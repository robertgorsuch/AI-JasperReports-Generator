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

## `data_load.ps1` — Data API client (Baas)

**Connection / health**
```powershell
.\data_load.ps1 -Action connection-info -ResourceId av-49jtc8yy9xi4
# Prints Data API base URL, version, service health, auth check, table count
```

**Native SQL** (SELECT / WITH / COPY / INSERT-as-SELECT only)
```powershell
.\data_load.ps1 -Action query      -Sql "SELECT COUNT(*) FROM my_table"
.\data_load.ps1 -Action query-file -SqlFile path\to\reads.sql      # ;-separated
.\data_load.ps1 -Action export-csv -Sql "SELECT * FROM sales WHERE year=2025" -OutFile out\sales.csv
```

**Tables / schema**
```powershell
.\data_load.ps1 -Action list-tables
.\data_load.ps1 -Action describe     -Table sales
.\data_load.ps1 -Action create-table -Table sales -Columns "id:int, product:string, amount:double, sale_date:date"
.\data_load.ps1 -Action count        -Table sales
.\data_load.ps1 -Action truncate     -Table sales
.\data_load.ps1 -Action drop-table   -Table sales
```
Column type names accepted: `int`/`integer`/`bigint`, `double`/`float`/`decimal`/`numeric`,
`bool`/`boolean`, `datetime`/`timestamp`, `date`, `time`, `string` (default). A literal `/db/...`
Baqend type passes through unchanged.

**Load a local CSV** (Object API, one row per POST)
```powershell
# Create the table from inferred CSV types, then load
.\data_load.ps1 -Action load-csv -Table sales -CsvFile data\sales.csv -CreateTable

# Load into an existing table
.\data_load.ps1 -Action load-csv -Table sales -CsvFile data\sales.csv
```
Row-by-row loading is fine for small/medium files. **For large loads, or loading from cloud
storage (S3/GCS), use `query_editor.ps1 -Action vwload-gcs`** (see below) — the Baas Data API
cannot run `COPY`.

**Insert a single row**
```powershell
.\data_load.ps1 -Action insert -Table sales -Json '{"product":"widget","amount":9.99}'
```

**Browse rows** (object view, max `-Limit`)
```powershell
.\data_load.ps1 -Action rows -Table sales -Limit 50
```

> `copy-from` exists in the action list but intentionally errors: the Baas Data API allowlists
> `COPY` yet silently no-ops it, so cloud bulk loading goes through `query_editor.ps1` instead.

---

## `query_editor.ps1` — full-SQL + cloud (GCS/S3) loading via the Query Editor API

The Baas Data API can only run SELECT/WITH/INSERT-as-SELECT and **cannot** do `COPY`, DDL such
as `CREATE EXTERNAL TABLE`, or `INSERT … VALUES`. For those — and for **loading from Google Cloud
Storage / S3** — use `query_editor.ps1`, which drives the warehouse's browser **Query Editor API**
(SQLPad at `https://{dns}/api`) and runs arbitrary SQL.

**Auth: a browser session cookie** (no headless login — SQLPad sits behind the Actian platform SSO).
Open the Query Editor (`https://{dns}/`) logged in → DevTools → Application → Cookies → copy the
`sqlpad.sid` cookie, then save it (gitignored):
```powershell
# write the sqlpad.sid value to scripts\..\.qe_cookie  (or pass -Cookie / set $env:QE_COOKIE)
Set-Content -NoNewline .claude\skills\admiral\.qe_cookie 'sqlpad.sid=s%3A...'
```
The cookie lasts a few hours; on `401` re-copy it. The script auto-picks the `(db)` data
connection (override with `-Connection <id|name>`).

**Run any SQL** (DDL, COPY, multi-statement)
```powershell
.\query_editor.ps1 -Action connections                         # list ODBC connections
.\query_editor.ps1 -Action run-sql  -Sql "CREATE TABLE t (id INT)"
.\query_editor.ps1 -Action run-file -SqlFile migration.sql
```

**Load from Google Cloud Storage** (`COPY … VWLOAD`, credentials inline from a service-account JSON)
```powershell
# 1. create the target table (DDL)
.\query_editor.ps1 -Action run-sql -Sql "CREATE TABLE sales (id INTEGER, name VARCHAR(50), amt FLOAT)"
# 2. bulk load from gs:// — GCS_EMAIL/PRIVATE_KEY_ID/PRIVATE_KEY are read from the JSON
.\query_editor.ps1 -Action vwload-gcs -Table sales `
    -Source "gs://rg_gcp_test/sales.csv" -GcsKeyFile path\to\service-account.json `
    -Header -FieldDelim "," [-ExtraOptions "QUOTE='\"'"]
```
`-Source` accepts a comma-separated list and `gs://bucket/prefix/` directories/wildcards. The
service-account JSON's `client_email` / `private_key_id` / `private_key` map to VWLOAD's
`GCS_EMAIL` / `GCS_PRIVATE_KEY_ID` / `GCS_PRIVATE_KEY` (the private key is masked in console output).
For S3, load the table the same way with a `COPY … VWLOAD` (`AWS_ACCESS_KEY`/`AWS_SECRET_KEY`/`AWS_REGION`) via `run-sql`.

**External table over GCS** (query in place; credentials must be set in the Avalanche console first)
```powershell
.\query_editor.ps1 -Action create-external-gcs -Table ext_sales `
    -Columns "id INT, amt DECIMAL(12,2)" -Source "gs://rg_gcp_test/sales/" -Format csv
```

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

# 1. Ensure the warehouse is running and the Data API is enabled
& "$skill\resource.ps1" -Action start              -ResourceType warehouse -ResourceId $wh
& "$skill\resource.ps1" -Action configure-data-api -ResourceType warehouse -ResourceId $wh -Enable $true

# 2. Verify the Data API connection
& "$skill\data_load.ps1" -Action connection-info -ResourceId $wh

# --- Option A: load a local CSV (small/medium files), via the Baas Object API ---
& "$skill\data_load.ps1" -Action load-csv -Table sales_2025 -CsvFile data\sales_2025.csv -CreateTable

# --- Option B: bulk load from cloud storage (large files, fastest), via the Query Editor API ---
#     The Baas Data API cannot run COPY, so cloud loads go through query_editor.ps1 (VWLOAD).
& "$skill\query_editor.ps1" -Action run-sql `
    -Sql "CREATE TABLE sales_2025 (region VARCHAR(50), amount FLOAT, sale_date DATE)"
& "$skill\query_editor.ps1" -Action vwload-gcs -Table sales_2025 `
    -Source "gs://my-bucket/sales/" -GcsKeyFile path\to\service-account.json -Header
# (for S3, run a COPY … VWLOAD with AWS_ACCESS_KEY/AWS_SECRET_KEY/AWS_REGION via -Action run-sql)

# 3. Query the data (native SQL passthrough)
& "$skill\data_load.ps1" -Action query `
    -Sql "SELECT region, SUM(amount) AS total FROM sales_2025 GROUP BY region ORDER BY total DESC"
```
