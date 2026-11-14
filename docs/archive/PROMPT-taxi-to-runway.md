# PROMPT: Taxi to runway (dispersal starts + player choice)

Goal: aircraft start where they were parked (dispersal/pads), taxi along the paved taxiways to the
runway, hold short, line up and take off - and the PLAYER picks between a dispersal start (taxi to the
runway) and the current on-runway start. Wingmen taxi in trail behind the player.

Grounded in what exists (do not rebuild):
- Every airfield layout builder (`scripts/airfield.gd`: `_build_raf_grass`, `_build_triangle`,
  `_build_cross`, `_build_grass`, `_build_forward`, `_build_lw_field`...) lays its taxiways with
  `_link(from, to, width, mat)` and its pads with `_pad` / `_box`, and records parking on
  `_dispersal_local` + `trees_local`/`markers_local`. Paved geometry is tracked in `_paved`
  ([from, to, half_width] segments). Runway: `get_threshold_position()`, `heading_deg`, `runway_length`.
- Ground handling exists on `Aircraft`: ground weathervaning, brakes (18 u/s2), take-off/rotation use
  ground airspeed; `player_ground_crew.gd` places the crew + trolley-acc + chocks and clears them when
  the throttle opens. Parked aircraft: `ParkedAircraft.place`.
- Wingmen runway ops (`main.gd` v7.24): `_rw_spawn` parks wingmen ON the runway, queue spacing
  `runway_slot_gap(r) = 2.6r + 12`, each rolls when the aircraft ahead is `gap + 45` along and moving;
  release at 5 s / 13 s; callsigns follow runway order. This queue logic is the seed for taxi trail order.
- AI ground steering: `AIPilot` (FIGHTER/WINGMAN cruise steering by bank angle is airborne only - the
  ground side is the simpler weathervane + throttle; `--ai-takeoff-all` already exercises AI take-off).

## Phase 1 - record the taxi graph at layout time
- In `airfield.gd`: `taxi_nodes: PackedVector3Array` (local) + `taxi_edges: Array` of `[i, j, width]`,
  plus `park_spots: Array` of {pos, yaw} (from `_dispersal_local` and the parked rows), and per layout
  `hold_short: Vector3` + `runway_entry: Vector3` (the point where the taxiway meets the runway edge,
  ~45 m from the pavement edge; the threshold end is the default entry).
- Populate from the same calls that BUILD the pavement: wrap `_link()` so every taxiway segment also
  registers an edge (dedupe by endpoint pair, snap endpoints within 8 m to a shared node). `_pad`
  registers a park node. Cost: zero new geometry, a few hundred small arrays per field, built once in
  `build_layout` (worker-safe: pure data).
- Route = A* (or Dijkstra; graphs are tiny) from the chosen park spot to `runway_entry`, then line up
  along `heading_deg` to `get_threshold_position()`. Store the polyline on the sortie config at spawn:
  `cfg["taxi_route"]`.

## Phase 2 - ground drive controller
- New `scripts/taxi_controller.gd` (class TaxiController, added to the aircraft like BailOut):
  `setup(af, route)`, `tick(delta, player)`. Drives throttle (target 8-12 m/s), `cmd_yaw` toward the
  active waypoint (pure pursuit on the polyline, lookahead ~14 m), brakes inside 10 m of a waypoint and
  at `hold_short`, and hands over to normal take-off once lined up (`runway_entry` -> threshold ->
  `player_controlled = true` restored for the player, or AIPilot take-off for AI).
- Turn radius: cap target speed to ~5 m/s through waypoints whose turn angle > 60 deg (taildraggers
  swing wide - bias the lookahead to the outside of tight turns).
- Player experience: the player FLIES the taxi (stick/rudder + throttle as today), the HUD adds the
  route as chevrons on the compass + a "TAXI - hold short" banner, and the radio says the real thing
  ("Green section, taxi to runway 26, hold short"). Skip choice: holding the assist key (R) for 2 s
  while stopped teleports the aircraft to the threshold ("skip taxi" - accessibility).
- Wingmen: park on adjacent spots (reuse the runway queue's starboard lane logic), taxi in trail with
  `runway_slot_gap` spacing, each starts rolling when the aircraft ahead is gap + 20 m and moving.
  At hold-short each waits until the one ahead is on the runway.

## Phase 3 - the player's choice
- Start point / planner page + quick-sortie config: new option "PARKING: Dispersal | Runway"
  (default Dispersal for free flight + career, Runway for training/dogfight/defence modes where a
  fast start matters). cfg key `start_parking` ("dispersal" | "runway"), persisted in settings.
- `main._spawn_player_inner`: with "dispersal", pick the park spot nearest the wind-preferred runway
  end (deterministic: hash of sortie id), place the aircraft aligned to the spot yaw, spawn the ground
  crew there, build the taxi route, and spawn the player AFTER the world settles as today.
- Ground start queue: on-runway starts keep the existing runway_queue_length nudge; dispersal starts
  ignore it (the queue is the taxi trail).
- Hold-short yield: while the player taxis, if the runway is occupied (landing rollout within 600 m of
  the entry, or another aircraft rolling), hold and re-check every 2 s; radio "hold position".

## Phase 4 - AI, tests, release
- AI wingmen + Ops Room scramble wingmen use the same TaxiController (AIPilot holds it until lined up).
  Escort/bomber formations starting airborne are untouched.
- Tests: `tools/tests.gd` gains `_test_taxi_graph` (every layout style builds a connected graph: every
  park spot reaches a runway entry; edges stay within `_paved` half-widths; hold-short is off the
  runway) and a live `--taxi-test` (player on a pad, `--autopilot` taxis and takes off; TAXI log lines
  every 2 s: leg, speed, hold state). Extend `--ai-takeoff-all` to include a dispersal start per field.
- Perf: nothing per-frame beyond one aircraft's pure-pursuit maths; the graph is built once per field.
- Guard rails: modes with `manages_respawn` keep their own respawn; carrier/ALG forward strips with no
  taxiways fall back to the on-runway start (graph empty -> runway start, no error).
- Release: bump, export, smoke the exported binary (a dispersal-start sortie), `gh release create`.

Order of work: Phase 1 (graph) -> Phase 3 (choice + spawn) with a straight-line taxi first, then
Phase 2 (pure pursuit + holds), then wingmen trail + yield. Commit after each phase; the TESTS OK gate
must stay green.
