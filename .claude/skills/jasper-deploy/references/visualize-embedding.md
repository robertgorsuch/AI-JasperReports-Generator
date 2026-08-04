# Embedding a JRS report or dashboard with Visualize.js

Visualize.js is JasperReports Server's JavaScript API for embedding a deployed
report or dashboard into an external web page. This is the "what next" after a
report is deployed: instead of linking users to the JRS UI, you render the
artifact inside your own app's DOM. **Verified end-to-end on this server** (see
the recipe in `references/jrs-rest-api.md`, "Embedding -- Visualize.js").

## One-command scaffold
`scaffold_visualize_embed.py` emits the verified host page below, ready to open:
```powershell
python $skill\scaffold_visualize_embed.py --uri /reports/geocoder/county_summary --out embed.html
python $skill\scaffold_visualize_embed.py --uri /reports/foodmart/dash --type dashboard --out d.html
# then serve it from OUTSIDE the JRS webapp:  python -m http.server 8000
```
Server + user default from `jrs.config.json`; the password is deliberately the
`CHANGE_ME` placeholder (the auth block is clear text in the page -- pass
`--password` only for throwaway demos, never commit a page with a real secret).
The page sets `window.__embedOk = true` in the `success` callback, matching the
headless-verification recipe at the bottom of this file.

## The script include
Load the library from the running server (it serves **anonymously**, ~126 KB --
do NOT send it HTTP Basic creds or the form-auth filter will `302` it to login):
```html
<script src="http://localhost:8081/jasperserver-pro/client/visualize.js"></script>
```

## Minimal host page (authenticate + run a report into a div)
Serve this from any plain web server (see the cross-origin note below). It logs
in cross-origin via the `auth` block, then renders a deployed report into
`#container`:
```html
<!doctype html>
<html>
<head>
  <script src="http://localhost:8081/jasperserver-pro/client/visualize.js"></script>
</head>
<body>
  <div id="container" style="width:900px;height:600px;"></div>
  <script>
    visualize({
      server: "http://localhost:8081/jasperserver-pro",
      auth:   { name: "superuser", password: "superuser" }
    }, function (v) {
      v.report({
        resource:  "/reports/geocoder/county_summary",
        container: "#container",
        error:     function (e) { console.error(e); }
      });
    });
  </script>
</body>
</html>
```
For a dashboard, swap `v.report(...)` for `v.dashboard({ resource: "...",
container: "#container" })`. Other entry points: `v.inputControls(...)`,
`v.resourcesSearch(...)`. JRS 7.9+ auto-generates this embed snippet from the
repository UI (the resource's "Embed" action), so you can copy a working block
from there too.

## CRITICAL: cross-origin configuration
1. **Serve the host page from OUTSIDE the JRS webapp.** Everything under
   `.../jasperserver-pro/` sits behind the auth filter, so a page dropped inside
   the webapp just `302`-redirects to the login screen before your JS runs. Put
   the page on a separate origin (e.g. `python -m http.server 8000`) and let the
   `auth` block log in cross-origin.
2. **Cross-origin needs CORS, controlled by the server `domainWhitelist`
   setting.** When your page's origin is allowed, the server returns
   `Access-Control-Allow-Origin: <your origin>` and the embed works. On this
   install `domainWhitelist` is `*` (so any origin is echoed back). For
   production, tighten it to the specific origins that may embed. It is a JRS
   server attribute (configured in `WEB-INF/js.config.properties` /
   `applicationContext-security-web.xml`'s domain whitelist, or via the
   attributes UI) -- not something the page can set.
3. **Do not send `Authorization: Basic ...` when fetching `visualize.js`
   itself** -- request it with no auth header (the page does this implicitly).

## Verifying a render headlessly
Chrome `--screenshot --virtual-time-budget` fires *before* the async fill
finishes, so you capture Visualize's own "Loading..." instead of the report. Use
Playwright (`channel="chrome"`, no chromium download) with `wait_for_function` on
a success flag set in the report's `success` callback, then screenshot. This is
how the cross-origin render was verified on this server.

## Cross-references
- `references/jrs-rest-api.md` ("Embedding -- Visualize.js") -- the original
  verified recipe, the full gotcha list, and the `v.*` entry points.
- `SKILL.md` -- deploying the report/dashboard that you then embed.

---

# API surface (10.1 guide, doc-only)

Everything below is distilled from the official JasperReports Server 10.1
Visualize.js guide (`docs/js-jrs_10.1.0_visualize.js-guide.pdf`); page numbers
cite that PDF. It is [doc-only]: NOT re-verified on the local server. Where it
touches the same ground as the [verified] recipe above, the recipe wins.

## visualize() entry point
Signature: `visualize(properties, callback, errorback, always)` (p.8). The
`errorback` (3rd arg) catches all initialization + authentication errors
(p.141). Alternative promise-ish form (p.10):
```js
visualize({ server: "...", auth: {...} }).always(function (err, v) {
  if (err) { alert(err.message); return; }
  v.report({...});
});
```
Script URL query params (p.8): `userLocale` (locale for display + report
execution), `logEnabled` (default true), `logLevel` (debug|info|warn|error,
default error), `baseUrl` (JRS instance answering visualize requests; defaults
to the server that served the script). Example:
`.../client/visualize.js?userLocale=fr&logLevel=debug`

Share one auth block across several `visualize()` calls with
`visualize.config({ auth: {...} })` (p.29). The client `v` exposes: `report`,
`dashboard`, `adhocView`, `inputControls`, `resourcesSearch`, `login`,
`logout` (p.9).

## Authentication
`auth` properties (p.20-22): `name`, `password`, `organization` (multi-tenant
only), `locale`, `timezone`, `token` (SSO -- if present all other fields are
ignored), `preAuth` (bool; when true the auth request goes to the base JRS URL
instead of `{baseUrl}/j_spring_security_check`), `tokenName` (override the SSO
token parameter name), `loginFn` / `logoutFn` (custom functions; each gets
`(properties, request)` and must return a deferred -- `request` only works
against the JRS domain, p.26).

Token pass-through / pre-auth example (p.25):
```js
var t = encodeURIComponent("u=John|r=Ext_User|o=organization_1|pa1=USA");
visualize({ auth: { token: t, preAuth: true, tokenName: "pp" } },
  function (v) { /* ... */ });
```
- `v.login(authObj)` / `v.logout()` manage sessions after init; `logout()`
  drops the JRS session (this is the "destroy session" call -- there is no
  separate destroySession function) (p.22-25). With SSO tokens attach logout
  UI feedback to `.always()`, not `.done()` (p.28).
- Session reuse: Visualize.js rides the same `JSESSIONID` cookie as the JRS
  web UI, so a browser already logged in (UI or prior REST auth) can call
  `visualize(function (v) {...})` with NO auth block at all (p.30).

## v.report()
Properties (p.40-43; `server` + `resource` required):
- `resource` (repo URI), `container` (CSS selector or DOM element; must not be
  or contain a `<script>` element, p.43), `params` (object; every value is an
  ARRAY of quoted strings), `pages` (int | "4" | "4-6" | `{pages, anchor}`).
- `scale`: number > 0 (1 = 100%) or "container" (default) | "width" |
  "height" (p.41, semantics p.57-58).
- `defaultJiveUi.enabled` (default true) -- interactive JIVE toolbar;
  `isolateDom` (default false) -- render in an iframe. Mutually exclusive
  with JIVE (see errors below).
- `linkOptions` (`beforeRender` fn + Backbone-like `events`), `ignorePagination`
  (default false), `autoresize` (default true), `chart.animation`,
  `chart.zoom` (false|"x"|"y"|"xy", Highcharts-based charts only),
  `loadingOverlay` (default true), `scrollToTop` (default true),
  `showAdhocChartTitle` (default true).
- `reportContainerWidth` -- passed to execution as the built-in
  REPORT_CONTAINER_WIDTH parameter for responsive reports (p.58).
- `runImmediately: false` -- construct without executing (used with
  `refresh()`/`run()` later, p.67).

Methods (p.44-49; all return a deferred, setters chain): `run()`, `render()`,
`refresh()`, `cancel()`, `export(opts)`, `destroy()`, `resize()`,
`search(query)` (text search across pages), `save()` / `save(opts)` (persist
JIVE state, optionally as a new report with `{folderUri, label, description,
overwrite}`), `undo()`, `undoAll()`, `redo()`, `updateComponent(...)` (JIVE),
`events({...})`, `data()`, plus getter/setters `params()`, `pages()`,
`scale()`. Common re-run pattern: `report.pages(5).run()`.

`data()` after a successful run returns report metadata, not rows (p.49):
`totalPages`, `links` (hyperlinks on the requested pages), `bookmarks`,
`reportParts`.

Events (`events:` property, p.146-150):
- `reportCompleted(status)` -- fired when the report finishes rendering.
- `changeTotalPages(totalPages)` -- fires as the server fills pages; good
  place to hide a spinner (p.68, p.148).
- `pageFinal(el)` -- last page has been generated (p.148).
- `beforeRender(el)` -- mutate the report DOM before display (p.149).
- `responsiveBreakpointChanged` -- container width crossed a breakpoint;
  destroy + re-create the report with a new `reportContainerWidth` (p.147).

### Params: array rule and special values (p.102)
Every parameter value is an array of quoted strings, even single-value,
boolean, numeric, or date inputs: `params: { Country: ["USA"] }`. Special
values: `""` (empty string), `"~NULL~"` (matches NULL), `"~NOTHING~"` (no
selection: all-selected for multi-select, `---` for single-select optional,
default value for single-select mandatory). `report.params({}).run()` resets
to defaults. (Documented for dashboards; same convention applies to reports.)

### Export (p.62-66)
Call `export` only AFTER `run()` completes. Formats: pdf, xlsx, rtf, csv,
xml, odt, ods, docx, json, pptx (p.62). HTML export is not available.
```js
report.run(function () {
  report.export({ outputFormat: "pdf", pages: "1-10" })
    .done(function (link) { window.open(link.href); })
    .fail(function (err) { alert(err.message); });
});
```
`pages` also accepts `{anchor: "summary"}` for a partial export (p.63). For
raw data use csv/json: the `.done(function (link, request) {...})` callback
gets a `request` function -- call `request({dataType: "json"})` to fetch the
payload directly into JS (p.65-66). Discover legal values at runtime from
`v.report.exportFormats`, `v.report.chart.types`,
`v.report.table.column.types` (p.69).

### Cancel / refresh (p.66-68)
`report.cancel()` stops a long-running execution (deferred resolves when
canceled). `report.refresh()` re-executes with current properties.
`report.destroy()` cancels everything and frees the container for reuse.

### Container sizing rules (p.57-59)
Default `scale:"container"` fits the report fully inside the container (both
dimensions; letterboxes on aspect mismatch). `"width"` / `"height"` fit one
dimension and scroll the other; numeric scale is a zoom factor. Aspect ratio
is always preserved. With `autoresize:false` you control size manually:
resize the container then call `report.resize()`. Give the container explicit
CSS width/height (the verified page uses 900x600 inline styles).

## Hyperlinks and drill-down (p.151-157)
Each link object: `id`, `type` (LocalPage, LocalAnchor, RemotePage,
RemoteAnchor, Reference, ReportExecution, AdHocExecution, or custom),
`target` (Self, Blank, Top, Parent, frame name), `tooltip`, `href`,
`parameters`, `resource`, `pages`, `anchor` (p.151-152). ReportExecution
links carry drill-through params `_report`, `_anchor`, `_page`, `_output`
(p.109).

`linkOptions.beforeRender(linkToElemPairs)` styles link elements before
display; `linkOptions.events.click(ev, link)` intercepts clicks. Verified
drill-down-in-second-container pattern from the guide (p.154):
```js
linkOptions: {
  events: {
    click: function (ev, link) {
      if (link.type == "ReportExecution") {
        v("#drill-down").report({
          resource: link.parameters._report,
          params: { city: [link.parameters.city] }
        });
      }
    }
  }
}
```
After a successful run, `data().links` exposes all links (with tooltips set
in the JRXML) for building custom navigation (p.156).

## v.dashboard()
Properties (p.88-90; `server` + `resource` required): `resource`, `container`,
`params` (same array-of-strings rule), `linkOptions` (same shape as report),
`report.chart.animation` / `report.chart.zoom` and `report.loadingOverlay`
(options for reports inside the dashboard), `runImmediately` (p.100).

Methods (p.91-94): `run()`, `render()`, `refresh()` or `refresh(id)` (whole
dashboard or one dashlet by component id), `cancel()` / `cancel(id)`,
`updateComponent(id, props)` (also batch array form), `destroy()`, `data()`,
`params()`. `dashboard.data().parameters` lists available input controls
(dashboard ICs are called "parameters"; the server renders their UI panel
inside the dashboard automatically, p.101). Set programmatically:
`dashboard.params({ month: ["2"] }).run()` (p.102); `params({})` resets all
to defaults.

Events: `dashboardCompleted` fires when rendering finishes (p.100). Refresh
can be raced with cancel: keep the deferred from `refresh()` and call
`dashboard.cancel()` if still `"pending"` after a timeout (p.100).

Export (p.113): `export({outputFormat: ..., detailed: ...})`, only after run
succeeds. Screenshot exports: pdf, png, docx, pptx, odt. Detailed exports:
pdf, xlsx, csv, docx, rtf, odt, ods, xlsx, pptx. Give the container explicit
width/height (guide example uses 1110x630 px). `dashboard.destroy()` closes
the dashboard and frees resources (p.117). Note: dashlet chart-type changes
users make in an embedded dashboard are session-only and cannot be saved
(p.99).

## v.adhocView()
Renders the table/crosstab/chart of a saved Ad Hoc view (JRS 7.0+); design
panels and filter panels are not rendered (p.118). Properties (p.118-121):
`resource`, `container`, `autoresize` (default true), `canvas.type` (switch
visualization: Table, Crosstab, Bar, Column, Line, Area, Pie, HeatMap,
TreeMap, Scatter, Bubble, many Stacked*/TimeSeries*/MultiAxis* variants),
`params` (filters, array-of-strings), `loadingOverlay`, `showTitle` (default
true), `linkOptions`. Methods (p.121-122): `run()`, `render()`, `refresh()`,
`destroy()`, `data()`. `data().metadata` lists
`availableVisualizationTypes`, `inputParameters` (usable as filter names) and
`outputParameters` (fields exposed in AdHocExecution hyperlinks) (p.122-124).

## v.inputControls() -- custom control UIs
Properties (p.71-72): `server`, `resource` (required), `container`, `params`.
Two modes:
1. Server-rendered widgets: give `resource` + `container` and the server emits
   the whole IC panel; restyle via CSS classes like `.jr-mInput-boolean-label`
   scoped under your container id (p.74, p.13).
2. Custom UI: omit the container rendering and read `data()` -- an array of
   control objects with `id`, `label`, `type` (e.g. singleSelect), `mandatory`,
   `readOnly`, `visible`, `masterDependencies` / `slaveDependencies`
   (cascading), `validationRules`, and `state.options`
   (`{selected,label,value}`) to build your own widgets (p.82-84).

Methods (p.72-73): `resource()`, `params()`, `events({...})`, `reset()`,
`run()`. The `change` event fires when the user edits a value:
`change: function (params, error)` -- standard pattern is
`report.params(params).run()` when `error` is falsy (p.77). The second arg
doubles as the server-side validation result (p.78). Run-button pattern: read
`inputControls.data().parameters` and feed it to `report.params(...).run()`
(p.75-76). ICs from one report can drive another report if both share the
same data source or Domain (p.76). Cascading customs: listen for change on
the parent control and re-run to update dependents (p.85).

## Theming and styling embedded content (p.12-13)
- Report/dashboard appearance itself comes from the JRXML / dashboard design.
- Server-generated UI widgets (IC panels, JIVE) carry server-emitted CSS
  classes: override them in YOUR app's CSS, scoped under your container id to
  avoid collisions. Find class names with the browser inspector.
- Server-side JRS themes (per-organization CSS) also restyle the generated
  widgets -- the theme applied depends on the org of the authenticated user.
  This skill's theme tooling (SKILL.md, UI themes) can deploy such a theme.
- Not everything is themeable; for full control export json data and render
  your own visuals.

## Errors (p.139-145)
Error object: `{ errorCode, message, parameters[] }` (plus `validationError`
detail for schema validation failures). Where to catch:
- init + auth errors: 3rd arg of `visualize()` (p.141).
- per-component: the `error:` callback in the properties, AND `.fail()` on
  the deferred returned by `run()` / `export()` etc. (p.143).
- pre-flight: `new ResourcesSearch({...}).validate()` and
  `new InputControls({...}).validate()` check property structure without a
  server call (p.142, p.144).

Common errorCode values and causes (p.140-141):
| errorCode | Cause / fix |
|---|---|
| (page hangs, no error) | visualize.js script host unreachable -- check the script include; on this install see the [verified] cross-origin rules above (CORS/domainWhitelist misconfig also lands here) |
| authentication.error | bad credentials or expired session -- re-login via v.login() |
| container.not.found.error | selector matched nothing in the DOM |
| unexpected.error | JS exception or HTTP 500 from server |
| schema.validation.error | properties failed JSON-schema check; read validationError |
| unsupported.configuration.error | isolateDom:true with defaultJiveUi.enabled:true -- mutually exclusive |
| report.execution.failed / .cancelled | report failed or was canceled on the server |
| report.export.failed | export failed server-side |
| export.pages.out.range | requested pages beyond the report's page count |
| licence.not.found / licence.expired | commercial license missing/expired (note the "licence" spelling) |
| resource.not.found | URI wrong OR user lacks read permission |
| input.controls.validation.error | bad IC params sent to server |

## Cross-domain extras beyond the verified recipe (p.14-17)
The [verified] section above is authoritative for this install
(domainWhitelist is `*`, serve the page from a separate origin). The guide
adds: the whitelist is edited as superuser under Manage > Server Settings >
Server Attributes, attribute `domainWhitelist`, a simplified regex like
`http://*.myexample.com:80\d0` (blank = same-origin only) (p.14). Safari
blocks the third-party cookies Visualize.js relies on -- workarounds: proxy
JRS onto your app's domain or use sibling subdomains (p.15). Chrome treats
cross-domain access as CORS: both sides should be HTTPS and XHR needs
`withCredentials=true`; JRS then sends `Secure; HttpOnly` cookies (p.15).
For AJAX from a public page to a private-network JRS, uncomment the
`Access-Control-Allow-Private-Network: true` entries in the `corsProcessor`
bean of `...\WEB-INF\applicationContext-security-web.xml` (p.16). Visualize.js
can also be served from a CDN/static host by copying
`webapps/jasperserver-pro/scripts/visualize/` (p.16-17).

## 10.1 vs 9.0
Content-identical. A full token-level diff of the 9.0 and 10.1 guides shows
the same API surface, properties, events, formats, and error codes; only
pagination/layout differ (9.0: 160 pp, 10.1: 207 pp). Anything above applies
equally to 9.x and 10.x servers, including the local 10.0 install.
