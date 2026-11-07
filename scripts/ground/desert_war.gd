class_name DesertWar
extends RefCounted
## Dated war scenery for the desert map (data/desert/war_scenery.json), modelled on WarDamage / WarGround:
##  * defence lines (Gazala, Alamein, Mareth, Tobruk perimeter, Halfaya, Wadi Akarit) and the fortified boxes: wire
##    fences and minefield markers as short MultiMesh chunks along the line, sangars and gun pits on the boxes;
##  * battle wrecks and pass features: knocked-out tanks, burnt lorries and guns left where they were hit;
##  * harbour wrecks (Tobruk, Malta): hulls snapped to the nearest open water, awash and listing;
##  * airfield damage and bombed towns: terrain zones of kind 4 (rubble, scorch and crater fields, as the Channel
##    bomb damage) with a few burnt-out aircraft on the fields; defence lines and boxes get kind 6 (churned ground).
## Everything is gated on GameState.current_map == "desert" and the EraClock date. Sites are streamed by the
## WorldPopulator (register()), so only the ones near the player exist; each chunk is a handful of MultiMeshes.

const JSON_PATH := "res://data/desert/war_scenery.json"
const CHUNK_M: float = 1500.0          # wire / marker chunk length (one site each)
const VIS_WIRE: float = 2600.0
const VIS_PROP: float = 3600.0

static var _data: Dictionary = {}
static var _loaded: bool = false


static func data() -> Dictionary:
	if GameState.current_map != "desert" or DesertScatter.legacy():
		return {}
	if not _loaded:
		_loaded = true
		var f: FileAccess = FileAccess.open(JSON_PATH, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
	return _data


static func _pos(r: Dictionary) -> Vector3:
	return WorldCoords.latlon_to_world(float(r["lat"]), float(r["lon"]))


static func _live(r: Dictionary) -> bool:
	return EraClock.is_between(str(r.get("from", "")), str(r.get("to", "")))


# ------------------------------------------------------------------ terrain zones
static func zones() -> Array:
	var out: Array = []
	var d: Dictionary = data()
	for r in d.get("airfield_damage", []):
		var rd: Dictionary = r
		if EraClock.current() < str(rd.get("from", "")):
			continue
		var lvl: float = float(rd.get("level", 0.5)) * lerpf(0.45, 1.0, EraClock.ramp(str(rd["from"]), str(rd.get("full", rd["from"]))))
		var rad: float = float(rd.get("radius_m", 1500.0))
		out.append({"pos": _pos(rd), "heading": 0.0, "half": Vector2(rad * 0.62, rad * 0.62), "feather": rad * 0.5, "kind": 4.0 + clampf(lvl, 0.0, 0.99), "from": str(rd["from"])})
	for r in d.get("damage_areas", []):
		var ad: Dictionary = r
		if EraClock.current() < str(ad.get("from", "")):
			continue
		var lv2: float = float(ad.get("level", 0.4)) * lerpf(0.45, 1.0, EraClock.ramp(str(ad["from"]), str(ad.get("full", ad["from"]))))
		var rr: float = float(ad.get("radius_m", 900.0))
		out.append({"pos": _pos(ad), "heading": 0.0, "half": Vector2(rr * 0.62, rr * 0.62), "feather": rr * 0.5, "kind": 4.0 + clampf(lv2, 0.0, 0.99)})
	for r in d.get("battle_wrecks", []):
		var bd: Dictionary = r
		if not _live(bd):
			continue
		var br: float = float(bd.get("radius_m", 3000.0))
		out.append({"pos": _pos(bd), "heading": 0.0, "half": Vector2(br * 0.5, br * 0.5), "feather": br * 0.4, "kind": 4.0 + 0.28})
	for r in d.get("defence_lines", []):
		var ld: Dictionary = r
		if not _live(ld):
			continue
		for ch in _chunks(_line_pts(ld), 2600.0):
			var pts: PackedVector2Array = ch
			var a: Vector2 = pts[0]
			var b: Vector2 = pts[pts.size() - 1]
			var mid: Vector2 = (a + b) * 0.5
			var dirv: Vector2 = (b - a)
			out.append({"pos": Vector3(mid.x, 0.0, mid.y), "heading": WorldCoords.dir_to_heading(Vector3(dirv.x, 0.0, dirv.y)),
				"half": Vector2(maxf(dirv.length() * 0.5, 200.0), 90.0), "feather": 90.0, "kind": 6.0 + 0.55})
	return out


# ------------------------------------------------------------------ registration
static func _line_pts(r: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in r.get("pts", []):
		var w: Vector3 = WorldCoords.latlon_to_world(float(p[0]), float(p[1]))
		pts.append(Vector2(w.x, w.z))
	return pts


## Split a polyline into pieces of about `len_m` (each keeps its end points).
static func _chunks(pts: PackedVector2Array, len_m: float) -> Array:
	var out: Array = []
	if pts.size() < 2:
		return out
	var cur := PackedVector2Array([pts[0]])
	var acc: float = 0.0
	var pos: Vector2 = pts[0]
	var idx: int = 1
	while idx < pts.size():
		var nxt: Vector2 = pts[idx]
		var seg: float = pos.distance_to(nxt)
		if acc + seg < len_m:
			cur.append(nxt)
			acc += seg
			pos = nxt
			idx += 1
		else:
			var cut: Vector2 = pos.lerp(nxt, (len_m - acc) / maxf(seg, 0.001))
			cur.append(cut)
			out.append(cur)
			cur = PackedVector2Array([cut])
			acc = 0.0
			pos = cut
	if cur.size() >= 2 and acc > 1.0:
		out.append(cur)
	return out


static func register(pop: Node) -> void:
	var d: Dictionary = data()
	if d.is_empty():
		return
	for r in d.get("defence_lines", []):
		var ld: Dictionary = r
		var k: int = 0
		for ch in _chunks(_line_pts(ld), CHUNK_M):
			var pts: PackedVector2Array = ch
			var m: Vector2 = pts[pts.size() / 2]
			pop._add_site("dw_%s_%d" % [str(ld["id"]), k], Vector3(m.x, 0.0, m.y), 1900.0, DesertWar._build_wire,
				{"row": ld, "pts": pts, "mode": "line", "from": str(ld.get("from", "")), "to": str(ld.get("to", "")), "id": str(ld["id"]) + str(k)})
			k += 1
	for r in d.get("fortified_boxes", []):
		var bd: Dictionary = r
		var c: Vector3 = _pos(bd)
		var rad: float = float(bd.get("radius_m", 2000.0))
		# the perimeter wire: a ring of chunks
		var ring := PackedVector2Array()
		var steps: int = maxi(int(TAU * rad * 0.85 / 120.0), 12)
		for i in steps + 1:
			var a: float = TAU * float(i) / float(steps)
			ring.append(Vector2(c.x + cos(a) * rad * 0.85, c.z + sin(a) * rad * 0.85))
		var k2: int = 0
		for ch in _chunks(ring, CHUNK_M):
			var cp: PackedVector2Array = ch
			var m2: Vector2 = cp[cp.size() / 2]
			pop._add_site("dw_%s_w%d" % [str(bd["id"]), k2], Vector3(m2.x, 0.0, m2.y), 1900.0, DesertWar._build_wire,
				{"row": bd, "pts": cp, "mode": "box", "from": str(bd.get("from", "")), "to": str(bd.get("to", "")), "id": str(bd["id"]) + str(k2)})
			k2 += 1
		# sangars and gun pits: one small site each, spread over the box
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(bd["id"]))
		var npits: int = clampi(6 + int(rad / 220.0), 8, 24)
		for i in npits:
			var a2: float = rng.randf() * TAU
			var rr: float = rad * (0.25 + 0.65 * sqrt(rng.randf())) if i % 3 != 0 else rad * rng.randf_range(0.78, 0.88)
			var pp := Vector3(c.x + cos(a2) * rr, 0.0, c.z + sin(a2) * rr)
			pop._add_site("dw_%s_p%d" % [str(bd["id"]), i], pp, 1800.0, DesertWar._build_pit,
				{"row": bd, "kind": "gunpit" if i % 3 != 0 else "sangar", "yaw": a2 + PI, "from": str(bd.get("from", "")), "to": str(bd.get("to", "")), "id": str(bd["id"]) + "p" + str(i)})
	for grp in ["battle_wrecks", "pass_features"]:
		for r in d.get(grp, []):
			var wd: Dictionary = r
			var rad2: float = float(wd.get("radius_m", 3000.0))
			pop._add_site("dw_%s" % str(wd["id"]), _pos(wd), 1500.0 + rad2, DesertWar._build_wrecks,
				{"row": wd, "from": str(wd.get("from", "")), "to": str(wd.get("to", "")), "id": str(wd["id"])})
	print("[desert_war] registered: %d sites so far" % pop._sites.size())
	for r in d.get("harbour_wrecks", []):
		var hd: Dictionary = r
		pop._add_site("dw_%s" % str(hd["id"]), _pos(hd), 5200.0, DesertWar._build_hull,
			{"row": hd, "from": str(hd.get("from", "")), "to": str(hd.get("to", "")), "id": str(hd["id"])})
	for r in d.get("airfield_damage", []):
		var ad: Dictionary = r
		pop._add_site("dw_%s" % str(ad["id"]), _pos(ad), 3600.0, DesertWar._build_af_damage,
			{"row": ad, "from": str(ad.get("from", "")), "to": "", "id": str(ad["id"])})


# ------------------------------------------------------------------ builders (main thread, via the site streamer)
static func _gated(s: Dictionary) -> bool:
	return EraClock.is_between(str(s.get("from", "")), str(s.get("to", "")))


static func _ok_pt(x: float, z: float) -> bool:
	return GroundKit.raw_y(x, z) > 1.2 and not Scatter.in_lake(x, z)


## Wire fence + minefield markers along a chunk of a polyline: posts every ~6 m with two wire strands (one unit
## mesh scaled to the bay length), mine-marker plates in rows beside it. Three MultiMeshes per chunk.
static func _build_wire(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	if not _gated(s):
		return root
	var pts: PackedVector2Array = s["pts"]
	var mode: String = str(s["mode"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(s["id"]))
	var posts: Array = []
	var wires: Array = []
	var mines: Array = []
	var bay: float = 6.0
	for si in range(pts.size() - 1):
		var a: Vector2 = pts[si]
		var b: Vector2 = pts[si + 1]
		var seg: float = a.distance_to(b)
		if seg < 1.0:
			continue
		var dv: Vector2 = (b - a) / seg
		var nv := Vector2(-dv.y, dv.x)
		var yaw: float = -atan2(dv.y, dv.x)
		var nb: int = int(seg / bay)
		for i in nb:
			var p: Vector2 = a + dv * (float(i) * bay + 1.0)
			if not _ok_pt(p.x, p.y):
				continue
			var y: float = GroundKit.ground_y(p.x, p.y)
			var gap: bool = rng.randf() < 0.04
			posts.append(Scatter._xf(Vector3(p.x, y + 0.5, p.y), yaw, Vector3.ONE))
			if not gap:
				var mid: Vector2 = p + dv * (bay * 0.5)
				wires.append(Scatter._xf(Vector3(mid.x, y + 0.5, mid.y), yaw, Vector3(bay, 1.0, 1.0)))
			# a second strand 3 m inside (double apron fence), only on lines
			if mode == "line" and i % 2 == 0:
				var p2: Vector2 = p + nv * 3.0
				if _ok_pt(p2.x, p2.y):
					var y2: float = GroundKit.ground_y(p2.x, p2.y)
					wires.append(Scatter._xf(Vector3(p2.x + dv.x * bay * 0.5, y2 + 0.4, p2.y + dv.y * bay * 0.5), yaw, Vector3(bay, 0.8, 1.0)))
			# mine markers: two rows 40 and 90 m behind the wire, and a scatter further out
			if i % 3 == 0:
				for off in [-40.0, 40.0, -90.0 if mode == "line" else 70.0]:
					var q: Vector2 = p + nv * (off + rng.randf_range(-6.0, 6.0))
					if rng.randf() < 0.75 and _ok_pt(q.x, q.y):
						mines.append(Scatter._xf(Vector3(q.x, GroundKit.ground_y(q.x, q.y) + 0.35, q.y), rng.randf() * TAU, Vector3.ONE))
	if not posts.is_empty():
		root.add_child(Scatter.multi(mesh("post"), posts, VIS_WIRE, false))
	if not wires.is_empty():
		root.add_child(Scatter.multi(mesh("wire"), wires, VIS_WIRE, false))
	if not mines.is_empty():
		root.add_child(Scatter.multi(mesh("mine"), mines, VIS_WIRE * 0.8, false))
	return root


static func _build_pit(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	if not _gated(s):
		return root
	var p: Vector3 = s["pos"]
	if not _ok_pt(p.x, p.z):
		return root
	var kind: String = str(s["kind"])
	var yaw: float = float(s["yaw"])
	root.add_child(Scatter.multi(mesh(kind), [Scatter._xf(Vector3(p.x, GroundKit.ground_y(p.x, p.z), p.z), yaw, Vector3.ONE)], VIS_PROP, false))
	if kind == "gunpit":
		# the dug-in crew: a couple of slit trenches and ammunition boxes beside it
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(s["id"]))
		var xs: Array = []
		for i in 3:
			var q := Vector2(p.x + rng.randf_range(-14.0, 14.0), p.z + rng.randf_range(-14.0, 14.0))
			if _ok_pt(q.x, q.y):
				xs.append(Scatter._xf(Vector3(q.x, GroundKit.ground_y(q.x, q.y), q.y), rng.randf() * TAU, Vector3.ONE))
		if not xs.is_empty():
			root.add_child(Scatter.multi(mesh("sangar"), xs, VIS_PROP * 0.8, false))
	return root


static func _build_wrecks(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	if not _gated(s):
		return root
	var r: Dictionary = s["row"]
	var c: Vector3 = _pos(r)
	var rad: float = float(r.get("radius_m", 3000.0))
	var tanks: int = int(r.get("tanks", clampi(int(rad / 380.0), 3, 14)))
	var trucks: int = int(r.get("trucks", clampi(int(rad / 260.0), 4, 24)))
	if r.has("wrecks"):
		tanks = int(r["wrecks"])
		trucks = maxi(tanks / 2, 2)
	tanks = mini(tanks, 40)
	trucks = mini(trucks, 60)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(s["id"]))
	var buckets: Dictionary = {}
	var centre := Vector2(c.x, c.z)
	for spec in [["tank", tanks], ["truck", trucks], ["gun", maxi(tanks / 3, 1)]]:
		for i in int(spec[1]):
			if i % 4 == 0:
				# wrecks lie in clusters (a knocked-out squadron, a strafed convoy), not evenly
				var a: float = rng.randf() * TAU
				var rr: float = rad * 0.75 * pow(rng.randf(), 0.9)
				centre = Vector2(c.x + cos(a) * rr, c.z + sin(a) * rr)
			var p: Vector2 = centre + Vector2(rng.randf_range(-130.0, 130.0), rng.randf_range(-130.0, 130.0))
			if not _ok_pt(p.x, p.y) or RoadMesh.near_rail(p):
				continue
			var burnt: bool = rng.randf() < 0.45
			var key: String = "w_%s%s" % [str(spec[0]), "_b" if burnt else ""]
			var yaw: float = rng.randf() * TAU
			var y: float = GroundKit.ground_y(p.x, p.y)
			var tilt: Basis = Basis(Vector3.RIGHT, rng.randf_range(-0.08, 0.08)) * Basis(Vector3.FORWARD, rng.randf_range(-0.08, 0.08))
			var t := Transform3D(Basis(Vector3.UP, yaw) * tilt * Basis.from_scale(Vector3.ONE * 1.4), Vector3(p.x, y - 0.1, p.y))
			if not buckets.has(key):
				buckets[key] = []
			(buckets[key] as Array).append(t)
	for key2 in buckets.keys():
		root.add_child(Scatter.multi(mesh(str(key2)), buckets[key2], VIS_PROP, false))
	return root


static func _build_af_damage(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	var r: Dictionary = s["row"]
	if EraClock.current() < str(r.get("from", "")):
		return root
	var lvl: float = float(r.get("level", 0.5)) * lerpf(0.45, 1.0, EraClock.ramp(str(r["from"]), str(r.get("full", r["from"]))))
	var c: Vector3 = _pos(r)
	var rad: float = float(r.get("radius_m", 1800.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(s["id"]))
	var n: int = clampi(int(float(r.get("craters", 60)) / 22.0 * lvl) + 1, 1, 9)
	var xs: Array = []
	for i in n:
		var a: float = rng.randf() * TAU
		var rr: float = rad * rng.randf_range(0.12, 0.5)
		var p := Vector2(c.x + cos(a) * rr, c.z + sin(a) * rr)
		if _ok_pt(p.x, p.y) and not RoadMesh.near_road(p, 4.0):
			xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2)), Vector3(p.x, GroundKit.ground_y(p.x, p.y) + 0.1, p.y)))
	if not xs.is_empty():
		root.add_child(Scatter.multi(mesh("w_plane_b"), xs, VIS_PROP, false))
	return root


## A sunk or burnt-out hull in the harbour: moved to the nearest open water (the 10 m coast mask has no harbour
## inlets), awash and listing, with the superstructure standing clear.
static func _build_hull(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	if not _gated(s):
		return root
	var r: Dictionary = s["row"]
	var c: Vector3 = _pos(r)
	var best: Vector2 = Vector2(c.x, c.z)
	var found: bool = GroundKit.raw_y(c.x, c.z) < 0.4
	if not found:
		var bd: float = 1.0e9
		for ring in range(1, 40):
			var rr: float = float(ring) * 90.0
			if rr > bd + 90.0:
				break
			for k in 16:
				var a: float = TAU * float(k) / 16.0
				var q := Vector2(c.x + cos(a) * rr, c.z + sin(a) * rr)
				if GroundKit.raw_y(q.x, q.y) < 0.2 and rr < bd:
					bd = rr
					best = q
					found = true
	if not found:
		return root
	# push a little further out to sea so the keel is in real water: walk away from land along the open-water side
	var hull: String = str(r.get("hull", "cargo"))
	var len_m: float = float(r.get("length_m", {"cruiser": 140.0, "destroyer": 105.0, "gunboat": 55.0, "liner": 150.0, "cargo": 120.0, "tanker": 160.0}.get(hull, 110.0)))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(s["id"]))
	var yaw: float = deg_to_rad(float(r.get("heading", 0.0))) + rng.randf_range(-0.6, 0.6)
	var sc: float = len_m / 100.0
	var tilt: Basis = Basis(Vector3.FORWARD, rng.randf_range(-0.12, 0.12)) * Basis(Vector3.RIGHT, rng.randf_range(-0.03, 0.03))
	var burnt: bool = hull != "tanker" or rng.randf() < 0.5
	var t := Transform3D(Basis(Vector3.UP, yaw) * tilt * Basis.from_scale(Vector3(sc, sc, sc)), Vector3(best.x, -1.0 * sc, best.y))
	print("[desert_war] hull %s at %.0f,%.0f (row %.0f,%.0f, %.0f m snap)" % [str(r["id"]), best.x, best.y, c.x, c.z, Vector2(c.x, c.z).distance_to(best)])
	root.add_child(Scatter.multi(mesh("hull_%s%s" % [hull, "_b" if burnt else ""]), [t], 7000.0, false))
	return root


# ------------------------------------------------------------------ meshes
static func _bx(sx: float, sy: float, sz: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(sx, sy, sz)
	return b


static func _cy(rt: float, rb: float, h: float, seg: int = 6) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _p(m: Mesh, pos: Vector3, col: Color, rot: Basis = Basis.IDENTITY) -> Array:
	return [m, Transform3D(rot, pos), Scatter._dmat(col, 1, 0.0, false)]


const SAND := Color(0.62, 0.54, 0.40)
const KHAKI := Color(0.40, 0.38, 0.28)
const RUST := Color(0.36, 0.22, 0.14)
const CHAR := Color(0.10, 0.09, 0.08)


static func mesh(kind: String) -> ArrayMesh:
	var key: String = "dw_" + kind
	if Scatter._meshes.has(key):
		return Scatter._meshes[key]
	var parts: Array = []
	var burnt: bool = kind.ends_with("_b")
	var base: String = kind.trim_suffix("_b")
	match base:
		"post":
			parts.append(_p(_bx(0.45, 2.6, 0.45), Vector3(0, 0, 0), Color(0.22, 0.17, 0.12)))
			parts.append(_p(_bx(1.9, 1.2, 0.12), Vector3(0, 0.6, 0), Color(0.30, 0.27, 0.23)))
		"wire":
			parts.append(_p(_bx(1.0, 0.2, 0.2), Vector3(0, 0.8, 0), Color(0.14, 0.13, 0.12)))
			parts.append(_p(_bx(1.0, 0.2, 0.2), Vector3(0, 0.1, 0), Color(0.14, 0.13, 0.12)))
			# a coil of concertina through the middle: a dark low tube
			parts.append(_p(_cy(0.7, 0.7, 1.0, 5), Vector3(0, -0.5, 0), Color(0.18, 0.17, 0.15), Basis(Vector3.FORWARD, PI * 0.5)))
		"mine":
			parts.append(_p(_bx(0.2, 1.4, 0.2), Vector3(0, 0, 0), Color(0.30, 0.24, 0.18)))
			parts.append(_p(_bx(1.3, 0.9, 0.08), Vector3(0, 0.6, 0), Color(0.62, 0.12, 0.10)))
		"sangar":
			var wall: Color = Color(0.58, 0.51, 0.39)
			parts.append(_p(_bx(4.8, 1.1, 0.7), Vector3(0, 0.45, 2.1), wall))
			parts.append(_p(_bx(4.8, 1.1, 0.7), Vector3(0, 0.45, -2.1), wall))
			parts.append(_p(_bx(0.7, 1.1, 3.6), Vector3(2.1, 0.45, 0), wall))
			parts.append(_p(_bx(0.7, 1.1, 3.6), Vector3(-2.1, 0.45, 0), wall * 0.95))
		"gunpit":
			var tm := TorusMesh.new()
			tm.inner_radius = 2.6
			tm.outer_radius = 4.4
			tm.rings = 10
			tm.ring_segments = 5
			parts.append([tm, Transform3D(Basis.from_scale(Vector3(1, 0.5, 1)), Vector3(0, 0.3, 0)), Scatter._dmat(Color(0.60, 0.52, 0.38), 1, 0.0, false)])
			parts.append(_p(_bx(0.25, 1.1, 2.2), Vector3(0, 1.0, 1.4), Color(0.30, 0.31, 0.27)))
			parts.append(_p(_cy(0.12, 0.14, 4.6, 5), Vector3(0, 1.3, 3.4), Color(0.24, 0.25, 0.22), Basis(Vector3.RIGHT, PI * 0.5 - 0.22)))
			parts.append(_p(_bx(0.5, 0.5, 1.0), Vector3(1.9, 0.5, -0.6), KHAKI))
		"w_tank":
			var hc: Color = CHAR if burnt else Color(0.52, 0.44, 0.31)
			var tc: Color = CHAR * 1.3 if burnt else Color(0.46, 0.39, 0.28)
			parts.append(_p(_bx(5.9, 1.2, 2.6), Vector3(0, 1.0, 0), hc))
			parts.append(_p(_bx(5.9, 0.7, 0.55), Vector3(0, 0.55, 1.45), CHAR * 1.6))
			parts.append(_p(_bx(5.9, 0.7, 0.55), Vector3(0, 0.55, -1.45), CHAR * 1.6))
			parts.append(_p(_bx(2.6, 0.9, 2.2), Vector3(-0.2, 1.9, 0), tc))
			parts.append(_p(_cy(0.1, 0.12, 3.2, 5), Vector3(2.2, 2.0, 0), CHAR * 1.4, Basis(Vector3.FORWARD, PI * 0.5)))
			if burnt:
				parts.append(_p(_bx(2.0, 0.2, 1.6), Vector3(-0.2, 2.45, 0), RUST * 0.6))
		"w_truck":
			var tcol: Color = CHAR if burnt else Color(0.45, 0.40, 0.29)
			parts.append(_p(_bx(2.0, 1.9, 2.3), Vector3(1.8, 1.4, 0), tcol))
			parts.append(_p(_bx(4.2, 0.4, 2.3), Vector3(-1.1, 0.8, 0), tcol * 0.85))
			if not burnt:
				parts.append(_p(_bx(4.2, 1.5, 2.3), Vector3(-1.1, 1.8, 0), Color(0.55, 0.50, 0.38)))
			for wx in [1.9, -2.2]:
				for wz in [-1.15, 1.15]:
					parts.append(_p(_cy(0.5, 0.5, 0.4, 6), Vector3(wx, 0.5, wz), Color(0.08, 0.08, 0.08), Basis(Vector3.RIGHT, PI * 0.5)))
		"w_gun":
			parts.append(_p(_bx(0.3, 1.2, 1.6), Vector3(0, 0.9, 0), Color(0.25, 0.26, 0.22)))
			parts.append(_p(_cy(0.1, 0.14, 4.8, 5), Vector3(2.0, 1.1, 0), Color(0.22, 0.23, 0.20), Basis(Vector3.FORWARD, PI * 0.5 - 0.15)))
			parts.append(_p(_cy(0.6, 0.6, 0.2, 6), Vector3(0, 0.6, 1.0), Color(0.08, 0.08, 0.08), Basis(Vector3.RIGHT, PI * 0.5)))
			parts.append(_p(_cy(0.6, 0.6, 0.2, 6), Vector3(0, 0.6, -1.0), Color(0.08, 0.08, 0.08), Basis(Vector3.RIGHT, PI * 0.5)))
		"w_plane":
			var pc: Color = CHAR if burnt else Color(0.45, 0.40, 0.30)
			parts.append(_p(_cy(0.7, 0.45, 9.0, 6), Vector3(0, 1.0, 0), pc, Basis(Vector3.FORWARD, PI * 0.5)))
			parts.append(_p(_bx(2.0, 0.22, 12.0), Vector3(0.6, 0.9, 0), pc * 1.1))
			parts.append(_p(_bx(1.2, 1.8, 0.15), Vector3(-4.2, 1.7, 0), pc))
			parts.append(_p(_bx(1.4, 0.15, 3.6), Vector3(-4.0, 1.1, 0), pc))
		_:
			if base.begins_with("hull_"):
				_hull_parts(parts, base.substr(5), burnt)
	var m: ArrayMesh = Scatter._merge(parts)
	Scatter._meshes[key] = m
	return m


## Hull in a 100 m long unit: scale by length/100. Bow at +X.
static func _hull_parts(parts: Array, type: String, burnt: bool) -> void:
	var hc: Color = Color(0.13, 0.12, 0.11) if burnt else Color(0.32, 0.33, 0.33)
	var sc: Color = Color(0.20, 0.19, 0.17) if burnt else Color(0.42, 0.43, 0.43)
	var rustc: Color = RUST
	var beam: float = 12.0
	var depth: float = 7.0
	match type:
		"gunboat":
			beam = 17.0
			depth = 8.0
		"destroyer":
			beam = 10.0
		"liner":
			beam = 15.0
			depth = 10.0
		"tanker":
			beam = 16.0
			depth = 8.0
		"cruiser":
			beam = 14.0
	parts.append(_p(_bx(84.0, depth, beam), Vector3(-7.0, depth * 0.5 - 1.0, 0), hc))
	var bow := PrismMesh.new()
	bow.size = Vector3(16.0, depth, beam)
	bow.left_to_right = 0.0
	parts.append([bow, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(43.0, depth * 0.5 - 1.0, 0)), Scatter._dmat(hc, 1, 0.0, false)])
	parts.append(_p(_bx(40.0, 0.4, beam * 0.9), Vector3(-6.0, depth - 0.8, 0), rustc))
	var sh: float = 9.0 if type != "liner" else 14.0
	parts.append(_p(_bx(24.0 if type != "tanker" else 14.0, sh, beam * 0.6), Vector3(-12.0 if type != "tanker" else -34.0, depth + sh * 0.5 - 1.0, 0), sc))
	parts.append(_p(_cy(2.2, 3.0, 14.0, 6), Vector3(-16.0 if type != "tanker" else -36.0, depth + sh + 5.0, 0), CHAR if burnt else Color(0.30, 0.25, 0.20)))
	parts.append(_p(_cy(0.35, 0.5, 30.0, 4), Vector3(14.0, depth + 14.0, 0), sc * 0.8))
	if type in ["cruiser", "destroyer", "gunboat"]:
		parts.append(_p(_bx(7.0, 3.5, 5.0), Vector3(28.0, depth + 1.2, 0), sc * 0.9))
		parts.append(_p(_cy(0.4, 0.5, 9.0, 5), Vector3(32.0, depth + 2.6, 0), CHAR, Basis(Vector3.FORWARD, PI * 0.5)))
