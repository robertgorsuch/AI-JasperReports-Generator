# Dashboards — compose, author, promote, teardown

Deep reference for JRS dashboards. The dashboard *model shapes* (descriptor +
companion files) are in `references/dashboard-model.md`; this file is the
*workflow*. `$skill` = the skill's `scripts/` dir.

## Fully scripted: compose a dashboard of report dashlets — `build_dashlets.ps1`
Drives the **entire** dashboard pipeline from one JSON manifest — no designer
needed for a dashboard whose tiles are deployed reports (each a tabular report
with a chart in its summary band):
```powershell
$env:PGPASSWORD = "postgres"
& $skill\build_dashlets.ps1 -Manifest report\foodmart\dashboard.json -Compose
```
For each `dashlets[]` entry it **scaffolds → compiles → deploys → verifies** (runs
to PDF, asserts `200` + `%PDF-` + non-trivial size), prints a results table, then
with **`-Compose`** assembles them into the dashboard. **Verified end-to-end**
building the 7-tile `foodmart_kpi_dashboard_auto`. The unified manifest carries
both the build spec and the grid layout:
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
and **ad hoc views** stay designer-authored — see below.)

## How the compose step works (and why it renders, unlike a raw PUT)
A JRS dashboard is a descriptor + three companion files (`components` = the
dashlet frames + a `DashboardProperties` singleton, `layout` = the `<div
data-componentId data-x data-y data-width data-height>` grid, `wiring` =
`@init`→`@refresh` / `@applyParams` events). `gen_dashboard.py` synthesizes all
four from the manifest (the model shape is reverse-engineered from a real
designer export; `id` = `re.sub('[^0-9A-Za-z]','_', label)`).
`compose_dashboard.ps1` then: exports the already-deployed dashlet reports (→ a
real, importable envelope: reportUnit descriptors + jrxml, datasource, folder
chain, valid `index.xml`), **injects** the synthesized dashboard into it, points
`index.xml`'s `repositoryResources` at the dashboard, re-zips with
**forward-slash** entries (the Java importer ignores back-slash paths — a silent
no-op), and **imports** it. Because the archive is structurally identical to a
designer export, the imported dashboard **renders** — verified by a clean
re-export round-trip (a broken import cannot be re-exported) and the HTML5 viewer.

> **Why import, not PUT?** You *can* PUT a hand-built dashboard model straight to
> `/rest_v2/resources` and the server stores it (201) — but the JRS 10 client
> **silently won't render it** (frames spin forever; the designer shows it empty),
> even when the stored model is byte-for-byte equivalent to a working one. The
> designer/import broker does extra work on save that a raw PUT skips. The
> **import** path reproduces that work, so it renders. Don't PUT.

`compose_dashboard.ps1 -WorkDir` accepts an **absolute** path (defaults to the
relative `out\dash_build`). Earlier it joined the work dir with `Get-Location`
unconditionally, so an absolute `-WorkDir` produced an invalid `C:\cwd\C:\abs`
path and `ExtractToDirectory` threw "the given path's format is not supported";
that's fixed — pass an absolute `-WorkDir` when the caller's CWD isn't writable
(e.g. the web wizard runs it from the Tomcat temp dir).

## Gotcha — `resource.in.use` (403)
A report that is already a dashlet of an **existing** dashboard is
modification-locked by JRS: re-deploying it (delete or `?overwrite=true` PUT
alike) returns `403 resource.in.use` naming the owning dashboard.
`build_dashlets.ps1` treats this as **"in-use (kept)"** — not a failure — leaves
the deployed version in place, still verifies it renders, and continues to
compose. To actually push report changes, delete/recreate the owning dashboard
(or compose under a new name) first. `deploy_report.ps1 -Overwrite` updates **in
place** via `?overwrite=true` (no delete), which also dodges the delete-protection
on referenced resources.

## Author in the designer; promote via export/import
For dashboards with non-report tiles (ad hoc views, filter groups, text/input
controls) authoring is still a manual designer step:
1. Author once in the **designer**, dragging in already-deployed reports / ad hoc
   views, then Save:
   `http://localhost:8081/jasperserver-pro/dashboard/designer.html`
   (open an existing one at `dashboard/designer.html#<url-encoded uri>`).
2. **Version-control / back up / promote** it with the REST v2 export+import
   service (the archive is the designer's own output, so it re-imports and renders
   identically — ideal for dev→prod promotion across servers):
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
**Verified:** round-trip export+import of the `1._Supermart_Dashboard` sample, and
a **destructive** round-trip of `5._Top_Performers` — export → DELETE the
dashboard (`resource.not.found`) → import → the full component model is restored
intact (all frames: charts, text dashlet, filter group, input control; plus the
embedded ad hoc views, `layout` and `wiring`). The export archive holds the
dashboard `.xml` descriptor + `_files/{components.data,layout,wiring.data}` + each
embedded ad hoc view.

## Promote dev→prod — `promote.ps1`
`promote.ps1 -Uri <uri> -ToServerUrl … -ToUser … -ToPassword …` exports from the
source (this skill's config by default, or `-From*`) and imports into the target
server in one step (a folder URI promotes a whole app).

## Teardown — `teardown_dashboard.ps1`
`teardown_dashboard.ps1 -Uri <dash> [-IncludeReports] [-DryRun]` deletes the
dashboard first (releasing the `resource.in.use` locks), then its report tiles +
`<report>_controls` folders; a report still used by another dashboard is skipped,
not half-deleted.

## View a dashboard
Use the HTML5 viewer (NOT a `flow.html` flow — there is no `dashboardRuntimeFlow`;
that errors "No flow definition found"). The resource URI goes in the
**URL-encoded hash fragment**:
`http://localhost:8081/jasperserver-pro/dashboard/viewer.html#%2Freports%2Fgeocoder%2Fsales_dashboard`

## Scope summary
A dashboard of **report dashlets** is fully scripted (`build_dashlets.ps1
-Compose`). Export/import additionally promotes/versions *any* dashboard across
servers. **Ad hoc views** and **Domains** have their own scripted lifecycle (see
data-and-semantic-layer.md): single-table Domains are scaffolded + created
outright, and ad hoc views are listed/inspected/exported/imported. The remaining
manual step is authoring dashboards whose tiles are **filter groups / input
controls** drawn in the designer. Everything else — reports, their embedded
charts, report-tile dashboards, style templates, datasources, domains, and
themes — is scripted.
