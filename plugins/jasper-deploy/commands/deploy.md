---
description: Scaffold/compile/deploy a report to JasperReports Server and verify it renders
argument-hint: [jrxml path or SQL query] [target repo URI]
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/jasper-deploy/SKILL.md` (and `LOCAL.md` next
to it if present) and follow its "core happy path".

Arguments given: `$ARGUMENTS`

- If the argument is an existing `.jrxml` file, skip scaffolding and start at
  the compile step.
- If it is a SQL query (or the user described the report in words), scaffold
  first with `scaffold_jrxml.py` (flags in `references/reports.md`).
- Deploy with `deploy_report.ps1` (the lint gate runs automatically — do not
  skip it), then verify with `verify_report.ps1` / run-to-PDF and report the
  HTTP status and output location.
- No target URI given → ask where in the repository the report should live
  before deploying.
- On any 400 at fill time, check `references/gotchas.md` first (strict-Jackson
  and leading-`WITH` SQL are the usual culprits).
