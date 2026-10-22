class_name CliffSkirt
extends RefCounted
## Explicit near-vertical chalk-cliff faces along the OSM coastline.
##
## The DEM is ~300 m/px and the anti-aliased coast mask ~126 m/px, so the terrain mesh (>=31 m
## steps, coarser with distance) can only ramp a 100 m cliff over ~100 m of ground — from the sea it
## reads as a soft slope, never a face, and the shader's slope test never paints chalk on it. This
## script builds the missing vertical geometry: for every land/sea contour cell inside a chalk cliff
## zone whose inland land is already high, a ribbon quad runs from a little below sea level (its
## foot, offset slightly seaward) up to the local cliff-top height. The quads are appended to the
## terrain tile's arrays, so the terrain material (and its chalk zones) paints them pale.
##
## A static build is enough: the five cliff zones are small and the ribbon is cheap.

const RES := 25.0           # world metres between contour samples (must divide the chunk size)
const FOOT_Y := -6.0        # world Y at the foot (3 m below sea level)
const BATTER_M := 20.0      # the foot leads the crest this far seaward -> a face leaning inland
const MIN_TOP_M := 20.0     # no face where the inland land is lower than this (beaches, harbours)
const RIM_M := 260.0        # extra margin around a cliff zone whose tiles still need the ribbon


## Builds the cliff-face geometry for the chunk [ox,oz .. ox+size,oz+size].
## Returns {"verts": PackedVector3Array, "norms": PackedVector3Array, "indices": PackedInt32Array};
## all three empty when the chunk has no cliff. Reads `field` only, so it is worker-thread safe.
static func build_chunk(field: HeightField, ox: float, oz: float, size: float) -> Dictionary:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var indices := PackedInt32Array()
	if field == null or not field.use_coast_mask:
		return {"verts": verts, "norms": norms, "indices": indices}
	if not _near_zone(field, ox + size * 0.5, oz + size * 0.5, size):
		return {"verts": verts, "norms": norms, "indices": indices}
	# cheap rejection: only chunks that actually straddle the coast need the full grid
	var land_n: int = 0
	for cj in 5:
		for ci in 5:
			if field.coast_land_w(ox + size * float(ci) * 0.25, oz + size * float(cj) * 0.25) >= 0.5:
				land_n += 1
	if land_n == 0 or land_n == 25:
		return {"verts": verts, "norms": norms, "indices": indices}
	var n: int = maxi(2, int(round(size / RES)))
	var step: float = size / float(n)
	var land := PackedFloat32Array()
	land.resize(n * n)
	for j in n:
		var wz: float = oz + float(j) * step
		for i in n:
			land[j * n + i] = field.coast_land_w(ox + float(i) * step, wz) - 0.5
	for j in n - 1:
		for i in n - 1:
			var a: float = land[j * n + i]
			var b: float = land[j * n + i + 1]
			var c: float = land[(j + 1) * n + i + 1]
			var d: float = land[(j + 1) * n + i]
			var lc: int = int(a > 0.0) + int(b > 0.0) + int(c > 0.0) + int(d > 0.0)
			if lc == 0 or lc == 4:
				continue
			var x0: float = ox + float(i) * step
			var z0: float = oz + float(j) * step
			var x1: float = x0 + step
			var z1: float = z0 + step
			var pts: Array[Vector2] = []
			if (a > 0.0) != (b > 0.0):
				pts.append(_cross(Vector2(x0, z0), a, Vector2(x1, z0), b))
			if (b > 0.0) != (c > 0.0):
				pts.append(_cross(Vector2(x1, z0), b, Vector2(x1, z1), c))
			if (c > 0.0) != (d > 0.0):
				pts.append(_cross(Vector2(x1, z1), c, Vector2(x0, z1), d))
			if (d > 0.0) != (a > 0.0):
				pts.append(_cross(Vector2(x0, z1), d, Vector2(x0, z0), a))
			if pts.size() >= 2:
				_segment(field, verts, norms, indices, pts[0], pts[1])
			if pts.size() >= 4:   # saddle cell: two crossings, two short quads
				_segment(field, verts, norms, indices, pts[2], pts[3])
	return {"verts": verts, "norms": norms, "indices": indices}


## True when the chunk is close enough to a cliff zone to be worth examining.
static func _near_zone(field: HeightField, cx: float, cz: float, size: float) -> bool:
	var reach: float = size * 0.708 + RIM_M
	for z in field.get_cliff_world_zones():
		if Vector2(cx - z.x, cz - z.y).length() <= z.z + reach:
			return true
	return false


## Coast point on the segment p0->p1 where the land value (relative to 0.5) crosses 0.
static func _cross(p0: Vector2, v0: float, p1: Vector2, v1: float) -> Vector2:
	var denom: float = v0 - v1
	if absf(denom) < 1e-6:
		return p0.lerp(p1, 0.5)
	return p0.lerp(p1, clampf(v0 / denom, 0.0, 1.0))


## Appends one cliff quad (foot -> crest) for a coast segment, if it is a real cliff.
static func _segment(field: HeightField, verts: PackedVector3Array, norms: PackedVector3Array, indices: PackedInt32Array, p0: Vector2, p1: Vector2) -> void:
	var t: Vector2 = p1 - p0
	if t.length() < 0.01:
		return
	t = t.normalized()
	var seaward := Vector2(t.y, -t.x)
	var mid: Vector2 = (p0 + p1) * 0.5
	var land_mid: float = field.coast_land_w(mid.x, mid.y)
	if field.coast_land_w(mid.x + seaward.x * RES, mid.y + seaward.y * RES) > land_mid:
		seaward = -seaward
	if field.cliff_zone_weight_w(mid.x, mid.y) <= 0.0:
		return
	var top0: float = field.cliff_top_m_w(p0.x, p0.y)
	var top1: float = field.cliff_top_m_w(p1.x, p1.y)
	if maxf(top0, top1) < MIN_TOP_M:
		return
	var base: int = verts.size()
	verts.append(Vector3(p0.x + seaward.x * BATTER_M, FOOT_Y, p0.y + seaward.y * BATTER_M))
	verts.append(Vector3(p1.x + seaward.x * BATTER_M, FOOT_Y, p1.y + seaward.y * BATTER_M))
	verts.append(Vector3(p0.x, top0 * WorldCoords.VERTICAL_SCALE, p0.y))
	verts.append(Vector3(p1.x, top1 * WorldCoords.VERTICAL_SCALE, p1.y))
	var nrm := Vector3(seaward.x, 0.14, seaward.y).normalized()
	for _i in 4:
		norms.append(nrm)
	indices.append(base)
	indices.append(base + 1)
	indices.append(base + 2)
	indices.append(base + 1)
	indices.append(base + 3)
	indices.append(base + 2)
