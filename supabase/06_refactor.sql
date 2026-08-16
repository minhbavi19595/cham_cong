-- =============================================================
-- 06_REFACTOR.SQL — Cập nhật kiến trúc (Chạy 1 lần trên SQL Editor)
-- =============================================================

-- 1. BỎ RLS KHẮT KHE, CHO PHÉP STAFF CHẤM HỘ NHAU
DROP POLICY IF EXISTS "att_records_staff_read_self" ON public.attendance_records;
DROP POLICY IF EXISTS "att_records_staff_insert" ON public.attendance_records;
DROP POLICY IF EXISTS "att_records_staff_update" ON public.attendance_records;
DROP POLICY IF EXISTS "edit_logs_staff_read" ON public.attendance_edit_logs;
DROP POLICY IF EXISTS "edit_logs_staff_insert" ON public.attendance_edit_logs;
DROP POLICY IF EXISTS "ledger_staff_read" ON public.day_off_ledger;

CREATE POLICY "att_records_all_access" ON public.attendance_records FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "edit_logs_all_access" ON public.attendance_edit_logs FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "ledger_all_access" ON public.day_off_ledger FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 2. XOÁ BẢNG THỪA
DROP TABLE IF EXISTS public.attendance_open_days;
DROP TABLE IF EXISTS public.holidays;

-- 3. CẬP NHẬT HÀM get_day_category (Bỏ holiday)
CREATE OR REPLACE FUNCTION public.get_day_category(p_date date)
RETURNS text
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE v_dow int;
BEGIN
  v_dow := EXTRACT(DOW FROM p_date);
  IF v_dow = 0 OR v_dow = 6 THEN RETURN 'weekend'; END IF;
  RETURN 'weekday';
END;
$$;

-- 4. VIỆT HOÁ NHÓM LUẬT VÀ THÊM LOẠI CÔNG "TRỰC NGÀY LÊ"
UPDATE public.attendance_types SET type_group = 'Hành chính' WHERE type_group = 'HC';
UPDATE public.attendance_types SET type_group = 'Nghỉ phép' WHERE type_group = 'NP';
UPDATE public.attendance_types SET type_group = 'Ốm đau / Thai sản' WHERE type_group = 'OM';
UPDATE public.attendance_types SET type_group = 'Nửa ngày / Trễ' WHERE type_group = 'HN_HC';
UPDATE public.attendance_types SET type_group = 'Trực' WHERE type_group = 'DUTY';

UPDATE public.attendance_rules SET type_group = 'Hành chính' WHERE type_group = 'HC';
UPDATE public.attendance_rules SET type_group = 'Nghỉ phép' WHERE type_group = 'NP';
UPDATE public.attendance_rules SET type_group = 'Ốm đau / Thai sản' WHERE type_group = 'OM';
UPDATE public.attendance_rules SET type_group = 'Nửa ngày / Trễ' WHERE type_group = 'HN_HC';
UPDATE public.attendance_rules SET type_group = 'Trực' WHERE type_group = 'DUTY';

INSERT INTO public.attendance_types (code, name, type_group, is_active, sort_order)
VALUES ('TR_NL', 'Trực ngày lễ', 'Trực', true, 8)
ON CONFLICT (code) DO NOTHING;

-- Xoá rule cũ của DUTY (Trực) để cài lại rule mới
DELETE FROM public.attendance_rules WHERE type_group = 'Trực';

INSERT INTO public.attendance_rules (type_group, day_category, comp_off_delta, weekly_off_delta, leave_delta) VALUES
  ('Trực', 'weekday', 1, 0, 0),    -- Trực ngày thường: +1 nghỉ bù
  ('Trực', 'weekend', 1, 1, 0);    -- Trực cuối tuần: +1 nghỉ bù, +1 nghỉ tuần

-- Rule riêng cho mã TR_NL (Trực ngày lễ): +2 nghỉ bù, không phân biệt ngày thường/cuối tuần
-- Note: Rule engine dựa theo (type_group, day_category). Để TR_NL được ưu tiên, ta gán mã này có group riêng.
UPDATE public.attendance_types SET type_group = 'Trực ngày lễ' WHERE code = 'TR_NL';
INSERT INTO public.attendance_rules (type_group, day_category, comp_off_delta, weekly_off_delta, leave_delta) VALUES
  ('Trực ngày lễ', 'weekday', 2, 0, 0),
  ('Trực ngày lễ', 'weekend', 2, 0, 0);

-- 5. CẬP NHẬT RPC rpc_cham_cong
CREATE OR REPLACE FUNCTION public.rpc_cham_cong(
  p_user_id     uuid,  -- THÊM THAM SỐ NÀY ĐỂ CHẤM CHO NGƯỜI KHÁC
  p_work_date   date,
  p_type_code   text,
  p_reason      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_current_user  uuid;
  v_is_past       boolean;
  v_is_locked     boolean;
  v_existing_id   uuid;
  v_old_type      text;
BEGIN
  SELECT id INTO v_current_user FROM public.users WHERE auth_id = auth.uid();
  IF v_current_user IS NULL THEN RETURN jsonb_build_object('error', 'Lỗi xác thực'); END IF;

  -- KHOÁ THÁNG: Nếu ngày chấm công < ngày mùng 1 của tháng hiện tại
  v_is_locked := p_work_date < date_trunc('month', (NOW() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date);
  IF v_is_locked THEN
    RETURN jsonb_build_object('error', 'Tháng này đã chốt, không thể chỉnh sửa');
  END IF;

  v_is_past := p_work_date < (NOW() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date;
  IF v_is_past AND (p_reason IS NULL OR trim(p_reason) = '') THEN
    RETURN jsonb_build_object('error', 'Ngày đã qua — bắt buộc nhập lý do');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.attendance_types WHERE code = p_type_code AND is_active) THEN
    RETURN jsonb_build_object('error', 'Loại công không hợp lệ');
  END IF;

  SELECT id, type_code INTO v_existing_id, v_old_type
  FROM public.attendance_records
  WHERE user_id = p_user_id AND work_date = p_work_date;

  IF v_existing_id IS NULL THEN
    INSERT INTO public.attendance_records (user_id, work_date, type_code, created_by)
    VALUES (p_user_id, p_work_date, p_type_code, v_current_user);
  ELSE
    UPDATE public.attendance_records
    SET type_code = p_type_code, updated_by = v_current_user, updated_at = now()
    WHERE id = v_existing_id;

    IF v_is_past THEN
      INSERT INTO public.attendance_edit_logs (record_id, old_type_code, new_type_code, reason, edited_by)
      VALUES (v_existing_id, v_old_type, p_type_code, p_reason, v_current_user);
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- Xoá function rpc_get_open_days_in_month
DROP FUNCTION IF EXISTS public.rpc_get_open_days_in_month;

-- Cập nhật rpc_get_bang_cham_cong để bỏ join với open_days
CREATE OR REPLACE FUNCTION public.rpc_get_bang_cham_cong(p_month int, p_year int)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_result jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(t)) INTO v_result
  FROM (
    SELECT ar.id, ar.user_id, u.full_name, u.position, ar.work_date, ar.type_code,
           at.name AS type_name, at.type_group, ar.created_at, ar.updated_at
    FROM public.attendance_records ar
    JOIN public.users u ON u.id = ar.user_id
    JOIN public.attendance_types at ON at.code = ar.type_code
    WHERE EXTRACT(MONTH FROM ar.work_date) = p_month
      AND EXTRACT(YEAR  FROM ar.work_date) = p_year
      AND u.is_active = true
    ORDER BY u.full_name, ar.work_date
  ) t;
  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- Cập nhật rpc_get_all_staff để cho phép cả staff cũng xem được danh sách nhân viên (để chấm công hộ)
CREATE OR REPLACE FUNCTION public.rpc_get_all_staff()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_result  jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(t))
  INTO v_result
  FROM (
    SELECT id, full_name, email, role, position, is_active, created_at
    FROM public.users
    WHERE manager_id IS NULL
    ORDER BY full_name
  ) t;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- RPC lấy số dư của 1 nhân viên cụ thể (Admin dùng để hiện trên grid)
CREATE OR REPLACE FUNCTION public.rpc_get_so_du_by_user(
  p_target_user_id  uuid,
  p_year            int DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_year        int;
  v_comp_off    numeric;
  v_weekly_off  numeric;
  v_leave_total numeric;
BEGIN
  v_year := COALESCE(p_year, EXTRACT(YEAR FROM now())::int);

  SELECT COALESCE(SUM(change), 0) INTO v_comp_off
  FROM public.day_off_ledger
  WHERE user_id = p_target_user_id AND ledger_type = 'comp_off';

  SELECT COALESCE(SUM(change), 0) INTO v_weekly_off
  FROM public.day_off_ledger
  WHERE user_id = p_target_user_id AND ledger_type = 'weekly_off';

  SELECT COALESCE(total_days, 12) INTO v_leave_total
  FROM public.leave_quota
  WHERE user_id = p_target_user_id AND year = v_year;

  RETURN jsonb_build_object(
    'comp_off',        v_comp_off,
    'weekly_off',      v_weekly_off,
    'leave_remaining', COALESCE(v_leave_total, 12)
  );
END;
$$;
