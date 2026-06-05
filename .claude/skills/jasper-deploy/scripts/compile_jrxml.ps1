<#
.SYNOPSIS
  Compile a JasperReports 7 .jrxml to .jasper, validating it against the JR7 engine.

.DESCRIPTION
  Uses JDK 11+ single-file source launch (no separate javac step) to run
  CompileReport.java against the JasperReports 7.0.6 runtime classpath.
  A clean compile is also the fastest validation that the jrxml is JR7-valid
  before deploying it to JasperReports Server.

.PARAMETER Jrxml
  Path to the .jrxml file to compile.

.PARAMETER LibDir
  Folder containing the JasperReports 7 jars. Defaults to the machine build.

.EXAMPLE
  .\compile_jrxml.ps1 -Jrxml ..\..\report\my_report.jrxml
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Jrxml,
    [string]$LibDir          # default resolves via env JR_LIB_DIR / jrs.config jrLibDir
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")

if (-not (Test-Path $Jrxml)) { throw "jrxml not found: $Jrxml" }
$jrxmlFull = (Resolve-Path $Jrxml).Path
Write-Host "Compiling $jrxmlFull ..."

$res = Invoke-JrCompile -Jrxml $jrxmlFull -LibDir $LibDir -PassThru
if (-not $res.Ok) {
    Write-Host $res.Output
    throw "compilation failed: $jrxmlFull (no .jasper produced)"
}
Write-Host "OK: $($res.Jasper)"
