# Desert map plan (second map: "Mediterranean / North Africa")

Decisions (from the user): one desert map covering Tunisia, Libya/Egypt (Western Desert) and Malta/Sicily; a second map
chosen from the menu next to the Channel map; real heightmap and coast data, desert surface types painted on top.

## Facts that shape the plan
- The world is 1:1 metres, origin lat 50.30 / lon 0.00, bounds are `const`s in `scripts/world_coords.gd` and
  `scripts/flight_planner.gd`; horizontal scale uses cos(50.3 deg). 68 scripts use WorldCoords, 28 load `res://data/heightmap` or `res://data/osm` paths directly.
- Channel data: 6144 x 3000 heightmap (13.6 x 4.1 deg, ~150 m/px), 58 MB in data/heightmap.
- The tools pipeline is generic (AWS terrain tiles, EOX imagery, OSM, ESA WorldCover) but writes to fixed folders.
- Checked from the PC: elevation tiles and EOX imagery reachable; the OSM land-polygon zip download failed (retry/mirror needed); `rasterio` (landcover) not installed.

## Extent
One map lon 8.0 .. 30.5, lat 30.0 .. 37.5 (Tunis to Alexandria, with Malta and Sicily's south). ~2,000 x 830 km.
Heightmap at ~300 m/px = about 7,500 x 2,800 px (similar file size to the Channel one). Desert needs less detail than
bocage; coastal strips and escarpments (Halfaya, Qattara rim, Jebel Akhdar, Atlas edge) are the relief that matters.

## Phases
1. **Map plumbing** (the risky part): turn WorldCoords bounds/origin/scale into per-map values (`MapDef` resource: id, name, bounds, origin, data folder, available aircraft/modes); `GameState.current_map`; `HeightField`, `TerrainChunkManager`, transport/river/landcover loaders read the map's data folder instead of fixed paths. Channel must stay byte-identical in behaviour (A/B perf test against v3.16).
2. **Data build** (scripted, mostly Haiku-able): region-aware make_heightmap / fetch_imagery / coast mask, `data/desert/*`. Sparse OSM (coast road, railway, few towns); landcover from WorldCover (sand, bare, scrub, built-up, crop strips along the coast and Nile delta).
3. **Terrain look**: terrain shader desert palette driven by the baked imagery and a surface-type mask (sand, rock, gravel, wadi, salt flat/sabkha, dunes in the Great Sand Sea edge); heat haze, dust, bright low-contrast sky, long visibility; scatter = sparse scrub, palms in oases, tents/vehicles/camps instead of hedges and trees.
4. **Sites**: airfields (dirt strips, landing grounds with tents, revetments), ports, towns, fortified lines (Mareth, Gazala, Alamein boxes), convoys on the coast road, Malta's Grand Harbour.
5. **Content**: aircraft availability (Hurricane, Kittyhawk, Spitfire V, Bf 109 E/F, Ju 87, Ju 88, Bf 110, Blenheim, Wellington, Bisley/Beaufort), missions per theatre and date, Free Flight start choices, menu map picker.
6. **Perf pass** with the seeded A/B harness (`--seed`, `--perf`) on desert scenes; budget no worse than the Channel scenes.

## Haiku vs main model
Haiku: tool option plumbing (region args), location/airfield lists, JSON/data conversions, asset file shuffling, test harness copies.
Main model: WorldCoords/HeightField refactor, shaders, anything touching flight or rendering, final review of Haiku output.

## Open questions for later
- Dates and eras per theatre (1940-43) and whether Channel-era unit skins (RAF/Luftwaffe) need desert schemes.
- Whether the desert map needs its own night/weather presets (sandstorms, haze).
