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

## The aircraft models are built at 1.1x life size (ModelSpecs "scale"), so a 1.78 m man is drawn at the same
## scale and stands the right height against a wing, an engine cowling or a wheel. (Was 1.45: next to a parked
## aircraft the men came out a third too big.)
const SCALE: float = 1.1
const HEIGHT_M: float = 1.78
const FIG_H: float = 1.89             # the mesh as built, boots to crown
const MAN: float = SCALE * HEIGHT_M / FIG_H

enum Kind { WALK, TALK, WORK, WAVE, RUN, MARCH, SIT, SALUTE, PATIENT, MEDIC, BEARER, CARRIED, DOCTOR, BEARER_FRONT, PASSER, BALL, SMOKER, REACH, KNEEL, ON_WING }

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


static func _part(acc: _Acc, m: PrimitiveMesh, xf: Transform3D, col: Color, part: int, limb: int, lower: bool, item: int = 0) -> void:
	var arr: Array = m.get_mesh_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var base: int = acc.v.size()
	var nb: Basis = xf.basis.inverse().transposed()
	var lin: Color = col.srgb_to_linear()
	var vc := Color(lin.r, lin.g, lin.b, float(part) / 10.0)
	var tag := Vector2(float(limb), float(item) if item >= 2 else (1.0 if lower else 0.0))
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
	# a cigarette between the fingers of the right hand (shown on smokers only), its tip glowing
	var cig := CylinderMesh.new()
	cig.top_radius = 0.012
	cig.bottom_radius = 0.012
	cig.height = 0.10
	cig.radial_segments = 5
	cig.rings = 1
	_part(a, cig, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.225, 0.90, -0.075)), Color(0.95, 0.94, 0.90), 0, 4, true, 2)
	var tip := SphereMesh.new()
	tip.radius = 0.016
	tip.height = 0.032
	tip.radial_segments = 5
	tip.rings = 3
	_part(a, tip, Transform3D(Basis.IDENTITY, Vector3(0.225, 0.90, -0.128)), Color(1.0, 0.36, 0.05), 0, 4, true, 2)
	# the football (shown on the BALL instance only)
	var fb := SphereMesh.new()
	fb.radius = 0.11
	fb.height = 0.22
	fb.radial_segments = 8
	fb.rings = 5
	_part(a, fb, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.11, 0.0)), Color(0.44, 0.26, 0.11), 0, 0, false, 3)
	# a stretcher (part 10: shown under the wounded only, never posed): two poles, the canvas and four short feet
	var wood := Color(0.42, 0.31, 0.17)
	var canvas := Color(0.50, 0.47, 0.33)
	for sx2 in [-0.29, 0.29]:
		var pole := CylinderMesh.new()
		pole.top_radius = 0.022
		pole.bottom_radius = 0.022
		pole.height = 2.5
		pole.radial_segments = 5
		pole.rings = 1
		_part(a, pole, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sx2, 0.17, 0.0)), wood, 10, 0, true)
		for sz2 in [-0.95, 0.95]:
			_box(a, Vector3(0.035, 0.15, 0.035), Vector3(sx2, 0.075, sz2), wood, 10, 0, true)
	_box(a, Vector3(0.56, 0.025, 2.1), Vector3(0.0, 0.18, 0.0), canvas, 10, 0, true)
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


## How many men the quality setting allows, as a multiplier on the base numbers (low / medium / high). The men
## are nearly free to draw (one MultiMesh per site, animated in the vertex shader), so medium and high are busy.
static func density() -> float:
	return [0.7, 1.6, 2.2][clampi(GameState.quality, 0, 2)]


## Occupancy of a built site: the ground cells taken by anything standing on it (buildings, aircraft, vehicles,
## guns, tents, trees, fences), so no man is placed inside one or walks through it. Flat things (tracks, aprons,
## painted ground) do not block. Built from the site's own meshes before it enters the scene.
class Grid:
	var ox: float = 0.0
	var oz: float = 0.0
	var cell: float = 4.0
	var n: int = 0
	var b := PackedByteArray()

	func _init(center: Vector3, half: float, p_cell: float = 4.0) -> void:
		cell = p_cell
		n = int(ceil(half * 2.0 / cell))
		ox = center.x - half
		oz = center.z - half
		b.resize(n * n)

	func mark(a: AABB) -> void:
		if a.size.y < 0.6 or a.size.x > 300.0 or a.size.z > 300.0:
			return
		var i0: int = maxi(int(floor((a.position.x - 1.2 - ox) / cell)), 0)
		var j0: int = maxi(int(floor((a.position.z - 1.2 - oz) / cell)), 0)
		var i1: int = mini(int(floor((a.end.x + 1.2 - ox) / cell)), n - 1)
		var j1: int = mini(int(floor((a.end.z + 1.2 - oz) / cell)), n - 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				b[j * n + i] = 1

	func mark_disc(c: Vector3, r: float) -> void:
		var i0: int = maxi(int(floor((c.x - r - ox) / cell)), 0)
		var j0: int = maxi(int(floor((c.z - r - oz) / cell)), 0)
		var i1: int = mini(int(floor((c.x + r - ox) / cell)), n - 1)
		var j1: int = mini(int(floor((c.z + r - oz) / cell)), n - 1)
		var rr: float = (r + cell * 0.71) * (r + cell * 0.71)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var dx: float = ox + (float(i) + 0.5) * cell - c.x
				var dz: float = oz + (float(j) + 0.5) * cell - c.z
				if dx * dx + dz * dz <= rr:
					b[j * n + i] = 1

	func mark_line(p0: Vector3, p1: Vector3, r: float) -> void:
		var d: float = Vector2(p1.x - p0.x, p1.z - p0.z).length()
		var steps: int = int(d / maxf(cell * 0.75, 1.0)) + 1
		for k in steps + 1:
			mark_disc(p0.lerp(p1, float(k) / float(steps)), r)

	func blocked_cells() -> int:
		return b.count(1)

	func free_at(p: Vector3) -> bool:
		var i: int = int(floor((p.x - ox) / cell))
		var j: int = int(floor((p.z - oz) / cell))
		if i < 0 or j < 0 or i >= n or j >= n:
			return true
		return b[j * n + i] == 0

	func line_free(p0: Vector3, p1: Vector3) -> bool:
		var d: float = Vector2(p1.x - p0.x, p1.z - p0.z).length()
		var steps: int = int(d / 2.0) + 1
		for k in steps + 1:
			if not free_at(p0.lerp(p1, float(k) / float(steps))):
				return false
		return true


static func grid_for(root: Node3D, center: Vector3, half: float) -> Grid:
	var g := Grid.new(center, half)
	_mark_tree(g, root, root.transform)
	return g


static func _mark_tree(g: Grid, node: Node, xf: Transform3D) -> void:
	for c in node.get_children():
		if not (c is Node3D) or (c as Node3D).name in ["AirfieldPeople", "CampPeople", "SitePeople", "PeopleKit"]:
			continue
		var cx: Transform3D = xf * (c as Node3D).transform
		# props, structures, guns and vehicles build their meshes only when they enter the scene: use what they
		# were made from instead (an AirfieldProp's mesh and per-item transforms; otherwise the hit radius)
		if c is AirfieldProp:
			var ap: AirfieldProp = c
			var pm: Mesh = ap.get("_mesh")
			if pm != null:
				var pb: AABB = pm.get_aabb()
				for t in ap.get("_xf"):
					g.mark(cx * (t as Transform3D) * pb)
			continue
		if "hit_radius" in c and (c as Node3D).get_child_count() == 0:
			var hr: float = float(c.get("hit_radius"))
			if hr > 0.5 and hr < 80.0:
				g.mark_disc(cx.origin, hr)
		if c is MeshInstance3D:
			var m: Mesh = (c as MeshInstance3D).mesh
			if m != null:
				g.mark(cx * m.get_aabb())
		elif c is MultiMeshInstance3D:
			var mm: MultiMesh = (c as MultiMeshInstance3D).multimesh
			if mm != null and mm.mesh != null and mm.transform_format == MultiMesh.TRANSFORM_3D:
				var mb: AABB = mm.mesh.get_aabb()
				var cnt: int = mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
				for i in mini(cnt, 5000):
					g.mark(cx * mm.get_instance_transform(i) * mb)
			continue
		_mark_tree(g, c, cx)


## The taxiways (2.5 m either side of the paving) and the taxi-out routes (9 m either side) as one grid, so the
## thousands of placement checks are a lookup each instead of a walk over every paved segment and route.
static func paved_grid(af: Airfield, axf: Transform3D, half: float) -> Grid:
	var g := Grid.new(axf.origin, half)
	for seg in af._paved:
		var s0: Vector3 = seg[0]
		var s1: Vector3 = seg[1]
		if Vector2(s1.x - s0.x, s1.z - s0.z).length() < 1.0:
			continue
		g.mark_line(axf * Vector3(s0.x, 0.0, s0.z), axf * Vector3(s1.x, 0.0, s1.z), float(seg[2]) + 2.5)
	for rt in af.taxi_flight_routes:
		var r: PackedVector3Array = rt
		for i in range(1, r.size()):
			g.mark_line(axf * Vector3(r[i - 1].x, 0.0, r[i - 1].z), axf * Vector3(r[i].x, 0.0, r[i].z), 9.0)
	return g


## Kit beside the men: ammunition boxes, oil drums and (`tents`) the odd tent next to the groups standing about,
## working or sat on the grass. Returns [[kind (0 crates, 1 drums, 2 tent), world position (y unused), yaw], ...];
## `ok` says whether a world point may hold something. Every item keeps clear of each man and of every beat walked.
static func kit_spots(men: Array, seed_v: int, ok: Callable, tents: bool, team: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var meshes: Array = [AirfieldAssets.crate_stack(team), AirfieldAssets.drum_stack(team), AirfieldAssets.tent(team)]
	var rad: Array = []
	for m in meshes:
		var bb: AABB = (m as Mesh).get_aabb()
		rad.append(maxf(bb.size.x, bb.size.z) * 0.5 + 0.6)
	var out: Array = []
	var budget: int = men.size() / 4
	for i in men.size():
		if out.size() >= budget:
			break
		var m: Array = men[i]
		var kind: int = int(m[2])
		if not (kind == Kind.TALK or kind == Kind.SIT or kind == Kind.WORK) or float(m[3]) > 0.0 or rng.randf() > 0.5:
			continue
		var roll: float = rng.randf()
		var k: int = 0 if roll < 0.42 else (1 if roll < 0.80 else 2)
		if k == 2 and not tents:
			k = rng.randi() % 2
		var r: float = float(rad[k])
		var anchor: Vector3 = m[0]
		for _try in 5:
			var a: float = rng.randf() * TAU
			var p: Vector3 = anchor + Vector3(cos(a), 0.0, sin(a)) * (r + rng.randf_range(2.0, 3.6))
			p.y = 0.0
			var good: bool = ok.call(p) and ok.call(p + Vector3(r, 0, 0)) and ok.call(p - Vector3(r, 0, 0)) and ok.call(p + Vector3(0, 0, r)) and ok.call(p - Vector3(0, 0, r))
			if not good:
				continue
			var q := Vector2(p.x, p.z)
			for mm in men:
				var s0 := Vector2((mm[0] as Vector3).x, (mm[0] as Vector3).z)
				var e: Vector3 = (mm[0] as Vector3) + (mm[1] as Vector3) * float(mm[3])
				var s1 := Vector2(e.x, e.z)
				if Geometry2D.get_closest_point_to_segment(q, s0, s1).distance_to(q) < r + 1.0:
					good = false
					break
			if not good:
				continue
			for o in out:
				if Vector2((o[1] as Vector3).x - p.x, (o[1] as Vector3).z - p.z).length() < r + float(rad[int(o[0])]) + 1.0:
					good = false
					break
			if good:
				out.append([k, p, rng.randf() * TAU])
				break
	return out


## The kit from kit_spots as one MultiMesh per kind (plain scenery: no collision, no target), standing at `y_of(p)`.
static func add_kit(container: Node3D, spots: Array, team: String, y_of: Callable) -> void:
	if spots.is_empty():
		return
	var meshes: Array = [AirfieldAssets.crate_stack(team), AirfieldAssets.drum_stack(team), AirfieldAssets.tent(team)]
	var xfs: Array = [[], [], []]
	for sp in spots:
		var p: Vector3 = sp[1]
		(xfs[int(sp[0])] as Array).append(Transform3D(Basis(Vector3.UP, float(sp[2])), Vector3(p.x, float(y_of.call(p)), p.z)))
	for k in 3:
		if not (xfs[k] as Array).is_empty():
			var mi: MultiMeshInstance3D = Scatter.multi(meshes[k], xfs[k], 2400.0 if k < 2 else 3200.0, false)
			mi.name = "PeopleKit"
			container.add_child(mi)


## XZ distance check against the taxi-out routes (the grass legs from a pad to the taxiway are not paved).
static func _route_clear(af: Airfield, lp: Vector3, margin: float) -> bool:
	for rt in af.taxi_flight_routes:
		if Airfield.route_distance(rt as PackedVector3Array, lp) < margin:
			return false
	return true


## A ring of men passing a football: n men round a circle of radius `r` m about `c`, all facing in, and the ball
## (an instance of its own, see the shader's kinds 14 and 15). `ok` says whether a world point is free.
static func football_ring(c: Vector3, n: int, r: float, ph: float, soldier: bool, ok: Callable) -> Array:
	var out: Array = []
	if not ok.call(c):
		return out
	for k in n:
		var a: float = TAU * float(k) / float(n)
		var p: Vector3 = c + Vector3(cos(a), 0.0, sin(a)) * r
		if not ok.call(p):
			return []
		out.append([p, c - p, Kind.PASSER, 0.0, ph, 0.0, soldier, Vector2(float(k), float(n))])
	out.append([c, Vector3.FORWARD, Kind.BALL, 0.0, ph, 0.0, false, Vector2(float(n), r / MAN)])
	return out


## A field dressing station: a hospital tent with red crosses on its roof, a row of wounded on stretchers in front of
## it with medics kneeling over them, doctors, a pair of bearers carrying a man in on a stretcher, and an ambulance or
## two drawn up beside it. `f` points the way the casualties come from (the tent door faces it). Returns
## {"men": [...], "items": [[mesh, Transform3D], ...], "area": [[centre, radius], ...]} - the caller adds the items
## and keeps everyone else off the area. Empty when `ok` finds the ground taken.
static func dressing_station(c: Vector3, f: Vector3, team: String, ok: Callable, rng: RandomNumberGenerator) -> Dictionary:
	f.y = 0.0
	f = f.normalized()
	var r := Vector3(-f.z, 0.0, f.x)
	var S: float = SCALE
	for q in [Vector3.ZERO, r * 9.0 * S, -r * 9.0 * S, f * 10.0 * S, f * 10.0 * S + r * 6.0 * S, f * 10.0 * S - r * 6.0 * S, -f * 6.0 * S, r * 13.0 * S + f * 2.0 * S]:
		if not ok.call(c + q):
			return {}
	var men: Array = []
	var items: Array = []
	var face_tent := Basis.looking_at(f, Vector3.UP).scaled(Vector3.ONE * S)
	items.append([medical_tent_mesh(team), Transform3D(face_tent, c)])
	# the wounded on stretchers in a row in front of the door, heads toward the tent, medics kneeling at their sides
	var row: Vector3 = c + f * 8.5 * S
	for k in 4:
		var pp: Vector3 = row + r * (float(k) - 1.5) * 1.55 * S
		men.append([pp, f, Kind.PATIENT, 0.0, -1.0, 0.0, false])
		if k != 2:
			var side: float = 1.0 if k % 2 == 0 else -1.0
			men.append([pp - f * 0.55 * S + r * side * 0.95 * S, -r * side, Kind.MEDIC, 0.0, -1.0, 0.0, false])
	men.append([row + f * 2.6 * S + r * 0.6 * S, -f, Kind.DOCTOR, 0.0, -1.0, 0.0, false])
	men.append([c + f * 4.3 * S + r * 2.4 * S, f + r, Kind.DOCTOR, 0.0, -1.0, 0.0, false])
	men.append([c + f * 4.6 * S + r * 3.6 * S, -r, Kind.TALK, 0.0, -1.0, 0.0, false])
	# a stretcher party carrying a man in, along a beat that ends just short of the row
	var len_c: float = 26.0 + rng.randf_range(0.0, 10.0)
	var start: Vector3 = c + f * (11.5 * S + len_c) - r * 5.5 * S
	var cph: float = rng.randf()
	men.append([start, -f, Kind.CARRIED, len_c, cph, 0.95, false])
	men.append([start - (-f) * 1.42 * MAN, -f, Kind.BEARER, len_c, cph, 0.95, false])
	men.append([start + (-f) * 1.30 * MAN, -f, Kind.BEARER_FRONT, len_c, cph, 0.95, false])
	# ambulances drawn up beside the tent, backs to it
	var amb: ArrayMesh = ambulance_mesh(team)
	items.append([amb, Transform3D(Basis.looking_at(r, Vector3.UP).scaled(Vector3.ONE * S), c + r * 10.0 * S + f * 2.5 * S)])
	if rng.randf() < 0.6:
		items.append([amb, Transform3D(Basis.looking_at(r + f * 0.3, Vector3.UP).scaled(Vector3.ONE * S), c + r * 11.5 * S - f * 3.5 * S)])
	men.append([c + r * 10.0 * S + f * 6.0 * S, -r, Kind.SMOKER, 0.0, -1.0, 0.0, false])     # the driver
	var area: Array = [[c, 9.5 * S], [c + f * 8.5 * S, 7.5 * S], [c + r * 11.0 * S, 6.5 * S]]
	return {"men": men, "items": items, "area": area, "path": [start, start - f * len_c]}


static var _med_tent: Dictionary = {}
static var _ambulance: Dictionary = {}


## Hospital tent, in metres before SCALE: 11 m long ridge tent, door to -Z, a white panel with a red cross on each
## roof slope and a red-cross flag on a pole at one end.
static func medical_tent_mesh(team: String) -> ArrayMesh:
	if _med_tent.has(team):
		return _med_tent[team]
	var canvas: Color = Color(0.37, 0.39, 0.25) if team != "Axis" else Color(0.40, 0.42, 0.36)
	var white := Color(0.92, 0.91, 0.87)
	var red := Color(0.72, 0.06, 0.05)
	var L: float = 11.0
	var W: float = 7.0
	var wh: float = 1.9
	var rise: float = 2.0
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(L, wh, W), Vector3(0.0, wh * 0.5, 0.0), canvas))
	var ang: float = atan(rise / (W * 0.5))
	var sw: float = sqrt(rise * rise + W * W * 0.25) + 0.25
	for sgn in [-1.0, 1.0]:
		var bas := Basis(Vector3.RIGHT, ang * sgn)
		var cpos := Vector3(0.0, wh + rise * 0.5, sgn * W * 0.25)
		parts.append([_boxm(Vector3(L + 0.4, 0.08, sw)), Transform3D(bas, cpos), GroundKit.mat(canvas.darkened(0.05), true)])
		var nrm: Vector3 = bas * Vector3.UP
		parts.append([_boxm(Vector3(2.8, 0.02, 2.6)), Transform3D(bas, cpos + nrm * 0.055), GroundKit.mat(white, false)])
		parts.append([_boxm(Vector3(2.1, 0.02, 0.62)), Transform3D(bas, cpos + nrm * 0.07), GroundKit.mat(red, false)])
		parts.append([_boxm(Vector3(0.62, 0.02, 2.0)), Transform3D(bas, cpos + nrm * 0.07), GroundKit.mat(red, false)])
	# gable ends: a squashed diamond set into each end wall (its lower half hides inside the walls)
	var dg: float = (W * 0.5) * sqrt(2.0)
	for ex in [-1.0, 1.0]:
		var gb := Basis.from_scale(Vector3(1.0, rise / (W * 0.5), 1.0)) * Basis(Vector3.RIGHT, PI * 0.25)
		parts.append([_boxm(Vector3(0.1, dg, dg)), Transform3D(gb, Vector3(ex * (L * 0.5 - 0.08), wh, 0.0)), GroundKit.mat(canvas, false)])
	# the door: an open dark flap on the -Z side, a red cross on a white board beside it
	parts.append(GroundKit.box_part(Vector3(1.6, 1.8, 0.05), Vector3(0.0, 0.9, -W * 0.5 - 0.02), Color(0.10, 0.09, 0.07), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(1.0, 1.0, 0.04), Vector3(1.9, 1.15, -W * 0.5 - 0.03), white, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.72, 0.22, 0.03), Vector3(1.9, 1.15, -W * 0.5 - 0.05), red, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.22, 0.72, 0.03), Vector3(1.9, 1.15, -W * 0.5 - 0.05), red, Vector3.ZERO, false))
	# flag pole and Red Cross flag
	parts.append(GroundKit.cyl_part(0.05, 0.06, 5.5, Vector3(L * 0.5 + 1.2, 2.75, -W * 0.5), Color(0.85, 0.85, 0.82), Vector3.ZERO, 6, false))
	parts.append(GroundKit.box_part(Vector3(1.5, 1.0, 0.03), Vector3(L * 0.5 + 2.0, 5.0, -W * 0.5), white, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(1.0, 0.24, 0.04), Vector3(L * 0.5 + 2.0, 5.0, -W * 0.5), red, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.24, 0.76, 0.04), Vector3(L * 0.5 + 2.0, 5.0, -W * 0.5), red, Vector3.ZERO, false))
	var m: ArrayMesh = AirfieldAssets._build(parts)
	_med_tent[team] = m
	return m


## A period field ambulance, in metres before SCALE, nose to -Z: the British Austin K2 "Katy" (khaki, a tall square
## box body over the rear wheels, a short bonnet and open-sided cab) or, for the Germans, the Phaenomen Granit 1500A
## Krankenwagen (field grey, a rounded bonnet and a long box body). Red crosses on white on the sides, the back and
## the roof.
static func ambulance_mesh(team: String) -> ArrayMesh:
	if _ambulance.has(team):
		return _ambulance[team]
	var axis: bool = team == "Axis"
	var paint: Color = Color(0.38, 0.40, 0.42) if axis else Color(0.37, 0.36, 0.22)
	var dark: Color = Color(0.06, 0.06, 0.06)
	var white := Color(0.92, 0.91, 0.87)
	var red := Color(0.72, 0.06, 0.05)
	var glass := Color(0.20, 0.25, 0.28)
	var parts: Array = []
	var bw: float = 2.1 if not axis else 2.0       # body width
	var bl: float = 3.3 if not axis else 3.6       # body length
	var bh: float = 2.0 if not axis else 1.75      # body height
	var bz: float = 0.95                           # body centre (behind the cab)
	var floor_y: float = 0.95
	# chassis and wheels
	parts.append(GroundKit.box_part(Vector3(1.5, 0.25, 5.4), Vector3(0.0, 0.62, -0.15), dark))
	for wz in [-1.75, 1.35]:
		for wx in [-0.88, 0.88]:
			parts.append(GroundKit.cyl_part(0.42, 0.42, 0.28, Vector3(wx, 0.42, wz), dark, Vector3(0, 0, 90), 10))
			parts.append(GroundKit.cyl_part(0.2, 0.2, 0.30, Vector3(wx, 0.42, wz), paint.darkened(0.2), Vector3(0, 0, 90), 8, false))
	# bonnet, wings, radiator
	if axis:
		parts.append(GroundKit.cyl_part(0.48, 0.48, 1.25, Vector3(0.0, 1.02, -2.25), paint, Vector3(90, 0, 0), 10))
		parts.append(GroundKit.box_part(Vector3(1.0, 0.5, 1.25), Vector3(0.0, 0.82, -2.25), paint))
	else:
		parts.append(GroundKit.box_part(Vector3(0.95, 0.70, 1.0), Vector3(0.0, 1.10, -2.2), paint))
		parts.append(GroundKit.box_part(Vector3(0.9, 0.62, 0.06), Vector3(0.0, 1.10, -2.72), dark, Vector3.ZERO, false))
	for wx2 in [-0.82, 0.82]:
		parts.append(GroundKit.box_part(Vector3(0.38, 0.12, 1.15), Vector3(wx2, 0.86, -1.9), paint))
	# cab
	parts.append(GroundKit.box_part(Vector3(1.85, 1.15, 1.1), Vector3(0.0, 1.55, -1.15), paint))
	parts.append(GroundKit.box_part(Vector3(1.6, 0.55, 0.05), Vector3(0.0, 1.78, -1.72), glass, Vector3(-8, 0, 0), false))
	for wx3 in [-0.93, 0.93]:
		parts.append(GroundKit.box_part(Vector3(0.05, 0.5, 0.6), Vector3(wx3, 1.75, -1.2), glass, Vector3.ZERO, false))
	# the box body
	parts.append(GroundKit.box_part(Vector3(bw, bh, bl), Vector3(0.0, floor_y + bh * 0.5, bz), paint))
	parts.append(GroundKit.box_part(Vector3(bw + 0.08, 0.08, bl + 0.08), Vector3(0.0, floor_y + bh + 0.04, bz), paint.darkened(0.12)))
	# red crosses on white: both sides, the back doors and the roof
	var cy: float = floor_y + bh * 0.55
	for sx in [-1.0, 1.0]:
		var xs: float = sx * (bw * 0.5 + 0.02)
		parts.append(GroundKit.box_part(Vector3(0.02, 1.1, 1.1), Vector3(xs, cy, bz), white, Vector3.ZERO, false))
		parts.append(GroundKit.box_part(Vector3(0.03, 0.26, 0.82), Vector3(xs + sx * 0.01, cy, bz), red, Vector3.ZERO, false))
		parts.append(GroundKit.box_part(Vector3(0.03, 0.82, 0.26), Vector3(xs + sx * 0.01, cy, bz), red, Vector3.ZERO, false))
	var zb: float = bz + bl * 0.5 + 0.02
	parts.append(GroundKit.box_part(Vector3(0.9, 0.9, 0.02), Vector3(0.0, cy, zb), white, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.66, 0.22, 0.03), Vector3(0.0, cy, zb + 0.01), red, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.22, 0.66, 0.03), Vector3(0.0, cy, zb + 0.01), red, Vector3.ZERO, false))
	var ry: float = floor_y + bh + 0.1
	parts.append(GroundKit.box_part(Vector3(1.4, 0.02, 1.4), Vector3(0.0, ry, bz), white, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(1.05, 0.03, 0.32), Vector3(0.0, ry + 0.01, bz), red, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.32, 0.03, 1.05), Vector3(0.0, ry + 0.01, bz), red, Vector3.ZERO, false))
	# headlamps
	for wx4 in [-0.62, 0.62]:
		parts.append(GroundKit.cyl_part(0.11, 0.11, 0.1, Vector3(wx4, 1.2, -2.62), Color(0.75, 0.74, 0.66), Vector3(90, 0, 0), 8, false))
	var m: ArrayMesh = AirfieldAssets._build(parts)
	_ambulance[team] = m
	return m


static func _boxm(size: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = size
	return bm


## Debug (--people-shot=<kind>[,<n>[,<distance>]]): a camera on the n-th man of that Kind at the start airfield
## (hidden-desktop screenshots of the figures close up).
static func _debug_shot(container: Node3D, men: Array, af_name: String) -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--people-shot="):
			continue
		var f: PackedStringArray = arg.substr(14).split(",")
		if not af_name.to_lower().contains(GameState.start_airfield.substr(0, 5)):
			return
		var nth: int = int(f[1]) if f.size() > 1 else 0
		for m in men:
			if int(m[2]) != int(f[0]):
				continue
			nth -= 1
			if nth >= 0:
				continue
			var cam := Camera3D.new()
			cam.fov = 40.0
			container.add_child(cam)
			var tp: Vector3 = (m[0] as Vector3) + (m[1] as Vector3) * minf(float(m[3]), 12.0)
			var gy: float = GroundKit.ground_y(tp.x, tp.z)
			tp.y = gy + 1.4 + (float(m[8]) if m.size() > 8 else 0.0)
			var back: float = float(f[2]) if f.size() > 2 else 9.0
			var cp: Vector3 = tp + Vector3(back * 0.75, 2.2 + back * 0.12, back)
			cam.transform = Transform3D(Basis.looking_at(tp - cp, Vector3.UP), cp)      # (the airfield's container sits at the world origin)
			var tree: SceneTree = Engine.get_main_loop() as SceneTree
			var wr: WeakRef = weakref(cam)          # (the field may be unloaded and rebuilt: never capture the node itself)
			var keep := func() -> void:
				var c: Camera3D = wr.get_ref() as Camera3D
				if c != null and c.is_inside_tree() and not c.current:
					c.make_current()
			tree.create_timer(3.0).timeout.connect(func() -> void: tree.process_frame.connect(keep))
			return


# ------------------------------------------------------------------ mechanics at the parked aircraft

static var _top_cache: Dictionary = {}
static var _stand_cache: Dictionary = {}


## Top surface of a parked aircraft mesh as a height map (0.4 m cells, -1 where there is nothing): where a cowling,
## a nacelle or the wing is and how high, read from the model itself. Cached per mesh.
static func _top_map(mesh: Mesh) -> Dictionary:
	var key: int = mesh.get_instance_id()
	if _top_cache.has(key):
		return _top_cache[key]
	var bb: AABB = mesh.get_aabb()
	var cell: float = 0.4
	var nx: int = int(bb.size.x / cell) + 2
	var nz: int = int(bb.size.z / cell) + 2
	var top := PackedFloat32Array()
	top.resize(nx * nz)
	top.fill(-1.0)
	# every triangle is filled in, not just its corners: a wing is a few big triangles with no vertex in the middle
	var step: float = cell * 0.7
	for si in mesh.get_surface_count():
		var arrs: Array = mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
		var ids: PackedInt32Array = arrs[Mesh.ARRAY_INDEX] if arrs[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var tri_n: int = ids.size() / 3 if not ids.is_empty() else vs.size() / 3
		for t in tri_n:
			var a: Vector3 = vs[ids[t * 3] if not ids.is_empty() else t * 3]
			var b: Vector3 = vs[ids[t * 3 + 1] if not ids.is_empty() else t * 3 + 1]
			var c: Vector3 = vs[ids[t * 3 + 2] if not ids.is_empty() else t * 3 + 2]
			var l: float = maxf(maxf(Vector2(b.x - a.x, b.z - a.z).length(), Vector2(c.x - a.x, c.z - a.z).length()), Vector2(c.x - b.x, c.z - b.z).length())
			var nn: int = clampi(int(ceil(l / step)), 1, 200)
			for i2 in nn + 1:
				for j2 in nn + 1 - i2:
					var v: Vector3 = a + (b - a) * (float(i2) / nn) + (c - a) * (float(j2) / nn)
					var idx: int = int((v.z - bb.position.z) / cell) * nx + int((v.x - bb.position.x) / cell)
					if idx >= 0 and idx < top.size() and v.y > top[idx]:
						top[idx] = v.y
	var d: Dictionary = {"ox": bb.position.x, "oz": bb.position.z, "cell": cell, "nx": nx, "nz": nz, "top": top}
	_top_cache[key] = d
	return d


static func _top_at(tm: Dictionary, x: float, z: float, rad: float) -> float:
	var cell: float = tm["cell"]
	var nx: int = tm["nx"]
	var nz: int = tm["nz"]
	var top: PackedFloat32Array = tm["top"]
	var best: float = -1.0
	var i0: int = int((x - rad - float(tm["ox"])) / cell)
	var i1: int = int((x + rad - float(tm["ox"])) / cell)
	var j0: int = int((z - rad - float(tm["oz"])) / cell)
	var j1: int = int((z + rad - float(tm["oz"])) / cell)
	for j in range(maxi(j0, 0), mini(j1, nz - 1) + 1):
		for i in range(maxi(i0, 0), mini(i1, nx - 1) + 1):
			best = maxf(best, top[j * nx + i])
	return best


## The nearest z, from `z0` going forward (toward -Z, the nose) to `z_min`, where nothing of the aircraft is above
## the ground at (x, z) - a man standing there is not inside a wing or a cowling. INF if there is none.
static func _clear_z(tm: Dictionary, x: float, z0: float, z_min: float) -> float:
	var z: float = z0
	while z >= z_min:
		if _top_at(tm, x, z, 0.45) < 0.25:
			return z
		z -= 0.3
	return INF


## A steel engine work stand (or, low down, a wooden trestle) whose platform is `h` m up: four legs, the platform,
## a hand rail on three sides and a ladder up the back (+Z). Cached by height in 0.25 m steps.
static func work_stand_mesh(h: float) -> ArrayMesh:
	var hk: int = int(round(h * 4.0))
	if _stand_cache.has(hk):
		return _stand_cache[hk]
	h = float(hk) / 4.0
	var parts: Array = []
	var trestle: bool = h < 1.3
	var col: Color = Color(0.45, 0.33, 0.20) if trestle else Color(0.40, 0.43, 0.42)
	var w: float = 1.0 if trestle else 1.7
	var d: float = 0.8 if trestle else 1.3
	parts.append(GroundKit.box_part(Vector3(w, 0.08, d), Vector3(0.0, h - 0.04, 0.0), col))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var lean: float = 6.0 if trestle else 0.0
			parts.append(GroundKit.box_part(Vector3(0.07, h, 0.07), Vector3(sx * (w * 0.5 - 0.05), h * 0.5, sz * (d * 0.5 - 0.05)), col, Vector3(0, 0, -lean * sx), false))
	if not trestle:
		# cross braces, rails and the ladder
		for sz2 in [-1.0, 1.0]:
			parts.append(GroundKit.box_part(Vector3(w - 0.1, 0.05, 0.05), Vector3(0.0, h * 0.45, sz2 * (d * 0.5 - 0.05)), col, Vector3.ZERO, false))
		for sx2 in [-1.0, 1.0]:
			parts.append(GroundKit.box_part(Vector3(0.05, 1.0, 0.05), Vector3(sx2 * (w * 0.5 - 0.05), h + 0.5, d * 0.5 - 0.05), col, Vector3.ZERO, false))
			parts.append(GroundKit.box_part(Vector3(0.05, 1.0, 0.05), Vector3(sx2 * (w * 0.5 - 0.05), h + 0.5, -d * 0.5 + 0.05), col, Vector3.ZERO, false))
			parts.append(GroundKit.box_part(Vector3(0.05, 0.05, d), Vector3(sx2 * (w * 0.5 - 0.05), h + 1.0, 0.0), col, Vector3.ZERO, false))
		parts.append(GroundKit.box_part(Vector3(w, 0.05, 0.05), Vector3(0.0, h + 1.0, d * 0.5 - 0.05), col, Vector3.ZERO, false))
		for lx in [-0.25, 0.25]:
			parts.append(GroundKit.box_part(Vector3(0.05, h + 0.9, 0.05), Vector3(lx, (h + 0.9) * 0.5, d * 0.5 + 0.35), col, Vector3(-12, 0, 0), false))
		var rung: float = 0.3
		while rung < h:
			parts.append(GroundKit.box_part(Vector3(0.5, 0.04, 0.04), Vector3(0.0, rung, d * 0.5 + 0.35 + 0.21 * (rung / maxf(h, 0.1)) - 0.1), col, Vector3.ZERO, false))
			rung += 0.3
	var m: ArrayMesh = AirfieldAssets._build(parts)
	_stand_cache[hk] = m
	return m


## The parked model's type id (ParkedAircraft keeps one mesh per type), or "".
static func _type_of(mesh: Mesh) -> String:
	for id in ParkedAircraft._cache:
		if ParkedAircraft._cache[id] == mesh:
			return str(id)
	return ""


## Mechanics at one parked aircraft, as in the period photographs: men up on work stands (or trestles) at one or two
## engines reaching into the cowlings, one up on the wing beside the engine and one kneeling at a main wheel. All
## placed from the aircraft's own spec (engine, wing and gear positions) and its model's top surface.
## Appends men to `men` and [mesh, Transform3D] stands to `items`.
static func mechanics_at(ap: AirfieldProp, rng: RandomNumberGenerator, men: Array, items: Array) -> void:
	var mesh: Mesh = ap.get("_mesh")
	if mesh == null:
		return
	var id: String = _type_of(mesh)
	var spec: Dictionary = ModelSpecs.get_spec(id) if id != "" else {}
	if spec.is_empty() or not spec.has("wing"):
		return
	var bb: AABB = mesh.get_aabb()
	var k: float = (bb.size.x * 0.5) / maxf(float((spec["wing"] as Dictionary)["half"]), 1.0)
	var tm: Dictionary = _top_map(mesh)
	var engines: Array = spec.get("engines", [])
	var jobs: Array = []                 # [x, front z, radius] in model space
	if engines.is_empty():
		var fus: Dictionary = spec.get("fus", {})
		jobs.append([0.0, float(fus.get("z0", bb.position.z)) * k, float(fus.get("hw", 0.5)) * k * 1.05])
	else:
		var order: Array = engines.duplicate()
		order.shuffle()
		for e in order.slice(0, 1 if order.size() <= 2 and rng.randf() < 0.5 else 2):
			jobs.append([float(e["x"]) * k, float(e["z0"]) * k, float(e["r"]) * k])
	var xfs: Array = ap.get("_xf")
	if xfs.is_empty():
		return
	var W: Transform3D = Transform3D(Basis.IDENTITY, ap.position) * (xfs[0] as Transform3D)
	W.basis = W.basis.orthonormalized()
	for jb in jobs:
		var ex: float = jb[0]
		var ez: float = jb[1]
		var er: float = jb[2]
		var sgn: float = signf(ex) if absf(ex) > 0.5 else (-1.0 if rng.randf() < 0.5 else 1.0)
		var cz: float = ez + er + 0.6                     # just behind the spinner, on the cowling
		var top: float = _top_at(tm, ex, cz, 0.45)
		if top < 0.3:
			continue
		var centre_y: float = top - er
		var hand_y: float = 1.85 * MAN                    # where the reaching man's hands are, above his feet
		var h: float = clampf(centre_y - hand_y + 0.15, 0.0, 6.0)
		# beside the cowling, but clear of the wing above: forward of its leading edge, behind the propeller
		var lx: float = ex + sgn * (er + 0.75)
		var lz: float = _clear_z(tm, lx, cz + 0.2, ez - 0.6)
		if lz == INF:
			continue
		var local := Vector3(lx, 0.0, lz)
		var wp: Vector3 = W * local
		var face: Vector3 = W.basis * Vector3(-sgn, 0.0, -0.15)
		if h > 0.25:
			var hk: float = float(int(round(h * 4.0))) / 4.0
			items.append([work_stand_mesh(hk), Transform3D(Basis.looking_at(face, Vector3.UP), Vector3(wp.x, 0.0, wp.z))])
			h = hk
		men.append([Vector3(wp.x, 0.0, wp.z), face, Kind.REACH, 0.0, -1.0, 0.0, false, null, h])
		# a second man on the other side of the cowling on single-engined types (the trestle on the far side)
		var lz2: float = _clear_z(tm, ex - sgn * (er + 0.75), cz + 0.4, ez - 0.6)
		if engines.is_empty() and lz2 != INF:
			var lp2 := Vector3(ex - sgn * (er + 0.75), 0.0, lz2)
			var wp2: Vector3 = W * lp2
			var face2: Vector3 = W.basis * Vector3(sgn, 0.0, -0.15)
			if h > 0.25:
				items.append([work_stand_mesh(h), Transform3D(Basis.looking_at(face2, Vector3.UP), Vector3(wp2.x, 0.0, wp2.z))])
			men.append([Vector3(wp2.x, 0.0, wp2.z), face2, Kind.REACH, 0.0, -1.0, 0.0, false, null, h])
		# up on the wing beside the engine, bent over it
		var wx: float = ex - sgn * (er + 0.9) if absf(ex) > 0.5 else sgn * (er + 1.0)
		var wz: float = cz + er * 1.6 + 0.6
		var wt: float = _top_at(tm, wx, wz, 0.3)
		var under: float = _top_at(tm, wx, wz + 1.2, 0.3)
		if wt > 0.6 and under > 0.6 and absf(wt - under) < 0.5 and rng.randf() < 0.75:
			var wpw: Vector3 = W * Vector3(wx, 0.0, wz)
			men.append([Vector3(wpw.x, 0.0, wpw.z), W.basis * Vector3(0.0, 0.0, -1.0), Kind.ON_WING, 0.0, -1.0, 0.0, false, null, wt])
	# kneeling at a main wheel
	if spec.has("gear") and rng.randf() < 0.8:
		var gr: Dictionary = spec["gear"]
		var gs: float = -1.0 if rng.randf() < 0.5 else 1.0
		var gx: float = float(gr["x"]) * k * gs
		var gz: float = float(gr["z"]) * k
		# at the front of the wheel, out from under the wing (kneeling, his head would be in it)
		var kz: float = _clear_z(tm, gx + gs * 0.6, gz - 0.6, gz - 6.0)
		if kz == INF:
			return
		var wpg: Vector3 = W * Vector3(gx + gs * 0.6, 0.0, kz)
		men.append([Vector3(wpg.x, 0.0, wpg.z), W.basis * Vector3(-gs * 0.6, 0.0, gz - kz), Kind.KNEEL, 0.0, -1.0, 0.0, false])


## A few heavy bombers parked on the grass behind the spectators at the take-off end, noses toward the runway.
## Real parked aircraft (ParkedAircraft: destructible, the period's types for the side), marked into `g` so nobody
## is placed under them. Returns [[world position, the way it faces, half span], ...].
static func take_off_bombers(container: Node3D, af: Airfield, axf: Transform3D, y: float, team: String, rws: Array, g: Grid, pave: Grid, count: int, seed_v: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var late: bool = EraClock.band() in ["buildup", "liberation", "1945"]
	var ids: Array
	if team == "Axis":
		ids = ["he111", "ju88", "do17"] if not late else ["he111", "ju88", "fw200"]
	else:
		ids = ["blenheim", "a20"] if not late else ["lancaster", "b25", "b26", "lancaster"]
	var inv: Transform3D = axf.affine_inverse()
	var thr: Vector3 = af.get_threshold_position()
	var tdir: Vector3 = WorldCoords.heading_to_dir(af.heading_deg)
	tdir.y = 0.0
	tdir = tdir.normalized()
	var tright := Vector3(-tdir.z, 0.0, tdir.x)
	var off0: float = af.runway_width * 0.5 + RUNWAY_CLEAR + 5.0
	var out: Array = []
	var xfs: Array = []
	for k in count * 6:
		if out.size() >= count:
			break
		var id: String = ids[(k + out.size()) % ids.size()]
		var mesh: ArrayMesh = ParkedAircraft.mesh_for(id)
		if mesh == null:
			continue
		var bb: AABB = mesh.get_aabb()
		var half: float = maxf(bb.size.x, bb.size.z) * 0.5 * 1.7          # (parked aircraft are placed at x1.7, as on the aprons)
		var sgn: float = 1.0 if (out.size() % 2 == 0) else -1.0
		var along: float = rng.randf_range(40.0, 330.0)
		var p: Vector3 = thr + tdir * along + tright * sgn * (off0 + 52.0 + half)
		p.y = 0.0
		var face: Vector3 = -tright * sgn
		var good: bool = true
		for q in [Vector3.ZERO, tdir * half * 0.9, -tdir * half * 0.9, face * half * 0.6, -face * half * 0.6]:
			var w: Vector3 = p + q
			var lw: Vector3 = inv * w
			if not (g.free_at(w) and pave.free_at(w) and AirfieldActivity.leg_clear(rws, lw, lw, RUNWAY_CLEAR + 20.0)):
				good = false
				break
		if not good:
			continue
		for o in out:
			if (o[0] as Vector3).distance_to(p) < half + float(o[2]) + 8.0:
				good = false
		if not good:
			continue
		var t := Transform3D(Basis.looking_at(face, Vector3.UP) * Basis.from_scale(Vector3.ONE * 1.7), Vector3(p.x, y + 0.4, p.z))
		var n0: int = container.get_child_count()
		ParkedAircraft.place(container, [t], team, af)
		if container.get_child_count() == n0:
			continue
		# (ParkedAircraft.place picks its own type for the field: swap in the bomber, before it builds its meshes)
		var placed: Node = container.get_child(container.get_child_count() - 1)
		if placed is AirfieldProp:
			var ap: AirfieldProp = placed
			ap.set("_mesh", mesh)
			ap.far_mesh = ParkedAircraft.far_mesh_for(id)
			for tt in ap.get("_xf"):
				g.mark(Transform3D(Basis.IDENTITY, ap.position) * (tt as Transform3D) * bb)
		out.append([p, face, half])
	return out


## The plan for one field: [[world position, world direction he faces / walks, Kind, beat length in metres,
## phase (-1 = his own), speed in mesh m/s (0 = his own), soldier (optional, default: the drill squad and sentries)], ...].
static func plan(af: Airfield, axf: Transform3D, rws: Array, pads: Array, depot: Vector3, dump: Vector3, tower: Vector3, seed_v: int, dens: float = 1.0, grid: Grid = null, kit_out: Array = [], team: String = "Allies", pave_in: Grid = null, extra: Array = []) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var inv: Transform3D = axf.affine_inverse()
	var men: Array = extra.duplicate()
	var pave: Grid = pave_in if pave_in != null else paved_grid(af, axf, af.runway_length * 0.75 + 450.0)
	# a spot a man may stand on: off the runways, taxiways and taxi routes, not inside anything
	var ok := func(p: Vector3, rw_margin: float = 0.0) -> bool:
		var lp: Vector3 = inv * p
		return pave.free_at(p) and (grid == null or grid.free_at(p)) and AirfieldActivity.leg_clear(rws, lp, lp, RUNWAY_CLEAR + rw_margin)
	var stand := func(p: Vector3, face: Vector3, kind: int) -> bool:
		if not ok.call(p):
			return false
		face.y = 0.0
		men.append([p, face.normalized() if face.length() > 0.01 else Vector3.FORWARD, kind, 0.0, -1.0, 0.0])
		return true
	# a straight beat a man can walk (or run) without crossing a runway, a taxiway, a taxi route or anything built
	var line_ok := func(p0: Vector3, p1: Vector3, margin: float) -> bool:
		if not AirfieldActivity.leg_clear(rws, inv * p0, inv * p1, RUNWAY_CLEAR + margin):
			return false
		if grid != null and not grid.line_free(p0, p1):
			return false
		return pave.line_free(p0, p1)
	var beat := func(p0: Vector3, p1: Vector3, kind: int, spd: float, ph: float, soldier: bool) -> bool:
		var d: Vector3 = p1 - p0
		d.y = 0.0
		var ln: float = d.length()
		if ln < 8.0 or ln > 420.0 or not line_ok.call(p0, p1, 0.0):
			return false
		men.append([p0, d / ln, kind, ln, ph, spd, soldier])
		return true
	var walk := func(p0: Vector3, p1: Vector3) -> bool:
		return beat.call(p0, p1, Kind.WALK, 0.0, -1.0, false)
	# a knot of men standing talking (or sat on the grass), facing each other
	var knot := func(c: Vector3, count: int, wave: bool, kind: int = Kind.TALK) -> void:
		var a0: float = rng.randf() * TAU
		for k in count:
			var a: float = a0 + TAU * float(k) / float(count) + rng.randf_range(-0.25, 0.25)
			var p: Vector3 = c + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.9, 1.4) * SCALE * (1.3 if kind == Kind.SIT else 1.0)
			stand.call(p, c - p, Kind.WAVE if wave and k == 0 else kind)
	# at the parked aircraft: one or two bent over a job at the edge of the pad, a third looking on
	var n_pads: int = mini(pads.size(), int(round(10.0 * dens)))
	for i in n_pads:
		var pad: Vector3 = pads[i]
		for _try in 8:
			var a: float = rng.randf() * TAU
			var out := Vector3(cos(a), 0.0, sin(a))
			var p: Vector3 = pad + out * rng.randf_range(9.0, 13.5)
			if not stand.call(p, pad - p, Kind.WORK):
				continue
			var side := Vector3(-out.z, 0.0, out.x)
			if i % 2 == 0 or dens > 1.4:
				stand.call(p + side * 1.5 * SCALE, pad - p, Kind.WORK)
			stand.call(p - side * 1.4 * SCALE + out * 1.2, (pad - p) + side * 4.0, Kind.TALK)
			if dens > 1.4:
				stand.call(p - side * 2.6 * SCALE + out * 2.0, (pad - p) - side * 3.0, Kind.TALK)
			break
	# men walking from pad to pad, clear of the pads themselves
	var walkers: int = 0
	for i in pads.size() - 1:
		if walkers >= int(round(12.0 * dens)):
			break
		var p0: Vector3 = pads[i]
		var p1: Vector3 = pads[i + 1]
		var d: Vector3 = p1 - p0
		d.y = 0.0
		if d.length() < 25.0:
			continue
		for sd in ([13.0, -13.0] if dens > 1.4 else [13.0 if i % 2 == 0 else -13.0]):
			var side: Vector3 = Vector3(-d.z, 0.0, d.x).normalized() * float(sd)
			if walk.call(p0 + side + d.normalized() * 6.0, p1 + side - d.normalized() * 6.0):
				walkers += 1
	# the fuel depot, the bomb dump and the watch office: men standing about, and beats out to the nearest pads
	for hub in [[depot + Vector3(16.0, 0.0, 9.0), 3, false], [tower + Vector3(11.0, 0.0, 7.0), 3, true], [dump + Vector3(-12.0, 0.0, 3.0), 2, false]]:
		var c: Vector3 = hub[0]
		knot.call(c, int(hub[1]) + (1 if dens > 1.4 else 0), bool(hub[2]))
		if dens > 1.4:
			knot.call(c + Vector3(rng.randf_range(-14.0, 14.0), 0.0, rng.randf_range(-14.0, 14.0)), 2 + rng.randi() % 2, false)
		var a: float = rng.randf() * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		for _try in 4:                                   # a man pacing up and down nearby
			if walk.call(c + dir * 5.0, c + dir * rng.randf_range(28.0, 45.0)):
				break
			dir = dir.rotated(Vector3.UP, PI * 0.5)
		if dens < 0.75:
			continue
		var near: Array = pads.duplicate()
		near.sort_custom(func(x: Vector3, z: Vector3) -> bool: return x.distance_squared_to(c) < z.distance_squared_to(c))
		for k in mini(2 if dens < 1.4 else 4, near.size()):
			var to: Vector3 = (near[k] as Vector3) - c
			to.y = 0.0
			if to.length() > 30.0:
				walk.call(c + to.normalized() * 6.0, (near[k] as Vector3) - to.normalized() * 14.0)
	# off duty: two or three sat on the grass a little way from some of the pads
	var lounging: int = 0
	for i in range(1, pads.size(), 1 if dens > 1.4 else 2):
		if lounging >= int(round(4.0 * dens)):
			break
		var pad2: Vector3 = pads[i]
		for _try in 6:
			var a2: float = rng.randf() * TAU
			var c2: Vector3 = pad2 + Vector3(cos(a2), 0.0, sin(a2)) * rng.randf_range(19.0, 28.0)
			if not ok.call(c2, 8.0) or _taxiway_clear(af, inv * c2) < 7.0:
				continue
			var close: bool = false
			for q in pads:
				if (q as Vector3).distance_to(c2) < 17.0:
					close = true
			if close:
				continue
			knot.call(c2, 2 + rng.randi() % 2, false, Kind.SIT)
			lounging += 1
			break

	# --- the take-off end of the runway: everyone who can turns out to watch the flight go -----------------------
	# lines of men along both sides of the first few hundred metres of the take-off run, facing the runway (some
	# waving the pilots off), knots talking and sat on the grass behind them, men walking and running along, and
	# the runway controller's men at the threshold
	var thr: Vector3 = af.get_threshold_position()
	var tdir: Vector3 = WorldCoords.heading_to_dir(af.heading_deg)
	tdir.y = 0.0
	tdir = tdir.normalized()
	var tright := Vector3(-tdir.z, 0.0, tdir.x)
	var off0: float = af.runway_width * 0.5 + RUNWAY_CLEAR + 5.0
	var gap0: float = 1.15 * SCALE
	for sgn in [-1.0, 1.0]:
		var face: Vector3 = -tright * float(sgn)              # toward the runway
		var lines: int = int(round(4.0 * dens))
		for k in lines:
			var along: float = rng.randf_range(-20.0, 320.0)
			var lat: float = off0 + rng.randf_range(0.0, 12.0)
			var cnt: int = 3 + rng.randi() % 4
			for m in cnt:
				var p: Vector3 = thr + tdir * (along + float(m) * gap0 * rng.randf_range(0.9, 1.3)) + tright * float(sgn) * (lat + rng.randf_range(-0.6, 0.6))
				stand.call(p, face + tdir * rng.randf_range(-0.35, 0.35), Kind.WAVE if rng.randf() < 0.3 else Kind.TALK)
		for k in int(round(3.0 * dens)):
			knot.call(thr + tdir * rng.randf_range(-40.0, 340.0) + tright * float(sgn) * (off0 + rng.randf_range(14.0, 45.0)), 2 + rng.randi() % 3, false, Kind.SIT if k % 2 == 0 else Kind.TALK)
		for k in int(round(2.0 * dens)):
			var a0: float = rng.randf_range(-30.0, 200.0)
			var lat2: float = off0 + rng.randf_range(6.0, 40.0)
			beat.call(thr + tdir * a0 + tright * float(sgn) * lat2, thr + tdir * (a0 + rng.randf_range(60.0, 160.0)) + tright * float(sgn) * lat2, Kind.WALK, 0.0, -1.0, false)
		var a1: float = rng.randf_range(0.0, 120.0)
		var lat3: float = off0 + rng.randf_range(8.0, 30.0)
		beat.call(thr + tdir * a1 + tright * float(sgn) * lat3, thr + tdir * (a1 + rng.randf_range(90.0, 180.0)) + tright * float(sgn) * lat3, Kind.RUN, rng.randf_range(3.2, 3.9), -1.0, false)
	# the runway controller's party at the threshold, waving each aircraft off
	stand.call(thr + tdir * 12.0 - tright * off0, tright, Kind.WAVE)
	stand.call(thr + tdir * 10.0 - tright * (off0 + 1.6 * SCALE), tright, Kind.TALK)
	stand.call(thr + tdir * 14.0 - tright * (off0 + 1.2 * SCALE), tright + tdir, Kind.SALUTE)

	# --- the rest of the field: groups and walkers anywhere on the open grass inside the boundary -------------
	var reach: float = af.runway_length * 0.55 + 120.0
	var spots: int = int(round(14.0 * dens))
	var placed: int = 0
	for _try in spots * 10:
		if placed >= spots:
			break
		var a7: float = rng.randf() * TAU
		var c7: Vector3 = axf.origin + Vector3(cos(a7), 0.0, sin(a7)) * sqrt(rng.randf()) * reach
		c7.y = 0.0
		if not ok.call(c7, 6.0):
			continue
		var roll: float = rng.randf()
		if roll < 0.40:
			knot.call(c7, 2 + rng.randi() % 3, rng.randf() < 0.15)
		elif roll < 0.55:
			knot.call(c7, 2 + rng.randi() % 2, false, Kind.SIT)
		elif roll < 0.68:
			stand.call(c7, Vector3(cos(a7 + 2.0), 0.0, sin(a7 + 2.0)), Kind.WORK)
			stand.call(c7 + Vector3(1.6, 0.0, 0.4), Vector3(cos(a7 + 2.4), 0.0, sin(a7 + 2.4)), Kind.WORK)
		else:
			var dir7 := Vector3(cos(a7 + 1.1), 0.0, sin(a7 + 1.1))
			if not walk.call(c7, c7 + dir7 * rng.randf_range(30.0, 110.0)):
				continue
		placed += 1

	# runners with messages between the watch office and the depot (or out to a pad)
	var run_from: Vector3 = tower + Vector3(11.0, 0.0, 7.0)
	var run_to: Array = [depot + Vector3(16.0, 0.0, 9.0), dump + Vector3(-12.0, 0.0, 3.0)]
	for q in pads:
		run_to.append((q as Vector3) + Vector3(12.0, 0.0, 0.0))
	var runners: int = 0
	for q in run_to:
		if runners >= (1 if dens < 1.4 else 3):
			break
		var rd: Vector3 = (q as Vector3) - run_from
		rd.y = 0.0
		var rl: float = rd.length()
		if rl < 60.0:
			continue
		if beat.call(run_from + rd.normalized() * 8.0, q as Vector3 - rd.normalized() * 8.0, Kind.RUN, rng.randf_range(3.3, 3.9), -1.0, false):
			runners += 1
	# drill: squads marching in step up and down clear stretches near the watch office, an NCO beside each, and a
	# sentry at attention by the line who salutes
	var files: int = 3
	var ranks: int = 2 if dens < 0.75 else (3 if dens < 1.4 else 4)
	var m_len: float = 70.0
	var gap: float = 1.15 * SCALE
	var squads: int = 0
	for _try in 30:
		if squads >= (1 if dens < 1.4 else 2):
			break
		var a4: float = rng.randf() * TAU
		var dir4 := Vector3(cos(a4), 0.0, sin(a4))
		var side4 := Vector3(-dir4.z, 0.0, dir4.x)
		var start: Vector3 = tower + Vector3(cos(a4 + 1.3), 0.0, sin(a4 + 1.3)) * rng.randf_range(35.0, 120.0)
		var back: Vector3 = start - dir4 * gap * float(ranks)
		if not line_ok.call(back - side4 * gap * 1.5, start + dir4 * m_len - side4 * gap * 1.5, 6.0) or not line_ok.call(back + side4 * gap * 2.5, start + dir4 * m_len + side4 * gap * 2.5, 6.0):
			continue
		var m_ph: float = rng.randf()
		for r in ranks:
			for f in files:
				men.append([start - dir4 * gap * float(r) + side4 * gap * (float(f) - 1.0), dir4, Kind.MARCH, m_len, m_ph, 1.45])
		men.append([start - dir4 * gap * 0.5 + side4 * gap * 2.4, dir4, Kind.MARCH, m_len, m_ph, 1.45])          # the NCO
		stand.call(start + dir4 * m_len * 0.5 - side4 * (gap * 1.0 + 5.0), side4, Kind.SALUTE)
		squads += 1
	# a kickabout on the grass near the watch office: five men chasing a ball every which way
	if dens >= 0.75:
		for _try in 14:
			var a5: float = rng.randf() * TAU
			var kc: Vector3 = tower + Vector3(cos(a5), 0.0, sin(a5)) * rng.randf_range(45.0, 140.0)
			if not ok.call(kc, 30.0) or _taxiway_clear(af, inv * kc) < 28.0 or (grid != null and not (grid.free_at(kc + Vector3(10, 0, 0)) and grid.free_at(kc - Vector3(10, 0, 0)) and grid.free_at(kc + Vector3(0, 0, 10)) and grid.free_at(kc - Vector3(0, 0, 10)))):
				continue
			for k in 5:
				var a6: float = TAU * float(k) / 5.0 + rng.randf_range(-0.5, 0.5)
				var kd := Vector3(cos(a6), 0.0, sin(a6))
				var kl: float = rng.randf_range(11.0, 19.0)
				men.append([kc - kd * kl * 0.5 + Vector3(rng.randf_range(-3.0, 3.0), 0.0, rng.randf_range(-3.0, 3.0)), kd, Kind.RUN, kl, -1.0, rng.randf_range(2.4, 3.2), false])
			break
	# men passing a football round a ring on the grass (one near the watch office, another behind the spectators)
	var rings: int = 0
	for _try in 24:
		if rings >= (1 if dens < 1.4 else 2):
			break
		var a9: float = rng.randf() * TAU
		var rc: Vector3 = tower + Vector3(cos(a9), 0.0, sin(a9)) * rng.randf_range(40.0, 160.0)
		if rings == 1:
			rc = thr + tdir * rng.randf_range(0.0, 250.0) + tright * (1.0 if rng.randf() < 0.5 else -1.0) * (off0 + rng.randf_range(30.0, 50.0))
		rc.y = 0.0
		var ring: Array = football_ring(rc, 4 + rng.randi() % 2, rng.randf_range(4.5, 6.5), rng.randf(), false, func(q: Vector3) -> bool: return ok.call(q, 4.0))
		if not ring.is_empty():
			men.append_array(ring)
			rings += 1
	# a file of airmen walking out from the depot together
	var file_to: Vector3 = (pads[0] as Vector3) if not pads.is_empty() else tower
	var fd: Vector3 = file_to - depot
	fd.y = 0.0
	if fd.length() > 60.0:
		var fl: float = minf(fd.length() - 30.0, 180.0)
		var fside: Vector3 = Vector3(-fd.z, 0.0, fd.x).normalized() * 9.0
		var f0: Vector3 = depot + fd.normalized() * 10.0 + fside
		if line_ok.call(f0, f0 + fd.normalized() * (fl + 6.0 * SCALE), 0.0):
			var fph: float = rng.randf()
			for k in 4:
				men.append([f0 + fd.normalized() * (float(k) * 1.3 * SCALE), fd.normalized(), Kind.WALK, fl, fph, 1.45, false])
	# a sentry at the bomb dump
	stand.call(dump + Vector3(-20.0, 0.0, -6.0), tower - dump, Kind.SALUTE)
	# ammunition boxes, oil drums and a few tents by the groups (kept clear of the pads: aircraft swing round there)
	var kit_ok := func(p: Vector3) -> bool:
		if not ok.call(p, 4.0):
			return false
		for q in pads:
			if Vector2((q as Vector3).x - p.x, (q as Vector3).z - p.z).length() < 16.0:
				return false
		return true
	kit_out.append_array(kit_spots(men, seed_v + 3, kit_ok, true, team))
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
	var t0: int = Time.get_ticks_usec()
	var g: Grid = grid_for(container, axf.origin, af.runway_length * 0.75 + 450.0)
	var t1: int = Time.get_ticks_usec()
	var kit: Array = []
	var dens: float = density()
	var pave: Grid = paved_grid(af, axf, af.runway_length * 0.75 + 450.0)
	var inv: Transform3D = axf.affine_inverse()
	var seed0: int = hash(af.airfield_name)
	var extra: Array = []
	var free_ok := func(q: Vector3) -> bool:
		var lq: Vector3 = inv * q
		return g.free_at(q) and pave.free_at(q) and AirfieldActivity.leg_clear(rws, lq, lq, RUNWAY_CLEAR + 4.0)
	# heavy bombers parked behind the spectators at the take-off end, with their crews in front of them
	var bombers: Array = take_off_bombers(container, af, axf, y, team, rws, g, pave, 3 if dens >= 1.0 else 2, seed0 + 11)
	for bm in bombers:
		var bp: Vector3 = bm[0]
		var bf: Vector3 = bm[1]
		var bs: Vector3 = Vector3(-bf.z, 0.0, bf.x)
		var cc: Vector3 = bp + bf * (float(bm[2]) * 0.8 + 5.0)
		for e in [[cc, -bf, Kind.TALK], [cc + bs * 1.5 * SCALE, -bf - bs, Kind.TALK], [cc - bs * 1.6 * SCALE + bf * 0.8, bs, Kind.SMOKER], [cc + bs * 3.4 * SCALE - bf * 1.5, -bf, Kind.WORK]]:
			if free_ok.call(e[0]):
				extra.append([e[0], e[1], e[2], 0.0, -1.0, 0.0, false])
	# a dressing station with ambulances behind the spectators
	var thr: Vector3 = af.get_threshold_position()
	var tdir: Vector3 = WorldCoords.heading_to_dir(af.heading_deg)
	tdir.y = 0.0
	tdir = tdir.normalized()
	var tright := Vector3(-tdir.z, 0.0, tdir.x)
	var off0: float = af.runway_width * 0.5 + RUNWAY_CLEAR + 5.0
	var srng := RandomNumberGenerator.new()
	srng.seed = seed0 + 13
	for k in 24:
		var sgn: float = -1.0 if k % 2 == 0 else 1.0
		var sc: Vector3 = thr + tdir * srng.randf_range(-20.0, 280.0) + tright * sgn * (off0 + srng.randf_range(62.0, 110.0))
		sc.y = 0.0
		var st: Dictionary = dressing_station(sc, -tright * sgn, team, free_ok, srng)
		if st.is_empty():
			continue
		var path: Array = st["path"]
		if not (g.line_free(path[0], path[1]) and pave.line_free(path[0], path[1]) and free_ok.call(path[0])):
			continue
		for it in st["items"]:
			var mi2 := MeshInstance3D.new()
			mi2.mesh = it[0]
			var xf2: Transform3D = it[1]
			xf2.origin.y = y + 0.02
			mi2.transform = xf2
			mi2.visibility_range_end = 3500.0
			mi2.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			mi2.name = "PeopleKit"
			container.add_child(mi2)
			g.mark(xf2 * (it[0] as Mesh).get_aabb())
		for ar in st["area"]:
			g.mark_disc(ar[0], float(ar[1]))
		g.mark_line(path[0], path[1], 3.0)
		extra.append_array(st["men"])
		break
	var men: Array = plan(af, axf, rws, pads, depot, dump, tower, seed0 + 1940, dens, g, kit, team, pave, extra)
	# mechanics at work on the parked aircraft nearest the runway, and at every bomber at the take-off end
	var parked: Array = []
	for ch in container.get_children():
		if ch is AirfieldProp and (ch as AirfieldProp).pkind == "parked":
			parked.append(ch)
	parked.sort_custom(func(a1: AirfieldProp, b1: AirfieldProp) -> bool:
		return absf((inv * a1.position).x) < absf((inv * b1.position).x))
	var mrng := RandomNumberGenerator.new()
	mrng.seed = seed0 + 17
	var mitems: Array = []
	var n_mech: int = int(round(5.0 * dens)) + bombers.size()
	for ap in parked.slice(0, n_mech):
		mechanics_at(ap, mrng, men, mitems)
	for it in mitems:
		var smi := MeshInstance3D.new()
		smi.mesh = it[0]
		var sxf: Transform3D = it[1]
		sxf.origin.y = y + 0.02
		smi.transform = sxf
		smi.visibility_range_end = 2500.0
		smi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		smi.name = "PeopleKit"
		container.add_child(smi)
	var mi: MultiMeshInstance3D = spawn(container, men, Vector3(axf.origin.x, y + 0.01, axf.origin.z), team, hash(af.airfield_name) + 7, af.airfield_name, false)
	add_kit(container, kit, team, func(_p: Vector3) -> float: return y + 0.02)
	_debug_shot(container, men, af.airfield_name)
	print("[people] %s: grid %.1f ms (%d cells blocked), plan + spawn %.1f ms, %d kit" % [af.airfield_name, (t1 - t0) / 1000.0, g.blocked_cells(), (Time.get_ticks_usec() - t1) / 1000.0, kit.size()])
	return mi


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
		var elev: float = float(m[8]) if m.size() > 8 else 0.0      # raised: on a work stand or a wing
		if follow_ground:
			p.y = GroundKit.ground_y(w0.x, w0.z) + 0.01 - origin.y
			p1.y = p.y
			if ln > 1.0:
				var w1: Vector3 = w0 + dir * ln
				p1.y = GroundKit.ground_y(w1.x, w1.z) + 0.01 - origin.y
				dir = (p1 - p).normalized()
		var bas: Basis = Basis.looking_at(dir, Vector3.UP).scaled(Vector3.ONE * MAN)
		mm.set_instance_transform(i, Transform3D(bas, p + Vector3(0.0, elev, 0.0)))
		var spd: float = float(m[5]) if float(m[5]) > 0.0 else rng.randf_range(1.25, 1.65)     # mesh metres a second
		var ph: float = float(m[4]) if float(m[4]) >= 0.0 else rng.randf()
		var dress: int = rng.randi() % CrewFigure.DRESSES
		var soldier: bool = bool(m[6]) if m.size() > 6 else (int(m[2]) == Kind.MARCH or int(m[2]) == Kind.SALUTE)
		var kind: int = int(m[2])
		if kind == Kind.TALK and rng.randf() < 0.22:
			kind = Kind.SMOKER                                  # about one man in five standing about is having a smoke
		var cx: float = p.distance_to(p1) / MAN
		if m.size() > 7 and m[7] is Vector2:
			cx = (m[7] as Vector2).x
			spd = (m[7] as Vector2).y
		mm.set_instance_custom_data(i, Color(cx, spd, ph, float(kind * 8 + (4 if soldier else 0) + dress)))
		for q in [p + Vector3(0.0, elev, 0.0), p1]:
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
	var dens: float = density()
	var occ: Grid = grid_for(container, axf.origin, maxf(ArmyCampKit.HX, ArmyCampKit.HZ) + 80.0)
	var men: Array = []
	var w := func(x: float, z: float) -> Vector3:
		return axf * Vector3(x, 0.0, z)
	var d := func(x: float, z: float) -> Vector3:
		return (axf.basis * Vector3(x, 0.0, z)).normalized()
	var one := func(x: float, z: float, fx: float, fz: float, kind: int) -> void:
		var p: Vector3 = w.call(x, z)
		if occ.free_at(p):
			men.append([p, d.call(fx, fz), kind, 0.0, -1.0, 0.0, true])
	var beat := func(x: float, z: float, fx: float, fz: float, ln: float, kind: int, ph: float, spd: float) -> void:
		var p: Vector3 = w.call(x, z)
		var dv: Vector3 = d.call(fx, fz)
		if kind == Kind.MARCH or occ.line_free(p, p + dv * ln):      # (a squad marches on the open track: its line is checked whole below)
			men.append([p, dv, kind, ln, ph, spd, true])
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
	squad.call(-95.0, -60.0, 1.0, 0.0, 85.0, 3, 4 if dens >= 0.75 else 2)
	squad.call(0.0, 185.0, 0.0, -1.0, 60.0, 3, 3 if dens >= 0.75 else 2)
	# the tank park, the half-tracks and the lorries: crews at work between the rows, others looking on
	for i in range(0, 9, 1 if dens > 1.4 else (2 if dens >= 0.75 else 4)):
		one.call(-210.0 + float(i) * 11.0 + 4.6, -110.0 + 6.0, -1.0, -0.6, Kind.WORK)
		one.call(-210.0 + float(i) * 11.0 + 6.4, -110.0 + 23.5, -1.0, -0.5, Kind.WORK if i % 4 == 0 else Kind.TALK)
	knot.call(-150.0, -64.0, 3, Kind.TALK)
	for i in range(1, 10, 2 if dens > 1.4 else 3):
		one.call(70.0 + float(i) * 11.0 + 5.0, -110.0 + 5.5, -1.0, -0.4, Kind.WORK)
	beat.call(64.0, -102.5, 1.0, 0.0, 104.0, Kind.WALK, -1.0, 0.0)
	beat.call(172.0, -87.5, -1.0, 0.0, 104.0, Kind.WALK, -1.0, 0.0)
	# the battery: a detachment at each gun
	for i in range(0, 6, 1 if dens >= 0.75 else 2):
		one.call(-200.0 + float(i) * 20.0 - 1.9, 43.5, 0.3, -1.0, Kind.WORK)
		one.call(-200.0 + float(i) * 20.0 + 2.1, 44.5, -0.3, -1.0, Kind.TALK if i % 2 == 0 else Kind.WORK)
	# the tent lines: men off duty sat and standing in the lanes between the rows, others walking along them
	for r in 7:
		var lane_z: float = 10.0 + float(r) * 11.0 + 5.5
		if dens < 0.75 and r % 2 == 1:
			continue
		for kk in int(round(2.0 * dens)):
			knot.call(34.0 + rng.randf_range(0.0, 100.0), lane_z, 2 + rng.randi() % 2, Kind.SIT if kk % 2 == 0 else (Kind.TALK if r % 3 != 0 else Kind.SIT))
		if r % 2 == 0:
			beat.call(28.0 if r % 4 == 0 else 150.0, lane_z + 1.5, 1.0 if r % 4 == 0 else -1.0, 0.0, 118.0, Kind.WALK, -1.0, 0.0)
	# the cookhouse queue outside the Nissen huts
	for k in (10 if dens > 1.4 else (7 if dens >= 0.75 else 4)):
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
	if dens > 1.4:
		squad.call(150.0, -60.0, -1.0, 0.0, 90.0, 3, 3)
		beat.call(-150.0, -57.5, 1.0, 0.0, 120.0, Kind.RUN, -1.0, 3.4)
		beat.call(180.0, 107.5, -1.0, 0.0, 160.0, Kind.WALK, -1.0, 0.0)
		beat.call(-2.5, 60.0, 0.0, 1.0, 120.0, Kind.WALK, -1.0, 0.0)
	# and anywhere else in the wire there is open ground: knots of men, men at work, men walking about
	var fx_half: float = ArmyCampKit.HX - 15.0
	var fz_half: float = ArmyCampKit.HZ - 15.0
	var fill: int = int(round(14.0 * dens))
	var placed: int = 0
	for _try in fill * 10:
		if placed >= fill:
			break
		var lx: float = rng.randf_range(-fx_half, fx_half)
		var lz: float = rng.randf_range(-fz_half, fz_half)
		if not occ.free_at(w.call(lx, lz)):
			continue
		var roll: float = rng.randf()
		if roll < 0.45:
			knot.call(lx, lz, 2 + rng.randi() % 3, Kind.TALK)
		elif roll < 0.62:
			knot.call(lx, lz, 2 + rng.randi() % 2, Kind.SIT)
		elif roll < 0.75:
			one.call(lx, lz, rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), Kind.WORK)
		else:
			var a8: float = rng.randf() * TAU
			beat.call(lx, lz, cos(a8), sin(a8), rng.randf_range(25.0, 80.0), Kind.WALK, -1.0, 0.0)
		placed += 1
	# a dressing station with its ambulances, and a ring of men passing a football
	var cinv: Transform3D = axf.affine_inverse()
	var camp_ok := func(q: Vector3) -> bool:
		var lq: Vector3 = cinv * q
		return absf(lq.x) < ArmyCampKit.HX - 12.0 and absf(lq.z) < ArmyCampKit.HZ - 12.0 and occ.free_at(q)
	for _try in 40:
		var sc: Vector3 = w.call(rng.randf_range(-ArmyCampKit.HX + 40.0, ArmyCampKit.HX - 40.0), rng.randf_range(-ArmyCampKit.HZ + 40.0, ArmyCampKit.HZ - 40.0))
		var a5: float = rng.randf() * TAU
		var st: Dictionary = dressing_station(sc, Vector3(cos(a5), 0.0, sin(a5)), team, camp_ok, rng)
		if st.is_empty():
			continue
		var path: Array = st["path"]
		if not (occ.line_free(path[0], path[1]) and camp_ok.call(path[0])):
			continue
		for it in st["items"]:
			var mi2 := MeshInstance3D.new()
			mi2.mesh = it[0]
			var xf2: Transform3D = it[1]
			xf2.origin.y = GroundKit.ground_y(xf2.origin.x, xf2.origin.z) - 0.05
			mi2.transform = xf2
			mi2.visibility_range_end = 3500.0
			mi2.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			mi2.name = "PeopleKit"
			container.add_child(mi2)
			occ.mark(xf2 * (it[0] as Mesh).get_aabb())
		for ar in st["area"]:
			occ.mark_disc(ar[0], float(ar[1]))
		occ.mark_line(path[0], path[1], 3.0)
		men.append_array(st["men"])
		break
	for _try in 30:
		var rc: Vector3 = w.call(rng.randf_range(-ArmyCampKit.HX + 30.0, ArmyCampKit.HX - 30.0), rng.randf_range(-ArmyCampKit.HZ + 30.0, ArmyCampKit.HZ - 30.0))
		var ring: Array = football_ring(rc, 4 + rng.randi() % 2, rng.randf_range(4.5, 6.0), rng.randf(), true, camp_ok)
		if not ring.is_empty():
			men.append_array(ring)
			break
	var c: Vector3 = axf.origin
	var mi: MultiMeshInstance3D = spawn(container, men, Vector3(c.x, GroundKit.ground_y(c.x, c.z), c.z), team, seed_v + 3, "", true)
	if mi != null:
		mi.name = "CampPeople"
	return mi


## Men at any other built site (camps, coastal and anti-invasion defences, V-weapon and radar sites, POW camps,
## ports, docks, works and depots): `soldiers` - men in service dress, sentries, the odd squad at drill - or the
## working dress of the side's ground crews for dockers and works hands. Placed on the open ground among what the
## site built (Grid), never in water or on a steep bank; one MultiMesh per site.
static func populate_site(container: Node3D, center: Vector3, team: String, size: int, soldiers: bool, seed_v: int) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var dens: float = density()
	var radius: float = clampf(55.0 + 40.0 * float(size), 60.0, 240.0)
	var g: Grid = grid_for(container, center, radius + 40.0)
	var target: int = clampi(int(round((9.0 + 6.0 * float(size)) * dens)), 4, 80)
	var men: Array = []
	var ground_ok := func(p: Vector3) -> bool:
		if not g.free_at(p) or GroundKit.is_water(p.x, p.z):
			return false
		var y0: float = GroundKit.raw_y(p.x, p.z)
		return y0 > 0.8 and absf(GroundKit.raw_y(p.x + 2.0, p.z) - y0) < 1.0 and absf(GroundKit.raw_y(p.x, p.z + 2.0) - y0) < 1.0
	var put := func(p: Vector3, face: Vector3, kind: int) -> bool:
		if not ground_ok.call(p):
			return false
		face.y = 0.0
		men.append([p, face.normalized() if face.length() > 0.01 else Vector3.FORWARD, kind, 0.0, -1.0, 0.0, soldiers])
		return true
	var line := func(p0: Vector3, dir: Vector3, ln: float, kind: int, spd: float, ph: float) -> bool:
		var p1: Vector3 = p0 + dir * ln
		if not g.line_free(p0, p1) or not ground_ok.call(p0) or not ground_ok.call(p1) or not ground_ok.call((p0 + p1) * 0.5):
			return false
		men.append([p0, dir, kind, ln, ph, spd, soldiers])
		return true
	var tries: int = 0
	while men.size() < target and tries < target * 14:
		tries += 1
		var a: float = rng.randf() * TAU
		var p: Vector3 = center + Vector3(cos(a), 0.0, sin(a)) * sqrt(rng.randf()) * radius
		p.y = 0.0
		if not ground_ok.call(p):
			continue
		var roll: float = rng.randf()
		if roll < 0.32:
			var cnt: int = 2 + rng.randi() % 3
			var a0: float = rng.randf() * TAU
			for k in cnt:
				var b: float = a0 + TAU * float(k) / float(cnt)
				var q: Vector3 = p + Vector3(cos(b), 0.0, sin(b)) * rng.randf_range(0.9, 1.4) * SCALE
				put.call(q, p - q, Kind.TALK)
		elif roll < 0.44:
			var cnt2: int = 2 + rng.randi() % 2
			var a1: float = rng.randf() * TAU
			for k in cnt2:
				var b2: float = a1 + TAU * float(k) / float(cnt2)
				var q2: Vector3 = p + Vector3(cos(b2), 0.0, sin(b2)) * rng.randf_range(1.3, 1.9) * SCALE
				put.call(q2, p - q2, Kind.SIT if soldiers else Kind.WORK)
		elif roll < 0.72:
			line.call(p, Vector3(cos(a + 1.3), 0.0, sin(a + 1.3)), rng.randf_range(14.0, 55.0), Kind.WALK, 0.0, -1.0)
		elif roll < 0.84:
			put.call(p, Vector3(cos(a), 0.0, sin(a)), Kind.WORK)
			put.call(p + Vector3(1.7, 0.0, 0.3), Vector3(cos(a + 0.5), 0.0, sin(a + 0.5)), Kind.WORK)
		elif roll < 0.90:
			line.call(p, Vector3(cos(a + 0.7), 0.0, sin(a + 0.7)), rng.randf_range(25.0, 70.0), Kind.RUN, rng.randf_range(3.0, 3.8), -1.0)
		elif soldiers:
			put.call(p, center - p, Kind.SALUTE)
		else:
			put.call(p, center - p, Kind.WAVE)
	# a squad at drill where there is a clear 50 m stretch (the bigger military sites)
	if soldiers and size >= 2 and dens >= 0.75:
		for _try in 20:
			var a2: float = rng.randf() * TAU
			var dir := Vector3(cos(a2), 0.0, sin(a2))
			var side := Vector3(-dir.z, 0.0, dir.x)
			var st: Vector3 = center + Vector3(cos(a2 + 2.0), 0.0, sin(a2 + 2.0)) * rng.randf_range(20.0, radius * 0.8)
			var gp: float = 1.15 * SCALE
			if not (g.line_free(st - side * gp * 1.6 - dir * gp * 3.0, st - side * gp * 1.6 + dir * 50.0) and g.line_free(st + side * gp * 2.6 - dir * gp * 3.0, st + side * gp * 2.6 + dir * 50.0) and ground_ok.call(st) and ground_ok.call(st + dir * 50.0) and ground_ok.call(st + dir * 25.0)):
				continue
			var ph: float = rng.randf()
			for r in 2:
				for f in 3:
					men.append([st - dir * gp * float(r) + side * gp * (float(f) - 1.0), dir, Kind.MARCH, 46.0, ph, 1.45, true])
			men.append([st - dir * gp * 0.5 + side * gp * 2.4, dir, Kind.MARCH, 46.0, ph, 1.45, true])
			break
	if men.is_empty():
		return null
	add_kit(container, kit_spots(men, seed_v + 9, ground_ok, soldiers, team), team, func(p: Vector3) -> float: return GroundKit.ground_y(p.x, p.z))
	var mi: MultiMeshInstance3D = spawn(container, men, Vector3(center.x, GroundKit.ground_y(center.x, center.z), center.z), team, seed_v + 5, "", true)
	if mi != null:
		mi.name = "SitePeople"
		if OS.is_debug_build():
			print("[people] site at %.0f, %.0f: %d men" % [center.x, center.z, men.size()])
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
