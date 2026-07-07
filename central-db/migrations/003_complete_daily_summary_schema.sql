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
  ADD COLUMN IF NOT EXISTS payload JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_summaries_facility_report_date_unique
  ON facility_daily_summaries(facility_id, report_date);

CREATE INDEX IF NOT EXISTS idx_daily_summaries_report_date
  ON facility_daily_summaries(report_date DESC);

CREATE INDEX IF NOT EXISTS idx_daily_summaries_facility_date
  ON facility_daily_summaries(facility_id, report_date DESC);
