'use client';
import { useState, useEffect } from 'react';
import { createClient } from '@/lib/supabase/client';
import { AttendanceRule } from '@/types';
import toast from 'react-hot-toast';
import { Plus, Edit2, Trash2, X, Info } from 'lucide-react';

const DAY_CATS = ['weekday','weekend','holiday'] as const;
const DAY_CAT_LABEL: Record<string, string> = { weekday:'Ngày thường (T2–T6)', weekend:'Cuối tuần (T7, CN)', holiday:'Ngày lễ / Tết' };
const DAY_CAT_COLOR: Record<string, string> = { weekday:'bg-blue-500/10 text-blue-300 border-blue-500/20', weekend:'bg-violet-500/10 text-violet-300 border-violet-500/20', holiday:'bg-rose-500/10 text-rose-300 border-rose-500/20' };

export default function QuyTacPage() {
  const supabase = createClient();
  const [rules, setRules] = useState<AttendanceRule[]>([]);
  const [groups, setGroups] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState<{ open: boolean; rule: AttendanceRule | null }>({ open: false, rule: null });
  const [form, setForm] = useState({ type_group:'', day_category:'weekday', comp_off_delta:0, weekly_off_delta:0, leave_delta:0, counts_as_work_day:false, note:'' });
  const [saving, setSaving] = useState(false);

  async function load() {
    setLoading(true);
    const [rulesRes, typesRes] = await Promise.all([
      supabase.from('attendance_rules').select('*').order('type_group').order('day_category'),
      supabase.from('attendance_types').select('type_group').eq('is_active', true),
    ]);
    setRules(rulesRes.data || []);
    const uniqueGroups = [...new Set((typesRes.data || []).map((t: {type_group:string}) => t.type_group))];
    setGroups(uniqueGroups);
    setLoading(false);
  }
  useEffect(() => { load(); }, []);

  function openCreate() {
    setForm({ type_group:'', day_category:'weekday', comp_off_delta:0, weekly_off_delta:0, leave_delta:0, counts_as_work_day:false, note:'' });
    setModal({ open: true, rule: null });
  }
  function openEdit(r: AttendanceRule) {
    setForm({ type_group: r.type_group, day_category: r.day_category, comp_off_delta: r.comp_off_delta, weekly_off_delta: r.weekly_off_delta, leave_delta: r.leave_delta, counts_as_work_day: r.counts_as_work_day, note: r.note || '' });
    setModal({ open: true, rule: r });
  }

  async function handleSave() {
    if (!form.type_group) { toast.error('Chọn nhóm loại công'); return; }
    setSaving(true);
    const payload = { type_group: form.type_group, day_category: form.day_category, comp_off_delta: form.comp_off_delta, weekly_off_delta: form.weekly_off_delta, leave_delta: form.leave_delta, counts_as_work_day: form.counts_as_work_day, note: form.note || null };
    let error;
    if (modal.rule) {
      ({ error } = await supabase.from('attendance_rules').update(payload).eq('id', modal.rule.id));
    } else {
      ({ error } = await supabase.from('attendance_rules').upsert(payload));
    }
    setSaving(false);
    if (error) { toast.error(error.message); return; }
    toast.success('Đã lưu rule!');
    setModal({ open: false, rule: null });
    load();
  }

  async function handleDelete(id: string) {
    if (!confirm('Xoá rule này?')) return;
    await supabase.from('attendance_rules').delete().eq('id', id);
    toast.success('Đã xoá'); load();
  }

  // Group rules by type_group
  const grouped: Record<string, AttendanceRule[]> = {};
  for (const r of rules) {
    if (!grouped[r.type_group]) grouped[r.type_group] = [];
    grouped[r.type_group].push(r);
  }

  return (
    <div className="p-6 flex flex-col gap-6">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold" style={{ color:'#f1f5f9' }}>Rule Engine — Quy tắc chấm công</h1>
          <p className="text-sm mt-0.5" style={{ color:'#64748b' }}>Cấu hình phát sinh / trừ ngày nghỉ bù, nghỉ tuần, phép năm theo từng loại công × loại ngày</p>
        </div>
        <button id="btn-add-rule" onClick={openCreate} className="btn btn-primary">
          <Plus size={16} /> Thêm rule
        </button>
      </div>

      {loading ? (
        <div className="text-center p-8" style={{ color:'#475569' }}>Đang tải...</div>
      ) : (
        Object.entries(grouped).map(([grp, grpRules]) => (
          <div key={grp} className="glass-card overflow-hidden">
            <div className="px-5 py-3" style={{ borderBottom:'1px solid rgba(51,65,85,0.4)', background:'rgba(15,23,42,0.5)' }}>
              <span className="font-semibold text-sm" style={{ color:'#f1f5f9' }}>Nhóm: <span style={{ color:'#60a5fa' }}>{grp}</span></span>
            </div>
            <table className="table-dark">
              <thead>
                <tr>
                  <th>Loại ngày</th>
                  <th style={{ textAlign:'center' }}>+/− Nghỉ bù</th>
                  <th style={{ textAlign:'center' }}>+/− Nghỉ tuần</th>
                  <th style={{ textAlign:'center' }}>+/− Phép năm</th>
                  <th style={{ textAlign:'center' }}>Tính ngày công</th>
                  <th>Ghi chú</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {grpRules.map(r => (
                  <tr key={r.id}>
                    <td><span className={`badge ${DAY_CAT_COLOR[r.day_category]}`}>{DAY_CAT_LABEL[r.day_category]}</span></td>
                    <td style={{ textAlign:'center' }}>
                      <span className="font-bold" style={{ color: r.comp_off_delta > 0 ? '#10b981' : r.comp_off_delta < 0 ? '#ef4444' : '#64748b' }}>
                        {r.comp_off_delta > 0 ? '+' : ''}{r.comp_off_delta}
                      </span>
                    </td>
                    <td style={{ textAlign:'center' }}>
                      <span className="font-bold" style={{ color: r.weekly_off_delta > 0 ? '#10b981' : r.weekly_off_delta < 0 ? '#ef4444' : '#64748b' }}>
                        {r.weekly_off_delta > 0 ? '+' : ''}{r.weekly_off_delta}
                      </span>
                    </td>
                    <td style={{ textAlign:'center' }}>
                      <span className="font-bold" style={{ color: r.leave_delta > 0 ? '#10b981' : r.leave_delta < 0 ? '#ef4444' : '#64748b' }}>
                        {r.leave_delta > 0 ? '+' : ''}{r.leave_delta}
                      </span>
                    </td>
                    <td style={{ textAlign:'center' }}>
                      <span className={`badge ${r.counts_as_work_day ? 'bg-emerald-500/15 text-emerald-400' : 'bg-slate-500/15 text-slate-400'}`}>
                        {r.counts_as_work_day ? 'Có' : 'Không'}
                      </span>
                    </td>
                    <td style={{ color:'#64748b', fontSize:'0.75rem' }}>{r.note || '—'}</td>
                    <td>
                      <div className="flex gap-1">
                        <button onClick={() => openEdit(r)} className="btn btn-ghost btn-xs"><Edit2 size={11} /></button>
                        <button onClick={() => handleDelete(r.id)} className="btn btn-ghost btn-xs" style={{ color:'#ef4444' }}><Trash2 size={11} /></button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ))
      )}

      {modal.open && (
        <div className="modal-overlay" onClick={() => setModal({ open:false, rule:null })}>
          <div className="modal-box" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between px-5 pt-5 pb-4" style={{ borderBottom:'1px solid rgba(51,65,85,0.4)' }}>
              <h3 className="font-semibold" style={{ color:'#f1f5f9' }}>{modal.rule ? 'Sửa rule' : 'Thêm rule'}</h3>
              <button onClick={() => setModal({ open:false, rule:null })} className="btn btn-ghost btn-sm"><X size={16} /></button>
            </div>
            <div className="p-5 flex flex-col gap-4">
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium mb-1.5" style={{ color:'#94a3b8' }}>Nhóm loại công *</label>
                  <select className="input-dark" value={form.type_group} onChange={e => setForm(p => ({ ...p, type_group: e.target.value }))}>
                    <option value="">-- Chọn --</option>
                    {groups.map(g => <option key={g} value={g}>{g}</option>)}
                  </select>
                </div>
                <div>
                  <label className="block text-xs font-medium mb-1.5" style={{ color:'#94a3b8' }}>Loại ngày *</label>
                  <select className="input-dark" value={form.day_category} onChange={e => setForm(p => ({ ...p, day_category: e.target.value }))}>
                    {DAY_CATS.map(d => <option key={d} value={d}>{DAY_CAT_LABEL[d]}</option>)}
                  </select>
                </div>
              </div>
              <div className="grid grid-cols-3 gap-3">
                {[
                  { key:'comp_off_delta', label:'+/− Nghỉ bù' },
                  { key:'weekly_off_delta', label:'+/− Nghỉ tuần' },
                  { key:'leave_delta', label:'+/− Phép năm' },
                ].map(f => (
                  <div key={f.key}>
                    <label className="block text-xs font-medium mb-1.5" style={{ color:'#94a3b8' }}>{f.label}</label>
                    <input type="number" step="0.5" className="input-dark" value={form[f.key as keyof typeof form] as number}
                      onChange={e => setForm(p => ({ ...p, [f.key]: parseFloat(e.target.value) || 0 }))} />
                  </div>
                ))}
              </div>
              <div className="flex items-center gap-3">
                <input type="checkbox" id="counts_as_work_day" checked={form.counts_as_work_day}
                  onChange={e => setForm(p => ({ ...p, counts_as_work_day: e.target.checked }))}
                  style={{ accentColor:'#3b82f6', width:16, height:16 }} />
                <label htmlFor="counts_as_work_day" className="text-sm cursor-pointer" style={{ color:'#f1f5f9' }}>Tính là ngày công hành chính</label>
              </div>
              <div>
                <label className="block text-xs font-medium mb-1.5" style={{ color:'#94a3b8' }}>Ghi chú</label>
                <input type="text" className="input-dark" placeholder="Mô tả rule..." value={form.note}
                  onChange={e => setForm(p => ({ ...p, note: e.target.value }))} />
              </div>
              <div className="flex gap-2">
                <button onClick={() => setModal({ open:false, rule:null })} className="btn btn-ghost flex-1">Huỷ</button>
                <button id="btn-save-rule" onClick={handleSave} className="btn btn-primary flex-1" disabled={saving}>
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
