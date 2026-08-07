# jasper-deploy gotchas (by symptom)

Fast-lookup index of the hard-won failures scattered through SKILL.md, grouped so
you can jump from an error message / observed behavior to the fix. Each entry:
Symptom / Cause / Fix / Handled-by (the script or flag that already deals with it).

ASCII only. Terse on purpose.

## Index

JR7 jrxml + community charts
- [G1  400 UnrecognizedPropertyException at fill on a LINE chart](#g1)
- [G2  Pie chart 400 UnrecognizedPropertyException (seriesColor / order)](#g2)
- [G3  KPI gauge deploys with opaque 400 (Pro FusionWidgets)](#g3)
- [G4  Meter/dial value not displayed; dial is an oval not a circle](#g4)
- [G5  Bar report fails to fill (gradient customizer jar missing)](#g5)
- [G6  Field class mismatch -> fill fails](#g6)
- [G7  Branded gradient not applied to bar3D/stacked/multi-series](#g7)
- [G8  No-query report produces 0 pages](#g8)
- [G9  repo: logo/image absent in local RenderPng preview](#g9)
- [G10 Subreport: invalid resource / wrong URI kind](#g10)

Data adapters (.jrdax) and style templates (.jrtx) - strict Jackson
- [G11 .jrdax 400 UnrecognizedPropertyException at fill time](#g11)
- [G12 .jrtx default style ignored / 400 (isDefault vs default)](#g12)
- [G13 CSV report yields 0 rows / "Misplaced quote"](#g13)
- [G14 resourceBundle report fails even with whenResourceMissingType=Key](#g14)

SQL security validator
- [G15 400 / error UID at fill on a leading-WITH (CTE) query](#g15)

Pro charts / maps (HTML5, FusionMaps)
- [G16 Pro chart/map renders blank or uniform (evaluationTime)](#g16)
- [G17 Pro component will not compile locally](#g17)

Dashboards
- [G18 PUT'd dashboard stored 201 but never renders](#g18)
- [G19 ExtractToDirectory: the given path's format is not supported](#g19)
- [G20 Recompose silently keeps the OLD layout](#g20)
- [G21 403 resource.in.use re-deploying a dashlet report](#g21)
- [G22 Imported dashboard is a silent no-op (back-slash zip entries)](#g22)
- [G23 Designer edits reverted on recompose](#g23)
- [G24 Dashboard URL errors "No flow definition found"](#g24)

Export / import
- [G25 405 on GET /rest_v2/export/{id}](#g25)
- [G26 Ad hoc view PUT 500 "bytes is null"](#g26)

Datasources
- [G27 Datasource list looks empty / returns 204](#g27)
- [G28 AWS datasource 400 "invalid Region"](#g28)
- [G29 Non-JDBC datasource created but will not connect](#g29)

Domains / OLAP
- [G30 Domain create 500 resource.does.not.exist](#g30)
- [G31 Domain metadata wrong / datasourceId mismatch](#g31)
- [G32 olapUnit view 500 on create](#g32)
- [G32b Multi-table Domain 400 element.name.not.unique](#g32b)

REST / PowerShell 5.1 / curl
- [G33 409 versions not match on re-deploy](#g33)
- [G34 Async POST 400 serialization.error (mangled JSON)](#g34)
- [G35 Attribute path 405 / base dropped ($base?name)](#g35)
- [G36 PUT /attributes wipes all ~134 system attributes](#g36)
- [G37 PowerShell drops the database name (-Db reserved)](#g37)
- [G38 Maven/Java -D args eaten by PowerShell](#g38)
- [G39 SLF4J-on-stderr aborts a Stop-mode wrapper](#g39)
- [G40 Synchronous /reports/{uri}.{fmt} times out on big reports](#g40)
- [G41 /Type /Page grep reads 0 on a good PDF](#g41)

File upload
- [G42 Uploaded image will not resolve (Type img)](#g42)

Permissions / attributes / admin
- [G43 415 setting permissions (wrong media type)](#g43)
- [G44 manage_users 401 (-Password vs -JrsPassword)](#g44)
- [G45 Org create: PUT {id} 404/wrong (must POST collection)](#g45)

Reports: alerts, options, run
- [G46 Alert create 400 (toAddresses shape / baseOutputFilename)](#g46)
- [G47 Saved report options not applied (?reportOptions=)](#g47)
- [G48 Library samples render blank (missing params)](#g48)

Collateral docs (Word COM)
- [G49 make_docx: bad path / wrong SaveAs format / inline if](#g49)

Environment
- [G50 Everything 401s (wrong port 8080)](#g50)
- [G51 401 with the RIGHT password (account lockout via stale client creds)](#g51)
- [G52 Connection test POST /contexts 415 (wrong media type)](#g52)
- [G53 Diagnostic collectors: bare DELETE wipes all / encrypted log / dup name](#g53)
- [G54 Type-filtered searches 500 after a HIGH-verbosity collector](#g54)

---

## JR7 jrxml + community charts

### G1
- Symptom: 400 UnrecognizedPropertyException at fill time on a `line` chart.
- Cause: a line plot does NOT accept `showTickMarks` / `showTickLabels` (those are
  bar/area/stackedbar plot props). A line plot uses `showLines` / `showShapes`.
- Fix: emit the correct plot per chart type (line -> showLines/showShapes;
  bar/area/stackedbar -> showTickMarks/showTickLabels).
- Handled-by: `scaffold_jrxml.py --chart line` emits the right plot.

### G2
- Symptom: 400 UnrecognizedPropertyException at fill time on a `pie`/`pie3d` chart
  with branded gradient slices.
- Cause: two name traps. The element is repeated `<seriesColor>` (there is NO
  `<seriesColors>` wrapper), and the index attribute is `order`, NOT `seriesOrder`.
  Either wrong name throws.
- Fix: repeated `<seriesColor order="N" color="#hex"/>` under `<plot>`. Pure jrxml,
  no customizer/jar/restart. `ORDER BY <value> DESC` so the largest slice is deepest.
- Handled-by: `scaffold_jrxml.py --chart pie` (default gradient; `--no-gradient` opts out).

### G3
- Symptom: a single-value KPI gauge deploys but returns opaque `400`s at run.
- Cause: the Pro FusionWidgets angular gauge does not fill cleanly here.
- Fix: use a JFreeChart **meter** (`shape="dial"`) instead -- a community chart that
  compiles + renders locally.
- Handled-by: `scaffold_kpi_dial.py`.

### G4
- Symptom: dial value not displayed; the dial renders as an oval, not a circle.
- Cause: the meter's `<valueDisplay>` is unreliable; a non-SQUARE element makes the
  meter an ellipse; `meterColor`/`fontSize` are element-name traps.
- Fix: SQUARE element -> perfect circle; overlay a `textField` for the value instead
  of `<valueDisplay>`.
- Handled-by: `scaffold_kpi_dial.py` bakes all three in.

### G5
- Symptom: a `bar` report fails to fill (no gradient styling).
- Cause: `--chart bar` is styled by `com.actian.jasper.GradientTrendCustomizer` by
  default; that is a Java class whose jar must be on the JRS classpath. Missing jar
  -> fill failure.
- Fix: build + copy `actian-chart-customizers.jar` into
  `...\jasperserver-pro\WEB-INF\lib\` and restart Tomcat (see SKILL.md one-time
  block). Survives restarts but NOT a JRS reinstall/upgrade. Or opt out per-report.
- Handled-by: `scaffold_jrxml.py --no-gradient` (plain flat bars, no jar needed).

### G6
- Symptom: report fails to fill after a hand-edit to the SQL.
- Cause: a `<field class=...>` no longer matches the JDBC column type.
- Fix: keep `<field class>` in sync with the column type.
- Handled-by: `scaffold_jrxml.py` sets it from introspection; only an issue on manual edits.

### G7
- Symptom: branded blue gradient / trend line not applied.
- Cause: the gradient customizer + pie seriesColor gradient apply only to `bar`
  (customizer) and `pie`/`pie3d` (seriesColor). Not bar3D / stackedbar /
  `--chart-series` multi-series.
- Fix: expected; use a supported chart type if you need the gradient.
- Handled-by: scaffolder scopes it automatically.

### G8
- Symptom: a no-query report (e.g. static barcodes) produces 0 pages.
- Cause: with no detail rows JR emits nothing.
- Fix: set `whenNoDataType="AllSectionsNoDetail"` on the root.
- Handled-by: author per the community-component recipe. (QR also needs `zxing-core`
  on the classpath.)

### G9
- Symptom: the Actian logo / a `repo:` image is missing in a local `RenderPng` preview.
- Cause: `repo:` refs resolve server-side at fill time, not in a local render.
- Fix: deploy + run-to-PDF to verify the image. The logo must exist once in the repo
  (`upload_file.ps1 ... -Type img`).
- Handled-by: branding is on by default in `scaffold_jrxml.py` (`--no-logo` / `--logo-uri`).

### G10
- Symptom: subreport fails to resolve / invalid resource.
- Cause: `--subreport` URI pointed at a reportUnit instead of a jrxml file resource.
- Fix: point it at a jrxml FILE resource (e.g. `/reports/x/rpt_files/Label_main_jrxml`
  or one uploaded with `upload_file.ps1`).
- Handled-by: caller must pass a file URI.

## Data adapters (.jrdax) and style templates (.jrtx) - strict Jackson

### G11
- Symptom: 400 UnrecognizedPropertyException at fill time for a CSV-backed report
  (NOT a clean compile error).
- Cause: JR7 parses the `.jrdax` with a strict Jackson deserializer; any unknown
  element throws. JR6-era fields like `<useConnection>` are rejected.
- Fix: only these `CsvDataAdapterImpl` elements are valid: `name, fileName, dataFile,
  fieldDelimiter, recordDelimiter, useFirstRowAsHeader, columnNames, queryExecuterMode,
  datePattern, numberPattern, encoding, timeZone, locale`.
- Handled-by: author the `.jrdax` from the verified template.

### G12
- Symptom: the style template's default style is ignored, or a generic 400 at fill.
- Cause: JR7 parses the `.jrtx` with the same strict Jackson deserializer; the
  default-style attribute is `default="true"`, NOT the 6.x `isDefault="true"`. Wrong
  name throws UnrecognizedPropertyException (surfaced as a generic 400, not a compile error).
- Fix: use `default="true"`.
- Handled-by: `scaffold_style_template.py`.

### G13
- Symptom: CSV report yields 0 rows, or fill error "Misplaced quote".
- Cause: (a) a UTF-8 BOM at the start of the CSV trips the parser; (b) `recordDelimiter`
  does not match the CSV's real line endings.
- Fix: strip the UTF-8 BOM; set `recordDelimiter` to `&#10;` for LF or `&#13;&#10;`
  for CRLF (JRS preserves it).
- Handled-by: prep the CSV before `upload_file.ps1`.

### G14
- Symptom: a report with `resourceBundle="X"` fails even though `whenResourceMissingType="Key"`.
- Cause: that attribute only covers missing keys, not a missing bundle file.
- Fix: embed the `.properties` bundle in the report unit.
- Handled-by: `deploy_report.ps1 -ResourceFiles "X.properties=path"`.

## SQL security validator

### G15
- Symptom: a report whose query starts with `WITH` (CTE) fails at fill time --
  `JSSecurityException` (`Validator.validateSQL`) surfaced as a generic 400 / error
  UID. A clean local `compile_jrxml.ps1` does NOT catch it (the CTE is valid JR/SQL).
  A 400 with an XML `errorDescriptor` body (magic `<?xml`) is the tell.
- Cause: the JRS SQL security validator requires queries to begin with `SELECT`.
  Window functions (`... over ()`) are fine; only a leading `WITH`/non-SELECT is rejected.
- Fix: push each CTE down into a nested subquery in `FROM` so the statement starts
  with `SELECT`: `WITH a AS (...), b AS (... FROM a) SELECT ... FROM b` becomes
  `SELECT ... FROM (... FROM (...) a) b`. Verify identical output in psql first.
- Handled-by: `deploy_report.ps1` lints + blocks before deploy (`-SkipSqlLint` overrides);
  `scaffold_jrxml.py` warns.

## Pro charts / maps

### G16
- Symptom: a Pro chart/map renders blank or uniform (no error).
- Cause: a component bound to the main dataset, placed in a band that fills BEFORE
  row iteration (e.g. `title`), binds zero data.
- Fix: set `evaluationTime="Report"`, or place the component in `summary`.
- Handled-by: author per the Pro recipe.

### G17
- Symptom: a Pro component (HTML5 HighCharts, FusionMaps) will not compile with the
  local JR7 jars.
- Cause: Pro components are authored in legacy 6.x jrxml; the open-source lib cannot
  compile them, and you cannot mix JR7-native with 6.x in one file.
- Fix: skip local compile -- deploy then run-to-PDF to validate (200 + non-trivial
  PDF; `.html` export contains the component markup).
- Handled-by: the whole file must be 6.x; JRS `legacy-jrxml-*` modules convert at fill.

## Dashboards

### G18
- Symptom: a hand-built dashboard PUT to `/rest_v2/resources` stores `201` but never
  renders (frames spin forever; designer shows it empty) -- even when the model is
  byte-equivalent to a working one.
- Cause: the JRS 10 client needs extra broker work the designer/import does on save;
  a raw PUT skips it.
- Fix: do NOT PUT. Use the import path: synthesize companion files, inject into a real
  designer-shaped export envelope, re-zip, and import.
- Handled-by: `compose_dashboard.ps1` / `build_dashlets.ps1 -Compose`.

### G19
- Symptom: `ExtractToDirectory: the given path's format is not supported`.
- Cause: an absolute `-WorkDir` was joined with `Get-Location` unconditionally,
  producing an invalid `C:\cwd\C:\abs` path.
- Fix: pass an absolute `-WorkDir` (now honored); needed when CWD is not writable
  (e.g. the web wizard runs from the Tomcat temp dir).
- Handled-by: `compose_dashboard.ps1 -WorkDir <abs>` (fixed).

### G20
- Symptom: recompose over an existing dashboard silently keeps the OLD layout.
- Cause: JRS import will not overwrite an existing dashboard's companion files
  (`layout`/`components`/`wiring`).
- Fix: delete the target dashboard before importing (also frees dashlet
  `resource.in.use` locks).
- Handled-by: `compose_dashboard.ps1` deletes first by default (`-KeepExisting` to skip);
  `build_dashlets.ps1 -Compose` inherits it.

### G21
- Symptom: 403 `resource.in.use` (naming the owning dashboard) when re-deploying a
  report that is already a dashlet.
- Cause: a dashlet report is modification-locked by its owning dashboard (delete or
  `?overwrite=true` PUT alike).
- Fix: delete/recreate the owning dashboard (or compose under a new name) to push
  report changes. An in-place `?overwrite=true` update dodges delete-protection on
  referenced resources.
- Handled-by: `deploy_report.ps1 -Overwrite` updates in place (no delete);
  `build_dashlets.ps1` treats 403 as "in-use (kept)", not a failure;
  `teardown_dashboard.ps1` deletes the dashboard first.

### G22
- Symptom: imported dashboard archive is a silent no-op.
- Cause: the Java importer ignores back-slash zip entry paths.
- Fix: re-zip with forward-slash entries and point `index.xml`'s
  `repositoryResources` at the dashboard.
- Handled-by: `compose_dashboard.ps1`.

### G23
- Symptom: a recompose reverts hand-edits made in the JRS designer.
- Cause: the compose manifest is stale relative to the live (rearranged) dashboard.
- Fix: re-derive the manifest from the live dashboard before recomposing.
- Handled-by: `sync_manifest_from_dashboard.ps1 -Uri <dash> -Out <manifest.json>`.

### G24
- Symptom: opening a dashboard URL errors "No flow definition found".
- Cause: there is no `dashboardRuntimeFlow`; a dashboard is not a `flow.html` flow.
- Fix: use the HTML5 viewer with the URI in the URL-encoded hash fragment:
  `.../dashboard/viewer.html#%2Freports%2F...`.
- Handled-by: N/A (use the right URL).

## Export / import

### G25
- Symptom: 405 on `GET /rest_v2/export/{id}`.
- Cause: the export download endpoint is `/exportFile`, not the bare id.
- Fix: download from `/rest_v2/export/{id}/exportFile` (after polling
  `/rest_v2/export/{id}/state` to `phase=finished`).
- Handled-by: `export_resource.ps1`.

### G26
- Symptom: an ad hoc view JSON PUT fails `500 "bytes is null"`.
- Cause: an `adhocDataView` carries a large opaque `query.multiAxis`/`component`
  state plus a companion binary; a raw JSON PUT cannot reconstruct it (same
  don't-PUT lesson as dashboards).
- Fix: use the export/import envelope (carries the view plus its backing Topic/Domain).
- Handled-by: `manage_adhoc.ps1 -Action export|import` (wraps `export_resource.ps1`/`import_resource.ps1`).

## Datasources

### G27
- Symptom: the datasource list looks empty / returns `204` ("no datasources").
- Cause: querying `type=dataSource` returns 204/empty on this server.
- Fix: use `type=jdbcDataSource`:
  `.../rest_v2/resources?type=jdbcDataSource&recursive=true`.
- Handled-by: caller must use the right type token.

### G28
- Symptom: AWS datasource create `400` "invalid Region".
- Cause: `-Region` is the AWS endpoint HOST, not the bare region code.
- Fix: pass `us-east-1.amazonaws.com` (or `eu-west-1.amazonaws.com`), NOT `us-east-1`.
- Handled-by: `create_datasource.ps1 -Type aws -Region <host>` (default
  `us-east-1.amazonaws.com`).

### G29
- Symptom: a non-JDBC datasource created `201` but cannot actually connect.
- Cause: create only validates the descriptor shape and stores the resource;
  connecting needs the server-side prerequisite (a JNDI resource, a Spring bean on
  the classpath, a custom data-source service, the referenced sub-datasources, or
  live AWS creds).
- Fix: provision the server-side prerequisite separately.
- Handled-by: `create_datasource.ps1 -Type jndi|bean|custom|virtual|aws` (descriptor only).

## Domains / OLAP

### G30
- Symptom: Domain create fails `500 resource.does.not.exist`.
- Cause: a pre-uploaded `schemaFileReference` is used; the `_files` child is orphaned
  until the parent exists.
- Fix: embed the schema INLINE in the descriptor (`schema.schemaFile.content` base64,
  like a reportUnit's jrxml).
- Handled-by: `create_domain.ps1` (schema materializes at `<Uri>_files/schema.xml`).
  Note: a Mondrian schema is the opposite -- standalone/referenced, not embedded.

### G31
- Symptom: Domain metadata wrong / does not behave like the sample Domains.
- Cause: the schema's `<jdbcTable datasourceId="...">` does not equal the LEAF of
  `-DataSourceUri`.
- Fix: pass the datasource leaf as `--datasource-id`.
- Handled-by: `scaffold_domain_schema.py` / `create_domain.ps1` (warns on mismatch).

### G32
- Symptom: `olapUnit` analysis view fails `500` on create (schema + connection are fine).
- Cause: creating the view OPENS the connection and validates the MDX against the
  live cube; it 500s unless tables/columns match.
- Fix: best-effort -- the schema + connection are still left in place. Fix the schema
  to match the backing DB if you need the view.
- Handled-by: `create_mondrian.ps1` warns and continues.

### G32b
- Symptom: multi-table Domain create fails
  `400 domain.schema.presentation.element.name.not.unique` naming a column.
- Cause: `<item id>`s must be GLOBALLY unique across ALL itemGroups, and a join
  key by definition appears in two tables.
- Fix: dedupe designer-style -- keep the first occurrence plain, suffix later
  ones `_1`, `_2`, ... (the label can stay the plain column name).
- Handled-by: `scaffold_domain_schema.py` (multi-table mode dedupes item ids).

## REST / PowerShell 5.1 / curl

### G33
- Symptom: re-deploying an existing report fails `409 versions not match`.
- Cause: optimistic locking.
- Fix: `-Overwrite` (now updates in place via `?overwrite=true`, no delete).
- Handled-by: `deploy_report.ps1 -Overwrite`.

### G34
- Symptom: an async report-execution POST fails `400 serialization.error`.
- Cause: on Windows an inline `-d '{...}'` gets its quotes mangled by PowerShell/curl.
- Fix: write the JSON to a file and pass `--data "@req.json"`.
- Handled-by: `run_report_async.ps1` / `schedule_job.ps1` / `manage_alert.ps1` all
  pass the body from a file.

### G35
- Symptom: an attribute call `405`s; the base URL is silently dropped.
- Cause: PowerShell 5.1 treats `?` as a variable-name char, so `"$base?name"`
  evaluates `$base?name` (undefined) and drops `$base`.
- Fix: build the path with braces: `"${base}?name=..."`.
- Handled-by: `manage_attributes.ps1`.

### G36
- Symptom: a server attribute write wipes all ~134 system attributes.
- Cause: a bare `PUT /attributes` REPLACES the whole set.
- Fix: always scope the server call with `?name=`.
- Handled-by: `manage_attributes.ps1` (always name-scoped at server scope).

### G37
- Symptom: PowerShell drops the database-name argument to `create_datasource.ps1`.
- Cause: `-Db` is a reserved alias of `-Debug`.
- Fix: use `-Database`.
- Handled-by: `create_datasource.ps1 -Database`.

### G38
- Symptom: PowerShell eats Maven/Java `-D...` args.
- Cause: PS parses `-D...` as its own switches.
- Fix: put them after the `--%` stop-parsing token.
- Handled-by: N/A (caller convention).

### G39
- Symptom: a wrapper script aborts on a clean (exit 0) compile/render.
- Cause: the SLF4J "No providers" line goes to stderr; under
  `$ErrorActionPreference="Stop"` that aborts the wrapper.
- Fix: invoke `java` directly, or check the `.jasper`/`.png` output rather than the
  pipeline error state.
- Handled-by: the shared `Invoke-JrCompile` helper absorbs SLF4J-on-stderr.

### G40
- Symptom: a large report times out on the synchronous `/reports/{uri}.{fmt}` endpoint.
- Cause: the sync endpoint blocks until the fill finishes.
- Fix: use the async `reportExecutions` service (submit -> poll `.../status` until
  `ready` -> download `.../outputResource`; `exportId` from
  `GET .../reportExecutions/{rid}` -> `exports[0].id`).
- Handled-by: `run_report_async.ps1`.

### G41
- Symptom: a `/Type /Page` grep reads 0 on a perfectly good PDF.
- Cause: the PDF page tree is usually compressed.
- Fix: verify by HTTP `200` + correct magic bytes (`%PDF-`, or `PK` for Office/OD
  zip formats) + a non-trivial byte size, not by counting page objects.
- Handled-by: `verify_report.ps1` / `build_dashlets.ps1` verify this way.

## File upload

### G42
- Symptom: an uploaded image (logo) does not resolve via `repo:`.
- Cause: it was uploaded with Type `png`/`jpg` instead of `img`.
- Fix: upload images with `Type img`.
- Handled-by: `upload_file.ps1 -Type img`.

## Permissions / attributes / admin

### G43
- Symptom: setting permissions returns `415`.
- Cause: `Content-Type: application/collection.permission+json` is rejected.
- Fix: use `Content-Type: application/collection+json`. Masks: 1=administer,
  2=read+delete, 18=read+write, 30=read-only, 32=execute-only.
- Handled-by: `manage_permissions.ps1`.

### G44
- Symptom: `manage_users.ps1` auth fails (401) or sets the wrong password.
- Cause: `-Password` is the NEW user's initial password, not the JRS auth password.
- Fix: pass the JRS auth password as `-JrsPassword`.
- Handled-by: `manage_users.ps1`.

### G45
- Symptom: creating an organization with `PUT {id}` does not work as expected.
- Cause: org create is a POST on the collection
  (`/rest_v2/organizations?createDefaultUsers=true`, WADL id `putOrganization`).
- Fix: POST to create; `update` is a read-modify-write `PUT {id}` (so setting
  `-Theme` does not blank other fields).
- Handled-by: `manage_organizations.ps1`.

## Reports: alerts, options, run

### G46
- Symptom: alert create fails `400`.
- Cause: two shape traps -- `mailNotification.toAddresses` must be a wrapper object
  `{address:[...]}` (NOT a bare array, unlike jobs); and `baseOutputFilename` is
  required even for an email-only alert.
- Fix: use the wrapper object and always set `baseOutputFilename`.
- Handled-by: `manage_alert.ps1`.

### G47
- Symptom: a saved report option's input-control values are not applied.
- Cause: a `?reportOptions=<id>` query on the report URL does NOT apply them.
- Fix: run the option's OWN sibling URI as a report:
  `GET /reports/<folder>/<id>.pdf`.
- Handled-by: `manage_options.ps1 -Action run`.

### G48
- Symptom: a JR Library sample deploys + runs (200 + valid PDF) but renders blank.
- Cause: many samples rely on parameters the Java harness supplies (e.g.
  `MaxOrderID`); with no default they fill empty. (A 200 + valid PDF only means it
  ran, not that it has content.)
- Fix: pass params at run time (`...PieChartReport.pdf?MaxOrderID=11077`) or bake in
  defaults.
- Handled-by: `report\inject_chart_defaults.py` injects `<defaultValueExpression>`.

## Collateral docs (Word COM)

### G49
- Symptom: `make_docx.ps1` fails on a relative path, saves the wrong format, or
  PowerShell will not parse an inline conditional as a method arg.
- Cause: Word COM requires absolute paths; the SaveAs format codes are 16=`.docx`,
  17=`.pdf`; PowerShell 5.1 will not parse an inline `(if ... {} else {})` as a
  method argument.
- Fix: resolve paths to absolute; use codes 16/17; assign a conditional to a variable
  first. The script also releases the COM object in a `finally` block so a failed run
  leaves no orphaned `WINWORD.EXE`.
- Handled-by: `make_docx.ps1`.

## Environment

### G50
- Symptom: every path `401`s.
- Cause: targeting port 8080, an unrelated Bearer-token-gated Java service.
- Fix: target `http://localhost:8081/jasperserver-pro` (REST v2, HTTP Basic,
  `superuser` with the password from `jrs.config.json` -- not the default).
- Handled-by: credential resolution defaults to 8081.

### G51
- Symptom: every call `401`s on the RIGHT server with the RIGHT password --
  even `GET /rest_v2/serverInfo` -- when the same credentials worked minutes
  earlier.
- Cause: JRS account lockout. 10 failed logins disable the account
  (`jiuser.enabled = false`); a client retrying with a STALE password (the
  classic culprit: a deployed jasper-wizard WAR whose `web.xml` still holds the
  old `jrsPass` after a password change, failing once per proxied request)
  burns through the 10 in seconds. The lockout does NOT auto-expire, and no
  org admin can re-enable the root `superuser` via REST.
- Fix: re-enable directly in the repo metadata DB (**:5433**, not the :5432
  decoy): `UPDATE jiuser SET enabled=true, numberoffailedloginattempts=0
  WHERE username='superuser';` -- then fix the stale-credential client.
- Handled-by: `webapp/jasper-wizard/build.ps1` patches the assembled
  `web.xml`'s JRS connection from the skill's gitignored `jrs.config.json` at
  build time, so a rebuilt wizard always matches the local server creds; the
  smoke test's `wizard-api` step catches the drift before it can lock the
  account.

### G52
- Symptom: `POST /rest_v2/contexts` (datasource connection test) fails `415
  Unsupported Media Type`.
- Cause: guessing a `application/connections.jdbc+json` content type. The
  contexts service wants the descriptor's OWN repository media type.
- Fix: `Content-Type: application/repository.jdbcDataSource+json` (or
  `...jndiJdbcDataSource+json` / `...customDataSource+json`). Then 201 = the
  server-side connection actually opened; 400 `connection.failed` carries the
  driver's real error.
- Handled-by: `Invoke-JrsConnectionTest` (`_jrs_common.ps1`) /
  `create_datasource.ps1 -Test` / doctor's "JRS->DB connection" check.

### G53
- Symptom: diagnostic collectors vanish after a "delete one" call; or the
  downloaded collector zip's log will not open; or creating a collector 400s
  with a `validateName` stack trace.
- Cause: three sharp edges of `/rest_v2/diagnostic/collectors`: (1) a DELETE on
  the bare collection (no id) deletes ALL collectors (same family as G36's
  PUT-/attributes wipe); (2) the zip's `diagnostic.log.jsEncrypted` is
  encrypted with the server key -- intended for Jaspersoft support, only
  `collectorSettings.xml` is plaintext; (3) collector names must be unique
  among live collectors.
- Fix: always delete by id (`-Id`); treat the zip as a support bundle; use a
  fresh name per run.
- Handled-by: `manage_diagnostic.ps1` (requires `-Id` unless `-All`; notes the
  encryption; documents the name rule).

### G54
- Symptom: every type-filtered repository search
  (`resources?type=jdbcDataSource`, `jndiJdbcDataSource`, ...) suddenly `500`s
  with `ClassCastException: Cannot cast RepoJdbcDataSource to
  RepoResourceItemBase` -- single GETs and `q=` text search still work, the
  wizard's datasource list breaks, and clearing caches via
  `DELETE /caches/{id}` does nothing.
- Cause: a diagnostic collector started at **verbosity HIGH** (JRS 10.0.0
  server bug). Bisected live: the search breaks the moment the HIGH collector
  STARTS and stays broken after stop/delete; a full LOW-verbosity lifecycle
  (start->stop->download->delete) is clean.
- Fix: restart Tomcat (only cure), and use `LOW` verbosity for collectors.
- Handled-by: `manage_diagnostic.ps1` defaults to `LOW` and warns on `HIGH`;
  the smoke's `diagnostic` step runs the LOW lifecycle.
