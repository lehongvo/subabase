// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Types} from "../libraries/Types.sol";

/// @title IContractParties — Interface for party management and escrow operations
/// @notice Handles party joining with ERC-20 escrow deposits, and escrow
///         release/refund during settlement.
/// @dev Maps to Phase 0 DB table `contract_parties`.
///      Escrow flow:
///        1. joinContract(): user deposits tokens via SafeERC20.safeTransferFrom
///        2. releaseEscrow(): tokens sent to winner/treasury during settlement
///        3. refundEscrow(): tokens returned to depositors on draw/cancellation
///      This contract holds all escrowed ERC-20 tokens.
interface IContractParties {
    // ========================================================================
    // EVENTS
    // ========================================================================

    /// @notice Emitted when a party joins a contract with escrow
    event PartyJoined(
        bytes32 indexed instanceId,
        address indexed userId,
        bytes32 role,
        uint128 escrowAmount,
        Types.PointType escrowType,
        uint48 joinedAt
    );

    /// @notice Emitted when escrow is released after settlement
    event EscrowReleased(
        bytes32 indexed instanceId,
        address indexed to,
        uint128 amount
    );

    /// @notice Emitted when escrow is refunded to a party
    event EscrowRefunded(
        bytes32 indexed instanceId,
        address indexed to,
        uint128 amount
    );

    // ========================================================================
    // WRITE FUNCTIONS
    // ========================================================================

    /// @notice Join a contract instance with an escrow deposit
    /// @dev Access: anyone, whenNotPaused, nonReentrant.
    ///      Full flow: validate instance status == Created -> validate template active ->
    ///      validate not already joined -> validate escrow amount in range ->
    ///      store party record -> SafeERC20.safeTransferFrom(user, this, amount) -> emit.
    /// @param instanceId FK to contract_instances (must be in Created status)
    /// @param role keccak256 of the role string (e.g., keccak256("challenger"))
    /// @param escrowAmount Amount to escrow in token smallest unit
    /// @param escrowType IXPoint or IXFreePoint
    function joinContract(
        bytes32 instanceId,
        bytes32 role,
        uint128 escrowAmount,
        Types.PointType escrowType
    ) external;

    /// @notice Release escrowed tokens to a recipient during settlement
    /// @dev Access: onlyRole(CONTRACT_ROLE), nonReentrant.
    ///      Called by ContractSettlements to pay winner or treasury.
    /// @param instanceId The contract instance ID
    /// @param to Recipient address (winner or treasury)
    /// @param amount Amount to release
    function releaseEscrow(
        bytes32 instanceId,
        address to,
        uint128 amount
    ) external;

    /// @notice Refund all escrowed tokens to original depositors
    /// @dev Access: onlyRole(CONTRACT_ROLE), nonReentrant.
    ///      Called on draw or cancellation. Each party gets their exact deposit back.
    /// @param instanceId The contract instance ID
    function refundEscrow(bytes32 instanceId) external;

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /// @notice Get all parties for a contract instance
    /// @param instanceId The contract instance ID
    /// @return parties Array of Party structs
    function getParties(bytes32 instanceId) external view returns (Types.Party[] memory parties);

    /// @notice Get a specific party record
    /// @param instanceId The contract instance ID
    /// @param userId The user's wallet address
    /// @return party The Party struct
    function getParty(bytes32 instanceId, address userId) external view returns (Types.Party memory party);

    /// @notice Get the number of parties in a contract
    /// @param instanceId The contract instance ID
    /// @return count The party count
    function getPartyCount(bytes32 instanceId) external view returns (uint8 count);

    /// @notice Get the sum of all escrow amounts for a contract
    /// @param instanceId The contract instance ID
    /// @return total The total escrowed amount
    function getTotalEscrow(bytes32 instanceId) external view returns (uint128 total);

    /// @notice Check if a user has already joined a contract
    /// @param instanceId The contract instance ID
    /// @param userId The user's wallet address
    /// @return joined True if the user is already a party
    function hasJoined(bytes32 instanceId, address userId) external view returns (bool joined);
}
