// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TestSetup} from "./helpers/TestSetup.sol";
import {Types} from "../libraries/Types.sol";

/// @title IntegrationTest -- End-to-end lifecycle tests replicating the RPS walkthrough
/// @notice These tests verify the exact financial outcomes described in the
///         rps-lifecycle-walkthrough.md document.
contract IntegrationTest is TestSetup {
    // ========================================================================
    // test_FullLifecycle_BWins
    // ========================================================================

    /// @notice Full RPS lifecycle: A=100e18, B=100e18, fee 3%, B wins
    ///         Expected: A=50e18, B=147e18, Treasury=3e18
    function test_FullLifecycle_BWins() public {
        // --- Initial state ---
        assertEq(token.balanceOf(alice), 100e18, "Alice initial balance");
        assertEq(token.balanceOf(bob), 100e18, "Bob initial balance");

        // --- Step 1: Create template (3% fee) ---
        bytes32 templateId = _createRPSTemplate();

        // --- Step 2: Create instance ---
        bytes32 instanceId = _createInstance(templateId);

        // --- Step 3: Both parties join with 50e18 escrow ---
        _aliceJoins(instanceId);
        assertEq(token.balanceOf(alice), 50e18, "Alice after joining");

        _bobJoins(instanceId);
        assertEq(token.balanceOf(bob), 50e18, "Bob after joining");

        // Verify escrow state
        assertEq(parties.getTotalEscrow(instanceId), 100e18, "Total escrow");
        assertEq(token.balanceOf(address(parties)), 100e18, "Parties contract holds escrow");

        // --- Step 4: Activate contract ---
        _activate(instanceId);
        assertEq(
            uint8(instances.getInstanceStatus(instanceId)),
            uint8(Types.ContractStatus.Active)
        );

        // --- Step 5: Submit result (B wins) ---
        _submitResultBobWins(instanceId);
        assertEq(
            uint8(instances.getInstanceStatus(instanceId)),
            uint8(Types.ContractStatus.Completed)
        );

        // --- Step 6: Both parties consent ---
        _bothConsent(instanceId);
        assertTrue(consents.allConsented(instanceId));

        // --- Step 7: Settlement ---
        vm.prank(admin);
        settlements.settleContract(instanceId);

        // --- Final assertions ---
        assertEq(
            uint8(instances.getInstanceStatus(instanceId)),
            uint8(Types.ContractStatus.Settled),
            "Instance should be Settled"
        );

        assertEq(token.balanceOf(alice), 50e18, "Alice final: 50e18 (lost escrow)");
        assertEq(token.balanceOf(bob), 147e18, "Bob final: 50 + 97 = 147e18");
        assertEq(token.balanceOf(treasury), 3e18, "Treasury final: 3e18 fee");

        // Verify settlement records
        Types.Settlement[] memory setts = settlements.getSettlements(instanceId);
        assertEq(setts.length, 2, "2 settlement records (reward + fee)");
        assertTrue(settlements.isSettled(instanceId), "Should be marked settled");
    }

    // ========================================================================
    // test_FullLifecycle_Dispute
    // ========================================================================

    /// @notice Full lifecycle with dispute: A disputes, admin resolves, same financial outcome
    function test_FullLifecycle_Dispute() public {
        // Setup
        bytes32 templateId = _createRPSTemplate();
        bytes32 instanceId = _createInstance(templateId);
        _aliceJoins(instanceId);
        _bobJoins(instanceId);
        _activate(instanceId);
        _submitResultBobWins(instanceId);

        // --- Alice disputes ---
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, false, "", "Server lag, my move was not registered.");
        assertEq(
            uint8(instances.getInstanceStatus(instanceId)),
            uint8(Types.ContractStatus.Disputed)
        );
        assertTrue(consents.hasDispute(instanceId));

        // --- Admin resolves the dispute (upholds original result) ---
        vm.prank(admin);
        instances.resolveInstance(instanceId);
        assertEq(
            uint8(instances.getInstanceStatus(instanceId)),
            uint8(Types.ContractStatus.Resolved)
        );

        // --- Settlement (consent check skipped for Resolved) ---
        vm.prank(admin);
        settlements.settleContract(instanceId);

        // --- Same financial outcome as BWins ---
        assertEq(token.balanceOf(alice), 50e18, "Alice final: 50e18");
        assertEq(token.balanceOf(bob), 147e18, "Bob final: 147e18");
        assertEq(token.balanceOf(treasury), 3e18, "Treasury final: 3e18");

        assertEq(
            uint8(instances.getInstanceStatus(instanceId)),
            uint8(Types.ContractStatus.Settled)
        );
    }

    // ========================================================================
    // test_FullLifecycle_Draw
    // ========================================================================

    /// @notice Full lifecycle draw: both get full refund, no fee
    ///         Expected: A=100e18, B=100e18, Treasury=0
    function test_FullLifecycle_Draw() public {
        // Setup
        bytes32 templateId = _createRPSTemplate();
        bytes32 instanceId = _createInstance(templateId);
        _aliceJoins(instanceId);
        _bobJoins(instanceId);
        _activate(instanceId);

        // Submit draw result
        _submitResultDraw(instanceId);
        assertEq(
            uint8(instances.getInstanceStatus(instanceId)),
            uint8(Types.ContractStatus.Completed)
        );

        // Both consent
        _bothConsent(instanceId);
        assertTrue(consents.allConsented(instanceId));

        // Refund (draw scenario)
        vm.prank(admin);
        settlements.refundContract(instanceId);

        // --- Final assertions ---
        assertEq(token.balanceOf(alice), 100e18, "Alice final: full refund 100e18");
        assertEq(token.balanceOf(bob), 100e18, "Bob final: full refund 100e18");
        assertEq(token.balanceOf(treasury), 0, "Treasury final: 0 (no fee on draw)");

        assertEq(
            uint8(instances.getInstanceStatus(instanceId)),
            uint8(Types.ContractStatus.Settled)
        );
    }

    // ========================================================================
    // test_FullLifecycle_TimeoutAutoConsent
    // ========================================================================

    /// @notice Timeout auto-consent: only A consents, time passes, B auto-consented
    function test_FullLifecycle_TimeoutAutoConsent() public {
        // Setup
        bytes32 templateId = _createRPSTemplate();
        bytes32 instanceId = _createInstance(templateId);
        _aliceJoins(instanceId);
        _bobJoins(instanceId);
        _activate(instanceId);
        _submitResultBobWins(instanceId);

        // Only Alice consents
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, true, "", "");
        assertFalse(consents.allConsented(instanceId), "Not all consented yet");

        // Get consent deadline
        uint48 deadline = consents.getConsentDeadline(instanceId);
        assertGt(deadline, 0, "Deadline should be set");

        // Warp past deadline (timeout = 15 seconds as configured in template)
        vm.warp(uint256(deadline) + 1);

        // Auto-consent for Bob
        vm.prank(admin);
        consents.autoConsent(instanceId, bob);
        assertTrue(consents.allConsented(instanceId), "All should be consented after auto-consent");

        // Now settle normally
        vm.prank(admin);
        settlements.settleContract(instanceId);

        // --- Final assertions (same as BWins) ---
        assertEq(token.balanceOf(alice), 50e18, "Alice final: 50e18");
        assertEq(token.balanceOf(bob), 147e18, "Bob final: 147e18");
        assertEq(token.balanceOf(treasury), 3e18, "Treasury final: 3e18");

        assertEq(
            uint8(instances.getInstanceStatus(instanceId)),
            uint8(Types.ContractStatus.Settled)
        );
    }
}
