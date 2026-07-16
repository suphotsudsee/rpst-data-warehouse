import { FormEvent, useState } from "react";
import { Database } from "lucide-react";
import { Navigate, useNavigate } from "react-router-dom";
import { useAuthStore } from "../store/auth";

export function LoginPage() {
  const { user, login, loading } = useAuthStore();
  const navigate = useNavigate();
  const [username, setUsername] = useState("admin");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  if (user) return <Navigate to="/" replace />;

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError("");
    try {
      await login(username, password);
      navigate("/");
    } catch {
      setError("ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง");
    }
  }

  return (
    <div className="grid min-h-screen place-items-center bg-slate-950 px-4">
      <div className="w-full max-w-md rounded-3xl bg-white p-8 shadow-2xl">
        <div className="mb-8 flex items-center gap-4">
          <div className="rounded-2xl bg-teal-600 p-3 text-white"><Database size={30} /></div>
          <div><h1 className="text-2xl font-bold">UB-AMMS</h1><p className="text-sm text-slate-500">Ubon Account Mapping Management System</p></div>
        </div>
        <form className="space-y-5" onSubmit={submit}>
          <label className="block text-sm font-medium">ชื่อผู้ใช้
            <input className="mt-2 w-full rounded-xl border border-slate-300 px-4 py-3 outline-none focus:border-teal-600" value={username} onChange={(e) => setUsername(e.target.value)} required />
          </label>
          <label className="block text-sm font-medium">รหัสผ่าน
            <input className="mt-2 w-full rounded-xl border border-slate-300 px-4 py-3 outline-none focus:border-teal-600" type="password" value={password} onChange={(e) => setPassword(e.target.value)} required />
          </label>
          {error && <p className="rounded-lg bg-rose-50 p-3 text-sm text-rose-700">{error}</p>}
          <button disabled={loading} className="w-full rounded-xl bg-teal-600 py-3 font-semibold text-white hover:bg-teal-700 disabled:opacity-60">
            {loading ? "กำลังเข้าสู่ระบบ..." : "เข้าสู่ระบบ"}
          </button>
        </form>
      </div>
    </div>
  );
}
