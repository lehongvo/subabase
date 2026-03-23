// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title Types — Shared types for IX Metaverse Contract System
/// @notice All enums, structs, constants, and custom errors used across the system.
/// @dev 1:1 mapping to Phase 0 Supabase DB schema ENUMs and tables.
library Types {
    // ========================================================================
    // ENUMS (1:1 to DB ENUMs)
    // ========================================================================

    /// @notice Maps to DB: contract_type (rps, work_reward, tournament, custom)
    enum ContractType {
        RPS,          // 0
        WorkReward,   // 1
        Tournament,   // 2
        Custom        // 3
    }

    /// @notice Maps to DB: contract_status
    enum ContractStatus {
        Created,   // 0
        Active,    // 1
        Completed, // 2
        Disputed,  // 3
        Resolved,  // 4
        Settled    // 5
    }

    /// @notice Maps to DB: payment_type (ix_point, ix_free_point, both)
    enum PaymentType {
        IXPoint,     // 0
        IXFreePoint, // 1
        Both         // 2
    }

    /// @notice Maps to DB: point_type (ix_point, ix_free_point)
    enum PointType {
        IXPoint,     // 0
        IXFreePoint  // 1
    }

    /// @notice Maps to DB: chain_record_policy (required, optional, off)
    enum ChainRecordPolicy {
        Required, // 0
        Optional, // 1
        Off       // 2
    }

    /// @notice Maps to DB: result_source (system, user)
    enum ResultSource {
        System, // 0
        User    // 1
    }

    /// @notice Maps to DB: settlement_type (reward, fee, refund)
    enum SettlementType {
        Reward, // 0
        Fee,    // 1
        Refund  // 2
    }

    /// @notice Escrow status tracking per party
    enum EscrowStatus {
        Held,     // 0
        Released, // 1
        Refunded  // 2
    }

    // ========================================================================
    // STRUCTS — gas-packed, 1:1 to DB tables
    // ========================================================================

    /// @notice Maps to DB: contract_templates
    /// @dev Packing: slot1 = contractType(1)+paymentType(1)+chainRecordPolicy(1)+isActive(1)+feeRateBps(2)+createdBy(20) = 26 bytes
    ///      slot6 = createdAt(6)+updatedAt(6) = 12 bytes
    struct Template {
        bytes32           id;                // slot 0 — 32 bytes
        ContractType      contractType;      // slot 1 — packed start
        PaymentType       paymentType;       //
        ChainRecordPolicy chainRecordPolicy; //
        bool              isActive;          //
        uint16            feeRateBps;        // basis points, max 10000
        address           createdBy;         // 20 bytes — slot 1 total 26 bytes
        bytes32           metaverseEventId;  // slot 2 — 32 bytes
        bytes             conditions;        // slot 3 — dynamic (ABI-encoded)
        bytes             rewardRules;       // slot 4 — dynamic (ABI-encoded)
        string            name;              // slot 5 — dynamic
        uint48            createdAt;         // slot 6 — packed
        uint48            updatedAt;         // slot 6 — 12 bytes total
    }

    /// @notice Maps to DB: contract_instances
    /// @dev Packing: slot2 = status(1)+chainRecord(1)+createdAt(6)+settledAt(6)+activatedAt(6)+completedAt(6) = 26 bytes
    struct Instance {
        bytes32        id;          // slot 0
        bytes32        templateId;  // slot 1
        ContractStatus status;      // slot 2 — packed start
        bool           chainRecord; //
        uint48         createdAt;   //
        uint48         settledAt;   //
        uint48         activatedAt; //
        uint48         completedAt; // slot 2 total 26 bytes
        bytes          metadata;    // slot 3 — dynamic
        bytes32        txHash;      // slot 4
    }

    /// @notice Maps to DB: contract_parties
    /// @dev Packing: slot2 = userId(20)+escrowStatus(1)+escrowType(1)+joinedAt(6) = 28 bytes
    struct Party {
        bytes32      id;           // slot 0
        bytes32      contractId;   // slot 1
        address      userId;       // slot 2 — packed start
        EscrowStatus escrowStatus; //
        PointType    escrowType;   //
        uint48       joinedAt;     // slot 2 total 28 bytes
        uint128      escrowAmount; // slot 3
        bytes32      role;         // slot 4 — keccak256 of role string
    }

    /// @notice Maps to DB: contract_results
    /// @dev Packing: slot2 = reportedBy(1)+isFinal(1)+reportedAt(6) = 8 bytes
    struct Result {
        bytes32      id;         // slot 0
        bytes32      contractId; // slot 1
        ResultSource reportedBy; // slot 2 — packed start
        bool         isFinal;    //
        uint48       reportedAt; // slot 2 total 8 bytes
        bytes        resultData; // slot 3 — dynamic (ABI-encoded)
    }

    /// @notice Maps to DB: contract_consents
    /// @dev Packing: slot2 = userId(20)+consented(1)+consentedAt(6) = 27 bytes
    struct Consent {
        bytes32 id;         // slot 0
        bytes32 contractId; // slot 1
        address userId;     // slot 2 — packed start
        bool    consented;  //
        uint48  consentedAt;// slot 2 total 27 bytes
        bytes   signature;  // slot 3 — dynamic (EIP-712 wallet signature)
        string  reason;     // slot 4 — dynamic (dispute reason)
    }

    /// @notice Maps to DB: contract_settlements
    /// @dev Packing: slot2 = fromUserId(20)+settlementType(1)+pointType(1)+settledAt(6) = 28 bytes
    ///      slot4 = amount(16)+feeAmount(16) = 32 bytes
    struct Settlement {
        bytes32        id;             // slot 0
        bytes32        contractId;     // slot 1
        address        fromUserId;     // slot 2 — packed start
        SettlementType settlementType; //
        PointType      pointType;      //
        uint48         settledAt;      // slot 2 total 28 bytes
        address        toUserId;       // slot 3
        uint128        amount;         // slot 4 — packed start
        uint128        feeAmount;      // slot 4 total 32 bytes
        bytes32        txHash;         // slot 5
    }

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    /// @notice System escrow address (maps to Phase 0 UUID 00..00)
    address constant ESCROW_SYSTEM = address(0);

    /// @notice Treasury address placeholder (maps to Phase 0 UUID 00..01)
    address constant TREASURY = address(1);

    // ========================================================================
    // CUSTOM ERRORS
    // ========================================================================

    // --- Authorization ---
    error Unauthorized();
    error ZeroAddress();
    error InvalidContractReference(string contractName);
    error ContractPaused();

    // --- Template Errors ---
    error TemplateNotActive(bytes32 templateId);
    error TemplateNotFound(bytes32 templateId);
    error TemplateNameExists(string name);
    error TemplateAlreadyExists(bytes32 templateId);
    error InvalidFeeRate(uint16 feeRateBps);

    // --- Instance / State Errors ---
    error InvalidState(bytes32 id, ContractStatus current);
    error InvalidTransition(bytes32 id, ContractStatus from, ContractStatus to);
    error ContractNotFound(bytes32 instanceId);
    error InstanceAlreadyExists(bytes32 instanceId);
    error InstanceAlreadySettled(bytes32 instanceId);

    // --- Party / Escrow Errors ---
    error InsufficientBalance(uint128 required, uint128 available);
    error InvalidAmount();
    error BetOutOfRange(uint128 amount, uint128 min, uint128 max);
    error AlreadyJoined(bytes32 instanceId, address userId);
    error AlreadySettled(bytes32 instanceId);
    error NotAParty(bytes32 instanceId, address userId);
    error MaxPartiesReached(bytes32 instanceId, uint8 maxParties);
    error EscrowNotHeld(bytes32 instanceId, address userId);

    // --- Consent Errors ---
    error AlreadyConsented(bytes32 instanceId, address userId);
    error ConsentNotComplete(bytes32 instanceId);

    // --- Result Errors ---
    error ResultAlreadySubmitted(bytes32 instanceId);
    error ResultNotFound(bytes32 instanceId);
    error InvalidResultData();

    // --- Settlement Errors ---
    error SettlementAlreadyDone(bytes32 instanceId);
    error InvalidTreasuryAddress();

    // --- Payment Type Errors ---
    error PaymentTypeMismatch(uint8 expected, uint8 actual);

    // --- Escrow Release Errors ---
    error EscrowOverRelease(bytes32 instanceId, uint128 totalEscrow, uint128 totalReleased);
}
