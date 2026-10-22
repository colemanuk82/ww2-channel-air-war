class_name AircraftIndustryKit
extends RefCounted
## P10 1940 aircraft industry: the real plants and shadow factories (and a few dispersed production / storage
## sites) placed at the cited sites in data/aircraft_industry_1940.json. The destructible industrial target
## itself is an existing GroundStructure("factory") (see WorldPopulator._build_aircraft_industry); this kit
## builds the works AROUND it - long multi-bay assembly sheds and flight sheds (reusing the shared
## AirfieldAssets T2/T1 hangar meshes), dispersal / blast pens with dummy aircraft, machine shops, a foundry and
## test-bed cells, chimneys, water tower and a works flag. All procedural low-poly toon from GroundKit
## primitives (plus the shared AirfieldAssets hangar / revetment / dummy-aircraft meshes) - no photo textures.
##
##   var n: Node3D = AircraftIndustryKit.build(kind, pos, heading_deg, size, team, seed_v)   # node at ORIGIN
##
## The returned container holds a `root` at (pos.x, 0, pos.z) whose local -Z is the site front (the WorldFeatures
## / GroundStructure convention). Deterministic from seed_v.

## The scenery kinds this kit understands (mapped to the destructible kind in WorldPopulator._build_aircraft_industry).
static func kinds() -> Array:
	return ["shadow_factory", "assembly_plant", "engine_works", "dispersal_site", "aircraft_depot"]


## Central dispatch, driven by the `kind` in data/aircraft_industry_1940.json.
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
		"shadow_factory":
			_shadow_factory(root, sz, team, rng)
		"engine_works":
			_engine_works(root, sz, rng)
		"dispersal_site":
			_dispersal_site(root, sz, team, rng)
		"aircraft_depot":
			_aircraft_depot(root, sz, team, rng)
		_:
			_assembly_plant(root, sz, team, rng)
	return container


# ------------------------------------------------------------------ helpers
## Terrain height at a local point of `root` (root is at the world origin's XZ with a yaw, as OilFuelKit).
static func _gh(root: Node3D, local: Vector3) -> float:
	var w: Vector3 = root.transform * local
	return GroundKit.ground_y(w.x, w.z)


## One instance of a shared mesh (a hangar / revetment / dummy aircraft) at a local point on the ground.
static func _inst(root: Node3D, mesh: Mesh, local: Vector3, yaw_deg: float) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(local.x, _gh(root, local), local.z)
	mi.rotation.y = deg_to_rad(yaw_deg)
	root.add_child(mi)


## A long multi-bay assembly shed: a box with a row of roof monitors and (optionally) a dark door front on -Z.
static func _shed(root: Node3D, local: Vector3, w: float, d: float, h: float, bays: int, brick: Color, door: bool) -> void:
	var gy: float = _gh(root, local)
	GroundKit.box(root, Vector3(w, h, d), Vector3(local.x, gy + h * 0.5, local.z), brick)
	var nb: int = maxi(bays, 1)
	for i in nb:
		var bx: float = local.x - w * 0.5 + (float(i) + 0.5) * (w / float(nb))
		var pm := MeshInstance3D.new()
		pm.mesh = GroundKit.prism_mesh(d * 0.7, w / float(nb) * 0.8, 2.4)
		pm.material_override = GroundKit.mat(brick.darkened(0.22), true)
		pm.position = Vector3(bx, gy + h, local.z)
		pm.rotation_degrees = Vector3(0.0, 90.0, 0.0)
		root.add_child(pm)
	if door:
		GroundKit.box(root, Vector3(w * 0.86, h * 0.8, 0.6), Vector3(local.x, gy + h * 0.4, local.z - d * 0.5), GroundKit.COL_DARK, Vector3.ZERO, false)


## A rank of dispersal / blast pens: a three-sided revetment arc with a dummy aircraft in each pen.
static func _pens(root: Node3D, origin: Vector3, n: int, gap: float, yaw: float, team: String) -> void:
	var rev: Mesh = AirfieldAssets.revetment(team)
	var ac: Mesh = AirfieldAssets.dummy_aircraft(team)
	for i in n:
		var p: Vector3 = origin + Vector3(float(i) * gap, 0.0, 0.0)
		for a in 3:
			var ang: float = yaw + 120.0 * float(a)
			var rad: float = deg_to_rad(ang)
			_inst(root, rev, p + Vector3(cos(rad) * 12.0, 0.0, sin(rad) * 12.0), ang + 90.0)
		_inst(root, ac, p, yaw + float(i % 2) * 10.0 - 5.0)


## A works flag mast so a site reads as owned by one side.
static func _flag(root: Node3D, local: Vector3, team: String) -> void:
	var gy: float = _gh(root, local)
	GroundKit.cyl(root, 0.15, 0.18, 10.0, Vector3(local.x, gy + 5.0, local.z), GroundKit.COL_STEEL, Vector3.ZERO, 6, false)
	GroundKit.box(root, Vector3(2.8, 1.6, 0.1), Vector3(local.x + 1.4, gy + 9.0, local.z), Color(0.75, 0.15, 0.13) if team == "Allies" else Color(0.55, 0.55, 0.55), Vector3.ZERO, false)


## A water tower / chimney pair shared by the works kinds.
static func _tower(root: Node3D, local: Vector3, chimney: bool) -> void:
	var gy: float = _gh(root, local)
	if chimney:
		GroundKit.cyl(root, 1.6, 2.2, 42.0, Vector3(local.x, gy + 21.0, local.z), GroundKit.COL_BRICK.darkened(0.05), Vector3.ZERO, 10)
		GroundKit.cyl(root, 1.8, 1.8, 1.4, Vector3(local.x, gy + 42.5, local.z), Color(0.8, 0.8, 0.75), Vector3.ZERO, 10, false)
	else:
		GroundKit.cyl(root, 0.6, 0.8, 12.0, Vector3(local.x, gy + 6.0, local.z), GroundKit.COL_STEEL, Vector3.ZERO, 8)
		GroundKit.cyl(root, 4.0, 4.0, 5.0, Vector3(local.x, gy + 14.5, local.z), Color(0.55, 0.56, 0.53), Vector3.ZERO, 12)
		GroundKit.cyl(root, 4.2, 4.2, 0.6, Vector3(local.x, gy + 17.3, local.z), Color(0.3, 0.3, 0.32), Vector3.ZERO, 12, false)


# ------------------------------------------------------------------ kinds
## A final-assembly plant / aircraft factory: a big multi-bay assembly shed, a wide-doored flight shed (a T2
## hangar), an apron with dispersal pens, a boiler house with a chimney and a water tower.
static func _assembly_plant(root: Node3D, size: int, team: String, rng: RandomNumberGenerator) -> void:
	var brick: Color = GroundKit.COL_BRICK.darkened(0.1)
	_shed(root, Vector3(-10.0, 0.0, 30.0), 150.0 + 20.0 * float(size), 56.0, 14.0, 5 + size, brick, true)
	_tower(root, Vector3(70.0, 0.0, 6.0), true)
	_tower(root, Vector3(-95.0, 0.0, 8.0), false)
	var t2: Mesh = AirfieldAssets.t2_hangar(team)
	for i in 2 + size:
		_inst(root, t2, Vector3(-70.0 + float(i) * 70.0, 0.0, -40.0), 0.0)
	GroundKit.box(root, Vector3(240.0, 0.3, 90.0), Vector3(0.0, _gh(root, Vector3.ZERO) + 0.15, -35.0), Color(0.4, 0.4, 0.38), Vector3.ZERO, false)   # apron
	_pens(root, Vector3(-60.0, 0.0, -95.0), 4 + size, 40.0, 0.0, team)
	_flag(root, Vector3(rng.randf_range(-30.0, 30.0), 0.0, 90.0), team)


## A government shadow factory: two long assembly sheds with roof monitors and two flight sheds, an apron with
## pens, a power house with chimneys and a works flag - the Castle Bromwich / Longbridge silhouette.
static func _shadow_factory(root: Node3D, size: int, team: String, rng: RandomNumberGenerator) -> void:
	var brick: Color = GroundKit.COL_BRICK.darkened(0.08)
	_shed(root, Vector3(0.0, 0.0, 46.0), 210.0, 46.0, 13.0, 7, brick, true)
	_shed(root, Vector3(0.0, 0.0, 96.0), 210.0, 40.0, 12.0, 7, brick.lightened(0.04), false)
	_tower(root, Vector3(95.0, 0.0, 20.0), true)
	_tower(root, Vector3(110.0, 0.0, 20.0), true)
	_tower(root, Vector3(-110.0, 0.0, 12.0), false)
	var t2: Mesh = AirfieldAssets.t2_hangar(team)
	var t1: Mesh = AirfieldAssets.t1_hangar(team)
	for i in 2 + size:
		_inst(root, t2, Vector3(-80.0 + float(i) * 80.0, 0.0, -46.0), 0.0)
	_inst(root, t1, Vector3(120.0, 0.0, -70.0), 90.0)
	GroundKit.box(root, Vector3(320.0, 0.3, 120.0), Vector3(0.0, _gh(root, Vector3.ZERO) + 0.15, -30.0), Color(0.4, 0.4, 0.38), Vector3.ZERO, false)   # apron
	_pens(root, Vector3(-90.0, 0.0, -120.0), 5 + size, 44.0, 0.0, team)
	_flag(root, Vector3(rng.randf_range(-40.0, 40.0), 0.0, 130.0), team)


## An aero-engine works: machine shops, a foundry block with chimneys, open-air test-bed cells and a water tower.
static func _engine_works(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var brick: Color = GroundKit.COL_BRICK.darkened(0.12)
	_shed(root, Vector3(0.0, 0.0, 40.0), 120.0, 44.0, 12.0, 4 + size, brick, true)                # machine shop
	_shed(root, Vector3(0.0, 0.0, 92.0), 100.0, 34.0, 11.0, 4, brick.lightened(0.05), false)        # erecting shop
	_tower(root, Vector3(60.0, 0.0, 4.0), true)
	_tower(root, Vector3(74.0, 0.0, 4.0), true)
	_tower(root, Vector3(-70.0, 0.0, 8.0), false)
	# open-air test-bed cells: blast walls with a stand and a chimney each
	for i in 2 + size:
		var z: float = -20.0 - float(i) * 30.0
		GroundKit.box(root, Vector3(18.0, 5.0, 16.0), Vector3(-70.0, _gh(root, Vector3(-70.0, 0.0, z)) + 2.5, z), Color(0.34, 0.29, 0.2))   # earth blast wall
		GroundKit.box(root, Vector3(6.0, 4.0, 6.0), Vector3(-70.0, _gh(root, Vector3(-70.0, 0.0, z)) + 2.0, z), GroundKit.COL_STEEL)          # test stand
		GroundKit.cyl(root, 0.9, 1.2, 14.0, Vector3(-84.0, _gh(root, Vector3(-84.0, 0.0, z)) + 7.0, z), GroundKit.COL_STEEL.darkened(0.1), Vector3.ZERO, 8)
	_flag(root, Vector3(rng.randf_range(-30.0, 30.0), 0.0, 120.0), "Allies")


## A dispersed production / satellite site: small scattered sheds among the hedgerows, camouflage poles with
## netting, and a pair of revetted hardstandings for aircraft.
static func _dispersal_site(root: Node3D, size: int, team: String, rng: RandomNumberGenerator) -> void:
	var camo: Color = Color(0.34, 0.4, 0.24)
	var wood: Color = GroundKit.COL_WOOD
	var ute: Color = Color(0.4, 0.4, 0.34)
	for i in 3 + size * 2:
		var d: Vector2 = _disc(rng, 40.0, 130.0)
		var gy: float = _gh(root, Vector3(d.x, 0.0, d.y))
		GroundKit.box(root, Vector3(24.0, 6.0, 12.0), Vector3(d.x, gy + 3.0, d.y), ute if i % 2 == 0 else camo.darkened(0.05))
		var pm := MeshInstance3D.new()
		pm.mesh = GroundKit.prism_mesh(12.6, 24.6, 2.4)
		pm.material_override = GroundKit.mat(camo, true)
		pm.position = Vector3(d.x, gy + 6.0, d.y)
		pm.rotation_degrees = Vector3(0.0, 90.0, 0.0)
		root.add_child(pm)
	# camouflage netting over a hardstanding: poles carrying a flat net panel
	for i in 4:
		var d2: Vector2 = _disc(rng, 55.0, 150.0)
		var gy2: float = _gh(root, Vector3(d2.x, 0.0, d2.y))
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				GroundKit.cyl(root, 0.2, 0.24, 6.0, Vector3(d2.x + sx * 9.0, gy2 + 3.0, d2.y + sz * 12.0), wood, Vector3.ZERO, 5, false)
		GroundKit.box(root, Vector3(20.0, 0.2, 26.0), Vector3(d2.x, gy2 + 6.0, d2.y), camo, Vector3.ZERO, false)
	_pens(root, Vector3(-40.0, 0.0, 60.0), 2 + size, 44.0, 0.0, team)
	_flag(root, Vector3(0.0, 0.0, -60.0), team)


## A storage / maintenance depot: rows of T2/T1 hangars, revetment pens holding parked aircraft, stores and a
## water tower - the Kemble Maintenance-Unit silhouette.
static func _aircraft_depot(root: Node3D, size: int, team: String, rng: RandomNumberGenerator) -> void:
	var brick: Color = GroundKit.COL_BRICK.darkened(0.12)
	var t2: Mesh = AirfieldAssets.t2_hangar(team)
	var t1: Mesh = AirfieldAssets.t1_hangar(team)
	for row in 2:
		for i in 2 + size:
			_inst(root, t2, Vector3(-70.0 + float(i) * 80.0, 0.0, 30.0 + float(row) * 120.0), 0.0)
	_inst(root, t1, Vector3(-110.0, 0.0, -40.0), 0.0)
	_inst(root, t1, Vector3(110.0, 0.0, -40.0), 0.0)
	_shed(root, Vector3(0.0, 0.0, 90.0), 90.0, 30.0, 9.0, 3, brick, false)                      # stores
	_pens(root, Vector3(-90.0, 0.0, -110.0), 4 + size, 46.0, 0.0, team)
	_pens(root, Vector3(-90.0, 0.0, -170.0), 4 + size, 46.0, 180.0, team)
	_tower(root, Vector3(0.0, 0.0, 150.0), false)
	_flag(root, Vector3(0.0, 0.0, 190.0), team)


## A local disc point (a small helper so scattered pieces stay deterministic from the caller's rng).
static func _disc(rng: RandomNumberGenerator, r_min: float, r_max: float) -> Vector2:
	var a: float = rng.randf() * TAU
	var r: float = rng.randf_range(r_min, r_max)
	return Vector2(cos(a) * r, sin(a) * r)
