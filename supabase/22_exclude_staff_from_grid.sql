-- =============================================================
-- 22_EXCLUDE_STAFF_FROM_GRID.SQL
-- Cập nhật các hàm để loại bỏ tài khoản Staff khỏi bảng chấm công
-- (Chỉ hiển thị các nhân viên ảo do Staff quản lý)
-- =============================================================

CREATE OR REPLACE FUNCTION public.rpc_get_team_members(
  p_manager_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
  v_current_user uuid;
  v_role text;
  v_target_manager uuid;
BEGIN
  SELECT id, role INTO v_current_user, v_role FROM public.users WHERE auth_id = auth.uid();
  IF v_role = 'staff' THEN
    v_target_manager := v_current_user;
  ELSE
    v_target_manager := COALESCE(p_manager_id, v_current_user);
  END IF;

  SELECT jsonb_agg(row_to_json(t))
  INTO v_result
  FROM (
    SELECT id, full_name, email, role, position, is_active, created_at, manager_id
    FROM public.users
    WHERE manager_id = v_target_manager AND is_active = true
    ORDER BY full_name
  ) t;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_get_bang_cham_cong(
  p_month int, 
  p_year int,
  p_manager_id uuid DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE 
  v_result jsonb;
  v_current_user uuid;
  v_role text;
  v_target_manager uuid;
BEGIN
  SELECT id, role INTO v_current_user, v_role FROM public.users WHERE auth_id = auth.uid();
  
  IF v_role = 'staff' THEN
    v_target_manager := v_current_user;
  ELSE
    v_target_manager := COALESCE(p_manager_id, v_current_user);
  END IF;

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
      AND u.manager_id = v_target_manager
    ORDER BY u.full_name, ar.work_date
  ) t;
  
  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

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
  v_weekend_count     int;
BEGIN
  SELECT id, role INTO v_current_user_id, v_role
  FROM public.users WHERE auth_id = auth.uid();

  IF v_role = 'admin' THEN
    v_target_manager := COALESCE(p_manager_id, v_current_user_id);
  ELSE
    v_target_manager := v_current_user_id;
  END IF;

  v_weekend_count := public.get_weekends_in_month(p_month, p_year);

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
      (
        SELECT COALESCE(SUM(l.change), 0)
        FROM public.day_off_ledger l
        WHERE l.user_id = u.id AND l.ledger_type = 'comp_off'
      ) AS comp_off_balance,
      (
        v_weekend_count + 
        COALESCE((
          SELECT SUM(l.change)
          FROM public.day_off_ledger l
          JOIN public.attendance_records ar ON ar.id = l.source_record_id
          WHERE l.user_id = u.id 
            AND l.ledger_type = 'weekly_off'
            AND EXTRACT(MONTH FROM ar.work_date) = p_month
            AND EXTRACT(YEAR FROM ar.work_date) = p_year
        ), 0)
      ) AS weekly_off_balance,
      (
        SELECT COALESCE((SELECT total_days FROM public.leave_quota WHERE user_id = u.id AND year = p_year), 12) +
               COALESCE((SELECT SUM(change) FROM public.day_off_ledger WHERE user_id = u.id AND ledger_type = 'annual_leave'), 0)
      ) AS leave_remaining
    FROM public.users u
    WHERE u.manager_id = v_target_manager
      AND u.is_active = true
    ORDER BY u.full_name
  ) t;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;
