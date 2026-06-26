<#
.SYNOPSIS
  Rebuild a compose manifest from a LIVE (possibly designer-edited) dashboard.

.DESCRIPTION
  Exports the dashboard, then derives a manifest whose dashlet positions/sizes
  match the live layout (via sync_manifest.py). Use this after someone rearranges
  the dashboard in the JRS designer so a later `compose_dashboard.ps1` reproduces
  the hand-edited layout instead of reverting it.

.EXAMPLE
  .\sync_manifest_from_dashboard.ps1 -Uri /reports/foodmart/foodmart_sales_dashboard_2dashlet `
      -Out report\foodmart\sales_dashboard_2dashlet.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password

$tmp = [IO.Path]::Combine([IO.Path]::GetTempPath(), "dash_sync_" + [IO.Path]::GetRandomFileName() + ".zip")
try {
    & (Join-Path $PSScriptRoot "export_resource.ps1") -Uri $Uri -Out $tmp `
        -ServerUrl $jrs.ServerUrl -User $jrs.User -Password $jrs.Password | Write-Host
    & python (Join-Path $PSScriptRoot "sync_manifest.py") --zip $tmp --out $Out
    if ($LASTEXITCODE -ne 0) { throw "sync_manifest.py failed" }
} finally {
    Remove-Item $tmp -ErrorAction SilentlyContinue
}
