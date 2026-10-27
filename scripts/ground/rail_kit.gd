class_name RailKit
extends RefCounted
## P7 railway drama along the real rail lines (data/osm/rails.json) plus a small hand-authored catalogue of
## famous viaducts and tunnels (data/rail_drama_1940.json). rails.json carries NO bridge/tunnel tags, so the
## viaducts and tunnels are DERIVED from the terrain: where a rail line crosses a dip in the height field it is
## carried on a viaduct (deck at the valley shoulders, piers down into the dip), and where it runs through a rise
## the line "disappears below" the ground at a tunnel portal. Junctions, signal boxes, level crossings,
## turntables, water cranes, coaling stages and goods sheds are placed along the real lines by a deterministic
## arc-length cadence. All procedural low-poly toon from GroundKit primitives - no photo textures.
##
##   RailKit.ensure_loaded()                          # once, from WorldPopulator._ready()
##   var n: Node3D = RailKit.build_tile(org, size)    # per world tile (built on the main thread)
##   var c: Node3D = RailKit.build_catalog(rec)       # one curated record -> a site node
##
## Everything is deterministic (seeded from the line index and step) so a freed and re-streamed tile rebuilds
## identically. Local +Z of every piece runs along the track (rotation.y = atan2(tangent.x, tangent.z)).

const CELL: float = 1800.0            # world-tile index cell, matches WorldPopulator.TILE
const STEP: float = 720.0             # furniture spacing along a rail line (metres)
const RAIL_CELL: float = 90.0         # spatial-hash cell used to detect rail-on-rail junctions
const SPAN: float = 90.0              # half-length sampled either side of a point for the terrain derivations
const DIP: float = 7.0                # ground drop over SPAN that reads as a valley a viaduct spans (metres)
const RISE: float = 7.0               # ground rise over SPAN that reads as a hill the line tunnels through

static var loaded: bool = false
static var rails: Array = []          # {"pts": PackedVector2Array (x,z), "cum": PackedFloat32Array, "len": float}
static var _cells: Dictionary = {}    # Vector2i -> Array of Vector3i(line index, first segment, last segment)
static var _rail_pts: Dictionary = {} # Vector2i -> Array of int (line indices with a point in this cell)
static var catalog: Array = []        # records from data/rail_drama_1940.json


static func ensure_loaded() -> void:
	if loaded:
		return
	loaded = true
	_load_rails()
	_load_catalog()


# ------------------------------------------------------------------ data
static func _load_rails() -> void:
	var path: String = "res://data/osm/rails.json"
	if not FileAccess.file_exists(path):
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	# the same joined, rounded lines as TransportNetwork.rails (the trains follow those); prepared once there
	TransportNetwork.ensure_loaded()
	if not TransportNetwork.rail_chains.is_empty():
		for c in TransportNetwork.rail_chains:
			var cp: PackedVector2Array = c
			var cc: PackedFloat32Array = RoutePath.cum_2d(cp)
			if cp.size() >= 2 and cc[cc.size() - 1] >= 200.0:
				_register_rail(cp, cc, cc[cc.size() - 1])
		return
	var kinds := PackedStringArray()
	var segs: Array = []
	for l in (d as Dictionary).get("lines", []):
		var raw: Array = l.get("pts", [])
		if raw.size() < 2:
			continue
		var p2 := PackedVector2Array()
		for p in raw:
			var w: Vector3 = WorldCoords.latlon_to_world(float(p[0]), float(p[1]))
			p2.append(Vector2(w.x, w.z))
		kinds.append("x")
		segs.append(p2)
	for ch in RoutePath.chain_2d(kinds, segs):
		var pts: PackedVector2Array = RoutePath.fillet_2d(ch[1], RoutePath.curve_radius("rail"))
		var cum: PackedFloat32Array = RoutePath.cum_2d(pts)
		if pts.size() < 2 or cum[cum.size() - 1] < 200.0:
			continue
		_register_rail(pts, cum, cum[cum.size() - 1])


static func _load_catalog() -> void:
	var path: String = "res://data/rail_drama_1940.json"
	if not FileAccess.file_exists(path):
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if d is Dictionary:
		catalog = (d as Dictionary).get("sites", [])


static func _register_rail(pts: PackedVector2Array, cum: PackedFloat32Array, len_m: float) -> void:
	var idx: int = rails.size()
	rails.append({"pts": pts, "cum": cum, "len": len_m})
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
	for i in range(0, pts.size(), 3):
		var key2 := Vector2i(floori(pts[i].x / RAIL_CELL), floori(pts[i].y / RAIL_CELL))
		if not _rail_pts.has(key2):
			_rail_pts[key2] = []
		(_rail_pts[key2] as Array).append(idx)


static func rail_count() -> int:
	return rails.size()


static func total_km() -> float:
	var km: float = 0.0
	for ln in rails:
		km += float(ln["len"])
	return km / 1000.0


static func catalog_count() -> int:
	return catalog.size()


# ------------------------------------------------------------------ sampling helpers
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


## True if a DIFFERENT rail line passes within `r` of p (a junction).
static func _near_other_rail(p: Vector2, r: float, exclude_li: int) -> bool:
	var c: int = int(ceil(r / RAIL_CELL))
	var cx: int = floori(p.x / RAIL_CELL)
	var cz: int = floori(p.y / RAIL_CELL)
	for dz in range(-c, c + 1):
		for dx in range(-c, c + 1):
			var key := Vector2i(cx + dx, cz + dz)
			if not _rail_pts.has(key):
				continue
			for li in (_rail_pts[key] as Array):
				if int(li) != exclude_li:
					return true
	return false


static func _near_any_route(routes: Array, p: Vector2, r: float) -> bool:
	var q := Vector3(p.x, 0.0, p.y)
	for w in routes:
		var rp: RoutePath = (w as Dictionary)["route"]
		if rp != null and rp.closest(q).y <= r:
			return true
	return false


static func _tile_roads(origin: Vector2, size: float) -> Array:
	if not RoadMesh.has_roads():
		return []
	return RoadMesh.ways_in_tile(origin, size)


# ------------------------------------------------------------------ terrain derivations
static func _ground(p: Vector2) -> float:
	return GroundKit.raw_y(p.x, p.y)


## Depth of the dip under a rail point (lowest shoulder minus the rail height): > DIP = a valley.
static func _valley(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> float:
	var p: Vector2 = _sample(pts, cum, s)
	var h0: float = _ground(p)
	var a: float = _ground(_sample(pts, cum, s - SPAN))
	var b: float = _ground(_sample(pts, cum, s + SPAN))
	return minf(a, b) - h0


## Height of the rise under a rail point (rail height minus the highest shoulder): > RISE = a hill.
static func _hill(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> float:
	var p: Vector2 = _sample(pts, cum, s)
	var h0: float = _ground(p)
	var a: float = _ground(_sample(pts, cum, s - SPAN))
	var b: float = _ground(_sample(pts, cum, s + SPAN))
	return h0 - maxf(a, b)


# ------------------------------------------------------------------ piece builders
## Holder at p whose local +Z runs along the track (yaw = atan2(tangent.x, tangent.z)).
static func _holder(parent: Node3D, p: Vector3, yaw: float) -> Node3D:
	var h := Node3D.new()
	h.position = p
	h.rotation.y = yaw
	parent.add_child(h)
	return h


static func _rng(seed_v: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	return rng


## A brick railway viaduct: a deck on arched piers spanning a dip, with parapets and a rail deck on top.
## `deck_y` is the deck height in world units (the valley shoulders); the holder sits at y = 0.
static func _viaduct(parent: Node3D, p: Vector3, yaw: float, span: float, deck_y: float, seed_v: int) -> void:
	var stone: Color = Color(0.52, 0.47, 0.4)
	var h: Node3D = _holder(parent, Vector3(p.x, 0.0, p.z), yaw)
	var n: int = 7
	var bay: float = span / float(n)
	var sin_y: float = sin(yaw)
	var cos_y: float = cos(yaw)
	# piers, spandrel panels and shallow arches between them
	for i in n + 1:
		var z: float = -span * 0.5 + float(i) * bay
		var gy: float = GroundKit.ground_y(p.x + z * sin_y, p.z + z * cos_y)
		var ph: float = maxf(deck_y - gy, 1.0)
		if ph > 1.5:
			GroundKit.box(h, Vector3(9.0, ph, 3.4), Vector3(0.0, gy + ph * 0.5, z), stone.darkened(0.08))
			GroundKit.box(h, Vector3(12.0, 1.2, 4.4), Vector3(0.0, gy + ph + 0.6, z), stone)          # pier cap
	for i in n:
		var zc: float = -span * 0.5 + (float(i) + 0.5) * bay
		GroundKit.box(h, Vector3(8.6, 2.2, 3.0), Vector3(0.0, deck_y - 1.1, zc), stone.darkened(0.03))   # spandrel
		GroundKit.box(h, Vector3(6.2, 1.6, 2.2), Vector3(0.0, deck_y - 2.4, zc), Color(0.16, 0.15, 0.14))  # arch shadow
	# deck: two parapet walls, a deck slab and a dark rail bed down the middle
	for sx in [-1.0, 1.0]:
		GroundKit.box(h, Vector3(2.2, 2.2, span), Vector3(sx * 5.4, deck_y + 1.1, 0.0), stone)
	GroundKit.box(h, Vector3(12.4, 0.8, span), Vector3(0.0, deck_y + 2.1, 0.0), stone.darkened(0.06))
	GroundKit.box(h, Vector3(6.0, 0.4, span), Vector3(0.0, deck_y + 2.6, 0.0), Color(0.28, 0.26, 0.24), Vector3.ZERO, false)


## A tunnel portal: a stone face with an arched opening and a dark interior set into a hillside mound.
## Local -Z is the direction the line has come FROM, so the opening faces back down the track.
static func _tunnel_portal(parent: Node3D, p: Vector3, yaw: float, seed_v: int) -> void:
	var stone: Color = Color(0.5, 0.47, 0.42)
	var dark: Color = Color(0.05, 0.05, 0.05)
	var h: Node3D = _holder(parent, p, yaw)
	# hillside the line disappears into
	GroundKit.box(h, Vector3(46.0, 11.0, 34.0), Vector3(0.0, 3.0, 20.0), Color(0.34, 0.32, 0.22))
	GroundKit.box(h, Vector3(30.0, 4.0, 20.0), Vector3(0.0, 8.0, 26.0), Color(0.36, 0.4, 0.24), Vector3.ZERO, false)
	# portal face: two jambs, a lintel and an arch band
	for sx in [-1.0, 1.0]:
		GroundKit.box(h, Vector3(5.0, 9.0, 2.4), Vector3(sx * 4.4, 4.5, 0.0), stone)
	GroundKit.box(h, Vector3(14.0, 3.2, 2.4), Vector3(0.0, 8.0, 0.0), stone.darkened(0.05))
	GroundKit.box(h, Vector3(6.0, 1.3, 2.6), Vector3(0.0, 7.2, 0.0), stone.lightened(0.06))         # string course
	GroundKit.box(h, Vector3(4.6, 5.6, 1.2), Vector3(0.0, 3.2, -0.7), dark, Vector3.ZERO, false)      # opening
	GroundKit.box(h, Vector3(4.0, 1.0, 2.0), Vector3(0.0, 6.0, -0.2), stone.darkened(0.15))           # arch ring
	# wing walls flaring out away from the portal
	for sx2 in [-1.0, 1.0]:
		GroundKit.box(h, Vector3(2.0, 4.4, 9.0), Vector3(sx2 * 8.4, 2.2, -3.6), stone.darkened(0.1), Vector3(0.0, sx2 * 9.0, 0.0))


## A signal box: a two-storey brick cabin with a glazed upper stage and a semaphore signal nearby.
static func _signal_box(parent: Node3D, p: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var brick: Color = GroundKit.COL_BRICK.darkened(0.12)
	var h: Node3D = _holder(parent, p, yaw)
	GroundKit.box(h, Vector3(7.0, 2.4, 5.0), Vector3(8.0, 1.2, 0.0), brick, Vector3.ZERO)              # base
	GroundKit.box(h, Vector3(6.6, 2.0, 4.6), Vector3(8.0, 3.4, 0.0), brick.lightened(0.04), Vector3.ZERO, false)  # cabin (glazed band)
	var roof := MeshInstance3D.new()
	roof.mesh = GroundKit.prism_mesh(5.6, 7.6, 1.8)
	roof.material_override = GroundKit.mat(Color(0.3, 0.3, 0.32), true)
	roof.position = Vector3(8.0, 4.4, 0.0)
	roof.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	h.add_child(roof)
	GroundKit.cyl(h, 0.35, 0.45, 1.8, Vector3(10.4, 5.2, 0.0), brick.darkened(0.2), Vector3.ZERO, 6)     # chimney
	# semaphore signal post on the far side of the line
	GroundKit.cyl(h, 0.18, 0.22, 9.0, Vector3(-6.5, 4.5, 0.0), GroundKit.COL_STEEL, Vector3.ZERO, 6)
	GroundKit.box(h, Vector3(0.3, 1.6, 0.3), Vector3(-6.5, 8.4, 0.0), Color(0.86, 0.16, 0.12))
	GroundKit.box(h, Vector3(0.24, 0.24, 2.6), Vector3(-6.5, 8.9, 1.3), Color(0.86, 0.16, 0.12))


## A level crossing: crossing boards, two lifting barriers, a keeper's hut and a road strip across the line.
## Local X is across the track (the road runs along it).
static func _level_crossing(parent: Node3D, p: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var road: Color = Color(0.34, 0.32, 0.28)
	var white: Color = Color(0.86, 0.84, 0.8)
	var h: Node3D = _holder(parent, p, yaw)
	GroundKit.box(h, Vector3(46.0, 0.22, 6.4), Vector3(0.0, 0.11, 0.0), road, Vector3.ZERO, false)      # road across the track
	GroundKit.box(h, Vector3(9.0, 0.14, 5.2), Vector3(0.0, 0.25, 0.0), Color(0.3, 0.28, 0.25), Vector3.ZERO, false)  # crossing boards
	for sx in [-1.0, 1.0]:
		GroundKit.cyl(h, 0.2, 0.24, 3.4, Vector3(sx * 9.0, 1.7, 4.4), GroundKit.COL_STEEL, Vector3.ZERO, 6)          # barrier posts
		GroundKit.box(h, Vector3(11.0, 0.22, 0.5), Vector3(sx * 14.5, 2.6, 4.4), white)
		GroundKit.box(h, Vector3(3.0, 0.5, 0.5), Vector3(sx * 13.5, 2.6, 4.4), Color(0.86, 0.16, 0.12), Vector3.ZERO, false)
	# keeper's hut
	GroundKit.box(h, Vector3(4.2, 3.0, 3.6), Vector3(11.0, 1.5, -8.0), GroundKit.COL_BRICK)
	GroundKit.box(h, Vector3(4.8, 1.2, 4.2), Vector3(11.0, 3.6, -8.0), Color(0.3, 0.3, 0.32), Vector3.ZERO, false)


## A rail junction: a diverging second track, trailing points and a signal gantry over the tracks.
static func _junction(parent: Node3D, p: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var ballast: Color = Color(0.4, 0.38, 0.34)
	var rail: Color = Color(0.22, 0.2, 0.18)
	var sleepers: Color = Color(0.28, 0.22, 0.15)
	var h: Node3D = _holder(parent, p, yaw)
	# the line itself, a diverging branch fanning off to one side
	GroundKit.box(h, Vector3(6.0, 0.3, 90.0), Vector3(0.0, 0.15, 0.0), ballast, Vector3.ZERO, false)
	var br := Node3D.new()
	br.rotation.y = deg_to_rad(11.0)
	h.add_child(br)
	GroundKit.box(br, Vector3(6.0, 0.3, 80.0), Vector3(0.0, 0.16, 0.0), ballast, Vector3.ZERO, false)
	# the two running rails of the main line
	GroundKit.box(h, Vector3(0.5, 0.4, 90.0), Vector3(-2.0, 0.55, 0.0), rail, Vector3.ZERO, false)
	GroundKit.box(h, Vector3(0.5, 0.4, 90.0), Vector3(2.0, 0.55, 0.0), rail, Vector3.ZERO, false)
	for sz in [-6.0, 0.0, 6.0]:
		GroundKit.box(h, Vector3(4.2, 0.3, 0.7), Vector3(0.0, 0.34, sz), sleepers, Vector3.ZERO, false)
	# signal gantry over the tracks
	for sx in [-1.0, 1.0]:
		GroundKit.cyl(h, 0.24, 0.28, 8.0, Vector3(sx * 8.0, 4.0, -20.0), GroundKit.COL_STEEL, Vector3.ZERO, 6)
	GroundKit.box(h, Vector3(17.0, 0.4, 0.4), Vector3(0.0, 8.0, -20.0), GroundKit.COL_STEEL, Vector3.ZERO, false)
	for sx2 in [-6.0, 0.0, 6.0]:
		GroundKit.box(h, Vector3(1.0, 0.9, 0.7), Vector3(sx2, 7.3, -20.0), Color(0.86, 0.16, 0.12), Vector3.ZERO, false)
	# points lever frame beside the track
	GroundKit.box(h, Vector3(2.6, 1.4, 1.4), Vector3(-7.0, 0.7, 2.0), GroundKit.COL_WOOD)


## An engine turntable: a circular pit with a girder deck on a centre pivot and a short approach spur.
static func _turntable(parent: Node3D, p: Vector3, yaw: float) -> void:
	var steel: Color = Color(0.3, 0.3, 0.32)
	var h: Node3D = _holder(parent, p, yaw)
	GroundKit.cyl(h, 11.5, 11.5, 0.7, Vector3(0.0, 0.1, 0.0), Color(0.28, 0.28, 0.3), Vector3.ZERO, 18, false)   # pit walls
	GroundKit.cyl(h, 10.4, 10.4, 0.3, Vector3(0.0, 0.2, 0.0), Color(0.18, 0.18, 0.2), Vector3.ZERO, 18, false)   # pit floor
	GroundKit.box(h, Vector3(4.2, 0.6, 20.0), Vector3(0.0, 0.5, 0.0), steel)                                      # girder deck
	GroundKit.cyl(h, 0.7, 0.7, 2.2, Vector3(0.0, 1.3, 0.0), GroundKit.COL_STEEL, Vector3.ZERO, 8)                  # centre pivot
	GroundKit.box(h, Vector3(5.0, 0.3, 12.0), Vector3(0.0, 0.4, 22.0), Color(0.4, 0.38, 0.34), Vector3.ZERO, false)  # approach spur


## A water crane: a swan-necked column beside the track with a water tank behind it.
static func _water_crane(parent: Node3D, p: Vector3, yaw: float) -> void:
	var h: Node3D = _holder(parent, p, yaw)
	GroundKit.cyl(h, 0.28, 0.36, 6.0, Vector3(5.0, 3.0, 0.0), GroundKit.COL_STEEL, Vector3.ZERO, 8)               # column
	GroundKit.cyl(h, 0.22, 0.22, 3.2, Vector3(3.0, 6.4, 0.0), GroundKit.COL_STEEL, Vector3(0.0, 0.0, 52.0), 8)     # swan neck over the track
	GroundKit.cyl(h, 0.16, 0.16, 1.6, Vector3(1.6, 5.4, 0.0), Color(0.16, 0.16, 0.18), Vector3.ZERO, 6, false)     # hose
	GroundKit.cyl(h, 3.4, 3.4, 4.0, Vector3(14.0, 4.0, 0.0), GroundKit.COL_BRICK.lightened(0.05), Vector3.ZERO, 12)  # water tank
	GroundKit.cyl(h, 3.6, 3.6, 0.5, Vector3(14.0, 8.1, 0.0), Color(0.3, 0.3, 0.32), Vector3.ZERO, 12, false)


## A coaling stage: an elevated timber staithe deck on legs with coal heaps on top and a ramp.
static func _coaling_stage(parent: Node3D, p: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var wood: Color = GroundKit.COL_WOOD
	var coal: Color = Color(0.1, 0.1, 0.1)
	var h: Node3D = _holder(parent, p, yaw)
	GroundKit.box(h, Vector3(7.5, 1.3, 30.0), Vector3(0.0, 4.2, 0.0), wood.darkened(0.12))                        # deck
	for i in 6:
		var z: float = -12.0 + float(i) * 4.8
		for sx in [-1.0, 1.0]:
			GroundKit.cyl(h, 0.32, 0.36, 4.0, Vector3(sx * 3.2, 2.0, z), wood, Vector3.ZERO, 6, false)
	GroundKit.box(h, Vector3(7.0, 3.4, 14.0), Vector3(0.0, 1.7, 22.0), Color(0.32, 0.3, 0.26), Vector3(-24.0, 0.0, 0.0))  # ramp
	for i in 3:
		GroundKit.sphere(h, 2.1, Vector3((float(i) - 1.0) * 2.0, 5.3, -8.0 + float(i) * 6.0), coal, Vector3(1.0, 0.5, 1.0), false)


## A goods shed: a long brick transit shed with a pitched roof, a loading bank and a couple of wagons.
static func _goods_shed(parent: Node3D, p: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var brick: Color = GroundKit.COL_BRICK.darkened(0.1)
	var stone: Color = Color(0.5, 0.48, 0.43)
	var h: Node3D = _holder(parent, p, yaw)
	GroundKit.box(h, Vector3(15.0, 7.0, 44.0), Vector3(10.0, 3.5, 0.0), brick)
	for i in 3:
		var roof := MeshInstance3D.new()
		roof.mesh = GroundKit.prism_mesh(15.4, 14.8, 3.0)
		roof.material_override = GroundKit.mat(Color(0.3, 0.3, 0.32), true)
		roof.position = Vector3(10.0, 7.0, -14.8 + float(i) * 14.8)
		h.add_child(roof)
	# loading bank and a shallow canopy over the track side
	GroundKit.box(h, Vector3(3.2, 1.6, 44.0), Vector3(-1.0, 0.8, 0.0), stone)
	GroundKit.box(h, Vector3(9.0, 0.4, 44.0), Vector3(2.0, 5.4, 0.0), Color(0.3, 0.3, 0.32), Vector3.ZERO, false)
	# a few open wagons on the siding
	for i in 3:
		var wz: float = -14.0 + float(i) * 14.0
		GroundKit.box(h, Vector3(3.0, 1.5, 8.0), Vector3(-5.0, 1.1, wz), Color(0.3, 0.24, 0.18))
		GroundKit.box(h, Vector3(2.6, 0.5, 7.2), Vector3(-5.0, 1.9, wz), Color(0.14, 0.12, 0.1), Vector3.ZERO, false)


# ------------------------------------------------------------------ dispatch
static func _classify(li: int, j: int, p: Vector2, near_road: bool, near_junction: bool) -> String:
	if near_road:
		return "level_crossing"
	if near_junction:
		return "junction"
	var rng: RandomNumberGenerator = _rng(li * 7919 + j * 104729 + 29)
	var r: float = rng.randf()
	if r < 0.26:
		return "signal_box"
	elif r < 0.40:
		return "water_crane"
	elif r < 0.52:
		return "coaling_stage"
	elif r < 0.70:
		return "goods_shed"
	elif r < 0.80:
		return "turntable"
	return ""


static func _place(container: Node3D, kind: String, p: Vector3, yaw: float, li: int, j: int) -> void:
	var rng: RandomNumberGenerator = _rng(li * 2654435761 + j * 40503 + 7)
	match kind:
		"signal_box":
			_signal_box(container, p, yaw, rng)
		"level_crossing":
			_level_crossing(container, p, yaw, rng)
		"junction":
			_junction(container, p, yaw, rng)
		"turntable":
			_turntable(container, p, yaw)
		"water_crane":
			_water_crane(container, p, yaw)
		"coaling_stage":
			_coaling_stage(container, p, yaw, rng)
		"goods_shed":
			_goods_shed(container, p, yaw, rng)


## Build one furniture piece of a given `kind` at pos/heading (used by --rail-test and the kind test).
static func build_piece(kind: String, pos: Vector3, heading_deg: float, seed_v: int) -> Node3D:
	var container := Node3D.new()
	var yaw: float = deg_to_rad(heading_deg)
	var gy: float = GroundKit.ground_y(pos.x, pos.z)
	var p := Vector3(pos.x, gy, pos.z)
	var rng: RandomNumberGenerator = _rng(seed_v)
	match kind:
		"viaduct":
			_viaduct(container, Vector3(pos.x, 0.0, pos.z), yaw, 240.0, gy + 24.0, seed_v)
		"tunnel":
			_tunnel_portal(container, p, yaw, seed_v)
		"signal_box":
			_signal_box(container, p, yaw, rng)
		"level_crossing":
			_level_crossing(container, p, yaw, rng)
		"junction":
			_junction(container, p, yaw, rng)
		"turntable":
			_turntable(container, p, yaw)
		"water_crane":
			_water_crane(container, p, yaw)
		"coaling_stage":
			_coaling_stage(container, p, yaw, rng)
		"goods_shed":
			_goods_shed(container, p, yaw, rng)
	return container


## The furniture kinds build_piece/build_tile can produce (for tests and the debug report).
static func kinds() -> Array:
	return ["viaduct", "tunnel", "signal_box", "level_crossing", "junction", "turntable", "water_crane", "coaling_stage", "goods_shed"]


## Build one tile of railway furniture: terrain-derived viaducts/tunnels plus the line furniture.
## Where every piece of railway furniture in a tile goes (viaducts, tunnel portals, signals, stations...): pure
## maths on the read-only line data and the terrain, so the tile streamer works it out on a worker thread.
## Each entry: ["viaduct", pos, yaw, top, seed] / ["tunnel", pos, yaw, seed] / ["place", kind, pos, yaw, li, j].
static func tile_plan(origin: Vector2, size: float) -> Array:
	var plan: Array = []
	if rails.is_empty():
		return plan
	var rect := Rect2(origin, Vector2(size, size))
	var ranges: Dictionary = _ranges_for(origin)
	var roads: Array = _tile_roads(origin, size)
	for li in ranges.keys():
		var rg: Vector2i = ranges[li]
		var ln: Dictionary = rails[li]
		var pts: PackedVector2Array = ln["pts"]
		var cum: PackedFloat32Array = ln["cum"]
		var s_lo: float = cum[clampi(rg.x, 0, cum.size() - 1)]
		var s_hi: float = cum[clampi(rg.y + 1, 0, cum.size() - 1)]
		var j: int = int(floorf(s_lo / STEP))
		var s: float = float(j) * STEP
		while s <= s_hi:
			var p: Vector2 = _sample(pts, cum, s)
			if rect.has_point(p) and GroundKit.raw_y(p.x, p.y) > 1.0:
				var d: Vector2 = _tangent(pts, cum, s)
				var yaw: float = atan2(d.x, d.y)
				var g: float = GroundKit.ground_y(p.x, p.y)
				if _valley(pts, cum, s) > DIP:
					var a: float = _ground(_sample(pts, cum, s - SPAN))
					var b: float = _ground(_sample(pts, cum, s + SPAN))
					plan.append(["viaduct", Vector3(p.x, 0.0, p.y), yaw, maxf(a, b), li * 131 + j])
				elif _hill(pts, cum, s) > RISE:
					plan.append(["tunnel", Vector3(p.x, g, p.y), yaw, li * 137 + j])
				else:
					var kind: String = _classify(li, j, p, _near_any_route(roads, p, 26.0), _near_other_rail(p, 95.0, li))
					if kind != "":
						plan.append(["place", kind, Vector3(p.x, g, p.y), yaw, li, j])
			s += STEP
			j += 1
	return plan


## Main thread: the furniture nodes for a tile_plan() (null when there is none).
static func build_from_plan(plan: Array) -> Node3D:
	if plan.is_empty():
		return null
	var container := Node3D.new()
	container.name = "rails"
	for e in plan:
		match String(e[0]):
			"viaduct":
				_viaduct(container, e[1], float(e[2]), 240.0, float(e[3]), int(e[4]))
			"tunnel":
				_tunnel_portal(container, e[1], float(e[2]), int(e[3]))
			_:
				_place(container, String(e[1]), e[2], float(e[3]), int(e[4]), int(e[5]))
	if container.get_child_count() == 0:
		container.free()
		return null
	return container


static func build_tile(origin: Vector2, size: float) -> Node3D:
	return build_from_plan(tile_plan(origin, size))




## Build one curated catalogue record (data/rail_drama_1940.json): a named viaduct or tunnel at its real position.
static func build_catalog(rec: Dictionary) -> Node3D:
	var container := Node3D.new()
	var pos: Vector3 = WorldCoords.latlon_to_world(float(rec.get("lat", 0.0)), float(rec.get("lon", 0.0)))
	var yaw: float = deg_to_rad(float(rec.get("heading_deg", 0.0)))
	var seed_v: int = hash(str(rec.get("id", "")))
	var kind: String = str(rec.get("kind", "viaduct"))
	var gy: float = GroundKit.ground_y(pos.x, pos.z)
	match kind:
		"tunnel":
			_tunnel_portal(container, Vector3(pos.x, gy, pos.z), yaw, seed_v)
		"junction":
			_junction(container, Vector3(pos.x, gy, pos.z), yaw, _rng(seed_v))
		"turntable":
			_turntable(container, Vector3(pos.x, gy, pos.z), yaw)
		"goods_shed":
			_goods_shed(container, Vector3(pos.x, gy, pos.z), yaw, _rng(seed_v))
		"signal_box":
			_signal_box(container, Vector3(pos.x, gy, pos.z), yaw, _rng(seed_v))
		_:
			_viaduct(container, Vector3(pos.x, 0.0, pos.z), yaw, float(rec.get("span_m", 240.0)), gy + float(rec.get("height_m", 24.0)), seed_v)
	return container
