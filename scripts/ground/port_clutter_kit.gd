class_name PortClutterKit
extends RefCounted
## P12 1940 port clutter at the existing ports and dock sites (data/port_clutter_1940.json): dockside cranes
## (hammerhead / travelling gantry and hand cranes), dock entrance locks with mitre/caisson gates, bucket and
## suction dredgers, dumb hopper barges, harbour tugs, paddle steamers and the Dover-Dunkerque train ferries.
## The moored and working vessels are real GroundShip hulls (the same hulls the harbours moor) with extra toon
## superstructure - a bucket ladder, a hopper chute, paddle boxes, a linkspan and rail wagons. All procedural
## low-poly toon from GroundKit primitives - no photo textures, no new assets.
##
##   var n: Node3D = PortClutterKit.build(kind, pos, sea, size, team, seed_v)   # node at the world ORIGIN
##
## `pos` is a shore point and `sea` the unit direction towards open water; the returned container holds a `root`
## at (pos.x, 0, pos.z) rotated so local -Z faces the sea (the WorldFeatures convention). Moored ships are
## world-space children of the container, as WorldFeatures.build_port does. Deterministic from seed_v.

## The clutter kinds this kit understands.
static func kinds() -> Array:
	return ["crane", "lock_gate", "dredger", "hopper_barge", "tug", "paddle_steamer", "train_ferry"]


static func build(kind: String, pos: Vector3, sea: Vector3, size: int, team: String, seed_v: int) -> Node3D:
	var container := Node3D.new()
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.z)
	root.rotation.y = -deg_to_rad(WorldCoords.dir_to_heading(sea))      # local -Z = towards the sea
	container.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var sz: int = clampi(size, 1, 3)
	var base_heading: float = WorldCoords.dir_to_heading(sea)
	match kind:
		"lock_gate":
			_lock_gate(root, sz, team, rng)
		"dredger":
			_dredger(root, container, team, rng, base_heading)
		"hopper_barge":
			_hopper_barge(root, container, team, rng, base_heading)
		"tug":
			_tug(root, container, team, rng, base_heading)
		"paddle_steamer":
			_paddle_steamer(root, container, team, rng, base_heading)
		"train_ferry":
			_train_ferry(root, container, team, rng, base_heading)
		_:
			_crane(root, sz, rng)
	return container


# ------------------------------------------------------------------ helpers
## World position of a local point of `root`, flattened to the water plane (moored ships sit at y = 0.1).
static func _wp(root: Node3D, local: Vector3) -> Vector3:
	var w: Vector3 = root.transform * local
	return Vector3(w.x, 0.1, w.z)


## Terrain height at a local point of `root` (root is at the world origin's XZ with a yaw, as OilFuelKit).
static func _gh(root: Node3D, local: Vector3) -> float:
	var w: Vector3 = root.transform * local
	return GroundKit.ground_y(w.x, w.z)


## A world-space holder that shares a moored ship's frame, for building its superstructure.
static func _holder(container: Node3D, wp: Vector3, heading_deg: float) -> Node3D:
	var h := Node3D.new()
	h.position = Vector3(wp.x, 0.1, wp.z)
	h.rotation.y = -deg_to_rad(heading_deg)
	container.add_child(h)
	return h


## A moored (stationary) GroundShip at a world point, aligned to `heading_deg`.
static func _moor(container: Node3D, t: String, team: String, wp: Vector3, heading_deg: float) -> GroundShip:
	var along: Vector3 = WorldCoords.heading_to_dir(heading_deg)
	var rp: RoutePath = RoutePath.from_points(PackedVector3Array([wp, wp + along * 8.0]))
	var sh: GroundShip = GroundShip.create(t, team, rp, 0.0, 0.0)
	sh.speed = 0.0
	sh.wrap = false
	sh.position = Vector3(wp.x, 0.1, wp.z)
	sh.rotation.y = -deg_to_rad(heading_deg)
	container.add_child(sh)
	return sh


## A masonry quay edge strip along the local X axis (the land side is +Z).
static func _quay(root: Node3D, length: float, z: float) -> void:
	var stone: Color = Color(0.45, 0.45, 0.42)
	GroundKit.box(root, Vector3(length, 2.4, 10.0), Vector3(0.0, 1.1, z), stone)
	GroundKit.box(root, Vector3(length + 2.0, 0.8, 11.0), Vector3(0.0, 2.6, z), GroundKit.COL_CONCRETE.darkened(0.08))


# ------------------------------------------------------------------ kinds
## Dockside cranes: a travelling portal gantry on rails plus a fixed hand crane and a line of bollards.
static func _crane(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var steel: Color = Color(0.42, 0.42, 0.4)
	var red: Color = Color(0.7, 0.18, 0.12)
	_quay(root, 130.0 + 30.0 * float(size), 6.0)
	# travelling portal gantry crane(s)
	for i in 1 + size:
		var cx: float = (float(i) - float(1 + size) * 0.5) * 40.0
		for sx in [-1.0, 1.0]:
			GroundKit.box(root, Vector3(1.6, 22.0, 1.6), Vector3(cx + sx * 5.0, 11.0, 4.0), steel)                       # legs
			GroundKit.box(root, Vector3(2.4, 1.0, 2.4), Vector3(cx + sx * 5.0, 0.6, 4.0), GroundKit.COL_DARK, Vector3.ZERO, false)   # bogie
		GroundKit.box(root, Vector3(15.0, 2.0, 2.0), Vector3(cx, 22.0, 4.0), steel)                                          # portal beam
		GroundKit.box(root, Vector3(2.4, 24.0, 2.4), Vector3(cx, 30.0, 4.0), red)                                            # mast
		GroundKit.box(root, Vector3(2.0, 2.0, 44.0), Vector3(cx, 34.0, -12.0), red, Vector3(-8.0, 0.0, 0.0))                 # jib out over the water
		GroundKit.box(root, Vector3(1.0, 14.0, 1.0), Vector3(cx, 26.0, -30.0), GroundKit.COL_DARK, Vector3.ZERO, false)      # hoist rope
		GroundKit.box(root, Vector3(1.6, 1.6, 1.6), Vector3(cx, 18.0, -30.0), GroundKit.COL_DARK, Vector3.ZERO, false)       # hook block
		GroundKit.box(root, Vector3(4.0, 4.0, 4.0), Vector3(cx, 16.0, 4.0), GroundKit.COL_DARK.lightened(0.2))               # cab
	# fixed hand crane on a masonry base
	var hx: float = 70.0 + 10.0 * float(size)
	GroundKit.box(root, Vector3(5.0, 3.0, 5.0), Vector3(hx, 1.5, 8.0), GroundKit.COL_BRICK.darkened(0.15))
	GroundKit.cyl(root, 0.7, 0.9, 10.0, Vector3(hx, 8.0, 8.0), steel, Vector3.ZERO, 8)
	GroundKit.cyl(root, 0.35, 0.45, 9.0, Vector3(hx - 3.0, 12.0, 8.0), steel, Vector3(0.0, 0.0, 62.0), 8)
	GroundKit.box(root, Vector3(1.4, 1.2, 1.4), Vector3(hx, 12.6, 8.0), GroundKit.COL_DARK, Vector3.ZERO, false)
	# bollards along the quay edge
	for i in 10:
		GroundKit.cyl(root, 0.35, 0.45, 1.4, Vector3((float(i) - 4.5) * (140.0 + 30.0 * float(size)) / 10.0, 3.0, 1.2), GroundKit.COL_DARK, Vector3.ZERO, 6, false)
	_office(root, Vector3(-80.0 - 10.0 * float(size), 0.0, 16.0), rng)
	# a stone breakwater arm running out along the shore, with a rounded head, a harbour light and rock toes
	var stone: Color = Color(0.5, 0.5, 0.46)
	var bl: float = 150.0 + 34.0 * float(size)
	var bz: float = -58.0
	GroundKit.box(root, Vector3(bl, 7.0, 18.0), Vector3(0.0, 2.2, bz), stone, Vector3.ZERO, false)
	GroundKit.box(root, Vector3(bl + 4.0, 1.6, 11.0), Vector3(0.0, 6.4, bz), stone.lightened(0.05), Vector3.ZERO, false)
	for i in maxi(1, int(bl / 26.0)):
		var bx: float = -bl * 0.5 + (float(i) + 0.5) * (bl / float(maxi(1, int(bl / 26.0))))
		GroundKit.box(root, Vector3(13.0, 3.2, 9.0), Vector3(bx, 0.7, bz - 11.0), stone.darkened(0.08), Vector3(0.0, 0.0, rng.randf_range(-7.0, 7.0)), false)
	# the return arm tying the breakwater back to the shore, and the rounded head with the light
	GroundKit.box(root, Vector3(13.0, 7.0, 30.0), Vector3(bl * 0.5 - 6.0, 2.2, bz + 22.0), stone, Vector3.ZERO, false)
	var hxh: float = -bl * 0.5 + 8.0
	GroundKit.cyl(root, 11.0, 13.0, 6.2, Vector3(hxh, 2.2, bz), stone, Vector3.ZERO, 14)
	GroundKit.cyl(root, 1.0, 1.4, 10.0, Vector3(hxh, 10.6, bz), Color(0.88, 0.86, 0.82), Vector3.ZERO, 8)
	GroundKit.cyl(root, 1.2, 1.2, 2.2, Vector3(hxh, 14.9, bz), Color(0.9, 0.85, 0.5), Vector3.ZERO, 8, false)
	GroundKit.cyl(root, 0.0, 1.6, 2.4, Vector3(hxh, 17.2, bz), GroundKit.COL_DARK, Vector3.ZERO, 8, false)
	# an extra timber finger pier running out from the quay on slim piles
	var px: float = 46.0 + 8.0 * float(size)
	var wood: Color = GroundKit.COL_WOOD.darkened(0.1)
	GroundKit.box(root, Vector3(11.0, 1.6, 52.0), Vector3(px, 3.4, -22.0), wood)
	for pk in 5:
		for sx in [-1.0, 1.0]:
			GroundKit.cyl(root, 0.5, 0.6, 6.0, Vector3(px + sx * 4.2, 1.5, -1.0 - float(pk) * 11.0), GroundKit.COL_WOOD, Vector3.ZERO, 6, false)
	GroundKit.box(root, Vector3(13.0, 0.6, 3.0), Vector3(px, 4.4, -46.0), wood.lightened(0.06), Vector3.ZERO, false)
	# moored small boats inside the harbour, between the quay and the breakwater
	for bi in 5:
		_small_boat(root, Vector3(-92.0 + float(bi) * 33.0, 0.0, -15.0 - float(bi % 2) * 8.0), (0.0 if bi % 2 == 0 else 180.0) + rng.randf_range(-6.0, 6.0), rng)


## A small moored open boat (rowing boat / ship's dinghy): a low hull, a foredeck and a short mast.
static func _small_boat(root: Node3D, local: Vector3, yaw_deg: float, rng: RandomNumberGenerator) -> void:
	var b := Node3D.new()
	b.position = Vector3(local.x, 0.15, local.z)
	b.rotation.y = -deg_to_rad(yaw_deg)
	root.add_child(b)
	var hull: Color = Color(0.34, 0.3, 0.24)
	GroundKit.box(b, Vector3(2.2, 1.1, 6.4), Vector3(0.0, 0.55, 0.0), hull, Vector3.ZERO, false)
	GroundKit.box(b, Vector3(1.9, 1.3, 1.6), Vector3(0.0, 0.85, -2.6), hull.darkened(0.08), Vector3.ZERO, false)
	GroundKit.box(b, Vector3(0.14, 0.16, 6.2), Vector3(0.95, 1.2, 0.0), Color(0.5, 0.5, 0.46), Vector3.ZERO, false)
	GroundKit.box(b, Vector3(0.14, 0.16, 6.2), Vector3(-0.95, 1.2, 0.0), Color(0.5, 0.5, 0.46), Vector3.ZERO, false)
	GroundKit.cyl(b, 0.1, 0.12, 4.6, Vector3(0.0, 2.3, -1.4), GroundKit.COL_WOOD, Vector3.ZERO, 4, false)


## A small port office / weighbridge hut.
static func _office(root: Node3D, local: Vector3, rng: RandomNumberGenerator) -> void:
	var gy: float = _gh(root, local)
	GroundKit.box(root, Vector3(9.0, 4.0, 6.0), Vector3(local.x, gy + 2.0, local.z), GroundKit.COL_BRICK)
	var pm := MeshInstance3D.new()
	pm.mesh = GroundKit.prism_mesh(6.6, 9.4, 1.8)
	pm.material_override = GroundKit.mat(Color(0.3, 0.3, 0.32), true)
	pm.position = Vector3(local.x, gy + 4.0, local.z)
	pm.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	root.add_child(pm)
	GroundKit.cyl(root, 0.5, 0.6, 2.0, Vector3(local.x + 3.0, gy + 5.0, local.z), GroundKit.COL_BRICK.darkened(0.3), Vector3.ZERO, 6)


## A dock entrance lock: a channel between two walled piers, mitre gates at both ends with balance beams,
## capstans, a sluice, and a lock keeper's office on the bank.
static func _lock_gate(root: Node3D, size: int, team: String, rng: RandomNumberGenerator) -> void:
	var stone: Color = Color(0.5, 0.48, 0.43)
	var wood: Color = GroundKit.COL_WOOD
	var conc: Color = GroundKit.COL_CONCRETE
	var length: float = 54.0 + 10.0 * float(size)
	var half_w: float = 11.0 + 2.0 * float(size)
	# channel water + the two flanking entrance piers running along the channel (local Z)
	var water: MeshInstance3D = GroundKit.box(root, Vector3(half_w * 2.0, 0.2, length), Vector3(0.0, 0.1, 0.0), Color(0.16, 0.3, 0.42), Vector3.ZERO, false)
	water.material_override = GroundKit.glow_mat(Color(0.16, 0.3, 0.42), 0.86, false)
	for sx in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(7.0, 6.0, length), Vector3(sx * (half_w + 3.5), 1.2, 0.0), conc)
		GroundKit.box(root, Vector3(8.0, 1.0, length + 2.0), Vector3(sx * (half_w + 3.5), 4.4, 0.0), stone)
	# mitre gates at both ends: two leaves angled to meet in the middle, with balance beams
	for sz in [-1.0, 1.0]:
		var z: float = sz * length * 0.42
		for sx2 in [-1.0, 1.0]:
			var leaf := Node3D.new()
			leaf.position = Vector3(sx2 * half_w * 0.5, 0.0, z)
			leaf.rotation.y = deg_to_rad(sx2 * 20.0)
			root.add_child(leaf)
			GroundKit.box(leaf, Vector3(half_w, 5.0, 1.0), Vector3(0.0, 2.5, 0.0), wood)
			GroundKit.box(leaf, Vector3(half_w * 1.1, 0.5, 0.4), Vector3(0.0, 5.4, 0.0), stone, Vector3.ZERO, false)
		for sx3 in [-1.0, 1.0]:
			GroundKit.box(root, Vector3(6.0, 0.5, 0.5), Vector3(sx3 * (half_w + 1.0), 4.6, z + sz * 2.0), wood.darkened(0.15))
	# capstans and bollards on the piers
	for i in 6:
		var z2: float = -length * 0.5 + float(i) * (length / 6.0)
		for sx4 in [-1.0, 1.0]:
			GroundKit.cyl(root, 0.6, 0.7, 1.6, Vector3(sx4 * (half_w + 4.5), 5.2, z2), GroundKit.COL_STEEL, Vector3.ZERO, 6, false)
			GroundKit.cyl(root, 0.35, 0.45, 1.4, Vector3(sx4 * (half_w + 1.5), 5.4, z2), GroundKit.COL_DARK, Vector3.ZERO, 6, false)
	# keeper's office at the landward end
	_office(root, Vector3(half_w + 12.0, 0.0, -length * 0.5 - 6.0), rng)


## A moored bucket dredger with its ladder over the bow, plus an engine casing and a chimney.
static func _dredger(root: Node3D, container: Node3D, team: String, rng: RandomNumberGenerator, base_heading: float) -> void:
	_quay(root, 120.0, 8.0)
	var wp: Vector3 = _wp(root, Vector3(0.0, 0.0, -30.0))
	var hdg: float = base_heading + 90.0
	_moor(container, "collier", team, wp, hdg)
	var h: Node3D = _holder(container, wp, hdg)
	var steel: Color = Color(0.36, 0.36, 0.38)
	GroundKit.box(h, Vector3(6.0, 3.0, 12.0), Vector3(0.0, 4.0, 6.0), Color(0.5, 0.48, 0.44))                          # engine casing
	GroundKit.cyl(h, 0.9, 1.2, 9.0, Vector3(0.0, 8.0, 2.0), GroundKit.COL_DARK, Vector3.ZERO, 8)                          # funnel
	# the bucket ladder: a rising frame with a chain of buckets, over the bow (-Z)
	GroundKit.box(h, Vector3(2.4, 1.2, 20.0), Vector3(0.0, 6.0, -16.0), steel, Vector3(-38.0, 0.0, 0.0))
	for i in 6:
		var t: float = float(i) / 5.0
		GroundKit.box(h, Vector3(1.8, 1.6, 1.8), Vector3(0.0, 2.0 + t * 7.0, -8.0 - t * 16.0), Color(0.28, 0.28, 0.3))
	# hopper barges lying alongside
	for i in 2:
		var bp: Vector3 = _wp(root, Vector3(-40.0 + float(i) * 24.0, 0.0, -16.0))
		_moor(container, "landing_craft", team, bp, base_heading + 90.0)


## Dumb hopper barges with bottom doors, alongside the quay (the dredging spoil fleet).
static func _hopper_barge(root: Node3D, container: Node3D, team: String, rng: RandomNumberGenerator, base_heading: float) -> void:
	_quay(root, 100.0, 8.0)
	for i in 3:
		var wp: Vector3 = _wp(root, Vector3(-30.0 + float(i) * 28.0, 0.0, -22.0))
		var hdg: float = base_heading + 90.0
		_moor(container, "landing_craft", team, wp, hdg)
		var h: Node3D = _holder(container, wp, hdg)
		GroundKit.box(h, Vector3(6.4, 1.0, 14.0), Vector3(0.0, 2.2, 0.0), Color(0.28, 0.26, 0.23), Vector3.ZERO, false)   # raised coaming
		GroundKit.box(h, Vector3(2.0, 0.4, 8.0), Vector3(0.0, 1.2, 6.0), Color(0.2, 0.2, 0.2), Vector3.ZERO, false)


## A harbour tug with its towing winch, fenders and a squat funnel.
static func _tug(root: Node3D, container: Node3D, team: String, rng: RandomNumberGenerator, base_heading: float) -> void:
	_quay(root, 80.0, 8.0)
	var wp: Vector3 = _wp(root, Vector3(0.0, 0.0, -18.0))
	var hdg: float = base_heading + 90.0
	_moor(container, "trawler", team, wp, hdg)
	var h: Node3D = _holder(container, wp, hdg)
	GroundKit.box(h, Vector3(3.6, 2.6, 5.0), Vector3(0.0, 3.4, 1.0), Color(0.8, 0.8, 0.76))                              # wheelhouse
	GroundKit.cyl(h, 0.7, 0.9, 4.0, Vector3(0.0, 5.5, 1.0), GroundKit.COL_DARK, Vector3.ZERO, 8)                          # funnel
	GroundKit.cyl(h, 0.5, 0.6, 2.0, Vector3(0.0, 1.6, -6.0), GroundKit.COL_STEEL, Vector3.ZERO, 8)                        # towing winch
	for sz in [-1.0, 1.0]:
		GroundKit.cyl(h, 0.6, 0.6, 5.0, Vector3(2.2, 1.2, sz * 3.0), Color(0.2, 0.2, 0.2), Vector3(0.0, 0.0, 90.0), 6, false)   # fenders


## A paddle steamer: a steamer hull with two paddle boxes and a promenade deck over them, and a slim funnel.
static func _paddle_steamer(root: Node3D, container: Node3D, team: String, rng: RandomNumberGenerator, base_heading: float) -> void:
	_quay(root, 110.0, 8.0)
	var wp: Vector3 = _wp(root, Vector3(0.0, 0.0, -26.0))
	var hdg: float = base_heading + 90.0
	_moor(container, "ferry", team, wp, hdg)
	var h: Node3D = _holder(container, wp, hdg)
	var cream: Color = Color(0.86, 0.83, 0.72)
	for sx in [-1.0, 1.0]:
		GroundKit.cyl(h, 5.0, 5.0, 3.2, Vector3(sx * 4.2, 4.0, 0.0), cream, Vector3(0.0, 0.0, 90.0), 14)                  # paddle box
		GroundKit.cyl(h, 5.2, 5.2, 0.5, Vector3(sx * 4.2, 4.0, 0.0), Color(0.3, 0.3, 0.32), Vector3(0.0, 0.0, 90.0), 14, false)
	GroundKit.box(h, Vector3(9.0, 2.6, 22.0), Vector3(0.0, 5.6, 0.0), cream)                                              # promenade deck
	GroundKit.box(h, Vector3(6.0, 2.0, 12.0), Vector3(0.0, 7.6, 2.0), Color(0.78, 0.75, 0.66))                            # saloon
	GroundKit.cyl(h, 0.9, 1.1, 8.0, Vector3(0.0, 10.0, -6.0), Color(0.85, 0.2, 0.15), Vector3.ZERO, 8)                    # funnel
	GroundKit.cyl(h, 0.06, 0.06, 6.0, Vector3(0.0, 12.0, 6.0), GroundKit.COL_WOOD, Vector3.ZERO, 4, false)                # mast


## A Dover-Dunkerque train-ferry berth: a quay with rail sidings and covered wagons, an inclined linkspan onto
## the water and a gantry over it, with a ferry moored alongside.
static func _train_ferry(root: Node3D, container: Node3D, team: String, rng: RandomNumberGenerator, base_heading: float) -> void:
	var steel: Color = Color(0.4, 0.4, 0.42)
	_quay(root, 180.0, 10.0)
	# rail sidings on the quay with covered wagons
	for side in 2:
		var zz: float = 6.0 + float(side) * 8.0
		GroundKit.box(root, Vector3(160.0, 0.3, 1.4), Vector3(0.0, 2.7, zz), Color(0.4, 0.38, 0.34), Vector3.ZERO, false)
		for i in 4:
			var wx: float = -60.0 + float(i) * 40.0
			GroundKit.box(root, Vector3(9.0, 3.0, 2.6), Vector3(wx, _gh(root, Vector3(wx, 0.0, zz)) + 4.2, zz), Color(0.32, 0.28, 0.22))
			GroundKit.box(root, Vector3(9.4, 0.4, 2.9), Vector3(wx, _gh(root, Vector3(wx, 0.0, zz)) + 5.9, zz), Color(0.2, 0.18, 0.16), Vector3.ZERO, false)
	# the linkspan: an inclined bridge from the quay down towards the water (local -Z)
	var span := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(16.0, 1.2, 40.0)
	span.mesh = bm
	span.material_override = GroundKit.mat(steel, false)
	span.position = Vector3(0.0, 2.4, -22.0)
	span.rotation_degrees = Vector3(14.0, 0.0, 0.0)
	root.add_child(span)
	# a portal gantry straddling the linkspan
	for sx in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(1.8, 20.0, 1.8), Vector3(sx * 11.0, 10.0, -14.0), steel)
	GroundKit.box(root, Vector3(26.0, 2.2, 2.2), Vector3(0.0, 20.0, -14.0), steel)
	GroundKit.box(root, Vector3(1.0, 12.0, 1.0), Vector3(0.0, 12.0, -14.0), GroundKit.COL_DARK, Vector3.ZERO, false)
	# the ferry moored at the berth
	var wp: Vector3 = _wp(root, Vector3(0.0, 0.0, -40.0))
	var hdg: float = base_heading + 90.0
	_moor(container, "ferry", team, wp, hdg)
	var h: Node3D = _holder(container, wp, hdg)
	GroundKit.box(h, Vector3(6.0, 2.6, 10.0), Vector3(0.0, 5.0, 8.0), Color(0.8, 0.8, 0.76))                             # bridge
	GroundKit.cyl(h, 1.1, 1.3, 6.0, Vector3(0.0, 9.0, 6.0), Color(0.85, 0.2, 0.15), Vector3.ZERO, 8)                      # funnel
	_office(root, Vector3(-70.0, 0.0, 20.0), rng)
