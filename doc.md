# Metaverse Contract Management System — Requirements Specification

# Metaverse Contract Management System — Requirements Specification

| Item | Details |
| --- | --- |
| Document ID | IX-REQ-CONTRACT-001 |
| Version | 0.1.0 (Draft) |
| Created | 2026-03-18 |
| Author | Akio Iwaki (PO) |
| Target Project | IX |
| Status | Pending Review |

---

## 1. Overview

### 1.1 Background

Within the IX Metaverse, various "consent-based interactions" occur between users and between users and the platform. This system unifies all such interactions under a single abstraction — "contracts" — and provides a transparent management framework.

### 1.2 Objectives

- Centrally manage all contract events within the metaverse
- Publicly disclose the full history of contract creation, execution, and settlement
- Provide a flexible mechanism to control whether each contract is recorded on-chain or off-chain
- Build the foundation for full blockchain management on MegaETH in the future

### 1.3 Contract Examples

| Contract Type | Description | Parties |
| --- | --- | --- |
| RPS (Rock-Paper-Scissors) | User vs user match with point transfer based on outcome | User vs User |
| Work Reward | Payment upon task completion | Worker vs Client |
| Tournament Entry | Entry fee collection and prize distribution | Participant vs Organizer |
| Other | Any contract template defined by administrators | Variable |

---

## 2. Phase Plan

### Phase 0 (Initial Release)

- **Payment method**: IX Points / IX Free Points (already implemented)
- **Management**: Off-chain (Supabase DB)
- **Transparency**: Full contract history including point transfer records made publicly available
- **Goal**: UX validation, rule refinement, user acquisition

### Phase 1

- **Payment method**: USDT on MegaETH
- **Management**: Smart contracts
- **Goal**: On-chain migration, real-currency contract execution

### Phase 2

- **Payment method**: IX Economic Token (ERC-20)
- **Management**: Smart contracts
- **Goal**: Launch of the IX token economy

### Phase 3

- **Payment method**: Economic Token + Governance Token integration
- **Management**: DAO-based governance
- **Goal**: Contract template proposals and approvals by Governance Token holders

---

## 3. Phase 0 — Detailed Requirements

### 3.1 Functional Requirements

### 3.1.1 Contract Template Management (Admin Functions)

| Function | Description |
| --- | --- |
| Template creation | Define contract type, conditions, and reward rules |
| Template activation/deactivation | Control which contracts are available in the metaverse |
| Metaverse event binding | Associate a template with a specific metaverse event |
| **Blockchain recording setting** | Configure on-chain recording policy per template (see 3.1.6) |

**Only administrators can create and manage contract templates.**

### 3.1.2 Contract Lifecycle

```
Created → Active → Completed → Settled
                       ↓
                   Disputed → Resolved → Settled
```

| Status | Description |
| --- | --- |
| Created | Contract instance generated from a template |
| Active | All parties have joined; contract is in progress |
| Completed | Event result determined (awaiting consent) |
| Disputed | One party has raised an objection to the result |
| Resolved | Dispute has been resolved |
| Settled | Settlement complete (points transferred) |

### 3.1.3 Contract Execution Flow

1. An event occurs in the metaverse (e.g., RPS match starts)
2. A contract instance is generated from the bound template
3. Parties escrow (deposit) their points
4. Event is executed
5. Result is determined → both parties consent
6. Points are transferred from escrow to the winner/recipient
7. Fees are sent to the Treasury (platform)

### 3.1.4 Settlement (IX Points / IX Free Points)

| Item | IX Points | IX Free Points |
| --- | --- | --- |
| Acquisition | Purchase / Rewards | Free distribution, login bonuses, etc. |
| Usage | Settlement of production contracts | Practice / low-risk contracts |
| Convertibility | Yes (future token conversion) | No |

### 3.1.5 Public Ledger (Open Transparency)

Information available for public viewing:

| Public Field | Description |
| --- | --- |
| Contract ID | Unique identifier |
| Contract type | RPS, work reward, tournament, etc. |
| Parties | User IDs (anonymization options under consideration) |
| Point transfer amount | Amount of IX Points / Free Points transferred |
| Timestamp | Timestamp of each status change |
| Result / Status | Current status and final outcome |

### 3.1.6 Blockchain Recording Settings (On-chain / Off-chain Selection)

Whether a contract transaction is recorded on the blockchain (MegaETH) is managed through a **two-level control system**.

**Level 1: Admin template configuration**

When creating a contract template, the administrator sets the blockchain recording policy to one of the following:

| Setting | Description | Example Use Case |
| --- | --- | --- |
| `required` | Always recorded on-chain. Users cannot opt out | High-value contracts, tournaments, work rewards |
| `optional` | Users can choose whether to record on-chain when joining | Mid-tier RPS matches, etc. |
| `off` | Not recorded on-chain. Off-chain (DB) only | Small / casual RPS, Free Point contracts |

**Level 2: User selection (`optional` only)**

When a template is set to `optional`, users can choose at the time of joining:

- **On-chain recording enabled** → Transaction is written to MegaETH upon settlement
- **On-chain recording disabled** → Recorded only in the DB public ledger

> **Note**: Selecting on-chain recording may incur gas fee costs (e.g., deducted from IX Points). The cost allocation rules are TBD.
> 

**Admin Dashboard UI Requirements**

- Include a "Blockchain Recording" section on the template create/edit screen
- Provide a 3-option radio button or select box: `required` / `optional` / `off`
- When `optional` is selected, display a customizable text field for the user-facing description
- Setting changes do not affect existing contract instances (applied to new contracts only)

**Metaverse UI Requirements (User-facing)**

- When the template is `optional`, display a toggle or checkbox on the contract participation screen
    - Example: "Record this contract on the blockchain"
- When `required`, display a notice that on-chain recording is mandatory (no user choice)
- When `off`, no display

---

### 3.2 Data Model (Designed for On-chain Migration)

> **Important**: The Phase 0 DB schema must be designed to map 1:1 to the Phase 1 smart contract state.
> 

### contract_templates

| Column | Type | Description |
| --- | --- | --- |
| id | UUID | Template ID |
| name | VARCHAR | Template name |
| type | ENUM | Contract type (rps, work_reward, tournament, custom) |
| conditions | JSONB | Contract condition definitions |
| reward_rules | JSONB | Reward calculation rules |
| payment_type | ENUM | ix_point, ix_free_point, both |
| fee_rate | DECIMAL | Fee rate (%) |
| chain_record_policy | ENUM | required, optional, off (blockchain recording policy) |
| is_active | BOOLEAN | Active / Inactive |
| metaverse_event_id | VARCHAR | Bound metaverse event ID |
| created_by | UUID | Admin user ID who created the template |
| created_at | TIMESTAMP | Creation timestamp |
| updated_at | TIMESTAMP | Last update timestamp |

### contract_instances

| Column | Type | Description |
| --- | --- | --- |
| id | UUID | Contract instance ID |
| template_id | UUID | FK → contract_templates |
| status | ENUM | created, active, completed, disputed, resolved, settled |
| chain_record | BOOLEAN | Whether to record on-chain (determined by template policy + user selection) |
| tx_hash | VARCHAR | On-chain transaction hash (NULLable) |
| created_at | TIMESTAMP | Creation timestamp |
| settled_at | TIMESTAMP | Settlement completion timestamp |

### contract_parties

| Column | Type | Description |
| --- | --- | --- |
| id | UUID | PK |
| contract_id | UUID | FK → contract_instances |
| user_id | UUID | Party's user ID |
| role | VARCHAR | Role (challenger, opponent, worker, client, participant, etc.) |
| escrow_amount | DECIMAL | Escrowed point amount |
| escrow_type | ENUM | ix_point, ix_free_point |
| joined_at | TIMESTAMP | Join timestamp |

### contract_results

| Column | Type | Description |
| --- | --- | --- |
| id | UUID | PK |
| contract_id | UUID | FK → contract_instances |
| result_data | JSONB | Result data (winner, score, etc.) |
| reported_by | VARCHAR | Result source (system, user) |
| reported_at | TIMESTAMP | Report timestamp |

### contract_settlements

| Column | Type | Description |
| --- | --- | --- |
| id | UUID | PK |
| contract_id | UUID | FK → contract_instances |
| from_user_id | UUID | Sender user |
| to_user_id | UUID | Recipient user |
| amount | DECIMAL | Point transfer amount |
| point_type | ENUM | ix_point, ix_free_point |
| fee_amount | DECIMAL | Fee amount |
| settled_at | TIMESTAMP | Settlement timestamp |
| tx_hash | VARCHAR | Phase 1+: On-chain transaction hash |

### contract_consents

| Column | Type | Description |
| --- | --- | --- |
| id | UUID | PK |
| contract_id | UUID | FK → contract_instances |
| user_id | UUID | Consenting user |
| consented | BOOLEAN | Consent / Objection |
| consented_at | TIMESTAMP | Consent timestamp |
| signature | VARCHAR | Phase 1+: Wallet signature |

### 3.3 Non-functional Requirements

| Item | Requirement |
| --- | --- |
| Availability | Real-time processing required due to metaverse event integration |
| Data integrity | Point transfers must be handled with transactional consistency |
| Scalability | Architecture must support backend replacement for Phase 1 (MegaETH) migration |
| Security | Escrow operations restricted to admin privileges or automated system processes |
| Auditability | All point transfers must have timestamps and full traceability |

---

## 4. Phase 1 Migration Strategy (Reference)

The following mapping applies when migrating from Phase 0 to Phase 1:

| Phase 0 (Off-chain) | Phase 1 (MegaETH) |
| --- | --- |
| contract_templates table | ContractRegistry contract |
| contract_instances table | ContractInstance contract (per-deploy or Factory pattern) |
| contract_settlements table | Escrow + automated transfer logic |
| Public ledger API | On-chain event logs (verifiable by anyone) |
| IX Points | ERC-20 Economic Token |
| Admin privileges | Owner / Admin roles (within contract) |

---

## 5. Result Determination (Including Dispute Resolution)

### Normal Flow

1. Metaverse server reports the result to the system
2. Both parties are notified of the result
3. If no objection is raised within a set period (TBD), the result is automatically finalized
4. Settlement is executed

### Dispute Flow

1. A party raises an objection to the result (Status: Disputed)
2. Administrator reviews the evidence and makes a ruling
3. Settlement is executed based on the ruling (Status: Resolved → Settled)

---

## 6. Open Items (TBD)

| Item | Details |
| --- | --- |
| Fee rates | Fee rate configuration per contract type |
| Objection period | Time window from result report to automatic finalization |
| Anonymization level | How much user information to display in the public ledger |
| Free Point restrictions | Limits on contracts accessible with Free Points |
| On-chain recording cost | Cost allocation rules when users select on-chain recording under `optional` |
| Contract templates beyond RPS | Detailed condition definitions for work rewards, tournaments |
| Governance Token specification | Token design for Phase 3 |
| Economic Token specification | Token design for Phase 2 |

---

## 7. Related Systems

| System | Relationship |
| --- | --- |
| IX-Government-platform | Admin dashboard, user management, point system (existing) |
| IX Metaverse | Event source, contract execution environment |
| MegaETH | Blockchain infrastructure from Phase 1 onward |

---

## Appendix: Glossary