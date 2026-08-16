-- =============================================================
-- 09_CLEANUP_HOLIDAY_RULES.SQL
-- Xoá bỏ hoàn toàn khái niệm "Ngày lễ" (holiday) ra khỏi bộ quy tắc ngày
-- =============================================================

-- Xoá mọi quy tắc liên quan đến ngày lễ tự động (vì nhân viên sẽ tự bấm chọn)
DELETE FROM public.attendance_rules 
WHERE day_category = 'holiday';

-- Đảm bảo mã TR_NL (Trực Lễ/Tết) có đủ luật cho ngày thường và cuối tuần (nếu lỡ mất)
-- TR_NL được nghỉ bù 2 ngày (không cộng nghỉ tuần)
INSERT INTO public.attendance_rules (type_group, day_category, comp_off_delta, weekly_off_delta, leave_delta, counts_as_work_day)
VALUES 
  ('Trực ngày lễ', 'weekday', 2, 0, 0, false),
  ('Trực ngày lễ', 'weekend', 2, 0, 0, false)
ON CONFLICT (type_group, day_category) 
DO UPDATE SET 
  comp_off_delta = EXCLUDED.comp_off_delta,
  weekly_off_delta = EXCLUDED.weekly_off_delta,
  counts_as_work_day = EXCLUDED.counts_as_work_day;

-- Đảm bảo mã NL (Nghỉ Lễ/Tết) có đủ luật
-- Nghỉ lễ mặc định là có tính ngày công hưởng lương (vì nhà nước cho nghỉ có lương)
INSERT INTO public.attendance_rules (type_group, day_category, comp_off_delta, weekly_off_delta, leave_delta, counts_as_work_day)
VALUES 
  ('Nghỉ lễ', 'weekday', 0, 0, 0, true),
  ('Nghỉ lễ', 'weekend', 0, 0, 0, true)
ON CONFLICT (type_group, day_category) 
DO UPDATE SET 
  counts_as_work_day = EXCLUDED.counts_as_work_day;
