-- JHCIS DM/HT pingpong 7-color queries (v2 — with HbA1c + DBP + controlled).
-- Parameter style for Windows agent scalar queries: ? is report_date in yyyy-MM-dd format.
--
-- Changes from v1:
--   1. Base is DM/HT (E10-E14 OR I10-I15), not DM only.
--   2. DBP (diastolic) is parsed from visit.pressure / pressure2.
--   3. HbA1c is read from visitlabchcyhembmsse.labresultdigit WHERE labcode = 'CH99'.
--   4. Controlled color added: FBS <=125 AND SBP <=139 AND DBP <=89.
--   5. Color priority: black > red > orange > yellow > controlled > green > white.

-- ── Summary by color for one day (single query, returns color_key + count) ──
SELECT color_key, COUNT(*) AS patients
FROM (
  SELECT
    patient_key,
    CASE
      WHEN has_complication = 1 THEN 'black'
      WHEN COALESCE(max_fbs, 0) >= 183 OR COALESCE(max_hba1c, 0) > 8 OR COALESCE(max_sbp, 0) >= 180 OR COALESCE(max_dbp, 0) >= 110 THEN 'red'
      WHEN COALESCE(max_fbs, 0) BETWEEN 155 AND 182 OR COALESCE(max_hba1c, 0) BETWEEN 7 AND 7.9 OR COALESCE(max_sbp, 0) BETWEEN 160 AND 179 OR COALESCE(max_dbp, 0) BETWEEN 100 AND 109 THEN 'orange'
      WHEN COALESCE(max_fbs, 0) BETWEEN 126 AND 154 OR COALESCE(max_sbp, 0) BETWEEN 140 AND 159 OR COALESCE(max_dbp, 0) BETWEEN 90 AND 99 THEN 'yellow'
      WHEN COALESCE(max_fbs, 9999) <= 125 AND COALESCE(max_sbp, 9999) <= 139 AND COALESCE(max_dbp, 9999) <= 89 THEN 'controlled'
      WHEN COALESCE(max_fbs, 0) BETWEEN 100 AND 125 OR COALESCE(max_sbp, 0) BETWEEN 121 AND 139 OR COALESCE(max_dbp, 0) BETWEEN 81 AND 89 THEN 'green'
      WHEN COALESCE(max_fbs, 9999) < 100 AND COALESCE(max_sbp, 9999) <= 120 AND COALESCE(max_dbp, 9999) <= 80 THEN 'white'
      ELSE NULL
    END AS color_key
  FROM (
    SELECT
      CONCAT(v.pcucodeperson, ':', v.pid) AS patient_key,
      MAX(CASE WHEN s.bsl IS NOT NULL AND s.bsl > 0 THEN CAST(s.bsl AS DECIMAL(10,1)) ELSE NULL END) AS max_fbs,
      MAX(CASE
        WHEN TRIM(v.pressure) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure), '/', 1) AS DECIMAL(5,1))
        WHEN TRIM(v.pressure2) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2), '/', 1) AS DECIMAL(5,1))
        WHEN TRIM(v.pressure) REGEXP '^[0-9]+$' THEN CAST(TRIM(v.pressure) AS DECIMAL(5,1))
        ELSE NULL
      END) AS max_sbp,
      MAX(CASE
        WHEN TRIM(v.pressure) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure), '/', -1) AS DECIMAL(5,1))
        WHEN TRIM(v.pressure2) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2), '/', -1) AS DECIMAL(5,1))
        ELSE NULL
      END) AS max_dbp,
      MAX(CASE WHEN hb.labresultdigit IS NOT NULL AND hb.labresultdigit > 0 THEN hb.labresultdigit ELSE NULL END) AS max_hba1c,
      MAX(CASE
        WHEN dg.diagcode REGEXP '^E1[0-4]\.[2-8]'
          OR dg.diagcode REGEXP '^N18'
          OR dg.diagcode REGEXP '^N08'
          OR dg.diagcode REGEXP '^H36'
          OR dg.diagcode REGEXP '^L97'
          OR dg.diagcode REGEXP '^I7[0-9]'
        THEN 1 ELSE 0
      END) AS has_complication
    FROM visit v
    JOIN visitdiag ncd
      ON ncd.pcucode = v.pcucode
     AND ncd.visitno = v.visitno
     AND (ncd.diagcode REGEXP '^E1[0-4]' OR ncd.diagcode REGEXP '^I1[0-5]')
    LEFT JOIN visitdiag dg
      ON dg.pcucode = v.pcucode
     AND dg.visitno = v.visitno
    LEFT JOIN ncd_person_ncd_screen s
      ON s.pid = v.pid
     AND s.pcucode = v.pcucodeperson
     AND s.screen_date = v.visitdate
    LEFT JOIN visitlabchcyhembmsse hb
      ON hb.pcucodeperson = v.pcucodeperson
     AND hb.pid = v.pid
     AND hb.datecheck = v.visitdate
     AND hb.labcode = 'CH99'
    WHERE v.visitdate = ?
    GROUP BY v.pcucodeperson, v.pid
  ) patient_day
) colored
WHERE color_key IS NOT NULL
GROUP BY color_key
ORDER BY FIELD(color_key, 'white', 'green', 'controlled', 'yellow', 'orange', 'red', 'black');

-- ── Windows agent scalar queries ──
-- Copy each query into config Sql as PingpongWhite, PingpongGreen, PingpongControlled,
-- PingpongYellow, PingpongOrange, PingpongRed, and PingpongBlack.
-- Each query counts patients in that one color for the given report date.

-- PingpongBlack (complications)
SELECT COUNT(*) FROM (
  SELECT CONCAT(v.pcucodeperson, ':', v.pid) AS patient_key
  FROM visit v
  JOIN visitdiag ncd ON ncd.pcucode = v.pcucode AND ncd.visitno = v.visitno
    AND (ncd.diagcode REGEXP '^E1[0-4]' OR ncd.diagcode REGEXP '^I1[0-5]')
  LEFT JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
  WHERE v.visitdate = ?
  GROUP BY v.pcucodeperson, v.pid
  HAVING MAX(CASE WHEN dg.diagcode REGEXP '^E1[0-4]\.[2-8]' OR dg.diagcode REGEXP '^N18'
    OR dg.diagcode REGEXP '^N08' OR dg.diagcode REGEXP '^H36' OR dg.diagcode REGEXP '^L97'
    OR dg.diagcode REGEXP '^I7[0-9]' THEN 1 ELSE 0 END) = 1
) x;

-- PingpongRed (FBS >=183 OR HbA1c >8 OR SBP >=180 OR DBP >=110, no complication)
SELECT COUNT(*) FROM (
  SELECT CONCAT(v.pcucodeperson, ':', v.pid) AS pk,
    MAX(CASE WHEN s.bsl IS NOT NULL AND s.bsl > 0 THEN CAST(s.bsl AS DECIMAL(10,1)) ELSE NULL END) AS fbs,
    MAX(CASE WHEN TRIM(v.pressure) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure),'/',1) AS DECIMAL(5,1))
             WHEN TRIM(v.pressure2) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2),'/',1) AS DECIMAL(5,1))
             WHEN TRIM(v.pressure) REGEXP '^[0-9]+$' THEN CAST(TRIM(v.pressure) AS DECIMAL(5,1)) ELSE NULL END) AS sbp,
    MAX(CASE WHEN TRIM(v.pressure) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure),'/',-1) AS DECIMAL(5,1))
             WHEN TRIM(v.pressure2) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2),'/',-1) AS DECIMAL(5,1))
             ELSE NULL END) AS dbp,
    MAX(CASE WHEN hb.labresultdigit IS NOT NULL AND hb.labresultdigit > 0 THEN hb.labresultdigit ELSE NULL END) AS hba1c,
    MAX(CASE WHEN dg.diagcode REGEXP '^E1[0-4]\.[2-8]' OR dg.diagcode REGEXP '^N18' OR dg.diagcode REGEXP '^N08'
      OR dg.diagcode REGEXP '^H36' OR dg.diagcode REGEXP '^L97' OR dg.diagcode REGEXP '^I7[0-9]' THEN 1 ELSE 0 END) AS comp
  FROM visit v
  JOIN visitdiag ncd ON ncd.pcucode=v.pcucode AND ncd.visitno=v.visitno AND (ncd.diagcode REGEXP '^E1[0-4]' OR ncd.diagcode REGEXP '^I1[0-5]')
  LEFT JOIN visitdiag dg ON dg.pcucode=v.pcucode AND dg.visitno=v.visitno
  LEFT JOIN ncd_person_ncd_screen s ON s.pid=v.pid AND s.pcucode=v.pcucodeperson AND s.screen_date=v.visitdate
  LEFT JOIN visitlabchcyhembmsse hb ON hb.pcucodeperson=v.pcucodeperson AND hb.pid=v.pid AND hb.datecheck=v.visitdate AND hb.labcode='CH99'
  WHERE v.visitdate = ? GROUP BY v.pcucodeperson, v.pid
) x WHERE comp = 0 AND (COALESCE(fbs,0)>=183 OR COALESCE(hba1c,0)>8 OR COALESCE(sbp,0)>=180 OR COALESCE(dbp,0)>=110);

-- PingpongOrange (FBS 155-182 OR HbA1c 7-7.9 OR SBP 160-179 OR DBP 100-109, no comp, not red)
SELECT COUNT(*) FROM (
  SELECT CONCAT(v.pcucodeperson, ':', v.pid) AS pk,
    MAX(CASE WHEN s.bsl IS NOT NULL AND s.bsl > 0 THEN CAST(s.bsl AS DECIMAL(10,1)) ELSE NULL END) AS fbs,
    MAX(CASE WHEN TRIM(v.pressure) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure),'/',1) AS DECIMAL(5,1))
             WHEN TRIM(v.pressure2) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2),'/',1) AS DECIMAL(5,1))
             WHEN TRIM(v.pressure) REGEXP '^[0-9]+$' THEN CAST(TRIM(v.pressure) AS DECIMAL(5,1)) ELSE NULL END) AS sbp,
    MAX(CASE WHEN TRIM(v.pressure) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure),'/',-1) AS DECIMAL(5,1))
             WHEN TRIM(v.pressure2) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2),'/',-1) AS DECIMAL(5,1))
             ELSE NULL END) AS dbp,
    MAX(CASE WHEN hb.labresultdigit IS NOT NULL AND hb.labresultdigit > 0 THEN hb.labresultdigit ELSE NULL END) AS hba1c,
    MAX(CASE WHEN dg.diagcode REGEXP '^E1[0-4]\.[2-8]' OR dg.diagcode REGEXP '^N18' OR dg.diagcode REGEXP '^N08'
      OR dg.diagcode REGEXP '^H36' OR dg.diagcode REGEXP '^L97' OR dg.diagcode REGEXP '^I7[0-9]' THEN 1 ELSE 0 END) AS comp
  FROM visit v
  JOIN visitdiag ncd ON ncd.pcucode=v.pcucode AND ncd.visitno=v.visitno AND (ncd.diagcode REGEXP '^E1[0-4]' OR ncd.diagcode REGEXP '^I1[0-5]')
  LEFT JOIN visitdiag dg ON dg.pcucode=v.pcucode AND dg.visitno=v.visitno
  LEFT JOIN ncd_person_ncd_screen s ON s.pid=v.pid AND s.pcucode=v.pcucodeperson AND s.screen_date=v.visitdate
  LEFT JOIN visitlabchcyhembmsse hb ON hb.pcucodeperson=v.pcucodeperson AND hb.pid=v.pid AND hb.datecheck=v.visitdate AND hb.labcode='CH99'
  WHERE v.visitdate = ? GROUP BY v.pcucodeperson, v.pid
) x WHERE comp = 0
  AND NOT (COALESCE(fbs,0)>=183 OR COALESCE(hba1c,0)>8 OR COALESCE(sbp,0)>=180 OR COALESCE(dbp,0)>=110)
  AND (COALESCE(fbs,0) BETWEEN 155 AND 182 OR COALESCE(hba1c,0) BETWEEN 7 AND 7.9
       OR COALESCE(sbp,0) BETWEEN 160 AND 179 OR COALESCE(dbp,0) BETWEEN 100 AND 109);

-- PingpongYellow (FBS 126-154 OR SBP 140-159 OR DBP 90-99, no comp, not red/orange)
SELECT COUNT(*) FROM (
  SELECT CONCAT(v.pcucodeperson, ':', v.pid) AS pk,
    MAX(CASE WHEN s.bsl IS NOT NULL AND s.bsl > 0 THEN CAST(s.bsl AS DECIMAL(10,1)) ELSE NULL END) AS fbs,
    MAX(CASE WHEN TRIM(v.pressure) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure),'/',1) AS DECIMAL(5,1))
             WHEN TRIM(v.pressure2) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2),'/',1) AS DECIMAL(5,1))
             WHEN TRIM(v.pressure) REGEXP '^[0-9]+$' THEN CAST(TRIM(v.pressure) AS DECIMAL(5,1)) ELSE NULL END) AS sbp,
    MAX(CASE WHEN TRIM(v.pressure) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure),'/',-1) AS DECIMAL(5,1))
             WHEN TRIM(v.pressure2) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2),'/',-1) AS DECIMAL(5,1))
             ELSE NULL END) AS dbp,
    MAX(CASE WHEN dg.diagcode REGEXP '^E1[0-4]\.[2-8]' OR dg.diagcode REGEXP '^N18' OR dg.diagcode REGEXP '^N08'
      OR dg.diagcode REGEXP '^H36' OR dg.diagcode REGEXP '^L97' OR dg.diagcode REGEXP '^I7[0-9]' THEN 1 ELSE 0 END) AS comp
  FROM visit v
  JOIN visitdiag ncd ON ncd.pcucode=v.pcucode AND ncd.visitno=v.visitno AND (ncd.diagcode REGEXP '^E1[0-4]' OR ncd.diagcode REGEXP '^I1[0-5]')
  LEFT JOIN visitdiag dg ON dg.pcucode=v.pcucode AND dg.visitno=v.visitno
  LEFT JOIN ncd_person_ncd_screen s ON s.pid=v.pid AND s.pcucode=v.pcucodeperson AND s.screen_date=v.visitdate
  WHERE v.visitdate = ? GROUP BY v.pcucodeperson, v.pid
) x WHERE comp = 0
  AND NOT (COALESCE(fbs,0)>=183 OR COALESCE(sbp,0)>=180 OR COALESCE(dbp,0)>=110)
  AND NOT (COALESCE(fbs,0) BETWEEN 155 AND 182 OR COALESCE(sbp,0) BETWEEN 160 AND 179 OR COALESCE(dbp,0) BETWEEN 100 AND 109)
  AND (COALESCE(fbs,0) BETWEEN 126 AND 154 OR COALESCE(sbp,0) BETWEEN 140 AND 159 OR COALESCE(dbp,0) BETWEEN 90 AND 99);

-- PingpongControlled (FBS <=125 AND SBP <=139 AND DBP <=89, no comp, not red/orange/yellow)
SELECT COUNT(*) FROM (
  SELECT CONCAT(v.pcucodeperson, ':', v.pid) AS pk,
    MAX(CASE WHEN s.bsl IS NOT NULL AND s.bsl > 0 THEN CAST(s.bsl AS DECIMAL(10,1)) ELSE NULL END) AS fbs,
    MAX(CASE WHEN TRIM(v.pressure) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure),'/',1) AS DECIMAL(5,1))
             WHEN TRIM(v.pressure2) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2),'/',1) AS DECIMAL(5,1))
             WHEN TRIM(v.pressure) REGEXP '^[0-9]+$' THEN CAST(TRIM(v.pressure) AS DECIMAL(5,1)) ELSE NULL END) AS sbp,
    MAX(CASE WHEN TRIM(v.pressure) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure),'/',-1) AS DECIMAL(5,1))
             WHEN TRIM(v.pressure2) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2),'/',-1) AS DECIMAL(5,1))
             ELSE NULL END) AS dbp,
    MAX(CASE WHEN dg.diagcode REGEXP '^E1[0-4]\.[2-8]' OR dg.diagcode REGEXP '^N18' OR dg.diagcode REGEXP '^N08'
      OR dg.diagcode REGEXP '^H36' OR dg.diagcode REGEXP '^L97' OR dg.diagcode REGEXP '^I7[0-9]' THEN 1 ELSE 0 END) AS comp
  FROM visit v
  JOIN visitdiag ncd ON ncd.pcucode=v.pcucode AND ncd.visitno=v.visitno AND (ncd.diagcode REGEXP '^E1[0-4]' OR ncd.diagcode REGEXP '^I1[0-5]')
  LEFT JOIN visitdiag dg ON dg.pcucode=v.pcucode AND dg.visitno=v.visitno
  LEFT JOIN ncd_person_ncd_screen s ON s.pid=v.pid AND s.pcucode=v.pcucodeperson AND s.screen_date=v.visitdate
  WHERE v.visitdate = ? GROUP BY v.pcucodeperson, v.pid
) x WHERE comp = 0
  AND NOT (COALESCE(fbs,0)>=183 OR COALESCE(sbp,0)>=180 OR COALESCE(dbp,0)>=110)
  AND NOT (COALESCE(fbs,0) BETWEEN 155 AND 182 OR COALESCE(sbp,0) BETWEEN 160 AND 179 OR COALESCE(dbp,0) BETWEEN 100 AND 109)
  AND NOT (COALESCE(fbs,0) BETWEEN 126 AND 154 OR COALESCE(sbp,0) BETWEEN 140 AND 159 OR COALESCE(dbp,0) BETWEEN 90 AND 99)
  AND COALESCE(fbs,9999) <= 125 AND COALESCE(sbp,9999) <= 139 AND COALESCE(dbp,9999) <= 89;

-- PingpongGreen (FBS 100-125 OR SBP 121-139 OR DBP 81-89, no comp, not red/orange/yellow/controlled)
SELECT COUNT(*) FROM (
  SELECT CONCAT(v.pcucodeperson, ':', v.pid) AS pk,
    MAX(CASE WHEN s.bsl IS NOT NULL AND s.bsl > 0 THEN CAST(s.bsl AS DECIMAL(10,1)) ELSE NULL END) AS fbs,
    MAX(CASE WHEN TRIM(v.pressure) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure),'/',1) AS DECIMAL(5,1))
             WHEN TRIM(v.pressure2) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2),'/',1) AS DECIMAL(5,1))
             WHEN TRIM(v.pressure) REGEXP '^[0-9]+$' THEN CAST(TRIM(v.pressure) AS DECIMAL(5,1)) ELSE NULL END) AS sbp,
    MAX(CASE WHEN TRIM(v.pressure) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure),'/',-1) AS DECIMAL(5,1))
             WHEN TRIM(v.pressure2) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2),'/',-1) AS DECIMAL(5,1))
             ELSE NULL END) AS dbp,
    MAX(CASE WHEN dg.diagcode REGEXP '^E1[0-4]\.[2-8]' OR dg.diagcode REGEXP '^N18' OR dg.diagcode REGEXP '^N08'
      OR dg.diagcode REGEXP '^H36' OR dg.diagcode REGEXP '^L97' OR dg.diagcode REGEXP '^I7[0-9]' THEN 1 ELSE 0 END) AS comp
  FROM visit v
  JOIN visitdiag ncd ON ncd.pcucode=v.pcucode AND ncd.visitno=v.visitno AND (ncd.diagcode REGEXP '^E1[0-4]' OR ncd.diagcode REGEXP '^I1[0-5]')
  LEFT JOIN visitdiag dg ON dg.pcucode=v.pcucode AND dg.visitno=v.visitno
  LEFT JOIN ncd_person_ncd_screen s ON s.pid=v.pid AND s.pcucode=v.pcucodeperson AND s.screen_date=v.visitdate
  WHERE v.visitdate = ? GROUP BY v.pcucodeperson, v.pid
) x WHERE comp = 0
  AND NOT (COALESCE(fbs,9999) <= 125 AND COALESCE(sbp,9999) <= 139 AND COALESCE(dbp,9999) <= 89)
  AND (COALESCE(fbs,0) BETWEEN 100 AND 125 OR COALESCE(sbp,0) BETWEEN 121 AND 139 OR COALESCE(dbp,0) BETWEEN 81 AND 89);

-- PingpongWhite (FBS <100 AND SBP <=120 AND DBP <=80, no comp, no other color matched)
SELECT COUNT(*) FROM (
  SELECT CONCAT(v.pcucodeperson, ':', v.pid) AS pk,
    MAX(CASE WHEN s.bsl IS NOT NULL AND s.bsl > 0 THEN CAST(s.bsl AS DECIMAL(10,1)) ELSE NULL END) AS fbs,
    MAX(CASE WHEN TRIM(v.pressure) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure),'/',1) AS DECIMAL(5,1))
             WHEN TRIM(v.pressure2) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2),'/',1) AS DECIMAL(5,1))
             WHEN TRIM(v.pressure) REGEXP '^[0-9]+$' THEN CAST(TRIM(v.pressure) AS DECIMAL(5,1)) ELSE NULL END) AS sbp,
    MAX(CASE WHEN TRIM(v.pressure) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure),'/',-1) AS DECIMAL(5,1))
             WHEN TRIM(v.pressure2) REGEXP '^[0-9]+/[0-9]+$' THEN CAST(SUBSTRING_INDEX(TRIM(v.pressure2),'/',-1) AS DECIMAL(5,1))
             ELSE NULL END) AS dbp,
    MAX(CASE WHEN dg.diagcode REGEXP '^E1[0-4]\.[2-8]' OR dg.diagcode REGEXP '^N18' OR dg.diagcode REGEXP '^N08'
      OR dg.diagcode REGEXP '^H36' OR dg.diagcode REGEXP '^L97' OR dg.diagcode REGEXP '^I7[0-9]' THEN 1 ELSE 0 END) AS comp
  FROM visit v
  JOIN visitdiag ncd ON ncd.pcucode=v.pcucode AND ncd.visitno=v.visitno AND (ncd.diagcode REGEXP '^E1[0-4]' OR ncd.diagcode REGEXP '^I1[0-5]')
  LEFT JOIN visitdiag dg ON dg.pcucode=v.pcucode AND dg.visitno=v.visitno
  LEFT JOIN ncd_person_ncd_screen s ON s.pid=v.pid AND s.pcucode=v.pcucodeperson AND s.screen_date=v.visitdate
  WHERE v.visitdate = ? GROUP BY v.pcucodeperson, v.pid
) x WHERE comp = 0
  AND NOT (COALESCE(fbs,9999) <= 125 AND COALESCE(sbp,9999) <= 139 AND COALESCE(dbp,9999) <= 89)
  AND NOT (COALESCE(fbs,0) BETWEEN 100 AND 125 OR COALESCE(sbp,0) BETWEEN 121 AND 139 OR COALESCE(dbp,0) BETWEEN 81 AND 89)
  AND COALESCE(fbs,9999) < 100 AND COALESCE(sbp,9999) <= 120 AND COALESCE(dbp,9999) <= 80;