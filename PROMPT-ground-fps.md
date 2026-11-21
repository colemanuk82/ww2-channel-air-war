# PROGRAM: Land, then fight — an on-foot FPS layer

> **How to use this file:** this is a *program brief* in the style of `PROMPT-cities-towns-1940s.md`
> (see its header for the delegation pattern). It is written to be handed to an implementation agent
> with no memory of the conversation that produced it. [Bracketed] text is a decision I could not make
> for you — answer it before phase 0, or the phase writes down the assumption it took.

**Goal (the owner's words):** when you land, the game turns into a first-person shooter. On the ground
the graphics and ground textures should be as good as *Call of Duty*. Landing on hostile territory
gets you hunted by soldiers. You carry a sniper rifle, assault weapons and pistols, and can pick up
ammo and weapons from enemies.

**Read this first — three facts that decide the whole design (verified on HEAD `9025207`):**

1. **There is no character at all today.** No `CharacterBody3D`, no mouse capture, no first-person
   camera. The player is an `Aircraft` with an arcade flight model (`scripts/aircraft.gd`). Nothing to
   extend: this is a new subsystem.
2. **The world has almost no collision.** `git grep StaticBody3D|CollisionShape3D -- '*.gd'` returns
   **one hit, inside `addons/ocean3d_lite/`** — i.e. zero places in the game. Terrain heights come
   from `TerrainChunkManager.get_height_at()`, and houses, hedges, walls and airfield furniture are
   **decoration with no colliders**, built as MultiMeshes on the scatter worker thread. You cannot
   "stand on" or "shoot from behind" any of it until this phase creates collision. Treat this as the
   single biggest and least glamorous part of the program — it is ~40% of the work and every other
   phase depends on it.
3. **"As good as Call of Duty" is not reachable with this art pipeline, and the brief must not pretend
   otherwise.** Everything is procedural, authored in Python: 20 tileable **1024×1024** surface
   textures (`tools/make_world_textures.py`) and one **256×256** close-range detail texture
   (`tools/make_detail_textures.py`). Lit with ACES tonemapping, SSAO 0.62, no baked lighting, no
   normal maps, and drawn from a camera 200-4000 m up. Get to tree height and it will look coarse.
   *Call of Duty* ground quality means ~2-4k albedo + normal + roughness + AO maps, photogrammetry,
   baked GI and a dedicated art team. What this program *can* do is close the specific gaps that make
   a procedurally-generated ground read as fake from 1.7 m: texel density, a real normal map, proper
   triplanar scaling at player scale, wetness and wear, and grass/biome variety. Success is "the
   ground holds up at 1.7 m and looks deliberately painterly", not parity with a AAA studio.
   **Do not promise the owner CoD parity in the release notes.**

---

## 0. Current context (verified by reading HEAD `9025207`)

| Area | Where | What's actually there |
|---|---|---|
| Player | `scripts/aircraft.gd` (`Aircraft`) | Arcade flight model, `on_ground: bool`, `signal landed(aircraft)` at L17, touchdown logic ~L612. No walking. |
| Controls | `scripts/game_state.gd` `_setup_input` | Flight actions only; gamepad + keyboard. No mouse capture, no `MOUSE_MODE_CAPTURED` anywhere. |
| Ground height | `scripts/terrain_chunk_manager.gd` | `get_height_at(pos)` / `is_water_at(pos)`; group `"terrain"`. Streams chunks from `data/heightmap/region_height.png`. **No collision shapes.** |
| Scenery | `scripts/ground/scatter.gd` | Houses, hedges, trees per tile as MultiMeshes, built on a worker thread (`tile_landcover_data` pure → `build_tile_nodes` main thread). No colliders, no per-object identity. |
| Buildings & sites | `scripts/ground/ground_structure.gd`, `scripts/ground/*_kit.gd`, `scripts/world_populator.gd` | Streamed sites; anything hittable joins group `"damageable"` with `hit_radius` + `take_damage(amount, source)` (contract in `scripts/mode_base.gd`). |
| Hit detection | `scripts/weapons/weapon_world.gd` | 300 m spatial grid + `_movers`; **no physics raycasts** (the only `intersect_ray` in the repo is in `scripts/models/plane_builder.gd`, a mesh probe). |
| Weapons | `scripts/weapons/weapon_system.gd` | **Aircraft mounts only**: guns/cannon/bombs/rockets, `AIM_ASSIST_DEG`, jam, ammo warnings. Nothing on foot, no inventory. |
| Men | `scripts/ground/crew_figure.gd` | `CrewFigure.mesh/make(team, pose, dress)` — merged low-poly figures, 4 dresses per side, poses STAND/HIPS/POINT/BEND/KNEEL/REACH/WALK_A/B/CARRY/WAVE. `scripts/ground/airfield_people.gd` draws ~300 more per airfield as vertex-animated MultiMeshes. These are the enemy bodies. |
| Sides / territory | `scripts/ground/ground_kit.gd` | `side_at(pos)` / `side_at_latlon(lat, lon)` — "Allies"/"Axis"/"Neutral". `scripts/bail_out.gd` already has fate `"captured"` for enemy territory, and `fate_text()`. |
| Ground textures | `tools/make_world_textures.py` | 20 × 1024² tileable PNGs + a manifest with measured means / roughness / metallic / scale. `shaders/world_pbr.gdshader` triplanar (world meshes have no usable UVs). |
| Terrain shader | `shaders/terrain.gdshader` | Painted palette + `map_tex` imagery drape (~72%), field lattice `field_cell = 190` (must stay in step with `Scatter.FIELD_CELL`), `terrain_detail.png` micro-detail. |
| Tests | `tools/tests.gd` → `scenes/tests.tscn` | Headless, exits non-zero on fail, must print `TESTS OK`. 4625 checks at HEAD. |
| Release | `tools/cache/ship.ps1 -msg "..."` | licence gate → bump → build+test+export → installer → commit+push → tag → GitHub release. |

**Conventions (from `HANDOFF.md` §7 + `CLAUDE.md`, all mandatory):**
- TABS, statically-typed GDScript. New `class_name` ⇒ `--headless --path . --import` (no `--quit`) first.
- **Never** a visible window or focus steal: `--headless` for tests, `tools/hidden/hidden_run.ps1` for
  screenshots. Do not use `--minimized`.
- Never re-implement the projection: `WorldCoords.latlon_to_world()` only.
- All art procedural or CC0/CC-BY in `ATTRIBUTION.md`. **(Never copy CoD or any other game's assets,
  models, sounds or textures — the repo has been through a copyright cleanup; a takedown risk is an
  instant reject.)**
- Deterministic per site from `hash(id)`. Scatter stays worker-thread split (pure pass → node pass).
- Never commit commercial audio; `tools/audio_allowlist.json` gates it.

---

## Phase 0 — Decisions to take before any code

Answer these in the program file as it is checked in; each has a default marked **(default)**.

| # | Question | Why it matters |
|---|---|---|
| 0.1 | Is on-foot a **new mode**, a **phase of an existing mode**, or entered by any landing? | Scope. A separate `ModeBase` mode keeps every existing mode untouched; "any landing" needs hooks in all of them. **(default: new mode `mode=fps`, plus a one-line hand-off from any landing — see 1.6)** |
| 0.2 | Does the aircraft stay, to return to (fly out again), or is the sortie on foot from then on? | Whether the player can get back in the air. **(default: the aircraft parks and can be re-entered; the FPS layer is a state, not a mode swap, so a career sortie can land and take off again)** |
| 0.3 | Which sides may be FPS? Allies and Axis, or one? | Both is right; art is side-aware already. **(default: both)** |
| 0.4 | Is this in the flight game's existing menu flow, or a separate "ground war" entry? | UI surface. **(default: same flow — it happens on landing)** |
| 0.5 | Rating/age: is gore acceptable? | 1940s ground war. **(default: no gore — figures fall, no dismemberment; keep the game's current rating)** |

**Definition of the "graphics" goal for phase 4** (write it into the program file, and into the release
notes): *"the ground holds up at 1.7 m eye height: texel density, normals, wetness and wear read
correctly; it looks deliberately painterly. It is not Call of Duty parity."*

---

## Phase 1 — A body that can stand on the ground (the foundation)

**Why:** nothing in the world is solid (fact 2). Walking, cover, hunting and bullets all need it.

1.1 `scripts/ground/ground_body.gd` — a `CharacterBody3D`: capsule, `move_and_slide()`, walk/sprint/
crouch/prone, gravity from terrain height, step-up, slope limit, crouch-through-door height check.
1.2 **Camera:** first-person eye (~1.7 m), mouse capture toggled with the existing pause handling
(restore `MOUSE_MODE_VISIBLE` on pause/quit — a stuck-captured mouse is a bug report), FOV ~75,
head-bob that can be turned off, ADS (aim-down-sights) zoom.
1.3 **Collision for the streamed world.** This is the hard one; pick the cheap and honest route:
   - Terrain: a `HeightMapShape3D` (or per-chunk height shape) fed from `TerrainChunkManager`'s
     existing height data, created `StaticBody3D` per streamed chunk and freed with it. Do **not**
     bake a second copy of the heightmap.
   - Houses / walls / hedges / airfield kit: a **capsule/box per scattered unit**, not a trimesh.
     ~1000 units per 1.8 km tile is far too many for one body each — use one `StaticBody3D` per
     tile holding many `CollisionShape3D` children, or (better) a coarse collision mesh per tile
     built on the scatter worker thread and uploaded on the main thread. Budget it: measure and
     report the frame cost and the physics-server memory at a 1.8 km tile.
   - Keep fog distance honest: a body further than the fog can be culled from collision too.
1.4 A debug arg `--fps-test=lat,lon` that drops the body at a real place and prints ground height,
   walkable area, collider count and physics tick cost.
1.5 **Verification:** headless run with no script errors; the hidden-desktop render shows the body
   standing on real terrain at a known spot; a scripted walk of 100 m across a hedge line and into a
   house wall neither falls through nor passes through. Report the numbers.
1.6 **Landing hook:** `Aircraft.landed` already exists. On landing, if the ground is not friendly,
   hand over (below); if friendly, allow a walk-around but not the hunt.

---

## Phase 2 — Small arms: pistol, assault, sniper

**Why:** the owner's explicit list. Today `WeaponSystem` is aircraft-only.

2.1 `scripts/weapons/small_arms.gd` — a data-driven weapon definition (`data/small_arms.json`):
   pistol, assault rifle, sniper rifle; per weapon: damage, RPM, magazine, reserve, spread, recoil
   curve, ADS zoom, bullet drop, muzzle velocity, reload time, effective range, sound id.
   Suggested set (1940s, real names): **Webley / Walther P38**, **Sten / MP 40**, **Lee-Enfield /
   Kar98k** (scope variant for the sniper). Keep it to 3 families as asked, not 20.
2.2 Ballistics: real projectile with drop and travel time (reuse the pattern in
   `scripts/weapons/weapon_world.gd`, which already pools projectiles and has a spatial grid).
2.3 Hit resolution on foot: **physics raycast against the phase-1 colliders** for geometry, and the
   existing `"damageable"` / `take_damage(amount, source)` contract for people and structures. A head
   hit vs body hit must differ; report the multipliers you choose. Sniper must **one-shot** a soldier.
2.4 HUD: on-foot crosshair, ammo/magazine, weapon name, hit marker, low-ammo warning. Reuse
   `scripts/weapons/weapon_hud.gd` style, do not build a second HUD framework.
2.5 Audio: reuse `AudioSFX` procedural synths (no sampled gunshots — commercial audio rule).
2.6 **Verification:** a headless ballistics test (drop at 100/300/600 m within tolerance), a
   scripted hit test (N shots, N hits on a `damageable` target), and a render of each weapon in ADS.

---

## Phase 3 — The hunt: soldiers come for you

**Why:** "when you land on hostile territory soldiers should hunt you down."

3.1 **The trigger:** on landing, `GroundKit.side_at(player_pos) != GameState.player_side` (and not
   "Neutral") ⇒ hostile. `scripts/bail_out.gd` already models the same idea for a downed pilot
   (`fate == "captured"`), so reuse `GroundKit.side_at` and keep the two consistent.
3.2 `scripts/ground/hunters.gd` — a soldier squad manager:
   - Bodies: `CrewFigure` meshes (fact: they exist, 4 dresses, walk/run/kneel/aim poses) — **not** new
     character art. If a pose is missing, add it to `CrewFigure`, do not fork it.
   - Behaviour: an alert state machine — PATROL → SUSPECT (heard the shot / saw you) → SEARCH (last
     known position, spread out, take cover) → ENGAGE (fire while bound), plus a `reinforce` timer so
     a manhunt escalates, and a `give up` after N seconds out of contact. **This is what makes the
     feature read as CoD rather than as a firing-range dummy.**
   - Cover-seeking: with phase-1 colliders, use navmesh-free cheap cover (probe a few directions for
     a blocking collider within 15 m, else crouch in place). A real navmesh is a phase 5 option.
   - Numbers: a first wave of 4-6, escalation cap configurable; tie into the existing
     `AIFactory.ai_room()` cap so the ground fight cannot starve the sky.
3.3 Combat honesty: soldiers must **hit you sometimes and miss sometimes** at range; they use the
   same small-arms ballistics as you (shared definitions, different skill constants, the way
   `PLAYER_SPREAD_K` / `AIM_ASSIST_DEG` already split player vs AI).
3.4 Player health/damage on foot: a health pool, hit direction indicator, regen or bandage, death
   screen that returns you to the air (or ends the career sortie if it is a career mission).
3.5 **Verification:** headless soak — land hostile, let the squad run 120 s; assert they reach
   SUSPECT → SEARCH → ENGAGE, that they path around a wall, that they damage the player, and that
   they give up. Report the state timeline. Render one: soldiers advancing on a player behind a wall.

---

## Phase 4 — Ground that holds up at 1.7 m (the "graphics" ask)

**Why:** the owner asked for CoD-quality ground. See fact 3 for what is achievable; this phase is how
far it can actually go. Order the work so a partial pass still helps.

4.1 **Texel density.** Measure it first: at 1.7 m, how many texels per metre does each surface get?
   The 1024² tiles are reused across buildings, so a house wall may be getting a handful of cm/texel.
   Fix by per-surface scale in the manifest, more tile variants, and **a second, larger-scale detail
   layer** (the 256² detail texture is the current attempt). Report before/after numbers.
4.2 **Normal maps.** The single highest-value item: `world_pbr` has none. Generate derivatives from
   the procedural height fields already inside `tools/make_world_textures.py` (it has `fbm2`,
   `vnoise2` and a manifest) — no third-party normal maps. Wire into `shaders/world_pbr.gdshader`;
   check the triplanar path.
4.3 **Parallax/POM** on ground materials (cobbles, bricks, planking) at close range, with a fade to
   flat beyond ~12 m so the flight game is unaffected.
4.4 **Terrain at eye height:** more biome variety (the shader palette is per-field-type — add mud,
   track ruts, stubble, crop rows at player scale), and a **grout/wear pass** where the player walks.
   Keep `field_cell` in step with `Scatter.FIELD_CELL` (that pair has drifted before).
4.5 **Lighting on the ground:** contact shadows/AO under objects, better SSAO at player scale, and
   the existing `TimeOfDay` grading must not wash out textures at 1.7 m (it was tuned for altitude).
4.6 **The honest gate:** a set of renders — 4 biomes × dawn/noon/dusk × 1.7 m eye height — reviewed
   against a written checklist (texel density, normal response, no visible tiling within 20 m, no
   flat-shaded walls, shadows, fog at the right distance). **Put these renders in `screenshots/`** and
   link them from the program file, so the next agent can see whether it got better or worse.
4.7 Flight regression gate: `--perf=120:30` at three places must not drop more than [10%] — the flight
   game is the product. Report before/after.

---

## Phase 5 — Pickups, inventory, and the loop closing

5.1 Weapons and ammo drop from a fallen soldier and are **picked up with a key when near** (prompt,
   not auto-grab). Per-weapon reserve ammo; a magazine carried over, not magically refilled.
5.2 Inventory: two weapon slots + pistol, switch with the existing keys, drop to swap. The snipers
   and assault rifles must feel different in handling (recoil, ADS time, sway), not just numbers.
5.3 Dead bodies: leave a pickable corpse for [N] seconds, then fade — asset lifetimes must be pooled.
5.4 **The loop closes in both directions:** on foot you can be strafed by enemy aircraft (they already
   exist), and your aircraft can be hit on the ground; if it is destroyed you are stranded (call for
   extraction, or fight on). This is what stops the FPS layer feeling bolted on.
5.5 **Verification:** a headless test that killing a soldier spawns a pickup, picking it up adds the
   weapon and its ammo, and the inventory survives a save/load if [career sortie persistence is
   wanted — see 0.2].

---

## Phase 6 — Testing, performance, release

6.1 `tools/tests.gd` gains a block per phase (pure logic only, no world): ballistics drop table, hit
   resolution maths, weapon definitions load and validate, hunt state machine transitions, inventory.
6.2 A headless soak `--fps-soak=SECS` running the whole loop (land hostile, fight, die, return) with
   no script errors and a state timeline printed; a hidden-desktop recording of 60 s.
6.3 Performance: the flight game must be untouched when nobody lands. Ground collision and hunt
   AI must not be built until the FPS layer is entered, and must be freed on take-off.
6.4 Docs: `docs/STATUS.md`, a `HANDOFF.md` session entry, and **README honesty** — say what the ground
   looks like, not "CoD quality".
6.5 Release only through `tools/cache/ship.ps1 -msg "..."` once `TESTS OK` and the exported smoke test
   pass. No version bump, no tag, no release until every phase above passes its own verification.

---

## Order of work and why

1 → 2 → 3 → (4 in parallel with 1, it is art-only) → 5 → 6.

Phase 1 first because nothing works without collision; phase 2 because the hunt is meaningless if
your bullets do not land; phase 3 is the actual ask; phase 4 is the graphics ask and the only phase
that can slip without breaking the feature; phase 5 closes it; phase 6 ships it.

**Do not** start with the graphics — it is the most visible and therefore the most tempting, and it
is the one part that cannot fail the feature if it is imperfect.

## Risks the owner should know before this starts

- **Cost.** This is a second game inside the game: ~6 phases, a new physics layer, a new AI, an art
  pass. On the past record of this repo (the 1940s cities program was 6 phases and a large engine
  run), expect it to be the largest single piece of work since the world realism pass.
- **The ground will be the weak point**, no matter what: 1024² procedural tiles viewed from 1.7 m.
  Phase 4 narrows the gap; it does not close it.
- **Scope creep guard:** 3 weapon families, one enemy type, one hunt behaviour, no vehicles, no
  destructible terrain, no multiplayer, no squad commands. Anything else is a new program.
- **Rating/content:** no gore by default (0.5).
