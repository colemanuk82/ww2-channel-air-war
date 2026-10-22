class_name PylonMesh
extends RefCounted
## 1927-35 National Grid pylons + overhead lines (P5) and telegraph poles along the roads.
## Prefers the real OSM `power` layer (data/osm/power.json, fetched by tools/fetch_osm.py); falls back to the
## curated period-grid file data/pylons_1940.json when the fetch is absent. Only >= 132 kV lines are drawn
## (the period grid voltage); lower-voltage distribution lines are skipped.
##
##   PylonMesh.ensure_loaded()                       # once, from WorldPopulator._ready()
##   var n: Node3D = PylonMesh.build_tile(org, size) # per world tile (built on the main thread)
##
## The overhead line is drawn as a narrow dark ribbon ~26 m above the ground (the RiverMesh drape pattern)
## and a lattice pylon mesh is instanced every ~275 m (the period 132 kV span) at the tower positions.
## Telegraph poles are placed every ~65 m along the real road routes. Everything is deterministic: tower and
## pole positions come from the line's own cumulative arc-length, so an element falls in exactly one tile.

const CELL: float = 1800.0           # world-tile index cell, matches WorldPopulator.TILE
const PIECE: float = 45.0            # ribbon subdivision length (metres)
const SPAN: float = 275.0            # pylon spacing along a line (the ~275 m 132 kV National Grid span)
const POLE_SPAN: float = 65.0        # telegraph-pole spacing along a road
const POLE_OFFSET: float = 4.5       # how far off the carriageway a telegraph pole stands
const LINE_H: float = 26.0           # conductor height above ground (metres)
const LINE_HW: float = 0.8           # conductor-ribbon half width
const MIN_V: float = 132000.0        # period grid voltage; below this a power line is skipped

static var loaded: bool = false
static var lines: Array = []         # {"k": String, "pts": PackedVector2Array (x,z), "cum": PackedFloat32Array, "len": float, "v": int}
static var _cells: Dictionary = {}   # Vector2i -> Array of Vector3i(line index, first segment, last segment)
static var _discs: Array = []        # exclusion circles: [centre Vector2, radius]
static var sourced_osm: bool = false
static var _pylon_mesh_cache: ArrayMesh = null
static var _pole_mesh_cache: ArrayMesh = null


static func add_exclusion_disc(centre: Vector2, radius: float) -> void:
	_discs.append([centre, radius])


static func _excluded(p: Vector2) -> bool:
	for c in _discs:
		if p.distance_squared_to(c[0]) < float(c[1]) * float(c[1]):
			return true
	return false


static func ensure_loaded() -> void:
	if loaded:
		return
	loaded = true
	if _load("res://data/osm/power.json"):
		sourced_osm = true
	else:
		_load("res://data/pylons_1940.json")


## True when there is anything to place: power lines, or roads for the telegraph poles.
static func active() -> bool:
	return not lines.is_empty() or RoadMesh.has_roads()


static func has_pylons() -> bool:
	return not lines.is_empty()


static func line_count() -> int:
	return lines.size()


static func total_km() -> float:
	var km: float = 0.0
	for ln in lines:
		km += float(ln["len"])
	return km / 1000.0


## Approximate number of pylons the network will place (one every SPAN along every line).
static func pylon_total() -> int:
	var n: int = 0
	for ln in lines:
		n += int(floor(float(ln["len"]) / SPAN)) + 1
	return n


static func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return false
	for l in (d as Dictionary).get("lines", []):
		var raw: Array = l.get("pts", [])
		if raw.size() < 2:
			continue
		var v: int = int(l.get("v", 0))
		if v > 0 and v < int(MIN_V):
			continue                                       # skip sub-132 kV distribution lines
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
		if pts.size() < 2 or len_m < 1.0:
			continue
		_register_line(String(l.get("k", "line")), pts, cum, len_m, v)
	return not lines.is_empty()


static func _register_line(kind: String, pts: PackedVector2Array, cum: PackedFloat32Array, len_m: float, v: int) -> void:
	var idx: int = lines.size()
	lines.append({"k": kind, "pts": pts, "cum": cum, "len": len_m, "v": v})
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


## Sample a point (Vector2 x,z) at arc length `s` along a registered line.
static func _sample(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	if s <= 0.0:
		return pts[0]
	if s >= cum[cum.size() - 1]:
		return pts[pts.size() - 1]
	for i in range(cum.size() - 1):
		if s <= cum[i + 1]:
			var seg: float = maxf(cum[i + 1] - cum[i], 0.0001)
			var t: float = (s - cum[i]) / seg
			return pts[i].lerp(pts[i + 1], t)
	return pts[pts.size() - 1]


## Unit tangent (Vector2 x,z) at arc length `s`.
static func _tangent(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	for i in range(cum.size() - 1):
		if s <= cum[i + 1]:
			var d: Vector2 = pts[i + 1] - pts[i]
			return d.normalized() if d.length() > 0.001 else Vector2(0.0, 1.0)
	return (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()


# ------------------------------------------------------------------ geometry
static func _pylon_mesh() -> ArrayMesh:
	if _pylon_mesh_cache != null:
		return _pylon_mesh_cache
	var steel: Color = GroundKit.COL_STEEL
	var parts: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			parts.append(GroundKit.box_part(Vector3(0.55, 22.0, 0.55), Vector3(sx * 1.8, 11.0, sz * 1.8), steel, Vector3(sx * -2.5, 0.0, sz * 2.5)))
			parts.append(GroundKit.box_part(Vector3(0.42, 7.0, 0.42), Vector3(sx * 0.9, 25.0, sz * 0.9), steel))
	for y in [6.0, 12.0, 18.0]:
		parts.append(GroundKit.box_part(Vector3(4.6, 0.28, 0.28), Vector3(0.0, y, 1.6), steel.darkened(0.08)))
		parts.append(GroundKit.box_part(Vector3(4.6, 0.28, 0.28), Vector3(0.0, y, -1.6), steel.darkened(0.08)))
		parts.append(GroundKit.box_part(Vector3(0.28, 0.28, 4.6), Vector3(1.6, y, 0.0), steel.darkened(0.08)))
		parts.append(GroundKit.box_part(Vector3(0.28, 0.28, 4.6), Vector3(-1.6, y, 0.0), steel.darkened(0.08)))
	for i in 3:
		parts.append(GroundKit.box_part(Vector3(11.0 - float(i) * 2.0, 0.45, 0.65), Vector3(0.0, 20.0 + float(i) * 2.6, 0.0), steel))
	parts.append(GroundKit.cyl_part(0.0, 0.5, 3.0, Vector3(0.0, 29.0, 0.0), steel, Vector3.ZERO, 4))
	_pylon_mesh_cache = GroundKit.combine(parts)
	return _pylon_mesh_cache


static func _pole_mesh() -> ArrayMesh:
	if _pole_mesh_cache != null:
		return _pole_mesh_cache
	var wood: Color = GroundKit.COL_WOOD
	var parts: Array = []
	parts.append(GroundKit.cyl_part(0.16, 0.2, 8.0, Vector3(0.0, 4.0, 0.0), wood, Vector3.ZERO, 6))
	parts.append(GroundKit.box_part(Vector3(2.4, 0.16, 0.16), Vector3(0.0, 7.2, 0.0), wood.darkened(0.1)))
	parts.append(GroundKit.box_part(Vector3(1.6, 0.14, 0.14), Vector3(0.0, 6.4, 0.0), wood.darkened(0.1)))
	_pole_mesh_cache = GroundKit.combine(parts)
	return _pole_mesh_cache


## Gather the (line index, first segment, last segment) ranges for the tile's 3x3 CELL neighbourhood.
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


## The overhead-line ribbon for this tile (verts at ground + LINE_H), or null if no line crosses.
static func _line_strips(origin: Vector2, size: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var rect := Rect2(origin, Vector2(size, size))
	var ranges: Dictionary = _ranges_for(origin)
	for li in ranges.keys():
		var rg: Vector2i = ranges[li]
		_add_line(lines[li], rg.x, rg.y, rect, verts, norms, uvs, cols, idx)
	if verts.is_empty():
		return null
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Append one line's ribbon pieces that fall inside `rect` (miter normals, like RoadMesh/RiverMesh).
static func _add_line(ln: Dictionary, seg0: int, seg1: int, rect: Rect2, verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array) -> void:
	var pts: PackedVector2Array = ln["pts"]
	var cum: PackedFloat32Array = ln["cum"]
	var n: int = pts.size()
	var nrm := PackedVector2Array()
	nrm.resize(n)
	var n_lo: int = maxi(seg0 - 1, 0)
	var n_hi: int = mini(seg1 + 2, n - 1)
	for i in range(n_lo, n_hi + 1):
		var d0 := Vector2.ZERO
		var d1 := Vector2.ZERO
		if i > 0:
			d0 = (pts[i] - pts[i - 1]).normalized()
		if i < n - 1:
			d1 = (pts[i + 1] - pts[i]).normalized()
		var dd: Vector2 = d0 + d1
		if dd.length() < 0.05:
			dd = d0 if d0 != Vector2.ZERO else d1
		nrm[i] = Vector2(-dd.y, dd.x).normalized()
	for i in range(maxi(seg0, 0), mini(seg1, n - 2) + 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg: float = a.distance_to(b)
		if seg < 0.5:
			continue
		var pieces: int = maxi(int(ceil(seg / PIECE)), 1)
		for k in pieces:
			var t0: float = float(k) / float(pieces)
			var t1: float = float(k + 1) / float(pieces)
			var mid: Vector2 = a.lerp(b, (t0 + t1) * 0.5)
			if not rect.has_point(mid) or _excluded(mid):
				continue
			var base: int = verts.size()
			for e in 2:
				var tt: float = t0 if e == 0 else t1
				var p: Vector2 = a.lerp(b, tt)
				var nn: Vector2 = nrm[i].lerp(nrm[i + 1], tt).normalized()
				var yy: float = GroundKit.ground_y(p.x, p.y) + LINE_H
				verts.append(Vector3(p.x + nn.x * LINE_HW, yy, p.y + nn.y * LINE_HW))
				verts.append(Vector3(p.x - nn.x * LINE_HW, yy, p.y - nn.y * LINE_HW))
				norms.append(Vector3.UP)
				norms.append(Vector3.UP)
				uvs.append(Vector2(1.0, cum[i] + seg * tt))
				uvs.append(Vector2(-1.0, cum[i] + seg * tt))
				cols.append(Color(0.13, 0.13, 0.15, 1.0))
				cols.append(Color(0.13, 0.13, 0.15, 1.0))
			idx.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))


## Pylon instances for this tile: one every SPAN along each crossing line, in the tile rect.
static func _towers_in(origin: Vector2, size: float) -> Array:
	var out: Array = []
	var rect := Rect2(origin, Vector2(size, size))
	var ranges: Dictionary = _ranges_for(origin)
	for li in ranges.keys():
		var rg: Vector2i = ranges[li]
		var ln: Dictionary = lines[li]
		var pts: PackedVector2Array = ln["pts"]
		var cum: PackedFloat32Array = ln["cum"]
		var s_lo: float = cum[clampi(rg.x, 0, cum.size() - 1)]
		var s_hi: float = cum[clampi(rg.y + 1, 0, cum.size() - 1)]
		var s: float = floorf(s_lo / SPAN) * SPAN
		while s <= s_hi:
			var p: Vector2 = _sample(pts, cum, s)
			if rect.has_point(p):
				var d: Vector2 = _tangent(pts, cum, s)
				var y: float = GroundKit.ground_y(p.x, p.y)
				out.append(Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)), Vector3(p.x, y, p.y)))
			s += SPAN
	return out


## Telegraph poles along the roads crossing this tile: one every POLE_SPAN, offset to one side of the road.
static func _poles_along_roads(origin: Vector2, size: float) -> Array:
	var out: Array = []
	if not RoadMesh.has_roads():
		return out
	var rect := Rect2(origin, Vector2(size, size))
	var centre := Vector3(origin.x + size * 0.5, 0.0, origin.y + size * 0.5)
	for w in RoadMesh.ways_in_tile(origin, size):
		var rp: RoutePath = (w as Dictionary)["route"]
		var s_c: float = rp.closest(centre).x
		var s_lo: float = maxf(s_c - 1600.0, 0.0)
		var s_hi: float = minf(s_c + 1600.0, rp.length)
		var s: float = floorf(s_lo / POLE_SPAN) * POLE_SPAN
		while s <= s_hi:
			var d3: Vector3 = rp.tangent(s)
			var side := Vector2(-d3.z, d3.x).normalized()
			var c3: Vector3 = rp.sample(s)
			var p := Vector2(c3.x, c3.z) + side * POLE_OFFSET
			if rect.has_point(p) and not _excluded(p) and GroundKit.raw_y(p.x, p.y) > 1.0:
				var y: float = GroundKit.ground_y(p.x, p.y)
				out.append(Transform3D(Basis(Vector3.UP, atan2(d3.x, d3.z)), Vector3(p.x, y, p.y)))
			s += POLE_SPAN
	return out


## Build one tile: the overhead-line ribbon, a pylon MultiMesh and telegraph poles along the roads.
static func build_tile(origin: Vector2, size: float) -> Node3D:
	var container := Node3D.new()
	container.name = "pylons"
	if not lines.is_empty():
		var mesh: ArrayMesh = _line_strips(origin, size)
		if mesh != null:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = GroundKit.glow_mat(Color(0.13, 0.13, 0.15), 1.0, false)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.name = "power_lines"
			container.add_child(mi)
		var towers: Array = _towers_in(origin, size)
		if not towers.is_empty():
			var pm: MultiMeshInstance3D = Scatter.multi(_pylon_mesh(), towers, 0.0)
			pm.name = "pylons"
			container.add_child(pm)
	var poles: Array = _poles_along_roads(origin, size)
	if not poles.is_empty():
		var qm: MultiMeshInstance3D = Scatter.multi(_pole_mesh(), poles, 0.0)
		qm.name = "poles"
		container.add_child(qm)
	if container.get_child_count() == 0:
		return null
	return container
