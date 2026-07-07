# Windows Agent สำหรับ รพ.สต.

ชุดนี้ออกแบบให้ รพ.สต. ใช้งานบน Windows โดยไม่ต้องติดตั้ง Docker

## วิธีใช้แบบง่าย

1. แตกไฟล์โฟลเดอร์ `windows-agent` ไว้ในเครื่อง รพ.สต. เช่น `C:\RPST-Agent`
2. คัดลอก `config.sample.json` เป็น `config.json`
3. แก้ `config.json` ให้ตรงกับหน่วยบริการ
4. ดับเบิลคลิก `run-now.bat` เพื่อทดสอบส่งข้อมูล
5. ถ้าทดสอบผ่าน ให้คลิกขวา `install-daily-task.bat` แล้วเลือก Run as administrator

ระบบจะตั้งเวลาให้ส่งข้อมูลทุกวันเวลา `00:15`

## ค่าใน config.json ที่ต้องแก้

- `FacilityId` รหัสหน่วยบริการ
- `FacilityName` ชื่อ รพ.สต.
- `District` อำเภอ
- `Province` จังหวัด
- `CentralApiUrl` URL API กลางจาก สสจ.
- `JwtSecret` ค่า secret ที่ สสจ. แจกให้
- `DataSourceKind`
  - `sample` ใช้ทดสอบ ไม่อ่านฐานข้อมูลจริง
  - `odbc` อ่านข้อมูลจากฐานผ่าน ODBC
- `OdbcConnectionString` ค่าเชื่อมต่อฐานข้อมูลหน้างาน
- `Sql` ชุดคำสั่ง SQL สำหรับนับยอดสรุป

ใน SQL ให้ใช้ `?` แทนวันที่รายงาน เช่น `WHERE visitdate = ?`
ถ้า query หนึ่งมี `?` หลายตำแหน่ง ระบบจะใส่วันที่เดียวกันให้ทุกตำแหน่ง

## การเชื่อมต่อฐานข้อมูล HOSxP หรือ MySQL

แนวทางที่ง่ายสำหรับ Windows คือใช้ ODBC:

1. ติดตั้ง MySQL ODBC Driver บนเครื่อง รพ.สต.
2. เปิด ODBC Data Sources แบบ 32-bit หรือ 64-bit ให้ตรงกับ driver
3. สร้าง DSN เช่น `HOSXP`
4. ใช้ user แบบอ่านอย่างเดียว
5. ตั้งค่าใน `config.json`

ตัวอย่าง:

```json
"DataSourceKind": "odbc",
"OdbcConnectionString": "DSN=HOSXP;UID=readonly_user;PWD=readonly_password;"
```

SQL ในไฟล์ตัวอย่างเป็นโครงเริ่มต้น ต้องปรับชื่อ table/field ให้ตรงกับฐานจริงของแต่ละจังหวัดหรือระบบหน้างาน

ตัวอย่างสำหรับ API บน Coolify:

```json
"CentralApiUrl": "http://s14gjbvbsnmq1r2v3ujwh8nu.110.164.222.217.sslip.io/api/v1/etl/summary",
"JwtSecret": "change_this_to_a_long_random_secret",
"JwtIssuer": "rpst-etl",
"JwtAudience": "rpst-central-api"
```

SQL กลุ่ม `Disease...` ใช้เติมกราฟกลุ่มโรคสำคัญใน dashboard ถ้ายังไม่พร้อมสามารถปล่อยไว้ได้ ระบบจะส่งค่าเป็น `0` สำหรับ query ที่ไม่มีใน config

## การดูผลลัพธ์

ไฟล์ log อยู่ในโฟลเดอร์ `logs`

- ถ้าส่งสำเร็จ จะเห็นข้อความ `Sent successfully`
- ถ้าส่งไม่สำเร็จ จะมีข้อความ `ERROR`

## การยกเลิกตั้งเวลา

ดับเบิลคลิก `uninstall-daily-task.bat`

## สิ่งที่ควรทำในระบบจริง

- ให้ สสจ. สร้าง `config.json` แยกให้ครบ 90 แห่ง เพื่อลดงานของ รพ.สต.
- ใช้บัญชีฐานข้อมูลแบบ read-only
- เปิดสิทธิ์ firewall เฉพาะออกไปยัง API กลาง
- ทดสอบ 2-3 แห่งก่อน แล้วค่อยกระจายครบทุกแห่ง
