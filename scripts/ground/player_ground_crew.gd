class_name PlayerGroundCrew
extends Node3D
## The player's own ground crew on a ground start: a fitter up at the engine, a rigger down by the wheel, the
## trolley-acc man by his trolley accumulator (cable plugged into the aircraft) and wheel chocks with their
## rope. When the throttle opens the chocks are pulled, the cable comes out and the erks walk clear to the side;
## one stops and waves the pilot off. Purely visual. Figures are CrewFigure meshes at aircraft scale.

const SCALE: float = 1.45            # aircraft are drawn ~1.45x life size; the crew and kit match them

var aircraft: Aircraft
var _crew: Array = []                # [{node, pose, walk_off: Vector3, phase}]
var _trolley: Node3D
var _cable: MeshInstance3D
var _chocks: Array = []
var _state: int = 0                  # 0 waiting, 1 walking clear, 2 done
var _t: float = 0.0
var _away: Vector3 = Vector3.ZERO
var _fwd: Vector3 = Vector3.FORWARD
var _walk_t: float = 0.0


static func attach(ac: Aircraft, host: Node) -> PlayerGroundCrew:
	var g := PlayerGroundCrew.new()
	g.aircraft = ac
	host.add_child(g)
	return g


func _ready() -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		queue_free()
		return
	top_level = true
	_fwd = aircraft.get_forward()
	_fwd.y = 0.0
	_fwd = _fwd.normalized()
	var left := Vector3(_fwd.z, 0.0, -_fwd.x)
	_away = left
	var base: Vector3 = aircraft.global_position
	var span: float = maxf(aircraft.hit_radius, 6.0)
	var team: String = aircraft.team
	var dress0: int = randi() % CrewFigure.DRESSES
	var face_ac: float = atan2(left.x, left.z)          # yaw that faces back toward the aircraft from the port side
	# nobody stands ahead of the wing's leading edge (the propeller and the pilot's view): the crew wait beside
	# and behind the wing. The fitter reaches up to the cockpit side, behind the trailing edge.
	_add_fig(team, CrewFigure.Pose.REACH, dress0, base - _fwd * (span * 0.32) + left * 2.0, face_ac + 0.5)
	# rigger down by the port wheel
	_add_fig(team, CrewFigure.Pose.KNEEL, (dress0 + 1) % CrewFigure.DRESSES, base + left * (span * 0.28 + 1.4) - _fwd * 0.6, face_ac)
	# a third at the wingtip, hands on hips, watching
	_add_fig(team, CrewFigure.Pose.HIPS, (dress0 + 2) % CrewFigure.DRESSES, base + left * (span * 1.0 + 1.5) - _fwd * 1.5, face_ac - 0.4)
	# the trolley-acc man beside his trolley, out past the port wing and level with its trailing edge
	var tpos: Vector3 = base + left * (span * 0.62 + 2.0) - _fwd * (span * 0.15)
	_add_fig(team, CrewFigure.Pose.STAND, (dress0 + 3) % CrewFigure.DRESSES, tpos - _fwd * 1.8 + left * 1.0, face_ac + 0.8)
	_build_trolley(team, tpos, base + _fwd * (span * 0.08) + left * 0.9)
	# chocks in front of both main wheels, joined by a rope so they can be pulled together
	for sx in [-1.0, 1.0]:
		var cp: Vector3 = base + left * (sx * span * 0.22) + _fwd * 1.3
		_chocks.append(_build_chock(cp))
	var rope_a: Vector3 = (_chocks[0] as Node3D).global_position
	var rope_b: Vector3 = (_chocks[1] as Node3D).global_position
	var rope: MeshInstance3D = _line(rope_a + Vector3.UP * 0.35, rope_b + Vector3.UP * 0.35, 0.035, Color(0.62, 0.55, 0.40))
	add_child(rope)
	_chocks.append(rope)


func _gy(p: Vector3) -> float:
	return GroundKit.ground_y(p.x, p.z)


func _add_fig(team: String, pose: int, dress: int, p: Vector3, yaw: float) -> void:
	var fig: MeshInstance3D = CrewFigure.make(team, pose, dress)
	fig.scale = Vector3.ONE * SCALE
	add_child(fig)
	fig.global_position = Vector3(p.x, _gy(p), p.z)
	fig.rotation.y = yaw
	_crew.append({"node": fig, "team": team, "dress": dress, "pose": pose, "phase": randf() * 2.0})


## A trolley accumulator: a low four-wheeled cart carrying a battery box, a towing handle, and a heavy cable
## running to the aircraft's starter socket.
func _build_trolley(team: String, p: Vector3, socket: Vector3) -> void:
	_trolley = Node3D.new()
	add_child(_trolley)
	_trolley.global_position = Vector3(p.x, _gy(p), p.z)
	_trolley.rotation.y = atan2(-_away.x, -_away.z)          # handle pointing away from the aircraft
	_trolley.scale = Vector3.ONE * SCALE
	var paint: Color = Color(0.24, 0.27, 0.18) if team != "Axis" else Color(0.34, 0.35, 0.33)
	var dark := Color(0.08, 0.08, 0.08)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(0.78, 0.08, 1.45), Vector3(0, 0.30, 0), dark, Vector3.ZERO, false))         # chassis
	parts.append(GroundKit.box_part(Vector3(0.72, 0.46, 1.10), Vector3(0, 0.58, 0.05), paint))                         # battery box
	parts.append(GroundKit.box_part(Vector3(0.76, 0.05, 1.14), Vector3(0, 0.83, 0.05), paint.darkened(0.15), Vector3(0, 0, 0), false))   # lid
	parts.append(GroundKit.box_part(Vector3(0.30, 0.10, 0.18), Vector3(0.18, 0.90, -0.30), Color(0.55, 0.12, 0.10), Vector3.ZERO, false))   # terminal cover
	parts.append(GroundKit.box_part(Vector3(0.40, 0.18, 0.02), Vector3(0, 0.62, -0.51), Color(0.85, 0.80, 0.65), Vector3.ZERO, false))   # stencilled plate
	for wz in [-0.5, 0.5]:
		for wx in [-0.40, 0.40]:
			parts.append(GroundKit.cyl_part(0.17, 0.17, 0.09, Vector3(wx, 0.17, wz), dark, Vector3(0, 0, 90), 10, false))
	parts.append(GroundKit.cyl_part(0.025, 0.025, 1.0, Vector3(0, 0.42, -1.12), dark, Vector3(-75, 0, 0), 6, false))   # drawbar
	parts.append(GroundKit.cyl_part(0.03, 0.03, 0.32, Vector3(0, 0.55, -1.58), dark, Vector3(0, 0, 90), 6, false))     # T-handle
	var mi := MeshInstance3D.new()
	mi.mesh = AirfieldAssets._build(parts)
	_trolley.add_child(mi)
	# the cable: from the terminal cover, sagging along the ground, up to the socket in the fuselage side
	var start: Vector3 = _trolley.to_global(Vector3(0.18, 0.92, -0.30))
	var mid: Vector3 = (start + socket) * 0.5
	mid.y = _gy(mid) + 0.08
	var sock: Vector3 = Vector3(socket.x, _gy(socket) + 1.4, socket.z)
	_cable = MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(GroundKit.mat(Color(0.05, 0.05, 0.05), false))
	var pts: Array = []
	for i in 9:
		var t: float = float(i) / 8.0
		var q: Vector3 = (1.0 - t) * (1.0 - t) * start + 2.0 * (1.0 - t) * t * mid + t * t * sock
		pts.append(q)
	for i in 8:
		_tube(st, pts[i], pts[i + 1], 0.045)
	_cable.mesh = st.commit()
	add_child(_cable)


func _tube(st: SurfaceTool, a: Vector3, b: Vector3, r: float) -> void:
	var d: Vector3 = (b - a).normalized()
	var side: Vector3 = d.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized() * r
	var up: Vector3 = side.cross(d).normalized() * r
	var ring: Array = [side, up, -side, -up]
	for k in 4:
		var s0: Vector3 = ring[k]
		var s1: Vector3 = ring[(k + 1) % 4]
		var n: Vector3 = (s0 + s1).normalized()
		st.set_normal(n)
		st.add_vertex(a + s0)
		st.add_vertex(b + s0)
		st.add_vertex(b + s1)
		st.add_vertex(a + s0)
		st.add_vertex(b + s1)
		st.add_vertex(a + s1)


func _line(a: Vector3, b: Vector3, r: float, col: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(GroundKit.mat(col, false))
	var m: Vector3 = (a + b) * 0.5
	m.y -= 0.12
	_tube(st, a, m, r)
	_tube(st, m, b, r)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	return mi


## A wooden wheel chock: a wedge with a rope eye, at aircraft scale.
func _build_chock(p: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = Vector3(p.x, _gy(p), p.z)
	n.rotation.y = atan2(-_fwd.x, -_fwd.z) + PI * 0.5
	n.scale = Vector3.ONE * SCALE
	var wood := Color(0.42, 0.30, 0.17)
	var parts: Array = []
	var w := MeshInstance3D.new()
	w.mesh = GroundKit.prism_mesh(0.5, 0.32, 0.26)
	w.material_override = GroundKit.mat(wood, false)
	n.add_child(w)
	parts.append(GroundKit.box_part(Vector3(0.52, 0.06, 0.34), Vector3(0, 0.03, 0), wood.darkened(0.2), Vector3.ZERO, false))
	var b := MeshInstance3D.new()
	b.mesh = AirfieldAssets._build(parts)
	n.add_child(b)
	return n


func _set_pose(c: Dictionary, pose: int) -> void:
	if int(c["pose"]) == pose:
		return
	c["pose"] = pose
	(c["node"] as MeshInstance3D).mesh = CrewFigure.mesh(String(c["team"]), pose, int(c["dress"]))


func _process(delta: float) -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		queue_free()
		return
	_t += delta
	match _state:
		0:
			if aircraft.throttle > 0.12 or aircraft.speed > 1.0:
				_state = 1
				_t = 0.0
				for c in _chocks:
					(c as Node3D).queue_free()      # chocks away
				_chocks.clear()
				if is_instance_valid(_cable):
					_cable.queue_free()             # trolley-acc unplugged
			else:
				# idle fidgets: the man at the wingtip turns now and then
				if fmod(_t, 7.0) < delta and _crew.size() > 2:
					var c2: Dictionary = _crew[2]
					_set_pose(c2, CrewFigure.Pose.HIPS if int(c2["pose"]) != CrewFigure.Pose.HIPS else CrewFigure.Pose.STAND)
		1:
			# walk clear: out to the side and a little back; the last man stops at a safe distance and waves
			_walk_t += delta
			var wdir: Vector3 = (_away * 1.6 - _fwd * 0.4).normalized()
			var yaw: float = atan2(-wdir.x, -wdir.z)
			for i in _crew.size():
				var c: Dictionary = _crew[i]
				var fig: Node3D = c["node"]
				if i == _crew.size() - 1 and _t > 3.5:
					_set_pose(c, CrewFigure.Pose.WAVE)
					fig.rotation.y = lerp_angle(fig.rotation.y, atan2(_away.x, _away.z), clampf(delta * 3.0, 0.0, 1.0))
					continue
				if _t < 0.3 * float(i):
					continue              # they don't all set off at once
				var stride: bool = fmod(_walk_t * 2.6 + float(c["phase"]), 2.0) < 1.0
				_set_pose(c, CrewFigure.Pose.WALK_A if stride else CrewFigure.Pose.WALK_B)
				fig.rotation.y = lerp_angle(fig.rotation.y, yaw, clampf(delta * 4.0, 0.0, 1.0))
				var np: Vector3 = fig.global_position + wdir * 1.6 * SCALE * delta
				np.y = _gy(np)
				fig.global_position = np
			if is_instance_valid(_trolley) and _t < 8.0:
				# the trolley-acc is hauled away by its handle
				var tp: Vector3 = _trolley.global_position + _away * 1.1 * delta
				tp.y = _gy(tp)
				_trolley.global_position = tp
			if _t > 16.0 or not aircraft.on_ground:
				_state = 2
				for c in _crew:
					if int(c["pose"]) != CrewFigure.Pose.WAVE:
						_set_pose(c, CrewFigure.Pose.STAND)
		2:
			if _t > 40.0 or (not aircraft.on_ground and aircraft.altitude_agl > 120.0):
				queue_free()
