'use client';
import { useState, useEffect, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import { AttendanceEditLog } from '@/types';
import { Search, Filter } from 'lucide-react';
import dayjs from 'dayjs';

export default function GiaiTrinhPage() {
  const supabase = createClient();
  const [logs, setLogs]       = useState<AttendanceEditLog[]>([]);
  const [users, setUsers]     = useState<{id:string;full_name:string}[]>([]);
  const [loading, setLoading] = useState(true);
  const [filters, setFilters] = useState({ 
    user_id: '', 
    from_date: dayjs().startOf('month').format('YYYY-MM-DD'), 
    to_date: dayjs().endOf('month').format('YYYY-MM-DD') 
  });

  async function load() {
    setLoading(true);
    const params: Record<string,unknown> = {};
    if (filters.user_id)   params.p_user_id   = filters.user_id;
    if (filters.from_date) params.p_from_date = filters.from_date;
    if (filters.to_date)   params.p_to_date   = filters.to_date;
    const { data } = await supabase.rpc('rpc_admin_get_giai_trinh', params);
    setLogs(data || []);
    setLoading(false);
  }

  useEffect(() => {
    supabase.rpc('rpc_get_all_staff').then(({ data }) => setUsers((data || []).filter((u: {role:string}) => u.role==='staff')));
    load();
  }, []);

  return (
    <div className="p-6 flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold" style={{ color:'#f1f5f9' }}>Lịch sử Giải trình</h1>
        <p className="text-sm mt-0.5" style={{ color:'#64748b' }}>Toàn bộ các lần chuyên viên sửa dữ liệu ngày đã qua và lý do giải trình</p>
      </div>

      {/* Filters */}
      <div className="glass-card p-4 flex flex-wrap items-end gap-3">
        <Filter size={14} style={{ color:'#64748b', marginBottom:2 }} />
        <div>
          <label className="block text-xs mb-1" style={{ color:'#94a3b8' }}>Nhân viên</label>
          <select className="input-dark" style={{ width:200 }} value={filters.user_id} onChange={e => setFilters(p => ({ ...p, user_id: e.target.value }))}>
            <option value="">Tất cả</option>
            {users.map(u => <option key={u.id} value={u.id}>{u.full_name}</option>)}
          </select>
        </div>
        <div>
          <label className="block text-xs mb-1" style={{ color:'#94a3b8' }}>Từ ngày</label>
          <input type="date" className="input-dark" style={{ width:155 }} value={filters.from_date} onChange={e => setFilters(p => ({ ...p, from_date: e.target.value }))} />
        </div>
        <div>
          <label className="block text-xs mb-1" style={{ color:'#94a3b8' }}>Đến ngày</label>
          <input type="date" className="input-dark" style={{ width:155 }} value={filters.to_date} onChange={e => setFilters(p => ({ ...p, to_date: e.target.value }))} />
        </div>
        <button id="btn-filter-giai-trinh" onClick={load} className="btn btn-primary btn-sm">
          <Search size={14} /> Lọc
        </button>
      </div>

      <div className="glass-card overflow-hidden">
        {loading ? (
          <div className="p-8 text-center" style={{ color:'#475569' }}>Đang tải...</div>
        ) : logs.length === 0 ? (
          <div className="p-10 text-center" style={{ color:'#475569' }}>
            <div className="text-4xl mb-3">📋</div>
            <div>Không có giải trình nào</div>
          </div>
        ) : (
          <table className="table-dark">
            <thead>
              <tr>
                <th>Thời gian sửa</th>
                <th>Nhân viên</th>
                <th>Ngày công</th>
                <th>Loại cũ</th>
                <th>Loại mới</th>
                <th>Lý do giải trình</th>
              </tr>
            </thead>
            <tbody>
              {logs.map(l => (
                <tr key={l.id}>
                  <td style={{ color:'#64748b', whiteSpace:'nowrap' }}>
                    {dayjs(l.edited_at).format('DD/MM/YYYY HH:mm')}
                  </td>
                  <td>
                    <span className="font-medium" style={{ color:'#f1f5f9' }}>{l.editor_name}</span>
                  </td>
                  <td style={{ color:'#93c5fd', fontWeight:600 }}>
                    {dayjs(l.work_date).format('DD/MM/YYYY')}
                  </td>
                  <td>
                    {l.old_type_code
                      ? <span className="badge bg-slate-500/15 text-slate-300 border-slate-500/25">{l.old_type_code}</span>
                      : <span style={{ color:'#475569' }}>—</span>}
                  </td>
                  <td>
                    <span className="badge bg-blue-500/15 text-blue-300 border-blue-500/25">{l.new_type_code}</span>
                  </td>
                  <td style={{ color:'#94a3b8', maxWidth:320 }}>
                    <span title={l.reason}>{l.reason}</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
