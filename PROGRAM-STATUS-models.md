# PROGRAM-STATUS: aircraft-models (1:1 high-poly aircraft)

Brief: `PROMPT-aircraft-models.md`. Owner, 2026-10-10: **"get rid of the toon aesthetic and aim for more real
life assets"** - this supersedes the earlier "keep the toon look + outline" decision. Straight through all
models, no interim sign-off; then build/commit/push/release; then the world assets get the same realism pass.

Baseline gate: `TESTS OK (734 passed, 0 failed)`.

## What the pipeline is now

| Piece | What it does |
|---|---|
| `tools/models/kit.py` | Blender geometry API: `tube` / `surface` (6th station element = leading-edge offset, so an ellipse curves BOTH edges) / `fin` / `canopy` / `propeller` (blades carry pitch twist) / `nacelle` / `turret` / `radiator` / `exhaust_bank` / `tailwheel` / `gear_leg` / `markings` / `pilot`, plus `refine_all(cuts)` for the poly budget and `bounds_report(id, (length, span))` as the numeric accuracy gate |
| `tools/models/build_all.py` | `blender --background --python tools/models/build_all.py -- <id> [<id> ...] [--ortho]` -> `assets/models/<id>.glb` + tris + ACCURACY verdict |
| `tools/models/data/<id>.py` | one file per aircraft: station tables from published dimensions, `EXPECT = (length, span)` |
| `tools/make_aircraft_camo.py` | procedural camouflage/finish textures -> `assets/models/camo/*.png` (raf_day, raf_night, lw_splinter, lw_desert, usaaf_od, bare_metal) |
| `shaders/aircraft_pbr.gdshader` | realistic painted metal: triplanar camo, painted underside, panel lines, grime, chipping, micro-relief. **No toon ramp, no outline pass** |
| `scripts/models/gltf_models.gd` | instantiates the `.glb`, paints it onto the contract node names, falls back to the procedural builds when an asset is missing |
| `scripts/models/model_gallery.gd` | `--ids=<id> --view=side\|top\|front\|three\|skin --dist=N --shot=<png>`; auto-fits a single model and skips the label so detail is inspectable |

Accuracy gate in use: `ACCURACY <id> length N/Nm (x%) span N/Nm (x%) ... PASS` - anything outside 2% is a FAIL
and the data has to be fixed. Height is printed but not gated (the published figure is stance-dependent).

## Phase board

| # | Phase | State | Evidence |
|---|---|---|---|
| 0 | Pipeline (kit + rewire + materials + gallery + gate) | **DONE** | Spitfire round-trips Blender -> `.glb` -> Godot; `TESTS OK (734/0)`; `[models] spitfire from spitfire.glb (raf_day)` proves the glTF path is live, not a silent fallback |
| 1 | Spitfire Mk I | IN PROGRESS | `ACCURACY spitfire length 9.12/9.12m (+0.0%) span 11.23/11.23m (-0.0%) PASS`, 22,964 tris, camo + roundels + fin flash + 3-blade prop with pitch; **left: fin/tailplane still a touch heavy, canopy could sit prouder, radiator ducts boxy** |
| 2-24 | the other 23 aircraft | DELEGATED | 6 background builders (RAF fighters, US fighters, US bombers, LW fighters, LW bombers, multi-engine), each with the numeric accuracy gate + tri budget in its brief |
| 25 | C-47 | **DONE** | `ACCURACY c47 length 19.66/19.66m span 28.96/28.96m height 5.16/5.16m PASS`, 47,504 tris, deterministic (582 KB .glb) - shipped in v6.0 |
| 26 | Verify + export/commit/push/release | **DONE** | `TESTS OK (734 passed, 0 failed)` with all 25 models loading from `.glb`; committed `1e3affc`, pushed; exported `build/WW2ChannelAirWar.exe` (444 MB) and **published release v6.0** (asset `WW2ChannelAirWar_v6.0_win64.zip`, 394 MB, read back from the GitHub API) |

## Fixes from the owner's review (2026-10-10)
- **Wing decals**: `kit.disc()` built "horizontal" markings in the X-Z plane, so wing roundels stood edge-on
  *inside* the wing. Replaced with `kit.skin_disc()`, which places the ring in the correct plane AND drops
  every vertex onto the real skin (sampled from the wing/fuselage mesh), so markings follow dihedral, camber
  and fuselage curvature instead of hovering on a flat plane. All four nation branches now sample the skin.
- **Spitfire wing shape**: it was built as a single ellipse, which curves the leading edge aft from the root
  and makes the wing read as a leaf. The real planform is **two semi-ellipses on a common major axis at the
  spar** (31.5% of the root chord): the leading-edge semi-ellipse has the small minor axis (nearly straight
  LE), the trailing edge the large one (hard forward curve). `A_FRONT = 0.315 * root_chord`,
  `A_REAR = 0.685 * root_chord`, elliptical chord distribution, 13% -> 6% thickness, -2.5 deg tip washout.
  The Spitfire is the only two-semi-ellipse wing in the roster - the Hurricane/Typhoon/Tempest/Mustang/
  Thunderbolt are straight-LE types and are unaffected.
- `kit.surface()` now honours the `twist` station element (it was parsed and then ignored).

## Decisions log
- Axis convention: metres, origin at the **CG station**, nose +Y, up +Z, right +X (glTF maps that to Godot -Z).
  The Spitfire pins it down: CG 0.79 m behind the wing root LE, spinner 2.20 m ahead of the wing root LE.
- Poly budget: fighters 20-30k tris, bombers 40-60k (`refine_all(cuts=1)` on top of dense station tables).
- **Realism over toon** (owner, 2026-10-10): the aircraft use StandardMaterial3D / the PBR shader; the outline
  pass is gone from the aircraft. To be extended to the world assets in the next program.
- `gltf_models.gd` hides `PropDisc` until `AircraftModels.prop_blur` swaps it in, so a freshly built model
  shows blades rather than a blur plate.
- Geometry is original: never import or convert meshes from any other game. No swastika is modelled anywhere - the Luftwaffe fin marking is a plain band.
