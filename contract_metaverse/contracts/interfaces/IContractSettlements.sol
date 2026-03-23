// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Types} from "../libraries/Types.sol";

/// @title IContractSettlements — Interface for fee calculation and token distribution
/// @notice Handles settlement of contract instances: calculates fees, distributes
///         tokens to winners and treasury, and handles draw refunds.
/// @dev Maps to Phase 0 DB table `contract_settlements`.
///      Settlement flow:
///        1. Verify all consents received
///        2. Read result to determine winner
///        3. Calculate fee from template fee_rate
///        4. Transfer tokens (reward to winner, fee to treasury)
///        5. Mark instance as Settled
interface IContractSettlements {
    // ========================================================================
    // EVENTS
    // ========================================================================

    /// @notice Emitted for each individual settlement transfer (reward, fee, or refund)
    event SettlementExecuted(
        bytes32 indexed instanceId,
        address indexed fromUserId,
        address indexed toUserId,
        uint128 amount,
        uint128 feeAmount,
        Types.SettlementType settlementType,
        Types.PointType pointType,
        uint48 settledAt
    );

    /// @notice Emitted when a full contract settlement is completed (winner scenario)
    event ContractSettled(
        bytes32 indexed instanceId,
        uint128 totalAmount,
        uint128 totalFees,
        uint48 settledAt
    );

    /// @notice Emitted when a contract is refunded (draw / cancellation)
    event ContractRefunded(
        bytes32 indexed instanceId,
        uint128 totalRefunded,
        uint48 refundedAt
    );

    // ========================================================================
    // WRITE FUNCTIONS
    // ========================================================================

    /// @notice Execute full settlement for a contract instance (winner scenario)
    /// @dev Access: onlyRole(SETTLER_ROLE), whenNotPaused, nonReentrant.
    ///      Flow:
    ///        1. Verify allConsented (via Consents) or dispute resolved
    ///        2. Verify instance status == Completed or Resolved
    ///        3. Read result from Results to determine winner
    ///        4. Read template feeRate via instance -> template
    ///        5. Calculate: fee = totalEscrow * feeRateBps / 10000
    ///        6. Effects: create Settlement records (reward + fee)
    ///        7. Interactions: releaseEscrow to winner and treasury,
    ///           transition instance to Settled
    /// @param instanceId FK to contract_instances
    function settleContract(bytes32 instanceId) external;

    /// @notice Execute refund settlement (draw or cancellation)
    /// @dev Access: onlyRole(SETTLER_ROLE) or onlyRole(ADMIN_ROLE),
    ///      whenNotPaused, nonReentrant.
    ///      All escrowed amounts returned to original depositors. No fee charged.
    /// @param instanceId FK to contract_instances
    function refundContract(bytes32 instanceId) external;

    /// @notice Set the treasury address for fee collection
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE).
    /// @param treasury New treasury address
    function setTreasury(address treasury) external;

    /// @notice Set cross-contract reference to ContractInstances
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE).
    /// @param instancesContract Address of the ContractInstances proxy
    function setInstancesContract(address instancesContract) external;

    /// @notice Set cross-contract reference to ContractParties
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE).
    /// @param partiesContract Address of the ContractParties proxy
    function setPartiesContract(address partiesContract) external;

    /// @notice Set cross-contract reference to ContractResults
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE).
    /// @param resultsContract Address of the ContractResults proxy
    function setResultsContract(address resultsContract) external;

    /// @notice Set cross-contract reference to ContractConsents
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE).
    /// @param consentsContract Address of the ContractConsents proxy
    function setConsentsContract(address consentsContract) external;

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /// @notice Get all settlement records for a contract instance
    /// @param instanceId FK to contract_instances
    /// @return settlements Array of Settlement structs
    function getSettlements(bytes32 instanceId)
        external view returns (Types.Settlement[] memory settlements);

    /// @notice Check if a contract instance has been settled
    /// @param instanceId FK to contract_instances
    /// @return settled True if settlement records exist
    function isSettled(bytes32 instanceId)
        external view returns (bool settled);

    /// @notice Get the number of settlement records for an instance
    /// @param instanceId FK to contract_instances
    /// @return count Number of settlement records
    function getSettlementCount(bytes32 instanceId)
        external view returns (uint256 count);

    /// @notice Get the current treasury address
    /// @return treasuryAddr The treasury address
    function getTreasury()
        external view returns (address treasuryAddr);
}
