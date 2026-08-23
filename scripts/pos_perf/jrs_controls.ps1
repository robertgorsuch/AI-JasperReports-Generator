# scripts/pos_perf/jrs_controls.ps1 -- create the shared finance controls once
# under /reports/pos_perf/controls and attach any subset to a report unit.
# Usage:
#   . .\scripts\pos_perf\jrs_controls.ps1
#   New-FinanceControls                      # idempotent: creates each control once, skips if present
#   Attach-Controls -ReportUri /reports/pos_perf/trs_ar_aging -ControlUris @("/reports/pos_perf/controls/p_asof","/reports/pos_perf/controls/p_regions")
param([string]$Env = $env:JRS_ENV)
. (Join-Path $PSScriptRoot "..\..\.claude\skills\jasper-deploy\scripts\_jrs_common.ps1")
$script:jrs = Resolve-JrsConfig -Env $Env
$script:ctl = "/reports/pos_perf/controls"
$script:ds  = "/datasources/pos_data_avalanche"

function Put-Json([string]$Uri, [string]$ContentType, [string]$Json) {
    $f = [IO.Path]::GetTempFileName()
    $Json | Set-Content $f -Encoding utf8
    try { $r = Invoke-JrsPut -Jrs $script:jrs -Uri $Uri -Overwrite -ContentType $ContentType -JsonFile $f }
    finally { Remove-Item $f -ErrorAction SilentlyContinue }
    Assert-JrsOk -Response $r -Operation "PUT $Uri" | Out-Null
    Write-Host "OK: $Uri"
}

function Test-JrsExists([string]$Uri) {
    $r = Invoke-JrsGet -Jrs $script:jrs -Uri $Uri
    return ("$($r.Code)" -match '^2\d\d$')
}

function New-LovControl([string]$Name, [string]$Label, [string[]]$Items) {
    # Idempotence: once $Name exists, skip re-creating it. A re-PUT of the LOV
    # sub-resource (even with -Overwrite) 403s once an inputControl references
    # it -- JRS does a delete+insert of the JIListOfValues row under overwrite,
    # which trips the FK from JIInputControl to the (about to be deleted) old
    # row ("... still referenced from table jiinputcontrol", errorCode
    # resource.in.use). Verified empirically against STAGE. Since these values
    # are static, "create once, skip if present" is both safe and matches the
    # brief's own description of this script ("create ... once").
    if (Test-JrsExists "$script:ctl/$Name") { Write-Host "OK (exists, skipped): $script:ctl/$Name"; return }
    # Items are "label=value" pairs. JSON is built by hand: PS 5.1 unwraps 1-element arrays.
    $itemJson = ($Items | ForEach-Object { $kv = $_.Split("=", 2); "{`"label`":`"$($kv[0])`",`"value`":`"$($kv[1])`"}" }) -join ","
    Put-Json "$script:ctl/${Name}_lov" "application/repository.listOfValues+json" "{`"label`":`"$Label values`",`"items`":[$itemJson]}"
    Put-Json "$script:ctl/$Name" "application/repository.inputControl+json" ("{`"label`":`"$Label`",`"mandatory`":false,`"readOnly`":false,`"visible`":true,`"type`":3," +
        "`"listOfValues`":{`"listOfValuesReference`":{`"uri`":`"$script:ctl/${Name}_lov`",`"version`":0}}}")
}

function New-QueryControl([string]$Name, [string]$Label, [string]$ValueCol, [string]$Sql, [int]$Type) {
    # Same idempotence guard as New-LovControl, and for the same reason: the
    # query sub-resource hits the identical FK-on-overwrite 403 once
    # referenced by its inputControl.
    if (Test-JrsExists "$script:ctl/$Name") { Write-Host "OK (exists, skipped): $script:ctl/$Name"; return }
    Put-Json "$script:ctl/${Name}_query" "application/repository.query+json" ("{`"label`":`"$Name query`",`"language`":`"sql`",`"value`":`"$($Sql -replace '"','\"')`"," +
        "`"dataSource`":{`"dataSourceReference`":{`"uri`":`"$script:ds`",`"version`":0}}}")
    Put-Json "$script:ctl/$Name" "application/repository.inputControl+json" ("{`"label`":`"$Label`",`"mandatory`":false,`"readOnly`":false,`"visible`":true,`"type`":$Type," +
        "`"valueColumn`":`"$ValueCol`",`"visibleColumns`":[`"$ValueCol`"]," +
        "`"query`":{`"queryReference`":{`"uri`":`"$script:ctl/${Name}_query`",`"version`":0}}}")
}

function New-FinanceControls {
    $months = @()
    foreach ($y in 2019, 2020) { foreach ($m in 1..12) { $ym = "{0}{1:00}" -f $y, $m; $months += "$ym=$ym" } }
    New-LovControl -Name "p_yyyymm"  -Label "Month"          -Items $months
    New-LovControl -Name "p_asof"    -Label "As of month"    -Items $months
    New-LovControl -Name "p_version" -Label "Budget version" -Items @("Original=Original", "Reforecast Q2 2020=Reforecast Q2 2020")
    New-LovControl -Name "p_province" -Label "Province" -Items @("All=All","ON=ON","QC=QC","BC=BC","AB=AB","SK=SK","MB=MB","NB=NB","NL=NL","NS=NS","PE=PE","YT=YT","NT=NT")
    New-QueryControl -Name "p_franchisee" -Label "Franchisee" -ValueCol "franchisee_id" -Sql "SELECT DISTINCT franchisee_id FROM franchisees ORDER BY 1" -Type 7
    New-QueryControl -Name "p_store" -Label "Store" -ValueCol "storenumber" -Sql "SELECT DISTINCT storenumber FROM stores ORDER BY 1" -Type 4
}

function Attach-Controls([string]$ReportUri, [string[]]$ControlUris) {
    $cur = Invoke-JrsGet -Jrs $script:jrs -Uri $ReportUri
    Assert-JrsOk -Response $cur -Operation "GET $ReportUri" | Out-Null
    $ru = $cur.Body | ConvertFrom-Json
    # Drop any existing inputControls property before serializing (a prior
    # Attach-Controls call may have left one, as an object OR an array) so
    # ConvertTo-Json never has a chance to touch it -- PS 5.1's ConvertTo-Json
    # unwraps a one-element array into a scalar object, which the server
    # rejects with a 400 "ArrayList from String value". The array is instead
    # built as literal JSON text below and spliced in, for both the
    # one-control and N-control cases, so the trap never applies.
    if ($ru.PSObject.Properties.Name -contains "inputControls") {
        $ru.PSObject.Properties.Remove("inputControls")
    }
    $ru | Add-Member -NotePropertyName controlsLayout -NotePropertyValue "popupScreen" -Force
    $json = $ru | ConvertTo-Json -Depth 12
    $icJson = "[" + (($ControlUris | ForEach-Object { "{`"inputControlReference`":{`"uri`":`"$_`"}}" }) -join ",") + "]"
    $json = $json -replace '^\{', ('{"inputControls":' + $icJson + ',')
    Put-Json $ReportUri "application/repository.reportUnit+json" $json
}
