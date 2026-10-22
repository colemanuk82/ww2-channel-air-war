# PROGRAM-STATUS — 1940s Cities, Towns, Rivers, Docks & Industry

Program brief + full task list: **`PROMPT-cities-towns-1940s.md`** (read it in full before starting a phase).
This file is the phase board + tooling/traps. The orchestrator verifies every phase independently.

## Owner decisions (resolved — do NOT re-ask)
- **Rivers:** carve the DEM offline with a new `tools/carve_rivers.py` (back up `region_height.png` to `tools/cache/`
  first) **and** make `RiverMesh` drape-fallback so the game still works without the rebuilt PNG.
- **Industry / docks data:** hand-authored, generated deterministically by `tools/make_industry_1940.py`
  (commit the script *and* the JSON).
- **Delivery gate:** NO export, NO version bump, NO `gh release` until **every** phase is verified. The single
  export + zip + release happens only in Phase 6.

## Baseline (verified by the orchestrator at HEAD `9f82b96`, program start)
- `<godot> --headless --path F:/ww2_dlss --import --quit` → exit 0, ~9 s.
- `<godot> --headless --path F:/ww2_dlss scenes/tests.tscn` → **`TESTS OK (617 passed, 0 failed)`**. N must stay ≥ 617.
- `python3 tools/validate_data.py` → `RESULT: FAIL (1 errors)` — the only error is `roads.json too large (19657 KB)`,
  a stale size guard against the legitimately-large real roads file. A phase may raise that guard (documented) so the
  validator reflects reality; **never** regenerate `roads.json`.
- `data/osm/rivers.json` = 22 lines / 116 pts / 2 KB / `source=fallback`.
- `rasterio` NOT installed (`fetch_landcover.py` cannot run). `requests` + `PIL` installed (`fetch_osm.py` can run).
- **One Godot instance at a time.** Never run two engine processes concurrently. Never run a windowed instance.

## Verification policy (updated)
Per-phase engine runs are **stopped**: `--import`, `scenes/tests.tscn` and the `--no-window --shot` render are slow
(a render run holds a ~2.4 GB process) and now happen **once**, in a single consolidated engine pass at the very end,
after every phase is done. Phase work is otherwise code-complete and statically checked; a phase's engine acceptance
items are deferred to that final pass and marked as deferred in its phase row.

## Engine / commands
`<godot>` = `F:/godot-rtx/bin/godot.windows.editor.x86_64.console.exe`
- Import after adding any `class_name` script: `<godot> --headless --path F:/ww2_dlss --import --quit`
- Tests: `<godot> --headless --path F:/ww2_dlss scenes/tests.tscn` → expect `TESTS OK (N passed, 0 failed)`.
- Runtime check (no errors means empty grep):
  `<godot> --path F:/ww2_dlss --no-window --quit-after 400 -- --skip-menu --air --at=51.49,0.1,900,90 --frames=200 "--shot=tools\shots\x.png" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Invalid|ERROR" | grep -v "signed by NVIDIA"`
- `--shot` / `--logFile` need a NATIVE Windows path (`F:/...` or `F:\...`), never an MSYS `/f/...` path.
  `--shot` needs the **console** exe (headless renders nothing and saves no PNG).

## Codebase map (head start — do not re-explore)
- `scripts/world_populator.gd` — streams all sites: `_register_cities` (L182), `_register_features` (L198),
  `_register_industry` (L243) / `_build_industry` (L254), `_register_targets` (L285), `_register_ports` (L408),
  `_build_city` (L1186) + `_city_skyline` (L1218), `_build_target` (L1314). Constants `TILE`/`SITE_TICK`/budget near L16.
- `scripts/ground/scatter.gd` — `house_mesh(variant)` (L43), `make_town` (L468), `_add_terrace`, `_make_tile_landcover`
  (L665), `tile_landcover_data` (L672, **pure/worker**), `build_tile_nodes` (L762, main thread), `_land`/`_ok` guards.
- `scripts/ground/landmarks.gd` — `build(id)` (L93), `church()`, `windmill()`, `lighthouse()`, `_cathedral()`, `_arch_bridge()`.
- `scripts/world_features.gd` — `PORTS` (26), `build_port` (L91), `build_camp`, `SEA_MARKS`, `build_lightship`, `build_sea_fort`.
- `scripts/ground/ground_structure.gd` — `CONFIG` kinds + `_build_intact` (L76); `create(kind, team, pos, heading)`.
- `scripts/ground/ground_kit.gd` — primitives: `box/cyl/sphere/prism_mesh/combine/box_part/cyl_part`, `mat`,
  `ground_y/raw_y/is_water/water_dir`, `side_at`, `explosion`, `stack_smoke`, `persistent_smoke`, `lp`.
- `scripts/ground/road_mesh.gd` — the ribbon pattern to copy: `ensure_loaded`, `_register_line`, `ways_in_tile`,
  `build_tile` (L226), `_add_line` (L271), `prepare_block`/`near_road`, `add_exclusion_box/disc`.
- `scripts/ground/transport_network.gd` — `roads`/`rails`/`sea_lanes`, `routes_near(kind,pos,max_dist)`.
- `scripts/land_cover.gd` — `class_at(x,z)` (class 50 = built-up), `urban_mask()`.
- `shaders/terrain.gdshader` — painted rivers L204-219, lakes L220-229; `project.godot [shader_globals]` holds globals.
- `tools/fetch_osm.py` — LAYERS table (L41), `RIVERS_FB` (L301), `fallback_rivers` (L332), dispatch (L395).
- `tools/validate_data.py`, `tools/validate_missions.py`, `tools/README.md`, `tools/make_landcover` (needs rasterio).
- `tools/tests.gd` → `scenes/tests.tscn`; `_check(ok, what)` style; the runner quits non-zero on any failure.

## Conventions / traps
- TABS, statically-typed GDScript. Never re-implement `WorldCoords.latlon_to_world` / `world_to_latlon`.
- Adding a `class_name` script ⇒ run `--import` before anything else uses it.
- Per-tile scatter split: `Scatter.tile_landcover_data()` is **pure** (worker thread; call `RoadMesh.prepare_block()`
  on that thread first) → `Scatter.build_tile_nodes()` on the main thread. New per-tile builders follow this.
- Deterministic: seed every site from `hash(id)` so a streamed rebuild is identical.
- Procedural low-poly toon only; no photo textures; any new data source must be attributed in `ATTRIBUTION.md`.
- Do NOT run `tools/build_locations.py` (drops hand-added targets). Do NOT regenerate `roads.json`.
- Kent/Pas-de-Calais synthetic roads and the synthetic NE-area rails/coast/woods are **accepted** — not bugs, not TODOs.
- Keep `Scatter.field_edge()` in sync with `shaders/terrain.gdshader` if the field pattern ever changes.

## Phase board
| # | Phase | State |
|---|-------|-------|
| 0 | Data foundation (rivers + curated industry/docks/landmark data) | DONE — `validate_data.py` PASS (0 errors); rivers.json 6508 lines / 8589 km (source=overpass: 9 cached tiles merged + 45 fallback fills for uncached tiles), 467 KB; industry_1940 73 sites, docks_1940 34 docks + 18 piers; `cities[].landmark` filled for 44 cities (+1 fix), 28/28 landmark feature rows present; raised the roads size guard (19.6 MB real file now passes — roads.json untouched) |
| 1 | Real rivers (RiverMesh + river shader + DEM carve + gate painted rivers) | CODE DONE — `river_mesh.gd` + `river.gdshader` + `tools/carve_rivers.py` (DEM 158635 cells lowered, backup kept) + `real_rivers` gate + scatter guards wired; **engine verification DEFERRED to the final consolidated pass** (per-phase exe runs stopped) |
| 2 | Town fabric v2 (streets, districts, waterfront orientation) | CODE DONE — `Scatter.make_town()` rewritten street-driven via new `Scatter.town_layout()`: terraces run ALONG each real street (`RoadMesh.routes_in_rect()` → street tangents in short runs), breaking at junctions (`_near_junction`) and street ends, yaw from the local street (not one town yaw); the legacy jittered grid is kept as the fallback when no street covers the town (synthetic-fallback areas). Districts by radius + `size` (`_band_for`: commercial core / inner terraces / suburban semis-cottages / industrial fringe), civic core for `size>=3` (market square + town hall + railway station snapped to `TransportNetwork.routes_near("rails",…)`). Waterfront (`_town_water` + `_river_block`): the nearest rows face the water and are thinned to a quay edge, houses kept out of the channel. New `house_mesh(8)=cinema`, `house_mesh(9)=station front` (0-7 unchanged). `--city-test` added to `main.gd` (id/size/streets/houses/longest run/core/suburb/industrial/civic/waterfront). **Engine verification DEFERRED to the final consolidated pass** (per-phase exe runs stopped) |
| 3 | Piers & docks (pleasure pier, dock basin, dry dock/shipyard, river quay, fishing harbour) | CODE DONE — 5 typed builders added to `world_features.gd` (`build_pleasure_pier`, `build_dock_basin`, `build_drydock_shipyard`, `build_river_quay`, `build_fishing_harbour`), all reusing `GroundKit` primitives + `GroundShip` for moored hulls; `world_populator.gd` `_register_docks()` reads `data/docks_1940.json` (18 piers + 34 docks = **52 sites**) and dispatches on kind via `_build_dock()`, each snapped to the nearest shoreline point (`Scatter.find_shore`, shared `_nearest_shore` helper) with a site exclusion + RoadMesh disc; `_build_port()` now routes size≤1 → fishing harbour, the estuary harbours (honfleur/etaples/rye_harbour/newhaven) → river quay and the dockyards (portsmouth/sheerness/cherbourg) → drydock/shipyard (3.3); `ground_structure.gd` `_build_port()` delegates to `WorldFeatures.build_port` (`_rebase_world` cancels the node transform so target- and site-ports look the same) + new `dock_basin`/`drydock` CONFIG kinds; `--dock-test` added to `main.gd` (builds one of each type, prints mesh/ship counts). Static-only (engine runs stopped); **engine verification DEFERRED to the final consolidated pass** |
| 4 | Industry v2 (gasworks, colliery, mill, brewery, power station, shipyard, yards) | CODE DONE — new `scripts/ground/industry_kit.gd` (`class_name IndustryKit`) with one static builder per kind in `data/industry_1940.json` — **12/12 kinds** (gasworks/colliery/mill/brewery/power_station/shipyard/dockyard/goods_yard/engine_shed/waterworks/cement_works/staithes), all from `GroundKit` primitives; `build(kind,pos,yaw,size,team,seed,with_smoke=true)` returns a `build_camp`-style container, chimney tops collected into a `ChimneySmokes` node, plus `build_siding(site,rail_pt,seed)` (ballast + rails + sleepers). `world_populator.gd` `_register_industry()` now reads `res://data/industry_1940.json` (**73 in-bounds sites registered**), orients each along the nearest rail (`_nearest_rail` over `TransportNetwork.rails`) / river (`_nearest_river_dir`, read-only over `RiverMesh.lines`) and draws a siding stub (`RoutePath.from_points([pos, rail_pt])` stored on the site); legacy `INDUSTRY` clusters kept as the JSON-missing fallback (`_register_industry_legacy`/`_build_industry_legacy`); `industry_sites` still populated (now with `kind`/`size`). `ground_structure.gd`: new CONFIG + `_build_intact` kinds gasworks/colliery/goods_yard/engine_shed (destructible raid targets, via `_rebase_world(IndustryKit.build(...))`), added to `INDUSTRIAL`; `_build_target()` maps factory/rail_yard/oil_depot targets to the richer shapes where the name matches (gas/collier/goods/marshalling/shed) + a new `oil_depot` type case. `main.gd` `--industry-test` builds one of each kind + a siding and prints mesh/emitter counts and the registered-site count. **Engine verification DEFERRED to the final consolidated pass** (per-phase exe runs stopped; no engine launched) |
| 5 | Landmarks & city skylines (new ids + wire `cities[].landmark`) | DONE (code; engine verify deferred) — **5.1** all 42 `data/landmarks_1940.json` ids now have a `features[type=landmark]` row in `data/locations.json` (28 existing kept → **70 rows, unique**; the features landmark id set is **identical** to the 70 `Landmarks.build()` case ids; 378 lines added / 0 deleted, no key reorder; `build_locations.py` NOT run). **5.2** `world_populator.gd` `_build_landmark()` pins sea landmarks to y=0 via `_landmark_at_sea()` (kinds `docks`/`harbour_works`/`pier` from the json — london_docks, dover_admiralty_pier, chatham_dockyard, ramsgate_harbour, antwerp_docks, zeebrugge_mole, rotterdam_maashaven, ostend_harbour — plus the existing `eddystone`/`needles`/`arromanches_mulberry`), and `_landmark_heading()` gives the sea works a rotation (pier along the sea direction, breakwater/mole/dock wall along the shore); tower_bridge/big_ben keep 90°. **5.3** `_register_cities()` passes the feature index (`lm`) + json lat/lon index to `_build_city()`, which now consumes `cities[].landmark` in `_city_landmarks()`: semicolon names → landmark id (exact / substring / alias / word-overlap), a landmark that already has a features row is left to its streamed `lm_<id>` site (no double placement), only an absent row is placed per-city at its own json lat/lon. **5.4** `--landmark-test` added to `main.gd` (builds every id from the json + the features rows, tallies pass/fail, flags null or 0-mesh). Static-only; **engine verification DEFERRED to the final consolidated pass** (no engine launched) |
| 6 | Integration, tests, perf, docs, export + release | CODE DONE (6.1 tests, 6.2 perf, 6.3 docs) — `tools/tests.gd` gains `_test_data_files()` / `_test_river_data()` / `_test_landmarks_all()` / `_test_house_variants()` / `_test_industry_kinds()` (deterministic, `_check` style; called from `_ready`, exit-code behaviour kept; statically verified — tabs, balanced brackets, every referenced symbol exists). PERF NOTES section added below (budgets UNCHANGED). SPEC.md + HANDOFF.md + README.md + ATTRIBUTION.md updated. **Export, `project.godot` version bump and `gh release` NOT done** — deferred to the single final consolidated engine pass per the owner rule. |

| 7 | Exact OSM coastline (vector land/sea mask + chalk cliffs) | DONE — new `tools/make_coast_mask.py` rasterises the OSM land polygons (`land-polygons-split-4326.zip`, 873,494 polygons, cached in `tools/cache/`) into `data/heightmap/region_coast.png` (L8, **7680x3616 ≈ 126 m/px, 0.26 MB**; supersampled x2 + 0.7 px blur → smooth 1-2 px edge) + `region_coast_meta.json` (unique `uid 875431800ff4e17a…e14b3`); **8/8 geography checks pass** (Poole Harbour sea, Brownsea land, IoW land, Dover land, London land, mid-Channel sea, Poole Bay sea, Bournemouth land). `scripts/height_field.gd` now loads it and uses it as the **authoritative** land/sea decision (`_mask_elev`, bilinear 0..255): m>=0.5 = land (elevation from the DEM, min ~1 m), m<0.5 = sea (`_sea_depth` now driven by a distance-to-land grid built from the MASK, not the DEM); land ramps to its DEM height over `COAST_RAMP_M`=110 m, narrowed to `CLIFF_RAMP_M`=55 m inside the chalk `cliff_zones` **only where the DEM land is already high** (cliff-top sampled around the cell to beat the coarse DEM's coast offset) so Dover/Seven Sisters/Blanc-Nez/Etretat read as faces. Graceful fallback to the old DEM cubic-B-spline path when the mask is absent (**verified**: `WARNING: HeightField: … not found - coastline falls back to the DEM B-spline path`). Engine pass: `--import` exit 0; `scenes/tests.tscn` → **`TESTS OK (636 passed, 0 failed)`**; renders `tools/shots/poole_coast.png` (4.9 MB), `bournemouth_coast.png` (2.7 MB), `dover_coast.png` (2.3 MB) all load the mask + a before/after pair. Old-vs-new land/sea classification over Poole differs on **7.3 %** of sampled cells (9.4 % at Dover): the old DEM mask showed Poole Harbour as a narrow notch, the mask shows the full basin with Brownsea Island. |

| 8 | Real chalk cliffs (skirt geometry) + sharper DEM (z10) | DONE — new `scripts/ground/cliff_skirt.gd` (`class_name CliffSkirt`): both the DEM (~150 m/px) and the coast mask (~126 m/px) are too coarse to hold a ~100 m face, so `TerrainChunkManager._build_arrays()` calls `CliffSkirt.build_chunk()` per tile — a marching-squares contour of the mask 0.5 line inside the 5 chalk `cliff_zones`, emitting quads from y=-6 up to the DEM cliff-top (`HeightField.cliff_top_m_w`, the ring max that beats the DEM's own coast offset) where the inland land is >=20 m; the terrain material's chalk zones paint them. `HeightField.CLIFF_RAMP_M` 55→25 so the land behind reaches the cliff top within ~1 mask px. Renders `tools/shots/cliff_dover.png` + `cliff_seven_sisters.png` (3840x2160) both show a white near-vertical chalk face above the water (orchestrator to vision-inspect). DEM re-fetched at **z10 6144x3000** (`make_heightmap.py --zoom 10 --width 6144 --height 3000`; source "AWS terrain tiles (terrarium) z10"), pristine copied to `tools/cache/region_height_pre_rivers.png`, re-carved (`carve_rivers.py`, 7.43 % cells lowered) and `make_urban_mask.py` re-run. `--import` exit 0; `scenes/tests.tscn` → **`TESTS OK (636 passed, 0 failed)`**; `validate_data.py` → PASS (0 errors). Perf (cold first load): `start_game` t=12.87 s (z9) → 19.77 s (z10) = **1.54x** (<2x); `[mem]` start 790→816 MB, after 25 s **1109→1136 MB (+27 MB**, <100 MB); FPS 33→34. Hills sharper: mean slope North Downs 1.39°→1.74°, Weald 1.41°→2.09°, Ardennes 2.17°→3.10° (`tools/shots/hills.png` vs `hills_z9.png`). |

Mark a phase **DONE** here, with its verifying numbers, as part of finishing it.

## PERF NOTES (Phase 6.2 — static review, no engine)
Budgets are UNCHANGED: `SITE_TICK`/`SITE_BUDGET`/`TILE_BUDGET` (`world_populator.gd` L18-20), the 6 ms/tick site cap (L860), and the worker-thread tile split (`_start_tile_job` → `Scatter.tile_landcover_data`; main-thread `_finish_tile`). Obvious cost increases to watch:
- **RiverMesh in the tile path:** `_make_tile`/`_start_tile_job` now call `RiverMesh.prepare_block` (rasterises river cells in the tile + 40 m margin into a 10 m cell set) and `_finish_tile`/`_make_tile` call `RiverMesh.build_tile` (per-line miter normals + ~30 m ribbon pieces + one `ground_y` sample per piece). It rides the existing worker/main split, so the worker pass grows and each river-crossed tile gains one `MeshInstance3D`. `near_river` stays a single hash lookup per scatter candidate.
- **Rivers data much bigger:** `data/osm/rivers.json` is now ~1.8 MB / ~15.5k lines (baseline was 22 fallback lines); `RiverMesh.ensure_loaded()` parses and cell-indexes all of it once at startup → first-load growth.
- **`_nearest_river_dir` is O(all river points):** `world_populator.gd` L325 walks every `RiverMesh.lines` point per call, and it runs at registration per industry site that has no rail (`_industry_yaw`). Registration-time only, but with ~15.5k lines this is the heaviest new registration loop (compare `_nearest_rail`, also O(all rails) per site).
- **More streamed sites:** +73 industry (`ind_*`) and +52 docks (`dock_*`) added to `_sites`; the `_stream_sites` descriptor loops are unchanged but `want` is longer, so settling after a teleport/`_warm_up` (which builds up to 8 nearest sites synchronously) does more work. `dock_*` build-time `Scatter.find_shore` is per-site, not per frame.
- **Towns:** street-driven `make_town` samples `RoadMesh.routes_in_rect()` per town at build time; the district/civic additions are build-time node-count growth inside the existing per-tile scatter (no new per-frame cost).

What the final consolidated engine pass must measure (compare to the HEAD envelope: ~230 MB CPU at start / ~350 MB after 25 s; first load 5 s, replay 1.5 s):
- `--loadprof` — first-load and replay timing (the 1.8 MB river parse/index + the `_nearest_river_dir` registration show here).
- `--mem-test` — CPU/VRAM envelope (new per-tile river meshes + more sites).
- `--turn-test` — max frame time (main-thread `_finish_tile` now also builds a river ribbon; teleport/`_warm_up` builds more).
- `--river-test` / `--city-test` / `--dock-test` / `--industry-test` / `--landmark-test` — build/print counts (confirm the systems run; not timings).
If `--turn-test`/`--loadprof` regress, ordered mitigations: drop the thinnest river class (`stream`, already min-length gated) first, then cache the river cell index used by `_nearest_river_dir`. **Do NOT change `SITE_BUDGET`/`TILE_BUDGET` without a measurement.**
