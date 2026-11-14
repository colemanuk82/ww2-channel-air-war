# PROGRAM-STATUS — 1940s landscape additions

Program brief + full phase specs: **`PROMPT-landscape-additions-1940.md`** (read it in full before starting a phase).
Predecessor program (complete, shipped as v4.0): `PROMPT-cities-towns-1940s.md` + the older `PROGRAM-STATUS.md`.

**Baseline at program start** — HEAD `4f9791f` (v4.0), clean tree except an untracked `.hermes/`.
- Self-tests: `scenes/tests.tscn` → `TESTS OK (636 passed, 0 failed)`. **N must never drop.**
- `python3 tools/validate_data.py` → PASS (0 errors).
- 85 airfields, 85 cities, 195 targets, 92 features in `data/locations.json`.

## Owner decisions (resolved — do NOT re-ask)
- Per-phase engine runs are **stopped**. Phases are code-complete + statically checked; the single
  consolidated engine pass (import + tests + `--<thing>-test` args + renders) happens at the end and is
  owned by the parent. **A child must never launch the engine** — one instance at a time, never windowed.
- **No export, no `project.godot` version bump, no `gh release`** until every phase is verified *and* the
  user asks. Pre-program artifact state for later checking: `project.godot` mtime 2026-10-09 16:18,
  `build/` holds only the NVIDIA runtime DLLs (2025-12 dates), no release artifact.
- **RELEASE AUTHORISED (owner, 2026-10-09): "build commit and release when complete."** The gate above is
  now satisfied *by completion* — run the full release sequence once EVERY phase (P1-P19) is verified and
  the consolidated pass is green, without needing to ask again. Sequence that works in this repo:
  1. every phase row DONE or explicitly carried as a gap; `python3 tools/validate_data.py` PASS;
  2. consolidated engine pass: `--import` (exit 0, no SCRIPT/Parse errors) then `scenes/tests.tscn`
     (`TESTS OK (N passed, 0 failed)`, N >= 636) then every `--<thing>-test` arg, then a render or two;
  3. bump `config/version` in `project.godot` and note it in HANDOFF/README;
  4. `--import` again, then
     `<godot> --headless --path F:/ww2_dlss --export-release "Windows Desktop" F:/ww2_dlss/build/WW2ChannelAirWar.exe`;
  5. **smoke-test the exported binary itself** (launch it `--no-window` with the debug flags and grep for
     script errors) — an export reporting DONE can still ship a binary that dies on a missing script;
  6. commit source only (explicit paths — never `git add -A`; there is an untracked `.hermes/`), push,
     then `gh release create` with the zipped exe + its NVIDIA runtime DLLs.
  **Decisions resolved (owner, 2026-10-09):** release version = **5.0**; the repo **stays PRIVATE**, so the
  GitHub release is visible to the owner and collaborators only (do not publish it publicly).
- **DEMO VIDEO IN THE README (owner, 2026-10-09): "upload video to readme when complete."** After the
  content is in, capture a fresh demo of the NEW landscape content (dams, decoy sites, canal furniture,
  railway viaducts, airfield furniture, refineries, V-weapon bunkers, sea defences, city barrage balloons,
  pylons) and add it to `README.md` beside the existing two demos. Recipe that works:
  `--no-window --write-movie <x>.avi --fixed-fps 30` plus a game arg set, **including `--shot=<png>`** (that
  is what disables DLSS/frame-gen, without which the offscreen save aborts and no video is written). Two
  traps: every recording carries a fixed **184-frame (6 s) loading-backdrop lead-in**, and the game's
  `--frames` counter ticks ~2x faster than recorded frames, so the gameplay portion is the LAST
  `requested/2` frames. The recorder writes **no audio track** — composite the voice from `assets/voice/`
  and score it from `assets/music/` in ffmpeg. Verify every caption against the actual frames before
  publishing: an earlier cut was rejected because its captions over-claimed (no visible dogfight, no bomb
  release). Commit the repo-sized MP4 + an inline GIF under `docs/demo/` and link both.
- Deliverable ordering named by the owner: sea defences → city balloon barrages → dams (Dam Busters),
  then the rest of the brief in order.

## Engine / commands
`<godot>` = `F:/godot-rtx/bin/godot.windows.editor.x86_64.console.exe`
- Import after adding any `class_name` script: `<godot> --headless --path F:/ww2_dlss --import --quit`
- Tests: `<godot> --headless --path F:/ww2_dlss scenes/tests.tscn` → expect `TESTS OK (N passed, 0 failed)`.
- Data check (cheap, no engine — run this per phase): `python3 tools/validate_data.py` → `RESULT: PASS (0 errors)`.
- `--shot` / `--logFile` need a NATIVE Windows path (`F:/...`), never an MSYS `/f/...`; `--shot` needs the
  console exe (headless renders nothing and saves no PNG). **Do not run these per phase.**

## Conventions / traps
- TABS, statically-typed GDScript. Never re-implement `WorldCoords.latlon_to_world` / `world_to_latlon`.
- Deterministic: seed every site from `hash(id)`.
- Per-tile split: pure worker half (no node creation, no shared-cache writes) → main-thread node building.
- Procedural low-poly toon only (`GroundKit` primitives); no photo textures.
- Real coordinates only, each with a cited source, added to `ATTRIBUTION.md`.
- Do NOT run `tools/build_locations.py`. Do NOT regenerate `data/osm/roads.json`.
- Synthetic fallback roads (Kent tile 21, Pas-de-Calais tile 16) and the synthetic NE-area rails/coast/woods
  are ACCEPTED — not bugs, not TODOs.
- New per-tile builders call `RoadMesh.prepare_block()` / `RiverMesh.prepare_block()` on the worker thread first.

## Phase board
| # | Phase | State |
|---|-------|-------|
| P1 | Sea defences (minefields, booms/nets, blockships, more sea forts, offshore obstacles, sweepers) | CODE DONE (static) — engine pass deferred |
| P2 | Barrage balloons over cities (per-size barrage + winch sites) | CODE DONE (static) — engine pass deferred |
| P3 | Dams for the Dam Busters (Möhne, Eder, Sorpe, Ennepe, Lister, Diemel) — places + targets | CODE DONE (static) — engine pass deferred |
| P3b | Upkeep weapon + Chastise mission (bouncing bomb, low-level run, breach) — **separate follow-on, not implied by P3** | NOT STARTED |
| P4 | Decoy sites (Starfish, Q-sites, K-sites, decoy fires) | CODE DONE (static) — engine pass deferred |
| P5 | Power grid (pylons, overhead lines, telegraph poles) | CODE DONE (static) — engine pass deferred |
| P6 | Canal furniture (locks, aqueducts, basins, wharves, narrowboats) | CODE DONE (static) — engine pass deferred |
| P7 | Railway drama (viaducts, tunnels, junctions, signal boxes, level crossings, turntables, water cranes, coaling stages, goods sheds) | CODE DONE (static) — engine pass deferred |
| P8 | Airfield furniture (dispersal/blast pens, revetments, Nissen camps, T2/T1 hangars, control tower, fuel + bomb dumps, flare path + Chance lights, dummy aircraft) | CODE DONE (static) — engine pass deferred |
| P9 | Oil and fuel (tank farms, refineries, petrol depots, gas holders) | CODE DONE (static) — engine pass deferred |
| P10 | Aircraft industry (plants, shadow factories, dispersal) | CODE DONE (static) — engine pass deferred |
| P11 | V-weapons (ski sites, Heavy Cross bunkers at Wizernes + Eperlecques) | CODE DONE (static) — engine pass deferred |
| P12 | Port clutter (cranes, lock gates, dredgers, barges, tugs, paddle steamers, train ferries) | CODE DONE (static) — engine pass deferred |
| P13 | Rural / Kentish texture (oast houses, hop gardens, orchards, market gardens, drainage mills) | CODE DONE (static) — engine pass deferred |
| P14 | Coastal landmarks (Martello towers, coastguard + RNLI stations, lidos, bandstands, holiday camps) | CODE DONE (static) — engine pass deferred |
| P15 | Civil defence (shelters, ARP posts, sandbagging, camouflage roofs) | CODE DONE (static) — engine pass deferred |
| P16 | Aviation support (seaplane/flying-boat bases, airship stations, kite balloons) | CODE DONE (static) — engine pass deferred |
| P17 | Forestry (plantations, timber camps) | CODE DONE (static) — engine pass deferred |
| P18 | Navigation aids (radio beacons, DF stations, beacon masts, airfield lighting) | CODE DONE (static) — engine pass deferred |
| P19 | Military depth (transit/embarkation camps, ammo depots, vehicle parks, horse columns, tank trains) | CODE DONE (static) — engine pass deferred |

Mark a row **DONE** with its verifying numbers as part of finishing it; mark it **CODE DONE (verify deferred)**
when it is written and statically checked but not yet through the consolidated engine pass.

## Phase detail (this chunk: P1, P2, P3)

### P1 — Sea defences — CODE DONE (static)
- **New files:** `scripts/ground/sea_defence_kit.gd` (`class_name SeaDefenceKit`), `data/sea_defences_1940.json`
  (generated by `tools/make_sea_defences_1940.py`).
- **Kinds:** `minefield` (buoyed moored-mine line), `boom` (anti-submarine boom + hanging steel net with a
  gate), `blockship` (Zeebrugge/Ostend + Gooseberry hulks), `sea_fort` (extra Maunsell/Grain forts, reusing
  `WorldFeatures.build_sea_fort`), `obstacles` (offshore hedgehogs/scaffolding below the tide line), `wreck`
  (marked wreck + wreck buoy). Sweeping trawlers and boom-gate vessels are ambient `GroundShip`s.
- **Hooks:** `world_populator.gd` `_register_sea_defences()` + `_register_sweepers()` (called from `_ready()`
  after `_register_ports()`), builders `_build_sea_defence()` / `_build_sweeper()`; `SeaDefenceKit.build()`.
- **Debug:** `--sea-defence-test` (sites + spanned km + meshes). **Tests:** `_test_landscape_data`,
  `_test_sea_defence_kinds` in `tools/tests.gd`.
- **Verify deferred:** no engine run; meshes checked only by `_mesh_count` in the tests, not rendered.

### P2 — Barrage balloons over cities — CODE DONE (static)
- **Hooks:** `world_populator.gd` static `city_balloon_plan()` / `city_balloon_count()` (pure, deterministic
  from `hash(id)`), instance `_balloon_barrage()` + `_winch_site()`, called from `_build_city()`.
- **Scale:** 4 + size*4 balloons, ×2+6 for London/Thames-Medway/ports (London 96); altitudes 600–1500 m
  (× `WorldCoords.VERTICAL_SCALE`) scaled by size, on 1–3 concentric rings with ground winch sites.
- **Debug:** `--balloon-test`. **Tests:** `_test_city_balloons` (London > size-1 town; count rises with size).

### P3 — Dams — CODE DONE (static)
- **New files:** `scripts/ground/dam_kit.gd` (`class_name DamKit`), `data/dams_1940.json`
  (generated by `tools/make_dams_1940.py`).
- **Structure:** new `GroundStructure.CONFIG["dam"]` kind, `_build_dam()` (curved masonry wall + two valve
  towers + spillway + crest road) and a breached `_build_wreck()` "dam" branch.
- **Scenery:** `DamKit.build(id)` — reservoir that reads as water, powerhouse, spillway apron, the
  anti-torpedo net boom across the reservoir, valley shoulders.
- **Hooks:** `world_populator.gd` `_register_dams()` (called from `_ready()` after `_register_targets()`) +
  `_build_dam()`; dams are `_target_info` mission targets and added to `raid_targets()`.
- **Debug:** `--dam-test`. **Tests:** `_test_dams_build` (every id builds a wall + scenery with ≥ 1 mesh).
- **P3 delivers the PLACES and the destructible targets only.** The Upkeep bouncing bomb, the low-level
  Chastise run and the breach event are a **separate follow-on (P3b)** — NOT playable after this chunk.

## Phase detail (this chunk: P4, P5, P6)

### P4 — Decoy sites — CODE DONE (static)
- **New files:** `scripts/ground/decoy_kit.gd` (`class_name DecoyKit`), `data/decoys_1940.json`
  (generated by `tools/make_decoys_1940.py`).
- **Kinds:** `starfish` (Starfish / SF decoy town — building silhouettes, oil-drum fire baskets,
  light arrays, control bunker), `qf_site` (QF fire decoy: banks of burners + control bunker),
  `q_site` (Q night-light decoy: flare path of lamp poles + glow boxes + shelter),
  `k_site` (K day dummy airfield: cleared strip, dummy aircraft, dumps, ring track).
- **Structure:** new `GroundStructure.CONFIG["decoy"]` kind (`_build_decoy`: a fake shadow factory
  silhouette so a strike reads as a hit on a real works) + a wrecked `decoy` branch (burnt frame + smoke).
  Decoys are registered in `_target_info` with `type:"decoy"` and added to `raid_targets()`, so an Axis
  raid **can be wasted on one**.
- **Hooks:** `world_populator.gd` `_register_decoys()` (called from `_ready()` after `_register_dams()`)
  + `_build_decoy()`; `DecoyKit.build(kind, pos, heading_deg, size, seed)`. Sites are `Allies`
  (`side_at`), streamed, and seeded from `hash(id)`.
- **Data provenance:** 11 real, documented sites — see `data/decoys_1940.json` `_note` and `ATTRIBUTION.md`.
  Sources: Suffolk Heritage Explorer (RMS 042 Shottisham, HLY 098 Hollesley), Historic England Research
  Records (Q42a Nazeing), Airfield Research Group decoy listing (Stambourne/Barley/Cliffe/Luddesdown/
  Grendon/Lullingstone/Bulphan), Heritage Gateway NHER 13606 (Winterton Ness). OSGB grid refs were
  converted to WGS84 with a cited algorithm (OS guide / Helmert OSGB36→WGS84).
- **Debug:** `--decoy-test` (sites + kinds + meshes). **Tests:** `_test_decoy_kinds` in `tools/tests.gd`.
- **Verify deferred:** no engine run; meshes checked only by `_mesh_count`, not rendered.

### P5 — Power grid (1927–35 National Grid pylons + overhead lines + telegraph poles) — CODE DONE (static)
- **New files:** `scripts/ground/pylon_mesh.gd` (`class_name PylonMesh`), `data/pylons_1940.json`
  (curated period-grid fallback, generated by `tools/make_pylons_1940.py`).
- **Fetch:** `tools/fetch_osm.py` gains a `power` layer (`way["power"="line"]`, simplified at tol 0.004,
  voltage recorded per line, `fit_size` drops < 132 kV lines); it was fetched for real over Overpass into
  `data/osm/power.json` (`_source.json` -> `"power":"overpass"`).
- **Runtime:** `PylonMesh.ensure_loaded()` drapes the overhead line as a narrow dark ribbon at ~26 m above
  ground (RiverMesh pattern) and instances a lattice pylon mesh every ~275 m (the period 132 kV span) at the
  tower nodes, plus telegraph poles every ~65 m along the real road routes (`RoadMesh.ways_in_tile`).
  Lines below 132 kV are skipped. `data/osm/power.json` (overpass) is preferred; `data/pylons_1940.json`
  is the curated period-grid fallback when the fetch is absent.
- **Hooks:** `world_populator.gd` `ensure_loaded()` in `_ready()`; `PylonMesh.build_tile(org, TILE)` added to
  `_finish_tile()` and `_make_tile()` beside `RoadMesh`/`RiverMesh`.
- **Debug:** `--pylon-test` (lines, km, pylons, poles). **Tests:** `_test_pylon_data` + `_test_pylon_build`.
- **Simplification:** OSM `power=tower` nodes are **not** fetched separately (the line layer captures only
  ways); pylon positions are sampled along each line at the documented ~275 m span. Recorded as a gap.

### P6 — Canal furniture — CODE DONE (static)
- **New file:** `scripts/ground/canal_kit.gd` (`class_name CanalKit`).
- **Data:** reuses `data/osm/rivers.json`; filters `k=="canal"` (8,491 canal lines are already on disk —
  no new fetch, no re-derivation of canals).
- **Furniture:** `lock` (+ `lock_cottage`), `aqueduct` (where a canal crosses a real river line),
  `basin` (at canal junctions), `wharf`, `dry_dock`, `canal_industry`, `narrowboat` and `barge` moored
  alongside — placed along the canal centrelines with terrain-aware spacing, deterministic per line/step.
- **Hooks:** `world_populator.gd` `ensure_loaded()` in `_ready()`; `CanalKit.build_tile(org, TILE)` added to
  `_finish_tile()` and `_make_tile()`.
- **Debug:** `--canal-test`. **Tests:** `_test_canal_furniture`.

## Phase detail (this chunk: P7, P8, P9)

### P7 — Railway drama — CODE DONE (static)
- **New files:** `scripts/ground/rail_kit.gd` (`class_name RailKit`), `data/rail_drama_1940.json`
  (generated by `tools/make_rail_drama_1940.py`).
- **Terrain-derived:** `rails.json` has no bridge/tunnel tags, so `RailKit.build_tile` derives them — a rail
  point whose ground is > 7 m below both ~90 m shoulders is carried on a **viaduct** (deck at the shoulders,
  piers down into the dip); a point > 7 m above both shoulders becomes a **tunnel portal** (stone face +
  hillside). Curated famous ones are pinned separately (below).
- **Line furniture:** junctions (another rail line within ~95 m), level crossings (a real road within ~26 m via
  `RoadMesh.ways_in_tile`), plus signal boxes, water cranes, coaling stages, goods sheds and turntables on a
  deterministic 720 m cadence along every real rail line.
- **Curated:** 8 famous viaducts/tunnels at cited WGS84 positions, built by `RailKit.build_catalog`.
- **Hooks:** `world_populator.gd` `RailKit.ensure_loaded()` in `_ready()`; `_register_rail_drama()` in the
  `_ready()` register block + `_build_rail_drama()`; `RailKit.build_tile(org, TILE)` added to `_finish_tile()`
  and `_make_tile()`.
- **Debug:** `--rail-test`. **Tests:** `_test_rail_drama`.
- **Verify deferred:** no engine run; meshes counted only, never rendered.

### P8 — Airfield furniture — CODE DONE (static)
- **New file:** `scripts/ground/airfield_furniture.gd` (`class_name AirfieldFurniture`); new meshes in
  `scripts/ground/airfield_assets.gd` (`t2_hangar`, `t1_hangar`, `revetment`, `chance_light`, `dummy_aircraft`).
- **Furniture:** dispersal/blast pens (earth revetment arcs round the dispersal pads), a flank revetment line,
  a Nissen-hut camp + water tower, rows of T2 and T1 hangars, a two-storey **watch office**, a fuel dump (tanks)
  and a bomb dump (earth-banked stacks) as destructible `AirfieldProp` clusters, a **flare path** of Chance
  lights, and dummy aircraft — all at |x| ≥ 110 m in the airfield frame, clear of the runway.
- **Hook:** `AirfieldFurniture.dress(...)` called once per airfield in `_build_airfield()` (all 85 layouts; the
  per-style `_dress_grass_airfield` / `_dress_other_airfield` are unchanged).
- **Debug:** `--airfield-furniture-test`. **Tests:** `_test_airfield_furniture`.

### P9 — Oil and fuel — CODE DONE (static)
- **New files:** `scripts/ground/oil_fuel_kit.gd` (`class_name OilFuelKit`), `data/oil_fuel_1940.json`
  (generated by `tools/make_oil_fuel_1940.py`).
- **Kinds:** `refinery`, `oil_depot`, `tank_farm`, `gasworks` (builders also cover `petrol_depot` and
  `gas_holder`). The destructible target **reuses** the existing `GroundStructure` kinds (`refinery` /
  `oil_depot` / `gasworks`, mapped by `WorldPopulator._oil_structure_kind`); `OilFuelKit` builds the works around it.
- **Hooks:** `world_populator.gd` `_register_oil_fuel()` (from `_ready()` after `_register_rail_drama()`) +
  `_build_oil_fuel()`; sites are in `_target_info` with type `"oil"` and added to `raid_targets()`.
- **Data provenance:** 10 real sites — see `data/oil_fuel_1940.json` `_note` and `ATTRIBUTION.md`.
- **Debug:** `--oil-test`. **Tests:** `_test_oil_fuel`.

### Test-harness note (this chunk)
- `tools/tests.gd` now installs a tiny flat **test terrain** (`class TestTerrain`, group `"terrain"`) at the
  start of `_ready()`: the headless `scenes/tests.tscn` shipped with no terrain node, so `GroundKit.raw_y` was
  0 everywhere and the tile-based builders (canal **and** railway) would have placed nothing — a latent P6 issue
  this also repairs.

## Phase detail (this chunk: P10, P11, P12)

### P10 — Aircraft industry — CODE DONE (static)
- **New files:** `scripts/ground/aircraft_industry_kit.gd` (`class_name AircraftIndustryKit`),
  `data/aircraft_industry_1940.json` (generated by `tools/make_aircraft_industry_1940.py`).
- **Kinds:** `shadow_factory`, `assembly_plant`, `engine_works`, `dispersal_site`, `aircraft_depot` — multi-bay
  assembly/flight sheds with roof monitors, T2/T1 hangars (reusing the shared `AirfieldAssets` meshes),
  dispersal/blast pens with dummy aircraft, machine shops, foundry + open-air test-bed cells, chimneys, water
  tower and a works flag.
- **Structure:** the destructible target **reuses** the existing `GroundStructure("factory")` kind; the site is
  registered in `_target_info` with type `"aircraft"` (added to the `raid_targets()` type list).
- **Hooks:** `world_populator.gd` `_register_aircraft_industry()` (from `_ready()` after `_register_oil_fuel()`)
  + `_build_aircraft_industry()`.
- **Data provenance:** 13 real, cited sites (Castle Bromwich, Woolston/Supermarine, Banner Lane + Baginton
  Coventry, Filton, Brooklands, Hatfield, Yeovil, Salisbury Hall, Longbridge, Ryton, Radlett, Kemble) — see
  `data/aircraft_industry_1940.json` `_note` and `ATTRIBUTION.md`.
- **Debug:** `--aircraft-industry-test` (sites + kinds + meshes). **Tests:** `_test_aircraft_industry`.
- **Verify deferred:** no engine run; meshes counted only, never rendered.

### P11 — V-weapons — CODE DONE (static)
- **New files:** `scripts/ground/v_weapons_kit.gd` (`class_name VWeaponsKit`), `data/v_weapons_1940.json`
  (generated by `tools/make_v_weapons_1940.py`).
- **Kinds:** `ski_site` (curved-end "ski" storage buildings, inclined launch ramp with a V-1 on its trolley,
  assembly shed, non-magnetic building, store bunker, light flak, hut line), `supply_depot` (a mound with tunnel
  portals + a rail spur), `heavy_cross` (the approach cutting, quarry bench, rail spur, power house and store
  around the giant dome).
- **Structure:** the destructible target **reuses/extends** the existing `GroundStructure("v1_site")` kind — the
  standard ramp branch for a ski site/depot, the `variant = "dome"` big-bunker branch for a Heavy Cross site.
  Registered in `_target_info` with type `"v1_site"` (already a raid-target type).
- **Hooks:** `world_populator.gd` `_register_v_weapons()` (from `_ready()` after `_register_aircraft_industry()`)
  + `_build_v_weapons()`.
- **Data provenance:** 13 sites (9 V-1 "ski" sites/depots at their documented localities, 2 V-1 storage depots,
  the 2 Heavy Cross bunkers) — see `data/v_weapons_1940.json` `_note` and `ATTRIBUTION.md`.
- **Debug:** `--v-weapons-test`. **Tests:** `_test_v_weapons`.
- **Verify deferred:** no engine run; meshes counted only, never rendered.

### P12 — Port clutter — CODE DONE (static)
- **New files:** `scripts/ground/port_clutter_kit.gd` (`class_name PortClutterKit`),
  `data/port_clutter_1940.json` (generated by `tools/make_port_clutter_1940.py`).
- **Kinds:** `crane`, `lock_gate`, `dredger`, `hopper_barge`, `tug`, `paddle_steamer`, `train_ferry`. Moored /
  working vessels are real `GroundShip` hulls (the same hulls the harbours moor) with extra toon superstructure
  (bucket ladder, hopper coaming, paddle boxes, linkspan + rail wagons).
- **Hooks:** `world_populator.gd` `_register_port_clutter()` (from `_ready()` after `_register_docks()`) +
  `_build_port_clutter()`, snapping each site to its nearest shore (like `_build_port`). The two train-ferry
  terminals additionally lay a moving `GroundShip("ferry")` across the Channel via `_register_train_ferry_lane()`
  / `_build_port_ferry()`.
- **Data provenance:** 23 real berths/ports — see `data/port_clutter_1940.json` `_note` and `ATTRIBUTION.md`.
- **Debug:** `--port-clutter-test`. **Tests:** `_test_port_clutter`.
- **Verify deferred:** no engine run; meshes/ships counted only, never rendered.

## Phase detail (this chunk: P13, P14, P15)

### P13 — Rural / Kentish texture — CODE DONE (static)
- **New files:** `scripts/ground/rural_kit.gd` (`class_name RuralKit`), `data/rural_1940.json`
  (generated by `tools/make_rural_1940.py`; 30 sites, 6 kinds).
- **Kinds:** `oast_house` (brick roundel + white conical cowl + weatherboarded stowage barn, one or two kilns),
  `hop_garden` (wire-strung grid of hop poles + headland + pickers' hut), `orchard` (rows of standards on
  mown grass + windbreak hedge), `market_garden` (glasshouses under prism roofs + cloche beds + packing shed),
  `drainage_mill` (tarred smock tower, boat-shaped cap, four sails, scoop wheel + drain leat), `sheep_fold`
  (dry-stone pen + hurdles race + sheep + shepherd's hut).
- **Hooks:** `world_populator.gd` `_register_rural()` (from `_ready()` after `_register_v_weapons()`) +
  `_build_rural()`; each site is `_add_site("rural_" + id, pos, 6800.0, _build_rural, {...})`, non-destructible
  scenery, seeded from `hash(id)`.
- **Data provenance:** 30 real, cited places — see `data/rural_1940.json` `_note` and `ATTRIBUTION.md`
  (Wikipedia per-place articles + *Hops* / *Oast house*).
- **Debug:** `--rural-test` (sites + kinds + meshes). **Tests:** `_test_rural`.
- **Verify deferred:** no engine run; meshes counted only, never rendered.

### P14 — Coastal landmarks — CODE DONE (static)
- **New files:** `data/coastal_landmarks_1940.json` (generated by `tools/make_coastal_landmarks_1940.py`;
  22 sites, 6 kinds). Six **new `landmarks.gd` `build()` ids**: `martello_tower`, `coastguard_station`,
  `lifeboat_station`, `lido`, `bandstand`, `holiday_camp` (new helper builders `_martello` /
  `_coastguard_station` / `_lifeboat_station` / `_lido` / `_bandstand` / `_holiday_camp`). The `_b` box helper
  gained an optional `outline` parameter (backward compatible). The six ids are also documented in
  `data/landmarks_1940.json`.
- **Hooks:** `world_populator.gd` `_register_coastal_landmarks()` (from `_ready()` after `_register_rural()`) +
  `_build_coastal_landmark()`; each site is `_add_site("coastlm_" + id, pos, 6600 + 400*size, ...)`, builds its
  `Landmarks.build(kind)` id on the ground with a deterministic heading from `hash(id)`.
- **Data provenance:** real, cited seaside landmarks (Martello towers, HM Coastguard, RNLI, Saltdean/Tinside
  lidos, Eastbourne bandstand, Butlin's Clacton/Dovercourt + Corton holiday camps) — see
  `data/coastal_landmarks_1940.json` `_note` and `ATTRIBUTION.md`.
- **Debug:** `--coastal-landmark-test` (sites + kinds + meshes). **Tests:** `_test_coastal_landmarks`.
- **Verify deferred:** no engine run; meshes counted only, never rendered.

### P15 — Civil defence — CODE DONE (static)
- **New files:** `scripts/ground/civil_defence_kit.gd` (`class_name CivilDefenceKit`),
  `data/civil_defence_1940.json` (generated by `tools/make_civil_defence_1940.py`; 17 sites, 4 kinds).
- **Kinds:** `surface_shelter` (low brick box + flat blast slab + earth bank + baffled entrance),
  `anderson_shelter` (sunk earth-mounded corrugated garden shelter + sandbagged entrance), `arp_post`
  (control hut, look-out slit, sign board, sandbag revetment, alarm post), `sandbagged_building` (a small
  civic building with sandbags banked against the ground floor and a blast wall at the door).
- **Camouflage roofs:** `CivilDefenceKit.camouflage_roof(pos, heading, size, seed)` lays a disruptive CVD paint
  pattern over a works footprint; driven **off the existing industry and aircraft-industry sites** by
  `WorldPopulator._camouflage_industry()`, called from `_build_industry()` and `_build_aircraft_industry()`
  (no data rows, exactly as the brief requires).
- **Hooks:** `world_populator.gd` `_register_civil_defence()` (from `_ready()` after
  `_register_coastal_landmarks()`) + `_build_civil_defence()`; `_camouflage_industry()` in the two builders.
- **Data provenance:** real, cited civil-defence provision (Ramsgate/Dover/Canterbury/Hastings/Maidstone
  shelters, London Anderson-shelter districts, Westminster/East End ARP posts, the sandbagged Bank of
  England) — see `data/civil_defence_1940.json` `_note` and `ATTRIBUTION.md`.
- **Debug:** `--civil-defence-test` (sites + kinds + meshes + a camouflage roof). **Tests:** `_test_civil_defence`.
- **Verify deferred:** no engine run; meshes counted only, never rendered.

## Phase detail (this chunk: P16, P17, P18, P19)

### P16 — Aviation support — CODE DONE (static)
- **New files:** `scripts/ground/aviation_support_kit.gd` (`class_name AviationSupportKit`),
  `data/aviation_support_1940.json` (generated by `tools/make_aviation_support_1940.py`; 15 sites, 3 kinds).
- **Kinds:** `seaplane_base` (a Sunderland station: an inclined slipway to the water, a concrete apron,
  T2 hangars, a control/watch office, beaching crane, mooring buoys and a moored flying boat), `airship_station`
  (a long airship shed with big doors + curved roof, a tall lattice mooring mast with a gantry, a hydrogen/gas
  store, a windbreak and a hut line) and `kite_balloon_site` (a balloon shed, a winch lorry, an apron and
  `BarrageBalloon` kite balloons on cables).
- **Hooks:** `world_populator.gd` `_register_aviation_support()` (from `_ready()` after `_register_civil_defence()`)
  + `_build_aviation_support()`; `AviationSupportKit.build(kind, pos, heading_deg, size, seed)`.
- **Data provenance:** real, cited seaplane/flying-boat stations (Calshot, Mount Batten, Felixstowe, Hamble,
  Lee-on-Solent, Poole, Southampton Water), airship stations (Pulham, Cardington, Kingsnorth, Capel, Wormwood
  Scrubs) and Balloon Command centres — see `data/aviation_support_1940.json` `_note` and `ATTRIBUTION.md`.
- **Debug:** `--aviation-test` (sites + kinds + meshes). **Tests:** `_test_aviation_support`.
- **Verify deferred:** no engine run; meshes counted only, never rendered.

### P17 — Forestry — CODE DONE (static)
- **New files:** `scripts/ground/forestry_kit.gd` (`class_name ForestryKit`),
  `data/forestry_1940.json` (generated by `tools/make_forestry_1940.py`; 12 sites, 2 kinds).
- **Kinds:** `plantation` (a Forestry Commission conifer plantation: rows of conifers on a grid with a firebreak,
  a boundary ditch/fence and a forester's hut) and `timber_camp` (a wartime timber camp: Nissen-hut lines, a
  sawmill with a saw bench, timber + pit-prop stacks, a loading ramp and a narrow-gauge tramway).
- **Hooks:** `world_populator.gd` `_register_forestry()` (from `_ready()` after `_register_aviation_support()`)
  + `_build_forestry()`; `ForestryKit.build(kind, pos, heading_deg, size, seed)`.
- **Data provenance:** real Forestry Commission forests and wartime timber-camp localities (Thetford Chase,
  Alice Holt, Cannock Chase, New Forest, Ashdown, Bedgebury, Savernake, Breckland/Brandon …) — see
  `data/forestry_1940.json` `_note` and `ATTRIBUTION.md`.
- **Debug:** `--forestry-test` (sites + kinds + meshes). **Tests:** `_test_forestry`.
- **Verify deferred:** no engine run; meshes counted only, never rendered.

### P18 — Navigation aids — CODE DONE (static)
- **New files:** `scripts/ground/navigation_aid_kit.gd` (`class_name NavigationAidKit`),
  `data/navigation_aids_1940.json` (generated by `tools/make_navigation_aids_1940.py`; 14 sites, 4 kinds).
- **Kinds:** `radio_beacon` (a radio-range beacon: a guyed mast + transmitting hut on a circular earth mat),
  `df_station` (a direction-finding station: a four-mast Adcock aerial array on a circular earth mat with a
  central operator hut), `beacon_mast` (a Rugby / Droitwich-style tall guyed lattice broadcasting/beacon mast
  with a tuning hut and guy-anchor blocks) and `night_lighting` (an outer approach-lighting array for night
  sorties: elevated lamps with pundit marker lights, an outer marker and a controller's caravan on the approach).
- **Hooks:** `world_populator.gd` `_register_navigation_aids()` (from `_ready()` after `_register_forestry()`)
  + `_build_navigation_aids()`; `NavigationAidKit.build(kind, pos, heading_deg, size, seed)`.
- **Data provenance:** real, cited sites — the Rugby and Droitwich transmitting stations, Brookmans Park and the
  BBC station chain, and documented RAF radio/navigation and night-fighter airfields — see
  `data/navigation_aids_1940.json` `_note` and `ATTRIBUTION.md`.
- **Debug:** `--navigation-aid-test` (sites + kinds + meshes). **Tests:** `_test_navigation_aids`.
- **Verify deferred:** no engine run; meshes counted only, never rendered.

### P19 — Military depth — CODE DONE (static)
- **New files:** `scripts/ground/military_depth_kit.gd` (`class_name MilitaryDepthKit`),
  `data/military_depth_1940.json` (generated by `tools/make_military_depth_1940.py`; 16 sites, 5 kinds).
- **Kinds:** `transit_camp` (a transit / embarkation camp: hut and tent lines, a rail siding with wagons, a
  staging area and a guard post), `ammunition_depot` (earth-banked magazines in rows with sidings, stores and a
  perimeter fence), `vehicle_park` (rows of parked lorries reusing the shared `AirfieldAssets.truck` mesh, with
  workshops and a fuel point), `horse_column` (a horse-drawn transport column: horse lines, GS wagons and
  limbers, a farrier's forge and a water trough — 1940 is far more horse than truck) and `tank_train` (a rail
  siding of flatcars loaded with tanks).
- **Hooks:** `world_populator.gd` `_register_military_depth()` (from `_ready()` after
  `_register_navigation_aids()`) + `_build_military_depth()`; `MilitaryDepthKit.build(kind, pos, heading_deg,
  size, seed)`.
- **Data provenance:** real, cited British (and German) camps, depots, remount depots and rail-heads of 1940 —
  see `data/military_depth_1940.json` `_note` and `ATTRIBUTION.md`.
- **Debug:** `--military-depth-test` (sites + kinds + meshes). **Tests:** `_test_military_depth`.
- **Verify deferred:** no engine run; meshes counted only, never rendered.
- **Non-destructible scenery** (like P13/P14/P15): these four phases add no `_target_info` / raid targets and no
  new `GroundStructure` kinds; the ammunition/vehicle content is scenery, not a raid objective.

## Known gaps carried forward
- None yet — program just started. The predecessor program's accepted items (synthetic NE-area rails/coast/
  woods, the raised roads size guard) remain accepted and are not to be "fixed".
- P3: the Edersee (Eder) dam is sited at 51.1833, 8.9667 (a real point on the Edersee reservoir inside the
  playable bounds); the 1914 dam wall itself stands at 51.1833, 9.0589, ~4 km east of the heightmap edge
  (LON_MAX 9.0) — the site is kept in-theatre deliberately (see `data/dams_1940.json` `_note`).
- P7: the terrain-derived viaducts/tunnels are read off the game's *draped* rails — the rail ribbon itself still
  follows `ground_y`, so at a derived viaduct the ribbon sags below the deck rather than running across it, and a
  derived tunnel portal is a single portal + hillside mound, not a bore. Both are static-checked only (no render).
- P7: the curated catalogue is deliberately small (8 famous viaducts/tunnels, all in SE England); the continental
  (French/Belgian) and less famous structures are left entirely to the terrain pass, so they carry no cited rows.
- P8: airfield furniture is placed on every layout in `_build_airfield()`, not inside `_dress_grass_airfield` as
  the brief's shorthand suggested, so the 85 airfields are all covered; the per-style dress functions are unchanged.
- P9: `petrol_depot` and `gas_holder` have builders and are exercised by tests, but there are no curated data rows
  of those kinds yet. Five sites (Fawley, Southampton Water, Rouen, Antwerp, Dunkirk) reuse the hand-authored v4.0
  `INDUSTRY` positions and are flagged as not freshly re-verified in the record `source`.
- All three phases: written and statically checked but **not** run through the engine — mesh counts come only from
  the headless tests / `--<thing>-test` args, never a render.
- P10: the two Coventry sites and the Longbridge / Ryton / Radlett / Kemble rows cite the documented wartime
  facility and its real locality coordinate, but a couple use a town-centre coordinate (Banner Lane, Baginton /
  Coventry Airport, Longbridge, Ryton, Radlett) rather than a surveyed works footprint; flagged in each `source`.
- P11: `locations.json` already carries approximate `v1_site` targets named `wizernes_v2` (50.7143, 2.1055) and
  `eperlecques` (50.8208, 2.1989); the new cited Heavy Cross rows `wizernes_la_coupole` (50.7052616, 2.2436221)
  and `eperlecques_blockhaus` (50.82861, 2.18361) sit a few km from them, so the map now shows both the legacy
  approximate pair and the newly cited pair. Reconciling/retiring the legacy rows is left to the owner.
- P11: the 9 V-1 "ski" site localities are the documented communes (Wikipedia "V-1 flying bomb facilities" /
  Réseau AGIR), verified via OpenStreetMap/Nominatim as the site locality — the exact surveyed footprint of each
  ski site is not pinned. Two storage depots (Renescure, Domléger) are included; the other August-1943 depots
  (Biennais, Brécourt, Couville, Beauvais, Valognes, …) are not.
- P12: port clutter is **non-destructible scenery** (no `_target_info` / raid target), matching the brief; each
  site snaps to the nearest shore so its exact berth is terrain-driven, not the literal data coordinate. The
  moving Dover–Dunkerque ferry is a single `GroundShip("ferry")` shuttling a straight three-point lane.
- P10/P11/P12 kits reuse only existing helpers (`GroundKit`, `AirfieldAssets`, `GroundShip`, `RoutePath`,
  `GroundStructure`); no new engine-level assets or meshes were added.
- P13: the rural texture is a **curated** set of 30 named farm sites (real village/locality coordinates), not a
  procedural per-tile scatter, so the hop/orchard/market-garden density is lower than the real 1940s Kent. Each
  record's `source` cites the real place; the exact field/farmstead position is the locality centroid.
- P14: the coastal landmarks stream from **`data/coastal_landmarks_1940.json`** (a new registration path,
  `_register_coastal_landmarks`), not from `data/locations.json` `features[]` — the brief's "features rows" model
  is reused in spirit (the new ids are also documented in `data/landmarks_1940.json`), but `locations.json` was
  deliberately left untouched (hard rule: do not regenerate it). Each lido/bandstand label is cited to a town or
  landmark article, not a per-structure survey.
- P15: the civil-defence shelters/posts are placed at real town/district centroids (the exact street-corner
  shelter is not pinned) and the Anderson-shelter rows stand for the ubiquitous garden-shelter districts rather
  than individual gardens. The camouflage paint is a flat roof-plane overlay sized to the works footprint, not a
  per-surface retexture of the underlying factory mesh (which lives inside `GroundStructure`).
- All three phases: written and statically checked but **not** run through the engine — mesh counts come only
  from the headless tests / `--<thing>-test` args, never a render.
