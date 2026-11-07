# Desert visual audit: data pass and hook list

Scope of this pass: data and tooling only. Nothing below is wired into the game. (Shader, height field and airfield code
belong to the parallel pass.) Status verified against the code on 2026-11-07.

## 1. New data (all derived, rebuildable)

| File | Built by | Notes |
|---|---|---|
| data/desert/region_landcover.bin/.json | tools/make_desert_landcover.py | 7000 x 2770 (about 300 m/px, same grid as the heightmap), one byte per cell, format of scripts/land_cover.gd `_load()` |
| data/desert/region_urban.png | same | 8-bit soft town mask, 1x land-cover grid (Channel's is 2x; use `--urban-scale 2` if needed), outline at 0.5 |
| data/desert/landcover_zones.json | hand | curated polygons / corridors / circles, oases, urban radii; every zone has a heightmap `check` |
| data/desert/tracks.json | tools/make_desert_tracks.py | 67 derived pistes (about 4,500 km), schema of osm/roads.json, `k: "track"`, `derived: true` |
| data/desert/war_scenery.json | tools/make_desert_war_scenery.py | dated: harbour wrecks, defence lines, boxes, passes, battle wrecks, airfield damage, damage areas |
| build/desert_landcover_preview.png | same | colour preview with hillshade |

Class ids reuse WorldCover numbers where the meaning is the same (10 tree, 20 shrub, 30 grass, 40 crop, 50 built, 60 bare,
80 water, 90 wetland; 0 = sea). New desert ids, all unknown to today's consumers (they fall through every `match`):
110 coastal sand, 111 sabkha, 112 hamada, 113 reg, 114 rock, 115 erg, 116 salt pan, 117 wadi, 118 limestone (Malta,
Hyblaean), 119 basalt, 120 oasis, 121 orchard (olive, citrus). `region_landcover.json` lists them under `classes`.

Landcover.gd needs no change to read the grid. Its `urban_mask()` fallback is not needed because region_urban.png exists.

### Caveats
- **LandCover.ready() is now true on the desert map.** That would have switched world_populator onto the Channel async
  tile path (hedges, farms, terraced houses). I added a guard (`GameState.current_map != "desert"`) at
  world_populator.gd lines 2422 and 2437, so behaviour is unchanged. Remove it when the desert tile hook (hook 2) lands.
  Scatter.make_tile already returns `_desert_tile` before it consults LandCover.
- Siwa (29.20N) and Jarabub (29.75N) are south of lat_min 30.0 and cannot exist; the Qattara Depression and Calanscio sand
  sea are cut by the southern edge. They are kept as skipped entries in the zones file for a future bounds extension.
- Heightmap is clipped at 0 m, so Qattara's floor and the Nile delta read as 0 m land (the coast mask separates them from
  sea). Qattara's salt crust is therefore drawn where elevation is 0 inland.
- Natural Earth 10 m coast does not resolve harbour inlets. Tobruk harbour, Grand Harbour, Marsamxett and Marsaxlokk are
  mask-land (flagged `harbour_in_mask_land` on the wrecks); El Agheila, La Goulette and Bizerte centres fall in mask sea.
- Zone shapes are hand-placed (+-10 km) and war positions are +-3 to 10 km with a `confidence` field. locations.json puts
  `halfaya_pass` at 31.35N 25.1E, about 20 km inland of the real pass (about 31.50N 25.2E, 2.6 km from the shore); war_scenery
  uses the latter.
- A 300 m grid makes class edges blocky below about 600 m altitude; the shader has to add its own detail inside each class.
- Tracks hug the coast: roads.json is sparse and has no Via Balbia, so the coast piste serves as it.
- `tracks.json` is already read by `HeightField._load_dune_roads` (dunes keep clear of it), so it affects dune carving as
  soon as the file exists, before any mesh is drawn.
- New PNGs need one Godot import (tools/hidden/imp.ps1 ran inside test.ps1). Keep `compress/mode=0` for region_urban.png.

## 2. What the desert has now versus the Channel map

| Layer | Channel | Desert today |
|---|---|---|
| Ground colour | satellite mosaic (region_color.png) plus WorldCover-driven fields, urban, wood, regions | procedural `desert_ground` from latitude, height, slope, sea distance, dune mask; no land-cover input |
| Urban ground | `urban_tex` (region_urban.png) and `use_urban` in `_apply_imagery` | none; `_apply_desert` never sets it |
| Towns | Scatter.tile_landcover_data class 50: terraced rows, district bands, parks, bomb shells | `_desert_tile` places only scrub and oasis palms; no houses |
| Trees, fields, hedges | classes 10/20/30/40 | sparse scrub only (density from height and sea distance) |
| Roads, rails | RoadMesh and RailKit from osm_dir | same code and sparse Natural Earth lines; no tracks mesh |
| Water | coast mask plus sea_tex | same (works) |
| Bomb damage | WarDamage areas | gated off for desert (war_damage.gd:49) |
| Battlefields, floods | WarGround | gated off (war_ground.gd:26) |
| Build-up | BuildupKit | gated off (buildup_kit.gd:23) |
| Airfields | full kit | desert strip with tents (world_populator.gd:2966); other agent is editing |
| Regions palette | RegionMap | skipped, no baked file |

## 3. Hooks to add, in order of visual impact

1. **Land-cover texture into the terrain shader** (biggest win). In `_apply_desert`, load a class texture built from
   region_landcover.bin (R8, nearest or a 2-tap blend at class edges; same rect as `map_rect`, that is world_bounds) plus a
   small LUT (class id to albedo, roughness, strata strength, detail scale). Feed `desert_ground` per-class base colours
   instead of latitude only. Per-class cues: 116 bright crust, 117 darker damp bed, 112 pale limestone, 113 dark gravel,
   114 strata banding by slope, 115 hand over to the dune mask, 118 honey stone, 119 near-black, 120/121/40 green, 20/30
   olive-grey. Needs a `Texture2D` uniform in terrain.gdshader (other agent's file). Cost: one extra sample.
2. **Desert tile scatter driven by class** (`Scatter._desert_tile`). Call `LandCover.class_at` on the 60 m jitter grid:
   shrub density per class (20 thick, 60/112 sparse, 113/116 none), olive grid rows for 121, palms at 120, rock props for
   114, stone-wall terraces for 40 and 118 on Malta. Then drop the world_populator guard so tiles can use the async path
   (`tile_landcover_data` would need a desert branch; keep the Channel branch untouched).
3. **Urban ground and desert houses.** In `_apply_desert` load region_urban.png into `urban_tex`/`use_urban`, and make
   `desert_ground` blend packed street earth where it is set. In `tile_landcover_data` class 50 on desert, use a desert style set
   (flat-roof boxes, courtyards, domes and minarets, no chimneys or pitched roofs) instead of terraced Channel houses.
   `_built_near`, `_built_frac` and `_exclude` already work from class_at.
4. **Track meshing.** RoadMesh loads only `osm_dir/roads.json`. Add a second source for `heightmap_dir/tracks.json`, kind
   `track`, width entry in `WIDTHS` (3.5 m) and a pale, dusty material variant; `RoadMesh.near_road` should include them so
   scatter keeps clear. TransportNetwork (`_load_osm`) is the second consumer if convoys should use pistes.
5. **War scenery loader** (new `DesertWar` in scripts/ground, modelled on WarDamage: `load_data`, `refresh()` on EraClock
   change, tile jobs read only arrays). Rows by group:
   - damage_areas: same schema as war_damage.json, so WarDamage can read it. Lift the desert gate and make the JSON path
     per map, or merge the rows.
   - defence_lines and fortified_boxes: wire belts, sandbag boxes, minefield markers, trench scars; MultiMesh per tile.
   - battle_wrecks and pass_features: burnt tanks and trucks from existing vehicle meshes (WarGround patterns).
   - harbour_wrecks: hull meshes at the shore; first carve harbour water or snap to the mask shore (inlets are land in
     the mask).
   - airfield_damage: craters and burnt hangars at the airfield sites, gated by the sortie date.
   Date gating via EraClock like WarDamage.
6. **Terrain-shader zones for damage and lines.** The existing `zone_tex` (kind 4 rubble/scorch) already carries Channel
   bomb damage; reuse it for airfield_damage, damage_areas and minefield belts on the desert.
7. **Hydrology and relief cues from class.** Class 117 (wadi) can drive darker bed texture and thicker scrub in the
   desert tile; 114 can drive the height-noise gate in `HeightField` (rocky only). Both are hand-offs to the other pass.
8. **Era-gated settlement growth.** Town masks are about 1940s-appropriate radii; if urban sprawl is to depend on date, add
   a per-town `from` year to landcover_zones.json (not built).
9. **Desert regions palette.** `RegionMap` is skipped for the desert; the class texture in hook 1 replaces it, so no work
   unless macro tinting by region is wanted later.

## 4. How to rebuild
```
python3 tools/make_desert_landcover.py      # about 10 s, deterministic (--seed 7)
python3 tools/make_desert_tracks.py         # needs the land cover first
python3 tools/make_desert_war_scenery.py    # validates every coordinate against the coast mask
```
Validation prints a class histogram, per-zone mean elevation and WARN lines (Qattara, chotts and Sirte checks all pass).
