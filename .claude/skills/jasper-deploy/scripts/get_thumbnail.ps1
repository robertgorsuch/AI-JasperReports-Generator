<#
.SYNOPSIS
  Download a report's thumbnail image (JPEG on this server) from
  JasperReports Server -- a cheap visual check without a full PDF/HTML export.

.DESCRIPTION
  GET /rest_v2/thumbnails{reportUri}. The server keeps a thumbnail of the last
  UI execution of each report; -DefaultAllowed (on by default) makes the call
  return the generic placeholder image instead of 204 No Content when the
  report has never been run in the UI -- pass -NoDefault to distinguish "has a
  real thumbnail" from "placeholder only" (204 => no thumbnail; the script
  reports which you got).

  Batch form also exists server-side (POST /rest_v2/thumbnails, uri=... form
  params) -- loop this script instead; one GET per report keeps it simple.

.PARAMETER Uri  Repository URI of the report, e.g. /reports/geocoder/county_summary.
.PARAMETER Out  Output image path (default: out/thumbnails/<leaf>.jpg).
.PARAMETER NoDefault  Fail (exit 2) with a note instead of saving the placeholder
  when the report has no real thumbnail yet.

.EXAMPLE
  .\get_thumbnail.ps1 -Uri /reports/foodmart/foodmart_sales_by_region
.EXAMPLE
  .\get_thumbnail.ps1 -Uri /reports/geocoder/county_summary -Out county.png -NoDefault
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [string]$Out,
    [switch]$NoDefault,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password,
    [string]$Env
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password -Env $Env

if (-not $Uri.StartsWith("/")) { $Uri = "/$Uri" }
if (-not $Out) { $Out = "out/thumbnails/$(($Uri -split '/')[-1]).jpg" }

$defaultAllowed = if ($NoDefault) { "false" } else { "true" }
# build the full URL in one string (PS5.1: ? is a variable-name char -- ${} braces)
$url = "$($jrs.ServerUrl)/rest_v2/thumbnails${Uri}?defaultAllowed=$defaultAllowed"

# no Accept header: the endpoint 406s an explicit image/* ask; an unadorned GET
# returns the image bytes (JPEG on this install)
$code = Invoke-JrsDownload -Jrs $jrs -Url $url -OutFile $Out -AllowError
if ("$code".Trim() -eq "204") {
    Write-Host "NO THUMBNAIL: $Uri has never been executed in the UI (204). Run it once in the web UI, or drop -NoDefault to accept the placeholder."
    Remove-Item $Out -ErrorAction SilentlyContinue
    exit 2
}
if ("$code".Trim() -ne "200") { throw "thumbnail GET failed (HTTP $code) for $Uri" }

# image magic: PNG (89 50 4E 47) or JPEG (FF D8 FF)
$bytes = [IO.File]::ReadAllBytes((Resolve-Path $Out))
$fmt = $null
if ($bytes.Length -gt 8 -and $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) { $fmt = "PNG" }
elseif ($bytes.Length -gt 3 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8 -and $bytes[2] -eq 0xFF) { $fmt = "JPEG" }
if (-not $fmt) { throw "response was not an image ($($bytes.Length) bytes) -- body: $([Text.Encoding]::UTF8.GetString($bytes[0..[Math]::Min(120, $bytes.Length-1)]))" }

Write-Host "OK: thumbnail $Uri -> $Out ($fmt, $($bytes.Length) bytes)"
