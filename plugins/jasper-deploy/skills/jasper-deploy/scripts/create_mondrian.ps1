<#
.SYNOPSIS
  Create a JasperReports Server OLAP analysis stack via REST v2: upload a Mondrian
  schema, create a secureMondrianConnection over a JDBC datasource, and
  (optionally) an OLAP analysis view (olapUnit) with an MDX query.

.DESCRIPTION
  Three resources make up server-side OLAP:
    * an olapMondrianSchema  -- the Mondrian cube/dimension XML, a file resource
    * a secureMondrianConnection -- binds a JDBC datasource to that schema
      ({dataSource:{dataSourceReference}, schema:{schemaReference}})
    * an olapUnit (optional) -- a saved analysis view: an MDX query against the
      connection ({mdxQuery, olapConnection:{olapConnectionReference}})

  Unlike a Domain (whose schema must be embedded inline), a Mondrian schema is a
  standalone repository resource, so this uploads it first and references it.

  Credentials resolve: params -> JRS_URL/JRS_USER/JRS_PASS -> jrs.config.json.

.PARAMETER Uri            Repository URI for the connection, e.g. /analysis/foodmart.
.PARAMETER SchemaFile     Local Mondrian schema XML.
.PARAMETER DataSourceUri  Existing JDBC datasource the cubes read from.
.PARAMETER SchemaUri      Where to store the schema (default: <Uri>_schema).
.PARAMETER MdxQuery       If set (with -ViewUri), also create an olapUnit analysis view.
.PARAMETER ViewUri        Repository URI for the olapUnit analysis view.

.EXAMPLE
  .\create_mondrian.ps1 -Uri /analysis/foodmart -SchemaFile out\foodmart_schema.xml `
      -DataSourceUri /public/Samples/Data_Sources/FoodmartDataSource -Overwrite `
      -ViewUri /analysis/foodmart_sales `
      -MdxQuery "select {[Measures].[Unit Sales]} on columns, {[Product].[All Products]} on rows from Sales"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Uri,
    [Parameter(Mandatory)][string]$SchemaFile,
    [Parameter(Mandatory)][string]$DataSourceUri,
    [string]$Label,
    [string]$Description = "",
    [string]$SchemaUri,
    [string]$MdxQuery,
    [string]$ViewUri,
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
if (-not $SchemaUri) { $SchemaUri = "${Uri}_schema" }

# 1. upload the Mondrian schema as an olapMondrianSchema file resource
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $SchemaFile)))
$sf = [IO.Path]::GetTempFileName()
([ordered]@{ label = ($SchemaUri -split "/")[-1]; type = "olapMondrianSchema"; content = $b64 } | ConvertTo-Json) | Set-Content $sf -Encoding utf8
try { $sr = Invoke-JrsPut -Jrs $jrs -Uri $SchemaUri -ContentType "application/repository.file+json" -JsonFile $sf -Overwrite:$Overwrite }
finally { Remove-Item $sf -ErrorAction SilentlyContinue }
Assert-JrsOk -Response $sr -Operation "upload schema $SchemaUri failed" | Out-Null
Write-Host "OK ($($sr.Code)): mondrian schema $SchemaUri"

# 2. create the secureMondrianConnection (datasource + schema)
$conn = [ordered]@{
    label       = $Label
    description = $Description
    dataSource  = [ordered]@{ dataSourceReference = [ordered]@{ uri = $DataSourceUri } }
    schema      = [ordered]@{ schemaReference = [ordered]@{ uri = $SchemaUri } }
}
$cf = [IO.Path]::GetTempFileName()
($conn | ConvertTo-Json -Depth 6) | Set-Content $cf -Encoding utf8
try { $cr = Invoke-JrsPut -Jrs $jrs -Uri $Uri -ContentType "application/repository.secureMondrianConnection+json" -JsonFile $cf -Overwrite:$Overwrite }
finally { Remove-Item $cf -ErrorAction SilentlyContinue }
Assert-JrsOk -Response $cr -Operation "create connection $Uri failed" | Out-Null
Write-Host "OK ($($cr.Code)): mondrian connection $Uri"

# 3. optional OLAP analysis view (olapUnit) with an MDX query
if ($MdxQuery) {
    if (-not $ViewUri) { throw "-MdxQuery requires -ViewUri (where to save the analysis view)" }
    if (-not $ViewUri.StartsWith("/")) { $ViewUri = "/$ViewUri" }
    $view = [ordered]@{
        label = ($ViewUri -split "/")[-1]; description = "$Label analysis view"
        mdxQuery = $MdxQuery
        olapConnection = [ordered]@{ olapConnectionReference = [ordered]@{ uri = $Uri } }
    }
    $vf = [IO.Path]::GetTempFileName()
    ($view | ConvertTo-Json -Depth 6) | Set-Content $vf -Encoding utf8
    try { $vr = Invoke-JrsPut -Jrs $jrs -Uri $ViewUri -ContentType "application/repository.olapUnit+json" -JsonFile $vf -Overwrite:$Overwrite }
    finally { Remove-Item $vf -ErrorAction SilentlyContinue }
    if ($vr.Code -match '^2\d\d$') {
        Write-Host "OK ($($vr.Code)): olap analysis view $ViewUri"
    } else {
        # Best-effort: creating an olapUnit OPENS the connection and validates the
        # MDX against the cube, so it 500s unless the schema actually parses against
        # the live DB (the schema's tables/columns + datasource must match). The
        # schema + connection above are created regardless; fix the schema/DB to
        # enable the view.
        Write-Warning "olap view $ViewUri NOT created (HTTP $($vr.Code)) -- the connection must open + the MDX must resolve against the live cube. Schema + connection were created. $($vr.Body)"
    }
}
