<#
.SYNOPSIS
  Compile, package, and deploy the Jaspersoft Artifact Wizard WAR into the
  JasperReports Server Tomcat (no Maven required -- compiles straight against
  Tomcat's bundled Jakarta servlet-api.jar).

.DESCRIPTION
  1. javac all src/main/java against <tomcat>/lib/servlet-api.jar (Jakarta).
  2. Assemble the exploded webapp under build/ (static files + WEB-INF/classes).
  3. jar it into target/jasper-wizard.war.
  4. (default) copy the WAR into Tomcat's webapps so it hot-deploys.

  Tomcat here is 10.1.x => Jakarta Servlet (jakarta.servlet.*), and the bundled
  JDK 11 (C:\jdk-11.0.24+8) compiles it. Override paths with the params below.

.EXAMPLE
  .\build.ps1                       # build + deploy to the JRS Tomcat
.EXAMPLE
  .\build.ps1 -NoDeploy             # just build target\jasper-wizard.war
#>
[CmdletBinding()]
param(
    [string]$JdkBin   = "C:\jdk-11.0.24+8\bin",
    [string]$Tomcat   = "C:\Jaspersoft\jasperreports-server-10.0.0\apache-tomcat",
    [switch]$NoDeploy
)

$ErrorActionPreference = "Stop"
$root    = $PSScriptRoot
$srcDir  = Join-Path $root "src\main\java"
$webDir  = Join-Path $root "src\main\webapp"
$build   = Join-Path $root "build"
$target  = Join-Path $root "target"
$classes = Join-Path $build "WEB-INF\classes"

$javac = Join-Path $JdkBin "javac.exe"
$jar   = Join-Path $JdkBin "jar.exe"
$servletApi = Join-Path $Tomcat "lib\servlet-api.jar"

foreach ($p in @($javac, $jar, $servletApi)) {
    if (-not (Test-Path $p)) { throw "required tool/jar not found: $p" }
}

# --- clean ---------------------------------------------------------------
if (Test-Path $build)  { Remove-Item $build  -Recurse -Force }
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
New-Item -ItemType Directory -Path $classes -Force | Out-Null
New-Item -ItemType Directory -Path $target  -Force | Out-Null

# --- 1. assemble static webapp into build/ (incl. WEB-INF/web.xml) --------
Copy-Item (Join-Path $webDir "*") $build -Recurse -Force

# The tracked web.xml carries only the harmless factory defaults
# (superuser/superuser). Patch the ASSEMBLED copy from the skill's gitignored
# jrs.config.json so the deployed wizard always matches the local server creds
# -- otherwise its JRS proxy calls 401 after a password change (the smoke
# test's wizard-api step catches exactly that drift).
$jrsCfgPath = Join-Path $root "..\..\.claude\skills\jasper-deploy\jrs.config.json"
if (Test-Path $jrsCfgPath) {
    $jrsCfg = Get-Content $jrsCfgPath -Raw | ConvertFrom-Json
    $webXml = Join-Path $build "WEB-INF\web.xml"
    $xmlText = Get-Content $webXml -Raw
    foreach ($pair in @(@("jrsUrl", $jrsCfg.serverUrl), @("jrsUser", $jrsCfg.user), @("jrsPass", $jrsCfg.password))) {
        $name, $value = $pair
        if ($value) {
            $xmlText = $xmlText -replace "(?s)(<param-name>$name</param-name>\s*<param-value>)[^<]*(</param-value>)", "`${1}$value`${2}"
        }
    }
    Set-Content $webXml $xmlText -Encoding utf8
    Write-Host "Patched web.xml JRS connection from jrs.config.json (creds stay out of git)"
}

# bundle the verified jasper-deploy scripts INSIDE the WAR (WEB-INF/scripts) so
# the Tomcat service account (LocalService) can read+execute them from its own
# webapps dir -- no access to the user profile/repo is needed at runtime.
$repoScripts = Resolve-Path (Join-Path $root "..\..\.claude\skills\jasper-deploy\scripts")
$bundle = Join-Path $build "WEB-INF\scripts"
New-Item -ItemType Directory -Path $bundle -Force | Out-Null
Copy-Item (Join-Path $repoScripts "*") $bundle -Recurse -Force
Write-Host "Bundled scripts from $repoScripts"

# --- 2. compile ----------------------------------------------------------
$sources = Get-ChildItem $srcDir -Recurse -Filter *.java | ForEach-Object { $_.FullName }
Write-Host "Compiling $($sources.Count) source file(s) against Jakarta servlet-api..."
& $javac -encoding UTF-8 -classpath $servletApi -d $classes @sources
if ($LASTEXITCODE -ne 0) { throw "javac failed ($LASTEXITCODE)" }

# --- 3. package ----------------------------------------------------------
$war = Join-Path $target "jasper-wizard.war"
Push-Location $build
try { & $jar -c -f $war . ; if ($LASTEXITCODE -ne 0) { throw "jar failed ($LASTEXITCODE)" } }
finally { Pop-Location }
Write-Host "Built $war ($([math]::Round((Get-Item $war).Length/1KB)) KB)"

# --- 4. deploy -----------------------------------------------------------
if (-not $NoDeploy) {
    $webapps = Join-Path $Tomcat "webapps"
    if (-not (Test-Path $webapps)) { throw "Tomcat webapps not found: $webapps" }
    $exploded = Join-Path $webapps "jasper-wizard"
    $deployedWar = Join-Path $webapps "jasper-wizard.war"
    if (Test-Path $exploded)    { Remove-Item $exploded    -Recurse -Force }
    if (Test-Path $deployedWar) { Remove-Item $deployedWar -Force }
    Copy-Item $war $deployedWar -Force
    Write-Host "Deployed to $deployedWar"
    Write-Host "Tomcat will auto-expand it. Open:  http://localhost:8081/jasper-wizard/"
}
