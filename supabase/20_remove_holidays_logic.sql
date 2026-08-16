-- =============================================================
-- 20_REMOVE_HOLIDAYS_LOGIC.SQL
-- Lược bỏ logic check ngày lễ trong get_day_category 
-- (vì người dùng chỉ cần chấm mã công Lễ là đủ)
-- =============================================================

CREATE OR REPLACE FUNCTION public.get_day_category(p_date date)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
STABLE
AS $$
BEGIN
  -- Cuối tuần (dow: 0=CN, 6=T7)
  IF EXTRACT(DOW FROM p_date) IN (0, 6) THEN
    RETURN 'weekend';
  END IF;

  RETURN 'weekday';
END;
$$;

-- Xóa bảng holidays vì không còn sử dụng nữa (nếu có tồn tại)
DROP TABLE IF EXISTS public.holidays CASCADE;
