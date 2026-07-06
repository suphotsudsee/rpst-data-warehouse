-- JHCIS jhcisdb03633 phase-1 dashboard queries.
-- Parameter style: ? is report_date in yyyy-MM-dd format.
-- If a query has more than one ?, Windows agent will bind the same report_date to all of them.

-- TotalVisits
SELECT COUNT(*)
FROM visit v
WHERE v.visitdate = ?;

-- UniquePatients
SELECT COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
WHERE v.visitdate = ?;

-- ChronicFollowups
-- DM: E10-E14, HT: I10-I15.
SELECT COUNT(DISTINCT v.pcucode, v.visitno)
FROM visit v
JOIN visitdiag d
  ON d.pcucode = v.pcucode
 AND d.visitno = v.visitno
WHERE v.visitdate = ?
  AND (
    d.diagcode REGEXP '^E1[0-4]'
    OR d.diagcode REGEXP '^I1[0-5]'
  );

-- NcdDmPatients
SELECT COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d
  ON d.pcucode = v.pcucode
 AND d.visitno = v.visitno
WHERE v.visitdate = ?
  AND d.diagcode REGEXP '^E1[0-4]';

-- NcdHtPatients
SELECT COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d
  ON d.pcucode = v.pcucode
 AND d.visitno = v.visitno
WHERE v.visitdate = ?
  AND d.diagcode REGEXP '^I1[0-5]';

-- NcdDmHtPatients
SELECT COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d
  ON d.pcucode = v.pcucode
 AND d.visitno = v.visitno
WHERE v.visitdate = ?
  AND (
    d.diagcode REGEXP '^E1[0-4]'
    OR d.diagcode REGEXP '^I1[0-5]'
  );

-- NcdBpScreened
-- Counts patients with BP in visit.pressure/pressure2 on the report date.
SELECT COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
WHERE v.visitdate = ?
  AND (
    NULLIF(TRIM(v.pressure), '') IS NOT NULL
    OR NULLIF(TRIM(v.pressure2), '') IS NOT NULL
  );

-- NcdFbsScreened
-- Counts FBS/blood sugar records from NCD screening or NCD lab on the report date.
SELECT COUNT(DISTINCT x.pid)
FROM (
  SELECT CAST(s.pid AS CHAR) AS pid
  FROM ncd_person_ncd_screen s
  JOIN (SELECT ? AS report_date) p
  WHERE s.screen_date = p.report_date
    AND s.bsl IS NOT NULL
    AND s.bsl > 0

  UNION

  SELECT CAST(l.pid AS CHAR) AS pid
  FROM ncdlab l
  JOIN (SELECT ? AS report_date) p
  WHERE l.date_serv = DATE_FORMAT(p.report_date, '%Y%m%d')
    AND (
      l.testname LIKE '%FBS%'
      OR l.testname LIKE '%FAST%'
      OR l.testname LIKE '%SUGAR%'
      OR l.labstdcode IN ('0531101', '0531102')
    )
) x;

-- MissingDiagnosis
SELECT COUNT(*)
FROM visit v
LEFT JOIN visitdiag d
  ON d.pcucode = v.pcucode
 AND d.visitno = v.visitno
WHERE v.visitdate = ?
  AND d.visitno IS NULL;

-- AncVisits
SELECT COUNT(*)
FROM visitanc a
WHERE a.datecheck = ?;

-- VaccineVisits
SELECT COUNT(*)
FROM visitepi e
WHERE e.dateepi = ?;

-- HomeVisits
SELECT COUNT(DISTINCT h.pcucode, h.visitno)
FROM visithomehealthindividual h
JOIN visit v
  ON v.pcucode = h.pcucode
 AND v.visitno = h.visitno
WHERE v.visitdate = ?;

-- ReferOut
SELECT COUNT(*)
FROM visitrefer r
WHERE DATE(r.datetimerefer) = ?;

-- EmergencyCases
-- JHCIS has visit.typein with comment: 4 = EMS. Adjust if local site uses another ER flag.
SELECT COUNT(*)
FROM visit v
WHERE v.visitdate = ?
  AND v.typein = '4';
