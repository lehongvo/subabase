# IX Metaverse Contract System -- Phase 1 Smart Contract Architecture Design

| Item | Details |
| --- | --- |
| Document ID | IX-ARCH-SC-001 |
| Version | 1.0.0 |
| Created | 2026-03-23 |
| Target Chain | MegaETH |
| Solidity | ^0.8.27 |
| Framework | Hardhat + Foundry (dual) |
| OpenZeppelin | v5 |
| Upgradability | TransparentUpgradeableProxy + ProxyAdmin |

---

## 1. System Architecture Diagram

```
+---------------------------------------------------------------------+
|                        EXTERNAL ACTORS                               |
|  [Admin/Owner]     [Metaverse Server]     [Users A,B]     [Anyone]  |
+--------+------------------+------------------+---------------+------+
         |                  |                  |               |
         v                  v                  v               v
+---------------------------------------------------------------------+
|                      PROXY LAYER (TransparentUpgradeableProxy)       |
|  Each core contract deployed behind its own proxy + shared ProxyAdmin|
+---------------------------------------------------------------------+
         |                  |                  |               |
         v                  v                  v               v
+------------------+  +-------------------+  +-----------------+
| ContractTemplates|  | ContractInstances |  | ContractParties |
| (Registry)       |  | (Lifecycle FSM)   |  | (Escrow Mgmt)   |
| - CRUD templates |  | - create/activate |  | - join + escrow |
| - admin only     |  | - status machine  |  | - IERC20 holds  |
+--------+---------+  +----+---------+----+  +----+------+-----+
         |                  |         |            |      |
         |                  v         v            v      |
         |           +------+----+ +--+------------+-+    |
         |           |ContractResults| |ContractConsents|  |
         |           | - report   | | - consent/dispute|  |
         |           | - finalize | | - auto-timeout   |  |
         |           +------+-----+ +--------+---------+  |
         |                  |                 |            |
         v                  v                 v            v
+---------------------------------------------------------------------+
|                    ContractSettlements                                |
|  - calculates fee (FeeCalculator lib)                                |
|  - transfers IERC20 from escrow to winner + treasury                 |
|  - emits settlement events (on-chain public ledger)                  |
+---------------------------------------------------------------------+
         |
         v
+---------------------------------------------------------------------+
|                     SHARED DEPENDENCIES                              |
|                                                                      |
|  +------------+  +--------------+  +--------------+  +-------------+ |
|  | Types.sol  |  |FeeCalculator |  |StateValidator|  |TimeoutHelper| |
|  | enums,     |  |  .sol (lib)  |  |  .sol (lib)  |  |  .sol (lib) | |
|  | structs,   |  | fee math     |  | FSM checks   |  | deadline    | |
|  | errors     |  |              |  |              |  | logic       | |
|  +------------+  +--------------+  +--------------+  +-------------+ |
|                                                                      |
|  +------------+  +--------------+                                    |
|  |AccessRoles |  |EmergencyStop |   IERC20 (USDT on MegaETH)        |
|  |  .sol      |  |  .sol        |   SafeERC20 (OZ)                   |
|  | role bytes |  | global pause |                                    |
|  +------------+  +--------------+                                    |
+---------------------------------------------------------------------+

Cross-contract call graph:

  ContractTemplates  <----  ContractInstances (reads template on create)
  ContractInstances  <----  ContractParties   (reads status, party count)
  ContractInstances  <----  ContractResults   (reads status)
  ContractInstances  <----  ContractConsents  (reads status, parties)
  ContractInstances  <----  ContractSettlements (reads status, result)
  ContractParties    <----  ContractSettlements (reads escrow data)
  ContractResults    <----  ContractSettlements (reads winner)
  ContractConsents   <----  ContractSettlements (reads consent state)
  ContractConsents   <----  ContractInstances   (writes status on dispute)
  IERC20 (USDT)     <----  ContractParties (transferFrom for escrow)
  IERC20 (USDT)     <----  ContractSettlements (transfer for payouts)
```

---

## 2. File Structure

```
contracts/
├── interfaces/
│   ├── IContractTemplates.sol
│   ├── IContractInstances.sol
│   ├── IContractParties.sol
│   ├── IContractResults.sol
│   ├── IContractConsents.sol
│   └── IContractSettlements.sol
├── libraries/
│   ├── Types.sol              // All enums, structs, custom errors
│   ├── FeeCalculator.sol      // Fee math: basis-point arithmetic
│   ├── StateValidator.sol     // FSM transition validation
│   └── TimeoutHelper.sol      // Deadline / timeout utilities
├── security/
│   ├── AccessRoles.sol        // Role constants (bytes32)
│   └── EmergencyStop.sol      // Global + per-contract pause base
├── mocks/
│   └── MockIXToken.sol        // ERC-20 mock for testing
├── ContractTemplates.sol
├── ContractInstances.sol
├── ContractParties.sol
├── ContractResults.sol
├── ContractConsents.sol
└── ContractSettlements.sol
```

---

## 3. Inheritance & Interface Design

### 3.1 ContractTemplates

```
ContractTemplates
  ├─ Initializable                (OZ — upgradeable init guard)
  ├─ AccessControlUpgradeable     (OZ — ADMIN_ROLE for CRUD)
  ├─ PausableUpgradeable          (OZ — emergency stop)
  ├─ UUPSUpgradeable / Proxy      (deployed behind TransparentUpgradeableProxy)
  └─ IContractTemplates           (project interface)
```

Why each OZ contract:
- **AccessControlUpgradeable** -- only ADMIN_ROLE can create/update/deactivate templates.
- **PausableUpgradeable** -- freeze template creation during emergency.
- **Initializable** -- no constructor; `initialize()` sets roles and state.

### 3.2 ContractInstances

```
ContractInstances
  ├─ Initializable
  ├─ AccessControlUpgradeable     (SERVER_ROLE creates instances, ADMIN resolves disputes)
  ├─ PausableUpgradeable
  └─ IContractInstances
```

Why:
- **AccessControlUpgradeable** -- SERVER_ROLE (metaverse backend) creates instances; ADMIN_ROLE resolves disputes.
- **PausableUpgradeable** -- halt new instance creation.

### 3.3 ContractParties

```
ContractParties
  ├─ Initializable
  ├─ AccessControlUpgradeable     (SERVER_ROLE joins users)
  ├─ ReentrancyGuardUpgradeable   (OZ — escrow token transfers)
  ├─ PausableUpgradeable
  └─ IContractParties
```

Why:
- **ReentrancyGuardUpgradeable** -- this contract calls `IERC20.transferFrom` to collect escrow; reentrancy protection is mandatory.
- **AccessControlUpgradeable** -- SERVER_ROLE manages join flow.

### 3.4 ContractResults

```
ContractResults
  ├─ Initializable
  ├─ AccessControlUpgradeable     (SERVER_ROLE / ORACLE_ROLE reports results)
  ├─ PausableUpgradeable
  └─ IContractResults
```

Why:
- **AccessControlUpgradeable** -- only the game server (SERVER_ROLE) or oracle can submit results.

### 3.5 ContractConsents

```
ContractConsents
  ├─ Initializable
  ├─ AccessControlUpgradeable     (SERVER_ROLE for auto-consent; ADMIN_ROLE for dispute resolution)
  ├─ PausableUpgradeable
  └─ IContractConsents
```

Why:
- **AccessControlUpgradeable** -- users consent via server relay (Phase 1 front-running mitigation: off-chain game, on-chain settlement). Admin resolves disputes.

### 3.6 ContractSettlements

```
ContractSettlements
  ├─ Initializable
  ├─ AccessControlUpgradeable     (SETTLER_ROLE executes settlement)
  ├─ ReentrancyGuardUpgradeable   (OZ — token transfers out)
  ├─ PausableUpgradeable
  └─ IContractSettlements
```

Why:
- **ReentrancyGuardUpgradeable** -- transfers tokens to winner and treasury; must guard reentrancy.
- **AccessControlUpgradeable** -- only SETTLER_ROLE (automated or admin) can trigger settlement.

### 3.7 Upgradability Strategy

All 6 core contracts are deployed behind **TransparentUpgradeableProxy** instances, managed by a single **ProxyAdmin** contract (OZ v5). Core logic contracts use `Initializable` with `initializer` modifier instead of constructors. Storage layout must be append-only across upgrades.

---

## 4. Storage Layout (Per Contract)

### 4.1 ContractTemplates

```solidity
// --- State Variables ---
mapping(bytes32 => Types.Template) private _templates;       // templateId => Template
bytes32[] private _templateIds;                               // enumerable list
mapping(bytes32 => bool) private _templateExists;             // existence check
address private _instancesContract;                           // cross-ref

uint256[46] private __gap;  // upgrade safety gap
```

```solidity
// --- Struct (Types.sol) ---
struct Template {
    bytes32         id;                 // 32 bytes  | slot 0
    ContractType    contractType;       // 1 byte    | slot 1 (packed below)
    PaymentType     paymentType;        // 1 byte    |
    ChainRecordPolicy chainRecordPolicy;// 1 byte    |
    bool            isActive;           // 1 byte    |
    uint16          feeRateBps;         // 2 bytes   | (basis points, max 10000 = 100%)
    address         createdBy;          // 20 bytes  | total = 26 bytes => fits slot 1
    bytes32         metaverseEventId;   // 32 bytes  | slot 2
    bytes           conditions;         // dynamic   | slot 3 (pointer)
    bytes           rewardRules;        // dynamic   | slot 4 (pointer)
    string          name;               // dynamic   | slot 5 (pointer)
    uint48          createdAt;          // 6 bytes   | slot 6 (packed below)
    uint48          updatedAt;          // 6 bytes   | 12 bytes total => fits slot 6
}
```

**Packing notes**: `contractType + paymentType + chainRecordPolicy + isActive + feeRateBps + createdBy` = 1+1+1+1+2+20 = 26 bytes, fits in one 32-byte slot. `createdAt + updatedAt` = 6+6 = 12 bytes, fits in one slot.

### 4.2 ContractInstances

```solidity
// --- State Variables ---
mapping(bytes32 => Types.Instance) private _instances;       // instanceId => Instance
bytes32[] private _instanceIds;
mapping(bytes32 => bool) private _instanceExists;

address private _templatesContract;
address private _partiesContract;
address private _resultsContract;
address private _consentsContract;
address private _settlementsContract;

uint256[43] private __gap;
```

```solidity
struct Instance {
    bytes32         id;             // 32 bytes  | slot 0
    bytes32         templateId;     // 32 bytes  | slot 1
    ContractStatus  status;         // 1 byte    | slot 2 (packed below)
    bool            chainRecord;    // 1 byte    |
    uint48          createdAt;      // 6 bytes   |
    uint48          settledAt;      // 6 bytes   |
    uint48          activatedAt;    // 6 bytes   |
    uint48          completedAt;    // 6 bytes   | total = 28 bytes => fits slot 2
    bytes           metadata;       // dynamic   | slot 3 (pointer) -- room_id, session etc.
    bytes32         txHash;         // 32 bytes  | slot 4
}
```

**Packing**: `status(1) + chainRecord(1) + createdAt(6) + settledAt(6) + activatedAt(6) + completedAt(6)` = 26 bytes in one slot.

### 4.3 ContractParties

```solidity
// --- State Variables ---
mapping(bytes32 => Types.Party[]) private _parties;         // instanceId => Party[]
mapping(bytes32 => mapping(address => bool)) private _hasJoined; // instanceId => user => bool
mapping(bytes32 => uint8) private _partyCount;              // instanceId => count

address private _instancesContract;
address private _settlementsContract;
IERC20  private _paymentToken;       // USDT on MegaETH
address private _escrowVault;        // address holding escrowed tokens (can be this contract)

uint256[44] private __gap;
```

```solidity
struct Party {
    bytes32         id;             // 32 bytes  | slot 0
    bytes32         contractId;     // 32 bytes  | slot 1
    address         userId;         // 20 bytes  | slot 2 (packed below)
    EscrowStatus    escrowStatus;   // 1 byte    |
    PointType       escrowType;     // 1 byte    |
    uint48          joinedAt;       // 6 bytes   | total = 28 bytes => fits slot 2
    uint128         escrowAmount;   // 16 bytes  | slot 3 (packed below)
    bytes32         role;           // 32 bytes  | slot 4  (keccak256 of role string)
}
```

**Packing**: `userId(20) + escrowStatus(1) + escrowType(1) + joinedAt(6)` = 28 bytes in one slot.

### 4.4 ContractResults

```solidity
// --- State Variables ---
mapping(bytes32 => Types.Result) private _results;          // instanceId => Result
mapping(bytes32 => bool) private _resultExists;

address private _instancesContract;

uint256[47] private __gap;
```

```solidity
struct Result {
    bytes32         id;             // 32 bytes  | slot 0
    bytes32         contractId;     // 32 bytes  | slot 1
    ResultSource    reportedBy;     // 1 byte    | slot 2 (packed below)
    bool            isFinal;        // 1 byte    |
    uint48          reportedAt;     // 6 bytes   | total = 8 bytes => fits slot 2
    bytes           resultData;     // dynamic   | slot 3 (pointer) -- ABI-encoded winner, moves, score
}
```

### 4.5 ContractConsents

```solidity
// --- State Variables ---
mapping(bytes32 => mapping(address => Types.Consent)) private _consents; // instanceId => user => Consent
mapping(bytes32 => uint8) private _consentCount;           // instanceId => consented count
mapping(bytes32 => bool) private _hasDispute;              // instanceId => dispute flag

address private _instancesContract;
address private _partiesContract;

uint256[45] private __gap;
```

```solidity
struct Consent {
    bytes32         id;             // 32 bytes  | slot 0
    bytes32         contractId;     // 32 bytes  | slot 1
    address         userId;         // 20 bytes  | slot 2 (packed below)
    bool            consented;      // 1 byte    |
    uint48          consentedAt;    // 6 bytes   | total = 27 bytes => fits slot 2
    bytes           signature;      // dynamic   | slot 3 (pointer) -- wallet signature
    string          reason;         // dynamic   | slot 4 (pointer) -- dispute reason
}
```

### 4.6 ContractSettlements

```solidity
// --- State Variables ---
mapping(bytes32 => Types.Settlement[]) private _settlements; // instanceId => Settlement[]
mapping(bytes32 => bool) private _isSettled;                // instanceId => settled flag

address private _instancesContract;
address private _partiesContract;
address private _resultsContract;
address private _consentsContract;
IERC20  private _paymentToken;      // USDT on MegaETH
address private _treasury;          // Treasury address (00..0001)

uint256[42] private __gap;
```

```solidity
struct Settlement {
    bytes32         id;             // 32 bytes  | slot 0
    bytes32         contractId;     // 32 bytes  | slot 1
    address         fromUserId;     // 20 bytes  | slot 2 (packed below)
    SettlementType  settlementType; // 1 byte    |
    PointType       pointType;      // 1 byte    |
    uint48          settledAt;      // 6 bytes   | total = 28 bytes => fits slot 2
    address         toUserId;       // 20 bytes  | slot 3 (packed below)
    // 12 bytes free in slot 3
    uint128         amount;         // 16 bytes  | slot 4 (packed below)
    uint128         feeAmount;      // 16 bytes  | total = 32 bytes => fits slot 4
    bytes32         txHash;         // 32 bytes  | slot 5
}
```

**Packing**: `amount + feeAmount` = 16+16 = 32 bytes, exactly one slot. Max representable: 2^128 - 1 (~3.4e38) which far exceeds any realistic token amount.

---

## 5. Enum Definitions (All in Types.sol)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @notice All shared types for IX Metaverse Contract System
library Types {

    // ========== ENUMS (1:1 mapping to Phase 0 DB ENUMs) ==========

    /// @notice Maps to DB: contract_type
    /// rps=0, work_reward=1, tournament=2, custom=3
    enum ContractType {
        RPS,            // 0
        WorkReward,     // 1
        Tournament,     // 2
        Custom          // 3
    }

    /// @notice Maps to DB: contract_status
    /// created=0, active=1, completed=2, disputed=3, resolved=4, settled=5
    enum ContractStatus {
        Created,        // 0
        Active,         // 1
        Completed,      // 2
        Disputed,       // 3
        Resolved,       // 4
        Settled         // 5
    }

    /// @notice Maps to DB: payment_type
    /// ix_point=0, ix_free_point=1, both=2
    enum PaymentType {
        IxPoint,        // 0
        IxFreePoint,    // 1
        Both            // 2
    }

    /// @notice Maps to DB: point_type (used in settlements and escrow)
    /// ix_point=0, ix_free_point=1
    enum PointType {
        IxPoint,        // 0
        IxFreePoint     // 1
    }

    /// @notice Maps to DB: chain_record_policy
    /// required=0, optional=1, off=2
    enum ChainRecordPolicy {
        Required,       // 0
        Optional,       // 1
        Off             // 2
    }

    /// @notice Maps to DB: result_source (reported_by)
    /// system=0, user=1
    enum ResultSource {
        System,         // 0
        User            // 1
    }

    /// @notice Maps to DB: settlement_type
    /// reward=0, fee=1, refund=2
    enum SettlementType {
        Reward,         // 0
        Fee,            // 1
        Refund          // 2
    }

    /// @notice Maps to DB: escrow_status
    /// held=0, released=1, refunded=2
    enum EscrowStatus {
        Held,           // 0
        Released,       // 1
        Refunded        // 2
    }

    // ========== STRUCTS ==========
    // (See Section 4 for full struct definitions with packing notes)

    struct Template { ... }
    struct Instance { ... }
    struct Party    { ... }
    struct Result   { ... }
    struct Consent  { ... }
    struct Settlement { ... }
}
```

---

## 6. Complete Function Signatures

### 6.1 ContractTemplates

```solidity
interface IContractTemplates {

    // ---- Write Functions ----

    /// @notice Initialize the contract (proxy pattern, replaces constructor)
    /// @dev Maps to: admin setup
    function initialize(address defaultAdmin) external; // initializer

    /// @notice Create a new contract template
    /// @dev Maps to: INSERT INTO contract_templates
    /// @param name Template name
    /// @param contractType RPS, WorkReward, Tournament, Custom
    /// @param conditions ABI-encoded condition data (min_bet, max_bet, rounds, timeout)
    /// @param rewardRules ABI-encoded reward rules (winner_pct, draw_refund)
    /// @param paymentType IxPoint, IxFreePoint, Both
    /// @param feeRateBps Fee rate in basis points (300 = 3%)
    /// @param chainRecordPolicy Required, Optional, Off
    /// @param metaverseEventId Linked metaverse event identifier
    /// @return templateId The generated template ID
    function createTemplate(
        string calldata name,
        Types.ContractType contractType,
        bytes calldata conditions,
        bytes calldata rewardRules,
        Types.PaymentType paymentType,
        uint16 feeRateBps,
        Types.ChainRecordPolicy chainRecordPolicy,
        bytes32 metaverseEventId
    ) external returns (bytes32 templateId);
    // Access: onlyRole(ADMIN_ROLE) whenNotPaused
    // Mutability: state-changing

    /// @notice Update an existing template
    /// @dev Maps to: UPDATE contract_templates SET ...
    function updateTemplate(
        bytes32 templateId,
        string calldata name,
        bytes calldata conditions,
        bytes calldata rewardRules,
        Types.PaymentType paymentType,
        uint16 feeRateBps,
        Types.ChainRecordPolicy chainRecordPolicy,
        bytes32 metaverseEventId
    ) external;
    // Access: onlyRole(ADMIN_ROLE) whenNotPaused

    /// @notice Activate or deactivate a template
    /// @dev Maps to: UPDATE contract_templates SET is_active = ...
    function setTemplateActive(bytes32 templateId, bool isActive) external;
    // Access: onlyRole(ADMIN_ROLE) whenNotPaused

    /// @notice Set cross-contract reference to ContractInstances
    function setInstancesContract(address instancesContract) external;
    // Access: onlyRole(DEFAULT_ADMIN_ROLE)

    // ---- Read Functions ----

    /// @notice Get a template by ID
    /// @dev Maps to: SELECT * FROM contract_templates WHERE id = ...
    function getTemplate(bytes32 templateId)
        external view returns (Types.Template memory);

    /// @notice Get all active templates of a given type
    /// @dev Maps to: SELECT * FROM contract_templates WHERE type = ... AND is_active = true
    function getActiveTemplatesByType(Types.ContractType contractType)
        external view returns (Types.Template[] memory);

    /// @notice Check if template exists and is active
    function isTemplateActive(bytes32 templateId)
        external view returns (bool);

    /// @notice Get total template count
    function getTemplateCount() external view returns (uint256);

    /// @notice Get template fee rate
    function getTemplateFeeRate(bytes32 templateId)
        external view returns (uint16 feeRateBps);
}
```

### 6.2 ContractInstances

```solidity
interface IContractInstances {

    function initialize(
        address defaultAdmin,
        address templatesContract
    ) external; // initializer

    /// @notice Create a new contract instance from a template
    /// @dev Maps to: RPC create_contract(p_template_id, p_metadata)
    /// @param templateId FK to contract_templates
    /// @param metadata ABI-encoded metadata (room_id, session, etc.)
    /// @param chainRecord Whether this instance records on-chain
    /// @return instanceId The generated instance ID
    function createInstance(
        bytes32 templateId,
        bytes calldata metadata,
        bool chainRecord
    ) external returns (bytes32 instanceId);
    // Access: onlyRole(SERVER_ROLE) whenNotPaused

    /// @notice Transition: Created -> Active
    /// @dev Maps to: RPC activate_contract(p_contract_id)
    function activateInstance(bytes32 instanceId) external;
    // Access: onlyRole(SERVER_ROLE) whenNotPaused

    /// @notice Transition: Active -> Completed
    /// @dev Maps to: PATCH contract_instances SET status='completed'
    function completeInstance(bytes32 instanceId) external;
    // Access: onlyRole(SERVER_ROLE) whenNotPaused

    /// @notice Transition: Completed -> Disputed
    /// @dev Maps to: PATCH contract_instances SET status='disputed'
    function disputeInstance(bytes32 instanceId) external;
    // Access: onlyRole(SERVER_ROLE) or onlyRole(ADMIN_ROLE) whenNotPaused

    /// @notice Transition: Disputed -> Resolved
    /// @dev Maps to: PATCH contract_instances SET status='resolved'
    function resolveInstance(bytes32 instanceId) external;
    // Access: onlyRole(ADMIN_ROLE) whenNotPaused

    /// @notice Transition: Completed/Resolved -> Settled
    /// @dev Maps to: settle_contract marks settled_at
    function settleInstance(bytes32 instanceId) external;
    // Access: onlyRole(SETTLER_ROLE) whenNotPaused

    /// @notice Set the on-chain tx hash after settlement broadcast
    function setTxHash(bytes32 instanceId, bytes32 txHash) external;
    // Access: onlyRole(SERVER_ROLE)

    // ---- Cross-contract setters ----
    function setPartiesContract(address addr) external;   // DEFAULT_ADMIN_ROLE
    function setResultsContract(address addr) external;   // DEFAULT_ADMIN_ROLE
    function setConsentsContract(address addr) external;   // DEFAULT_ADMIN_ROLE
    function setSettlementsContract(address addr) external; // DEFAULT_ADMIN_ROLE

    // ---- Read Functions ----

    function getInstance(bytes32 instanceId)
        external view returns (Types.Instance memory);

    function getInstanceStatus(bytes32 instanceId)
        external view returns (Types.ContractStatus);

    function getInstanceTemplateId(bytes32 instanceId)
        external view returns (bytes32);

    function instanceExists(bytes32 instanceId)
        external view returns (bool);
}
```

### 6.3 ContractParties

```solidity
interface IContractParties {

    function initialize(
        address defaultAdmin,
        address instancesContract,
        address paymentToken,
        address escrowVault
    ) external; // initializer

    /// @notice A user joins a contract instance with escrow deposit
    /// @dev Maps to: RPC join_contract(p_contract_id, p_user_id, p_role, p_escrow_amount, p_escrow_type)
    ///      Calls IERC20.transferFrom(user, escrowVault, amount)
    /// @param instanceId FK to contract_instances
    /// @param userId The user's address (wallet)
    /// @param role keccak256 of role string ("challenger", "opponent", etc.)
    /// @param escrowAmount Amount to escrow (in token smallest unit)
    /// @param escrowType IxPoint or IxFreePoint
    function joinContract(
        bytes32 instanceId,
        address userId,
        bytes32 role,
        uint128 escrowAmount,
        Types.PointType escrowType
    ) external;
    // Access: onlyRole(SERVER_ROLE) whenNotPaused nonReentrant

    /// @notice Release escrow (mark as released) after settlement
    /// @dev Called by ContractSettlements during settle flow
    function releaseEscrow(bytes32 instanceId, address userId) external;
    // Access: onlyRole(SETTLER_ROLE)

    /// @notice Refund escrow back to user (dispute resolution / cancellation)
    function refundEscrow(bytes32 instanceId, address userId) external;
    // Access: onlyRole(ADMIN_ROLE) nonReentrant

    /// @notice Set settlement contract reference
    function setSettlementsContract(address addr) external;
    // Access: DEFAULT_ADMIN_ROLE

    // ---- Read Functions ----

    function getParties(bytes32 instanceId)
        external view returns (Types.Party[] memory);

    function getParty(bytes32 instanceId, address userId)
        external view returns (Types.Party memory);

    function getPartyCount(bytes32 instanceId)
        external view returns (uint8);

    function hasJoined(bytes32 instanceId, address userId)
        external view returns (bool);

    function getTotalEscrow(bytes32 instanceId)
        external view returns (uint128 totalAmount);
}
```

### 6.4 ContractResults

```solidity
interface IContractResults {

    function initialize(
        address defaultAdmin,
        address instancesContract
    ) external; // initializer

    /// @notice Report the result of a contract
    /// @dev Maps to: POST /contract_results + PATCH status='completed'
    /// @param instanceId FK to contract_instances
    /// @param resultData ABI-encoded result (winner_id, winner_move, loser_move, score, is_draw)
    /// @param reportedBy System or User
    /// @param isFinal Whether result is immediately final
    function reportResult(
        bytes32 instanceId,
        bytes calldata resultData,
        Types.ResultSource reportedBy,
        bool isFinal
    ) external;
    // Access: onlyRole(SERVER_ROLE) whenNotPaused

    /// @notice Admin overrides a result (dispute resolution)
    /// @dev Maps to: admin dispute resolution flow
    function overrideResult(
        bytes32 instanceId,
        bytes calldata resultData
    ) external;
    // Access: onlyRole(ADMIN_ROLE) whenNotPaused

    // ---- Read Functions ----

    function getResult(bytes32 instanceId)
        external view returns (Types.Result memory);

    function resultExists(bytes32 instanceId)
        external view returns (bool);

    function isResultFinal(bytes32 instanceId)
        external view returns (bool);
}
```

### 6.5 ContractConsents

```solidity
interface IContractConsents {

    function initialize(
        address defaultAdmin,
        address instancesContract,
        address partiesContract
    ) external; // initializer

    /// @notice A party submits consent or objection
    /// @dev Maps to: POST /contract_consents
    /// @param instanceId FK to contract_instances
    /// @param userId The consenting user's address
    /// @param consented true = consent, false = dispute
    /// @param signature Wallet signature (EIP-712 or raw bytes)
    /// @param reason Dispute reason (empty if consented=true)
    function submitConsent(
        bytes32 instanceId,
        address userId,
        bool consented,
        bytes calldata signature,
        string calldata reason
    ) external;
    // Access: onlyRole(SERVER_ROLE) whenNotPaused

    /// @notice Auto-consent after timeout expiry
    /// @dev Maps to: timeout_seconds auto-accept logic
    /// @param instanceId FK to contract_instances
    /// @param userId The user whose consent timed out
    function autoConsent(bytes32 instanceId, address userId) external;
    // Access: onlyRole(SERVER_ROLE) whenNotPaused

    /// @notice Check if all parties have consented
    function allConsented(bytes32 instanceId) external view returns (bool);

    /// @notice Check if instance has a dispute
    function hasDispute(bytes32 instanceId) external view returns (bool);

    // ---- Read Functions ----

    function getConsent(bytes32 instanceId, address userId)
        external view returns (Types.Consent memory);

    function getConsentCount(bytes32 instanceId)
        external view returns (uint8);
}
```

### 6.6 ContractSettlements

```solidity
interface IContractSettlements {

    function initialize(
        address defaultAdmin,
        address instancesContract,
        address partiesContract,
        address resultsContract,
        address consentsContract,
        address paymentToken,
        address treasury
    ) external; // initializer

    /// @notice Execute full settlement for a contract instance
    /// @dev Maps to: RPC settle_contract(p_contract_id)
    ///      1. Reads result to determine winner
    ///      2. Reads template fee rate via instance->template
    ///      3. Calculates fee (FeeCalculator)
    ///      4. Transfers reward to winner, fee to treasury
    ///      5. Marks escrow as released
    ///      6. Transitions instance to Settled
    /// @param instanceId FK to contract_instances
    function settleContract(bytes32 instanceId) external;
    // Access: onlyRole(SETTLER_ROLE) whenNotPaused nonReentrant

    /// @notice Execute refund settlement (draw or cancelled)
    /// @dev All escrowed amounts returned to parties
    function refundContract(bytes32 instanceId) external;
    // Access: onlyRole(SETTLER_ROLE) or onlyRole(ADMIN_ROLE) whenNotPaused nonReentrant

    /// @notice Set treasury address
    function setTreasury(address treasury) external;
    // Access: DEFAULT_ADMIN_ROLE

    // ---- Read Functions ----

    function getSettlements(bytes32 instanceId)
        external view returns (Types.Settlement[] memory);

    function isSettled(bytes32 instanceId)
        external view returns (bool);

    function getSettlementCount(bytes32 instanceId)
        external view returns (uint256);
}
```

### 6.7 Cross-Contract Call Sequence: Full RPS Lifecycle (11 Steps)

```
Step  Action                  Contract Called           Function                    Caller
─────────────────────────────────────────────────────────────────────────────────────────────
 1    Find template           ContractTemplates         getActiveTemplatesByType()  Server (view)
 2    Create instance         ContractInstances         createInstance()            Server
      └─ validates            ContractTemplates         isTemplateActive()          (internal call)
 3a   Player A joins+escrow   ContractParties           joinContract()              Server
      └─ collects token       IERC20 (USDT)             transferFrom(A, vault, 50)  (internal call)
      └─ validates instance   ContractInstances         getInstanceStatus()         (internal call)
 3b   Player B joins+escrow   ContractParties           joinContract()              Server
      └─ collects token       IERC20 (USDT)             transferFrom(B, vault, 50)  (internal call)
 3c   Activate contract       ContractInstances         activateInstance()          Server
      └─ validates 2 parties  ContractParties           getPartyCount()             (internal call)
 4    Report result           ContractResults           reportResult()              Game Server
      └─ validates status     ContractInstances         getInstanceStatus()         (internal call)
 4b   Mark completed          ContractInstances         completeInstance()          Game Server
 5a   A consents              ContractConsents          submitConsent(A, true)      Server
      └─ validates party      ContractParties           hasJoined()                 (internal call)
 5b   B consents              ContractConsents          submitConsent(B, true)      Server
      └─ checks all consented ContractConsents          allConsented()              (internal read)
 6    Settle contract         ContractSettlements       settleContract()            Server/Auto
      └─ reads result         ContractResults           getResult()                 (internal call)
      └─ reads fee rate       ContractTemplates         getTemplateFeeRate()        (internal call)
      └─ reads parties        ContractParties           getParties()                (internal call)
      └─ checks consent       ContractConsents          allConsented()              (internal call)
      └─ calculates fee       FeeCalculator             calculateFee()              (library call)
      └─ transfers reward     IERC20 (USDT)             transfer(winner, 97)        (internal call)
      └─ transfers fee        IERC20 (USDT)             transfer(treasury, 3)       (internal call)
      └─ releases escrow      ContractParties           releaseEscrow()             (internal call)
      └─ marks settled        ContractInstances         settleInstance()            (internal call)
 7    Public ledger           (All contracts)           get*() view functions        Anyone
```

**Dispute branch (replaces steps 5a onward when A objects):**

```
Step  Action                  Contract Called           Function
───────────────────────────────────────────────────────────────────
 5a'  A disputes              ContractConsents          submitConsent(A, false, reason)
      └─ flags dispute        ContractInstances         disputeInstance()
 5b'  Admin reviews           (off-chain)
 5c'  Admin resolves          ContractResults           overrideResult()
      └─ resolves instance    ContractInstances         resolveInstance()
 6'   Settle after resolve    ContractSettlements       settleContract()
      (same as step 6 above)
```

---

## 7. Event Definitions (Complete)

### 7.1 ContractTemplates Events

```solidity
/// @notice Emitted when a new template is created
event TemplateCreated(
    bytes32 indexed templateId,
    Types.ContractType indexed contractType,
    address indexed createdBy,
    string name,
    uint16 feeRateBps,
    Types.ChainRecordPolicy chainRecordPolicy
);

/// @notice Emitted when a template is updated
event TemplateUpdated(
    bytes32 indexed templateId,
    uint16 feeRateBps,
    Types.ChainRecordPolicy chainRecordPolicy,
    uint48 updatedAt
);

/// @notice Emitted when a template is activated or deactivated
event TemplateActiveChanged(
    bytes32 indexed templateId,
    bool isActive
);
```

### 7.2 ContractInstances Events

```solidity
/// @notice Emitted when a new instance is created
event InstanceCreated(
    bytes32 indexed instanceId,
    bytes32 indexed templateId,
    bool chainRecord,
    uint48 createdAt
);

/// @notice Emitted on every status transition
event InstanceStatusChanged(
    bytes32 indexed instanceId,
    Types.ContractStatus indexed oldStatus,
    Types.ContractStatus indexed newStatus,
    uint48 timestamp
);

/// @notice Emitted when tx_hash is set after on-chain recording
event InstanceTxHashSet(
    bytes32 indexed instanceId,
    bytes32 txHash
);
```

### 7.3 ContractParties Events

```solidity
/// @notice Emitted when a party joins a contract with escrow
event PartyJoined(
    bytes32 indexed instanceId,
    address indexed userId,
    bytes32 role,
    uint128 escrowAmount,
    Types.PointType escrowType,
    uint48 joinedAt
);

/// @notice Emitted when escrow is released after settlement
event EscrowReleased(
    bytes32 indexed instanceId,
    address indexed userId,
    uint128 amount
);

/// @notice Emitted when escrow is refunded
event EscrowRefunded(
    bytes32 indexed instanceId,
    address indexed userId,
    uint128 amount
);
```

### 7.4 ContractResults Events

```solidity
/// @notice Emitted when a result is reported
event ResultReported(
    bytes32 indexed instanceId,
    Types.ResultSource indexed reportedBy,
    bool isFinal,
    bytes resultData,
    uint48 reportedAt
);

/// @notice Emitted when a result is overridden by admin
event ResultOverridden(
    bytes32 indexed instanceId,
    bytes oldResultData,
    bytes newResultData,
    uint48 overriddenAt
);
```

### 7.5 ContractConsents Events

```solidity
/// @notice Emitted when a party submits consent
event ConsentSubmitted(
    bytes32 indexed instanceId,
    address indexed userId,
    bool consented,
    uint48 consentedAt
);

/// @notice Emitted when consent is granted automatically after timeout
event AutoConsentApplied(
    bytes32 indexed instanceId,
    address indexed userId,
    uint48 appliedAt
);

/// @notice Emitted when a dispute is raised
event DisputeRaised(
    bytes32 indexed instanceId,
    address indexed userId,
    string reason,
    uint48 disputedAt
);
```

### 7.6 ContractSettlements Events

```solidity
/// @notice Emitted for each settlement transfer (reward or fee)
event SettlementExecuted(
    bytes32 indexed instanceId,
    address indexed fromUserId,
    address indexed toUserId,
    uint128 amount,
    uint128 feeAmount,
    Types.SettlementType settlementType,
    Types.PointType pointType,
    uint48 settledAt
);

/// @notice Emitted when a full contract settlement is completed
event ContractSettled(
    bytes32 indexed instanceId,
    uint128 totalAmount,
    uint128 totalFees,
    uint48 settledAt
);

/// @notice Emitted when a contract is refunded (draw / cancellation)
event ContractRefunded(
    bytes32 indexed instanceId,
    uint128 totalRefunded,
    uint48 refundedAt
);
```

---

## 8. Custom Errors (Types.sol)

```solidity
library Types {

    // ========== TEMPLATE ERRORS ==========
    error TemplateNotFound(bytes32 templateId);
    error TemplateNotActive(bytes32 templateId);
    error TemplateAlreadyExists(bytes32 templateId);
    error InvalidFeeRate(uint16 feeRateBps);            // feeRateBps > 10000

    // ========== INSTANCE ERRORS ==========
    error InstanceNotFound(bytes32 instanceId);
    error InstanceAlreadyExists(bytes32 instanceId);
    error InvalidStatusTransition(
        bytes32 instanceId,
        ContractStatus currentStatus,
        ContractStatus targetStatus
    );
    error InstanceAlreadySettled(bytes32 instanceId);

    // ========== PARTY ERRORS ==========
    error PartyAlreadyJoined(bytes32 instanceId, address userId);
    error PartyNotFound(bytes32 instanceId, address userId);
    error MaxPartiesReached(bytes32 instanceId, uint8 maxParties);
    error InsufficientEscrow(uint128 required, uint128 provided);
    error EscrowNotHeld(bytes32 instanceId, address userId);
    error InvalidEscrowAmount();                         // amount == 0
    error EscrowTransferFailed(address from, uint128 amount);

    // ========== RESULT ERRORS ==========
    error ResultAlreadyReported(bytes32 instanceId);
    error ResultNotFound(bytes32 instanceId);
    error ResultNotFinal(bytes32 instanceId);
    error InvalidResultData();

    // ========== CONSENT ERRORS ==========
    error ConsentAlreadySubmitted(bytes32 instanceId, address userId);
    error ConsentNotFromParty(bytes32 instanceId, address userId);
    error AllConsentsNotReceived(bytes32 instanceId);
    error DisputeAlreadyRaised(bytes32 instanceId);

    // ========== SETTLEMENT ERRORS ==========
    error SettlementAlreadyDone(bytes32 instanceId);
    error SettlementTransferFailed(address to, uint128 amount);
    error InvalidTreasuryAddress();
    error ConsentsIncomplete(bytes32 instanceId);

    // ========== GENERAL ERRORS ==========
    error ZeroAddress();
    error Unauthorized(address caller, bytes32 requiredRole);
    error ContractPaused();
    error InvalidContractReference(string contractName);
}
```

---

## 9. Security Architecture

### 9.1 Access Control Matrix

| Function | DEFAULT_ADMIN | ADMIN_ROLE | SERVER_ROLE | SETTLER_ROLE | ORACLE_ROLE | Anyone |
|---|---|---|---|---|---|---|
| **Templates: CRUD** | | X | | | | |
| **Templates: read** | | | | | | X (view) |
| **Instances: create** | | | X | | | |
| **Instances: activate/complete** | | | X | | | |
| **Instances: dispute** | | X | X | | | |
| **Instances: resolve** | | X | | | | |
| **Instances: settle (status)** | | | | X | | |
| **Parties: join** | | | X | | | |
| **Parties: refund** | | X | | | | |
| **Parties: release** | | | | X | | |
| **Results: report** | | | X | | X | |
| **Results: override** | | X | | | | |
| **Consents: submit** | | | X | | | |
| **Consents: autoConsent** | | | X | | | |
| **Settlements: settle** | | | | X | | |
| **Settlements: refund** | | X | | X | | |
| **Set contract refs** | X | | | | | |
| **Pause / unpause** | X | X | | | | |
| **Upgrade proxy** | X (ProxyAdmin) | | | | | |
| **All view functions** | | | | | | X |

Role constants (AccessRoles.sol):

```solidity
bytes32 constant ADMIN_ROLE   = keccak256("ADMIN_ROLE");
bytes32 constant SERVER_ROLE  = keccak256("SERVER_ROLE");
bytes32 constant SETTLER_ROLE = keccak256("SETTLER_ROLE");
bytes32 constant ORACLE_ROLE  = keccak256("ORACLE_ROLE");
```

### 9.2 Reentrancy Protection Points

| Contract | Protected Functions | Reason |
|---|---|---|
| ContractParties | `joinContract()` | Calls `IERC20.transferFrom()` to collect escrow |
| ContractParties | `refundEscrow()` | Calls `IERC20.transfer()` to return escrow |
| ContractSettlements | `settleContract()` | Calls `IERC20.transfer()` twice (winner + treasury) |
| ContractSettlements | `refundContract()` | Calls `IERC20.transfer()` for each party |

All token interactions use OpenZeppelin `SafeERC20` to handle non-standard ERC-20 tokens (like USDT which returns no bool).

### 9.3 Front-Running Mitigation

**Phase 1 strategy for RPS**: The game is played **off-chain** on the metaverse server. Only the settlement is recorded on-chain. This eliminates the classic commit-reveal problem entirely:

1. Players choose moves in the metaverse client (off-chain).
2. The metaverse server determines the result (off-chain).
3. Only the result and settlement are submitted on-chain via SERVER_ROLE.

No player move data is ever in the mempool, so front-running is not possible for the game itself. Settlement transactions are protected by role-based access (only SERVER_ROLE/SETTLER_ROLE can call).

For future phases where moves might be on-chain, a commit-reveal scheme can be added:
- Phase A: `commitMove(bytes32 hash)` where `hash = keccak256(abi.encodePacked(move, salt))`
- Phase B: `revealMove(uint8 move, bytes32 salt)` after both commits are in

### 9.4 Pausable Strategy

**Global pause**: The DEFAULT_ADMIN_ROLE or ADMIN_ROLE can pause any individual contract via its inherited `_pause()` function. All state-changing functions use `whenNotPaused`.

**Per-contract granularity**: Each of the 6 contracts has its own `Pausable` state. This allows surgical intervention:
- Pause only `ContractSettlements` if a settlement bug is found, while still allowing new games to start.
- Pause only `ContractTemplates` to freeze template changes during an audit.

**Emergency sequence**:
1. Pause affected contract(s).
2. Investigate and prepare upgrade.
3. Deploy new implementation via ProxyAdmin.
4. Unpause.

### 9.5 Integer Safety

Solidity 0.8.27 has built-in overflow/underflow checks. Additionally:
- `uint128` for all monetary amounts (max ~3.4e38, sufficient for any token).
- `uint48` for timestamps (max year 8,921,556 -- sufficient).
- `uint16` for fee rate in basis points (max 65535, but capped at 10000 = 100% in validation).
- Basis-point arithmetic avoids floating-point; `fee = amount * feeRateBps / 10000`.

---

## 10. Gas Optimization Strategy

### 10.1 Storage Packing for Structs

All structs are designed with explicit packing (see Section 4). Key savings:

| Struct | Naive slots | Packed slots | Savings |
|---|---|---|---|
| Template | ~10 | 6 + dynamic | ~40% |
| Instance | ~8 | 4 + dynamic | ~50% |
| Party | ~6 | 4 | ~33% |
| Settlement | ~7 | 5 | ~29% |

### 10.2 Events for Data Not Needed On-Chain

The following data is emitted via events only (not stored in contract state), since it is only needed for the public ledger / indexing:
- Full `resultData` bytes (stored in events; on-chain only the `Result` struct with pointer is stored).
- Historical status transitions (each transition emits `InstanceStatusChanged`; only current status is stored).
- Settlement details are stored but also emitted for easy off-chain indexing.

### 10.3 calldata vs memory

- All external function parameters that are `bytes` or `string` use `calldata` (cheaper than `memory` for external calls).
- Internal functions that need to modify data use `memory`.
- View functions returning structs use `memory` in the return type.

### 10.4 Cache Storage Reads

```solidity
// BAD: reads _instances[id] from storage multiple times
function example(bytes32 id) external {
    require(_instances[id].status == ContractStatus.Active);
    emit Event(_instances[id].templateId);
    _instances[id].status = ContractStatus.Completed;
}

// GOOD: single SLOAD, modify in memory, single SSTORE
function example(bytes32 id) external {
    Types.Instance storage inst = _instances[id];
    Types.ContractStatus currentStatus = inst.status;
    require(currentStatus == Types.ContractStatus.Active);
    emit Event(inst.templateId);
    inst.status = Types.ContractStatus.Completed;
}
```

### 10.5 Additional Optimizations

- **bytes32 for IDs** instead of `uint256` counters -- enables deterministic ID generation via `keccak256(abi.encodePacked(templateId, block.timestamp, msg.sender))`.
- **bytes32 for roles** (e.g., `keccak256("challenger")`) instead of `string` -- saves storage and enables efficient comparison.
- **Minimal cross-contract calls**: The `settleContract` function is the most expensive (5+ cross-contract calls). Caching results in local variables minimizes redundant calls.
- **Short-circuit validation**: Check cheapest conditions first (e.g., `instanceExists` before reading full struct).

---

## 11. Deployment Architecture

### 11.1 Deployment Order with Dependencies

```
Phase   Contract                 Dependencies (must exist first)
──────────────────────────────────────────────────────────────────
  1     ProxyAdmin               none
  2     Types.sol (library)      none (linked at compile time)
  3     FeeCalculator (library)  Types.sol
  4     StateValidator (library) Types.sol
  5     TimeoutHelper (library)  none
  6     ContractTemplates        none
        └─ deploy implementation
        └─ deploy TransparentUpgradeableProxy(impl, proxyAdmin, initData)
        └─ call initialize(deployer)
  7     ContractInstances        ContractTemplates (address)
        └─ deploy impl + proxy
        └─ call initialize(deployer, templatesProxy)
  8     ContractParties          ContractInstances (address), IERC20 (USDT address)
        └─ deploy impl + proxy
        └─ call initialize(deployer, instancesProxy, usdtAddress, escrowVault)
  9     ContractResults          ContractInstances (address)
        └─ deploy impl + proxy
        └─ call initialize(deployer, instancesProxy)
 10     ContractConsents         ContractInstances, ContractParties (addresses)
        └─ deploy impl + proxy
        └─ call initialize(deployer, instancesProxy, partiesProxy)
 11     ContractSettlements      All others + IERC20 + Treasury
        └─ deploy impl + proxy
        └─ call initialize(deployer, instancesProxy, partiesProxy,
                           resultsProxy, consentsProxy, usdtAddress, treasury)
```

### 11.2 Post-Deployment Role Grants & Cross-References

```
Step   Action
──────────────────────────────────────────────────────────────────────────
 A     ContractTemplates.setInstancesContract(instancesProxy)
 B     ContractInstances.setPartiesContract(partiesProxy)
 C     ContractInstances.setResultsContract(resultsProxy)
 D     ContractInstances.setConsentsContract(consentsProxy)
 E     ContractInstances.setSettlementsContract(settlementsProxy)
 F     ContractParties.setSettlementsContract(settlementsProxy)

 G     Grant ADMIN_ROLE on all contracts to admin multisig
 H     Grant SERVER_ROLE on Instances, Parties, Results, Consents to metaverse server address
 I     Grant SETTLER_ROLE on Instances, Parties, Settlements to settler bot address
 J     Grant ORACLE_ROLE on Results to oracle address (if separate from server)
 K     Renounce DEFAULT_ADMIN_ROLE from deployer (transfer to multisig)
```

### 11.3 Hardhat Ignition Module Structure

```typescript
// ignition/modules/IXMetaverse.ts
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const IXMetaverseModule = buildModule("IXMetaverse", (m) => {
    // Parameters
    const admin       = m.getParameter("admin");
    const usdtAddress = m.getParameter("usdtAddress");
    const treasury    = m.getParameter("treasury");
    const serverAddr  = m.getParameter("serverAddress");
    const settlerAddr = m.getParameter("settlerAddress");

    // 1. Deploy ProxyAdmin
    const proxyAdmin = m.contract("ProxyAdmin", [admin]);

    // 2. Deploy implementations
    const templatesImpl    = m.contract("ContractTemplates",    [], { id: "templatesImpl" });
    const instancesImpl    = m.contract("ContractInstances",    [], { id: "instancesImpl" });
    const partiesImpl      = m.contract("ContractParties",      [], { id: "partiesImpl" });
    const resultsImpl      = m.contract("ContractResults",      [], { id: "resultsImpl" });
    const consentsImpl     = m.contract("ContractConsents",     [], { id: "consentsImpl" });
    const settlementsImpl  = m.contract("ContractSettlements",  [], { id: "settlementsImpl" });

    // 3. Deploy proxies (TransparentUpgradeableProxy)
    const templatesProxy = m.contract("TransparentUpgradeableProxy",
        [templatesImpl, proxyAdmin, "0x"], { id: "templatesProxy" });
    const instancesProxy = m.contract("TransparentUpgradeableProxy",
        [instancesImpl, proxyAdmin, "0x"], { id: "instancesProxy" });
    const partiesProxy = m.contract("TransparentUpgradeableProxy",
        [partiesImpl, proxyAdmin, "0x"], { id: "partiesProxy" });
    const resultsProxy = m.contract("TransparentUpgradeableProxy",
        [resultsImpl, proxyAdmin, "0x"], { id: "resultsProxy" });
    const consentsProxy = m.contract("TransparentUpgradeableProxy",
        [consentsImpl, proxyAdmin, "0x"], { id: "consentsProxy" });
    const settlementsProxy = m.contract("TransparentUpgradeableProxy",
        [settlementsImpl, proxyAdmin, "0x"], { id: "settlementsProxy" });

    // 4. Initialize (via proxy)
    m.call(templatesProxy, "initialize", [admin], { id: "initTemplates" });
    m.call(instancesProxy, "initialize", [admin, templatesProxy],
        { id: "initInstances" });
    m.call(partiesProxy, "initialize",
        [admin, instancesProxy, usdtAddress, partiesProxy],
        { id: "initParties" });
    m.call(resultsProxy, "initialize", [admin, instancesProxy],
        { id: "initResults" });
    m.call(consentsProxy, "initialize",
        [admin, instancesProxy, partiesProxy],
        { id: "initConsents" });
    m.call(settlementsProxy, "initialize",
        [admin, instancesProxy, partiesProxy, resultsProxy,
         consentsProxy, usdtAddress, treasury],
        { id: "initSettlements" });

    // 5. Cross-references
    m.call(templatesProxy, "setInstancesContract", [instancesProxy],
        { id: "xrefTemplates" });
    m.call(instancesProxy, "setPartiesContract", [partiesProxy],
        { id: "xrefParties" });
    m.call(instancesProxy, "setResultsContract", [resultsProxy],
        { id: "xrefResults" });
    m.call(instancesProxy, "setConsentsContract", [consentsProxy],
        { id: "xrefConsents" });
    m.call(instancesProxy, "setSettlementsContract", [settlementsProxy],
        { id: "xrefSettlements" });
    m.call(partiesProxy, "setSettlementsContract", [settlementsProxy],
        { id: "xrefPartiesSettlements" });

    // 6. Role grants
    // ADMIN_ROLE, SERVER_ROLE, SETTLER_ROLE granted post-deploy
    // (omitted for brevity; done via separate admin script)

    return {
        proxyAdmin,
        templatesProxy, instancesProxy, partiesProxy,
        resultsProxy, consentsProxy, settlementsProxy,
    };
});

export default IXMetaverseModule;
```

### 11.4 Upgradability Details

**Pattern**: TransparentUpgradeableProxy + ProxyAdmin (OZ v5).

- Each core contract has its own proxy. All proxies share one ProxyAdmin.
- ProxyAdmin owner is a multisig (admin wallet).
- Upgrade flow: deploy new implementation -> call `ProxyAdmin.upgradeAndCall(proxy, newImpl, data)`.
- Storage layout is append-only: new versions must not reorder or remove existing state variables. The `__gap` arrays reserve space for future variables.
- All core contracts use `Initializable` with `initializer` modifier. No constructors in logic contracts.
- Implementation contracts should call `_disableInitializers()` in their constructor to prevent re-initialization of the implementation itself.

```solidity
/// @custom:oz-upgrades-from ContractTemplates
contract ContractTemplatesV2 is ContractTemplates {
    // New state variables appended after __gap (reduce __gap size accordingly)
    uint256 private _newVariable;
    uint256[45] private __gap; // was [46], now [45]
}
```

---

## Completeness Checklist

- [x] All 6 contracts fully specified (Templates, Instances, Parties, Results, Consents, Settlements)
- [x] All 6 interfaces defined (IContractTemplates through IContractSettlements)
- [x] All structs with storage packing (Template, Instance, Party, Result, Consent, Settlement)
- [x] Every function has complete signature with params, return types, access modifiers, mutability
- [x] Every event defined (17 events across 6 contracts)
- [x] Cross-contract interactions mapped (Section 6.7 -- 11-step lifecycle + dispute branch)
- [x] RPS lifecycle traceable end-to-end (maps 1:1 to Phase 0 walkthrough)
- [x] All 8 enums defined (ContractType, ContractStatus, PaymentType, PointType, ChainRecordPolicy, ResultSource, SettlementType, EscrowStatus)
- [x] All custom errors defined (26 errors)
- [x] Access control matrix complete
- [x] Reentrancy protection points identified
- [x] Front-running mitigation strategy documented
- [x] Gas optimization strategy with concrete examples
- [x] Deployment order with dependency graph
- [x] Hardhat Ignition module structure
- [x] Upgradability via TransparentUpgradeableProxy + ProxyAdmin
- [x] All contracts use initialize() + initializer (no constructors in logic)

---

## Appendix A: DB-to-Solidity Type Mapping Reference

| PostgreSQL Type | Solidity Type | Notes |
|---|---|---|
| UUID | bytes32 | keccak256-generated |
| VARCHAR / TEXT | string | stored as dynamic bytes |
| JSONB | bytes | ABI-encoded struct or raw bytes |
| TIMESTAMP | uint48 | Unix timestamp (sufficient until year 8M+) |
| BOOLEAN | bool | 1 byte |
| DECIMAL | uint128 | Scaled to token decimals (e.g., 6 for USDT) |
| ENUM | uint8 (via enum) | Auto-indexed 0,1,2,... |
| SERIAL / INT | uint256 or uint32 | Context-dependent |

## Appendix B: System UUIDs to Addresses

| Phase 0 UUID | Phase 1 Address | Purpose |
|---|---|---|
| `00000000-...-000000000000` | `ContractParties` contract address (escrow vault) | Escrow holding account |
| `00000000-...-000000000001` | Treasury address (configurable) | Platform fee recipient |
