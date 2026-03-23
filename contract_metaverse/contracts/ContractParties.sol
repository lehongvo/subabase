// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IContractParties} from "./interfaces/IContractParties.sol";
import {IContractInstances} from "./interfaces/IContractInstances.sol";
import {IContractTemplates} from "./interfaces/IContractTemplates.sol";
import {Types} from "./libraries/Types.sol";

/// @title ContractParties — Party management and escrow operations
/// @notice Handles party joining with ERC-20 escrow deposits, and escrow
///         release/refund during settlement. This contract holds all escrowed tokens.
/// @dev Deployed behind TransparentUpgradeableProxy. No constructor; uses initialize().
///      Maps to Phase 0 DB table `contract_parties`.
///      Uses SafeERC20 for all token operations to handle non-standard ERC-20 tokens.
contract ContractParties is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IContractParties
{
    using SafeERC20 for IERC20;

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant CONTRACT_ROLE = keccak256("CONTRACT_ROLE");
    bytes32 public constant SYSTEM_ROLE = keccak256("SYSTEM_ROLE");

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @dev instanceId => Party[]
    mapping(bytes32 => Types.Party[]) private _parties;

    /// @dev instanceId => user => bool (has already joined)
    mapping(bytes32 => mapping(address => bool)) private _hasJoined;

    /// @dev instanceId => party count
    mapping(bytes32 => uint8) private _partyCount;

    /// @dev instanceId => user => index in _parties array
    mapping(bytes32 => mapping(address => uint256)) private _partyIndex;

    /// @dev Cross-contract references
    IContractInstances private _instancesContract;
    IContractTemplates private _templatesContract;

    /// @dev The ERC-20 token used for escrow (e.g., USDT on MegaETH)
    IERC20 private _paymentToken;

    /// @dev instanceId => cumulative amount released via releaseEscrow
    mapping(bytes32 => uint128) private _totalReleased;

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

    /// @notice Initialize the parties contract
    /// @dev Grants roles and sets cross-contract references.
    /// @param admin The initial admin address
    /// @param instancesAddress Address of the ContractInstances proxy
    /// @param tokenAddress Address of the ERC-20 payment token
    function initialize(
        address admin,
        address instancesAddress,
        address tokenAddress
    ) external initializer {
        if (admin == address(0)) revert Types.ZeroAddress();
        if (instancesAddress == address(0)) revert Types.ZeroAddress();
        if (tokenAddress == address(0)) revert Types.ZeroAddress();

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);

        _instancesContract = IContractInstances(instancesAddress);
        _paymentToken = IERC20(tokenAddress);

        // Read the templates contract from instances (for bet range validation)
        // The templates contract address is derived from the instance's templateId later
    }

    /// @notice Set the ContractTemplates contract address (post-deploy linkage)
    /// @dev Access: onlyRole(DEFAULT_ADMIN_ROLE).
    /// @param templatesAddress Address of the ContractTemplates proxy
    function setTemplatesContract(address templatesAddress)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (templatesAddress == address(0)) revert Types.ZeroAddress();
        _templatesContract = IContractTemplates(templatesAddress);
    }

    // ========================================================================
    // WRITE FUNCTIONS
    // ========================================================================

    /// @notice Join a contract instance with an escrow deposit
    /// @dev Access: anyone, whenNotPaused, nonReentrant.
    ///      Follows Checks-Effects-Interactions pattern:
    ///        1. Validate instance status == Created
    ///        2. Validate not already joined
    ///        3. Validate escrow amount against template conditions (min_bet, max_bet)
    ///        4. Store party record (Effects)
    ///        5. SafeERC20.safeTransferFrom (Interactions)
    ///        6. Emit event
    /// @param instanceId FK to contract_instances (must be in Created status)
    /// @param role keccak256 of the role string (e.g., keccak256("challenger"))
    /// @param escrowAmount Amount to escrow in token smallest unit
    /// @param escrowType IXPoint or IXFreePoint
    function joinContract(
        bytes32 instanceId,
        bytes32 role,
        uint128 escrowAmount,
        Types.PointType escrowType
    ) external whenNotPaused nonReentrant {
        // --- Checks ---
        // 1. Validate instance exists and is in Created status
        Types.ContractStatus status = _instancesContract.getInstanceStatus(instanceId);
        if (status != Types.ContractStatus.Created) {
            revert Types.InvalidState(instanceId, status);
        }

        // 2. Validate caller has not already joined
        if (_hasJoined[instanceId][msg.sender]) {
            revert Types.AlreadyJoined(instanceId, msg.sender);
        }

        // 3. Validate escrow amount is non-zero
        if (escrowAmount == 0) revert Types.InvalidAmount();

        // 4. Validate template is active and escrow amount against template conditions
        bytes32 templateId = _instancesContract.getInstanceTemplateId(instanceId);
        Types.Template memory tmpl = _templatesContract.getTemplate(templateId);

        if (!tmpl.isActive) {
            revert Types.TemplateNotActive(templateId);
        }

        (uint256 minBet, uint256 maxBet,,) = abi.decode(
            tmpl.conditions,
            (uint256, uint256, uint256, uint256)
        );
        if (escrowAmount < minBet || escrowAmount > maxBet) {
            revert Types.BetOutOfRange(escrowAmount, uint128(minBet), uint128(maxBet));
        }

        // 5. Validate escrowType matches template paymentType
        if (tmpl.paymentType != Types.PaymentType.Both) {
            // If template requires IX_POINT, escrowType must be IX_POINT (0==0)
            // If template requires IX_FREE_POINT, escrowType must be IX_FREE_POINT (1==1)
            if (uint8(tmpl.paymentType) != uint8(escrowType)) {
                revert Types.PaymentTypeMismatch(uint8(tmpl.paymentType), uint8(escrowType));
            }
        }

        // --- Effects ---
        uint256 currentNonce = _nonce++;
        bytes32 partyId = keccak256(
            abi.encodePacked(instanceId, msg.sender, block.timestamp, currentNonce)
        );

        Types.Party memory party = Types.Party({
            id: partyId,
            contractId: instanceId,
            userId: msg.sender,
            escrowStatus: Types.EscrowStatus.Held,
            escrowType: escrowType,
            joinedAt: uint48(block.timestamp),
            escrowAmount: escrowAmount,
            role: role
        });

        _partyIndex[instanceId][msg.sender] = _parties[instanceId].length;
        _parties[instanceId].push(party);
        _hasJoined[instanceId][msg.sender] = true;
        _partyCount[instanceId]++;

        // --- Interactions ---
        _paymentToken.safeTransferFrom(msg.sender, address(this), escrowAmount);

        emit PartyJoined(
            instanceId,
            msg.sender,
            role,
            escrowAmount,
            escrowType,
            uint48(block.timestamp)
        );
    }

    /// @notice Release escrowed tokens to a recipient during settlement
    /// @dev Access: onlyRole(CONTRACT_ROLE), nonReentrant. Checks-Effects-Interactions.
    ///      Called by ContractSettlements to pay winner or treasury.
    /// @param instanceId The contract instance ID
    /// @param to Recipient address (winner or treasury)
    /// @param amount Amount to release
    function releaseEscrow(
        bytes32 instanceId,
        address to,
        uint128 amount
    ) external onlyRole(CONTRACT_ROLE) nonReentrant {
        // --- Checks ---
        if (to == address(0)) revert Types.ZeroAddress();
        if (amount == 0) revert Types.InvalidAmount();

        // Verify cumulative release does not exceed total escrow for this instance
        uint128 totalEscrow = this.getTotalEscrow(instanceId);
        uint128 newTotalReleased = _totalReleased[instanceId] + amount;
        if (newTotalReleased > totalEscrow) {
            revert Types.EscrowOverRelease(instanceId, totalEscrow, newTotalReleased);
        }

        // --- Effects ---
        _totalReleased[instanceId] = newTotalReleased;

        // --- Interactions ---
        _paymentToken.safeTransfer(to, amount);

        emit EscrowReleased(instanceId, to, amount);
    }

    /// @notice Refund all escrowed tokens to original depositors
    /// @dev Access: onlyRole(CONTRACT_ROLE), nonReentrant. Checks-Effects-Interactions.
    ///      Called on draw or cancellation. Each party gets their exact deposit back.
    /// @param instanceId The contract instance ID
    function refundEscrow(bytes32 instanceId)
        external
        onlyRole(CONTRACT_ROLE)
        nonReentrant
    {
        Types.Party[] storage parties = _parties[instanceId];
        uint256 length = parties.length;

        for (uint256 i; i < length; ++i) {
            Types.Party storage party = parties[i];
            if (party.escrowStatus != Types.EscrowStatus.Held) continue;

            uint128 amount = party.escrowAmount;
            address userId = party.userId;

            // --- Effects ---
            party.escrowStatus = Types.EscrowStatus.Refunded;

            // --- Interactions ---
            if (amount > 0) {
                _paymentToken.safeTransfer(userId, amount);
                emit EscrowRefunded(instanceId, userId, amount);
            }
        }
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

    /// @notice Get all parties for a contract instance
    /// @param instanceId The contract instance ID
    /// @return parties Array of Party structs
    function getParties(bytes32 instanceId)
        external
        view
        returns (Types.Party[] memory parties)
    {
        parties = _parties[instanceId];
    }

    /// @notice Get a specific party record by instance and user
    /// @param instanceId The contract instance ID
    /// @param userId The user's wallet address
    /// @return party The Party struct
    function getParty(bytes32 instanceId, address userId)
        external
        view
        returns (Types.Party memory party)
    {
        if (!_hasJoined[instanceId][userId]) {
            revert Types.NotAParty(instanceId, userId);
        }
        uint256 idx = _partyIndex[instanceId][userId];
        party = _parties[instanceId][idx];
    }

    /// @notice Get the number of parties in a contract
    /// @param instanceId The contract instance ID
    /// @return count The party count
    function getPartyCount(bytes32 instanceId) external view returns (uint8 count) {
        count = _partyCount[instanceId];
    }

    /// @notice Get the sum of all escrow amounts for a contract
    /// @param instanceId The contract instance ID
    /// @return total The total escrowed amount
    function getTotalEscrow(bytes32 instanceId) external view returns (uint128 total) {
        Types.Party[] storage parties = _parties[instanceId];
        uint256 length = parties.length;
        for (uint256 i; i < length; ++i) {
            total += parties[i].escrowAmount;
        }
    }

    /// @notice Check if a user has already joined a contract
    /// @param instanceId The contract instance ID
    /// @param userId The user's wallet address
    /// @return joined True if the user is already a party
    function hasJoined(bytes32 instanceId, address userId)
        external
        view
        returns (bool joined)
    {
        joined = _hasJoined[instanceId][userId];
    }
}
