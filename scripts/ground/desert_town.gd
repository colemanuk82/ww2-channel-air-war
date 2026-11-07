class_name DesertTown
extends RefCounted
## Desert-map houses for built-up land cover (class 50 of data/desert/region_landcover.bin): low flat-roofed whitewashed and
## sand-coloured blocks on a loose street grid (a bearing per ~260 m district), rooftop stair-houses and tanks, courtyard
## wall stubs, and a mosque with a dome and a minaret here and there. No pitched roofs, no chimneys.
## Pure data like DesertScatter.tile_data (transform arrays, safe on a worker thread). Nothing here runs on the Channel map.

const STEP: float = 24.0
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


static func _mosque_pos(ci: int, cj: int) -> Vector2:
	var r0: float = DesertScatter._h(ci * 7 + 3, cj * 13 + 5)
	if r0 > 0.38:
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
			if LandCover.class_at(mp.x, mp.y) != 50:
				continue
			mosques.append(mp)
			if mp.x < origin.x or mp.x >= origin.x + cell or mp.y < origin.y or mp.y >= origin.y + cell:
				continue
			if not DesertScatter._okc(mp, exclude, 1.5) or RoadMesh.near_road(mp, 14.0):
				continue
			var yaw_m: float = floorf(DesertScatter._h(ci + 5, cj + 9) * 4.0) * PI * 0.5 + 0.12
			DesertScatter._put(b, "d_mosque", mp, yaw_m, Vector3.ONE, 0.4)
	var n: int = int(ceil(cell / STEP))
	for j in n:
		for i in n:
			var p := Vector2(origin.x + (float(i) + 0.5) * STEP + rng.randf_range(-4.5, 4.5), origin.y + (float(j) + 0.5) * STEP + rng.randf_range(-4.5, 4.5))
			# ragged class edge: wobble the lookup like the shader's noise-warped blend does
			var cls: int = LandCover.class_at(p.x + (DesertScatter._vn(p.x, p.y, 61.0) - 0.5) * 120.0, p.y + (DesertScatter._vn(p.y + 37.0, p.x, 61.0) - 0.5) * 120.0)
			if cls != 50:
				continue
			var frac: float = Scatter._built_frac(p, 34.0)
			if frac < 0.99 and rng.randf() > 0.25 + frac * 0.9:
				continue
			if rng.randf() < 0.12:
				continue                                    # an empty plot, a yard
			# lanes: in each district's own frame every 4th row and every 5th column of plots is left open (streets between blocks)
			var dgx: int = floori(p.x / 260.0)
			var dgz: int = floori(p.y / 260.0)
			var da: float = floorf(DesertScatter._h(dgx + 11, dgz + 29) * 8.0) / 8.0 * PI * 0.5
			var du: float = p.x * cos(da) - p.y * sin(da)
			var dv: float = p.x * sin(da) + p.y * cos(da)
			if posmod(floori(du / STEP), 5) == 0 or posmod(floori(dv / STEP), 4) == 0:
				continue
			var w: float = rng.randf_range(8.0, 13.5)
			var l: float = rng.randf_range(7.5, 12.0)
			var two: bool = rng.randf() < 0.12 + 0.35 * frac * frac
			var h: float = rng.randf_range(6.2, 7.4) if two else rng.randf_range(3.2, 4.0)
			var near_m: bool = false
			for mp2 in mosques:
				if (mp2 as Vector2).distance_squared_to(p) < 22.0 * 22.0:
					near_m = true
					break
			if near_m:
				continue
			var dist_x: float = floorf(p.x / 260.0)
			var dist_z: float = floorf(p.y / 260.0)
			var yaw: float = floorf(DesertScatter._h(int(dist_x) + 11, int(dist_z) + 29) * 8.0) / 8.0 * PI * 0.5 + rng.randf_range(-0.05, 0.05)
			if not DesertScatter._okc(p, exclude, 1.5) or RoadMesh.near_road(p, maxf(w, l) * 0.6):
				continue
			var y0: float = GroundKit.ground_y(p.x, p.y)
			if absf(GroundKit.ground_y(p.x + 7.0, p.y) - y0) > 3.0 or absf(GroundKit.ground_y(p.x, p.y + 7.0) - y0) > 3.0:
				continue                                    # not on a steep bank
			var kind: String = HOUSE_KINDS[mini(int(DesertScatter._vn(p.x, p.y, 90.0) * 2.4 + rng.randf() * 1.6), 3)]
			if not b.has(kind):
				b[kind] = []
			(b[kind] as Array).append(Scatter._xf(Vector3(p.x, y0 + h * 0.5 - 0.4, p.y), yaw, Vector3(w, h, l)))
			# rooftop stair-house or water tank
			if rng.randf() < 0.45:
				var rs: float = rng.randf_range(2.2, 3.4)
				var off := Vector2(rng.randf_range(-0.25, 0.25) * w, rng.randf_range(-0.25, 0.25) * l).rotated(-yaw)
				if not b.has("d_roofbox"):
					b["d_roofbox"] = []
				(b["d_roofbox"] as Array).append(Scatter._xf(Vector3(p.x + off.x, y0 + h - 0.4 + rs * 0.5, p.y + off.y), yaw, Vector3(rs, rs * 0.85, rs)))
			# courtyard wall stub along one side
			if rng.randf() < 0.22:
				var wl: float = w + rng.randf_range(2.0, 6.0)
				var wd := Vector2(0.0, l * 0.5 + 2.2).rotated(-yaw)
				if not b.has("d_wall"):
					b["d_wall"] = []
				(b["d_wall"] as Array).append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(wl, 1.7, 0.55)), Vector3(p.x + wd.x, y0 + 0.45, p.y + wd.y)))
