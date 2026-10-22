class_name BeachKit
extends RefCounted
## Coast-wide beach defences laid on the real sand: barbed-wire fences and concertina coils at the back of the
## beach, concrete anti-tank cubes and dragon's teeth above the tide line, Czech hedgehogs and Belgian gates in
## the surf, scaffolding fences and the odd pillbox. Axis-held coasts get the full 1940-44 belt, British beaches
## the lighter 1940 invasion-scare set (wire, cubes, scaffolding). Pure data (worker-thread safe): the result is
## a list of [mesh_kind, multi_data, visibility] rows that Scatter.build_tile_nodes turns into MultiMeshes.

const STEP: float = 40.0
const VIS: float = 9000.0
const BIG: float = 2.2          # defences are drawn oversize and dark so they read from the air
static var _meshes: Dictionary = {}
static var _logged: int = 0
static var _cache: Dictionary = {}
static var _mx := Mutex.new()


static func _key(origin: Vector2, cell: float) -> Vector2i:
	return Vector2i(roundi(origin.x / cell), roundi(origin.y / cell))


## Compute the beach defences of several tiles in parallel (one worker task per tile) ahead of the tile builder,
## which then picks the rows out of the cache. Used while the loading screen streams the first tiles in.
static func precompute(keys: Array, cell: float, exclude: Array) -> void:
	var todo: Array = []
	for k in keys:
		if not _cache.has(k):
			todo.append(k)
	if todo.is_empty():
		return
	GroundKit.terrain()          # resolve the cached terrain node on the main thread
	var task: int = WorkerThreadPool.add_group_task(func(i: int) -> void:
		var k2: Vector2i = todo[i]
		var org := Vector2(float(k2.x) * cell, float(k2.y) * cell)
		var seed_v: int = k2.x * 73856093 ^ k2.y * 19349663
		var rows: Array = _compute(org, cell, seed_v, exclude)
		_mx.lock()
		_cache[k2] = rows
		_mx.unlock(), todo.size())
	WorkerThreadPool.wait_for_group_task_completion(task)



static func mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var m: Mesh
	match kind:
		"bk_wire":
			m = _wire_mesh()
		"bk_coil":
			m = _coil_mesh()
		"bk_scaffold":
			m = _scaffold_mesh()
		"bk_gate":
			m = _gate_mesh()
		"bk_pillbox":
			m = _pillbox_mesh()
		"bk_cube":
			m = Scatter.box_unit(Color(0.20, 0.20, 0.19), false)
		"bk_tooth":
			m = _tooth_mesh()
		"bk_hedgehog":
			m = Scatter.hedgehog_mesh()
		_:
			m = Scatter.pole_mesh()
	_meshes[kind] = m
	return m


static func _tooth_mesh() -> ArrayMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 1.5
	cm.height = 1.7
	cm.radial_segments = 4
	cm.rings = 1
	return GroundKit.combine([[cm, Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 0.85, 0)), GroundKit.mat(Color(0.17, 0.17, 0.16), true, 0.04)]])


static func _bx(w: float, h: float, d: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return b


## 6 m run of barbed-wire fence: posts every 3 m, three strands and crossing diagonals (runs along local X).
static func _wire_mesh() -> ArrayMesh:
	var post: ShaderMaterial = GroundKit.mat(Color(0.12, 0.09, 0.06), false)
	var wire: ShaderMaterial = GroundKit.mat(Color(0.03, 0.03, 0.03), false)
	var parts: Array = []
	for x in [-3.0, 0.0, 3.0]:
		parts.append([_bx(0.10, 1.5, 0.10), Transform3D(Basis.IDENTITY, Vector3(x, 0.75, 0.0)), post])
	for y in [0.30, 0.62, 0.95, 1.25]:
		parts.append([_bx(6.0, 0.035, 0.035), Transform3D(Basis.IDENTITY, Vector3(0.0, y, 0.0)), wire])
	for sgn in [-1.0, 1.0]:
		parts.append([_bx(3.6, 0.03, 0.03), Transform3D(Basis(Vector3(0, 0, 1), sgn * 0.62), Vector3(-1.5, 0.78, 0.0)), wire])
		parts.append([_bx(3.6, 0.03, 0.03), Transform3D(Basis(Vector3(0, 0, 1), sgn * 0.62), Vector3(1.5, 0.78, 0.0)), wire])
	return GroundKit.combine(parts)


## 6 m of concertina wire: a row of loose coils lying on the sand.
static func _coil_mesh() -> ArrayMesh:
	var wire: ShaderMaterial = GroundKit.mat(Color(0.04, 0.04, 0.04), false)
	var parts: Array = []
	for i in 9:
		var t := TorusMesh.new()
		t.inner_radius = 0.40
		t.outer_radius = 0.46
		t.rings = 10
		t.ring_segments = 3
		parts.append([t, Transform3D(Basis.from_euler(Vector3(0.0, 0.0, PI * 0.5)) * Basis(Vector3.RIGHT, 0.0), Vector3(-3.0 + float(i) * 0.75, 0.46, 0.0)), wire])
	return GroundKit.combine(parts)


## UK 1940 anti-landing scaffolding fence: tubular poles every 2 m, four rails and diagonals, 6 m long.
static func _scaffold_mesh() -> ArrayMesh:
	var tube: ShaderMaterial = GroundKit.mat(Color(0.13, 0.13, 0.12), false)
	var parts: Array = []
	for x in [-3.0, -1.0, 1.0, 3.0]:
		parts.append([_bx(0.09, 2.5, 0.09), Transform3D(Basis.IDENTITY, Vector3(x, 1.15, 0.0)), tube])
	for y in [0.45, 1.0, 1.55, 2.1]:
		parts.append([_bx(6.0, 0.07, 0.07), Transform3D(Basis.IDENTITY, Vector3(0.0, y, 0.0)), tube])
	for sgn in [-1.0, 1.0]:
		parts.append([_bx(3.2, 0.06, 0.06), Transform3D(Basis(Vector3(0, 0, 1), sgn * 0.7), Vector3(-2.0, 1.2, 0.0)), tube])
		parts.append([_bx(3.2, 0.06, 0.06), Transform3D(Basis(Vector3(0, 0, 1), sgn * 0.7), Vector3(2.0, 1.2, 0.0)), tube])
	return GroundKit.combine(parts)


## Belgian gate (Cointet element): a rusty girder gate on two props, facing the sea.
static func _gate_mesh() -> ArrayMesh:
	var rust: ShaderMaterial = GroundKit.mat(Color(0.16, 0.09, 0.06), false)
	var parts: Array = []
	parts.append([_bx(0.22, 3.0, 0.22), Transform3D(Basis.IDENTITY, Vector3(-1.7, 1.5, 0.0)), rust])
	parts.append([_bx(0.22, 3.0, 0.22), Transform3D(Basis.IDENTITY, Vector3(1.7, 1.5, 0.0)), rust])
	parts.append([_bx(3.6, 0.22, 0.22), Transform3D(Basis.IDENTITY, Vector3(0.0, 2.7, 0.0)), rust])
	parts.append([_bx(3.6, 0.22, 0.22), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0)), rust])
	parts.append([_bx(0.2, 2.6, 0.2), Transform3D(Basis(Vector3.RIGHT, 0.7), Vector3(-1.7, 1.2, 1.0)), rust])
	parts.append([_bx(0.2, 2.6, 0.2), Transform3D(Basis(Vector3.RIGHT, 0.7), Vector3(1.7, 1.2, 1.0)), rust])
	return GroundKit.combine(parts)


## Low concrete pillbox with an embrasure on the local -Z (sea) face.
static func _pillbox_mesh() -> ArrayMesh:
	var conc: ShaderMaterial = GroundKit.mat(Color(0.26, 0.26, 0.25), true, 0.05)
	var dark: ShaderMaterial = GroundKit.mat(Color(0.05, 0.05, 0.05), false)
	var parts: Array = []
	parts.append([_bx(6.5, 2.6, 6.5), Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), conc])
	parts.append([_bx(7.2, 0.4, 7.2), Transform3D(Basis.IDENTITY, Vector3(0.0, 2.4, 0.0)), conc])
	parts.append([_bx(2.4, 0.5, 0.3), Transform3D(Basis.IDENTITY, Vector3(0.0, 1.6, -3.3)), dark])
	return GroundKit.combine(parts)


## Which side of the Channel median line (no GameState lookup: this runs on a worker thread).
static func _axis_held(p: Vector2) -> bool:
	var ll: Vector2 = WorldCoords.world_to_latlon(Vector3(p.x, 0.0, p.y))
	var lat: float = ll.x
	var lon: float = ll.y
	if lon >= 1.5 and not (lat > 51.45 and lon < 2.0):
		return true
	var keys: Array = [[-4.6, 50.0], [-1.0, 50.25], [0.0, 50.38], [0.8, 50.85], [1.2, 51.05], [1.5, 51.3]]
	var mid: float = 50.0
	if lon > -4.6:
		for i in range(keys.size() - 1):
			var a: Array = keys[i]
			var b: Array = keys[i + 1]
			if lon >= float(a[0]) and lon <= float(b[0]):
				mid = lerpf(float(a[1]), float(b[1]), (lon - float(a[0])) / (float(b[0]) - float(a[0])))
	return lat <= mid


static func _sea_near(p: Vector2, r: float) -> bool:
	for k in 8:
		var a: float = TAU * float(k) / 8.0
		if GroundKit.raw_y(p.x + cos(a) * r, p.y + sin(a) * r) < 0.3:
			return true
	return false


static func _in_exclude(p: Vector2, exclude: Array) -> bool:
	for e in exclude:
		var c: Vector3 = e[0]
		var r: float = e[1]
		if Vector2(c.x, c.z).distance_squared_to(p) < r * r:
			return true
	return false


static func _put(lists: Dictionary, kind: String, x: float, z: float, lift: float, yaw: float, sc: Vector3, min_h: float = 0.5) -> void:
	if GroundKit.raw_y(x, z) < min_h:
		return
	if not lists.has(kind):
		lists[kind] = []
	(lists[kind] as Array).append(Scatter._xf(Vector3(x, GroundKit.ground_y(x, z) + lift, z), yaw, sc))


## The tile's beach defences as multimesh rows (see Scatter.build_tile_nodes).
static func tile_multis(origin: Vector2, cell: float, seed_v: int, exclude: Array) -> Array:
	var k: Vector2i = _key(origin, cell)
	_mx.lock()
	var hit: bool = _cache.has(k)
	var rows_c: Array = _cache.get(k, [])
	if hit:
		_cache.erase(k)
	_mx.unlock()
	if hit:
		return rows_c
	return _compute(origin, cell, seed_v, exclude)


static func _compute(origin: Vector2, cell: float, seed_v: int, exclude: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v ^ 0x5be4c
	var lists: Dictionary = {}
	var n: int = int(ceil(cell / STEP))
	# Coarse pre-pass: 150 m blocks (plus a one-block margin) that have open water in them. Inland tiles exit here
	# after ~170 height samples; coastal tiles only scan the cells in blocks next to the sea.
	var cb: int = int(ceil(cell / 150.0)) + 2
	var wet := PackedByteArray()
	wet.resize(cb * cb)
	var any_water: bool = false
	for bj in cb:
		for bi in cb:
			var wx: float = origin.x + (float(bi) - 1.0) * 150.0 + 75.0
			var wz: float = origin.y + (float(bj) - 1.0) * 150.0 + 75.0
			if GroundKit.raw_y(wx, wz) < 0.3:
				wet[bj * cb + bi] = 1
				any_water = true
	if not any_water:
		return []
	var near := PackedByteArray()
	near.resize(cb * cb)
	for bj in cb:
		for bi in cb:
			if wet[bj * cb + bi] == 1:
				for dj in range(-1, 2):
					for di in range(-1, 2):
						var nj: int = bj + dj
						var ni: int = bi + di
						if nj >= 0 and nj < cb and ni >= 0 and ni < cb:
							near[nj * cb + ni] = 1
	var cells: int = 0
	for j in n:
		for i in n:
			var p := Vector2(origin.x + (float(i) + 0.5) * STEP, origin.y + (float(j) + 0.5) * STEP)
			var kbi: int = clampi(int((p.x - origin.x) / 150.0) + 1, 0, cb - 1)
			var kbj: int = clampi(int((p.y - origin.y) / 150.0) + 1, 0, cb - 1)
			if near[kbj * cb + kbi] == 0:
				continue
			var h: float = GroundKit.raw_y(p.x, p.y)
			if h < 0.9 or h > 9.0:
				continue
			if not _sea_near(p, 90.0):
				continue                         # cheap reject before the 16-ray search
			var sea: Vector3 = GroundKit.water_dir(Vector3(p.x, 0.0, p.y), 100.0)
			if sea == Vector3.ZERO:
				continue
			if _in_exclude(p, exclude):
				continue
			# distance from here to the waterline along the sea direction, and the beach slope
			var rw: float = 6.0
			while rw < 120.0 and GroundKit.raw_y(p.x + sea.x * rw, p.y + sea.z * rw) > 0.5:
				rw += 4.0
			var slope: float = absf(GroundKit.raw_y(p.x + sea.x * 8.0, p.y + sea.z * 8.0) - GroundKit.raw_y(p.x - sea.x * 8.0, p.y - sea.z * 8.0)) / 16.0
			if slope > 0.55 or rw > 110.0:
				continue                         # cliff foot / marsh flat, not a beach
			var axis: bool = _axis_held(p)
			if not axis and rng.randf() > 0.6:
				continue
			cells += 1
			var perp := Vector3(-sea.z, 0.0, sea.x)
			var yaw: float = atan2(-perp.z, perp.x)
			var base := Vector3(p.x, 0.0, p.y)     # a point on the beach; the waterline is rw metres seaward of it
			# back of the beach: barbed wire fence, with concertina coils in front on the Axis side
			var wd: float = rw - 34.0
			for k in 7:
				var wp: Vector3 = base + sea * wd + perp * (float(k) - 3.0) * 6.0
				_put(lists, "bk_wire", wp.x, wp.z, 0.0, yaw, Vector3(1.0, BIG, BIG), 0.8)
				if axis:
					var cp: Vector3 = wp + sea * 4.0
					_put(lists, "bk_coil", cp.x, cp.z, 0.0, yaw, Vector3(1.0, BIG, BIG), 0.8)
			# above the tide line: dragon's teeth (Axis) / concrete tank cubes (British)
			var td: float = rw - 9.0
			for k2 in 9:
				var tp: Vector3 = base + sea * (td + sin(float(k2) * 1.9) * 1.1) + perp * (float(k2) - 4.0) * 4.4 * BIG * 0.8
				if axis:
					_put(lists, "bk_tooth", tp.x, tp.z, -0.2 * BIG, rng.randf() * TAU, Vector3.ONE * BIG * rng.randf_range(0.9, 1.2), 0.5)
				else:
					_put(lists, "bk_cube", tp.x, tp.z, 0.55 * BIG, yaw + rng.randf_range(-0.15, 0.15), Vector3.ONE * 1.3 * BIG, 0.5)
			# scaffolding fence (UK 1940, and some Axis stretches)
			if not axis or rng.randf() < 0.35:
				for k3 in 6:
					var sp: Vector3 = base + sea * (rw - 20.0) + perp * (float(k3) - 2.5) * 6.0
					_put(lists, "bk_scaffold", sp.x, sp.z, 0.0, yaw, Vector3(1.0, BIG, BIG), 0.7)
			# in the surf: Czech hedgehogs and Belgian gates (Axis)
			if axis:
				for k4 in 4:
					var hp: Vector3 = base + sea * (rw + rng.randf_range(10.0, 45.0)) + perp * rng.randf_range(-18.0, 18.0)
					_put(lists, "bk_hedgehog", hp.x, hp.z, 0.0, rng.randf() * TAU, Vector3.ONE * BIG * rng.randf_range(0.8, 1.2), -1.2)
				if rng.randf() < 0.5:
					for k5 in 3:
						var gp: Vector3 = base + sea * (rw + 25.0) + perp * (float(k5) - 1.0) * 12.0 * 1.4
						_put(lists, "bk_gate", gp.x, gp.z, 0.0, yaw + rng.randf_range(-0.2, 0.2), Vector3.ONE * BIG, -1.2)
				# the occasional pillbox behind the wire, facing the sea
				if rng.randf() < 0.12:
					var pb: Vector3 = base + sea * (wd - 10.0)
					if GroundKit.raw_y(pb.x, pb.z) > 1.0:
						_put(lists, "bk_pillbox", pb.x, pb.z, 0.0, atan2(sea.x, sea.z) + PI, Vector3.ONE * 1.6, 1.0)
	var out: Array = []
	if cells > 0 and _logged < 6:
		_logged += 1
		var tot: int = 0
		for k6 in lists:
			tot += (lists[k6] as Array).size()
		print("[beach] tile at %d,%d: %d beach cells, %d obstacles %s" % [int(origin.x), int(origin.y), cells, tot, str(lists.keys())])
	for kind in lists:
		var xs: Array = lists[kind]
		if not xs.is_empty():
			out.append([kind, Scatter.multi_data(xs), VIS])
	return out
