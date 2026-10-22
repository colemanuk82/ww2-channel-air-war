# Dam Busters campaign: plan

Goal: a training course and then a campaign mission (Operation Chastise, May 1943) in which the player
(1) learns to fly at 60 ft and skip a bouncing bomb, (2) releases a bomb, watches it skip across the
reservoir, (3) watches it sink and detonate against the dam wall, and (4) sees the wall breach and the
water flood the valley below.

## What already exists (reuse, do not rebuild)

- `data/dams_1940.json`: Möhne, Eder and Sorpe sites with real coordinates, wall length and height, and
  reservoir area.
- `scripts/ground/dam_kit.gd`: the reservoir water, powerhouse, valley shoulders and anti-torpedo net boom.
- `scripts/ground/ground_structure.gd`: `GroundStructure.create("dam", ...)` with 1400 HP, a `_build_dam`
  wall, and `_build_wreck_dam` breached state that already sprays water off the downstream face.
- `scripts/weapons/weapon_world.gd`: `drop_bomb`, `_step_bombs`, `explode_at`, `_over_water`, and
  `predict_bomb_impact` (the bomb-sight aiming maths).
- `scripts/modes/training_mode.gd`: lesson list and objective/voice system (`LESSONS`).
- `scripts/modes/historical_missions.gd` and `data/missions.json`: historical sortie framework.
- `scripts/campaign.gd`: campaign days, ranks and strike types.
- `scripts/aa_gun.gd`, `scripts/ground/searchlight.gd`: flak and searchlights to defend the dams.
- `scripts/camera_rig.gd`: chase and cockpit views (`set_cockpit`, `view_changed`).
- `--dam-test` in `main.gd`: headless build check for every dam.

## Ground rules

- Loading time: the dams stay out of the tile streaming and are built only when the mission starts. Keep
  the preload budget (~40 s) unchanged.
- Palette: keep the existing toon palette (greys, chalk, khaki green, blue-grey water). No new colour families.
- Stage only your own files in git. Another thread may have edits in `main.gd`, `camera_rig.gd` and
  `cockpit_interior.gd`.
- Every new `class_name` file needs `godot --headless --path F:\ww2_dlss --import` once.
- Worker-thread rule: no `get_node` from worker code.

## Phase 1: Bouncing bomb physics (the core)

File: new `scripts/weapons/bouncing_bomb.gd` (class `BouncingBomb`), used by `weapon_world.gd`.

- Model the Upkeep bomb as a cylinder with backspin. Spin rate in rpm is a parameter; default ~500 rpm.
- Release: at ~60 ft (18 m) and ~340 km/h (about 95 m/s), at about 400 m range from the wall.
- Each time the bomb reaches the water surface (`_over_water`, water height from `GroundKit`):
  - Reflect vertical velocity with restitution ~0.55.
  - Keep ~85% of the horizontal velocity.
  - Lose spin a little on each skip.
  - Add a small backward lift so it skips rather than digs in.
- Stop skipping when the vertical speed is low: it sinks with drag.
- Fuse: explode after a set time (e.g. 30 s), or when it touches the dam wall (`GroundStructure` hit).
- Expose skip count and skip distance for the HUD and debug test.
- Headless test `--bomb-test`: print skip count, total run and sink point for several release speeds and
  heights. Target: 5 to 8 skips for a good release, 0 for a bomb released too high.

Visuals: a cylinder mesh (reuse `_make_bomb_node`), a small splash at each skip (reuse `fx_puff`), and a
spray trail.

## Phase 2: Camera change on release

File: `scripts/camera_rig.gd` (add a "bomb cam" mode).

- On release, the view follows the bomb from a low side angle (about 2 m above the water, 25 m behind),
  so the skips are visible. After the detonation, it returns to the aircraft over ~2 s.
- The pilot can press the existing view key to skip the bomb cam.
- Use the existing shake-free rig (no speed shake, per the earlier fix).

## Phase 3: Dam destruction and flood

Files: `scripts/ground/ground_structure.gd` (dam), `scripts/ground/dam_kit.gd`.

- Detonation under the wall applies damage with a stronger effect on the wall (hydrostatic: a bomb that
  explodes in the water next to the wall does more to the wall than an air burst).
- Stages by damage fraction:
  1. Cracks and first spray at 40% of HP.
  2. A breach opens at the centre at 0%. The wall mesh changes to the wreck state (`_build_wreck_dam`).
  3. The reservoir level drops over ~20 s, and the lake surface shrinks.
- Flood: a new `FloodWave` node (new file `scripts/ground/flood_wave.gd`) that moves down the valley from
  the breach along the downstream direction (-Z local). Visual: a water sheet with the existing
  `shaders/water.gdshader` tinted to the river colour, leading edge with foam, and stops at the valley
  floor. Its path is limited to the valley (a simple distance cap, no terrain flow solver).
- Spray and smoke from the breach reuse the existing wreck spray and `fx`.

Worker safety: the flood only runs on the main thread (per-frame node).

## Phase 4: Training course

File: `scripts/modes/training_mode.gd`: add lessons after `t_rockets`:

1. "Low flying": hold 60 ft (18 m) over the sea with a radar altimeter readout. Ring checkpoints along
   the coast at that height.
2. "Bomb run practice": drop a practice bomb onto a marked pool. Score is distance from the marker.
3. "Skipping": drop practice bombs on a flat water range. Score is the skip count. Shows the skip
   camera (phase 2).
4. "Spin and release": approach the mock wall at the target speed and release at the marked range.
   The range marker is drawn on the ground with `_make_ring`.
5. "Dam wall attack": one full run on a training wall (a copy of the Möhne wall) at reduced HP, so the
   player sees the breach and flood.

Each lesson has a brief, checkpoints and a pass condition, following the existing lesson format.

## Phase 5: The campaign mission ("Operation Chastise")

Files: `data/missions.json` (new entry), `scripts/modes/historical_missions.gd`, and
`scripts/campaign.gd` (add a `dam` strike type).

- Side: Allies. Aircraft: Lancaster (the existing heavy bomber in `AircraftCatalog`), flown at low level.
- Three waves in order, historic: Möhne (wave 1), Eder (wave 2), Sorpe (decoy/diversion).
- Each sortie: fly from the start airfield at low level over the North Sea and the Dutch coast, dodge
  flak and searchlights (existing `aa_gun` and `searchlight`), set up the run at ~400 m, release the
  bomb, watch the bomb cam, then see the result.
- Mission success: a breach at Möhne or Eder. Score: breach timing, bombs used, losses.
- Failure: the bomber is shot down, or the bomb is wasted.
- Campaign: a "dam" strike type that unlocks after the training course is passed.

## Phase 6: Test and release

1. `--dam-test` (existing) passes for all three dams.
2. `--bomb-test` (new) gives the expected skip counts.
3. Render checks with `tools/cache/shots.ps1`:
   - Training range: low flight and skip.
   - Bomb cam: bomb in mid-skip.
   - Wall breach and flood.
4. Load time: the `--loadprof` wall time must stay within the existing budget.
5. Commit only the files changed in each phase. Release as the next point release (v6.4).

## Open questions for you

1. Campaign length: one mission, or the full Chastise run (three dams, then the aftermath)?
2. Historical accuracy versus gameplay: the bomb skips at a fixed physics model. Do you want the real
   fuse set time (about 30 s) or a shorter one?
3. Flood extent: the flood runs down the valley for a fixed distance (proposed ~3 km). Is that enough?
4. The Eder and Sorpe dams: the Eder site is placed at 51.1833, 8.9667 to stay in the heightmap (see
   `dams_1940.json`), so the flood there may not reach a town. Acceptable?
