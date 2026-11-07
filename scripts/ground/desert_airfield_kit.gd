extends RefCounted
## Desert airfield props (all merged meshes, placed as MultiMeshes by WorldPopulator._dress_desert_ground):
## sandbag blast bays, bell tents and marquees, oil-drum markers and fuel dumps, sand-coloured lorries and bowsers,
## a sandbagged control hut, camouflage nets, taxi scars and honey-limestone field walls (Malta).

const SANDBAG := Color(0.60, 0.52, 0.36)
const SANDBAG_DK := Color(0.50, 0.43, 0.30)
const CANVAS := Color(0.70, 0.64, 0.49)
const CANVAS_DK := Color(0.55, 0.49, 0.37)
const DRUM_RED := Color(0.50, 0.21, 0.13)
const DRUM_OLIVE := Color(0.33, 0.35, 0.23)
const DRUM_DARK := Color(0.13, 0.12, 0.11)
const WHITE := Color(0.88, 0.86, 0.80)
const LIMESTONE := Color(0.76, 0.67, 0.49)
const DARK := Color(0.07, 0.07, 0.07)


static func _cached(key: String) -> ArrayMesh:
	return Scatter._meshes[key] if Scatter._meshes.has(key) else null


static func _put(key: String, parts: Array) -> ArrayMesh:
	var m: ArrayMesh = AirfieldAssets._build(parts)
	Scatter._meshes[key] = m
	return m


## Oil drum with a white painted top: strip boundary marker (about 1 m tall).
static func drum_marker() -> ArrayMesh:
	if _cached("dk_drum_marker") != null:
		return _cached("dk_drum_marker")
	var parts: Array = []
	parts.append(GroundKit.cyl_part(0.42, 0.42, 1.0, Vector3(0, 0.5, 0), DRUM_RED, Vector3.ZERO, 8, false))
	parts.append(GroundKit.cyl_part(0.44, 0.44, 0.18, Vector3(0, 0.8, 0), WHITE, Vector3.ZERO, 8, false))
	return _put("dk_drum_marker", parts)


## Tall pole with a red and white flag, marking the strip ends and corners (about 3.5 m).
static func flag_marker() -> ArrayMesh:
	if _cached("dk_flag_marker") != null:
		return _cached("dk_flag_marker")
	var parts: Array = []
	parts.append(GroundKit.cyl_part(0.45, 0.5, 0.7, Vector3(0, 0.35, 0), DRUM_RED, Vector3.ZERO, 8, false))
	parts.append(GroundKit.cyl_part(0.07, 0.09, 4.2, Vector3(0, 2.4, 0), Color(0.3, 0.26, 0.2), Vector3.ZERO, 5, false))
	parts.append(GroundKit.box_part(Vector3(1.5, 0.55, 0.05), Vector3(0.8, 4.3, 0), WHITE, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(1.5, 0.55, 0.05), Vector3(0.8, 3.75, 0), DRUM_RED, Vector3.ZERO, false))
	return _put("dk_flag_marker", parts)


## Round bell tent in sand canvas, about 5 m across and 3.5 m high.
static func bell_tent() -> ArrayMesh:
	if _cached("dk_bell_tent") != null:
		return _cached("dk_bell_tent")
	var parts: Array = []
	parts.append(GroundKit.cyl_part(2.5, 2.5, 1.1, Vector3(0, 0.55, 0), CANVAS, Vector3.ZERO, 10, false))
	parts.append(GroundKit.cyl_part(0.1, 2.65, 2.3, Vector3(0, 2.25, 0), CANVAS.lightened(0.04), Vector3.ZERO, 10, false))
	parts.append(GroundKit.cyl_part(0.07, 0.07, 0.8, Vector3(0, 3.7, 0), Color(0.3, 0.25, 0.18), Vector3.ZERO, 5, false))
	parts.append(GroundKit.box_part(Vector3(1.0, 1.5, 0.12), Vector3(0, 0.75, 2.45), DARK, Vector3.ZERO, false))
	return _put("dk_bell_tent", parts)


## Stacked crates, drums and tarpaulins at an airfield: an ammo / supply dump (about 10 x 5 m).
static func supply_dump() -> ArrayMesh:
	if _cached("dk_supply_dump") != null:
		return _cached("dk_supply_dump")
	var crate := Color(0.56, 0.49, 0.34)
	var tarp := Color(0.42, 0.38, 0.27)
	var drums := Color(0.44, 0.39, 0.29)
	var parts: Array = []
	for r in 3:
		for i in 4:
			var x: float = (float(i) - 1.5) * 2.5
			var z: float = (float(r) - 1.0) * 1.7
			parts.append(GroundKit.box_part(Vector3(2.2, 1.05, 1.3), Vector3(x, 0.55, z), crate, Vector3.ZERO, false))
			if (i + r) % 3 == 0:
				parts.append(GroundKit.box_part(Vector3(2.0, 0.95, 1.2), Vector3(x, 1.55, z), crate.darkened(0.08), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(7.2, 0.14, 4.1), Vector3(-1.0, 2.15, 0.2), tarp, Vector3(0.04, 0.0, 0.0), false))
	for i in 5:
		parts.append(GroundKit.cyl_part(0.34, 0.34, 0.92, Vector3(6.2, 0.46, -1.6 + float(i) * 0.95), drums, Vector3.ZERO, 8, false))
	return _put("dk_supply_dump", parts)


## Tall radio / wireless mast with crossarms, guy wires and a small equipment hut at its foot.
static func radio_mast() -> ArrayMesh:
	if _cached("dk_radio_mast") != null:
		return _cached("dk_radio_mast")
	var steel := Color(0.44, 0.44, 0.41)
	var parts: Array = []
	parts.append(GroundKit.cyl_part(0.34, 0.62, 28.0, Vector3(0, 14.0, 0), steel, Vector3.ZERO, 6, false))
	parts.append(GroundKit.box_part(Vector3(5.4, 0.20, 0.20), Vector3(0, 26.0, 0), steel, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(4.0, 0.18, 0.18), Vector3(0, 19.0, 0), steel, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(2.8, 0.18, 0.18), Vector3(0, 12.0, 0), steel, Vector3.ZERO, false))
	# three guy wires
	for i in 3:
		var ya: float = TAU * float(i) / 3.0
		var off := Vector3(cos(ya) * 5.0, 10.0, sin(ya) * 5.0)
		parts.append(GroundKit.box_part(Vector3(0.07, 21.0, 0.07), off, Color(0.30, 0.30, 0.28), Vector3(sin(ya) * 0.48, 0.0, -cos(ya) * 0.48), false))
	parts.append(GroundKit.box_part(Vector3(3.0, 2.2, 2.6), Vector3(3.4, 1.1, 0), Color(0.62, 0.57, 0.46), Vector3.ZERO, false))
	return _put("dk_radio_mast", parts)


## Large white ridge tent (the standard army camp tent): vertical walls and a pitched canvas roof,
## long axis along X, about 7.4 x 4.6 m and 3 m high.
static func ridge_tent() -> ArrayMesh:
	if _cached("dk_ridge_tent") != null:
		return _cached("dk_ridge_tent")
	var white := Color(0.91, 0.90, 0.85)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(7.4, 1.3, 4.6), Vector3(0, 0.65, 0), white, Vector3.ZERO, false))
	parts.append([GroundKit.prism_mesh(5.0, 7.6, 1.9), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 1.3, 0)), GroundKit.mat(Color(0.94, 0.93, 0.88), false)])
	parts.append(GroundKit.box_part(Vector3(0.12, 1.7, 1.6), Vector3(3.72, 0.85, 0), Color(0.55, 0.52, 0.45), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(7.6, 0.08, 0.08), Vector3(0, 2.95, 0), Color(0.72, 0.70, 0.64), Vector3.ZERO, false))
	return _put("dk_ridge_tent", parts)


## Packed-earth parade square / well apron at a camp centre: a flat disc, a foot above the sand.
static func parade_ring() -> ArrayMesh:
	if _cached("dk_parade_ring") != null:
		return _cached("dk_parade_ring")
	var parts: Array = []
	parts.append(GroundKit.cyl_part(13.0, 13.0, 0.06, Vector3(0, 0.03, 0), Color(0.52, 0.44, 0.32), Vector3.ZERO, 20, false))
	parts.append(GroundKit.cyl_part(9.5, 9.5, 0.07, Vector3(0, 0.04, 0), Color(0.58, 0.49, 0.36), Vector3.ZERO, 20, false))
	return _put("dk_parade_ring", parts)


## Large marquee (mess, stores, ops tent): long axis along X, about 14 x 7 m.
static func marquee() -> ArrayMesh:
	if _cached("dk_marquee") != null:
		return _cached("dk_marquee")
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(14.0, 2.4, 7.0), Vector3(0, 1.2, 0), CANVAS, Vector3.ZERO, false))
	parts.append([GroundKit.prism_mesh(7.6, 14.4, 2.4), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 2.4, 0)), GroundKit.mat(CANVAS_DK, false)])
	parts.append(GroundKit.box_part(Vector3(0.12, 1.6, 2.0), Vector3(7.02, 0.9, 0), DARK, Vector3.ZERO, false))
	return _put("dk_marquee", parts)


## U-shaped sandbag blast bay for one fighter, open towards +Z (aircraft nose toward +Z, tail to the back wall).
static func bay() -> ArrayMesh:
	if _cached("dk_bay") != null:
		return _cached("dk_bay")
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(17.0, 1.5, 1.7), Vector3(0, 0.75, -7.2), SANDBAG, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(17.2, 0.3, 1.9), Vector3(0, 1.6, -7.2), SANDBAG_DK, Vector3.ZERO, false))
	for sx in [-1.0, 1.0]:
		parts.append(GroundKit.box_part(Vector3(1.6, 1.4, 7.5), Vector3(sx * 8.3, 0.7, -3.4), SANDBAG, Vector3.ZERO, false))
		parts.append(GroundKit.box_part(Vector3(1.8, 0.3, 7.7), Vector3(sx * 8.3, 1.5, -3.4), SANDBAG_DK, Vector3.ZERO, false))
	return _put("dk_bay", parts)


## Sandbagged control hut with a flat plank roof, a signal mast and a flag. Door toward +Z.
static func control_hut() -> ArrayMesh:
	if _cached("dk_control_hut") != null:
		return _cached("dk_control_hut")
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(6.0, 2.6, 4.6), Vector3(0, 1.3, 0), SANDBAG, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(6.6, 0.3, 5.2), Vector3(0, 2.75, 0), Color(0.34, 0.29, 0.21), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(1.1, 1.8, 0.2), Vector3(-1.2, 0.9, 2.35), DARK, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(1.6, 0.8, 0.2), Vector3(1.4, 1.7, 2.35), Color(0.14, 0.17, 0.18), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(5.0, 0.6, 0.9), Vector3(0, 0.3, 3.4), SANDBAG_DK, Vector3.ZERO, false))   # sandbag screen
	parts.append(GroundKit.cyl_part(0.08, 0.11, 8.0, Vector3(2.2, 7.0, -1.2), Color(0.3, 0.26, 0.2), Vector3.ZERO, 5, false))
	parts.append(GroundKit.box_part(Vector3(1.4, 0.8, 0.05), Vector3(2.9, 10.2, -1.2), DRUM_RED, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(1.8, 0.1, 0.1), Vector3(2.2, 9.0, -1.2), Color(0.3, 0.26, 0.2), Vector3.ZERO, false))
	return _put("dk_control_hut", parts)


## Camouflage net on four poles, sand and brown, 13 x 9 m, 2.8 m up (vehicles park beneath).
static func camo_net() -> ArrayMesh:
	if _cached("dk_camo_net") != null:
		return _cached("dk_camo_net")
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(13.0, 0.1, 9.0), Vector3(0, 2.8, 0), Color(0.55, 0.47, 0.32), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(6.0, 0.12, 4.0), Vector3(-2.0, 2.86, 1.0), Color(0.40, 0.36, 0.25), Vector3.ZERO, false))
	for px in [-6.2, 6.2]:
		for pz in [-4.2, 4.2]:
			parts.append(GroundKit.cyl_part(0.1, 0.1, 2.8, Vector3(px, 1.4, pz), Color(0.3, 0.25, 0.18), Vector3.ZERO, 5, false))
	return _put("dk_camo_net", parts)


## Fuel dump: rows of 44-gallon drums standing in the sand, some stacked two high.
static func fuel_dump() -> ArrayMesh:
	if _cached("dk_fuel_dump") != null:
		return _cached("dk_fuel_dump")
	var parts: Array = []
	var cols: Array = [DRUM_RED, DRUM_OLIVE, DRUM_DARK]
	for row in 5:
		for i in 14:
			var c: Color = cols[(row + i / 4) % 3]
			var p := Vector3(float(i) * 1.05, 0.5, float(row) * 1.5)
			parts.append(GroundKit.cyl_part(0.4, 0.4, 1.0, p, c, Vector3.ZERO, 7, false))
			if (i + row) % 3 == 0:
				parts.append(GroundKit.cyl_part(0.4, 0.4, 1.0, p + Vector3(0, 1.0, 0), cols[(row + i + 1) % 3], Vector3.ZERO, 7, false))
	parts.append(GroundKit.box_part(Vector3(15.0, 0.8, 0.9), Vector3(7.0, 0.4, -1.2), SANDBAG_DK, Vector3.ZERO, false))
	return _put("dk_fuel_dump", parts)


## Sand-painted three-ton lorry with a canvas tilt. Nose at -Z (same footprint as AirfieldAssets.truck).
static func lorry() -> ArrayMesh:
	if _cached("dk_lorry") != null:
		return _cached("dk_lorry")
	var paint := Color(0.56, 0.48, 0.34)
	var parts: Array = _truck_chassis(paint)
	parts.append(GroundKit.box_part(Vector3(2.5, 0.5, 4.6), Vector3(0, 1.25, 2.1), paint.darkened(0.1), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(2.4, 1.7, 4.4), Vector3(0, 2.35, 2.1), CANVAS, Vector3.ZERO, false))
	parts.append(GroundKit.cyl_part(1.2, 1.2, 4.4, Vector3(0, 3.15, 2.1), CANVAS.lightened(0.04), Vector3(90, 0, 0), 8, false))
	return _put("dk_lorry", parts)


## Fuel bowser: sand-painted chassis with a cylindrical tank.
static func bowser() -> ArrayMesh:
	if _cached("dk_bowser") != null:
		return _cached("dk_bowser")
	var paint := Color(0.50, 0.44, 0.32)
	var parts: Array = _truck_chassis(paint)
	parts.append(GroundKit.cyl_part(1.25, 1.25, 4.8, Vector3(0, 2.35, 2.0), Color(0.42, 0.40, 0.33), Vector3(90, 0, 0), 10, false))
	parts.append(GroundKit.box_part(Vector3(0.9, 0.5, 0.9), Vector3(0, 3.7, 1.6), DARK, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(2.0, 0.12, 0.5), Vector3(0, 0.9, 4.6), Color(0.55, 0.12, 0.08), Vector3.ZERO, false))
	return _put("dk_bowser", parts)


## Water bowser: box tank on a lorry chassis.
static func water_bowser() -> ArrayMesh:
	if _cached("dk_water") != null:
		return _cached("dk_water")
	var paint := Color(0.50, 0.46, 0.34)
	var parts: Array = _truck_chassis(paint)
	parts.append(GroundKit.box_part(Vector3(2.3, 1.8, 4.2), Vector3(0, 2.3, 2.1), Color(0.40, 0.42, 0.36), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.7, 0.3, 0.7), Vector3(0, 3.3, 1.0), DARK, Vector3.ZERO, false))
	return _put("dk_water", parts)


static func _truck_chassis(paint: Color) -> Array:
	var parts: Array = []
	var glass := Color(0.13, 0.17, 0.2)
	parts.append(GroundKit.box_part(Vector3(1.9, 0.5, 7.6), Vector3(0, 0.85, 0.2), DARK, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(2.1, 1.1, 1.8), Vector3(0, 1.65, -3.2), paint, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(2.3, 1.0, 0.6), Vector3(0, 1.4, -4.1), paint.darkened(0.08), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(2.35, 1.7, 1.7), Vector3(0, 2.2, -1.7), paint.lightened(0.04), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(2.0, 0.7, 0.12), Vector3(0, 2.45, -2.58), glass, Vector3(-12, 0, 0), false))
	for wz in [-3.0, 1.0, 3.2]:
		for wx in [-1.05, 1.05]:
			parts.append(GroundKit.cyl_part(0.55, 0.55, 0.45, Vector3(wx, 0.55, wz), DARK, Vector3(0, 0, 90), 8, false))
	return parts


## Taxi and wheel scars: pairs of dark ruts wandering between points (local airfield frame), as one merged mesh.
## `paths` is an Array of PackedVector3Array polylines.
static func scars(paths: Array) -> ArrayMesh:
	var parts: Array = []
	var col := Color(0.38, 0.30, 0.20)
	for pl in paths:
		var pts: PackedVector3Array = pl
		for i in range(pts.size() - 1):
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var d: Vector3 = b - a
			var ln: float = Vector2(d.x, d.z).length()
			if ln < 1.0:
				continue
			var yaw: float = rad_to_deg(atan2(d.x, d.z))
			var nrm := Vector3(d.z, 0.0, -d.x).normalized()
			for side in [-1.3, 1.3]:
				var mid: Vector3 = (a + b) * 0.5 + nrm * float(side)
				parts.append(GroundKit.box_part(Vector3(0.8, 0.05, ln + 0.6), Vector3(mid.x, 0.3, mid.z), col, Vector3(0, yaw, 0), false))
	return AirfieldAssets._build(parts) if not parts.is_empty() else null


## Dry-stone field walls in honey limestone (Malta): each wall is (start, end) in the local frame.
static func stone_walls(walls: Array) -> ArrayMesh:
	var parts: Array = []
	for w in walls:
		var a: Vector3 = w[0]
		var b: Vector3 = w[1]
		var d: Vector3 = b - a
		var ln: float = Vector2(d.x, d.z).length()
		if ln < 2.0:
			continue
		var mid: Vector3 = (a + b) * 0.5
		var yaw: float = rad_to_deg(atan2(d.x, d.z))
		parts.append(GroundKit.box_part(Vector3(0.9, 1.3, ln), Vector3(mid.x, 0.65, mid.z), LIMESTONE, Vector3(0, yaw, 0), false))
		parts.append(GroundKit.box_part(Vector3(1.1, 0.25, ln), Vector3(mid.x, 1.4, mid.z), LIMESTONE.darkened(0.12), Vector3(0, yaw, 0), false))
	return AirfieldAssets._build(parts) if not parts.is_empty() else null
