# How the jasper-deploy Skill Was Built

*The engineering story behind `.claude/skills/jasper-deploy/` — a Claude Code skill that
automates the full JasperReports Server 10 lifecycle. Written for anyone who wants to
understand the skill's design, reproduce the approach for another product, or evaluate
what "agent-built automation" looks like when it is held to production standards.*

*Current as of July 2026 (commit `f0f0ec6` and later: public-repo hardening, CI, Apache-2.0).*

---

## 1. The starting point

The skill began on **June 1, 2026** as a single happy path: scaffold a JasperReports 7
`.jrxml` from a SQL query, compile it locally, deploy it to a JasperReports Server 10 Pro
instance over REST v2, and run it to PDF. One scaffolder, one deploy script, one SKILL.md.

Everything after that grew the same way: **a real task was attempted against a live
server, whatever broke was fixed, and the fix was captured as executable tooling** — a
script flag, a lint rule, a reference note — so no session would ever relearn it.

## 2. Build principles

Five rules held from the first commit to the latest:

1. **Verify everything against a live server.** No capability was documented until it
   round-tripped end-to-end on the real JRS 10 Pro instance — deploy → run → assert
   output (HTTP status, `%PDF-` magic bytes, CSV row counts, rendered-pixel baselines).
   Import/export flows were proven with *destructive* round-trips: export, delete the
   live resource, re-import, verify it renders.

2. **Docs distinguish verified from doc-only.** The REST endpoint map
   (`references/jrs-rest-api.md`) marks each endpoint **verified** (exercised on this
   install) or **doc-only** (from the vendor PDFs, untested). The ultimate source of
   truth is the server's own live WADL, snapshotted into `references/application.wadl`.

3. **Every failure becomes a guardrail, not a memory.** Painful discoveries were
   promoted, in order of strength: gotcha note → symptom-indexed reference
   (`references/gotchas.md`) → lint rule (`lint_jrxml.ps1`) → hard gate inside the
   deploy script itself. The strict-Jackson traps that JRS reports as an opaque
   HTTP `400` at fill time are now caught *before* deploy by a linter derived from the
   Jackson annotations in the JasperReports 7.0.6 source tree
   (`references/jr7-valid-elements.md`).

4. **A lean index over deep references.** `SKILL.md` stays a capability map — one line
   per task, pointing at the script and the reference that holds the detail. The deep
   knowledge (schemas, flag tables, verified recipes, failure symptoms) lives in 20
   reference files so the index never bloats and the details never go stale invisibly —
   `check_docs.ps1` fails CI if a link breaks or a script disappears.

5. **Regression protection scales with the surface.** As capabilities accumulated, a
   19-step smoke test grew alongside them: scaffold → lint → compile → deploy → verify →
   run-to-PDF → schedule job CRUD → alert CRUD → dashboard compose → style template →
   Domain → JNDI datasource → theme → AWS datasource → cascading controls → permissions →
   attributes → Mondrian → teardown, each step asserted, all under a throwaway
   `/reports/_smoke` folder. Offline prechecks (doc-consistency + a Pester unit suite)
   run first so a broken script never reaches the server.

## 3. Architecture

```
.claude/skills/jasper-deploy/
├── SKILL.md                  # lean capability index (task → script → reference)
├── jrs.config.example.json   # credential/config template (real config is gitignored)
├── scripts/                  # 44 PowerShell + Python tools
│   ├── _jrs_common.ps1       #   shared plumbing: auth, Assert-JrsOk, gotcha hints,
│   │                         #   config resolution (params → env vars → config file)
│   ├── scaffold_*.py         #   generators: jrxml, style templates, Domains, themes, dials
│   ├── deploy/verify/lint    #   the gated pipeline
│   ├── manage_*.ps1          #   admin CRUD: users, roles, orgs, permissions, attributes,
│   │                         #   ad hoc views, alerts, options, caches
│   ├── reconcile.ps1         #   declarative environment applier (plan by default)
│   ├── doctor.ps1            #   environment preflight
│   ├── extract_lineage.py    #   asset + column-level lineage (OpenLineage out)
│   └── smoke_test.ps1        #   the 19-step regression gate
├── references/               # 20 deep-dive docs incl. the live WADL snapshot,
│   │                         #   JR7 schema/valid-elements, symptom-indexed gotchas,
│   │                         #   JSON Schemas for manifests/config/environment
├── tests/                    # Pester unit suite (lint rules, shared helpers)
├── baselines/                # golden PNGs for visual verification
├── fixtures/                 # seed inputs for the smoke test
└── chart_customizers/        # JFreeChart customizer jar (Actian gradient + trend line)
```

Two consumers sit on top of the same scripts:

- **Claude Code sessions** invoke them via `/jasper-deploy` (SKILL.md is the prompt-side
  index).
- **The self-service web wizard** (`webapp/jasper-wizard/`, a Jakarta servlet WAR)
  bundles the identical scripts inside `WEB-INF/scripts` and shells out to them — so the
  browser UI and the agent can never drift apart on behavior.

## 4. Chronology

| Phase | Dates | What was built |
|---|---|---|
| **Core pipeline** | Jun 1 | Scaffold → compile → deploy → run-to-PDF; `-Overwrite`; charts, spider/barcode/HTML5/FusionMaps components; CSV data adapters; bulk sample deployer |
| **Dashboards cracked** | Jun 2 | The defining discovery: a hand-built dashboard model PUT to the REST API stores fine (201) but **renders blank**. The fix — compose via export-inject-**import** — became `compose_dashboard.ps1` and a standing rule |
| **Verification blitz** | Jun 5 | Vendor REST docs distilled into a verified/doc-only endpoint map; destructive round-trips for import/export; jobs, permissions, input controls, attributes, alerts, saved options, Visualize.js embedding all proven live; parameters, groups, drill-down, crosstabs, subreports; the smoke test is born |
| **Scheduling + semantic layer** | Jun 10–16 | Job scheduling, data alerts, report templates; style templates (.jrtx), single-table Domains, ad hoc views, UI themes, non-JDBC + AWS datasources, cascading query controls, OLAP/Mondrian, users/roles/orgs admin, async execution, cache management |
| **Hardening + branding** | Jun 21–25 | `Assert-JrsOk`/`Invoke-JrsDownload` helpers; docx collateral generator; Actian-branded report defaults (centered titles, logo, gradient bars + trend line via a custom JFreeChart customizer jar); the Foodmart Sales Dashboard |
| **Guardrails as code** | Jun 26–29 | `lint_jrxml.ps1` becomes a **pre-deploy gate inside `deploy_report.ps1`**; `Get-GotchaHint` appends a symptom-matched fix pointer to every failed server call; column-level lineage via `sqlglot`; `reconcile.ps1` (declarative env applier) + `doctor.ps1` (preflight); Pester unit suite + `check_docs.ps1` CI guard |
| **Public-repo hardening** | Jul 9–10 | Repo refocused to Jaspersoft-only; every machine-specific path removed (config/env-var resolution with clear errors); secret-hygiene incident driven to resolution (history rewrite + rotation guidance); GitHub Actions CI (gitleaks full-history scan + the skill's own offline gates); Apache-2.0 license |

## 5. The lessons that shaped the design

Each of these cost real debugging time once, and can no longer recur:

| Discovery | Guardrail that now enforces it |
|---|---|
| JR7's strict Jackson parser rejects unknown jrxml/.jrtx/.jrdax elements as an opaque `400` at **fill** time — a clean local compile proves nothing | `lint_jrxml.ps1` runs automatically inside `deploy_report.ps1`; valid element names per construct were extracted from the JR 7.0.6 source annotations into `references/jr7-valid-elements.md` |
| JRS's SQL security validator rejects any report query not beginning with `SELECT` (CTEs → `JSSecurityException`) | SQL lint blocks a leading `WITH` at deploy time; the documented fix is rewriting CTEs as nested subqueries |
| Dashboards and ad hoc views **cannot be PUT** — they store but render blank / 500 | All composition goes through export-inject-import; the raw-PUT failure mode is documented so nobody "simplifies" it back |
| Chart plot properties are per-class (`line` vs `bar` vs `area` accept different attributes; area accepts none) | Lint rules per chart kind; captured in `references/gotchas.md` indexed by symptom |
| PowerShell 5.1 treats `?` as a variable character and mangles inline JSON quotes | Conventions baked into every script: `${base}` URL construction, JSON bodies passed to curl from files |
| A field `class` that mismatches the JDBC column type fails the fill | The scaffolder derives classes from live column introspection; hand-edits are flagged in SKILL.md |
| Anything hardcoded to one machine breaks everyone else | July hardening: paths resolve strictly via parameter → env var → config file, and error with guidance; CI secret-scans every push |

## 6. Quality gates, as they stand today

Local, on every change:

```
lint_jrxml.ps1  →  compile_jrxml.ps1  →  deploy_report.ps1 (lint gate inside)
                →  verify_report.ps1 (status / content / visual baseline)
                →  smoke_test.ps1 (offline prechecks + 19 live steps)
```

Continuous, on every push (`.github/workflows/ci.yml`):

- **gitleaks** — full-history secret scan
- **check_docs.ps1** — every SKILL.md/reference link resolves, every mapped script exists
- **Pester suite** — unit tests for the lint rules and shared helpers

Security posture: no credentials in the repo (config file gitignored; template committed),
resolution order params → env → config, and the skill's `references/security-and-config.md`
documents `passwordCommand`-style secret sourcing for shared environments.

## 7. By the numbers

| Metric | Value |
|---|---|
| Scripts | 44 (PowerShell + Python) |
| Reference docs | 20 (incl. live WADL snapshot, 3 JSON Schemas, symptom-indexed gotchas) |
| Smoke-test lifecycle steps | 19, each asserted, plus offline prechecks |
| Unit tests | Pester suite (lint rules, helpers) — runs in CI |
| Visual baselines | 3 golden PNGs |
| Build span | June 1 → July 10, 2026, across ~50 commits |
| Consumers | Claude Code sessions (`/jasper-deploy`) + the jasper-wizard web UI |

## 8. Reproducing the approach

The transferable method, product-agnostic:

1. Start with one verified happy path, not a framework.
2. Grow only by attempting real tasks against the real system.
3. Convert every failure into the strongest guardrail you can afford: note → reference →
   lint rule → hard gate.
4. Keep the agent-facing index lean; push depth into linked references, and make a CI
   check own their consistency.
5. Mark knowledge as verified vs. doc-only, and prefer the system's own introspection
   (the WADL, the source annotations) over vendor prose.
6. Build the regression gate in step with the surface area — never after.
