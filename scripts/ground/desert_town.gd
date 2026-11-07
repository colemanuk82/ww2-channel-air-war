class_name DesertTown
extends RefCounted
## Desert-map houses for built-up land cover (class 50 of data/desert/region_landcover.bin): low flat-roofed whitewashed and
## sand-coloured blocks on a loose street grid (a bearing per ~260 m district), rooftop stair-houses and tanks, courtyard
## wall stubs, and a mosque with a dome and a minaret here and there. No pitched roofs, no chimneys.
## Pure data like DesertScatter.tile_data (transform arrays, safe on a worker thread). Nothing here runs on the Channel map.

const STEP: float = 16.0
const BLOCK: float = 58.0        # block length (long axis)
const STREET: float = 13.0       # clear street between blocks
const UNIT: float = 10.5         # one attached row-house unit
const MOSQUE_CELL: float = 300.0
const HOUSE_KINDS: Array = ["d_house0", "d_house1", "d_house2", "d_house3"]


static func _h2(x: float, z: float, salt: float) -> float:
	return DesertScatter._h(floori(x * 1.37 + salt * 17.0), floori(z * 1.91 - salt * 5.0))


static func _has_built(origin: Vector2, cell: float) -> bool:
	var n: int = int(ceil((cell + 300.0) / 150.0))
	for j in n:
		for i in n:
			if LandCover.class_at(origin.x - 150.0 + float(i) * 150.0, origin.y - 150.0 + float(j) * 150.0) == 50:
				return true
	return false


## Built-up land within ~r of p. The 300 m class grid is coarse, so a landmark placed on a building
## block often sits on a cell that reads as bare ground: look around before rejecting it.
static func _built_near(p: Vector2, r: float) -> bool:
	for j in 3:
		for i in 3:
			if LandCover.class_at(p.x + (float(i) - 1.0) * r, p.y + (float(j) - 1.0) * r) == 50:
				return true
	return false


static var _places_loaded: bool = false
static var _place_rows: Array = []


## Extra desert places (hamlets and oases) from data/desert/life.json, loaded once.
static func places() -> Array:
	if _places_loaded:
		return _place_rows
	_places_loaded = true
	var f: FileAccess = FileAccess.open("res://data/desert/life.json", FileAccess.READ)
	if f == null:
		return _place_rows
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return _place_rows
	for p in (d as Dictionary).get("settlements", []):
		if not (p is Dictionary):
			continue
		var w: Vector3 = WorldCoords.latlon_to_world(float(p.get("lat", 0.0)), float(p.get("lon", 0.0)))
		_place_rows.append({"pos": Vector2(w.x, w.z), "size": int(p.get("size", 1)),
			"kind": String(p.get("kind", "hamlet")), "id": String(p.get("id", "place")), "name": String(p.get("name", ""))})
	return _place_rows


## Hamlets and oases from data/desert/life.json: a well, a mosque, flat-roofed houses and palms (an oasis
## is mostly palms). Placed independently of the 300 m built-up class, so they exist even in empty desert.
static func add_settlements(b: Dictionary, origin: Vector2, cell: float, seed_v: int, exclude: Array) -> void:
	for p in places():
		var cp: Vector2 = p["pos"]
		if cp.x < origin.x - 900.0 or cp.x > origin.x + cell + 900.0 or cp.y < origin.y - 900.0 or cp.y > origin.y + cell + 900.0:
			continue
		if not DesertScatter._okc(cp, exclude, 2.0) or GroundKit.raw_y(cp.x, cp.y) < 1.0:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(p["id"]))
		var sz: int = int(p["size"])
		var oasis: bool = str(p["kind"]) == "oasis"
		var rad: float = 120.0 + 55.0 * float(sz)
		var inside := func(q: Vector2) -> bool:
			return q.x >= origin.x and q.x < origin.x + cell and q.y >= origin.y and q.y < origin.y + cell
		# the well (and, for a hamlet, a mosque and a market)
		if inside.call(cp):
			DesertScatter._put(b, "d_well", cp, rng.randf() * TAU, Vector3.ONE, 0.1)
		var yaw0: float = rng.randf() * TAU
		if sz >= 2:
			var mq: Vector2 = cp + Vector2(34.0, -26.0).rotated(-yaw0)
			if inside.call(mq) and DesertScatter._okc(mq, exclude, 1.5) and not RoadMesh.near_road(mq, 12.0):
				DesertScatter._put(b, "d_mosque", mq, yaw0, Vector3(0.85, 0.85, 0.85), 0.4)
		if sz >= 3 and not oasis:
			var mk: Vector2 = cp + Vector2(-52.0, 38.0).rotated(-yaw0)
			if inside.call(mk) and DesertScatter._okc(mk, exclude, 1.5) and not RoadMesh.near_road(mk, 10.0):
				DesertScatter._put(b, "d_market", mk, yaw0, Vector3(0.8, 0.8, 0.8), 0.05)
		# houses (an oasis keeps a few, a hamlet a denser cluster)
		var nh: int = (2 + sz * 2) if oasis else (5 + sz * 6)
		for i in nh:
			var a: float = rng.randf() * TAU
			var rr: float = 22.0 + sqrt(rng.randf()) * rad
			var q: Vector2 = cp + Vector2(cos(a), sin(a)) * rr
			if not inside.call(q):
				continue
			if not DesertScatter._okc(q, exclude, 1.5) or RoadMesh.near_road(q, 8.0):
				continue
			var w: float = rng.randf_range(8.0, 13.0)
			var l: float = rng.randf_range(7.5, 11.5)
			var h: float = rng.randf_range(3.2, 4.0) if rng.randf() > 0.15 else rng.randf_range(6.2, 7.2)
			var y0: float = GroundKit.ground_y(q.x, q.y)
			if absf(GroundKit.ground_y(q.x + 7.0, q.y) - y0) > 3.0:
				continue
			var kind: String = HOUSE_KINDS[rng.randi() % HOUSE_KINDS.size()]
			if not b.has(kind):
				b[kind] = []
			(b[kind] as Array).append(Scatter._xf(Vector3(q.x, y0 + h * 0.5 - 0.4, q.y), rng.randf() * TAU, Vector3(w, h, l)))
		# palms (oases are mostly palms)
		var np: int = 5 + sz * 4 + (14 if oasis else 0)
		for i in np:
			var a2: float = rng.randf() * TAU
			var r2: float = 18.0 + sqrt(rng.randf()) * (rad * (1.35 if oasis else 0.9))
			var q2: Vector2 = cp + Vector2(cos(a2), sin(a2)) * r2
			if not inside.call(q2) or not DesertScatter._okc(q2, exclude, 2.0):
				continue
			if GroundKit.raw_y(q2.x, q2.y) < 1.0:
				continue
			var s1: float = rng.randf_range(0.9, 1.3)
			DesertScatter._put(b, "d_palm", q2, rng.randf() * TAU, Vector3(s1, s1 * rng.randf_range(0.9, 1.2), s1))



static var _cities_loaded: bool = false
static var _city_rows: Array = []


## Towns from the map's locations file (world XZ + size), loaded once. Used for the great mosque and
## the market square in each town centre.
static func cities() -> Array:
	if _cities_loaded:
		return _city_rows
	_cities_loaded = true
	var f: FileAccess = FileAccess.open(WorldCoords.locations_path(), FileAccess.READ)
	if f == null:
		return _city_rows
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return _city_rows
	for c in (d as Dictionary).get("cities", []):
		if not (c is Dictionary) or not bool((c as Dictionary).get("in_bounds", true)):
			continue
		var w: Vector3 = WorldCoords.latlon_to_world(float(c.get("lat", 0.0)), float(c.get("lon", 0.0)))
		_city_rows.append({"pos": Vector2(w.x, w.z), "size": int(c.get("size", 1)), "name": String(c.get("name", ""))})
	return _city_rows


static func _mosque_pos(ci: int, cj: int) -> Vector2:
	var r0: float = DesertScatter._h(ci * 7 + 3, cj * 13 + 5)
	# Only a small share of 300 m cells get a neighbourhood mosque; the town-centre great mosque is added
	# separately, so towns no longer bristle with minarets.
	if r0 > 0.08:
		return Vector2(1.0e12, 1.0e12)
	return Vector2((float(ci) + 0.2 + 0.6 * DesertScatter._h(ci + 91, cj + 17)) * MOSQUE_CELL, (float(cj) + 0.2 + 0.6 * DesertScatter._h(ci + 33, cj + 71)) * MOSQUE_CELL)


## Appends house transforms to the tile bucket b (kinds d_house0-3, d_roofbox, d_mosque, d_wall).
static func add_houses(b: Dictionary, origin: Vector2, cell: float, seed_v: int, exclude: Array) -> void:
	if not _has_built(origin, cell):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v ^ 0x51ed
	# mosques first (the houses keep clear of them); neighbours' mosques count too
	var mosques: Array = []
	for cj in range(floori(origin.y / MOSQUE_CELL) - 1, floori((origin.y + cell) / MOSQUE_CELL) + 2):
		for ci in range(floori(origin.x / MOSQUE_CELL) - 1, floori((origin.x + cell) / MOSQUE_CELL) + 2):
			var mp: Vector2 = _mosque_pos(ci, cj)
			if mp.x > 1.0e11:
				continue
			if not _built_near(mp, 220.0):
				continue
			mosques.append(mp)
			if mp.x < origin.x or mp.x >= origin.x + cell or mp.y < origin.y or mp.y >= origin.y + cell:
				continue
			if not DesertScatter._okc(mp, exclude, 1.5) or RoadMesh.near_road(mp, 14.0):
				continue
			var yaw_m: float = floorf(DesertScatter._h(ci + 5, cj + 9) * 4.0) * PI * 0.5 + 0.12
			DesertScatter._put(b, "d_mosque", mp, yaw_m, Vector3.ONE, 0.4)
	# Town-centre landmarks: one great mosque and a market square per town, on the tile that owns
	# the centre. Markets make the towns read as places rather than a scatter of boxes.
	for c in cities():
		var cp: Vector2 = c["pos"]
		if cp.x < origin.x - 400.0 or cp.x > origin.x + cell + 400.0 or cp.y < origin.y - 400.0 or cp.y > origin.y + cell + 400.0:
			continue
		if not DesertScatter._okc(cp, exclude, 4.0):
			continue
		var sz: int = int(c["size"])
		var cd: float = floorf(DesertScatter._h(floori(cp.x / 260.0) + 11, floori(cp.y / 260.0) + 29) * 8.0) / 8.0 * PI * 0.5
		if sz >= 2:
			var mq: Vector2 = cp + Vector2(70.0, -55.0).rotated(-cd)
			if mq.x >= origin.x and mq.x < origin.x + cell and mq.y >= origin.y and mq.y < origin.y + cell \
					and _built_near(mq, 260.0) and DesertScatter._okc(mq, exclude, 2.0) and not RoadMesh.near_road(mq, 16.0):
				DesertScatter._put(b, "d_mosque", mq, cd, Vector3(1.9, 1.55, 1.9), 0.4)
		var mk: Vector2 = cp + Vector2(-95.0, 65.0).rotated(-cd)
		if mk.x >= origin.x and mk.x < origin.x + cell and mk.y >= origin.y and mk.y < origin.y + cell \
				and DesertScatter._okc(mk, exclude, 3.0) and not RoadMesh.near_road(mk, 18.0):
			DesertScatter._put(b, "d_market", mk, cd, Vector3.ONE, 0.05)
	# Dense city blocks: a rectilinear grid (in each district's own orientation) of long rectangular
	# blocks packed with contiguous row houses, with clear streets between them - the look of a real
	# North African city from the air, not scattered plots.
	var pitch: float = BLOCK + STREET
	var nb: int = int(ceil(cell / pitch)) + 2
	for bj in range(-1, nb):
		for bi in range(-1, nb):
			var bc := Vector2(origin.x + (float(bi) + 0.5) * pitch, origin.y + (float(bj) + 0.5) * pitch)
			if bc.x < origin.x - 1.0 or bc.x > origin.x + cell + 1.0 or bc.y < origin.y - 1.0 or bc.y > origin.y + cell + 1.0:
				continue
			# ragged class edge: wobble the lookup like the shader's noise-warped blend does
			var cls: int = LandCover.class_at(bc.x + (DesertScatter._vn(bc.x, bc.y, 61.0) - 0.5) * 100.0, bc.y + (DesertScatter._vn(bc.y + 37.0, bc.x, 61.0) - 0.5) * 100.0)
			if cls != 50:
				continue
			var frac: float = Scatter._built_frac(bc, 46.0)
			var dens: float = DesertScatter._vn(bc.x + 311.0, bc.y + 97.0, 620.0)
			var keep: float = (0.22 + 0.78 * frac) * smoothstep(0.12, 0.48, dens)
			if rng.randf() > keep:
				continue
			if rng.randf() < 0.07:
				continue                                    # square, park, empty lot
			var dgx: int = floori(bc.x / 260.0)
			var dgz: int = floori(bc.y / 260.0)
			var yaw: float = floorf(DesertScatter._h(dgx + 11, dgz + 29) * 8.0) / 8.0 * PI * 0.5
			var bl: float = BLOCK * rng.randf_range(0.78, 1.0)
			var bw: float = BLOCK * rng.randf_range(0.55, 0.85)
			var rows: int = 2 if bw > 28.0 else 1
			var depth: float = bw / float(rows)
			var units: int = maxi(2, int(bl / UNIT))
			var ux: float = bl / float(units)
			var c: float = cos(yaw)
			var s: float = sin(yaw)
			for r in rows:
				for u in units:
					var lx: float = (float(u) + 0.5) * ux - bl * 0.5
					var lz: float = (float(r) + 0.5) * depth - bw * 0.5
					var p := bc + Vector2(lx * c - lz * s, lx * s + lz * c)
					if p.x < origin.x or p.x >= origin.x + cell or p.y < origin.y or p.y >= origin.y + cell:
						continue
					if not DesertScatter._okc(p, exclude, 1.5) or RoadMesh.near_road(p, 4.0):
						continue
					var y0: float = GroundKit.ground_y(p.x, p.y)
					if absf(GroundKit.ground_y(p.x + 6.0, p.y) - y0) > 2.6 or absf(GroundKit.ground_y(p.x, p.y + 6.0) - y0) > 2.6:
						continue
					# contiguous row house: nearly the full slot, so the walls touch
					var w: float = ux * 0.98
					var l: float = depth * 0.94
					var two: bool = rng.randf() < 0.18 + 0.45 * frac
					var h: float = rng.randf_range(6.4, 9.6) if two else rng.randf_range(3.6, 5.2)
					var kind: String = HOUSE_KINDS[rng.randi() % HOUSE_KINDS.size()]
					if not b.has(kind):
						b[kind] = []
					(b[kind] as Array).append(Scatter._xf(Vector3(p.x, y0 + h * 0.5 - 0.4, p.y), yaw, Vector3(w, h, l)))
					if rng.randf() < 0.5:
						var rs: float = rng.randf_range(2.0, 3.2)
						var off := Vector2(rng.randf_range(-0.3, 0.3) * w, rng.randf_range(-0.3, 0.3) * l).rotated(-yaw)
						if not b.has("d_roofbox"):
							b["d_roofbox"] = []
						(b["d_roofbox"] as Array).append(Scatter._xf(Vector3(p.x + off.x, y0 + h - 0.4 + rs * 0.5, p.y + off.y), yaw, Vector3(rs, rs * 0.85, rs)))
					if r < rows - 1 and rng.randf() < 0.18:
						var wl: float = ux * 0.9
						var wd := Vector2(0.0, depth * 0.5 + 1.4).rotated(-yaw)
						if not b.has("d_wall"):
							b["d_wall"] = []
						(b["d_wall"] as Array).append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(wl, 1.7, 0.55)), Vector3(p.x + wd.x, y0 + 0.45, p.y + wd.y)))
