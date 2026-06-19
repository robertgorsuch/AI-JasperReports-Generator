# Admiral API Reference Overview

**Base URL:** `https://admiral.aop-stage.aws.actiandatacloud.com/api/v1`
**Swagger UI:** `https://admiral.aop-stage.aws.actiandatacloud.com/api-docs/#/`
**Auth:** OAuth2 password flow — POST `/login` with `grant_type=password&username=...&password=...`; returns `access_token` (JWT, bearer, ~10h TTL)

---

## Resource Types

| `resourceType` value | Description |
|---|---|
| `warehouse` | Avalanche analytical warehouse (compute) |
| `database` | Avalanche database instance (storage) |

## Platforms & Regions (as of v1.1.0)

| Platform | Region IDs |
|---|---|
| Google | `us-east1`, `europe-west1`, `europe-west2` |
| Azure  | `eastus2` |
| AWS    | `us-east-2` |

## AU Sizes
1, 2, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128, 256

## Deployment Tiers
`economy` · `standard` · `enterprise` · `super`

## Warehouse Versions (as of Jun 2026)
- `release-701` (latest) — chart `701.0.8`
- `release-700` (stable) — chart `700.0.31`

## Resource Status Values
`Running` · `Sleeping` · `Stopped` · `Starting` · `Stopping` · `Scaling` · `Updating` · `Error`

---

## Endpoint Inventory

### Tenant
| Method | Path | Summary |
|---|---|---|
| GET | `/tenant` | Tenant details (AU quota, features) |
| GET | `/tenant/entitlements` | Compute & storage entitlements |
| GET | `/tenant/entitlements/features` | Feature flags |

### Resource (warehouse / database)
| Method | Path | Summary |
|---|---|---|
| GET | `/config/{resourceType}` | Available configs, regions, AU sizes |
| GET | `/resource/{resourceType}` | List resources |
| POST | `/resource/{resourceType}` | Create resource |
| GET | `/resource/{resourceType}/{id}` | Get resource |
| PATCH | `/resource/{resourceType}/{id}` | Modify resource (rename, tier) |
| DELETE | `/resource/{resourceType}/{id}` | Delete resource |
| PUT | `/resource/{resourceType}/{id}/start` | Start resource |
| PUT | `/resource/{resourceType}/{id}/stop` | Stop resource |
| PUT | `/resource/{resourceType}/{id}/sleep` | Sleep resource |
| PUT | `/resource/{resourceType}/{id}/scale` | Scale AU count |
| PUT | `/resource/{resourceType}/{id}/allowlist-ip` | Update IP allowlist |
| PUT | `/resource/{resourceType}/{id}/idle-stop` | Update idle-stop policy |
| PUT | `/resource/{resourceType}/{id}/alter-wlm` | Set WLM active limit |
| PUT | `/resource/{resourceType}/{id}/data-api/configure` | Enable/disable Data API |
| PUT | `/resource/{resourceType}/{id}/ml-services/configure` | Enable/disable ML services |
| PUT | `/resource/{resourceType}/{id}/external-table/credentials` | Set S3 credentials |
| PUT | `/resource/{resourceType}/{id}/update-version` | Set target version |
| PUT | `/resource/{resourceType}/{id}/apply-updates` | Apply pending updates |
| GET | `/resource/{resourceType}/{id}/available-updates` | List available updates |
| GET | `/resource/{resourceType}/{id}/planned-updates` | Planned updates |
| GET | `/resource/{resourceType}/planned-updates` | All planned updates for type |
| GET | `/resource/{resourceType}/{id}/upcoming-updates` | Next maintenance update |
| GET | `/resource/{resourceType}/{id}/backups` | Backup list |
| GET | `/resource/{resourceType}/{id}/clone/history` | Clone history |
| GET | `/resource/{resourceType}/{id}/request` | Last async request details |
| GET | `/resource/${ resourceType}/{id}/dbs` | Named databases |
| POST | `/resource/${resourceType}/{id}/dbs` | Create named database |
| DELETE | `/resource/${resourceType}/{id}/dbs` | Drop named database |

### Warehouse-specific
| Method | Path | Summary |
|---|---|---|
| POST | `/resource/warehouse/clone` | Clone warehouse (GCP/AWS only) |
| PUT | `/resource/warehouse/{id}/refresh-clone` | Refresh clone (GCP/AWS only) |
| PUT | `/resource/warehouse/{id}/restart` | Restart warehouse |
| GET | `/resource/warehouse/{id}/spark/settings` | Spark settings |
| PUT | `/resource/warehouse/{id}/spark/settings` | Update Spark settings |
| GET | `/resource/warehouse/{id}/spark/logs` | Spark logs |

### Database-specific
| Method | Path | Summary |
|---|---|---|
| GET | `/resource/database/{id}/logs` | Database logs |
| GET | `/resource/database/{id}/location` | Storage locations |
| PUT | `/resource/database/{id}/location` | Add location |
| DELETE | `/resource/database/{id}/location` | Remove location |
| PUT | `/resource/database/{id}/dba/access` | Enable DBA access |
| POST | `/resource/database/{id}/volumes/resize` | Resize data volume |

### Encryption Key
| Method | Path | Summary |
|---|---|---|
| GET | `/encryption-key` | List all keys |
| GET | `/encryption-key/{id}` | Get key details |
| GET | `/encryption-key/managers/list` | List key managers (Actian KMS, AWS KMS, …) |
| POST | `/encryption-key` | Create key |
| PATCH | `/encryption-key/{id}` | Update key |
| DELETE | `/encryption-key/{id}` | Delete key |
| PUT | `/encryption-key/check` | Test key validity |
| PATCH | `/encryption-key/reencrypt` | Re-encrypt resource data keys |

### Scheduled Task
| Method | Path | Summary |
|---|---|---|
| GET | `/scheduled-task/{type}/{id}/task` | List tasks for resource |
| POST | `/scheduled-task/{type}` | Create task |
| PUT | `/scheduled-task` | Update task |
| DELETE | `/scheduled-task/{type}/{id}/task/{taskId}` | Delete task |

### Usage
| Method | Path | Summary |
|---|---|---|
| GET | `/usage/current` | Total AU-hour consumption |
| GET | `/usage/current/storage` | Storage usage |
| GET | `/usage/storage/high-watermark` | Peak storage per PPID |
| GET | `/usage/summary/compute` | Compute summary |
| GET | `/usage/details/timeseries` | Time-series usage data |
| GET | `/usage/details/consumer` | Per-consumer usage |
