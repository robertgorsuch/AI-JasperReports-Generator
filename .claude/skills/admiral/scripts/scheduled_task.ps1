# scheduled_task.ps1 — Scheduled task management for warehouse resources.
#
# Usage:
#   .\scheduled_task.ps1 -Action list   -ResourceType warehouse -ResourceId av-xxxxx
#   .\scheduled_task.ps1 -Action create -ResourceType warehouse -TaskName "NightlyStop" -TaskAction stop -Cron "0 22 * * *" -Timezone "America/New_York"
#   .\scheduled_task.ps1 -Action create -ResourceType warehouse -TaskName "WeekendSleep" -TaskAction sleep -IntervalMinutes 1440
#   .\scheduled_task.ps1 -Action update -TaskId task-xxx -TaskName "NewName" [-Cron "..."] [-Timezone "..."] [-Active $true]
#   .\scheduled_task.ps1 -Action delete -ResourceType warehouse -ResourceId av-xxxxx -TaskId task-xxx

param(
    [Parameter(Mandatory)]
    [ValidateSet("list","create","update","delete")]
    [string]$Action,

    [ValidateSet("warehouse","database","")]
    [string]$ResourceType = "warehouse",

    [string]$ResourceId,
    [string]$TaskId,

    # Create
    [string]$TaskName,
    [ValidateSet("start","stop","sleep","")]
    [string]$TaskAction = "",
    [string]$Cron,
    [string]$Timezone = "UTC",
    [int]$IntervalMinutes = 0,
    [string]$Description,

    # Update
    [bool]$Active = $true
)

. "$PSScriptRoot\_admiral_common.ps1"

switch ($Action) {

    "list" {
        if (-not $ResourceId)   { throw "-ResourceId required" }
        Write-Host "=== Scheduled Tasks: $ResourceType $ResourceId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/scheduled-task/$ResourceType/$ResourceId/task")
    }

    "create" {
        if (-not $TaskName)   { throw "-TaskName required" }
        if (-not $TaskAction) { throw "-TaskAction required (start|stop|sleep)" }
        if (-not $Cron -and $IntervalMinutes -eq 0) { throw "-Cron or -IntervalMinutes required" }

        $body = @{
            resourceType       = $ResourceType
            scheduledTaskName  = $TaskName
            scheduledTaskAction= $TaskAction
            scheduledTimezone  = $Timezone
        }
        if ($ResourceId)            { $body.resourceId              = $ResourceId }
        if ($Cron)                  { $body.scheduledCronExpression = $Cron }
        if ($IntervalMinutes -gt 0) { $body.scheduledIntervalInMinutes = $IntervalMinutes }
        if ($Description)           { $body.scheduledTaskDescription = $Description }

        Write-Host "=== Creating Scheduled Task '$TaskName' ($TaskAction) ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method POST -Path "/scheduled-task/$ResourceType" -Body $body)
    }

    "update" {
        if (-not $TaskId) { throw "-TaskId required" }
        $body = @{ taskId = $TaskId; active = $Active }
        if ($TaskName) { $body.scheduledTaskName = $TaskName }
        if ($Cron)     { $body.scheduledCronExpression = $Cron }
        if ($Timezone) { $body.scheduledTimezone = $Timezone }
        if ($Description) { $body.scheduledTaskDescription = $Description }
        Write-Host "=== Updating Scheduled Task $TaskId ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Method PUT -Path "/scheduled-task" -Body $body)
    }

    "delete" {
        if (-not $ResourceId) { throw "-ResourceId required" }
        if (-not $TaskId)     { throw "-TaskId required" }
        Write-Host "=== Deleting Scheduled Task $TaskId from $ResourceType $ResourceId ===" -ForegroundColor Yellow
        Write-AdmiralResult (Invoke-AdmiralApi -Method DELETE -Path "/scheduled-task/$ResourceType/$ResourceId/task/$TaskId")
    }
}
