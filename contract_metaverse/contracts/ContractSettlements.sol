// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {Types} from "./libraries/Types.sol";
import {FeeCalculator} from "./libraries/FeeCalculator.sol";
import {IContractSettlements} from "./interfaces/IContractSettlements.sol";
import {IContractInstances} from "./interfaces/IContractInstances.sol";
import {IContractParties} from "./interfaces/IContractParties.sol";
import {IContractResults} from "./interfaces/IContractResults.sol";
import {IContractConsents} from "./interfaces/IContractConsents.sol";
import {IContractTemplates} from "./interfaces/IContractTemplates.sol";

/// @title ContractSettlements — Fee calculation, token distribution, and status finalization
/// @notice Handles the settlement phase of contract instances:
///         - Winner scenario: calculates fee, distributes reward to winner and fee to treasury
///         - Draw scenario: refunds all escrowed amounts to original depositors (no fee)
///         - Updates instance status to Settled via ContractInstances
/// @dev Deployed behind TransparentUpgradeableProxy. No constructor; uses initialize().
///      Strictly follows Checks-Effects-Interactions pattern.
///      All token operations use SafeERC20 for non-standard ERC-20 compatibility.
contract ContractSettlements is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IContractSettlements
{

    // ========================================================================
    // ROLE CONSTANTS
    // ========================================================================

    /// @notice Role for automated settler (bot or admin) that triggers settlement
    bytes32 public constant SETTLER_ROLE = keccak256("SETTLER_ROLE");

    /// @notice Role for admin operations (refund, treasury management)
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @dev instanceId => array of Settlement records
    mapping(bytes32 => Types.Settlement[]) private _settlements;

    /// @dev instanceId => whether settlement has been completed
    mapping(bytes32 => bool) private _isSettled;

    /// @dev Reference to ContractInstances
    IContractInstances private _instancesContract;

    /// @dev Reference to ContractParties
    IContractParties private _partiesContract;

    /// @dev Reference to ContractResults
    IContractResults private _resultsContract;

    /// @dev Reference to ContractConsents
    IContractConsents private _consentsContract;

    /// @dev Reference to ContractTemplates (for fee rate lookup)
    IContractTemplates private _templatesContract;

    /// @dev Treasury address for platform fee collection
    address private _treasury;

    /// @dev Nonce for deterministic ID generation
    uint256 private _nonce;

    /// @dev Reserved storage gap for future upgrades
    uint256[41] private __gap;

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
    /// @param resultsContract Address of the ContractResults proxy
    /// @param consentsContract Address of the ContractConsents proxy
    /// @param treasury Address of the treasury (platform fee recipient)
    function initialize(
        address defaultAdmin,
        address instancesContract,
        address partiesContract,
        address resultsContract,
        address consentsContract,
        address treasury
    ) external initializer {
        if (defaultAdmin == address(0)) revert Types.ZeroAddress();
        if (instancesContract == address(0)) revert Types.ZeroAddress();
        if (partiesContract == address(0)) revert Types.ZeroAddress();
        if (resultsContract == address(0)) revert Types.ZeroAddress();
        if (consentsContract == address(0)) revert Types.ZeroAddress();
        if (treasury == address(0)) revert Types.InvalidTreasuryAddress();

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(ADMIN_ROLE, defaultAdmin);
        _grantRole(SETTLER_ROLE, defaultAdmin);

        _instancesContract = IContractInstances(instancesContract);
        _partiesContract = IContractParties(partiesContract);
        _resultsContract = IContractResults(resultsContract);
        _consentsContract = IContractConsents(consentsContract);
        _treasury = treasury;
    }

    // ========================================================================
    // WRITE FUNCTIONS
    // ========================================================================

    /// @notice Execute full settlement for a contract instance (winner scenario)
    /// @dev Checks-Effects-Interactions:
    ///      1. Checks: consent complete, status valid, result exists, not already settled
    ///      2. Effects: create Settlement records, mark as settled
    ///      3. Interactions: release escrow to winner + treasury, settle instance
    ///
    ///      Fee calculation (basis points):
    ///        totalEscrow = SUM(all parties' escrow_amount)
    ///        feeAmount   = totalEscrow * feeRateBps / 10000
    ///        winnerAmount = totalEscrow - feeAmount
    ///
    ///      RPS walkthrough verification:
    ///        A stakes 50e18, B stakes 50e18 => totalEscrow = 100e18
    ///        feeRate = 300 bps (3%)
    ///        feeAmount = 100e18 * 300 / 10000 = 3e18
    ///        winnerAmount = 100e18 - 3e18 = 97e18
    ///        B (winner) gets 97e18, Treasury gets 3e18
    /// @param instanceId FK to contract_instances
    function settleContract(bytes32 instanceId)
        external
        onlyRole(SETTLER_ROLE)
        whenNotPaused
        nonReentrant
    {
        // --- Checks ---
        if (_isSettled[instanceId]) {
            revert Types.SettlementAlreadyDone(instanceId);
        }

        Types.ContractStatus status = _instancesContract.getInstanceStatus(instanceId);
        if (status != Types.ContractStatus.Completed && status != Types.ContractStatus.Resolved) {
            revert Types.InvalidState(instanceId, status);
        }

        // Verify all parties have consented (or auto-consented, or dispute resolved)
        // For Resolved status, we skip consent check as admin has resolved the dispute
        if (status == Types.ContractStatus.Completed) {
            if (!_consentsContract.allConsented(instanceId)) {
                revert Types.ConsentNotComplete(instanceId);
            }
        }

        // Read result
        Types.Result memory result = _resultsContract.getResult(instanceId);
        if (!result.isFinal) {
            revert Types.InvalidState(instanceId, status);
        }

        // Read parties and calculate total escrow
        Types.Party[] memory parties = _partiesContract.getParties(instanceId);
        uint128 totalEscrow = _partiesContract.getTotalEscrow(instanceId);

        // Read template fee rate
        bytes32 templateId = _instancesContract.getInstanceTemplateId(instanceId);
        uint16 feeRateBps = _templatesContract.getTemplateFeeRate(templateId);

        // Determine winner from result data
        // result_data is ABI-encoded: (address winnerId, string winnerMove, string loserMove,
        //                              uint256 roundsPlayed, string score, bool isDraw)
        (address winnerId, , , , , bool isDraw) = abi.decode(
            result.resultData,
            (address, string, string, uint256, string, bool)
        );

        // If draw, caller should use refundContract instead
        if (isDraw) {
            revert Types.InvalidState(instanceId, status);
        }

        // Calculate fee using FeeCalculator library (validates bounds)
        (uint128 winnerAmount, uint128 feeAmount) = FeeCalculator.calculateFee(totalEscrow, feeRateBps);

        // Determine the escrow point type from the first party (all parties use the same type)
        Types.PointType pointType = parties[0].escrowType;

        uint48 settledAt = uint48(block.timestamp);

        // --- Effects ---
        // Create reward settlement record
        bytes32 rewardSettlementId = keccak256(
            abi.encodePacked(instanceId, winnerId, "reward", _nonce++)
        );
        _settlements[instanceId].push(Types.Settlement({
            id: rewardSettlementId,
            contractId: instanceId,
            fromUserId: address(_partiesContract),  // escrow vault = parties contract
            settlementType: Types.SettlementType.Reward,
            pointType: pointType,
            settledAt: settledAt,
            toUserId: winnerId,
            amount: winnerAmount,
            feeAmount: 0,
            txHash: bytes32(0)
        }));

        // Create fee settlement record
        bytes32 feeSettlementId = keccak256(
            abi.encodePacked(instanceId, _treasury, "fee", _nonce++)
        );
        _settlements[instanceId].push(Types.Settlement({
            id: feeSettlementId,
            contractId: instanceId,
            fromUserId: address(_partiesContract),  // escrow vault
            settlementType: Types.SettlementType.Fee,
            pointType: pointType,
            settledAt: settledAt,
            toUserId: _treasury,
            amount: feeAmount,
            feeAmount: feeAmount,
            txHash: bytes32(0)
        }));

        _isSettled[instanceId] = true;

        // Emit settlement events
        emit SettlementExecuted(
            instanceId,
            address(_partiesContract),
            winnerId,
            winnerAmount,
            0,
            Types.SettlementType.Reward,
            pointType,
            settledAt
        );

        emit SettlementExecuted(
            instanceId,
            address(_partiesContract),
            _treasury,
            feeAmount,
            feeAmount,
            Types.SettlementType.Fee,
            pointType,
            settledAt
        );

        emit ContractSettled(instanceId, totalEscrow, feeAmount, settledAt);

        // --- Interactions ---
        // Release escrow: winner gets winnerAmount, treasury gets feeAmount
        _partiesContract.releaseEscrow(instanceId, winnerId, winnerAmount);
        _partiesContract.releaseEscrow(instanceId, _treasury, feeAmount);

        // Transition instance to Settled
        _instancesContract.settleInstance(instanceId);
    }

    /// @notice Execute refund settlement (draw or cancellation)
    /// @dev All escrowed amounts returned to original depositors. No fee charged.
    ///
    ///      Draw walkthrough verification:
    ///        A stakes 50e18, B stakes 50e18
    ///        refund: A gets 50e18 back, B gets 50e18 back
    ///        Treasury gets 0
    /// @param instanceId FK to contract_instances
    function refundContract(bytes32 instanceId)
        external
        whenNotPaused
        nonReentrant
    {
        // Allow both SETTLER_ROLE and ADMIN_ROLE
        if (!hasRole(SETTLER_ROLE, msg.sender) && !hasRole(ADMIN_ROLE, msg.sender)) {
            revert Types.Unauthorized();
        }

        // --- Checks ---
        if (_isSettled[instanceId]) {
            revert Types.SettlementAlreadyDone(instanceId);
        }

        Types.ContractStatus status = _instancesContract.getInstanceStatus(instanceId);
        if (
            status != Types.ContractStatus.Completed &&
            status != Types.ContractStatus.Resolved &&
            status != Types.ContractStatus.Active &&
            status != Types.ContractStatus.Created
        ) {
            revert Types.InvalidState(instanceId, status);
        }

        // For Completed status, verify all consented (or admin can force refund)
        if (status == Types.ContractStatus.Completed) {
            if (!hasRole(ADMIN_ROLE, msg.sender) && !_consentsContract.allConsented(instanceId)) {
                revert Types.ConsentNotComplete(instanceId);
            }
        }

        // Read parties
        Types.Party[] memory parties = _partiesContract.getParties(instanceId);
        uint128 totalRefunded = 0;
        uint48 settledAt = uint48(block.timestamp);

        // --- Effects ---
        for (uint256 i = 0; i < parties.length; i++) {
            Types.Party memory party = parties[i];
            if (party.escrowAmount == 0) continue;

            bytes32 refundSettlementId = keccak256(
                abi.encodePacked(instanceId, party.userId, "refund", _nonce++)
            );

            _settlements[instanceId].push(Types.Settlement({
                id: refundSettlementId,
                contractId: instanceId,
                fromUserId: address(_partiesContract),  // escrow vault
                settlementType: Types.SettlementType.Refund,
                pointType: party.escrowType,
                settledAt: settledAt,
                toUserId: party.userId,
                amount: party.escrowAmount,
                feeAmount: 0,
                txHash: bytes32(0)
            }));

            totalRefunded += party.escrowAmount;

            emit SettlementExecuted(
                instanceId,
                address(_partiesContract),
                party.userId,
                party.escrowAmount,
                0,
                Types.SettlementType.Refund,
                party.escrowType,
                settledAt
            );
        }

        _isSettled[instanceId] = true;

        emit ContractRefunded(instanceId, totalRefunded, settledAt);

        // --- Interactions ---
        // Refund all escrow back to original depositors
        _partiesContract.refundEscrow(instanceId);

        // Transition instance to Settled
        _instancesContract.settleInstance(instanceId);
    }

    /// @notice Set the treasury address for fee collection
    /// @param treasury New treasury address
    function setTreasury(address treasury)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (treasury == address(0)) {
            revert Types.InvalidTreasuryAddress();
        }
        _treasury = treasury;
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

    /// @notice Set cross-contract reference to ContractResults
    /// @param resultsContract Address of the ContractResults proxy
    function setResultsContract(address resultsContract)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (resultsContract == address(0)) {
            revert Types.InvalidContractReference("ContractResults");
        }
        _resultsContract = IContractResults(resultsContract);
    }

    /// @notice Set cross-contract reference to ContractConsents
    /// @param consentsContract Address of the ContractConsents proxy
    function setConsentsContract(address consentsContract)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (consentsContract == address(0)) {
            revert Types.InvalidContractReference("ContractConsents");
        }
        _consentsContract = IContractConsents(consentsContract);
    }

    /// @notice Set cross-contract reference to ContractTemplates
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE). Required for fee rate lookup.
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

    /// @notice Get all settlement records for a contract instance
    /// @param instanceId FK to contract_instances
    /// @return settlements Array of Settlement structs
    function getSettlements(bytes32 instanceId)
        external
        view
        returns (Types.Settlement[] memory settlements)
    {
        return _settlements[instanceId];
    }

    /// @notice Check if a contract instance has been settled
    /// @param instanceId FK to contract_instances
    /// @return settled True if settlement records exist
    function isSettled(bytes32 instanceId)
        external
        view
        returns (bool settled)
    {
        return _isSettled[instanceId];
    }

    /// @notice Get the number of settlement records for an instance
    /// @param instanceId FK to contract_instances
    /// @return count Number of settlement records
    function getSettlementCount(bytes32 instanceId)
        external
        view
        returns (uint256 count)
    {
        return _settlements[instanceId].length;
    }

    /// @notice Get the current treasury address
    /// @return treasuryAddr The treasury address
    function getTreasury()
        external
        view
        returns (address treasuryAddr)
    {
        return _treasury;
    }
}
