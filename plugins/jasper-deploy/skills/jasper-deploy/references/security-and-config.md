# Security, secrets, and portability

How the skill resolves connection settings, how to avoid plaintext secrets, and
what is / is not portable off this Windows + PowerShell 5.1 machine.

## Credential resolution (every script)
`Resolve-JrsConfig` (in `scripts/_jrs_common.ps1`) resolves each of server URL,
user, and password independently, first match wins:

1. Script parameter (`-ServerUrl` / `-User` / `-Password`)
2. Named environment profile, when one is active via `-Env` / `$env:JRS_ENV`
   (profile keys shadow the top level; process env vars are then skipped --
   see "Named environment profiles" below)
3. Environment variable (`JRS_URL` / `JRS_USER` / `JRS_PASS`)
4. `jrs.config.json` in the skill root (`serverUrl` / `user` / `password`)
5. (password only) `passwordCommand` in the profile or `jrs.config.json` -- see below

`jrLibDir` (local compile/render jar dir) follows the same idea:
`-LibDir` -> `$env:JR_LIB_DIR` -> `jrs.config.json` `jrLibDir` -> machine default.

## Named environment profiles (STAGE / PROD)
`jrs.config.json` may define an `environments` object of named profiles; select
one with a script's `-Env <name>` parameter or `$env:JRS_ENV` (which works for
**every** script, since resolution happens inside `Resolve-JrsConfig`):

```jsonc
{
  "serverUrl": "http://localhost:8081/jasperserver-pro",   // default = stage
  "user": "superuser",
  "passwordCommand": "...",
  "environments": {
    "stage": { "serverUrl": "http://localhost:8081/jasperserver-pro" },
    "prod":  { "serverUrl": "http://prod-host:8080/jasperserver-pro",
               "passwordCommand": "(Get-StoredCredential -Target jrs-prod).GetNetworkCredential().Password" }
  }
}
```

Rules:
- A profile may carry any connection key (`serverUrl`, `user`, `password`,
  `passwordCommand`, `dataSourceUri`); keys it omits fall through to the
  top level, so a shared `user` need not be repeated.
- While a profile is active the `JRS_URL`/`JRS_USER`/`JRS_PASS` env vars are
  **ignored** -- a stale shell export cannot silently retarget a named
  environment. Explicit script params (`-ServerUrl` etc.) still override.
- Cross-server scripts take profile pairs: `promote.ps1 -Uri /reports/x
  -FromEnv stage -ToEnv prod` (the target must come from `-ToEnv` or the full
  `-To*` triple). `export_resource.ps1`, `import_resource.ps1`,
  `diff_resource.ps1`, and `reconcile.ps1` take a single `-Env`.
- An unknown profile name throws, listing the defined names.

## Avoiding a plaintext secret on disk
Pick whichever fits your environment:

- **Env-only (no file).** Do not create `jrs.config.json`; export the three env
  vars in the shell/session instead:
  ```powershell
  $env:JRS_URL  = "http://localhost:8081/jasperserver-pro"
  $env:JRS_USER = "superuser"
  $env:JRS_PASS = "superuser"
  ```
  Good for CI and for never persisting the secret.

- **`passwordCommand`.** Keep `serverUrl`/`user` in `jrs.config.json` but omit
  `password`; set `passwordCommand` to a PowerShell command whose stdout is the
  secret. It runs only when no `-Password` / `$env:JRS_PASS` / `password` is set,
  so the secret lives in a vault / Windows Credential Manager, not the file:
  ```jsonc
  {
    "serverUrl": "http://localhost:8081/jasperserver-pro",
    "user": "superuser",
    "passwordCommand": "(Get-StoredCredential -Target jrs).GetNetworkCredential().Password"
  }
  ```
  (Any command that prints the password works -- a vault CLI, `cmdkey`, etc.)

- **Always gitignore `jrs.config.json`.** It is already in the skill `.gitignore`;
  `jrs.config.example.json` (no real secret) is the committed template.

## Least-privilege server account
`superuser` is convenient for this dev box but is the JRS root admin. For shared
or prod use, create a dedicated deploy account (see `manage_users.ps1` /
`manage_roles.ps1`) scoped to the target folders with repository read/write +
execute, and point the config/env at that account instead. The web wizard
(`webapp/jasper-wizard/`) publishes with stored admin creds and runs user SQL --
keep it behind the JRS login / a network boundary (it is an internal tool).

## Portability (PowerShell 7 / non-Windows) -- current status
The scripts target **Windows PowerShell 5.1** and are exercised there by
`smoke_test.ps1`. Known realities:

- **`curl.exe`** is invoked explicitly (not the `Invoke-WebRequest` alias), so it
  also works under **PowerShell 7 (pwsh) on Windows**; on Linux/macOS `curl` is
  the system binary -- the calls are written as `curl.exe`, so a non-Windows port
  would alias or adjust that.
- **PS 5.1-isms the scripts deliberately handle** (and which remain correct on
  PS7): build URLs with `${base}` braces because `?` is a variable-name char;
  pass JSON bodies to curl from a file (`--data "@req.json"`), not inline; emit
  single-element JSON arrays by hand (PS5.1 `ConvertTo-Json` scalar-unwraps them).
  See `references/gotchas.md` (REST / PowerShell section).
- **Hardcoded paths** are confined to defaults that are all overridable via config
  or env (`jrLibDir`/`JR_LIB_DIR`; DB host/user/password via script params +
  `$env:PGPASSWORD`). The JR runtime jars, JDK, and the JRS install path are
  machine-specific; set `jrLibDir` (and the DB params) on a fresh clone -- run
  `scripts/doctor.ps1` to confirm the environment before deploying.
- Python helpers (`scaffold_*.py`, `extract_lineage.py`) are stdlib-only except
  `extract_lineage.py`'s optional `sqlglot` (column lineage) and the visual-diff
  `pypdfium2`/`Pillow`; all degrade gracefully when a dep is absent.

Not yet done: a full pwsh-7 / cross-platform test pass. The scripts are believed
PS7-compatible on Windows but are only CI-verified on 5.1.
