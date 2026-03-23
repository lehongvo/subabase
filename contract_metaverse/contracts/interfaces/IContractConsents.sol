// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Types} from "../libraries/Types.sol";

/// @title IContractConsents — Interface for consent and dispute management
/// @notice Manages consent/dispute submission after contract completion,
///         auto-consent timeout logic, and dispute triggering.
/// @dev Maps to Phase 0 DB table `contract_consents`.
///      Consent flow: after a final result is submitted and instance is Completed,
///      each party submits consent (true) or dispute (false).
interface IContractConsents {
    // ========================================================================
    // EVENTS
    // ========================================================================

    /// @notice Emitted when a party submits consent (accept or dispute)
    event ConsentSubmitted(
        bytes32 indexed instanceId,
        address indexed userId,
        bool consented,
        uint48 consentedAt
    );

    /// @notice Emitted when consent is granted automatically after timeout
    event AutoConsentApplied(
        bytes32 indexed instanceId,
        address indexed userId,
        uint48 appliedAt
    );

    /// @notice Emitted when a dispute is raised (consented == false)
    event DisputeRaised(
        bytes32 indexed instanceId,
        address indexed userId,
        string reason,
        uint48 disputedAt
    );

    // ========================================================================
    // WRITE FUNCTIONS
    // ========================================================================

    /// @notice A party submits consent or objection for a contract result
    /// @dev Access: onlyRole(SERVER_ROLE), whenNotPaused.
    ///      Flow:
    ///        1. Validate instance status == Completed (or Resolved for post-dispute)
    ///        2. Validate userId is a party of this contract (via ContractParties)
    ///        3. Validate user has not already submitted consent
    ///        4. Store Consent record, increment consent count
    ///        5. If consented == false: call instances.disputeInstance(instanceId)
    /// @param instanceId FK to contract_instances
    /// @param userId The consenting user's wallet address
    /// @param consented true = accept result, false = dispute
    /// @param signature Wallet signature (EIP-712 or raw bytes)
    /// @param reason Dispute reason (empty string if consented == true)
    function submitConsent(
        bytes32 instanceId,
        address userId,
        bool consented,
        bytes calldata signature,
        string calldata reason
    ) external;

    /// @notice Auto-consent for a user after timeout expiry
    /// @dev Access: onlyRole(SERVER_ROLE), whenNotPaused.
    ///      Anyone can trigger via server. Validates consent deadline has passed.
    /// @param instanceId FK to contract_instances
    /// @param userId The user whose consent timed out
    function autoConsent(bytes32 instanceId, address userId) external;

    /// @notice Set cross-contract reference to ContractInstances
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE).
    /// @param instancesContract Address of the ContractInstances proxy
    function setInstancesContract(address instancesContract) external;

    /// @notice Set cross-contract reference to ContractParties
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE).
    /// @param partiesContract Address of the ContractParties proxy
    function setPartiesContract(address partiesContract) external;

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /// @notice Check if all parties have consented (or auto-consented via timeout)
    /// @param instanceId FK to contract_instances
    /// @return allDone True if all parties have submitted consent
    function allConsented(bytes32 instanceId)
        external view returns (bool allDone);

    /// @notice Check if an instance has a dispute
    /// @param instanceId FK to contract_instances
    /// @return disputed True if any party submitted consented == false
    function hasDispute(bytes32 instanceId)
        external view returns (bool disputed);

    /// @notice Get a specific party's consent record
    /// @param instanceId FK to contract_instances
    /// @param userId The user's wallet address
    /// @return consent The full Consent struct
    function getConsent(bytes32 instanceId, address userId)
        external view returns (Types.Consent memory consent);

    /// @notice Get the number of consents submitted for an instance
    /// @param instanceId FK to contract_instances
    /// @return count Number of consent records
    function getConsentCount(bytes32 instanceId)
        external view returns (uint8 count);
}
