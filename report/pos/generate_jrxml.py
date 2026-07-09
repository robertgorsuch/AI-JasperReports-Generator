#!/usr/bin/env python3
"""
Generate JasperReports jrxml files from SQL queries for POS dashboard
"""
import json
import re
import sys
from pathlib import Path

def read_sql_file(filepath):
    """Read SQL from file"""
    with open(filepath, 'r') as f:
        return f.read().strip()

def extract_columns_from_sql(sql_text):
    """Extract column names from SELECT statement"""
    # Remove comments
    sql_clean = re.sub(r'--.*?$', '', sql_text, flags=re.MULTILINE)

    # Find SELECT to FROM
    select_match = re.search(r'SELECT\s+(.*?)\s+FROM', sql_clean, re.DOTALL | re.IGNORECASE)
    if not select_match:
        return []

    select_part = select_match.group(1)

    # Split by comma but handle nested parentheses
    columns = []
    current = ''
    paren_level = 0

    for char in select_part:
        if char == '(':
            paren_level += 1
        elif char == ')':
            paren_level -= 1
        elif char == ',' and paren_level == 0:
            col = current.strip()
            if col:
                columns.append(col)
            current = ''
            continue
        current += char

    if current.strip():
        columns.append(current.strip())

    # Extract alias or column name
    result = []
    for col_expr in columns:
        # Try to find AS alias
        as_match = re.search(r'\s+AS\s+(\w+)', col_expr, re.IGNORECASE)
        if as_match:
            col_name = as_match.group(1).lower()
        else:
            # Take the last identifier
            identifiers = re.findall(r'\b(\w+)\b', col_expr)
            if identifiers:
                col_name = identifiers[-1].lower()
            else:
                continue

        col_type = infer_column_type(col_name)
        result.append({'name': col_name, 'type': col_type})

    return result

def infer_column_type(col_name):
    """Infer data type from column name"""
    col_lower = col_name.lower()
    if any(x in col_lower for x in ['sales', 'price', 'cost', 'value', 'amount']):
        return 'java.math.BigDecimal'
    elif any(x in col_lower for x in ['count', 'units', 'transactions', 'customers', 'transaction']):
        return 'java.lang.Integer'
    elif any(x in col_lower for x in ['date', 'time']):
        return 'java.util.Date'
    elif any(x in col_lower for x in ['flag', 'boolean']):
        return 'java.lang.Boolean'
    else:
        return 'java.lang.String'

def generate_jrxml(report_name, report_title, sql_file):
    """Generate a basic jrxml file for a report"""

    # Read SQL
    sql_text = read_sql_file(sql_file)

    # Extract columns
    columns = extract_columns_from_sql(sql_text)

    if not columns:
        print(f"    [WARNING] No columns found in {sql_file}")
        return None

    # Limit to 6 columns for display
    display_columns = columns[:6]

    # Calculate column width
    col_width = int(802 / len(display_columns)) if display_columns else 133

    # Build field definitions
    fields_xml = '\n  '.join([
        f'<field name="{col["name"]}" class="{col["type"]}"/>'
        for col in display_columns
    ])

    # Build column headers
    headers_xml = ''
    for i, col in enumerate(display_columns):
        x = i * col_width
        col_label = col['name'].replace('_', ' ').title()
        headers_xml += f'''  <staticText>
    <reportElement x="{x}" y="0" width="{col_width}" height="20" uuid="uuid{i+3}"/>
    <box>
      <pen lineWidth="1.0"/>
      <topPen lineWidth="1.0"/>
      <leftPen lineWidth="1.0"/>
      <bottomPen lineWidth="1.0"/>
      <rightPen lineWidth="1.0"/>
    </box>
    <textElement textAlignment="Center" verticalAlignment="Middle">
      <font isBold="true" size="10"/>
    </textElement>
    <text><![CDATA[{col_label}]]></text>
  </staticText>
'''

    # Build detail row
    detail_xml = ''
    for i, col in enumerate(display_columns):
        x = i * col_width
        align = "Right" if col["type"] in ['java.math.BigDecimal', 'java.lang.Integer'] else "Left"
        detail_xml += f'''  <textField isBlankWhenNull="true">
    <reportElement x="{x}" y="0" width="{col_width}" height="20" uuid="uuid{i+100+3}"/>
    <box>
      <pen lineWidth="0.5"/>
      <topPen lineWidth="0.5"/>
      <leftPen lineWidth="0.5"/>
      <bottomPen lineWidth="0.5"/>
      <rightPen lineWidth="0.5"/>
    </box>
    <textElement textAlignment="{align}" verticalAlignment="Middle">
      <font size="9"/>
    </textElement>
    <textFieldExpression><![CDATA[$F{{{col['name']}}}]]></textFieldExpression>
  </textField>
'''

    jrxml = f'''<?xml version="1.0" encoding="UTF-8"?>
<jasperReport xmlns="http://jasperreports.sourceforge.net/jasperreports/print" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://jasperreports.sourceforge.net/jasperreports/print http://jasperreports.sourceforge.net/xsd/jasperreport.xsd" name="{report_name}" pageWidth="842" pageHeight="595" columnWidth="802" leftMargin="20" rightMargin="20" topMargin="20" bottomMargin="20" uuid="a1b2c3d4-e5f6-47a8-9b0c-1d2e3f4a5b6c">
  <property name="com.jaspersoft.studio.data.sql.tables" value=""/>
  <queryString language="SQL">
    <![CDATA[{sql_text}]]>
  </queryString>
  {fields_xml}
  <background/>
  <title>
    <band height="50">
      <staticText>
        <reportElement x="0" y="0" width="802" height="30" uuid="uuid1"/>
        <textElement textAlignment="Center" verticalAlignment="Middle">
          <font size="18" isBold="true"/>
        </textElement>
        <text><![CDATA[{report_title}]]></text>
      </staticText>
      <staticText>
        <reportElement x="0" y="30" width="802" height="15" uuid="uuid2"/>
        <textElement textAlignment="Center" verticalAlignment="Middle">
          <font size="9" isItalic="true"/>
        </textElement>
        <text><![CDATA[POS Analytics Dashboard]]></text>
      </staticText>
    </band>
  </title>
  <columnHeader>
    <band height="20">
{headers_xml}  </band>
  </columnHeader>
  <detail>
    <band height="20">
{detail_xml}  </band>
  </detail>
  <pageFooter>
    <band height="20">
      <textField>
        <reportElement x="700" y="0" width="102" height="20" uuid="uuid9999"/>
        <textElement textAlignment="Right" verticalAlignment="Middle"/>
        <textFieldExpression><![CDATA["Page " + $V{{PAGE_NUMBER}} + " of " + $V{{PAGE_COUNT}}]]></textFieldExpression>
      </textField>
    </band>
  </pageFooter>
</jasperReport>
'''

    return jrxml

def main():
    # Load manifest
    manifest_path = Path('report/pos/dashboard.json')
    with open(manifest_path) as f:
        manifest = json.load(f)

    outdir = Path(manifest['outDir'])
    outdir.mkdir(parents=True, exist_ok=True)

    print(f"Generating jrxml files in {outdir}...")

    for dashlet in manifest['dashlets']:
        if dashlet['kind'] != 'report':
            continue

        report_name = dashlet['name']
        report_title = dashlet['title']
        query_file = dashlet.get('queryFile')

        if not query_file:
            print(f"  Skipping {report_name} - no queryFile")
            continue

        print(f"  Generating {report_name}...")

        jrxml_content = generate_jrxml(report_name, report_title, query_file)

        if not jrxml_content:
            continue

        jrxml_path = outdir / f'{report_name}.jrxml'
        with open(jrxml_path, 'w') as f:
            f.write(jrxml_content)

        print(f"    [OK] Created {jrxml_path}")

    print("\nAll jrxml files generated successfully!")
    return 0

if __name__ == '__main__':
    sys.exit(main())
