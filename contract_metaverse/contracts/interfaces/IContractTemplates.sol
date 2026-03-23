// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Types} from "../libraries/Types.sol";

/// @title IContractTemplates — Interface for contract template management
/// @notice Admin-managed registry of contract templates that define game rules,
///         fee rates, payment types, and blockchain recording policies.
/// @dev Maps to Phase 0 DB table `contract_templates`. Only ADMIN_ROLE can mutate.
interface IContractTemplates {
    // ========================================================================
    // EVENTS
    // ========================================================================

    /// @notice Emitted when a new template is created
    event TemplateCreated(
        bytes32 indexed templateId,
        Types.ContractType indexed contractType,
        address indexed createdBy,
        string name,
        uint16 feeRateBps,
        Types.ChainRecordPolicy chainRecordPolicy
    );

    /// @notice Emitted when a template is updated
    event TemplateUpdated(
        bytes32 indexed templateId,
        uint16 feeRateBps,
        Types.ChainRecordPolicy chainRecordPolicy,
        uint48 updatedAt
    );

    /// @notice Emitted when a template is activated
    event TemplateActivated(bytes32 indexed templateId);

    /// @notice Emitted when a template is deactivated
    event TemplateDeactivated(bytes32 indexed templateId);

    // ========================================================================
    // WRITE FUNCTIONS
    // ========================================================================

    /// @notice Create a new contract template
    /// @dev Access: onlyRole(ADMIN_ROLE), whenNotPaused.
    ///      ID generated via keccak256(abi.encodePacked(name, block.timestamp, msg.sender, nonce)).
    /// @param name Template name (must be unique)
    /// @param contractType RPS, WorkReward, Tournament, or Custom
    /// @param conditions ABI-encoded TemplateConditions (minBet, maxBet, rounds, timeoutSeconds)
    /// @param rewardRules ABI-encoded RewardRules (drawRefund, winnerPct)
    /// @param paymentType IXPoint, IXFreePoint, or Both
    /// @param feeRateBps Fee rate in basis points (0-5000, i.e. 0%-50%)
    /// @param chainRecordPolicy Required, Optional, or Off
    /// @param metaverseEventId Linked metaverse event identifier
    /// @return templateId The generated template ID
    function createTemplate(
        string calldata name,
        Types.ContractType contractType,
        bytes calldata conditions,
        bytes calldata rewardRules,
        Types.PaymentType paymentType,
        uint16 feeRateBps,
        Types.ChainRecordPolicy chainRecordPolicy,
        bytes32 metaverseEventId
    ) external returns (bytes32 templateId);

    /// @notice Update an existing template's mutable fields
    /// @dev Access: onlyRole(ADMIN_ROLE), whenNotPaused. Changes apply to future instances only.
    /// @param templateId The template to update
    /// @param name New template name
    /// @param conditions New ABI-encoded conditions
    /// @param rewardRules New ABI-encoded reward rules
    /// @param paymentType New payment type
    /// @param feeRateBps New fee rate in basis points
    /// @param chainRecordPolicy New chain record policy
    /// @param metaverseEventId New metaverse event identifier
    function updateTemplate(
        bytes32 templateId,
        string calldata name,
        bytes calldata conditions,
        bytes calldata rewardRules,
        Types.PaymentType paymentType,
        uint16 feeRateBps,
        Types.ChainRecordPolicy chainRecordPolicy,
        bytes32 metaverseEventId
    ) external;

    /// @notice Activate a template so it can be used to create new instances
    /// @dev Access: onlyRole(ADMIN_ROLE). Only inactive templates can be activated.
    /// @param templateId The template to activate
    function activateTemplate(bytes32 templateId) external;

    /// @notice Deactivate a template to prevent new instance creation
    /// @dev Access: onlyRole(ADMIN_ROLE). Existing instances are unaffected.
    /// @param templateId The template to deactivate
    function deactivateTemplate(bytes32 templateId) external;

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /// @notice Get a template by its ID
    /// @param templateId The template ID
    /// @return template_ The full template struct
    function getTemplate(bytes32 templateId) external view returns (Types.Template memory template_);

    /// @notice Get all currently active templates
    /// @return templates Array of active template structs
    function getActiveTemplates() external view returns (Types.Template[] memory templates);

    /// @notice Get the total number of registered templates
    /// @return count Total template count
    function getTemplateCount() external view returns (uint256 count);

    /// @notice Check whether a template is active
    /// @param templateId The template ID
    /// @return active True if the template exists and is active
    function isTemplateActive(bytes32 templateId) external view returns (bool active);

    /// @notice Get the fee rate for a template
    /// @param templateId The template ID
    /// @return feeRateBps The fee rate in basis points
    function getTemplateFeeRate(bytes32 templateId) external view returns (uint16 feeRateBps);
}
