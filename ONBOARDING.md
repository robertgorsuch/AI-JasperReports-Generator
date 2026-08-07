# Onboarding Guide

Welcome to `AI-JasperReports-Generator` — a working reference for **BI pipeline automation using Jaspersoft and Claude Code**, built by the Actian SE team.

This guide gets you oriented in about 10 minutes. For full operational detail, see `RUNBOOK.md`.

---

## Who this is for

This project is used by **Actian/HCLSoftware SEs and technical staff** to:
- Demo JasperReports Server capabilities to customers and prospects
- Prototype report automation pipelines using Claude Code skills
- Develop and test the `jasper-deploy` skill against a local JRS environment
- Provide a reference implementation for customers evaluating Jaspersoft embedded analytics

If you are a **customer or partner** reviewing this repo, it demonstrates what's possible when you combine JasperReports Server 10 Pro's REST API with AI-assisted automation tooling.

---

## What this project is

Three things in one repo:

**1. A statewide Texas address geocoder**
Built on PostgreSQL 14 + PostGIS 3.4. All 254 Texas counties are loaded via the TIGER geocoder — 5.7M edges, 5M feature names, 2.7M address ranges. The geocoder is the data foundation for everything else.

**2. A JasperReports 7 report suite**
A 317-page block-group density report compiled from the same PostGIS database, plus chart, crosstab, drill-down, and dashboard samples under `report/`. (Leaflet map visualizations can also be generated locally into `maps/` — generated HTML is not tracked in the repo.)

**3. A full JRS automation toolkit**
The `jasper-deploy` Claude Code skill (48 PowerShell/Python scripts) and a self-service web wizard (Jakarta servlet WAR) that together automate the entire JasperReports Server lifecycle — design, compile, lint, deploy, verify, dashboard composition, single- and multi-table Domains, live datasource connection tests, usage reporting, diagnostics, Visualize.js embedding, admin, governance, and STAGE→PROD promotion via named environment profiles. The skill also carries a doc-derived reference library covering **JasperReports Server 4.7 through 10.1** — version deltas, platform-support cliffs, vendor EOL dates, and a cross-version upgrade/migration playbook (`references/upgrade-migration-playbook.md`, start at its section 0).

The skill is also installable into Claude Code as a **plugin** without cloning this repo — see "Install as a Claude Code plugin" in `README.md` (`/plugin marketplace add robertgorsuch/AI-JasperReports-Generator`, then `/plugin install jasper-deploy@jaspersoft-tools`). If you work in this repo directly, do NOT install the plugin: the project-level skill already loads, and both would load twice.

---

## Get oriented fast

### The database

```
Host:     localhost:5432
DB:       postgis_34_sample
User:     postgres
Password: (set PGPASSWORD in your environment — never hardcode it)
```

Extensions: `postgis`, `postgis_tiger_geocoder`, `address_standardizer`.

Test the geocoder:

```sql
SELECT g.rating, pprint_addy(g.addy)
FROM geocode('1100 Congress Ave, Austin, TX 78701', 1) AS g;
-- Expected: rating 0 (exact match)
```

### JasperReports Server

```
URL:  http://localhost:8081/jasperserver-pro
Auth: superuser / superuser  (HTTP Basic)
```

> Port 8080 is a separate, unrelated service — not JRS.

### Key directories

| Path | What it is |
|---|---|
| `scripts/` | TIGER data loaders (idempotent, verified with `7z t`) |
| `report/` | JasperReports templates, compile/fill harnesses, Foodmart KPI reports |
| `plugins/jasper-deploy/skills/jasper-deploy/` | The automation skill — read `SKILL.md` first, then `references/` for detail |
| `webapp/jasper-wizard/` | Self-service web wizard — see its `README.md` |
| `maps/`, `backups/` | Generated artifacts (Leaflet HTML, JRS export zips) — local-only, not tracked |
| `docs/` | Vendor PDF corpus (220 JRS docs, 4.7→10.1) — **machine-local, gitignored** (not redistributable); the distilled summaries live in the skill's `references/` |
| `.claude-plugin/` | Plugin + marketplace manifests that make the skill installable via `/plugin install` |
| `RUNBOOK.md` | **Full reference** — read this before running anything in production |

### Jaspersoft editions covered

All automation and wizard tooling targets **JasperReports Server 10 Pro** (commercial edition). The open-source community edition is architecturally similar but lacks multi-tenancy, advanced scheduling, and some API surface used by the scripts. The report `.jrxml` files work with both editions.

---

## Prerequisites

Before you can run anything, confirm these are installed and configured:

| Tool | Required version | Check |
|---|---|---|
| PostgreSQL + PostGIS | 14 + 3.4 | `psql --version` |
| JDK | 11 | `java -version` |
| Maven | 3.9 | `mvn --version` |
| 7-Zip | Any | `7z i` |
| curl | Built-in (Windows) | `curl --version` |
| JasperReports Server | 10 Pro | `http://localhost:8081/jasperserver-pro` |
| JR 7.0.6 runtime jars | Pre-built | See RUNBOOK §5 |
| Python | 3.8+ (optional) | Required for `scaffold_jrxml.py`, `extract_lineage.py` |
| sqlglot | Latest (optional) | `pip install sqlglot` — used by lineage extractor |

Run the environment preflight before your first deploy:

```powershell
.\plugins\jasper-deploy\skills\jasper-deploy\scripts\doctor.ps1
```

This 10-point preflight checks server reachability, both databases (reporting + repo metadata on :5433), JRS→DB connectivity via the `/contexts` service, server settings (including the Visualize.js `domainWhitelist`), jar availability, config validity, and Python deps, and prints a PASS/WARN/FAIL checklist.

---

## Common tasks

### Geocode an address

```sql
SELECT g.rating, ST_X(g.geomout) lon, ST_Y(g.geomout) lat, pprint_addy(g.addy)
FROM geocode('901 Bagby St, Houston, TX 77002', 1) AS g;
```

### Rebuild the geocoder (from scratch)

```powershell
# Step 1: national lookups (run once, run first)
scripts\load_tiger_nation.bat

# Step 2: all 254 Texas counties (idempotent, verified)
powershell -File scripts\load_remaining.ps1
```

Sweep the log for `DOWNLOAD FAILED (skipped)`. Fix those files using the cache-buster trick (see RUNBOOK §3, G3).

### Render the report PDF

See RUNBOOK §5 for the full build sequence. High-level:

1. Build the JR 7.0.6 library (Maven, one-time).
2. Compile `report\tx_density_blockgroup_report_jr7.jrxml` → `.jasper`.
3. Fill and export → `output\tx_density_blockgroup_report.pdf` (317 pages).

### Deploy reports and build a dashboard

```powershell
$skill = ".\plugins\jasper-deploy\skills\jasper-deploy\scripts"
$env:PGPASSWORD = "postgres"

# Run environment preflight
& $skill\doctor.ps1

# Build all Foodmart KPI dashlets and compose the dashboard
& $skill\build_dashlets.ps1 -Manifest report\foodmart\dashboard.json -Compose
```

After editing any skill script, run the regression gate:

```powershell
& $skill\smoke_test.ps1   # 24-step end-to-end check (+ wizard-api when the wizard is deployed)
```

### Use the self-service web wizard

```powershell
cd webapp\jasper-wizard
.\build.ps1   # compile + bundle + hot-deploy to JRS Tomcat
```

Then open `http://localhost:8081/jasper-wizard/`. Business users can create reports from SQL, build dashboards, manage data sources, run and export artifacts — all without touching JRXML or REST directly.

### Lint a JRXML before deploying

```powershell
.\plugins\jasper-deploy\skills\jasper-deploy\scripts\lint_jrxml.ps1 -Path report\my_report.jrxml
```

Catches strict-Jackson violations that a clean local compile misses. This runs automatically inside `deploy_report.ps1` — skip it only if you know what you're doing (`-SkipLint`).

### Extract lineage from deployed reports

```powershell
python .\plugins\jasper-deploy\skills\jasper-deploy\scripts\extract_lineage.py --folder /public/Samples
```

Emits a metadata + column-level lineage graph (reports → datasources → tables → columns). Add `--format openlineage` for OpenLineage-compatible output.

### Detect drift between local source and live JRS

```powershell
.\plugins\jasper-deploy\skills\jasper-deploy\scripts\diff_resource.ps1 -Uri /public/Reports/MyReport -Against report\MyReport.json
```

Exits nonzero if the live resource differs from the committed local descriptor.

### Apply a desired-state environment manifest

```powershell
# Preview what would change (plan-only, default)
.\plugins\jasper-deploy\skills\jasper-deploy\scripts\reconcile.ps1 -Manifest env.json

# Apply the changes
.\plugins\jasper-deploy\skills\jasper-deploy\scripts\reconcile.ps1 -Manifest env.json -Apply
```

### See who's actually using what

```powershell
$env:PGPASSWORD = "postgres"
.\plugins\jasper-deploy\skills\jasper-deploy\scripts\report_usage.ps1                       # top resources, 30 days
.\plugins\jasper-deploy\skills\jasper-deploy\scripts\report_usage.ps1 -Action users -Days 7
```

Reads the repository metadata DB's access events (live DB is on **:5433**).

### Promote a resource from STAGE to PROD

```powershell
# Profiles are defined once under "environments" in jrs.config.json
.\plugins\jasper-deploy\skills\jasper-deploy\scripts\promote.ps1 -Uri /reports/geocoder/sales_dashboard -FromEnv stage -ToEnv prod
```

---

## Things that will bite you

Read RUNBOOK §3 before running anything significant. The short list:

1. **Use `curl.exe`, not `wget`** — wget's installer source is unreachable here.
2. **Always verify downloads with `7z t` + retry** — the Census CDN silently returns corrupt ZIPs.
3. **JasperReports 7 `.jrxml` format is not backward-compatible with 6.x.** Use the `_jr7` file or let Jaspersoft Studio auto-upgrade. PDF export requires the separate `jasperreports-pdf` module.
4. **JRS report queries must start with `SELECT`** — a leading `WITH` (CTE) compiles locally but is rejected at fill time. Push CTEs into a `FROM` subquery.
5. **Dashboards and ad hoc views: import, don't PUT** — a direct PUT renders blank (dashboards) or fails with `500 "bytes is null"` (ad hoc views). Use the skill scripts.
6. **Reports that are dashlets are modification-locked (403)** until the owning dashboard is deleted. Use `teardown_dashboard.ps1`.
7. **Lint before you deploy** — `lint_jrxml.ps1` catches strict-Jackson traps that a clean local compile misses.
8. **PowerShell `-D` args after `--%`** — Maven flags must follow the stop-parsing token.

When a deploy `400`s with an opaque error, check `references/gotchas.md` (indexed by symptom) and `references/jr7-valid-elements.md` (valid/rejected element names per construct).

---

## Where to go for help

| Resource | Location |
|---|---|
| Full operational reference | `RUNBOOK.md` |
| Skill index and happy path | `plugins/jasper-deploy/skills/jasper-deploy/SKILL.md` |
| Contribution guidelines (conventions, definition-of-done) | `plugins/jasper-deploy/skills/jasper-deploy/CONTRIBUTING.md` |
| Symptom → fix index (50+ issues) | `plugins/jasper-deploy/skills/jasper-deploy/references/gotchas.md` |
| Valid JR7 element names | `plugins/jasper-deploy/skills/jasper-deploy/references/jr7-valid-elements.md` |
| Upgrade/migration planning (any version → 10.1) | `plugins/jasper-deploy/skills/jasper-deploy/references/upgrade-migration-playbook.md` |
| Version deltas 9.0 → 10.1 in depth | `plugins/jasper-deploy/skills/jasper-deploy/references/version-matrix.md` |
| Web wizard reference | `webapp/jasper-wizard/README.md` |
| Official Jaspersoft docs | https://community.jaspersoft.com/documentation |
| Jaspersoft community forum | https://community.jaspersoft.com |
| JasperReports Library (open source) | https://github.com/Jaspersoft/jasperreports |
| Actian Jaspersoft product page | https://www.actian.com/analytic-database/jaspersoft-reporting-analytics/ |

---

## Security reminders

- **Never commit credentials.** Set `PGPASSWORD`, `JRS_PASS`, and any API keys as environment variables or in `jrs.config.json` (which is gitignored).
- **The web wizard is an internal tool.** It runs user-supplied SQL with the configured data source's privileges and publishes using stored admin credentials. Keep it behind the JRS login and a network boundary.
- The `jasper-deploy` skill defaults to `superuser`/`superuser` for local development. Use proper credentials in any shared or production-facing environment.
