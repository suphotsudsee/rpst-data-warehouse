import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AgGridReact } from "ag-grid-react";
import type { ColDef, CellValueChangedEvent } from "ag-grid-community";
import { Download, Plus, RefreshCw, Search, Send, Upload } from "lucide-react";
import { api } from "../api/client";
import type { Mapping } from "../types";
import { useAuthStore } from "../store/auth";

export function MappingsPage() {
  const [rows, setRows] = useState<Mapping[]>([]);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const user = useAuthStore((state) => state.user);
  const canEdit = user?.role !== "viewer";

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const { data } = await api.get("/mappings", { params: { search: search || undefined, page_size: 500 } });
      setRows(data.items);
    } finally { setLoading(false); }
  }, [search]);
  useEffect(() => { void load(); }, [load]);

  const columns = useMemo<ColDef<Mapping>[]>(() => [
    { field: "sequence", headerName: "ลำดับ", width: 90, pinned: "left", editable: canEdit },
    { field: "benefit_code", headerName: "รหัสสิทธิ", width: 145, pinned: "left", editable: canEdit },
    { field: "benefit_name", headerName: "ชื่อสิทธิ", minWidth: 220, flex: 1, editable: canEdit },
    { field: "account_code", headerName: "รหัสบัญชี", width: 150, editable: canEdit },
    { field: "account_name", headerName: "ชื่อบัญชี", minWidth: 240, flex: 1, editable: canEdit },
    { field: "effective_date", headerName: "วันที่เริ่มใช้", width: 145, editable: canEdit },
    { field: "expiry_date", headerName: "วันที่สิ้นสุด", width: 145, editable: canEdit },
    { field: "status", headerName: "สถานะ", width: 130, editable: false },
    { field: "version", headerName: "Version", width: 100, editable: false },
  ], [canEdit]);

  async function cellChanged(event: CellValueChangedEvent<Mapping>) {
    if (!event.data || event.oldValue === event.newValue) return;
    try {
      const item = event.data;
      const { data } = await api.put(`/mappings/${item.id}`, {
        [event.colDef.field!]: event.newValue,
        version: item.version,
      });
      event.node.setData(data);
    } catch {
      event.node.setDataValue(event.colDef.field!, event.oldValue);
      alert("บันทึกไม่สำเร็จ กรุณารีเฟรชข้อมูลและลองใหม่");
    }
  }

  async function createRow() {
    const today = new Date().toISOString().slice(0, 10);
    const { data } = await api.post("/mappings", {
      sequence: rows.length + 1,
      benefit_code: "NEW",
      benefit_name: "รายการใหม่",
      account_code: "NEW",
      account_name: "กรุณาระบุชื่อบัญชี",
      effective_date: today,
    });
    setRows((current) => [...current, data]);
  }

  async function importFile(file: File) {
    const form = new FormData();
    form.append("file", file);
    await api.post("/import", form);
    await load();
  }

  async function exportFile() {
    const response = await api.get("/export", { responseType: "blob" });
    const url = URL.createObjectURL(response.data);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = "ub-amms-mappings.xlsx";
    anchor.click();
    URL.revokeObjectURL(url);
  }

  async function submitDrafts() {
    const ids = rows.filter((item) => item.status === "draft").map((item) => item.id);
    if (!ids.length) return;
    await api.post("/workflow", { mapping_ids: ids, action: "submit" });
    await load();
  }

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div><h2 className="text-2xl font-bold">Mapping Management</h2><p className="mt-1 text-sm text-slate-500">แก้ไขข้อมูลแบบตาราง พร้อมบันทึก Audit และ Version อัตโนมัติ</p></div>
        <div className="flex flex-wrap gap-2">
          {canEdit && <button onClick={createRow} className="flex items-center gap-2 rounded-xl bg-teal-600 px-4 py-2 text-sm font-medium text-white"><Plus size={17} />เพิ่มรายการ</button>}
          {canEdit && <button onClick={() => fileRef.current?.click()} className="flex items-center gap-2 rounded-xl border bg-white px-4 py-2 text-sm"><Upload size={17} />นำเข้า Excel</button>}
          <input ref={fileRef} type="file" accept=".xlsx" className="hidden" onChange={(e) => e.target.files?.[0] && void importFile(e.target.files[0])} />
          <button onClick={exportFile} className="flex items-center gap-2 rounded-xl border bg-white px-4 py-2 text-sm"><Download size={17} />ส่งออก Excel</button>
          {canEdit && <button onClick={submitDrafts} className="flex items-center gap-2 rounded-xl border border-violet-200 bg-violet-50 px-4 py-2 text-sm text-violet-700"><Send size={17} />ส่งอนุมัติ</button>}
        </div>
      </div>
      <div className="flex items-center gap-3 rounded-2xl border bg-white p-3">
        <Search size={18} className="text-slate-400" />
        <input value={search} onChange={(e) => setSearch(e.target.value)} className="flex-1 outline-none" placeholder="ค้นหารหัสสิทธิ ชื่อสิทธิ รหัสบัญชี หรือชื่อบัญชี..." />
        <button onClick={load} className="rounded-lg p-2 hover:bg-slate-100" title="รีเฟรช"><RefreshCw size={17} className={loading ? "animate-spin" : ""} /></button>
      </div>
      <div className="ag-theme-quartz h-[calc(100vh-280px)] min-h-[500px] overflow-hidden rounded-2xl border bg-white">
        <AgGridReact<Mapping>
          rowData={rows}
          columnDefs={columns}
          defaultColDef={{ sortable: true, filter: true, resizable: true }}
          rowSelection={{ mode: "multiRow" }}
          undoRedoCellEditing
          undoRedoCellEditingLimit={20}
          onCellValueChanged={cellChanged}
          getRowId={(params) => params.data.id}
        />
      </div>
    </div>
  );
}
