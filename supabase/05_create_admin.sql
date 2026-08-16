-- =============================================================
-- 05_CREATE_ADMIN.SQL — Tạo tài khoản Admin đầu tiên
-- Chạy sau 04_seed_default_data.sql
--
-- HƯỚNG DẪN:
-- 1. Truy cập Supabase Dashboard → Authentication → Users → "Add user"
--    Nhập email và password → nhấn "Create user"
--    Copy UUID của user vừa tạo (cột "UID")
--
-- 2. Thay YOUR_ADMIN_AUTH_UUID, YOUR_ADMIN_EMAIL, YOUR_ADMIN_NAME
--    bên dưới bằng thông tin thực tế rồi chạy script này
-- =============================================================

-- Bước 1: Xác nhận auth user đã tồn tại (chạy để kiểm tra)
-- SELECT id, email FROM auth.users WHERE email = 'YOUR_ADMIN_EMAIL';

-- Bước 2: Insert vào bảng public.users
INSERT INTO public.users (auth_id, full_name, email, role, position, is_active)
VALUES (
  '9c7bc112-1d08-450e-934a-32854d8009a0',   -- UUID lấy từ Authentication > Users
  'admin',        -- VD: 'Nguyễn Văn Admin'
  'quanlychamcong.admin@gmail.com',       -- VD: 'admin@congty.vn'
  'admin',
  'Quản trị viên',
  true
)
ON CONFLICT (auth_id) DO UPDATE
  SET role = 'admin', is_active = true;

-- Bước 3: Kiểm tra kết quả
SELECT id, full_name, email, role, is_active
FROM public.users
WHERE role = 'admin';
