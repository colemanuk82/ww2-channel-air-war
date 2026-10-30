class_name BomberFormation
extends Node
## A group of AI bombers flying a waypoint route in a staggered-V formation, with defensive gunners
## that shoot at enemy aircraft in range.
##   var f := BomberFormation.spawn(world, "he111", "Axis", 3, start_pos, heading, route_points, difficulty)
##   f.set_route_from_path(path3d)      # or pass a Path3D curve instead of waypoints
## Signals: route_finished, bomber_destroyed(ac, killer), all_destroyed.

signal route_finished
signal bomber_destroyed(bomber: Aircraft, killer: Node)
signal all_destroyed

const GUN_RANGE: float = 520.0
const TRAIL_ALT_M: float = 1000.0     # above this every bomber in the formation leaves its own contrail

# Defensive turret arcs, in the bomber's own frame: azimuth 0 = dead ahead, +/-180 = astern; elevation
# 0 = level, +90 = straight up. A gun can only fire inside its arc, so the gaps between them are real blind
# spots. The underside is a blind spot on everything except the heavy types, which get a narrow belly
# turret: diving in from below and ahead is the safe way to attack a bomber.
const ARCS := [
	{"az": 0.0,   "azh": 48.0,  "el0": 4.0,   "el1": 72.0},    # nose / upper front
	{"az": 0.0,   "azh": 118.0, "el0": 16.0,  "el1": 80.0},    # dorsal
	{"az": 180.0, "azh": 42.0,  "el0": -26.0, "el1": 46.0},    # tail
]
const BELLY_ARC := {"az": 0.0, "azh": 95.0, "el0": -74.0, "el1": -15.0}
const BELLY_TYPES := ["lancaster", "he111", "b26", "b25", "ju88", "do17", "fw200"]

var team: String = "Allies"
var members: Array[Aircraft] = []
var leader: Aircraft
var home_af: Airfield
var difficulty: float = 0.5
var gunner_damage: float = 3.5
var route: Array[Vector3] = []
var _gun_t: float = 0.0
var _finished: bool = false
var _landing_started: bool = false
var _landed: int = 0


## Bomber streams are bigger than they were: every formation is scaled by this (1 = the old sizes).
static var size_mult: float = 2.0
const MAX_BOMBERS: int = 18
const MAX_BIG_RAID: int = 30          # the occasional big raid: several more vics stacked up and back
## Chance that a formation is a big raid (more vics in a deeper stacked box). 0 in tests (deterministic sizes).
static var big_raid_chance: float = 0.3

## Vic positions inside a combat box, in units of `spacing` (x, z) and world units (y): the lead vic, then vics
## stepped out to each side, up and down, and back, so a big formation reads as a stacked box, not one long V.
const VIC_SLOTS := [
	Vector3(0.0, 0.0, 0.0), Vector3(-3.4, 36.0, 2.8), Vector3(3.4, -36.0, 2.8), Vector3(0.0, 60.0, 5.6),
	Vector3(-3.4, -18.0, 8.4), Vector3(3.4, 54.0, 8.4),
]


## A formation of n scaled to the current size (at least n, never more than MAX_BOMBERS).
static func scaled(n: int) -> int:
	return clampi(int(round(float(n) * size_mult)), n, maxi(n, MAX_BOMBERS))


static func slot_offset(i: int, spacing: float) -> Vector3:
	if i == 0:
		return Vector3.ZERO
	# three to a vic: leader, then right and left, stepped back (the first three keep the old positions)
	var v: int = i / 3
	var j: int = i % 3
	var local := Vector3.ZERO
	if j > 0:
		local = Vector3((1.0 if j == 1 else -1.0) * spacing, -2.0, spacing * 1.3)
	var vs: Vector3 = VIC_SLOTS[v % VIC_SLOTS.size()] + Vector3(0.0, 0.0, 8.4 * float(v / VIC_SLOTS.size()))
	return local + Vector3(vs.x * spacing, vs.y, vs.z * spacing)


static func spawn(parent: Node, stats_id: String, p_team: String, count: int, start_pos: Vector3, heading_deg: float, waypoints: Array[Vector3], p_difficulty: float = 0.5, spacing: float = 95.0) -> BomberFormation:
	count = scaled(count)
	if count >= 6 and randf() < big_raid_chance:
		count = mini(int(round(float(count) * randf_range(1.5, 1.9))) / 3 * 3, MAX_BIG_RAID)   # whole vics
	var f := BomberFormation.new()
	f.name = "BomberFormation"
	f.team = p_team
	f.difficulty = p_difficulty
	f.gunner_damage = lerpf(1.2, 2.4, p_difficulty)
	parent.add_child(f)
	f.home_af = _nearest_home(parent, p_team, start_pos)
	var yaw: Basis = Basis.looking_at(WorldCoords.heading_to_dir(heading_deg), Vector3.UP)
	for i in count:
		var off: Vector3 = slot_offset(i, spacing)
		var pos: Vector3 = start_pos + yaw * off
		var role: int = AIPilot.Role.BOMBER_LEADER if i == 0 else AIPilot.Role.BOMBER_FOLLOWER
		var ac: Aircraft = AIFactory.spawn(parent, stats_id, p_team, pos, heading_deg, -1.0, p_difficulty, role)
		ac.add_to_group("bomber")
		f.members.append(ac)
		var pilot: AIPilot = AIFactory.pilot_of(ac)
		pilot.set_leader(null if i == 0 else f.members[0], off)
		pilot.landed_ai.connect(f._on_member_landed)
		ac.destroyed.connect(f._on_member_destroyed)
	f.leader = f.members[0]
	f.set_route(waypoints)
	var lp: AIPilot = AIFactory.pilot_of(f.leader)
	lp.route_finished.connect(f._on_route_finished)
	return f


func set_route(points: Array[Vector3]) -> void:
	route = points
	if is_instance_valid(leader):
		var p: AIPilot = AIFactory.pilot_of(leader)
		if p:
			p.set_route(points)
			p.state = AIPilot.State.ROUTE


func set_route_from_path(path: Path3D, step: float = 500.0) -> void:
	var pts: Array[Vector3] = []
	var curve: Curve3D = path.curve
	var length: float = curve.get_baked_length()
	var d: float = 0.0
	while d < length:
		pts.append(path.to_global(curve.sample_baked(d)))
		d += step
	pts.append(path.to_global(curve.sample_baked(length)))
	set_route(pts)


func alive_count() -> int:
	var n: int = 0
	for m in members:
		if is_instance_valid(m) and m.state == Aircraft.State.ALIVE:
			n += 1
	return n


static func _nearest_home(parent: Node, p_team: String, pos: Vector3) -> Airfield:
	if parent == null or parent.get_tree() == null:
		return null
	var best: Airfield = null
	var bd: float = INF
	for n in parent.get_tree().get_nodes_in_group("airfield"):
		var af: Airfield = n as Airfield
		if af != null and af.team == p_team:
			var d: float = Vector2(af.global_position.x - pos.x, af.global_position.z - pos.z).length()
			if d < bd:
				bd = d
				best = af
	return best


## Fly the whole formation back into the circuit and land each aircraft. Called when a route that ends
## at the home field is finished, or by a mode that is ending a raid but wants the bombers to go home.
func land_at_home() -> void:
	if _landing_started or home_af == null or not is_instance_valid(home_af):
		return
	_landing_started = true
	for i in members.size():
		var m: Aircraft = members[i]
		if not is_instance_valid(m) or m.state != Aircraft.State.ALIVE:
			continue
		var p: AIPilot = AIFactory.pilot_of(m)
		if p == null:
			continue
		if i == 0:
			p.begin_landing(home_af)
		else:
			var mm: Aircraft = m
			get_tree().create_timer(2.5 * float(i)).timeout.connect(func() -> void:
				if is_instance_valid(mm) and is_instance_valid(home_af):
					var pp: AIPilot = AIFactory.pilot_of(mm)
					if pp != null and mm.state == Aircraft.State.ALIVE:
						pp.begin_landing(home_af))


func _on_member_landed(_a: Aircraft) -> void:
	_landed += 1
	_maybe_free()


func _maybe_free() -> void:
	for m in members:
		if is_instance_valid(m) and m.state == Aircraft.State.ALIVE:
			return
	queue_free()


func _on_route_finished() -> void:
	if not _finished:
		_finished = true
		route_finished.emit()
		if home_af != null and is_instance_valid(home_af) and not route.is_empty():
			var last: Vector3 = route[route.size() - 1]
			if Vector2(last.x - home_af.global_position.x, last.z - home_af.global_position.z).length() < 9000.0:
				land_at_home()


func _on_member_destroyed(a: Aircraft, killer: Node) -> void:
	bomber_destroyed.emit(a, killer)
	if a == leader:
		_promote_leader()
	if alive_count() == 0:
		all_destroyed.emit()
		_maybe_free()


func _promote_leader() -> void:
	var old: AIPilot = AIFactory.pilot_of(leader)
	for m in members:
		if is_instance_valid(m) and m != leader and m.state == Aircraft.State.ALIVE:
			leader = m
			var p: AIPilot = AIFactory.pilot_of(m)
			if p == null:
				return
			p.role = AIPilot.Role.BOMBER_LEADER
			p.leader = null
			p.waypoints = route
			p.wp_index = old.wp_index if old else 0
			p.state = AIPilot.State.ROUTE
			p.route_finished.connect(_on_route_finished)
			for o in members:
				if is_instance_valid(o) and o != m:
					var op: AIPilot = AIFactory.pilot_of(o)
					if op and op.role == AIPilot.Role.BOMBER_FOLLOWER:
						op.leader = m
			return


# ------------------------------------------------------------------ defensive reactions
# Most of the time the bombers hold the box (mutual protection from the gunners). Now and then, under attack, one
# crew does something unpredictable for a few seconds: dives away, climbs, or breaks out to one side, then rejoins.
# Rarely a whole vic (three aircraft) does it together.
var _def_t: float = 2.0
var _home_off: Dictionary = {}      # AIPilot -> its normal formation offset while it is out of the box
var _back_t: Dictionary = {}        # AIPilot -> seconds until it rejoins


func _tick_defence(delta: float, enemies: Array[Aircraft]) -> void:
	for p in _back_t.keys():
		_back_t[p] = float(_back_t[p]) - delta
		if float(_back_t[p]) <= 0.0 or not is_instance_valid(p):
			if is_instance_valid(p):
				(p as AIPilot).formation_offset = _home_off[p]
			_back_t.erase(p)
			_home_off.erase(p)
	_def_t -= delta
	if _def_t > 0.0:
		return
	_def_t = randf_range(2.5, 5.0)
	# under attack: an enemy fighter close to any of us
	var hot: bool = false
	for e in enemies:
		for m in members:
			if is_instance_valid(m) and m.state == Aircraft.State.ALIVE and e.global_position.distance_to(m.global_position) < 900.0:
				hot = true
				break
		if hot:
			break
	if not hot or randf() > 0.35:
		return
	var followers: Array = []
	for i in members.size():
		var m2: Aircraft = members[i]
		if is_instance_valid(m2) and m2.state == Aircraft.State.ALIVE and m2 != leader:
			var p2: AIPilot = AIFactory.pilot_of(m2)
			if p2 != null and p2.role == AIPilot.Role.BOMBER_FOLLOWER and not _back_t.has(p2):
				followers.append([i, p2])
	if followers.is_empty():
		return
	var pick: Array = followers[randi() % followers.size()]
	var group: Array = [pick]
	if randf() < 0.2:                  # the whole vic goes together
		var vic: int = int(pick[0]) / 3
		for f in followers:
			if int(f[0]) / 3 == vic and f != pick:
				group.append(f)
	var move: int = randi() % 3        # 0 dive, 1 climb, 2 break out to a side
	var shift := Vector3.ZERO
	match move:
		0: shift = Vector3(randf_range(-80.0, 80.0), -randf_range(180.0, 420.0), randf_range(0.0, 150.0))
		1: shift = Vector3(randf_range(-80.0, 80.0), randf_range(140.0, 300.0), randf_range(60.0, 220.0))
		_: shift = Vector3((1.0 if randf() < 0.5 else -1.0) * randf_range(300.0, 650.0), randf_range(-120.0, 60.0), randf_range(-60.0, 180.0))
	var dur: float = randf_range(4.0, 9.0)
	for g in group:
		var pp: AIPilot = g[1]
		_home_off[pp] = pp.formation_offset
		_back_t[pp] = dur
		pp.formation_offset = pp.formation_offset + shift + Vector3(randf_range(-30, 30), randf_range(-20, 20), randf_range(-30, 30))


var _def_enemies: Array[Aircraft] = []


func _process(delta: float) -> void:
	_tick_trails()
	_tick_defence(delta, _def_enemies)
	_gun_t -= delta
	if _gun_t > 0.0:
		return
	_gun_t = 0.3
	var vis: float = 1.0
	var wm: Node = get_node_or_null("/root/WeatherManager")
	if wm and wm.has_method("get_visibility_multiplier"):
		vis = clampf(sqrt(float(wm.call("get_visibility_multiplier")) * AIPilot.night_vis()), 0.35, 1.0)
	var acc: float = lerpf(0.28, 0.62, difficulty) * (0.55 + 0.45 * vis)
	var enemies: Array[Aircraft] = []
	for n in get_tree().get_nodes_in_group("aircraft"):
		var e: Aircraft = n as Aircraft
		if e != null and e.team != team and e.team != "Neutral" and e.state == Aircraft.State.ALIVE and not e.is_in_group("bomber"):
			enemies.append(e)
	_def_enemies = enemies
	if enemies.is_empty():
		return
	for m in members:
		if not is_instance_valid(m) or m.state != Aircraft.State.ALIVE:
			continue
		var best: Aircraft = null
		var bd: float = GUN_RANGE * vis
		for e in enemies:
			var d: float = e.global_position.distance_to(m.global_position)
			if d < bd and _turret_can_bear(m, e):
				bd = d
				best = e
		if best == null:
			continue
		# one short burst per tick from this bomber's turrets
		var t: float = bd / AIGun.BULLET_SPEED
		var aim: Vector3 = best.global_position + (best.velocity - m.velocity) * t
		# deliberately loose: not 100% accurate, bursts mostly miss and the occasional round connects
		var spread: float = (1.0 - acc) * 0.12 + 0.04
		var jitter: Vector3 = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * spread * 1.5
		var fire_dir: Vector3 = (aim + jitter - m.global_position).normalized()
		var origin: Vector3 = m.global_position + Vector3.UP * 4.0
		for k in 2:
			AIGun.fire(self, m, origin, AIGun.spread_dir(fire_dir, spread), m.velocity, team, gunner_damage)


## Every bomber leaves its own trail while the formation is high, instead of one line drawn down the
## centre from the leader. The formation altitude is used so a bomber a little low still trails with the box.
func _tick_trails() -> void:
	var sum := Vector3.ZERO
	var n: int = 0
	for m in members:
		if is_instance_valid(m) and m.state == Aircraft.State.ALIVE:
			sum += m.global_position
			n += 1
	if n == 0:
		return
	var c: Vector3 = sum / float(n)
	var alt_m: float = c.y / WorldCoords.VERTICAL_SCALE
	if alt_m < TRAIL_ALT_M:
		return
	var f: float = clampf((alt_m - TRAIL_ALT_M) / 150.0, 0.0, 1.0)
	for m in members:
		if is_instance_valid(m) and m.state == Aircraft.State.ALIVE:
			m.add_contrail_point(f)


## True when at least one turret can bear on `e` (i.e. it is inside a turret arc, not in a blind spot).
func _turret_can_bear(m: Aircraft, e: Aircraft) -> bool:
	var rel: Vector3 = e.global_position - m.global_position
	var local: Vector3 = m.global_transform.basis.inverse() * rel
	var fwd: float = -local.z
	var horiz: float = sqrt(local.x * local.x + fwd * fwd)
	var az: float = rad_to_deg(atan2(local.x, fwd))
	var el: float = rad_to_deg(atan2(local.y, maxf(horiz, 0.01)))
	for a in ARCS:
		if _in_arc(az, el, a):
			return true
	if BELLY_TYPES.has(String(m.stats.id)) and _in_arc(az, el, BELLY_ARC):
		return true
	return false


func _in_arc(az: float, el: float, a: Dictionary) -> bool:
	return absf(wrapf(az - float(a["az"]), -180.0, 180.0)) <= float(a["azh"]) \
		and el >= float(a["el0"]) and el <= float(a["el1"])
