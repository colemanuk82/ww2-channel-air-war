class_name EnemyFlights
extends Node
## Free flight: the other side's flights, each with a job. Every couple of minutes a formation appears on its way
## from a real airfield of its own side to a real objective on the player's side, close enough to the player to be
## met. Mission kinds:
##   raid    bombers in vics on a factory / port / airfield / city, with a close escort and a top-cover layer that
##           stays with the bombers and turns on whoever attacks them
##   stuka   dive-bomber attack on Channel shipping (a ship near the player when there is one) or a port, escorted
##   sweep   a "free hunt" fighter sweep: out to a patrol area, a square patrol over it (it picks up the route
##           again after every fight), then home
##   recon   a single high aircraft over an objective and home
## Group size: mostly small (a pair to a schwarm), sometimes medium, now and then a large raid (SIZE_ODDS), cut
## down to what the AI budget (AIFactory.ai_room) allows. Every flight flies a waypoint route out, over the target
## (bombs fall there) and home to its own airfield, and is tidied away once it has left the player's sector.
## Medium and large raids are announced on the radio and the other side's fighters are scrambled against them.
## Owned by FreeFlightMode (ambient flights; cfg "ambient"). Data-driven: the tables below.
## Debug: --flights-test (first flight after 5 s), --flights-kind=raid|stuka|sweep|recon, --flights-size=0|1|2,
## --flights-log ([mission] lines), --flights-every=SECS.

enum Size { SMALL, MEDIUM, LARGE }

const SIZE_ODDS: Array[float] = [0.62, 0.28, 0.10]            # small, medium, large
## Mission weights per side that flies them (the Allied side has no dive-bombers).
const KIND_ODDS_AXIS := {"raid": 0.30, "stuka": 0.14, "sweep": 0.40, "recon": 0.16}
const KIND_ODDS_ALLIED := {"raid": 0.40, "sweep": 0.46, "recon": 0.14}
## Aircraft in the formation, by kind and size: [main min, main max, escort min, escort max].
const COUNTS := {
	"raid": [[3, 4, 2, 4], [6, 9, 4, 6], [12, 18, 8, 10]],
	"stuka": [[3, 4, 2, 3], [6, 8, 3, 4], [10, 12, 5, 6]],
	"sweep": [[2, 4, 0, 0], [6, 8, 0, 0], [10, 12, 0, 0]],
	"recon": [[1, 1, 0, 0], [1, 1, 0, 0], [1, 1, 0, 0]],
}
const MAX_FLIGHTS: int = 3
const SPAWN_RANGE: float = 11000.0     # the flight starts about this far from the player, on its way to the target
const MAX_START: float = 35000.0       # ... and never further than this
const DESPAWN_RANGE: float = 45000.0
const MAX_AGE: float = 1500.0
const BOMBER_ALT := [2400.0, 4300.0]
const STUKA_ALT := [2000.0, 3000.0]
const SWEEP_ALT := [1800.0, 5200.0]
const RECON_ALT := [5200.0, 6400.0]
const ESCORT_CLOSE: int = 4            # this many escorts ride close, the rest fly top cover

var world: Node
var player: Aircraft
var hud: Node
var side: String = "Allies"            # the player's side
var enemy: String = "Axis"             # the side that flies these flights
var difficulty: float = 0.5
var flights: Array = []                # {kind, size, target, tpos, home, members, bombers, escorts, defenders, leader, form, route, target_idx, phase, age, alert_t, done}
var launched: int = 0
var log_on: bool = false

var _t: float = 70.0
var _tick_t: float = 0.0
var _every: float = 0.0
var _forced_kind: String = ""
var _forced_size: int = -1
var _args: PackedStringArray = OS.get_cmdline_user_args()


func setup(p_world: Node, p_player: Aircraft, p_hud: Node, p_side: String, p_difficulty: float) -> void:
	world = p_world
	player = p_player
	hud = p_hud
	side = p_side
	enemy = AircraftCatalog.opposite(side)
	difficulty = p_difficulty
	log_on = _args.has("--flights-log") or _args.has("--flights-test")
	_t = randf_range(60.0, 100.0)
	if _args.has("--flights-test"):
		_t = 5.0
	for a in _args:
		if a.begins_with("--flights-kind="):
			_forced_kind = a.substr(15)
		elif a.begins_with("--flights-size="):
			_forced_size = clampi(int(a.substr(15)), 0, 2)
		elif a.begins_with("--flights-every="):
			_every = float(a.substr(16))
		elif a.begins_with("--flights-timescale="):      # debug: fast-forward the whole sim to watch a flight fly its mission
			Engine.time_scale = clampf(float(a.substr(20)), 1.0, 10.0)


# ------------------------------------------------------------------ pure planning (static: unit-tested)

static func size_class(r: float) -> int:
	if r < SIZE_ODDS[0]:
		return Size.SMALL
	if r < SIZE_ODDS[0] + SIZE_ODDS[1]:
		return Size.MEDIUM
	return Size.LARGE


static func kind_odds(flying_side: String) -> Dictionary:
	return KIND_ODDS_AXIS if flying_side == "Axis" else KIND_ODDS_ALLIED


static func pick_kind(flying_side: String, r: float) -> String:
	var odds: Dictionary = kind_odds(flying_side)
	var total: float = 0.0
	for k in odds:
		total += float(odds[k])
	var acc: float = 0.0
	var last: String = "raid"
	for k in odds:
		acc += float(odds[k]) / total
		last = k
		if r < acc:
			return k
	return last


## Most aircraft a kind and size can field.
static func max_total(kind: String, cls: int) -> int:
	var c: Array = (COUNTS[kind] as Array)[cls]
	return int(c[1]) + int(c[3])


## Counts for a flight: the size is cut down (large -> medium -> small) until it fits `room` free AI slots, then the
## escort and bomber counts are trimmed. main = 0 means there is no room for even the smallest flight.
static func counts_for(kind: String, cls: int, room: int) -> Dictionary:
	if kind == "recon":
		cls = Size.SMALL
	while cls > Size.SMALL and max_total(kind, cls) > room:
		cls -= 1
	var c: Array = (COUNTS[kind] as Array)[cls]
	var main: int = randi_range(int(c[0]), int(c[1]))
	var esc: int = randi_range(int(c[2]), int(c[3]))
	while main + esc > room and esc > 0:
		esc -= 1
	while main + esc > room and main > 1:
		main -= 1
	if main + esc > room:
		main = 0
		esc = 0
	return {"cls": cls, "main": main, "escort": esc}


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Where a flight starts and what it flies: the best of `targets` ({name, pos, kind}) for a player at `p`. Each target
## is paired with the origin airfield ({name, pos}) nearest to it, and the start is the point of the origin -> target
## line that is about `want` from the player (with at least 8 km of run to the target), so flying on the player meets
## the flight. Returns {} when nothing is within `max_start` of the player.
static func plan(p: Vector3, targets: Array, origins: Array, want: float = SPAWN_RANGE, max_start: float = MAX_START) -> Dictionary:
	if origins.is_empty():
		return {}
	var cands: Array = []
	for t in targets:
		var tp: Vector3 = t["pos"]
		var o: Dictionary = {}
		var od: float = INF
		for og in origins:
			var d: float = _flat(og["pos"], tp)
			if d < od:
				od = d
				o = og
		if o.is_empty() or od < 20000.0 or od > 160000.0:
			continue
		var op: Vector3 = o["pos"]
		var dir: Vector3 = Vector3(tp.x - op.x, 0.0, tp.z - op.z).normalized()
		var best_s: float = -1.0
		var best_score: float = INF
		var s: float = 0.0
		while s <= od - 8000.0:
			var pt: Vector3 = op + dir * s
			var sc: float = absf(_flat(pt, p) - want)
			if sc < best_score:
				best_score = sc
				best_s = s
			s += 1500.0
		if best_s < 0.0:
			continue
		var start: Vector3 = op + dir * best_s
		if _flat(start, p) > max_start:
			continue
		cands.append({"score": best_score, "target": t, "origin": o, "start": Vector3(start.x, 0.0, start.z), "dir": dir})
	if cands.is_empty():
		return {}
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) < float(b["score"]))
	return cands[randi() % mini(cands.size(), 4)]


## The waypoints of a flight: the leg to the target (raid / stuka / recon: straight over it, then a turn away on the
## far side; sweep: a square patrol of radius 4.5 km over the area), then home. `target_idx` is the waypoint that is
## the last of the mission itself (over the target / the end of the patrol): flying past it means "turning for home".
static func build_route(start: Vector3, tpos: Vector3, home: Vector3, alt: float, kind: String) -> Dictionary:
	var pts: Array[Vector3] = []
	var to_t: Vector3 = Vector3(tpos.x - start.x, 0.0, tpos.z - start.z)
	var leg: float = to_t.length()
	var dn: Vector3 = to_t.normalized() if leg > 1.0 else Vector3(0.0, 0.0, -1.0)
	var perp := Vector3(-dn.z, 0.0, dn.x)
	var n: int = maxi(int(leg / 9000.0), 1)
	for i in range(1, n):
		var f: float = float(i) / float(n)
		pts.append(Vector3(lerpf(start.x, tpos.x, f), alt, lerpf(start.z, tpos.z, f)))
	var target_idx: int
	if kind == "sweep":
		var ang0: float = Vector2(-dn.x, -dn.z).angle()
		for k in 4:
			var a: float = ang0 + float(k) * PI * 0.5
			pts.append(Vector3(tpos.x + cos(a) * 4500.0, alt, tpos.z + sin(a) * 4500.0))
		target_idx = pts.size() - 1
	else:
		pts.append(Vector3(tpos.x, alt, tpos.z))
		target_idx = pts.size() - 1
		var out1: Vector3 = tpos + dn * 4500.0
		pts.append(Vector3(out1.x, alt, out1.z))
		var out2: Vector3 = tpos + dn * 6000.0 + perp * 6500.0
		pts.append(Vector3(out2.x, alt, out2.z))
	var last: Vector3 = pts[pts.size() - 1]
	var back: float = Vector2(home.x - last.x, home.z - last.z).length()
	var m: int = maxi(int(back / 12000.0), 1)
	for i in range(1, m):
		var f2: float = float(i) / float(m)
		pts.append(Vector3(lerpf(last.x, home.x, f2), lerpf(alt, alt * 0.6, f2), lerpf(last.z, home.z, f2)))
	pts.append(Vector3(home.x, 900.0, home.z))
	return {"pts": pts, "target_idx": target_idx}


## Phase of a flight from its leader's waypoint index.
static func phase_of(wp_index: int, target_idx: int) -> String:
	if wp_index < target_idx:
		return "outbound"
	if wp_index == target_idx:
		return "target"
	return "home"


## Spawn offset of the i-th fighter of a sweep: finger-four flights of four, further flights stepped out to the
## sides, up and back, so a big sweep reads as several flights in one gaggle.
static func fighter_slot(i: int) -> Vector3:
	var g: int = i / 4
	var j: int = i % 4
	var local := Vector3.ZERO
	match j:
		1: local = Vector3(-70.0, -3.0, 85.0)
		2: local = Vector3(70.0, -6.0, 170.0)
		3: local = Vector3(-140.0, -9.0, 255.0)
	if g == 0:
		return local
	var sgn: float = 1.0 if g % 2 == 1 else -1.0
	return local + Vector3(sgn * (320.0 + 200.0 * float(g / 2)), 50.0 * float(g), 220.0 * float(g))


## Offset of the i-th escort fighter round the bombers: the first ESCORT_CLOSE ride close on the flanks, the others
## fly top cover (higher, wider and a little behind).
static func escort_slot(i: int) -> Vector3:
	if i < ESCORT_CLOSE:
		return Vector3((240.0 + float(i / 2) * 90.0) * (1.0 if i % 2 == 0 else -1.0), 110.0 + float(i / 2) * 40.0, 40.0 + float(i / 2) * 120.0)
	var k: int = i - ESCORT_CLOSE
	return Vector3((520.0 + float(k / 2) * 160.0) * (1.0 if k % 2 == 0 else -1.0), 480.0 + float(k / 2) * 70.0, -150.0 - float(k / 2) * 120.0)


# ------------------------------------------------------------------ scheduling

func _process(delta: float) -> void:
	if world == null or player == null or not is_instance_valid(player):
		return
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = 1.0
		_tick(1.0)
	_t -= delta
	if _t > 0.0:
		return
	_t = _every if _every > 0.0 else randf_range(100.0, 190.0)
	if flights.size() >= MAX_FLIGHTS or not _can_spawn():
		_t = 10.0                 # not now (still on the ground, many flights up): look again soon
		_log("[mission] no launch now (%d flights, spawn ok %s)" % [flights.size(), str(_can_spawn())])
		return
	launch_next()


func _can_spawn() -> bool:
	if player.state != Aircraft.State.ALIVE or player.on_ground or player.altitude_agl < 120.0:
		return false
	return WorldPopulator.instance != null and is_instance_valid(WorldPopulator.instance)


## Choose a mission and size and start it. Returns the flight record ({} if nothing could be placed).
func launch_next() -> Dictionary:
	var pop: WorldPopulator = WorldPopulator.instance
	if pop == null or not is_instance_valid(pop):
		return {}
	var kind: String = _forced_kind if _forced_kind != "" else pick_kind(enemy, randf())
	if kind == "stuka" and enemy != "Axis":
		kind = "raid"
	var cls: int = _forced_size if _forced_size >= 0 else size_class(randf())
	var targets: Array = pop.raid_targets(side)
	for a in pop.airfield_sites("RAF" if side == "Allies" else "Luftwaffe"):
		targets.append({"id": a["id"], "name": str(a["name"]) + " airfield", "pos": a["pos"], "kind": "airfield"})
	if kind == "stuka":
		var ship: Node3D = _find_ship()
		if ship != null:
			targets = [{"id": "ship", "name": "Channel shipping", "pos": ship.global_position, "kind": "ship", "node": ship}]
		else:
			targets = targets.filter(func(t: Dictionary) -> bool: return str(t["kind"]) in ["port", "airfield"])
	var origins: Array = pop.airfield_sites("Luftwaffe" if enemy == "Axis" else "RAF")
	var pl: Dictionary = plan(player.global_position, targets, origins)
	if pl.is_empty():
		_t = 25.0
		_log("[mission] no %s plan from here (%d targets, %d origin fields)" % [kind, targets.size(), origins.size()])
		return {}
	return spawn_flight(kind, cls, pl)


func _find_ship() -> Node3D:
	var best: Node3D = null
	var bd: float = 45000.0
	for n in get_tree().get_nodes_in_group("ship"):
		var s: Node3D = n as Node3D
		if s == null or not is_instance_valid(s) or str(s.get("team")) != side or bool(s.get("is_dead")):
			continue
		var d: float = _flat(s.global_position, player.global_position)
		if d > 9000.0 and d < bd:
			bd = d
			best = s
	return best


# ------------------------------------------------------------------ spawning

## Create a flight from a plan() result. Public so the tests can drive it without a WorldPopulator.
func spawn_flight(kind: String, cls: int, pl: Dictionary) -> Dictionary:
	var cnt: Dictionary = counts_for(kind, cls, AIFactory.ai_room(get_tree()) - 2)
	if int(cnt["main"]) < 1:
		return {}
	cls = int(cnt["cls"])
	var tgt: Dictionary = pl["target"]
	var tpos: Vector3 = tgt["pos"]
	var home: Vector3 = (pl["origin"] as Dictionary)["pos"]
	var start: Vector3 = pl["start"]
	var pp: Vector3 = player.global_position
	var alt: float
	match kind:
		"raid": alt = clampf(pp.y + randf_range(200.0, 1200.0), BOMBER_ALT[0], BOMBER_ALT[1])
		"stuka": alt = randf_range(STUKA_ALT[0], STUKA_ALT[1])
		"recon": alt = randf_range(RECON_ALT[0], RECON_ALT[1])
		_: alt = clampf(pp.y + randf_range(-300.0, 900.0), SWEEP_ALT[0], SWEEP_ALT[1])
	start.y = maxf(alt, GroundKit.ground_y(start.x, start.z) + 600.0)
	var rt: Dictionary = build_route(start, tpos, home, alt, kind)
	var route: Array[Vector3] = rt["pts"]
	var hdg: float = WorldCoords.dir_to_heading(Vector3(route[0].x - start.x, 0.0, route[0].z - start.z))
	var f: Dictionary = {"kind": kind, "size": cls, "target": tgt, "tpos": tpos, "home": home, "alt": alt, "members": [], "bombers": [],
		"escorts": [], "defenders": [], "leader": null, "form": null, "route": route, "target_idx": int(rt["target_idx"]),
		"phase": "outbound", "age": 0.0, "alert_t": -100.0, "done": false, "what": "", "start": start}
	flights.append(f)
	launched += 1
	match kind:
		"raid", "stuka":
			_spawn_bombers(f, int(cnt["main"]), int(cnt["escort"]), start, hdg, "ju87" if kind == "stuka" else "")
		"sweep":
			_spawn_sweep(f, int(cnt["main"]), start, hdg)
		_:
			_spawn_recon(f, start, hdg)
	f["what"] = _describe(f)
	_announce(f)
	_log("[mission] launch %s" % _summary(f))
	if cls >= Size.MEDIUM and kind in ["raid", "stuka"]:
		_scramble_defenders(f)
	return f


func _pick(pool: Array, fallback: String) -> String:
	return str(pool[randi() % pool.size()]) if not pool.is_empty() else fallback


func _spawn_bombers(f: Dictionary, n_b: int, n_esc: int, start: Vector3, hdg: float, force_id: String) -> void:
	var bid: String = force_id if force_id != "" else _pick(AircraftCatalog.bombers_for_side(enemy).filter(func(i: String) -> bool: return i not in ["ju87", "ju52", "fw200", "c47"]), "he111")
	var route: Array[Vector3] = f["route"]
	var tpos: Vector3 = f["tpos"]
	var ground_t := Vector3(tpos.x, GroundKit.ground_y(tpos.x, tpos.z), tpos.z)
	var yaw: Basis = Basis.looking_at(WorldCoords.heading_to_dir(hdg), Vector3.UP)
	var form := BomberFormation.new()
	form.name = "BomberFormation"
	form.team = enemy
	form.difficulty = difficulty
	form.gunner_damage = lerpf(1.2, 2.4, difficulty)
	world.add_child(form)
	form.home_af = BomberFormation._nearest_home(world, enemy, f["home"])
	for i in n_b:
		var off: Vector3 = BomberFormation.slot_offset(i, 95.0)
		var role: int = AIPilot.Role.BOMBER_LEADER if i == 0 else AIPilot.Role.BOMBER_FOLLOWER
		var ac: Aircraft = AIFactory.spawn(world, bid, enemy, start + yaw * off, hdg, -1.0, difficulty, role)
		ac.add_to_group("bomber")
		form.members.append(ac)
		var p: AIPilot = AIFactory.pilot_of(ac)
		p.bomb_target = ground_t
		p.bomb_armed = true
		p.bomber_speed_k = 0.92
		p.set_leader(null if i == 0 else form.members[0], off)
		p.landed_ai.connect(form._on_member_landed)
		ac.destroyed.connect(form._on_member_destroyed)
		ac.damaged.connect(func(_a: Aircraft, _amt: float, _h: float) -> void: f["alert_t"] = float(f["age"]))
		(f["members"] as Array).append(ac)
		(f["bombers"] as Array).append(ac)
		_track(ac)
	form.leader = form.members[0]
	form.set_route(route)
	var lp: AIPilot = AIFactory.pilot_of(form.leader)
	lp.route_finished.connect(form._on_route_finished)
	f["form"] = form
	f["leader"] = form.leader
	# the escort: close on the flanks, then top cover. They follow the lead bomber and engage near it.
	var fid: String = _pick(AircraftCatalog.fighters_for_side(enemy).filter(func(i: String) -> bool: return i not in ["me262", "mosquito", "defiant", "typhoon", "tempest", "p38"]), "bf109")
	for j in n_esc:
		var eo: Vector3 = escort_slot(j)
		var e: Aircraft = AIFactory.spawn(world, fid, enemy, start + yaw * eo, hdg, -1.0, clampf(difficulty + 0.1, 0.0, 1.0), AIPilot.Role.WINGMAN, form.leader)
		var ep: AIPilot = AIFactory.pilot_of(e)
		ep.set_leader(form.leader, eo)
		_escort_calm(ep, j >= ESCORT_CLOSE)
		(f["members"] as Array).append(e)
		(f["escorts"] as Array).append(e)
		_track(e)


func _escort_calm(ep: AIPilot, top_cover: bool) -> void:
	ep.engage_radius = 4200.0 if top_cover else 3600.0
	ep.detect_range = 8000.0 if top_cover else 7000.0


func _escort_alert(ep: AIPilot) -> void:
	ep.engage_radius = 8000.0
	ep.detect_range = 11000.0


func _spawn_sweep(f: Dictionary, n: int, start: Vector3, hdg: float) -> void:
	var fid: String = _pick(AircraftCatalog.fighters_for_side(enemy).filter(func(i: String) -> bool: return i not in ["me262", "mosquito", "defiant", "p38"]), "bf109")
	var route: Array[Vector3] = f["route"]
	var tpos: Vector3 = f["tpos"]
	var yaw: Basis = Basis.looking_at(WorldCoords.heading_to_dir(hdg), Vector3.UP)
	var lead: Aircraft = null
	for i in n:
		var off: Vector3 = fighter_slot(i)
		var role: int = AIPilot.Role.FIGHTER if i == 0 else AIPilot.Role.WINGMAN
		var a: Aircraft = AIFactory.spawn(world, fid, enemy, start + yaw * off, hdg, -1.0, clampf(difficulty + 0.1, 0.0, 1.0), role, lead)
		var p: AIPilot = AIFactory.pilot_of(a)
		if i == 0:
			lead = a
			p.patrol_center = Vector3(tpos.x, float(f["alt"]), tpos.z)
			p.patrol_alt = float(f["alt"])
			p.patrol_radius = 3000.0
			p.detect_range = 7000.0
			p.home = f["home"]
			p.set_route(route)
			p.state = AIPilot.State.ROUTE
		else:
			p.set_leader(lead, off)
			p.engage_radius = 4000.0
			p.detect_range = 7000.0
		(f["members"] as Array).append(a)
		_track(a)
	f["leader"] = lead


func _spawn_recon(f: Dictionary, start: Vector3, hdg: float) -> void:
	var ids: Array = ["ju88", "bf110"] if enemy == "Axis" else ["spitfire", "blenheim"]
	var rid: String = str(ids[randi() % ids.size()])
	var a: Aircraft = AIFactory.spawn(world, rid, enemy, start, hdg, -1.0, difficulty, AIPilot.Role.FIGHTER)
	var p: AIPilot = AIFactory.pilot_of(a)
	p.detect_range = 1800.0          # eyes on the ground, not looking for a fight
	p.patrol_alt = float(f["alt"])
	p.home = f["home"]
	p.set_route(f["route"])
	p.state = AIPilot.State.ROUTE
	(f["members"] as Array).append(a)
	f["leader"] = a
	_track(a)


## The other side's fighters come up to meet a medium or large raid: they appear over their own nearest airfield
## to the target, already climbing, and patrol over the target area.
func _scramble_defenders(f: Dictionary) -> void:
	var pop: WorldPopulator = WorldPopulator.instance
	if pop == null or not is_instance_valid(pop):
		return
	var tpos: Vector3 = f["tpos"]
	var best: Dictionary = {}
	var bd: float = 45000.0
	for s in pop.airfield_sites("RAF" if side == "Allies" else "Luftwaffe"):
		var d: float = _flat(s["pos"], tpos)
		if d < bd:
			bd = d
			best = s
	if best.is_empty():
		return
	var n: int = mini(3 if int(f["size"]) == Size.MEDIUM else 6, AIFactory.ai_room(get_tree()))
	if n < 2:
		return
	var fid: String = _pick(AircraftCatalog.fighters_for_side(side).filter(func(i: String) -> bool: return i not in ["me262", "mosquito", "defiant", "p38"]), "spitfire")
	var bp: Vector3 = best["pos"]
	var hdg: float = WorldCoords.dir_to_heading(Vector3(tpos.x - bp.x, 0.0, tpos.z - bp.z))
	for i in n:
		var pos := Vector3(bp.x + float(i) * 110.0, GroundKit.ground_y(bp.x, bp.z) + 1300.0 + float(i) * 25.0, bp.z + float(i % 2) * 90.0)
		var e: Aircraft = AIFactory.spawn(world, fid, side, pos, hdg, -1.0, difficulty, AIPilot.Role.FIGHTER)
		var p: AIPilot = AIFactory.pilot_of(e)
		p.patrol_center = Vector3(tpos.x, float(f["alt"]) - 300.0, tpos.z)
		p.patrol_alt = float(f["alt"]) - 300.0
		p.patrol_radius = 3500.0
		p.detect_range = 9000.0
		(f["defenders"] as Array).append(e)
		_track(e)


func _track(a: Aircraft) -> void:
	AIFactory.add_marker(hud, a, Color(0.3, 0.75, 1.0) if a.team == side else Color(1.0, 0.25, 0.2))
	a.crashed.connect(func(x: Aircraft, _r: String) -> void:
		if not x.is_inside_tree():
			return
		await x.get_tree().create_timer(2.5).timeout
		if is_instance_valid(x):
			x.queue_free())


# ------------------------------------------------------------------ describing and announcing

func _describe(f: Dictionary) -> String:
	var n_main: int = (f["bombers"] as Array).size() if not (f["bombers"] as Array).is_empty() else (f["members"] as Array).size()
	var tn: String = str(f["target"]["name"])
	match str(f["kind"]):
		"raid": return "%d bombers and %d fighters for %s" % [n_main, (f["escorts"] as Array).size(), tn]
		"stuka": return "%d dive-bombers and %d fighters on %s" % [n_main, (f["escorts"] as Array).size(), tn]
		"sweep": return "a sweep of %d fighters over %s" % [n_main, tn]
	return "a reconnaissance aircraft over %s" % tn


func _summary(f: Dictionary) -> String:
	var lead: Variant = f.get("leader")
	var where: String = ""
	if lead != null and is_instance_valid(lead):
		var lp: Vector3 = (lead as Node3D).global_position
		where = " start=(%.0f,%.0f,%.0f) player_d=%.1fkm" % [lp.x, lp.y, lp.z, _flat(lp, player.global_position) / 1000.0]
	return "%s size=%d (%s) %d aircraft target=%s (%s) home=(%.0f,%.0f) wps=%d target_wp=%d%s" % [str(f["kind"]), int(f["size"]), ["small", "medium", "large"][int(f["size"])], (f["members"] as Array).size(), str(f["target"]["name"]), str(f["target"]["kind"]), (f["home"] as Vector3).x, (f["home"] as Vector3).z, (f["route"] as Array).size(), int(f["target_idx"]), where]


func _announce(f: Dictionary) -> void:
	if int(f["size"]) < Size.MEDIUM or str(f["kind"]) == "recon":
		return
	var count: int = (f["members"] as Array).size()
	var round_n: int = count / 5 * 5
	var tn: String = str(f["target"]["name"]).replace(" airfield", "")
	var line: String
	if str(f["kind"]) == "sweep":
		line = "%s, Control. Large formation of fighters, %d plus, over the area - heading for %s." % [Radio.callsign_of(player), round_n, tn]
	else:
		line = "%s, Control. %s raid building, %d plus bandits, heading for %s." % [Radio.callsign_of(player), "Large" if int(f["size"]) == Size.LARGE else "Medium", round_n, tn]
	Radio.say("Control", line, Radio.Kind.CONTROL, 1.0)
	if hud != null and hud.has_method("show_message"):
		hud.call("show_message", "Raid reported: %d+ bandits, heading for %s" % [round_n, tn], 5.0)


func _log(msg: String) -> void:
	if log_on:
		print(msg)


# ------------------------------------------------------------------ the flights on their way

func _alive(arr: Array) -> Array:
	return arr.filter(func(m) -> bool: return is_instance_valid(m) and (m as Aircraft).state == Aircraft.State.ALIVE)


func _lead_of(f: Dictionary) -> Aircraft:
	var l: Variant = f.get("leader")
	if l != null and is_instance_valid(l) and (l as Aircraft).state == Aircraft.State.ALIVE:
		return l
	var pool: Array = _alive(f["bombers"]) if not (f["bombers"] as Array).is_empty() else _alive(f["members"])
	if pool.is_empty():
		return null
	var nl: Aircraft = pool[0]
	if (f["bombers"] as Array).is_empty():
		# a fighter flight: the next in line takes over the route
		var np: AIPilot = AIFactory.pilot_of(nl)
		var op: AIPilot = AIFactory.pilot_of(l) if l != null and is_instance_valid(l) else null
		if np != null:
			np.role = AIPilot.Role.FIGHTER
			np.leader = null
			np.waypoints = f["route"]
			np.wp_index = op.wp_index if op != null else 0
			np.patrol_center = Vector3(f["tpos"].x, float(f["alt"]), f["tpos"].z)
			np.state = AIPilot.State.ROUTE
			for o in pool:
				if o != nl:
					var opl: AIPilot = AIFactory.pilot_of(o)
					if opl != null:
						opl.leader = nl
	else:
		var form: Variant = f.get("form")
		if form != null and is_instance_valid(form):
			var bf: BomberFormation = form
			if is_instance_valid(bf.leader) and bf.leader.state != Aircraft.State.ALIVE:
				bf._promote_leader()          # normally done by the destroyed signal; make sure it has happened
			if is_instance_valid(bf.leader) and bf.leader.state == Aircraft.State.ALIVE:
				nl = bf.leader
	f["leader"] = nl
	return nl


func _tick(dt: float) -> void:
	var keep: Array = []
	for f in flights:
		if _update(f, dt):
			keep.append(f)
	flights = keep


## One second of one flight; false when it has been tidied away.
func _update(f: Dictionary, dt: float) -> bool:
	f["age"] = float(f["age"]) + dt
	var lead: Aircraft = _lead_of(f)
	if lead == null:
		_log("[mission] %s over (no survivors)" % str(f["kind"]))
		_remove(f, false)
		return false
	var lp: AIPilot = AIFactory.pilot_of(lead)
	var d: float = _flat(lead.global_position, player.global_position)
	if log_on and int(float(f["age"])) % 20 == 0:
		var lpp: Vector3 = lead.global_position
		_log("[mission] status %s %s: lead (%.0f, %.0f, %.0f) spd %.0f wp %d/%d, %.1f km from player, %d alive" % [str(f["kind"]), str(f["phase"]), lpp.x, lpp.y, lpp.z, lead.speed, lp.wp_index if lp != null else -1, lp.waypoints.size() if lp != null else 0, d / 1000.0, _alive(f["members"]).size()])
	if lp != null:
		var ph: String = phase_of(lp.wp_index, int(f["target_idx"]))
		if ph != str(f["phase"]):
			f["phase"] = ph
			_log("[mission] %s %s -> %s (wp %d/%d, lead %.0f m alt, %.1f km from player, %d alive)" % [str(f["kind"]), str(f["target"]["name"]), ph, lp.wp_index, lp.waypoints.size(), lead.global_position.y, d / 1000.0, _alive(f["members"]).size()])
			if ph == "home" and str(f["kind"]) in ["raid", "stuka"]:
				_log("[mission] %s bombs: %s" % [str(f["kind"]), _bombs_left(f)])
		# a fighter flight whose leader finished a fight resumes its route instead of stooging about
		if lp.role == AIPilot.Role.FIGHTER and lp.state == AIPilot.State.PATROL and lp.wp_index < lp.waypoints.size() and str(f["kind"]) != "":
			lp.state = AIPilot.State.ROUTE
			_log("[mission] %s resumes its route (wp %d)" % [str(f["kind"]), lp.wp_index])
	# escorts: re-attach to the lead after a leader change, widen their reaction when the bombers are hit
	if not (f["escorts"] as Array).is_empty():
		var alert: bool = float(f["age"]) - float(f["alert_t"]) < 25.0
		for e in f["escorts"]:
			if not is_instance_valid(e) or (e as Aircraft).state != Aircraft.State.ALIVE:
				continue
			var ep: AIPilot = AIFactory.pilot_of(e)
			if ep == null:
				continue
			if ep.leader == null or not is_instance_valid(ep.leader) or (ep.leader as Aircraft).state != Aircraft.State.ALIVE:
				ep.set_leader(lead, ep.formation_offset)
			if alert:
				_escort_alert(ep)
			else:
				_escort_calm(ep, ep.formation_offset.y > 300.0)
	# tidy away once it has gone home and left the player's sector, or is simply far / old
	var finished: bool = lp != null and lp.wp_index >= lp.waypoints.size()
	if (finished and d > 12000.0) or (d > DESPAWN_RANGE and float(f["age"]) > 60.0) or float(f["age"]) > MAX_AGE:
		_log("[mission] %s over: %s, %.1f km from player after %.0f s" % [str(f["kind"]), "home" if finished else "left the area", d / 1000.0, float(f["age"])])
		_remove(f, true)
		return false
	return true


func _bombs_left(f: Dictionary) -> String:
	var left: int = 0
	var n: int = 0
	for b in f["bombers"]:
		if is_instance_valid(b):
			n += 1
			left += int((b as Aircraft).bombs)
	return "%d bomber(s) alive, %d bombs still aboard" % [n, left]


func _remove(f: Dictionary, quiet: bool) -> void:
	if quiet:
		for m in (f["members"] as Array) + (f["defenders"] as Array):
			if is_instance_valid(m):
				(m as Node).queue_free()
		var form: Variant = f.get("form")
		if form != null and is_instance_valid(form):
			(form as Node).queue_free()


func _exit_tree() -> void:
	flights.clear()
