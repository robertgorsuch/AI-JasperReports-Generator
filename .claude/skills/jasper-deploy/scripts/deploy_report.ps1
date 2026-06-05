<#
.SYNOPSIS
  Deploy a .jrxml to JasperReports Server as a reportUnit via the REST v2 API.

.DESCRIPTION
  Builds a reportUnit descriptor with the jrxml inlined as base64 content and
  PUTs it to /rest_v2/resources (creating intermediate folders). The jrxml is
  uploaded as-is; JasperReports Server compiles it server-side on first run.
  A datasource reference is optional but a report won't run without one.

  Server URL and credentials are resolved in this order (first wins):
    1. -ServerUrl / -User / -Password parameters
    2. environment variables JRS_URL / JRS_USER / JRS_PASS
    3. jrs.config.json in the skill root (gitignored)

.PARAMETER Jrxml
  Path to the .jrxml to deploy.

.PARAMETER TargetUri
  Repository URI for the report unit, e.g. /reports/geocoder/county_summary
  (no spaces). The last segment becomes the resource id.

.PARAMETER Label
  Human-readable label. Defaults to the file base name.

.PARAMETER DataSourceUri
  Repository URI of an EXISTING datasource, e.g. /datasources/postgis_34_sample.

.EXAMPLE
  .\deploy_report.ps1 -Jrxml ..\..\report\county_summary.jrxml `
      -TargetUri /reports/geocoder/county_summary `
      -Label "County Edge Summary" `
      -DataSourceUri /datasources/postgis_34_sample
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Jrxml,
    [Parameter(Mandatory = $true)][string]$TargetUri,
    [string]$Label,
    [string]$Description = "",
    [string]$DataSourceUri,
    [string[]]$ResourceFiles,   # companion resources: "name=localpath" (bundles, images, subreports)
    [switch]$Overwrite,
    [switch]$SkipSqlLint,       # bypass the SELECT-first / leading-WITH guard
    [string[]]$Control,         # input controls: "param:kind[:label[:extra]]"
                                #   kind=select|multiselect  extra="Food;Drink" (or lab=val;..)
                                #   kind=single              extra=text|number|date|datetime
    [string]$ControlsLayout = "popupScreen",
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")

if (-not (Test-Path $Jrxml)) { throw "jrxml not found: $Jrxml" }
$jrxmlFull = (Resolve-Path $Jrxml).Path

# --- SQL lint: a leading WITH (CTE) or non-SELECT query compiles locally but
#     the JRS SQL security validator rejects it at fill time (JSSecurityException
#     surfaced as a generic 400). Catch it before deploying.
if (-not $SkipSqlLint) {
    $jx = Get-Content $jrxmlFull -Raw
    $mq = [regex]::Match($jx, '(?s)<query[^>]*language="SQL"[^>]*>\s*<!\[CDATA\[(.*?)\]\]>')
    if ($mq.Success) {
        $q = $mq.Groups[1].Value.Trim()
        while ($true) {                              # strip leading SQL comments
            if ($q.StartsWith("--"))     { $i = $q.IndexOf("`n"); $q = if ($i -ge 0) { $q.Substring($i + 1).TrimStart() } else { "" } }
            elseif ($q.StartsWith("/*")) { $i = $q.IndexOf("*/");  $q = if ($i -ge 0) { $q.Substring($i + 2).TrimStart() } else { "" } }
            else { break }
        }
        $kw = ([regex]::Match($q, "(?i)^[a-z]+")).Value.ToLower()
        if ($kw -eq "with") {
            throw "SQL lint: query begins with WITH (CTE). JRS rejects this at fill time though it compiles locally. Rewrite each CTE as a FROM subquery so the statement starts with SELECT, or pass -SkipSqlLint. (See SKILL.md gotchas.)"
        } elseif ($kw -and $kw -ne "select") {
            Write-Warning "SQL lint: query begins with '$kw', not SELECT; JRS requires report queries to start with SELECT."
        }
    }
}

# --- resolve config (param -> env -> jrs.config.json, validated) ----------
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password
if (-not $DataSourceUri) { $DataSourceUri = $jrs.DataSourceUri }
if (-not $TargetUri.StartsWith("/")) { $TargetUri = "/$TargetUri" }
if (-not $Label) { $Label = [System.IO.Path]::GetFileNameWithoutExtension($jrxmlFull) }

# --- build reportUnit descriptor -----------------------------------------
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($jrxmlFull))

$desc = [ordered]@{
    label       = $Label
    description = $Description
    jrxml       = [ordered]@{
        jrxmlFile = [ordered]@{
            label   = "$Label main jrxml"
            type    = "jrxml"
            content = $b64
        }
    }
}
if ($DataSourceUri) {
    $desc.dataSource = [ordered]@{ dataSourceReference = [ordered]@{ uri = $DataSourceUri } }
} else {
    Write-Warning "No datasource specified; report unit will be created but won't run until one is attached."
}

# optional companion resources embedded in the report unit (resource bundles,
# images, subreport .jasper, etc.). -ResourceFiles entries are "name=localpath".
if ($ResourceFiles) {
    $extType = @{ ".properties"="prop"; ".png"="img"; ".gif"="img"; ".jpg"="img"; ".jpeg"="img";
                  ".jrxml"="jrxml"; ".jasper"="jrxml"; ".ttf"="font"; ".xml"="xml" }
    $list = @()
    foreach ($rf in $ResourceFiles) {
        $name, $path = $rf -split "=", 2
        if (-not (Test-Path $path)) { throw "resource file not found: $path" }
        $ext = [IO.Path]::GetExtension($path).ToLower()
        $rtype = if ($extType.ContainsKey($ext)) { $extType[$ext] } else { "txt" }
        $rb64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $path)))
        $list += [ordered]@{ name = $name; file = [ordered]@{ fileResource = [ordered]@{ label = $name; type = $rtype; content = $rb64 } } }
    }
    $desc.resources = [ordered]@{ resource = $list }
}

# --- PUT to REST v2 -------------------------------------------------------
# JRS uses optimistic locking, so a plain re-PUT over an existing report unit
# fails with 409 "versions not match". -Overwrite passes ?overwrite=true, which
# updates the resource IN PLACE -- no delete, so it also works for a report that
# is a dependency of a dashboard (a delete-then-create would 403 on the delete,
# since referenced resources are delete-protected).
$jsonFile = [IO.Path]::GetTempFileName()
($desc | ConvertTo-Json -Depth 8) | Set-Content -Path $jsonFile -Encoding utf8
try {
    $r = Invoke-JrsPut -Jrs $jrs -Uri $TargetUri -Overwrite:$Overwrite `
        -ContentType "application/repository.reportUnit+json" -JsonFile $jsonFile
} finally {
    Remove-Item $jsonFile -ErrorAction SilentlyContinue
}

if ($r.Code -match '^2\d\d$') {
    Write-Host "OK ($($r.Code)): deployed $TargetUri"
    if ($r.Body) { Write-Host $r.Body }
} else {
    Write-Host "FAILED ($($r.Code))"
    if ($r.Body) { Write-Host $r.Body }
    throw "deploy failed with HTTP $($r.Code): $($r.Body)"
}

# --- input controls -------------------------------------------------------
# Build each control as a standalone repository resource (the verified JRS
# pattern -- embedding in the report unit is rejected) whose NAME equals the
# report parameter ($P{name}), then reference it from the report unit. select/
# multiselect get a listOfValues resource; single gets an embedded dataType.
if ($Control) {
    $parent = $TargetUri.Substring(0, $TargetUri.LastIndexOf("/"))
    $rname  = $TargetUri.Substring($TargetUri.LastIndexOf("/") + 1)
    $ctlFolder = "$parent/${rname}_controls"

    function Put-Resource($uri, $ctype, $obj) {
        $f = [IO.Path]::GetTempFileName()
        ($obj | ConvertTo-Json -Depth 8) | Set-Content $f -Encoding utf8
        try { $rr = Invoke-JrsPut -Jrs $jrs -Uri $uri -Overwrite -ContentType $ctype -JsonFile $f }
        finally { Remove-Item $f -ErrorAction SilentlyContinue }
        if ($rr.Code -notmatch '^2\d\d$') { throw "input control PUT $uri failed ($($rr.Code)): $($rr.Body)" }
    }

    $icRefs = @()
    foreach ($spec in $Control) {
        $p = $spec.Split(":", 4)
        $cname = $p[0]; $kind = $p[1].ToLower()
        $label = if ($p.Count -ge 3 -and $p[2]) { $p[2] } else { $cname }
        $extra = if ($p.Count -ge 4) { $p[3] } else { "" }
        $icUri = "$ctlFolder/$cname"
        if ($kind -eq "select" -or $kind -eq "multiselect") {
            $items = @()
            foreach ($v in ($extra -split ";")) {
                if (-not $v) { continue }
                if ($v -match "=") { $kv = $v.Split("=", 2); $items += [ordered]@{ label = $kv[0]; value = $kv[1] } }
                else { $items += [ordered]@{ label = $v; value = $v } }
            }
            $lovUri = "$ctlFolder/${cname}_lov"
            Put-Resource $lovUri "application/repository.listOfValues+json" ([ordered]@{ label = "$label values"; items = $items })
            $type = if ($kind -eq "select") { 3 } else { 6 }
            Put-Resource $icUri "application/repository.inputControl+json" ([ordered]@{
                label = $label; mandatory = $false; readOnly = $false; visible = $true; type = $type
                listOfValues = [ordered]@{ listOfValuesReference = [ordered]@{ uri = $lovUri; version = 0 } } })
        } elseif ($kind -eq "single") {
            $dt = if ($extra) { $extra } else { "text" }
            Put-Resource $icUri "application/repository.inputControl+json" ([ordered]@{
                label = $label; mandatory = $false; readOnly = $false; visible = $true; type = 2
                dataType = [ordered]@{ dataType = [ordered]@{ type = $dt; label = "$cname type" } } })
        } else { throw "unknown control kind '$kind' (use select|multiselect|single)" }
        $icRefs += [ordered]@{ inputControlReference = [ordered]@{ uri = $icUri } }
        Write-Host "  input control: $cname ($kind) -> $icUri"
    }

    # reference the controls from the report unit
    $cur = Invoke-JrsGet -Jrs $jrs -Uri $TargetUri
    if ($cur.Code -notmatch '^2\d\d$') { throw "could not re-read $TargetUri to attach controls ($($cur.Code))" }
    $ru = $cur.Body | ConvertFrom-Json
    $ru | Add-Member -NotePropertyName inputControls -NotePropertyValue $icRefs -Force
    $ru | Add-Member -NotePropertyName controlsLayout -NotePropertyValue $ControlsLayout -Force
    $f2 = [IO.Path]::GetTempFileName()
    ($ru | ConvertTo-Json -Depth 12) | Set-Content $f2 -Encoding utf8
    try { $ur = Invoke-JrsPut -Jrs $jrs -Uri $TargetUri -Overwrite -ContentType "application/repository.reportUnit+json" -JsonFile $f2 }
    finally { Remove-Item $f2 -ErrorAction SilentlyContinue }
    if ($ur.Code -notmatch '^2\d\d$') { throw "attaching controls to $TargetUri failed ($($ur.Code)): $($ur.Body)" }
    Write-Host "OK: attached $($icRefs.Count) input control(s) to $TargetUri"
}
