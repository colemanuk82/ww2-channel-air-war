class_name RuralKit
extends RefCounted
## P13 rural / Kentish texture: oast houses, hop gardens, orchards, market gardens, drainage windpumps
## and sheep folds, from data/rural_1940.json. The distinctive 1940s Kentish / Channel-coast farming look.
## All procedural low-poly toon from GroundKit primitives - no photo textures, no new assets.
##
##   var n: Node3D = RuralKit.build(kind, pos, heading_deg, size, seed_v)   # node sits at world ORIGIN
##
## The returned container holds a `root` at (pos.x, ground_y, pos.z) rotated so local -Z faces the site's
## heading (the WorldFeatures / GroundStructure convention). Deterministic from seed_v. Driven from
## data/rural_1940.json by WorldPopulator._register_rural().

## The rural kinds this kit understands.
static func kinds() -> Array:
	return ["oast_house", "hop_garden", "orchard", "market_garden", "drainage_mill", "sheep_fold"]


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
		"oast_house":
			_oast_house(root, sz, rng)
		"hop_garden":
			_hop_garden(root, sz, rng)
		"orchard":
			_orchard(root, sz, rng)
		"market_garden":
			_market_garden(root, sz, rng)
		"drainage_mill":
			_drainage_mill(root, sz, rng)
		_:
			_sheep_fold(root, sz, rng)
	return container


# ------------------------------------------------------------------ helpers
## Terrain height at a local point of `root` (root is at the world origin's XZ with a yaw).
static func _gh(root: Node3D, local: Vector3) -> float:
	var w: Vector3 = root.transform * local
	return GroundKit.ground_y(w.x, w.z)


## A small deciduous tree: a trunk and a rounded canopy, with a faint outline (an orchard / hedge tree).
static func _tree(root: Node3D, local: Vector3, h: float, rng: RandomNumberGenerator) -> void:
	var gy: float = _gh(root, local)
	var green: Color = Color(0.28, 0.42, 0.2).lightened(rng.randf_range(-0.04, 0.06))
	GroundKit.cyl(root, 0.28, 0.4, h, Vector3(local.x, gy + h * 0.5, local.z), Color(0.34, 0.26, 0.18), Vector3.ZERO, 6)
	GroundKit.sphere(root, h * 0.55, Vector3(local.x, gy + h + h * 0.15, local.z), green, Vector3(1.0, 0.85, 1.0))


# ------------------------------------------------------------------ kinds
## An oast house: a brick roundel (kiln) with a conical white cowl on a rotating cap, beside a weatherboarded
## stowage barn with a pitched roof, and (for larger sites) a second roundel.
static func _oast_house(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var brick: Color = Color(0.5, 0.34, 0.26)
	var board: Color = Color(0.86, 0.85, 0.8)
	var roofs: Color = Color(0.3, 0.3, 0.32)
	# stowage barn (weatherboarded) with a pitched roof
	GroundKit.box(root, Vector3(18.0, 8.0, 12.0), Vector3(0.0, 4.0, 0.0), board)
	var pm := MeshInstance3D.new()
	pm.mesh = GroundKit.prism_mesh(19.0, 13.0, 5.0)
	pm.material_override = GroundKit.mat(roofs, true)
	pm.position = Vector3(0.0, 8.0, 0.0)
	root.add_child(pm)
	# roundel kilns with tapering cowls (one per size 1, two from size 2)
	var n: int = 1 + (size - 1)
	for i in n:
		var kx: float = 14.0 + float(i) * 11.0
		var kz: float = 0.0
		GroundKit.cyl(root, 4.4, 4.6, 9.0, Vector3(kx, 4.5, kz), brick, Vector3.ZERO, 12)
		GroundKit.cyl(root, 4.9, 4.9, 1.2, Vector3(kx, 9.6, kz), brick.darkened(0.15), Vector3.ZERO, 12)
		GroundKit.cyl(root, 0.0, 4.6, 6.5, Vector3(kx, 13.6, kz), Color(0.9, 0.89, 0.84), Vector3.ZERO, 12)   # cowl
		GroundKit.box(root, Vector3(1.2, 1.2, 3.0), Vector3(kx, 17.0, -1.6), roofs, Vector3.ZERO, false)          # cowl cap vane
	# a stack of hop-picking bins by the open side
	GroundKit.box(root, Vector3(2.4, 2.2, 2.4), Vector3(-13.0, 1.1, 8.0), Color(0.42, 0.34, 0.22))
	GroundKit.box(root, Vector3(2.4, 2.2, 2.4), Vector3(-13.0, 3.3, 8.0), Color(0.46, 0.38, 0.24))


## A hop garden: a grid of hop poles strung with wire trellis between rows, with a couple of hop kilns' worth of
## wire poles and a hop-pickers' hut - the unmistakable 1940s Kentish field.
static func _hop_garden(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var pole: Color = Color(0.4, 0.3, 0.18)
	var wire: Color = Color(0.5, 0.5, 0.46)
	var cols: int = 6 + size * 2
	var rows: int = 4 + size
	var sx: float = 4.0
	var sz: float = 6.0
	var w: float = float(cols - 1) * sx
	var d: float = float(rows - 1) * sz
	# headland wire at each end
	for zz in [0.0, d]:
		GroundKit.box(root, Vector3(w + 2.0, 0.15, 0.15), Vector3(w * 0.5, 6.0, zz), wire, Vector3.ZERO, false)
	for r in rows:
		for c in cols:
			var x: float = float(c) * sx
			var z: float = float(r) * sz
			# a hop pole with a string of wire up to the trellis
			GroundKit.cyl(root, 0.12, 0.16, 6.5, Vector3(x, 3.25, z), pole, Vector3.ZERO, 4, false)
			if r < rows - 1:
				GroundKit.box(root, Vector3(0.1, 0.1, sz), Vector3(x, 6.0, z + sz * 0.5), wire, Vector3.ZERO, false)
	# hop-pickers' hut and bins at the headland
	var hx: float = w + 10.0
	GroundKit.box(root, Vector3(6.0, 3.0, 4.0), Vector3(hx, 1.5, d * 0.5), Color(0.34, 0.3, 0.2))
	var hm := MeshInstance3D.new()
	hm.mesh = GroundKit.prism_mesh(6.6, 4.6, 2.0)
	hm.material_override = GroundKit.mat(Color(0.28, 0.26, 0.22), true)
	hm.position = Vector3(hx, 3.0, d * 0.5)
	root.add_child(hm)
	GroundKit.box(root, Vector3(2.2, 2.0, 2.2), Vector3(hx + 5.0, 1.0, d * 0.5 + 4.0), Color(0.42, 0.34, 0.22))


## An orchard: rows of small standard apple / cherry trees on mown grass, with a windbreak hedge on one side.
static func _orchard(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var cols: int = 6 + size * 2
	var rows: int = 5 + size
	var sx: float = 7.0
	var sz: float = 7.0
	for r in rows:
		for c in cols:
			var jx: float = rng.randf_range(-0.8, 0.8)
			var jz: float = rng.randf_range(-0.8, 0.8)
			_tree(root, Vector3(float(c) * sx + jx, 0.0, float(r) * sz + jz), 4.0 + rng.randf_range(-0.5, 0.8), rng)
	# a hawthorn windbreak hedge along the north edge
	var hedge: Color = Color(0.26, 0.36, 0.2)
	GroundKit.box(root, Vector3(float(cols - 1) * sx + 4.0, 2.4, 1.4), Vector3(float(cols - 1) * sx * 0.5, 1.2, -6.0), hedge, Vector3.ZERO, false)


## A market garden: rows of low glasshouses under cloches, vegetable beds and a packing shed - the market-garden
## belt that fed London and the Channel ports.
static func _market_garden(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var glass: Color = Color(0.62, 0.7, 0.7)
	var frame: Color = Color(0.6, 0.6, 0.56)
	var soil: Color = Color(0.34, 0.26, 0.18)
	var n_gh: int = 2 + size
	for i in n_gh:
		var gx: float = float(i) * 20.0
		GroundKit.box(root, Vector3(16.0, 3.0, 6.0), Vector3(gx, 1.5, -10.0), frame)
		var gm := MeshInstance3D.new()
		gm.mesh = GroundKit.prism_mesh(6.6, 16.4, 2.0)
		gm.material_override = GroundKit.mat(glass, false)
		gm.position = Vector3(gx, 3.0, -10.0)
		gm.rotation_degrees = Vector3(0.0, 90.0, 0.0)
		root.add_child(gm)
	# vegetable beds in rows with cloches
	for r in 4:
		for c in 6:
			var bx: float = float(c) * 6.0
			var bz: float = float(r) * 7.0 + 4.0
			GroundKit.box(root, Vector3(5.0, 0.3, 5.6), Vector3(bx, 0.15, bz), soil, Vector3.ZERO, false)
			if rng.randf() < 0.5:
				GroundKit.cyl(root, 1.6, 1.6, 1.0, Vector3(bx, 0.5, bz - 1.2), glass, Vector3(90.0, 0.0, 0.0), 6, false)
	# packing shed
	GroundKit.box(root, Vector3(9.0, 4.0, 6.0), Vector3(-14.0, 2.0, 4.0), frame.darkened(0.1))
	var sm := MeshInstance3D.new()
	sm.mesh = GroundKit.prism_mesh(6.6, 9.4, 2.4)
	sm.material_override = GroundKit.mat(Color(0.34, 0.32, 0.28), true)
	sm.position = Vector3(-14.0, 4.0, 4.0)
	sm.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	root.add_child(sm)


## A drainage windpump (a Marsh/Broadland smock mill): a tarred weatherboarded tower, a cap with four sails
## driving a scoop wheel, and a short drain leat - the marsh-drainage staple of Romney Marsh and the Broads.
static func _drainage_mill(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var tar: Color = Color(0.16, 0.15, 0.14)
	var white: Color = Color(0.88, 0.87, 0.82)
	# brick base and tarred smock body
	GroundKit.cyl(root, 5.0, 5.6, 3.0, Vector3(0.0, 1.5, 0.0), Color(0.42, 0.34, 0.28), Vector3.ZERO, 10)
	GroundKit.cyl(root, 3.0, 5.0, 11.0, Vector3(0.0, 8.5, 0.0), tar, Vector3.ZERO, 10)
	# boat-shaped cap
	GroundKit.cyl(root, 0.0, 3.4, 3.2, Vector3(0.0, 15.6, 0.0), white, Vector3.ZERO, 10)
	# four common sails
	var sails := Node3D.new()
	sails.position = Vector3(0.0, 15.0, -3.4)
	sails.name = "Sails"
	root.add_child(sails)
	for i in 4:
		var arm := Node3D.new()
		arm.rotation.z = float(i) * PI * 0.5
		sails.add_child(arm)
		GroundKit.box(arm, Vector3(1.6, 13.0, 0.3), Vector3(0.0, 7.0, 0.0), Color(0.82, 0.78, 0.68), Vector3.ZERO, false)
	sails.rotation.z = rng.randf() * TAU
	# the scoop wheel in its housing beside the tower, over the drain leat
	GroundKit.box(root, Vector3(5.0, 5.0, 6.0), Vector3(7.0, 2.5, 0.0), Color(0.36, 0.32, 0.28))
	GroundKit.cyl(root, 3.0, 3.0, 1.0, Vector3(7.0, 2.5, 0.0), Color(0.3, 0.3, 0.32), Vector3(0.0, 0.0, 90.0), 10)
	var leat: MeshInstance3D = GroundKit.box(root, Vector3(30.0, 0.2, 3.2), Vector3(9.0, 0.1, 0.0), Color(0.18, 0.3, 0.38), Vector3.ZERO, false)
	leat.material_override = GroundKit.glow_mat(Color(0.18, 0.3, 0.38), 0.86, false)


## A sheep fold: a stone-walled / hurdle pen with a hurdles race, a fold-yard gate and a handful of sheep, with a
## shepherd's hut beside it - the downland sheep-folding landscape of the South Downs.
static func _sheep_fold(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var stone: Color = Color(0.62, 0.6, 0.54)
	var wood: Color = Color(0.4, 0.3, 0.18)
	var wool: Color = Color(0.86, 0.84, 0.78)
	# dry-stone pen walls (four sides with a gap on the south side for the gate)
	var w: float = 16.0 + float(size) * 4.0
	var d: float = 12.0 + float(size) * 3.0
	for sz in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(w, 1.4, 1.0), Vector3(0.0, 0.7, sz * d * 0.5), stone, Vector3.ZERO, false)
	GroundKit.box(root, Vector3(1.0, 1.4, d), Vector3(-w * 0.5, 0.7, 0.0), stone, Vector3.ZERO, false)
	GroundKit.box(root, Vector3(w * 0.45, 1.4, 1.0), Vector3(-w * 0.25, 0.7, d * 0.5), stone, Vector3.ZERO, false)
	GroundKit.box(root, Vector3(w * 0.45, 1.4, 1.0), Vector3(w * 0.25, 0.7, d * 0.5), stone, Vector3.ZERO, false)
	# the gate posts and a hurdle gate at the gap
	for sx in [-1.0, 1.0]:
		GroundKit.cyl(root, 0.3, 0.3, 2.2, Vector3(sx * w * 0.06, 1.1, d * 0.5), wood, Vector3.ZERO, 5, false)
	GroundKit.box(root, Vector3(w * 0.5, 1.1, 0.2), Vector3(0.0, 0.6, d * 0.5), wood, Vector3.ZERO, false)
	# a hurdles race leading in from the gate
	for i in 4:
		var hx: float = -w * 0.5 + float(i) * 2.2
		for sx2 in [-1.0, 1.0]:
			GroundKit.box(root, Vector3(0.15, 1.1, 2.0), Vector3(hx, 0.55, d * 0.5 + sx2 * 1.2), wood, Vector3.ZERO, false)
	# (no sheep: removed in v7.27)
	# a shepherd's hut on wheels
	GroundKit.box(root, Vector3(3.6, 2.4, 2.2), Vector3(-w * 0.6, 1.2, d * 0.5 + 4.0), Color(0.42, 0.34, 0.24))
	var rh := MeshInstance3D.new()
	rh.mesh = GroundKit.prism_mesh(4.0, 2.6, 1.0)
	rh.material_override = GroundKit.mat(Color(0.28, 0.26, 0.22), true)
	rh.position = Vector3(-w * 0.6, 2.4, d * 0.5 + 4.0)
	root.add_child(rh)
	for sx4 in [-1.0, 1.0]:
		GroundKit.cyl(root, 0.5, 0.5, 0.3, Vector3(-w * 0.6 + sx4 * 1.2, 0.3, d * 0.5 + 5.1), Color(0.12, 0.12, 0.12), Vector3(90.0, 0.0, 0.0), 8, false)
