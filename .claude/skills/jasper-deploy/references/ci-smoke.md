# Running smoke_test.ps1 as recurring regression CI

`scripts/smoke_test.ps1` is the skill's end-to-end regression test. Run it after
editing ANY script (it exercises the whole pipeline against the live
JasperReports Server and PostgreSQL on this machine). This note covers running it
on a schedule so regressions surface without a human remembering to run it.

## What it covers (19 asserted steps)
Per `SKILL.md`, the test scaffolds -> **lints** (`lint_jrxml.ps1`) -> compiles -> deploys (+ an input control) ->
verifies content -> runs to PDF -> schedules a job (CRUD) -> sets an alert (CRUD)
-> composes a dashboard (report + text tile) -> deploys a **style template** and
runs a report that references it -> creates a single-table **Domain** -> creates
a multi-table **Domain with a join** -> creates a non-JDBC (**jndi**) datasource
-> deploys a UI **theme** -> creates an **AWS** datasource -> deploys a report
with **cascading query input controls** (asserts the child option count changes
per parent) -> sets + clears **permissions** -> server **attribute** CRUD ->
creates a **Mondrian** schema + connection -> scaffolds a **Visualize.js embed**
page (offline content check) -> creates a datasource with **`-Test`** (the
`/contexts` service opens the live connection first) -> fetches a report
**thumbnail** -> runs a **diagnostic collector** lifecycle (start/stop/download
zip/delete) -> tears down. It asserts each of the **24 steps** under a throwaway
`/reports/_smoke` folder (the theme lives under `/themes`), and cleans
everything up at the end. When the **jasper-wizard** WAR is deployed
next to JRS an extra `wizard-api` step also runs (GET `/jasper-wizard/api/health`,
`/api/summary`, `/api/datasources` must all return 200); on machines without the
wizard it is skipped, not failed.

## Prerequisites for a fresh clone
Before the test can pass on a freshly cloned machine, two things must already be
set up (the test does not create them):
1. `jrs.config.json` in the skill root -- copy `jrs.config.example.json` to
   `jrs.config.json` and fill in the password (`superuser`) and `jrLibDir`. It is
   gitignored. See `SKILL.md` (Credentials).
2. The two sample databases AND their JRS datasource bindings -- `foodmart`
   (`/public/Samples/Data_Sources/FoodmartDataSource`) and `postgis_34_sample`
   (`/datasources/postgis_34_sample`). See **`references/seed-data.md`** for load
   and verification steps.

The test also needs `$env:PGPASSWORD` set (the DB password, `postgres`) in the
environment it runs under, because the scaffolders shell out to `psql`.

## Manual run
```powershell
$env:PGPASSWORD = "postgres"
& .\.claude\skills\jasper-deploy\scripts\smoke_test.ps1
```

## Windows Task Scheduler (recurring local CI)
Register a daily task that sets `PGPASSWORD`, runs the smoke test, and writes a
**timestamped log artifact** so you can see when a regression first appeared. The
inner command sets the env var, cd's to the repo, and tees output to a per-run
log; the task's own exit code is the test's pass/fail.

```powershell
# set to your checkout location
$repo = "C:\path\to\your\checkout"
$logDir = "$repo\out\smoke-logs"
New-Item -ItemType Directory -Force $logDir | Out-Null

# the command Task Scheduler will run (PowerShell -Command); %DATE/TIME via PS at run time
$inner = '$ts = Get-Date -Format yyyyMMdd_HHmmss; ' +
         '$env:PGPASSWORD = "postgres"; ' +
         "Set-Location '$repo'; " +
         "& '$repo\.claude\skills\jasper-deploy\scripts\smoke_test.ps1' " +
         "*>&1 | Tee-Object -FilePath '$logDir\smoke_'+\$ts+'.log'; " +
         'exit $LASTEXITCODE'

schtasks /Create /TN "jasper-deploy smoke" /SC DAILY /ST 06:30 /RL HIGHEST /F `
  /TR ("powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"" + $inner + "\"")

# run it once on demand / inspect / remove:
schtasks /Run    /TN "jasper-deploy smoke"
schtasks /Query  /TN "jasper-deploy smoke" /V /FO LIST
schtasks /Delete /TN "jasper-deploy smoke" /F
```
Notes:
- `*>&1` redirects all PowerShell streams (incl. the harmless SLF4J-on-stderr)
  into the log so a non-zero stream does not abort under a strict caller.
- Each run writes `out\smoke-logs\smoke_<timestamp>.log`; keep or prune those as
  your artifact history.
- `/RL HIGHEST` is needed because parts of the pipeline (and any chart-customizer
  jar reinstall) may require elevation; the JRS service must be running.
- Store the DB password in the task command (above) or, more safely, as a
  machine env var the task inherits, rather than committing it.

## macOS / Linux (recurring local CI via cron)
On macOS/Linux run the same smoke test under `pwsh` from `cron` (or a `launchd`
agent). Add a crontab line (`crontab -e`) that sets the DB password, cd's to the
repo, and tees a timestamped log:
```sh
30 6 * * *  PGPASSWORD=postgres /usr/local/bin/pwsh -NoProfile \
  -File "$HOME/tx-geocoder/.claude/skills/jasper-deploy/scripts/smoke_test.ps1" \
  > "$HOME/tx-geocoder/out/smoke-logs/smoke_$(date +\%Y\%m\%d_\%H\%M\%S).log" 2>&1
```
(`brew install powershell` provides `pwsh`; use `which pwsh` for its path. The JRS
server and PostgreSQL must be running on this host.)

## Claude Code drivers (cloud + interval)
The same test can be driven by Claude Code's scheduling primitives instead of (or
in addition to) Task Scheduler:
- **`/schedule`** -- a cloud cron "routine" that runs on a schedule. Useful for a
  managed, off-machine cadence; the routine's prompt would set `$env:PGPASSWORD`
  and invoke `scripts/smoke_test.ps1`, then report pass/fail. (Cloud agents do not
  have this machine's localhost JRS/PostgreSQL, so use `/schedule` to remind/kick
  a run on this host, with the actual execution happening here.)
- **`/loop`** -- run the test (or a slash command wrapping it) on a recurring
  local interval during a session, e.g. poll after each change.

## Cross-references
- `references/seed-data.md` -- the sample DBs + bindings the test assumes.
- `SKILL.md` (Notes / gotchas -> "Smoke test") -- the authoritative step list.
