<#
.SYNOPSIS
  Deploy a JasperReports Server UI theme (CSS + images) to the repository and,
  optionally, set it as the active theme for an organization -- fully via REST.

.DESCRIPTION
  A JRS theme is a folder inside a `Themes` folder containing CSS files (at
  minimum `overrides_custom.css`) plus any referenced images/fonts. This script
  creates the theme folder and uploads every file as a repository file resource
  (`application/repository.file+json`), preserving subfolders (e.g. images/).
  Themes take effect immediately -- no server restart.

  Activation: the active theme is a property of the ORGANIZATION
  (`PUT /rest_v2/organizations/{id}` with `{"theme":"<name>"}`). Pass -Activate
  with -Organization to set it. Without activation, a deployed theme can be
  previewed by appending `&theme=<name>` to any JRS UI URL (logged in).

  Credentials resolve: params -> JRS_URL/JRS_USER/JRS_PASS -> jrs.config.json.

.PARAMETER ThemeDir
  Local folder whose contents become the theme (overrides_custom.css + images/…).
  The folder ITSELF is not uploaded -- only its contents (matching JRS's ZIP
  convention). Mutually exclusive with -CssFile.

.PARAMETER CssFile
  A single local .css file deployed as the theme's `overrides_custom.css` (the
  quickest custom theme -- one overrides file). Mutually exclusive with -ThemeDir.

.PARAMETER Name
  Theme name = the repository theme folder name (must not contain spaces).

.PARAMETER ThemesFolder
  Parent Themes folder. Default `/themes` (the system/root level). For an
  organization use `/organizations/<orgId>/themes`.

.PARAMETER Activate
  After deploying, set this theme as the active theme for -Organization.

.PARAMETER Organization
  Organization id whose active theme to set (required with -Activate), e.g.
  `organization_1`.

.PARAMETER Overwrite
  Delete an existing theme folder of the same name first (the ZIP-upload UI
  refuses to overwrite; this script does it via DELETE-then-create).

.EXAMPLE
  # single-file override theme, deployed to the system Themes folder
  .\deploy_theme.ps1 -CssFile mytheme.css -Name corporate_blue

.EXAMPLE
  # full theme folder, deployed to an org and activated
  .\deploy_theme.ps1 -ThemeDir .\themes\corporate -Name corporate `
      -ThemesFolder /organizations/organization_1/themes `
      -Activate -Organization organization_1
#>
[CmdletBinding()]
param(
    [string]$ThemeDir,
    [string]$CssFile,
    [Parameter(Mandatory)][string]$Name,
    [string]$ThemesFolder = "/themes",
    [switch]$Activate,
    [string]$Organization,
    [switch]$Overwrite,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")

if ($ThemeDir -and $CssFile) { throw "specify at most one of -ThemeDir or -CssFile" }
$deployFiles = [bool]$ThemeDir -or [bool]$CssFile
if (-not $deployFiles -and -not $Activate) {
    throw "nothing to do: pass -ThemeDir or -CssFile to deploy files, and/or -Activate to set the active theme"
}
if ($Activate -and -not $Organization) {
    throw "-Activate requires -Organization (the org whose active theme to set, e.g. organization_1)"
}
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password
$themeUri = ($ThemesFolder.TrimEnd("/")) + "/" + $Name

# JRS file-resource type by extension (svg/png/gif/jpg = img; ttf/woff/otf = font)
function file_type($path) {
    switch ([IO.Path]::GetExtension($path).ToLower()) {
        ".css"  { "css" }
        ".png"  { "img" }; ".gif" { "img" }; ".jpg" { "img" }; ".jpeg" { "img" }
        ".svg"  { "img" }; ".ico" { "img" }
        ".ttf"  { "font" }; ".otf" { "font" }; ".woff" { "font" }; ".woff2" { "font" }; ".eot" { "font" }
        ".properties" { "prop" }
        ".js"   { "unspecified" }
        default { "unspecified" }
    }
}

if ($deployFiles) {
# assemble (repoRelativePath, localFullPath) pairs
$files = @()
if ($CssFile) {
    if (-not (Test-Path $CssFile)) { throw "CSS file not found: $CssFile" }
    $files += , @("overrides_custom.css", (Resolve-Path $CssFile).Path)
} else {
    if (-not (Test-Path $ThemeDir)) { throw "theme dir not found: $ThemeDir" }
    $root = (Resolve-Path $ThemeDir).Path
    foreach ($f in Get-ChildItem -File -Recurse -LiteralPath $root) {
        $rel = $f.FullName.Substring($root.Length).TrimStart("\", "/").Replace("\", "/")
        $files += , @($rel, $f.FullName)
    }
    if ($files.Count -eq 0) { throw "no files found under $ThemeDir" }
    if (-not ($files | Where-Object { $_[0] -eq "overrides_custom.css" })) {
        Write-Warning "no overrides_custom.css in $ThemeDir; JRS only applies recognized theme filenames."
    }
}

# overwrite: drop the existing theme folder (recursive) first
if ($Overwrite) {
    $dc = Invoke-JrsDelete -Jrs $jrs -Uri $themeUri
    Write-Host "overwrite: DELETE $themeUri -> $dc"
    if ($dc -notmatch '^(2\d\d|404)$') { throw "overwrite: DELETE $themeUri returned $dc; aborting" }
}

# create the theme folder resource
$ff = [IO.Path]::GetTempFileName()
([ordered]@{ label = $Name; description = "Theme $Name (deployed by jasper-deploy)" } | ConvertTo-Json) |
    Set-Content $ff -Encoding utf8
try {
    $r = Invoke-JrsPut -Jrs $jrs -Uri $themeUri -ContentType "application/repository.folder+json" -JsonFile $ff -Overwrite
} finally { Remove-Item $ff -ErrorAction SilentlyContinue }
if ($r.Code -notmatch '^2\d\d$') { throw "create theme folder $themeUri failed ($($r.Code)): $($r.Body)" }
Write-Host "OK ($($r.Code)): theme folder $themeUri"

# upload each file as a repository file resource (createFolders builds images/ etc.)
foreach ($pair in $files) {
    $rel, $local = $pair
    $uri  = "$themeUri/$rel"
    $type = file_type $local
    $b64  = [Convert]::ToBase64String([IO.File]::ReadAllBytes($local))
    $label = ($rel -split "/")[-1]
    $jf = [IO.Path]::GetTempFileName()
    ([ordered]@{ label = $label; type = $type; content = $b64 } | ConvertTo-Json) | Set-Content $jf -Encoding utf8
    try { $fr = Invoke-JrsPut -Jrs $jrs -Uri $uri -ContentType "application/repository.file+json" -JsonFile $jf -Overwrite }
    finally { Remove-Item $jf -ErrorAction SilentlyContinue }
    if ($fr.Code -notmatch '^2\d\d$') { throw "upload $uri failed ($($fr.Code)): $($fr.Body)" }
    Write-Host "  + $rel ($type)"
}
Write-Host "OK: deployed $($files.Count) file(s) to $themeUri"
} # end if ($deployFiles)

# optional activation via the organizations service
if ($Activate) {
    $jf = [IO.Path]::GetTempFileName()
    ([ordered]@{ theme = $Name } | ConvertTo-Json) | Set-Content $jf -Encoding utf8
    try {
        $ar = Invoke-JrsRest -Jrs $jrs -Method PUT -Path "/rest_v2/organizations/$Organization" `
            -ContentType "application/json" -JsonFile $jf
    } finally { Remove-Item $jf -ErrorAction SilentlyContinue }
    if ($ar.Code -notmatch '^2\d\d$') { throw "activate (PUT /organizations/$Organization theme=$Name) failed ($($ar.Code)): $($ar.Body)" }
    $now = try { ($ar.Body | ConvertFrom-Json).theme } catch { $null }
    Write-Host "OK ($($ar.Code)): activated theme '$Name' for org '$Organization'$(if ($now) { " (theme=$now)" })"
} else {
    Write-Host "Not activated. Preview by appending '&theme=$Name' to a JRS UI URL, or activate with:"
    Write-Host "  deploy_theme.ps1 -Name $Name -Activate -Organization <orgId> (re-run, files already deployed)"
}
