# Jaspersoft Copilot — preflight module

The single shared chokepoint every `jasper-deploy` script sources before doing
work. Centralizing it here (one PowerShell module, one Python module) is the
**critical path** from the licensing scope doc: get this interface right, refactor
the ~25 scripts to source it, and entitlement / metering / guardrails all land at
once instead of being sprinkled per-script.

| File | For |
|---|---|
| `Entitlement.psm1` | PowerShell scripts (`deploy_report.ps1`, `compose_dashboard.ps1`, …) |
| `entitlement.py` | Python scaffolders (`scaffold_jrxml.py`, `gen_dashboard.py`, …) |

Both expose the same four concerns and share on-disk layout
(`~/.jaspersoft-copilot/{config.json,usage.ndjson,audit.ndjson}`) and the same
tier→feature map, so a PS deploy step and a Python scaffold step stay consistent.

## Interface

| Concern | PowerShell | Python |
|---|---|---|
| Gate | `Assert-CopilotEntitlement -Feature` | `assert_entitlement(feature)` |
| Check | `Test-CopilotFeature -Feature` | `test_feature(feature)` |
| Profile | `Get-CopilotProfile [-Name]` | `get_profile(name=None)` |
| Secret | `Resolve-CopilotSecret -Ref` | `resolve_secret(ref)` |
| Meter | `Write-CopilotUsage -Event -ResourceUri` | `write_usage(event, uri)` |
| Audit | `Write-CopilotAudit -Action -ResourceUri` | `write_audit(action, uri)` |
| Mutate | `Invoke-CopilotMutation -Action -ResourceUri { … }` | (wrap inline) |

## Wiring an existing script (example)

```powershell
Import-Module "$PSScriptRoot/../copilot/preflight/Entitlement.psm1"
Assert-CopilotEntitlement -Feature 'report.deploy'        # 1. gate
$p = Get-CopilotProfile                                    # 2. profile, not hardcoded localhost
Invoke-CopilotMutation -Action 'report.deploy' -ResourceUri $TargetUri {  # 4. dry-run + audit
    # existing REST PUT here, using $p.jrsUrl / Resolve-CopilotSecret $p.jrsSecretRef
}
Write-CopilotUsage -Event 'report.deployed' -ResourceUri $TargetUri        # 3. meter
```

## What is real vs. stubbed

**Real now:** config resolution, env overrides, profile lookup, `env:` secret
refs, dry-run (`CLAUDE_COPILOT_DRYRUN=1`), local NDJSON usage/audit buffering with
idempotency keys, the tier→feature map, the mutation wrapper (dry-run + confirm +
audit).

**Stubbed (`NotImplementedError` / stub-mode-allow):**
- `Get-CopilotEntitlement` / `get_entitlement` — signature verification (WS1).
  Until implemented, `Test-CopilotFeature` returns `$true` (allow-all) so
  development isn't blocked. **Flip to deny before shipping.**
- `vault:` / `keychain:` secret backends (WS2).
- Metering transport — events buffer locally; batched POST + flush job is WS3 (P1).

See `../../JASPERSOFT_COPILOT_LICENSING_SCOPE.md` for the workstream (WS) numbers.
