class_name AviationSupportKit
extends RefCounted
## P16 aviation support: the 1940 seaplane / flying-boat stations (the Sunderland bases), the airship / blimp
## mooring stations and the kite-balloon sites, from data/aviation_support_1940.json. All procedural low-poly
## toon from GroundKit primitives plus the shared AirfieldAssets hangar/nissen meshes and the existing
## BarrageBalloon for the kite balloons - no photo textures, no new assets.
##
##   var n: Node3D = AviationSupportKit.build(kind, pos, heading_deg, size, seed_v)   # node sits at world ORIGIN
##
## The returned container holds a `root` at (pos.x, ground_y, pos.z) rotated so local -Z faces the site's
## heading (the WorldFeatures / GroundStructure convention). Deterministic from seed_v. Driven from
## data/aviation_support_1940.json by WorldPopulator._register_aviation_support().

## The aviation-support kinds this kit understands.
static func kinds() -> Array:
	return ["seaplane_base", "airship_station", "kite_balloon_site"]


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
		"airship_station":
			_airship_station(root, container, pos, sz, rng)
		"kite_balloon_site":
			_kite_balloon_site(root, container, pos, sz, rng)
		_:
			_seaplane_base(root, container, pos, sz, rng)
	return container


# ------------------------------------------------------------------ helpers
## Terrain height at a local point of `root` (root is at the world origin's XZ with a yaw).
static func _gh(root: Node3D, local: Vector3) -> float:
	var w: Vector3 = root.transform * local
	return GroundKit.ground_y(w.x, w.z)


## One instance of a shared mesh (a T2 hangar / Nissen hut) at a local point on the ground.
static func _inst(root: Node3D, mesh: Mesh, local: Vector3, yaw_deg: float) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(local.x, _gh(root, local), local.z)
	mi.rotation.y = deg_to_rad(yaw_deg)
	root.add_child(mi)


## A curved shed roof: angled slabs spanning a width, base at `base_y` and rising `rise`.
static func _arched_roof(root: Node3D, length: float, width: float, rise: float, base_y: float, col: Color) -> void:
	var n: int = 7
	for i in n:
		var a0: float = PI * float(i) / float(n)
		var a1: float = PI * float(i + 1) / float(n)
		var x0: float = cos(a0) * width * 0.5
		var y0: float = sin(a0) * rise
		var x1: float = cos(a1) * width * 0.5
		var y1: float = sin(a1) * rise
		var mid := Vector3((x0 + x1) * 0.5, base_y + (y0 + y1) * 0.5, 0.0)
		var seg: float = Vector2(x1 - x0, y1 - y0).length()
		var ang: float = rad_to_deg(atan2(y1 - y0, x1 - x0))
		GroundKit.box(root, Vector3(seg + 0.3, 0.7, length), mid, col, Vector3(0, 0, ang), false)


## A moored four-engined flying boat (a Sunderland silhouette) on the water, world-space in `container`.
## `wp` is a world position and `hdg` the heading (deg) it rides to.
static func _flying_boat(container: Node3D, wp: Vector3, hdg: float) -> void:
	var h := Node3D.new()
	h.position = Vector3(wp.x, 1.4, wp.z)
	h.rotation.y = -deg_to_rad(hdg)
	container.add_child(h)
	var cream: Color = Color(0.72, 0.74, 0.72)
	GroundKit.box(h, Vector3(4.4, 2.6, 26.0), Vector3(0, 0, 0), cream)                                   # hull
	GroundKit.box(h, Vector3(3.2, 1.2, 6.0), Vector3(0, 2.0, -9.0), cream.darkened(0.06))                  # cabin / step
	GroundKit.box(h, Vector3(2.2, 2.0, 5.0), Vector3(0, 4.0, -10.0), cream.darkened(0.1))                  # flight deck
	GroundKit.box(h, Vector3(36.0, 0.6, 5.4), Vector3(0, 2.2, -1.0), cream)                               # wing
	GroundKit.box(h, Vector3(9.0, 0.5, 2.4), Vector3(0, 2.6, 12.0), cream.darkened(0.05))                  # tailplane
	GroundKit.box(h, Vector3(0.5, 3.0, 3.0), Vector3(0, 4.0, 12.6), cream)                                # fin
	for ex in [-8.0, 8.0]:
		GroundKit.cyl(h, 0.9, 0.9, 3.4, Vector3(ex, 1.6, -3.0), cream.darkened(0.12), Vector3(90, 0, 0), 8)   # engine nacelle
		GroundKit.cyl(h, 1.6, 1.6, 0.2, Vector3(ex, 1.6, -4.8), Color(0.16, 0.16, 0.18), Vector3(90, 0, 0), 10, false)


# ------------------------------------------------------------------ kinds
## A seaplane / flying-boat station (a Sunderland station): an inclined slipway down to the water, a concrete
## apron, T2 hangars, a control / watch office, a beaching crane, mooring buoys and a moored flying boat.
static func _seaplane_base(root: Node3D, container: Node3D, pos: Vector3, size: int, rng: RandomNumberGenerator) -> void:
	var conc: Color = GroundKit.COL_CONCRETE
	var stone: Color = Color(0.44, 0.44, 0.42)
	var W: float = 120.0 + 40.0 * float(size)
	# concrete apron on the landward side
	GroundKit.box(root, Vector3(W, 0.5, 105.0), Vector3(0, _gh(root, Vector3.ZERO) + 0.25, 34.0), conc.darkened(0.06), Vector3.ZERO, false)
	# the slipway: an inclined ramp running out to the water (local -Z), with side walls and a winch house
	var slip := MeshInstance3D.new()
	var sbm := BoxMesh.new()
	sbm.size = Vector3(36.0, 1.4, 105.0)
	slip.mesh = sbm
	slip.material_override = GroundKit.mat(conc, true)
	slip.position = Vector3(0, -3.0, -62.0)
	slip.rotation_degrees = Vector3(7.0, 0.0, 0.0)
	root.add_child(slip)
	for sx in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(2.0, 3.0, 100.0), Vector3(sx * 19.0, -1.0, -60.0), stone, Vector3(7.0, 0.0, 0.0), false)
	GroundKit.box(root, Vector3(10.0, 7.0, 9.0), Vector3(-28.0, _gh(root, Vector3(-28.0, 0.0, -6.0)) + 3.5, -6.0), GroundKit.COL_BRICK)      # winch house
	GroundKit.cyl(root, 0.7, 0.9, 3.0, Vector3(-28.0, _gh(root, Vector3(-28.0, 0.0, -6.0)) + 8.0, -6.0), GroundKit.COL_STEEL, Vector3(90, 0, 0), 8)
	# T2 hangars on the technical side
	var t2: Mesh = AirfieldAssets.t2_hangar("Allies")
	for i in 2 + size:
		_inst(root, t2, Vector3(-60.0 + float(i) * 74.0, 0.0, 60.0), 0.0)
	# control / watch office, a stores hut and a beaching crane beside the slip
	var h := Node3D.new()
	h.position = Vector3(58.0, 0.0, 6.0)
	root.add_child(h)
	GroundKit.box(h, Vector3(13.0, 4.0, 10.0), Vector3(0.0, _gh(root, Vector3(58.0, 0.0, 6.0)) + 4.0, 0.0), GroundKit.COL_BRICK.darkened(0.06))
	GroundKit.box(h, Vector3(10.0, 3.0, 7.0), Vector3(0.0, _gh(root, Vector3(58.0, 0.0, 6.0)) + 7.0, 0.0), Color(0.16, 0.2, 0.22), Vector3.ZERO, false)
	GroundKit.cyl(h, 0.1, 0.12, 7.0, Vector3(5.0, _gh(root, Vector3(58.0, 0.0, 6.0)) + 10.0, 0.0), GroundKit.COL_STEEL, Vector3.ZERO, 4, false)
	GroundKit.box(root, Vector3(7.0, 20.0, 7.0), Vector3(30.0, _gh(root, Vector3(30.0, 0.0, 6.0)) + 10.0, 6.0), Color(0.7, 0.18, 0.12))
	GroundKit.box(root, Vector3(3.0, 3.0, 30.0), Vector3(30.0, _gh(root, Vector3(30.0, 0.0, 6.0)) + 20.0, -9.0), Color(0.7, 0.18, 0.12), Vector3(-10.0, 0.0, 0.0))
	# mooring buoys out on the water
	for i in 3 + size:
		var bz: float = -130.0 - float(i) * 22.0
		GroundKit.sphere(root, 1.6, Vector3((float(i % 3) - 1.0) * 26.0, 0.6, bz), Color(0.85, 0.72, 0.2))
		GroundKit.cyl(root, 0.2, 0.2, 2.0, Vector3((float(i % 3) - 1.0) * 26.0, 1.8, bz), GroundKit.COL_DARK, Vector3.ZERO, 4, false)
	# a moored flying boat out on the water
	var sea: Vector3 = GroundKit.water_dir(pos, 500.0)
	var shdg: float = WorldCoords.dir_to_heading(sea) if sea != Vector3.ZERO else 0.0
	var sdir: Vector3 = WorldCoords.heading_to_dir(shdg)
	var wp: Vector3 = Vector3(pos.x + sdir.x * 150.0, 0.0, pos.z + sdir.z * 150.0)
	if GroundKit.is_water(wp.x, wp.z):
		_flying_boat(container, wp, shdg + 90.0)


## An airship / blimp mooring station: a long airship shed with big doors and a curved roof, a tall lattice
## mooring mast with a gantry, a hydrogen store, a windbreak and a hut line.
static func _airship_station(root: Node3D, container: Node3D, pos: Vector3, size: int, rng: RandomNumberGenerator) -> void:
	var steel: Color = Color(0.5, 0.52, 0.5)
	var wall: Color = Color(0.46, 0.46, 0.42)
	var shed_l: float = 150.0 + 40.0 * float(size)
	var shed_w: float = 60.0 + 12.0 * float(size)
	var shed_h: float = 40.0
	var sy: float = _gh(root, Vector3(0.0, 0.0, 40.0))
	# the shed body, a curved roof and a big door front (local -Z)
	GroundKit.box(root, Vector3(shed_w, shed_h, shed_l), Vector3(0.0, sy + shed_h * 0.5, 40.0), wall)
	_arched_roof(root, shed_l, shed_w, 16.0, sy + shed_h, wall.darkened(0.18))
	GroundKit.box(root, Vector3(shed_w * 0.9, shed_h * 0.9, 1.4), Vector3(0.0, sy + shed_h * 0.45, 40.0 - shed_l * 0.5), GroundKit.COL_DARK, Vector3.ZERO, false)
	for sx in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(1.6, shed_h, 1.6), Vector3(sx * shed_w * 0.5, sy + shed_h * 0.5, 40.0 - shed_l * 0.5), wall.darkened(0.1))
	# the mooring mast: a tall lattice mast with a gantry and a winch
	var mast_h: float = 62.0
	var my: float = _gh(root, Vector3(0.0, 0.0, -46.0))
	GroundKit.cyl(root, 1.0, 2.2, mast_h, Vector3(0.0, my + mast_h * 0.5, -46.0), steel, Vector3.ZERO, 8)
	for sx2 in [-1.0, 1.0]:
		for sz2 in [-1.0, 1.0]:
			GroundKit.cyl(root, 0.3, 0.5, mast_h * 0.98, Vector3(sx2 * 4.0, my + mast_h * 0.49, -46.0 + sz2 * 4.0), steel.darkened(0.12), Vector3.ZERO, 4, false)
	GroundKit.box(root, Vector3(16.0, 1.6, 16.0), Vector3(0.0, my + mast_h, -46.0), steel)                      # gantry platform
	GroundKit.box(root, Vector3(3.0, 3.0, 3.0), Vector3(0.0, my + mast_h + 2.0, -46.0), GroundKit.COL_DARK, Vector3.ZERO, false)
	GroundKit.cyl(root, 0.5, 0.7, 8.0, Vector3(0.0, my + 5.0, -46.0), GroundKit.COL_DARK.lightened(0.2), Vector3(90, 0, 0), 6)   # winch drum
	# hydrogen / gas store: cylinders in a bund
	for i in 3 + size:
		GroundKit.cyl(root, 2.6, 2.6, 12.0, Vector3(-46.0, _gh(root, Vector3(-46.0, 0.0, -30.0 + float(i) * 9.0)) + 6.0, -30.0 + float(i) * 9.0), steel.darkened(0.06), Vector3(0, 0, 90), 10)
	# windbreak wall to windward and a Nissen hut line
	var nis: Mesh = AirfieldAssets.nissen("Allies")
	for i in 4:
		_inst(root, nis, Vector3(46.0, 0.0, -20.0 + float(i) * 13.0), PI * 0.5)
	GroundKit.box(root, Vector3(1.2, 4.0, 120.0), Vector3(-64.0, _gh(root, Vector3(-64.0, 0.0, 0.0)) + 2.0, 10.0), Color(0.36, 0.34, 0.28), Vector3.ZERO, false)
	# a moored airship alongside the mast (silver ellipsoid + fins)
	var ar: Node3D = Node3D.new()
	ar.position = Vector3(0.0, my + mast_h + 6.0, -46.0)
	root.add_child(ar)
	GroundKit.sphere(ar, 22.0, Vector3(0.0, 0.0, 0.0), Color(0.72, 0.75, 0.78), Vector3(1.0, 1.0, 3.6))
	for a in [0.0, 120.0, 240.0]:
		GroundKit.box(ar, Vector3(0.5, 8.0, 8.0), Vector3(0.0, 0.0, 74.0), Color(0.6, 0.62, 0.64), Vector3(0, 0, a), false)
	GroundKit.box(ar, Vector3(2.0, 3.0, 6.0), Vector3(0.0, -24.0, 0.0), Color(0.85, 0.86, 0.84))                # gondola


## A kite-balloon site: a balloon shed with a curved roof, a winch lorry, an apron and kite balloons on cables.
static func _kite_balloon_site(root: Node3D, container: Node3D, pos: Vector3, size: int, rng: RandomNumberGenerator) -> void:
	var conc: Color = GroundKit.COL_CONCRETE
	var sy: float = _gh(root, Vector3(0.0, 0.0, 0.0))
	# balloon shed: a long low shed with a curved roof and an open door
	GroundKit.box(root, Vector3(46.0, 12.0, 24.0), Vector3(0.0, sy + 6.0, 18.0), conc.darkened(0.1))
	_arched_roof(root, 24.0, 46.0, 8.0, sy + 12.0, Color(0.4, 0.42, 0.4))
	GroundKit.box(root, Vector3(13.0, 10.0, 0.6), Vector3(0.0, sy + 5.0, 5.6), GroundKit.COL_DARK, Vector3.ZERO, false)
	# apron and a wind stocking
	GroundKit.box(root, Vector3(90.0, 0.4, 60.0), Vector3(0.0, sy + 0.2, -6.0), conc.darkened(0.08), Vector3.ZERO, false)
	GroundKit.cyl(root, 0.15, 0.2, 9.0, Vector3(40.0, sy + 4.5, -30.0), GroundKit.COL_STEEL, Vector3.ZERO, 5, false)
	GroundKit.cyl(root, 1.6, 1.6, 4.0, Vector3(40.0, sy + 9.0, -32.0), Color(0.85, 0.5, 0.2), Vector3(90, 0, 0), 8, false)
	# winch lorries
	var truck: Mesh = AirfieldAssets.truck("Allies")
	for i in 1 + size:
		_inst(root, truck, Vector3(-30.0 + float(i) * 16.0, 0.0, -22.0), 0.0)
		GroundKit.cyl(root, 0.6, 0.8, 2.4, Vector3(-30.0 + float(i) * 16.0, _gh(root, Vector3(-30.0, 0.0, -22.0)) + 2.6, -26.0), GroundKit.COL_DARK, Vector3(0, 0, 90), 8, false)
	# kite balloons on their cables (deterministic positions around the apron)
	var alt_m: float = 500.0 + float(size) * 120.0
	for i in 2 + size:
		var a: float = TAU * float(i) / float(2 + size) + rng.randf_range(-0.2, 0.2)
		var r: float = 70.0 + rng.randf_range(0.0, 40.0)
		var wp: Vector3 = root.transform * Vector3(cos(a) * r, 0.0, -20.0 + sin(a) * r)
		if GroundKit.raw_y(wp.x, wp.z) < 0.6:
			continue
		var bb: BarrageBalloon = BarrageBalloon.create("Allies", alt_m * WorldCoords.VERTICAL_SCALE)
		bb.position = Vector3(wp.x, GroundKit.ground_y(wp.x, wp.z) + bb.altitude, wp.z)
		container.add_child(bb)
