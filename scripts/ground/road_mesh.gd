class_name RoadMesh
extends RefCounted
## Real road network (data/osm/roads.json) drawn as asphalt ribbons that hug the terrain, built per world tile.
## RoadMesh.ensure_loaded() once; RoadMesh.build_tile(origin, size) -> MeshInstance3D (or null if no road crosses).
## RoadMesh.ways_in_tile(origin, size) -> Array of {"route": RoutePath, "class": String, "len": float}.
## Roads follow the data's own polylines (simplified at ~300 m), with every bend rounded into a curve sized to the
## road class (RoutePath.fillet_2d / curve_radius); the rounded lines are what the user:// cache stores.

const CELL: float = 1800.0
const PIECE: float = 45.0           # ribbon subdivision length (metres/units)
const WIDTHS := {"rail": 10.0, "motorway": 12.0, "trunk": 10.0, "primary": 8.0, "secondary": 6.5, "tertiary": 5.5}

static var loaded: bool = false
static var lines: Array = []        # {"k": String, "pts": PackedVector2Array (x,z), "route": RoutePath (lazy), "len": float}
static var _cells: Dictionary = {}  # Vector2i -> Array of Vector3i(line index, first segment, last segment)
static var _material: ShaderMaterial
static var _boxes: Array = []     # oriented rectangles roads must not cross: [centre Vector2, dir Vector2, half_along, half_across]
static var _discs: Array = []     # circles: [centre Vector2, radius]


## No road ribbons across an airfield (oriented rectangle: dir = runway direction in world XZ).
static func add_exclusion_box(centre: Vector2, dir: Vector2, half_along: float, half_across: float) -> void:
	_boxes.append([centre, dir.normalized(), half_along, half_across])


static func add_exclusion_disc(centre: Vector2, radius: float) -> void:
	_discs.append([centre, radius])


static func _excluded(p: Vector2) -> bool:
	for b in _boxes:
		var d: Vector2 = p - (b[0] as Vector2)
		var dir: Vector2 = b[1]
		if absf(d.dot(dir)) < float(b[2]) and absf(d.dot(Vector2(-dir.y, dir.x))) < float(b[3]):
			return true
	for c in _discs:
		if p.distance_squared_to(c[0]) < float(c[1]) * float(c[1]):
			return true
	return false


static func ensure_loaded() -> void:
	if loaded:
		return
	loaded = true
	GroundKit.lp("    roads: start")
	# The rail keep-out grid is independent of the road data, so it is built on a worker while the roads load.
	var block_task: int = WorkerThreadPool.add_task(_build_rail_block)
	_load_roads()
	GroundKit.lp("    roads: load+register")
	_load_rails()
	WorkerThreadPool.wait_for_task_completion(block_task)
	GroundKit.lp("    roads: rails")


const ROAD_CELL: float = 10.0
static var _blocks: Dictionary = {}              # thread id -> blocked-cell set of the tile that thread is scattering
static var _blocks_mutex := Mutex.new()


## True near a road while a tile is being scattered (see prepare_block): trees, houses and hedges keep off roads.
static func near_road(p: Vector2) -> bool:
	_blocks_mutex.lock()
	var blk: Variant = _blocks.get(OS.get_thread_caller_id())
	_blocks_mutex.unlock()
	if blk == null:
		return false
	return (blk as Dictionary).has(Vector2i(floori(p.x / ROAD_CELL), floori(p.y / ROAD_CELL)))


static func clear_block() -> void:
	_blocks_mutex.lock()
	_blocks.erase(OS.get_thread_caller_id())
	_blocks_mutex.unlock()


## Rasterise the roads crossing this tile (plus a margin) into the blocked-cell set used by near_road().
static func prepare_block(origin: Vector2, size: float) -> void:
	var blk: Dictionary = {}
	var rect := Rect2(origin - Vector2(30, 30), Vector2(size + 60.0, size + 60.0))
	var cx0: int = floori(origin.x / CELL)
	var cz0: int = floori(origin.y / CELL)
	var ranges: Dictionary = {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := Vector2i(cx0 + dx, cz0 + dz)
			if not _cells.has(key):
				continue
			for e in (_cells[key] as Array):
				var ev: Vector3i = e
				if lines[ev.x]["k"] == "rail":
					continue
				if ranges.has(ev.x):
					var r: Vector2i = ranges[ev.x]
					ranges[ev.x] = Vector2i(mini(r.x, ev.y), maxi(r.y, ev.z))
				else:
					ranges[ev.x] = Vector2i(ev.y, ev.z)
	for li in ranges.keys():
		var pts: PackedVector2Array = lines[li]["pts"]
		var rg: Vector2i = ranges[li]
		for i in range(maxi(rg.x, 0), mini(rg.y, pts.size() - 2) + 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			if not rect.has_point(a) and not rect.has_point(b) and not rect.has_point((a + b) * 0.5):
				continue
			var steps: int = maxi(int(a.distance_to(b) / (ROAD_CELL * 0.6)), 1)
			for st in steps + 1:
				var q: Vector2 = a.lerp(b, float(st) / float(steps))
				var cx: int = floori(q.x / ROAD_CELL)
				var cz: int = floori(q.y / ROAD_CELL)
				for dz2 in range(-1, 2):
					for dx2 in range(-1, 2):
						blk[Vector2i(cx + dx2, cz + dz2)] = true
	_blocks_mutex.lock()
	_blocks[OS.get_thread_caller_id()] = blk
	_blocks_mutex.unlock()


const RAIL_CELL: float = 30.0
static var _rail_block: Dictionary = {}   # Vector2i cell -> true: ground within ~45 units of a railway


## True near a railway: trees, houses, farms and hedges keep off the track.
static func near_rail(p: Vector2) -> bool:
	if _rail_block.is_empty():
		return false
	return _rail_block.has(Vector2i(floori(p.x / RAIL_CELL), floori(p.y / RAIL_CELL)))


## Railway lines (the routes trains run on) drawn as ballast bed + sleepers + two steel rails.
static func _load_rails() -> void:
	for rp in TransportNetwork.rails:
		var r: RoutePath = rp
		if r.points.size() < 2:
			continue
		var pts := PackedVector2Array()
		var cum := PackedFloat32Array()
		for i in r.points.size():
			pts.append(Vector2(r.points[i].x, r.points[i].z))
			cum.append(r.cum[i])
		_register_line("rail", pts, cum, r.length)


## Keep-out grid beside the railways (houses, trees and hedges stay off the track): every 10 m cell within one cell
## of a rail centreline.
static func _build_rail_block() -> void:
	var core: Dictionary = {}
	for rp in TransportNetwork.rails:
		var r: RoutePath = rp
		if r.points.size() < 2:
			continue
		for i in range(r.points.size() - 1):
			var a := Vector2(r.points[i].x, r.points[i].z)
			var bb := Vector2(r.points[i + 1].x, r.points[i + 1].z)
			var steps: int = maxi(int(a.distance_to(bb) / RAIL_CELL), 1)
			for st in steps + 1:
				var q: Vector2 = a.lerp(bb, float(st) / float(steps))
				var ck := Vector2i(floori(q.x / RAIL_CELL), floori(q.y / RAIL_CELL))
				if core.has(ck):
					continue
				core[ck] = true
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						_rail_block[Vector2i(ck.x + dx, ck.y + dz)] = true


## The parsed roads (world-space polylines) are cached in user:// as packed arrays, keyed on the source file's size,
## modified time and the world scale: the 20 MB JSON parse + lat/lon projection took ~3 s on every launch.
static func _roads_cache_path(src: String) -> String:
	return "user://roads_world_v3_%d_%d_%d_%d.bin" % [_src_len(src), FileAccess.get_modified_time(src), int(WorldCoords.units_per_deg_lon * 100.0), int(WorldCoords.units_per_deg_lat * 100.0)]


static func _src_len(src: String) -> int:
	var f: FileAccess = FileAccess.open(src, FileAccess.READ)
	return f.get_length() if f != null else 0


static func _load_roads() -> void:
	var path: String = "res://data/osm/roads.json"
	if not FileAccess.file_exists(path):
		return
	var cache: String = _roads_cache_path(path)
	if FileAccess.file_exists(cache):
		var cf: FileAccess = FileAccess.open(cache, FileAccess.READ)
		if cf != null:
			var cd: Variant = cf.get_var()
			cf = null
			if cd is Dictionary and (cd as Dictionary).has("p"):
				var kinds: PackedStringArray = cd["k"]
				var counts: PackedInt32Array = cd["n"]
				var allp: PackedVector2Array = cd["p"]
				var allc: PackedFloat32Array = cd["c"]
				var o: int = 0
				for i in kinds.size():
					var cnt: int = counts[i]
					var pts: PackedVector2Array = allp.slice(o, o + cnt)
					var cum: PackedFloat32Array = allc.slice(o, o + cnt)
					_register_line(kinds[i], pts, cum, cum[cnt - 1])
					o += cnt
				return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var out_k := PackedStringArray()
	var out_n := PackedInt32Array()
	var out_p := PackedVector2Array()
	var out_c := PackedFloat32Array()
	# the export is two-point segments: join them into whole roads first, then round the bends
	var kinds := PackedStringArray()
	var segs: Array = []
	for l in (d as Dictionary).get("lines", []):
		var raw: Array = l.get("pts", [])
		if raw.size() < 2:
			continue
		var pts0 := PackedVector2Array()
		for p in raw:
			var w: Vector3 = WorldCoords.latlon_to_world(float(p[0]), float(p[1]))
			pts0.append(Vector2(w.x, w.z))
		kinds.append(String(l.get("k", "primary")))
		segs.append(pts0)
	for ch in RoutePath.chain_2d(kinds, segs):
		var kind: String = ch[0]
		var pts: PackedVector2Array = RoutePath.fillet_2d(ch[1], RoutePath.curve_radius(kind), 8.0)
		var cum: PackedFloat32Array = RoutePath.cum_2d(pts)
		var len_m: float = cum[cum.size() - 1]
		if len_m < 1.0:
			continue
		_register_line(kind, pts, cum, len_m)
		out_k.append(kind)
		out_n.append(pts.size())
		out_p.append_array(pts)
		out_c.append_array(cum)
	var wf: FileAccess = FileAccess.open(cache, FileAccess.WRITE)
	if wf != null:
		wf.store_var({"k": out_k, "n": out_n, "p": out_p, "c": out_c})


static func _register_line(kind: String, pts: PackedVector2Array, cum: PackedFloat32Array, len_m: float) -> void:
	var idx: int = lines.size()
	lines.append({"k": kind, "pts": pts, "cum": cum, "route": null, "len": len_m})
	# register the line in every grid cell its segments touch, remembering which segments (index range)
	var ranges: Dictionary = {}   # Vector2i -> Vector2i(first, last)
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


static func has_roads() -> bool:
	return not lines.is_empty()


static func _mat() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/road.gdshader") as Shader
	return _material


static func _route(i: int) -> RoutePath:
	var ln: Dictionary = lines[i]
	if ln["route"] == null:
		var pts3 := PackedVector3Array()
		for v in (ln["pts"] as PackedVector2Array):
			pts3.append(Vector3(v.x, 0.0, v.y))
		ln["route"] = RoutePath.from_points(pts3)
	return ln["route"]


## Roads that cross the tile (for traffic).
static func ways_in_tile(origin: Vector2, size: float) -> Array:
	var out: Array = []
	var key := Vector2i(floori((origin.x + size * 0.5) / CELL), floori((origin.y + size * 0.5) / CELL))
	for e in (_cells.get(key, []) as Array):
		var i: int = (e as Vector3i).x
		var ln: Dictionary = lines[i]
		if ln["k"] != "rail" and float(ln["len"]) > 900.0:
			out.append({"route": _route(i), "class": ln["k"], "len": ln["len"]})
	return out


## Read-only: street polylines (kind != "rail") whose course passes within `radius` of `centre`.
## Used by town layout to run terraces along the real streets. Touches only `_cells`/`lines` (immutable after
## ensure_loaded), so it is safe to call on a worker thread as well as the main thread. Returns Array of
## {"idx": int, "k": String, "pts": PackedVector2Array (world x,z), "cum": PackedFloat32Array, "len": float}.
static func routes_in_rect(centre: Vector2, radius: float) -> Array:
	var out: Array = []
	var x0: int = floori((centre.x - radius) / CELL)
	var x1: int = floori((centre.x + radius) / CELL)
	var z0: int = floori((centre.y - radius) / CELL)
	var z1: int = floori((centre.y + radius) / CELL)
	var seen: Dictionary = {}
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			var key := Vector2i(cx, cz)
			if not _cells.has(key):
				continue
			for e in (_cells[key] as Array):
				var i: int = (e as Vector3i).x
				if seen.has(i):
					continue
				seen[i] = true
				var ln: Dictionary = lines[i]
				if ln["k"] == "rail":
					continue
				var pts: PackedVector2Array = ln["pts"]
				if _poly_near(pts, centre, radius):
					out.append({"idx": i, "k": ln["k"], "pts": pts, "cum": ln["cum"], "len": ln["len"]})
	return out


## True if any segment of the polyline passes within `radius` of point c (cheap chord test).
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


static func build_tile(origin: Vector2, size: float) -> MeshInstance3D:
	return node_from_arrays(tile_arrays(origin, size))


## The ribbon geometry for one tile as mesh arrays (empty when there is nothing here). Pure maths on the loaded,
## read-only line data and the terrain heights, so the tile streamer runs it on a worker thread.
static func tile_arrays(origin: Vector2, size: float) -> Array:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var rect := Rect2(origin, Vector2(size, size))
	# a tile spans CELL-aligned grid cells (TILE == CELL here); gather its cell and neighbours for border lines
	var cx0: int = floori(origin.x / CELL)
	var cz0: int = floori(origin.y / CELL)
	var ranges: Dictionary = {}   # line index -> Vector2i(first, last segment) over this tile's neighbourhood
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
	for li in ranges.keys():
		var rg: Vector2i = ranges[li]
		_add_line(lines[li], rg.x, rg.y, rect, verts, norms, uvs, cols, idx)
	if verts.is_empty():
		return []
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## Main thread: the tile's mesh node from tile_arrays() (null when there is nothing).
static func node_from_arrays(arr: Array) -> MeshInstance3D:
	if arr.is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "roads"
	return mi


static func _add_line(ln: Dictionary, seg0: int, seg1: int, rect: Rect2, verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array) -> void:
	var pts: PackedVector2Array = ln["pts"]
	var cum: PackedFloat32Array = ln["cum"]
	var half: float = float(WIDTHS.get(ln["k"], 8.0)) * 0.5
	if ln["k"] != "rail":
		half *= 1.5      # outer third of the ribbon is the grass verge (see road.gdshader)
	var rail: float = 1.0 if ln["k"] == "rail" else 0.0
	var major: float = 1.0 if (ln["k"] == "motorway" or ln["k"] == "trunk" or ln["k"] == "primary") else 0.0
	# per-vertex miter normals of the original polyline
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
		dd = dd.normalized()
		nrm[i] = Vector2(-dd.y, dd.x)
	for i in range(maxi(seg0, 0), mini(seg1, n - 2) + 1):
		var s_acc: float = cum[i]
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg: float = a.distance_to(b)
		if seg < 0.5:
			continue
		var pieces: int = maxi(int(ceil(seg / PIECE)), 1)
		var prev_l: int = -1
		for k in pieces:
			var t0: float = float(k) / float(pieces)
			var t1: float = float(k + 1) / float(pieces)
			var mid: Vector2 = a.lerp(b, (t0 + t1) * 0.5)
			if rect.has_point(mid) and not _excluded(mid):
				# endpoints of this piece
				var ends: Array = [t0, t1]
				var lv: Array = []
				for e in 2:
					var tt: float = ends[e]
					var p: Vector2 = a.lerp(b, tt)
					var nn: Vector2 = nrm[i].lerp(nrm[i + 1], tt).normalized()
					var y: float = GroundKit.ground_y(p.x, p.y)
					lv.append([p, nn, y, s_acc + seg * tt])
				# skip open water (the sea): the ground height is clamped to 0 there
				if GroundKit.raw_y(((lv[0][0] as Vector2).x + (lv[1][0] as Vector2).x) * 0.5, ((lv[0][0] as Vector2).y + (lv[1][0] as Vector2).y) * 0.5) < 0.4:
					continue
				var base: int = verts.size()
				for e in 2:
					var p2: Vector2 = lv[e][0]
					var n2: Vector2 = lv[e][1]
					var yy: float = float(lv[e][2]) + 0.25
					var sd: float = float(lv[e][3])
					verts.append(Vector3(p2.x + n2.x * half, yy, p2.y + n2.y * half))
					verts.append(Vector3(p2.x - n2.x * half, yy, p2.y - n2.y * half))
					norms.append(Vector3.UP)
					norms.append(Vector3.UP)
					uvs.append(Vector2(1.0, sd))
					uvs.append(Vector2(-1.0, sd))
					cols.append(Color(major, rail, 0, 1))
					cols.append(Color(major, rail, 0, 1))
				# quad: (0 left0, 1 right0, 2 left1, 3 right1)
				idx.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
