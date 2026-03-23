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

/// @title GasBenchmark -- Measures gas cost for every key operation in the IX Metaverse system
/// @notice Run with: forge test --match-contract GasBenchmark -vvv --gas-report
contract GasBenchmark is Test {
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

    address public admin    = makeAddr("admin");
    address public alice    = makeAddr("alice");
    address public bob      = makeAddr("bob");
    address public treasury = makeAddr("treasury");

    // ========================================================================
    // ROLE HASHES
    // ========================================================================

    bytes32 public constant ADMIN_ROLE     = keccak256("ADMIN_ROLE");
    bytes32 public constant SYSTEM_ROLE    = keccak256("SYSTEM_ROLE");
    bytes32 public constant OPERATOR_ROLE  = keccak256("OPERATOR_ROLE");
    bytes32 public constant CONTRACT_ROLE  = keccak256("CONTRACT_ROLE");
    bytes32 public constant SERVER_ROLE    = keccak256("SERVER_ROLE");
    bytes32 public constant SETTLER_ROLE   = keccak256("SETTLER_ROLE");

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    bytes32 public constant CHALLENGER_ROLE = keccak256("challenger");
    bytes32 public constant OPPONENT_ROLE   = keccak256("opponent");

    uint128 public constant MINT_AMOUNT   = 10_000e18;
    uint128 public constant ESCROW_AMOUNT = 50e18;
    uint16  public constant FEE_RATE_BPS  = 300; // 3%

    // ========================================================================
    // OZ INITIALIZABLE SLOT
    // ========================================================================

    bytes32 constant OZ_INIT_SLOT = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    // ========================================================================
    // SETUP
    // ========================================================================

    function setUp() public {
        // Deploy token
        token = new MockIXToken();

        // Deploy and initialize all contracts
        templates = new ContractTemplates();
        _resetInit(address(templates));
        templates.initialize(admin);

        instances = new ContractInstances();
        _resetInit(address(instances));
        instances.initialize(admin, address(templates));

        parties = new ContractParties();
        _resetInit(address(parties));
        parties.initialize(admin, address(instances), address(token));

        results = new ContractResults();
        _resetInit(address(results));
        results.initialize(admin, address(instances));

        consents = new ContractConsents();
        _resetInit(address(consents));
        consents.initialize(admin, address(instances), address(parties), address(templates));

        settlements = new ContractSettlements();
        _resetInit(address(settlements));
        settlements.initialize(
            admin,
            address(instances),
            address(parties),
            address(results),
            address(consents),
            treasury
        );

        // Wire cross-contract references and grant roles
        vm.startPrank(admin);

        instances.setPartiesContract(address(parties));
        instances.setResultsContract(address(results));
        instances.setConsentsContract(address(consents));
        instances.setSettlementsContract(address(settlements));
        parties.setTemplatesContract(address(templates));
        settlements.setTemplatesContract(address(templates));

        instances.grantRole(SYSTEM_ROLE, admin);
        instances.grantRole(CONTRACT_ROLE, address(results));
        instances.grantRole(CONTRACT_ROLE, address(consents));
        instances.grantRole(CONTRACT_ROLE, address(settlements));
        parties.grantRole(CONTRACT_ROLE, address(settlements));
        results.grantRole(SERVER_ROLE, admin);
        consents.grantRole(SERVER_ROLE, admin);
        settlements.grantRole(SETTLER_ROLE, admin);
        instances.grantRole(OPERATOR_ROLE, admin);

        vm.stopPrank();

        // Mint and approve tokens
        token.mint(alice, MINT_AMOUNT);
        token.mint(bob, MINT_AMOUNT);
        vm.prank(alice);
        token.approve(address(parties), type(uint256).max);
        vm.prank(bob);
        token.approve(address(parties), type(uint256).max);
    }

    function _resetInit(address target) internal {
        vm.store(target, OZ_INIT_SLOT, bytes32(0));
    }

    // ========================================================================
    // ENCODING HELPERS
    // ========================================================================

    function _encodeConditions(uint256 minBet, uint256 maxBet, uint256 rounds_, uint256 timeout)
        internal pure returns (bytes memory)
    {
        return abi.encode(minBet, maxBet, rounds_, timeout);
    }

    function _encodeRewardRules(bool drawRefund, uint256 winnerPct)
        internal pure returns (bytes memory)
    {
        return abi.encode(drawRefund, winnerPct);
    }

    function _resultBobWins() internal view returns (bytes memory) {
        return abi.encode(bob, "rock", "scissors", uint256(1), "1-0", false);
    }

    function _resultDraw() internal view returns (bytes memory) {
        return abi.encode(address(0), "rock", "rock", uint256(1), "0-0", true);
    }

    // ========================================================================
    // BENCHMARK: createTemplate
    // ========================================================================

    function test_gas_createTemplate() public {
        vm.prank(admin);
        uint256 gasBefore = gasleft();
        templates.createTemplate(
            "RPS Benchmark Template",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("Gas: createTemplate", gasUsed);
    }

    // ========================================================================
    // BENCHMARK: createInstance
    // ========================================================================

    function test_gas_createInstance() public {
        vm.prank(admin);
        bytes32 templateId = templates.createTemplate(
            "RPS CI Template",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );

        vm.prank(admin);
        uint256 gasBefore = gasleft();
        instances.createInstance(templateId, abi.encode("room-1", "A-vs-B"));
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("Gas: createInstance", gasUsed);
    }

    // ========================================================================
    // BENCHMARK: joinContract (includes ERC-20 transfer)
    // ========================================================================

    function test_gas_joinContract() public {
        // Setup template + instance
        vm.prank(admin);
        bytes32 templateId = templates.createTemplate(
            "RPS Join Template",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
        vm.prank(admin);
        bytes32 instanceId = instances.createInstance(templateId, abi.encode("room-1", "A-vs-B"));

        // Benchmark: first party join (alice)
        vm.prank(alice);
        uint256 gasBefore = gasleft();
        parties.joinContract(instanceId, CHALLENGER_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("Gas: joinContract (1st party)", gasUsed);

        // Benchmark: second party join (bob)
        vm.prank(bob);
        gasBefore = gasleft();
        parties.joinContract(instanceId, OPPONENT_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);
        gasUsed = gasBefore - gasleft();
        emit log_named_uint("Gas: joinContract (2nd party)", gasUsed);
    }

    // ========================================================================
    // BENCHMARK: activateInstance
    // ========================================================================

    function test_gas_activateInstance() public {
        (bytes32 templateId, bytes32 instanceId) = _setupFullJoined();

        vm.prank(admin);
        uint256 gasBefore = gasleft();
        instances.activateInstance(instanceId);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("Gas: activateInstance", gasUsed);
    }

    // ========================================================================
    // BENCHMARK: reportResult (with completeInstance callback)
    // ========================================================================

    function test_gas_reportResult() public {
        (bytes32 templateId, bytes32 instanceId) = _setupFullJoined();
        vm.prank(admin);
        instances.activateInstance(instanceId);

        vm.prank(admin);
        uint256 gasBefore = gasleft();
        results.reportResult(instanceId, _resultBobWins(), Types.ResultSource.System, true);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("Gas: reportResult (isFinal=true, triggers completeInstance)", gasUsed);
    }

    // ========================================================================
    // BENCHMARK: submitConsent (first and second party)
    // ========================================================================

    function test_gas_submitConsent() public {
        (bytes32 templateId, bytes32 instanceId) = _setupCompleted();

        // First consent
        vm.prank(admin);
        uint256 gasBefore = gasleft();
        consents.submitConsent(instanceId, alice, true, "", "");
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("Gas: submitConsent (1st party, sets deadline)", gasUsed);

        // Second consent
        vm.prank(admin);
        gasBefore = gasleft();
        consents.submitConsent(instanceId, bob, true, "", "");
        gasUsed = gasBefore - gasleft();
        emit log_named_uint("Gas: submitConsent (2nd party)", gasUsed);
    }

    // ========================================================================
    // BENCHMARK: autoConsent (after timeout)
    // ========================================================================

    function test_gas_autoConsent() public {
        (bytes32 templateId, bytes32 instanceId) = _setupCompleted();

        // First consent from alice to set deadline
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, true, "", "");

        // Warp past timeout (15 seconds timeout + 1)
        vm.warp(block.timestamp + 16);

        vm.prank(admin);
        uint256 gasBefore = gasleft();
        consents.autoConsent(instanceId, bob);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("Gas: autoConsent (timeout)", gasUsed);
    }

    // ========================================================================
    // BENCHMARK: settleContract (winner scenario with 2 token transfers + state updates)
    // ========================================================================

    function test_gas_settleContract() public {
        (bytes32 templateId, bytes32 instanceId) = _setupConsented();

        vm.prank(admin);
        uint256 gasBefore = gasleft();
        settlements.settleContract(instanceId);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("Gas: settleContract (winner, 2 transfers + state update)", gasUsed);
    }

    // ========================================================================
    // BENCHMARK: refundContract (draw scenario with refunds)
    // ========================================================================

    function test_gas_refundContract() public {
        // Setup: create, join, activate, submit draw result, consent
        vm.prank(admin);
        bytes32 templateId = templates.createTemplate(
            "RPS Refund Template",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
        vm.prank(admin);
        bytes32 instanceId = instances.createInstance(templateId, abi.encode("room-1", "A-vs-B"));

        vm.prank(alice);
        parties.joinContract(instanceId, CHALLENGER_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);
        vm.prank(bob);
        parties.joinContract(instanceId, OPPONENT_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);

        vm.prank(admin);
        instances.activateInstance(instanceId);

        // Submit draw result
        vm.prank(admin);
        results.reportResult(instanceId, _resultDraw(), Types.ResultSource.System, true);

        // Both consent
        vm.startPrank(admin);
        consents.submitConsent(instanceId, alice, true, "", "");
        consents.submitConsent(instanceId, bob, true, "", "");
        vm.stopPrank();

        // Benchmark refund
        vm.prank(admin);
        uint256 gasBefore = gasleft();
        settlements.refundContract(instanceId);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("Gas: refundContract (draw, 2 refunds + state update)", gasUsed);
    }

    // ========================================================================
    // BENCHMARK: Full lifecycle total gas
    // ========================================================================

    function test_gas_fullLifecycle() public {
        uint256 totalGasStart = gasleft();

        // 1. createTemplate
        vm.prank(admin);
        bytes32 templateId = templates.createTemplate(
            "RPS Full Lifecycle",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );

        // 2. createInstance
        vm.prank(admin);
        bytes32 instanceId = instances.createInstance(templateId, abi.encode("room-1", "A-vs-B"));

        // 3. joinContract (alice)
        vm.prank(alice);
        parties.joinContract(instanceId, CHALLENGER_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);

        // 4. joinContract (bob)
        vm.prank(bob);
        parties.joinContract(instanceId, OPPONENT_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);

        // 5. activateInstance
        vm.prank(admin);
        instances.activateInstance(instanceId);

        // 6. reportResult (isFinal=true, triggers completeInstance)
        vm.prank(admin);
        results.reportResult(instanceId, _resultBobWins(), Types.ResultSource.System, true);

        // 7. submitConsent (alice)
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, true, "", "");

        // 8. submitConsent (bob)
        vm.prank(admin);
        consents.submitConsent(instanceId, bob, true, "", "");

        // 9. settleContract
        vm.prank(admin);
        settlements.settleContract(instanceId);

        uint256 totalGasUsed = totalGasStart - gasleft();
        emit log_named_uint("Gas: FULL LIFECYCLE (create->settle)", totalGasUsed);

        // Verify final state
        Types.ContractStatus finalStatus = instances.getInstanceStatus(instanceId);
        assertEq(uint8(finalStatus), uint8(Types.ContractStatus.Settled), "Instance should be Settled");

        // Verify token balances
        // Bob (winner) should receive: 100e18 - 3e18 fee = 97e18
        // Bob started with 10_000e18 - 50e18 escrow = 9_950e18, then + 97e18 = 10_047e18
        assertEq(token.balanceOf(bob), 10_047e18, "Bob (winner) balance");
        // Alice lost her escrow: 10_000e18 - 50e18 = 9_950e18
        assertEq(token.balanceOf(alice), 9_950e18, "Alice (loser) balance");
        // Treasury gets 3% of 100e18 = 3e18
        assertEq(token.balanceOf(treasury), 3e18, "Treasury fee balance");
    }

    // ========================================================================
    // INTERNAL HELPERS
    // ========================================================================

    /// @dev Create template + instance + both parties join
    function _setupFullJoined() internal returns (bytes32 templateId, bytes32 instanceId) {
        vm.prank(admin);
        templateId = templates.createTemplate(
            "RPS Setup Template",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
        vm.prank(admin);
        instanceId = instances.createInstance(templateId, abi.encode("room-1", "A-vs-B"));
        vm.prank(alice);
        parties.joinContract(instanceId, CHALLENGER_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);
        vm.prank(bob);
        parties.joinContract(instanceId, OPPONENT_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);
    }

    /// @dev Full joined + activated + result reported (Completed state)
    function _setupCompleted() internal returns (bytes32 templateId, bytes32 instanceId) {
        (templateId, instanceId) = _setupFullJoined();
        vm.prank(admin);
        instances.activateInstance(instanceId);
        vm.prank(admin);
        results.reportResult(instanceId, _resultBobWins(), Types.ResultSource.System, true);
    }

    /// @dev Completed + both consented
    function _setupConsented() internal returns (bytes32 templateId, bytes32 instanceId) {
        (templateId, instanceId) = _setupCompleted();
        vm.startPrank(admin);
        consents.submitConsent(instanceId, alice, true, "", "");
        consents.submitConsent(instanceId, bob, true, "", "");
        vm.stopPrank();
    }
}
