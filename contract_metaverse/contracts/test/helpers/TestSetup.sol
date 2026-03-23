// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {ContractTemplates} from "../../ContractTemplates.sol";
import {ContractInstances} from "../../ContractInstances.sol";
import {ContractParties} from "../../ContractParties.sol";
import {ContractResults} from "../../ContractResults.sol";
import {ContractConsents} from "../../ContractConsents.sol";
import {ContractSettlements} from "../../ContractSettlements.sol";
import {MockIXToken} from "../../mocks/MockIXToken.sol";
import {Types} from "../../libraries/Types.sol";

/// @title TestSetup -- Base contract for all IX Metaverse test suites
/// @notice Deploys the full 6-contract system plus MockIXToken, grants all roles,
///         mints tokens, approves spending, and provides lifecycle helper functions.
contract TestSetup is Test {
    // ========================================================================
    // CONTRACTS
    // ========================================================================

    ContractTemplates public templates;
    ContractInstances public instances;
    ContractParties   public parties;
    ContractResults   public results;
    ContractConsents  public consents;
    ContractSettlements public settlements;
    MockIXToken       public token;

    // ========================================================================
    // ACCOUNTS
    // ========================================================================

    address public admin   = makeAddr("admin");
    address public alice   = makeAddr("alice");
    address public bob     = makeAddr("bob");
    address public treasury = makeAddr("treasury");
    address public stranger = makeAddr("stranger");

    // ========================================================================
    // ROLE HASHES
    // ========================================================================

    bytes32 public constant ADMIN_ROLE     = keccak256("ADMIN_ROLE");
    bytes32 public constant SYSTEM_ROLE    = keccak256("SYSTEM_ROLE");
    bytes32 public constant OPERATOR_ROLE  = keccak256("OPERATOR_ROLE");
    bytes32 public constant CONTRACT_ROLE  = keccak256("CONTRACT_ROLE");
    bytes32 public constant SERVER_ROLE    = keccak256("SERVER_ROLE");
    bytes32 public constant SETTLER_ROLE   = keccak256("SETTLER_ROLE");
    bytes32 public constant ORACLE_ROLE    = keccak256("ORACLE_ROLE");

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    bytes32 public constant CHALLENGER_ROLE = keccak256("challenger");
    bytes32 public constant OPPONENT_ROLE   = keccak256("opponent");

    uint128 public constant MINT_AMOUNT   = 100e18;
    uint128 public constant ESCROW_AMOUNT = 50e18;
    uint16  public constant FEE_RATE_BPS  = 300; // 3%

    /// @dev Counter for generating unique template names in _fullSetup
    uint256 private _templateNameCounter;

    // ========================================================================
    // SETUP
    // ========================================================================

    function setUp() public virtual {
        // --- Deploy token ---
        token = new MockIXToken();

        // --- Deploy contracts (using transparent proxy pattern: skip proxy, call initialize directly) ---
        // We deploy implementation contracts and call initialize() to simulate proxy init.

        // 1. Templates
        templates = new ContractTemplates();
        // Bypass _disableInitializers by using vm.store to reset initialized state
        _resetInitialized(address(templates));
        templates.initialize(admin);

        // 2. Instances (needs templates address)
        instances = new ContractInstances();
        _resetInitialized(address(instances));
        instances.initialize(admin, address(templates));

        // 3. Parties (needs instances + token)
        parties = new ContractParties();
        _resetInitialized(address(parties));
        parties.initialize(admin, address(instances), address(token));

        // 4. Results (needs instances)
        results = new ContractResults();
        _resetInitialized(address(results));
        results.initialize(admin, address(instances));

        // 5. Consents (needs instances + parties + templates)
        consents = new ContractConsents();
        _resetInitialized(address(consents));
        consents.initialize(admin, address(instances), address(parties), address(templates));

        // 6. Settlements (needs instances + parties + results + consents + treasury)
        settlements = new ContractSettlements();
        _resetInitialized(address(settlements));
        settlements.initialize(
            admin,
            address(instances),
            address(parties),
            address(results),
            address(consents),
            treasury
        );

        // --- Wire cross-contract references ---
        vm.startPrank(admin);

        // Instances needs parties reference for activateInstance
        instances.setPartiesContract(address(parties));
        instances.setResultsContract(address(results));
        instances.setConsentsContract(address(consents));
        instances.setSettlementsContract(address(settlements));

        // Parties needs templates reference for bet range validation
        parties.setTemplatesContract(address(templates));

        // Settlements needs templates reference for fee rate lookup
        settlements.setTemplatesContract(address(templates));

        // --- Grant SYSTEM_ROLE on instances (for createInstance, activateInstance) ---
        instances.grantRole(SYSTEM_ROLE, admin);

        // --- Grant CONTRACT_ROLE on instances (for completeInstance, disputeInstance, settleInstance) ---
        instances.grantRole(CONTRACT_ROLE, address(results));
        instances.grantRole(CONTRACT_ROLE, address(consents));
        instances.grantRole(CONTRACT_ROLE, address(settlements));

        // --- Grant CONTRACT_ROLE on parties (for releaseEscrow, refundEscrow) ---
        parties.grantRole(CONTRACT_ROLE, address(settlements));

        // --- Grant SERVER_ROLE on results (for reportResult) ---
        results.grantRole(SERVER_ROLE, admin);

        // --- Grant SERVER_ROLE on consents (for submitConsent, autoConsent) ---
        consents.grantRole(SERVER_ROLE, admin);

        // --- Grant SETTLER_ROLE on settlements (for settleContract, refundContract) ---
        settlements.grantRole(SETTLER_ROLE, admin);

        // --- Grant OPERATOR_ROLE on instances (for resolveInstance) ---
        instances.grantRole(OPERATOR_ROLE, admin);

        vm.stopPrank();

        // --- Mint tokens to alice and bob ---
        token.mint(alice, MINT_AMOUNT);
        token.mint(bob, MINT_AMOUNT);

        // --- Approve token spending for parties contract ---
        vm.prank(alice);
        token.approve(address(parties), type(uint256).max);

        vm.prank(bob);
        token.approve(address(parties), type(uint256).max);
    }

    // ========================================================================
    // HELPER: Reset Initializable storage slot to allow re-initialization
    // ========================================================================

    /// @dev The Initializable contract in OZ 5.x stores its state at a specific slot.
    ///      We reset it to allow calling initialize() on implementation contracts directly.
    function _resetInitialized(address target) internal {
        // OZ 5.x Initializable storage slot: keccak256("openzeppelin.storage.Initializable") - 1
        // = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00
        bytes32 slot = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
        vm.store(target, slot, bytes32(0));
    }

    // ========================================================================
    // LIFECYCLE HELPERS
    // ========================================================================

    /// @notice Create an RPS template with default settings
    /// @return templateId The created template ID
    function _createRPSTemplate() internal returns (bytes32 templateId) {
        return _createRPSTemplateWithName("RPS Casual Lobby 1");
    }

    /// @notice Create an RPS template with a custom name
    /// @param name The template name (must be unique)
    /// @return templateId The created template ID
    function _createRPSTemplateWithName(string memory name) internal returns (bytes32 templateId) {
        vm.prank(admin);
        templateId = templates.createTemplate(
            name,
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
    }

    /// @notice Create a contract instance from a template
    /// @param templateId The template to use
    /// @return instanceId The created instance ID
    function _createInstance(bytes32 templateId) internal returns (bytes32 instanceId) {
        vm.prank(admin);
        instanceId = instances.createInstance(
            templateId,
            abi.encode("rps-lobby-001", "A-vs-B")
        );
    }

    /// @notice Alice joins a contract instance as challenger with ESCROW_AMOUNT
    /// @param instanceId The instance to join
    function _aliceJoins(bytes32 instanceId) internal {
        vm.prank(alice);
        parties.joinContract(
            instanceId,
            CHALLENGER_ROLE,
            ESCROW_AMOUNT,
            Types.PointType.IXFreePoint
        );
    }

    /// @notice Bob joins a contract instance as opponent with ESCROW_AMOUNT
    /// @param instanceId The instance to join
    function _bobJoins(bytes32 instanceId) internal {
        vm.prank(bob);
        parties.joinContract(
            instanceId,
            OPPONENT_ROLE,
            ESCROW_AMOUNT,
            Types.PointType.IXFreePoint
        );
    }

    /// @notice Full setup: create template + instance + both parties join
    /// @return templateId The created template ID
    /// @return instanceId The created instance ID
    function _fullSetup() internal returns (bytes32 templateId, bytes32 instanceId) {
        _templateNameCounter++;
        string memory name = string(abi.encodePacked("RPS Full Setup ", vm.toString(_templateNameCounter)));
        templateId = _createRPSTemplateWithName(name);
        instanceId = _createInstance(templateId);
        _aliceJoins(instanceId);
        _bobJoins(instanceId);
    }

    /// @notice Activate a contract instance (Created -> Active)
    /// @param instanceId The instance to activate
    function _activate(bytes32 instanceId) internal {
        vm.prank(admin);
        instances.activateInstance(instanceId);
    }

    /// @notice Submit a final result where Bob wins
    /// @param instanceId The instance to submit result for
    function _submitResultBobWins(bytes32 instanceId) internal {
        bytes memory resultData = abi.encode(
            bob,           // winnerId
            "rock",        // winnerMove
            "scissors",    // loserMove
            uint256(1),    // roundsPlayed
            "1-0",         // score
            false          // isDraw
        );
        vm.prank(admin);
        results.reportResult(
            instanceId,
            resultData,
            Types.ResultSource.System,
            true
        );
    }

    /// @notice Submit a final result that is a draw
    /// @param instanceId The instance to submit result for
    function _submitResultDraw(bytes32 instanceId) internal {
        bytes memory resultData = abi.encode(
            address(0),    // winnerId (no winner)
            "rock",        // winnerMove
            "rock",        // loserMove
            uint256(1),    // roundsPlayed
            "0-0",         // score
            true           // isDraw
        );
        vm.prank(admin);
        results.reportResult(
            instanceId,
            resultData,
            Types.ResultSource.System,
            true
        );
    }

    /// @notice Both alice and bob consent to the result
    /// @param instanceId The instance to consent for
    function _bothConsent(bytes32 instanceId) internal {
        vm.startPrank(admin);
        consents.submitConsent(instanceId, alice, true, "", "");
        consents.submitConsent(instanceId, bob, true, "", "");
        vm.stopPrank();
    }

    /// @notice Encode template conditions (minBet, maxBet, rounds, timeoutSeconds)
    function _encodeConditions(
        uint256 minBet,
        uint256 maxBet,
        uint256 rounds_,
        uint256 timeout
    ) internal pure returns (bytes memory) {
        return abi.encode(minBet, maxBet, rounds_, timeout);
    }

    /// @notice Encode reward rules (drawRefund, winnerTakesAllPct)
    function _encodeRewardRules(
        bool drawRefund,
        uint256 winnerPct
    ) internal pure returns (bytes memory) {
        return abi.encode(drawRefund, winnerPct);
    }
}
