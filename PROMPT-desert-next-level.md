# PROMPT: Desert map, next level — living desert, towns, dunes, battles

You are working on WW2 Channel Air War (Godot 4.7 double precision, project at F:\ww2_dlss). The Desert map (Libya / Egypt / Tunisia / Malta, lat 30.0-37.5, lon 8.0-30.5) shipped in v3.17 and got its visual pass in v3.18. It now looks like North Africa from the air, but it is still a diorama, not a place: too much empty ground, towns with gaps, airfields that read as circles, no war on the ground and no reason to fly from one end to the other.

This pass is about **life and coherence**, not another colour tweak. A player flying Tobruk -> Alamein should pass camel caravans, hamlets and oases, dust trails from moving columns, a tank battle, wrecked armour, and landing grounds that sit in the landscape instead of being stamped on it. Bring your own artistic judgement: where a real feature is missing, add a plausible desert-themed one. Nothing in this prompt overrides the Channel map staying unchanged.

## Ground rules

- Read first: `docs/map_research/DESERT_VISUAL_AUDIT.md`, `PROMPT-desert-stunning.md`, `HANDOFF.md`, `PROGRAM-STATUS-map-next.md`, `scripts/height_field.gd` (`_dune_offset`, `dune_region_mask`), `scripts/ground/desert_town.gd`, `scripts/ground/desert_scatter.gd`, `scripts/ground/desert_war.gd`, `scripts/ground/desert_airfield_kit.gd`, `scripts/airfield.gd` (`_pad`, `_flatten`, `_build_mesh`), `scripts/world_populator.gd`, `scripts/bail_out.gd`, `scripts/modes/ops_room.gd` (`_make_rescue`, `_sea_from_player`), `scripts/modes/ditch_rescue.gd`, `scripts/modes/dinghy.gd`, `scripts/era_clock.gd`.
- Everything desert-specific is gated on `GameState.current_map == "desert"` / `WorldCoords.active_map`. Render a Channel shot before and after to prove no regression.
- Hidden runs only: `tools/hidden/hidden_run.ps1`, `--audio-driver Dummy`, PowerShell via `.ps1 -File`. Never steal focus. Never touch the player's real `settings.cfg`; build/test with `APPDATA` pointed at a scratch folder (build10b.ps1 already does this). No commit or release unless told "build commit release".
- Tests: `tools/hidden/test.ps1` must print `TESTS OK`, and `scenes/tests_desert.tscn` must stay green. Add checks for every new pure function (town density, dune edge feathered to zero, rescue side/terrain decision, extra airfields within bounds and not in the sea).
- Performance is a hard budget: no desert scene more than 3% worse than the v3.18 baseline, Channel unchanged. MultiMesh everything repeated, merge static meshes per tile (`GroundKit.flatten`), fade small props with distance, cap moving groups near the player. Measure with the seeded A/B on a quiet machine.
- Judge by looking. Render at 300 m, 600 m, 1200 m and 3000 m, plus low sun, and view the image before claiming a change. 1500 settle frames or the terrain will not have streamed. Pose recipe: `--plan=lat,lon,-,1,<alt_m_AGL>,hdg --at=lat,lon,<world_y>,hdg --freeze` (altitude in world units = 2 per metre).

## 1. Bugs to fix first

### 1a. Air-sea rescue must never happen in the middle of the desert
The trigger is `scripts/bail_out.gd` around line 180:

```gdscript
if FX.is_water(pos) or pos.y < 1.5:
    fate = "sea"
```

`pos.y < 1.5` is a Channel-ism. On the desert, the DEM is clipped at 0 m and `HeightField._mask_elev()` floors low land at 0.2-1.0 m, so Qattara, the Nile delta, the Sirte sabkha, the chotts and the coastal flats sit at world Y 0.4-2.0 and are classified as sea. The player lands inland and gets a dinghy, a green dye patch and "Ditched in the Channel. Rescue flight launching...".

- Decide "sea" from the actual water test only: `FX.is_water(pos)` / `HeightField.coast_land_w()` with a depth margin (e.g. more than ~1.5 m below the water plane), never from `pos.y`.
- Inland desert landings must resolve to `safe` (own side / open desert) or `captured` (enemy side). Add a desert fate text ("Down in the desert - walking out" / "captured by the Afrika Korps"), do not reuse Channel wording.
- Same audit for the other call sites: `main.gd` crash reason `"ditched"` -> `DitchRescue.start()` (only when actually in water), `main.gd _on_bail_resolved()` (`fate == "sea"`), and `OpsRoom._make_rescue()` / `_sea_from_player()` / `_sea_point_near()` (those already test `GroundKit.raw_y < -6`; keep that, and reject inland lakes and sabkha that are above the water plane).
- `Dinghy` must never spawn on dry land. Test: a point on the Qattara floor, the delta and a coastal flat must all be "land", a point 10 km offshore must be "sea".

### 1b. Some town buildings do not show
Towns come from `DesertTown.add_houses()` (`scripts/ground/desert_town.gd`). Buildings are culled by a stack of conditions that can empty a whole district:

- only land-cover class 50, from a 300 m grid (`LandCover.class_at`, wobbled 120 m);
- `_built_frac(p, 34.0)` must be >= 0.99, else a probabilistic drop;
- 12% of plots empty, whole lane rows skipped (1 in 5 and 1 in 4), steep-bank rejection, `_okc()` and `RoadMesh.near_road()` keep-outs;
- mosques only where `_mosque_pos()` rolls under 0.38 and the cell is class 50.

Result: town fringes read as pale gravel with a scatter of white dots, and some districts have no buildings at all.

- Audit first: add a headless census (per town: class-50 area vs house count vs mosque count) and print the worst offenders.
- Then fix the placement: every built-up district must produce a plausible block structure; lower the `_built_frac` cliff to a smooth density ramp; do not skip both lane families at once; add low-density fringe/hamlet placement so the built area frays into the desert instead of stopping at the 300 m cell edge.
- Streets must read at 600 m: blocks around lanes, courtyards, dead ends, a few larger compounds. No buildings floating on slopes; no gaps left where a district was rejected.
- Verify at 300 m, 600 m and 3000 m, and on the painted map / minimap.

## 2. Dunes: adopt the dune-generator technique, but with smooth edges

Reference: https://github.com/WildTangent4/dune-generator (Godot 4, `generate_dunes.gd`).

What that project does and what to take:

- **Triangle-strip grid** with alternating row direction, and a **pipeline of callables** applied per point (`run_pipeline`).
- `apply_sin_shifting_angle()`: a sine along one axis whose phase is shifted by `tanh(noise) * amplitude`. That is the core trick: the crest line meanders with the noise field, so the ridges are never straight.
- A stack of further sines of **decreasing amplitude, increasing frequency, at varying angles**, so one dune field has large primary ridges plus smaller secondary ripples.
- A **Perlin/simplex layer** added on top so the repeating sine pattern never reads as a pattern.
- A **threshold clamp** that pulls low points up toward a floor, simulating bedrock under the sand.
- Known issues in that repo: jagged patch edges, normal banding from computing normals row-by-row before the next row exists, poor performance at large grids, visible repetition.

How to apply it here:

- Keep `HeightField._dune_offset(wx, wz, e)` a **pure function of world position** (mesh, collision, scatter, aircraft ground height all sample it). Do not replace the terrain chunk mesher with a triangle-strip mesh.
- Build the dune height as that pipeline: primary shifting-angle sine + 2-4 secondary sines (decreasing amplitude, increasing frequency, different angles) + one noise term + a soft bedrock floor. Use the existing `DUNE_DIR` / `DUNE_ACROSS` so crests stay NW-SE.
- **Smooth edges are a requirement, not a nice-to-have**:
  - Feather the whole dune amplitude to exactly 0 at the `dune_region_mask` boundary with a wide smoothstep (at least 20-30% of the patch radius). No hard edge, no cliff, no ring of faceted triangles where the field stops.
  - Feather to 0 around roads, tracks, airfields, towns and oases with a noise-warped boundary, not a perfect circle.
  - Compute normals analytically from the same height function (central differences on X and Z) for the shading path. If you touch mesh normals, build the whole grid first and smooth across rows — never per-triangle-in-generation-order (that is the repo's banding bug).
  - Vary the primary wavelength by warping the phase slowly (the current implementation already does this); make sure it does not repeat visibly at 6 km.
  - Keep the asymmetric profile (long windward slope, short steep slip face) and the barchan gaps.
- A/B against `--desert-v1` and render 600 m, 1200 m, 3000 m and an oblique low-sun shot. The acceptance test is: no straight edge, no visible repetition, no shading bands.

## 3. More features: make the desert lived-in (artistic licence encouraged)

Everything below is dated through `EraClock` where it represents war, and independent of the date where it is landscape.

### 3a. People and animals
- **Camel caravans**: 6-20 camels plus handlers, moving along pistes and between wells, oases and the coast. Grouped, not scattered; a dust puff at their feet; slow walking animation or at least leg/bob motion; visible from 600 m.
- Bedouin camps: goat-hair tents, thorn fences, a few goats/camels, fire smoke at dawn/dusk, wells and cisterns.
- Flocks and herds near oases and the delta; birds over water.

### 3b. Extra places (not necessarily real)
- **Extra mini towns / hamlets / villages** between the big bases, to break the long empty stretches: a mosque, a well, a market, 10-40 flat-roofed houses, palms, a wall. Place them on flat class-60/112/113 ground, off the pistes' centre, and give them plausible names in `locations.json`.
- **Extra oases**: the real bounds exclude Siwa and Jarabub; add plausible ones inside the map (south of the coast between the known towns). Palms in a ring, a spring/well, irrigated garden plots, a cistern, a few houses, camel pens.
- **Markets**: a souk/market square in every sizeable town - awnings, stalls, crates, carts, livestock pens, a walled yard. Low-cost props only (MultiMesh), no crowds needed at altitude, but the layout must read as a market from 300 m.
- **Mosques**: make them a landmark, not a rarity. Dome + minaret + courtyard, whitewashed or honey stone; at least one per district, plus a Great Mosque in the large towns. Fix `_mosque_pos()` so they are not randomly absent from most 300 m cells.
- Ruined forts, Italian-era blockhouses, cairns, wrecked vehicles and abandoned camps as small points of interest between the towns.

### 3c. War on the ground
- **Tank battles and battle groups**: dated engagements at the plausible places (Gazala, Bir Hakeim, Alamein, Mareth, Kasserine, Sidi Rezegh). Tanks firing (muzzle flash, tracer, dust), burning wrecks, smoke, shell bursts. A battle scene is a cluster of a dozen-plus vehicles with wrecks and craters, not one tank.
- **Moving columns**: tank/truck/armoured-car groups travelling the pistes and the coast road with dust plumes, gated by side and date; a column should be a line of 6-20 vehicles with spacing, not a blob.
- **Convoys on the pistes** and camel trains sharing the same network (`TransportNetwork`), plus supply dumps, fuel dumps and POW cages at the bases.
- Cap active moving groups and battle scenes near the player; everything else is static dressing or fades out.

## 4. More airfields, scattered

The map is 2,500 km wide and has 18 fields, so vast areas have no reason to exist.

- Add **10-20 extra landing grounds / forward strips** across Libya, Egypt and Tunisia (and a couple in Sicily/Malta's orbit), placed on flat, low, class 60/112/113 ground, clear of towns, oases and wadis, with a **minimum separation of roughly 40-60 km** and **sporadic spacing** - not a grid, not evenly spaced.
- Mix the two kinds already in the kit: forward landing ground (scuffed strip, tents, drums, sandbag bays) and a few larger satellite fields (hangars, proper strip, flak).
- Real names where known, plausible invented names otherwise, documented as such in `locations.json`; set era windows with `EraClock`, runway headings where a source exists (do not invent 310 everywhere).
- Every new field must be in bounds, on land, flat enough to land on, on the minimap, reachable by the AI spawn logic, and covered by the tests.

## 5. Airfields must blend into the landscape, not be circles dropped on it

Right now `Airfield._pad()` drops a 12-segment cylinder disc, and the flattening produces a pale oval with a hard edge that is obvious from 1200 m and 3000 m (Tobruk and the Egypt fields are the worst).

- Stop drawing the airfield surface as a disc. Paint it in the terrain shader: one soft, noise-warped mask per field (rectangle or irregular polygon, not a circle), blending the scuffed earth/sand strip into the surrounding land-cover colour over 40-80 m.
- Keep meshes for what should be geometry: runway markings (where the field has a real strip), taxi scars, revetments, tracks.
- Flatten the ground with an **irregular, noise-warped blend boundary**, and make the transition follow the surrounding classes (sabkha, hamr, sand) so the field looks cleared out of the desert rather than stamped on it.
- Add the things that make a field belong: tyre ruts leading off both ends, dust halo, wind-blown sand at the edges of the strip, a few tracks to the nearest piste, sparse scrub re-entering the boundary.
- No circular pads unless a real dispersal circle; if one is needed, break its edge with noise and wear.
- Verify at 300 m, 600 m, 1200 m, 3000 m and at dawn/dusk. A field must be readable as a field from the air but invisible as a shape when compared with the ground around it.

## 6. Method and acceptance

Work in passes, view every pass:

1. Audit: headless town census, list every airfield disc, render a baseline contact sheet (300/600/1200/3000 m at 6 sites plus a Channel control).
2. Fix 1a and 1b, add tests.
3. Dunes (2), render the A/B and the edge close-ups.
4. Towns, mosques, markets, oases, camels, extra hamlets (3a/3b), then war groups and battles (3c).
5. Airfield blending (5) and the extra fields (4).
6. Perf pass, Channel regression, tests, contact sheet, changelog.

Acceptance checklist:

- [ ] Landing/crashing on the Qattara floor, the delta and the Sirte sabkha never starts a sea rescue; an offshore ditching still does.
- [ ] Every town with built-up land has continuous buildings, street structure, at least one mosque and a market; no empty class-50 districts.
- [ ] Dune fields have smooth, irregular edges, no repetition at 3-6 km, no shading bands, and still match mesh/collision/scatter.
- [ ] A 20-minute free flight across the map encounters at least three moving groups, two camel caravans, two extra settlements and one battle, without a frame-rate drop.
- [ ] Every airfield reads as part of the ground at 300 m and 3000 m; no pale disc silhouettes.
- [ ] New airfields are sporadic, spaced, era-gated, on land, and on the map.
- [ ] `TESTS OK` (main + desert), Channel shots unchanged, desert perf within 3%.

Use your own judgement on the specifics - the goal is a desert that feels inhabited and at war, with dunes worth flying low over. If you find a better desert-themed feature, add it.
