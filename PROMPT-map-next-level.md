# PROMPT: take the map to the next level (WW2 era, 1940–45), without costing frames

> **How to use this prompt.** Paste it, or point Claude at this file, at the start of a fresh session.
>
> It is written to be worked through **thoroughly**:
> - research every item properly before building it;
> - write down what was found;
> - build it;
> - look at it;
> - measure it;
> - review it.
>
> Depth and correctness beat speed. Do not skip the research, screenshot or measurement steps to save
> effort: they are the point.

**Project:** WW2 Channel Air War. A free, donation-supported WW2 flight game. Public repo
`colemanuk82/ww2-channel-air-war`.

**Engine:** Godot 4.8-dev RTX fork, `F:\godot-rtx\bin\godot.windows.editor.x86_64.console.exe`.

**Project folder:** `F:\ww2_dlss`, on the user's Windows PC.

**Start point:** v2.3, which added:
- army camps with wire, towers, nets and dumps;
- 20 POW and labour camps at their real sites;
- 116 airfields in RAF and Luftwaffe styles;
- ricks, stooks and crash sites in the fields;
- 15 in-flight music tracks.

**World:** about 954 × 453 km, lat 48.9–53.0, lon −4.6 to 9.0. It covers southern England, the Channel,
northern France, Belgium, the Netherlands and the Rhineland. Positions come from `WorldCoords.latlon_to_world`.

---

## 1. The vision

The map is strong at **summer 1940**: most data files are `data/*_1940.json`. The game already knows the
date (`GroundKit.era_date()`) and the front line (`GroundKit.front_lon(lat, date)`), but the ground barely
uses them.

The aim of this update is that **the war shows on the ground, and changes with the date.** Fly over the same
square of Kent or Normandy in four eras and see four different places:

| Era | Date range | What the ground should say |
|---|---|---|
| Battle of Britain | Jul–Oct 1940 | Peaceful summer farmland, harvest ricks, fresh pillboxes and anti-tank ditches, the first bomb damage on airfields |
| The Blitz | Sep 1940 – May 1941 | Burnt-out districts in London's East End and docks, Coventry, Portsmouth, Southampton, Plymouth and Bristol; rubble, fire-watch smoke |
| The build-up | 1943 – early Jun 1944 | Southern England turned into a vehicle park; landing craft crowding the harbours; Mulberry units waiting off Selsey and Dungeness; the Ruhr cities progressively gutted |
| Liberation | Jun 1944 – 1945 | Normandy torn up: Mulberry B, beach exits, gliders in the fields, deliberate floods, Caen and Saint-Lô in ruins; then Walcheren flooded, Arnhem's landing zones, the Westwall, the Rhine crossing |

At the same time, every altitude band must look **more convincing**:
- **Low level** (under 300 m), what strafing and take-off show: detail, life, clutter, damage.
- **Mid level** (1–3 km), where most dogfights happen: the regional *shape* of fields, roads, towns,
  woods and damage.
- **High level** (5 km and up), the bomber stream: colour, haze, horizon, and readable landmarks to
  navigate by.

**And the performance rule is absolute.** Frame time in the heaviest test scenes must not get worse:
stay within 3% of the baseline, *measured*. If a feature can't pay for itself, cut it or move it into the
terrain shader.

---

## 2. Working method (follow it for every task)

For **every** task in section 5, do these steps in order. Do not merge steps or skip ahead.

1. **Survey what already exists (always first).**
   - Search the code and data for the subject. Many things already exist in some form:
     - oast houses, hop gardens, drainage mills, orchards and sheep folds in `data/rural_1940.json`;
     - army, transit and ammunition camps in `data/military_depth_1940.json`;
     - V-1 ski sites in `data/v_weapons_1940.json`;
     - Anderson shelters and ARP posts in `data/civil_defence_1940.json`;
     - booms and minefields in `data/sea_defences_1940.json`;
     - coast clusters in `_register_coast_defences`;
     - canals in `CanalKit`;
     - rail drama in `_register_rail_drama`;
     - balloons and searchlights in `WorldPopulator._defences`.
   - List the files and functions involved, and say whether the task **deepens** something or adds
     something **new**. Never build a second copy of something.
2. **Research.**
   - Use WebSearch and WebFetch for facts, dates and positions.
   - Use `tools/cache/refs.ps1 -q "<query>" -tag <tag> -n 8` to download Wikimedia Commons photos into
     `build\refs`, then stage and **look at** them.
   - Find at least **3 period photos per subject**, preferably aerial or high-angle views, since that is
     how the player sees it.
   - Note the real dimensions, layout, colours, materials and the dates something existed.
   - Write it all to `docs/map_research/<task>.md`: sources (URLs), coordinates with how they were
     checked, dimensions, colour notes, the date window, and what you will and won't model, with reasons.
   - The `docs` folder has a `.gdignore` under promo; add one in `docs/map_research` too.
3. **Design for cost.**
   - Before writing code, decide which tier from section 4 each element uses.
   - Estimate instance counts, draw calls and fade distances.
   - Write the estimate into the research note.
4. **Build.**
   - Match the surrounding code style.
   - Keep data in a JSON file under `data/` when there are more than about 6 rows, with a `source` field
     per row.
   - Pass the data validator if one exists (`tools/validate_data.py`).
5. **Import and test.**
   - Run `godot --headless --path F:\ww2_dlss --import` if you added a `class_name`.
   - Then run `tools/cache/tonly.ps1`, and decode `build\tonly.log` from UTF-16LE.
   - The test count must not drop (currently 1155). **Add tests** for new data loaders and for era
     switching. For example: "on 1940-08-01 Caen shows no ruins; on 1944-07-20 it does".
6. **Look at it.**
   - Take screenshots at the relevant altitudes with `tools/cache/afshots.ps1` (edit the `S` lines;
     run one capture at a time, since parallel runs time out).
   - Downscale them to 1600 px wide and **view** them.
   - Compare side by side with the reference photos.
   - Write in the research note what still doesn't match, and fix what can be fixed. At least one
     look-and-fix loop per task.
7. **Measure.** Run the perf harness (section 3). If a scene is more than 3% worse, fix it before
   moving on.
8. **Commit.** Use `tools/cache/ship.ps1 -norelease -msg "<what and why, with perf numbers>"`. It bumps
   the version, builds, runs the tests, commits and pushes. **No GitHub release** until the user says
   "release".
9. **Review.**
   - After each group of tasks (A, B, C, D), ask a **separate reviewer agent** that hasn't seen the work
     to read the diff and the research notes.
   - It should check: invented helpers or wrong arity; non-determinism; work done on the main thread
     that belongs on the worker; missing fade distances; uncapped lists; wrong dates or coordinates
     against the cited sources.
   - Fix what it finds.

Keep a phase board in `PROGRAM-STATUS-map-next.md`: one row per task, with status, commit, perf delta
and notes. Update it as you go so the user can see progress at a glance.

---

## 3. Step 0: a performance harness that actually works (do this before any feature)

The old profiler (`--perf`, `tools/cache/perf_af.ps1`) timed out on both old and new code, because the
window was started **minimised** and a minimised Godot window doesn't render frames.

1. **Build `tools/cache/perf.ps1`.**
   - Launch the game in a **normal visible window** (`-WindowStyle Normal`) at 1920×1080, with fixed
     settings: same weather, time of day, aircraft and graphics preset; DLSS off for repeatability.
   - Pass `--perf=<scene>:<seconds>` and a scripted flight path. Reuse `--at=lat,lon,alt,heading` and
     `--chase`, with an autopilot holding heading and altitude.
2. **What to record.**
   - After a 10 s warm-up, sample every frame for 30 s:
     - frame time;
     - `Performance.TIME_PROCESS`;
     - `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`;
     - `RENDER_TOTAL_PRIMITIVES_IN_FRAME`;
     - `RENDER_TOTAL_OBJECTS_IN_FRAME`;
     - `MEMORY_STATIC`.
   - Report the average, 1% low and 0.1% low frame times, the average draw calls and primitives, and
     the peak memory.
   - Also log the **streaming hitch count**: frames over 2× the median.
3. **Scenes** (keep this list fixed for the whole program):
   - `biggin_low`: 150 m over Biggin Hill (airfield, camp, Kent farmland).
   - `london_3k`: 3 km over the City heading east down the Thames (the densest town scatter).
   - `caen_low`: 200 m over Caen heading north to the beaches (Normandy; will gain bocage, ruins and
     Mulberry).
   - `ruhr_6k`: 6 km over Essen (the high-altitude view, haze, many cities).
   - `channel_dusk`: 500 m over the Dover Strait at dusk (sea, convoys, coast, searchlights).
   - `arnhem_1k`: 1 km over Oosterbeek, dated 1944-09-18 (landing zones; added once task A6 exists).
4. **Baseline and recording.**
   - Record the baseline into `build/perf_baseline.json` **before any change**, plus a copy in the
     phase board.
   - Run each scene twice and use the better run. Note the machine's background load.
   - Every commit message carries the per-scene delta, e.g.
     `perf: biggin -0.4% london +1.1% caen +2.3% ruhr -0.2% channel +0.6%`.
5. **Era switching.** Add a `--date=YYYY-MM-DD` launch argument if one doesn't exist, so screenshots and
   perf runs can pick the era. Check how `GameState.era_date` is set by the menus first, and reuse that.

---

## 4. Performance toolkit (choose the cheapest tier that looks right)

**Tier 0: terrain shader** (almost free). For anything flat or seen from altitude: craters, scorch,
rubble, floods, trampled ground, mud, crop marks, bocage colour, seasonal tint, snow, beach churn, tank
tracks.
- The zone system already exists. `af_a` / `af_b` are vec4[24], and the zone kind is `af_b.w`:
  - 1 = airfield grass;
  - 2 = army camp mud;
  - 3 = POW sand.
- `TerrainChunkManager` keeps every zone and uploads the 24 nearest the player (`_upload_zones`).
- Add new kinds the same way: 4 = bomb craters, 5 = flood sheen, 6 = rubble and scorch, 7 = beach churn,
  and so on. Each kind gets its own date window (store `from` / `to` dates on the zone and filter when
  uploading).
- For **large or region-wide** effects (bocage, polders, seasons, Blitz districts), don't use point
  zones. Bake a small **data texture** instead: one RGBA8 texture at about 1 km per pixel over the whole
  map. For example: R = region type, G = damage level by era band, B = flood, A = spare. Sample it once
  per fragment, next to `map_tex`. Bake it from JSON with a Python tool (`tools/bake_regions.py`) that
  writes `assets/terrain/regions.png`.
- Keep the noise cheap: reuse `t_vnoise2`, and no extra texture fetches inside loops.

**Tier 1: shared mesh + MultiMesh per kind per tile or site.**
- Build meshes once and cache them in `Scatter._meshes`.
- Merge surfaces by material with `AirfieldAssets._build`, keeping palettes to 4–6 colours so a prop
  costs one to three draw calls.
- **Always** set `visibility_range_end`:

| Kind | Fade distance |
|---|---|
| Small clutter (crates, drums, stooks, debris) | 1.5–2.5 km |
| Vehicles | 3–3.5 km |
| Gliders and landing craft | 3.5–4.5 km |
| Huts and houses | 6–10 km |
| Big landmarks (Mulberry breakwaters, caissons, cathedrals) | 15–25 km, since they are navigation aids |

**Tier 2: worker-thread data, main-thread nodes.**
- Keep the split: pure data on the worker (`tile_landcover_data`, `_shore_for` jobs), and nodes plus
  meshes on the main thread (`build_tile_nodes`, site builders).
- Never create a Mesh, Material or Node on a worker thread.

**Tier 3: streamed sites** (`WorldPopulator._add_site(key, pos, act, builder, extra)`).
- The activation radius should match how far away the site matters (e.g. 7.5–9.5 km for camps).
- Builders must be deterministic, seeded from `hash(id)`, so a freed site rebuilds identically.

**Tier 4: moving or emitting things** (vehicles, barges, trains, smoke, fire, searchlights).
- A **global cap** on each type, nearest-N to the player, recycled rather than spawned and freed.
- Emitters are culled beyond 12–15 km, and searchlights only exist at night.

**Never:**
- A Node3D per static prop (only destructible things get nodes; use `AirfieldProp` clusters).
- An uncapped scatter list.
- A new full-screen post-process pass.
- A per-frame `get_nodes_in_group` sweep.
- Shader loops longer than the existing 24-zone loop.

---

## 5. The work

Each item lists: what to research, the places (starting coordinates are given only as search hints;
**verify every one against a source**, write the checked value and source into the research note and
data file, and fix the hint if it is wrong), what to build, which tier, the acceptance criteria, and
what to screenshot.

### Group A: the map follows the date

#### A1. Era plumbing (prerequisite)
- **What:**
  - A single `EraClock` helper (or extend `GroundKit`) with `is_between(from, to)` and `era_band()`,
    returning one of `"1940"`, `"blitz"`, `"midwar"`, `"buildup"`, `"liberation"`, `"1945"`.
  - Data rows gain optional `from` / `to` ISO dates.
  - The zone upload filters by date.
  - Sites check their date window when building.
  - The tile data path takes the band as an input, so a cache built in one era isn't reused in
    another.
- **Acceptance:** tests for the band boundaries; one dated test row that appears or disappears across
  a boundary; `--date=` works for screenshots.

#### A2. The Blitz and the bombing war: damage that builds up
- **Research:**
  - Bomb-damage maps: the LCC bomb damage maps for London, and the Coventry raid of 14 Nov 1940.
  - Aerial photos of the gutted East End and Surrey Docks; Coventry city centre after the raid;
    Rotterdam after 14 May 1940; Caen and Saint-Lô in July 1944; Le Havre in Sept 1944; Cologne after
    the 30/31 May 1942 raid; Essen and Düsseldorf by 1943–45.
  - How the damage looks from the air: roofless shells in rows, cleared rubble sites, scorched patches,
    crater fields on the docks and rail yards.
- **Places (hints, verify):**

| Place | Lat, lon | Dates |
|---|---|---|
| London docks and East End | 51.505, −0.03 | from 7 Sep 1940 |
| Coventry | 52.408, −1.51 | from 14 Nov 1940 |
| Portsmouth | 50.80, −1.09 | Jan 1941 |
| Southampton | 50.90, −1.40 | Nov–Dec 1940 |
| Plymouth | 50.37, −4.14 | Mar–Apr 1941 |
| Bristol | 51.45, −2.59 | Nov 1940 |
| Birmingham | 52.48, −1.89 | 1940–41 |
| Rotterdam | 51.92, 4.48 | from 14 May 1940 |
| Cologne | 50.94, 6.96 | heavier from May 1942 |
| Essen | 51.46, 7.01 | 1943 onwards |
| Düsseldorf | 51.22, 6.78 | |
| Caen | 49.18, −0.37 | from 7 Jul 1944 |
| Saint-Lô | 49.116, −1.09 | Jun–Jul 1944 |
| Le Havre | 49.49, 0.11 | Sep 1944 |

- **Build:**
  - Tier 0 zones of kind "rubble/scorch" and "crater field", with a damage level that rises with the
    date. A data texture is better here if there are many cities.
  - A **gutted-house mesh variant**: roofless shell with blackened wall tops and an interior rubble
    heap. In the town scatter, swap a share of houses in damaged districts to this variant (share
    = damage level × 0.6). It uses the same transforms, so the cost is zero.
  - A few **cleared sites** (flat rubble patches) and **static water tanks** (EWS) in London.
  - Optional smoke from still-burning blocks for 48 h after a big raid, capped at 4 emitters.
- **Acceptance:** the London East End reads as bombed from 3 km in October 1940 and as untouched in
  August 1940; Coventry centre is gutted after 14 Nov 1940; no measurable perf change in `london_3k`.
- **Screenshot:** London docks from 2 km in 1940-08 vs 1940-10; Caen from 1 km in 1944-06-01 vs
  1944-07-20.

#### A3. 1944 invasion build-up across southern England
- **Research:** photos of vehicle parks along English lanes (the "sausage" marshalling areas), landing
  craft (LCT, LCI, LST) crowding the Solent and Poole, embarkation hards (concrete "chocolate-block"
  slipways), Phoenix caissons sunk and waiting off Selsey and Dungeness, and Bombardon floats.
- **Places (hints):**

| Place | Lat, lon |
|---|---|
| Solent anchorage | 50.78, −1.25 |
| Southampton Water | 50.86, −1.36 |
| Poole Harbour | 50.70, −1.98 |
| Portland and Weymouth | 50.57, −2.44 |
| Selsey Phoenix park | 50.72, −0.79 |
| Dungeness | 50.91, 0.97 |

  - Hards: Lepe 50.785, −1.36; Stokes Bay 50.78, −1.16; Hamble.
  - Falmouth (lon −5.07) is **outside** the map, so leave it out.
- **Build:**
  - The marshalling areas reuse the camp vehicle meshes, as roadside vehicle lines along real lanes
    near the coast. Sample `data/osm/roads.json` minor roads within about 25 km of the hards, and place
    vehicles nose-to-tail on the verge under trees. Tier 1, capped at about 400 vehicles per 1800 m
    tile.
  - New landing-craft meshes (LCT, LCI(L), LST) moored in rows. Tier 1, with 4 km fades.
  - Phoenix caissons: big concrete blocks, seen from 15 km.
  - Embarkation hards: Tier 0 concrete strip plus a mesh slipway.
  - All dated April – 5 June 1944 (the caissons until they are towed away in June).
- **Acceptance:** at 2 km over the Solent in May 1944 the anchorage is crowded and the lanes inland are
  lined with vehicles; in 1940 none of it exists.

#### A4. Normandy after D-Day
- **Research:**
  - Mulberry B at Arromanches: aerial photos of the Phoenix breakwater arc, the "Whale" floating
    roadways and the Spud pierheads.
  - Mulberry A off Saint-Laurent (Omaha), wrecked in the storm of 19–22 June 1944.
  - The Gooseberry blockship lines.
  - Beach exits and the churned beaches.
  - Horsa and Hamilcar gliders broken up in the landing zones at Ranville (LZ N) and by Pegasus Bridge
    (LZ X/Y); Waco and Horsa gliders around Sainte-Mère-Église and the Merderet.
  - The German flooding of the Dives valley and the Merderet/Douve marshes.
  - The bocage fighting landscape: shell-holed fields, knocked-out tanks in the hedgerows.
- **Places (hints):**

| Place | Lat, lon |
|---|---|
| Arromanches (Mulberry B) | 49.34, −0.62 |
| Saint-Laurent (Mulberry A) | 49.37, −0.88 |
| Pegasus Bridge, Bénouville | 49.242, −0.274 |
| Ranville | 49.23, −0.25 |
| La Fière causeway | 49.40, −1.36 |
| Sainte-Mère-Église | 49.408, −1.316 |
| Robehomme (Dives valley) | 49.21, −0.13 |
| Utah beach | 49.42, −1.18 |
| Omaha beach | 49.37, −0.87 |
| Gold beach | 49.34, −0.55 |
| Juno beach | 49.33, −0.40 |
| Sword beach | 49.29, −0.27 |

- **Build:**
  - Mulberry B as a streamed site: the Phoenix arc, the Whale roadways to the shore, pierheads and
    blockships. Fades at 20 km; it is a landmark.
  - Mulberry A's wreckage after 22 June.
  - Beach churn and vehicle tracks (Tier 0).
  - Gliders in the landing zones: three mesh variants, intact, nose broken and fuselage split, as a
    MultiMesh along the real field edges.
  - The flooded valleys as a Tier 0 water sheen with emergent hedge tops and posts.
  - Knocked-out tanks and vehicles on the roads behind the front line from `front_lon` (Tier 1, capped).
- **Acceptance:** on 1944-06-10, from 1.5 km, the Arromanches harbour reads instantly as Mulberry B; the
  gliders read as gliders from 800 m; the Merderet floods are visible from 3 km; none of it exists
  before 6 June 1944.

#### A5. Walcheren and the Scheldt, Oct–Nov 1944
- **Research:** the RAF breached the Westkapelle, Flushing, Veere and Rammekens sea walls (3–17 Oct
  1944). Aerial photos of a flooded Walcheren with the towns standing out as islands.
- **Places (hints):** Westkapelle dyke 51.53, 3.44; Middelburg 51.50, 3.61; Flushing (Vlissingen)
  51.44, 3.57.
- **Build:**
  - A Tier 0 flood over the island's low ground, from 3 Oct 1944 to the end of 1945, with the dunes and
    towns left dry (use the height field: flood below about +1 m).
  - Breach gaps in the dyke as meshes.
- **Acceptance:** from 5 km the island is a sheet of water with islands of town.

#### A6. Arnhem, Nijmegen and the bridges (Market Garden, Sept 1944)
- **Research:** glider landing zones on Renkum heath and at Wolfheze, the dropping-zone patterns,
  Oosterbeek, the Arnhem road bridge (the John Frost bridge) and its damaged northern ramp, and the
  Nijmegen road bridge.
- **Places (hints):** Wolfheze LZ 52.00, 5.79; Renkum heath 51.99, 5.76; Oosterbeek 51.99, 5.84; Arnhem
  bridge 51.977, 5.914; Nijmegen bridge 51.85, 5.87; Grave bridge 51.76, 5.73.
- **Build:**
  - Gliders reusing A4's meshes, from 17 Sept 1944.
  - Parachute canopies as small white discs in the fields, dropped on the day plus two days only, and
    capped.
  - Bridge-damage meshes.
  - Wrecked vehicles on the bridge ramp.
- **Acceptance:** the `arnhem_1k` perf scene exists and passes.

#### A7. The Westwall (Siegfried Line) and the Rhine crossing
- **Research:**
  - The Westwall "dragon's teeth" lines south of Aachen, which are very distinctive from the air.
  - Bunkers.
  - Operation Varsity on 24 Mar 1945: gliders around Hamminkeln and Wesel.
  - The ruins of Wesel.
  - The Ludendorff bridge at Remagen (7 Mar 1945, collapsed on 17 Mar).
- **Places (hints):**

| Place | Lat, lon |
|---|---|
| Dragon's teeth near Aachen (Schevenhütte to Monschau) | 50.70–50.55, 6.15–6.25 |
| Hamminkeln | 51.73, 6.59 |
| Wesel | 51.66, 6.62 |
| Remagen | 50.58, 7.24 |

  - Check whether the Aachen and Westwall area is inside the terrain data.
- **Build:**
  - The dragon's teeth as a MultiMesh of small pyramids in 4–5 staggered rows along the real line
    (Tier 1, fade at 3 km), plus a Tier 0 cleared strip so the line reads from 5 km.
  - Varsity gliders.
  - Wesel's ruins, using A2's damage.
  - The Remagen bridge with its date-dependent collapsed state.
- **Acceptance:** from 4 km the dragon's teeth read as a pale line through the woods and fields.

#### A8. The 1940 invasion-defence landscape (deepen; survey first)
- **Research:** the GHQ Line and the coastal crust; anti-tank ditches; pillbox types (FW3/22, FW3/24);
  anti-landing obstacles in open fields (poles, trenches, old cars) to stop gliders; roadblocks.
- **Build:**
  - Only what is **missing**.
  - Glider-obstacle ditches and poles in big open fields near the coast and airfields in summer 1940
    (Tier 0 lines plus Tier 1 poles).
  - The real GHQ Line anti-tank ditch along its course where a source gives it.
- **Acceptance:** large open fields within about 15 km of the south coast show obstacle patterns in
  summer 1940.

### Group B: regional shape (mid level)

#### B1. A bake tool for the region map
- **What:** write `tools/bake_regions.py`. It reads `data/regions_1940.json`: polygons in lat/lon, each
  with a type and source. It writes `assets/terrain/regions.png` at about 1 km per pixel, plus an import
  file.
- **Region types:**
  - bocage;
  - open fields (Picardy, Artois, Beauce);
  - polder;
  - Weald;
  - downland (South Downs, North Downs, Chilterns);
  - heath (Surrey, the Breckland edge, Brabant, the Veluwe);
  - Ardennes/Eifel forest;
  - Ruhr industrial.
- **Shader:** add one sampler and one fetch, and branch the field lattice and colour on the region type.
- **Acceptance:** a debug colour mode shows the regions in the right places; a test checks the PNG
  matches the JSON (hash written by the bake).

#### B2. Bocage
- **Research:** aerial photos of Normandy bocage in 1944: field sizes (often 0.5–2 ha), the high banks
  topped with dense hedges and trees, sunken lanes, orchards round the farms.
- **Build:**
  - In the bocage region the shader uses smaller, irregular cells and thicker, darker hedge lines.
  - `Scatter.field_edge` (which mirrors the shader's lattice) must use the same cell size there, so
    the hedge meshes still sit on the painted lines. **This coupling is the main risk; test it**
    with a script that samples both.
  - Hedge meshes are taller with tree crowns along them.
  - Cider orchards around the farmsteads.
  - Keep the per-tile hedge cap and use the hedge near/far LOD pair.
- **Acceptance:** from 1.5 km, Normandy west of Caen reads as a fine green mesh of hedges, clearly
  unlike Kent; `caen_low` stays within budget.

#### B3. Open fields of northern France
- **What:** large fields with almost no hedges; villages packed tight round a church with an orchard
  ring; long straight roads lined with trees (the `routes nationales` with plane trees).
- **Build:** shader cell size and hedge density by region; roadside tree lines along major roads in
  France (Tier 1, capped).
- **Acceptance:** from 3 km Picardy looks open and stripy; the roads read from the tree lines.

#### B4. Dutch and Flemish polders
- **What:** dead-straight drainage ditches in long thin parcels, lines of poplars and willows, windmills
  (survey `drainage_mill` in `rural_1940.json` and deepen), farmhouses on mounds.
- **Places (hints):** Haarlemmermeer 52.30, 4.69; Noordoostpolder (drained in 1942, so check its era);
  the Zeeland islands; the polders along the Flemish coast.
- **Build:**
  - A shader stripe lattice in the polder region, with water-coloured ditches.
  - Poplar lines (Tier 1).
  - More windmills, from sourced lists.
- **Acceptance:** from 2 km Holland reads as long ruled strips with blue ditch lines.

#### B5. Kent and the Weald, the Downs, the heaths
- **What:**
  - **The Weald:** small fields, lots of shaws and woods, oast houses and hop gardens (deepen
    `rural_1940`: there are only 6 oast houses and 5 hop gardens; real Kent had thousands of oast
    roundels. Scatter them procedurally on farmsteads in the Weald region, with the 6 real ones kept).
  - **Chalk downland:** open, pale, with sheep-cropped grass, few hedges, white tracks and dew ponds.
  - **Heaths:** brown and purple heather with pine clumps, and army training scars on Surrey heath and
    Salisbury Plain (the edge of the map).
- **Acceptance:** each region is recognisable from 2 km in summer 1940.

#### B6. Seasons
- **What:** shader tint by month: spring green; June hay; July–August harvest gold with stubble;
  September–October ploughed brown; November–February dull winter green with bare trees; frost or snow
  in Jan 1945 (the hard winter) in the north and east.
- **Build:**
  - Seasonal colour uniforms set once when the date changes.
  - Tree crowns use a seasonal far-mesh colour, either via a `MultiMesh` custom colour or a
    per-season material swap. No extra draw calls.
  - The ricks and stooks (v2.3) only appear in season.
- **Acceptance:** the same view in 1944-05, 1944-08, 1944-11 and 1945-01 reads as four seasons; zero
  frame-time cost.

### Group C: life at low level (strict caps)

#### C1. Barges on the canals and rivers
- **Survey** `CanalKit` and the river data.
- **Research:** Dutch and Belgian barges (péniches, Rhine barges), British narrowboats and Thames
  lighters.
- **Build:**
  - Moored strings at locks and wharves (Tier 1).
  - Up to **12** moving barges near the player, sliding along the canal polyline. Recycle them as the
    player moves.
  - Rhine barge trains (a tug plus 3–4 lighters) on the Rhine and Waal.
  - All are ground targets for the Typhoon and Mustang trains-and-barges missions, if the mission
    system supports it. Check `ground_target.gd`.

#### C2. Trains in motion
- **Survey** `_register_rail_drama` and the traffic code.
- **Build:**
  - Always 3–6 trains moving on the real rail lines within 20 km of the player, with steam exhaust
    from a **shared, pooled** particle emitter.
  - Goods trains of the right length.
  - Armoured flak trains in 1944 France.
  - Recycled, never freed.
  - Night: firebox glow only.
- **Acceptance:** `london_3k` and `ruhr_6k` stay within budget.

#### C3. Industry breathes
- **What:**
  - Chimney smoke at the major works (survey `industry_1940`): one shared emitter per site, culled at
    15 km.
  - The Ruhr gets a **height-limited smog layer** (Tier 0 fog in the sky shader or a large volume with
    one draw).
  - Coking-plant glow at night.

#### C4. Searchlight and flak belts by date
- **Research:** the 1940 London Inner Artillery Zone; the Kammhuber Line belts across the Netherlands
  and Belgium (1941–43), with their searchlight boxes and Würzburg radars; the Ruhr flak concentrations
  in 1943–45.
- **Build:**
  - Positions as dated data.
  - Lights exist only at night and only within 25 km.
  - Flak is reused from `AAGun`.
  - A global cap on active beams (e.g. 24).
- **Acceptance:** a night run over the Ruhr in 1943 shows a searchlight belt and flak; `ruhr_6k` at
  night stays within budget.

#### C5. Harbours and anchorages
- **Survey** `_defences`, `sea_defences_1940`, `port_clutter_1940` and the docks.
- **What to add where missing:**
  - Balloon barrages over the main ports by date.
  - Anti-torpedo nets across fleet anchorages (Portsmouth, Plymouth Sound).
  - Convoys forming up off Southend in the Thames estuary (survey the convoy code).
  - Minesweepers at work.
- **Do not duplicate.**

### Group D: high level and the horizon

#### D1. The far horizon
- Fly at 6 km and look for terrain popping in, chunk edges, or a hard line where the terrain ends.
  Fix with a cheap far-ring impostor (a low-res mesh with `map_tex` colours) or a horizon blend in the
  sky or fog shader.
- **Acceptance:** no visible popping or hard edge in `ruhr_6k` and `channel_dusk`.

#### D2. Haze and smog
- Height-limited haze over London and the Ruhr, and a thin layer over cities in winter. Done in the sky
  or fog shader only.
- **Acceptance:** from 6 km the Ruhr reads as a smoky basin.

#### D3. Navigation landmarks
- Make sure the features bomber and fighter crews navigated by are readable from 5 km:
  - the coast and estuaries (Thames, Seine, Scheldt);
  - the white cliffs;
  - the Rhine bends and the Dutch IJsselmeer;
  - big woods and lakes;
  - cathedrals (Canterbury, Amiens, Cologne);
  - the Möhne and Eder dams (survey `dam_kit`).
- Tune their colour or scale, or add a far-only LOD, so they stand out without looking fake.

#### D4. The coast from altitude
- The sand, chalk, shingle and mud bands and the tidal flats should read correctly from 6 km. Tune
  `sand_col`, `chalk_col` and the shoreline shading against period aerial photos of the Kent, Normandy
  and Dutch coasts.

### Group E: fixes found during v2.3 (do these early, they are small)

1. **Hemer.** Stalag VI-A sits on the edge of Hemer on steep ground. Find its real footprint (the
   Blücher barracks, Jübergstraße area) and move the camp to it if a source supports that. Check that
   all 20 camps sit on reasonably flat land; nudge them within 300 m to the flattest nearby spot if not.
2. **Screenshot harness.** The low orbit shots fly into hills. Keep the camera above `ground_y + 80 m`
   all the way round, and abort a shot cleanly if the aircraft hits the ground.
3. **`--overhead`.** It doesn't look straight down at the `--at` point: sites appear in the lower part
   of the frame. Fix the camera basis so the target is centred.
4. **Ricks and stooks.** The v2.3 ricks were never seen in a screenshot. Take low-level shots of Kent
   farmland in August 1940 and confirm they read as ricks, not pale blobs, from 300–800 m. Tune the
   colour or fade distance if not.
5. **POW low shots.** Get a proper low-level look at a Stalag and a British camp, and compare it with
   the Stalag Luft III model photo in `build\refs\pow_02.jpg`.

---

## 6. Ground rules (from this project's history; all mandatory)

- **Code style:** TABS, statically typed GDScript, matching the style of the file you're in.
- **Determinism:** every site is seeded from `hash(id)`. A site that is freed and re-streamed must
  rebuild exactly the same. Worker tiles use `seed_v` only.
- **Never name a static helper `_get`, `_set`, `_init` or any other `Object` virtual.** This broke the
  v2.3 build (`CampAssets._get`).
- **New `class_name` scripts** need `godot --headless --path F:\ww2_dlss --import` before tests or
  renders, or you get "Identifier not declared".
- **Text:** use `Label3D` for text in the world. TextMesh fails with "Convex decomposing failed".
- **Line endings:** HEAD is LF, but some working files had been converted to CRLF. Keep each file's
  line endings as you found them, and run `git diff --stat` before shipping. A file showing hundreds
  of changed lines for a small edit means line endings flipped; fix it.
- **PowerShell from the device shell:** run `.ps1` files with `-File` (inline `-Command` loses the `$`).
  Never redirect into `ship.log`.
- **The device shell:**
  - It can't delete files (`rm` is not permitted); ask for delete permission if needed, or move files
    into `_to_delete/`.
  - Write new files with a heredoc or Python, or write them in the container and push them with the
    commit-files tool.
- **Captures:** run one screenshot or perf capture at a time. Screenshots are 3840×2160; downscale to
  1600 px wide before viewing.
- **Web access:**
  - Commons downloads need the User-Agent already in `refs.ps1`.
  - Pixabay blocks scripted page fetches (403). The built-in browser can read a track page's JSON-LD
    `contentUrl`, and the CDN MP3 then downloads fine from PowerShell.
- **Data:** never run `tools/build_locations.py`. Never regenerate `data/osm/roads.json`. Never
  re-implement `WorldCoords`.
- **Credits:** any new music, image or data source is credited in the README credits, `ATTRIBUTION.md`,
  `docs/legal/CREDITS.txt` and `data/legal.json` (the in-game credits).
- **Sensitive history:**
  - Do **not** add concentration or extermination camps.
  - POW, internment and labour camps stay in scope only as already handled: static, not targets, not
    destructible.
  - Bomb damage is shown matter-of-factly: no bodies or casualties.
- **Shipping:**
  - `tools/cache/ship.ps1 -norelease -msg "..."` bumps the version on **every** update, then builds,
    runs the tests, commits and pushes.
  - Commits end with the session's co-author and session trailers (ship.ps1 writes them).
  - **No GitHub release until the user says "release".**

---

## 7. Definition of done

- Every task in groups A–E is either **done** (researched, built, tests passing, screenshots compared
  with references, perf within budget, committed) or **dropped with a written reason** in the phase
  board.
- `docs/map_research/` has one note per task with sources, checked coordinates, the cost estimate and
  the actual measured cost.
- `PROGRAM-STATUS-map-next.md` shows every task with its commit hash and perf delta.
- A final perf table against the baseline for all 6 scenes. No scene more than 3% worse; ideally some
  better, thanks to cleanups made along the way.
- **README:**
  - A new "The war on the ground" section with era comparison pairs of the same place: London docks
    Aug 1940 vs Oct 1940, the Solent 1940 vs May 1944, Arromanches 1940 vs Jun 1944, Walcheren Sep vs
    Nov 1944, and Caen in summer 1944.
  - Feature table rows updated.
  - Credits added.
- A short closing report for the user: what was added, what was dropped and why, the perf table, and
  suggested next steps. Then **wait for "release"**.
