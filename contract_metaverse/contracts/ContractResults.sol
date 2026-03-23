// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {Types} from "./libraries/Types.sol";
import {IContractResults} from "./interfaces/IContractResults.sol";
import {IContractInstances} from "./interfaces/IContractInstances.sol";

/// @title ContractResults — Result storage and completion triggering
/// @notice Stores game/event results for contract instances. When a final result
///         is submitted, calls ContractInstances.completeInstance() to transition
///         the instance from Active to Completed.
/// @dev Deployed behind TransparentUpgradeableProxy. No constructor; uses initialize().
///      Checks-Effects-Interactions pattern strictly followed.
contract ContractResults is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    IContractResults
{
    // ========================================================================
    // ROLE CONSTANTS
    // ========================================================================

    /// @notice Role for the game server / automated system that reports results
    bytes32 public constant SERVER_ROLE = keccak256("SERVER_ROLE");

    /// @notice Role for admin operations (dispute result override)
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @dev instanceId => Result struct
    mapping(bytes32 => Types.Result) private _results;

    /// @dev instanceId => whether a result exists
    mapping(bytes32 => bool) private _resultExists;

    /// @dev Reference to ContractInstances contract
    IContractInstances private _instancesContract;

    /// @dev Nonce for deterministic ID generation
    uint256 private _nonce;

    /// @dev Reserved storage gap for future upgrades
    uint256[46] private __gap;

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
    function initialize(
        address defaultAdmin,
        address instancesContract
    ) external initializer {
        if (defaultAdmin == address(0)) revert Types.ZeroAddress();
        if (instancesContract == address(0)) revert Types.ZeroAddress();

        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(ADMIN_ROLE, defaultAdmin);
        _grantRole(SERVER_ROLE, defaultAdmin);

        _instancesContract = IContractInstances(instancesContract);
    }

    // ========================================================================
    // WRITE FUNCTIONS
    // ========================================================================

    /// @notice Report the result of a contract instance
    /// @dev Checks-Effects-Interactions:
    ///      1. Check: instance status == Active, no final result already submitted
    ///      2. Effect: store Result record, mark result exists
    ///      3. Interaction: if isFinal, call instances.completeInstance()
    /// @param instanceId FK to contract_instances
    /// @param resultData ABI-encoded result (winner_id, moves, score, is_draw, etc.)
    /// @param reportedBy System or User (ResultSource enum)
    /// @param isFinal Whether this result is the definitive final result
    function reportResult(
        bytes32 instanceId,
        bytes calldata resultData,
        Types.ResultSource reportedBy,
        bool isFinal
    ) external onlyRole(SERVER_ROLE) whenNotPaused {
        // --- Checks ---
        if (!_instancesContract.instanceExists(instanceId)) {
            revert Types.ContractNotFound(instanceId);
        }

        Types.ContractStatus status = _instancesContract.getInstanceStatus(instanceId);
        if (status != Types.ContractStatus.Active) {
            revert Types.InvalidState(instanceId, status);
        }

        if (resultData.length == 0) {
            revert Types.InvalidResultData();
        }

        // If a final result already exists, revert
        if (_resultExists[instanceId] && _results[instanceId].isFinal) {
            revert Types.ResultAlreadySubmitted(instanceId);
        }

        // --- Effects ---
        uint48 reportedAt = uint48(block.timestamp);

        // Generate deterministic result ID
        bytes32 resultId = keccak256(
            abi.encodePacked(instanceId, block.timestamp, msg.sender, _nonce++)
        );

        Types.Result storage result = _results[instanceId];
        result.id = resultId;
        result.contractId = instanceId;
        result.reportedBy = reportedBy;
        result.isFinal = isFinal;
        result.reportedAt = reportedAt;
        result.resultData = resultData;

        _resultExists[instanceId] = true;

        emit ResultReported(instanceId, reportedBy, isFinal, resultData, reportedAt);

        // --- Interactions ---
        if (isFinal) {
            _instancesContract.completeInstance(instanceId);
        }
    }

    /// @notice Admin overrides a result during dispute resolution
    /// @dev Instance must be in Disputed state. Replaces existing result data.
    ///      After overriding, admin should call resolveInstance() on ContractInstances.
    /// @param instanceId FK to contract_instances
    /// @param resultData New ABI-encoded result data replacing the previous result
    function overrideResult(
        bytes32 instanceId,
        bytes calldata resultData
    ) external onlyRole(ADMIN_ROLE) whenNotPaused {
        // --- Checks ---
        if (!_resultExists[instanceId]) {
            revert Types.ResultNotFound(instanceId);
        }

        Types.ContractStatus status = _instancesContract.getInstanceStatus(instanceId);
        if (status != Types.ContractStatus.Disputed) {
            revert Types.InvalidState(instanceId, status);
        }

        if (resultData.length == 0) {
            revert Types.InvalidResultData();
        }

        // --- Effects ---
        Types.Result storage result = _results[instanceId];
        bytes memory oldResultData = result.resultData;

        uint48 overriddenAt = uint48(block.timestamp);
        result.resultData = resultData;
        result.reportedAt = overriddenAt;
        result.isFinal = true;

        emit ResultOverridden(instanceId, oldResultData, resultData, overriddenAt);
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

    /// @notice Pause the contract (emergency stop)
    /// @dev Access: onlyRole(ADMIN_ROLE) or DEFAULT_ADMIN_ROLE
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    /// @dev Access: onlyRole(ADMIN_ROLE) or DEFAULT_ADMIN_ROLE
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /// @notice Get the result for a contract instance
    /// @param instanceId FK to contract_instances
    /// @return result The full Result struct
    function getResult(bytes32 instanceId)
        external
        view
        returns (Types.Result memory result)
    {
        if (!_resultExists[instanceId]) {
            revert Types.ResultNotFound(instanceId);
        }
        return _results[instanceId];
    }

    /// @notice Check if a result exists for a contract instance
    /// @param instanceId FK to contract_instances
    /// @return exists True if a result has been reported
    function resultExists(bytes32 instanceId)
        external
        view
        returns (bool exists)
    {
        return _resultExists[instanceId];
    }

    /// @notice Check if the result for an instance is marked final
    /// @param instanceId FK to contract_instances
    /// @return isFinal True if the result is definitive
    function isResultFinal(bytes32 instanceId)
        external
        view
        returns (bool isFinal)
    {
        if (!_resultExists[instanceId]) {
            return false;
        }
        return _results[instanceId].isFinal;
    }
}
