# IX Metaverse — Database & API Design

| Item | Details |
|------|---------|
| Document ID | IX-API-FRONTEND-001 |
| Version | 1.0.0 |
| Created | 2026-03-27 |
| Author | Vo Le (Backend Lead) |
| Audience | Frontend Development Team |
| Status | Active |

---

## Table of Contents

1. [Overview](#1-overview)
2. [Authentication](#2-authentication)
3. [Database Schema](#3-database-schema)
4. [REST API Reference](#4-rest-api-reference)
5. [RPC Functions (Business Logic)](#5-rpc-functions-business-logic)
6. [Realtime Subscriptions](#6-realtime-subscriptions)
7. [Contract Lifecycle & Flow](#7-contract-lifecycle--flow)
8. [Frontend Integration Guide](#8-frontend-integration-guide)
9. [Error Handling](#9-error-handling)
10. [Appendix](#10-appendix)

---

## 1. Overview

### 1.1 System Architecture

```
┌──────────────┐         ┌──────────────────────────────────────────┐
│   Frontend   │ ──────> │           Supabase Cloud                 │
│  (React/Vue) │ <────── │                                          │
└──────────────┘         │  ┌─────────────┐   ┌─────────────────┐  │
       │                 │  │  PostgREST   │   │   PostgreSQL    │  │
       │  REST API       │  │  (Auto API)  │──>│   (Database)    │  │
       │  WebSocket      │  └─────────────┘   └─────────────────┘  │
       │                 │  ┌─────────────┐   ┌─────────────────┐  │
       └────────────────>│  │  Realtime    │   │  Auth (GoTrue)  │  │
                         │  │  (WebSocket) │   │  (JWT + Users)  │  │
                         │  └─────────────┘   └─────────────────┘  │
                         └──────────────────────────────────────────┘
```

### 1.2 Base Information

| Item | Value |
|------|-------|
| Project URL | `https://veoillsstewpnvmhxmlx.supabase.co` |
| REST API Base | `https://veoillsstewpnvmhxmlx.supabase.co/rest/v1` |
| Realtime URL | `wss://veoillsstewpnvmhxmlx.supabase.co/realtime/v1` |
| API Format | JSON (application/json) |
| Database | PostgreSQL 14.4 |

### 1.3 Enum Types

Các enum types được sử dụng xuyên suốt hệ thống:

| Enum | Values | Mô tả |
|------|--------|-------|
| `contract_type` | `rps` · `work_reward` · `tournament` · `custom` | Loại hợp đồng |
| `contract_status` | `created` · `active` · `completed` · `disputed` · `resolved` · `settled` | Trạng thái lifecycle |
| `payment_type` | `ix_point` · `ix_free_point` · `both` | Loại thanh toán template chấp nhận |
| `point_type` | `ix_point` · `ix_free_point` | Loại point cụ thể |
| `chain_record_policy` | `required` · `optional` · `off` | Chính sách ghi blockchain |
| `result_source` | `system` · `user` | Nguồn báo kết quả |

---

## 2. Authentication

### 2.1 Required Headers

Mọi request đến Supabase API cần **2 headers**:

```http
apikey: <SUPABASE_ANON_KEY>
Authorization: Bearer <USER_JWT_TOKEN>
```

| Header | Nguồn | Mô tả |
|--------|-------|-------|
| `apikey` | Anon Key (public) | Embed trực tiếp trong FE code. Dùng cho mọi request |
| `Authorization` | JWT Token | Lấy sau khi user đăng nhập qua Supabase Auth |

### 2.2 Auth Flow

```
1. User đăng nhập  →  supabase.auth.signInWithPassword({ email, password })
2. Nhận JWT token  →  session.access_token
3. Gắn vào mọi request  →  Authorization: Bearer <token>
4. Token hết hạn   →  supabase.auth.refreshSession()
```

> **Lưu ý:** Supabase JS Client tự động xử lý việc gắn headers và refresh token. Chỉ cần cấu hình `createClient()` đúng là đủ.

---

## 3. Database Schema

### 3.1 Entity Relationship Diagram

```
┌─────────────────────┐
│  contract_templates  │
│  (Admin quản lý)     │
└──────────┬──────────┘
           │ 1:N
           ▼
┌─────────────────────┐       ┌──────────────────┐
│  contract_instances  │──────>│  contract_results │
│  (Hợp đồng cụ thể)  │  1:N  │  (Kết quả)       │
└──────────┬──────────┘       └──────────────────┘
           │
     ┌─────┼─────────────────┐
     │ 1:N │ 1:N             │ 1:N
     ▼     ▼                 ▼
┌──────────────┐  ┌──────────────────┐  ┌───────────────────────┐
│  contract_   │  │  contract_       │  │  contract_            │
│  parties     │  │  consents        │  │  settlements          │
│  (Tham gia)  │  │  (Đồng thuận)   │  │  (Thanh toán)         │
└──────────────┘  └──────────────────┘  └───────────────────────┘

                  ┌──────────────────┐
                  │  point_balances   │  (Số dư user — standalone)
                  └──────────────────┘

                  ┌──────────────────┐
                  │  public_ledger    │  (VIEW — read-only, tổng hợp)
                  └──────────────────┘
```

### 3.2 Table Definitions

#### `contract_templates`

> Template hợp đồng do Admin tạo và quản lý. Mỗi template định nghĩa 1 loại hợp đồng.

| Column | Type | Null | Default | Description |
|--------|------|------|---------|-------------|
| `id` | `uuid` | **PK** | `gen_random_uuid()` | Template ID |
| `name` | `varchar` | NOT NULL | — | Tên template hiển thị |
| `description` | `text` | NULL | — | Mô tả chi tiết |
| `type` | `contract_type` | NOT NULL | — | Loại hợp đồng |
| `conditions` | `jsonb` | NOT NULL | — | Điều kiện hợp đồng *(xem mục 3.3)* |
| `reward_rules` | `jsonb` | NOT NULL | — | Quy tắc thưởng *(xem mục 3.3)* |
| `payment_type` | `payment_type` | NOT NULL | `'both'` | Loại point chấp nhận |
| `fee_rate` | `numeric` | NOT NULL | `5.0` | Phí platform (%). VD: `5.00` = 5% |
| `chain_record_policy` | `chain_record_policy` | NOT NULL | `'off'` | Chính sách ghi blockchain |
| `chain_record_description` | `text` | NULL | — | Text hiển thị khi policy = `optional` |
| `is_active` | `boolean` | NOT NULL | `false` | Template đang hoạt động? |
| `metaverse_event_id` | `varchar` | NULL | — | ID event metaverse liên kết |
| `created_by` | `uuid` | NOT NULL | — | Admin user ID |
| `created_at` | `timestamptz` | NOT NULL | `now()` | Thời điểm tạo |
| `updated_at` | `timestamptz` | NOT NULL | `now()` | Thời điểm cập nhật cuối |

---

#### `contract_instances`

> Instance hợp đồng cụ thể, được tạo từ template. Chứa trạng thái lifecycle.

| Column | Type | Null | Default | Description |
|--------|------|------|---------|-------------|
| `id` | `uuid` | **PK** | `gen_random_uuid()` | Instance ID |
| `template_id` | `uuid` | **FK** | — | → `contract_templates.id` |
| `status` | `contract_status` | NOT NULL | `'created'` | Trạng thái hiện tại |
| `chain_record` | `boolean` | NOT NULL | `false` | Có ghi on-chain không |
| `tx_hash` | `varchar` | NULL | — | MegaETH transaction hash (Phase 1+) |
| `metadata` | `jsonb` | NULL | — | Data mở rộng: game room, match details... |
| `created_at` | `timestamptz` | NOT NULL | `now()` | |
| `activated_at` | `timestamptz` | NULL | — | Thời điểm đủ người, bắt đầu |
| `completed_at` | `timestamptz` | NULL | — | Thời điểm có kết quả |
| `settled_at` | `timestamptz` | NULL | — | Thời điểm thanh toán xong |

---

#### `contract_parties`

> Các bên tham gia hợp đồng. Mỗi user join sẽ tạo 1 record.

| Column | Type | Null | Default | Description |
|--------|------|------|---------|-------------|
| `id` | `uuid` | **PK** | `gen_random_uuid()` | |
| `contract_id` | `uuid` | **FK** | — | → `contract_instances.id` |
| `user_id` | `uuid` | NOT NULL | — | User tham gia |
| `role` | `varchar` | NOT NULL | — | Vai trò *(xem bảng roles bên dưới)* |
| `escrow_amount` | `numeric` | NOT NULL | `0` | Số point ký quỹ |
| `escrow_type` | `point_type` | NOT NULL | — | Loại point ký quỹ |
| `escrow_status` | `varchar` | NOT NULL | `'held'` | `held` · `released` · `refunded` |
| `chain_record_choice` | `boolean` | NULL | — | User chọn ghi on-chain (khi policy = `optional`) |
| `joined_at` | `timestamptz` | NOT NULL | `now()` | |

**Roles theo loại hợp đồng:**

| Contract Type | Roles |
|---------------|-------|
| `rps` | `challenger` · `opponent` |
| `work_reward` | `worker` · `client` |
| `tournament` | `participant` · `organizer` |
| `custom` | Tùy định nghĩa |

---

#### `contract_results`

> Kết quả của hợp đồng. Thường do game server (system) submit.

| Column | Type | Null | Default | Description |
|--------|------|------|---------|-------------|
| `id` | `uuid` | **PK** | `gen_random_uuid()` | |
| `contract_id` | `uuid` | **FK** | — | → `contract_instances.id` |
| `result_data` | `jsonb` | NOT NULL | — | Kết quả JSON *(xem mục 3.3)* |
| `reported_by` | `result_source` | NOT NULL | `'system'` | `system` hoặc `user` |
| `reporter_id` | `uuid` | NULL | — | ID người/system báo kết quả |
| `is_final` | `boolean` | NOT NULL | `false` | `true` = kết quả chính thức, dùng để settle |
| `reported_at` | `timestamptz` | NOT NULL | `now()` | |
| `finalized_at` | `timestamptz` | NULL | — | Thời điểm finalize |

---

#### `contract_consents`

> Đồng thuận hoặc khiếu nại của các bên sau khi có kết quả.

| Column | Type | Null | Default | Description |
|--------|------|------|---------|-------------|
| `id` | `uuid` | **PK** | `gen_random_uuid()` | |
| `contract_id` | `uuid` | **FK** | — | → `contract_instances.id` |
| `user_id` | `uuid` | NOT NULL | — | User đồng thuận |
| `consented` | `boolean` | NOT NULL | — | `true` = đồng ý · `false` = khiếu nại |
| `reason` | `text` | NULL | — | Lý do khiếu nại (bắt buộc khi `consented = false`) |
| `signature` | `varchar` | NULL | — | EIP-712 wallet signature (Phase 1+) |
| `consented_at` | `timestamptz` | NOT NULL | `now()` | |

---

#### `contract_settlements`

> Các giao dịch chuyển point khi thanh toán hợp đồng.

| Column | Type | Null | Default | Description |
|--------|------|------|---------|-------------|
| `id` | `uuid` | **PK** | `gen_random_uuid()` | |
| `contract_id` | `uuid` | **FK** | — | → `contract_instances.id` |
| `from_user_id` | `uuid` | NOT NULL | — | Người gửi *(xem System UUIDs)* |
| `to_user_id` | `uuid` | NOT NULL | — | Người nhận *(xem System UUIDs)* |
| `amount` | `numeric` | NOT NULL | — | Số point chuyển |
| `point_type` | `point_type` | NOT NULL | — | `ix_point` · `ix_free_point` |
| `settlement_type` | `varchar` | NOT NULL | `'reward'` | `reward` · `fee` · `refund` |
| `fee_amount` | `numeric` | NOT NULL | `0` | Phí platform |
| `tx_hash` | `varchar` | NULL | — | Transaction hash (Phase 1+) |
| `settled_at` | `timestamptz` | NOT NULL | `now()` | |

**System UUIDs:**

| UUID | Vai trò | Mô tả |
|------|---------|-------|
| `00000000-0000-0000-0000-000000000000` | **ESCROW** | Hệ thống ký quỹ — giữ point khi user join |
| `00000000-0000-0000-0000-000000000001` | **TREASURY** | Ngân quỹ platform — nhận phí |

---

#### `point_balances`

> Số dư point hiện tại của mỗi user. Mỗi user có tối đa 2 records (1 per point_type).

| Column | Type | Null | Default | Description |
|--------|------|------|---------|-------------|
| `id` | `uuid` | **PK** | `gen_random_uuid()` | |
| `user_id` | `uuid` | NOT NULL | — | User ID |
| `point_type` | `point_type` | NOT NULL | — | `ix_point` · `ix_free_point` |
| `balance` | `numeric` | NOT NULL | `0` | Số dư hiện tại |
| `updated_at` | `timestamptz` | NOT NULL | `now()` | |

---

#### `public_ledger` *(VIEW — Read-only)*

> View tổng hợp thông tin contract cho public transparency. Không thể INSERT/UPDATE/DELETE.

| Column | Type | Description |
|--------|------|-------------|
| `contract_id` | `uuid` | Contract instance ID |
| `contract_type_name` | `varchar` | Tên loại hợp đồng (từ template) |
| `contract_type` | `contract_type` | Enum loại |
| `contract_status` | `contract_status` | Trạng thái hiện tại |
| `is_on_chain` | `boolean` | Có ghi on-chain không |
| `created_at` | `timestamptz` | |
| `activated_at` | `timestamptz` | |
| `completed_at` | `timestamptz` | |
| `settled_at` | `timestamptz` | |
| `tx_hash` | `varchar` | Transaction hash |
| `parties` | `jsonb` | Array các bên tham gia |
| `result` | `jsonb` | Kết quả |
| `settlements` | `jsonb` | Array các giao dịch thanh toán |

---

### 3.3 JSONB Field Structures

#### `conditions` (trong contract_templates)

```json
{
  "min_bet": 10,
  "max_bet": 1000,
  "rounds": 1,
  "timeout_seconds": 15,
  "max_parties": 2
}
```

#### `reward_rules` (trong contract_templates)

```json
{
  "winner_percentage": 100,
  "draw_refund": true,
  "fee_from": "winner"
}
```

#### `result_data` (trong contract_results)

```json
{
  "winner_id": "uuid-of-winner",
  "loser_id": "uuid-of-loser",
  "is_draw": false,
  "scores": { "player_a": 1, "player_b": 0 },
  "moves": ["rock", "scissors"],
  "rounds_played": 1
}
```

#### `metadata` (trong contract_instances)

```json
{
  "room_id": "room-abc-123",
  "game_mode": "casual",
  "region": "asia"
}
```

---

## 4. REST API Reference

### 4.1 Endpoints Overview

| Endpoint | Methods | RLS | Mô tả |
|----------|---------|-----|-------|
| `/contract_templates` | GET · POST · PATCH · DELETE | Yes | Template CRUD (Admin) |
| `/contract_instances` | GET · POST · PATCH · DELETE | Yes | Instance CRUD |
| `/contract_parties` | GET · POST · PATCH · DELETE | Yes | Parties CRUD |
| `/contract_results` | GET · POST · PATCH · DELETE | Yes | Results CRUD |
| `/contract_consents` | GET · POST · PATCH · DELETE | Yes | Consents CRUD |
| `/contract_settlements` | GET · POST · PATCH · DELETE | Yes | Settlements CRUD |
| `/point_balances` | GET · POST · PATCH · DELETE | Yes | Balances CRUD |
| `/public_ledger` | GET | No | Public view (read-only) |

> **Lưu ý quan trọng:** Đối với các thao tác business logic (tạo contract, join, settle...), **luôn dùng RPC Functions** (mục 5) thay vì gọi CRUD trực tiếp. CRUD chỉ dùng để đọc dữ liệu.

### 4.2 Query Syntax

#### Filtering (WHERE)

| Operator | Ý nghĩa | Ví dụ |
|----------|---------|-------|
| `eq` | `=` | `?status=eq.active` |
| `neq` | `!=` | `?type=neq.custom` |
| `gt` | `>` | `?balance=gt.100` |
| `gte` | `>=` | `?fee_rate=gte.5` |
| `lt` | `<` | `?balance=lt.50` |
| `lte` | `<=` | `?escrow_amount=lte.1000` |
| `in` | `IN(...)` | `?status=in.(created,active)` |
| `is` | `IS NULL` | `?tx_hash=is.null` |
| `like` | `LIKE` | `?name=like.*RPS*` |
| `ilike` | `ILIKE` | `?name=ilike.*rps*` (case-insensitive) |

#### Selecting Columns

```http
# Chỉ lấy các cột cần thiết
GET /contract_templates?select=id,name,type,fee_rate,is_active

# Lấy kèm relation (JOIN)
GET /contract_instances?select=*,contract_templates(name,type,conditions)

# Nested relation
GET /contract_instances?select=*,contract_parties(*),contract_results(*)
```

#### Ordering

```http
# Sắp xếp theo created_at giảm dần
GET /public_ledger?select=*&order=created_at.desc

# Sắp xếp nhiều cột
GET /contract_templates?select=*&order=type.asc,created_at.desc
```

#### Pagination

```http
# Lấy 20 records, bỏ qua 40 records đầu (trang 3)
GET /public_ledger?select=*&limit=20&offset=40

# Đếm tổng records (thêm header)
# Header: Prefer: count=exact
# Response header: Content-Range: 0-19/156
```

### 4.3 Common Queries

```http
# 1. Lấy tất cả templates RPS đang active
GET /contract_templates?is_active=eq.true&type=eq.rps&select=*

# 2. Lấy contract instance theo ID kèm template + parties
GET /contract_instances?id=eq.{uuid}&select=*,contract_templates(name,type,conditions,fee_rate),contract_parties(user_id,role,escrow_amount,escrow_status)

# 3. Lấy tất cả contracts của 1 user (qua parties)
GET /contract_parties?user_id=eq.{uuid}&select=*,contract_instances(id,status,created_at,contract_templates(name,type))

# 4. Lấy balance của user
GET /point_balances?user_id=eq.{uuid}&select=*

# 5. Lấy lịch sử settlement của 1 contract
GET /contract_settlements?contract_id=eq.{uuid}&select=*&order=settled_at.asc

# 6. Public ledger — 50 contracts mới nhất đã settled
GET /public_ledger?contract_status=eq.settled&select=*&order=settled_at.desc&limit=50

# 7. Contracts đang active (realtime lobby)
GET /contract_instances?status=eq.created&select=*,contract_templates(name,type,conditions)&order=created_at.desc
```

---

## 5. RPC Functions (Business Logic)

> **Quan trọng:** Các function này xử lý business logic phức tạp (escrow, state transitions, balance updates...). Frontend **PHẢI** gọi RPC thay vì thao tác trực tiếp trên tables.

### 5.1 `register_player`

Đăng ký player mới — tạo 2 records `point_balances` (ix_point + ix_free_point).

```http
POST /rest/v1/rpc/register_player
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `p_user_id` | `uuid` | **Yes** | — | User ID (từ Auth) |
| `p_starting_ix_points` | `numeric` | No | *(DB default)* | IX Points khởi tạo |
| `p_welcome_free_points` | `numeric` | No | *(DB default)* | Free Points chào mừng |

**Request:**
```json
{
  "p_user_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "p_starting_ix_points": 1000,
  "p_welcome_free_points": 500
}
```

---

### 5.2 `create_contract`

Tạo contract instance mới từ template.

```http
POST /rest/v1/rpc/create_contract
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_template_id` | `uuid` | **Yes** | Template ID để tạo instance |
| `p_metadata` | `jsonb` | No | Data mở rộng (room_id, game_mode...) |

**Request:**
```json
{
  "p_template_id": "template-uuid-here",
  "p_metadata": {
    "room_id": "room-abc-123",
    "game_mode": "casual"
  }
}
```

**Response:** UUID của contract instance mới tạo.

**Logic nội bộ:**
1. Kiểm tra template `is_active = true`
2. Tạo record `contract_instances` với `status = 'created'`
3. Set `chain_record` dựa trên template policy

---

### 5.3 `join_contract`

Tham gia contract — ký quỹ point (escrow).

```http
POST /rest/v1/rpc/join_contract
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_contract_id` | `uuid` | **Yes** | Contract instance ID |
| `p_user_id` | `uuid` | **Yes** | User tham gia |
| `p_role` | `varchar` | **Yes** | Vai trò: `challenger` · `opponent` · `worker` · `client` · `participant` |
| `p_escrow_amount` | `numeric` | **Yes** | Số point ký quỹ |
| `p_escrow_type` | `point_type` | **Yes** | `ix_point` hoặc `ix_free_point` |
| `p_chain_record_choice` | `boolean` | No | Chọn ghi on-chain (chỉ khi template policy = `optional`) |

**Request:**
```json
{
  "p_contract_id": "contract-uuid-here",
  "p_user_id": "user-uuid-here",
  "p_role": "challenger",
  "p_escrow_amount": 50,
  "p_escrow_type": "ix_point",
  "p_chain_record_choice": null
}
```

**Logic nội bộ:**
1. Kiểm tra contract `status = 'created'`
2. Kiểm tra user chưa join contract này
3. Kiểm tra `balance >= escrow_amount`
4. Kiểm tra `escrow_amount` trong khoảng `[min_bet, max_bet]` của template
5. Trừ `point_balances` của user
6. Tạo record `contract_parties` với `escrow_status = 'held'`

---

### 5.4 `activate_contract`

Kích hoạt contract khi đủ số người tham gia.

```http
POST /rest/v1/rpc/activate_contract
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_contract_id` | `uuid` | **Yes** | Contract instance ID |

**Request:**
```json
{
  "p_contract_id": "contract-uuid-here"
}
```

**Logic nội bộ:**
1. Kiểm tra `status = 'created'`
2. Kiểm tra đủ số parties (VD: RPS cần 2 người)
3. Chuyển `status` → `'active'`
4. Set `activated_at = now()`

---

### 5.5 `settle_contract`

Thanh toán contract — chuyển point cho winner, thu phí platform.

```http
POST /rest/v1/rpc/settle_contract
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_contract_id` | `uuid` | **Yes** | Contract instance ID |

**Request:**
```json
{
  "p_contract_id": "contract-uuid-here"
}
```

**Logic nội bộ:**
1. Đọc `contract_results` có `is_final = true`
2. Tính fee: `fee = total_escrow × fee_rate / 100`
3. Tính winner amount: `winner_amount = total_escrow - fee`
4. Nếu `is_draw = true`: refund toàn bộ, fee = 0
5. Tạo records `contract_settlements`:
   - `settlement_type = 'reward'`: Escrow → Winner
   - `settlement_type = 'fee'`: Escrow → Treasury
   - `settlement_type = 'refund'`: Escrow → User (nếu draw)
6. Cập nhật `point_balances` tương ứng
7. Chuyển `status` → `'settled'`, set `settled_at = now()`

---

## 6. Realtime Subscriptions

### 6.1 Available Channels

FE có thể subscribe để nhận real-time updates qua WebSocket:

| Table | Events | Use Case |
|-------|--------|----------|
| `contract_instances` | INSERT · UPDATE | Theo dõi trạng thái contract |
| `contract_parties` | INSERT | Biết khi có người join |
| `contract_results` | INSERT | Nhận kết quả ngay khi có |
| `contract_consents` | INSERT | Theo dõi consent/dispute |
| `contract_settlements` | INSERT | Nhận thông báo thanh toán |
| `point_balances` | UPDATE | Cập nhật số dư realtime |

### 6.2 Code Examples

```javascript
// Subscribe thay đổi trạng thái 1 contract cụ thể
const channel = supabase
  .channel('my-contract')
  .on('postgres_changes', {
    event: 'UPDATE',
    schema: 'public',
    table: 'contract_instances',
    filter: `id=eq.${contractId}`
  }, (payload) => {
    console.log('Status changed:', payload.new.status)
  })
  .subscribe()

// Subscribe khi có người join contract
const partyChannel = supabase
  .channel('party-joins')
  .on('postgres_changes', {
    event: 'INSERT',
    schema: 'public',
    table: 'contract_parties',
    filter: `contract_id=eq.${contractId}`
  }, (payload) => {
    console.log('New player joined:', payload.new.user_id)
  })
  .subscribe()

// Subscribe balance updates cho user hiện tại
const balanceChannel = supabase
  .channel('my-balance')
  .on('postgres_changes', {
    event: 'UPDATE',
    schema: 'public',
    table: 'point_balances',
    filter: `user_id=eq.${userId}`
  }, (payload) => {
    console.log('Balance updated:', payload.new.balance)
  })
  .subscribe()

// Cleanup khi component unmount
supabase.removeChannel(channel)
```

---

## 7. Contract Lifecycle & Flow

### 7.1 State Machine

```
                    ┌─────────┐
                    │ Created │  ← create_contract()
                    └────┬────┘
                         │  activate_contract()
                         ▼
                    ┌─────────┐
                    │ Active  │  ← game đang diễn ra
                    └────┬────┘
                         │  submit result (is_final=true)
                         ▼
                    ┌──────────┐
               ┌───>│Completed │  ← chờ consent
               │    └────┬─────┘
               │         │
               │    ┌────┴─────┐
               │    ▼          ▼
               │  consent    dispute
               │  (true)     (false)
               │    │          │
               │    │     ┌────▼────┐
               │    │     │Disputed │  ← admin review
               │    │     └────┬────┘
               │    │          │  admin resolve
               │    │     ┌────▼────┐
               │    │     │Resolved │
               │    │     └────┬────┘
               │    │          │
               │    └────┬─────┘
               │         ▼
               │    ┌─────────┐
               │    │ Settled │  ← settle_contract()
               │    └─────────┘
               │
               └── (timeout auto-consent)
```

### 7.2 Complete RPS Flow Example

> **Scenario:** Player A (challenger) vs Player B (opponent), bet 50 IX Points, fee 5%.

```
Step  Action                    API Call                                          Status Change
────  ────────────────────────  ────────────────────────────────────────────────  ──────────────
 1    Lấy template RPS         GET /contract_templates?type=eq.rps               —
 2    Tạo contract              POST /rpc/create_contract                         → created
 3    Player A join (50 pts)   POST /rpc/join_contract                           —
 4    Player B join (50 pts)   POST /rpc/join_contract                           —
 5    Activate                  POST /rpc/activate_contract                       → active
 6    Game server báo kết quả  POST /contract_results (is_final=true)            → completed
 7    Player A consent          POST /contract_consents (consented=true)          —
 8    Player B consent          POST /contract_consents (consented=true)          —
 9    Settle                    POST /rpc/settle_contract                         → settled
10    Xem kết quả công khai    GET /public_ledger?contract_id=eq.{id}            —
```

**Kết quả thanh toán (B thắng):**

| Giao dịch | From | To | Amount | Type |
|-----------|------|-----|--------|------|
| Reward | Escrow | Player B | 95 pts | `reward` |
| Fee | Escrow | Treasury | 5 pts | `fee` |

**Kết quả thanh toán (hòa):**

| Giao dịch | From | To | Amount | Type |
|-----------|------|-----|--------|------|
| Refund | Escrow | Player A | 50 pts | `refund` |
| Refund | Escrow | Player B | 50 pts | `refund` |

---

## 8. Frontend Integration Guide

### 8.1 Install & Setup

```bash
npm install @supabase/supabase-js
```

```typescript
// lib/supabase.ts
import { createClient } from '@supabase/supabase-js'

const SUPABASE_URL = 'https://veoillsstewpnvmhxmlx.supabase.co'
const SUPABASE_ANON_KEY = '<ANON_KEY>'  // Lấy từ Settings → API

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
```

### 8.2 Common Operations

```typescript
// === AUTH ===

// Đăng nhập
const { data, error } = await supabase.auth.signInWithPassword({
  email: 'user@example.com',
  password: 'password123'
})

// Lấy user hiện tại
const { data: { user } } = await supabase.auth.getUser()


// === READ DATA ===

// Lấy templates active
const { data: templates } = await supabase
  .from('contract_templates')
  .select('*')
  .eq('is_active', true)
  .eq('type', 'rps')

// Lấy contract kèm relations
const { data: contract } = await supabase
  .from('contract_instances')
  .select(`
    *,
    contract_templates (name, type, conditions, fee_rate),
    contract_parties (user_id, role, escrow_amount, escrow_status),
    contract_results (result_data, is_final),
    contract_consents (user_id, consented)
  `)
  .eq('id', contractId)
  .single()

// Lấy balance
const { data: balances } = await supabase
  .from('point_balances')
  .select('*')
  .eq('user_id', userId)

// Public ledger
const { data: ledger, count } = await supabase
  .from('public_ledger')
  .select('*', { count: 'exact' })
  .order('created_at', { ascending: false })
  .range(0, 19)


// === RPC CALLS ===

// Tạo contract
const { data: contractId } = await supabase.rpc('create_contract', {
  p_template_id: templateId,
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

// Activate
await supabase.rpc('activate_contract', { p_contract_id: contractId })

// Consent
await supabase.from('contract_consents').insert({
  contract_id: contractId,
  user_id: userId,
  consented: true
})

// Settle
await supabase.rpc('settle_contract', { p_contract_id: contractId })
```

---

## 9. Error Handling

### 9.1 HTTP Status Codes

| Code | Meaning | Xử lý |
|------|---------|--------|
| `200` | Success | OK |
| `201` | Created | Record mới được tạo |
| `400` | Bad Request | Sai params, validation fail |
| `401` | Unauthorized | Token hết hạn → refresh |
| `403` | Forbidden | Không có quyền (RLS block) |
| `404` | Not Found | Resource không tồn tại |
| `409` | Conflict | Duplicate hoặc constraint violation |
| `422` | Unprocessable | RPC function raise exception |

### 9.2 Error Response Format

```json
{
  "code": "PGRST116",
  "details": null,
  "hint": null,
  "message": "The result contains 0 rows"
}
```

### 9.3 RPC Error Handling

```typescript
const { data, error } = await supabase.rpc('join_contract', { ... })

if (error) {
  switch (error.message) {
    case 'Insufficient balance':
      // Hiển thị: "Không đủ point"
      break
    case 'Contract not found':
      // Hiển thị: "Hợp đồng không tồn tại"
      break
    case 'Already joined':
      // Hiển thị: "Bạn đã tham gia hợp đồng này"
      break
    default:
      console.error('Unexpected error:', error)
  }
}
```

---

## 10. Appendix

### 10.1 Blockchain Recording Rules

| Template Policy | User Choice | `chain_record` | Mô tả |
|----------------|-------------|-----------------|--------|
| `required` | *(không có)* | `true` | Luôn ghi on-chain |
| `optional` | `true` | `true` | User chọn ghi |
| `optional` | `false` | `false` | User chọn không ghi |
| `optional` | `null` | `false` | User không chọn → mặc định off |
| `off` | *(không có)* | `false` | Không ghi on-chain |

**FE cần hiển thị:**
- `required`: Notice "Hợp đồng này sẽ được ghi trên blockchain" (không có toggle)
- `optional`: Toggle/checkbox "Ghi hợp đồng lên blockchain" + description từ `chain_record_description`
- `off`: Không hiển thị gì

### 10.2 Settlement Calculation

```
Total Escrow = sum(escrow_amount) của tất cả parties
Fee          = Total Escrow × (fee_rate / 100)
Winner Gets  = Total Escrow - Fee

Ví dụ: 2 players × 50 pts, fee_rate = 5%
  Total Escrow = 100
  Fee          = 100 × 0.05 = 5
  Winner Gets  = 100 - 5 = 95
  Treasury Gets = 5

Nếu Draw:
  Refund mỗi player = escrow_amount gốc
  Fee = 0
```

### 10.3 Supabase Dashboard

| URL | Mô tả |
|-----|-------|
| [Dashboard](https://supabase.com/dashboard) | Quản lý project |
| Settings → API | Lấy Project URL, Anon Key |
| Table Editor | Xem/sửa data trực tiếp |
| SQL Editor | Chạy SQL queries |
| Authentication | Quản lý users |
| API Docs | Auto-generated API documentation |
