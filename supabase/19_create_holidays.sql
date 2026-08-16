-- =============================================================
-- 19_CREATE_HOLIDAYS_TABLE.SQL
-- Tạo bảng holidays nếu chưa tồn tại
-- =============================================================

CREATE TABLE IF NOT EXISTS public.holidays (
  holiday_date  date PRIMARY KEY,
  name          text NOT NULL,
  created_by    uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.holidays ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Cho phép tất cả đọc holidays" ON public.holidays;
CREATE POLICY "Cho phép tất cả đọc holidays" 
ON public.holidays FOR SELECT 
TO authenticated 
USING (true);

DROP POLICY IF EXISTS "Chỉ admin được sửa holidays" ON public.holidays;
CREATE POLICY "Chỉ admin được sửa holidays" 
ON public.holidays FOR ALL 
TO authenticated 
USING (
  EXISTS (
    SELECT 1 FROM public.users 
    WHERE users.auth_id = auth.uid() AND users.role = 'admin'
  )
);
