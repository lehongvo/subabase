// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Types} from "../libraries/Types.sol";

/// @title IContractInstances — Interface for contract instance lifecycle management
/// @notice Manages the full lifecycle state machine of contract instances:
///         Created -> Active -> Completed -> Settled
///                                 |
///                             Disputed -> Resolved -> Settled
/// @dev Maps to Phase 0 DB table `contract_instances`.
///      State transitions are enforced by role-based access control.
interface IContractInstances {
    // ========================================================================
    // EVENTS
    // ========================================================================

    /// @notice Emitted when a new instance is created
    event InstanceCreated(
        bytes32 indexed instanceId,
        bytes32 indexed templateId,
        bool chainRecord,
        uint48 createdAt
    );

    /// @notice Emitted on every status transition
    event InstanceStatusChanged(
        bytes32 indexed instanceId,
        Types.ContractStatus indexed oldStatus,
        Types.ContractStatus indexed newStatus,
        uint48 timestamp
    );

    /// @notice Emitted when tx_hash is set
    event InstanceTxHashSet(
        bytes32 indexed instanceId,
        bytes32 txHash
    );

    /// @notice Emitted when a linked contract address is updated
    event ContractReferenceUpdated(
        string contractName,
        address newAddress
    );

    // ========================================================================
    // WRITE FUNCTIONS
    // ========================================================================

    /// @notice Create a new contract instance from an active template
    /// @dev Access: anyone, whenNotPaused. Template must exist and be active.
    ///      ID generated via keccak256(abi.encodePacked(templateId, block.timestamp, msg.sender, nonce)).
    /// @param templateId FK to contract_templates
    /// @param metadata ABI-encoded metadata (room_id, session, etc.)
    /// @return instanceId The generated instance ID
    function createInstance(
        bytes32 templateId,
        bytes calldata metadata
    ) external returns (bytes32 instanceId);

    /// @notice Transition instance from Created to Active
    /// @dev Access: onlyRole(SYSTEM_ROLE). Requires party count >= 2
    ///      (reads from ContractParties).
    /// @param instanceId The instance to activate
    function activateInstance(bytes32 instanceId) external;

    /// @notice Transition instance from Active to Completed
    /// @dev Access: onlyRole(CONTRACT_ROLE). Called by ContractResults after final result.
    /// @param instanceId The instance to complete
    function completeInstance(bytes32 instanceId) external;

    /// @notice Transition instance from Completed to Disputed
    /// @dev Access: onlyRole(CONTRACT_ROLE). Called by ContractConsents when party disputes.
    /// @param instanceId The instance to dispute
    function disputeInstance(bytes32 instanceId) external;

    /// @notice Transition instance from Disputed to Resolved
    /// @dev Access: onlyRole(ADMIN_ROLE) or onlyRole(OPERATOR_ROLE).
    /// @param instanceId The instance to resolve
    function resolveInstance(bytes32 instanceId) external;

    /// @notice Transition instance from Completed/Resolved to Settled
    /// @dev Access: onlyRole(CONTRACT_ROLE). Called by ContractSettlements.
    /// @param instanceId The instance to settle
    function settleInstance(bytes32 instanceId) external;

    /// @notice Set the on-chain tx hash after settlement broadcast
    /// @dev Access: onlyRole(SYSTEM_ROLE).
    /// @param instanceId The instance ID
    /// @param txHash The on-chain transaction hash
    function setTxHash(bytes32 instanceId, bytes32 txHash) external;

    /// @notice Set the ContractParties contract address (post-deploy linkage)
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE).
    /// @param partiesContract Address of the ContractParties proxy
    function setPartiesContract(address partiesContract) external;

    /// @notice Set the ContractResults contract address (post-deploy linkage)
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE).
    /// @param resultsContract Address of the ContractResults proxy
    function setResultsContract(address resultsContract) external;

    /// @notice Set the ContractConsents contract address (post-deploy linkage)
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE).
    /// @param consentsContract Address of the ContractConsents proxy
    function setConsentsContract(address consentsContract) external;

    /// @notice Set the ContractSettlements contract address (post-deploy linkage)
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE).
    /// @param settlementsContract Address of the ContractSettlements proxy
    function setSettlementsContract(address settlementsContract) external;

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /// @notice Get a contract instance by its ID
    /// @param instanceId The instance ID
    /// @return instance The full instance struct
    function getInstance(bytes32 instanceId) external view returns (Types.Instance memory instance);

    /// @notice Get the current status of an instance
    /// @param instanceId The instance ID
    /// @return status The current ContractStatus
    function getInstanceStatus(bytes32 instanceId) external view returns (Types.ContractStatus status);

    /// @notice Get the template ID for an instance
    /// @param instanceId The instance ID
    /// @return templateId The linked template ID
    function getInstanceTemplateId(bytes32 instanceId) external view returns (bytes32 templateId);

    /// @notice Check whether an instance exists
    /// @param instanceId The instance ID
    /// @return exists True if the instance exists
    function instanceExists(bytes32 instanceId) external view returns (bool exists);
}
