# named_db.ps1 — Create, drop, and list named databases within a warehouse or database resource.
#
# Avalanche named databases support page sizes, encryption, unicode collation, extended
# locations, and access control. This script exposes all CreateNamedDbRequest options.
#
# Usage:
#   .\named_db.ps1 -Action list   -ResourceType warehouse -ResourceId av-xxxxx
#   .\named_db.ps1 -Action create -ResourceType warehouse -ResourceId av-xxxxx -DbName mydb
#   .\named_db.ps1 -Action create -ResourceType warehouse -ResourceId av-xxxxx -DbName analytics `
#       -PageSize 65536 -Location data -EncryptionKeyId "3a3b5ff1-..." -PrivateDb
#   .\named_db.ps1 -Action drop   -ResourceType warehouse -ResourceId av-xxxxx -DbName mydb
#
# Location flags for create:
#   -Location work  — database files go into the work area (default)
#   -Location data  — database files go into the data area
#
# To create an encrypted database, first configure an encryption key via:
#   .\encryption_key.ps1 -Action list   (find the key ID)
#   then pass -EncryptionKeyId "..."

param(
    [Parameter(Mandatory)]
    [ValidateSet("list","create","drop")]
    [string]$Action,

    [ValidateSet("warehouse","database")]
    [string]$ResourceType = "warehouse",

    [Parameter(Mandatory)]
    [string]$ResourceId,

    # Database identity
    [string]$DbName,

    # create options (all optional)
    [string]$ServerClass,

    [ValidateSet("work","data","")]
    [string]$Location = "",

    [switch]$PrivateDb,

    [ValidateSet("2048","4096","8192","16384","65536","")]
    [string]$PageSize = "",

    [ValidateSet("udefault","udefault5","unicode_french","")]
    [string]$NfcCollation = "",

    [ValidateSet("udefault","udefault5","unicode_french","")]
    [string]$NfdCollation = "",

    [switch]$NoX100,           # Disable X100 (columnar) engine

    [ValidateSet("ingres","ingres/dbd","vision","windows_4gl","nofeclients","")]
    [string]$Product = "",

    [string]$Language,         # Collation for non-Unicode DBs
    [switch]$NonUnicodeEnabled,# Disable Unicode (not recommended)

    [string]$EncryptionKeyId,  # UUID from encryption_key.ps1 -Action list

    # Extended locations: comma-separated list of location names to extend
    [string[]]$ExtendedLocations
)

. "$PSScriptRoot\_admiral_common.ps1"

switch ($Action) {

    "list" {
        Write-Host "=== Named Databases in $ResourceType $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/resource/$ResourceType/$ResourceId/dbs")
    }

    "create" {
        if (-not $DbName) { throw "-DbName required" }
        $body = @{ dbName = $DbName }

        if ($ServerClass)          { $body.serverClass           = $ServerClass }
        if ($Location)             { $body.location              = $Location }
        if ($PrivateDb)            { $body.privateDb             = $true }
        if ($PageSize)             { $body.pageSize              = [int]$PageSize }
        if ($NfcCollation)         { $body.nfcCollationName      = $NfcCollation }
        if ($NfdCollation)         { $body.nfdCollationName      = $NfdCollation }
        if ($NoX100)               { $body.noX100                = $true }
        if ($Product)              { $body.product               = $Product }
        if ($Language)             { $body.language              = $Language }
        if ($NonUnicodeEnabled)    { $body.nonUnicodeEnabled      = $true }
        if ($EncryptionKeyId)      { $body.encryptionKeyId       = $EncryptionKeyId }
        if ($ExtendedLocations)    { $body.extendedLocations     = $ExtendedLocations }

        Write-Host "=== Creating named database '$DbName' in $ResourceType $ResourceId ===" -ForegroundColor Cyan
        Write-Host "Options: $(($body.GetEnumerator() | Where-Object { $_.Key -ne 'dbName' } | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
        Write-AdmiralResult (Invoke-AdmiralApi -Method POST -Path "/resource/$ResourceType/$ResourceId/dbs" -Body $body)
    }

    "drop" {
        if (-not $DbName) { throw "-DbName required" }
        Write-Host "=== Dropping named database '$DbName' from $ResourceType $ResourceId ===" -ForegroundColor Yellow
        $body = @{ dbName = $DbName }
        Write-AdmiralResult (Invoke-AdmiralApi -Method DELETE -Path "/resource/$ResourceType/$ResourceId/dbs" -Body $body)
    }
}
