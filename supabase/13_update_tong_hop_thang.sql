-- =============================================================
-- 13_UPDATE_TONG_HOP_THANG.SQL
-- Bổ sung cột leave_remaining vào kết quả trả về của rpc_get_tong_hop_thang
-- để hiển thị lên bảng chấm công một cách tối ưu nhất.
-- =============================================================

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
      (
        SELECT COALESCE(SUM(l.change), 0)
        FROM public.day_off_ledger l
        WHERE l.user_id = u.id AND l.ledger_type = 'comp_off'
      ) AS comp_off_balance,
      (
        SELECT COALESCE(SUM(l.change), 0)
        FROM public.day_off_ledger l
        WHERE l.user_id = u.id AND l.ledger_type = 'weekly_off'
      ) AS weekly_off_balance,
      (
        SELECT COALESCE((SELECT total_days FROM public.leave_quota WHERE user_id = u.id AND year = p_year), 12) +
               COALESCE((SELECT SUM(change) FROM public.day_off_ledger WHERE user_id = u.id AND ledger_type = 'annual_leave'), 0)
      ) AS leave_remaining
    FROM public.users u
    WHERE (u.manager_id = v_target_manager OR u.id = v_target_manager)
      AND u.is_active = true
    ORDER BY u.full_name
  ) t;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;
