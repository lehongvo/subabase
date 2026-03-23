// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {StateValidator} from "../libraries/StateValidator.sol";
import {Types} from "../libraries/Types.sol";

/// @title StateValidatorHarness -- Wrapper to call library functions externally
/// @dev Required because vm.expectRevert() does not work with inlined library calls
contract StateValidatorHarness {
    function validateTransition(
        bytes32 instanceId,
        Types.ContractStatus from,
        Types.ContractStatus to
    ) external pure {
        StateValidator.validateTransition(instanceId, from, to);
    }
}

/// @title StateValidatorTest -- Tests for contract lifecycle state machine validation
contract StateValidatorTest is Test {
    bytes32 constant DUMMY_ID = bytes32(uint256(1));
    StateValidatorHarness internal harness;

    function setUp() public {
        harness = new StateValidatorHarness();
    }

    // ========================================================================
    // Valid transitions (6 tests)
    // ========================================================================

    /// @notice Created -> Active is valid
    function test_validTransition_CreatedToActive() public pure {
        assertTrue(StateValidator.isValidTransition(
            Types.ContractStatus.Created,
            Types.ContractStatus.Active
        ));
    }

    /// @notice Active -> Completed is valid
    function test_validTransition_ActiveToCompleted() public pure {
        assertTrue(StateValidator.isValidTransition(
            Types.ContractStatus.Active,
            Types.ContractStatus.Completed
        ));
    }

    /// @notice Completed -> Settled is valid
    function test_validTransition_CompletedToSettled() public pure {
        assertTrue(StateValidator.isValidTransition(
            Types.ContractStatus.Completed,
            Types.ContractStatus.Settled
        ));
    }

    /// @notice Completed -> Disputed is valid
    function test_validTransition_CompletedToDisputed() public pure {
        assertTrue(StateValidator.isValidTransition(
            Types.ContractStatus.Completed,
            Types.ContractStatus.Disputed
        ));
    }

    /// @notice Disputed -> Resolved is valid
    function test_validTransition_DisputedToResolved() public pure {
        assertTrue(StateValidator.isValidTransition(
            Types.ContractStatus.Disputed,
            Types.ContractStatus.Resolved
        ));
    }

    /// @notice Resolved -> Settled is valid
    function test_validTransition_ResolvedToSettled() public pure {
        assertTrue(StateValidator.isValidTransition(
            Types.ContractStatus.Resolved,
            Types.ContractStatus.Settled
        ));
    }

    // ========================================================================
    // Invalid transitions
    // ========================================================================

    /// @notice Created -> Completed is invalid
    function test_invalidTransition_CreatedToCompleted() public pure {
        assertFalse(StateValidator.isValidTransition(
            Types.ContractStatus.Created,
            Types.ContractStatus.Completed
        ));
    }

    /// @notice Created -> Settled is invalid
    function test_invalidTransition_CreatedToSettled() public pure {
        assertFalse(StateValidator.isValidTransition(
            Types.ContractStatus.Created,
            Types.ContractStatus.Settled
        ));
    }

    /// @notice Active -> Settled is valid (cancellation path)
    function test_validTransition_ActiveToSettled() public pure {
        assertTrue(StateValidator.isValidTransition(
            Types.ContractStatus.Active,
            Types.ContractStatus.Settled
        ));
    }

    /// @notice Active -> Disputed is invalid
    function test_invalidTransition_ActiveToDisputed() public pure {
        assertFalse(StateValidator.isValidTransition(
            Types.ContractStatus.Active,
            Types.ContractStatus.Disputed
        ));
    }

    /// @notice Settled -> anything is invalid (terminal state)
    function test_invalidTransition_SettledToCreated() public pure {
        assertFalse(StateValidator.isValidTransition(
            Types.ContractStatus.Settled,
            Types.ContractStatus.Created
        ));
    }

    /// @notice Backward transition Active -> Created is invalid
    function test_invalidTransition_ActiveToCreated() public pure {
        assertFalse(StateValidator.isValidTransition(
            Types.ContractStatus.Active,
            Types.ContractStatus.Created
        ));
    }

    /// @notice Same state transition is invalid (Created -> Created)
    function test_invalidTransition_SameState() public pure {
        assertFalse(StateValidator.isValidTransition(
            Types.ContractStatus.Created,
            Types.ContractStatus.Created
        ));
    }

    // ========================================================================
    // validateTransition reverts
    // ========================================================================

    /// @notice validateTransition reverts for invalid transition
    function testRevert_validateTransition_InvalidCombo() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Types.InvalidTransition.selector,
                DUMMY_ID,
                Types.ContractStatus.Created,
                Types.ContractStatus.Settled
            )
        );
        harness.validateTransition(
            DUMMY_ID,
            Types.ContractStatus.Created,
            Types.ContractStatus.Settled
        );
    }

    /// @notice validateTransition does not revert for valid transition
    function test_validateTransition_ValidDoesNotRevert() public pure {
        // Should not revert
        StateValidator.validateTransition(
            DUMMY_ID,
            Types.ContractStatus.Created,
            Types.ContractStatus.Active
        );
    }

    // ========================================================================
    // Fuzz tests
    // ========================================================================

    /// @notice Fuzz: random state pairs — only 6 specific combos are valid
    function testFuzz_isValidTransition_RandomPairs(uint8 fromRaw, uint8 toRaw) public pure {
        fromRaw = uint8(bound(fromRaw, 0, 5));
        toRaw = uint8(bound(toRaw, 0, 5));

        Types.ContractStatus from = Types.ContractStatus(fromRaw);
        Types.ContractStatus to = Types.ContractStatus(toRaw);

        bool result = StateValidator.isValidTransition(from, to);

        // Manually check expected valid transitions
        bool expected = false;
        if (from == Types.ContractStatus.Created && to == Types.ContractStatus.Active) expected = true;
        if (from == Types.ContractStatus.Active && to == Types.ContractStatus.Completed) expected = true;
        if (from == Types.ContractStatus.Completed && to == Types.ContractStatus.Settled) expected = true;
        if (from == Types.ContractStatus.Completed && to == Types.ContractStatus.Disputed) expected = true;
        if (from == Types.ContractStatus.Disputed && to == Types.ContractStatus.Resolved) expected = true;
        if (from == Types.ContractStatus.Resolved && to == Types.ContractStatus.Settled) expected = true;

        assertEq(result, expected, "isValidTransition must match expected valid transitions");
    }
}
