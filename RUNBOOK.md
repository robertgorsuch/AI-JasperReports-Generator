# Texas PostGIS Geocoder + Population Maps + JasperReports — Runbook

Cumulative knowledge from building a **statewide Texas address geocoder** on PostGIS, a set of
**population density visualizations**, and a **JasperReports 7** report over the same data.

> Conventions: `psql`/PostgreSQL **14** at `C:\Program Files\PostgreSQL\14\bin`. Database
> **`postgis_34_sample`** on `localhost:5432`, user/pw **`postgres` / `<your local password>` (set via $env:PGPASSWORD)**. Staging dir **`C:\gisdata`**.

---

## 1. What exists

- **Statewide TIGER geocoder** in `postgis_34_sample` — all **254 Texas counties** loaded
  (edges 5,692,076 · featnames 5,060,971 · addr 2,664,841 · faces 1,924,566 · place 1,860),
  plus nation state/county. `geocode('1100 Congress Ave, Austin, TX 78701')` → rating 0.
- **Population data**: `tiger_data.tx_tabblock20` (668,757 2020 census blocks, statewide, with `pop`),
  `tiger_data.tx_bg` (18,638 block groups), `tiger_data.tx_tract` (6,896 tracts). TX total pop 29,145,505.
- **Maps** (in `maps\`, open in a browser): statewide heatmap (2 km grid), Houston heatmap (500 m),
  full block-detail heatmap (449k blocks), tract choropleth, block-group choropleth, and two geocode-pin maps.
- **JasperReports** (in `report\`): a block-group density report in both 6.x and native JR 7 form,
  compiled (`.jasper`) and rendered (`output\tx_density_blockgroup_report.pdf`, 317 pages).

## 2. Prerequisites / environment (this machine)

| Tool | Location | Notes |
|------|----------|-------|
| PostgreSQL + PostGIS 3.4 | `C:\Program Files\PostgreSQL\14\bin` | DB `postgis_34_sample`, the Tiger geocoder + address_standardizer extensions |
| curl | `C:\WINDOWS\system32\curl.exe` | **used instead of wget** (see gotchas) |
| 7-Zip | `C:\Program Files\7-Zip\7z.exe` | unzip + `7z t` integrity checks |
| JDK | `C:\jdk-11.0.24+8` (set `JAVA_HOME`) | Java 11; runs JasperReports + javac |
| Maven | `C:\apache-maven-3.9.9\bin\mvn.cmd` | built JasperReports from source |
| JasperReports 7.0.6 runtime | `C:\Users\rgorsuch\jasperreports-lib\` | 37 jars (core, pdf, openpdf, PG JDBC driver, deps) |
| JasperReports 7.0.6 source | `C:\Users\rgorsuch\jasperreports-7.0.6\` | Maven source project (extracted from the -project.zip) |

## 3. GOTCHAS (the expensive-to-rediscover lessons)

1. **wget: use curl instead.** `winget install wget` fails — its source `eternallybored.org` is
   not reachable from this environment. **Use the built-in `curl.exe`.** The TIGER loader scripts
   were rewritten to use `curl --location --fail --retry 3 --create-dirs -o "<host\path>" "<url>"`
   (rebuilds wget --mirror's directory tree).
2. **Census downloads silently corrupt.** curl exits 0 (HTTP 200) but bytes can be truncated/bad
   (this killed PLACE + TRACT on the first run). **Always validate every download with `7z t` and retry.**
   `load_tiger_TX.bat` has a `:getverified` subroutine that does this; the PS1 loaders use a `Get-Verified` function.
3. **Cloudflare can cache a WAF "Request Rejected" page** (247-byte HTML, HTTP 200, `cf-cache-status: HIT`)
   for a specific census URL (hit on Nacogdoches `48347` edges). `--fail` won't catch it. **Fix: re-request with a
   cache-buster query string (`?cb=<timestamp>`) + a browser `-A` User-Agent.**
4. **PowerShell mangles Maven `-D` args.** `-Dmaven.test.skip=true` gets split into a bogus lifecycle phase.
   **Pass Maven args after the `--%` stop-parsing token.**
5. **JasperReports 7 has a NEW jrxml format**, NOT backward-compatible with 6.x (Jackson-based loader):
   no XML namespace; root `<jasperReport name=".." language="java" ..>`; `<queryString>`→`<query>`;
   `<reportElement>` removed (x/y/w/h flattened onto `<element kind="..">`); `textAlignment`→`hTextAlign`/`vTextAlign`;
   `<variableExpression>`/`<groupExpression>`→`<expression>`. A 6.x jrxml fails JR7's CLI loader (open in
   Jaspersoft Studio to auto-upgrade, or use the `_jr7` version here).
6. **JR 7 PDF export is a separate module** (`jasperreports-pdf` / OpenPDF) — core alone throws
   "Missing JasperReports PDF Extension". Build `ext/pdf` too.
7. **`usa_states`** was SRID 0 (undefined) → fixed to **4269** (NAD83, matches TIGER). It and two other
   former-`public` data tables now live in schema **`tiger`** (`tiger.usa_states` etc.). `public` holds only
   PostGIS/extension objects — do NOT move those.

## 4. Scripts (`scripts\`)

All use absolute paths; safe to run from anywhere. Run `.bat` from `cmd.exe`, `.ps1` via `powershell -File`.

| Script | Purpose |
|--------|---------|
| `load_tiger_nation.bat` | One-time: load national STATE + COUNTY lookup tables. Run first. |
| `load_tiger_TX.bat` | Full statewide TX loader (all layers, all 254 counties). Has the `:getverified` CRC-verify+retry fix and curl. Long run. |
| `load_geocode_travis.bat` | Loads PLACE (statewide) + EDGES/FEATNAMES/ADDR for Travis County only (fast demo). |
| `load_geocode_faces_zip.bat` | Loads Travis FACES + builds the zip lookup tables (needed for geocoding). |
| `load_metros.ps1` | Verified loader for 16 metro counties (faces/featnames/edges/addr), idempotent. |
| `load_remaining.ps1` | Verified loader for ALL remaining counties; **idempotent** (skips counties already in `tx_edges`). |
| `test_verify.bat` | Standalone test of the download-verify-retry subroutine. |

## 5. Reports (`report\`)

- `tx_density_blockgroup_report.jrxml` — JasperReports **6.x** format (open in Jaspersoft Studio to auto-upgrade).
- `tx_density_blockgroup_report_jr7.jrxml` — native **JR 7** format; compiles with the built library.
- `tx_density_blockgroup_report_jr7.jasper` — compiled report.
- `postgis_34_sample.xml` — Jaspersoft Studio JDBC data adapter (needs the PostgreSQL driver on its classpath).
- `CompileReport.java` / `FillReport.java` — CLI compile + fill/export harnesses.

**Build the JasperReports library (once):**
```
set JAVA_HOME=C:\jdk-11.0.24+8
mvn --% -f C:\Users\rgorsuch\jasperreports-7.0.6\pom.xml -pl core,ext/pdf -am -Dmaven.test.skip=true -Dmaven.javadoc.skip=true -B install
mvn --% -f C:\Users\rgorsuch\jasperreports-7.0.6\core\pom.xml  dependency:copy-dependencies -DoutputDirectory=C:\Users\rgorsuch\jasperreports-lib -DincludeScope=runtime
mvn --% -f C:\Users\rgorsuch\jasperreports-7.0.6\ext\pdf\pom.xml dependency:copy-dependencies -DoutputDirectory=C:\Users\rgorsuch\jasperreports-lib -DincludeScope=runtime
copy core\target\jasperreports-7.0.6.jar + ext\pdf\target\jasperreports-pdf-7.0.6.jar into jasperreports-lib\
:: PostgreSQL JDBC driver: curl https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.4/postgresql-42.7.4.jar -> jasperreports-lib\
```

**Compile + render to PDF** (run from `report\`):
```
set CP=C:\Users\rgorsuch\jasperreports-lib\*
set PGPASSWORD=<your local password>   :: FillReport reads PGPASSWORD from the environment
"C:\jdk-11.0.24+8\bin\javac.exe" -cp "%CP%" CompileReport.java FillReport.java
"C:\jdk-11.0.24+8\bin\java.exe" -Dnet.sf.jasperreports.compiler.class=net.sf.jasperreports.engine.design.JRJavacCompiler -cp "%CP%;." CompileReport tx_density_blockgroup_report_jr7.jrxml
"C:\jdk-11.0.24+8\bin\java.exe" -cp "%CP%;." FillReport tx_density_blockgroup_report_jr7.jasper ..\output\tx_density_blockgroup_report.pdf
```

## 6. Maps (`maps\`)

Self-contained HTML (Leaflet + CDN). Open directly in a browser.

| File | Shows |
|------|-------|
| `tx_population_heatmap.html` | Statewide pop heatmap, 2 km grid (64,722 cells) |
| `tx_population_heatmap_blocks.html` | Full block-detail heatmap (449k blocks; heavy) |
| `houston_population_heatmap.html` | Houston metro, 500 m grid |
| `tx_density_choropleth.html` | Density choropleth by census tract (6,896) |
| `tx_density_choropleth_blockgroup.html` | Density choropleth by block group (18,638) |
| `geocode_result.html` / `geocode_houston.html` | Single geocoded address pins |

## 7. Rebuild order from scratch

1. `load_tiger_nation.bat` (national lookups).
2. `load_remaining.ps1` (verified statewide county load; or `load_tiger_TX.bat`). Sweep the log for
   `DOWNLOAD FAILED (skipped)` and repair those files with the cache-buster+UA trick.
3. Build the JasperReports library (§5), compile + fill the report.
4. Regenerate maps as needed (queries embedded in session history; data in `tiger_data.tx_*`).

## 8. Useful geocode test

```sql
SELECT g.rating, ST_X(g.geomout) lon, ST_Y(g.geomout) lat, pprint_addy(g.addy)
FROM geocode('901 Bagby St, Houston, TX 77002', 1) AS g;
```

## 9. JasperReports Server automation — the `jasper-deploy` skill

`.claude/skills/jasper-deploy/` scripts the full JasperReports lifecycle against a local
**JasperReports Server 10** over REST v2. Everything is **JR 7.0.6-native**. `SKILL.md` is the
authoritative reference; `references/` now holds: `gotchas.md` (50 issues indexed by symptom → fix),
`jr7-valid-elements.md` (strict-Jackson valid/rejected element lists, source-cited), the distilled JR7
schema (`jr7-schema.md`), the verified JRS REST API map + `application.wadl` (a committed snapshot of
this server's exact REST surface), the reverse-engineered dashboard model, `manifest.schema.json` +
`jrs.config.schema.json` (JSON Schemas), and `seed-data.md` / `smtp-testing.md` / `ci-smoke.md` /
`visualize-embedding.md`. `fixtures/README.md` indexes known-good exemplars and `baselines/*.png` back
`verify_report.ps1 -Baseline`.

**Server / toolchain**
- JRS PRO at **`http://localhost:8081/jasperserver-pro`** (HTTP Basic, `superuser`/`superuser`).
  Port **8080** is an unrelated Bearer-gated service — not JRS.
- JR 7.0.6 runtime jars at `C:\Users\rgorsuch\jasperreports-lib\` (resolved via `-LibDir` →
  `$env:JR_LIB_DIR` → `jrs.config.json` `jrLibDir` → that default).
- Credentials/URL resolve: script params → env `JRS_URL`/`JRS_USER`/`JRS_PASS` → `jrs.config.json`
  (gitignored; copy `jrs.config.example.json`).

**Scripts (`scripts\`)**

| Script | Purpose |
|--------|---------|
| `scaffold_jrxml.py` | Introspect a SQL query → emit a JR7 tabular report. Flags: `--chart`/`--chart-label-rotation`, `--param`, `--group-by`, `--highlight`, `--drill`, `--crosstab`, `--subreport`, `--style-template`. |
| `compile_jrxml.ps1` | Compile `.jrxml` → `.jasper` (fast JR7 validity check; via shared `Invoke-JrCompile`). |
| `create_datasource.ps1` | Create/update a datasource: JDBC plus `-Type jndi\|bean\|custom\|virtual\|aws` (`-Overwrite` updates in place). |
| `deploy_report.ps1` | PUT a report unit. `-Overwrite` updates in place (works for in-use reports); SQL-lint guard; `-Control` attaches static input controls; `-QueryControl`/`-QueryMultiControl` attach query-backed + cascading controls. |
| `verify_report.ps1` (+ `pdf_verify.py`) | Run a deployed report and assert HTTP + CSV row-count/contains + a visual baseline diff. |
| `scaffold_style_template.py` | Emit a shared JR7 `.jrtx` style template from a palette (upload as a file resource; reference via `scaffold_jrxml.py --style-template`). |
| `scaffold_domain_schema.py` / `create_domain.ps1` | Introspect a table → single-table Domain `schema.xml`; create the `semanticLayerDataSource` (schema embedded inline). |
| `manage_adhoc.ps1` | Ad hoc views (`adhocDataView`): `list` / `get` (inspect JSON) / `export` / `import` / `delete`. |
| `scaffold_theme.py` / `deploy_theme.ps1` | Emit an `overrides_custom.css` from a palette; deploy a CSS file or theme folder and `-Activate` it per organization. |
| `create_mondrian.ps1` | OLAP: upload a Mondrian schema + create a `secureMondrianConnection` (and best-effort an MDX `olapUnit` view). |
| `manage_permissions.ps1` / `manage_attributes.ps1` | Repository ACLs (get/set/clear) and server/org/user attributes (get/set/delete). |
| `manage_users.ps1` / `manage_roles.ps1` / `manage_organizations.ps1` | Tenant/identity admin: user, role, and organization CRUD (server- or org-scoped). |
| `run_report_async.ps1` | Run a report via the async `reportExecutions` service (submit→poll→download) — for large fills that time out synchronously. |
| `manage_options.ps1` / `manage_cache.ps1` | Saved input-control value sets (create/list/run/delete) and clear a server cache (`DELETE /rest_v2/caches/{id}`). |
| `build_dashlets.ps1` | Manifest-driven: scaffold→compile→deploy→verify each dashlet; `-Compose` then builds the dashboard. |
| `gen_dashboard.py` / `compose_dashboard.ps1` | Synthesize a dashboard (report/text/image tiles, auto-grid, wiring) and import it so it renders. |
| `export_resource.ps1` / `import_resource.ps1` | Export/import any resource (back up, version, restore). |
| `promote.ps1` | Export from a source server, import into a target — dev→prod promotion. |
| `teardown_dashboard.ps1` | Delete a dashboard then (optionally) its report tiles + `_controls`, in lock-safe order. |
| `lint_jrxml.ps1` | Static pre-deploy linter for `.jrxml`/`.jrtx`/`.jrdax` — catches the strict-Jackson 400s a clean compile misses (isDefault, `.jrdax` non-CSV elements, pie `seriesColors`/`seriesOrder`, leading-`WITH` SQL, line/area plot props, title-band `evaluationTime`). Exit 1 on error; `-WarningsAsErrors` to fail on warnings too. Wired into `smoke_test.ps1`. |
| `extract_lineage.py` | Read-only repository crawler → asset + lineage graph (`lineage.json` + `assets.csv`/`edges.csv`): reports→datasources/domains/source-tables, dashboards→reports. Stdlib-only. Implements the model in `JASPERSOFT_CATALOG_CONNECTOR_PDD.md`. |
| `diff_resource.ps1` | Drift detector — diffs a live resource descriptor vs. a committed local `.json`; exits nonzero on drift. Pairs with `promote.ps1`. |
| `smoke_test.ps1` | 19-step end-to-end regression gate (scaffold→**lint**→compile→deploy→…→style template→domain→jndi/aws datasource→theme→cascading query controls→permissions→attributes→mondrian→teardown under `/reports/_smoke`). |
| `upload_file.ps1`, `deploy_jr_samples.ps1`, `_jrs_common.ps1` | File upload, bulk sample deploy, shared helpers. |

**Quick start**
```powershell
$skill = ".\.claude\skills\jasper-deploy\scripts"; $env:PGPASSWORD = "postgres"
# build + deploy + verify all dashlets, then compose the dashboard:
& $skill\build_dashlets.ps1 -Manifest report\foodmart\dashboard.json -Compose
# regression gate after editing any script:
& $skill\smoke_test.ps1
```

**GOTCHAS (skill-specific)**
1. **JRS SQL security validator**: report queries must begin with `SELECT`. A leading `WITH` (CTE)
   compiles locally but is rejected at fill time (`JSSecurityException` → generic `400`). `deploy_report.ps1`
   now lints+blocks this before deploy (`-SkipSqlLint` to override); fix by pushing each CTE into a `FROM`
   subquery. Window functions (`... over ()`) are fine.
2. **Dashboards: import, don't PUT.** A hand-built dashboard model PUT to `/rest_v2/resources` stores
   (201) but renders **blank**. `compose_dashboard.ps1` instead exports the real dashlets, injects the
   synthesized model, and **imports** (re-zipped with forward-slash entries — the Java importer ignores
   back-slash paths). See `references/dashboard-model.md`.
3. **`resource.in.use` (403)**: a report that is a dashlet of a dashboard is modification/delete-locked.
   `deploy_report.ps1` updates in place to dodge it; `build_dashlets.ps1` reports such reports as
   "in-use (kept)"; `teardown_dashboard.ps1` deletes the dashboard first to release the lock.
4. **Input controls** must be standalone repository resources referenced by the report (embedding is
   rejected); the control's name must equal the `$P{param}` it drives.
5. **Subreport** `--subreport` must reference a jrxml **file** resource (e.g. `…/rpt_files/Label_main_jrxml`),
   not a report unit.
6. **Domains & ad hoc views are scripted now.** Single-table Domains: `scaffold_domain_schema.py` +
   `create_domain.ps1` (the schema.xml must be **embedded inline** in the descriptor — a pre-uploaded
   `schemaFileReference` 500s `resource.does.not.exist`; and the schema's `datasourceId` must equal the
   `-DataSourceUri` leaf). Ad hoc views: `manage_adhoc.ps1` lists/inspects/exports/imports them (a raw
   JSON **PUT is rejected `500 "bytes is null"`** — move them via export/import, like dashboards). What's
   still designer-only: an ad hoc view's interactive state, multi-table Domains (joins), and filter-group /
   input-control dashboard tiles — author those in the web UI and promote with `export`/`import`/`promote.ps1`.
7. **Style templates (`.jrtx`)**: the default-style attribute is **`default="true"`**, NOT the 6.x
   `isDefault="true"` (JR7 parses the `.jrtx` with strict Jackson → `UnrecognizedPropertyException` as a
   generic `400` at fill time, not a compile error). `scaffold_style_template.py` emits the correct form.
8. **Non-JDBC datasources**: `create_datasource.ps1 -Type jndi|bean|custom|virtual|aws` validates the
   **descriptor shape** and stores the resource; *connecting* still needs the server-side prerequisite
   (JNDI resource / Spring bean / custom service / referenced sub-datasources / live AWS creds).
   The AWS `-Region` value is the **endpoint host** (`us-east-1.amazonaws.com`), not the bare code.
9. **OLAP `olapUnit` is best-effort**: the schema + `secureMondrianConnection` create reliably, but a
   saved analysis view OPENS the connection and validates the MDX against the live cube, so it `500`s
   unless the Mondrian schema parses against the backing DB. `create_mondrian.ps1` warns and keeps the
   schema + connection.
10. **PowerShell 5.1 quirks (in the new scripts)**: `?` is a legal variable-name char, so a URL built as
    `"$base?name="` drops the base (→ `405`) — use `"${base}?name="`. And `ConvertTo-Json` unwraps a
    single-element array property to a scalar (server `400`s `ArrayList from String`) — emit such arrays
    as hand-built JSON. (`manage_attributes.ps1` / `deploy_report.ps1` handle both.)
11. **JR7 chart plot properties are per-class.** `line` uses `showLines`/`showShapes`;
   `bar`/`bar3d`/`stackedbar` use `showTickMarks`/`showTickLabels`; **`area` (`JRDesignAreaPlot`) accepts
   NEITHER pair** — it gets a bare `<plot/>` (only `categoryAxisTickLabelRotation` is valid). The wrong
   pair throws `UnrecognizedPropertyException` at compile/fill. `scaffold_jrxml.py` emits the correct plot
   per type (a prior version emitted tick props for `--chart area`, which failed to compile — now fixed);
   `lint_jrxml.ps1` catches the wrong form, and the per-class valid lists are in
   `references/jr7-valid-elements.md`. The harmless SLF4J "no providers" line goes to stderr and can abort
   a `$ErrorActionPreference=Stop` wrapper — `Invoke-JrCompile` absorbs it.
12. **`compose_dashboard.ps1 -WorkDir` accepts an absolute path now.** It previously joined the work dir
   with `Get-Location` unconditionally, so an absolute `-WorkDir` produced an invalid `C:\cwd\C:\abs`
   path and `ExtractToDirectory` threw "the given path's format is not supported". Pass an absolute
   `-WorkDir` when the caller's CWD isn't writable (the web wizard runs it from the Tomcat temp dir).

## 10. Self-service web wizard (`webapp\jasper-wizard\`)

A **Jakarta servlet WAR** (Actian-branded) that puts the `jasper-deploy` skill behind a browser UI for
business users — no JRXML or REST knowledge needed. It runs inside the JRS Tomcat at
**`http://localhost:8081/jasper-wizard/`** and covers the full lifecycle: reports (SQL→chart/table with
live query preview + interactive input controls), dashboards, data sources, domains, themes, run & export
(PDF/XLSX/CSV/DOCX/PPTX + async), scheduling, repository browse, ad hoc list/export, permissions, and a
**Server Summary** overview (repository inventory + runtime characteristics). `webapp/jasper-wizard/README.md`
is the authoritative reference.

**Architecture.** Reads / preview / run are proxied straight to JRS REST by a small `JrsClient` (auth added
server-side: no browser creds, no CORS). Create / deploy actions shell out to the verified skill scripts via
`ScriptRunner` (`scaffold_jrxml.py`, `deploy_report.ps1`, `create_datasource.ps1`, `compose_dashboard.ps1`,
`scaffold_domain_schema.py`+`create_domain.ps1`, `scaffold_theme.py`+`deploy_theme.ps1`, `schedule_job.ps1`,
`manage_permissions.ps1`, `manage_adhoc.ps1`, `export_resource.ps1`, `run_report_async.ps1`). **So a change to
a script's parameters or stdout shape can require updating the matching wizard handler.**

**Build & deploy** (no Maven):
```powershell
cd webapp\jasper-wizard
.\build.ps1                 # compile + bundle scripts + WAR + hot-deploy to the JRS Tomcat
# .\build.ps1 -NoDeploy     # just build target\jasper-wizard.war
```

**Environment realities the build accounts for**
- **Tomcat is 10.1.x → Jakarta Servlet** (`jakarta.servlet.*`, not `javax.*`); compiles against Tomcat's
  bundled `servlet-api.jar` with JDK 11.
- **The Tomcat service runs as `NT AUTHORITY\LocalService`**, which can't read the user profile/repo — so the
  skill scripts are **bundled inside the WAR** (`WEB-INF/scripts`) and child processes run from the **container
  temp dir** (writable). This is why the wizard passes an absolute `-WorkDir` to `compose_dashboard.ps1`.
- **No local jrxml compile** (drops the `jasperreports-lib` dependency); JRS compiles server-side on deploy
  and `deploy_report.ps1` lints the SQL first.
- **Config** is in `WEB-INF/web.xml` context-params (JRS URL/creds, PostgreSQL host/port/user/password,
  python exe, script timeout) — edit and rebuild, or edit the exploded webapp and restart the app.

**Security note.** The wizard runs user-supplied SQL against the configured DB and publishes with stored admin
credentials — it's an **internal, trusted-user tool**; keep it behind the JRS login / a network boundary.
Command args are passed as an argv array (no shell-injection surface), but the SQL runs with the data source's
privileges.
