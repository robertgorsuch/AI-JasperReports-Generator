<#
.SYNOPSIS
  Manage JRS diagnostic log collectors (/rest_v2/diagnostic/collectors):
  start one, stop it, download its zip, list, delete.

.DESCRIPTION
  A collector captures server-side logs (optionally filtered to a user /
  session / resource) between start and stop -- the supported way to gather a
  troubleshooting bundle for a specific failing report without trawling the
  whole catalina log. Lifecycle verified on this server:

    start    POST   /diagnostic/collectors  {name, verbosity} -> 200 {id, status:RUNNING}
    stop     PUT    /diagnostic/collectors/{id}  (same body, status:STOPPED)
                    -> 200 status SHUTTING_DOWN (finishes async)
    download GET    /diagnostic/collectors/{id}/content  (Accept: application/zip)
                    -> collectorSettings.xml + diagnostic.log.jsEncrypted
    list     GET    /diagnostic/collectors  (204 when none)
    delete   DELETE /diagnostic/collectors/{id}

  NOTES verified live:
  * The zip's log is ENCRYPTED (diagnostic.log.jsEncrypted) with the server
    key -- it is meant for Jaspersoft support / offline decryption with the
    server keystore, not casual reading. collectorSettings.xml is plain.
  * A DELETE without an id wipes ALL collectors (the REST treats the bare
    collection DELETE as delete-everything) -- this script therefore requires
    -Id for delete unless you pass -All. Same family of trap as the
    PUT-/attributes-wipes-everything gotcha (G36); see gotchas.md G53.
  * Collector NAMES must be unique among existing collectors -- a duplicate
    -Name 400s with a validateName stack trace. Delete the old one first (or
    pick a fresh name per run, e.g. suffix a timestamp).
  * VERBOSITY HIGH IS BROKEN ON JRS 10.0.0 (gotchas.md G54): the moment a
    HIGH collector starts, every type-filtered repository search
    (resources?type=jdbcDataSource, jndiJdbcDataSource, ...) begins to 500
    with a Hibernate ClassCastException, and ONLY a Tomcat restart heals it --
    stop/delete of the collector does not. LOW (and the log content it
    captures) is verified safe end-to-end; the default is therefore LOW and
    the script warns if you ask for HIGH.

.PARAMETER Action    list (default) | start | stop | download | get | delete
.PARAMETER Id        Collector id (from start/list); required for stop/download/get,
                     and for delete unless -All.
.PARAMETER Name      (start) Collector name (default jd_collector).
.PARAMETER Verbosity (start) LOW | MEDIUM | HIGH (default LOW -- HIGH triggers a
                     server bug, see gotchas.md G54 and the warning below).
.PARAMETER UserId    (start) Only capture activity of this user.
.PARAMETER ResourceUri (start) Only capture activity around this resource.
.PARAMETER Out       (download) Output zip path (default out/diagnostic/<id>.zip).
.PARAMETER All       (delete) Delete EVERY collector (explicit opt-in).

.EXAMPLE
  $c = .\manage_diagnostic.ps1 -Action start -Name repro_bug | ConvertFrom-Json
  # ... reproduce the problem ...
  .\manage_diagnostic.ps1 -Action stop -Id $c.id
  .\manage_diagnostic.ps1 -Action download -Id $c.id -Out bug.zip
  .\manage_diagnostic.ps1 -Action delete -Id $c.id
#>
[CmdletBinding()]
param(
    [ValidateSet("list", "start", "stop", "download", "get", "delete")][string]$Action = "list",
    [string]$Id,
    [string]$Name = "jd_collector",
    [ValidateSet("LOW", "MEDIUM", "HIGH")][string]$Verbosity = "LOW",
    [string]$UserId,
    [string]$ResourceUri,
    [string]$Out,
    [switch]$All,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password,
    [string]$Env
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password -Env $Env
$base = "/rest_v2/diagnostic/collectors"

function Invoke-CollectorJson([string]$Method, [string]$Path, $Body) {
    if ($null -ne $Body) {
        $tf = [IO.Path]::GetTempFileName()
        ($Body | ConvertTo-Json -Depth 4) | Set-Content $tf -Encoding utf8
        try { return Invoke-JrsRest -Jrs $jrs -Method $Method -Path $Path -ContentType "application/json" -JsonFile $tf }
        finally { Remove-Item $tf -ErrorAction SilentlyContinue }
    }
    return Invoke-JrsRest -Jrs $jrs -Method $Method -Path $Path
}

switch ($Action) {
    "list" {
        $r = Assert-JrsOk (Invoke-CollectorJson GET $base $null) "list collectors" '^(200|204)$'
        if ($r.Code -eq "204" -or -not $r.Body) { Write-Host "(no collectors)" } else { $r.Body }
    }
    "start" {
        if ($Verbosity -eq "HIGH") {
            Write-Warning "verbosity HIGH breaks type-filtered repository searches on JRS 10.0.0 until Tomcat restarts (gotchas.md G54). Continuing anyway."
        }
        $body = [ordered]@{ name = $Name; verbosity = $Verbosity }
        if ($UserId -or $ResourceUri) {
            $f = [ordered]@{}
            if ($UserId) { $f.userId = $UserId }
            if ($ResourceUri) { $f.resourceAndSnapshotFilter = [ordered]@{ resourceUri = $ResourceUri } }
            $body.filterBy = $f
        }
        $r = Assert-JrsOk (Invoke-CollectorJson POST $base $body) "start collector"
        $r.Body   # pipeline output so callers can ConvertFrom-Json
    }
    "stop" {
        if (-not $Id) { throw "-Action stop requires -Id" }
        $cur = Assert-JrsOk (Invoke-CollectorJson GET "$base/$Id" $null) "get collector"
        $settings = $cur.Body | ConvertFrom-Json
        $settings.status = "STOPPED"
        $r = Assert-JrsOk (Invoke-CollectorJson PUT "$base/$Id" $settings) "stop collector"
        $r.Body   # status SHUTTING_DOWN; content becomes downloadable shortly after
    }
    "get" {
        if (-not $Id) { throw "-Action get requires -Id" }
        $r = Assert-JrsOk (Invoke-CollectorJson GET "$base/$Id" $null) "get collector"
        $r.Body
    }
    "download" {
        if (-not $Id) { throw "-Action download requires -Id" }
        if (-not $Out) { $Out = "out/diagnostic/$Id.zip" }
        $code = Invoke-JrsDownload -Jrs $jrs -Url "$($jrs.ServerUrl)$base/$Id/content" -OutFile $Out -Accept "application/zip"
        $size = (Get-Item $Out).Length
        Write-Host "OK: collector $Id -> $Out ($size bytes; log inside is jsEncrypted -- see gotchas.md G53)"
    }
    "delete" {
        if ($All) {
            $code = "$((Invoke-CollectorJson DELETE $base $null).Code)"
            Write-Host "OK ($code): deleted ALL collectors"
        } elseif ($Id) {
            $code = "$((Invoke-CollectorJson DELETE "$base/$Id" $null).Code)"
            Write-Host "OK ($code): deleted collector $Id"
        } else {
            throw "delete requires -Id <collector>, or -All to wipe every collector (a bare collection DELETE removes them ALL -- gotchas.md G53)"
        }
    }
}
