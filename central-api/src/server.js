import cors from "cors";
import express from "express";
import helmet from "helmet";
import { z } from "zod";
import { requireEtlToken } from "./auth.js";
import { pool, query } from "./db.js";

const app = express();
const port = Number(process.env.PORT || 8080);

app.use(helmet());
app.use(cors({ origin: process.env.CORS_ORIGIN || "*" }));
app.use(express.json({ limit: "512kb" }));

const summarySchema = z.object({
  facility_id: z.string().min(1).max(20),
  facility_name: z.string().min(1).max(255),
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
      `INSERT INTO facilities (facility_id, facility_name, district, province, updated_at)
       VALUES ($1, $2, $3, $4, NOW())
       ON CONFLICT (facility_id) DO UPDATE SET
         facility_name = EXCLUDED.facility_name,
         district = EXCLUDED.district,
         province = EXCLUDED.province,
         updated_at = NOW()`,
      [data.facility_id, data.facility_name, data.district || null, data.province || null]
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
    return res.status(500).json({ error: "store_failed" });
  } finally {
    client.release();
  }
});

app.get("/api/v1/facilities", async (_req, res) => {
  const result = await query(
    `SELECT facility_id, facility_name, district, province, is_active, updated_at
     FROM facilities
     ORDER BY facility_name`
  );
  res.json({ data: result.rows });
});

app.get("/api/v1/dashboard/overview", async (req, res) => {
  const reportDate = typeof req.query.report_date === "string" ? req.query.report_date : null;
  const joinDate = reportDate ? "AND s.report_date = $1" : "";
  const params = reportDate ? [reportDate] : [];

  const selected = await query(
    `SELECT DISTINCT ON (f.facility_id)
       f.facility_id, f.facility_name, f.district, f.province,
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
  const hasRange = Boolean(startDate && endDate);
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
     }
     GROUP BY report_date
     ORDER BY report_date`,
    hasRange ? [startDate, endDate] : [days]
  );

  res.json({ days: hasRange ? null : days, start_date: startDate, end_date: endDate, data: result.rows });
});

app.get("/api/v1/dashboard/facilities/range", async (req, res) => {
  const startDate = typeof req.query.start_date === "string" ? req.query.start_date : null;
  const endDate = typeof req.query.end_date === "string" ? req.query.end_date : null;

  if (!startDate || !endDate) {
    return res.status(400).json({ error: "start_date_and_end_date_required" });
  }

  const result = await query(
    `SELECT
       f.facility_id,
       f.facility_name,
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
     GROUP BY f.facility_id, f.facility_name, f.district, f.province
     ORDER BY total_visits DESC, f.facility_name`,
    [startDate, endDate]
  );

  res.json({ start_date: startDate, end_date: endDate, facilities: result.rows });
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

app.listen(port, () => {
  console.log(`Central API listening on ${port}`);
});
