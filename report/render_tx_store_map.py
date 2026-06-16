#!/usr/bin/env python3
"""Render a two-layer Texas choropleth heatmap for the foodmart relocation demo.

Layer 1 (choropleth): Texas counties shaded by 2020 Census block population
                      (tiger.county geometry + tiger_data.tx_tabblock20 pop).
Layer 2 (markers)   : foodmart stores + warehouses, relocated onto real Texas
                      cities (tiger_data.tx_place point-on-surface) and plotted
                      as point markers in the SAME lon/lat coordinate system as
                      the polygons -- so positions are geographically exact.

Pure matplotlib (no geopandas): county polygons come in as GeoJSON and are drawn
as PathPatches. Output: a high-res PNG embedded in a deployed JasperReport.
"""
import csv, json, math, sys
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import PathPatch, Patch
from matplotlib.path import Path as MplPath
from matplotlib.lines import Line2D
import matplotlib.colors as mcolors
import matplotlib.patheffects as pe
from matplotlib.cm import ScalarMappable

HERE = Path(__file__).resolve().parent
MAP = HERE.parent / "out" / "map"
OUT = MAP / "tx_store_warehouse_map.png"
RELOC = MAP / "relocation.csv"

# ---- load layer 1: counties --------------------------------------------------
counties = []
with open(MAP / "tx_counties.csv", newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        counties.append((row["name"], int(row["population"]),
                         json.loads(row["geom"])))

# ---- load cities + foodmart records, build the relocation --------------------
cities = []
with open(MAP / "tx_cities.csv", newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        cities.append((row["name"], float(row["lat"]), float(row["lon"])))

stores = []
with open(MAP / "fm_stores.csv", newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        stores.append((row["store_id"], row["store_type"], row["store_name"]))

warehouses = []
with open(MAP / "fm_warehouses.csv", newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        warehouses.append((row["warehouse_id"], row["warehouse_name"]))


def jitter(i, n_same):
    """Deterministic small spiral offset (degrees) so co-located markers split."""
    if n_same <= 1:
        return 0.0, 0.0
    ang = 2 * math.pi * (i / max(n_same, 1))
    r = 0.18
    return r * math.cos(ang), r * math.sin(ang)


# assign stores to cities round-robin; warehouses offset by half so they don't
# sit exactly on a store. Track how many land on each city for jitter.
reloc_rows = []
store_pts, wh_pts = [], []
ncity = len(cities)
city_load = {}  # city -> running count
for idx, (sid, stype, sname) in enumerate(stores):
    cname, lat, lon = cities[idx % ncity]
    k = city_load.get(cname, 0); city_load[cname] = k + 1
    dlat, dlon = jitter(k, 4)
    store_pts.append((lon + dlon, lat + dlat, f"{sname} ({stype})", cname))
    reloc_rows.append(("store", sid, sname, stype, cname,
                       round(lat + dlat, 5), round(lon + dlon, 5)))
for idx, (wid, wname) in enumerate(warehouses):
    cname, lat, lon = cities[(idx + ncity // 2) % ncity]
    k = city_load.get(cname, 0); city_load[cname] = k + 1
    dlat, dlon = jitter(k, 4)
    wh_pts.append((lon + dlon, lat + dlat, wname, cname))
    reloc_rows.append(("warehouse", wid, wname, "", cname,
                       round(lat + dlat, 5), round(lon + dlon, 5)))

with open(RELOC, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["kind", "id", "name", "store_type", "tx_city", "lat", "lon"])
    w.writerows(reloc_rows)

# ---- figure ------------------------------------------------------------------
fig, ax = plt.subplots(figsize=(16, 14), dpi=150)
fig.patch.set_facecolor("white")

# 5-band heatmap matching the FusionMaps tx population palette
bounds = [0, 25000, 100000, 500000, 1000000, 5000000]
colors = ["#FFEDA0", "#FEB24C", "#FD8D3C", "#FC4E2A", "#800026"]
cmap = mcolors.ListedColormap(colors)
norm = mcolors.BoundaryNorm(bounds, cmap.N)


def rings_to_path(rings):
    verts, codes = [], []
    for ring in rings:
        for j, (x, y) in enumerate(ring):
            verts.append((x, y))
            codes.append(MplPath.MOVETO if j == 0 else MplPath.LINETO)
        verts.append((0, 0)); codes.append(MplPath.CLOSEPOLY)
    return MplPath(verts, codes)


for name, pop, geom in counties:
    polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
    color = cmap(norm(pop))
    for poly in polys:
        ax.add_patch(PathPatch(rings_to_path(poly), facecolor=color,
                               edgecolor="#777777", linewidth=0.35, zorder=1))

# layer 2: markers
sx = [p[0] for p in store_pts]; sy = [p[1] for p in store_pts]
wx = [p[0] for p in wh_pts]; wy = [p[1] for p in wh_pts]
ax.scatter(wx, wy, marker="s", s=150, c="#1f3a93", edgecolors="white",
           linewidths=1.1, zorder=3, label=f"Warehouses ({len(wh_pts)})")
ax.scatter(sx, sy, marker="o", s=130, c="#0b8043", edgecolors="white",
           linewidths=1.1, zorder=4, label=f"Stores ({len(store_pts)})")

# city labels: one per city (at its base lon/lat), offset from the markers, with
# a white halo so they stay legible over the choropleth fill. The DFW/north-Texas
# cities sit too close to share the default offset, so they get hand-tuned
# offsets fanned outward + a thin leader line back to the marker.
halo = [pe.withStroke(linewidth=2.6, foreground="white")]
# city -> (dx_pts, dy_pts, ha, va) ; absence => default (6, 6, left, bottom)
LABEL_OVERRIDES = {
    "Sherman":    (0,  13, "center", "bottom"),
    "Plano":      (12,  9, "left",   "bottom"),
    "Dallas":     (15, -1, "left",   "center"),
    "Fort Worth": (-12, 9, "right",  "bottom"),
    "Arlington":  (-6, -15, "right", "top"),
}
for cname, lat, lon in cities:
    if cname in LABEL_OVERRIDES:
        dx, dy, ha, va = LABEL_OVERRIDES[cname]
        ax.annotate(cname, xy=(lon, lat), xytext=(dx, dy),
                    textcoords="offset points", ha=ha, va=va,
                    fontsize=9.5, fontweight="bold", color="#1a1a1a",
                    zorder=6, path_effects=halo,
                    arrowprops=dict(arrowstyle="-", color="#555555",
                                    linewidth=0.6, shrinkA=1, shrinkB=4))
    else:
        ax.annotate(cname, xy=(lon, lat), xytext=(6, 6),
                    textcoords="offset points", ha="left", va="bottom",
                    fontsize=9.5, fontweight="bold", color="#1a1a1a",
                    zorder=5, path_effects=halo)

ax.set_xlim(-107.0, -93.0)
ax.set_ylim(25.5, 36.7)
ax.set_aspect(1.0 / math.cos(math.radians(31.0)))  # rough equirect at TX lat
ax.set_xticks([]); ax.set_yticks([])
for s in ax.spines.values():
    s.set_visible(False)

# NB: the report frame (tx_store_warehouse_map.jrxml) supplies the title and
# subtitle as crisp vector text, so the rendered image carries neither -- this
# avoids a doubled title and gives the map more vertical room.

# choropleth colorbar
sm = ScalarMappable(cmap=cmap, norm=norm); sm.set_array([])
cbar = fig.colorbar(sm, ax=ax, fraction=0.030, pad=0.01, ticks=bounds)
cbar.ax.set_yticklabels([f"{b:,}" for b in bounds])
cbar.set_label("County population (2020)", fontsize=11)

leg = ax.legend(loc="lower left", frameon=True, fontsize=13, title="Foodmart sites",
                title_fontsize=13, markerscale=1.2)
leg.get_frame().set_edgecolor("#888888")

fig.tight_layout()
fig.savefig(OUT, dpi=150, bbox_inches="tight", facecolor="white")
print(f"OK wrote {OUT} ({OUT.stat().st_size} bytes)")
print(f"   counties={len(counties)} stores={len(store_pts)} warehouses={len(wh_pts)}")
print(f"   relocation table -> {RELOC}")
