-- =============================================================
-- 04_SEED_DEFAULT_DATA.SQL — Dữ liệu mặc định ban đầu
-- Chạy sau 03_rpcs.sql
-- =============================================================

-- =============================================================
-- Danh mục loại chấm công
-- =============================================================
INSERT INTO public.attendance_types (code, name, type_group, sort_order) VALUES
  ('HC',     'Hành chính (đi làm)',                        'HC',     1),
  ('NP',     'Nghỉ phép',                                   'NP',     2),
  ('OM',     'Ốm',                                          'OM',     3),
  ('HN_HC',  'Hội nghị / Học tập (tính hành chính)',        'HN_HC',  4),
  ('HN_KHC', 'Hội nghị / Học tập (không tính hành chính)', 'HN_KHC', 5),
  ('NT',     'Nghỉ tuần',                                   'NT',     6),
  ('TS',     'Thai sản',                                    'TS',     7),
  ('TR',     'Trực',                                        'DUTY',   8),
  ('TRV',    'Trực viện',                                   'DUTY',   9),
  ('TYT',    'Trực y tế',                                   'DUTY',  10),
  ('NB',     'Nghỉ bù',                                     'NB',    11),
  ('NL',     'Nghỉ lễ / Tết',                               'NL',    12)
ON CONFLICT (code) DO NOTHING;

-- =============================================================
-- Rule engine mặc định (theo đặc tả mục 5.3)
-- Admin có thể sửa qua giao diện sau khi setup xong
-- =============================================================
INSERT INTO public.attendance_rules
  (type_group, day_category, comp_off_delta, weekly_off_delta, leave_delta, counts_as_work_day, note)
VALUES
  -- Hành chính ngày thường → tính ngày công
  ('HC',      'weekday',  0,  0, 0, true,  'Hành chính ngày thường'),
  -- Hành chính cuối tuần → tính ngày công + +1 nghỉ tuần
  ('HC',      'weekend',  0,  1, 0, true,  'Hành chính cuối tuần — phát sinh nghỉ tuần'),
  -- Hành chính ngày lễ → tính ngày công + +1 nghỉ bù
  ('HC',      'holiday',  1,  0, 0, true,  'Hành chính ngày lễ — phát sinh nghỉ bù'),

  -- Hội nghị tính HC
  ('HN_HC',   'weekday',  0,  0, 0, true,  'HN/Học tập — tính HC'),
  ('HN_HC',   'weekend',  0,  1, 0, true,  'HN/Học tập cuối tuần — phát sinh nghỉ tuần'),
  ('HN_HC',   'holiday',  1,  0, 0, true,  'HN/Học tập ngày lễ — phát sinh nghỉ bù'),

  -- Hội nghị không tính HC
  ('HN_KHC',  'weekday',  0,  0, 0, false, 'HN/Học tập — không tính HC'),
  ('HN_KHC',  'weekend',  0,  0, 0, false, 'HN/Học tập cuối tuần — không phát sinh'),
  ('HN_KHC',  'holiday',  0,  0, 0, false, 'HN/Học tập ngày lễ — không phát sinh'),

  -- Trực (DUTY: TR, TRV, TYT) ngày thường → +1 nghỉ bù
  ('DUTY',    'weekday',  1,  0, 0, false, 'Trực ngày thường — +1 nghỉ bù'),
  -- Trực cuối tuần (T7/CN) → +1 nghỉ bù +1 nghỉ tuần (được nghỉ bù thêm vì trực ngày nghỉ tuần)
  ('DUTY',    'weekend',  1,  1, 0, false, 'Trực cuối tuần — +1 nghỉ bù +1 nghỉ tuần'),
  -- Trực ngày lễ/Tết → +2 nghỉ bù (mức thưởng cao hơn ngày thường/cuối tuần; Admin có thể điều chỉnh)
  ('DUTY',    'holiday',  2,  0, 0, false, 'Trực ngày lễ — +2 nghỉ bù (cao hơn ngày thường/cuối tuần)'),

  -- Nghỉ tuần ngày thường (dời nghỉ) → -1 nghỉ tuần
  ('NT',      'weekday', 0, -1, 0, false, 'Nghỉ tuần (dời sang ngày thường) — trừ 1 nghỉ tuần'),
  -- Nghỉ tuần đúng T7/CN → không phát sinh, không trừ (mặc định)
  ('NT',      'weekend',  0,  0, 0, false, 'Nghỉ tuần thông thường — không tính'),
  ('NT',      'holiday',  0,  0, 0, false, 'Nghỉ tuần ngày lễ — không tính'),

  -- Nghỉ bù → -1 nghỉ bù
  ('NB',      'weekday', -1,  0, 0, false, 'Nghỉ bù — trừ 1 nghỉ bù'),
  ('NB',      'weekend', -1,  0, 0, false, 'Nghỉ bù cuối tuần — trừ 1 nghỉ bù'),
  ('NB',      'holiday', -1,  0, 0, false, 'Nghỉ bù ngày lễ — trừ 1 nghỉ bù'),

  -- Nghỉ phép → -1 phép năm
  ('NP',      'weekday',  0,  0, -1, false, 'Nghỉ phép — trừ 1 phép năm'),
  ('NP',      'weekend',  0,  0, -1, false, 'Nghỉ phép cuối tuần — trừ 1 phép năm'),
  ('NP',      'holiday',  0,  0, -1, false, 'Nghỉ phép ngày lễ — trừ 1 phép năm'),

  -- Nghỉ lễ → không phát sinh gì
  ('NL',      'weekday',  0,  0, 0, false, 'Nghỉ lễ — không phát sinh'),
  ('NL',      'weekend',  0,  0, 0, false, 'Nghỉ lễ cuối tuần — không phát sinh'),
  ('NL',      'holiday',  0,  0, 0, false, 'Nghỉ lễ — không phát sinh'),

  -- Ốm, Thai sản → không phát sinh
  ('OM',      'weekday',  0,  0, 0, false, 'Ốm'),
  ('OM',      'weekend',  0,  0, 0, false, 'Ốm cuối tuần'),
  ('OM',      'holiday',  0,  0, 0, false, 'Ốm ngày lễ'),
  ('TS',      'weekday',  0,  0, 0, false, 'Thai sản'),
  ('TS',      'weekend',  0,  0, 0, false, 'Thai sản cuối tuần'),
  ('TS',      'holiday',  0,  0, 0, false, 'Thai sản ngày lễ')
ON CONFLICT (type_group, day_category) DO NOTHING;
