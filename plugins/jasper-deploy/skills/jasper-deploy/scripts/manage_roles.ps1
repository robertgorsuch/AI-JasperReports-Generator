<#
.SYNOPSIS
  Create / list / get / delete a JasperReports Server role via the REST v2
  `roles` service.

.DESCRIPTION
    list    GET    /rest_v2/roles               (server scope)
            GET    /rest_v2/organizations/{org}/roles
    get     GET    /rest_v2/roles/{name}
    create  PUT    /rest_v2/roles/{name}   body {name, externallyDefined:false}
    delete  DELETE /rest_v2/roles/{name}

  PUT both creates and updates (idempotent on role name). Credentials resolve:
  params -> JRS_URL/JRS_USER/JRS_PASS -> jrs.config.json.

.PARAMETER Action
  list | get | create | delete.

.PARAMETER Name
  Role name (e.g. ROLE_ANALYST). Required for get/create/delete.

.PARAMETER Organization
  Tenant id for an org-scoped role. Omit for the root org.

.EXAMPLE
  .\manage_roles.ps1 -Action list
.EXAMPLE
  .\manage_roles.ps1 -Action create -Name ROLE_ANALYST -Organization organization_1
.EXAMPLE
  .\manage_roles.ps1 -Action delete -Name ROLE_ANALYST -Organization organization_1
#>
[CmdletBinding()]
param(
    [ValidateSet("list", "get", "create", "delete")]
    [string]$Action = "list",
    [string]$Name,
    [string]$Organization,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password

$rolesBase = if ($Organization) { "/rest_v2/organizations/$Organization/roles" } else { "/rest_v2/roles" }

switch ($Action) {
    "list" {
        $r = Invoke-JrsRest -Jrs $jrs -Method GET -Path $rolesBase
        if ($r.Code -eq "204") { Write-Host "No roles found."; return }
        Assert-JrsOk -Response $r -Operation "list failed" | Out-Null
        Write-Output $r.Body
        return
    }
    "get" {
        if (-not $Name) { throw "-Name is required for get" }
        $r = Invoke-JrsRest -Jrs $jrs -Method GET -Path "$rolesBase/$Name"
        Assert-JrsOk -Response $r -Operation "get failed" | Out-Null
        Write-Output $r.Body
        return
    }
    "delete" {
        if (-not $Name) { throw "-Name is required for delete" }
        $r = Invoke-JrsRest -Jrs $jrs -Method DELETE -Path "$rolesBase/$Name"
        Assert-JrsOk -Response $r -Operation "delete failed" -Ok '^(2\d\d|404)$' | Out-Null
        Write-Host "OK ($($r.Code)): deleted role $Name"
        return
    }
    "create" {
        if (-not $Name) { throw "-Name is required for create" }
        $desc = [ordered]@{ name = $Name; externallyDefined = $false }
        $f = [IO.Path]::GetTempFileName()
        ($desc | ConvertTo-Json) | Set-Content -Path $f -Encoding utf8
        try {
            $r = Invoke-JrsRest -Jrs $jrs -Method PUT -Path "$rolesBase/$Name" `
                -ContentType "application/json" -Accept "application/json" -JsonFile $f
        } finally { Remove-Item $f -ErrorAction SilentlyContinue }
        Assert-JrsOk -Response $r -Operation "create failed" | Out-Null
        Write-Host "OK ($($r.Code)): created/updated role $Name"
        return
    }
}
