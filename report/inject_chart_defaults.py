#!/usr/bin/env python3
"""Inject defaultValueExpression into the JR Library 'charts' sample parameters
so they render with data when run from the JRS UI (the samples otherwise rely on
the Java harness to supply MaxOrderID etc., and render blank without it).

Reads the charts sample jrxml, adds defaults to self-closing <parameter> tags
that lack one, and writes copies under output/charts_defaulted/charts/reports/
(a regenerable work dir) for deploy_jr_samples.ps1 to deploy.
"""
import os, re, glob

SRC = r"C:\Users\rgorsuch\jasperreports-7.0.6\demo\samples\charts\reports"
OUT = r"C:\Users\rgorsuch\tx-geocoder\output\charts_defaulted\charts\reports"
os.makedirs(OUT, exist_ok=True)

# literal default value expressions (Java) per parameter name
DEFAULTS = {
    "MaxOrderID": "11077",            # max OrderID in the demo data -> all orders
    "ChartFreightThreshold": "100.0",
    "Country": '"USA"',
}

def inject(text, name, expr):
    # only transform a self-closing <parameter name="NAME" .../> (no existing default)
    pat = re.compile(r'<parameter name="' + re.escape(name) + r'"([^>]*?)/>')
    repl = ('<parameter name="' + name + r'"\1>'
            '<defaultValueExpression><![CDATA[' + expr + ']]></defaultValueExpression>'
            '</parameter>')
    return pat.sub(repl, text)

n = 0
for path in glob.glob(os.path.join(SRC, "*.jrxml")):
    base = os.path.splitext(os.path.basename(path))[0]
    text = open(path, encoding="utf-8").read()
    for name, expr in DEFAULTS.items():
        text = inject(text, name, expr)
    # ReportTitle default = the report's base name
    text = inject(text, "ReportTitle", '"' + base + '"')
    open(os.path.join(OUT, base + ".jrxml"), "w", encoding="utf-8").write(text)
    n += 1

print(f"wrote {n} defaulted chart jrxml to {OUT}")
