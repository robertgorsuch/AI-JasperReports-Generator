<#
.SYNOPSIS
  Jaspersoft Copilot — shared preflight module (PowerShell).

.DESCRIPTION
  The single chokepoint every jasper-deploy script must source before doing work.
  Provides four cross-cutting concerns in one place so they are applied uniformly:

    1. Entitlement  — Assert-CopilotEntitlement / Test-CopilotFeature
    2. Profiles     — Get-CopilotProfile / Resolve-CopilotSecret
    3. Metering     — Write-CopilotUsage  (billable events)
    4. Guardrails   — Invoke-CopilotMutation / Write-CopilotAudit / -DryRun

  STATUS: STUB. Signature verification, secret-vault, and the metering transport
  are intentionally NotImplemented — the scaffolding, config resolution, dry-run,
  and local event/audit buffering are real so callers can be wired up today.

  Usage in a script (e.g. deploy_report.ps1), at the top:
      Import-Module "$PSScriptRoot/../copilot/preflight/Entitlement.psm1"
      Assert-CopilotEntitlement -Feature 'report.deploy'
      ...
      Invoke-CopilotMutation -Action 'report.deploy' -ResourceUri $TargetUri -ScriptBlock {
          # the actual REST PUT
      }
      Write-CopilotUsage -Event 'report.deployed' -ResourceUri $TargetUri
#>

Set-StrictMode -Version Latest

# --------------------------------------------------------------------------
# Module-scope config. Resolved once, lazily, on first use.
# --------------------------------------------------------------------------
$script:CopilotConfig = $null

# Tier -> feature capability map. The license carries the tier; this maps it to
# the operations a caller may perform. Keep in sync with entitlement.py.
$script:CopilotFeatureMap = @{
    starter    = @('report.scaffold','report.compile','report.deploy','report.verify')
    pro        = @('domain.create','dashboard.publish','theme.deploy','control.create',
                   'job.schedule','alert.create')
    enterprise = @('resource.promote','admin.users','admin.roles','admin.orgs',
                   'dataplane.load','dataplane.sql.write','resource.delete')
}

function Get-CopilotConfig {
    <# Resolve config once: env CLAUDE_COPILOT_HOME, else ~/.jaspersoft-copilot. #>
    if ($null -ne $script:CopilotConfig) { return $script:CopilotConfig }

    $home = $env:CLAUDE_COPILOT_HOME
    if ([string]::IsNullOrWhiteSpace($home)) {
        $home = Join-Path $env:USERPROFILE '.jaspersoft-copilot'
    }
    $cfgPath = Join-Path $home 'config.json'

    $cfg = if (Test-Path $cfgPath) {
        Get-Content $cfgPath -Raw | ConvertFrom-Json
    } else {
        [pscustomobject]@{ licenseToken = $null; activeProfile = $null; profiles = @() }
    }

    $script:CopilotConfig = [pscustomobject]@{
        Home         = $home
        LicenseToken = $env:CLAUDE_COPILOT_LICENSE ?? $cfg.licenseToken   # env overrides file
        ActiveProfile= $env:CLAUDE_COPILOT_PROFILE ?? $cfg.activeProfile
        Profiles     = $cfg.profiles
        DryRun       = [bool]($env:CLAUDE_COPILOT_DRYRUN -in @('1','true','True'))
        UsageLog     = Join-Path $home 'usage.ndjson'
        AuditLog     = Join-Path $home 'audit.ndjson'
    }
    if (-not (Test-Path $home)) { New-Item -ItemType Directory -Path $home -Force | Out-Null }
    return $script:CopilotConfig
}

# --------------------------------------------------------------------------
# 1. Entitlement
# --------------------------------------------------------------------------
function Get-CopilotEntitlement {
    <#
    .SYNOPSIS Decode + verify the license token into a claims object.
    .OUTPUTS  pscustomobject: account, tier, features[], envQuota, seat, exp.
    #>
    $cfg = Get-CopilotConfig
    if (-not $cfg.LicenseToken) {
        throw "Jaspersoft Copilot: no license token. Set CLAUDE_COPILOT_LICENSE or run 'copilot login'."
    }
    # TODO(P0): verify the Ed25519/JWT signature against the bundled public key,
    # check exp, check revocation list (online refresh, offline-tolerant cache).
    # For now: NOT VERIFIED — decode the payload only so callers can be wired up.
    throw [System.NotImplementedException]::new(
        "License verification not implemented. Stub: wire signature check here (see scope doc WS1).")
}

function Test-CopilotFeature {
    <# Returns $true if the active license tier grants -Feature. #>
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Feature)
    try {
        $ent = Get-CopilotEntitlement
        return $ent.features -contains $Feature
    } catch [System.NotImplementedException] {
        # STUB MODE: allow everything so development isn't blocked. Flip to $false
        # once Get-CopilotEntitlement is real.
        Write-Verbose "Copilot entitlement stubbed -> allowing '$Feature'."
        return $true
    }
}

function Assert-CopilotEntitlement {
    <#
    .SYNOPSIS The preflight gate. Every mutating script calls this first.
    .EXAMPLE  Assert-CopilotEntitlement -Feature 'dashboard.publish'
    #>
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Feature)
    if (-not (Test-CopilotFeature -Feature $Feature)) {
        throw "Jaspersoft Copilot: your plan does not include '$Feature'. Upgrade to enable it."
    }
}

# --------------------------------------------------------------------------
# 2. Profiles & secrets
# --------------------------------------------------------------------------
function Get-CopilotProfile {
    <#
    .SYNOPSIS Resolve a named connection profile (JRS URL/creds + DB).
    .DESCRIPTION Replaces the single hardcoded localhost:8081 + jrs.config.json.
                 Falls back to the active profile when -Name is omitted.
    #>
    [CmdletBinding()] param([string]$Name)
    $cfg = Get-CopilotConfig
    $target = if ($Name) { $Name } else { $cfg.ActiveProfile }
    if (-not $target) {
        throw "Jaspersoft Copilot: no profile selected. Pass -Name or set an active profile."
    }
    $p = $cfg.Profiles | Where-Object { $_.name -eq $target } | Select-Object -First 1
    if (-not $p) { throw "Jaspersoft Copilot: profile '$target' not found." }
    return $p   # { name, jrsUrl, jrsUser, jrsSecretRef, db{host,port,name,user,secretRef} }
}

function Resolve-CopilotSecret {
    <#
    .SYNOPSIS Resolve a secret reference to a plaintext value at call time.
    .DESCRIPTION Secret refs ('vault:...','keychain:...','env:NAME') are never
                 written to the work dir. env: resolves now; vault/keychain are P1.
    #>
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Ref)
    switch -Regex ($Ref) {
        '^env:(.+)$'      { return [Environment]::GetEnvironmentVariable($Matches[1]) }
        '^vault:'         { throw [System.NotImplementedException]::new("Vault backend: scope WS2 (P1).") }
        '^keychain:'      { throw [System.NotImplementedException]::new("OS keychain backend: scope WS2 (P1).") }
        default           { throw "Unrecognized secret ref '$Ref'. Use env:/vault:/keychain:." }
    }
}

# --------------------------------------------------------------------------
# 3. Metering — billable events
# --------------------------------------------------------------------------
function Write-CopilotUsage {
    <#
    .SYNOPSIS Emit one billable usage event. Idempotent per (uri, event, day).
    .DESCRIPTION Buffers NDJSON locally; a flush job batches to the metering
                 endpoint. Offline-tolerant by design.
    .EXAMPLE  Write-CopilotUsage -Event 'report.deployed' -ResourceUri $uri
    #>
    [CmdletBinding()] param(
        [Parameter(Mandatory)][ValidateSet(
            'report.deployed','dashboard.published','domain.created',
            'job.scheduled','alert.created','data.loaded')]
        [string]$Event,
        [Parameter(Mandatory)][string]$ResourceUri,
        [hashtable]$Properties = @{}
    )
    $cfg = Get-CopilotConfig
    if ($cfg.DryRun) { Write-Verbose "[dry-run] would meter $Event $ResourceUri"; return }

    $ts  = (Get-Date).ToUniversalTime().ToString('o')
    $day = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    $rec = [ordered]@{
        # Idempotency key so a retried deploy doesn't double-bill (scope WS3).
        idempotencyKey = [System.BitConverter]::ToString(
            [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                [Text.Encoding]::UTF8.GetBytes("$Event|$ResourceUri|$day"))).Replace('-','').Substring(0,32)
        event = $Event; resourceUri = $ResourceUri; ts = $ts; properties = $Properties
        # account/seat/env filled from the verified entitlement once WS1 lands.
        account = '<stub>'; seat = '<stub>'; env = $cfg.ActiveProfile
    }
    ($rec | ConvertTo-Json -Compress) | Add-Content -Path $cfg.UsageLog -Encoding utf8
    # TODO(P1): buffered, batched, retried POST to the metering endpoint + flush job.
}

# --------------------------------------------------------------------------
# 4. Guardrails — audit + dry-run wrapper
# --------------------------------------------------------------------------
function Write-CopilotAudit {
    <# Append-only audit record (who/what/when/result), separate from billing. #>
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$ResourceUri,
        [string]$Result = 'ok'
    )
    $cfg = Get-CopilotConfig
    $rec = [ordered]@{
        ts = (Get-Date).ToUniversalTime().ToString('o')
        action = $Action; resourceUri = $ResourceUri; result = $Result
        actor = $env:USERNAME; profile = $cfg.ActiveProfile
    }
    ($rec | ConvertTo-Json -Compress) | Add-Content -Path $cfg.AuditLog -Encoding utf8
}

function Test-CopilotDryRun { (Get-CopilotConfig).DryRun }

function Invoke-CopilotMutation {
    <#
    .SYNOPSIS Wrap a mutating REST call with dry-run + audit + (destructive) confirm.
    .DESCRIPTION Honors -DryRun (prints intent, runs nothing). For destructive
                 actions, requires -Confirmed or interactive consent.
    .EXAMPLE
        Invoke-CopilotMutation -Action 'dashboard.delete' -ResourceUri $u -Destructive -Confirmed:$Yes {
            curl.exe -X DELETE ...
        }
    #>
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$ResourceUri,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [switch]$Destructive,
        [switch]$Confirmed
    )
    if (Test-CopilotDryRun) {
        Write-Host "[dry-run] $Action -> $ResourceUri (no call made)" -ForegroundColor Yellow
        Write-CopilotAudit -Action $Action -ResourceUri $ResourceUri -Result 'dry-run'
        return
    }
    if ($Destructive -and -not $Confirmed) {
        throw "Jaspersoft Copilot: '$Action' on '$ResourceUri' is destructive. Pass -Confirmed (or --yes)."
    }
    try {
        $out = & $ScriptBlock
        Write-CopilotAudit -Action $Action -ResourceUri $ResourceUri -Result 'ok'
        return $out
    } catch {
        Write-CopilotAudit -Action $Action -ResourceUri $ResourceUri -Result "error: $($_.Exception.Message)"
        throw
    }
}

Export-ModuleMember -Function `
    Get-CopilotConfig, Get-CopilotEntitlement, Test-CopilotFeature, Assert-CopilotEntitlement,
    Get-CopilotProfile, Resolve-CopilotSecret, Write-CopilotUsage, Write-CopilotAudit,
    Test-CopilotDryRun, Invoke-CopilotMutation
