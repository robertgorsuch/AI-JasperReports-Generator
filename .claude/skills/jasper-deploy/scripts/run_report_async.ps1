<#
.SYNOPSIS
  Run a deployed report through the asynchronous `reportExecutions` service:
  submit -> poll status -> download the output. The proper path for large/slow
  fills that time out on the synchronous /reports/{uri}.{fmt} endpoint.

.DESCRIPTION
  1. POST /rest_v2/reportExecutions {reportUnitUri, outputFormat, async:true}
     -> {requestId, exports:[{id}]}
  2. GET  /rest_v2/reportExecutions/{requestId}/status  until {"value":"ready"}
  3. GET  /rest_v2/reportExecutions/{requestId}/exports/{exportId}/outputResource
     -> the bytes, written to -OutFile.

  The request body is passed from a file (PowerShell->curl quoting otherwise
  mangles inline JSON into a 400 serialization.error). The final download uses a
  direct `curl -o` so binary output (PDF/XLSX/…) is written byte-intact rather
  than captured as text.

  Credentials resolve: params -> JRS_URL/JRS_USER/JRS_PASS -> jrs.config.json.

.PARAMETER ReportUri
  Repository URI of the report unit, e.g. /reports/foodmart/top_5_customers_revenue.

.PARAMETER Format
  Output format: pdf|html|xlsx|csv|docx|pptx|rtf|ods|odt|xml. Default pdf.

.PARAMETER OutFile
  Local path for the downloaded output. Default: <leaf>.<format> in the cwd.

.PARAMETER Parameters
  Hashtable of report parameter / input-control values, sent as the execution's
  `parameters` (each value wrapped as a string array, the service's shape).

.PARAMETER TimeoutSec
  Max seconds to poll before giving up. Default 120.

.PARAMETER PollMs
  Milliseconds between status polls. Default 1000.

.EXAMPLE
  .\run_report_async.ps1 -ReportUri /reports/foodmart/top_5_customers_revenue
.EXAMPLE
  .\run_report_async.ps1 -ReportUri /reports/geocoder/county_summary_param `
      -Format xlsx -Parameters @{ minEdges = 50000 } -OutFile out\county.xlsx
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ReportUri,
    [ValidateSet("pdf", "html", "xlsx", "csv", "docx", "pptx", "rtf", "ods", "odt", "xml")]
    [string]$Format = "pdf",
    [string]$OutFile,
    [hashtable]$Parameters,
    [int]$TimeoutSec = 120,
    [int]$PollMs = 1000,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password

if (-not $ReportUri.StartsWith("/")) { $ReportUri = "/$ReportUri" }
$leaf = $ReportUri.Substring($ReportUri.LastIndexOf("/") + 1)
if (-not $OutFile) { $OutFile = "$leaf.$Format" }

# --- 1. submit ------------------------------------------------------------
$req = [ordered]@{
    reportUnitUri = $ReportUri
    outputFormat  = $Format
    interactive   = $false
    async         = $true
}
if ($Parameters -and $Parameters.Count) {
    # the service wants each value as a string array under parameters.reportParameter? No --
    # the documented shape is a flat map of name -> [values].
    $pv = [ordered]@{}
    foreach ($k in $Parameters.Keys) { $pv[$k] = @("$($Parameters[$k])") }
    $req.parameters = [ordered]@{ reportParameter = @($pv.GetEnumerator() | ForEach-Object { [ordered]@{ name = $_.Key; value = $_.Value } }) }
}

$reqFile = [IO.Path]::GetTempFileName()
($req | ConvertTo-Json -Depth 8) | Set-Content -Path $reqFile -Encoding utf8
try {
    $r = Invoke-JrsRest -Jrs $jrs -Method POST -Path "/rest_v2/reportExecutions" `
        -ContentType "application/json" -Accept "application/json" -JsonFile $reqFile
} finally { Remove-Item $reqFile -ErrorAction SilentlyContinue }

if ($r.Code -notmatch '^2\d\d$') { Write-Host $r.Body; throw "submit failed HTTP $($r.Code)" }
$exec = $r.Body | ConvertFrom-Json
$rid = $exec.requestId
$exportId = $exec.exports[0].id
if (-not $exportId) { $exportId = $Format }   # fallback: the format doubles as the export id
Write-Host "submitted: requestId=$rid exportId=$exportId"

# --- 2. poll status -------------------------------------------------------
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$status = ""
while ((Get-Date) -lt $deadline) {
    $s = Invoke-JrsRest -Jrs $jrs -Method GET -Path "/rest_v2/reportExecutions/$rid/status"
    $status = try { ($s.Body | ConvertFrom-Json).value } catch { $s.Body }
    if ($status -eq "ready") { break }
    if ($status -eq "failed" -or $status -eq "cancelled") { throw "execution $status : $($s.Body)" }
    Start-Sleep -Milliseconds $PollMs
}
if ($status -ne "ready") { throw "timed out after ${TimeoutSec}s (last status: $status)" }

# re-read the execution to pick up the final exportId (it can differ from the submit echo)
$d = Invoke-JrsRest -Jrs $jrs -Method GET -Path "/rest_v2/reportExecutions/$rid"
$exportId = try { ($d.Body | ConvertFrom-Json).exports[0].id } catch { $exportId }

# --- 3. download (binary-safe, direct curl -o) ----------------------------
$dir = Split-Path -Parent $OutFile
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$url = "$($jrs.ServerUrl)/rest_v2/reportExecutions/$rid/exports/$exportId/outputResource"
$code = & curl.exe -s -o $OutFile -w "%{http_code}" -u "$($jrs.User):$($jrs.Password)" $url
if ("$code".Trim() -notmatch '^2\d\d$') { throw "download failed HTTP $code" }
$size = (Get-Item $OutFile).Length
Write-Host "OK: $ReportUri -> $OutFile ($size bytes, status $status)"
