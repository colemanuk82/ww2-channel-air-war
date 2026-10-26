class_name RiverMesh
extends RefCounted
## Real river network (data/osm/rivers.json) drawn as terrain-hugging water ribbons, built per world tile.
## RiverMesh.ensure_loaded() once; RiverMesh.build_tile(origin, size) -> MeshInstance3D (or null if no river crosses).
## Rivers follow the data's own polylines. Widths by class (river wide, canal narrower, stream thin), scaled a
## little by the line's own length so the big rivers read from the air.
## The ribbon drapes on GroundKit.ground_y, so it works whether or not data/heightmap/region_height.png has been
## carved by tools/carve_rivers.py: a carved DEM drops the channel bed and the ribbon sits in it; an un-carved DEM
## leaves it draped on the ground surface. Open sea (raw_y < 0.4) is skipped - the y=0 water plane already covers it.
## ensure_loaded() also sets the `real_rivers` shader global so the painted terrain rivers retire when real data loads.
## near_river(p) / prepare_block(origin,size) / clear_block() mirror RoadMesh and are worker-safe (thread-owned).

const CELL: float = 1800.0           # world-tile index cell, matches WorldPopulator.TILE
const PIECE: float = 30.0            # ribbon subdivision length (metres/units)
const WATER_LIFT: float = 0.1        # metres above the sampled ground (road ribbons use +0.25)
const WIDTHS := {"river": 26.0, "canal": 18.0, "stream": 7.0}
const CLASSES := {"stream": 0.0, "canal": 0.5, "river": 1.0}
## Real widths (metres, bank to bank) of the big named rivers; everything else uses WIDTHS by class.
const NAMED_WIDTHS := {
	"La Seine": 160.0, "La Meuse": 100.0, "Maas": 150.0, "Rhein": 350.0, "Waal": 400.0, "Nederrijn": 180.0,
	"Lek": 200.0, "IJssel": 120.0, "Boven-Rijn": 350.0, "Nieuwe Maas": 450.0, "Oude Maas": 300.0, "Bergsche Maas": 250.0,
	"Escaut": 70.0, "L'Escaut": 70.0, "Schelde": 300.0, "Westerschelde": 2500.0, "Rupel": 150.0, "Durme": 60.0,
	"River Medway": 150.0, "La Somme": 45.0, "L'Oise": 70.0, "La Marne": 75.0, "Mosel": 110.0, "La Moselle": 100.0,
	"River Severn": 120.0, "River Trent": 80.0, "La Lys": 35.0, "Leie": 40.0, "La Sambre": 40.0, "IJzer": 35.0,
	"L'Yser": 35.0, "La Canche": 30.0, "L'Authie": 25.0, "River Great Ouse": 45.0, "Main": 150.0, "Nahe": 60.0,
	"Lahn": 50.0, "Niers": 25.0, "River Stour": 30.0, "River Rother": 25.0, "River Arun": 35.0,
}
## River Thames, bank to bank by longitude: narrow above Reading, ~250 m through London, widening down the tideway.
const THAMES_W := [[-1.6, 40.0], [-0.9, 60.0], [-0.45, 90.0], [-0.3, 180.0], [-0.1, 250.0], [0.08, 330.0],
	[0.2, 500.0], [0.33, 750.0], [0.45, 1200.0], [0.65, 2500.0]]
const SMOOTH_STEP: float = 50.0      # resample spacing (metres) of the smoothed river / canal centre lines

static var loaded: bool = false
static var lines: Array = []        # {"k": String, "pts": PackedVector2Array (x,z), "cum": PackedFloat32Array, "len": float}
static var _cells: Dictionary = {}  # Vector2i -> Array of Vector3i(line index, first segment, last segment)
static var _material: ShaderMaterial
static var _discs: Array = []       # circles: [centre Vector2, radius]


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
	_load_rivers()
	# (the real_rivers shader global is set by WorldPopulator on the main thread once loading is done)


const RIVER_CELL: float = 10.0
static var _blocks: Dictionary = {}              # thread id -> blocked-cell set of the tile that thread is scattering
static var _blocks_mutex := Mutex.new()


## True near a river while a tile is being scattered (see prepare_block): houses, trees, hedges and farms keep off
## the channel. Thread-guarded: returns false unless the calling thread owns the block.
static func near_river(p: Vector2) -> bool:
	_blocks_mutex.lock()
	var blk: Variant = _blocks.get(OS.get_thread_caller_id())
	_blocks_mutex.unlock()
	if blk == null:
		return false
	return (blk as Dictionary).has(Vector2i(floori(p.x / RIVER_CELL), floori(p.y / RIVER_CELL)))


static func clear_block() -> void:
	_blocks_mutex.lock()
	_blocks.erase(OS.get_thread_caller_id())
	_blocks_mutex.unlock()


## Rasterise the rivers crossing this tile (plus a margin) into the blocked-cell set used by near_river().
static func prepare_block(origin: Vector2, size: float) -> void:
	var blk: Dictionary = {}
	var rect := Rect2(origin - Vector2(40, 40), Vector2(size + 80.0, size + 80.0))
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
				if ranges.has(ev.x):
					var r: Vector2i = ranges[ev.x]
					ranges[ev.x] = Vector2i(mini(r.x, ev.y), maxi(r.y, ev.z))
				else:
					ranges[ev.x] = Vector2i(ev.y, ev.z)
	for li in ranges.keys():
		var pts: PackedVector2Array = lines[li]["pts"]
		var rg: Vector2i = ranges[li]
		var rc: int = clampi(int(ceil((float(lines[li].get("hw", 13.0)) + 18.0) / RIVER_CELL)), 3, 140)
		for i in range(maxi(rg.x, 0), mini(rg.y, pts.size() - 2) + 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			if not rect.has_point(a) and not rect.has_point(b) and not rect.has_point((a + b) * 0.5):
				continue
			var steps: int = maxi(int(a.distance_to(b) / (RIVER_CELL * 0.5)), 1)
			for st in steps + 1:
				var q: Vector2 = a.lerp(b, float(st) / float(steps))
				var cx: int = floori(q.x / RIVER_CELL)
				var cz: int = floori(q.y / RIVER_CELL)
				for dz2 in range(-rc, rc + 1):
					for dx2 in range(-rc, rc + 1):
						if rc > 3 and dx2 * dx2 + dz2 * dz2 > rc * rc:
							continue
						blk[Vector2i(cx + dx2, cz + dz2)] = true
	_blocks_mutex.lock()
	_blocks[OS.get_thread_caller_id()] = blk
	_blocks_mutex.unlock()


static func has_rivers() -> bool:
	return not lines.is_empty()


static func line_count() -> int:
	return lines.size()


static func total_km() -> float:
	var km: float = 0.0
	for ln in lines:
		km += float(ln["len"])
	return km / 1000.0


static func _load_rivers() -> void:
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
	var li: int = 0
	for l in (d as Dictionary).get("lines", []):
		var raw: Array = l.get("pts", [])
		li += 1
		if raw.size() < 2:
			continue
		var kind: String = String(l.get("k", "river"))
		var nm: String = String(l.get("n", ""))
		var ctrl := PackedVector2Array()
		for p in raw:
			var w: Vector3 = WorldCoords.latlon_to_world(float(p[0]), float(p[1]))
			var v := Vector2(w.x, w.z)
			if ctrl.is_empty() or ctrl[ctrl.size() - 1].distance_to(v) > 1.0:
				ctrl.append(v)
		if ctrl.size() < 2:
			continue
		# the data's lines are simplified (points ~700 m apart): curve them, and give rivers gentle meanders
		var pts: PackedVector2Array = _smooth(ctrl, kind == "river" and nm != "" or kind == "river", li)
		var cum := PackedFloat32Array()
		cum.resize(pts.size())
		var len_m: float = 0.0
		for i in pts.size():
			if i > 0:
				len_m += pts[i - 1].distance_to(pts[i])
			cum[i] = len_m
		if len_m < 1.0:
			continue
		_register_line(kind, pts, cum, len_m, nm)


## A rounded, meandering version of a simplified polyline. Rivers get an S-bend offset between each pair of data
## points (zero at the points themselves, so junctions and crossings stay put), then everything goes through a
## centripetal Catmull-Rom spline (no overshoot on uneven spacing) resampled every SMOOTH_STEP metres.
static func _smooth(src: PackedVector2Array, meander: bool, seed_i: int) -> PackedVector2Array:
	var ctrl := PackedVector2Array()
	var n: int = src.size()
	for i in n - 1:
		var a: Vector2 = src[i]
		var b: Vector2 = src[i + 1]
		ctrl.append(a)
		var seg: float = a.distance_to(b)
		if meander and seg > 160.0:
			var nrm: Vector2 = (b - a).normalized().orthogonal()
			var h1: float = fposmod(sin(float(seed_i * 131 + i) * 12.9898) * 43758.5453, 1.0)
			var h2: float = fposmod(sin(float(seed_i * 71 + i) * 78.233) * 24634.6345, 1.0)
			var amp: float = minf(seg * 0.075, 80.0)
			var sgn: float = 1.0 if h1 > 0.5 else -1.0
			ctrl.append(a.lerp(b, 0.3 + 0.08 * h2) + nrm * amp * sgn * (0.6 + 0.4 * h2))
			ctrl.append(a.lerp(b, 0.68 + 0.08 * h1) - nrm * amp * sgn * (0.5 + 0.4 * h1))
	ctrl.append(src[n - 1])
	var m: int = ctrl.size()
	if m < 3:
		return ctrl
	var out := PackedVector2Array()
	for i in m - 1:
		var p0: Vector2 = ctrl[maxi(i - 1, 0)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[mini(i + 2, m - 1)]
		if i == 0:
			p0 = p1 + (p1 - p2)
		if i + 2 > m - 1:
			p3 = p2 + (p2 - p1)
		var seg2: float = p1.distance_to(p2)
		var steps: int = clampi(int(ceil(seg2 / SMOOTH_STEP)), 1, 40)
		for k in steps:
			out.append(_cr(p0, p1, p2, p3, float(k) / float(steps)))
	out.append(ctrl[m - 1])
	return out


## Centripetal Catmull-Rom point between p1 and p2 at t (0..1).
static func _cr(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t0: float = 0.0
	var t1: float = t0 + sqrt(maxf(p0.distance_to(p1), 0.01))
	var t2: float = t1 + sqrt(maxf(p1.distance_to(p2), 0.01))
	var t3: float = t2 + sqrt(maxf(p2.distance_to(p3), 0.01))
	var tt: float = lerpf(t1, t2, t)
	var a1: Vector2 = p0 * ((t1 - tt) / (t1 - t0)) + p1 * ((tt - t0) / (t1 - t0))
	var a2: Vector2 = p1 * ((t2 - tt) / (t2 - t1)) + p2 * ((tt - t1) / (t2 - t1))
	var a3: Vector2 = p2 * ((t3 - tt) / (t3 - t2)) + p3 * ((tt - t2) / (t3 - t2))
	var b1: Vector2 = a1 * ((t2 - tt) / (t2 - t0)) + a2 * ((tt - t0) / (t2 - t0))
	var b2: Vector2 = a2 * ((t3 - tt) / (t3 - t1)) + a3 * ((tt - t1) / (t3 - t1))
	return b1 * ((t2 - tt) / (t2 - t1)) + b2 * ((tt - t1) / (t2 - t1))


static func _thames_w(x: float, z: float) -> float:
	var lon: float = WorldCoords.world_to_latlon(Vector3(x, 0.0, z)).y
	if lon <= float(THAMES_W[0][0]):
		return float(THAMES_W[0][1])
	for i in THAMES_W.size() - 1:
		var a: Array = THAMES_W[i]
		var b: Array = THAMES_W[i + 1]
		if lon <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (lon - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(THAMES_W[THAMES_W.size() - 1][1])


static func _register_line(kind: String, pts: PackedVector2Array, cum: PackedFloat32Array, len_m: float, nm: String = "") -> void:
	var idx: int = lines.size()
	var ln: Dictionary = {"k": kind, "pts": pts, "cum": cum, "len": len_m, "n": nm}
	if nm == "River Thames":
		var hw := PackedFloat32Array()
		hw.resize(pts.size())
		for i in pts.size():
			hw[i] = _thames_w(pts[i].x, pts[i].y) * 0.5
		ln["hwv"] = hw
		ln["hw"] = hw[0]
	elif NAMED_WIDTHS.has(nm):
		ln["hw"] = float(NAMED_WIDTHS[nm]) * 0.5
	else:
		ln["hw"] = _half_width(kind, len_m)
	lines.append(ln)
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


static func _mat() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/river.gdshader") as Shader
	return _material


## Half width (metres) of the class, nudged up by the line's own length so the big rivers read wider.
static func _half_width(k: String, len_m: float) -> float:
	var w: float = float(WIDTHS.get(k, 16.0))
	w *= clampf(1.0 + sqrt(maxf(len_m, 0.0)) / 260.0, 1.0, 1.55)
	return w * 0.5


static func build_tile(origin: Vector2, size: float) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var rect := Rect2(origin, Vector2(size, size))
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
				if ranges.has(ev.x):
					var r: Vector2i = ranges[ev.x]
					ranges[ev.x] = Vector2i(mini(r.x, ev.y), maxi(r.y, ev.z))
				else:
					ranges[ev.x] = Vector2i(ev.y, ev.z)
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
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "rivers"
	return mi


static func _add_line(ln: Dictionary, seg0: int, seg1: int, rect: Rect2, verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array) -> void:
	var pts: PackedVector2Array = ln["pts"]
	var cum: PackedFloat32Array = ln["cum"]
	var half: float = float(ln.get("hw", _half_width(String(ln["k"]), float(ln["len"]))))
	var hwv: PackedFloat32Array = ln.get("hwv", PackedFloat32Array())
	var cls: float = float(CLASSES.get(ln["k"], 0.5))
	# per-vertex miter normals of the original polyline (identical to RoadMesh._add_line)
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
		for k in pieces:
			var t0: float = float(k) / float(pieces)
			var t1: float = float(k + 1) / float(pieces)
			var mid: Vector2 = a.lerp(b, (t0 + t1) * 0.5)
			if not rect.has_point(mid) or _excluded(mid):
				continue
			# skip open water (the sea): the flat water plane already covers it
			if GroundKit.raw_y(mid.x, mid.y) < 0.4:
				continue
			# a river runs INTO a lake or pond: no ribbon across the painted water
			if Scatter.lake_noise(mid.x, mid.y) > 0.79 and Scatter.in_lake(mid.x, mid.y):
				continue
			var base: int = verts.size()
			for e in 2:
				var tt: float = t0 if e == 0 else t1
				var p: Vector2 = a.lerp(b, tt)
				var nn: Vector2 = nrm[i].lerp(nrm[i + 1], tt).normalized()
				var yy: float = GroundKit.ground_y(p.x, p.y) + WATER_LIFT
				if not hwv.is_empty():
					half = lerpf(hwv[i], hwv[i + 1], tt)
				var sd: float = s_acc + seg * tt
				verts.append(Vector3(p.x + nn.x * half, yy, p.y + nn.y * half))
				verts.append(Vector3(p.x - nn.x * half, yy, p.y - nn.y * half))
				norms.append(Vector3.UP)
				norms.append(Vector3.UP)
				uvs.append(Vector2(1.0, sd))
				uvs.append(Vector2(-1.0, sd))
				cols.append(Color(cls, 0.0, 0.0, 1.0))
				cols.append(Color(cls, 0.0, 0.0, 1.0))
			# quad: (0 left0, 1 right0, 2 left1, 3 right1)
			idx.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
