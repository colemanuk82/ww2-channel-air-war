class_name OilFuelKit
extends RefCounted
## P9 oil and fuel scenery: tank farms, refineries, petrol depots and gas holders, placed at the real, cited
## sites in data/oil_fuel_1940.json. The destructible industrial target itself is an existing
## GroundStructure("refinery" / "oil_depot" / "gasworks") (see WorldPopulator._build_oil_fuel); this kit builds
## the works AROUND it - extra product tanks, bunds and pipe runs, a loading gantry and jetty, drum stacks and
## bowsers, cooling towers, telescopic gasholders, rail tank cars. All procedural low-poly toon from GroundKit
## primitives - no photo textures, no new assets.
##
##   var n: Node3D = OilFuelKit.build(kind, pos, heading_deg, size, team, seed_v)   # node sits at world ORIGIN
##
## The returned container holds a `root` at (pos.x, 0, pos.z) whose local -Z is the site front (the WorldFeatures
## / GroundStructure convention). Deterministic from seed_v.

## The scenery kinds this kit understands (mapped to a destructible kind in WorldPopulator._build_oil_fuel).
static func kinds() -> Array:
	return ["refinery", "oil_depot", "tank_farm", "gasworks", "petrol_depot", "gas_holder"]


## Central dispatch, driven by the `kind` in data/oil_fuel_1940.json.
static func build(kind: String, pos: Vector3, heading_deg: float, size: int, team: String, seed_v: int) -> Node3D:
	var container := Node3D.new()
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.z)
	root.rotation.y = -deg_to_rad(heading_deg)
	container.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var sz: int = clampi(size, 1, 3)
	match kind:
		"refinery":
			_refinery(root, sz, team, rng)
		"oil_depot":
			_oil_depot(root, sz, team, rng)
		"gasworks":
			_gasworks(root, sz, rng)
		"petrol_depot":
			_petrol_depot(root, sz, team, rng)
		"gas_holder":
			_gas_holder(root, sz, rng)
		_:
			_tank_farm(root, sz, rng)
	return container


# ------------------------------------------------------------------ helpers
## Terrain height at a local point of `root` (root is at the world origin's XZ with a yaw, as IndustryKit).
static func _gh(root: Node3D, local: Vector3) -> float:
	var w: Vector3 = root.transform * local
	return GroundKit.ground_y(w.x, w.z)


## A storage tank on a low base pad.
static func _tank(root: Node3D, p: Vector3, r: float, h: float, col: Color) -> void:
	var gy: float = _gh(root, p)
	GroundKit.box(root, Vector3(r * 2.3, 0.4, r * 2.3), Vector3(p.x, gy + 0.2, p.z), Color(0.35, 0.33, 0.3), Vector3.ZERO, false)
	GroundKit.cyl(root, r, r, h, Vector3(p.x, gy + 0.4 + h * 0.5, p.z), col, Vector3.ZERO, 14)
	GroundKit.cyl(root, r * 1.04, r * 1.04, 0.5, Vector3(p.x, gy + 0.4 + h, p.z), col.darkened(0.25), Vector3.ZERO, 14, false)


## A cluster of tanks on a grid (rows x cols) with an in-line pipe run.
static func _tank_rows(root: Node3D, origin: Vector3, rows: int, cols: int, gap: float, r: float, h: float, col: Color) -> void:
	for rr in rows:
		for cc in cols:
			var p := origin + Vector3(float(cc) * gap, 0.0, float(rr) * gap)
			_tank(root, p, r, h, col if (rr + cc) % 2 == 0 else col.darkened(0.08))
	GroundKit.box(root, Vector3(float(cols) * gap, 0.8, 1.2), Vector3(origin.x + float(cols - 1) * gap * 0.5, _gh(root, origin) + 4.0, origin.z - gap * 0.4), Color(0.24, 0.24, 0.26), Vector3.ZERO, false)


## A stack of oil drums and a couple of road tanker bowsers (a small depot stores its product in drums).
static func _drums_and_bowsers(root: Node3D, p: Vector3, rng: RandomNumberGenerator, team: String) -> void:
	var gy: float = _gh(root, p)
	var drum: Color = Color(0.22, 0.2, 0.18)
	for s in 3:
		for i in 8:
			var dx: float = float(i % 4) * 1.1 - 2.0
			var dz: float = float(i / 4) * 1.1 - 0.6
			var dy: float = float(s) * 1.0
			GroundKit.cyl(root, 0.5, 0.5, 1.0, Vector3(p.x + dx, gy + 0.5 + dy, p.z + dz), drum, Vector3.ZERO, 8, false)
	for b in 2:
		var bp := Vector3(p.x + 10.0 + float(b) * 5.0, gy, p.z + 2.0 + rng.randf_range(-2.0, 2.0))
		var paint: Color = Color(0.36, 0.36, 0.31) if team == "Axis" else Color(0.3, 0.34, 0.22)
		GroundKit.box(root, Vector3(2.4, 1.6, 7.0), Vector3(bp.x, bp.y + 1.6, bp.z), paint)
		GroundKit.box(root, Vector3(2.2, 1.0, 2.0), Vector3(bp.x, bp.y + 2.7, bp.z - 2.2), paint.lightened(0.05))
		GroundKit.cyl(root, 2.0, 2.0, 4.4, Vector3(bp.x, bp.y + 3.4, bp.z + 0.6), Color(0.6, 0.6, 0.56), Vector3(90.0, 0.0, 0.0), 10)


## A works flag mast so a site reads as owned by one side.
static func _flag(root: Node3D, local: Vector3, team: String) -> void:
	var gy: float = _gh(root, local)
	GroundKit.cyl(root, 0.15, 0.18, 10.0, Vector3(local.x, gy + 5.0, local.z), GroundKit.COL_STEEL, Vector3.ZERO, 6, false)
	GroundKit.box(root, Vector3(2.8, 1.6, 0.1), Vector3(local.x + 1.4, gy + 9.0, local.z), Color(0.75, 0.15, 0.13) if team == "Allies" else Color(0.55, 0.55, 0.55), Vector3.ZERO, false)


# ------------------------------------------------------------------ kinds
## A refinery: product tank rows on the technical side, a cooling tower, distillation columns, a pipe rack and a
## loading gantry/jetty on the front (local -Z, i.e. the water or rail side).
static func _refinery(root: Node3D, size: int, team: String, rng: RandomNumberGenerator) -> void:
	var tank: Color = Color(0.6, 0.6, 0.57)
	var steel: Color = Color(0.62, 0.64, 0.64)
	_tank_rows(root, Vector3(-30.0, 0.0, 40.0), 2 + size, 3, 26.0, 8.0, 11.0, tank)
	GroundKit.cyl(root, 1.6, 1.8, 40.0, Vector3(-64.0, 20.0, 74.0), Color(0.36, 0.36, 0.37), Vector3.ZERO, 8)          # flare stack
	GroundKit.cyl(root, 0.0, 1.6, 3.6, Vector3(-64.0, 42.0, 74.0), Color(1.0, 0.55, 0.12), Vector3.ZERO, 8, false)      # flare flame
	# distillation / cracking columns
	for i in 3 + size:
		var cx: float = -70.0 + float(i) * 15.0
		GroundKit.cyl(root, 2.4, 2.6, 34.0, Vector3(cx, 17.0, 8.0), steel, Vector3.ZERO, 10)
		for b in 2:
			GroundKit.cyl(root, 2.9, 2.9, 0.7, Vector3(cx, 10.0 + float(b) * 12.0, 8.0), steel.darkened(0.25), Vector3.ZERO, 10, false)
	# cooling tower with a flared top
	GroundKit.cyl(root, 11.0, 14.0, 30.0, Vector3(64.0, 15.0, 30.0), Color(0.5, 0.5, 0.48), Vector3.ZERO, 12)
	GroundKit.cyl(root, 14.0, 12.0, 4.0, Vector3(64.0, 32.0, 30.0), Color(0.46, 0.46, 0.44), Vector3.ZERO, 12, false)
	# pipe racks across the works
	for y in [6.0, 8.0]:
		GroundKit.box(root, Vector3(150.0, 0.8, 1.2), Vector3(0.0, y, -6.0), Color(0.26, 0.26, 0.28) if y < 7.0 else Color(0.3, 0.2, 0.15), Vector3.ZERO, false)
	# loading gantry / jetty on the front (-Z = the front)
	GroundKit.box(root, Vector3(90.0, 1.2, 14.0), Vector3(0.0, 4.0, -70.0), Color(0.42, 0.4, 0.36), Vector3.ZERO, false)
	for i in 5:
		GroundKit.cyl(root, 0.6, 0.7, 5.0, Vector3(-36.0 + float(i) * 18.0, 2.5, -70.0), GroundKit.COL_STEEL, Vector3.ZERO, 6, false)
		GroundKit.cyl(root, 0.4, 0.4, 6.0, Vector3(-36.0 + float(i) * 18.0, 7.0, -70.0), Color(0.2, 0.2, 0.22), Vector3.ZERO, 6, false)
	# control / administration block beside the gate
	GroundKit.box(root, Vector3(22.0, 8.0, 12.0), Vector3(58.0, 4.0, -50.0), GroundKit.COL_BRICK.darkened(0.08))
	_flag(root, Vector3(-80.0, 0.0, -50.0), team)


## A fuel storage depot / marine terminal: modest tank rows, drum stacks, bowsers and a loading rack.
static func _oil_depot(root: Node3D, size: int, team: String, rng: RandomNumberGenerator) -> void:
	var tank: Color = Color(0.55, 0.56, 0.54)
	_tank_rows(root, Vector3(-24.0, 0.0, 20.0), 2, 2 + size, 24.0, 7.0, 10.0, tank)
	GroundKit.box(root, Vector3(60.0, 0.6, 1.0), Vector3(0.0, 4.5, 6.0), Color(0.22, 0.22, 0.24), Vector3.ZERO, false)      # pipe run
	GroundKit.box(root, Vector3(40.0, 0.8, 10.0), Vector3(0.0, 3.0, -34.0), Color(0.42, 0.4, 0.36), Vector3.ZERO, false)     # loading rack
	for i in 4:
		GroundKit.cyl(root, 0.4, 0.5, 4.0, Vector3(-15.0 + float(i) * 10.0, 2.0, -34.0), GroundKit.COL_STEEL, Vector3.ZERO, 6, false)
	_drums_and_bowsers(root, Vector3(30.0, 0.0, -20.0), rng, team)
	GroundKit.box(root, Vector3(20.0, 6.0, 10.0), Vector3(40.0, 3.0, 10.0), GroundKit.COL_BRICK.darkened(0.1))                 # pump house


## A large independent storage tank farm: a dense grid of tanks, interconnecting pipes, a pump house and a rail siding.
static func _tank_farm(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var tank: Color = Color(0.58, 0.58, 0.55)
	_tank_rows(root, Vector3(-45.0, 0.0, -30.0), 2 + size, 3 + size, 30.0, 9.0, 12.0, tank)
	for g in 3:
		GroundKit.box(root, Vector3(140.0, 0.6, 1.2), Vector3(0.0, 5.0, -30.0 + float(g) * 30.0), Color(0.24, 0.24, 0.26), Vector3.ZERO, false)
	GroundKit.box(root, Vector3(24.0, 7.0, 12.0), Vector3(-70.0, 3.5, 60.0), GroundKit.COL_BRICK.darkened(0.1))                # pump house
	# a rail tank siding
	GroundKit.box(root, Vector3(6.0, 0.3, 120.0), Vector3(0.0, 0.15, 90.0), Color(0.4, 0.38, 0.34), Vector3.ZERO, false)
	for i in 5:
		var wz: float = 40.0 + float(i) * 18.0
		GroundKit.cyl(root, 1.6, 1.6, 12.0, Vector3(0.0, 2.2, wz), Color(0.28, 0.28, 0.3), Vector3(90.0, 0.0, 0.0), 10)


## A coal-gas works: telescopic gasholders, a retort house with chimneys, a coal stack and purifiers.
static func _gasworks(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	_gasholder(root, Vector3(-40.0, 0.0, 10.0), 15.0)
	if size >= 2:
		_gasholder(root, Vector3(40.0, 0.0, 10.0), 13.0)
	var brick: Color = GroundKit.COL_BRICK.darkened(0.1)
	GroundKit.box(root, Vector3(50.0, 14.0, 26.0), Vector3(0.0, 7.0, -50.0), brick)                                            # retort house
	var pm := MeshInstance3D.new()
	pm.mesh = GroundKit.prism_mesh(26.0, 50.0, 5.0)
	pm.material_override = GroundKit.mat(Color(0.3, 0.3, 0.32), true)
	pm.position = Vector3(0.0, 14.0, -50.0)
	pm.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	root.add_child(pm)
	for i in 3:
		GroundKit.cyl(root, 1.4, 1.8, 34.0, Vector3(-18.0 + float(i) * 18.0, 17.0, -50.0), brick.lightened(0.08), Vector3.ZERO, 10)
	for i in 8:
		var dx: float = float(i % 4) * 3.0 - 4.0
		var dz: float = float(i / 4) * 3.0
		GroundKit.sphere(root, 2.6, Vector3(60.0 + dx, 2.0, -40.0 + dz), Color(0.1, 0.1, 0.1), Vector3(1.0, 0.5, 1.0), false)   # coal heaps
	GroundKit.box(root, Vector3(26.0, 6.0, 16.0), Vector3(60.0, 3.0, 20.0), brick.darkened(0.15))                              # purifier house


## A standalone gas holder station: one or two telescopic holders with a booster house and chimney.
static func _gas_holder(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var jitter: float = rng.randf_range(-3.0, 3.0)
	_gasholder(root, Vector3(-26.0 + jitter, 0.0, 12.0), 15.0)
	if size >= 2:
		_gasholder(root, Vector3(30.0 + jitter, 0.0, 12.0), 13.0)
	var brick: Color = GroundKit.COL_BRICK.darkened(0.12)
	GroundKit.box(root, Vector3(22.0, 6.0, 14.0), Vector3(0.0, 3.0, -40.0), brick)                                      # booster house
	GroundKit.cyl(root, 1.2, 1.5, 18.0, Vector3(22.0, 9.0, -40.0), brick.lightened(0.06), Vector3.ZERO, 10)              # chimney


## A petrol / distribution depot: a canning shed, drum stacks, bowsers and a rail tank siding.
static func _petrol_depot(root: Node3D, size: int, team: String, rng: RandomNumberGenerator) -> void:
	_tank_rows(root, Vector3(-20.0, 0.0, 20.0), 1, 2 + size, 22.0, 6.0, 9.0, Color(0.56, 0.56, 0.53))
	GroundKit.box(root, Vector3(36.0, 7.0, 18.0), Vector3(0.0, 3.5, -34.0), GroundKit.COL_BRICK.darkened(0.12))               # canning shed
	_drums_and_bowsers(root, Vector3(34.0, 0.0, -18.0), rng, team)
	GroundKit.box(root, Vector3(6.0, 0.3, 90.0), Vector3(0.0, 0.15, 70.0), Color(0.4, 0.38, 0.34), Vector3.ZERO, false)
	for i in 4:
		GroundKit.cyl(root, 1.4, 1.4, 10.0, Vector3(0.0, 1.9, 30.0 + float(i) * 18.0), Color(0.28, 0.28, 0.3), Vector3(90.0, 0.0, 0.0), 10)


## A single telescopic gas holder: a guide frame of lattice columns with telescoping sections inside.
static func _gasholder(root: Node3D, p: Vector3, r: float) -> void:
	var gy: float = _gh(root, p)
	# telescoping sections (a tall can, a middle and a top insert)
	GroundKit.cyl(root, r, r, 16.0, Vector3(p.x, gy + 8.0, p.z), Color(0.4, 0.42, 0.42), Vector3.ZERO, 16)
	GroundKit.cyl(root, r * 0.86, r * 0.86, 8.0, Vector3(p.x, gy + 20.0, p.z), Color(0.44, 0.46, 0.46), Vector3.ZERO, 16)
	GroundKit.cyl(root, r * 0.7, r * 0.7, 6.0, Vector3(p.x, gy + 27.0, p.z), Color(0.5, 0.52, 0.52), Vector3.ZERO, 16)
	GroundKit.cyl(root, r * 0.72, r * 0.72, 1.2, Vector3(p.x, gy + 30.6, p.z), Color(0.3, 0.3, 0.32), Vector3.ZERO, 16, false)  # crown
	# outer guide frame: 8 lattice columns + two rings of ties
	var steel: Color = Color(0.32, 0.34, 0.36)
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		var cx: float = p.x + cos(a) * (r + 1.6)
		var cz: float = p.z + sin(a) * (r + 1.6)
		GroundKit.box(root, Vector3(0.6, 34.0, 0.6), Vector3(cx, gy + 17.0, cz), steel, Vector3.ZERO, false)
	for y in [12.0, 24.0]:
		GroundKit.cyl(root, r + 1.8, r + 1.8, 0.5, Vector3(p.x, gy + y, p.z), steel.darkened(0.1), Vector3.ZERO, 16, false)
