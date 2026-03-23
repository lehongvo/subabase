// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {TestSetup} from "../helpers/TestSetup.sol";
import {Types} from "../../libraries/Types.sol";
import {FeeCalculator} from "../../libraries/FeeCalculator.sol";

/// @title FeeManipulationTest -- Tests fee calculation safety bounds and invariants
/// @notice Verifies that fee rates are capped, fee + winner == totalEscrow always holds,
///         and direct escrow release without proper settlement is blocked.
contract FeeManipulationTest is TestSetup {

    bytes32 public templateId;
    bytes32 public instanceId;

    function setUp() public override {
        super.setUp();
    }

    // ========================================================================
    // FEE RATE BOUNDS
    // ========================================================================

    /// @notice Template with feeRate > 5000 bps (50%) must revert with InvalidFeeRate
    function test_feeRateAboveMax_reverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Types.InvalidFeeRate.selector, uint16(5001)));
        templates.createTemplate(
            "Evil High Fee",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            5001, // > 5000 bps
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
    }

    /// @notice Template with feeRate = 5000 bps (50%) should succeed (boundary)
    function test_feeRateAtMax_succeeds() public {
        vm.prank(admin);
        bytes32 tplId = templates.createTemplate(
            "Max Fee Template",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            5000, // exactly 50%
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
        assertEq(templates.getTemplateFeeRate(tplId), 5000);
    }

    /// @notice Template with feeRate = 0 bps (no fee) should succeed
    function test_feeRateZero_succeeds() public {
        vm.prank(admin);
        bytes32 tplId = templates.createTemplate(
            "No Fee Template",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            0,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
        assertEq(templates.getTemplateFeeRate(tplId), 0);
    }

    /// @notice Update template to feeRate > 5000 must revert
    function test_updateFeeRateAboveMax_reverts() public {
        vm.prank(admin);
        bytes32 tplId = templates.createTemplate(
            "Normal Template",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            300,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Types.InvalidFeeRate.selector, uint16(6000)));
        templates.updateTemplate(
            tplId,
            "Normal Template",
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            6000, // > 5000 bps
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
    }

    // ========================================================================
    // FEE CALCULATION INVARIANT: winner + fee == totalEscrow (FUZZ)
    // ========================================================================

    /// @notice Fuzz test: for any valid totalEscrow and feeRate,
    ///         winnerAmount + feeAmount == totalEscrow
    function testFuzz_feeInvariant_winnerPlusFeeEqualsTotalEscrow(
        uint128 totalEscrow,
        uint16 feeRateBps
    ) public pure {
        // Bound inputs to valid ranges
        vm.assume(totalEscrow > 0);
        vm.assume(feeRateBps <= 5000);

        (uint128 winnerAmount, uint128 feeAmount) = FeeCalculator.calculateFee(
            totalEscrow,
            feeRateBps
        );

        // Core invariant: no tokens created or destroyed
        assertEq(
            uint256(winnerAmount) + uint256(feeAmount),
            uint256(totalEscrow),
            "Fee invariant violated: winner + fee != totalEscrow"
        );
    }

    /// @notice Fuzz test: fee amount must never exceed totalEscrow
    function testFuzz_feeNeverExceedsTotalEscrow(
        uint128 totalEscrow,
        uint16 feeRateBps
    ) public pure {
        vm.assume(totalEscrow > 0);
        vm.assume(feeRateBps <= 5000);

        (, uint128 feeAmount) = FeeCalculator.calculateFee(totalEscrow, feeRateBps);

        assertLe(feeAmount, totalEscrow / 2, "Fee exceeds 50% of total escrow");
    }

    /// @notice Fuzz test: winner always gets at least 50% when fee <= 5000 bps
    function testFuzz_winnerGetsAtLeastHalf(
        uint128 totalEscrow,
        uint16 feeRateBps
    ) public pure {
        vm.assume(totalEscrow > 0);
        vm.assume(feeRateBps <= 5000);

        (uint128 winnerAmount, ) = FeeCalculator.calculateFee(totalEscrow, feeRateBps);

        assertGe(winnerAmount, totalEscrow / 2, "Winner gets less than 50%");
    }

    /// @notice FeeCalculator rejects totalEscrow = 0
    function test_feeCalculator_zeroEscrow_reverts() public {
        vm.expectRevert(Types.InvalidAmount.selector);
        FeeCalculator.calculateFee(0, 300);
    }

    /// @notice FeeCalculator rejects feeRate > 5000
    function test_feeCalculator_aboveMaxRate_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(Types.InvalidFeeRate.selector, uint16(5001)));
        FeeCalculator.calculateFee(100e18, 5001);
    }

    // ========================================================================
    // BYPASS FEE BY CALLING releaseEscrow DIRECTLY
    // ========================================================================

    /// @notice Attacker cannot bypass fee by calling releaseEscrow directly
    ///         (requires CONTRACT_ROLE, which only ContractSettlements has)
    function test_bypassFee_directReleaseEscrow_reverts() public {
        (bytes32 tplId, bytes32 instId) = _fullSetup();
        _activate(instId);
        _submitResultBobWins(instId);
        _bothConsent(instId);

        // Bob (winner) tries to call releaseEscrow directly to get full escrow without fee
        vm.prank(bob);
        vm.expectRevert();
        parties.releaseEscrow(instId, bob, 100e18);

        // Alice tries too
        vm.prank(alice);
        vm.expectRevert();
        parties.releaseEscrow(instId, alice, 100e18);

        // Stranger tries
        vm.prank(stranger);
        vm.expectRevert();
        parties.releaseEscrow(instId, stranger, 100e18);
    }

    /// @notice Admin without CONTRACT_ROLE cannot call releaseEscrow
    function test_bypassFee_adminWithoutContractRole_reverts() public {
        (bytes32 tplId, bytes32 instId) = _fullSetup();

        // Admin does not have CONTRACT_ROLE on parties (only settlements does)
        vm.prank(admin);
        vm.expectRevert();
        parties.releaseEscrow(instId, admin, 100e18);
    }

    // ========================================================================
    // END-TO-END FEE VERIFICATION
    // ========================================================================

    /// @notice Verify exact fee calculation in a full settlement lifecycle
    function test_exactFeeCalculation_settlement() public {
        (bytes32 tplId, bytes32 instId) = _fullSetup();
        _activate(instId);
        _submitResultBobWins(instId);
        _bothConsent(instId);

        uint128 totalEscrow = parties.getTotalEscrow(instId);
        uint16 feeRate = templates.getTemplateFeeRate(tplId);

        // Calculate expected values
        (uint128 expectedWinner, uint128 expectedFee) = FeeCalculator.calculateFee(
            totalEscrow,
            feeRate
        );

        uint256 bobBefore = token.balanceOf(bob);
        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(admin);
        settlements.settleContract(instId);

        uint256 bobAfter = token.balanceOf(bob);
        uint256 treasuryAfter = token.balanceOf(treasury);

        assertEq(bobAfter - bobBefore, expectedWinner, "Bob received wrong winner amount");
        assertEq(treasuryAfter - treasuryBefore, expectedFee, "Treasury received wrong fee");
        assertEq(
            expectedWinner + expectedFee,
            totalEscrow,
            "Total distributed != total escrowed"
        );
    }

    /// @notice Verify settlement with 0% fee (all goes to winner)
    function test_settlement_zeroFee() public {
        vm.prank(admin);
        bytes32 tplId = templates.createTemplate(
            "No Fee RPS",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 100),
            Types.PaymentType.IXFreePoint,
            0, // 0% fee
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
        bytes32 instId = _createInstance(tplId);

        token.mint(alice, MINT_AMOUNT);
        token.mint(bob, MINT_AMOUNT);
        vm.prank(alice);
        parties.joinContract(instId, CHALLENGER_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);
        vm.prank(bob);
        parties.joinContract(instId, OPPONENT_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);

        _activate(instId);

        // Report bob wins
        bytes memory resultData = abi.encode(
            bob, "rock", "scissors", uint256(1), "1-0", false
        );
        vm.prank(admin);
        results.reportResult(instId, resultData, Types.ResultSource.System, true);

        // Both consent
        vm.startPrank(admin);
        consents.submitConsent(instId, alice, true, "", "");
        consents.submitConsent(instId, bob, true, "", "");
        vm.stopPrank();

        uint256 bobBefore = token.balanceOf(bob);
        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(admin);
        settlements.settleContract(instId);

        // Bob gets everything, treasury gets nothing
        assertEq(token.balanceOf(bob) - bobBefore, 100e18, "Bob gets full escrow");
        assertEq(token.balanceOf(treasury) - treasuryBefore, 0, "Treasury gets nothing");
    }

    /// @notice Verify settlement with max 50% fee
    function test_settlement_maxFee() public {
        vm.prank(admin);
        bytes32 tplId = templates.createTemplate(
            "Max Fee RPS",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 50),
            Types.PaymentType.IXFreePoint,
            5000, // 50% fee
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
        bytes32 instId = _createInstance(tplId);

        token.mint(alice, MINT_AMOUNT);
        token.mint(bob, MINT_AMOUNT);
        vm.prank(alice);
        parties.joinContract(instId, CHALLENGER_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);
        vm.prank(bob);
        parties.joinContract(instId, OPPONENT_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);

        _activate(instId);

        bytes memory resultData = abi.encode(
            bob, "rock", "scissors", uint256(1), "1-0", false
        );
        vm.prank(admin);
        results.reportResult(instId, resultData, Types.ResultSource.System, true);

        vm.startPrank(admin);
        consents.submitConsent(instId, alice, true, "", "");
        consents.submitConsent(instId, bob, true, "", "");
        vm.stopPrank();

        uint256 bobBefore = token.balanceOf(bob);
        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(admin);
        settlements.settleContract(instId);

        // 50% fee: bob gets 50e18, treasury gets 50e18
        assertEq(token.balanceOf(bob) - bobBefore, 50e18, "Bob gets 50% at max fee");
        assertEq(token.balanceOf(treasury) - treasuryBefore, 50e18, "Treasury gets 50% at max fee");
    }

    // ========================================================================
    // TREASURY ADDRESS MANIPULATION
    // ========================================================================

    /// @notice Treasury cannot be set to zero address
    function test_setTreasury_zeroAddress_reverts() public {
        vm.prank(admin);
        vm.expectRevert(Types.InvalidTreasuryAddress.selector);
        settlements.setTreasury(address(0));
    }

    /// @notice Only DEFAULT_ADMIN_ROLE can set treasury
    function test_setTreasury_unauthorized_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        settlements.setTreasury(stranger);
    }
}
