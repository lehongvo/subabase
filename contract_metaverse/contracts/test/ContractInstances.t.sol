// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TestSetup} from "./helpers/TestSetup.sol";
import {Types} from "../libraries/Types.sol";
import {IContractInstances} from "../interfaces/IContractInstances.sol";

/// @title ContractInstancesTest -- Tests for instance lifecycle state machine
contract ContractInstancesTest is TestSetup {
    bytes32 internal templateId;

    function setUp() public override {
        super.setUp();
        templateId = _createRPSTemplate();
    }

    // ========================================================================
    // createInstance
    // ========================================================================

    /// @notice Creating an instance from an active template succeeds
    function test_createInstance_Success() public {
        bytes32 instanceId = _createInstance(templateId);
        assertTrue(instanceId != bytes32(0), "Instance ID should be non-zero");
        assertTrue(instances.instanceExists(instanceId), "Instance should exist");
    }

    /// @notice Creating an instance emits InstanceCreated event
    function test_createInstance_EmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(false, true, false, false);
        emit IContractInstances.InstanceCreated(
            bytes32(0), templateId, true, uint48(block.timestamp)
        );
        instances.createInstance(templateId, abi.encode("lobby", "session"));
    }

    /// @notice Cannot create instance from an inactive template
    function testRevert_createInstance_TemplateNotActive() public {
        vm.prank(admin);
        templates.deactivateTemplate(templateId);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Types.TemplateNotActive.selector, templateId));
        instances.createInstance(templateId, abi.encode("lobby", "session"));
    }

    /// @notice Unauthorized caller cannot create instance
    function testRevert_createInstance_Unauthorized() public {
        vm.prank(stranger);
        vm.expectRevert();
        instances.createInstance(templateId, abi.encode("lobby", "session"));
    }

    // ========================================================================
    // Valid transitions (6 tests)
    // ========================================================================

    /// @notice Created -> Active: succeeds when 2 parties have joined
    function test_transition_CreatedToActive() public {
        bytes32 instanceId = _createInstance(templateId);
        _aliceJoins(instanceId);
        _bobJoins(instanceId);
        _activate(instanceId);

        Types.ContractStatus status = instances.getInstanceStatus(instanceId);
        assertEq(uint8(status), uint8(Types.ContractStatus.Active));
    }

    /// @notice Active -> Completed: succeeds when result is reported as final
    function test_transition_ActiveToCompleted() public {
        bytes32 instanceId = _createInstance(templateId);
        _aliceJoins(instanceId);
        _bobJoins(instanceId);
        _activate(instanceId);
        _submitResultBobWins(instanceId);

        Types.ContractStatus status = instances.getInstanceStatus(instanceId);
        assertEq(uint8(status), uint8(Types.ContractStatus.Completed));
    }

    /// @notice Completed -> Settled: succeeds when all consent and settlement executed
    function test_transition_CompletedToSettled() public {
        (bytes32 _tid, bytes32 instanceId) = _fullSetup();
        _activate(instanceId);
        _submitResultBobWins(instanceId);
        _bothConsent(instanceId);

        vm.prank(admin);
        settlements.settleContract(instanceId);

        Types.ContractStatus status = instances.getInstanceStatus(instanceId);
        assertEq(uint8(status), uint8(Types.ContractStatus.Settled));
    }

    /// @notice Completed -> Disputed: succeeds when a party disputes
    function test_transition_CompletedToDisputed() public {
        (bytes32 _tid, bytes32 instanceId) = _fullSetup();
        _activate(instanceId);
        _submitResultBobWins(instanceId);

        // Alice disputes
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, false, "", "Server lag");

        Types.ContractStatus status = instances.getInstanceStatus(instanceId);
        assertEq(uint8(status), uint8(Types.ContractStatus.Disputed));
    }

    /// @notice Disputed -> Resolved: admin resolves a dispute
    function test_transition_DisputedToResolved() public {
        (bytes32 _tid, bytes32 instanceId) = _fullSetup();
        _activate(instanceId);
        _submitResultBobWins(instanceId);

        vm.prank(admin);
        consents.submitConsent(instanceId, alice, false, "", "Dispute reason");

        vm.prank(admin);
        instances.resolveInstance(instanceId);

        Types.ContractStatus status = instances.getInstanceStatus(instanceId);
        assertEq(uint8(status), uint8(Types.ContractStatus.Resolved));
    }

    /// @notice Resolved -> Settled: settlement after dispute resolution
    function test_transition_ResolvedToSettled() public {
        (bytes32 _tid, bytes32 instanceId) = _fullSetup();
        _activate(instanceId);
        _submitResultBobWins(instanceId);

        vm.prank(admin);
        consents.submitConsent(instanceId, alice, false, "", "Dispute");

        vm.prank(admin);
        instances.resolveInstance(instanceId);

        vm.prank(admin);
        settlements.settleContract(instanceId);

        Types.ContractStatus status = instances.getInstanceStatus(instanceId);
        assertEq(uint8(status), uint8(Types.ContractStatus.Settled));
    }

    // ========================================================================
    // Invalid transitions (10+ tests)
    // ========================================================================

    /// @notice Created -> Completed: invalid
    function testRevert_transition_CreatedToCompleted() public {
        bytes32 instanceId = _createInstance(templateId);

        // Try to complete directly — requires CONTRACT_ROLE
        vm.prank(address(results));
        vm.expectRevert();
        instances.completeInstance(instanceId);
    }

    /// @notice Created -> Disputed: invalid
    function testRevert_transition_CreatedToDisputed() public {
        bytes32 instanceId = _createInstance(templateId);
        vm.prank(address(consents));
        vm.expectRevert();
        instances.disputeInstance(instanceId);
    }

    /// @notice Created -> Resolved: invalid
    function testRevert_transition_CreatedToResolved() public {
        bytes32 instanceId = _createInstance(templateId);
        vm.prank(admin);
        vm.expectRevert();
        instances.resolveInstance(instanceId);
    }

    /// @notice Created -> Settled: invalid
    function testRevert_transition_CreatedToSettled() public {
        bytes32 instanceId = _createInstance(templateId);
        vm.prank(address(settlements));
        vm.expectRevert();
        instances.settleInstance(instanceId);
    }

    /// @notice Active -> Disputed: invalid (must go through Completed first)
    function testRevert_transition_ActiveToDisputed() public {
        bytes32 instanceId = _createInstance(templateId);
        _aliceJoins(instanceId);
        _bobJoins(instanceId);
        _activate(instanceId);

        vm.prank(address(consents));
        vm.expectRevert();
        instances.disputeInstance(instanceId);
    }

    /// @notice Active -> Settled: invalid
    function testRevert_transition_ActiveToSettled() public {
        bytes32 instanceId = _createInstance(templateId);
        _aliceJoins(instanceId);
        _bobJoins(instanceId);
        _activate(instanceId);

        vm.prank(address(settlements));
        vm.expectRevert();
        instances.settleInstance(instanceId);
    }

    /// @notice Active -> Resolved: invalid
    function testRevert_transition_ActiveToResolved() public {
        bytes32 instanceId = _createInstance(templateId);
        _aliceJoins(instanceId);
        _bobJoins(instanceId);
        _activate(instanceId);

        vm.prank(admin);
        vm.expectRevert();
        instances.resolveInstance(instanceId);
    }

    /// @notice Completed -> Active: invalid (no backward transitions)
    function testRevert_transition_CompletedToActive() public {
        (bytes32 _tid, bytes32 instanceId) = _fullSetup();
        _activate(instanceId);
        _submitResultBobWins(instanceId);

        vm.prank(admin);
        vm.expectRevert();
        instances.activateInstance(instanceId);
    }

    /// @notice Disputed -> Completed: invalid
    function testRevert_transition_DisputedToCompleted() public {
        (bytes32 _tid, bytes32 instanceId) = _fullSetup();
        _activate(instanceId);
        _submitResultBobWins(instanceId);

        vm.prank(admin);
        consents.submitConsent(instanceId, alice, false, "", "Dispute");

        vm.prank(address(results));
        vm.expectRevert();
        instances.completeInstance(instanceId);
    }

    /// @notice Settled -> anything: terminal state, no transitions
    function testRevert_transition_SettledToAnything() public {
        (bytes32 _tid, bytes32 instanceId) = _fullSetup();
        _activate(instanceId);
        _submitResultBobWins(instanceId);
        _bothConsent(instanceId);
        vm.prank(admin);
        settlements.settleContract(instanceId);

        vm.prank(admin);
        vm.expectRevert();
        instances.activateInstance(instanceId);
    }

    // ========================================================================
    // Access control
    // ========================================================================

    /// @notice Unauthorized caller cannot activate instance
    function testRevert_activateInstance_Unauthorized() public {
        bytes32 instanceId = _createInstance(templateId);
        _aliceJoins(instanceId);
        _bobJoins(instanceId);

        vm.prank(stranger);
        vm.expectRevert();
        instances.activateInstance(instanceId);
    }

    /// @notice Unauthorized caller cannot resolve instance
    function testRevert_resolveInstance_Unauthorized() public {
        (bytes32 _tid, bytes32 instanceId) = _fullSetup();
        _activate(instanceId);
        _submitResultBobWins(instanceId);
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, false, "", "dispute");

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Types.Unauthorized.selector));
        instances.resolveInstance(instanceId);
    }

    /// @notice Cannot activate with fewer than 2 parties
    function testRevert_activateInstance_InsufficientParties() public {
        bytes32 instanceId = _createInstance(templateId);
        _aliceJoins(instanceId);
        // Only 1 party

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Types.InvalidState.selector, instanceId, Types.ContractStatus.Created)
        );
        instances.activateInstance(instanceId);
    }

    // ========================================================================
    // View functions
    // ========================================================================

    /// @notice getInstance returns correct data
    function test_getInstance_Success() public {
        bytes32 instanceId = _createInstance(templateId);
        Types.Instance memory inst = instances.getInstance(instanceId);
        assertEq(inst.templateId, templateId);
        assertEq(uint8(inst.status), uint8(Types.ContractStatus.Created));
    }

    /// @notice getInstance reverts for non-existent instance
    function testRevert_getInstance_NotFound() public {
        bytes32 fakeId = keccak256("fake");
        vm.expectRevert(abi.encodeWithSelector(Types.ContractNotFound.selector, fakeId));
        instances.getInstance(fakeId);
    }

    /// @notice instanceExists returns false for non-existent instance
    function test_instanceExists_False() public {
        assertFalse(instances.instanceExists(keccak256("nonexistent")));
    }
}
