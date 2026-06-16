#!/usr/bin/env python3
"""Scaffold a JasperReports Server Domain (semantic layer) schema.xml.

A Domain is JRS's semantic layer: a business-friendly view of a datasource that
Ad Hoc views and Domain reports query. It is two repository resources:
  1. a semanticLayerDataSource descriptor (created by create_domain.ps1) that
     references a JDBC datasource + a schema file, and
  2. a schema.xml (this script) describing the tables, their fields, and the
     business "items" exposed to the Ad Hoc designer.

This generates a SINGLE-TABLE Domain (no joins) by introspecting one table's
columns via psql/information_schema -- the reliable, fully-scripted case. A
multi-table Domain (joinInfo/joinedDataSetList) is authored in the Domain
Designer and promoted with export_resource.ps1 / import_resource.ps1.

Schema shape (namespace http://www.jaspersoft.com/2007/SL/XMLSchema):
  <schema><itemGroups><itemGroup resourceId=tableId><items>
     <item id=col resourceId="tableId.col"/></items></itemGroup></itemGroups>
   <resources><jdbcTable id=tableId datasourceId=dsId tableName="sch.tbl">
     <fieldList><field id=col type=javaType/></fieldList></jdbcTable></resources></schema>

psql must be on PATH; the DB password is read from PGPASSWORD.
"""
import argparse
import csv
import io
import re
import subprocess
import sys
from xml.sax.saxutils import escape, quoteattr

# reuse the exact PostgreSQL->Java type mapping the report scaffolder uses
from scaffold_jrxml import java_class


def sanitize(s: str) -> str:
    return re.sub(r"[^0-9A-Za-z_]", "_", s)


def _sqllit(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def introspect_table(schema, table, host, port, user, db):
    """Return [(column_name, udt_name), ...] for schema.table, in column order."""
    where = f"table_name = {_sqllit(table)}"
    if schema:
        where += f" AND table_schema = {_sqllit(schema)}"
    # feed via stdin (-f -) like scaffold_jrxml; \copy interpolation of :'var'
    # does NOT apply inside the meta-command, so embed quoted literals directly.
    script = (r"\copy (SELECT column_name, udt_name FROM information_schema.columns "
              f"WHERE {where} ORDER BY ordinal_position) TO STDOUT WITH (FORMAT csv)" + "\n")
    cmd = ["psql", "-h", host, "-p", str(port), "-U", user, "-d", db,
           "-v", "ON_ERROR_STOP=1", "-q", "-X", "-f", "-"]
    proc = subprocess.run(cmd, input=script, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write("psql introspection failed:\n" + proc.stderr + "\n")
        sys.exit(2)
    cols = [(r[0], r[1]) for r in csv.reader(io.StringIO(proc.stdout)) if len(r) >= 2]
    if not cols:
        sys.stderr.write(f"No columns found for table {schema or ''}.{table}\n")
        sys.exit(2)
    return cols


def build_schema(table_id, ds_id, table_name, label, cols):
    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<schema xmlns="http://www.jaspersoft.com/2007/SL/XMLSchema" version="1.0">',
           '  <itemGroups>',
           f'    <itemGroup id={quoteattr(table_id)} label={quoteattr(label)} '
           f'description={quoteattr(label)} descriptionId="" labelId="" '
           f'resourceId={quoteattr(table_id)}>',
           '      <items>']
    for col, _udt in cols:
        rid = f"{table_id}.{col}"
        out.append(f'        <item id={quoteattr(col)} label={quoteattr(col)} '
                   f'description={quoteattr(col)} descriptionId="" labelId="" '
                   f'resourceId={quoteattr(rid)} />')
    out += ['      </items>',
            '    </itemGroup>',
            '  </itemGroups>',
            '  <resources>',
            f'    <jdbcTable id={quoteattr(table_id)} datasourceId={quoteattr(ds_id)} '
            f'tableName={quoteattr(table_name)}>',
            '      <fieldList>']
    for col, udt in cols:
        out.append(f'        <field id={quoteattr(col)} type={quoteattr(java_class(udt))} />')
    out += ['      </fieldList>',
            '    </jdbcTable>',
            '  </resources>',
            '</schema>']
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(description="Scaffold a single-table JRS Domain schema.xml.")
    ap.add_argument("--name", required=True, help="domain/table logical id (no spaces)")
    ap.add_argument("--table", required=True,
                    help="DB table, optionally schema-qualified (e.g. public.product or product)")
    ap.add_argument("--datasource-id", help="datasourceId used inside the schema "
                    "(default: the --datasource-uri leaf, set by create_domain.ps1; "
                    "if omitted here, defaults to 'JDBCDataSource')")
    ap.add_argument("--label", help="itemGroup label (default: --name)")
    ap.add_argument("--out", help="output schema.xml path (default: <name>_schema.xml)")
    ap.add_argument("--db", default="postgis_34_sample")
    ap.add_argument("--host", default="localhost")
    ap.add_argument("--port", default="5432")
    ap.add_argument("--user", default="postgres")
    args = ap.parse_args()

    if "." in args.table:
        schema, table = args.table.split(".", 1)
    else:
        schema, table = None, args.table
    cols = introspect_table(schema, table, args.host, args.port, args.user, args.db)

    table_id = sanitize(args.name)
    ds_id = args.datasource_id or "JDBCDataSource"
    # JRS addresses the table by its DB name; keep the schema prefix if given
    table_name = args.table
    label = args.label or args.name
    xml = build_schema(table_id, ds_id, table_name, label, cols)

    out_path = args.out or f"{args.name}_schema.xml"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(xml)
    print(f"OK: scaffolded {out_path} (table={args.table}, {len(cols)} fields, "
          f"datasourceId={ds_id})")
    for col, udt in cols:
        print(f"    {col:<28} {udt:<14} -> {java_class(udt)}")


if __name__ == "__main__":
    main()
