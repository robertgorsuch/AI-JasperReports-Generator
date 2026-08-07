# Pester 3.x/4.x (legacy `Should Be` syntax; CI installs Pester 4 for pwsh)
# tests for scripts\lint_jrxml.ps1. Each test writes a temporary fixture to the
# platform temp dir, runs the linter against it (capturing all streams +
# $LASTEXITCODE), then removes the fixture.

$script:Linter = "$PSScriptRoot/../scripts/lint_jrxml.ps1"

function Invoke-Linter($file) {
    $out = & $script:Linter -Path $file *>&1
    [pscustomobject]@{ Output = ($out | Out-String); Exit = $LASTEXITCODE }
}

Describe "lint_jrxml.ps1" {

    It "flags a .jrtx with isDefault true (exit 1, jrtx-default-attr)" {
        $f = Join-Path ([IO.Path]::GetTempPath())("lint_jrtx_{0}.jrtx" -f ([guid]::NewGuid().ToString('N')))
        @'
<?xml version="1.0" encoding="UTF-8"?>
<jasperTemplate>
  <style name="Base" isDefault="true" forecolor="#000000"/>
</jasperTemplate>
'@ | Set-Content -LiteralPath $f -Encoding ASCII
        try {
            $r = Invoke-Linter $f
            $r.Exit   | Should Be 1
            $r.Output | Should Match 'jrtx-default-attr'
        } finally { Remove-Item $f -ErrorAction SilentlyContinue }
    }

    It "flags an area chart plot with tick props (exit 1, areaplot-plot-props)" {
        $f = Join-Path ([IO.Path]::GetTempPath())("lint_area_{0}.jrxml" -f ([guid]::NewGuid().ToString('N')))
        @'
<?xml version="1.0" encoding="UTF-8"?>
<jasperReport name="r">
  <summary>
    <band height="200">
      <element kind="chart" chartType="area">
        <plot showTickMarks="true"/>
      </element>
    </band>
  </summary>
</jasperReport>
'@ | Set-Content -LiteralPath $f -Encoding ASCII
        try {
            $r = Invoke-Linter $f
            $r.Exit   | Should Be 1
            $r.Output | Should Match 'areaplot-plot-props'
        } finally { Remove-Item $f -ErrorAction SilentlyContinue }
    }

    It "passes a clean minimal .jrxml (exit 0)" {
        $f = Join-Path ([IO.Path]::GetTempPath())("lint_clean_{0}.jrxml" -f ([guid]::NewGuid().ToString('N')))
        @'
<?xml version="1.0" encoding="UTF-8"?>
<jasperReport name="clean">
  <detail>
    <band height="20">
      <element kind="staticText"/>
    </band>
  </detail>
</jasperReport>
'@ | Set-Content -LiteralPath $f -Encoding ASCII
        try {
            $r = Invoke-Linter $f
            $r.Exit | Should Be 0
        } finally { Remove-Item $f -ErrorAction SilentlyContinue }
    }
}
