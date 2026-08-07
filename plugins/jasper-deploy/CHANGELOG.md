# Changelog — jasper-deploy plugin

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
