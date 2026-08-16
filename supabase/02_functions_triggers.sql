-- =============================================================
-- 02_FUNCTIONS_TRIGGERS.SQL — Rule Engine Logic
-- Chạy sau 01_rls.sql
-- =============================================================

-- =============================================================
-- FUNCTION: get_day_category
-- Trả về day_category để tra rule engine:
--   'holiday'  — ngày nằm trong bảng holidays (ngày lễ/Tết)
--   'weekend'  — T7 hoặc CN (và không phải ngày lễ)
--   'weekday'  — T2–T6 bình thường
--
-- Lưu ý: holiday là category độc lập với weekend.
-- Một ngày lễ rơi vào T7/CN sẽ là 'holiday', không phải 'weekend'.
-- Admin có thể set rule riêng cho holiday vs weekend trong bảng attendance_rules.
-- Nếu muốn ngày lễ trùng T7/CN dùng rule weekend → xoá dòng holiday đó khỏi bảng holidays.
-- =============================================================
CREATE OR REPLACE FUNCTION public.get_day_category(p_date date)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
STABLE
AS $$
BEGIN
  -- (Đã lược bỏ logic holiday theo yêu cầu: người dùng chấm công trực tiếp bằng mã công Lễ)

  -- Cuối tuần (dow: 0=CN, 6=T7)
  IF EXTRACT(DOW FROM p_date) IN (0, 6) THEN
    RETURN 'weekend';
  END IF;

  RETURN 'weekday';
END;
$$;

-- =============================================================
-- FUNCTION: apply_rule_for_record
-- Áp dụng hoặc revert delta vào day_off_ledger và leave_quota
-- mode: 'apply' | 'revert'
-- Dùng SECURITY DEFINER để bypass RLS khi ghi ledger
-- =============================================================
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

-- =============================================================
-- TRIGGER FUNCTION: trg_attendance_record_change
-- Tự động revert rule cũ rồi apply rule mới mỗi khi INSERT/UPDATE/DELETE
-- =============================================================
CREATE OR REPLACE FUNCTION public.trg_attendance_record_change()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  -- DELETE: revert toàn bộ delta của bản ghi cũ
  IF TG_OP = 'DELETE' THEN
    -- Xoá hết các ledger entry liên quan
    DELETE FROM public.day_off_ledger WHERE source_record_id = OLD.id;
    -- Re-apply reverse để hoàn tác ảnh hưởng leave_quota
    PERFORM public.apply_rule_for_record(
      OLD.id, OLD.user_id, OLD.type_code, OLD.work_date, 'revert'
    );
    RETURN OLD;
  END IF;

  -- UPDATE: revert record cũ, apply record mới
  IF TG_OP = 'UPDATE' THEN
    -- Xoá ledger entries của record cũ
    DELETE FROM public.day_off_ledger WHERE source_record_id = OLD.id;
    -- Revert leave_quota ảnh hưởng cũ
    PERFORM public.apply_rule_for_record(
      OLD.id, OLD.user_id, OLD.type_code, OLD.work_date, 'revert'
    );
    -- Apply rule mới
    PERFORM public.apply_rule_for_record(
      NEW.id, NEW.user_id, NEW.type_code, NEW.work_date, 'apply'
    );
    RETURN NEW;
  END IF;

  -- INSERT: apply rule
  IF TG_OP = 'INSERT' THEN
    PERFORM public.apply_rule_for_record(
      NEW.id, NEW.user_id, NEW.type_code, NEW.work_date, 'apply'
    );
    RETURN NEW;
  END IF;

  RETURN NULL;
END;
$$;

-- Gắn trigger vào attendance_records
DROP TRIGGER IF EXISTS trg_attendance_rule_engine ON public.attendance_records;
CREATE TRIGGER trg_attendance_rule_engine
  AFTER INSERT OR UPDATE OF type_code OR DELETE
  ON public.attendance_records
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_attendance_record_change();
