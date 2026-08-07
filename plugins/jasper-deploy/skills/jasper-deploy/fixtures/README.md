# Fixtures: canonical known-good JR7 artifacts (index)

This is an **index only** -- it does not copy any files. Each row points at an
existing, known-good exemplar in the repo so you can crib the exact JR7 markup
for a given feature instead of guessing. The list is drawn from `SKILL.md`'s
"## Visualization components" table, its "Reference reports known to compile and
render" note, and the `report\` tree.

Paths are **relative to the repository root** (the `tx-geocoder` checkout that
contains this skill under `plugins\jasper-deploy\skills\jasper-deploy\`). Every path below was
verified to exist at the time of writing; anything that could not be found is
marked `(not found in repo)`.

Which artifacts compile locally vs. only render server-side, and the per-feature
JR7 gotchas, are documented in `SKILL.md`; this file is just the map from feature
to file.

| Feature | Exemplar file (repo-root relative) | Notes |
|---|---|---|
| Tabular report + groups/subtotals | `report\tx_density_blockgroup_report_jr7.jrxml` | The canonical tabular-with-groups reference; compiles + renders. |
| Pie chart (JFreeChart) | `report\metro_population_piechart.jrxml` | Community; compiles + RenderPng locally. |
| Bar chart (JFreeChart) | `report\metro_population_bar.jrxml` | Community; gradient/trend customizer applies by default. |
| Spider / radar chart | `report\metro_population_spider.jrxml` | Community `<component kind="spiderChart">`. |
| Barcode / QR | `report\barcode_demo.jrxml` | barcode4j QR/DataMatrix/Code128; needs `whenNoDataType="AllSectionsNoDetail"`. |
| KPI dial (gauge / meter) | `report\foodmart\gross_margin_dial.jrxml` | JFreeChart meter `shape="dial"`, from `scaffold_kpi_dial.py`. |
| CSV-adapter main report | `report\csv_metro_pop.jrxml` | Main dataset via a `.jrdax` data adapter, no JDBC datasource. |
| CSV data adapter (`.jrdax`) | `report\data\metro_pop_adapter.jrdax` | The adapter `csv_metro_pop.jrxml` references (paired with `report\data\metro_pop.csv`). |
| Shared style template (`.jrtx`) | `out\styletest\jd_corporate.jrtx` | No canonical copy under `report\`; this is the verified output of `scripts/scaffold_style_template.py --palette corporate`. Generate fresh with that scaffolder. |
| HTML5 Pro chart (HighCharts) | `report\metro_population_html5.jrxml` | Pro / legacy 6.x jrxml; server-rendered only (deploy -> run to validate). |
| FusionMaps Pro choropleth | `report\tx_county_density_map.jrxml` | Pro / legacy 6.x jrxml; Texas map keyed by county FIPS; server-rendered only. |

## Cross-references
- `SKILL.md` -- the "Visualization components" tables (Community vs. Pro tiers),
  per-feature jrxml shape, and the gotchas for each of the above.
- `references/jr7-schema.md` -- JR7 schema notes for hand-editing these.
- `references/fusion-pro-gotchas.md` -- KPI meter dial + FusionMaps reference.
- `references/seed-data.md` -- the sample databases these reports query.
