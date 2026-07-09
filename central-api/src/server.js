import cors from "cors";
import express from "express";
import helmet from "helmet";
import { z } from "zod";
import { requireAdminToken, requireEtlToken } from "./auth.js";
import { ensureSchema, pool, query } from "./db.js";

const app = express();
const port = Number(process.env.PORT || 8080);

app.use(helmet());
app.use(cors({ origin: process.env.CORS_ORIGIN || "*" }));
app.use(express.json({ limit: "5mb" }));

const summarySchema = z.object({
  facility_id: z.string().min(1).max(20),
  facility_name: z.string().min(1).max(255),
  subdistrict: z.string().max(255).optional().nullable(),
  district: z.string().max(255).optional().nullable(),
  province: z.string().max(255).optional().nullable(),
  report_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  total_visits: z.number().int().nonnegative().default(0),
  unique_patients: z.number().int().nonnegative().default(0),
  chronic_followups: z.number().int().nonnegative().default(0),
  ncd_dm_patients: z.number().int().nonnegative().default(0),
  ncd_ht_patients: z.number().int().nonnegative().default(0),
  ncd_dm_ht_patients: z.number().int().nonnegative().default(0),
  ncd_bp_screened: z.number().int().nonnegative().default(0),
  ncd_fbs_screened: z.number().int().nonnegative().default(0),
  missing_diagnosis: z.number().int().nonnegative().default(0),
  anc_visits: z.number().int().nonnegative().default(0),
  vaccine_visits: z.number().int().nonnegative().default(0),
  home_visits: z.number().int().nonnegative().default(0),
  refer_out: z.number().int().nonnegative().default(0),
  emergency_cases: z.number().int().nonnegative().default(0),
  source_generated_at: z.string().datetime(),
  payload: z.record(z.unknown()).default({})
});

const locationItemSchema = z.object({
  patient_hash: z.string().min(16).max(128),
  disease_group: z.string().min(1).max(50),
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  payload: z.record(z.unknown()).default({})
});

const locationsSchema = z.object({
  facility_id: z.string().min(1).max(20),
  report_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  source_generated_at: z.string().datetime(),
  locations: z.array(locationItemSchema).max(10000).default([])
});

app.get("/health", async (_req, res) => {
  try {
    await query("SELECT 1");
    res.json({ status: "ok" });
  } catch {
    res.status(503).json({ status: "database_unavailable" });
  }
});

app.post("/api/v1/etl/summary", requireEtlToken, async (req, res) => {
  const parsed = summarySchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: "invalid_payload", details: parsed.error.flatten() });
  }

  const data = parsed.data;
  if (req.etl.facility_id !== data.facility_id) {
    return res.status(403).json({ error: "facility_token_mismatch" });
  }

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(
      `INSERT INTO facilities (facility_id, facility_name, subdistrict, district, province, updated_at)
       VALUES ($1, $2, $3, $4, $5, NOW())
       ON CONFLICT (facility_id) DO UPDATE SET
         facility_name = EXCLUDED.facility_name,
         subdistrict = EXCLUDED.subdistrict,
         district = EXCLUDED.district,
         province = EXCLUDED.province,
         updated_at = NOW()`,
      [data.facility_id, data.facility_name, data.subdistrict || null, data.district || null, data.province || null]
    );

    const result = await client.query(
      `INSERT INTO facility_daily_summaries (
         facility_id, report_date, total_visits, unique_patients,
         chronic_followups, ncd_dm_patients, ncd_ht_patients, ncd_dm_ht_patients,
         ncd_bp_screened, ncd_fbs_screened, missing_diagnosis,
         anc_visits, vaccine_visits, home_visits, refer_out, emergency_cases,
         source_generated_at, payload
       )
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)
       ON CONFLICT (facility_id, report_date) DO UPDATE SET
         total_visits = EXCLUDED.total_visits,
         unique_patients = EXCLUDED.unique_patients,
         chronic_followups = EXCLUDED.chronic_followups,
         ncd_dm_patients = EXCLUDED.ncd_dm_patients,
         ncd_ht_patients = EXCLUDED.ncd_ht_patients,
         ncd_dm_ht_patients = EXCLUDED.ncd_dm_ht_patients,
         ncd_bp_screened = EXCLUDED.ncd_bp_screened,
         ncd_fbs_screened = EXCLUDED.ncd_fbs_screened,
         missing_diagnosis = EXCLUDED.missing_diagnosis,
         anc_visits = EXCLUDED.anc_visits,
         vaccine_visits = EXCLUDED.vaccine_visits,
         home_visits = EXCLUDED.home_visits,
         refer_out = EXCLUDED.refer_out,
         emergency_cases = EXCLUDED.emergency_cases,
         source_generated_at = EXCLUDED.source_generated_at,
         payload = EXCLUDED.payload,
         received_at = NOW()
       RETURNING id`,
      [
        data.facility_id,
        data.report_date,
        data.total_visits,
        data.unique_patients,
        data.chronic_followups,
        data.ncd_dm_patients,
        data.ncd_ht_patients,
        data.ncd_dm_ht_patients,
        data.ncd_bp_screened,
        data.ncd_fbs_screened,
        data.missing_diagnosis,
        data.anc_visits,
        data.vaccine_visits,
        data.home_visits,
        data.refer_out,
        data.emergency_cases,
        data.source_generated_at,
        data.payload
      ]
    );
    await client.query("COMMIT");
    return res.status(202).json({ status: "accepted", summary_id: result.rows[0].id });
  } catch (error) {
    await client.query("ROLLBACK");
    console.error("Failed to store ETL summary", {
      facility_id: data.facility_id,
      report_date: data.report_date,
      error: error.message,
      code: error.code
    });
    return res.status(500).json({ error: "store_failed" });
  } finally {
    client.release();
  }
});

app.post("/api/v1/etl/ncd-house-locations", requireEtlToken, async (req, res) => {
  const parsed = locationsSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: "invalid_payload", details: parsed.error.flatten() });
  }

  const data = parsed.data;
  if (req.etl.facility_id !== data.facility_id) {
    return res.status(403).json({ error: "facility_token_mismatch" });
  }

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(
      `DELETE FROM ncd_house_locations
       WHERE facility_id = $1
         AND report_date = $2`,
      [data.facility_id, data.report_date]
    );

    for (const item of data.locations) {
      await client.query(
        `INSERT INTO ncd_house_locations (
           facility_id, report_date, patient_hash, disease_group,
           latitude, longitude, source_generated_at, payload
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (facility_id, report_date, patient_hash, disease_group) DO UPDATE SET
           latitude = EXCLUDED.latitude,
           longitude = EXCLUDED.longitude,
           source_generated_at = EXCLUDED.source_generated_at,
           payload = EXCLUDED.payload,
           received_at = NOW()`,
        [
          data.facility_id,
          data.report_date,
          item.patient_hash,
          item.disease_group,
          item.latitude,
          item.longitude,
          data.source_generated_at,
          item.payload
        ]
      );
    }

    await client.query("COMMIT");
    return res.status(202).json({ status: "accepted", locations: data.locations.length });
  } catch (error) {
    await client.query("ROLLBACK");
    console.error("Failed to store NCD house locations", {
      facility_id: data.facility_id,
      report_date: data.report_date,
      error: error.message,
      code: error.code
    });
    return res.status(500).json({ error: "store_failed" });
  } finally {
    client.release();
  }
});

app.get("/api/v1/facilities", async (_req, res) => {
  const result = await query(
    `SELECT facility_id, facility_name, subdistrict, district, province, is_active, updated_at
     FROM facilities
     ORDER BY facility_name`
  );
  res.json({ data: result.rows });
});

app.get("/api/v1/admin/facility-data", requireAdminToken, async (_req, res) => {
  const result = await query(
    `WITH summary_totals AS (
       SELECT
         facility_id,
         COUNT(DISTINCT report_date)::int AS summary_days,
         COALESCE(SUM(total_visits), 0)::int AS total_visits,
         COALESCE(SUM(ncd_dm_ht_patients), 0)::int AS ncd_dm_ht_patients,
         MIN(report_date) AS first_report_date,
         MAX(report_date) AS last_report_date,
         MAX(received_at) AS summary_received_at
       FROM facility_daily_summaries
       GROUP BY facility_id
     ),
     location_totals AS (
       SELECT
         facility_id,
         COUNT(*)::int AS location_records,
         MAX(received_at) AS location_received_at
       FROM ncd_house_locations
       GROUP BY facility_id
     )
     SELECT
       f.facility_id,
       f.facility_name,
       f.subdistrict,
       f.district,
       f.province,
       COALESCE(s.summary_days, 0)::int AS summary_days,
       COALESCE(s.total_visits, 0)::int AS total_visits,
       COALESCE(s.ncd_dm_ht_patients, 0)::int AS ncd_dm_ht_patients,
       COALESCE(l.location_records, 0)::int AS location_records,
       s.first_report_date,
       s.last_report_date,
       GREATEST(
         COALESCE(s.summary_received_at, 'epoch'::timestamptz),
         COALESCE(l.location_received_at, 'epoch'::timestamptz)
       ) AS last_received_at
     FROM facilities f
     LEFT JOIN summary_totals s ON s.facility_id = f.facility_id
     LEFT JOIN location_totals l ON l.facility_id = f.facility_id
     ORDER BY f.facility_id`
  );

  res.json({ data: result.rows });
});

app.delete("/api/v1/admin/facility-data/:facility_id", requireAdminToken, async (req, res) => {
  const facilityId = req.params.facility_id;
  const deleteFacility = req.query.delete_facility === "true";
  if (!facilityId || facilityId.length > 20) {
    return res.status(400).json({ error: "invalid_facility_id" });
  }

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const locations = await client.query(
      "DELETE FROM ncd_house_locations WHERE facility_id = $1 RETURNING id",
      [facilityId]
    );
    const summaries = await client.query(
      "DELETE FROM facility_daily_summaries WHERE facility_id = $1 RETURNING id",
      [facilityId]
    );
    let facilities = { rowCount: 0 };
    if (deleteFacility) {
      facilities = await client.query(
        "DELETE FROM facilities WHERE facility_id = $1 RETURNING facility_id",
        [facilityId]
      );
    }
    await client.query("COMMIT");
    res.json({
      status: "deleted",
      facility_id: facilityId,
      summaries_deleted: summaries.rowCount,
      locations_deleted: locations.rowCount,
      facility_deleted: facilities.rowCount
    });
  } catch (error) {
    await client.query("ROLLBACK");
    console.error("Failed to delete facility data", {
      facility_id: facilityId,
      error: error.message,
      code: error.code
    });
    res.status(500).json({ error: "delete_failed" });
  } finally {
    client.release();
  }
});

app.get("/api/v1/dashboard/overview", async (req, res) => {
  const reportDate = typeof req.query.report_date === "string" ? req.query.report_date : null;
  const joinDate = reportDate ? "AND s.report_date = $1" : "";
  const params = reportDate ? [reportDate] : [];

  const selected = await query(
    `SELECT DISTINCT ON (f.facility_id)
       f.facility_id, f.facility_name, f.subdistrict, f.district, f.province,
       s.report_date, s.total_visits, s.unique_patients, s.chronic_followups,
       s.ncd_dm_patients, s.ncd_ht_patients, s.ncd_dm_ht_patients,
       s.ncd_bp_screened, s.ncd_fbs_screened, s.missing_diagnosis,
       s.anc_visits, s.vaccine_visits, s.home_visits, s.refer_out,
       s.emergency_cases, s.received_at
     FROM facilities f
     LEFT JOIN facility_daily_summaries s
       ON s.facility_id = f.facility_id ${joinDate}
     ORDER BY f.facility_id, s.report_date DESC NULLS LAST`,
    params
  );

  const totals = selected.rows.reduce(
    (acc, row) => {
      acc.facilities_total += 1;
      if (row.report_date) {
        acc.facilities_reported += 1;
      }
      acc.total_visits += Number(row.total_visits || 0);
      acc.unique_patients += Number(row.unique_patients || 0);
      acc.chronic_followups += Number(row.chronic_followups || 0);
      acc.ncd_dm_patients += Number(row.ncd_dm_patients || 0);
      acc.ncd_ht_patients += Number(row.ncd_ht_patients || 0);
      acc.ncd_dm_ht_patients += Number(row.ncd_dm_ht_patients || 0);
      acc.ncd_bp_screened += Number(row.ncd_bp_screened || 0);
      acc.ncd_fbs_screened += Number(row.ncd_fbs_screened || 0);
      acc.missing_diagnosis += Number(row.missing_diagnosis || 0);
      acc.refer_out += Number(row.refer_out || 0);
      acc.emergency_cases += Number(row.emergency_cases || 0);
      return acc;
    },
    {
      facilities_total: 0,
      facilities_reported: 0,
      total_visits: 0,
      unique_patients: 0,
      chronic_followups: 0,
      ncd_dm_patients: 0,
      ncd_ht_patients: 0,
      ncd_dm_ht_patients: 0,
      ncd_bp_screened: 0,
      ncd_fbs_screened: 0,
      missing_diagnosis: 0,
      refer_out: 0,
      emergency_cases: 0
    }
  );

  res.json({
    report_date: reportDate || "latest_per_facility",
    totals,
    facilities: selected.rows
  });
});

app.get("/api/v1/dashboard/trends", async (req, res) => {
  const days = Math.min(Math.max(Number(req.query.days || 1827), 1), 2000);
  const startDate = typeof req.query.start_date === "string" ? req.query.start_date : null;
  const endDate = typeof req.query.end_date === "string" ? req.query.end_date : null;
  const facilityId = typeof req.query.facility_id === "string" && req.query.facility_id ? req.query.facility_id : null;
  const hasRange = Boolean(startDate && endDate);
  const params = hasRange ? [startDate, endDate] : [days];
  const facilityWhere = facilityId ? ` AND facility_id = $${params.push(facilityId)}` : "";
  const result = await query(
    `SELECT
       report_date,
       COALESCE(SUM(total_visits), 0)::int AS total_visits,
       COALESCE(SUM(unique_patients), 0)::int AS unique_patients,
       COALESCE(SUM(chronic_followups), 0)::int AS chronic_followups,
       COALESCE(SUM(ncd_dm_patients), 0)::int AS ncd_dm_patients,
       COALESCE(SUM(ncd_ht_patients), 0)::int AS ncd_ht_patients,
       COALESCE(SUM(ncd_dm_ht_patients), 0)::int AS ncd_dm_ht_patients,
       COALESCE(SUM(ncd_bp_screened), 0)::int AS ncd_bp_screened,
       COALESCE(SUM(ncd_fbs_screened), 0)::int AS ncd_fbs_screened,
       COALESCE(SUM(missing_diagnosis), 0)::int AS missing_diagnosis,
       COALESCE(SUM(anc_visits), 0)::int AS anc_visits,
       COALESCE(SUM(vaccine_visits), 0)::int AS vaccine_visits,
       COALESCE(SUM(home_visits), 0)::int AS home_visits,
       COALESCE(SUM(refer_out), 0)::int AS refer_out,
       COALESCE(SUM(emergency_cases), 0)::int AS emergency_cases
     FROM facility_daily_summaries
     WHERE ${
       hasRange
          ? "report_date BETWEEN $1::date AND $2::date"
          : "report_date >= CURRENT_DATE - ($1::int - 1)"
     }${facilityWhere}
     GROUP BY report_date
     ORDER BY report_date`,
    params
  );

  res.json({ days: hasRange ? null : days, start_date: startDate, end_date: endDate, data: result.rows });
});

app.get("/api/v1/dashboard/facilities/range", async (req, res) => {
  const startDate = typeof req.query.start_date === "string" ? req.query.start_date : null;
  const endDate = typeof req.query.end_date === "string" ? req.query.end_date : null;
  const facilityId = typeof req.query.facility_id === "string" && req.query.facility_id ? req.query.facility_id : null;

  if (!startDate || !endDate) {
    return res.status(400).json({ error: "start_date_and_end_date_required" });
  }

  const params = [startDate, endDate];
  const facilityWhere = facilityId ? `WHERE f.facility_id = $${params.push(facilityId)}` : "";
  const result = await query(
    `SELECT
       f.facility_id,
       f.facility_name,
       f.subdistrict,
       f.district,
       f.province,
       MIN(s.report_date) AS first_report_date,
       MAX(s.report_date) AS last_report_date,
       MAX(s.received_at) AS received_at,
       COUNT(s.report_date)::int AS reported_days,
       COALESCE(SUM(s.total_visits), 0)::int AS total_visits,
       COALESCE(SUM(s.unique_patients), 0)::int AS unique_patients,
       COALESCE(SUM(s.chronic_followups), 0)::int AS chronic_followups,
       COALESCE(SUM(s.ncd_dm_patients), 0)::int AS ncd_dm_patients,
       COALESCE(SUM(s.ncd_ht_patients), 0)::int AS ncd_ht_patients,
       COALESCE(SUM(s.ncd_dm_ht_patients), 0)::int AS ncd_dm_ht_patients,
       COALESCE(SUM(s.ncd_bp_screened), 0)::int AS ncd_bp_screened,
       COALESCE(SUM(s.ncd_fbs_screened), 0)::int AS ncd_fbs_screened,
       COALESCE(SUM(s.missing_diagnosis), 0)::int AS missing_diagnosis,
       COALESCE(SUM(s.anc_visits), 0)::int AS anc_visits,
       COALESCE(SUM(s.vaccine_visits), 0)::int AS vaccine_visits,
       COALESCE(SUM(s.home_visits), 0)::int AS home_visits,
       COALESCE(SUM(s.refer_out), 0)::int AS refer_out,
       COALESCE(SUM(s.emergency_cases), 0)::int AS emergency_cases
     FROM facilities f
     LEFT JOIN facility_daily_summaries s
       ON s.facility_id = f.facility_id
      AND s.report_date BETWEEN $1::date AND $2::date
     ${facilityWhere}
     GROUP BY f.facility_id, f.facility_name, f.subdistrict, f.district, f.province
     ORDER BY total_visits DESC, f.facility_name`,
    params
  );

  res.json({ start_date: startDate, end_date: endDate, facilities: result.rows });
});

app.get("/api/v1/dashboard/disease-groups/range", async (req, res) => {
  const startDate = typeof req.query.start_date === "string" ? req.query.start_date : null;
  const endDate = typeof req.query.end_date === "string" ? req.query.end_date : null;
  const facilityId = typeof req.query.facility_id === "string" && req.query.facility_id ? req.query.facility_id : null;

  if (!startDate || !endDate) {
    return res.status(400).json({ error: "start_date_and_end_date_required" });
  }

  const params = [startDate, endDate];
  const facilityWhere = facilityId ? ` AND s.facility_id = $${params.push(facilityId)}` : "";
  const result = await query(
    `WITH disease_groups AS (
       SELECT
         item.key,
         SUM(CASE WHEN item.value ~ '^[0-9]+$' THEN item.value::int ELSE 0 END)::int AS patients
       FROM facility_daily_summaries s
       CROSS JOIN LATERAL jsonb_each_text(COALESCE(s.payload->'disease_groups', '{}'::jsonb)) AS item(key, value)
       WHERE s.report_date BETWEEN $1::date AND $2::date
       ${facilityWhere}
       GROUP BY item.key
     ),
     column_totals AS (
       SELECT
         COALESCE(SUM(ncd_dm_patients), 0)::int AS diabetes,
         COALESCE(SUM(ncd_ht_patients), 0)::int AS hypertension
       FROM facility_daily_summaries
       WHERE report_date BETWEEN $1::date AND $2::date
       ${facilityId ? ` AND facility_id = $${params.length}` : ""}
     )
     SELECT
       disease_key,
       disease_label,
       CASE
         WHEN labels.disease_key = 'diabetes' THEN GREATEST(COALESCE(disease_groups.patients, 0), column_totals.diabetes)
         WHEN labels.disease_key = 'hypertension' THEN GREATEST(COALESCE(disease_groups.patients, 0), column_totals.hypertension)
         ELSE COALESCE(disease_groups.patients, 0)
       END::int AS patients
     FROM (VALUES
       ('dyslipidemia', 'ไขมันในเลือดสูง', 1),
       ('vaping_lung_injury', 'ปอดอักเสบจากการสูบบุหรี่ไฟฟ้า', 2),
       ('coronary_artery_disease', 'หลอดเลือดหัวใจ', 3),
       ('stroke', 'หลอดเลือดสมอง', 4),
       ('mental_health', 'สุขภาพจิต', 5),
       ('cancer', 'มะเร็งทุกชนิด', 6),
       ('diabetes', 'เบาหวาน', 7),
       ('pertussis', 'ไอควาย', 8),
       ('hypertension', 'ความดันโลหิตสูง', 9),
       ('copd_emphysema', 'ถุงลมโป่งพองเรื้อรัง', 10)
     ) AS labels(disease_key, disease_label, sort_order)
     CROSS JOIN column_totals
     LEFT JOIN disease_groups ON disease_groups.key = labels.disease_key
     ORDER BY labels.sort_order`,
    params
  );

  res.json({ start_date: startDate, end_date: endDate, data: result.rows });
});

app.get("/api/v1/dashboard/pingpong-7color/range", async (req, res) => {
  const startDate = typeof req.query.start_date === "string" ? req.query.start_date : null;
  const endDate = typeof req.query.end_date === "string" ? req.query.end_date : null;
  const facilityId = typeof req.query.facility_id === "string" && req.query.facility_id ? req.query.facility_id : null;

  if (!startDate || !endDate) {
    return res.status(400).json({ error: "start_date_and_end_date_required" });
  }

  const params = [startDate, endDate];
  const facilityWhere = facilityId ? ` AND s.facility_id = $${params.push(facilityId)}` : "";
  const result = await query(
    `WITH pingpong AS (
       SELECT
         item.key,
         SUM(CASE WHEN item.value ~ '^[0-9]+$' THEN item.value::int ELSE 0 END)::int AS patients
       FROM facility_daily_summaries s
       CROSS JOIN LATERAL jsonb_each_text(COALESCE(s.payload->'pingpong_7color', '{}'::jsonb)) AS item(key, value)
       WHERE s.report_date BETWEEN $1::date AND $2::date
       ${facilityWhere}
       GROUP BY item.key
     )
     SELECT
       labels.color_key,
       labels.color_label,
       labels.risk_level,
       labels.care_advice,
       COALESCE(pingpong.patients, 0)::int AS patients
     FROM (VALUES
       ('black', 'สีดำ', 'มีภาวะแทรกซ้อน', 'พบแพทย์/ทีมสหวิชาชีพเร่งด่วน และติดตามภาวะแทรกซ้อนอย่างใกล้ชิด', 1),
       ('red', 'สีแดง', 'ป่วยระดับ 3', 'พบแพทย์โดยเร็ว ปรับแผนรักษา และติดตามซ้ำถี่ตามนัด', 2),
       ('orange', 'สีส้ม', 'ป่วยระดับ 2', 'พบแพทย์ทุก 4 สัปดาห์หรือตามนัด พร้อมบันทึกค่าน้ำตาลและความดัน', 3),
       ('yellow', 'สีเหลือง', 'ป่วยระดับ 1', 'ปรับพฤติกรรม รับยา/ติดตามตามนัด และเฝ้าระวังค่าน้ำตาลกับความดัน', 4),
       ('green', 'สีเขียว', 'กลุ่มเสี่ยง', 'ให้คำแนะนำปรับพฤติกรรม ควบคุมอาหาร ออกกำลังกาย และติดตามคัดกรอง', 5),
       ('white', 'สีขาว', 'กลุ่มปกติ', 'ส่งเสริมสุขภาพ คงพฤติกรรมที่ดี และตรวจคัดกรองตามรอบ', 6)
     ) AS labels(color_key, color_label, risk_level, care_advice, sort_order)
     LEFT JOIN pingpong ON pingpong.key = labels.color_key
     ORDER BY labels.sort_order`,
    params
  );

  res.json({ start_date: startDate, end_date: endDate, data: result.rows });
});

app.get("/api/v1/dashboard/ncd-house-locations", async (req, res) => {
  const startDate = typeof req.query.start_date === "string" ? req.query.start_date : null;
  const endDate = typeof req.query.end_date === "string" ? req.query.end_date : null;
  const facilityId = typeof req.query.facility_id === "string" && req.query.facility_id ? req.query.facility_id : null;
  const diseaseGroup = typeof req.query.disease_group === "string" && req.query.disease_group ? req.query.disease_group : null;

  if (!startDate || !endDate) {
    return res.status(400).json({ error: "start_date_and_end_date_required" });
  }

  const params = [startDate, endDate];
  const filters = ["l.report_date BETWEEN $1::date AND $2::date"];
  if (facilityId) {
    filters.push(`l.facility_id = $${params.push(facilityId)}`);
  }
  if (diseaseGroup) {
    filters.push(`l.disease_group = $${params.push(diseaseGroup)}`);
  }

  const result = await query(
    `WITH selected_diseases AS (
       SELECT DISTINCT ON (l.facility_id, l.patient_hash, l.disease_group)
         l.facility_id,
         f.facility_name,
         l.report_date,
         l.patient_hash,
         l.disease_group,
         l.latitude::float AS latitude,
         l.longitude::float AS longitude
       FROM ncd_house_locations l
       JOIN facilities f ON f.facility_id = l.facility_id
       WHERE ${filters.join(" AND ")}
       ORDER BY l.facility_id, l.patient_hash, l.disease_group, l.report_date DESC
     ),
     selected AS (
       SELECT DISTINCT ON (facility_id, patient_hash)
         facility_id,
         facility_name,
         MAX(report_date) OVER (PARTITION BY facility_id, patient_hash) AS report_date,
         patient_hash,
         CASE
           WHEN BOOL_OR(disease_group = 'DM') OVER (PARTITION BY facility_id, patient_hash)
            AND BOOL_OR(disease_group = 'HT') OVER (PARTITION BY facility_id, patient_hash)
             THEN 'DM_HT'
           WHEN BOOL_OR(disease_group = 'DM') OVER (PARTITION BY facility_id, patient_hash)
             THEN 'DM'
           WHEN BOOL_OR(disease_group = 'HT') OVER (PARTITION BY facility_id, patient_hash)
             THEN 'HT'
           ELSE MIN(disease_group) OVER (PARTITION BY facility_id, patient_hash)
         END AS disease_group,
         FIRST_VALUE(latitude) OVER (PARTITION BY facility_id, patient_hash ORDER BY report_date DESC) AS latitude,
         FIRST_VALUE(longitude) OVER (PARTITION BY facility_id, patient_hash ORDER BY report_date DESC) AS longitude
       FROM selected_diseases
       ORDER BY facility_id, patient_hash, report_date DESC
     )
     SELECT
       facility_id,
       facility_name,
       report_date,
       disease_group,
       latitude,
       longitude,
       COUNT(*) OVER ()::int AS total_locations
     FROM selected
     ORDER BY report_date DESC, facility_id, disease_group
     LIMIT 5000`,
    params
  );

  const groups = result.rows.reduce((acc, row) => {
    acc[row.disease_group] = (acc[row.disease_group] || 0) + 1;
    return acc;
  }, {});

  res.json({
    start_date: startDate,
    end_date: endDate,
    total_locations: result.rows[0]?.total_locations || 0,
    returned_locations: result.rows.length,
    groups,
    data: result.rows.map(({ total_locations, ...row }) => row)
  });
});

app.get("/api/v1/dashboard/available-years", async (_req, res) => {
  const result = await query(
    `SELECT DISTINCT (EXTRACT(YEAR FROM report_date)::int + 543) AS calendar_year
     FROM facility_daily_summaries
     ORDER BY calendar_year DESC`
  );

  const years = result.rows.map((row) => Number(row.calendar_year));
  res.json({ years });
});

app.use((_req, res) => {
  res.status(404).json({ error: "not_found" });
});

try {
  await ensureSchema();
  app.listen(port, () => {
    console.log(`Central API listening on ${port}`);
  });
} catch (error) {
  console.error("Central API failed to start", error);
  process.exit(1);
}
