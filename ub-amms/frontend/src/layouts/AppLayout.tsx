import { Database, FileClock, LayoutDashboard, LogOut, ShieldCheck, Table2 } from "lucide-react";
import { NavLink, Outlet } from "react-router-dom";
import { useAuthStore } from "../store/auth";

const navigation = [
  { to: "/", label: "ภาพรวม", icon: LayoutDashboard },
  { to: "/mappings", label: "จัดการ Mapping", icon: Table2 },
  { to: "/history", label: "ประวัติการแก้ไข", icon: FileClock },
];

export function AppLayout() {
  const { user, logout } = useAuthStore();
  return (
    <div className="min-h-screen bg-slate-100 text-slate-900">
      <aside className="fixed inset-y-0 left-0 z-20 w-64 bg-slate-950 text-slate-100">
        <div className="flex h-20 items-center gap-3 border-b border-slate-800 px-6">
          <div className="rounded-xl bg-teal-500 p-2"><Database size={24} /></div>
          <div><div className="font-bold">UB-AMMS</div><div className="text-xs text-slate-400">Master Data Center</div></div>
        </div>
        <nav className="space-y-1 p-4">
          {navigation.map(({ to, label, icon: Icon }) => (
            <NavLink
              key={to}
              to={to}
              end={to === "/"}
              className={({ isActive }) =>
                `flex items-center gap-3 rounded-xl px-4 py-3 text-sm transition ${
                  isActive ? "bg-teal-600 text-white" : "text-slate-300 hover:bg-slate-800"
                }`
              }
            >
              <Icon size={18} />{label}
            </NavLink>
          ))}
        </nav>
        <div className="absolute inset-x-4 bottom-4 rounded-xl border border-slate-800 bg-slate-900 p-4">
          <div className="mb-3 flex items-center gap-2 text-sm"><ShieldCheck size={17} className="text-teal-400" />{user?.role}</div>
          <div className="truncate text-xs text-slate-400">{user?.username}</div>
          <button className="mt-3 flex items-center gap-2 text-xs text-rose-300 hover:text-rose-200" onClick={logout}>
            <LogOut size={15} />ออกจากระบบ
          </button>
        </div>
      </aside>
      <main className="ml-64 min-h-screen">
        <header className="flex h-20 items-center justify-between border-b bg-white px-8">
          <div><h1 className="font-semibold">ระบบจัดการข้อมูล Map สิทธิการรักษาพยาบาล</h1><p className="text-xs text-slate-500">สำนักงานสาธารณสุขจังหวัดอุบลราชธานี</p></div>
          <div className="rounded-full bg-emerald-50 px-3 py-1 text-xs font-medium text-emerald-700">● ระบบพร้อมใช้งาน</div>
        </header>
        <div className="p-8"><Outlet /></div>
      </main>
    </div>
  );
}
