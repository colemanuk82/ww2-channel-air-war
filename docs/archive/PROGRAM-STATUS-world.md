# PROGRAM-STATUS: world realism

Brief: `PROMPT-world-realism.md`. Owner: keep going without input; no release until the aircraft program and
this one are both complete; the aircraft get committed/released first.

Gate after every phase: `TESTS OK (N passed, 0 failed)` + a rendered world shot (main scene / free flight).

| # | Phase | State | Evidence |
|---|---|---|---|
| W0 | Recon: how the world is shaded | DONE | ~100 kit scripts funnel through `ToonUtil.make_toon`; used by scripts/aircraft.gd, scripts/ground/ground_ship.gd, scripts/toon_util.gd; terrain via `shaders/terrain.gdshader` (scripts/terrain_chunk_manager.gd, scripts/ground/scatter.gd) |
| W1 | World material system | **DONE** | 20 textures + manifest in `assets/textures/world/` (`tools/make_world_textures.py`); `shaders/world_pbr.gdshader` (triplanar, PBR, weathering); `ToonUtil.make_toon` re-pointed at it with outline now opt-in, so all ~100 kit scripts upgraded with no edits. One real bug in the delivered shader: `bool flat = ...` - `flat` is a reserved interpolation qualifier in the shading language; renamed to `untextured`. Gate green (734/0) |
| W2 | Terrain shader realism | **DONE** | new `shaders/terrain.gdshader` (22 KB) live and verified rendering: an aerial shot reads as varied fields/hedgerows/coast with no shader errors, and the judge's verdict moved from "flat cartoon colour bands" to "more like real countryside... varied field colours, hedgerows, trees, roads" |
| W3 | Vegetation + water | TODO | |
| W4 | Lighting + atmosphere | DONE (first pass) | `time_of_day.gd`: ACES tonemap (was Filmic/Linear), sky reflections for specular (was disabled), stronger SSAO (0.35 -> 0.62 - it used to fight the flat-shaded buildings), subtler grade (sat 1.12 -> 1.05), sky haze 0.12, glow bloom 0.06. Gate green after the change |
| W5 | Effects | TODO | |
| W6 | Verify + build/commit/push/release (with the aircraft) | TODO | |

## Baseline before the realism pass (from an aerial shot at 435 m, `--air --shot=`)
Judge's verdict: exposure "not blown out but flat and washed out"; ground = "low-resolution patchwork colour
map, not real countryside - fields are flat polygons, little crop detail, hedgerow structure or plough lines";
buildings = "flat-shaded low-poly blocks with simple diffuse textures, no specular, bump or material
differentiation"; haze present but "crude linear fog rather than atmospheric scattering, and somewhat
overdone". That is the gap W1-W3 close.
