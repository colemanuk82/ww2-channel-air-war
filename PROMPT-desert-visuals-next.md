# PROMPT: Desert map — next visual pass

You are working on WW2 Channel Air War (Godot 4.7 double precision, project at `F:\ww2_dlss`). The Desert map (Tunisia, Libya, Egypt, Malta, south Sicily; bounds 30.0-37.5 N, 8.0-30.5 E) shipped its life-and-war pass in v3.19: towns, dunes, airfields, harbours, camel caravans, battle groups, army camps and convoy missions all exist. This task is **purely visual quality** — make it look like North Africa in 1942 from every altitude, not a sand-coloured game map.

Do not add gameplay systems, missions or balance changes. Do not run frame-rate/performance A/B tests (the user runs those); keep draw calls, triangles and texture samples sane and document anything expensive.

## Ground rules

- Read first: `docs/map_research/DESERT_VISUAL_AUDIT.md`, `PROMPT-desert-stunning.md`, `PROMPT-desert-next-level.md`, `scripts/map_def.gd`, `scripts/terrain_chunk_manager.gd` (`_apply_desert`, `_apply_desert_landcover`, `_apply_sea`), `shaders/terrain.gdshader` (`desert_ground`, `desert_dune_shade`, `lc_sample`, airfield/urban/zone blocks), `shaders/water.gdshader`, `scripts/height_field.gd` (`_dune_offset`), `scripts/ground/desert_town.gd`, `desert_scatter.gd`, `desert_war.gd`, `desert_airfield_kit.gd`, `scripts/airfield.gd`.
- Everything desert-specific is gated on `GameState.current_map == "desert"` / `WorldCoords.active_map`; the Channel map must stay visually unchanged. Render a Channel control shot before and after.
- Hidden runs only: `tools/hidden/hidden_run.ps1`, `--audio-driver Dummy`, PowerShell via `.ps1 -File`. Never steal focus, never touch the player's `settings.cfg`. Tests must run with `APPDATA` pointed at a scratch folder (`tools/cache/build10b.ps1` already does this).
- Tests: `scenes/tests.tscn` must print `TESTS OK`, and `scenes/tests_desert.tscn` must stay green. No commit or release unless told "build commit release".
- Judge every change by looking. Render at 300 m, 600 m, 1200 m and 3000 m plus low sun, and view the image. 1500 settle frames. Pose recipe: `--plan=lat,lon,-,1,<alt_m_AGL>,hdg --at=lat,lon,<world_y>,hdg --freeze` (altitude in world units = 2 per metre).
- Work in passes, each with a contact sheet and a written list of what still looks wrong.

## Current weaknesses to fix (in priority order)

### 1. Towns still read as "gravel with white dots" from 300 m
The density fix stopped the empty districts, but there is still no readable urban structure. Make a town legible from 300-600 m:
- Carve the street network into the ground shader, not just the building scatter: arterial roads, a market plaza, lanes between blocks, a walled old town, courtyards and yards. The `urban` mask + `region_urban.png` path already exists; add a street/block pattern derived from the same district frame the buildings use, and make the shader's street earth follow it.
- Give buildings hierarchy: dense two-storey blocks in the core, single-storey sprawl at the fringe, a few larger compounds, warehouses, a cemetery, an Italian colonial quarter. Eliminate the uniform white dotting: vary roof colour/size, and let some blocks be open ground, gardens or ruins.
- Make landmark mosques and markets read from the air: larger minarets/dome, awnings and stalls with colour, a walled courtyard, a visible square of packed earth.
- Frays: no straight class-50 boundary; the town must dissolve into hamlets and palms.

### 2. Ground detail and the 300 m class grid
- The land-cover classes are still visible as blocks in places, and the ground lacks close detail. Add near-field texture at 1-50 m: pebbles and gravel speckle, cracked clay, wind ripples, salt-crust polygons, damp darker sabkha, sheen on wet flats, dust film on tracks.
- Break the class edges further with a second, coarser class lookup blended in, so no 300 m square survives at any altitude.
- Escarpments: strata banding following height, talus and rubble, dark crevices, sun-facing/wind-facing colour differences.
- Wadi beds: darker damp gravel, scrub lines, braided channels, fading correctly with distance.
- Tracks and pistes: pale compacted ribbons with dust shoulders, tyre scars, wandering edges, occasional ruts through dunes.

### 3. Dunes: push the shapes and the light
The dune-generator sine stack is in place. Now make dune fields read like real sand seas:
- Add barchan crescents at field edges, star/draa complexes in the deep south, and a few large transverse ridges; keep them a pure function of world XZ so mesh, collision, scatter and shadows agree.
- Lighting: lit windward faces, dark slip faces, crest highlights, long low-sun shadows, ripples at 1-5 m, sand streaks crossing roads, no shading banding or repetition at 3-6 km.
- Add wind-blown sand: thin streaming sand off crests, dust devils, and sand drift over the piste (visual only).

### 4. Coast, harbours and water
- The 300 m coast mask still gives stair-step shorelines. Improve the visual edge with a shader-side shore blend, foam and a wet-sand band on the land side.
- Harbour quays, breakwaters, moles, bollards, cranes and warehouses at Tobruk, Benghazi, Tripoli, Alexandria, Bizerte, Valletta; ships and wrecks must sit in water at the right draft.
- Shallows: turquoise shelf, sandbars, reef patches, calm lagoon vs deep blue; surf lines and foam that break on the shore rather than a uniform band.
- Sabkha and salt pans: bright crust with damp dark patches, polygon cracks, standing water after rain (dated weather).

### 5. Airfields still read as pale patches
- Make the surface worn and specific: compacted earth, pierced-steel planking, oil stains, tyre ruts, dust halo, tracks leading off both ends and to the nearest piste.
- Blending: the feathered mask must agree with the surrounding land cover (sand, sabkha, hamada); no oval silhouette at 1200-3000 m.
- Dressing that survives altitude: hangars, blast pens, sandbag bays, fuel dumps, parked aircraft, windsocks, camouflage netting, slit trenches; Malta fields in honey limestone with dry-stone walls.
- Malta/Luqa and the big Libyan bases should look different from forward landing grounds.

### 6. Sky, atmosphere and light
- Remove the lavender noon cast; the sky should be a clean pale blue grading to a milky dust horizon. Check dawn, noon, dusk and night.
- Clouds: fewer, higher, thinner; desert cumulus, cirrus and dust haze, not Channel puffs. Cloud shadows drifting over the ground.
- Khamsin: make it a real weather state — a rolling dust wall, orange-brown light, visibility falloff, sand streaming across the ground and past the aircraft.
- Heat shimmer near the ground, haze layers that thicken towards the horizon, sun glare, long cool shadows.

### 7. Vegetation and small life
- Scrub density and shape by class (thick in wadis and oases, sparse on reg/hamada, dense on Jebel Akhdar and Tunisia); 3-4 distinct meshes, wind sway on LOD0 only, dry-grass colour variation.
- Palm groves, olive rows, cypress windbreaks, irrigated plots; orchard/crop edges must not follow the 300 m grid.
- Small props with silhouettes that survive 300 m: wells, cisterns, cairns, Bedouin tents, animal pens, ruins, abandoned vehicles.

### 8. War scenery readability
- Wrecks, wire, sangars, tents and camouflage nets are still tiny/thin above 300 m. Give important clusters a readable silhouette (burnt tank clusters, smoke columns, crater fields, a knocked-out battery).
- Battle scenes: muzzle flashes, shell bursts, burning tanks, smoke that hangs and drifts; visible from 1200 m without looking like grey blobs.
- Convoys and caravans: dust plumes that read from altitude, correct scale, no popping.

### 9. Colour grade and exposure
- Target a restrained wartime palette: bleached ochre, limestone grey-white, orange-red erg sand, near-black basalt, dull olive north. Ground mean about 130-165 at noon with real tonal range, not flat cream.
- Strong contrast at low sun; deep but not black shadows; no neon saturation.

## Method

1. Baseline: render a contact sheet from the fixes in this file (300/600/1200/3000 m at 8 sites: dunes/erg, Tripoli town, Benghazi coast, Tobruk harbour, Luqa, Alamein, Qattara, plus a Channel control). Write a short audit of what still looks wrong.
2. Pass 1: towns (structure, landmarks, fringe) + ground near-field detail + class-edge softening.
3. Pass 2: dunes, coast/water, airfields.
4. Pass 3: sky/atmosphere/khamsin, vegetation, war scenery.
5. Pass 4: colour grade and exposure; final contact sheet at dawn/noon/dusk.
6. Per pass: `TESTS OK` for main + desert, Channel control unchanged, and a list of what remains.

## Acceptance checklist

- [ ] A town at 300 m has readable streets, a plaza, a mosque silhouette and a market; no uniform speckle.
- [ ] No 300 m class squares or 85 m field checkerboards at any altitude.
- [ ] Dune fields have varied shapes, smooth edges, slip-face light and no repetition at 3-6 km.
- [ ] The shoreline has no stair-steps, with a wet-sand band, foam and readable harbours.
- [ ] An airfield is identifiable as a field but has no pale oval edge at 1200-3000 m.
- [ ] Noon has no lavender cast; khamsin reads as blowing sand and dust, not fog.
- [ ] A 300 m pass over a town, coast, dunes and airfield produces no visible tiling, banding, z-fighting or decal edges.
- [ ] `TESTS OK` (main + desert); Channel shots unchanged.

Use your own judgement: the target is "that is North Africa, 1942" at every altitude, from a 30 m beat-up of a piste to a 3000 m map view.
