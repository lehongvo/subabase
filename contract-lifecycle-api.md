# IX Metaverse — Contract Lifecycle API Documentation

**Version:** Phase 0 (Off-chain, Supabase)
**Last updated:** 2026-03-22
**Status:** Production (Supabase Cloud)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Environment & Base URLs](#2-environment--base-urls)
3. [Authentication](#3-authentication)
4. [Data Models](#4-data-models)
5. [System Constants](#5-system-constants)
6. [REST Endpoints — Tables](#6-rest-endpoints--tables)
7. [RPC Functions](#7-rpc-functions)
8. [Complete Lifecycle — RPS Example (A vs B)](#8-complete-lifecycle--rps-example-a-vs-b)
9. [Dispute Flow](#9-dispute-flow)
10. [Draw Flow](#10-draw-flow)
11. [Realtime WebSocket Subscriptions](#11-realtime-websocket-subscriptions)
12. [Filtering, Sorting & Pagination](#12-filtering-sorting--pagination)
13. [Error Handling](#13-error-handling)
14. [FAQ for Frontend Engineers](#14-faq-for-frontend-engineers)

---

## 1. Overview

The IX Metaverse Contract Management System handles **consent-based interactions** (contracts) between users. A contract represents any interaction where two or more parties commit points, play an activity, and receive a settlement based on the result.

### Phase 0 — What this is

- **Off-chain only** — all data stored in PostgreSQL (Supabase)
- **No blockchain** — `tx_hash` fields exist but are always `null` in Phase 0
- **PostgREST** — REST API auto-generated from the database schema
- **Business logic** — runs inside PostgreSQL functions (SECURITY DEFINER)

### Phase 1 preview (future)

Phase 0 schema maps 1:1 to MegaETH smart contracts. The same API call flow will work against smart contracts in Phase 1 without changing the frontend.

### Supported contract types

| Type | Description |
|------|-------------|
| `rps` | Rock-Paper-Scissors — 2 players, winner takes all minus fee |
| `work_reward` | Work Reward — worker completes task, client approves/pays |
| `tournament` | Tournament — multi-player ranked payout |
| `custom` | Custom — admin-defined rules |

### Contract lifecycle

```
Created → Active → Completed → Settled
                      ↓
                  Disputed → Resolved → Settled
```

| Status | Meaning |
|--------|---------|
| `created` | Contract exists, waiting for all parties to join and escrow |
| `active` | All parties joined, match/activity in progress |
| `completed` | Result determined, waiting for consent |
| `disputed` | At least one party disputed the result |
| `resolved` | Admin reviewed and resolved the dispute |
| `settled` | Points distributed — **final state, immutable** |

---

## 2. Environment & Base URLs

### Production (Supabase Cloud)

```
REST API:    https://YOUR_PROJECT_REF.supabase.co/rest/v1
Auth API:    https://YOUR_PROJECT_REF.supabase.co/auth/v1
Realtime:   wss://YOUR_PROJECT_REF.supabase.co/realtime/v1
```

### Local Development (Docker)

```
REST API:    http://localhost:8000/rest/v1
Auth API:    http://localhost:8000/auth/v1
Realtime:   ws://localhost:8000/realtime/v1
Swagger UI: http://localhost:8888
API Docs:   http://localhost:8889
Studio:     http://localhost:8000  (admin: supabase / see .env)
```

---

## 3. Authentication

### Required headers

**Every API request must include both headers:**

```http
apikey: <API_KEY>
Authorization: Bearer <API_KEY>
Content-Type: application/json
```

### API Keys

| Key Type | Value | Use Case |
|----------|-------|----------|
| `anon` (public) | `<YOUR_SUPABASE_ANON_KEY>` | Client-side calls, respects RLS |
| `service_role` | (in `.env`) | Server-side admin calls, bypasses RLS |

> **Important:** In Phase 0, always use the `anon` key from the client. The `service_role` key is only for server-to-server calls (game server, admin backend).

### User Authentication (Supabase Auth)

Users authenticate via email/password. After login, the JWT token is used instead of the API key in the `Authorization` header — the `apikey` header still uses the anon key.

**Register new user:**
```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/auth/v1/signup' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "email": "player@example.com",
    "password": "securepassword"
  }'
```

**Login:**
```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/auth/v1/token?grant_type=password' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "email": "player@example.com",
    "password": "securepassword"
  }'
```

**Login response:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR...",
  "token_type": "bearer",
  "expires_in": 3600,
  "refresh_token": "...",
  "user": {
    "id": "USER_UUID",
    "email": "player@example.com"
  }
}
```

After login, use `access_token` as the `Authorization: Bearer` value.

---

## 4. Data Models

### 4.1 ENUM Types

#### `contract_type`
```
rps | work_reward | tournament | custom
```

#### `contract_status`
```
created | active | completed | disputed | resolved | settled
```

#### `payment_type`
```
ix_point | ix_free_point | both
```

#### `point_type`
```
ix_point | ix_free_point
```

#### `chain_record_policy`
```
required | optional | off
```
- `required` → always recorded on-chain (Phase 1)
- `optional` → user chooses at join time
- `off` → never recorded on-chain

#### `result_source`
```
system | user
```

---

### 4.2 Table: `contract_templates`

Admin-managed templates. Each template defines the rules, fee, and behavior for a type of contract.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `name` | VARCHAR(255) | Template display name |
| `description` | TEXT | Admin description |
| `type` | contract_type | Contract type |
| `conditions` | JSONB | Contract rules (min_bet, max_bet, rounds, etc.) |
| `reward_rules` | JSONB | Payout rules (winner_pct, draw_refund, etc.) |
| `payment_type` | payment_type | Accepted point type |
| `fee_rate` | DECIMAL(5,2) | Platform fee %, e.g. `5.00` = 5% |
| `chain_record_policy` | chain_record_policy | Blockchain recording rule |
| `chain_record_description` | TEXT | User-facing text for optional policy |
| `is_active` | BOOLEAN | Only active templates can be used |
| `metaverse_event_id` | VARCHAR(255) | Metaverse event binding |
| `created_by` | UUID | Admin user ID |
| `created_at` | TIMESTAMPTZ | - |
| `updated_at` | TIMESTAMPTZ | Auto-updated |

**RLS:** Anyone can read active templates (`is_active = true`). Only admins can create/edit/delete.

**Example `conditions` for RPS:**
```json
{ "min_bet": 10, "max_bet": 1000, "rounds": 1, "timeout_seconds": 15 }
```

**Example `reward_rules` for RPS:**
```json
{ "winner_pct": 95, "draw_refund": true }
```

---

### 4.3 Table: `contract_instances`

One instance per actual contract played. Created from a template.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `template_id` | UUID | FK → contract_templates |
| `status` | contract_status | Current lifecycle status |
| `chain_record` | BOOLEAN | Whether to record on-chain at settlement |
| `tx_hash` | VARCHAR(66) | MegaETH tx hash — always `null` in Phase 0 |
| `metadata` | JSONB | Game room ID, match ID, etc. |
| `created_at` | TIMESTAMPTZ | - |
| `activated_at` | TIMESTAMPTZ | Set when status → active |
| `completed_at` | TIMESTAMPTZ | Set when status → completed |
| `settled_at` | TIMESTAMPTZ | Set when status → settled |

**RLS:** Public read (transparency). Admin full access. Status transitions enforced by DB trigger.

**Valid status transitions:**
```
created → active
active → completed
completed → settled
completed → disputed
disputed → resolved
resolved → settled
```
Any other transition returns HTTP 400 / SQLSTATE error.

---

### 4.4 Table: `contract_parties`

Each row = one user participating in one contract, with their escrow info.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `contract_id` | UUID | FK → contract_instances |
| `user_id` | UUID | The participating user |
| `role` | VARCHAR(50) | challenger / opponent / worker / client / participant / organizer |
| `escrow_amount` | DECIMAL(18,2) | Points locked in escrow |
| `escrow_type` | point_type | Which point type |
| `escrow_status` | VARCHAR(20) | `held` → `released` (paid winner) or `refunded` (draw/dispute) |
| `chain_record_choice` | BOOLEAN | User's on-chain choice (only when template policy = optional) |
| `joined_at` | TIMESTAMPTZ | - |

**RLS:** Users can read their own party records. Public read (for ledger).

---

### 4.5 Table: `contract_results`

Result of the contract. Reported by game server (`system`) or user.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `contract_id` | UUID | FK → contract_instances |
| `result_data` | JSONB | Flexible result (see examples below) |
| `reported_by` | result_source | `system` or `user` |
| `reporter_id` | UUID | User ID if `reported_by = user`, else null |
| `is_final` | BOOLEAN | Only `is_final = true` result is used for settlement |
| `reported_at` | TIMESTAMPTZ | - |
| `finalized_at` | TIMESTAMPTZ | When result was finalized |

**RLS:** Public read. Admin full access. System/server writes with service_role key.

**Example `result_data` for RPS:**
```json
{
  "winner_id": "USER_B_ID",
  "winner_move": "rock",
  "loser_move": "scissors",
  "rounds_played": 1,
  "score": "1-0",
  "is_draw": false
}
```

**Example `result_data` for draw:**
```json
{
  "is_draw": true,
  "rounds_played": 3,
  "score": "1-1-1"
}
```

---

### 4.6 Table: `contract_settlements`

Point transfer records. Created by `settle_contract()` — do not insert manually.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `contract_id` | UUID | FK → contract_instances |
| `from_user_id` | UUID | Sender (Escrow system UUID or user) |
| `to_user_id` | UUID | Recipient (user or Treasury UUID) |
| `amount` | DECIMAL(18,2) | Points transferred |
| `point_type` | point_type | Which point type |
| `settlement_type` | VARCHAR(20) | `reward` / `fee` / `refund` |
| `fee_amount` | DECIMAL(18,2) | Platform fee deducted |
| `tx_hash` | VARCHAR(66) | Always `null` in Phase 0 |
| `settled_at` | TIMESTAMPTZ | - |

**RLS:** Public read (transparency).

---

### 4.7 Table: `contract_consents`

Each party's consent (agree or dispute) after result is reported.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `contract_id` | UUID | FK → contract_instances |
| `user_id` | UUID | The user giving consent |
| `consented` | BOOLEAN | `true` = agree, `false` = dispute |
| `reason` | TEXT | Required if `consented = false` |
| `signature` | VARCHAR(132) | EIP-712 signature — always `null` in Phase 0 |
| `consented_at` | TIMESTAMPTZ | - |

**RLS:** Users can insert consent for contracts they're a party of. Public read.

---

### 4.8 Table: `point_balances`

Current point balance per user per point type.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `user_id` | UUID | The user |
| `point_type` | point_type | `ix_point` or `ix_free_point` |
| `balance` | DECIMAL(18,2) | Current balance (never negative) |
| `updated_at` | TIMESTAMPTZ | Auto-updated |

**RLS:** Users can read their own balance. Admin full access.

---

### 4.9 View: `public_ledger`

Aggregated read-only view. Combines contract + parties + result + settlements.

| Field | Type | Description |
|-------|------|-------------|
| `contract_id` | UUID | - |
| `contract_type_name` | VARCHAR | Template name |
| `contract_type` | contract_type | Template type enum |
| `contract_status` | contract_status | Current status |
| `is_on_chain` | BOOLEAN | chain_record value |
| `created_at` | TIMESTAMPTZ | - |
| `activated_at` | TIMESTAMPTZ | - |
| `completed_at` | TIMESTAMPTZ | - |
| `settled_at` | TIMESTAMPTZ | - |
| `tx_hash` | VARCHAR(66) | null in Phase 0 |
| `parties` | JSONB array | All parties with escrow info |
| `result` | JSONB | Final result (is_final = true) |
| `settlements` | JSONB array | All settlement transfers |

**RLS:** Public read — anyone can query (anonymous transparency).

---

## 5. System Constants

These UUIDs appear in `from_user_id` and `to_user_id` fields in settlements. They are not real users.

| UUID | Name | Meaning |
|------|------|---------|
| `00000000-0000-0000-0000-000000000000` | Escrow System | Source of all settlement payouts |
| `00000000-0000-0000-0000-000000000001` | Treasury | Receives platform fees |

**Point types:**

| Type | Description |
|------|-------------|
| `ix_point` | Real IX Points — has monetary value, can be converted |
| `ix_free_point` | Free Points — bonus/promotional, cannot be converted |

---

## 6. REST Endpoints — Tables

Base URL: `https://YOUR_PROJECT_REF.supabase.co/rest/v1`

Headers for all requests:
```http
apikey: <YOUR_SUPABASE_ANON_KEY>
Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>
Content-Type: application/json
```

---

### 6.1 `GET /contract_templates`

List available contract templates.

**List all active templates:**
```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_templates?is_active=eq.true' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```

**Get RPS templates only:**
```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_templates?type=eq.rps&is_active=eq.true&select=id,name,fee_rate,conditions,reward_rules,chain_record_policy' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```

**Get one template by ID:**
```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_templates?id=eq.20000000-0000-0000-0000-000000000001' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```

**Response:**
```json
[
  {
    "id": "20000000-0000-0000-0000-000000000001",
    "name": "RPS Casual Lobby 1",
    "type": "rps",
    "fee_rate": 3.00,
    "payment_type": "ix_point",
    "chain_record_policy": "off",
    "is_active": true,
    "conditions": { "min_bet": 10, "max_bet": 100, "rounds": 1, "timeout_seconds": 15 },
    "reward_rules": { "winner_pct": 97, "draw_refund": true }
  }
]
```

---

### 6.2 `GET /contract_instances`

**Get contract by ID:**
```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_instances?id=eq.CONTRACT_ID' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```

**List active contracts:**
```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_instances?status=eq.active&order=created_at.desc&limit=20' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```

**Response:**
```json
[
  {
    "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    "template_id": "20000000-0000-0000-0000-000000000001",
    "status": "active",
    "chain_record": false,
    "tx_hash": null,
    "metadata": {},
    "created_at": "2026-03-22T10:00:00Z",
    "activated_at": "2026-03-22T10:01:00Z",
    "completed_at": null,
    "settled_at": null
  }
]
```

**PATCH status (server-side, service_role key required):**
```bash
curl -X PATCH 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_instances?id=eq.CONTRACT_ID' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{"status": "completed"}'
```

---

### 6.3 `GET /contract_parties`

**Get all parties of a contract:**
```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_parties?contract_id=eq.CONTRACT_ID&select=user_id,role,escrow_amount,escrow_type,escrow_status' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```

**Get all contracts for a user:**
```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_parties?user_id=eq.USER_ID&select=contract_id,role,escrow_amount,joined_at' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```

**Response:**
```json
[
  {
    "user_id": "USER_A_ID",
    "role": "challenger",
    "escrow_amount": 100.00,
    "escrow_type": "ix_point",
    "escrow_status": "held"
  },
  {
    "user_id": "USER_B_ID",
    "role": "opponent",
    "escrow_amount": 100.00,
    "escrow_type": "ix_point",
    "escrow_status": "held"
  }
]
```

---

### 6.4 `POST /contract_results`

Report a contract result (game server call, use service_role key).

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_results' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -H 'Prefer: return=representation' \
  -d '{
    "contract_id": "CONTRACT_ID",
    "result_data": {
      "winner_id": "USER_B_ID",
      "winner_move": "rock",
      "loser_move": "scissors",
      "rounds_played": 1,
      "score": "1-0",
      "is_draw": false
    },
    "reported_by": "system",
    "is_final": true
  }'
```

**Response (HTTP 201):**
```json
[
  {
    "id": "result-uuid-here",
    "contract_id": "CONTRACT_ID",
    "result_data": { "winner_id": "USER_B_ID", ... },
    "reported_by": "system",
    "reporter_id": null,
    "is_final": true,
    "reported_at": "2026-03-22T10:05:00Z",
    "finalized_at": null
  }
]
```

**Get result for a contract:**
```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_results?contract_id=eq.CONTRACT_ID&is_final=eq.true' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```

---

### 6.5 `GET /contract_settlements`

**Get all settlements for a contract:**
```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_settlements?contract_id=eq.CONTRACT_ID&select=from_user_id,to_user_id,amount,point_type,settlement_type,fee_amount,settled_at' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```

**Get all rewards received by a user:**
```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_settlements?to_user_id=eq.USER_ID&settlement_type=eq.reward&order=settled_at.desc' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```

**Response:**
```json
[
  {
    "from_user_id": "00000000-0000-0000-0000-000000000000",
    "to_user_id": "USER_B_ID",
    "amount": 190.00,
    "point_type": "ix_point",
    "settlement_type": "reward",
    "fee_amount": 0.00,
    "settled_at": "2026-03-22T10:10:00Z"
  },
  {
    "from_user_id": "00000000-0000-0000-0000-000000000000",
    "to_user_id": "00000000-0000-0000-0000-000000000001",
    "amount": 10.00,
    "point_type": "ix_point",
    "settlement_type": "fee",
    "fee_amount": 10.00,
    "settled_at": "2026-03-22T10:10:00Z"
  }
]
```

---

### 6.6 `POST /contract_consents`

Submit consent or dispute after result is reported.

**Consent (agree):**
```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_consents' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "contract_id": "CONTRACT_ID",
    "user_id": "USER_A_ID",
    "consented": true
  }'
```

**Dispute (disagree) — `reason` is required:**
```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_consents' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "contract_id": "CONTRACT_ID",
    "user_id": "USER_A_ID",
    "consented": false,
    "reason": "My move was registered incorrectly due to server lag."
  }'
```

**Get consents for a contract:**
```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_consents?contract_id=eq.CONTRACT_ID&select=user_id,consented,reason,consented_at' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```

---

### 6.7 `GET /point_balances`

**Get all balances for a user:**
```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/point_balances?user_id=eq.USER_ID&select=point_type,balance' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```

**Get only ix_point balance:**
```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/point_balances?user_id=eq.USER_ID&point_type=eq.ix_point&select=balance' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```

**Response:**
```json
[
  { "point_type": "ix_point", "balance": 500.00 },
  { "point_type": "ix_free_point", "balance": 200.00 }
]
```

---

### 6.8 `GET /public_ledger`

Public read-only view. No authentication required (but headers must still be sent).

**Get full contract record:**
```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/public_ledger?contract_id=eq.CONTRACT_ID' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```

**Recent settled contracts:**
```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/public_ledger?contract_status=eq.settled&order=settled_at.desc&limit=10' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```

**Response:**
```json
[
  {
    "contract_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    "contract_type_name": "RPS Casual Lobby 1",
    "contract_type": "rps",
    "contract_status": "settled",
    "is_on_chain": false,
    "created_at": "2026-03-22T10:00:00Z",
    "activated_at": "2026-03-22T10:01:00Z",
    "completed_at": "2026-03-22T10:05:00Z",
    "settled_at": "2026-03-22T10:10:00Z",
    "tx_hash": null,
    "parties": [
      { "user_id": "USER_A_ID", "role": "challenger", "escrow_amount": 100, "escrow_type": "ix_point" },
      { "user_id": "USER_B_ID", "role": "opponent", "escrow_amount": 100, "escrow_type": "ix_point" }
    ],
    "result": {
      "winner_id": "USER_B_ID",
      "winner_move": "rock",
      "loser_move": "scissors",
      "rounds_played": 1,
      "score": "1-0",
      "is_draw": false
    },
    "settlements": [
      { "from": "00000000-0000-0000-0000-000000000000", "to": "USER_B_ID", "amount": 194, "point_type": "ix_point", "fee": 0, "settled_at": "..." },
      { "from": "00000000-0000-0000-0000-000000000000", "to": "00000000-0000-0000-0000-000000000001", "amount": 6, "point_type": "ix_point", "fee": 6, "settled_at": "..." }
    ]
  }
]
```

---

## 7. RPC Functions

RPC functions run business logic inside the database. Call via `POST /rest/v1/rpc/<function_name>`.

All RPC calls require the same auth headers as REST endpoints.

---

### 7.1 `register_player` — Initialize user point balances

**Call when:** A new user registers. Creates their `point_balances` records with starting amounts.

> This function should be called immediately after Supabase Auth signup succeeds.

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/rpc/register_player' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "p_user_id": "USER_UUID_FROM_AUTH"
  }'
```

**Response (HTTP 200):**
```json
true
```

**What it does:**
1. Creates `point_balances` for `ix_point` with starting balance (e.g. 1000)
2. Creates `point_balances` for `ix_free_point` with starting balance (e.g. 500)
3. Is idempotent — safe to call multiple times (uses `ON CONFLICT DO NOTHING`)

---

### 7.2 `create_contract` — Create contract from template

**Call when:** A contract session is initiated (e.g. two users agree to play RPS).

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/rpc/create_contract' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "p_template_id": "20000000-0000-0000-0000-000000000001",
    "p_metadata": { "room_id": "room-123", "match_id": "match-456" }
  }'
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_template_id` | UUID | Yes | Template to use |
| `p_metadata` | JSONB | No | Extra data (room ID, match ID, etc.) |

**Response (HTTP 200):** Returns the new contract UUID.
```json
"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
```

**Errors:**
- `Template not found` — template ID doesn't exist
- `Template is not active` — template is disabled

---

### 7.3 `join_contract` — Join contract + lock escrow

**Call when:** Each party joins the contract and commits their escrow amount.

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/rpc/join_contract' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "p_contract_id": "CONTRACT_UUID",
    "p_user_id": "USER_UUID",
    "p_role": "challenger",
    "p_escrow_amount": 100,
    "p_escrow_type": "ix_point"
  }'
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_contract_id` | UUID | Yes | The contract to join |
| `p_user_id` | UUID | Yes | The joining user |
| `p_role` | VARCHAR | Yes | User's role (`challenger`, `opponent`, `worker`, `client`, `participant`, `organizer`) |
| `p_escrow_amount` | DECIMAL | Yes | Points to lock. Must be ≤ user's balance |
| `p_escrow_type` | point_type | Yes | `ix_point` or `ix_free_point` |
| `p_chain_record_choice` | BOOLEAN | No | Only if template `chain_record_policy = optional` |

**Response (HTTP 200):** Returns party record UUID.
```json
"party-uuid-here"
```

**What it does:**
1. Validates contract is in `created` status
2. Validates user has sufficient balance
3. Deducts escrow from user's `point_balances` (atomic)
4. Creates `contract_parties` record with `escrow_status = held`

**Errors:**
- `Contract not found` — contract ID doesn't exist
- `Contract is not in created status` — already active/completed/etc.
- `Insufficient balance` — user doesn't have enough points

---

### 7.4 `activate_contract` — Start the contract

**Call when:** All parties have joined and escrowed. Transitions `created → active`.

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/rpc/activate_contract' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "p_contract_id": "CONTRACT_UUID"
  }'
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_contract_id` | UUID | Yes | Contract to activate |

**Response (HTTP 200):**
```json
true
```

**What it does:**
1. Validates at least 2 parties have joined
2. Updates status `created → active`
3. DB trigger automatically sets `activated_at = NOW()`

**Errors:**
- `Contract not found`
- `Contract is not in created status`
- `Need at least 2 parties` — not enough players joined yet

---

### 7.5 `settle_contract` — Distribute points after result

**Call when:** Contract is in `completed` or `resolved` status and a final result (`is_final = true`) exists.

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/rpc/settle_contract' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "p_contract_id": "CONTRACT_UUID"
  }'
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_contract_id` | UUID | Yes | Contract to settle |

**Response (HTTP 200):**
```json
true
```

**What it does (winner scenario):**
1. Reads the `is_final = true` result to get `winner_id`
2. Calculates `fee = total_escrow × fee_rate / 100`
3. Calculates `winner_amount = total_escrow - fee`
4. Creates settlement record: escrow → winner (type: `reward`)
5. Creates settlement record: escrow → treasury (type: `fee`)
6. Adds `winner_amount` to winner's balance
7. Adds `fee` to treasury's balance
8. Updates all parties `escrow_status = released`
9. Updates contract status `→ settled`, sets `settled_at`

**What it does (draw scenario):**
- Checks `result_data.is_draw = true` and `reward_rules.draw_refund = true`
- Refunds each party their full escrow amount
- Creates `refund` settlement record per party
- Updates parties `escrow_status = refunded`

**Errors:**
- `Contract not in completed/resolved status`
- `No finalized result found (is_final=true)` — result must be posted before settling

---

## 8. Complete Lifecycle — RPS Example (A vs B)

**Scenario:** Player A (challenger) vs Player B (opponent). Bet: 100 IX Points each. Template fee: 3%.

```
A balance: 500 ix_point    B balance: 300 ix_point
```

---

### Step 0 — Register players (first time only)

Each new user must call this once after signup:

```bash
# Register Player A
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/rpc/register_player' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{ "p_user_id": "USER_A_ID" }'

# Register Player B
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/rpc/register_player' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{ "p_user_id": "USER_B_ID" }'
```

---

### Step 1 — Check balances before playing

```bash
# A checks their balance
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/point_balances?user_id=eq.USER_A_ID&select=point_type,balance' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```

```json
[
  { "point_type": "ix_point", "balance": 500.00 },
  { "point_type": "ix_free_point", "balance": 200.00 }
]
```

---

### Step 2 — Find the RPS template

```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_templates?type=eq.rps&is_active=eq.true&select=id,name,fee_rate,conditions,reward_rules&limit=1' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```

```json
[{
  "id": "20000000-0000-0000-0000-000000000001",
  "name": "RPS Casual Lobby 1",
  "fee_rate": 3.00,
  "conditions": { "min_bet": 10, "max_bet": 100, "rounds": 1, "timeout_seconds": 15 },
  "reward_rules": { "winner_pct": 97, "draw_refund": true }
}]
```

---

### Step 3 — Create contract instance

> Status: **→ Created**

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/rpc/create_contract' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "p_template_id": "20000000-0000-0000-0000-000000000001",
    "p_metadata": { "room_id": "rps-lobby-42" }
  }'
```

```json
"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
```

Save this contract ID: `aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee`

---

### Step 4 — A joins and locks escrow

> A's balance: 500 → **400** (100 locked)

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/rpc/join_contract' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "p_contract_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    "p_user_id": "USER_A_ID",
    "p_role": "challenger",
    "p_escrow_amount": 100,
    "p_escrow_type": "ix_point"
  }'
```

---

### Step 5 — B joins and locks escrow

> B's balance: 300 → **200** (100 locked)

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/rpc/join_contract' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "p_contract_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    "p_user_id": "USER_B_ID",
    "p_role": "opponent",
    "p_escrow_amount": 100,
    "p_escrow_type": "ix_point"
  }'
```

Total escrow locked: **200 ix_point**

---

### Step 6 — Activate the contract

> Status: Created **→ Active**

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/rpc/activate_contract' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{ "p_contract_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" }'
```

---

### Step 7 — Match plays, game server reports result

> A picks **Scissors**, B picks **Rock** → B wins.

**Game server posts result (uses service_role key in production):**

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_results' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -H 'Prefer: return=representation' \
  -d '{
    "contract_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    "result_data": {
      "winner_id": "USER_B_ID",
      "winner_move": "rock",
      "loser_move": "scissors",
      "rounds_played": 1,
      "score": "1-0",
      "is_draw": false
    },
    "reported_by": "system",
    "is_final": true
  }'
```

**Update contract status to completed:**

> Status: Active **→ Completed**

```bash
curl -X PATCH 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_instances?id=eq.aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{ "status": "completed" }'
```

---

### Step 8 — Both parties consent

**A consents (accepts the loss):**

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_consents' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "contract_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    "user_id": "USER_A_ID",
    "consented": true
  }'
```

**B consents (accepts the win):**

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_consents' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "contract_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    "user_id": "USER_B_ID",
    "consented": true
  }'
```

---

### Step 9 — Settle the contract

> Status: Completed **→ Settled**

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/rpc/settle_contract' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{ "p_contract_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" }'
```

**Point math:**
```
Total escrow:   200 ix_point
Fee (3%):         6 ix_point  → Treasury
B's reward:     194 ix_point  → USER_B_ID

A final balance: 400 (400 - already deducted at join)
B final balance: 200 + 194 = 394
```

---

### Step 10 — Verify final state

**Check B's balance:**
```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/point_balances?user_id=eq.USER_B_ID&point_type=eq.ix_point&select=balance' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```
```json
[{ "balance": 394.00 }]
```

**View on public ledger:**
```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/public_ledger?contract_id=eq.aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>'
```

---

### Full lifecycle summary

| Step | Action | API | Who calls |
|------|--------|-----|-----------|
| 0 | Register user | `POST /rpc/register_player` | Client (on signup) |
| 1 | Check balance | `GET /point_balances?user_id=...` | Client |
| 2 | Find template | `GET /contract_templates?type=eq.rps&is_active=eq.true` | Client / Server |
| 3 | Create contract | `POST /rpc/create_contract` | Server |
| 4 | A joins + escrow | `POST /rpc/join_contract` | Server (for each party) |
| 5 | B joins + escrow | `POST /rpc/join_contract` | Server |
| 6 | Activate | `POST /rpc/activate_contract` | Server |
| 7a | Report result | `POST /contract_results` | Game server |
| 7b | Mark completed | `PATCH /contract_instances?id=...` | Game server |
| 8 | Each party consents | `POST /contract_consents` | Client (per user) |
| 9 | Settle | `POST /rpc/settle_contract` | Server |
| 10 | View ledger | `GET /public_ledger?contract_id=...` | Client / Anyone |

---

## 9. Dispute Flow

If any party disagrees with the result, they submit `consented: false`.

### Step 1 — A disputes the result

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_consents' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "contract_id": "CONTRACT_ID",
    "user_id": "USER_A_ID",
    "consented": false,
    "reason": "Suspected lag. My Scissors move was not registered correctly."
  }'
```

### Step 2 — Server moves contract to `disputed`

> Status: Completed **→ Disputed**

```bash
curl -X PATCH 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_instances?id=eq.CONTRACT_ID' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{ "status": "disputed" }'
```

### Step 3 — Admin reviews and resolves

Admin reviews logs, game replay, or server data. After decision:

> Status: Disputed **→ Resolved**

```bash
curl -X PATCH 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_instances?id=eq.CONTRACT_ID' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{ "status": "resolved" }'
```

If admin decides to update the result (correcting the winner), post a new final result:

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_results' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "contract_id": "CONTRACT_ID",
    "result_data": {
      "winner_id": "USER_A_ID",
      "is_draw": false,
      "note": "Corrected after dispute review. Server log confirmed A played Scissors before timeout."
    },
    "reported_by": "system",
    "is_final": true
  }'
```

### Step 4 — Settle

Same as normal — `settle_contract` uses the latest `is_final = true` result.

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/rpc/settle_contract' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{ "p_contract_id": "CONTRACT_ID" }'
```

---

## 10. Draw Flow

### Setup: result with `is_draw: true`

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_results' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "contract_id": "CONTRACT_ID",
    "result_data": {
      "is_draw": true,
      "rounds_played": 3,
      "score": "1-1-1"
    },
    "reported_by": "system",
    "is_final": true
  }'
```

Mark completed, collect consents, then settle. `settle_contract` will:

1. Detect `is_draw = true` in result_data
2. Check template `reward_rules.draw_refund = true`
3. Refund each party their full escrow (no fee deducted)
4. Create `refund` settlement records

**Draw result:**
```
A gets back: 100 ix_point (full refund)
B gets back: 100 ix_point (full refund)
Treasury:    0 (no fee on draw)
```

---

## 11. Realtime WebSocket Subscriptions

Subscribe to live contract status changes using Supabase Realtime.

The following tables have Realtime enabled:
- `contract_instances` — status changes
- `contract_results` — new results
- `contract_consents` — consent updates

### JavaScript (Supabase client)

```javascript
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://YOUR_PROJECT_REF.supabase.co',
  '<YOUR_SUPABASE_ANON_KEY>'
)

// Subscribe to status changes on a specific contract
const channel = supabase
  .channel('contract-status')
  .on(
    'postgres_changes',
    {
      event: 'UPDATE',
      schema: 'public',
      table: 'contract_instances',
      filter: `id=eq.CONTRACT_UUID`
    },
    (payload) => {
      console.log('Contract status changed:', payload.new.status)
    }
  )
  .subscribe()

// Subscribe to new results for a contract
supabase
  .channel('contract-results')
  .on(
    'postgres_changes',
    {
      event: 'INSERT',
      schema: 'public',
      table: 'contract_results',
      filter: `contract_id=eq.CONTRACT_UUID`
    },
    (payload) => {
      console.log('New result:', payload.new.result_data)
    }
  )
  .subscribe()

// Cleanup
channel.unsubscribe()
```

---

## 12. Filtering, Sorting & Pagination

PostgREST supports rich query parameters. All filters use `column=operator.value` format.

### Comparison operators

| Operator | SQL | Example |
|----------|-----|---------|
| `eq` | `=` | `status=eq.active` |
| `neq` | `!=` | `status=neq.settled` |
| `lt` | `<` | `escrow_amount=lt.100` |
| `lte` | `<=` | `balance=lte.500` |
| `gt` | `>` | `balance=gt.0` |
| `gte` | `>=` | `created_at=gte.2026-03-01T00:00:00Z` |
| `in` | `IN (...)` | `status=in.(active,completed)` |
| `is` | `IS` | `tx_hash=is.null` |

### Select specific columns

```bash
# Only return id, status, created_at
?select=id,status,created_at

# Nested join (via foreign key)
?select=id,contract_instances(status,created_at)
```

### Sorting

```bash
?order=created_at.desc        # newest first
?order=balance.asc            # lowest balance first
?order=settled_at.desc.nullslast   # settled first, nulls at end
```

### Pagination

```bash
?limit=20&offset=0    # page 1 (20 per page)
?limit=20&offset=20   # page 2
?limit=20&offset=40   # page 3
```

### Range header (for total count)

```bash
curl 'https://YOUR_PROJECT_REF.supabase.co/rest/v1/contract_instances?status=eq.settled' \
  -H 'apikey: <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>' \
  -H 'Prefer: count=exact'
```

Response headers include:
```
Content-Range: 0-19/847   ← total 847 records
```

### Common query examples

**All contracts for a user (via parties):**
```bash
/contract_parties?user_id=eq.USER_ID&select=contract_id,role,joined_at,contract_instances(status,created_at)&order=joined_at.desc&limit=20
```

**User's transaction history:**
```bash
/contract_settlements?to_user_id=eq.USER_ID&order=settled_at.desc&limit=50
```

**Recent disputes:**
```bash
/contract_instances?status=eq.disputed&order=created_at.desc&limit=10
```

**Contracts with escrow still held (active):**
```bash
/contract_parties?escrow_status=eq.held&user_id=eq.USER_ID
```

---

## 13. Error Handling

### HTTP status codes

| Code | Meaning |
|------|---------|
| `200` | Success (GET, RPC) |
| `201` | Created (POST with `Prefer: return=representation`) |
| `204` | Success, no body (POST without Prefer header) |
| `400` | Bad request — validation error, invalid status transition |
| `401` | Unauthorized — missing or invalid API key |
| `403` | Forbidden — RLS policy blocked the operation |
| `404` | Not found — resource doesn't exist |
| `409` | Conflict — unique constraint violation (e.g. user already joined) |
| `500` | Internal server error — PostgreSQL function error |

### RPC error format

When a PostgreSQL function raises an exception, the response is:

```json
{
  "code": "P0001",
  "details": null,
  "hint": null,
  "message": "Contract is not in created status (current: active). Cannot join."
}
```

### Common errors and how to handle them

| Error message | Cause | Fix |
|---------------|-------|-----|
| `Template not found` | Wrong template UUID | Query templates first |
| `Template is not active` | Template disabled | Use `is_active=eq.true` filter |
| `Contract not found` | Wrong contract UUID | Verify contract was created |
| `Contract is not in created status` | Already active/completed | Check status before joining |
| `Need at least 2 parties` | Only 1 party joined | Wait for all parties |
| `Insufficient balance` | User doesn't have enough points | Check balance before joining |
| `No finalized result found` | `is_final=true` result missing | Post result before settling |
| `Invalid status transition` | Bad status change (e.g. active→created) | Follow lifecycle order |
| `duplicate key value violates unique constraint` | User already joined or consented | Check before calling |
| `new row violates check constraint "chk_dispute_reason"` | Dispute missing reason | Include `reason` when `consented=false` |

### RLS (403) errors

If you get `403 Forbidden`, the Row Level Security policy blocked the request. Common causes:

- Using `anon` key but trying to insert into a restricted table
- User trying to read another user's balance
- Non-admin trying to create a template

**Solution:** Use `service_role` key for server-side operations, or ensure the user is authenticated and the data belongs to them.

---

## 14. FAQ for Frontend Engineers

**Q: Do I need to authenticate the user to call the APIs?**
A: For most read operations (templates, public ledger), you can use the `anon` key without a user token. For writes (join_contract, consent), the RLS policy checks the user's JWT. Use Supabase Auth to log users in and pass their access token.

---

**Q: What is the difference between `anon` key and `service_role` key?**
A: The `anon` key is safe to use in the browser/client — it respects Row Level Security policies. The `service_role` key bypasses all RLS and should **only** be used server-side (game server, backend). Never expose `service_role` in frontend code.

---

**Q: Why do both headers (`apikey` and `Authorization`) send the same value?**
A: This is how Supabase's API gateway works. The `apikey` identifies the project (goes to Kong API gateway). The `Authorization: Bearer` token is what PostgREST/Auth uses to check permissions. When using user JWT, `apikey` stays as the anon key but `Authorization` changes to the user's access token.

```http
apikey: <ANON_KEY>                     ← always anon key
Authorization: Bearer <USER_JWT>       ← user's JWT from auth login
```

---

**Q: How do I know when to call `settle_contract`?**
A: After both parties have submitted their consent (`consented = true`), the server should automatically call `settle_contract`. The contract must be in `completed` or `resolved` status, and a `is_final = true` result must exist.

---

**Q: Can a user join a contract twice?**
A: No. The DB has a unique constraint `(contract_id, user_id)` in `contract_parties`. The second join attempt returns HTTP 409 Conflict.

---

**Q: What happens if a user doesn't have enough balance?**
A: `join_contract` will return HTTP 500 with message `Insufficient balance. Required: X, current: Y`. The frontend should check balance before showing the join UI.

---

**Q: Can I consent after settling?**
A: No. Once status = `settled`, no further changes are possible. The status transition trigger blocks all changes to settled contracts.

---

**Q: How do I display a user's match history?**
A: Query `contract_parties` for the user's contracts, then join with `public_ledger` for full details:

```bash
/contract_parties?user_id=eq.USER_ID&order=joined_at.desc&limit=20
```

Then for each `contract_id`, fetch from `public_ledger`.

---

**Q: What does `tx_hash` being null mean?**
A: In Phase 0, all contracts are off-chain. `tx_hash` is always `null`. In Phase 1, settled contracts will have a real MegaETH transaction hash here.

---

**Q: Can I filter `public_ledger` by user?**
A: The view doesn't have a direct `user_id` column. Filter by `contract_id`, or first query `contract_parties` for the user's contract IDs, then pass to `public_ledger`.

---

**Q: What is the Escrow UUID (`00000000-...-000000000000`)?**
A: It's a virtual system account that holds escrowed points. In settlement records, it appears as `from_user_id` — meaning "the escrow system is releasing held points to the winner". There is no real user with this UUID.

---

**Q: Should the client or server call `settle_contract`?**
A: Always the server. Settlement involves financial logic (point math, fee calculation, balance updates). Never trust the client with financial operations. The game server should call this automatically after detecting both consents.
