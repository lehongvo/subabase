# Cross-Review B: Agent 3 Code Review (Types, Templates, Instances, Parties)

| Item | Details |
| --- | --- |
| Reviewer | Senior Solidity Code Reviewer (Agent B) |
| Date | 2026-03-23 |
| Scope | Types.sol, IContractTemplates.sol, IContractInstances.sol, IContractParties.sol, ContractTemplates.sol, ContractInstances.sol, ContractParties.sol |

---

## Summary

Reviewed 7 files from Agent 3. Found **13 issues**: 2 Critical, 3 High, 4 Medium, 4 Low. Critical issues involve using non-upgradeable `ReentrancyGuard` in a proxy-deployed contract and missing `EscrowStatus` updates on `releaseEscrow`. All issues documented below with fixes applied.

---

## Issues

### [CRITICAL-01] ContractParties uses non-upgradeable ReentrancyGuard with proxy pattern

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractParties.sol`
- **Line**: 6, 25
- **Category**: Security
- **Description**: `ContractParties` imports and inherits `ReentrancyGuard` from `@openzeppelin/contracts/utils/ReentrancyGuard.sol` (non-upgradeable). The contract uses `Initializable` and `_disableInitializers()`, confirming it is deployed behind a proxy. Non-upgradeable `ReentrancyGuard` uses a constructor to initialize its internal state, which never executes in a proxy context. The `_status` variable remains at default (0), and the guard may not function correctly or may break in future OZ versions.
- **Impact**: Reentrancy protection may silently fail. In OZ v5, the non-upgradeable `ReentrancyGuard` sets `_status = NOT_ENTERED` in the constructor. When deployed via proxy, this constructor never runs, so `_status` starts at 0 (which happens to equal `NOT_ENTERED` in v5). While this happens to work with OZ v5 by coincidence, it is brittle and will break if the guard implementation changes. This is the exact scenario `ReentrancyGuardUpgradeable` exists to handle.
- **Recommendation**: Replace `ReentrancyGuard` with `ReentrancyGuardUpgradeable` and call `__ReentrancyGuard_init()` in `initialize()`.

```solidity
// Before:
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
// After:
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// In inheritance:
// Before: ReentrancyGuard
// After: ReentrancyGuardUpgradeable

// In initialize():
__ReentrancyGuard_init();
```

**Status**: FIXED

---

### [CRITICAL-02] releaseEscrow does not update party escrowStatus

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractParties.sol`
- **Line**: 206-219
- **Category**: Correctness / Security
- **Description**: `releaseEscrow()` transfers tokens but never marks any party's `escrowStatus` as `Released`. This means after settlement, all parties still show `escrowStatus == Held`, and the same escrow could theoretically be released or refunded again if `releaseEscrow` or `refundEscrow` is called multiple times. The function also lacks any check that escrow is currently `Held` before releasing.
- **Impact**: Double-spend of escrowed funds is possible if the caller (ContractSettlements) calls `releaseEscrow` multiple times for the same instance. The on-chain state would be inconsistent, showing `Held` when tokens are already transferred.
- **Recommendation**: The `releaseEscrow` function should track releases. Since it transfers arbitrary amounts to arbitrary recipients (winner gets total minus fee, treasury gets fee), add per-instance release tracking rather than per-party status updates. Add a `_totalReleased` mapping and validate against total escrow.

```solidity
// Add: mapping(bytes32 => uint128) private _totalReleased;
// In releaseEscrow: track cumulative release and verify it doesn't exceed total escrow
```

**Status**: FIXED

---

### [HIGH-01] Types.sol EscrowStatus has "Forfeited" instead of "Refunded" per architecture spec

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/libraries/Types.sol`
- **Line**: 64-68
- **Category**: Correctness
- **Description**: The architecture-design.md specifies `EscrowStatus { Held, Released, Refunded }` but Types.sol has `EscrowStatus { Held, Released, Forfeited }`. The value at index 2 is `Forfeited` instead of `Refunded`. This mismatches the spec and makes `refundEscrow()` in ContractParties semantically incorrect when it sets `escrowStatus = EscrowStatus.Released` for refunds instead of a dedicated refund status.
- **Impact**: Mismatch with Phase 0 DB schema where escrow_status has `held`, `released`, `refunded`. Off-chain indexers/frontends expecting the spec values will break.
- **Recommendation**: Change `Forfeited` to `Refunded` to match the architecture spec.

**Status**: FIXED

---

### [HIGH-02] refundEscrow sets escrowStatus to Released instead of Refunded

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractParties.sol`
- **Line**: 241
- **Category**: Correctness
- **Description**: In `refundEscrow()`, `party.escrowStatus` is set to `Types.EscrowStatus.Released` when it should be set to `Types.EscrowStatus.Refunded` (after fixing CRITICAL-02/HIGH-01). A refund and a release are semantically different operations.
- **Impact**: On-chain state incorrectly represents refunded escrow as released.
- **Recommendation**: Set `party.escrowStatus = Types.EscrowStatus.Refunded;`

**Status**: FIXED

---

### [HIGH-03] createInstance has no access control -- anyone can create instances

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractInstances.sol`
- **Line**: 114
- **Category**: Security
- **Description**: The `createInstance` function has `whenNotPaused` but no role restriction. The architecture-design.md Section 6.2 specifies `Access: onlyRole(SERVER_ROLE) whenNotPaused`. Without access control, any EOA can create unlimited contract instances, potentially flooding the `_instanceIds` array and causing DoS for enumeration, or creating spam instances.
- **Impact**: Unauthorized instance creation. Potential DoS vector via unbounded `_instanceIds` growth.
- **Recommendation**: Add `onlyRole(SYSTEM_ROLE)` modifier.

**Status**: FIXED

---

### [MEDIUM-01] IContractInstances interface missing setTxHash and getActiveTemplatesByType from arch spec

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/interfaces/IContractInstances.sol`
- **Line**: N/A
- **Category**: Correctness
- **Description**: Architecture spec Section 6.2 defines `setTxHash(bytes32 instanceId, bytes32 txHash)` but the interface does not include it. The `ContractInstances` implementation also lacks it. The `InstanceTxHashSet` event is declared but can never be emitted.
- **Impact**: No way to record on-chain tx hashes for instances, which is a Phase 1 requirement.
- **Recommendation**: Add `setTxHash` to both the interface and implementation.

**Status**: FIXED

---

### [MEDIUM-02] IContractTemplates interface missing getActiveTemplatesByType from arch spec

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/interfaces/IContractTemplates.sol`
- **Line**: N/A
- **Category**: Correctness
- **Description**: The architecture spec Section 6.1 defines `getActiveTemplatesByType(Types.ContractType contractType)` but the interface only has `getActiveTemplates()`. The implementation in `ContractTemplates.sol` has a `_templatesByType` mapping that is populated on `createTemplate` but never queried via a public function.
- **Impact**: Cannot filter templates by type on-chain, which is required for the RPS lifecycle lookup flow ("find template by type RPS").
- **Recommendation**: Add `getActiveTemplatesByType` to interface and implementation.

**Status**: FIXED

---

### [MEDIUM-03] joinContract does not validate escrowType against template paymentType

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractParties.sol`
- **Line**: 133-198
- **Category**: Correctness
- **Description**: Requirements Section 3.1 step 5 specifies validating that `escrowType` matches the template's `paymentType`. If template `paymentType == IX_POINT`, only IX_POINT should be accepted. If `paymentType == IX_FREE_POINT`, only IX_FREE_POINT. If `BOTH`, either is fine. The current `joinContract` does not perform this validation.
- **Impact**: Users could escrow the wrong token type, breaking the settlement logic.
- **Recommendation**: Add payment type validation after template decode.

**Status**: FIXED

---

### [MEDIUM-04] joinContract does not validate template is_active

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractParties.sol`
- **Line**: 133-198
- **Category**: Correctness
- **Description**: Requirements Section 3.1 step 2 specifies "Validate template is active: Revert if the associated template `is_active == false`". The current implementation only checks instance status but not whether the template is still active.
- **Impact**: Parties could join a contract whose template has been deactivated, which the admin intended to prevent.
- **Recommendation**: Add template active check after fetching the template.

**Status**: FIXED

---

### [LOW-01] ContractTemplates.__gap is 50 slots -- may conflict with OZ storage

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractTemplates.sol`
- **Line**: 52
- **Category**: Quality
- **Description**: The `__gap` is 50 slots. The architecture spec Section 4.1 recommends 46 slots for ContractTemplates. The exact gap size should account for all state variables to ensure the total slots used + gap = a consistent number (usually 50 per "section"). Currently there are 6 state variables (mappings and arrays count as 1 slot each for layout purposes) + nonce = 7 slots, so a gap of 43 would give 50 total, or 50 is fine if the convention is "gap itself is 50".
- **Impact**: Not a bug, but inconsistent with the architecture spec. If new state variables are added during an upgrade, the gap must be manually reduced. Using 50 when the spec says 46 means 4 more slots of padding than expected.
- **Recommendation**: Align gap sizes with architecture spec or document the convention clearly. No code change applied since this is non-breaking.

**Status**: ACKNOWLEDGED (no fix needed)

---

### [LOW-02] createTemplate and createInstance ID generation could theoretically collide

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractTemplates.sol`
- **Line**: 112-115
- **Category**: Security (very low probability)
- **Description**: Template IDs are generated via `keccak256(name, block.timestamp, msg.sender, nonce)`. The nonce makes collisions practically impossible as long as the same contract handles all creations. The `if (_templateExists[templateId]) revert` check provides a safety net. This is acceptable.
- **Impact**: Negligible. The nonce + existence check make collisions revert safely.
- **Recommendation**: No change needed. The current design is collision-safe.

**Status**: ACKNOWLEDGED (no fix needed)

---

### [LOW-03] getTotalEscrow may overflow for uint128 with many parties

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractParties.sol`
- **Line**: 304-310
- **Category**: Gas / Correctness
- **Description**: `getTotalEscrow` sums `uint128` values into a `uint128` return. With Solidity 0.8+ overflow checks, this is safe (will revert on overflow). However, for realistic usage (2-8 parties with amounts < 2^128), overflow is impossible. The implementation is correct.
- **Impact**: None in practice.
- **Recommendation**: No change needed.

**Status**: ACKNOWLEDGED (no fix needed)

---

### [LOW-04] Missing PaymentTypeMismatch custom error in Types.sol

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/libraries/Types.sol`
- **Line**: N/A
- **Category**: Quality
- **Description**: After adding payment type validation in joinContract (MEDIUM-03 fix), a `PaymentTypeMismatch` custom error is needed in Types.sol but does not exist.
- **Impact**: Without this error, the payment type validation fix cannot provide a meaningful revert reason.
- **Recommendation**: Add `error PaymentTypeMismatch(uint8 expected, uint8 actual);` to Types.sol.

**Status**: FIXED (as part of MEDIUM-03 fix)

---

## Fix Summary

| Issue | Severity | Fixed |
| --- | --- | --- |
| CRITICAL-01: Non-upgradeable ReentrancyGuard | Critical | Yes |
| CRITICAL-02: releaseEscrow no status update | Critical | Yes |
| HIGH-01: EscrowStatus Forfeited vs Refunded | High | Yes |
| HIGH-02: refundEscrow wrong status | High | Yes |
| HIGH-03: createInstance no access control | High | Yes |
| MEDIUM-01: Missing setTxHash | Medium | Yes |
| MEDIUM-02: Missing getActiveTemplatesByType | Medium | Yes |
| MEDIUM-03: No escrowType vs paymentType validation | Medium | Yes |
| MEDIUM-04: No template is_active check in joinContract | Medium | Yes |
| LOW-01: __gap size inconsistency | Low | Acknowledged |
| LOW-02: ID collision safety | Low | Acknowledged |
| LOW-03: getTotalEscrow overflow | Low | Acknowledged |
| LOW-04: Missing PaymentTypeMismatch error | Low | Fixed |
