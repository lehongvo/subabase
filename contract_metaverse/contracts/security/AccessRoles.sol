// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title AccessRoles -- Centralized role definitions for IX Metaverse Contract System
/// @notice Defines all role constants used across the contract system for access control.
/// @dev All roles are bytes32 hashes used with OpenZeppelin AccessControlUpgradeable.
///
/// Role Assignment Matrix:
/// +-----------------+-------------------------------------------------------------------+
/// | Role            | Assigned To             | Permissions                              |
/// +-----------------+-------------------------+------------------------------------------+
/// | DEFAULT_ADMIN   | Deployer / ProxyAdmin   | Grant/revoke roles, set contract refs,   |
/// |                 |                         | pause/unpause, upgrade proxies           |
/// +-----------------+-------------------------+------------------------------------------+
/// | ADMIN_ROLE      | Platform administrators | Template CRUD, dispute resolution,       |
/// |                 |                         | escrow refunds, pause/unpause            |
/// +-----------------+-------------------------+------------------------------------------+
/// | SERVER_ROLE     | Metaverse game server   | Create/activate/complete instances,      |
/// |                 |                         | join parties, submit results/consents    |
/// +-----------------+-------------------------+------------------------------------------+
/// | SETTLER_ROLE    | Settlement automation   | Execute settlements, release escrow,     |
/// |                 |                         | settle instance status                   |
/// +-----------------+-------------------------+------------------------------------------+
/// | ORACLE_ROLE     | Result oracle service   | Report game results                      |
/// +-----------------+-------------------------+------------------------------------------+
///
/// Access Control by Contract Function:
///   ContractTemplates: CRUD -> ADMIN_ROLE; read -> Anyone
///   ContractInstances: create/activate/complete -> SERVER_ROLE;
///                      dispute -> SERVER_ROLE | ADMIN_ROLE;
///                      resolve -> ADMIN_ROLE;
///                      settle (status) -> SETTLER_ROLE
///   ContractParties:   join -> SERVER_ROLE; refund -> ADMIN_ROLE; release -> SETTLER_ROLE
///   ContractResults:   report -> SERVER_ROLE | ORACLE_ROLE; override -> ADMIN_ROLE
///   ContractConsents:  submit/autoConsent -> SERVER_ROLE
///   ContractSettlements: settle -> SETTLER_ROLE; refund -> ADMIN_ROLE | SETTLER_ROLE
///   Cross-contract refs: DEFAULT_ADMIN_ROLE
///   All view functions: Anyone
library AccessRoles {
    /// @notice Administrator role for template management, dispute resolution, and emergency actions
    bytes32 constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Metaverse game server role for instance lifecycle and party management
    bytes32 constant SERVER_ROLE = keccak256("SERVER_ROLE");

    /// @notice Settlement automation role for executing settlements and releasing escrow
    bytes32 constant SETTLER_ROLE = keccak256("SETTLER_ROLE");

    /// @notice Oracle role for reporting game results from external sources
    bytes32 constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
}
