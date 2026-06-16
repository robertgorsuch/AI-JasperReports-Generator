# Jaspersoft Artifact Wizard

A self-service web app that steps a business user or analyst through creating and
deploying Jaspersoft artifacts — **reports**, **dashboards**, and **data
sources** — without touching JRXML or the REST API directly.

It runs as a WAR inside the JasperReports Server's own Tomcat and reuses the
verified `jasper-deploy` scripts under the hood, so what the wizard produces is
identical to the scripted pipeline.

```
Browser ──HTTP──> Java servlet (WAR on Tomcat)
                     ├─ reads/preview ─────REST──> JasperReports Server
                     └─ create/deploy ─ ProcessBuilder ─> bundled scripts ─REST─> JRS
                            ├─ scaffold_jrxml.py   (introspect query via psql)
                            ├─ deploy_report.ps1   (publish report unit)
                            ├─ create_datasource.ps1
                            └─ compose_dashboard.ps1
```

## What it does

| Tab | Flow | Scripts used |
|-----|------|--------------|
| **Report** | Pick a data source → write a `SELECT` → choose template + chart → review → deploy, with an inline PDF preview | `scaffold_jrxml.py`, `deploy_report.ps1` |
| **Dashboard** | Check deployed reports to use as tiles → set columns → publish; links to the HTML5 viewer | `gen_dashboard.py`, `compose_dashboard.ps1` |
| **Data Source** | Fill a form → register a PostgreSQL JDBC data source | `create_datasource.ps1` |

## Build & deploy

Requires JDK 11 (`C:\jdk-11.0.24+8`) and the JRS Tomcat at
`C:\Jaspersoft\jasperreports-server-10.0.0\apache-tomcat`. No Maven — it compiles
straight against Tomcat's bundled Jakarta `servlet-api.jar`.

```powershell
cd webapp\jasper-wizard
.\build.ps1                 # compile + bundle scripts + WAR + deploy to Tomcat
# .\build.ps1 -NoDeploy     # just build target\jasper-wizard.war
```

Tomcat auto-expands the WAR. Open:

```
http://localhost:8081/jasper-wizard/
```

## How it's wired (and why)

- **Tomcat 10.1 → Jakarta Servlet.** Imports are `jakarta.servlet.*` (not
  `javax.*`); JDK 11 compiles it.
- **Reads & preview are proxied, not scripted.** Listing data sources/reports and
  the report preview go straight to the JRS REST API from the servlet, with Basic
  auth added server-side — so the browser needs no credentials and there is no
  CORS problem. Create/deploy actions shell out to the verified scripts.
- **Scripts are bundled inside the WAR** (`WEB-INF/scripts`). The Tomcat service
  runs as `NT AUTHORITY\LocalService`, which cannot read the user profile / repo.
  Bundling the scripts into the webapp means LocalService executes them from its
  own `webapps` dir — **no ACL changes or service-account changes required.**
- **Child processes run from Tomcat's temp dir.** Generated JRXML, dashboard
  manifests, and compose scratch space all live under the container temp dir
  (LocalService-writable); nothing is written back into the repo.
- **No local compile step.** JasperServer compiles the JRXML server-side on
  deploy, and `deploy_report.ps1` lints the SQL first — so the wizard skips the
  local `compile_jrxml.ps1`/`jasperreports-lib` dependency entirely.

## Configuration

All settings are `<context-param>`s in `src/main/webapp/WEB-INF/web.xml` — edit
and rebuild (or edit the exploded `webapps/jasper-wizard/WEB-INF/web.xml` and
restart the app):

| Param | Default | Purpose |
|-------|---------|---------|
| `jrsUrl` | `http://localhost:8081/jasperserver-pro` | JRS base URL |
| `jrsUser` / `jrsPass` | `superuser` / `superuser` | JRS Basic auth |
| `pgPassword` | `postgres` | local PostgreSQL password for query introspection |
| `pythonExe` | `python` | Python launcher (on the machine PATH) |
| `scriptTimeoutSec` | `180` | max seconds per script step |
| `repoRoot` | repo path | fallback scripts location for an unpacked/dev run |

## Endpoints (for reference / scripting)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/health` | server reachability |
| GET | `/api/datasources` | list JDBC data sources (raw JRS JSON) |
| POST | `/api/datasources` | create a JDBC data source |
| GET | `/api/reports?folder=/reports` | list deployed report units |
| POST | `/api/reports` | scaffold + deploy a report |
| POST | `/api/dashboards` | compose a dashboard from deployed reports |
| GET | `/api/run?uri=…&format=pdf` | run a report and stream the output |

## Security note

The wizard executes user-supplied SQL against the configured database and
publishes to JasperServer with stored admin credentials. It is an **internal,
trusted-user tool** — put it behind the JRS login / a network boundary; do not
expose it to untrusted users. (Command arguments are passed as an argv array, not
a shell string, so there is no shell-injection surface, but the SQL itself still
runs with the data source's privileges.)

## Project layout

```
webapp/jasper-wizard/
  build.ps1                          compile + bundle + WAR + deploy (no Maven)
  src/main/java/com/jasperwizard/
    WizardServlet.java               dispatcher: proxy reads, shell out for writes
    ScriptRunner.java                ProcessBuilder wrapper (argv, env, timeout, drain)
    Json.java                        minimal JSON output escaping
  src/main/webapp/
    index.html  css/style.css  js/wizard.js
    WEB-INF/web.xml                  context-params + servlet mapping
  (build time) WEB-INF/scripts/      bundled copy of the jasper-deploy scripts
```
