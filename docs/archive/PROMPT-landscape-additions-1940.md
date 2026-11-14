# PROMPT — 1940s landscape additions (decoys, grid, canals, rail drama, dams, sea defences, city barrages)

**Status:** brief + phase sequence. Phase board: `PROGRAM-STATUS-landscape.md`.
**Engine:** `F:/godot-rtx/bin/godot.windows.editor.x86_64.console.exe`
**Program start:** HEAD `4f9791f` (v4.0), 2026-10-09.

---

## Target

Deepen the world with the 1940s landscape that is *genuinely absent* from the map. Reconnaissance against
the real tree (not assumption) found that several items first proposed already exist and are therefore
**out of scope except where they are deepened**: coastal defence clusters (`_register_coast_defences`
+ `_build_coast_cluster`, up to 320 clusters along the real OSM coast, each with bunkers/pillboxes/beach
defences/AA/radar), barrage balloons and searchlights around targets (`_defences`), ambient road/rail/sea
traffic (`_register_traffic`), camps (`_register_camps`), ports/docks/industry/landmarks (v4.0).

## Non-negotiable constraints

1. **Never launch the engine.** One Godot instance at a time and none from a child. Per-phase verification
   is *static* (below). The parent runs the single consolidated `--import` + tests + render pass at the end.
2. **TABS, statically-typed GDScript.** Match surrounding style exactly.
3. **Determinism**: seed every streamed site from `hash(id)`. A freed and re-streamed site must rebuild identically.
4. **No release, no version bump, no export, no `gh release`** until every phase is verified and the user asks.
5. Never run `tools/build_locations.py`. Never regenerate `data/osm/roads.json`.
6. Never re-implement `WorldCoords.latlon_to_world` / `world_to_latlon`.
7. **Real places, real coordinates, cited.** Every new data row carries a real lat/lon and its source;
   add the source to `ATTRIBUTION.md`. No invented geography, no invented site names.
8. Procedural low-poly toon only — `GroundKit` primitives, no photo textures.
9. Every new per-tile builder keeps the pure/worker → main-thread node split (call `RoadMesh.prepare_block`
   / `RiverMesh.prepare_block` on the worker thread first).
10. `tools/validate_data.py` must stay PASS and `tools/tests.gd` count (currently **636**) must never drop.

## Static verification contract (what a child owes per phase)

- Re-read every file changed, end to end: tabs, types, balanced delimiters.
- For every symbol *called*, confirm the exact name and arity exists in the file that *defines* it
  (`GroundKit.box`, `GroundKit.cyl`, `GroundKit.combine`, `GroundKit.ground_y`, `GroundStructure.create`,
  `_add_site`, `Scatter.find_shore`, `RoutePath.from_latlon`, …). Invented helpers are the top failure.
- Every new entry point has a call site (a builder never *called* generates nothing and raises nothing).
- `python3 tools/validate_data.py` → PASS (this is not the engine; it is cheap and required).
- Add `_test_*` cases to `tools/tests.gd` in the existing `_check` style, and a `--<thing>-test` arg in
  `scripts/main.gd` printing counts (mesh count, site count, total km) beside the existing ones
  (`--dock-test`, `--industry-test`, `--landmark-test`, …).
- Mark every change NOT-verified in the report and the phase board row.

## Exact hooks (verified against the tree)

- Sites: `world_populator.gd` — `_load_locations` (113), `_add_site(key, pos, act, builder, extra)` (123),
  `_register_airfields` (156), `_register_cities` (185), `_register_features` (205), `_register_industry`
  (255), `_register_targets` (420), `_register_coast_defences` (458), `_register_traffic` (510),
  `_register_ports` (548), `_register_channel_convoys` (596), `_build_sea_mark` (626),
  `_register_sea_lane` (637), `_register_camps` (658), `_register_docks` (706), `_stream_sites` (839),
  `_build_site` (870), `_defences` (1096), `_build_coast_cluster` (1665), `_build_target` (1712).
- Structures: `scripts/ground/ground_structure.gd` `CONFIG` (21 kinds) + `create(kind, team, pos, heading_deg)`.
- Primitives: `scripts/ground/ground_kit.gd` — `box/cyl/sphere/prism_mesh/combine/box_part/cyl_part`,
  `mat`, `ground_y`, `raw_y`, `is_water`, `water_dir`, `side_at`, `explosion`, `stack_smoke`,
  `persistent_smoke`, `find`-free `lp`.
- Ribbon pattern (copy for any draped line): `scripts/ground/road_mesh.gd` (`ensure_loaded`,
  `_register_line`, `ways_in_tile`, `build_tile` L226, `_add_line` L271, `prepare_block`, `add_exclusion_box/disc`),
  `scripts/ground/river_mesh.gd`, `scripts/ground/transport_network.gd` (`roads`/`rails`/`sea_lanes`,
  `routes_near(kind,pos,max_dist)`).
- Ports/sea furniture: `scripts/world_features.gd` — `PORTS` (26), `build_port` (91), `build_camp`,
  `SEA_MARKS`, `build_lightship`, `build_sea_fort`.
- Landmarks: `scripts/ground/landmarks.gd` `build(id)` — 66 ids today (cathedrals, castles, civic, bridges, docks).
- Land cover: `scripts/land_cover.gd` `class_at(x,z)` (50 = built-up), `urban_mask()`.
- Tests: `tools/tests.gd` `_check` (31), `_check_has_entries` (315), `_test_data_files` (289),
  `_test_river_data` (325), `_test_landmarks_all` (367), `_test_industry_kinds` (433).
- Debug args live in `scripts/main.gd` (`--dock-test`, `--industry-test`, `--landmark-test`, …).

**Data already on disk:** `data/osm/rivers.json` has **15,479 lines, `k` ∈ {`canal` 8,491, `river` 6,988}**
— canals are already fetched and rendered as ribbons; what is missing is canal *furniture*.
`data/osm/rails.json` = 72,308 lines, **no bridge/tunnel tags** (viaducts/tunnels need terrain logic or
curated data). OSM fetch layers: roads, rails, rivers(+canals), coast, woods, towns — **no power layer**.
`data/locations.json` = 85 airfields, 85 cities, 195 targets, 92 features.

---

## Phases, in priority order

The user's own words set the top three. **P1–P3 are named by the user and come first.**

### P1 — Sea defences ("quite limited currently")
Minefields as marked lines of moored mines and buoyed channels; anti-submarine booms and steel nets across
harbour/estuary mouths (Portsmouth, Dover, Southampton, Cherbourg, Le Havre, the Solent, the Thames
estuary); **blockships** — the Zeebrugge/Ostend blockships and the Gooseberry hulks; additional sea forts
(`build_sea_fort` exists — place more, with real positions for the Maunsell/Grain forts and the
Thames/Medway sea forts); offshore beach obstacles (Czech hedgehogs and scaffolding below the tide line);
mine-sweeping trawlers and boom-gate vessels as ambient traffic; wreck buoys and marked wrecks.
New: `scripts/ground/sea_defence_kit.gd`, `data/sea_defences_1940.json`, registered from
`_register_coast_defences`/`_register_ports` neighbourhoods and the sea lanes. Target kinds where
destructible: reuse `bunker`/`port`.
Acceptance: count of sea-defence sites and total spanned km printed by `--sea-defence-test`; meshes non-null.

### P2 — Barrage balloons over cities ("more balloons over cities")
Balloons exist (`BarrageBalloon.create(team, altitude)`, placed only in small numbers by `_defences`).
Add a **city balloon barrage**: for every city (`city.size` 1–5, 85 cities) lay a barrage scaled to size —
rings/aprons of balloons on cables at realistic altitudes (600–1,500 m for the big cities), denser over
London and the Thames/Medway estuary and the ports, with ground winch sites. Hook `_register_cities` (185)
/ `_build_city`; keep it deterministic from `hash(city.id)`.
Acceptance: `--balloon-test` prints cities covered, balloons per size band, total balloons; a headless test
asserts London's count > a size-1 town's count.

### P3 — Dams for the Dam Busters raid
Real dams, real coordinates, as world features and destructible targets: **Möhne (51.4889, 8.0575),
Eder (51.1833, 8.9667), Sorpe (51.3167, 7.9667), Ennepe (51.2833, 7.4667), Lister (51.0833, 7.9167),
Diemel (51.4667, 8.7167)** — verify each coordinate from a cited source in the implementation pass and
record it in `ATTRIBUTION.md`. Build: curved gravity/masonry dam wall across a valley, valve towers,
spillway, hydro plant, and a reservoir — the lake must read as water (terrain carve or a water body the
height field accepts; the game already has a sea plane and `is_water`, and `tools/carve_rivers.py` shows
the offline-carve pattern for holding terrain).
New: `scripts/ground/dam_kit.gd` (one `build(id)`), `data/dams_1940.json`, new `GroundStructure.CONFIG`
kind(s) `dam` (+ a breached state so a busted dam can be shown), registered by `_register_dams()`.
Acceptance: `--dam-test` builds every dam from the data, prints mesh counts and reservoir area; a headless
test asserts every dam id builds non-null with ≥ 1 mesh.
**Note in the board** that the *Upkeep weapon and the Chastise mission* (bouncing bomb, low-level run,
breach event) are a separate follow-on phase — P3 delivers the places and the targets; say so rather than
implying the raid is playable.

### P4 — Decoy sites
Starfish decoy towns (QF/QL lighting decoys that mimicked a burning city), Q-sites and K-sites (dummy
airfields with dummy aircraft, flare paths and decoy fires), and decoy fires. Real documented sites, cited.
New `scripts/ground/decoy_kit.gd` + `data/decoys_1940.json`; non-destructible scenery plus a `decoy` target
kind so a raid *can* be wasted on one.

### P5 — The power grid
1927–35 National Grid pylons and overhead lines, plus telegraph poles along roads. `tools/fetch_osm.py`
has no power layer: add `power=line`/`power=tower` to `LAYERS` and fetch, with a curated
`data/pylons_1940.json` fallback for the period grid where OSM differs. Draped ribbon for the line
(copy `road_mesh.gd`), instanced pylon meshes at tower nodes. Record a tolerance/simplification like the
other layers so the file stays small.

### P6 — Canal furniture
Canals are already in `rivers.json` (`k='canal'`, 8,491 lines). Add the missing furniture: locks, lock
keepers' cottages, aqueducts, basins, wharves, dry docks, narrowboats and barges, and canal-side industry.
Place along the canal lines with terrain-aware spacing.

### P7 — Railway drama
Vi abundance of rail yards exists; add viaducts, tunnels, junctions, signal boxes, level crossings,
turntables, water cranes, coaling stages and goods sheds. `rails.json` carries no bridge/tunnel tags —
derive viaducts/tunnels from terrain (rail crossing a valley above ground → viaduct; rail disappearing
below the height field → tunnel portal), or curate the famous ones with real positions.

### P8 — Airfield furniture
Dispersal and blast pens, revetments, Nissen hut camps, T2/T1 hangars, control tower, fuel and bomb dumps,
flare path with Chance lights, dummy aircraft. Hook `_dress_grass_airfield` and `airfield_assets.gd`;
keep it inside the airfield footprint and clear of the runway.

### P9 — Oil and fuel
One oil depot exists and a `refinery` kind exists — place the real cluster: Thames Haven, Shell Haven,
Coryton, Fawley, Southampton, the Seine and Antwerp refineries, plus petrol depots and gas holders.

### P10 — Aircraft industry
The 1940 aircraft plants and shadow factories at their real sites (Castle Bromwich, Southampton, Coventry,
Bristol, Brooklands, Hatfield, Yeovil) plus dispersed production and storage sites.

### P11 — V-weapons
`v1_site` exists (5). Add the 1944 "ski" sites and the **Heavy Cross bunkers at Wizernes and Eperlecques**
(Pas-de-Calais — inside the theatre), with cited coordinates.

### P12 — Port clutter
Cranes, lock gates, dredgers, hopper barges, tugs, paddle steamers, and the **Dover–Dunkerque train
ferries**; existing dock builders supply moored hulls to reuse.

### P13 — Rural and Kentish texture
Oast houses and hop gardens, orchards, market gardens, drainage mills, sheep folds.

### P14 — Coastal landmarks
Martello towers, coastguard stations, RNLI lifeboat stations, lidos, bandstands, requisitioned holiday
camps — as `landmarks.gd` ids (the landmark data model and the 70-row feature set already exist).

### P15 — Civil defence
Public shelters, Anderson shelters, ARP and wardens' posts, sandbagged buildings, camouflage-painted
factory roofs.

### P16 — Aviation support
Seaplane and flying-boat bases (Sunderland stations), airship/blimp mooring stations, kite balloons.

### P17 — Forestry
Forestry Commission plantations and timber camps.

### P18 — Navigation aids
Radio range beacons, DF stations, beacon masts (Rugby, Droitwich), airfield lighting for night sorties.

### P19 — Military depth
Transit and embarkation camps, ammunition depots, vehicle parks, horse-drawn transport columns
(1940 is more horse than truck), tank trains.

---

## Report shape owed per chunk

1. Phase rows updated in `PROGRAM-STATUS-landscape.md` **first**, with files and exact hooks touched.
2. Per phase: what was built, the data file and its cited sources, the new debug arg, the new tests.
3. `python3 tools/validate_data.py` output.
4. A wire-up list: every new entry point and the one call site that invokes it.
5. The honest gap list — what was written but not exercised, and anything knowingly incomplete.
6. Confirm the forbidden artifacts are untouched (no export, no version bump, no release).

## Definition of done for the program

- Every phase row DONE with evidence, or explicitly carried as a gap.
- One consolidated engine pass by the parent: `--import` → `scenes/tests.tscn` (`TESTS OK (N, 0)`, N ≥ 636)
  → the new `--<thing>-test` args → a render or two of the most visible additions, reviewed.
- `validate_data.py` PASS. Docs (`SPEC.md`, `HANDOFF.md`, `README.md`, `ATTRIBUTION.md`) updated.
- No export, no version bump, no release until the user asks.
