# data_load.ps1 — Load data and run SQL on an Avalanche warehouse STRICTLY via the
# Actian Data API (Baas / "Orestes" REST service at https://{dns}/baas/v1).
#
# No local client runtime (psql / isql / ODBC) is used or required — every action
# is an HTTPS call against the Data API. Requires the Data API ("dataAPI" feature)
# to be enabled on the warehouse (see resource.ps1 -Action configure-data-api).
#
# Auth bridge (handled automatically, token cached per session):
#   Admiral /login  ->  IDP access_token
#   GET /baas/v1/db/User/login?access_token=...  ->  Baqend token
#   Authorization: BAT <baqend-token>   on every Data API call
#
# ── Action surface (redesigned around the Data API's natural shape) ─────────────
#
#   Meta:
#     connection-info                         Data API base URL, version, health, table count
#
#   Native SQL  (passthrough — SELECT / WITH / COPY / INSERT-as-SELECT only):
#     query       -Sql "SELECT ..."           run a native query and render the result
#     query-file  -SqlFile script.sql         run ;-separated native queries from a file
#     export-csv  -Sql "SELECT ..." -OutFile out.csv
#     copy-from   -Table t -Source "s3://b/f.csv" [-Format CSV] [-Header] [-Options "..."]
#
#   Tables / schema  (Schema API):
#     list-tables                             list bucket (table) names
#     describe     -Table t                   show the table's fields and types
#     create-table -Table t -Columns "id:int,name:string,amt:double"
#     drop-table   -Table t                   delete the table (schema + data)
#     truncate     -Table t                   delete all rows, keep the table
#     count        -Table t                   row count
#
#   Rows / objects  (Object API):
#     insert    -Table t -Json '{"name":"x","amt":1.5}'
#     load-csv  -Table t -CsvFile data.csv [-CreateTable] [-Delimiter ","]
#     rows      -Table t [-Limit 50]          list rows
#
# NOTE: the native passthrough does NOT accept DDL (CREATE/DROP) or INSERT...VALUES.
#       Tables are created through the Schema API and rows through the Object API.
#       Tables created via the API carry Baqend system columns
#       (id, version, acl, createdAt, updatedAt) alongside your data columns.

param(
    [Parameter(Mandatory)]
    [ValidateSet("connection-info","query","query-file","export-csv","copy-from",
                 "list-tables","describe","create-table","drop-table","truncate","count",
                 "insert","load-csv","rows")]
    [string]$Action,

    # Connection (host comes from config 'dbHost', -DbHost, or resolved from -ResourceId)
    [string]$ResourceId,
    [string]$DbHost,

    # SQL / files
    [string]$Sql,
    [string]$SqlFile,
    [string]$OutFile,

    # Tables / schema
    [string]$Table,
    [string]$Columns,     # "id:int, name:string, amt:double"

    # Rows
    [string]$Json,        # raw JSON object for -Action insert
    [string]$CsvFile,
    [string]$Delimiter = ",",
    [switch]$CreateTable, # load-csv: create the table from inferred CSV types first
    [int]$Limit = 50,

    # COPY (cloud bulk load)
    [string]$Source,      # s3://bucket/key.csv  (or gs:// / azure://)
    [string]$Format = "CSV",
    [switch]$Header,
    [string]$Options      # extra COPY options, appended verbatim inside WITH(...)
)

. "$PSScriptRoot\_admiral_common.ps1"

# ── Connection / auth ──────────────────────────────────────────────────────────

function Get-BaasContext {
    $cfg = Get-AdmiralConfig
    $dns = $DbHost
    if (-not $dns -and $ResourceId) {
        $wh = Invoke-AdmiralApi -Path "/resource/warehouse/$ResourceId"
        $dns = $wh.dns
        if (-not $dns) { $wh = Invoke-AdmiralApi -Path "/resource/database/$ResourceId"; $dns = $wh.dns }
    }
    if (-not $dns -and $cfg.PSObject.Properties["dbHost"]) { $dns = $cfg.dbHost }
    if (-not $dns) { throw "Cannot resolve warehouse host. Provide -DbHost, -ResourceId, or add 'dbHost' to admiral.config.json" }
    return @{ Dns = $dns; BaseUrl = "https://$dns/baas/v1" }
}

# Exchange the Admiral IDP token for a Baqend Data-API token (cached per session).
function Get-BaasToken {
    param([string]$BaseUrl)
    if ($script:BaasToken -and $script:BaasTokenExpiry -and (Get-Date) -lt $script:BaasTokenExpiry) {
        return $script:BaasToken
    }
    $cfg = Get-AdmiralConfig
    $idp = Get-AdmiralToken -Config $cfg
    $uri = "$BaseUrl/db/User/login?access_token=$([uri]::EscapeDataString($idp))"
    $resp = Invoke-WebRequest -Uri $uri -Headers @{ Accept = "application/json" } -UseBasicParsing
    # DCLogin returns an HTML shim:  var response = { "headers": { "Authorization-Token": "..." } };
    $m = [regex]::Match($resp.Content, 'var response\s*=\s*(\{.*?\});', 'Singleline')
    if (-not $m.Success) { throw "Data API login: could not parse token from DCLogin response." }
    $obj = $m.Groups[1].Value | ConvertFrom-Json
    $tok = $obj.headers.'Authorization-Token'
    if (-not $tok) { throw "Data API login: no Authorization-Token returned (check warehouse is running and Data API is enabled)." }
    $script:BaasToken       = $tok
    $script:BaasTokenExpiry = (Get-Date).AddMinutes(30)
    return $tok
}

function Invoke-Baas {
    param(
        [string]$Method = "GET",
        [Parameter(Mandatory)][string]$Path,
        [object]$Body,
        [switch]$Raw
    )
    $ctx = Get-BaasContext
    $tok = Get-BaasToken -BaseUrl $ctx.BaseUrl
    $params = @{
        Uri             = "$($ctx.BaseUrl)$Path"
        Method          = $Method
        Headers         = @{ Authorization = "BAT $tok"; Accept = "application/json" }
        UseBasicParsing = $true
    }
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $params.Body        = ($Body | ConvertTo-Json -Depth 20 -Compress)
        $params.ContentType = "application/json"
    }
    try {
        $resp = Invoke-WebRequest @params
        if ($Raw) { return $resp.Content }
        if ($resp.Content) { return $resp.Content | ConvertFrom-Json }
        return $null
    } catch {
        $status = try { $_.Exception.Response.StatusCode.value__ } catch { "?" }
        $detail = try { $_.ErrorDetails.Message } catch { $_.Exception.Message }
        throw "Data API $Method $Path => HTTP ${status}: $detail"
    }
}

function Invoke-NativeQuery {
    param([string]$Query)
    return Invoke-Baas -Method GET -Path ("/db/query?native=true&q=" + [uri]::EscapeDataString($Query))
}

# ── Result rendering ────────────────────────────────────────────────────────────

# Native query results are: [ {header:{columnDefinitions:[...]}}, {row:{"tbl:col":v,...}}, ... ]
# The Baas always returns the FULL bucket column set; columns not in the SELECT come
# back null. We drop columns that are null/empty for every row (this includes the
# system 'id'), so the output shows what the query actually projected. A genuinely
# all-null projected column is therefore not displayed.
function ConvertFrom-NativeResult {
    param($Result)
    $out = @{ Rows = @(); Messages = @(); Error = $null }
    if ($null -eq $Result) { return $out }
    if ($Result.PSObject.Properties['status'] -and $Result.PSObject.Properties['reason']) {
        $out.Error = $Result; return $out
    }
    $cols = @(); $raw = @()
    foreach ($el in @($Result)) {
        if ($el.header -and $el.header.columnDefinitions) {
            $cols = $el.header.columnDefinitions | ForEach-Object {
                [PSCustomObject]@{ Key = "$($_.tableName):$($_.columnName)"; Name = $_.columnName }
            }
        } elseif ($el.row)     { $raw += ,$el.row }
        elseif ($el.message)   { $out.Messages += $el.message }
    }
    $isEmpty = { param($v) ($null -eq $v) -or ("$v" -eq "") -or ("$v" -eq "null") }
    $keep = foreach ($c in $cols) {
        $hasVal = $false
        foreach ($r in $raw) { $p = $r.PSObject.Properties[$c.Key]; if ($p -and -not (& $isEmpty $p.Value)) { $hasVal = $true; break } }
        if ($hasVal) { $c }
    }
    if (-not @($keep).Count) { $keep = $cols }   # all-null result set: keep declared columns
    $out.Rows = foreach ($r in $raw) {
        $o = [ordered]@{}
        foreach ($c in @($keep)) {
            $p = $r.PSObject.Properties[$c.Key]
            $v = if ($p) { $p.Value } else { $null }
            if ("$v" -eq "null") { $v = $null }
            $o[$c.Name] = $v
        }
        [PSCustomObject]$o
    }
    return $out
}

function Format-NativeResult {
    param($Result)
    $p = ConvertFrom-NativeResult $Result
    if ($p.Error) { Write-Host "ERROR $($p.Error.status) $($p.Error.reason): $($p.Error.message)" -ForegroundColor Red; return }
    $p.Messages | ForEach-Object { Write-Host $_ }
    $rows = @($p.Rows)
    if ($rows.Count) {
        $rows | Format-Table -AutoSize | Out-String | Write-Host
        Write-Host "($($rows.Count) row$(if($rows.Count -ne 1){'s'}))"
    } elseif (-not $p.Messages.Count) {
        Write-Host "(0 rows)"
    }
}

# ── Type mapping ────────────────────────────────────────────────────────────────

# Baqend objects inherit these system fields from /db/Object — a data column of the
# same name collides, so it is renamed with a trailing underscore.
$script:ReservedFields = @('id','version','acl','createdat','updatedat')
function Get-SafeFieldName {
    param([string]$n)
    # A trailing '_' is itself reserved by Baqend, so use a full-word suffix.
    if ($script:ReservedFields -contains $n.ToLower()) { return "${n}_col" }
    return $n
}

function ConvertTo-BaasType {
    param([string]$t)
    $tl = $t.Trim().ToLower()
    if ($tl -like "/db/*") { return $t.Trim() }
    switch -regex ($tl) {
        '^(int|integer|smallint|tinyint)$'                 { return "/db/Integer" }
        '^(long|bigint)$'                                  { return "/db/Integer" }
        '^(double|float|real|decimal|numeric|number|money)$' { return "/db/Double" }
        '^(bool|boolean|bit)$'                             { return "/db/Boolean" }
        '^(datetime|timestamp)$'                           { return "/db/DateTime" }
        '^date$'                                           { return "/db/Date" }
        '^time$'                                           { return "/db/Time" }
        default                                            { return "/db/String" }
    }
}

# Returns ordered list of @{ Name; Baas; Kind } inferred from a CSV.
function Get-CsvColumnTypes {
    param([string]$CsvPath, [string]$Delim = ",")
    $rows = Import-Csv -Path $CsvPath -Delimiter $Delim[0]
    if (-not $rows) { throw "CSV is empty or unreadable: $CsvPath" }
    $sample = $rows | Select-Object -First 200
    $names  = $sample[0].PSObject.Properties.Name
    $order  = 0
    foreach ($name in $names) {
        $vals = $sample | ForEach-Object { $_.$name } | Where-Object { $_ -ne $null -and $_ -ne "" }
        $kind = "String"
        if ($vals) {
            $cnt = @($vals).Count
            if (@($vals | Where-Object { $_ -match '^-?\d+$' }).Count -eq $cnt)                { $kind = "Integer" }
            elseif (@($vals | Where-Object { $_ -match '^-?\d+(\.\d+)?$' }).Count -eq $cnt)     { $kind = "Double" }
            elseif (@($vals | Where-Object { $_ -match '^(true|false)$' }).Count -eq $cnt)      { $kind = "Boolean" }
            elseif (@($vals | Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}' }).Count -eq $cnt)  { $kind = "DateTime" }
        }
        $field = Get-SafeFieldName $name
        if ($field -ne $name) { Write-Warning "Column '$name' is a reserved system field; storing it as '$field'." }
        [PSCustomObject]@{ Name = $field; Source = $name; Baas = "/db/$kind"; Kind = $kind; Order = $order }
        $order++
    }
}

function ConvertTo-Typed {
    param($Value, [string]$Kind)
    if ($null -eq $Value -or $Value -eq "") { return $null }
    switch ($Kind) {
        "Integer" { return [int64]$Value }
        "Double"  { return [double]$Value }
        "Boolean" { return [bool]($Value -match '^(true|1)$') }
        default   { return [string]$Value }
    }
}

function New-TableSchema {
    param([string]$Name, $ColumnTypes)  # ColumnTypes: list of @{Name;Baas;Order}
    $fields = @{}
    foreach ($c in $ColumnTypes) {
        $fields[$c.Name] = @{ name = $c.Name; type = $c.Baas; order = [int]$c.Order }
    }
    $schema = @(@{
        class      = "/db/$Name"
        superClass = "/db/Object"
        metadata   = @{ backendType = "jdbc" }
        fields     = $fields
    })
    Invoke-Baas -Method POST -Path "/schema" -Body $schema | Out-Null
    Invoke-Baas -Method GET  -Path "/schema/refresh" | Out-Null
}

# ── Actions ─────────────────────────────────────────────────────────────────────

switch ($Action) {

    "connection-info" {
        $ctx = Get-BaasContext
        Write-Host "=== Actian Data API (Baas) ===" -ForegroundColor Cyan
        Write-Host "  Warehouse DNS : $($ctx.Dns)"
        Write-Host "  Data API base : $($ctx.BaseUrl)"
        Write-Host "  Transport     : HTTPS only (no psql/isql/ODBC)"
        Write-Host ""
        try {
            $ver = Invoke-Baas -Method GET -Path "/version"
            Write-Host "  API version   : $ver"
            Get-BaasToken -BaseUrl $ctx.BaseUrl | Out-Null
            Write-Host "  Auth          : OK (Baqend token acquired)" -ForegroundColor Green
            $status = Invoke-Baas -Method GET -Path "/status"
            foreach ($s in $status.serviceStatus) {
                $mark = if ($s.isAvailable) { "up" } else { "DOWN" }
                Write-Host "    - $($s.name): $mark"
            }
            $bk = Invoke-Baas -Method GET -Path "/db"; $buckets = @($bk)
            Write-Host "  Tables (buckets): $($buckets.Count)"
        } catch {
            Write-Host "  Auth/health   : FAILED - $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    "query" {
        if (-not $Sql) { throw "-Sql required" }
        Write-Host "=== Native query ===" -ForegroundColor Cyan
        Write-Host $Sql; Write-Host ""
        Format-NativeResult (Invoke-NativeQuery -Query $Sql) | Out-Null
    }

    "query-file" {
        if (-not $SqlFile) { throw "-SqlFile required" }
        if (-not (Test-Path $SqlFile)) { throw "File not found: $SqlFile" }
        $text = Get-Content $SqlFile -Raw
        $stmts = $text -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        Write-Host "=== Running $($stmts.Count) native quer$(if($stmts.Count -ne 1){'ies'}else{'y'}) from $SqlFile ===" -ForegroundColor Cyan
        foreach ($s in $stmts) {
            Write-Host "`n--- $s" -ForegroundColor DarkGray
            Format-NativeResult (Invoke-NativeQuery -Query $s) | Out-Null
        }
    }

    "export-csv" {
        if (-not $Sql)     { throw "-Sql required" }
        if (-not $OutFile) { throw "-OutFile required" }
        Write-Host "=== Exporting query results to $OutFile ===" -ForegroundColor Cyan
        $parsed = ConvertFrom-NativeResult (Invoke-NativeQuery -Query $Sql)
        if ($parsed.Error) { Write-Host "ERROR $($parsed.Error.status) $($parsed.Error.reason): $($parsed.Error.message)" -ForegroundColor Red; break }
        $rows = @($parsed.Rows)
        $abs = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path (Get-Location) $OutFile }
        $rows | Export-Csv -Path $abs -NoTypeInformation -Encoding UTF8
        Write-Host "Wrote $($rows.Count) rows -> $abs"
    }

    "copy-from" {
        if (-not $Table)  { throw "-Table required" }
        if (-not $Source) { throw "-Source required (e.g. s3://bucket/file.csv)" }
        $with = @($Format)
        if ($Header)  { $with += "HEADER" }
        if ($Options) { $with += $Options }
        $sql = "COPY `"$Table`" FROM '$Source' WITH ($($with -join ', '))"
        Write-Host "=== COPY FROM (cloud bulk load) ===" -ForegroundColor Cyan
        Write-Host $sql
        Write-Host "(Requires S3/cloud creds via resource.ps1 -Action external-table-creds)"
        Write-Host ""
        Format-NativeResult (Invoke-NativeQuery -Query $sql) | Out-Null
    }

    "list-tables" {
        $bk = Invoke-Baas -Method GET -Path "/db"; $buckets = @($bk)
        Write-Host "=== Tables ($($buckets.Count)) ===" -ForegroundColor Cyan
        $buckets | ForEach-Object { ($_ -replace '^/db/','') } | Sort-Object | ForEach-Object { Write-Host "  $_" }
    }

    "describe" {
        if (-not $Table) { throw "-Table required" }
        $schema = Invoke-Baas -Method GET -Path "/schema/$Table"
        Write-Host "=== $Table ===" -ForegroundColor Cyan
        Write-Host "  superClass: $($schema.superClass)  backend: $($schema.metadata.backendType)"
        $schema.fields.PSObject.Properties |
            Sort-Object { $_.Value.order } |
            ForEach-Object { "{0,-3} {1,-24} {2}" -f $_.Value.order, $_.Value.name, $_.Value.type } |
            ForEach-Object { Write-Host "  $_" }
    }

    "create-table" {
        if (-not $Table)   { throw "-Table required" }
        if (-not $Columns) { throw "-Columns required (e.g. 'id:int, name:string, amt:double')" }
        $i = 0
        $colTypes = $Columns -split ',' | ForEach-Object {
            $parts = $_ -split ':', 2
            $name = $parts[0].Trim()
            if (-not $name) { return }
            $type  = if ($parts.Count -gt 1) { ConvertTo-BaasType $parts[1] } else { "/db/String" }
            $field = Get-SafeFieldName $name
            if ($field -ne $name) { Write-Warning "Column '$name' is a reserved system field; creating it as '$field'." }
            $r = [PSCustomObject]@{ Name = $field; Baas = $type; Order = $i }; $i++; $r
        } | Where-Object { $_ }
        Write-Host "=== Creating table $Table ===" -ForegroundColor Cyan
        $colTypes | ForEach-Object { Write-Host "  $($_.Name) -> $($_.Baas)" }
        New-TableSchema -Name $Table -ColumnTypes $colTypes
        Write-Host "Created (plus system columns id, version, acl, createdAt, updatedAt)." -ForegroundColor Green
    }

    "drop-table" {
        if (-not $Table) { throw "-Table required" }
        Write-Host "=== Dropping table $Table ===" -ForegroundColor Yellow
        Invoke-Baas -Method DELETE -Path "/schema/$Table" -Raw | Out-Null
        Write-Host "Dropped."
    }

    "truncate" {
        if (-not $Table) { throw "-Table required" }
        Write-Host "=== Truncating $Table ===" -ForegroundColor Yellow
        Invoke-Baas -Method DELETE -Path "/db/$Table" -Raw | Out-Null
        Write-Host "All rows deleted."
    }

    "count" {
        if (-not $Table) { throw "-Table required" }
        Write-Host "=== Row count: $Table ===" -ForegroundColor Cyan
        Format-NativeResult (Invoke-NativeQuery -Query "SELECT COUNT(*) AS count FROM `"$Table`"") | Out-Null
    }

    "insert" {
        if (-not $Table) { throw "-Table required" }
        if (-not $Json)  { throw "-Json required (e.g. {'name':'x','amt':1.5})" }
        $obj = $Json | ConvertFrom-Json
        $created = Invoke-Baas -Method POST -Path "/db/$Table" -Body $obj
        Write-Host "Inserted: $($created.id)" -ForegroundColor Green
    }

    "load-csv" {
        if (-not $Table)   { throw "-Table required" }
        if (-not $CsvFile) { throw "-CsvFile required" }
        if (-not (Test-Path $CsvFile)) { throw "File not found: $CsvFile" }

        $colTypes = Get-CsvColumnTypes -CsvPath $CsvFile -Delim $Delimiter
        if ($CreateTable) {
            Write-Host "=== Creating table $Table from CSV ===" -ForegroundColor Cyan
            $colTypes | ForEach-Object { Write-Host "  $($_.Name) -> $($_.Baas)" }
            New-TableSchema -Name $Table -ColumnTypes $colTypes
        }

        $rows = Import-Csv -Path $CsvFile -Delimiter $Delimiter[0]
        Write-Host "=== Loading $($rows.Count) rows into $Table (Object API) ===" -ForegroundColor Cyan
        $ok = 0; $fail = 0; $n = 0
        foreach ($row in $rows) {
            $obj = @{}
            foreach ($c in $colTypes) { $obj[$c.Name] = ConvertTo-Typed $row.($c.Source) $c.Kind }
            try { Invoke-Baas -Method POST -Path "/db/$Table" -Body $obj | Out-Null; $ok++ }
            catch { $fail++; if ($fail -le 5) { Write-Warning "row $($n+1): $($_.Exception.Message)" } }
            $n++
            if ($n % 100 -eq 0) { Write-Host "  ... $n / $($rows.Count)" }
        }
        Write-Host "Loaded $ok row(s), $fail failed." -ForegroundColor $(if ($fail) { "Yellow" } else { "Green" })
        if ($fail -gt 0) { Write-Host "(For large or repeated failures, stage to cloud storage and use -Action copy-from.)" }
    }

    "rows" {
        if (-not $Table) { throw "-Table required" }
        Write-Host "=== Rows in $Table (max $Limit) ===" -ForegroundColor Cyan
        $emptyQ = [uri]::EscapeDataString('{}')
        $amp = [char]38
        $rowsPath = "/db/$Table/query?q=$emptyQ${amp}eager=true${amp}count=$Limit"
        $resp = Invoke-Baas -Method GET -Path $rowsPath
        $objs = @($resp)
        if (-not $objs.Count) { Write-Host "(0 rows)"; break }
        $objs | Select-Object -Property * -ExcludeProperty acl, version |
            Format-Table -AutoSize | Out-String | Write-Host
        Write-Host "($($objs.Count) row$(if($objs.Count -ne 1){'s'}))"
    }
}
