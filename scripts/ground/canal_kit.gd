class_name CanalKit
extends RefCounted
## 1940s canal furniture (P6): locks and lock keepers' cottages, aqueducts, basins, wharves, dry docks,
## narrowboats and barges, and canal-side industry - placed along the real canal centrelines already in
## data/osm/rivers.json (k == "canal"). No water is re-fetched and canals are not re-derived.
##
##   CanalKit.ensure_loaded()                       # once, from WorldPopulator._ready()
##   var n: Node3D = CanalKit.build_tile(org, size) # per world tile (built on the main thread)
##
## Furniture is placed at a fixed arc-length spacing along each canal and classified deterministically
## (locks on a fixed cadence, aqueducts where a canal actually crosses a river line, basins at canal
## junctions, the rest scattered), so a freed and re-streamed tile rebuilds identically. All procedural
## low-poly toon from GroundKit primitives - no photo textures.

const CELL: float = 1800.0           # world-tile index cell, matches WorldPopulator.TILE
const WATER_CELL: float = 120.0      # spatial-hash cell for the river points used by aqueduct detection
const LOCK_SPAN: float = 2400.0      # average spacing of locks along a canal reach (metres)
const FURN_SPAN: float = 650.0       # spacing between furniture steps along a canal

static var loaded: bool = false
static var canals: Array = []        # {"pts": PackedVector2Array (x,z), "cum": PackedFloat32Array, "len": float}
static var _cells: Dictionary = {}   # Vector2i -> Array of Vector3i(line index, first, last)
static var _water_pts: Dictionary = {}   # Vector2i -> Array of Vector2: river/stream points (aqueduct crossings)


static func ensure_loaded() -> void:
	if loaded:
		return
	loaded = true
	var path: String = "res://data/osm/rivers.json"
	if not FileAccess.file_exists(path):
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	for l in (d as Dictionary).get("lines", []):
		var k: String = String(l.get("k", "river"))
		var raw: Array = l.get("pts", [])
		if raw.size() < 2:
			continue
		var pts := PackedVector2Array()
		var cum := PackedFloat32Array()
		var len_m: float = 0.0
		for p in raw:
			var w: Vector3 = WorldCoords.latlon_to_world(float(p[0]), float(p[1]))
			var q := Vector2(w.x, w.z)
			if pts.size() > 0:
				len_m += pts[pts.size() - 1].distance_to(q)
			pts.append(q)
			cum.append(len_m)
		if k == "canal":
			if pts.size() >= 2 and len_m >= 1.0:
				_register_canal(pts, cum, len_m)
		elif k == "river" or k == "stream":
			_index_water(pts)


static func _register_canal(pts: PackedVector2Array, cum: PackedFloat32Array, len_m: float) -> void:
	var idx: int = canals.size()
	canals.append({"pts": pts, "cum": cum, "len": len_m})
	var ranges: Dictionary = {}
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var steps: int = maxi(int(a.distance_to(b) / (CELL * 0.5)), 1)
		for st in steps + 1:
			var q: Vector2 = a.lerp(b, float(st) / float(steps))
			var key := Vector2i(floori(q.x / CELL), floori(q.y / CELL))
			if ranges.has(key):
				var r: Vector2i = ranges[key]
				ranges[key] = Vector2i(mini(r.x, i), maxi(r.y, i))
			else:
				ranges[key] = Vector2i(i, i)
	for key in ranges.keys():
		var r2: Vector2i = ranges[key]
		if not _cells.has(key):
			_cells[key] = []
		(_cells[key] as Array).append(Vector3i(idx, r2.x, r2.y))


## Hash a river/stream line's points into the coarse water grid (for aqueduct crossing detection).
static func _index_water(pts: PackedVector2Array) -> void:
	for i in range(0, pts.size(), 2):
		var q: Vector2 = pts[i]
		var key := Vector2i(floori(q.x / WATER_CELL), floori(q.y / WATER_CELL))
		if not _water_pts.has(key):
			_water_pts[key] = []
		(_water_pts[key] as Array).append(q)


static func canal_count() -> int:
	return canals.size()


static func total_km() -> float:
	var km: float = 0.0
	for ln in canals:
		km += float(ln["len"])
	return km / 1000.0


static func _sample(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	if s <= 0.0:
		return pts[0]
	if s >= cum[cum.size() - 1]:
		return pts[pts.size() - 1]
	for i in range(cum.size() - 1):
		if s <= cum[i + 1]:
			var seg: float = maxf(cum[i + 1] - cum[i], 0.0001)
			return pts[i].lerp(pts[i + 1], (s - cum[i]) / seg)
	return pts[pts.size() - 1]


static func _tangent(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	for i in range(cum.size() - 1):
		if s <= cum[i + 1]:
			var d: Vector2 = pts[i + 1] - pts[i]
			return d.normalized() if d.length() > 0.001 else Vector2(0.0, 1.0)
	return (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()


static func _ranges_for(origin: Vector2) -> Dictionary:
	var ranges: Dictionary = {}
	var cx0: int = floori(origin.x / CELL)
	var cz0: int = floori(origin.y / CELL)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := Vector2i(cx0 + dx, cz0 + dz)
			if not _cells.has(key):
				continue
			for e in (_cells[key] as Array):
				var ev: Vector3i = e
				if ranges.has(ev.x):
					var r: Vector2i = ranges[ev.x]
					ranges[ev.x] = Vector2i(mini(r.x, ev.y), maxi(r.y, ev.z))
				else:
					ranges[ev.x] = Vector2i(ev.y, ev.z)
	return ranges


static func _poly_near(pts: PackedVector2Array, c: Vector2, radius: float) -> bool:
	var r2: float = radius * radius
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab: Vector2 = b - a
		var l2: float = maxf(ab.length_squared(), 0.0001)
		var t: float = clampf((c - a).dot(ab) / l2, 0.0, 1.0)
		if (a + ab * t).distance_squared_to(c) <= r2:
			return true
	return false


static func _near_water(p: Vector2, r: float) -> bool:
	var c: int = int(ceil(r / WATER_CELL))
	var cx: int = floori(p.x / WATER_CELL)
	var cz: int = floori(p.y / WATER_CELL)
	for dz in range(-c, c + 1):
		for dx in range(-c, c + 1):
			var key := Vector2i(cx + dx, cz + dz)
			if not _water_pts.has(key):
				continue
			for q in (_water_pts[key] as Array):
				if (q as Vector2).distance_squared_to(p) <= r * r:
					return true
	return false


static func _near_canal(p: Vector2, r: float, exclude_li: int) -> bool:
	var c: int = int(ceil(r / CELL))
	var cx: int = floori(p.x / CELL)
	var cz: int = floori(p.y / CELL)
	for dz in range(-c, c + 1):
		for dx in range(-c, c + 1):
			var key := Vector2i(cx + dx, cz + dz)
			if not _cells.has(key):
				continue
			for e in (_cells[key] as Array):
				var li: int = (e as Vector3i).x
				if li == exclude_li:
					continue
				if _poly_near(canals[li]["pts"], p, r):
					return true
	return false


# ------------------------------------------------------------------ piece builders
static func _holder(parent: Node3D, p: Vector3, head: float) -> Node3D:
	var h := Node3D.new()
	h.position = p
	h.rotation.y = -deg_to_rad(head)
	parent.add_child(h)
	return h


## A pitched-roof building the canal furniture shares (cottage / warehouse / works).
static func _house(parent: Node3D, p: Vector3, yaw: float, size: Vector3, brick: Color) -> void:
	var h := Node3D.new()
	h.position = p
	h.rotation.y = yaw
	parent.add_child(h)
	GroundKit.box(h, size, Vector3(0.0, size.y * 0.5, 0.0), brick)
	var pm := MeshInstance3D.new()
	pm.mesh = GroundKit.prism_mesh(size.z + 0.6, size.x + 0.6, minf(size.x, size.z) * 0.35)
	pm.material_override = GroundKit.mat(brick.darkened(0.3), true)
	pm.position = Vector3(0.0, size.y, 0.0)
	pm.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	h.add_child(pm)
	GroundKit.cyl(h, 0.5, 0.6, 1.6, Vector3(size.x * 0.32, size.y + size.z * 0.2 + 0.6, size.z * 0.3), brick.darkened(0.45), Vector3.ZERO, 6)


## A moored narrowboat (barge=false) or barge (barge=true): a flattish steel/wood hull with a cabin.
static func _boat(parent: Node3D, p: Vector3, head: float, barge: bool, rng: RandomNumberGenerator) -> void:
	var h: Node3D = _holder(parent, p, head)
	var L: float = 22.0 if barge else 14.0
	var W: float = 4.6 if barge else 2.2
	var hull: Color = Color(0.22, 0.2, 0.18) if rng.randf() < 0.5 else Color(0.3, 0.24, 0.16)
	GroundKit.box(h, Vector3(W, 1.4, L), Vector3(0.0, 0.5, 0.0), hull)
	GroundKit.box(h, Vector3(W - 0.5, 0.4, L - 1.2), Vector3(0.0, 1.25, 0.0), Color(0.14, 0.12, 0.1), Vector3.ZERO, false)   # open hold
	GroundKit.box(h, Vector3(W - 0.6, 1.1, L * 0.28), Vector3(0.0, 1.9, -L * 0.28), Color(0.5, 0.42, 0.28))                     # cabin
	GroundKit.box(h, Vector3(W - 0.8, 0.16, L * 0.2), Vector3(0.0, 1.05, L * 0.38), hull.darkened(0.2), Vector3.ZERO, false)     # bow deck


## A narrow lock: a stone chamber with a water strip, mitre gates and balance beams at both ends, bollards,
## and a lock keeper's cottage on the bank.
static func _lock(parent: Node3D, p: Vector3, head: float, rng: RandomNumberGenerator) -> void:
	var stone: Color = Color(0.5, 0.48, 0.43)
	var wood: Color = GroundKit.COL_WOOD
	var h: Node3D = _holder(parent, p, head)
	var water: MeshInstance3D = GroundKit.box(h, Vector3(5.0, 0.15, 26.0), Vector3(0.0, 0.12, 0.0), Color(0.16, 0.3, 0.42), Vector3.ZERO, false)
	water.material_override = GroundKit.glow_mat(Color(0.16, 0.3, 0.42), 0.86, false)
	for sx in [-1.0, 1.0]:
		GroundKit.box(h, Vector3(1.4, 2.6, 26.0), Vector3(sx * 3.2, 1.3, 0.0), stone)
	for sz in [-1.0, 1.0]:
		GroundKit.box(h, Vector3(7.0, 3.2, 1.2), Vector3(0.0, 1.6, sz * 13.2), stone.darkened(0.1))
		GroundKit.box(h, Vector3(2.8, 2.6, 0.5), Vector3(-1.6, 1.3, sz * 12.6), wood, Vector3(0.0, sz * 16.0, 0.0))
		GroundKit.box(h, Vector3(2.8, 2.6, 0.5), Vector3(1.6, 1.3, sz * 12.6), wood, Vector3(0.0, sz * -16.0, 0.0))
		GroundKit.box(h, Vector3(4.4, 0.4, 0.4), Vector3(3.6, 1.0, sz * 12.6), wood.darkened(0.2))
	for sz2 in [-1.0, 0.0, 1.0]:
		GroundKit.cyl(h, 0.35, 0.4, 1.4, Vector3(4.2, 0.8, sz2 * 9.0), GroundKit.COL_DARK, Vector3.ZERO, 6, false)
	var rad: float = deg_to_rad(head)
	var bank := Vector2(cos(rad), sin(rad)) * 15.0
	var cp := Vector3(p.x + bank.x, GroundKit.ground_y(p.x + bank.x, p.z + bank.y), p.z + bank.y)
	_house(parent, cp, -rad, Vector3(8.0, 4.0, 6.0), GroundKit.COL_BRICK)


## A canal aqueduct: a water trough on masonry piers carrying the canal over the river it crosses.
static func _aqueduct(parent: Node3D, p: Vector3, head: float) -> void:
	var stone: Color = Color(0.5, 0.48, 0.43)
	var h: Node3D = _holder(parent, p, head)
	var len_z: float = 40.0
	var trough: MeshInstance3D = GroundKit.box(h, Vector3(5.6, 1.0, len_z), Vector3(0.0, 6.0, 0.0), stone.darkened(0.05))
	GroundKit.box(h, Vector3(4.6, 0.2, len_z - 0.6), Vector3(0.0, 6.6, 0.0), Color(0.16, 0.3, 0.42), Vector3.ZERO, false)
	for sz in [-1.0, 1.0]:
		GroundKit.box(h, Vector3(6.8, 1.4, 1.4), Vector3(0.0, 6.9, sz * (len_z * 0.5)), stone)                     # parapet caps
	for i in 3:
		var z: float = -len_z * 0.35 + float(i) * (len_z * 0.35)
		GroundKit.box(h, Vector3(5.0, 6.0, 3.2), Vector3(0.0, 3.0, z), stone.darkened(0.08))                     # pier
		GroundKit.box(h, Vector3(7.0, 1.0, 4.0), Vector3(0.0, 5.5, z), stone)                                    # pier cap


## A canal basin: a wider pool off the main line with a quay wall, bollards and moored boats.
static func _basin(parent: Node3D, p: Vector3, head: float, rng: RandomNumberGenerator) -> void:
	var stone: Color = Color(0.5, 0.48, 0.43)
	var h: Node3D = _holder(parent, p, head)
	var water: MeshInstance3D = GroundKit.box(h, Vector3(46.0, 0.2, 44.0), Vector3(0.0, 0.1, 0.0), Color(0.16, 0.3, 0.42), Vector3.ZERO, false)
	water.material_override = GroundKit.glow_mat(Color(0.16, 0.3, 0.42), 0.86, false)
	for sx in [-1.0, 1.0]:
		GroundKit.box(h, Vector3(2.0, 2.2, 44.0), Vector3(sx * 23.0, 1.1, 0.0), stone)
	for sz in [-1.0, 1.0]:
		GroundKit.box(h, Vector3(46.0, 2.2, 2.0), Vector3(0.0, 1.1, sz * 22.0), stone)
	for i in 5:
		GroundKit.cyl(h, 0.4, 0.5, 1.4, Vector3(-22.0 + float(i) * 11.0, 2.6, 21.0), GroundKit.COL_DARK, Vector3.ZERO, 6, false)
	_boat(h, Vector3(-8.0, 0.0, 8.0), 90.0, false, rng)
	_boat(h, Vector3(8.0, 0.0, 8.0), 90.0, true, rng)


## A wharf: a quay wall, a transit shed, a hand crane and moored boats.
static func _wharf(parent: Node3D, p: Vector3, head: float, rng: RandomNumberGenerator) -> void:
	var stone: Color = Color(0.5, 0.48, 0.43)
	var h: Node3D = _holder(parent, p, head)
	GroundKit.box(h, Vector3(36.0, 2.6, 6.0), Vector3(0.0, 1.3, 8.0), stone)                                          # quay wall
	_house(h, Vector3(0.0, 0.0, 15.0), 0.0, Vector3(26.0, 6.0, 9.0), GroundKit.COL_BRICK)                              # transit shed
	var crane := Node3D.new()
	crane.position = Vector3(12.0, 2.6, 8.0)
	h.add_child(crane)
	GroundKit.cyl(crane, 0.6, 0.8, 9.0, Vector3(0.0, 4.5, 0.0), GroundKit.COL_STEEL, Vector3.ZERO, 6)
	GroundKit.cyl(crane, 0.35, 0.45, 8.0, Vector3(3.0, 8.5, 0.0), GroundKit.COL_STEEL, Vector3(0.0, 0.0, 68.0), 6)      # jib
	GroundKit.box(crane, Vector3(1.4, 1.2, 1.4), Vector3(0.0, 9.4, 0.0), GroundKit.COL_DARK, Vector3.ZERO, false)       # cab
	_boat(h, Vector3(-10.0, 0.0, 2.0), 90.0, false, rng)
	_boat(h, Vector3(6.0, 0.0, 2.0), 90.0, true, rng)


## A dry dock: a stone-walled, gate-fitting graving dock with a vessel resting on the blocks.
static func _dry_dock(parent: Node3D, p: Vector3, head: float, rng: RandomNumberGenerator) -> void:
	var stone: Color = Color(0.5, 0.48, 0.43)
	var h: Node3D = _holder(parent, p, head)
	GroundKit.box(h, Vector3(16.0, 0.4, 40.0), Vector3(0.0, 0.2, 0.0), stone.darkened(0.15), Vector3.ZERO, false)       # floor
	for sx in [-1.0, 1.0]:
		GroundKit.box(h, Vector3(3.0, 5.0, 40.0), Vector3(sx * 9.5, 2.5, 0.0), stone)                                  # side walls
	GroundKit.box(h, Vector3(22.0, 5.0, 3.0), Vector3(0.0, 2.5, 20.0), stone)                                           # head (gate) wall
	_boat(h, Vector3(0.0, 0.4, -2.0), 0.0, true, rng)
	for sz in [-1.0, 1.0]:
		GroundKit.box(h, Vector3(2.0, 1.0, 2.0), Vector3(0.0, 5.4, 20.0 + sz * 1.6), GroundKit.COL_STEEL, Vector3.ZERO, false)


## A canal-side works: a warehouse with a chimney and a small loading wharf.
static func _canal_industry(parent: Node3D, p: Vector3, head: float, rng: RandomNumberGenerator) -> void:
	var brick: Color = GroundKit.COL_BRICK.darkened(0.1)
	var h: Node3D = _holder(parent, p, head)
	_house(h, Vector3(0.0, 0.0, 13.0), 0.0, Vector3(30.0, 8.0, 12.0), brick)
	GroundKit.cyl(h, 1.4, 2.0, 30.0, Vector3(18.0, 15.0, 13.0), brick.lightened(0.06), Vector3.ZERO, 10)
	GroundKit.box(h, Vector3(30.0, 2.0, 5.0), Vector3(0.0, 1.0, 6.0), Color(0.5, 0.48, 0.43))                          # wharf apron
	_boat(h, Vector3(-6.0, 0.0, 0.0), 90.0, true, rng)


## Pick the furniture kind for a canal step: locks on a fixed cadence, aqueducts where the canal crosses a
## river, basins at canal junctions, the rest scattered deterministically.
static func _classify(li: int, j: int, p: Vector2, s: float) -> String:
	if fposmod(s, LOCK_SPAN) < FURN_SPAN * 0.5:
		return "lock"
	if _near_water(p, 45.0):
		return "aqueduct"
	if _near_canal(p, 160.0, li):
		return "basin"
	var rng := RandomNumberGenerator.new()
	rng.seed = li * 7919 + j * 104729 + 17
	var r: float = rng.randf()
	if r < 0.30:
		return "wharf"
	elif r < 0.42:
		return "dry_dock"
	elif r < 0.58:
		return "canal_industry"
	elif r < 0.80:
		return "narrowboats"
	return "barges"


static func _place(container: Node3D, kind: String, p: Vector3, head: float, li: int, j: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = li * 2654435761 + j * 40503 + 3
	match kind:
		"lock":
			_lock(container, p, head, rng)
		"aqueduct":
			_aqueduct(container, p, head)
		"basin":
			_basin(container, p, head, rng)
		"wharf":
			_wharf(container, p, head, rng)
		"dry_dock":
			_dry_dock(container, p, head, rng)
		"canal_industry":
			_canal_industry(container, p, head, rng)
		"narrowboats":
			var rad := deg_to_rad(head)
			var perp := Vector2(cos(rad), sin(rad))
			var along := Vector2(sin(rad), -cos(rad))
			for i in 2 + int(rng.randi() % 3):
				var off: Vector2 = perp * (5.5 if i % 2 == 0 else -5.5) + along * (float(i) * 16.0)
				_boat(container, Vector3(p.x + off.x, GroundKit.ground_y(p.x + off.x, p.z + off.y), p.z + off.y), head, false, rng)
		_:
			var rad2 := deg_to_rad(head)
			var perp2 := Vector2(cos(rad2), sin(rad2))
			var along2 := Vector2(sin(rad2), -cos(rad2))
			for i in 1 + int(rng.randi() % 3):
				var off2: Vector2 = perp2 * (8.0 if i % 2 == 0 else -8.0) + along2 * (float(i) * 24.0)
				_boat(container, Vector3(p.x + off2.x, GroundKit.ground_y(p.x + off2.x, p.z + off2.y), p.z + off2.y), head, true, rng)


## Build one tile of canal furniture, or null if no canal crosses it.
static func build_tile(origin: Vector2, size: float) -> Node3D:
	if canals.is_empty():
		return null
	var container := Node3D.new()
	container.name = "canals"
	var rect := Rect2(origin, Vector2(size, size))
	var ranges: Dictionary = _ranges_for(origin)
	for li in ranges.keys():
		var rg: Vector2i = ranges[li]
		var ln: Dictionary = canals[li]
		var pts: PackedVector2Array = ln["pts"]
		var cum: PackedFloat32Array = ln["cum"]
		var s_lo: float = cum[clampi(rg.x, 0, cum.size() - 1)]
		var s_hi: float = cum[clampi(rg.y + 1, 0, cum.size() - 1)]
		var j: int = int(floorf(s_lo / FURN_SPAN))
		var s: float = float(j) * FURN_SPAN
		while s <= s_hi:
			var p: Vector2 = _sample(pts, cum, s)
			if rect.has_point(p) and GroundKit.raw_y(p.x, p.y) > 0.5 and not RiverMesh._excluded(p):
				var d: Vector2 = _tangent(pts, cum, s)
				var head: float = rad_to_deg(atan2(d.x, d.y))
				var kind: String = _classify(li, j, p, s)
				_place(container, kind, Vector3(p.x, GroundKit.ground_y(p.x, p.y), p.y), head, li, j)
			s += FURN_SPAN
			j += 1
	if container.get_child_count() == 0:
		return null
	return container
