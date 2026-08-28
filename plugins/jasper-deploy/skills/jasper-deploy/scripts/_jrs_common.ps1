<#
  Shared helpers for the jasper-deploy scripts. Dot-source it:
      . (Join-Path $PSScriptRoot "_jrs_common.ps1")

  Resolve-JrsConfig  - server URL + credentials, resolved param -> env
                       (JRS_URL/JRS_USER/JRS_PASS) -> jrs.config.json, with
                       validation and trailing-slash trim. Also returns the
                       config's dataSourceUri fallback.
                       Named environments: -Env <name> (or $env:JRS_ENV) selects
                       jrs.config.json "environments".<name> -- a profile whose
                       keys (serverUrl/user/password/passwordCommand/...) override
                       the top-level ones. With a profile active the JRS_URL/
                       JRS_USER/JRS_PASS process env vars are IGNORED so a stale
                       shell export can't silently retarget a named environment;
                       explicit script params still win.
  Invoke-JrsPut      - PUT a descriptor file to /rest_v2/resources and return
                       the HTTP code + body.
  Invoke-JrsDelete   - DELETE a resource and return the HTTP code.
  Invoke-JrsGet      - GET a resource (Accept json) -> { Code; Body }. It does
                       NOT throw on 404: a missing resource comes back as
                       { Code = "404"; Body = ... }, so a bare
                       `if (Invoke-JrsGet ...)` is always truthy. Existence
                       checks must use Test-JrsResource / Assert-JrsResource.
  Test-JrsResource   - [bool] existence check: $true only when GET returns HTTP
                       200. Takes -Jrs (a Resolve-JrsConfig object) or resolves
                       one itself from -ServerUrl/-User/-Password/-Env/config.
  Assert-JrsResource - throw a clear "not found on <server>" message unless the
                       resource exists (same parameters as Test-JrsResource).
  Get-JrsDashboardsReferencing
                     - list the dashboard URIs whose descriptor references a
                       resource (search GET rest_v2/resources?type=dashboard,
                       then inspect each). Used by deploy_report.ps1 to explain
                       a 403 resource.in.use.
  New-JrsDeployResult - the result object deploy_report.ps1 emits on the
                       pipeline: { Uri; Code; Status; ControlsAttached; Message }.
  Invoke-JrsDownload - GET any URL straight to a file (binary-safe), checking the
                       HTTP status. Use for PDF/XLSX/zip output where the string
                       body of Invoke-JrsGet/Rest would corrupt binary bytes.
                       -TimeoutSec caps the transfer (curl --max-time).
  Assert-JrsOk       - throw a uniform error unless a { Code; Body } response
                       carries a 2xx (override -Ok to allow e.g. 404 on delete).
                       Replaces the inline `if (-notmatch '^2\d\d$') { throw }`.
                       Appends a Get-GotchaHint pointer when the error matches a
                       known signature.
  Get-GotchaHint     - map an HTTP code + body to a one-line references/gotchas.md
                       pointer (UnrecognizedPropertyException, resource.in.use,
                       validateSQL, etc.); "" if no rule matches.
  Resolve-JrsConfig also honors a `passwordCommand` in jrs.config.json (PowerShell
  command whose stdout is the password) so no plaintext secret need live on disk.
  Invoke-JrsRest     - generic call to ANY rest_v2 path (not just /resources):
                       arbitrary method, Content-Type, Accept, optional JSON body
                       from a file. Used by the jobs/alerts wrappers, whose
                       services live at /rest_v2/jobs and /rest_v2/alerts with
                       their own application/<type>+json media types and (for
                       alerts) inverted PUT-creates / POST-modifies verbs.
                       Returns { Code; Body }.
  Resolve-JrLib      - locate the JasperReports 7 runtime jar dir
                       (param -> env JR_LIB_DIR -> jrs.config jrLibDir -> default).
  Invoke-JrCompile   - compile a .jrxml to .jasper with CompileReport.java,
                       tolerating the harmless SLF4J-on-stderr that would
                       otherwise abort a $ErrorActionPreference=Stop caller;
                       returns $true iff the .jasper was produced.

  Cross-platform helpers (Windows PowerShell 5.1, pwsh 7 on Windows, pwsh 7 on
  macOS/Linux). Dot-sourcing brings these into the caller's scope:
  Test-JrsWindows    - $true on Windows (both PS editions), $false on macOS/Linux.
  Get-JrsCurl        - the curl executable name: 'curl.exe' on Windows (PS 5.1's
                       `curl` is an Invoke-WebRequest alias), 'curl' elsewhere.
  Get-JrsPython      - the Python launcher: 'python' on Windows, 'python3' on
                       macOS/Linux (where bare 'python' is usually absent).
#>

# $IsWindows is an automatic in pwsh 6+; it does NOT exist under Windows
# PowerShell 5.1 (evaluates to $null there). Testing `-eq $false` is the one
# idiom that classifies all three runtimes correctly: $null -eq $false and
# $true -eq $false are both $false (-> Windows), only the real $false (pwsh on
# macOS/Linux) is non-Windows.
function Test-JrsWindows { return -not ($IsWindows -eq $false) }
function Get-JrsCurl   { if (Test-JrsWindows) { 'curl.exe' } else { 'curl' } }
function Get-JrsPython { if (Test-JrsWindows) { 'python' }   else { 'python3' } }
function Get-JrsNull   { if (Test-JrsWindows) { 'NUL' }      else { '/dev/null' } }  # curl -o discard target

function Resolve-JrsConfig {
    [CmdletBinding()]
    param([string]$ServerUrl, [string]$User, [string]$Password, [string]$Env)

    $cfgPath = Join-Path $PSScriptRoot "../jrs.config.json"
    $cfg = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw | ConvertFrom-Json } else { $null }

    # Named environment profile: -Env (or $env:JRS_ENV) selects an entry under the
    # config's "environments" object. Profile keys shadow the top-level keys; keys
    # a profile omits fall through to the top level (so shared user/jrLibDir need
    # not be repeated per environment).
    if ([string]::IsNullOrEmpty($Env)) { $Env = [Environment]::GetEnvironmentVariable("JRS_ENV") }
    $prof = $null
    if (-not [string]::IsNullOrEmpty($Env)) {
        $envs = if ($cfg -and ($cfg.PSObject.Properties.Name -contains "environments")) { $cfg.environments } else { $null }
        if (-not ($envs -and ($envs.PSObject.Properties.Name -contains $Env))) {
            $have = if ($envs) { ($envs.PSObject.Properties.Name -join ", ") } else { "(none defined)" }
            throw "Environment '$Env' not found under `"environments`" in jrs.config.json. Defined: $have"
        }
        $prof = $envs.$Env
    }

    function pick($p, $e, $c) {
        if (-not [string]::IsNullOrEmpty($p)) { return $p }
        if ($prof) {
            # A profile pins the target: take its key, else the top-level key.
            # Process env vars (JRS_URL/...) are deliberately skipped so a stale
            # shell export can't silently retarget a named environment.
            if (($prof.PSObject.Properties.Name -contains $c) -and -not [string]::IsNullOrEmpty([string]$prof.$c)) { return $prof.$c }
        } elseif ($e) {
            $v = [Environment]::GetEnvironmentVariable($e); if (-not [string]::IsNullOrEmpty($v)) { return $v }
        }
        if ($cfg -and ($cfg.PSObject.Properties.Name -contains $c)) { return $cfg.$c }
        return $null
    }

    $u   = pick $ServerUrl "JRS_URL"  "serverUrl"
    $usr = pick $User      "JRS_USER" "user"
    $pw  = pick $Password  "JRS_PASS" "password"
    # Secret hardening: instead of a plaintext `password`, the profile or the top
    # level may set `passwordCommand` (a PowerShell command whose stdout is the
    # password) so the secret lives in Windows Credential Manager / a vault, not
    # the file. Env vars (JRS_PASS) and -Password still win; this is the
    # no-plaintext-on-disk fallback. A profile's passwordCommand wins over the
    # top-level one; a profile with a plaintext password never runs either.
    if ([string]::IsNullOrEmpty($pw)) {
        $pwCmd = $null
        if ($prof -and ($prof.PSObject.Properties.Name -contains "passwordCommand") -and $prof.passwordCommand) { $pwCmd = $prof.passwordCommand }
        elseif ($cfg -and ($cfg.PSObject.Properties.Name -contains "passwordCommand") -and $cfg.passwordCommand) { $pwCmd = $cfg.passwordCommand }
        if ($pwCmd) {
            try { $pw = (Invoke-Expression $pwCmd | Out-String).Trim() } catch { $pw = $null }
        }
    }

    if (-not $u) { throw "No server URL. Set -ServerUrl, `$env:JRS_URL, or serverUrl in jrs.config.json" }
    if (-not $usr -or -not $pw) { throw "No credentials. Set -User/-Password, `$env:JRS_USER/JRS_PASS, or user/password in jrs.config.json" }

    $ds = pick $null $null "dataSourceUri"
    return [pscustomobject]@{ ServerUrl = $u.TrimEnd("/"); User = $usr; Password = $pw; DataSourceUri = $ds; Env = $Env }
}

function Invoke-JrsPut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Jrs,          # object from Resolve-JrsConfig
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$ContentType,
        [Parameter(Mandatory)][string]$JsonFile,
        [switch]$Overwrite                       # update in place (no delete) and
                                                 # bypass the optimistic-lock 409
    )
    $url = "$($Jrs.ServerUrl)/rest_v2/resources$Uri" + "?createFolders=true"
    if ($Overwrite) { $url += "&overwrite=true" }
    Write-Host "PUT $url"
    $resp = & (Get-JrsCurl) -s -S -w "`n%{http_code}" -u "$($Jrs.User):$($Jrs.Password)" `
        -X PUT -H "Content-Type: $ContentType" -H "Accept: application/json" `
        --data-binary "@$JsonFile" $url
    $lines = $resp -split "`n"
    $code = $lines[-1].Trim()
    $body = if ($lines.Length -ge 2) { ($lines[0..($lines.Length - 2)] -join "`n").Trim() } else { "" }
    return [pscustomobject]@{ Code = $code; Body = $body }
}

function Invoke-JrsDelete {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Jrs, [Parameter(Mandatory)][string]$Uri)
    $sink = [IO.Path]::GetTempFileName()
    try {
        $code = & (Get-JrsCurl) -s -o $sink -w "%{http_code}" -u "$($Jrs.User):$($Jrs.Password)" `
            -X DELETE "$($Jrs.ServerUrl)/rest_v2/resources$Uri"
    } finally { Remove-Item $sink -ErrorAction SilentlyContinue }
    return "$code".Trim()
}

function Invoke-JrsGet {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Jrs, [Parameter(Mandatory)][string]$Uri,
          [string]$Accept = "application/json")
    $resp = & (Get-JrsCurl) -s -w "`n%{http_code}" -u "$($Jrs.User):$($Jrs.Password)" `
        -H "Accept: $Accept" "$($Jrs.ServerUrl)/rest_v2/resources$Uri"
    $lines = $resp -split "`n"
    $code = $lines[-1].Trim()
    $body = if ($lines.Length -ge 2) { ($lines[0..($lines.Length - 2)] -join "`n").Trim() } else { "" }
    return [pscustomobject]@{ Code = $code; Body = $body }
}

function Test-JrsResource {
    # [bool] existence check for a repository URI: $true ONLY when the server
    # answers HTTP 200 to GET /rest_v2/resources<uri>. Invoke-JrsGet deliberately
    # returns { Code = "404" } instead of throwing, so `if (Invoke-JrsGet ...)`
    # is always true -- use this (or Assert-JrsResource) for existence checks.
    # Pass -Jrs (a Resolve-JrsConfig object) when calling in a loop; otherwise the
    # server is resolved from -ServerUrl/-User/-Password/-Env -> env -> config.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Uri,
        $Jrs,
        [string]$ServerUrl, [string]$User, [string]$Password, [string]$Env
    )
    if (-not $Jrs) { $Jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password -Env $Env }
    if (-not $Uri.StartsWith("/")) { $Uri = "/$Uri" }
    $r = Invoke-JrsGet -Jrs $Jrs -Uri $Uri
    return ("$($r.Code)".Trim() -eq "200")
}

function Assert-JrsResource {
    # Throw unless the repository URI exists (HTTP 200). The message names the
    # server and the HTTP code so a typo'd URI or a wrong -Env is obvious.
    # Returns the URI so it can be used inline: $u = Assert-JrsResource -Uri ...
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        $Jrs,
        [string]$ServerUrl, [string]$User, [string]$Password, [string]$Env,
        [string]$What = "resource"                 # human label for the message
    )
    if (-not $Jrs) { $Jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password -Env $Env }
    if (-not $Uri.StartsWith("/")) { $Uri = "/$Uri" }
    $r = Invoke-JrsGet -Jrs $Jrs -Uri $Uri
    $code = "$($r.Code)".Trim()
    if ($code -ne "200") {
        $where = if ($Jrs.Env) { "$($Jrs.ServerUrl) [env $($Jrs.Env)]" } else { "$($Jrs.ServerUrl)" }
        throw "$What not found on ${where}: $Uri (HTTP $code)"
    }
    return $Uri
}

function Get-JrsDashboardsReferencing {
    # Return the URIs of every dashboard whose descriptor references $Uri (a
    # report unit that is a dashlet, a control, ...). Lists dashboards via
    # GET /rest_v2/resources?type=dashboard, then GETs each descriptor and looks
    # for the URI in its resources[] list (falls back to a body text match).
    # Read-only. Returns an empty array when nothing references it.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Jrs,
        [Parameter(Mandatory)][string]$Uri,
        [string]$Folder = "/",                    # limit the search to a subtree
        [int]$Limit = 1000
    )
    if (-not $Uri.StartsWith("/")) { $Uri = "/$Uri" }
    $path = "/rest_v2/resources?type=dashboard&recursive=true&limit=$Limit&folderUri=$Folder"
    $list = Invoke-JrsRest -Jrs $Jrs -Method GET -Path $path
    if ("$($list.Code)" -ne "200" -or -not $list.Body) { return @() }
    $items = @()
    try {
        $parsed = $list.Body | ConvertFrom-Json
        if ($parsed -and ($parsed.PSObject.Properties.Name -contains "resourceLookup")) { $items = @($parsed.resourceLookup) }
    } catch { return @() }
    $hits = @()
    foreach ($it in $items) {
        if (-not $it.uri) { continue }
        $d = Invoke-JrsGet -Jrs $Jrs -Uri $it.uri
        if ("$($d.Code)" -ne "200") { continue }
        $refs = @()
        try {
            $desc = $d.Body | ConvertFrom-Json
            if ($desc.PSObject.Properties.Name -contains "resources") {
                # each entry is { name; type; resource = { resourceReference = { uri } } }
                $refs = @($desc.resources | ForEach-Object {
                    if ($_.resource -and $_.resource.resourceReference) { "$($_.resource.resourceReference.uri)" }
                    elseif ($_.resource -is [string]) { "$($_.resource)" }
                    else { "$($_.name)" } })
            }
        } catch { }
        if (($refs -contains $Uri) -or ($d.Body -match [regex]::Escape($Uri))) { $hits += "$($it.uri)" }
    }
    return @($hits)
}

function New-JrsDeployResult {
    # The object deploy_report.ps1 writes to the pipeline (Write-Output), so a
    # caller can `$r = & deploy_report.ps1 ...` and test $r.Status instead of
    # scraping Write-Host lines (which `2>&1` does not capture under PS 5.1).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [string]$Code = "",
        [ValidateSet("OK", "FAIL")][string]$Status = "OK",
        [int]$ControlsAttached = 0,
        [string]$Message = ""
    )
    return [pscustomobject]@{
        Uri = $Uri; Code = "$Code"; Status = $Status
        ControlsAttached = $ControlsAttached; Message = $Message
    }
}

function Get-GotchaHint {
    # Map a JRS error (HTTP code + body) to a one-line pointer into the gotchas
    # catalog, so a failing call says WHERE to look. Returns "" if nothing matches.
    [CmdletBinding()]
    param([string]$Code, [string]$Body)
    $b = "$Body"
    $rules = @(
        @{ m = 'UnrecognizedPropertyException|Unrecognized field'; h = 'strict-Jackson unknown element/attr in a .jrxml/.jrtx/.jrdax -- run lint_jrxml.ps1; see references/jr7-valid-elements.md + gotchas.md (strict-Jackson section)' },
        @{ m = 'resource\.in\.use'; h = 'resource is a dashlet of a dashboard (delete-locked) -- remove/recompose the owning dashboard first; gotchas.md (Dashboards)' },
        @{ m = 'version.*(not match|mismatch)|optimistic'; h = 'optimistic-lock conflict -- re-run with -Overwrite; gotchas.md' },
        @{ m = 'JSSecurityException|validateSQL|Validator'; h = 'query must start with SELECT (no leading WITH/CTE) -- gotchas.md (SQL security validator)' },
        @{ m = 'resource\.does\.not\.exist'; h = 'a referenced resource is missing or an embedded child is orphaned (e.g. a Domain schema must be inline) -- gotchas.md (Domains)' },
        @{ m = 'bytes is null|serialization\.error'; h = "don't PUT a dashboard / ad hoc view -- use the export-inject-import path; gotchas.md (Dashboards)" },
        @{ m = 'Misplaced quote|Number of columns'; h = 'CSV adapter: strip the UTF-8 BOM and match recordDelimiter to the file; gotchas.md (data adapters)' }
    )
    foreach ($r in $rules) { if ($b -match $r.m) { return $r.h } }
    return ""
}

function Assert-JrsOk {
    # Throw a uniform error unless $Response.Code matches $Ok (default any 2xx).
    # $Operation is the human label; the response body + a gotchas hint (if the
    # error matches a known signature) are appended for diagnostics.
    # Returns $Response so it can be used inline: $r = Assert-JrsOk (Invoke-JrsGet ...) "get X".
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Response,           # { Code; Body } from an Invoke-Jrs* call
        [Parameter(Mandatory)][string]$Operation,
        [string]$Ok = '^2\d\d$'                     # success-code regex
    )
    if ("$($Response.Code)" -notmatch $Ok) {
        $msg = "$Operation (HTTP $($Response.Code)): $($Response.Body)"
        $hint = Get-GotchaHint -Code "$($Response.Code)" -Body "$($Response.Body)"
        if ($hint) { $msg += "`n  -> hint: $hint" }
        throw $msg
    }
    return $Response
}

function Invoke-JrsDownload {
    # GET $Url straight to $OutFile (binary-safe via curl -o) and check the status.
    # $Url is the full URL -- binary endpoints live under /rest_v2/reports and
    # /rest_v2/reportExecutions, not just /resources, so the caller builds it.
    # Returns the HTTP code. Throws on non-2xx unless -AllowError (then the caller
    # inspects the returned code, e.g. to report size/magic on its own).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Jrs,
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutFile,
        [string]$Accept,
        [switch]$AllowError,
        [int]$TimeoutSec = 0                       # 0 = no limit; else curl --max-time
    )
    $parent = Split-Path -Parent $OutFile
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force $parent | Out-Null }
    $cArgs = @("-s", "-S", "-o", $OutFile, "-w", "%{http_code}", "-u", "$($Jrs.User):$($Jrs.Password)")
    if ($Accept) { $cArgs += @("-H", "Accept: $Accept") }
    if ($TimeoutSec -gt 0) { $cArgs += @("--max-time", "$TimeoutSec") }
    $cArgs += $Url
    $code = "$(& (Get-JrsCurl) @cArgs)".Trim()
    if (-not $AllowError -and $code -notmatch '^2\d\d$') {
        throw "download failed (HTTP $code) for $Url"
    }
    return $code
}

function Invoke-JrsRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Jrs,                  # object from Resolve-JrsConfig
        [Parameter(Mandatory)][string]$Method,       # GET | PUT | POST | DELETE
        [Parameter(Mandatory)][string]$Path,         # path under ServerUrl, e.g. /rest_v2/jobs (may include ?query)
        [string]$ContentType,                        # set for bodied requests
        [string]$Accept = "application/json",
        [string]$JsonFile                            # optional request-body file (survives PS->curl quoting)
    )
    # Build the full literal URL in one string before handing it to curl: an
    # inline "$base?query=..." expression at the PowerShell->curl boundary can
    # yield exit-code 000 (request never sent). Same root cause as the JSON-body
    # quoting gotcha -- keep complex args out of the inline boundary.
    $url = "$($Jrs.ServerUrl)$Path"
    $cArgs = @("-s", "-S", "-w", "`n%{http_code}", "-u", "$($Jrs.User):$($Jrs.Password)",
               "-X", $Method, "-H", "Accept: $Accept")
    if ($ContentType) { $cArgs += @("-H", "Content-Type: $ContentType") }
    if ($JsonFile)    { $cArgs += @("--data-binary", "@$JsonFile") }
    $cArgs += $url
    $resp = & (Get-JrsCurl) @cArgs
    $lines = $resp -split "`n"
    $code = $lines[-1].Trim()
    $body = if ($lines.Length -ge 2) { ($lines[0..($lines.Length - 2)] -join "`n").Trim() } else { "" }
    return [pscustomobject]@{ Code = $code; Body = $body }
}

function Invoke-JrsConnectionTest {
    # Validate a datasource connection WITHOUT creating any repository resource:
    # POST the descriptor to /rest_v2/contexts, which actually opens the
    # connection server-side. 201 = connect OK; 400 connection.failed carries
    # the real driver error (bad password, unknown host, ...). The Content-Type
    # must be the descriptor's own repository.<type>+json media type -- the
    # generic application/connections.jdbc+json guess 415s (gotchas.md G52).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Jrs,
        [Parameter(Mandatory)][string]$JsonFile,     # datasource descriptor body
        [ValidateSet("jdbc", "jndi", "custom")][string]$Type = "jdbc"
    )
    $mime = switch ($Type) {
        "jdbc"   { "application/repository.jdbcDataSource+json" }
        "jndi"   { "application/repository.jndiJdbcDataSource+json" }
        "custom" { "application/repository.customDataSource+json" }
    }
    return Invoke-JrsRest -Jrs $Jrs -Method POST -Path "/rest_v2/contexts" `
        -ContentType $mime -JsonFile $JsonFile
}

function Resolve-JrLib {
    [CmdletBinding()]
    param([string]$LibDir)
    $cfgPath = Join-Path $PSScriptRoot "../jrs.config.json"
    $cfg = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw | ConvertFrom-Json } else { $null }
    if ([string]::IsNullOrEmpty($LibDir)) { $LibDir = [Environment]::GetEnvironmentVariable("JR_LIB_DIR") }
    if ([string]::IsNullOrEmpty($LibDir) -and $cfg -and ($cfg.PSObject.Properties.Name -contains "jrLibDir")) { $LibDir = $cfg.jrLibDir }
    if ([string]::IsNullOrEmpty($LibDir)) {
        throw "JasperReports lib dir not configured. Set -LibDir, `$env:JR_LIB_DIR, or `"jrLibDir`" in jrs.config.json (a directory of JasperReports 7.0.6 runtime jars incl. the JDBC driver and jasperreports-pdf)."
    }
    if (-not (Test-Path $LibDir)) {
        throw "JasperReports lib dir not found: $LibDir (set -LibDir, `$env:JR_LIB_DIR, or jrLibDir in jrs.config.json)"
    }
    return (Resolve-Path $LibDir).Path
}

function Invoke-JrCompile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Jrxml,
        [string]$LibDir,
        [switch]$PassThru          # also return compiler output text for diagnostics
    )
    $jrxmlFull = (Resolve-Path $Jrxml).Path
    $lib = Resolve-JrLib -LibDir $LibDir
    $cp = Join-Path $lib "*"
    $compiler = Join-Path $PSScriptRoot "CompileReport.java"
    if (-not (Test-Path $compiler)) { throw "CompileReport.java missing next to _jrs_common.ps1" }
    $jasper = [IO.Path]::ChangeExtension($jrxmlFull, ".jasper")
    if (Test-Path $jasper) { Remove-Item $jasper -Force }
    # The compiler prints a harmless "SLF4J: No providers" line to stderr; under
    # $ErrorActionPreference=Stop that becomes a terminating NativeCommandError
    # even on a clean exit. Run it under Continue and judge by the .jasper file.
    $out = & { $ErrorActionPreference = "Continue"; & java --class-path $cp $compiler $jrxmlFull 2>&1 }
    $ok = Test-Path $jasper
    if ($PassThru) { return [pscustomobject]@{ Ok = $ok; Jasper = $jasper; Output = ($out | Out-String) } }
    return $ok
}
