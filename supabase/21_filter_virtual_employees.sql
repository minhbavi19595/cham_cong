-- =============================================================
-- 21_FILTER_VIRTUAL_EMPLOYEES.SQL
-- Lọc danh sách nhân viên ảo ra khỏi danh sách quản lý tài khoản
-- =============================================================

CREATE OR REPLACE FUNCTION public.rpc_get_all_staff()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_result  jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(t))
  INTO v_result
  FROM (
    SELECT id, full_name, email, role, position, is_active, created_at
    FROM public.users
    WHERE manager_id IS NULL -- Chỉ lấy tài khoản thật, bỏ qua nhân viên ảo do staff tạo
    ORDER BY full_name
  ) t;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;
