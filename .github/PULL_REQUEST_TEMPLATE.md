<!--
One focused change per PR. Commit style: "component: summary" first line.
Redact all credentials, real hostnames/IPs, and org names from descriptions
and logs. Full guidelines: .claude/skills/jasper-deploy/CONTRIBUTING.md
-->

## What and why

<!-- What does this PR change, and why? Link the issue if one exists. -->

Closes #

## Change type

<!-- Check all that apply, then complete the matching checklist(s) below.
     Delete the checklists that do not apply. -->

- [ ] Script (new or changed) in `scripts/`
- [ ] Reference / documentation
- [ ] Gotcha (symptom + fix)
- [ ] jrxml construct / template / fixture
- [ ] Other (repo tooling, CI, webapp)

## Definition of done

### Script (new or changed)

- [ ] Uses `_jrs_common.ps1` helpers (`Get-JrsCurl` / `Get-JrsPython` /
      `Get-JrsNull`); no hardcoded `curl.exe`, `python`, `NUL`, or `\` paths
- [ ] Credential resolution follows the standard order (params, env vars,
      `jrs.config.json`); no hardcoded environment specifics
- [ ] Pester test added/updated in `tests/`; passes offline
- [ ] Capability-map row in `SKILL.md` + section in the matching
      `references/*.md`
- [ ] `smoke_test.ps1` passes against a live server
      — or explain below why it could not be run
- [ ] Parameters or stdout shape changed: jasper-wizard handler checked
      (`references/admin-and-scheduling.md`, "Web wizard") — or N/A

### Reference / documentation

- [ ] `& scripts/check_docs.ps1` passes
- [ ] Doc-derived claims keep their source citation (PDF name + page);
      `[doc-only]` vs verified labeling preserved
- [ ] Generated docs are 7-bit ASCII (no em dashes, curly quotes, arrows)

### Gotcha

- [ ] Entry in `references/gotchas.md` with the LITERAL symptom text (the
      search key), the cause, and the fix
- [ ] If the linter could have caught it: rule added to `lint_jrxml.ps1`
      + test — or N/A

### jrxml construct / template / fixture

- [ ] `lint_jrxml.ps1` passes on every changed `.jrxml` / `.jrtx` / `.jrdax`
- [ ] Compiles (`compile_jrxml.ps1`) and deploys + fills on a live server
- [ ] Query begins with `SELECT` (no leading `WITH`); field `class` matches
      JDBC column types
- [ ] Exemplar added to `fixtures/`; visual baseline via `pdf_verify.py` if
      render-sensitive — or N/A

## Always (every PR)

- [ ] No credentials, tokens, license files, or real hostnames/IPs added
      (gitleaks CI must stay green)
- [ ] Derived artifacts regenerated from source, not hand-edited
      (baselines, docx renders) — or N/A
- [ ] Focused on one change; commit messages follow `component: summary`

## Test evidence

<!-- Paste the relevant output: check_docs PASS line, Pester summary,
     smoke_test result. If smoke_test.ps1 could not run (e.g. no live
     JasperReports Server available), say so explicitly here. -->

```

```
