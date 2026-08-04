# Domains deep reference: schema XML, DomEL, security, locale bundles

[doc-only] Everything here is derived from the official Jaspersoft docs
(js-jrs_10.1.0_domains-guide.pdf, cross-checked against the 9.0.0 guide), NOT
verified against the live server. For the VERIFIED, scripted creation flow
(scaffold_domain_schema.py + create_domain.ps1, inline schemaFile, the join-tree
shape that actually deploys on JRS 10) defer to
`references/data-and-semantic-layer.md` -- where the two disagree, trust that
file. Page cites are to the 10.1 guide.

## Design file anatomy

The design file is a `schema.xml` (materializes at `<domainUri>_files/schema.xml`).
Root element (10.1 guide p.95):

```xml
<schema xmlns="http://www.jaspersoft.com/2007/SL/XMLSchema"
        version="1.3" schemaLocation="schema_1_3.xsd">
  <dataIslands>  (0..1)  declares presentation data islands
  <dataSources>  (0..1)  the ONE datasource + database schemas
  <itemGroups>   (0..n)  sets; one itemGroups element per data island
  <items>        (0..n)  loose items not in any set; one per island
  <resources>    (1)     tables, derived tables, joins, calc fields, pre-filters
</schema>
```

- XSDs ship in `<install-dir>/samples/domain-xsd/`; current is `schema_1_3.xsd`
  (p.92). XML is NOT the native format -- the repo stores an internal design and
  the XML is a projection; repeated export/edit/upload cycles may drift (e.g.
  the Designer sometimes renames `JoinTree_1`, which breaks the security file)
  (p.93).
- Escape `& " < >` as `&amp; &quot; &lt; &gt;` everywhere, including join
  expressions (p.94).
- Minimum usable Domain: a datasource ref, >=1 table, >=1 presentation item
  (p.92). Everything under `resources` must exist in the real database.
- `id` attributes (tables, fields, sets, items): alphanumeric plus `@#$^`_~?`,
  must not start with a digit (p.99, p.105).

## dataSources / schemaMap

One datasource max. `jdbcDataSource id="..."` for Domains; `jrQueryDataset` for
Topics (either/or, p.97). The id is an ALIAS local to the file -- the binding to
the repository datasource is metadata on the Domain resource, set outside the
XML (p.97; the skill's `create_domain.ps1 -DataSourceUri` supplies it, and the
alias must equal the leaf of that URI -- see G31).

```xml
<dataSources>
  <jdbcDataSource id="dsFoodMart">
    <schemaMap>
      <entry key="public"><string>public</string></entry>
      <entry key="defaultSchema"><string>public</string></entry>
    </schemaMap>
  </jdbcDataSource>
</dataSources>
```

- `schemaMap/entry key=...` names a DB schema; the reserved key
  `defaultSchema` sets a fallback used when a schema name is missing/an
  attribute is null (p.99-100). Schema keys cannot contain periods or start
  with a digit (p.100).
- Schemaless DBs (MySQL): `dataSources` optional, `schemaAlias` not required.
- `<string>` may be an attribute expression: `{attribute('schemaAttr')}`
  (p.101). If the attribute is undefined server-wide, the Domain fails.

## Tables: jdbcTable (p.104-108)

```xml
<jdbcTable id="store" datasourceId="dsFoodMart" schemaAlias="public"
           datasourceTableName="store">
  <fieldList>
    <field id="store_id" fieldDBName="store_id" type="java.lang.Integer"/>
  </fieldList>
  <filterString>...optional DomEL pre-filter...</filterString>
</jdbcTable>
```

- `datasourceId` must be identical for ALL tables/derived tables (p.104).
- Copies of a table (self-join) share schemaAlias/datasourceTableName but need
  distinct `id`s (p.105).
- In a virtual datasource, `schemaAlias` is `dataSourcePrefix` (schemaless) or
  `dataSourcePrefix_schema` (p.105-106).
- The Designer always takes whole tables; hand-written XML may list any SUBSET
  of columns -- but every column referenced anywhere (joins, calc fields) must
  be declared (p.106-107).
- `field type` = Java type from JDBC. Allowed: Boolean, Byte, Character,
  Double, Float, Integer, Long, Short, String, BigDecimal, java.sql.Date/
  Time/Timestamp, java.util.Date (p.108). An explicit `type` overrides the
  server's JDBC mapping for proprietary DB types.

## Derived tables: jdbcQuery (p.108-113)

A SQL query inside the Domain. Same shape as jdbcTable plus `<query>`:

```xml
<jdbcQuery id="expenses_usd" datasourceId="dsFoodMart">
  <fieldList>
    <field id="exp_date" type="java.sql.Timestamp"/>
    <field id="as_dollars" type="java.math.BigDecimal"/>
  </fieldList>
  <query>select e.exp_date, amount * c.conversion_ratio as_dollars
         from expense_fact e join currency c on (e.currency_id = c.currency_id)</query>
</jdbcQuery>
```

- Field `id` = literal column name in the query RESULT (alias wins on
  `SELECT ... AS`); only selected columns are usable (p.111-112). No trailing
  semicolon in the SQL (p.111).
- The derived table becomes a SUBQUERY in generated SQL: SQL Server rejects
  ORDER BY in it without TOP/FOR XML (p.112); the wrap can be slower than a
  plain table (p.113).
- Virtual datasources validate the SQL as Teiid SQL (p.112); Trino-based
  datasources accept Trino functions/operators in derived tables (p.60).
- Calc fields inside the derived-table SQL may use ANY RDBMS function; Domain
  calc fields are limited to DomEL (p.113).

## Joins: a join tree is a jdbcTable (p.113-125)

One `jdbcTable` per join tree, carrying every referenced column of every joined
table as `table_ID.field_name` fields, plus:

```xml
<jdbcTable id="JoinTree_1" datasourceId="dsFoodMart" schemaAlias="public"
           datasourceTableName="customer">     <!-- FIRST table of the tree -->
  <fieldList>
    <field id="customer.account_num" fieldDBName="account_num" type="java.lang.Long"/>
    ...
  </fieldList>
  <joinInfo alias="customer" referenceId="customer"/>
  <joinOptions suppressCircularJoins="true"/>
  <tableRefList>
    <tableRef tableId="customer" tableAlias="customer"/>
    <tableRef tableId="store" tableAlias="store"/>
    <tableRef tableId="region" tableAlias="region" alwaysIncludeTable="true"/>
  </tableRefList>
  <joinList>
    <join left="customer" right="store" type="inner"
          expr="customer.region_id == store.region_id"/>
    <join left="store" right="region" type="leftOuter" weight="2"
          expr="store.region_id == region.region_id"/>
  </joinList>
</jdbcTable>
```

Rules that bite:
- `joinInfo` names the first/anchor table; its two attributes are required even
  when identical to the jdbcTable attrs (p.116, p.118). The anchor must be the
  LEFT table of the FIRST join (p.116).
- Join order matters: a join's `left` table must already be defined -- via
  joinInfo or as the `right` of an EARLIER join in the same joinList (p.125).
  New tables enter as `right`.
- `type`: inner (default) | leftOuter | rightOuter | fullOuter (fullOuter not
  supported on MySQL) (p.120).
- `expr` is DomEL: `==` plus `AND OR NOT`, `< <= > >= !=` (only in conjunction
  with an `==`), `IN(set)` / `IN(min:max)` ranges, constants. `<`/`>` must be
  written `&lt;`/`&gt;` (p.120-121). First column of a direct comparison must
  come from the left table. Oracle Date literals need `Date('1914-02-02')`
  (p.121).
- `joinOptions suppressCircularJoins="true"` -> Ad Hoc uses the minimum-weight
  join set (best practice; p.122). Higher `weight` = less desirable join; equal
  weights = fewest-joins path (p.120, p.125). `includeAllDataIslandJoins` is
  legacy back-compat only.
- `tableRef alwaysIncludeTable="true"` forces the table into every Ad Hoc query
  from that island (p.123).
- An unjoined table listed in a join tree pollutes Ad Hoc views with unusable
  fields and errors (p.119).
- Designer-uneditable (imported as READ-ONLY joins): OR/NOT between join
  expressions, self-joins between two columns of the same table (p.91).

## Pre-filters: filterString (p.126-127)

Optional child of jdbcTable (table or join tree) and jdbcQuery; a DomEL boolean
applied per-row (becomes part of the WHERE clause).

```xml
<filterString>opportunity_type == 'Existing Business'</filterString>       <!-- table: bare field id -->
<filterString>store.store_city IN('San Francisco','Portland')</filterString><!-- join tree: table_ID.field -->
```

Designer only edits single-column conditions AND-ed together; anything fancier
(OR across conditions etc.) is upload-only and shows read-only (p.127).

## Calculated fields (p.127-131)

A `field` with a `dataSetExpression` (DomEL). Placement/id rules:
1. All source columns from ONE table -> the field appears TWICE: under that
   table's jdbcTable/jdbcQuery with bare `id="city_and_state"`, AND under the
   join tree with `id="accounts.city_and_state"` (p.128-130).
2. Columns from DIFFERENT tables -> once only, under the join tree,
   `id="jointree_ID.field_name"`. Cross-join-tree calc fields are impossible
   (p.128).
3. Constant fields (no column refs) -> under `<null id="constant_fields_level"
   datasourceId="...">` <fieldList>...` in resources; usable in any island and
   in other calc fields/pre-filters (p.128, p.131).

```xml
<field id="city_and_state" type="java.lang.String"
       dataSetExpression="concat(billing_address_city, ', ', billing_address_state)"/>
```

`type` must be JDBC-compatible with what the expression returns (p.129).

## Presentation: dataIslands, itemGroups, items (p.131-142)

```xml
<dataIslands>
  <itemGroup id="JoinTree_1" resourceId="JoinTree_1"/>   <!-- one per join tree / lone table -->
</dataIslands>
<itemGroups>                                             <!-- one per island -->
  <itemGroup id="AccountsSet" label="Accounts" resourceId="JoinTree_1">
    <itemGroups>
      <itemGroup id="AddressSubset" label="Account Address" resourceId="JoinTree_1">
        <items>
          <item id="billing_address_city" label="Account City"
                resourceId="JoinTree_1.accounts.billing_address_city"/>
        </items>
      </itemGroup>
    </itemGroups>
    <items><item id="name" label="Account Name" resourceId="JoinTree_1.accounts.name"/></items>
  </itemGroup>
</itemGroups>
<items>  <!-- island items outside any set -->
  <item id="created_by" label="Account Creator" resourceId="JoinTree_1.accounts.created_by"/>
</items>
```

- item `resourceId`: `table_id.field_ID` (unjoined table) or
  `jointree_id.table_ID.field_name` (join tree) (p.139). Every descendant of
  one `itemGroups` must resolve through the SAME island resource (p.134).
- Set/item `id`s must be unique among ALL sets and items (p.136, p.138) --
  this is the `element.name.not.unique` failure the scaffolder dedupes (G32b).
- Item properties (p.138-141): `label` (falls back to id), `description`
  (tooltip), `labelId`/`descriptionId` (i18n keys, chars: alnum + `.` ` ` ~ _`),
  `dimensionOrMeasure="Dimension|Measure"` (override only; numeric fields
  default to Measure), `defaultMask` (format), `defaultAgg` (summary function).
- `defaultMask` values by type (p.140): Integer `#,##0` | `0` |
  `$#,##0;($#,##0)` | `#,##0;(#,##0)`; Double same with `.00` variants; Date
  `short` | `medium` | `long` | `hide` prefix variants (`hidemedium` etc.);
  other types: not allowed.
- `defaultAgg` values (p.140-141): Max, Min, Average, Sum, CountDistinct,
  CountAll (availability depends on type).

## DomEL (p.149-156)

Used in: join `expr`, calculated fields, filterString pre-filters, attribute
values, security filterExpressions (p.149). The server compiles DomEL into the
generated SQL (or, depending on the Ad Hoc data policy, applies it in memory
to a simpler query's result -- p.149).

Types (p.150-151): integer `123`; decimal `123.45` (dot separator only);
string `'single quotes only'`; date `d'2009-03-31'` or `Date('2009-03-31')`;
timestamp `ts'2009-03-31 23:59:59'` / `TimeStamp(...)`; boolean values exist
but the literals true/false do NOT; composites: set `('a','b')`, inclusive
range `(0:12)`, `(d'2009-01-01':d'2009-12-31')`.

Field references depend on context (p.151-152): derived-table SQL and join
exprs use `table_id.field_name`; calc field / filter ON a table uses bare
`field_name`; ON a join tree uses `table_id.field_name`; Ad Hoc view calc
fields may use `"Field Label"` in double quotes.

Operators, high to low precedence (p.152-153): `* /` | `%` (i as percent of j)
| `+ -` | `== !=` (string/numeric/date) | `< <= > >=` (numeric/date) |
`IN(set)` `IN(lo:hi)` | `NOT(x)` (parens required) | `AND` | `OR`.
Functions: `startsWith(f,'p')`, `endsWith(f,'s')`, `contains(f,'sub')`,
`concat(a,b,...)`.

- Raw SQL functions ARE allowed inside DomEL if: the DB supports them, they use
  comma-separated args (`TRIM(x)` ok, `TRIM('Jr' FROM x)` not), types line up,
  and context fits -- NO aggregates like COUNT in calc fields (no GROUP BY)
  (p.154). None of this is validated; it fails at report time.
- `groovy('code')` embeds a Groovy expression whose STRING result is spliced
  into the SQL (p.154-155). Unvalidated.
- Parentheses group booleans only; parenthesized ARITHMETIC is unsupported --
  split complex math into chained calculated fields (p.155).
- Expected return types (p.156): join expr -> boolean; pre-filter -> boolean;
  calc field -> must match its declared Java `type`.

## Server attributes in designs (p.142-147)

`attribute('name')` (hierarchical: user -> tenant -> parents -> server) or
`attribute('name','user'|'tenant'|'server')`. Plain form in DomEL spots (calc
fields, join exprs -- but never the FIRST join of an expression, p.146 --
pre-filters); curly-escaped `{attribute('name')}` in schema-name strings and
derived-table SQL (p.144-145). Attribute values are always strings; cast with
`Integer() Decimal() Boolean() Date() Time() Timestamp()` (p.146). Empty
attribute: '' for String fields, FALSE for Boolean, ERROR for numeric/date
pre-filters; derived-table/join usage mostly fails; schema names fall back to
defaultSchema (p.147). Undefined (nonexistent) attribute: hard failure.

## Domain security file (p.157-180)

Separate XML attached on the Security tab (upload from file, or reference a
repository file resource shareable across structurally identical Domains,
p.174). Skeleton (p.179-180):

```xml
<securityDefinition xmlns="http://www.jaspersoft.com/2007/SL/XMLSchema"
                    version="1.0" itemGroupDefaultAccess="granted">
  <resourceAccessGrants>          <!-- ROW-level -->
    <resourceAccessGrantList id="uniq1" label="l" resourceId="JoinTree_1">
      <resourceAccessGrants>
        <resourceAccessGrant id="uniq2">
          <principalExpression>authentication.getPrincipal().getRoles().any
            { it.getRoleName() in ['ROLE_SUPERMART_MANAGER'] }</principalExpression>
          <filterExpression>s.store_country in ('USA') and s.store_state in ('CA')</filterExpression>
        </resourceAccessGrant>
      </resourceAccessGrants>
    </resourceAccessGrantList>
  </resourceAccessGrants>
  <itemGroupAccessGrants>         <!-- COLUMN-level -->
    <itemGroupAccessGrantList id="uniq3" label="l" itemGroupId="JoinTree_1"
                              defaultAccess="denied">
      <itemGroupAccessGrants>
        <itemGroupAccessGrant id="uniq4" access="granted">
          <principalExpression>...</principalExpression>
          <itemAccessGrantList id="uniq5" defaultAccess="denied">
            <itemAccessGrants>
              <itemAccessGrant id="uniq6" itemId="StoreSales" access="granted"/>
            </itemAccessGrants>
          </itemAccessGrantList>
        </itemGroupAccessGrant>
      </itemGroupAccessGrants>
    </itemGroupAccessGrantList>
  </itemGroupAccessGrants>
</securityDefinition>
```

Mechanics (p.167-173):
- `principalExpression` is GROOVY (true = grant applies to current user).
  Roles: `authentication.getPrincipal().getRoles().any { it.getRoleName() in
  ['ROLE_X','ROLE_Y'] }`. Attributes:
  `attributesService.getAttribute('Attr', null|'USER'|'TENANT'|'SERVER'
  [, required])` -- with required=false (default) a missing attribute silently
  SKIPS the filterExpression, i.e. the user sees UNFILTERED data (p.169);
  pass `true` to error instead.
- `filterExpression` is DomEL added to the WHERE clause. Helper:
  `testProfileAttribute(table_ID.field_name, 'Attr'[, Level])` compares a field
  to the user's (possibly multi-valued) attribute (p.169-170). Attribute
  COLLECTIONS are supported here (unlike in the main design, p.147).
- Multiple resource grants combine with logical AND by default; set
  `orMultipleExpressions` to TRUE for OR (p.171).
- Column grants: principalExpression picks the users; nested
  itemAccessGrantList with `defaultAccess="denied"` then whitelists items by
  `itemId` (the presentation item/set ids). A denied column renders as
  zeros/blank in reports, NOT an error (p.172-176).
- Every grant id must be unique within the file (p.171).
- The uploaded file is validated for XML syntax + Domain IDs on upload, and for
  join references + principal expressions on save (p.175). Groovy validation is
  "very lightweight" -- test as each user via Login as User (p.175, p.178).
- If the Domain design changes (esp. auto-renamed JoinTree ids), re-export the
  design and fix ids in the security file too (p.179).

## Locale bundles (p.181-195)

Java `.properties` files translating labels/descriptions. Naming:
`<any_name>_<locale>.properties` (`Labels_fr.properties`), plus optional
default `<any_name>.properties` (p.186). Keys default to
`<islandID>.<setID>...<itemID>.LABEL` / `.DESCR`, or custom via
`labelId`/`descriptionId` on itemGroup/item; unique across the Domain;
ISO Latin-1 chars, digits, underscores only (p.187). Values: everything after
`=`; file encoding ISO-8859-1 with `\uXXXX` escapes for the rest; escape the
apostrophe as the right-single-quote escape sequence backslash-u2019 (a straight `'`
misbehaves in Domain properties files) (p.187-189).

Resolution order: user-locale file -> default file -> label/description attr
in the design -> the id (label) / blank (description) (p.188).

Attach on the Locales tab: upload files directly (stored with the Domain) or
reference repository file resources of type Resource Bundle (shareable across
Domains; keep the `.properties` extension in Name and ID) (p.189-192). The
Designer exports a key template from the Locales tab ("Generate missing
label/description keys") (p.184-185). After adding bundles or re-uploading a
design to a live Domain, CLEAR THE AD HOC CACHE (p.87, p.192).

## Ad Hoc integration

- A Topic is a JRXML-query-based source for Ad Hoc; a Domain is the semantic
  layer. In a design file the split is visible at the datasource: Topics use
  `jrQueryDataset`, Domains `jdbcDataSource` (p.96-97, p.101).
- A "Domain Topic" is a saved Ad Hoc slice of a Domain: Create > Ad Hoc Report
  > pick the Domain > customize Data/Filters/Display > save from the Topics
  page (p.179). Recommended pattern: one broad Domain, several focused Domain
  Topics.
- Data policies (whether DomEL is pushed down as augmented SQL or applied
  in-memory to a broader result, p.149) are server Ad Hoc settings documented
  in the Administrator guide, not the Domains guide.
- Domain security + locale bundles take effect in the Ad Hoc Editor and in
  final report output (p.89).

## Editing / round-tripping (p.85-93)

- Export the design: edit the Domain in the Designer -> export `schema.xml`
  from the menu bar (p.86). Export the Domain WITH datasource/security/bundles/
  permissions: repository right-click > Export -> zip catalog (p.87-88) -- this
  is what the skill's `export_resource.ps1`/`import_resource.ps1` automate.
- Upload replaces the whole design without prompting; syntax/semantic errors
  abort the replace. Then SAVE the Domain, and clear the Ad Hoc cache (p.86-87).
- Validation runs on open-for-edit, datasource replacement, XML upload, and
  save; it checks (p.85): tables/columns exist in the datasource (skippable via
  a server config param for design-before-datasource), all items of a set share
  one join tree, items reference existing columns, derived-table SQL is valid,
  and security-file items/sets all exist in the design.
- What breaks references: renaming table ids / item ids invalidates security
  files and locale keys built on them; the Designer itself sometimes renames
  join trees (p.93, p.179). If DB table/column names change, you can edit the
  design XML resource names and re-upload -- dependent reports keep working --
  but the security file must be edited in step (p.179).
- Design-file-only features (Designer shows read-only): OR/NOT joins,
  same-table self-joins, defaultSchema-with-attribute, per-column table
  subsets (p.91).

## Failure symptoms -> causes (doc-derived; see gotchas.md G30-G32b for the verified ones)

| Symptom | Likely cause / fix |
|---|---|
| Upload rejected, syntax error | Not valid vs schema_1_3.xsd; unescaped `& < > "`; id starts with digit or has illegal chars |
| Upload ok, save fails validation | Table/column missing in datasource; item references column not in fieldList; set mixes join trees; derived-table SQL invalid (p.85) |
| `element.name.not.unique` 400 | Item/set ids repeat across itemGroups; dedupe like the scaffolder (G32b) |
| Join tree fields error in Ad Hoc | Unjoined table in tableRefList; join `left` table not yet defined (order joins so new tables enter on the right, p.125) |
| Calc field errors at report time | DomEL type vs declared `type` mismatch; parenthesized arithmetic; aggregate SQL function in calc field (p.154-155) |
| Users see data they should not | principalExpression attribute lookup with required=false and attribute unset -> filter silently skipped (p.169) |
| Security file accepted but empty results | itemId/resourceId in grants do not match current design ids (Designer renamed JoinTree); defaultAccess=denied with no grants matching |
| Denied column shows zeros | Working as designed: column-level denial blanks values, does not error (p.176) |
| Labels show raw ids | Locale key mismatch or bundle not attached; check resolution order (p.188); clear Ad Hoc cache |
| Domain fails after schema attr change | Attribute undefined at every level, or defaultSchema not declared (p.100, p.147) |

## 9.0.0 differences

None material. The 9.0.0 guide is the same document at the same schema version
(1.3, schema_1_3.xsd) with identical element sets, DomEL, security syntax, and
even the Trino/Teiid notes; only pagination differs (10.1 = 200 pp, 9.0 = 191
pp). Anything above applies to both, and to the JRS 10.0.0 install this skill
targets.
