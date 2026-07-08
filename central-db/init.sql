CREATE TABLE IF NOT EXISTS facilities (
  facility_id VARCHAR(20) PRIMARY KEY,
  facility_name TEXT NOT NULL,
  district TEXT,
  province TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS facility_daily_summaries (
  id BIGSERIAL PRIMARY KEY,
  facility_id VARCHAR(20) NOT NULL REFERENCES facilities(facility_id),
  report_date DATE NOT NULL,
  total_visits INTEGER NOT NULL DEFAULT 0,
  unique_patients INTEGER NOT NULL DEFAULT 0,
  chronic_followups INTEGER NOT NULL DEFAULT 0,
  ncd_dm_patients INTEGER NOT NULL DEFAULT 0,
  ncd_ht_patients INTEGER NOT NULL DEFAULT 0,
  ncd_dm_ht_patients INTEGER NOT NULL DEFAULT 0,
  ncd_bp_screened INTEGER NOT NULL DEFAULT 0,
  ncd_fbs_screened INTEGER NOT NULL DEFAULT 0,
  missing_diagnosis INTEGER NOT NULL DEFAULT 0,
  anc_visits INTEGER NOT NULL DEFAULT 0,
  vaccine_visits INTEGER NOT NULL DEFAULT 0,
  home_visits INTEGER NOT NULL DEFAULT 0,
  refer_out INTEGER NOT NULL DEFAULT 0,
  emergency_cases INTEGER NOT NULL DEFAULT 0,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  source_generated_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (facility_id, report_date)
);

CREATE INDEX IF NOT EXISTS idx_daily_summaries_report_date
  ON facility_daily_summaries(report_date DESC);

CREATE INDEX IF NOT EXISTS idx_daily_summaries_facility_date
  ON facility_daily_summaries(facility_id, report_date DESC);

CREATE TABLE IF NOT EXISTS ncd_house_locations (
  id BIGSERIAL PRIMARY KEY,
  facility_id VARCHAR(20) NOT NULL REFERENCES facilities(facility_id),
  report_date DATE NOT NULL,
  patient_hash TEXT NOT NULL,
  disease_group VARCHAR(50) NOT NULL,
  latitude NUMERIC(10,7) NOT NULL,
  longitude NUMERIC(10,7) NOT NULL,
  source_generated_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (facility_id, report_date, patient_hash, disease_group)
);

CREATE INDEX IF NOT EXISTS idx_ncd_house_locations_date
  ON ncd_house_locations(report_date DESC);

CREATE INDEX IF NOT EXISTS idx_ncd_house_locations_facility_date
  ON ncd_house_locations(facility_id, report_date DESC);

CREATE INDEX IF NOT EXISTS idx_ncd_house_locations_disease_group
  ON ncd_house_locations(disease_group);

INSERT INTO facilities (facility_id, facility_name, district, province)
VALUES
  ('10001', 'รพ.สต. ตัวอย่าง', 'เมือง', 'จังหวัดตัวอย่าง')
ON CONFLICT (facility_id) DO NOTHING;
