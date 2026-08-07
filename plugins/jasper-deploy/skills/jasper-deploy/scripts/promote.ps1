<#
.SYNOPSIS
  Promote a repository resource (dashboard, report, folder, datasource, ...) from
  one JasperReports Server to another by export + import.

.DESCRIPTION
  Exports -Uri from the SOURCE server to a local archive, then imports it into the
  TARGET server. Because the archive is the server's own export format, the
  resource lands at the same URI and renders identically -- the supported
  dev->prod promotion path. Export a folder URI to promote a whole app at once.

  Servers can be named environment profiles from jrs.config.json "environments"
  (-FromEnv / -ToEnv) or explicit URLs + credentials (-From* / -To*). Source
  defaults to the skill's top-level jrs.config.json (or env vars) when neither
  is given; the TARGET must be identified by -ToEnv or the full -To* triple.

.PARAMETER Uri
  Repository URI to promote, e.g. /reports/foodmart/foodmart_kpi_dashboard_auto
  (a folder promotes everything under it).

.PARAMETER ToEnv / FromEnv
  Named environment profiles under "environments" in jrs.config.json, e.g.
  -FromEnv stage -ToEnv prod. A profile supplies serverUrl/user/password (or
  passwordCommand); explicit -To*/-From* params override individual values.

.PARAMETER ToServerUrl / ToUser / ToPassword
  Explicit target server; required as a triple when -ToEnv is not given.

.PARAMETER Archive
  Where to write the intermediate .zip (default backups/promote_<name>.zip).

.EXAMPLE
  .\promote.ps1 -Uri /reports/geocoder/sales_dashboard -FromEnv stage -ToEnv prod

.EXAMPLE
  .\promote.ps1 -Uri /reports/geocoder/sales_dashboard `
      -ToServerUrl https://prod:8443/jasperserver-pro -ToUser admin -ToPassword secret
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [string]$ToServerUrl,
    [string]$ToUser,
    [string]$ToPassword,
    [string]$ToEnv,
    [string]$FromServerUrl,
    [string]$FromUser,
    [string]$FromPassword,
    [string]$FromEnv,
    [string]$Archive,
    [bool]$Update = $true
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")

if (-not $Uri.StartsWith("/")) { $Uri = "/$Uri" }
$leaf = ($Uri -split "/")[-1]
if (-not $Archive) { $Archive = "backups/promote_$leaf.zip" }

# Resolve the TARGET up front so a bad profile name or missing credential fails
# before the export runs, and so the summary line can print the real URL.
if (-not $ToEnv -and -not ($ToServerUrl -and $ToUser -and $ToPassword)) {
    throw "Target server required: pass -ToEnv <name> (a jrs.config.json `"environments`" profile) or the full -ToServerUrl/-ToUser/-ToPassword triple"
}
$to = Resolve-JrsConfig -ServerUrl $ToServerUrl -User $ToUser -Password $ToPassword -Env $ToEnv
$from = Resolve-JrsConfig -ServerUrl $FromServerUrl -User $FromUser -Password $FromPassword -Env $FromEnv
if ($to.ServerUrl -eq $from.ServerUrl) {
    throw "source and target are the same server ($($to.ServerUrl)) -- nothing to promote"
}

Write-Host "=== export $Uri from $($from.ServerUrl) ==="
& (Join-Path $PSScriptRoot "export_resource.ps1") -Uri $Uri -Out $Archive `
    -ServerUrl $from.ServerUrl -User $from.User -Password $from.Password

Write-Host "=== import into target $($to.ServerUrl) ==="
& (Join-Path $PSScriptRoot "import_resource.ps1") -Zip $Archive -Update $Update `
    -ServerUrl $to.ServerUrl -User $to.User -Password $to.Password

Write-Host "OK: promoted $Uri -> $($to.ServerUrl) (archive: $Archive)"
