# 1940s Cities, Towns, Rivers, Docks & Industry — Implementation Plan

> **For Hermes:** use the `multi-phase-program-delegation` / `subagent-driven-development` skills to run the
> phases below. One subagent per task, spec-compliance check then a code-quality check, tick a phase only when
> its own verification passes. No export / no version bump / no GitHub release until the **whole** program is done.

**Goal:** make the pre-rendered cities and towns read like real 1940s Channel-theatre settlements from the air —
a real street fabric, real rivers with water in them, piers and docks with period character, landmark skylines
and industry tied to the rails and the water.

**Architecture:** all of it is procedural, low-poly, streamed from `scripts/world_populator.gd` + `scripts/ground/*`.
New geography (rivers/waterfronts) is built as terrain-hugging ribbon meshes like `RoadMesh`, driven by real
OSM/curated lat-lon data. New architecture (piers, docks, industry, landmarks) extends `WorldFeatures` /
`Landmarks` / new `*_kit.gd` builders. Per-tile scatter stays on the worker-thread split
(`Scatter.tile_landcover_data` pure → `Scatter.build_tile_nodes` on the main thread).

**Tech stack:** Godot 4.8-dev (NVIDIA RTX fork) / GDScript, procedural toon meshes via `GroundKit` + `Scatter`.

---

## 0. Current context (verified by reading HEAD `9f82b96`)

| Area | Where it lives now | What's actually there |
|---|---|---|
| Towns | `scripts/ground/scatter.gd` — `make_town()` (L468), `_add_terrace()`, `tile_landcover_data()` L672 | One jittered rectilinear grid per city disc, **one yaw for the whole town**, terrace units from `house_mesh(0..7)`. Suburbs come from LandCover class 50 ⇒ `_add_terrace`. One church per tile/village. No streets from data, no town character by district. |
| City sites | `scripts/world_populator.gd` — `_register_cities()` L182, `_build_city()` L1186, `_city_skyline()` L1218 | Builds defences + `Scatter.make_town` core + a few churches and chimney stacks. **`cities[].landmark` in `data/locations.json` is read nowhere** — the field is dead. |
| Landmarks | `scripts/ground/landmarks.gd` — `build(id)` L93 | ~40 hand-built ids (big_ben, tower_bridge, dover_castle, st_pauls, cathedral family, arch bridges, mont_saint_michel, stonehenge…). Placed only from `features[type=landmark]` (28 features). Missing most 1940s silhouettes. |
| Rivers | `shaders/terrain.gdshader` L204-219 (painted ridged-noise), `scripts/water_plane.gd` (one flat sea plane at y=0), `data/osm/rivers.json` (**2.2 KB, hand-drawn fallback**, `_source.json` says `rivers: fallback`) | Rivers are **paint only**: no geometry, no water surface, no real course, no docks, and they never appear *in* a town. |
| Piers / docks | `scripts/world_features.gd` — `PORTS` (26), `build_port()` L91 | One generic quay + 2 breakwaters + finger piers + cranes + warehouses + fuel tanks + moored ships, scaled by `size 1-3`. `GroundStructure "port"` (`ground_structure.gd` L281) is a second, different generic quay. No pleasure piers, dry docks, shipyards, river quays, locks or basins. |
| Industry | `scripts/world_populator.gd` — `INDUSTRY` (21) L217, `_build_industry()` L254, `INDUSTRIAL_CITIES` L1214 | Grid of `GroundStructure("factory"/"refinery")` per cluster + chimney stacks near listed cities. No gasworks, colliery, mill, brewery, power station, shipyard, goods yard, engine shed or staithes. |
| Targets | `data/locations.json` `targets` (195) + `_build_target()` L1314 | `port`, `factory`, `rail_yard`, `oil_depot`, `bridge`, `battery`, `radar`, `v1_site`. Factory/rail_yard/oil_depot/port are single generic `GroundStructure`s. |
| Tests | `tools/tests.gd` → `scenes/tests.tscn` (headless, exits non-zero on fail); `tools/validate_data.py`, `tools/validate_missions.py` | Shader/mesh/aircraft/marking/turret/scatter-mask/music/audio checks. No town/river/landmark/industry coverage yet. |

**Known conventions to respect (from `HANDOFF.md` §7 and the code):**
- TABS, statically-typed GDScript. Adding a `class_name` script ⇒ run `--headless --path F:\ww2_dlss --import --quit` first.
- Never re-implement the projection — always `WorldCoords.latlon_to_world()`.
- All art is procedural low-poly toon, no photo textures. Any imported asset must be CC0/CC-BY in `ATTRIBUTION.md`.
- Per-tile scatter must stay split into a **pure** data pass (worker thread; call `RoadMesh.prepare_block()` on that thread first) and a node-making pass (main thread). No shared caches written on the worker.
- Deterministic: seed every site from `hash(id)` so a freed/streamed site rebuilds identically.
- Do not run `tools/build_locations.py` (drops hand-added targets). Use `tools/fix_imported_missions.py` for importer upserts.
- Accepted, do **not** "fix": synthetic fallback roads for Kent/Pas-de-Calais and synthetic rails/coast/woods in the expanded NE area.

---

## Delivery cadence (confirm before Phase 1)

Per the user's standing rule for phased programs: **build/test/tick per phase, no export, no version bump, no
`gh release` until every phase is complete.** Each phase ends with its own verification command producing a real
pass/fail, plus a one-line status tick. At the end: one export via the `HANDOFF.md` §"Export" command, one zip,
one release, and a `HANDOFF.md` session entry.

---

## Phase 0 — Data foundation (tools + curated datasets) — no game-code changes

Everything downstream needs real data. Do this first so Phases 1-5 are data-driven, not hard-coded.

### Task 0.1 — Real river geometry data
**Files:**
- Modify: `tools/fetch_osm.py:41` (the `LAYERS`/query table) — broaden the `rivers` layer:
  `way["waterway"="river"]`, `way["waterway"="canal"]`, `way["waterway"="riverbank"]` (as polygon → use its
  `lat/lon` outer ring as a wide centreline or keep as an area), plus `way["waterway"="stream"]` **only** inside a
  min-length filter. Raise the river `tol` so files stay loadable (<2 s target in `SPEC.md`).
- Modify: `tools/fetch_osm.py` `RIVERS_FB` (L301) — replace the 4 hand-drawn rivers with a richer fallback set
  (Thames, Medway, Swale, Great Stour, Rother, Arun, Adur, Ouse, Mole, Wey; Seine, Somme, Bresle, Canche, Authie,
  Lys, Scarpe, Deûle; Escaut/Scheldt, Leie, Dender, Meuse, Waal, Rhine, Moselle, Main, Ruhr, IJssel). Enough that a
  no-network run still looks right.
- Output: `data/osm/rivers.json` (grow from 2.2 KB to a real network) + `data/osm/_source.json` `rivers` field.
- Also write `data/osm/water.json` — polygon areas for lakes/estuaries/harbour basins (optional but valuable for
  docks in Phase 3).
- Code paths you must not break: `TransportNetwork._load_osm()` expects `{"lines":[{"k":..,"n":..,"pts":[[lat,lon],…]}]}`.

**Verify:** `python tools/fetch_osm.py --layers rivers,coast` (allow `--force-fallback`); then
`python tools/validate_data.py` → 0 errors; and a one-off Python check that `rivers.json` has ≥ 60 lines totalling
≥ 1200 km. Report line count + total length.

### Task 0.2 — Curated 1940s industry / docks / piers / landmarks dataset
**Files:**
- Create: `data/industry_1940.json` — hand-authored, era-plausible sites in the real places, keys like
  `{id,name,kind,lat,lon,size,team}` with `kind` ∈ `gasworks|colliery|mill|brewery|power_station|shipyard|
  dockyard|goods_yard|engine_shed|waterworks|cement_works|staithes`. Cover the Thames/Medway, S. Wales-adjacent
  Midlands, Lille/Rouen/Antwerp/Ruhr. Mark in the file header comment that it is hand-authored (no licence issue).
- Create: `data/docks_1940.json` — pleasure piers + harbour piers + dry docks + locks, keyed to lat/lon
  (Brighton Palace Pier, Eastbourne, Hastings, Deal; Port of London docks, Dover Admiralty Pier, Portsmouth
  dockyard, Southampton, Cherbourg arsenal, Le Havre, Antwerp, Rotterdam, Zeebrugge).
- Modify: `data/locations.json` — **do not regenerate.** Add missing entries with an inline edit (or a small
  `tools/upsert_cities_1940.py` that edits in place like `fix_imported_missions.py`), so the existing
  airfields/targets survive. Populate the currently-dead `cities[].landmark` strings properly, and add the missing
  `features[type=landmark]` rows for the new ids in Phase 5.
- Modify: `tools/validate_data.py` — validate the two new files (ids unique, lat/lon in bounds, kinds known).

**Verify:** `python tools/validate_data.py` → 0 errors; `python tools/validate_missions.py` → 0 errors (no
regression). Report counts (industry sites / docks / landmark features).

---

## Phase 1 — Real rivers (geometry + water + carve) — the biggest visual win

### Task 1.1 — `RiverMesh` ribbon builder (mirror of `RoadMesh`)
**Files:**
- Create: `scripts/ground/river_mesh.gd` (class_name `RiverMesh`, `RefCounted`) — copy the `RoadMesh` cell-index
  pattern (`_cells`, `_register_line`, `ways_in_tile`): load `data/osm/rivers.json`, register each line into
  1800 m cells, and `build_tile(origin, size) -> MeshInstance3D` emits a terrain-hugging water ribbon with width by
  class (`river` 1.5× the OSM tag width or a class default, `canal` narrower, `stream` thin). Miter normals as in
  `RoadMesh._add_line`. Add `near_river(p: Vector2) -> bool` + `prepare_block(origin,size)` exactly like
  `RoadMesh.prepare_block`/`near_road` so scatter keeps houses/trees/hedges out of the channel.
- Create: `shaders/river.gdshader` — a surface that follows the ribbon: base water colour, subtle flow scroll along
  the UV.y (already the arc-length in `RoadMesh`), mud/silt banks at the edges, depth fade to `col` where the ribbon
  meets the bank. Can start as a variant of `shaders/water.gdshader` (`scripts/water_plane.gd`) but **must not** rely
  on the y=0 sea plane — rivers sit in valleys above sea level.
- Modify: `scripts/world_populator.gd` — call `RiverMesh.ensure_loaded()` in `_ready()` next to
  `RoadMesh.ensure_loaded()` (L81); draw `RiverMesh.build_tile()` in the same place tiles are built
  (`_make_tile`/`_stream_tiles`), reusing the tile lifecycle so rivers stream with the terrain.
- Modify: `_land()`/`_ok()` in `scatter.gd` (L463, L1098) and `Scatter.make_town` guards — add `not RiverMesh.near_river(p)`.

**Verify:** add `--river-test` to `main.gd` `_parse_debug_args` — print lines loaded, total km, tiles drawn, and
`screenshot`. Run
`& 'F:\godot-rtx\bin\godot.windows.editor.x86_64.console.exe' --path F:\ww2_dlss --no-window --quit-after 400 -- --skip-menu --air --at=51.49,0.1,900,90 --frames=200 "--shot=tools\shots\river_thames.png"`
Expected: non-zero line/km counts in the log, a river ribbon visible in the shot, no SCRIPT/Parse errors.

### Task 1.2 — Heightmap river carve (offline) with an in-engine fallback
**Files:**
- Create: `tools/carve_rivers.py` — read `data/osm/rivers.json` + `data/heightmap/region_height.png` +
  `region_meta.json`, lower the DEM along each polyline by a depth that scales with river class, feathering the
  banks (so the ribbon sits in a real valley and the banks read from 200 m up). Write a backup of the previous PNG
  to `tools/cache/` before overwriting (the repo did not keep one last time — do it now).
- Modify: `tools/make_heightmap.py` docs/README to say rivers are carved **after** `fetch_osm` and **before**
  `fetch_imagery`/`make_urban_mask`.
- In-engine fallback: `RiverMesh.build_tile` must work when the heightmap is **not** carved (drape the ribbon on
  `GroundKit.ground_y` and just clamp it a hair below the terrain) so the game is playable without the rebuilt PNG.
- Re-check after carving: `TerrainChunkManager.add_flat_zone` airfield flats still level the runways; `RoadMesh`
  and `TransportNetwork` still drape; towns excluded from the channel.

**Verify:** rebuild heightmap path (`python tools/make_heightmap.py` then `python tools/carve_rivers.py`), re-import,
one `--no-window` run, and a screenshot over the Somme/Seine floodplain showing banks. Report before/after water
pixels along a known river sample.

### Task 1.3 — Retire the painted rivers
**Files:**
- Modify: `shaders/terrain.gdshader` — gate the L204-219 painted-river block behind a new global
  `real_rivers` (add to `project.godot [shader_globals]`), default 0. Set it to 1 from `RiverMesh.ensure_loaded()`
  when `rivers.json` is present, so paint and geometry never fight.
- Keep lakes (L220-229) as-is unless Phase 0 also produced `water.json`; if so, gate them the same way.

**Verify:** `--no-window` run with rivers present shows no double-rivers; with `rivers.json` deleted the painted
rivers return (fallback intact).

---

## Phase 2 — Town fabric v2 (streets, districts, waterfronts)

### Task 2.1 — Street-driven layout
**Files:**
- Modify: `scripts/ground/scatter.gd` — rewrite `make_town()` (L468). Instead of one grid yaw, build terraces
  **along the real streets**: reuse `RoadMesh.ways_in_tile()`/a new `RoadMesh.streets_in(rect)` to get road
  polylines inside the town radius, and lay terrace units along each street's tangents in short runs, breaking at
  junctions and cross-streets. Fall back to the current jittered grid when `roads.json` is the synthetic fallback.
  Vary `house_yaw` per street. Keep the 8 `house_mesh` variants and the `multi()` streaming.
- Keep the worker-thread purity contract: any street sampling used in `tile_landcover_data` must be read-only.

**Verify:** `--city-test` (new) prints, per city, street count / houses placed / longest terrace run; screenshot
over London-Croydon and Lille. Compare house count and footprint against HEAD.

### Task 2.2 — District character + civic core
**Files:**
- Modify: `scatter.gd` `make_town()` + `TILE` built-up branch — district rules by distance from centre and by
  `cities[].size` (1-5): central commercial (taller blocks, shopfront band, the odd cinema/church), inner terraces,
  suburban semis/cottages, industrial fringe. For `size >= 3` add a market square, town hall, and a railway station
  on the nearest rail (`TransportNetwork.routes_near("rails", …)`).
- Modify: `house_mesh()` (L43) only if a new variant is needed (e.g. a cinema/vaudeville front, a station canopy) —
  add `house_mesh(8,9)` rather than changing existing indices (multis index by variant).

**Verify:** `--city-test` district histogram; screenshots at 800 m over Canterbury (cathedral town), Calais, Lille.

### Task 2.3 — Waterfront orientation
**Files:**
- Modify: `scatter.gd` / `world_populator.gd` — where a town touches a river/coast (probe `RiverMesh`/`GroundKit.is_water`
  within the radius), face the nearest rows to the water, thin them into a quay edge, and register a waterfront
  quay + warehouses (Phase 3 builder) along that edge.

**Verify:** screenshot over the Thames at Erith/Dartford and the Seine at Rouen; quay + wharves visible, no houses
in the water.

---

## Phase 3 — Piers & docks

### Task 3.1 — Typed waterfront builders
**Files:**
- Modify: `scripts/world_features.gd` — add builders next to `build_port()` (L91):
  `build_pleasure_pier()` (trestle pier + pavilion + boarding kiosk), `build_dock_basin()` (basin walls, locks,
  quay cranes, transit sheds), `build_drydock_shipyard()` (slipways, gantry crane, fitting-out berth),
  `build_river_quay()` (quay wall + wharf sheds + coal staithes + barges), `build_fishing_harbour()`
  (net lofts, ice house, small boats). Reuse `GroundKit` primitives and `GroundShip` for moored hulls.
- Create: `scripts/ground/waterfront_kit.gd` if `world_features.gd` gets too big (it is already 399 lines) — keep
  the `class_name` + `static func` style so `WorldPopulator` can call either.

**Verify:** `--dock-test` (new) — build every type at one known lat/lon each, print mesh counts, screenshot.

### Task 3.2 — Register piers/docks from data + port type
**Files:**
- Modify: `scripts/world_populator.gd` — `_register_ports()` L408 and `_register_features()` L198: register
  `data/docks_1940.json` sites as streamed sites (`_add_site("dock_"+id, …)`), and branch `build_port()` by
  port **type** (fishing harbour / ferry port / dockyard / naval base) rather than only size.
- Modify: `scripts/ground/ground_structure.gd` `_build_port()` (L281) — either delegate to
  `WorldFeatures.build_port()` or upgrade so target-type `port` and site-type `port` match visually.

**Verify:** `--dock-test` + `--no-window` screenshot over Dover, Portsmouth, Zeebrugge, the Port of London.
Confirm no SCRIPT errors and site counts equal the dataset.

---

## Phase 4 — Industry v2 (gasworks, collieries, mills, yards)

### Task 4.1 — Industry builders
**Files:**
- Create: `scripts/ground/industry_kit.gd` (class_name `IndustryKit`) — static builders for
  `gasworks` (gasholders — the iconic silhouette), `colliery` (pit head-frame + winding house + spoil heap),
  `mill` (chimney + weaving sheds), `brewery` (tower + vats), `power_station` (cooling towers + chimney),
  `shipyard` (berths + gantry), `goods_yard` + `engine_shed` + turntable, `waterworks`, `cement_works`, `staithes`.
  All from `GroundKit` primitives; chimneys annotated so they can get `ChimneySmokes`.
- Modify: `scripts/world_populator.gd` — `_register_industry()` L243 / `_build_industry()` L254: place from
  `data/industry_1940.json` by `kind`, orient along the nearest rail or river, and run a **siding** from the site to
  `TransportNetwork.routes_near("rails", pos, …)` (a `RoutePath` stub so a `Train` can serve it later). Extend
  `industry_sites` (already consumed by campaign/planner) so the new kinds are raid targets.
- Modify: `scripts/ground/ground_structure.gd` — add destructible kinds (`gasworks`, `colliery`, `goods_yard`) to
  `CONFIG` + `_build_intact` so they can be mission targets, and point `_build_target()` L1337 at them for
  `factory`/`rail_yard`/`oil_depot` where the name matches.

**Verify:** `--industry-test` (new) — build each kind, print mesh/emitter counts, assert no null builder; screenshot
over the Ruhr, Thames Gateway, Lille. `--wp-auto` still reaches MISSION COMPLETE on a factory/rail_yard mission.

---

## Phase 5 — Landmarks & city skylines

### Task 5.1 — Add the missing 1940s landmarks
**Files:**
- Modify: `scripts/ground/landmarks.gd` `build()` (L93) — add ids for the period silhouettes that matter from the
  air: London (Battersea Power Station, Tower of London, Westminster Abbey, Royal Albert Hall, London Docks,
  Crystal Palace, Wembley), Kent/Channel (Rochester Castle + Cathedral, Leeds Castle, Dover Admiralty Pier/Great
  Tower), France/Belgium (Dunkerque belfry, Boulogne basilica, Lille Hôtel de Ville + citadel, Ghent belfry, Brussels
  Palais de Justice, Antwerp/Zeebrugge harbour works). Keep procedural + era-accurate; exaggerate scale so they read
  from altitude (the file's own header says this is intended).
- Modify: `data/locations.json` features — add the `type:"landmark"` rows for each new id (Phase 0.2 already opens
  the door). No change to `_build_landmark()` unless a new id needs a special sea/rotation rule (it already has the
  `sea_lm` and `tower_bridge/big_ben` special cases — extend that list).

**Verify:** `--landmark-test` (new) — iterate every landmark id, assert `Landmarks.build(id) != null` and has
≥ 1 mesh, screenshot the big ones. Report `N/38 built`.

### Task 5.2 — Wire `cities[].landmark` into placement
**Files:**
- Modify: `scripts/world_populator.gd` `_build_city()` L1186 — parse `cities[].landmark` (semicolon-separated
  names), map name → landmark id, and place each at its real offset inside/next to the built-up core
  (`_city_skyline()` L1218 is the natural home). Keep the deterministic `rng.seed = hash(id)` pattern.

**Verify:** `--city-test` prints which landmarks each city got; screenshot over London (St Paul's + Big Ben + Tower
Bridge together) and Dover (castle on the cliffs).

---

## Phase 6 — Integration, performance, docs, release gate

### Task 6.1 — Tests
**Files:**
- Modify: `tools/tests.gd` + `scenes/tests.tscn` — add deterministic checks:
  `_test_river_data()` (rivers.json parses, ≥ N lines, total length in range), `_test_landmarks_all()` (every id in
  `build()` returns a non-null node), `_test_house_variants()` (all indices build), `_test_industry_kinds()`.
  Follow the existing `_check(ok, what)` style.

**Verify:** `& <godot exe> --headless --path F:\ww2_dlss scenes/tests.tscn` → `TESTS OK (N passed, 0 failed)`,
exit 0.

### Task 6.2 — Performance budget
**Files:**
- Modify: streaming in `world_populator.gd` / `scatter.gd` — rivers/docks/industry are extra per-tile work: keep the
  6 ms/tick site budget (`_stream_sites`), the worker-thread tile split, `MultiMesh` for repeated props, and
  visibility ranges. Re-measure with `--loadprof`, `--mem-test`, `--turn-test`.

**Verify:** `--loadprof` first-load and replay numbers within ~10 % of HEAD; `--turn-test` max frame time not
regressed; `--mem-test` CPU/VRAM within the HEAD envelope (~230/350 MB CPU).

### Task 6.3 — Docs + release (only after 0-5 all tick)
**Files:**
- Modify: `SPEC.md` (WORLD CONTENT + data contract for rivers.json/industry_1940.json/docks_1940.json),
  `HANDOFF.md` (new session entry), `README.md` (features: real rivers, piers/docks, 1940s industry, landmarks),
  `ATTRIBUTION.md` (only if any new data source is added beyond OSM).
- Do **not** touch `LICENCE`. Bump `application/config/version` in `project.godot` once.
- Export: `& 'F:\godot-rtx\bin\godot.windows.editor.x86_64.console.exe' --headless --path F:\ww2_dlss --export-release "Windows Desktop" F:\ww2_dlss\build\WW2ChannelAirWar.exe`, then the zip + `gh release create` per `HANDOFF.md`.

**Verify:** every mode × both sides, day + night, one `--no-window` run each with no SCRIPT/Parse errors; the four
screenshots (Dover, London, Calais, Rouen) committed to `screenshots/`.

---

## Files likely to change

**New:** `scripts/ground/river_mesh.gd`, `scripts/ground/waterfront_kit.gd` (maybe), `scripts/ground/industry_kit.gd`,
`shaders/river.gdshader`, `tools/carve_rivers.py`, `tools/upsert_cities_1940.py` (maybe),
`data/industry_1940.json`, `data/docks_1940.json`.

**Modified:** `scripts/world_populator.gd`, `scripts/ground/scatter.gd`, `scripts/ground/landmarks.gd`,
`scripts/world_features.gd`, `scripts/ground/ground_structure.gd`, `scripts/ground/road_mesh.gd` (expose
`streets_in`/reuse `prepare_block`), `scripts/main.gd` (debug args), `shaders/terrain.gdshader`,
`project.godot`, `tools/fetch_osm.py`, `tools/make_heightmap.py`, `tools/validate_data.py`, `tools/tests.gd`,
`data/osm/rivers.json`, `data/locations.json`, `data/heightmap/region_height.png` (carve), plus `SPEC.md`,
`HANDOFF.md`, `README.md`.

## Tests / validation (all real commands)
- `python tools/validate_data.py` → 0 errors (after Phase 0 and 2/5 data edits).
- `python tools/validate_missions.py` → 0 errors (regression guard).
- `& <godot exe> --headless --path F:\ww2_dlss --import --quit` after each new `class_name`.
- `& <godot exe> --headless --path F:\ww2_dlss scenes/tests.tscn` → `TESTS OK`.
- `--no-window` runs with `Select-String 'SCRIPT|Parse|Invalid'` empty, plus one `--shot=` screenshot per phase.
- New debug args: `--river-test`, `--city-test`, `--dock-test`, `--industry-test`, `--landmark-test`.

## Risks, tradeoffs, open questions
1. **Rivers above sea level.** The sea is one flat plane at y=0 (`water_plane.gd`); a real river needs its own
   surface in its own valley. Decision needed: **carve the DEM offline** (best look, touches every downstream
   consumer) vs **drape-only** (cheap, rivers sit on the ground). Plan assumes carve **with** a drape fallback.
2. **Carving cost.** Rebuilding `region_height.png` changes terrain everywhere ⇒ re-verify airfield flats, town
   exclusions, road/rail draping, and load time. Keep a PNG backup in `tools/cache/`.
3. **OSM reflects today**, not 1940: canals/dredging differ slightly. Accepted for the Channel theatre — the plan is
   about *reading* right from the air, not survey accuracy.
4. **Perf.** Rivers + docks + industry add per-tile geometry. Mitigations: MultiMesh, visibility ranges, the existing
   6 ms/tick budget, keep the worker-thread split. If it regresses, drop `stream`-class rivers first.
5. **Worker-thread purity.** New per-tile builders must not touch shared caches on the worker; follow
   `tile_landcover_data` (pure) → `build_tile_nodes` (main thread).
6. **Licensing.** OSM (ODbL) is already attributed; `industry_1940.json`/`docks_1940.json` must be hand-authored or
   derived from OSM, and listed in `ATTRIBUTION.md` if a new source appears.
7. **Scope.** This is 6 phases / ~14 tasks — a multi-session program. Confirm the phase order (data → rivers →
   towns → docks → industry → landmarks) before starting, since rivers (Phase 0/1) gate town waterfronts (2.3) and
   dock/industry placement (3.2, 4.1).

## Open decision for the owner
- Carve-the-DEM vs drape-only for rivers (risk 1) — pick before Phase 1.2.
- Do `industry_1940.json` / `docks_1940.json` get derived from OSM via a new tool, or hand-authored? (hand-authored
  is faster and licence-safe; OSM-derived is more accurate but needs a new fetcher + attribution).
