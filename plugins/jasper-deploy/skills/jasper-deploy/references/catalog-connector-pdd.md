# Product Design Document -- Jaspersoft Metadata & Lineage Connector

**Product area:** Connectivity / Source Connectors
**Owner:** Product Management, Connectivity
**Status:** Draft for review
**Version:** 0.1
**Last updated:** 2026-06-29

---

## 1. Executive Summary

Business-intelligence (BI) content is the "last mile" of the data estate: the
reports and dashboards that executives actually read are where data turns into
decisions. Yet for most catalog customers this last mile is a **blind spot**.
Our catalog has rich coverage of warehouses, lakes, and pipelines, but stops at
the BI tool boundary -- so a data steward cannot answer *"if I change this
column, which executive dashboards break?"*, and an analyst cannot tell whether
the number on a dashboard is sourced from a certified, governed table.

This document proposes a **Jaspersoft connector** that crawls a JasperReports
Server (JRS) / Jaspersoft repository, extracts the metadata of every reporting
artifact, parses the embedded SQL and semantic-layer mappings, and publishes
**asset-level and column-level lineage** that stitches Jaspersoft reports,
dashboards, ad hoc views, and Domains back to the physical tables and columns
already cataloged on the data-source side.

The connector is **read-only**, API-based (JRS REST v2), and agentless. It
delivers three customer-visible outcomes:

1. **Impact analysis** -- "what reports/dashboards depend on this table/column?"
2. **Trust & certification** -- surface BI assets next to their governed sources,
   with ownership, popularity, and freshness.
3. **End-to-end lineage** -- a single graph from source column -> SQL -> report
   field -> dashboard tile.

---

## 2. Problem Statement & Motivation

### 2.1 The gap today
- Catalog lineage terminates at the warehouse view or extract. The
  consumption layer (who reports on this, and how) is invisible.
- Source-side schema changes are made **without visibility** into downstream BI
  breakage. Change management is reactive (a dashboard breaks, then someone
  files a ticket).
- Analysts re-derive the same metrics in new reports because they cannot
  discover existing, trusted ones. Report sprawl grows unchecked.
- Compliance teams cannot trace **PII propagation** into reports/exports, which
  is exactly where sensitive data leaves the governed perimeter (PDF/XLSX/CSV
  exports, scheduled email bursts).

### 2.2 Why Jaspersoft specifically
Jaspersoft (JasperReports Server, now part of the Cloud Software Group portfolio)
is a widely-embedded, OEM-heavy BI platform. Its content is **highly
structured and API-addressable** -- every artifact is a typed resource in a
repository tree, retrievable over a stable REST v2 API, and reports carry their
**SQL inline** in the JRXML. Compared to drag-and-drop visual tools, Jaspersoft
is unusually amenable to high-fidelity, automated lineage extraction:

- Report queries are **explicit SQL** (or Domain/MDX) embedded in the JRXML, not
  hidden behind a proprietary visual binding.
- A **semantic layer (Domains)** provides a declarative table->field mapping in
  `schema.xml`, giving us clean logical-to-physical lineage.
- Data sources are first-class typed resources with connection metadata.
- The export service produces a **fully self-describing archive** (descriptors +
  JRXML + companion files) -- a deterministic extraction target.

### 2.3 Strategic fit
This is a **horizontal connector investment**: the SQL-parsing and lineage-graph
machinery built here is reusable for other JRXML/BI sources, and it closes a
named gap in competitive BI-lineage coverage (the catalogs we compete with tout
Power BI / Tableau / Looker lineage; Jaspersoft is an underserved, OEM-dense
install base where we can differentiate).

---

## 3. Goals & Non-Goals

### 3.1 Goals (v1)
- **G1** -- Catalog all first-class Jaspersoft repository artifacts as typed
  assets: reports, dashboards, ad hoc views, Domains, Topics, data sources,
  OLAP/Mondrian, input controls, file resources.
- **G2** -- Capture technical, business, and operational metadata for each
  (URI, type, owner, folder, description, permissions, schedules, parameters,
  fields).
- **G3** -- Produce **asset-level lineage**: data source -> Domain/Topic -> ad hoc
  view -> report -> dashboard.
- **G4** -- Produce **column/field-level lineage** for the common path: physical
  DB column -> SQL SELECT item -> report field -> dashboard tile, via SQL parsing
  and Domain schema resolution.
- **G5** -- **Stitch** Jaspersoft data sources to existing cataloged warehouse
  assets so the BI lineage connects to physical lineage already in the catalog.
- **G6** -- Incremental, schedulable, **read-only** ingestion that scales to tens
  of thousands of resources without impacting the live JRS.

### 3.2 Non-Goals (v1)
- **NG1** -- No write-back / push of catalog metadata into Jaspersoft (one-way
  pull only).
- **NG2** -- No runtime/usage telemetry beyond what the audit/scheduling APIs
  expose (deep "who-viewed-what" analytics is a later phase).
- **NG3** -- No parsing of arbitrary JRXML **expression-language** field
  derivations into column lineage (Java/Groovy expressions) beyond best-effort;
  see Sec. 10.3.
- **NG4** -- No support for legacy SOAP/`flow.html` scraping; REST v2 only.
- **NG5** -- No transformation/profiling of the underlying data (that is the
  data-source connector's job).

---

## 4. Personas & Use Cases

| Persona | Need | Connector capability |
|---|---|---|
| **Data Steward / Governance** | Impact analysis before a schema change; certify trusted reports | Where-used from column -> reports/dashboards; certification badges on BI assets |
| **Data Engineer** | Know who consumes a table before deprecating it | Downstream BI dependency list per table/view |
| **BI Developer / Report Author** | Discover existing reports/metrics; avoid duplication | Searchable BI catalog with fields, queries, datasource |
| **Compliance / Privacy** | Trace PII into reports and exports | Tag propagation from classified columns -> report fields -> scheduled exports |
| **Data Analyst** | Trust the number on a dashboard | Source lineage + freshness/owner on each dashboard tile |

### 4.1 Headline user stories
- *As a steward,* when I open a warehouse column, I see **every Jaspersoft report
  and dashboard that reads it**, with owners and last-run, so I can assess
  change impact.
- *As a compliance officer,* when I classify a column as PII, the tag
  **propagates** to downstream report fields and flags any **scheduled email
  exports** of that data.
- *As a report author,* I can search the catalog for "revenue by region" and find
  the **certified existing report** instead of building a duplicate.
- *As an engineer,* before dropping a view I get a **blast-radius report** of
  affected dashboards ranked by usage.

---

## 5. Background -- The Jaspersoft Artifact Model (extraction surface)

The connector targets the **JRS REST v2 API** at
`{base}/rest_v2/...` (HTTP Basic or token auth). The repository is a tree of
**typed resources**; each type has a JSON descriptor media type and, for
report-like resources, an associated JRXML payload.

### 5.1 Resource taxonomy (what we crawl)

| Jaspersoft resource | `type` (REST) | Lineage role | Carries |
|---|---|---|---|
| Report unit | `reportUnit` | **Consumer** of a datasource/Domain; producer of fields | JRXML (inlined base64 or `_files` child), datasource ref, input controls, query |
| Dashboard | `dashboardModel` / dashboard | Top consumer; composes dashlets | `components`, `layout`, `wiring` companion files referencing reports/ad hoc views |
| Ad hoc view | `adhocDataView` | Consumer of Topic/Domain/DS; producer for dashboards | `query.multiAxis` + component state, backing Topic/Domain |
| Domain (semantic layer) | `semanticLayerDataSource` | **Logical->physical map** | `schema.xml` (tables, joins, items->columns), datasource ref |
| Topic | `reportUnit` (jrxml file) | Ad hoc data source | JRXML query |
| JDBC data source | `jdbcDataSource` | **Physical anchor** | connection URL, driver, db user, host/port/db |
| Non-JDBC DS | `jndiJdbcDataSource`, `beanDataSource`, `customDataSource`, `virtualDataSource`, `awsDataSource` | Physical anchor (indirect) | JNDI name / bean / sub-DS list / AWS instance |
| OLAP | `olapMondrianSchema`, `secureMondrianConnection`, `olapUnit` | Cube -> DS map; MDX consumer | Mondrian schema XML, MDX |
| Input control / query | `inputControl`, `query` | Parameter binding; query-backed option lists | query SQL on a datasource |
| File resources | `file` (jrxml, jrtx, img, csv, properties, xml, accessGrant) | Supporting | raw bytes |
| Style template | `file`/xml (`.jrtx`) | Cross-report styling (non-lineage) | named styles |

### 5.2 Key extraction endpoints (verified against a live JRS 10.0.0)

| Purpose | Endpoint |
|---|---|
| Browse tree (recursive) | `GET /rest_v2/resources?folderUri=/&recursive=true[&type=...]` |
| Resource descriptor (expanded) | `GET /rest_v2/resources{uri}` with `Accept: application/repository.<type>+json` |
| List datasources | `GET /rest_v2/resources?type=jdbcDataSource&recursive=true` |
| Report input controls | `GET /rest_v2/reports{uri}/inputControls` |
| Domain metadata | `GET /rest_v2/domains{uri}/metadata` |
| **Full-fidelity export** (descriptor + JRXML + companions) | `POST /rest_v2/export` -> poll `/state` -> `GET /export/{id}/exportFile` |
| API surface discovery | `GET /rest_v2/application.wadl?detail=true` |
| Schedules (operational) | `GET /rest_v2/jobs?reportUnitURI=...` |
| Permissions (ownership/ACL) | `GET /rest_v2/permissions{uri}?effectivePermissions=true` |

> **Design note:** there are two extraction modes -- (a) **live descriptor
> crawl** via `/resources` for incremental, cheap metadata; and (b) **export
> archive** for the high-fidelity payloads (dashboard `components`/`layout`/
> `wiring`, ad hoc view binary state) that the live descriptor flattens or
> omits. The connector uses (a) for discovery + change detection and (b) for
> deep parse of dashboards and ad hoc views. See Sec. 9.

---

## 6. Metadata Model -- Mapping Jaspersoft -> Catalog

Each Jaspersoft resource maps to a catalog **asset type** with normalized
attributes. Lineage edges connect assets.

### 6.1 Asset-type mapping

| Catalog asset type | Source resource | Notes |
|---|---|---|
| **BI Report** | `reportUnit` | Has child **Report Field** and **Report Parameter** assets |
| **BI Dashboard** | dashboard | Has child **Dashboard Tile** assets |
| **BI View** (ad hoc) | `adhocDataView` | Bridges Domain/Topic <-> dashboard |
| **Semantic Model** | `semanticLayerDataSource` (Domain) | Has child **Logical Field / Item** assets mapped to physical columns |
| **Data Source (BI)** | `*DataSource` | **Stitch target** -> existing physical DB asset |
| **OLAP Cube** | Mondrian schema/connection | Dimensions/measures as child assets |
| **Folder** | repository folder | Mirrors repo hierarchy for navigation |

### 6.2 Attribute set (per asset)

**Technical:** repository URI (stable ID), resource type, creation/update
timestamps, version, query language (`sql`/`domain`/`mdx`/`csv`), bound
datasource URI, field list (name, Java class/type), parameter list (name, type,
default).

**Business:** label, description, containing folder path, owner/created-by,
tags/labels, certification status (catalog-assigned).

**Operational:** schedule(s) and recurrence (from `jobs`), last-run / next-run,
output formats and **email recipients** (export surface for compliance),
alert thresholds (from `alerts`), permission/ACL summary (from `permissions`).

### 6.3 Stable identity & dedup
- Primary key = **server ID + repository URI** (URIs are stable and unique per
  server; the server ID disambiguates multi-environment/dev->prod).
- Renames/moves are detected by URI change with content hash continuity (export
  archive hash) so we update rather than orphan-and-recreate.

---

## 7. Lineage Design

Lineage is modeled at **two resolutions**, both emitted to the catalog graph.

### 7.1 Asset-level lineage (v1, high confidence)

```
[Physical DB Table]                      (already cataloged via DB connector)
        |  (stitched by connection identity)
        v
[BI Data Source]  -->  [Domain / Topic]  -->  [Ad Hoc View]  -->  [Dashboard]
        |                     |                                       ^
        +---------------------+---------->  [Report]  ---------------+
```

Edges are derived deterministically from descriptor references:
- **Report -> DataSource:** `reportUnit.dataSource.dataSourceReference` (or
  embedded), or via a Domain.
- **Report/AdHoc -> Domain:** Domain URI in the query/topic reference.
- **Domain -> DataSource:** `schema.xml` `<jdbcTable datasourceId>` + descriptor
  `dataSource.dataSourceReference`.
- **Dashboard -> Report/AdHoc:** dashlet frames in the dashboard `components` /
  `layout` companion files (`data-componentId` -> resource URI).
- **DataSource -> Physical asset:** **stitching** (Sec. 7.4).

### 7.2 Column / field-level lineage (v1 for SQL path; v2 for ad hoc)

The high-value, harder problem. The target chain:

```
DB.schema.table.COLUMN
   +-(SQL SELECT projection)-> report FIELD  -> dashboard TILE measure/dimension
```

Resolution strategy by query language:

- **`sql` reports (primary path):** parse the JRXML `<query language="sql">` with
  a dialect-aware SQL parser. Map each `<field name>` to its SELECT projection,
  resolve the projection to source `table.column`(s) through the FROM/JOIN graph
  and alias resolution. Aggregations/expressions yield a **derived-from** edge to
  all contributing columns (not a 1:1 copy edge).
- **`domain` reports / ad hoc views:** resolve report fields -> Domain **items**
  via the query's selected fields, then Domain items -> physical columns via
  `schema.xml` `<itemGroup>/<item>` `-> <field>` mappings. This is **declarative**
  and high confidence -- the Domain *is* the mapping.
- **`mdx`/OLAP:** map measures/dimensions to the Mondrian schema's
  `<Measure column>` / `<Level column>` definitions -> physical columns.

### 7.3 Lineage confidence levels
Every edge carries a confidence:
- **Exact** -- declarative mapping (Domain item->column, Mondrian column).
- **Parsed** -- SQL parsed and resolved unambiguously.
- **Derived** -- column participates in an expression/aggregate (fan-in).
- **Inferred/low** -- dynamic SQL, unresolved alias, or expression-language field;
  surfaced with a warning and excluded from "exact impact" by default.

### 7.4 Stitching to physical assets (critical for value)
The connector does **not** re-catalog the warehouse; it **connects** to assets
the DB connector already produced. Matching key is the **connection identity**
extracted from the JDBC datasource: `{driver/dialect, host, port, database
[, schema]}` normalized to the catalog's data-source fingerprint. When a match
is found, BI lineage attaches to the existing physical table/column nodes;
when not, we create a **shadow/external** datasource node and flag it for the
admin to map (config UI). Non-JDBC datasources (JNDI/bean/virtual/AWS) resolve
their effective connection where possible (virtual -> sub-datasources; AWS ->
instance identifier) and otherwise fall back to shadow nodes.

---

## 8. Extraction Architecture

```
            +------------------------ Catalog Platform -----------------------+
            |                                                                  |
  +---------+---------+   pull (REST v2)   +------------------+               |
  |  Jaspersoft        | <---------------  |  Jaspersoft       |   normalized  |
  |  (JRS) Repository  |  HTTPS Basic/token|  Connector        | - assets ---> |  Ingestion
  |  + REST v2 API     | --------------->  |  (agentless svc)  | - lineage --> |  + Lineage
  +--------------------+    descriptors    |                  |   edges       |  Graph
                            export archives |  - Crawler       |               |
                                            |  - Descriptor    |               |
                                            |    parser        |               |
                                            |  - JRXML/SQL      |              |
                                            |    parser        |               |
                                            |  - Domain/Mondrian|              |
                                            |    resolver       |              |
                                            |  - Lineage builder|               |
                                            |  - Stitcher       |               |
                                            +------------------+               |
            +------------------------------------------------------------------+
```

### 8.1 Components
1. **Crawler** -- walks `/rest_v2/resources` (recursive, paginated), respects
   folder include/exclude filters, builds the resource inventory + change set.
2. **Descriptor parser** -- fetches per-type JSON descriptors; extracts metadata
   and reference edges.
3. **Payload parser** -- pulls JRXML (inline base64 or `_files` child) and, for
   dashboards/ad hoc views, the **export archive**; parses XML.
4. **SQL parser** -- dialect-aware (Postgres, Oracle, SQL Server, MySQL, Redshift,
   Snowflake, etc.) AST parse -> table/column resolution.
5. **Semantic resolver** -- Domain `schema.xml` and Mondrian schema -> logical/
   physical maps.
6. **Lineage builder** -- assembles asset- and column-level edges with confidence.
7. **Stitcher** -- matches BI datasources to physical catalog assets.
8. **Emitter** -- maps to the catalog's ingestion API / open-metadata format.

### 8.2 Crawl & sync strategy
- **Full crawl** on first run; **incremental** thereafter using resource
  `updateDate` / version from the descriptor (and export-archive content hash for
  deep artifacts) to process only changed resources.
- **Pagination & throttling** -- bounded concurrency, configurable rate limit, and
  off-peak scheduling to protect the live JRS (BI servers are latency-sensitive).
- **Resumable** -- checkpoint per folder so a failed run resumes, not restarts.
- **Multi-tenant** -- Jaspersoft organizations map to catalog domains/scopes;
  crawl is org-scoped where the install is multi-tenant.

### 8.3 Auth & connectivity
- HTTP Basic (service account) or token; least-privilege **read-only** role with
  repository read + export permission.
- Supports on-prem JRS reachable via the catalog's agent/bridge, and
  cloud/OEM-hosted JRS via direct HTTPS with allow-listing.
- Credentials in the catalog secret store; never logged.

---

## 9. Technical Approach by Artifact

### 9.1 Reports (`reportUnit`)
1. Get descriptor -> datasource ref, input controls, label/desc/folder.
2. Get JRXML -> `<field>` list (name + Java class), `<parameter>` list,
   `<query language>` + query text, `<variable>`s, `<subDataset>`s, subreport
   references, crosstab `<measure>`/`<rowGroup>`/`<columnGroup>`.
3. Parse SQL -> table/column lineage to fields (Sec. 7.2). Handle **parameters**:
   `$P{x}` / `$P!{x}` substitution and `$X{}` clauses are normalized before
   parse (parameters become bind points, not literals).
4. Emit Report asset + Field/Parameter children + lineage edges.
5. **Subreports** create report->report edges (URI in `<subreportExpression>`).

### 9.2 Domains (`semanticLayerDataSource`)
1. Descriptor -> bound datasource; fetch embedded `schema.xml`.
2. Parse `schema.xml`: `<jdbcTable>` (physical tables), `<itemGroup>/<item>`
   (logical fields), joins (`joinInfo`), and item->column mappings.
3. Emit Semantic Model + Logical Field children, each with an **exact** edge to
   its physical column -> high-confidence backbone for ad hoc lineage.

### 9.3 Ad Hoc Views (`adhocDataView`)
1. Live descriptor is opaque (`query.multiAxis` + binary state); use the
   **export archive** for full fidelity (it carries the backing Topic/Domain).
2. Resolve selected fields/measures -> Domain items -> physical columns (via Sec. 9.2)
   or -> Topic JRXML query (via Sec. 9.1 SQL parse).
3. Emit BI View asset; it becomes the lineage bridge to dashboards.

### 9.4 Dashboards
1. Export archive -> `components` (dashlet frames + properties), `layout` (grid
   `data-componentId` -> resource URIs), `wiring` (filter/parameter events).
2. Each report/ad hoc dashlet -> dashboard->consumer edge; text/image tiles carry
   no lineage.
3. **Wiring** (input-control -> dashlet parameter) becomes parameter-level edges,
   useful for understanding filter propagation.
4. Emit Dashboard + Tile children.

### 9.5 Data Sources
- JDBC: extract `connectionUrl` (or host/port/db), driver class, db user ->
  connection fingerprint for stitching.
- Virtual: expand sub-datasource list -> multiple stitch targets.
- AWS: instance identifier + region -> stitch to cloud DB asset.
- JNDI/bean/custom: best-effort; otherwise shadow node + admin mapping.

### 9.6 OLAP / Mondrian
- Mondrian schema XML -> cubes, dimensions/hierarchies/levels, measures, each with
  column refs -> physical lineage.
- `secureMondrianConnection` -> datasource binding; `olapUnit` MDX -> cube usage.

---

## 10. Challenges & Mitigations

| Challenge | Risk | Mitigation |
|---|---|---|
| **SQL dialect diversity** | Mis-parse -> wrong/no lineage | Pluggable dialect grammars; detect dialect from datasource driver; fall back to table-level lineage when column resolution is ambiguous |
| **Dynamic / parameterized SQL** (`$P!{}` injecting clauses, `$X{}`) | Unparseable text | Normalize parameter tokens to bind markers pre-parse; for clause-injection, parse the static skeleton and mark affected columns **inferred** |
| **CTEs / nested subqueries / window funcs** | Resolution depth | Full AST walk with scope/alias stack; CTE and derived-table resolution (note: JRS *blocks* leading-`WITH` at fill time, so production report SQL is typically `SELECT`-rooted -- reduces but doesn't remove CTE-in-subquery cases) |
| **Expression-language fields** (Java/Groovy in `<fieldExpression>`/`<variable>`) | No SQL to parse | Best-effort variable->field derivation; emit **derived** edges to referenced fields; flag low-confidence |
| **Opaque ad hoc / dashboard state** | Live descriptor insufficient | Use export-archive path for deep parse (Sec. 9.3-9.4) |
| **Stitching misses** (non-JDBC, host aliasing) | Broken lineage to physical | Connection fingerprint normalization + admin mapping UI + shadow nodes |
| **Scale / server load** | Impact live BI server | Incremental sync, throttling, off-peak scheduling, export over deep-crawl |
| **Version drift across JRS releases** | API/schema changes | Pin to REST v2; discover surface via WADL; schema-tolerant parsers; CE vs Pro feature detection |
| **CE vs Pro feature gaps** | Domains/OLAP/dashboards are Pro-only | Capability probe at connect time; degrade gracefully to report+datasource lineage on CE |

---

## 11. Phased Delivery / Roadmap

**Phase 1 -- MVP: Inventory + asset-level lineage (target: foundation release)**
- Crawl, descriptor parse, all asset types cataloged with metadata.
- Asset-level lineage (DS->Domain->AdHoc->Report->Dashboard) + stitching.
- Incremental sync, read-only auth, on-prem + cloud connectivity.
- *Exit criteria:* full repo cataloged; where-used at **asset** granularity;
  >=95% of `reportUnit`/datasource/Domain/dashboard resources ingested.

**Phase 2 -- Column-level lineage (SQL + Domain path)**
- Dialect-aware SQL parser; report-field -> source-column lineage.
- Domain item -> physical column exact lineage; OLAP measure/dimension lineage.
- Confidence scoring + lineage UI surfacing.
- *Exit criteria:* column lineage on >=80% of `sql`/`domain` reports at
  Exact/Parsed confidence on reference installs.

**Phase 3 -- Operational metadata & compliance**
- Schedules, recipients, alerts; **tag/PII propagation** along lineage;
  export-surface flags; certification workflow integration.

**Phase 4 -- Scale, breadth & usage**
- Expression-language best-effort lineage; usage/popularity (audit logs);
  multi-tenant org mapping at scale; performance hardening for very large repos.

---

## 12. Success Metrics

- **Coverage:** % of repository resources cataloged (target >=95% Phase 1).
- **Lineage completeness:** % reports with column lineage at Exact/Parsed
  confidence (target >=80% Phase 2).
- **Stitch rate:** % BI datasources auto-matched to physical assets (target >=85%).
- **Freshness:** incremental sync latency (target < 1h for changed resources).
- **Server impact:** P95 added load on JRS during sync (target negligible /
  within agreed rate limit).
- **Adoption:** # impact-analysis queries traversing BI lineage; # certified BI
  assets; reduction in "duplicate report" creation (customer-reported).

---

## 13. Security, Privacy & Compliance
- **Read-only** least-privilege service account; no write-back.
- Extracted artifacts may include **column names and SQL** (not data rows) --
  treated as metadata; SQL text stored with the same classification as other
  query metadata; configurable redaction of literals in stored SQL.
- Credentials in secret store; TLS in transit; per-org scoping honored so catalog
  visibility mirrors Jaspersoft permissions where required.
- Audit trail of every crawl (what was read, when, by which service account).

---

## 14. Open Questions / Risks
1. **CE vs Pro mix** in the target install base -- how many customers are on
   Community Edition (no Domains/dashboards/ad hoc)? Drives Phase priorities.
2. **OEM/embedded deployments** -- non-standard base paths, custom auth, and
   white-labeled repos may need per-deployment config.
3. **Dialect coverage priority** -- which underlying warehouses dominate
   (Postgres/Oracle/SQL Server/Snowflake/Redshift)? Sequences parser work.
4. **Permission-scoped ingestion** -- do customers want catalog visibility to
   mirror JRS ACLs, or full-admin extraction with catalog-side governance?
5. **Expression-language depth** -- appetite/ROI for parsing Groovy/Java field
   derivations vs. flagging them low-confidence.
6. **Cloud Jaspersoft API parity** -- confirm REST v2 surface and rate limits on
   vendor-hosted/cloud editions vs. self-managed.

---

## 15. Appendix A -- Reference REST v2 Extraction Recipes

```text
# 1. Discover the full resource inventory (paginate)
GET /rest_v2/resources?folderUri=/&recursive=true&limit=100&offset=0
    Accept: application/json

# 2. Per-resource typed descriptor (reportUnit example)
GET /rest_v2/resources/reports/sales/revenue_by_region
    Accept: application/repository.reportUnit+json
    -> datasource ref, inputControls[], jrxml (inline or _files child)

# 3. Pull the JRXML payload (when stored as a _files child)
GET /rest_v2/resources/reports/sales/revenue_by_region_files/main_jrxml
    Accept: application/xml
    -> <query language="sql">, <field>, <parameter>, <subDataset>

# 4. Domain semantic mapping
GET /rest_v2/domains/domains/sales_domain/metadata
    -> logical items <-> physical tables/columns

# 5. High-fidelity export (dashboards / ad hoc deep parse)
POST /rest_v2/export   {"uris":["/dashboards/exec"],"parameters":[...]}
    -> {id};  GET /rest_v2/export/{id}/state  -> finished
    -> GET /rest_v2/export/{id}/exportFile    -> zip(descriptor + _files + jrxml)

# 6. Operational metadata
GET /rest_v2/jobs?reportUnitURI=/reports/sales/revenue_by_region   # schedules
GET /rest_v2/permissions/reports/sales?effectivePermissions=true   # ACL/owner
GET /rest_v2/reports/reports/sales/revenue_by_region/inputControls # parameters

# 7. API surface of the exact target install
GET /rest_v2/application.wadl?detail=true
```

## 16. Appendix B -- Field-Level Lineage Resolution (worked sketch)

```text
JRXML:  <query language="sql">
          SELECT r.region_name AS region,
                 SUM(s.amount)  AS revenue
          FROM   sales_fact s
          JOIN   region r ON r.region_id = s.region_id
          GROUP BY r.region_name
        </query>
        <field name="region"  class="java.lang.String"/>
        <field name="revenue" class="java.math.BigDecimal"/>

Resolved lineage edges (confidence):
  region   <-- region.region_name            (Parsed,  copy)
  revenue  <-- sales_fact.amount             (Derived, SUM aggregate)
  [join]   region.region_id, sales_fact.region_id  (context, not projected)

Dashboard tile "Revenue by Region" (bar):
  category = field:region   -> region.region_name
  value    = field:revenue  -> sales_fact.amount (derived)

Stitched: datasource fingerprint {postgres, host, 5432, salesdb}
          -> physical assets salesdb.public.sales_fact / .region
          (already cataloged by the Postgres connector)
```
