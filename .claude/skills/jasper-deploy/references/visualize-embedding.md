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
