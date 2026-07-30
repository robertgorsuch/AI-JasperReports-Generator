<#
.SYNOPSIS
  One-command environment/readiness preflight for the jasper-deploy skill. Run
  this first on a fresh clone to confirm the machine can scaffold, compile, and
  deploy before anything actually tries to.

.DESCRIPTION
  Runs an independent checklist and prints PASS / WARN / FAIL per item, then a
  one-line summary. Each check is wrapped so one failure never aborts the rest.
  Exit code is nonzero if ANY item is FAIL (WARN does not fail the run).

  Checks:
    1. jrs.config.json present + parseable; required keys (serverUrl/user and
       password OR passwordCommand) present, loosely validated against
       references/jrs.config.schema.json.
    2. JRS server reachable: GET {serverUrl}/rest_v2/serverInfo -> 200 (reports
       the server version from the body).
    3. PostgreSQL reachable: psql "select 1" (WARN if psql is not on PATH).
    4. Repo metadata DB (access events): connect to the "repoDb" from
       jrs.config.json (default localhost:5433/jasperserver) and count
       jiaccessevent rows. WARN -- usage reporting is optional -- when
       unreachable, and also when the count is 0, which usually means the
       stale :5432 decoy DB rather than the live bundled PostgreSQL on :5433.
    5. JRS->DB connection (contexts): POST a jdbc descriptor built from the
       -Db* params + PGPASSWORD to /rest_v2/contexts, which OPENS the
       connection server-side -- proves the JRS JVM (not just this shell) can
       reach the database. WARN on failure with the driver's real error.
    6. Server settings REST (/rest_v2/settings/globalConfiguration -> 200);
       also reports the domainWhitelist SERVER ATTRIBUTE (the Visualize.js
       cross-origin gate -- unset means cross-origin embeds 403).
    7. JR runtime jars: Resolve-JrLib + a jasperreports-*.jar and the PostgreSQL
       driver jar in that dir.
    8. Chart-customizer jar on the live JRS classpath (WARN if absent -- only
       bar-gradient reports need it).
    9. Python on PATH; sqlglot + pypdfium2 importable (WARN if missing).
   10. Key scripts present in scripts\.

.EXAMPLE
  .\doctor.ps1

.EXAMPLE
  $env:PGPASSWORD = "postgres"; .\doctor.ps1 -Database foodmart

.EXAMPLE
  .\doctor.ps1 -ServerUrl http://localhost:8081/jasperserver-pro -User superuser -Password superuser
#>
[CmdletBinding()]
param(
    [string]$ServerUrl,
    [string]$User,
    [string]$Password,
    [string]$Database = "postgis_34_sample",
    [string]$DbHost = "localhost",
    [string]$DbUser = "postgres"
)

# Never let one bad check abort the whole preflight; each check is try/caught.
$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")

$script:fail = 0
$script:warn = 0
$script:pass = 0

# Record + print a single checklist line. $status is PASS | WARN | FAIL.
function Check {
    param([string]$Name, [string]$Status, [string]$Detail)
    switch ($Status) {
        "PASS" { $script:pass++ }
        "WARN" { $script:warn++ }
        "FAIL" { $script:fail++ }
    }
    $line = "{0,-5} {1}" -f $Status, $Name
    if ($Detail) { $line += "  --  $Detail" }
    Write-Host $line
}

# Run a check body that returns @{ Status=...; Detail=... }; any thrown error
# becomes a FAIL so the checklist always advances.
function Run-Check {
    param([string]$Name, [scriptblock]$Body)
    try {
        $r = & $Body
        Check $Name $r.Status $r.Detail
    } catch {
        Check $Name "FAIL" $_.Exception.Message
    }
}

Write-Host "jasper-deploy doctor -- environment preflight"
Write-Host ("=" * 46)

# --- 1. jrs.config.json present + parseable + required keys --------------------
Run-Check "jrs.config.json" {
    $cfgPath = Join-Path $PSScriptRoot "../jrs.config.json"
    if (-not (Test-Path $cfgPath)) {
        return @{ Status = "FAIL"; Detail = "missing; copy jrs.config.example.json -> jrs.config.json" }
    }
    try { $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json }
    catch { return @{ Status = "FAIL"; Detail = "not valid JSON: $($_.Exception.Message)" } }

    # Loose validation against the schema's key names (PS has no JSON-schema
    # validator): pull the required list from the schema, do presence/type checks.
    $schemaPath = Join-Path $PSScriptRoot "../references/jrs.config.schema.json"
    $required = @("serverUrl", "user", "password")
    if (Test-Path $schemaPath) {
        try { $required = (Get-Content $schemaPath -Raw | ConvertFrom-Json).required } catch {}
    }
    $names = $cfg.PSObject.Properties.Name
    $missing = @()
    foreach ($k in $required) {
        # password may be satisfied by passwordCommand (no plaintext on disk).
        if ($k -eq "password" -and ($names -contains "passwordCommand") -and $cfg.passwordCommand) { continue }
        if (-not ($names -contains $k) -or [string]::IsNullOrEmpty([string]$cfg.$k)) { $missing += $k }
    }
    if ($missing.Count -gt 0) {
        return @{ Status = "FAIL"; Detail = "missing/empty key(s): $($missing -join ', ')" }
    }
    # Type sanity: serverUrl/user/password should be strings.
    foreach ($k in @("serverUrl", "user")) {
        if (-not ($cfg.$k -is [string])) { return @{ Status = "FAIL"; Detail = "$k must be a string" } }
    }
    $auth = if ($names -contains "passwordCommand" -and $cfg.passwordCommand -and [string]::IsNullOrEmpty([string]$cfg.password)) { "passwordCommand" } else { "password" }
    return @{ Status = "PASS"; Detail = "serverUrl=$($cfg.serverUrl), user=$($cfg.user), auth=$auth" }
}

# Resolve once for the network/db checks (param -> env -> config). A failure here
# is reported under the server check; later checks guard on $jrs being non-null.
$jrs = $null
try { $jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password } catch {}

# --- 2. JRS server reachable (serverInfo) -------------------------------------
Run-Check "JRS server reachable" {
    if (-not $jrs) { return @{ Status = "FAIL"; Detail = "could not resolve server URL / credentials" } }
    $url = "$($jrs.ServerUrl)/rest_v2/serverInfo"
    $resp = & (Get-JrsCurl) -s -S -w "`n%{http_code}" -u "$($jrs.User):$($jrs.Password)" -H "Accept: application/json" $url
    # curl's body+code spans a newline, so $resp arrives as a string array; split
    # it directly (do NOT "$resp"-stringify first -- that joins lines with spaces).
    $lines = $resp -split "`n"
    $code = $lines[-1].Trim()
    $body = if ($lines.Length -ge 2) { ($lines[0..($lines.Length - 2)] -join "`n") } else { "" }
    if ($code -ne "200") {
        return @{ Status = "FAIL"; Detail = "GET $url -> HTTP $code" }
    }
    $ver = ""
    try { $ver = ($body | ConvertFrom-Json).version } catch {}
    $detail = "$($jrs.ServerUrl) (HTTP 200"
    if ($ver) { $detail += ", version $ver" }
    $detail += ")"
    return @{ Status = "PASS"; Detail = $detail }
}

# --- 3. PostgreSQL reachable ---------------------------------------------------
Run-Check "PostgreSQL reachable" {
    $psql = Get-Command psql -ErrorAction SilentlyContinue
    if (-not $psql) {
        return @{ Status = "WARN"; Detail = "psql not on PATH; scaffold_*.py introspection will fail" }
    }
    if ([string]::IsNullOrEmpty($env:PGPASSWORD)) {
        # Not fatal -- a .pgpass or trust auth may still work -- but worth flagging.
        Write-Verbose "PGPASSWORD not set; relying on .pgpass/trust"
    }
    $out = & psql -h $DbHost -U $DbUser -d $Database -tAc "select 1" 2>&1
    if ($LASTEXITCODE -eq 0 -and "$out".Trim() -match "1") {
        return @{ Status = "PASS"; Detail = "$DbUser@${DbHost}/$Database -> select 1 ok" }
    }
    return @{ Status = "FAIL"; Detail = "psql select 1 failed: $("$out".Trim())" }
}

# --- 3b. Repo metadata DB (access events) --------------------------------------
Run-Check "repo metadata DB" {
    $psql = Get-Command psql -ErrorAction SilentlyContinue
    if (-not $psql) {
        return @{ Status = "WARN"; Detail = "psql not on PATH; report_usage.ps1 unavailable" }
    }
    # Resolve like report_usage.ps1: "repoDb" in jrs.config.json -> defaults.
    $repo = $null
    $cfgPath = Join-Path $PSScriptRoot "../jrs.config.json"
    if (Test-Path $cfgPath) {
        try { $repo = (Get-Content $cfgPath -Raw | ConvertFrom-Json).repoDb } catch {}
    }
    $rHost = if ($repo -and $repo.host)     { $repo.host }     else { "localhost" }
    $rPort = if ($repo -and $repo.port)     { [int]$repo.port } else { 5433 }
    $rDb   = if ($repo -and $repo.database) { $repo.database } else { "jasperserver" }
    $rUser = if ($repo -and $repo.user)     { $repo.user }     else { "postgres" }
    $out = & psql -h $rHost -p $rPort -U $rUser -d $rDb -X -tAc "select count(*) from jiaccessevent" 2>&1
    if ($LASTEXITCODE -ne 0) {
        return @{ Status = "WARN"; Detail = "unreachable ($rUser@${rHost}:${rPort}/$rDb): $("$out".Trim()) -- report_usage.ps1 will not work; live metadata DB is the JRS-bundled PostgreSQL on :5433" }
    }
    $n = "$out".Trim()
    if ($n -eq "0") {
        return @{ Status = "WARN"; Detail = "${rHost}:${rPort}/$rDb reachable but 0 access events -- likely the stale :5432 decoy DB; point repoDb at the bundled PostgreSQL on :5433" }
    }
    return @{ Status = "PASS"; Detail = "${rHost}:${rPort}/$rDb -- $n access events" }
}

# --- 3c. JRS->DB connection via the contexts service ---------------------------
Run-Check "JRS->DB connection (contexts)" {
    if (-not $jrs) { return @{ Status = "WARN"; Detail = "no JRS credentials resolved; skipping" } }
    # psql (check 3) proves THIS SHELL can reach the DB; this proves the JRS JVM
    # can -- different network/user/driver path, and the one report fills use.
    $pw = if ($env:PGPASSWORD) { $env:PGPASSWORD } else { "postgres" }
    $desc = [ordered]@{
        label = "doctor-conn-test"
        driverClass = "org.postgresql.Driver"
        connectionUrl = "jdbc:postgresql://${DbHost}:5432/${Database}"
        username = $DbUser; password = $pw
    }
    $tf = [IO.Path]::GetTempFileName()
    ($desc | ConvertTo-Json) | Set-Content $tf -Encoding utf8
    try { $t = Invoke-JrsConnectionTest -Jrs $jrs -JsonFile $tf -Type jdbc }
    finally { Remove-Item $tf -ErrorAction SilentlyContinue }
    if ($t.Code -match '^2\d\d$') {
        return @{ Status = "PASS"; Detail = "JRS JVM connected to $DbUser@${DbHost}:5432/$Database (HTTP $($t.Code))" }
    }
    $snippet = "$($t.Body)" -replace '\s+', ' '
    if ($snippet.Length -gt 140) { $snippet = $snippet.Substring(0, 140) + "..." }
    return @{ Status = "WARN"; Detail = "contexts test failed (HTTP $($t.Code)): $snippet" }
}

# --- 3d. Server settings REST + Visualize.js domainWhitelist -------------------
Run-Check "server settings (REST)" {
    if (-not $jrs) { return @{ Status = "WARN"; Detail = "no JRS credentials resolved; skipping" } }
    $s = Invoke-JrsRest -Jrs $jrs -Method GET -Path "/rest_v2/settings/globalConfiguration"
    if ($s.Code -ne "200") {
        return @{ Status = "WARN"; Detail = "GET /settings/globalConfiguration -> HTTP $($s.Code)" }
    }
    $detail = "globalConfiguration readable"
    try {
        $g = $s.Body | ConvertFrom-Json
        $detail += " (maxFileSize=$($g.maxFileSize))"
    } catch {}
    # Visualize.js cross-origin embeds are gated by the domainWhitelist SERVER
    # ATTRIBUTE (JSCorsConfiguration -> DomainWhitelistProviderImpl reads the
    # 'domainWhitelist' profile attribute) -- report it so an embed 403 is
    # diagnosable from the preflight.
    $a = Invoke-JrsRest -Jrs $jrs -Method GET -Path "/rest_v2/attributes?name=domainWhitelist"
    if ($a.Code -eq "200") {
        try {
            $attr = ($a.Body | ConvertFrom-Json).attribute | Select-Object -First 1
            if ($attr) { $detail += "; domainWhitelist=$($attr.value) (Visualize.js cross-origin gate)" }
        } catch {}
    } elseif ($a.Code -eq "204") {
        $detail += "; domainWhitelist attribute unset (Visualize.js cross-origin embeds will 403)"
    }
    return @{ Status = "PASS"; Detail = $detail }
}

# --- 4. JR runtime jars --------------------------------------------------------
Run-Check "JR runtime jars" {
    $lib = Resolve-JrLib   # throws if dir missing -> FAIL
    $jars = Get-ChildItem -Path $lib -Filter *.jar -ErrorAction SilentlyContinue
    $jr = $jars | Where-Object { $_.Name -like "jasperreports-*.jar" } | Select-Object -First 1
    $pg = $jars | Where-Object { $_.Name -like "postgresql-*.jar" } | Select-Object -First 1
    $miss = @()
    if (-not $jr) { $miss += "jasperreports-*.jar" }
    if (-not $pg) { $miss += "postgresql-*.jar (driver)" }
    if ($miss.Count -gt 0) {
        return @{ Status = "FAIL"; Detail = "$lib missing: $($miss -join ', ')" }
    }
    return @{ Status = "PASS"; Detail = "$lib ($($jr.Name), $($pg.Name))" }
}

# --- 5. Chart-customizer jar on the live JRS classpath -------------------------
Run-Check "chart-customizer jar" {
    # The jar lives in the JRS webapp's WEB-INF/lib, whose path is install- and
    # OS-specific. Resolve it in order: config key `chartCustomizerJar` -> the
    # known Windows install default (only when actually on Windows). On macOS/Linux
    # set `chartCustomizerJar` in jrs.config.json to point at your JRS lib dir.
    $tomcatLib = $null
    $cfgPath = Join-Path $PSScriptRoot "../jrs.config.json"
    if (Test-Path $cfgPath) {
        try { $tomcatLib = (Get-Content $cfgPath -Raw | ConvertFrom-Json).chartCustomizerJar } catch {}
    }
    if ([string]::IsNullOrEmpty($tomcatLib) -and (Test-JrsWindows)) {
        $tomcatLib = "C:\Jaspersoft\jasperreports-server-10.0.0\apache-tomcat\webapps\jasperserver-pro\WEB-INF\lib\actian-chart-customizers.jar"
    }
    $bundled = Join-Path $PSScriptRoot "../chart_customizers/actian-chart-customizers.jar"
    if ($tomcatLib -and (Test-Path $tomcatLib)) {
        return @{ Status = "PASS"; Detail = "on classpath: $tomcatLib" }
    }
    $hint = "not located on JRS classpath -- only bar-gradient reports need it."
    if ([string]::IsNullOrEmpty($tomcatLib)) { $hint += " Set `"chartCustomizerJar`" in jrs.config.json to your JRS WEB-INF/lib jar to check it." }
    if (Test-Path $bundled) { $hint += " Bundled source: $((Resolve-Path $bundled).Path)" }
    return @{ Status = "WARN"; Detail = $hint }
}

# --- 6. Python + analysis libs -------------------------------------------------
Run-Check "Python (sqlglot, pypdfium2)" {
    $py = Get-Command (Get-JrsPython) -ErrorAction SilentlyContinue
    if (-not $py) {
        return @{ Status = "WARN"; Detail = "$(Get-JrsPython) not on PATH; scaffold_*.py / lineage / baselines unavailable" }
    }
    $pyver = (& (Get-JrsPython) --version 2>&1) -replace "Python ", ""
    $libs = @{}
    foreach ($m in @("sqlglot", "pypdfium2")) {
        & (Get-JrsPython) -c "import $m" 2>$null
        $libs[$m] = ($LASTEXITCODE -eq 0)
    }
    $have = ($libs.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { $_.Key })
    $miss = ($libs.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
    if ($miss.Count -gt 0) {
        $d = "python $($pyver.Trim()); missing: $($miss -join ', ') (sqlglot=column lineage, pypdfium2=visual baselines)"
        return @{ Status = "WARN"; Detail = $d }
    }
    return @{ Status = "PASS"; Detail = "python $($pyver.Trim()); $($have -join ', ') importable" }
}

# --- 7. Key scripts present ----------------------------------------------------
Run-Check "key scripts present" {
    $need = @("scaffold_jrxml.py", "deploy_report.ps1", "lint_jrxml.ps1", "smoke_test.ps1", "extract_lineage.py")
    $missing = $need | Where-Object { -not (Test-Path (Join-Path $PSScriptRoot $_)) }
    if ($missing.Count -gt 0) {
        return @{ Status = "FAIL"; Detail = "missing in scripts/: $($missing -join ', ')" }
    }
    return @{ Status = "PASS"; Detail = "$($need.Count) scripts found" }
}

# --- summary -------------------------------------------------------------------
Write-Host ("=" * 46)
Write-Host ("doctor: {0} passed, {1} warned, {2} failed" -f $script:pass, $script:warn, $script:fail)
if ($script:fail -gt 0) {
    Write-Host "RESULT: FAIL ($script:fail item(s) need attention)"
    exit 1
}
if ($script:warn -gt 0) {
    Write-Host "RESULT: OK (with $script:warn warning(s))"
} else {
    Write-Host "RESULT: OK -- environment ready"
}
exit 0
