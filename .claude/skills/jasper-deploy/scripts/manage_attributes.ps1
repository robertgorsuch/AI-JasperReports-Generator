<#
.SYNOPSIS
  Get / set / delete a JasperReports Server attribute (key-value) at server, org,
  or user scope, via the REST v2 `attributes` service. Attributes are usable in
  datasource/report expressions as {attribute('name')} -- handy for not
  hard-coding per-environment DB creds.

.DESCRIPTION
    -Scope server  /rest_v2/attributes              (ALWAYS scoped with ?name= --
                   a bare PUT /attributes REPLACES ALL ~134 system attributes!)
    -Scope org     /rest_v2/organizations/{id}/attributes/{name}  (per-name sub-resource)
    -Scope user    /rest_v2/[organizations/{org}/]users/{u}/attributes/{name}

    -Action get | set | delete. set needs -Value (and optional -Secure to
    write-mask the value in reads).

  Credentials resolve: params -> JRS_URL/JRS_USER/JRS_PASS -> jrs.config.json.

.EXAMPLE
  .\manage_attributes.ps1 -Scope server -Action set -Name dbHost -Value db.prod.internal
.EXAMPLE
  .\manage_attributes.ps1 -Scope user -UserName jdoe -Action set -Name region -Value west
.EXAMPLE
  .\manage_attributes.ps1 -Scope server -Action delete -Name dbHost
#>
[CmdletBinding()]
param(
    [ValidateSet("server", "org", "user")][string]$Scope = "server",
    [ValidateSet("get", "set", "delete")][string]$Action = "get",
    [Parameter(Mandatory)][string]$Name,
    [string]$Value,
    [switch]$Secure,
    [string]$Organization,
    [string]$UserName,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password

# Resolve the holder path + whether it's a per-name sub-resource or a ?name=-scoped
# collection. Server has NO /attributes/{name} sub-resource -- only the collection,
# which MUST be scoped with ?name= so a PUT doesn't wipe every server attribute.
switch ($Scope) {
    "server" { $base = "/rest_v2/attributes"; $subResource = $false }
    "org" {
        if (-not $Organization) { throw "-Scope org requires -Organization" }
        $base = "/rest_v2/organizations/$Organization/attributes/$Name"; $subResource = $true
    }
    "user" {
        if (-not $UserName) { throw "-Scope user requires -UserName" }
        $base = if ($Organization) { "/rest_v2/organizations/$Organization/users/$UserName/attributes/$Name" }
                else { "/rest_v2/users/$UserName/attributes/$Name" }
        $subResource = $true
    }
}

switch ($Action) {
    "get" {
        # ${base} braces are required: PowerShell treats '?' as a variable-name
        # char, so "$base?name=" would parse $base?name (null) and drop the base.
        $path = if ($subResource) { $base } else { "${base}?name=$Name" }
        $r = Invoke-JrsRest -Jrs $jrs -Method GET -Path $path
        Write-Host "GET $Scope attribute '$Name' -> $($r.Code)"
        if ($r.Body) { Write-Host $r.Body }
    }
    "set" {
        if (-not $PSBoundParameters.ContainsKey("Value")) { throw "-Action set requires -Value" }
        $f = [IO.Path]::GetTempFileName()
        if ($subResource) {
            # per-name sub-resource: a single attribute object
            ([ordered]@{ name = $Name; value = $Value; secure = [bool]$Secure } | ConvertTo-Json) | Set-Content $f -Encoding utf8
            $path = $base
        } else {
            # server collection: scope with ?name= so only this attribute changes
            ([ordered]@{ attribute = @([ordered]@{ name = $Name; value = $Value; secure = [bool]$Secure }) } | ConvertTo-Json -Depth 4) | Set-Content $f -Encoding utf8
            $path = "${base}?name=$Name"
        }
        try { $r = Invoke-JrsRest -Jrs $jrs -Method PUT -Path $path -ContentType "application/json" -JsonFile $f }
        finally { Remove-Item $f -ErrorAction SilentlyContinue }
        if ($r.Code -notmatch '^2\d\d$') { Write-Host $r.Body; throw "set attribute failed HTTP $($r.Code)" }
        Write-Host "OK ($($r.Code)): set $Scope attribute '$Name'"
    }
    "delete" {
        $path = if ($subResource) { $base } else { "${base}?name=$Name" }
        $r = Invoke-JrsRest -Jrs $jrs -Method DELETE -Path $path
        Write-Host "DELETE $Scope attribute '$Name' -> $($r.Code)"
        if ($r.Code -notmatch '^(2\d\d|404)$') { Write-Host $r.Body; throw "delete attribute failed HTTP $($r.Code)" }
    }
}
