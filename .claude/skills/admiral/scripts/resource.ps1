# resource.ps1 — General resource CRUD and lifecycle for warehouses and databases.
#
# Usage:
#   .\resource.ps1 -Action list   -ResourceType warehouse
#   .\resource.ps1 -Action get    -ResourceType warehouse -ResourceId av-xxxxx
#   .\resource.ps1 -Action create -ResourceType warehouse -Name "MyWH" -Platform Google -RegionId us-east1 -AUs 1
#   .\resource.ps1 -Action modify -ResourceType warehouse -ResourceId av-xxxxx -Name "NewName"
#   .\resource.ps1 -Action delete -ResourceType warehouse -ResourceId av-xxxxx
#   .\resource.ps1 -Action start  -ResourceType warehouse -ResourceId av-xxxxx
#   .\resource.ps1 -Action stop   -ResourceType warehouse -ResourceId av-xxxxx
#   .\resource.ps1 -Action sleep  -ResourceType warehouse -ResourceId av-xxxxx
#   .\resource.ps1 -Action scale  -ResourceType warehouse -ResourceId av-xxxxx -AUs 2
#   .\resource.ps1 -Action allowlist-ip -ResourceType warehouse -ResourceId av-xxxxx -CIDRs "10.0.0.0/8","192.168.1.0/24"
#   .\resource.ps1 -Action idle-stop -ResourceType warehouse -ResourceId av-xxxxx -IdleMinutes 120 -IdleAction Stop
#   .\resource.ps1 -Action alter-wlm -ResourceType warehouse -ResourceId av-xxxxx -ActiveLimit 4
#   .\resource.ps1 -Action configure-data-api -ResourceType warehouse -ResourceId av-xxxxx -Enable $true
#   .\resource.ps1 -Action configure-ml -ResourceType warehouse -ResourceId av-xxxxx -Enable $true
#   .\resource.ps1 -Action external-table-creds -ResourceType warehouse -ResourceId av-xxxxx -AccessKeyId AK... -SecretKey ...
#   .\resource.ps1 -Action update-version -ResourceType warehouse -ResourceId av-xxxxx -Version "701.0.8"
#   .\resource.ps1 -Action apply-updates -ResourceType warehouse -ResourceId av-xxxxx
#   .\resource.ps1 -Action available-updates -ResourceType warehouse -ResourceId av-xxxxx
#   .\resource.ps1 -Action planned-updates -ResourceType warehouse -ResourceId av-xxxxx
#   .\resource.ps1 -Action upcoming-update -ResourceType warehouse -ResourceId av-xxxxx
#   .\resource.ps1 -Action backups -ResourceType warehouse -ResourceId av-xxxxx
#   .\resource.ps1 -Action clone-history -ResourceType warehouse -ResourceId av-xxxxx
#   .\resource.ps1 -Action last-request -ResourceType warehouse -ResourceId av-xxxxx
#   .\resource.ps1 -Action config -ResourceType warehouse

param(
    [Parameter(Mandatory)]
    [ValidateSet("list","get","create","modify","delete","start","stop","sleep","scale",
                 "allowlist-ip","idle-stop","alter-wlm","configure-data-api","configure-ml",
                 "external-table-creds","update-version","apply-updates","available-updates",
                 "planned-updates","upcoming-update","backups","clone-history","last-request","config",
                 "planned-updates-all")]
    [string]$Action,

    [ValidateSet("warehouse","database")]
    [string]$ResourceType = "warehouse",

    [string]$ResourceId,

    # Create / Modify
    [string]$Name,
    [ValidateSet("Google","Azure","AWS","")]
    [string]$Platform = "",
    [string]$RegionId,
    [int]$AUs = 0,
    [string]$DeploymentTier,   # economy|standard|enterprise|super
    [string]$AdminPassword,
    [switch]$LoadSampleData,

    # Scale / Resize
    [int]$NewAUs = 0,

    # IP Allowlist
    [string[]]$CIDRs,

    # Idle-stop
    [int]$IdleMinutes = 0,
    [ValidateSet("Stop","Sleep","")]
    [string]$IdleAction = "",

    # WLM
    [int]$ActiveLimit = 0,

    # Data API / ML services
    [bool]$Enable = $true,

    # External table credentials (AWS S3)
    [string]$AccessKeyId,
    [string]$SecretKey,

    # Version
    [string]$Version,

    # Lifecycle wait
    [switch]$Wait,
    [int]$TimeoutSec = 600
)

. "$PSScriptRoot\_admiral_common.ps1"

# Poll until the resource reaches $Target status; used by -Wait on lifecycle actions.
function Wait-ForStatus {
    param([string]$Id, [string]$Type, [string]$Target, [int]$Timeout)
    $deadline = (Get-Date).AddSeconds($Timeout)
    $last = ""
    Write-Host "  Waiting for '$Target'..." -ForegroundColor DarkCyan -NoNewline
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 10
        try {
            $r      = Invoke-AdmiralApi -Path "/resource/$Type/$Id"
            $status = "$($r.status)"
        } catch {
            if ("$($_.Exception.Message)" -match '404|not.?found') {
                Write-Host " Deleted." -ForegroundColor Green; return
            }
            $status = "?"
        }
        if ($status -ne $last) {
            if ($last) { Write-Host "" }
            Write-Host "  -> $status" -ForegroundColor DarkCyan -NoNewline
            $last = $status
        } else { Write-Host "." -NoNewline }
        if ($status -eq $Target) { Write-Host " Done." -ForegroundColor Green; return }
    }
    Write-Host ""
    Write-Host "  Timed out after ${Timeout}s (last status: $last)" -ForegroundColor Yellow
}

function Require-ResourceId {
    if (-not $ResourceId) { throw "-ResourceId is required for action '$Action'" }
}

switch ($Action) {

    "config" {
        Write-Host "=== Available Configurations: $ResourceType ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/config/$ResourceType")
    }

    "list" {
        Write-Host "=== Resources: $ResourceType ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/resource/$ResourceType")
    }

    "get" {
        Require-ResourceId
        Write-Host "=== Resource: $ResourceType / $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/resource/$ResourceType/$ResourceId")
    }

    "create" {
        if (-not $Name)     { throw "-Name is required" }
        if (-not $Platform) { throw "-Platform is required (Google|Azure|AWS)" }
        if (-not $RegionId) { throw "-RegionId is required" }
        if ($AUs -eq 0)     { throw "-AUs is required" }

        $body = @{
            resourceName   = $Name
            platform       = $Platform
            regionId       = $RegionId
            avalancheUnits = $AUs
        }
        if ($DeploymentTier)  { $body.deploymentTier = $DeploymentTier }
        if ($AdminPassword)   { $body.password       = $AdminPassword }
        if ($LoadSampleData)  { $body.loadSampleData = $true }

        Write-Host "=== Creating $ResourceType '$Name' ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method POST -Path "/resource/$ResourceType" -Body $body)
    }

    "modify" {
        Require-ResourceId
        $body = @{}
        if ($Name)           { $body.resourceName   = $Name }
        if ($DeploymentTier) { $body.deploymentTier = $DeploymentTier }
        if ($body.Count -eq 0) { throw "Provide at least -Name or -DeploymentTier to modify" }
        Write-Host "=== Modifying $ResourceType $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method PATCH -Path "/resource/$ResourceType/$ResourceId" -Body $body)
    }

    "delete" {
        Require-ResourceId
        Write-Host "=== Deleting $ResourceType $ResourceId ===" -ForegroundColor Yellow
        Write-AdmiralResult (Invoke-AdmiralApi -Method DELETE -Path "/resource/$ResourceType/$ResourceId")
        if ($Wait) { Wait-ForStatus -Id $ResourceId -Type $ResourceType -Target "Deleted"  -Timeout $TimeoutSec }
    }

    "start" {
        Require-ResourceId
        $body = @{}
        if ($AdminPassword) { $body.password = $AdminPassword }
        Write-Host "=== Starting $ResourceType $ResourceId ===" -ForegroundColor Green
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/resource/$ResourceType/$ResourceId/start" -Body $body)
        if ($Wait) { Wait-ForStatus -Id $ResourceId -Type $ResourceType -Target "Running"  -Timeout $TimeoutSec }
    }

    "stop" {
        Require-ResourceId
        Write-Host "=== Stopping $ResourceType $ResourceId ===" -ForegroundColor Yellow
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/resource/$ResourceType/$ResourceId/stop")
        if ($Wait) { Wait-ForStatus -Id $ResourceId -Type $ResourceType -Target "Stopped"  -Timeout $TimeoutSec }
    }

    "sleep" {
        Require-ResourceId
        Write-Host "=== Sleeping $ResourceType $ResourceId ===" -ForegroundColor Yellow
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/resource/$ResourceType/$ResourceId/sleep")
        if ($Wait) { Wait-ForStatus -Id $ResourceId -Type $ResourceType -Target "Sleeping" -Timeout $TimeoutSec }
    }

    "scale" {
        Require-ResourceId
        $units = if ($NewAUs -gt 0) { $NewAUs } elseif ($AUs -gt 0) { $AUs } else { throw "-AUs or -NewAUs required" }
        $body = @{ avalancheUnits = $units }
        Write-Host "=== Scaling $ResourceType $ResourceId to $units AUs ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/resource/$ResourceType/$ResourceId/scale" -Body $body)
        if ($Wait) { Wait-ForStatus -Id $ResourceId -Type $ResourceType -Target "Running"  -Timeout $TimeoutSec }
    }

    "allowlist-ip" {
        Require-ResourceId
        if (-not $CIDRs) { throw "-CIDRs required (e.g. '0.0.0.0/0' or '10.0.0.0/8','1.2.3.4/32')" }
        $body = @{ allowListCIDRs = @($CIDRs | ForEach-Object { @{ sourceIp = $_ } }) }
        Write-Host "=== Updating IP Allowlist for $ResourceType $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/resource/$ResourceType/$ResourceId/allowlist-ip" -Body $body)
    }

    "idle-stop" {
        Require-ResourceId
        $body = @{}
        if ($IdleMinutes -gt 0)  { $body.idleAutoStopTimeoutMinutes = $IdleMinutes }
        if ($IdleAction)         { $body.idleAction = $IdleAction }
        if ($body.Count -eq 0) { throw "-IdleMinutes and/or -IdleAction required" }
        Write-Host "=== Updating Idle-Stop for $ResourceType $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/resource/$ResourceType/$ResourceId/idle-stop" -Body $body)
    }

    "alter-wlm" {
        Require-ResourceId
        if ($ActiveLimit -eq 0) { throw "-ActiveLimit required" }
        $body = @{ activeLimit = $ActiveLimit }
        Write-Host "=== Altering WLM for $ResourceType $ResourceId (activeLimit=$ActiveLimit) ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/resource/$ResourceType/$ResourceId/alter-wlm" -Body $body)
    }

    "configure-data-api" {
        Require-ResourceId
        $body = @{ enable = $Enable }
        Write-Host "=== Configuring Data API (enable=$Enable) for $ResourceType $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/resource/$ResourceType/$ResourceId/data-api/configure" -Body $body)
    }

    "configure-ml" {
        Require-ResourceId
        $body = @{ enable = $Enable }
        Write-Host "=== Configuring ML Services (enable=$Enable) for $ResourceType $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/resource/$ResourceType/$ResourceId/ml-services/configure" -Body $body)
    }

    "external-table-creds" {
        Require-ResourceId
        if (-not $AccessKeyId -or -not $SecretKey) { throw "-AccessKeyId and -SecretKey required" }
        $body = @{ awsAccessKeyId = $AccessKeyId; awsSecretAccessKey = $SecretKey }
        Write-Host "=== Upserting External Table Credentials for $ResourceType $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/resource/$ResourceType/$ResourceId/external-table/credentials" -Body $body)
    }

    "update-version" {
        Require-ResourceId
        if (-not $Version) { throw "-Version required (e.g. '701.0.8')" }
        $body = @{ version = $Version }
        Write-Host "=== Setting Update Version $Version for $ResourceType $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/resource/$ResourceType/$ResourceId/update-version" -Body $body)
    }

    "apply-updates" {
        Require-ResourceId
        Write-Host "=== Applying Updates for $ResourceType $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/resource/$ResourceType/$ResourceId/apply-updates")
    }

    "available-updates" {
        Require-ResourceId
        Write-Host "=== Available Updates: $ResourceType $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/resource/$ResourceType/$ResourceId/available-updates")
    }

    "planned-updates" {
        if ($ResourceId) {
            Write-Host "=== Planned Updates: $ResourceType $ResourceId ===" -ForegroundColor Cyan
            Write-AdmiralResult (Invoke-AdmiralApi -Path "/resource/$ResourceType/$ResourceId/planned-updates")
        } else {
            Write-Host "=== Planned Updates: all $ResourceType ===" -ForegroundColor Cyan
            Write-AdmiralResult (Invoke-AdmiralApi -Path "/resource/$ResourceType/planned-updates")
        }
    }

    "upcoming-update" {
        Require-ResourceId
        Write-Host "=== Upcoming Maintenance Update: $ResourceType $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/resource/$ResourceType/$ResourceId/upcoming-updates")
    }

    "backups" {
        Require-ResourceId
        Write-Host "=== Backups: $ResourceType $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/resource/$ResourceType/$ResourceId/backups")
    }

    "clone-history" {
        Require-ResourceId
        Write-Host "=== Clone History: $ResourceType $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/resource/$ResourceType/$ResourceId/clone/history")
    }

    "last-request" {
        Require-ResourceId
        Write-Host "=== Last Request: $ResourceType $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/resource/$ResourceType/$ResourceId/request")
    }
}
