import { NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

// Khởi tạo Supabase client với SERVICE_ROLE_KEY (Chỉ dùng trên server)
const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
  { auth: { autoRefreshToken: false, persistSession: false } }
);

export async function POST(req: Request) {
  try {
    const { action, payload } = await req.json();

    if (action === 'create_user') {
      const { email, password, full_name, role, position } = payload;

      // 1. Tạo Auth User bằng Admin API (bỏ qua email confirm, không đổi session)
      const { data: authData, error: authErr } = await supabaseAdmin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      });

      if (authErr) throw authErr;

      // 2. Insert vào bảng public.users
      const { error: insertErr } = await supabaseAdmin.from('users').insert({
        auth_id: authData.user.id,
        full_name,
        email,
        role,
        position: position || null,
        is_active: true
      });

      if (insertErr) {
        // Rollback nếu lỗi
        await supabaseAdmin.auth.admin.deleteUser(authData.user.id);
        throw insertErr;
      }

      return NextResponse.json({ success: true, user: authData.user });
    }

    if (action === 'update_password') {
      const { uid, password } = payload;
      const { error } = await supabaseAdmin.auth.admin.updateUserById(uid, { password });
      if (error) throw error;
      return NextResponse.json({ success: true });
    }

    return NextResponse.json({ error: 'Invalid action' }, { status: 400 });

  } catch (error: any) {
    console.error('Admin API Error:', error);
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
