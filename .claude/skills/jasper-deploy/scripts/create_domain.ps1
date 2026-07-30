<#
.SYNOPSIS
  Create (or update) a JasperReports Server Domain (semantic layer) via REST v2:
  upload the schema.xml as a companion file, then PUT the semanticLayerDataSource
  descriptor that binds a JDBC datasource to that schema.

.DESCRIPTION
  A Domain is a semanticLayerDataSource resource whose descriptor references:
    * dataSource.dataSourceReference.uri  -> an existing JDBC datasource
    * schema.schemaFileReference.uri      -> a schema.xml file resource
  This script uploads -SchemaFile to <Uri>_files/schema.xml (the convention the
  Domain Designer uses) as an application/repository.file+json (type xml), then
  PUTs the semanticLayerDataSource descriptor referencing both.

  Generate the schema.xml with scaffold_domain_schema.py -- one --table for the
  single-table shape, several --table + --join for a multi-table (join tree)
  Domain. This script deploys either shape unchanged (it is schema-agnostic);
  Designer-authored Domains promoted via import_resource.ps1 also still work.

  IMPORTANT: the schema's <jdbcTable datasourceId="..."> must match a logical id
  JRS resolves to -DataSourceUri. scaffold_domain_schema.py defaults datasourceId
  to the value you pass as --datasource-id; pass the -DataSourceUri leaf there so
  the two line up (this script warns if you forget).

  Credentials resolve: params -> JRS_URL/JRS_USER/JRS_PASS -> jrs.config.json.

.PARAMETER Uri            Repository URI for the Domain, e.g. /domains/tx_counties.
.PARAMETER SchemaFile     Local schema.xml (from scaffold_domain_schema.py).
.PARAMETER DataSourceUri  Existing JDBC datasource URI the Domain reads from.
.PARAMETER Label          Domain label (default: the URI leaf).

.EXAMPLE
  .\create_domain.ps1 -Uri /domains/foodmart_product `
      -SchemaFile out\foodmart_product_schema.xml `
      -DataSourceUri /public/Samples/Data_Sources/FoodmartDataSource `
      -Label "Foodmart Product Domain" -Overwrite
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Uri,
    [Parameter(Mandatory)][string]$SchemaFile,
    [Parameter(Mandatory)][string]$DataSourceUri,
    [string]$Label,
    [string]$Description = "",
    [switch]$Overwrite,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")

if (-not (Test-Path $SchemaFile)) { throw "schema file not found: $SchemaFile" }
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password
if (-not $Uri.StartsWith("/")) { $Uri = "/$Uri" }
if (-not $DataSourceUri.StartsWith("/")) { $DataSourceUri = "/$DataSourceUri" }
if (-not $Label) { $Label = ($Uri -split "/")[-1] }

# warn if the schema's datasourceId doesn't reference the datasource leaf
$dsLeaf = ($DataSourceUri -split "/")[-1]
$schemaText = Get-Content $SchemaFile -Raw
if ($schemaText -notmatch [regex]::Escape("datasourceId=`"$dsLeaf`"")) {
    Write-Warning "schema.xml jdbcTable datasourceId does not contain '$dsLeaf' (the -DataSourceUri leaf). If the Domain fails to resolve the table, re-scaffold with --datasource-id $dsLeaf."
}

# PUT the semanticLayerDataSource with the schema.xml EMBEDDED inline (base64),
# mirroring how a reportUnit embeds its jrxml (jrxmlFile). A separate
# pre-upload + schemaFileReference fails 500 because the <Uri>_files child is
# orphaned until the parent Domain exists; the embedded form creates both
# atomically. JRS materializes the schema at <Uri>_files/schema.xml on save.
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $SchemaFile)))
$desc = [ordered]@{
    label       = $Label
    description = $Description
    dataSource  = [ordered]@{ dataSourceReference = [ordered]@{ uri = $DataSourceUri } }
    schema      = [ordered]@{ schemaFile = [ordered]@{ label = "schema.xml"; type = "xml"; content = $b64 } }
}
$df = [IO.Path]::GetTempFileName()
($desc | ConvertTo-Json -Depth 6) | Set-Content $df -Encoding utf8
try {
    $r = Invoke-JrsPut -Jrs $jrs -Uri $Uri -ContentType "application/repository.semanticLayerDataSource+json" -JsonFile $df -Overwrite:$Overwrite
} finally { Remove-Item $df -ErrorAction SilentlyContinue }

if ($r.Code -match '^2\d\d$') {
    Write-Host "OK ($($r.Code)): domain $Uri"
    if ($r.Body) { Write-Host $r.Body }
} else {
    Write-Host "FAILED ($($r.Code))"
    if ($r.Body) { Write-Host $r.Body }
    throw "domain create failed with HTTP $($r.Code)"
}
