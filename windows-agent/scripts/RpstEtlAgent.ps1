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
  }
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
  }
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
    }
  } | ConvertTo-Json -Depth 5

  $token = New-Jwt $config.JwtSecret $config.JwtIssuer $config.JwtAudience $config.FacilityId
  $headers = @{
    Authorization = "Bearer $token"
    "Content-Type" = "application/json; charset=utf-8"
  }

  $response = Invoke-RestMethod -Method Post -Uri $config.CentralApiUrl -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30
  Write-AgentLog "Sent successfully. Response: $($response | ConvertTo-Json -Compress)"
  exit 0
}
catch {
  Write-AgentLog "ERROR: $($_.Exception.Message)"
  exit 1
}
