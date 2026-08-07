<#
.SYNOPSIS
  Clear a JasperReports Server cache via the REST v2 `caches` service.

.DESCRIPTION
  The caches service is minimal: it exposes only DELETE /rest_v2/caches/{cacheId}
  ("clearCache") -- there is no list-all GET (GET /caches returns the webapp's
  404 page). The chief use is invalidating the Ad Hoc / query result cache after
  the underlying data changes, so the next ad-hoc/Domain query re-reads the DB.

  Common cacheId values (per the JRS REST reference): `queryCache` (Ad Hoc query
  results). Pass the cache id you intend to clear with -CacheId.

  Credentials resolve: params -> JRS_URL/JRS_USER/JRS_PASS -> jrs.config.json.

.PARAMETER CacheId
  The cache to clear, e.g. queryCache.

.EXAMPLE
  .\manage_cache.ps1 -CacheId queryCache
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CacheId,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password

$r = Invoke-JrsRest -Jrs $jrs -Method DELETE -Path "/rest_v2/caches/$CacheId"
if ($r.Code -notmatch '^(2\d\d|404)$') { Write-Host $r.Body; throw "clear cache failed HTTP $($r.Code)" }
if ($r.Code -eq "404") { Write-Host "cache '$CacheId' not found (404) -- nothing to clear" }
else { Write-Host "OK ($($r.Code)): cleared cache '$CacheId'" }
