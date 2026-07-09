param(
  [string]$DbHost = "76.13.185.54",
  [int]$DbPort = 32772,
  [string]$DbUser = "suphot",
  [string]$DbName = "jhcisdb03633",
  [string]$StartDate = (Get-Date).AddYears(-5).ToString("yyyy-MM-dd"),
  [string]$EndDate = (Get-Date).ToString("yyyy-MM-dd"),
  [string]$FacilityId = "03633",
  [string]$FacilityName = "JHCIS 03633",
  [string]$CentralApiUrl = "http://s14gjbvbsnmq1r2v3ujwh8nu.110.164.222.217.sslip.io/api/v1/etl/summary",
  [string]$CentralLocationsApiUrl = "http://s14gjbvbsnmq1r2v3ujwh8nu.110.164.222.217.sslip.io/api/v1/etl/ncd-house-locations",
  [string]$JwtSecret = "change_this_to_a_long_random_secret",
  [string]$JwtIssuer = "rpst-etl",
  [string]$JwtAudience = "rpst-central-api",
  [string]$MySqlClientPath = "",
  [string]$WorkDir = "",
  [switch]$SkipLocations
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
if ([string]::IsNullOrWhiteSpace($WorkDir)) {
  $WorkDir = Join-Path $RootDir "..\..\work"
}
$WorkDir = [System.IO.Path]::GetFullPath($WorkDir)
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$workDrive = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($WorkDir))
$minimumFreeBytes = 512MB
if ($workDrive.AvailableFreeSpace -lt $minimumFreeBytes) {
  throw "Not enough free disk space for WorkDir '$WorkDir'. Free space: $([Math]::Round($workDrive.AvailableFreeSpace / 1MB, 1)) MB. Use -WorkDir on another drive, for example -WorkDir 'D:\rpst-work'."
}

function ConvertTo-Base64Url {
  param([byte[]]$Bytes)
  return [Convert]::ToBase64String($Bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

function New-Jwt {
  param(
    [string]$Secret,
    [string]$Issuer,
    [string]$Audience,
    [string]$FacilityId
  )
  $epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $encoding = [Text.Encoding]::UTF8
  $header = @{ alg = "HS256"; typ = "JWT" } | ConvertTo-Json -Compress
  $payload = @{
    iss = $Issuer
    aud = $Audience
    iat = $epoch
    exp = $epoch + 300
    facility_id = $FacilityId
    scope = "etl:write"
  } | ConvertTo-Json -Compress
  $unsigned = "$(ConvertTo-Base64Url ($encoding.GetBytes($header))).$(ConvertTo-Base64Url ($encoding.GetBytes($payload)))"
  $hmac = New-Object System.Security.Cryptography.HMACSHA256
  $hmac.Key = $encoding.GetBytes($Secret)
  $signature = ConvertTo-Base64Url ($hmac.ComputeHash($encoding.GetBytes($unsigned)))
  return "$unsigned.$signature"
}

function New-PatientHash {
  param(
    [string]$Secret,
    [string]$FacilityId,
    [string]$PatientKey
  )
  $encoding = [Text.Encoding]::UTF8
  $hmac = New-Object System.Security.Cryptography.HMACSHA256
  $hmac.Key = $encoding.GetBytes($Secret)
  $hashBytes = $hmac.ComputeHash($encoding.GetBytes("$FacilityId|$PatientKey"))
  return ([BitConverter]::ToString($hashBytes)).Replace("-", "").ToLowerInvariant()
}

function Read-Secret {
  param([string]$Prompt)
  $secure = Read-Host -Prompt $Prompt -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  }
  finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

function Get-MySqlClientCommand {
  param([string]$ExplicitPath)
  if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
    if (-not (Test-Path -LiteralPath $ExplicitPath)) {
      throw "MySQL client not found at '$ExplicitPath'."
    }
    return [pscustomobject]@{ Kind = "mysql"; Command = (Resolve-Path $ExplicitPath).Path }
  }

  $mysql = Get-Command mysql -ErrorAction SilentlyContinue
  if ($null -ne $mysql) {
    return [pscustomobject]@{ Kind = "mysql"; Command = $mysql.Source }
  }

  $docker = Get-Command docker -ErrorAction SilentlyContinue
  if ($null -ne $docker) {
    return [pscustomobject]@{ Kind = "docker"; Command = $docker.Source }
  }

  throw "Cannot find mysql.exe or docker. Install MySQL Client and add mysql.exe to PATH, or install Docker Desktop."
}

function Invoke-MySqlFile {
  param(
    [string]$SqlPath,
    [string]$OutPath,
    [string]$Password,
    [string]$EnvPath
  )

  $runner = Get-MySqlClientCommand $MySqlClientPath
  $errorPath = Join-Path $WorkDir "jhcis-history-mysql-error.log"
  Remove-Item -LiteralPath $OutPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $errorPath -Force -ErrorAction SilentlyContinue

  if ($runner.Kind -eq "mysql") {
    $oldPassword = $env:MYSQL_PWD
    $mysqlSqlPath = $SqlPath.Replace("\", "/")
    try {
      $env:MYSQL_PWD = $Password
      & $runner.Command `
        -h $DbHost -P $DbPort -u $DbUser -D $DbName --connect-timeout=20 `
        --batch --raw --default-character-set=utf8 `
        -e "source $mysqlSqlPath" > $OutPath 2> $errorPath

      if ($LASTEXITCODE -ne 0) {
        $errorText = if (Test-Path -LiteralPath $errorPath) { Get-Content -Path $errorPath -Raw -Encoding UTF8 } else { "" }
        throw "mysql.exe failed with exit code $LASTEXITCODE. $errorText"
      }
    }
    finally {
      if ($null -eq $oldPassword) {
        Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
      }
      else {
        $env:MYSQL_PWD = $oldPassword
      }
    }
    return
  }

  Set-Content -Path $EnvPath -Value "MYSQL_PWD=$Password" -Encoding ASCII
  try {
    $dockerSqlFile = Split-Path -Leaf $SqlPath
    & $runner.Command run --rm --env-file $EnvPath -v "${WorkDir}:/work" mysql:8.0 mysql `
      -h $DbHost -P $DbPort -u $DbUser -D $DbName --connect-timeout=20 `
      --batch --raw --default-character-set=utf8 `
      -e "source /work/$dockerSqlFile" > $OutPath 2> $errorPath

    if ($LASTEXITCODE -ne 0) {
      $errorText = if (Test-Path -LiteralPath $errorPath) { Get-Content -Path $errorPath -Raw -Encoding UTF8 } else { "" }
      throw "docker/mysql failed with exit code $LASTEXITCODE. $errorText"
    }
  }
  finally {
    Remove-Item -LiteralPath $EnvPath -Force -ErrorAction SilentlyContinue
  }

  if (-not (Test-Path -LiteralPath $OutPath)) {
    throw "MySQL command finished but result file was not created: $OutPath"
  }
}

function Set-Utf8NoBomContent {
  param(
    [string]$Path,
    [string]$Value
  )
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Value, $encoding)
}

$dbPassword = $env:JHCIS_DB_PASSWORD
if ([string]::IsNullOrWhiteSpace($dbPassword)) {
  $dbPassword = Read-Secret "JHCIS DB password"
}

$sqlPath = Join-Path $WorkDir "jhcis-history-import.sql"
$facilitySqlPath = Join-Path $WorkDir "jhcis-facility-info.sql"
$locationSqlPath = Join-Path $WorkDir "jhcis-history-locations.sql"
$locationDiagnosticSqlPath = Join-Path $WorkDir "jhcis-history-location-diagnostics.sql"
$envPath = Join-Path $WorkDir "jhcis-history-mysql.env"
$outPath = Join-Path $WorkDir "jhcis-history-result.tsv"
$facilityOutPath = Join-Path $WorkDir "jhcis-facility-info.tsv"
$locationOutPath = Join-Path $WorkDir "jhcis-history-locations.tsv"
$locationDiagnosticOutPath = Join-Path $WorkDir "jhcis-history-location-diagnostics.tsv"

$facilitySql = @"
SELECT
  office.offid,
  chospital.hosname,
  chospital.hostype,
  chospital.address,
  chospital.road,
  chospital.mu,
  chospital.subdistcode,
  chospital.distcode,
  chospital.provcode,
  cprovince.provname,
  cdistrict.distname,
  csubdistrict.subdistname
FROM office
INNER JOIN chospital ON office.offid = chospital.hoscode
INNER JOIN cprovince ON chospital.provcode = cprovince.provcode
INNER JOIN cdistrict ON chospital.provcode = cdistrict.provcode AND chospital.distcode = cdistrict.distcode
INNER JOIN csubdistrict ON chospital.provcode = csubdistrict.provcode AND chospital.distcode = csubdistrict.distcode AND chospital.subdistcode = csubdistrict.subdistcode
LIMIT 1;
"@

Set-Utf8NoBomContent $facilitySqlPath $facilitySql
Invoke-MySqlFile $facilitySqlPath $facilityOutPath $dbPassword $envPath

$facilityInfo = @{
  facility_id = $FacilityId
  facility_name = $FacilityName
  subdistrict = $null
  district = $null
  province = $null
}
$facilityLines = Get-Content -Path $facilityOutPath -Encoding UTF8
if ($facilityLines.Count -ge 2) {
  $facilityHeaders = $facilityLines[0] -split "`t"
  $facilityParts = $facilityLines[1] -split "`t", $facilityHeaders.Count
  $facilityRecord = @{}
  for ($i = 0; $i -lt $facilityHeaders.Count; $i++) {
    $facilityRecord[$facilityHeaders[$i]] = $facilityParts[$i]
  }
  if (-not [string]::IsNullOrWhiteSpace($facilityRecord.offid)) {
    $facilityInfo.facility_id = $facilityRecord.offid
  }
  if (-not [string]::IsNullOrWhiteSpace($facilityRecord.hosname)) {
    $facilityInfo.facility_name = $facilityRecord.hosname
  }
  $facilityInfo.subdistrict = $facilityRecord.subdistname
  $facilityInfo.district = $facilityRecord.distname
  $facilityInfo.province = $facilityRecord.provname
}
$EffectiveFacilityId = $facilityInfo.facility_id

$sql = @"
SET @start_date = '$StartDate';
SET @end_date = '$EndDate';

DROP TEMPORARY TABLE IF EXISTS rpst_pingpong_daily;
CREATE TEMPORARY TABLE rpst_pingpong_daily AS
SELECT
  report_date,
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
    DATE_FORMAT(v.visitdate, '%Y-%m-%d') AS report_date,
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
  WHERE v.visitdate BETWEEN @start_date AND @end_date
  GROUP BY v.visitdate, v.pcucodeperson, v.pid
) classified;

SELECT 'total_visits' AS metric, DATE_FORMAT(visitdate, '%Y-%m-%d') AS report_date, COUNT(*) AS value
FROM visit
WHERE visitdate BETWEEN @start_date AND @end_date
GROUP BY visitdate
UNION ALL
SELECT 'unique_patients', DATE_FORMAT(visitdate, '%Y-%m-%d'), COUNT(DISTINCT pcucodeperson, pid)
FROM visit
WHERE visitdate BETWEEN @start_date AND @end_date
GROUP BY visitdate
UNION ALL
SELECT 'chronic_followups', DATE_FORMAT(v.visitdate, '%Y-%m-%d'), COUNT(DISTINCT v.pcucode, v.visitno)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND (dg.diagcode REGEXP '^E1[0-4]' OR dg.diagcode REGEXP '^I1[0-5]')
GROUP BY v.visitdate
UNION ALL
SELECT 'ncd_dm_patients', DATE_FORMAT(v.visitdate, '%Y-%m-%d'), COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND dg.diagcode REGEXP '^E1[0-4]'
GROUP BY v.visitdate
UNION ALL
SELECT 'ncd_ht_patients', DATE_FORMAT(v.visitdate, '%Y-%m-%d'), COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND dg.diagcode REGEXP '^I1[0-5]'
GROUP BY v.visitdate
UNION ALL
SELECT 'ncd_dm_ht_patients', DATE_FORMAT(v.visitdate, '%Y-%m-%d'), COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND (dg.diagcode REGEXP '^E1[0-4]' OR dg.diagcode REGEXP '^I1[0-5]')
GROUP BY v.visitdate
UNION ALL
SELECT 'ncd_bp_screened', DATE_FORMAT(visitdate, '%Y-%m-%d'), COUNT(DISTINCT pcucodeperson, pid)
FROM visit
WHERE visitdate BETWEEN @start_date AND @end_date
  AND (NULLIF(TRIM(pressure), '') IS NOT NULL OR NULLIF(TRIM(pressure2), '') IS NOT NULL)
GROUP BY visitdate
UNION ALL
SELECT 'ncd_fbs_screened', DATE_FORMAT(report_date, '%Y-%m-%d'), COUNT(DISTINCT pid)
FROM (
  SELECT screen_date AS report_date, CAST(pid AS CHAR) AS pid
  FROM ncd_person_ncd_screen
  WHERE screen_date BETWEEN @start_date AND @end_date
    AND bsl IS NOT NULL
    AND bsl > 0
  UNION
  SELECT STR_TO_DATE(date_serv, '%Y%m%d') AS report_date, CAST(pid AS CHAR) AS pid
  FROM ncdlab
  WHERE date_serv BETWEEN DATE_FORMAT(@start_date, '%Y%m%d') AND DATE_FORMAT(@end_date, '%Y%m%d')
    AND (
      testname LIKE '%FBS%'
      OR testname LIKE '%FAST%'
      OR testname LIKE '%SUGAR%'
      OR labstdcode IN ('0531101', '0531102')
    )
) f
GROUP BY report_date
UNION ALL
SELECT 'missing_diagnosis', DATE_FORMAT(v.visitdate, '%Y-%m-%d'), COUNT(*)
FROM visit v
LEFT JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND dg.visitno IS NULL
GROUP BY v.visitdate
UNION ALL
SELECT 'anc_visits', DATE_FORMAT(datecheck, '%Y-%m-%d'), COUNT(*)
FROM visitanc
WHERE datecheck BETWEEN @start_date AND @end_date
GROUP BY datecheck
UNION ALL
SELECT 'vaccine_visits', DATE_FORMAT(dateepi, '%Y-%m-%d'), COUNT(*)
FROM visitepi
WHERE dateepi BETWEEN @start_date AND @end_date
GROUP BY dateepi
UNION ALL
SELECT 'home_visits', DATE_FORMAT(v.visitdate, '%Y-%m-%d'), COUNT(DISTINCT h.pcucode, h.visitno)
FROM visithomehealthindividual h
JOIN visit v ON v.pcucode = h.pcucode AND v.visitno = h.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
GROUP BY v.visitdate
UNION ALL
SELECT 'refer_out', DATE_FORMAT(DATE(datetimerefer), '%Y-%m-%d'), COUNT(*)
FROM visitrefer
WHERE DATE(datetimerefer) BETWEEN @start_date AND @end_date
GROUP BY DATE(datetimerefer)
UNION ALL
SELECT 'emergency_cases', DATE_FORMAT(visitdate, '%Y-%m-%d'), COUNT(*)
FROM visit
WHERE visitdate BETWEEN @start_date AND @end_date
  AND typein = '4'
GROUP BY visitdate
UNION ALL
SELECT 'disease_dyslipidemia', DATE_FORMAT(v.visitdate, '%Y-%m-%d'), COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND dg.diagcode REGEXP '^E78'
GROUP BY v.visitdate
UNION ALL
SELECT 'disease_vaping_lung_injury', DATE_FORMAT(v.visitdate, '%Y-%m-%d'), COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND (
    dg.diagcode REGEXP '^U07\\.0'
    OR dg.diagcode REGEXP '^J68\\.0'
    OR dg.diagcode REGEXP '^J69\\.1'
  )
GROUP BY v.visitdate
UNION ALL
SELECT 'disease_coronary_artery', DATE_FORMAT(v.visitdate, '%Y-%m-%d'), COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND dg.diagcode REGEXP '^I2[0-5]'
GROUP BY v.visitdate
UNION ALL
SELECT 'disease_stroke', DATE_FORMAT(v.visitdate, '%Y-%m-%d'), COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND dg.diagcode REGEXP '^I6[0-9]'
GROUP BY v.visitdate
UNION ALL
SELECT 'disease_mental_health', DATE_FORMAT(v.visitdate, '%Y-%m-%d'), COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND dg.diagcode REGEXP '^F[0-9][0-9]'
GROUP BY v.visitdate
UNION ALL
SELECT 'disease_cancer', DATE_FORMAT(v.visitdate, '%Y-%m-%d'), COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND (
    dg.diagcode REGEXP '^C[0-9][0-9]'
    OR dg.diagcode REGEXP '^D0[0-9]'
    OR dg.diagcode REGEXP '^D[1-3][0-9]'
    OR dg.diagcode REGEXP '^D4[0-8]'
  )
GROUP BY v.visitdate
UNION ALL
SELECT 'disease_diabetes', DATE_FORMAT(v.visitdate, '%Y-%m-%d'), COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND dg.diagcode REGEXP '^E1[0-4]'
GROUP BY v.visitdate
UNION ALL
SELECT 'disease_pertussis', DATE_FORMAT(v.visitdate, '%Y-%m-%d'), COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND dg.diagcode REGEXP '^A37'
GROUP BY v.visitdate
UNION ALL
SELECT 'disease_hypertension', DATE_FORMAT(v.visitdate, '%Y-%m-%d'), COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND dg.diagcode REGEXP '^I1[0-5]'
GROUP BY v.visitdate
UNION ALL
SELECT 'disease_copd_emphysema', DATE_FORMAT(v.visitdate, '%Y-%m-%d'), COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND (
    dg.diagcode REGEXP '^J43'
    OR dg.diagcode REGEXP '^J44'
  )
GROUP BY v.visitdate
UNION ALL
SELECT CONCAT('pingpong_', color_key), report_date, COUNT(*)
FROM rpst_pingpong_daily
WHERE color_key IS NOT NULL
GROUP BY report_date, color_key
ORDER BY report_date, metric;
"@

Set-Utf8NoBomContent $sqlPath $sql
Invoke-MySqlFile $sqlPath $outPath $dbPassword $envPath

$locationsByDate = @{}
if (-not $SkipLocations -and -not [string]::IsNullOrWhiteSpace($CentralLocationsApiUrl)) {
  $locationSql = @"
SET @start_date = '$StartDate';
SET @end_date = '$EndDate';

SELECT DISTINCT
  DATE_FORMAT(v.visitdate, '%Y-%m-%d') AS report_date,
  CONCAT(v.pcucodeperson, ':', v.pid) AS patient_key,
  v.pcucodeperson,
  v.pid,
  CASE
    WHEN dg.diagcode REGEXP '^E1[0-4]' THEN 'DM'
    WHEN dg.diagcode REGEXP '^I1[0-5]' THEN 'HT'
    ELSE 'NCD'
  END AS disease_group,
  colored.color_key,
  CAST(TRIM(h.xgis) AS DECIMAL(10,7)) AS latitude,
  CAST(TRIM(h.ygis) AS DECIMAL(10,7)) AS longitude
FROM visit v
JOIN visitdiag dg
  ON dg.pcucode = v.pcucode
 AND dg.visitno = v.visitno
JOIN person p
  ON p.pcucodeperson = v.pcucodeperson
 AND p.pid = v.pid
JOIN house h
  ON h.pcucode = p.pcucodeperson
 AND h.hcode = p.hcode
LEFT JOIN (
  SELECT
    report_date,
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
      v2.visitdate AS report_date,
      CONCAT(v2.pcucodeperson, ':', v2.pid) AS patient_key,
      MAX(CASE WHEN s.bsl IS NOT NULL AND s.bsl > 0 THEN CAST(s.bsl AS UNSIGNED) ELSE NULL END) AS max_fbs,
      MAX(CASE
        WHEN TRIM(v2.pressure) REGEXP '^[0-9]+(/[0-9]+)?$' THEN CAST(SUBSTRING_INDEX(TRIM(v2.pressure), '/', 1) AS UNSIGNED)
        WHEN TRIM(v2.pressure2) REGEXP '^[0-9]+(/[0-9]+)?$' THEN CAST(SUBSTRING_INDEX(TRIM(v2.pressure2), '/', 1) AS UNSIGNED)
        ELSE NULL
      END) AS max_sbp,
      MAX(CASE
        WHEN dg2.diagcode REGEXP '^E1[0-4]\\.[2-8]'
          OR dg2.diagcode REGEXP '^N18'
          OR dg2.diagcode REGEXP '^N08'
          OR dg2.diagcode REGEXP '^H36'
          OR dg2.diagcode REGEXP '^L97'
          OR dg2.diagcode REGEXP '^I7[0-9]'
        THEN 1 ELSE 0
      END) AS has_complication
    FROM visit v2
    JOIN visitdiag dm2
      ON dm2.pcucode = v2.pcucode
     AND dm2.visitno = v2.visitno
     AND dm2.diagcode REGEXP '^E1[0-4]'
    LEFT JOIN visitdiag dg2
      ON dg2.pcucode = v2.pcucode
     AND dg2.visitno = v2.visitno
    LEFT JOIN ncd_person_ncd_screen s
      ON s.pid = v2.pid
     AND s.screen_date = v2.visitdate
    WHERE v2.visitdate BETWEEN @start_date AND @end_date
    GROUP BY v2.visitdate, v2.pcucodeperson, v2.pid
  ) patient_day
) colored
  ON colored.report_date = v.visitdate
 AND colored.patient_key = CONCAT(v.pcucodeperson, ':', v.pid)
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND (
    dg.diagcode REGEXP '^E1[0-4]'
    OR dg.diagcode REGEXP '^I1[0-5]'
  )
  AND TRIM(h.ygis) REGEXP '^-?[0-9]+(\\.[0-9]+)?$'
  AND TRIM(h.xgis) REGEXP '^-?[0-9]+(\\.[0-9]+)?$'
  AND CAST(TRIM(h.xgis) AS DECIMAL(10,7)) BETWEEN 5 AND 21
  AND CAST(TRIM(h.ygis) AS DECIMAL(10,7)) BETWEEN 97 AND 106
ORDER BY report_date, patient_key, disease_group;
"@

  Set-Utf8NoBomContent $locationSqlPath $locationSql
  Invoke-MySqlFile $locationSqlPath $locationOutPath $dbPassword $envPath

  $locationLines = Get-Content -Path $locationOutPath -Encoding UTF8
  if ($locationLines.Count -ge 2) {
    $locationHeaders = $locationLines[0] -split "`t"
    foreach ($requiredHeader in @("report_date", "patient_key", "disease_group", "latitude", "longitude")) {
      if ($locationHeaders -notcontains $requiredHeader) {
        throw "Location SQL returned unexpected columns. Missing '$requiredHeader'. Check $locationOutPath and $locationSqlPath."
      }
    }
    foreach ($line in $locationLines[1..($locationLines.Count - 1)]) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      $parts = $line -split "`t", $locationHeaders.Count
      $record = @{}
      for ($i = 0; $i -lt $locationHeaders.Count; $i++) {
        $record[$locationHeaders[$i]] = $parts[$i]
      }
      $dateKey = $record.report_date
      if (-not $locationsByDate.ContainsKey($dateKey)) {
        $locationsByDate[$dateKey] = New-Object System.Collections.ArrayList
      }
      [void]$locationsByDate[$dateKey].Add($record)
    }
  }

  if ($locationsByDate.Count -eq 0) {
    $locationDiagnosticSql = @"
SET @start_date = '$StartDate';
SET @end_date = '$EndDate';

SELECT 'ncd_visit_patients' AS metric, COUNT(DISTINCT v.pcucodeperson, v.pid) AS value
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND (dg.diagcode REGEXP '^E1[0-4]' OR dg.diagcode REGEXP '^I1[0-5]')
UNION ALL
SELECT 'ncd_person_join_patients', COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
JOIN person p ON p.pcucodeperson = v.pcucodeperson AND p.pid = v.pid
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND (dg.diagcode REGEXP '^E1[0-4]' OR dg.diagcode REGEXP '^I1[0-5]')
UNION ALL
SELECT 'ncd_house_join_patients', COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
JOIN person p ON p.pcucodeperson = v.pcucodeperson AND p.pid = v.pid
JOIN house h ON h.pcucode = p.pcucodeperson AND h.hcode = p.hcode
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND (dg.diagcode REGEXP '^E1[0-4]' OR dg.diagcode REGEXP '^I1[0-5]')
UNION ALL
SELECT 'houses_with_numeric_xy', COUNT(*)
FROM house h
WHERE TRIM(h.ygis) REGEXP '^-?[0-9]+(\\.[0-9]+)?$'
  AND TRIM(h.xgis) REGEXP '^-?[0-9]+(\\.[0-9]+)?$'
UNION ALL
SELECT 'ncd_house_numeric_xy_patients', COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
JOIN person p ON p.pcucodeperson = v.pcucodeperson AND p.pid = v.pid
JOIN house h ON h.pcucode = p.pcucodeperson AND h.hcode = p.hcode
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND (dg.diagcode REGEXP '^E1[0-4]' OR dg.diagcode REGEXP '^I1[0-5]')
  AND TRIM(h.ygis) REGEXP '^-?[0-9]+(\\.[0-9]+)?$'
  AND TRIM(h.xgis) REGEXP '^-?[0-9]+(\\.[0-9]+)?$'
UNION ALL
SELECT 'ncd_house_y_lat_x_lng_patients', COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
JOIN person p ON p.pcucodeperson = v.pcucodeperson AND p.pid = v.pid
JOIN house h ON h.pcucode = p.pcucodeperson AND h.hcode = p.hcode
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND (dg.diagcode REGEXP '^E1[0-4]' OR dg.diagcode REGEXP '^I1[0-5]')
  AND TRIM(h.ygis) REGEXP '^-?[0-9]+(\\.[0-9]+)?$'
  AND TRIM(h.xgis) REGEXP '^-?[0-9]+(\\.[0-9]+)?$'
  AND CAST(TRIM(h.ygis) AS DECIMAL(10,7)) BETWEEN 5 AND 21
  AND CAST(TRIM(h.xgis) AS DECIMAL(10,7)) BETWEEN 97 AND 106
UNION ALL
SELECT 'ncd_house_x_lat_y_lng_patients', COUNT(DISTINCT v.pcucodeperson, v.pid)
FROM visit v
JOIN visitdiag dg ON dg.pcucode = v.pcucode AND dg.visitno = v.visitno
JOIN person p ON p.pcucodeperson = v.pcucodeperson AND p.pid = v.pid
JOIN house h ON h.pcucode = p.pcucodeperson AND h.hcode = p.hcode
WHERE v.visitdate BETWEEN @start_date AND @end_date
  AND (dg.diagcode REGEXP '^E1[0-4]' OR dg.diagcode REGEXP '^I1[0-5]')
  AND TRIM(h.ygis) REGEXP '^-?[0-9]+(\\.[0-9]+)?$'
  AND TRIM(h.xgis) REGEXP '^-?[0-9]+(\\.[0-9]+)?$'
  AND CAST(TRIM(h.xgis) AS DECIMAL(10,7)) BETWEEN 5 AND 21
  AND CAST(TRIM(h.ygis) AS DECIMAL(10,7)) BETWEEN 97 AND 106;
"@
    Set-Utf8NoBomContent $locationDiagnosticSqlPath $locationDiagnosticSql
    Invoke-MySqlFile $locationDiagnosticSqlPath $locationDiagnosticOutPath $dbPassword $envPath
    Write-Warning "No NCD house location rows returned. Diagnostics written to $locationDiagnosticOutPath"
    Get-Content -Path $locationDiagnosticOutPath -Encoding UTF8 | ForEach-Object { Write-Warning $_ }
  }
}

$lines = Get-Content -Path $outPath -Encoding UTF8
$byDate = @{}

if ($lines.Count -lt 2) {
  Write-Warning "No aggregate rows returned from $DbName between $StartDate and $EndDate. Sending zero values for requested calendar days."
}
else {
  $headers = $lines[0] -split "`t"
  foreach ($line in $lines[1..($lines.Count - 1)]) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line -split "`t", $headers.Count
    $record = @{}
    for ($i = 0; $i -lt $headers.Count; $i++) {
      $record[$headers[$i]] = $parts[$i]
    }
    $dateKey = $record.report_date
    if (-not $byDate.ContainsKey($dateKey)) {
      $byDate[$dateKey] = @{}
    }
    $byDate[$dateKey][$record.metric] = $record.value
  }
}

$start = [DateTime]::ParseExact($StartDate, "yyyy-MM-dd", $null)
$end = [DateTime]::ParseExact($EndDate, "yyyy-MM-dd", $null)
$sent = 0
$failed = 0
$locationSent = 0
$locationFailed = 0
$locationRecordsSent = 0
$locationRecordsSkipped = 0

for ($day = $start; $day -le $end; $day = $day.AddDays(1)) {
  $dateText = $day.ToString("yyyy-MM-dd")
  $row = $byDate[$dateText]
  $token = New-Jwt $JwtSecret $JwtIssuer $JwtAudience $EffectiveFacilityId

  function IntField([string]$name) {
    if ($null -eq $row -or [string]::IsNullOrWhiteSpace($row[$name]) -or $row[$name] -eq "NULL") {
      return 0
    }
    return [int]$row[$name]
  }

  $body = @{
    facility_id = $EffectiveFacilityId
    facility_name = $facilityInfo.facility_name
    subdistrict = $facilityInfo.subdistrict
    district = $facilityInfo.district
    province = $facilityInfo.province
    report_date = $dateText
    total_visits = IntField "total_visits"
    unique_patients = IntField "unique_patients"
    chronic_followups = IntField "chronic_followups"
    ncd_dm_patients = IntField "ncd_dm_patients"
    ncd_ht_patients = IntField "ncd_ht_patients"
    ncd_dm_ht_patients = IntField "ncd_dm_ht_patients"
    ncd_bp_screened = IntField "ncd_bp_screened"
    ncd_fbs_screened = IntField "ncd_fbs_screened"
    missing_diagnosis = IntField "missing_diagnosis"
    anc_visits = IntField "anc_visits"
    vaccine_visits = IntField "vaccine_visits"
    home_visits = IntField "home_visits"
    refer_out = IntField "refer_out"
    emergency_cases = IntField "emergency_cases"
    source_generated_at = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    payload = @{
      source = $DbName
      generated_by = "history-import"
      ncd_definition = "DM=E10-E14, HT=I10-I15"
      import_range = "$StartDate..$EndDate"
      disease_groups = @{
        dyslipidemia = IntField "disease_dyslipidemia"
        vaping_lung_injury = IntField "disease_vaping_lung_injury"
        coronary_artery_disease = IntField "disease_coronary_artery"
        stroke = IntField "disease_stroke"
        mental_health = IntField "disease_mental_health"
        cancer = IntField "disease_cancer"
        diabetes = IntField "disease_diabetes"
        pertussis = IntField "disease_pertussis"
        hypertension = IntField "disease_hypertension"
        copd_emphysema = IntField "disease_copd_emphysema"
      }
      pingpong_7color = @{
        black = IntField "pingpong_black"
        red = IntField "pingpong_red"
        orange = IntField "pingpong_orange"
        yellow = IntField "pingpong_yellow"
        green = IntField "pingpong_green"
        white = IntField "pingpong_white"
      }
    }
  } | ConvertTo-Json -Depth 5

  try {
    Invoke-RestMethod `
      -Method Post `
      -Uri $CentralApiUrl `
      -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json; charset=utf-8" } `
      -Body ([Text.Encoding]::UTF8.GetBytes($body)) `
      -TimeoutSec 30 | Out-Null
    $sent += 1
  }
  catch {
    $failed += 1
    Write-Warning "Failed to send ${dateText}: $($_.Exception.Message)"
  }

  if (-not $SkipLocations -and -not [string]::IsNullOrWhiteSpace($CentralLocationsApiUrl)) {
    $locationRows = @($locationsByDate[$dateText])
    $locations = @()
    foreach ($locationRow in $locationRows) {
      if ($null -eq $locationRow) { continue }
      $latitude = 0.0
      $longitude = 0.0
      if ([string]::IsNullOrWhiteSpace($locationRow.patient_key) `
          -or -not [double]::TryParse(([string]$locationRow.latitude), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$latitude) `
          -or -not [double]::TryParse(([string]$locationRow.longitude), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$longitude)) {
        $locationRecordsSkipped += 1
        continue
      }
      $locations += @{
        patient_hash = New-PatientHash $JwtSecret $EffectiveFacilityId $locationRow.patient_key
        pcucodeperson = $locationRow.pcucodeperson
        pid = [int]$locationRow.pid
        disease_group = $locationRow.disease_group
        latitude = $latitude
        longitude = $longitude
        payload = $(if ([string]::IsNullOrWhiteSpace($locationRow.color_key)) { @{} } else { @{ color_key = $locationRow.color_key } })
      }
    }

    $locationBody = @{
      facility_id = $EffectiveFacilityId
      report_date = $dateText
      source_generated_at = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
      locations = $locations
    } | ConvertTo-Json -Depth 6

    try {
      $locationToken = New-Jwt $JwtSecret $JwtIssuer $JwtAudience $EffectiveFacilityId
      Invoke-RestMethod `
        -Method Post `
        -Uri $CentralLocationsApiUrl `
        -Headers @{ Authorization = "Bearer $locationToken"; "Content-Type" = "application/json; charset=utf-8" } `
        -Body ([Text.Encoding]::UTF8.GetBytes($locationBody)) `
        -TimeoutSec 60 | Out-Null
      $locationSent += 1
      $locationRecordsSent += $locations.Count
    }
    catch {
      $locationFailed += 1
      Write-Warning "Failed to send locations for ${dateText}: $($_.Exception.Message)"
    }
  }
}

[pscustomobject]@{
  database = $DbName
  facility_id = $EffectiveFacilityId
  facility_name = $facilityInfo.facility_name
  subdistrict = $facilityInfo.subdistrict
  district = $facilityInfo.district
  province = $facilityInfo.province
  start_date = $StartDate
  end_date = $EndDate
  aggregate_days_with_data = $byDate.Count
  calendar_days_sent = $sent
  failed = $failed
  location_days_with_data = $locationsByDate.Count
  location_days_sent = $locationSent
  location_records_sent = $locationRecordsSent
  location_records_skipped = $locationRecordsSkipped
  location_failed = $locationFailed
}
