-- =============================================================
-- 11_SEED_TEST_DATA.SQL
-- Sinh dữ liệu mẫu tự động để kiểm thử bộ máy tính toán (Rule Engine)
-- =============================================================

DO $$
DECLARE
  v_admin_id uuid;
  v_staff_id uuid;
  v_user1_id uuid;
  v_user2_id uuid;
  v_month int := EXTRACT(MONTH FROM NOW())::int;
  v_year int := EXTRACT(YEAR FROM NOW())::int;
  v_date_weekday date;
  v_date_weekend date;
BEGIN
  -- 1. Tìm 1 người dùng đang có auth_id (ưu tiên Admin) để gán quyền created_by
  SELECT id INTO v_admin_id FROM public.users WHERE auth_id IS NOT NULL LIMIT 1;
  IF v_admin_id IS NULL THEN
    RAISE NOTICE 'Không tìm thấy tài khoản người dùng thực nào để gán dữ liệu.';
    RETURN;
  END IF;

  -- 2. Dọn dẹp dữ liệu mẫu cũ (nếu có) để tránh lỗi trùng lặp
  DELETE FROM public.users WHERE full_name IN ('Chuyên viên Test', 'Nhân viên Test 1', 'Nhân viên Test 2');

  -- 3. Tạo 1 tài khoản Chuyên viên mẫu (để hiển thị trong Dropdown của Admin)
  INSERT INTO public.users (full_name, position, role)
  VALUES ('Chuyên viên Test', 'Trưởng tổ', 'staff')
  RETURNING id INTO v_staff_id;

  -- 3. Tạo 2 nhân viên ảo mẫu, chịu sự quản lý của Chuyên viên Test
  INSERT INTO public.users (full_name, position, role, manager_id)
  VALUES ('Nhân viên Test 1', 'Kế toán', 'staff', v_staff_id)
  RETURNING id INTO v_user1_id;

  INSERT INTO public.users (full_name, position, role, manager_id)
  VALUES ('Nhân viên Test 2', 'Bảo vệ', 'staff', v_staff_id)
  RETURNING id INTO v_user2_id;

  -- 4. Setup Quỹ phép gốc cho 2 nhân viên này
  INSERT INTO public.leave_quota (user_id, year, total_days) 
  VALUES 
    (v_user1_id, v_year, 12), -- Quỹ 12 ngày
    (v_user2_id, v_year, 15)  -- Quỹ 15 ngày
  ON CONFLICT (user_id, year) DO UPDATE SET total_days = EXCLUDED.total_days;

  -- 5. Tìm ngày an toàn trong tháng hiện tại để chấm công
  -- Tìm Thứ Hai đầu tiên của tháng
  v_date_weekday := date_trunc('month', NOW())::date;
  WHILE EXTRACT(DOW FROM v_date_weekday) IN (0, 6) LOOP
    v_date_weekday := v_date_weekday + interval '1 day';
  END LOOP;

  -- Tìm Thứ Bảy đầu tiên của tháng
  v_date_weekend := date_trunc('month', NOW())::date;
  WHILE EXTRACT(DOW FROM v_date_weekend) <> 6 LOOP
    v_date_weekend := v_date_weekend + interval '1 day';
  END LOOP;

  -- 6. Insert dữ liệu chấm công để kích hoạt Triggers
  
  ---------------------------------------------------------
  -- NHÂN VIÊN TEST 1
  ---------------------------------------------------------
  -- a) Thứ Hai: Đi làm Hành chính (HC) -> Tính 1 ngày công
  INSERT INTO public.attendance_records (user_id, work_date, type_code, created_by)
  VALUES (v_user1_id, v_date_weekday, 'HC', v_admin_id);

  -- b) Thứ Ba: Trực thường (TR) -> Cộng 1 nghỉ bù
  INSERT INTO public.attendance_records (user_id, work_date, type_code, created_by)
  VALUES (v_user1_id, v_date_weekday + interval '1 day', 'TR', v_admin_id);

  -- c) Thứ Bảy: Trực cuối tuần (TR) -> Cộng 1 nghỉ bù + 1 nghỉ tuần
  INSERT INTO public.attendance_records (user_id, work_date, type_code, created_by)
  VALUES (v_user1_id, v_date_weekend, 'TR', v_admin_id);

  -- d) Thứ Tư: Nghỉ phép (NP) -> Trừ 1 phép năm
  INSERT INTO public.attendance_records (user_id, work_date, type_code, created_by)
  VALUES (v_user1_id, v_date_weekday + interval '2 days', 'NP', v_admin_id);


  ---------------------------------------------------------
  -- NHÂN VIÊN TEST 2
  ---------------------------------------------------------
  -- a) Thứ Năm: Trực Lễ (TR_NL) -> Cộng 2 nghỉ bù (luật riêng)
  INSERT INTO public.attendance_records (user_id, work_date, type_code, created_by)
  VALUES (v_user2_id, v_date_weekday + interval '3 days', 'TR_NL', v_admin_id);

  -- b) Chủ Nhật: Nghỉ phép cuối tuần (NP) -> Trừ 1 phép năm
  INSERT INTO public.attendance_records (user_id, work_date, type_code, created_by)
  VALUES (v_user2_id, v_date_weekend + interval '1 day', 'NP', v_admin_id);

END;
$$;
