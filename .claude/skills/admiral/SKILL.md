---
name: admiral
description: >-
  Manage Actian Data Platform (Avalanche) resources via the Admiral REST API on a live stage
  environment. Use for the full warehouse/database lifecycle — list, create, start, stop, sleep,
  scale, modify, clone, delete — plus IP allowlists, WLM, idle-stop, Data API / ML toggles,
  external-table credentials, named databases, encryption keys, scheduled stop/sleep/start tasks,
  and AU-hour / storage / utilization reporting and tenant entitlements. Also covers data loading
  strictly over HTTPS (no psql/isql/ODBC): run native SQL, load local CSVs, bulk-load from S3/GCS
  via COPY/VWLOAD, and create/drop/describe tables and named databases.
---

# Admiral — Actian Data Platform API Skill

Automates **Actian Avalanche** warehouses and databases against the Admiral REST API at
`https://admiral.aop-stage.aws.actiandatacloud.com/api/v1`. Every operation is an HTTPS call —
no local database client is used or required.

## Setup

1. Copy the config template and set the real password:
   ```powershell
   Copy-Item "$skill\..\admiral.config.example.json" "$skill\..\admiral.config.json"
   # Edit admiral.config.json — set "password" (username robert.gorsuch@actian.com.idp)
   ```
   `admiral.config.json` is `.gitignore`d and never committed.

2. `$skill` in every example is the `scripts/` subdirectory:
   ```powershell
   $skill = ".\.claude\skills\admiral\scripts"
   ```

## Auth

Scripts handle auth automatically: OAuth2 password flow (`POST /login`) yields a JWT (~10h TTL)
cached and refreshed per PowerShell session. Data-API calls additionally exchange that token for a
Baqend token; the Query Editor loader uses a separate browser cookie (see its section in the reference).
No manual token handling.

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
| `data_load.ps1` | Data API client (Baas) — SQL + local CSV | `connection-info`, `query`, `query-file`, `export-csv`, `list-tables`, `describe`, `create-table`, `drop-table`, `truncate`, `count`, `insert`, `load-csv`, `rows` |
| `query_editor.ps1` | Full-SQL + cloud (GCS/S3) bulk load | `connections`, `run-sql`, `run-file`, `vwload-gcs`, `create-external-gcs` |

Known stage resource: warehouse `RG_Claude` → `av-49jtc8yy9xi4` (Google, us-east1, 1 AU).

## Data loading — the one thing to get right

Loading is split across two APIs because the **Baas Data API native passthrough accepts only
`SELECT` / `WITH` / `COPY` / `INSERT … as SELECT`** — not `CREATE`/`DROP`/`INSERT … VALUES`, and it
**silently no-ops `COPY`**. So:

| Need | Use | Script · action |
|---|---|---|
| Read / aggregate / export | native SQL passthrough | `data_load.ps1` · `query`, `count`, `export-csv` |
| Create / drop / describe table | Baas Schema API | `data_load.ps1` · `create-table`, `drop-table`, `describe` |
| Insert local rows / small CSV | Baas Object API (one POST/row) | `data_load.ps1` · `insert`, `load-csv` |
| **Bulk load from cloud (S3/GCS), DDL, `INSERT … VALUES`** | **Query Editor API** | **`query_editor.ps1` · `run-sql`, `vwload-gcs`** |

> `data_load.ps1 -Action copy-from` exists but **intentionally throws** and redirects you to
> `query_editor.ps1 -Action vwload-gcs` — the Baas API cannot actually run `COPY`.

> Tables created via the Baas API are Baqend "buckets" carrying system columns
> (`id`, `version`, `acl`, `createdAt`, `updatedAt`). A data column colliding with one (e.g. `id`)
> is auto-renamed with a `_col` suffix (`id_col`).

The Data API must be enabled on the warehouse (`resource.ps1 -Action configure-data-api`) and needs
no DB credentials — it reuses the Admiral login. Config just needs the host:
`{ "dbHost": "av-49jtc8yy9xi4.avstage.actiandatacloud.com" }` (or pass `-ResourceId` / `-DbHost`).

## Reference

- Full command examples + workflows: [`references/commands.md`](references/commands.md)
- Endpoint inventory, regions, AU sizes, versions: [`references/api-overview.md`](references/api-overview.md)
- API Swagger UI: `https://admiral.aop-stage.aws.actiandatacloud.com/api-docs/#/`
- Query Editor (browser, separate cookie auth): `https://{warehouse-dns}/`
