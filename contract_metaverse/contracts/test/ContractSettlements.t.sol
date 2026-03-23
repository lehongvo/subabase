// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TestSetup} from "./helpers/TestSetup.sol";
import {Types} from "../libraries/Types.sol";
import {IContractSettlements} from "../interfaces/IContractSettlements.sol";

/// @title ContractSettlementsTest -- Tests for settlement, refund, and fee distribution
contract ContractSettlementsTest is TestSetup {
    bytes32 internal templateId;
    bytes32 internal instanceId;

    function setUp() public override {
        super.setUp();
        (templateId, instanceId) = _fullSetup();
        _activate(instanceId);
    }

    // ========================================================================
    // settleContract — Winner scenario
    // ========================================================================

    /// @notice Settlement distributes 97e18 to winner and 3e18 to treasury
    function test_settleContract_WinnerAmounts() public {
        _submitResultBobWins(instanceId);
        _bothConsent(instanceId);

        uint256 bobBefore = token.balanceOf(bob);
        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(admin);
        settlements.settleContract(instanceId);

        // Bob won: should receive 97e18 (100e18 total - 3% fee)
        assertEq(token.balanceOf(bob), bobBefore + 97e18, "Winner should receive 97e18");
        // Treasury: should receive 3e18
        assertEq(token.balanceOf(treasury), treasuryBefore + 3e18, "Treasury should receive 3e18");
    }

    /// @notice Settlement emits ContractSettled event
    function test_settleContract_EmitsEvent() public {
        _submitResultBobWins(instanceId);
        _bothConsent(instanceId);

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IContractSettlements.ContractSettled(
            instanceId,
            100e18, // totalEscrow
            3e18,   // totalFees
            uint48(block.timestamp)
        );
        settlements.settleContract(instanceId);
    }

    /// @notice Settlement sets instance status to Settled
    function test_settleContract_StatusSettled() public {
        _submitResultBobWins(instanceId);
        _bothConsent(instanceId);

        vm.prank(admin);
        settlements.settleContract(instanceId);

        assertEq(
            uint8(instances.getInstanceStatus(instanceId)),
            uint8(Types.ContractStatus.Settled)
        );
    }

    /// @notice Settlement records are stored correctly
    function test_settleContract_RecordsStored() public {
        _submitResultBobWins(instanceId);
        _bothConsent(instanceId);

        vm.prank(admin);
        settlements.settleContract(instanceId);

        Types.Settlement[] memory setts = settlements.getSettlements(instanceId);
        assertEq(setts.length, 2, "Should have 2 settlement records (reward + fee)");
        assertTrue(settlements.isSettled(instanceId));
    }

    // ========================================================================
    // settleContract — Revert cases
    // ========================================================================

    /// @notice Cannot settle without all parties consenting
    function testRevert_settleContract_NotAllConsented() public {
        _submitResultBobWins(instanceId);

        // Only alice consents
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, true, "", "");

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Types.ConsentNotComplete.selector, instanceId));
        settlements.settleContract(instanceId);
    }

    /// @notice Cannot settle if instance is not in Completed/Resolved status
    function testRevert_settleContract_InvalidStatus() public {
        // Instance is Active, not Completed
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Types.InvalidState.selector, instanceId, Types.ContractStatus.Active)
        );
        settlements.settleContract(instanceId);
    }

    /// @notice Unauthorized caller cannot settle
    function testRevert_settleContract_Unauthorized() public {
        _submitResultBobWins(instanceId);
        _bothConsent(instanceId);

        vm.prank(stranger);
        vm.expectRevert();
        settlements.settleContract(instanceId);
    }

    /// @notice Cannot settle twice
    function testRevert_settleContract_AlreadySettled() public {
        _submitResultBobWins(instanceId);
        _bothConsent(instanceId);

        vm.prank(admin);
        settlements.settleContract(instanceId);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Types.SettlementAlreadyDone.selector, instanceId));
        settlements.settleContract(instanceId);
    }

    // ========================================================================
    // refundContract — Draw scenario
    // ========================================================================

    /// @notice Draw refund returns all escrow to parties, no fee charged
    function test_refundContract_DrawFullRefund() public {
        _submitResultDraw(instanceId);
        _bothConsent(instanceId);

        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore = token.balanceOf(bob);
        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(admin);
        settlements.refundContract(instanceId);

        assertEq(token.balanceOf(alice), aliceBefore + ESCROW_AMOUNT, "Alice should get full refund");
        assertEq(token.balanceOf(bob), bobBefore + ESCROW_AMOUNT, "Bob should get full refund");
        assertEq(token.balanceOf(treasury), treasuryBefore, "Treasury should get nothing on draw");
    }

    /// @notice Refund emits ContractRefunded event
    function test_refundContract_EmitsEvent() public {
        _submitResultDraw(instanceId);
        _bothConsent(instanceId);

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IContractSettlements.ContractRefunded(
            instanceId,
            100e18, // total refunded
            uint48(block.timestamp)
        );
        settlements.refundContract(instanceId);
    }

    // ========================================================================
    // After dispute: resolve -> settle
    // ========================================================================

    /// @notice Settling after dispute resolution distributes correct amounts
    function test_settleContract_AfterDisputeResolution() public {
        _submitResultBobWins(instanceId);

        // Alice disputes
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, false, "", "Dispute reason");

        // Admin resolves
        vm.prank(admin);
        instances.resolveInstance(instanceId);

        // Settle (consent check skipped for Resolved status)
        uint256 bobBefore = token.balanceOf(bob);
        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(admin);
        settlements.settleContract(instanceId);

        assertEq(token.balanceOf(bob), bobBefore + 97e18, "Winner gets 97e18 after dispute");
        assertEq(token.balanceOf(treasury), treasuryBefore + 3e18, "Treasury gets 3e18 after dispute");
    }
}
