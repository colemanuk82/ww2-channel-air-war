class_name CivilDefenceKit
extends RefCounted
## P15 civil defence: public surface shelters, Anderson garden shelters, ARP / wardens' posts and sandbagged
## buildings from data/civil_defence_1940.json, plus camouflage-painted factory roofs driven off the existing
## industry / aircraft-industry sites (see camouflage_roof). All procedural low-poly toon from GroundKit
## primitives - no photo textures, no new assets.
##
##   var n: Node3D = CivilDefenceKit.build(kind, pos, heading_deg, size, seed_v)   # node sits at world ORIGIN
##
## The returned container holds a `root` at (pos.x, ground_y, pos.z) rotated so local -Z faces the site's
## heading (the WorldFeatures / GroundStructure convention). Deterministic from seed_v. Driven from
## data/civil_defence_1940.json by WorldPopulator._register_civil_defence().

const COL_SAND: Color = Color(0.62, 0.55, 0.38)
const COL_CORRUGATED: Color = Color(0.46, 0.47, 0.45)
const COL_BRICKWALL: Color = Color(0.52, 0.33, 0.26)


## The civil-defence kinds this kit understands (scenery).
static func kinds() -> Array:
	return ["surface_shelter", "anderson_shelter", "arp_post", "sandbagged_building"]


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
		"anderson_shelter":
			_anderson_shelter(root, sz, rng)
		"arp_post":
			_arp_post(root, sz, rng)
		"sandbagged_building":
			_sandbagged_building(root, sz, rng)
		_:
			_surface_shelter(root, sz, rng)
	return container


# ------------------------------------------------------------------ helpers
## Terrain height at a local point of `root` (root is at the world origin's XZ with a yaw).
static func _gh(root: Node3D, local: Vector3) -> float:
	var w: Vector3 = root.transform * local
	return GroundKit.ground_y(w.x, w.z) - root.position.y


## A row of sandbags along the local X axis (a wall face at +Z), length `length` at local z.
static func _sandbag_row(root: Node3D, length: float, y: float, z: float) -> void:
	var n: int = maxi(2, int(length / 1.1))
	for i in n:
		var x: float = -length * 0.5 + (float(i) + 0.5) * (length / float(n))
		if i % 2 == 1:
			GroundKit.box(root, Vector3(1.1, 0.45, 0.7), Vector3(x, y + 0.22, z), COL_SAND, Vector3.ZERO, false)
		GroundKit.box(root, Vector3(1.1, 0.45, 0.7), Vector3(x, y + 0.67, z), COL_SAND.darkened(0.06 if (i % 2 == 0) else 0.0), Vector3.ZERO, false)


## A low sandbag revetment ring around a point (an ARP post / shelter entrance protection).
static func _sandbag_ring(root: Node3D, centre: Vector3, sides: int, radius: float, y: float) -> void:
	for i in sides:
		var a: float = TAU * float(i) / float(sides)
		var px: float = centre.x + cos(a) * radius
		var pz: float = centre.z + sin(a) * radius
		GroundKit.box(root, Vector3(2.0, 0.5, 0.9), Vector3(px, y + 0.25, pz), COL_SAND, Vector3(0.0, -rad_to_deg(a) + 90.0, 0.0), false)
		GroundKit.box(root, Vector3(2.0, 0.5, 0.9), Vector3(px, y + 0.75, pz), COL_SAND.darkened(0.05), Vector3(0.0, -rad_to_deg(a) + 90.0, 0.0), false)


# ------------------------------------------------------------------ kinds
## A public surface shelter: a long low brick-and-concrete box (a flat blast slab roof), a baffled entrance
## with a blast wall, and a ventilation stack - the street-corner communal shelters of 1940.
static func _surface_shelter(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var conc: Color = GroundKit.COL_CONCRETE
	var length: float = 14.0 + float(size) * 5.0
	var width: float = 5.0 + float(size) * 0.5
	# the shelter body (a low brick box) and its heavy flat blast roof slab
	GroundKit.box(root, Vector3(length, 3.0, width), Vector3(0.0, 1.5, 0.0), COL_BRICKWALL)
	GroundKit.box(root, Vector3(length + 1.2, 1.0, width + 1.2), Vector3(0.0, 3.5, 0.0), conc, Vector3.ZERO, false)
	GroundKit.box(root, Vector3(length + 0.4, 0.4, width + 0.4), Vector3(0.0, 4.1, 0.0), conc.darkened(0.1), Vector3.ZERO, false)
	# earth banking over the roof slab (blast / splinter protection)
	var bank := MeshInstance3D.new()
	bank.mesh = GroundKit.prism_mesh(width + 3.0, length + 3.0, 1.6)
	bank.material_override = GroundKit.mat(Color(0.34, 0.4, 0.22), false)
	bank.position = Vector3(0.0, 4.3, 0.0)
	bank.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	root.add_child(bank)
	# baffled entrance at the west end with a blast wall across it
	GroundKit.box(root, Vector3(3.0, 2.6, width * 0.7), Vector3(-length * 0.5 - 1.0, 1.3, 0.0), COL_BRICKWALL.darkened(0.05))
	GroundKit.box(root, Vector3(0.8, 3.2, width + 4.0), Vector3(-length * 0.5 - 4.0, 1.6, 0.0), COL_BRICKWALL.darkened(0.12))
	# ventilation stack and a painted sign board
	GroundKit.cyl(root, 0.5, 0.6, 2.4, Vector3(length * 0.32, 5.4, 0.0), GroundKit.COL_DARK, Vector3.ZERO, 8, false)
	GroundKit.box(root, Vector3(4.0, 1.0, 0.2), Vector3(0.0, 4.0, -width * 0.5 - 0.7), Color(0.9, 0.9, 0.85), Vector3.ZERO, false)


## An Anderson shelter: the small corrugated-steel garden shelter, sunk and mounded with earth, with its
## ribbed curved roof and a sandbagged entrance - the ubiquitous 1939 garden shelter.
static func _anderson_shelter(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var earth: Color = Color(0.34, 0.4, 0.22)
	var length: float = 6.0 + float(size) * 1.2
	var width: float = 2.6
	# the earth mound over the shelter (a low rounded bank) built from stacked slabs
	for i in 5:
		var t: float = float(i) / 4.0
		var w: float = width + 1.6 - t * 2.2
		GroundKit.box(root, Vector3(length + 1.4 - t * 1.2, 0.5, w), Vector3(0.0, 0.25 + t * 0.9, 0.0), earth.lightened(0.03 * float(i)), Vector3.ZERO, false)
	# corrugated steel end of the shelter frame poking out (the ribbed roof)
	for i in 6:
		var zz: float = -length * 0.5 + (float(i) + 0.5) * (length / 6.0)
		GroundKit.box(root, Vector3(width + 0.2, 0.12, 0.12), Vector3(0.0, 2.05, zz), COL_CORRUGATED, Vector3.ZERO, false)
	# the entrance: a short trench with a sandbagged step down
	GroundKit.box(root, Vector3(2.2, 0.6, 2.4), Vector3(0.0, 0.3, length * 0.5 + 1.0), Color(0.3, 0.26, 0.2), Vector3.ZERO, false)
	_sandbag_row(root, 3.0, 0.0, length * 0.5 + 2.0)
	GroundKit.box(root, Vector3(1.4, 1.2, 0.2), Vector3(0.0, 0.6, length * 0.5 + 0.2), GroundKit.COL_DARK, Vector3.ZERO, false)


## An ARP / wardens' post: a small brick-and-concrete control hut with a flat roof, a look-out slit, a sign
## board, a sandbag revetment and a gas-rattle / bell alarm post - the 1939 ARP wardens' posts.
static func _arp_post(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var conc: Color = GroundKit.COL_CONCRETE
	var w: float = 6.0 + float(size)
	var d: float = 5.0 + float(size) * 0.6
	GroundKit.box(root, Vector3(w, 3.2, d), Vector3(0.0, 1.6, 0.0), COL_BRICKWALL)
	GroundKit.box(root, Vector3(w + 1.0, 0.8, d + 1.0), Vector3(0.0, 3.6, 0.0), conc, Vector3.ZERO, false)
	# the look-out slit facing -Z and a doorway
	GroundKit.box(root, Vector3(w * 0.7, 0.7, 0.4), Vector3(0.0, 2.2, -d * 0.5 - 0.1), GroundKit.COL_DARK, Vector3.ZERO, false)
	GroundKit.box(root, Vector3(1.3, 2.4, 0.4), Vector3(-w * 0.28, 1.2, -d * 0.5 - 0.1), GroundKit.COL_DARK, Vector3.ZERO, false)
	# the ARP sign board and a bell / rattle post
	GroundKit.box(root, Vector3(2.6, 1.0, 0.2), Vector3(w * 0.32, 3.6, -d * 0.5 - 0.2), Color(0.9, 0.9, 0.86), Vector3.ZERO, false)
	GroundKit.cyl(root, 0.12, 0.16, 5.0, Vector3(w * 0.5 + 2.0, 2.5, -d * 0.5), GroundKit.COL_WOOD, Vector3.ZERO, 5, false)
	GroundKit.cyl(root, 0.6, 0.7, 0.6, Vector3(w * 0.5 + 2.0, 5.0, -d * 0.5), Color(0.7, 0.6, 0.2), Vector3.ZERO, 8, false)
	# sandbag revetment around the seaward face
	_sandbag_ring(root, Vector3(0.0, 0.0, -d * 0.5), 5, d * 0.5 + 1.2, 0.0)
	# a stirrup pump and a stack of sandbags beside the door
	GroundKit.box(root, Vector3(1.2, 1.0, 1.2), Vector3(w * 0.5 + 1.0, 0.5, d * 0.5), COL_SAND, Vector3.ZERO, false)


## A sandbagged building: a small brick civic / commercial building whose ground floor is piled with sandbags
## and whose entrance is protected by a sandbag blast wall - the 1940 sandbagging of public buildings.
static func _sandbagged_building(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var brick: Color = COL_BRICKWALL.lightened(0.04)
	var roof: Color = Color(0.34, 0.33, 0.35)
	var w: float = 14.0 + float(size) * 4.0
	var d: float = 10.0 + float(size) * 2.0
	GroundKit.box(root, Vector3(w, 8.0, d), Vector3(0.0, 4.0, 0.0), brick)
	var pr := MeshInstance3D.new()
	pr.mesh = GroundKit.prism_mesh(w + 1.0, d + 1.0, 3.4)
	pr.material_override = GroundKit.mat(roof, true)
	pr.position = Vector3(0.0, 8.0, 0.0)
	pr.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	root.add_child(pr)
	# window rows on the upper storey
	for szc in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(w * 0.8, 1.2, 0.3), Vector3(0.0, 6.0, szc * (d * 0.5 + 0.1)), Color(0.24, 0.3, 0.32), Vector3.ZERO, false)
	# sandbags banked against the ground floor on all four sides
	_sandbag_row(root, w * 0.95, 0.0, d * 0.5 + 0.5)
	_sandbag_row(root, w * 0.95, 0.0, -d * 0.5 - 0.5)
	_sandbag_row(root, w * 0.95, 0.45, d * 0.5 + 0.5)
	_sandbag_row(root, w * 0.95, 0.45, -d * 0.5 - 0.5)
	for i in 6:
		var zz: float = -d * 0.5 + (float(i) + 0.5) * (d / 6.0)
		GroundKit.box(root, Vector3(0.7, 0.45, 1.1), Vector3(w * 0.5 + 0.5, 0.22, zz), COL_SAND, Vector3.ZERO, false)
		GroundKit.box(root, Vector3(0.7, 0.45, 1.1), Vector3(-w * 0.5 - 0.5, 0.22, zz), COL_SAND, Vector3.ZERO, false)
	# the entrance with a sandbag wall either side
	GroundKit.box(root, Vector3(2.0, 3.2, 0.4), Vector3(0.0, 1.6, -d * 0.5 - 0.1), GroundKit.COL_DARK, Vector3.ZERO, false)
	_sandbag_row(root, 4.0, 0.0, -d * 0.5 - 2.0)


## A camouflage-painted factory roof (P15): a disruptive "CVD" camouflage paint pattern laid as flat painted
## panels over the works footprint, driven off the existing industry / aircraft-industry site (pass its world
## centre, yaw, size and seed). Deterministic from seed_v. Returns the container to add to the site node.
static func camouflage_roof(pos: Vector3, heading_deg: float, size: int, seed_v: int) -> Node3D:
	var container := Node3D.new()
	var root := Node3D.new()
	var y: float = 9.0 + float(clampi(size, 1, 3)) * 2.5
	root.position = Vector3(pos.x, y, pos.z)
	root.rotation.y = -deg_to_rad(heading_deg)
	container.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	# a disruptive-pattern paint: broad tan / green / brown panels on the roof plane, sized to the works
	var cols: int = 4 + clampi(size, 1, 3)
	var rows: int = 3 + clampi(size, 1, 3)
	var pw: float = 26.0
	var pd: float = 22.0
	var colours: Array = [Color(0.52, 0.48, 0.34), Color(0.34, 0.4, 0.26), Color(0.44, 0.36, 0.24), Color(0.4, 0.4, 0.34)]
	for r in rows:
		for c in cols:
			var col: Color = colours[(r * 3 + c + seed_v % 4) % colours.size()].lightened(rng.randf_range(-0.03, 0.03))
			var px: float = (float(c) - float(cols - 1) * 0.5) * pw
			var pz: float = (float(r) - float(rows - 1) * 0.5) * pd
			GroundKit.box(root, Vector3(pw * 0.94, 0.5, pd * 0.94), Vector3(px, 0.0, pz), col, Vector3.ZERO, false)
	return container
