class_name WarDamage
extends RefCounted
## Bomb damage that builds up with the war date (data/war_damage.json): the Blitz on London and the British cities from
## September 1940, Rotterdam in May 1940, the Baedeker raids of 1942, the Ruhr and the Rhineland cities from 1942 to
## 1945, and the Normandy towns in the summer of 1944.
##
## Each area has a centre, a radius, a peak level (the share of the built-up area destroyed or gutted at its centre)
## and a ramp from its first raid to the date the damage was complete. The ramp follows EraClock.
##
## Three cheap layers carry it (no extra draw calls beyond two shared MultiMeshes per tile):
##  * houses: a share of the houses in a damaged area are swapped for a gutted shell (roofless, blackened wall tops,
##    a heap of rubble inside) or left out altogether as a cleared site - same transforms, so the cost is zero;
##  * terrain: a zone of kind 4 per area turns the ground to rubble, scorch and crater fields (terrain shader);
##  * nothing else - no per-house nodes, no particles.
##
## Thread safety: load() and refresh() run on the main thread (populator ready / era change) before any tile job is
## started; tile jobs on the worker threads only read the arrays.

const JSON_PATH := "res://data/war_damage.json"

static var _rows: Array = []        # parsed json rows
static var _live: Array = []        # [Vector2 centre, radius, level now] for areas with damage on the current date
static var _loaded: bool = false


static func load_data() -> void:
	if _loaded:
		return
	_loaded = true
	var f: FileAccess = FileAccess.open(JSON_PATH, FileAccess.READ)
	if f == null:
		push_warning("WarDamage: %s missing" % JSON_PATH)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_rows = (d as Dictionary).get("areas", [])


static func rows() -> Array:
	load_data()
	return _rows


## Recompute the live areas for the current EraClock date. Call on the main thread before tiles are (re)built.
static func refresh() -> void:
	load_data()
	_live.clear()
	for r in _rows:
		var rd: Dictionary = r
		var lvl: float = float(rd.get("level", 0.0)) * level_ramp(str(rd.get("from", "")), str(rd.get("full", "")))
		if lvl <= 0.01:
			continue
		var p: Vector3 = WorldCoords.latlon_to_world(float(rd["lat"]), float(rd["lon"]))
		_live.append([Vector2(p.x, p.z), float(rd.get("radius_m", 800.0)), lvl])


## 0 before the first raid, rising to 1 on the `full` date. A raid on the first day already shows: the first night
## of a blitz did most of the damage, so the ramp starts at 0.45.
static func level_ramp(from: String, full: String) -> float:
	if from == "" or EraClock.current() < from:
		return 0.0
	return lerpf(0.45, 1.0, EraClock.ramp(from, full))


static func live_count() -> int:
	return _live.size()


## The live areas touching a square (tile) [origin, origin + size]: a short list to test each house against.
static func areas_near(origin: Vector2, size: float) -> Array:
	var out: Array = []
	var c: Vector2 = origin + Vector2(size, size) * 0.5
	for a in _live:
		if (a[0] as Vector2).distance_to(c) < float(a[1]) + size * 0.75:
			out.append(a)
	return out


## Damage level 0..1 at a point from a short area list: strongest at the centre, fading to nothing at the radius.
static func level_in(list: Array, x: float, z: float) -> float:
	var best: float = 0.0
	for a in list:
		var d: float = (a[0] as Vector2).distance_to(Vector2(x, z)) / float(a[1])
		if d < 1.0:
			best = maxf(best, float(a[2]) * (1.0 - smoothstep(0.35, 1.0, d)))
	return best


static func level_at(x: float, z: float) -> float:
	return level_in(_live, x, z)


## Swap damaged houses in-place: `lists` is the scatter's per-variant transform lists; gutted shells are appended to
## ruins[0] / ruins[1]; cleared sites are dropped. Deterministic per house position (no rng consumed), so the same
## street is wrecked the same way every time it streams in.
static func apply_to_houses(lists: Array, ruins: Array, areas: Array) -> void:
	if areas.is_empty():
		return
	for li in lists.size():
		var src: Array = lists[li]
		var keep: Array = []
		for t in src:
			var tf: Transform3D = t
			var lvl: float = level_in(areas, tf.origin.x, tf.origin.z)
			if lvl <= 0.0:
				keep.append(tf)
				continue
			var h: float = _hash01(tf.origin.x, tf.origin.z)
			if h < lvl * 0.68:
				var v: int = 0 if _hash01(tf.origin.z, tf.origin.x) < 0.5 else 1
				(ruins[v] as Array).append(_shell_xf(tf, h))
			elif h < lvl * 0.86:
				pass                     # cleared: the rubble has been bulldozed into the next gap
			else:
				keep.append(tf)
		lists[li] = keep


## A gutted shell stands lower than the house it replaces (the roof and the top floor are gone).
static func _shell_xf(tf: Transform3D, h: float) -> Transform3D:
	var sc: Vector3 = tf.basis.get_scale()
	var keep_h: float = lerpf(0.55, 0.85, fposmod(h * 7.31, 1.0))
	var new_h: float = sc.y * keep_h
	var b: Basis = tf.basis.orthonormalized() * Basis.from_scale(Vector3(sc.x, new_h, sc.z))
	var o: Vector3 = tf.origin - Vector3(0.0, (sc.y - new_h) * 0.5, 0.0)
	return Transform3D(b, o)


static func _hash01(x: float, z: float) -> float:
	return fposmod(sin(floorf(x) * 12.9898 + floorf(z) * 78.233) * 43758.5453, 1.0)


## Terrain zones (kind 4: rubble and scorch, strength in the fractional part) for the live areas.
static func zones() -> Array:
	var out: Array = []
	for a in _live:
		var c: Vector2 = a[0]
		var r: float = float(a[1])
		out.append({"pos": Vector3(c.x, 0.0, c.y), "heading": 0.0, "half": Vector2(r * 0.62, r * 0.62), "feather": r * 0.5, "kind": 4.0 + clampf(float(a[2]), 0.0, 0.99)})
	return out


## Gutted house shell in the house meshes' unit-box convention (centred on the origin, 1 x 1 x 1, scaled per
## instance): four walls with broken, blackened tops, empty window holes read as dark bands, no roof, a rubble heap.
static func ruin_mesh(v: int) -> ArrayMesh:
	var key: String = "ruin%d" % v
	if Scatter._meshes.has(key):
		return Scatter._meshes[key]
	var brick: Color = Color(0.34, 0.23, 0.18) if v == 0 else Color(0.36, 0.33, 0.29)
	var soot := Color(0.10, 0.09, 0.08)
	var rubble := Color(0.36, 0.32, 0.27)
	var hole := Color(0.06, 0.06, 0.06)
	var t: float = 0.07
	var parts: Array = []
	# front and back walls in three broken segments each (different heights), side walls in two
	var segs: Array = [[-0.33, 0.34, 1.0, 0.78], [0.0, 0.32, 0.62, 1.0], [0.33, 0.34, 0.86, 0.55]]
	for sz in [-1.0, 1.0]:
		for s in segs:
			var hh: float = float(s[2]) if sz < 0.0 else float(s[3])
			var y: float = -0.5 + hh * 0.5
			parts.append(GroundKit.box_part(Vector3(float(s[1]), hh, t), Vector3(float(s[0]), y, sz * (0.5 - t * 0.5)), brick, Vector3.ZERO, false))
			parts.append(GroundKit.box_part(Vector3(float(s[1]) * 1.01, 0.06, t * 1.1), Vector3(float(s[0]), -0.5 + hh - 0.03, sz * (0.5 - t * 0.5)), soot, Vector3.ZERO, false))
			if hh > 0.6:
				parts.append(GroundKit.box_part(Vector3(float(s[1]) * 0.55, 0.14, t * 1.2), Vector3(float(s[0]), -0.5 + hh * 0.62, sz * (0.5 - t * 0.5)), hole, Vector3.ZERO, false))
	for sx in [-1.0, 1.0]:
		var hs: float = 0.9 if (sx < 0.0) == (v == 0) else 0.6
		parts.append(GroundKit.box_part(Vector3(t, hs, 1.0 - t * 2.0), Vector3(sx * (0.5 - t * 0.5), -0.5 + hs * 0.5, 0.0), brick, Vector3.ZERO, false))
		parts.append(GroundKit.box_part(Vector3(t * 1.1, 0.06, 1.0 - t * 2.0), Vector3(sx * (0.5 - t * 0.5), -0.5 + hs - 0.03, 0.0), soot, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.84, 0.05, 0.84), Vector3(0.0, -0.47, 0.0), soot, Vector3.ZERO, false))          # burnt floor
	parts.append(GroundKit.box_part(Vector3(0.62, 0.22, 0.55), Vector3(0.08, -0.38, 0.06), rubble, Vector3(0, 18, 8), false))   # rubble heap
	parts.append(GroundKit.box_part(Vector3(0.40, 0.14, 0.38), Vector3(-0.18, -0.40, -0.14), rubble.darkened(0.15), Vector3(0, -25, -6), false))
	parts.append(GroundKit.box_part(Vector3(0.06, 0.55, 0.06), Vector3(-0.30, -0.18, 0.28), soot, Vector3(0, 0, 14), false))   # chimney breast left standing
	var m: ArrayMesh = AirfieldAssets._build(parts)
	Scatter._meshes[key] = m
	return m
