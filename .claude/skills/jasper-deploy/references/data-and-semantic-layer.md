# Data sources, Domains, Ad hoc views, OLAP, Themes

Deep reference for the data/semantic/presentation resources a report or dashboard
sits on. `$skill` = the skill's `scripts/` dir.

## Data sources — `create_datasource.ps1`
A report needs a JDBC datasource on the server to run. Create it once (the
PostgreSQL driver ships with JRS):
```powershell
& $skill\create_datasource.ps1 `
    -Uri /datasources/postgis_34_sample `
    -Label "PostGIS 34 Sample" `
    -Database postgis_34_sample -DbUser postgres -DbPassword postgres
```
Defaults target PostgreSQL `localhost:5432`; override with `-DbHost -DbPort
-DbUser -DbPassword`, or pass a full `-ConnectionUrl` and `-DriverClass` for
another engine. NOTE: PowerShell reserves `-Db` (alias of `-Debug`), so the
database-name parameter is `-Database`.

**`-Test` — validate the LIVE connection before creating.** A plain create only
stores the descriptor (it 201s with a wrong password!). `-Test` first POSTs the
descriptor to `/rest_v2/contexts`, which makes the **JRS JVM actually open the
connection**: 201 = good, and creation proceeds; a failure throws with the
driver's real error (e.g. `FATAL: password authentication failed`, SQL state
28P01) and nothing is stored. Supported for `jdbc`/`jndi`/`custom` (the media
type must be the descriptor's own `repository.<type>+json` — G52); other types
warn and skip the test. `doctor.ps1` runs the same check as
"JRS->DB connection (contexts)".

**List existing datasources** — use **`type=jdbcDataSource`** (the generic
`type=dataSource` returns `204`/empty on this server and looks like "no
datasources"):
```powershell
curl.exe -s -u "${user}:${pass}" "http://localhost:8081/jasperserver-pro/rest_v2/resources?type=jdbcDataSource&recursive=true"
```

### Non-JDBC datasources — `create_datasource.ps1 -Type`
Also emits `jndi|bean|custom|virtual|aws` descriptors (the matching
`application/repository.<type>DataSource+json` media type):
```powershell
& $skill\create_datasource.ps1 -Type jndi    -Uri /datasources/fm_jndi -JndiName jdbc/foodmart
& $skill\create_datasource.ps1 -Type bean    -Uri /datasources/fm_bean -BeanName myDsBean -BeanMethod getDataSource
& $skill\create_datasource.ps1 -Type custom  -Uri /datasources/cds -ServiceClass com.acme.MyDsService -Properties @{k="v"}
& $skill\create_datasource.ps1 -Type virtual -Uri /datasources/combined `
    -SubDataSources ([ordered]@{ fm='/public/Samples/Data_Sources/FoodmartDataSource'; pg='/datasources/postgis_34_sample' })
& $skill\create_datasource.ps1 -Type aws     -Uri /datasources/rds -DbInstanceIdentifier mydb `
    -Database foodmart -AccessKey AKIA... -SecretKey ...   # -Region defaults to us-east-1.amazonaws.com
```
**Verified:** `jndi`, `virtual`, and `aws` create (`201`) and round-trip. NOTE:
creating a non-JDBC datasource validates the **descriptor shape** and stores the
resource; actually *connecting* needs the server-side prerequisite (a JNDI
resource in the app server, a Spring bean on the classpath, a custom data-source
service, the referenced sub-datasources, or live AWS creds). **AWS `-Region`
gotcha:** the value is the AWS **endpoint host** (`us-east-1.amazonaws.com`,
`eu-west-1.amazonaws.com`), NOT the bare `us-east-1` code (which `400`s "invalid
Region").

## Domains (semantic layer) — `scaffold_domain_schema.py` + `create_domain.ps1`
A **Domain** (`semanticLayerDataSource`) is a business-friendly view of a
datasource that Ad Hoc views and Domain reports query. It is two resources: a
descriptor binding a JDBC datasource to a **schema.xml** (tables, fields, and the
"items" exposed to the designer).

A **single-table** Domain is fully scripted. `scaffold_domain_schema.py`
introspects one table's columns (psql/`information_schema`) and emits the
`schema.xml`; `create_domain.ps1` creates the Domain:
```powershell
$env:PGPASSWORD = "postgres"
python $skill\scaffold_domain_schema.py --name foodmart_product --table product `
    --db foodmart --datasource-id FoodmartDataSource --out report\foodmart_product_schema.xml
& $skill\create_domain.ps1 -Uri /domains/foodmart_product `
    -SchemaFile report\foodmart_product_schema.xml `
    -DataSourceUri /public/Samples/Data_Sources/FoodmartDataSource -Label "Foodmart Product" -Overwrite
```
**Verified:** the Domain creates (`201`), the schema **materializes** at
`<Uri>_files/schema.xml`, the descriptor round-trips, and its
`GET /rest_v2/domains{uri}/metadata` behaves identically to the shipped sample
Domains. **Two gotchas the script handles:**
1. The schema's `<jdbcTable datasourceId="…">` must equal the **leaf** of
   `-DataSourceUri` (pass it as `--datasource-id`; the script warns on a mismatch).
2. The schema must be **embedded inline** in the descriptor
   (`schema.schemaFile.content` base64, like a reportUnit's jrxml) — a pre-uploaded
   `schemaFileReference` fails `500 resource.does.not.exist` because the `_files`
   child is orphaned until the parent exists.

**Multi-table** Domains (joins) are now fully scripted too — repeat `--table`
and wire the tables with `--join` (`left_table.col=right_table.col[:inner|left|
right|full]`; inner is the default and the verified type; N tables need ≥ N-1
joins):
```powershell
python $skill\scaffold_domain_schema.py --name product_join `
    --table product --table product_class `
    --join "product.product_class_id=product_class.product_class_id" `
    --db foodmart --datasource-id FoodmartDataSource --out out\product_join_schema.xml
& $skill\create_domain.ps1 -Uri /domains/product_join -SchemaFile out\product_join_schema.xml `
    -DataSourceUri /public/Samples/Data_Sources/FoodmartDataSource -Label "Product Join" -Overwrite
```
This emits the JRS 10 Domain-Designer **v1.3 join-tree ("data island") shape**
(reverse-engineered from a live designer-authored export): per-table `jdbcTable`
resources (`datasourceTableName` + `schemaAlias`, not `tableName`), plus one
join-tree `jdbcTable` named after the Domain carrying every table's fields
(`table.col` ids), `joinInfo` anchored on the LEFT table of the first join, a
`joinList` of `expr="a.x == b.y"` entries, and a `tableRefList`; `dataIslands`
declares the tree and every `itemGroup` resolves its items THROUGH it
(`resourceId="name.table.col"`). **Verified end-to-end:** create `201`, both
tables' items surface in `GET /rest_v2/domains{uri}/metadata`, and a
`queryExecutor` query selecting fields from BOTH tables returns joined rows.
**Gotcha the script handles:** item ids must be **globally unique across all
itemGroups** — a repeated column name (the join key, typically) fails
`400 domain.schema.presentation.element.name.not.unique`; the scaffolder
dedupes designer-style (`col`, `col_1`, …) while keeping the plain column name
as the label. Domains too complex to describe as one join list (multiple
islands, calculated fields, filters) are still Designer territory — promote
those with `export_resource.ps1`/`import_resource.ps1`.

## Ad hoc views — `manage_adhoc.ps1`
An **Ad Hoc view** (`adhocDataView`) is authored interactively in the Ad Hoc
Designer over a Topic (a jrxml file), a Domain, or a datasource. Its descriptor
carries a large opaque `query.multiAxis` + `component` state plus a companion
binary, so it is **not** scaffolded from scratch and a raw JSON **PUT does not
work** (the server rejects it `500 "bytes is null"` — the same don't-PUT lesson as
dashboards). `manage_adhoc.ps1` makes the lifecycle scriptable:
```powershell
& $skill\manage_adhoc.ps1 -Action list   -Folder /public/Samples/Ad_Hoc_Views
& $skill\manage_adhoc.ps1 -Action get    -Uri <view> -OutFile backups\view.json   # inspect / diff (not redeployable)
& $skill\manage_adhoc.ps1 -Action export -Uri <view> -OutFile backups\view.zip    # portable backup (carries Topic/Domain)
& $skill\manage_adhoc.ps1 -Action import -Zip backups\view.zip                     # restore / clone / promote
```
**Verified:** list, get-to-JSON, and the export→import round-trip. `export`/
`import` wrap the proven `export_resource.ps1`/`import_resource.ps1` envelope
(carries the view *and* its backing Topic/Domain, re-imports rendering-intact);
`promote.ps1` does dev→prod in one step.

## OLAP / Mondrian — `create_mondrian.ps1`
Server-side OLAP is three resources: an `olapMondrianSchema` (the Mondrian
cube/dimension XML, a file resource), a `secureMondrianConnection` binding a JDBC
datasource to that schema, and optionally an `olapUnit` analysis view (a saved MDX
query). `create_mondrian.ps1` does all three:
```powershell
& $skill\create_mondrian.ps1 -Uri /analysis/foodmart -SchemaFile report\foodmart_schema.xml `
    -DataSourceUri /public/Samples/Data_Sources/FoodmartDataSource -Label "Foodmart OLAP" -Overwrite `
    -ViewUri /analysis/foodmart_sales `
    -MdxQuery "select {[Measures].[Unit Sales]} on columns, {[Product].[All Products]} on rows from Sales"
```
**Verified:** the schema uploads + the `secureMondrianConnection` creates (`201`)
and round-trips (`schema.schemaReference` + `dataSource.dataSourceReference`).
Unlike a Domain, a Mondrian schema is a **standalone** resource (referenced, not
embedded). **The `olapUnit` view is best-effort:** creating it OPENS the
connection and validates the MDX against the live cube, so it `500`s unless the
schema actually parses against the backing DB (tables/columns must match) — the
script warns and still leaves the schema + connection in place. Grab a sample
schema to start from:
`GET /rest_v2/resources/public/Samples/OLAP/Schemas/FoodmartSchema2013.xml`.

## UI themes (CSS) — `scaffold_theme.py` + `deploy_theme.ps1`
A **theme** restyles the JRS web UI via a folder of CSS (key file
`overrides_custom.css`) under a `Themes` folder. `scaffold_theme.py` emits a
starter `overrides_custom.css` from a palette; `deploy_theme.ps1` deploys it (one
CSS file or a whole folder incl. images/fonts) and can activate it for an
organization:
```powershell
python $skill\scaffold_theme.py --name corporate --palette corporate --out themes\corporate\overrides_custom.css
& $skill\deploy_theme.ps1 -CssFile themes\corporate\overrides_custom.css -Name corporate -Overwrite
# or a full theme folder, deployed to an org and made active:
& $skill\deploy_theme.ps1 -ThemeDir themes\corporate -Name corporate `
    -ThemesFolder /organizations/organization_1/themes -Activate -Organization organization_1
```
Themes take effect immediately (no restart). Without `-Activate`, preview by
appending **`&theme=<name>`** to any logged-in JRS UI URL. Activation is a
property of the **organization** (`PUT /rest_v2/organizations/{id}`
`{"theme":"<name>"}`). `-Overwrite` deletes an existing same-named theme folder
first (the ZIP-upload UI refuses to overwrite). **Verified:** scaffold → deploy →
the CSS serves back from its repo URI. The scaffolded selectors (banner, primary
buttons, login, table headers) are a **starting point** — refine against your
install's actual markup.
