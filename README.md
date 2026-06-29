# Texas PostGIS Geocoder + Population Maps + JasperReports

A self-contained toolkit built on a single PostgreSQL/PostGIS database (`postgis_34_sample`) that:

- 🗺️ **Geocodes Texas addresses** — the PostGIS **Tiger geocoder** loaded for **all 254 Texas counties**
  (5.7M edges, 5.1M feature names, 2.7M address ranges).
- 📊 **Visualizes population** — 2020 census population as interactive Leaflet heatmaps and density
  choropleths (statewide down to ~500 m and census block-group level).
- 📄 **Reports** — a **JasperReports 7** report over the same data (native `.jrxml`, compiles to `.jasper`,
  renders a 317-page PDF).
- 🤖 **JasperReports automation** — the **`jasper-deploy` skill** scripts the whole design → compile →
  deploy → verify pipeline against **JasperReports Server 10** (REST v2), and even **composes dashboards
  from a JSON manifest**. See [the skill section](#jasperreports-server-automation--the-jasper-deploy-skill).
- 🖥️ **Self-service web wizard** — `webapp/jasper-wizard/`, a browser UI (Actian-branded) over the skill
  that lets a business user create/run/deliver/manage Jaspersoft artifacts with no JRXML, plus a live
  **Server Summary** dashboard of repository inventory + runtime characteristics.

```sql
-- it works:
SELECT g.rating, pprint_addy(g.addy)
FROM geocode('1100 Congress Ave, Austin, TX 78701', 1) AS g;   -- rating 0, exact match
```

## Repository layout

| Path | Contents |
|------|----------|
| `scripts/` | TIGER data loaders (verified curl downloads + CRC retry). `load_tiger_nation.bat`, `load_remaining.ps1`, etc. |
| `report/`  | JasperReports: `*_jr7.jrxml` (native JR 7) + 6.x version, JDBC data adapter, compile/fill harnesses. `report/foodmart/` holds the deployable KPI reports + `dashboard.json` manifest |
| `.claude/skills/jasper-deploy/` | The **jasper-deploy skill**: scripts for reports (`scaffold_jrxml.py`, `deploy_report.ps1`, `verify_report.ps1`), dashboards (`build_dashlets.ps1`, `compose_dashboard.ps1`), style templates (`scaffold_style_template.py`), domains (`scaffold_domain_schema.py`, `create_domain.ps1`), ad hoc views (`manage_adhoc.ps1`), datasources (`create_datasource.ps1`), themes (`scaffold_theme.py`, `deploy_theme.ps1`), OLAP (`create_mondrian.ps1`), governance (`manage_permissions.ps1`, `manage_attributes.ps1`), lifecycle (`promote.ps1`, `teardown_dashboard.ps1`, `smoke_test.ps1`), quality/governance (`lint_jrxml.ps1`, `extract_lineage.py`, `diff_resource.ps1`), operations (`reconcile.ps1`, `doctor.ps1`, `check_docs.ps1`), plus `SKILL.md` (lean index) + topic `references/` (reports, dashboards, data-and-semantic-layer, admin-and-scheduling, gotchas, jr7-valid-elements, JR7 schema, REST API + `application.wadl`, dashboard model, security-and-config, seed-data, smtp-testing, ci-smoke, visualize-embedding, JSON schemas), `fixtures/`, `baselines/`, and `tests/` (Pester) |
| `webapp/jasper-wizard/` | **Self-service web wizard** (Jakarta servlet WAR) over the skill: reports, dashboards, data sources, domains, themes, run/export, scheduling, repository browse, ad hoc, permissions, and a Server Summary. Builds with `build.ps1` (no Maven), bundles the skill scripts, hot-deploys to the JRS Tomcat. See its `README.md` |
| `maps/`    | Self-contained Leaflet HTML visualizations (open in a browser) |
| `backups/` | Versioned JRS export archives (dashboards) for restore / dev→prod promotion |
| `output/`  | Generated PDF / GeoJSON / CSV (not tracked — regenerate from the DB) |
| **`RUNBOOK.md`** | **Full reference**: environment, exact commands, rebuild order, and the gotchas |
| `ONBOARDING.md` | 5-minute orientation for a new contributor |

## Quick start

1. **Database**: PostgreSQL 14 + PostGIS 3.4, DB `postgis_34_sample`, user `postgres`.
   Set your password in the environment before running anything: `set PGPASSWORD=...` (Windows) — scripts read it from there.
2. **Geocoder**: run `scripts/load_tiger_nation.bat` then `scripts/load_remaining.ps1` (idempotent, verified).
3. **Maps**: open any file in `maps/` directly in a browser.
4. **Report → PDF**: see [RUNBOOK.md](RUNBOOK.md) §5 (build the JasperReports 7 library, compile, fill, export).

## Good to know (the gotchas, in brief)

- **Downloads use `curl` + `7z t` integrity checks with retry** — the census CDN occasionally serves silently
  corrupt zips (HTTP 200) and can return a CDN-cached WAF rejection page; both are handled. Details in the RUNBOOK.
- **JasperReports 7 changed the `.jrxml` format** (no namespace, `<query>`, no `<reportElement>`, flattened
  `<element kind="…">`). Use the `*_jr7.jrxml` file, or let Jaspersoft Studio auto-upgrade the 6.x one.
  PDF export requires the separate `jasperreports-pdf` module.

## JasperReports Server automation — the `jasper-deploy` skill

`.claude/skills/jasper-deploy/` automates the full JasperReports lifecycle against a local
**JasperReports Server 10** (`http://localhost:8081/jasperserver-pro`, REST v2) — everything is
**JR 7.0.6-native**. Highlights (each verified end-to-end against the server):

- **Design from SQL** — `scaffold_jrxml.py` introspects a query and emits a tabular JR7 report. Options:
  charts (pie/bar/line/area/stacked + label rotation), `--param` (parameters), `--group-by` (subtotals),
  `--highlight` (conditional formatting), `--drill` (drill-down links), `--crosstab` (pivot), `--subreport`.
- **Compile & deploy** — `compile_jrxml.ps1`, `deploy_report.ps1` (in-place overwrite, SQL-lint guard,
  and `-Control` to attach interactive input controls).
- **Data sources** — `create_datasource.ps1` creates JDBC plus non-JDBC types
  (`-Type jndi|bean|custom|virtual|aws`).
- **Input controls** — `deploy_report.ps1 -Control` for static lists, plus
  `-QueryControl`/`-QueryMultiControl` for query-backed and **cascading** controls.
- **Style templates** — `scaffold_style_template.py` emits a shared `.jrtx`; `scaffold_jrxml.py
  --style-template` references it via `<template>` so many reports share one centrally-managed look.
- **Domains (semantic layer)** — `scaffold_domain_schema.py` + `create_domain.ps1` introspect a table
  into a single-table Domain (`semanticLayerDataSource`) for Ad Hoc / Domain reporting.
- **Verify** — `verify_report.ps1` asserts HTTP + CSV row-count/contained-text + a visual baseline diff.
- **Dashboards (no designer)** — `build_dashlets.ps1` + `compose_dashboard.ps1` build a dashboard of
  report / **text** / **image** tiles from one JSON manifest and import it so it actually renders
  (a raw REST PUT renders blank — see `references/dashboard-model.md`).
- **Ad hoc views** — `manage_adhoc.ps1` lists / inspects / exports / imports `adhocDataView` resources
  (authoring stays in the designer; everything around it is scripted).
- **UI themes** — `scaffold_theme.py` emits an `overrides_custom.css` from a palette; `deploy_theme.ps1`
  deploys + activates it per organization.
- **OLAP / Mondrian** — `create_mondrian.ps1` uploads a Mondrian schema + creates a
  `secureMondrianConnection` (and, best-effort, an MDX analysis view).
- **Governance** — `manage_permissions.ps1` (repository ACLs) and `manage_attributes.ps1`
  (server/org/user attributes).
- **Admin** — `manage_users.ps1`, `manage_roles.ps1`, `manage_organizations.ps1` (tenant/identity CRUD).
- **Run, schedule & cache** — `run_report_async.ps1` (large fills via `reportExecutions`),
  `manage_options.ps1` (saved input-control sets), `manage_cache.ps1` (clear a server cache).
- **Lifecycle** — `export_resource.ps1` / `import_resource.ps1`, `promote.ps1` (dev→prod),
  `teardown_dashboard.ps1`, and `smoke_test.ps1` (19-step end-to-end regression gate).
- **Quality & governance** — `lint_jrxml.ps1` statically validates `.jrxml`/`.jrtx`/`.jrdax` (now a
  gate **inside** `deploy_report.ps1`, also in the smoke prechecks); `extract_lineage.py` emits a
  metadata + **column-level** lineage graph (reports→datasources/tables/columns via `sqlglot`, also
  OpenLineage); `diff_resource.ps1` detects drift vs. a committed source. Troubleshooting:
  `references/gotchas.md` is indexed by symptom (and JRS errors auto-print a pointer to it).
- **Operations** — `reconcile.ps1` applies a whole environment from one manifest (plan by default,
  `-Apply` to execute); `doctor.ps1` is a one-command environment preflight; `check_docs.ps1` guards
  doc/link consistency; `tests/` holds server-less Pester unit tests. Secrets/portability:
  `references/security-and-config.md` (env-only creds, `passwordCommand`, no plaintext on disk).

A 7-tile **Foodmart KPI dashboard** built this way is the reference example
(`report/foodmart/dashboard.json`). Full reference: the skill's `SKILL.md`, and [RUNBOOK.md](RUNBOOK.md) §9.

### Self-service web wizard (`webapp/jasper-wizard/`)

A Jakarta servlet WAR (Actian-branded) that puts the skill behind a browser UI for business users —
no JRXML or REST knowledge needed. It runs inside the JRS Tomcat at `http://localhost:8081/jasper-wizard/`
and covers the full lifecycle: **reports** (SQL→chart/table with live query preview + interactive input
controls), **dashboards**, **data sources**, **domains**, **themes**, **run & export** (PDF/XLSX/CSV/DOCX/
PPTX + async), **scheduling**, **repository browse**, **ad hoc** list/export, **permissions**, and a
**Server Summary** overview (repository inventory + runtime characteristics). Reads/preview proxy straight
to REST; create/deploy shell out to the verified skill scripts (bundled into the WAR). Build & deploy with
`cd webapp\jasper-wizard; .\build.ps1` (no Maven). See `webapp/jasper-wizard/README.md`.

## Prerequisites

PostgreSQL 14 + PostGIS · JDK 11 · Maven 3.9 · 7-Zip · curl. For the jasper-deploy skill: JasperReports
Server 10 on `:8081` + the JR 7.0.6 runtime jars (`C:\Users\rgorsuch\jasperreports-lib\`). See
[RUNBOOK.md](RUNBOOK.md) for versions and paths.

---
*No credentials are stored in this repo — set `PGPASSWORD` in your environment. See RUNBOOK.md for the full reference.*
