# SESSION 2026-10-22: copyright cleanup
- **Music:** deleted the *Battle of Britain* film score (19 tracks in `assets/music/ingame/`), the three BBC Churchill broadcast recordings and the newsreel / NBC radio clips from `assets/music/` and `assets/music/victory/`. Menu music is now copies of two Pixabay tracks (`freedom.mp3`, `cinematic_violin_tribal.mp3`); `victory/allies.mp3` is a copy of "Battle Cry of the Brave". Playlists are discovered from the folders, so licensed tracks can be dropped in at any time.
- **Missions:** all missions derived from third-party mission packs (43 commercial-game and 30 free-pack) were removed. Replacements are original, authored by `tools/add_original_missions.py` (25 missions, ids `op_*`, diamond-prefixed names). Do not re-import third-party mission data.
- **Tools removed:** the mission importers and mesh/archive extractors for third-party games (including `fm_extract.py`, `sfs_*` and `fix_imported_missions.py`) and the scraped blueprint library (`tools/models/reference/`, `tools/models/overlay.py`).
- **Flight models:** the nine aircraft that used extracted values now use published top speeds, so they are 20-35% faster than before. Re-check `tools/validate_missions.py` after any further change.
- **Not changed:** earlier commits and published release zips still contain the removed files; `assets/ui/controller_outline.png` has no recorded source.

# SESSION 2026-10-15 (v7.25): realistic field shapes and sizes
- terrain.gdshader farmland lattice: field_cell 124 -> 190 (average ~190 m, ~4 ha); district sizes 0.65 / 1.0 /
  1.6 / 1.2 (was 0.5 / 1 / 2 / 1.1); domain warp 130 m at 0.0055 -> 30 m at 0.004 (straight hedges with the odd kink
  instead of curved bananas); strip districts 1.7 x 0.72 (was 2.0 x 0.55, ~2.4:1 instead of 3.6:1); hedge band
  thresholds scaled to keep the same width in metres. Textures / palette untouched.
- scatter.gd field_edge mirrors it exactly. FIELD_CELL was 62 while the shader used 124, so the 3D hedges sat on a
  half-size grid that missed the painted boundaries (stray green bars across fields); now both 190.

# SESSION 2026-10-15 (v7.24): wingmen take off with you; passing flights you can join (free flight)
- Runway take-off with the flight (ModeBase, every mode using the generic wingmen; not dogfight, which runs its
  own, nor bombers): on a ground start _wingmen_tick parks the wingmen on the same runway (_rw_spawn): split by
  runway_split(n) (1 -> 0 ahead/1 behind, 2-3 -> 1 ahead, 4-5 -> 2 ahead; at most RUNWAY_WINGMEN_MAX = 5 on the
  runway, any more join in the air as before). Ahead: starboard lane (lane = min(r*2+2, width/2 + 0.45r)),
  released at 5 s / 13 s, take off and PATROL over the field (leader null) until the player is up. Behind: queue
  at runway_slot_gap(r) = 2.6r + 12, alternating starboard lane / centreline, AIPilot.enabled = false while
  parked; each rolls once the aircraft ahead is gap + 45 along the runway (player: also moving > 8 u/s). Once the
  player is > 25 AGL everyone gets set_leader(player, Radio.formation_offset(k, n)) (stored as pilot meta
  "rw_off"); if he lands / aborts they go back to circling the field. Callsigns follow runway order (meta
  radio_idx). main._spawn_player_inner moves a ground start up the runway by runway_queue_length() (capped at 30%
  of the runway) so the queue behind has tarmac. Crew stay on the port side (PlayerGroundCrew), the queue uses
  starboard. Debug: --rw-test (player takes off by itself at 12 s; RWTEST lines every 2 s).
- PassingFlights (scripts/modes/passing_flights.gd, owned by FreeFlightMode; cfg "passing_flights", default on,
  --no-passing): one friendly flight at a time, first after 150-260 s, next 240-420 s after the last ends; only
  spawned with the player airborne. Kinds: "raid" (BomberFormation of 2 -> scaled 4, armed for a real
  WorldPopulator.raid_targets(enemy) target 16-160 km away (nearer half preferred), plus 2-4 close escorts) and "sweep" (4 fighters: FIGHTER
  leader on a route over the target, then patrol). Starts 6.5-9 km ahead of the player and 1.8-3.2 km to one side,
  already heading for the target. Within OFFER_RANGE 3.6 km the leader (own callsign list, ALLY_CALLS /
  AXIS_CALLS) asks; key 5 (action "radio_join", game_state.gd) accepts within 25 s. Joined: compass = the leader
  (target when close), HUD line, objective text; 3-6 enemy fighters scramble near the target (only when joined).
  Success = bombs gone (or over the target and 4.5 km past it) / sweep patrol cleared or 150 s -> PilotLog
  {"missions": 1, "points": 250}. Left behind (> 22 km for 60 s) or shot down: no credit. Unjoined flights are
  removed once 30 km away (or heading home > 12 km away). No offers while an Ops Room tasking is active.
  Debug: --passing-test (first flight at 4 s, 2.6 km ahead), --passing-kind=raid|sweep, --passing-auto.
- Steadier AI flying out of combat: AIPilot._steer_cruise replaces _steer for FIGHTER / WINGMAN in FORMATION,
  ROUTE, PATROL, CLIMB_OUT and RETURN (not during manoeuvres, combat states or ground-avoidance pull-ups). Flies
  by bank angle: want_bank = leader bank * 0.9 (formation, fading out 200-600 from the slot) + slot/heading
  correction (1.8 * flat heading error, capped 15 deg next to the slot rising to 60 deg 900 out; 30 deg minimum
  when the leader banks; 60 deg on routes), never over 65 deg; cmd_roll = 1.6 * bank error - 0.45 * roll rate
  (+-0.5); pitch = 3.2 * nose error + a little pull in a bank. The old _steer commanded roll RATE from the
  sideways error with no bank feedback: straight flight wobbled +-30 deg every second and a wingman catching up
  (r pinned at the 0.35 clamp) went into a slow continuous roll. --form-legacy flies the old way; --rw-test logs
  RWROLL (average roll rate of the runway wingmen) and a calm square-circuit leader.
- Runways: default runway_width 42 -> 56 (a pair abreast on the take-off roll; everything beside the runway is
  45+ out). Aged look in toon.gdshader: detail_mode 6 = concrete slabs 6.2 x 7.4 (per-slab tone, chipped edges,
  occasional tar patch) with grass growing in the joints and tufting out of them, cracks, spalling, oil, tyre
  rubber in the touchdown zones and mossy crumbling edges; detail 7 = worn paint (aged off-white, ragged edges and
  flaked holes by discard). Both read the strip size from the model scale (Airfield._add_box builds runway / paint boxes as unit boxes scaled to size; varying strip_wl). NOT an instance uniform: on the shared toon shader that made every toon instance reserve a slot and overflowed the buffer ("Too many instances using shader instance variables"). The
  old materials passed a "tex" option make_toon never read, so runways were flat grey. Markings are laid by
  _paint / _edge_stripes with a little random size / position / angle error (seeded by airfield name), and the
  edge stripes are uneven segments with gaps.
- Curved roads and railways: RoutePath.fillet_2d rounds every bend of 3-150 degrees into a tangent arc
  (radius by class, RoutePath.curve_radius: rail 900, motorway 600, trunk 450, primary 320, secondary 220,
  tertiary 160, else 140; never more than 48% of either leg, sampled every 5 deg). Applied where the lines are
  loaded. The OSM exports are TWO-POINT SEGMENTS (roads 348k, rails 72k), so RoutePath.chain_2d first joins
  pieces of the same kind wherever exactly two meet (0.5 m end match; junctions stay ends): roads -> ~100k lines
  (180k bends rounded, 8 deg arc steps), rails -> ~29k lines (32k bends). RoadMesh._load_roads stores the
  joined, rounded roads in the cache (user://roads_world_v3_*; the first launch after the update builds it).
  TransportNetwork._load_osm joins / rounds the rails once and keeps them in rail_chains; RailKit registers
  those (>= 200 m), the trains use TransportNetwork.rails (>= 450 m): ribbons, track, traffic and trains share
  the curves. WorldPopulator loads in two stages now (TransportNetwork with rivers / pylons / canals, then
  RoadMesh + RailKit) because both need the rail chains.
- Built and checked from the GitHub copy in the cloud (stock Godot 4.4.1 headless: import clean, tests 762/762);
  visual check and release on the PC.

# SESSION 2026-10-15 (v7.23): five new volumetric cloud types
- CloudField.Kind gains LENS(5) CASTLE(6) CIRROCU(7) CONGESTUS(8) STRATUS(9); ctype = kind in cloud_volume.gdshader
  (branch `ty > 4.5`). Formations from a second RNG (seed 1940, 34 formations + 30 lone congestus) added after the
  original layout, so the seed-1066 sky is unchanged. _kind_visible has a cover threshold per type. CIRROCU is
  skipped like CIRRUS in blocks_los / density_at and uses the thin_hi lighting (no sun march). sample_rain:
  congestus 0.5, stratus 0.35. Cumulus get flat_k (per-seed squash).
- debug_cloud_pos's "largest cloud" sentinel moved from 9 to 99 (9 is now STRATUS). --cloudview prints
  "CLOUDVIEW none visible" when nothing matches. Shots: --cloudview=5:0:9000:-300, 6:0:5000:-400,
  7:0:3000:-7000 --orbit=0,-35 (look up), 8:0:5000:-500, 9:0:4000:500 --weather=overcast. If none of that kind
  is visible yet (cover still blending in), debug_cloud_pos forces the nth one on.
- build/.gdignore added after v7.23: the debug screenshots in build/vis (300 MB) were being imported and packed
  into the exported game (v7.23 exe 786 MB vs 740 MB). build/ is gitignored, so this lives on this PC only.

# SESSION 2026-10-15 (v7.22): rain realism, windscreen rain, cloud pass-through
- RainFX (scripts/effects/rain_fx.gd, top_level): GPUParticles3D local_coords, velocity = (wind, -18 fall) - aircraft
  velocity, re-aimed each frame; emitter 45 m upstream of the camera; streak length ~ relative speed. Sound is a
  procedural loop (louder in cockpit). No wing spray: puffs (with drag) were left hanging behind the
  aircraft and the chase cam showed them as white blobs; tried twice, removed.
- RainOverlay (CanvasLayer 4): glass drops only when Aircraft._cockpit_view. _update_flow projects air velocity
  through the camera: focus = unproject(cp + dir*2000) (drops run away from it) or, when that is behind the camera,
  unproject(cp - dir*2000) (drops run toward it). Stick-slip drops with trail points.
- global shader uniform `wetness` (project.godot) darkens and glosses aircraft_pbr.
- CloudPassFX (scripts/effects/cloud_pass_fx.gd, child of WeatherManager): CloudField.density_at(p) -> veil
  (layer 3, max alpha 0.58), wisps in a 16-42 m ring around the flight path (never on it), camera_rig shake (group "camera_rig").
- Debug: --rain-now forces rain on at once.

# SESSION 2026-10-15 (v7.21): medal ceremony, visible damage, weather fronts, night smoke, newsreel news
- MedalCeremony (scripts/medal_ceremony.gd, layer 60): STYLE table per award id (ribbon stripes / diagonal, shape:
  cross_flory, cross_pattee, iron, star, leaf, clasp, disc). No swastikas: German awards show the year. PilotLog
  queues ids in career "unseen_awards" (migrated: existing awards get one ceremony). Shown by main._check_ceremony
  (on ground, stopped), over the results, and from the start menu after 5.5 s.
- AircraftDamageModel (scripts/effects/aircraft_damage_model.gd): parts wing_l/wing_r/tail/engine/cockpit.
  WeaponWorld sets Aircraft._pending_hit/_pending_dir before take_damage; flak/blast hits spread fragments on the
  side facing the source. Decals: per model_id cache of ~2500 sampled mesh vertices+normals (aircraft-local,
  propeller/canopy/gear excluded); hit -> nearest sample to the bullet ray, Decal +Y = vertex normal, normal_fade
  0.35, size scaled by span (ext.x/8, 1..2.2). Aileron lost at part >= 0.6 (75%). Handling hooks in
  Aircraft._update_rotation (roll/pitch authority, roll_bias, yaw_wander) and thrust/drag. Repair on reset_pose or
  self-repair to full health. Cockpit overlay (CanvasLayer 3): cracks + oil. Debug: --damage-test[=dmg].
- Weather fronts (weather_manager.gd): line moving along wind blow-to at 12-20 u/s; zones by signed distance
  (FRONT_AHEAD_FAR 42 km, NEAR 9 km x2.4 for warm, BEHIND -7 km, CLEAR -26 km). set_weather() sets base_weather and
  cancels a front; _blend_to() changes the look. CloudField._front_visibility uses cover_at() per cloud (1 s).
  Minimap symbols in hud._draw_front. Fronts off for training/dambuster/historical; 50% chance of one at start.
  Debug: --front-now (wind from 250, arriving in ~4 min), --no-fronts.
- fx_puff.gdshader: fog_disabled + own haze (haze_color = fog_light_color darkened at night, haze_density =
  env fog density), far smoke thins.
- NewsreelCard.headline_from_log(): news since last shown (career "news_seen"), awards > promotion > kills > ships.
- PilotLog.debug_run() also covers --logbook-shot/--dam-shot/--medal-shot/--damage-test (no logbook writes).

# SESSION 2026-10-13 (v7.18): remaining ElevenLabs credits spent on 970 radio takes
- Batches (all --premade, ~0.22 credits per character on this account): tools/make_voice_more.py (182),
  make_voice_bulk.py (338), make_voice_final.py (404), voice_last.csv (46). Texts live in the *_data.py files;
  tools/wire_voice_bulk.py and inline patches appended them to radio.gd TAKES / CHATTER_* and ops_room.gd tables
  (array index n-1 == file suffix _n; asserts guard the counts). Account left at 37460/37472 (no extension).
- Spotting: bandits/bombers_NN + _b.._f takes, plus _high/_high2/_low/_low2 chosen when the target is >300 m
  above/below (text gets " high"/" low"). Chatter 161 allies / 158 axis; ops headlines up to 11 per kind.

# SESSION 2026-10-13 (v7.17): fire glow, livelier Ops Room, voice takes, proper ground crew, map key steps
- Fires drew a red square: CityFires' OmniLight3D reached 300-400 units (FX.light_flash up to ~200) and the
  clustered lighting lit ground/trees inside hard straight edges. Lights are now short (CityFires 45+9*sz,
  attenuation 2, distance fade), light_flash reach capped at 110, BurningRuin 26*scale. The visible firelight is
  GroundGlow (scripts/effects/ground_glow.gd + shaders/fx_ground_glow.gdshader): a polar mesh draped over the
  terrain, additive, soft ragged rim, flicker; intensity follows FX.night_factor(). Halo billboard has proximity
  fade. fx_puff.gdshader: soft particles (depth_tex, soft_dist 4) on the soft puffs only.
  Debug: --fire-test[=dist] (bombs + city fire ahead every 9 s), --crew-test (a dispersal crew group ahead).
  Known, not fixed: dark smoke plumes read as blue beads at night from a distance (fog/sky tint on unshaded puffs).
- Ops Room: _band_lo/_band_hi range band (follow-up jobs 4-40 km), 45% follow-up after a success (25-45 s),
  otherwise next call 90-160 s; fail 120-180 s. _streak: +25%/step points (max x2), streak_1..3 calls.
  _ammo_check: out of guns/bombs/rockets on an attack job -> winchester_1, job scrubbed, nav to home field, no new
  jobs until rearmed (rearmed_1). _say_take keeps success/fail/hit text and clip index together (they were
  picked independently before). Twist calls use *_2 keys without minutes.
- Voice: tools/make_voice_variants.py -> assets/voice/voice_variants.csv (179 lines), plus 48 new ops lines in
  make_voice_ops.py; all generated (--premade). Radio.TAKES table + take(key, team, fmt) picks only recorded
  takes; spotting calls use bandits_NN / _b / _c; chatter extended to 20 (allies) / 17 (axis).
- CrewFigure (scripts/ground/crew_figure.gd): cached merged ArrayMesh per (team, pose, dress); poses STAND, HIPS,
  POINT, BEND, KNEEL, REACH, WALK_A/B, CARRY, WAVE; 4 dresses per side. PlayerGroundCrew uses them at x1.45 with a
  trolley accumulator + cable and rope-tied chocks; crew stand beside/behind the wing (user: never in front).
  GroundVehicle "crew" groups: 4 working figures + a walker + kit (crate, toolbox, cans, drum).
- HUD minimap 150 px by default; M: small -> 240 px -> full-screen chart (Bombsight._map_key) -> small.
  Modes without a Bombsight toggle small/large in hud.gd.

# SESSION 2026-10-12 (v7.1 / v7.2)
- v7.1: sky.gdshader Milky Way is a smooth faint band (0.03, no per-cell hash = no blocky squares); stars x0.75.
  Flak, tracers, searchlights, city fires unchanged from v7.0.
- v7.2: all mission time limits removed. Bombing/ground attack/defend `time_limit` vars and their checks are gone;
  BombingMode no longer reads the mission "time_limit" field (data/missions.json still carries the values, unused);
  ModeBase.fit_time_limit deleted. Ops Room: TASK_LIMIT, job t_left countdown, "Time's up" and twist deadline caps
  (300/360/420 s) removed; HUD countdown removed. Dialogue lines for twists still say "five/six/seven minutes" -
  re-voice or reword those (twist_convoy_hurry_1, twist_deadline_1, twist_shore_1) if wanted.

# SESSION 2026-10-12 (v7.0): fireworks night - more flak, lingering bursts, bigger formations, V-1/V-2 blitz, city fires
- Flak: _defences scales every site (88mm x2, Bofors/searchlights x1.5). AAGun 88mm: 3-round salvos (gap 0.32 s),
  range 3600, dmg 3.4/shell; Bofors bursts of 8. At night heavy guns fire a sound-located barrage (err x5) at unlit
  targets. The [aa-debug] print is gone.
- FX: flak_burst(pos, scale, quiet) - puffs live 18-30 s, drift with wind, bigger/longer flash and glowing fragments at
  night (FX.night_factor()). explosion() smoke 14-24 s plus a 28-42 s pall. STAR_POOL 96, puffs pool 7000.
  fx_puff.gdshader: uniform light_k dims smoke (shade >= 0.5) at night; flames/tracers stay bright.
- SkyWar (scripts/effects/sky_war.gd): scenery created by main.gd for every air mode except dambuster/training
  (--no-skywar). Distant salvos (2.5/min day, ~15/min night), light-flak tracer streams at night, 10 additive
  searchlight beams over the active zone, raids on towns 5-32 km away (free flight), ambient V-1 (200-380 s) and V-2
  (300-560 s) at London. Debug: --skywar=<mult> --raid-now --raid-city=<name> --v1-now --v2-now.
- V2Rocket (scripts/modes/v2_rocket.gd): visible boost 62 s with a heavy white trail (FX.pillars pool) and motor
  flare, hidden 70 s, 5 s near-vertical fall, 44-size blast, explode_at(70, 400), CityFires strength 3.
- CityFires (scripts/effects/city_fires.gd): ignite(pos, strength) in built-up areas (cities from loc, radius
  (90+85*size)*(1.6+0.9*size)); merges within 220 m, pillar when power >= 2.5, a city pall once 3+ fires; 5-9 min life,
  max 30 fires. Hooked from WeaponWorld.explode_at (radius >= 12), FlyingBomb impact, V-2, SkyWar raids.
- BomberFormation.size_mult = 2.0 (scaled(n), max 18) applied in spawn(); slot_offset is now vics of three in a
  stacked combat box (first three slots unchanged). SortieManager raids scaled (max 12, one take-off at a time).
- Note: the white ball under the aircraft in night chase shots is a small cumulus below (also in v6.9).
- vis_shots: blitz, flakn, flakd, v2.

# SESSION 2026-10-12 (v6.9): Ops Room campaign - single-hit jobs, rendezvous, escorts, intel, V-1s, logbook, chart
- Single hit completes a job: Weapons.player_hit/player_kill signals (weapon_world.gd), emitted by GroundTarget and
  Aircraft when WeaponWorld.is_player_source(source). OpsRoom._hits_target checks info["hit"] nodes (and ancestors),
  hit_area radius for airfield/intruder, any bomber for intercept/cover.
- Rendezvous (_maybe_rv, 40%, --ops-rv forces): 2-3 friendly fighters patrol an RV 28-40% of the way out; join within
  2.5 km -> WINGMAN in FORMATION on the player; released with RTB at job end. New kinds: escort (bombers spawn when
  player within 7 km of RV, interceptors at 55% of route, bomb at target), intruder (night, lit airfield, searchlights).
- Night (light_level < 0.32) drops recce/rescue/escort, adds intruder. Fog scrub 8% by day. Scramble when parked 35 s.
- Twists (--ops-twist forces) per kind in _twist; bounce chance from air_threat.
- Intel: _intel_scan reports enemy sites passed below 2500 m within 2.6 km; queued reports used 60% for next jobs.
- Pressure: supply/air_threat/v1_threat move with success/failure; _pressure_flak adds flak; Allies get FlyingBomb
  (scripts/modes/flying_bomb.gd) launched at London, interval max(320-70*threat, 90) s.
- PilotLog (scripts/pilot_log.gd): user://pilot_log.cfg, per-side points/ranks/awards; logbook overlay on J.
- Chart: Bombsight.attach with chart_only=true for aircraft with <8 bombs (main.gd), M toggles; pins come only from
  game_mode.map_pins() (announced objective, RV, home for recce, live V-1s).
- Voice: tools/make_voice_ops.py -> assets/voice/voice_ops.csv (186 lines) -> assets/voice/ops/<allies|axis>/<key>.mp3
  via generate_voices_elevenlabs.py --premade. _clip(key) falls back to text-only when a file is missing.
- Tests: tools/ops_test.sh 13/13 (typhoon Allies, ju88 Axis); live forced runs build/v69_live.sh.

# SESSION 2026-10-12 (v6.8): dynamic free flight - Ops Room taskings
- **Free Flight > "Ops Room taskings"** (menu checkbox on the START POINT page, on by default; cfg `taskings`,
  `tasking_interval`, debug `--taskings`). `scripts/modes/ops_room.gd` (`OpsRoom`, owned by FreeFlightMode):
  every 10 minutes Sector Control (RAF) / Jafü 2 (Luftwaffe) radios a tasking against a real place - opener,
  brief and "Steer 135, 42 km" - with a waypoint on the compass (FreeFlightMode.nav_point forwards to it), a
  pulsing objective diamond on the minimap or an edge arrow with the distance when it is off the chart (hud.gd,
  works for every mode's nav_point), and an OPS ROOM panel (job, bearing/distance, progress, time left, tally).
- **11 kinds**, weighted by aircraft role (bomber / fighter-bomber / fighter): strike (real WorldPopulator
  targets), airfield (5 kills inside 2.2 km), road convoy, train, shipping (real naval convoy routes), E-boats/MTBs
  out of an enemy port, intercept (bomber raid + escort on one of our towns: fail if they reach it, bombs fall),
  cover (dive bombers on one of our convoys), sweep (enemy fighters patrolling near their airfield), air-sea
  rescue (`scripts/modes/dinghy.gd`: dinghy, dye marker, orange smoke; circle low 40 s; sometimes bandits come
  for him), photo recce (low wings-level pass, then land with the film). Several briefing lines per kind, side
  aware; places named from the nearest town ("12 km north-east of Calais", "... out at sea").
- Rules: one tasking at a time; a finished one brings the next call forward (half the interval); a tasking
  older than 15 min at the next call is cancelled and replaced; time allowed scales with distance (min 25 min).
  Targets prefer 12-90 km, else the nearest up to 180 km (from Tangmere France is ~120-170 km away).
- `_held_by()`: GroundKit.side_at puts Dover/Folkestone on the Axis side of its coastline approximation, so
  towns are checked against the nearest airfield's owner too; enemy airfields must be on the enemy side of the
  front (the airfield list mixes eras: no RAF Brussels for a 1940 Luftwaffe pilot).
- Soak test: `tools/ops_test.sh <aircraft> <side>` (`--ops-test` cycles all kinds, auto-completing each; results
  in build/ops_events.log - stdout redirected to a file is block-buffered on Windows and loses its tail).
  Passed: typhoon/Allies, ju88/Axis, spitfire/Allies - 11/11 each. Debug: --ops-first, --ops-interval,
  --ops-kind, --ops-auto, --ops-verbose.
- Gotcha for automation: a PowerShell `Stop-Process` filter on "*ops_test*" also matches the PowerShell running
  it (its own -Command contains the text) and kills it before the next statement.

# SESSION 2026-10-12 (v6.7): world visual pass - the sea fixed at last, moonlit water, wakes, plumes, flood, rays
- **ROOT CAUSE of the long-open "white / flat sea" (and the washed-out airfields): height fog.** time_of_day.gd set
  `fog_height = 120, fog_height_density = 0.006`. Godot's height fog is NOT distance based - it adds
  `1 - exp((y - fog_height) * density)` of fog colour to every pixel below fog_height however close it is: 51% at
  sea level, ~25% at a 36 m airfield. Found by instrumenting, not tuning: the water painted pure red came out pink,
  hiding the water plane showed the seabed equally pale, disabling volumetric fog and exponential density changed
  nothing. Height fog is now off; distance haze (density + aerial perspective) is unchanged.
  Debug switches kept: env `WW2_NO_FOG=1`, `WW2_NO_VFOG=1`, `WW2_WATER_DEBUG=1|2|3|4` (depth-diff colours / forced
  opaque / hide the sea / plain opaque material).
- **Sea (shaders/water.gdshader)**: Channel grey-green body colour, Fresnel sky reflection from new shader globals
  `sky_top` / `sky_horizon` (TimeOfDay sets them), `ambient_light_disabled` (the engine sky ambient + radiance were
  stacking on the shader's own reflection), view-space normals (the old shader mixed a world-space normal into
  view-space NORMAL), irregular swell envelope + mid-scale chop, near ripples, soft-edged sun/moon glints plus a
  broad sheen that draws the glitter path, wind-lane foam streaks and small down-wind whitecaps (the round fbm
  blobs read as ice floes), lacy shallows/surf, smooth depth tint (hard toon bands drew straight steps at seabed
  LOD seams), drifting cloud shadows matching terrain.gdshader.
- **Moon**: rides lower (~30 deg at midnight) so it lays a long path across the water; reservoirs use the water
  shader in `lake_mode` (calm, no depth/foam) so the moon path shows on them too; Chastise days (d5-d7) are now
  flown at night.
- **Ship wakes**: WaterPlane feeds the 4 nearest moving ships to globals `wake_0..3` (xz, forward angle, length);
  the shader draws a churned track, Kelvin arms and a bow wave.
- **Bomb plumes**: `FX.water_plume()` - column, crown, base surge, mist, lingering foam slick - for radius >= 6
  explosions in the sea or a registered reservoir (Upkeep detonations now plume at the reservoir surface).
- **Dam breach**: DamFlood uses shaders/flood.gdshader (muddy water, whitewater below the gap and at the surge
  front, flow streaks, ragged leading edge) and throws spray/mist at the gap and along the front for 2 minutes.
- **Light**: screen-space god rays (shaders/god_rays.gdshader via SunGlare) with the sun in or near view,
  stronger with a low sun; volumetric haze thickens at dawn/dusk (high preset).
- **Airfields**: wind sock now streams with the real wind (scripts/ground/wind_sock.gd); on a ground start the
  player gets a ground crew, trolley-acc and chocks that clear away when the throttle opens
  (scripts/ground/player_ground_crew.gd). (Crews, bowsers, tugs, bomb carts, fire tender already existed.)
- **FX were invisible over Germany**: FXParticles (all puffs: smoke, fire, flak, spray) and the tracer MultiMesh had
  a custom_aabb of +-100 km round the origin, so everything past x ~ 100 km (the dams are at x ~ 573 km) was culled.
  Now +-2000 km. The sea (and lakes) draw first among transparents (`render_priority = -100`) - the huge
  depth-less sea plane was sorting on top of splashes and spray.
- Terrain procedural ponds are rarer and darker (they glowed like snow at dusk); Scatter.in_lake threshold kept in
  step (0.78).
- HUD: VSI / THR text moved below the dials (it collided with the needles).
- Known: dam days spend up to ~90-120 s on the loading screen - the terrain streamer keeps 2-6 chunks in flight
  near the dams and only settles late (pre-existing; the 120 s cap in main.gd ends it).
- Visual check: `tools/vis_shots.sh <tag>` (SHOTS="sea dusk night coast field rays cloud dam", TMO, DAMF) renders
  real in-game shots with the RTX build into build/vis/.

# SESSION 2026-10-12 (v6.6): hands-off level flight for every aircraft, Dam Busters rings you can see
- **Why every aircraft drifted up or down:** the auto-trim aimed for the ideal-wing 1 g angle of attack, but the
  strip wing (washout, elliptical loading) only delivered ~92% of the weight there, so every hands-off aircraft
  sagged into a dive; and a "1 g" trim is neutrally stable anyway (any climb/sink just carried on). Measured
  with a new headless harness, not guessed: Lancaster released level at 300 m hit the sea in 25 s at any throttle.
- **Fix (aircraft.gd `_update_trim`, all 29 types):** the trim learns the wing's real AoA offset (`_trim_corr`),
  and with the stick released the player's aircraft is speed-stable like a real trimmed aeroplane: it holds
  `trim_speed` (captured when the stick is let go) and the THROTTLE sets the climb/sink rate, so there is one
  throttle at which it stays at a fixed height. Light sink-rate damping tames the phugoid. With the assist on
  (R / LB) it is an altitude hold instead (captures the height on release, holds it within ~3 m even after a
  6 deg disturbance, adds the extra lift a level banked turn needs). AI pilots keep their own control; they
  only get the trim correction. Throttle keys: a tap is now a 1% step; held it runs after 0.25 s.
- **HUD:** VSI to 0.1 m/s, `LEVEL` when within 0.3 m/s, `ALT HOLD` while the assist holds height, `THR nn%`.
- **Dam Busters day 1 rings:** they all faced north-south while the course runs east (seen edge-on), were thin,
  55% transparent and fogged out at dusk. Now: thick, fog-free signal-orange rings facing along the course,
  centred at 20 m on the 60 ft band, a halo that pulses on the next ring, two 900 m light posts per ring visible
  from km away, a buoy, the next-but-one ring in yellow, passed rings flash green and fade; "TOO HIGH" message
  when you pass over a ring above 40 m. Range marker (day 3) is a wide fog-free band with a light post.
  Before/after render: `screenshots/dam_rings_before_after.png`.
- **Spotlight altimeter** (all Dam Busters days, below 120 m): two lamp spots on the water that meet at 60 ft
  and turn green, as on 617 Squadron's Lancasters.
- Training rings (t_basic) are thicker and fog-free too.
- Harness: `tools/fm_sim.gd` (+ .tscn): `godot --headless --path . tools/fm_sim.tscn -- [--only=<id>] [--assist]
  [--kick] [--secs=N] [--alt=M] [--thr=a,b,c]` prints the hands-off height range for each type/throttle.
# SESSION 2026-10-10 (v6.1): menus rebuilt page-by-page, music managers, adjustable view distance
- **Menus no longer need scrolling.** The main menu is four pages (SORTIE / START POINT / CONDITIONS /
  BRIEFING) behind a visible nav row with TAKE OFF plus Campaign/Options/Quit always on screen; Settings is
  six tabs (VIDEO / RENDER / AUDIO / MUSIC / GAMEPLAY / CONTROLS) with Apply + Back always visible, and the
  old 18-row Graphics page was split into VIDEO + RENDER because it cannot fit 720p. Verified from captures,
  not by reading: main menu page, the settings shell, the controls bindings table and the music page all fit
  with no clipping and no scrollbar.
- **Music managers** (Settings > MUSIC): separate MENU MUSIC and IN-GAME MUSIC track lists driving the
  existing `menu_music.gd` / `game_music.gd` (no third music system). Import copies the file into
  `user://music/<manager>/` (survives a read-only install), Delete removes it from the playlist and only
  deletes the file when it is a user import - shipped tracks are never deleted from disk. Playlists and
  selection persist in the existing `settings.cfg` under a new `[music]` section. Note: Import/Delete/Play is
  ONE control row acting on the selected manager, not a duplicated row per manager.
- **Adjustable view distance** (owner request): numpad `+`/`-` scale the chase-view distance (0.35x - 3.0x,
  eased, multiplying whatever the rig already computes) and, in the cockpit, zoom the FOV (35 - 95 deg - the
  eye is inside the aircraft so "distance" is a zoom there). Numpad Enter resets the current view; `=` / `-` /
  Enter also work. New input actions live in `project.godot [input]` with a runtime InputMap fallback, and the
  value is echoed through the existing HUD toast helper.
- **Screenshot hooks** (added because the engine is only runnable by the parent): `WW2_MENU_PAGE=`,
  `WW2_SETTINGS_PAGE=`, and `--ui-shot=` now awaits `RenderingServer.frame_post_draw` - grabbing the viewport
  image straight from a Timer returns a black frame, which is what made the first menu captures look empty.
- Gate: `TESTS OK (734 passed, 0 failed)`.
# SESSION 2026-10-10 (after v6.0): world realism - materials, terrain, airfield, sky
- **The whole world left the toon look behind.** ~100 procedural kit scripts all build through
  `ToonUtil.make_toon()`, so re-pointing that one factory at the new realistic system upgraded every building,
  road, prop and vehicle with **no kit-script edits**: `shaders/world_pbr.gdshader` (triplanar - the world
  meshes have no usable UVs - with real roughness/metallic, settled dust, rain runs, cavity darkening and
  screen-space relief) plus 20 procedurally generated surface textures from `tools/make_world_textures.py`
  (brick, render, stone, concrete, roof tile, slate, timber, 3 metals, asphalt, gravel, grass, foliage,
  thatch, sand, snow) with a manifest carrying measured means and per-surface roughness/metallic/scale.
  The inverted-hull outline is now **opt-in** and no world surface uses it.
- **A landmine worth remembering:** the kits pass the OLD toon detail codes (1 building, 2 asphalt, 3 foliage,
  4 grass, 5 aircraft) while the new shader numbers its modes differently, so every surface was initially
  mis-graded - `detail 5` (aircraft) became `metal` at 0.75 metallic, i.e. chrome aeroplanes. `ToonUtil`
  now translates old->new in `remap_detail()`.
- **Terrain** (`shaders/terrain.gdshader`) rewritten: continuous mixes of pasture, rough grazing, arable in
  several crop states, heath, chalk/limestone, sand, marsh and rock, blended by altitude + slope + a district
  noise + within-field noise, with headlands as soft darkening rather than colour steps. No toon ramp.
- **Airfield** (owner asked twice): the terrain tint no longer mixes in a fixed pale green (that constant
  lifted the aerodrome out of the landscape); it darkens the surrounding field colour, the feather widened
  230 -> 330 m, and inside the perimeter the field patchwork is suppressed entirely in favour of one muddy
  mown grass with a slow mottle. `airfield.gd`'s own dirt/apron/asphalt materials were also pale
  (0.62/0.58/0.43 dirt!) and are now dull earth tones with real textures.
- **Sky** (`shaders/sky.gdshader`) rewritten: elevation-driven continuous gradient, soft sun disc, broad
  forward-scatter at low sun, night stars + Milky Way + moon halo, horizon haze consistent with the fog.
- **Lighting:** ACES tonemapping, sky reflections enabled for specular (they were disabled), SSAO 0.35 ->
  0.62, subtler grade. `scripts/time_of_day.gd`.
- **`Ocean3D Lite` (MIT, (c) Justin Schroeder) vendored** at `addons/ocean3d_lite/` and credited in
  ATTRIBUTION.md; its Gerstner approach and spectral-LOD idea informed the sea.
- **KNOWN OPEN - the sea still renders white/flat.** Ruled OUT by experiment, not opinion: the albedo
  (painted solid red - the dash grid SURVIVED, so it was never in the colour), the foam (switching it off
  left the grid), the glitter lobe (tightened - still washed white), and wave-field periodicity (replaced
  the trains with an analytic normal field, which reduced but did not remove the grid). The remaining
  suspects are the fog/aerial perspective washing a surface that runs to the horizon, and the custom
  `light()` accumulation in `shaders/water.gdshader`. **Instrument it before tuning it further.**
- Gate: `TESTS OK (734 passed, 0 failed)`.

# SESSION 2026-10-10 (v6.0): 1:1 Blender aircraft for all 25 types + the toon look removed
- **Every aircraft is now a Blender-authored 1:1 model.** The 24 procedural airframes plus the C-47 were
  replaced by high-poly geometry generated from published dimensions in `tools/models/data/<id>.py` (25 files:
  23 by six parallel builders, Spitfire + the pipeline by hand, C-47 last). Poly counts: 22,964 (Spitfire) to
  50,436 (Ju 88); the files carry a **numeric accuracy gate** that fails any model more than 2% off its
  published length/span - every one passes, e.g. `ACCURACY spitfire length 9.12/9.12m (+0.0%) span 11.22/11.23m
  (-0.1%) PASS`. Rebuild with `blender --background --python tools/models/build_all.py -- <id> [<id> ...]`.
- **The toon aesthetic is gone from the aircraft** (owner: "get rid of the toon aesthetic and aim for more real
  life assets"). `shaders/aircraft_pbr.gdshader` paints the airframes as real painted metal - triplanar
  procedural camouflage (six schemes from `tools/make_aircraft_camo.py`), painted underside, panel lines,
  grime, paint chipping, micro-relief - and the inverted-hull outline pass is **not** used on aircraft any
  more. Metal, glass, tyres and national markings are `StandardMaterial3D`. `scripts/models/gltf_models.gd`
  instantiates the `.glb`, paints it by node name, and falls back to the old procedural builders when an asset
  is missing, so the game still runs if an aircraft is unfinished.
- **`ToonUtil`/kit fixes found by the model builders:** `kit.surface()` honours the `twist` station element
  (washout), takes an optional 6th element = leading-edge offset (so a planform can curve BOTH edges), the
  propeller blades now carry pitch twist and fan correctly around the prop shaft, `markings()` names the
  Luftwaffe fuselage crosses by colour (they were being named by a float and fell through to grey), and
  `gear_leg` grew a wheel hub.
- **Spitfire wing, corrected:** it was a single ellipse, which curves the leading edge from the root and makes
  the wing read as a leaf. The real planform is two semi-ellipses on a common major axis at the spar (31.5% of
  root chord), so the LE is nearly straight and the TE curves hard; thickness now grades 13% -> 6% with -2.5
  deg tip washout.
- **Decals, corrected:** `kit.disc()` built "horizontal" markings in the X-Z plane, so wing roundels stood
  edge-on inside the wing. `kit.skin_disc()` places them in the right plane and drapes every vertex onto the
  actual skin (sampled from the wing/fuselage mesh), so markings follow dihedral, camber and curvature.
- **Multi-engine props:** `aircraft.gd` used to spin only the node literally named `Propeller`, so a Lancaster,
  Ju 52, Fw 200 or B-25 flew with dead engines. It now gathers every `Propeller*` group and swaps each one's
  blades/disc.
- **Lighting (first step of the world pass):** ACES tonemapping (was Linear/Filmic), sky reflections enabled
  for specular (they were disabled), SSAO 0.35 -> 0.62 now that surfaces are not flat-shaded, subtler colour
  grade, haze in the sky. `scripts/time_of_day.gd`.
- Gate: `--import` then `scenes/tests.tscn` -> `TESTS OK (734 passed, 0 failed)`. Exported v6.0.
- **Still to do (next session):** the world realism pass (`PROMPT-world-realism.md`,
  `PROGRAM-STATUS-world.md`) - world surface textures, `world_pbr.gdshader`, terrain, vegetation, water, FX.

# SESSION 2026-10-10 (v5.4): gunnery eased back a notch ("a bit easier to hit enemies")
- After flying v5.3 the owner found it too hard, so the two `weapon_system.gd` constants moved part-way back: `AIM_ASSIST_DEG` 2.5 -> **5.0** (2.5 deg had overshot; 9 deg was the "too easy" original) and `PLAYER_SPREAD_K` 1.0 -> **0.75** (the player's cone is 0.009 rad against the AI's 0.012). Ladder kept in the comment above the constants: 0.5 / 9 deg = too easy, 1.0 / 2.5 deg = too hard, 0.75 / 5 deg = current. Next time this needs tweaking, change the two constants only - they are the whole player gunnery difficulty knob.

# SESSION 2026-10-10 (later still): v5.3 - player gunnery tuned down (too easy)
- **The player's guns were far too forgiving.** Two stacked bonuses in `weapon_system.gd` `_on_fire`: the player's cone was HALF the AI's (`spread *= 0.5`, i.e. 0.006 rad vs `gun_spread` 0.012) and `_assisted_aim` re-aimed the guns onto the exact intercept point for anything inside a **9 deg** cone. Both are now tunable constants at the top of `weapon_system.gd`: `PLAYER_SPREAD_K = 1.0` (the player's cone now matches the AI's) and `AIM_ASSIST_DEG = 2.5` (9 -> 2.5 deg, so the assist corrects small aiming errors instead of being a 47 m crutch at 300 m). The assist still computes the same lead, and every gun cone is still driven by `AircraftStats.gun_spread` (0.012 rad default; nothing in `data/aircraft/*.tres` overrides it).
- Version bumped to 5.3. **Not released** - owner tests the local `build/` exe first.

# SESSION 2026-10-10 (later): v5.2 - fire no longer renders as hard red squares
- **The "red squares" on the ground were the FIRE.** `shaders/fx_puff.gdshader` softened a puff only when `v_col.a < 0.85`, but every flame / ember / fireball puff is *spawned* at alpha 1.0 (`FXEmitter._emit` for FIRE, BLAZE, TRAIL_FIRE and the PILLAR flames; `FX.explosion`'s fireballs and embers; the burning-vehicle `_fire_flash`), so they all took the crisp path and drew as hard-edged opaque low-poly blobs - at range a cluster of those reads as solid red-orange squares sitting on the ground. The softening is now forced for flames too: `float soft_amt = max(1.0 - step(0.5, v_shade), 1.0 - smoothstep(0.85, 0.99, v_col.a));` - everything with `shade < 0.5` softens at any opacity, while debris (shade = 1, opaque) keeps its crisp low-poly look and smoke (already spawned translucent) is unchanged. Affects `FX.fire` / `blaze` / crash fires, explosion fireballs and embers.
- **Diagnosis method** (the owner had to point at it twice): scan the screenshot for red pixels, label the components, then print each blob as ASCII art (1 char per 2-4 px) - the fire patch resolved as a cluster of hard-edged solid blocks with smoke (soft) around them. Same technique as the v5.1 prop-strobe fix. Also worth knowing: town roofs are themselves red/orange, so a "red patch from the air" needs the shape checked, not just the hue.
- Version bumped to 5.2. **Not released** - the owner tests the local `build/` exe first.

# SESSION 2026-10-10: v5.1 look pass - prop strobe fix (the "shaking plane"), darker buildings, green trees, dull fields
- **The cockpit "shaking" was the PROPELLER, not the airframe.** Measured from cockpit-view recordings (`--write-movie --fixed-fps 60`, frames differenced at 640x360): across consecutive frames the airframe (nose cowl, spinner, canopy frame) is static to within ~2/255 grey levels and 0 pixels jump by >25, while the prop region changes by 13-17 mean / 40+ peak with ~700 pixels per frame above 25 - i.e. the only thing moving in the cockpit view is the prop. Cause: at cruise `rate = lerpf(9, 70, throttle)` = ~52 rad/s, so one frame advances the blades ~49 deg against a 120 deg three-blade pattern - they land on an unrelated angle every frame and strobe (worse under DLSS at 0.667 render scale, where the blades are sub-pixel). Frame-rate/airframe data at the time: `Vector3(16777217,0,0).x == 16777216` (float32, no double precision) and the player sat at world z ~ -133 km, so large-world jitter was checked and RULED OUT (the airframe is steady). Fix: `AircraftModels.prop_blur(rate, delta)` - past `PROP_STEP_LIMIT` (30 deg of spin in one frame) the discrete blades (and their bright tips) are hidden and the translucent `PropDisc` blur carries the prop; frame-rate aware, so a prop still shows blades at high frame rates. Blade pivots now hang off a node named `Blades` in both builders (`spitfire_model.gd`, `plane_builder.gd`), `PropSpinner` gets the same swap for secondary props, and the disc alpha went 0.22 -> 0.30 so the blur reads.
- **Buildings darker:** `shaders/toon.gdshader` `BUILDING_DARKEN = 0.74`, applied through `flat_shade` so it hits the flat-shaded building pass (towns/cities) and nothing else.
- **No red trees:** `Scatter.tree_variant` 4 (was "autumn oak", ochre/russet) and 5 (was "copper beech", red-brown) are now green species, so every crown is a shade of green.
- **Duller fields:** `shaders/terrain.gdshader` palette darkened/desaturated (grass_a/b, field_brown, field_wheat, meadow, rape, upland, the flower-meadow speckle, the fallow pale tone and the poppy flecks) plus a lowland grade - `mix(col, mix(col, vec3(luma), 0.22) * 0.87, lowland * (1 - urban))` - so farmland reads muted while towns, heath and upland are untouched.
- Gate: `--import` then `scenes/tests.tscn` -> `TESTS OK (734 passed, 0 failed)`. Exported v5.1 (`gh release create v5.1`).

# SESSION 2026-10-09: 1940s Cities, Towns, Rivers, Docks & Industry (program, Phases 0-6)
Program brief `PROMPT-cities-towns-1940s.md`, board `PROGRAM-STATUS.md`. Phase code is COMPLETE and statically checked; **per-phase engine runs were stopped** - the `--import`, the `scenes/tests.tscn` run and the `--no-window --shot` renders happen ONCE in a final consolidated pass (see `PROGRAM-STATUS.md` "Verification policy"), so every phase's engine acceptance item is DEFERRED.
- **Real rivers:** new `scripts/ground/river_mesh.gd` (`class_name RiverMesh`) draws `data/osm/rivers.json` as terrain-hugging water ribbons (miter normals copied from `RoadMesh`), streamed per tile; new `shaders/river.gdshader` (flow scroll, silt banks). `tools/carve_rivers.py` lowers the DEM along each course (backup in `tools/cache/`) with a drape fallback; `RiverMesh.ensure_loaded()` sets the terrain shader global `real_rivers` so the painted rivers retire; scatter keeps houses/trees/hedges/farms off the channel (`near_river`/`prepare_block`). River data is the OpenStreetMap waterway network (Overpass-tiled; a Geofabrik regional extract is the offline alternative - OSM/ODbL, see ATTRIBUTION.md).
- **Street-driven towns:** `Scatter.make_town()` rewritten via new `Scatter.town_layout()` - terraces run along the real street tangents (`RoadMesh.routes_in_rect()`), break at junctions, yaw from the local street; districts by radius/size; civic core (market square, town hall, station) for size>=3; waterfront rows face the river/coast and thin to a quay edge. `house_mesh(8)=cinema`, `house_mesh(9)=station front` (0-7 unchanged). Debug `--city-test`.
- **Piers & docks:** 5 typed builders in `scripts/world_features.gd` (`build_pleasure_pier`/`build_dock_basin`/`build_drydock_shipyard`/`build_river_quay`/`build_fishing_harbour`); `world_populator.gd` `_register_docks()` reads `data/docks_1940.json` (18 piers + 34 docks = 52 sites) and snaps each to the nearest shoreline, with new `dock_basin`/`drydock` `GroundStructure` kinds. Debug `--dock-test`.
- **Industry v2:** new `scripts/ground/industry_kit.gd` (`class_name IndustryKit`, one builder per kind, 12/12) driven by `data/industry_1940.json` (73 in-bounds sites); `_register_industry()` orients each along the nearest rail/river and draws a siding stub (`build_siding`); destructible gasworks/colliery/goods_yard/engine_shed kinds added to `GroundStructure`. Debug `--industry-test`.
- **Landmarks & skylines:** all 42 `data/landmarks_1940.json` ids wired to `features[type=landmark]` rows (28 kept -> 70 total, matching the 70 `Landmarks.build()` cases); `_city_landmarks()` resolves `cities[].landmark` names to ids and places the ones without a features row; harbour landmarks pinned to y=0. Debug `--landmark-test`.
- **Tests (Phase 6.1):** `tools/tests.gd` gains `_test_data_files`, `_test_river_data`, `_test_landmarks_all`, `_test_house_variants` and `_test_industry_kinds` (deterministic, `_check` style; baseline was `TESTS OK (617 passed, 0 failed)`). **Perf (6.2)** and **docs (6.3)** done - see the PERF NOTES section in `PROGRAM-STATUS.md`. **Export, `project.godot` version bump and `gh release` are NOT done** - per the owner rule they wait for the single final consolidated engine pass.

# SESSION 2026-10-07: real Bf 110/Do 17/Blenheim flight models, voice complete, --shot fixed, minimap icons, bomber sink, visual + pacing pass
- **Flight models:** every aircraft's stats are derived by `tools/apply_flight_models.py` from published figures only (sources in the script header); nothing is read from any game's files. `data/aircraft/*.tres` re-derived on 2026-10-22.
- **Voice is COMPLETE:** `assets/voice/voice_generic.csv` (68 lines) and `voice_places.csv` (146 lines) all have generated MP3s; `Radio._load_story` loads voice_story + voice_generic + voice_places. The earlier "NOT generated yet" note was WRONG.
- **`--shot=` / `--tour=` pipeline FIXED:** the upscaler (and frame generation) is forced OFF for capture runs (`game_state.gd _debug_upscaler_args`, `main.gd _parse_debug_args`), with null/empty-image guards and absolute-path logging on save. Previously DLSS-G `_upscale_internal` aborted the save in `--no-window` runs.
- **Minimap plane silhouettes** (`HUD._plane_icon`) CONFIRMED working and visible in-game.
- **AI bomber altitude sink reduced:** was a steady ~3.4 m/s unbounded descent; now decelerates to near-level with a small steady-state offset. PARTIAL fix - auto-trim holds 1 g and therefore preserves the existing flight-path angle, so an attitude-only AI command cannot fully recover the sink.
- **Visual pass:** terrain palette desaturated toward olive + `map_amount` 0.88 -> 0.72 (kills noon neon), lighter dark-brown field end-member, muted grey sea + a second large-scale fbm to break tiling, softer foam, softer cloud shading, wider/warmer sun glow, deeper dusk orange (`TimeOfDay` 18.4 key), softer coastline sand fade.
- **Pacing:** dogfight wave spawn 6-9 km -> 4.5-7 km; free-flight first skirmish 150-240 s -> 90-150 s.
- **DECISION (do not "fix"):** the synthetic fallback roads for Kent (tile 21) + Pas-de-Calais (tile 16) (those OSM tiles never downloaded) and the synthetic/missing rails, coast, woods and towns for the expanded NE map area are ACCEPTED and intentional. Not a bug and not a TODO - only re-run the fetchers if a real-data look is wanted. See `tools/README.md` and `SPEC.md`.

# SESSION 2026-10-06 (later): mission validation, spawns, events, wingmen, bomber speed, minimap planes, audio options
- **`tools/validate_missions.py`** checks every mission synthetically (no game launch): references, aircraft/side, airfield ownership by date, land/sea placement, round-trip time vs time limit, events. Currently 0 errors. Run it after any mission/location change. `tools/land.py` = heightmap helpers (land test, snap to land, land-safe convoy path, `time_limit`).
- **DO NOT run `tools/build_locations.py`** any more: it regenerates `data/locations.json` from scratch and drops the hand-added D-Day / Dunkirk / Blitz / forward-airfield (`af_*`) entries. Edit `data/locations.json` in place.
- Missions may carry `sides[].spawn` {lat, lon, heading, alt} = airborne start at that point (start_airfield is then "home"); `HistoricalMissions.configure` sets `GameState.spawn_point`. Invented "<Town> Airstrip" fields were converted to spawns. `wingmen` (0-3) = flight size; time limits are distance based.
- Scripted events (`HistoricalMissions._check_events`): nothing before 45 s airborne, max one air event per 75 s, groups behind / on top of the player are brought in ahead; the aircraft's own side decides who flies it. Debug `--event-debug`, `--spawn-debug`.
- Wingmen: `ModeBase.wingmen_wanted` + `_wingmen_tick` (spawn once the player is airborne; not for bomber pilots; the dogfight mode keeps its own). Planner has a Wingmen option, campaign sets 2 for fighter pilots. Debug `--wingmen=N --wingmen-test`.
- AI bombers: lower top speed (AIFactory, all spawn routes) + throttle governor (`AIPilot.BOMBER_CRUISE_CAP`), slow start ramp in EscortMode; they still sink ~3 m/s (pre-existing altitude hold). Debug `--escort-debug`.
- Minimap shows plane silhouettes (`HUD._plane_icon`) - CONFIRMED on screen and visible in-game (2026-10-07).
- Options > Audio sliders, version label (project.godot application/config/version - bump every release), `--audio-test`, `--menu-test`, `--mem-test`, `--loadprof`.

# SESSION 2026-10-06: ammo, ammo warnings, music ducking
- Gun ammo x3 on every aircraft (`data/aircraft/*.tres`). `WeaponSystem._check_ammo`: spoken + banner warning at 25 % and at empty (clips `assets/voice/mode/<side>/ammo_low_N|ammo_out_N`, generated with `--premade` British "RAF pilot"/"Luftwaffe pilot" voices because the ElevenLabs monthly voice add/edit quota (54) was used up; regenerate with Voice Design after the quota resets if wanted). Debug: `--ammo-test`.
- `GameMusic` ducks to 30 % while `Radio.voice_active()` (a recorded call/briefing is playing): fast down, slow back up.
- Compass objective marker: `ModeBase.nav_point()` (group `game_mode`) overridden per mode (bombing/ground/escort/defend/dogfight/historical); `HUD._draw_nav_marker` draws a subtle cyan line + distance on the compass tape (chevron at the edge when off-tape).
- Loading: `GroundKit.lp()` timing markers (`--loadprof`, `--reload-test` times a replay). Urban mask is precomputed (`tools/make_urban_mask.py` -> `data/heightmap/region_urban.png`, re-run after fetch_landcover); imagery/urban textures are kept in `TerrainChunkManager` statics; replay load screen minimum 1.5 s (first load 5 s). Memory: ~230 MB CPU at start, ~350 MB after 25 s; imagery+urban textures ~95 MB VRAM resident.
- `Scatter.field_edge()` now mirrors the terrain shader's strip-field / zone / rectangular-field logic - **keep it in sync with `shaders/terrain.gdshader` whenever the field pattern changes**.
- `scripts/game_music.gd` spawn timings and `shaders/terrain.gdshader` field districts were edited outside this session and are included as found.

# SESSION 2026-10-05: bigger map, imported missions, planner, campaign (branch `bigger-map`, NOT committed)
- **Map 2.1x bigger:** bounds now 48.9-53.0 N, 4.6 W-9.0 E (`WorldCoords`, `tools/make_heightmap.py|fetch_osm.py|build_locations.py|validate_data.py`); heightmap 3072x1500, imagery 6144x3000, landcover 3072x1500. Rebuild order: make_heightmap -> fetch_landcover -> fix_polders -> fetch_imagery -> fetch_osm. **fetch_osm.py overwrites roads.json with synthetic roads if ONE Overpass tile times out** - it did; the real old-area roads were restored from git and saved as `tools/cache/roads_old_area.json`. After the run: `fetch_osm_fill.py --layers roads,rails`, `merge_osm_cache.py`, then `tools/union_osm_roads.py` (a queued background script was doing this; check `tools/cache/bm_fin`). Rivers = hand-drawn fallback lines in `RIVERS_FB` (Rhine, Meuse, Scheldt, Moselle, Main, Trent, Severn...). Rails/coast/woods/towns for the new area are still synthetic/missing.
- **Locations:** 86 airfields, 85 cities, ~180 targets (real Low Countries / Rhineland / Midlands + industry); `naval: true` flags sea convoys. Forward airfields use the `af_` prefix.
- **Original missions (`op_*`):** 25 author-written missions covering the Battle of Britain, 1944-45 Allied strikes and sweeps, and Axis counterparts. Add more by editing `tools/add_original_missions.py` and re-running it (idempotent).
- **Voice:** generic fallback lines (`tools/make_voice_generic.py` -> `voice_generic.csv`, ~1.8k credits on `--model eleven_flash_v2_5`) and place-name lines (`make_voice_places.py` -> `voice_places.csv`). `Radio._load_story` loads all three CSVs; `HistoricalMissions._line` and `main._play_briefing` fall back to `generic/<role>/<side>/<key>`. NOW GENERATED (2026-10-07): all 68 generic + 146 place lines have MP3s - the earlier "NOT generated yet" note was wrong. Regenerate `voice_places.csv` only if the objectives change.
- **Airfields:** `airfield.gd` styles triangle/grass/cross/parallel/forward (`style_for` by id lists). `AirfieldProp` (`scripts/ground/airfield_prop.gd`) makes parked aircraft, blister hangars, huts/tents, trucks and bomb dumps destructible (clusters, group `damageable`); `WorldPopulator._props` / `_dress_other_airfield`.
- **Scenery:** `Scatter.field_edge()` ports the terrain shader's warped-Voronoi fields so hedges/trees/farmsteads follow real field boundaries (hedge segments must have both ends on a boundary); `Scatter._add_farmstead` places sparse farms.
- **Pause menu:** Score button (`ModeBase.live_stats()`).
- **Flight planner:** `scripts/flight_planner.gd` (map click -> airfield runway/airborne or free air spawn, scenario, enemy strength) opened from the start menu (free flight). Config keys `spawn_lat/lon/airfield/airborne/alt/heading`, applied by `main._apply_planned_spawn`. New `EscortMode`, `defend` mode registered. Debug: `--plan=lat,lon,af|-,airborne,alt,hdg`, `--planner-test`.
- **Campaign:** `scripts/campaign.gd` (state in user://campaign.json: strengths, industry, damaged targets, daily offers, enemy raids, ranks, victory/defeat) + `campaign_menu.gd`; start menu has a Campaign button; `main._on_mission_complete` records results. Debug `--campaign-test`.
- Not done: ambient shipping lanes / sea marks for the North Sea, scenery for new areas beyond landcover, visual checks of new airfield layouts and farms (headless runs only). (Real flight models for Bf 110 / Do 17 / Blenheim are now DONE - see the 2026-10-07 session; their visual models stay procedural.)

# >>> HANDOFF FOR THE NEXT MODEL (2026-10-04 evening) - read this first <<<
## Working cheaply (important: the user is short on tokens)
- Do NOT re-read big files or re-explore the project. Use `grep -n` for the exact spot, then edit that spot only.
- Do NOT take screenshots unless the user asks; a `--no-window` run filtered with `Select-String 'SCRIPT|Parse|Invalid'` is enough to check for errors.
- Do NOT spawn subagents. Keep replies short. One test run per change.
- Godot console exe: `F:\godot-rtxin\godot.windows.editor.x86_64.console.exe`. After adding a `class_name` script run it with `--headless --path F:\ww2_dlss --import --quit`.
- Export when done: `& <exe> --headless --path F:\ww2_dlss --export-release "Windows Desktop" F:\ww2_dlssuild\WW2ChannelAirWar.exe` (DLLs are already in build\).
- PowerShell mangles `	`/`\"` inside `python -c`; put Python edits in a bash heredoc or a .py file.

## GitHub (2026-10-04: repo + release are LIVE)
- Repo (public, `main`): https://github.com/colemanuk82/ww2-channel-air-war — owner `colemanuk82`, authed via `gh` (keyring).
- Release v1.0: `WW2ChannelAirWar-v1.0-win64.zip` (exe + the 10 NVIDIA Streamline/DLSS DLLs from `build\`). Rebuild the zip: `Compress-Archive build\WW2ChannelAirWar.exe, build\*.dll -DestinationPath <scratch>\WW2ChannelAirWar-vX.Y-win64.zip`; publish: `gh release create vX.Y <zip> --title vX.Y --notes "..."` (run from `F:\ww2_dlss`).
- `.gitignore` excludes `.godot/`, `build/`, `tools/cache/`, `tools/shots/`, `.commandcode/` — never commit those (~500 MB). Curated README shots live in `screenshots/` (1280x720 jpg) and ARE committed.
- README/ATTRIBUTION/LICENCE: disclosure says the project was vibecoded; voices = ElevenLabs, music = Pixabay (each track title links to its author page: jeremusic70, nocopyrightsound633, musicwallah), map data = Sentinel-2/EOX + ESA WorldCover + AWS Terrain Tiles + OSM. LICENCE = free non-commercial, NO monetization (no sales/ads/sponsorships/monetized streams). Do not relicense to MIT or anything commercial without asking.
- Screenshot recipe (for README updates): `& <exe> --path F:\ww2_dlss --no-window --quit-after 600 -- --skip-menu --air --at=LAT,LON,ALT_M,HDG --frames=180 "--shot=out.png"` then downscale to 1280x720 jpg into `screenshots/`. `--at` teleports to any real coord (alt is world-Y metres; 1 unit = 1 m, terrain heights x2). The shot self-saves and quits at frame N, so `--quit-after` is only a backstop — keep it >= 300 to survive the ~5-120 s scenery load. NOTE: `--shot`/`--tour` runs once stopped saving (DLSS-G `_upscale_internal` in the no-window log); FIXED in the 2026-10-07 session - the upscaler/frame-gen are forced OFF for capture runs, with null/empty-image guards and absolute-path logging, so captures work again.

## Open tasks, in order
1. **DONE (all 468 files generated, imported, build exported 14:39).** Was: finish the voice generation. `tools/generate_voices_elevenlabs.py --csv assets/voice/voice_story.csv` was running in the background (log: `tools/cache/voice_story_gen.log`, 318 lines, ~25k ElevenLabs credits). It skips files that already exist, so if it stopped, just re-run it (the user must set `$env:ELEVENLABS_API_KEY` in their own terminal; never write the key into a file). Count done: `(Get-ChildItem assetsoice -Recurse -Filter *.mp3).Count` (target 150 + 318 = 468).
2. DONE: import + export. Still worth a check: bomber crew lines from a runway start (`--mode=bombing --aircraft=lancaster`, no `--air`).
3. Tell the user to delete the two ElevenLabs API keys pasted in chat and create a new one.
4. Optional: check `tools/cache/voice_story_gen.log` for over-long clips like the 5 trimmed in `assets/voice/allies` (originals in `tools/cache/voice_untrimmed`): compare file size/16000 s vs text length; trim with ffmpeg `atrim` (see that session).

## What exists now (voice system)
- `scripts/radio.gd` (autoload Radio): queue waits for the previous transmission to finish + random 1-6.5 s gap (`_random_gap`); `prio` calls (instructor, bomber crew) skip the gap. Background static/crackle/squelch on the "Radio" bus (option Radio static). `say(sender, text, kind, delay, clip, prio)`; `story(id)` voices a line from `assets/voice/voice_story.csv`; `narrate(rel)` plays a briefing on the "Narration" bus; `reset_channel()`.
- Recorded files: `assets/voice/<allies|axis>/<id>.mp3` (radio calls, 150), `brief/`, `training/<side>/`, `mission/<id>/<side>/`, `mode/<side>/`, `crew/<side>/`. Missing files just fall back to text.
- Options: Radio subtitles (off by default, HUD radio log), Radio static, Radio voice (TTS, off), Control hints.
- Hooks: briefings play over the loading screen (`main._play_briefing`); training `_say` maps text -> clip (`TrainingMode.VOICE_KEYS`) + lesson intros; `HistoricalMissions` start/first/half/all/loss/win/lose lines (`_line`), inner modes muted via `ModeBase.radio_quiet`; generic `radio_call*` in bombing/dogfight/ground/defend; `scripts/crew_intercom.gd` (bomber crew, attached in `main` when the player flies a bomber).
- Audio buses: `AudioManager._ready` makes SFX + Narration; the loading screen mutes SFX only (`set_game_sound_muted`).
- Line lists: `tools/make_voice_lines.py` -> `voice_lines.csv` + `BRIEF.md` cast; `tools/make_voice_story.py` -> `voice_story.csv`. CSVs have `.import` with importer="keep" (stop Godot turning them into translations).

# SESSION 2026-10-04 (afternoon): visuals, HUD/menus, map, convoys, flight smoothness
- **Menu art:** `MenuBackground.discover()` now also accepts `<name>.png.import` (exported builds have no source PNGs, which is why the art never showed in the .exe). Paintings pan/zoom and crossfade. Same paintings are the loading screen (`main.gd _build_load_screen`, bar driven by `WorldPopulator.pending`; cap 120 s; debug `--load-shot=png`).
- **UI look:** `UIKit` restyled (Bahnschrift via SystemFont, set as `ThemeDB.fallback_font` in GameState; brass/smoke palette; `heading()`, `rule()`, `dimmer()`). Start menu = left briefing column over the painting. HUD: boxless round dials (ASI + two-hand altimeter) with throttle/boost/hull/G as arcs round them, icon status row (gear/flaps/assist/brake/wind), icon ammo strip (WeaponHud `_draw_ammo`), mode labels in the top-left column are shrunk by `HUD.add_widget`. Ship markers on the minimap.
- **Flight model (later):** removed the "lift capacity" stall (it stalled every loop at the vertical and every roll at knife-edge); wing rigging bias only acts near the stall; bank-turn and trim fade during fast rolls (`_roll_trim`). Air energy is thrust vs drag (`ENGINE_POWER` 0.6, `INDUCED_DRAG` 1.5; top speeds unchanged). Debug `--loop-test` / `--roll-test`.
- **Free flight:** first skirmish after 150-240 s, then every 120-210 s, 9-14 km away, detect 4.5 km; first raid 90 s.
- **Radio:** silent during the loading screen; random ambient chatter (`CHATTER_ALLIES/AXIS`); every call has a clip id played from `assets/voice/<allies|axis>/<id>.ogg|wav|mp3` through a "Radio" filter bus when present. TTS is off by default (Options > Radio voice). Voice script for external generation: `assets/voice/BRIEF.md` + `voice_lines.csv` (regenerate with `tools/make_voice_lines.py`).
- **Control hints:** right-side panel of Xbox glyphs only (`HUD.HINTS`, `_pad_glyph`), toggled by `GameState.show_hints` (Options > Control hints, saved under [ui] in settings.cfg; F1 also toggles).
- **Map:** `HeightField` coast uses a cubic B-spline land mask on coastal cells + bilinear sea depth (no staircase). Terrain shader: sand only at the waterline and never where imagery is green; built-up land (ESA class 50, `LandCover.urban_mask()` -> `urban_tex`) is paved, no field patchwork. `tools/fix_polders.py` raised enclosed 0 m pockets (Calais/Dunkirk/Flanders polders, Carentan) to 1 m (keeps land-cover water such as Poole/Portsmouth harbours); backup of the old PNG was not kept in the repo.
- **Towns:** city discs from locations.json were left empty (exclusion with no builder) - `_build_city` now adds `Scatter.make_town` cores; land-cover built-up cells get terraces (`_add_terrace`).
- **Sea:** `WorldPopulator.CHANNEL_LANES` (CW/CE British colliers in two columns with destroyer/trawler escorts and barrage balloons; German coastal convoys Cherbourg-Ostend), new ship types collier/trawler, `GroundShip.lateral`, `SHIP_SCALE` 1.8 for ships under way, red/yellow team outline like AI aircraft. `WorldFeatures.SEA_MARKS`: lightvessels (Goodwins, Varne, Sandettie, Royal Sovereign) and Maunsell forts. Debug `--ship-test` verifies ships take damage and sink.
- **Flight smoothness:** tiles took 100-330 ms on the main thread (the real cause of choppy flight). Tile scatter now runs on a WorkerThreadPool task (`Scatter.tile_landcover_data` -> `build_tile_nodes`, MultiMesh buffers), RoadMesh road block is owned by the worker thread; sites are time-budgeted (6 ms/tick) outside load-in. Hard on/off switches in `Aircraft._update_rotation` (bank turn at 100 deg, assist, stall nose drop, trim) are now smooth fades; keyboard stick ramp (`_stick`); per-type `rate_response` (fighters 4.8-6.5, bombers 2.8-3.4). Camera follow uses nlerp (fixes the "axis must be normalized" spam). `--turn-test` prints a JIT line (rotation smoothness + wall-clock max frame time).

# >>> READ FIRST (2026-10-04): the project now lives in F:\ww2_dlss and runs on the NVIDIA RTX Godot fork <<<
The old Godot 4.3 folder `F:\ww2` was deleted. Everything below that mentions `F:\ww2` or the Godot 4.3 exe means THIS folder and the engine described here.
- **Engine:** NVIDIA's official Godot fork (4.8.0-dev, DLSS + frame generation through Streamline), built from source in `F:\godot-rtx` (source: github.com/NVIDIA-RTX/godot, branch `nvidia-pt-dlss`). Rebuild: `cd F:\godot-rtx; python -m SCons platform=windows target=editor use_streamline=yes d3d12=yes vulkan=yes -j14` (and `target=template_release` for the export template). Needs VS 2022 Build Tools (installed) and SCons (`pip install --user scons`); dependencies live in `%LOCALAPPDATA%\Godot\build_deps`.
- **Run / test (always `--no-window`, never a focus-stealing window):**
  `& 'F:\godot-rtx\bin\godot.windows.editor.x86_64.console.exe' --path F:\ww2_dlss --no-window --quit-after 900 -- --skip-menu --air --frames=300 "--shot=F:\ww2_dlss\tools\shots\x.png"`
  Import: the same exe with `--headless --path F:\ww2_dlss --import --quit`.
- **Export (when a batch of work is done):**
  `& 'F:\godot-rtx\bin\godot.windows.editor.x86_64.console.exe' --headless --path F:\ww2_dlss --export-release "Windows Desktop" F:\ww2_dlss\build\WW2ChannelAirWar.exe`
  The preset uses the custom template `F:/godot-rtx/bin/godot.windows.template_release.x86_64.exe`. The NVIDIA runtime DLLs must sit next to the exe: copy `F:\ww2_dlss_sdk\runtime\*.dll` into `build\` (sl.interposer/common/dlss/dlss_g/reflex/pcl/nis, nvngx_dlss/dlssg, NvLowLatencyVk; Streamline SDK v2.10.0 from github.com/NVIDIA-RTX/Streamline, all NVIDIA-signed). Do NOT write `export_presets.cfg` with PowerShell `Set-Content -Encoding utf8` (it adds a BOM and breaks the parser).
- **Desktop shortcut** `WW2 Channel Air War.lnk` points at `F:\ww2_dlss\build\WW2ChannelAirWar.exe`.
- **Upscaling:** `GameState` has `upscaler` (OFF / FSR2 / DLSS; default = DLSS when the `Streamline` singleton reports it, else OFF), `upscale_quality` (render scale 0.667 / 0.58 / 0.5 / 0.333) and `frame_gen` (default OFF; needs an RTX 40-series or newer). The Options menu has a row for each. DLSS is `Viewport.scaling_3d_mode` 6, frame generation is `Viewport.frame_generation`. Debug args: `--upscaler=off|fsr2|dlss`, `--upscale-quality=0..3`, `--framegen`. The game logs `[gfx] upscaler=... dlss_supported=...` at start.
- Raw OSM / terrain downloads are in `tools\cache`. Real roads exist for most tiles; Kent (tile 21) and Pas-de-Calais (tile 16) never downloaded, so those areas still use synthetic roads (see `tools/fetch_osm_fill.py` and `tools/merge_osm_cache.py`).

# HANDOFF: WW2 Channel Air War (Godot 4.3)

Written for another AI model (DeepSeek 4.1 Flash) to continue this project. Read this file, then `SPEC.md`, then work through "NEXT STEPS" in order. Be literal and careful: Godot 4 GDScript is strict about types and indentation (tabs).

## 0. SESSION 2026-10-03 CHANGES (implemented and verified, no script errors, 86-101 FPS)
- **World real scale:** `WorldCoords.HORIZ_COMPRESSION` 10 -> 1. The world is now real-scale (1 unit = 1 m horizontally; aircraft speeds were already m/s since the HUD does `speed * 3.6` for km/h). Crossing the Channel now takes a few minutes. Fixed-size world objects updated: `WaterPlane.size` 110000 -> 1000000, `CloudField.wrap_size` -> 100000 (denser cloud coverage), `custom_aabb` -> +/-5e5. NOTE: sections 4 and 7 below still say 1:10 in places — the 1:1 scale is the new truth.
- **Minimap:** `MAP_RANGE` 22000 (44 km window), `MAP_MOVE` 1500, panel 240x240. Uses the real `region_color.png` mosaic, clamped to the game-map bounds (never cuts off at the map edge), night dimming via `TimeOfDay.light_level`, airfield runway symbols, town dots + names (labels auto-flip to the dot's left side instead of clipping at the panel edge), player arrow.
- **Gamepad:** left stick = plane control (pitch/roll), right stick = free-look only (look, never yaw; deadzone + auto re-center; pitch direction verified via `Input.parse_input_event` injection test). Triggers throttle, A fire, B weapon toggle, Y gear, X camera, RB boost, LB assist.
- **Bombsight:** with bombs selected the chase camera pitches down at the predicted impact point and zooms out 2.4x (so the tail doesn't block). Ground marker = flat crosshair (hand-built `ArrayMesh`: annulus + cross bars) pinned to terrain height each frame, subtle (half blast radius, thin band, dim pulsing emission). No beam, no line to the aircraft. Updates every frame (was 12.5 Hz — caused jitter).
- **Rearm:** land within 450 m of a friendly airfield (`SIDE_AIRFIELDS[GameState.player_side]`) and `player.weapons.rearm()` restores guns/bombs/rockets ("REARMED" message, once per landing). Airfields now carry `team` and join group `"airfield"` (set in `main.gd`).
- **AA safe zone:** `AAGun._acquire` skips aircraft within 700 m of an airfield of their own team (`_at_friendly_field`).
- **Dogfights easier:** enemy count factor 0.6+0.4d, AI skill `difficulty * 0.6`, fighter `detect_range` 4500 (4.5 km visual), spawns 6-9 km away, bomber formations spawn 9 km / route 1.2-10 km.
- **AI detection:** `AIPilot._has_los` (terrain heightfield raycast, 3 samples) gates `_find_target`; `_cloud_field()` + `CloudField.blocks_los(p1, p2)` (sphere test vs whole-cloud centres with wrap-around) gates both `_find_target` and `_target_valid` — clouds now hide you from the AI (tactical mechanic).
- **Sea/clouds:** water shader more waves (wave_scale 0.016, scroll 0.05, lower streak/whitecap thresholds, stronger normal perturbation); low cloud band 700-1600 units (350-800 m), 450 clouds.
- **Export:** `godot --headless --path F:\ww2 --export-release "Windows Desktop" F:\ww2\build\WW2ChannelAirWar.exe` (preset in `export_presets.cfg`, embedded PCK). Desktop shortcut `WW2 Channel Air War.lnk` targets that fixed path, so it always opens the latest build.
- **Validation loop:** rebuild class cache with `--import` after adding `class_name` scripts, then `--no-window` runs + screenshots; use the powershell tool (not shell_command) to avoid progress-XML swallowing output.

## 0b. SESSION 2026-10-03 (later): scale, flight feel, clouds, HUD
- **World is now 1:2** (`HORIZ_COMPRESSION = 2.0`): real map distances take half the flying time. Speeds/object sizes are game units (HUD shows units/s as m/s). `VERTICAL_SCALE` stays 2 (slopes now match reality).
- Runways 1000x42 (`Airfield.layout_scale()` scales taxiways/pens/buildings; populator uses it). Plane accel 7 u/s2, models 1.1x.
- Stall: progressive onset/clear, 55% authority kept, speed floor 0.55*stall speed, unloading breaks the stall (`--stall-test` debug arg logs a recovery).
- Clouds: `cloud_field.gd` + `shaders/cloud_volume.gdshader` = raymarched volumes (box proxies, scene-depth clipped, work when flying inside). API unchanged (cover, mat, blocks_los).
- Toon shader has `detail_mode` (1 building, 2 asphalt, 3 foliage, 4 grass); `Scatter.multi` re-centres batches so they cull/fade (VIS_* constants). HUD rewritten in `hud.gd` (custom drawn).

## 0c. SESSION 2026-10-03 (evening): wind, radio, roads, ports, camps
- **Input:** left-stick click mapping removed (it respawned/cycled airfield). New actions: `brake` (key V, gamepad R3), `radio_form/attack/cover/rtb` (keys 1-4). Options menu (menu + pause) now has Graphics + Controls pages (`SettingsMenu.BINDINGS` table; keep it in sync with `GameState._setup_input`). `GameState.radio_voice` toggles TTS.
- **Wind:** `WeatherManager.get_wind(pos)` (blow-to vector, altitude shear, gusts), `get_turbulence(agl)`, `wind_dir_deg` (from), `wind_speed`, per-weather `wind_lo/hi`, random prevailing south-westerly, retargets every 90-180 s and on weather change. `Aircraft` samples it each frame (`wind`, `headwind`, `crosswind`, `turbulence`): airmass drift, turbulence kicks, ground weathervaning, take-off/rotation use ground airspeed (speed + headwind), touchdown ground speed = airspeed - headwind. Clouds drift with the wind (`cloud_drift`). HUD shows a wind compass + `HEAD/TAIL`, `X-WIND`, `BRAKE`.
- **Audio:** `AudioSFX.wind()` (two procedural noise loops, volume/pitch from airspeed, gust-modulated), called from `aircraft.gd` for the player.
- **Brake:** `Aircraft.brake_on`, 18 u/s2 deceleration on the ground.
- **Radio:** `scripts/radio.gd` autoload `Radio`: FIFO message queue -> HUD log (`hud.gd _draw_radio`), squelch click, optional TTS. Orders 1-4 -> `AIPilot.set_order(Order.*)` (FORM cycles Vic / Echelon / Line abreast / Trail via `Radio.formation_offset`), automatic bandit/kill/hit/tower/control calls. Dogfight spawns 3 wingmen. Debug: `--radio-test`.
- **Minimap:** aircraft markers draw as heading arrows.
- **World:** `RoadMesh` (`scripts/ground/road_mesh.gd`, `shaders/road.gdshader`) draws OSM roads as terrain-hugging ribbons per tile (depth-biased towards camera) and `WorldPopulator._tile_traffic` spawns cars/buses/lorries/military convoys/tanks (max 40 convoys, within 8 km). `TransportNetwork` skips building routes from a big roads.json. `WorldFeatures` (`scripts/world_features.gd`): `PORTS` (quays, breakwaters, piers, cranes, warehouses, moored ships/fishing boats) and `CAMPS` (brick barracks or hut/tent camps with parade ground, fences, guard towers) at real lat/lon, registered as streamed sites. Atlantic Wall clusters are placed every ~3.4 km along the real coastline (`data/osm/coast.json` when its source is overpass, else the old `COAST_STRIPS` x3), with dragon's teeth, poles, hedgehogs, wire, sandbags, bunkers. Trees are suppressed on beaches (`Scatter._beach`). Villages get a church (`Scatter._make_tile_landcover`). Fishing fleets + coastal convoys registered in `_register_ports`.
- **OSM data:** `tools/fetch_osm.py` (LAYER_BUDGET_S raised to 3000 s; per-tile cache in `tools/cache/osm`). If the live fetch aborts (8 failed tiles) it falls back to synthetic; the cache keeps what it got, so rerun it.
- Debug args added: `--stall-test`, `--cloudview=kind:nth:dist[:height]`, `--dump-near`, `--radio-test`, `--call-after=1:_debug_open_options`.

## 1. What the game is
Arcade, cell-shaded (toon) WW2 flight game. Southern England, English Channel, N France, Belgium (real lat/lon, real scale 1 unit = 1 m). Player picks Allies/Axis; modes: dogfight, bombing, ground attack, historical missions, free flight. Full design in `SPEC.md` (the source of truth; includes the coordinate and data contracts).

## 2. Environment
- Project: `F:\ww2` (Godot project, `project.godot` at the root). Windows 11, PowerShell.
- Godot 4.3 exe (console build): `F:\ww2\tools\godot\Godot_v4.3-stable_win64_console.exe`. Windowed exe is in the same folder.
- Python 3.10 at `C:\Program Files\Python310\python.exe` (used only by `/tools`).
- No git repo yet. Consider `git init` and commit before big changes.

## 3. HOW TO RUN AND TEST (important)
ALWAYS test with `--no-window`. A normal windowed run steals the user's keyboard/mouse focus (the user explicitly asked for checks that don't). `--no-window` still renders and saves screenshots.

```powershell
$g='F:\ww2\tools\godot\Godot_v4.3-stable_win64_console.exe'
# first time and after adding any new `class_name` script (rebuilds the class cache, else parse errors):
& $g --headless --path F:\ww2 --import
# validation + screenshot
& $g --path F:\ww2 --no-window --quit-after 600 -- --skip-menu --air --frames=300 "--shot=F:\ww2\tools\shots\x.png" 2>&1 | Select-String 'ERROR|SCRIPT|Parse'
```
Then read the PNG (image viewer/Read tool) to look at it. No output from Select-String = no errors.
- `--headless` prints harmless `Parameter "m" is null ... mesh_get_surface_count` errors (dummy renderer, procedural meshes). Ignore those; use `--no-window` for real validation.
- Debug args (after `--`, parsed in `scripts/main.gd`): `--skip-menu`, `--mode=dogfight|free|bombing|ground|<id>`, `--side=Allies|Axis`, `--aircraft=<id>`, `--difficulty=easy|normal|hard|0..1`, `--weather=clear|scattered|overcast|rain|storm|fog`, `--time=dawn|noon|dusk|night`, `--air` (start airborne), `--at=lat,lon,alt,hdg`, `--wave=N`, `--planes=N`, `--autopilot` (AI flies the player), `--ai-debug`, `--ambient`, `--shot=path.png`, `--frames=N`, `--cockpit`, `--procedural` (force noise terrain), `--noout` (no outlines), `--pause-after=S`, `--finish-after=S`, `--ui-shot=png`.
- Weapons test scene: `res://scenes/weapons/test_range.tscn`. Model viewer: `res://scenes/model_gallery.tscn -- --shot=out.png --ids=spitfire,bf109`.
- Controls: W/S pitch, A/D roll, Q/E yaw, Shift/Ctrl throttle, Space fire, B bomb, G gear, C camera, Tab boost, T time of day, Y weather, O outlines, R assist, Backspace respawn, F2 start mode, F3 cycle airfield, Esc pause.

## 4. Architecture quick map
- Autoloads (project.godot): `WorldCoords`, `GameState`, `TimeOfDay`, `WeatherManager`, `AudioManager`, `SaveSystem`, `FX` (effects), `Weapons` (projectiles).
- `WorldCoords.latlon_to_world(lat, lon)` is the ONLY place the map projection lives (origin lat 50.30/lon 0.00, 1 unit = 1 m horizontal since 2026-10-03, height x2). Never reimplement.
- Damage contract (see `scripts/mode_base.gd`): anything hittable is in group `"damageable"` with `team` ("Allies"/"Axis"/"Neutral"), `hit_radius`, and `take_damage(amount, source)`. Mission targets also join `"mission_target"`.
- `scripts/aircraft.gd` (class `Aircraft`): arcade flight; AI sets `cmd_pitch/cmd_roll/cmd_yaw/throttle_target/cmd_boost/cmd_fire`; each aircraft owns a `WeaponSystem` and damage FX.
- Modes extend `ModeBase` (`scripts/mode_base.gd`) and are registered in `scripts/mode_registry.gd` (dictionary id -> {name, script, desc}). Optional duck-typed members: `configure(cfg)`, `start_airborne`, `manages_respawn`.
- Spawn AI: `AIFactory.spawn(parent, stats_id, team, pos, heading_deg, speed, difficulty, role, leader)`. Bombers: `BomberFormation.spawn(...)`. Minimap markers: `AIFactory.add_marker(hud, node, color)`.
- Aircraft data: `data/aircraft/*.tres` (`AircraftStats`); models are procedural (`scripts/models/model_specs.gd` + `plane_builder.gd`; Spitfire in `spitfire_model.gd`).
- Toon look: `ToonUtil.make_toon(color, opts)` (shaders `toon.gdshader` + `outline.gdshader`); build meshes with `MeshUtil` (smooth normals needed for outlines).
- Terrain: `TerrainChunkManager` streams chunks from `data/heightmap/region_height.png` (16-bit; Godot truncates it, so the script decodes it itself; first run is slow then cached in `user://`). Group "terrain": `get_height_at(pos)`, `is_water_at(pos)`, `add_flat_zone(...)`. LOD rings go out to 48000 units and the cameras' far plane is 48000 to avoid visible pop-in at the horizon.
- World content: `scripts/world_populator.gd` + `scripts/ground/*` (tanks, bunkers, AA guns, searchlights, ships, trains, balloons, landmarks, convoys, scatter for farms/forests). Modes: `scripts/modes/{dogfight,free_flight,bombing,ground_attack,historical_missions}_mode/*.gd`; `scripts/ground/defend_mode.gd` also exists.
- Data: `data/locations.json` (real airfields/cities/features/targets), `data/missions.json` (+ `missions_seed.json`), `data/osm/*.json`, `/tools/*.py` regenerate heightmap/OSM/locations (see `tools/README.md`).

## 5. STATUS (as of this handoff)
DONE and verified by running with no script errors:
- Stage 1: toon+outline shaders, flyable Spitfire, chase/cockpit camera, chunked terrain from real DEM, sea shader, day/night cycle, HUD + minimap, Manston/Hawkinge runways.
- Stage 2: weapons (MG/cannon/bombs/rockets, pooled), FX (explosions, smoke, fire, craters, flak, parachutes), damage visuals, 13 extra aircraft with national markings, AI pilots + wingmen + bomber formations, dogfight and free-flight modes, start menu / pause / results.
- Pop-in fix: terrain streams to 48000 units, faster loading, wider LOD hysteresis.
- Minimap crash on freed nodes fixed in `hud.gd`.

STAGE 3 (world content) WRITTEN, PARTLY VERIFIED (agent report received):
- Files: `scripts/ground/*` (ground_kit, ground_target, ground_vehicle, ground_ship, ground_structure, convoy, train, train_car, aa_gun, aa_shells, searchlight, barrage_balloon, scatter, landmarks, route_path, transport_network, defend_mode), `scripts/world_populator.gd`, `scripts/modes/{bombing_mode,ground_attack_mode,historical_missions}.gd`, `data/missions.json`.
- Modes registered: `bombing`, `ground`, `historical` (use `--mission=<id>`; ids: bob_kent, dieppe_1942, dday_1944, dunkirk_1940, antwerp_raid, lille_raid, lehavre_raid, v1_sites, seine_bridges). Each mode calls `WorldPopulator.ensure(world)` itself, so main.gd needs no change (optional: `WorldPopulator.populate(self, terrain, airfields)` after the airfield loop).
- Debug args: `--wp-demo` (AA nest, convoy, train, bunker, tanks ahead), `--wp-peace` (AA silent), `--wp-teleport`, `--wp-auto` (auto-destroys targets, prints MISSION COMPLETE), `--wp-night`, `--wp-mode=bombing:id|ground_attack:region|hist:id[:side]`.
- VERIFIED: AA fires at the player; convoy and train move; bombing, ground attack and `dday_1944` (Allies) reach MISSION COMPLETE under `--wp-auto`.
- NOT VERIFIED: `dieppe_1942` (Axis), `dunkirk_1940` (Allies), `seine_bridges` (Axis) print no MISSION line within 40 s; searchlights at night; barrage balloons; DefendMode (never run); performance with many streamed sites; real OSM roads (data/osm was empty when that agent ran, straight city-to-city fallback roads were used).
- KNOWN ISSUES: AA was too deadly in dense areas (killed the player in ~5 s; damage was lowered afterwards, not rechecked). "axis must be normalized" errors spam the console in all modes, source not found: find it (grep for `rotated(`, `Basis(`, `look_at`, `Quaternion` with possibly zero vectors) and fix. Streamed site activation radii (7000-9500) are far inside the 48000 far plane, so content pops in: raise radii or fade in; `Scatter.multi` uses visibility_range FADE_SELF which may be ignored by the toon shader (untested). Each AAGun is ~25 meshes (heavy if dense). Results screen pauses the tree, so windowed runs hang at mission end (`--no-window` is fine).

NOT STARTED: real weather effects (rain particles, lightning, cloud decks, sea fog), real audio (engine/guns are procedural via `FX`/`audio_sfx.gd`; music/volume menu missing), SaveSystem (stub), progression/medals/unlocks, quality settings menu, cockpit gauges, kill-cam, README/ATTRIBUTION polish.

## 6. NEXT STEPS (do in order; run the section 3 test after each)
0. **First, fix the "axis must be normalized" console spam** (see section 5 known issues), then recheck AA damage balance.
1. **Integration check of Stage 3.** Investigate the three historical missions that never completed (see section 5). Run every mode: `--mode=bombing`, `--mode=ground`, each historical mission id from `data/missions.json` (see `ModeRegistry.MODES`). Confirm `main.gd` calls `WorldPopulator.populate(...)` so the world has towns, airfields, defences. Fix script errors. Take screenshots over Dover, London, Calais, the D-Day beaches. Check frame rate is acceptable (target 60 fps); lower densities or add visibility ranges if not.
2. **Get real OSM data.** CONFIRMED: `data/osm/*.json` are the SYNTHETIC FALLBACK (validator prints `source=fallback`, files are 1-6 KB). The heightmap is REAL (AWS terrarium z9, 2048x1024) and `locations.json` is real. `python tools\validate_data.py` currently passes with 0 errors. Try `python tools\fetch_osm.py` again (needs internet; Overpass API, tiled with retries; read `tools\README.md`), then re-run validate_data.py. If Overpass keeps failing, download a Geofabrik extract instead. Ensure roads, rails and trains in `scripts/ground/transport_network.gd` follow the data. (The data-tools agent was stopped before finishing; `fetch_osm.py` and `woods.json` were last modified at 17:21, so re-run fetch_osm.py once to be safe.)
3. **Bomb accuracy.** The weapons agent saw a bomb dropped at the predicted impact point not damage a dummy target in the test range. Test in a real bombing run (`Weapons.drop_bomb`, `Weapons.predict_bomb_impact`, `Weapons.explode_at`). Fix if bombs miss.
4. **Pop-in for spawned things.** Enemies spawn 3-5 km away and appear instantly; streamed buildings/trees/units may pop. Use `visibility_range_begin/end` with fade margins (`visibility_range_fade_mode = VISIBILITY_RANGE_FADE_SELF`) or spawn beyond the fog distance; fade in new nodes.
5. **Weather system (Stage 5).** Implement in `scripts/weather_manager.gd` (API already: `set_weather(name, blend)`, signal `weather_changed`): GPUParticles3D rain following the camera, wet look, storm lightning flashes, layered cloud decks the player can fly through (`cloud_field.gd`), sea-fog layer, reduced visibility, and an AI/AA accuracy modifier. Weather currently only changes fog, light and clouds. Note: TimeOfDay uses exponential fog (`fog_density` x `fog_mul`).
6. **Audio, saves, progression (Stage 6).** Real `AudioManager` (buses Music/SFX/Ambience, volume + mute menu, engine drone via `FX.engine`, music loop; if you implement `set_engine_state`, set `FX.audio.engine_enabled = false` to avoid double sound). `SaveSystem` using `ConfigFile` or JSON in `user://` for score/medals/unlocked aircraft; award medals in the results screen.
7. **Remaining polish:** cockpit toon gauges, kill-cam, quality settings (low/med/high), AI tuning (fights are slow: AI fires only a few seconds per minute; bomber stats are untuned), enemy-aircraft difficulty, LOD crossfade, update `README.md` (controls, regenerate data, list of real locations) and `ATTRIBUTION.md`.
8. Run a final pass: every mode on both sides, day and night, every weather, 5 minutes each, no script errors, no focus-stealing windows.

## 7. Rules and gotchas
- Use TABS. Use typed GDScript. If you add a `class_name` script, run the `--headless --import` command, otherwise other scripts fail to parse it.
- Do not use a typed variable to hold a possibly-freed node (`var n: Node3D = arr[0]` errors if freed); use an untyped var plus `is_instance_valid`.
- Do not write source files with PowerShell `Set-Content -Encoding utf8` (Windows PowerShell 5.1 adds a BOM). Use the editor/Write tools, or strip BOM bytes `EF BB BF`.
- All art is procedural low-poly toon, no photo textures. Any imported asset must be CC0/CC-BY and listed in `ATTRIBUTION.md`.
- Keep the real scale: 1 unit = 1 m horizontally (HORIZ_COMPRESSION = 1.0; runways are a fixed 420 units, Spitfire max 175 u/s = 630 km/h).
- Don't break the data contract in `SPEC.md`; other scripts rely on it.
- When unsure whether a change worked, take a `--no-window` screenshot and look at it.


## v5.0 - 1940s landscape additions (released)
Nineteen phases of new world content: sea defences (minefields, booms, blockships, sea forts),
per-city barrage balloons, Dam Busters dams, bombing-decoy sites, the 1927-35 power grid, canal
furniture, railway viaducts/tunnels/junctions, airfield furniture, oil/fuel works, aircraft industry,
V-weapon ski sites and the Pas-de-Calais Heavy Cross bunkers, port clutter, Kentish rural texture,
coastal landmarks, civil defence, aviation support, forestry, navigation aids and military depth.
Gate: import clean, TESTS OK (734 passed, 0 failed); every phase also verified to build in-world by
its own --<thing>-test arg.

## Performance pass (after v7.25)
- `--perf=SECS[:SETTLE]` prints `PERF avg_fps low1_fps gpu_ms rcpu_ms proc_ms phys_ms draws objs prims_k nodes aircraft` then quits.
  A/B switches: `--no-clouds` (hide the volumetric field), `--no-newclouds` (skip the v7.23 types), `--no-passing`, `--no-skywar`, `--no-fronts`.
- Settings > Video > "Cloud detail" (GameState.cloud_detail, also set by the Quality preset): cloud_volume.gdshader
  `step_k` / `max_steps` / `light_every` = Low 1.8/30/3, Medium 1.3/44/2, High 1.0/60/2 (High = the v7.25 look).
- Runway paint marks (≈100 per runway since the v7.24 hand-laid stripes) now share one unit BoxMesh per height,
  cast no shadow and stop drawing beyond 4 km (visibility_range_end).

## v7.27 performance (measured on the RTX 4070 SUPER, 4K, DLSS Performance, frame generation off)
- Cause: trees. ~1000 trees per 1.8 km tile at ~300-420 tris and 8-10 surfaces each (+ an outline pass per surface),
  drawn at full detail to 10.5 km: 78-86 M triangles and 10-15 k draw calls low over an airfield.
- Fixes: (1) far LOD (Scatter.far_mesh / _add_lod_pair): one-surface 30-48 tri crown, no outline, beyond 2200 m x view scale
  (hedges: a 12-tri box beyond 1500 m); (2) Scatter._merge replaces GroundKit.combine in scatter meshes: parts that differ
  only in colour share one surface, colour in vertex COLOR (toon `use_vcol`): a tree is 2 surfaces;
  (3) fewer, bigger wood trees (0.78 -> 0.52, scale 1.25-1.8, cap 6000/tile); 40% of field boundaries have no hedge
  (Scatter.HEDGE_OPEN_PCT, per boundary via field_edge "eid"); (4) removed: airfield ground crews (AirfieldActivity._crew,
  player send-off crew), sheep in folds, field cattle (Scatter.LIVESTOCK).
- Results: Biggin Hill low 30-35 -> 79 fps; countryside 71 -> 107 fps; dogfight 47 -> 57 fps (now CPU-bound).
- Debug: --perf=SECS[:SETTLE] (+ --perf-dump: triangles by owner), --no-framegen, --shadows=0|1, --view=0..2.
- Frame generation works (log: "Enabling DLSS-G"); it doubles the displayed rate, but the in-game rendered rate is what
  --perf reports. A swapchain change (fullscreen toggle) force-disables it for 10 frames, then it re-enables.

## v7.28 CPU performance + free-flight AI cap
- Profiling: PC-only instrumentation (build/prof_inst.py wraps every _process/_physics_process with Prof timers,
  build/spike.py prints SPIKE lines naming the scripts behind a >45 ms frame); never committed. Release script
  reverts it (`git checkout -- scripts shaders; rm scripts/prof.gd`).
- Worker threads: WorldPopulator._shore_for (dock / port / port-clutter shore search, cached; sync on load screen,
  warm-up and pinned sites, otherwise the site defers a tick); AudioSFX.prewarm synthesises every procedural stream one per frame on the MAIN thread (the worker-thread version crashed the exported build: exit 139 during load - never create AudioStreamWAV off the main thread);
  Radio clips via ResourceLoader.load_threaded_request (channel busy while pending).
- WeaponWorld: GRID 300 m spatial index of gridded targets, aircraft / huge targets in _movers; _grid_top skips the
  grid for high bullets. Verified: enemy shot down on the test range; a scripted ground-hit check scored 3/3.
- LOD: GroundVehicle / GroundShip update every 1/3/8 frames by camera distance (x4 for parked vehicles).
- TimeOfDay re-lights every 0.2 s; CloudField repositions 1/4 of the clouds per frame; FXParticles sizes its
  MultiMesh to the live count (power-of-two steps); RaidBlackout spawns its vehicles one per frame.
- FX._ready prebuilds the blast-column material/meshes and the ground-glow shader (first bomb burst stalled ~100 ms).
- AIFactory.ai_cap / ai_room(tree): FreeFlightMode.AI_CAP = 22, honoured by PassingFlights, SortieManager,
  ambient skirmishes and OpsRoom group sizes (taskings still get at least one aircraft).
- Separate render thread (--render-thread separate) tested: "experimental" warning plus a render-thread error; left off.
- [slow] diagnostics added: tile parts, site builds > 40 ms, sky_war raid / flak ticks.
- v7.29: hotfix of the above; release scripts now abort when the exported smoke test exits non-zero.

## NEXT: Pilot's Life career + bail-out (in progress, handed off 2026-10-16)
User asked for: a "Pilot's Life" career campaign for BOTH sides (one pilot, 1940 -> 1945), full-screen images
and a storyline between every mission, and a bail-out button. Agreed first slice: the career framework + the 1940
chapter for RAF and Luftwaffe. Workflow is unchanged: build/test on the PC (F:\ww2_dlss), commit, push,
release with a tools/release_v7xx.sh copied from release_v729.sh (it reverts PC-only instrumentation, gates on tests
AND on the exported smoke test exit code).

### Done so far
- scripts/bail_out.gd (class BailOut, NOT wired in yet; parses OK). Hold the "bail_out" action (J) for 0.9 s,
  >= 70 m AGL: spawns FX.parachute, lets go of the controls, sets player.player_controlled = false and
  take_damage(1e6) so the aircraft spins in and modes count it lost; own Camera3D orbits the chute;
  Enter/J skips the descent after 4 s; emits resolved(fate, pos) with fate "safe" (own land), "sea", "captured"
  (GroundKit.side_at != player side). BailOut.fate_text(fate, side) gives a HUD line. cancel() drops the camera.

### Bail-out wiring (steps 1-7 written in cloud, compile OK, NOT yet tested on the PC)
Steps below are done in code; the PC test (step 8) and the career hook in step 7 are still open.
1. game_state.gd `_setup_input`: `_key("bail_out", KEY_J)` (J is free; keep CRLF line endings on the PC copy).
   Add it to settings_menu.gd BINDINGS (FLIGHT section) and the controls/help text.
2. main.gd after camera_rig is created (~line 1512): `_bail = BailOut.new(); add_child(_bail); _bail.setup(hud)`
   (hud is created just after camera_rig - call setup after the hud exists); connect `_bail.resolved` to a new
   `_on_bail_resolved(fate, pos)`.
3. main._process (in_game branch): `if _bail: _bail.tick(delta, player)`.
4. `_on_player_crashed`: if `_bail != null and _bail.active` -> only camera shake, return (wait for the chute).
5. `respawn_player()` and `_respawn_player_with_support()`: if `_bail.active` -> set `_bail.pending_respawn = true`
   and return (modes with manages_respawn call world.respawn_player() ~4.5 s after the loss).
6. `_spawn_player_inner()`: set `player.player_controlled = true` (bail-out cleared it) and `_bail.cancel()`;
   camera_rig.bind(player) already makes the rig camera current again.
7. `_on_bail_resolved`: hud message BailOut.fate_text; fate "sea" -> DitchRescue.start(self, pos, hud);
   if `_bail.pending_respawn` -> clear it and `_spawn_player()`, elif not `_manages_respawn()` -> `_respawn_timer = 3.0`.
   In a career sortie (config "career") hand the fate to Career instead (see below) and finish the mode.
   [Done] J bound (game_state.gd, settings_menu.gd rows shifted: FLIGHT 0-11 ... SYSTEM 38-43); main.gd wiring as above.
   Career hook still to add in _on_bail_resolved.
8. Test on the PC: free flight, dogfight (manages_respawn), bombing; over land, sea, enemy side; too low.

### To do: career framework (new files, reuse the existing pipeline)
- Pattern to copy: scripts/campaign.gd (+ campaign_menu.gd). A sortie is just a cfg Dictionary emitted via
  `start_requested(cfg)` (menu.gd `_open_campaign` shows how); main.gd `_on_mission_complete` calls
  `Campaign.record_result(success, stats, config)` when cfg "campaign" is true and `quit_to_menu` sets the
  Engine meta "open_campaign" so the menu reopens the campaign screen. Do the same with cfg "career" and meta
  "open_career". Modes available: dogfight, bombing, ground, defend, escort, free, training, historical
  (historical uses data/missions.json ids: dunkirk_1940, bob_kent, dieppe_1942, dday_1944, bmb_* and blitz_*
  bomber raids for the Axis, etc. - good ready-made key missions). cfg keys used by offer_config(): side,
  aircraft, mode, difficulty, weather, time, era_date, spawn_lat/lon/airfield/heading/alt, spawn_airborne,
  wingmen, targets, protect, mission (historical).
- scripts/career.gd (class Career): state in user://career.json: pilot name, side, squadron (fictional number),
  home airfield, aircraft, date, rank (RAF: Pilot Officer..; Luftwaffe: Leutnant..), sorties, kills, hours,
  fatigue, status (active / wounded until date / pow / killed), ironman flag, chapter + step index, mates
  (named squadron mates who appear in the story and can be lost), story flags. record_result(success, stats,
  cfg, fate) advances the step, applies fate: returned / bailed safe (next day) / rescued at sea (2-3 days) /
  wounded (crash on own side: weeks in hospital) / evaded (enemy side, non-ironman: back after weeks) /
  POW or killed (ironman: career ends, memorial / POW page). Fatigue rises per sortie, leave resets it.
- One-life in career sorties: when cfg "career" and the player is lost (crash or bail-out), do not respawn:
  resolve the fate, then mode.finish(false, {"reason": "shot down", "fate": fate}).
- data/career.json: per side, chapters -> steps. A step is either a story sequence (pages) or a mission
  (cfg overrides + story pages before, after_success, after_failure). 1940 chapter ideas (agreed with user):
  RAF - conversion/first solo (training), convoy patrol over Channel shipping (Stukas), scramble from dispersal,
  15 Aug multiple raids, airfield bombed while landing (divert), 15 Sept bombers over London, night fighter
  over the burning docks. Luftwaffe - Freie Jagd over Kent, close escort for Stukas, Adlertag escort of Do 17s to
  Manston, fuel-limited London escort (get home), Seenotdienst: circle a ditched wingman, night Blitz (He 111,
  existing blitz_* missions). Later chapters (1941-45) listed in the chat: Rhubarb, Circus, Channel Dash,
  Dieppe, Crossbow/Diver, D-Day, Cab Rank, Falaise, Bodenplatte, Me 262; Jabo raids, Wilde Sau, Reich defence.
  Use fictional squadron numbers and invented pilot names (no real people). Between-mission beats: readiness
  hut, letters home / to a lost mate's family, newspaper clippings, telegrams, medal ceremonies (MedalCeremony
  exists), postings, a choice of path (night fighters / bombers / PR) that changes later missions.
- scripts/career_menu.gd: new pilot form (name, side, ironman), status page (rank, squadron, date, sorties,
  kills, fatigue, mates), CONTINUE -> story screen -> briefing -> fly. Add a "Pilot's Life" button in
  menu.gd next to "Campaign" (line ~207) and the "open_career" meta reopen (line ~261).
- scripts/story_screen.gd: full-screen CanvasLayer that plays pages: image page (TextureRect, expand/cover,
  slow Ken Burns pan, caption box with typewriter text), letter / telegram / newspaper / diary pages drawn
  as styled UI on paper colours (no image needed), Continue / Skip. Pages come from career.json and can use
  {name}, {rank}, {squadron}, {mate1}... placeholders.

### To do: full-screen story images
No image-generation tool in this environment: render the pictures with the game itself on the PC
(build/shot.ps1 with --skip-menu --mode=free --air --at=lat,lon,alt,hdg --chase=N --orbit=yaw,pitch
--time=dawn|noon|dusk|night --weather=... --frames=N; shots are 1280x720 by default, pass --resolution 1920x1080
in shot.ps1 for plates), e.g. Spitfires on the grass at Biggin Hill at dawn, a formation over the white cliffs,
He 111s over the Thames, London docks burning at night (--raid-now --raid-city=london), a convoy in the
Channel, Stukas diving. Then post-process in Python (PIL/OpenCV: painterly / poster grade, grain, vignette)
into assets/career/<id>.jpg and reference them by id from career.json. Interiors (huts, letters) are UI pages.

## STATUS: Pilot's Life career v1 (written in cloud, tests 762/762, NOT yet played on the PC)
- scripts/career.gd (Career): state user://career.json; new_pilot, next_action, fill (placeholders), mission_config
  (like Campaign.offer_config, cfg "career": true, "career_step"), record_result (fates: safe, sea, captured,
  crashed; rest days; ironman ends the career as KIA / POW; lost mates; queues after pages in state.pending).
- data/career.json: chapter 1940, RAF and Luftwaffe, 7 steps each: story pages (letter/text/telegram/news) and
  missions (free, dogfight, historical dunkirk_1940, bob_kent, blitz_black_saturday).
- scripts/story_screen.gd (StoryScreen.play(parent, pages)): typewriter captions, paper cards, Enter/Esc. Picture
  pages use assets/career/<image> when the file exists; there are NO images yet (dark ground shows instead).
- scripts/career_menu.gd (CareerMenu): new pilot (name, side, aircraft, ironman), status page, CONTINUE.
  "Pilot's Life" button in menu.gd; Engine meta "open_career" reopens it after a sortie.
- main.gd: career sorties end on a lost pilot (_career_lost -> mode.finish(false, {fate})); bail-out fate applies
  the same way; _on_mission_complete calls Career.record_result.
- Open: play-test the whole loop on the PC (new pilot -> story -> mission -> results -> reopen -> pending pages);
  full-screen images (render with build/shot.ps1 into assets/career/<image>, reference from data/career.json
  pages as "image": "name.jpg"); 1941+ chapters; a mission's aircraft choice for the Luftwaffe bombers.
- Squadron names are invented on purpose: No. 921 Squadron, I./JG 901.
