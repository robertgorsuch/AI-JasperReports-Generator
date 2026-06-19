# encryption_key.ps1 — Encryption key management (CRUD, test, re-encrypt).
#
# Usage:
#   .\encryption_key.ps1 -Action list
#   .\encryption_key.ps1 -Action get    -KeyId 3a3b5ff1-...
#   .\encryption_key.ps1 -Action managers
#   .\encryption_key.ps1 -Action create -Name "my-key" -ExternalKeyManagerId 2 -KeyArn "arn:aws:kms:..."
#   .\encryption_key.ps1 -Action update -KeyId 3a3b5ff1-... -Name "new-name"
#   .\encryption_key.ps1 -Action delete -KeyId 3a3b5ff1-...
#   .\encryption_key.ps1 -Action test   -KeyArn "arn:aws:kms:..." -ExternalKeyManagerId 2
#   .\encryption_key.ps1 -Action reencrypt -KeyId 3a3b5ff1-... [-ResourceIds "av-xxx","av-yyy"]

param(
    [Parameter(Mandatory)]
    [ValidateSet("list","get","managers","create","update","delete","test","reencrypt")]
    [string]$Action,

    [string]$KeyId,
    [string]$Name,
    [int]$ExternalKeyManagerId = 0,
    [string]$KeyArn,
    [string[]]$ResourceIds
)

. "$PSScriptRoot\_admiral_common.ps1"

switch ($Action) {

    "list" {
        Write-Host "=== Encryption Keys ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/encryption-key")
    }

    "get" {
        if (-not $KeyId) { throw "-KeyId required" }
        Write-Host "=== Encryption Key: $KeyId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/encryption-key/$KeyId")
    }

    "managers" {
        Write-Host "=== Encryption Key Managers ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/encryption-key/managers/list")
    }

    "create" {
        if (-not $Name)                  { throw "-Name required" }
        if ($ExternalKeyManagerId -eq 0) { throw "-ExternalKeyManagerId required" }
        if (-not $KeyArn)                { throw "-KeyArn required" }
        $body = @{
            name                  = $Name
            externalKeyManagerId  = $ExternalKeyManagerId
            keyId                 = $KeyArn
        }
        Write-Host "=== Creating Encryption Key '$Name' ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method POST -Path "/encryption-key" -Body $body)
    }

    "update" {
        if (-not $KeyId) { throw "-KeyId required" }
        $body = @{}
        if ($Name) { $body.name = $Name }
        if ($body.Count -eq 0) { throw "Provide at least -Name to update" }
        Write-Host "=== Updating Encryption Key $KeyId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method PATCH -Path "/encryption-key/$KeyId" -Body $body)
    }

    "delete" {
        if (-not $KeyId) { throw "-KeyId required" }
        Write-Host "=== Deleting Encryption Key $KeyId ===" -ForegroundColor Yellow
        Write-AdmiralResult (Invoke-AdmiralApi -Method DELETE -Path "/encryption-key/$KeyId")
    }

    "test" {
        if (-not $KeyArn)                { throw "-KeyArn required" }
        if ($ExternalKeyManagerId -eq 0) { throw "-ExternalKeyManagerId required" }
        $body = @{
            keyId                = $KeyArn
            externalKeyManagerId = $ExternalKeyManagerId
        }
        Write-Host "=== Testing Encryption Key ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/encryption-key/check" -Body $body)
    }

    "reencrypt" {
        if (-not $KeyId) { throw "-KeyId required" }
        $body = @{ encryptionKeyId = $KeyId }
        if ($ResourceIds) { $body.resourceIds = $ResourceIds }
        Write-Host "=== Re-encrypting data keys with key $KeyId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method PATCH -Path "/encryption-key/reencrypt" -Body $body)
    }
}
