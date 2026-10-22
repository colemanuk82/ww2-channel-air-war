class_name DecoyKit
extends RefCounted
## 1940s bombing-decoy scenery (P4): Starfish (SF) decoy towns, QF fire decoys, Q night-light decoys and K
## daytime dummy airfields, from Colonel J. F. Turner's decoy programme. All procedural low-poly toon from
## GroundKit primitives - no photo textures, no new assets.
##
##   var n: Node3D = DecoyKit.build(kind, pos, heading_deg, size, seed_v)   # node sits at world ORIGIN
##
## The returned container holds a `root` at (pos.x, ground_y, pos.z) rotated so local -Z faces the site's
## heading (the WorldFeatures / GroundStructure convention). Driven from data/decoys_1940.json by
## WorldPopulator._register_decoys(). The destructible decoy "target" itself is a separate
## GroundStructure("decoy"); this kit builds the decoy scenery AROUND it.

const COL_HESSIAN := Color(0.4, 0.33, 0.26)
const COL_DRUM := Color(0.22, 0.2, 0.18)
const COL_FLAME := Color(1.0, 0.5, 0.14)
const COL_LAMP := Color(1.0, 0.94, 0.6)


## Central dispatch, driven by the `kind` in data/decoys_1940.json.
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
		"starfish":
			_starfish(root, sz, rng)
		"qf_site":
			_qf(root, sz, rng)
		"k_site":
			_k_site(root, sz, rng)
		_:
			_q_site(root, sz, rng)
	return container


static func _disc(rng: RandomNumberGenerator, r_min: float, r_max: float) -> Vector2:
	var a: float = rng.randf() * TAU
	var r: float = rng.randf_range(r_min, r_max)
	return Vector2(cos(a) * r, sin(a) * r)


## An unshaded additive glow ball (a fire / lamp core); ignoring outline so it reads as light.
static func _glow(root: Node3D, radius: float, p: Vector3, col: Color) -> void:
	var mi: MeshInstance3D = GroundKit.sphere(root, radius, p, col, Vector3.ONE, false)
	mi.material_override = GroundKit.glow_mat(col, 0.95, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A decoy fire basket: a ring of oil drums packed with combustible material, with a glowing core.
static func _basket(root: Node3D, p: Vector3) -> void:
	for i in 6:
		var a: float = TAU * float(i) / 6.0
		GroundKit.cyl(root, 0.55, 0.55, 1.2, p + Vector3(cos(a) * 1.2, 0.6, sin(a) * 1.2), COL_DRUM, Vector3.ZERO, 6, false)
	GroundKit.box(root, Vector3(2.6, 0.4, 2.6), p + Vector3(0.0, 0.9, 0.0), Color(0.16, 0.14, 0.12), Vector3.ZERO, false)
	_glow(root, 1.1, p + Vector3(0.0, 1.7, 0.0), COL_FLAME)


## A lamp mast: a steel pole carrying a shaded lamp (a Q-site / QL decoy element).
static func _lamp_pole(root: Node3D, p: Vector3) -> void:
	GroundKit.cyl(root, 0.12, 0.16, 7.5, p + Vector3(0.0, 3.75, 0.0), GroundKit.COL_STEEL, Vector3.ZERO, 5, false)
	GroundKit.box(root, Vector3(1.0, 0.3, 1.0), p + Vector3(0.0, 7.5, 0.0), GroundKit.COL_DARK, Vector3.ZERO, false)
	_glow(root, 0.7, p + Vector3(0.0, 7.0, 0.0), COL_LAMP)


## A glow box on the ground: a hooded lamp simulating a lit building / street / marshalling yard.
static func _box_lamp(root: Node3D, p: Vector3) -> void:
	var mi: MeshInstance3D = GroundKit.box(root, Vector3(2.4, 1.6, 2.4), p + Vector3(0.0, 0.8, 0.0), Color(1.0, 0.88, 0.5), Vector3.ZERO, false)
	mi.material_override = GroundKit.glow_mat(Color(1.0, 0.88, 0.5), 0.85, false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The decoy control bunker: an earth-covered concrete post the decoy crew operated the fires and lights from.
## `yaw` is in degrees.
static func _bunker(root: Node3D, p: Vector3, yaw: float) -> void:
	var h := Node3D.new()
	h.position = p
	h.rotation.y = deg_to_rad(yaw)
	root.add_child(h)
	GroundKit.box(h, Vector3(6.4, 2.4, 4.4), Vector3(0.0, 1.2, 0.0), GroundKit.COL_CONCRETE)
	GroundKit.box(h, Vector3(8.4, 1.0, 6.4), Vector3(0.0, 2.6, 0.0), Color(0.34, 0.4, 0.22), Vector3.ZERO, false)   # earth cover
	GroundKit.box(h, Vector3(1.3, 1.7, 0.6), Vector3(0.0, 0.85, -2.4), GroundKit.COL_DARK, Vector3.ZERO, false)        # entrance


## A decoy building silhouette: a shed with a pitched roof (a fake house / works in a Starfish town).
static func _building(root: Node3D, p: Vector3, yaw: float, col: Color) -> void:
	var h := Node3D.new()
	h.position = p
	h.rotation.y = yaw
	root.add_child(h)
	GroundKit.box(h, Vector3(10.0, 5.0, 6.0), Vector3(0.0, 2.5, 0.0), col)
	var pm := MeshInstance3D.new()
	pm.mesh = GroundKit.prism_mesh(6.4, 10.0, 2.4)
	pm.material_override = GroundKit.mat(col.darkened(0.25), true)
	pm.position = Vector3(0.0, 5.0, 0.0)
	pm.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	h.add_child(pm)


## A dummy aircraft: the flat plywood-and-canvas silhouette of the K-site day decoys (a Blenheim/Hurricane).
static func _dummy_plane(root: Node3D, p: Vector3, yaw: float, col: Color) -> void:
	var h := Node3D.new()
	h.position = p
	h.rotation.y = yaw
	root.add_child(h)
	GroundKit.box(h, Vector3(1.7, 0.5, 11.0), Vector3(0.0, 1.1, 0.0), col)                       # fuselage
	GroundKit.box(h, Vector3(13.0, 0.35, 2.2), Vector3(0.0, 1.1, -0.5), col)                     # wings
	GroundKit.box(h, Vector3(4.6, 0.3, 1.2), Vector3(0.0, 1.15, 4.6), col)                       # tailplane
	GroundKit.box(h, Vector3(0.25, 1.6, 1.4), Vector3(0.0, 2.0, 4.6), col)                       # fin
	for sx in [-1.0, 1.0]:
		GroundKit.cyl(h, 0.35, 0.35, 0.5, Vector3(sx * 2.2, 0.35, 0.0), GroundKit.COL_DARK, Vector3(0.0, 0.0, 90.0), 5, false)


## Starfish (SF) decoy town: a scatter of fake buildings mimicking a built-up area, banks of oil-drum fire
## baskets (the decoy fires), lamp and glow-box light arrays, and the crew's control bunker.
static func _starfish(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	for i in 6 + size * 5:
		var d: Vector2 = _disc(rng, 18.0, 150.0 + float(size) * 42.0)
		_building(root, Vector3(d.x, 0.0, d.y), rng.randf() * TAU, COL_HESSIAN.lightened(rng.randf_range(-0.05, 0.08)))
	for i in 4 + size * 4:
		var d: Vector2 = _disc(rng, 20.0, 120.0 + float(size) * 30.0)
		_basket(root, Vector3(d.x, 0.0, d.y))
	for i in 8 + size * 6:
		var d: Vector2 = _disc(rng, 25.0, 170.0 + float(size) * 42.0)
		if rng.randf() < 0.5:
			_lamp_pole(root, Vector3(d.x, 0.0, d.y))
		else:
			_box_lamp(root, Vector3(d.x, 0.0, d.y))
	_bunker(root, Vector3(0.0, 0.0, -95.0), 180.0)


## QF fire decoy: a dense bank of fire baskets (the Q-site fires), a few lights, a control bunker and a shed.
static func _qf(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	for i in 9 + size * 6:
		var d: Vector2 = _disc(rng, 16.0, 120.0 + float(size) * 26.0)
		_basket(root, Vector3(d.x, 0.0, d.y))
	for i in 4 + size * 2:
		var d: Vector2 = _disc(rng, 30.0, 150.0)
		_box_lamp(root, Vector3(d.x, 0.0, d.y))
	for i in 2 + size:
		var d: Vector2 = _disc(rng, 40.0, 130.0)
		_building(root, Vector3(d.x, 0.0, d.y), rng.randf() * TAU, COL_HESSIAN)
	_bunker(root, Vector3(0.0, 0.0, -70.0), 180.0)


## Q night-light decoy: a flare path (a straight row of lamp masts) with glow boxes simulating lit buildings,
## a taxi track outline and a control shelter - an airfield seen at night from the air.
static func _q_site(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var n: int = 6 + size * 3
	GroundKit.box(root, Vector3(30.0, 0.25, 230.0), Vector3(0.0, 0.12, 0.0), Color(0.3, 0.28, 0.24), Vector3.ZERO, false)   # flare path strip
	for i in n:
		var z: float = -95.0 + float(i) * (190.0 / float(maxi(n - 1, 1)))
		_lamp_pole(root, Vector3(0.0, 0.0, z))
		if i % 2 == 0:
			_box_lamp(root, Vector3(9.0, 0.0, z))
	for i in 6 + size * 3:
		var d: Vector2 = _disc(rng, 30.0, 150.0)
		_box_lamp(root, Vector3(d.x, 0.0, d.y))
	_bunker(root, Vector3(26.0, 0.0, 26.0), 225.0)


## K daytime dummy airfield: a cleared strip with a ring track, dummy aircraft on the grass, earth-banked
## dumps and a few dummy buildings - the day decoy that drew Luftwaffe attacks in 1940.
static func _k_site(root: Node3D, size: int, rng: RandomNumberGenerator) -> void:
	var track: Color = Color(0.34, 0.3, 0.24)
	GroundKit.box(root, Vector3(28.0, 0.3, 250.0), Vector3(0.0, 0.15, 0.0), track, Vector3.ZERO, false)      # cleared strip
	for sx in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(7.0, 0.2, 150.0), Vector3(sx * 72.0, 0.1, 0.0), track, Vector3.ZERO, false)
	for sz in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(150.0, 0.2, 7.0), Vector3(0.0, 0.1, sz * 78.0), track, Vector3.ZERO, false)  # ring track
	var ac: Color = Color(0.32, 0.38, 0.24)
	for i in 4 + size * 3:
		var px: float = -44.0 + float(i % 3) * 30.0 + rng.randf_range(-5.0, 5.0)
		var pz: float = -48.0 + float(i / 3) * 32.0 + rng.randf_range(-5.0, 5.0)
		_dummy_plane(root, Vector3(px, 0.0, pz), rng.randf_range(-0.35, 0.35), ac)
	for i in 5:
		var d: Vector2 = _disc(rng, 50.0, 130.0)
		GroundKit.box(root, Vector3(14.0, 3.0, 5.0), Vector3(d.x, 1.5, d.y), Color(0.32, 0.28, 0.2), Vector3.ZERO, false)   # dump
	for i in 2 + size:
		var d2: Vector2 = _disc(rng, 60.0, 140.0)
		_building(root, Vector3(d2.x, 0.0, d2.y), rng.randf() * TAU, COL_HESSIAN)
	_bunker(root, Vector3(-95.0, 0.0, -95.0), 135.0)
