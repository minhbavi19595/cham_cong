-- =============================================================
-- 12_FIX_RPC_SIGNATURES.SQL
-- Dọn dẹp triệt để các phiên bản cũ của Hàm lấy dữ liệu
-- Tránh lỗi "Could not find function" do PostgreSQL bị nhầm lẫn giữa các hàm trùng tên
-- =============================================================

-- 1. Xoá SẠCH mọi phiên bản cũ của Bảng chấm công
DROP FUNCTION IF EXISTS public.rpc_get_bang_cham_cong(integer, integer);
DROP FUNCTION IF EXISTS public.rpc_get_bang_cham_cong(integer, integer, uuid);

-- 2. Tạo lại hàm Bảng chấm công chuẩn nhất
CREATE OR REPLACE FUNCTION public.rpc_get_bang_cham_cong(
  p_month int, 
  p_year int,
  p_manager_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_current_user_id   uuid;
  v_role              text;
  v_target_manager    uuid;
  v_result            jsonb;
BEGIN
  SELECT id, role INTO v_current_user_id, v_role
  FROM public.users WHERE auth_id = auth.uid();

  -- Xác định manager cần lấy dữ liệu
  IF v_role = 'admin' THEN
    v_target_manager := COALESCE(p_manager_id, v_current_user_id);
  ELSE
    v_target_manager := v_current_user_id;
  END IF;

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
      ar.updated_at
    FROM public.attendance_records ar
    JOIN public.users u ON u.id = ar.user_id
    JOIN public.attendance_types at ON at.code = ar.type_code
    WHERE
      EXTRACT(MONTH FROM ar.work_date) = p_month
      AND EXTRACT(YEAR  FROM ar.work_date) = p_year
      AND (u.manager_id = v_target_manager OR u.id = v_target_manager)
      AND u.is_active = true
    ORDER BY u.full_name, ar.work_date
  ) t;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- 3. Xoá SẠCH mọi phiên bản cũ của Tổng hợp tháng
DROP FUNCTION IF EXISTS public.rpc_get_tong_hop_thang(integer, integer);
DROP FUNCTION IF EXISTS public.rpc_get_tong_hop_thang(integer, integer, uuid);

-- 4. Tạo lại hàm Tổng hợp tháng chuẩn nhất
CREATE OR REPLACE FUNCTION public.rpc_get_tong_hop_thang(
  p_month int, 
  p_year int,
  p_manager_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_current_user_id   uuid;
  v_role              text;
  v_target_manager    uuid;
  v_result            jsonb;
BEGIN
  SELECT id, role INTO v_current_user_id, v_role
  FROM public.users WHERE auth_id = auth.uid();

  IF v_role = 'admin' THEN
    v_target_manager := COALESCE(p_manager_id, v_current_user_id);
  ELSE
    v_target_manager := v_current_user_id;
  END IF;

  SELECT jsonb_agg(row_to_json(t))
  INTO v_result
  FROM (
    SELECT
      u.id AS user_id,
      u.full_name,
      u.position,
      (
        SELECT COUNT(*)
        FROM public.attendance_records ar
        JOIN public.attendance_types at ON at.code = ar.type_code
        JOIN public.attendance_rules ru ON ru.type_group = at.type_group
           AND ru.day_category = public.get_day_category(ar.work_date)
        WHERE ar.user_id = u.id
          AND EXTRACT(MONTH FROM ar.work_date) = p_month
          AND EXTRACT(YEAR  FROM ar.work_date) = p_year
          AND ru.counts_as_work_day = true
      ) AS work_days,
      COALESCE((
        SELECT SUM(l.change)
        FROM public.day_off_ledger l
        JOIN public.attendance_records ar ON ar.id = l.source_record_id
        WHERE l.user_id = u.id 
          AND l.ledger_type = 'annual_leave'
          AND EXTRACT(MONTH FROM ar.work_date) = p_month
          AND EXTRACT(YEAR FROM ar.work_date) = p_year
      ), 0) AS leave_days,
      (
        SELECT COALESCE(SUM(l.change), 0)
        FROM public.day_off_ledger l
        WHERE l.user_id = u.id AND l.ledger_type = 'comp_off'
      ) AS comp_off_balance,
      (
        SELECT COALESCE(SUM(l.change), 0)
        FROM public.day_off_ledger l
        WHERE l.user_id = u.id AND l.ledger_type = 'weekly_off'
      ) AS weekly_off_balance
    FROM public.users u
    WHERE (u.manager_id = v_target_manager OR u.id = v_target_manager)
      AND u.is_active = true
    ORDER BY u.full_name
  ) t;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;
