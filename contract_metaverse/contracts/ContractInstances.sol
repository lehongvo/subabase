// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IContractInstances} from "./interfaces/IContractInstances.sol";
import {IContractTemplates} from "./interfaces/IContractTemplates.sol";
import {IContractParties} from "./interfaces/IContractParties.sol";
import {Types} from "./libraries/Types.sol";
import {StateValidator} from "./libraries/StateValidator.sol";

/// @title ContractInstances — Lifecycle state machine for contract instances
/// @notice Manages the full lifecycle of contract instances:
///         Created -> Active -> Completed -> Settled
///                                  |
///                              Disputed -> Resolved -> Settled
/// @dev Deployed behind TransparentUpgradeableProxy. No constructor; uses initialize().
///      Maps to Phase 0 DB table `contract_instances`.
contract ContractInstances is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    IContractInstances
{
    using StateValidator for Types.ContractStatus;

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SYSTEM_ROLE = keccak256("SYSTEM_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant CONTRACT_ROLE = keccak256("CONTRACT_ROLE");

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @dev instanceId => Instance
    mapping(bytes32 => Types.Instance) private _instances;

    /// @dev All instance IDs for enumeration
    bytes32[] private _instanceIds;

    /// @dev instanceId => exists
    mapping(bytes32 => bool) private _instanceExists;

    /// @dev Cross-contract references
    IContractTemplates private _templatesContract;
    IContractParties private _partiesContract;
    address private _resultsContract;
    address private _consentsContract;
    address private _settlementsContract;

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

    /// @notice Initialize the instances contract
    /// @dev Grants roles and sets the templates contract reference.
    /// @param admin The initial admin address
    /// @param templatesAddress Address of the ContractTemplates proxy
    function initialize(address admin, address templatesAddress) external initializer {
        if (admin == address(0)) revert Types.ZeroAddress();
        if (templatesAddress == address(0)) revert Types.ZeroAddress();

        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);

        _templatesContract = IContractTemplates(templatesAddress);
    }

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    /// @dev Validates a state transition from current to target status using StateValidator library
    modifier validTransition(bytes32 instanceId, Types.ContractStatus target) {
        if (!_instanceExists[instanceId]) revert Types.ContractNotFound(instanceId);
        Types.ContractStatus current = _instances[instanceId].status;
        StateValidator.validateTransition(instanceId, current, target);
        _;
    }

    // ========================================================================
    // WRITE FUNCTIONS
    // ========================================================================

    /// @notice Create a new contract instance from an active template
    /// @dev Access: anyone, whenNotPaused.
    /// @param templateId FK to contract_templates
    /// @param metadata ABI-encoded metadata (room_id, session, etc.)
    /// @return instanceId The generated instance ID
    function createInstance(
        bytes32 templateId,
        bytes calldata metadata
    ) external whenNotPaused returns (bytes32 instanceId) {
        // --- Checks ---
        if (!_templatesContract.isTemplateActive(templateId)) {
            revert Types.TemplateNotActive(templateId);
        }

        // --- Effects ---
        uint256 currentNonce = _nonce++;
        instanceId = keccak256(
            abi.encodePacked(templateId, block.timestamp, msg.sender, currentNonce)
        );

        if (_instanceExists[instanceId]) revert Types.InstanceAlreadyExists(instanceId);

        Types.Instance storage inst = _instances[instanceId];
        inst.id = instanceId;
        inst.templateId = templateId;
        inst.status = Types.ContractStatus.Created;
        inst.chainRecord = true; // Phase 1: all on-chain by default
        inst.createdAt = uint48(block.timestamp);
        inst.metadata = metadata;

        _instanceExists[instanceId] = true;
        _instanceIds.push(instanceId);

        emit InstanceCreated(instanceId, templateId, true, uint48(block.timestamp));
    }

    /// @notice Transition instance from Created to Active
    /// @dev Access: onlyRole(SYSTEM_ROLE). Requires party count >= 2.
    /// @param instanceId The instance to activate
    function activateInstance(bytes32 instanceId)
        external
        onlyRole(SYSTEM_ROLE)
        validTransition(instanceId, Types.ContractStatus.Active)
    {
        // Check party count via cross-contract call
        uint8 partyCount = _partiesContract.getPartyCount(instanceId);
        if (partyCount < 2) revert Types.InvalidState(instanceId, Types.ContractStatus.Created);

        Types.Instance storage inst = _instances[instanceId];
        Types.ContractStatus oldStatus = inst.status;
        inst.status = Types.ContractStatus.Active;
        inst.activatedAt = uint48(block.timestamp);

        emit InstanceStatusChanged(
            instanceId,
            oldStatus,
            Types.ContractStatus.Active,
            uint48(block.timestamp)
        );
    }

    /// @notice Transition instance from Active to Completed
    /// @dev Access: onlyRole(CONTRACT_ROLE). Called by ContractResults after final result.
    /// @param instanceId The instance to complete
    function completeInstance(bytes32 instanceId)
        external
        onlyRole(CONTRACT_ROLE)
        validTransition(instanceId, Types.ContractStatus.Completed)
    {
        Types.Instance storage inst = _instances[instanceId];
        Types.ContractStatus oldStatus = inst.status;
        inst.status = Types.ContractStatus.Completed;
        inst.completedAt = uint48(block.timestamp);

        emit InstanceStatusChanged(
            instanceId,
            oldStatus,
            Types.ContractStatus.Completed,
            uint48(block.timestamp)
        );
    }

    /// @notice Transition instance from Completed to Disputed
    /// @dev Access: onlyRole(CONTRACT_ROLE). Called by ContractConsents when party disputes.
    /// @param instanceId The instance to dispute
    function disputeInstance(bytes32 instanceId)
        external
        onlyRole(CONTRACT_ROLE)
        validTransition(instanceId, Types.ContractStatus.Disputed)
    {
        Types.Instance storage inst = _instances[instanceId];
        Types.ContractStatus oldStatus = inst.status;
        inst.status = Types.ContractStatus.Disputed;

        emit InstanceStatusChanged(
            instanceId,
            oldStatus,
            Types.ContractStatus.Disputed,
            uint48(block.timestamp)
        );
    }

    /// @notice Transition instance from Disputed to Resolved
    /// @dev Access: onlyRole(ADMIN_ROLE) or onlyRole(OPERATOR_ROLE).
    /// @param instanceId The instance to resolve
    function resolveInstance(bytes32 instanceId)
        external
        validTransition(instanceId, Types.ContractStatus.Resolved)
    {
        if (
            !hasRole(ADMIN_ROLE, msg.sender) &&
            !hasRole(OPERATOR_ROLE, msg.sender)
        ) {
            revert Types.Unauthorized();
        }

        Types.Instance storage inst = _instances[instanceId];
        Types.ContractStatus oldStatus = inst.status;
        inst.status = Types.ContractStatus.Resolved;

        emit InstanceStatusChanged(
            instanceId,
            oldStatus,
            Types.ContractStatus.Resolved,
            uint48(block.timestamp)
        );
    }

    /// @notice Transition instance from Completed/Resolved to Settled
    /// @dev Access: onlyRole(CONTRACT_ROLE). Called by ContractSettlements.
    /// @param instanceId The instance to settle
    function settleInstance(bytes32 instanceId)
        external
        onlyRole(CONTRACT_ROLE)
        validTransition(instanceId, Types.ContractStatus.Settled)
    {
        Types.Instance storage inst = _instances[instanceId];
        Types.ContractStatus oldStatus = inst.status;
        inst.status = Types.ContractStatus.Settled;
        inst.settledAt = uint48(block.timestamp);

        emit InstanceStatusChanged(
            instanceId,
            oldStatus,
            Types.ContractStatus.Settled,
            uint48(block.timestamp)
        );
    }

    /// @notice Set the ContractParties contract address
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE).
    /// @param partiesContract Address of the ContractParties proxy
    function setPartiesContract(address partiesContract)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (partiesContract == address(0)) revert Types.ZeroAddress();
        _partiesContract = IContractParties(partiesContract);
        emit ContractReferenceUpdated("ContractParties", partiesContract);
    }

    /// @notice Set the ContractResults contract address
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE).
    /// @param resultsContract Address of the ContractResults proxy
    function setResultsContract(address resultsContract)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (resultsContract == address(0)) revert Types.ZeroAddress();
        _resultsContract = resultsContract;
        emit ContractReferenceUpdated("ContractResults", resultsContract);
    }

    /// @notice Set the ContractConsents contract address
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE).
    /// @param consentsContract Address of the ContractConsents proxy
    function setConsentsContract(address consentsContract)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (consentsContract == address(0)) revert Types.ZeroAddress();
        _consentsContract = consentsContract;
        emit ContractReferenceUpdated("ContractConsents", consentsContract);
    }

    /// @notice Set the ContractSettlements contract address
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE).
    /// @param settlementsContract Address of the ContractSettlements proxy
    function setSettlementsContract(address settlementsContract)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (settlementsContract == address(0)) revert Types.ZeroAddress();
        _settlementsContract = settlementsContract;
        emit ContractReferenceUpdated("ContractSettlements", settlementsContract);
    }

    /// @notice Pause the contract
    /// @dev Access: onlyRole(ADMIN_ROLE).
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    /// @dev Access: onlyRole(ADMIN_ROLE).
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /// @notice Get a contract instance by its ID
    /// @param instanceId The instance ID
    /// @return instance The full instance struct
    function getInstance(bytes32 instanceId)
        external
        view
        returns (Types.Instance memory instance)
    {
        if (!_instanceExists[instanceId]) revert Types.ContractNotFound(instanceId);
        instance = _instances[instanceId];
    }

    /// @notice Get the current status of an instance
    /// @param instanceId The instance ID
    /// @return status The current ContractStatus
    function getInstanceStatus(bytes32 instanceId)
        external
        view
        returns (Types.ContractStatus status)
    {
        if (!_instanceExists[instanceId]) revert Types.ContractNotFound(instanceId);
        status = _instances[instanceId].status;
    }

    /// @notice Get the template ID for an instance
    /// @param instanceId The instance ID
    /// @return templateId The linked template ID
    function getInstanceTemplateId(bytes32 instanceId)
        external
        view
        returns (bytes32 templateId)
    {
        if (!_instanceExists[instanceId]) revert Types.ContractNotFound(instanceId);
        templateId = _instances[instanceId].templateId;
    }

    /// @notice Check whether an instance exists
    /// @param instanceId The instance ID
    /// @return exists_ True if the instance exists
    function instanceExists(bytes32 instanceId)
        external
        view
        returns (bool exists_)
    {
        exists_ = _instanceExists[instanceId];
    }

}
