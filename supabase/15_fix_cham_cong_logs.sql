-- =============================================================
-- 15_FIX_CHAM_CONG_LOGS.SQL
-- Sửa lỗi không ghi được Giải trình khi chấm công mới (INSERT)
-- do thiếu RETURNING id.
-- =============================================================

CREATE OR REPLACE FUNCTION public.rpc_cham_cong(
  p_user_id   uuid,
  p_work_date date,
  p_type_code varchar,
  p_reason    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_current_user  uuid;
  v_role          text;
  v_is_open_day   boolean;
  v_is_past       boolean;
  v_existing_id   uuid;
  v_old_type      text;
  v_manager_id    uuid;
BEGIN
  -- 1. Lấy thông tin user đang thao tác
  SELECT id, role INTO v_current_user, v_role FROM public.users WHERE auth_id = auth.uid();
  IF v_current_user IS NULL THEN
    RETURN jsonb_build_object('error', 'Không xác định được tài khoản');
  END IF;

  -- 2. Quyền: Admin, Tổ trưởng chấm cho thành viên, hoặc tự chấm cho mình
  IF v_role <> 'admin' AND p_user_id <> v_current_user THEN
    SELECT manager_id INTO v_manager_id FROM public.users WHERE id = p_user_id;
    IF v_manager_id IS DISTINCT FROM v_current_user THEN
      RETURN jsonb_build_object('error', 'Bạn không có quyền chấm công cho nhân viên này');
    END IF;
  END IF;

  -- 3. Kiểm tra ngày hợp lệ (đã mở hoặc đã qua)
  v_is_open_day := EXISTS (SELECT 1 FROM public.attendance_open_days WHERE work_date = p_work_date);
  v_is_past := p_work_date < (NOW() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date;
  
  IF NOT v_is_open_day AND NOT v_is_past THEN
    RETURN jsonb_build_object('error', 'Ngày này chưa được mở chấm công');
  END IF;

  IF v_is_past AND (p_reason IS NULL OR trim(p_reason) = '') THEN
    RETURN jsonb_build_object('error', 'Ngày đã qua nửa đêm — bắt buộc nhập lý do giải trình');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.attendance_types WHERE code = p_type_code AND is_active = true) THEN
    RETURN jsonb_build_object('error', 'Loại công không hợp lệ');
  END IF;

  -- 4. Tìm record cũ (nếu có)
  SELECT id, type_code INTO v_existing_id, v_old_type
  FROM public.attendance_records
  WHERE user_id = p_user_id AND work_date = p_work_date;

  -- 5. Thực hiện Lưu
  IF v_existing_id IS NULL THEN
    INSERT INTO public.attendance_records (user_id, work_date, type_code, created_by)
    VALUES (p_user_id, p_work_date, p_type_code, v_current_user)
    RETURNING id INTO v_existing_id; -- QUAN TRỌNG: Phải lấy được ID vừa tạo ra!
  ELSE
    UPDATE public.attendance_records
    SET type_code = p_type_code, updated_by = v_current_user, updated_at = now()
    WHERE id = v_existing_id;
  END IF;

  -- 6. Ghi log giải trình nếu có nhập lý do
  IF p_reason IS NOT NULL AND p_reason <> '' THEN
    INSERT INTO public.attendance_edit_logs (record_id, old_type_code, new_type_code, reason, edited_by)
    VALUES (v_existing_id, v_old_type, p_type_code, p_reason, v_current_user);
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;
