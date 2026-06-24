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

## Toolchain (already on this machine)
- JR7 runtime jars: `C:\Users\rgorsuch\jasperreports-lib\` (incl. PostgreSQL
  driver and the `jasperreports-pdf` export module).
- JDK 11 (`C:\jdk-11.0.24+8`, also on PATH) — supports single-file source
  launch, so no separate `javac` step.
- `psql` 14 and `curl` 8.x on PATH.
- JasperReports Server (PRO/Enterprise) on **`http://localhost:8081/jasperserver-pro`**
  (REST v2, HTTP Basic auth). NOTE: a *different*, Bearer-token-gated Java
  service runs on :8080 — do not target it. The real install is `C:\Jaspersoft`.

## Workflow

### 1. Design — scaffold a JR7 jrxml from SQL
`scripts/scaffold_jrxml.py` introspects a query's result columns (via a psql
TEMP VIEW over `information_schema`), maps PostgreSQL types to Java field
classes, and emits a tabular JR7 report (title, column header, detail band,
page footer with "Page X of Y").

```powershell
# $skill points to the scripts/ subdirectory bundled with this skill.
# Use the base directory provided at the top of this skill's context:
$skill = "<skill-base-dir>\scripts"
# e.g. if invoked from the tx-geocoder project you can also use the repo-relative path:
# $skill = ".\.claude\skills\jasper-deploy\scripts"
$env:PGPASSWORD = "postgres"
python $skill\scaffold_jrxml.py `
    --name county_summary `
    --title "Texas County Edge Summary" `
    --subtitle "From the TIGER geocoder load" `
    --query "SELECT c.name AS county, count(*)::int AS edge_count FROM tiger_data.tx_edges l JOIN tiger.county c ON c.statefp='48' AND c.countyfp=l.countyfp GROUP BY 1 ORDER BY 2 DESC" `
    --out report\county_summary.jrxml
```
Use `--query-file q.sql` for long queries. Options: `--db --host --port --user`
(defaults: postgis_34_sample / localhost / 5432 / postgres), `--page-size
a4|letter`, `--landscape`. The scaffold is a starting point — refine layout by
hand using `references/jr7-schema.md`, or open it in Jaspersoft Studio.

**Branding (always-on):** the scaffolder emits a 44×44 **Actian logo** at the
top-left of the title band (`kind="image"` → `repo:/images/actian_logo`) and
**centers** the title/subtitle, on every report. This requires the logo to exist
in the repo once — upload it with `upload_file.ps1 -File <jpg> -Uri
/images/actian_logo -Type img -Overwrite` (Type **`img`**). `repo:` image refs
resolve server-side at fill time (they won't appear in a local `RenderPng`
preview — deploy + run-to-PDF to verify). Override the image with `--logo-uri`,
or drop the logo with `--no-logo`.

Pick a **visual template** with `--template` =
`slate|corporate|forest|minimal|dark` (default `slate`, the original look). The
theme sets the column-header band, title/subtitle, group band, row-rule and
footer colors; `minimal` paints no header fill (dark header text + an underline
rule) for a clean look. **Verified:** all themes compile JR7-clean and render
(corporate = filled deep-blue header + blue title; minimal = underline style),
data identical across themes. To add a palette, extend the `THEMES` dict in
`scaffold_jrxml.py`.

Add a **JFreeChart chart** in the summary band with `--chart`:
```powershell
python $skill\scaffold_jrxml.py --name metro_pop --chart bar `
    --query "SELECT metro, sum(pop)::bigint AS population FROM ... GROUP BY metro" `
    --out report\metro_pop.jrxml
```
`--chart` = `pie|pie3d|bar|bar3d|line|area|stackedbar`. The category column
defaults to the first text column and the value to the first numeric column;
override with `--chart-category`, `--chart-value`, `--chart-series` (multi-series
category charts), `--chart-height`. Best with a small number of categories.
`--chart-label-rotation -45` rotates category-axis tick labels so long bar/line
labels don't truncate. (The scaffolder emits the correct JR7 plot per chart
type: `line` uses `showLines/showShapes` — `showTickMarks/showTickLabels` throw
`UnrecognizedPropertyException` on a line plot — while bar/area/stackedbar use
`showTickMarks/showTickLabels`.)

**Branded `bar` charts (default).** A plain `--chart bar` is styled by the
`com.actian.jasper.GradientTrendCustomizer` JFreeChart customizer **by default**:
bars are painted on an **Actian-blue gradient that encodes the measure** (palest =
lowest, deep navy = highest) instead of a flat color, and if a second numeric
column exists it's drawn as an **amber trend line on a secondary axis** (auto-
picked, or set with `--chart-trend COLUMN`). The scaffolder emits
`customizerClass="…"` + a second `<series>`; the customizer identifies series by
position (row 0 = gradient bars, row 1 = trend line) so it's generic. Disable with
**`--no-gradient`** (plain flat bars). Only applies to `bar` (not bar3D/stacked/
multi-series via `--chart-series`). **Verified** end-to-end (local RenderPng +
server run-to-PDF).
> **Server prerequisite (one-time):** the customizer is a Java class, so its jar
> must be on the JRS classpath. Build + install:
> ```powershell
> $cc = ".\.claude\skills\jasper-deploy\chart_customizers"
> javac -cp "C:\Users\rgorsuch\jasperreports-lib\*" -d $cc\build $cc\com\actian\jasper\GradientTrendCustomizer.java
> jar cf $cc\actian-chart-customizers.jar -C $cc\build . ; Remove-Item -Recurse $cc\build
> Copy-Item $cc\actian-chart-customizers.jar "C:\Jaspersoft\jasperreports-server-10.0.0\apache-tomcat\webapps\jasperserver-pro\WEB-INF\lib\" -Force
> Restart-Service jasperreportsTomcat -Force   # needs admin/UAC; ~50s downtime
> ```
> Already installed on this server. It survives restarts but **not** a JRS
> reinstall/upgrade — re-copy + restart then. A bar report whose customizer jar is
> missing fails to fill (use `--no-gradient` to opt out).

**Advanced report features** (all on `scaffold_jrxml.py`, all verified):
- `--param NAME:TYPE[:DEFAULT]` — a report parameter used as `$P{NAME}` in the
  query (TYPE = string|integer|long|decimal|double|boolean|date|timestamp).
  Introspection substitutes the default literal for `$P{..}` so psql can run the
  query; the jrxml keeps `$P{..}`. Pair with `deploy_report.ps1 -Control` for an
  interactive prompt (below). Run-time override: `…/rpt.pdf?NAME=value`.
- `--group-by COLUMN` — group header + a subtotal footer summing every numeric
  column (the query should `ORDER BY COLUMN`).
- `--highlight "COL:OP:VALUE:#COLOR"` — a `<conditionalStyle>` shading the cell
  when the condition holds (numeric `> >= < <= == !=`; strings `== / !=`).
- `--drill "COL:TARGET_URI[:p=COL2;..]"` — COL becomes a ReportExecution
  hyperlink running TARGET_URI with row values as params.
- `--crosstab ROW:COL:MEASURE` — a JR7-native pivot (rows × columns, Sum of
  MEASURE) with row/column totals + grand total, instead of the flat table.
- `--subreport JRXML_FILE_URI[:p=COL;..]` — embed a child report in the summary
  band on the parent connection. The URI must point to a jrxml **file** resource
  (e.g. `/reports/x/rpt_files/Label_main_jrxml`, or one uploaded with
  `upload_file.ps1`) — not a reportUnit.

### 1b. Shared style templates (.jrtx)
Instead of repeating inline colors/fonts in every report, factor styling into a
**shared style template** (`.jrtx`) deployed once and referenced by many reports
— change the `.jrtx`, redeploy it, and every consuming report restyles.

`scripts/scaffold_style_template.py` emits a JR7 `.jrtx` (root `<jasperTemplate>`
with named `<style>`s) from the same palettes as `--template`:
```powershell
python $skill\scaffold_style_template.py --name jd_corporate --palette corporate `
    --out report\jd_corporate.jrtx      # palette in slate|corporate|forest|minimal|dark; --font, --base-size
```
Styles emitted: `jdBase` (the **default** style — sets fontName/base color for
every text element), plus `jdTitle/jdSubtitle/jdColumnHeader/jdDetail/
jdGroupHeader/jdGroupFooter/jdPageFooter` for hand-referencing via `style="…"`.
Deploy the `.jrtx` as a repository **file** resource, then reference it from a
scaffold with `--style-template`:
```powershell
& $skill\upload_file.ps1 -File report\jd_corporate.jrtx -Uri /styles/jd_corporate -Type xml -Overwrite
python $skill\scaffold_jrxml.py --name styled_rpt --style-template /styles/jd_corporate `
    --query "SELECT …" --out report\styled_rpt.jrxml   # emits <template><![CDATA["repo:/styles/jd_corporate"]]></template>
```
`--style-template` wraps a leading-`/` value as `repo:URI`; JRS resolves it at
fill time and applies the template's default style. **Verified end-to-end**
(deploy + run-to-PDF, `200` + `%PDF-`). **Gotcha:** JR7 parses the `.jrtx` with
the same strict Jackson deserializer as a `.jrdax` — the default-style attribute
is **`default="true"`**, NOT the 6.x `isDefault="true"` (a wrong name throws
`UnrecognizedPropertyException` at fill time as a generic `400`, not a clean
compile error).

### 2. Compile — validate jrxml -> jasper
`scripts/compile_jrxml.ps1` compiles against the JR7 runtime. A clean compile is
the fastest check that the jrxml is JR7-valid before deploying.

```powershell
& $skill\compile_jrxml.ps1 -Jrxml report\county_summary.jrxml
```
(The SLF4J "No providers" lines are harmless.) To preview a PDF locally, fill
the `.jasper` against the DB with the existing `report\FillReport.java` helper.

### 2a. (one-time) Create the datasource a report will use
A report needs a JDBC datasource on the server to run. Create it once with
`scripts/create_datasource.ps1` (the PostgreSQL driver ships with JRS):

```powershell
& $skill\create_datasource.ps1 `
    -Uri /datasources/postgis_34_sample `
    -Label "PostGIS 34 Sample" `
    -Database postgis_34_sample -DbUser postgres -DbPassword postgres
```
Defaults target PostgreSQL `localhost:5432`; override with
`-DbHost -DbPort -DbUser -DbPassword`, or pass a full `-ConnectionUrl` and
`-DriverClass` for another engine. NOTE: PowerShell reserves `-Db` (alias of
`-Debug`), so the database-name parameter is `-Database`.

**Non-JDBC datasources** — `create_datasource.ps1 -Type` also emits
`jndi|bean|custom|virtual|aws` descriptors (the matching
`application/repository.<type>DataSource+json` media type):
```powershell
& $skill\create_datasource.ps1 -Type jndi    -Uri /datasources/fm_jndi -JndiName jdbc/foodmart
& $skill\create_datasource.ps1 -Type bean    -Uri /datasources/fm_bean -BeanName myDsBean -BeanMethod getDataSource
& $skill\create_datasource.ps1 -Type custom  -Uri /datasources/cds -ServiceClass com.acme.MyDsService -Properties @{k="v"}
& $skill\create_datasource.ps1 -Type virtual -Uri /datasources/combined `
    -SubDataSources ([ordered]@{ fm='/public/Samples/Data_Sources/FoodmartDataSource'; pg='/datasources/postgis_34_sample' })
& $skill\create_datasource.ps1 -Type aws     -Uri /datasources/rds -DbInstanceIdentifier mydb `
    -Database foodmart -AccessKey AKIA... -SecretKey ...   # -Region defaults to us-east-1.amazonaws.com
```
**Verified:** `jndi`, `virtual`, and `aws` create (`201`) and round-trip. NOTE:
creating a non-JDBC datasource validates the **descriptor shape** and stores the
resource; actually *connecting* needs the server-side prerequisite (a JNDI
resource in the app server, a Spring bean on the classpath, a custom data-source
service, the referenced sub-datasources, or live AWS creds). **AWS `-Region`
gotcha:** the value is the AWS **endpoint host** (`us-east-1.amazonaws.com`,
`eu-west-1.amazonaws.com`), NOT the bare `us-east-1` code (which `400`s
"invalid Region").

### 3. Deploy — publish to JasperReports Server (REST v2)
`scripts/deploy_report.ps1` wraps the jrxml in a reportUnit descriptor (jrxml
inlined as base64) and PUTs it to `/rest_v2/resources`, creating intermediate
folders. JRS compiles the jrxml server-side on first run.

```powershell
& $skill\deploy_report.ps1 `
    -Jrxml report\county_summary.jrxml `
    -TargetUri /reports/geocoder/county_summary `
    -Label "County Edge Summary" `
    -DataSourceUri /datasources/postgis_34_sample
```
Verified working: a live deploy to this server returns `201 Created` and the
report unit is retrievable at its URI.

`deploy_report.ps1` also:
- **`-Overwrite`** now updates **in place** via `?overwrite=true` (no delete) — so
  it works even for a report that is a dashboard dashlet (a delete-then-create
  would hit `403 resource.in.use`; see Dashboards).
- **SQL lint** (on by default): blocks a query that begins with `WITH`/non-`SELECT`
  before deploying (the JRS security validator rejects it at fill time anyway).
  `-SkipSqlLint` overrides.
- **`-Control "param:kind[:label[:extra]]"`** (repeatable) attaches a JRS input
  control to the matching `$P{param}`, so the report prompts. `kind` =
  `select`/`multiselect` (extra = `Food;Drink;…`, or `Label=value;…`) or `single`
  (extra = `text|number|date|datetime`). Controls are created as standalone
  repository resources under `<report>_controls/` and referenced (the verified
  pattern — embedding controls in the report unit is rejected). Verify with
  `GET /rest_v2/reports/{uri}/inputControls`.
- **`-QueryControl` / `-QueryMultiControl`** (`string[]`) attach **query-backed**
  controls whose option list comes from SQL. Format
  `"param|valueCol|visibleCols|SQL"` (`|`-delimited; SQL is last so it may contain
  `|`; `visibleCols` comma-separated, defaults to `valueCol`). Each gets a companion
  `query` resource on the report's datasource (so `-DataSourceUri` is required).
  **Cascading:** reference a parent control as `$P{parent}` in a child's SQL and
  pass the parent earlier in the array — the child's options then filter by the
  parent's selection. (single = inputControl type 4, multi = type 7.) **Verified
  end-to-end:** a Product_Family → Product_Department cascade returns 16 / 4 / 6
  departments for Food / Drink / Non-Consumable via
  `GET /rest_v2/reports/{uri}/inputControls/{child}/values?{parent}=…`. PowerShell
  arrays take comma-separated values (`-QueryControl $a,$b`), not a repeated flag.

**Credentials** resolve in order: script params → env vars
`JRS_URL`/`JRS_USER`/`JRS_PASS` → `jrs.config.json` in the skill root. Copy
`jrs.config.example.json` to `jrs.config.json` and fill it in; it is gitignored.
This server authenticates `superuser`/`superuser` over HTTP Basic on port 8081.

**The datasource referenced by `-DataSourceUri` must already exist** (create it
with step 2a). List existing datasources with (use **`type=jdbcDataSource`** —
the generic `type=dataSource` returns `204`/empty on this server and looks like
"no datasources"):
```powershell
curl.exe -s -u "${user}:${pass}" "http://localhost:8081/jasperserver-pro/rest_v2/resources?type=jdbcDataSource&recursive=true"
```

**Browse / delete deployed resources.** List everything under a folder (e.g. to
see what reports are deployed), and delete a resource (report unit, datasource,
etc.) by its repo URI:
```powershell
# list a folder's contents (drop &type= to see all resource kinds)
curl.exe -s -u "${user}:${pass}" "http://localhost:8081/jasperserver-pro/rest_v2/resources?folderUri=/reports/geocoder&recursive=true&type=reportUnit"
# delete one resource (204 No Content on success); the repo URI is appended after /rest_v2/resources
curl.exe -s -u "${user}:${pass}" -X DELETE "http://localhost:8081/jasperserver-pro/rest_v2/resources/reports/geocoder/county_summary"
```
Deleting a folder is recursive (removes the report units inside it). To redeploy
in bulk, loop `deploy_report.ps1 -Overwrite` over the `report\*.jrxml` files.

### 4. (optional) Run the report server-side to verify
```powershell
curl.exe -s -u "${user}:${pass}" -o out.pdf `
    "http://localhost:8081/jasperserver-pro/rest_v2/reports/reports/geocoder/county_summary.pdf"
```
A `200` and a `%PDF-` file confirm JRS compiled the jrxml, connected through the
datasource, filled, and exported. Re-deploying an existing report fails with
`409 versions not match` (optimistic locking) — pass **`-Overwrite`** to
`deploy_report.ps1` to delete-then-recreate.

**Other export formats** — the same synchronous endpoint just takes a different
extension. **Verified on this server** (all `200` with real content): `.xlsx`,
`.csv`, `.docx`, `.pptx` (also `.rtf`, `.ods`, `.odt`, `.xml`). e.g.
`.../rest_v2/reports/reports/geocoder/county_summary.xlsx`. The magic bytes
differ per format (`PK` for the Office/OpenDocument zip formats), so verify by
HTTP `200` + a non-trivial byte size rather than `%PDF-`.

**Big reports — async execution** (`rest_v2/reportExecutions`). The synchronous
`/reports/{uri}.{fmt}` endpoint blocks until the fill finishes and can time out
on large reports (the `tx_density_blockgroup_report*` reports are ~1 MB / tens of
thousands of rows). The async service queues the fill and lets you poll. **Verified
round-trip on this server.** NOTE: on Windows, pass the JSON body from a **file**
(`--data "@req.json"`) — an inline `-d '{...}'` gets its quotes mangled and the
server 400s with `serialization.error`.
```powershell
# 1. POST the request (body from a file to survive PowerShell/curl quoting)
'{"reportUnitUri":"/reports/geocoder/county_summary","outputFormat":"pdf","interactive":false,"async":true}' |
    Set-Content out\req.json -Encoding utf8
$rid = (curl.exe -s -u "${user}:${pass}" -H "Content-Type: application/json" -H "Accept: application/json" `
    --data "@out\req.json" "http://localhost:8081/jasperserver-pro/rest_v2/reportExecutions" | ConvertFrom-Json).requestId
# 2. poll until ready  ->  {"value":"ready"}
curl.exe -s -u "${user}:${pass}" -H "Accept: application/json" ".../rest_v2/reportExecutions/$rid/status"
# 3. download the output (exportId comes from GET .../reportExecutions/$rid -> exports[0].id)
curl.exe -s -o out.pdf -u "${user}:${pass}" ".../rest_v2/reportExecutions/$rid/exports/$exportId/outputResource"
```

**API source of truth for THIS server** — rather than the external community docs
(which version-drift and 403 scripted fetches), the live WADL lists every
`rest_v2` endpoint this exact 10.0.0 install exposes:
`http://localhost:8081/jasperserver-pro/rest_v2/application.wadl?detail=true`
(drop `?detail=true` for the core-only, shorter listing). See
`references/jrs-rest-api.md` for a distilled, verified-vs-doc-only endpoint map.

**Verify content + visuals (not just HTTP 200).** `scripts/verify_report.ps1`
runs a deployed report and asserts more than a `%PDF-`: the format returns
`200` + right magic + non-trivial size; the CSV export has `>= -MinRows` data
rows and contains every `-Contains` string; and page 1 rasterized matches a
committed `-Baseline` PNG within `-MaxPixelDiff` (mean abs pixel diff;
`-UpdateBaseline` / a missing baseline saves it). `-Params @{name="val"}` sets
run params. Throws on any failed assertion.
```powershell
& $skill\verify_report.ps1 -Uri /reports/foodmart/foodmart_top_categories `
    -MinRows 10 -Contains "Vegetables","Snack Foods" -Baseline baselines\top_categories.png
```

**Verify a whole folder of reports** — run each to PDF and check the HTTP code +
`%PDF-` magic + a non-trivial byte size. (Do NOT count `/Type /Page` objects as a
signal — the page tree is usually compressed, so the grep reads 0 on a perfectly
good PDF.) A `400` with an XML `errorDescriptor` body (magic `<?xml`) is a fill
failure — read it; a leading-`WITH` CTE in the query is a common cause (see
gotchas).
```bash
base="http://localhost:8081/jasperserver-pro/rest_v2/reports/reports/geocoder"
for r in county_summary metro_population_piechart tx_addr_zip_summary; do
  curl.exe -s -u "$user:$pass" -o "out/$r.pdf" -w "%{http_code}" "$base/$r.pdf"
  echo "  $r  $(head -c5 out/$r.pdf)  $(stat -c%s out/$r.pdf)b"
done
```
**Open a deployed folder in the JRS web UI:**
`http://localhost:8081/jasperserver-pro/flow.html?_flowId=searchFlow&folderUri=/reports/geocoder`

To **preview locally as an image** (handy for charts), fill + render a page to PNG:
```powershell
$env:PGPASSWORD = "postgres"
java --class-path "C:\Users\rgorsuch\jasperreports-lib\*" `
    report\RenderPng.java report\my_report.jasper out.png   # optional 3rd arg = page index
```

### 5. (optional) Schedule a job / set a data alert
Two thin wrappers over the verified `jobs` and `alerts` REST services (see
`references/jrs-rest-api.md` for the underlying recipes). Both resolve
credentials the same way as `deploy_report.ps1` and pass their JSON body from a
file. **Verified end-to-end** (create→list→get→delete round-trips, and wired
into `smoke_test.ps1`).

**`scripts/schedule_job.ps1`** — recurring / triggered / one-off report delivery
to the repository and/or by email:
```powershell
# one-off PDF saved to the repo at a future date
& $skill\schedule_job.ps1 -ReportUri /reports/geocoder/county_summary `
    -Label "County summary" -StartDate "2026-12-01 09:00:00"
# every day forever, two formats, emailed
& $skill\schedule_job.ps1 -ReportUri /reports/geocoder/county_summary `
    -StartType now -OccurrenceCount -1 -RecurrenceInterval 1 -RecurrenceIntervalUnit DAY `
    -OutputFormats PDF,XLSX -MailTo ops@example.com
& $skill\schedule_job.ps1 -Action list -ReportUri /reports/geocoder/county_summary  # list/get/delete (-Id N)
```
`-StartType` `now|at` (default `at` if `-StartDate` given). For a recurring job
set `-OccurrenceCount -1` plus `-RecurrenceInterval`/`-RecurrenceIntervalUnit`
(`MINUTE|HOUR|DAY|WEEK`). `-Parameters @{p="v"}` bakes in report params.

**`scripts/manage_alert.ps1`** — fire a notification when a watched numeric
report element crosses a threshold:
```powershell
& $skill\manage_alert.ps1 -ReportUri /reports/geocoder/county_summary `
    -Label "Edge count high" -ElementUuid <element-uuid> -Operator ">" `
    -Threshold 500000 -MailTo ops@example.com
& $skill\manage_alert.ps1 -Action list -ReportUri /reports/geocoder/county_summary  # list/get/delete (-Id N)
```
`-ElementUuid` is the design `uuid` of the JR7 `<element>` to watch (the alerts
UI captures it by click; via REST you supply it — creation only validates the
descriptor shape, not element existence, so it's resolved at fire time).
`-Operator` accepts the JRS enums (`equals|notEqual|less|lessOrEqual|greater|
greaterOrEqual`) or the symbols `== != < <= > >=`. Firing drives the
evaluate→notify pipeline to the SMTP send; actual delivery needs a reachable
mail host configured server-side (see the alerts section of the REST reference).
**Two shape gotchas the scripts handle** (both surfaced as `400` otherwise):
the alert's `mailNotification.toAddresses` is a wrapper object `{address:[…]}`,
**not** a bare array (unlike jobs); and `baseOutputFilename` is required even for
an email-only alert.

## Bulk deploy (e.g. the JR Library demo samples)
`scripts/deploy_jr_samples.ps1` walks a folder of `.jrxml`, deploys each under
`-TargetRoot`, and runs it to PDF to verify (writes a results CSV). A report
with no `<query>` is "standalone" (deploys + runs on an empty data source);
reports WITH a query are skipped unless you pass `-DataSourceUri`.
```powershell
# standalone samples (render with no data)
& $skill\deploy_jr_samples.ps1 -SamplesDir C:\Users\rgorsuch\jasperreports-7.0.6\demo\samples
# query-based samples (e.g. charts) against demo data
& $skill\deploy_jr_samples.ps1 -SamplesDir ...\demo\samples\charts -DataSourceUri /datasources/postgis_34_sample
```
The JR Library `charts` samples query an HSQLDB demo DB (`SELECT * FROM Orders`).
`report\translate_hsqldb_demo.py` translates `demo/hsqldb/test.script` →
PostgreSQL (handles `CREATE MEMORY TABLE` and `\uXXXX` escapes) so the tables
load into `postgis_34_sample` and the samples run against the existing data
source. Caveat: many library samples rely on parameters the Java harness
supplies (e.g. `MaxOrderID`) — without a default they render blank; pass them at
run time (`...PieChartReport.pdf?MaxOrderID=11077`) or bake in defaults.
`report\inject_chart_defaults.py` does the latter for the charts samples
(injects `<defaultValueExpression>` into self-closing `<parameter>` tags) so
they render with content from the JRS UI with no input. A `200`+valid-PDF only
means it ran, not that it has content — spot-check pages.

## File resources & CSV data adapters
`scripts/upload_file.ps1` uploads any local file to JRS as a repository file
resource (REST v2) — CSV/image/font/properties referenced by reports:
```powershell
& $skill\upload_file.ps1 -File data\foo.csv -Uri /reports/jr_samples/data/foo -Type csv
```
Verified: the file uploads and is retrievable at its repo URI, byte-intact.

**CSV-backed reports** reference a CSV via a `.jrdax` data adapter (a
`<csvDataAdapter>` with `fileName`=`repo:/path`, `useFirstRowAsHeader` or
explicit `columnNames`, `recordDelimiter` (CRLF=`&#13;&#10;`, preserved by JRS),
`fieldDelimiter`, `datePattern`, `queryExecuterMode`). Set the adapter on the
relevant `<dataset>`/subDataset with a `net.sf.jasperreports.data.adapter`
property (= the adapter's `repo:` URI) and remove any `dataSourceExpression`.
Upload the CSV and the `.jrdax` with `upload_file.ps1`; deploy companion
resources (resource bundles, images) embedded in the report unit with
`deploy_report.ps1 -ResourceFiles "name=path"`.
**Verified (subdataset adapters):** the `chartthemes` AllChartsReport (5 CSVs via
subdataset adapters) renders all chart themes this way.
**Verified (single-CSV main report, end-to-end):** `csv_metro_pop.jrxml` reads a
7-row CSV as its **main** dataset — no JDBC datasource, no `<query>` — via a
report-level `net.sf.jasperreports.data.adapter` property pointing at
`metro_pop_adapter.jrdax`; fields map to columns by header
(`useFirstRowAsHeader`), and a numeric column declared `class="java.lang.Integer"`
is summed in a variable (the adapter does the String→Integer conversion). Flow:
upload the CSV + `.jrdax` (`upload_file.ps1`), deploy the report **with no
datasource** (the "won't run until a datasource is attached" warning is expected
and wrong for adapter-backed reports), run to PDF → all rows render.
Gotchas that cause a silent 0-row or a fill error:
(1) **strip the UTF-8 BOM** from the CSV — it trips the parser with "Misplaced
quote"; match `recordDelimiter` to the CSV's real line endings (`&#10;` for LF,
`&#13;&#10;` for CRLF). (2) a report with `resourceBundle="X"` needs the
`.properties` bundle embedded (`-ResourceFiles "X.properties=..."`) even with
`whenResourceMissingType="Key"` (that only covers missing keys, not a missing
bundle). (3) **JR7 parses the `.jrdax` with strict Jackson** — an unknown element
throws `UnrecognizedPropertyException` at fill time (`400`), NOT a clean compile
error. JR6-era fields like `<useConnection>` are rejected; the only valid
`CsvDataAdapterImpl` elements are: `name, fileName, dataFile, fieldDelimiter,
recordDelimiter, useFirstRowAsHeader, columnNames, queryExecuterMode, datePattern,
numberPattern, encoding, timeZone, locale`.
The single-CSV *query-executer* report (`csvdatasource`, empty
`<query language="csv">`) is still a harder case — build that one in Jaspersoft
Studio — but the property-on-main-dataset form above needs no Studio.

## Dashboards (compose from a manifest, OR author in the designer)

### Fully scripted: compose a dashboard of report dashlets from a manifest
`scripts/build_dashlets.ps1` drives the **entire** dashboard pipeline from one
JSON manifest — no designer needed for a dashboard whose tiles are deployed
reports (each a tabular report with a chart in its summary band):

```powershell
$env:PGPASSWORD = "postgres"
& $skill\build_dashlets.ps1 -Manifest report\foodmart\dashboard.json -Compose
```
For each `dashlets[]` entry it **scaffolds → compiles → deploys → verifies**
(runs to PDF, asserts `200` + `%PDF-` + non-trivial size), prints a results
table, then with **`-Compose`** assembles them into the dashboard. **Verified
end-to-end** building the 7-tile `foodmart_kpi_dashboard_auto`. The unified
manifest (see `report\foodmart\dashboard.json`) carries both the build spec and
the grid layout:
```jsonc
{ "db":"foodmart", "dataSourceUri":"/public/Samples/Data_Sources/FoodmartDataSource",
  "folder":"/reports/foodmart", "name":"foodmart_kpi_dashboard_auto",
  "label":"...", "outDir":"report\\foodmart",
  "dashlets":[ {
    "name":"foodmart_yoy_sales", "title":"Year-over-Year Sales", "chart":"bar",
    "chartCategory":"month","chartValue":"sales","chartSeries":"year",
    "chartHeight":380, "landscape":true, "queryFile":"report\\foodmart\\yoy_sales.sql",
    "x":0,"y":0,"width":40,"height":10 }, ... ] }
```
`x/y/width/height` place each tile on a 40-wide grid (omit them all and pass
`-AutoGrid`; manifest `"cols"` sets the column count, default 2). Use
`-SkipVerify` to skip the run-to-PDF check.

**Mixed tiles.** A dashlet's `"kind"` is `report` (default), `text`, or `image`:
- `text` — `{"kind":"text","name":"Hdr","text":"…","size":18,"bold":true,
  "align":"center","color":"rgba(..)","background":"rgb(..)"}`
- `image` — `{"kind":"image","name":"Logo","url":"repo:/path or http://…"}`

Only report tiles are exported/referenced; text/image carry no repository
resource. A manifest-level `"wiring":[{"producer":"A:out","consumers":["B:param"]}]`
appends cross-dashlet (filter) wiring. **Verified:** a text+report+report+image
dashboard composes, imports, and re-exports intact. The full model schema is in
`references/dashboard-model.md`. (Interactive **filterGroup + inputControl** tiles
and **ad hoc views** stay designer-authored — see that reference and the scope
note below.)

**How the compose step works (and why it renders, unlike a raw PUT).** A JRS
dashboard is a descriptor + three companion files (`components` = the dashlet
frames + a `DashboardProperties` singleton, `layout` = the `<div data-componentId
data-x data-y data-width data-height>` grid, `wiring` = `@init`→`@refresh` /
`@applyParams` events). `scripts/gen_dashboard.py` synthesizes all four from the
manifest (the model shape is reverse-engineered from a real designer export;
`id` = `re.sub('[^0-9A-Za-z]','_', label)`). `scripts/compose_dashboard.ps1`
then: exports the already-deployed dashlet reports (→ a real, importable
envelope: reportUnit descriptors + jrxml, datasource, folder chain, valid
`index.xml`), **injects** the synthesized dashboard into it, points
`index.xml`'s `repositoryResources` at the dashboard, re-zips with
**forward-slash** entries (the Java importer ignores back-slash paths — a silent
no-op), and **imports** it. Because the archive is structurally identical to a
designer export, the imported dashboard **renders** — verified by a clean
re-export round-trip (a broken import cannot be re-exported) and the HTML5
viewer.

> **Why import, not PUT?** You *can* PUT a hand-built dashboard model straight to
> `/rest_v2/resources` and the server stores it (201) — but the JRS 10 client
> **silently won't render it** (frames spin forever; the designer shows it
> empty), even when the stored model is byte-for-byte equivalent to a working
> one. The designer/import broker does extra work on save that a raw PUT skips.
> The **import** path (above) reproduces that work, so it renders. Don't PUT.

`compose_dashboard.ps1 -WorkDir` accepts an **absolute** path (defaults to the
relative `out\dash_build`). Earlier it joined the work dir with `Get-Location`
unconditionally, so an absolute `-WorkDir` produced an invalid `C:\cwd\C:\abs`
path and `ExtractToDirectory` threw "the given path's format is not supported";
that's fixed — pass an absolute `-WorkDir` when the caller's CWD isn't writable
(e.g. the web wizard runs it from the Tomcat temp dir).

**Gotcha — `resource.in.use` (403).** A report that is already a dashlet of an
**existing** dashboard is modification-locked by JRS: re-deploying it (delete or
`?overwrite=true` PUT alike) returns `403 resource.in.use` naming the owning
dashboard. `build_dashlets.ps1` treats this as **"in-use (kept)"** — not a
failure — leaves the deployed version in place, still verifies it renders, and
continues to compose. To actually push report changes, delete/recreate the
owning dashboard (or compose under a new name) first. `deploy_report.ps1
-Overwrite` now updates **in place** via `?overwrite=true` (no delete), which
also dodges the delete-protection on referenced resources.

### Author in the designer; promote via export/import
For dashboards with non-report tiles (ad hoc views, filter groups, text/input
controls) authoring is still a manual designer step:
1. Author once in the **designer**, dragging in already-deployed reports / ad hoc
   views, then Save:
   `http://localhost:8081/jasperserver-pro/dashboard/designer.html`
   (open an existing one at `dashboard/designer.html#<url-encoded uri>`).
2. **Version-control / back up / promote** it with the REST v2 export+import
   service (the archive is the designer's own output, so it re-imports and
   renders identically — ideal for dev→prod promotion across servers):
```powershell
& $skill\export_resource.ps1 -Uri /reports/geocoder/sales_dashboard -Out backups\sales_dashboard.zip
& $skill\import_resource.ps1 -Zip backups\sales_dashboard.zip      # -Update:$false to fail on existing
```
`export_resource.ps1`: POST `/rest_v2/export` `{uris,parameters}` → `{id}`, polls
`/rest_v2/export/{id}/state` until `phase=finished`, downloads
`/rest_v2/export/{id}/exportFile` (the download is **`/exportFile`** — a bare
`GET /rest_v2/export/{id}` returns `405`). `import_resource.ps1`: POSTs the zip
multipart to `/rest_v2/import?update=true`, polls `/rest_v2/import/{id}/state`.
Both export folders recursively (export a folder URI to grab a whole app).
**Verified:** round-trip export+import of the `1._Supermart_Dashboard` sample,
and a **destructive** round-trip of `5._Top_Performers` — export → DELETE the
dashboard (`resource.not.found`) → import → the full component model is restored
intact (all frames: charts, text dashlet, filter group, input control; plus the
embedded ad hoc views, `layout` and `wiring`). The export archive holds the
dashboard `.xml` descriptor + `_files/{components.data,layout,wiring.data}` +
each embedded ad hoc view.

**Promote dev→prod** with `scripts/promote.ps1 -Uri <uri> -ToServerUrl … -ToUser
… -ToPassword …` — exports from the source (this skill's config by default, or
`-From*`) and imports into the target server in one step (a folder URI promotes
a whole app). **Teardown** a composed dashboard with
`scripts/teardown_dashboard.ps1 -Uri <dash> [-IncludeReports] [-DryRun]` — it
deletes the dashboard first (releasing the `resource.in.use` locks), then its
report tiles + `<report>_controls` folders; a report still used by another
dashboard is skipped, not half-deleted.

**View a dashboard** in the HTML5 viewer (NOT a `flow.html` flow — there is no
`dashboardRuntimeFlow`; that errors "No flow definition found"). The resource URI
goes in the **URL-encoded hash fragment**:
`http://localhost:8081/jasperserver-pro/dashboard/viewer.html#%2Freports%2Fgeocoder%2Fsales_dashboard`

**Note on scope:** a dashboard of **report dashlets** is now fully scripted
(`build_dashlets.ps1 -Compose`, above). Export/import additionally
promotes/versions *any* dashboard across servers. **Ad hoc views** and
**Domains** now have their own scripted lifecycle (see those sections below):
single-table Domains are scaffolded + created outright, and ad hoc views are
listed/inspected/exported/imported (authoring an ad hoc view's interactive state
is still web-UI, but everything around it is scripted). The remaining manual step
is authoring dashboards whose tiles are **filter groups / input controls** drawn
in the designer. Everything else here — reports, their embedded charts,
report-tile dashboards, style templates, datasources, domains, and themes — is
scripted.

## Domains (semantic layer)
A **Domain** (`semanticLayerDataSource`) is a business-friendly view of a
datasource that Ad Hoc views and Domain reports query. It is two resources: a
descriptor binding a JDBC datasource to a **schema.xml** (tables, fields, and the
"items" exposed to the designer).

A **single-table** Domain is fully scripted. `scripts/scaffold_domain_schema.py`
introspects one table's columns (psql/`information_schema`) and emits the
`schema.xml`; `scripts/create_domain.ps1` creates the Domain:
```powershell
$env:PGPASSWORD = "postgres"
python $skill\scaffold_domain_schema.py --name foodmart_product --table product `
    --db foodmart --datasource-id FoodmartDataSource --out report\foodmart_product_schema.xml
& $skill\create_domain.ps1 -Uri /domains/foodmart_product `
    -SchemaFile report\foodmart_product_schema.xml `
    -DataSourceUri /public/Samples/Data_Sources/FoodmartDataSource -Label "Foodmart Product" -Overwrite
```
**Verified:** the Domain creates (`201`), the schema **materializes** at
`<Uri>_files/schema.xml`, the descriptor round-trips, and its
`GET /rest_v2/domains{uri}/metadata` behaves identically to the shipped sample
Domains. **Two gotchas the script handles:** (1) the schema's
`<jdbcTable datasourceId="…">` must equal the **leaf** of `-DataSourceUri` (pass
it as `--datasource-id`; the script warns on a mismatch). (2) the schema must be
**embedded inline** in the descriptor (`schema.schemaFile.content` base64, like a
reportUnit's jrxml) — a pre-uploaded `schemaFileReference` fails `500
resource.does.not.exist` because the `_files` child is orphaned until the parent
exists. **Multi-table** Domains (joins/`joinInfo`) are authored in the Domain
Designer and promoted with `export_resource.ps1`/`import_resource.ps1`.

## Ad hoc views
An **Ad Hoc view** (`adhocDataView`) is authored interactively in the Ad Hoc
Designer over a Topic (a jrxml file), a Domain, or a datasource. Its descriptor
carries a large opaque `query.multiAxis` + `component` state plus a companion
binary, so it is **not** scaffolded from scratch and a raw JSON **PUT does not
work** (the server rejects it `500 "bytes is null"` — the same don't-PUT lesson
as dashboards). `scripts/manage_adhoc.ps1` makes the lifecycle scriptable:
```powershell
& $skill\manage_adhoc.ps1 -Action list   -Folder /public/Samples/Ad_Hoc_Views
& $skill\manage_adhoc.ps1 -Action get    -Uri <view> -OutFile backups\view.json   # inspect / diff (not redeployable)
& $skill\manage_adhoc.ps1 -Action export -Uri <view> -OutFile backups\view.zip    # portable backup (carries Topic/Domain)
& $skill\manage_adhoc.ps1 -Action import -Zip backups\view.zip                     # restore / clone / promote
```
**Verified:** list, get-to-JSON, and the export→import round-trip. `export`/
`import` wrap the proven `export_resource.ps1`/`import_resource.ps1` envelope
(carries the view *and* its backing Topic/Domain, re-imports rendering-intact);
`promote.ps1` does dev→prod in one step.

## UI themes (CSS)
A **theme** restyles the JRS web UI via a folder of CSS (key file
`overrides_custom.css`) under a `Themes` folder. `scripts/scaffold_theme.py`
emits a starter `overrides_custom.css` from a palette; `scripts/deploy_theme.ps1`
deploys it (one CSS file or a whole folder incl. images/fonts) and can activate
it for an organization:
```powershell
python $skill\scaffold_theme.py --name corporate --palette corporate --out themes\corporate\overrides_custom.css
& $skill\deploy_theme.ps1 -CssFile themes\corporate\overrides_custom.css -Name corporate -Overwrite
# or a full theme folder, deployed to an org and made active:
& $skill\deploy_theme.ps1 -ThemeDir themes\corporate -Name corporate `
    -ThemesFolder /organizations/organization_1/themes -Activate -Organization organization_1
```
Themes take effect immediately (no restart). Without `-Activate`, preview by
appending **`&theme=<name>`** to any logged-in JRS UI URL. Activation is a
property of the **organization** (`PUT /rest_v2/organizations/{id}`
`{"theme":"<name>"}`). `-Overwrite` deletes an existing same-named theme folder
first (the ZIP-upload UI refuses to overwrite). **Verified:** scaffold → deploy →
the CSS serves back from its repo URI. The scaffolded selectors (banner, primary
buttons, login, table headers) are a **starting point** — refine against your
install's actual markup.

## OLAP / Mondrian
Server-side OLAP is three resources: an `olapMondrianSchema` (the Mondrian
cube/dimension XML, a file resource), a `secureMondrianConnection` binding a JDBC
datasource to that schema, and optionally an `olapUnit` analysis view (a saved
MDX query). `scripts/create_mondrian.ps1` does all three:
```powershell
& $skill\create_mondrian.ps1 -Uri /analysis/foodmart -SchemaFile report\foodmart_schema.xml `
    -DataSourceUri /public/Samples/Data_Sources/FoodmartDataSource -Label "Foodmart OLAP" -Overwrite `
    -ViewUri /analysis/foodmart_sales `
    -MdxQuery "select {[Measures].[Unit Sales]} on columns, {[Product].[All Products]} on rows from Sales"
```
**Verified:** the schema uploads + the `secureMondrianConnection` creates (`201`)
and round-trips (`schema.schemaReference` + `dataSource.dataSourceReference`).
Unlike a Domain, a Mondrian schema is a **standalone** resource (referenced, not
embedded). **The `olapUnit` view is best-effort:** creating it OPENS the
connection and validates the MDX against the live cube, so it `500`s unless the
schema actually parses against the backing DB (tables/columns must match) — the
script warns and still leaves the schema + connection in place. Grab a sample
schema to start from: `GET /rest_v2/resources/public/Samples/OLAP/Schemas/FoodmartSchema2013.xml`.

## Permissions & attributes
`scripts/manage_permissions.ps1` get/set/clear repository ACLs via the
`permissions` service:
```powershell
& $skill\manage_permissions.ps1 -Action get   -Uri /reports/geocoder -Effective
& $skill\manage_permissions.ps1 -Action set   -Uri /reports/geocoder -Recipient role:/ROLE_USER -Mask 30
& $skill\manage_permissions.ps1 -Action clear -Uri /reports/geocoder      # back to inherited (204)
```
`-Recipient`/`-Mask` are parallel arrays (one mask per recipient); `set` uses
`Content-Type: application/collection+json` (NOT `…collection.permission+json`,
which `415`s). Masks: 1=administer, 2=read+delete, 18=read+write, 30=read-only,
32=execute-only. **Verified:** set → confirm → clear round-trip.

`scripts/manage_attributes.ps1` get/set/delete a key-value attribute at server /
org / user scope (usable in datasource/report expressions as `{attribute('name')}`):
```powershell
& $skill\manage_attributes.ps1 -Scope server -Action set -Name dbHost -Value db.prod.internal
& $skill\manage_attributes.ps1 -Scope user   -UserName jdoe -Action set -Name region -Value west
& $skill\manage_attributes.ps1 -Scope server -Action delete -Name dbHost
```
**Verified:** server-scope set → get → delete round-trip. **Two gotchas the script
handles:** (1) a bare `PUT /attributes` REPLACES ALL ~134 system attributes, so
the server scope is **always `?name=`-scoped**; (2) PowerShell 5.1 treats `?` as a
variable-name char, so the path is built with `${base}` braces (else `"$base?name"`
silently drops the base and `405`s).

## Users, roles & organizations (admin)
Tenant/identity administration over the REST v2 `users`, `roles`, and
`organizations` services. All resolve credentials the same way as the other
scripts and pass JSON bodies from a file. **Verified end-to-end** (create→get→
delete round-trips for roles and users; org list + read; options below).

`scripts/manage_users.ps1` — user CRUD + role assignment. `create`/`delete`/`get`
hit `/rest_v2/users/{username}` (or `/rest_v2/organizations/{org}/users/{username}`
when `-Organization` is given); `PUT` both creates and updates (idempotent on
username). **Gotcha:** the JRS auth password is `-JrsPassword` here, because
`-Password` is the *new user's* initial password.
```powershell
& $skill\manage_users.ps1 -Action list   -Organization organization_1
& $skill\manage_users.ps1 -Action create -UserName jdoe -FullName "Jane Doe" `
    -Password "Secret123!" -Roles ROLE_USER,ROLE_ADMINISTRATOR -Organization organization_1
& $skill\manage_users.ps1 -Action delete -UserName jdoe -Organization organization_1
```

`scripts/manage_roles.ps1` — role CRUD (`/rest_v2/roles/{name}`, `PUT` create/
update). Pass `-Organization` for a tenant-scoped role.
```powershell
& $skill\manage_roles.ps1 -Action list
& $skill\manage_roles.ps1 -Action create -Name ROLE_ANALYST -Organization organization_1
& $skill\manage_roles.ps1 -Action delete -Name ROLE_ANALYST -Organization organization_1
```

`scripts/manage_organizations.ps1` — organization (tenant) CRUD. **Gotcha:**
create is **POST on the collection** (`/rest_v2/organizations?createDefaultUsers=true`,
WADL id `putOrganization`), not a `PUT {id}`; `update` is a read-modify-write
`PUT {id}` (so e.g. setting `-Theme` doesn't blank other fields) — this is the
same `{"theme":…}` activation `deploy_theme.ps1 -Activate` performs.
```powershell
& $skill\manage_organizations.ps1 -Action list
& $skill\manage_organizations.ps1 -Action create -Id acme -TenantName "ACME Inc"
& $skill\manage_organizations.ps1 -Action update -Id organization_1 -Theme corporate
& $skill\manage_organizations.ps1 -Action delete -Id acme
```

## Async report run, saved options & cache
`scripts/run_report_async.ps1` — run a report through the `reportExecutions`
service (submit → poll `…/status` until `ready` → download `…/outputResource`).
The proper path for large/slow fills that time out on the synchronous
`/reports/{uri}.{fmt}` endpoint. The final download uses a direct `curl -o` so
binary output is byte-intact. **Verified** (32 KB PDF round-trip).
```powershell
& $skill\run_report_async.ps1 -ReportUri /reports/foodmart/top_5_customers_revenue -OutFile out\rpt.pdf
& $skill\run_report_async.ps1 -ReportUri /reports/geocoder/county_summary_param `
    -Format xlsx -Parameters @{ minEdges = 50000 } -OutFile out\county.xlsx
```

`scripts/manage_options.ps1` — "report options": named saved sets of input-control
values stored beside a report (`/rest_v2/reports{uri}/options`). **Verified**
create→list→run→delete on `county_summary_param`/`minEdges` (the 50k option ran to
the 17-county filtered PDF). **Gotcha:** to *run* with the saved values, run the
option's OWN sibling URI as a report (`GET /reports/<folder>/<id>.pdf`) — a
`?reportOptions=<id>` query on the report URL does **not** apply them.
```powershell
$rpt = "/reports/foodmart/sample_report"
& $skill\manage_options.ps1 -Action create -ReportUri $rpt -Label Food_Snacks -Values @{ category="Food"; department=@("Snacks","Dairy") }
& $skill\manage_options.ps1 -Action list   -ReportUri $rpt
& $skill\manage_options.ps1 -Action run    -ReportUri $rpt -Id Food_Snacks -OutFile out\opt.pdf
& $skill\manage_options.ps1 -Action delete -ReportUri $rpt -Id Food_Snacks
```

`scripts/manage_cache.ps1` — clear a server cache via `DELETE /rest_v2/caches/{id}`
(invalidate the Ad Hoc / query result cache after the data changes). The service
is DELETE-only — there is no list-all GET. **Verified:** `queryCache` → `204`.
```powershell
& $skill\manage_cache.ps1 -CacheId queryCache
```

## Web wizard (self-service UI over these scripts)
`webapp/jasper-wizard/` (in the repo, **not** under this skill dir) is a Jakarta
servlet WAR that gives business users a browser UI for the whole lifecycle —
**reports** (SQL→chart/table with live query preview + interactive input
controls), **dashboards**, **data sources**, **domains**, **themes**, **run &
export** (multi-format + async), **scheduling**, **repository browse**, **ad hoc
view** list/export, **permissions**, and a **Server Summary** overview. It runs
inside the JasperReports Server's own Tomcat at
`http://localhost:8081/jasper-wizard/`.

**It consumes these scripts** — so if you change a script's parameters or stdout
shape, the wizard's matching handler may need updating. The split:
- **reads / preview / run** are proxied straight to JRS REST by `JrsClient`
  (auth added server-side: no browser creds, no CORS);
- **create / deploy** shell out to the verified scripts via `ScriptRunner`
  (`scaffold_jrxml.py`, `deploy_report.ps1`, `create_datasource.ps1`,
  `compose_dashboard.ps1`, `scaffold_domain_schema.py`+`create_domain.ps1`,
  `scaffold_theme.py`+`deploy_theme.ps1`, `schedule_job.ps1`,
  `manage_permissions.ps1`, `manage_adhoc.ps1`, `export_resource.ps1`,
  `run_report_async.ps1`).

**Build & deploy:** `cd webapp\jasper-wizard; .\build.ps1` (no Maven — compiles
against Tomcat 10.1's bundled Jakarta `servlet-api.jar` with JDK 11, bundles the
scripts into the WAR, hot-deploys to Tomcat). Key environment realities the build
already accounts for (see `webapp/jasper-wizard/README.md`):
- **Tomcat 10.1 = Jakarta Servlet** (`jakarta.servlet.*`, not `javax.*`).
- **Tomcat runs as `NT AUTHORITY\LocalService`**, which can't read the user
  profile/repo — so the scripts are **bundled inside the WAR** (`WEB-INF/scripts`)
  and the child processes run from the **container temp dir** (writable). This is
  why the wizard passes an absolute `-WorkDir` to `compose_dashboard.ps1`.
- **No local compile** of jrxml (drops the `jasperreports-lib` dependency); JRS
  compiles server-side on deploy and `deploy_report.ps1` lints the SQL first.

## Collateral docs (HTML -> DOCX/PDF via Word)
`scripts/make_docx.ps1` renders an HTML document to a `.docx` (and optionally a
`.pdf`) by driving a hidden **Microsoft Word** instance over COM — full CSS/table
styling fidelity with **no pandoc/LibreOffice**. This is the verified, repeatable
pattern behind the `Jaspersoft_*` feature/comparison documents in the repo root
(e.g. `Jaspersoft_Commercial_Edition.docx`), useful for generating report-
accompanying write-ups, enablement briefs, and edition/feature summaries. Word
COM is available on this machine; the script always releases the COM object in a
`finally` block so a failed run leaves no orphaned `WINWORD.EXE`.

```powershell
$skill = ".\.claude\skills\jasper-deploy\scripts"
# Full mode — convert a complete .html document and open it
& $skill\make_docx.ps1 -Html Jaspersoft_Commercial_Edition.html -Open
# Body mode — wrap an HTML *fragment* in the house theme (Actian-navy headings/
# tables), then emit DOCX + PDF. -Title sets the heading/<title>.
& $skill\make_docx.ps1 -BodyHtml summary_body.html -Title "Release Notes" -Pdf -Open
```
`-Out` overrides the output path (defaults to the input basename + `.docx`,
alongside the input); `-Pdf` also exports a PDF (`wdFormatPDF`); `-Open` launches
the result; `-KeepHtml` retains the wrapped temp HTML from `-BodyHtml`. **Verified
end-to-end** (both modes; Full mode is byte-equivalent to the hand-run Word
conversions, Body mode auto-cleans its `*.wrapped.html` temp). **Gotchas the
script handles:** Word COM requires **absolute paths** (resolved internally), and
the SaveAs format codes are **16 = `.docx`**, **17 = `.pdf`**. **Gotcha for
callers:** PowerShell 5.1 will not parse an inline `(if … {} else {})` as a method
argument — assign it to a variable first (this bit the script's own first draft).

## Notes / gotchas
- The live server is `jasperserver-pro` on **port 8081** (HTTP Basic). Port 8080
  hosts an unrelated Bearer-token-gated Java service that 401s every path — not JRS.
- **Smoke test:** after editing any script, run `scripts/smoke_test.ps1`
  (`$env:PGPASSWORD="postgres"` first) — it scaffolds → compiles → deploys (+input
  control) → verifies content → runs to PDF → schedules a job (CRUD) → sets an
  alert (CRUD) → composes a dashboard (report + text tile) → deploys a **style
  template** and runs a report that references it → creates a single-table
  **Domain** → creates a non-JDBC (**jndi**) datasource → deploys a UI **theme** →
  creates an **AWS** datasource → deploys a report with **cascading query input
  controls** (asserts the child option count changes per parent) → sets+clears
  **permissions** → server **attribute** CRUD → creates a **Mondrian** schema +
  connection → tears down, asserting each of the 18 steps under a throwaway
  `/reports/_smoke` (the theme lives under `/themes` and is cleaned up too).
- **JR runtime lib dir** resolves via `-LibDir` → `$env:JR_LIB_DIR` → `jrs.config.json`
  `jrLibDir` → the machine default; set `jrLibDir` on a fresh clone. The shared
  `Invoke-JrCompile` helper also absorbs the harmless SLF4J-on-stderr that would
  otherwise abort a `$ErrorActionPreference=Stop` caller.
- **JRS SQL security validator**: report queries must begin with `SELECT`.
  A leading `WITH` (CTE) is rejected at fill time with a `JSSecurityException`
  (`Validator.validateSQL`) surfaced as a generic `400`/error UID. Window
  functions (`... over ()`) are fine. A clean local `compile_jrxml.ps1` does NOT
  catch it (the CTE is valid JR/SQL) — but **`deploy_report.ps1` now lints and
  blocks it before deploy** (and `scaffold_jrxml.py` warns); `-SkipSqlLint`
  overrides. **Fix:** push each CTE down into a nested subquery in
  the `FROM` clause so the statement starts with `SELECT`, e.g.
  `WITH a AS (...), b AS (... FROM a) SELECT ... FROM b`
  → `SELECT ... FROM (... FROM (...) a) b`. The `tx_density_blockgroup_report*`
  reference reports were converted this way (verify the rewrite in psql first —
  output must be identical).
- See **## Visualization components** below for charts, spider charts,
  barcodes/QR (community, local) and HTML5/FusionMaps (Pro, server-rendered).
- The full JRS 10.0.0 PDF docs are in `docs/` (machine-local, **gitignored** like
  the `jasperreports-lib` jars — authoritative offline source, the community site
  403s scripted fetches; read PDFs with `pypdfium2`, not the Read tool, since
  `pdftoppm` is unavailable). `references/jrs-rest-api.md` is the
  distilled, verified endpoint map with `docs/` page cites; it now also covers the
  `options` (saved input-control sets, verified), `queryExecutor` (Domain-only),
  `alerts`, and richer `reportExecutions` services, non-JDBC datasource types, and
  a **verified** Visualize.js cross-origin embedding recipe (serve the page
  outside the webapp; `domainWhitelist` controls CORS).
- In PowerShell, pass Maven/Java `-D...` args after `--%` if you script the
  underlying tools directly.
- Field `class` must match the JDBC column type or fill fails — the scaffolder
  handles this; if you hand-edit the SQL, keep `<field class>` in sync.
- Reference reports known to compile and render:
  `..\..\report\tx_density_blockgroup_report_jr7.jrxml` (tabular + groups),
  `..\..\report\metro_population_piechart.jrxml` (pie chart).

## Visualization components

Two tiers. **Community** components compile + preview locally (RenderPng) *and*
deploy. **Pro** components are authored in the legacy 6.x jrxml format and only
render server-side on JRS Pro — the open-source lib can't compile them, so
validate them by **deploy → run-to-PDF** (a `200` + a non-trivial PDF, and the
`.html` export containing the component markup, confirm a render).

**Verified (both tiers, end-to-end):** Community — `compile_jrxml.ps1` → `.jasper`
then `RenderPng` → PNG for JFreeChart pie/bar (`metro_population_piechart`,
`metro_population_bar`), spider/radar (`metro_population_spider`), and barcode4j
QR/DataMatrix/Code128 (`barcode_demo`) — all render offline from the local jars,
content matching the data. Pro — deploy → run-to-PDF → rasterize for HTML5
HighCharts (`metro_population_html5`) and FusionMaps choropleth
(`tx_county_density_map`, `tx_county_population_map`) — both render server-side
with correct data. (RenderPng note: the SLF4J "no providers" line goes to stderr;
under PowerShell `$ErrorActionPreference="Stop"` that can abort a wrapper script
even on a clean exit 0 — invoke the `java` compiler/renderer directly, or check
the `.jasper`/`.png` output rather than trusting the pipeline's error state.)

### Community (local + deploy)
Extra jars in `C:\Users\rgorsuch\jasperreports-lib` (outside this repo — rebuild
on a fresh clone, see below):
`jasperreports-charts-7.0.6.jar`, `jfreechart-1.5.6.jar`,
`jasperreports-barcode4j-7.0.6.jar`, `barcode4j-2.1.jar`, `zxing-core-3.4.0.jar`.

| Component | JR7 jrxml | Example |
|---|---|---|
| JFreeChart (pie/bar/line/area/…) | `<element kind="chart" chartType="…">` + `<dataset kind="pie\|category">` + `<plot>` | `metro_population_piechart.jrxml`, `metro_population_bar.jrxml` |
| Spider / radar | `<element kind="component"><component kind="spiderChart">` (chartSettings/dataset series-category-value/plot) | `metro_population_spider.jrxml` |
| Barcodes / QR | `<element kind="component"><component kind="barcode4j:QRCode\|DataMatrix\|Code128\|…">` + `<codeExpression>` | `barcode_demo.jrxml` |

Pie label tokens: `{0}`=key, `{1}`=value, `{2}`=percentage. A no-query report
(e.g. static barcodes) needs `whenNoDataType="AllSectionsNoDetail"` on the root
or it produces 0 pages. QR specifically needs `zxing-core` on the classpath.

**Rebuild the community jars** from the JR7 source (machine-local, not in repo):
```powershell
$env:JAVA_HOME = "C:\jdk-11.0.24+8"
& "C:\apache-maven-3.9.9\bin\mvn.cmd" -f "C:\Users\rgorsuch\jasperreports-7.0.6\pom.xml" `
    -pl ext/charts,ext/barcode4j -am --% -Dmaven.test.skip=true package
```
Copy the built `ext\charts\target\jasperreports-charts-7.0.6.jar` and
`ext\barcode4j\target\jasperreports-barcode4j-7.0.6.jar`, plus from `~\.m2`:
`org\jfree\jfreechart\1.5.6\jfreechart-1.5.6.jar`,
`net\sf\barcode4j\barcode4j\2.1\barcode4j-2.1.jar`,
`com\google\zxing\core\3.4.0\core-3.4.0.jar` (→ `zxing-core-3.4.0.jar`), into
`C:\Users\rgorsuch\jasperreports-lib`. (JFreeChart 1.5.x bundles jcommon.)

### Pro (server-rendered only; deploy → run to validate)
Authored in legacy 6.x jrxml (`xmlns="http://jasperreports.sourceforge.net/jasperreports"`,
`<componentElement>`, `<queryString>`, `<reportElement>`). The whole file must be
6.x — you can't mix JR7-native with these. JRS's `legacy-jrxml-*` modules convert
at fill time; **skip local compile**, deploy and run.

| Component | jrxml | Example |
|---|---|---|
| HTML5 charts (HighCharts) | `<hc:chart xmlns:hc="http://jaspersoft.com/highcharts" type="Column\|StackedBar\|…">` with `<hc:chartSetting>` + `<multiAxisData>` (`dataAxis` row buckets + `multiAxisMeasure`) | `metro_population_html5.jrxml` |
| FusionMaps choropleth | `<fm:map xmlns:fm="http://jaspersoft.com/fusion">` with `<fm:mapNameExpression>`, `<fm:colorRange>`s, `<fm:mapDataset><fm:entity>` (idExpression + valueExpression) | `tx_county_density_map.jrxml` |

**Gotcha:** a chart/map component bound to the main dataset and placed in a
band that fills *before* row iteration (e.g. `title`) must set
**`evaluationTime="Report"`**, or it binds zero data and renders blank/uniform
(no error). Put it in `summary`, or keep it in `title` with that attribute.

**Preview a Pro report as an image** (no local renderer for Pro components — use
the server's PDF and rasterize it): run to PDF, then
```bash
python -m pip install pypdfium2 Pillow   # one-time
python -c "import pypdfium2 as p; p.PdfDocument(r'out.pdf')[0].render(scale=3).to_pil().save(r'out.png')"
```

FusionMaps geometry lives in `…\jasperserver-pro\fusion\maps\fusioncharts.*.js`.
The installed **`Texas`** map (`fusioncharts.texas.js`) is keyed by **county FIPS**
(no zero-padding), so bind `idExpression` to `(countyfp::int)::text` — no lookup
table. Other Pro options present on this server: Fusion charts/gauges/widgets
(`jasperreports-fusion`), HighCharts heatmap/treemap/solid-gauge, and Ad Hoc
views/dashboards (web-UI, not jrxml). Get jrxml syntax from the bundled samples,
e.g. fetch `/public/Samples/Reports/ProfitDetailReport` (HTML5) or
`/public/Samples/Reports/14._World_Map` (FusionMaps) jrxml via REST.
