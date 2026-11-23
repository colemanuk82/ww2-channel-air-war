# Current state

The one page that says how the project stands today. Keep it short and current: when something here changes,
edit this page in the same commit. History belongs in `HANDOFF.md`; finished plans live in `docs/archive/`.

## What it is

WW2 Channel Air War: a Godot 4 flight game over southern England, the Channel, northern France and Belgium at
real scale (1 unit = 1 m). Allied and Axis sides, dogfight / bombing / ground attack / historical missions /
free flight, a campaign, Pilot's Life career, logbook, mission editor, Dam Busters (work in progress) and a
training film. The game design and data contracts are in `SPEC.md`.

## Engine and build

* Godot **4.7 branch head `c230cbeb6c3f`** (post-4.7.2 maintenance, 2026-11-22), **double precision**, built from
  source in `F:\godot-std` (`platform=windows precision=double optimize=speed use_static_cpp=yes angle=no
  debug_symbols=yes`, script `tools/cache/build_engine47.ps1`) with our 4 local patches (camera origin / variant,
  `F:\godot-std\ww2_local_patches.diff`; see `HANDOFF.md` 2026-10-24) and **debug symbols**. Roll-back: the previous
  4.7.2-stable binaries are in `F:\godot-std\bin\backup_4.7.2\`.
* **Crash symbols:** the matching template exe + `.pdb` are archived in `build\symbols\c230cbeb6c3f\`.
  Resolve WER fault offsets with `tools\cache\symaddr.ps1 -offsets 0x2a27e73` (defaults to the newest archive).
  After installing the game run `tools\cache\install_symbols.ps1` to put the pdb beside the installed exe (the
  installer never ships it); then Godot's crash handler writes a symbolised backtrace to
  `%APPDATA%\Godot\app_userdata\WW2 Channel Air War\logs\godot.log` ("Program crashed"). The project sets
  `application/run/flush_stdout_on_print=true` so the last log lines are on disk when it crashes.
* **Forcing the crash scenario:** free flight, Axis, Bf 109G, night:
  `--mode=free --side=Axis --aircraft=bf109g --time=night --flights-test --flights-kind=raid --flights-size=2
  --flights-log`, plus `--kill-player-after=SECS` to be shot down after SECS (death / spectator transition).
* Release: `tools/cache/ship.ps1 -msg "..."` bumps the version, builds, runs the tests, commits, pushes and makes
  the GitHub release (zip + Inno Setup installer). Only release when the owner asks.

## Checks

| check | how | when |
|---|---|---|
| Unit / data tests | `tools/hidden/test.ps1` (headless, expects `TESTS OK`) | every change |
| Same tests in CI | `.github/workflows/tests.yml` (Windows runner; builds Godot 4.7.2 double once, then cached) | every push / PR |
| Audio licences | `python tools/check_audio_licences.py`, `.github/workflows/audio-licences.yml` | every push; also inside `TESTS OK` |
| Screenshot comparison | `tools/shotcheck/shotcheck.ps1` (hidden desktop) against `tools/shotcheck/baselines/` | after UI / rendering changes; `-Update` after an intended change |
| Taxi and airfield dressing | `tools/dbg` `regress_taxi`, `dress_check` (see `tools/dbg/README.md`) | after airfield changes |
| Load profiling | `--hitch`, `--loadnotes` game args | after loading / streaming changes |

Never open a visible game window on the developer's PC: everything with pictures runs on the hidden desktop
(`tools/hidden/README.md`).

## Player-facing safety features

* **Black box** (`scripts/black_box.gd`): a crash recorder flushed line by line to `user://logs/blackbox_*.txt`.
  A session without `CLEAN EXIT` is kept as `blackbox_CRASH_*.txt` and the start menu says so.
* **Crash report / feedback** (`scripts/report_link.gd`): opt-in. Buttons open a pre-filled GitHub issue in the
  browser (crash log tail with the user's folders and name removed); nothing is sent unless the player submits it.
* **Update check** (`scripts/update_check.gd`): the menu button asks GitHub's releases API on demand; Options >
  Gameplay > *Check for updates at start* makes it automatic, at most once a day. Off by default.

## Rules that must not be broken

* No commercial audio in the repo (see `CLAUDE.md`).
* Liveries are our own painted textures (`tools/liveries/README.md`); never copy from other games.
* The developer edits `README.md` on GitHub: merge before pushing README changes.

## Recently added (November 2026)

* **Loading:** road / river keep-out grids only cover the tile being laid out (Detling start 120+ s -> ~43 s,
  Maidstone and Chatham builds ~3 s -> ~0.1 s). Distant realistic trees use a one-ball tier past 2.5 km.
  Debug: `--loadnotes` (tile-job throughput), `--prim-audit=N` (triangles per mesh), `WW2_TILE_JOBS`.
* **Visuals:** sash windows on near-LOD houses; bombed tile towns lose their trees; tree belts round paved
  airfields (clear of runway lanes).
* **UI:** Training > *First flight* (taxi from the dispersal, take-off, circuit, landing); keyboard rebinding
  and three control profiles in Options > Controls; flight assists (auto-rudder, stall guard).
* **Audio:** bullet whiz and ricochets, cockpit low-pass, combat-aware in-flight music (all procedural).
* **Quiet-spell / lull / air-support voices:** 112 generated clips (56 per side, edge-TTS) in `assets/voice/<allies|axis>/<category>_<n>.mp3`: `lull_quiet`, `lull_end`, `support_land` / `_losing` / `_thanks`, `support_naval` / `_attack` / `_end` / `_lost`, `support_guns`. Source of truth `tools/make_voice_chatter.py` (writes `assets/voice/voice_chatter.csv` and the subtitle table `scripts/radio_chatter.gd`); generate with `python tools/generate_voices_edge.py --csv voice_chatter.csv --missing`. API: `Radio.play_line(category, side="")` (random variant, per-category cooldown), `Radio.pick_line` / `Radio.chatter_clip` (for calls that keep their own text). During a lull (`ActivityTempo.lulling`) Radio plays `lull_quiet` every 60-120 s; `EnemyFlights._lull_over_cue` plays `lull_end`; land / naval / gun calls attach a generic clip.
* **Take-off / departure voices and the tower landing call:** `takeoff_clear` (tower, start of the take-off roll; skipped when the opening Control call was heard < 25 s ago), `takeoff_away` (good luck once 60 m AGL after leaving the ground, one per sortie) and `takeoff_check` (wingman "Two, airborne", only with wingmen): 7 / 8 / 6 lines per side, 42 clips, same pipeline (`tools/make_voice_chatter.py`, speakers "RAF/Luftwaffe airfield tower" + sector / fighter controller + wingman). Logic: `Radio._departure_step`. Bug fixed: the Radio autoload kept `_left_field` from the previous sortie, so the next runway take-off got "cleared to land / welcome back" right after lift-off; `Radio._track_departure` now clears it whenever the player is on the ground (and `reset_channel` clears it), and the landing call (`_tower_land_due`) needs a departure of > 9 km from every friendly field first. Airborne starts are never armed for take-off calls. Tests: `_test_takeoff_calls`.
* **Gameplay:** gun jams (on by default) and a convergence option; *Patrol Missions* mode (pick an Ops Room job:
  intercept, recce, rescue, convoy hunt...); Pilot's Life squadron roster and branching story steps (`when`).
* Terrain chunks now stream nearest first (they were built in grid order from the far corner, so the ground filled in from the horizon and showed as water round the aircraft).
* **Taxi-out flight:** wingmen follow the leader through the hold-short onto the runway (each hold opens when the aircraft ahead has gone through its own), close up faster on the straights, and roll as soon as the player starts his take-off run.
* **Options > Video > Anisotropic filtering** (Off to 16x, default 8x; `GameState.aniso_level`): the terrain map and detail, scenery surface and aircraft camouflage samplers are anisotropic.
* **Airfield grass** is a tiling texture now (`assets/textures/airfield_grass`, generated by `tools/make_grass_texture.py`, numpy + Pillow), mipmapped and anisotropic; the procedural blades remain as the fallback. `terrain_detail.png` is imported with mipmaps too.
* **Men on the ground** (`scripts/ground/airfield_people.gd`, `shaders/airfield_people.gdshader`): airfield ground crew and soldiers, and the soldiers of the army camps, are one MultiMesh per field / camp, animated entirely in the vertex shader (walk, run, march in step, talk, work, wave, sit, salute; everyone dives flat while enemy aircraft are low overhead). Side-specific dress: RAF blue working dress and khaki soldiers in tin hats; Luftwaffe overalls and blue-grey soldiers in Stahlhelm and jackboots. Drawn at the aircraft's 1.45x scale. Debug: `--people-demo[=<dir to save frames>]`.
* **Aircraft stand on their wheels:** the propeller ground clearance is 0.08 m (`Aircraft.PROP_CLEAR`, was 0.45 m, which lifted big-propeller types off their tyres) and the tail only lifts on the take-off run as far as the propeller allows (`_gg_clear`). Debug: `--gear-debug`.
* **Parachuting pilot** rebuilt: tapered body, rounded joints, Mae West / kapok life jacket, harness and pack, flying boots (`--chute=<side> --chute-close`).
* **More men, and kit by them:** numbers follow the quality setting (`AirfieldPeople.density()`: 0.7 / 1.6 / 2.2), about 300 per airfield on high; lines of men watch and wave along the first 300 m of the take-off run; camps, POW camps, coastal / anti-invasion, V-weapon and decoy sites get soldiers, and ports, docks, works, depots and civil-defence sites get working parties (`WorldPopulator.PEOPLE_SITES`). Ammunition boxes, oil drums and tents stand beside the groups. Placement uses an occupancy grid of everything the site built (`AirfieldPeople.Grid`), so nobody stands in a hangar, pen or parked aircraft.
* **Airfield scenes:** heavy bombers parked behind the spectators at the take-off end (with crews), a field dressing station (hospital tent with red crosses, wounded on stretchers, kneeling medics, doctors, a stretcher party carrying a man in, period ambulances: Austin K2 / Phaenomen Granit), a ring of men passing a football, men smoking, and mechanics on work stands / trestles and wings at the engines of parked aircraft (positions from ModelSpecs and the model's own top surface). Also in the army camps (station, football). Figures are now 1.1x life size, the aircraft models' scale. Debug: `--people-shot=<kind>[,<n>[,<dist>]]`.
* **Airfield ground:** the aerodrome grass fully covers the field patchwork (was 85%), roads are kept off the whole grass zone (1060 x 880 m) and rivers off 1250 m. The terrain's lighting-only relief takes its slope from world-space differences, not dFdx/dFdy (those made dashed lines along the mesh triangle edges). The dashed rows that were left came from the relief height itself: its float-hash value noise (t_vnoise2) stepped along lattice lines at these world coordinates; it now uses the exact integer-hash noise (s_ivn), and the relief shades the colour against the sun (shader global `sun_dir_world`, set by time_of_day.gd) instead of writing NORMAL.
* **Worn airfield grass and the field boundary:** thinner, yellower patches, broken trodden footpaths and subtle muddy hollows in the aerodrome grass (terrain shader, `af_` block); a perimeter fence round each airfield with eight guard towers manned by sentries, and clumps of trees well away from the runway (`AirfieldPeople.dress_perimeter`). The stations' own boundary tree belt is now irregular copses (`Airfield._copse`: gaps, single trees and groups of up to seven, mixed sizes, five tree kinds) instead of identical rows of three. Every layout has one now: the dirt-strip, satellite and glider fields and the forward / ALG strips gained a belt, and the Luftwaffe grass fields a deeper two-row one. Parked aircraft, vehicles, guns, tents and huts now cast shadows close up (`AirfieldProp.SHADOW_KINDS`, with scenery shadows on: `Scatter.scenery_shadow_mode()`); their far stand-ins do not.
* **Living towns and villages** (`AirfieldPeople.town_plan` / `village_plan`, `scripts/ground/airfield_people.gd`): the
  towns of England and France and every tile's village now have people on their streets. Civilians in suits and flat
  caps, women in coats and dresses (with a skirt), the odd constable, ARP warden and Home Guard patrol, and German
  patrols in Axis-held France: walking the pavements, queueing outside shops, chatting at corners, riding bicycles and
  pushing prams. Numbers follow the quality setting - 40-120 for a town on High, 10-30 for a village - as one MultiMesh
  per town / tile, animated entirely in the vertex shader like the airfield men, and placed on the layout / tile
  worker from the scatter's own house footprints and the land-cover street grid pavement lines (the streets the tiles
  and the terrain shader actually draw), so nobody stands in a wall or out in the fields.
  They fade at 1.2 km and dive for cover with the existing Driver when enemy aircraft are low. Debug:
  `--town-people-shot=<n>[,<distance>[,<town id>]]` (a camera on the n-th standing townsperson, optionally of one
  named town such as `folkestone`; it lives on the scene root so it survives the town streaming out, and prints
  `[town-people-shot] at x, z`; give it a high `--frames` (2000) so the town has streamed in, and `--air --freeze
  --at=lat,lon,...` so the player stays by the town; the airfield's `--people-shot` is unchanged). Each town logs
  `[people] town <id>: N on the streets` and each village tile `[people] village tile x,z: N on the streets`.
  A named town's own layout holds few houses, so most of its people are placed on the pavements of the land-cover
  street grid (420 m districts, 34 m blocks, `town_plan` -> `_grid_people`); tests require >= 30 townspeople on High
  for Folkestone's real layout (Folkestone gets 79, Boulogne 97 on High).

* **Free-flight enemy flights with missions** (scripts/modes/enemy_flights.gd, owned by FreeFlightMode when ambient flights are on; replaces the old random two-fighter skirmish / stooging patrol): every 100-190 s (max 3 up) the other side's flight appears in the air about 11 km from the player, on the line from one of its real airfields to a real objective on the player's side (WorldPopulator.raid_targets + the player side's airfields), so flying on meets it. Missions: **raid** (bombers in vics + close escort + top-cover layer that stay with the lead bomber and widen their engage radius when a bomber is hit), **stuka** (Ju 87 attack on a Channel ship near the player, else a port / airfield; Axis only), **sweep** (fighter free hunt: route to an area, 4.5 km square patrol, home; the leader goes back to its route after every fight and the next fighter takes over if it dies), **recon** (one high aircraft over the target). All fly a waypoint route out, over the target (bombs fall) and home to their own airfield, and are tidied away when home and 12 km from the player (or 45 km / 25 min). Size odds 62 % small / 28 % medium / 10 % large (SIZE_ODDS; raid 3-4 / 6-9 / 12-18 bombers plus 2-4 / 4-6 / 8-10 fighters, sweep 2-4 / 6-8 / 10-12), cut down to the free AI slots (AIFactory.ai_room; free-flight AI_CAP 30 -> 40). Medium and large raids are announced by Control on the radio / HUD ("Large raid building, 20+ bandits, heading for Manston") and the player side's fighters are scrambled from the airfield nearest the target. Friendly flights you can join remain PassingFlights; SortieManager (airfield take-offs) is unchanged. **Enemy activity / tempo** (scripts/modes/activity_tempo.gd, preload-only; sortie page option "Enemy activity" Quiet / Normal / Busy, free flight only, remembered as `activity` with the last sortie, pad-reachable like War period): the activity drifts between busy spells and natural lulls so a sortie is not a conveyor belt. First busy spell 150-260 s (first contact as before, 60-100 s); then after each spell a lull with chance 0.75 / 0.55 / 0.2 (Quiet / Normal / Busy; x1.25 at night, x1.2 in rain / storm / fog / overcast, capped 0.95). Lull lengths: Quiet 4-7 min (35 % 7-11), Normal 2-5 min (20 % 5-10), Busy 40-100 s; busy spells Quiet 1.5-3.3 min, Normal 4-8, Busy 6-12. During a lull nothing NEW starts: EnemyFlights launches, SortieManager sorties, land battles, naval fights and the cross-Channel guns are held back (flights already up are never removed); a big raid can break a lull (0.6 / 1 / 2 % per 10 s). A natural lull end pulls the next launch to 25-60 s and sends the optional text cue "Control. Plots building over ..." (`EnemyFlights.lull_end_text = false` turns it off for a voice line). Quiet: launch and event gaps x1.5-1.6, 2 flights up; Busy: gaps x0.6-0.65, 4 flights up, size odds 45/38/17. API: `EnemyFlights.lull_started(length)` / `lull_ended(broken)` signals, `is_lull()`, shared `Tempo.lulling`. Debug: `--activity=quiet|normal|busy`, `[tempo]` lines under `--flights-log`. Tests: _test_enemy_tempo.
Tests: _test_enemy_flights. Debug: --flights-test (first flight after 5 s), --flights-kind=raid|stuka|sweep|recon, --flights-size=0|1|2, --flights-every=SECS, --flights-timescale=N, --flights-log ([mission] lines: launch, status every 20 s, phase changes, resume, over).

## Cloud performance (shaders/cloud_volume.gdshader, scripts/cloud_field.gd)

* **What exists:** one raymarched box proxy per cloud (render_priority 20, shafts 21), procedural 3-octave value noise (no noise texture),
  3 sun taps + 1 sky tap per lit step. Distance LOD (step 55/90/150 m, angular-size step floors), whole-cloud discard past the fade-out,
  `visibility_range_end` 60 km, scene-depth clip, T < 0.03 early exit, Options > Cloud detail Low/Medium/High (`step_k`, `max_steps`,
  `light_every`; cel capped at Medium), adaptive fallback only with FSR 2 + dynamic resolution. Cloud shadows on ground / sea are a cheap
  noise term in terrain.gdshader / water.gdshader (global `cloud_shadow`), not tied to the volumes. Not present: reduced-resolution
  buffer, temporal reprojection, impostors, noise textures.
* **v4.36 additions (shader constants at the top of cloud_volume.gdshader; set the value shown to get the old behaviour):**
  `FADE_CULL` 0.002 (0.0: fragments already faded out are dropped before marching, not after), `CD_EXACT_SKIPS` true (false: skips noise
  taps whose result is provably unused - bit-identical picture), `LAZY_LIGHT_A` 0.004 (0.0: a due light refresh is skipped on samples thinner
  than this and the last light is reused), `FAR_LIGHT_DIST` 20000 (1e9: beyond it lights refresh every light_every+1 steps).
  Debug flag `--cloud-detail=0..2` forces a detail level for a run without touching settings.cfg.
* **Not benchmarked yet:** the user was gaming, so no fps numbers or screenshots were taken. One pre-change sample, 4K realistic,
  scattered, 700 m, Medium, `--perf=10:12` (tools/cache/perf_clouds.ps1, hidden desktop): 31.7 fps avg, 24.2 1% low, gpu 30.0 ms.
  Re-run `tools\cache\perf_clouds.ps1 -Tag after` (and `-Cel`) when the PC is free, compare with a `git stash` of the shader.

## Air-dropped torpedoes (scripts/weapons/torpedo.gd)

* **Aircraft:** RAF **Bristol Beaufort** (new: `data/aircraft/beaufort.tres`, `model_specs.beaufort`, livery scheme `beaufort_raf`, 1 x 18 in Mk XII) and Luftwaffe **He 111** (2 x LT F5b, `torpedoes = 2` in he111.tres). `AircraftStats.torpedoes`; `Aircraft.torpedo_load` swaps the bomb load for torpedoes (`max_bombs()`), models carry `Torp0/Torp1` under the fuselage (`Torpedo.fit_to_body`). The sortie loadout has a Torpedoes No/Yes option (menu.gd, only for aircraft with `torpedoes > 0`, default Yes for the Beaufort; saved as `loadout["torpedo"]`). Debug: `--torpedoes`.
* **Release limits** (`Torpedo.evaluate_release`, `TYPES`): Mk XII 8-30 m above the sea and 45-82 m/s, LT F5b 10-45 m and 50-92 m/s, max 18-20 degrees dive. Inside: the torpedo runs. A little outside: it porpoises (dives deeper, oscillates, may pass under); outside the sea depth: duds into the seabed; far outside (>70 % too high, >28 % too fast, >35 degrees steep): breaks up. HUD message by fate (TORPEDO AWAY / PORPOISING / TOO DEEP / BROKE UP).
* **Flight and run:** air phase with a slight nose-down pitch and wobble, water-entry splash (`FX.water_splash` plus puffs), dive then recovery to the set depth (4.5 / 5 m), run at 20 / 18.5 m/s for 2600 / 2200 m, armed after 250 / 220 m (a hit before arming is a dud), bubble-wake ribbon (inline shader, `WAKE_*`). Runs ashore or aground end the run. Sea depth: the terrain has no bathymetry, so water counts as 40 m deep, never under 6 m (`_sea_depth`).
* **Hit:** hull test against the ship's draught and oriented box; tall white `water_plume`, explosion, debris, flash, delayed fallback curtain, existing SFX only. `GroundShip.torpedo_hit`: heavy damage, lists to the hit side, halves speed, sinks over about 30 s (rolls 40 degrees, trims by the bow, foam). `Weapons.drop_torpedo` / `MAX_TORPEDOES = 10`, weapon camera follows the torpedo (`skip_bomb_view`, camera_rig `dist`).
* **Sight/HUD** (`weapon_hud._draw_torpedo_sight`): ALT / SPD against the limits, predicted entry ring and track, target box on the nearest enemy ship, lead diamond ("AIM nnn m" / "NO INTERCEPT"). Infinite ammo (`GameState.infinite_ammo`) keeps the player's torpedoes, like bombs.
* **AI:** `AIPilot._run_torpedo_attack` (low run-in at 65 % of the drop ceiling, speed eased inside the limit, lead from `Torpedo.lead_point` with the pilot's accuracy error, release at about 760 m only inside the limits and with the entry point on sea, then a 55 degree break away). `AIFactory.spawn(..., torpedo)` sets `torpedo_load`. `EnemyFlights` kind **torpedo** (He 111 for the Axis, Beaufort for the Allies; 8 % of flights; small escorted groups, cruise 500-800 m, ship target of the player's side, else a raid; strike trigger within 6.5 km of the ship). Debug: `--flights-kind=torpedo` (needs `--mode=free --ambient --air`).
* **Tests:** `_test_torpedoes` (limits, arming/range figures, entry and lead, hit damage and slowing, loadouts, infinite-ammo flag, AI kind odds and counts). Debug: `--torp-test` (scripted drop on a moving destroyer, screenshots `build/fix/torp_*.jpg`), `--torp-log`.

## Controller navigation (scripts/pad_nav.gd, autoload `PadNav`)
Every menu is usable with a gamepad (generic JoyButton / JoyAxis, so Xbox, DualSense etc.); mouse and keyboard are unchanged.
- **Mapping in menus**: D-pad / left stick = move focus (stick and D-pad auto-repeat 0.42 s then 0.11 s, jitter filtered);
  A = ui_accept (press / toggle / open dropdown); B = back (ui_cancel; Start also backs out); LB / RB = previous / next tab or
  page (Options tabs, sortie pages, mission-editor tabs) or previous / next marker on a map; left / right = change a slider
  or SpinBox; right stick scrolls scroll areas and drives the map pointer; LT / RT zoom a map. In flight nothing changes:
  B is still weapon toggle, A still fires; B only maps to ui_cancel while a menu is open, and a press a menu consumed never
  leaks into a flight action. Start + B opens and closes pause.
- **Shared helper**: a screen calls `PadNav.screen(self, {first, back, tabs, hints, hints_at, a_label, b_label})` when it opens
  and `PadNav.unscreen(self)` when it closes. A screen stack makes the covered screen non-focusable
  (`focus_behavior_recursive`), saves its focus and restores it on return (Options -> back lands on the "Options" button).
  `PadNav.refocus(node, first)` after a rebuild; `PadNav.pointer(control)` registers a map for the virtual pointer.
  ScrollContainers get `follow_focus` automatically. A hint bar (A Select / B Back / LB RB Page, drawn with `PadGlyph`, no
  copied art) shows only after the pad is used; `hints_at` picks a free corner (bottom_right default, top_left, top_center).
- **Look**: thick brass focus frame with warm fill on every control type (default theme set in PadNav, matching UIKit).
- **Special cases**: maps (flight planner, mission editor, bombsight chart) get a virtual pointer (right stick, A = click,
  X = right click) plus LB / RB marker cycling; key rebinding listens for a pad button too, B cancels it and an 8 s timeout
  stops it getting stuck; LineEdit / TextEdit / SpinBox never trap the pad (D-pad up/down and B step out); the custom
  mission list is picked with A (`item_activated`); MenuButton "Add unit" is focusable.
- **Tests** (`tools/tests.gd::_test_pad_navigation`): input map, initial focus, reachability by `find_valid_focus_neighbor`
  and B handled on StartMenu (all pages), Options (all tabs, rebind cancel), Pause (+Score), results, campaign, dam, legal,
  logbook, donation, story, medal, legal gate, flight planner, mission editor, training film. Not testable without hardware:
  real stick / D-pad repeat on a physical pad (the repeat is driven by tracked D-pad / stick state and was exercised with
  synthetic events on the hidden desktop).

## Practice aids (sortie setup)
Two CheckBoxes on the StartMenu SORTIE page, off by default and remembered with the other sortie options (`last_sortie`):
**Infinite health** and **Infinite ammo**. They reach `Main` as `config["infinite_health"/"infinite_ammo"]` and set
`Aircraft.infinite_health / infinite_ammo` on the player only (AI ignore them).
- Infinite health: `take_damage`, `fire_kill` and `start_breakup` do nothing for the player, so no gunfire, collision,
  taxi-bump or hard-landing damage and no fire / structural kill. Hitting the ground, water or an obstacle too hard still
  wrecks the aircraft (`_crash`), so a sortie can always end.
- Infinite ammo: `WeaponSystem` leaves the player's rounds, bombs and rocket count untouched after firing / releasing.
- With either on, `GameState.sortie_assists` is set: no pilot-log points / decorations (`PilotLog.record_and_announce`), no
  historical-mission "done" mark; the results screen lists "Practice aids". Campaign / career sorties are built without the
  flags, so their progress is unaffected. Test: `_test_practice_aids`.

## War period (sortie setup, scripts/war_period.gd)

* **Where**: SORTIE page, "War period" dropdown under Side (free flight and dogfight only; hidden for historical missions, campaigns, training etc., which keep their own date and the full roster). Pad-reachable like the other sortie controls (tested).
* **Choices**: Any / custom (today's free choice, nothing filtered), Early war 1940-05-10..1941-12-31, Mid war 1942-1943, Late war 1944-01-01..1945-04-30. Table of dates and in-service aircraft per side lives in `WarPeriod` (`PERIODS`, `IN_SERVICE`); only types in `data/aircraft` are listed.
* **Date**: Take off draws a random day inside the period, still inside the Season choice if one is set (`WarPeriod.random_date`); that feeds `era_date` / `EraClock` so airfields, ground, weather month and the era-driven land battles follow it.
* **Aircraft list**: the menu list is narrowed to the period (`AircraftCatalog.ids_for_side_period`); the current aircraft stays if it fits, otherwise the closest fit (same role, same family) is selected and a note is shown.
* **AI / ambient**: `main.start_game` sets `WarPeriod.active`; `AircraftCatalog.fighters_for_side` / `bombers_for_side` narrow to it (empty pool falls back to the full list), so enemy flights, passing flights, Ops Room, sortie manager etc. pick period types; dogfight waves and the recon pair use `WarPeriod.substitute` / `filter_or_all`; backup flights already pick by year. "Any" leaves everything as before.
* **Remembered** with the last sortie as `war_period` (`art_style` untouched). Shown on the BRIEFING page and as "War period" on the results screen.
* Tests: `_test_war_period` in tools/tests.gd (dates in range, lists in service, AI picks in period, Any unchanged, menu behaviour, pad reach).
* Known gaps: hard-coded raid kinds in enemy_flights (Stuka `ju87`, torpedo `he111` / `beaufort`) are not period-filtered.

## Art style: Realistic / Cel-shaded (scripts/cel_shade.gd, shaders/cel/)
Options > Video > Art style. Index 0 = Realistic (default, byte-for-byte the old path: every cel hook is gated on
`GameState.art_style == 1`), index 1 = **Cel-shaded** (the old "Pixel art" slot, same saved index; pixel grid, dither and
palette are gone). **F7** (action `art_style_toggle`, remappable in Options > Controls) flips between them in flight with
a HUD toast and saves through `set_graphic`.
* Post pass: a full-screen quad (`CelShade`, `cel_post.gdshader`, render_priority -128 so clouds and the sea, which are
  transparent, draw on top of its opaque-only screen copy - at +100 it overwrote them) reads colour, depth and normals:
  full-resolution ink lines (one-sided depth second difference + normal creases, width scales with window height),
  2-3 flat light bands, saturated colours (greens teal-shifted, gold/mustard damped), clean banded sky. HUD untouched.
* Aircraft: inverted-hull ink (`cel_ink.gdshader`) - thick black on the player, team ink on AI (red enemy, yellow
  friendly, fog-free so distant aircraft stay readable); canopy glass gets haze + glint streaks (cel only).
* Sea and clouds: water/seabed recoloured (ultramarine offshore, lighter near the coast) via `set_cel_look`; clouds use
  `cel_k` in `cloud_volume.gdshader` (flat white tops, two hard blue-grey bands, ink rim).
* Lowered only while cel is on (recomputed in `apply_graphics`/`apply_post`, restored on Realistic, saved settings never
  touched; `GameState.art_style_saved` is what `settings.cfg` holds, so the debug `--cel` flag cannot leak into it):
  MSAA -> off (FXAA), soft shadow filter -> hard, sun shadow atlas 4096 / 2 cascades / max distance 1400, shadow blur 0,
  SSAO, SSIL, SSR, volumetric fog, glow and reflected sky light off, FILMIC tonemap (exposure 1.0, contrast 1.0,
  saturation 1.1), fog density x0.12 with no sun scatter, cloud detail capped at Medium, terrain detail texture off.
* Debug: `--cel` forces it for a run (`--pixel` is the old alias), `--call-after=N:set_art_style:0|1`,
  `--cloudview=kind:nth:dist:dy` puts the camera next to a cloud. Tests: `_test_cel_style`, `_test_cel_ink`,
  `_test_art_style_key` (incl. "Realistic leaves every graphics setting at its saved value").
* **Aircraft range (both styles):** the detailed model swaps to the far stand-in boxes beyond 1.8 km (`Aircraft._update_lod`,
  unchanged, the boxes are cheap); camera far is 48 km. The AI team outline (`shaders/team_outline.gdshader`, Realistic and
  the Outline options) is now fog-free (the haze used to wash a far red / yellow outline into the sky), never ends before
  16 km whatever the saved "Outline fade out" says (`OUTLINE_MIN_END`), and fades over the last 6 km instead of 2.5 km (no
  pop); defaults 12 km, slider to 20 km, clamp 25 km. Root cause of the 'outline pops in too short': the far stand-ins are
  BoxMeshes with per-face normals, so the normal-expanded hull left no ring (both styles). Their overlay materials now use
  `box_hull` (inflate along sign(VERTEX)), and beyond 1.2-3.5 km the Realistic ring grows x1.5 and goes opaque (`v_far`). Hidden
  shots (`--ac-line=2500;5000;8000;12000;16000;20000,2,bf109,Axis --wingmen=0`): before, no red at all past 2.5 km; now red
  markers clear to ~12 km, small to 16-20 km, in both styles. Cel ink (`cel_ink.gdshader`) is fog-free already and its size clamp
  (`max_dist`) went from 12 km to 24 km. Outline width stays ~1.3 px (Realistic) / the cel ink weight per side.
* **Close-range team markers (v4.31):** the red / yellow AI outline is thin and soft up close and only grows with
  distance, so the on-screen size stays about 1-2 px: `team_outline.gdshader` ring x0.35 at <1.5 km rising to full at 6 km,
  alpha 0.22 at 300 m rising to 0.5 at 3 km, the heavy far styling (x1.5 ring, alpha 0.95) builds up over 3-6 km (was
  1.2-3.5 km), so 8-20 km is unchanged; the cel ink of AI aircraft (`cel_ink.gdshader`, `soft_near` = 1 for non-player
  aircraft) is x0.4 under 1.5 km rising to x1 at 6 km.
* **Thinner player ink (v4.31+):** the player's black cel ink is about 37% of its old width at every distance, including the
  LOD boxes and the prop ink (`PLAYER_INK_WIDTH` = 0.375 in `aircraft.gd`, applied through the `width_scale` uniform of
  `cel_ink.gdshader`). AI team ink is unchanged (`width_scale` 1.0). Realistic has no player outline, so nothing changed there.
* **Spawn keep-clear (v4.31):** root cause of 'Axis spawn inside ground assets, plane stuck and dying': the dispersal pad
  (`taxi_flight_routes[0]`, where the player spawns) is also where `WorldPopulator` scattered Luftwaffe E-pens, camo nets and
  boundary markers, and `AirfieldFurniture` put revetment banks, flare-path lamps and dummy aircraft; solid scenery registers
  in `Obstacles`, and a ground bump at under 9 m/s stops the aircraft dead and costs 15 health per 2 s. All of those now go
  through `Airfield.off_taxi_routes(xforms, margin)`, which drops anything within `margin` of a taxi-flight polyline (pens 18 m,
  nets 16 m, markers 6 m, revetments 12 m, lamps 5 m, dummies 14 m). Check: `tools/tests.gd` `_test_spawn_clear` builds every
  real airfield record (both sides) plus every layout / style for RAF and Luftwaffe and walks every taxi route and a runway
  start with `Obstacles.scan_route(spawn, route, 3.0 m, gear)`; it failed before the fix and passes now. Headless has no
  MultiMesh instance data, so `Scatter.multi` stores the transforms in the `obstacle_xforms` meta only when headless (the
  obstacle index reads it). Debug flags: `--start-af=<id>` (spawn the player at that airfield), `--spawn-audit` (prints
  `[spawn-audit]` clearance and a once-a-second pos / speed / health line; taxi bumps print `[obstacle] taxi bump`),
  `--prop-blur` (force the prop blur disc, for shots).
* **Prop edge vs clouds (v4.31):** root cause of 'distant clouds draw over the edge of the prop': the soft-edged rim ring of the blur
  disc (`AircraftModels._add_tip_ring`, used by the Spitfire and the builder aircraft) had material render priority 0, while the
  cloud volumes are 20 (shafts 21) - transparent objects sort by priority first, so every cloud was drawn over the ring. It is now 40
  like the disc (`prop_blur`, priority 40, depth_draw_never). The ring (a child called TipRing, which the `*disc*` name filter missed)
  also took the cel ink hull / team outline overlay; `Aircraft._skips_overlay` now leaves it out, and the blades / spinner get their
  outline at `PROP_OVERLAY_PRIORITY` 30 (team outline) or a depth-writing ink variant (`_prop_ink`, cel) so clouds stop at them. Proof
  (hidden desktop, Spitfire, nose up 20 deg, `--prop-blur --rail-pitch=20 --cloudview=99:0:2500:900`, rim ring forced bright, `--ring-old`
  = the old priority 0): `build/perf/ring_old_cock_real.jpg` / `ring_old_cock_cel.jpg` (ring cut by clouds) vs `ring_new_cock_real.jpg` /
  `ring_new_cock_cel.jpg` (unbroken). Debug flags: `--rail-pitch=DEG` (nose-up still frames with `--rail`), `--ring-old`.
* **Cel speed:** `cel_post.gdshader` skips every depth / normal tap beyond `line_far` (3.5 km) and normal taps beyond
  `normal_far`, and reconstructs linear depth from the projection's z / w terms instead of a mat4 multiply (identical
  image, far pixels - most of a flight frame - cost 1 colour + 1 depth tap). Aircraft ink materials are shared per colour
  (`Aircraft._ink_cache`) and the redundant team-outline overlay is not built in cel (the opaque team-coloured ink hull covers
  it; `refresh_art_style` puts it back on Realistic). `CelShade` writes `view_px` only when the window size changes.
  Hawkinge, 1080p, uncapped, run 0 of each batch dropped (first run of a batch is ~3x slow on this PC): Realistic 72.0 fps,
  Cel 75.3 fps, same hitch count.
* Debug / perf flags: `--realistic` (force Realistic for a run, settings untouched), `--no-vsync` (uncapped), `--ac-line=DIST[,N[,model[,side]]]`
  (N frozen AI aircraft DIST m ahead), `--perf=SECS:SETTLE` now also prints hitch33 / hitch50 / worst_ms / med_ms.## Occupation life (Phase 5, scripts/ground/occupation_life.gd)
- German garrison in Axis-held towns of size 2 and up: two sentries either side of the town hall door (facing out, from the
  civic "townhall" entry's yaw), a two-man patrol across the square on High, and two sentries at the station (civic
  "station" entry). Made by OccupationLife.garrison, called from AirfieldPeople.town_plan with the same HouseMap, so
  no sentry stands in a house. Allied towns get none. Harbour sentries and the Kommandantur flag are built now (see War props below).
- French civilians: OccupationLife.civilise runs on a town's men after planning (WorldPopulator._build_city). In a
  continental town (continental(lat, lon): east of 1.5 E, or south of the Channel shore) the British-only outfits
  (constable, ARP warden, Home Guard rifleman) become a dark suit or a tweed jacket. There is no gendarme outfit yet.
  Village tiles still plan with the shared town_dress, so a liberated French village can still show British police
  until the village hook gets a latitude and longitude (not done).
- Luftwaffe airfields: unchanged; AirfieldPeople.populate already covers the Axis fields. The horse-drawn wagons and the
  field kitchen are built now (see War props below).
- Tests: _test_occupation_life in tools/tests.gd (continental coast, no British outfit in Axis towns, Boulogne civilians
  made French, Axis garrison only in Axis towns).
- Note: the module is loaded with const OccupationLife := preload(...) rather than class_name, because a new
  class_name is not in the editor's class cache until a project import.

## War props (scripts/ground/war_vehicles.gd)
- Crash scenes: a red fire engine with a ladder and bell (English side) or a grey Opel Blitz (German side) parks on
  the road about 12 m short of the ambulance, with 2-3 dark-clad firemen. Built inside WarReactions' gang (`_add_engine`, `_tick_fire`).
- Kommandantur flag: a red flag with white discs on an iron pole over the town hall in Axis-held towns of size 2 and up (no swastika).
  Hooked from WorldPopulator._build_city.
- Harbour sentries: two German sentries 9-12 m landward of Axis port and dock sites (`port_` / `dock_` keys). Hooked from WorldPopulator._site_people.
- Field kitchen: one kitchen trailer with 4-6 men and 1-2 horse-drawn wagons at Axis airfields, placed through AirfieldPeople's Grid.
  The wagons are static.
- Test: `_test_war_vehicles` in tools/tests.gd.

## Military life everywhere (Phase 3, scripts/ground/military_people.gd)

* **Gun and searchlight crews:** when a built site enters the world (`WorldPopulator._site_people` -> `MilitaryPeople.scan_site`)
  every `AAGun` (88 mm / 3.7 in, Bofors, machine-gun pit) gets 3-7 men (`crew_size`, from the type and the quality
  setting) and every `Searchlight` 3-4. They stand about outside the sandbag pit's entrance and, when an enemy aircraft
  is within 1.5 km and below 3 km, RUN in to their posts on the pit floor (layer and spotter reach, loaders kneel at the
  ammunition, ammunition number works, the sergeant shouts at the entrance); they walk back 8 s after the last enemy.
  The run is the shader's RUN beat started at the matching clock phase (`beat_phase`; the shader TIME is measured once by a
  4 x 4 pixel `TimeProbe` render), then swapped for the stationed pose. One MultiMesh + `CrewDriver` per 400 m cluster of guns
  (the usual "everybody lies flat" driver is replaced for these). Searchlight crews work the lamp at the alarm.
* **Sentries:** one at each pillbox / bunker (two on High), and at coastal batteries at the end casemates and the fire-control post.
* **Per countryside tile** (`tile_plan`, planned on the tile worker with the village houses, `spawn_tile` on the main thread):
  Home Guard (English side) or Feldgendarmerie (Axis-held ground, `GroundKit.side_at`, so the 1944-45 front moves it) at
  crossroads outside the villages with a pole barrier, sandbags and a sentry box (`barrier_mesh`); pairs of rifle-carrying
  soldiers marching a beat along beaches and cliff tops (both coasts); and roadside halts with 2-3 lorries on the verge and
  4-7 men stood about them. Every spot is checked against the tile's `HouseMap`, land and bounds. Counts follow `density()`.
* **Debug:** `--mil-log` (prints sites, checkpoints, halts, patrols, the shader clock offset), `--mil-alarm[=s]` (crews are
  alarmed `s` seconds after they exist), `--mil-shot=<gun|light|sentry|checkpoint|halt|patrol>[,<distance>[,<skip>]]` (a held
  camera on the first such group, picked with `--mil-pick=<frame>`; hidden-desktop screenshots only),
  `--mil-demo=<gun|checkpoint|halt|patrol>[,<distance>[,<Allies|Axis>]]` (builds that group on open ground ahead of the start
  and holds a camera on it). Test: `_test_military_people` in `tools/tests.gd`.

## Life on the farms (Phase 2, scripts/ground/farm_people.gd)
* A few work parties per countryside tile (about 2 x density() x a month factor: 4-5 on High in August, 2 in January), planned on the
  tile worker next to `village_plan` (`FarmPeople.plan`, hooked in `WorldPopulator._start_tile_job`, spawned in stage 0 and by `_tile_people`).
  Each party is INSIDE a field: cropland or grass, at least 9 m from every field boundary (`Scatter.field_edge`, the CPU mirror of
  the terrain's field lattice), off roads / rivers / lakes / the sea, clear of the tile's houses (the farms are the anchors), along its
  whole beat and a margin beyond it.
* Seasons follow `EraClock.month()` and the terrain's crop cycle (`FarmPeople.JOB_W`): ploughing with horses (and a few Fordsons, rarer
  in France) October to March, sowing and hoeing March to June, haymaking June-July (cart, forkers, haycocks), harvest July-September
  (stooks, a gang bent to the sheaves, a loaded cart with forkers), fodder carting from a haystack in the dead of winter.
* New figure Kinds (appended, nothing renumbered): `PITCHFORK` 24, `HOE` 25, `LEAD_HORSE` 26, `DRIVE_CART` 27, `PLOUGHMAN` 28; farm
  dresses 16-20 (English farmer, Women's Land Army, farm boy, French farmer in a blue smock and beret, French farm woman); a pitchfork
  and a hoe as item parts 14 / 15 on the right forearm. Kinds 26-28 ignore the raid's dive and held-back clock (they move with a prop).
* Props (`shaders/farm_props.gdshader`, one MultiMesh per prop type per tile): a horse led with a hay cart, a driven horse and cart,
  a plough team of two horses, a Fordson-like tractor with a trailed plough; animated walk (legs, head, tail) in the vertex stage.
  The man and his prop are spawned from the same entry and run the same beat maths, so they stay rigid through the headland turn.
  Stooks, haycocks and haystacks are plain still MultiMeshes. All low poly, built in code, nothing from other games.
* Debug: `--farm-shot[=<plough|tractor|sow|hay|harvest|feed|any>[,<distance>[,<lat>,<lon>]]]` puts a camera on a work party (use with
  `--date=YYYY-MM-DD` to pick the season); the log prints `[farm]` and `[farm-shot]` lines.
* Test: `_test_farm_people` in tools/tests.gd.

## Things that react to the war (`scripts/ground/war_reactions.gd`)

* **Crash scenes:** an aircraft (either side) that comes down on land draws locals and soldiers: they run in from
  70-170 m, stop on a ring 25-40 m from the wreck and talk, smoke or wave people back; Home Guard / police / ARP
  wardens and civilians on British ground (also Allied-held France), German soldiers on German-held ground, and an
  ambulance up the nearest road (within 220 m). One MultiMesh per scene, at most 4 scenes, cleared after 7 minutes or
  when the camera is 3.2 km away; crashes more than 6 km from the camera are not staged.
* **Downed pilots:** a parachutist who lands on land gets 2-4 captors walking up; the pilot raises a hand (WAVE) if
  they are of the other side ("captured"), otherwise just talks.
* **Low passes:** below 60 m the player's aircraft makes friendly people within 150 m (civilians, own-side crews and
  soldiers) stop, turn and wave for 3.5-5.5 s; while the guns fire, friendly people within 130 m run 20-30 m away and
  crouch. Enemy troops dive through the existing `AirfieldPeople.Driver`. A scan at ~8 Hz over the `people_mm` group
  (every `AirfieldPeople.spawn` MultiMesh), working on cached arrays; measured 0.03 ms in the unit test.
* **Runner timing:** the figure shader walks a beat there and back from its own `TIME`, so to make a runner stop at the
  ring the manager samples the shader time once with a 1-pixel SubViewport probe (`shader time probe ok` in the log,
  drift about 1 ms) and starts the stride at the launch moment. Headless runs fall back to the engine clock.
* **Debug:** `--crash-scene-demo=close|far[,ahead,right]` (with `--hawkinge --freeze --nohud`, shot after ~80 s;
  `--frames=5000`). Tests: `_test_war_reactions` in `tools/tests.gd` (headless MultiMeshes cannot be read back, so
  the scene keeps `cur_pos` / `cur_code` mirrors).
* **Time of day:** T steps through eight parts of the day (first light, sunrise, morning, midday, afternoon, golden hour, dusk, night) at a random time inside each (`TimeOfDay.STEPS`); --time= and missions keep the named presets. Golden hour warms the sky, sun and clouds fully but the light on the ground only part-way (the low-sun ground boost is 0.45, was 1.5).

## Ground people / low-light notes (c1 round)

* Figures: one MultiMesh mesh posed in `shaders/airfield_people.gdshader`. Dress 8-15 town, 16-20 farm, `CIV_GENDARME` = 21 (dark blue tunic and kepi; French constables via `occupation_life.civilise`). Part ids >= 10 travel as UV.y = 100 + part (10 stretcher, 11 bicycle, 12 pram, 13 skirt, 14 pitchfork, 15 hoe). Axis town sentries use field-grey Wehrmacht colours.
* Harvest parties also lay a subtle stubble ground patch (`farm_people._spawn_patches`).
* Debug flags (put after `--air --freeze --at=`): `--people-lineup=ride|med|law|farm[,yaw,team,dist]`, `--look=lat,lon,dist,height[,yaw,delay,aim_up]`, `--look-xz=x,z,...`, `--no-alarm`, `--town-people-shot=n,dist,town,KIND[,dress]`.
* Kommandantur flag sits on the Boulogne town-hall clock-tower finial; Saint-Omer field kitchen + horse wagons verified on screen.
* Low light (`time_of_day.gd`): dusk/dawn ambient lift 0.9 -> 0.5, ambient x(1-0.18*low), sun x(1-0.10*low), sky ambient share x(1-0.35*low), cooler ambient at golden hour. Not yet verified on screen.

## Battle ruins (scripts/ground/battle_damage.gd, autoload `BattleDamage`)

Wherever a fight is staged the buildings nearby are left as WW2 ruins. Callers (tank battles, ship skirmishes, bombs) only use the API:
`BattleDamage.ruin_area(world_pos, radius_m, intensity = 1.0, seed = 0)`, `crater(world_pos, size_m)`, `on_blast(world_pos, blast_radius_m)`
(a bomb / big shell burst: craters in the open, a ruined patch in a built-up area; `Weapons.explode_at` calls it for every ground burst),
`scar_at(world_pos, radius_m = 0.0) -> bool`, `clear()`. Repeated calls from the same spot fold into one scar (cheap; a bigger radius or
intensity re-makes it). Scars last the session and are not saved.
* **Buildings:** a scar is a live battle area in `WarDamage` (`set_battle`, copy-on-write so tile workers never see a half-edited list), so every
  tile / town built while it exists gets gutted shells and cleared plots (`apply_to_houses`, same deterministic hash as the dated bomb damage).
  Already-built tiles are re-made on a worker by `WorldPopulator.battle_refresh` (the old tile stays until the replacement is ready, `_replace_tiles`),
  town sites (`city_*`) are rebuilt from their stored layout, and the terrain's rubble / scorch zone (group `damage`) is refreshed. `WarDamage.ruin_mesh`
  now has a stepped, jagged gable, broken front / back walls, a flue, charred rafters and rubble spilling out into the street.
* **Debris and fire:** one node per scar while the player is within radius + 5.5 km (freed beyond +8 km): MultiMesh craters (raised rim, black floor), scorch
  patches, rubble piles, broken wall runs, leaning chimney stacks, a burnt barn frame in open country; black smoke columns (10-20 min) and 1-4 small
  fires (1-4 min) on the scar's own clock (`FX.pillar` / `FX.blaze`, stopped when their time is up). Single craters are one MeshInstance3D each (cap 200).
* **Art style:** the meshes use the shared vertex-coloured scenery material, so Realistic and Cel look the same way as the houses (cel ink and bands come from the post pass).
* **Tests:** `_test_battle_ruins` (ruins inside the radius and none outside, persistence for later tiles, merge, clear, intensity, craters, meshes, node build).
* **Debug:** `--ruin-test=<lat,lon | town:id>[,radius[,delay s[,intensity]]]` (use with `--air --freeze --at=lat,lon,alt,hdg` and `--look-xz=x,z,dist,height,yaw,delay,aim_up`); screenshots `build/fix/ruin_*.jpg`.

## Land battles (scripts/ground/land_battles.gd director, scripts/ground/land_battle.gd one battle)

* **What:** in free flight with ambient flights on (same switch as EnemyFlights / NavalSkirmish; also `--battle-test`) a tank-and-infantry battle appears every 4-9 minutes (first after ~75 s, two live at most, 9 km apart) at a site 3.5-8.5 km from the player: open ground (ESA land cover not wood / water, 8 of 12 points on a 350 m ring drivable), at least 3 km from every airfield. It is announced by Control on the radio, shows as a pin on the chart (M, `FreeFlightMode.map_pins`, and as the compass point when there is no Ops Room tasking), runs 9-13 minutes at most, then winds down; wrecks and fires stay until the player is 16 km away (or 4.5 km away 150 s after the end).
* **Plausibility (the 1940-42 Channel front had no tank battles in England), by date and ground:** before 25 Jun 1940 French ground "arras" (Matildas v Pz 38(t) / Pz III, the real 21 May fight); Jun 1940 - May 1943 French ground "raid" (an Allied raid in force, Dieppe style: Churchills from Jun 1942, Matildas / Valentine before, against Pz III, three PaK and a couple of lorries); Jul 1940 - Dec 1941 English ground "sealion" (a WHAT-IF German foothold: Pz III / 38(t) / IV against Matildas, Valentines and anti-tank guns; `LandBattles.WHATIF_SEALION`, off with `--no-whatif`); Jun 1943 on, "normandy" (Shermans v Pz IV / Tiger). English ground at any other date: no battle. Beach scenarios put the attackers' start towards the sea.
* **Units:** `GroundVehicle` (new types `churchill`, `matilda`, `valentine`, `panzer3`, `pz38t`, `pak`; the rest existed) - so they are normal GroundTargets: group `damageable` + `team_<side>`, take bombs / rockets / cannon, wreck + fire + score through the existing paths. Infantry: one MultiMesh per squad of the airfield men (5-8 on the quality setting), a squad runs a bound (the shader RUN beat started at the right clock phase, `MilitaryPeople.beat_phase`), then goes to ground (the shader's `alarm` = lying flat) and fires; casualties fall (shrinking MultiMesh + a corpse MultiMesh), a squad below 40 % routs. Tracers: a pool of 56 emissive streaks, no damage to aircraft.
* **Behaviour:** the attackers' tanks advance in bounds (move 8-13 s, halt and fire 5-9 s) to 190-300 m from the objective with the squads following behind them; defenders hold, a tank shifts position now and then; PaK and tanks pick tanks first, then infantry (HE plume + casualties) and fire MGs at squads; hit chance falls with range and a moving target, damage 26-80 so a tank takes 2-3 hits; below 38 % health a tank brews (smoke, 2.5-6.5 s) then blows (`die()`: fire, black smoke, burnt wreck with the blown turret). Low enemy aircraft pin squads. A battle ends when one side has no armour and under 40 % of its men, or after 9-13 min; each battle has a random edge (0.75-1.3) for the defenders. Distance LOD: logic ticks at 4 / 2 / 1 Hz by distance (<3.5 / <7 / far km), effects, tracers and per-frame movement only within 6.5 km, tanks move in ticks beyond 3.5 km. Vehicles that stand in a house once the village streams in (`Obstacles.hit`) are moved to open ground.
* **Player interaction:** vehicles are damageable targets of the right team; killing one of the enemy's counts in `battle_kills`, a hit on the player's own side's vehicle or men (bomb / rocket splash within 11 m of a destroyed vehicle) counts in `battle_friendly_fire` with a HUD warning; both go into the free-flight stats (`FreeFlightMode._stats`). Score comes from the vehicles' normal GroundTarget points (`Weapons.player_kill`).
* **Radio:** `Radio.say("Control", ...)` + `hud.show_message`, text only: "Tiger 1, Control. Our Churchills are pinned down at Wissant by Panzers and anti-tank guns, requesting air support!" (or, when the player's side is defending, "Panzers attacking at ..."); a second call "We are being overrun at ... Anything you can spare, now!" when the player's side is down to a third of its armour; "Well done, the Panzers at ... have been broken" if the player helped and his side won.
* **BattleDamage:** `ruin_area(centre, 170, 0.5, seed)` when the battle starts and every 80 s with rising intensity (to 280 m / 1.0) while it runs; `crater(pos, 3-6 m)` for up to 28 shell misses (FX crater when BattleDamage is absent). Looked up as `/root/BattleDamage` and guarded.
* **Debug:** `--battle-test` (first battle 6 s after start, `--battle-dist=M` ahead, default 2200, ignores airfield clearance), `--battle-kind=raid|arras|sealion|normandy`, `--battle-every=SECS`, `--battle-log` (`[battle]` lines), `--no-battles`, `--no-whatif`, `--battle-shots` (hidden-desktop pictures `build/fix/battle_*.jpg` and fps; use with `--air --freeze --at=50.60,1.62,500,0 --date=1942-08-17 --nohud --battle-test --battle-kind=raid --battle-dist=1800`, `--battle-timescale=N`).
* **Minimap:** each air-support call (start, losing) rings the battle centre on the minimap ("ground support requested": pulsing ring with crossed blades, clamped to the chart edge with an arrow when it lies beyond the chart) through `hud.register_support_marker`; the ring goes when the battle finishes (`_drop_support`).
* **Tests:** `_test_land_battles` (scenario by date / ground, spacing odds, site selection on land clear of airfields and of other battles, landing direction, every scenario's forces / teams / land, a hit destroys a tank and leaves a wreck, battles end with a winner, men fall and own-side casualties count as friendly fire, the air-support call, the overrun call, the Axis player's call).


## Naval skirmishes (scripts/ground/naval_skirmish.gd, class `NavalSkirmish`)

* **What:** now and then ships of opposing sides fight in view of the player: E-boats (S-boote) rushing a British
  coastal convoy (night 80 %), a German destroyer duelling the escort, MTBs / MGBs or destroyers hitting a German
  coastal convoy. The manager (a child of free flight, created with the ambient flights) scans every 2 s: opposing
  armed ships already in gun range may open fire (chance per scan <= 0.12, x1.5 at night), or an opposing patrol is
  spawned 1.5-3 km off a convoy 1.5-8 km from the player. First fight after 150-260 s, then a 330-660 s cooldown;
  one engagement at a time; an engagement 14 km from the player is dropped.
* **Behaviour:** `GroundShip._process` hands engaged ships to `NavalSkirmish.drive()` (hook `skirmish` in
  ground_ship.gd). Fast boats make attack runs, fire torpedoes (surface-launched wake runs, `torpedo_hit` listing and
  sinking reused), break away laying smoke, come round again, flee when hurt; destroyers close to a standoff range and
  turn broadside; escorts intercept and then rejoin the convoy station; merchants scatter (faster, weaving). Shells
  straddle short then over, then bracket (`spread()` shrinks per salvo; fast boats are harder to hit); hits damage, list
  and slow ships, fires and smoke below 50 % health, sinking via GroundShip. Shells landing ashore call
  `BattleDamage.crater / ruin_area` when the autoload exists. Starshells at night. Single-mesh models: turrets do not
  traverse, ships turn broadside instead. New hulls `eboat`, `mtb` (GroundShip.TYPES, ShipModels `_fast_boat`).
* **Radio:** one text call per engagement through `Radio.say` + HUD message (and minimap markers on the attackers):
  "Convoy Peewit under attack by E-boats off Dungeness, any aircraft in the area, request immediate support! Bearing
  317, 2 miles." When the player's side is attacking, its boats ask for air support instead. A short thanks / loss line
  follows at the end. Shared helper: `NavalSkirmish.request_air_support(hud, sender, text, world_pos, player_pos)`.
* **Minimap:** the air-support call also rings the fight on the minimap (the same "support requested" ring as the land battles, `_support_mark`), removed when the engagement finishes (`_unsupport` in `_finish`).
* **Cost:** nothing but the 2 s scan when idle; effects only within 6.5 km of the camera, shell tracers are a pool of 40.
* **Debug:** `--naval-test` (convoy + attack in front of the player after 4 s), `--naval-log`, `--naval-every=SECS`
  (first and later cooldown), `--naval-kind=eboat|mtb|destroyer`, `--naval-team=Allies|Axis`,
  `--naval-shots=<dir> --naval-tag=day|night` (flies the camera over the fight, writes naval_<tag>_N.jpg, logs fps, quits).
  Hidden-desktop example: `--skip-menu --mode=free --side=Allies --aircraft=spitfire --air --autopilot --at=50.70,0.9,700,90 --time=night --naval-test`.

## Cross-Channel guns mission (scripts/ground/gun_shelling.gd, coastal_gun.gd, coastal_battery.gd, scripts/modes/gun_batteries_mode.gd)
* Three heavy-battery targets (type `heavy_battery` in data/locations.json, built by `WorldPopulator._build_heavy_battery` as `CoastalBattery`): Grosser Kurfuerst (Cap Gris-Nez, 4 casemated guns), Friedrich August (Wimereux, 3 casemates), K5 railway guns (Coquelles, 2). Each has camouflaged open gun pits / railway carriages, 2 ammunition bunkers (chain explosion within 60 m), a fire-control tower and ringed flak (88 mm, Bofors, MGs). All sites are on land (checked against LandCover in tests).
* `GunShelling` (node kept under the world, independent of tile streaming) runs the bombardment: guns traverse (4 deg/s) and fire on a cycle (casemate 62 s, railway 150 s) with muzzle blast, smoke ring, dust. Shell flight time = range / 430 m/s (about 79 s at 34 km); impacts on Dover, Folkestone and the Strait with dispersion 90 m (x2.6 once the fire-control tower is dead): large explosion, craters, fires, water plumes at sea, nearby damageable things hurt, `BattleDamage.ruin_area/crater` (guarded, optional). Far batteries show flash / smoke / thunder.
* Killing guns: bombs/rockets/cannon via the `GroundTarget` contract (casemate hp 300, railway 230, cannon fire does 3 percent). A battery falls silent at 75 percent of its guns lost; destroyed guns persist across tile streaming.
* **Minimap (free-flight ambient event):** when the Dover bombardment call goes out, each battery still firing gets a "support requested" ring on the minimap (`GunShelling.mark_support`, anchors `SupportMark_<battery>`). A ring goes when its battery is silenced (`unmark_support`), and the rest go when the bombardment stops (`unmark_all_support` in `stop()`).
* Missions (Historical list): "Silence the Guns: Cap Gris-Nez" (gun_batteries_1940, Allies from Hawkinge; Axis defend variant from Calais-Marck) and "The Gun Line: Calais Railway Guns" (gun_batteries_railway, Manston). `gun_mission: true` makes `HistoricalMissions` use `GunBatteriesMode` (a `BombingMode`): HUD shows guns down x/y, FIRING/SILENT, shells on town; results record guns destroyed, shells landed on town, and whether the town was spared.
* Free flight (Allies, ambient events on): after about 150 s a radio call "Dover under shellfire from Gris-Nez, any aircraft to attack the batteries" starts a bombardment window; the nav point points at the nearest live battery. Works with the PadNav nav list and infinite health/ammo aids.
* Debug flags: `--mission=gun_batteries_1940`, `--guns-test[=shots]` (hidden-desktop screenshot harness, `build/fix/guns_*.jpg`, `--guns-out=`), `--guns-log`, `--guns-first=<s>`, `--guns-target=<id>`, `--guns-timescale=<x>`, `--guns-event`, `--no-guns`.
* Tests: `_test_cross_channel_guns` in tools/tests.gd (sites on land, flight time, impact at target, slewing/recoil, silencing stops fire, objective/results, ambient radio hook).

## Ground target markers (scripts/ground/ground_marks.gd; Options > Gameplay > "Ground target markers")

* **Option** `GameState.ground_markers` (settings.cfg `[gameplay] ground_markers`, never touches art_style): 0 Off, 1 Smoke only, **2 Outlines + smoke (default)**, 3 Full. Plain `OptionButton` row, so PadNav handles it.
* **Outlines:** shared cached `ShaderMaterial` overlays (4 per art style: enemy / friendly x box / other mesh): `team_outline.gdshader` in Realistic, `cel/cel_ink.gdshader` in Cel (both got a `range_m` uniform; aircraft are unchanged with the default `(0, 0)`). Enemy = red, friendly = yellow (colour-blind: blue / yellow). Fades in from 500 m, gone by 8 km, thin and soft up close. Applied by `GroundMarks.update` (10 Hz, called from `hud.gd`) to enemy GroundVehicle / GroundShip / AAGun / CoastalGun within 8 km (dropped past 9 km) and to friendly units that carry meta `gm_event` (land battle units, naval skirmish ships, coastal guns). `GroundShip._apply_team_outline` no longer puts a permanent overlay on (the option controls ships now). Infantry squads have no per-man outline (MultiMesh).
* **HUD brackets** (`hud.gd _draw_ground_marks`): red corner brackets over the nearest 12 enemy units of an event (distance on the nearest and on the one nearest the crosshair), small yellow ticks over friendlies within 4 km, edge arrow with distance for each off-screen support spot. Shown while air support is requested (mode 2) or whenever an event is within 8 km (mode 3).
* **Minimap:** red / yellow dots (max 48) for the units of a nearby event, same gating.
* **Marker smoke:** `LandBattles._support_mark` (start and "losing" calls) calls `GroundMarks.battle_smoke`: yellow `FX.marker_smoke` on the enemy position (30 m towards our line), white on our own line, 100 s each, refreshed every 60-100 s (meta `gm_smoke_at`, housekeeping) while the battle runs and the player is within 14 km. New `FXEmitter.Kind.MARKER`, `FX.marker_smoke`, `FX.gun_flash` (a larger muzzle flash, used by land battle tank fire seen from > 450 m).
* **Perf:** 10 Hz scan over four groups, no per-frame allocation (HUD list rebuilt at 10 Hz), materials shared, overlay only inside 8-9 km.
* **Tests:** `_test_ground_markers`.