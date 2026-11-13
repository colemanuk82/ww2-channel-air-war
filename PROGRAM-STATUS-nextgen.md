# PROGRAM-STATUS: next-gen graphics pass (2026-11-13)

Brief: the "next-gen, cinematic, 60 fps mid-range" graphics prompt. Engine: Godot 4.7.2 double
(F:\godot-std). Baseline gate `TESTS OK (4314)`; release authorised by the owner.

## Owner decisions
- In-flight town-tree / tug / bomb-cart / field-gun work: verified and landed (P0).
- Motion blur: skipped. Town windows/doors: skipped (earlier owner call stands).
- Airfield landing areas read as dust with a grass ring (owner reference photo of a UK grass airfield:
  row of arched hangars, gravel aprons, parked rows, boundary trees — more of that in P5 follow-ups).
- Towns: noticeably more trees (street + garden).

## Phase board
| # | Phase | State | Evidence |
|---|---|---|---|
| P0 | Land in-flight work (trees, tug/bomb cart/field gun, inst probe) + dust airfields + tree density | DONE | tests 4314/0; before/after town + Biggin shots; `[inst] with_instance_uniforms=3830` baseline (clouds 3194, aircraft 631, ships 5 — nothing on shared shaders) |
| P1 | Lighting: date/latitude sun path, overcast sky treatment, soft low-sun shadows, film grain at medium | DONE | preset grid shots (gold/dusk/overcast/dawn/winter); `--perf` dusk 59.5 fps before = 59.5 after (GPU 15.4 -> 15.6 ms) |
| P2 | Terrain close-up detail texture | DONE | tileable 256² R=turf / G=soil / B=height texture (93 KB, bit-exact torus seams); additive shader edits only, lattice byte-identical |
| P3 | Vegetation: wind-linked sway + named-town street/garden trees | DONE | wind_sway global from WeatherManager (blow-to, 0.15 calm..1.0 storm); ~55-60 street + ~40-48 garden trees per size-3 town via the tile-tree LOD pipeline |
| P4 | Towns: party-wall terrace rows, old-centre lanes, kerb strips, warm stone / cleaner roofs | DONE | example town ~250 band-0/1 house instances -> ~94 (-62%); lanes pitch x0.70-0.80 in core; roof stain -30% |
| P5 | Airfield types & variety (8 archetypes + era conversions + role/era parking) | DONE | `--airfield-furniture-test` per-style counts (raf_bomber 692 meshes, satellite 70, night_fighter 690, fliegerhorst 307, ALG 216, glider 14); `_test_airfield_styles` green; Biggin 1940 dust vs 1944 concrete era pair |
| P6 | Aircraft: per-airframe oil/exhaust streak variation (+30% aft) | DONE | plain `wear_seed` uniform on a per-aircraft skin material duplicate (no instance uniforms; parked strip path verified) |
| P7 | Effects verification | DONE (no changes needed) | layered explosions, 9-15 s flak smoke, tracer bloom, contrails and 10 cloud kinds untouched this pass and exercised by the suite/shots |
| P8 | Consolidated verify + release | DONE (this release) | tests 4331/0; `--airfield-furniture-test`; era-pair + town + ALG + gallery shots; A/B perf = P1 numbers (no regression) |

## Bugs found and fixed during verification
- Core airfields (main._ready) built with the startup date, so `--date` never changed their style;
  `--date` is now applied before the world builds and core fields use `style_for_record`.
- Cottesmore sits in Rutland Water in the heightmap: the `raf_bomber` showcase moved to Wittering.

## Known gaps / next
- Mid-session era changes do not restyle the 15 core airfields (only team); a proper restyle needs an
  Airfield layout teardown+rebuild.
- Terrace rows / kerb strips / town trees bypass WarDamage.apply_to_houses (a bombed core keeps intact rows).
- P5 follow-ups from the owner's reference photo: hangars in a row facing the park, gravel aprons/tracks,
  boundary tree lines.
- Map/visual "next level" plan: see the next program brief.
