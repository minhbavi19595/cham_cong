-- =============================================================
-- 03_RPCS.SQL — Stored Procedures (gọi từ frontend qua supabase.rpc())
-- Chạy sau 02_functions_triggers.sql
-- =============================================================

-- =============================================================
-- RPC: rpc_cham_cong
-- Chuyên viên chấm công hoặc sửa ngày đã chốt (kèm reason)
-- p_reason: BẮT BUỘC nếu ngày đã qua nửa đêm
-- =============================================================
CREATE OR REPLACE FUNCTION public.rpc_cham_cong(
  p_work_date   date,
  p_type_code   text,
  p_reason      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_user_id       uuid;
  v_is_open_day   boolean;
  v_is_past       boolean;
  v_existing_id   uuid;
  v_old_type      text;
BEGIN
  -- Lấy user_id từ token
  SELECT id INTO v_user_id FROM public.users WHERE auth_id = auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Không xác định được tài khoản');
  END IF;

  -- Kiểm tra ngày đã mở chưa
  v_is_open_day := EXISTS (
    SELECT 1 FROM public.attendance_open_days WHERE work_date = p_work_date
  );

  -- Ngày đã qua nếu qua nửa đêm (theo UTC+7 — điều chỉnh timezone nếu cần)
  v_is_past := p_work_date < (NOW() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date;

  -- Ngày chưa mở và chưa qua → không cho chấm
  IF NOT v_is_open_day AND NOT v_is_past THEN
    RETURN jsonb_build_object('error', 'Ngày này chưa được mở chấm công');
  END IF;

  -- Ngày đã qua → bắt buộc có giải trình
  IF v_is_past AND (p_reason IS NULL OR trim(p_reason) = '') THEN
    RETURN jsonb_build_object('error', 'Ngày đã qua — bắt buộc nhập lý do giải trình');
  END IF;

  -- Kiểm tra loại công hợp lệ
  IF NOT EXISTS (SELECT 1 FROM public.attendance_types WHERE code = p_type_code AND is_active) THEN
    RETURN jsonb_build_object('error', 'Loại công không hợp lệ');
  END IF;

  -- Lấy record đang có (nếu đã chấm trước đó)
  SELECT id, type_code INTO v_existing_id, v_old_type
  FROM public.attendance_records
  WHERE user_id = v_user_id AND work_date = p_work_date;

  IF v_existing_id IS NULL THEN
    -- INSERT mới
    INSERT INTO public.attendance_records
      (user_id, work_date, type_code, created_by)
    VALUES
      (v_user_id, p_work_date, p_type_code, v_user_id);
  ELSE
    -- UPDATE (trigger sẽ revert cũ + apply mới)
    UPDATE public.attendance_records
    SET type_code  = p_type_code,
        updated_by = v_user_id,
        updated_at = now()
    WHERE id = v_existing_id;

    -- Ghi log giải trình nếu ngày đã qua
    IF v_is_past THEN
      INSERT INTO public.attendance_edit_logs
        (record_id, old_type_code, new_type_code, reason, edited_by)
      VALUES
        (v_existing_id, v_old_type, p_type_code, p_reason, v_user_id);
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- =============================================================
-- RPC: rpc_get_bang_cham_cong
-- Lấy toàn bộ dữ liệu bảng chấm công 1 tháng
-- Admin: xem tất cả nhân viên; Staff: chỉ xem mình
-- =============================================================
CREATE OR REPLACE FUNCTION public.rpc_get_bang_cham_cong(
  p_month int,
  p_year  int
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_current_user_id   uuid;
  v_role              text;
  v_result            jsonb;
BEGIN
  SELECT id, role INTO v_current_user_id, v_role
  FROM public.users WHERE auth_id = auth.uid();

  SELECT jsonb_agg(row_to_json(t))
  INTO v_result
  FROM (
    SELECT
      ar.id,
      ar.user_id,
      u.full_name,
      u.position,
      ar.work_date,
      ar.type_code,
      at.name        AS type_name,
      at.type_group,
      ar.created_at,
      ar.updated_at,
      -- Ngày mở?
      EXISTS (
        SELECT 1 FROM public.attendance_open_days od WHERE od.work_date = ar.work_date
      ) AS is_open_day
    FROM public.attendance_records ar
    JOIN public.users u ON u.id = ar.user_id
    JOIN public.attendance_types at ON at.code = ar.type_code
    WHERE
      EXTRACT(MONTH FROM ar.work_date) = p_month
      AND EXTRACT(YEAR  FROM ar.work_date) = p_year
      AND (v_role = 'admin' OR ar.user_id = v_current_user_id)
      AND u.is_active = true
    ORDER BY u.full_name, ar.work_date
  ) t;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- =============================================================
-- RPC: rpc_get_so_du
-- Lấy số dư nghỉ bù / nghỉ tuần / phép còn lại của user hiện tại
-- =============================================================
CREATE OR REPLACE FUNCTION public.rpc_get_so_du(p_year int DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_user_id     uuid;
  v_year        int;
  v_comp_off    numeric;
  v_weekly_off  numeric;
  v_leave_used  numeric;
  v_leave_total numeric;
BEGIN
  SELECT id INTO v_user_id FROM public.users WHERE auth_id = auth.uid();
  v_year := COALESCE(p_year, EXTRACT(YEAR FROM now())::int);

  SELECT COALESCE(SUM(change), 0) INTO v_comp_off
  FROM public.day_off_ledger
  WHERE user_id = v_user_id AND ledger_type = 'comp_off';

  SELECT COALESCE(SUM(change), 0) INTO v_weekly_off
  FROM public.day_off_ledger
  WHERE user_id = v_user_id AND ledger_type = 'weekly_off';

  -- Phép: tổng phép theo năm (đã trừ leave_delta)
  SELECT COALESCE(total_days, 12) INTO v_leave_total
  FROM public.leave_quota
  WHERE user_id = v_user_id AND year = v_year;

  RETURN jsonb_build_object(
    'comp_off',    v_comp_off,
    'weekly_off',  v_weekly_off,
    'leave_remaining', COALESCE(v_leave_total, 12)
  );
END;
$$;

-- =============================================================
-- RPC: rpc_get_tong_hop_thang
-- Tổng hợp cuối bảng: đếm số ngày theo từng loại trong tháng
-- =============================================================
CREATE OR REPLACE FUNCTION public.rpc_get_tong_hop_thang(
  p_month   int,
  p_year    int,
  p_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_current_user_id uuid;
  v_role            text;
  v_target_user_id  uuid;
  v_result          jsonb;
BEGIN
  SELECT id, role INTO v_current_user_id, v_role
  FROM public.users WHERE auth_id = auth.uid();

  -- Staff chỉ xem của mình
  IF v_role = 'staff' THEN
    v_target_user_id := v_current_user_id;
  ELSE
    v_target_user_id := COALESCE(p_user_id, v_current_user_id);
  END IF;

  SELECT jsonb_object_agg(type_code, cnt)
  INTO v_result
  FROM (
    SELECT type_code, COUNT(*) AS cnt
    FROM public.attendance_records
    WHERE user_id = v_target_user_id
      AND EXTRACT(MONTH FROM work_date) = p_month
      AND EXTRACT(YEAR  FROM work_date) = p_year
    GROUP BY type_code
  ) t;

  -- Thêm ngày công hành chính
  SELECT v_result || jsonb_build_object(
    'work_days',
    (
      SELECT COUNT(*)
      FROM public.attendance_records ar
      JOIN public.attendance_types   at ON at.code = ar.type_code
      WHERE ar.user_id = v_target_user_id
        AND EXTRACT(MONTH FROM ar.work_date) = p_month
        AND EXTRACT(YEAR  FROM ar.work_date) = p_year
        AND at.counts_as_work_day = true
    )
  ) INTO v_result;

  RETURN COALESCE(v_result, '{}'::jsonb);
END;
$$;

-- =============================================================
-- RPC: rpc_admin_get_giai_trinh
-- Admin đọc lịch sử giải trình, lọc theo nhân viên/ngày
-- =============================================================
CREATE OR REPLACE FUNCTION public.rpc_admin_get_giai_trinh(
  p_user_id     uuid    DEFAULT NULL,
  p_from_date   date    DEFAULT NULL,
  p_to_date     date    DEFAULT NULL,
  p_limit       int     DEFAULT 50,
  p_offset      int     DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_role    text;
  v_result  jsonb;
BEGIN
  SELECT role INTO v_role FROM public.users WHERE auth_id = auth.uid();
  IF v_role <> 'admin' THEN
    RETURN jsonb_build_object('error', 'Không có quyền truy cập');
  END IF;

  SELECT jsonb_agg(row_to_json(t))
  INTO v_result
  FROM (
    SELECT
      el.id,
      el.record_id,
      el.old_type_code,
      el.new_type_code,
      el.reason,
      el.edited_at,
      ar.work_date,
      u.full_name  AS editor_name,
      u.id         AS editor_id
    FROM public.attendance_edit_logs el
    JOIN public.attendance_records   ar ON ar.id = el.record_id
    JOIN public.users                u  ON u.id  = el.edited_by
    WHERE (p_user_id IS NULL OR el.edited_by = p_user_id)
      AND (p_from_date IS NULL OR ar.work_date >= p_from_date)
      AND (p_to_date   IS NULL OR ar.work_date <= p_to_date)
    ORDER BY el.edited_at DESC
    LIMIT p_limit OFFSET p_offset
  ) t;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- =============================================================
-- RPC: rpc_get_all_staff — Admin lấy danh sách nhân viên
-- =============================================================
CREATE OR REPLACE FUNCTION public.rpc_get_all_staff()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_role    text;
  v_result  jsonb;
BEGIN
  SELECT role INTO v_role FROM public.users WHERE auth_id = auth.uid();
  IF v_role <> 'admin' THEN
    RETURN jsonb_build_object('error', 'Không có quyền');
  END IF;

  SELECT jsonb_agg(row_to_json(t))
  INTO v_result
  FROM (
    SELECT id, full_name, email, role, position, is_active, created_at
    FROM public.users
    ORDER BY full_name
  ) t;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- =============================================================
-- RPC: rpc_get_open_days_in_month — Lấy ngày đã mở trong tháng
-- =============================================================
CREATE OR REPLACE FUNCTION public.rpc_get_open_days_in_month(p_month int, p_year int)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE v_result jsonb;
BEGIN
  SELECT jsonb_agg(work_date ORDER BY work_date)
  INTO v_result
  FROM public.attendance_open_days
  WHERE EXTRACT(MONTH FROM work_date) = p_month
    AND EXTRACT(YEAR  FROM work_date) = p_year;
  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;
