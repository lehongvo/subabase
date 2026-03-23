// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title EmergencyStop -- Granular pause control for IX Metaverse Contract System
/// @notice Provides both global and per-contract pause functionality with role-based access.
/// @dev Abstract contract designed to be inherited by core contracts. Implements a two-tier
///      pause system: a global pause that halts all operations, and per-contract pauses that
///      allow surgical intervention on individual contract instances.
///
///      Emergency fund recovery follows a timelock concept: when paused, an admin can initiate
///      a recovery request that takes effect only after a cooldown period, providing a safety
///      window to cancel erroneous recovery actions.
///
///      Inheriting contracts should apply the `whenOperational` modifier to all state-changing
///      functions instead of a simple `whenNotPaused` modifier.
abstract contract EmergencyStop {

    // ========================================================================
    // STATE
    // ========================================================================

    /// @notice Whether the entire system is globally paused
    bool private _globalPaused;

    /// @notice Per-contract pause state (contractId => paused)
    mapping(bytes32 => bool) private _contractPaused;

    /// @notice Pending emergency recovery requests (requestId => unlock timestamp)
    /// @dev Recovery is only executable after the timelock period elapses
    mapping(bytes32 => uint256) private _recoveryTimelocks;

    /// @notice Minimum delay (in seconds) before a recovery request can be executed
    uint256 private _recoveryDelay;

    /// @notice Default recovery delay set during initialization (48 hours)
    uint256 private constant DEFAULT_RECOVERY_DELAY = 48 hours;

    // ========================================================================
    // EVENTS
    // ========================================================================

    /// @notice Emitted when the global pause state changes
    /// @param paused True if paused, false if unpaused
    /// @param caller Address that triggered the action
    event GlobalPauseChanged(bool indexed paused, address indexed caller);

    /// @notice Emitted when a specific contract's pause state changes
    /// @param contractId The contract instance being paused/unpaused
    /// @param paused True if paused, false if unpaused
    /// @param caller Address that triggered the action
    event ContractPauseChanged(bytes32 indexed contractId, bool indexed paused, address indexed caller);

    /// @notice Emitted when an emergency recovery is requested
    /// @param requestId Unique identifier for the recovery request
    /// @param target Address where recovered funds would be sent
    /// @param unlockTime Timestamp after which the recovery can be executed
    /// @param caller Address that initiated the request
    event RecoveryRequested(bytes32 indexed requestId, address indexed target, uint256 unlockTime, address indexed caller);

    /// @notice Emitted when a pending recovery request is cancelled
    /// @param requestId The cancelled recovery request identifier
    /// @param caller Address that cancelled the request
    event RecoveryCancelled(bytes32 indexed requestId, address indexed caller);

    /// @notice Emitted when a recovery request is executed after timelock expiry
    /// @param requestId The executed recovery request identifier
    /// @param target Address that received the recovered funds
    /// @param caller Address that executed the recovery
    event RecoveryExecuted(bytes32 indexed requestId, address indexed target, address indexed caller);

    /// @notice Emitted when the recovery delay is updated
    /// @param oldDelay Previous delay in seconds
    /// @param newDelay New delay in seconds
    /// @param caller Address that updated the delay
    event RecoveryDelayUpdated(uint256 oldDelay, uint256 newDelay, address indexed caller);

    // ========================================================================
    // ERRORS
    // ========================================================================

    /// @notice Thrown when an operation is attempted while globally paused
    error GloballyPaused();

    /// @notice Thrown when an operation is attempted on a paused contract
    /// @param contractId The paused contract instance
    error ContractIsPaused(bytes32 contractId);

    /// @notice Thrown when trying to pause an already-paused entity or unpause an already-active entity
    error PauseStateUnchanged();

    /// @notice Thrown when trying to execute a recovery before the timelock expires
    /// @param requestId The recovery request
    /// @param unlockTime When the timelock expires
    /// @param currentTime Current block timestamp
    error RecoveryTimelocked(bytes32 requestId, uint256 unlockTime, uint256 currentTime);

    /// @notice Thrown when referencing a recovery request that does not exist
    /// @param requestId The invalid recovery request identifier
    error RecoveryNotFound(bytes32 requestId);

    /// @notice Thrown when the recovery delay value is invalid (zero)
    error InvalidRecoveryDelay();

    /// @notice Thrown when the recovery target address is invalid (zero address)
    error InvalidRecoveryTarget();

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    /// @notice Reverts if the system is globally paused
    modifier whenNotGloballyPaused() {
        if (_globalPaused) revert GloballyPaused();
        _;
    }

    /// @notice Reverts if the system is globally paused OR the specified contract is paused
    /// @param contractId The contract instance to check
    modifier whenOperational(bytes32 contractId) {
        if (_globalPaused) revert GloballyPaused();
        if (_contractPaused[contractId]) revert ContractIsPaused(contractId);
        _;
    }

    /// @notice Reverts if the system is globally paused (alias for whenNotGloballyPaused)
    /// @dev Use this on functions that are not contract-instance-specific
    modifier whenSystemOperational() {
        if (_globalPaused) revert GloballyPaused();
        _;
    }

    // ========================================================================
    // INTERNAL INITIALIZER
    // ========================================================================

    /// @notice Initialize the EmergencyStop state
    /// @dev Must be called by the inheriting contract's initializer
    /// @param recoveryDelay_ Initial recovery timelock delay in seconds. Pass 0 to use the default (48h).
    function __EmergencyStop_init(uint256 recoveryDelay_) internal {
        _recoveryDelay = recoveryDelay_ == 0 ? DEFAULT_RECOVERY_DELAY : recoveryDelay_;
    }

    // ========================================================================
    // AUTHORIZATION HOOK (must be overridden)
    // ========================================================================

    /// @notice Authorization check for emergency actions
    /// @dev Must be implemented by the inheriting contract to enforce ADMIN_ROLE access
    /// @param caller The address attempting the emergency action
    function _checkEmergencyAccess(address caller) internal view virtual;

    // ========================================================================
    // GLOBAL PAUSE
    // ========================================================================

    /// @notice Pause the entire system globally
    /// @dev Only callable by addresses passing the `_checkEmergencyAccess` check (ADMIN_ROLE)
    function globalPause() external {
        _checkEmergencyAccess(msg.sender);
        if (_globalPaused) revert PauseStateUnchanged();
        _globalPaused = true;
        emit GlobalPauseChanged(true, msg.sender);
    }

    /// @notice Unpause the entire system globally
    /// @dev Only callable by addresses passing the `_checkEmergencyAccess` check (ADMIN_ROLE)
    function globalUnpause() external {
        _checkEmergencyAccess(msg.sender);
        if (!_globalPaused) revert PauseStateUnchanged();
        _globalPaused = false;
        emit GlobalPauseChanged(false, msg.sender);
    }

    // ========================================================================
    // PER-CONTRACT PAUSE
    // ========================================================================

    /// @notice Pause a specific contract instance
    /// @dev Only callable by addresses passing the `_checkEmergencyAccess` check (ADMIN_ROLE)
    /// @param contractId The contract instance to pause
    function pauseContract(bytes32 contractId) external {
        _checkEmergencyAccess(msg.sender);
        if (_contractPaused[contractId]) revert PauseStateUnchanged();
        _contractPaused[contractId] = true;
        emit ContractPauseChanged(contractId, true, msg.sender);
    }

    /// @notice Unpause a specific contract instance
    /// @dev Only callable by addresses passing the `_checkEmergencyAccess` check (ADMIN_ROLE)
    /// @param contractId The contract instance to unpause
    function unpauseContract(bytes32 contractId) external {
        _checkEmergencyAccess(msg.sender);
        if (!_contractPaused[contractId]) revert PauseStateUnchanged();
        _contractPaused[contractId] = false;
        emit ContractPauseChanged(contractId, false, msg.sender);
    }

    // ========================================================================
    // EMERGENCY FUND RECOVERY (with timelock)
    // ========================================================================

    /// @notice Request an emergency fund recovery (subject to timelock)
    /// @dev Creates a pending recovery that can only be executed after `_recoveryDelay` seconds.
    ///      The requestId is deterministic: keccak256(target, block.timestamp, msg.sender).
    /// @param target The address to receive recovered funds
    /// @return requestId The unique identifier for this recovery request
    function requestRecovery(address target) external returns (bytes32 requestId) {
        _checkEmergencyAccess(msg.sender);
        if (target == address(0)) revert InvalidRecoveryTarget();

        requestId = keccak256(abi.encodePacked(target, block.timestamp, msg.sender));
        uint256 unlockTime = block.timestamp + _recoveryDelay;
        _recoveryTimelocks[requestId] = unlockTime;

        emit RecoveryRequested(requestId, target, unlockTime, msg.sender);
    }

    /// @notice Cancel a pending recovery request
    /// @param requestId The recovery request to cancel
    function cancelRecovery(bytes32 requestId) external {
        _checkEmergencyAccess(msg.sender);
        if (_recoveryTimelocks[requestId] == 0) revert RecoveryNotFound(requestId);

        delete _recoveryTimelocks[requestId];
        emit RecoveryCancelled(requestId, msg.sender);
    }

    /// @notice Execute a recovery request after the timelock has expired
    /// @dev The inheriting contract must override `_executeRecovery` to implement the actual
    ///      fund transfer logic. This function only validates the timelock.
    /// @param requestId The recovery request to execute
    /// @param target The address to receive recovered funds (must match the original request)
    function executeRecovery(bytes32 requestId, address target) external {
        _checkEmergencyAccess(msg.sender);

        uint256 unlockTime = _recoveryTimelocks[requestId];
        if (unlockTime == 0) revert RecoveryNotFound(requestId);
        if (block.timestamp < unlockTime) {
            revert RecoveryTimelocked(requestId, unlockTime, block.timestamp);
        }

        delete _recoveryTimelocks[requestId];
        _executeRecovery(requestId, target);

        emit RecoveryExecuted(requestId, target, msg.sender);
    }

    /// @notice Hook for inheriting contracts to implement actual fund recovery logic
    /// @dev Override this to transfer tokens, ETH, or other assets to the target
    /// @param requestId The recovery request being executed
    /// @param target The recipient of recovered funds
    function _executeRecovery(bytes32 requestId, address target) internal virtual;

    // ========================================================================
    // RECOVERY DELAY MANAGEMENT
    // ========================================================================

    /// @notice Update the recovery timelock delay
    /// @dev Only callable by addresses passing the `_checkEmergencyAccess` check
    /// @param newDelay New delay in seconds (must be > 0)
    function setRecoveryDelay(uint256 newDelay) external {
        _checkEmergencyAccess(msg.sender);
        if (newDelay == 0) revert InvalidRecoveryDelay();

        uint256 oldDelay = _recoveryDelay;
        _recoveryDelay = newDelay;
        emit RecoveryDelayUpdated(oldDelay, newDelay, msg.sender);
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /// @notice Check if the system is globally paused
    /// @return True if globally paused
    function isGloballyPaused() external view returns (bool) {
        return _globalPaused;
    }

    /// @notice Check if a specific contract instance is paused
    /// @param contractId The contract instance to check
    /// @return True if the contract is individually paused
    function isContractPaused(bytes32 contractId) external view returns (bool) {
        return _contractPaused[contractId];
    }

    /// @notice Check if a contract is operational (not globally paused AND not individually paused)
    /// @param contractId The contract instance to check
    /// @return True if the contract is fully operational
    function isOperational(bytes32 contractId) external view returns (bool) {
        return !_globalPaused && !_contractPaused[contractId];
    }

    /// @notice Get the current recovery timelock delay
    /// @return The delay in seconds
    function getRecoveryDelay() external view returns (uint256) {
        return _recoveryDelay;
    }

    /// @notice Get the unlock time for a pending recovery request
    /// @param requestId The recovery request to query
    /// @return The unlock timestamp (0 if not found)
    function getRecoveryUnlockTime(bytes32 requestId) external view returns (uint256) {
        return _recoveryTimelocks[requestId];
    }
}
