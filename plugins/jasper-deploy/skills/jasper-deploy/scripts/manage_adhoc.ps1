<#
.SYNOPSIS
  List / fetch / (re)deploy / delete JasperReports Server Ad Hoc views
  (adhocDataView resources) via REST v2.

.DESCRIPTION
  An Ad Hoc view is authored interactively in the Ad Hoc Designer on top of a
  Topic (a jrxml file resource), a Domain, or a datasource -- its descriptor
  carries a large opaque query.multiAxis + component state that is impractical
  to hand-write. So this skill does NOT scaffold one from scratch. It DOES make
  the lifecycle scriptable:

    -Action list    list adhocDataView resources under -Folder (uri + label)
    -Action get     download an adhocDataView descriptor JSON to -OutFile, for
                    inspection / version-control diffs. (NOTE: this JSON is NOT
                    redeployable by a raw PUT -- the server rejects it 500
                    "bytes is null" because an ad hoc view also has a companion
                    binary state the descriptor omits, the same reason dashboards
                    must be imported, not PUT. Use export/import to move a view.)
    -Action export  back up / snapshot the view as a portable ZIP (wraps
                    export_resource.ps1) -- the envelope carries the view AND its
                    backing Topic/Domain, and re-imports rendering-intact.
    -Action import  restore / clone / promote from a ZIP (wraps import_resource.ps1).
    -Action delete  DELETE the adhocDataView at -Uri.

  For cross-server dev->prod promotion, promote.ps1 does export+import in one step.

  Credentials resolve: params -> JRS_URL/JRS_USER/JRS_PASS -> jrs.config.json.

.EXAMPLE
  .\manage_adhoc.ps1 -Action list -Folder /public/Samples/Ad_Hoc_Views
.EXAMPLE
  .\manage_adhoc.ps1 -Action get -Uri /public/Samples/Ad_Hoc_Views/05__Unit_Sales_Trend -OutFile backups\unit_sales.json
.EXAMPLE
  .\manage_adhoc.ps1 -Action export -Uri /public/Samples/Ad_Hoc_Views/05__Unit_Sales_Trend -OutFile backups\unit_sales.zip
  .\manage_adhoc.ps1 -Action import -Zip backups\unit_sales.zip
#>
[CmdletBinding()]
param(
    [ValidateSet("list", "get", "export", "import", "delete")][string]$Action = "list",
    [string]$Folder = "/",
    [string]$Uri,
    [string]$OutFile,
    [string]$Zip,
    [switch]$Overwrite,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password
$adhocMedia = "application/repository.adhocDataView+json"

switch ($Action) {
    "list" {
        $r = Invoke-JrsGet -Jrs $jrs -Uri "?folderUri=$Folder&recursive=true&type=adhocDataView"
        # 200 = results, 204 = empty folder; anything else is a real error, not "no views".
        Assert-JrsOk -Response $r -Operation "list ad hoc views under $Folder" -Ok '^2\d\d$' | Out-Null
        $items = try { ($r.Body | ConvertFrom-Json).resourceLookup } catch { @() }
        if (-not $items) { Write-Host "no adhocDataView resources under $Folder"; return }
        $items | ForEach-Object { "{0,-65} {1}" -f $_.uri, $_.label } | Write-Host
        Write-Host "($($items.Count) ad hoc view(s))"
    }
    "get" {
        if (-not $Uri) { throw "-Action get requires -Uri" }
        if (-not $OutFile) { $OutFile = (($Uri -split "/")[-1]) + ".adhoc.json" }
        $r = Invoke-JrsGet -Jrs $jrs -Uri $Uri -Accept $adhocMedia
        Assert-JrsOk -Response $r -Operation "get $Uri failed" | Out-Null
        $parent = Split-Path -Parent $OutFile
        if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force $parent | Out-Null }
        $r.Body | Set-Content $OutFile -Encoding utf8
        Write-Host "OK ($($r.Code)): wrote $OutFile ($((Get-Item $OutFile).Length) bytes)"
    }
    "export" {
        if (-not $Uri) { throw "-Action export requires -Uri" }
        if (-not $OutFile) { $OutFile = (($Uri -split "/")[-1]) + ".zip" }
        $args = @{ Uri = $Uri; Out = $OutFile }
        if ($ServerUrl) { $args.ServerUrl = $ServerUrl }
        if ($User) { $args.User = $User }; if ($Password) { $args.Password = $Password }
        & (Join-Path $PSScriptRoot "export_resource.ps1") @args
    }
    "import" {
        if (-not $Zip -or -not (Test-Path $Zip)) { throw "-Action import requires -Zip <export.zip>" }
        $args = @{ Zip = $Zip }
        if ($ServerUrl) { $args.ServerUrl = $ServerUrl }
        if ($User) { $args.User = $User }; if ($Password) { $args.Password = $Password }
        & (Join-Path $PSScriptRoot "import_resource.ps1") @args
    }
    "delete" {
        if (-not $Uri) { throw "-Action delete requires -Uri" }
        $code = Invoke-JrsDelete -Jrs $jrs -Uri $Uri
        Write-Host "DELETE $Uri -> $code"
        if ($code -notmatch '^(2\d\d|404)$') { throw "delete failed HTTP $code" }
    }
}
