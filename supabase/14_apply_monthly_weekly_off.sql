-- =============================================================
-- 14_APPLY_MONTHLY_WEEKLY_OFF.SQL
-- Áp dụng cơ chế Quỹ Nghỉ Tuần theo tháng (Reset theo tháng)
-- Quỹ = Tổng số ngày T7, CN trong tháng + Biến động Sổ cái
-- =============================================================

-- 1. Hàm đếm số ngày T7, CN trong 1 tháng bất kỳ
CREATE OR REPLACE FUNCTION public.get_weekends_in_month(p_month int, p_year int)
RETURNS int
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v_start_date date;
  v_end_date date;
  v_count int := 0;
  v_curr_date date;
BEGIN
  -- Nếu tháng/năm không hợp lệ, trả về 0
  IF p_month < 1 OR p_month > 12 THEN RETURN 0; END IF;
  
  v_start_date := make_date(p_year, p_month, 1);
  v_end_date := v_start_date + interval '1 month' - interval '1 day';
  v_curr_date := v_start_date;
  
  WHILE v_curr_date <= v_end_date LOOP
    IF EXTRACT(DOW FROM v_curr_date) IN (0, 6) THEN
      v_count := v_count + 1;
    END IF;
    v_curr_date := v_curr_date + interval '1 day';
  END LOOP;
  
  RETURN v_count;
END;
$$;

-- 2. Cập nhật rpc_get_tong_hop_thang để sử dụng Quỹ Nghỉ Tuần theo tháng
CREATE OR REPLACE FUNCTION public.rpc_get_tong_hop_thang(
  p_month int, 
  p_year int,
  p_manager_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_current_user_id   uuid;
  v_role              text;
  v_target_manager    uuid;
  v_result            jsonb;
  v_weekend_count     int;
BEGIN
  SELECT id, role INTO v_current_user_id, v_role
  FROM public.users WHERE auth_id = auth.uid();

  IF v_role = 'admin' THEN
    v_target_manager := COALESCE(p_manager_id, v_current_user_id);
  ELSE
    v_target_manager := v_current_user_id;
  END IF;

  -- Lấy số ngày cuối tuần mặc định của tháng
  v_weekend_count := public.get_weekends_in_month(p_month, p_year);

  SELECT jsonb_agg(row_to_json(t))
  INTO v_result
  FROM (
    SELECT
      u.id AS user_id,
      u.full_name,
      u.position,
      (
        SELECT COUNT(*)
        FROM public.attendance_records ar
        JOIN public.attendance_types at ON at.code = ar.type_code
        JOIN public.attendance_rules ru ON ru.type_group = at.type_group
           AND ru.day_category = public.get_day_category(ar.work_date)
        WHERE ar.user_id = u.id
          AND EXTRACT(MONTH FROM ar.work_date) = p_month
          AND EXTRACT(YEAR  FROM ar.work_date) = p_year
          AND ru.counts_as_work_day = true
      ) AS work_days,
      (
        SELECT COALESCE(SUM(l.change), 0)
        FROM public.day_off_ledger l
        WHERE l.user_id = u.id AND l.ledger_type = 'comp_off'
      ) AS comp_off_balance,
      (
        -- SỐ DƯ NGHỈ TUẦN THEO THÁNG:
        -- Quỹ mặc định (T7, CN) + Biến động trong Sổ cái CỦA THÁNG ĐÓ
        v_weekend_count + 
        COALESCE((
          SELECT SUM(l.change)
          FROM public.day_off_ledger l
          JOIN public.attendance_records ar ON ar.id = l.source_record_id
          WHERE l.user_id = u.id 
            AND l.ledger_type = 'weekly_off'
            AND EXTRACT(MONTH FROM ar.work_date) = p_month
            AND EXTRACT(YEAR FROM ar.work_date) = p_year
        ), 0)
      ) AS weekly_off_balance,
      (
        SELECT COALESCE((SELECT total_days FROM public.leave_quota WHERE user_id = u.id AND year = p_year), 12) +
               COALESCE((SELECT SUM(change) FROM public.day_off_ledger WHERE user_id = u.id AND ledger_type = 'annual_leave'), 0)
      ) AS leave_remaining
    FROM public.users u
    WHERE (u.manager_id = v_target_manager OR u.id = v_target_manager)
      AND u.is_active = true
    ORDER BY u.full_name
  ) t;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- 3. Chuẩn hoá lại Rule Engine để tránh lỗi "Tính kép" (Double Counting)
-- Khi Quỹ mặc định là số ngày T7, CN thì:
-- + Mã 'Nghỉ tuần' LUÔN LUÔN trừ 1 vào Sổ cái (dù là ngày thường hay cuối tuần).
-- + Mã 'Trực' (DUTY) vào cuối tuần KHÔNG CỘNG THÊM Nghỉ tuần nữa (vì bản chất họ không xài mã NT thì tự nhiên họ đã dư 1 ngày trong Quỹ rồi).

UPDATE public.attendance_rules 
SET weekly_off_delta = -1
WHERE type_group = 'Nghỉ tuần';

UPDATE public.attendance_rules
SET weekly_off_delta = 0
WHERE type_group != 'Nghỉ tuần';

-- 4. Tính toán lại Sổ cái cho Nghỉ tuần (Xóa cũ tạo lại)
DELETE FROM public.day_off_ledger WHERE ledger_type = 'weekly_off';

INSERT INTO public.day_off_ledger (user_id, ledger_type, change, source_record_id, note)
SELECT 
  ar.user_id, 
  'weekly_off', 
  ru.weekly_off_delta, 
  ar.id, 
  'recalc: ' || ar.type_code || ' on ' || ar.work_date
FROM public.attendance_records ar
JOIN public.attendance_types at ON at.code = ar.type_code
JOIN public.attendance_rules ru ON ru.type_group = at.type_group
   AND ru.day_category = public.get_day_category(ar.work_date)
WHERE ru.weekly_off_delta <> 0;
