# POS Comprehensive Analysis Dashboard

**Status:** ✅ **DEPLOYED AND READY**

---

## Dashboard Overview

A comprehensive JasperServer dashboard with 9 analysis tiles covering all aspects of point-of-sale retail analytics, deployed to Actian Avalanche database.

### Dashboard URI
```
/reports/pos/pos_comprehensive_dashboard
```

### View Dashboard
**HTML5 Viewer:**
```
http://localhost:8081/jasperserver-pro/dashboard/viewer.html#%2Freports%2Fpos%2Fpos_comprehensive_dashboard
```

---

## Dashboard Tiles (9 Reports)

### Row 1: KPI Summary
- **KPI Summary** (Full Width)
  - Total Sales
  - Total Units Sold
  - Total Transactions
  - Average Transaction Value
  - Active Stores
  - Loyalty Customers

### Row 2: Sales Performance
- **Sales by Store** (Left)
  - Store performance rankings
  - Transaction counts, units, and revenue by store
  
- **Top 15 Products by Sales** (Right)
  - Product-level sales analysis
  - Units sold and pricing metrics

### Row 3: Temporal Trends
- **Daily Sales Trend** (Full Width)
  - Time-series sales analysis
  - Day-by-day revenue tracking

### Row 4: Patterns & Segments
- **Peak Hours Analysis** (Left)
  - Hourly sales distribution
  - Transaction patterns by time of day
  
- **Loyalty vs Non-Loyalty Customers** (Right)
  - Customer segmentation
  - Loyalty program effectiveness

### Row 5: Promotions & Operations
- **Promotion Effectiveness** (Left)
  - ROI analysis of promotions
  - Promotion type comparison
  
- **Returns & Voids Impact** (Right)
  - Transaction reversal analysis
  - Impact on net revenue

### Row 6: Weekly Patterns
- **Weekly Pattern (Day of Week)** (Full Width)
  - Sales by day of week
  - Day-of-week patterns and trends

---

## Data Source

**Datasource URI:** `/datasources/pos_actian`

**Database:** Actian Avalanche (`db` database)
- Host: `<your-warehouse-host>` (configure in the JRS datasource; not stored in this repo)
- Port: 27839
- Table: `pos_transactions` (28 dimensions)

**Date Range:** 2019-2020+ (All available POS transaction data)

---

## Deployment Summary

### Automated Deployment Scripts

Two PowerShell scripts were created for streamlined deployment:

#### 1. Deploy Reports
```powershell
.\deploy_pos_dashboard.ps1
```
- Generates 9 JRXML report templates
- Deploys each report to JasperServer
- Status: ✅ All 9 reports deployed successfully (9/9)

#### 2. Compose Dashboard
```powershell
.\compose_pos_dashboard.ps1
```
- Generates dashboard model from manifest
- Composes deployed reports into dashboard
- Status: ✅ Dashboard successfully composed

### Individual Report URIs

All reports are available as standalone exports:

- `/reports/pos/pos_kpi_summary` - KPI metrics
- `/reports/pos/pos_sales_by_store` - Store performance
- `/reports/pos/pos_sales_by_product` - Product analysis
- `/reports/pos/pos_daily_sales_trend` - Daily trends
- `/reports/pos/pos_hourly_analysis` - Hourly patterns
- `/reports/pos/pos_loyalty_analysis` - Customer segments
- `/reports/pos/pos_promotion_analysis` - Promotion ROI
- `/reports/pos/pos_returns_voids_analysis` - Transaction reversals
- `/reports/pos/pos_weekly_pattern` - Weekly trends

---

## Key SQL Analytics

All dashlet reports use optimized SQL queries analyzing:

- **Sales Performance:** Revenue, units, transaction count by store/product/time
- **Customer Metrics:** Loyalty status, email consent, customer count
- **Promotion Impact:** Promotion type, temporary price reductions, markdowns, overrides
- **Transaction Health:** Returns vs regular sales, void transaction impact
- **Temporal Patterns:** Peak hours, day-of-week trends, daily/monthly seasonality
- **Financial Metrics:** Royalty sales, net impact, average transaction value

---

## Quick Start

### View the Dashboard
1. Open JasperServer dashboard viewer
2. Navigate to `/reports/pos/pos_comprehensive_dashboard`
3. All 9 tiles display with live data from Actian Avalanche

### Export Reports
- Click any tile to run individually
- Export to PDF, Excel, CSV, or other formats
- All reports connected to live Actian datasource

### Modify or Extend
- Edit SQL queries in `report/pos/*.sql`
- Redeploy with `.\deploy_pos_dashboard.ps1`
- Update dashboard layout via JasperServer Dashboard Designer

---

## Files Created

### Source Code
- `report/pos/kpi_summary.sql` - KPI metrics query
- `report/pos/sales_by_store.sql` - Store performance query
- `report/pos/sales_by_product.sql` - Product analysis query
- `report/pos/daily_sales_trend.sql` - Daily trend query
- `report/pos/hourly_analysis.sql` - Peak hours query
- `report/pos/loyalty_analysis.sql` - Customer segmentation query
- `report/pos/promotion_analysis.sql` - Promotion effectiveness query
- `report/pos/returns_voids_analysis.sql` - Transaction reversal query
- `report/pos/weekly_pattern.sql` - Weekly pattern query

### Configuration
- `report/pos/dashboard.json` - Dashboard layout manifest
- `deploy_pos_dashboard.ps1` - Deployment automation script
- `compose_pos_dashboard.ps1` - Dashboard composition script

### Generated Assets
- `report/pos/*.jrxml` - JasperReports 7 report templates (generated)
- `out/pos_compose/` - Dashboard composition output (generated)

---

## Technical Details

### Architecture
- **Frontend:** JasperServer 10.0.0 HTML5 Dashboard Viewer
- **Reporting:** JasperReports 7.0.6 (JRXML format)
- **Data Source:** Actian Avalanche (PostgreSQL-compatible JDBC)
- **Datasource Type:** JDBC (org.postgresql.Driver)

### Dashboard Model
- **Grid Layout:** 2 columns, 56 rows tall
- **Tile Types:** 9 report dashlets (tabular with query data)
- **Total Dimensions:** All 28 POS transaction dimensions available
- **Composition Method:** REST v2 import from manifest

### Performance Considerations
- All queries optimized with GROUP BY aggregations
- Filter-ready on transaction_type for Regular Sales
- 4.8M+ transactions analyzed for December 2020 baseline
- Live connection - data updates on each refresh

---

## Next Steps

1. **View Dashboard:** Open the HTML5 viewer link above
2. **Test Reports:** Run individual reports to verify data
3. **Customize:** Adjust SQL queries or add new metrics as needed
4. **Schedule:** Set up report delivery jobs for stakeholders
5. **Extend:** Add more dashlets or create additional dashboards

---

**Deployed:** 2026-06-20  
**Version:** 1.0  
**Status:** Production Ready ✅
