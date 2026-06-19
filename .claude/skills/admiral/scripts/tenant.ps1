# tenant.ps1 — Tenant details, entitlements, and features.
#
# Usage:
#   .\tenant.ps1 -Action details
#   .\tenant.ps1 -Action entitlements
#   .\tenant.ps1 -Action features

param(
    [ValidateSet("details","entitlements","features")]
    [string]$Action = "details"
)

. "$PSScriptRoot\_admiral_common.ps1"

switch ($Action) {
    "details" {
        Write-Host "=== Tenant Details ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/tenant")
    }
    "entitlements" {
        Write-Host "=== Tenant Entitlements ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/tenant/entitlements")
    }
    "features" {
        Write-Host "=== Tenant Entitlement Features ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/tenant/entitlements/features")
    }
}
