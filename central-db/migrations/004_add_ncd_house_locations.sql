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
);

CREATE INDEX IF NOT EXISTS idx_ncd_house_locations_date
  ON ncd_house_locations(report_date DESC);

CREATE INDEX IF NOT EXISTS idx_ncd_house_locations_facility_date
  ON ncd_house_locations(facility_id, report_date DESC);

CREATE INDEX IF NOT EXISTS idx_ncd_house_locations_disease_group
  ON ncd_house_locations(disease_group);
