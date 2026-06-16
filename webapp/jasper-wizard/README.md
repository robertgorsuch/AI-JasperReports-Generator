# Jaspersoft Artifact Wizard

A self-service web app that steps a business user or analyst through the **core
Jaspersoft lifecycle** — create, run, deliver, and manage artifacts — without
touching JRXML or the REST API directly.

It runs as a WAR inside the JasperReports Server's own Tomcat and reuses the
verified `jasper-deploy` scripts under the hood, so what the wizard produces is
identical to the scripted pipeline.

```
Browser ──HTTP──> Java servlet (WAR on Tomcat)
                     ├─ reads / preview / run ── JrsClient ──REST──> JasperReports Server
                     └─ create / deploy ── ScriptRunner (ProcessBuilder) ─> bundled scripts ─REST─> JRS
                            scaffold_jrxml · deploy_report · create_datasource · compose_dashboard
                            scaffold_domain_schema · create_domain · scaffold_theme · deploy_theme
                            schedule_job · manage_permissions · manage_adhoc · export_resource · run_report_async
```

## What it does

| Sidebar | Flow | Backend |
|---------|------|---------|
| **Report** | datasource → SQL with **live preview** → template/chart (columns auto-suggested from the preview) → optional **interactive input control** → deploy + PDF preview | `scaffold_jrxml.py` (`--param`), `deploy_report.ps1` (`-Control`/`-QueryControl`) |
| **Dashboard** | pick deployed reports as tiles → compose → HTML5 viewer | `compose_dashboard.ps1` |
| **Data Source** | form → register a PostgreSQL JDBC datasource | `create_datasource.ps1` |
| **Domain** | one table → semantic-layer Domain for Ad Hoc | `scaffold_domain_schema.py`, `create_domain.ps1` |
| **Theme** | palette → deploy a JRS UI theme | `scaffold_theme.py`, `deploy_theme.ps1` |
| **Run & Export** | pick a report → fill its **input-control filters** → run/download as PDF/XLSX/CSV/DOCX/PPTX/HTML, **async** for big fills | REST proxy + `run_report_async.ps1` |
| **Schedule** | recurring/one-off delivery, saved to repo and/or emailed; list & delete jobs | `schedule_job.ps1`, `jobs` REST |
| **Repository** | browse by folder/type; per-row **run / export / permissions / delete** | `resources`/`export_resource.ps1` |
| **Ad Hoc Views** | list and export (back up / promote) | `manage_adhoc.ps1` |
| **Permissions** | view effective ACLs; set/clear by role | `manage_permissions.ps1` |

## Build & deploy

Requires JDK 11 (`C:\jdk-11.0.24+8`) and the JRS Tomcat at
`C:\Jaspersoft\jasperreports-server-10.0.0\apache-tomcat`. No Maven — it compiles
against Tomcat's bundled Jakarta `servlet-api.jar`.

```powershell
cd webapp\jasper-wizard
.\build.ps1                 # compile + bundle scripts + WAR + hot-deploy to Tomcat
# .\build.ps1 -NoDeploy     # just build target\jasper-wizard.war
```

Open: **http://localhost:8081/jasper-wizard/**

## How it's wired (and why)

- **Tomcat 10.1 → Jakarta Servlet.** Imports are `jakarta.servlet.*`; JDK 11 compiles it.
- **Reads/preview/run go through `JrsClient`** straight to the JRS REST API, with
  Basic auth added server-side — the browser needs no credentials and there is no
  CORS problem. Create/deploy shell out to the verified scripts via `ScriptRunner`.
- **Scripts are bundled inside the WAR** (`WEB-INF/scripts`). Tomcat runs as
  `NT AUTHORITY\LocalService`, which cannot read the user profile/repo; bundling
  lets it run them from its own `webapps` dir — **no ACL or service-account
  changes required.** Child processes run from the container temp dir (writable);
  nothing is written back into the repo.
- **No local compile step.** JasperServer compiles the JRXML server-side on
  deploy and `deploy_report.ps1` lints the SQL first, so the local
  `compile_jrxml`/`jasperreports-lib` dependency is gone.

### Optimizations in this build
- **Performance** — input-control values and report runs proxy directly to REST
  (no extra script spawn); large reports use the async `reportExecutions` path
  (`run_report_async.ps1`); `health` reflects real `serverInfo` reachability.
- **UX** — live **query preview** (psql) validates the SQL and **auto-populates
  the chart/group column pickers** from the actual result columns; per-report
  filter inputs are generated from the deployed input controls; inline banners +
  collapsible logs on every action.
- **Robustness** — every script step's combined stdout/stderr is surfaced with
  the `failedStep`; output is drained on a worker thread with a hard timeout;
  command args are passed as an argv array (no shell-injection surface);
  deletes prompt for confirmation and report `resource.in.use`.
- **Code structure** — REST wiring factored into `JrsClient`; the servlet is a
  thin dispatcher with one small handler method per feature; all
  environment-specific values are `web.xml` context-params.

## Configuration (`WEB-INF/web.xml` context-params)

| Param | Default | Purpose |
|-------|---------|---------|
| `jrsUrl` / `jrsUser` / `jrsPass` | `localhost:8081` / `superuser` / `superuser` | JRS base URL + Basic auth |
| `pgHost` / `pgPort` / `pgUser` / `pgPassword` | `localhost` / `5432` / `postgres` / `postgres` | local PostgreSQL for query/column introspection |
| `pythonExe` | `python` | Python launcher (on the machine PATH) |
| `scriptTimeoutSec` | `180` | max seconds per script step / REST read |
| `repoRoot` | repo path | fallback scripts location for an unpacked/dev run |

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/health` | reachability + `jrsUp` |
| GET | `/api/datasources` · POST `/api/datasources` | list / create JDBC datasource |
| POST | `/api/query/preview` | run SQL via psql → columns + sample rows |
| GET | `/api/reports?folder=` · POST `/api/reports` | list / scaffold+deploy a report |
| GET | `/api/run?uri=&format=&<ctrl>=…[&async=true]` | run + stream (filters, multi-format, async) |
| GET | `/api/controls?uri=` · `/api/controls/values?uri=&id=` | input controls + cascading values |
| POST | `/api/dashboards` | compose a dashboard |
| GET | `/api/domains` · POST `/api/domains` | list / create single-table Domain |
| POST | `/api/themes` | scaffold + deploy a UI theme |
| GET | `/api/jobs?reportUri=` · POST `/api/jobs` · DELETE `/api/jobs?id=` | schedule CRUD |
| GET | `/api/permissions?uri=` · POST `/api/permissions` · DELETE `/api/permissions?uri=` | ACLs |
| GET | `/api/resources?folder=&type=` · DELETE `/api/resources?uri=` | browse / delete |
| GET | `/api/export?uri=` | export a resource as a zip |
| GET | `/api/adhoc?folder=` · `/api/adhoc/export?uri=` | list / export Ad Hoc views |

## Security note

The wizard runs user-supplied SQL against the configured database and publishes to
JasperServer with stored admin credentials. It is an **internal, trusted-user
tool** — put it behind the JRS login / a network boundary. Command arguments are
passed as an argv array (no shell injection), but the SQL still runs with the data
source's privileges.

## Project layout

```
webapp/jasper-wizard/
  build.ps1                          compile + bundle + WAR + deploy (no Maven)
  src/main/java/com/jasperwizard/
    WizardServlet.java               dispatcher; one handler per feature
    JrsClient.java                   shared JRS REST client (auth, get/delete/stream)
    ScriptRunner.java                ProcessBuilder wrapper (argv, env, timeout, drain)
    Json.java                        minimal JSON output escaping
  src/main/webapp/
    index.html  css/style.css  js/wizard.js     sidebar UI + per-panel logic
    WEB-INF/web.xml                  context-params + servlet mapping
  (build time) WEB-INF/scripts/      bundled copy of the jasper-deploy scripts
```
