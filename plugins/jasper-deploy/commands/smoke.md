---
description: Run the full 24-step jasper-deploy smoke test (offline checks + server lifecycle)
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/jasper-deploy/SKILL.md` (and `LOCAL.md` next
to it if present). Ensure `$env:PGPASSWORD` is set (see SKILL.md Conventions),
then run:

```powershell
& "${CLAUDE_PLUGIN_ROOT}/skills/jasper-deploy/scripts/smoke_test.ps1"
```

It runs offline prechecks (doc consistency + Pester unit tests) and then the
full server lifecycle under a throwaway `/reports/_smoke` folder. Report the
result step by step. On a failure, look the symptom up in
`${CLAUDE_PLUGIN_ROOT}/skills/jasper-deploy/references/gotchas.md` before
diagnosing from scratch, and quote the matching entry if one exists.
