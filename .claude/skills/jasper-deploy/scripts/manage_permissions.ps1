<#
.SYNOPSIS
  Get / set / clear repository permissions (ACLs) on a JasperReports Server
  resource via the REST v2 `permissions` service.

.DESCRIPTION
  A resource with no explicit ACL returns 204 and inherits from its parent.
    -Action get    show explicit permissions (add -Effective for resolved/inherited)
    -Action set    REPLACE all explicit permissions with -Recipient/-Mask (repeatable
                   via parallel arrays), Content-Type application/collection+json
    -Action clear  remove all explicit permissions (PUT an empty set) -> back to 204

  Permission entry = {uri:"repo:<uri>", recipient:"role:/ROLE_X" | "user:/u", mask}.
  Mask values: 1=administer, 2=read+delete, 6=read+write+delete, 18=read+write,
  30=read-only, 32=execute-only, 0=none.

  Credentials resolve: params -> JRS_URL/JRS_USER/JRS_PASS -> jrs.config.json.

.EXAMPLE
  .\manage_permissions.ps1 -Action get -Uri /reports/geocoder -Effective
.EXAMPLE
  .\manage_permissions.ps1 -Action set -Uri /reports/geocoder `
      -Recipient role:/ROLE_USER -Mask 30
.EXAMPLE
  .\manage_permissions.ps1 -Action clear -Uri /reports/geocoder
#>
[CmdletBinding()]
param(
    [ValidateSet("get", "set", "clear")][string]$Action = "get",
    [Parameter(Mandatory)][string]$Uri,
    [string[]]$Recipient,
    [int[]]$Mask,
    [switch]$Effective,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password
if (-not $Uri.StartsWith("/")) { $Uri = "/$Uri" }

switch ($Action) {
    "get" {
        $path = "/rest_v2/permissions$Uri"
        if ($Effective) { $path += "?effectivePermissions=true" }
        $r = Invoke-JrsRest -Jrs $jrs -Method GET -Path $path
        Write-Host "GET permissions$Uri -> $($r.Code)$(if ($r.Code -eq '204') { ' (none explicit; inherited from parent)' })"
        if ($r.Body) { Write-Host $r.Body }
    }
    "set" {
        if (-not $Recipient -or -not $Mask -or $Recipient.Count -ne $Mask.Count) {
            throw "-Action set requires matching -Recipient and -Mask arrays (one mask per recipient)"
        }
        $perms = @(for ($i = 0; $i -lt $Recipient.Count; $i++) {
            [ordered]@{ uri = "repo:$Uri"; recipient = $Recipient[$i]; mask = $Mask[$i] }
        })
        $f = [IO.Path]::GetTempFileName()
        ([ordered]@{ permission = $perms } | ConvertTo-Json -Depth 5) | Set-Content $f -Encoding utf8
        try {
            # application/collection+json (NOT collection.permission+json, which 415s)
            $r = Invoke-JrsRest -Jrs $jrs -Method PUT -Path "/rest_v2/permissions$Uri" `
                -ContentType "application/collection+json" -JsonFile $f
        } finally { Remove-Item $f -ErrorAction SilentlyContinue }
        Assert-JrsOk -Response $r -Operation "set permissions failed" | Out-Null
        Write-Host "OK ($($r.Code)): set $($perms.Count) permission(s) on $Uri"
    }
    "clear" {
        $f = [IO.Path]::GetTempFileName()
        ([ordered]@{ permission = @() } | ConvertTo-Json) | Set-Content $f -Encoding utf8
        try {
            $r = Invoke-JrsRest -Jrs $jrs -Method PUT -Path "/rest_v2/permissions$Uri" `
                -ContentType "application/collection+json" -JsonFile $f
        } finally { Remove-Item $f -ErrorAction SilentlyContinue }
        Assert-JrsOk -Response $r -Operation "clear permissions failed" | Out-Null
        Write-Host "OK ($($r.Code)): cleared explicit permissions on $Uri (back to inherited)"
    }
}
