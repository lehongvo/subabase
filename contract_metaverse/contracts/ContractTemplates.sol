// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IContractTemplates} from "./interfaces/IContractTemplates.sol";
import {Types} from "./libraries/Types.sol";

/// @title ContractTemplates — Admin-managed template registry
/// @notice Provides CRUD operations for contract templates that define game rules,
///         fee rates, payment types, and blockchain recording policies.
/// @dev Deployed behind TransparentUpgradeableProxy. No constructor; uses initialize().
///      Maps to Phase 0 DB table `contract_templates`.
contract ContractTemplates is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    IContractTemplates
{
    // ========================================================================
    // CONSTANTS
    // ========================================================================

    /// @notice Role required to create, update, activate, and deactivate templates
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @dev templateId => Template
    mapping(bytes32 => Types.Template) private _templates;

    /// @dev contractType => array of templateIds of that type
    mapping(Types.ContractType => bytes32[]) private _templatesByType;

    /// @dev All template IDs for enumeration
    bytes32[] private _templateIds;

    /// @dev template name hash => bool (uniqueness check)
    mapping(bytes32 => bool) private _nameExists;

    /// @dev templateId => exists
    mapping(bytes32 => bool) private _templateExists;

    /// @dev Monotonically increasing nonce for deterministic ID generation
    uint256 private _nonce;

    /// @dev Upgrade safety gap
    uint256[50] private __gap;

    // ========================================================================
    // INITIALIZER
    // ========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the template registry
    /// @dev Grants DEFAULT_ADMIN_ROLE and ADMIN_ROLE to the admin address.
    /// @param admin The initial admin address
    function initialize(address admin) external initializer {
        if (admin == address(0)) revert Types.ZeroAddress();

        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    // ========================================================================
    // WRITE FUNCTIONS
    // ========================================================================

    /// @notice Create a new contract template
    /// @dev Access: onlyRole(ADMIN_ROLE), whenNotPaused.
    /// @param name Template name (must be unique)
    /// @param contractType RPS, WorkReward, Tournament, or Custom
    /// @param conditions ABI-encoded TemplateConditions
    /// @param rewardRules ABI-encoded RewardRules
    /// @param paymentType IXPoint, IXFreePoint, or Both
    /// @param feeRateBps Fee rate in basis points (0-5000)
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
    ) external onlyRole(ADMIN_ROLE) whenNotPaused returns (bytes32 templateId) {
        // --- Checks ---
        if (bytes(name).length == 0) revert Types.InvalidAmount();
        if (feeRateBps > 5000) revert Types.InvalidFeeRate(feeRateBps);

        bytes32 nameHash = keccak256(bytes(name));
        if (_nameExists[nameHash]) revert Types.TemplateNameExists(name);

        if (conditions.length == 0) revert Types.InvalidAmount();
        if (rewardRules.length == 0) revert Types.InvalidAmount();

        // --- Effects ---
        uint256 currentNonce = _nonce++;
        templateId = keccak256(
            abi.encodePacked(name, block.timestamp, msg.sender, currentNonce)
        );

        if (_templateExists[templateId]) revert Types.TemplateAlreadyExists(templateId);

        Types.Template storage t = _templates[templateId];
        t.id = templateId;
        t.contractType = contractType;
        t.paymentType = paymentType;
        t.chainRecordPolicy = chainRecordPolicy;
        t.isActive = true;
        t.feeRateBps = feeRateBps;
        t.createdBy = msg.sender;
        t.metaverseEventId = metaverseEventId;
        t.conditions = conditions;
        t.rewardRules = rewardRules;
        t.name = name;
        t.createdAt = uint48(block.timestamp);
        t.updatedAt = uint48(block.timestamp);

        _templateExists[templateId] = true;
        _nameExists[nameHash] = true;
        _templateIds.push(templateId);
        _templatesByType[contractType].push(templateId);

        emit TemplateCreated(
            templateId,
            contractType,
            msg.sender,
            name,
            feeRateBps,
            chainRecordPolicy
        );
    }

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
    ) external onlyRole(ADMIN_ROLE) whenNotPaused {
        // --- Checks ---
        if (!_templateExists[templateId]) revert Types.TemplateNotFound(templateId);
        if (feeRateBps > 5000) revert Types.InvalidFeeRate(feeRateBps);
        if (bytes(name).length == 0) revert Types.InvalidAmount();

        Types.Template storage t = _templates[templateId];

        // Check name uniqueness if name changed
        bytes32 oldNameHash = keccak256(bytes(t.name));
        bytes32 newNameHash = keccak256(bytes(name));
        if (oldNameHash != newNameHash) {
            if (_nameExists[newNameHash]) revert Types.TemplateNameExists(name);
            _nameExists[oldNameHash] = false;
            _nameExists[newNameHash] = true;
        }

        // --- Effects ---
        t.name = name;
        t.conditions = conditions;
        t.rewardRules = rewardRules;
        t.paymentType = paymentType;
        t.feeRateBps = feeRateBps;
        t.chainRecordPolicy = chainRecordPolicy;
        t.metaverseEventId = metaverseEventId;
        t.updatedAt = uint48(block.timestamp);

        emit TemplateUpdated(
            templateId,
            feeRateBps,
            chainRecordPolicy,
            uint48(block.timestamp)
        );
    }

    /// @notice Activate a template so it can be used to create new instances
    /// @dev Access: onlyRole(ADMIN_ROLE).
    /// @param templateId The template to activate
    function activateTemplate(bytes32 templateId)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (!_templateExists[templateId]) revert Types.TemplateNotFound(templateId);
        Types.Template storage t = _templates[templateId];
        t.isActive = true;
        t.updatedAt = uint48(block.timestamp);

        emit TemplateActivated(templateId);
    }

    /// @notice Deactivate a template to prevent new instance creation
    /// @dev Access: onlyRole(ADMIN_ROLE). Existing instances continue unaffected.
    /// @param templateId The template to deactivate
    function deactivateTemplate(bytes32 templateId)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (!_templateExists[templateId]) revert Types.TemplateNotFound(templateId);
        Types.Template storage t = _templates[templateId];
        t.isActive = false;
        t.updatedAt = uint48(block.timestamp);

        emit TemplateDeactivated(templateId);
    }

    /// @notice Pause the contract (emergency stop)
    /// @dev Access: onlyRole(ADMIN_ROLE) or DEFAULT_ADMIN_ROLE.
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    /// @dev Access: onlyRole(ADMIN_ROLE) or DEFAULT_ADMIN_ROLE.
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /// @notice Get a template by its ID
    /// @param templateId The template ID
    /// @return template_ The full template struct
    function getTemplate(bytes32 templateId)
        external
        view
        returns (Types.Template memory template_)
    {
        if (!_templateExists[templateId]) revert Types.TemplateNotFound(templateId);
        template_ = _templates[templateId];
    }

    /// @notice Get all currently active templates
    /// @return templates Array of active template structs
    function getActiveTemplates()
        external
        view
        returns (Types.Template[] memory templates)
    {
        uint256 totalCount = _templateIds.length;
        uint256 activeCount;

        // First pass: count active templates
        for (uint256 i; i < totalCount; ++i) {
            if (_templates[_templateIds[i]].isActive) {
                ++activeCount;
            }
        }

        // Second pass: populate array
        templates = new Types.Template[](activeCount);
        uint256 idx;
        for (uint256 i; i < totalCount; ++i) {
            if (_templates[_templateIds[i]].isActive) {
                templates[idx++] = _templates[_templateIds[i]];
            }
        }
    }

    /// @notice Get all active templates of a given type
    /// @param contractType The contract type to filter by
    /// @return templates Array of active template structs of the given type
    function getActiveTemplatesByType(Types.ContractType contractType)
        external
        view
        returns (Types.Template[] memory templates)
    {
        bytes32[] storage ids = _templatesByType[contractType];
        uint256 totalCount = ids.length;
        uint256 activeCount;

        // First pass: count active templates of this type
        for (uint256 i; i < totalCount; ++i) {
            if (_templates[ids[i]].isActive) {
                ++activeCount;
            }
        }

        // Second pass: populate array
        templates = new Types.Template[](activeCount);
        uint256 idx;
        for (uint256 i; i < totalCount; ++i) {
            if (_templates[ids[i]].isActive) {
                templates[idx++] = _templates[ids[i]];
            }
        }
    }

    /// @notice Get the total number of registered templates
    /// @return count Total template count
    function getTemplateCount() external view returns (uint256 count) {
        count = _templateIds.length;
    }

    /// @notice Check whether a template is active
    /// @param templateId The template ID
    /// @return active True if the template exists and is active
    function isTemplateActive(bytes32 templateId) external view returns (bool active) {
        if (!_templateExists[templateId]) return false;
        active = _templates[templateId].isActive;
    }

    /// @notice Get the fee rate for a template
    /// @param templateId The template ID
    /// @return feeRateBps The fee rate in basis points
    function getTemplateFeeRate(bytes32 templateId)
        external
        view
        returns (uint16 feeRateBps)
    {
        if (!_templateExists[templateId]) revert Types.TemplateNotFound(templateId);
        feeRateBps = _templates[templateId].feeRateBps;
    }
}
