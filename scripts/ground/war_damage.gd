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
	var nl: Array = []
	for r in _rows:
		var rd: Dictionary = r
		var lvl: float = float(rd.get("level", 0.0)) * level_ramp(str(rd.get("from", "")), str(rd.get("full", "")))
		if lvl <= 0.01:
			continue
		var p: Vector3 = WorldCoords.latlon_to_world(float(rd["lat"]), float(rd["lon"]))
		nl.append([Vector2(p.x, p.z), float(rd.get("radius_m", 800.0)), lvl])
	_base = nl
	_live = nl + _battle


## Session battle scars (BattleDamage): [Vector2 centre, radius, level] rows added to the dated areas. The live list
## is replaced, never edited in place, so tile jobs on worker threads keep reading a consistent array.
static var _base: Array = []
static var _battle: Array = []


static func set_battle(list: Array) -> void:
	_battle = list.duplicate()
	_live = _base + _battle


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


## True when apply_to_houses would gut or clear the house at (x, z) (the same level + hash test): the
## scatter's terrace-row merge and street-tree pass keep such slots out, so a bombed core keeps no intact
## party-wall rows or street trees. Worker-safe (reads the live area list, like the tile jobs do).
static func house_doomed(x: float, z: float) -> bool:
	var lvl: float = level_at(x, z)
	if lvl <= 0.0:
		return false
	return _hash01(x, z) < lvl * 0.86


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
	# (five broken stretches each, a tall remnant and a low one, a different order in each variant)
	var front_h: Array = [1.0, 0.92, 0.66, 0.38, 0.22] if v == 0 else [0.48, 0.84, 1.0, 0.58, 0.30]
	var back_h: Array = [0.30, 0.56, 0.90, 1.0, 0.62] if v == 0 else [0.88, 0.60, 0.26, 0.50, 0.80]
	for sz in [-1.0, 1.0]:
		var hl: Array = front_h if sz < 0.0 else back_h
		for si in 5:
			var hh: float = float(hl[si])
			var xc: float = -0.4 + 0.2 * float(si)
			var y: float = -0.5 + hh * 0.5
			parts.append(GroundKit.box_part(Vector3(0.202, hh, t), Vector3(xc, y, sz * (0.5 - t * 0.5)), brick, Vector3.ZERO, false))
			parts.append(GroundKit.box_part(Vector3(0.206, 0.05, t * 1.1), Vector3(xc, -0.5 + hh - 0.025, sz * (0.5 - t * 0.5)), soot, Vector3.ZERO, false))
			if hh > 0.55:
				parts.append(GroundKit.box_part(Vector3(0.11, 0.17, t * 1.25), Vector3(xc, -0.5 + hh * 0.6, sz * (0.5 - t * 0.5)), hole, Vector3.ZERO, false))
	# side walls: the standing one keeps a jagged gable (stepped slices peaking in the middle, the roof line the
	# rafters left), the other is knocked down in broken steps
	for sx in [-1.0, 1.0]:
		var gable: bool = (sx < 0.0) == (v == 0)
		var heights: Array = [0.36, 0.54, 0.74, 0.92, 1.04, 0.86, 0.64, 0.46, 0.28] if gable else [0.22, 0.46, 0.30, 0.62, 0.40, 0.18]
		var sl: float = (1.0 - t * 2.0) / float(heights.size())
		for si in heights.size():
			var hs: float = float(heights[si])
			var zc: float = -0.5 + t + sl * (float(si) + 0.5)
			var wx: float = sx * (0.5 - t * 0.5)
			parts.append(GroundKit.box_part(Vector3(t, hs, sl * 1.005), Vector3(wx, -0.5 + hs * 0.5, zc), brick, Vector3.ZERO, false))
			parts.append(GroundKit.box_part(Vector3(t * 1.1, 0.05, sl * 1.01), Vector3(wx, -0.5 + hs - 0.025, zc), soot, Vector3.ZERO, false))
			if gable and si in [2, 6]:
				parts.append(GroundKit.box_part(Vector3(t * 1.25, 0.16, sl * 0.5), Vector3(wx, -0.5 + hs * 0.55, zc), hole, Vector3.ZERO, false))   # window hole
		if gable:
			# fireplace and flue running up the gable, black with soot
			parts.append(GroundKit.box_part(Vector3(t * 1.8, 0.62, 0.10), Vector3(sx * (0.5 - t * 0.9), -0.5 + 0.31, 0.12), soot, Vector3.ZERO, false))
	# charred roof timbers hanging from the standing gable into the shell, and one spilled out into the street
	parts.append(GroundKit.box_part(Vector3(0.04, 0.04, 0.55), Vector3(-0.30 if v == 0 else 0.30, -0.18, -0.05), soot, Vector3(0, 0, 0) + Vector3(-28, 0, 0), false))
	parts.append(GroundKit.box_part(Vector3(0.04, 0.04, 0.42), Vector3(-0.18 if v == 0 else 0.18, -0.30, 0.12), soot, Vector3(22, 14, 0), false))
	parts.append(GroundKit.box_part(Vector3(0.36, 0.12, 0.16), Vector3(0.12, -0.44, 0.58), rubble, Vector3(0, 12, 0), false))        # rubble spilling out over the pavement
	parts.append(GroundKit.box_part(Vector3(0.05, 0.05, 0.34), Vector3(-0.15, -0.40, 0.60), soot, Vector3(0, 35, 8), false))
	parts.append(GroundKit.box_part(Vector3(0.84, 0.05, 0.84), Vector3(0.0, -0.47, 0.0), soot, Vector3.ZERO, false))          # burnt floor
	parts.append(GroundKit.box_part(Vector3(0.62, 0.22, 0.55), Vector3(0.08, -0.38, 0.06), rubble, Vector3(0, 18, 8), false))   # rubble heap
	parts.append(GroundKit.box_part(Vector3(0.40, 0.14, 0.38), Vector3(-0.18, -0.40, -0.14), rubble.darkened(0.15), Vector3(0, -25, -6), false))
	parts.append(GroundKit.box_part(Vector3(0.06, 0.55, 0.06), Vector3(-0.30, -0.18, 0.28), soot, Vector3(0, 0, 14), false))   # chimney breast left standing
	var m: ArrayMesh = AirfieldAssets._build(parts)
	Scatter._meshes[key] = m
	return m
