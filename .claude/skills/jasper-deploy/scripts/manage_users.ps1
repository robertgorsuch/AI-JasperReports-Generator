<#
.SYNOPSIS
  Create / list / get / delete a JasperReports Server user (and assign roles) via
  the REST v2 `users` service.

.DESCRIPTION
    list    GET    /rest_v2/users[?search=&requiredRole=&maxRecords=]   (server scope)
            GET    /rest_v2/organizations/{org}/users                   (org scope)
    get     GET    /rest_v2/users/{username}
    create  PUT    /rest_v2/users/{username}   body {fullName,password,enabled,roles:[{name}]}
            (org scope: /rest_v2/organizations/{org}/users/{username})
    delete  DELETE /rest_v2/users/{username}

  PUT both creates and updates (idempotent on username). The descriptor is passed
  from a file so PowerShell->curl quoting can't mangle it. Roles are given by name
  (e.g. ROLE_USER); each is sent as {name, externallyDefined:false}.

  Credentials resolve: params -> JRS_URL/JRS_USER/JRS_PASS -> jrs.config.json.

.PARAMETER Action
  list | get | create | delete.

.PARAMETER UserName
  The username (required for get/create/delete).

.PARAMETER Organization
  Tenant id (e.g. organization_1) for an org-scoped user. Omit for the root org.

.PARAMETER FullName
  Display name (create). Defaults to -UserName.

.PARAMETER Password
  Initial password (create). Required for create.

.PARAMETER Roles
  Role names to assign (create), e.g. ROLE_USER,ROLE_ADMINISTRATOR. Default ROLE_USER.

.PARAMETER Enabled
  Whether the account is enabled (create). Default $true.

.PARAMETER Search
  Substring filter for list.

.PARAMETER RequiredRole
  Filter list to users holding this role.

.EXAMPLE
  .\manage_users.ps1 -Action list -Organization organization_1
.EXAMPLE
  .\manage_users.ps1 -Action create -UserName jdoe -FullName "Jane Doe" `
      -Password "Secret123!" -Roles ROLE_USER -Organization organization_1
.EXAMPLE
  .\manage_users.ps1 -Action delete -UserName jdoe -Organization organization_1
#>
[CmdletBinding()]
param(
    [ValidateSet("list", "get", "create", "delete")]
    [string]$Action = "list",
    [string]$UserName,
    [string]$Organization,
    [string]$FullName,
    [string]$Password,                    # NOTE: the new user's password (NOT the JRS auth password)
    [string[]]$Roles = @("ROLE_USER"),
    [bool]$Enabled = $true,
    [string]$Search,
    [string]$RequiredRole,
    [string]$ServerUrl,
    [string]$User,                        # JRS auth user
    [string]$JrsPassword                  # JRS auth password (renamed so -Password is the new user's)
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $JrsPassword

# base path: org-scoped or server-scoped
$usersBase = if ($Organization) { "/rest_v2/organizations/$Organization/users" } else { "/rest_v2/users" }

switch ($Action) {
    "list" {
        $q = @()
        if ($Search) { $q += "search=$Search" }
        if ($RequiredRole) { $q += "requiredRole=$RequiredRole" }
        $path = if ($q.Count) { "${usersBase}?$($q -join '&')" } else { $usersBase }
        $r = Invoke-JrsRest -Jrs $jrs -Method GET -Path $path
        if ($r.Code -eq "204") { Write-Host "No users found."; return }
        if ($r.Code -notmatch '^2\d\d$') { throw "list failed ($($r.Code)): $($r.Body)" }
        Write-Output $r.Body
        return
    }
    "get" {
        if (-not $UserName) { throw "-UserName is required for get" }
        $r = Invoke-JrsRest -Jrs $jrs -Method GET -Path "$usersBase/$UserName"
        if ($r.Code -notmatch '^2\d\d$') { throw "get failed ($($r.Code)): $($r.Body)" }
        Write-Output $r.Body
        return
    }
    "delete" {
        if (-not $UserName) { throw "-UserName is required for delete" }
        $r = Invoke-JrsRest -Jrs $jrs -Method DELETE -Path "$usersBase/$UserName"
        if ($r.Code -notmatch '^(2\d\d|404)$') { throw "delete failed ($($r.Code)): $($r.Body)" }
        Write-Host "OK ($($r.Code)): deleted user $UserName"
        return
    }
    "create" {
        if (-not $UserName) { throw "-UserName is required for create" }
        if (-not $Password) { throw "-Password (the new user's password) is required for create" }
        if (-not $FullName) { $FullName = $UserName }
        $desc = [ordered]@{
            fullName          = $FullName
            externallyDefined = $false
            enabled           = $Enabled
            password          = $Password
            roles             = @($Roles | ForEach-Object { [ordered]@{ name = $_; externallyDefined = $false } })
        }
        if ($Organization) { $desc.tenantId = $Organization }
        $f = [IO.Path]::GetTempFileName()
        ($desc | ConvertTo-Json -Depth 6) | Set-Content -Path $f -Encoding utf8
        try {
            $r = Invoke-JrsRest -Jrs $jrs -Method PUT -Path "$usersBase/$UserName" `
                -ContentType "application/json" -Accept "application/json" -JsonFile $f
        } finally { Remove-Item $f -ErrorAction SilentlyContinue }
        if ($r.Code -notmatch '^2\d\d$') { Write-Host $r.Body; throw "create failed HTTP $($r.Code)" }
        Write-Host "OK ($($r.Code)): created/updated user $UserName (roles: $($Roles -join ', '))"
        return
    }
}
