# UB-AMMS

Ubon Account Mapping Management System เป็นระบบ Master Data กลางสำหรับบริหารการ Map
สิทธิการรักษาพยาบาลกับผังบัญชี สป.สธ. ข้อมูลจริงอยู่ในฐานข้อมูล ส่วน Excel เป็นช่องทาง
นำเข้าและส่งออกเท่านั้น

## สิ่งที่พร้อมใน Production Foundation

- FastAPI, SQLAlchemy 2, Alembic และ Pydantic
- SQLite สำหรับพัฒนา และ MariaDB สำหรับ production
- JWT authentication และ RBAC: `viewer`, `editor`, `approver`, `super_admin`
- Mapping CRUD, search, pagination, soft delete และ optimistic versioning
- Validation ก่อน workflow และ unique business key ในฐานข้อมูล
- Audit Log เก็บ user, เวลา, ค่าเดิม/ใหม่, IP และ browser
- Workflow: Draft → Submit → Approve → Publish
- Logical backup อัตโนมัติก่อนแก้ไข และ restore พร้อม safety backup
- Import/Export `.xlsx` ด้วย openpyxl
- React 19, TypeScript, Tailwind CSS และ AG Grid
- Docker Compose สำหรับ MariaDB + Backend + Nginx/Frontend

## เริ่มใช้งานบน Windows (Development)

Backend:

```powershell
cd backend
Copy-Item .env.example .env
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
alembic upgrade head
uvicorn app.main:app --reload
```

Frontend (เปิด PowerShell อีกหน้าต่าง):

```powershell
cd frontend
npm install
npm run dev
```

เปิด `http://localhost:5173` และเข้าสู่ระบบด้วยค่า `INITIAL_ADMIN_USERNAME` /
`INITIAL_ADMIN_PASSWORD` ใน `backend/.env` จากนั้นเปลี่ยนรหัสผ่านเริ่มต้นก่อนนำข้อมูลจริงเข้า
ระบบ API docs อยู่ที่ `http://localhost:8000/api/docs`

## Deploy ด้วย Docker บน Ubuntu 24

```bash
cp .env.production.example .env
# แก้ secret/password/domain ทุกค่าใน .env
docker compose up -d --build
docker compose ps
```

ให้วาง reverse proxy ที่เปิด HTTPS หน้า port `8080` และปิดการเข้าถึง MariaDB จากภายนอก
ระบบจะรัน Alembic migration ก่อนเริ่ม FastAPI ทุกครั้ง

## Excel Contract

ไฟล์นำเข้าต้องเป็น `.xlsx` และมีหัวคอลัมน์อย่างน้อย:

`ลำดับ`, `รหัสสิทธิ`, `ชื่อสิทธิ`, `รหัสบัญชี`, `ชื่อบัญชี`

คอลัมน์เสริมคือ `รายละเอียด`, `วันที่เริ่มใช้`, `วันที่สิ้นสุด`, `สถานะ`

การทำให้รูปแบบเหมือนไฟล์ต้นฉบับ 100% ต้องนำไฟล์ Excel ต้นฉบับจริงมาเก็บเป็น template
จากนั้นกำหนด sheet, merged cells, styles, formulas, print area และตำแหน่งข้อมูลใน
import/export profile เพิ่มเติม โดย engine ปัจจุบันทำ data round-trip และรูปแบบมาตรฐานแล้ว

## API หลัก

- `POST /api/v1/auth/login`
- `GET /api/v1/dashboard`
- `GET|POST /api/v1/mappings`
- `GET /api/v1/master-data/mappings` (อ่านเฉพาะข้อมูล Publish ที่มีผล ณ วันที่ระบุ)
- `PUT|DELETE /api/v1/mappings/{id}`
- `POST /api/v1/import`
- `GET /api/v1/export`
- `POST /api/v1/workflow`
- `GET /api/v1/history`
- `GET|POST /api/v1/backups`, `POST /api/v1/backup`
- `POST /api/v1/restore`

ดูแบบฐานข้อมูลที่ [docs/ER-DIAGRAM.md](docs/ER-DIAGRAM.md)

## งานถัดไปก่อน UAT

1. รับไฟล์ Excel ต้นฉบับและล็อก data dictionary/business rules อย่างเป็นทางการ
2. เพิ่มหน้าจอ User Management, Approval Inbox, Backup/Restore และรายงาน PDF/CSV
3. เพิ่ม batch edit/delete, paste matrix, server-side AG Grid และ validation profile
4. เพิ่ม refresh token/revocation, password policy, rate limiting และ secret management
5. เพิ่ม unit/integration/E2E tests, MariaDB restore drill และ security scan
6. จัดทำ Windows installer/service wrapper และ systemd/Nginx/HTTPS installer สำหรับ Ubuntu
