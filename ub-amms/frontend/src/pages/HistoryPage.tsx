import { useEffect, useState } from "react";
import { api } from "../api/client";

interface Audit {
  id: string;
  action: string;
  entity_type: string;
  entity_id: string | null;
  user_id: string | null;
  ip_address: string | null;
  created_at: string;
}

export function HistoryPage() {
  const [items, setItems] = useState<Audit[]>([]);
  useEffect(() => { api.get("/history").then(({ data }) => setItems(data)); }, []);
  return (
    <div className="space-y-5">
      <div><h2 className="text-2xl font-bold">Audit Log</h2><p className="mt-1 text-sm text-slate-500">ประวัติการเปลี่ยนแปลงข้อมูลและกิจกรรมสำคัญ</p></div>
      <div className="overflow-hidden rounded-2xl border bg-white">
        <table className="w-full text-left text-sm">
          <thead className="bg-slate-50 text-xs uppercase text-slate-500"><tr><th className="p-4">เวลา</th><th>Action</th><th>ประเภท</th><th>Entity ID</th><th>User</th><th>IP</th></tr></thead>
          <tbody className="divide-y">{items.map((item) => <tr key={item.id} className="hover:bg-slate-50"><td className="p-4">{new Date(item.created_at).toLocaleString("th-TH")}</td><td className="font-medium text-teal-700">{item.action}</td><td>{item.entity_type}</td><td className="font-mono text-xs">{item.entity_id ?? "-"}</td><td className="font-mono text-xs">{item.user_id ?? "-"}</td><td>{item.ip_address ?? "-"}</td></tr>)}</tbody>
        </table>
      </div>
    </div>
  );
}
