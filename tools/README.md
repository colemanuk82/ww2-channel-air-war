# tools/ : map-data pipeline

Python 3.10, deps: `numpy pillow requests` (`pip install numpy pillow requests`).
Run everything from the project root `F:\ww2`.

| Script | Output | Notes |
|---|---|---|
| `build_locations.py` | `data/locations.json`, `data/missions_seed.json` | Hand-authored real coordinates. Edit lists in the script, re-run. Records outside the playable bounds (Duxford, Debden, Mont Saint-Michel) carry `in_bounds:false`. Target `side_owner` is `"Axis"` or `"Allies"`; airfields use `"RAF"`/`"Luftwaffe"`. Convoy-route targets also have a `path` of `[lat,lon]` points. |
| `make_heightmap.py` | `data/heightmap/region_height.png` (16-bit, 65535 = 1000 m, sea = 0) + `region_meta.json` | Downloads AWS Terrain Tiles (terrarium, z10, cached in `tools/cache/`), resamples to 6144x3000 equirectangular north-up (`--zoom 10 --width 6144 --height 3000`; z9/3072x1500 was the old build). If offline: procedural fallback (hand-authored coastline + noise + chalk cliffs). Force it with `--force-procedural`. `region_meta.json` has a `source` field. **Rivers are carved after this, by `carve_rivers.py`.** |
| `make_coast_mask.py` | `data/heightmap/region_coast.png` (L8, 7680x3616, 255 = land, 0 = sea) + `region_coast_meta.json` | **The authoritative land/sea mask.** Rasterises the OpenStreetMap land polygons (osmddata.openstreetmap.de `land-polygons-split-4326.zip`, cached in `tools/cache/`; falls back to the complete zip, then the download page, then `data/osm/coast.json` — reported on stdout) at ~126 m/pixel with anti-aliased edges and islands as holes. `HeightField` uses it to decide land/sea exactly (inlets like Poole Harbour, islands like Brownsea) and the DEM only for elevation. Read with `pyshp` (`python3 -m pip install --target F:/ww2_dlss/tools/cache/pylibs pyshp`; run with `PYTHONPATH=F:/ww2_dlss/tools/cache/pylibs python3 tools/make_coast_mask.py`). Delete the PNG to fall back to the old DEM B-spline coastline. |
| `carve_rivers.py` | `data/heightmap/region_height.png` (carved) + `region_meta.json` (`rivers_carved`) | Lowers the DEM along `data/osm/rivers.json` (river/canal/stream depth, feathered banks) so the `RiverMesh` ribbons sit in real valleys. Backs the pre-carve PNG up to `tools/cache/region_height_pre_rivers.png` once. Run it after `fetch_osm.py` + `make_heightmap.py`, before `fetch_imagery.py` / `make_urban_mask.py`; re-run the engine import afterwards. The game also works without it (ribbons drape on the ground). |
| `fetch_osm.py` | `data/osm/{roads,rails,rivers,coast,woods,towns}.json`, `_source.json` | Overpass API, tiled, retried over mirrors, Douglas-Peucker simplified. Per-layer fallback to synthetic data (roads/rails link the cities in locations.json over land; hand-drawn rivers; coast from polygons; woods blobs). `--layers roads,rails` to limit, `--force-fallback` to skip network. `_source.json` says `overpass` or `fallback` per layer. Raw responses cached in `tools/cache/osm`. |
| `fetch_imagery.py` | `data/heightmap/region_color.png` (4096x2048 RGB, north-up, equirectangular) | Real terrain imagery draped on the terrain shader. `--source eox` (default, Sentinel-2 cloudless, CC-BY), `esri` (World Imagery) or `osm` (OSM carto). `--zoom` (default 10) sets tile detail, `--width/--height` the output size. Tiles cached in `tools/cache/imagery/<source>/<z>/`. Only the terrain shader uses it; delete the file to fall back to the painted palette. |
| `fetch_landcover.py` | `data/heightmap/region_landcover.bin` + `.json` (+ `.png` debug view) | ESA WorldCover 10 m land cover (CC-BY) window-read straight from the public COGs (needs the `rasterio` package). Drives 3D placement: trees on tree cover, buildings on built-up, hedgerows on cropland. `--width/--height` (default 2048x1024) set the grid; delete the `.bin` to fall back to the painted/random scatter. |
| `validate_data.py` | stdout | Schema checks, counts, bounds, file sizes, Dover/Channel heightmap sanity, and `latlon_to_world` for Dover, Calais, London, Antwerp. Exit 1 on error. |

## Chalk-cliff geometry (engine, not a python tool)
`scripts/ground/cliff_skirt.gd` (`class_name CliffSkirt`) appends a near-vertical face mesh along the
OSM coastline inside the five chalk `cliff_zones`, so Dover / South Foreland / Seven Sisters / Cap
Blanc-Nez / Etretat read as cliffs instead of ramps. Both the DEM (~150 m/px at z10) and the coast
mask (~126 m/px) are too coarse to hold a ~100 m face in the terrain grid, so `TerrainChunkManager._build_arrays()`
calls `CliffSkirt.build_chunk()` per tile (marching-squares contour of the mask, quads from a little
below sea level up to the DEM cliff-top height `HeightField.cliff_top_m_w()`); the tile's terrain
material paints them with the shader's chalk zones. Rebuilt with each streamed tile, so it follows
the LOD. If the coast looks ramped again, check the mask is loaded and the cliff zones still cover the
coast.

## OSM JSON formats (all `[lat, lon]`)
- roads/rails/rivers/coast: `{"lines":[{"k":"motorway","n":"optional name","pts":[[lat,lon],...]}]}`
- woods: `{"polys":[{"pts":[[lat,lon],...]}]}` (closed rings)
- towns: `{"towns":[{"name","lat","lon","kind":"city|town|village"}]}`

## Accepted synthetic data (intentional - NOT a bug or a TODO)
- **Kent (tile 21) and Pas-de-Calais (tile 16) roads are the synthetic fallback** - those Overpass tiles never downloaded, so `fetch_osm.py` / `fetch_osm_fill.py` generated fallback roads there. Accepted as-is.
- **Rails, coast, woods and towns for the expanded NE map area are synthetic or missing** (`_source.json` records `overpass` vs `fallback` per layer). Accepted as-is.
- Re-running `fetch_osm.py` (+ `fetch_osm_fill.py`, `merge_osm_cache.py`) is only needed if a real-data look is wanted; it is NOT required. Do not treat the current state as a bug or a pending task.

## Regenerate everything
```
python tools/build_locations.py
python tools/make_heightmap.py
python tools/make_coast_mask.py
python tools/fetch_osm.py
python tools/carve_rivers.py
python tools/fetch_imagery.py
python tools/fetch_landcover.py
python tools/validate_data.py
```
Delete `tools/cache/` to force fresh downloads.
