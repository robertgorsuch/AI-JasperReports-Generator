---
name: Feature request
about: Propose a new capability, script option, or reference addition
title: ''
labels: enhancement
assignees: ''

---

**Before filing:** check the capability map in
`plugins/jasper-deploy/skills/jasper-deploy/SKILL.md` — most "new" needs already have a
script or a reference (48 scripts, 25+ references). If a script almost does
what you need, name it below instead of proposing a new one. For anything
larger than a small option, file this issue BEFORE building — see
`plugins/jasper-deploy/skills/jasper-deploy/CONTRIBUTING.md` ("Before you start").

**Problem / use case**
What are you trying to accomplish, and what makes it hard or impossible
today? Concrete workflow beats abstract capability ("I need to deploy 40
reports with per-org permissions in one command" beats "bulk operations").

**Closest existing capability**
Which script/reference comes closest today, and where does it fall short?
(e.g. `deploy_report.ps1` handles X but not Y)

**Proposed solution**
What you would like to see — new script, new flag on an existing script,
reference addition, wizard feature. Sketch the invocation if you can:

```powershell

```

**Alternatives considered**
Other approaches you tried or rejected (including manual REST calls or
server-side configuration), and why they were not enough.

**Scope check**
- Target JasperReports Server version(s)/edition:
- Works over REST v2 only, or needs server-side/filesystem access?
- Cross-platform (Windows PowerShell 5.1 + pwsh on macOS/Linux) feasible?

**Willing to contribute?**
- [ ] I plan to open a PR for this myself (the definition-of-done
      checklists in CONTRIBUTING.md apply)
- [ ] I can test a contributed implementation against a live server
- [ ] Proposal only

**Additional context**
Anything else relevant (links, screenshots, related issues).
