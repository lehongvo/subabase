# IX Metaverse — DB Design & API Design

| Item | Details |
|------|---------|
| Document ID | IX-API-FRONTEND-001 |
| Version | 1.0.0 |
| Date | 2026-03-27 |
| Author | Vo Le (Backend Lead) |
| Audience | Frontend Development Team |

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Connection Info](#2-connection-info)
3. [DB Design](#3-db-design)
4. [API Design](#4-api-design)
5. [RPC Functions](#5-rpc-functions)
6. [Realtime Subscriptions](#6-realtime-subscriptions)
7. [Full Flow Example](#7-full-flow-example)
8. [FE Integration Code](#8-fe-integration-code)
9. [Error Handling](#9-error-handling)
10. [FE UI Requirements (từ Spec)](#10-fe-ui-requirements-từ-spec)
11. [Open Items (TBD)](#11-open-items-tbd)

---

## 1. Project Overview

### 1.1 Hệ thống là gì?

IX Metaverse Contract Management System — quản lý tất cả "tương tác dựa trên đồng thuận" (contracts) giữa users trong metaverse IX.

**Ví dụ contract:**

| Loại | Mô tả | Các bên |
|------|--------|---------|
| **RPS** (Kéo-búa-bao) | User vs User, đặt cược point theo kết quả | User vs User |
| **Work Reward** | Thanh toán khi hoàn thành công việc | Worker vs Client |
| **Tournament** | Thu phí tham gia và chia giải thưởng | Participant vs Organizer |
| **Custom** | Template tùy chỉnh do Admin định nghĩa | Tùy |

### 1.2 Phase Plan

```
Phase 0 (HIỆN TẠI)  →  Phase 1         →  Phase 2           →  Phase 3
Off-chain (Supabase)    On-chain MegaETH   IX Economic Token     DAO Governance
IX Points / Free Pts    USDT               ERC-20 Token          Governance Token
```

| Phase | Thanh toán | Quản lý | Mục tiêu |
|-------|-----------|---------|----------|
| **Phase 0** *(hiện tại)* | IX Points / IX Free Points | Off-chain (Supabase DB) | UX validation, user acquisition |
| Phase 1 | USDT trên MegaETH | Smart contracts | On-chain migration |
| Phase 2 | IX Economic Token (ERC-20) | Smart contracts | Token economy |
| Phase 3 | Economic + Governance Token | DAO | Community governance |

> **FE đang build cho Phase 0.** DB schema thiết kế sẵn để map 1:1 sang smart contract Phase 1.

### 1.3 IX Points vs IX Free Points

| | IX Points | IX Free Points |
|--|-----------|----------------|
| **Cách có** | Mua / nhận thưởng | Phát miễn phí, login bonus... |
| **Dùng cho** | Hợp đồng production (thật) | Luyện tập / hợp đồng rủi ro thấp |
| **Chuyển đổi** | Có (tương lai → token) | **Không** |
| **Giá trị** | Có giá trị thật | Không có giá trị thật |

> FE cần hiển thị rõ ràng user đang dùng loại point nào. **Không được trộn lẫn 2 loại.**

### 1.4 Hệ thống liên quan

| Hệ thống | Vai trò |
|----------|---------|
| **IX-Government-platform** | Admin dashboard, quản lý user, hệ thống point (đã có) |
| **IX Metaverse** | Nguồn event, môi trường thực thi contract |
| **MegaETH** | Blockchain (từ Phase 1 trở đi) |

---

## 2. Connection Info

| Item | Value |
|------|-------|
| Platform | Supabase Cloud |
| Project URL | `https://veoillsstewpnvmhxmlx.supabase.co` |
| REST API | `https://veoillsstewpnvmhxmlx.supabase.co/rest/v1` |
| Anon Key | *(lấy từ Settings → API → Project API keys → anon public)* |

### Headers (mọi request đều cần)

```
apikey: <ANON_KEY>
Authorization: Bearer <USER_JWT_TOKEN>
Content-Type: application/json
```

---

## 3. DB Design

### 3.1 Tổng quan

```
┌─────────────────────┐
│  contract_templates  │  ← Admin tạo template (RPS, Work Reward...)
└──────────┬──────────┘
           │ 1 template → N instances
           ▼
┌─────────────────────┐
│  contract_instances  │  ← Mỗi trận đấu / hợp đồng cụ thể
└──────────┬──────────┘
           │
     ┌─────┼──────────┬──────────────┐
     │     │          │              │
     ▼     ▼          ▼              ▼
 parties  results   consents    settlements
 (ai chơi) (kết quả) (đồng ý?)  (thanh toán)

┌──────────────────┐
│  point_balances   │  ← Số dư point của mỗi user
└──────────────────┘

┌──────────────────┐
│  public_ledger    │  ← VIEW tổng hợp (read-only, cho public)
└──────────────────┘
```

### 3.2 ENUM Types

```
contract_type:        rps | work_reward | tournament | custom
contract_status:      created | active | completed | disputed | resolved | settled
payment_type:         ix_point | ix_free_point | both
point_type:           ix_point | ix_free_point
chain_record_policy:  required | optional | off
result_source:        system | user
```

### 3.3 Chi tiết từng Table

---

#### `contract_templates`

> Template do Admin tạo. Định nghĩa loại hợp đồng, điều kiện, phí...

| Column | Type | Null | Default | Mô tả |
|--------|------|------|---------|-------|
| `id` | uuid | PK | auto | |
| `name` | varchar | NOT NULL | — | Tên hiển thị |
| `description` | text | NULL | — | Mô tả |
| `type` | contract_type | NOT NULL | — | `rps` · `work_reward` · `tournament` · `custom` |
| `conditions` | jsonb | NOT NULL | — | Điều kiện hợp đồng |
| `reward_rules` | jsonb | NOT NULL | — | Quy tắc thưởng |
| `payment_type` | payment_type | NOT NULL | `both` | Loại point chấp nhận |
| `fee_rate` | numeric | NOT NULL | `5.0` | Phí platform (%) |
| `chain_record_policy` | chain_record_policy | NOT NULL | `off` | Ghi blockchain? |
| `chain_record_description` | text | NULL | — | Text cho user khi `optional` |
| `is_active` | boolean | NOT NULL | `false` | Đang hoạt động? |
| `metaverse_event_id` | varchar | NULL | — | Event ID liên kết |
| `created_by` | uuid | NOT NULL | — | Admin tạo |
| `created_at` | timestamptz | NOT NULL | `now()` | |
| `updated_at` | timestamptz | NOT NULL | `now()` | |

**Data thực tế:**

```json
{
  "id": "20000000-0000-0000-0000-000000000001",
  "name": "RPS Casual Lobby 1",
  "description": "Casual rock-paper-scissors for beginners. Low stakes, fast rounds.",
  "type": "rps",
  "conditions": {
    "rounds": 1,
    "max_bet": 100,
    "min_bet": 10,
    "timeout_seconds": 15
  },
  "reward_rules": {
    "winner_pct": 95,
    "draw_refund": true
  },
  "payment_type": "ix_free_point",
  "fee_rate": 3.0,
  "chain_record_policy": "off",
  "chain_record_description": null,
  "is_active": true,
  "metaverse_event_id": "evt_rps_001",
  "created_by": "10000000-0000-0000-0000-000000000001",
  "created_at": "2026-03-22T11:29:30.010771+00:00",
  "updated_at": "2026-03-22T11:29:30.010771+00:00"
}
```

> **`conditions` fields**: `min_bet` (số bet tối thiểu), `max_bet` (tối đa), `rounds` (số ván), `timeout_seconds` (thời gian chờ consent)
>
> **`reward_rules` fields**: `winner_pct` (% winner nhận, 95 = 95%), `draw_refund` (hòa → hoàn tiền?)

---

#### `contract_instances`

> Mỗi trận đấu / hợp đồng cụ thể, tạo từ template.

| Column | Type | Null | Default | Mô tả |
|--------|------|------|---------|-------|
| `id` | uuid | PK | auto | |
| `template_id` | uuid | FK | — | → `contract_templates.id` |
| `status` | contract_status | NOT NULL | `created` | Trạng thái hiện tại |
| `chain_record` | boolean | NOT NULL | `false` | Ghi on-chain? |
| `tx_hash` | varchar | NULL | — | Transaction hash (Phase 1+) |
| `metadata` | jsonb | NULL | — | Data mở rộng |
| `created_at` | timestamptz | NOT NULL | `now()` | |
| `activated_at` | timestamptz | NULL | — | Bắt đầu chơi |
| `completed_at` | timestamptz | NULL | — | Có kết quả |
| `settled_at` | timestamptz | NULL | — | Thanh toán xong |

**Lifecycle (state machine):**

```
Created → Active → Completed → Settled
                       ↓
                   Disputed → Resolved → Settled
```

**Data thực tế:**

```json
{
  "id": "30000000-0000-0000-0000-000000000001",
  "template_id": "20000000-0000-0000-0000-000000000002",
  "status": "settled",
  "chain_record": false,
  "tx_hash": null,
  "metadata": {
    "room_id": "room_0001",
    "match_id": "match_c4ca4238a0b923820dcc509a6f75849b"
  },
  "created_at": "2025-12-13T11:29:30.305244+00:00",
  "activated_at": "2025-12-13T11:34:30.305244+00:00",
  "completed_at": "2025-12-13T11:39:30.305244+00:00",
  "settled_at": "2025-12-13T11:44:30.305244+00:00"
}
```

---

#### `contract_parties`

> Ai tham gia hợp đồng, đặt bao nhiêu point.

| Column | Type | Null | Default | Mô tả |
|--------|------|------|---------|-------|
| `id` | uuid | PK | auto | |
| `contract_id` | uuid | FK | — | → `contract_instances.id` |
| `user_id` | uuid | NOT NULL | — | User tham gia |
| `role` | varchar | NOT NULL | — | Vai trò |
| `escrow_amount` | numeric | NOT NULL | `0` | Số point ký quỹ |
| `escrow_type` | point_type | NOT NULL | — | Loại point |
| `escrow_status` | varchar | NOT NULL | `held` | `held` · `released` · `refunded` |
| `chain_record_choice` | boolean | NULL | — | User chọn ghi on-chain? |
| `joined_at` | timestamptz | NOT NULL | `now()` | |

**Roles theo loại contract:**

| Contract Type | Role 1 | Role 2 |
|---------------|--------|--------|
| `rps` | `challenger` | `opponent` |
| `work_reward` | `worker` | `client` |
| `tournament` | `participant` | `organizer` |

**Data thực tế:**

```json
{
  "id": "40000000-0001-0000-0000-000000000001",
  "contract_id": "30000000-0000-0000-0000-000000000001",
  "user_id": "10000000-0000-0000-0000-000000000002",
  "role": "challenger",
  "escrow_amount": 60.0,
  "escrow_type": "ix_free_point",
  "escrow_status": "released",
  "chain_record_choice": null,
  "joined_at": "2025-12-13T11:30:30.305244+00:00"
}
```

---

#### `contract_results`

> Kết quả trận đấu. Thường do game server (system) gửi.

| Column | Type | Null | Default | Mô tả |
|--------|------|------|---------|-------|
| `id` | uuid | PK | auto | |
| `contract_id` | uuid | FK | — | → `contract_instances.id` |
| `result_data` | jsonb | NOT NULL | — | Kết quả chi tiết |
| `reported_by` | result_source | NOT NULL | `system` | `system` hoặc `user` |
| `reporter_id` | uuid | NULL | — | Ai báo kết quả |
| `is_final` | boolean | NOT NULL | `false` | Kết quả chính thức? |
| `reported_at` | timestamptz | NOT NULL | `now()` | |
| `finalized_at` | timestamptz | NULL | — | Thời điểm finalize |

**Data thực tế:**

```json
{
  "id": "50000000-0000-0000-0000-000000000001",
  "contract_id": "30000000-0000-0000-0000-000000000001",
  "result_data": {
    "score": "1-0",
    "winner_id": "10000000-0000-0000-0000-000000000027",
    "loser_move": "rock",
    "winner_move": "paper",
    "rounds_played": 1
  },
  "reported_by": "system",
  "reporter_id": null,
  "is_final": true,
  "reported_at": "2025-12-13T11:39:30.305244+00:00",
  "finalized_at": "2025-12-13T11:44:30.305244+00:00"
}
```

> **`result_data` fields (RPS)**: `winner_id`, `score`, `winner_move`, `loser_move`, `rounds_played`

---

#### `contract_consents`

> Đồng thuận kết quả. Mỗi bên phải consent trước khi settle.

| Column | Type | Null | Default | Mô tả |
|--------|------|------|---------|-------|
| `id` | uuid | PK | auto | |
| `contract_id` | uuid | FK | — | → `contract_instances.id` |
| `user_id` | uuid | NOT NULL | — | User |
| `consented` | boolean | NOT NULL | — | `true` = đồng ý · `false` = khiếu nại |
| `reason` | text | NULL | — | Lý do khiếu nại |
| `signature` | varchar | NULL | — | Wallet signature (Phase 1+) |
| `consented_at` | timestamptz | NOT NULL | `now()` | |

**Data thực tế:**

```json
{
  "id": "60000000-0001-0000-0000-000000000001",
  "contract_id": "30000000-0000-0000-0000-000000000001",
  "user_id": "10000000-0000-0000-0000-000000000002",
  "consented": true,
  "reason": null,
  "signature": null,
  "consented_at": "2025-12-13T11:41:30.305244+00:00"
}
```

---

#### `contract_settlements`

> Giao dịch chuyển point khi thanh toán.

| Column | Type | Null | Default | Mô tả |
|--------|------|------|---------|-------|
| `id` | uuid | PK | auto | |
| `contract_id` | uuid | FK | — | → `contract_instances.id` |
| `from_user_id` | uuid | NOT NULL | — | Người gửi |
| `to_user_id` | uuid | NOT NULL | — | Người nhận |
| `amount` | numeric | NOT NULL | — | Số point |
| `point_type` | point_type | NOT NULL | — | Loại point |
| `settlement_type` | varchar | NOT NULL | `reward` | `reward` · `fee` · `refund` |
| `fee_amount` | numeric | NOT NULL | `0` | Phí platform |
| `tx_hash` | varchar | NULL | — | TX hash (Phase 1+) |
| `settled_at` | timestamptz | NOT NULL | `now()` | |

**System UUIDs:**

| UUID | Vai trò |
|------|---------|
| `00000000-0000-0000-0000-000000000000` | **ESCROW** — giữ point khi user join |
| `00000000-0000-0000-0000-000000000001` | **TREASURY** — ngân quỹ platform nhận phí |

**Data thực tế:**

```json
{
  "id": "70000000-0001-0000-0000-000000000001",
  "contract_id": "30000000-0000-0000-0000-000000000001",
  "from_user_id": "00000000-0000-0000-0000-000000000000",
  "to_user_id": "10000000-0000-0000-0000-000000000027",
  "amount": 114.0,
  "point_type": "ix_free_point",
  "settlement_type": "reward",
  "fee_amount": 6.0,
  "tx_hash": null,
  "settled_at": "2025-12-13T11:44:30.305244+00:00"
}
```

> Ví dụ trên: Escrow trả 114 point cho winner, phí platform 6 point (tổng escrow 120, fee 5% ≈ 6).

---

#### `point_balances`

> Số dư point hiện tại. Mỗi user có 2 records: `ix_point` và `ix_free_point`.

| Column | Type | Null | Default | Mô tả |
|--------|------|------|---------|-------|
| `id` | uuid | PK | auto | |
| `user_id` | uuid | NOT NULL | — | |
| `point_type` | point_type | NOT NULL | — | `ix_point` · `ix_free_point` |
| `balance` | numeric | NOT NULL | `0` | Số dư |
| `updated_at` | timestamptz | NOT NULL | `now()` | |

**Data thực tế:**

```json
{
  "id": "74ba3f34-8486-4877-8a69-8f1b969703a6",
  "user_id": "10000000-0000-0000-0000-000000000003",
  "point_type": "ix_point",
  "balance": 8617.94,
  "updated_at": "2026-03-22T11:29:44.344251+00:00"
}
```

---

#### `public_ledger` *(VIEW — read-only)*

> View tổng hợp tất cả thông tin contract. Dùng cho trang lịch sử / public transparency.

| Column | Type | Mô tả |
|--------|------|-------|
| `contract_id` | uuid | |
| `contract_type_name` | varchar | Tên template |
| `contract_type` | contract_type | Loại |
| `contract_status` | contract_status | Trạng thái |
| `is_on_chain` | boolean | Ghi blockchain? |
| `created_at` | timestamptz | |
| `activated_at` | timestamptz | |
| `completed_at` | timestamptz | |
| `settled_at` | timestamptz | |
| `tx_hash` | varchar | |
| `parties` | jsonb | Array bên tham gia |
| `result` | jsonb | Kết quả |
| `settlements` | jsonb | Array thanh toán |

**Data thực tế:**

```json
{
  "contract_id": "30000000-0000-0000-0000-000000000066",
  "contract_type_name": "RPS Casual Lobby 2",
  "contract_type": "rps",
  "contract_status": "created",
  "is_on_chain": false,
  "created_at": "2026-03-22T11:19:30.535072+00:00",
  "activated_at": null,
  "completed_at": null,
  "settled_at": null,
  "tx_hash": null,
  "parties": [
    {
      "role": "worker",
      "user_id": "10000000-0000-0000-0000-000000000017",
      "escrow_type": "ix_point",
      "escrow_amount": 1520.0
    },
    {
      "role": "client",
      "user_id": "10000000-0000-0000-0000-000000000042",
      "escrow_type": "ix_point",
      "escrow_amount": 1520.0
    }
  ],
  "result": null,
  "settlements": null
}
```

---

## 4. API Design

### 4.1 Overview

Supabase tự tạo REST API cho mọi table. FE gọi trực tiếp qua HTTP.

| Endpoint | Methods | Mô tả |
|----------|---------|-------|
| `/contract_templates` | `GET` `POST` `PATCH` `DELETE` | Templates (Admin) |
| `/contract_instances` | `GET` `POST` `PATCH` `DELETE` | Instances |
| `/contract_parties` | `GET` `POST` `PATCH` `DELETE` | Parties |
| `/contract_results` | `GET` `POST` `PATCH` `DELETE` | Results |
| `/contract_consents` | `GET` `POST` `PATCH` `DELETE` | Consents |
| `/contract_settlements` | `GET` `POST` `PATCH` `DELETE` | Settlements |
| `/point_balances` | `GET` `POST` `PATCH` `DELETE` | Balances |
| `/public_ledger` | `GET` | Public view (read-only) |
| `/rpc/register_player` | `POST` | Đăng ký player |
| `/rpc/create_contract` | `POST` | Tạo contract |
| `/rpc/join_contract` | `POST` | Join contract |
| `/rpc/activate_contract` | `POST` | Activate contract |
| `/rpc/settle_contract` | `POST` | Settle contract |

> **Quan trọng:** Các thao tác business logic (tạo, join, activate, settle contract) → **gọi RPC** (mục 4). Không POST/PATCH trực tiếp vào tables.

### 4.2 Query Syntax (cho GET requests)

#### Filtering

| Operator | Ý nghĩa | Ví dụ |
|----------|---------|-------|
| `eq` | = | `?status=eq.active` |
| `neq` | != | `?type=neq.custom` |
| `gt` | > | `?balance=gt.100` |
| `gte` | >= | `?fee_rate=gte.5` |
| `lt` | < | `?balance=lt.50` |
| `lte` | <= | `?escrow_amount=lte.1000` |
| `in` | IN | `?status=in.(created,active)` |
| `is` | IS NULL | `?tx_hash=is.null` |
| `like` | LIKE | `?name=like.*Casual*` |
| `ilike` | ILIKE | `?name=ilike.*casual*` |

#### Select, Order, Pagination

```http
# Chỉ lấy một số columns
?select=id,name,type,fee_rate

# JOIN relations
?select=*,contract_templates(name,type)

# Sắp xếp
?order=created_at.desc

# Phân trang
?limit=20&offset=0

# Đếm tổng (thêm header: Prefer: count=exact)
# → Response header: Content-Range: 0-19/156
```

### 4.3 API chi tiết + Request/Response thực tế

---

#### GET — Lấy templates active

```http
GET /rest/v1/contract_templates?is_active=eq.true&select=*
```

**Response `200`:**

```json
[
  {
    "id": "20000000-0000-0000-0000-000000000001",
    "name": "RPS Casual Lobby 1",
    "description": "Casual rock-paper-scissors for beginners. Low stakes, fast rounds.",
    "type": "rps",
    "conditions": { "rounds": 1, "max_bet": 100, "min_bet": 10, "timeout_seconds": 15 },
    "reward_rules": { "winner_pct": 95, "draw_refund": true },
    "payment_type": "ix_free_point",
    "fee_rate": 3.0,
    "chain_record_policy": "off",
    "is_active": true,
    "metaverse_event_id": "evt_rps_001",
    "created_by": "10000000-0000-0000-0000-000000000001",
    "created_at": "2026-03-22T11:29:30.010771+00:00",
    "updated_at": "2026-03-22T11:29:30.010771+00:00"
  },
  { "..." }
]
```

---

#### GET — Lấy contract instance kèm template + parties + result

```http
GET /rest/v1/contract_instances?id=eq.30000000-0000-0000-0000-000000000001&select=*,contract_templates(name,type,conditions,fee_rate),contract_parties(user_id,role,escrow_amount,escrow_status),contract_results(result_data,is_final)
```

**Response `200`:**

```json
[
  {
    "id": "30000000-0000-0000-0000-000000000001",
    "template_id": "20000000-0000-0000-0000-000000000002",
    "status": "settled",
    "chain_record": false,
    "metadata": { "room_id": "room_0001", "match_id": "match_c4ca..." },
    "created_at": "2025-12-13T11:29:30.305244+00:00",
    "activated_at": "2025-12-13T11:34:30.305244+00:00",
    "completed_at": "2025-12-13T11:39:30.305244+00:00",
    "settled_at": "2025-12-13T11:44:30.305244+00:00",
    "contract_templates": {
      "name": "RPS Casual Lobby 2",
      "type": "rps",
      "conditions": { "rounds": 1, "max_bet": 100, "min_bet": 10, "timeout_seconds": 15 },
      "fee_rate": 3.0
    },
    "contract_parties": [
      { "user_id": "10000000-...-000000000002", "role": "challenger", "escrow_amount": 60.0, "escrow_status": "released" },
      { "user_id": "10000000-...-000000000027", "role": "opponent", "escrow_amount": 60.0, "escrow_status": "released" }
    ],
    "contract_results": [
      {
        "result_data": { "score": "1-0", "winner_id": "10000000-...-000000000027", "winner_move": "paper", "loser_move": "rock" },
        "is_final": true
      }
    ]
  }
]
```

---

#### GET — Lấy contracts của 1 user

```http
GET /rest/v1/contract_parties?user_id=eq.{user_id}&select=*,contract_instances(id,status,created_at,metadata,contract_templates(name,type))&order=joined_at.desc
```

---

#### GET — Lấy balance user

```http
GET /rest/v1/point_balances?user_id=eq.{user_id}&select=*
```

**Response `200`:**

```json
[
  { "user_id": "10000000-...", "point_type": "ix_point", "balance": 8617.94, "updated_at": "2026-03-22T..." },
  { "user_id": "10000000-...", "point_type": "ix_free_point", "balance": 2500.00, "updated_at": "2026-03-22T..." }
]
```

---

#### GET — Public ledger (lịch sử công khai)

```http
GET /rest/v1/public_ledger?select=*&order=created_at.desc&limit=20&offset=0
```

**Response `200`:**

```json
[
  {
    "contract_id": "30000000-...",
    "contract_type_name": "RPS Casual Lobby 2",
    "contract_type": "rps",
    "contract_status": "created",
    "is_on_chain": false,
    "created_at": "2026-03-22T11:19:30.535072+00:00",
    "parties": [
      { "role": "worker", "user_id": "...", "escrow_type": "ix_point", "escrow_amount": 1520.0 },
      { "role": "client", "user_id": "...", "escrow_type": "ix_point", "escrow_amount": 1520.0 }
    ],
    "result": null,
    "settlements": null
  }
]
```

---

#### POST — Consent (đồng ý kết quả)

```http
POST /rest/v1/contract_consents
Prefer: return=representation
```

**Request:**

```json
{
  "contract_id": "30000000-0000-0000-0000-000000000001",
  "user_id": "10000000-0000-0000-0000-000000000002",
  "consented": true
}
```

**Response `201`:**

```json
[
  {
    "id": "auto-generated-uuid",
    "contract_id": "30000000-...",
    "user_id": "10000000-...",
    "consented": true,
    "reason": null,
    "signature": null,
    "consented_at": "2026-03-27T10:00:00.000000+00:00"
  }
]
```

---

#### POST — Dispute (khiếu nại kết quả)

```http
POST /rest/v1/contract_consents
Prefer: return=representation
```

**Request:**

```json
{
  "contract_id": "30000000-0000-0000-0000-000000000001",
  "user_id": "10000000-0000-0000-0000-000000000002",
  "consented": false,
  "reason": "Tôi không đồng ý kết quả, có vấn đề về lag"
}
```

---

## 5. RPC Functions

> Business logic phức tạp (escrow, state transitions, balance updates). **FE gọi RPC, không thao tác trực tiếp trên tables.**

### 5.1 `register_player`

Đăng ký player mới → tạo 2 records `point_balances`.

```http
POST /rest/v1/rpc/register_player
```

**Request:**

```json
{
  "p_user_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "p_starting_ix_points": 1000,
  "p_welcome_free_points": 500
}
```

| Param | Type | Required | Mô tả |
|-------|------|----------|-------|
| `p_user_id` | uuid | **Yes** | User ID |
| `p_starting_ix_points` | numeric | No | IX Points ban đầu |
| `p_welcome_free_points` | numeric | No | Free Points chào mừng |

---

### 5.2 `create_contract`

Tạo contract instance mới từ template.

```http
POST /rest/v1/rpc/create_contract
```

**Request:**

```json
{
  "p_template_id": "20000000-0000-0000-0000-000000000001",
  "p_metadata": { "room_id": "room-abc-123", "game_mode": "casual" }
}
```

| Param | Type | Required | Mô tả |
|-------|------|----------|-------|
| `p_template_id` | uuid | **Yes** | Template nào |
| `p_metadata` | jsonb | No | Data mở rộng |

**Response:** UUID contract instance mới.

**Nội bộ:** Kiểm tra template active → tạo instance `status = created` → set `chain_record` theo policy.

---

### 5.3 `join_contract`

Tham gia contract — **trừ point**, tạo record parties.

```http
POST /rest/v1/rpc/join_contract
```

**Request:**

```json
{
  "p_contract_id": "30000000-0000-0000-0000-000000000001",
  "p_user_id": "10000000-0000-0000-0000-000000000002",
  "p_role": "challenger",
  "p_escrow_amount": 50,
  "p_escrow_type": "ix_point",
  "p_chain_record_choice": null
}
```

| Param | Type | Required | Mô tả |
|-------|------|----------|-------|
| `p_contract_id` | uuid | **Yes** | Contract nào |
| `p_user_id` | uuid | **Yes** | User join |
| `p_role` | varchar | **Yes** | `challenger` · `opponent` · `worker` · `client` · `participant` |
| `p_escrow_amount` | numeric | **Yes** | Số point ký quỹ |
| `p_escrow_type` | point_type | **Yes** | `ix_point` hoặc `ix_free_point` |
| `p_chain_record_choice` | boolean | No | Chỉ khi template policy = `optional` |

**Nội bộ:** Kiểm tra status = `created` → kiểm tra chưa join → kiểm tra balance đủ → kiểm tra bet trong [min_bet, max_bet] → trừ balance → tạo party `escrow_status = held`.

---

### 5.4 `activate_contract`

Kích hoạt contract khi đủ người.

```http
POST /rest/v1/rpc/activate_contract
```

**Request:**

```json
{
  "p_contract_id": "30000000-0000-0000-0000-000000000001"
}
```

| Param | Type | Required | Mô tả |
|-------|------|----------|-------|
| `p_contract_id` | uuid | **Yes** | Contract nào |

**Nội bộ:** Kiểm tra status = `created` → kiểm tra đủ parties → status → `active`, set `activated_at`.

---

### 5.5 `settle_contract`

Thanh toán — chuyển point cho winner, thu phí.

```http
POST /rest/v1/rpc/settle_contract
```

**Request:**

```json
{
  "p_contract_id": "30000000-0000-0000-0000-000000000001"
}
```

| Param | Type | Required | Mô tả |
|-------|------|----------|-------|
| `p_contract_id` | uuid | **Yes** | Contract nào |

**Nội bộ:**

```
1. Đọc result (is_final = true)
2. Tính:
   - total_escrow = tổng escrow_amount các parties
   - fee = total_escrow × fee_rate / 100
   - winner_amount = total_escrow - fee
3. Nếu draw: refund hết, fee = 0
4. Tạo settlement records:
   - reward: Escrow → Winner
   - fee: Escrow → Treasury
   - refund: Escrow → User (nếu draw)
5. Cập nhật point_balances
6. Status → settled, set settled_at
```

**Ví dụ thực tế (2 players × 60 pts, fee 5%):**

| Settlement | From | To | Amount | Fee |
|-----------|------|-----|--------|-----|
| `reward` | Escrow (`000...000`) | Winner | 114.0 | 6.0 |

---

## 6. Realtime Subscriptions

FE subscribe WebSocket để nhận live updates:

```javascript
// Theo dõi trạng thái 1 contract
supabase
  .channel('my-contract')
  .on('postgres_changes', {
    event: 'UPDATE',
    schema: 'public',
    table: 'contract_instances',
    filter: `id=eq.${contractId}`
  }, (payload) => {
    // payload.new.status → 'active', 'completed', 'settled'...
  })
  .subscribe()

// Có người join
supabase
  .channel('party-joins')
  .on('postgres_changes', {
    event: 'INSERT',
    schema: 'public',
    table: 'contract_parties',
    filter: `contract_id=eq.${contractId}`
  }, (payload) => {
    // payload.new → { user_id, role, escrow_amount }
  })
  .subscribe()

// Balance thay đổi
supabase
  .channel('my-balance')
  .on('postgres_changes', {
    event: 'UPDATE',
    schema: 'public',
    table: 'point_balances',
    filter: `user_id=eq.${userId}`
  }, (payload) => {
    // payload.new.balance → số dư mới
  })
  .subscribe()
```

---

## 7. Full Flow Example

### RPS Match: Player A vs Player B, bet 50 pts, fee 3%

```
Step  Ai gọi   API                                                  Kết quả
────  ───────  ───────────────────────────────────────────────────   ────────────────────
 1    FE       GET /contract_templates?is_active=eq.true&type=eq.rps  Danh sách lobby
 2    FE       POST /rpc/create_contract { template_id }              → status: created
 3    FE       POST /rpc/join_contract { user_A, challenger, 50 }     A bị trừ 50 pts
 4    FE       POST /rpc/join_contract { user_B, opponent, 50 }       B bị trừ 50 pts
 5    FE       POST /rpc/activate_contract { contract_id }            → status: active
 6    Server   POST /contract_results { result_data, is_final:true }  → status: completed
 7    FE       POST /contract_consents { user_A, consented:true }     A đồng ý
 8    FE       POST /contract_consents { user_B, consented:true }     B đồng ý
 9    FE       POST /rpc/settle_contract { contract_id }              → status: settled
10    FE       GET /public_ledger?contract_id=eq.{id}                 Xem kết quả
```

**Kết quả thanh toán (B thắng):**

| | From | To | Amount |
|--|------|-----|--------|
| Reward | Escrow | Player B | 97 pts |
| Fee | Escrow | Treasury | 3 pts |

**Kết quả thanh toán (hòa):**

| | From | To | Amount |
|--|------|-----|--------|
| Refund | Escrow | Player A | 50 pts |
| Refund | Escrow | Player B | 50 pts |

---

## 8. FE Integration Code

### Setup

```bash
npm install @supabase/supabase-js
```

```typescript
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://veoillsstewpnvmhxmlx.supabase.co',
  '<ANON_KEY>'
)
```

### Ví dụ sử dụng

```typescript
// Lấy templates
const { data: templates } = await supabase
  .from('contract_templates')
  .select('*')
  .eq('is_active', true)

// Tạo contract
const { data: contractId } = await supabase.rpc('create_contract', {
  p_template_id: 'template-uuid',
  p_metadata: { room_id: 'room-123' }
})

// Join contract
const { error } = await supabase.rpc('join_contract', {
  p_contract_id: contractId,
  p_user_id: userId,
  p_role: 'challenger',
  p_escrow_amount: 50,
  p_escrow_type: 'ix_point'
})

// Lấy balance
const { data: balances } = await supabase
  .from('point_balances')
  .select('*')
  .eq('user_id', userId)

// Lấy contract chi tiết kèm relations
const { data: contract } = await supabase
  .from('contract_instances')
  .select(`
    *,
    contract_templates(name, type, conditions, fee_rate),
    contract_parties(user_id, role, escrow_amount, escrow_status),
    contract_results(result_data, is_final),
    contract_consents(user_id, consented)
  `)
  .eq('id', contractId)
  .single()
```

---

## 9. Error Handling

### HTTP Status Codes

| Code | Ý nghĩa | FE xử lý |
|------|---------|----------|
| `200` | OK | Thành công |
| `201` | Created | Record mới tạo |
| `400` | Bad Request | Sai params |
| `401` | Unauthorized | Token hết hạn → refresh |
| `403` | Forbidden | Không có quyền |
| `409` | Conflict | Duplicate / constraint |
| `422` | Unprocessable | RPC raise exception |

### Error Response

```json
{
  "code": "PGRST116",
  "details": null,
  "hint": null,
  "message": "The result contains 0 rows"
}
```

### Xử lý error từ RPC

```typescript
const { data, error } = await supabase.rpc('join_contract', { ... })

if (error) {
  // error.message có thể là:
  // "Insufficient balance"    → Không đủ point
  // "Contract not found"      → Hợp đồng không tồn tại
  // "Already joined"          → Đã tham gia rồi
  // "Bet out of range"        → Số bet ngoài min/max
  // "Template not active"     → Template đã tắt
  console.error(error.message)
}
```

---

## 10. FE UI Requirements (từ Spec)

### 10.1 Blockchain Recording — Hiển thị theo policy

Hệ thống ghi blockchain có **2 cấp**: Admin đặt policy trên template → User chọn khi join (nếu `optional`).

**FE cần hiển thị khác nhau tùy `chain_record_policy` của template:**

| Policy | FE hiển thị | User interaction |
|--------|------------|------------------|
| `required` | Notice: "Hợp đồng này sẽ được ghi trên blockchain" | Không có toggle, chỉ thông báo |
| `optional` | Toggle/checkbox: "Ghi hợp đồng lên blockchain" + text từ `chain_record_description` | User bật/tắt → truyền vào `p_chain_record_choice` khi join |
| `off` | **Không hiển thị gì** | Không có |

**Logic xác định `chain_record` trên instance:**

| Template Policy | User Choice | `chain_record` |
|----------------|-------------|-----------------|
| `required` | *(không có)* | `true` |
| `optional` | `true` | `true` |
| `optional` | `false` | `false` |
| `optional` | `null` (không chọn) | `false` |
| `off` | *(không có)* | `false` |

> **Lưu ý:** Chọn ghi on-chain có thể phát sinh phí gas (TBD). Thay đổi policy KHÔNG ảnh hưởng các contract đã tạo, chỉ áp dụng cho contract mới.

### 10.2 Contract Lifecycle — Hiển thị trạng thái

```
Created   → "Đang chờ người chơi"
Active    → "Đang diễn ra"
Completed → "Đã có kết quả — chờ xác nhận"
Disputed  → "Đang khiếu nại — chờ admin xử lý"
Resolved  → "Khiếu nại đã giải quyết — chờ thanh toán"
Settled   → "Đã hoàn tất"
```

### 10.3 Result & Consent Flow — FE cần xử lý

**Normal Flow:**

```
1. Server báo kết quả  → FE nhận realtime update (status → completed)
2. Hiển thị kết quả    → "Bạn thắng/thua/hòa"
3. Hiển thị nút        → [Đồng ý kết quả] hoặc [Khiếu nại]
4. User nhấn Đồng ý    → POST /contract_consents { consented: true }
5. Cả 2 đồng ý         → Có thể settle
6. Nếu timeout (timeout_seconds từ template conditions)
   → Tự động consent (backend xử lý)
```

**Dispute Flow:**

```
1. User nhấn Khiếu nại  → Hiển thị form nhập lý do
2. Submit               → POST /contract_consents { consented: false, reason: "..." }
3. Status → disputed     → Hiển thị: "Đang chờ admin xử lý"
4. Admin resolve         → Status → resolved → settled
5. FE nhận realtime      → Hiển thị kết quả cuối cùng
```

### 10.4 Public Ledger — Hiển thị công khai

Trang public ledger cần hiển thị:

| Field | Hiển thị |
|-------|---------|
| Contract ID | ID (có thể rút gọn) |
| Contract type | RPS, Work Reward, Tournament... |
| Parties | User IDs (cân nhắc ẩn danh — TBD) |
| Point transfer amount | Số IX Points / Free Points chuyển |
| Timestamps | Thời điểm mỗi lần đổi trạng thái |
| Result / Status | Trạng thái hiện tại và kết quả cuối |

### 10.5 Admin Dashboard — Template Management

Màn tạo/sửa template cần:

- Form fields cho tất cả columns trong `contract_templates`
- **Section "Blockchain Recording"**:
  - Radio button hoặc select: `required` / `optional` / `off`
  - Khi chọn `optional`: hiển thị thêm text field cho `chain_record_description` (text hiển thị cho user)
- **Chỉ Admin mới được tạo/sửa template**

### 10.6 Settlement Calculation

```
Total Escrow = tổng escrow_amount của tất cả parties
Fee          = Total Escrow × (fee_rate / 100)
Winner Gets  = Total Escrow - Fee

Ví dụ: 2 players × 50 pts, fee_rate = 5%
  Total Escrow = 100
  Fee          = 100 × 0.05 = 5
  Winner Gets  = 100 - 5 = 95
  Treasury     = 5

Nếu Draw (và draw_refund = true):
  Refund mỗi player = escrow_amount gốc
  Fee = 0
```

---

## 11. Open Items (TBD)

> Các item chưa được quyết định từ spec. FE **không nên hardcode** các giá trị này — lấy từ DB/API.

| Item | Chi tiết | FE ảnh hưởng |
|------|---------|--------------|
| Fee rates | Phí tùy loại contract (hiện tại `fee_rate` trên template) | Đọc từ template, không hardcode |
| Objection period | Thời gian chờ auto-consent (hiện tại `timeout_seconds` trong conditions) | Đọc từ template conditions |
| Anonymization level | Mức độ ẩn danh user trên public ledger | Chờ quyết định, có thể cần mask user_id |
| Free Point restrictions | Giới hạn contract cho Free Points | Chờ quyết định, check `payment_type` trên template |
| On-chain recording cost | Ai trả phí gas khi user chọn ghi on-chain | Chờ quyết định, có thể cần hiển thị chi phí |
| Templates beyond RPS | Định nghĩa conditions cho work_reward, tournament | Sẽ bổ sung thêm template types |
