class_name SeaDefenceKit
extends RefCounted
## 1940s sea defences (P1): buoyed moored-mine lines, anti-submarine booms and steel nets across
## harbour/estuary mouths, blockships, offshore beach obstacles just below the tide line, and wreck buoys.
## All procedural low-poly toon from GroundKit primitives - no photo textures, no new assets.
##
## Every builder returns a container at the WORLD ORIGIN whose child `root` sits at the site, oriented so
## local -Z runs ALONG the defence line (the heading the site data gives), matching the WorldFeatures
## convention (`root.rotation.y = -deg_to_rad(heading)`). The whole set is driven from
## data/sea_defences_1940.json by WorldPopulator._register_sea_defences():
##   SeaDefenceKit.build(kind, style, pos, heading_deg, length_m, rows, seed_v) -> Node3D

const COL_MINE := Color(0.13, 0.13, 0.14)
const COL_NET := Color(0.16, 0.17, 0.18)


## Root that carries the site: sits at (pos.x, 0, pos.z) so the defence floats on the sea plane (y = 0).
static func _root(container: Node3D, pos: Vector3, heading_deg: float) -> Node3D:
	var r := Node3D.new()
	r.position = Vector3(pos.x, 0.0, pos.z)
	r.rotation.y = -deg_to_rad(heading_deg)
	container.add_child(r)
	return r


## A channel-marker / wreck buoy: a can buoy floating at p with a lattice mast and a light.
static func _buoy(root: Node3D, p: Vector3, col: Color) -> void:
	GroundKit.cyl(root, 1.05, 1.35, 3.2, p + Vector3(0.0, 1.2, 0.0), col, Vector3.ZERO, 8)
	GroundKit.cyl(root, 0.09, 0.09, 4.2, p + Vector3(0.0, 4.0, 0.0), GroundKit.COL_DARK, Vector3.ZERO, 4, false)
	GroundKit.sphere(root, 0.55, p + Vector3(0.0, 6.3, 0.0), Color(0.95, 0.86, 0.24), Vector3.ONE, false)


## Central dispatch, driven by the `kind` in data/sea_defences_1940.json.
static func build(kind: String, style: String, pos: Vector3, heading_deg: float, length_m: float, rows: int, seed_v: int) -> Node3D:
	match kind:
		"minefield":
			return build_minefield(pos, heading_deg, length_m, rows, seed_v)
		"boom":
			return build_boom(pos, heading_deg, length_m, seed_v)
		"blockship":
			return build_blockship(pos, heading_deg, seed_v)
		"sea_fort":
			return build_sea_fort(style, pos, seed_v)
		"obstacles":
			return build_obstacles(pos, heading_deg, length_m, seed_v)
		"wreck":
			return build_wreck(pos, heading_deg, seed_v)
		"breakwater":
			return build_breakwater(pos, heading_deg, length_m, seed_v)
	var container := Node3D.new()
	_root(container, pos, heading_deg)
	return container


## A moored-mine line: rows of horned mines just below the surface on mooring wires, with the ends and every
## few hundred metres marked by buoys (a buoyed channel through a swept gap is what the gaps imply).
static func build_minefield(pos: Vector3, heading_deg: float, length_m: float, rows: int, seed_v: int) -> Node3D:
	var container := Node3D.new()
	var root: Node3D = _root(container, pos, heading_deg)
	var half: float = length_m * 0.5
	var spacing: float = 110.0
	var n: int = maxi(int(length_m / spacing), 2)
	var r: int = maxi(rows, 1)
	for rr in r:
		var offx: float = (float(rr) - float(r - 1) * 0.5) * 70.0
		for i in n + 1:
			var z: float = -half + float(i) * (length_m / float(n))
			GroundKit.sphere(root, 1.5, Vector3(offx, -0.9, z), COL_MINE, Vector3.ONE, false)                 # mine body, awash
			for a in [0.0, 90.0]:
				GroundKit.cyl(root, 0.12, 0.12, 2.2, Vector3(offx, -0.3, z), COL_MINE, Vector3(90.0, a, 0.0), 4, false)   # horns
			GroundKit.cyl(root, 0.06, 0.06, 7.0, Vector3(offx, -4.2, z), Color(0.18, 0.18, 0.18), Vector3.ZERO, 4, false)  # mooring wire
	for e in [-1.0, 1.0]:
		_buoy(root, Vector3(0.0, 0.0, e * (half + 12.0)), Color(0.78, 0.14, 0.1))
	var nb: int = maxi(n / 8, 1)
	for i in nb + 1:
		var z2: float = -half + float(i) * (length_m / float(nb))
		_buoy(root, Vector3(float(r - 1) * 70.0 * 0.5 + 26.0, 0.0, z2), Color(0.15, 0.15, 0.16))
	return container


## An anti-submarine boom and steel net across a harbour/estuary mouth: steel floats joined by booms with net
## panels hanging below, a boom-gate gap in the middle where vessels pass, and mooring dolphins at the ends.
static func build_boom(pos: Vector3, heading_deg: float, length_m: float, seed_v: int) -> Node3D:
	var container := Node3D.new()
	var root: Node3D = _root(container, pos, heading_deg)
	var half: float = length_m * 0.5
	var spacing: float = 26.0
	var n: int = maxi(int(length_m / spacing), 2)
	var steel := Color(0.3, 0.32, 0.34)
	var gate: int = n / 2
	for i in n + 1:
		if absi(i - gate) < 3:
			continue                                          # boom gate opening
		var z: float = -half + float(i) * (length_m / float(n))
		GroundKit.cyl(root, 1.0, 1.2, 2.0, Vector3(0.0, 0.6, z), steel, Vector3.ZERO, 8)             # steel float
		GroundKit.box(root, Vector3(2.6, 0.5, 2.4), Vector3(0.0, 1.7, z), steel.darkened(0.2))       # float deck
		if i % 3 == 0:
			GroundKit.box(root, Vector3(1.4, 7.0, spacing - 1.5), Vector3(0.0, -3.6, z), COL_NET, Vector3.ZERO, false)  # hanging net
	for e in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(4.0, 3.4, 4.0), Vector3(0.0, 1.6, e * (half + 6.0)), Color(0.42, 0.42, 0.4))     # mooring dolphin
		GroundKit.cyl(root, 0.5, 0.6, 6.0, Vector3(0.0, 3.0, e * (half + 6.0)), GroundKit.COL_WOOD, Vector3.ZERO, 5, false)
	for g in [-1.0, 1.0]:
		var gz: float = -half + (float(gate) + g * 3.0) * (length_m / float(n))
		GroundKit.box(root, Vector3(3.0, 2.6, 3.0), Vector3(0.0, 1.3, gz), Color(0.5, 0.5, 0.46))     # gate piers
	# stone breakwater / mole ends anchoring the line where it meets the shore or a mole
	for e2 in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(15.0, 6.5, 26.0), Vector3(0.0, 2.0, e2 * (half + 20.0)), Color(0.5, 0.5, 0.46), Vector3.ZERO, false)
		GroundKit.box(root, Vector3(16.0, 1.4, 28.0), Vector3(0.0, 6.0, e2 * (half + 20.0)), Color(0.56, 0.55, 0.5), Vector3.ZERO, false)
		GroundKit.cyl(root, 0.9, 1.2, 8.0, Vector3(0.0, 10.5, e2 * (half + 20.0)), Color(0.88, 0.86, 0.82), Vector3.ZERO, 8)
	return container


## A scuttled blockship: an obsolete cruiser filled with concrete, lying across a channel half-submerged,
## listing to one side, with a funnel and masts standing out of the water.
static func build_blockship(pos: Vector3, heading_deg: float, seed_v: int) -> Node3D:
	var container := Node3D.new()
	var root: Node3D = _root(container, pos, heading_deg)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var list_deg: float = rng.randf_range(14.0, 22.0) * (1.0 if rng.randf() < 0.5 else -1.0)
	var hull := Color(0.19, 0.2, 0.22)
	var rust := Color(0.32, 0.24, 0.18)
	var rot := Vector3(0.0, 0.0, list_deg)
	GroundKit.box(root, Vector3(11.0, 7.0, 46.0), Vector3(0.0, -0.4, 0.0), hull, rot)
	GroundKit.box(root, Vector3(9.0, 1.2, 42.0), Vector3(0.0, 3.2, 0.0), rust, rot, false)             # awash weather deck
	GroundKit.box(root, Vector3(6.0, 5.0, 10.0), Vector3(0.0, 4.4, -8.0), hull.lightened(0.08), rot)   # bridge superstructure
	GroundKit.cyl(root, 1.6, 1.9, 7.0, Vector3(0.0, 6.5, 2.0), Color(0.14, 0.14, 0.15), rot, 8)        # funnel
	GroundKit.cyl(root, 0.2, 0.26, 18.0, Vector3(0.0, 8.0, -14.0), rust, rot, 5)                        # foremast
	GroundKit.cyl(root, 0.2, 0.26, 15.0, Vector3(0.0, 7.0, 14.0), rust, rot, 5)                         # mainmast
	GroundKit.box(root, Vector3(3.0, 1.0, 3.0), Vector3(0.0, 9.0, -14.0), Color(0.4, 0.12, 0.1))       # tattered ensign
	return container


## A sea fort: the Maunsell army/navy forts reuse WorldFeatures.build_sea_fort(kind); `tower` builds the
## mid-19th-century round granite gun tower (Grain Tower) that still guarded the Medway in 1940.
static func build_sea_fort(style: String, pos: Vector3, seed_v: int) -> Node3D:
	var container := Node3D.new()
	if style == "tower":
		var t: Node3D = build_tower_fort()
		t.position = Vector3(pos.x, 0.0, pos.z)
		t.rotation.y = float(seed_v % 360) * PI / 180.0
		container.add_child(t)
		return container
	var root: Node3D = _root(container, pos, float(seed_v % 360))
	root.add_child(WorldFeatures.build_sea_fort(style))
	return container


## Round granite gun tower on a tidal sandbank (Grain Tower silhouette): battered shaft, gun embrasures,
## a parapet, and a Second World War fire-director tower added on the top.
static func build_tower_fort() -> Node3D:
	var root := Node3D.new()
	var stone := Color(0.5, 0.48, 0.44)
	GroundKit.cyl(root, 9.0, 11.0, 14.0, Vector3(0.0, 5.0, 0.0), stone, Vector3.ZERO, 14)
	GroundKit.cyl(root, 10.2, 10.2, 1.6, Vector3(0.0, 12.6, 0.0), stone.darkened(0.12), Vector3.ZERO, 14)
	for i in 10:
		var a: float = TAU * float(i) / 10.0
		GroundKit.box(root, Vector3(1.4, 1.6, 1.4), Vector3(cos(a) * 9.2, 13.6, sin(a) * 9.2), stone)
	GroundKit.cyl(root, 3.0, 3.4, 7.0, Vector3(0.0, 17.5, 0.0), Color(0.58, 0.58, 0.55), Vector3.ZERO, 10)
	GroundKit.box(root, Vector3(5.0, 1.2, 5.0), Vector3(0.0, 21.4, 0.0), Color(0.34, 0.34, 0.36), Vector3.ZERO, false)
	return root


## Offshore beach obstacles below the tide line: rows of Czech hedgehogs and scaffolding / girder frames
## sitting awash just off the beach, exactly the 1944 obstacle belt seen from the air.
static func build_obstacles(pos: Vector3, heading_deg: float, span_m: float, seed_v: int) -> Node3D:
	var container := Node3D.new()
	var root: Node3D = _root(container, pos, heading_deg)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var half: float = span_m * 0.5
	var hh: Array = []
	for row in 5:
		var z: float = -half + float(row) * (span_m / 5.0)
		var oy: float = -0.3 - float(row) * 1.1
		for i in 14:
			var x: float = (float(i) - 6.5) * 7.0 + rng.randf_range(-1.5, 1.5)
			var ox: float = z + rng.randf_range(-2.0, 2.0)
			if i % 2 == 0:
				hh.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, oy, ox)))
			else:
				var h := Node3D.new()
				h.position = Vector3(x, oy, ox)
				h.rotation.y = rng.randf() * TAU
				root.add_child(h)
				GroundKit.box(h, Vector3(0.4, 5.0, 0.4), Vector3(-1.6, 1.0, 0.0), Color(0.28, 0.2, 0.14), Vector3.ZERO, false)
				GroundKit.box(h, Vector3(0.4, 5.0, 0.4), Vector3(1.6, 1.0, 0.0), Color(0.28, 0.2, 0.14), Vector3.ZERO, false)
				GroundKit.box(h, Vector3(0.3, 5.6, 0.3), Vector3(0.0, 1.0, 0.0), Color(0.28, 0.2, 0.14), Vector3(0.0, 0.0, 40.0), false)
	if not hh.is_empty():
		root.add_child(Scatter.multi(Scatter.hedgehog_mesh(), hh, 5000.0))
	return container


## A marked wreck on a shoal or approach: a submerged hull on the sea bed with a mast still standing and a
## wreck buoy on the surface marking the hazard.
static func build_wreck(pos: Vector3, heading_deg: float, seed_v: int) -> Node3D:
	var container := Node3D.new()
	var root: Node3D = _root(container, pos, heading_deg)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var yaw: float = rng.randf_range(-20.0, 20.0)
	GroundKit.box(root, Vector3(9.0, 5.0, 34.0), Vector3(0.0, -3.0, 0.0), Color(0.16, 0.15, 0.14), Vector3(0.0, yaw, 8.0))
	GroundKit.box(root, Vector3(6.0, 2.0, 9.0), Vector3(0.0, -0.6, -6.0), Color(0.18, 0.16, 0.15), Vector3(0.0, yaw, 10.0))
	GroundKit.cyl(root, 0.2, 0.28, 16.0, Vector3(-2.0, 5.0, 6.0), Color(0.24, 0.2, 0.18), Vector3(0.0, yaw, 12.0), 5)
	_buoy(root, Vector3(0.0, 0.0, 0.0), Color(0.16, 0.5, 0.2))
	GroundKit.cyl(root, 0.5, 0.5, 1.2, Vector3(0.0, 6.9, 0.0), Color(0.95, 0.85, 0.2), Vector3.ZERO, 8, false)
	return container


## A rubble-mound breakwater / mole across a harbour mouth: a wide seaward face with rock toes, a level
## crest, a rounded head carrying a harbour light, and a return arm back to the shore. Local -Z runs along
## the breakwater (the site heading).
static func build_breakwater(pos: Vector3, heading_deg: float, length_m: float, seed_v: int) -> Node3D:
	var container := Node3D.new()
	var root: Node3D = _root(container, pos, heading_deg)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var stone := Color(0.5, 0.5, 0.46)
	var l: float = maxf(length_m, 140.0)
	var n_toe: int = maxi(1, int(l / 26.0))
	GroundKit.box(root, Vector3(l, 8.0, 26.0), Vector3(0.0, 2.4, 0.0), stone, Vector3.ZERO, false)                       # core
	GroundKit.box(root, Vector3(l + 4.0, 2.0, 15.0), Vector3(0.0, 7.2, 0.0), stone.lightened(0.05), Vector3.ZERO, false)  # crest
	for i in n_toe:
		var bx: float = -l * 0.5 + (float(i) + 0.5) * (l / float(n_toe))
		GroundKit.box(root, Vector3(12.0, 3.0, 8.0), Vector3(bx, 0.8, -14.0), stone.darkened(0.08), Vector3(0.0, 0.0, rng.randf_range(-7.0, 7.0)), false)   # rock toes
	var hd: float = l * 0.5
	GroundKit.cyl(root, 12.0, 14.0, 7.0, Vector3(hd, 2.6, 0.0), stone, Vector3.ZERO, 14)                                  # rounded head
	GroundKit.cyl(root, 1.0, 1.4, 10.0, Vector3(hd, 11.0, 0.0), Color(0.88, 0.86, 0.82), Vector3.ZERO, 8)
	GroundKit.cyl(root, 1.2, 1.2, 2.2, Vector3(hd, 15.2, 0.0), Color(0.9, 0.85, 0.5), Vector3.ZERO, 8, false)             # light
	GroundKit.cyl(root, 0.0, 1.6, 2.4, Vector3(hd, 17.5, 0.0), GroundKit.COL_DARK, Vector3.ZERO, 8, false)
	return container
