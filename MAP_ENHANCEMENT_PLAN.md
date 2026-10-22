# Map enhancement plan (hand-off for a smaller model)

Goal: make the map look richer from the air by **enhancing what already exists**, inside the game's current colour palette. No new colour families: reuse colours already in `shaders/terrain.gdshader`, `shaders/water.gdshader` and the kit scripts, and nudge values rather than introducing new hues.

## Ground rules (read first)

- Project: Godot 4.8-dev RTX fork, `F:\ww2_dlss`, engine `F:\godot-rtx`. 1 unit = 1 m horizontally, y = elevation x 2. TILE = 1800 m.
- **Loading time is a hard constraint.** Loading is about 40 s for an 8 km preload. Do not add main-thread work per tile (>5 ms per tile is too much). Anything per tile must be computed in `Scatter.tile_landcover_data` (runs on a worker thread) and only nodes/MultiMeshes created in `_finish_tile`.
- **Worker-thread safety:** no `get_node`, no `GroundKit.side_at`/`era_date`, no scene access in code reached from `Scatter.tile_landcover_data`. `GroundKit.raw_y` and `water_dir` are safe.
- Use MultiMesh for repeated objects. Keep new instance counts per tile in the low hundreds.
- Another Claude thread may have uncommitted edits in the folder (`camera_rig.gd`, `main.gd`, `cockpit_interior.gd`, `models/gltf_models.gd`, many `.import` files). **Stage only your own files** with explicit `git add <files>`. Never `git add -A`. Never use `hash-object` on a file.
- New `class_name` script files need `godot --headless --path F:\ww2_dlss --import` once before they run.
- Palette: keep greys, chalk whites, sand, olive/khaki greens, muted blues already used. No saturated colours.

## What already exists (do not rebuild)

Water: depth bands, swell normals, whitecaps, shoreline foam rings, sun glints (`shaders/water.gdshader`). Terrain shader: field patterns, furrows, stubble, marsh, rivers, lakes, cloud shadows, beach block (sand, wet sand, ripples, wrack, dune fringe). Cliffs: `scripts/ground/cliff_skirt.gd`. Barrage balloons `barrage_balloon.gd`, searchlights `searchlight.gd`, chimney smoke `chimney_smokes.gd`, burning ruins, landmarks (incl. lighthouses) `landmarks.gd`, ship wakes in `ground_ship.gd`, windsocks in `airfield.gd`, radar in `ground_structure.gd`, BeachKit defences `beach_kit.gd`.

## Tasks (do in order; build, test and commit after each)

### 1. Surf zone (water shader) - ALREADY EDITED, NEEDS VISUAL CHECK
`shaders/water.gdshader` already has a new `surf_zone / surf_line / surf` block (rolling shoreward foam lines). Not yet viewed. Check it renders (no shader errors, lines visible near beaches, not a hard stripe pattern, not shimmering). Tune `0.42` (line spacing), `0.55` (speed) and the `0.85` weight if needed.

### 2. Chalk cliffs
In `scripts/ground/cliff_skirt.gd` and the cliff part of `shaders/terrain.gdshader`: make chalk faces read whiter with vertical weathering streaks, darker grass cap and a rubble/talus fan at the foot. Targets: Dover, Beachy Head, Seven Sisters, Isle of Wight (Needles).

### 3. Hedgerows and field edges
In `scripts/ground/scatter.gd` (tile scatter) strengthen hedgerow lines along field borders: slightly darker continuous strips with the occasional taller hedgerow tree. Reuse existing hedge meshes. Keep within the current instance budget.

### 4. Town texture
`scripts/ground/scatter.gd` / `rural_kit.gd`: add church spires or towers at town centres, terraced rows (long thin roofs) along streets, a gasworks drum or railway yard where a rail line meets a town. Reuse existing materials.

### 5. Heath, downs and woodland tone
`shaders/terrain.gdshader`: broader tonal variation over chalk downs (paler), New Forest / Surrey heath (heather brown + gorse olive patches), woodland edge darkening. Colours must be existing palette entries.

### 6. Tidal flats and estuary banks
Terrain shader plus the coast mask: where the sea meets a very low flat area (estuaries: Thames, Medway, Solent, Humber) add a band of wet mud/sand flat with a faint sheen and channel patterns. Reuse `mud_col`.

### 7. Harbours
Extend `scripts/ground/port_clutter_kit.gd` and `sea_defence_kit.gd`: breakwaters, piers, moored small boats, cranes. Also the queued items: more ports, quarries (pale pits in the downs), canals, and airfields around Bournemouth and Southampton.

### 8. Blackout / night towns
At night (see `TimeOfDay`), towns should be mostly dark with a few dim lights; airfields stay lit only when active. Check `scripts/ground/airfield_activity.gd` and `civil_defence_kit.gd`.

### 9. Atmosphere polish
Low haze near the horizon (fog parameters in the environment, not new nodes), warmer low sun at dawn/dusk, drifting cloud shadows (exists in `cloud_field.gd`/terrain shader: just raise contrast slightly). Seasonal autumn tints already exist in `scatter.gd`: extend carefully.

## Per-task checklist

1. Make the change. Keep it small and reversible.
2. Run a render check: `tools/cache/shots.ps1 -jobs "name|extra args" -at "lat,lon,alt,heading"` then look at `tools/shots/name.png`. (`--at` is not always exact; try a few positions near the target coast.) Check `tools/cache/shots.log` for script errors.
3. Check the load time is unchanged: run with `--loadprof` and compare the `[load] scenery ready ... wall` line (was about 10-15 s wall in the test run for a 3 km area).
4. Commit with `git add <your files>` only. Message ends with:
   `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`
   `Claude-Session: https://claude.ai/code/session_01H7JMasEMLG65d41xgBWNEp`
5. Releases: build the exe with `godot --headless --path F:\ww2_dlss --export-release "Windows Desktop" F:\ww2_dlss\build\WW2ChannelAirWar.exe`, zip only `.exe` and `.dll` from `build`, tag the next point release (v6.4, v6.5, ...) and `gh release create`. Pattern: `tools/cache/rel63.ps1`.

## Definition of done

Each task: renders correctly in a screenshot, no new script errors, load time not noticeably worse, committed. Stop and report if a task needs more than a modest change to the loading pipeline.
