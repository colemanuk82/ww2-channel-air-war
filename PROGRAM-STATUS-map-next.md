# Phase board: map next level (PROMPT-map-next-level.md)

Perf budget: no scene more than 3% worse than the v2.3 baseline.

## How perf is measured (changed during the work)

The first harness (`tools/cache/perf.ps1`: rail flight at 110-130 m/s, 15 s settle, 30 s sampled) turned out to measure
how far the scenery had streamed in, not what it costs: the player keeps flying into unloaded tiles, so a build that
streams faster scores worse. The v2.3 baseline in `build/perf_baseline.json` was taken that way.

The final numbers use an A/B instead (`tools/cache/ab.ps1 -rail 0.01 -settle 100`): the v2.3 build (git worktree
`build/base`) and the current tree alternate scene by scene, each hovering at the scene's start point, 100 s settle so
every tile and site within range has loaded, then 30 s sampled. 1920x1080, upscaler off, no frame generation. Date is the
1940-08-15 default except arnhem_1k (1944-09-18). Debug: `tools/cache/dump.ps1` + `--perf-dump` lists the geometry by owner.

## Final A/B (v2.3 -> current, fully loaded)

| Scene | FPS v2.3 | FPS now | Change | GPU ms | Draw calls | 1% low FPS |
|---|---|---|---|---|---|---|
| biggin_low | 99.5 | 104.1 | +4.6% | 9.62 -> 8.99 | 251 -> 251 | 71.6 -> 71.2 |
| london_3k | 30.5 | 41.6 | +36.4% | 23.26 -> 22.13 | 17894 -> 7091 | 7.2 -> 8.2 |
| caen_low | 56.1 | 59.3 | +5.7% | 17.11 -> 16.43 | 4989 -> 4491 | 46.1 -> 54.0 |
| ruhr_6k | 44.6 | 64.0 | +43.5% | 14.20 -> 15.06 | 9781 -> 3311 | 12.3 -> 60.0 |
| channel_dusk | 71.6 | 73.2 | +2.2% | 13.73 -> 13.37 | 1030 -> 1526 | 67.7 -> 69.3 |
| arnhem_1k (1944-09-18) | 51.7 | 53.3 | +3.1% | 17.94 -> 18.48 | 5966 -> 4816 | 18.2 -> 50.1 |

Where the headroom came from, so the new content could fit:
- **Rail and canal furniture merged per tile** (`GroundKit.flatten`): signal boxes, crossings, bridges, locks and the
  like were one MeshInstance per box, ~400 per London tile (17,500 draw calls over London). Now one surface per material
  per tile, small pieces fading at 6 km.
- **Zone mask texture** (`TerrainChunkManager._build_zone_mask`): the terrain shader's 32 zone slots (airfields, camps,
  damage, floods, beaches) were tested on every pixel. A 256 x 256 km mask at 1 km cells now tells each pixel which slots
  can reach it; most ground skips the loop entirely.
- **Era rebuild drops stale tile jobs** (`_tile_gen`), so the world streams in faster after the sortie date is set.

## Tasks

| Task | Status | Notes |
|---|---|---|
| 0 Perf harness + baseline | done | `perf.ps1`, then `ab.ps1` / `perf2.ps1` / `dump.ps1`; `--rail=`, `--date=`, `--perf-dump` |
| E1 Hemer / camp flatness | done | Stalag VI-A moved to the Bluecher barracks site; camps flattened with feathered zones |
| E2 Shot harness above ground | done | `--rail=0.01` pins the aircraft for shots |
| E3 `--overhead` centred | done | anchored, north-up |
| E4 Ricks check | done | toned down, verified in close shots |
| E5 POW low shots | partly | overhead shots taken; no new low-level POW shots this pass |
| A1 Era plumbing | done | `EraClock`, dated zones, rebuild on date change |
| A2 Blitz / bombing damage | done | `data/war_damage.json` (55 dated areas), ruins in the house scatter, terrain rubble/scorch/craters |
| A3 1944 build-up | done | `data/buildup_1944.json`: marshalling areas, anchorages, Phoenix parks, hards |
| A4 Normandy after D-Day | done | Mulberry A/B, beaches, LZs/DZs, floods, battlefields |
| A5 Walcheren floods | done | plus Betuwe, Wieringermeer |
| A6 Arnhem / Nijmegen | done | LZs, bridge ramp, Arnhem bridge broken from 1944-10-07 |
| A7 Westwall / Rhine | done | dragon's teeth, Ludendorff bridge broken from 1945-03-17 |
| A8 1940 anti-invasion | done | obstructed fields near the coast, 1940-06 .. 1942-12 (England) |
| B1 Region bake | done | `tools/bake_regions.py` -> `data/heightmap/region_types.png` |
| B2 Bocage | done | |
| B3 Open fields | done | |
| B4 Polders | done | |
| B5 Weald / Downs / heath | done | Weald channel; downs use the open-field channel |
| B6 Seasons | done | season stage + grade from the sortie month; stooks Aug-Sep, ricks Jul-Mar |
| C1 Barges | done | `BargeTraffic`, max 12, continent only |
| C2 Trains | done | steam trail within 7 km, max 6 |
| C3 Industry smoke / smog | done | covered by D2 haze plus the existing chimney smoke |
| C4 Searchlight / flak belts | done | Kammhuber belt sites, 1941-42 |
| C5 Harbours | survey only | gaps listed in `docs/map_research/C_D_life_horizon.md` |
| D1 Horizon | checked | over the Channel from 6 km: fog and far terrain meet without a visible edge; no change made |
| D2 Haze | done | `TimeOfDay.HAZE_AREAS` |
| D3 Landmarks | done | dated bridges; river-aligned |
| D4 Coast from altitude | done | shallow-sea foam blotches removed (water.gdshader) |

Research notes: `docs/map_research/`.
