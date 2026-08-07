<#
.SYNOPSIS
  Render an HTML file (or a themed HTML body fragment) to a .docx — and optionally a .pdf —
  via Word COM automation, then optionally open it.

.DESCRIPTION
  This is the verified, repeatable pattern used to produce the Jaspersoft_* feature and
  comparison documents in this repo (e.g. Jaspersoft_Commercial_Edition.docx). On Windows it
  drives a hidden Microsoft Word instance to convert HTML with full CSS/table styling fidelity
  (Word must be installed). On macOS/Linux it falls back to LibreOffice headless
  (`soffice --convert-to`) or pandoc — install one of those (`brew install --cask libreoffice`
  or `brew install pandoc`).

  Two input modes:
    -Html <file>       a COMPLETE .html document is converted as-is.
    -BodyHtml <file>   an HTML *fragment* (just the body markup) is wrapped in the standard
                       Actian-navy theme (-Title sets the heading/<title>), then converted —
                       so callers get the consistent house style without repeating the <style> block.

  Output defaults to the input's basename with a .docx extension, alongside the input.

.EXAMPLE
  # Convert a full HTML doc and open it (the pattern used for the feature summaries)
  & make_docx.ps1 -Html Jaspersoft_Commercial_Edition.html -Open

.EXAMPLE
  # Wrap a body fragment in the house theme, emit DOCX + PDF, and open it
  & make_docx.ps1 -BodyHtml summary_body.html -Title "Release Notes" -Pdf -Open

.NOTES
  SaveAs format codes: wdFormatDocumentDefault = 16 (.docx), wdFormatPDF = 17.
  Word COM needs ABSOLUTE paths — the script resolves them. The COM object is always released
  in a finally block so a failed conversion does not leave a WINWORD.EXE running.
#>
[CmdletBinding(DefaultParameterSetName = 'Full')]
param(
  [Parameter(Mandatory = $true, ParameterSetName = 'Full', Position = 0)]
  [string]$Html,

  [Parameter(Mandatory = $true, ParameterSetName = 'Body')]
  [string]$BodyHtml,

  [string]$Title = 'Document',
  [string]$Out,
  [switch]$Pdf,
  [switch]$Open,
  [switch]$KeepHtml
)

$ErrorActionPreference = 'Stop'

# --- standard house theme (matches the Jaspersoft_* document set) -----------------------------
$Template = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>__TITLE__</title>
<style>
  body { font-family: 'Calibri', 'Segoe UI', sans-serif; font-size: 11pt; color: #1a1a1a; line-height: 1.42; }
  h1 { font-family: 'Calibri Light', 'Segoe UI Light', sans-serif; color: #1a3a5c; font-size: 24pt; margin-bottom: 2pt; }
  .subtitle { color: #5a6b7b; font-size: 12pt; margin-top: 0; margin-bottom: 16pt; }
  h2 { color: #1a3a5c; font-size: 15pt; border-bottom: 1.5pt solid #2e6da4; padding-bottom: 3pt; margin-top: 20pt; }
  h3 { color: #2e6da4; font-size: 12.5pt; margin-top: 14pt; margin-bottom: 2pt; }
  ul { margin-top: 4pt; }
  li { margin-bottom: 3pt; }
  table { border-collapse: collapse; width: 100%; margin: 10pt 0; }
  th { background-color: #1a3a5c; color: #ffffff; text-align: left; padding: 6pt 8pt; font-size: 10.5pt; }
  td { border: 0.75pt solid #c8d2dc; padding: 5pt 8pt; font-size: 10.5pt; vertical-align: top; }
  tr:nth-child(even) td { background-color: #eef3f8; }
  code { font-family: 'Consolas', monospace; background-color: #eef1f4; padding: 1pt 3pt; font-size: 10pt; }
  .note { background-color: #f4f8fb; border-left: 3pt solid #2e6da4; padding: 8pt 12pt; margin-top: 14pt; }
  .tier { font-weight: bold; color: #1a3a5c; }
</style>
</head>
<body>
__BODY__
</body>
</html>
'@

# --- resolve the input HTML (wrapping a fragment if needed) -----------------------------------
$tempHtml = $null
if ($PSCmdlet.ParameterSetName -eq 'Body') {
  if (-not (Test-Path $BodyHtml)) { throw "BodyHtml not found: $BodyHtml" }
  $body = Get-Content -Raw -LiteralPath $BodyHtml
  $doc  = $Template.Replace('__TITLE__', $Title).Replace('__BODY__', $body)
  $srcAbs = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetFullPath($BodyHtml), '.wrapped.html')
  Set-Content -LiteralPath $srcAbs -Value $doc -Encoding UTF8
  $tempHtml = $srcAbs
} else {
  if (-not (Test-Path $Html)) { throw "Html not found: $Html" }
  $srcAbs = [System.IO.Path]::GetFullPath($Html)
}

# --- compute outputs --------------------------------------------------------------------------
$inputForName = if ($Html) { $Html } else { $BodyHtml }
$docxAbs = if ($Out) { [System.IO.Path]::GetFullPath($Out) }
           else { [System.IO.Path]::ChangeExtension([System.IO.Path]::GetFullPath($inputForName), '.docx') }
$pdfAbs  = [System.IO.Path]::ChangeExtension($docxAbs, '.pdf')

# --- convert HTML -> DOCX (+ optional PDF) -----------------------------------------------------
# $IsWindows is $null under Windows PowerShell 5.1; `-eq $false` is true ONLY on
# pwsh for macOS/Linux (see _jrs_common.ps1 Test-JrsWindows for the same idiom).
$onWindows = -not ($IsWindows -eq $false)

if ($onWindows) {
  # Word COM: highest CSS/table fidelity. Word must be installed.
  $word = New-Object -ComObject Word.Application
  $word.Visible = $false
  try {
    $d = $word.Documents.Open($srcAbs)
    $d.SaveAs([ref]$docxAbs, [ref]16)          # wdFormatDocumentDefault (.docx)
    if ($Pdf) { $d.SaveAs([ref]$pdfAbs, [ref]17) }  # wdFormatPDF (.pdf)
    $d.Close()
  } finally {
    $word.Quit()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($word)
  }
} else {
  # macOS/Linux: no Word COM. Prefer LibreOffice headless (good CSS/table
  # fidelity), then pandoc. LibreOffice writes <srcbase>.<ext> into --outdir, so
  # rename to the requested $Out when they differ.
  $outDir  = [System.IO.Path]::GetDirectoryName($docxAbs)
  $srcBase = [System.IO.Path]::GetFileNameWithoutExtension($srcAbs)
  $soffice = foreach ($c in @('soffice', 'libreoffice')) { if (Get-Command $c -ErrorAction SilentlyContinue) { $c; break } }
  if ($soffice) {
    & $soffice --headless --convert-to docx --outdir $outDir $srcAbs | Out-Null
    $loDocx = Join-Path $outDir "$srcBase.docx"
    if ($loDocx -ne $docxAbs -and (Test-Path $loDocx)) { Move-Item -Force $loDocx $docxAbs }
    if ($Pdf) {
      & $soffice --headless --convert-to pdf --outdir $outDir $srcAbs | Out-Null
      $loPdf = Join-Path $outDir "$srcBase.pdf"
      if ($loPdf -ne $pdfAbs -and (Test-Path $loPdf)) { Move-Item -Force $loPdf $pdfAbs }
    }
  } elseif (Get-Command pandoc -ErrorAction SilentlyContinue) {
    & pandoc $srcAbs -o $docxAbs | Out-Null
    if ($Pdf) { & pandoc $srcAbs -o $pdfAbs | Out-Null }   # PDF needs a pandoc PDF engine (e.g. weasyprint/wkhtmltopdf)
  } else {
    throw "No HTML->DOCX converter found. Install LibreOffice (brew install --cask libreoffice) or pandoc (brew install pandoc)."
  }
}

if ($tempHtml -and -not $KeepHtml) { Remove-Item -LiteralPath $tempHtml -ErrorAction SilentlyContinue }

# --- report + open ----------------------------------------------------------------------------
if (-not (Test-Path $docxAbs)) { throw "Conversion failed: $docxAbs not created" }
$kb = [math]::Round((Get-Item $docxAbs).Length / 1KB, 1)
Write-Output "Created: $docxAbs  ($kb KB)"
if ($Pdf -and (Test-Path $pdfAbs)) {
  $pkb = [math]::Round((Get-Item $pdfAbs).Length / 1KB, 1)
  Write-Output "Created: $pdfAbs  ($pkb KB)"
}
if ($Open) {
  if ($onWindows)    { Start-Process $docxAbs }
  elseif ($IsMacOS)  { & open $docxAbs }
  else               { & xdg-open $docxAbs }
  Write-Output "Opened: $docxAbs"
}
