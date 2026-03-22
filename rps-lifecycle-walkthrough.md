# Flow: Contract Lifecycle Engine
## Ví dụ: A và B chơi Oẳn tù tì, cược 50 IX Free Points

**Môi trường:** Supabase Cloud Production
**Base URL:** `https://veoillsstewpnvmhxmlx.supabase.co`

### Người chơi

| Vai trò | User ID | Email |
|---------|---------|-------|
| **A** (challenger) | `b176cb76-988e-4382-a7ed-d13d443fab5a` | lehongvi19x@gmail.com |
| **B** (opponent) | `f2b0eabb-6e9a-4e39-a3e9-5e9d991ac2db` | lehongvi19x@gmail.com (2) |

### Headers dùng cho mọi request

```
apikey: <ANON_KEY>
Authorization: Bearer <ANON_KEY>
Content-Type: application/json
``` 

---

## Trước khi bắt đầu — 3 API khởi động

### API 1 — Kiểm tra kết nối (Health check)

Kiểm tra REST API đang hoạt động và xem danh sách các tables có sẵn.

```bash
curl --location 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/' \
  --header 'apikey: <ANON_KEY>'
```

**Response:** Danh sách tất cả tables và views của project dưới dạng OpenAPI spec.

---

### API 2 — Đăng ký user mới (Sign up)

Tạo tài khoản mới qua Supabase Auth. Response trả về `user.id` — dùng ID này cho API 3.

```bash
curl --location 'https://veoillsstewpnvmhxmlx.supabase.co/auth/v1/signup' \
  --header 'apikey: <ANON_KEY>' \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "email": "lehongvi191x@gmail.com",
    "password": "PWdGtQTCnAPvnGmPDzvE"
  }'
```

**Response (200 OK):**
```json
{
  "access_token": "eyJhbGci...",
  "token_type": "bearer",
  "expires_in": 3600,
  "user": {
    "id": "USER_UUID",
    "email": "lehongvi191x@gmail.com",
    "email_confirmed_at": "2026-03-22T..."
  }
}
```

> Lưu lại `user.id` để dùng ở bước register_player bên dưới.

---

### API 3 — Khởi tạo ví điểm (register_player)

Tạo bản ghi `point_balances` cho user vừa đăng ký. **Bắt buộc gọi sau signup.**

```bash
curl --location 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/rpc/register_player' \
  --header 'apikey: <ANON_KEY>' \
  --header 'Authorization: Bearer <ANON_KEY>' \
  --header 'Content-Type: application/json' \
  --data '{ "p_user_id": "b176cb76-988e-4382-a7ed-d13d443fab5a" }'
```

**Response:** `204 No Content` → thành công.

**Verify ví đã được tạo:**
```bash
curl 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/point_balances?user_id=eq.b176cb76-988e-4382-a7ed-d13d443fab5a&select=point_type,balance' \
  --header 'apikey: <ANON_KEY>' \
  --header 'Authorization: Bearer <ANON_KEY>'
```

```json
[
  { "point_type": "ix_point",      "balance": 0.00   },
  { "point_type": "ix_free_point", "balance": 100.00 }
]
```

---

## Đăng ký user

**Khởi tạo ví điểm (register_player):**
```bash
# Đăng ký A
curl -X POST 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/rpc/register_player' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{ "p_user_id": "b176cb76-988e-4382-a7ed-d13d443fab5a" }'

# Đăng ký B
curl -X POST 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/rpc/register_player' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer sb_secret_kqs63im0zT4-L0_EpJ17sQ_kEeDcnJ5s' \
  -H 'Content-Type: application/json' \
  -d '{ "p_user_id": "f2b0eabb-6e9a-4e39-a3e9-5e9d991ac2db" }'
```

Response: `204 No Content` → thành công.

---

## Kiểm tra số dư trước khi chơi

```bash
# Số dư của A
curl 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/point_balances?user_id=eq.b176cb76-988e-4382-a7ed-d13d443fab5a&select=point_type,balance' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>'

# Số dư của B
curl 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/point_balances?user_id=eq.f2b0eabb-6e9a-4e39-a3e9-5e9d991ac2db&select=point_type,balance' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>'
```

**Kết quả hiện tại:**
```json
A: [{"point_type":"ix_free_point","balance":100.00}, {"point_type":"ix_point","balance":0.00}]
B: [{"point_type":"ix_free_point","balance":100.00}, {"point_type":"ix_point","balance":0.00}]
```

**Luồng tài chính — Ban đầu:**
```
A: 100 ix_free_point | B: 100 ix_free_point | Escrow: 0 | Treasury: 0
```

---

## Bước 1 — Event xảy ra trong metaverse

> A và B gặp nhau trong thế giới ảo và cùng bấm nút **"Chơi Oẳn tù tì"**.
> Server metaverse nhận sự kiện và bắt đầu khởi tạo contract.

Không cần gọi API ở bước này — đây là UI event trong metaverse.

---

## Bước 2 — Tìm template RPS

Hệ thống tìm template **"RPS Casual Lobby 1"** đã được admin cấu hình sẵn.

```bash
curl 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/contract_templates?type=eq.rps&is_active=eq.true&select=id,name,fee_rate,conditions,reward_rules&limit=1' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>'
```

**Response:**
```json
[{
  "id": "20000000-0000-0000-0000-000000000001",
  "name": "RPS Casual Lobby 1",
  "fee_rate": 3.00,
  "conditions": { "min_bet": 10, "max_bet": 100, "rounds": 1, "timeout_seconds": 15 },
  "reward_rules": { "winner_pct": 95, "draw_refund": true }
}]
```

Template ID: `20000000-0000-0000-0000-000000000001`
Phí nền tảng: **3%**

---

## Bước 3 — Tạo contract instance

> Trạng thái: **→ Created**

```bash
curl -X POST 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/rpc/create_contract' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "p_template_id": "20000000-0000-0000-0000-000000000001",
    "p_metadata": { "room_id": "rps-lobby-001", "session": "A-vs-B" }
  }'
```

**Response:** Contract ID mới
```json
"<CONTRACT_ID>"
```

> Lưu lại Contract ID này để dùng cho các bước tiếp theo.

**Verify trạng thái:**
```bash
curl 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/contract_instances?id=eq.<CONTRACT_ID>&select=id,status,created_at' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>'
```

```json
[{ "id": "<CONTRACT_ID>", "status": "created", "created_at": "2026-03-22T..." }]
```

---

## Bước 4 — Escrow (ký quỹ)

> A và B mỗi người nạp **50 ix_free_point** vào escrow.
> Điểm bị trừ ngay lập tức khỏi ví, giữ trong hệ thống đến khi có kết quả.

**A tham gia (challenger), nạp 50 điểm:**
```bash
curl -X POST 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/rpc/join_contract' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "p_contract_id": "<CONTRACT_ID>",
    "p_user_id": "b176cb76-988e-4382-a7ed-d13d443fab5a",
    "p_role": "challenger",
    "p_escrow_amount": 50,
    "p_escrow_type": "ix_free_point"
  }'
```

> A: 100 → **50** ix_free_point (50 bị khóa)

**B tham gia (opponent), nạp 50 điểm:**
```bash
curl -X POST 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/rpc/join_contract' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "p_contract_id": "<CONTRACT_ID>",
    "p_user_id": "f2b0eabb-6e9a-4e39-a3e9-5e9d991ac2db",
    "p_role": "opponent",
    "p_escrow_amount": 50,
    "p_escrow_type": "ix_free_point"
  }'
```

> B: 100 → **50** ix_free_point (50 bị khóa)

**Tổng escrow đang giữ: 100 ix_free_point**

**Kích hoạt contract (activate):**
```bash
curl -X POST 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/rpc/activate_contract' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{ "p_contract_id": "<CONTRACT_ID>" }'
```

> Trạng thái: Created → **Active**

**Verify escrow đang giữ:**
```bash
curl 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/contract_parties?contract_id=eq.<CONTRACT_ID>&select=user_id,role,escrow_amount,escrow_type,escrow_status' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>'
```

```json
[
  { "user_id": "b176cb76-...", "role": "challenger", "escrow_amount": 50, "escrow_type": "ix_free_point", "escrow_status": "held" },
  { "user_id": "f2b0eabb-...", "role": "opponent",   "escrow_amount": 50, "escrow_type": "ix_free_point", "escrow_status": "held" }
]
```

**Luồng tài chính — Sau khi ký quỹ:**
```
A: 50 | B: 50 | Escrow: 100 | Treasury: 0
```

---

## Bước 5 — Thực thi trận đấu

> A chọn **Kéo (Scissors)**, B chọn **Búa (Rock)** → Server xử lý kết quả → **B thắng**.

Server metaverse gửi kết quả lên hệ thống:

```bash
curl -X POST 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/contract_results' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -H 'Prefer: return=representation' \
  -d '{
    "contract_id": "<CONTRACT_ID>",
    "result_data": {
      "winner_id": "f2b0eabb-6e9a-4e39-a3e9-5e9d991ac2db",
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

**Cập nhật trạng thái sang Completed:**
```bash
curl -X PATCH 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/contract_instances?id=eq.<CONTRACT_ID>' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{ "status": "completed" }'
```

> Trạng thái: Active → **Completed**

---

## Bước 6 — Xác nhận kết quả (Consent)

Cả hai bên nhận thông báo và xác nhận kết quả.

**A xác nhận (chấp nhận thua):**
```bash
curl -X POST 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/contract_consents' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "contract_id": "<CONTRACT_ID>",
    "user_id": "b176cb76-988e-4382-a7ed-d13d443fab5a",
    "consented": true
  }'
```

**B xác nhận (chấp nhận thắng):**
```bash
curl -X POST 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/contract_consents' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "contract_id": "<CONTRACT_ID>",
    "user_id": "f2b0eabb-6e9a-4e39-a3e9-5e9d991ac2db",
    "consented": true
  }'
```

**Kiểm tra consent:**
```bash
curl 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/contract_consents?contract_id=eq.<CONTRACT_ID>&select=user_id,consented,consented_at' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>'
```

```json
[
  { "user_id": "b176cb76-...", "consented": true, "consented_at": "2026-03-22T..." },
  { "user_id": "f2b0eabb-...", "consented": true, "consented_at": "2026-03-22T..." }
]
```

> Nếu không có phản đối trong **15 giây** (timeout_seconds) → hệ thống tự động chấp nhận.
> Nếu A gửi `consented: false` kèm `reason` → chuyển sang **Disputed** để admin xử lý.

---

## Bước 7 — Settlement (thanh toán)

Toàn bộ phân bổ điểm được xử lý tự động bởi `settle_contract`.

```bash
curl -X POST 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/rpc/settle_contract' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{ "p_contract_id": "<CONTRACT_ID>" }'
```

> Trạng thái: Completed → **Settled**

**Hệ thống tự động thực hiện:**

```
Tổng escrow:      100 ix_free_point
Phí nền tảng 3%:   3 ix_free_point → Treasury
B (người thắng):  97 ix_free_point → f2b0eabb-...
A (người thua):    0 (đã mất escrow từ bước join)
```

**Luồng tài chính — Sau khi thanh toán:**
```
A: 50 | B: 50 + 97 = 147 | Escrow: 0 | Treasury: 3
```

---

## Kiểm tra kết quả cuối

**Số dư A (người thua):**
```bash
curl 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/point_balances?user_id=eq.b176cb76-988e-4382-a7ed-d13d443fab5a&point_type=eq.ix_free_point&select=balance' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>'
```
```json
[{ "balance": 50.00 }]
```

**Số dư B (người thắng):**
```bash
curl 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/point_balances?user_id=eq.f2b0eabb-6e9a-4e39-a3e9-5e9d991ac2db&point_type=eq.ix_free_point&select=balance' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>'
```
```json
[{ "balance": 147.00 }]
```

**Xem chi tiết settlements:**
```bash
curl 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/contract_settlements?contract_id=eq.<CONTRACT_ID>&select=to_user_id,amount,settlement_type,fee_amount' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>'
```

```json
[
  { "to_user_id": "f2b0eabb-...", "amount": 97.00, "settlement_type": "reward", "fee_amount": 0.00 },
  { "to_user_id": "00000000-0000-0000-0000-000000000001", "amount": 3.00, "settlement_type": "fee", "fee_amount": 3.00 }
]
```

---

## Xem trên Public Ledger (sổ cái công khai)

Bất kỳ ai cũng có thể xem contract này:

```bash
curl 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/public_ledger?contract_id=eq.<CONTRACT_ID>' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>'
```

```json
[{
  "contract_id": "<CONTRACT_ID>",
  "contract_type_name": "RPS Casual Lobby 1",
  "contract_type": "rps",
  "contract_status": "settled",
  "is_on_chain": false,
  "created_at": "2026-03-22T...",
  "activated_at": "2026-03-22T...",
  "completed_at": "2026-03-22T...",
  "settled_at": "2026-03-22T...",
  "tx_hash": null,
  "parties": [
    { "user_id": "b176cb76-...", "role": "challenger", "escrow_amount": 50, "escrow_type": "ix_free_point" },
    { "user_id": "f2b0eabb-...", "role": "opponent",   "escrow_amount": 50, "escrow_type": "ix_free_point" }
  ],
  "result": {
    "winner_id": "f2b0eabb-...",
    "winner_move": "rock",
    "loser_move": "scissors",
    "rounds_played": 1,
    "score": "1-0",
    "is_draw": false
  },
  "settlements": [
    { "from": "00000000-...-000000000000", "to": "f2b0eabb-...", "amount": 97, "point_type": "ix_free_point", "fee": 0 },
    { "from": "00000000-...-000000000000", "to": "00000000-...-000000000001", "amount": 3, "point_type": "ix_free_point", "fee": 3 }
  ]
}]
```

---

## Tóm tắt toàn bộ luồng

| Bước | Hành động | API | Ai gọi |
|------|-----------|-----|--------|
| 0 | Signup | `POST /auth/v1/signup` | Client |
| 0b | Khởi tạo ví | `POST /rpc/register_player` | Client (sau signup) |
| Pre | Kiểm tra số dư | `GET /point_balances?user_id=eq.{id}` | Client |
| 1 | Tìm template RPS | `GET /contract_templates?type=eq.rps&is_active=eq.true` | Server |
| 2 | Tạo contract | `POST /rpc/create_contract` | Server |
| 3a | A ký quỹ | `POST /rpc/join_contract` | Server |
| 3b | B ký quỹ | `POST /rpc/join_contract` | Server |
| 3c | Kích hoạt | `POST /rpc/activate_contract` | Server |
| 4 | Báo kết quả | `POST /contract_results` | Game server |
| 4b | Cập nhật completed | `PATCH /contract_instances?id=eq.{id}` | Game server |
| 5a | A đồng thuận | `POST /contract_consents` | Client |
| 5b | B đồng thuận | `POST /contract_consents` | Client |
| 6 | Thanh toán | `POST /rpc/settle_contract` | Server |
| 7 | Xem sổ cái | `GET /public_ledger?contract_id=eq.{id}` | Client / Bất kỳ ai |

---

## Luồng tài chính theo thời gian

| Thời điểm | A | B | Escrow | Treasury |
|-----------|---|---|--------|----------|
| Ban đầu | 100 | 100 | 0 | 0 |
| Sau ký quỹ | 50 | 50 | 100 | 0 |
| Sau thanh toán (B thắng) | 50 | 147 | 0 | 3 |

---

## Điểm quan trọng

- **Escrow trước khi chơi** — điểm bị khóa ngay khi join, không bên nào có thể gian lận hoặc từ chối trả sau khi thua
- **Phí tự động** — 3% được trừ và gửi về Treasury mà không cần can thiệp thủ công
- **Trạng thái immutable** — sau khi `settled`, contract không thể thay đổi
- **Public ledger** — mọi giao dịch đều công khai, ai cũng có thể kiểm tra
- **Phase 1 ready** — `tx_hash = null` hiện tại, sẽ có giá trị thật khi migrate lên MegaETH

---

## Nếu có tranh chấp (Dispute Flow)

Thay vì A gửi `consented: true`, A gửi dispute:

```bash
curl -X POST 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/contract_consents' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "contract_id": "<CONTRACT_ID>",
    "user_id": "b176cb76-988e-4382-a7ed-d13d443fab5a",
    "consented": false,
    "reason": "Server bị lag, nước đi của tôi không được đăng ký đúng."
  }'
```

Server chuyển trạng thái → `disputed`:
```bash
curl -X PATCH 'https://veoillsstewpnvmhxmlx.supabase.co/rest/v1/contract_instances?id=eq.<CONTRACT_ID>' \
  -H 'apikey: <ANON_KEY>' \
  -H 'Authorization: Bearer <ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{ "status": "disputed" }'
```

Admin xem xét và giải quyết → `resolved` → `settled` (xem [contract-lifecycle-api.md](./contract-lifecycle-api.md#9-dispute-flow)).
