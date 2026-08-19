'use client';
import { useState, useEffect, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import { AttendanceRecord, AttendanceType, AttendanceGrid, DayOffBalance, MonthSummary, AppUser, TYPE_COLORS, TYPE_SHORT } from '@/types';
import toast from 'react-hot-toast';
import { ChevronLeft, ChevronRight, Download, Upload, FileSpreadsheet, AlertCircle, X, Plus } from 'lucide-react';
import * as XLSX from 'xlsx';
import dayjs from 'dayjs';
import 'dayjs/locale/vi';

dayjs.locale('vi');

const WEEKDAY_SHORT = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];

interface PageProps { user: AppUser; }

export default function BangChamCongClient({ user }: PageProps) {
    const supabase = createClient();
    const today = dayjs();

    const [month, setMonth] = useState(today.month() + 1);
    const [year, setYear] = useState(today.year());
    const [records, setRecords] = useState<AttendanceRecord[]>([]);
    const [types, setTypes] = useState<AttendanceType[]>([]);
    const [balance, setBalance] = useState<DayOffBalance | null>(null);
    const [userBalances, setUserBalances] = useState<Record<string, DayOffBalance>>({});
    const [summary, setSummary] = useState<MonthSummary | null>(null);
    const [loading, setLoading] = useState(true);
    const [teamMembers, setTeamMembers] = useState<{ id: string; full_name: string; position: string; manager_id: string | null }[]>([]);
    const [staffAccounts, setStaffAccounts] = useState<{ id: string; full_name: string }[]>([]);
    const [selectedManagerId, setSelectedManagerId] = useState<string | null>(null);
    const [showAddUserModal, setShowAddUserModal] = useState(false);
    const [newMemberName, setNewMemberName] = useState('');
    const [newMemberPos, setNewMemberPos] = useState('');

    // Chấm công modal
    const [modal, setModal] = useState<{
        open: boolean;
        userId: string;
        workDate: string;
        currentCode: string | null;
        isPast: boolean;
        isOpen: boolean;
    } | null>(null);
    const [selectedType, setSelectedType] = useState('');
    const [reason, setReason] = useState('');
    const [submitting, setSubmitting] = useState(false);

    const [nameColWidth, setNameColWidth] = useState(160);

    const daysInMonth = dayjs(`${year}-${month}-01`).daysInMonth();
    const days = Array.from({ length: daysInMonth }, (_, i) => i + 1);

    function getHolidayName(_d: number) { return null; }

    const [myTeamIds, setMyTeamIds] = useState<string[]>([]);

    useEffect(() => {
        const saved = localStorage.getItem('chamcong_team_ids');
        if (saved) {
            try { setMyTeamIds(JSON.parse(saved)); } catch (e) { }
        }
    }, []);

    useEffect(() => {
        localStorage.setItem('chamcong_team_ids', JSON.stringify(myTeamIds));
    }, [myTeamIds]);

    const loadData = useCallback(async () => {
        setLoading(true);
        try {
            // Nếu là Admin nhưng chưa chọn Manager nào thì chỉ load staffAccounts (nếu chưa có)
            if (user.role === 'admin' && !selectedManagerId) {
                const staffRes = await supabase.rpc('rpc_get_staff_accounts');
                setStaffAccounts(staffRes.data || []);
                if (staffRes.data && staffRes.data.length > 0) {
                    setSelectedManagerId(staffRes.data[0].id);
                }
                setLoading(false);
                return;
            }

            const p_manager_id = selectedManagerId || undefined;

            const [recordsRes, typesRes, balanceRes, summaryRes, teamRes] = await Promise.all([
                supabase.rpc('rpc_get_bang_cham_cong', { p_month: month, p_year: year, p_manager_id }),
                supabase.from('attendance_types').select('*').eq('is_active', true).order('sort_order'),
                supabase.rpc('rpc_get_so_du', { p_year: year }),
                supabase.rpc('rpc_get_tong_hop_thang', { p_month: month, p_year: year, p_manager_id }),
                supabase.rpc('rpc_get_team_members', { p_manager_id })
            ]);

            const fetchedUsers: { id: string; full_name: string; position: string; manager_id: string | null }[] = Array.isArray(teamRes.data) ? teamRes.data : [];

            if (recordsRes.error) {
                toast.error('Lỗi tải bảng chấm công: ' + recordsRes.error.message);
            }
            if (summaryRes.error) {
                toast.error('Lỗi tổng hợp: ' + summaryRes.error.message);
                console.error("Lỗi tổng hợp:", summaryRes.error);
            }

            setRecords(recordsRes.data || []);
            setTypes(typesRes.data || []);
            setBalance(balanceRes.data);

            const sumArr = Array.isArray(summaryRes.data) ? summaryRes.data : [];
            const sumMap: Record<string, any> = {};
            let totalWorkDays = 0;
            let totalDutyDays = 0;
            for (const s of sumArr) {
                s.duty_days = 0;
                s.tr_days = 0;
                s.trv_days = 0;
                s.tr_nl_days = 0;
                sumMap[s.user_id] = s;
                totalWorkDays += Number(s.work_days) || 0;
            }

            // Tính tổng các loại công cho cả team và số ngày trực của từng nhân viên
            const typeCounts: Record<string, number> = {};
            for (const r of (recordsRes.data || [])) {
                typeCounts[r.type_code] = (typeCounts[r.type_code] || 0) + 1;

                if (sumMap[r.user_id]) {
                    if (r.type_code === 'TR') sumMap[r.user_id].tr_days += 1;
                    else if (r.type_code === 'TRV') sumMap[r.user_id].trv_days += 1;
                    else if (r.type_code === 'TR_NL') sumMap[r.user_id].tr_nl_days += 1;

                    // Đếm tổng ngày trực cho mục đích khác (nếu cần)
                    const isDuty = ['TR', 'TRV', 'TR_NL'].includes(r.type_code);
                    if (isDuty) {
                        sumMap[r.user_id].duty_days += 1;
                        totalDutyDays += 1;
                    }
                }
            }
            setSummary({ work_days: totalWorkDays, duty_days: totalDutyDays, ...typeCounts });

            setUserBalances(sumMap);
            setTeamMembers(fetchedUsers);

            if (user.role === 'admin' && staffAccounts.length === 0) {
                const staffRes = await supabase.rpc('rpc_get_staff_accounts');
                setStaffAccounts(staffRes.data || []);
            }
        } catch (err) {
            console.error(err);
            toast.error('Lỗi tải dữ liệu');
        } finally {
            setLoading(false);
        }
    }, [month, year, selectedManagerId, user.role]);

    useEffect(() => { loadData(); }, [loadData]);

    useEffect(() => {
        if (!loading && month === dayjs().month() + 1 && year === dayjs().year()) {
            setTimeout(() => {
                const todayCol = document.getElementById('today-col');
                const container = document.getElementById('grid-scroll-container');
                if (todayCol && container) {
                    const thNhanVien = document.getElementById('th-nhan-vien');
                    const thChucVu = document.getElementById('th-chuc-vu');
                    const leftStickyWidth = (thNhanVien?.offsetWidth || 160) + (thChucVu?.offsetWidth || 120);
                    const rightStickyWidth = 424; // 7 cột bên phải (64*4 + 56*3)
                    const availableWidth = container.clientWidth - leftStickyWidth - rightStickyWidth;
                    
                    const colCenter = todayCol.offsetLeft + (todayCol.offsetWidth / 2);
                    const viewportCenter = leftStickyWidth + (availableWidth / 2);
                    
                    const targetScrollLeft = colCenter - viewportCenter;
                    container.scrollTo({ left: Math.max(0, targetScrollLeft), behavior: 'smooth' });
                }
            }, 100);
        }

        const thNhanVien = document.getElementById('th-nhan-vien');
        if (thNhanVien) {
            const observer = new ResizeObserver(entries => {
                for (const entry of entries) {
                    setNameColWidth(entry.target.getBoundingClientRect().width);
                }
            });
            observer.observe(thNhanVien);
            return () => observer.disconnect();
        }
    }, [loading, month, year]);

    // Build grid: userId → { 'YYYY-MM-DD': record }
    const grid: AttendanceGrid = {};
    for (const rec of records) {
        if (!grid[rec.user_id]) grid[rec.user_id] = {};
        grid[rec.user_id][rec.work_date] = rec;
    }

    // Danh sách người dùng hiển thị
    const displayUsers = teamMembers;

    function getDateStr(d: number) {
        return `${year}-${String(month).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
    }
    function isWeekend(d: number) {
        const dow = dayjs(getDateStr(d)).day();
        return dow === 0 || dow === 6;
    }
    function isToday(d: number) { return getDateStr(d) === today.format('YYYY-MM-DD'); }

    // Hết tháng thì khoá: Ngày thuộc tháng cũ so với tháng hiện tại sẽ bị khoá
    function isLockedMonth(d: number) {
        return dayjs(getDateStr(d)).isBefore(today.startOf('month'));
    }
    // Ngày đã qua nửa đêm (bắt buộc nhập lý do)
    function isPastDay(d: number) {
        return getDateStr(d) < today.format('YYYY-MM-DD');
    }

    function handleCellClick(uid: string, d: number) {
        if (user.role === 'admin') {
            toast.error('Quản trị viên chỉ có quyền xem bảng chấm công, không được phép chấm công.');
            return;
        }

        const dateStr = getDateStr(d);
        const locked = isLockedMonth(d);
        const past = isPastDay(d);
        const rec = grid[uid]?.[dateStr];

        // Tháng cũ đã chốt → không cho chấm
        if (locked) {
            toast.error('Tháng này đã chốt, không thể chỉnh sửa');
            return;
        }

        setSelectedType(rec?.type_code || '');
        setReason('');
        setModal({ open: true, userId: uid, workDate: dateStr, currentCode: rec?.type_code || null, isPast: past, isOpen: true });
    }

    async function handleSubmit() {
        if (!modal || !selectedType) { toast.error('Vui lòng chọn loại công'); return; }
        if (modal.isPast && !reason.trim()) { toast.error('Ngày đã qua — bắt buộc nhập lý do giải trình'); return; }
        setSubmitting(true);
        const { data, error } = await supabase.rpc('rpc_cham_cong', {
            p_user_id: modal.userId,
            p_work_date: modal.workDate,
            p_type_code: selectedType,
            p_reason: reason || null,
        });
        setSubmitting(false);
        if (error || data?.error) {
            toast.error(data?.error || error?.message || 'Lỗi chấm công');
        } else {
            toast.success('Đã lưu!');
            setModal(null);
            loadData();
        }
    }

    function prevMonth() {
        if (month === 1) { setMonth(12); setYear(y => y - 1); }
        else setMonth(m => m - 1);
    }
    function nextMonth() {
        if (month === 12) { setMonth(1); setYear(y => y + 1); }
        else setMonth(m => m + 1);
    }

    async function handleAddMember() {
        if (!newMemberName.trim()) { toast.error('Vui lòng nhập tên'); return; }
        setSubmitting(true);
        const { data, error } = await supabase.rpc('rpc_add_team_member', {
            p_full_name: newMemberName,
            p_position: newMemberPos
        });
        setSubmitting(false);
        if (error || data?.error) {
            toast.error(data?.error || error?.message || 'Lỗi tạo nhân viên');
        } else {
            toast.success('Đã thêm nhân viên vào tổ');
            setShowAddUserModal(false);
            setNewMemberName('');
            setNewMemberPos('');
            loadData();
        }
    }

    async function handleRemoveMember(uid: string) {
        if (!confirm('Bạn có chắc chắn muốn xoá nhân viên này khỏi bảng chấm công? Các dữ liệu chấm công cũ sẽ bị xoá.')) return;
        const { data, error } = await supabase.rpc('rpc_remove_team_member', { p_user_id: uid });
        if (error || data?.error) toast.error(data?.error || error?.message || 'Lỗi');
        else {
            toast.success('Đã xoá nhân viên');
            loadData();
        }
    }

    function handleDownloadTemplate() {
        const ws = XLSX.utils.json_to_sheet([
            { 'Tên nhân viên': 'Nguyễn Văn A', 'Chức vụ': 'Điều dưỡng' },
            { 'Tên nhân viên': 'Trần Thị B', 'Chức vụ': 'Hộ sinh' }
        ]);
        const wb = XLSX.utils.book_new();
        XLSX.utils.book_append_sheet(wb, ws, 'Mau_Nhap_Nhan_Vien_To');
        XLSX.writeFile(wb, 'Mau_Nhap_Nhan_Vien_To.xlsx');
    }

    async function handleImportExcel(e: React.ChangeEvent<HTMLInputElement>) {
        const file = e.target.files?.[0];
        if (!file) return;
        setLoading(true);

        const reader = new FileReader();
        reader.onload = async (evt) => {
            try {
                const ab = evt.target?.result;
                const wb = XLSX.read(ab, { type: 'array' });
                const wsname = wb.SheetNames[0];
                const ws = wb.Sheets[wsname];
                const data = XLSX.utils.sheet_to_json(ws) as any[];

                let successCount = 0;
                let errorCount = 0;

                for (const row of data) {
                    const name = row['Tên nhân viên'];
                    const position = row['Chức vụ'] || '';

                    if (!name) {
                        errorCount++;
                        continue;
                    }

                    const { error } = await supabase.rpc('rpc_add_team_member', {
                        p_full_name: name,
                        p_position: position
                    });

                    if (!error) successCount++;
                    else errorCount++;
                }

                toast.success(`Đã nhập thành công ${successCount} nhân viên. ${errorCount > 0 ? `Lỗi: ${errorCount}` : ''}`);
            } catch (err) {
                toast.error('Lỗi khi đọc file Excel');
                console.error(err);
            } finally {
                setLoading(false);
                loadData();
                e.target.value = ''; // reset input
            }
        };
        reader.readAsArrayBuffer(file);
    }

    function handleExportExcel() {
        if (displayUsers.length === 0) {
            toast.error('Không có dữ liệu để xuất');
            return;
        }

        const aoa: any[][] = [];
        const merges: any[] = [];
        let currentRow = 0;

        // Dòng 1: Tiêu đề bảng
        aoa.push([`BẢNG CHẤM CÔNG THÁNG ${month}/${year}`]);
        merges.push({ s: { r: currentRow, c: 0 }, e: { r: currentRow, c: 2 + daysInMonth + 4 } });
        currentRow++;

        // Dòng 2: Chú thích ký hiệu
        aoa.push(['KÝ HIỆU:']);
        currentRow++;

        // Chia chú thích thành 2 cột viết dọc
        const half = Math.ceil(types.length / 2);
        for (let i = 0; i < half; i++) {
            const row = [];
            const left = types[i] ? `${types[i].code}: ${types[i].name}` : '';
            const right = types[i + half] ? `${types[i + half].code}: ${types[i + half].name}` : '';

            row[1] = left; // Đặt ở cột B (index 1)
            row[7] = right; // Đặt ở cột H (index 7)
            aoa.push(row);

            // Gộp các cột để nội dung dài không bị tràn
            merges.push({ s: { r: currentRow, c: 1 }, e: { r: currentRow, c: 6 } });
            merges.push({ s: { r: currentRow, c: 7 }, e: { r: currentRow, c: 15 } });
            currentRow++;
        }

        // Dòng trống
        aoa.push([]);
        currentRow++;

        // Header chính (Hàng trên của merge)
        const h1Row = currentRow;
        const h1 = ['Tên nhân viên', 'Chức vụ'];
        for (let i = 1; i <= daysInMonth; i++) {
            h1.push(i === 1 ? 'Ngày trong tháng' : '');
        }
        h1.push('Hành chính', 'Nghỉ bù còn dư', 'Nghỉ tuần còn dư', 'Phép còn dư', 'Trực lễ', 'Trực', 'Trực viện');
        aoa.push(h1);
        currentRow++;

        // Header phụ (Hàng dưới: 1,2,3...)
        const h2Row = currentRow;
        const h2 = ['', ''];
        for (let i = 1; i <= daysInMonth; i++) {
            h2.push(i.toString());
        }
        h2.push('', '', '', '', '');
        aoa.push(h2);
        currentRow++;

        // Dữ liệu nhân viên
        displayUsers.forEach(u => {
            const row = [u.full_name, u.position || ''];
            for (let i = 1; i <= daysInMonth; i++) {
                const dateStr = getDateStr(i);
                const rec = records.find(r => r.user_id === u.id && r.work_date === dateStr);
                row.push(rec ? (TYPE_SHORT[rec.type_code] || rec.type_code) : '');
            }
            const bal = userBalances[u.id] as any;
            row.push(bal?.work_days || 0);
            row.push(bal?.comp_off_balance || 0);
            row.push(bal?.weekly_off_balance || 0);
            row.push(bal?.leave_remaining || 0);
            row.push(bal?.tr_nl_days || 0);
            row.push(bal?.tr_days || 0);
            row.push(bal?.trv_days || 0);
            aoa.push(row);
            currentRow++;
        });

        const ws = XLSX.utils.aoa_to_sheet(aoa);

        // Thiết lập gộp ô (Merge cells) cho các Header
        merges.push(
            { s: { r: h1Row, c: 0 }, e: { r: h2Row, c: 0 } }, // Tên nhân viên
            { s: { r: h1Row, c: 1 }, e: { r: h2Row, c: 1 } }, // Chức vụ
            { s: { r: h1Row, c: 2 }, e: { r: h1Row, c: 2 + daysInMonth - 1 } }, // Header: Ngày trong tháng
            { s: { r: h1Row, c: 2 + daysInMonth }, e: { r: h2Row, c: 2 + daysInMonth } }, // Hành chính
            { s: { r: h1Row, c: 2 + daysInMonth + 1 }, e: { r: h2Row, c: 2 + daysInMonth + 1 } }, // Bù
            { s: { r: h1Row, c: 2 + daysInMonth + 2 }, e: { r: h2Row, c: 2 + daysInMonth + 2 } }, // Tuần
            { s: { r: h1Row, c: 2 + daysInMonth + 3 }, e: { r: h2Row, c: 2 + daysInMonth + 3 } }, // Phép
            { s: { r: h1Row, c: 2 + daysInMonth + 4 }, e: { r: h2Row, c: 2 + daysInMonth + 4 } }, // Trực lễ
            { s: { r: h1Row, c: 2 + daysInMonth + 5 }, e: { r: h2Row, c: 2 + daysInMonth + 5 } }, // Trực
            { s: { r: h1Row, c: 2 + daysInMonth + 6 }, e: { r: h2Row, c: 2 + daysInMonth + 6 } }  // Trực viện
        );
        ws['!merges'] = merges;

        // Căn chỉnh độ rộng cột (Column Widths) để bảng nhỏ gọn vừa 1 màn hình
        const cols = [{ wch: 22 }, { wch: 15 }];
        for (let i = 1; i <= daysInMonth; i++) cols.push({ wch: 4 }); // Thu nhỏ các cột ngày
        cols.push({ wch: 11 }, { wch: 13 }, { wch: 13 }, { wch: 11 }, { wch: 9 }, { wch: 6 }, { wch: 9 });
        ws['!cols'] = cols;

        const wb = XLSX.utils.book_new();
        XLSX.utils.book_append_sheet(wb, ws, `BangChamCong_${month}_${year}`);
        XLSX.writeFile(wb, `BangChamCong_${month}_${year}.xlsx`);
    }

    return (
        <div className="p-6 flex flex-col gap-6 h-full overflow-hidden">
            {/* Header */}
            <div className="flex items-center justify-between flex-wrap gap-3">
                <div>
                    <h1 className="text-2xl font-bold" style={{ color: '#f1f5f9' }}>Bảng Chấm Công</h1>
                    <p className="text-sm mt-0.5" style={{ color: '#64748b' }}>
                        {user.role === 'admin' ? 'Xem toàn bộ nhân viên' : 'Chấm công cho tổ'}
                    </p>
                </div>

                <div className="flex items-center gap-4">
                    {/* Admin: Chọn Staff */}
                    {user.role === 'admin' && staffAccounts.length > 0 && (
                        <select
                            className="input-dark text-sm py-1.5"
                            value={selectedManagerId || ''}
                            onChange={(e) => setSelectedManagerId(e.target.value)}
                        >
                            {staffAccounts.map(s => (
                                <option key={s.id} value={s.id}>Tổ: {s.full_name}</option>
                            ))}
                        </select>
                    )}

                    {/* Staff: Quản lý nhân sự trong tổ */}
                    {user.role === 'staff' && (
                        <div className="flex items-center gap-2 mr-2">
                            <button onClick={handleDownloadTemplate} className="btn btn-ghost btn-sm" title="Tải Excel mẫu">
                                <FileSpreadsheet size={16} /> Mẫu
                            </button>

                            <label className="btn btn-outline btn-sm gap-2" style={{ color: '#10b981', borderColor: 'rgba(16,185,129,0.5)', cursor: 'pointer', margin: 0 }}>
                                <Upload size={16} /> Nhập Excel
                                <input type="file" accept=".xlsx, .xls" style={{ display: 'none' }} onChange={handleImportExcel} />
                            </label>

                            <button
                                onClick={() => setShowAddUserModal(true)}
                                className="btn btn-outline btn-sm gap-2"
                                style={{ color: '#3b82f6', borderColor: 'rgba(59,130,246,0.5)' }}
                            >
                                <Plus size={16} /> Thêm nhân viên
                            </button>
                        </div>
                    )}

                    <button onClick={handleExportExcel} className="btn btn-secondary btn-sm" title="Xuất Excel bảng chấm công">
                        <Download size={16} /> Xuất Excel
                    </button>

                    {/* Month picker */}
                    <div className="flex items-center gap-2">
                        <button id="btn-prev-month" onClick={prevMonth} className="btn btn-ghost btn-sm" title="Tháng trước"><ChevronLeft size={16} /></button>
                        <div className="glass-card flex items-center gap-1 px-2 py-1" style={{ borderRadius: 8 }}>
                            <span className="text-sm font-semibold pl-2" style={{ color: '#f1f5f9' }}>Tháng</span>
                            <select
                                className="bg-transparent text-sm font-semibold outline-none cursor-pointer text-center"
                                style={{ color: '#f1f5f9' }}
                                value={month}
                                onChange={e => setMonth(Number(e.target.value))}
                            >
                                {Array.from({ length: 12 }, (_, i) => i + 1).map(m => (
                                    <option key={m} value={m} className="bg-slate-800 text-slate-200">{m}</option>
                                ))}
                            </select>
                            <span className="text-sm font-semibold" style={{ color: '#f1f5f9' }}>/</span>
                            <select
                                className="bg-transparent text-sm font-semibold outline-none cursor-pointer text-center"
                                style={{ color: '#f1f5f9' }}
                                value={year}
                                onChange={e => setYear(Number(e.target.value))}
                            >
                                {Array.from({ length: Math.max(1, dayjs().year() - 2026 + 1) }, (_, i) => dayjs().year() - i).map(y => (
                                    <option key={y} value={y} className="bg-slate-800 text-slate-200">{y}</option>
                                ))}
                            </select>
                        </div>
                        <button id="btn-next-month" onClick={nextMonth} className="btn btn-ghost btn-sm" title="Tháng sau"><ChevronRight size={16} /></button>
                    </div>
                </div>
            </div>



            {/* Grid */}
            <div className="glass-card flex flex-col flex-1 min-h-0 overflow-hidden">
                {loading ? (
                    <div className="flex items-center justify-center p-16 flex-1">
                        <svg className="animate-spin" width="32" height="32" viewBox="0 0 24 24" fill="none">
                            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="#3b82f6" strokeWidth="4" />
                            <path className="opacity-75" fill="#3b82f6" d="M4 12a8 8 0 018-8v8z" />
                        </svg>
                    </div>
                ) : (
                    <div className="overflow-auto flex-1 min-h-0" id="grid-scroll-container">
                        <table className="table-dark" style={{ minWidth: 800 }}>
                            <thead>
                                <tr>
                                    <th id="th-nhan-vien" style={{ minWidth: 160, position: 'sticky', top: 0, left: 0, zIndex: 4, background: 'rgba(15,23,42,0.95)' }}>
                                        Nhân viên
                                    </th>
                                    <th id="th-chuc-vu" style={{ minWidth: 120, position: 'sticky', top: 0, left: nameColWidth, zIndex: 4, background: 'rgba(15,23,42,0.95)', borderRight: '1px solid rgba(51,65,85,0.5)' }}>
                                        Chức vụ
                                    </th>
                                    {days.map(d => {
                                        const dow = dayjs(getDateStr(d)).day();
                                        const isWknd = isWeekend(d);
                                        const tod = isToday(d);
                                        const colBg = isWknd ? 'rgba(51,65,85,0.25)' : 'transparent';
                                        const colColor = isWknd ? '#94a3b8' : '#64748b';
                                        return (
                                            <th
                                                key={d}
                                                id={tod ? 'today-col' : undefined}
                                                title={isWknd ? 'Cuối tuần' : undefined}
                                                style={{
                                                    position: 'sticky',
                                                    top: 0,
                                                    zIndex: 3,
                                                    padding: '0.4rem 0.15rem',
                                                    color: colColor,
                                                    textAlign: 'center',
                                                    minWidth: 46,
                                                    background: colBg,
                                                    borderBottom: isWknd ? '2px solid rgba(100,116,139,0.25)' : undefined,
                                                }}
                                            >
                                                <div style={{ fontSize: '0.6rem', fontWeight: 500 }}>{WEEKDAY_SHORT[dow]}</div>
                                                <div style={{ fontSize: '0.82rem', fontWeight: 700, lineHeight: 1.2 }}>{d}</div>
                                                {isWknd && (
                                                    <div style={{ width: 3, height: 3, borderRadius: '50%', background: '#64748b', margin: '2px auto 0' }} />
                                                )}
                                            </th>
                                        );
                                    })}
                                    {/* 7 cột cố định bên phải */}
                                    <th style={{ position: 'sticky', top: 0, right: 360, zIndex: 4, background: 'rgba(15,23,42,0.98)', width: 64, minWidth: 64, maxWidth: 64, textAlign: 'center', borderLeft: '1px solid rgba(51,65,85,0.5)', color: '#8b5cf6', fontSize: '0.65rem', whiteSpace: 'normal', lineHeight: 1.2, padding: '0.3rem 0.2rem' }}>Hành chính</th>
                                    <th style={{ position: 'sticky', top: 0, right: 296, zIndex: 4, background: 'rgba(15,23,42,0.98)', width: 64, minWidth: 64, maxWidth: 64, textAlign: 'center', borderLeft: '1px solid rgba(51,65,85,0.5)', color: '#f59e0b', fontSize: '0.65rem', whiteSpace: 'normal', lineHeight: 1.2, padding: '0.3rem 0.2rem' }}>Nghỉ bù còn dư</th>
                                    <th style={{ position: 'sticky', top: 0, right: 232, zIndex: 4, background: 'rgba(15,23,42,0.98)', width: 64, minWidth: 64, maxWidth: 64, textAlign: 'center', borderLeft: '1px solid rgba(51,65,85,0.5)', color: '#3b82f6', fontSize: '0.65rem', whiteSpace: 'normal', lineHeight: 1.2, padding: '0.3rem 0.2rem' }}>Nghỉ tuần còn dư</th>
                                    <th style={{ position: 'sticky', top: 0, right: 168, zIndex: 4, background: 'rgba(15,23,42,0.98)', width: 64, minWidth: 64, maxWidth: 64, textAlign: 'center', borderLeft: '1px solid rgba(51,65,85,0.5)', color: '#10b981', fontSize: '0.65rem', whiteSpace: 'normal', lineHeight: 1.2, padding: '0.3rem 0.2rem' }}>Phép còn dư</th>
                                    <th style={{ position: 'sticky', top: 0, right: 112, zIndex: 4, background: 'rgba(15,23,42,0.98)', width: 56, minWidth: 56, maxWidth: 56, textAlign: 'center', borderLeft: '1px solid rgba(51,65,85,0.5)', color: '#ec4899', fontSize: '0.65rem', whiteSpace: 'normal', lineHeight: 1.2, padding: '0.3rem 0.2rem' }}>Trực lễ</th>
                                    <th style={{ position: 'sticky', top: 0, right: 56, zIndex: 4, background: 'rgba(15,23,42,0.98)', width: 56, minWidth: 56, maxWidth: 56, textAlign: 'center', borderLeft: '1px solid rgba(51,65,85,0.5)', color: '#ec4899', fontSize: '0.65rem', whiteSpace: 'normal', lineHeight: 1.2, padding: '0.3rem 0.2rem' }}>Trực</th>
                                    <th style={{ position: 'sticky', top: 0, right: 0, zIndex: 4, background: 'rgba(15,23,42,0.98)', width: 56, minWidth: 56, maxWidth: 56, textAlign: 'center', borderLeft: '1px solid rgba(51,65,85,0.5)', color: '#ec4899', fontSize: '0.65rem', whiteSpace: 'normal', lineHeight: 1.2, padding: '0.3rem 0.2rem' }}>Trực viện</th>
                                </tr>
                            </thead>
                            <tbody>
                                {displayUsers.length === 0 && (
                                    <tr>
                                        <td colSpan={daysInMonth + 4} className="text-center py-8" style={{ color: '#475569' }}>
                                            Không có dữ liệu
                                        </td>
                                    </tr>
                                )}
                                {displayUsers.map(u => (
                                    <tr key={u.id}>
                                        <td style={{ minWidth: 160, position: 'sticky', left: 0, zIndex: 2, background: 'rgba(15,23,42,0.95)' }}>
                                            <div className="flex items-center justify-between group w-full px-1">
                                                <div className="font-medium text-sm flex-1 whitespace-nowrap" style={{ color: '#f1f5f9' }} title={u.full_name}>{u.full_name}</div>
                                                {user.role === 'staff' && u.id !== user.id && u.manager_id === user.id && (
                                                    <button
                                                        onClick={() => handleRemoveMember(u.id)}
                                                        className="opacity-0 group-hover:opacity-100 transition-opacity p-1 text-slate-500 hover:text-red-400 flex-shrink-0 ml-2"
                                                        title="Xoá nhân viên (xóa luôn dữ liệu)"
                                                    >
                                                        <X size={14} />
                                                    </button>
                                                )}
                                            </div>
                                        </td>
                                        <td style={{ minWidth: 120, position: 'sticky', left: nameColWidth, zIndex: 2, background: 'rgba(15,23,42,0.95)', borderRight: '1px solid rgba(51,65,85,0.4)' }}>
                                            <div className="text-xs whitespace-nowrap px-1" style={{ color: '#94a3b8' }} title={u.position || ''}>{u.position || '—'}</div>
                                        </td>
                                        {days.map(d => {
                                            const dateStr = getDateStr(d);
                                            const rec = grid[u.id]?.[dateStr];
                                            const locked = isLockedMonth(d);
                                            const tod = isToday(d);
                                            const wknd = isWeekend(d);

                                            let cellClass = 'att-cell ';
                                            if (tod) cellClass += 'today ';
                                            if (wknd) cellClass += 'weekend-day ';
                                            if (!rec && !locked) cellClass += 'empty-open ';
                                            if (!rec && locked) cellClass += 'empty-closed ';

                                            const colorCls = rec ? (TYPE_COLORS[rec.type_code] || 'bg-slate-500/20 text-slate-300') : '';

                                            return (
                                                <td key={d} style={{ padding: '0.3rem 0.2rem', textAlign: 'center' }}>
                                                    <div
                                                        id={`cell-${u.id.slice(0, 8)}-${dateStr}`}
                                                        className={cellClass + (rec ? colorCls : '')}
                                                        onClick={() => user.role !== 'admin' && !locked && handleCellClick(u.id, d)}
                                                        title={rec?.type_name || (locked ? 'Đã chốt' : (user.role === 'admin' ? 'Chỉ xem' : 'Click để chấm'))}
                                                        style={{
                                                            cursor: (user.role !== 'admin' && !locked) ? 'pointer' : 'default',
                                                            margin: '0 auto',
                                                        }}
                                                    >
                                                        {rec ? (TYPE_SHORT[rec.type_code] || rec.type_code) : (!locked ? '·' : '')}
                                                    </div>
                                                </td>
                                            );
                                        })}
                                        {/* 5 cột số dư cố định bên phải */}
                                        {(() => {
                                            const bal = userBalances[u.id] as any;
                                            return (<>
                                                <td style={{ position: 'sticky', right: 360, zIndex: 1, background: 'rgba(15,23,42,0.98)', textAlign: 'center', borderLeft: '1px solid rgba(51,65,85,0.4)', fontWeight: 700, fontSize: '0.8rem', color: '#8b5cf6', width: 64, minWidth: 64, maxWidth: 64 }}>
                                                    {bal ? bal.work_days : '–'}
                                                </td>
                                                <td style={{ position: 'sticky', right: 296, zIndex: 1, background: 'rgba(15,23,42,0.98)', textAlign: 'center', borderLeft: '1px solid rgba(51,65,85,0.4)', fontWeight: 700, fontSize: '0.8rem', color: '#f59e0b', width: 64, minWidth: 64, maxWidth: 64 }}>
                                                    {bal ? bal.comp_off_balance : '–'}
                                                </td>
                                                <td style={{ position: 'sticky', right: 232, zIndex: 1, background: 'rgba(15,23,42,0.98)', textAlign: 'center', borderLeft: '1px solid rgba(51,65,85,0.4)', fontWeight: 700, fontSize: '0.8rem', color: '#3b82f6', width: 64, minWidth: 64, maxWidth: 64 }}>
                                                    {bal ? bal.weekly_off_balance : '–'}
                                                </td>
                                                <td style={{ position: 'sticky', right: 168, zIndex: 1, background: 'rgba(15,23,42,0.98)', textAlign: 'center', borderLeft: '1px solid rgba(51,65,85,0.4)', fontWeight: 700, fontSize: '0.8rem', color: '#10b981', width: 64, minWidth: 64, maxWidth: 64 }}>
                                                    {bal ? bal.leave_remaining : '–'}
                                                </td>
                                                <td style={{ position: 'sticky', right: 112, zIndex: 1, background: 'rgba(15,23,42,0.98)', textAlign: 'center', borderLeft: '1px solid rgba(51,65,85,0.4)', fontWeight: 700, fontSize: '0.8rem', color: '#ec4899', width: 56, minWidth: 56, maxWidth: 56 }}>
                                                    {bal && bal.tr_nl_days > 0 ? bal.tr_nl_days : '–'}
                                                </td>
                                                <td style={{ position: 'sticky', right: 56, zIndex: 1, background: 'rgba(15,23,42,0.98)', textAlign: 'center', borderLeft: '1px solid rgba(51,65,85,0.4)', fontWeight: 700, fontSize: '0.8rem', color: '#ec4899', width: 56, minWidth: 56, maxWidth: 56 }}>
                                                    {bal && bal.tr_days > 0 ? bal.tr_days : '–'}
                                                </td>
                                                <td style={{ position: 'sticky', right: 0, zIndex: 1, background: 'rgba(15,23,42,0.98)', textAlign: 'center', borderLeft: '1px solid rgba(51,65,85,0.4)', fontWeight: 700, fontSize: '0.8rem', color: '#ec4899', width: 56, minWidth: 56, maxWidth: 56 }}>
                                                    {bal && bal.trv_days > 0 ? bal.trv_days : '–'}
                                                </td>
                                            </>);
                                        })()}
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}

                {/* Legend */}
                {!loading && (
                    <div className="flex flex-wrap items-center gap-4 px-4 py-2.5" style={{ borderTop: '1px solid rgba(51,65,85,0.3)', background: 'rgba(15,23,42,0.5)' }}>
                        <div className="flex items-center gap-1.5 text-xs" style={{ color: '#64748b' }}>
                            <div style={{ width: 10, height: 10, borderRadius: 2, background: 'rgba(51,65,85,0.4)', border: '1px solid rgba(100,116,139,0.3)' }} />
                            Cuối tuần (T7, CN)
                        </div>
                        <div className="flex items-center gap-1.5 text-xs" style={{ color: '#64748b' }}>
                            <div style={{ width: 10, height: 10, borderRadius: 2, background: 'rgba(59,130,246,0.08)', border: '1px dashed rgba(59,130,246,0.3)' }} />
                            Tháng đang mở
                        </div>
                    </div>
                )}
            </div>

            {/* Modal chấm công */}
            {modal?.open && (
                <div className="modal-overlay" onClick={() => setModal(null)}>
                    <div className="modal-box" onClick={e => e.stopPropagation()}>
                        <div className="flex items-center justify-between px-6 pt-6 pb-5" style={{ borderBottom: '1px solid rgba(51,65,85,0.4)' }}>
                            <div>
                                <h3 className="font-semibold text-lg" style={{ color: '#f1f5f9' }}>
                                    Chấm công — {teamMembers.find(u => u.id === modal.userId)?.full_name}
                                </h3>
                                <p className="text-sm mt-1 flex flex-wrap items-center gap-2" style={{ color: '#64748b' }}>
                                    {dayjs(modal.workDate).format('dddd, DD/MM/YYYY')}
                                    {modal.isPast && <span className="badge" style={{ background: 'rgba(239,68,68,0.15)', color: '#f87171', border: '1px solid rgba(239,68,68,0.3)' }}>Ngày đã qua</span>}
                                    {(() => { const dow = dayjs(modal.workDate).day(); return (dow === 0 || dow === 6); })() && <span className="badge" style={{ background: 'rgba(51,65,85,0.4)', color: '#94a3b8', border: '1px solid rgba(100,116,139,0.3)' }}>Cuối tuần</span>}
                                </p>
                            </div>
                            <button onClick={() => setModal(null)} className="btn btn-ghost btn-sm">
                                <X size={18} />
                            </button>
                        </div>
                        <div className="p-6 flex flex-col gap-5">
                            {/* Loại công */}
                            <div>
                                <label className="block text-xs font-medium mb-2" style={{ color: '#94a3b8' }}>Loại công</label>
                                <div className="grid grid-cols-3 gap-2">
                                    {types.filter(t => t.code !== 'TYT').map(t => (
                                        <button
                                            key={t.code}
                                            id={`type-btn-${t.code}`}
                                            onClick={() => setSelectedType(t.code)}
                                            className={`px-3 py-2 rounded-lg text-xs font-bold border-2 transition-all duration-200 ${selectedType === t.code
                                                    ? 'border-blue-400 shadow-[0_0_12px_rgba(59,130,246,0.6)] ' + (TYPE_COLORS[t.code] || '')
                                                    : 'border-transparent ' + (TYPE_COLORS[t.code] || 'bg-slate-800/40 text-slate-400') + ' hover:brightness-125'
                                                }`}
                                            style={{ cursor: 'pointer', transform: selectedType === t.code ? 'scale(1.02)' : 'scale(1)', opacity: selectedType === t.code ? 1 : 0.45 }}
                                        >
                                            <div className="font-bold">{t.code}</div>
                                            <div style={{ fontSize: '0.6rem', opacity: 0.85, marginTop: 2, lineHeight: 1.3 }}>{t.name}</div>
                                        </button>
                                    ))}
                                </div>
                            </div>

                            {/* Giải trình (bắt buộc nếu ngày đã qua) */}
                            {modal.isPast && (
                                <div>
                                    <label className="block text-xs font-medium mb-1.5" style={{ color: '#94a3b8' }}>
                                        Lý do giải trình <span style={{ color: '#ef4444' }}>*</span>
                                    </label>
                                    <div className="flex items-start gap-2 mb-2 p-2.5 rounded-lg" style={{ background: 'rgba(239,68,68,0.08)', border: '1px solid rgba(239,68,68,0.2)' }}>
                                        <AlertCircle size={13} style={{ color: '#f87171', flexShrink: 0, marginTop: 2 }} />
                                        <span className="text-xs" style={{ color: '#fca5a5' }}>Ngày đã qua nửa đêm — bắt buộc nhập lý do</span>
                                    </div>
                                    <textarea
                                        id="reason-input"
                                        className="input-dark"
                                        rows={3}
                                        placeholder="VD: Quên chấm do đi công tác..."
                                        value={reason}
                                        onChange={e => setReason(e.target.value)}
                                        style={{ resize: 'none' }}
                                    />
                                </div>
                            )}

                            <div className="flex gap-2 pt-1">
                                <button id="btn-cancel-chamcong" onClick={() => setModal(null)} className="btn btn-ghost flex-1">Huỷ</button>
                                <button id="btn-submit-chamcong" onClick={handleSubmit} className="btn btn-primary flex-1" disabled={submitting || !selectedType}>
                                    {submitting ? 'Đang lưu...' : 'Lưu'}
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            )}

            {/* Modal Thêm Nhân Viên Vào Bảng */}
            {showAddUserModal && (
                <div className="modal-overlay" onClick={() => setShowAddUserModal(false)}>
                    <div className="modal-box" style={{ maxWidth: 400 }} onClick={e => e.stopPropagation()}>
                        <div className="flex items-center justify-between px-5 pt-5 pb-4" style={{ borderBottom: '1px solid rgba(51,65,85,0.4)' }}>
                            <h3 className="font-semibold" style={{ color: '#f1f5f9' }}>Thêm nhân viên vào bảng</h3>
                            <button onClick={() => setShowAddUserModal(false)} className="btn btn-ghost btn-sm"><X size={16} /></button>
                        </div>
                        <div className="p-5 flex flex-col gap-4">
                            <div>
                                <label className="block text-xs font-medium mb-1.5" style={{ color: '#94a3b8' }}>Họ Tên</label>
                                <input
                                    autoFocus
                                    className="input-dark w-full"
                                    placeholder="VD: Nguyễn Văn A"
                                    value={newMemberName}
                                    onChange={e => setNewMemberName(e.target.value)}
                                />
                            </div>
                            <div>
                                <label className="block text-xs font-medium mb-1.5" style={{ color: '#94a3b8' }}>Chức vụ</label>
                                <input
                                    className="input-dark w-full"
                                    placeholder="VD: Nhân viên / Bảo vệ..."
                                    value={newMemberPos}
                                    onChange={e => setNewMemberPos(e.target.value)}
                                />
                            </div>
                            <div className="flex gap-2 pt-2">
                                <button onClick={() => setShowAddUserModal(false)} className="btn btn-ghost flex-1">Huỷ</button>
                                <button onClick={handleAddMember} className="btn btn-primary flex-1" disabled={submitting || !newMemberName}>
                                    {submitting ? 'Đang lưu...' : 'Thêm'}
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}
