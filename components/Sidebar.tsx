'use client';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import { AppUser } from '@/types';
import toast from 'react-hot-toast';
import {
  LayoutGrid, Calendar, Users, Umbrella,
  Settings, FolderOpen, MessageSquare, LogOut,
  Clock, ChevronRight, Shield
} from 'lucide-react';

interface SidebarProps {
  user: AppUser;
}

const staffNav = [
  { href: '/bang-cham-cong', label: 'Bảng chấm công', icon: LayoutGrid },
];

const adminNav = [
  { href: '/bang-cham-cong', label: 'Bảng chấm công', icon: LayoutGrid },
  { label: 'QUẢN TRỊ', isHeader: true },
  { href: '/admin/nhan-vien',  label: 'Nhân viên',       icon: Users },
  { href: '/admin/phep-nam',   label: 'Quỹ phép năm',    icon: Calendar },
  { href: '/admin/quy-tac',    label: 'Quy tắc chấm công', icon: Settings },
  { href: '/admin/giai-trinh', label: 'Giải trình',       icon: MessageSquare },
];

export default function Sidebar({ user }: SidebarProps) {
  const pathname = usePathname();
  const router = useRouter();
  const supabase = createClient();

  async function handleLogout() {
    await supabase.auth.signOut();
    toast.success('Đã đăng xuất');
    router.push('/login');
    router.refresh();
  }

  const navItems = user.role === 'admin' ? adminNav : staffNav;

  return (
    <aside
      className="flex flex-col h-full"
      style={{
        width: 240,
        minWidth: 240,
        background: 'rgba(15,23,42,0.95)',
        borderRight: '1px solid rgba(51,65,85,0.5)',
        backdropFilter: 'blur(16px)',
      }}
    >
      {/* Logo */}
      <div className="flex items-center gap-3 px-4 py-5" style={{ borderBottom: '1px solid rgba(51,65,85,0.4)' }}>
        <div className="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0"
          style={{ background: 'linear-gradient(135deg, #3b82f6, #6366f1)' }}>
          <Clock size={18} className="text-white" />
        </div>
        <div>
          <div className="font-bold text-sm" style={{ color: '#f1f5f9' }}>Chấm Công</div>
          <div className="text-xs" style={{ color: '#475569' }}>Nội bộ</div>
        </div>
      </div>

      {/* Nav */}
      <nav className="flex-1 overflow-y-auto px-3 py-3 flex flex-col gap-0.5">
        {navItems.map((item, i) => {
          if ('isHeader' in item) {
            return (
              <div key={i} className="px-2 pt-4 pb-1 text-xs font-semibold tracking-widest" style={{ color: '#475569' }}>
                {item.label}
              </div>
            );
          }
          const Icon = item.icon!;
          const active = pathname === item.href || (item.href !== '/bang-cham-cong' && pathname?.startsWith(item.href!));
          return (
            <Link key={item.href} href={item.href!}
              className={`sidebar-nav-item ${active ? 'active' : ''}`}>
              <Icon size={16} />
              <span className="flex-1">{item.label}</span>
              {active && <ChevronRight size={12} style={{ color: '#3b82f6' }} />}
            </Link>
          );
        })}
      </nav>

      {/* User footer */}
      <div className="px-3 py-3" style={{ borderTop: '1px solid rgba(51,65,85,0.4)' }}>
        <div className="flex items-center gap-3 px-2 py-2 mb-2 rounded-xl" style={{ background: 'rgba(30,41,59,0.6)' }}>
          <div className="w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 text-xs font-bold"
            style={{ background: 'linear-gradient(135deg, #3b82f6, #8b5cf6)', color: 'white' }}>
            {user.full_name.charAt(0).toUpperCase()}
          </div>
          <div className="flex-1 min-w-0">
            <div className="text-sm font-medium truncate" style={{ color: '#f1f5f9' }}>{user.full_name}</div>
            <div className="flex items-center gap-1">
              {user.role === 'admin' && <Shield size={10} style={{ color: '#f59e0b' }} />}
              <span className="text-xs" style={{ color: '#64748b' }}>
                {user.role === 'admin' ? 'Admin' : 'Chuyên viên'}
              </span>
            </div>
          </div>
        </div>
        <button id="btn-logout" onClick={handleLogout}
          className="sidebar-nav-item w-full"
          style={{ color: '#ef4444' }}>
          <LogOut size={15} />
          Đăng xuất
        </button>
      </div>
    </aside>
  );
}
