-- JHCIS disease group queries.
-- Parameter style: ? is report_date in yyyy-MM-dd format.
-- Counts distinct patients who had a visit diagnosis on the report date.
--
-- Verify local ICD-10 usage before production, especially vaping-related lung disease.

-- 5-year daily history by disease group.
-- Set @end_date to the last date you want to import.
SET @end_date = CURDATE();
SET @start_date = DATE_SUB(@end_date, INTERVAL 5 YEAR);

SELECT DATE_FORMAT(v.visitdate, '%Y-%m-%d') AS report_date,
       'ไขมันในเลือดสูง' AS disease_group,
       COUNT(DISTINCT v.pcucodeperson, v.pid) AS patients
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND d.diagcode REGEXP '^E78'
GROUP BY v.visitdate

UNION ALL
SELECT DATE_FORMAT(v.visitdate, '%Y-%m-%d'), 'ปอดอักเสบจากการสูบบุหรี่ไฟฟ้า', COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND (
    d.diagcode REGEXP '^U07\\.0'
    OR d.diagcode REGEXP '^J68\\.0'
    OR d.diagcode REGEXP '^J69\\.1'
  )
GROUP BY v.visitdate

UNION ALL
SELECT DATE_FORMAT(v.visitdate, '%Y-%m-%d'), 'หลอดเลือดหัวใจ', COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND d.diagcode REGEXP '^I2[0-5]'
GROUP BY v.visitdate

UNION ALL
SELECT DATE_FORMAT(v.visitdate, '%Y-%m-%d'), 'หลอดเลือดสมอง', COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND d.diagcode REGEXP '^I6[0-9]'
GROUP BY v.visitdate

UNION ALL
SELECT DATE_FORMAT(v.visitdate, '%Y-%m-%d'), 'สุขภาพจิต', COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND d.diagcode REGEXP '^F[0-9][0-9]'
GROUP BY v.visitdate

UNION ALL
SELECT DATE_FORMAT(v.visitdate, '%Y-%m-%d'), 'มะเร็งทุกชนิด', COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND (
    d.diagcode REGEXP '^C[0-9][0-9]'
    OR d.diagcode REGEXP '^D0[0-9]'
    OR d.diagcode REGEXP '^D[1-3][0-9]'
    OR d.diagcode REGEXP '^D4[0-8]'
  )
GROUP BY v.visitdate

UNION ALL
SELECT DATE_FORMAT(v.visitdate, '%Y-%m-%d'), 'เบาหวาน', COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND d.diagcode REGEXP '^E1[0-4]'
GROUP BY v.visitdate

UNION ALL
SELECT DATE_FORMAT(v.visitdate, '%Y-%m-%d'), 'ไอควาย', COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND d.diagcode REGEXP '^A37'
GROUP BY v.visitdate

UNION ALL
SELECT DATE_FORMAT(v.visitdate, '%Y-%m-%d'), 'ความดันโลหิตสูง', COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND d.diagcode REGEXP '^I1[0-5]'
GROUP BY v.visitdate

UNION ALL
SELECT DATE_FORMAT(v.visitdate, '%Y-%m-%d'), 'ถุงลมโป่งพองเรื้อรัง', COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND (
    d.diagcode REGEXP '^J43'
    OR d.diagcode REGEXP '^J44'
  )
GROUP BY v.visitdate
ORDER BY report_date, disease_group;

-- Summary by disease group
SELECT 'ไขมันในเลือดสูง' AS disease_group, COUNT(DISTINCT v.pcucodeperson, v.pid) AS patients
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ? AND d.diagcode REGEXP '^E78'

UNION ALL
SELECT 'ปอดอักเสบจากการสูบบุหรี่ไฟฟ้า' AS disease_group, COUNT(DISTINCT v.pcucodeperson, v.pid) AS patients
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ? AND (
  d.diagcode REGEXP '^U07\\.0'
  OR d.diagcode REGEXP '^J68\\.0'
  OR d.diagcode REGEXP '^J69\\.1'
)

UNION ALL
SELECT 'หลอดเลือดหัวใจ' AS disease_group, COUNT(DISTINCT v.pcucodeperson, v.pid) AS patients
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ? AND d.diagcode REGEXP '^I2[0-5]'

UNION ALL
SELECT 'หลอดเลือดสมอง' AS disease_group, COUNT(DISTINCT v.pcucodeperson, v.pid) AS patients
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ? AND d.diagcode REGEXP '^I6[0-9]'

UNION ALL
SELECT 'สุขภาพจิต' AS disease_group, COUNT(DISTINCT v.pcucodeperson, v.pid) AS patients
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ? AND d.diagcode REGEXP '^F[0-9][0-9]'

UNION ALL
SELECT 'มะเร็งทุกชนิด' AS disease_group, COUNT(DISTINCT v.pcucodeperson, v.pid) AS patients
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ? AND (
  d.diagcode REGEXP '^C[0-9][0-9]'
  OR d.diagcode REGEXP '^D0[0-9]'
  OR d.diagcode REGEXP '^D[1-3][0-9]'
  OR d.diagcode REGEXP '^D4[0-8]'
)

UNION ALL
SELECT 'เบาหวาน' AS disease_group, COUNT(DISTINCT v.pcucodeperson, v.pid) AS patients
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ? AND d.diagcode REGEXP '^E1[0-4]'

UNION ALL
SELECT 'ไอควาย' AS disease_group, COUNT(DISTINCT v.pcucodeperson, v.pid) AS patients
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ? AND d.diagcode REGEXP '^A37'

UNION ALL
SELECT 'ความดันโลหิตสูง' AS disease_group, COUNT(DISTINCT v.pcucodeperson, v.pid) AS patients
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ? AND d.diagcode REGEXP '^I1[0-5]'

UNION ALL
SELECT 'ถุงลมโป่งพองเรื้อรัง' AS disease_group, COUNT(DISTINCT v.pcucodeperson, v.pid) AS patients
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ? AND (
  d.diagcode REGEXP '^J43'
  OR d.diagcode REGEXP '^J44'
);

-- Individual queries

-- ไขมันในเลือดสูง: E78
SELECT COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ?
  AND d.diagcode REGEXP '^E78';

-- ปอดอักเสบจากการสูบบุหรี่ไฟฟ้า: verify local coding.
-- U07.0 is vaping-related disorder in ICD-10-CM; J68.0/J69.1 are fallback respiratory injury codes.
SELECT COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ?
  AND (
    d.diagcode REGEXP '^U07\\.0'
    OR d.diagcode REGEXP '^J68\\.0'
    OR d.diagcode REGEXP '^J69\\.1'
  );

-- หลอดเลือดหัวใจ: I20-I25
SELECT COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ?
  AND d.diagcode REGEXP '^I2[0-5]';

-- หลอดเลือดสมอง: I60-I69
SELECT COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ?
  AND d.diagcode REGEXP '^I6[0-9]';

-- สุขภาพจิต: F00-F99
SELECT COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ?
  AND d.diagcode REGEXP '^F[0-9][0-9]';

-- มะเร็งทุกชนิด: C00-D48
SELECT COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ?
  AND (
    d.diagcode REGEXP '^C[0-9][0-9]'
    OR d.diagcode REGEXP '^D0[0-9]'
    OR d.diagcode REGEXP '^D[1-3][0-9]'
    OR d.diagcode REGEXP '^D4[0-8]'
  );

-- เบาหวาน: E10-E14
SELECT COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ?
  AND d.diagcode REGEXP '^E1[0-4]';

-- ไอควาย: A37
SELECT COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ?
  AND d.diagcode REGEXP '^A37';

-- ความดันโลหิตสูง: I10-I15
SELECT COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ?
  AND d.diagcode REGEXP '^I1[0-5]';

-- ถุงลมโป่งพองเรื้อรัง: J43-J44
SELECT COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno
WHERE v.visitdate = ?
  AND (
    d.diagcode REGEXP '^J43'
    OR d.diagcode REGEXP '^J44'
  );
