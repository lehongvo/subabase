// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {Types} from "./libraries/Types.sol";
import {IContractConsents} from "./interfaces/IContractConsents.sol";
import {IContractInstances} from "./interfaces/IContractInstances.sol";
import {IContractParties} from "./interfaces/IContractParties.sol";
import {IContractTemplates} from "./interfaces/IContractTemplates.sol";

/// @title ContractConsents — Consent submission, dispute triggering, and timeout
/// @notice After a contract instance reaches Completed status, each party must
///         submit consent (accept) or dispute (reject). If all parties consent,
///         the contract can proceed to settlement. If any party disputes, the
///         instance transitions to Disputed. Auto-consent is applied after timeout.
/// @dev Deployed behind TransparentUpgradeableProxy. No constructor; uses initialize().
///      Checks-Effects-Interactions pattern strictly followed.
contract ContractConsents is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    IContractConsents
{
    // ========================================================================
    // ROLE CONSTANTS
    // ========================================================================

    /// @notice Role for the server that relays user consent on-chain
    bytes32 public constant SERVER_ROLE = keccak256("SERVER_ROLE");

    /// @notice Role for admin operations
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @dev instanceId => userId => Consent struct
    mapping(bytes32 => mapping(address => Types.Consent)) private _consents;

    /// @dev instanceId => number of consents submitted
    mapping(bytes32 => uint8) private _consentCount;

    /// @dev instanceId => whether a dispute has been raised
    mapping(bytes32 => bool) private _hasDispute;

    /// @dev instanceId => consent deadline timestamp (first consent + timeout)
    mapping(bytes32 => uint48) private _consentDeadline;

    /// @dev Reference to ContractInstances contract
    IContractInstances private _instancesContract;

    /// @dev Reference to ContractParties contract
    IContractParties private _partiesContract;

    /// @dev Reference to ContractTemplates contract (for reading timeout_seconds)
    IContractTemplates private _templatesContract;

    /// @dev Nonce for deterministic ID generation
    uint256 private _nonce;

    /// @dev Reserved storage gap for future upgrades
    uint256[42] private __gap;

    // ========================================================================
    // INITIALIZER
    // ========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract (proxy pattern, replaces constructor)
    /// @param defaultAdmin Address granted DEFAULT_ADMIN_ROLE
    /// @param instancesContract Address of the ContractInstances proxy
    /// @param partiesContract Address of the ContractParties proxy
    function initialize(
        address defaultAdmin,
        address instancesContract,
        address partiesContract
    ) external initializer {
        if (defaultAdmin == address(0)) revert Types.ZeroAddress();
        if (instancesContract == address(0)) revert Types.ZeroAddress();
        if (partiesContract == address(0)) revert Types.ZeroAddress();

        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(ADMIN_ROLE, defaultAdmin);
        _grantRole(SERVER_ROLE, defaultAdmin);

        _instancesContract = IContractInstances(instancesContract);
        _partiesContract = IContractParties(partiesContract);
    }

    // ========================================================================
    // WRITE FUNCTIONS
    // ========================================================================

    /// @notice A party submits consent or objection for a contract result
    /// @dev Checks-Effects-Interactions:
    ///      1. Check: status == Completed or Resolved, user is party, not already consented
    ///      2. Effect: store Consent, increment count, set deadline on first consent
    ///      3. Interaction: if !consented, call instances.disputeInstance()
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
    ) external onlyRole(SERVER_ROLE) whenNotPaused {
        // --- Checks ---
        Types.ContractStatus status = _instancesContract.getInstanceStatus(instanceId);
        if (status != Types.ContractStatus.Completed && status != Types.ContractStatus.Resolved) {
            revert Types.InvalidState(instanceId, status);
        }

        // Verify userId is a party of this contract
        if (!_partiesContract.hasJoined(instanceId, userId)) {
            revert Types.NotAParty(instanceId, userId);
        }

        // Verify user hasn't already submitted consent
        if (_consents[instanceId][userId].consentedAt != 0) {
            revert Types.AlreadyConsented(instanceId, userId);
        }

        // --- Effects ---
        uint48 consentedAt = uint48(block.timestamp);

        bytes32 consentId = keccak256(
            abi.encodePacked(instanceId, userId, block.timestamp, msg.sender, _nonce++)
        );

        Types.Consent storage consent = _consents[instanceId][userId];
        consent.id = consentId;
        consent.contractId = instanceId;
        consent.userId = userId;
        consent.consented = consented;
        consent.consentedAt = consentedAt;
        consent.signature = signature;

        _consentCount[instanceId] += 1;

        // Set consent deadline on first consent submission
        if (_consentCount[instanceId] == 1) {
            uint256 timeoutSeconds = _getTimeoutSeconds(instanceId);
            _consentDeadline[instanceId] = consentedAt + uint48(timeoutSeconds);
        }

        if (consented) {
            emit ConsentSubmitted(instanceId, userId, true, consentedAt);
        } else {
            // Store dispute reason
            consent.reason = reason;
            _hasDispute[instanceId] = true;

            emit ConsentSubmitted(instanceId, userId, false, consentedAt);
            emit DisputeRaised(instanceId, userId, reason, consentedAt);

            // --- Interactions ---
            // Only trigger dispute transition if instance is still in Completed state
            // (avoids double-dispatch if another party already triggered it)
            Types.ContractStatus currentStatus = _instancesContract.getInstanceStatus(instanceId);
            if (currentStatus == Types.ContractStatus.Completed) {
                _instancesContract.disputeInstance(instanceId);
            }
        }
    }

    /// @notice Auto-consent for a user after timeout expiry
    /// @dev Validates that the consent deadline has passed and the user hasn't already consented.
    ///      Auto-consent is equivalent to consented = true.
    /// @param instanceId FK to contract_instances
    /// @param userId The user whose consent timed out
    function autoConsent(
        bytes32 instanceId,
        address userId
    ) external onlyRole(SERVER_ROLE) whenNotPaused {
        // --- Checks ---
        // Deadline must have been set (at least one consent already submitted)
        uint48 deadline = _consentDeadline[instanceId];
        if (deadline == 0) {
            revert Types.ConsentNotComplete(instanceId);
        }

        if (block.timestamp < deadline) {
            revert Types.ConsentNotComplete(instanceId);
        }

        // Verify userId is a party of this contract
        if (!_partiesContract.hasJoined(instanceId, userId)) {
            revert Types.NotAParty(instanceId, userId);
        }

        // Verify user hasn't already submitted consent
        if (_consents[instanceId][userId].consentedAt != 0) {
            revert Types.AlreadyConsented(instanceId, userId);
        }

        // --- Effects ---
        uint48 appliedAt = uint48(block.timestamp);

        bytes32 consentId = keccak256(
            abi.encodePacked(instanceId, userId, block.timestamp, "auto", _nonce++)
        );

        Types.Consent storage consent = _consents[instanceId][userId];
        consent.id = consentId;
        consent.contractId = instanceId;
        consent.userId = userId;
        consent.consented = true;
        consent.consentedAt = appliedAt;

        _consentCount[instanceId] += 1;

        emit AutoConsentApplied(instanceId, userId, appliedAt);
    }

    /// @notice Set cross-contract reference to ContractInstances
    /// @param instancesContract Address of the ContractInstances proxy
    function setInstancesContract(address instancesContract)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (instancesContract == address(0)) {
            revert Types.InvalidContractReference("ContractInstances");
        }
        _instancesContract = IContractInstances(instancesContract);
    }

    /// @notice Set cross-contract reference to ContractParties
    /// @param partiesContract Address of the ContractParties proxy
    function setPartiesContract(address partiesContract)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (partiesContract == address(0)) {
            revert Types.InvalidContractReference("ContractParties");
        }
        _partiesContract = IContractParties(partiesContract);
    }

    /// @notice Set cross-contract reference to ContractTemplates
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE). Needed for reading timeout_seconds.
    /// @param templatesContract Address of the ContractTemplates proxy
    function setTemplatesContract(address templatesContract)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (templatesContract == address(0)) {
            revert Types.InvalidContractReference("ContractTemplates");
        }
        _templatesContract = IContractTemplates(templatesContract);
    }

    /// @notice Pause the contract (emergency stop)
    /// @dev Access: onlyRole(ADMIN_ROLE)
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    /// @dev Access: onlyRole(ADMIN_ROLE)
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /// @notice Check if all parties have consented (or auto-consented via timeout)
    /// @param instanceId FK to contract_instances
    /// @return allDone True if all parties have submitted consent
    function allConsented(bytes32 instanceId)
        external
        view
        returns (bool allDone)
    {
        uint8 partyCount = _partiesContract.getPartyCount(instanceId);
        return _consentCount[instanceId] >= partyCount && partyCount > 0;
    }

    /// @notice Check if an instance has a dispute
    /// @param instanceId FK to contract_instances
    /// @return disputed True if any party submitted consented == false
    function hasDispute(bytes32 instanceId)
        external
        view
        returns (bool disputed)
    {
        return _hasDispute[instanceId];
    }

    /// @notice Get a specific party's consent record
    /// @param instanceId FK to contract_instances
    /// @param userId The user's wallet address
    /// @return consent The full Consent struct
    function getConsent(bytes32 instanceId, address userId)
        external
        view
        returns (Types.Consent memory consent)
    {
        return _consents[instanceId][userId];
    }

    /// @notice Get the number of consents submitted for an instance
    /// @param instanceId FK to contract_instances
    /// @return count Number of consent records
    function getConsentCount(bytes32 instanceId)
        external
        view
        returns (uint8 count)
    {
        return _consentCount[instanceId];
    }

    /// @notice Get the consent deadline for an instance
    /// @param instanceId FK to contract_instances
    /// @return deadline The timestamp after which auto-consent can be applied
    function getConsentDeadline(bytes32 instanceId)
        external
        view
        returns (uint48 deadline)
    {
        return _consentDeadline[instanceId];
    }

    // ========================================================================
    // INTERNAL HELPERS
    // ========================================================================

    /// @dev Reads timeout_seconds from the template conditions for a given instance.
    ///      Falls back to 300 seconds (5 minutes) if templates contract is not set
    ///      or conditions are empty.
    /// @param instanceId The contract instance ID
    /// @return timeoutSeconds The consent timeout in seconds
    function _getTimeoutSeconds(bytes32 instanceId)
        internal
        view
        returns (uint256 timeoutSeconds)
    {
        // If templates contract is not set, use default
        if (address(_templatesContract) == address(0)) {
            return 300; // 5 minutes default
        }

        bytes32 templateId = _instancesContract.getInstanceTemplateId(instanceId);
        Types.Template memory template_ = _templatesContract.getTemplate(templateId);

        if (template_.conditions.length == 0) {
            return 300; // 5 minutes default
        }

        // TemplateConditions: (uint256 minBet, uint256 maxBet, uint256 rounds, uint256 timeoutSeconds)
        (, , , timeoutSeconds) = abi.decode(
            template_.conditions,
            (uint256, uint256, uint256, uint256)
        );

        // Ensure a minimum timeout of 10 seconds
        if (timeoutSeconds < 10) {
            timeoutSeconds = 10;
        }
    }
}
