# query_editor.ps1 — Run FULL SQL on an Avalanche warehouse through the browser
# Query Editor's HTTP API (SQLPad at https://{dns}/api), incl. DDL and COPY...VWLOAD
# (which the Baas Data API cannot do). Used for cloud/GCS loading.
#
# AUTH: the Query Editor API is SQLPad behind the Actian platform's SSO — there is no
# headless login. You must supply a session cookie copied from a browser where you're
# logged into the Query Editor. It is read from (in order): -Cookie, $env:QE_COOKIE,
# or the gitignored file scripts\..\.qe_cookie. Cookies last a few hours.
#
# To get the cookie: open https://{dns}/ (Query Editor) logged in -> DevTools ->
# Application -> Cookies -> copy the `sqlpad.sid` Name=Value (or the whole Cookie header).
#
# Usage:
#   .\query_editor.ps1 -Action connections
#   .\query_editor.ps1 -Action run-sql  -Sql "SELECT COUNT(*) FROM pos_transactions"
#   .\query_editor.ps1 -Action run-file -SqlFile script.sql
#   .\query_editor.ps1 -Action vwload-gcs -Table sales `
#       -Source "gs://rg_gcp_test/sales.csv" -GcsKeyFile sa.json -Header [-FieldDelim ","]
#   .\query_editor.ps1 -Action create-external-gcs -Table ext_sales `
#       -Columns "id INT, amt DECIMAL(12,2)" -Source "gs://rg_gcp_test/sales/" [-Format csv]

param(
    [Parameter(Mandatory)]
    [ValidateSet("connections","run-sql","run-file","vwload-gcs","create-external-gcs")]
    [string]$Action,

    # Connection / target
    [string]$ResourceId,
    [string]$DbHost,
    [string]$Cookie,        # session cookie; else $env:QE_COOKIE, else .qe_cookie file
    [string]$Connection,    # connection id or name substring; default = the 'db' data connection

    # SQL
    [string]$Sql,
    [string]$SqlFile,

    # Load / external table
    [string]$Table,
    [string]$Columns,       # for create-external-gcs: "id INT, name VARCHAR(50)"
    [string]$Source,        # gs://bucket/file.csv  (comma-separated list allowed)
    [string]$GcsKeyFile,    # path to the GCP service-account JSON
    [string]$Format = "csv",
    [string]$FieldDelim = ",",
    [switch]$Header,
    [string]$ExtraOptions,  # extra VWLOAD/external options appended verbatim
    [int]$MaxRows = 1000
)

. "$PSScriptRoot\_admiral_common.ps1"

# ── Connection / auth ──────────────────────────────────────────────────────────

function Get-QeBaseUrl {
    $cfg = Get-AdmiralConfig
    $dns = $DbHost
    if (-not $dns -and $ResourceId) {
        $wh = Invoke-AdmiralApi -Path "/resource/warehouse/$ResourceId"
        $dns = $wh.dns
        if (-not $dns) { $wh = Invoke-AdmiralApi -Path "/resource/database/$ResourceId"; $dns = $wh.dns }
    }
    if (-not $dns -and $cfg.PSObject.Properties["dbHost"]) { $dns = $cfg.dbHost }
    if (-not $dns) { throw "Cannot resolve warehouse host. Provide -DbHost, -ResourceId, or add 'dbHost' to admiral.config.json" }
    return "https://$dns"
}

# Strip cookie attributes (Path/Expires/HttpOnly/...) so only name=value pairs remain.
function Get-QeCookie {
    $raw = $Cookie
    if (-not $raw -and $env:QE_COOKIE) { $raw = $env:QE_COOKIE }
    if (-not $raw) {
        $f = Join-Path $PSScriptRoot "..\.qe_cookie"
        if (Test-Path $f) { $raw = (Get-Content $f -Raw).Trim() }
    }
    if (-not $raw) {
        throw "No Query Editor cookie. Pass -Cookie, set `$env:QE_COOKIE, or write it to .claude/skills/admiral/.qe_cookie (see script header)."
    }
    $attrs = @('path','expires','domain','httponly','samesite','secure','max-age','version')
    $pairs = $raw -split ';' | ForEach-Object { $_.Trim() } | Where-Object {
        $_ -and ($_ -match '=') -and ($attrs -notcontains ($_ -split '=',2)[0].Trim().ToLower())
    }
    if (-not $pairs) { throw "Cookie value has no name=value pairs: $raw" }
    return ($pairs -join '; ')
}

# Use HttpClient with UseCookies=$false so our 'Cookie' header is sent verbatim.
# (PS5.1 Invoke-WebRequest silently drops the restricted Cookie header.)
function Get-QeClient {
    if ($script:QeClient) { return $script:QeClient }
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    $h = New-Object System.Net.Http.HttpClientHandler
    $h.UseCookies = $false
    $h.AllowAutoRedirect = $false
    $c = New-Object System.Net.Http.HttpClient($h)
    $c.Timeout = [TimeSpan]::FromSeconds(180)
    $c.DefaultRequestHeaders.Add("Cookie", (Get-QeCookie))
    $c.DefaultRequestHeaders.Add("Accept", "application/json")
    $script:QeClient = $c
    return $c
}

function Invoke-Qe {
    param([string]$Method = "GET", [Parameter(Mandatory)][string]$Path, [object]$Body)
    $client = Get-QeClient
    $uri = "$(Get-QeBaseUrl)$Path"
    $req = New-Object System.Net.Http.HttpRequestMessage ([System.Net.Http.HttpMethod]::$Method), $uri
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 10 -Compress
        $req.Content = New-Object System.Net.Http.StringContent($json, [System.Text.Encoding]::UTF8, "application/json")
    }
    $resp    = $client.SendAsync($req).Result
    $status  = [int]$resp.StatusCode
    $content = $resp.Content.ReadAsStringAsync().Result
    if ($status -eq 401) {
        throw "Query Editor API 401 Unauthorized - the session cookie is missing or expired. Re-copy the sqlpad.sid cookie from the browser into .qe_cookie."
    }
    if ($status -ge 400) {
        throw "Query Editor API $Method $Path => HTTP ${status}: $($content.Substring(0, [Math]::Min(200, $content.Length)))"
    }
    if ($content) { return $content | ConvertFrom-Json }
    return $null
}

# Pick the connection: -Connection (id or name substring), else the 'db' data connection.
function Resolve-QeConnection {
    $bk = Invoke-Qe -Method GET -Path "/api/connections"
    $conns = @($bk)
    if (-not $conns.Count) { throw "No connections returned by the Query Editor API." }
    if ($Connection) {
        $hit = $conns | Where-Object { $_.id -eq $Connection -or $_.name -like "*$Connection*" } | Select-Object -First 1
        if (-not $hit) { throw "No connection matching '$Connection'. Available: $(($conns | ForEach-Object { $_.name }) -join '; ')" }
        return $hit
    }
    $data = $conns | Where-Object { $_.name -like "*(db)*" } | Select-Object -First 1
    if (-not $data) { $data = $conns | Where-Object { $_.name -like "*Data*" } | Select-Object -First 1 }
    if (-not $data) { $data = $conns[0] }
    return $data
}

# ── SQL execution via the batch API ─────────────────────────────────────────────

function Invoke-QeSql {
    param([string]$Query, $Conn, [int]$Max = 1000)
    $client = Invoke-Qe -Method POST -Path "/api/connection-clients" -Body @{ connectionId = $Conn.id }
    $body = @{
        connectionId       = $Conn.id
        connectionClientId = $client.id
        batchText          = $Query
        selectedText       = $Query
    }
    $batch = Invoke-Qe -Method POST -Path "/api/batches?maxRows=$Max&pageSize=$Max" -Body $body
    $bid = $batch.id
    $st = $null
    for ($i = 0; $i -lt 240; $i++) {
        Start-Sleep -Milliseconds 500
        $st = Invoke-Qe -Method GET -Path "/api/batches/$bid"
        if ($st.status -eq "finished" -or $st.status -eq "error") { break }
    }
    $out = @()
    foreach ($s in @($st.statements)) {
        $rows = $null
        if ($s.status -eq "finished" -and $s.rowCount) {
            $rows = Invoke-Qe -Method GET -Path "/api/statements/$($s.id)/results?pageNumber=1"
        }
        $cols = @()
        if ($s.columns) { $cols = $s.columns | ForEach-Object { if ($_.name) { $_.name } else { "$_" } } }
        $out += [PSCustomObject]@{ Status = $s.status; RowCount = $s.rowCount; Error = $s.error; Columns = $cols; Rows = $rows }
    }
    return [PSCustomObject]@{ BatchStatus = $st.status; Statements = $out }
}

function Show-QeResult {
    param($Result)
    foreach ($s in @($Result.Statements)) {
        if ($s.Status -eq "error") {
            $msg = if ($s.Error.title) { $s.Error.title } elseif ($s.Error.message) { $s.Error.message } else { ($s.Error | ConvertTo-Json -Compress) }
            Write-Host "ERROR: $msg" -ForegroundColor Red
            continue
        }
        if ($s.Rows -and @($s.Rows).Count) {
            $cols = @($s.Columns)
            $table = foreach ($row in @($s.Rows)) {
                $o = [ordered]@{}
                for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $row[$i] }
                [PSCustomObject]$o
            }
            $table | Format-Table -AutoSize | Out-String | Write-Host
            Write-Host "($(@($s.Rows).Count) row$(if(@($s.Rows).Count -ne 1){'s'}))"
        } else {
            $rc = if ($null -ne $s.RowCount) { $s.RowCount } else { 0 }
            Write-Host "OK ($rc row(s) affected)" -ForegroundColor Green
        }
    }
}

# Build the GCS credential option clause from a service-account JSON file.
function Get-GcsCredClause {
    param([string]$KeyFile)
    if (-not $KeyFile)            { throw "-GcsKeyFile <service-account.json> required for GCS access" }
    if (-not (Test-Path $KeyFile)) { throw "Service-account file not found: $KeyFile" }
    $sa = Get-Content $KeyFile -Raw | ConvertFrom-Json
    foreach ($f in 'client_email','private_key_id','private_key') {
        if (-not $sa.$f) { throw "Service-account JSON missing '$f'." }
    }
    # VWLOAD wants the PEM key with literal \n escape sequences (per COPY VWLOAD docs).
    $pk = ($sa.private_key -replace "`r`n", "`n") -replace "`n", '\n'
    return "GCS_EMAIL='$($sa.client_email)', GCS_PRIVATE_KEY_ID='$($sa.private_key_id)', GCS_PRIVATE_KEY='$pk'"
}

# ── Actions ─────────────────────────────────────────────────────────────────────

switch ($Action) {

    "connections" {
        $bk = Invoke-Qe -Method GET -Path "/api/connections"
        Write-Host "=== Query Editor connections ===" -ForegroundColor Cyan
        @($bk) | ForEach-Object { Write-Host ("  {0,-10} {1}  [{2}]" -f $_.id, $_.name, $_.driver) }
    }

    "run-sql" {
        if (-not $Sql) { throw "-Sql required" }
        $conn = Resolve-QeConnection
        Write-Host "=== $($conn.name) ===" -ForegroundColor Cyan
        Write-Host $Sql; Write-Host ""
        Show-QeResult (Invoke-QeSql -Query $Sql -Conn $conn -Max $MaxRows)
    }

    "run-file" {
        if (-not $SqlFile) { throw "-SqlFile required" }
        if (-not (Test-Path $SqlFile)) { throw "File not found: $SqlFile" }
        $conn = Resolve-QeConnection
        $text = Get-Content $SqlFile -Raw
        Write-Host "=== $($conn.name): $SqlFile ===" -ForegroundColor Cyan
        Show-QeResult (Invoke-QeSql -Query $text -Conn $conn -Max $MaxRows)
    }

    "vwload-gcs" {
        if (-not $Table)  { throw "-Table required" }
        if (-not $Source) { throw "-Source required (e.g. gs://rg_gcp_test/file.csv)" }
        $cred = Get-GcsCredClause -KeyFile $GcsKeyFile
        $opts = @("FDELIM='$FieldDelim'")
        if ($Header)       { $opts += "HEADER" }
        if ($ExtraOptions) { $opts += $ExtraOptions }
        $opts += $cred
        $sources = ($Source -split ',' | ForEach-Object { "'" + $_.Trim() + "'" }) -join ', '
        $sql = "COPY $Table () VWLOAD FROM $sources WITH $($opts -join ', ')"
        $conn = Resolve-QeConnection
        Write-Host "=== VWLOAD into $Table from $Source ===" -ForegroundColor Cyan
        Write-Host ($sql -replace "GCS_PRIVATE_KEY='[^']*'", "GCS_PRIVATE_KEY='***'")
        Write-Host ""
        Show-QeResult (Invoke-QeSql -Query $sql -Conn $conn -Max $MaxRows)
    }

    "create-external-gcs" {
        if (-not $Table)   { throw "-Table required" }
        if (-not $Columns) { throw "-Columns required (e.g. 'id INT, amt DECIMAL(12,2)')" }
        if (-not $Source)  { throw "-Source required (e.g. gs://rg_gcp_test/sales/)" }
        # External tables read credentials configured in the Avalanche console, not inline.
        $sql = "CREATE EXTERNAL TABLE $Table ($Columns) USING SPARK WITH REFERENCE='$Source', FORMAT='$Format'"
        if ($ExtraOptions) { $sql += ", $ExtraOptions" }
        $conn = Resolve-QeConnection
        Write-Host "=== CREATE EXTERNAL TABLE $Table -> $Source ===" -ForegroundColor Cyan
        Write-Host $sql
        Write-Host "(External tables use GCS credentials configured in the Avalanche console, not inline.)"
        Write-Host ""
        Show-QeResult (Invoke-QeSql -Query $sql -Conn $conn -Max $MaxRows)
    }
}
