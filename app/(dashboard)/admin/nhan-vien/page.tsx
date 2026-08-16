'use client';
import { useState, useEffect } from 'react';
import { createClient } from '@/lib/supabase/client';
import { AppUser } from '@/types';
import toast from 'react-hot-toast';
import { Plus, Edit2, Shield, User, ToggleLeft, ToggleRight, X, Eye, EyeOff, Download, Upload, FileSpreadsheet } from 'lucide-react';
import * as XLSX from 'xlsx';

export default function NhanVienPage() {
  const supabase = createClient();
  const [users, setUsers] = useState<AppUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState<{ open: boolean; user: AppUser | null }>({ open: false, user: null });
  const [form, setForm] = useState({ full_name: '', email: '', password: '', role: 'staff', position: '' });
  const [showPw, setShowPw] = useState(false);
  const [saving, setSaving] = useState(false);

  async function load() {
    setLoading(true);
    const { data } = await supabase.rpc('rpc_get_all_staff');
    setUsers(data || []);
    setLoading(false);
  }
  useEffect(() => { load(); }, []);

  function openCreate() {
    setForm({ full_name: '', email: '', password: '', role: 'staff', position: '' });
    setShowPw(false);
    setModal({ open: true, user: null });
  }

  function openEdit(u: AppUser) {
    setForm({ full_name: u.full_name, email: u.email, password: '', role: u.role, position: u.position || '' });
    setShowPw(false);
    setModal({ open: true, user: u });
  }

  async function handleSave() {
    if (!form.full_name.trim() || !form.email.trim()) { toast.error('Nhập đầy đủ họ tên và email'); return; }
    setSaving(true);

    if (!modal.user) {
      // Tạo mới qua Admin API nội bộ (để không bị mất phiên đăng nhập hiện tại)
      if (!form.password) { toast.error('Nhập mật khẩu'); setSaving(false); return; }
      
      const res = await fetch('/api/admin/users', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          action: 'create_user',
          payload: { ...form }
        })
      });
      const data = await res.json();
      
      if (!res.ok) {
        toast.error(data.error || 'Lỗi tạo nhân viên');
        setSaving(false);
        return;
      }
    } else {
      // Cập nhật thông tin
      const { error } = await supabase.from('users').update({
        full_name: form.full_name,
        role: form.role,
        position: form.position || null,
      }).eq('id', modal.user.id);
      
      if (error) { toast.error(error.message); setSaving(false); return; }

      // Reset mật khẩu nếu có nhập
      if (form.password) {
        const res = await fetch('/api/admin/users', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            action: 'update_password',
            payload: { uid: modal.user.auth_id, password: form.password }
          })
        });
        if (!res.ok) toast.error('Lỗi đổi mật khẩu');
        else toast.success('Đã đổi mật khẩu!');
      }
    }

    toast.success(modal.user ? 'Đã cập nhật!' : 'Đã tạo nhân viên!');
    setModal({ open: false, user: null });
    load();
    setSaving(false);
  }

  async function toggleActive(u: AppUser) {
    await supabase.from('users').update({ is_active: !u.is_active }).eq('id', u.id);
    toast.success(!u.is_active ? 'Đã kích hoạt' : 'Đã vô hiệu hoá');
    load();
  }

  function handleExportExcel() {
    if (users.length === 0) { toast.error('Không có dữ liệu để xuất'); return; }
    const data = users.map(u => ({
      'Họ tên': u.full_name,
      'Email': u.email,
      'Chức vụ': u.position || '',
      'Vai trò': u.role === 'admin' ? 'Admin' : 'Chuyên viên',
      'Trạng thái': u.is_active ? 'Hoạt động' : 'Đã vô hiệu hoá'
    }));
    const ws = XLSX.utils.json_to_sheet(data);
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, 'DanhSachNhanVien');
    XLSX.writeFile(wb, 'DanhSachNhanVien.xlsx');
  }

  return (
    <div className="p-6 flex flex-col gap-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold" style={{ color: '#f1f5f9' }}>Quản lý Nhân viên</h1>
          <p className="text-sm mt-0.5" style={{ color: '#64748b' }}>Thêm, sửa thông tin và phân quyền nhân viên</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <button onClick={handleExportExcel} className="btn btn-secondary btn-sm">
            <Download size={16} /> Xuất Excel
          </button>

          <button id="btn-add-staff" onClick={openCreate} className="btn btn-primary btn-sm ml-2">
            <Plus size={16} /> Thêm nhân viên
          </button>
        </div>
      </div>

      <div className="glass-card overflow-hidden">
        {loading ? (
          <div className="p-8 text-center" style={{ color: '#475569' }}>Đang tải...</div>
        ) : (
          <table className="table-dark">
            <thead>
              <tr>
                <th>Họ tên</th>
                <th>Email</th>
                <th>Chức vụ</th>
                <th>Vai trò</th>
                <th>Trạng thái</th>
                <th>Thao tác</th>
              </tr>
            </thead>
            <tbody>
              {users.map(u => (
                <tr key={u.id}>
                  <td>
                    <div className="flex items-center gap-2.5">
                      <div className="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0"
                        style={{ background: u.role === 'admin' ? 'linear-gradient(135deg,#f59e0b,#d97706)' : 'linear-gradient(135deg,#3b82f6,#6366f1)', color: 'white' }}>
                        {u.full_name.charAt(0)}
                      </div>
                      <span className="font-medium" style={{ color: '#f1f5f9' }}>{u.full_name}</span>
                    </div>
                  </td>
                  <td style={{ color: '#94a3b8' }}>{u.email}</td>
                  <td style={{ color: '#94a3b8' }}>{u.position || '—'}</td>
                  <td>
                    <span className={`badge ${u.role === 'admin' ? 'bg-amber-500/15 text-amber-400 border-amber-500/25' : 'bg-blue-500/15 text-blue-400 border-blue-500/25'}`}>
                      {u.role === 'admin' ? <><Shield size={9} className="inline mr-1" />Admin</> : <><User size={9} className="inline mr-1" />Chuyên viên</>}
                    </span>
                  </td>
                  <td>
                    <button onClick={() => toggleActive(u)} title={u.is_active ? 'Vô hiệu hoá' : 'Kích hoạt'}
                      style={{ background: 'none', border: 'none', cursor: 'pointer' }}>
                      {u.is_active
                        ? <ToggleRight size={22} style={{ color: '#10b981' }} />
                        : <ToggleLeft  size={22} style={{ color: '#475569' }} />}
                    </button>
                  </td>
                  <td>
                    <button id={`btn-edit-${u.id.slice(0,8)}`} onClick={() => openEdit(u)} className="btn btn-ghost btn-xs">
                      <Edit2 size={12} /> Sửa
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Modal */}
      {modal.open && (
        <div className="modal-overlay" onClick={() => setModal({ open: false, user: null })}>
          <div className="modal-box" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between px-6 pt-6 pb-5" style={{ borderBottom: '1px solid rgba(51,65,85,0.4)' }}>
              <div>
                <h3 className="font-semibold text-lg" style={{ color: '#f1f5f9' }}>
                  {modal.user ? 'Cập nhật Nhân viên' : 'Thêm Nhân viên mới'}
                </h3>
              </div>
              <button onClick={() => setModal({ open: false, user: null })} className="btn btn-ghost btn-sm">
                <X size={18} />
              </button>
            </div>
            <div className="p-6 flex flex-col gap-5">
              {[
                { label: 'Họ tên *', key: 'full_name', type: 'text', placeholder: 'Nguyễn Văn A' },
                { label: 'Email *', key: 'email', type: 'email', placeholder: 'nva@congty.vn', disabled: !!modal.user },
                { label: 'Chức vụ', key: 'position', type: 'text', placeholder: 'VD: Chuyên viên kế hoạch' },
              ].map(f => (
                <div key={f.key}>
                  <label className="block text-xs font-medium mb-1.5" style={{ color: '#94a3b8' }}>{f.label}</label>
                  <input type={f.type} className="input-dark" placeholder={f.placeholder}
                    value={form[f.key as keyof typeof form]}
                    onChange={e => setForm(p => ({ ...p, [f.key]: e.target.value }))}
                    disabled={f.disabled} />
                </div>
              ))}

              <div>
                <label className="block text-xs font-medium mb-1.5" style={{ color: '#94a3b8' }}>
                  {modal.user ? 'Đặt lại mật khẩu (bỏ trống nếu không đổi)' : 'Mật khẩu *'}
                </label>
                <div className="relative">
                  <input type={showPw ? 'text' : 'password'} className="input-dark" placeholder="••••••••"
                    value={form.password}
                    onChange={e => setForm(p => ({ ...p, password: e.target.value }))}
                    style={{ paddingRight: '2.75rem' }} />
                  <button type="button" onClick={() => setShowPw(!showPw)}
                    style={{ position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)', color: '#64748b', background: 'none', border: 'none', cursor: 'pointer' }}>
                    {showPw ? <EyeOff size={15} /> : <Eye size={15} />}
                  </button>
                </div>
              </div>

              <div>
                <label className="block text-xs font-medium mb-1.5" style={{ color: '#94a3b8' }}>Vai trò</label>
                <select className="input-dark" value={form.role} onChange={e => setForm(p => ({ ...p, role: e.target.value }))}>
                  <option value="staff">Chuyên viên</option>
                  <option value="admin">Admin</option>
                </select>
              </div>

              <div className="flex gap-2 pt-1">
                <button onClick={() => setModal({ open: false, user: null })} className="btn btn-ghost flex-1">Huỷ</button>
                <button id="btn-save-staff" onClick={handleSave} className="btn btn-primary flex-1" disabled={saving}>
                  {saving ? 'Đang lưu...' : 'Lưu'}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
