-- =============================================================
-- 08_RENAME_GROUPS.SQL — Đổi tên các nhóm chấm công cho rõ ràng
-- =============================================================

-- Cập nhật tên nhóm trong bảng attendance_types
UPDATE public.attendance_types 
SET type_group = 'Hội nghị (Tính HC)' 
WHERE code = 'HN_HC';

UPDATE public.attendance_types 
SET type_group = 'Hội nghị (Không tính HC)' 
WHERE code = 'HN_KHC';

-- Cập nhật tên loại công cho dễ hiểu hơn
UPDATE public.attendance_types 
SET name = 'Hội nghị / Học tập (Tính công Hành chính)' 
WHERE code = 'HN_HC';

UPDATE public.attendance_types 
SET name = 'Hội nghị / Học tập (Không tính công Hành chính)' 
WHERE code = 'HN_KHC';

-- Cập nhật tên nhóm trong bảng attendance_rules (để rule engine hoạt động đúng)
UPDATE public.attendance_rules 
SET type_group = 'Hội nghị (Tính HC)' 
WHERE type_group = 'HN_HC' OR type_group = 'Nửa ngày / Trễ'; -- Fix lại lỗi đặt tên nhầm ở file 06

UPDATE public.attendance_rules 
SET type_group = 'Hội nghị (Không tính HC)' 
WHERE type_group = 'HN_KHC';

-- Cập nhật lại các nhóm viết tắt còn lại nếu có
UPDATE public.attendance_types SET type_group = 'Nghỉ tuần' WHERE type_group = 'NT';
UPDATE public.attendance_rules SET type_group = 'Nghỉ tuần' WHERE type_group = 'NT';

UPDATE public.attendance_types SET type_group = 'Thai sản' WHERE type_group = 'TS';
UPDATE public.attendance_rules SET type_group = 'Thai sản' WHERE type_group = 'TS';

UPDATE public.attendance_types SET type_group = 'Nghỉ bù' WHERE type_group = 'NB';
UPDATE public.attendance_rules SET type_group = 'Nghỉ bù' WHERE type_group = 'NB';

UPDATE public.attendance_types SET type_group = 'Nghỉ lễ' WHERE type_group = 'NL';
UPDATE public.attendance_rules SET type_group = 'Nghỉ lễ' WHERE type_group = 'NL';
