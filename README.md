# RPST Mini Data Warehouse

ระบบต้นแบบสำหรับรวบรวมข้อมูลสรุปจาก รพ.สต. หลายแห่งเข้าสู่ฐานข้อมูลกลาง แล้วให้ Dashboard ดึงข้อมูลจากฐานกลางแทนการยิง query ไปยังแต่ละ รพ.สต. แบบ real-time

## โครงสร้าง

- `central-db` ฐานข้อมูล PostgreSQL กลาง
- `central-api` API สำหรับรับข้อมูล ETL และให้ Dashboard อ่านข้อมูล
- `windows-agent` ชุดส่งข้อมูลสำหรับ รพ.สต. ที่ใช้ Windows และไม่ต้องใช้ Docker
- `etl-agent` ตัวอย่าง ETL แบบ Docker สำหรับทีมเทคนิคหรือทดสอบใน lab
- `dashboard` หน้าเว็บอ่านข้อมูลภาพรวมจาก API กลาง

## เริ่มใช้งานแบบทดสอบ

1. แก้ค่า `JWT_SECRET` ใน `docker-compose.yml` ให้เป็นค่ายาวและสุ่มจริง
2. เปิดระบบกลาง

```powershell
docker compose up -d --build central-db central-api dashboard
```

3. ส่งข้อมูลตัวอย่างจาก ETL agent

```powershell
docker compose --profile etl-sample run --rm etl-agent-sample
```

4. เปิด Dashboard ที่ `http://localhost:8088`

## API หลัก

### รับข้อมูลสรุปจาก รพ.สต.

`POST /api/v1/etl/summary`

ต้องมี header:

```http
Authorization: Bearer <JWT>
Content-Type: application/json
```

ตัวอย่าง payload:

```json
{
  "facility_id": "10001",
  "facility_name": "รพ.สต. ตัวอย่าง",
  "district": "เมือง",
  "province": "จังหวัดตัวอย่าง",
  "report_date": "2026-07-05",
  "total_visits": 120,
  "unique_patients": 98,
  "chronic_followups": 24,
  "ncd_dm_patients": 18,
  "ncd_ht_patients": 22,
  "ncd_dm_ht_patients": 31,
  "ncd_bp_screened": 80,
  "ncd_fbs_screened": 25,
  "missing_diagnosis": 4,
  "anc_visits": 6,
  "vaccine_visits": 18,
  "home_visits": 9,
  "refer_out": 3,
  "emergency_cases": 1,
  "source_generated_at": "2026-07-06T00:05:00Z",
  "payload": {
    "schema_version": "1.0"
  }
}
```

### อ่านภาพรวม Dashboard

- `GET /api/v1/dashboard/overview`
- `GET /api/v1/dashboard/overview?report_date=2026-07-05`
- `GET /api/v1/facilities`

## ถ้าเคยเปิดฐานข้อมูลกลางก่อนเพิ่ม NCD

ถ้ามี volume PostgreSQL เดิมอยู่แล้ว ให้รัน migration นี้หนึ่งครั้ง:

```powershell
docker compose exec central-db psql -U rpst -d rpst_dw -f /migrations/002_add_ncd_metrics.sql
```

## การติดตั้ง ETL ที่แต่ละ รพ.สต.

ถ้า รพ.สต. ใช้ Windows และไม่มีทีมดูแล Docker ให้ใช้โฟลเดอร์ `windows-agent` แทน:

1. คัดลอกโฟลเดอร์ `windows-agent` ไปที่เครื่อง รพ.สต.
2. คัดลอก `config.sample.json` เป็น `config.json`
3. แก้รหัสหน่วยบริการ, URL API กลาง, secret และค่า ODBC
4. ดับเบิลคลิก `run-now.bat` เพื่อทดสอบ
5. คลิกขวา `install-daily-task.bat` แล้วเลือก Run as administrator เพื่อตั้งเวลาส่งทุกคืน

ดูรายละเอียดที่ `windows-agent/README-WINDOWS.md`

ถ้ายังไม่รู้ว่าต้องดึงอะไรจาก `jhcisdb` ให้เริ่มจากเอกสารนี้:

- `docs/JHCIS-MAPPING.md`
- `docs/jhcis-discovery.sql`
- `docs/jhcis-phase1-config-template.json`

ถ้าทีมเทคนิคต้องการรันผ่าน Docker ยังใช้โฟลเดอร์ `etl-agent` ได้ โดยตั้งค่า `.env` ต่อหน่วยบริการ:

```text
FACILITY_ID=10001
FACILITY_NAME=รพ.สต. ตัวอย่าง
DISTRICT=เมือง
PROVINCE=จังหวัดตัวอย่าง
CENTRAL_API_URL=https://central.example.go.th/api/v1/etl/summary
JWT_SECRET=ใช้ค่าเดียวกับ central-api
JWT_ISSUER=rpst-etl
JWT_AUDIENCE=rpst-central-api
LOCAL_DB_KIND=sqlite
LOCAL_DB_DSN=/app/sample_hosp.sqlite
```

สำหรับระบบจริงให้แทนที่ฟังก์ชัน `aggregate_sqlite` ใน `etl-agent/src/run_etl.py` ด้วย query จากฐานข้อมูลหน้างาน เช่น HOSxP/MySQL หรือ PostgreSQL แล้วตั้งเวลาให้รันตอนเที่ยงคืนผ่าน cron, Windows Task Scheduler หรือ scheduler ของ container platform

## แนวทาง production

- วาง `central-api` หลัง reverse proxy ที่เปิด HTTPS เท่านั้น
- ใช้ secret แยกตามจังหวัด และหมุน secret ตามรอบ
- จำกัด IP ต้นทางหรือ VPN สำหรับ traffic จาก รพ.สต.
- เก็บเฉพาะ aggregated data ไม่ส่งข้อมูลส่วนบุคคลเข้าฐานกลางถ้าไม่จำเป็น
- เพิ่มตาราง audit log และ dead-letter queue สำหรับ payload ที่ส่งไม่สำเร็จ
- สำรอง PostgreSQL เป็นรายวัน และทดสอบ restore เป็นระยะ
