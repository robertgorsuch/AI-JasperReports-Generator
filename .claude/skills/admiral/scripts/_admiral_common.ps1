# _admiral_common.ps1 — shared auth and HTTP helpers for all admiral scripts.
# Dot-source this at the top of every admiral script:
#   . "$PSScriptRoot\_admiral_common.ps1"

$ErrorActionPreference = "Stop"

# ── Config ──────────────────────────────────────────────────────────────────

function Get-AdmiralConfig {
    $cfgPath = Join-Path $PSScriptRoot "..\admiral.config.json"
    if (-not (Test-Path $cfgPath)) {
        throw "Config not found: $cfgPath. Copy admiral.config.example.json to admiral.config.json and fill in your credentials."
    }
    $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
    if ($cfg.password -eq "REPLACE_WITH_PASSWORD") {
        throw "admiral.config.json still has placeholder password. Edit the file and set the real password."
    }
    return $cfg
}

# ── Auth ─────────────────────────────────────────────────────────────────────
# Token is cached in $script:AdmiralToken / $script:AdmiralTokenExpiry per
# session; re-login happens automatically when within 5 min of expiry.

function Get-AdmiralToken {
    param([PSCustomObject]$Config)
    if ($script:AdmiralToken -and $script:AdmiralTokenExpiry -and (Get-Date) -lt $script:AdmiralTokenExpiry) {
        return $script:AdmiralToken
    }
    $body = "grant_type=password&username=$([uri]::EscapeDataString($Config.username))&password=$([uri]::EscapeDataString($Config.password))"
    $resp = Invoke-RestMethod -Uri "$($Config.baseUrl)/login" -Method POST `
        -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing
    $script:AdmiralToken = $resp.access_token
    $script:AdmiralTokenExpiry = (Get-Date).AddSeconds($resp.expires_in - 300)
    return $script:AdmiralToken
}

# ── HTTP helper ───────────────────────────────────────────────────────────────
# Usage:
#   Invoke-AdmiralApi -Method GET -Path "/tenant"
#   Invoke-AdmiralApi -Method POST -Path "/resource/warehouse" -Body @{...}
#   Invoke-AdmiralApi -Method PUT  -Path "/resource/warehouse/$id/start" -Raw

function Invoke-AdmiralApi {
    param(
        [string]$Method = "GET",
        [Parameter(Mandatory)][string]$Path,
        [object]$Body = $null,
        [switch]$Raw           # return raw string instead of parsed object
    )
    $cfg   = Get-AdmiralConfig
    $token = Get-AdmiralToken -Config $cfg
    $uri   = "$($cfg.baseUrl)/api/v1$Path"
    $hdrs  = @{ Authorization = "Bearer $token"; Accept = "application/json" }

    $params = @{
        Uri             = $uri
        Method          = $Method
        Headers         = $hdrs
        UseBasicParsing = $true
    }
    if ($Body) {
        $params.Body        = $Body | ConvertTo-Json -Depth 10 -Compress
        $params.ContentType = "application/json"
    }

    try {
        $resp = Invoke-WebRequest @params
        if ($Raw) { return $resp.Content }
        if ($resp.Content) {
            return $resp.Content | ConvertFrom-Json
        }
        return $null
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
        $detail = try { $_.ErrorDetails.Message } catch { $_.Exception.Message }
        Write-Error "Admiral API $Method $Path => HTTP ${status}: $detail"
    }
}

# ── Pretty-print ──────────────────────────────────────────────────────────────

function Write-AdmiralResult {
    param([object]$Result, [int]$Depth = 5)
    if ($null -eq $Result) { Write-Host "(no content)" } else { $Result | ConvertTo-Json -Depth $Depth }
}
