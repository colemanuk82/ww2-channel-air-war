class_name NavigationAidKit
extends RefCounted
## P18 navigation aids: the radio-range beacons, the direction-finding (DF) stations, the tall beacon / broadcast
## masts (Rugby, Droitwich) and the outer approach-lighting arrays for night sorties, from
## data/navigation_aids_1940.json. All procedural low-poly toon from GroundKit primitives - no photo textures,
## no new assets.
##
##   var n: Node3D = NavigationAidKit.build(kind, pos, heading_deg, size, seed_v)   # node sits at world ORIGIN
##
## The returned container holds a `root` at (pos.x, ground_y, pos.z) rotated so local -Z faces the site's
## heading (the WorldFeatures / GroundStructure convention). Deterministic from seed_v. Driven from
## data/navigation_aids_1940.json by WorldPopulator._register_navigation_aids().

## The navigation-aid kinds this kit understands.
static func kinds() -> Array:
	return ["radio_beacon", "df_station", "beacon_mast", "night_lighting"]


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
		"df_station":
			_df_station(root, sz, rng)
		"beacon_mast":
			_beacon_mast(root, sz, rng)
		"night_lighting":
			_night_lighting(root, sz, rng)
		_:
			_radio_beacon(root, sz, rng)
	return container


# ------------------------------------------------------------------ helpers
## Terrain height at a local point of `root` (root is at the world origin's XZ with a yaw).
static func _gh(root: Node3D, local: Vector3) -> float:
	var w: Vector3 = root.transform * local
	return GroundKit.ground_y(w.x, w.z)


## A circular earth / concrete aerial mat (a flat disc) under an aerial array.
static func _earth_mat(root: Node3D, radius: float) -> void:
	var gy: float = _gh(root, Vector3.ZERO)
	GroundKit.cyl(root, radius, radius, 0.3, Vector3(0.0, gy + 0.15, 0.0), Color(0.42, 0.4, 0.34), Vector3.ZERO, 24, false)


## A thin beam (a box) spanning two local points of `root`, so a stay wire reads as a real line.
static func _beam(root: Node3D, a: Vector3, b: Vector3, thickness: float, col: Color) -> void:
	var dir: Vector3 = b - a
	var ln: float = dir.length()
	if ln < 0.01:
		return
	var up: Vector3 = Vector3.UP
	var x_axis: Vector3 = dir.cross(up)
	if x_axis.length() < 0.001:
		x_axis = Vector3.RIGHT
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(dir).normalized()
	var y_axis: Vector3 = dir / ln
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thickness, ln, thickness)
	mi.mesh = bm
	mi.material_override = GroundKit.mat(col, false)
	mi.transform = Transform3D(Basis(x_axis, y_axis, z_axis), (a + b) * 0.5)
	root.add_child(mi)


## A guyed mast: a central lattice post of height `h` at `local`, with `guys` stay wires to anchor blocks.
static func _guyed_mast(root: Node3D, local: Vector3, h: float, guys: int, col: Color) -> void:
	var gy: float = _gh(root, local)
	GroundKit.cyl(root, h * 0.02 + 0.2, h * 0.03 + 0.35, h, Vector3(local.x, gy + h * 0.5, local.z), col, Vector3.ZERO, 6)
	# two cross-braces so the mast reads as a lattice
	for fy in [0.4, 0.75]:
		GroundKit.box(root, Vector3(1.2, 0.4, 1.2), Vector3(local.x, gy + h * float(fy), local.z), col.darkened(0.1), Vector3.ZERO, false)
	for i in guys:
		var a: float = TAU * float(i) / float(maxi(guys, 1))
		var ax: float = local.x + cos(a) * h * 0.35
		var az: float = local.z + sin(a) * h * 0.35
		var ay: float = _gh(root, Vector3(ax, 0.0, az))
		_beam(root, Vector3(local.x, gy + h * 0.92, local.z), Vector3(ax, ay + 0.4, az), 0.12, Color(0.2, 0.2, 0.22))
		GroundKit.box(root, Vector3(1.2, 0.8, 1.2), Vector3(ax, ay + 0.4, az), Color(0.3, 0.3, 0.3), Vector3.ZERO, false)


# ------------------------------------------------------------------ kinds
## A radio-range beacon: a guyed mast and a transmitting hut on a circular earth mat.
static func _radio_beacon(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	_earth_mat(root, 46.0 + 12.0 * float(size))
	_guyed_mast(root, Vector3(0.0, 0.0, -8.0), 45.0 + 8.0 * float(size), 4, Color(0.45, 0.47, 0.47))
	# transmitting / receiver hut and an aerial tuning unit
	var hy: float = _gh(root, Vector3(16.0, 0.0, 14.0))
	GroundKit.box(root, Vector3(12.0, 4.0, 8.0), Vector3(16.0, hy + 2.0, 14.0), Color(0.78, 0.76, 0.68))
	var hr := MeshInstance3D.new()
	hr.mesh = GroundKit.prism_mesh(13.0, 9.0, 2.0)
	hr.material_override = GroundKit.mat(Color(0.3, 0.3, 0.32), true)
	hr.position = Vector3(16.0, hy + 4.0, 14.0)
	root.add_child(hr)
	for i in 2 + size:
		GroundKit.cyl(root, 0.12, 0.12, 12.0, Vector3(-24.0 - float(i) * 8.0, _gh(root, Vector3(-24.0, 0.0, -18.0 + float(i) * 9.0)) + 6.0, -18.0 + float(i) * 9.0), Color(0.35, 0.35, 0.35), Vector3.ZERO, 4, false)   # shorter aerial masts
	GroundKit.box(root, Vector3(2.2, 2.2, 2.2), Vector3(0.0, _gh(root, Vector3.ZERO) + 1.1, 0.0), Color(0.5, 0.5, 0.48))       # tuning / feeder unit


## A direction-finding station: a four-mast Adcock aerial array on a circular earth mat around an operator hut.
static func _df_station(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var mat_r: float = 34.0 + 8.0 * float(size)
	_earth_mat(root, mat_r)
	var side: float = 32.0 + 8.0 * float(size)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_guyed_mast(root, Vector3(sx * side * 0.5, 0.0, sz * side * 0.5), 26.0 + 4.0 * float(size), 0, Color(0.4, 0.42, 0.42))
	# the operator hut at the centre, with a screened feeder cable run to each mast
	var cy: float = _gh(root, Vector3.ZERO)
	GroundKit.box(root, Vector3(9.0, 3.4, 7.0), Vector3(0.0, cy + 1.7, 0.0), Color(0.72, 0.7, 0.62))
	GroundKit.box(root, Vector3(10.0, 0.6, 8.0), Vector3(0.0, cy + 3.7, 0.0), Color(0.3, 0.3, 0.32), Vector3.ZERO, false)
	for sx2 in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(side, 0.15, 0.15), Vector3(0.0, cy + 0.4, sx2 * side * 0.5), Color(0.16, 0.16, 0.18), Vector3.ZERO, false)
		GroundKit.box(root, Vector3(0.15, 0.15, side), Vector3(sx2 * side * 0.5, cy + 0.4, 0.0), Color(0.16, 0.16, 0.18), Vector3.ZERO, false)


## A tall guyed beacon / broadcast mast (the Rugby / Droitwich silhouette) with a tuning hut and anchor blocks.
static func _beacon_mast(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var h: float = 150.0 + 40.0 * float(size)
	_earth_mat(root, 30.0)
	# a base insulator block and the lattice mast
	var gy: float = _gh(root, Vector3.ZERO)
	GroundKit.box(root, Vector3(6.0, 2.0, 6.0), Vector3(0.0, gy + 1.0, 0.0), Color(0.5, 0.5, 0.48))
	_guyed_mast(root, Vector3.ZERO, h, 6, Color(0.5, 0.52, 0.52))
	# tuning / transmitter building and a standby plant
	var by: float = _gh(root, Vector3(30.0, 0.0, 20.0))
	GroundKit.box(root, Vector3(18.0, 6.0, 11.0), Vector3(30.0, by + 3.0, 20.0), Color(0.78, 0.76, 0.68))
	GroundKit.box(root, Vector3(19.0, 1.0, 12.0), Vector3(30.0, by + 6.5, 20.0), Color(0.3, 0.3, 0.32), Vector3.ZERO, false)
	for i in 3:
		GroundKit.cyl(root, 0.15, 0.15, 4.0, Vector3(24.0 + float(i) * 6.0, by + 8.0, 20.0), Color(0.4, 0.4, 0.4), Vector3.ZERO, 4, false)


## An outer approach-lighting array for night sorties: a line of elevated lamps with pundit marker lights, an
## outer marker and a controller's caravan on the approach (distinct from the in-field flare path of P8).
static func _night_lighting(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var track: Color = Color(0.2, 0.22, 0.2)
	var lamp: Color = Color(0.95, 0.92, 0.6)
	# the approach centreline (local -Z) and its light line
	GroundKit.box(root, Vector3(3.0, 0.2, 220.0), Vector3(0.0, _gh(root, Vector3.ZERO) + 0.1, -110.0), track, Vector3.ZERO, false)
	var n: int = 8 + size * 2
	for i in n:
		var z: float = -20.0 - float(i) * (200.0 / float(n))
		GroundKit.cyl(root, 0.14, 0.18, 3.0, Vector3(0.0, _gh(root, Vector3(0.0, 0.0, z)) + 1.5, z), GroundKit.COL_STEEL, Vector3.ZERO, 5, false)
		GroundKit.box(root, Vector3(1.0, 0.6, 0.8), Vector3(0.0, _gh(root, Vector3(0.0, 0.0, z)) + 3.2, z), lamp, Vector3.ZERO, false)
		# a red pundit marker beside each lamp
		GroundKit.cyl(root, 0.1, 0.12, 1.4, Vector3(2.6, _gh(root, Vector3(2.6, 0.0, z)) + 0.7, z), GroundKit.COL_DARK, Vector3.ZERO, 4, false)
		GroundKit.sphere(root, 0.35, Vector3(2.6, _gh(root, Vector3(2.6, 0.0, z)) + 1.5, z), Color(0.85, 0.15, 0.12))
	# outer marker: a floodlight tower + a lit marker board at the far end of the approach
	var oz: float = -20.0 - 200.0
	GroundKit.cyl(root, 0.2, 0.3, 10.0, Vector3(-8.0, _gh(root, Vector3(-8.0, 0.0, oz)) + 5.0, oz), GroundKit.COL_STEEL, Vector3.ZERO, 6)
	GroundKit.box(root, Vector3(3.0, 3.4, 3.0), Vector3(-8.0, _gh(root, Vector3(-8.0, 0.0, oz)) + 11.0, oz), lamp, Vector3.ZERO, false)
	# controller's caravan and a flare-path generator truck at the near end
	GroundKit.box(root, Vector3(7.0, 3.0, 3.6), Vector3(14.0, _gh(root, Vector3(14.0, 0.0, 6.0)) + 1.5, 6.0), Color(0.55, 0.5, 0.36))
	GroundKit.box(root, Vector3(7.4, 0.4, 4.0), Vector3(14.0, _gh(root, Vector3(14.0, 0.0, 6.0)) + 3.2, 6.0), Color(0.3, 0.28, 0.24), Vector3.ZERO, false)
	GroundKit.box(root, Vector3(5.0, 2.4, 2.6), Vector3(-14.0, _gh(root, Vector3(-14.0, 0.0, 8.0)) + 1.5, 8.0), Color(0.35, 0.34, 0.3))
