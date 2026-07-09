#Requires -Version 5.1
<#
.SYNOPSIS
    Compose deployed POS reports into a comprehensive dashboard
.DESCRIPTION
    Takes the deployed POS reports and composes them into a dashboard
    using the dashboard manifest and composition scripts.
.EXAMPLE
    .\compose_pos_dashboard.ps1
#>

param(
    [string]$SkillPath = ".\.claude\skills\jasper-deploy\scripts",
    [string]$ManifestPath = "report\pos\dashboard.json",
    [string]$DashboardUri = "/reports/pos/pos_comprehensive_dashboard",
    [string]$WorkDir = "out\pos_dashboard_build"
)

function Write-Success { Write-Host "  [OK] $args" -ForegroundColor Green }
function Write-Error_ { Write-Host "  [FAILED] $args" -ForegroundColor Red }
function Write-Info { Write-Host $args -ForegroundColor Cyan }

function Compose-Dashboard {
    Write-Info "`n=== POS Dashboard Composition ==="
    Write-Info "Manifest: $ManifestPath"
    Write-Info "Dashboard URI: $DashboardUri"
    Write-Info "Work Directory: $WorkDir"
    Write-Info ""

    # Verify manifest exists
    if (-not (Test-Path $ManifestPath)) {
        Write-Error_ "Manifest file not found: $ManifestPath"
        return $false
    }

    # Create work directory
    $WorkDirAbs = (Resolve-Path -Path (Split-Path $WorkDir -Parent)).Path + "\" + (Split-Path $WorkDir -Leaf)
    New-Item -ItemType Directory -Path $WorkDirAbs -Force | Out-Null
    Write-Success "Work directory created: $WorkDirAbs"

    # Load manifest
    $manifest = Get-Content $ManifestPath | ConvertFrom-Json

    Write-Info "`nDashboard: $($manifest.label)"
    Write-Info "Reports: $($manifest.dashlets | Where-Object { $_.kind -eq 'report' } | Measure-Object | Select-Object -ExpandProperty Count)"
    Write-Info ""

    # Create dashboard using compose_dashboard.ps1
    Write-Info "--- Composing Dashboard ---`n"

    try {
        # Call the build_dashlets script with the manifest to compose
        & "$SkillPath\build_dashlets.ps1" `
            -Manifest $ManifestPath `
            -Compose `
            -SkipVerify 2>&1 | ForEach-Object {
                if ($_ -match "OK|deployed|composed|success|created" -and $_ -notmatch "error|failed") {
                    Write-Host "  $_" -ForegroundColor Green
                } elseif ($_ -match "error|failed") {
                    Write-Host "  $_" -ForegroundColor Red
                } else {
                    Write-Host "  $_"
                }
            }

        Write-Success "Dashboard composition complete"
        return $true
    }
    catch {
        Write-Error_ "Dashboard composition failed: $_"
        return $false
    }
}

function Display-DashboardInfo {
    param([bool]$Success)

    Write-Info "`n=== Dashboard Deployment Complete ==="

    if ($Success) {
        Write-Info "`nDashboard Details:"
        Write-Info "  URI: /reports/pos/pos_comprehensive_dashboard"
        Write-Info "  Reports: 9 POS analysis tiles"
        Write-Info "  Layout: 2-column grid"
        Write-Info ""
        Write-Info "View Dashboard:"
        Write-Info "  HTML5 Viewer:"
        Write-Info "    http://localhost:8081/jasperserver-pro/dashboard/viewer.html#%2Freports%2Fpos%2Fpos_comprehensive_dashboard"
        Write-Info ""
        Write-Info "  Direct Links to Individual Reports:"
        Write-Info "    • KPI Summary: /reports/pos/pos_kpi_summary"
        Write-Info "    • Sales by Store: /reports/pos/pos_sales_by_store"
        Write-Info "    • Top 15 Products: /reports/pos/pos_sales_by_product"
        Write-Info "    • Daily Sales Trend: /reports/pos/pos_daily_sales_trend"
        Write-Info "    • Peak Hours: /reports/pos/pos_hourly_analysis"
        Write-Info "    • Loyalty Analysis: /reports/pos/pos_loyalty_analysis"
        Write-Info "    • Promotions: /reports/pos/pos_promotion_analysis"
        Write-Info "    • Returns & Voids: /reports/pos/pos_returns_voids_analysis"
        Write-Info "    • Weekly Pattern: /reports/pos/pos_weekly_pattern"
        Write-Info ""
        Write-Success "Dashboard is ready!"
    } else {
        Write-Error_ "Dashboard composition encountered issues"
        Write-Info "Individual reports are still available at /reports/pos/"
    }
}

# Main execution
$success = Compose-Dashboard
Display-DashboardInfo -Success $success

exit $(if ($success) { 0 } else { 1 })
