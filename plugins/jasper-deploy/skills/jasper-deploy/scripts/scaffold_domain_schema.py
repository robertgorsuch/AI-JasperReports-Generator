#!/usr/bin/env python3
"""Scaffold a JasperReports Server Domain (semantic layer) schema.xml.

A Domain is JRS's semantic layer: a business-friendly view of a datasource that
Ad Hoc views and Domain reports query. It is two repository resources:
  1. a semanticLayerDataSource descriptor (created by create_domain.ps1) that
     references a JDBC datasource + a schema file, and
  2. a schema.xml (this script) describing the tables, their fields, and the
     business "items" exposed to the Ad Hoc designer.

Two modes, both introspecting columns via psql/information_schema:

SINGLE-TABLE (one --table, no --join): the original, verified v1.0 shape:
  <schema><itemGroups><itemGroup resourceId=tableId><items>
     <item id=col resourceId="tableId.col"/></items></itemGroup></itemGroups>
   <resources><jdbcTable id=tableId datasourceId=dsId tableName="sch.tbl">
     <fieldList><field id=col type=javaType/></fieldList></jdbcTable></resources></schema>

MULTI-TABLE (repeat --table, wire with --join): the JRS 10 Domain-Designer
v1.3 shape, reverse-engineered from a live designer-authored domain export --
a join tree ("data island") over plain per-table resources:
  <schema version="1.3">
    <dataIslands><itemGroup id=NAME resourceId=NAME/></dataIslands>
    <dataSources><jdbcDataSource id=dsId><schemaMap>
        <entry key="defaultSchema"><string/></entry>
        <entry key=SCH><string>SCH</string></entry></schemaMap></jdbcDataSource></dataSources>
    <itemGroups>  <!-- one group per table; items resolve THROUGH the island -->
      <itemGroup id=tbl resourceId=NAME><items>
        <item id=col resourceId="NAME.tbl.col"/></items></itemGroup></itemGroups>
    <resources>
      <jdbcTable id=tbl datasourceId=dsId datasourceTableName=tbl schemaAlias=SCH>
        <fieldList><field id=col .../></fieldList></jdbcTable>  <!-- per table -->
      <jdbcTable id=NAME datasourceId=dsId datasourceTableName=<anchor> schemaAlias=SCH>
        <fieldList><field id="tbl.col" .../></fieldList>       <!-- all tables -->
        <joinInfo alias=<anchor> referenceId=<anchor>/>
        <joinList><join expr="a.x == b.y" left=a right=b type=inner weight="1"/></joinList>
        <joinOptions/>
        <tableRefList><tableRef alwaysIncludeTable="false" tableAlias=tbl tableId=tbl/></tableRefList>
      </jdbcTable></resources></schema>
--join syntax: "left_table.col=right_table.col[:inner|left|right|full]"
(inner is the default and the only type verified end-to-end). The anchor table
is the LEFT side of the first join. N tables need at least N-1 joins.

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


JOIN_RE = re.compile(
    r"^(?P<lt>[A-Za-z0-9_.]+)\.(?P<lc>[A-Za-z0-9_]+)"
    r"=(?P<rt>[A-Za-z0-9_.]+)\.(?P<rc>[A-Za-z0-9_]+)"
    r"(?::(?P<type>inner|left|right|full))?$")


def parse_join(spec):
    m = JOIN_RE.match(spec)
    if not m:
        sys.stderr.write(f"Bad --join '{spec}'. Expected left_table.col=right_table.col[:inner|left|right|full]\n")
        sys.exit(2)
    return {"lt": m.group("lt").split(".")[-1], "lc": m.group("lc"),
            "rt": m.group("rt").split(".")[-1], "rc": m.group("rc"),
            "type": m.group("type") or "inner"}


def build_schema_multi(name, ds_id, tables, joins, label):
    """tables: [{'id','schema','cols'}] in CLI order; joins: parse_join dicts.
    Emits the JRS 10 Domain-Designer v1.3 join-tree ('data island') shape."""
    anchor = joins[0]["lt"]
    # every schema alias used, mapped in <schemaMap> (defaultSchema stays empty
    # like the designer emits)
    aliases = []
    for t in tables:
        if t["schema"] not in aliases:
            aliases.append(t["schema"])
    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<schema xmlns="http://www.jaspersoft.com/2007/SL/XMLSchema" version="1.3">',
           '  <dataIslands>',
           f'    <itemGroup id={quoteattr(name)} label={quoteattr(label)} resourceId={quoteattr(name)}></itemGroup>',
           '  </dataIslands>',
           '  <dataSources>',
           f'    <jdbcDataSource id={quoteattr(ds_id)}>',
           '      <schemaMap>',
           '        <entry key="defaultSchema">',
           '          <string></string>',
           '        </entry>']
    for a in aliases:
        out += [f'        <entry key={quoteattr(a)}>',
                f'          <string>{escape(a)}</string>',
                '        </entry>']
    out += ['      </schemaMap>',
            '    </jdbcDataSource>',
            '  </dataSources>',
            '  <itemGroups>']
    # item ids must be GLOBALLY unique across all groups (JRS rejects the schema
    # with domain.schema.presentation.element.name.not.unique otherwise); the
    # designer dedupes by suffixing _1, _2, ... -- do the same, keeping the
    # plain column name as the label.
    used = {}
    for t in tables:
        out.append(f'    <itemGroup id={quoteattr(t["id"])} label={quoteattr(t["id"])} resourceId={quoteattr(name)}>')
        out.append('      <items>')
        for col, _udt in t["cols"]:
            n = used.get(col, 0)
            used[col] = n + 1
            item_id = col if n == 0 else f"{col}_{n}"
            rid = f'{name}.{t["id"]}.{col}'
            out.append(f'        <item id={quoteattr(item_id)} label={quoteattr(col)} resourceId={quoteattr(rid)}></item>')
        out += ['      </items>', '    </itemGroup>']
    out += ['  </itemGroups>', '  <resources>']
    for t in tables:
        out.append(f'    <jdbcTable id={quoteattr(t["id"])} datasourceId={quoteattr(ds_id)} '
                   f'datasourceTableName={quoteattr(t["id"])} schemaAlias={quoteattr(t["schema"])}>')
        out.append('      <fieldList>')
        for col, udt in t["cols"]:
            out.append(f'        <field id={quoteattr(col)} type={quoteattr(java_class(udt))}></field>')
        out += ['      </fieldList>', '    </jdbcTable>']
    # the join tree: one jdbcTable named after the island, anchored on the left
    # table of the first join, carrying every joined table's fields
    out.append(f'    <jdbcTable id={quoteattr(name)} datasourceId={quoteattr(ds_id)} '
               f'datasourceTableName={quoteattr(anchor)} schemaAlias={quoteattr(tables[0]["schema"])}>')
    out.append('      <fieldList>')
    for t in tables:
        for col, udt in t["cols"]:
            out.append(f'        <field id={quoteattr(t["id"] + "." + col)} type={quoteattr(java_class(udt))}></field>')
    out += ['      </fieldList>',
            f'      <joinInfo alias={quoteattr(anchor)} referenceId={quoteattr(anchor)}></joinInfo>',
            '      <joinList>']
    for j in joins:
        expr = f'{j["lt"]}.{j["lc"]} == {j["rt"]}.{j["rc"]}'
        out.append(f'        <join expr={quoteattr(expr)} left={quoteattr(j["lt"])} '
                   f'right={quoteattr(j["rt"])} type={quoteattr(j["type"])} weight="1"></join>')
    out += ['      </joinList>',
            '      <joinOptions></joinOptions>',
            '      <tableRefList>']
    for t in tables:
        out.append(f'        <tableRef alwaysIncludeTable="false" tableAlias={quoteattr(t["id"])} tableId={quoteattr(t["id"])}></tableRef>')
    out += ['      </tableRefList>',
            '    </jdbcTable>',
            '  </resources>',
            '</schema>']
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(
        description="Scaffold a JRS Domain schema.xml: one --table for the "
                    "verified single-table shape, several --table + --join for "
                    "a multi-table (join tree) Domain.")
    ap.add_argument("--name", required=True, help="domain logical id (no spaces); "
                    "in multi-table mode this names the join tree / data island")
    ap.add_argument("--table", required=True, action="append",
                    help="DB table, optionally schema-qualified (e.g. public.product "
                    "or product); repeat for a multi-table Domain")
    ap.add_argument("--join", action="append", default=[],
                    help="join spec left_table.col=right_table.col[:inner|left|right|full]; "
                    "repeat per join (N tables need at least N-1 joins)")
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

    ds_id = args.datasource_id or "JDBCDataSource"
    label = args.label or args.name
    out_path = args.out or f"{args.name}_schema.xml"

    tables = []
    for spec in args.table:
        if "." in spec:
            schema, table = spec.split(".", 1)
        else:
            schema, table = None, spec
        cols = introspect_table(schema, table, args.host, args.port, args.user, args.db)
        tables.append({"id": table, "schema": schema or "public", "cols": cols})

    if len(tables) == 1 and not args.join:
        # single-table: the original, verified v1.0 shape (unchanged)
        table_id = sanitize(args.name)
        xml = build_schema(table_id, ds_id, args.table[0], label, tables[0]["cols"])
        mode = f"table={args.table[0]}"
        nfields = len(tables[0]["cols"])
    else:
        joins = [parse_join(s) for s in args.join]
        if len(joins) < len(tables) - 1:
            sys.stderr.write(f"{len(tables)} tables need at least {len(tables) - 1} "
                             f"--join spec(s); got {len(joins)}\n")
            sys.exit(2)
        known = {t["id"] for t in tables}
        for j in joins:
            for side in ("lt", "rt"):
                if j[side] not in known:
                    sys.stderr.write(f"--join references table '{j[side]}' not in --table list {sorted(known)}\n")
                    sys.exit(2)
        colnames = {t["id"]: {c for c, _u in t["cols"]} for t in tables}
        for j in joins:
            for tside, cside in (("lt", "lc"), ("rt", "rc")):
                if j[cside] not in colnames[j[tside]]:
                    sys.stderr.write(f"--join column {j[tside]}.{j[cside]} not found in that table\n")
                    sys.exit(2)
        xml = build_schema_multi(sanitize(args.name), ds_id, tables, joins, label)
        mode = f"tables={'+'.join(t['id'] for t in tables)}, joins={len(joins)}"
        nfields = sum(len(t["cols"]) for t in tables)

    with open(out_path, "w", encoding="utf-8") as f:
        f.write(xml)
    print(f"OK: scaffolded {out_path} ({mode}, {nfields} fields, datasourceId={ds_id})")
    for t in tables:
        for col, udt in t["cols"]:
            prefix = f"{t['id']}." if len(tables) > 1 else ""
            print(f"    {prefix + col:<34} {udt:<14} -> {java_class(udt)}")


if __name__ == "__main__":
    main()
