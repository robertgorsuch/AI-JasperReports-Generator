#!/usr/bin/env python3
"""
extract_lineage.py -- Jaspersoft metadata & lineage extractor (read-only).

Crawls a JasperReports Server (JRS) repository over the REST v2 API and emits a
catalog-style asset inventory plus asset-level lineage edges. This is the
Phase-1 MVP slice of the connector spec'd in
JASPERSOFT_CATALOG_CONNECTOR_PDD.md: inventory + asset-level lineage with a
best-effort SQL source-table parse.

Standard library plus the OPTIONAL sqlglot package (the only non-stdlib
dependency). When sqlglot is importable, each reportUnit's SQL is parsed into an
AST to resolve report fields to source table.column(s) -- column-level lineage
with confidence "exact" (1:1 column projection) or "derived" (expression /
aggregate fan-in). When sqlglot is absent or a query fails to parse, the crawl
falls back to the regex table-level extraction (confidence "inferred"). ASCII
output only.

OUTPUT FORMATS (--format)
  - internal (default): {assets:[...], edges:[...]} JSON + sibling assets.csv /
    edges.csv. Edges now include report->column field-level edges.
  - openlineage: OpenLineage-style RunEvents JSON (jobs = reports, output
    datasets carry a columnLineage facet, inputs = source tables) to --out.

  --dialect sets the sqlglot SQL dialect (default 'postgres').

WHAT IT DOES
  - GET /rest_v2/resources?recursive=true under --folder, paginated (limit/offset),
    collecting every resource as an asset {uri, type, label, description,
    updateDate, datasource}.
  - For each reportUnit: fetch the typed descriptor, capture its datasource
    reference, fetch the JRXML (jrxmlFileReference child OR inline base64
    content) and parse it with xml.etree to collect the <queryString> text +
    language, every <field name>, and every <parameter name>. Best-effort
    source-table extraction from SQL via FROM/JOIN regex (confidence "parsed";
    falls back to "inferred" when a subquery/derived table is detected).
  - For each semanticLayerDataSource (Domain): capture the bound datasource.
  - For each dashboard: read its companion 'components' file and extract the
    repository URIs it references (reports / ad hoc topics).
  - Builds edges:
        report    -> datasource   (resolved)
        report    -> domain        (resolved; when the bound DS is a Domain or
                                    the query language is 'domain')
        report    -> source-table  (parsed | inferred)
        domain    -> datasource    (resolved)
        dashboard -> report        (resolved)
  - Emits --out (lineage.json) = {assets:[...], edges:[...]} plus sibling
    assets.csv and edges.csv. Prints a summary with counts by asset type,
    edge count, and skip count.

CREDENTIAL / SERVER RESOLUTION (first match wins)
  1. CLI flags          --server / --user / --password
  2. Environment        JRS_URL / JRS_USER / JRS_PASS
  3. Skill config       ../jrs.config.json  (serverUrl / user / password)
  4. Defaults           http://localhost:8081/jasperserver-pro, superuser/superuser
  HTTP Basic auth on every call. All operations are GET (read-only).

USAGE
  # Crawl the bundled samples, write to a temp file:
  python extract_lineage.py --folder /public/Samples \
         --out C:\\Users\\me\\AppData\\Local\\Temp\\lineage_test.json

  # Crawl the whole repository with explicit credentials:
  python extract_lineage.py --server http://localhost:8081/jasperserver-pro \
         --user superuser --password superuser --folder / --out lineage.json

  # Use env vars:
  set JRS_URL=http://host:8081/jasperserver-pro & set JRS_USER=svc & set JRS_PASS=secret
  python extract_lineage.py --folder /reports
"""

import argparse
import base64
import csv
import datetime
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
import xml.etree.ElementTree as ET

# Optional column-level lineage backend. sqlglot is the ONLY non-stdlib
# dependency and it is strictly optional: if it is not importable the crawl
# transparently falls back to the regex table-level extraction (confidence
# "inferred"). See extract_column_lineage() / run().
try:
    import sqlglot
    from sqlglot import exp as sqlglot_exp
    from sqlglot.optimizer.scope import build_scope as sqlglot_build_scope
except Exception:  # pragma: no cover - exercised only when sqlglot absent
    sqlglot = None
    sqlglot_exp = None
    sqlglot_build_scope = None

DEFAULT_SERVER = "http://localhost:8081/jasperserver-pro"
DEFAULT_DIALECT = "postgres"
PAGE_LIMIT = 100

# Resource types that the descriptor parser treats specially.
DOMAIN_TYPE = "semanticLayerDataSource"
REPORT_TYPE = "reportUnit"
DATASOURCE_TYPES = (
    "jdbcDataSource", "jndiJdbcDataSource", "beanDataSource",
    "customDataSource", "virtualDataSource", "awsDataSource",
)

# SQL keywords that must never be mistaken for a table name after FROM/JOIN.
_SQL_NOISE = {
    "select", "where", "group", "order", "having", "union", "on", "as",
    "inner", "left", "right", "outer", "full", "cross", "join", "lateral",
}


# --------------------------------------------------------------------------- #
# Configuration / credential resolution
# --------------------------------------------------------------------------- #
def resolve_config(args):
    """Resolve server/user/password: CLI -> env -> jrs.config.json -> defaults."""
    server = args.server or os.environ.get("JRS_URL")
    user = args.user or os.environ.get("JRS_USER")
    password = args.password if args.password is not None else os.environ.get("JRS_PASS")

    if not (server and user and password is not None):
        cfg_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "jrs.config.json")
        cfg_path = os.path.normpath(cfg_path)
        if os.path.isfile(cfg_path):
            try:
                with open(cfg_path, "r") as fh:
                    cfg = json.load(fh)
                server = server or cfg.get("serverUrl")
                user = user or cfg.get("user")
                if password is None:
                    password = cfg.get("password")
            except Exception as exc:
                sys.stderr.write("WARN: could not read %s: %s\n" % (cfg_path, exc))

    server = server or DEFAULT_SERVER
    user = user or "superuser"
    password = "superuser" if password is None else password
    return server.rstrip("/"), user, password


# --------------------------------------------------------------------------- #
# HTTP client
# --------------------------------------------------------------------------- #
class JrsClient(object):
    def __init__(self, server, user, password):
        self.base = server + "/rest_v2"
        token = base64.b64encode(("%s:%s" % (user, password)).encode("utf-8")).decode("ascii")
        self.auth = "Basic " + token

    def get(self, path, accept="application/json"):
        """GET base+path. Returns (status, body_bytes, content_type)."""
        url = self.base + path
        req = urllib.request.Request(url)
        req.add_header("Authorization", self.auth)
        req.add_header("Accept", accept)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return resp.status, resp.read(), resp.headers.get("Content-Type", "")
        except urllib.error.HTTPError as exc:
            return exc.code, exc.read() if hasattr(exc, "read") else b"", ""
        except Exception as exc:
            raise

    def get_json(self, path, accept="application/json"):
        status, body, _ = self.get(path, accept)
        if status == 204 or not body:
            return status, None
        return status, json.loads(body.decode("utf-8", "replace"))


def enc(uri):
    """Encode a repository URI for use in a path, preserving slashes."""
    return urllib.parse.quote(uri, safe="/")


# --------------------------------------------------------------------------- #
# Crawl
# --------------------------------------------------------------------------- #
def crawl(client, folder):
    """Paginated recursive listing -> list of resourceLookup dicts."""
    assets = []
    offset = 0
    while True:
        q = "/resources?folderUri=%s&recursive=true&limit=%d&offset=%d" % (
            enc(folder), PAGE_LIMIT, offset)
        status, data = client.get_json(q)
        if status != 200 or not data:
            break
        page = data.get("resourceLookup", [])
        if not page:
            break
        assets.extend(page)
        if len(page) < PAGE_LIMIT:
            break
        offset += PAGE_LIMIT
    return assets


# --------------------------------------------------------------------------- #
# JRXML / SQL parsing
# --------------------------------------------------------------------------- #
def _local(tag):
    return tag.split("}")[-1] if "}" in tag else tag


def parse_jrxml(xml_bytes):
    """Parse JRXML bytes. Returns dict with queries, fields, parameters.

    queries: list of {language, text}. Matched by local element name so the
    JasperReports default namespace does not interfere.
    """
    root = ET.fromstring(xml_bytes)
    queries = []
    fields = []
    parameters = []
    for el in root.iter():
        name = _local(el.tag)
        if name == "queryString":
            lang = el.attrib.get("language") or "sql"
            text = (el.text or "").strip()
            queries.append({"language": lang, "text": text})
        elif name == "field":
            fn = el.attrib.get("name")
            if fn:
                fields.append(fn)
        elif name == "parameter":
            pn = el.attrib.get("name")
            if pn:
                parameters.append(pn)
    return {"queries": queries, "fields": fields, "parameters": parameters}


def extract_source_tables(sql):
    """Best-effort source-table extraction from a SQL string.

    Returns a list of (table, confidence) where confidence is "parsed" for a
    plain identifier following FROM/JOIN, or "inferred" when the SQL contains a
    derived table / subquery in a FROM/JOIN position (so the table set may be
    incomplete or aliased). Not a full SQL parse -- see PDD Sec. 10.
    """
    if not sql:
        return []
    # Normalize parameter tokens ($P{x}, $P!{x}, $X{...}) so they do not break
    # the regex; they are bind points, not tables.
    cleaned = re.sub(r"\$[PXR]!?\{[^}]*\}", " ", sql)
    inferred = bool(re.search(r"(?:FROM|JOIN)\s*\(", cleaned, re.IGNORECASE))
    tables = []
    seen = set()
    for m in re.finditer(r"\b(?:FROM|JOIN)\s+([A-Za-z_][\w$]*(?:\.[A-Za-z_][\w$]*)*)",
                         cleaned, re.IGNORECASE):
        tbl = m.group(1)
        if tbl.lower() in _SQL_NOISE:
            continue
        key = tbl.lower()
        if key in seen:
            continue
        seen.add(key)
        tables.append((tbl, "inferred" if inferred else "parsed"))
    return tables


# --------------------------------------------------------------------------- #
# Column-level lineage (sqlglot AST). Optional -- returns None to signal that
# the caller should fall back to the regex table-level extractor.
# --------------------------------------------------------------------------- #
def _normalize_params(sql):
    """Replace Jaspersoft bind/clause tokens ($P{}, $P!{}, $X{}, $R{}) with a
    benign literal so the SQL parser does not choke on them."""
    return re.sub(r"\$[PXR]!?\{[^}]*\}", " '__JP__' ", sql or "")


def _table_fullname(table):
    """Dotted physical name for a sqlglot exp.Table: [catalog.][db.]name."""
    parts = []
    for key in ("catalog", "db"):
        val = table.text(key)
        if val:
            parts.append(val)
    if table.name:
        parts.append(table.name)
    return ".".join(parts)


def extract_column_lineage(sql, fields, dialect):
    """Resolve report fields to source table.column(s) via a sqlglot AST walk.

    Returns a tuple (tables, col_edges) or None.

      tables    -- list of physical table full-names referenced anywhere in the
                   query (CTE names excluded). Drives table-level edges with
                   AST confidence "parsed".
      col_edges -- list of (field, "table.column", confidence) where confidence
                   is "exact" for a 1:1 column projection or "derived" when the
                   projected value is an expression/aggregate (one edge per
                   contributing column).

    None is returned when sqlglot is unavailable or the query fails to parse, so
    the caller can fall back to the regex table-level extractor (confidence
    "inferred"). Never raises on malformed SQL.
    """
    if sqlglot is None or not sql:
        return None
    cleaned = _normalize_params(sql)
    try:
        tree = sqlglot.parse_one(cleaned, read=dialect)
    except Exception:
        return None
    if tree is None:
        return None
    exp = sqlglot_exp

    # CTE aliases are logical names, not physical tables -- exclude them.
    cte_names = set()
    try:
        for cte in tree.find_all(exp.CTE):
            if cte.alias:
                cte_names.add(cte.alias.lower())
    except Exception:
        return None

    # Physical tables across every scope (subqueries included).
    tables = []
    seen_t = set()
    for tbl in tree.find_all(exp.Table):
        if not tbl.name or tbl.name.lower() in cte_names:
            continue
        full = _table_fullname(tbl)
        if not full or full.lower() in seen_t:
            continue
        seen_t.add(full.lower())
        tables.append(full)

    # Column resolution against the outermost SELECT scope.
    col_edges = []
    try:
        root = sqlglot_build_scope(tree)
    except Exception:
        root = None
    select = tree.find(exp.Select)
    if root is not None and select is not None:
        # alias/table -> physical full-name for this scope's direct sources.
        src_map = {}
        single = None
        n_tables = 0
        for name, source in root.sources.items():
            if isinstance(source, exp.Table):
                full = _table_fullname(source)
                src_map[name.lower()] = full
                src_map.setdefault(source.name.lower(), full)
                single = full
                n_tables += 1
        field_set = set((f or "").lower() for f in (fields or []))
        for proj in select.selects:
            out_name = proj.alias_or_name
            if not out_name:
                continue
            if field_set and out_name.lower() not in field_set:
                continue
            core = proj.this if isinstance(proj, exp.Alias) else proj
            cols = list(proj.find_all(exp.Column))
            if not cols:
                continue
            exact = isinstance(core, exp.Column) and len(cols) == 1
            conf = "exact" if exact else "derived"
            for col in cols:
                qualifier = (col.table or "").lower()
                colname = col.name
                if not colname:
                    continue
                if qualifier:
                    tbl = src_map.get(qualifier)
                    if tbl is None:
                        # Qualifier points at a subquery/derived alias -- cannot
                        # resolve to a physical column without schema. Skip.
                        continue
                elif n_tables == 1:
                    tbl = single
                else:
                    # Unqualified column with >1 source: ambiguous, skip.
                    continue
                col_edges.append((out_name, "%s.%s" % (tbl, colname), conf))
    return tables, col_edges


# --------------------------------------------------------------------------- #
# Reference helpers
# --------------------------------------------------------------------------- #
def ref_uri(node):
    """Pull a repository URI out of a descriptor reference node."""
    if not isinstance(node, dict):
        return None
    for key in ("dataSourceReference", "jrxmlFileReference", "resourceReference",
                "schemaFileReference", "reference"):
        sub = node.get(key)
        if isinstance(sub, dict) and sub.get("uri"):
            return sub["uri"]
    if node.get("uri"):
        return node["uri"]
    return None


def fetch_jrxml(client, descriptor):
    """Return JRXML bytes for a reportUnit descriptor (child file or inline)."""
    jrxml = descriptor.get("jrxml")
    if not isinstance(jrxml, dict):
        return None
    uri = ref_uri(jrxml)
    if uri:
        status, body, _ = client.get(enc_path(uri), "application/xml")
        if status == 200 and body:
            return body
        return None
    # Inline content (base64) under jrxmlFile.content or content.
    inline = jrxml.get("jrxmlFile") if isinstance(jrxml.get("jrxmlFile"), dict) else jrxml
    content = inline.get("content") if isinstance(inline, dict) else None
    if content:
        try:
            return base64.b64decode(content)
        except Exception:
            return content.encode("utf-8", "replace")
    return None


def enc_path(uri):
    return "/resources" + enc(uri)


# Repository-URI shapes seen in dashboard companion files.
_URI_RE = re.compile(r"(?:repo:)?(/(?:public|organizations|reports|datasources|temp)/[A-Za-z0-9_./%-]+)")


def dashboard_referenced_uris(client, descriptor):
    """Read a dashboard's 'components' companion file and return referenced URIs."""
    refs = set()
    for res in descriptor.get("resources", []) or []:
        if not isinstance(res, dict):
            continue
        if res.get("type") != "components":
            continue
        comp_uri = ref_uri(res.get("resource") or {})
        if not comp_uri:
            continue
        try:
            status, body, _ = client.get(enc_path(comp_uri), "application/json")
        except Exception:
            continue
        if status != 200 or not body:
            continue
        txt = body.decode("utf-8", "replace")
        for m in _URI_RE.finditer(txt):
            uri = m.group(1)
            # Skip the dashboard's own companion files.
            if "_files/" in uri:
                continue
            refs.add(uri)
    return sorted(refs)


# --------------------------------------------------------------------------- #
# Main extraction
# --------------------------------------------------------------------------- #
def run(client, folder, dialect=DEFAULT_DIALECT):
    raw = crawl(client, folder)

    assets = []
    edges = []
    skips = []
    domain_uris = set()

    # First pass: base asset records + index of domain URIs.
    by_uri = {}
    for r in raw:
        uri = r.get("uri")
        rtype = r.get("resourceType")
        rec = {
            "uri": uri,
            "type": rtype,
            "label": r.get("label"),
            "description": r.get("description"),
            "updateDate": r.get("updateDate"),
            "datasource": None,
        }
        assets.append(rec)
        by_uri[uri] = rec
        if rtype == DOMAIN_TYPE:
            domain_uris.add(uri)

    edge_seen = set()

    def add_edge(src, tgt, etype, confidence, detail=""):
        if not src or not tgt:
            return
        key = (src, tgt, etype, detail)
        if key in edge_seen:
            return
        edge_seen.add(key)
        edges.append({
            "source": src, "target": tgt, "type": etype,
            "confidence": confidence, "detail": detail,
        })

    # Second pass: per-resource deep parse. Wrapped so one bad resource cannot
    # abort the crawl.
    for rec in assets:
        uri = rec["uri"]
        rtype = rec["type"]
        try:
            if rtype == REPORT_TYPE:
                status, desc = client.get_json(
                    enc_path(uri), "application/repository.reportUnit+json")
                if status != 200 or not desc:
                    skips.append((uri, "reportUnit descriptor status %s" % status))
                    continue
                ds_uri = ref_uri(desc.get("dataSource") or {})
                rec["datasource"] = ds_uri
                if ds_uri:
                    if ds_uri in domain_uris:
                        add_edge(uri, ds_uri, "report->domain", "resolved")
                    else:
                        add_edge(uri, ds_uri, "report->datasource", "resolved")

                xml_bytes = fetch_jrxml(client, desc)
                if xml_bytes:
                    parsed = parse_jrxml(xml_bytes)
                    rec["fields"] = sorted(set(parsed["fields"]))
                    rec["parameters"] = sorted(set(parsed["parameters"]))
                    langs = set()
                    for q in parsed["queries"]:
                        langs.add(q["language"])
                        ql = q["language"].lower()
                        if ql.startswith("sql"):
                            col_lin = extract_column_lineage(
                                q["text"], rec.get("fields"), dialect)
                            if col_lin is None:
                                # sqlglot missing or parse failed: regex fallback,
                                # tagged "inferred" (lower confidence, no AST).
                                for tbl, _conf in extract_source_tables(q["text"]):
                                    add_edge(uri, tbl, "report->table",
                                             "inferred", "source-table")
                            else:
                                tables, col_edges = col_lin
                                for tbl in tables:
                                    add_edge(uri, tbl, "report->table",
                                             "parsed", "source-table")
                                for fname, target, cconf in col_edges:
                                    add_edge(uri, target, "report->column",
                                             cconf, "field:%s" % fname)
                        elif ql.startswith("domain"):
                            # Domain-language query: the bound DS is the domain.
                            if ds_uri:
                                add_edge(uri, ds_uri, "report->domain", "resolved",
                                         "domain-query")
                    rec["queryLanguages"] = sorted(langs)
                else:
                    skips.append((uri, "jrxml not retrievable"))

            elif rtype == DOMAIN_TYPE:
                status, desc = client.get_json(
                    enc_path(uri), "application/repository.semanticLayerDataSource+json")
                if status != 200 or not desc:
                    skips.append((uri, "domain descriptor status %s" % status))
                    continue
                ds_uri = ref_uri(desc.get("dataSource") or {})
                rec["datasource"] = ds_uri
                add_edge(uri, ds_uri, "domain->datasource", "resolved")

            elif rtype == "dashboard":
                status, desc = client.get_json(
                    enc_path(uri), "application/repository.dashboard+json")
                if status != 200 or not desc:
                    skips.append((uri, "dashboard descriptor status %s" % status))
                    continue
                for ref in dashboard_referenced_uris(client, desc):
                    add_edge(uri, ref, "dashboard->report", "resolved")

        except Exception as exc:
            skips.append((uri, "%s: %s" % (type(exc).__name__, exc)))

    return assets, edges, skips


# --------------------------------------------------------------------------- #
# Output
# --------------------------------------------------------------------------- #
def write_outputs(out_path, assets, edges):
    out_dir = os.path.dirname(os.path.abspath(out_path))
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir)

    with open(out_path, "w") as fh:
        json.dump({"assets": assets, "edges": edges}, fh, indent=2)

    base = os.path.splitext(out_path)[0]
    assets_csv = os.path.join(out_dir, "assets.csv")
    edges_csv = os.path.join(out_dir, "edges.csv")

    with open(assets_csv, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["uri", "type", "label", "description", "updateDate", "datasource"])
        for a in assets:
            w.writerow([a.get("uri"), a.get("type"), a.get("label"),
                        a.get("description"), a.get("updateDate"), a.get("datasource")])

    with open(edges_csv, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["source", "target", "type", "confidence", "detail"])
        for e in edges:
            w.writerow([e["source"], e["target"], e["type"],
                        e["confidence"], e["detail"]])

    return assets_csv, edges_csv


_PRODUCER = "jasper-deploy/extract_lineage.py"
_CL_SCHEMA = ("https://openlineage.io/spec/facets/1-0-1/"
              "ColumnLineageDatasetFacet.json")


def build_openlineage(assets, edges, server):
    """Build OpenLineage-style RunEvents (one per reportUnit).

    Each report is a job; its output dataset carries a columnLineage facet
    mapping report fields to source table.columns, and inputs list the source
    tables. Namespaces: reports under the server URL, source tables under the
    report's bound datasource URI. Returns a list of event dicts.
    """
    jrs_ns = server
    now = (datetime.datetime.now(datetime.timezone.utc)
           .replace(microsecond=0, tzinfo=None).isoformat() + "Z")

    table_by_report = {}
    cols_by_report = {}
    for e in edges:
        src = e["source"]
        if e["type"] == "report->table":
            table_by_report.setdefault(src, []).append(e["target"])
        elif e["type"] == "report->column":
            detail = e.get("detail") or ""
            field = detail[6:] if detail.startswith("field:") else detail
            tbl, _, col = e["target"].rpartition(".")
            cols_by_report.setdefault(src, {}).setdefault(field, []).append(
                (tbl, col, e["confidence"]))

    events = []
    for a in assets:
        if a["type"] != REPORT_TYPE:
            continue
        uri = a["uri"]
        ds_ns = a.get("datasource") or "jaspersoft:unknown"

        inputs = []
        seen_in = set()
        for tbl in table_by_report.get(uri, []):
            if tbl in seen_in:
                continue
            seen_in.add(tbl)
            inputs.append({"namespace": ds_ns, "name": tbl, "facets": {}})

        fields_facet = {}
        for field, srcs in cols_by_report.get(uri, {}).items():
            in_fields = []
            seen_f = set()
            for tbl, col, conf in srcs:
                key = (tbl, col)
                if key in seen_f:
                    continue
                seen_f.add(key)
                in_fields.append({
                    "namespace": ds_ns,
                    "name": tbl,
                    "field": col,
                    "transformations": [{
                        "type": "DIRECT" if conf == "exact" else "INDIRECT",
                        "subtype": conf,
                    }],
                })
            fields_facet[field] = {"inputFields": in_fields}

        out_facets = {}
        if fields_facet:
            out_facets["columnLineage"] = {
                "_producer": _PRODUCER,
                "_schemaURL": _CL_SCHEMA,
                "fields": fields_facet,
            }
        outputs = [{"namespace": jrs_ns, "name": uri, "facets": out_facets}]

        events.append({
            "eventType": "COMPLETE",
            "eventTime": a.get("updateDate") or now,
            "producer": _PRODUCER,
            "run": {"runId": str(uuid.uuid5(uuid.NAMESPACE_URL, jrs_ns + uri))},
            "job": {"namespace": jrs_ns, "name": uri},
            "inputs": inputs,
            "outputs": outputs,
        })
    return events


def write_openlineage(out_path, events):
    out_dir = os.path.dirname(os.path.abspath(out_path))
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir)
    with open(out_path, "w") as fh:
        json.dump(events, fh, indent=2)


def summarize(assets, edges, skips):
    counts = {}
    for a in assets:
        counts[a["type"]] = counts.get(a["type"], 0) + 1
    type_str = ", ".join("%s=%d" % (k, counts[k]) for k in sorted(counts))
    etypes = {}
    for e in edges:
        etypes[e["type"]] = etypes.get(e["type"], 0) + 1
    col_n = etypes.get("report->column", 0)
    edge_str = ", ".join("%s=%d" % (k, etypes[k]) for k in sorted(etypes))
    return ("assets=%d (%s) | edges=%d [%s] | column-edges=%d | skipped=%d"
            % (len(assets), type_str, len(edges), edge_str, col_n, len(skips)))


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Extract Jaspersoft metadata + asset-level lineage (read-only).")
    parser.add_argument("--server", help="JRS base URL (default from config/env).")
    parser.add_argument("--user", help="JRS user (default from config/env).")
    parser.add_argument("--password", help="JRS password (default from config/env).")
    parser.add_argument("--folder", default="/", help="Root repository folder to crawl (default '/').")
    parser.add_argument("--out", default="lineage.json", help="Output JSON path (default lineage.json).")
    parser.add_argument("--dialect", default=DEFAULT_DIALECT,
                        help="SQL dialect for sqlglot column parsing (default 'postgres').")
    parser.add_argument("--format", default="internal",
                        choices=("internal", "openlineage"),
                        help="Output format: 'internal' (assets/edges JSON + CSVs) "
                             "or 'openlineage' (RunEvents JSON). Default 'internal'.")
    args = parser.parse_args(argv)

    server, user, password = resolve_config(args)
    if sqlglot is None:
        sys.stderr.write("WARN: sqlglot not importable; column-level lineage "
                         "disabled, falling back to regex table extraction.\n")
    sys.stderr.write("Crawling %s under %s ...\n" % (server, args.folder))
    client = JrsClient(server, user, password)

    assets, edges, skips = run(client, args.folder, args.dialect)

    if args.format == "openlineage":
        events = build_openlineage(assets, edges, server)
        write_openlineage(args.out, events)
        print(summarize(assets, edges, skips))
        print("Format: openlineage | runEvents=%d" % len(events))
        print("Wrote: %s" % os.path.abspath(args.out))
    else:
        assets_csv, edges_csv = write_outputs(args.out, assets, edges)
        print(summarize(assets, edges, skips))
        print("Wrote: %s" % os.path.abspath(args.out))
        print("       %s" % assets_csv)
        print("       %s" % edges_csv)
    if skips:
        sys.stderr.write("Skipped %d resource(s):\n" % len(skips))
        for uri, reason in skips[:20]:
            sys.stderr.write("  %s -- %s\n" % (uri, reason))
        if len(skips) > 20:
            sys.stderr.write("  ... and %d more\n" % (len(skips) - 20))
    return 0


if __name__ == "__main__":
    sys.exit(main())
