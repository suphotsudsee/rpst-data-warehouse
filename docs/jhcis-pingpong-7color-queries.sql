-- JHCIS DM pingpong 7-color queries.
-- Parameter style for Windows agent scalar queries: ? is report_date in yyyy-MM-dd format.
--
-- Color priority is applied once per patient per day:
-- black > red > orange > yellow > green > white.
-- Assumptions to verify per site:
-- - DM patients are visit patients with ICD-10 E10-E14 on the report date.
-- - FBS is read from ncd_person_ncd_screen.bsl.
-- - Systolic BP is parsed from visit.pressure or visit.pressure2.
-- - Complication signals use diabetic complication ICD and common renal/eye/foot/vascular ICD groups.

-- Summary by color for one day.
SELECT color_key, COUNT(*) AS patients
FROM (
  SELECT
    patient_key,
    CASE
      WHEN has_complication = 1 THEN 'black'
      WHEN COALESCE(max_fbs, 0) >= 183 OR COALESCE(max_sbp, 0) >= 180 THEN 'red'
      WHEN COALESCE(max_fbs, 0) BETWEEN 155 AND 182 OR COALESCE(max_sbp, 0) BETWEEN 160 AND 179 THEN 'orange'
      WHEN COALESCE(max_fbs, 0) BETWEEN 126 AND 154 OR COALESCE(max_sbp, 0) BETWEEN 140 AND 159 THEN 'yellow'
      WHEN COALESCE(max_fbs, 0) BETWEEN 100 AND 125 THEN 'green'
      WHEN COALESCE(max_fbs, 9999) < 100 AND COALESCE(max_sbp, 9999) < 120 THEN 'white'
      ELSE NULL
    END AS color_key
  FROM (
    SELECT
      CONCAT(v.pcucodeperson, ':', v.pid) AS patient_key,
      MAX(CASE WHEN s.bsl IS NOT NULL AND s.bsl > 0 THEN CAST(s.bsl AS UNSIGNED) ELSE NULL END) AS max_fbs,
      MAX(CASE
        WHEN TRIM(v.pressure) REGEXP '^[0-9]+(/[0-9]+)?$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure), '/', 1) AS UNSIGNED)
        WHEN TRIM(v.pressure2) REGEXP '^[0-9]+(/[0-9]+)?$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2), '/', 1) AS UNSIGNED)
        ELSE NULL
      END) AS max_sbp,
      MAX(CASE
        WHEN dg.diagcode REGEXP '^E1[0-4]\\.[2-8]'
          OR dg.diagcode REGEXP '^N18'
          OR dg.diagcode REGEXP '^N08'
          OR dg.diagcode REGEXP '^H36'
          OR dg.diagcode REGEXP '^L97'
          OR dg.diagcode REGEXP '^I7[0-9]'
        THEN 1 ELSE 0
      END) AS has_complication
    FROM visit v
    JOIN visitdiag dm
      ON dm.pcucode = v.pcucode
     AND dm.visitno = v.visitno
     AND dm.diagcode REGEXP '^E1[0-4]'
    LEFT JOIN visitdiag dg
      ON dg.pcucode = v.pcucode
     AND dg.visitno = v.visitno
    LEFT JOIN ncd_person_ncd_screen s
      ON s.pid = v.pid
     AND s.screen_date = v.visitdate
    WHERE v.visitdate = ?
    GROUP BY v.pcucodeperson, v.pid
  ) patient_day
) colored
WHERE color_key IS NOT NULL
GROUP BY color_key
ORDER BY FIELD(color_key, 'black', 'red', 'orange', 'yellow', 'green', 'white');

-- Windows agent scalar queries.
-- Copy each query into config Sql as PingpongBlack, PingpongRed, PingpongOrange,
-- PingpongYellow, PingpongGreen, and PingpongWhite.

-- PingpongBlack
SELECT COUNT(*)
FROM (
  SELECT CONCAT(v.pcucodeperson, ':', v.pid) AS patient_key
  FROM visit v
  JOIN visitdiag dm ON dm.pcucode = v.pcucode AND dm.visitno = v.visitno AND dm.diagcode REGEXP '^E1[0-4]'
  LEFT JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
  WHERE v.visitdate = ?
  GROUP BY v.pcucodeperson, v.pid
  HAVING MAX(CASE WHEN dg.diagcode REGEXP '^E1[0-4]\\.[2-8]' OR dg.diagcode REGEXP '^N18' OR dg.diagcode REGEXP '^N08' OR dg.diagcode REGEXP '^H36' OR dg.diagcode REGEXP '^L97' OR dg.diagcode REGEXP '^I7[0-9]' THEN 1 ELSE 0 END) = 1
) x;

-- PingpongRed
SELECT COUNT(*)
FROM (
  SELECT CONCAT(v.pcucodeperson, ':', v.pid) AS patient_key,
         MAX(CASE WHEN s.bsl IS NOT NULL AND s.bsl > 0 THEN CAST(s.bsl AS UNSIGNED) ELSE NULL END) AS max_fbs,
         MAX(CASE WHEN TRIM(v.pressure) REGEXP '^[0-9]+(/[0-9]+)?$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure), '/', 1) AS UNSIGNED) WHEN TRIM(v.pressure2) REGEXP '^[0-9]+(/[0-9]+)?$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2), '/', 1) AS UNSIGNED) ELSE NULL END) AS max_sbp,
         MAX(CASE WHEN dg.diagcode REGEXP '^E1[0-4]\\.[2-8]' OR dg.diagcode REGEXP '^N18' OR dg.diagcode REGEXP '^N08' OR dg.diagcode REGEXP '^H36' OR dg.diagcode REGEXP '^L97' OR dg.diagcode REGEXP '^I7[0-9]' THEN 1 ELSE 0 END) AS has_complication
  FROM visit v
  JOIN visitdiag dm ON dm.pcucode = v.pcucode AND dm.visitno = v.visitno AND dm.diagcode REGEXP '^E1[0-4]'
  LEFT JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
  LEFT JOIN ncd_person_ncd_screen s ON s.pid = v.pid AND s.screen_date = v.visitdate
  WHERE v.visitdate = ?
  GROUP BY v.pcucodeperson, v.pid
) x
WHERE has_complication = 0
  AND (COALESCE(max_fbs, 0) >= 183 OR COALESCE(max_sbp, 0) >= 180);

-- PingpongOrange
SELECT COUNT(*)
FROM (
  SELECT CONCAT(v.pcucodeperson, ':', v.pid) AS patient_key,
         MAX(CASE WHEN s.bsl IS NOT NULL AND s.bsl > 0 THEN CAST(s.bsl AS UNSIGNED) ELSE NULL END) AS max_fbs,
         MAX(CASE WHEN TRIM(v.pressure) REGEXP '^[0-9]+(/[0-9]+)?$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure), '/', 1) AS UNSIGNED) WHEN TRIM(v.pressure2) REGEXP '^[0-9]+(/[0-9]+)?$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2), '/', 1) AS UNSIGNED) ELSE NULL END) AS max_sbp,
         MAX(CASE WHEN dg.diagcode REGEXP '^E1[0-4]\\.[2-8]' OR dg.diagcode REGEXP '^N18' OR dg.diagcode REGEXP '^N08' OR dg.diagcode REGEXP '^H36' OR dg.diagcode REGEXP '^L97' OR dg.diagcode REGEXP '^I7[0-9]' THEN 1 ELSE 0 END) AS has_complication
  FROM visit v
  JOIN visitdiag dm ON dm.pcucode = v.pcucode AND dm.visitno = v.visitno AND dm.diagcode REGEXP '^E1[0-4]'
  LEFT JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
  LEFT JOIN ncd_person_ncd_screen s ON s.pid = v.pid AND s.screen_date = v.visitdate
  WHERE v.visitdate = ?
  GROUP BY v.pcucodeperson, v.pid
) x
WHERE has_complication = 0
  AND NOT (COALESCE(max_fbs, 0) >= 183 OR COALESCE(max_sbp, 0) >= 180)
  AND (COALESCE(max_fbs, 0) BETWEEN 155 AND 182 OR COALESCE(max_sbp, 0) BETWEEN 160 AND 179);

-- PingpongYellow
SELECT COUNT(*)
FROM (
  SELECT CONCAT(v.pcucodeperson, ':', v.pid) AS patient_key,
         MAX(CASE WHEN s.bsl IS NOT NULL AND s.bsl > 0 THEN CAST(s.bsl AS UNSIGNED) ELSE NULL END) AS max_fbs,
         MAX(CASE WHEN TRIM(v.pressure) REGEXP '^[0-9]+(/[0-9]+)?$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure), '/', 1) AS UNSIGNED) WHEN TRIM(v.pressure2) REGEXP '^[0-9]+(/[0-9]+)?$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2), '/', 1) AS UNSIGNED) ELSE NULL END) AS max_sbp,
         MAX(CASE WHEN dg.diagcode REGEXP '^E1[0-4]\\.[2-8]' OR dg.diagcode REGEXP '^N18' OR dg.diagcode REGEXP '^N08' OR dg.diagcode REGEXP '^H36' OR dg.diagcode REGEXP '^L97' OR dg.diagcode REGEXP '^I7[0-9]' THEN 1 ELSE 0 END) AS has_complication
  FROM visit v
  JOIN visitdiag dm ON dm.pcucode = v.pcucode AND dm.visitno = v.visitno AND dm.diagcode REGEXP '^E1[0-4]'
  LEFT JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
  LEFT JOIN ncd_person_ncd_screen s ON s.pid = v.pid AND s.screen_date = v.visitdate
  WHERE v.visitdate = ?
  GROUP BY v.pcucodeperson, v.pid
) x
WHERE has_complication = 0
  AND NOT (COALESCE(max_fbs, 0) >= 183 OR COALESCE(max_sbp, 0) >= 180)
  AND NOT (COALESCE(max_fbs, 0) BETWEEN 155 AND 182 OR COALESCE(max_sbp, 0) BETWEEN 160 AND 179)
  AND (COALESCE(max_fbs, 0) BETWEEN 126 AND 154 OR COALESCE(max_sbp, 0) BETWEEN 140 AND 159);

-- PingpongGreen
SELECT COUNT(*)
FROM (
  SELECT CONCAT(v.pcucodeperson, ':', v.pid) AS patient_key,
         MAX(CASE WHEN s.bsl IS NOT NULL AND s.bsl > 0 THEN CAST(s.bsl AS UNSIGNED) ELSE NULL END) AS max_fbs,
         MAX(CASE WHEN dg.diagcode REGEXP '^E1[0-4]\\.[2-8]' OR dg.diagcode REGEXP '^N18' OR dg.diagcode REGEXP '^N08' OR dg.diagcode REGEXP '^H36' OR dg.diagcode REGEXP '^L97' OR dg.diagcode REGEXP '^I7[0-9]' THEN 1 ELSE 0 END) AS has_complication
  FROM visit v
  JOIN visitdiag dm ON dm.pcucode = v.pcucode AND dm.visitno = v.visitno AND dm.diagcode REGEXP '^E1[0-4]'
  LEFT JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
  LEFT JOIN ncd_person_ncd_screen s ON s.pid = v.pid AND s.screen_date = v.visitdate
  WHERE v.visitdate = ?
  GROUP BY v.pcucodeperson, v.pid
) x
WHERE has_complication = 0
  AND COALESCE(max_fbs, 0) BETWEEN 100 AND 125;

-- PingpongWhite
SELECT COUNT(*)
FROM (
  SELECT CONCAT(v.pcucodeperson, ':', v.pid) AS patient_key,
         MAX(CASE WHEN s.bsl IS NOT NULL AND s.bsl > 0 THEN CAST(s.bsl AS UNSIGNED) ELSE NULL END) AS max_fbs,
         MAX(CASE WHEN TRIM(v.pressure) REGEXP '^[0-9]+(/[0-9]+)?$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure), '/', 1) AS UNSIGNED) WHEN TRIM(v.pressure2) REGEXP '^[0-9]+(/[0-9]+)?$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2), '/', 1) AS UNSIGNED) ELSE NULL END) AS max_sbp,
         MAX(CASE WHEN dg.diagcode REGEXP '^E1[0-4]\\.[2-8]' OR dg.diagcode REGEXP '^N18' OR dg.diagcode REGEXP '^N08' OR dg.diagcode REGEXP '^H36' OR dg.diagcode REGEXP '^L97' OR dg.diagcode REGEXP '^I7[0-9]' THEN 1 ELSE 0 END) AS has_complication
  FROM visit v
  JOIN visitdiag dm ON dm.pcucode = v.pcucode AND dm.visitno = v.visitno AND dm.diagcode REGEXP '^E1[0-4]'
  LEFT JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
  LEFT JOIN ncd_person_ncd_screen s ON s.pid = v.pid AND s.screen_date = v.visitdate
  WHERE v.visitdate = ?
  GROUP BY v.pcucodeperson, v.pid
) x
WHERE has_complication = 0
  AND COALESCE(max_fbs, 9999) < 100
  AND COALESCE(max_sbp, 9999) < 120;
