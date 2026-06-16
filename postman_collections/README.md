# Jaspersoft REST API Postman Collection

A comprehensive Postman collection for the JasperReports Server 10.0.0 REST v2 API, with support for all major endpoints and workflows.

## Contents

- **Jaspersoft-REST-API-v10.json** — Complete API collection with 50+ endpoints organized by service
- **Jaspersoft-Environment.json** — Pre-configured environment for localhost testing

## Quick Start

### 1. Import the Collection

1. Open Postman
2. Click **Import** (top-left)
3. Select **Jaspersoft-REST-API-v10.json**
4. The collection appears in the left sidebar under "Jaspersoft REST API v10.0.0"

### 2. Import the Environment

1. Click the **Environments** icon (right sidebar)
2. Click **Import**
3. Select **Jaspersoft-Environment.json**
4. Select "Jaspersoft - Local" from the environment dropdown (top-right)

### 3. Configure Credentials (if needed)

The default environment is set to:
- **Base URL:** `http://localhost:8081/jasperserver-pro`
- **Username:** `superuser`
- **Password:** `superuser`

Edit the environment variables if your JasperServer uses different credentials.

## Endpoints Included

### Resources - Repository CRUD
- List resources by type/folder
- Get/delete resources
- List datasources

### Reports - Synchronous Execution
- Run reports as PDF, Excel, CSV, HTML, DOCX, PPTX
- Pass input control values as query parameters
- Quick ad-hoc report generation

### Report Executions - Asynchronous
- Submit large/slow reports for background execution
- Poll execution status
- Download outputs once ready
- Multi-format exports from one execution

### Input Controls
- List report input controls
- Get input control values (for dropdowns)
- Cascading control support (parent → child filtering)

### Jobs - Scheduling
- Create one-time or recurring scheduled reports
- Email delivery + repository save
- List/get/delete jobs
- Supports daily/weekly/monthly schedules

### Alerts - Data Threshold Notifications
- Create alerts that fire when report values cross a threshold
- Email notifications
- Manage alert lifecycle (CRUD)

### Permissions & Access Control
- Get explicit and effective permissions
- Grant/revoke read/write/admin rights by role
- Restore inheritance from parent folders

### Attributes
- Set server-level key-value pairs
- Usable in report expressions as `{attribute('name')}`
- Manage across server/org/user scopes

### Export & Import
- Export reports, dashboards, and folders as zip archives
- Import to clone, back up, or promote across servers
- Version-control entire apps

### Dashboards
- Get dashboard descriptors
- View dashboards in HTML5 viewer

### Domains (Semantic Layer)
- Query Domain metadata
- List available fields
- Build semantic-layer queries

### Options - Saved Input Control Sets
- Save named combinations of input control values
- Run reports with pre-set options
- Manage options lifecycle

### Organizations & Users
- List/get organizations
- List/get users and roles
- User/role management

## Common Workflows

### Run a Report Asynchronously

1. **Submit Execution** — POST to `/reportExecutions` with report URI and format
   - Copy `requestId` from response
   - Paste into `{{request_id}}` environment variable

2. **Poll Status** — GET `/reportExecutions/{{request_id}}/status`
   - Wait for `{"value":"ready"}`

3. **Download** — GET `/reportExecutions/{{request_id}}/exports/{{export_id}}/outputResource`
   - Save the PDF/Excel/CSV

### Schedule a Daily Report

1. **Create Job** — PUT to `/jobs` with:
   - Report URI
   - `startType: 1` (now) or `2` (at startDate)
   - `recurrenceInterval: 1, recurrenceIntervalUnit: DAY`
   - Email addresses for delivery

2. **Verify** — GET `/jobs?reportUnitURI=<uri>` to list

### Set Report Permissions

1. **Get Current** — GET `/permissions/reports/…` (see what's set)
2. **Set New** — PUT `/permissions/reports/…` with roles and mask values:
   - `1` = Administer
   - `2` = Read + Delete
   - `18` = Read + Write
   - `30` = Read-only
   - `32` = Execute-only

## Tips

### Variable Substitution

The collection uses Postman environment variables:
- `{{base_url}}` — defaults to localhost:8081
- `{{username}}` / `{{password}}` — HTTP Basic auth
- `{{request_id}}`, `{{export_id}}`, `{{job_id}}` — copy IDs from responses

To use a variable, copy the ID from the previous response and paste into the environment editor.

### Pre-request Scripts

The collection includes a pre-request script that auto-sets default environment variables if they're missing. You can still override them.

### Windows/PowerShell Users

When using curl/PowerShell directly (not Postman), remember:
- JSON bodies should be read from a file: `curl ... --data "@req.json"`
- Inline `-d '{...}'` fails due to quote mangling

### Async vs Sync Reports

- **Synchronous** (`GET /reports/{uri}.pdf`) — fast for small reports, blocks until done, times out on large fills
- **Asynchronous** (`POST /reportExecutions`) — proper for large reports, non-blocking, you poll for status

### HTTP Status Codes

- `200 OK` — Success
- `201 Created` — Resource created (PUT/POST)
- `204 No Content` — Success with no body (DELETE, GET empty lists)
- `400 Bad Request` — Validation error (check response body)
- `401 Unauthorized` — Bad credentials
- `403 Forbidden` — Permission denied
- `404 Not Found` — Resource doesn't exist
- `409 Conflict` — Version mismatch (use `?overwrite=true`)

## Reference

Full JasperReports Server 10.0.0 REST API documentation is available at:
- **Live WADL:** `http://localhost:8081/jasperserver-pro/rest_v2/application.wadl?detail=true`
- **PDF Docs:** Available in `docs/` directory (local install)

See `jrs-rest-api.md` in this project for a curated endpoint reference with verified workflows.

## Examples

### Export a Dashboard

```json
POST /rest_v2/export
{
  "uris": ["/reports/foodmart/top_customers_dashboard"]
}
```

Then poll `/rest_v2/export/{id}/state` until finished, then download from `/rest_v2/export/{id}/exportFile`.

### Run Report with Cascading Controls

```
GET /rest_v2/reports/reports/foodmart/sample_report.pdf?category=Food&department=Snacks
```

The API validates that the `department` value is valid for the selected `category` and filters accordingly.

### Create a Weekly Email Job

```json
PUT /rest_v2/jobs
{
  "label": "Weekly Sales Summary",
  "source": {"reportUnitURI": "/reports/foodmart/top_5_customers_revenue"},
  "trigger": {
    "simpleTrigger": {
      "startType": 1,
      "occurrenceCount": -1,
      "recurrenceInterval": 1,
      "recurrenceIntervalUnit": "WEEK"
    }
  },
  "baseOutputFilename": "weekly_sales",
  "outputFormats": {"outputFormat": ["PDF"]},
  "repositoryDestination": {"folderURI": "/reports/foodmart", "saveToRepository": true},
  "mailNotification": {"toAddresses": "team@example.com"}
}
```

---

**Last Updated:** June 16, 2026  
**JasperServer Version:** 10.0.0 (Enterprise/Pro)  
**API Version:** REST v2
