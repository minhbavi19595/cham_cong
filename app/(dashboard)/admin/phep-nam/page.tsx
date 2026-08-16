'use client';
import { useState, useEffect } from 'react';
import { createClient } from '@/lib/supabase/client';
import toast from 'react-hot-toast';
import { Edit2, X } from 'lucide-react';

interface QuotaRow { user_id: string; full_name: string; leave_base: number; leave_used: number; leave_remaining: number; }

export default function PhepNamPage() {
  const supabase = createClient();
  const [year, setYear] = useState(new Date().getFullYear());
  const [rows, setRows]   = useState<QuotaRow[]>([]);
  const [users, setUsers] = useState<{id:string;full_name:string}[]>([]);
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState<{ open:boolean; userId:string; userName:string; days:number; quotaId:string|null } | null>(null);
  const [saving, setSaving] = useState(false);

  async function load() {
    setLoading(true);
    const res = await supabase.rpc('rpc_get_all_leave_balances', { p_year: year });
    setRows(Array.isArray(res.data) ? res.data : []);
    setLoading(false);
  }
  useEffect(() => { load(); }, [year]);

  function openEdit(r: QuotaRow) {
    setModal({ open:true, userId:r.user_id, userName:r.full_name, days:r.leave_base, quotaId:null });
  }

  async function handleSave() {
    if (!modal) return;
    setSaving(true);
    const payload = { user_id: modal.userId, year, total_days: modal.days };
    const { error } = await supabase.from('leave_quota').upsert(payload, { onConflict:'user_id,year' });
    setSaving(false);
    if (error) { toast.error(error.message); return; }
    toast.success('Đã cập nhật quỹ phép!');
    setModal(null);
    load();
  }

  return (
    <div className="p-6 flex flex-col gap-6">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold" style={{ color:'#f1f5f9' }}>Quỹ phép năm</h1>
          <p className="text-sm mt-0.5" style={{ color:'#64748b' }}>Setup số ngày phép năm cho từng nhân viên</p>
        </div>
        <select className="input-dark" style={{ width:100 }} value={year} onChange={e => setYear(+e.target.value)}>
          {Array.from({length: Math.max(1, new Date().getFullYear() - 2026 + 1)}, (_, i) => new Date().getFullYear() - i).map(y=><option key={y} value={y}>{y}</option>)}
        </select>
      </div>

      <div className="glass-card overflow-hidden">
        {loading ? (
          <div className="p-8 text-center" style={{ color:'#475569' }}>Đang tải...</div>
        ) : (
          <table className="table-dark">
            <thead>
              <tr>
                <th>Nhân viên</th>
                <th style={{ textAlign:'center' }}>Quỹ gốc {year}</th>
                <th style={{ textAlign:'center' }}>Đã nghỉ</th>
                <th style={{ textAlign:'center' }}>Phép còn lại</th>
                <th style={{ textAlign:'right' }}>Thao tác</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(r => (
                <tr key={r.user_id}>
                  <td>
                    <div className="flex items-center gap-2.5">
                      <div className="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0"
                        style={{ background:'linear-gradient(135deg,#3b82f6,#6366f1)', color:'white' }}>
                        {r.full_name.charAt(0)}
                      </div>
                      <span style={{ color:'#f1f5f9' }}>{r.full_name}</span>
                    </div>
                  </td>
                  <td style={{ textAlign:'center' }}>
                    <span className="text-sm font-semibold" style={{ color:'#94a3b8' }}>{r.leave_base}</span>
                  </td>
                  <td style={{ textAlign:'center' }}>
                    <span className="text-sm font-semibold" style={{ color:'#f87171' }}>{r.leave_used > 0 ? `-${r.leave_used}` : 0}</span>
                  </td>
                  <td style={{ textAlign:'center' }}>
                    <span className="text-xl font-bold" style={{ color:'#10b981' }}>{r.leave_remaining}</span>
                    <span className="text-xs ml-1" style={{ color:'#64748b' }}>ngày</span>
                  </td>
                  <td style={{ textAlign:'right' }}>
                    <button id={`btn-edit-quota-${r.user_id.slice(0,8)}`} onClick={() => openEdit(r)} className="btn btn-ghost btn-xs">
                      <Edit2 size={12} /> Cập nhật Quỹ gốc
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {modal?.open && (
        <div className="modal-overlay" onClick={() => setModal(null)}>
          <div className="modal-box" style={{ maxWidth:360 }} onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between px-5 pt-5 pb-4" style={{ borderBottom:'1px solid rgba(51,65,85,0.4)' }}>
              <h3 className="font-semibold" style={{ color:'#f1f5f9' }}>Cập nhật quỹ phép — {modal.userName}</h3>
              <button onClick={() => setModal(null)} className="btn btn-ghost btn-sm"><X size={16} /></button>
            </div>
            <div className="p-5 flex flex-col gap-4">
              <div>
                <label className="block text-xs font-medium mb-1.5" style={{ color:'#94a3b8' }}>Quỹ gốc (Base Quota) năm {year}</label>
                <input type="number" min="0" max="365" step="0.5" className="input-dark"
                  value={modal.days} onChange={e => setModal(m => m ? { ...m, days: parseFloat(e.target.value) || 0 } : m)} />
              </div>
              <div className="flex gap-2">
                <button onClick={() => setModal(null)} className="btn btn-ghost flex-1">Huỷ</button>
                <button id="btn-save-quota" onClick={handleSave} className="btn btn-primary flex-1" disabled={saving}>
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
