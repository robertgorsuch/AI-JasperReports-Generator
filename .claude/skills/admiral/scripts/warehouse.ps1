# warehouse.ps1 — Warehouse-specific operations: clone, refresh-clone, Spark, restart.
#
# Usage:
#   .\warehouse.ps1 -Action restart -ResourceId av-xxxxx [-ForceRestart]
#   .\warehouse.ps1 -Action clone   -ResourceId av-xxxxx -CloneName "MyClone" [-CloneType fullClone|readonlyClone]
#   .\warehouse.ps1 -Action refresh-clone -ResourceId av-xxxxx [-BackupBeforeClone]
#   .\warehouse.ps1 -Action spark-settings -ResourceId av-xxxxx
#   .\warehouse.ps1 -Action spark-settings-update -ResourceId av-xxxxx -LogLevel INFO -HeapSizeGb 4
#   .\warehouse.ps1 -Action spark-logs -ResourceId av-xxxxx
#   .\warehouse.ps1 -Action dbs -ResourceId av-xxxxx
#   .\warehouse.ps1 -Action create-db -ResourceId av-xxxxx -DbName mydb
#   .\warehouse.ps1 -Action drop-db -ResourceId av-xxxxx -DbName mydb

param(
    [Parameter(Mandatory)]
    [ValidateSet("restart","clone","refresh-clone","spark-settings","spark-settings-update",
                 "spark-logs","dbs","create-db","drop-db")]
    [string]$Action,

    [Parameter(Mandatory)]
    [string]$ResourceId,

    # Restart
    [switch]$ForceRestart,

    # Clone
    [string]$CloneName,
    [ValidateSet("fullClone","readonlyClone","")]
    [string]$CloneType = "fullClone",

    # Refresh-clone
    [switch]$BackupBeforeClone,

    # Spark settings
    [ValidateSet("ERROR","WARN","INFO","DEBUG","")]
    [string]$LogLevel = "",
    [int]$HeapSizeGb = 0,

    # Named DBs
    [string]$DbName
)

. "$PSScriptRoot\_admiral_common.ps1"

switch ($Action) {

    "restart" {
        $body = @{ forceRestart = ($ForceRestart -eq $true) }
        Write-Host "=== Restarting warehouse $ResourceId (force=$($ForceRestart)) ===" -ForegroundColor Yellow
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/resource/warehouse/$ResourceId/restart" -Body $body)
    }

    "clone" {
        if (-not $CloneName) { throw "-CloneName required" }
        $body = @{
            resourceName = $CloneName
            cloneType    = if ($CloneType) { $CloneType } else { "fullClone" }
        }
        Write-Host "=== Cloning warehouse $ResourceId as '$CloneName' ($($body.cloneType)) ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method POST -Path "/resource/warehouse/clone" -Body ($body + @{ resourceId = $ResourceId }))
    }

    "refresh-clone" {
        $body = @{ backupBeforeClone = ($BackupBeforeClone -eq $true) }
        Write-Host "=== Refresh-cloning warehouse $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/resource/warehouse/$ResourceId/refresh-clone" -Body $body)
    }

    "spark-settings" {
        Write-Host "=== Spark Settings: warehouse $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/resource/warehouse/$ResourceId/spark/settings")
    }

    "spark-settings-update" {
        $body = @{}
        if ($LogLevel)      { $body.sparkLogLevel = $LogLevel }
        if ($HeapSizeGb -gt 0) { $body.heapSizeGb = $HeapSizeGb }
        if ($body.Count -eq 0) { throw "Provide -LogLevel and/or -HeapSizeGb" }
        Write-Host "=== Updating Spark Settings: warehouse $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/resource/warehouse/$ResourceId/spark/settings" -Body $body)
    }

    "spark-logs" {
        Write-Host "=== Spark Logs: warehouse $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/resource/warehouse/$ResourceId/spark/logs")
    }

    "dbs" {
        Write-Host "=== Databases in warehouse $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/resource/warehouse/$ResourceId/dbs")
    }

    "create-db" {
        if (-not $DbName) { throw "-DbName required" }
        $body = @{ databaseName = $DbName }
        Write-Host "=== Creating database '$DbName' in warehouse $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method POST -Path "/resource/warehouse/$ResourceId/dbs" -Body $body)
    }

    "drop-db" {
        if (-not $DbName) { throw "-DbName required" }
        $body = @{ databaseName = $DbName }
        Write-Host "=== Dropping database '$DbName' from warehouse $ResourceId ===" -ForegroundColor Yellow
        Write-AdmiralResult (Invoke-AdmiralApi -Method DELETE -Path "/resource/warehouse/$ResourceId/dbs" -Body $body)
    }
}
