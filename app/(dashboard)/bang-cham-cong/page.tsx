import { createClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import { AppUser } from '@/types';
import BangChamCongClient from './BangChamCongClient';
import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Bảng Chấm Công | Hệ Thống Chấm Công',
};

export default async function BangChamCongPage() {
  const supabase = await createClient();
  const { data: { user: authUser } } = await supabase.auth.getUser();
  if (!authUser) redirect('/login');

  const { data: appUser } = await supabase
    .from('users')
    .select('*')
    .eq('auth_id', authUser.id)
    .single();

  if (!appUser) redirect('/login');

  return <BangChamCongClient user={appUser as AppUser} />;
}
