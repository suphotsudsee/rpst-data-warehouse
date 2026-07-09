import pg from "pg";

const { Pool } = pg;

export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000
});

export async function query(text, params) {
  return pool.query(text, params);
}

export async function ensureSchema() {
  await query(`
    CREATE TABLE IF NOT EXISTS facilities (
      facility_id VARCHAR(20) PRIMARY KEY,
      facility_name TEXT NOT NULL,
      subdistrict TEXT,
      district TEXT,
      province TEXT,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await query(`
    ALTER TABLE facilities
      ADD COLUMN IF NOT EXISTS subdistrict TEXT
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS facility_daily_summaries (
      id BIGSERIAL PRIMARY KEY,
      facility_id VARCHAR(20) NOT NULL REFERENCES facilities(facility_id),
      report_date DATE NOT NULL,
      source_generated_at TIMESTAMPTZ NOT NULL,
      received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await query(`
    ALTER TABLE facility_daily_summaries
      ADD COLUMN IF NOT EXISTS total_visits INTEGER NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS unique_patients INTEGER NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS chronic_followups INTEGER NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS ncd_dm_patients INTEGER NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS ncd_ht_patients INTEGER NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS ncd_dm_ht_patients INTEGER NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS ncd_bp_screened INTEGER NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS ncd_fbs_screened INTEGER NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS missing_diagnosis INTEGER NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS anc_visits INTEGER NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS vaccine_visits INTEGER NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS home_visits INTEGER NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS refer_out INTEGER NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS emergency_cases INTEGER NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS payload JSONB NOT NULL DEFAULT '{}'::jsonb
  `);

  await query(`
    CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_summaries_facility_report_date_unique
      ON facility_daily_summaries(facility_id, report_date)
  `);

  await query(`
    CREATE INDEX IF NOT EXISTS idx_daily_summaries_report_date
      ON facility_daily_summaries(report_date DESC)
  `);

  await query(`
    CREATE INDEX IF NOT EXISTS idx_daily_summaries_facility_date
      ON facility_daily_summaries(facility_id, report_date DESC)
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS ncd_house_locations (
      id BIGSERIAL PRIMARY KEY,
      facility_id VARCHAR(20) NOT NULL REFERENCES facilities(facility_id),
      report_date DATE NOT NULL,
      patient_hash TEXT NOT NULL,
      pcucodeperson CHAR(5) NOT NULL DEFAULT '',
      pid INTEGER NOT NULL DEFAULT 0,
      disease_group VARCHAR(50) NOT NULL,
      latitude NUMERIC(10,7) NOT NULL,
      longitude NUMERIC(10,7) NOT NULL,
      source_generated_at TIMESTAMPTZ NOT NULL,
      received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      payload JSONB NOT NULL DEFAULT '{}'::jsonb,
      UNIQUE (facility_id, report_date, patient_hash, disease_group)
    )
  `);

  await query(`
    ALTER TABLE ncd_house_locations
      ADD COLUMN IF NOT EXISTS pcucodeperson CHAR(5) NOT NULL DEFAULT '',
      ADD COLUMN IF NOT EXISTS pid INTEGER NOT NULL DEFAULT 0
  `);

  await query(`
    CREATE INDEX IF NOT EXISTS idx_ncd_house_locations_date
      ON ncd_house_locations(report_date DESC)
  `);

  await query(`
    CREATE INDEX IF NOT EXISTS idx_ncd_house_locations_facility_date
      ON ncd_house_locations(facility_id, report_date DESC)
  `);

  await query(`
    CREATE INDEX IF NOT EXISTS idx_ncd_house_locations_disease_group
      ON ncd_house_locations(disease_group)
  `);
}
