import { redirect } from 'next/navigation';

// Trang / redirect thẳng vào dashboard
export default function RootPage() {
  redirect('/bang-cham-cong');
}
