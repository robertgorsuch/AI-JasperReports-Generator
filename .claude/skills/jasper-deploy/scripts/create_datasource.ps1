<#
.SYNOPSIS
  Create (or update) a datasource on JasperReports Server via REST v2.
  Supports JDBC (default) plus the JNDI / bean / custom / virtual types.

.DESCRIPTION
  PUTs the matching application/repository.<type>DataSource+json descriptor to
  /rest_v2/resources, creating intermediate folders. Reports deployed by
  deploy_report.ps1 reference a datasource by its repository URI
  (-DataSourceUri). For JDBC, the target DB's JDBC driver must be on the JRS
  server classpath (the PostgreSQL driver ships with JasperReports Server).

  NOTE: creating a non-JDBC datasource validates the DESCRIPTOR SHAPE and stores
  the resource (201); actually CONNECTING needs the server-side prerequisite
  (a JNDI resource in the app server, a Spring bean on the classpath, a custom
  data-source service, or -- for virtual -- the referenced sub-datasources).

  Server URL and credentials resolve the same way as deploy_report.ps1:
    1. -ServerUrl / -User / -Password parameters
    2. environment variables JRS_URL / JRS_USER / JRS_PASS
    3. jrs.config.json in the skill root (gitignored)

.PARAMETER Uri
  Repository URI for the datasource, e.g. /datasources/postgis_34_sample.

.PARAMETER Type
  Datasource type: jdbc (default) | jndi | bean | custom | virtual.

.PARAMETER Label
  Human-readable label. Defaults to the last URI segment.

.PARAMETER ConnectionUrl
  (jdbc) Full JDBC URL. If omitted, built from -DbHost/-DbPort/-Database.

.PARAMETER JndiName
  (jndi) JNDI resource name, e.g. jdbc/foodmart.

.PARAMETER BeanName / BeanMethod
  (bean) Spring bean id and the method returning the JDBC datasource/connection.

.PARAMETER ServiceClass / Properties
  (custom) the data-source service class and a @{key=value} property map.

.PARAMETER SubDataSources
  (virtual) ordered @{alias='/datasources/uri'} map of member datasources; each
  alias becomes a schema prefix in the virtual (Teiid) datasource.

.EXAMPLE
  .\create_datasource.ps1 -Uri /datasources/postgis_34_sample `
      -Label "PostGIS 34 Sample" -Database postgis_34_sample `
      -DbUser postgres -DbPassword postgres
.EXAMPLE
  # JNDI datasource
  .\create_datasource.ps1 -Type jndi -Uri /datasources/foodmart_jndi -JndiName jdbc/foodmart
.EXAMPLE
  # virtual datasource joining two existing JDBC datasources
  .\create_datasource.ps1 -Type virtual -Uri /datasources/combined `
      -SubDataSources ([ordered]@{ fm='/public/Samples/Data_Sources/FoodmartDataSource'; pg='/datasources/postgis_34_sample' })
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [ValidateSet("jdbc", "jndi", "bean", "custom", "virtual")][string]$Type = "jdbc",
    [string]$Label,
    [string]$Description = "",
    # jdbc
    [string]$ConnectionUrl,
    [string]$DriverClass = "org.postgresql.Driver",
    [string]$DbHost = "localhost",
    [int]$DbPort = 5432,
    [string]$Database = "postgis_34_sample",
    [string]$DbUser = "postgres",
    [string]$DbPassword = "postgres",
    # jndi
    [string]$JndiName,
    # bean
    [string]$BeanName,
    [string]$BeanMethod,
    # custom
    [string]$ServiceClass,
    [hashtable]$Properties,
    # virtual
    [System.Collections.IDictionary]$SubDataSources,
    [switch]$Overwrite,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")

# --- resolve config (param -> env -> jrs.config.json, validated) ----------
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password
if (-not $Uri.StartsWith("/")) { $Uri = "/$Uri" }
if (-not $Label) { $Label = ($Uri -split "/")[-1] }

# --- build the type-specific descriptor + media type ----------------------
switch ($Type) {
    "jdbc" {
        if (-not $ConnectionUrl) { $ConnectionUrl = "jdbc:postgresql://${DbHost}:${DbPort}/${Database}" }
        $contentType = "application/repository.jdbcDataSource+json"
        $desc = [ordered]@{
            label = $Label; description = $Description
            driverClass = $DriverClass; connectionUrl = $ConnectionUrl
            username = $DbUser; password = $DbPassword
        }
        Write-Host "(jdbc driver=$DriverClass)"
    }
    "jndi" {
        if (-not $JndiName) { throw "-Type jndi requires -JndiName (e.g. jdbc/foodmart)" }
        $contentType = "application/repository.jndiJdbcDataSource+json"
        $desc = [ordered]@{ label = $Label; description = $Description; jndiName = $JndiName }
        Write-Host "(jndi name=$JndiName)"
    }
    "bean" {
        if (-not $BeanName) { throw "-Type bean requires -BeanName" }
        $contentType = "application/repository.beanDataSource+json"
        $desc = [ordered]@{ label = $Label; description = $Description; beanName = $BeanName }
        if ($BeanMethod) { $desc.beanMethod = $BeanMethod }
        Write-Host "(bean name=$BeanName)"
    }
    "custom" {
        if (-not $ServiceClass) { throw "-Type custom requires -ServiceClass" }
        $contentType = "application/repository.customDataSource+json"
        $desc = [ordered]@{ label = $Label; description = $Description; serviceClass = $ServiceClass }
        if ($Properties) {
            $desc.properties = @(foreach ($k in $Properties.Keys) { [ordered]@{ key = "$k"; value = "$($Properties[$k])" } })
        }
        Write-Host "(custom serviceClass=$ServiceClass)"
    }
    "virtual" {
        if (-not $SubDataSources -or $SubDataSources.Count -eq 0) {
            throw "-Type virtual requires -SubDataSources @{alias='/datasources/uri';..}"
        }
        $contentType = "application/repository.virtualDataSource+json"
        $subs = @(foreach ($alias in $SubDataSources.Keys) {
            [ordered]@{ id = "$alias"; uri = "$($SubDataSources[$alias])" }
        })
        $desc = [ordered]@{ label = $Label; description = $Description; subDataSources = $subs }
        Write-Host "(virtual subDataSources=$($SubDataSources.Count))"
    }
}

# --- PUT to REST v2 ------------------------------------------------------
# -Overwrite updates the datasource IN PLACE via ?overwrite=true (no delete -- a
# datasource referenced by reports can't be deleted, and a plain re-PUT hits
# JRS optimistic locking with 409 "versions not match").
$jsonFile = [IO.Path]::GetTempFileName()
($desc | ConvertTo-Json -Depth 6) | Set-Content -Path $jsonFile -Encoding utf8
try {
    $r = Invoke-JrsPut -Jrs $jrs -Uri $Uri -Overwrite:$Overwrite `
        -ContentType $contentType -JsonFile $jsonFile
} finally {
    Remove-Item $jsonFile -ErrorAction SilentlyContinue
}

if ($r.Code -match '^2\d\d$') {
    Write-Host "OK ($($r.Code)): datasource $Uri"
    if ($r.Body) { Write-Host $r.Body }
} else {
    Write-Host "FAILED ($($r.Code))"
    if ($r.Body) { Write-Host $r.Body }
    throw "datasource create failed with HTTP $($r.Code)"
}
