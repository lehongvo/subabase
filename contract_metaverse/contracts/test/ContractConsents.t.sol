// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TestSetup} from "./helpers/TestSetup.sol";
import {Types} from "../libraries/Types.sol";
import {IContractConsents} from "../interfaces/IContractConsents.sol";

/// @title ContractConsentsTest -- Tests for consent submission, disputes, auto-consent
contract ContractConsentsTest is TestSetup {
    bytes32 internal templateId;
    bytes32 internal instanceId;

    function setUp() public override {
        super.setUp();
        (templateId, instanceId) = _fullSetup();
        _activate(instanceId);
        _submitResultBobWins(instanceId);
        // Instance is now in Completed status
    }

    // ========================================================================
    // submitConsent — Happy path
    // ========================================================================

    /// @notice Single party consent succeeds
    function test_submitConsent_SingleParty() public {
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, true, "", "");

        Types.Consent memory c = consents.getConsent(instanceId, alice);
        assertTrue(c.consented);
        assertEq(c.userId, alice);
        assertGt(c.consentedAt, 0);
    }

    /// @notice Both parties consenting makes allConsented return true
    function test_submitConsent_BothParties() public {
        _bothConsent(instanceId);
        assertTrue(consents.allConsented(instanceId));
    }

    /// @notice submitConsent emits ConsentSubmitted event
    function test_submitConsent_EmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit IContractConsents.ConsentSubmitted(
            instanceId, alice, true, uint48(block.timestamp)
        );
        consents.submitConsent(instanceId, alice, true, "", "");
    }

    // ========================================================================
    // Dispute flow
    // ========================================================================

    /// @notice Submitting consented=false triggers disputeInstance
    function test_submitConsent_DisputeTriggered() public {
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, false, "", "Server lag");

        Types.ContractStatus status = instances.getInstanceStatus(instanceId);
        assertEq(uint8(status), uint8(Types.ContractStatus.Disputed));
    }

    /// @notice Dispute emits DisputeRaised event
    function test_submitConsent_DisputeEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit IContractConsents.DisputeRaised(instanceId, alice, "Lag", uint48(block.timestamp));
        consents.submitConsent(instanceId, alice, false, "", "Lag");
    }

    /// @notice hasDispute returns true after a dispute is raised
    function test_hasDispute_True() public {
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, false, "", "Dispute reason");
        assertTrue(consents.hasDispute(instanceId));
    }

    // ========================================================================
    // submitConsent — Revert cases
    // ========================================================================

    /// @notice Non-party cannot submit consent
    function testRevert_submitConsent_NotAParty() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Types.NotAParty.selector, instanceId, stranger));
        consents.submitConsent(instanceId, stranger, true, "", "");
    }

    /// @notice Cannot consent twice
    function testRevert_submitConsent_AlreadyConsented() public {
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, true, "", "");

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Types.AlreadyConsented.selector, instanceId, alice));
        consents.submitConsent(instanceId, alice, true, "", "");
    }

    /// @notice Cannot consent when instance is not in Completed/Resolved status
    function testRevert_submitConsent_InvalidStatus() public {
        // Create a fresh instance in Created status
        bytes32 freshId = _createInstance(templateId);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Types.InvalidState.selector, freshId, Types.ContractStatus.Created)
        );
        consents.submitConsent(freshId, alice, true, "", "");
    }

    /// @notice Unauthorized caller cannot submit consent
    function testRevert_submitConsent_Unauthorized() public {
        vm.prank(stranger);
        vm.expectRevert();
        consents.submitConsent(instanceId, alice, true, "", "");
    }

    // ========================================================================
    // autoConsent (timeout)
    // ========================================================================

    /// @notice Auto-consent works after deadline passes
    function test_autoConsent_AfterTimeout() public {
        // Alice consents first (sets the deadline)
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, true, "", "");

        // Get the deadline
        uint48 deadline = consents.getConsentDeadline(instanceId);
        assertGt(deadline, 0, "Deadline should be set");

        // Warp past deadline
        vm.warp(uint256(deadline) + 1);

        // Auto-consent for bob
        vm.prank(admin);
        consents.autoConsent(instanceId, bob);

        assertTrue(consents.allConsented(instanceId), "All should be consented after auto-consent");
    }

    /// @notice Auto-consent emits AutoConsentApplied event
    function test_autoConsent_EmitsEvent() public {
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, true, "", "");

        uint48 deadline = consents.getConsentDeadline(instanceId);
        vm.warp(uint256(deadline) + 1);

        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit IContractConsents.AutoConsentApplied(instanceId, bob, uint48(block.timestamp));
        consents.autoConsent(instanceId, bob);
    }

    /// @notice Auto-consent reverts before deadline
    function testRevert_autoConsent_BeforeDeadline() public {
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, true, "", "");

        // Do not warp time — deadline not yet reached
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Types.ConsentNotComplete.selector, instanceId));
        consents.autoConsent(instanceId, bob);
    }

    // ========================================================================
    // View functions
    // ========================================================================

    /// @notice getConsentCount tracks count correctly
    function test_getConsentCount() public {
        assertEq(consents.getConsentCount(instanceId), 0);

        vm.prank(admin);
        consents.submitConsent(instanceId, alice, true, "", "");
        assertEq(consents.getConsentCount(instanceId), 1);

        vm.prank(admin);
        consents.submitConsent(instanceId, bob, true, "", "");
        assertEq(consents.getConsentCount(instanceId), 2);
    }

    /// @notice allConsented returns false when only one party has consented
    function test_allConsented_FalseWhenIncomplete() public {
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, true, "", "");
        assertFalse(consents.allConsented(instanceId));
    }
}
