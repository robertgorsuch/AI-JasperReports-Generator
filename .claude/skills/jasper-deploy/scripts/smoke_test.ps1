<#
.SYNOPSIS
  End-to-end smoke test of the jasper-deploy pipeline. Run after editing any
  script to confirm nothing regressed.

.DESCRIPTION
  Exercises, against the foodmart DB + JRS, under a throwaway -Folder:
    scaffold (chart + param + highlight) -> compile -> deploy (+ input control)
    -> verify_report (content) -> run to PDF -> schedule_job CRUD -> manage_alert
    CRUD -> compose a dashboard (report + text tile) -> style template (.jrtx)
    referenced by a report -> single-table Domain -> non-JDBC (jndi) datasource
    -> UI theme deploy -> teardown.
  Prints PASS/FAIL per step and throws if any step fails. Leaves nothing behind
  unless -KeepArtifacts.

.EXAMPLE
  $env:PGPASSWORD = "postgres"; .\smoke_test.ps1
#>
[CmdletBinding()]
param(
    [string]$Folder = "/reports/_smoke",
    [string]$Database = "foodmart",
    [string]$DataSourceUri = "/public/Samples/Data_Sources/FoodmartDataSource",
    [switch]$KeepArtifacts,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password
$cred = @{ ServerUrl = $jrs.ServerUrl; User = $jrs.User; Password = $jrs.Password }
if (-not $env:PGPASSWORD) { Write-Warning "PGPASSWORD not set; scaffold introspection may fail" }
$skill = $PSScriptRoot
$work = "out\smoke"; New-Item -ItemType Directory -Force $work | Out-Null
$rptUri = "$Folder/smoke_rpt"; $dashUri = "$Folder/smoke_dash"
$themeName = "jd_smoke_theme"; $dsLeaf = ($DataSourceUri -split "/")[-1]
$script:pass = 0; $script:fail = 0
function step($name, $ok) {
    if ($ok) { Write-Host "PASS  $name"; $script:pass++ } else { Write-Host "FAIL  $name"; $script:fail++ }
}

try {
    # 1. scaffold
    @"
SELECT pc.product_family AS family, round(sum(s.store_sales),0)::numeric AS sales
FROM sales_fact_1997 s JOIN product p ON p.product_id=s.product_id
JOIN product_class pc ON pc.product_class_id=p.product_class_id
GROUP BY 1 ORDER BY 2 DESC
"@ | Set-Content "$work\smoke.sql" -Encoding ascii
    $jrxml = "$work\smoke_rpt.jrxml"
    & python "$skill\scaffold_jrxml.py" --name smoke_rpt --db $Database --title "Smoke Test" `
        --chart bar --chart-label-rotation -30 --highlight "sales:>:100000:#FFE0B2" `
        --query-file "$work\smoke.sql" --out $jrxml | Out-Null
    step "scaffold" (Test-Path $jrxml)

    # 2. compile
    step "compile" (Invoke-JrCompile -Jrxml $jrxml)

    # 3. deploy (with a single-select input control on family)
    & "$skill\deploy_report.ps1" -Jrxml $jrxml -TargetUri $rptUri -Label "Smoke Test" `
        -DataSourceUri $DataSourceUri -Overwrite `
        -Control "family:select:Family:Food;Drink;Non-Consumable" @cred *>$null
    $r = Invoke-JrsGet -Jrs $jrs -Uri $rptUri
    step "deploy" ($r.Code -match '^2\d\d$')

    # 4. verify content
    $vok = $true
    try { & "$skill\verify_report.ps1" -Uri $rptUri -MinRows 3 -Contains "Food" @cred *>$null }
    catch { $vok = $false }
    step "verify-content" $vok

    # 5. run to PDF
    $pdf = "$work\smoke_rpt.pdf"
    $code = & curl.exe -s -o $pdf -w "%{http_code}" -u "$($jrs.User):$($jrs.Password)" "$($jrs.ServerUrl)/rest_v2/reports$rptUri.pdf"
    step "run-pdf" ("$code".Trim() -eq "200" -and ((Get-Content $pdf -Raw) -like "%PDF-*"))

    # 5b. schedule_job CRUD round-trip on the smoke report (far-future so it
    #     never fires before we delete it)
    $jobOk = $false
    try {
        & "$skill\schedule_job.ps1" -ReportUri $rptUri -Label "smoke job" -StartDate "2099-01-01 09:00:00" @cred *>$null
        $jid = ((& "$skill\schedule_job.ps1" -Action list -ReportUri $rptUri @cred) | ConvertFrom-Json).jobsummary.id
        & "$skill\schedule_job.ps1" -Action delete -Id $jid @cred *>$null
        $jobOk = $null -ne $jid
    } catch { $jobOk = $false }
    step "schedule-job" $jobOk

    # 5c. manage_alert CRUD round-trip (placeholder element uuid -- create only
    #     validates the descriptor shape; far-future so it doesn't self-remove)
    $alertOk = $false
    try {
        & "$skill\manage_alert.ps1" -ReportUri $rptUri -Label "smoke alert" `
            -ElementUuid "00000000-0000-0000-0000-000000000001" -Operator ">" -Threshold 1 `
            -MailTo smoke@example.com -StartType at -StartDate "2099-01-01 09:00:00" @cred *>$null
        $aid = ((& "$skill\manage_alert.ps1" -Action list -ReportUri $rptUri @cred) | ConvertFrom-Json).alertsummary.id
        & "$skill\manage_alert.ps1" -Action delete -Id $aid @cred *>$null
        $alertOk = $null -ne $aid
    } catch { $alertOk = $false }
    step "alert-crud" $alertOk

    # 6. compose a dashboard (report tile + text tile)
    $manifest = "$work\smoke_dash.json"
    @"
{ "folder": "$Folder", "name": "smoke_dash", "label": "Smoke Dash",
  "dashlets": [
    {"kind":"text","name":"Hdr","text":"Smoke","size":14,"bold":true,"x":0,"y":0,"width":40,"height":3},
    {"kind":"report","name":"smoke_rpt","title":"Smoke Test","x":0,"y":3,"width":40,"height":12} ] }
"@ | Set-Content $manifest -Encoding ascii
    & "$skill\compose_dashboard.ps1" -Manifest $manifest @cred *>$null
    $d = Invoke-JrsGet -Jrs $jrs -Uri $dashUri
    step "compose-dashboard" ($d.Code -match '^2\d\d$')

    # 6b. style template (.jrtx) -> a report referencing it runs to PDF
    $styleOk = $false
    try {
        & python "$skill\scaffold_style_template.py" --name jd_smoke --palette corporate --out "$work\jd_smoke.jrtx" *>$null
        & "$skill\upload_file.ps1" -File "$work\jd_smoke.jrtx" -Uri "$Folder/jd_smoke" -Type xml -Overwrite @cred *>$null
        & python "$skill\scaffold_jrxml.py" --name smoke_styled --db $Database --title "Styled" `
            --style-template "$Folder/jd_smoke" --query-file "$work\smoke.sql" --out "$work\smoke_styled.jrxml" *>$null
        & "$skill\deploy_report.ps1" -Jrxml "$work\smoke_styled.jrxml" -TargetUri "$Folder/smoke_styled" `
            -Label "Styled" -DataSourceUri $DataSourceUri -Overwrite @cred *>$null
        $sc = & curl.exe -s -o "$work\smoke_styled.pdf" -w "%{http_code}" -u "$($jrs.User):$($jrs.Password)" "$($jrs.ServerUrl)/rest_v2/reports$Folder/smoke_styled.pdf"
        $styleOk = ("$sc".Trim() -eq "200" -and ((Get-Content "$work\smoke_styled.pdf" -Raw) -like "%PDF-*"))
    } catch { $styleOk = $false }
    step "style-template" $styleOk

    # 6c. single-table Domain (semantic layer) over the smoke datasource's product table
    $domOk = $false
    try {
        & python "$skill\scaffold_domain_schema.py" --name smoke_dom --table product --db $Database `
            --datasource-id $dsLeaf --out "$work\smoke_dom_schema.xml" *>$null
        & "$skill\create_domain.ps1" -Uri "$Folder/smoke_domain" -SchemaFile "$work\smoke_dom_schema.xml" `
            -DataSourceUri $DataSourceUri -Label "Smoke Domain" -Overwrite @cred *>$null
        $domOk = (Invoke-JrsGet -Jrs $jrs -Uri "$Folder/smoke_domain").Code -match '^2\d\d$'
    } catch { $domOk = $false }
    step "domain" $domOk

    # 6d. non-JDBC datasource (jndi -- descriptor-shape validation)
    $dsOk = $false
    try {
        & "$skill\create_datasource.ps1" -Type jndi -Uri "$Folder/smoke_jndi" -JndiName jdbc/smoke -Overwrite @cred *>$null
        $dsOk = (Invoke-JrsGet -Jrs $jrs -Uri "$Folder/smoke_jndi").Code -match '^2\d\d$'
    } catch { $dsOk = $false }
    step "datasource-jndi" $dsOk

    # 6e. UI theme scaffold + deploy (cleaned up in finally -- it lives under /themes)
    $themeOk = $false
    try {
        & python "$skill\scaffold_theme.py" --name $themeName --palette corporate --out "$work\overrides_custom.css" *>$null
        & "$skill\deploy_theme.ps1" -CssFile "$work\overrides_custom.css" -Name $themeName -Overwrite @cred *>$null
        $themeOk = (Invoke-JrsGet -Jrs $jrs -Uri "/themes/$themeName/overrides_custom.css").Code -match '^2\d\d$'
    } catch { $themeOk = $false }
    step "theme" $themeOk
}
finally {
    if (-not $KeepArtifacts) {
        # 7. teardown (dashboard, report, control folder, then the smoke folder,
        #    plus the UI theme which lives under /themes outside $Folder)
        try { & "$skill\teardown_dashboard.ps1" -Uri $dashUri -IncludeReports @cred *>$null } catch {}
        Invoke-JrsDelete -Jrs $jrs -Uri $Folder | Out-Null
        Invoke-JrsDelete -Jrs $jrs -Uri "/themes/$themeName" | Out-Null
        $gone = (Invoke-JrsGet -Jrs $jrs -Uri $dashUri).Code -notmatch '^2\d\d$'
        step "teardown" $gone
    }
}

Write-Host ""
Write-Host "smoke test: $script:pass passed, $script:fail failed"
if ($script:fail -gt 0) { throw "smoke test FAILED ($script:fail step(s))" }
Write-Host "OK: smoke test passed"
