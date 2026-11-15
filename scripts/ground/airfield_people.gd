class_name AirfieldPeople
extends RefCounted
## Men on the airfield: ground crew walking between the dispersals, the fuel depot, the bomb dump and the watch
## office, pairs working at the parked aircraft, knots of men standing talking or sat on the grass, a runner, a
## squad marching in step past a saluting sentry, someone waving by the tower. When enemy aircraft come over low
## every man throws himself flat until they have gone (Driver).
## Purely visual (no collision, not targets) and almost free: all the men of a field are ONE MultiMesh of one
## figure mesh, and every movement - the stride, the turn at the end of the beat, the gestures - is done in the
## vertex shader (shaders/airfield_people.gdshader). Nothing is processed per frame on the CPU.
## Called from AirfieldActivity.populate. The earlier CrewFigure groups (a mesh per pose, swapped to "animate",
## several draw calls each) were removed for their cost; this replaces them.

## Aircraft and vehicles are drawn about 1.45x life size, so a 1.78 m man is drawn at the same scale and stands
## the right height against a wing, a wheel or a lorry cab. (Set SCALE to 1.0 for a literal 1.78 m.)
const SCALE: float = 1.45
const HEIGHT_M: float = 1.78
const FIG_H: float = 1.89             # the mesh as built, boots to crown
const MAN: float = SCALE * HEIGHT_M / FIG_H

enum Kind { WALK, TALK, WORK, WAVE, RUN, MARCH, SIT, SALUTE }

const RUNWAY_CLEAR: float = 20.0      # nobody stands or walks this close to a runway edge
const VIEW_RANGE: float = 1400.0

static var _mesh: ArrayMesh
static var _shader: Shader
static var _mats: Dictionary = {}


class _Acc:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var i := PackedInt32Array()


static func _part(acc: _Acc, m: PrimitiveMesh, xf: Transform3D, col: Color, part: int, limb: int, lower: bool) -> void:
	var arr: Array = m.get_mesh_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var base: int = acc.v.size()
	var nb: Basis = xf.basis.inverse().transposed()
	var lin: Color = col.srgb_to_linear()
	var vc := Color(lin.r, lin.g, lin.b, float(part) / 10.0)
	var tag := Vector2(float(limb), 1.0 if lower else 0.0)
	for k in vs.size():
		acc.v.append(xf * vs[k])
		acc.n.append((nb * ns[k]).normalized())
		acc.c.append(vc)
		acc.uv.append(tag)
	for k in idx:
		acc.i.append(base + k)


static func _cyl(acc: _Acc, x: float, y0: float, y1: float, r0: float, r1: float, part: int, limb: int, lower: bool, squash: float = 1.0) -> void:
	var cm := CylinderMesh.new()
	cm.bottom_radius = r0
	cm.top_radius = r1
	cm.height = y1 - y0
	cm.radial_segments = 7
	cm.rings = 1
	_part(acc, cm, Transform3D(Basis.from_scale(Vector3(1.0, 1.0, squash)), Vector3(x, (y0 + y1) * 0.5, 0.0)), Color.WHITE, part, limb, lower)


static func _ball(acc: _Acc, c: Vector3, r: float, sc: Vector3, part: int, limb: int, lower: bool, col: Color = Color.WHITE) -> void:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 8
	sm.rings = 5
	_part(acc, sm, Transform3D(Basis.from_scale(sc), c), col, part, limb, lower)


static func _box(acc: _Acc, size: Vector3, c: Vector3, col: Color, part: int, limb: int, lower: bool, bas: Basis = Basis.IDENTITY) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_part(acc, bm, Transform3D(bas, c), col, part, limb, lower)


## The one figure: standing to attention, arms at his sides, in the proportions of CrewFigure. One surface; the
## shader poses and colours it (see the header of airfield_people.gdshader for what UV and COLOR.a carry).
static func figure_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var a := _Acc.new()
	var boot := Color(0.07, 0.06, 0.05)
	var belt := Color(0.10, 0.09, 0.07)
	for side in [-1.0, 1.0]:
		var leg: int = 1 if side < 0.0 else 2
		var arm: int = 3 if side < 0.0 else 4
		var lx: float = side * 0.10
		_cyl(a, lx, 0.49, 0.94, 0.070, 0.085, 2, leg, false)                 # thigh
		_ball(a, Vector3(lx, 0.93, 0.0), 0.088, Vector3.ONE, 2, leg, false) # hip joint
		_ball(a, Vector3(lx, 0.49, 0.0), 0.071, Vector3.ONE, 2, leg, false) # knee: one rounded joint both halves turn about
		_ball(a, Vector3(lx, 0.075, 0.0), 0.060, Vector3.ONE, 8, leg, true) # ankle
		_ball(a, Vector3(lx, 0.045, -0.165), 0.055, Vector3(1.0, 0.80, 1.0), 0, leg, true, boot)   # rounded toe
		_cyl(a, lx, 0.06, 0.49, 0.055, 0.068, 8, leg, true)                  # shin (a jackboot on a German soldier)
		_box(a, Vector3(0.11, 0.09, 0.27), Vector3(lx, 0.045, -0.06), boot, 0, leg, true)
		var sx: float = side * 0.225
		_ball(a, Vector3(sx, 1.52, 0.0), 0.065, Vector3.ONE, 1, arm, false)  # shoulder
		_cyl(a, sx, 1.23, 1.52, 0.050, 0.058, 1, arm, false)                 # upper arm
		_ball(a, Vector3(sx, 1.23, 0.0), 0.051, Vector3.ONE, 1, arm, false)  # elbow
		_ball(a, Vector3(sx, 0.96, 0.0), 0.041, Vector3.ONE, 1, arm, true)   # wrist
		_cyl(a, sx, 0.96, 1.23, 0.040, 0.048, 1, arm, true)                  # forearm
		_ball(a, Vector3(sx, 0.915, 0.0), 0.045, Vector3.ONE, 4, arm, true)  # hand
	_cyl(a, 0.0, 0.90, 1.09, 0.172, 0.168, 2, 0, false, 0.64)                                   # hips: rounded, not a box
	_ball(a, Vector3(0.0, 0.91, 0.0), 0.172, Vector3(1.0, 0.50, 0.64), 2, 0, false)             # seat
	_ball(a, Vector3(0.0, 1.565, 0.0), 0.200, Vector3(1.0, 0.30, 0.62), 1, 0, true)             # the slope of the shoulders
	_box(a, Vector3(0.36, 0.055, 0.24), Vector3(0.0, 1.10, 0.0), belt, 0, 0, true)
	_cyl(a, 0.0, 1.07, 1.57, 0.17, 0.20, 1, 0, true, 0.62)                                      # chest
	_cyl(a, 0.0, 1.55, 1.67, 0.05, 0.05, 4, 0, true)                                            # neck
	_ball(a, Vector3(0.0, 1.77, 0.0), 0.11, Vector3(0.92, 1.05, 1.0), 4, 0, true)               # head
	_ball(a, Vector3(0.0, 1.79, 0.02), 0.108, Vector3(0.95, 0.70, 1.0), 5, 0, true)             # hair
	_box(a, Vector3(0.11, 0.075, 0.25), Vector3(0.0, 1.875, 0.0), Color.WHITE, 3, 0, true, Basis(Vector3.BACK, -0.18))   # side cap
	# soldiers only (the shader folds away whichever a man does not wear): the British Mk II "tin hat" - a shallow
	# bowl with a wide brim - the German Stahlhelm - a deep bowl flared over the ears and neck - and a slung rifle
	_ball(a, Vector3(0.0, 1.855, 0.0), 0.125, Vector3(1.0, 0.50, 1.0), 6, 0, true)
	_cyl(a, 0.0, 1.835, 1.853, 0.195, 0.150, 6, 0, true)
	_ball(a, Vector3(0.0, 1.815, 0.005), 0.132, Vector3(1.0, 0.86, 1.08), 7, 0, true)
	var skirt := CylinderMesh.new()
	skirt.bottom_radius = 0.158
	skirt.top_radius = 0.130
	skirt.height = 0.085
	skirt.radial_segments = 8
	skirt.rings = 1
	_part(a, skirt, Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.80)), Vector3(0.0, 1.765, 0.055)), Color.WHITE, 7, 0, true)
	var rifle_b := Basis(Vector3.BACK, 0.10) * Basis(Vector3.RIGHT, -0.10)
	_box(a, Vector3(0.045, 1.10, 0.065), Vector3(-0.20, 1.30, 0.135), Color(0.25, 0.15, 0.08), 9, 0, true, rifle_b)
	_box(a, Vector3(0.03, 0.34, 0.03), Vector3(-0.255, 1.99, 0.065), Color(0.07, 0.07, 0.08), 9, 0, true, rifle_b)        # barrel
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = a.v
	arr[Mesh.ARRAY_NORMAL] = a.n
	arr[Mesh.ARRAY_COLOR] = a.c
	arr[Mesh.ARRAY_TEX_UV] = a.uv
	arr[Mesh.ARRAY_INDEX] = a.i
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _mesh


static func _material(team: String) -> ShaderMaterial:
	if _mats.has(team):
		return _mats[team]
	if _shader == null:
		_shader = load("res://shaders/airfield_people.gdshader")
	var sm := ShaderMaterial.new()
	sm.shader = _shader
	for d in CrewFigure.DRESSES:
		var p: Dictionary = CrewFigure._palette(team, d)
		for pair in [["top", "top"], ["leg", "legs"], ["skin", "skin"], ["hair", "hair"]]:
			var l: Color = (p[pair[1]] as Color).srgb_to_linear()
			sm.set_shader_parameter("%s%d" % [pair[0], d], Vector3(l.r, l.g, l.b))
	var cap: Color = (CrewFigure._palette(team, 0)["cap"] as Color).srgb_to_linear()
	sm.set_shader_parameter("cap_col", Vector3(cap.r, cap.g, cap.b))
	# the soldiers: khaki battledress and a dull green tin hat on a British field; Luftwaffe blue-grey, a dark
	# blue-grey Stahlhelm and black jackboots on a German one
	var axis: bool = team == "Axis"
	var s_top: Color = (Color(0.33, 0.37, 0.44) if axis else Color(0.45, 0.40, 0.25)).srgb_to_linear()
	var s_leg: Color = (Color(0.31, 0.35, 0.42) if axis else Color(0.43, 0.38, 0.24)).srgb_to_linear()
	var s_hel: Color = (Color(0.21, 0.24, 0.29) if axis else Color(0.31, 0.33, 0.22)).srgb_to_linear()
	sm.set_shader_parameter("soldier_top", Vector3(s_top.r, s_top.g, s_top.b))
	sm.set_shader_parameter("soldier_leg", Vector3(s_leg.r, s_leg.g, s_leg.b))
	sm.set_shader_parameter("helmet_col", Vector3(s_hel.r, s_hel.g, s_hel.b))
	sm.set_shader_parameter("axis_side", 1.0 if axis else 0.0)
	_mats[team] = sm
	return sm


## XZ distance from local point p to the nearest paved strip (taxiway or runway; pads and other discs excepted).
static func _taxiway_clear(af: Airfield, p: Vector3) -> float:
	var q := Vector2(p.x, p.z)
	var best: float = 1.0e9
	for seg in af._paved:
		var s0 := Vector2((seg[0] as Vector3).x, (seg[0] as Vector3).z)
		var s1 := Vector2((seg[1] as Vector3).x, (seg[1] as Vector3).z)
		if s0.distance_to(s1) < 1.0:
			continue
		best = minf(best, Geometry2D.get_closest_point_to_segment(q, s0, s1).distance_to(q) - float(seg[2]))
	return best


## The plan for one field: [[world position, world direction he faces / walks, Kind, beat length in metres,
## phase (-1 = his own), speed in mesh m/s (0 = his own), soldier (optional, default: the drill squad and sentries)], ...].
## `pads`, `depot`, `dump` and `tower` are world points, `rws` the runways (AirfieldActivity.runways, local frame).
static func plan(af: Airfield, axf: Transform3D, rws: Array, pads: Array, depot: Vector3, dump: Vector3, tower: Vector3, seed_v: int, density: float = 1.0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var inv: Transform3D = axf.affine_inverse()
	var men: Array = []
	var stand := func(p: Vector3, face: Vector3, kind: int) -> bool:
		var lp: Vector3 = inv * p
		if not AirfieldActivity.leg_clear(rws, lp, lp, RUNWAY_CLEAR) or _taxiway_clear(af, lp) < 2.5:
			return false
		face.y = 0.0
		men.append([p, face.normalized() if face.length() > 0.01 else Vector3.FORWARD, kind, 0.0, -1.0, 0.0])
		return true
	var walk := func(p0: Vector3, p1: Vector3) -> bool:
		var d: Vector3 = p1 - p0
		d.y = 0.0
		var ln: float = d.length()
		if ln < 10.0 or ln > 260.0 or not AirfieldActivity.leg_clear(rws, inv * p0, inv * p1, RUNWAY_CLEAR):
			return false
		men.append([p0, d / ln, Kind.WALK, ln, -1.0, 0.0])
		return true
	var clear_line := func(p0: Vector3, p1: Vector3, margin: float) -> bool:
		return AirfieldActivity.leg_clear(rws, inv * p0, inv * p1, RUNWAY_CLEAR + margin) and _taxiway_clear(af, inv * p0) > margin \
			and _taxiway_clear(af, inv * p1) > margin and _taxiway_clear(af, inv * ((p0 + p1) * 0.5)) > margin
	# a knot of men standing talking, facing each other
	var knot := func(c: Vector3, count: int, wave: bool) -> void:
		var a0: float = rng.randf() * TAU
		for k in count:
			var a: float = a0 + TAU * float(k) / float(count) + rng.randf_range(-0.25, 0.25)
			var p: Vector3 = c + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.9, 1.4) * SCALE
			stand.call(p, c - p, Kind.WAVE if wave and k == 0 else Kind.TALK)
	# at the parked aircraft: one or two bent over a job at the edge of the pad, a third looking on
	var n_pads: int = mini(pads.size(), int(round(10.0 * density)))
	for i in n_pads:
		var pad: Vector3 = pads[i]
		for _try in 6:
			var a: float = rng.randf() * TAU
			var out := Vector3(cos(a), 0.0, sin(a))
			var p: Vector3 = pad + out * rng.randf_range(9.0, 12.5)
			if not stand.call(p, pad - p, Kind.WORK):
				continue
			var side := Vector3(-out.z, 0.0, out.x)
			if i % 2 == 0:
				stand.call(p + side * 1.5 * SCALE, pad - p, Kind.WORK)
			stand.call(p - side * 1.4 * SCALE + out * 1.2, (pad - p) + side * 4.0, Kind.TALK)
			break
	# men walking from pad to pad, clear of the pads themselves
	var walkers: int = 0
	for i in pads.size() - 1:
		if walkers >= int(round(12.0 * density)):
			break
		var p0: Vector3 = pads[i]
		var p1: Vector3 = pads[i + 1]
		var d: Vector3 = p1 - p0
		d.y = 0.0
		if d.length() < 25.0:
			continue
		var side: Vector3 = Vector3(-d.z, 0.0, d.x).normalized() * (13.0 if i % 2 == 0 else -13.0)
		if walk.call(p0 + side + d.normalized() * 6.0, p1 + side - d.normalized() * 6.0):
			walkers += 1
	# the fuel depot, the bomb dump and the watch office: men standing about, and beats out to the nearest pads
	for hub in [[depot + Vector3(16.0, 0.0, 9.0), 3, false], [tower + Vector3(11.0, 0.0, 7.0), 3, true], [dump + Vector3(-12.0, 0.0, 3.0), 2, false]]:
		var c: Vector3 = hub[0]
		knot.call(c, int(hub[1]), bool(hub[2]))
		var a: float = rng.randf() * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		for _try in 4:                                   # a man pacing up and down nearby
			if walk.call(c + dir * 5.0, c + dir * rng.randf_range(28.0, 45.0)):
				break
			dir = dir.rotated(Vector3.UP, PI * 0.5)
		if density < 0.75:
			continue
		var near: Array = pads.duplicate()
		near.sort_custom(func(x: Vector3, z: Vector3) -> bool: return x.distance_squared_to(c) < z.distance_squared_to(c))
		for k in mini(2, near.size()):
			var to: Vector3 = (near[k] as Vector3) - c
			to.y = 0.0
			if to.length() > 30.0:
				walk.call(c + to.normalized() * 6.0, (near[k] as Vector3) - to.normalized() * 14.0)
	# off duty: two or three sat on the grass a little way from some of the pads
	var lounging: int = 0
	for i in range(1, pads.size(), 2):
		if lounging >= int(round(4.0 * density)):
			break
		var pad2: Vector3 = pads[i]
		for _try in 5:
			var a2: float = rng.randf() * TAU
			var c2: Vector3 = pad2 + Vector3(cos(a2), 0.0, sin(a2)) * rng.randf_range(19.0, 26.0)
			if _taxiway_clear(af, inv * c2) < 7.0 or not AirfieldActivity.leg_clear(rws, inv * c2, inv * c2, RUNWAY_CLEAR + 8.0):
				continue
			var close: bool = false
			for q in pads:
				if (q as Vector3).distance_to(c2) < 17.0:
					close = true
			if close:
				continue
			var a0: float = rng.randf() * TAU
			var cnt: int = 2 + rng.randi() % 2
			for k in cnt:
				var a3: float = a0 + TAU * float(k) / float(cnt) + rng.randf_range(-0.3, 0.3)
				var sp: Vector3 = c2 + Vector3(cos(a3), 0.0, sin(a3)) * rng.randf_range(1.3, 1.9) * SCALE
				men.append([sp, ((c2 - sp) + Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))).normalized(), Kind.SIT, 0.0, -1.0, 0.0])
			lounging += 1
			break
	# a runner with a message between the watch office and the depot (or out to a pad)
	var run_from: Vector3 = tower + Vector3(11.0, 0.0, 7.0)
	var run_to: Array = [depot + Vector3(16.0, 0.0, 9.0), dump + Vector3(-12.0, 0.0, 3.0)]
	for q in pads:
		run_to.append((q as Vector3) + Vector3(12.0, 0.0, 0.0))
	for q in run_to:
		var rd: Vector3 = (q as Vector3) - run_from
		rd.y = 0.0
		var rl: float = rd.length()
		if rl < 60.0 or rl > 420.0 or not AirfieldActivity.leg_clear(rws, inv * run_from, inv * (q as Vector3), RUNWAY_CLEAR):
			continue
		men.append([run_from + rd.normalized() * 8.0, rd / rl, Kind.RUN, rl - 16.0, -1.0, rng.randf_range(3.3, 3.9)])
		break
	# drill: a squad marching in step up and down a clear stretch near the watch office, an NCO beside it, and a
	# sentry at attention by the line who salutes
	var files: int = 3
	var ranks: int = 2 if density < 0.75 else 3
	var m_len: float = 70.0
	var gap: float = 1.15 * SCALE
	for _try in 16:
		var a4: float = rng.randf() * TAU
		var dir4 := Vector3(cos(a4), 0.0, sin(a4))
		var side4 := Vector3(-dir4.z, 0.0, dir4.x)
		var start: Vector3 = tower + Vector3(cos(a4 + 1.3), 0.0, sin(a4 + 1.3)) * rng.randf_range(35.0, 80.0)
		var back: Vector3 = start - dir4 * gap * float(ranks)
		if not clear_line.call(back, start + dir4 * m_len, 6.0):
			continue
		var m_ph: float = rng.randf()
		for r in ranks:
			for f in files:
				men.append([start - dir4 * gap * float(r) + side4 * gap * (float(f) - 1.0), dir4, Kind.MARCH, m_len, m_ph, 1.45])
		men.append([start - dir4 * gap * 0.5 + side4 * gap * 2.4, dir4, Kind.MARCH, m_len, m_ph, 1.45])          # the NCO
		var sp4: Vector3 = start + dir4 * m_len * 0.5 - side4 * (gap * 1.0 + 5.0)
		men.append([sp4, side4, Kind.SALUTE, 0.0, -1.0, 0.0])
		break
	# a kickabout on the grass near the watch office: five men chasing a ball every which way
	if density >= 0.75:
		for _try in 10:
			var a5: float = rng.randf() * TAU
			var kc: Vector3 = tower + Vector3(cos(a5), 0.0, sin(a5)) * rng.randf_range(45.0, 110.0)
			if _taxiway_clear(af, inv * kc) < 28.0 or not AirfieldActivity.leg_clear(rws, inv * kc, inv * kc, RUNWAY_CLEAR + 30.0):
				continue
			for k in 5:
				var a6: float = TAU * float(k) / 5.0 + rng.randf_range(-0.5, 0.5)
				var kd := Vector3(cos(a6), 0.0, sin(a6))
				var kl: float = rng.randf_range(11.0, 19.0)
				men.append([kc - kd * kl * 0.5 + Vector3(rng.randf_range(-3.0, 3.0), 0.0, rng.randf_range(-3.0, 3.0)), kd, Kind.RUN, kl, -1.0, rng.randf_range(2.4, 3.2), false])
			break
	# a file of airmen walking out from the depot together
	var file_to: Vector3 = (pads[0] as Vector3) if not pads.is_empty() else tower
	var fd: Vector3 = file_to - depot
	fd.y = 0.0
	if fd.length() > 60.0 and AirfieldActivity.leg_clear(rws, inv * depot, inv * file_to, RUNWAY_CLEAR):
		var fl: float = minf(fd.length() - 30.0, 180.0)
		var fph: float = rng.randf()
		for k in 4:
			men.append([depot + fd.normalized() * (10.0 + float(k) * 1.3 * SCALE) + Vector3(-fd.z, 0.0, fd.x).normalized() * 9.0, fd.normalized(), Kind.WALK, fl, fph, 1.45, false])
	# a sentry at the bomb dump
	stand.call(dump + Vector3(-20.0, 0.0, -6.0), tower - dump, Kind.SALUTE)
	return men


## Per field: watches for enemy aircraft low over the airfield and drives the two per-instance shader values -
## `alarm` (everyone flat) and `t_off` (the field's clock held while they lie there). Checks twice a second and only
## touches the shader while something is changing.
class Driver extends Node:
	var mi: MultiMeshInstance3D
	var team: String = ""
	var reach: float = 600.0
	var _check: float = 0.0
	var _threat_t: float = 0.0       # seconds the men stay down after the last enemy seen
	var _alarm: float = 0.0
	var _off: float = 0.0
	var demo: bool = false           # the showcase drives the alarm itself
	var demo_alarm: bool = false

	func _process(delta: float) -> void:
		_check -= delta
		if _check <= 0.0:
			_check = 0.5
			if (demo_alarm if demo else _enemy_overhead()):
				_threat_t = 0.6 if demo else 7.0
		_threat_t = maxf(_threat_t - delta, 0.0)
		var want: float = 1.0 if _threat_t > 0.0 else 0.0
		if _alarm == want and want == 0.0:
			return
		_alarm = move_toward(_alarm, want, delta * (1.8 if want > _alarm else 0.55))
		_off += delta * smoothstep(0.0, 0.3, _alarm)
		mi.set_instance_shader_parameter("alarm", _alarm)
		mi.set_instance_shader_parameter("t_off", _off)

	func _enemy_overhead() -> bool:
		var c: Vector3 = mi.global_position
		for n in get_tree().get_nodes_in_group("aircraft"):
			var ac: Aircraft = n as Aircraft
			if ac == null or ac.team == team or ac.state != Aircraft.State.ALIVE or ac.on_ground:
				continue
			var d: Vector3 = ac.global_position - c
			if d.y < 450.0 and Vector2(d.x, d.z).length() < reach:
				return true
		return false


static func populate(container: Node3D, af: Airfield, axf: Transform3D, y: float, team: String, rws: Array, pads: Array, depot: Vector3, dump: Vector3, tower: Vector3) -> MultiMeshInstance3D:
	var density: float = 0.5 if GameState.quality <= 0 else 1.0
	var men: Array = plan(af, axf, rws, pads, depot, dump, tower, hash(af.airfield_name) + 1940, density)
	return spawn(container, men, Vector3(axf.origin.x, y + 0.01, axf.origin.z), team, hash(af.airfield_name) + 7, af.airfield_name, false)


## Build the one MultiMesh for a planned set of men (see plan() for the entries). `origin` is the node's position:
## instance positions are stored relative to it, so they stay small. On an airfield the ground is one level
## (`follow_ground` false); in a camp each man stands on the terrain under him and a beat follows the slope.
static func spawn(container: Node3D, men: Array, origin: Vector3, team: String, seed_v: int, label: String, follow_ground: bool) -> MultiMeshInstance3D:
	if men.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = figure_mesh()
	mm.instance_count = men.size()
	var lo := Vector3(1.0e9, 1.0e9, 1.0e9)
	var hi := Vector3(-1.0e9, -1.0e9, -1.0e9)
	for i in men.size():
		var m: Array = men[i]
		var w0: Vector3 = m[0]
		var dir: Vector3 = m[1]
		var ln: float = float(m[3])
		var p: Vector3 = w0 - origin
		p.y = 0.0
		var p1: Vector3 = p + dir * ln
		if follow_ground:
			p.y = GroundKit.ground_y(w0.x, w0.z) + 0.01 - origin.y
			p1.y = p.y
			if ln > 1.0:
				var w1: Vector3 = w0 + dir * ln
				p1.y = GroundKit.ground_y(w1.x, w1.z) + 0.01 - origin.y
				dir = (p1 - p).normalized()
		var bas: Basis = Basis.looking_at(dir, Vector3.UP).scaled(Vector3.ONE * MAN)
		mm.set_instance_transform(i, Transform3D(bas, p))
		var spd: float = float(m[5]) if float(m[5]) > 0.0 else rng.randf_range(1.25, 1.65)     # mesh metres a second
		var ph: float = float(m[4]) if float(m[4]) >= 0.0 else rng.randf()
		var dress: int = rng.randi() % CrewFigure.DRESSES
		var soldier: bool = bool(m[6]) if m.size() > 6 else (int(m[2]) == Kind.MARCH or int(m[2]) == Kind.SALUTE)
		mm.set_instance_custom_data(i, Color(p.distance_to(p1) / MAN, spd, ph, float(int(m[2]) * 8 + (4 if soldier else 0) + dress)))
		for q in [p, p1]:
			lo = Vector3(minf(lo.x, (q as Vector3).x), minf(lo.y, (q as Vector3).y), minf(lo.z, (q as Vector3).z))
			hi = Vector3(maxf(hi.x, (q as Vector3).x), maxf(hi.y, (q as Vector3).y), maxf(hi.z, (q as Vector3).z))
	mm.custom_aabb = AABB(lo - Vector3(4.0, 1.0, 4.0), hi - lo + Vector3(8.0, 5.0, 8.0))
	var mi := MultiMeshInstance3D.new()
	mi.name = "AirfieldPeople"
	mi.multimesh = mm
	mi.material_override = _material(team)
	mi.position = origin
	mi.visibility_range_end = VIEW_RANGE
	mi.visibility_range_end_margin = 100.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	container.add_child(mi)
	var drv := Driver.new()
	drv.name = "Driver"
	drv.mi = mi
	drv.team = team
	drv.reach = maxf((hi - lo).length() * 0.5, 250.0) + 350.0
	mi.add_child(drv)
	if label != "":
		print("[people] %s: %d men" % [label, men.size()])
	return mi


## Soldiers in an army camp (ArmyCampKit.build; `axf` is the camp's frame, local x across and z along, the gate at
## +z): sentries at the gate and the dumps, two squads at drill on the tracks, crews at the tanks, lorries and guns,
## men sat and standing about between the tent lines, a queue at the cookhouse, a kickabout, runners and walkers
## on the tracks. All in their side's service uniform; one MultiMesh for the whole camp.
static func populate_camp(container: Node3D, axf: Transform3D, team: String, seed_v: int) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var density: float = 0.5 if GameState.quality <= 0 else 1.0
	var men: Array = []
	var w := func(x: float, z: float) -> Vector3:
		return axf * Vector3(x, 0.0, z)
	var d := func(x: float, z: float) -> Vector3:
		return (axf.basis * Vector3(x, 0.0, z)).normalized()
	var one := func(x: float, z: float, fx: float, fz: float, kind: int) -> void:
		men.append([w.call(x, z), d.call(fx, fz), kind, 0.0, -1.0, 0.0, true])
	var beat := func(x: float, z: float, fx: float, fz: float, ln: float, kind: int, ph: float, spd: float) -> void:
		men.append([w.call(x, z), d.call(fx, fz), kind, ln, ph, spd, true])
	var knot := func(x: float, z: float, count: int, kind: int) -> void:
		var a0: float = rng.randf() * TAU
		for k in count:
			var a: float = a0 + TAU * float(k) / float(count) + rng.randf_range(-0.25, 0.25)
			var r: float = rng.randf_range(0.9, 1.5) * SCALE * (1.3 if kind == Kind.SIT else 1.0)
			one.call(x + cos(a) * r, z + sin(a) * r, -cos(a), -sin(a), kind)
	var squad := func(x: float, z: float, fx: float, fz: float, ln: float, files: int, ranks: int) -> void:
		var ph: float = rng.randf()
		var g: float = 1.15 * SCALE
		for r in ranks:
			for f in files:
				var off: float = (float(f) - float(files - 1) * 0.5) * g
				beat.call(x - fx * g * float(r) - fz * off, z - fz * g * float(r) + fx * off, fx, fz, ln, Kind.MARCH, ph, 1.45)
		beat.call(x + fx * g - fz * g * (float(files) * 0.5 + 1.0), z + fz * g + fx * g * (float(files) * 0.5 + 1.0), fx, fz, ln, Kind.MARCH, ph, 1.45)   # the sergeant
	var hz: float = ArmyCampKit.HZ
	# sentries: the gate, the ammunition and fuel dumps, the flagpole
	one.call(-6.0, hz + 3.0, 0.0, 1.0, Kind.SALUTE)
	one.call(6.0, hz + 3.0, 0.0, 1.0, Kind.SALUTE)
	one.call(-232.0, 58.0, 1.0, 0.0, Kind.SALUTE)
	one.call(232.0, 62.0, -1.0, 0.0, Kind.SALUTE)
	one.call(-86.0, 146.0, -1.0, 1.0, Kind.SALUTE)
	# drill on the tracks
	squad.call(-95.0, -60.0, 1.0, 0.0, 85.0, 3, 4 if density >= 0.75 else 2)
	squad.call(0.0, 185.0, 0.0, -1.0, 60.0, 3, 3 if density >= 0.75 else 2)
	# the tank park, the half-tracks and the lorries: crews at work between the rows, others looking on
	for i in range(0, 9, 2 if density >= 0.75 else 4):
		one.call(-210.0 + float(i) * 11.0 + 4.6, -110.0 + 6.0, -1.0, -0.6, Kind.WORK)
		one.call(-210.0 + float(i) * 11.0 + 6.4, -110.0 + 23.5, -1.0, -0.5, Kind.WORK if i % 4 == 0 else Kind.TALK)
	knot.call(-150.0, -64.0, 3, Kind.TALK)
	for i in range(1, 10, 3):
		one.call(70.0 + float(i) * 11.0 + 5.0, -110.0 + 5.5, -1.0, -0.4, Kind.WORK)
	beat.call(64.0, -102.5, 1.0, 0.0, 104.0, Kind.WALK, -1.0, 0.0)
	beat.call(172.0, -87.5, -1.0, 0.0, 104.0, Kind.WALK, -1.0, 0.0)
	# the battery: a detachment at each gun
	for i in range(0, 6, 1 if density >= 0.75 else 2):
		one.call(-200.0 + float(i) * 20.0 - 1.9, 43.5, 0.3, -1.0, Kind.WORK)
		one.call(-200.0 + float(i) * 20.0 + 2.1, 44.5, -0.3, -1.0, Kind.TALK if i % 2 == 0 else Kind.WORK)
	# the tent lines: men off duty sat and standing in the lanes between the rows, others walking along them
	for r in 7:
		var lane_z: float = 10.0 + float(r) * 11.0 + 5.5
		if density < 0.75 and r % 2 == 1:
			continue
		knot.call(34.0 + rng.randf_range(0.0, 100.0), lane_z, 2 + rng.randi() % 2, Kind.SIT)
		knot.call(34.0 + rng.randf_range(0.0, 100.0), lane_z, 2 + rng.randi() % 2, Kind.TALK if r % 3 != 0 else Kind.SIT)
		if r % 2 == 0:
			beat.call(28.0 if r % 4 == 0 else 150.0, lane_z + 1.5, 1.0 if r % 4 == 0 else -1.0, 0.0, 118.0, Kind.WALK, -1.0, 0.0)
	# the cookhouse queue outside the Nissen huts
	for k in (7 if density >= 0.75 else 4):
		one.call(-46.0 + float(k) * 0.95 * SCALE, 130.5, -1.0, 0.0, Kind.TALK)
	knot.call(-52.0, 127.0, 2, Kind.TALK)
	# a kickabout on the open ground, a runner along the cross track, men on the tracks
	for k in 6:
		var a1: float = TAU * float(k) / 6.0 + rng.randf_range(-0.5, 0.5)
		var kl: float = rng.randf_range(11.0, 19.0)
		beat.call(-62.0 - cos(a1) * kl * 0.5 + rng.randf_range(-3.0, 3.0), 84.0 - sin(a1) * kl * 0.5 + rng.randf_range(-3.0, 3.0), cos(a1), sin(a1), kl, Kind.RUN, -1.0, rng.randf_range(2.4, 3.2))
	beat.call(-210.0, 112.5, 1.0, 0.0, 190.0, Kind.RUN, -1.0, 3.6)
	beat.call(2.5, 200.0, 0.0, -1.0, 150.0, Kind.WALK, -1.0, 0.0)
	beat.call(-2.5, -40.0, 0.0, 1.0, 130.0, Kind.WALK, -1.0, 0.0)
	beat.call(40.0, -57.5, 1.0, 0.0, 200.0, Kind.WALK, -1.0, 0.0)
	beat.call(-30.0, 107.5, -1.0, 0.0, 170.0, Kind.WALK, -1.0, 0.0)
	var c: Vector3 = axf.origin
	var mi: MultiMeshInstance3D = spawn(container, men, Vector3(c.x, GroundKit.ground_y(c.x, c.z), c.z), team, seed_v + 3, "", true)
	if mi != null:
		mi.name = "CampPeople"
	return mi


## Debug showcase (main: --people-demo): every animation side by side, labelled, British on the left and German
## on the right, with a camera that tracks along the line and then pulls back while both groups take cover.
static func demo(host: Node3D, base: Vector3, fwd: Vector3, record_dir: String = "") -> void:
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var block: float = 46.0
	var mis: Array = []
	var caps: Array = []          # [text, world point] - drawn as 2D labels over the picture by the camera
	for t in 2:
		var team: String = "Allies" if t == 0 else "Axis"
		var o: Vector3 = base + right * (float(t) * block)
		var men: Array = []
		var caption := func(text: String, x: float, z: float) -> void:
			caps.append([text, o + right * x + fwd * z + Vector3(0.0, 3.1 if z < 8.0 else 4.6, 0.0)])
		var who := "RAF" if t == 0 else "LUFTWAFFE"
		caption.call(who + "  ground crew", 6.0, 9.0)
		men.append([o + right * 0.0, right, Kind.WALK, 12.0, -1.0, 0.0, false])
		men.append([o + right * 1.0 + fwd * 2.5, right, Kind.WALK, 10.0, -1.0, 0.0, false])
		caption.call("walk", 6.0, 0.0)
		men.append([o + right * 0.0 + fwd * 6.0, right, Kind.RUN, 14.0, -1.0, 3.6, false])
		caption.call("run", 7.0, 6.0)
		for k in 2:
			men.append([o + right * (16.0 + float(k) * 2.2), -fwd + right * (0.5 - float(k)), Kind.WORK, 0.0, -1.0, 0.0, false])
		caption.call("work", 17.0, 0.0)
		for k in 3:
			var a: float = TAU * float(k) / 3.0
			men.append([o + right * (16.5 + cos(a) * 1.7) + fwd * (6.0 + sin(a) * 1.7), -(right * cos(a) + fwd * sin(a)), Kind.TALK, 0.0, -1.0, 0.0, false])
		caption.call("talk", 16.5, 6.0)
		men.append([o + right * 22.0, -fwd, Kind.WAVE, 0.0, -1.0, 0.0, false])
		caption.call("wave", 22.0, 0.0)
		for k in 3:
			var a2: float = TAU * float(k) / 3.0 + 0.5
			men.append([o + right * (23.0 + cos(a2) * 2.2) + fwd * (6.0 + sin(a2) * 2.2), -(right * cos(a2) + fwd * sin(a2)), Kind.SIT, 0.0, -1.0, 0.0, false])
		caption.call("relaxed", 23.0, 6.0)
		for r in 2:
			for f in 3:
				men.append([o + right * (28.0 - float(r) * 1.7) + fwd * (-0.5 + float(f) * 1.7), right, Kind.MARCH, 11.0, 0.3, 1.45, true])
		caption.call("soldiers: march", 32.0, 0.0)
		men.append([o + right * 30.0 + fwd * 6.5, -fwd, Kind.SALUTE, 0.0, 0.31, 0.0, true])
		men.append([o + right * 32.5 + fwd * 6.5, -fwd, Kind.SALUTE, 0.0, 0.83, 0.0, true])
		caption.call("salute", 31.2, 6.5)
		men.append([o + right * 36.0 + fwd * 6.0, right, Kind.RUN, 6.0, -1.0, 3.0, true])
		var mi: MultiMeshInstance3D = spawn(host, men, o, team, 11 + t, "", false)
		mi.visibility_range_end = 0.0
		(mi.get_node("Driver") as Driver).demo = true
		mis.append(mi)
	var cam := DemoCam.new()
	cam.base = base
	cam.right = right
	cam.fwd = fwd
	cam.span = block + 36.0
	cam.mis = mis
	cam.caps = caps
	cam.record_dir = record_dir
	host.add_child(cam)


## The showcase camera: tracks along the line, then pulls back and calls the alarm (see demo()).
class DemoCam extends Camera3D:
	var base: Vector3
	var right: Vector3
	var fwd: Vector3
	var span: float = 80.0
	var mis: Array = []
	var caps: Array = []
	var _labels: Array = []
	var record_dir: String = ""      # save every frame here as a JPEG (run with --fixed-fps 30) and quit at the end
	var _t: float = 0.0
	var _n: int = 0
	const TRACK: float = 22.0        # seconds along the line
	const END: float = 34.0

	func _ready() -> void:
		fov = 38.0
		print("[people-demo] start frame %d" % Engine.get_frames_drawn())
		_place()
		make_current()
		var layer := CanvasLayer.new()
		layer.layer = 50
		add_child(layer)
		for c in caps:
			var l := Label.new()
			l.text = String(c[0])
			l.add_theme_font_size_override("font_size", 30 if not String(c[0]).contains("ground crew") else 40)
			l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
			l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
			l.add_theme_constant_override("outline_size", 8)
			layer.add_child(l)
			_labels.append(l)
		for h in get_tree().get_nodes_in_group("hud"):
			if h is CanvasItem:
				(h as CanvasItem).visible = false
			elif h is CanvasLayer:
				(h as CanvasLayer).visible = false

	func _process(delta: float) -> void:
		_t += delta
		if not current:
			make_current()
		_place()
		for i in _labels.size():
			var wp: Vector3 = caps[i][1]
			var l: Label = _labels[i]
			l.visible = not is_position_behind(wp)
			l.position = unproject_position(wp) - l.size * 0.5
		for m in mis:
			var drv: AirfieldPeople.Driver = (m as Node).get_node("Driver")
			drv.demo_alarm = _t > TRACK + 3.0 and _t < TRACK + 8.0
		if record_dir != "" and _t > 0.2:
			get_viewport().get_texture().get_image().save_jpg("%s/f_%04d.jpg" % [record_dir, _n], 0.9)
			_n += 1
		if _t > END:
			print("[people-demo] end frame %d, %d frames saved" % [Engine.get_frames_drawn(), _n])
			set_process(false)
			if record_dir != "":
				get_tree().quit()

	func _place() -> void:
		var k: float = smoothstep(0.0, 1.0, clampf(_t / TRACK, 0.0, 1.0))
		var wide: float = smoothstep(TRACK, TRACK + 2.5, _t)
		var x: float = lerpf(lerpf(7.0, span - 9.0, k), span * 0.5, wide)
		var look: Vector3 = base + right * x + fwd * 3.0 + Vector3(0.0, 1.5, 0.0)
		var pos: Vector3 = base + right * (x + 3.0) - fwd * lerpf(17.0, 60.0, wide) + Vector3(0.0, lerpf(2.6, 9.0, wide), 0.0)
		global_transform = Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)
