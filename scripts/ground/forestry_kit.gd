class_name ForestryKit
extends RefCounted
## P17 forestry: the Forestry Commission plantations and the wartime timber camps, from data/forestry_1940.json.
## The Commission's 1919 conifer plantations (rows on a grid with a firebreak and a boundary) and the 1940
## timber camps where the Home Grown Timber Production Department felled them - Nissen-hut lines, a sawmill,
## timber and pit-prop stacks, a loading ramp and a narrow-gauge tramway. All procedural low-poly toon from
## GroundKit primitives plus the shared AirfieldAssets nissen mesh - no photo textures, no new assets.
##
##   var n: Node3D = ForestryKit.build(kind, pos, heading_deg, size, seed_v)   # node sits at world ORIGIN
##
## The returned container holds a `root` at (pos.x, ground_y, pos.z) rotated so local -Z faces the site's
## heading (the WorldFeatures / GroundStructure convention). Deterministic from seed_v. Driven from
## data/forestry_1940.json by WorldPopulator._register_forestry().

## The forestry kinds this kit understands.
static func kinds() -> Array:
	return ["plantation", "timber_camp"]


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
		"timber_camp":
			_timber_camp(root, sz, rng)
		_:
			_plantation(root, sz, rng)
	return container


# ------------------------------------------------------------------ helpers
## Terrain height at a local point of `root` (root is at the world origin's XZ with a yaw).
static func _gh(root: Node3D, local: Vector3) -> float:
	var w: Vector3 = root.transform * local
	return GroundKit.ground_y(w.x, w.z)


## One instance of a shared mesh (a Nissen hut) at a local point on the ground.
static func _inst(root: Node3D, mesh: Mesh, local: Vector3, yaw_deg: float) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(local.x, _gh(root, local), local.z)
	mi.rotation.y = deg_to_rad(yaw_deg)
	root.add_child(mi)


## A Forestry Commission conifer: a short trunk under a dark conical crown.
static func _conifer(root: Node3D, local: Vector3, h: float, rng: RandomNumberGenerator) -> void:
	var gy: float = _gh(root, local)
	var green: Color = Color(0.15, 0.29, 0.17).lightened(rng.randf_range(-0.02, 0.05))
	GroundKit.cyl(root, 0.16, 0.26, h * 0.3, Vector3(local.x, gy + h * 0.15, local.z), Color(0.33, 0.25, 0.17), Vector3.ZERO, 5, false)
	GroundKit.cyl(root, 0.0, h * 0.3, h * 0.85, Vector3(local.x, gy + h * 0.28 + h * 0.42, local.z), green, Vector3.ZERO, 7, false)


## A stack of saw logs: a low triangular heap of horizontal trunks of length `l`, laid along local X.
static func _log_stack(root: Node3D, local: Vector3, l: float, tiers: int) -> void:
	var gy: float = _gh(root, local)
	var bark: Color = Color(0.34, 0.25, 0.16)
	var r: float = 0.42
	for t in tiers:
		var cnt: int = tiers - t
		for i in cnt:
			var z: float = (float(i) - float(cnt - 1) * 0.5) * (r * 2.1)
			GroundKit.cyl(root, r, r, l, Vector3(local.x, gy + r + float(t) * r * 1.9, local.z + z), bark.lightened(0.03 * float((t + i) % 3)), Vector3(0, 0, 90), 8)


# ------------------------------------------------------------------ kinds
## A Forestry Commission conifer plantation: rows of conifers on a grid with a firebreak, a boundary ditch /
## fence and a forester's hut - the 1919-onwards State forest of Thetford Chase / Cannock Chase.
static func _plantation(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var rows: int = 8 + size * 3
	var cols: int = 9 + size * 3
	var sx: float = 9.0
	var sz: float = 9.0
	var fb_row: int = rows / 2
	for r in rows:
		if r == fb_row:
			continue                                             # a firebreak strip through the middle
		for c in cols:
			if c == cols / 2 and r % 3 == 0:
				continue                                         # a ride / extraction track
			var jx: float = rng.randf_range(-1.2, 1.2)
			var jz: float = rng.randf_range(-1.2, 1.2)
			_conifer(root, Vector3(float(c) * sx + jx, 0.0, float(r) * sz + jz), 9.0 + rng.randf_range(-1.5, 2.5), rng)
	var w: float = float(cols - 1) * sx
	var d: float = float(rows - 1) * sz
	# boundary ditch (a shallow dark cut) and a fence line around the plantation
	GroundKit.box(root, Vector3(w + 6.0, 0.3, 1.4), Vector3(w * 0.5, 0.15, -6.0), Color(0.24, 0.22, 0.16), Vector3.ZERO, false)
	for i in int(w / 12.0) + 1:
		GroundKit.cyl(root, 0.1, 0.12, 2.0, Vector3(float(i) * 12.0, 1.0, -6.0), Color(0.3, 0.24, 0.16), Vector3.ZERO, 4, false)
	# forester's hut beside the entrance to the ride
	var hx: float = w + 14.0
	var hy: float = _gh(root, Vector3(hx, 0.0, d * 0.5))
	GroundKit.box(root, Vector3(7.0, 3.5, 5.0), Vector3(hx, hy + 1.75, d * 0.5), Color(0.4, 0.34, 0.24))
	var pr := MeshInstance3D.new()
	pr.mesh = GroundKit.prism_mesh(7.6, 5.6, 2.0)
	pr.material_override = GroundKit.mat(Color(0.28, 0.26, 0.22), true)
	pr.position = Vector3(hx, hy + 3.5, d * 0.5)
	pr.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	root.add_child(pr)
	GroundKit.cyl(root, 0.5, 0.6, 1.8, Vector3(hx + 4.0, hy + 3.5, d * 0.5), Color(0.2, 0.2, 0.2), Vector3.ZERO, 6)


## A wartime timber camp: Nissen-hut lines, a sawmill with a saw bench, stacks of sawn timber and pit props,
## a loading ramp and a narrow-gauge tramway.
static func _timber_camp(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var conc: Color = GroundKit.COL_CONCRETE
	var wood: Color = GroundKit.COL_WOOD
	var hard: Color = Color(0.34, 0.3, 0.24)
	# the sawmill: a big open shed with a prism roof and a saw bench beneath it
	var my: float = _gh(root, Vector3(0.0, 0.0, 20.0))
	GroundKit.box(root, Vector3(30.0, 9.0, 18.0), Vector3(0.0, my + 4.5, 20.0), hard)
	var mr := MeshInstance3D.new()
	mr.mesh = GroundKit.prism_mesh(31.0, 19.0, 4.5)
	mr.material_override = GroundKit.mat(Color(0.28, 0.26, 0.22), true)
	mr.position = Vector3(0.0, my + 9.0, 20.0)
	mr.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	root.add_child(mr)
	GroundKit.box(root, Vector3(30.0, 8.5, 0.4), Vector3(0.0, my + 4.25, 11.0), GroundKit.COL_DARK, Vector3.ZERO, false)      # open mill front
	GroundKit.cyl(root, 1.4, 1.4, 22.0, Vector3(0.0, my + 4.0, 24.0), Color(0.35, 0.35, 0.33), Vector3(0, 0, 90), 10)          # bench saw
	GroundKit.box(root, Vector3(0.4, 6.0, 0.4), Vector3(9.0, my + 3.0, 24.0), GroundKit.COL_STEEL, Vector3.ZERO, false)
	GroundKit.cyl(root, 1.6, 2.0, 24.0, Vector3(-14.0, my + 18.0, 20.0), Color(0.3, 0.3, 0.3), Vector3.ZERO, 8)               # chimney / stack
	# sawdust apron and tramway spur to the stacking ground
	GroundKit.box(root, Vector3(60.0, 0.3, 40.0), Vector3(0.0, _gh(root, Vector3.ZERO) + 0.15, -4.0), conc.darkened(0.12), Vector3.ZERO, false)
	for i in 2:
		GroundKit.box(root, Vector3(0.4, 0.25, 90.0), Vector3((float(i) - 0.5) * 3.2, 0.5, -14.0), Color(0.3, 0.28, 0.26), Vector3.ZERO, false)
	for i in 12:
		GroundKit.box(root, Vector3(5.0, 0.2, 0.4), Vector3(0.0, 0.35, -56.0 + float(i) * 7.6), wood.darkened(0.05), Vector3.ZERO, false)
	# sawn-timber and pit-prop stacks
	for i in 3 + size:
		var lx: float = -40.0 + float(i) * 20.0
		GroundKit.box(root, Vector3(12.0, 3.0, 6.0), Vector3(lx, _gh(root, Vector3(lx, 0.0, -30.0)) + 1.5, -30.0), Color(0.55, 0.45, 0.3))
		GroundKit.box(root, Vector3(12.2, 0.4, 6.2), Vector3(lx, _gh(root, Vector3(lx, 0.0, -30.0)) + 3.2, -30.0), Color(0.3, 0.26, 0.2), Vector3.ZERO, false)
	_log_stack(root, Vector3(-24.0, 0.0, -52.0), 18.0, 3)
	_log_stack(root, Vector3(24.0, 0.0, -52.0), 18.0, 3)
	for i in 4 + size:
		GroundKit.cyl(root, 0.22, 0.22, 4.0, Vector3(44.0 + float(i % 2) * 3.0, _gh(root, Vector3(44.0, 0.0, -20.0 + float(i) * 2.6)) + 2.0, -20.0 + float(i) * 2.6), Color(0.5, 0.4, 0.26), Vector3.ZERO, 6, false)
	# Nissen-hut lines for the timber workers
	var nis: Mesh = AirfieldAssets.nissen("Allies")
	for row in 2:
		for i in 2 + size:
			_inst(root, nis, Vector3(-60.0 + float(i) * 14.0, 0.0, 60.0 + float(row) * 24.0), PI * 0.5)
	# a loading ramp and a timber lorry
	GroundKit.box(root, Vector3(16.0, 2.0, 8.0), Vector3(40.0, _gh(root, Vector3(40.0, 0.0, 40.0)) + 1.0, 40.0), hard, Vector3(-14.0, 0.0, 0.0))
	_inst(root, AirfieldAssets.truck("Allies"), Vector3(20.0, 0.0, 44.0), 0.0)
