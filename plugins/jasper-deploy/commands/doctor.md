---
description: Preflight-check the JasperReports toolchain and server connectivity
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/jasper-deploy/SKILL.md` (and `LOCAL.md` next
to it if present), then run the environment preflight:

```powershell
& "${CLAUDE_PLUGIN_ROOT}/skills/jasper-deploy/scripts/doctor.ps1"
```

Interpret the output for the user: list what passed, and for each failure give
the concrete fix (missing tool → install command for their OS; missing
`jrs.config.json` → copy `jrs.config.example.json` and fill in; unreachable
server → check URL/port/credentials). If everything passes, say the environment
is ready and suggest `/jasper-deploy:deploy` for a first report.
