class_name TargetIndex
extends RefCounted
## Shared snapshot of every damageable thing (aircraft, ships, ground targets) so combat code does not walk the
## scene tree every frame. The AI looked up its nearest ground target by iterating every damageable node, for
## every aircraft, every frame: with 30 aircraft and ~700 targets that alone measured 7.5 ms a frame - more than
## half the frame budget at 25 fps.
##
## The tree is only read on the main thread (scene access is not thread-safe) and only REFRESH_HZ times a second;
## the searches then run over packed arrays, which is ~100x cheaper per query and needs no locks. A quarter of a
## second of staleness is invisible for target picking, and the callers already lead their targets.
##
## Usage: TargetIndex.ensure(get_tree()) then one of the search helpers. Everything is static: no node of its own.

const REFRESH_HZ: float = 5.0

const KIND_AIR: int = 0        # aircraft: fast moving, used for aim assist and the HUD
const KIND_GROUND: int = 1     # ships and ground targets: what an opportunistic strike looks for

static var _nodes: Array = []
static var _pos: PackedVector3Array = PackedVector3Array()
static var _vel: PackedVector3Array = PackedVector3Array()
static var _rad: PackedFloat32Array = PackedFloat32Array()
static var _team: PackedInt32Array = PackedInt32Array()
static var _kind: PackedInt32Array = PackedInt32Array()
static var _neutral: PackedByteArray = PackedByteArray()
static var _team_ids: Dictionary = {}
static var _seen: Dictionary = {}
static var _next_ms: int = 0


static func _team_code(team: String) -> int:
	var c: int = int(_team_ids.get(team, -1))
	if c < 0:
		c = _team_ids.size()
		_team_ids[team] = c
	return c


static func _collect(list: Array, kind: int) -> void:
	for n in list:
		var n3: Node3D = n as Node3D
		if n3 == null or not is_instance_valid(n3):
			continue
		var id: int = n3.get_instance_id()
		if _seen.has(id):
			continue
		var tm: Variant = n3.get("team")
		if tm == null:
			continue
		var dead: Variant = n3.get("is_dead")
		if dead != null and bool(dead):
			continue
		if kind == KIND_AIR and int(n3.get("state")) != 0:     # Aircraft.State.ALIVE
			continue
		_seen[id] = true
		_nodes.append(n3)
		_pos.append(n3.global_position)
		var v: Variant = n3.get("velocity")
		_vel.append(v if v is Vector3 else Vector3.ZERO)
		var r: Variant = n3.get("hit_radius")
		_rad.append(float(r) if r is float or r is int else 0.0)
		_team.append(_team_code(str(tm)))
		_neutral.append(1 if str(tm) == "Neutral" else 0)
		_kind.append(kind)


## Re-read the scene tree (at most REFRESH_HZ times a second: cheap enough to call every frame).
static func ensure(tree: SceneTree) -> void:
	var now: int = Time.get_ticks_msec()
	if now < _next_ms:
		return
	_next_ms = now + int(1000.0 / REFRESH_HZ)
	_nodes.clear()
	_pos.clear()
	_vel.clear()
	_rad.clear()
	_team.clear()
	_kind.clear()
	_neutral.clear()
	_seen.clear()
	_collect(tree.get_nodes_in_group("ground_target"), KIND_GROUND)
	_collect(tree.get_nodes_in_group("ship"), KIND_GROUND)
	_collect(tree.get_nodes_in_group("aircraft"), KIND_AIR)


static func count() -> int:
	return _nodes.size()


## The nearest live enemy in range, or null. ground_only ignores aircraft.
static func nearest(from: Vector3, team: String, min_d: float, max_d: float, ground_only: bool = true, skip_neutral: bool = false) -> Node3D:
	var tc: int = _team_code(team)
	var min2: float = min_d * min_d
	var max2: float = max_d * max_d
	var best: int = -1
	var best_d: float = max2
	for i in _nodes.size():
		if _team[i] == tc:
			continue
		if skip_neutral and _neutral[i] != 0:
			continue
		if ground_only and _kind[i] != KIND_GROUND:
			continue
		var d2: float = from.distance_squared_to(_pos[i])
		if d2 < min2 or d2 >= best_d:
			continue
		best_d = d2
		best = i
	return _node(best)


## The nearest live enemy in range lying roughly ahead of fwd (a wider cone for things with a big hit radius),
## or null. What an opportunistic ground strike scans for.
static func nearest_ahead(from: Vector3, fwd: Vector3, team: String, min_d: float, max_d: float, base_ang: float) -> Node3D:
	var tc: int = _team_code(team)
	var min2: float = min_d * min_d
	var max2: float = max_d * max_d
	var best: int = -1
	var best_d: float = max2
	for i in _nodes.size():
		if _kind[i] != KIND_GROUND or _team[i] == tc:
			continue
		var rel: Vector3 = _pos[i] - from
		var d2: float = rel.length_squared()
		if d2 < min2 or d2 >= best_d:
			continue
		var d: float = sqrt(d2)
		if d < 0.001:
			continue
		if fwd.dot(rel / d) < cos(base_ang + _rad[i] / d):
			continue
		best_d = d2
		best = i
	return _node(best)


## The live enemy closest to the aim line within the range window (aim assist), or null.
static func best_by_angle(from: Vector3, fwd: Vector3, team: String, min_d: float, max_d: float, max_ang: float = INF) -> Node3D:
	var tc: int = _team_code(team)
	var min2: float = min_d * min_d
	var max2: float = max_d * max_d
	var best: int = -1
	var best_ang: float = max_ang
	for i in _nodes.size():
		if _team[i] == tc or _neutral[i] != 0:
			continue
		var rel: Vector3 = _pos[i] - from
		var d2: float = rel.length_squared()
		if d2 < min2 or d2 > max2:
			continue
		var ang: float = fwd.angle_to(rel)
		if ang < best_ang:
			best_ang = ang
			best = i
	return _node(best)


## The live enemy with the best "in front and close" score (HUD target + lead), or null.
static func best_in_cone(from: Vector3, fwd: Vector3, team: String, min_d: float, max_d: float, min_dot: float) -> Node3D:
	var tc: int = _team_code(team)
	var min2: float = min_d * min_d
	var max2: float = max_d * max_d
	var best: int = -1
	var best_score: float = -INF
	for i in _nodes.size():
		if _team[i] == tc or _neutral[i] != 0:
			continue
		var rel: Vector3 = _pos[i] - from
		var d2: float = rel.length_squared()
		if d2 < min2 or d2 > max2:
			continue
		var d: float = sqrt(d2)
		var dot: float = fwd.dot(rel) / d
		if dot < min_dot:
			continue
		var score: float = dot * 2.0 - d / max_d
		if score > best_score:
			best_score = score
			best = i
	return _node(best)


## A random live enemy ground target within radius of p (excluding `exclude`), or null.
static func random_near(p: Vector3, team: String, radius: float, exclude: Node3D) -> Node3D:
	var tc: int = _team_code(team)
	var r2: float = radius * radius
	var picks: Array = []
	for i in _nodes.size():
		if _kind[i] != KIND_GROUND or _team[i] == tc:
			continue
		if _nodes[i] == exclude:
			continue
		if p.distance_squared_to(_pos[i]) < r2:
			picks.append(i)
	if picks.is_empty():
		return null
	return _node(int(picks[randi() % picks.size()]))


## True when a live enemy sits within radius of p (planar, i.e. over the ground: the bombsight aim point).
static func any_near(p: Vector3, team: String, radius: float) -> bool:
	var tc: int = _team_code(team)
	var r2: float = radius * radius
	for i in _nodes.size():
		if _team[i] == tc or _neutral[i] != 0:
			continue
		var dx: float = _pos[i].x - p.x
		var dz: float = _pos[i].z - p.z
		if dx * dx + dz * dz < r2:
			return true
	return false


static func _node(i: int) -> Node3D:
	if i < 0:
		return null
	var n: Node3D = _nodes[i] as Node3D
	if n == null or not is_instance_valid(n):
		return null
	return n
