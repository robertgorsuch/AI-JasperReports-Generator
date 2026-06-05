#!/usr/bin/env python3
"""Synthesize a JasperReports Server dashboard import archive from a manifest.

JRS 10 dashboards cannot be composed by PUTting a model to /rest_v2/resources
(the server stores it but the client renders it blank). The *supported* path is
export/import: the designer's own export archive re-imports and renders
identically. This script generates a byte-compatible export archive
programmatically -- the dashboard descriptor (.xml) plus the three companion
files the designer produces (components.data / layout / wiring.data) -- so a
dashboard can be composed from a manifest and imported with import_resource.ps1,
no designer needed.

The model shape was reverse-engineered from a real designer export (every field
below matches what the JRS 10 designer writes). The dashlets (reportUnits) must
already be deployed; they are referenced by repository URI.

Manifest (JSON):
{
  "folder": "/reports/foodmart",          # repository folder to hold the dashboard
  "name":   "foodmart_kpi_dashboard",      # resource name (no spaces)
  "label":  "Foodmart KPI Dashboard",      # display label
  "dashlets": [                            # one per deployed report, placed on a 40-wide grid
    {"resource": "/reports/foodmart/foodmart_yoy_sales",
     "label": "Year-over-Year Sales (1997 vs 1998)",
     "x": 0, "y": 0, "width": 22, "height": 10},
    ...
  ]
}

Emits a .zip ready for import_resource.ps1. With --auto-grid, dashlet x/y/width/
height are computed automatically (two columns) when omitted.
"""
import argparse
import json
import os
import re
import sys
import zipfile
from datetime import datetime, timezone


def component_id(label: str) -> str:
    """Designer rule: every non-alphanumeric char in the label -> '_'."""
    return re.sub(r"[^0-9A-Za-z]", "_", label)


def iso_now() -> str:
    # local time with offset, milliseconds -- matches the designer's format
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="milliseconds")


# --- the three companion files ----------------------------------------------
def build_components(dashlets) -> str:
    props = {
        "id": "DashboardProperties", "type": "dashboardProperties",
        "name": "DashboardProperties", "autoRefresh": False,
        "refreshInterval": 5, "refreshIntervalUnit": "minute",
        "showDashletBorders": True, "showExportButton": False,
        "showPrintButton": False, "dashletMargin": 5, "dashletPadding": 5,
        "dashletFilterShowPopup": False, "useFixedSize": False,
        "fixedWidth": 1280, "fixedHeight": 800, "canvasColor": "#ffffff",
        "titleBarColor": "rgba(0, 0, 0, 0)", "titleTextColor": "#454545",
    }
    arr = [props]
    for d in dashlets:
        cid = component_id(d["label"])
        arr.append({
            "type": "reportUnit", "label": d["label"], "resource": d["resource"],
            "exposeOutputsToFilterManager": False, "dashletHyperlinkTarget": "",
            "id": cid, "name": d["label"], "scaleToFit": "width",
            "autoRefresh": False, "refreshInterval": 5,
            "refreshIntervalUnit": "minute", "showTitleBar": True,
            "showExportButton": False, "showPrintButton": False,
            "showRefreshButton": False, "showMaximizeButton": True,
            "showBackButton": True, "dataSourceUri": d["resource"],
            "showVizSelectorIcon": False, "outputParameters": [],
            "parameters": [], "showVizSelector": False,
        })
    return json.dumps(arr, separators=(",", ":"))


def build_layout(dashlets) -> str:
    divs = []
    for d in dashlets:
        cid = component_id(d["label"])
        divs.append(
            f"<div data-componentId='{cid}' data-x='{d['x']}' data-y='{d['y']}' "
            f"data-width='{d['width']}' data-height='{d['height']}'></div>"
        )
    return "".join(divs)


def build_wiring(dashlets) -> str:
    def event(name):
        return {
            "name": name, "producer": f"DashboardProperties:{name}",
            "component": "DashboardProperties",
            "consumers": [{"consumer": f"{component_id(d['label'])}:"
                           + ("@refresh" if name == "@init" else "@applyParams")}
                          for d in dashlets],
        }
    return json.dumps([event("@init"), event("@applyParams")],
                      separators=(",", ":"))


# --- archive descriptors -----------------------------------------------------
def build_descriptor(folder, name, label, dashlets, ts) -> str:
    files_folder = f"{folder}/{name}_files"
    rds = "".join(
        f"    <resourceDescriptor>\n        <type>reportUnit</type>\n"
        f"        <id>{d['resource']}</id>\n    </resourceDescriptor>\n"
        for d in dashlets)
    res_uris = "".join(
        f"    <resource>\n        <uri>{d['resource']}</uri>\n    </resource>\n"
        for d in dashlets)

    def local(data_file, rname, ftype, xsitype, ver):
        return (
            f"    <resource>\n"
            f"        <localResource\n"
            f'            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"\n'
            f'            exportedWithPermissions="false" dataFile="{data_file}" '
            f'xsi:type="{xsitype}">\n'
            f"            <folder>{files_folder}</folder>\n"
            f"            <name>{rname}</name>\n"
            f"            <version>{ver}</version>\n"
            f"            <label>{rname}</label>\n"
            f"            <creationDate>{ts}</creationDate>\n"
            f"            <updateDate>{ts}</updateDate>\n"
            f"            <fileType>{ftype}</fileType>\n"
            f"        </localResource>\n"
            f"    </resource>\n")

    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<dashboardModelResource exportedWithPermissions="true">\n'
        f"    <folder>{folder}</folder>\n"
        f"    <name>{name}</name>\n"
        f"    <version>0</version>\n"
        f"    <label>{label}</label>\n"
        f"    <creationDate>{ts}</creationDate>\n"
        f"    <updateDate>{ts}</updateDate>\n"
        "    <defaultFoundation>default</defaultFoundation>\n"
        "    <foundation>\n"
        "        <id>default</id>\n"
        "        <layout>layout</layout>\n"
        "        <wiring>wiring</wiring>\n"
        "        <components>components</components>\n"
        "    </foundation>\n"
        "    <resourceDescriptor>\n        <type>wiring</type>\n        <id>wiring</id>\n    </resourceDescriptor>\n"
        "    <resourceDescriptor>\n        <type>layout</type>\n        <id>layout</id>\n    </resourceDescriptor>\n"
        "    <resourceDescriptor>\n        <type>components</type>\n        <id>components</id>\n    </resourceDescriptor>\n"
        f"{rds}"
        + local("wiring.data", "wiring", "json", "fileResource", 1)
        + local("layout", "layout", "html", "contentResource", 2)
        + local("components.data", "components", "dashboardComponent", "fileResource", 1)
        + res_uris
        + "</dashboardModelResource>\n"
    )


def build_folder_xml(path, ts) -> str:
    """A repository folder descriptor (.folder.xml) for `path`."""
    parent = path.rsplit("/", 1)[0] or "/"
    nm = path.rsplit("/", 1)[1]
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<folder exportedWithPermissions="true">\n'
        f"    <parent>{parent}</parent>\n"
        f"    <name>{nm}</name>\n"
        f"    <label>{nm}</label>\n"
        f"    <creationDate>{ts}</creationDate>\n"
        f"    <updateDate>{ts}</updateDate>\n"
        "</folder>\n"
    )


def ancestor_folders(folder):
    """['/reports', '/reports/foodmart'] for folder='/reports/foodmart'."""
    parts = [p for p in folder.split("/") if p]
    return ["/" + "/".join(parts[: i + 1]) for i in range(len(parts))]


def build_index(folder, name) -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        "<export>"
        '<module id="repositoryResources">'
        f"<resource>{folder}/{name}</resource>"
        "</module>"
        '<module id="favorites"/>'
        '<property name="pathProcessorId" value="zip"/>'
        '<property name="rootTenantId" value="organizations"/>'
        "</export>\n"
    )


def main():
    ap = argparse.ArgumentParser(description="Synthesize a JRS dashboard import archive.")
    ap.add_argument("--manifest", required=True, help="dashboard manifest JSON")
    ap.add_argument("--out", required=True, help="output .zip path")
    ap.add_argument("--auto-grid", action="store_true",
                    help="compute x/y/width/height for any dashlet missing them (2 columns)")
    args = ap.parse_args()

    with open(args.manifest, encoding="utf-8-sig") as f:  # tolerate a UTF-8 BOM
        m = json.load(f)
    folder = m["folder"].rstrip("/")
    name = m["name"]
    label = m.get("label", name)
    dashlets = m["dashlets"]
    if not dashlets:
        sys.stderr.write("ERROR: manifest has no dashlets\n")
        sys.exit(2)

    # normalize: a dashlet may be specified as {resource,label} (compose-only)
    # or as {name,title} (the unified build+compose manifest) -- derive the
    # repository URI and display label from name/title + the dashboard folder.
    for d in dashlets:
        d.setdefault("resource", f"{folder}/{d['name']}" if "name" in d else None)
        if not d.get("resource"):
            sys.stderr.write(f"ERROR: dashlet needs 'resource' or 'name': {d}\n")
            sys.exit(2)
        d.setdefault("label", d.get("title") or d["resource"].rsplit("/", 1)[-1])

    if args.auto_grid:
        # two-column 40-wide grid; each tile 20 wide, 10 tall, stacked
        for i, d in enumerate(dashlets):
            d.setdefault("width", 20)
            d.setdefault("height", 10)
            d.setdefault("x", 20 if i % 2 else 0)
            d.setdefault("y", (i // 2) * 10)
    missing = [d.get("label", "?") for d in dashlets
               if any(k not in d for k in ("x", "y", "width", "height"))]
    if missing:
        sys.stderr.write("ERROR: these dashlets lack x/y/width/height "
                         f"(use --auto-grid): {missing}\n")
        sys.exit(2)

    ts = iso_now()
    base = f"resources{folder}/{name}"
    files_base = f"resources{folder}/{name}_files"
    entries = {
        "index.xml": build_index(folder, name),
        f"{base}.xml": build_descriptor(folder, name, label, dashlets, ts),
        f"{files_base}/components.data": build_components(dashlets),
        f"{files_base}/layout": build_layout(dashlets),
        f"{files_base}/wiring.data": build_wiring(dashlets),
    }
    # the folder chain that holds the dashboard must be described or the import
    # broker silently no-ops (reports referenced by URI are resolved in the repo)
    for fpath in ancestor_folders(folder):
        entries[f"resources{fpath}/.folder.xml"] = build_folder_xml(fpath, ts)

    os.makedirs(os.path.dirname(os.path.abspath(args.out)) or ".", exist_ok=True)
    with zipfile.ZipFile(args.out, "w", zipfile.ZIP_DEFLATED) as z:
        for arcname, content in entries.items():
            z.writestr(arcname, content)

    print(f"OK: wrote {args.out} ({len(dashlets)} dashlets) for {folder}/{name}")
    for d in dashlets:
        print(f"    [{d['x']:>2},{d['y']:>2} {d['width']}x{d['height']}] "
              f"{component_id(d['label']):<40} {d['resource']}")


if __name__ == "__main__":
    main()
