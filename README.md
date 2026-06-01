# Texas PostGIS Geocoder + Population Maps + JasperReports

A self-contained toolkit built on a single PostgreSQL/PostGIS database (`postgis_34_sample`) that:

- 🗺️ **Geocodes Texas addresses** — the PostGIS **Tiger geocoder** loaded for **all 254 Texas counties**
  (5.7M edges, 5.1M feature names, 2.7M address ranges).
- 📊 **Visualizes population** — 2020 census population as interactive Leaflet heatmaps and density
  choropleths (statewide down to ~500 m and census block-group level).
- 📄 **Reports** — a **JasperReports 7** report over the same data (native `.jrxml`, compiles to `.jasper`,
  renders a 317-page PDF).

```sql
-- it works:
SELECT g.rating, pprint_addy(g.addy)
FROM geocode('1100 Congress Ave, Austin, TX 78701', 1) AS g;   -- rating 0, exact match
```

## Repository layout

| Path | Contents |
|------|----------|
| `scripts/` | TIGER data loaders (verified curl downloads + CRC retry). `load_tiger_nation.bat`, `load_remaining.ps1`, etc. |
| `report/`  | JasperReports: `*_jr7.jrxml` (native JR 7) + 6.x version, JDBC data adapter, compile/fill harnesses |
| `maps/`    | Self-contained Leaflet HTML visualizations (open in a browser) |
| `output/`  | Generated PDF / GeoJSON / CSV (not tracked — regenerate from the DB) |
| **`RUNBOOK.md`** | **Full reference**: environment, exact commands, rebuild order, and the gotchas |
| `ONBOARDING.md` | 5-minute orientation for a new contributor |

## Quick start

1. **Database**: PostgreSQL 14 + PostGIS 3.4, DB `postgis_34_sample`, user `postgres`.
   Set your password in the environment before running anything: `set PGPASSWORD=...` (Windows) — scripts read it from there.
2. **Geocoder**: run `scripts/load_tiger_nation.bat` then `scripts/load_remaining.ps1` (idempotent, verified).
3. **Maps**: open any file in `maps/` directly in a browser.
4. **Report → PDF**: see [RUNBOOK.md](RUNBOOK.md) §5 (build the JasperReports 7 library, compile, fill, export).

## Good to know (the gotchas, in brief)

- **Downloads use `curl` + `7z t` integrity checks with retry** — the census CDN occasionally serves silently
  corrupt zips (HTTP 200) and can return a CDN-cached WAF rejection page; both are handled. Details in the RUNBOOK.
- **JasperReports 7 changed the `.jrxml` format** (no namespace, `<query>`, no `<reportElement>`, flattened
  `<element kind="…">`). Use the `*_jr7.jrxml` file, or let Jaspersoft Studio auto-upgrade the 6.x one.
  PDF export requires the separate `jasperreports-pdf` module.

## Prerequisites

PostgreSQL 14 + PostGIS · JDK 11 · Maven 3.9 · 7-Zip · curl. See [RUNBOOK.md](RUNBOOK.md) for versions and paths.

---
*No credentials are stored in this repo — set `PGPASSWORD` in your environment. See RUNBOOK.md for the full reference.*
