class_name AirfieldAssets
extends RefCounted
## Better-looking ground clutter for airfields: lorries and blister (Super-Robin / Over-type) hangars.
## Same footprints as the old blocks so placement, hit radii and wrecks stay as they were. Nose at -Z.


static func _cached(key: String) -> ArrayMesh:
	return Scatter._meshes[key] if Scatter._meshes.has(key) else null


## Combine parts, then merge surfaces that share a material so each prop costs a handful of draw calls, not dozens.
static func _build(parts: Array) -> ArrayMesh:
	var src: ArrayMesh = GroundKit.combine(parts)
	var by_mat: Dictionary = {}
	for i in src.get_surface_count():
		var mat: Material = src.surface_get_material(i)
		var key: int = mat.get_instance_id() if mat != null else 0
		if not by_mat.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_material(mat)
			by_mat[key] = st
		(by_mat[key] as SurfaceTool).append_from(src, i, Transform3D.IDENTITY)
	var out := ArrayMesh.new()
	for k in by_mat:
		(by_mat[k] as SurfaceTool).commit(out)
	return out


static func truck(team: String) -> ArrayMesh:
	var key: String = "truck2_" + team
	if _cached(key) != null:
		return _cached(key)
	var allied: bool = team == "Allies"
	var paint: Color = Color(0.27, 0.31, 0.19) if allied else Color(0.36, 0.36, 0.31)
	var canvas: Color = Color(0.36, 0.37, 0.26) if allied else Color(0.42, 0.41, 0.35)
	var dark := Color(0.07, 0.07, 0.07)
	var glass := Color(0.13, 0.17, 0.2)
	var parts: Array = []
	# chassis and mudguards
	parts.append(GroundKit.box_part(Vector3(1.9, 0.5, 7.6), Vector3(0, 0.85, 0.2), dark, Vector3.ZERO, false))
	# bonnet and cab
	parts.append(GroundKit.box_part(Vector3(2.1, 1.1, 1.8), Vector3(0, 1.65, -3.2), paint))
	parts.append(GroundKit.box_part(Vector3(2.3, 1.0, 0.6), Vector3(0, 1.4, -4.1), paint.darkened(0.08)))   # radiator / grille
	parts.append(GroundKit.box_part(Vector3(2.35, 1.7, 1.7), Vector3(0, 2.2, -1.7), paint.lightened(0.04)))
	parts.append(GroundKit.box_part(Vector3(2.0, 0.7, 0.12), Vector3(0, 2.45, -2.58), glass, Vector3(-12, 0, 0), false))   # windscreen
	parts.append(GroundKit.box_part(Vector3(2.38, 0.5, 1.0), Vector3(0, 2.4, -1.4), glass, Vector3.ZERO, false))           # side windows
	# load bed with canvas tilt
	parts.append(GroundKit.box_part(Vector3(2.5, 0.5, 4.6), Vector3(0, 1.25, 2.1), paint.darkened(0.1)))
	parts.append(GroundKit.box_part(Vector3(2.4, 1.7, 4.4), Vector3(0, 2.35, 2.1), canvas))
	parts.append(GroundKit.cyl_part(1.2, 1.2, 4.4, Vector3(0, 3.15, 2.1), canvas.lightened(0.04), Vector3(90, 0, 0), 8))
	parts.append(GroundKit.box_part(Vector3(1.6, 1.2, 0.12), Vector3(0, 2.3, 4.34), dark, Vector3.ZERO, false))           # open tail
	# wheels
	for wz in [-3.0, 1.0, 3.2]:
		for wx in [-1.05, 1.05]:
			parts.append(GroundKit.cyl_part(0.55, 0.55, 0.45, Vector3(wx, 0.55, wz), dark, Vector3(0, 0, 90), 8, false))
	# headlights
	for hx in [-0.8, 0.8]:
		parts.append(GroundKit.box_part(Vector3(0.3, 0.3, 0.1), Vector3(hx, 1.75, -4.42), Color(0.9, 0.85, 0.6), Vector3.ZERO, false))
	var m: ArrayMesh = _build(parts)
	Scatter._meshes[key] = m
	return m


static func blister(team: String) -> ArrayMesh:
	var key: String = "blister2_" + team
	if _cached(key) != null:
		return _cached(key)
	var allied: bool = team == "Allies"
	var skin: Color = Color(0.24, 0.30, 0.18) if allied else Color(0.32, 0.33, 0.28)
	var rib: Color = skin.darkened(0.22)
	var dark := Color(0.06, 0.06, 0.06)
	var parts: Array = []
	# curved shell: a lying half-buried cylinder, with raised ribs along its length
	parts.append(GroundKit.cyl_part(5.0, 5.0, 15.0, Vector3(0, 0.0, 0), skin, Vector3(90, 0, 0), 12))
	for i in 7:
		var z: float = -6.6 + float(i) * 2.2
		parts.append(GroundKit.cyl_part(5.4, 5.4, 0.55, Vector3(0, 0.0, z), rib, Vector3(90, 0, 0), 12, false))
	# open end: dark interior, door frame and a sliding door leaf pushed to one side
	parts.append(GroundKit.box_part(Vector3(8.6, 4.0, 0.3), Vector3(0, 2.0, 7.45), dark, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.5, 4.3, 0.6), Vector3(-4.5, 2.1, 7.55), rib))
	parts.append(GroundKit.box_part(Vector3(0.5, 4.3, 0.6), Vector3(4.5, 2.1, 7.55), rib))
	parts.append(GroundKit.box_part(Vector3(9.5, 0.5, 0.6), Vector3(0, 4.2, 7.55), rib))
	parts.append(GroundKit.box_part(Vector3(3.6, 3.7, 0.25), Vector3(2.7, 2.0, 7.75), skin.lightened(0.05)))
	# blank rear wall
	parts.append(GroundKit.box_part(Vector3(9.4, 4.4, 0.3), Vector3(0, 2.2, -7.4), skin))
	var m: ArrayMesh = _build(parts)
	Scatter._meshes[key] = m
	return m


## Corrugated Nissen hut: half-round iron roof with ribs, brick gable ends with door and window, a stove chimney.
static func nissen(team: String) -> ArrayMesh:
	var key: String = "nissen2_" + team
	if _cached(key) != null:
		return _cached(key)
	var iron: Color = Color(0.40, 0.42, 0.32) if team == "Allies" else Color(0.38, 0.38, 0.34)
	var brick := Color(0.45, 0.31, 0.24)
	var dark := Color(0.08, 0.08, 0.08)
	var parts: Array = []
	parts.append(GroundKit.cyl_part(3.0, 3.0, 11.0, Vector3(0, 1.3, 0), iron, Vector3(90, 0, 0), 12))
	for i in 9:
		parts.append(GroundKit.cyl_part(3.12, 3.12, 0.28, Vector3(0, 1.3, -4.8 + float(i) * 1.2), iron.darkened(0.2), Vector3(90, 0, 0), 12, false))
	for zs in [-5.5, 5.5]:
		parts.append(GroundKit.box_part(Vector3(5.6, 3.0, 0.35), Vector3(0, 1.5, zs), brick))
	parts.append(GroundKit.box_part(Vector3(1.1, 2.0, 0.4), Vector3(-1.0, 1.0, 5.62), dark, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(1.0, 0.9, 0.4), Vector3(1.4, 1.8, 5.62), Color(0.16, 0.2, 0.22), Vector3.ZERO, false))
	parts.append(GroundKit.cyl_part(0.28, 0.28, 1.4, Vector3(0.8, 4.4, -1.5), Color(0.2, 0.2, 0.2), Vector3.ZERO, 6, false))
	var m: ArrayMesh = _build(parts)
	Scatter._meshes[key] = m
	return m


## Ridge tent with a dark door flap and guy-pole tips. About 4 x 6 m.
static func tent(team: String) -> ArrayMesh:
	var key: String = "tent2_" + team
	if _cached(key) != null:
		return _cached(key)
	var cloth: Color = Color(0.45, 0.45, 0.32) if team == "Allies" else Color(0.40, 0.41, 0.36)
	var parts: Array = []
	for sd in [-1.0, 1.0]:
		parts.append(GroundKit.box_part(Vector3(3.12, 0.1, 6.0), Vector3(sd * 1.0, 1.2, 0), cloth, Vector3(0, 0, -sd * 50.2)))
	parts.append(GroundKit.box_part(Vector3(0.14, 0.14, 6.3), Vector3(0, 2.42, 0), cloth.darkened(0.3), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(1.1, 1.5, 0.1), Vector3(0, 0.8, 3.0), Color(0.07, 0.07, 0.06), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(4.0, 0.5, 0.1), Vector3(0, 0.25, -3.0), cloth.darkened(0.15), Vector3.ZERO, false))
	var m: ArrayMesh = _build(parts)
	Scatter._meshes[key] = m
	return m


## Bulk fuel tank: concrete plinth, banded steel drum, domed roof with hatch, ladder, and a pipe run. Centre at origin, base y = 0.
static func fuel_tank() -> ArrayMesh:
	if _cached("fuel_tank2") != null:
		return _cached("fuel_tank2")
	var steel := Color(0.58, 0.58, 0.55)
	var band := Color(0.34, 0.35, 0.34)
	var parts: Array = []
	parts.append(GroundKit.cyl_part(5.1, 5.1, 0.5, Vector3(0, 0.25, 0), Color(0.55, 0.54, 0.5), Vector3.ZERO, 14))
	parts.append(GroundKit.cyl_part(4.5, 4.5, 5.6, Vector3(0, 3.3, 0), steel, Vector3.ZERO, 14))
	for yb in [1.5, 3.3, 5.1]:
		parts.append(GroundKit.cyl_part(4.58, 4.58, 0.22, Vector3(0, yb, 0), band, Vector3.ZERO, 14, false))
	parts.append(GroundKit.cyl_part(1.2, 4.5, 1.1, Vector3(0, 6.65, 0), steel.darkened(0.06), Vector3.ZERO, 14))
	parts.append(GroundKit.cyl_part(0.7, 0.7, 0.5, Vector3(0, 7.45, 0), band, Vector3.ZERO, 8))
	parts.append(GroundKit.box_part(Vector3(0.18, 6.4, 0.55), Vector3(4.62, 3.4, 0), Color(0.15, 0.15, 0.15), Vector3.ZERO, false))
	parts.append(GroundKit.cyl_part(0.3, 0.3, 4.4, Vector3(0, 0.9, 6.2), Color(0.2, 0.2, 0.2), Vector3(90, 0, 0), 6, false))
	parts.append(GroundKit.cyl_part(0.3, 0.3, 1.4, Vector3(0, 0.9, 4.6), Color(0.2, 0.2, 0.2), Vector3(90, 0, 0), 6, false))
	var m: ArrayMesh = _build(parts)
	Scatter._meshes["fuel_tank2"] = m
	return m


## Bomb dump: three earth revetment walls round a pallet stack of bombs with fins and noses.
static func bomb_bank() -> ArrayMesh:
	if _cached("bomb_bank2") != null:
		return _cached("bomb_bank2")
	var earth := Color(0.34, 0.29, 0.2)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(14.0, 3.4, 3.0), Vector3(0, 1.7, -5.0), earth))
	parts.append(GroundKit.box_part(Vector3(3.0, 3.4, 10.0), Vector3(-5.5, 1.7, 0.0), earth))
	parts.append(GroundKit.box_part(Vector3(3.0, 3.4, 10.0), Vector3(5.5, 1.7, 0.0), earth))
	parts.append(GroundKit.box_part(Vector3(6.4, 0.25, 5.4), Vector3(0, 0.12, 0.0), Color(0.3, 0.22, 0.14)))
	var bomb := Color(0.28, 0.31, 0.2)
	var yel := Color(0.78, 0.66, 0.2)
	for layer in 2:
		for r in 3:
			for c in 5 - layer:
				var x: float = -2.0 + float(c) * 0.9 + float(layer) * 0.45
				var z: float = -1.6 + float(r) * 1.45
				var y: float = 0.62 + float(layer) * 0.5
				parts.append(GroundKit.cyl_part(0.26, 0.26, 2.0, Vector3(x, y, z), bomb, Vector3(90, 0, 0), 6, false))
				parts.append(GroundKit.cyl_part(0.04, 0.26, 0.45, Vector3(x, y, z - 1.2), yel, Vector3(90, 0, 0), 6, false))
				parts.append(GroundKit.box_part(Vector3(0.7, 0.04, 0.4), Vector3(x, y, z + 1.0), bomb.darkened(0.2), Vector3.ZERO, false))
	var m: ArrayMesh = _build(parts)
	Scatter._meshes["bomb_bank2"] = m
	return m


## RAF T2 hangar (240 ft x 115 ft steel-truss hangar): a tall gabled shed with big sliding doors. Nose at -Z.
static func t2_hangar(team: String) -> ArrayMesh:
	var key: String = "t2hangar_" + team
	if _cached(key) != null:
		return _cached(key)
	var skin: Color = Color(0.5, 0.51, 0.47) if team == "Allies" else Color(0.46, 0.46, 0.43)
	var rib: Color = skin.darkened(0.2)
	var door: Color = Color(0.34, 0.35, 0.33)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(34.0, 9.0, 72.0), Vector3(0, 4.5, 0), skin))
	for i in 9:
		parts.append(GroundKit.box_part(Vector3(34.4, 9.2, 0.5), Vector3(0, 4.6, -34.0 + float(i) * 8.5), rib, Vector3.ZERO, false))
	parts.append([GroundKit.prism_mesh(34.2, 72.2, 5.0), Transform3D(Basis(), Vector3(0, 9.0, 0)), GroundKit.mat(skin.darkened(0.08), true)])
	for sx in [-1.0, 1.0]:
		parts.append(GroundKit.box_part(Vector3(16.4, 8.4, 0.4), Vector3(sx * 8.4, 4.2, 36.2), door))
	parts.append(GroundKit.box_part(Vector3(1.0, 9.2, 0.7), Vector3(0, 4.6, 36.2), rib))
	parts.append(GroundKit.box_part(Vector3(34.0, 9.0, 0.4), Vector3(0, 4.5, -36.2), skin.darkened(0.05)))
	var m: ArrayMesh = _build(parts)
	Scatter._meshes[key] = m
	return m


## RAF T1 hangar (186 ft x 96 ft): a smaller gabled shed, same construction. Nose at -Z.
static func t1_hangar(team: String) -> ArrayMesh:
	var key: String = "t1hangar_" + team
	if _cached(key) != null:
		return _cached(key)
	var skin: Color = Color(0.49, 0.5, 0.46) if team == "Allies" else Color(0.45, 0.45, 0.42)
	var rib: Color = skin.darkened(0.2)
	var door: Color = Color(0.34, 0.35, 0.33)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(29.0, 8.0, 56.0), Vector3(0, 4.0, 0), skin))
	for i in 8:
		parts.append(GroundKit.box_part(Vector3(29.4, 8.2, 0.5), Vector3(0, 4.1, -28.0 + float(i) * 8.0), rib, Vector3.ZERO, false))
	parts.append([GroundKit.prism_mesh(29.2, 56.2, 4.4), Transform3D(Basis(), Vector3(0, 8.0, 0)), GroundKit.mat(skin.darkened(0.08), true)])
	for sx in [-1.0, 1.0]:
		parts.append(GroundKit.box_part(Vector3(13.9, 7.4, 0.4), Vector3(sx * 7.2, 3.7, 28.2), door))
	parts.append(GroundKit.box_part(Vector3(1.0, 8.2, 0.7), Vector3(0, 4.1, 28.2), rib))
	parts.append(GroundKit.box_part(Vector3(29.0, 8.0, 0.4), Vector3(0, 4.0, -28.2), skin.darkened(0.05)))
	var m: ArrayMesh = _build(parts)
	Scatter._meshes[key] = m
	return m


## A straight earth blast-wall / revetment segment (~22 m long, 2.4 m high). Placed end to end to line a pen.
static func revetment(team: String) -> ArrayMesh:
	var key: String = "revetment_" + team
	if _cached(key) != null:
		return _cached(key)
	var earth: Color = Color(0.34, 0.29, 0.2)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(1.8, 2.4, 22.0), Vector3(0, 1.2, 0), earth))
	parts.append(GroundKit.box_part(Vector3(2.3, 0.5, 22.4), Vector3(0, 2.5, 0), earth.lightened(0.06), Vector3.ZERO, false))
	var m: ArrayMesh = _build(parts)
	Scatter._meshes[key] = m
	return m


## A Chance light: a trailer-mounted floodlight (the wartime airfield flare-path lamp). Base at y = 0.
static func chance_light() -> ArrayMesh:
	if _cached("chance_light2") != null:
		return _cached("chance_light2")
	var metal: Color = Color(0.3, 0.3, 0.32)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(1.6, 0.5, 2.6), Vector3(0, 0.45, 0), metal))
	for wx in [-0.7, 0.7]:
		parts.append(GroundKit.cyl_part(0.34, 0.34, 0.3, Vector3(wx, 0.34, 0.0), Color(0.1, 0.1, 0.1), Vector3(0, 0, 90), 6, false))
	parts.append(GroundKit.cyl_part(0.07, 0.07, 1.5, Vector3(0, 1.4, -0.6), metal, Vector3.ZERO, 6, false))
	parts.append(GroundKit.box_part(Vector3(1.2, 0.9, 0.7), Vector3(0, 2.4, -0.6), Color(0.9, 0.88, 0.6)))
	parts.append(GroundKit.box_part(Vector3(0.06, 0.85, 0.65), Vector3(0, 2.4, -0.95), Color(1.0, 0.96, 0.8), Vector3.ZERO, false))
	var m: ArrayMesh = _build(parts)
	Scatter._meshes["chance_light2"] = m
	return m


## A dummy aircraft: the flat plywood-and-canvas silhouette used on decoy and decoy-dispersed stands. Nose at -Z.
static func dummy_aircraft(team: String) -> ArrayMesh:
	var key: String = "dummy_ac_" + team
	if _cached(key) != null:
		return _cached(key)
	var col: Color = Color(0.32, 0.38, 0.24) if team == "Allies" else Color(0.4, 0.4, 0.33)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(1.7, 0.5, 11.0), Vector3(0, 1.1, 0), col))
	parts.append(GroundKit.box_part(Vector3(13.0, 0.35, 2.2), Vector3(0, 1.1, -0.5), col))
	parts.append(GroundKit.box_part(Vector3(4.6, 0.3, 1.2), Vector3(0, 1.15, 4.6), col))
	parts.append(GroundKit.box_part(Vector3(0.25, 1.6, 1.4), Vector3(0, 2.0, 4.6), col))
	for sx in [-1.0, 1.0]:
		parts.append(GroundKit.cyl_part(0.35, 0.35, 0.5, Vector3(sx * 2.2, 0.35, 0.0), Color(0.1, 0.1, 0.1), Vector3(0, 0, 90), 5, false))
	var m: ArrayMesh = _build(parts)
	Scatter._meshes[key] = m
	return m
