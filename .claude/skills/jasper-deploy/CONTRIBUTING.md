# Contributing to the jasper-deploy skill

jasper-deploy automates the design / compile / deploy pipeline for
JasperReports Server (REST v2): scaffolding JR7 jrxml from SQL, deploying
reports and dashboards, datasources, Domains, OLAP, themes, scheduling,
permissions, environment promotion, and a doc-derived reference library
covering JRS 4.7 through 10.1.

These guidelines keep contributions mergeable on the first pass — for you,
that means a clear definition of "done"; for maintainers, it means no
rejected-and-resubmitted round trips.

## Skill layout (where your change goes)

| Path | What lives there | Contribution rule |
|---|---|---|
| `SKILL.md` | Lean index: conventions, capability map, happy paths | Every new/changed script gets a capability-map row; deep detail does NOT go here |
| `scripts/` | PowerShell + Python automation (48 scripts) | Cross-platform, credential-free, follows `_jrs_common.ps1` helpers |
| `references/` | Per-area deep docs, verified notes, gotchas | Every capability row points at one; keep `[doc-only]` vs verified labeling |
| `references/version-archive/` | Per-era distillations of the vendor PDF corpus | Page-cited facts only; note contradictions, do not resolve them silently |
| `tests/` | Pester unit tests (offline) | New script logic gets a test; must pass without a live server |
| `fixtures/` | Exemplar jrxml/manifests | Add an exemplar when you add a new construct |
| `baselines/` | PNG visual baselines for `verify_report.ps1 -Baseline` | Regenerate, never hand-edit |
| `jrs.config.example.json` | Config template | Add new keys here with placeholder values; real `jrs.config.json` is gitignored |

## Security and secrets (read first)

**The repository is public.** CI runs a full-history gitleaks scan on every
push and PR — but do not rely on it to catch you.

- Never commit passwords, tokens, license files, service-account JSON, or
  real server hostnames/IPs. `jrs.config.json` and `docs/` are gitignored
  on purpose; do not force-add them.
- Credentials resolve in this order — keep the pattern for anything new:
  script parameters, then `JRS_URL`/`JRS_USER`/`JRS_PASS` env vars, then
  `jrs.config.json` (copied from the example, gitignored). A
  `passwordCommand` hook exists for secret managers.
- Redact URLs, usernames, and org names from logs in issues and PRs.
- Vulnerabilities: report privately (GitHub Security Advisories), not as a
  public issue.

## Development environment

Scripts run on Windows PowerShell 5.1 and PowerShell 7 (`pwsh`) on
Windows/macOS/Linux. You need: JDK 11+, `psql` 14, `curl` 8.x, Python 3
with `sqlglot` + `pypdfium2`, a local JasperReports 7.0.6 jar directory
(`jrLibDir` in config or `JR_LIB_DIR`), and for live testing a reachable
JasperReports Server + PostgreSQL. Verify readiness:

```powershell
& scripts/doctor.ps1
```

## The non-negotiable conventions

1. **JR7-native jrxml only.** The JR7 schema is not 6.x compatible; the
   server's strict Jackson parser rejects unknown elements at fill time as
   an opaque 400. Always lint: `& scripts/lint_jrxml.ps1 -Path <file>`.
   Valid element names per construct: `references/jr7-valid-elements.md`.
2. **Report queries begin with `SELECT`.** A leading `WITH` is rejected by
   the server's SQL validator at fill time; rewrite CTEs as nested
   subqueries and verify the rewrite in psql first.
3. **Cross-platform or it does not merge.** Use `Get-JrsCurl` /
   `Get-JrsPython` / `Get-JrsNull` / `Test-JrsWindows` from
   `_jrs_common.ps1` — never hardcode `curl.exe`, `python`, or `NUL`. Use
   `/` path separators. PS 5.1 quirks are load-bearing: `${var}` braces in
   URLs, JSON bodies to curl via file (`--data "@req.json"`), never inline.
4. **Never PUT dashboards or ad hoc views** — export-inject-import only
   (`compose_dashboard.ps1`, `manage_adhoc.ps1`). A raw PUT stores 201 but
   renders blank or 500s.
5. **Generated docs are 7-bit ASCII.** No em dashes, curly quotes,
   box-drawing, or unicode arrows in `references/*.md`.
6. **Field `class` matches the JDBC column type** in any jrxml you touch.

## Definition of done (per change type)

**New or changed script**
- [ ] Uses `_jrs_common.ps1` helpers; credential resolution follows the
      standard order; no hardcoded environment specifics
- [ ] Pester test added/updated in `tests/`; passes offline
- [ ] Capability-map row in `SKILL.md` + section in the matching
      `references/*.md`
- [ ] `smoke_test.ps1` passes against a live server (it runs check_docs +
      Pester first, then the ~24-step lifecycle under `/reports/_smoke`)
- [ ] If parameters or stdout shape changed: the jasper-wizard handler that
      calls the script is checked (`references/admin-and-scheduling.md`,
      "Web wizard")

**Reference/doc change**
- [ ] `& scripts/check_docs.ps1` passes (validates every link, script
      reference, and count — staleness is a rejected PR)
- [ ] Doc-derived claims keep their source citation (PDF name + page);
      `[doc-only]` vs verified labeling preserved
- [ ] ASCII-only

**Gotcha contribution** (you hit an opaque JRS error and found the fix)
- [ ] Entry added to `references/gotchas.md` with the literal symptom text
      (that is the search key), the cause, and the fix
- [ ] If the linter could have caught it: rule added to `lint_jrxml.ps1`
      + test

**New jrxml construct or template**
- [ ] Lints clean; compiles (`compile_jrxml.ps1`); deploys and fills on a
      live server
- [ ] Exemplar added to `fixtures/`; visual baseline via `pdf_verify.py`
      if render-sensitive

## Opening a useful issue

Search existing issues first, then include:

1. Exact command line (credentials redacted)
2. Full error output — for deploy/fill failures include the SERVER RESPONSE
   BODY, not just the script output; that is where the real error lives
3. Expected behavior
4. Environment: OS, `$PSVersionTable.PSVersion`, JRS version + edition from
   `GET /rest_v2/serverInfo`, JDK and Python versions
5. The offending jrxml/manifest if shareable, or a minimal repro built from
   `fixtures/`

Check `references/gotchas.md` before filing — your symptom may already have
a documented fix. One issue per problem.

## Submitting a well-formed pull request

- Branch from `main`; one focused change per PR.
- Commit style: `component: summary` first line, body explaining what and
  why (see `git log` for examples).
- Include the relevant "definition of done" checklist in the PR
  description, checked off. If `smoke_test.ps1` could not run (no live
  server), say so explicitly — do not skip silently.
- Regenerate derived artifacts from source (baselines, docx renders); never
  hand-edit them.
- CI (gitleaks secret scan) must be green before review starts.

## Review process

- Feedback will reference the conventions above; "the linter passes but
  the convention is broken" is still a change request.
- Small, well-described PRs merge fastest — by design.
- Be respectful and constructive; disagreements are about code, not people.

By contributing you agree your contributions are licensed under the terms
in the repository's [LICENSE](../../../LICENSE).
