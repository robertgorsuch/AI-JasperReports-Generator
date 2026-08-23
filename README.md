# AI-JasperReports-Generator

[![CI](https://github.com/robertgorsuch/AI-JasperReports-Generator/actions/workflows/ci.yml/badge.svg)](https://github.com/robertgorsuch/AI-JasperReports-Generator/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/robertgorsuch/AI-JasperReports-Generator)](https://github.com/robertgorsuch/AI-JasperReports-Generator/releases)
[![License](https://img.shields.io/github/license/robertgorsuch/AI-JasperReports-Generator)](LICENSE)

> **BI pipeline automation using Jaspersoft and Claude Code** — a self-contained toolkit that geocodes Texas addresses, visualizes 2020 census population data, and automates the full JasperReports Server lifecycle through a Claude Code skill and a self-service web wizard.

Built and maintained by the Actian (HCLSoftware) SE team as a working reference for customers evaluating **Jaspersoft** embedded analytics and report automation.

---

## What this project demonstrates

| Capability | Technology |
|---|---|
| Full JRS lifecycle automation | `jasper-deploy` Claude Code skill (REST v2 against JRS 10 Pro) |
| Pixel-perfect PDF reporting | JasperReports 7 native `.jrxml` → 317-page statewide PDF |
| Self-service report creation | Jakarta servlet web wizard (Actian-branded, no JRXML required) |
| Demo sample data | PostgreSQL 14 + PostGIS 3.4 Tiger geocoder (TX census data the demo reports query) |

This is a **working demo environment**, not a starter template. Every script, skill, and wizard endpoint has been verified end-to-end against a local JasperReports Server 10 Pro instance.

---

## Repository layout

| Path | Contents |
|---|---|
| `scripts/` | TIGER data loaders that build the PostGIS sample DB the demo reports query — `load_tiger_nation.bat`, `load_remaining.ps1`, etc. All use `curl` + `7z t` integrity checks with retry. |
| `report/` | JasperReports templates (`*_jr7.jrxml` native JR7 + 6.x version), JDBC data adapter, compile/fill harnesses. `report/foodmart/` holds deployable KPI reports + `dashboard.json` manifest. |
| `plugins/jasper-deploy/` | The **jasper-deploy Claude Code plugin** — the skill (49 PowerShell/Python scripts covering the full JRS lifecycle; `SKILL.md` is the lean index, detail lives in `references/`), four slash commands, and the plugin [CHANGELOG](plugins/jasper-deploy/CHANGELOG.md). |
| `webapp/jasper-wizard/` | Self-service browser UI over the skill. Business users create, run, and deliver Jaspersoft artifacts with no JRXML or REST knowledge. |
| `postman_collections/` | REST v2 Postman collections for manual API exploration. |
| `output/`, `maps/`, `backups/` | Generated artifacts (PDF / GeoJSON / CSV / Leaflet HTML / JRS export zips) — not tracked; regenerate from the DB and the skill's export scripts. |
| `RUNBOOK.md` | Full operational reference: environment, exact commands, rebuild order, and gotchas. |
| `ONBOARDING.md` | 5-minute orientation for a new contributor. |

---

## Quick start

### Prerequisites

| Tool | Version | Notes |
|---|---|---|
| PostgreSQL + PostGIS | 14 + 3.4 | DB `postgis_34_sample`, extensions `postgis`, `postgis_tiger_geocoder`, `address_standardizer` |
| JDK | 11 | Set `JAVA_HOME` |
| Maven | 3.9 | For building JasperReports from source |
| 7-Zip | Any | For download integrity checks |
| curl | Built-in (Windows) | Use `curl.exe` — do **not** use `wget` (see gotchas) |
| JasperReports Server | 10 Pro | Listening on `http://localhost:8081/jasperserver-pro` |
| JR 7.0.6 runtime jars | 7.0.6 | Pre-built; see RUNBOOK §5 for build instructions |

### 1 — Geocoder

```bat
:: Load national state/county lookups (run once, run first)
scripts\load_tiger_nation.bat

:: Load all 254 Texas counties (idempotent, verified)
powershell -File scripts\load_remaining.ps1
```

Test it:

```sql
SELECT g.rating, pprint_addy(g.addy)
FROM geocode('1100 Congress Ave, Austin, TX 78701', 1) AS g;
-- Expected: rating 0 (exact match)
```

### 2 — Report → PDF

See RUNBOOK §5 for the full build sequence. At a glance:

```bat
set CP=C:\path\to\jasperreports-lib\*
set PGPASSWORD=<your password>
javac -cp "%CP%" report\CompileReport.java report\FillReport.java
java -cp "%CP%;report" CompileReport report\tx_density_blockgroup_report_jr7.jrxml
java -cp "%CP%;report" FillReport report\tx_density_blockgroup_report_jr7.jasper output\report.pdf
```

### 3 — Deploy reports and dashboards (jasper-deploy skill)

> Not cloning the repo? The skill installs straight into Claude Code as a
> plugin — see [Install as a Claude Code plugin](#install-as-a-claude-code-plugin).

```powershell
$skill = ".\plugins\jasper-deploy\skills\jasper-deploy\scripts"
$env:PGPASSWORD = "postgres"

# Build all Foodmart KPI dashlets and compose the dashboard
& $skill\build_dashlets.ps1 -Manifest report\foodmart\dashboard.json -Compose

# Run the full 24-step regression gate after any script change
& $skill\smoke_test.ps1
```

### 4 — Self-service web wizard

```powershell
cd webapp\jasper-wizard
.\build.ps1   # compile + bundle + hot-deploy to JRS Tomcat
```

Access at `http://localhost:8081/jasper-wizard/`.

---

## The `jasper-deploy` skill

`plugins/jasper-deploy/skills/jasper-deploy/` automates the full JasperReports Server lifecycle against JRS 10 Pro over REST v2. All scripts are JR 7.0.6-native and verified end-to-end. Highlights:

**Design & compile**
- `scaffold_jrxml.py` — introspect a SQL query, emit a JR7 tabular report with optional charts, parameters, grouping, conditional formatting, drill-down, crosstab, and subreport support
- `compile_jrxml.ps1` — compile `.jrxml` → `.jasper` with a fast JR7 validity check
- `lint_jrxml.ps1` — static pre-deploy linter (catches strict-Jackson traps that a clean local compile misses); runs automatically inside `deploy_report.ps1`

**Deploy & verify**
- `deploy_report.ps1` — PUT a report unit with in-place overwrite, SQL-lint guard, and input control attachment
- `verify_report.ps1` — assert HTTP status, CSV row counts, contained text, and visual baseline diff against a deployed report

**Data layer**
- `create_datasource.ps1` — JDBC plus JNDI, bean, custom, virtual, and AWS datasource types; `-Test` makes the server open the live connection (`/contexts`) before anything is stored
- `scaffold_domain_schema.py` + `create_domain.ps1` — introspect tables into a Domain for Ad Hoc reporting: single-table, or multi-table with joins (`--table` × N + `--join`, emitting the JRS 10 join-tree schema)
- `manage_adhoc.ps1` — list, inspect, export, and import Ad Hoc views

**Dashboards**
- `build_dashlets.ps1` + `compose_dashboard.ps1` — build and import a dashboard of report, text, and image tiles from a single JSON manifest (bypasses the blank-render bug of a raw REST PUT)

**Governance & operations**
- `extract_lineage.py` — asset + column-level lineage graph (reports → datasources → tables → columns via `sqlglot`); supports OpenLineage output
- `diff_resource.ps1` — drift detection between live JRS and committed source
- `reconcile.ps1` — declarative desired-state applier (plan-only by default; `-Apply` to execute)
- `report_usage.ps1` — who-ran-what usage reporting from the repository metadata DB's access events (top resources / per-user / recent / per-resource, CSV output)
- `manage_diagnostic.ps1` — diagnostic log collectors: capture server logs around a repro and download the support bundle
- `doctor.ps1` — 10-point environment preflight (server, DBs, JRS→DB connectivity via `/contexts`, server settings + Visualize.js domainWhitelist, jars, Python)
- `smoke_test.ps1` — 24-step end-to-end regression gate (+ a wizard-api step when the web wizard is deployed)

**Admin**
- `manage_users.ps1`, `manage_roles.ps1`, `manage_organizations.ps1` — identity and tenant CRUD
- `manage_permissions.ps1`, `manage_attributes.ps1` — repository ACLs and server/org/user attributes
- `promote.ps1` — dev→prod promotion between named environment profiles (`-FromEnv stage -ToEnv prod`, defined once in `jrs.config.json` "environments") or explicit URLs
- `run_report_async.ps1` — large fills via the async `reportExecutions` API

**Delivery & embedding**
- `scaffold_visualize_embed.py` — generate a ready-to-open Visualize.js embed page for a deployed report or dashboard (credential placeholder by default)
- `get_thumbnail.ps1` — fetch a report's server-side thumbnail image, the cheapest visual sanity check

Full reference: `plugins/jasper-deploy/skills/jasper-deploy/SKILL.md` and `RUNBOOK.md` §9.

---

## Self-service web wizard (`webapp/jasper-wizard/`)

A Jakarta servlet WAR (Actian-branded) that puts the `jasper-deploy` skill behind a browser UI for business users — no JRXML or REST knowledge needed.

**Capabilities:** create and deploy reports (SQL → chart/table with live query preview + input controls), dashboards, data sources, domains, and themes; run and export (PDF/XLSX/CSV/DOCX/PPTX + async); schedule jobs; browse the repository; manage ad hoc views and permissions; view a **Server Summary** dashboard of live repository inventory and runtime characteristics.

**Architecture:** read/preview/run operations proxy directly to JRS REST (no browser credentials, no CORS). Create/deploy operations shell out to the verified skill scripts bundled inside the WAR (`WEB-INF/scripts`). Changes to a script's parameters or stdout shape may require updating the matching wizard handler.

> ⚠️ Security note: the wizard runs user-supplied SQL with the configured data source's privileges and publishes using stored admin credentials. Keep it behind the JRS login and a network boundary. This is an internal, trusted-user tool.

---

## Key gotchas

Full details in `RUNBOOK.md` §3 and `plugins/jasper-deploy/skills/jasper-deploy/references/gotchas.md`. Top issues:

1. **Use `curl.exe`, not `wget`** — wget's installer source is unreachable in this environment.
2. **Always verify downloads with `7z t` + retry** — the Census CDN silently returns corrupt ZIPs (HTTP 200).
3. **JasperReports 7 `.jrxml` ≠ 6.x** — new Jackson format. Use the `_jr7` file or let Jaspersoft Studio auto-upgrade. PDF export requires the separate `jasperreports-pdf` module.
4. **JRS report queries must start with `SELECT`** — a leading `WITH` (CTE) compiles locally but the server rejects it at fill time. Push CTEs into a `FROM` subquery.
5. **Dashboards: import, don't PUT** — a hand-built dashboard PUT to `/rest_v2/resources` stores successfully but renders blank. Use `compose_dashboard.ps1`.
6. **Lint before you deploy** — `lint_jrxml.ps1` catches strict-Jackson traps that a clean local compile misses.
7. **PowerShell `-D` args after `--%`** — Maven `-Dproperty=value` flags must follow the stop-parsing token or PowerShell mangles them.

---

## Jaspersoft resources

| Resource | URL |
|---|---|
| Official documentation | https://community.jaspersoft.com/documentation |
| Community forum | https://community.jaspersoft.com |
| JasperReports Library (open source) | https://github.com/Jaspersoft/jasperreports |
| Jaspersoft Studio download | https://community.jaspersoft.com/download |
| REST API reference | `{jrs-host}/jasperserver-pro/rest_v2/api` (live Swagger on your server) |
| Actian Jaspersoft page | https://www.actian.com/jaspersoft/ |

> Note: `jaspersoft.com` / `community.jaspersoft.com` sit behind Cloudflare and
> block scripted access (HTTP 403 to curl and link checkers) — open them in a
> browser. The skill's `references/` carry doc-derived offline equivalents for
> most of what the documentation site covers.

---

## POS performance dashboards (report/pos_perf)

Three dashboards on JasperReports Server, fed by `robert.gorsuch` on the
pos_data Avalanche warehouse through `/datasources/pos_data_avalanche`:

| Dashboard | URI | Manifest |
|---|---|---|
| POS Executive Overview | /reports/pos_perf/pos_executive_overview | report/pos_perf/exec_dashboard.json |
| POS Operations Console | /reports/pos_perf/pos_operations_console | report/pos_perf/ops_dashboard.json |
| POS Promo and Margin Story | /reports/pos_perf/pos_promo_story | report/pos_perf/story_dashboard.json |

Tiles read the precomputed `dash_*` aggregates built by
`scripts/pos_perf/build_dash_aggregates.sql` (verify with
`verify_dash_aggregates.sql`). Margin basis: extended sales minus extended
cost per line, 31.65 pct network (see out/pos_perf/margin_basis_decision.md
in a local build). Design: specs/2026-08-20-pos-sales-dashboards-design.md;
suite roadmap: specs/2026-08-23-pos-suite-design.md.

## About

Demos and artifacts for BI pipeline automation using **Jaspersoft** and **Claude Code Desktop**, built by the Actian SE team.

- Topics: `jaspersoft` `jasperreports` `claude-code` `claude-skills` `claude-code-plugin` `postgis` `business-intelligence`
- No credentials are stored in this repo. Set `PGPASSWORD` in your environment before running scripts.
- See `RUNBOOK.md` for full environment details, rebuild order, and exact commands.

## Install as a Claude Code plugin

The `jasper-deploy` skill is installable directly into Claude Code — no
clone required. In any Claude Code session:

```
/plugin marketplace add robertgorsuch/AI-JasperReports-Generator
/plugin install jasper-deploy@jaspersoft-tools
/reload-plugins
```

**Slash commands** (since [1.1.0](plugins/jasper-deploy/CHANGELOG.md)):

| Command | What it does |
|---|---|
| `/jasper-deploy:doctor` | Preflight the toolchain + server connectivity — **run this first** |
| `/jasper-deploy:deploy` | Scaffold/compile/deploy a report from SQL or a `.jrxml`, then verify it renders |
| `/jasper-deploy:promote` | Promote a resource between environments (STAGE → PROD) with a target backup |
| `/jasper-deploy:smoke` | Full 24-step lifecycle regression test |

**Verify:** the four commands above appear in your command list, and Claude
picks the skill up automatically for JasperReports work — scaffolding jrxml
from SQL, deploying reports/dashboards, datasources, Domains, promotion, and
upgrade/migration planning questions. Release history:
[CHANGELOG](plugins/jasper-deploy/CHANGELOG.md) ·
[GitHub releases](https://github.com/robertgorsuch/AI-JasperReports-Generator/releases).

**Configure credentials** (never committed): in the installed skill's
directory copy `jrs.config.example.json` to `jrs.config.json`, or set the
`JRS_URL` / `JRS_USER` / `JRS_PASS` environment variables. A
`passwordCommand` hook is available for secret managers.

**Prerequisites:** PowerShell 5.1 or `pwsh` 7+ (Windows/macOS/Linux),
JDK 11+, `psql` 14, `curl` 8.x, Python 3 (`sqlglot`, `pypdfium2`), and a
local JasperReports 7.0.6 jar directory (`jrLibDir` in the config or
`JR_LIB_DIR`). Run the skill's `scripts/doctor.ps1` to verify readiness
against your JasperReports Server.

**Manage:**

```
/plugin update jasper-deploy        # pull the latest published version
/plugin uninstall jasper-deploy     # remove
```

Working on this repo directly? Skip the plugin — the project-level skill
in `plugins/jasper-deploy/skills/jasper-deploy/` loads automatically (installing the
plugin too would load it twice).

## Contributing

Contributions welcome — start with the
[contribution guidelines](plugins/jasper-deploy/skills/jasper-deploy/CONTRIBUTING.md)
(conventions, testing gates, and per-change-type definition-of-done
checklists). Pull requests are pre-filled with the
[PR template](.github/PULL_REQUEST_TEMPLATE.md); issues use the
[bug report](.github/ISSUE_TEMPLATE/bug_report.md) and
[feature request](.github/ISSUE_TEMPLATE/feature_request.md) templates.
All project spaces follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

Licensed under the [Apache License, Version 2.0](LICENSE). Jaspersoft®, JasperReports®, and related marks are trademarks of Cloud Software Group, Inc.; this is an independent demo/reference project and is not endorsed by or affiliated with the trademark holders.
