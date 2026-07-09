param(
  [string]$ConfigPath = ".\config.json"
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentRoot = Split-Path -Parent $ScriptRoot
$LogDir = Join-Path $AgentRoot "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-AgentLog {
  param([string]$Message)
  $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $line = "[$stamp] $Message"
  $logFile = Join-Path $LogDir ("agent-" + (Get-Date -Format "yyyyMMdd") + ".log")
  Add-Content -Path $logFile -Value $line -Encoding UTF8
  Write-Host $line
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
  $header = @{ alg = "HS256"; typ = "JWT" } | ConvertTo-Json -Compress
  $payload = @{
    iss = $Issuer
    aud = $Audience
    iat = $epoch
    exp = $epoch + 300
    facility_id = $FacilityId
    scope = "etl:write"
  } | ConvertTo-Json -Compress

  $encoding = [Text.Encoding]::UTF8
  $headerPart = ConvertTo-Base64Url ($encoding.GetBytes($header))
  $payloadPart = ConvertTo-Base64Url ($encoding.GetBytes($payload))
  $unsigned = "$headerPart.$payloadPart"
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

function Invoke-OdbcScalar {
  param(
    [string]$ConnectionString,
    [string]$Sql,
    [string]$ReportDate
  )
  $connection = New-Object System.Data.Odbc.OdbcConnection($ConnectionString)
  try {
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = $Sql
    $reportDateValue = [DateTime]::ParseExact($ReportDate, "yyyy-MM-dd", $null)
    $parameterCount = ([regex]::Matches($Sql, "\?")).Count
    if ($parameterCount -eq 0) {
      throw "SQL query must contain at least one ? report date parameter."
    }
    for ($index = 0; $index -lt $parameterCount; $index++) {
      $parameter = $command.Parameters.Add("@report_date$index", [System.Data.Odbc.OdbcType]::Date)
      $parameter.Value = $reportDateValue
    }
    $value = $command.ExecuteScalar()
    if ($null -eq $value -or $value -is [DBNull]) {
      return 0
    }
    return [int]$value
  }
  finally {
    if ($connection.State -ne "Closed") {
      $connection.Close()
    }
  }
}

function Invoke-OdbcRows {
  param(
    [string]$ConnectionString,
    [string]$Sql,
    [string]$ReportDate
  )
  $connection = New-Object System.Data.Odbc.OdbcConnection($ConnectionString)
  try {
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = $Sql
    $reportDateValue = [DateTime]::ParseExact($ReportDate, "yyyy-MM-dd", $null)
    $parameterCount = ([regex]::Matches($Sql, "\?")).Count
    if ($parameterCount -eq 0) {
      throw "SQL query must contain at least one ? report date parameter."
    }
    for ($index = 0; $index -lt $parameterCount; $index++) {
      $parameter = $command.Parameters.Add("@report_date$index", [System.Data.Odbc.OdbcType]::Date)
      $parameter.Value = $reportDateValue
    }
    $adapter = New-Object System.Data.Odbc.OdbcDataAdapter($command)
    $table = New-Object System.Data.DataTable
    [void]$adapter.Fill($table)
    return $table.Rows
  }
  finally {
    if ($connection.State -ne "Closed") {
      $connection.Close()
    }
  }
}

function Invoke-OptionalOdbcScalar {
  param(
    $SqlConfig,
    [string]$Name,
    [string]$ConnectionString,
    [string]$ReportDate
  )
  if ($null -eq $SqlConfig -or -not ($SqlConfig.PSObject.Properties.Name -contains $Name)) {
    return 0
  }
  $query = $SqlConfig.$Name
  if ([string]::IsNullOrWhiteSpace($query)) {
    return 0
  }
  return Invoke-OdbcScalar $ConnectionString $query $ReportDate
}

function Get-SampleMetrics {
  param([string]$ReportDate)
  $seed = [Math]::Abs($ReportDate.GetHashCode()) % 100
  return @{
    total_visits = 60 + $seed
    unique_patients = 45 + [Math]::Floor($seed * 0.7)
    chronic_followups = 10 + ($seed % 20)
    ncd_dm_patients = 8 + ($seed % 15)
    ncd_ht_patients = 12 + ($seed % 18)
    ncd_dm_ht_patients = 4 + ($seed % 8)
    ncd_bp_screened = 35 + ($seed % 40)
    ncd_fbs_screened = 8 + ($seed % 20)
    missing_diagnosis = $seed % 7
    anc_visits = 2 + ($seed % 8)
    vaccine_visits = 5 + ($seed % 15)
    home_visits = 1 + ($seed % 6)
    refer_out = $seed % 5
    emergency_cases = $seed % 3
    disease_groups = @{
      dyslipidemia = 0
      vaping_lung_injury = 0
      coronary_artery_disease = 0
      stroke = 0
      mental_health = 0
      cancer = 0
      diabetes = 8 + ($seed % 15)
      pertussis = 0
      hypertension = 12 + ($seed % 18)
      copd_emphysema = 0
    }
    pingpong_7color = @{
      black = $seed % 3
      red = 2 + ($seed % 5)
      orange = 3 + ($seed % 7)
      yellow = 5 + ($seed % 9)
      green = 8 + ($seed % 12)
      white = 12 + ($seed % 16)
    }
  }
}

function Get-SampleLocations {
  param($Config, [string]$ReportDate)
  $seed = [Math]::Abs($ReportDate.GetHashCode()) % 100
  $baseLat = 13.7563 + (($seed % 10) * 0.01)
  $baseLng = 100.5018 + (($seed % 10) * 0.01)
  $rows = @()
  for ($index = 0; $index -lt 16; $index++) {
    $patientKey = "sample-$ReportDate-$index"
    $rows += @{
      patient_hash = New-PatientHash $Config.JwtSecret $Config.FacilityId $patientKey
      disease_group = $(if ($index % 2 -eq 0) { "DM" } else { "HT" })
      latitude = [Math]::Round($baseLat + (($index % 4) * 0.006), 7)
      longitude = [Math]::Round($baseLng + ([Math]::Floor($index / 4) * 0.006), 7)
      payload = @{}
    }
  }
  return $rows
}

function Get-OdbcMetrics {
  param($Config, [string]$ReportDate)
  $sql = $Config.Sql
  return @{
    total_visits = Invoke-OdbcScalar $Config.OdbcConnectionString $sql.TotalVisits $ReportDate
    unique_patients = Invoke-OdbcScalar $Config.OdbcConnectionString $sql.UniquePatients $ReportDate
    chronic_followups = Invoke-OdbcScalar $Config.OdbcConnectionString $sql.ChronicFollowups $ReportDate
    ncd_dm_patients = Invoke-OdbcScalar $Config.OdbcConnectionString $sql.NcdDmPatients $ReportDate
    ncd_ht_patients = Invoke-OdbcScalar $Config.OdbcConnectionString $sql.NcdHtPatients $ReportDate
    ncd_dm_ht_patients = Invoke-OdbcScalar $Config.OdbcConnectionString $sql.NcdDmHtPatients $ReportDate
    ncd_bp_screened = Invoke-OdbcScalar $Config.OdbcConnectionString $sql.NcdBpScreened $ReportDate
    ncd_fbs_screened = Invoke-OdbcScalar $Config.OdbcConnectionString $sql.NcdFbsScreened $ReportDate
    missing_diagnosis = Invoke-OdbcScalar $Config.OdbcConnectionString $sql.MissingDiagnosis $ReportDate
    anc_visits = Invoke-OdbcScalar $Config.OdbcConnectionString $sql.AncVisits $ReportDate
    vaccine_visits = Invoke-OdbcScalar $Config.OdbcConnectionString $sql.VaccineVisits $ReportDate
    home_visits = Invoke-OdbcScalar $Config.OdbcConnectionString $sql.HomeVisits $ReportDate
    refer_out = Invoke-OdbcScalar $Config.OdbcConnectionString $sql.ReferOut $ReportDate
    emergency_cases = Invoke-OdbcScalar $Config.OdbcConnectionString $sql.EmergencyCases $ReportDate
    disease_groups = @{
      dyslipidemia = Invoke-OptionalOdbcScalar $sql "DiseaseDyslipidemia" $Config.OdbcConnectionString $ReportDate
      vaping_lung_injury = Invoke-OptionalOdbcScalar $sql "DiseaseVapingLungInjury" $Config.OdbcConnectionString $ReportDate
      coronary_artery_disease = Invoke-OptionalOdbcScalar $sql "DiseaseCoronaryArtery" $Config.OdbcConnectionString $ReportDate
      stroke = Invoke-OptionalOdbcScalar $sql "DiseaseStroke" $Config.OdbcConnectionString $ReportDate
      mental_health = Invoke-OptionalOdbcScalar $sql "DiseaseMentalHealth" $Config.OdbcConnectionString $ReportDate
      cancer = Invoke-OptionalOdbcScalar $sql "DiseaseCancer" $Config.OdbcConnectionString $ReportDate
      diabetes = Invoke-OptionalOdbcScalar $sql "DiseaseDiabetes" $Config.OdbcConnectionString $ReportDate
      pertussis = Invoke-OptionalOdbcScalar $sql "DiseasePertussis" $Config.OdbcConnectionString $ReportDate
      hypertension = Invoke-OptionalOdbcScalar $sql "DiseaseHypertension" $Config.OdbcConnectionString $ReportDate
      copd_emphysema = Invoke-OptionalOdbcScalar $sql "DiseaseCopdEmphysema" $Config.OdbcConnectionString $ReportDate
    }
    pingpong_7color = @{
      black = Invoke-OptionalOdbcScalar $sql "PingpongBlack" $Config.OdbcConnectionString $ReportDate
      red = Invoke-OptionalOdbcScalar $sql "PingpongRed" $Config.OdbcConnectionString $ReportDate
      orange = Invoke-OptionalOdbcScalar $sql "PingpongOrange" $Config.OdbcConnectionString $ReportDate
      yellow = Invoke-OptionalOdbcScalar $sql "PingpongYellow" $Config.OdbcConnectionString $ReportDate
      green = Invoke-OptionalOdbcScalar $sql "PingpongGreen" $Config.OdbcConnectionString $ReportDate
      white = Invoke-OptionalOdbcScalar $sql "PingpongWhite" $Config.OdbcConnectionString $ReportDate
    }
  }
}

function Get-OdbcLocations {
  param($Config, [string]$ReportDate)
  if ($null -eq $Config.Sql -or -not ($Config.Sql.PSObject.Properties.Name -contains "NcdHouseLocations")) {
    return @()
  }
  $query = $Config.Sql.NcdHouseLocations
  if ([string]::IsNullOrWhiteSpace($query)) {
    return @()
  }

  $rows = @()
  $dataRows = Invoke-OdbcRows $Config.OdbcConnectionString $query $ReportDate
  foreach ($row in $dataRows) {
    if (-not $row.Table.Columns.Contains("patient_key") -or -not $row.Table.Columns.Contains("latitude") -or -not $row.Table.Columns.Contains("longitude")) {
      throw "NcdHouseLocations SQL must return patient_key, disease_group, latitude, longitude."
    }
    $patientKey = [string]$row["patient_key"]
    if ([string]::IsNullOrWhiteSpace($patientKey)) {
      continue
    }

    $latitude = 0.0
    $longitude = 0.0
    if (-not [double]::TryParse(([string]$row["latitude"]), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$latitude)) {
      continue
    }
    if (-not [double]::TryParse(([string]$row["longitude"]), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$longitude)) {
      continue
    }
    if ($latitude -lt -90 -or $latitude -gt 90 -or $longitude -lt -180 -or $longitude -gt 180) {
      continue
    }

    $diseaseGroup = "NCD"
    if ($row.Table.Columns.Contains("disease_group") -and -not [string]::IsNullOrWhiteSpace([string]$row["disease_group"])) {
      $diseaseGroup = [string]$row["disease_group"]
    }

    $rows += @{
      patient_hash = New-PatientHash $Config.JwtSecret $Config.FacilityId $patientKey
      disease_group = $diseaseGroup
      latitude = $latitude
      longitude = $longitude
      payload = @{}
    }
  }
  return $rows
}

function Remove-OldLogs {
  param([int]$RetentionDays)
  if ($RetentionDays -le 0) {
    return
  }
  Get-ChildItem -Path $LogDir -Filter "*.log" -File |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1 * $RetentionDays) } |
    Remove-Item -Force
}

try {
  $resolvedConfigPath = Resolve-Path $ConfigPath
  $config = Get-Content -Path $resolvedConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $retentionDays = 30
  if ($null -ne $config.LogRetentionDays) {
    $retentionDays = [int]$config.LogRetentionDays
  }
  Remove-OldLogs $retentionDays

  $reportDate = $config.ReportDate
  if ([string]::IsNullOrWhiteSpace($reportDate)) {
    $reportDate = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
  }

  Write-AgentLog "Starting ETL for facility $($config.FacilityId), report date $reportDate"

  if ($config.DataSourceKind -eq "odbc") {
    $metrics = Get-OdbcMetrics $config $reportDate
  }
  elseif ($config.DataSourceKind -eq "sample") {
    $metrics = Get-SampleMetrics $reportDate
  }
  else {
    throw "Unsupported DataSourceKind: $($config.DataSourceKind). Use sample or odbc."
  }

  $body = @{
    facility_id = $config.FacilityId
    facility_name = $config.FacilityName
    district = $config.District
    province = $config.Province
    report_date = $reportDate
    total_visits = $metrics.total_visits
    unique_patients = $metrics.unique_patients
    chronic_followups = $metrics.chronic_followups
    ncd_dm_patients = $metrics.ncd_dm_patients
    ncd_ht_patients = $metrics.ncd_ht_patients
    ncd_dm_ht_patients = $metrics.ncd_dm_ht_patients
    ncd_bp_screened = $metrics.ncd_bp_screened
    ncd_fbs_screened = $metrics.ncd_fbs_screened
    missing_diagnosis = $metrics.missing_diagnosis
    anc_visits = $metrics.anc_visits
    vaccine_visits = $metrics.vaccine_visits
    home_visits = $metrics.home_visits
    refer_out = $metrics.refer_out
    emergency_cases = $metrics.emergency_cases
    source_generated_at = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    payload = @{
      source = $config.DataSourceKind
      schema_version = "1.0"
      generated_by = "rpst-windows-agent"
      disease_groups = $metrics.disease_groups
      pingpong_7color = $metrics.pingpong_7color
    }
  } | ConvertTo-Json -Depth 5

  $token = New-Jwt $config.JwtSecret $config.JwtIssuer $config.JwtAudience $config.FacilityId
  $headers = @{
    Authorization = "Bearer $token"
    "Content-Type" = "application/json; charset=utf-8"
  }

  $response = Invoke-RestMethod -Method Post -Uri $config.CentralApiUrl -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30
  Write-AgentLog "Sent successfully. Response: $($response | ConvertTo-Json -Compress)"

  if (-not [string]::IsNullOrWhiteSpace($config.CentralLocationsApiUrl)) {
    if ($config.DataSourceKind -eq "odbc") {
      $locations = @(Get-OdbcLocations $config $reportDate)
    }
    else {
      $locations = @(Get-SampleLocations $config $reportDate)
    }

    $locationBody = @{
      facility_id = $config.FacilityId
      report_date = $reportDate
      source_generated_at = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
      locations = $locations
    } | ConvertTo-Json -Depth 6

    $locationResponse = Invoke-RestMethod -Method Post -Uri $config.CentralLocationsApiUrl -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($locationBody)) -TimeoutSec 60
    Write-AgentLog "Sent NCD house locations. Count: $($locations.Count). Response: $($locationResponse | ConvertTo-Json -Compress)"
  }
  exit 0
}
catch {
  Write-AgentLog "ERROR: $($_.Exception.Message)"
  exit 1
}
