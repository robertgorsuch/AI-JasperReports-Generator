<#
.SYNOPSIS
  Create / list / get / delete / run "report options" -- named saved sets of
  input-control values stored beside a report -- via the REST v2 `options`
  service (a sibling of `inputControls`).

.DESCRIPTION
    create  POST /rest_v2/reports{uri}/options?label=NAME  body {ctrlId:[vals],…}
            -> 200 {uri,id,label}; the option lands as a sibling resource.
    list    GET  /rest_v2/reports{uri}/options -> {reportOptionsSummary:[…]}
    get     GET  /rest_v2/reports{uri}/options/{id}
    delete  DELETE /rest_v2/reports{uri}/options/{id}
    run     run the option's OWN sibling URI as a report:
            GET /rest_v2/reports/<folder>/<id>.<fmt>  (verified: a ?reportOptions=
            query on the report URL does NOT apply saved values -- use the option URI).

  -Values is a hashtable of inputControlId -> value(s); each value is wrapped as
  the string array the service expects. The body is passed from a file so
  PowerShell->curl quoting can't mangle it.

  Credentials resolve: params -> JRS_URL/JRS_USER/JRS_PASS -> jrs.config.json.

.PARAMETER Action
  create | list | get | delete | run.

.PARAMETER ReportUri
  Repository URI of the report unit, e.g. /reports/foodmart/sample_report.

.PARAMETER Label
  Option label (create). Becomes the sibling resource leaf name.

.PARAMETER Id
  Option id (get/delete/run). For run, this is the saved option's leaf name.

.PARAMETER Values
  Hashtable of input-control id -> value or array of values (create).

.PARAMETER Format
  Output format for -Action run. Default pdf.

.PARAMETER OutFile
  Local path for -Action run output. Default <id>.<format>.

.EXAMPLE
  .\manage_options.ps1 -Action create -ReportUri /reports/foodmart/sample_report `
      -Label Food_Snacks -Values @{ category = "Food"; department = @("Snacks","Dairy") }
.EXAMPLE
  .\manage_options.ps1 -Action list -ReportUri /reports/foodmart/sample_report
.EXAMPLE
  .\manage_options.ps1 -Action run -ReportUri /reports/foodmart/sample_report -Id Food_Snacks
#>
[CmdletBinding()]
param(
    [ValidateSet("create", "list", "get", "delete", "run")]
    [string]$Action = "list",
    [Parameter(Mandatory)][string]$ReportUri,
    [string]$Label,
    [string]$Id,
    [hashtable]$Values,
    [ValidateSet("pdf", "html", "xlsx", "csv", "docx", "pptx")]
    [string]$Format = "pdf",
    [string]$OutFile,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password

if (-not $ReportUri.StartsWith("/")) { $ReportUri = "/$ReportUri" }
$folder = $ReportUri.Substring(0, $ReportUri.LastIndexOf("/"))
$optBase = "/rest_v2/reports$ReportUri/options"

switch ($Action) {
    "list" {
        $r = Invoke-JrsRest -Jrs $jrs -Method GET -Path $optBase
        if ($r.Code -eq "204") { Write-Host "No options found."; return }
        Assert-JrsOk -Response $r -Operation "list failed" | Out-Null
        Write-Output $r.Body
        return
    }
    "get" {
        if (-not $Id) { throw "-Id is required for get" }
        $r = Invoke-JrsRest -Jrs $jrs -Method GET -Path "$optBase/$Id"
        Assert-JrsOk -Response $r -Operation "get failed" | Out-Null
        Write-Output $r.Body
        return
    }
    "delete" {
        if (-not $Id) { throw "-Id is required for delete" }
        $r = Invoke-JrsRest -Jrs $jrs -Method DELETE -Path "$optBase/$Id"
        Assert-JrsOk -Response $r -Operation "delete failed" -Ok '^(2\d\d|404)$' | Out-Null
        Write-Host "OK ($($r.Code)): deleted option $Id"
        return
    }
    "run" {
        # run the option's OWN sibling URI as a report (the verified pattern)
        if (-not $Id) { throw "-Id is required for run" }
        if (-not $OutFile) { $OutFile = "$Id.$Format" }
        $url = "$($jrs.ServerUrl)/rest_v2/reports$folder/$Id.$Format"
        Invoke-JrsDownload -Jrs $jrs -Url $url -OutFile $OutFile | Out-Null
        Write-Host "OK: ran option $Id -> $OutFile ($((Get-Item $OutFile).Length) bytes)"
        return
    }
    "create" {
        if (-not $Label) { throw "-Label is required for create" }
        if (-not $Values -or -not $Values.Count) { throw "-Values is required for create" }
        # body is a flat map of controlId -> string array
        $body = [ordered]@{}
        foreach ($k in $Values.Keys) { $body[$k] = @($Values[$k] | ForEach-Object { "$_" }) }
        $f = [IO.Path]::GetTempFileName()
        ($body | ConvertTo-Json -Depth 6) | Set-Content -Path $f -Encoding utf8
        # the full literal URL (inline ?label= triggers the curl 000 quirk -- build it whole)
        try {
            $r = Invoke-JrsRest -Jrs $jrs -Method POST -Path "${optBase}?label=$Label" `
                -ContentType "application/json" -Accept "application/json" -JsonFile $f
        } finally { Remove-Item $f -ErrorAction SilentlyContinue }
        Assert-JrsOk -Response $r -Operation "create failed" | Out-Null
        Write-Host "OK ($($r.Code)): created option '$Label' on $ReportUri"
        if ($r.Body) { Write-Host $r.Body }
        return
    }
}
