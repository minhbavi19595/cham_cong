CREATE OR REPLACE FUNCTION public.apply_rule_for_record(
  p_record_id   uuid,
  p_user_id     uuid,
  p_type_code   text,
  p_work_date   date,
  p_mode        text   -- 'apply' hoặc 'revert'
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_type_group        text;
  v_day_category      text;
  v_rule              public.attendance_rules%ROWTYPE;
  v_multiplier        numeric := 1;
BEGIN
  -- Nếu user không còn tồn tại (do xóa user gây ra cascade delete), 
  -- thì không cố gắng ghi đè/hoàn tác vào ledger nữa để tránh lỗi Foreign Key
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RETURN;
  END IF;

  IF p_mode = 'revert' THEN
    v_multiplier := -1;
  END IF;

  -- Lấy type_group từ attendance_types
  SELECT type_group INTO v_type_group
  FROM public.attendance_types
  WHERE code = p_type_code;

  IF v_type_group IS NULL THEN RETURN; END IF;

  -- Xác định loại ngày
  v_day_category := public.get_day_category(p_work_date);

  -- Tìm rule tương ứng
  SELECT * INTO v_rule
  FROM public.attendance_rules
  WHERE type_group = v_type_group
    AND day_category = v_day_category;

  IF NOT FOUND THEN RETURN; END IF;

  -- Ghi vào ledger: nghỉ bù
  IF v_rule.comp_off_delta <> 0 THEN
    INSERT INTO public.day_off_ledger
      (user_id, ledger_type, change, source_record_id, note)
    VALUES (
      p_user_id,
      'comp_off',
      v_rule.comp_off_delta * v_multiplier,
      p_record_id,
      p_mode || ': ' || p_type_code || ' on ' || p_work_date::text
    );
  END IF;

  -- Ghi vào ledger: nghỉ tuần
  IF v_rule.weekly_off_delta <> 0 THEN
    INSERT INTO public.day_off_ledger
      (user_id, ledger_type, change, source_record_id, note)
    VALUES (
      p_user_id,
      'weekly_off',
      v_rule.weekly_off_delta * v_multiplier,
      p_record_id,
      p_mode || ': ' || p_type_code || ' on ' || p_work_date::text
    );
  END IF;

  -- Điều chỉnh leave_quota nếu có
  IF v_rule.leave_delta <> 0 THEN
    UPDATE public.leave_quota
    SET total_days = total_days + (v_rule.leave_delta * v_multiplier)
    WHERE user_id = p_user_id
      AND year = EXTRACT(YEAR FROM p_work_date)::int;
  END IF;
END;
$$;
