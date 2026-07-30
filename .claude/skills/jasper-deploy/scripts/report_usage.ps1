<#
.SYNOPSIS
  Usage / access-event reporting straight from the JRS repository *metadata*
  database (read-only): most-run resources, who-ran-what, recent activity, and
  the access history of a single resource.

.DESCRIPTION
  JRS records an access event per repository touch in the metadata DB table
  jiaccessevent (user_id, event_date, resource_uri, resource_type, updating,
  hidden) when "access events" auditing is enabled (it is on this install).
  There is no REST surface for these events in the community/pro tier we use,
  so this script queries the metadata PostgreSQL directly via psql -- SELECTs
  only, nothing is written.

  IMPORTANT (this install): the LIVE metadata DB is the JRS-bundled PostgreSQL
  on port 5433. A stale decoy "jasperserver" database also exists on :5432 with
  an EMPTY jiaccessevent -- if every count comes back 0, you are probably on
  the decoy. Connection settings resolve: script params -> "repoDb" object in
  jrs.config.json (host/port/database/user) -> defaults
  localhost:5433/jasperserver/postgres. The password comes from $env:PGPASSWORD
  (or a .pgpass entry), never from the config file.

.PARAMETER Action
  top      - most-accessed resources in the window (default)
  users    - per-user event + distinct-resource counts
  recent   - latest raw events
  resource - per-user access summary for one -Uri

.PARAMETER Uri
  Repository URI for -Action resource, e.g. /reports/geocoder/county_summary.

.PARAMETER Days
  Look-back window in days (default 30). 0 = all history.

.PARAMETER Type
  Filter by resource type SIMPLE name, matched against the stored Java class
  name: ReportUnit, DashboardModelResource, AdhocDataView,
  SemanticLayerDataSource, JdbcReportDataSource, FileResource, ...

.PARAMETER IncludeUpdates
  Include updating=true events (writes/deploys). Default: reads only, which is
  what "who ran what" usually means.

.PARAMETER Csv
  Emit CSV instead of an aligned table (for piping into a file/report).

.EXAMPLE
  .\report_usage.ps1                          # top resources, last 30 days
.EXAMPLE
  .\report_usage.ps1 -Action users -Days 7
.EXAMPLE
  .\report_usage.ps1 -Action top -Type ReportUnit -Days 90 -Limit 10
.EXAMPLE
  .\report_usage.ps1 -Action resource -Uri /reports/geocoder/county_summary
#>
[CmdletBinding()]
param(
    [ValidateSet("top", "users", "recent", "resource")][string]$Action = "top",
    [string]$Uri,
    [int]$Days = 30,
    [int]$Limit = 20,
    [string]$Type,
    [switch]$IncludeUpdates,
    [string]$DbHost,
    [int]$DbPort,
    [string]$DbName,
    [string]$DbUser,
    [switch]$Csv
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")

# --- resolve repo-DB connection: params -> jrs.config.json repoDb -> defaults --
$cfgPath = Join-Path $PSScriptRoot "../jrs.config.json"
$repo = $null
if (Test-Path $cfgPath) {
    try { $repo = (Get-Content $cfgPath -Raw | ConvertFrom-Json).repoDb } catch {}
}
function rpick($p, $c, $d) {
    if ($p) { return $p }
    if ($repo -and ($repo.PSObject.Properties.Name -contains $c) -and $repo.$c) { return $repo.$c }
    return $d
}
$DbHost = rpick $DbHost "host" "localhost"
$DbPort = [int](rpick $DbPort "port" 5433)
$DbName = rpick $DbName "database" "jasperserver"
$DbUser = rpick $DbUser "user" "postgres"

if (-not (Get-Command psql -ErrorAction SilentlyContinue)) { throw "psql not on PATH" }
if ($Action -eq "resource" -and -not $Uri) { throw "-Action resource requires -Uri" }
if (-not $env:PGPASSWORD) { Write-Warning "PGPASSWORD not set; relying on .pgpass/trust for $DbUser@${DbHost}:$DbPort" }

# --- build the WHERE clause (values single-quote-escaped for SQL literals) ----
function esc($s) { return ($s -replace "'", "''") }
$where = @("hidden = false")
if ($Days -gt 0) { $where += "event_date > now() - interval '$Days days'" }
if (-not $IncludeUpdates) { $where += "updating = false" }
if ($Type) { $where += "resource_type ILIKE '%$(esc $Type)'" }
if ($Action -eq "resource") { $where += "resource_uri = '$(esc $Uri)'" }
$w = $where -join " AND "

# resource_type stores the full Java class name; report just the simple name.
$typeExpr = "regexp_replace(resource_type, '^.*\.', '')"

$sql = switch ($Action) {
    "top" {
        "SELECT resource_uri, $typeExpr AS type, count(*) AS events,
                count(DISTINCT user_id) AS users, max(event_date) AS last_access
         FROM jiaccessevent WHERE $w
         GROUP BY resource_uri, resource_type
         ORDER BY events DESC, last_access DESC LIMIT $Limit"
    }
    "users" {
        "SELECT user_id, count(*) AS events,
                count(DISTINCT resource_uri) AS resources, max(event_date) AS last_active
         FROM jiaccessevent WHERE $w
         GROUP BY user_id ORDER BY events DESC LIMIT $Limit"
    }
    "recent" {
        "SELECT event_date, user_id, resource_uri, $typeExpr AS type, updating
         FROM jiaccessevent WHERE $w
         ORDER BY event_date DESC LIMIT $Limit"
    }
    "resource" {
        "SELECT user_id, count(*) AS events,
                min(event_date) AS first_access, max(event_date) AS last_access
         FROM jiaccessevent WHERE $w
         GROUP BY user_id ORDER BY events DESC LIMIT $Limit"
    }
}

$header = "usage ($Action) -- $DbUser@${DbHost}:${DbPort}/$DbName, last $(if ($Days -gt 0) { "$Days day(s)" } else { 'all history' })$(if ($Type) { ", type ~$Type" })$(if ($Action -eq 'resource') { ", uri $Uri" })"
Write-Host $header

$psqlArgs = @("-h", $DbHost, "-p", $DbPort, "-U", $DbUser, "-d", $DbName, "-X", "-v", "ON_ERROR_STOP=1")
if ($Csv) { $psqlArgs += "--csv" }
$out = & psql @psqlArgs -c $sql 2>&1
if ($LASTEXITCODE -ne 0) {
    $msg = "repo-DB query failed: $("$out".Trim())"
    if ("$out" -match 'relation .* does not exist|refused|no pg_hba') {
        $msg += "`n  -> hint: the LIVE metadata DB is the bundled PostgreSQL on :5433; the :5432 jasperserver DB is a stale decoy. Check `"repoDb`" in jrs.config.json."
    }
    throw $msg
}
$out | ForEach-Object { Write-Host $_ }

# Decoy tripwire: a working connection that sees zero events is almost always
# the wrong (stale) database, not a quiet server.
if (-not $Csv -and ("$out" -match '\(0 rows\)')) {
    Write-Warning "0 events found. If unexpected, you may be on the stale :5432 decoy DB -- the live metadata DB listens on :5433 (repoDb in jrs.config.json)."
}
