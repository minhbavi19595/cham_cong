# ĐẶC TẢ HỆ THỐNG CHẤM CÔNG (v2)

**Công nghệ:** Frontend Next.js — Backend/Database Supabase (PostgreSQL + Auth)

> Bản cập nhật theo xác nhận: (1) Chuyên viên tự chấm công, Admin chỉ theo dõi/xem; (2) Trực / Trực viện / Trực y tế dùng chung 1 bộ quy tắc nghỉ bù; (3) Sửa dữ liệu quá hạn chỉ cần giải trình để Admin đọc, không cần duyệt; (4) Thêm loại "Nghỉ lễ/Tết"; (5) Quy tắc phát sinh nghỉ bù/nghỉ tuần được thiết kế thành **rule engine động do Admin tự cấu hình**, không hard-code.

---

## 1. TỔNG QUAN

Hệ thống quản lý chấm công theo tháng, dạng bảng: mỗi hàng là một nhân viên, mỗi cột là một ngày trong tháng, giá trị ô là loại công. Cuối bảng là phần tổng hợp số ngày theo từng loại và số dư nghỉ bù/nghỉ tuần/nghỉ phép.

Điểm cốt lõi của phiên bản này: **các quy tắc "chấm loại công X vào ngày loại Y thì phát sinh/trừ bao nhiêu ngày nghỉ bù, nghỉ tuần" không được viết cứng trong code, mà là dữ liệu cấu hình do Admin tự thiết lập** trong một màn hình riêng ("Thiết lập quy tắc chấm công").

---

## 2. VAI TRÒ NGƯỜI DÙNG

### 2.1. Chuyên viên
- **Tự chấm công cho bản thân** trong các ngày đã được mở.
- Xem bảng chấm công, số dư nghỉ phép / nghỉ bù / nghỉ tuần của chính mình.
- Sửa dữ liệu ngày đã qua (đã chốt) → bắt buộc nhập **giải trình lý do sửa**.

### 2.2. Admin
- Quản lý tài khoản: thêm chuyên viên mới, cập nhật/reset mật khẩu.
- Setup số ngày phép năm cho từng nhân viên theo từng năm.
- Cấu hình **danh mục loại chấm công** và **rule engine** (quy tắc phát sinh nghỉ bù/nghỉ tuần) — xem mục 5.
- Mở/khóa ngày được phép chấm công.
- **Theo dõi / xem trực tiếp** toàn bộ bảng chấm công của mọi chuyên viên (không tự nhập hộ trong luồng thường; có thể có quyền override khi cần — xem câu hỏi mở 9.1).
- Đọc (không cần duyệt) toàn bộ giải trình khi chuyên viên sửa dữ liệu quá hạn.
- Khai báo **danh sách ngày nghỉ lễ/Tết** trong năm.
- Xuất Excel bảng chấm công.

---

## 3. DANH MỤC LOẠI CHẤM CÔNG (Attendance Types)

| Mã | Tên loại công | Tính ngày công hành chính? | Ghi chú |
|---|---|---|---|
| `HC` | Hành chính (đi làm) | Có | |
| `NP` | Nghỉ phép | Không | Auto trừ vào quỹ phép năm |
| `OM` | Ốm | Không | |
| `HN_HC` | Hội nghị / Học tập — tính hành chính | Có | |
| `HN_KHC` | Hội nghị / Học tập — không tính hành chính | Không | |
| `NT` | Nghỉ tuần | Không | Dùng số dư nghỉ tuần đã tích lũy khi nghỉ vào ngày thường |
| `TS` | Thai sản | Không | |
| `TR` | Trực | Không | Áp dụng rule engine mục 5 |
| `TRV` | Trực viện | Không | Áp dụng **cùng bộ rule** như `TR` |
| `TYT` | Trực y tế | Không | Áp dụng **cùng bộ rule** như `TR` |
| `NB` | Nghỉ bù | Không | Dùng số dư nghỉ bù đã tích lũy |
| `NL` | **Nghỉ lễ, Tết** *(mới)* | Không | Ngày lễ do Admin khai báo trước trong năm (xem 3.1) |

Vì `TR`, `TRV`, `TYT` dùng chung quy tắc, hệ thống nhóm 3 mã này vào một **nhóm loại công "Trực"** (`group = 'DUTY'`) để rule engine chỉ cần cấu hình 1 lần, áp dụng cho cả nhóm.

### 3.1. Danh sách ngày nghỉ lễ/Tết
- Admin khai báo trước danh sách ngày nghỉ lễ/Tết trong năm (bảng `holidays`, gồm ngày + tên ngày lễ).
- Khi một ngày nằm trong danh sách này, hệ thống coi ngày đó thuộc **day_category = 'holiday'** khi áp dụng rule engine (thay vì weekday/weekend) — xem mục 5.
- Mặc định nhân viên có thể được chấm `NL` vào ngày đó nếu không đi làm/trực; nếu vẫn đi làm/trực vào đúng ngày lễ, hệ thống áp dụng rule engine theo `day_category = 'holiday'` cho loại công tương ứng (`HC`, `TR`...).

---

## 4. NGHỈ TUẦN MẶC ĐỊNH

- Mỗi nhân viên, mỗi tuần, mặc định có 2 ngày nghỉ tuần: **Thứ 7** và **Chủ nhật**.
- Nhân viên có thể **dời** nghỉ tuần sang ngày khác trong tuần (chấm `NT` vào ngày đó), và đi làm/trực vào đúng T7/CN.
- Khi chấm `NT` vào một ngày **không phải T7/CN**, hệ thống hiểu đây là hành động "dùng" 1 ngày nghỉ tuần đã có sẵn trong số dư → trừ số dư nghỉ tuần.
- Khi chấm `NT` đúng vào T7/CN (nghỉ tuần bình thường, không dời) → không phát sinh, không trừ gì cả (đây là mặc định).

---

## 5. RULE ENGINE — CẤU HÌNH ĐỘNG QUY TẮC PHÁT SINH NGÀY NGHỈ

Đây là phần thay thế cho việc hard-code các quy tắc "trực T7/CN thì +1 nghỉ bù +1 nghỉ tuần...". Thay vào đó là **1 bảng cấu hình** mà Admin có thể chỉnh sửa qua giao diện, không cần sửa code.

### 5.1. Khái niệm

Với **mỗi loại công (hoặc nhóm loại công)**, Admin thiết lập: *"nếu chấm loại công này vào ngày thuộc loại ngày X, thì cộng/trừ bao nhiêu vào quỹ nghỉ bù, quỹ nghỉ tuần, quỹ nghỉ phép, và có tính là ngày công hành chính hay không."*

**Loại ngày (day_category)** gồm:
- `weekday` — Thứ 2 đến Thứ 6
- `weekend` — Thứ 7, Chủ nhật
- `holiday` — Ngày nằm trong danh sách nghỉ lễ/Tết (mục 3.1)

### 5.2. Bảng cấu hình quy tắc (`attendance_rules`)

Mỗi dòng cấu hình = 1 tổ hợp (nhóm loại công × loại ngày), với các "delta" (số cộng/trừ) cho từng quỹ:

| Cột | Ý nghĩa |
|---|---|
| `type_group` | Nhóm loại công áp dụng (VD: `DUTY` cho Trực/Trực viện/Trực y tế, hoặc mã đơn lẻ như `HC`, `NT`, `NP`) |
| `day_category` | `weekday` / `weekend` / `holiday` |
| `comp_off_delta` | Số ngày cộng(+)/trừ(−) vào **quỹ nghỉ bù** |
| `weekly_off_delta` | Số ngày cộng(+)/trừ(−) vào **quỹ nghỉ tuần** |
| `leave_delta` | Số ngày cộng(+)/trừ(−) vào **quỹ nghỉ phép năm** |
| `counts_as_work_day` | true/false — có tính vào tổng ngày công hành chính không |

### 5.3. Ví dụ cấu hình mặc định tương ứng đúng các quy tắc bạn đã mô tả

| type_group | day_category | comp_off_delta | weekly_off_delta | leave_delta | counts_as_work_day |
|---|---|---|---|---|---|
| `DUTY` (Trực/Trực viện/Trực y tế) | `weekday` | **+1** | 0 | 0 | false |
| `DUTY` (Trực/Trực viện/Trực y tế) | `weekend` | **+1** | **+1** | 0 | false |
| `HC` (Hành chính) | `weekday` | 0 | 0 | 0 | true |
| `HC` (Hành chính) | `weekend` | 0 | **+1** | 0 | true |
| `NT` (Nghỉ tuần) | `weekday` | 0 | **−1** | 0 | false |
| `NT` (Nghỉ tuần) | `weekend` | 0 | 0 | 0 | false |
| `NB` (Nghỉ bù) | bất kỳ | **−1** | 0 | 0 | false |
| `NP` (Nghỉ phép) | bất kỳ | 0 | 0 | **−1** | false |

→ Đây chính xác là ví dụ bạn đưa ra: *"chọn trực, nếu vào T7/CN thì +1 nghỉ bù, +1 nghỉ tuần"* — nay là 1 **dòng dữ liệu** trong bảng `attendance_rules`, Admin có thể sửa số delta này bất cứ lúc nào qua giao diện (ví dụ sau này công ty đổi chính sách: trực T7/CN được +2 nghỉ bù → Admin chỉ cần sửa số, không cần sửa code).

### 5.4. Cách hệ thống áp dụng rule khi chấm công

Khi chuyên viên chấm 1 ô (nhân viên, ngày, loại công):
1. Xác định `day_category` của ngày đó: nếu nằm trong `holidays` → `holiday`; nếu là T7/CN → `weekend`; còn lại → `weekday`.
2. Tìm dòng `attendance_rules` khớp với (nhóm loại công vừa chọn, `day_category` vừa xác định).
3. Áp dụng các delta vào `day_off_ledger` (nghỉ bù, nghỉ tuần) và `leave_quota` (nghỉ phép) — ghi nhận nguồn gốc (record nào gây ra thay đổi) để có thể truy vết/hoàn tác khi sửa/xóa.
4. Cập nhật cờ `counts_as_work_day` để tính vào tổng hợp cuối bảng.
5. Nếu chuyên viên **sửa lại** ô đã chấm (kèm giải trình): hệ thống **hoàn tác (revert)** toàn bộ delta của giá trị cũ, rồi áp dụng delta của giá trị mới — đảm bảo số dư luôn đúng dù sửa nhiều lần.

### 5.5. Màn hình "Thiết lập quy tắc chấm công" (Admin)

Giao diện dạng bảng, mỗi dòng = 1 rule, Admin có thể:
- Thêm/sửa/xóa rule.
- Chọn nhóm loại công (hoặc gán loại công vào nhóm `DUTY`/nhóm khác).
- Chọn loại ngày áp dụng.
- Nhập số delta cho từng quỹ.
- Bật/tắt `counts_as_work_day`.

Nhờ vậy, nếu sau này phát sinh thêm loại công mới hoặc thay đổi chính sách nghỉ, **không cần sửa code**, chỉ cần cấu hình lại trong bảng này.

---

## 6. LUỒNG CHẤM CÔNG & SỬA DỮ LIỆU QUÁ HẠN

1. Admin **mở chấm công** cho một ngày/khoảng ngày.
2. Chuyên viên tự chấm công cho bản thân trong các ngày đã mở → hệ thống tự áp dụng rule engine (mục 5.4).
3. Với ngày **đã qua** (đã chốt), nếu chuyên viên muốn sửa:
   - Bắt buộc nhập **nội dung giải trình**.
   - Hệ thống lưu: giá trị cũ, giá trị mới, người sửa, thời điểm, nội dung giải trình — **không cần Admin duyệt**, thay đổi có hiệu lực ngay, Admin chỉ **đọc** lại giải trình khi cần kiểm tra.
   - Số dư nghỉ bù/nghỉ tuần/nghỉ phép được tự động điều chỉnh lại theo mục 5.4 bước 5.
4. Admin có thể xem toàn bộ lịch sử giải trình của mọi chuyên viên (lọc theo người, theo ngày).

---

## 7. BẢNG TỔNG HỢP CUỐI THÁNG

| Chỉ tiêu | Giá trị |
|---|---|
| Tổng ngày công (các loại có `counts_as_work_day = true`) | X |
| Ngày nghỉ phép đã dùng trong tháng | X |
| Số ngày phép còn lại trong năm | X |
| Ngày ốm | X |
| Ngày thai sản | X |
| Ngày trực / trực viện / trực y tế (từng loại) | X |
| Ngày nghỉ lễ/Tết | X |
| Nghỉ bù phát sinh / đã dùng trong tháng | X / X |
| Nghỉ tuần phát sinh / đã dùng trong tháng | X / X |
| Số dư nghỉ bù lũy kế | X |
| Số dư nghỉ tuần lũy kế | X |

---

## 8. CẤU TRÚC DỮ LIỆU ĐỀ XUẤT (Supabase / PostgreSQL)

*(Yêu cầu: Toàn bộ schema, RPC và cấu hình cơ sở dữ liệu sẽ được viết riêng vào một thư mục `supabase/` để Admin có thể tự copy/chạy lệnh trên giao diện Supabase. Cấu hình kết nối sẽ được đặt trong file `.env` kèm comment hướng dẫn chi tiết nơi lấy các token cần thiết.)*

```sql
-- Người dùng hệ thống
users (
  id uuid PK,
  auth_id uuid (FK -> auth.users),
  full_name text,
  role text CHECK (role IN ('admin','staff')),
  position text,          -- chức vụ
  is_active boolean,
  created_at timestamptz
)

-- Quỹ phép năm theo từng nhân viên
leave_quota (
  id uuid PK,
  user_id uuid FK -> users,
  year int,
  total_days numeric,
  UNIQUE (user_id, year)
)

-- Ngày nghỉ lễ/Tết do Admin khai báo
holidays (
  holiday_date date PK,
  name text
)

-- Danh mục loại chấm công
attendance_types (
  code text PK,               -- HC, NP, OM, HN_HC, HN_KHC, NT, TS, TR, TRV, TYT, NB, NL
  name text,
  type_group text             -- nhóm dùng để tra rule, VD: 'DUTY' cho TR/TRV/TYT, còn lại = chính code đó
)

-- Rule engine: quy tắc phát sinh/trừ quỹ nghỉ theo (nhóm loại công x loại ngày)
attendance_rules (
  id uuid PK,
  type_group text,                         -- khớp attendance_types.type_group
  day_category text CHECK (day_category IN ('weekday','weekend','holiday')),
  comp_off_delta numeric DEFAULT 0,
  weekly_off_delta numeric DEFAULT 0,
  leave_delta numeric DEFAULT 0,
  counts_as_work_day boolean DEFAULT false,
  UNIQUE (type_group, day_category)
)

-- Bản ghi chấm công theo ngày
attendance_records (
  id uuid PK,
  user_id uuid FK -> users,
  work_date date,
  type_code text FK -> attendance_types,
  created_by uuid FK -> users,       -- chính chuyên viên đó
  created_at timestamptz,
  updated_by uuid,
  updated_at timestamptz,
  UNIQUE (user_id, work_date)
)

-- Lịch sử sửa + giải trình (khi sửa ngày đã chốt)
attendance_edit_logs (
  id uuid PK,
  record_id uuid FK -> attendance_records,
  old_type_code text,
  new_type_code text,
  reason text,               -- nội dung giải trình
  edited_by uuid FK -> users,
  edited_at timestamptz
)

-- Sổ cái công nợ ngày nghỉ (nghỉ bù / nghỉ tuần) — ghi nhận từng lần phát sinh/sử dụng
day_off_ledger (
  id uuid PK,
  user_id uuid FK -> users,
  ledger_type text CHECK (ledger_type IN ('comp_off','weekly_off')),
  change numeric,
  source_record_id uuid FK -> attendance_records,
  note text,
  created_at timestamptz
)

-- Cấu hình mở/khóa chấm công theo ngày
attendance_open_days (
  work_date date PK,
  opened_by uuid FK -> users,
  opened_at timestamptz
)
```

**Cách tính số dư:**
- Nghỉ bù / Nghỉ tuần = `SUM(change)` trong `day_off_ledger` theo `user_id`, `ledger_type`.
- Nghỉ phép còn lại = `leave_quota.total_days − COUNT/SUM(leave_delta áp dụng)` trong năm tương ứng.

**Nơi đặt logic áp dụng rule:** nên đặt trong **Postgres function/trigger** (chạy khi `INSERT/UPDATE/DELETE` trên `attendance_records`) để đảm bảo mọi thay đổi — kể cả sửa dữ liệu quá hạn — đều tự động revert + re-apply đúng, không phụ thuộc frontend.

---

## 9. PHÂN QUYỀN DỮ LIỆU (RLS — Supabase)

- **Chuyên viên:** đọc + ghi (insert/update) `attendance_records` **chỉ của chính mình**, chỉ trong các ngày đã mở (`attendance_open_days`) hoặc kèm giải trình nếu ngày đã chốt. Đọc số dư/tổng hợp của chính mình.
- **Admin:** đọc toàn bộ `attendance_records`, `attendance_edit_logs`, `day_off_ledger` của mọi người. Ghi được `users`, `leave_quota`, `attendance_types`, `attendance_rules`, `holidays`, `attendance_open_days`. *(Lưu ý: Admin KHÔNG được phép chấm hộ/sửa trực tiếp bản ghi của chuyên viên; mọi thao tác chấm công, kể cả khi quên, đều do chuyên viên tự thực hiện).*

---

## 10. CÁC QUY ĐỊNH ĐÃ CHỐT VÀ CÂU HỎI CÒN LẠI

**A. Các vấn đề đã chốt (dựa trên phản hồi mới nhất):**
1. **Quyền override của Admin:** Admin **KHÔNG** chấm hộ/sửa trực tiếp. Chuyên viên bắt buộc phải tự thực hiện mọi thao tác.
2. **Ngày lễ/Tết trùng cuối tuần:** Rule engine cho phép Admin tự setup trực tiếp số ngày nghỉ bù/nghỉ tuần được cộng, do đó hệ thống sẽ xử lý linh hoạt mọi trường hợp, không cần lo vấn đề trùng lặp cứng.
3. **Thưởng trực ngày lễ:** Hệ thống chấm công **KHÔNG** quản lý việc thưởng, chỉ quản lý việc có phát sinh ngày nghỉ bù hay không (dựa theo setup của rule engine).
4. **Chốt bảng công (lock):** Tính theo mốc **nửa đêm** (00:00). Qua mốc này, bản ghi của ngày đó bị chốt, nếu chuyên viên muốn sửa thì bắt buộc phải kèm giải trình.
5. **Tổ chức mã nguồn Database:** Các RPC và Database schema sẽ được viết riêng ra một folder `supabase` để Admin có thể tự lấy lệnh và chạy trên Supabase. Các kết nối Supabase sẽ được đặt trong file `.env` với comment rõ ràng hướng dẫn vị trí lấy các token cần thiết.

**B. Các câu hỏi còn mở (có thể xác nhận sau):**
1. **`NL` (Nghỉ lễ/Tết) có tự động chấm sẵn cho tất cả nhân viên** khi Admin khai báo ngày lễ trong `holidays` không, hay mỗi chuyên viên vẫn phải tự chấm `NL` cho ngày đó?
2. **Giới hạn/hết hạn số dư:** nghỉ bù, nghỉ tuần, nghỉ phép có bị **giới hạn âm** (chặn không cho dùng khi số dư = 0) hoặc **hết hạn** theo mốc thời gian không?
3. **Phòng ban/đơn vị:** có cần nhóm nhân viên theo phòng/ban để lọc bảng và xuất Excel riêng từng đơn vị không?
4. **Mẫu Excel xuất ra:** có mẫu công ty/nhà nước sẵn cần bám theo định dạng cụ thể không?
5. **Bulk-chấm công:** chuyên viên có cần thao tác chấm nhanh nhiều ngày cùng lúc không?

---
*Vì các vấn đề then chốt về logic (chốt sửa đổi, phân quyền) đã rõ ràng, ta có thể bắt đầu dựng **schema SQL đầy đủ + RPC (trong thư mục supabase)** và cài đặt khung dự án.*