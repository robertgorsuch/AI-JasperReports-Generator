# Changelog — jasper-deploy plugin

## 1.2.0 (2026-08-28)

Driven by the POS suite build/promotion sessions (Aug 20-27): every manual loop
that recurred in RUNBOOK.md is now a script, and the helper traps that caused
silent misreads are fixed.

### New scripts
- `verify_suite.ps1`: one read-only script for the "verify the build on STAGE
  without a browser" loop (report units exist / render code+bytes+pages /
  server-vs-git jrxml byte-diff / dashboard exists + input-control count vs
  manifest `filters`); `-Env` profiles, csv/json output, `-Offline` preflight,
  non-zero exit on any FAIL. Replaces five hand-written RUNBOOK recipes.
- `ensure_controls.ps1`: declarative, idempotent input-control creation from a
  JSON spec or a manifest `controls` key (types 1-7, LOV/query/dataType
  sub-resources, `-Update`, `-WhatIf`, `-Env`); generalises the four ad hoc
  `scripts/pos_perf/*_controls.ps1` scripts. Example: `fixtures/controls.example.json`.

### Promotion and recompose
- `promote.ps1`: manifest mode (`-Manifest <file|dir|glob> -FromEnv/-ToEnv
  [-WhatIf] [-EnsureControls] [-Backup]`) replays the PROD promotion in
  dependency-safe order: teardown -> folders -> controls -> distinct tiles
  (deploy_report -Overwrite, or export+import) -> re-attach controls ->
  compose -Replace. `-WhatIf` prints the full plan with target state and a
  byte-level jrxml comparison and issues GETs only. `-Uri` mode unchanged.
- `compose_dashboard.ps1`: explicit `-Replace` (idempotent delete+import
  transaction logged as [1/3] backup -> [2/3] delete -> [3/3] import), `-Env`,
  `-EnsureControls`; surfaces the fix on 403 `resource.in.use` /
  `import.decode.failed`; returns `{Uri, Code, Replaced, BackupPath, ...}`.
- `sync_manifest_from_dashboard.ps1` / `sync_manifest.py`: round-trip the
  designer presentation keys and the filter group (docked/floating, strip
  height); `-Manifest`/`--merge` update a manifest in place preserving key
  order; `-WhatIf`/`--dry-run` print a diff. gen -> sync -> gen is a fixed point.
- `gen_dashboard.py` honours `filterStripHeight`.
- `manifest.schema.json`: `controls` key, filter-group keys, per-dashlet
  `showTitleBar`/`resource`/`jrxml`/`controls`; `dataSourceUri` no longer required.

### Helper ergonomics
- `_jrs_common.ps1`: `Test-JrsResource` ([bool], HTTP 200 only) and
  `Assert-JrsResource` so existence checks no longer silently pass on
  `Invoke-JrsGet`'s non-throwing 404; `Get-JrsDashboardsReferencing`,
  `New-JrsDeployResult`; `Invoke-JrsDownload -TimeoutSec`.
- `deploy_report.ps1`: emits a `{Uri, Code, Status, ControlsAttached, Message}`
  result object on the pipeline (Write-Host is not captured by `2>&1` under
  PS 5.1); explains `resource.in.use` with the referencing dashboard(s) and
  the two fixes; accepts `-Env`.

### Preflight, lint, scaffold, CI guards
- `doctor.ps1`: SHA-256-compares the server's chart-customizer jar with the
  bundled one (WARN STALE + copy/restart steps); reads the real repository-DB
  port from `META-INF/context.xml` / `js.jdbc.properties` and cross-checks
  `repoDb` (bundled Postgres is often on 5433; never assume 5432); probes every
  `environments` profile and prints its version; new `jrsWebappDir` config key
  and `-ConfigPath`.
- `scaffold_jrxml.py --dialect x100`: static pre-compile check refuses ordered
  aggregates / ordered aggregate windows, correlated columns inside aggregates
  in subqueries, and `;` inside SQL comments (exit 3, nothing written);
  `--allow-dialect-warnings`, `--check-only`, `check_dialect_sql()` exported.
  Missing psql now exits 2 cleanly. Default postgres behaviour unchanged.
- `lint_jrxml.ps1 -Manifest`: manifest lint (missing `filterFloating` with
  `filters` -- the STAGE/PROD divergence after a8503f2 -- dashlets outside
  `folder`, duplicate dashlet names, invalid JSON / missing keys).
- `check_docs.ps1` check 5: junction guard -- fails if anything under
  `.claude/skills/jasper-deploy` is tracked in git (cf. f2184cf) or a real
  directory copy diverges from the plugin skill.

### References
- `gotchas.md` restructured into a symptom -> fix index (tables per area,
  stable G-ids, Where links); 582 -> 235 lines. Detail moved to its owner:
  G1-G14 -> `jr7-schema.md`; G25-G26, G33-G48, G50-G54 -> `jrs-rest-api.md`;
  G27-G32b -> `data-and-semantic-layer.md`.
- New gotchas G55-G59: area plot takes neither tick nor showLines/showShapes;
  PS 5.1 ConvertTo-Json single-element unwrap; inputControl type-code table;
  same-named metric differs across period windows (31.6 vs 33.7 gross margin);
  bundled metadata Postgres on a non-default port. G5: customizer jar must stay
  in WEB-INF/lib.
- New `x100-sql.md` (X100 engine restrictions + sql.ps1 splitter/export traps);
  `server-administration.md` "Preflight: doctor.ps1"; `ci-smoke.md`
  verify_suite; `dashboards.md` / `dashboard-model.md` replace transaction,
  ensure_controls, promote manifest mode, in-place sync, `controls` key.

### Tests
- New: `deploy_report`, `verify_suite`, `promote`, `sync_manifest`,
  `check_docs`, `doctor` Pester suites; `test_scaffold_jrxml.py` (18 cases,
  wired into CI on both OS legs); `_jrs_common` and `lint_jrxml` suites extended.

## 1.1.0 (2026-08-07)

### Packaging
- The plugin now ships only its own payload. Previously `source: "./"` cloned
  the entire working repository (~266 files) into every install — demo report
  suites, census loader scripts, a 239 KB sample SQL dump, workspace docs, a
  runtime lock file, and a repo-root `.claude/settings.json` that enabled
  unrelated plugins on installers' machines. The plugin source is now
  `plugins/jasper-deploy/` (skill + commands + manifests only).
- Skill moved from `.claude/skills/jasper-deploy/` to
  `plugins/jasper-deploy/skills/jasper-deploy/`.

### New: slash commands
- `/jasper-deploy:doctor` — preflight the toolchain and server connectivity
- `/jasper-deploy:smoke` — run the full 24-step smoke test
- `/jasper-deploy:deploy` — scaffold/compile/deploy a report and verify it
- `/jasper-deploy:promote` — promote a resource between environments

### SKILL.md
- Frontmatter description cut from ~2.4 KB to ~0.6 KB (it is injected into
  every session's skill list; the capability detail lives in the body).
- Machine-specific facts (server ports, install paths, local PDF doc corpus)
  moved out of SKILL.md into an optional, gitignored `LOCAL.md` overlay that
  the skill reads when present. SKILL.md is now environment-neutral; new
  environments start with `jrs.config.example.json` + `doctor.ps1`.
- Happy-path example now derives server URL and credentials from
  `jrs.config.json` instead of a hardcoded localhost URL.

### CI
- Re-enabled the offline skill checks (doc/link consistency + Pester unit
  tests) on pull requests, now on a windows-latest + ubuntu-latest matrix —
  the ubuntu/pwsh leg backs the cross-platform claim in SKILL.md.
- Added a plugin-manifest sanity step (marketplace source path + payload).

## 1.0.0 (2026-08-05)

- Initial release: jasper-deploy skill (49 scripts, 29 reference files,
  lint gate, smoke test, Pester tests) packaged as an installable Claude Code
  plugin with the jaspersoft-tools marketplace.
