<#
.SYNOPSIS
  Create / list / get / delete a JasperReports Server organization (tenant) via
  the REST v2 `organizations` service.

.DESCRIPTION
    list    GET    /rest_v2/organizations[?rootTenantId=&maxDepth=]
    get     GET    /rest_v2/organizations/{id}
    create  POST   /rest_v2/organizations?createDefaultUsers=true
                   body {id, alias, parentId, tenantName, tenantDesc}
                   (NOTE: create is POST on the collection -- WADL id "putOrganization")
    update  PUT    /rest_v2/organizations/{id}   (e.g. {"theme":"corporate"})
    delete  DELETE /rest_v2/organizations/{id}

  The descriptor is passed from a file so PowerShell->curl quoting can't mangle
  it. Credentials resolve: params -> JRS_URL/JRS_USER/JRS_PASS -> jrs.config.json.

.PARAMETER Action
  list | get | create | update | delete.

.PARAMETER Id
  Organization id / alias (required for get/create/update/delete).

.PARAMETER ParentId
  Parent tenant id for create. Default "organizations" (the root).

.PARAMETER TenantName
  Display name for create. Defaults to -Id.

.PARAMETER Description
  Tenant description for create.

.PARAMETER Theme
  Theme name (update) -- sets the org's active UI theme.

.PARAMETER CreateDefaultUsers
  Whether to seed the default jasperadmin/joeuser for a new org. Default $true.

.EXAMPLE
  .\manage_organizations.ps1 -Action list
.EXAMPLE
  .\manage_organizations.ps1 -Action create -Id acme -TenantName "ACME Inc"
.EXAMPLE
  .\manage_organizations.ps1 -Action update -Id organization_1 -Theme corporate
.EXAMPLE
  .\manage_organizations.ps1 -Action delete -Id acme
#>
[CmdletBinding()]
param(
    [ValidateSet("list", "get", "create", "update", "delete")]
    [string]$Action = "list",
    [string]$Id,
    [string]$ParentId = "organizations",
    [string]$TenantName,
    [string]$Description = " ",
    [string]$Theme,
    [bool]$CreateDefaultUsers = $true,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password

switch ($Action) {
    "list" {
        $r = Invoke-JrsRest -Jrs $jrs -Method GET -Path "/rest_v2/organizations"
        if ($r.Code -eq "204") { Write-Host "No organizations found."; return }
        Assert-JrsOk -Response $r -Operation "list failed" | Out-Null
        Write-Output $r.Body
        return
    }
    "get" {
        if (-not $Id) { throw "-Id is required for get" }
        $r = Invoke-JrsRest -Jrs $jrs -Method GET -Path "/rest_v2/organizations/$Id"
        Assert-JrsOk -Response $r -Operation "get failed" | Out-Null
        Write-Output $r.Body
        return
    }
    "delete" {
        if (-not $Id) { throw "-Id is required for delete" }
        $r = Invoke-JrsRest -Jrs $jrs -Method DELETE -Path "/rest_v2/organizations/$Id"
        Assert-JrsOk -Response $r -Operation "delete failed" -Ok '^(2\d\d|404)$' | Out-Null
        Write-Host "OK ($($r.Code)): deleted organization $Id"
        return
    }
    "create" {
        if (-not $Id) { throw "-Id is required for create" }
        if (-not $TenantName) { $TenantName = $Id }
        $desc = [ordered]@{
            id         = $Id
            alias      = $Id
            parentId   = $ParentId
            tenantName = $TenantName
            tenantDesc = $Description
        }
        $f = [IO.Path]::GetTempFileName()
        ($desc | ConvertTo-Json) | Set-Content -Path $f -Encoding utf8
        # create is POST on the collection, with createDefaultUsers as a query flag
        try {
            $r = Invoke-JrsRest -Jrs $jrs -Method POST `
                -Path "/rest_v2/organizations?createDefaultUsers=$($CreateDefaultUsers.ToString().ToLower())" `
                -ContentType "application/json" -Accept "application/json" -JsonFile $f
        } finally { Remove-Item $f -ErrorAction SilentlyContinue }
        Assert-JrsOk -Response $r -Operation "create failed" | Out-Null
        Write-Host "OK ($($r.Code)): created organization $Id"
        return
    }
    "update" {
        if (-not $Id) { throw "-Id is required for update" }
        # read-modify-write so we don't blank fields we aren't changing
        $cur = Invoke-JrsRest -Jrs $jrs -Method GET -Path "/rest_v2/organizations/$Id"
        Assert-JrsOk -Response $cur -Operation "update: read failed" | Out-Null
        $obj = $cur.Body | ConvertFrom-Json
        if ($Theme) { $obj | Add-Member -NotePropertyName theme -NotePropertyValue $Theme -Force }
        $f = [IO.Path]::GetTempFileName()
        ($obj | ConvertTo-Json -Depth 8) | Set-Content -Path $f -Encoding utf8
        try {
            $r = Invoke-JrsRest -Jrs $jrs -Method PUT -Path "/rest_v2/organizations/$Id" `
                -ContentType "application/json" -Accept "application/json" -JsonFile $f
        } finally { Remove-Item $f -ErrorAction SilentlyContinue }
        Assert-JrsOk -Response $r -Operation "update failed" | Out-Null
        Write-Host "OK ($($r.Code)): updated organization $Id$(if ($Theme) { " (theme=$Theme)" })"
        return
    }
}
