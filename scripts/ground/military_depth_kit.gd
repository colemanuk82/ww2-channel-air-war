class_name MilitaryDepthKit
extends RefCounted
## P19 military depth: the 1940 transit / embarkation camps, ammunition depots, vehicle parks, horse-drawn
## transport columns and tank trains, from data/military_depth_1940.json. 1940 is far more horse than truck, so
## the horse column is a real part of the texture. All procedural low-poly toon from GroundKit primitives plus
## the shared AirfieldAssets nissen / tent / truck meshes - no photo textures, no new assets.
##
##   var n: Node3D = MilitaryDepthKit.build(kind, pos, heading_deg, size, seed_v)   # node sits at world ORIGIN
##
## The returned container holds a `root` at (pos.x, ground_y, pos.z) rotated so local -Z faces the site's
## heading (the WorldFeatures / GroundStructure convention). Deterministic from seed_v. Driven from
## data/military_depth_1940.json by WorldPopulator._register_military_depth().

## The military-depth kinds this kit understands.
static func kinds() -> Array:
	return ["transit_camp", "ammunition_depot", "vehicle_park", "horse_column", "tank_train"]


static func build(kind: String, pos: Vector3, heading_deg: float, size: int, seed_v: int) -> Node3D:
	var container := Node3D.new()
	var root := Node3D.new()
	root.position = Vector3(pos.x, GroundKit.ground_y(pos.x, pos.z), pos.z)
	root.rotation.y = -deg_to_rad(heading_deg)
	container.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var sz: int = clampi(size, 1, 3)
	match kind:
		"ammunition_depot":
			_ammunition_depot(root, sz, rng)
		"vehicle_park":
			_vehicle_park(root, sz, rng)
		"horse_column":
			_horse_column(root, sz, rng)
		"tank_train":
			_tank_train(root, sz, rng)
		"army_camp":
			_army_camp(root, sz, rng)
		_:
			_transit_camp(root, sz, rng)
	return container


# ------------------------------------------------------------------ helpers
## Terrain height at a local point of `root` (root is at the world origin's XZ with a yaw).
static func _gh(root: Node3D, local: Vector3) -> float:
	var w: Vector3 = root.transform * local
	return GroundKit.ground_y(w.x, w.z)


## One instance of a shared mesh (a Nissen hut / tent / lorry) at a local point on the ground.
static func _inst(root: Node3D, mesh: Mesh, local: Vector3, yaw_deg: float) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(local.x, _gh(root, local), local.z)
	mi.rotation.y = deg_to_rad(yaw_deg)
	root.add_child(mi)


## A low-poly tank (hull, two tracks, turret and gun), nose at local -Z.
static func _tank(root: Node3D, local: Vector3, yaw_deg: float) -> void:
	var gy: float = _gh(root, local)
	var h := Node3D.new()
	h.position = Vector3(local.x, gy, local.z)
	h.rotation.y = deg_to_rad(yaw_deg)
	root.add_child(h)
	var paint: Color = Color(0.3, 0.33, 0.24)
	GroundKit.box(h, Vector3(2.6, 1.3, 5.6), Vector3(0, 1.15, 0), paint)                                        # hull
	for sx in [-1.0, 1.0]:
		GroundKit.box(h, Vector3(0.8, 1.0, 5.9), Vector3(sx * 1.5, 0.55, 0), Color(0.14, 0.14, 0.14))            # track
	GroundKit.cyl(h, 1.1, 1.1, 1.1, Vector3(0, 2.35, 0.3), paint.lightened(0.05), Vector3.ZERO, 10)            # turret
	GroundKit.cyl(h, 0.16, 0.2, 3.6, Vector3(0, 2.4, -1.8), Color(0.2, 0.2, 0.2), Vector3(90, 0, 0), 6, false)  # gun


## A horse-drawn General Service wagon (or limber): a bed on four wheels with a canvas tilt.
static func _wagon(root: Node3D, local: Vector3, yaw_deg: float) -> void:
	var gy: float = _gh(root, local)
	var h := Node3D.new()
	h.position = Vector3(local.x, gy, local.z)
	h.rotation.y = deg_to_rad(yaw_deg)
	root.add_child(h)
	var wood: Color = Color(0.42, 0.33, 0.2)
	GroundKit.box(h, Vector3(2.2, 0.4, 4.2), Vector3(0, 1.1, 0), wood)
	GroundKit.box(h, Vector3(2.3, 0.6, 4.2), Vector3(0, 1.5, 0), Color(0.34, 0.3, 0.22), Vector3.ZERO, false)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			GroundKit.cyl(h, 0.55, 0.55, 0.25, Vector3(sx * 1.2, 0.55, sz * 1.5), Color(0.3, 0.22, 0.14), Vector3(0, 0, 90), 8, false)


## A draught horse (body, four legs, neck and head), facing local -Z.
static func _horse(root: Node3D, local: Vector3, yaw_deg: float) -> void:
	var gy: float = _gh(root, local)
	var h := Node3D.new()
	h.position = Vector3(local.x, gy, local.z)
	h.rotation.y = deg_to_rad(yaw_deg)
	root.add_child(h)
	var coat: Color = Color(0.32, 0.24, 0.16)
	GroundKit.box(h, Vector3(0.7, 0.9, 2.0), Vector3(0, 1.55, 0), coat)                                       # body
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			GroundKit.cyl(h, 0.1, 0.12, 1.1, Vector3(sx * 0.26, 0.55, sz * 0.7), coat.darkened(0.12), Vector3.ZERO, 5, false)   # legs
	GroundKit.box(h, Vector3(0.32, 1.0, 0.6), Vector3(0, 2.1, -0.85), coat)                                    # neck
	GroundKit.box(h, Vector3(0.3, 0.4, 0.8), Vector3(0, 2.6, -1.25), coat.darkened(0.06))                      # head
	GroundKit.cyl(h, 0.06, 0.08, 0.8, Vector3(0, 1.9, 1.2), Color(0.14, 0.12, 0.1), Vector3(-30, 0, 0), 4, false)           # tail


## A short length of rail track (two rails on sleepers) along local X at local z.
static func _track(root: Node3D, length: float, z: float) -> void:
	var gy: float = _gh(root, Vector3(0.0, 0.0, z))
	for sx in [-0.75, 0.75]:
		GroundKit.box(root, Vector3(length, 0.25, 0.18), Vector3(0.0, gy + 0.35, z + sx), Color(0.32, 0.3, 0.28), Vector3.ZERO, false)
	var n: int = int(length / 2.6)
	for i in n:
		GroundKit.box(root, Vector3(0.5, 0.2, 2.0), Vector3(-length * 0.5 + (float(i) + 0.5) * (length / float(n)), gy + 0.15, z), Color(0.36, 0.3, 0.24), Vector3.ZERO, false)


## A covered goods wagon (a box on a rail flat) along local X at local z.
static func _rail_wagon(root: Node3D, x: float, z: float, col: Color) -> void:
	var gy: float = _gh(root, Vector3(x, 0.0, z))
	GroundKit.box(root, Vector3(9.0, 3.0, 2.6), Vector3(x, gy + 2.1, z), col)
	GroundKit.box(root, Vector3(9.4, 0.4, 2.9), Vector3(x, gy + 3.7, z), col.darkened(0.3), Vector3.ZERO, false)
	for wx in [-3.0, 3.0]:
		GroundKit.cyl(root, 0.4, 0.4, 0.4, Vector3(x + wx, gy + 0.5, z + 1.4), Color(0.1, 0.1, 0.1), Vector3(90, 0, 0), 6, false)


## An army camp: a long brick barracks block on each row, bell-tent lines on the south side, a cookhouse and a
## flagpole on the parade square. The 1940 garrison camps (Aldershot, Colchester, Lydd and the German camps round
## Saint-Omer).
static func _army_camp(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var conc: Color = GroundKit.COL_CONCRETE
	GroundKit.box(root, Vector3(170.0, 0.3, 100.0), Vector3(0.0, _gh(root, Vector3.ZERO) + 0.15, 0.0), conc.darkened(0.15), Vector3.ZERO, false)
	# barracks blocks along the north edge: brick walls under a dark roof slab
	var brick := Color(0.55, 0.42, 0.34)
	for i in 2 + size:
		var bx: float = -56.0 + float(i) * 28.0
		var by: float = _gh(root, Vector3(bx, 0.0, -28.0))
		GroundKit.box(root, Vector3(22.0, 4.5, 9.0), Vector3(bx, by + 2.25, -28.0), brick)
		GroundKit.box(root, Vector3(24.0, 1.0, 11.0), Vector3(bx, by + 5.0, -28.0), Color(0.34, 0.3, 0.27))
	# bell-tent lines on the south side
	var tent: Mesh = AirfieldAssets.tent("Allies")
	for row in 2:
		for i in 6 + size * 2:
			_inst(root, tent, Vector3(-72.0 + float(i) * 6.5, 0.0, 16.0 + float(row) * 11.0), rng.randf_range(-0.08, 0.08))
	# cookhouse and a flagpole on the parade square
	var ck: Vector3 = Vector3(58.0, 0.0, 34.0)
	GroundKit.box(root, Vector3(14.0, 3.6, 8.0), Vector3(ck.x, _gh(root, ck) + 1.8, ck.z), Color(0.6, 0.58, 0.5))
	var fp: Vector3 = Vector3(0.0, 0.0, 40.0)
	GroundKit.cyl(root, 0.15, 0.18, 9.0, Vector3(fp.x, _gh(root, fp) + 4.5, fp.z), GroundKit.COL_WOOD, Vector3.ZERO, 5, false)


# ------------------------------------------------------------------ kinds
## A transit / embarkation camp: Nissen-hut and tent lines, a rail siding with wagons, a staging area and a
## guard post - the 1940 transit and marshalling camps.
static func _transit_camp(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var conc: Color = GroundKit.COL_CONCRETE
	# staging area (a hardstanding slab)
	GroundKit.box(root, Vector3(120.0, 0.3, 70.0), Vector3(0.0, _gh(root, Vector3.ZERO) + 0.15, 0.0), conc.darkened(0.1), Vector3.ZERO, false)
	# a rail siding with covered wagons along the camp
	_track(root, 200.0 + 30.0 * float(size), -46.0)
	for i in 3 + size:
		_rail_wagon(root, -70.0 + float(i) * 26.0, -46.0, Color(0.36, 0.28, 0.2) if i % 2 == 0 else Color(0.32, 0.3, 0.26))
	# hut lines and tent lines
	var nis: Mesh = AirfieldAssets.nissen("Allies")
	for row in 2:
		for i in 3 + size:
			_inst(root, nis, Vector3(-54.0 + float(i) * 16.0, 0.0, 20.0 + float(row) * 24.0), PI * 0.5)
	var tent: Mesh = AirfieldAssets.tent("Allies")
	for row in 2:
		for i in 5 + size:
			_inst(root, tent, Vector3(-70.0 + float(i) * 7.0, 0.0, 66.0 + float(row) * 9.0), rng.randf_range(-0.1, 0.1))
	# an ablution block, a stores shed and a guard post at the gate
	GroundKit.box(root, Vector3(14.0, 4.0, 8.0), Vector3(50.0, _gh(root, Vector3(50.0, 0.0, 36.0)) + 2.0, 36.0), Color(0.6, 0.58, 0.5))
	GroundKit.box(root, Vector3(22.0, 5.0, 10.0), Vector3(-70.0, _gh(root, Vector3(-70.0, 0.0, 36.0)) + 2.5, 36.0), Color(0.5, 0.42, 0.32))
	GroundKit.box(root, Vector3(4.0, 3.2, 4.0), Vector3(0.0, _gh(root, Vector3(0.0, 0.0, 44.0)) + 1.6, 44.0), Color(0.44, 0.4, 0.28))
	GroundKit.cyl(root, 0.15, 0.18, 9.0, Vector3(0.0, _gh(root, Vector3(0.0, 0.0, 44.0)) + 4.5, 44.0), GroundKit.COL_WOOD, Vector3.ZERO, 5, false)


## An ammunition depot: earth-banked magazines in rows, a store shed, a rail siding and a perimeter fence.
static func _ammunition_depot(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var earth: Color = Color(0.34, 0.29, 0.2)
	var brick: Color = GroundKit.COL_BRICK.darkened(0.12)
	# rows of earth-banked magazines
	for row in 2 + size:
		for i in 3 + size:
			var mx: float = -40.0 + float(i) * 30.0
			var mz: float = -40.0 + float(row) * 34.0
			var gy: float = _gh(root, Vector3(mx, 0.0, mz))
			GroundKit.box(root, Vector3(14.0, 3.2, 9.0), Vector3(mx, gy + 1.6, mz), brick)
			GroundKit.box(root, Vector3(16.4, 2.6, 11.4), Vector3(mx, gy + 2.6, mz), earth)                     # earth over-roof
			GroundKit.box(root, Vector3(3.0, 2.6, 1.0), Vector3(mx, gy + 1.3, mz - 5.0), earth.darkened(0.1))    # traverse/isolation
	# store shed and a rail siding
	GroundKit.box(root, Vector3(30.0, 6.0, 14.0), Vector3(0.0, _gh(root, Vector3(0.0, 0.0, 46.0)) + 3.0, 46.0), brick)
	var pr := MeshInstance3D.new()
	pr.mesh = GroundKit.prism_mesh(15.0, 31.0, 3.0)
	pr.material_override = GroundKit.mat(Color(0.3, 0.3, 0.32), true)
	pr.position = Vector3(0.0, _gh(root, Vector3(0.0, 0.0, 46.0)) + 6.0, 46.0)
	pr.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	root.add_child(pr)
	_track(root, 160.0, 62.0)
	for i in 2 + size:
		_rail_wagon(root, -60.0 + float(i) * 26.0, 62.0, Color(0.32, 0.3, 0.26))
	# perimeter fence (posts + a wire line) around the depot
	var w: float = 140.0
	var d: float = 120.0
	for side in 4:
		var length: float = w if side < 2 else d
		var n: int = int(length / 12.0)
		for i in n:
			var t: float = (float(i) + 0.5) / float(n) - 0.5
			var lx: float
			var lz: float
			if side == 0:
				lx = t * w
				lz = -d * 0.5
			elif side == 1:
				lx = t * w
				lz = d * 0.5
			elif side == 2:
				lx = -w * 0.5
				lz = t * d
			else:
				lx = w * 0.5
				lz = t * d
			GroundKit.cyl(root, 0.12, 0.14, 2.6, Vector3(lx, _gh(root, Vector3(lx, 0.0, lz)) + 1.3, lz), GroundKit.COL_WOOD, Vector3.ZERO, 4, false)


## A vehicle park: rows of parked lorries on a hardstanding with workshops and a fuel point.
static func _vehicle_park(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var conc: Color = GroundKit.COL_CONCRETE
	GroundKit.box(root, Vector3(150.0, 0.3, 100.0), Vector3(0.0, _gh(root, Vector3.ZERO) + 0.15, 0.0), conc.darkened(0.12), Vector3.ZERO, false)
	var truck: Mesh = AirfieldAssets.truck("Allies")
	for row in 2 + size:
		for i in 4 + size:
			var lx: float = -60.0 + float(i) * 12.0
			var lz: float = -44.0 + float(row) * 13.0
			_inst(root, truck, Vector3(lx, 0.0, lz), 90.0 + rng.randf_range(-0.04, 0.04))
	# workshops with prism roofs and a fuel point
	for i in 2:
		var wx: float = -50.0 + float(i) * 100.0
		GroundKit.box(root, Vector3(26.0, 7.0, 16.0), Vector3(wx, _gh(root, Vector3(wx, 0.0, 52.0)) + 3.5, 52.0), GroundKit.COL_BRICK.darkened(0.1))
		var wr := MeshInstance3D.new()
		wr.mesh = GroundKit.prism_mesh(17.0, 27.0, 3.5)
		wr.material_override = GroundKit.mat(Color(0.3, 0.3, 0.32), true)
		wr.position = Vector3(wx, _gh(root, Vector3(wx, 0.0, 52.0)) + 7.0, 52.0)
		wr.rotation_degrees = Vector3(0.0, 90.0, 0.0)
		root.add_child(wr)
	GroundKit.cyl(root, 4.0, 4.0, 6.0, Vector3(80.0, _gh(root, Vector3(80.0, 0.0, 40.0)) + 3.0, 40.0), Color(0.55, 0.56, 0.54), Vector3.ZERO, 12)
	GroundKit.box(root, Vector3(2.0, 2.0, 2.0), Vector3(74.0, _gh(root, Vector3(74.0, 0.0, 42.0)) + 1.0, 42.0), Color(0.4, 0.4, 0.36))


## A horse-drawn transport column: horse lines, GS wagons and limbers, a farrier's forge and a water trough -
## the 1940 horse transport that far outnumbered the motorised columns.
static func _horse_column(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	# horse lines: a picket line with horses tethered along it
	for line in 2:
		var lz: float = -20.0 + float(line) * 40.0
		GroundKit.box(root, Vector3(80.0, 0.15, 0.15), Vector3(0.0, _gh(root, Vector3(0.0, 0.0, lz)) + 1.4, lz), GroundKit.COL_WOOD, Vector3.ZERO, false)
		for i in 5 + size * 2:
			var hx: float = -36.0 + float(i) * 7.0
			_horse(root, Vector3(hx, 0.0, lz + 2.4), 180.0 + rng.randf_range(-4.0, 4.0))
	# GS wagons and limbers
	for i in 2 + size:
		_wagon(root, Vector3(-30.0 + float(i) * 12.0, 0.0, 44.0), 0.0)
	for i in 1 + size:
		_wagon(root, Vector3(-24.0 + float(i) * 9.0, 0.0, 56.0), 0.0)
	# farrier's forge (a small shed with a chimney) and a water trough
	GroundKit.box(root, Vector3(9.0, 4.0, 7.0), Vector3(46.0, _gh(root, Vector3(46.0, 0.0, -30.0)) + 2.0, -30.0), Color(0.42, 0.34, 0.24))
	GroundKit.cyl(root, 0.5, 0.7, 5.0, Vector3(50.0, _gh(root, Vector3(50.0, 0.0, -30.0)) + 6.5, -30.0), Color(0.25, 0.22, 0.2), Vector3.ZERO, 6)
	GroundKit.box(root, Vector3(6.0, 1.0, 1.4), Vector3(-46.0, _gh(root, Vector3(-46.0, 0.0, -30.0)) + 0.5, -30.0), Color(0.42, 0.4, 0.36))
	# the horse lines' riders' tents
	var tent: Mesh = AirfieldAssets.tent("Allies")
	for i in 4 + size:
		_inst(root, tent, Vector3(-60.0 + float(i) * 6.0, 0.0, -46.0), rng.randf_range(-0.1, 0.1))


## A tank train: a rail siding of flatcars loaded with tanks.
static func _tank_train(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var ballast: Color = Color(0.4, 0.38, 0.34)
	_track(root, 200.0 + 20.0 * float(size), 0.0)
	GroundKit.box(root, Vector3(200.0 + 20.0 * float(size), 0.3, 4.0), Vector3(0.0, _gh(root, Vector3.ZERO) + 0.12, 0.0), ballast, Vector3.ZERO, false)
	var wagons: int = 4 + size
	for i in wagons:
		var x: float = (float(i) - float(wagons - 1) * 0.5) * 11.0
		var gy: float = _gh(root, Vector3(x, 0.0, 0.0))
		# the flatcar
		GroundKit.box(root, Vector3(10.0, 0.5, 3.0), Vector3(x, gy + 1.3, 0.0), Color(0.3, 0.28, 0.25))
		for bx in [-3.6, 3.6]:
			GroundKit.box(root, Vector3(2.0, 0.6, 2.4), Vector3(x + bx, gy + 0.7, 0.0), Color(0.18, 0.18, 0.18))
		_tank(root, Vector3(x, 0.0, 0.0), 0.0)
