-- =============================================================
-- 10_FIX_LEAVE_QUOTA.SQL
-- Sửa logic tính phép năm: Quỹ gốc (leave_quota) và Biến động (day_off_ledger)
-- =============================================================

-- 1. Cho phép day_off_ledger ghi nhận loại 'annual_leave'
ALTER TABLE public.day_off_ledger DROP CONSTRAINT IF EXISTS day_off_ledger_ledger_type_check;
ALTER TABLE public.day_off_ledger ADD CONSTRAINT day_off_ledger_ledger_type_check CHECK (ledger_type IN ('comp_off', 'weekly_off', 'annual_leave'));

-- 2. Cập nhật trigger apply_rule_for_record
CREATE OR REPLACE FUNCTION public.apply_rule_for_record(
  p_record_id   uuid,
  p_user_id     uuid,
  p_type_code   text,
  p_work_date   date,
  p_mode        text
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_type_group   text;
  v_day_category text;
  v_rule         record;
  v_multiplier   int := 1;
BEGIN
  IF p_mode = 'revert' THEN
    v_multiplier := -1;
  END IF;

  SELECT type_group INTO v_type_group FROM public.attendance_types WHERE code = p_type_code;
  IF v_type_group IS NULL THEN RETURN; END IF;

  v_day_category := public.get_day_category(p_work_date);

  SELECT * INTO v_rule FROM public.attendance_rules
  WHERE type_group = v_type_group AND day_category = v_day_category;
  IF NOT FOUND THEN RETURN; END IF;

  -- Ghi nghỉ bù
  IF v_rule.comp_off_delta <> 0 THEN
    INSERT INTO public.day_off_ledger (user_id, ledger_type, change, source_record_id, note)
    VALUES (p_user_id, 'comp_off', v_rule.comp_off_delta * v_multiplier, p_record_id, p_mode || ': ' || p_type_code || ' on ' || p_work_date::text);
  END IF;

  -- Ghi nghỉ tuần
  IF v_rule.weekly_off_delta <> 0 THEN
    INSERT INTO public.day_off_ledger (user_id, ledger_type, change, source_record_id, note)
    VALUES (p_user_id, 'weekly_off', v_rule.weekly_off_delta * v_multiplier, p_record_id, p_mode || ': ' || p_type_code || ' on ' || p_work_date::text);
  END IF;

  -- Ghi nghỉ phép (MỚI: Ghi vào ledger thay vì trừ thẳng vào quota)
  IF v_rule.leave_delta <> 0 THEN
    INSERT INTO public.day_off_ledger (user_id, ledger_type, change, source_record_id, note)
    VALUES (p_user_id, 'annual_leave', v_rule.leave_delta * v_multiplier, p_record_id, p_mode || ': ' || p_type_code || ' on ' || p_work_date::text);
  END IF;
END;
$$;

-- 3. Cập nhật rpc_get_so_du_by_user để tính Phép còn lại = Quỹ gốc + Biến động
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
  v_leave_base  numeric;
  v_leave_used  numeric;
BEGIN
  v_year := COALESCE(p_year, EXTRACT(YEAR FROM now())::int);

  -- Tính tổng nghỉ bù và nghỉ tuần (không phân biệt năm, cộng dồn)
  SELECT COALESCE(SUM(change), 0) INTO v_comp_off
  FROM public.day_off_ledger
  WHERE user_id = p_target_user_id AND ledger_type = 'comp_off';

  SELECT COALESCE(SUM(change), 0) INTO v_weekly_off
  FROM public.day_off_ledger
  WHERE user_id = p_target_user_id AND ledger_type = 'weekly_off';

  -- Lấy Quỹ gốc phép năm
  SELECT COALESCE(total_days, 12) INTO v_leave_base
  FROM public.leave_quota
  WHERE user_id = p_target_user_id AND year = v_year;

  -- Lấy tổng số phép đã sử dụng trong năm đó
  SELECT COALESCE(SUM(l.change), 0) INTO v_leave_used
  FROM public.day_off_ledger l
  JOIN public.attendance_records r ON r.id = l.source_record_id
  WHERE l.user_id = p_target_user_id 
    AND l.ledger_type = 'annual_leave'
    AND EXTRACT(YEAR FROM r.work_date) = v_year;

  RETURN jsonb_build_object(
    'comp_off',        v_comp_off,
    'weekly_off',      v_weekly_off,
    'leave_base',      v_leave_base,
    'leave_used',      ABS(v_leave_used),
    'leave_remaining', v_leave_base + v_leave_used -- v_leave_used là số âm nên cộng là đúng
  );
END;
$$;

-- Đồng bộ rpc_get_so_du (của user hiện tại)
CREATE OR REPLACE FUNCTION public.rpc_get_so_du(p_year int DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN public.rpc_get_so_du_by_user(auth.uid(), p_year);
END;
$$;

-- =============================================================
-- RPC: Lấy thông tin phép năm của tất cả nhân viên trong 1 năm
-- =============================================================
CREATE OR REPLACE FUNCTION public.rpc_get_all_leave_balances(p_year int)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(t))
  INTO v_result
  FROM (
    SELECT 
      u.id AS user_id,
      u.full_name,
      COALESCE(q.total_days, 12) AS leave_base,
      COALESCE(SUM(l.change), 0) AS leave_used_raw,
      ABS(COALESCE(SUM(l.change), 0)) AS leave_used,
      COALESCE(q.total_days, 12) + COALESCE(SUM(l.change), 0) AS leave_remaining
    FROM public.users u
    LEFT JOIN public.leave_quota q ON q.user_id = u.id AND q.year = p_year
    LEFT JOIN public.day_off_ledger l ON l.user_id = u.id AND l.ledger_type = 'annual_leave'
    LEFT JOIN public.attendance_records ar ON ar.id = l.source_record_id AND EXTRACT(YEAR FROM ar.work_date) = p_year
    WHERE u.role = 'staff' AND u.is_active = true
    GROUP BY u.id, u.full_name, q.total_days
    ORDER BY u.full_name
  ) t;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- 4. Chuyển đổi dữ liệu cũ & Reset Quỹ gốc về 12
-- Di chuyển các record nghỉ phép cũ vào day_off_ledger
INSERT INTO public.day_off_ledger (user_id, ledger_type, change, source_record_id, note)
SELECT 
  ar.user_id, 
  'annual_leave', 
  r.leave_delta, 
  ar.id, 
  'Migrated leave'
FROM public.attendance_records ar
JOIN public.attendance_types t ON ar.type_code = t.code
JOIN public.attendance_rules r ON r.type_group = t.type_group AND r.day_category = public.get_day_category(ar.work_date)
WHERE r.leave_delta <> 0 
  AND NOT EXISTS (
    SELECT 1 FROM public.day_off_ledger dl 
    WHERE dl.source_record_id = ar.id AND dl.ledger_type = 'annual_leave'
  );

-- Đặt lại toàn bộ leave_quota.total_days về 12 (để admin vào cấu hình lại cho đúng Quỹ gốc)
UPDATE public.leave_quota SET total_days = 12;
