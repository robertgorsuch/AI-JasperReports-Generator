---
description: Promote a repository resource between environments (e.g. STAGE to PROD)
argument-hint: [resource URI] [from-env] [to-env]
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/jasper-deploy/SKILL.md` (and `LOCAL.md` next
to it if present), plus the promotion sections of
`references/security-and-config.md` and `references/dashboards.md`.

Arguments given: `$ARGUMENTS`

Use `promote.ps1` with `-FromEnv`/`-ToEnv` named environment profiles. Before
promoting:
1. Confirm the resource URI exists in the source environment
   (`export_resource.ps1` or a GET).
2. If either environment name is missing from the arguments, ask rather than
   guessing — promotion writes to the target server.
3. Offer `-Backup` semantics: export the current target version first so the
   promotion is reversible.

After promoting, verify the resource renders in the target environment and
report both the export and import results.
