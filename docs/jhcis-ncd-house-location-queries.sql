-- JHCIS NCD house location queries.
-- Use these queries from a readonly account. Verify local column names first because
-- JHCIS versions may differ.

-- 1) Discover actual house/person coordinate and join columns.
SHOW COLUMNS FROM house;
SHOW COLUMNS FROM person;
SHOW COLUMNS FROM visit;
SHOW COLUMNS FROM visitdiag;

-- 2) Optional quick check: how many houses have coordinates.
-- Adjust xgis/ygis if the local house table uses different names.
SELECT
  COUNT(*) AS houses_total,
  SUM(CASE WHEN NULLIF(TRIM(xgis), '') IS NOT NULL
            AND NULLIF(TRIM(ygis), '') IS NOT NULL THEN 1 ELSE 0 END) AS houses_with_coordinates
FROM house;

-- 3) Daily NCD house locations for the Windows agent.
-- Required output columns:
--   patient_key    local raw key; the agent hashes this before sending
--   disease_group  display group such as DM or HT
--   latitude       decimal latitude
--   longitude      decimal longitude
--
-- Parameter style: ? is report_date in yyyy-MM-dd format.
SELECT DISTINCT
  CONCAT(v.pcucodeperson, ':', v.pid) AS patient_key,
  CASE
    WHEN d.diagcode REGEXP '^E1[0-4]' THEN 'DM'
    WHEN d.diagcode REGEXP '^I1[0-5]' THEN 'HT'
    ELSE 'NCD'
  END AS disease_group,
  CAST(TRIM(h.xgis) AS DECIMAL(10,7)) AS latitude,
  CAST(TRIM(h.ygis) AS DECIMAL(10,7)) AS longitude
FROM visit v
JOIN visitdiag d
  ON d.pcucode = v.pcucode
 AND d.visitno = v.visitno
JOIN person p
  ON p.pcucodeperson = v.pcucodeperson
 AND p.pid = v.pid
JOIN house h
  ON h.pcucode = p.pcucodeperson
 AND h.hcode = p.hcode
WHERE v.visitdate = ?
  AND (
    d.diagcode REGEXP '^E1[0-4]'
    OR d.diagcode REGEXP '^I1[0-5]'
  )
  AND TRIM(h.ygis) REGEXP '^-?[0-9]+(\\.[0-9]+)?$'
  AND TRIM(h.xgis) REGEXP '^-?[0-9]+(\\.[0-9]+)?$'
  AND CAST(TRIM(h.xgis) AS DECIMAL(10,7)) BETWEEN 5 AND 21
  AND CAST(TRIM(h.ygis) AS DECIMAL(10,7)) BETWEEN 97 AND 106;

-- This JHCIS database stores house.xgis as latitude and house.ygis as longitude.
