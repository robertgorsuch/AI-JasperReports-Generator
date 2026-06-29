<#
.SYNOPSIS
  Detect drift between a deployed JasperReports Server resource and a local
  source-of-truth descriptor -- which top-level fields were added, removed, or
  changed on the server vs the file you expected.

.DESCRIPTION
  GETs the live resource descriptor (Accept json) via _jrs_common.ps1's
  Invoke-JrsGet, parses both the live body and the local -Against .json file,
  and compares their TOP-LEVEL fields. Reports three buckets:
    * added   -- field present live but not in the local descriptor;
    * removed -- field present locally but not live;
    * changed -- field present in both with a different value.
  Nested objects and binary/opaque children (e.g. an embedded jrxml's base64
  'content', a schema file) are compared by PRESENCE and LENGTH, not a byte
  diff -- so a re-deploy that re-encodes the same jrxml does not show as drift
  unless its size actually changed. Fields whose names look like server-managed
  bookkeeping (version, creationDate, updateDate, permissionMask) are ignored.

  Prints a concise drift summary and exits NONZERO when any drift is found, so
  it slots into a verify/CI gate. Credentials resolve the same way as the other
  scripts: -ServerUrl/-User/-Password -> env JRS_URL/JRS_USER/JRS_PASS ->
  jrs.config.json.

.PARAMETER Uri
  Repository URI of the deployed resource, e.g.
  /reports/foodmart/foodmart_top_categories.

.PARAMETER Against
  Path to a local .json descriptor (the source-of-truth) to compare the live
  resource against. Typically a descriptor captured earlier with Invoke-JrsGet
  or exported for version control.

.PARAMETER IgnoreFields
  Extra top-level field names to ignore (added to the built-in bookkeeping list).

.EXAMPLE
  .\diff_resource.ps1 -Uri /reports/foodmart/foodmart_top_categories `
      -Against backups\foodmart_top_categories.json

.EXAMPLE
  # use in a gate -- nonzero exit on drift
  .\diff_resource.ps1 -Uri /datasources/postgis_34_sample -Against expected\ds.json
  if ($LASTEXITCODE) { throw "datasource drifted" }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [Parameter(Mandatory = $true)][string]$Against,
    [string[]]$IgnoreFields,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password
if (-not $Uri.StartsWith("/")) { $Uri = "/$Uri" }
if (-not (Test-Path $Against)) { throw "local descriptor not found: $Against" }

# server-managed fields that change on every save -- not real drift
$ignore = @{}
foreach ($f in (@("version", "creationDate", "updateDate", "permissionMask") + @($IgnoreFields))) {
    if ($f) { $ignore[$f] = $true }
}

# --- fetch the live descriptor ------------------------------------------------
$resp = Invoke-JrsGet -Jrs $jrs -Uri $Uri
if ($resp.Code -notmatch '^2\d\d$') { throw "GET $Uri failed (HTTP $($resp.Code)): $($resp.Body)" }
try { $live = $resp.Body | ConvertFrom-Json } catch { throw "live body is not JSON: $($resp.Body)" }

# --- parse the local source-of-truth ------------------------------------------
try { $local = Get-Content $Against -Raw | ConvertFrom-Json } catch { throw "could not parse local JSON ${Against}: $_" }

# --- normalize a top-level value to a comparable scalar -----------------------
# scalars compare by value; objects/arrays/long strings compare by a
# type+length signature (so binary/opaque children diff by presence/size).
function Repr($v) {
    if ($null -eq $v) { return "<null>" }
    if ($v -is [bool] -or $v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]) {
        return "$v"
    }
    if ($v -is [string]) {
        if ($v.Length -le 80) { return "`"$v`"" }
        return "<string len=$($v.Length)>"        # long/base64 content: by length
    }
    if ($v -is [array] -or $v -is [System.Collections.IEnumerable]) {
        $n = @($v).Count
        return "<array len=$n>"
    }
    # nested object: signature by its property names (not a deep byte diff)
    $names = @($v.PSObject.Properties.Name | Sort-Object) -join ","
    return "<object {$names}>"
}

function FieldNames($o) {
    if ($null -eq $o) { return @() }
    return @($o.PSObject.Properties.Name)
}

$liveNames  = FieldNames $live
$localNames = FieldNames $local

$added = @(); $removed = @(); $changed = @()

foreach ($n in ($liveNames + $localNames | Sort-Object -Unique)) {
    if ($ignore[$n]) { continue }
    $inLive  = $liveNames  -contains $n
    $inLocal = $localNames -contains $n
    if ($inLive -and -not $inLocal) { $added   += $n; continue }
    if ($inLocal -and -not $inLive) { $removed += $n; continue }
    $rl = Repr $live.$n
    $rf = Repr $local.$n
    if ($rl -ne $rf) { $changed += [pscustomobject]@{ Field = $n; Live = $rl; Local = $rf } }
}

# --- report -------------------------------------------------------------------
Write-Host "diff $Uri  (live)  vs  $Against  (local)"
Write-Host "  note: nested/binary children (e.g. jrxml content) compared by presence/length, not byte diff"
$driftCount = $added.Count + $removed.Count + $changed.Count

foreach ($n in $added)   { Write-Host "  + added   (live only)   $n = $(Repr $live.$n)" }
foreach ($n in $removed) { Write-Host "  - removed (local only)  $n = $(Repr $local.$n)" }
foreach ($c in $changed) { Write-Host "  ~ changed  $($c.Field) : local $($c.Local) -> live $($c.Live)" }

Write-Host ""
if ($driftCount -eq 0) {
    Write-Host "OK: no drift ($Uri matches $Against)"
    exit 0
}
Write-Host "DRIFT: $driftCount field(s) differ (+$($added.Count) / -$($removed.Count) / ~$($changed.Count))"
exit 1
