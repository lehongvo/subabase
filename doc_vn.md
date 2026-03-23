# Hệ thống quản lý hợp đồng Metaverse — Đặc tả yêu cầu

| Mục | Chi tiết |
| --- | --- |
| Mã tài liệu | IX-REQ-CONTRACT-001 |
| Phiên bản | 0.1.0 (Bản nháp) |
| Ngày tạo | 2026-03-18 |
| Tác giả | Akio Iwaki (PO) |
| Dự án mục tiêu | IX |
| Trạng thái | Chờ rà soát |

---

## 1. Tổng quan

### 1.1 Bối cảnh

Trong Metaverse IX, nhiều “tương tác dựa trên đồng thuận” diễn ra giữa người dùng với nhau và giữa người dùng với nền tảng. Hệ thống này thống nhất mọi tương tác đó dưới một khái niệm chung — “hợp đồng” — và cung khung quản lý minh bạch.

### 1.2 Mục tiêu

- Quản lý tập trung mọi sự kiện hợp đồng trong metaverse
- Công khai toàn bộ lịch sử tạo hợp đồng, thực thi và thanh toán
- Cung cơ chế linh hoạt để kiểm soát từng hợp đồng ghi on-chain hay off-chain
- Xây nền tảng cho quản lý blockchain đầy đủ trên MegaETH trong tương lai

### 1.3 Ví dụ hợp đồng

| Loại hợp đồng | Mô tả | Các bên |
| --- | --- | --- |
| RPS (Oẳn tù tì) | Trận người dùng đấu người dùng, chuyển điểm theo kết quả | Người dùng vs Người dùng |
| Thưởng công việc | Thanh toán khi hoàn thành nhiệm vụ | Người làm vs Khách hàng |
| Tham gia giải đấu | Thu phí tham gia và phân phối giải thưởng | Người tham gia vs Ban tổ chức |
| Khác | Mọi mẫu hợp đồng do quản trị viên định nghĩa | Linh hoạt |

---

## 2. Kế hoạch theo giai đoạn

### Giai đoạn 0 (Phát hành ban đầu)

- **Phương thức thanh toán**: IX Points / IX Free Points (đã triển khai)
- **Quản lý**: Off-chain (CSDL Supabase)
- **Minh bạch**: Toàn bộ lịch sử hợp đồng, gồm bản ghi chuyển điểm, được công khai
- **Mục tiêu**: Kiểm chứng UX, tinh chỉnh quy tắc, thu hút người dùng

### Giai đoạn 1

- **Phương thức thanh toán**: USDT trên MegaETH
- **Quản lý**: Hợp đồng thông minh (smart contract)
- **Mục tiêu**: Chuyển on-chain, thực thi hợp đồng bằng tiền thật

### Giai đoạn 2

- **Phương thức thanh toán**: IX Economic Token (ERC-20)
- **Quản lý**: Hợp đồng thông minh
- **Mục tiêu**: Ra mắt nền kinh tế token IX

### Giai đoạn 3

- **Phương thức thanh toán**: Tích hợp Economic Token + Governance Token
- **Quản lý**: Quản trị dựa trên DAO
- **Mục tiêu**: Đề xuất và phê duyệt mẫu hợp đồng bởi người nắm Governance Token

---

## 3. Giai đoạn 0 — Yêu cầu chi tiết

### 3.1 Yêu cầu chức năng

### 3.1.1 Quản lý mẫu hợp đồng (Chức năng quản trị)

| Chức năng | Mô tả |
| --- | --- |
| Tạo mẫu | Định nghĩa loại hợp đồng, điều kiện và quy tắc thưởng |
| Kích hoạt / Vô hiệu hóa mẫu | Kiểm soát hợp đồng nào có sẵn trong metaverse |
| Gắn sự kiện metaverse | Liên kết mẫu với một sự kiện metaverse cụ thể |
| **Cài đặt ghi blockchain** | Cấu hình chính sách ghi on-chain theo từng mẫu (xem 3.1.6) |

**Chỉ quản trị viên mới được tạo và quản lý mẫu hợp đồng.**

### 3.1.2 Vòng đời hợp đồng

```
Created → Active → Completed → Settled
                       ↓
                   Disputed → Resolved → Settled
```

| Trạng thái | Mô tả |
| --- | --- |
| Created | Thể hiện hợp đồng được tạo từ mẫu |
| Active | Mọi bên đã tham gia; hợp đồng đang diễn ra |
| Completed | Kết quả sự kiện đã xác định (chờ đồng thuận) |
| Disputed | Một bên phản đối kết quả |
| Resolved | Tranh chấp đã được xử lý |
| Settled | Thanh toán hoàn tất (điểm đã chuyển) |

### 3.1.3 Luồng thực thi hợp đồng

1. Một sự kiện xảy ra trong metaverse (ví dụ: trận RPS bắt đầu)
2. Một thể hiện hợp đồng được tạo từ mẫu đã gắn
3. Các bên ký quỹ (nộp) điểm
4. Sự kiện được thực thi
5. Kết quả được xác định → cả hai bên đồng thuận
6. Điểm được chuyển từ ký quỹ tới người thắng / người nhận
7. Phí được gửi tới Kho bạc (nền tảng)

### 3.1.4 Thanh toán (IX Points / IX Free Points)

| Mục | IX Points | IX Free Points |
| --- | --- | --- |
| Thu nhận | Mua / Thưởng | Phát miễn phí, thưởng đăng nhập, v.v. |
| Sử dụng | Thanh toán hợp đồng “production” | Hợp đồng luyện tập / rủi ro thấp |
| Chuyển đổi | Có (chuyển đổi token trong tương lai) | Không |

### 3.1.5 Sổ cái công khai (Minh bạch mở)

Thông tin có thể xem công khai:

| Trường công khai | Mô tả |
| --- | --- |
| Contract ID | Định danh duy nhất |
| Loại hợp đồng | RPS, thưởng công việc, giải đấu, v.v. |
| Các bên | ID người dùng (đang xem xét tùy chọn ẩn danh) |
| Số tiền chuyển điểm | Số IX Points / Free Points đã chuyển |
| Timestamp | Thời điểm mỗi lần đổi trạng thái |
| Kết quả / Trạng thái | Trạng thái hiện tại và kết cục cuối cùng |

### 3.1.6 Cài đặt ghi blockchain (Lựa chọn on-chain / off-chain)

Việc một giao dịch hợp đồng có ghi lên blockchain (MegaETH) hay không được quản lý bằng **hệ thống điều khiển hai cấp**.

**Cấp 1: Cấu hình mẫu bởi quản trị**

Khi tạo mẫu hợp đồng, quản trị viên đặt chính sách ghi blockchain thành một trong các giá trị sau:

| Cài đặt | Mô tả | Ví dụ trường hợp |
| --- | --- | --- |
| `required` | Luôn ghi on-chain. Người dùng không thể từ chối | Hợp đồng giá trị cao, giải đấu, thưởng công việc |
| `optional` | Người dùng chọn có ghi on-chain khi tham gia hay không | Trận RPS tầm trung, v.v. |
| `off` | Không ghi on-chain. Chỉ off-chain (CSDL) | RPS nhỏ / thường, hợp đồng Free Point |

**Cấp 2: Lựa chọn người dùng (chỉ khi `optional`)**

Khi mẫu được đặt `optional`, người dùng có thể chọn lúc tham gia:

- **Bật ghi on-chain** → Giao dịch được ghi lên MegaETH khi thanh toán
- **Tắt ghi on-chain** → Chỉ ghi trong sổ cái công khai CSDL

> **Ghi chú**: Chọn ghi on-chain có thể phát sinh phí gas (ví dụ: khấu trừ từ IX Points). Quy tắc phân bổ chi phí sẽ được quyết định sau.

**Yêu cầu giao diện bảng điều khiển quản trị**

- Có mục ghi blockchain trên màn hình tạo / sửa mẫu
- Cung cấp radio hoặc select 3 lựa chọn: `required` / `optional` / `off`
- Khi chọn `optional`, hiển thị ô văn bản tùy chỉnh cho mô tả hiển thị cho người dùng
- Thay đổi cài đặt không ảnh hưởng thể hiện hợp đồng hiện có (chỉ áp dụng cho hợp đồng mới)

**Yêu cầu giao diện Metaverse (phía người dùng)**

- Khi mẫu là `optional`, hiển thị toggle hoặc checkbox trên màn hình tham gia hợp đồng
  - Ví dụ: “Ghi hợp đồng này lên blockchain”
- Khi `required`, hiển thị thông báo ghi on-chain là bắt buộc (không có lựa chọn)
- Khi `off`, không hiển thị gì thêm

---

### 3.2 Mô hình dữ liệu (Thiết kế phục vụ chuyển on-chain)

> **Quan trọng**: Schema CSDL Giai đoạn 0 phải thiết kế để ánh xạ 1:1 với trạng thái hợp đồng thông minh Giai đoạn 1.

### contract_templates

| Cột | Kiểu | Mô tả |
| --- | --- | --- |
| id | UUID | ID mẫu |
| name | VARCHAR | Tên mẫu |
| type | ENUM | Loại hợp đồng (rps, work_reward, tournament, custom) |
| conditions | JSONB | Định nghĩa điều kiện hợp đồng |
| reward_rules | JSONB | Quy tắc tính thưởng |
| payment_type | ENUM | ix_point, ix_free_point, both |
| fee_rate | DECIMAL | Tỷ lệ phí (%) |
| chain_record_policy | ENUM | required, optional, off (chính sách ghi blockchain) |
| is_active | BOOLEAN | Đang hoạt động / Không hoạt động |
| metaverse_event_id | VARCHAR | ID sự kiện metaverse đã gắn |
| created_by | UUID | ID người dùng quản trị tạo mẫu |
| created_at | TIMESTAMP | Thời điểm tạo |
| updated_at | TIMESTAMP | Thời điểm cập nhật cuối |

### contract_instances

| Cột | Kiểu | Mô tả |
| --- | --- | --- |
| id | UUID | ID thể hiện hợp đồng |
| template_id | UUID | FK → contract_templates |
| status | ENUM | created, active, completed, disputed, resolved, settled |
| chain_record | BOOLEAN | Có ghi on-chain hay không (theo chính sách mẫu + lựa chọn người dùng) |
| tx_hash | VARCHAR | Hash giao dịch on-chain (có thể NULL) |
| created_at | TIMESTAMP | Thời điểm tạo |
| settled_at | TIMESTAMP | Thời điểm hoàn tất thanh toán |

### contract_parties

| Cột | Kiểu | Mô tả |
| --- | --- | --- |
| id | UUID | PK |
| contract_id | UUID | FK → contract_instances |
| user_id | UUID | ID người dùng của bên |
| role | VARCHAR | Vai trò (challenger, opponent, worker, client, participant, v.v.) |
| escrow_amount | DECIMAL | Số điểm ký quỹ |
| escrow_type | ENUM | ix_point, ix_free_point |
| joined_at | TIMESTAMP | Thời điểm tham gia |

### contract_results

| Cột | Kiểu | Mô tả |
| --- | --- | --- |
| id | UUID | PK |
| contract_id | UUID | FK → contract_instances |
| result_data | JSONB | Dữ liệu kết quả (người thắng, điểm số, v.v.) |
| reported_by | VARCHAR | Nguồn kết quả (system, user) |
| reported_at | TIMESTAMP | Thời điểm báo cáo |

### contract_settlements

| Cột | Kiểu | Mô tả |
| --- | --- | --- |
| id | UUID | PK |
| contract_id | UUID | FK → contract_instances |
| from_user_id | UUID | Người gửi |
| to_user_id | UUID | Người nhận |
| amount | DECIMAL | Số điểm chuyển |
| point_type | ENUM | ix_point, ix_free_point |
| fee_amount | DECIMAL | Số phí |
| settled_at | TIMESTAMP | Thời điểm thanh toán |
| tx_hash | VARCHAR | Giai đoạn 1+: Hash giao dịch on-chain |

### contract_consents

| Cột | Kiểu | Mô tả |
| --- | --- | --- |
| id | UUID | PK |
| contract_id | UUID | FK → contract_instances |
| user_id | UUID | Người dùng đồng thuận / phản đối |
| consented | BOOLEAN | Đồng thuận / Phản đối |
| consented_at | TIMESTAMP | Thời điểm đồng thuận |
| signature | VARCHAR | Giai đoạn 1+: Chữ ký ví |

### 3.3 Yêu cầu phi chức năng

| Mục | Yêu cầu |
| --- | --- |
| Sẵn sàng | Cần xử lý thời gian thực do tích hợp sự kiện metaverse |
| Toàn vẹn dữ liệu | Chuyển điểm phải đảm bảo tính nhất quán giao dịch |
| Khả năng mở rộng | Kiến trúc phải cho phép thay backend khi chuyển Giai đoạn 1 (MegaETH) |
| Bảo mật | Thao tác ký quỹ chỉ dành cho quyền quản trị hoặc quy trình hệ thống tự động |
| Khả năng kiểm toán | Mọi chuyển điểm phải có timestamp và truy vết đầy đủ |

---

## 4. Chiến lược chuyển Giai đoạn 1 (Tham khảo)

Ánh xạ khi chuyển từ Giai đoạn 0 sang Giai đoạn 1:

| Giai đoạn 0 (Off-chain) | Giai đoạn 1 (MegaETH) |
| --- | --- |
| Bảng contract_templates | Hợp đồng ContractRegistry |
| Bảng contract_instances | Hợp đồng ContractInstance (triển khai từng instance hoặc mẫu Factory) |
| Bảng contract_settlements | Ký quỹ + logic chuyển tự động |
| API sổ cái công khai | Nhật ký sự kiện on-chain (ai cũng có thể xác minh) |
| IX Points | ERC-20 Economic Token |
| Quyền quản trị | Vai trò Owner / Admin (trong hợp đồng) |

---

## 5. Xác định kết quả (Gồm giải quyết tranh chấp)

### Luồng bình thường

1. Máy chủ metaverse báo cáo kết quả cho hệ thống
2. Cả hai bên được thông báo kết quả
3. Nếu không có phản đối trong khoảng thời gian quy định (sẽ quyết định sau), kết quả được tự động chốt
4. Thực hiện thanh toán

### Luồng tranh chấp

1. Một bên phản đối kết quả (Trạng thái: Disputed)
2. Quản trị viên xem xét bằng chứng và ra phán quyết
3. Thanh toán theo phán quyết (Trạng thái: Resolved → Settled)

---

## 6. Hạng mục mở (Chưa quyết định)

| Mục | Chi tiết |
| --- | --- |
| Tỷ lệ phí | Cấu hình tỷ lệ phí theo loại hợp đồng |
| Thời hạn phản đối | Khoảng thời gian từ lúc báo cáo kết quả đến khi tự động chốt |
| Mức ẩn danh | Hiển thị bao nhiêu thông tin người dùng trên sổ cái công khai |
| Hạn chế Free Point | Giới hạn hợp đồng có thể dùng Free Point |
| Chi phí ghi on-chain | Quy tắc phân bổ chi phí khi người dùng chọn ghi on-chain với `optional` |
| Mẫu hợp đồng ngoài RPS | Định nghĩa chi tiết điều kiện cho thưởng công việc, giải đấu |
| Đặc tả Governance Token | Thiết kế token cho Giai đoạn 3 |
| Đặc tả Economic Token | Thiết kế token cho Giai đoạn 2 |

---

## 7. Hệ thống liên quan

| Hệ thống | Mối quan hệ |
| --- | --- |
| IX-Government-platform | Bảng điều khiển quản trị, quản lý người dùng, hệ thống điểm (hiện có) |
| IX Metaverse | Nguồn sự kiện, môi trường thực thi hợp đồng |
| MegaETH | Hạ tầng blockchain từ Giai đoạn 1 trở đi |

---

## Phụ lục: Thuật ngữ
