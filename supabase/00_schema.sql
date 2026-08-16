-- =============================================================
-- 00_SCHEMA.SQL  — Hệ thống Chấm Công
-- Chạy file này đầu tiên trên Supabase SQL Editor
-- =============================================================

-- Bật extension uuid nếu chưa có
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================
-- BẢNG: users — Nhân viên / Admin
-- auth_id liên kết với auth.users của Supabase
-- =============================================================
CREATE TABLE IF NOT EXISTS public.users (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_id     uuid UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name   text NOT NULL,
  email       text NOT NULL UNIQUE,
  role        text NOT NULL DEFAULT 'staff' CHECK (role IN ('admin','staff')),
  position    text,                    -- Chức vụ / phòng ban
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- =============================================================
-- BẢNG: leave_quota — Quỹ phép năm theo (nhân viên × năm)
-- =============================================================
CREATE TABLE IF NOT EXISTS public.leave_quota (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  year        int NOT NULL CHECK (year >= 2020),
  total_days  numeric(5,1) NOT NULL DEFAULT 12,
  UNIQUE (user_id, year)
);

-- =============================================================
-- BẢNG: holidays — Ngày nghỉ lễ/Tết do Admin khai báo
-- =============================================================
CREATE TABLE IF NOT EXISTS public.holidays (
  holiday_date  date PRIMARY KEY,
  name          text NOT NULL,
  created_by    uuid REFERENCES public.users(id),
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- =============================================================
-- BẢNG: attendance_types — Danh mục loại chấm công
-- type_group dùng để tra rule engine (VD: DUTY cho TR/TRV/TYT)
-- =============================================================
CREATE TABLE IF NOT EXISTS public.attendance_types (
  code        text PRIMARY KEY,   -- HC, NP, OM, TR, TRV, TYT, NT, NB, NL, TS, HN_HC, HN_KHC
  name        text NOT NULL,
  type_group  text NOT NULL,      -- 'DUTY' hoặc chính code đó
  sort_order  int  NOT NULL DEFAULT 0,
  is_active   boolean NOT NULL DEFAULT true
);

-- =============================================================
-- BẢNG: attendance_rules — Rule engine (nhóm loại × loại ngày)
-- Mọi quy tắc tính nghỉ bù/tuần/phép đặt tại đây, Admin sửa qua UI
-- =============================================================
CREATE TABLE IF NOT EXISTS public.attendance_rules (
  id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  type_group          text NOT NULL,
  day_category        text NOT NULL CHECK (day_category IN ('weekday','weekend','holiday')),
  comp_off_delta      numeric(5,2) NOT NULL DEFAULT 0,   -- cộng(+)/trừ(-) nghỉ bù
  weekly_off_delta    numeric(5,2) NOT NULL DEFAULT 0,   -- cộng(+)/trừ(-) nghỉ tuần
  leave_delta         numeric(5,2) NOT NULL DEFAULT 0,   -- cộng(+)/trừ(-) phép năm
  counts_as_work_day  boolean NOT NULL DEFAULT false,
  note                text,
  UNIQUE (type_group, day_category)
);

-- =============================================================
-- BẢNG: attendance_open_days — Ngày Admin mở cho phép chấm công
-- =============================================================
CREATE TABLE IF NOT EXISTS public.attendance_open_days (
  work_date   date PRIMARY KEY,
  opened_by   uuid REFERENCES public.users(id),
  opened_at   timestamptz NOT NULL DEFAULT now()
);

-- =============================================================
-- BẢNG: attendance_records — Bản ghi chấm công (user × ngày)
-- =============================================================
CREATE TABLE IF NOT EXISTS public.attendance_records (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  work_date     date NOT NULL,
  type_code     text NOT NULL REFERENCES public.attendance_types(code),
  created_by    uuid NOT NULL REFERENCES public.users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_by    uuid REFERENCES public.users(id),
  updated_at    timestamptz,
  UNIQUE (user_id, work_date)
);

CREATE INDEX IF NOT EXISTS idx_attendance_records_user_date
  ON public.attendance_records (user_id, work_date);

-- =============================================================
-- BẢNG: attendance_edit_logs — Lịch sử sửa + giải trình
-- Khi ngày đã qua nửa đêm, mọi sửa đổi phải kèm lý do
-- =============================================================
CREATE TABLE IF NOT EXISTS public.attendance_edit_logs (
  id             uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  record_id      uuid NOT NULL REFERENCES public.attendance_records(id) ON DELETE CASCADE,
  old_type_code  text,
  new_type_code  text,
  reason         text NOT NULL,
  edited_by      uuid NOT NULL REFERENCES public.users(id),
  edited_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_edit_logs_record
  ON public.attendance_edit_logs (record_id);

-- =============================================================
-- BẢNG: day_off_ledger — Sổ cái tích lũy nghỉ bù/nghỉ tuần
-- Mỗi lần phát sinh/dùng = 1 dòng, số dư = SUM(change)
-- =============================================================
CREATE TABLE IF NOT EXISTS public.day_off_ledger (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id           uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  ledger_type       text NOT NULL CHECK (ledger_type IN ('comp_off','weekly_off')),
  change            numeric(5,2) NOT NULL,
  source_record_id  uuid REFERENCES public.attendance_records(id) ON DELETE CASCADE,
  note              text,
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ledger_user_type
  ON public.day_off_ledger (user_id, ledger_type);
