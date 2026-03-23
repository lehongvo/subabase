// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Types} from "./Types.sol";

/// @title StateValidator -- Pure library for contract lifecycle state machine enforcement
/// @notice Validates state transitions in the IX Metaverse Contract System.
///         The contract lifecycle follows this directed graph:
///
///         Created --> Active --> Completed --> Settled
///            |          |            |
///            |          |            v
///            |          |        Disputed --> Resolved --> Settled
///            v          v
///          Settled   Settled   (cancellation / refund paths)
///
/// @dev 8 valid transitions are permitted:
///      1. Created   -> Active     (all parties joined, escrow confirmed)
///      2. Created   -> Settled    (cancellation before activation — refund escrow)
///      3. Active    -> Completed  (result determined by game server)
///      4. Active    -> Settled    (cancellation during active — admin refund)
///      5. Completed -> Settled    (all parties consented or timeout elapsed)
///      6. Completed -> Disputed   (a party raised an objection)
///      7. Disputed  -> Resolved   (admin resolved the dispute)
///      8. Resolved  -> Settled    (settlement executed after resolution)
///
///      All other transitions revert with Types.InvalidTransition.
///      The Settled state is terminal -- no transitions out of it.
library StateValidator {

    /// @notice Validate a state transition, reverting if invalid
    /// @dev Checks the transition against the 8 allowed paths. Reverts with
    ///      Types.InvalidTransition(instanceId, from, to) if the transition is not allowed.
    /// @param instanceId The contract instance ID (used in revert message for debugging)
    /// @param from The current status of the contract instance
    /// @param to The target status to transition to
    function validateTransition(
        bytes32 instanceId,
        Types.ContractStatus from,
        Types.ContractStatus to
    ) internal pure {
        if (!isValidTransition(from, to)) {
            revert Types.InvalidTransition(instanceId, from, to);
        }
    }

    /// @notice Check whether a state transition is valid (non-reverting)
    /// @dev Returns true only for the 8 defined valid transitions.
    ///      This function is useful for pre-checking transitions without consuming
    ///      gas on revert data encoding.
    /// @param from The current status
    /// @param to The target status
    /// @return valid True if the transition is permitted
    function isValidTransition(
        Types.ContractStatus from,
        Types.ContractStatus to
    ) internal pure returns (bool valid) {
        // Created -> Active
        if (from == Types.ContractStatus.Created && to == Types.ContractStatus.Active) {
            return true;
        }
        // Created -> Settled (cancellation / refund before activation)
        if (from == Types.ContractStatus.Created && to == Types.ContractStatus.Settled) {
            return true;
        }
        // Active -> Completed
        if (from == Types.ContractStatus.Active && to == Types.ContractStatus.Completed) {
            return true;
        }
        // Active -> Settled (cancellation / admin refund during active)
        if (from == Types.ContractStatus.Active && to == Types.ContractStatus.Settled) {
            return true;
        }
        // Completed -> Settled
        if (from == Types.ContractStatus.Completed && to == Types.ContractStatus.Settled) {
            return true;
        }
        // Completed -> Disputed
        if (from == Types.ContractStatus.Completed && to == Types.ContractStatus.Disputed) {
            return true;
        }
        // Disputed -> Resolved
        if (from == Types.ContractStatus.Disputed && to == Types.ContractStatus.Resolved) {
            return true;
        }
        // Resolved -> Settled
        if (from == Types.ContractStatus.Resolved && to == Types.ContractStatus.Settled) {
            return true;
        }

        return false;
    }
}
