-- =============================================================
-- 07_TEAM_MANAGEMENT.SQL — Cập nhật cấu trúc Tổ / Nhóm
-- =============================================================

-- 1. Bổ sung cột manager_id vào users để biết nhân viên ảo thuộc về ai
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS manager_id uuid REFERENCES public.users(id) ON DELETE CASCADE;

-- 2. Cho phép email trống đối với nhân viên ảo
ALTER TABLE public.users ALTER COLUMN email DROP NOT NULL;
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_email_key;

-- 3. Hàm tạo nhân viên ảo (Chỉ dành cho Staff tạo lính của mình)
CREATE OR REPLACE FUNCTION public.rpc_add_team_member(
  p_full_name text,
  p_position text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_current_user uuid;
  v_role text;
BEGIN
  SELECT id, role INTO v_current_user, v_role FROM public.users WHERE auth_id = auth.uid();
  IF v_current_user IS NULL OR v_role <> 'staff' THEN 
    RETURN jsonb_build_object('error', 'Chỉ chuyên viên mới có thể tạo nhân viên'); 
  END IF;

  INSERT INTO public.users (full_name, position, role, manager_id, email)
  VALUES (p_full_name, p_position, 'staff', v_current_user, NULL);

  RETURN jsonb_build_object('success', true);
END;
$$;

-- 4. Hàm xoá nhân viên ảo
CREATE OR REPLACE FUNCTION public.rpc_remove_team_member(
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_current_user uuid;
BEGIN
  SELECT id INTO v_current_user FROM public.users WHERE auth_id = auth.uid();
  
  -- Chỉ được xoá nếu nhân viên đó có manager_id là chính mình
  DELETE FROM public.users WHERE id = p_user_id AND manager_id = v_current_user;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- 5. Lấy danh sách các tài khoản Chuyên viên (dành cho Admin chọn)
CREATE OR REPLACE FUNCTION public.rpc_get_staff_accounts()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(t))
  INTO v_result
  FROM (
    SELECT id, full_name, email, position
    FROM public.users
    WHERE role = 'staff' AND manager_id IS NULL AND is_active = true
    ORDER BY full_name
  ) t;
  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- 6. Cập nhật rpc_get_bang_cham_cong hỗ trợ lọc theo manager_id
DROP FUNCTION IF EXISTS public.rpc_get_bang_cham_cong(integer, integer, uuid);

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
  
  -- Xác định manager_id cần xem:
  IF v_role = 'staff' THEN
    v_target_manager := v_current_user; -- Staff luôn chỉ xem của mình
  ELSE
    v_target_manager := COALESCE(p_manager_id, v_current_user); -- Admin xem theo lựa chọn, nếu null xem của mình (mặc dù admin thường ko có bảng)
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

-- 7. Cập nhật rpc_get_tong_hop_thang để tính toán chỉ trong phạm vi của v_target_manager
DROP FUNCTION IF EXISTS public.rpc_get_tong_hop_thang(integer, integer, uuid);

CREATE OR REPLACE FUNCTION public.rpc_get_tong_hop_thang(
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

  SELECT json_object_agg(key, val)::jsonb INTO v_result
  FROM (
    SELECT type_code AS key, count(*)::int AS val
    FROM public.attendance_records ar
    JOIN public.users u ON u.id = ar.user_id
    WHERE EXTRACT(MONTH FROM ar.work_date) = p_month
      AND EXTRACT(YEAR  FROM ar.work_date) = p_year
      AND (u.manager_id = v_target_manager OR u.id = v_target_manager)
    GROUP BY type_code
    UNION ALL
    SELECT 'work_days' AS key, count(*)::int AS val
    FROM public.attendance_records ar
    JOIN public.users u ON u.id = ar.user_id
    JOIN public.attendance_types t ON t.code = ar.type_code
    WHERE EXTRACT(MONTH FROM ar.work_date) = p_month
      AND EXTRACT(YEAR  FROM ar.work_date) = p_year
      AND (u.manager_id = v_target_manager OR u.id = v_target_manager)
      AND t.counts_as_work_day = true
  ) t;
  
  RETURN COALESCE(v_result, '{}'::jsonb);
END;
$$;

-- 8. Hàm rpc_get_team_members dùng cho grid để lấy danh sách user cần vẽ (Manager + các thành viên)
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
    ORDER BY CASE WHEN id = v_target_manager THEN 0 ELSE 1 END, full_name
  ) t;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;
