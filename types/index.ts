// =============================================================
// types/index.ts — TypeScript interfaces toàn hệ thống
// =============================================================

export type UserRole = 'admin' | 'staff';

export type DayCategory = 'weekday' | 'weekend' | 'holiday';

export type LedgerType = 'comp_off' | 'weekly_off';

export interface AppUser {
  id: string;
  auth_id: string | null;
  full_name: string;
  email: string;
  role: UserRole;
  position: string | null;
  is_active: boolean;
  created_at: string;
}

export interface LeaveQuota {
  id: string;
  user_id: string;
  year: number;
  total_days: number;
}

export interface Holiday {
  holiday_date: string; // 'YYYY-MM-DD'
  name: string;
  created_by: string | null;
  created_at: string;
}

export interface AttendanceType {
  code: string;
  name: string;
  type_group: string;
  sort_order: number;
  is_active: boolean;
}

export interface AttendanceRule {
  id: string;
  type_group: string;
  day_category: DayCategory;
  comp_off_delta: number;
  weekly_off_delta: number;
  leave_delta: number;
  counts_as_work_day: boolean;
  note: string | null;
}

export interface AttendanceRecord {
  id: string;
  user_id: string;
  full_name: string;
  position: string | null;
  work_date: string; // 'YYYY-MM-DD'
  type_code: string;
  type_name: string;
  type_group: string;
  created_at: string;
  updated_at: string | null;
  is_open_day: boolean;
}

export interface AttendanceEditLog {
  id: string;
  record_id: string;
  old_type_code: string | null;
  new_type_code: string | null;
  reason: string;
  edited_at: string;
  work_date: string;
  editor_name: string;
  editor_id: string;
}

export interface DayOffBalance {
  comp_off: number;
  weekly_off: number;
  leave_remaining: number;
}

export interface AttendanceOpenDay {
  work_date: string;
}

// Grid dữ liệu cho bảng chấm công
// key: user_id → map: work_date → AttendanceRecord
export type AttendanceGrid = Record<string, Record<string, AttendanceRecord>>;

// Tổng hợp cuối tháng
export interface MonthSummary {
  [typeCode: string]: number;
  work_days: number;
}

// Màu badge theo loại công
export const TYPE_COLORS: Record<string, string> = {
  HC:     'bg-emerald-500/20 text-emerald-300 border-emerald-500/30',
  NP:     'bg-blue-500/20 text-blue-300 border-blue-500/30',
  OM:     'bg-yellow-500/20 text-yellow-300 border-yellow-500/30',
  HN_HC:  'bg-cyan-500/20 text-cyan-300 border-cyan-500/30',
  HN_KHC: 'bg-teal-500/20 text-teal-300 border-teal-500/30',
  NT:     'bg-slate-500/20 text-slate-300 border-slate-500/30',
  TS:     'bg-pink-500/20 text-pink-300 border-pink-500/30',
  TR:     'bg-violet-500/20 text-violet-300 border-violet-500/30',
  TRV:    'bg-purple-500/20 text-purple-300 border-purple-500/30',
  TYT:    'bg-indigo-500/20 text-indigo-300 border-indigo-500/30',
  NB:     'bg-orange-500/20 text-orange-300 border-orange-500/30',
  NL:     'bg-rose-500/20 text-rose-300 border-rose-500/30',
};

export const TYPE_SHORT: Record<string, string> = {
  HC: 'HC', NP: 'NP', OM: 'OM', HN_HC: 'HH', HN_KHC: 'HK',
  NT: 'NT', TS: 'TS', TR: 'TR', TRV: 'TV', TYT: 'TY', NB: 'NB', NL: 'NL',
};
