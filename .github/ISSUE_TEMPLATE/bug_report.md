---
name: Bug report
about: A script fails, a jrxml will not deploy/fill, or a reference doc is wrong
title: ''
labels: bug
assignees: ''

---

**Before filing:** search existing issues and check
`.claude/skills/jasper-deploy/references/gotchas.md` — it is indexed by
symptom and your error may already have a documented fix. One issue per
problem. **Redact all credentials, real hostnames/IPs, and org names.**

**What you ran**
The exact command line (credentials redacted):

```powershell

```

**What happened**
Full error output. For deploy/fill failures, include the SERVER RESPONSE
BODY, not just the script output — that is where the real error lives:

```

```

**What you expected**
A clear description of what you expected to happen.

**Environment**
- OS:
- PowerShell version (`$PSVersionTable.PSVersion`):
- JasperReports Server version + edition (`GET /rest_v2/serverInfo`):
- JDK version (`java -version`):
- Python version (`python --version`):

**Artifacts**
The offending `.jrxml` / `.jrtx` / manifest if shareable, or a minimal
reproduction built from `.claude/skills/jasper-deploy/fixtures/` or
`report/samples/`.

**Additional context**
Anything else relevant (recent upgrade, custom theme, proxy/SSL setup, ...).
