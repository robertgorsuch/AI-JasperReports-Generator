# data_load.ps1 — Execute SQL, load CSV files, and browse schema on an Avalanche warehouse.
#
# Connects via psql (PostgreSQL protocol, port 5432/5439) or isql (Actian native, port 27833).
# Credentials come from admiral.config.json (dbUsername / dbPassword / dbName fields) or parameters.
#
# Usage:
#   .\data_load.ps1 -Action connection-info [-ResourceId av-xxxxx]
#   .\data_load.ps1 -Action run-sql   -Sql "SELECT * FROM t LIMIT 5"
#   .\data_load.ps1 -Action run-file  -SqlFile path\to\script.sql
#   .\data_load.ps1 -Action copy-from-csv -Table my_table  -CsvFile data.csv  [-Delimiter ","] [-Header]
#   .\data_load.ps1 -Action copy-to-csv   -Sql "SELECT * FROM t" -OutFile out.csv
#   .\data_load.ps1 -Action schema-tables  [-Schema public]
#   .\data_load.ps1 -Action schema-columns -Table my_table
#   .\data_load.ps1 -Action table-count    -Table my_table
#   .\data_load.ps1 -Action create-table-from-csv -Table my_table -CsvFile data.csv [-Load]
#   .\data_load.ps1 -Action s3-copy-from  -Table t -S3Path "s3://bucket/file.csv" [-Format CSV] [-Header]
#   .\data_load.ps1 -Action s3-create-external -Table ext_t -S3Path "s3://bucket/data/" -Columns "id INT, name TEXT"
#   .\data_load.ps1 -Action list-external-tables
#   .\data_load.ps1 -Action drop-table -Table my_table [-IfExists] [-External]
#
# Add to admiral.config.json:
#   "dbUsername": "actian",
#   "dbPassword": "YOUR_DB_PASSWORD",
#   "dbName":     "db",
#   "dbPort":     5432

param(
    [Parameter(Mandatory)]
    [ValidateSet("connection-info","run-sql","run-file","copy-from-csv","copy-to-csv",
                 "schema-tables","schema-columns","table-count","create-table-from-csv",
                 "s3-copy-from","s3-create-external","list-external-tables","drop-table")]
    [string]$Action,

    # Connection overrides (fall back to config)
    [string]$ResourceId,
    [string]$DbHost,
    [int]$DbPort      = 0,
    [string]$DbUser,
    [string]$DbPass,
    [string]$DbName,
    [ValidateSet("psql","isql")]
    [string]$Client   = "psql",

    # SQL / file
    [string]$Sql,
    [string]$SqlFile,

    # Table operations
    [string]$Table,
    [string]$Schema    = "public",

    # CSV operations
    [string]$CsvFile,
    [string]$OutFile,
    [string]$Delimiter = ",",
    [switch]$Header,

    # S3 operations
    [string]$S3Path,
    [string]$Format    = "CSV",
    [string]$Columns,   # e.g. "id INT, name TEXT, amount DECIMAL(10,2)"

    # Table flags
    [switch]$IfExists,
    [switch]$External,
    [switch]$Load       # in create-table-from-csv: also load data after creating
)

. "$PSScriptRoot\_admiral_common.ps1"

# ── Resolve connection params ─────────────────────────────────────────────────

function Get-DbConnection {
    $cfg = Get-AdmiralConfig

    # If ResourceId given, get DNS from Admiral API
    $dns = $DbHost
    if (-not $dns -and $ResourceId) {
        $wh  = Invoke-AdmiralApi -Path "/resource/warehouse/$ResourceId"
        $dns = $wh.dns
        if (-not $dns) {
            $wh  = Invoke-AdmiralApi -Path "/resource/database/$ResourceId"
            $dns = $wh.dns
        }
    }
    if (-not $dns -and $cfg.PSObject.Properties["dbHost"]) { $dns = $cfg.dbHost }
    if (-not $dns) { throw "Cannot resolve host. Provide -DbHost, -ResourceId, or add 'dbHost' to admiral.config.json" }

    $user = if ($DbUser) { $DbUser } elseif ($cfg.PSObject.Properties["dbUsername"]) { $cfg.dbUsername } else { throw "Provide -DbUser or add 'dbUsername' to admiral.config.json" }
    $pass = if ($DbPass) { $DbPass } elseif ($cfg.PSObject.Properties["dbPassword"]) { $cfg.dbPassword } else { throw "Provide -DbPass or add 'dbPassword' to admiral.config.json" }
    $db   = if ($DbName) { $DbName } elseif ($cfg.PSObject.Properties["dbName"]) { $cfg.dbName } else { "db" }
    $port = if ($DbPort -gt 0) { $DbPort } elseif ($cfg.PSObject.Properties["dbPort"]) { [int]$cfg.dbPort } else { 5432 }

    return @{ Host = $dns; Port = $port; User = $user; Pass = $pass; Db = $db }
}

function Invoke-Psql {
    param([hashtable]$Conn, [string]$Command, [string]$InputFile, [string]$OutputFile, [switch]$Csv)

    $env:PGPASSWORD = $Conn.Pass
    $args_list = @("-h", $Conn.Host, "-p", $Conn.Port, "-U", $Conn.User, "-d", $Conn.Db, "--no-password")

    if ($Csv)        { $args_list += @("-A", "-F", ",", "--pset=footer=off") }
    if ($Command)    { $args_list += @("-c", $Command) }
    if ($InputFile)  { $args_list += @("-f", $InputFile) }
    if ($OutputFile) { $args_list += @("-o", $OutputFile) }

    if ($Command -or $InputFile) {
        $result = & psql @args_list 2>&1
    } else {
        $result = & psql @args_list 2>&1
    }
    $env:PGPASSWORD = $null
    return $result
}

function Invoke-Isql {
    param([hashtable]$Conn, [string]$Command, [string]$InputFile)
    # Actian isql uses vnode::database format or -h host
    $db_spec = "$($Conn.Host)::$($Conn.Db)"
    if ($Command) {
        $result = & isql $db_spec -u "$($Conn.User)" "-P$($Conn.Pass)" -q @("-execute", $Command) 2>&1
    } elseif ($InputFile) {
        $result = & isql $db_spec -u "$($Conn.User)" "-P$($Conn.Pass)" -q @("-file", $InputFile) 2>&1
    }
    return $result
}

function Invoke-DbCommand {
    param([hashtable]$Conn, [string]$Command, [string]$InputFile, [string]$OutputFile, [switch]$Csv)
    if ($Client -eq "isql") {
        return Invoke-Isql -Conn $Conn -Command $Command -InputFile $InputFile
    }
    return Invoke-Psql -Conn $Conn -Command $Command -InputFile $InputFile -OutputFile $OutputFile -Csv:$Csv
}

# ── Helpers ───────────────────────────────────────────────────────────────────

function Infer-ColumnTypes {
    param([string]$CsvPath, [string]$Delim = ",")
    $rows = Import-Csv -Path $CsvPath -Delimiter $Delim[0]
    if (-not $rows) { throw "CSV file is empty or unreadable: $CsvPath" }
    $first = $rows | Select-Object -First 200
    $cols  = $first[0].PSObject.Properties.Name

    $typeDefs = $cols | ForEach-Object {
        $col    = $_
        $values = $first | ForEach-Object { $_.$col } | Where-Object { $_ -and $_ -ne "" }
        $type   = "TEXT"  # default
        if ($values) {
            $allInt    = @($values | Where-Object { $_ -match '^\-?\d+$' }).Count -eq $values.Count
            $allFloat  = @($values | Where-Object { $_ -match '^\-?\d+(\.\d+)?$' }).Count -eq $values.Count
            $allDate   = @($values | Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}' }).Count -eq $values.Count
            $maxLen    = ($values | Measure-Object -Property Length -Maximum).Maximum
            if ($allInt)   { $type = "BIGINT" }
            elseif ($allFloat) { $type = "DOUBLE PRECISION" }
            elseif ($allDate)  { $type = "DATE" }
            elseif ($maxLen -le 255) { $type = "VARCHAR(255)" }
        }
        "`"$col`" $type"
    }
    return $typeDefs -join ",`n    "
}

# ── Actions ───────────────────────────────────────────────────────────────────

switch ($Action) {

    "connection-info" {
        $conn = Get-DbConnection
        Write-Host "=== Warehouse Connection Details ===" -ForegroundColor Cyan
        Write-Host "  Host:    $($conn.Host)"
        Write-Host "  Port:    $($conn.Port)"
        Write-Host "  User:    $($conn.User)"
        Write-Host "  Database:$($conn.Db)"
        Write-Host ""
        Write-Host "psql connection string:"
        Write-Host "  postgresql://$($conn.User)@$($conn.Host):$($conn.Port)/$($conn.Db)"
        Write-Host ""
        Write-Host "JDBC URL (PostgreSQL driver):"
        Write-Host "  jdbc:postgresql://$($conn.Host):$($conn.Port)/$($conn.Db)?user=$($conn.User)"
        Write-Host ""
        Write-Host "JDBC URL (Actian Avalanche driver):"
        Write-Host "  jdbc:actian-avalanche://$($conn.Host):5449/$($conn.Db);UID=$($conn.User)"
        Write-Host ""
        Write-Host "psql command:"
        Write-Host "  psql -h $($conn.Host) -p $($conn.Port) -U $($conn.User) -d $($conn.Db)"
        Write-Host ""
        Write-Host "Ports open on this host: 5432 (pg), 5439 (pg-alt), 27833 (Ingres native)"

        if ($ResourceId) {
            $wh = Invoke-AdmiralApi -Path "/resource/warehouse/$ResourceId" -ErrorAction SilentlyContinue
            if ($wh) {
                Write-Host ""
                Write-Host "Warehouse status: $($wh.status)"
                Write-Host "AU size:          $($wh.avalancheUnits)"
                Write-Host "Region:           $($wh.regionName)"
                $feat = $wh.features | Where-Object { $_.name -eq "dataAPI" }
                if ($feat) { Write-Host "Data API:         $($feat.status)" }
                Write-Host "Query Editor URL: https://$($wh.dns)/"
            }
        }
    }

    "run-sql" {
        if (-not $Sql) { throw "-Sql required" }
        $conn = Get-DbConnection
        Write-Host "=== Executing SQL ===" -ForegroundColor Cyan
        Write-Host $Sql
        Write-Host ""
        $result = Invoke-DbCommand -Conn $conn -Command $Sql
        $result | ForEach-Object { Write-Host $_ }
    }

    "run-file" {
        if (-not $SqlFile) { throw "-SqlFile required" }
        if (-not (Test-Path $SqlFile)) { throw "File not found: $SqlFile" }
        $conn = Get-DbConnection
        Write-Host "=== Executing SQL file: $SqlFile ===" -ForegroundColor Cyan
        $result = Invoke-DbCommand -Conn $conn -InputFile $SqlFile
        $result | ForEach-Object { Write-Host $_ }
    }

    "copy-from-csv" {
        if (-not $Table)   { throw "-Table required" }
        if (-not $CsvFile) { throw "-CsvFile required" }
        if (-not (Test-Path $CsvFile)) { throw "File not found: $CsvFile" }
        $conn    = Get-DbConnection
        $absPath = (Resolve-Path $CsvFile).Path.Replace("\","/")

        # Use psql \copy which transfers the file client-side
        $headerOpt = if ($Header) { ", HEADER true" } else { "" }
        $copyCmd   = "\copy `"$Table`" FROM '$absPath' WITH (FORMAT CSV, DELIMITER '$Delimiter'$headerOpt)"
        Write-Host "=== Loading CSV into $Table ===" -ForegroundColor Cyan
        Write-Host "  File:  $CsvFile"
        Write-Host "  Table: $Table"
        Write-Host ""
        $result = Invoke-Psql -Conn $conn -Command $copyCmd
        $result | ForEach-Object { Write-Host $_ }
    }

    "copy-to-csv" {
        if (-not $Sql)     { throw "-Sql required" }
        if (-not $OutFile) { throw "-OutFile required" }
        $conn    = Get-DbConnection
        $absPath = (Join-Path (Get-Location) $OutFile)
        $copyCmd = "\copy ($Sql) TO '$($absPath.Replace('\','/'))' WITH (FORMAT CSV, HEADER true)"
        Write-Host "=== Exporting query results to $OutFile ===" -ForegroundColor Cyan
        $result  = Invoke-Psql -Conn $conn -Command $copyCmd
        $result  | ForEach-Object { Write-Host $_ }
        if (Test-Path $absPath) { Write-Host "Wrote: $absPath ($((Get-Item $absPath).Length) bytes)" }
    }

    "schema-tables" {
        $conn = Get-DbConnection
        $sql  = "SELECT table_schema, table_name, table_type FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema') ORDER BY table_schema, table_name;"
        if ($Schema -ne "public") {
            $sql = "SELECT table_schema, table_name, table_type FROM information_schema.tables WHERE table_schema = '$Schema' ORDER BY table_name;"
        }
        Write-Host "=== Tables in database $($conn.Db) ===" -ForegroundColor Cyan
        Invoke-Psql -Conn $conn -Command $sql | ForEach-Object { Write-Host $_ }
    }

    "schema-columns" {
        if (-not $Table) { throw "-Table required" }
        $conn = Get-DbConnection
        $sql  = "SELECT column_name, data_type, character_maximum_length, is_nullable, column_default FROM information_schema.columns WHERE table_name = '$Table' AND table_schema = '$Schema' ORDER BY ordinal_position;"
        Write-Host "=== Columns: $Schema.$Table ===" -ForegroundColor Cyan
        Invoke-Psql -Conn $conn -Command $sql | ForEach-Object { Write-Host $_ }
    }

    "table-count" {
        if (-not $Table) { throw "-Table required" }
        $conn = Get-DbConnection
        Write-Host "=== Row count: $Table ===" -ForegroundColor Cyan
        Invoke-Psql -Conn $conn -Command "SELECT COUNT(*) AS row_count FROM `"$Table`";" | ForEach-Object { Write-Host $_ }
    }

    "create-table-from-csv" {
        if (-not $Table)   { throw "-Table required" }
        if (-not $CsvFile) { throw "-CsvFile required" }
        if (-not (Test-Path $CsvFile)) { throw "File not found: $CsvFile" }

        $conn    = Get-DbConnection
        $colDefs = Infer-ColumnTypes -CsvPath $CsvFile -Delim $Delimiter

        $createSql = @"
CREATE TABLE IF NOT EXISTS "$Table" (
    $colDefs
);
"@
        Write-Host "=== Creating table: $Table ===" -ForegroundColor Cyan
        Write-Host $createSql
        Invoke-Psql -Conn $conn -Command $createSql | ForEach-Object { Write-Host $_ }

        if ($Load) {
            Write-Host "`n=== Loading data from $CsvFile ===" -ForegroundColor Cyan
            $absPath  = (Resolve-Path $CsvFile).Path.Replace("\","/")
            $copyCmd  = "\copy `"$Table`" FROM '$absPath' WITH (FORMAT CSV, HEADER true, DELIMITER '$Delimiter')"
            Invoke-Psql -Conn $conn -Command $copyCmd | ForEach-Object { Write-Host $_ }
        }
    }

    "s3-copy-from" {
        if (-not $Table)  { throw "-Table required" }
        if (-not $S3Path) { throw "-S3Path required (e.g. s3://bucket/file.csv)" }
        $headerOpt = if ($Header) { ", HEADER" } else { "" }
        $sql = "COPY `"$Table`" FROM '$S3Path' WITH ($Format$headerOpt);"
        Write-Host "=== S3 COPY FROM ===" -ForegroundColor Cyan
        Write-Host "SQL: $sql"
        Write-Host "(Requires S3 credentials configured via resource.ps1 -Action external-table-creds)"
        Write-Host ""
        $conn = Get-DbConnection
        Invoke-Psql -Conn $conn -Command $sql | ForEach-Object { Write-Host $_ }
    }

    "s3-create-external" {
        if (-not $Table)   { throw "-Table required" }
        if (-not $S3Path)  { throw "-S3Path required (e.g. s3://bucket/data/)" }
        if (-not $Columns) { throw "-Columns required (e.g. 'id INT, name TEXT, amount DECIMAL(10,2)')" }
        $sql = @"
CREATE EXTERNAL TABLE IF NOT EXISTS "$Table" (
    $Columns
)
LOCATION '$S3Path'
FORMAT '$Format'
$(if($Header){"OPTIONS (HEADER 'true')"});
"@
        Write-Host "=== Creating S3 External Table: $Table ===" -ForegroundColor Cyan
        Write-Host $sql
        Write-Host "(Requires S3 credentials configured via resource.ps1 -Action external-table-creds)"
        Write-Host ""
        $conn = Get-DbConnection
        Invoke-Psql -Conn $conn -Command $sql | ForEach-Object { Write-Host $_ }
    }

    "list-external-tables" {
        $conn = Get-DbConnection
        $sql  = @"
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_type = 'FOREIGN'
   OR table_name IN (
       SELECT foreign_table_name FROM information_schema.foreign_tables
   )
ORDER BY table_name;
"@
        Write-Host "=== External Tables ===" -ForegroundColor Cyan
        Invoke-Psql -Conn $conn -Command $sql | ForEach-Object { Write-Host $_ }
    }

    "drop-table" {
        if (-not $Table) { throw "-Table required" }
        $conn     = Get-DbConnection
        $ifEx     = if ($IfExists) { "IF EXISTS " } else { "" }
        $extKw    = if ($External)  { "EXTERNAL " } else { "" }
        $sql      = "DROP ${extKw}TABLE ${ifEx}`"$Table`";"
        Write-Host "=== Dropping ${extKw}table: $Table ===" -ForegroundColor Yellow
        Invoke-Psql -Conn $conn -Command $sql | ForEach-Object { Write-Host $_ }
    }
}
