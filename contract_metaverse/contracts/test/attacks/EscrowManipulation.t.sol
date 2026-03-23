// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {TestSetup} from "../helpers/TestSetup.sol";
import {Types} from "../../libraries/Types.sol";

/// @title EscrowManipulationTest -- Tests escrow deposit, release, and refund edge cases
/// @notice Verifies that escrow amounts are validated, isolated per contract instance,
///         and cannot be drained via repeated releaseEscrow calls.
contract EscrowManipulationTest is TestSetup {

    bytes32 public templateId;
    bytes32 public instanceId;

    function setUp() public override {
        super.setUp();
        (templateId, instanceId) = _fullSetup();
    }

    // ========================================================================
    // ZERO AMOUNT ATTACKS
    // ========================================================================

    /// @notice Join with 0 escrow amount must revert with InvalidAmount
    function test_joinWithZeroAmount_reverts() public {
        // Create a fresh instance for charlie
        address charlie = makeAddr("charlie");
        token.mint(charlie, MINT_AMOUNT);
        vm.prank(charlie);
        token.approve(address(parties), type(uint256).max);

        vm.prank(admin);
        bytes32 tplId2 = templates.createTemplate(
            "RPS Zero Test",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
        bytes32 instId2 = _createInstance(tplId2);

        vm.prank(charlie);
        vm.expectRevert(Types.InvalidAmount.selector);
        parties.joinContract(
            instId2,
            CHALLENGER_ROLE,
            0, // zero amount
            Types.PointType.IXFreePoint
        );
    }

    // ========================================================================
    // AMOUNT OUT OF RANGE ATTACKS
    // ========================================================================

    /// @notice Join with amount greater than maxBet must revert with BetOutOfRange
    function test_joinWithAmountAboveMaxBet_reverts() public {
        address charlie = makeAddr("charlie");
        token.mint(charlie, 200e18);
        vm.prank(charlie);
        token.approve(address(parties), type(uint256).max);

        vm.prank(admin);
        bytes32 tplId2 = templates.createTemplate(
            "RPS MaxBet Test",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15), // maxBet = 100e18
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
        bytes32 instId2 = _createInstance(tplId2);

        vm.prank(charlie);
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.BetOutOfRange.selector,
                uint128(150e18),
                uint128(10e18),
                uint128(100e18)
            )
        );
        parties.joinContract(
            instId2,
            CHALLENGER_ROLE,
            150e18, // above maxBet of 100e18
            Types.PointType.IXFreePoint
        );
    }

    /// @notice Join with amount below minBet must revert with BetOutOfRange
    function test_joinWithAmountBelowMinBet_reverts() public {
        address charlie = makeAddr("charlie");
        token.mint(charlie, 200e18);
        vm.prank(charlie);
        token.approve(address(parties), type(uint256).max);

        vm.prank(admin);
        bytes32 tplId2 = templates.createTemplate(
            "RPS MinBet Test",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15), // minBet = 10e18
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
        bytes32 instId2 = _createInstance(tplId2);

        vm.prank(charlie);
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.BetOutOfRange.selector,
                uint128(1e18),
                uint128(10e18),
                uint128(100e18)
            )
        );
        parties.joinContract(
            instId2,
            CHALLENGER_ROLE,
            1e18, // below minBet of 10e18
            Types.PointType.IXFreePoint
        );
    }

    // ========================================================================
    // DOUBLE RELEASE / DRAIN ATTACKS
    // ========================================================================

    /// @notice Try releaseEscrow multiple times to drain funds -- must be blocked
    ///         by _totalReleased tracking and EscrowOverRelease revert.
    function test_multipleReleaseEscrow_drainBlocked() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);
        _bothConsent(instanceId);

        // Total escrow is 100e18 (50e18 from alice + 50e18 from bob)
        uint128 totalEscrow = parties.getTotalEscrow(instanceId);
        assertEq(totalEscrow, 100e18);

        // Settle normally (releases 97e18 to winner + 3e18 to treasury = 100e18)
        vm.prank(admin);
        settlements.settleContract(instanceId);

        // After settlement, trying to release more escrow directly should fail
        // because _totalReleased == totalEscrow
        vm.prank(address(settlements));
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.EscrowOverRelease.selector,
                instanceId,
                totalEscrow,
                totalEscrow + 1e18
            )
        );
        parties.releaseEscrow(instanceId, bob, 1e18);
    }

    /// @notice releaseEscrow with amount exceeding total escrow must revert
    function test_releaseEscrow_exceedsTotalEscrow_reverts() public {
        _activate(instanceId);

        uint128 totalEscrow = parties.getTotalEscrow(instanceId);
        uint128 overAmount = totalEscrow + 1;

        vm.prank(address(settlements));
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.EscrowOverRelease.selector,
                instanceId,
                totalEscrow,
                overAmount
            )
        );
        parties.releaseEscrow(instanceId, bob, overAmount);
    }

    // ========================================================================
    // ESCROW ISOLATION PER CONTRACT INSTANCE
    // ========================================================================

    /// @notice Verify that escrow from one contract instance cannot leak to another
    function test_escrow_isolation_between_instances() public {
        // Instance 1 is already set up with 100e18 total escrow
        uint128 escrow1 = parties.getTotalEscrow(instanceId);
        assertEq(escrow1, 100e18);

        // Create instance 2
        token.mint(alice, MINT_AMOUNT);
        token.mint(bob, MINT_AMOUNT);

        vm.prank(admin);
        bytes32 tplId2 = templates.createTemplate(
            "RPS Isolation Test",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
        bytes32 instId2 = _createInstance(tplId2);
        vm.prank(alice);
        parties.joinContract(instId2, CHALLENGER_ROLE, 30e18, Types.PointType.IXFreePoint);
        vm.prank(bob);
        parties.joinContract(instId2, OPPONENT_ROLE, 30e18, Types.PointType.IXFreePoint);

        uint128 escrow2 = parties.getTotalEscrow(instId2);
        assertEq(escrow2, 60e18);

        // Verify isolation: each instance tracks its own escrow
        assertEq(parties.getTotalEscrow(instanceId), 100e18, "Instance 1 escrow unchanged");
        assertEq(parties.getTotalEscrow(instId2), 60e18, "Instance 2 escrow correct");

        // Settle instance 1
        _activate(instanceId);
        _submitResultBobWins(instanceId);
        _bothConsent(instanceId);
        vm.prank(admin);
        settlements.settleContract(instanceId);

        // Instance 2 escrow must be unaffected
        assertEq(parties.getTotalEscrow(instId2), 60e18, "Instance 2 escrow not affected by instance 1 settle");
    }

    // ========================================================================
    // DOUBLE JOIN ATTACKS
    // ========================================================================

    /// @notice Same user cannot join the same contract twice
    function test_doubleJoin_reverts() public {
        // Alice already joined in setUp via _fullSetup()
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Types.AlreadyJoined.selector, instanceId, alice)
        );
        parties.joinContract(
            instanceId,
            OPPONENT_ROLE,
            ESCROW_AMOUNT,
            Types.PointType.IXFreePoint
        );
    }

    // ========================================================================
    // JOIN AFTER ACTIVATION ATTACK
    // ========================================================================

    /// @notice Cannot join a contract that is already Active (must be Created)
    function test_joinAfterActivation_reverts() public {
        _activate(instanceId);

        address charlie = makeAddr("charlie");
        token.mint(charlie, MINT_AMOUNT);
        vm.prank(charlie);
        token.approve(address(parties), type(uint256).max);

        vm.prank(charlie);
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidState.selector,
                instanceId,
                Types.ContractStatus.Active
            )
        );
        parties.joinContract(
            instanceId,
            keccak256("spectator"),
            ESCROW_AMOUNT,
            Types.PointType.IXFreePoint
        );
    }

    // ========================================================================
    // REFUND AFTER SETTLEMENT ATTACK
    // ========================================================================

    /// @notice Cannot refund a contract that has already been settled
    function test_refundAfterSettle_reverts() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);
        _bothConsent(instanceId);

        vm.prank(admin);
        settlements.settleContract(instanceId);

        // Attempt refund after settle
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Types.SettlementAlreadyDone.selector, instanceId));
        settlements.refundContract(instanceId);
    }

    // ========================================================================
    // PAYMENT TYPE MISMATCH ATTACK
    // ========================================================================

    /// @notice Join with wrong escrow type (IXPoint when template requires IXFreePoint) must revert
    function test_paymentTypeMismatch_reverts() public {
        vm.prank(admin);
        bytes32 tplId2 = templates.createTemplate(
            "RPS PayType Test",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXPoint, // Requires IXPoint
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
        bytes32 instId2 = _createInstance(tplId2);

        address charlie = makeAddr("charlie");
        token.mint(charlie, MINT_AMOUNT);
        vm.prank(charlie);
        token.approve(address(parties), type(uint256).max);

        // Try to join with IXFreePoint when template requires IXPoint
        vm.prank(charlie);
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.PaymentTypeMismatch.selector,
                uint8(Types.PaymentType.IXPoint),
                uint8(Types.PointType.IXFreePoint)
            )
        );
        parties.joinContract(
            instId2,
            CHALLENGER_ROLE,
            ESCROW_AMOUNT,
            Types.PointType.IXFreePoint // Wrong type
        );
    }

    // ========================================================================
    // RELEASE TO ZERO ADDRESS ATTACK
    // ========================================================================

    /// @notice releaseEscrow to zero address must revert
    function test_releaseEscrow_zeroAddress_reverts() public {
        vm.prank(address(settlements));
        vm.expectRevert(Types.ZeroAddress.selector);
        parties.releaseEscrow(instanceId, address(0), ESCROW_AMOUNT);
    }

    /// @notice releaseEscrow with zero amount must revert
    function test_releaseEscrow_zeroAmount_reverts() public {
        vm.prank(address(settlements));
        vm.expectRevert(Types.InvalidAmount.selector);
        parties.releaseEscrow(instanceId, bob, 0);
    }

    // ========================================================================
    // TOKEN BALANCE VERIFICATION
    // ========================================================================

    /// @notice Verify exact token balances after full settlement lifecycle
    function test_tokenBalances_afterSettlement_correct() public {
        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore = token.balanceOf(bob);
        uint256 treasuryBefore = token.balanceOf(treasury);

        // Alice and Bob already escrowed in setUp
        assertEq(aliceBefore, MINT_AMOUNT - ESCROW_AMOUNT, "Alice post-escrow balance");
        assertEq(bobBefore, MINT_AMOUNT - ESCROW_AMOUNT, "Bob post-escrow balance");

        _activate(instanceId);
        _submitResultBobWins(instanceId);
        _bothConsent(instanceId);
        vm.prank(admin);
        settlements.settleContract(instanceId);

        // Fee = 100e18 * 300 / 10000 = 3e18
        // Winner (bob) gets 100e18 - 3e18 = 97e18
        uint256 aliceAfter = token.balanceOf(alice);
        uint256 bobAfter = token.balanceOf(bob);
        uint256 treasuryAfter = token.balanceOf(treasury);

        assertEq(aliceAfter, MINT_AMOUNT - ESCROW_AMOUNT, "Alice loses her escrow");
        assertEq(bobAfter, MINT_AMOUNT - ESCROW_AMOUNT + 97e18, "Bob gets winner amount");
        assertEq(treasuryAfter - treasuryBefore, 3e18, "Treasury gets fee");
        assertEq(
            aliceAfter + bobAfter + treasuryAfter,
            2 * MINT_AMOUNT,
            "Total token supply conserved"
        );
    }
}
