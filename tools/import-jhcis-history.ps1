param(
  [string]$DbHost = "76.13.185.54",
  [int]$DbPort = 32772,
  [string]$DbUser = "suphot",
  [string]$DbName = "jhcisdb03633",
  [string]$StartDate = (Get-Date).AddYears(-5).ToString("yyyy-MM-dd"),
  [string]$EndDate = (Get-Date).ToString("yyyy-MM-dd"),
  [string]$FacilityId = "03633",
  [string]$FacilityName = "JHCIS 03633",
  [string]$CentralApiUrl = "http://localhost:8080/api/v1/etl/summary",
  [string]$JwtSecret = "change_this_to_a_long_random_secret",
  [string]$JwtIssuer = "rpst-etl",
  [string]$JwtAudience = "rpst-central-api",
  [string]$MySqlClientPath = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$WorkDir = Join-Path $RootDir "..\..\work"
$WorkDir = [System.IO.Path]::GetFullPath($WorkDir)
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

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
  if ($runner.Kind -eq "mysql") {
    $oldPassword = $env:MYSQL_PWD
    try {
      $env:MYSQL_PWD = $Password
      & $runner.Command `
        -h $DbHost -P $DbPort -u $DbUser -D $DbName --connect-timeout=20 `
        --batch --raw --default-character-set=utf8 `
        -e "source $SqlPath" | Set-Content -Path $OutPath -Encoding UTF8
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
    & $runner.Command run --rm --env-file $EnvPath -v "${WorkDir}:/work" mysql:8.0 mysql `
      -h $DbHost -P $DbPort -u $DbUser -D $DbName --connect-timeout=20 `
      --batch --raw --default-character-set=utf8 `
      -e "source /work/jhcis-history-import.sql" | Set-Content -Path $OutPath -Encoding UTF8
  }
  finally {
    Remove-Item -LiteralPath $EnvPath -Force -ErrorAction SilentlyContinue
  }
}

$dbPassword = $env:JHCIS_DB_PASSWORD
if ([string]::IsNullOrWhiteSpace($dbPassword)) {
  $dbPassword = Read-Secret "JHCIS DB password"
}

$sqlPath = Join-Path $WorkDir "jhcis-history-import.sql"
$envPath = Join-Path $WorkDir "jhcis-history-mysql.env"
$outPath = Join-Path $WorkDir "jhcis-history-result.tsv"

$sql = @"
SET @start_date = '$StartDate';
SET @end_date = '$EndDate';

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
ORDER BY report_date, metric;
"@

Set-Content -Path $sqlPath -Value $sql -Encoding UTF8
Invoke-MySqlFile $sqlPath $outPath $dbPassword $envPath

$lines = Get-Content -Path $outPath -Encoding UTF8
if ($lines.Count -lt 2) {
  throw "No aggregate rows returned from $DbName between $StartDate and $EndDate."
}

$headers = $lines[0] -split "`t"
$byDate = @{}
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

$start = [DateTime]::ParseExact($StartDate, "yyyy-MM-dd", $null)
$end = [DateTime]::ParseExact($EndDate, "yyyy-MM-dd", $null)
$sent = 0
$failed = 0

for ($day = $start; $day -le $end; $day = $day.AddDays(1)) {
  $dateText = $day.ToString("yyyy-MM-dd")
  $row = $byDate[$dateText]
  $token = New-Jwt $JwtSecret $JwtIssuer $JwtAudience $FacilityId

  function IntField([string]$name) {
    if ($null -eq $row -or [string]::IsNullOrWhiteSpace($row[$name]) -or $row[$name] -eq "NULL") {
      return 0
    }
    return [int]$row[$name]
  }

  $body = @{
    facility_id = $FacilityId
    facility_name = $FacilityName
    district = $null
    province = $null
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
}

[pscustomobject]@{
  database = $DbName
  facility_id = $FacilityId
  start_date = $StartDate
  end_date = $EndDate
  aggregate_days_with_data = $byDate.Count
  calendar_days_sent = $sent
  failed = $failed
}
