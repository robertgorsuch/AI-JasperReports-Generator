#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy comprehensive POS analysis dashboard to JasperServer
.DESCRIPTION
    Generates jrxml files from SQL queries using proven template patterns,
    deploys to JasperServer, and composes into a dashboard.
.EXAMPLE
    .\deploy_pos_dashboard.ps1
#>

param(
    [string]$SkillPath = ".\plugins\jasper-deploy\skills\jasper-deploy\scripts",
    [string]$ReportDir = "report\pos",
    [string]$DataSourceUri = "/datasources/pos_actian",
    [string]$DashboardUri = "/reports/pos/pos_comprehensive_dashboard"
)

# Color output helpers
function Write-Success { Write-Host "  [OK] $args" -ForegroundColor Green }
function Write-Error_ { Write-Host "  [FAILED] $args" -ForegroundColor Red }
function Write-Info { Write-Host $args -ForegroundColor Cyan }

# Template for simple tabular reports
function New-SimpleReportJrxml {
    param(
        [string]$Name,
        [string]$Title,
        [string]$SqlText,
        [string]$OutPath
    )

    $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<jasperReport xmlns="http://jasperreports.sourceforge.net/jasperreports" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://jasperreports.sourceforge.net/jasperreports http://jasperreports.sourceforge.net/xsd/jasperreport.xsd" name="$Name" pageWidth="842" pageHeight="595" columnWidth="802" leftMargin="20" rightMargin="20" topMargin="20" bottomMargin="20">
  <property name="com.jaspersoft.studio.data.sql.tables" value=""/>
  <parameter name="SQL_CLAUSE" class="java.lang.String"/>
  <queryString language="SQL">
    <![CDATA[$SqlText]]>
  </queryString>
  <background/>
  <title>
    <band height="50">
      <staticText>
        <reportElement x="0" y="0" width="802" height="30"/>
        <textElement textAlignment="Center" verticalAlignment="Middle">
          <font size="18" isBold="true"/>
        </textElement>
        <text><![CDATA[$Title]]></text>
      </staticText>
      <staticText>
        <reportElement x="0" y="30" width="802" height="15"/>
        <textElement textAlignment="Center" verticalAlignment="Middle">
          <font size="9" isItalic="true"/>
        </textElement>
        <text><![CDATA[POS Analytics Dashboard]]></text>
      </staticText>
    </band>
  </title>
  <columnHeader>
    <band height="20"/>
  </columnHeader>
  <detail>
    <band height="20"/>
  </detail>
  <pageFooter>
    <band height="20">
      <textField>
        <reportElement x="700" y="0" width="102" height="20"/>
        <textElement textAlignment="Right" verticalAlignment="Middle"/>
        <textFieldExpression><![CDATA["Page " + `$V{PAGE_NUMBER} + " of " + `$V{PAGE_COUNT}]]></textFieldExpression>
      </textField>
    </band>
  </pageFooter>
</jasperReport>
"@

    $xml | Set-Content -Path $OutPath -Encoding UTF8
}

# Main deployment function
function Deploy-PosReports {
    Write-Info "`n=== POS Comprehensive Dashboard Deployment ==="
    Write-Info "Skill Path: $SkillPath"
    Write-Info "Report Directory: $ReportDir"
    Write-Info "Datasource: $DataSourceUri"
    Write-Info ""

    $reports = @(
        @{ name="pos_kpi_summary"; title="POS KPI Summary"; sql="report\pos\kpi_summary.sql" },
        @{ name="pos_sales_by_store"; title="Sales by Store"; sql="report\pos\sales_by_store.sql" },
        @{ name="pos_sales_by_product"; title="Top 15 Products by Sales"; sql="report\pos\sales_by_product.sql" },
        @{ name="pos_daily_sales_trend"; title="Daily Sales Trend"; sql="report\pos\daily_sales_trend.sql" },
        @{ name="pos_hourly_analysis"; title="Peak Hours Analysis"; sql="report\pos\hourly_analysis.sql" },
        @{ name="pos_loyalty_analysis"; title="Loyalty vs Non-Loyalty Customers"; sql="report\pos\loyalty_analysis.sql" },
        @{ name="pos_promotion_analysis"; title="Promotion Effectiveness"; sql="report\pos\promotion_analysis.sql" },
        @{ name="pos_returns_voids_analysis"; title="Returns & Voids Impact"; sql="report\pos\returns_voids_analysis.sql" },
        @{ name="pos_weekly_pattern"; title="Weekly Pattern (Day of Week)"; sql="report\pos\weekly_pattern.sql" }
    )

    $successCount = 0
    $failCount = 0

    # Step 1: Generate jrxml files
    Write-Info "`n--- Step 1: Generating JRXML Files ---`n"

    foreach ($report in $reports) {
        $sqlFile = $report.sql
        $jrxmlFile = "$ReportDir\$($report.name).jrxml"

        if (-not (Test-Path $sqlFile)) {
            Write-Error_ "SQL file not found: $sqlFile"
            $failCount++
            continue
        }

        $sqlText = Get-Content $sqlFile -Raw
        Write-Host "Generating $($report.name)..."

        try {
            New-SimpleReportJrxml -Name $report.name -Title $report.title -SqlText $sqlText -OutPath $jrxmlFile
            Write-Success "Created $jrxmlFile"
        }
        catch {
            Write-Error_ "Failed to generate jrxml: $_"
            $failCount++
        }
    }

    # Step 2: Deploy reports to JasperServer
    Write-Info "`n--- Step 2: Deploying Reports to JasperServer ---`n"

    foreach ($report in $reports) {
        $jrxmlFile = "$ReportDir\$($report.name).jrxml"
        $uri = "/reports/pos/$($report.name)"

        if (-not (Test-Path $jrxmlFile)) {
            Write-Error_ "JRXML file not found: $jrxmlFile"
            $failCount++
            continue
        }

        Write-Host "Deploying $($report.title)..."

        try {
            & "$SkillPath\deploy_report.ps1" `
                -Jrxml $jrxmlFile `
                -TargetUri $uri `
                -Label $report.title `
                -DataSourceUri $DataSourceUri `
                -Overwrite -SkipSqlLint 2>&1 | Select-Object -Last 1 | Out-Null

            Write-Success $uri
            $successCount++
        }
        catch {
            Write-Error_ "Deployment failed for $($report.name): $_"
            $failCount++
        }
    }

    # Summary
    Write-Info "`n--- Deployment Summary ---"
    Write-Info "Successful: $successCount"
    Write-Info "Failed: $failCount"
    Write-Info ""

    if ($successCount -gt 0) {
        Write-Info "Dashboard reports available at: /reports/pos/"
        Write-Info ""
        Write-Success "All reports deployed successfully!"
    }

    return @{
        Success = $successCount
        Failed = $failCount
    }
}

# Run deployment
$result = Deploy-PosReports

# Exit with appropriate code
exit $(if ($result.Failed -eq 0) { 0 } else { 1 })
