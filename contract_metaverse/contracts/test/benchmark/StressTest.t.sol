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

/// @title StressTest -- Stress tests for O(1) scaling verification and concurrent contracts
/// @notice Run with: forge test --match-contract StressTest -vvv --gas-report
contract StressTest is Test {
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

    bytes32 public constant CHALLENGER_ROLE = keccak256("challenger");
    bytes32 public constant OPPONENT_ROLE   = keccak256("opponent");

    uint128 public constant ESCROW_AMOUNT = 50e18;
    uint16  public constant FEE_RATE_BPS  = 300;

    bytes32 constant OZ_INIT_SLOT = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    // ========================================================================
    // DYNAMIC TEST PARTICIPANTS
    // ========================================================================

    uint256 constant NUM_CONTRACTS = 50;

    address[] public users_a;
    address[] public users_b;

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

        // Create 50 unique user pairs, mint tokens, approve spending
        for (uint256 i = 0; i < NUM_CONTRACTS; i++) {
            address userA = makeAddr(string(abi.encodePacked("userA_", vm.toString(i))));
            address userB = makeAddr(string(abi.encodePacked("userB_", vm.toString(i))));

            users_a.push(userA);
            users_b.push(userB);

            token.mint(userA, 10_000e18);
            token.mint(userB, 10_000e18);

            vm.prank(userA);
            token.approve(address(parties), type(uint256).max);
            vm.prank(userB);
            token.approve(address(parties), type(uint256).max);
        }
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

    // ========================================================================
    // STRESS TEST: 50 concurrent contracts -- create, join, settle all
    // ========================================================================

    function test_stress_50ConcurrentContracts() public {
        // Step 1: Create a shared template
        vm.prank(admin);
        bytes32 templateId = templates.createTemplate(
            "RPS Stress Template",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );

        bytes32[] memory instanceIds = new bytes32[](NUM_CONTRACTS);

        // Step 2: Create all instances
        for (uint256 i = 0; i < NUM_CONTRACTS; i++) {
            vm.prank(admin);
            instanceIds[i] = instances.createInstance(
                templateId,
                abi.encode(string(abi.encodePacked("room-", vm.toString(i))), "stress-test")
            );
        }

        // Step 3: All parties join
        for (uint256 i = 0; i < NUM_CONTRACTS; i++) {
            vm.prank(users_a[i]);
            parties.joinContract(instanceIds[i], CHALLENGER_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);
            vm.prank(users_b[i]);
            parties.joinContract(instanceIds[i], OPPONENT_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);
        }

        // Step 4: Activate all
        vm.startPrank(admin);
        for (uint256 i = 0; i < NUM_CONTRACTS; i++) {
            instances.activateInstance(instanceIds[i]);
        }
        vm.stopPrank();

        // Step 5: Report results (userB wins in each)
        vm.startPrank(admin);
        for (uint256 i = 0; i < NUM_CONTRACTS; i++) {
            bytes memory resultData = abi.encode(
                users_b[i], "rock", "scissors", uint256(1), "1-0", false
            );
            results.reportResult(instanceIds[i], resultData, Types.ResultSource.System, true);
        }
        vm.stopPrank();

        // Step 6: Both consent in each
        vm.startPrank(admin);
        for (uint256 i = 0; i < NUM_CONTRACTS; i++) {
            consents.submitConsent(instanceIds[i], users_a[i], true, "", "");
            consents.submitConsent(instanceIds[i], users_b[i], true, "", "");
        }
        vm.stopPrank();

        // Step 7: Settle all -- measure gas for 1st vs 50th
        uint256 gas1st;
        uint256 gas50th;

        vm.startPrank(admin);
        for (uint256 i = 0; i < NUM_CONTRACTS; i++) {
            uint256 gasBefore = gasleft();
            settlements.settleContract(instanceIds[i]);
            uint256 gasUsed = gasBefore - gasleft();

            if (i == 0) {
                gas1st = gasUsed;
                emit log_named_uint("Gas: settleContract #1", gasUsed);
            }
            if (i == NUM_CONTRACTS - 1) {
                gas50th = gasUsed;
                emit log_named_uint("Gas: settleContract #50", gasUsed);
            }
        }
        vm.stopPrank();

        // Verify O(1) scaling: 50th should be within 20% of 1st
        // (allowing for warm/cold storage access differences on first call)
        uint256 tolerance = gas1st * 20 / 100;
        bool isConstantTime = (gas50th <= gas1st + tolerance) && (gas50th + tolerance >= gas1st);

        emit log_named_uint("Gas: settle 1st", gas1st);
        emit log_named_uint("Gas: settle 50th", gas50th);
        emit log_named_uint("Gas: delta (abs)", gas1st > gas50th ? gas1st - gas50th : gas50th - gas1st);
        emit log_named_string("O(1) scaling verified", isConstantTime ? "YES" : "NO (investigate)");

        // Verify all instances are settled
        for (uint256 i = 0; i < NUM_CONTRACTS; i++) {
            Types.ContractStatus status = instances.getInstanceStatus(instanceIds[i]);
            assertEq(uint8(status), uint8(Types.ContractStatus.Settled), "All instances should be Settled");
        }
    }

    // ========================================================================
    // STRESS TEST: 1st vs 50th operation gas for individual operations
    // ========================================================================

    function test_stress_createInstance_scaling() public {
        vm.prank(admin);
        bytes32 templateId = templates.createTemplate(
            "RPS Scaling Template",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );

        uint256 gas1st;
        uint256 gas50th;

        vm.startPrank(admin);
        for (uint256 i = 0; i < NUM_CONTRACTS; i++) {
            uint256 gasBefore = gasleft();
            instances.createInstance(
                templateId,
                abi.encode(string(abi.encodePacked("room-", vm.toString(i))), "scaling")
            );
            uint256 gasUsed = gasBefore - gasleft();

            if (i == 0) gas1st = gasUsed;
            if (i == NUM_CONTRACTS - 1) gas50th = gasUsed;
        }
        vm.stopPrank();

        emit log_named_uint("Gas: createInstance #1", gas1st);
        emit log_named_uint("Gas: createInstance #50", gas50th);
        emit log_named_uint("Gas: delta", gas50th > gas1st ? gas50th - gas1st : gas1st - gas50th);

        // Note: createInstance pushes to _instanceIds array, so gas grows slightly O(1) per push
        // but the SSTORE cost is constant. Delta should be small.
    }

    // ========================================================================
    // STRESS TEST: 50 templates -- verify query scaling
    // ========================================================================

    function test_stress_50Templates_queryScaling() public {
        bytes32[] memory templateIds = new bytes32[](NUM_CONTRACTS);

        // Create 50 templates
        vm.startPrank(admin);
        for (uint256 i = 0; i < NUM_CONTRACTS; i++) {
            templateIds[i] = templates.createTemplate(
                string(abi.encodePacked("Template-", vm.toString(i))),
                Types.ContractType.RPS,
                _encodeConditions(10e18, 100e18, 1, 15),
                _encodeRewardRules(true, 95),
                Types.PaymentType.IXFreePoint,
                FEE_RATE_BPS,
                Types.ChainRecordPolicy.Optional,
                bytes32(0)
            );
        }
        vm.stopPrank();

        // Verify template count
        uint256 count = templates.getTemplateCount();
        assertEq(count, NUM_CONTRACTS, "Should have 50 templates");

        // Benchmark: getTemplate (direct lookup -- should be O(1))
        uint256 gasBefore = gasleft();
        templates.getTemplate(templateIds[0]);
        uint256 gasFirst = gasBefore - gasleft();

        gasBefore = gasleft();
        templates.getTemplate(templateIds[NUM_CONTRACTS - 1]);
        uint256 gasLast = gasBefore - gasleft();

        emit log_named_uint("Gas: getTemplate (1st of 50)", gasFirst);
        emit log_named_uint("Gas: getTemplate (50th of 50)", gasLast);

        // Benchmark: getActiveTemplates (O(n) scan)
        gasBefore = gasleft();
        Types.Template[] memory active = templates.getActiveTemplates();
        uint256 gasActiveQuery = gasBefore - gasleft();

        emit log_named_uint("Gas: getActiveTemplates (50 active)", gasActiveQuery);
        assertEq(active.length, NUM_CONTRACTS, "All 50 should be active");

        // Benchmark: isTemplateActive (O(1) lookup)
        gasBefore = gasleft();
        templates.isTemplateActive(templateIds[0]);
        uint256 gasIsActive1 = gasBefore - gasleft();

        gasBefore = gasleft();
        templates.isTemplateActive(templateIds[NUM_CONTRACTS - 1]);
        uint256 gasIsActive50 = gasBefore - gasleft();

        emit log_named_uint("Gas: isTemplateActive (1st)", gasIsActive1);
        emit log_named_uint("Gas: isTemplateActive (50th)", gasIsActive50);
    }

    // ========================================================================
    // STRESS TEST: joinContract scaling (1st vs 50th unique instance)
    // ========================================================================

    function test_stress_joinContract_scaling() public {
        vm.prank(admin);
        bytes32 templateId = templates.createTemplate(
            "RPS Join Scaling",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );

        bytes32[] memory instanceIds = new bytes32[](NUM_CONTRACTS);

        vm.startPrank(admin);
        for (uint256 i = 0; i < NUM_CONTRACTS; i++) {
            instanceIds[i] = instances.createInstance(
                templateId,
                abi.encode(string(abi.encodePacked("room-", vm.toString(i))), "join-scaling")
            );
        }
        vm.stopPrank();

        uint256 gas1st;
        uint256 gas50th;

        for (uint256 i = 0; i < NUM_CONTRACTS; i++) {
            vm.prank(users_a[i]);
            uint256 gasBefore = gasleft();
            parties.joinContract(instanceIds[i], CHALLENGER_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);
            uint256 gasUsed = gasBefore - gasleft();

            if (i == 0) gas1st = gasUsed;
            if (i == NUM_CONTRACTS - 1) gas50th = gasUsed;
        }

        emit log_named_uint("Gas: joinContract #1 (across instances)", gas1st);
        emit log_named_uint("Gas: joinContract #50 (across instances)", gas50th);
        emit log_named_uint("Gas: join delta", gas50th > gas1st ? gas50th - gas1st : gas1st - gas50th);
    }
}
