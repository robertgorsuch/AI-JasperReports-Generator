---
name: admiral
description: >-
  Manage Actian Data Platform (Avalanche) resources via the Admiral REST API on a live stage
  environment. Use for the full warehouse/database lifecycle — list, create, start, stop, sleep,
  scale, modify, clone, delete — plus IP allowlists, WLM, idle-stop, Data API / ML toggles,
  external-table credentials, named databases, encryption keys, scheduled stop/sleep/start tasks,
  and AU-hour / storage / utilization reporting and tenant entitlements. Also covers full SQL
  data management and loading over JDBC or ODBC (Actian Ingres driver): run arbitrary SQL and DDL,
  INSERT … VALUES, load local CSVs, bulk-load from S3/GCS via COPY … VWLOAD, create external
  tables, and create/drop/describe tables and named databases.
---

# Admiral — Actian Data Platform API Skill

Automates **Actian Avalanche** warehouses and databases two ways: **control plane** via the
Admiral REST API at `https://admiral.aop-stage.aws.actiandatacloud.com/api/v1` (resource lifecycle,
usage, scheduling), and **data plane** via **JDBC or ODBC** using the Actian Ingres driver
(full SQL, DDL, and `COPY … VWLOAD` bulk loads). There is **no dependency on the browser Query
Editor / SQLPad or any session cookie** — data operations run through a real database driver.

## Setup

1. Copy the config template and fill in credentials:
   ```powershell
   Copy-Item "$skill\..\admiral.config.example.json" "$skill\..\admiral.config.json"
   # Edit admiral.config.json — set Admiral "password" and the "db" block (host/user/password)
   ```
   `admiral.config.json` is `.gitignore`d and never committed.

   Data-plane prerequisites (already present on this machine): a JDK (`javac`/`java`) for the JDBC
   engine, the Actian client `iijdbc.jar`, and/or an installed Actian/Ingres ODBC driver.

2. `$skill` in every example is the `scripts/` subdirectory:
   ```powershell
   $skill = ".\.claude\skills\admiral\scripts"
   ```

## Auth

- **Control plane (REST):** scripts handle auth automatically — OAuth2 password flow (`POST /login`)
  yields a JWT (~10h TTL) cached and refreshed per PowerShell session. No manual token handling.
- **Data plane (JDBC/ODBC):** the database driver authenticates directly with the DB user/password
  from the `db` block of `admiral.config.json` over the encrypted Ingres port (27839, TLS). No token
  exchange, no browser, no cookie.

## Scripts

Run as `& "$skill\<script>.ps1" -Action <action> ...`. Each script self-documents its full action
set via its `-Action` ValidateSet and header comment. **Full flag-by-flag examples, common patterns,
and the end-to-end loading workflow are in [`references/commands.md`](references/commands.md).**

| Script | Manages | Common actions |
|---|---|---|
| `tenant.ps1` | Tenant info | `details`, `entitlements`, `features` |
| `resource.ps1` | Warehouse + database lifecycle (`-ResourceType warehouse`\|`database`) | `list`, `get`, `config`, `create`, `modify`, `start`, `stop`, `sleep`, `scale`, `delete`, `allowlist-ip`, `idle-stop`, `alter-wlm`, `configure-data-api`, `configure-ml`, `external-table-creds`, `*-updates`, `dbs`/`create-db`/`drop-db` |
| `warehouse.ps1` | Warehouse-only ops | `restart`, `clone`, `refresh-clone`, `spark-settings`, `spark-logs`, `dbs` |
| `database.ps1` | Database-only ops | `logs`, `locations`, `add-location`, `del-location`, `dba-access`, `resize`, `dbs` |
| `encryption_key.ps1` | Encryption keys | `list`, `managers`, `get`, `create`, `update`, `delete`, `test`, `reencrypt` |
| `scheduled_task.ps1` | Cron/interval stop·sleep·start tasks | `list`, `create`, `update`, `delete` |
| `usage.ps1` | Consumption + billing | `current`, `storage`, `high-watermark`, `compute-summary`, `timeseries`, `consumer` |
| `named_db.ps1` | Named databases (full Avalanche options) | `list`, `create`, `drop` |
| `sql.ps1` | **Data plane** — full SQL + loading over JDBC/ODBC (`-Engine jdbc`\|`odbc`) | `connection-info`, `query`, `exec`, `run-file`, `export-csv`, `list-tables`, `describe`, `count`, `create-table`, `drop-table`, `truncate`, `load-csv`, `vwload`, `create-external` |

`sql.ps1` uses the helper `SqlRunner.java` (compiled on demand to `SqlRunner.class`) for the JDBC
engine; the ODBC engine is pure PowerShell (`System.Data.Odbc`).

Known stage resource: warehouse `RG_Claude` → `av-49jtc8yy9xi4` (Google, us-east1, 1 AU).

## Data management & loading — one engine, full SQL

All data operations go through `sql.ps1`, which connects with a real database driver and runs
**arbitrary SQL** — `SELECT`, DDL (`CREATE`/`DROP`/`MODIFY`), `INSERT … VALUES`, and
`COPY … VWLOAD`. Pick the engine with `-Engine`:

| Engine | Transport | Needs |
|---|---|---|
| `jdbc` (default) | `jdbc:ingres://<host>:27839/<db>` via Java + `iijdbc.jar` | a JDK + the Actian client jar |
| `odbc` | DSN-less `System.Data.Odbc` connection string | an installed Actian/Ingres ODBC driver |

| Need | Action |
|---|---|
| Read / aggregate | `query -Sql "SELECT …"` |
| DDL / `INSERT … VALUES` / any non-query | `exec -Sql "…"` |
| Run a multi-statement batch (orchestration) | `run-file -SqlFile pipeline.sql` |
| Create / drop / describe / count / truncate a table | `create-table` / `drop-table` / `describe` / `count` / `truncate` |
| Load a local CSV (batched `INSERT`) | `load-csv -Table t -CsvFile data.csv [-CreateTable]` |
| **Bulk load from cloud (S3/GCS)** | `vwload -Table t -Source "gs://…" -GcsKeyFile sa.json -Header` |
| Reference cloud data as an external table | `create-external -Table t -Columns "…" -Source "gs://…/"` |
| Export query results to CSV | `export-csv -Sql "SELECT …" -OutFile out.csv` |

Connection comes from the `db` block of `admiral.config.json`, or override per call with
`-DbHost`/`-Port`/`-Database`/`-DbUser`/`-DbPassword`, or resolve the host from `-ResourceId`.
Tables are plain SQL tables — **no Baqend system columns, no `_col` renames**.

## Reference

- Full command examples + workflows: [`references/commands.md`](references/commands.md)
- Endpoint inventory, regions, AU sizes, versions: [`references/api-overview.md`](references/api-overview.md)
- API Swagger UI: `https://admiral.aop-stage.aws.actiandatacloud.com/api-docs/#/`
- JDBC driver: `com.ingres.jdbc.IngresDriver` in `iijdbc.jar` (Actian client); ODBC driver: "Actian AC"
