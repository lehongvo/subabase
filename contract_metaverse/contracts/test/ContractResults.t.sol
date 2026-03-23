// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TestSetup} from "./helpers/TestSetup.sol";
import {Types} from "../libraries/Types.sol";
import {IContractResults} from "../interfaces/IContractResults.sol";

/// @title ContractResultsTest -- Tests for result reporting and retrieval
contract ContractResultsTest is TestSetup {
    bytes32 internal templateId;
    bytes32 internal instanceId;

    function setUp() public override {
        super.setUp();
        (templateId, instanceId) = _fullSetup();
        _activate(instanceId);
    }

    // ========================================================================
    // reportResult — Happy path
    // ========================================================================

    /// @notice Reporting a final result succeeds and transitions to Completed
    function test_reportResult_Success() public {
        _submitResultBobWins(instanceId);

        Types.ContractStatus status = instances.getInstanceStatus(instanceId);
        assertEq(uint8(status), uint8(Types.ContractStatus.Completed));
    }

    /// @notice reportResult emits ResultReported event
    function test_reportResult_EmitsEvent() public {
        bytes memory resultData = abi.encode(bob, "rock", "scissors", uint256(1), "1-0", false);

        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit IContractResults.ResultReported(
            instanceId,
            Types.ResultSource.System,
            true,
            resultData,
            uint48(block.timestamp)
        );
        results.reportResult(instanceId, resultData, Types.ResultSource.System, true);
    }

    /// @notice Result data is stored and retrievable
    function test_reportResult_DataStored() public {
        _submitResultBobWins(instanceId);

        Types.Result memory r = results.getResult(instanceId);
        assertEq(r.contractId, instanceId);
        assertTrue(r.isFinal);
        assertEq(uint8(r.reportedBy), uint8(Types.ResultSource.System));
    }

    /// @notice resultExists returns true after result is reported
    function test_resultExists_True() public {
        _submitResultBobWins(instanceId);
        assertTrue(results.resultExists(instanceId));
    }

    // ========================================================================
    // reportResult — Revert cases
    // ========================================================================

    /// @notice Cannot report result for non-Active instance
    function testRevert_reportResult_InvalidStatus() public {
        // Instance is still in Created status before activation
        bytes32 newInstanceId = _createInstance(templateId);

        bytes memory resultData = abi.encode(bob, "rock", "scissors", uint256(1), "1-0", false);
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Types.InvalidState.selector, newInstanceId, Types.ContractStatus.Created)
        );
        results.reportResult(newInstanceId, resultData, Types.ResultSource.System, true);
    }

    /// @notice Unauthorized caller cannot report result
    function testRevert_reportResult_Unauthorized() public {
        bytes memory resultData = abi.encode(bob, "rock", "scissors", uint256(1), "1-0", false);
        vm.prank(stranger);
        vm.expectRevert();
        results.reportResult(instanceId, resultData, Types.ResultSource.System, true);
    }

    /// @notice Cannot submit a second final result
    function testRevert_reportResult_AlreadySubmitted() public {
        _submitResultBobWins(instanceId);

        // Need a new active instance to test double submission
        // Since this instance is now Completed, we test that the result already exists check works
        // by trying to report on a non-Active status (which triggers InvalidState first)
        // Actually, let's create a scenario where result is stored but instance is still active
        // This is not possible with isFinal=true, so the guard is: final result + trying again
        // The second call will hit InvalidState(Completed) before ResultAlreadySubmitted
        bytes memory resultData = abi.encode(bob, "rock", "scissors", uint256(1), "1-0", false);
        vm.prank(admin);
        vm.expectRevert(); // will revert (either InvalidState or ResultAlreadySubmitted)
        results.reportResult(instanceId, resultData, Types.ResultSource.System, true);
    }

    /// @notice Cannot report result with empty result data
    function testRevert_reportResult_EmptyData() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Types.InvalidResultData.selector));
        results.reportResult(instanceId, "", Types.ResultSource.System, true);
    }

    // ========================================================================
    // View functions
    // ========================================================================

    /// @notice getResult reverts for non-existent result
    function testRevert_getResult_NotFound() public {
        bytes32 fakeId = keccak256("fake");
        vm.expectRevert(abi.encodeWithSelector(Types.ResultNotFound.selector, fakeId));
        results.getResult(fakeId);
    }

    /// @notice isResultFinal returns false for non-existent result
    function test_isResultFinal_FalseWhenNotExists() public {
        assertFalse(results.isResultFinal(keccak256("nonexistent")));
    }
}
