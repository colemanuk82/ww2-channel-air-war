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
const STREAM_ALT_M: float = 800.0     # above this the formation's contrail stream forms
const STREAM_LIFE: float = 60.0       # seconds the stream stays in the sky (long, so it reads from far off)
var _stream: ContrailRibbon = null

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
var difficulty: float = 0.5
var gunner_damage: float = 3.5
var route: Array[Vector3] = []
var _gun_t: float = 0.0
var _finished: bool = false


## Bomber streams are bigger than they were: every formation is scaled by this (1 = the old sizes).
static var size_mult: float = 2.0
const MAX_BOMBERS: int = 18

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
	var f := BomberFormation.new()
	f.name = "BomberFormation"
	f.team = p_team
	f.difficulty = p_difficulty
	f.gunner_damage = lerpf(1.2, 2.4, p_difficulty)
	parent.add_child(f)
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


func _on_route_finished() -> void:
	if not _finished:
		_finished = true
		route_finished.emit()


func _on_member_destroyed(a: Aircraft, killer: Node) -> void:
	bomber_destroyed.emit(a, killer)
	if a == leader:
		_promote_leader()
	if alive_count() == 0:
		all_destroyed.emit()


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


func _process(delta: float) -> void:
	_tick_stream()
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


## The formation's stream: one long contrail laid down along the centre of the living formation while it is high.
## The centre tracks the raid's course, so the white line runs along the raid heading and reads from far off.
func _tick_stream() -> void:
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
	if alt_m < STREAM_ALT_M:
		return
	if _stream == null:
		_stream = ContrailRibbon.new()
		_stream.life = STREAM_LIFE
		add_child(_stream)
	_stream.add_point(c, clampf((alt_m - STREAM_ALT_M) / 250.0, 0.0, 1.0))


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
