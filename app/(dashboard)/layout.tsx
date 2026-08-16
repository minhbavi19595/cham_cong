import { createClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import Sidebar from '@/components/Sidebar';
import { AppUser } from '@/types';

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const { data: { user: authUser } } = await supabase.auth.getUser();

  if (!authUser) redirect('/login');

  const { data: appUser } = await supabase
    .from('users')
    .select('*')
    .eq('auth_id', authUser.id)
    .single();

  if (!appUser) {
    return (
      <div className="flex flex-col items-center justify-center h-screen" style={{ background: '#0f172a', color: '#f1f5f9' }}>
        <h2 className="text-xl font-bold mb-2 text-red-400">Lỗi xác thực</h2>
        <p className="mb-4 text-slate-400">Tài khoản của bạn chưa được cấp quyền truy cập hoặc đã bị xoá.</p>
        <p className="mb-6 text-sm text-slate-500">Vui lòng liên hệ Quản trị viên để biết thêm chi tiết.</p>
        <form action="/auth/signout" method="POST">
          <button type="submit" className="btn btn-primary bg-red-600 hover:bg-red-700 border-red-600">Đăng xuất</button>
        </form>
      </div>
    );
  }

  return (
    <div className="flex h-dvh overflow-hidden">
      <Sidebar user={appUser as AppUser} />
      <main className="flex-1 overflow-y-auto" style={{ background: '#0f172a' }}>
        {children}
      </main>
    </div>
  );
}
