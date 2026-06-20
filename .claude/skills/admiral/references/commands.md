# Admiral — full command reference

Detailed examples for every script action. SKILL.md has the overview, gotchas, and
script index; this file is the exhaustive flag-by-flag reference. Every script lives in
`scripts/` and is run as `& "$skill\<script>.ps1" -Action ...` where
`$skill = ".\.claude\skills\admiral\scripts"`. Each script also self-documents its
actions via its `-Action` ValidateSet and header comment.

---

## `tenant.ps1` — Tenant info

```powershell
.\tenant.ps1 -Action details        # AU quota, enabled features
.\tenant.ps1 -Action entitlements   # compute + storage entitlements with dates
.\tenant.ps1 -Action features       # feature flags
```

---

## `resource.ps1` — Warehouse and database lifecycle

Works for both `-ResourceType warehouse` (default) and `-ResourceType database`.

**List / inspect**
```powershell
.\resource.ps1 -Action list   -ResourceType warehouse
.\resource.ps1 -Action get    -ResourceType warehouse -ResourceId av-49jtc8yy9xi4
.\resource.ps1 -Action config -ResourceType warehouse   # platforms, regions, AU sizes
.\resource.ps1 -Action last-request  -ResourceType warehouse -ResourceId av-xxxxx
.\resource.ps1 -Action backups       -ResourceType warehouse -ResourceId av-xxxxx
.\resource.ps1 -Action clone-history -ResourceType warehouse -ResourceId av-xxxxx
```

**Create**
```powershell
.\resource.ps1 -Action create -ResourceType warehouse `
    -Name "MyWarehouse" -Platform Google -RegionId us-east1 -AUs 1 `
    [-DeploymentTier economy] [-AdminPassword "pw"] [-LoadSampleData]
```

**Rename / modify**
```powershell
.\resource.ps1 -Action modify -ResourceType warehouse -ResourceId av-xxxxx -Name "NewName"
```

**Lifecycle**
```powershell
.\resource.ps1 -Action start  -ResourceType warehouse -ResourceId av-xxxxx
.\resource.ps1 -Action stop   -ResourceType warehouse -ResourceId av-xxxxx
.\resource.ps1 -Action sleep  -ResourceType warehouse -ResourceId av-xxxxx
.\resource.ps1 -Action delete -ResourceType warehouse -ResourceId av-xxxxx
```

**Scale**
```powershell
.\resource.ps1 -Action scale -ResourceType warehouse -ResourceId av-xxxxx -AUs 4
```

**IP Allowlist**
```powershell
.\resource.ps1 -Action allowlist-ip -ResourceType warehouse -ResourceId av-xxxxx `
    -CIDRs "0.0.0.0/0"
.\resource.ps1 -Action allowlist-ip -ResourceType warehouse -ResourceId av-xxxxx `
    -CIDRs "10.0.0.0/8","203.0.113.0/24"
```

**Idle-stop policy**
```powershell
# Auto-sleep after 120 min idle
.\resource.ps1 -Action idle-stop -ResourceType warehouse -ResourceId av-xxxxx `
    -IdleMinutes 120 -IdleAction Sleep
# Auto-stop after 240 min idle
.\resource.ps1 -Action idle-stop -ResourceType warehouse -ResourceId av-xxxxx `
    -IdleMinutes 240 -IdleAction Stop
```

**WLM (workload management)**
```powershell
.\resource.ps1 -Action alter-wlm -ResourceType warehouse -ResourceId av-xxxxx -ActiveLimit 4
# Tier defaults: economy=2, standard=4, enterprise=8, super=16
```

**Data API / ML services**
```powershell
.\resource.ps1 -Action configure-data-api -ResourceType warehouse -ResourceId av-xxxxx -Enable $true
.\resource.ps1 -Action configure-ml       -ResourceType warehouse -ResourceId av-xxxxx -Enable $true
```

**External table credentials (S3)**
```powershell
.\resource.ps1 -Action external-table-creds -ResourceType warehouse -ResourceId av-xxxxx `
    -AccessKeyId "AKIAIOSFODNN7EXAMPLE" -SecretKey "wJalrXUtnFEMI/K7MDENG/..."
```

**Updates**
```powershell
.\resource.ps1 -Action available-updates -ResourceType warehouse -ResourceId av-xxxxx
.\resource.ps1 -Action planned-updates   -ResourceType warehouse -ResourceId av-xxxxx
.\resource.ps1 -Action planned-updates   -ResourceType warehouse   # all warehouses
.\resource.ps1 -Action upcoming-update   -ResourceType warehouse -ResourceId av-xxxxx
.\resource.ps1 -Action update-version    -ResourceType warehouse -ResourceId av-xxxxx -Version "701.0.8"
.\resource.ps1 -Action apply-updates     -ResourceType warehouse -ResourceId av-xxxxx
```

**Named databases (within a warehouse/database resource)**
```powershell
.\resource.ps1 -Action dbs        -ResourceType warehouse -ResourceId av-xxxxx
.\resource.ps1 -Action create-db  -ResourceType warehouse -ResourceId av-xxxxx -DbName mydb
.\resource.ps1 -Action drop-db    -ResourceType warehouse -ResourceId av-xxxxx -DbName mydb
```
> Note: The API path uses `$warehouse` / `$database` literals (not substituted) — the script handles this.

---

## `warehouse.ps1` — Warehouse-specific ops

```powershell
# Restart
.\warehouse.ps1 -Action restart -ResourceId av-xxxxx [-ForceRestart]

# Clone (Google / AWS only)
.\warehouse.ps1 -Action clone -ResourceId av-xxxxx -CloneName "MyClone" [-CloneType fullClone|readonlyClone]

# Refresh-clone
.\warehouse.ps1 -Action refresh-clone -ResourceId av-xxxxx [-BackupBeforeClone]

# Spark
.\warehouse.ps1 -Action spark-settings        -ResourceId av-xxxxx
.\warehouse.ps1 -Action spark-settings-update -ResourceId av-xxxxx -LogLevel INFO [-HeapSizeGb 4]
.\warehouse.ps1 -Action spark-logs            -ResourceId av-xxxxx

# Named DBs (warehouse-specific path)
.\warehouse.ps1 -Action dbs       -ResourceId av-xxxxx
.\warehouse.ps1 -Action create-db -ResourceId av-xxxxx -DbName mydb
.\warehouse.ps1 -Action drop-db   -ResourceId av-xxxxx -DbName mydb
```

---

## `database.ps1` — Database-specific ops

```powershell
.\database.ps1 -Action logs         -ResourceId db-xxxxx
.\database.ps1 -Action locations    -ResourceId db-xxxxx
.\database.ps1 -Action add-location -ResourceId db-xxxxx -LocationType s3 -LocationPath "s3://bucket/prefix"
.\database.ps1 -Action del-location -ResourceId db-xxxxx -LocationId loc-xxxxx
.\database.ps1 -Action dba-access   -ResourceId db-xxxxx -EnableDba $true [-DbaPassword "pw"]
.\database.ps1 -Action resize       -ResourceId db-xxxxx -NewSizeGib 200
.\database.ps1 -Action dbs          -ResourceId db-xxxxx
```

---

## `encryption_key.ps1` — Encryption key management

```powershell
.\encryption_key.ps1 -Action list
.\encryption_key.ps1 -Action managers   # lists Actian KMS, AWS KMS, etc.
.\encryption_key.ps1 -Action get     -KeyId "3a3b5ff1-..."
.\encryption_key.ps1 -Action create  -Name "my-key" -ExternalKeyManagerId 2 -KeyArn "arn:aws:kms:..."
.\encryption_key.ps1 -Action update  -KeyId "3a3b5ff1-..." -Name "new-name"
.\encryption_key.ps1 -Action delete  -KeyId "3a3b5ff1-..."
.\encryption_key.ps1 -Action test    -KeyArn "arn:aws:kms:..." -ExternalKeyManagerId 2
.\encryption_key.ps1 -Action reencrypt -KeyId "3a3b5ff1-..." [-ResourceIds "av-xxx","av-yyy"]
```

Key manager IDs (from stage environment):
- `1` = Actian KMS (service-managed)
- `2` = AWS KMS (customer-managed)

---

## `scheduled_task.ps1` — Scheduled tasks

```powershell
# List tasks on a warehouse
.\scheduled_task.ps1 -Action list -ResourceType warehouse -ResourceId av-xxxxx

# Create: nightly stop at 10pm ET Mon-Fri
.\scheduled_task.ps1 -Action create -ResourceType warehouse -ResourceId av-xxxxx `
    -TaskName "NightlyStop" -TaskAction stop `
    -Cron "0 22 * * 1-5" -Timezone "America/New_York"

# Create: start every weekday morning
.\scheduled_task.ps1 -Action create -ResourceType warehouse -ResourceId av-xxxxx `
    -TaskName "MorningStart" -TaskAction start `
    -Cron "0 8 * * 1-5" -Timezone "America/New_York"

# Create: interval-based (every 60 min)
.\scheduled_task.ps1 -Action create -ResourceType warehouse -TaskName "HourlyPulse" `
    -TaskAction stop -IntervalMinutes 60

# Update: disable a task
.\scheduled_task.ps1 -Action update -TaskId "task-xxxxx" -Active $false

# Delete
.\scheduled_task.ps1 -Action delete -ResourceType warehouse -ResourceId av-xxxxx -TaskId "task-xxxxx"
```

---

## `usage.ps1` — Consumption and billing

```powershell
.\usage.ps1 -Action current          # AU-hours: quota, consumed, remaining
.\usage.ps1 -Action storage          # storage used
.\usage.ps1 -Action high-watermark   # peak storage per PPID
.\usage.ps1 -Action compute-summary  # compute summary breakdown
.\usage.ps1 -Action timeseries [-From "2026-01-01"] [-To "2026-06-30"] [-Granularity daily|hourly]
.\usage.ps1 -Action consumer         # per-consumer breakdown
```

---

## `sql.ps1` — full SQL + loading over JDBC / ODBC

The single data-plane engine. Connects with the Actian Ingres database driver and runs **arbitrary
SQL** — `SELECT`, DDL, `INSERT … VALUES`, `COPY … VWLOAD`. No browser, no Query Editor, no cookie.
Choose the engine with `-Engine jdbc` (default) or `-Engine odbc`; everything below works with either.

**Connection / health**
```powershell
.\sql.ps1 -Action connection-info                         # JDBC (default)
.\sql.ps1 -Action connection-info -Engine odbc            # ODBC
# Connection from the admiral.config.json "db" block; override with
#   -DbHost / -Port / -Database / -DbUser / -DbPassword, or resolve host from -ResourceId
```

**Run SQL**
```powershell
.\sql.ps1 -Action query    -Sql "SELECT COUNT(*) FROM pos_transactions"
.\sql.ps1 -Action exec     -Sql "INSERT INTO sales VALUES (1,'widget',9.99)"   # DDL/DML
.\sql.ps1 -Action run-file -SqlFile pipeline.sql                               # ;-separated batch
.\sql.ps1 -Action export-csv -Sql "SELECT * FROM sales WHERE year=2025" -OutFile out\sales.csv
```

**Tables / schema** (real SQL tables — no Baqend system columns)
```powershell
.\sql.ps1 -Action list-tables
.\sql.ps1 -Action describe     -Table sales
.\sql.ps1 -Action create-table -Table sales -Columns "id INT, product VARCHAR(50), amount FLOAT, sale_date DATE"
.\sql.ps1 -Action count        -Table sales
.\sql.ps1 -Action truncate     -Table sales      # MODIFY … TO TRUNCATED
.\sql.ps1 -Action drop-table   -Table sales
```
`-Columns` is a raw SQL column list, passed through verbatim (Ingres/Vector types: `INTEGER`,
`BIGINT`, `FLOAT`, `DECIMAL(p,s)`, `VARCHAR(n)`, `DATE`, `TIMESTAMP`, …).

**Load a local CSV** (types inferred, batched `INSERT`)
```powershell
.\sql.ps1 -Action load-csv -Table sales -CsvFile data\sales.csv -CreateTable   # create then load
.\sql.ps1 -Action load-csv -Table sales -CsvFile data\sales.csv -BatchSize 1000 # into existing table
```
Fine for small/medium files. **For large or cloud-resident data, use `vwload`** (server-side bulk load).

**List GCS bucket objects** (verify file names/extensions before loading)
```powershell
.\sql.ps1 -Action list-gcs -Source "gs://rg_gcp_test" -GcsKeyFile path\to\sa.json
.\sql.ps1 -Action list-gcs -Source "gs://rg_gcp_test/poc_sales_" -GcsKeyFile path\to\sa.json  # prefix filter
```
Uses the service-account JSON to authenticate via RS256 JWT → Google OAuth2, then calls the GCS
JSON API. Outputs name + size (MB) for every matching object. Use this when VWLOAD returns
"File name pattern matches nothing" to confirm the exact file names and extensions.

> **Pattern matching is extension-sensitive.** `*.csv` will NOT match `*.csv.gz` files.
> Always confirm the exact extension with `list-gcs` before writing your `-Source` pattern.

**Bulk load from cloud storage** (`COPY … VWLOAD`)
```powershell
# Google Cloud Storage — plain CSV
.\sql.ps1 -Action vwload -Table sales `
    -Source "gs://rg_gcp_test/sales*.csv" -GcsKeyFile path\to\sa.json -Header

# Google Cloud Storage — gzip-compressed CSV (AUTO_DETECT_COMPRESSION added automatically)
.\sql.ps1 -Action vwload -Table sales `
    -Source "gs://rg_gcp_test/sales*.csv.gz" -GcsKeyFile path\to\sa.json -Header

# Amazon S3
.\sql.ps1 -Action vwload -Table sales `
    -Source "s3://my-bucket/sales.csv.gz" -AwsKey AKIA... -AwsSecret ... -AwsRegion us-east-1 -Header
```

**vwload defaults** — automatically added to every call; override via `-ExtraOptions` (duplicates are
skipped with a warning):
| Default | Value | Override |
|---|---|---|
| `FDELIM` | `','` | `-FieldDelim "\t"` |
| `RDELIM` | `'\n'` | `-ExtraOptions "RDELIM='\r\n'"` |
| `QUOTE` | `'"'` | `-QuoteChar ''` (omits the option) |
| `AUTO_DETECT_COMPRESSION` | added when `-Source` matches `*.gz` | n/a |
| `SET string_truncation IGNORE` | always prepended | n/a |

`-Source` accepts a comma-separated list and `gs://bucket/prefix/` directories/wildcards. The
service-account JSON's `client_email` / `private_key_id` / `private_key` map to VWLOAD's
`gcs_email` / `gcs_private_key_id` / `gcs_private_key` (the private key is masked in console output).

**External table over cloud storage** (query in place; cloud credentials set on the warehouse)
```powershell
.\sql.ps1 -Action create-external -Table ext_sales `
    -Columns "id INT, amt DECIMAL(12,2)" -Source "gs://rg_gcp_test/sales/" -Format csv
```

> JDBC engine needs a JDK + `iijdbc.jar` (auto-located under `II_SYSTEM`, or set `jdbcJar` in config);
> the helper `SqlRunner.java` is compiled once to `SqlRunner.class`. ODBC engine needs an installed
> Actian/Ingres ODBC driver (override the name with `odbcDriver` in config).

---

## `named_db.ps1` — Named database creation

Avalanche supports multiple named databases within a single warehouse instance.
Full options from the CreateNamedDbRequest schema:

```powershell
# List named databases
.\named_db.ps1 -Action list -ResourceType warehouse -ResourceId av-49jtc8yy9xi4

# Create a simple database
.\named_db.ps1 -Action create -ResourceType warehouse -ResourceId av-49jtc8yy9xi4 -DbName analytics

# Create with full options
.\named_db.ps1 -Action create -ResourceType warehouse -ResourceId av-49jtc8yy9xi4 `
    -DbName secure_analytics `
    -PageSize 65536 `             # 64K pages for columnar (X100) workloads
    -Location data `              # store files in 'data' area vs 'work'
    -EncryptionKeyId "3a3b5ff1-7a74-467e-90b1-54c0a92adc45" `  # from encryption_key.ps1
    -NfcCollation udefault `      # Unicode NFC collation
    -PrivateDb                    # restrict access to creating user

# Drop a named database
.\named_db.ps1 -Action drop -ResourceType warehouse -ResourceId av-49jtc8yy9xi4 -DbName analytics
```

**Page size guide:**
| `PageSize` | Best for |
|---|---|
| `2048` | OLTP, many small rows |
| `8192` | General purpose (default) |
| `16384` | Mixed workloads |
| `65536` | Columnar analytics (X100), large scans |

---

## Common patterns

### Morning startup script
```powershell
$skill = ".\.claude\skills\admiral\scripts"
. "$skill\_admiral_common.ps1"
# Start the primary warehouse
Invoke-AdmiralApi -Method PUT -Path "/resource/warehouse/av-49jtc8yy9xi4/start" -Body @{}
```

### Check quota before creating a new warehouse
```powershell
$skill = ".\.claude\skills\admiral\scripts"
& "$skill\usage.ps1" -Action current
& "$skill\tenant.ps1" -Action details
```

### Get all running warehouses
```powershell
$skill = ".\.claude\skills\admiral\scripts"
. "$skill\_admiral_common.ps1"
$r = Invoke-AdmiralApi -Path "/resource/warehouse"
$r.resources | Where-Object { $_.status -eq "Running" } |
    Select-Object resourceId, resourceName, avalancheUnits, platform, regionId, idleStopInMinutes
```

---

## End-to-end data loading workflow

```powershell
$skill = ".\.claude\skills\admiral\scripts"
$wh    = "av-49jtc8yy9xi4"

# 1. Ensure the warehouse is running
& "$skill\resource.ps1" -Action start -ResourceType warehouse -ResourceId $wh

# 2. Verify the SQL connection (JDBC by default; add -Engine odbc to use ODBC)
& "$skill\sql.ps1" -Action connection-info -ResourceId $wh

# 3. Create the target table (real SQL DDL)
& "$skill\sql.ps1" -Action create-table -Table sales_2025 `
    -Columns "region VARCHAR(50), amount FLOAT, sale_date DATE"

# --- Option A: load a local CSV (small/medium files), batched INSERT ---
& "$skill\sql.ps1" -Action load-csv -Table sales_2025 -CsvFile data\sales_2025.csv

# --- Option B: bulk load from cloud storage (large files, fastest), COPY … VWLOAD ---
# Step B1 (optional): confirm exact file names and extensions before loading
& "$skill\sql.ps1" -Action list-gcs -Source "gs://my-bucket/sales" -GcsKeyFile path\to\sa.json

# Step B2: load — RDELIM, QUOTE, string_truncation IGNORE auto-applied;
#          AUTO_DETECT_COMPRESSION added automatically for .gz sources
& "$skill\sql.ps1" -Action vwload -Table sales_2025 `
    -Source "gs://my-bucket/sales/*.csv.gz" -GcsKeyFile path\to\sa.json -Header
# (for S3: -Source "s3://my-bucket/sales.csv.gz" -AwsKey ... -AwsSecret ... -AwsRegion us-east-1)

# 4. Query the data
& "$skill\sql.ps1" -Action query `
    -Sql "SELECT region, SUM(amount) AS total FROM sales_2025 GROUP BY region ORDER BY total DESC"
```

---

## Post-load data quality checklist

Run these after any `vwload` to catch common issues before downstream queries see bad data.

```powershell
$skill = ".\.claude\skills\admiral\scripts"
$t     = "my_table"

# 1. Row count — confirm it matches expectation
& "$skill\sql.ps1" -Action count -Table $t

# 2. Categorical columns — spot case inconsistencies and unexpected values
& "$skill\sql.ps1" -Action query -Sql "SELECT province, COUNT(*) AS n FROM $t GROUP BY province ORDER BY n DESC"

# 3. Date range — confirm min/max are within expected bounds
& "$skill\sql.ps1" -Action query -Sql "SELECT MIN(sale_date) AS earliest, MAX(sale_date) AS latest FROM $t"

# 4. NULL audit — catch columns that loaded as all-NULL (common when column order mismatches)
& "$skill\sql.ps1" -Action query -Sql @"
SELECT 'amount'   AS col, COUNT(*) AS nulls FROM $t WHERE amount IS NULL
UNION SELECT 'region', COUNT(*) FROM $t WHERE region IS NULL
"@

# 5. Fix case inconsistencies once found
& "$skill\sql.ps1" -Action exec -Sql "UPDATE $t SET province = UPPER(province) WHERE province != UPPER(province)"
```
