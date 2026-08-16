-- =============================================================
-- 01_RLS.SQL — Row Level Security
-- Chạy sau 00_schema.sql
-- =============================================================

-- Bật RLS cho tất cả bảng
ALTER TABLE public.users                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leave_quota           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.holidays              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_types      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_rules      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_open_days  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_records    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_edit_logs  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.day_off_ledger        ENABLE ROW LEVEL SECURITY;

-- =============================================================
-- Helper function lấy role của user hiện tại
-- =============================================================
CREATE OR REPLACE FUNCTION public.get_current_user_role()
RETURNS text
LANGUAGE sql SECURITY DEFINER
STABLE
AS $$
  SELECT role FROM public.users
  WHERE auth_id = auth.uid()
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_current_user_id()
RETURNS uuid
LANGUAGE sql SECURITY DEFINER
STABLE
AS $$
  SELECT id FROM public.users
  WHERE auth_id = auth.uid()
  LIMIT 1;
$$;

-- =============================================================
-- BẢNG: users
-- Admin: đọc/ghi tất cả
-- Staff: chỉ đọc record của chính mình
-- =============================================================
DROP POLICY IF EXISTS "users_admin_all" ON public.users;
CREATE POLICY "users_admin_all" ON public.users
  FOR ALL
  TO authenticated
  USING (public.get_current_user_role() = 'admin')
  WITH CHECK (public.get_current_user_role() = 'admin');

DROP POLICY IF EXISTS "users_staff_read_self" ON public.users;
CREATE POLICY "users_staff_read_self" ON public.users
  FOR SELECT
  TO authenticated
  USING (auth_id = auth.uid());

-- =============================================================
-- BẢNG: leave_quota
-- Admin: full
-- Staff: chỉ đọc của mình
-- =============================================================
DROP POLICY IF EXISTS "leave_quota_admin" ON public.leave_quota;
CREATE POLICY "leave_quota_admin" ON public.leave_quota
  FOR ALL TO authenticated
  USING (public.get_current_user_role() = 'admin')
  WITH CHECK (public.get_current_user_role() = 'admin');

DROP POLICY IF EXISTS "leave_quota_staff_read" ON public.leave_quota;
CREATE POLICY "leave_quota_staff_read" ON public.leave_quota
  FOR SELECT TO authenticated
  USING (user_id = public.get_current_user_id());

-- =============================================================
-- BẢNG: holidays — đọc mọi người, ghi chỉ admin
-- =============================================================
DROP POLICY IF EXISTS "holidays_read_all" ON public.holidays;
CREATE POLICY "holidays_read_all" ON public.holidays
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "holidays_admin_write" ON public.holidays;
CREATE POLICY "holidays_admin_write" ON public.holidays
  FOR ALL TO authenticated
  USING (public.get_current_user_role() = 'admin')
  WITH CHECK (public.get_current_user_role() = 'admin');

-- =============================================================
-- BẢNG: attendance_types — đọc mọi người, ghi chỉ admin
-- =============================================================
DROP POLICY IF EXISTS "att_types_read_all" ON public.attendance_types;
CREATE POLICY "att_types_read_all" ON public.attendance_types
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "att_types_admin_write" ON public.attendance_types;
CREATE POLICY "att_types_admin_write" ON public.attendance_types
  FOR ALL TO authenticated
  USING (public.get_current_user_role() = 'admin')
  WITH CHECK (public.get_current_user_role() = 'admin');

-- =============================================================
-- BẢNG: attendance_rules — đọc mọi người, ghi chỉ admin
-- =============================================================
DROP POLICY IF EXISTS "att_rules_read_all" ON public.attendance_rules;
CREATE POLICY "att_rules_read_all" ON public.attendance_rules
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "att_rules_admin_write" ON public.attendance_rules;
CREATE POLICY "att_rules_admin_write" ON public.attendance_rules
  FOR ALL TO authenticated
  USING (public.get_current_user_role() = 'admin')
  WITH CHECK (public.get_current_user_role() = 'admin');

-- =============================================================
-- BẢNG: attendance_open_days — đọc mọi người, ghi chỉ admin
-- =============================================================
DROP POLICY IF EXISTS "open_days_read_all" ON public.attendance_open_days;
CREATE POLICY "open_days_read_all" ON public.attendance_open_days
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "open_days_admin_write" ON public.attendance_open_days;
CREATE POLICY "open_days_admin_write" ON public.attendance_open_days
  FOR ALL TO authenticated
  USING (public.get_current_user_role() = 'admin')
  WITH CHECK (public.get_current_user_role() = 'admin');

-- =============================================================
-- BẢNG: attendance_records
-- Admin: chỉ đọc (KHÔNG ghi hộ — chuyên viên tự thực hiện)
-- Staff: đọc+ghi chỉ record của chính mình
-- =============================================================
DROP POLICY IF EXISTS "att_records_admin_read" ON public.attendance_records;
CREATE POLICY "att_records_admin_read" ON public.attendance_records
  FOR SELECT TO authenticated
  USING (public.get_current_user_role() = 'admin');

DROP POLICY IF EXISTS "att_records_staff_read_self" ON public.attendance_records;
CREATE POLICY "att_records_staff_read_self" ON public.attendance_records
  FOR SELECT TO authenticated
  USING (user_id = public.get_current_user_id());

DROP POLICY IF EXISTS "att_records_staff_insert" ON public.attendance_records;
CREATE POLICY "att_records_staff_insert" ON public.attendance_records
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = public.get_current_user_id()
    AND public.get_current_user_role() = 'staff'
  );

DROP POLICY IF EXISTS "att_records_staff_update" ON public.attendance_records;
CREATE POLICY "att_records_staff_update" ON public.attendance_records
  FOR UPDATE TO authenticated
  USING (
    user_id = public.get_current_user_id()
    AND public.get_current_user_role() = 'staff'
  )
  WITH CHECK (
    user_id = public.get_current_user_id()
  );

-- =============================================================
-- BẢNG: attendance_edit_logs
-- Admin: đọc tất cả
-- Staff: chỉ đọc log của record của mình
-- =============================================================
DROP POLICY IF EXISTS "edit_logs_admin_read" ON public.attendance_edit_logs;
CREATE POLICY "edit_logs_admin_read" ON public.attendance_edit_logs
  FOR SELECT TO authenticated
  USING (public.get_current_user_role() = 'admin');

DROP POLICY IF EXISTS "edit_logs_staff_read" ON public.attendance_edit_logs;
CREATE POLICY "edit_logs_staff_read" ON public.attendance_edit_logs
  FOR SELECT TO authenticated
  USING (
    edited_by = public.get_current_user_id()
  );

DROP POLICY IF EXISTS "edit_logs_staff_insert" ON public.attendance_edit_logs;
CREATE POLICY "edit_logs_staff_insert" ON public.attendance_edit_logs
  FOR INSERT TO authenticated
  WITH CHECK (edited_by = public.get_current_user_id());

-- =============================================================
-- BẢNG: day_off_ledger
-- Admin: đọc tất cả
-- Staff: chỉ đọc của mình
-- Ghi: chỉ qua trigger/function (SECURITY DEFINER), không ai insert trực tiếp
-- =============================================================
DROP POLICY IF EXISTS "ledger_admin_read" ON public.day_off_ledger;
CREATE POLICY "ledger_admin_read" ON public.day_off_ledger
  FOR SELECT TO authenticated
  USING (public.get_current_user_role() = 'admin');

DROP POLICY IF EXISTS "ledger_staff_read" ON public.day_off_ledger;
CREATE POLICY "ledger_staff_read" ON public.day_off_ledger
  FOR SELECT TO authenticated
  USING (user_id = public.get_current_user_id());
