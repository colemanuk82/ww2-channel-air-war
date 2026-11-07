# PROMPT: make the Desert map visually stunning

You are working on WW2 Channel Air War (Godot 4.7 double precision, project at F:\ww2_dlss). The Desert map (Libya / Egypt / Tunisia / Malta, bounds lat 30.0-37.5, lon 8.0-30.5) shipped in v3.17 and works, but it is far behind the Channel map visually. Your job is to bring it to, then past, Channel quality. The goal is that a screenshot at any altitude makes a player say "that is North Africa in 1942", not "that is a sand-coloured test level".

## Ground rules
- Read first: docs/map_research/DESERT_PLAN.md, docs/map_research/ (Channel research notes), PROGRAM-STATUS-map-next.md (how the Channel map got its quality and how perf was measured), scripts/map_def.gd, scripts/terrain_chunk_manager.gd (`_apply_imagery`, `_apply_desert`), shaders/terrain.gdshader (`desert_ground`), scripts/ground/scatter.gd (`_desert_tile`), scripts/height_field.gd (`_dune_offset`), scripts/world_populator.gd, scripts/airfield.gd, scripts/time_of_day.gd.
- Everything desert-specific is gated on `GameState.current_map == "desert"` / `WorldCoords.active_map`. The Channel map must stay pixel-identical in behaviour; render a Channel shot before and after every change as a regression check.
- Never open visible windows or steal focus: run Godot hidden (tools/hidden/hidden_run.ps1, `--audio-driver Dummy`, PowerShell only via `.ps1 -File`). Do not touch the user's settings.cfg (`--map=desert` is a one-run override). No commit or release unless told "build commit release".
- Performance budget: no desert scene more than 3% worse than the current desert baseline, and no Channel scene worse at all. Measure with the seeded A/B (`--seed=7 --perf=40:90`, same pose, hidden, 1920x1080, 1500-frame settle). Merge static meshes per tile (GroundKit.flatten pattern), use MultiMesh for repeated props, fade small objects with distance, keep draw calls modest (`--perf-dump`).
- Judge every change by looking: render, stage with device_stage_files, open with Read. Never claim a look is fixed without having viewed the result. Always render with enough settle frames (1500) or the terrain will not have streamed. Pose recipe: `--plan=lat,lon,-,1,<alt_m_AGL>,hdg` plus `--at` (same spot, altitude in world units = 2 per metre) plus `--freeze`; see build/desert_af2_*.ps1.
- Work in passes. After each pass produce a contact sheet, list what still looks wrong, then do the next pass. Stop only when every shot on the checklist at the end passes.

## Visual targets, in priority order

### 1. Ground colour and material (biggest win)
There is no satellite imagery for the desert, so build the ground from layered data and rules, not one flat tint.
- Build a desert land-cover mask (data/desert/region_landcover.* in the same format `land_cover.gd` reads, plus an urban mask) from: Natural Earth data already in data/desert/osm, the heightmap (elevation, slope, curvature, drainage accumulation), latitude and distance-to-coast rules, and curated polygons for known regions (see below). Classes: coastal sand and sabkha, limestone hamada plateau, dark gravel reg, rocky escarpment, erg (dune sand), salt pan, wadi bed, cultivated strips (Nile delta west edge, Tunisian north, coastal plain around Benghazi and Derna), olive and scrub (Jebel Akhdar, Tunisian Dorsal), oasis (Siwa, Jarabub, Kufra edge if in bounds), urban.
- Curated regions: Jebel Akhdar (Cyrenaica green belt), the Marmarica plateau, the Libyan Sirte coast (sabkha and salt flats), Gulf of Sirte, Qattara Depression (Qattara sits just south of El Alamein, very low and salt-crusted, with the escarpment edge), Tunisian Dorsal and the Medjerda valley, Cap Bon, Sicily and Malta limestone (Malta is pale honey stone with terraced walls), Nile delta edge.
- Shader: a proper multi-layer material: macro colour variation at 20-50 km, regional mid variation at 1-5 km, micro detail at 1-50 m so the ground has texture at 300 m altitude (pebbles, cracked clay, ripples, scrub speckle), slope-based rock exposure with strata banding on escarpments, darker wet-looking wadi beds, bright salt crusts, vehicle and caravan tracks scarring the coast road and plateau, triplanar or world-space detail so there is no tiling visible from 3000 m. Respect `render_res_factor` and cost: keep it to a handful of texture samples per pixel.
- Colour reference: bleached pale ochre and limestone grey-white on the plateau, warmer orange-red sand inland and south, near-black basalt and gravel patches, dull olive and grey-green scrub on the Jebel Akhdar and Tunisian hills, vivid but small green oasis and delta fields. Avoid uniform cream or white. Aerial contrast comes from slope shading, shadows and tonal patches, not saturation.

### 2. Relief and landforms
- Dunes (already started in height_field.gd `_dune_offset`): make erg areas clearly dune-shaped at 600 m and 3000 m: seif (long linear) dunes NW-SE, barchans at edges, star dunes optional, with lit and shadowed slip faces, crest highlights, wind ripples. Mask them to real erg areas and keep roads, airfields, wadis and salt pans flat. Heights must be a pure function of position so mesh, collision and scatter agree.
- Escarpments and wadis: sharpen the heightmap detail that already exists (z9 terrarium is about 1 km pixels at this scale) with procedural detail noise gated by slope: eroded cliffs on the Libyan escarpment (Sollum, Halfaya, Jebel Akhdar scarp, Qattara scarp), steep-sided wadis with branching dendritic drainage, mesas and buttes (jebels), rocky outcrops. Add small-scale height noise only in the rocky classes.
- Coast: beaches with a wet-sand band, rocky headlands, cliffs where Natural Earth and slope say so, sabkha tidal flats along the Sirte coast, shallow turquoise water over the shelf transitioning to deep blue, foam lines, reefs, harbours with breakwaters (Tobruk, Benghazi, Tripoli, Alexandria, Bizerte, Valletta Grand Harbour).

### 3. Settlements, roads and infrastructure
- Towns and cities from data/desert/osm/towns.json and locations.json: flat-roofed whitewashed and sand-coloured blocks, minarets and domes, walled old towns, European-style quarters in Italian colonial towns (Tripoli, Benghazi, Tobruk), harbour quays, palms. Use the Channel house scatter machinery with a desert style set: low flat-roof boxes, few windows, courtyard walls, no pitched roofs, no chimneys. Ruins and shell damage at Tobruk, Bardia, Sollum, Mersa Matruh (dated).
- Roads: the Via Balbia coast road and the Tripoli-Tunis, Alexandria-Cairo and Tobruk-El Adem tracks as pale compacted ribbons with dust shoulders, plus tracks and pistes across the plateau with clear tyre-scar patterns. Railways: Alexandria-Mersa Matruh and the Tunisian lines.
- Add a denser derived track network between airfields, towns, wells and oases (procedural but plausible; document that it is derived).

### 4. Vegetation and props
- Scrub: low thorn and camel-thorn bushes in clumps following wadis and shallow depressions, sparser on plateau, denser on the Jebel Akhdar and Tunisian hills. Use MultiMesh with 3-4 mesh variants, wind sway on LOD0 only.
- Palms: real date-palm meshes (tall trunk, crown), groves at oases, in wadi mouths and around coastal cities. Olive groves and cypress lines in Tunisia and the Jebel Akhdar. Cultivated strip fields with irrigation channels at the Nile delta and Tunisian north.
- Rock props and boulder fields on rocky classes; occasional wells, cisterns, Bedouin tents, cairns, abandoned fort ruins (Italian forts Capuzzo, Maddalena, Sidi Omar, Bardia walls).

### 5. Airfields (landing grounds and main bases)
- Forward landing grounds: a rectangular area of scuffed pale earth, faint taxi scars, a few oil-drum markers and flags rather than painted runways, dispersal bays with sandbag or oil-drum revetments, canvas bell tents and marquees, camouflage netting, fuel bowsers, lorries, water bowser, field kitchen, a small control tent or hut, a bright oversized windsock, aircraft parked by side and era (Hurricane, Blenheim, Kittyhawk, Bf 109E/F, Ju 87, Ju 52, Macchi C.200, CR.42; Sunderland and Beaufighters at main bases), dust halo and trampled earth in the terrain shader around the field.
- Main bases (Luqa, Hal Far, Ta Kali, Benina, Tunis El Aouina, Castel Benito, El Adem, Gambut, Sidi Haneish, Heliopolis if in range): hangars, tarmac or steel-plank strips, control towers, barrack blocks, blast pens, flak sites, bomb dumps. Malta fields in honey limestone with dry-stone walls and dispersal pens carved into stone.
- Scene dressing near airfields: slit trenches, AA positions, searchlights, radar masts (Chain Home equivalent), dust plumes from taxiing aircraft.
- Era gating: fields exist only for their dated periods (e.g. Tunisian fields from late 1942, Luftwaffe on Tunis fields Nov 1942 to May 1943); set up the `era` fields in data/desert/locations.json (read EraClock).

### 6. Atmosphere, light and weather
- A desert sky: pale blue gradient to a milky-brown horizon, heat haze near the ground, dust haze layers thickening towards the horizon and with altitude inversion; sun glare with warm light and cool blue shadows; strong long dawn and dusk shadows (the desert shows relief best at low sun, so make time-of-day lighting count).
- Ground-hugging dust and sand-storm weather (ghibli): a Khamsin sandstorm weather preset with a rolling wall of dust, low visibility, orange-brown light; plus heat shimmer.
- Clouds: fewer, higher, thinner cirrus and sparse cumulus; avoid the low blobby Channel clouds. Shadow patches of clouds moving over ground make desert flight look alive.
- Contrast: compare desert shots with real WW2 colour photography descriptions: restrained, bleached, golden-hour warmth, deep shadows. Keep the exposure and tone-map so the ground mean is roughly 130-165 at noon with real tonal range, not pale and flat.

### 7. Life and war scenery (parity with the Channel "life and horizon" work)
- Coast road convoys, tank and truck columns trailing dust plumes, camel trains, Bedouin herds, supply dumps and ammunition stacks, tent camps, POW cages.
- Dated war scenery: Tobruk harbour with wrecks and sunken ships, the Gazala Line (boxes with wire and minefield belts, Bir Hakeim), Alamein defences and minefields (the "Devil's Gardens"), Mareth Line, Kasserine, Halfaya Pass (Hellfire Pass), wrecked vehicles and burnt tanks along the coast road, bomb craters and scorch marks around raided airfields, burning fuel dumps. Convoys of ships on the Malta run and in the Mediterranean, and wrecks off Malta.
- Use dated JSON like data/war_damage.json and data/buildup_1944.json as models (data/desert/...), gated on the sortie date through EraClock.

## Method
1. Audit: render the checklist shots at the current state, one contact sheet, and write docs/map_research/DESERT_VISUAL_AUDIT.md listing everything that looks weak compared with the Channel map (compare against equivalent Channel shots).
2. Land-cover and urban mask (target 1), then shader material, then relief (target 2). View after each.
3. Settlements, roads (target 3), then vegetation (target 4).
4. Airfields (target 5), then atmosphere (target 6), then life and war scenery (target 7).
5. Perf pass: seeded A/B for each checklist scene, fix anything over budget (LOD, merging, MultiMesh, distance fades), confirm the Channel numbers are unchanged. Run tools/hidden/test.ps1 (TESTS OK required) after every pass.
6. Final: contact sheets, a short changelog, and a list of what remains.

## Acceptance checklist (render each at 300 m, 600 m, 1200 m, 3000 m where noted, noon plus one dawn or dusk shot)
- Tobruk harbour and the Via Balbia coast road (600 m, 3000 m)
- El Alamein line and the Qattara escarpment (600 m, 3000 m)
- Jebel Akhdar green belt and the Cyrenaican coast near Derna (600 m, 3000 m)
- Sirte coast sabkha and salt flats (600 m, 3000 m)
- Erg and dune field in the low sandy interior (600 m, 3000 m, dusk)
- Malta: Grand Harbour, Valletta, Luqa (300 m, 1200 m, 3000 m)
- Tunis, Bizerte and Cap Bon (600 m, 3000 m)
- Tripoli and the Jefara plain (600 m, 3000 m)
- Alexandria and the Nile delta west edge (600 m, 3000 m)
- Three airfields (El Adem, Luqa, Tunis El Aouina) at 300 m and 1200 m
- A Khamsin sandstorm shot and a dusk shot with long shadows
- Channel regression shot (Dover, 600 m): unchanged

A shot passes only if: the ground has visible tonal and textural variation at that altitude, relief reads clearly, the place is recognisable, there is no white wash-out, no floating objects, no stepped shorelines or visible tiling, no Channel content leaking in, and the frame rate is within budget.

## Deliverables
Code and data changes (desert-gated), the audit and changelog docs, build/desert_v3_*.png shots with contact sheets, perf numbers (before and after), and a short list of known gaps. Do not commit or release.
