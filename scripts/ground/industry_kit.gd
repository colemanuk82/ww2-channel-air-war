class_name IndustryKit
extends RefCounted
## 1940s industry builders (Phase 4.1): one builder per `kind` in data/industry_1940.json
## (gasworks|colliery|mill|brewery|power_station|shipyard|dockyard|goods_yard|engine_shed|waterworks|
## cement_works|staithes|quarry). All procedural toon primitives from GroundKit - no new assets.
##
## Usage (mirrors WorldFeatures.build_camp):
##   var n: Node3D = IndustryKit.build(kind, world_pos, heading_deg, size, team, seed_v)
## The returned container sits at the world origin; its child `root` carries the site at (pos.x, 0, pos.z)
## with rotation.y = -deg_to_rad(heading_deg), so local -Z is the site "front" (the same convention as
## GroundStructure and WorldFeatures). Chimney tops are collected and handed to a ChimneySmokes node so a
## streamed works gets thin idle plumes; destructible GroundStructure targets pass with_smoke=false.
##
## build_siding(site, rail_pt, seed_v) draws the rail siding stub a works runs out to its nearest RoutePath.

const COL_IRON := Color(0.32, 0.34, 0.38)
const COL_COPPER := Color(0.5, 0.35, 0.2)
const COL_SLATE := Color(0.3, 0.29, 0.31)
const COL_BALLAST := Color(0.4, 0.38, 0.34)
const COL_RAIL := Color(0.2, 0.18, 0.16)
const COL_SLEEPER := Color(0.28, 0.22, 0.15)


# ============================================================================ public API
## Build one works of `kind` at world `pos`, oriented so local -Z faces `yaw_deg`. Returns a container at the
## world origin (child meshes are positioned at the site), or an empty container for an unknown kind fallback.
static func build(kind: String, pos: Vector3, yaw_deg: float, size: int = 2, team: String = "Allies", seed_v: int = 0, with_smoke: bool = true) -> Node3D:
	var container := Node3D.new()
	var root: Node3D = _root(container, pos, yaw_deg)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var chimneys: Array = []
	match kind:
		"gasworks":
			_gasworks(root, size, rng, chimneys)
		"colliery":
			_colliery(root, size, rng, chimneys)
		"mill":
			_mill(root, size, chimneys)
		"brewery":
			_brewery(root, size, chimneys)
		"power_station":
			_power_station(root, size, chimneys)
		"shipyard", "dockyard":
			_shipyard(root, size, chimneys)
		"goods_yard":
			_goods_yard(root, size, rng, chimneys)
		"engine_shed":
			_engine_shed(root, size, chimneys)
		"waterworks":
			_waterworks(root, size, chimneys)
		"cement_works":
			_cement_works(root, size, chimneys)
		"staithes":
			_staithes(root, size, chimneys)
		"quarry":
			_quarry(root, size, rng, chimneys)
		_:
			_mill(root, size, chimneys)
	# a works flag (also uses the team argument): the site is claimed by one side
	_flag(root, Vector3(62.0, 0.0, 62.0), team)
	if with_smoke and not chimneys.is_empty():
		var cs := ChimneySmokes.new()
		for cp in chimneys:
			cs.points.append(root.transform * (cp as Vector3))
		cs.size = 1.3 + 0.25 * float(size)
		container.add_child(cs)
	return container


## A rail siding stub from `site` towards the nearest rail point `rail_pt`: ballast strip + two rails + sleepers,
## draped on the terrain. Returns a container at the world origin. Empty if the two points coincide.
static func build_siding(site: Vector3, rail_pt: Vector3, _seed_v: int = 0) -> Node3D:
	var container := Node3D.new()
	var d: Vector3 = rail_pt - site
	d.y = 0.0
	var length: float = d.length()
	if length < 6.0:
		return container
	var yaw: float = WorldCoords.dir_to_heading(d)
	var root := Node3D.new()
	root.position = Vector3(site.x, 0.0, site.z)
	root.rotation.y = -deg_to_rad(yaw)         # local -Z runs towards the rail
	container.add_child(root)
	var segs: int = clampi(int(length / 30.0), 1, 20)
	var seg: float = length / float(segs)
	for i in segs:
		var z: float = -(float(i) + 0.5) * seg
		var gy: float = _gh(root, Vector3(0.0, 0.0, z))
		GroundKit.box(root, Vector3(6.0, 0.4, seg + 0.3), Vector3(0.0, gy + 0.2, z), COL_BALLAST, Vector3.ZERO, false)
		GroundKit.box(root, Vector3(0.7, 0.5, seg + 0.3), Vector3(-1.7, gy + 0.6, z), COL_RAIL, Vector3.ZERO, false)
		GroundKit.box(root, Vector3(0.7, 0.5, seg + 0.3), Vector3(1.7, gy + 0.6, z), COL_RAIL, Vector3.ZERO, false)
		GroundKit.box(root, Vector3(3.6, 0.35, 0.7), Vector3(0.0, gy + 0.32, z), COL_SLEEPER, Vector3.ZERO, false)
	# buffer stop at the yard (site) end
	var gy0: float = _gh(root, Vector3(0.0, 0.0, 0.0))
	GroundKit.box(root, Vector3(3.2, 2.0, 1.0), Vector3(0.0, gy0 + 1.0, -0.6), Color(0.2, 0.18, 0.16))
	return container


# ============================================================================ helpers
static func _root(container: Node3D, pos: Vector3, yaw_deg: float) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.z)
	root.rotation.y = -deg_to_rad(yaw_deg)
	container.add_child(root)
	return root


## Terrain height at a local point of `root`.
static func _gh(root: Node3D, local: Vector3) -> float:
	var w: Vector3 = root.transform * local
	return GroundKit.ground_y(w.x, w.z)


## Triangular-prism roof (width X, length Z, height Y) sitting at `pos` (base = pos.y).
static func _roof(root: Node3D, w: float, l: float, h: float, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = GroundKit.prism_mesh(w, l, h)
	mi.material_override = GroundKit.mat(col, true)
	mi.position = pos
	root.add_child(mi)
	return mi


## A shed: box walls + a pitched prism roof. `base` carries the ground height at the shed centre.
static func _shed(root: Node3D, w: float, h: float, l: float, base: Vector3, col: Color, ridge: float) -> void:
	GroundKit.box(root, Vector3(w, h, l), Vector3(base.x, base.y + h * 0.5, base.z), col)
	_roof(root, w + 1.0, l + 1.0, ridge, Vector3(base.x, base.y + h, base.z), col.darkened(0.28))


## A tapered chimney; the cap top is recorded in `chimneys` (local to root) for ChimneySmokes.
static func _chimney(root: Node3D, local: Vector3, h: float, r_base: float, r_top: float, col: Color, chimneys: Array) -> void:
	var gy: float = _gh(root, local)
	GroundKit.cyl(root, r_top, r_base, h, Vector3(local.x, gy + h * 0.5, local.z), col, Vector3.ZERO, 10)
	GroundKit.cyl(root, r_base * 0.99, r_base * 1.04, 0.9, Vector3(local.x, gy + h * 0.62, local.z), col.darkened(0.12), Vector3.ZERO, 10, false)
	GroundKit.cyl(root, r_top * 1.18, r_top * 1.18, 1.6, Vector3(local.x, gy + h + 0.5, local.z), col.darkened(0.22), Vector3.ZERO, 10, false)
	chimneys.append(Vector3(local.x, gy + h + 1.5, local.z))


## A fan of rail sidings (ballast + two rails per track) centred on (cx, cz) in local space.
static func _tracks(root: Node3D, cx: float, cz: float, n_tracks: int, length: float, gap: float) -> void:
	for t in n_tracks:
		var z: float = cz + (float(t) - float(n_tracks - 1) * 0.5) * gap
		var gy: float = _gh(root, Vector3(cx, 0.0, z))
		GroundKit.box(root, Vector3(length, 0.35, gap * 0.72), Vector3(cx, gy + 0.18, z), COL_BALLAST, Vector3.ZERO, false)
		for sx in [-1.0, 1.0]:
			GroundKit.box(root, Vector3(length, 0.4, 0.7), Vector3(cx, gy + 0.5, z + sx * 0.9), COL_RAIL, Vector3.ZERO, false)


static func _flag(root: Node3D, local: Vector3, team: String) -> void:
	var gy: float = _gh(root, local)
	GroundKit.cyl(root, 0.2, 0.3, 16.0, Vector3(local.x, gy + 8.0, local.z), Color(0.85, 0.85, 0.85), Vector3.ZERO, 6, false)
	GroundKit.box(root, Vector3(5.0, 3.0, 0.15), Vector3(local.x + 2.6, gy + 14.4, local.z), Color(0.1, 0.16, 0.5) if team == "Allies" else Color(0.6, 0.1, 0.1), Vector3.ZERO, false)


# ============================================================================ builders
## Gasworks: the iconic ring of telescopic gasholders in their guide frames, retort houses, chimneys.
static func _gasworks(root: Node3D, size: int, rng: RandomNumberGenerator, chimneys: Array) -> void:
	var brick: Color = GroundKit.COL_BRICK.darkened(0.1)
	var steel: Color = Color(0.36, 0.38, 0.4)
	var k: float = 1.0 + 0.3 * float(size)
	# retort / purifying houses: long low brick ranges across the front
	var rhy: float = _gh(root, Vector3(0.0, 0.0, -60.0))
	_shed(root, 120.0 * k, 13.0, 36.0, Vector3(0.0, rhy, -60.0), brick, 5.5)
	_shed(root, 80.0 * k, 10.0, 26.0, Vector3(-30.0 * k, _gh(root, Vector3(-30.0 * k, 0.0, -100.0)), -100.0), brick.lightened(0.05), 4.0)
	# gasholders arranged in a ring around a centre
	var n_h: int = 3 + mini(size, 3)
	var c := Vector3(0.0, 0.0, 30.0)
	var ring_r: float = 62.0 * k
	for i in n_h:
		var a: float = TAU * float(i) / float(n_h) + 0.35
		var gx: float = c.x + cos(a) * ring_r
		var gz: float = c.z + sin(a) * ring_r
		var gy: float = _gh(root, Vector3(gx, 0.0, gz))
		var R: float = rng.randf_range(20.0, 25.0) * (1.0 + 0.1 * float(size))
		var H: float = rng.randf_range(28.0, 36.0)
		var shell: Color = steel if i % 2 == 0 else Color(0.42, 0.4, 0.36)
		GroundKit.cyl(root, R * 0.9, R, H, Vector3(gx, gy + H * 0.5, gz), shell, Vector3.ZERO, 18)
		GroundKit.cyl(root, R * 0.97, R * 0.97, 1.8, Vector3(gx, gy + H * 0.5, gz), shell.darkened(0.16), Vector3.ZERO, 18, false)
		GroundKit.sphere(root, R * 0.94, Vector3(gx, gy + H, gz), shell.lightened(0.05), Vector3(1.0, 0.35, 1.0))
		for p in 8:
			var pa: float = TAU * float(p) / 8.0
			GroundKit.cyl(root, 0.6, 0.6, H * 0.92, Vector3(gx + cos(pa) * (R + 1.4), gy + H * 0.46, gz + sin(pa) * (R + 1.4)), shell.darkened(0.3), Vector3.ZERO, 4, false)
	# gasholder house / booster room in the middle of the ring
	_shed(root, 30.0, 9.0, 20.0, Vector3(c.x, _gh(root, Vector3(c.x, 0.0, c.z)), c.z), brick.lightened(0.06), 4.0)
	# twin chimneys
	_chimney(root, Vector3(50.0 * k, 0.0, -66.0), 44.0 + 4.0 * float(size), 3.4, 2.0, brick, chimneys)
	_chimney(root, Vector3(-50.0 * k, 0.0, 6.0), 38.0 + 4.0 * float(size), 3.0, 1.8, brick, chimneys)


## Colliery: pit head-frame winding tower, winding house, spoil heap, sidings, chimney.
static func _colliery(root: Node3D, size: int, rng: RandomNumberGenerator, chimneys: Array) -> void:
	var steel: Color = Color(0.3, 0.32, 0.36)
	var brick: Color = GroundKit.COL_BRICK.darkened(0.12)
	var k: float = 1.0 + 0.25 * float(size)
	# pit head-frame: four leaning legs, three platforms, twin winding wheels at the top
	var H: float = 40.0 + 6.0 * float(size)
	var hy: float = _gh(root, Vector3(0.0, 0.0, 0.0))
	var lean: float = rad_to_deg(atan2(3.0, H))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			GroundKit.cyl(root, 0.5, 0.7, H, Vector3(sx * 7.0, hy + H * 0.5, sz * 7.0), steel, Vector3(-sz * lean, 0.0, sx * lean), 4, false)
	for lvl in 3:
		var y: float = hy + H * (0.34 + 0.3 * float(lvl))
		var w: float = lerpf(15.0, 6.0, float(lvl) / 2.0)
		GroundKit.box(root, Vector3(w, 0.6, w), Vector3(0.0, y, 0.0), steel, Vector3.ZERO, false)
	for dx in [-3.4, 3.4]:
		GroundKit.cyl(root, 4.2, 4.2, 1.4, Vector3(dx, hy + H + 2.2, 0.0), steel.darkened(0.1), Vector3(0.0, 0.0, 90.0), 14)
	# winding house (gabled brick block feeding the head-gear) + a fan house
	_shed(root, 34.0, 13.0, 22.0, Vector3(36.0, _gh(root, Vector3(36.0, 0.0, -6.0)), -6.0), brick, 5.5)
	_shed(root, 20.0, 10.0, 16.0, Vector3(-34.0, _gh(root, Vector3(-34.0, 0.0, 12.0)), 12.0), brick.lightened(0.06), 4.5)
	# spoil heap: a cone with a flattened tipping top
	var sx2: float = -46.0
	var sy: float = _gh(root, Vector3(sx2, 0.0, 74.0))
	GroundKit.cyl(root, 13.0, 46.0, 30.0, Vector3(sx2, sy + 15.0, 74.0), Color(0.26, 0.24, 0.22), Vector3.ZERO, 16)
	GroundKit.cyl(root, 11.0, 13.0, 4.0, Vector3(sx2, sy + 32.0, 74.0), Color(0.22, 0.2, 0.18), Vector3.ZERO, 16, false)
	# sidings with wagon rakes leading away
	_tracks(root, 0.0, 46.0, 4 + mini(size, 2), 190.0, 12.0)
	for t in (4 + mini(size, 2)):
		var z: float = 46.0 + (float(t) - float(3 + mini(size, 2)) * 0.5) * 12.0
		var x0: float = rng.randf_range(-70.0, -10.0)
		for w in (3 + rng.randi() % 4):
			var col: Color = Color(0.36, 0.25, 0.18) if (w + t) % 3 != 0 else Color(0.3, 0.3, 0.28)
			GroundKit.box(root, Vector3(8.0, 3.2, 3.2), Vector3(x0 + float(w) * 9.5, _gh(root, Vector3(x0, 0.0, z)) + 2.4, z), col)
	# chimney
	_chimney(root, Vector3(58.0 * k, 0.0, 20.0), 42.0 + 4.0 * float(size), 3.0, 1.8, brick, chimneys)


## Mill: tall chimney + rows of long weaving/flat-roofed sheds.
static func _mill(root: Node3D, size: int, chimneys: Array) -> void:
	var brick: Color = GroundKit.COL_BRICK
	var k: float = 1.0 + 0.2 * float(size)
	_chimney(root, Vector3(-44.0 * k, 0.0, -34.0), 48.0 + 6.0 * float(size), 3.2, 1.9, brick, chimneys)
	var rows: int = 1 + mini(size, 2)
	var cols: int = 2 + size
	for r in rows:
		var sz: float = -12.0 + float(r) * 44.0
		for c in cols:
			var cx: float = (float(c) - float(cols - 1) * 0.5) * 46.0
			_shed(root, 42.0, 11.0, 26.0, Vector3(cx, _gh(root, Vector3(cx, 0.0, sz)), sz), brick.lightened(0.04), 4.2)
	# engine house / offices block at one end
	_shed(root, 34.0, 13.0, 22.0, Vector3(78.0 * k, _gh(root, Vector3(78.0 * k, 0.0, 0.0)), 0.0), brick.darkened(0.07), 5.5)
	# water tower
	GroundKit.cyl(root, 6.0, 6.0, 10.0, Vector3(78.0 * k, _gh(root, Vector3(78.0 * k, 0.0, 40.0)) + 16.0, 40.0), Color(0.55, 0.53, 0.5), Vector3.ZERO, 12)
	for p in 4:
		var pa: float = TAU * float(p) / 4.0 + 0.7
		GroundKit.cyl(root, 0.5, 0.7, 12.0, Vector3(78.0 * k + cos(pa) * 4.5, _gh(root, Vector3(78.0 * k, 0.0, 40.0)) + 6.0, 40.0 + sin(pa) * 4.5), Color(0.4, 0.4, 0.38), Vector3.ZERO, 6, false)


## Brewery: brewhouse tower + rows of fermentation vats + malting, chimney.
static func _brewery(root: Node3D, size: int, chimneys: Array) -> void:
	var brick: Color = GroundKit.COL_BRICK.darkened(0.05)
	var k: float = 1.0 + 0.25 * float(size)
	var t_h: float = 24.0 + 5.0 * float(size)
	var ty: float = _gh(root, Vector3(0.0, 0.0, 0.0))
	GroundKit.box(root, Vector3(24.0, t_h, 24.0), Vector3(0.0, ty + t_h * 0.5, 0.0), brick)
	GroundKit.box(root, Vector3(26.0, 1.6, 26.0), Vector3(0.0, ty + t_h + 0.6, 0.0), COL_SLATE, Vector3.ZERO, false)
	GroundKit.cyl(root, 0.0, 10.0, 8.0, Vector3(0.0, ty + t_h + 5.0, 0.0), brick.darkened(0.12), Vector3.ZERO, 12)   # conical tower roof
	# fermentation vats (copper cylinders in a row)
	var n: int = 3 + size
	for i in n:
		var vx: float = (float(i) - float(n - 1) * 0.5) * 17.0
		var vz: float = 42.0
		var vy: float = _gh(root, Vector3(vx, 0.0, vz))
		GroundKit.cyl(root, 6.0, 6.6, 13.0, Vector3(vx, vy + 6.5, vz), COL_COPPER, Vector3.ZERO, 12)
		GroundKit.cyl(root, 6.5, 6.5, 0.6, Vector3(vx, vy + 13.2, vz), COL_COPPER.darkened(0.15), Vector3.ZERO, 12, false)
	# malting / stores
	_shed(root, 66.0, 12.0, 26.0, Vector3(44.0 * k, _gh(root, Vector3(44.0 * k, 0.0, 20.0)), 20.0), brick.lightened(0.05), 4.5)
	_chimney(root, Vector3(-44.0 * k, 0.0, -18.0), 34.0 + 4.0 * float(size), 2.6, 1.6, brick, chimneys)


## Power station: hyperbolic-ish cooling towers + the landmark chimney + turbine hall.
static func _power_station(root: Node3D, size: int, chimneys: Array) -> void:
	var conc: Color = Color(0.72, 0.7, 0.66)
	var k: float = 1.0 + 0.3 * float(size)
	# cooling towers: flared base cone + waisted upper cone reads as a hyperboloid from the air
	for i in 2:
		var cx: float = (float(i) - 0.5) * 96.0 * k
		var gy: float = _gh(root, Vector3(cx, 0.0, 56.0))
		var R: float = 34.0
		var H: float = 48.0
		GroundKit.cyl(root, R * 0.62, R, H * 0.5, Vector3(cx, gy + H * 0.25, 56.0), conc, Vector3.ZERO, 20)
		GroundKit.cyl(root, R * 0.82, R * 0.62, H * 0.5, Vector3(cx, gy + H * 0.75, 56.0), conc.lightened(0.03), Vector3.ZERO, 20)
	# turbine hall + boiler house
	_shed(root, 140.0 * k, 24.0, 54.0, Vector3(-46.0, _gh(root, Vector3(-46.0, 0.0, -34.0)), -34.0), Color(0.58, 0.56, 0.52), 8.0)
	# the tall brick chimney (the skyline marker)
	_chimney(root, Vector3(-96.0 * k, 0.0, -34.0), 72.0 + 6.0 * float(size), 5.0, 3.0, GroundKit.COL_BRICK.darkened(0.05), chimneys)
	# switch house + a small auxiliary stack
	_chimney(root, Vector3(24.0, 0.0, -78.0), 34.0, 2.4, 1.6, GroundKit.COL_BRICK, chimneys)
	_shed(root, 36.0, 10.0, 24.0, Vector3(80.0, _gh(root, Vector3(80.0, 0.0, -20.0)), -20.0), Color(0.6, 0.58, 0.54), 4.0)


## Shipyard / dockyard: building berths with hulls on the ways, a portal gantry crane, fitting-out quay, chimney.
static func _shipyard(root: Node3D, size: int, chimneys: Array) -> void:
	var steel: Color = Color(0.55, 0.2, 0.16)
	var stone: Color = Color(0.44, 0.44, 0.42)
	var conc: Color = GroundKit.COL_CONCRETE
	var k: float = 1.0 + 0.4 * float(size)
	# yard apron
	GroundKit.box(root, Vector3(250.0 * k, 2.0, 200.0 * k), Vector3(0.0, _gh(root, Vector3(0.0, 0.0, 20.0)) + 0.9, 20.0), conc.darkened(0.12), Vector3.ZERO, false)
	# building berths (inclined slipways) with hulls on the ways
	for b in 2:
		var bx: float = (float(b) - 0.5) * 130.0
		GroundKit.box(root, Vector3(32.0, 1.4, 130.0), Vector3(bx, _gh(root, Vector3(bx, 0.0, -40.0)) + 1.0, -40.0), stone, Vector3(8.0, 0.0, 0.0))
		GroundKit.box(root, Vector3(16.0, 6.0, 82.0), Vector3(bx, _gh(root, Vector3(bx, 0.0, -52.0)) + 4.5, -52.0), Color(0.4, 0.4, 0.42))
		GroundKit.box(root, Vector3(10.0, 4.0, 24.0), Vector3(bx, _gh(root, Vector3(bx, 0.0, -30.0)) + 7.5, -30.0), Color(0.46, 0.46, 0.48))
	# portal gantry crane over the fitting-out berth
	var gx: float = 80.0
	var leg_h: float = 40.0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			GroundKit.box(root, Vector3(3.0, leg_h, 3.0), Vector3(gx + sx * 28.0, _gh(root, Vector3(gx, 0.0, 0.0)) + leg_h * 0.5, sz * 66.0), steel, Vector3.ZERO, false)
	for sz2 in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(64.0, 3.0, 3.0), Vector3(gx, _gh(root, Vector3(gx, 0.0, 0.0)) + leg_h + 2.0, sz2 * 66.0), steel, Vector3.ZERO, false)
	GroundKit.box(root, Vector3(5.0, 4.0, 5.0), Vector3(gx, _gh(root, Vector3(gx, 0.0, 0.0)) + leg_h - 2.0, 0.0), COL_IRON)
	GroundKit.box(root, Vector3(1.0, 12.0, 1.0), Vector3(gx, _gh(root, Vector3(gx, 0.0, 0.0)) + leg_h - 10.0, 0.0), GroundKit.COL_DARK, Vector3.ZERO, false)
	# fitting-out quay + a moored hull (dark box) along it
	GroundKit.box(root, Vector3(180.0, 3.0, 30.0), Vector3(0.0, _gh(root, Vector3(0.0, 0.0, -150.0)) + 1.4, -150.0), conc.darkened(0.06))
	GroundKit.box(root, Vector3(14.0, 6.0, 90.0), Vector3(-40.0, _gh(root, Vector3(-40.0, 0.0, -170.0)) + 2.0, -170.0), Color(0.34, 0.34, 0.36))
	# hulked hulls on the foreshore
	for h in 2:
		var hx: float = -150.0 + float(h) * 42.0
		GroundKit.box(root, Vector3(14.0, 5.0, 60.0), Vector3(hx, _gh(root, Vector3(hx, 0.0, 150.0)) + 1.0, 150.0), Color(0.22, 0.2, 0.18), Vector3(0.0, float(h) * 30.0 - 20.0, 0.0))
	# fitting-out workshop + chimney
	_shed(root, 70.0, 14.0, 30.0, Vector3(-110.0, _gh(root, Vector3(-110.0, 0.0, 40.0)), 40.0), GroundKit.COL_BRICK.darkened(0.1), 6.0)
	_chimney(root, Vector3(-150.0, 0.0, 40.0), 44.0 + 4.0 * float(size), 3.2, 1.9, GroundKit.COL_BRICK, chimneys)


## Goods / marshalling yard: a fan of sidings with wagon rakes, a transit shed, a coal hoist, a chimney.
static func _goods_yard(root: Node3D, size: int, rng: RandomNumberGenerator, chimneys: Array) -> void:
	var gy0: float = _gh(root, Vector3(0.0, 0.0, 0.0))
	GroundKit.box(root, Vector3(240.0, 0.4, 170.0), Vector3(0.0, gy0 + 0.2, 0.0), COL_BALLAST.darkened(0.06), Vector3.ZERO, false)
	var n_tracks: int = 4 + mini(size, 3)
	_tracks(root, 0.0, 0.0, n_tracks, 220.0, 14.0)
	for t in n_tracks:
		var z: float = (float(t) - float(n_tracks - 1) * 0.5) * 14.0
		var x0: float = rng.randf_range(-80.0, -10.0)
		for w in (3 + rng.randi() % 5):
			var col: Color = Color(0.38, 0.27, 0.2) if (w + t) % 3 != 0 else Color(0.32, 0.32, 0.3)
			GroundKit.box(root, Vector3(8.0, 3.2, 3.2), Vector3(x0 + float(w) * 9.5, _gh(root, Vector3(x0, 0.0, z)) + 2.4, z), col)
	# transit / goods shed across the back
	_shed(root, 100.0, 13.0, 30.0, Vector3(0.0, _gh(root, Vector3(0.0, 0.0, 96.0)), 96.0), GroundKit.COL_BRICK, 4.5)
	# coal hoist / crane on the yard, water column and a chimney
	GroundKit.cyl(root, 1.3, 1.7, 18.0, Vector3(-96.0, gy0 + 9.0, 0.0), COL_IRON, Vector3.ZERO, 8)
	GroundKit.box(root, Vector3(18.0, 1.4, 1.4), Vector3(-88.0, gy0 + 17.0, 0.0), COL_IRON, Vector3.ZERO, false)
	GroundKit.cyl(root, 0.5, 0.7, 12.0, Vector3(60.0, gy0 + 6.0, 40.0), Color(0.4, 0.4, 0.38), Vector3.ZERO, 6, false)
	_chimney(root, Vector3(92.0, 0.0, -84.0), 26.0, 2.0, 1.4, GroundKit.COL_BRICK, chimneys)


## Engine shed: a long multi-road shed with sawtooth bays, doors, a turntable and a coaling stage.
static func _engine_shed(root: Node3D, size: int, chimneys: Array) -> void:
	var brick: Color = GroundKit.COL_BRICK.darkened(0.08)
	var gy0: float = _gh(root, Vector3(0.0, 0.0, 0.0))
	var L: float = 92.0 + 12.0 * float(size)
	var n_bay: int = 4 + mini(size, 2)
	var span: float = 14.0
	var W: float = span * float(n_bay)
	GroundKit.box(root, Vector3(W, 15.0, L), Vector3(0.0, gy0 + 7.5, 0.0), brick)
	for b in n_bay:
		var bx: float = (float(b) - float(n_bay - 1) * 0.5) * span
		_roof(root, span + 0.5, L + 1.0, 4.4, Vector3(bx, gy0 + 15.0, 0.0), COL_SLATE)
		# front engine doors
		GroundKit.box(root, Vector3(span * 0.7, 11.0, 0.6), Vector3(bx, gy0 + 5.5, -L * 0.5 - 0.3), Color(0.14, 0.14, 0.15), Vector3.ZERO, false)
	# turntable: circular pit ring with the turning bridge
	var tz: float = -L * 0.5 - 44.0
	var ty: float = _gh(root, Vector3(0.0, 0.0, tz))
	GroundKit.cyl(root, 22.0, 22.0, 1.2, Vector3(0.0, ty + 0.1, tz), Color(0.24, 0.23, 0.22), Vector3.ZERO, 24)
	GroundKit.cyl(root, 20.0, 20.0, 1.6, Vector3(0.0, ty + 0.5, tz), Color(0.3, 0.3, 0.32), Vector3.ZERO, 24, false)
	GroundKit.box(root, Vector3(4.0, 1.0, 42.0), Vector3(0.0, ty + 1.3, tz), Color(0.2, 0.2, 0.22))
	# coaling stage + yard chimney
	GroundKit.box(root, Vector3(20.0, 8.0, 14.0), Vector3(60.0, gy0 + 4.0, 24.0), Color(0.22, 0.2, 0.18))
	_chimney(root, Vector3(54.0, 0.0, 26.0), 36.0 + 3.0 * float(size), 2.6, 1.6, brick, chimneys)


## Waterworks: rectangular filter beds, a water tower on legs, a pumping house, a small stack.
static func _waterworks(root: Node3D, size: int, chimneys: Array) -> void:
	var conc: Color = Color(0.66, 0.64, 0.6)
	var brick: Color = GroundKit.COL_BRICK.lightened(0.05)
	var n_bed: int = 3 + size
	for i in n_bed:
		var bx: float = (float(i % 3) - 1.0) * 62.0
		var bz: float = float(i / 3) * 56.0
		var gy: float = _gh(root, Vector3(bx, 0.0, bz))
		GroundKit.box(root, Vector3(50.0, 1.6, 44.0), Vector3(bx, gy + 0.6, bz), Color(0.55, 0.6, 0.6), Vector3.ZERO, false)
		GroundKit.box(root, Vector3(52.0, 2.0, 2.2), Vector3(bx, gy + 1.2, bz - 22.0), conc, Vector3.ZERO, false)
		GroundKit.box(root, Vector3(52.0, 2.0, 2.2), Vector3(bx, gy + 1.2, bz + 22.0), conc, Vector3.ZERO, false)
		GroundKit.box(root, Vector3(2.2, 2.0, 46.0), Vector3(bx - 25.0, gy + 1.2, bz), conc, Vector3.ZERO, false)
		GroundKit.box(root, Vector3(2.2, 2.0, 46.0), Vector3(bx + 25.0, gy + 1.2, bz), conc, Vector3.ZERO, false)
	# water tower on four legs (the town landmark)
	var tx: float = -74.0
	var tz: float = 62.0
	var ty: float = _gh(root, Vector3(tx, 0.0, tz))
	GroundKit.cyl(root, 9.0, 10.0, 16.0, Vector3(tx, ty + 22.0, tz), Color(0.6, 0.58, 0.54), Vector3.ZERO, 16)
	GroundKit.sphere(root, 9.5, Vector3(tx, ty + 30.0, tz), Color(0.55, 0.53, 0.5), Vector3(1.0, 0.4, 1.0))
	for p in 4:
		var pa: float = TAU * float(p) / 4.0 + 0.7
		GroundKit.cyl(root, 0.7, 0.9, 14.0, Vector3(tx + cos(pa) * 7.0, ty + 7.0, tz + sin(pa) * 7.0), Color(0.4, 0.4, 0.38), Vector3.ZERO, 6, false)
	# pumping house + small chimney
	_shed(root, 44.0, 11.0, 24.0, Vector3(74.0, _gh(root, Vector3(74.0, 0.0, -12.0)), -12.0), brick, 4.0)
	_chimney(root, Vector3(98.0, 0.0, -12.0), 22.0, 2.0, 1.3, brick, chimneys)


## Cement works: a cluster of silos, a long rotary kiln, a milling hall, basins, a tall chimney.
static func _cement_works(root: Node3D, size: int, chimneys: Array) -> void:
	var conc: Color = Color(0.7, 0.68, 0.63)
	var steel: Color = Color(0.5, 0.5, 0.5)
	var n_s: int = 4 + mini(size, 3)
	for i in n_s:
		var sx: float = (float(i % 3) - 1.0) * 17.0
		var sz: float = float(i / 3) * 17.0
		var gy: float = _gh(root, Vector3(sx, 0.0, sz))
		GroundKit.cyl(root, 7.0, 7.0, 34.0, Vector3(sx, gy + 17.0, sz), conc if i % 2 == 0 else conc.darkened(0.08), Vector3.ZERO, 14)
		GroundKit.cyl(root, 7.2, 7.2, 0.7, Vector3(sx, gy + 34.2, sz), steel, Vector3.ZERO, 14, false)
	# rotary kiln: a long inclined steel tube
	GroundKit.cyl(root, 4.0, 4.0, 84.0, Vector3(34.0, _gh(root, Vector3(34.0, 0.0, 84.0)) + 15.0, 84.0), steel.darkened(0.1), Vector3(78.0, 0.0, 0.0), 12)
	# milling / clinker hall
	_shed(root, 84.0, 16.0, 38.0, Vector3(-64.0, _gh(root, Vector3(-64.0, 0.0, 20.0)), 20.0), conc.darkened(0.05), 6.0)
	# tall chimney
	_chimney(root, Vector3(84.0, 0.0, -44.0), 56.0 + 4.0 * float(size), 4.0, 2.4, GroundKit.COL_BRICK.darkened(0.05), chimneys)
	# slurry basin
	GroundKit.cyl(root, 20.0, 20.0, 2.0, Vector3(-74.0, _gh(root, Vector3(-74.0, 0.0, -72.0)) + 0.6, -72.0), Color(0.5, 0.5, 0.48), Vector3.ZERO, 16)


## Staithes: coal drops on a raised timber trestle over a quay - hoppers, chutes, wagon rakes, barges below.
static func _staithes(root: Node3D, size: int, chimneys: Array) -> void:
	var wood: Color = GroundKit.COL_WOOD
	var brick: Color = GroundKit.COL_BRICK
	var conc: Color = GroundKit.COL_CONCRETE
	var deck_y: float = 16.0
	var L: float = 90.0 + 20.0 * float(size)
	# river wall / quay the staithes stand on (local -Z side faces the water)
	var qy: float = _gh(root, Vector3(0.0, 0.0, -30.0))
	GroundKit.box(root, Vector3(130.0, 10.0, 30.0), Vector3(0.0, qy - 3.0, -30.0), conc.darkened(0.16), Vector3.ZERO, false)
	# raised timber deck carrying the coal wagons
	var dy: float = _gh(root, Vector3(0.0, 0.0, 8.0)) + deck_y
	GroundKit.box(root, Vector3(40.0, 2.0, L), Vector3(0.0, dy, 8.0), wood)
	# supporting legs and cross bracing
	var n_leg: int = 6
	for i in n_leg:
		var z: float = 8.0 - L * 0.5 + 6.0 + float(i) * (L - 12.0) / float(n_leg - 1)
		for sx in [-1.0, 1.0]:
			GroundKit.cyl(root, 0.9, 1.1, deck_y, Vector3(sx * 18.0, _gh(root, Vector3(sx * 18.0, 0.0, z)) + deck_y * 0.5, z), wood.darkened(0.2), Vector3.ZERO, 6, false)
		GroundKit.box(root, Vector3(37.0, 0.6, 0.6), Vector3(0.0, dy - deck_y * 0.5, z), wood.darkened(0.25), Vector3.ZERO, false)
	# coal wagons on the deck
	for w in (4 + size):
		GroundKit.box(root, Vector3(8.0, 3.0, 3.2), Vector3(-14.0, dy + 2.6, -L * 0.38 + float(w) * 9.5), Color(0.24, 0.2, 0.18))
	# hoppers + inclined chutes spilling over the wall to the barges below
	var n_chute: int = 2 + size
	for i in n_chute:
		var hx: float = (float(i) - float(n_chute - 1) * 0.5) * 16.0
		GroundKit.box(root, Vector3(10.0, 10.0, 10.0), Vector3(hx, dy + 6.0, 8.0), Color(0.16, 0.15, 0.14))
		var cy: float = _gh(root, Vector3(hx, 0.0, -18.0))
		GroundKit.box(root, Vector3(6.0, 0.8, 30.0), Vector3(hx, cy + 9.0, -18.0), wood, Vector3(48.0, 0.0, 0.0), false)
	# barges moored along the quay below
	for i in (2 + size):
		GroundKit.box(root, Vector3(9.0, 3.2, 40.0), Vector3(0.0, qy - 8.0, -34.0 + (float(i) - float(1 + size) * 0.5) * 46.0), Color(0.22, 0.2, 0.18))
	# staithes engine house on the bank
	_shed(root, 26.0, 10.0, 18.0, Vector3(-52.0, _gh(root, Vector3(-52.0, 0.0, 0.0)), 0.0), brick, 3.8)
	_chimney(root, Vector3(-52.0, 0.0, -18.0), 26.0, 2.0, 1.3, brick, chimneys)


## Chalk / limestone quarry: the pale pits of the downs and the Portland / Beer stone quarries - an open pit
## with three stepped benches falling to a pale rubble floor, a vertical worked cut face with weathering
## streaks behind the top bench, spoil heaps tipped out beyond the pit, and the crusher / screening plant
## with an inclined conveyor, a lime-kiln stack and a couple of timber huts. Reuses the terrain shader's
## existing chalk / limestone / soil / olive palette entries - no new hues.
static func _quarry(root: Node3D, size: int, rng: RandomNumberGenerator, chimneys: Array) -> void:
	var chalk: Color = Color(0.62, 0.60, 0.53)          # chalk, toned down so the pit does not glare from the air
	var lime: Color = Color(0.50, 0.48, 0.42)           # limestone rubble, darkened
	var soil: Color = Color(0.30, 0.22, 0.14)           # terrain soil_col
	var grey: Color = GroundKit.COL_GREY
	var wood: Color = GroundKit.COL_WOOD
	var k: float = 1.0 + 0.25 * float(size)
	var gy: float = _gh(root, Vector3.ZERO)
	var pit_x: float = 72.0 * k
	var pit_z: float = 52.0 * k
	var bench_w: float = 20.0 * k
	var step_h: float = 5.0
	# the worked floor: a slab of pale limestone rubble lying in the middle of the pit
	GroundKit.box(root, Vector3(pit_x * 2.0, 0.6, pit_z * 2.0), Vector3(0.0, gy + 0.3, 0.0), lime, Vector3.ZERO, false)
	# three stepped benches rising outward: from the air they read as the terraces of the pit
	for s in 3:
		var hgt: float = step_h * float(s + 1)
		var cy: float = gy + hgt * 0.5
		var c_x: float = pit_x + bench_w * (float(s) + 0.5)
		var o_x: float = pit_x + bench_w * float(s + 1)
		var c_z: float = pit_z + bench_w * (float(s) + 0.5)
		var o_z: float = pit_z + bench_w * float(s + 1)
		GroundKit.box(root, Vector3(o_x * 2.0, hgt, bench_w), Vector3(0.0, cy, c_z), chalk, Vector3.ZERO, false)
		GroundKit.box(root, Vector3(o_x * 2.0, hgt, bench_w), Vector3(0.0, cy, -c_z), chalk, Vector3.ZERO, false)
		GroundKit.box(root, Vector3(bench_w, hgt, o_z * 2.0 + bench_w), Vector3(c_x, cy, 0.0), chalk, Vector3.ZERO, false)
		GroundKit.box(root, Vector3(bench_w, hgt, o_z * 2.0 + bench_w), Vector3(-c_x, cy, 0.0), chalk, Vector3.ZERO, false)
	# the vertical worked cut face standing behind the top bench, with faint vertical weathering streaks
	var face_z: float = pit_z + bench_w * 3.0 + 12.0
	GroundKit.box(root, Vector3(pit_x * 2.6, 26.0, 12.0), Vector3(0.0, gy + 13.0, face_z), chalk)
	for i in 7:
		GroundKit.box(root, Vector3(2.4, 22.0, 0.7), Vector3((float(i) - 3.0) * pit_x * 0.62, gy + 12.0, face_z - 6.4), grey.darkened(0.18), Vector3.ZERO, false)
	# the vegetated chalk cap above the face (downland turf), an olive entry
	GroundKit.box(root, Vector3(pit_x * 2.6, 5.0, 13.0), Vector3(0.0, gy + 28.0, face_z), GroundKit.COL_OLIVE.darkened(0.06), Vector3.ZERO, false)
	# spoil heaps tipped out beyond the near (-Z) benches: pale cones of chalk waste
	var n_spoil: int = 2 + mini(size, 2)
	for i in n_spoil:
		var hx: float = (float(i) - float(n_spoil - 1) * 0.5) * 44.0 * k
		var hz: float = -(pit_z + bench_w * 3.0 + 28.0)
		GroundKit.cyl(root, 5.0, 22.0, 16.0, Vector3(hx, _gh(root, Vector3(hx, 0.0, hz)) + 8.0, hz), lime.darkened(0.04), Vector3.ZERO, 14)
		GroundKit.cyl(root, 3.4, 5.0, 4.0, Vector3(hx, _gh(root, Vector3(hx, 0.0, hz)) + 18.0, hz), soil.lightened(0.3), Vector3.ZERO, 14, false)
	# the crushing and screening plant on the eastern bench
	var px: float = pit_x + bench_w * 3.6 + rng.randf_range(-3.0, 3.0)
	var py: float = _gh(root, Vector3(px, 0.0, 0.0))
	GroundKit.box(root, Vector3(9.0, 6.0, 9.0), Vector3(px - 8.0, py + 3.0, -18.0), grey.darkened(0.12))
	_shed(root, 22.0, 9.0, 14.0, Vector3(px + 8.0, _gh(root, Vector3(px + 8.0, 0.0, -20.0)), -20.0), grey.darkened(0.05), 3.5)
	# the screening bin on legs, fed by an inclined conveyor lifting out of the pit
	GroundKit.box(root, Vector3(13.0, 9.0, 13.0), Vector3(px + 6.0, py + 17.0, 8.0), grey.darkened(0.08))
	for lx in [-5.5, 5.5]:
		for lz in [-5.5, 5.5]:
			GroundKit.cyl(root, 0.5, 0.6, 13.0, Vector3(px + 6.0 + lx, py + 6.5, 8.0 + lz), grey.darkened(0.2), Vector3.ZERO, 6, false)
	GroundKit.box(root, Vector3(2.6, 1.8, 54.0), Vector3(px + 6.0, py + 9.0, -18.0), grey.darkened(0.15), Vector3(26.0, 0.0, 0.0), false)
	# a couple of timber quarry huts and the lime-kiln stack (the site's plume)
	_shed(root, 10.0, 4.0, 8.0, Vector3(px + 34.0, _gh(root, Vector3(px + 34.0, 0.0, 22.0)), 22.0), wood, 2.6)
	_shed(root, 14.0, 5.0, 9.0, Vector3(px + 34.0, _gh(root, Vector3(px + 34.0, 0.0, 40.0)), 40.0), wood.lightened(0.06), 3.0)
	_chimney(root, Vector3(px + 34.0, 0.0, -34.0), 24.0, 2.6, 1.5, GroundKit.COL_BRICK.lightened(0.12), chimneys)
