class_name VWeaponsKit
extends RefCounted
## P11 1944 V-weapon sites: the V-1 "ski" launch sites, the V-1 storage/preparation depots, and the ground
## works around the two Pas-de-Calais "Heavy Cross" V-2 bunkers (Wizernes / La Coupole and Eperlecques /
## Kraftwerk Nord West), placed at the cited sites in data/v_weapons_1940.json. The destructible target itself
## is an existing GroundStructure("v1_site") (see WorldPopulator._build_v_weapons): the standard launch-ramp
## branch, or the big-dome branch for the two Heavy Cross bunkers. This kit builds the rest of the site - the
## curved-end "ski" buildings, the inclined launch ramp on its trestles with a V-1 on the trolley, assembly and
## non-magnetic sheds, store bunkers, light flak, the depot tunnel portals, and the approach cutting, quarry
## bench and rail spur of a Heavy Cross site. All procedural low-poly toon from GroundKit primitives - no
## photo textures, no new assets.
##
##   var n: Node3D = VWeaponsKit.build(kind, pos, heading_deg, size, team, seed_v)   # node at world ORIGIN
##
## The returned container holds a `root` at (pos.x, 0, pos.z) whose local -Z is the site front (the launch
## direction for a ski site). Deterministic from seed_v.

## The scenery kinds this kit understands (each reuses a GroundStructure("v1_site") in WorldPopulator).
static func kinds() -> Array:
	return ["ski_site", "supply_depot", "heavy_cross"]


## Central dispatch, driven by the `kind` in data/v_weapons_1940.json.
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
		"supply_depot":
			_supply_depot(root, sz, team, rng)
		"heavy_cross":
			_heavy_cross(root, sz, team, rng)
		_:
			_ski_site(root, sz, team, rng)
	return container


# ------------------------------------------------------------------ helpers
static func _gh(root: Node3D, local: Vector3) -> float:
	var w: Vector3 = root.transform * local
	return GroundKit.ground_y(w.x, w.z)


## One instance of a shared mesh (the assembly-shed T2 hangar) at a local point on the ground.
static func _inst(root: Node3D, mesh: Mesh, local: Vector3, yaw_deg: float) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(local.x, _gh(root, local), local.z)
	mi.rotation.y = deg_to_rad(yaw_deg)
	root.add_child(mi)


static func _disc(rng: RandomNumberGenerator, r_min: float, r_max: float) -> Vector2:
	var a: float = rng.randf() * TAU
	var r: float = rng.randf_range(r_min, r_max)
	return Vector2(cos(a) * r, sin(a) * r)


## A curved-end "ski" storage building: a long low box with a rounded nose, the ski shape that gave the sites
## their name. Local -Z is the nose.
static func _ski_building(root: Node3D, local: Vector3, length: float, width: float, h: float, col: Color) -> void:
	var gy: float = _gh(root, local)
	GroundKit.box(root, Vector3(width, h, length), Vector3(local.x, gy + h * 0.5, local.z), col)
	GroundKit.cyl(root, width * 0.5, width * 0.5, h, Vector3(local.x, gy + h * 0.5, local.z - length * 0.5), col.lightened(0.05), Vector3.ZERO, 12)
	GroundKit.box(root, Vector3(width + 0.4, 0.6, length * 0.92), Vector3(local.x, gy + h + 0.3, local.z + length * 0.04), col.darkened(0.28), Vector3.ZERO, false)   # flat roof lip


## The inclined launch ramp on trestles with a V-1 on its trolley (the ski-site launch ramp).
static func _launch_ramp(root: Node3D, local: Vector3, length: float) -> void:
	var gy: float = _gh(root, local)
	var conc: Color = Color(0.5, 0.49, 0.45)
	var steel: Color = Color(0.35, 0.35, 0.37)
	# the ramp: an inclined strip pitched about local X, nose at -Z
	var ramp := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(3.4, 1.4, length)
	ramp.mesh = rm
	ramp.material_override = GroundKit.mat(conc, false)
	ramp.position = Vector3(local.x, gy + 4.6, local.z)
	ramp.rotation_degrees = Vector3(-13.0, 0.0, 0.0)
	root.add_child(ramp)
	# trestle legs under the ramp
	for i in 6:
		var z: float = local.z + length * 0.42 - float(i) * (length / 6.0)
		var h: float = 2.0 + float(i) * 1.1
		GroundKit.box(root, Vector3(3.0, h, 2.2), Vector3(local.x, gy + h * 0.5, z), steel, Vector3.ZERO, false)
	# the catapult trough / piston tube down the middle
	GroundKit.box(root, Vector3(0.7, 0.7, length * 0.9), Vector3(local.x, gy + 5.4, local.z), steel.darkened(0.15), Vector3(-13.0, 0.0, 0.0), false)
	# a V-1 on its trolley near the head of the ramp
	var vy: float = gy + 6.6
	GroundKit.cyl(root, 0.55, 0.55, 7.2, Vector3(local.x, vy, local.z - length * 0.30), Color(0.62, 0.63, 0.6), Vector3(-13.0, 0.0, 0.0), 10)
	GroundKit.box(root, Vector3(5.4, 0.22, 1.3), Vector3(local.x, vy - 0.3, local.z - length * 0.30), Color(0.62, 0.63, 0.6), Vector3(-13.0, 0.0, 0.0), false)
	GroundKit.cyl(root, 0.45, 0.45, 0.5, Vector3(local.x, vy + 0.5, local.z - length * 0.30 + 3.4), GroundKit.COL_DARK, Vector3.ZERO, 8, false)   # intake
	GroundKit.box(root, Vector3(4.0, 1.0, 5.0), Vector3(local.x, gy + 1.6, local.z - length * 0.30), steel)                                        # trolley


## A small light-AA emplacement: a sandbagged ring, a gun on a pedestal and a predictor.
static func _flak(root: Node3D, local: Vector3) -> void:
	var gy: float = _gh(root, local)
	var n: int = 10
	for i in n:
		var a: float = TAU * float(i) / float(n)
		GroundKit.box(root, Vector3(2.2, 0.9, 1.0), Vector3(local.x + cos(a) * 5.0, gy + 0.45, local.z + sin(a) * 5.0), GroundKit.COL_SAND, Vector3(0.0, -rad_to_deg(a) + 90.0, 0.0), false)
	GroundKit.cyl(root, 0.9, 1.1, 1.2, Vector3(local.x, gy + 0.6, local.z), GroundKit.COL_STEEL, Vector3.ZERO, 8)
	GroundKit.cyl(root, 0.16, 0.16, 4.2, Vector3(local.x, gy + 2.4, local.z - 1.0), GroundKit.COL_DARK, Vector3(70.0, 0.0, 0.0), 6, false)
	GroundKit.box(root, Vector3(1.6, 1.0, 1.2), Vector3(local.x + 4.0, gy + 0.5, local.z + 3.0), GroundKit.COL_OLIVE, Vector3.ZERO, false)


## A concrete store bunker with an earth cover and a steel door.
static func _store_bunker(root: Node3D, local: Vector3, yaw: float) -> void:
	var gy: float = _gh(root, local)
	var h := Node3D.new()
	h.position = Vector3(local.x, gy, local.z)
	h.rotation.y = deg_to_rad(yaw)
	root.add_child(h)
	GroundKit.box(h, Vector3(11.0, 4.0, 8.0), Vector3(0.0, 2.0, 0.0), GroundKit.COL_CONCRETE)
	GroundKit.box(h, Vector3(13.0, 1.2, 10.0), Vector3(0.0, 4.4, 0.0), Color(0.34, 0.4, 0.22), Vector3.ZERO, false)   # earth cover
	GroundKit.box(h, Vector3(2.2, 2.6, 0.4), Vector3(0.0, 1.3, -4.2), GroundKit.COL_DARK, Vector3.ZERO, false)         # door


## A wooden hut line (accommodation / workshop huts).
static func _hut_line(root: Node3D, origin: Vector3, n: int, gap: float, yaw: float) -> void:
	var wood: Color = GroundKit.COL_WOOD
	for i in n:
		var p: Vector3 = origin + Vector3(float(i) * gap, 0.0, 0.0)
		var gy: float = _gh(root, p)
		var h := Node3D.new()
		h.position = Vector3(p.x, gy, p.z)
		h.rotation.y = deg_to_rad(yaw)
		root.add_child(h)
		GroundKit.box(h, Vector3(5.0, 2.6, 8.0), Vector3(0.0, 1.3, 0.0), wood)
		var pm := MeshInstance3D.new()
		pm.mesh = GroundKit.prism_mesh(5.4, 8.2, 1.2)
		pm.material_override = GroundKit.mat(wood.darkened(0.25), true)
		pm.position = Vector3(0.0, 2.6, 0.0)
		pm.rotation_degrees = Vector3(0.0, 90.0, 0.0)
		h.add_child(pm)


static func _flag(root: Node3D, local: Vector3, team: String) -> void:
	var gy: float = _gh(root, local)
	GroundKit.cyl(root, 0.15, 0.18, 10.0, Vector3(local.x, gy + 5.0, local.z), GroundKit.COL_STEEL, Vector3.ZERO, 6, false)
	GroundKit.box(root, Vector3(2.8, 1.6, 0.1), Vector3(local.x + 1.4, gy + 9.0, local.z), Color(0.75, 0.15, 0.13) if team == "Allies" else Color(0.55, 0.55, 0.55), Vector3.ZERO, false)


# ------------------------------------------------------------------ kinds
## A 1944 V-1 "ski site": the curved-end ski storage buildings, the launch ramp with a V-1, an assembly shed
## (a T2 hangar), a non-magnetic building, a store bunker, light flak and a hut line, set on a hardstanding.
static func _ski_site(root: Node3D, size: int, team: String, rng: RandomNumberGenerator) -> void:
	var conc: Color = Color(0.5, 0.49, 0.45)
	var camo: Color = Color(0.34, 0.4, 0.24)
	GroundKit.box(root, Vector3(160.0, 0.25, 120.0), Vector3(0.0, _gh(root, Vector3.ZERO) + 0.12, -10.0), Color(0.42, 0.4, 0.38), Vector3.ZERO, false)   # hardstanding
	# three curved-end ski buildings along the +Z (rear) edge
	for i in 3:
		_ski_building(root, Vector3(-60.0 + float(i) * 44.0, 0.0, 44.0), 70.0, 16.0, 5.5, camo.darkened(0.04 if i % 2 == 0 else 0.1))
	# the launch ramp towards -Z (the front)
	_launch_ramp(root, Vector3(0.0, 0.0, -30.0), 70.0)
	# assembly shed (T2 hangar) and a couple of small sheds
	_inst(root, AirfieldAssets.t2_hangar(team), Vector3(-64.0, 0.0, -46.0), 0.0)
	GroundKit.box(root, Vector3(14.0, 4.0, 10.0), Vector3(70.0, _gh(root, Vector3(70.0, 0.0, 20.0)) + 2.0, 20.0), conc, Vector3.ZERO, false)          # non-magnetic building
	GroundKit.box(root, Vector3(12.0, 4.0, 9.0), Vector3(70.0, _gh(root, Vector3(70.0, 0.0, 40.0)) + 2.0, 40.0), camo, Vector3.ZERO, false)
	_store_bunker(root, Vector3(60.0, 0.0, -50.0), 0.0)
	_flak(root, Vector3(-84.0, 0.0, -60.0))
	if size >= 2:
		_flak(root, Vector3(84.0, 0.0, -60.0))
	_hut_line(root, Vector3(-30.0, 0.0, 78.0), 2 + size, 12.0, 0.0)
	_flag(root, Vector3(rng.randf_range(-20.0, 20.0), 0.0, 92.0), team)


## A V-1 storage / preparation depot: a mound with concrete tunnel portals, a rail spur with wagons, an
## assembly shed and hardstandings.
static func _supply_depot(root: Node3D, size: int, team: String, rng: RandomNumberGenerator) -> void:
	var conc: Color = Color(0.48, 0.47, 0.43)
	# the mound the tunnels run into
	GroundKit.box(root, Vector3(200.0, 16.0, 90.0), Vector3(0.0, _gh(root, Vector3.ZERO) + 6.0, 60.0), Color(0.34, 0.32, 0.2))
	GroundKit.sphere(root, 30.0, Vector3(-70.0, _gh(root, Vector3(-70.0, 0.0, 60.0)) + 8.0, 60.0), Color(0.36, 0.4, 0.24), Vector3(1.0, 0.6, 1.0), false)
	# tunnel portals into the mound face
	for i in 2 + size:
		var x: float = -50.0 + float(i) * 36.0
		var gy: float = _gh(root, Vector3(x, 0.0, 15.0))
		GroundKit.box(root, Vector3(12.0, 9.0, 4.0), Vector3(x, gy + 4.5, 15.0), conc)
		GroundKit.box(root, Vector3(5.0, 5.5, 1.4), Vector3(x, gy + 2.75, 13.4), GroundKit.COL_DARK, Vector3.ZERO, false)
	# a rail spur with a few covered wagons
	GroundKit.box(root, Vector3(6.0, 0.3, 150.0), Vector3(60.0, _gh(root, Vector3(60.0, 0.0, 0.0)) + 0.15, -20.0), Color(0.4, 0.38, 0.34), Vector3.ZERO, false)
	for i in 4:
		var wz: float = -60.0 + float(i) * 26.0
		GroundKit.box(root, Vector3(3.4, 3.0, 9.0), Vector3(60.0, _gh(root, Vector3(60.0, 0.0, wz)) + 1.6, wz), Color(0.3, 0.26, 0.2))
		GroundKit.box(root, Vector3(3.0, 0.5, 8.2), Vector3(60.0, _gh(root, Vector3(60.0, 0.0, wz)) + 3.3, wz), Color(0.16, 0.14, 0.12), Vector3.ZERO, false)
	_shed(root, Vector3(-40.0, 0.0, -50.0), 70.0, 30.0, 9.0, 3)
	_hut_line(root, Vector3(-80.0, 0.0, -80.0), 3, 14.0, 0.0)
	_flak(root, Vector3(90.0, 0.0, 40.0))
	_flag(root, Vector3(rng.randf_range(-15.0, 15.0), 0.0, -80.0), team)


## A heavy multi-bay shed (used by a depot for assembly / stores).
static func _shed(root: Node3D, local: Vector3, w: float, d: float, h: float, bays: int) -> void:
	var brick: Color = GroundKit.COL_BRICK.darkened(0.12)
	var gy: float = _gh(root, local)
	GroundKit.box(root, Vector3(w, h, d), Vector3(local.x, gy + h * 0.5, local.z), brick)
	var nb: int = maxi(bays, 1)
	for i in nb:
		var bx: float = local.x - w * 0.5 + (float(i) + 0.5) * (w / float(nb))
		var pm := MeshInstance3D.new()
		pm.mesh = GroundKit.prism_mesh(d * 0.7, w / float(nb) * 0.8, 2.0)
		pm.material_override = GroundKit.mat(brick.darkened(0.22), true)
		pm.position = Vector3(bx, gy + h, local.z)
		pm.rotation_degrees = Vector3(0.0, 90.0, 0.0)
		root.add_child(pm)


## The ground works around a Heavy Cross V-2 bunker: the approach cutting and quarry bench the giant dome
## (GroundStructure("v1_site") variant "dome") sits in, a rail spur with wagons, a power house, a store and
## light flak. The dome itself is the target structure, not built here.
static func _heavy_cross(root: Node3D, size: int, team: String, rng: RandomNumberGenerator) -> void:
	var stone: Color = Color(0.5, 0.48, 0.44)
	var conc: Color = GroundKit.COL_CONCRETE
	# the quarry face / chalk bench behind the dome (local +Z is the back of the site)
	GroundKit.box(root, Vector3(190.0, 60.0, 60.0), Vector3(0.0, _gh(root, Vector3.ZERO) + 20.0, 120.0), stone.darkened(0.06))
	GroundKit.box(root, Vector3(210.0, 8.0, 30.0), Vector3(0.0, _gh(root, Vector3.ZERO) + 50.0, 108.0), Color(0.36, 0.4, 0.24), Vector3.ZERO, false)   # vegetated top
	# the approach cutting sweeping round to the dome at the front (-Z)
	for sx in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(16.0, 20.0, 120.0), Vector3(sx * 95.0, _gh(root, Vector3(sx * 95.0, 0.0, -20.0)) + 8.0, -20.0), stone, Vector3.ZERO, false)
	GroundKit.box(root, Vector3(180.0, 0.4, 120.0), Vector3(0.0, _gh(root, Vector3.ZERO) + 0.2, -30.0), Color(0.42, 0.4, 0.37), Vector3.ZERO, false)       # cutting floor
	# rail spur with covered wagons bringing the rockets up
	GroundKit.box(root, Vector3(6.0, 0.3, 220.0), Vector3(-70.0, _gh(root, Vector3(-70.0, 0.0, 0.0)) + 0.15, -60.0), Color(0.4, 0.38, 0.34), Vector3.ZERO, false)
	for i in 4:
		var wz: float = -140.0 + float(i) * 26.0
		GroundKit.box(root, Vector3(3.4, 3.0, 9.0), Vector3(-70.0, _gh(root, Vector3(-70.0, 0.0, wz)) + 1.6, wz), Color(0.3, 0.26, 0.2))
	# power house, store and the mixing plant (the site was a colossal concrete pour)
	GroundKit.box(root, Vector3(30.0, 9.0, 18.0), Vector3(88.0, _gh(root, Vector3(88.0, 0.0, 40.0)) + 4.5, 40.0), conc)
	GroundKit.cyl(root, 1.4, 1.9, 30.0, Vector3(105.0, _gh(root, Vector3(105.0, 0.0, 40.0)) + 15.0, 40.0), GroundKit.COL_BRICK.darkened(0.05), Vector3.ZERO, 10)
	_store_bunker(root, Vector3(-96.0, 0.0, -40.0), 90.0)
	GroundKit.box(root, Vector3(40.0, 12.0, 24.0), Vector3(60.0, _gh(root, Vector3(60.0, 0.0, 90.0)) + 6.0, 90.0), Color(0.5, 0.49, 0.46))              # batching plant
	_flak(root, Vector3(0.0, 0.0, -110.0))
	if size >= 3:
		_flak(root, Vector3(-90.0, 0.0, -110.0))
	_flag(root, Vector3(rng.randf_range(-20.0, 20.0), 0.0, -90.0), team)
