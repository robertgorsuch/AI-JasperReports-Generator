# database.ps1 — Database-specific operations: locations, logs, DBA access, volume resize.
#
# Usage:
#   .\database.ps1 -Action logs        -ResourceId db-xxxxx
#   .\database.ps1 -Action locations   -ResourceId db-xxxxx
#   .\database.ps1 -Action add-location -ResourceId db-xxxxx -LocationType s3 -LocationPath s3://mybucket/path
#   .\database.ps1 -Action del-location -ResourceId db-xxxxx -LocationId loc-xxx
#   .\database.ps1 -Action dba-access  -ResourceId db-xxxxx -EnableDba $true [-DbaPassword mypass]
#   .\database.ps1 -Action resize      -ResourceId db-xxxxx -NewSizeGib 100
#   .\database.ps1 -Action dbs         -ResourceId db-xxxxx

param(
    [Parameter(Mandatory)]
    [ValidateSet("logs","locations","add-location","del-location","dba-access","resize","dbs")]
    [string]$Action,

    [Parameter(Mandatory)]
    [string]$ResourceId,

    # Location
    [string]$LocationType,
    [string]$LocationPath,
    [string]$LocationId,

    # DBA Access
    [bool]$EnableDba = $true,
    [string]$DbaPassword,

    # Volume Resize
    [int]$NewSizeGib = 0
)

. "$PSScriptRoot\_admiral_common.ps1"

switch ($Action) {

    "logs" {
        Write-Host "=== Database Logs: $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/resource/database/$ResourceId/logs")
    }

    "locations" {
        Write-Host "=== Database Locations: $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/resource/database/$ResourceId/location")
    }

    "add-location" {
        if (-not $LocationType) { throw "-LocationType required" }
        if (-not $LocationPath) { throw "-LocationPath required" }
        $body = @{ locationType = $LocationType; locationPath = $LocationPath }
        Write-Host "=== Adding Location ($LocationType: $LocationPath) to database $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/resource/database/$ResourceId/location" -Body $body)
    }

    "del-location" {
        if (-not $LocationId) { throw "-LocationId required" }
        $body = @{ locationId = $LocationId }
        Write-Host "=== Deleting Location $LocationId from database $ResourceId ===" -ForegroundColor Yellow
        Write-AdmiralResult (Invoke-AdmiralApi -Method DELETE -Path "/resource/database/$ResourceId/location" -Body $body)
    }

    "dba-access" {
        $body = @{ enable = $EnableDba }
        if ($DbaPassword) { $body.password = $DbaPassword }
        Write-Host "=== Setting DBA Access (enable=$EnableDba) for database $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/resource/database/$ResourceId/dba/access" -Body $body)
    }

    "resize" {
        if ($NewSizeGib -eq 0) { throw "-NewSizeGib required (size in GiB)" }
        $body = @{ dataVolumeSizeInGib = $NewSizeGib }
        Write-Host "=== Resizing data volume of database $ResourceId to $NewSizeGib GiB ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method POST -Path "/resource/database/$ResourceId/volumes/resize" -Body $body)
    }

    "dbs" {
        Write-Host "=== Databases in database resource $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/resource/database/$ResourceId/dbs")
    }
}
