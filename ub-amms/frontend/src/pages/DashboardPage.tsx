import { useEffect, useState } from "react";
import { AlertTriangle, BookOpenCheck, CheckCircle2, ClipboardList, GitBranch, Layers3, ShieldAlert } from "lucide-react";
import { api } from "../api/client";
import type { DashboardStats } from "../types";

const initial: DashboardStats = { mappings: 0, benefits: 0, account_codes: 0, duplicates: 0, validation_errors: 0, pending_approval: 0, latest_version: 0, recent_activity: [] };

export function DashboardPage() {
  const [stats, setStats] = useState(initial);
  useEffect(() => { api.get("/dashboard").then(({ data }) => setStats(data)); }, []);
  const cards = [
    ["Mapping ทั้งหมด", stats.mappings, Layers3, "bg-teal-50 text-teal-600"],
    ["จำนวนสิทธิ", stats.benefits, BookOpenCheck, "bg-blue-50 text-blue-600"],
    ["รหัสบัญชี", stats.account_codes, ClipboardList, "bg-indigo-50 text-indigo-600"],
    ["ข้อมูลซ้ำ", stats.duplicates, AlertTriangle, "bg-amber-50 text-amber-600"],
    ["Validation Error", stats.validation_errors, ShieldAlert, "bg-rose-50 text-rose-600"],
    ["รออนุมัติ", stats.pending_approval, CheckCircle2, "bg-violet-50 text-violet-600"],
    ["Version ล่าสุด", stats.latest_version, GitBranch, "bg-slate-100 text-slate-600"],
  ] as const;
  return (
    <div className="space-y-8">
      <div><h2 className="text-2xl font-bold">Dashboard</h2><p className="mt-1 text-sm text-slate-500">ภาพรวมคุณภาพและสถานะ Master Data</p></div>
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
        {cards.map(([label, value, Icon, colorClass]) => (
          <div key={label} className="rounded-2xl border bg-white p-5 shadow-sm">
            <div className="flex items-start justify-between"><div><p className="text-sm text-slate-500">{label}</p><p className="mt-3 text-3xl font-bold">{value.toLocaleString()}</p></div><div className={`rounded-xl p-3 ${colorClass}`}><Icon size={22} /></div></div>
          </div>
        ))}
      </div>
      <section className="rounded-2xl border bg-white p-6 shadow-sm">
        <h3 className="font-semibold">กิจกรรมล่าสุด</h3>
        <div className="mt-4 divide-y">
          {stats.recent_activity.length === 0 && <p className="py-6 text-center text-sm text-slate-400">ยังไม่มีกิจกรรม</p>}
          {stats.recent_activity.map((item, index) => (
            <div key={`${item.created_at}-${index}`} className="flex items-center justify-between py-3 text-sm">
              <span><b className="text-teal-700">{item.action}</b> · {item.entity_type}</span>
              <time className="text-xs text-slate-400">{new Date(item.created_at).toLocaleString("th-TH")}</time>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
