# Runbook — Texas PostGIS Geocoder + Population Maps + JasperReports

Cumulative operational knowledge from building a statewide Texas address geocoder on PostGIS, population-density visualizations, and a JasperReports 7 report — plus the `jasper-deploy` skill and web wizard that automate the full JasperReports Server lifecycle.

> **Path conventions:** This runbook was written against a specific Windows development machine. Wherever you see `C:\Users\rgorsuch\...` or `C:\Program Files\...`, substitute your own paths. Environment variables (`JAVA_HOME`, `PGPASSWORD`, `JR_LIB_DIR`) are the recommended way to avoid hard-coded paths in scripts.

---

## Contents

1. [What exists](#1-what-exists)
2. [Prerequisites and environment](#2-prerequisites-and-environment)
3. [Gotchas](#3-gotchas)
4. [Scripts (`scripts\`)](#4-scripts-scripts)
5. [Reports (`report\`)](#5-reports-report)
6. [Maps (`maps\`)](#6-maps-maps)
7. [Rebuild order from scratch](#7-rebuild-order-from-scratch)
8. [Useful geocode tests](#8-useful-geocode-tests)
9. [jasper-deploy skill](#9-jasper-deploy-skill)
10. [Self-service web wizard](#10-self-service-web-wizard)
11. [Troubleshooting quick reference](#11-troubleshooting-quick-reference)

---

## 1. What exists

**Geocoder** — Statewide TIGER geocoder in `postgis_34_sample`, all 254 Texas counties loaded:

| Table | Rows |
|---|---|
| `tiger_data.tx_edges` | 5,692,076 |
| `tiger_data.tx_featnames` | 5,060,971 |
| `tiger_data.tx_addr` | 2,664,841 |
| `tiger_data.tx_faces` | 1,924,566 |
| `tiger_data.tx_place` | 1,860 |

`geocode('1100 Congress Ave, Austin, TX 78701')` → rating 0 (exact match).

**Population data:**
- `tiger_data.tx_tabblock20` — 668,757 2020 census blocks (statewide, with `pop`). TX total: 29,145,505.
- `tiger_data.tx_bg` — 18,638 block groups
- `tiger_data.tx_tract` — 6,896 tracts

**Maps** (in `maps\`, open in a browser): statewide heatmap (2 km grid), Houston heatmap (500 m), full block-detail heatmap (449k blocks), tract choropleth, block-group choropleth, and two geocode-pin maps.

**JasperReports** (in `report\`): a block-group density report in both 6.x and native JR 7 format, compiled (`.jasper`) and rendered (`output\tx_density_blockgroup_report.pdf`, 317 pages).

**jasper-deploy skill** (`.claude\skills\jasper-deploy\`): 30+ scripts automating the full JRS 10 lifecycle (reports, dashboards, data sources, domains, themes, admin, lineage, smoke testing).

**Web wizard** (`webapp\jasper-wizard\`): Jakarta servlet WAR — a browser UI over the skill for business users.

---

## 2. Prerequisites and environment

### Software versions

| Tool | Version | Default location | Notes |
|---|---|---|---|
| PostgreSQL + PostGIS | 14 + 3.4 | `C:\Program Files\PostgreSQL\14\bin` | DB `postgis_34_sample`, user `postgres` |
| curl | Built-in | `C:\WINDOWS\system32\curl.exe` | **Use instead of wget** (see §3) |
| 7-Zip | Any | `C:\Program Files\7-Zip\7z.exe` | Unzip + `7z t` integrity checks |
| JDK | 11 | Set via `JAVA_HOME` | Runs JasperReports + javac |
| Maven | 3.9 | Set via `PATH` | Builds JasperReports from source |
| JasperReports 7.0.6 runtime | 7.0.6 | Set via `JR_LIB_DIR` (or `C:\Users\<you>\jasperreports-lib\`) | 37 jars (core, pdf, openpdf, PG JDBC driver, deps) |
| JasperReports 7.0.6 source | 7.0.6 | `C:\Users\<you>\jasperreports-7.0.6\` | Maven project extracted from `-project.zip` |
| JasperReports Server | 10 Pro | `http://localhost:8081/jasperserver-pro` | HTTP Basic — `superuser`/`superuser` |

### Environment variables

```bat
set JAVA_HOME=C:\path\to\jdk-11
set PGPASSWORD=<your postgres password>
set JR_LIB_DIR=C:\path\to\jasperreports-lib   :: used by jasper-deploy scripts; optional
```

### Data staging

Census TIGER data downloads stage to `C:\gisdata` by default (configurable in the loader scripts).

---

## 3. Gotchas

These are the expensive-to-rediscover lessons. Read this section before you start.

**G1 — Use `curl.exe`, not `wget`.**
`winget install wget` fails — its source (`eternallybored.org`) is unreachable in this environment. Use the built-in `curl.exe` with:
```
curl --location --fail --retry 3 --create-dirs -o "<host\path>" "<url>"
```
All loader scripts have been rewritten to use this pattern.

**G2 — Census downloads silently corrupt.**
`curl` exits 0 (HTTP 200) but bytes can be truncated or bad (killed PLACE + TRACT on first run). Always validate every download with `7z t` and retry. `load_tiger_TX.bat` has a `:getverified` subroutine; the PS1 loaders use a `Get-Verified` function.

**G3 — Cloudflare WAF cache.**
Cloudflare can cache a "Request Rejected" page (247-byte HTML, HTTP 200, `cf-cache-status: HIT`) for a specific Census URL. `--fail` won't catch it. Fix: re-request with a cache-buster (`?cb=<timestamp>`) and a browser User-Agent (`-A`).

**G4 — PowerShell mangles Maven `-D` args.**
`-Dmaven.test.skip=true` gets split into a bogus lifecycle phase. Pass Maven args after the `--%` stop-parsing token:
```powershell
mvn --% -f pom.xml -pl core,ext/pdf -am -Dmaven.test.skip=true -B install
```

**G5 — JasperReports 7 has a new `.jrxml` format** (Jackson-based, not backward-compatible with 6.x):
- No XML namespace
- Root element: `<jasperReport name=".." language="java" ..>`
- `<queryString>` → `<query>`
- `<reportElement>` removed — x/y/width/height are flattened onto `<element kind="..">`
- `textAlignment` → `hTextAlign` / `vTextAlign`
- `<variableExpression>` / `<groupExpression>` → `<expression>`

A 6.x `.jrxml` fails JR7's CLI loader. Open it in Jaspersoft Studio to auto-upgrade, or use the `_jr7` file in this repo.

**G6 — JR 7 PDF export is a separate module.**
The `jasperreports-pdf` module (OpenPDF) must be built and included. Core alone throws "Missing JasperReports PDF Extension". Build `ext/pdf` too (see §5).

**G7 — `usa_states` SRID.**
`tiger.usa_states` was SRID 0 (undefined), fixed to 4269 (NAD83, matching TIGER). It and two other former-`public` tables now live in schema `tiger`. The `public` schema holds only PostGIS/extension objects — do not move those.

**G8 — JRS SQL security validator.**
Report queries must begin with `SELECT`. A leading `WITH` (CTE) compiles locally but is rejected at fill time (`JSSecurityException` → generic 400). `deploy_report.ps1` lints and blocks this before deploy (`-SkipSqlLint` to bypass). Fix by pushing each CTE into a `FROM` subquery.

**G9 — Dashboards: import, don't PUT.**
A hand-built dashboard PUT to `/rest_v2/resources` stores (201) but renders blank. `compose_dashboard.ps1` exports real dashlets, injects the synthesized model, and imports a re-zipped archive (forward-slash entries required — the Java importer ignores back-slash paths).

**G10 — `resource.in.use` (403) on dashlet reports.**
A report that is a dashlet is modification/delete-locked. `deploy_report.ps1` updates in place to avoid this; `teardown_dashboard.ps1` deletes the dashboard first to release the lock.

**G11 — Input controls must be standalone repository resources.**
Embedded input controls are rejected. The control's name must equal the `$P{param}` it drives.

**G12 — PowerShell 5.1 URL and array quirks.**
- `?` is a legal variable-name char: build URLs as `"${base}?name="` not `"$base?name="` (the latter produces a 405).
- `ConvertTo-Json` unwraps single-element arrays to scalars (server 400s). Emit such arrays as hand-built JSON.

**G13 — JR7 chart plot properties are per-class.**
`line` uses `showLines`/`showShapes`; `bar`/`bar3d`/`stackedbar` use `showTickMarks`/`showTickLabels`; `area` (`JRDesignAreaPlot`) accepts neither pair (bare `<plot/>` only). The wrong pair throws `UnrecognizedPropertyException` at compile/fill. `scaffold_jrxml.py` emits the correct form; `lint_jrxml.ps1` catches the wrong form; `references/jr7-valid-elements.md` lists valid/rejected elements per construct.

---

## 4. Scripts (`scripts\`)

All scripts use absolute paths internally and are safe to run from any working directory. Run `.bat` files from `cmd.exe`; run `.ps1` files via `powershell -File`.

| Script | Purpose |
|---|---|
| `load_tiger_nation.bat` | One-time: load national STATE + COUNTY lookup tables. **Run this first.** |
| `load_tiger_TX.bat` | Full statewide TX loader (all layers, all 254 counties). Has the `:getverified` CRC-verify+retry fix. Long run. |
| `load_geocode_travis.bat` | Loads PLACE (statewide) + EDGES/FEATNAMES/ADDR for Travis County only. Fast demo. |
| `load_geocode_faces_zip.bat` | Loads Travis FACES + builds zip lookup tables (required for geocoding). |
| `load_metros.ps1` | Verified loader for 16 metro counties (faces/featnames/edges/addr). Idempotent. |
| `load_remaining.ps1` | Verified loader for all remaining counties. **Idempotent** — skips counties already in `tx_edges`. Recommended for a full statewide load. |
| `test_verify.bat` | Standalone test of the download-verify-retry subroutine. |

---

## 5. Reports (`report\`)

### Files

| File | Description |
|---|---|
| `tx_density_blockgroup_report.jrxml` | JasperReports 6.x format. Open in Jaspersoft Studio to auto-upgrade. |
| `tx_density_blockgroup_report_jr7.jrxml` | Native JR 7 format. Use this one. |
| `tx_density_blockgroup_report_jr7.jasper` | Pre-compiled report binary. |
| `postgis_34_sample.xml` | Jaspersoft Studio JDBC data adapter (requires the PostgreSQL driver on its classpath). |
| `CompileReport.java` | CLI compile harness. |
| `FillReport.java` | CLI fill/export harness. Reads `PGPASSWORD` from the environment. |
| `foodmart/` | Deployable KPI reports + `dashboard.json` manifest for the jasper-deploy skill. |

### Build the JasperReports 7.0.6 library (once)

```bat
set JAVA_HOME=C:\path\to\jdk-11

:: Build core + PDF extension
mvn --% -f C:\path\to\jasperreports-7.0.6\pom.xml -pl core,ext/pdf -am -Dmaven.test.skip=true -Dmaven.javadoc.skip=true -B install

:: Copy runtime jars to your lib directory
mvn --% -f C:\path\to\jasperreports-7.0.6\core\pom.xml dependency:copy-dependencies -DoutputDirectory=C:\path\to\jasperreports-lib -DincludeScope=runtime
mvn --% -f C:\path\to\jasperreports-7.0.6\ext\pdf\pom.xml dependency:copy-dependencies -DoutputDirectory=C:\path\to\jasperreports-lib -DincludeScope=runtime

:: Copy the built JARs into the lib directory
copy C:\path\to\jasperreports-7.0.6\core\target\jasperreports-7.0.6.jar C:\path\to\jasperreports-lib\
copy C:\path\to\jasperreports-7.0.6\ext\pdf\target\jasperreports-pdf-7.0.6.jar C:\path\to\jasperreports-lib\

:: Add the PostgreSQL JDBC driver
curl https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.4/postgresql-42.7.4.jar -o C:\path\to\jasperreports-lib\postgresql-42.7.4.jar
```

### Compile and render to PDF

Run from the `report\` directory:

```bat
set CP=C:\path\to\jasperreports-lib\*
set PGPASSWORD=<your postgres password>

:: Compile the Java harnesses
"C:\path\to\jdk-11\bin\javac.exe" -cp "%CP%" CompileReport.java FillReport.java

:: Compile the JRXML
"C:\path\to\jdk-11\bin\java.exe" ^
  -Dnet.sf.jasperreports.compiler.class=net.sf.jasperreports.engine.design.JRJavacCompiler ^
  -cp "%CP%;." CompileReport tx_density_blockgroup_report_jr7.jrxml

:: Fill and export to PDF
"C:\path\to\jdk-11\bin\java.exe" -cp "%CP%;." FillReport ^
  tx_density_blockgroup_report_jr7.jasper ^
  ..\output\tx_density_blockgroup_report.pdf
```

---

## 6. Maps (`maps\`)

Self-contained HTML files using Leaflet + CDN resources. Open directly in any browser — no web server required.

| File | Shows |
|---|---|
| `tx_population_heatmap.html` | Statewide population heatmap, 2 km grid (64,722 cells) |
| `tx_population_heatmap_blocks.html` | Full block-detail heatmap (449k blocks; loads slowly) |
| `houston_population_heatmap.html` | Houston metro, 500 m grid |
| `tx_density_choropleth.html` | Density choropleth by census tract (6,896) |
| `tx_density_choropleth_blockgroup.html` | Density choropleth by block group (18,638) |
| `geocode_result.html` | Single geocoded address pin (Austin example) |
| `geocode_houston.html` | Single geocoded address pin (Houston example) |

---

## 7. Rebuild order from scratch

1. Run `scripts\load_tiger_nation.bat` (national STATE + COUNTY lookups — required first).
2. Run `scripts\load_remaining.ps1` (verified statewide county load; or `load_tiger_TX.bat` for the original loader). Sweep the log for `DOWNLOAD FAILED (skipped)` and repair those files with the cache-buster + User-Agent trick (see G3).
3. Build the JasperReports 7.0.6 library (§5), compile the report, and fill it to PDF.
4. Regenerate maps as needed — queries are embedded in `report\` and data lives in `tiger_data.tx_*`.
5. To stand up the jasper-deploy skill: see §9. To deploy the web wizard: see §10.

---

## 8. Useful geocode tests

```sql
-- Exact match (rating 0)
SELECT g.rating, ST_X(g.geomout) lon, ST_Y(g.geomout) lat, pprint_addy(g.addy)
FROM geocode('1100 Congress Ave, Austin, TX 78701', 1) AS g;

-- Houston example
SELECT g.rating, ST_X(g.geomout) lon, ST_Y(g.geomout) lat, pprint_addy(g.addy)
FROM geocode('901 Bagby St, Houston, TX 77002', 1) AS g;

-- Check what's loaded
SELECT COUNT(*) FROM tiger_data.tx_edges;       -- ~5.7M
SELECT COUNT(*) FROM tiger_data.tx_tabblock20;  -- ~668K
SELECT SUM(pop) FROM tiger_data.tx_tabblock20;  -- 29,145,505
```

---

## 9. jasper-deploy skill

`.claude/skills/jasper-deploy/` scripts the full JasperReports lifecycle against JRS 10 Pro at `http://localhost:8081/jasperserver-pro` over REST v2. All scripts are JR 7.0.6-native and verified end-to-end.

### Configuration

Credentials and server URL resolve in this order:
1. Script parameters (`-Url`, `-User`, `-Pass`)
2. Environment variables (`JRS_URL`, `JRS_USER`, `JRS_PASS`)
3. `jrs.config.json` (gitignored; copy `jrs.config.example.json` to get started)

Default: `http://localhost:8081/jasperserver-pro`, `superuser` / `superuser`.

> ⚠️ Port 8080 is an unrelated Bearer-gated service — not JRS.

JR 7.0.6 runtime jars resolve via: `-LibDir` parameter → `$env:JR_LIB_DIR` → `jrs.config.json` `jrLibDir` → `C:\Users\<you>\jasperreports-lib\`.

### Script reference

| Script | Purpose |
|---|---|
| `scaffold_jrxml.py` | Introspect a SQL query → emit a JR7 tabular report. Flags: `--chart`, `--param`, `--group-by`, `--highlight`, `--drill`, `--crosstab`, `--subreport`, `--style-template`. |
| `compile_jrxml.ps1` | Compile `.jrxml` → `.jasper`. Fast JR7 validity check. |
| `lint_jrxml.ps1` | Static pre-deploy linter — catches strict-Jackson traps offline. **Run before every deploy.** Gate inside `deploy_report.ps1` (`-SkipLint` to bypass). |
| `create_datasource.ps1` | Create/update a JDBC datasource or non-JDBC type (`-Type jndi\|bean\|custom\|virtual\|aws`). |
| `deploy_report.ps1` | PUT a report unit. `-Overwrite` updates in place. SQL-lint guard. `-Control` / `-QueryControl` / `-QueryMultiControl` attach input controls. |
| `verify_report.ps1` | Run a deployed report and assert HTTP + CSV row-count/contains + visual baseline diff. |
| `scaffold_style_template.py` | Emit a shared JR7 `.jrtx` style template from a color palette. |
| `scaffold_domain_schema.py` + `create_domain.ps1` | Introspect a table → single-table Domain for Ad Hoc reporting. |
| `manage_adhoc.ps1` | Ad hoc views: list / get / export / import / delete. |
| `scaffold_theme.py` + `deploy_theme.ps1` | Emit `overrides_custom.css` from a palette; deploy + activate per organization. |
| `create_mondrian.ps1` | Upload a Mondrian schema + create a `secureMondrianConnection`. |
| `manage_permissions.ps1` + `manage_attributes.ps1` | Repository ACLs and server/org/user attributes. |
| `manage_users.ps1` + `manage_roles.ps1` + `manage_organizations.ps1` | Identity and tenant CRUD. |
| `run_report_async.ps1` | Large fills via the async `reportExecutions` API. |
| `manage_options.ps1` + `manage_cache.ps1` | Saved input-control value sets; clear server caches. |
| `build_dashlets.ps1` + `compose_dashboard.ps1` | Manifest-driven: scaffold → lint → compile → deploy → verify dashlets, then compose and import the dashboard. |
| `export_resource.ps1` + `import_resource.ps1` | Export/import any resource for backup or promotion. |
| `promote.ps1` | Dev→prod promotion (export from source, import to target). |
| `teardown_dashboard.ps1` | Delete a dashboard then its report tiles + `_controls`, in lock-safe order. |
| `extract_lineage.py` | Column-level lineage graph (reports → datasources → tables → columns via `sqlglot`). `--format openlineage` emits OpenLineage events. |
| `diff_resource.ps1` | Drift detection — diffs a live resource descriptor vs. committed local `.json`. |
| `reconcile.ps1` | Declarative desired-state applier. Plan-only by default; `-Apply` to execute. Schema: `references/environment.schema.json`. |
| `doctor.ps1` | Environment preflight — server/DB reachable, jars present, config valid, Python deps available. |
| `check_docs.ps1` | Doc-consistency guard — every `references/` link and capability-map script resolves. |
| `smoke_test.ps1` | **19-step end-to-end regression gate.** Run after any script change. |

### Quick start

```powershell
$skill = ".\.claude\skills\jasper-deploy\scripts"
$env:PGPASSWORD = "postgres"

# Preflight check
& $skill\doctor.ps1

# Build and deploy all Foodmart dashlets + compose the dashboard
& $skill\build_dashlets.ps1 -Manifest report\foodmart\dashboard.json -Compose

# Regression gate (run after any script change)
& $skill\smoke_test.ps1
```

### Skill-specific gotchas

These are in addition to the general gotchas in §3 and are also indexed by symptom in `references/gotchas.md`.

| # | Issue | Fix |
|---|---|---|
| S1 | Leading `WITH` (CTE) rejected at fill time | Push CTEs into `FROM` subqueries |
| S2 | Dashboard PUT renders blank | Use `compose_dashboard.ps1` (export/import path) |
| S3 | `resource.in.use` (403) on dashlet report | Delete the dashboard first; use `teardown_dashboard.ps1` |
| S4 | Input controls rejected | Must be standalone repo resources; name must match `$P{param}` |
| S5 | Subreport must reference a file resource | Use `…/rpt_files/Label_main_jrxml`, not a report unit |
| S6 | Ad hoc view PUT fails (`500 "bytes is null"`) | Use `manage_adhoc.ps1` import (same export/import pattern as dashboards) |
| S7 | `.jrtx` default style uses wrong attribute | Use `default="true"`, not 6.x `isDefault="true"` |
| S8 | AWS datasource `-Region` | Use endpoint host (`us-east-1.amazonaws.com`), not the bare code |
| S9 | `compose_dashboard.ps1 -WorkDir` | Pass absolute path; relative paths fail when CWD differs |
| S10 | SLF4J "no providers" on stderr aborts PS | `Invoke-JrCompile` absorbs it; don't wrap in `$ErrorActionPreference=Stop` |

### Reference files

`references/` contains the authoritative detail behind `SKILL.md`:

| File | Contents |
|---|---|
| `reports.md` | Report scaffolding, compilation, deployment patterns |
| `dashboards.md` | Dashboard model, dashlet wiring, import/export |
| `data-and-semantic-layer.md` | Datasources, Domains, Ad Hoc views |
| `admin-and-scheduling.md` | Users, roles, orgs, scheduling, permissions |
| `jr7-schema.md` | JR7 `.jrxml` schema reference |
| `jr7-valid-elements.md` | Valid/rejected element names per construct (source-cited) |
| `gotchas.md` | 50+ issues indexed by symptom → fix; JRS errors auto-print a pointer here |
| `dashboard-model.md` | Dashboard JSON model internals |
| `security-and-config.md` | Secrets management, env-only creds, `passwordCommand` |
| `visualize-embedding.md` | Visualize.js embedding patterns |
| `ci-smoke.md` | CI integration for `smoke_test.ps1` |
| `manifest.schema.json` | Dashboard manifest JSON schema |
| `jrs.config.schema.json` | Server config JSON schema |
| `environment.schema.json` | Reconcile environment manifest schema |

---

## 10. Self-service web wizard (`webapp\jasper-wizard\`)

A Jakarta servlet WAR (Actian-branded) that puts the `jasper-deploy` skill behind a browser UI for business users. No JRXML or REST knowledge needed.

**URL:** `http://localhost:8081/jasper-wizard/`

**Capabilities:** reports (SQL → chart/table, live query preview, input controls), dashboards, data sources, domains, themes, run & export (PDF/XLSX/CSV/DOCX/PPTX + async), scheduling, repository browse, ad hoc list/export, permissions, and a **Server Summary** (repository inventory + runtime characteristics).

### Architecture

- Read/preview/run operations proxy directly to JRS REST via `JrsClient` (auth added server-side; no browser credentials, no CORS).
- Create/deploy operations shell out to the verified skill scripts via `ScriptRunner`. Scripts are **bundled inside the WAR** (`WEB-INF/scripts`) because the Tomcat service runs as `NT AUTHORITY\LocalService` and cannot read the user profile.
- Child processes run from the container temp directory (writable). This is why the wizard passes an absolute `-WorkDir` to `compose_dashboard.ps1`.

> If you change a skill script's parameters or stdout shape, update the matching wizard handler.

### Build and deploy

```powershell
cd webapp\jasper-wizard
.\build.ps1               # compile + bundle scripts + WAR + hot-deploy to JRS Tomcat
.\build.ps1 -NoDeploy     # build only — produces target\jasper-wizard.war
```

The build compiles against Tomcat's bundled `servlet-api.jar` with JDK 11 (Jakarta Servlet `jakarta.servlet.*`, not `javax.*`). No Maven required.

### Configuration

All configuration is in `WEB-INF/web.xml` context-params:
- JRS URL, username, password
- PostgreSQL host, port, user, password
- Python executable path
- Script execution timeout

Edit `web.xml` and rebuild, or edit the exploded webapp in Tomcat's `webapps/` directory and restart the app.

> ⚠️ Security note: the wizard runs user-supplied SQL against the configured DB and publishes using stored admin credentials. Keep it behind the JRS login and a network boundary. Command args are passed as an argv array (no shell-injection surface), but SQL runs with the data source's privileges.

---

## 11. Troubleshooting quick reference

| Symptom | Likely cause | Fix |
|---|---|---|
| `DOWNLOAD FAILED` in loader log | Corrupt ZIP from Census CDN | Re-run with cache-buster (`?cb=<timestamp>`) + browser User-Agent (`-A`) |
| `400` on report deploy | Strict-Jackson violation in `.jrxml` | Run `lint_jrxml.ps1`; check `references/jr7-valid-elements.md` |
| `400` with "leading WITH" message | CTE at top of report query | Rewrite as `FROM (SELECT ...)` subquery |
| `403 resource.in.use` | Report is a dashlet of a live dashboard | Delete the dashboard first; use `teardown_dashboard.ps1` |
| Dashboard renders blank after PUT | Hand-built dashboard model | Use `compose_dashboard.ps1` (export/import path) |
| `500 "bytes is null"` on ad hoc view PUT | Raw PUT not supported for adhocDataView | Use `manage_adhoc.ps1 import` |
| `JSSecurityException` at fill time | JRS SQL validator rejection | Ensure query starts with `SELECT`; no leading `WITH` |
| `Missing JasperReports PDF Extension` | Core jar without the `jasperreports-pdf` module | Build and include `ext/pdf` (see §5) |
| SLF4J "no providers" aborts PowerShell | `$ErrorActionPreference=Stop` + JR stderr | Use `Invoke-JrCompile` helper which absorbs stderr |
| `405` on JRS REST call | URL built with bare `$var?param=` | Use `${var}?param=` in PowerShell |
| `400` on array property | `ConvertTo-Json` unwraps single-element array | Emit as hand-built JSON string |

For deeper diagnosis, run `doctor.ps1` for environment preflight and check `references/gotchas.md` (indexed by symptom).
