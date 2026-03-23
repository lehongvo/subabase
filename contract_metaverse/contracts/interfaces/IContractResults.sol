// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Types} from "../libraries/Types.sol";

/// @title IContractResults — Interface for result storage and completion triggering
/// @notice Manages result submission for contract instances. When a final result
///         is submitted, triggers the Active -> Completed transition on ContractInstances.
/// @dev Maps to Phase 0 DB table `contract_results`.
///      Result data is stored as ABI-encoded bytes to support different contract types.
interface IContractResults {
    // ========================================================================
    // EVENTS
    // ========================================================================

    /// @notice Emitted when a result is reported
    event ResultReported(
        bytes32 indexed instanceId,
        Types.ResultSource indexed reportedBy,
        bool isFinal,
        bytes resultData,
        uint48 reportedAt
    );

    /// @notice Emitted when a result is overridden by admin (dispute resolution)
    event ResultOverridden(
        bytes32 indexed instanceId,
        bytes oldResultData,
        bytes newResultData,
        uint48 overriddenAt
    );

    // ========================================================================
    // WRITE FUNCTIONS
    // ========================================================================

    /// @notice Report the result of a contract instance
    /// @dev Access: onlyRole(SERVER_ROLE), whenNotPaused.
    ///      Flow:
    ///        1. Validate instance status == Active
    ///        2. Store Result record
    ///        3. If isFinal, call instances.completeInstance(instanceId)
    /// @param instanceId FK to contract_instances
    /// @param resultData ABI-encoded result (winner_id, moves, score, is_draw, etc.)
    /// @param reportedBy System or User (ResultSource enum)
    /// @param isFinal Whether this result is the definitive final result
    function reportResult(
        bytes32 instanceId,
        bytes calldata resultData,
        Types.ResultSource reportedBy,
        bool isFinal
    ) external;

    /// @notice Admin overrides a result during dispute resolution
    /// @dev Access: onlyRole(ADMIN_ROLE), whenNotPaused.
    ///      Instance must be in Disputed state.
    /// @param instanceId FK to contract_instances
    /// @param resultData New ABI-encoded result data replacing the previous result
    function overrideResult(
        bytes32 instanceId,
        bytes calldata resultData
    ) external;

    /// @notice Set cross-contract reference to ContractInstances
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE).
    /// @param instancesContract Address of the ContractInstances proxy
    function setInstancesContract(address instancesContract) external;

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /// @notice Get the result for a contract instance
    /// @param instanceId FK to contract_instances
    /// @return result The full Result struct
    function getResult(bytes32 instanceId)
        external view returns (Types.Result memory result);

    /// @notice Check if a result exists for a contract instance
    /// @param instanceId FK to contract_instances
    /// @return exists True if a result has been reported
    function resultExists(bytes32 instanceId)
        external view returns (bool exists);

    /// @notice Check if the result for an instance is marked final
    /// @param instanceId FK to contract_instances
    /// @return isFinal True if the result is definitive
    function isResultFinal(bytes32 instanceId)
        external view returns (bool isFinal);
}
