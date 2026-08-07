# OLAP / Mondrian deep reference

Distilled from the Jaspersoft OLAP User Guide and OLAP Ultimate Guide, v10.1.0
(docs/js-jrs_10.1.0_OLAP-user-guide.pdf, docs/js-jrs_10.1.0_OLAP-ultimate-guide.pdf).
Local server is JRS 10.0.0 commercial; 10.1 docs apply. Everything here is
[doc-only] EXCEPT the descriptor shapes in "Repository resource types", which
match what `create_mondrian.ps1` actually does (verified against the live server;
see data-and-semantic-layer.md). ASCII only. Terse on purpose.

## The resource graph

OLAP view (olapUnit) -> MDX query + OLAP client connection
Mondrian connection -> OLAP schema (file) + JDBC/JNDI/bean datasource [+ AGXML access grant]
XML/A connection    -> URI + catalog + datasource string + credentials (remote provider)
XML/A source        -> catalog name + reference to a LOCAL Mondrian connection (server side)

Views and Ad Hoc views reference most objects indirectly: view -> connection ->
schema/datasource (10.1 OLAP user p.64). JRS can be XML/A client (XML/A
connection) and XML/A server (XML/A source) at the same time (p.81).

## Mondrian schema essentials

The schema is a standalone XML file resource (NOT embedded like a Domain
schema). Sample to crib from: `<js-install>\samples\schemas\FoodmartSchema.xml`
(10.1 OLAP ultimate p.15) or `GET /rest_v2/resources/public/Samples/OLAP/Schemas/FoodmartSchema2013.xml`.

Element skeleton (complete working example: 10.1 OLAP ultimate p.66-67):

```xml
<Schema name="CZS-sales">
  <Dimension name="Geographical Area">          <!-- shared dimension -->
    <Hierarchy hasAll="true" primaryKey="store_id" primaryKeyTable="store">
      <Join leftKey="region_id" rightKey="region_id">   <!-- snowflake -->
        <Table name="store"/>
        <Table name="region"/>
      </Join>
      <Level name="Country" table="region" column="sales_country" type="String"
             uniqueMembers="true" levelType="Regular" hideMemberIf="Never"/>
      <Level name="Store Name" table="store" column="store_name" type="String"
             uniqueMembers="true">
        <Property name="Store Sqft" column="store_sqft" type="Numeric"/>
      </Level>
    </Hierarchy>
  </Dimension>
  <Cube name="Sales" cache="true" enabled="true">
    <Table name="sales_fact_2006"/>             <!-- fact table -->
    <DimensionUsage source="Geographical Area" name="Geographical Area"
                    foreignKey="store_id"/>     <!-- bind shared dim to fact FK -->
    <Measure name="Unit Sales" column="unit_sales" formatString="Standard"
             aggregator="sum"/>
    <Measure name="Store Cost" column="store_cost" formatString="#,###.00"
             aggregator="sum"/>
  </Cube>
</Schema>
```

Rules of thumb:
- A cube = one fact table + DimensionUsage refs + Measures. Dimensions declared
  at Schema level are shared; declare inside a Cube (with foreignKey on the
  Dimension element) for private ones.
- Level attrs: `table` (which joined table), `column`, `type`
  (String/Numeric/...), `uniqueMembers` (true when values are globally unique at
  that level - wrong values break aggregation), `levelType="Regular"`
  (TimeYears/TimeQuarters/TimeMonths for time dims), `hideMemberIf`.
- `Property` children of a Level expose extra columns (drill-through detail).
- `approxRowCount` on a Level cuts query-time level sizing cost
  (10.1 OLAP ultimate p.93).
- Measures: `aggregator` = sum/count/min/max/avg/distinct-count;
  `formatString` controls display.
- Calculated members and virtual cubes are NOT documented in the JRS 10.1 OLAP
  guides (Mondrian-general: `<CalculatedMember name=".." dimension="Measures">`
  with a `<Formula>` child works; the "Solve Order evaluation behavior" server
  setting explicitly governs cube-defined vs query-defined calculated members,
  10.1 OLAP user p.52-53). Docs recommend materializing joined fact tables over
  virtual cubes - virtual cubes pay a join penalty per query (ultimate p.91).
- Javascript inside schemas (cell formatting) is DISABLED by default since JRS
  8.2; enable via `olap.mondrian.scripts.enabled=true` in
  `WEB-INF/js.config.properties` + restart, else opening the view throws
  "OLAP view scripting feature is disabled" (10.1 OLAP user p.45).

### Aggregate tables

Pre-rolled-up copies of a fact table (e.g. one row/day instead of one row/sec).
- Recognition is server-side: enable with the "Enable Aggregate Tables" OLAP
  setting; a rules file ("Rule file for aggregate table identification" +
  "AggRule element's tag value" settings) defines name-based recognition;
  "Choose Aggregate Table By Volume" picks smallest volume vs fewest rows
  (10.1 OLAP user p.53-54).
- "SQL to log for aggregate table creation" prints the CREATE/INSERT SQL for
  candidate aggregates (usable with Mondrian CmdRunner) (p.54).
- Populate/refresh them yourself in the data-load (ETL) step, or use Oracle
  materialized views; the Mondrian Aggregation Designer tool can pick the best
  set and patch the schema XML (10.1 OLAP ultimate p.90-92).
- Caveat: aggregate values may use a different aggregator than the schema
  measure - if users must see schema-defined aggregation, disable aggregate
  tables (10.1 OLAP user p.53).
- Parent-child hierarchies: build closure tables (one row per member/ancestor
  pair + distance) or ancestor lookups need multiple SQL queries
  (ultimate p.91).

## Repository resource types (REST descriptor shapes)

These three are what `create_mondrian.ps1` creates (verified):
- `olapMondrianSchema` - the schema XML uploaded as a file resource:
  `{label, type:"olapMondrianSchema", content:<base64>}` PUT with
  `application/repository.file+json`.
- `secureMondrianConnection` - commercial-edition Mondrian connection (can carry
  access grants; plain `mondrianConnection` is the community shape):
  `{label, dataSource:{dataSourceReference:{uri}}, schema:{schemaReference:{uri}}}`
  PUT with `application/repository.secureMondrianConnection+json`.
- `olapUnit` - saved analysis view:
  `{label, mdxQuery, olapConnection:{olapConnectionReference:{uri}}}`
  PUT with `application/repository.olapUnit+json`.
  GOTCHA (verified): creating an olapUnit OPENS the connection and validates the
  MDX against the live cube - it 500s unless schema tables/columns match the
  datasource DB. Schema + connection still create fine on their own.

UI equivalents (10.1 OLAP user p.31-43, 64-99): Add Resource > OLAP View /
OLAP Client Connection / File > OLAP Schema / File > Access Grant Schema /
Mondrian XML/A Source. Resource ID is auto-generated from Name and immutable
after save (p.32). Default folders: /Analysis Components/{Analysis Views,
Analysis Connections, Analysis Schemas, xml/a}.

Other repo types: `xmlaConnection` (client side) and the Mondrian XML/A source
("XML/A definition", server side) - fields below.

## XML/A

JRS as provider: define an XML/A SOURCE that exposes one local Mondrian
connection under a catalog name. Fields (10.1 OLAP user p.90-91): Name /
Resource ID / Description, Catalog (the database/schema name clients request),
Mondrian Connection Reference (URI of the local connection). Clients hit
`http://host:port/jasperserver-pro/xmla` with HTTP Basic auth; repository
permissions on the source control who can query it (p.89).

JRS as client: define an XML/A CONNECTION (10.1 OLAP user p.83-86):
- Catalog: name of the schema defining the cube.
- Data Source: full connection string. Against JRS it is ALWAYS
  `Provider=Mondrian;DataSource=JRS` (pre-5.6 releases used the catalog name
  here - upgrades must be edited). Against SSAS:
  `Provider=MSOLAP.4;Data Source=<ip>;Catalog=<cat>` for OLAP views, but just
  the SQL Server instance name (e.g. `Win-MyHost`) for Ad Hoc use.
- URI: the provider endpoint, e.g. `http://host:8080/jasperserver-pro/xmla`
  (port number required).
- Username/password: passed clear-text to the provider - use a dedicated
  restricted account, never superuser. Blank creds = pass the logged-in user's
  credentials through. Escape backslashes (`domain\\user`).
- Test Connection reports "catalog not found" / "no data source found" style
  messages; Show Details expands them (p.85).

Multi-organization servers (10.1 OLAP user p.86-88):
- Connect as `user|organization_1` in the username field.
- superuser has no organization so CANNOT be used over XML/A.
- The XML/A source must live in the SAME organization (or same Public folder)
  as the Mondrian connection it points to.
- Lookup order for a requested source: caller's organization, then Public.

Only JRS and MS SSAS are certified providers; other olap4j-compatible XML/A
providers may work uncertified (p.81-82).

## Ad Hoc OLAP

Ad Hoc views can be built directly on an OLAP client connection (Mondrian or
XML/A) - pick the connection as the Ad Hoc data source; the cube's dimensions/
measures become the field list and JRS generates MDX as you pivot
(10.1 OLAP user p.64; ultimate p.77).
vs Domains: an OLAP connection brings cube semantics (predefined hierarchies,
measures, MDX, AGXML data security); a Domain brings relational semantics
(joins, derived fields, its own row/column security). AGXML applies only to
Mondrian connections - not to Domains and not locally to XML/A (secure the
remote server instead) (p.93).
Quirks: superuser cannot open Ad Hoc on an XML/A connection - use jasperadmin
or a normal user (p.86). "Maximum number of filter values in an OLAP-based Ad
Hoc view" setting caps filter lists (p.47). Drill-through on parent-child
hierarchies is blocked in Ad Hoc and unreliable in OLAP views (MONDRIAN-388;
p.104) - avoid parent-child hierarchies where possible.

## Security: access grants (AGXML)

Commercial editions only; applies to data read through a LOCAL Mondrian
connection. XML/A traffic must be secured on the remote host (attach the AGXML
there) (10.1 OLAP user p.93).

An `.agxml` file maps JRS ROLES to Mondrian-style grants. Nesting (innermost
wins; 10.1 OLAP user p.93-96):

```xml
<Roles>
  <Role name="StateManager">
    <SchemaGrant access="none">            <!-- default for whole schema: all|none -->
      <CubeGrant cube="Sales" access="all">      <!-- all|none -->
        <HierarchyGrant hierarchy="[Store]" access="custom"
                        topLevel="[Store].[Store Country]"
                        bottomLevel="[Store].[City]">  <!-- all|none|custom -->
          <MemberGrant member="[Store].[USA].[%{State}]" access="all"/>
        </HierarchyGrant>
        <HierarchyGrant hierarchy="[Gender]" access="none"/>
      </CubeGrant>
    </SchemaGrant>
  </Role>
</Roles>
```

- Order matters: grant USA then deny Oregon = Oregon hidden; deny Oregon then
  grant USA = Oregon visible (grants apply in definition order) (p.95).
- Granting a member grants its ancestors too (bounded by topLevel); totals
  still aggregate ALL data, not just visible members (p.95).
- `%{Attr}` substitutes user/organization/server attributes (hierarchical
  attributes since 6.0); user attribute `State=CA,OR,WA` expands the member
  grant to those three states (p.96-97). Manage > Users/Organizations/Server
  Settings > Attributes.
- Role, user, level, and attribute names are CASE-SENSITIVE (p.95).
- Cube/hierarchy names in the AGXML must exactly match the OLAP schema attached
  to the same connection (p.93).
- Design tip: model one hierarchy level per access level, build grants
  iteratively smallest-first (p.99-100). Full worked example: 10.1 OLAP
  ultimate p.49-68 (roles + attributes + grant file).

## MDX as JRS uses it

Canonical shape (10.1 OLAP ultimate p.18):

```
select {[Measures].[Unit Sales], [Measures].[Store Cost]} ON COLUMNS,
       {([Promotion Media].[All Media], [Product].[All Products])} ON ROWS
from [Sales]
where [Time].[2012].[Q4].[12]
```

- FROM names the Cube (must match the schema's Cube name); WHERE is the slicer.
- The viewer builds MDX from UI gestures; "Show MDX Query" in the toolbar
  displays/edits it. Functions the UI emits: `Hierarchize`, `Union`,
  `.Children`, `Crossjoin` (ultimate p.73-77).
- Members are `[Dim].[member].[member]`; whether the dimension prefix is
  mandatory is governed by the "need to be prefixed" setting - with it enabled
  `select {[Omaha]} ...` fails and `{[Nebraska].[Omaha]}` is required
  (10.1 OLAP user p.51-52; recommended ON for large schemas).

## Config knobs (OLAP Settings page = mondrian.properties)

Manage > Server Settings > OLAP Settings (needs ROLE_SUPERUSER in commercial
editions). Each UI label shows the underlying engine property name; values are
stored as server-level attributes - prefer the UI over editing files
(10.1 OLAP user p.46-58). Key limits/timeouts:
- Query Limit - max concurrent queries.
- Result Limit (number of rows) - >0 caps result set rows (mondrian.result.limit).
- If > 0, Maximum query time (seconds) - query timeout; the RolapConnection
  shepherd polling interval must stay BELOW it or the timeout is not enforced.
- Maximum number of MDX query threads per instance.
- Max passes evaluating an MDX expression / max iterations evaluating an
  aggregate / cell batch size / crossjoin optimizer threshold.
- Maximum constraints in a single SQL IN clause (Postgres: 10000).
- Aggregate Settings block: see aggregate tables above.
- Cache/SQL block: expression result cache, RolapCubeMember cache, custom
  SegmentCache class, push-down of NON EMPTY / TopCount / Filter to the DB.
- Memory Monitoring: use Java memory monitoring -> MemoryLimitExceededException
  instead of OOM; threshold percent.
- Generate Formatted SQL Traces + log4j to see generated SQL.
No connectString/jdbcDrivers needed - JRS generates them from the connection's
datasource (p.58).

Config files (10.1 OLAP user p.45, 59-63, 102):
- `WEB-INF/js.config.properties` - `olap.mondrian.scripts.enabled`.
- `WEB-INF/classes/mondrian.connect.string.properties` - `UseContentChecksum`
  (identify cached datasets by schema checksum; DANGEROUS multi-tenant: two
  orgs with identical schemas can see each other's cached data - keep default).
- `...\WEB-INF\applicationContext-olap-connection.xml` - OLAP4J XML/A client cache:
  OLAP4J_CACHE_MODE (LIFO/FIFO/LFU/MFU, default LFU), OLAP4J_CACHE_SIZE
  (commercial 10000), OLAP4J_CACHE_TIMEOUT (commercial 3600s).
- `WEB-INF/log4j.properties` - uncomment `log4j.logger.mondrian.mdx=debug` /
  `mondrian.sql=debug`; `jasperanalysis.drillthroughSQL=DEBUG` for
  drill-through SQL; `log4j.logger.mondrian=debug` for everything.

## Caching / flushing (terminology for manage_cache.ps1)

Three distinct caches:
1. Mondrian in-memory cache (query results + cube metadata). Flush via Manage >
   Server Settings > OLAP Settings > "Flush OLAP Cache" after ETL loads -
   stale data persists until flush or app-server restart (10.1 OLAP user
   p.58-59). It is ALSO auto-flushed whenever a Mondrian connection or its
   schema/datasource is edited in the repository (p.59) - so redeploying via
   `create_mondrian.ps1 -Overwrite` implicitly flushes.
2. Ad Hoc query cache - what `manage_cache.ps1 -CacheId queryCache` clears
   (REST `DELETE /rest_v2/caches/{id}`). This is the Ad Hoc/Domain result
   cache, not the Mondrian cache; the docs expose no REST endpoint for the
   Mondrian flush.
3. XML/A client cache (OLAP4J) - refresh governed by the properties above.
Dataset reuse keying: by connection attributes (default) or schema checksum
(UseContentChecksum; see warning above) (p.59-61).

## Performance notes

- ROLAP: Mondrian issues SQL against your star/snowflake schema; the RDBMS does
  the heavy lifting. Single-table dimensions beat snowflakes; index every FK
  (compound indexes matching join order); NOT NULL everywhere applicable;
  split huge fact tables by time; statistics-based optimizers preferred
  (10.1 OLAP ultimate p.91-92).
- Scale-out: split front end (XML/A client) from OLAP engine (XML/A provider) -
  client's XML/A connections point at provider's Mondrian connections via XML/A
  sources; load-balance multiples of each (10.1 OLAP user p.100-101; ultimate
  p.93-95). First query against a remote XML/A provider is slow (cache warm).
- Performance Profiling Enabled setting -> reports in /performance/reports
  (10.1 OLAP user p.47).

## Failure symptoms -> fixes

- olapUnit create returns 500 (REST) / view validation error (UI): the MDX or
  schema does not resolve against the live DB - table/column names in the
  schema must exist in the connection's datasource; typo in MDX (10.1 OLAP
  user p.39). Script leaves schema+connection intact; fix and retry.
- "cube not found" / catalog not found on Test Connection: XML/A Catalog field
  must equal the schema name, MDX FROM must equal the Cube name; for JRS
  providers Data Source must be exactly `Provider=Mondrian;DataSource=JRS`
  (post-5.6) (10.1 OLAP user p.83-86).
- XML/A connection worked, now fails: the stored remote user's password
  changed, or a `\` in the username is not escaped (p.84).
- Sample XML/A views/reports fail: URI ports are hard-coded to 8080; edit the
  connections if Tomcat runs elsewhere (e.g. this install's STAGE on 8081)
  (p.105).
- Empty/partial results for some users only: AGXML role grants - SchemaGrant
  access="none" default hides everything not explicitly granted; grant order;
  case-sensitive role/level/attribute names; user missing the attribute used in
  %{...} substitution (p.93-97).
- "OLAP view scripting feature is disabled": schema contains Javascript;
  enable olap.mondrian.scripts.enabled or strip the scripts (p.45).
- Data stale after ETL: flush the OLAP cache (or touch the connection) (p.58).
- Query errors citing a limit/property value: you hit Result Limit, iteration
  limit, or query timeout - raise the corresponding OLAP Setting (p.48-51).
- Multi-org XML/A auth failures: pass `user|orgId`, never superuser (p.86-88).
- Drill-through wrong/blocked on parent-child hierarchies: engine defect,
  avoid parent-child dims (p.104).
- 404s changing cubes under WebLogic: WebLogic config + stale files; see the
  JRS Installation Guide (p.105).

## 9.0.0 differences

None material. The 9.0 user and ultimate guides have the identical section
structure and content as 10.1 (including the "as of 8.2" Javascript lockdown);
the only structural delta is that the 9.0 guides still carry a Glossary chapter
(9.0 OLAP user p.104; 9.0 OLAP ultimate p.100) that 10.1 dropped. Guidance
above applies unchanged to 9.0 and to the local 10.0 install.
