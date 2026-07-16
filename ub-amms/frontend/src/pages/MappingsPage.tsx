import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AgGridReact } from "ag-grid-react";
import type { ColDef, CellValueChangedEvent } from "ag-grid-community";
import { Download, Plus, RefreshCw, Search, Send, Upload } from "lucide-react";
import { api } from "../api/client";
import type { Mapping } from "../types";
import { useAuthStore } from "../store/auth";

const sourceHeaders = [
  "namepttype", "rights", "pttype", "stdcode", "pay", "op56", "inscl", "chkshow",
  "instypeold", "rightgroup", "chg18", "income_id", "que_group", "sss_export",
  "j_export", "ins_code", "dept_code_id", "dept_cr_code_id", "dept_code_ip_id",
  "dept_rf_code_id", "dept_rfo_code_id", "pttype_replace", "รหัสผังบัญชีลูกหนี้_OP",
  "รหัสผังบัญชีรายได้_OP", "รหัสผังบัญชีลูกหนี้_IP", "รหัสผังบัญชีรายได้_IP",
  "ชื่อบัญชี OP", "ชื่อบัญชี IP", "หมายเหตุ",
] as const;

const wideColumns = new Set([
  "namepttype", "ชื่อบัญชี OP", "ชื่อบัญชี IP", "หมายเหตุ",
]);

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
    { field: "sequence", headerName: "ลำดับ", width: 90, pinned: "left", editable: false },
    ...sourceHeaders.map((header) => ({
      colId: `source_data.${header}`,
      headerName: header,
      width: wideColumns.has(header) ? 280 : 135,
      minWidth: wideColumns.has(header) ? 200 : 100,
      pinned: header === "namepttype" ? "left" as const : undefined,
      editable: canEdit,
      valueGetter: (params: { data?: Mapping }) => params.data?.source_data?.[header] ?? null,
      valueSetter: (params: { data: Mapping; newValue: string | number | null }) => {
        params.data.source_data = { ...(params.data.source_data ?? {}), [header]: params.newValue };
        return true;
      },
    })),
    { field: "status", headerName: "Workflow", width: 130, editable: false, pinned: "right" },
    { field: "version", headerName: "Version", width: 100, editable: false, pinned: "right" },
  ], [canEdit]);

  async function cellChanged(event: CellValueChangedEvent<Mapping>) {
    if (!event.data || event.oldValue === event.newValue) return;
    try {
      const item = event.data;
      const sourceField = event.colDef.colId?.startsWith("source_data.");
      const { data } = await api.put(`/mappings/${item.id}`, {
        ...(sourceField
          ? { source_data: item.source_data }
          : { [event.colDef.field!]: event.newValue }),
        version: item.version,
      });
      event.node.setData(data);
    } catch {
      const sourceKey = event.colDef.colId?.replace("source_data.", "");
      if (sourceKey && event.data.source_data) {
        event.data.source_data = { ...event.data.source_data, [sourceKey]: event.oldValue };
        event.node.setData({ ...event.data });
      } else if (event.colDef.field) {
        event.node.setDataValue(event.colDef.field, event.oldValue);
      }
      alert("บันทึกไม่สำเร็จ กรุณารีเฟรชข้อมูลและลองใหม่");
    }
  }

  async function createRow() {
    const today = new Date().toISOString().slice(0, 10);
    const source_data: Record<string, string | number | null> = Object.fromEntries(
      sourceHeaders.map((header) => [header, null]),
    );
    source_data.namepttype = "รายการใหม่";
    source_data.pttype = `NEW-${Date.now()}`;
    source_data.rights = "SHOW";
    source_data.chkshow = "1";
    source_data["หมายเหตุ"] = "มีใช้";
    const { data } = await api.post("/mappings", {
      sequence: rows.length + 1,
      benefit_code: source_data.pttype,
      benefit_name: "รายการใหม่",
      account_code: `UNMAPPED:${source_data.pttype}`,
      account_name: "กรุณาระบุชื่อบัญชี",
      effective_date: today,
      source_sheet: "Blueprint_โพธิ์ไทร",
      source_row: rows.length + 2,
      source_data,
    });
    setRows((current) => [...current, data]);
  }

  async function importFile(file: File) {
    const form = new FormData();
    form.append("file", file);
    const { data } = await api.post("/import", form);
    alert(`นำเข้าสำเร็จ ${data.record_count} รายการ (เพิ่ม ${data.inserted}, อัปเดต ${data.updated})`);
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
