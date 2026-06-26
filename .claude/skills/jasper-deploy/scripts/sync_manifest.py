#!/usr/bin/env python3
"""Rebuild a build_dashlets/compose manifest from a LIVE dashboard export.

When a dashboard is rearranged in the JRS designer, the compose manifest goes
stale and a recompose would revert the hand edits. This reads the dashboard's
export archive (layout + components.data + descriptor) and writes a manifest
whose dashlets match the live tile positions/sizes, so a subsequent
compose_dashboard.ps1 reproduces the live layout.

Usage: sync_manifest.py --zip <export.zip> --out <manifest.json>
(normally called by sync_manifest_from_dashboard.ps1, which does the export).
"""
import argparse
import json
import re
import zipfile


def attr(blob, name):
    m = re.search(name + r"='([^']*)'", blob) or re.search(name + r'="([^"]*)"', blob)
    return m.group(1) if m else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zip", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    z = zipfile.ZipFile(args.zip)
    names = z.namelist()
    layout_path = next((n for n in names if n.endswith("_files/layout")), None)
    if not layout_path:
        raise SystemExit("ERROR: no dashboard layout found in the export (is the URI a dashboard?)")
    base = layout_path[: -len("_files/layout")]          # resources/<folder>/<name>
    uri = base[len("resources"):]                        # /<folder>/<name>
    folder, name = uri.rsplit("/", 1)

    layout = z.read(layout_path).decode("utf-8", "ignore")
    components = json.loads(z.read(base + "_files/components.data").decode("utf-8", "ignore"))
    desc = z.read(base + ".xml").decode("utf-8", "ignore") if (base + ".xml") in names else ""
    mlab = re.search(r"<label>(.*?)</label>", desc, re.S)
    label = mlab.group(1).strip() if mlab else name

    by_id = {c.get("id"): c for c in components if isinstance(c, dict)}

    dashlets = []
    for blob in re.findall(r"<div\b([^>]*)>\s*</div>", layout):
        cid = attr(blob, "data-componentId")
        if not cid:
            continue
        pos = {"x": int(attr(blob, "data-x") or 0), "y": int(attr(blob, "data-y") or 0),
               "width": int(attr(blob, "data-width") or 1), "height": int(attr(blob, "data-height") or 1)}
        c = by_id.get(cid, {})
        t = c.get("type")
        if t == "reportUnit":
            d = {"resource": c.get("resource"),
                 "label": c.get("name") or c.get("label") or cid,
                 "showTitleBar": bool(c.get("showTitleBar", False))}
        elif t == "text":
            d = {"kind": "text", "name": cid, "text": c.get("text", "")}
            for src, dst in (("size", "size"), ("alignment", "align"), ("bold", "bold"),
                             ("italic", "italic"), ("color", "color"),
                             ("backgroundColor", "background"), ("verticalAlignment", "valign")):
                if c.get(src) is not None:
                    d[dst] = c[src]
        elif t == "image":
            d = {"kind": "image", "name": cid, "url": c.get("url", "")}
        else:
            continue  # dashboardProperties / unknown -> not a tile
        d.update(pos)
        dashlets.append(d)

    if not dashlets:
        raise SystemExit("ERROR: no tiles parsed from the live layout")

    manifest = {"folder": folder, "name": name, "label": label, "dashlets": dashlets}
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print(f"OK: wrote {args.out} ({len(dashlets)} dashlets) from live {uri}")
    for d in dashlets:
        tgt = d.get("resource") or (d.get("kind", "?") + ":" + d.get("name", ""))
        print(f"    [{d['x']:>2},{d['y']:>2} {d['width']}x{d['height']}] {tgt}")


if __name__ == "__main__":
    main()
