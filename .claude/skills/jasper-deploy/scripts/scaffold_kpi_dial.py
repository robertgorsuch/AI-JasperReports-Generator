#!/usr/bin/env python3
"""Scaffold a single-value KPI dial (gauge) report.

Emits a compact JR7-native report with a JFreeChart **meter** (shape="dial").
This is the reliable way to render a gauge: the FusionWidgets angular gauge is
Pro-only and deploys with opaque 400s, whereas the meter is a community chart
that compiles + renders locally. Two hard-won details are baked in:
  * the chart element is SQUARE -> a perfect-circle dial (a non-square element
    renders an ellipse);
  * the value readout is an overlay textField centered in the circle, because the
    meter's own <valueDisplay> does not render reliably.

The query must return ONE row with the numeric metric. Example:
  python scaffold_kpi_dial.py --name gross_margin_dial --title "Gross Margin" \
    --query "SELECT round((SUM(store_sales-store_cost)/SUM(store_sales)*100)::numeric,1) AS v FROM sales_fact_1998" \
    --value-col v --min 0 --max 100 --units % --out report/foodmart/gross_margin_dial.jrxml

Zones default to red/amber/green thirds of [min,max]; override with --zones
"label:#color:lo:hi;...". Deploy with deploy_report.ps1 (bind a datasource).
"""
import argparse


def default_zones(lo, hi):
    span = hi - lo
    a, b = lo + span / 3.0, lo + 2 * span / 3.0
    return [("Low", "#D9534F", lo, a), ("Fair", "#F0AD4E", a, b), ("Good", "#5CB85C", b, hi)]


def parse_zones(s):
    out = []
    for part in s.split(";"):
        if not part.strip():
            continue
        label, color, lo, hi = part.split(":")
        out.append((label, color, float(lo), float(hi)))
    return out


def num(x):
    return str(int(x)) if float(x).is_integer() else str(x)


def main():
    ap = argparse.ArgumentParser(description="Scaffold a single-value KPI dial (meter) report.")
    ap.add_argument("--name", required=True)
    ap.add_argument("--title", required=True)
    ap.add_argument("--subtitle")
    ap.add_argument("--query", required=True, help="SQL returning ONE row with the metric")
    ap.add_argument("--value-col", default="value", help="column alias to read (default 'value')")
    ap.add_argument("--min", type=float, default=0.0)
    ap.add_argument("--max", type=float, default=100.0)
    ap.add_argument("--units", default="%", help="gauge units label (default percent sign); pass 'none' for no units")
    ap.add_argument("--decimals", type=int, default=1)
    ap.add_argument("--tick-count", type=int, default=11)
    ap.add_argument("--zones", help='override: "label:#color:lo:hi;..."')
    ap.add_argument("--no-logo", action="store_true")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    if a.units == "none":   # sentinel for "no units" (empty-string args are awkward in PowerShell)
        a.units = ""
    zones = parse_zones(a.zones) if a.zones else default_zones(a.min, a.max)
    val = a.value_col
    fmt = "#,##0" + ("." + "0" * a.decimals if a.decimals else "")
    suffix = a.units if a.units else ""

    o = []
    o.append('<?xml version="1.0" encoding="UTF-8"?>')
    o.append('<!-- KPI dial (JFreeChart meter, shape="dial"). SQUARE element -> perfect circle;')
    o.append('     value = overlay textField (meter valueDisplay is unreliable). JR7-native. -->')
    o.append(f'<jasperReport name="{a.name}" language="java" pageWidth="400" pageHeight="260" '
             'columnWidth="384" leftMargin="8" rightMargin="8" topMargin="8" bottomMargin="8">')
    o.append(f'\t<query language="SQL"><![CDATA[{a.query}]]></query>')
    o.append(f'\t<field name="{val}" class="java.math.BigDecimal"/>')
    o.append('\t<title height="244">')
    if not a.no_logo:
        o.append('\t\t<element kind="image" x="0" y="0" width="28" height="28" scaleImage="RetainShape" '
                 'hImageAlign="Left" vImageAlign="Top"><expression><![CDATA["repo:/images/actian_logo"]]></expression></element>')
    o.append(f'\t\t<element kind="staticText" x="0" y="0" width="384" height="20" fontSize="12.0" bold="true" '
             f'forecolor="#1F4E79" hTextAlign="Center"><text><![CDATA[{a.title}]]></text></element>')
    if a.subtitle:
        o.append(f'\t\t<element kind="staticText" x="0" y="20" width="384" height="12" fontSize="8.0" '
                 f'forecolor="#5B7DA6" hTextAlign="Center"><text><![CDATA[{a.subtitle}]]></text></element>')
    o.append('\t\t<element kind="chart" chartType="meter" x="82" y="24" width="220" height="220" evaluationTime="Report">')
    o.append('\t\t\t<dataset kind="value">')
    o.append(f'\t\t\t\t<valueExpression><![CDATA[$F{{{val}}}]]></valueExpression>')
    o.append('\t\t\t</dataset>')
    o.append(f'\t\t\t<plot shape="dial" units="{a.units}" tickCount="{a.tick_count}" meterAngle="180" '
             'needleColor="#1F4E79" tickColor="#5B7DA6">')
    o.append(f'\t\t\t\t<dataRange><lowExpression><![CDATA[Double.valueOf({num(a.min)})]]></lowExpression>'
             f'<highExpression><![CDATA[Double.valueOf({num(a.max)})]]></highExpression></dataRange>')
    o.append(f'\t\t\t\t<valueDisplay color="#1F4E79" mask="{fmt}\'{suffix}\'"/>')
    for label, color, lo, hi in zones:
        o.append(f'\t\t\t\t<interval label="{label}" backgroundColor="{color}"><dataRange>'
                 f'<lowExpression><![CDATA[Double.valueOf({num(lo)})]]></lowExpression>'
                 f'<highExpression><![CDATA[Double.valueOf({num(hi)})]]></highExpression></dataRange></interval>')
    o.append('\t\t\t</plot>')
    o.append('\t\t</element>')
    o.append(f'\t\t<element kind="textField" x="82" y="150" width="220" height="24" fontSize="16.0" bold="true" '
             f'forecolor="#1F4E79" hTextAlign="Center" vTextAlign="Middle" evaluationTime="Report">'
             f'<expression><![CDATA[new java.text.DecimalFormat("{fmt}").format($F{{{val}}}) + "{suffix}"]]></expression></element>')
    o.append('\t</title>')
    o.append('</jasperReport>')

    with open(a.out, "w", encoding="utf-8") as f:
        f.write("\n".join(o) + "\n")
    print(f"OK: scaffolded {a.out} (KPI dial '{a.title}', scale {num(a.min)}-{num(a.max)}{a.units}, {len(zones)} zones)")


if __name__ == "__main__":
    main()
