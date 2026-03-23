// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {TestSetup} from "../helpers/TestSetup.sol";
import {Types} from "../../libraries/Types.sol";

/// @title StateMachineAttackTest -- Verifies the contract lifecycle state machine
///        cannot be subverted. Tests all invalid transitions, skip attacks,
///        reverse attacks, and double-action attacks.
///
///        Valid state machine:
///          Created -> Active -> Completed -> Settled
///              |         |           |
///              |         |       Disputed -> Resolved -> Settled
///              |         |
///              +-> Settled (cancellation)
///              Active -> Settled (cancellation)
///
///        All other transitions must revert with InvalidTransition.
contract StateMachineAttackTest is TestSetup {

    bytes32 public templateId;
    bytes32 public instanceId;

    function setUp() public override {
        super.setUp();
        (templateId, instanceId) = _fullSetup();
    }

    // ========================================================================
    // SKIP STATE ATTACKS
    // ========================================================================

    /// @notice Created -> Completed directly (skipping Active) must revert
    function test_skip_created_to_completed_reverts() public {
        // Instance is in Created state. Try to complete it directly.
        vm.prank(address(results));
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidTransition.selector,
                instanceId,
                Types.ContractStatus.Created,
                Types.ContractStatus.Completed
            )
        );
        instances.completeInstance(instanceId);
    }

    /// @notice Created -> Settled directly is now valid (cancellation path)
    function test_created_to_settled_succeeds() public {
        vm.prank(address(settlements));
        instances.settleInstance(instanceId);

        assertEq(
            uint8(instances.getInstanceStatus(instanceId)),
            uint8(Types.ContractStatus.Settled)
        );
    }

    /// @notice Created -> Disputed directly must revert
    function test_skip_created_to_disputed_reverts() public {
        vm.prank(address(consents));
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidTransition.selector,
                instanceId,
                Types.ContractStatus.Created,
                Types.ContractStatus.Disputed
            )
        );
        instances.disputeInstance(instanceId);
    }

    /// @notice Created -> Resolved directly must revert
    function test_skip_created_to_resolved_reverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidTransition.selector,
                instanceId,
                Types.ContractStatus.Created,
                Types.ContractStatus.Resolved
            )
        );
        instances.resolveInstance(instanceId);
    }

    /// @notice Active -> Settled directly is now valid (cancellation path)
    function test_active_to_settled_succeeds() public {
        _activate(instanceId);

        vm.prank(address(settlements));
        instances.settleInstance(instanceId);

        assertEq(
            uint8(instances.getInstanceStatus(instanceId)),
            uint8(Types.ContractStatus.Settled)
        );
    }

    /// @notice Active -> Disputed directly (skipping Completed) must revert
    function test_skip_active_to_disputed_reverts() public {
        _activate(instanceId);

        vm.prank(address(consents));
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidTransition.selector,
                instanceId,
                Types.ContractStatus.Active,
                Types.ContractStatus.Disputed
            )
        );
        instances.disputeInstance(instanceId);
    }

    /// @notice Active -> Resolved directly must revert
    function test_skip_active_to_resolved_reverts() public {
        _activate(instanceId);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidTransition.selector,
                instanceId,
                Types.ContractStatus.Active,
                Types.ContractStatus.Resolved
            )
        );
        instances.resolveInstance(instanceId);
    }

    /// @notice Completed -> Resolved directly (skipping Disputed) must revert
    function test_skip_completed_to_resolved_reverts() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);
        // Now in Completed state

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidTransition.selector,
                instanceId,
                Types.ContractStatus.Completed,
                Types.ContractStatus.Resolved
            )
        );
        instances.resolveInstance(instanceId);
    }

    // ========================================================================
    // REVERSE STATE ATTACKS
    // ========================================================================

    /// @notice Active -> Created must revert (cannot go backwards)
    function test_reverse_active_to_created_reverts() public {
        _activate(instanceId);

        // There is no function to transition to Created, but try activating again
        // which would be Active -> Active, also invalid
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidTransition.selector,
                instanceId,
                Types.ContractStatus.Active,
                Types.ContractStatus.Active
            )
        );
        instances.activateInstance(instanceId);
    }

    /// @notice Completed -> Active must revert (cannot go backwards)
    function test_reverse_completed_to_active_reverts() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);
        // Now in Completed state

        // Try to activate again (Completed -> Active)
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidTransition.selector,
                instanceId,
                Types.ContractStatus.Completed,
                Types.ContractStatus.Active
            )
        );
        instances.activateInstance(instanceId);
    }

    /// @notice Settled -> any state must revert (terminal state)
    function test_settled_is_terminal() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);
        _bothConsent(instanceId);

        vm.prank(admin);
        settlements.settleContract(instanceId);
        // Now in Settled state

        // Try every possible transition from Settled
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidTransition.selector,
                instanceId,
                Types.ContractStatus.Settled,
                Types.ContractStatus.Active
            )
        );
        instances.activateInstance(instanceId);

        vm.prank(address(results));
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidTransition.selector,
                instanceId,
                Types.ContractStatus.Settled,
                Types.ContractStatus.Completed
            )
        );
        instances.completeInstance(instanceId);

        vm.prank(address(consents));
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidTransition.selector,
                instanceId,
                Types.ContractStatus.Settled,
                Types.ContractStatus.Disputed
            )
        );
        instances.disputeInstance(instanceId);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidTransition.selector,
                instanceId,
                Types.ContractStatus.Settled,
                Types.ContractStatus.Resolved
            )
        );
        instances.resolveInstance(instanceId);

        vm.prank(address(settlements));
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidTransition.selector,
                instanceId,
                Types.ContractStatus.Settled,
                Types.ContractStatus.Settled
            )
        );
        instances.settleInstance(instanceId);
    }

    // ========================================================================
    // DOUBLE ACTION ATTACKS
    // ========================================================================

    /// @notice Double settle must revert
    function test_double_settle_reverts() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);
        _bothConsent(instanceId);

        vm.prank(admin);
        settlements.settleContract(instanceId);

        // Second settle must fail
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Types.SettlementAlreadyDone.selector, instanceId));
        settlements.settleContract(instanceId);
    }

    /// @notice Double refund must revert
    function test_double_refund_reverts() public {
        _activate(instanceId);
        _submitResultDraw(instanceId);
        _bothConsent(instanceId);

        vm.prank(admin);
        settlements.refundContract(instanceId);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Types.SettlementAlreadyDone.selector, instanceId));
        settlements.refundContract(instanceId);
    }

    /// @notice Submit result when not Active must revert
    function test_reportResult_when_created_reverts() public {
        // Instance is in Created state (not yet activated)
        bytes memory resultData = abi.encode(
            bob, "rock", "scissors", uint256(1), "1-0", false
        );

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidState.selector,
                instanceId,
                Types.ContractStatus.Created
            )
        );
        results.reportResult(instanceId, resultData, Types.ResultSource.System, true);
    }

    /// @notice Submit result when already Completed must revert
    function test_reportResult_when_completed_reverts() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);
        // Now in Completed state

        bytes memory resultData = abi.encode(
            alice, "paper", "rock", uint256(1), "1-0", false
        );

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidState.selector,
                instanceId,
                Types.ContractStatus.Completed
            )
        );
        results.reportResult(instanceId, resultData, Types.ResultSource.System, true);
    }

    /// @notice Double result submission on active instance must revert
    ///         (first isFinal=true result blocks any subsequent)
    function test_double_final_result_reverts() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);
        // Instance moves to Completed after final result

        // Try again -- instance is now Completed, not Active
        bytes memory resultData = abi.encode(
            alice, "paper", "rock", uint256(1), "1-0", false
        );
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidState.selector,
                instanceId,
                Types.ContractStatus.Completed
            )
        );
        results.reportResult(instanceId, resultData, Types.ResultSource.System, true);
    }

    /// @notice Double consent submission by same user must revert
    function test_double_consent_reverts() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);

        vm.startPrank(admin);
        consents.submitConsent(instanceId, alice, true, "", "");

        // Alice tries to consent again
        vm.expectRevert(
            abi.encodeWithSelector(Types.AlreadyConsented.selector, instanceId, alice)
        );
        consents.submitConsent(instanceId, alice, true, "", "");
        vm.stopPrank();
    }

    /// @notice Settle when consent not complete must revert
    function test_settle_without_consent_reverts() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);

        // Only alice consents, bob does not
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, true, "", "");

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Types.ConsentNotComplete.selector, instanceId)
        );
        settlements.settleContract(instanceId);
    }

    // ========================================================================
    // DISPUTE/RESOLVE FLOW
    // ========================================================================

    /// @notice Disputed -> Active must revert (can only go to Resolved)
    function test_disputed_to_active_reverts() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, false, "", "dispute");
        // Now in Disputed state

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidTransition.selector,
                instanceId,
                Types.ContractStatus.Disputed,
                Types.ContractStatus.Active
            )
        );
        instances.activateInstance(instanceId);
    }

    /// @notice Disputed -> Completed must revert
    function test_disputed_to_completed_reverts() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, false, "", "dispute");

        vm.prank(address(results));
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidTransition.selector,
                instanceId,
                Types.ContractStatus.Disputed,
                Types.ContractStatus.Completed
            )
        );
        instances.completeInstance(instanceId);
    }

    /// @notice Disputed -> Settled must revert (must go through Resolved first)
    function test_disputed_to_settled_reverts() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, false, "", "dispute");

        vm.prank(address(settlements));
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidTransition.selector,
                instanceId,
                Types.ContractStatus.Disputed,
                Types.ContractStatus.Settled
            )
        );
        instances.settleInstance(instanceId);
    }

    /// @notice Valid full dispute resolution flow succeeds
    function test_valid_dispute_resolution_flow() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);

        // Alice disputes
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, false, "", "I dispute");

        // Verify Disputed state
        assertEq(
            uint8(instances.getInstanceStatus(instanceId)),
            uint8(Types.ContractStatus.Disputed)
        );

        // Admin resolves
        vm.prank(admin);
        instances.resolveInstance(instanceId);

        // Verify Resolved state
        assertEq(
            uint8(instances.getInstanceStatus(instanceId)),
            uint8(Types.ContractStatus.Resolved)
        );

        // Settle after resolution
        vm.prank(admin);
        settlements.settleContract(instanceId);

        // Verify Settled (terminal)
        assertEq(
            uint8(instances.getInstanceStatus(instanceId)),
            uint8(Types.ContractStatus.Settled)
        );
    }
}
