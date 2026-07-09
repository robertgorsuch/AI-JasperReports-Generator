---
name: jasper-deploy
description: >-
  Design, compile, and deploy JasperReports artifacts to JasperReports Server.
  Use when the user wants to scaffold a JasperReports report from a SQL query,
  generate or hand-edit a JR7 (JasperReports 7) .jrxml, compile a .jrxml to
  .jasper, publish/deploy a report to the Jasper(Reports) Server, or export/import
  (promote, back up, version-control) a dashboard or other repository resource.
  Also covers data sources (JDBC and non-JDBC: JNDI/bean/custom/virtual/AWS),
  shared JR style templates (.jrtx), single-table Domains (semantic layer),
  ad hoc views (list/inspect/export/import), JRS UI themes (CSS), query-based
  and cascading input controls, repository permissions and attributes, and
  OLAP/Mondrian (schema + secure connection).
  Covers the full design-compile-deploy pipeline against a local PostgreSQL
  database and a JasperReports Server REST v2 endpoint.
---

# JasperReports design / compile / deploy

Automates the pipeline for tabular JasperReports against PostgreSQL on this
machine, targeting JasperReports Server 10.0.0 over REST v2. Everything is
**JasperReports 7.0.6 native** — the jrxml schema is NOT 6.x compatible (see
`references/jr7-schema.md`).

This file is a lean index: each capability lists its script, the minimal
invocation, and a pointer to the reference file holding the full flags, verified
notes, and gotchas. **Read the linked reference before doing non-trivial work in
that area** — the deep detail lives there, not here.

## Conventions (apply everywhere)
- **`$skill`** = the `scripts/` subdirectory of this skill. Set it from the base
  directory given at the top of this skill's context:
  `$skill = "<skill-base-dir>\scripts"` (or, from the tx-geocoder repo,
  `.\.claude\skills\jasper-deploy\scripts`).
- **Server:** `http://localhost:8081/jasperserver-pro`, REST v2, HTTP Basic,
  `superuser`/`superuser`. NOTE: a *different* Bearer-token-gated Java service runs
  on **:8080** and 401s every path — do not target it. Real install: `C:\Jaspersoft`.
- **Credentials** resolve in order: script params → env vars
  `JRS_URL`/`JRS_USER`/`JRS_PASS` → `jrs.config.json` in the skill root (copy
  `jrs.config.example.json`, fill in, gitignored).
- **DB:** PostgreSQL `localhost:5432`, defaults `postgis_34_sample` / `postgres`;
  `$env:PGPASSWORD = "postgres"` before any `scaffold_*.py` (they introspect via
  psql).

## Toolchain (prerequisites)
- JR7 runtime jars: a local directory of JasperReports 7.0.6 jars (incl. the
  PostgreSQL JDBC driver and the `jasperreports-pdf` export module). Resolves via
  `-LibDir` → `$env:JR_LIB_DIR` → `jrs.config.json` `jrLibDir` (required — scripts
  error with guidance if unset).
- JDK 11+ on PATH — single-file source launch, no `javac` step.
- `psql` 14 and `curl` 8.x on PATH.

## Capability map (script → reference)
| Want to… | Script(s) | Reference |
|---|---|---|
| Scaffold a report from SQL (themes, charts, params, groups, drill, crosstab) | `scaffold_jrxml.py` | `references/reports.md` |
| Shared style template (.jrtx) | `scaffold_style_template.py` | `references/reports.md` |
| Compile / locally preview a jrxml | `compile_jrxml.ps1`, `RenderPng` | `references/reports.md` |
| Deploy a report (+ input controls) | `deploy_report.ps1` | `references/admin-and-scheduling.md` |
| Run / export / verify a deployed report | `verify_report.ps1`, `run_report_async.ps1`, curl | `references/reports.md`, `references/admin-and-scheduling.md` |
| CSV-backed report / upload a file resource | `upload_file.ps1` | `references/reports.md` |
| Bulk-deploy a folder of samples | `deploy_jr_samples.ps1` | `references/reports.md` |
| Charts / spider / barcodes / HTML5 / FusionMaps | (jrxml + jars) | `references/reports.md` |
| Create a datasource (JDBC or jndi/bean/custom/virtual/aws) | `create_datasource.ps1` | `references/data-and-semantic-layer.md` |
| Compose a dashboard from a manifest | `build_dashlets.ps1 -Compose` | `references/dashboards.md` |
| Export/import/promote/teardown a dashboard or resource | `export_resource.ps1`, `import_resource.ps1`, `promote.ps1`, `teardown_dashboard.ps1` | `references/dashboards.md` |
| Single-table Domain (semantic layer) | `scaffold_domain_schema.py` + `create_domain.ps1` | `references/data-and-semantic-layer.md` |
| Ad hoc view list/inspect/export/import | `manage_adhoc.ps1` | `references/data-and-semantic-layer.md` |
| OLAP / Mondrian schema + connection | `create_mondrian.ps1` | `references/data-and-semantic-layer.md` |
| UI theme (CSS) | `scaffold_theme.py` + `deploy_theme.ps1` | `references/data-and-semantic-layer.md` |
| Schedule a job / set a data alert | `schedule_job.ps1`, `manage_alert.ps1` | `references/admin-and-scheduling.md` |
| Saved report options / clear a cache | `manage_options.ps1`, `manage_cache.ps1` | `references/admin-and-scheduling.md` |
| Permissions / attributes / users / roles / orgs | `manage_permissions.ps1`, `manage_attributes.ps1`, `manage_users.ps1`, `manage_roles.ps1`, `manage_organizations.ps1` | `references/admin-and-scheduling.md` |
| jrxml schema (JR7 vs 6.x) | — | `references/jr7-schema.md` |
| REST v2 endpoint map (verified vs doc-only) | — | `references/jrs-rest-api.md` |
| Dashboard model shapes (descriptor + companions) | — | `references/dashboard-model.md` |
| Lint a jrxml/.jrtx/.jrdax before deploy | `lint_jrxml.ps1` | `references/jr7-valid-elements.md` |
| Extract metadata + column-level lineage (read-only; OpenLineage out) | `extract_lineage.py` | `references/catalog-connector-pdd.md` |
| Detect live-vs-committed resource drift | `diff_resource.ps1` | `references/admin-and-scheduling.md` |
| Apply a whole environment from one manifest (plan by default, `-Apply`) | `reconcile.ps1` | `references/environment.schema.json` |
| Preflight: is this environment ready to deploy? | `doctor.ps1` | `references/security-and-config.md` |
| Doc/link consistency check (CI guard) | `check_docs.ps1` | — |
| Troubleshoot a deploy/fill error by symptom | — | `references/gotchas.md` |
| Valid JR7 elements per construct (strict-Jackson) | — | `references/jr7-valid-elements.md` |
| Secrets / config / portability (env, passwordCommand, no plaintext) | — | `references/security-and-config.md` |
| Sample DBs / email test / CI / Visualize.js embed | — | `references/{seed-data,smtp-testing,ci-smoke,visualize-embedding}.md` |
| REST surface snapshot + manifest/config JSON schemas | — | `references/application.wadl`, `manifest.schema.json`, `jrs.config.schema.json` |

## The core happy path (report → deploy → run)
```powershell
$env:PGPASSWORD = "postgres"
# 1. Scaffold a JR7 jrxml from a query (see references/reports.md for every flag)
python $skill\scaffold_jrxml.py --name county_summary --title "County Edge Summary" `
    --query "SELECT c.name AS county, count(*)::int AS edge_count FROM ... GROUP BY 1 ORDER BY 2 DESC" `
    --out report\county_summary.jrxml
# 2. (optional) Compile to validate JR7-clean before deploying
& $skill\compile_jrxml.ps1 -Jrxml report\county_summary.jrxml
# 3. (one-time) Create the datasource the report will use
& $skill\create_datasource.ps1 -Uri /datasources/postgis_34_sample -Label "PostGIS" `
    -Database postgis_34_sample -DbUser postgres -DbPassword postgres
# 4. Deploy (JRS compiles server-side; 201 Created)
& $skill\deploy_report.ps1 -Jrxml report\county_summary.jrxml `
    -TargetUri /reports/geocoder/county_summary -Label "County Edge Summary" `
    -DataSourceUri /datasources/postgis_34_sample
# 5. Run to PDF to verify (200 + %PDF-)
curl.exe -s -u "superuser:superuser" -o out.pdf `
    "http://localhost:8081/jasperserver-pro/rest_v2/reports/reports/geocoder/county_summary.pdf"
```
Re-deploy with **`-Overwrite`** (updates in place via `?overwrite=true`, no
delete). Full scaffold flags (templates, charts, `--param/--group-by/--highlight/
--drill/--crosstab/--subreport`, style templates, CSV adapters, visualization
components) are in `references/reports.md`; deploy input-control options
(`-Control`, `-QueryControl`, cascading) are in `references/admin-and-scheduling.md`.

## Compose a dashboard (one command)
```powershell
$env:PGPASSWORD = "postgres"
& $skill\build_dashlets.ps1 -Manifest report\foodmart\dashboard.json -Compose
```
Scaffolds → compiles → deploys → verifies each report tile, then composes them
into a rendering dashboard via export-inject-import (NOT a raw PUT). Manifest
schema, mixed text/image tiles, the why-import-not-PUT rule, `resource.in.use`
handling, and designer-authored dashboards are in `references/dashboards.md`.

## Critical cross-cutting gotchas (do not relearn these)
- **JR7, not 6.x.** A 6.x jrxml fails the JR7 loader; the strict Jackson parser
  rejects unknown elements at *fill time* as a generic `400`, not a clean compile
  error. This bites `.jrtx` (`default="true"`, not `isDefault`) and `.jrdax`
  adapters (limited element set). See `references/jr7-schema.md` + `reports.md`.
- **Lint before deploy (now automatic).** `deploy_report.ps1` runs `lint_jrxml.ps1`
  as a pre-deploy gate (`-SkipLint` to bypass); it catches the strict-Jackson 400s a
  clean compile misses (isDefault, `.jrdax` JR6 elements, pie `seriesColors`/`seriesOrder`,
  leading-`WITH` SQL, line/area plot props, title-band `evaluationTime`). Chart plot
  props are per-class: `line` = showLines/showShapes; `bar`/`bar3d`/`stackedbar` =
  showTickMarks/showTickLabels; **`area` (`JRDesignAreaPlot`) accepts NEITHER** —
  bare `<plot/>` only. Valid names per construct: `references/jr7-valid-elements.md`;
  symptom→fix index: `references/gotchas.md`. When a JRS call still fails, `Assert-JrsOk`
  appends a `gotchas.md` pointer (via `Get-GotchaHint`). Pass `-Backup` to
  `deploy_report.ps1`/`compose_dashboard.ps1` to export the current version first.
- **Report queries must begin with `SELECT`.** A leading `WITH` (CTE) is rejected
  by the JRS SQL security validator at fill time (`JSSecurityException`) — a
  generic `400` that a clean local compile does NOT catch. `deploy_report.ps1`
  lints and blocks it (`-SkipSqlLint` overrides); `scaffold_jrxml.py` warns.
  **Fix:** push each CTE into a nested `FROM` subquery so the statement starts with
  `SELECT` (`WITH a AS (...) SELECT ... FROM a` → `SELECT ... FROM (...) a`); verify
  the rewrite in psql first — output must be identical. Window functions are fine.
- **Don't PUT dashboards or ad hoc views.** A hand-built model PUT to
  `/rest_v2/resources` stores (201) but renders **blank** (dashboard) or `500`s
  (`"bytes is null"`, ad hoc). Always go through the export-inject-**import** path
  (`compose_dashboard.ps1` / `manage_adhoc.ps1`). See `references/dashboards.md`.
- **Field `class` must match the JDBC column type** or fill fails — the scaffolder
  handles this; keep `<field class>` in sync if you hand-edit the SQL.
- **PowerShell 5.1:** `?` is a variable-name char (build URLs with `${base}`
  braces); pass JSON bodies to curl from a **file** (`--data "@req.json"`), not
  inline (`-d`), which gets quotes mangled → `400 serialization.error`.

## After editing any script: smoke test
```powershell
$env:PGPASSWORD = "postgres"
& $skill\smoke_test.ps1
```
First runs **offline prechecks** (`check_docs.ps1` doc-consistency + the `tests/`
Pester unit suite), then the full 19-step server lifecycle under a throwaway
`/reports/_smoke` (+ `/themes`):
scaffold → **lint** → compile → deploy (+input control) → verify → run-to-PDF → schedule job
(CRUD) → alert (CRUD) → compose dashboard (report + text tile) → style template →
single-table Domain → jndi datasource → UI theme → AWS datasource → cascading query
input controls → permissions set/clear → server attribute CRUD → Mondrian schema +
connection → teardown, asserting each step. **If you change a script's params or
stdout shape, also check the web wizard handler** that calls it
(`references/admin-and-scheduling.md` → Web wizard).

## Docs source of truth for THIS install
- Live WADL (never version-drifts): `…/rest_v2/application.wadl?detail=true`.
- `references/jrs-rest-api.md` — distilled, verified-vs-doc-only endpoint map with
  `docs/` page cites (covers `reports`, `reportExecutions`, `inputControls`,
  `options`, `jobs`, `alerts`, `queryExecutor`, `caches`, non-JDBC datasources, and
  a verified Visualize.js cross-origin embedding recipe).
- Full JRS 10.0.0 PDF docs live in `docs/` (machine-local, **gitignored**, ~62 MB,
  re-downloadable). Read them with `pypdfium2` — `pdftoppm` is unavailable, so the
  Read tool can't rasterize them; the community site 403s scripted fetches.
