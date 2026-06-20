# sql.ps1 — Full SQL + data loading on an Avalanche warehouse via JDBC or ODBC.
#
# This is the data-management engine for the admiral skill. It runs ARBITRARY SQL —
# SELECT, DDL (CREATE/DROP/MODIFY), INSERT … VALUES, and COPY … VWLOAD cloud bulk
# loads — against the warehouse's native SQL endpoint. No browser, no Query Editor,
# no SQLPad, no session cookie: it connects with a real database driver.
#
#   -Engine jdbc  (default)  Java + the Actian Ingres JDBC driver (iijdbc.jar).
#                            URL: jdbc:ingres://<host>:<port>/<db>
#   -Engine odbc             PowerShell System.Data.Odbc + the installed Actian/Ingres
#                            ODBC driver (DSN-less connection string).
#
# Connection comes from the "db" block of admiral.config.json (host/port/database/
# username/password/encryption), overridable per-call with -DbHost/-Port/-Database/
# -DbUser/-DbPassword, or resolved from -ResourceId via the Admiral API.
#
# ── Actions ──────────────────────────────────────────────────────────────────────
#   Meta:
#     connection-info                         resolve + test the connection
#   SQL:
#     query        -Sql "SELECT ..."          run SQL, render the result grid
#     exec         -Sql "CREATE TABLE ..."    run DDL/DML, report rows affected
#     run-file     -SqlFile script.sql        run a ;-separated batch (orchestration)
#     export-csv   -Sql "SELECT ..." -OutFile out.csv
#   Schema:
#     list-tables                             user tables (iitables catalog)
#     describe     -Table t                   columns + types (current user's schema only)
#     count        -Table t                   SELECT COUNT(*)
#     create-table -Table t -Columns "id INT, name VARCHAR(50), amt FLOAT"
#     drop-table   -Table t
#     truncate     -Table t                   MODIFY t TO TRUNCATED
#   Loading:
#     load-csv     -Table t -CsvFile data.csv [-CreateTable] [-Delimiter ","] [-BatchSize 500]
#     vwload       -Table t -Source "gs://b/f*.csv.gz" -GcsKeyFile sa.json [-Header] [-FieldDelim ","] [-QuoteChar '"']
#     vwload       -Table t -Source "s3://b/f.csv"     -AwsKey K -AwsSecret S -AwsRegion us-east-1 [-Header]
#                  Defaults: RDELIM='\n', QUOTE='"', SET string_truncation IGNORE; auto-adds
#                  AUTO_DETECT_COMPRESSION when source matches *.gz. ExtraOptions deduplicates.
#     create-external -Table t -Columns "id INT, amt FLOAT" -Source "gs://b/dir/" [-Format csv]
#     list-gcs     -Source "gs://bucket[/prefix]" -GcsKeyFile sa.json
#                  Authenticates via JWT and lists GCS objects (name + size) - useful for
#                  verifying file names / extensions before a vwload.

param(
    [Parameter(Mandatory)]
    [ValidateSet("connection-info","query","exec","run-file","export-csv",
                 "list-tables","describe","count","create-table","drop-table","truncate",
                 "load-csv","vwload","create-external","list-gcs")]
    [string]$Action,

    [ValidateSet("jdbc","odbc")]
    [string]$Engine = "jdbc",

    # Connection overrides (else taken from admiral.config.json "db" block)
    [string]$ResourceId,
    [string]$DbHost,
    [int]$Port,
    [string]$Database,
    [string]$DbUser,
    [string]$DbPassword,

    # SQL / files
    [string]$Sql,
    [string]$SqlFile,
    [string]$OutFile,
    [int]$MaxRows = 1000,

    # Schema / tables
    [string]$Table,
    [string]$Columns,        # raw SQL column list: "id INT, name VARCHAR(50), amt FLOAT"

    # Local CSV load
    [string]$CsvFile,
    [string]$Delimiter = ",",
    [switch]$CreateTable,
    [int]$BatchSize = 500,

    # Cloud bulk load (vwload / external)
    [string]$Source,         # gs://bucket/file*.csv  or  s3://bucket/key.csv (comma-list ok)
    [string]$GcsKeyFile,     # GCP service-account JSON (for gs://)
    [string]$AwsKey,
    [string]$AwsSecret,
    [string]$AwsRegion,
    [string]$Format = "csv", # create-external format
    [string]$FieldDelim = ",",
    [string]$QuoteChar  = '"',  # VWLOAD QUOTE option; set to '' to omit
    [switch]$Header,
    [string]$ExtraOptions    # merged into VWLOAD WITH(...); duplicates of auto-set keys are skipped
)

. "$PSScriptRoot\_admiral_common.ps1"

# ── Connection config ─────────────────────────────────────────────────────────────

function Get-DbConfig {
    if ($script:DbConfig) { return $script:DbConfig }
    $cfg = Get-AdmiralConfig
    # Prefer a nested "db" block; fall back to legacy flat db* keys for compatibility.
    $db = if ($cfg.PSObject.Properties["db"]) { $cfg.db } else { $null }
    $get = {
        param($nested, $flat, $default)
        if ($db -and $db.PSObject.Properties[$nested]) { return $db.$nested }
        if ($cfg.PSObject.Properties[$flat]) { return $cfg.$flat }
        return $default
    }
    $host_ = $DbHost
    if (-not $host_ -and $ResourceId) {
        $wh = Invoke-AdmiralApi -Path "/resource/warehouse/$ResourceId"
        $host_ = $wh.dns
        if (-not $host_) { $wh = Invoke-AdmiralApi -Path "/resource/database/$ResourceId"; $host_ = $wh.dns }
    }
    if (-not $host_) { $host_ = & $get 'host' 'dbHost' $null }
    if (-not $host_) { throw "No DB host. Set db.host in admiral.config.json or pass -DbHost/-ResourceId." }

    $c = @{
        Host       = $host_
        Port       = if ($Port)       { $Port }       else { [int](& $get 'port'       'dbPort'       27839) }
        Database   = if ($Database)   { $Database }   else { & $get 'database'   'dbName'       'db' }
        User       = if ($DbUser)     { $DbUser }     else { & $get 'username'   'dbUsername'   $null }
        Password   = if ($DbPassword) { $DbPassword } else { & $get 'password'   'dbPassword'   $null }
        Encryption = & $get 'encryption' 'dbEncryption' 'on'
    }
    if (-not $c.User)     { throw "No DB username. Set db.username in admiral.config.json or pass -DbUser." }
    if (-not $c.Password) { throw "No DB password. Set db.password in admiral.config.json or pass -DbPassword." }
    $script:DbConfig = $c
    return $c
}

# ── JDBC engine ───────────────────────────────────────────────────────────────────

function Get-IiJdbcJar {
    $cfg = Get-AdmiralConfig
    if ($cfg.PSObject.Properties["jdbcJar"] -and (Test-Path $cfg.jdbcJar)) { return $cfg.jdbcJar }
    $candidates = @(
        (Join-Path $env:II_SYSTEM "ingres\lib\iijdbc.jar"),
        "C:\Program Files\Actian\Actian Client AC\ingres\lib\iijdbc.jar",
        "C:\Program Files\Actian\Vector\ingres\lib\iijdbc.jar"
    )
    foreach ($p in $candidates) { if ($p -and (Test-Path $p)) { return $p } }
    throw "iijdbc.jar not found. Install the Actian client or set 'jdbcJar' in admiral.config.json. Looked: $($candidates -join '; ')"
}

# Compile SqlRunner.java once; recompile only if the source is newer than the class.
function Ensure-SqlRunner {
    $src   = Join-Path $PSScriptRoot "SqlRunner.java"
    $class = Join-Path $PSScriptRoot "SqlRunner.class"
    if (-not (Test-Path $src)) { throw "Missing $src" }
    if ((Test-Path $class) -and (Get-Item $class).LastWriteTime -ge (Get-Item $src).LastWriteTime) { return }
    $javac = (Get-Command javac -ErrorAction SilentlyContinue)
    if (-not $javac) { throw "javac not found on PATH (need a JDK to use -Engine jdbc; or use -Engine odbc)." }
    & javac -d $PSScriptRoot $src 2>&1 | ForEach-Object { Write-Verbose $_ }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $class)) { throw "Failed to compile SqlRunner.java" }
}

function Ensure-GcsLister {
    $src   = Join-Path $PSScriptRoot "GcsLister.java"
    $class = Join-Path $PSScriptRoot "GcsLister.class"
    if (-not (Test-Path $src)) { throw "Missing $src - required for list-gcs" }
    if ((Test-Path $class) -and (Get-Item $class).LastWriteTime -ge (Get-Item $src).LastWriteTime) { return }
    $javac = (Get-Command javac -ErrorAction SilentlyContinue)
    if (-not $javac) { throw "javac not found on PATH (need a JDK for list-gcs)." }
    & javac -d $PSScriptRoot $src 2>&1 | ForEach-Object { Write-Verbose $_ }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $class)) { throw "Failed to compile GcsLister.java" }
}

function Invoke-SqlJdbc {
    param([string]$Batch, [int]$Max = 1000)
    Ensure-SqlRunner
    $jar = Get-IiJdbcJar
    $c   = Get-DbConfig
    $url = "jdbc:ingres://$($c.Host):$($c.Port)/$($c.Database)"
    if ("$($c.Encryption)".ToLower() -in @('on','wire','true','1')) { $url += ";encryption=on" }

    $connFile = [System.IO.Path]::GetTempFileName()
    $sqlFile  = [System.IO.Path]::GetTempFileName()
    try {
        # Write BOM-less UTF-8: a BOM would prepend U+FEFF to the JDBC URL / first
        # statement (PS5.1 Set-Content -Encoding UTF8 emits a BOM). Keep the password
        # out of the process args by passing it through the file, not the command line.
        $noBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($connFile, ($url + "`n" + $c.User + "`n" + $c.Password + "`n"), $noBom)
        [System.IO.File]::WriteAllText($sqlFile, $Batch, $noBom)
        $cp  = "$jar;$PSScriptRoot"
        $out = & java -cp $cp SqlRunner $connFile $sqlFile $Max 2>&1
        $text = ($out | Out-String).Trim()
        if (-not $text.StartsWith("[")) { throw "JDBC runner error: $text" }
        $parsed = $text | ConvertFrom-Json
        return @($parsed)
    } finally {
        Remove-Item $connFile, $sqlFile -ErrorAction SilentlyContinue
    }
}

# ── ODBC engine ───────────────────────────────────────────────────────────────────

function Get-OdbcConnString {
    $c = Get-DbConfig
    $cfg = Get-AdmiralConfig
    $driver = if ($cfg.PSObject.Properties["odbcDriver"]) { $cfg.odbcDriver } else { "Actian AC" }
    # Ingres/Actian Net DSN-less form: Servername=@host,tcp_ip,port
    $enc = if ("$($c.Encryption)".ToLower() -in @('on','wire','true','1')) { "Encryption Mechanism=ssl;" } else { "" }
    return "Driver={$driver};Server=@$($c.Host),tcp_ip,$($c.Port);Database=$($c.Database);" +
           "UID=$($c.User);PWD=$($c.Password);$enc"
}

function Invoke-SqlOdbc {
    param([string]$Batch, [int]$Max = 1000)
    Add-Type -AssemblyName System.Data
    $stmts = Split-SqlStatements $Batch
    $results = @()
    $conn = New-Object System.Data.Odbc.OdbcConnection (Get-OdbcConnString)
    $conn.Open()
    try {
        foreach ($s in $stmts) {
            if (-not $s.Trim()) { continue }
            $cmd = $conn.CreateCommand(); $cmd.CommandText = $s
            try {
                $reader = $cmd.ExecuteReader()
                if ($reader.FieldCount -gt 0 -and -not $reader.IsClosed) {
                    $cols = @(); for ($i=0; $i -lt $reader.FieldCount; $i++) { $cols += $reader.GetName($i) }
                    $rows = @(); $n = 0
                    while ($reader.Read() -and $n -lt $Max) {
                        $r = @(); for ($i=0; $i -lt $reader.FieldCount; $i++) {
                            $v = $reader.GetValue($i); $r += $(if ($v -is [System.DBNull]) { $null } else { "$v" })
                        }
                        $rows += ,$r; $n++
                    }
                    $results += [PSCustomObject]@{ type="query"; columns=$cols; rows=$rows; rowCount=$rows.Count }
                } else {
                    $results += [PSCustomObject]@{ type="update"; updateCount=$reader.RecordsAffected }
                }
                $reader.Close()
            } catch {
                $results += [PSCustomObject]@{ type="error"; message=$_.Exception.Message; sqlState=$null; errorCode=0 }
            }
        }
    } finally { $conn.Close() }
    return $results
}

# Same splitting rule as the Java side, for the ODBC path.
function Split-SqlStatements {
    param([string]$s)
    $out = @(); $cur = New-Object System.Text.StringBuilder; $inS=$false; $inD=$false
    foreach ($ch in $s.ToCharArray()) {
        if ($ch -eq "'" -and -not $inD) { $inS = -not $inS }
        elseif ($ch -eq '"' -and -not $inS) { $inD = -not $inD }
        if ($ch -eq ';' -and -not $inS -and -not $inD) { $out += $cur.ToString(); $cur.Clear() | Out-Null }
        else { $cur.Append($ch) | Out-Null }
    }
    if ($cur.ToString().Trim()) { $out += $cur.ToString() }
    return $out
}

# ── Engine dispatch + rendering ────────────────────────────────────────────────────

function Invoke-Sql {
    param([string]$Batch, [int]$Max = $MaxRows)
    if ($Engine -eq "odbc") { return Invoke-SqlOdbc -Batch $Batch -Max $Max }
    return Invoke-SqlJdbc -Batch $Batch -Max $Max
}

function Show-SqlResults {
    param($Results, [switch]$Quiet)
    $errCount = 0
    foreach ($s in @($Results)) {
        switch ($s.type) {
            "error" {
                $errCount++
                $sqlState = if ($s.sqlState) { " [$($s.sqlState)]" } else { "" }
                Write-Host "ERROR${sqlState}: $($s.message)" -ForegroundColor Red
            }
            "update" {
                if (-not $Quiet) { Write-Host "OK ($($s.updateCount) row(s) affected)" -ForegroundColor Green }
            }
            "query" {
                $cols = @($s.columns)
                $table = foreach ($row in @($s.rows)) {
                    $o = [ordered]@{}
                    for ($i=0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $row[$i] }
                    [PSCustomObject]$o
                }
                if (@($table).Count) {
                    $table | Format-Table -AutoSize | Out-String | Write-Host
                    Write-Host "($($s.rowCount) row$(if($s.rowCount -ne 1){'s'}))"
                } else {
                    Write-Host "(0 rows)"
                }
            }
        }
    }
    return $errCount
}

function Get-FirstScalar {
    param($Results)
    foreach ($s in @($Results)) {
        if ($s.type -eq "error") { throw "SQL error: $($s.message)" }
        if ($s.type -eq "query" -and @($s.rows).Count) { return @($s.rows)[0][0] }
    }
    return $null
}

# Quote an identifier and escape a string literal for Ingres SQL.
function Quote-Ident { param([string]$n) '"' + ($n -replace '"','""') + '"' }
function Quote-Lit   { param([string]$v) "'" + ($v -replace "'","''") + "'" }

# Build the GCS credential clause for VWLOAD from a service-account JSON file.
function Get-GcsCredClause {
    param([string]$KeyFile)
    if (-not $KeyFile)             { throw "-GcsKeyFile <service-account.json> required for gs:// sources" }
    if (-not (Test-Path $KeyFile)) { throw "Service-account file not found: $KeyFile" }
    $sa = Get-Content $KeyFile -Raw | ConvertFrom-Json
    foreach ($f in 'client_email','private_key_id','private_key') {
        if (-not $sa.$f) { throw "Service-account JSON missing '$f'." }
    }
    $pk = ($sa.private_key -replace "`r`n","`n") -replace "`n",'\n'
    return "gcs_email='$($sa.client_email)', gcs_private_key_id='$($sa.private_key_id)', gcs_private_key='$pk'"
}

# ── Local CSV → SQL type inference ────────────────────────────────────────────────

function Get-CsvSqlColumns {
    param([object[]]$Rows)
    if (-not $Rows) { throw "CSV is empty or unreadable." }
    $sample = $Rows | Select-Object -First 200
    $names  = $sample[0].PSObject.Properties.Name
    foreach ($name in $names) {
        $vals = $sample | ForEach-Object { $_.$name } | Where-Object { $_ -ne $null -and $_ -ne "" }
        $sqlType = "VARCHAR(255)"; $kind = "str"
        if ($vals) {
            $cnt = @($vals).Count
            if (@($vals | Where-Object { $_ -match '^-?\d+$' }).Count -eq $cnt)                   { $sqlType="BIGINT"; $kind="int" }
            elseif (@($vals | Where-Object { $_ -match '^-?\d+(\.\d+)?$' }).Count -eq $cnt)        { $sqlType="FLOAT"; $kind="num" }
            elseif (@($vals | Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}( |T)\d{2}:' }).Count -eq $cnt) { $sqlType="TIMESTAMP"; $kind="str" }
            elseif (@($vals | Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}$' }).Count -eq $cnt)    { $sqlType="DATE"; $kind="str" }
            else {
                $maxLen = ($vals | Measure-Object -Property Length -Maximum).Maximum
                $w = [Math]::Max(50, [int]([Math]::Ceiling($maxLen / 50.0) * 50))
                $sqlType = "VARCHAR($w)"
            }
        }
        [PSCustomObject]@{ Name=$name; SqlType=$sqlType; Kind=$kind }
    }
}

function Format-SqlValue {
    param($Value, [string]$Kind)
    if ($null -eq $Value -or $Value -eq "") { return "NULL" }
    switch ($Kind) {
        "int" { return "$Value" }
        "num" { return "$Value" }
        default { return (Quote-Lit "$Value") }
    }
}

# ── Actions ────────────────────────────────────────────────────────────────────────

switch ($Action) {

    "connection-info" {
        $c = Get-DbConfig
        Write-Host "=== Avalanche SQL connection ($Engine) ===" -ForegroundColor Cyan
        Write-Host "  Host     : $($c.Host)"
        Write-Host "  Port     : $($c.Port)"
        Write-Host "  Database : $($c.Database)"
        Write-Host "  User     : $($c.User)"
        Write-Host "  Encrypt  : $($c.Encryption)"
        if ($Engine -eq "jdbc") { Write-Host "  JDBC URL : jdbc:ingres://$($c.Host):$($c.Port)/$($c.Database)" }
        else                    { Write-Host "  ODBC     : $((Get-OdbcConnString) -replace 'PWD=[^;]*','PWD=***')" }
        Write-Host ""
        try {
            $r = Invoke-Sql -Batch "SELECT dbmsinfo('_version') AS version, dbmsinfo('database') AS database" -Max 1
            if ((Show-SqlResults $r) -eq 0) { Write-Host "Auth: OK" -ForegroundColor Green }
        } catch { Write-Host "Connection FAILED: $($_.Exception.Message)" -ForegroundColor Red }
    }

    "query" {
        if (-not $Sql) { throw "-Sql required" }
        Write-Host "=== query ($Engine) ===" -ForegroundColor Cyan
        Write-Host $Sql; Write-Host ""
        Show-SqlResults (Invoke-Sql -Batch $Sql) | Out-Null
    }

    "exec" {
        if (-not $Sql) { throw "-Sql required" }
        Write-Host "=== exec ($Engine) ===" -ForegroundColor Cyan
        Write-Host $Sql; Write-Host ""
        Show-SqlResults (Invoke-Sql -Batch $Sql) | Out-Null
    }

    "run-file" {
        if (-not $SqlFile) { throw "-SqlFile required" }
        if (-not (Test-Path $SqlFile)) { throw "File not found: $SqlFile" }
        $text = Get-Content $SqlFile -Raw
        Write-Host "=== run-file ($Engine): $SqlFile ===" -ForegroundColor Cyan
        $errs = Show-SqlResults (Invoke-Sql -Batch $text)
        if ($errs) { Write-Host "$errs statement(s) failed." -ForegroundColor Yellow }
    }

    "export-csv" {
        if (-not $Sql)     { throw "-Sql required" }
        if (-not $OutFile) { throw "-OutFile required" }
        $res = Invoke-Sql -Batch $Sql -Max ([Math]::Max($MaxRows, 1000000))
        $q = @($res) | Where-Object { $_.type -eq "query" } | Select-Object -First 1
        $err = @($res) | Where-Object { $_.type -eq "error" } | Select-Object -First 1
        if ($err) { Write-Host "ERROR: $($err.message)" -ForegroundColor Red; break }
        if (-not $q) { Write-Host "Query returned no result set."; break }
        $cols = @($q.columns)
        $table = foreach ($row in @($q.rows)) {
            $o = [ordered]@{}; for ($i=0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $row[$i] }; [PSCustomObject]$o
        }
        $abs = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path (Get-Location) $OutFile }
        @($table) | Export-Csv -Path $abs -NoTypeInformation -Encoding UTF8
        Write-Host "Wrote $($q.rowCount) rows -> $abs" -ForegroundColor Green
    }

    "list-tables" {
        $sql = "SELECT TRIM(table_name) AS table_name, TRIM(table_owner) AS owner FROM iitables " +
               "WHERE table_type='T' AND table_owner NOT IN ('`$ingres','iidbdb') ORDER BY table_name"
        Write-Host "=== tables ($Engine) ===" -ForegroundColor Cyan
        Show-SqlResults (Invoke-Sql -Batch $sql) | Out-Null
    }

    "describe" {
        if (-not $Table) { throw "-Table required" }
        $sql = "SELECT TRIM(column_name) AS column_name, column_datatype, column_length, column_nulls " +
               "FROM iicolumns WHERE table_name=$(Quote-Lit $Table) " +
               "AND table_owner = DBMSINFO('username') ORDER BY column_sequence"
        Write-Host "=== $Table ===" -ForegroundColor Cyan
        Show-SqlResults (Invoke-Sql -Batch $sql) | Out-Null
    }

    "count" {
        if (-not $Table) { throw "-Table required" }
        $n = Get-FirstScalar (Invoke-Sql -Batch "SELECT COUNT(*) FROM $(Quote-Ident $Table)")
        Write-Host "$Table : $n row(s)"
    }

    "create-table" {
        if (-not $Table)   { throw "-Table required" }
        if (-not $Columns) { throw "-Columns required (e.g. 'id INT, name VARCHAR(50), amt FLOAT')" }
        $sql = "CREATE TABLE $(Quote-Ident $Table) ($Columns)"
        Write-Host "=== create-table $Table ===" -ForegroundColor Cyan
        Write-Host $sql; Write-Host ""
        Show-SqlResults (Invoke-Sql -Batch $sql) | Out-Null
    }

    "drop-table" {
        if (-not $Table) { throw "-Table required" }
        Write-Host "=== drop-table $Table ===" -ForegroundColor Yellow
        Show-SqlResults (Invoke-Sql -Batch "DROP TABLE $(Quote-Ident $Table)") | Out-Null
    }

    "truncate" {
        if (-not $Table) { throw "-Table required" }
        Write-Host "=== truncate $Table ===" -ForegroundColor Yellow
        Show-SqlResults (Invoke-Sql -Batch "MODIFY $(Quote-Ident $Table) TO TRUNCATED") | Out-Null
    }

    "load-csv" {
        if (-not $Table)   { throw "-Table required" }
        if (-not $CsvFile) { throw "-CsvFile required" }
        if (-not (Test-Path $CsvFile)) { throw "File not found: $CsvFile" }
        $rows = @(Import-Csv -Path $CsvFile -Delimiter $Delimiter[0])
        if (-not $rows.Count) { throw "CSV is empty or unreadable: $CsvFile" }
        $colDefs = Get-CsvSqlColumns -Rows $rows

        if ($CreateTable) {
            $colSql = ($colDefs | ForEach-Object { "$(Quote-Ident $_.Name) $($_.SqlType)" }) -join ", "
            Write-Host "=== create-table $Table from CSV ===" -ForegroundColor Cyan
            $colDefs | ForEach-Object { Write-Host "  $($_.Name) -> $($_.SqlType)" }
            $r = Invoke-Sql -Batch "CREATE TABLE $(Quote-Ident $Table) ($colSql)"
            if ((Show-SqlResults $r -Quiet) -ne 0) { throw "Failed to create table." }
        }

        Write-Host "=== load-csv: $($rows.Count) rows -> $Table (batched INSERT, $Engine) ===" -ForegroundColor Cyan
        $colList = "(" + (($colDefs | ForEach-Object { Quote-Ident $_.Name }) -join ", ") + ")"
        $ok = 0; $fail = 0; $i = 0
        while ($i -lt $rows.Count) {
            $chunk = $rows[$i..([Math]::Min($i+$BatchSize-1, $rows.Count-1))]
            $tuples = foreach ($row in $chunk) {
                $vals = foreach ($c in $colDefs) { Format-SqlValue $row.($c.Name) $c.Kind }
                "(" + ($vals -join ", ") + ")"
            }
            $insert = "INSERT INTO $(Quote-Ident $Table) $colList VALUES " + ($tuples -join ", ")
            $r = Invoke-Sql -Batch $insert -Max 1
            $e = @($r) | Where-Object { $_.type -eq "error" } | Select-Object -First 1
            if ($e) { $fail += @($chunk).Count; if ($fail -le ($BatchSize*2)) { Write-Warning "batch @ row $($i+1): $($e.message)" } }
            else    { $ok += @($chunk).Count }
            $i += $BatchSize
            Write-Host "  ... $([Math]::Min($i,$rows.Count)) / $($rows.Count)"
        }
        Write-Host "Loaded $ok row(s), $fail failed." -ForegroundColor $(if ($fail) { "Yellow" } else { "Green" })
        if ($fail) { Write-Host "(For large files prefer staging to GCS/S3 and -Action vwload.)" }
    }

    "vwload" {
        if (-not $Table)  { throw "-Table required" }
        if (-not $Source) { throw "-Source required (gs://bucket/file*.csv.gz or s3://bucket/key.csv)" }
        # Build WITH clause options - RDELIM, QUOTE, and AUTO_DETECT_COMPRESSION are on by default
        $opts = @("FDELIM=$(Quote-Lit $FieldDelim)")
        if ($Header)     { $opts += "HEADER" }
        $opts += "RDELIM='\n'"
        if ($QuoteChar)  { $opts += "QUOTE=$(Quote-Lit $QuoteChar)" }
        if ($Source -match '\.gz') { $opts += "AUTO_DETECT_COMPRESSION" }
        if ($Source -match '^gs://') {
            $opts += (Get-GcsCredClause -KeyFile $GcsKeyFile)
        } elseif ($Source -match '^s3://') {
            if (-not ($AwsKey -and $AwsSecret -and $AwsRegion)) { throw "s3:// requires -AwsKey -AwsSecret -AwsRegion" }
            $opts += "aws_access_key=$(Quote-Lit $AwsKey)", "aws_secret_key=$(Quote-Lit $AwsSecret)", "aws_region=$(Quote-Lit $AwsRegion)"
        } else { throw "Unsupported -Source scheme (use gs:// or s3://): $Source" }
        # Merge ExtraOptions - skip keys already set to avoid duplicate-clause syntax errors
        if ($ExtraOptions) {
            $usedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($opt in $opts) { $usedKeys.Add(($opt -split '=')[0].Trim()) | Out-Null }
            $ExtraOptions -split ',(?=\s*[A-Za-z_])' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
                $key = ($_ -split '=')[0].Trim()
                if ($usedKeys.Contains($key)) { Write-Warning "ExtraOptions: '$key' already set by vwload defaults - skipping duplicate." }
                else { $opts += $_; $usedKeys.Add($key) | Out-Null }
            }
        }
        $sources  = ($Source -split ',' | ForEach-Object { Quote-Lit ($_.Trim()) }) -join ', '
        $copySql  = "COPY $(Quote-Ident $Table)() VWLOAD FROM $sources WITH " + ($opts -join ', ')
        # Always prepend SET string_truncation IGNORE - cloud source widths are unpredictable
        $batch    = "SET string_truncation IGNORE;`r`n$copySql"
        Write-Host "=== vwload -> $Table ($Engine) ===" -ForegroundColor Cyan
        Write-Host ($copySql -replace "gcs_private_key='[^']*'","gcs_private_key='***'" -replace "aws_secret_key='[^']*'","aws_secret_key='***'")
        Write-Host ""
        Show-SqlResults (Invoke-Sql -Batch $batch) | Out-Null
    }

    "list-gcs" {
        if (-not $Source -or $Source -notmatch '^gs://') { throw "-Source gs://bucket[/prefix] required" }
        if (-not $GcsKeyFile) { throw "-GcsKeyFile <service-account.json> required" }
        $uri    = $Source -replace '^gs://',''
        $parts  = $uri -split '/',2
        $bucket = $parts[0]
        $pfx    = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        Ensure-GcsLister
        Write-Host "=== GCS: gs://$bucket$(if($pfx){'/' + $pfx}) ===" -ForegroundColor Cyan
        $javaArgs = @("-cp", $PSScriptRoot, "GcsLister", $GcsKeyFile, $bucket)
        if ($pfx) { $javaArgs += $pfx }
        # GcsLister outputs "name\tsize" lines; 2>&1 gives mixed strings+ErrorRecords - filter to strings
        $rawOut = & java @javaArgs 2>&1
        $lines  = @($rawOut | Where-Object { $_ -is [string] -and "$_".Trim() })
        $errOut = ($rawOut | Where-Object { $_ -isnot [string] } | Out-String).Trim()
        if ($errOut) { Write-Host "GcsLister warning: $errOut" -ForegroundColor Yellow }
        if (-not $lines.Count) {
            Write-Host "(no objects found)" -ForegroundColor Yellow
        } else {
            Write-Host ("{0,-55} {1,12}" -f "Name","Size (MB)")
            Write-Host ("{0,-55} {1,12}" -f "----","--------")
            foreach ($line in $lines) {
                $parts  = "$line".Split("`t")
                $name   = $parts[0]
                $sizeMB = if ($parts.Count -gt 1) {
                    try { "{0:N2}" -f ([double]$parts[1] / 1MB) } catch { "?" }
                } else { "?" }
                Write-Host ("{0,-55} {1,12}" -f $name, $sizeMB)
            }
            Write-Host ""
            Write-Host "$($lines.Count) object(s)"
        }
    }

    "create-external" {
        if (-not $Table)   { throw "-Table required" }
        if (-not $Columns) { throw "-Columns required (e.g. 'id INT, amt FLOAT')" }
        if (-not $Source)  { throw "-Source required (e.g. gs://bucket/dir/)" }
        $sql = "CREATE EXTERNAL TABLE $(Quote-Ident $Table) ($Columns) USING SPARK " +
               "WITH REFERENCE=$(Quote-Lit $Source), FORMAT=$(Quote-Lit $Format)"
        if ($ExtraOptions) { $sql += ", $ExtraOptions" }
        Write-Host "=== create-external $Table -> $Source ===" -ForegroundColor Cyan
        Write-Host $sql
        Write-Host "(External tables use cloud credentials configured on the warehouse, not inline.)"
        Write-Host ""
        Show-SqlResults (Invoke-Sql -Batch $sql) | Out-Null
    }
}
