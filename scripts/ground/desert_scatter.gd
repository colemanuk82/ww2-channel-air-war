class_name DesertScatter
extends RefCounted
## Desert-map countryside scatter, driven by the derived land-cover classes (data/desert/region_landcover.bin, see
## LandCover): camel-thorn and scrub by class (wadi / shrub thick, hamada / reg thin, erg almost bare), boulders on the
## rocky classes, olive rows and cypress windbreaks on orchard land, juniper / olive / cypress on tree cover, date-palm
## groves on oases and on the irrigated crop land round towns and on the delta, dry-stone terrace walls on the
## limestone (Malta, the Hyblaean plateau).
##
## tile_data() is pure data (transform arrays packed with Scatter.multi_data), safe on a worker thread, in the same
## shape as Scatter.tile_landcover_data(); Scatter.build_tile_nodes() hands every "d_*" entry to add_node() here.
## Nothing here runs on the Channel map.

const CELL_M: float = 36.0
const VIS_SCRUB: float = 2300.0
const VIS_BOULDER: float = 2400.0
const VIS_WALL: float = 3200.0
const VIS_HOUSE: float = 7000.0
## per tree kind: [visibility end, full model inside this]; beyond it a one-piece low-poly stand-in
const TREE_RANGE := {"d_palm": [3600.0, 1100.0], "d_olive": [2600.0, 650.0], "d_juniper": [3200.0, 900.0], "d_cypress": [3400.0, 1300.0]}
## the far stand-ins are a thinned copy (1 in N, N times the area): same tone from a distance for a fraction of the triangles
const FAR_THIN := {"d_palm": 3, "d_olive": 4, "d_juniper": 3, "d_cypress": 2}

static var _oases: Array = []
static var _oases_ready: bool = false
static var _mx := Mutex.new()


## --desert-legacy: the pre-class-driven look (sparse scrub only, no pistes, no war scenery), for perf A/B runs.
static var _legacy: int = -1


static func legacy() -> bool:
	if _legacy < 0:
		_legacy = 1 if ("--desert-legacy" in OS.get_cmdline_user_args() or "--desert-legacy" in OS.get_cmdline_args()) else 0
	return _legacy == 1


static func _legacy_data(origin: Vector2, cell: float, seed_v: int, exclude: Array) -> Dictionary:
	var out: Dictionary = {"multis": [], "smokes": []}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var trees_c: Array = []
	var trees_r: Array = []
	var n: int = int(ceil(cell / 60.0))
	for j in n:
		for i in n:
			var p := Vector2(origin.x + (float(i) + rng.randf()) * 60.0, origin.y + (float(j) + rng.randf()) * 60.0)
			var dens: float = 0.05
			if GroundKit.raw_y(p.x, p.y) < 60.0:
				dens = 0.09
			if Scatter._near_sea(p, 2500.0):
				dens = 0.13
			if rng.randf() > dens:
				continue
			if Scatter._ok_tree(p, exclude, 1.5):
				var sc: float = rng.randf_range(0.7, 1.1)
				var tr: Transform3D = Scatter._xf(Vector3(p.x, GroundKit.ground_y(p.x, p.y) - 0.3, p.y), rng.randf() * TAU, Vector3(sc, sc, sc))
				if rng.randf() < 0.5:
					trees_c.append(tr)
				else:
					trees_r.append(tr)
	var tsp: Array = Scatter._split_trees(trees_c, trees_r)
	for tv in tsp.size():
		if not (tsp[tv] as Array).is_empty():
			(out["multis"] as Array).append(["tree_v%d" % tv, Scatter.multi_data(tsp[tv]), 5000.0])
	return out


# ------------------------------------------------------------------ hashing / noise
static func _h(a: int, b: int) -> float:
	var n: int = (a * 374761393 + b * 668265263) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float((n ^ (n >> 16)) & 0xffff) / 65535.0


static func _vn(x: float, z: float, s: float) -> float:
	var fx: float = x / s
	var fz: float = z / s
	var ix: int = floori(fx)
	var iz: int = floori(fz)
	var tx: float = fx - float(ix)
	var tz: float = fz - float(iz)
	tx = tx * tx * (3.0 - 2.0 * tx)
	tz = tz * tz * (3.0 - 2.0 * tz)
	return lerpf(lerpf(_h(ix, iz), _h(ix + 1, iz), tx), lerpf(_h(ix, iz + 1), _h(ix + 1, iz + 1), tx), tz)


# ------------------------------------------------------------------ context
## Towns that carry palm gardens: [Vector2 world xz, radius m]. Every city on the coast or on the delta.
static func towns() -> Array:
	_mx.lock()
	if not _oases_ready:
		for o in Scatter._desert_oases():
			_oases.append([o[0], float(o[2])])
		_oases_ready = true
	_mx.unlock()
	return _oases


static func _near_town(p: Vector2, reach: float) -> bool:
	for t in towns():
		if (t[0] as Vector2).distance_to(p) - float(t[1]) * 0.3 < reach:
			return true
	return false


static func _okc(p: Vector2, exclude: Array, min_h: float) -> bool:
	if not Scatter._land(p.x, p.y, min_h):
		return false
	for e in exclude:
		var c: Vector3 = e[0]
		var r: float = e[1]
		if Vector2(c.x, c.z).distance_squared_to(p) < r * r:
			return false
	return true


static func _put(b: Dictionary, kind: String, p: Vector2, yaw: float, sc: Vector3, sink: float = 0.2) -> void:
	if not b.has(kind):
		b[kind] = []
	(b[kind] as Array).append(Scatter._xf(Vector3(p.x, GroundKit.ground_y(p.x, p.y) - sink, p.y), yaw, sc))


## Bernoulli count from an expected value (a density per cell).
static func _count(rng: RandomNumberGenerator, e: float) -> int:
	var n: int = int(floor(e))
	if rng.randf() < e - float(n):
		n += 1
	return n


# ------------------------------------------------------------------ tile
static func tile_data(origin: Vector2, cell: float, seed_v: int, exclude: Array) -> Dictionary:
	if legacy():
		return _legacy_data(origin, cell, seed_v, exclude)
	var out: Dictionary = {"multis": [], "smokes": []}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var cc := Vector2(origin.x + cell * 0.5, origin.y + cell * 0.5)
	var any_land: bool = false
	for pj in 3:
		for pi in 3:
			if LandCover.class_at(origin.x + cell * (0.15 + 0.35 * float(pi)), origin.y + cell * (0.15 + 0.35 * float(pj))) != 0:
				any_land = true
	if not any_land:
		return out
	var ll: Vector2 = WorldCoords.world_to_latlon(Vector3(cc.x, 0.0, cc.y))
	var malta: bool = ll.x > 35.7 and ll.x < 36.1 and ll.y > 14.1 and ll.y < 14.65
	var delta: bool = ll.x > 30.0 and ll.x < 31.8 and ll.y > 29.4 and ll.y < 31.0
	var town_d: bool = _near_town(cc, 9000.0)
	var b: Dictionary = {}
	var n: int = int(ceil(cell / CELL_M))
	for j in n:
		for i in n:
			var x0: float = origin.x + float(i) * CELL_M
			var z0: float = origin.y + float(j) * CELL_M
			var p := Vector2(x0 + CELL_M * (0.2 + 0.6 * rng.randf()), z0 + CELL_M * (0.2 + 0.6 * rng.randf()))
			# class edges follow the 300 m grid: wobble the lookup so groves and scrub belts get ragged margins
			var cls: int = LandCover.class_at(p.x + (_vn(p.x, p.y, 47.0) - 0.5) * 170.0, p.y + (_vn(p.y + 91.0, p.x, 47.0) - 0.5) * 170.0)
			if cls <= 0:
				continue
			_cell(b, rng, cls, x0, z0, p, exclude, malta, delta, town_d)
	# palm gardens round the coastal towns and on the delta (the curated towns list)
	for t in towns():
		var tc: Vector2 = t[0]
		if tc.x < origin.x - 1500.0 or tc.x > origin.x + cell + 1500.0 or tc.y < origin.y - 1500.0 or tc.y > origin.y + cell + 1500.0:
			continue
		var cnt: int = int(float(t[1]) * 0.07)
		var trng := RandomNumberGenerator.new()
		trng.seed = hash(Vector2i(floori(tc.x), floori(tc.y)))
		for k in cnt:
			var a: float = trng.randf() * TAU
			var q: Vector2 = tc + Vector2(cos(a), sin(a)) * sqrt(trng.randf()) * float(t[1])
			var s1: float = trng.randf_range(0.9, 1.25)
			var s2: float = trng.randf_range(0.85, 1.2)
			if q.x < origin.x or q.x >= origin.x + cell or q.y < origin.y or q.y >= origin.y + cell:
				continue
			var c2: int = LandCover.class_at(q.x, q.y)
			if c2 == 50 or c2 <= 0 or c2 == 111 or c2 == 116:
				continue
			if _okc(q, exclude, 2.0):
				_put(b, "d_palm", q, trng.randf() * TAU, Vector3(s1, s2, s1))
	DesertTown.add_houses(b, origin, cell, seed_v, exclude)       # flat-roofed houses and mosques on class 50
	DesertTown.add_settlements(b, origin, cell, seed_v, exclude)  # extra hamlets and oases from life.json
	for tk in FAR_THIN.keys():
		if not b.has(tk):
			continue
		var th: int = int(FAR_THIN[tk])
		var gs: float = sqrt(float(th))
		var far: Array = []
		for t in (b[tk] as Array):
			var tf: Transform3D = t
			if _h(floori(tf.origin.x * 3.1), floori(tf.origin.z * 3.1)) < 1.0 / float(th):
				far.append(Transform3D(tf.basis * Basis.from_scale(Vector3(gs, 1.0 + (gs - 1.0) * 0.4, gs)), tf.origin))
		b[tk + "_far"] = far
	var order: Array = ["d_scrub0", "d_scrub1", "d_scrub2", "d_boulder_p", "d_boulder_d", "d_palm", "d_olive", "d_cypress", "d_juniper", "d_palm_far", "d_olive_far", "d_cypress_far", "d_juniper_far", "d_wall", "d_house0", "d_house1", "d_house2", "d_house3", "d_roofbox", "d_mosque", "d_market", "d_well"]
	for kind in order:
		if not b.has(kind) or (b[kind] as Array).is_empty():
			continue
		var vis: float = VIS_SCRUB
		if kind.begins_with("d_boulder"):
			vis = VIS_BOULDER
		elif TREE_RANGE.has(kind.trim_suffix("_far")):
			vis = float((TREE_RANGE[kind.trim_suffix("_far")] as Array)[0])
		elif kind == "d_wall":
			vis = VIS_WALL
		elif kind.begins_with("d_house") or kind == "d_roofbox" or kind == "d_mosque" or kind == "d_market":
			vis = VIS_HOUSE
		elif kind == "d_well":
			vis = VIS_WALL
		(out["multis"] as Array).append([kind, Scatter.multi_data(b[kind]), vis])
	return out


static func _scrub_kind(cls: int, p: Vector2) -> String:
	var r: float = _h(floori(p.x / 70.0), floori(p.y / 70.0))
	if cls == 117 or cls == 90 or cls == 20:
		return "d_scrub1" if r < 0.55 else ("d_scrub0" if r < 0.85 else "d_scrub2")
	return "d_scrub0" if r < 0.55 else ("d_scrub2" if r < 0.85 else "d_scrub1")


static func _cell(b: Dictionary, rng: RandomNumberGenerator, cls: int, x0: float, z0: float, p: Vector2, exclude: Array, malta: bool, delta: bool, town_d: bool) -> void:
	var scrub: float = 0.0
	var boulders: float = 0.0
	var patch: float = 0.35 + 1.3 * _vn(p.x, p.y, 110.0)       # scrub grows in clumps, not evenly
	match cls:
		20:
			scrub = 0.62 * patch
		117:
			scrub = 0.85 * patch
		30:
			scrub = 0.2 * patch
		60:
			scrub = 0.045 * patch
		112:
			scrub = 0.04 * patch
		113:
			scrub = 0.022 * patch
			boulders = 0.02
		114:
			scrub = 0.07 * patch
			boulders = 0.4
		115:
			scrub = 0.004
		110:
			scrub = 0.06 * patch
		111:
			scrub = 0.012
		118:
			scrub = 0.1 * patch
			boulders = 0.07
		119:
			boulders = 0.32
		90:
			scrub = 0.4 * patch
		10:
			scrub = 0.3 * patch
		120:
			scrub = 0.2
		121:
			scrub = 0.05
		40:
			scrub = 0.02
	for k in _count(rng, scrub):
		var q := Vector2(x0 + rng.randf() * CELL_M, z0 + rng.randf() * CELL_M)
		if _okc(q, exclude, 1.5):
			var s: float = rng.randf_range(0.8, 1.7)
			_put(b, _scrub_kind(cls, q), q, rng.randf() * TAU, Vector3(s, s * rng.randf_range(0.7, 1.3), s * rng.randf_range(0.8, 1.2)), 0.1)
	for k in _count(rng, boulders):
		var q2 := Vector2(x0 + rng.randf() * CELL_M, z0 + rng.randf() * CELL_M)
		if _okc(q2, exclude, 1.5):
			var s2: float = rng.randf_range(0.7, 2.6)
			var bk: String = "d_boulder_d" if (cls == 119 or (cls == 114 and _h(floori(q2.x / 400.0), floori(q2.y / 400.0)) < 0.3)) else "d_boulder_p"
			_put(b, bk, q2, rng.randf() * TAU, Vector3(s2, s2 * rng.randf_range(0.5, 0.9), s2 * rng.randf_range(0.8, 1.3)), 0.25)
	match cls:
		120:
			for k in _count(rng, 11.0 * (0.6 + 0.8 * _vn(p.x, p.y, 60.0))):
				_palm_at(b, rng, x0, z0, exclude)
		40:
			# irrigated land round the towns and on the delta: palm gardens in groves, the fields stay bare
			var gm: float = _vn(p.x, p.y, 160.0)
			var near: float = 1.0 if (delta or (town_d and _near_town(p, 6000.0))) else 0.0
			if near > 0.0 and gm > 0.4:
				for k in _count(rng, 13.0 * (gm - 0.35)):
					_palm_at(b, rng, x0, z0, exclude)
			if malta:
				_walls(b, p, x0, z0, 34.0, 0.7, exclude)
		121:
			_orchard(b, rng, x0, z0, exclude)
		10:
			for k in _count(rng, 1.25 * (0.4 + 1.2 * _vn(p.x, p.y, 140.0))):
				var q3 := Vector2(x0 + rng.randf() * CELL_M, z0 + rng.randf() * CELL_M)
				if _okc(q3, exclude, 2.0):
					var r3: float = rng.randf()
					var s3: float = rng.randf_range(0.9, 1.5)
					if r3 < 0.35:
						_put(b, "d_cypress", q3, rng.randf() * TAU, Vector3(s3 * 0.8, s3 * rng.randf_range(0.9, 1.4), s3 * 0.8), 0.3)
					elif r3 < 0.7:
						_put(b, "d_juniper", q3, rng.randf() * TAU, Vector3(s3, s3 * rng.randf_range(0.8, 1.2), s3), 0.3)
					else:
						_put(b, "d_olive", q3, rng.randf() * TAU, Vector3(s3, s3 * rng.randf_range(0.8, 1.1), s3), 0.3)
		118:
			_walls(b, p, x0, z0, 38.0, 0.9, exclude)


static func _palm_at(b: Dictionary, rng: RandomNumberGenerator, x0: float, z0: float, exclude: Array) -> void:
	var q := Vector2(x0 + rng.randf() * CELL_M, z0 + rng.randf() * CELL_M)
	if _okc(q, exclude, 2.0):
		var s: float = rng.randf_range(0.85, 1.25)
		_put(b, "d_palm", q, rng.randf() * TAU, Vector3(s, s * rng.randf_range(0.8, 1.25), s), 0.3)


## Olive rows (a rotated lattice, rows run one way over a ~700 m block) with a cypress windbreak line now and then.
static func _orchard(b: Dictionary, rng: RandomNumberGenerator, x0: float, z0: float, exclude: Array) -> void:
	var cx: float = x0 + CELL_M * 0.5
	var cz: float = z0 + CELL_M * 0.5
	var bx: int = floori(cx / 700.0)
	var bz: int = floori(cz / 700.0)
	var ang: float = floorf(_h(bx, bz) * 8.0) * (PI / 8.0) + 0.17
	var sx: float = 17.0 + floorf(_h(bz, bx) * 3.0) * 2.0       # spacing along the row / between the rows
	var sz: float = 14.0 + floorf(_h(bx + 5, bz) * 3.0) * 2.0
	var ca: float = cos(ang)
	var sa: float = sin(ang)
	var umin: float = 1.0e9
	var umax: float = -1.0e9
	var vmin: float = 1.0e9
	var vmax: float = -1.0e9
	for c in [Vector2(x0, z0), Vector2(x0 + CELL_M, z0), Vector2(x0, z0 + CELL_M), Vector2(x0 + CELL_M, z0 + CELL_M)]:
		var u: float = c.x * ca + c.y * sa
		var v: float = -c.x * sa + c.y * ca
		umin = minf(umin, u)
		umax = maxf(umax, u)
		vmin = minf(vmin, v)
		vmax = maxf(vmax, v)
	var windbreak: bool = _h(bx + 11, bz - 4) < 0.5
	for jj in range(floori(vmin / sz), ceili(vmax / sz) + 1):
		for ii in range(floori(umin / sx), ceili(umax / sx) + 1):
			var u2: float = float(ii) * sx
			var v2: float = float(jj) * sz
			var wx: float = u2 * ca - v2 * sa
			var wz: float = u2 * sa + v2 * ca
			if wx < x0 or wx >= x0 + CELL_M or wz < z0 or wz >= z0 + CELL_M:
				continue
			var hh: float = _h(ii * 7 + 3, jj * 13 + 1)
			if hh < 0.05:
				continue              # a missing tree
			var q := Vector2(wx + (hh - 0.5) * 1.2, wz + (_h(ii, jj) - 0.5) * 1.2)
			if not _okc(q, exclude, 2.0):
				continue
			if windbreak and jj % 14 == 0:
				_put(b, "d_cypress", q, 0.0, Vector3(1.0, 1.0 + hh * 0.5, 1.0), 0.3)
			else:
				var s: float = 0.85 + hh * 0.5
				_put(b, "d_olive", q, hh * TAU, Vector3(s, s * (0.85 + hh * 0.2), s), 0.3)


## Dry-stone terrace and field walls: long lines ~spacing apart on a rotated lattice, broken into 10 m lengths with
## gaps, a cross wall now and then (the walled-field pattern of Malta and Ragusa). Unit box scaled to the length.
static func _walls(b: Dictionary, p: Vector2, x0: float, z0: float, spacing: float, prob: float, exclude: Array) -> void:
	var bx: int = floori(p.x / 500.0)
	var bz: int = floori(p.y / 500.0)
	var ang: float = floorf(_h(bx, bz) * 6.0) * (PI / 6.0) + 0.3
	var ca: float = cos(ang)
	var sa: float = sin(ang)
	var seg: float = 10.0
	var umin: float = 1.0e9
	var umax: float = -1.0e9
	var vmin: float = 1.0e9
	var vmax: float = -1.0e9
	for c in [Vector2(x0, z0), Vector2(x0 + CELL_M, z0), Vector2(x0, z0 + CELL_M), Vector2(x0 + CELL_M, z0 + CELL_M)]:
		var u: float = c.x * ca + c.y * sa
		var v: float = -c.x * sa + c.y * ca
		umin = minf(umin, u)
		umax = maxf(umax, u)
		vmin = minf(vmin, v)
		vmax = maxf(vmax, v)
	for jj in range(floori(vmin / spacing) - 1, ceili(vmax / spacing) + 2):
		var v2: float = float(jj) * spacing + (_h(jj, 77) - 0.5) * 8.0
		if v2 < vmin or v2 > vmax:
			continue
		if _h(jj, 31) > prob:
			continue
		for ii in range(floori(umin / seg), ceili(umax / seg) + 1):
			var u2: float = (float(ii) + 0.5) * seg
			if u2 < umin or u2 > umax:
				continue
			if _h(ii + jj * 31, jj) < 0.22:
				continue              # gap in the wall
			var wx: float = u2 * ca - v2 * sa
			var wz: float = u2 * sa + v2 * ca
			if wx < x0 or wx >= x0 + CELL_M or wz < z0 or wz >= z0 + CELL_M:
				continue
			var q := Vector2(wx, wz)
			if _okc(q, exclude, 3.0):
				var y: float = GroundKit.ground_y(wx, wz)
				if not b.has("d_wall"):
					b["d_wall"] = []
				(b["d_wall"] as Array).append(Transform3D(Basis(Vector3.UP, -ang) * Basis.from_scale(Vector3(seg + 0.4, 1.6, 1.2)), Vector3(wx, y + 0.65, wz)))


# ------------------------------------------------------------------ nodes
## Main thread: the multimesh node(s) for one "d_*" entry. Trees get a one-piece stand-in beyond NEAR_TREE.
static func add_node(root: Node, kind: String, d: Dictionary, vis_end: float) -> void:
	if kind.ends_with("_far"):
		var far: MultiMeshInstance3D = Scatter.multi_from_data(mesh(kind), d, vis_end, false)
		far.visibility_range_begin = float((TREE_RANGE[kind.trim_suffix("_far")] as Array)[1]) * Scatter.vis_scale
		far.visibility_range_begin_margin = 150.0
		root.add_child(far)
	elif TREE_RANGE.has(kind):
		var near: MultiMeshInstance3D = Scatter.multi_from_data(mesh(kind), d, float((TREE_RANGE[kind] as Array)[1]))
		near.visibility_range_end_margin = 150.0
		near.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		root.add_child(near)
	else:
		root.add_child(Scatter.multi_from_data(mesh(kind), d, vis_end, false))


static func _sph(r: float, h: float, seg: int = 6, rings: int = 3) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h
	s.radial_segments = seg
	s.rings = rings
	return s


static func _cyl(rt: float, rb: float, h: float, seg: int = 6) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _part(m: Mesh, pos: Vector3, col: Color, foliage: bool = true) -> Array:
	return [m, Transform3D(Basis.IDENTITY, pos), Scatter._dmat(col, 3 if foliage else 0, 0.0, false)]


static func mesh(kind: String) -> ArrayMesh:
	var key: String = "dz_" + kind
	if Scatter._meshes.has(key):
		return Scatter._meshes[key]
	var parts: Array = []
	match kind:
		"d_scrub0", "d_scrub1", "d_scrub2":
			var col: Color = [Color(0.47, 0.45, 0.28), Color(0.30, 0.37, 0.22), Color(0.53, 0.44, 0.31)][int(kind.substr(7))]
			parts.append(_part(_sph(1.1, 1.0, 5, 2), Vector3(0, 0.4, 0), col))
			parts.append(_part(_sph(0.7, 0.7, 5, 2), Vector3(0.7, 0.28, 0.3), col * 0.9))
		"d_boulder_p", "d_boulder_d":
			var bc: Color = Color(0.64, 0.60, 0.52) if kind == "d_boulder_p" else Color(0.23, 0.22, 0.21)
			parts.append(_part(_sph(0.9, 0.85, 5, 2), Vector3(0, 0.3, 0), bc, false))
			parts.append(_part(_sph(0.55, 0.5, 5, 2), Vector3(0.7, 0.14, 0.2), bc * 0.9, false))
		"d_wall":
			var wb := BoxMesh.new()
			wb.size = Vector3(1, 1, 1)
			parts.append(_part(wb, Vector3.ZERO, Color(0.72, 0.64, 0.47), false))
		"d_house0", "d_house1", "d_house2", "d_house3":
			# unit box scaled by the placement: flat-roofed whitewash / sand / ochre / grey-pink
			var hb := BoxMesh.new()
			hb.size = Vector3(1, 1, 1)
			var hcols: Array = [Color(0.91, 0.89, 0.83), Color(0.87, 0.83, 0.73), Color(0.80, 0.74, 0.63), Color(0.89, 0.82, 0.72)]
			parts.append(_part(hb, Vector3.ZERO, hcols[int(kind.substr(7))], false))
		"d_roofbox":
			var rb := BoxMesh.new()
			rb.size = Vector3(1, 1, 1)
			parts.append(_part(rb, Vector3.ZERO, Color(0.80, 0.76, 0.66), false))
		"d_mosque":
			var mb := BoxMesh.new()
			mb.size = Vector3(13, 8, 13)
			var stone: Color = Color(0.90, 0.88, 0.80)
			parts.append(_part(mb, Vector3(0, 4.0, 0), stone, false))
			parts.append(_part(_sph(5.2, 7.0, 10, 4), Vector3(0, 8.0, 0), Color(0.84, 0.82, 0.72), false))
			parts.append(_part(_cyl(0.9, 1.1, 22.0, 6), Vector3(7.6, 11.0, 7.6), stone, false))
			parts.append(_part(_cyl(1.5, 1.5, 0.6, 6), Vector3(7.6, 19.0, 7.6), Color(0.80, 0.77, 0.68), false))
			parts.append(_part(_cyl(0.0, 1.0, 2.6, 6), Vector3(7.6, 23.3, 7.6), Color(0.80, 0.77, 0.68), false))
		"d_market":
			# Open-air souk: striped canvas awnings on posts over trestle stalls, crates and a low wall.
			var canvas := Color(0.74, 0.67, 0.52)
			var stripe := Color(0.58, 0.34, 0.24)
			var wood := Color(0.40, 0.30, 0.20)
			for r in 2:
				for c in 3:
					var cx: float = (float(c) - 1.0) * 7.5
					var cz: float = (float(r) - 0.5) * 8.0
					var aw := BoxMesh.new()
					aw.size = Vector3(5.0, 0.18, 4.0)
					parts.append(_part(aw, Vector3(cx, 2.5, cz), canvas if (r + c) % 2 == 0 else stripe, false))
					for sx in [-1.0, 1.0]:
						for sz in [-1.0, 1.0]:
							parts.append(_part(_cyl(0.09, 0.11, 2.5, 4), Vector3(cx + sx * 2.3, 1.25, cz + sz * 1.8), wood, false))
					var tb := BoxMesh.new()
					tb.size = Vector3(4.2, 0.7, 1.2)
					parts.append(_part(tb, Vector3(cx, 0.35, cz + 0.9), wood, false))
					var cr := BoxMesh.new()
					cr.size = Vector3(0.8, 0.7, 0.8)
					parts.append(_part(cr, Vector3(cx + 1.4, 0.35, cz - 1.2), Color(0.52, 0.42, 0.28), false))
			var wl := BoxMesh.new()
			wl.size = Vector3(24.0, 1.2, 0.7)
			parts.append(_part(wl, Vector3(0.0, 0.6, 8.0), Color(0.62, 0.55, 0.42), false))
		"d_well":
			# Stone well: a ring wall, dark water, two posts and a crossbar.
			var stone := Color(0.64, 0.60, 0.52)
			var wood := Color(0.38, 0.29, 0.19)
			parts.append(_part(_cyl(1.8, 1.7, 1.3, 10), Vector3(0, 0.65, 0), stone, false))
			parts.append(_part(_cyl(1.35, 1.35, 0.1, 10), Vector3(0, 1.28, 0), Color(0.10, 0.16, 0.16), false))
			parts.append(_part(_cyl(0.09, 0.11, 2.2, 4), Vector3(-1.5, 1.9, 0), wood, false))
			parts.append(_part(_cyl(0.09, 0.11, 2.2, 4), Vector3(1.5, 1.9, 0), wood, false))
			parts.append(_part(_cyl(0.07, 0.07, 3.4, 4), Vector3(0, 3.0, 0), wood, false))
		"d_palm":
			_palm_parts(parts, false)
		"d_palm_far":
			_palm_parts(parts, true)
		"d_olive":
			parts.append(_part(_cyl(0.5, 0.7, 2.0, 4), Vector3(0, 1.0, 0), Color(0.30, 0.25, 0.19), false))
			parts.append(_part(_sph(3.1, 3.8, 6, 2), Vector3(0, 3.5, 0), Color(0.36, 0.42, 0.29)))
			parts.append(_part(_sph(2.0, 2.4, 5, 2), Vector3(1.8, 2.9, 0.6), Color(0.42, 0.47, 0.32)))
		"d_olive_far":
			parts.append(_part(_sph(3.6, 4.4, 4, 2), Vector3(0, 3.2, 0), Color(0.37, 0.42, 0.29)))
		"d_cypress":
			parts.append(_part(_cyl(0.15, 1.7, 13.0, 6), Vector3(0, 6.5, 0), Color(0.11, 0.21, 0.12)))
		"d_cypress_far":
			parts.append(_part(_cyl(0.0, 1.8, 13.0, 4), Vector3(0, 6.5, 0), Color(0.11, 0.21, 0.12)))
		"d_juniper":
			parts.append(_part(_cyl(0.3, 0.5, 1.8, 5), Vector3(0, 0.9, 0), Color(0.30, 0.24, 0.18), false))
			parts.append(_part(_cyl(0.0, 2.6, 6.0, 6), Vector3(0, 4.2, 0), Color(0.19, 0.30, 0.17)))
		"d_juniper_far":
			parts.append(_part(_cyl(0.0, 2.7, 7.0, 4), Vector3(0, 3.6, 0), Color(0.19, 0.30, 0.17)))
	var m: ArrayMesh = Scatter._merge(parts)
	Scatter._meshes[key] = m
	return m


## Date palm: tapering trunk, a bulge of date bunches under the crown, 8 arching fronds each in two bent pieces.
static func _palm_parts(parts: Array, far: bool) -> void:
	var trunk: Color = Color(0.43, 0.34, 0.25)
	var frond: Color = Color(0.22, 0.36, 0.15)
	if far:
		parts.append(_part(_cyl(0.3, 0.5, 10.0, 3), Vector3(0, 5.0, 0), trunk, false))
		parts.append(_part(_cyl(3.6, 3.6, 0.7, 4), Vector3(0, 10.3, 0), frond))
		return
	parts.append(_part(_cyl(0.32, 0.55, 10.0, 5), Vector3(0, 5.0, 0), trunk, false))
	parts.append(_part(_sph(0.9, 0.9, 5, 2), Vector3(0, 10.1, 0), Color(0.36, 0.24, 0.12)))
	for f in 6:
		var yaw: float = TAU * float(f) / 6.0 + 0.2 * float(f % 2)
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		var cpos := Vector3(0, 10.2, 0)
		for seg in 2:
			var pitch: float = 0.2 if seg == 0 else 0.75
			var ln: float = 2.6 if seg == 0 else 2.6
			var bm := BoxMesh.new()
			bm.size = Vector3(0.9 if seg == 0 else 0.7, 0.12, ln)
			var basis: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
			var centre: Vector3 = cpos + dir * (ln * 0.5 * cos(pitch)) + Vector3(0, -ln * 0.5 * sin(pitch), 0)
			parts.append([bm, Transform3D(basis, centre), Scatter._dmat(frond * (1.0 + 0.05 * float(f % 3)), 3, 0.0, false)])
			cpos = cpos + dir * (ln * cos(pitch)) + Vector3(0, -ln * sin(pitch), 0)
