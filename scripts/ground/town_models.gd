class_name TownModels
extends RefCounted
## Detailed 1940s building models for the realistic scenery: the ten town house units (Scatter.house_mesh near
## LOD) and the landmark buildings that stand over the roofs (parish church, town hall).
##
## House units fill the same unit box as the old models (walls x/z -0.5..0.5, y -0.5..0.5, roof above, street
## front at -Z), because the placement transforms scale that box per house. Each is ONE surface with vertex
## colours on the building material (roof / wall is decided by the shader from the face normal), so a town is
## still one draw per variant. Landmarks are authored in metres on the painted-prop material.
## Geometry is original; nothing here is taken from any other game.


## Flat-shaded mesh builder: convex faces with a colour each, wound by an "outward" hint so no face is ever
## inside out.
class MB:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()

	func face(pts: Array, col: Color, out: Vector3) -> void:
		var p0: Vector3 = pts[0]
		var nr: Vector3 = ((pts[1] as Vector3) - p0).cross((pts[2] as Vector3) - p0)
		if nr.length_squared() < 1.0e-14:
			return
		nr = nr.normalized()
		var flip: bool = nr.dot(out) < 0.0
		if flip:
			nr = -nr
		var lin: Color = col.srgb_to_linear()
		for i in range(1, pts.size() - 1):
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			# Godot front faces are clockwise seen from outside
			var tri: Array = [p0, a, b] if flip else [p0, b, a]
			for q in tri:
				v.append(q as Vector3)
				n.append(nr)
				c.append(lin)
				uv.append(Vector2.ZERO)

	func box(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, col: Color, top: bool = true, top_col: Variant = null) -> void:
		face([Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0)], col, Vector3.LEFT)
		face([Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0)], col, Vector3.RIGHT)
		face([Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0)], col, Vector3.FORWARD)
		face([Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1)], col, Vector3.BACK)
		if top:
			var tc: Color = col if top_col == null else (top_col as Color)
			face([Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1)], tc, Vector3.UP)

	## Gable roof, ridge along X. `ov` = eaves overhang front and back (the slope carries on down past the wall),
	## `vx` = verge overhang past the gable walls. Gable triangles take the wall colour.
	func gable_x(x0: float, x1: float, z0: float, z1: float, y: float, h: float, ov: float, rc: Color, wc: Color, vx: float = 0.0) -> void:
		var zc: float = (z0 + z1) * 0.5
		var half: float = maxf((z1 - z0) * 0.5, 1.0e-5)
		var ye: float = y - ov * h / half
		face([Vector3(x0 - vx, ye, z0 - ov), Vector3(x1 + vx, ye, z0 - ov), Vector3(x1 + vx, y + h, zc), Vector3(x0 - vx, y + h, zc)], rc, Vector3(0, 1, -0.2))
		face([Vector3(x0 - vx, ye, z1 + ov), Vector3(x1 + vx, ye, z1 + ov), Vector3(x1 + vx, y + h, zc), Vector3(x0 - vx, y + h, zc)], rc, Vector3(0, 1, 0.2))
		face([Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(x0, y + h, zc)], wc, Vector3.LEFT)
		face([Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x1, y + h, zc)], wc, Vector3.RIGHT)

	## Gable roof, ridge along Z.
	func gable_z(x0: float, x1: float, z0: float, z1: float, y: float, h: float, ov: float, rc: Color, wc: Color, vz: float = 0.0) -> void:
		var xc: float = (x0 + x1) * 0.5
		var half: float = maxf((x1 - x0) * 0.5, 1.0e-5)
		var ye: float = y - ov * h / half
		face([Vector3(x0 - ov, ye, z0 - vz), Vector3(x0 - ov, ye, z1 + vz), Vector3(xc, y + h, z1 + vz), Vector3(xc, y + h, z0 - vz)], rc, Vector3(-0.2, 1, 0))
		face([Vector3(x1 + ov, ye, z0 - vz), Vector3(x1 + ov, ye, z1 + vz), Vector3(xc, y + h, z1 + vz), Vector3(xc, y + h, z0 - vz)], rc, Vector3(0.2, 1, 0))
		face([Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(xc, y + h, z0)], wc, Vector3.FORWARD)
		face([Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(xc, y + h, z1)], wc, Vector3.BACK)

	## Hipped roof, ridge along X shortened by `inset` at each end (inset = half the width gives a pyramid).
	func hip_x(x0: float, x1: float, z0: float, z1: float, y: float, h: float, inset: float, ov: float, rc: Color) -> void:
		var zc: float = (z0 + z1) * 0.5
		var half: float = maxf((z1 - z0) * 0.5, 1.0e-5)
		var ye: float = y - ov * h / half
		var a := Vector3(x0 - ov, ye, z0 - ov)
		var b := Vector3(x1 + ov, ye, z0 - ov)
		var cc := Vector3(x1 + ov, ye, z1 + ov)
		var d := Vector3(x0 - ov, ye, z1 + ov)
		var r0 := Vector3(minf(x0 + inset, (x0 + x1) * 0.5), y + h, zc)
		var r1 := Vector3(maxf(x1 - inset, (x0 + x1) * 0.5), y + h, zc)
		if r0.is_equal_approx(r1):
			face([a, b, r0], rc, Vector3(0, 1, -0.2))
			face([d, cc, r0], rc, Vector3(0, 1, 0.2))
		else:
			face([a, b, r1, r0], rc, Vector3(0, 1, -0.2))
			face([d, cc, r1, r0], rc, Vector3(0, 1, 0.2))
		face([a, d, r0], rc, Vector3(-0.2, 1, 0))
		face([b, cc, r1], rc, Vector3(0.2, 1, 0))

	## Hipped roof with the ridge along Z.
	func hip_z(x0: float, x1: float, z0: float, z1: float, y: float, h: float, inset: float, ov: float, rc: Color) -> void:
		var xc: float = (x0 + x1) * 0.5
		var half: float = maxf((x1 - x0) * 0.5, 1.0e-5)
		var ye: float = y - ov * h / half
		var a := Vector3(x0 - ov, ye, z0 - ov)
		var b := Vector3(x1 + ov, ye, z0 - ov)
		var cc := Vector3(x1 + ov, ye, z1 + ov)
		var d := Vector3(x0 - ov, ye, z1 + ov)
		var r0 := Vector3(xc, y + h, minf(z0 + inset, (z0 + z1) * 0.5))
		var r1 := Vector3(xc, y + h, maxf(z1 - inset, (z0 + z1) * 0.5))
		face([a, d, r1, r0], rc, Vector3(-0.2, 1, 0))
		face([b, cc, r1, r0], rc, Vector3(0.2, 1, 0))
		face([a, b, r0], rc, Vector3(0, 1, -0.2))
		face([d, cc, r1], rc, Vector3(0, 1, 0.2))

	## Mono-pitch (lean-to) roof over a rectangle. `high`: which edge is the high one ("x0", "x1", "z0", "z1").
	## The two sloping side walls are filled in the wall colour.
	func mono(x0: float, x1: float, z0: float, z1: float, y_lo: float, y_hi: float, high: String, rc: Color, wc: Color, ov: float = 0.0) -> void:
		var ya: float = y_hi if high == "x0" or high == "z0" else y_lo      # corner (x0, z0)
		var yb: float = y_hi if high == "x1" or high == "z0" else y_lo      # corner (x1, z0)
		var yc: float = y_hi if high == "x1" or high == "z1" else y_lo      # corner (x1, z1)
		var yd: float = y_hi if high == "x0" or high == "z1" else y_lo      # corner (x0, z1)
		face([Vector3(x0 - ov, ya, z0 - ov), Vector3(x1 + ov, yb, z0 - ov), Vector3(x1 + ov, yc, z1 + ov), Vector3(x0 - ov, yd, z1 + ov)], rc, Vector3.UP)
		if high == "x0" or high == "x1":
			var xh: float = x0 if high == "x0" else x1
			var xl: float = x1 if high == "x0" else x0
			face([Vector3(xl, y_lo, z0), Vector3(xh, y_lo, z0), Vector3(xh, y_hi, z0)], wc, Vector3.FORWARD)
			face([Vector3(xl, y_lo, z1), Vector3(xh, y_lo, z1), Vector3(xh, y_hi, z1)], wc, Vector3.BACK)
		else:
			var zh: float = z0 if high == "z0" else z1
			var zl: float = z1 if high == "z0" else z0
			face([Vector3(x0, y_lo, zl), Vector3(x0, y_lo, zh), Vector3(x0, y_hi, zh)], wc, Vector3.LEFT)
			face([Vector3(x1, y_lo, zl), Vector3(x1, y_lo, zh), Vector3(x1, y_hi, zh)], wc, Vector3.RIGHT)

	## Chimney stack with an oversailing cap and clay pots.
	func chimney(x: float, z: float, y0: float, y1: float, wx: float, wz: float, col: Color, pots: int = 2, pot_col: Color = Color(0.50, 0.30, 0.20)) -> void:
		var hx: float = wx * 0.5
		var hz: float = wz * 0.5
		var cap: float = (y1 - y0) * 0.10
		box(x - hx, x + hx, y0, y1 - cap, z - hz, z + hz, col, false)
		box(x - hx * 1.22, x + hx * 1.22, y1 - cap, y1, z - hz * 1.22, z + hz * 1.22, col.darkened(0.12))
		var along_z: bool = wz >= wx
		for i in pots:
			var t: float = (float(i) + 0.5) / float(pots) - 0.5
			var px: float = x + (0.0 if along_z else t * wx * 1.1)
			var pz: float = z + (t * wz * 1.1 if along_z else 0.0)
			var psx: float = hx * 0.45 if along_z else hx * 0.62 / float(pots)
			var psz: float = hz * 0.62 / float(pots) if along_z else hz * 0.45
			box(px - psx, px + psx, y1, y1 + cap * 1.6, pz - psz, pz + psz, pot_col)

	## Upright n-sided prism / taper (radii given separately in x and z so it stays round in a stretched unit box).
	func prism(cx: float, cz: float, y0: float, y1: float, rx0: float, rz0: float, rx1: float, rz1: float, segs: int, col: Color, cap: bool = true, rot: float = 0.0) -> void:
		var top: Array = []
		for i in segs:
			var a0: float = rot + TAU * float(i) / float(segs)
			var a1: float = rot + TAU * float(i + 1) / float(segs)
			var b0 := Vector3(cx + cos(a0) * rx0, y0, cz + sin(a0) * rz0)
			var b1 := Vector3(cx + cos(a1) * rx0, y0, cz + sin(a1) * rz0)
			var t0 := Vector3(cx + cos(a0) * rx1, y1, cz + sin(a0) * rz1)
			var t1 := Vector3(cx + cos(a1) * rx1, y1, cz + sin(a1) * rz1)
			var am: float = (a0 + a1) * 0.5
			var outv := Vector3(cos(am), 0.15, sin(am))
			if rx1 <= 1.0e-6 and rz1 <= 1.0e-6:
				face([b0, b1, t0], col, outv)
			else:
				face([b0, b1, t1, t0], col, outv)
				top.append(t0)
		if cap and top.size() >= 3:
			face(top, col, Vector3.UP)

	## A rectangular bar between two points in the XY plane (thickness `wy` in that plane, `wz` across it).
	func beam(a: Vector3, bpt: Vector3, wy: float, wz: float, col: Color) -> void:
		var d: Vector3 = (bpt - a)
		if d.length() < 1.0e-4:
			return
		d = d.normalized()
		var up := Vector3(-d.y, d.x, 0.0) * wy
		var zz := Vector3(0.0, 0.0, wz)
		var c: Array = [a - up - zz, a + up - zz, a + up + zz, a - up + zz, bpt - up - zz, bpt + up - zz, bpt + up + zz, bpt - up + zz]
		face([c[1], c[2], c[6], c[5]], col, up)
		face([c[0], c[3], c[7], c[4]], col, -up)
		face([c[2], c[3], c[7], c[6]], col, zz)
		face([c[0], c[1], c[5], c[4]], col, -zz)

	func commit(material: Material) -> ArrayMesh:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_COLOR] = c
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, material)
		return m


static var _cache: Dictionary = {}
static var _on: int = -1


## True when the detailed models are in use: realistic scenery, unless WW2_OLD_TOWN is set (before/after shots).
static func enabled() -> bool:
	if _on < 0:
		_on = 1 if OS.get_environment("WW2_OLD_TOWN") == "" else 0
	return _on == 1 and GameState.realistic_scenery
static var _house_mat: ShaderMaterial
static var _paint_mat: ShaderMaterial


## The building material (flat-shaded toon/real shader, detail 1: roof tiles, per-house roof and facade tones)
## reading the part colour from the vertex colours.
static func house_material() -> ShaderMaterial:
	if _house_mat == null:
		_house_mat = (Scatter._dmat(Color.WHITE, 1, 0.0, false) as ShaderMaterial).duplicate()
		_house_mat.set_shader_parameter("albedo", Color.WHITE)
		_house_mat.set_shader_parameter("use_vcol", true)
	return _house_mat


## The painted-prop material (ground_paint) with vertex colours: landmark buildings keep the colours they are given.
static func paint_material() -> ShaderMaterial:
	if _paint_mat == null:
		_paint_mat = (GroundKit.mat(Color(0.5, 0.5, 0.5)) as ShaderMaterial).duplicate()
		_paint_mat.set_shader_parameter("albedo", Color.WHITE)
		_paint_mat.set_shader_parameter("use_vcol", true)
		_paint_mat.set_shader_parameter("roughness_v", 0.86)
		_paint_mat.set_shader_parameter("wear", 0.45)
	return _paint_mat


const BRICK := Color(0.46, 0.28, 0.21)
const BRICK_DK := Color(0.35, 0.23, 0.18)
const STONE := Color(0.52, 0.47, 0.40)
const SLATE := Color(0.29, 0.30, 0.33)
const TILE := Color(0.46, 0.28, 0.19)
const STACK := Color(0.34, 0.22, 0.17)
const THATCH := Color(0.50, 0.42, 0.26)
const LEAD := Color(0.34, 0.33, 0.31)


## Detailed house unit `variant` (0..9, the Scatter.house_mesh contract).
static func house(variant: int) -> ArrayMesh:
	var key: String = "house%d" % variant
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	match variant:
		0:
			_terrace_bay(b)
		1:
			_terrace_plain(b)
		2:
			_semi_pair(b)
		3:
			_cottage(b)
		4:
			_corner_shop(b)
		5:
			_villa(b)
		6:
			_warehouse(b)
		7:
			_works(b)
		8:
			_cinema(b)
		_:
			_station(b)
	var m: ArrayMesh = b.commit(house_material())
	_cache[key] = m
	return m


# ---- 0: bay-fronted brick terrace house: ridge along the street, shared stack, two-storey rear outrigger
static func _terrace_bay(b: MB) -> void:
	var wall: Color = BRICK
	b.box(-0.5, 0.5, -0.5, 0.5, -0.5, 0.5, wall, false)
	b.gable_x(-0.5, 0.5, -0.5, 0.5, 0.5, 0.46, 0.07, TILE, wall)
	b.chimney(-0.37, 0.02, 0.74, 1.17, 0.12, 0.17, STACK, 2)
	# ground-floor bay with its own little roof
	b.box(-0.16, 0.24, -0.5, 0.00, -0.585, -0.5, wall * 0.93, false)
	b.mono(-0.16, 0.24, -0.585, -0.5, 0.00, 0.10, "z1", TILE, wall * 0.93, 0.012)
	# door step and hood beside the bay
	b.box(-0.40, -0.24, -0.5, -0.455, -0.555, -0.5, STONE * 0.9)
	b.box(-0.41, -0.23, -0.10, -0.075, -0.56, -0.5, LEAD)
	# rear outrigger (kitchen and back bedroom) with a mono-pitch roof against the party wall, and its own flue
	b.box(0.05, 0.47, -0.5, 0.20, 0.5, 0.92, wall * 0.96, false)
	b.mono(0.05, 0.47, 0.5, 0.92, 0.20, 0.36, "x1", TILE, wall * 0.96, 0.015)
	b.chimney(0.42, 0.86, 0.26, 0.56, 0.07, 0.07, STACK, 1)


# ---- 1: plain-fronted, sooty terrace house: raised party wall, stack at the other end, gabled back addition
static func _terrace_plain(b: MB) -> void:
	var wall: Color = BRICK_DK
	b.box(-0.5, 0.5, -0.5, 0.5, -0.5, 0.5, wall, false)
	b.gable_x(-0.5, 0.5, -0.5, 0.5, 0.5, 0.42, 0.06, SLATE, wall)
	# fire-break party wall standing proud of the roof
	b.gable_x(-0.5, -0.455, -0.555, 0.555, 0.5, 0.47, 0.0, wall * 0.9, wall * 0.9)
	b.chimney(0.37, -0.02, 0.72, 1.12, 0.12, 0.17, STACK, 2)
	b.box(0.12, 0.30, -0.5, -0.455, -0.55, -0.5, STONE * 0.9)
	b.box(0.11, 0.31, -0.10, -0.075, -0.555, -0.5, LEAD)
	b.box(-0.47, -0.08, -0.5, 0.14, 0.5, 0.90, wall * 0.96, false)
	b.gable_z(-0.47, -0.08, 0.5, 0.90, 0.14, 0.17, 0.015, SLATE, wall * 0.96, 0.01)
	# wash-house against the back addition
	b.box(-0.08, 0.16, -0.5, -0.10, 0.5, 0.74, wall * 0.9, false)
	b.mono(-0.08, 0.16, 0.5, 0.74, -0.10, 0.02, "z0", SLATE, wall * 0.9, 0.012)


# ---- 2: 1930s semi-detached pair: one hipped roof, shared central stack, twin gabled bays
static func _semi_pair(b: MB) -> void:
	var wall: Color = BRICK
	var render: Color = Color(0.60, 0.56, 0.48)
	b.box(-0.5, 0.5, -0.5, 0.5, -0.5, 0.5, wall, false)
	b.hip_x(-0.5, 0.5, -0.5, 0.5, 0.5, 0.44, 0.30, 0.06, TILE)
	b.chimney(0.0, 0.0, 0.72, 1.14, 0.13, 0.20, STACK, 2)
	for sx in [-1.0, 1.0]:
		var x0: float = minf(sx * 0.15, sx * 0.44)
		var x1: float = maxf(sx * 0.15, sx * 0.44)
		b.box(x0, x1, -0.5, 0.5, -0.60, -0.5, wall, false)
		b.gable_z(x0, x1, -0.60, -0.16, 0.5, 0.25, 0.02, TILE, render, 0.012)
		# single-storey kitchen at the back, and a porch hood by each front door
		b.box(minf(sx * 0.10, sx * 0.44), maxf(sx * 0.10, sx * 0.44), -0.5, -0.06, 0.5, 0.74, wall * 0.95, true, LEAD)
		b.box(minf(sx * 0.02, sx * 0.13), maxf(sx * 0.02, sx * 0.13), -0.08, -0.05, -0.57, -0.5, LEAD)
		# garage / coal store set back at each side
		b.box(minf(sx * 0.5, sx * 0.62), maxf(sx * 0.5, sx * 0.62), -0.5, -0.12, -0.10, 0.42, wall * 0.9, true, LEAD)


# ---- 3: cottage: low stone walls, deep half-hipped roof, gable-end stack, catslide at the back, small porch
static func _cottage(b: MB) -> void:
	b.box(-0.5, 0.5, -0.5, 0.28, -0.5, 0.5, STONE, false)
	b.hip_x(-0.5, 0.5, -0.5, 0.5, 0.28, 0.62, 0.14, 0.08, THATCH)
	b.box(-0.585, -0.47, -0.5, 0.86, -0.10, 0.10, STONE * 0.92, false)
	b.box(-0.60, -0.455, 0.86, 0.92, -0.12, 0.12, STONE * 0.8)
	b.box(-0.555, -0.50, 0.92, 0.99, -0.045, 0.045, Color(0.50, 0.30, 0.20))
	b.box(-0.30, 0.42, -0.5, -0.08, 0.5, 0.78, STONE * 0.95, false)
	b.mono(-0.30, 0.42, 0.5, 0.78, -0.08, 0.26, "z0", THATCH, STONE * 0.95, 0.02)
	b.box(-0.06, 0.14, -0.5, -0.06, -0.60, -0.5, STONE * 0.95, false)
	b.gable_z(-0.06, 0.14, -0.60, -0.5, -0.06, 0.13, 0.015, THATCH, STONE * 0.95, 0.012)


# ---- 4: corner shop: parapet and cornice, fascia and awning over the pavement, flat roof with a stair head
static func _corner_shop(b: MB) -> void:
	var wall: Color = BRICK * 1.06
	var cope: Color = STONE * 1.05
	b.box(-0.5, 0.5, -0.5, 0.5, -0.5, 0.5, wall, true, LEAD)
	# parapet round the roof
	b.box(-0.5, 0.5, 0.5, 0.60, -0.5, -0.46, wall, true, cope)
	b.box(-0.5, 0.5, 0.5, 0.57, 0.46, 0.5, wall, true, cope)
	b.box(-0.5, -0.47, 0.5, 0.57, -0.46, 0.46, wall, true, cope)
	b.box(0.47, 0.5, 0.5, 0.57, -0.46, 0.46, wall, true, cope)
	b.box(-0.515, 0.515, 0.40, 0.44, -0.525, -0.5, cope)
	# shopfront: stall riser, fascia board and a canvas awning
	b.box(-0.47, 0.47, -0.5, -0.40, -0.52, -0.5, Color(0.18, 0.20, 0.19))
	b.box(-0.48, 0.48, -0.20, -0.12, -0.535, -0.5, Color(0.20, 0.24, 0.26))
	b.face([Vector3(-0.44, -0.20, -0.535), Vector3(0.44, -0.20, -0.535), Vector3(0.44, -0.27, -0.70), Vector3(-0.44, -0.27, -0.70)], Color(0.58, 0.52, 0.40), Vector3.UP)
	b.face([Vector3(-0.44, -0.27, -0.70), Vector3(0.44, -0.27, -0.70), Vector3(0.44, -0.30, -0.70), Vector3(-0.44, -0.30, -0.70)], Color(0.50, 0.44, 0.34), Vector3.FORWARD)
	# stair head, stack and a yard building behind
	b.box(0.14, 0.40, 0.5, 0.70, 0.08, 0.40, wall * 0.95, true, LEAD)
	b.chimney(-0.36, 0.38, 0.5, 0.88, 0.11, 0.13, STACK, 2)
	b.box(-0.5, 0.08, -0.5, 0.02, 0.5, 0.80, wall * 0.92, false)
	b.mono(-0.5, 0.08, 0.5, 0.80, 0.02, 0.14, "z0", SLATE, wall * 0.92, 0.012)


# ---- 5: Victorian villa: steep slate roof, gabled front wing with a bay, tall end stacks, back wing
static func _villa(b: MB) -> void:
	var wall: Color = BRICK * 0.95
	var roof: Color = SLATE * 1.05
	b.box(-0.5, 0.5, -0.5, 0.5, -0.5, 0.5, wall, false)
	b.gable_x(-0.5, 0.5, -0.5, 0.5, 0.5, 0.50, 0.06, roof, wall, 0.02)
	b.box(0.03, 0.46, -0.5, 0.5, -0.64, -0.5, wall, false)
	b.gable_z(0.03, 0.46, -0.64, -0.10, 0.5, 0.40, 0.02, roof, wall, 0.015)
	b.box(0.10, 0.39, -0.5, -0.02, -0.715, -0.64, wall * 0.9, false)
	b.mono(0.10, 0.39, -0.715, -0.64, -0.02, 0.07, "z1", roof, wall * 0.9, 0.012)
	b.box(-0.36, -0.16, -0.5, -0.06, -0.58, -0.5, wall * 0.9, false)
	b.mono(-0.36, -0.16, -0.58, -0.5, -0.06, 0.03, "z1", roof, wall * 0.9, 0.012)
	b.chimney(-0.44, 0.0, 0.62, 1.30, 0.10, 0.18, STACK, 2)
	b.chimney(0.44, 0.10, 0.62, 1.26, 0.10, 0.18, STACK, 2)
	b.box(-0.46, -0.04, -0.5, 0.30, 0.5, 0.86, wall * 0.96, false)
	b.gable_z(-0.46, -0.04, 0.5, 0.86, 0.30, 0.24, 0.02, roof, wall * 0.96, 0.012)


# ---- 6: warehouse: twin-gabled brick block on a stone plinth, hoist housing and a loading canopy
static func _warehouse(b: MB) -> void:
	var wall: Color = BRICK_DK
	var roof: Color = SLATE * 0.9
	b.box(-0.5, 0.5, -0.5, 0.5, -0.5, 0.5, wall, false)
	b.box(-0.508, 0.508, -0.5, -0.40, -0.508, 0.508, STONE * 0.72)
	b.gable_z(-0.5, 0.0, -0.5, 0.5, 0.5, 0.20, 0.0, roof, wall)
	b.gable_z(0.0, 0.5, -0.5, 0.5, 0.5, 0.20, 0.0, roof, wall)
	# coped gable parapets front and back
	for gx in [-0.25, 0.25]:
		b.gable_z(gx - 0.25, gx + 0.25, -0.515, -0.5, 0.5, 0.235, 0.0, STONE * 0.85, wall)
		b.gable_z(gx - 0.25, gx + 0.25, 0.5, 0.515, 0.5, 0.235, 0.0, STONE * 0.85, wall)
	b.box(-0.07, 0.07, 0.12, 0.56, -0.60, -0.5, Color(0.26, 0.22, 0.19), false)
	b.gable_z(-0.07, 0.07, -0.60, -0.5, 0.56, 0.08, 0.01, roof, Color(0.26, 0.22, 0.19), 0.01)
	b.box(-0.32, 0.32, -0.20, -0.17, -0.63, -0.5, LEAD)
	b.box(-0.30, 0.30, -0.5, -0.36, -0.585, -0.5, STONE * 0.8)


# ---- 7: works: north-light sawtooth roof over the shed, an office block on the street and a tall works chimney
static func _works(b: MB) -> void:
	var wall: Color = BRICK_DK * 1.1
	var glass: Color = Color(0.15, 0.19, 0.22)
	var roof: Color = Color(0.30, 0.29, 0.28)
	b.box(-0.5, 0.5, -0.5, 0.30, -0.5, 0.5, wall, false)
	for i in 4:
		var xa: float = -0.5 + float(i) * 0.25
		var xb: float = xa + 0.25
		b.face([Vector3(xa, 0.30, -0.5), Vector3(xa, 0.52, -0.5), Vector3(xa, 0.52, 0.5), Vector3(xa, 0.30, 0.5)], glass, Vector3.LEFT)
		b.face([Vector3(xa, 0.52, -0.5), Vector3(xb, 0.30, -0.5), Vector3(xb, 0.30, 0.5), Vector3(xa, 0.52, 0.5)], roof, Vector3.UP)
		b.face([Vector3(xa, 0.30, -0.5), Vector3(xb, 0.30, -0.5), Vector3(xa, 0.52, -0.5)], wall, Vector3.FORWARD)
		b.face([Vector3(xa, 0.30, 0.5), Vector3(xb, 0.30, 0.5), Vector3(xa, 0.52, 0.5)], wall, Vector3.BACK)
	# office block with a parapet, facing the street
	b.box(-0.5, -0.08, -0.5, 0.10, -0.72, -0.5, wall * 1.08, true, LEAD)
	b.box(-0.508, -0.072, 0.10, 0.15, -0.728, -0.70, STONE * 0.9)
	# boiler house and the stack
	b.box(0.20, 0.5, -0.5, 0.02, 0.5, 0.78, wall * 0.92, true, LEAD)
	b.prism(0.36, 0.66, -0.5, 1.50, 0.062, 0.090, 0.040, 0.058, 8, STACK, true, PI / 8.0)
	b.prism(0.36, 0.66, 1.50, 1.56, 0.050, 0.072, 0.050, 0.072, 8, STACK.darkened(0.2), true, PI / 8.0)


# ---- 8: picture palace: plain auditorium behind a stepped art-deco front with a fin and a lit canopy
static func _cinema(b: MB) -> void:
	var aud: Color = Color(0.50, 0.42, 0.36)
	var front: Color = Color(0.63, 0.60, 0.55)
	b.box(-0.43, 0.43, -0.5, 0.36, -0.36, 0.5, aud, true, LEAD)
	b.box(-0.43, 0.43, 0.36, 0.40, -0.36, -0.33, aud * 0.9)
	b.box(0.08, 0.30, 0.36, 0.45, 0.10, 0.34, aud * 0.9, true, LEAD)
	b.box(-0.47, 0.47, -0.5, 0.24, -0.58, -0.36, front, true, LEAD)
	b.box(-0.30, 0.30, 0.24, 0.38, -0.58, -0.36, front, true, LEAD)
	b.box(-0.15, 0.15, 0.38, 0.54, -0.60, -0.36, front * 1.03, true, LEAD)
	b.box(-0.028, 0.028, 0.10, 0.78, -0.635, -0.58, front * 1.06)
	# canopy with its lit edge, and the dark entrance below
	b.box(-0.34, 0.34, -0.16, -0.11, -0.73, -0.58, Color(0.30, 0.28, 0.26))
	b.box(-0.345, 0.345, -0.165, -0.105, -0.738, -0.73, Color(0.98, 0.86, 0.42))
	b.box(-0.16, 0.16, -0.5, -0.19, -0.588, -0.58, Color(0.12, 0.11, 0.10))
	b.box(-0.22, 0.22, -0.5, -0.47, -0.66, -0.58, Color(0.45, 0.43, 0.40))


# ---- 9: railway station: long slated range, gabled pavilions to the town, ridge stacks, clock turret and a
#         platform canopy on posts along the track side (-Z)
static func _station(b: MB) -> void:
	var wall: Color = BRICK
	var trim: Color = STONE * 1.05
	b.box(-0.5, 0.5, -0.5, 0.16, -0.5, 0.5, wall, false)
	b.box(-0.504, 0.504, -0.5, -0.40, -0.506, 0.506, trim * 0.8)
	b.gable_x(-0.5, 0.5, -0.5, 0.5, 0.16, 0.30, 0.05, SLATE, wall, 0.008)
	for px in [-0.30, 0.30]:
		b.box(px - 0.09, px + 0.09, -0.5, 0.22, 0.5, 0.60, wall, false)
		b.gable_z(px - 0.09, px + 0.09, 0.02, 0.60, 0.22, 0.20, 0.008, SLATE, trim, 0.02)
	for cx in [-0.42, -0.14, 0.14, 0.42]:
		b.chimney(cx, 0.0, 0.34, 0.66, 0.022, 0.12, STACK, 2)
	b.box(-0.035, 0.035, 0.40, 0.70, -0.11, 0.11, trim, false)
	b.hip_x(-0.035, 0.035, -0.11, 0.11, 0.70, 0.16, 0.035, 0.006, LEAD)
	b.box(-0.02, 0.02, 0.52, 0.64, -0.118, -0.11, Color(0.86, 0.84, 0.76))
	b.box(-0.02, 0.02, 0.52, 0.64, 0.11, 0.118, Color(0.86, 0.84, 0.76))
	# platform canopy: glazed slope, valance board, a row of iron posts
	b.face([Vector3(-0.49, 0.04, -0.5), Vector3(0.49, 0.04, -0.5), Vector3(0.49, -0.04, -0.90), Vector3(-0.49, -0.04, -0.90)], Color(0.34, 0.36, 0.36), Vector3.UP)
	b.face([Vector3(-0.49, 0.025, -0.5), Vector3(0.49, 0.025, -0.5), Vector3(0.49, -0.055, -0.90), Vector3(-0.49, -0.055, -0.90)], Color(0.30, 0.28, 0.25), Vector3.DOWN)
	b.box(-0.49, 0.49, -0.10, -0.04, -0.905, -0.895, Color(0.52, 0.47, 0.36))
	for i in 8:
		var qx: float = -0.455 + float(i) * 0.13
		b.box(qx - 0.004, qx + 0.004, -0.5, -0.05, -0.865, -0.845, Color(0.24, 0.26, 0.24), false)


# ------------------------------------------------------------------ landmarks (metres, origin on the ground)

## Parish church: aisled nave and lower chancel under slate roofs, south porch, buttressed west tower with a
## stair turret, string courses and corner pinnacles. `spire` adds a slated octagonal spire (about 48 m to the
## vane); without it the tower is finished with battlements, as most Kent and Sussex towers are.
static func church(spire: bool) -> ArrayMesh:
	var key: String = "church_%s" % str(spire)
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var stone := Color(0.60, 0.56, 0.48)
	var dress := Color(0.68, 0.65, 0.57)
	var roof := Color(0.27, 0.27, 0.30)
	var lead := Color(0.40, 0.41, 0.42)
	# nave and clerestory roof
	b.box(-5.0, 5.0, 0.0, 10.0, -12.0, 9.0, stone, false)
	b.gable_z(-5.0, 5.0, -12.0, 9.0, 10.0, 5.6, 0.45, roof, stone, 0.3)
	# aisles under lean-to lead roofs
	for sx in [-1.0, 1.0]:
		var x0: float = minf(sx * 5.0, sx * 8.6)
		var x1: float = maxf(sx * 5.0, sx * 8.6)
		b.box(x0, x1, 0.0, 5.2, -10.5, 8.0, stone * 0.97, false)
		b.mono(x0, x1, -10.5, 8.0, 5.2, 7.6, "x1" if sx < 0.0 else "x0", lead, stone * 0.97, 0.3)
		for bi in 5:
			var bz: float = lerpf(-10.0, 7.5, float(bi) / 4.0)
			b.box(minf(sx * 8.6, sx * 9.5), maxf(sx * 8.6, sx * 9.5), 0.0, 3.6, bz - 0.4, bz + 0.4, dress * 0.9, false)
			b.mono(minf(sx * 8.6, sx * 9.5), maxf(sx * 8.6, sx * 9.5), bz - 0.4, bz + 0.4, 3.6, 4.6, "x1" if sx < 0.0 else "x0", dress * 0.9, dress * 0.9)
	# chancel with diagonal east buttresses, and a vestry
	b.box(-3.8, 3.8, 0.0, 7.4, -20.0, -12.0, stone, false)
	b.gable_z(-3.8, 3.8, -20.0, -12.0, 7.4, 4.4, 0.4, roof, stone, 0.3)
	for sx2 in [-1.0, 1.0]:
		b.box(minf(sx2 * 3.4, sx2 * 4.6), maxf(sx2 * 3.4, sx2 * 4.6), 0.0, 5.0, -20.8, -19.8, dress * 0.9)
	b.box(-7.4, -3.8, 0.0, 3.8, -17.5, -13.0, stone * 0.95, false)
	b.mono(-7.4, -3.8, -17.5, -13.0, 3.8, 5.4, "x1", lead, stone * 0.95, 0.25)
	# south porch
	b.box(8.6, 11.6, 0.0, 3.4, 1.0, 5.0, stone * 0.96, false)
	b.gable_x(8.6, 11.6, 1.0, 5.0, 3.4, 2.2, 0.3, roof, stone * 0.96, 0.25)
	b.box(11.5, 11.66, 0.0, 2.6, 2.3, 3.7, Color(0.16, 0.13, 0.10))
	# west tower: three stages marked by string courses, clasping buttresses that step in
	var tz0: float = 9.0
	var tz1: float = 16.0
	b.box(-3.5, 3.5, 0.0, 27.0, tz0, tz1, stone, false)
	for sy in [9.5, 18.5]:
		b.box(-3.68, 3.68, sy, sy + 0.45, tz0 - 0.18, tz1 + 0.18, dress)
	for cx in [-1.0, 1.0]:
		for cz in [0.0, 1.0]:
			var bx: float = cx * 3.5
			var bzz: float = tz1 if cz > 0.5 else tz0
			var dz: float = 1.0 if cz > 0.5 else -1.0
			b.box(minf(bx, bx + cx * 0.9) - 0.5, maxf(bx, bx + cx * 0.9) + 0.5, 0.0, 9.5, minf(bzz, bzz + dz * 0.9) - 0.5, maxf(bzz, bzz + dz * 0.9) + 0.5, dress * 0.92, false)
			b.hip_x(minf(bx, bx + cx * 0.9) - 0.5, maxf(bx, bx + cx * 0.9) + 0.5, minf(bzz, bzz + dz * 0.9) - 0.5, maxf(bzz, bzz + dz * 0.9) + 0.5, 9.5, 1.4, 0.95, 0.0, dress * 0.92)
			b.box(minf(bx, bx + cx * 0.45) - 0.35, maxf(bx, bx + cx * 0.45) + 0.35, 9.5, 18.5, minf(bzz, bzz + dz * 0.45) - 0.35, maxf(bzz, bzz + dz * 0.45) + 0.35, dress * 0.95, false)
	# louvred belfry openings (one each face) and the west door
	for f in 4:
		var ang: float = float(f) * PI * 0.5
		var dx: float = cos(ang)
		var dzz: float = sin(ang)
		var mx: float = dx * 3.5
		var mz: float = (tz0 + tz1) * 0.5 + dzz * 3.5
		if absf(dx) > 0.5:
			b.box(mx - 0.08, mx + 0.08, 20.4, 24.4, mz - 0.8, mz + 0.8, Color(0.17, 0.16, 0.15))
		else:
			b.box(mx - 0.8, mx + 0.8, 20.4, 24.4, mz - 0.08, mz + 0.08, Color(0.17, 0.16, 0.15))
	b.box(-1.1, 1.1, 0.0, 3.6, tz1, tz1 + 0.1, Color(0.16, 0.13, 0.10))
	# parapet: battlements and four corner pinnacles
	b.box(-3.75, 3.75, 27.0, 27.5, tz0 - 0.25, tz1 + 0.25, dress, true, lead)
	for m in 4:
		var t: float = -2.85 + float(m) * 1.9
		b.box(t - 0.5, t + 0.5, 27.5, 28.6, tz0 - 0.25, tz0 + 0.2, dress)
		b.box(t - 0.5, t + 0.5, 27.5, 28.6, tz1 - 0.2, tz1 + 0.25, dress)
		b.box(-3.75, -3.3, 27.5, 28.6, 12.5 + t - 0.5, 12.5 + t + 0.5, dress)
		b.box(3.3, 3.75, 27.5, 28.6, 12.5 + t - 0.5, 12.5 + t + 0.5, dress)
	for px in [-3.4, 3.4]:
		for pz in [tz0 + 0.1, tz1 - 0.1]:
			b.box(px - 0.5, px + 0.5, 27.5, 29.6, pz - 0.5, pz + 0.5, dress, false)
			b.prism(px, pz, 29.6, 32.6 if spire else 32.0, 0.62, 0.62, 0.0, 0.0, 4, dress * 0.95, false, PI * 0.25)
	# stair turret up the south-east corner, rising above the parapet
	b.prism(3.3, tz0 + 0.3, 0.0, 30.4, 1.25, 1.25, 1.25, 1.25, 8, stone * 0.97, true, PI / 8.0)
	b.prism(3.3, tz0 + 0.3, 30.4, 32.4, 1.35, 1.35, 0.0, 0.0, 8, lead, false, PI / 8.0)
	if spire:
		b.prism(0.0, 12.5, 27.5, 47.0, 3.25, 3.25, 0.16, 0.16, 8, Color(0.32, 0.34, 0.38), true, PI / 8.0)
		b.box(-0.07, 0.07, 47.0, 49.2, 12.43, 12.57, Color(0.60, 0.50, 0.22))
		b.box(-0.5, 0.5, 48.5, 48.62, 12.45, 12.55, Color(0.60, 0.50, 0.22))
	else:
		b.hip_x(-3.2, 3.2, tz0 + 0.3, tz1 - 0.3, 27.5, 1.4, 3.2, 0.0, lead)
		b.box(-0.06, 0.06, 28.9, 34.5, 12.44, 12.56, Color(0.85, 0.85, 0.82))
	var m2: ArrayMesh = b.commit(paint_material())
	_cache[key] = m2
	return m2


## Town hall: a stone civic block on a rusticated base with end pavilions, a columned portico and pediment
## over the steps, a slated hipped roof with stacks, and a clock tower carrying a copper-green cupola.
## Authored at scale 1 (about 26 x 18 m on plan, 35 m to the finial); the street front is -Z.
static func town_hall() -> ArrayMesh:
	var key: String = "townhall"
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var stone := Color(0.60, 0.56, 0.49)
	var dress := Color(0.68, 0.65, 0.58)
	var base := Color(0.46, 0.43, 0.38)
	var roof := Color(0.27, 0.28, 0.31)
	var copper := Color(0.36, 0.53, 0.46)
	b.box(-12.0, 12.0, 0.0, 12.0, -8.0, 8.0, stone, false)
	b.box(-12.25, 12.25, 0.0, 2.6, -8.25, 8.25, base)
	b.box(-12.3, 12.3, 6.4, 6.8, -8.3, 8.3, dress)
	# end pavilions breaking forward, with their own little pediments
	for sx in [-1.0, 1.0]:
		var x0: float = minf(sx * 8.4, sx * 12.5)
		var x1: float = maxf(sx * 8.4, sx * 12.5)
		b.box(x0, x1, 0.0, 12.0, -9.0, -8.0, stone * 1.02, false)
		b.box(x0 - 0.1, x1 + 0.1, 0.0, 2.6, -9.25, -8.0, base)
		b.gable_z(x0, x1, -9.2, -4.0, 12.6, 1.7, 0.3, roof, dress, 0.0)
	# cornice, blocking course and the hipped roof behind it
	b.box(-12.6, 12.6, 12.0, 12.6, -9.3, 8.6, dress)
	b.box(-12.2, 12.2, 12.6, 13.3, -8.3, 8.2, stone, true, Color(0.36, 0.36, 0.37))
	b.hip_x(-11.6, 11.6, -7.6, 7.6, 13.3, 3.6, 7.6, 0.0, roof)
	for cx in [-9.0, 9.0]:
		for cz in [-3.5, 3.5]:
			b.chimney(cx, cz, 13.3, 18.2, 1.3, 2.0, stone * 0.85, 2)
	# steps, portico columns, entablature and pediment
	for s in 4:
		var sd: float = float(s)
		b.box(-7.6 + sd * 0.15, 7.6 - sd * 0.15, sd * 0.45, (sd + 1.0) * 0.45, -13.2 + sd * 0.5, -8.0, dress * (0.90 + 0.02 * sd))
	for ci in 6:
		var colx: float = -6.25 + float(ci) * 2.5
		b.box(colx - 0.62, colx + 0.62, 1.8, 2.3, -11.62, -10.38, dress)
		b.prism(colx, -11.0, 2.3, 9.6, 0.50, 0.50, 0.42, 0.42, 10, dress * 1.03, false)
		b.box(colx - 0.60, colx + 0.60, 9.6, 10.0, -11.60, -10.40, dress)
	b.box(-7.2, 7.2, 10.0, 11.3, -11.75, -8.0, dress)
	b.gable_z(-7.4, 7.4, -11.9, -8.0, 11.3, 2.7, 0.0, roof, stone * 1.04, 0.0)
	b.box(-1.5, 1.5, 1.8, 6.2, -8.12, -8.0, Color(0.16, 0.13, 0.10))
	# clock tower: shaft, clock stage with four faces, open belfry, cupola and finial
	b.box(-2.7, 2.7, 13.0, 23.0, -2.7, 2.7, stone, false)
	b.box(-3.0, 3.0, 18.2, 18.6, -3.0, 3.0, dress)
	b.box(-3.1, 3.1, 23.0, 23.7, -3.1, 3.1, dress)
	for f in 4:
		var ang: float = float(f) * PI * 0.5
		var dx: float = cos(ang)
		var dz: float = sin(ang)
		if absf(dx) > 0.5:
			b.box(dx * 2.7 - 0.07, dx * 2.7 + 0.07, 19.3, 22.3, -1.5, 1.5, Color(0.88, 0.86, 0.78))
		else:
			b.box(-1.5, 1.5, 19.3, 22.3, dz * 2.7 - 0.07, dz * 2.7 + 0.07, Color(0.88, 0.86, 0.78))
	for k in 8:
		var ka: float = PI / 8.0 + float(k) * TAU / 8.0
		b.prism(cos(ka) * 2.0, sin(ka) * 2.0, 23.7, 27.4, 0.28, 0.28, 0.28, 0.28, 6, dress, false)
	b.prism(0.0, 0.0, 23.7, 27.4, 1.35, 1.35, 1.35, 1.35, 8, Color(0.20, 0.19, 0.18), false, PI / 8.0)
	b.prism(0.0, 0.0, 27.4, 27.9, 2.5, 2.5, 2.5, 2.5, 8, dress, true, PI / 8.0)
	b.prism(0.0, 0.0, 27.9, 29.5, 2.3, 2.3, 1.75, 1.75, 8, copper, false, PI / 8.0)
	b.prism(0.0, 0.0, 29.5, 30.8, 1.75, 1.75, 0.85, 0.85, 8, copper * 1.05, false, PI / 8.0)
	b.prism(0.0, 0.0, 30.8, 31.6, 0.85, 0.85, 0.0, 0.0, 8, copper * 1.08, false, PI / 8.0)
	b.prism(0.0, 0.0, 31.4, 34.6, 0.10, 0.10, 0.03, 0.03, 4, Color(0.62, 0.52, 0.22), false)
	var m: ArrayMesh = b.commit(paint_material())
	_cache[key] = m
	return m


## Market square: cobbled paving with a kerb, a stepped market cross, and two rows of covered stalls on posts
## with striped awnings (46 x 38 m).
static func market_square() -> ArrayMesh:
	if _cache.has("market"):
		return _cache["market"]
	var b := MB.new()
	var stone := Color(0.62, 0.58, 0.50)
	b.box(-23.0, 23.0, 0.0, 0.35, -19.0, 19.0, Color(0.50, 0.48, 0.44), true, Color(0.46, 0.44, 0.40))
	b.box(-23.3, 23.3, 0.0, 0.5, -19.3, -19.0, stone)
	b.box(-23.3, 23.3, 0.0, 0.5, 19.0, 19.3, stone)
	b.box(-23.3, -23.0, 0.0, 0.5, -19.0, 19.0, stone)
	b.box(23.0, 23.3, 0.0, 0.5, -19.0, 19.0, stone)
	# market cross: three steps, a shaft and a cross-head under a little pyramid
	for s in 3:
		var h: float = 2.4 - float(s) * 0.7
		b.box(-h, h, 0.35 + float(s) * 0.4, 0.75 + float(s) * 0.4, -h, h, stone * (0.95 + 0.03 * s))
	b.prism(0.0, 0.0, 1.55, 6.8, 0.55, 0.55, 0.38, 0.38, 6, stone * 1.04, true)
	b.box(-0.9, 0.9, 6.8, 7.5, -0.35, 0.35, stone * 1.04)
	b.prism(0.0, 0.0, 7.5, 8.6, 0.55, 0.55, 0.0, 0.0, 4, stone * 0.92, false, PI * 0.25)
	# covered stalls: posts, a striped sloping awning, a counter
	var awn: Array = [Color(0.56, 0.27, 0.22), Color(0.66, 0.62, 0.54), Color(0.27, 0.36, 0.45), Color(0.62, 0.50, 0.28)]
	for row in 2:
		var zz: float = -12.0 if row == 0 else 12.0
		for i in 5:
			var xx: float = -16.0 + float(i) * 8.0
			var ac: Color = awn[(i + row * 2) % 4]
			for px in [-2.6, 2.6]:
				b.box(xx + px - 0.12, xx + px + 0.12, 0.35, 2.9, zz - 1.7, zz - 1.46, Color(0.30, 0.24, 0.18), false)
				b.box(xx + px - 0.12, xx + px + 0.12, 0.35, 2.4, zz + 1.46, zz + 1.7, Color(0.30, 0.24, 0.18), false)
			b.face([Vector3(xx - 3.0, 2.9, zz - 1.9), Vector3(xx + 3.0, 2.9, zz - 1.9), Vector3(xx + 3.0, 2.4, zz + 1.9), Vector3(xx - 3.0, 2.4, zz + 1.9)], ac, Vector3.UP)
			b.box(xx - 2.5, xx + 2.5, 0.35, 1.1, zz - 0.7, zz + 0.7, Color(0.42, 0.33, 0.24), true, Color(0.55, 0.46, 0.34))
	var m: ArrayMesh = b.commit(paint_material())
	_cache["market"] = m
	return m


# ------------------------------------------------------------------ airfield hangars

## Steel-framed aircraft hangar (the RAF T1 / T2 type): corrugated walls with a concrete plinth and pilasters, a
## low-pitch roof with eaves, ridge ventilator and rib lines, two big sliding door leaves with their rail and
## overhead track on the +Z end, a lean-to workshop annex along one side and a service door in the blank -Z end.
## Footprint matches the old box hangars (w x l metres, wall height h) so placement and wreck swaps stay the same.
static func hangar(w: float, l: float, h: float, rise: float, skin: Color) -> ArrayMesh:
	var key: String = "hangar_%d_%d_%s" % [int(w), int(l), skin.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var hw: float = w * 0.5
	var hl: float = l * 0.5
	var rib: Color = skin.darkened(0.2)
	var plinth := Color(0.46, 0.45, 0.42)
	var roof: Color = Color(0.27, 0.29, 0.27)
	var dark := Color(0.07, 0.07, 0.07)
	var door: Color = skin.darkened(0.18)
	# walls, concrete plinth, pilasters at the bays
	b.box(-hw, hw, 0.0, h, -hl, hl, skin, false)
	b.box(-hw - 0.12, hw + 0.12, 0.0, 1.1, -hl - 0.12, hl + 0.12, plinth)
	var bays: int = int(round(l / 8.5))
	for i in bays + 1:
		var z: float = -hl + float(i) * l / float(bays)
		b.box(-hw - 0.25, -hw, 0.0, h + 0.15, z - 0.28, z + 0.28, rib)
		b.box(hw, hw + 0.25, 0.0, h + 0.15, z - 0.28, z + 0.28, rib)
	# eaves band and the roof: gable with overhang, rib lines and a raised ridge ventilator with glazed sides
	b.box(-hw - 0.2, hw + 0.2, h, h + 0.4, -hl - 0.2, hl + 0.2, rib, false)
	b.gable_z(-hw - 0.2, hw + 0.2, -hl - 0.35, hl + 0.35, h + 0.3, rise, 0.5, roof, skin.darkened(0.05), 0.0)
	for i in bays + 1:
		var z2: float = -hl + float(i) * l / float(bays)
		b.gable_z(-hw - 0.2, hw + 0.2, z2 - 0.14, z2 + 0.14, h + 0.36, rise + 0.02, 0.5, roof.darkened(0.2), roof.darkened(0.2), 0.0)
	var vw: float = w * 0.12
	var vy: float = h + 0.3 + rise - 0.2
	b.box(-vw, vw, vy, vy + 0.8, -hl * 0.86, hl * 0.86, skin.darkened(0.08), false)
	b.box(-vw - 0.04, vw + 0.04, vy + 0.25, vy + 0.62, -hl * 0.84, hl * 0.84, Color(0.12, 0.17, 0.19), false)
	b.gable_z(-vw - 0.25, vw + 0.25, -hl * 0.86 - 0.15, hl * 0.86 + 0.15, vy + 0.8, 0.5, 0.0, roof.lightened(0.04), skin, 0.0)
	# the door end (+Z): rail, two door leaves with panel ribs, an overhead track and a dark gap showing the interior
	var zd: float = hl
	b.box(-hw * 0.99, hw * 0.99, 0.0, h * 0.93, zd - 0.05, zd + 0.15, dark, false)
	b.box(-hw - 1.0, hw + 1.0, 0.0, 0.1, zd + 0.1, zd + 0.6, plinth, true)
	for sx in [-1.0, 1.0]:
		var x0: float = minf(sx * hw * 0.05, sx * hw * 0.97)
		var x1: float = maxf(sx * hw * 0.05, sx * hw * 0.97)
		var slide: float = 0.0 if sx < 0.0 else hw * 0.30          # one leaf pulled partly open
		b.box(x0 + (0.0 if sx < 0.0 else slide), x1 + (0.0 if sx < 0.0 else slide) * 0.0, 0.15, h * 0.92, zd + 0.15, zd + 0.5, door, true, door.lightened(0.08))
		var panels: int = 7
		for p in panels:
			var px: float = lerpf(x0, x1, (float(p) + 0.5) / float(panels))
			b.box(px - 0.08, px + 0.08, 0.15, h * 0.92, zd + 0.5, zd + 0.62, rib, false)
		b.box(x0, x1, h * 0.46, h * 0.46 + 0.18, zd + 0.5, zd + 0.64, rib, false)
	b.box(-hw - 0.2, hw + 0.2, h * 0.93, h * 0.93 + 0.5, zd + 0.15, zd + 0.8, rib)
	b.box(-hw * 0.99, hw * 0.99, 0.0, 0.18, zd + 0.1, zd + 0.7, Color(0.20, 0.20, 0.20), false)
	# blank rear end: a service door under a small canopy and a louvre
	b.box(-1.0, 1.0, 0.0, 2.5, -hl - 0.12, -hl - 0.02, dark, false)
	b.box(-1.5, 1.5, 2.5, 2.7, -hl - 0.12, -hl - 0.9, rib)
	b.box(-hw * 0.4, -hw * 0.4 + 2.6, h * 0.62, h * 0.62 + 1.0, -hl - 0.12, -hl - 0.02, Color(0.18, 0.18, 0.17), false)
	# lean-to workshop annex along the east side with a row of small windows and its own mono roof
	var ax0: float = hw
	var ax1: float = hw + 5.0
	var az0: float = -hl * 0.55
	var az1: float = hl * 0.35
	b.box(ax0, ax1, 0.0, 3.4, az0, az1, skin.lightened(0.05), false)
	b.mono(ax0, ax1, az0, az1, 3.4, 4.4, "x0", roof.lightened(0.03), skin.lightened(0.05), 0.25)
	var nwin: int = 6
	for i in nwin:
		var wz: float = lerpf(az0 + 2.0, az1 - 2.0, float(i) / float(nwin - 1))
		b.box(ax1, ax1 + 0.06, 1.5, 2.5, wz - 0.7, wz + 0.7, Color(0.13, 0.17, 0.19), false)
	b.box(ax1, ax1 + 0.08, 0.0, 2.3, az1 - 3.0, az1 - 1.8, dark, false)
	b.prism(ax1 - 1.2, az0 + 2.0, 4.0, 6.2, 0.22, 0.22, 0.20, 0.20, 6, Color(0.20, 0.20, 0.20), true)
	var m: ArrayMesh = b.commit(paint_material())
	_cache[key] = m
	return m


# ------------------------------------------------------------------ strike-mission bridge

## 150 m through-arch road bridge on five elliptical masonry piers with cutwaters: a road deck with kerbs and
## parapets, a steel arch rib each side with vertical hangers, diagonal bracing and top lateral struts, and portal
## braces at the springings. The deck runs along X at y = 14 (same layout as the old box bridge).
static func strike_bridge() -> ArrayMesh:
	if _cache.has("strike_bridge"):
		return _cache["strike_bridge"]
	var b := MB.new()
	var L: float = 150.0
	var steel := Color(0.36, 0.38, 0.42)
	var pier := Color(0.46, 0.44, 0.40)
	var road := Color(0.20, 0.20, 0.21)
	var deck: float = 14.0
	for i in 5:
		var x: float = (float(i) - 2.0) * (L / 4.0 - 4.0)
		b.prism(x, 0.0, -3.0, deck - 1.2, 2.8, 5.6, 2.3, 5.2, 14, pier, true)
		b.box(x - 3.2, x + 3.2, deck - 1.4, deck - 1.1, -6.2, 6.2, pier.lightened(0.1))
		b.prism(x, 0.0, 0.0, 1.2, 3.2, 6.2, 3.2, 6.2, 14, pier.darkened(0.15), false)
	# deck: road surface, girder fascias and kerbs
	b.box(-L * 0.5, L * 0.5, deck - 1.2, deck + 0.4, -6.5, 6.5, steel.darkened(0.12), true, road)
	for sz in [-1.0, 1.0]:
		var z0: float = minf(sz * 6.5, sz * 6.1)
		var z1: float = maxf(sz * 6.5, sz * 6.1)
		b.box(-L * 0.5, L * 0.5, deck - 1.4, deck + 1.2, z0 - 0.1, z1 + 0.1, steel, true, steel.lightened(0.06))
		b.box(-L * 0.5, L * 0.5, deck + 0.4, deck + 0.55, minf(sz * 5.6, sz * 5.0), maxf(sz * 5.6, sz * 5.0), pier.lightened(0.15))
	b.box(-0.3, 0.3, deck + 0.4, deck + 0.44, -5.0, 5.0, Color(0.55, 0.52, 0.40))
	# the arch ribs and what hangs from them
	var n: int = 12
	var pts: Array = []
	for i in n + 1:
		var t: float = float(i) / float(n)
		pts.append(Vector3(lerpf(-L * 0.42, L * 0.42, t), deck + 0.6 + 22.0 * (1.0 - pow(2.0 * t - 1.0, 2.0)), 0.0))
	for sz2 in [-6.0, 6.0]:
		for i in n:
			var p0: Vector3 = pts[i]
			var p1: Vector3 = pts[i + 1]
			b.beam(Vector3(p0.x, p0.y, sz2), Vector3(p1.x, p1.y, sz2), 0.55, 0.5, steel)
		for i in range(1, n):
			var p: Vector3 = pts[i]
			b.beam(Vector3(p.x, deck + 1.0, sz2), Vector3(p.x, p.y, sz2), 0.14, 0.14, steel.darkened(0.12))
			if i < n - 1 and i > 1:
				var q: Vector3 = pts[i + 1]
				var from_y: float = deck + 1.0 if i % 2 == 0 else q.y
				var to_y: float = q.y if i % 2 == 0 else deck + 1.0
				b.beam(Vector3(p.x, from_y if i % 2 == 0 else p.y, sz2), Vector3(q.x, to_y, sz2), 0.12, 0.12, steel.darkened(0.2))
	for i in range(2, n - 1):
		var p2: Vector3 = pts[i]
		b.box(p2.x - 0.25, p2.x + 0.25, p2.y - 0.3, p2.y + 0.3, -5.8, 5.8, steel.darkened(0.1))
	# portal bracing at each springing, and the abutment wing walls
	for sx in [-1.0, 1.0]:
		var xe: float = sx * L * 0.42
		b.box(minf(xe - 0.5, xe + 0.5), maxf(xe - 0.5, xe + 0.5), deck + 1.0, deck + 4.0, -6.5, 6.5, steel.darkened(0.05))
		b.box(minf(sx * L * 0.5, sx * (L * 0.5 + 6.0)), maxf(sx * L * 0.5, sx * (L * 0.5 + 6.0)), 0.0, deck + 0.4, -7.0, 7.0, pier)
		b.box(minf(sx * L * 0.5, sx * (L * 0.5 + 6.0)), maxf(sx * L * 0.5, sx * (L * 0.5 + 6.0)), deck + 0.4, deck + 0.55, -6.5, 6.5, road)
	var m: ArrayMesh = b.commit(paint_material())
	_cache["strike_bridge"] = m
	return m


# ------------------------------------------------------------------ anti-aircraft guns (AAGun parts)

## Sandbag emplacement: two courses of staggered bags in a ring with an entrance gap, ammunition niches, a trodden
## earth floor with a concrete gun pad, and a few ammunition boxes.
static func aa_static(big: bool) -> ArrayMesh:
	var key: String = "aa_static_%s" % str(big)
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var r: float = 6.5 if big else 5.0
	var sand := Color(0.55, 0.49, 0.36)
	var n: int = 22
	b.prism(0.0, 0.0, 0.0, 0.12, r + 0.3, r + 0.3, r + 0.3, r + 0.3, 20, Color(0.30, 0.25, 0.17), true)
	b.prism(0.0, 0.0, 0.12, 0.3, r * 0.42, r * 0.42, r * 0.40, r * 0.40, 16, Color(0.40, 0.40, 0.38), true)
	for course in 2:
		for i in n:
			var a0: float = TAU * (float(i) + 0.5 * float(course)) / float(n)
			# a gap in the ring on the +Z side where the crew comes in
			if cos(a0 - PI * 0.5) > 0.93 and course == 0:
				continue
			if cos(a0 - PI * 0.5) > 0.93 and course == 1:
				continue
			var cx: float = cos(a0) * r
			var cz: float = sin(a0) * r
			var tan := Vector2(-sin(a0), cos(a0))
			var hl: float = TAU * r / float(n) * 0.56
			var y0: float = float(course) * 0.62
			var tone: float = 0.92 + 0.12 * fmod(float(i * 7 + course * 3), 5.0) / 5.0
			var corners: Array = []
			for sa in [-1.0, 1.0]:
				for sr in [-1.0, 1.0]:
					var rr: float = r + sr * 0.55
					var ang: float = a0 + sa * hl / r
					corners.append(Vector2(cos(ang) * rr, sin(ang) * rr))
			var c0: Vector2 = corners[0]
			var c1: Vector2 = corners[1]
			var c2: Vector2 = corners[2]
			var c3: Vector2 = corners[3]
			var h: float = 0.62
			var col: Color = sand * tone
			b.face([Vector3(c0.x, y0, c0.y), Vector3(c2.x, y0, c2.y), Vector3(c2.x, y0 + h, c2.y), Vector3(c0.x, y0 + h, c0.y)], col, Vector3(cx, 0, cz).rotated(Vector3.UP, 0.0) * -1.0 * -1.0 + Vector3(-tan.x, 0, -tan.y) * 0.0 - Vector3(0, 0, 0) - Vector3(cx, 0, cz) * 2.0 + Vector3(cx, 0, cz) * 2.0)
			b.face([Vector3(c1.x, y0, c1.y), Vector3(c3.x, y0, c3.y), Vector3(c3.x, y0 + h, c3.y), Vector3(c1.x, y0 + h, c1.y)], col, Vector3(cx, 0, cz))
			b.face([Vector3(c0.x, y0 + h, c0.y), Vector3(c1.x, y0 + h, c1.y), Vector3(c3.x, y0 + h, c3.y), Vector3(c2.x, y0 + h, c2.y)], col * 1.08, Vector3.UP)
			b.face([Vector3(c0.x, y0, c0.y), Vector3(c1.x, y0, c1.y), Vector3(c1.x, y0 + h, c1.y), Vector3(c0.x, y0 + h, c0.y)], col * 0.95, Vector3(-tan.x, 0, -tan.y))
			b.face([Vector3(c2.x, y0, c2.y), Vector3(c3.x, y0, c3.y), Vector3(c3.x, y0 + h, c3.y), Vector3(c2.x, y0 + h, c2.y)], col * 0.95, Vector3(tan.x, 0, tan.y))
	# ammunition boxes and a ready-use rack inside the wall
	for k in 3:
		var ka: float = PI * 1.15 + float(k) * 0.34
		var kx: float = cos(ka) * (r - 1.6)
		var kz: float = sin(ka) * (r - 1.6)
		b.box(kx - 0.5, kx + 0.5, 0.3, 0.75, kz - 0.35, kz + 0.35, Color(0.24, 0.26, 0.18), true, Color(0.30, 0.32, 0.22))
	var m: ArrayMesh = b.commit(paint_material())
	_cache[key] = m
	return m


## Rotating mount: a round turntable on a cruciform base with outrigger legs, traverse gear housing and the
## gunner's seat and platform.
static func aa_yaw(big: bool, c: Color) -> ArrayMesh:
	var key: String = "aa_yaw_%s_%s" % [str(big), c.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var dk: Color = c.darkened(0.2)
	b.prism(0.0, 0.0, 0.0, 0.5, 1.7, 1.7, 1.6, 1.6, 10, dk.darkened(0.1), true)
	b.prism(0.0, 0.0, 0.5, 1.2, 1.5, 1.5, 1.2, 1.2, 10, dk, true)
	if big:
		# cruciform carriage: four outrigger legs with levelling feet
		for lg in 4:
			var ang: float = float(lg) * PI * 0.5
			var ex: float = cos(ang) * 3.4
			var ez: float = sin(ang) * 3.4
			var ax: float = absf(cos(ang))
			b.box(minf(0.0, ex) - 0.3, maxf(0.0, ex) + 0.3, 0.2, 0.6, minf(0.0, ez) - 0.3, maxf(0.0, ez) + 0.3, dk.darkened(0.05), true)
			b.box(ex - 0.45, ex + 0.45, 0.0, 0.3, ez - 0.45, ez + 0.45, Color(0.15, 0.15, 0.15), true)
	else:
		for lg in 4:
			var ang2: float = float(lg) * PI * 0.5
			var ex2: float = cos(ang2) * 2.6
			var ez2: float = sin(ang2) * 2.6
			b.box(minf(0.0, ex2) - 0.22, maxf(0.0, ex2) + 0.22, 0.2, 0.5, minf(0.0, ez2) - 0.22, maxf(0.0, ez2) + 0.22, dk.darkened(0.05), true)
			b.box(ex2 - 0.35, ex2 + 0.35, 0.0, 0.25, ez2 - 0.35, ez2 + 0.35, Color(0.15, 0.15, 0.15), true)
		# gunner's seat on a bracket, and a foot plate
		b.box(1.2, 2.0, 1.1, 1.3, 0.8, 1.6, dk.darkened(0.1), true)
		b.box(1.5, 1.7, 0.5, 1.1, 1.1, 1.3, Color(0.15, 0.15, 0.15), false)
	b.box(-0.9, 0.9, 1.2, 1.9, -0.9, 0.9, dk.lightened(0.04), true)
	var m: ArrayMesh = b.commit(paint_material())
	_cache[key] = m
	return m


## The pitching part, barrels along -Z about the trunnion at the origin: for the 88 a long barrel with a recoil
## sleeve, muzzle brake and big breech under an angled shield; for the Bofors twin barrels with flash hiders, a
## clip-fed magazine on top and a splinter shield.
static func aa_pitch(big: bool, c: Color) -> ArrayMesh:
	var key: String = "aa_pitch_%s_%s" % [str(big), c.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var dk: Color = c.darkened(0.3)
	var steel := Color(0.17, 0.17, 0.18)
	if big:
		# shield: a flat plate with side wings
		b.box(-1.5, 1.5, -0.6, 1.4, -1.15, -1.0, c, true)
		for sx in [-1.0, 1.0]:
			b.box(minf(sx * 1.5, sx * 1.62), maxf(sx * 1.5, sx * 1.62), -0.6, 1.4, -1.1, 0.3, c.darkened(0.06), true)
		# cradle, recoil sleeve, barrel with a step and muzzle brake
		b.box(-0.55, 0.55, -0.45, 0.45, -1.0, 1.8, c.darkened(0.15), true)
		b.prism(0.0, -3.4, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3, steel, false)
		b.box(-0.30, 0.30, -0.30, 0.30, -4.2, -1.0, steel.lightened(0.03), true)
		b.box(-0.23, 0.23, -0.23, 0.23, -9.6, -4.2, steel, true)
		b.box(-0.36, 0.36, -0.36, 0.36, -10.4, -9.6, steel.lightened(0.05), true)
		# breech block, elevating arc and a sight
		b.box(-0.7, 0.7, -0.6, 0.6, 1.8, 2.8, c.darkened(0.25), true)
		b.box(-0.2, 0.2, 0.45, 0.9, -0.3, 0.2, Color(0.12, 0.12, 0.12), true)
		b.box(-1.4, -1.1, 0.0, 0.5, -0.4, 0.4, dk, true)
	else:
		# splinter shield and cradle
		b.box(-1.35, 1.35, -0.55, 0.9, -0.95, -0.82, c, true)
		b.box(-1.1, 1.1, -0.45, 0.45, -0.8, 1.5, c.darkened(0.12), true)
		for sx2 in [-0.62, 0.62]:
			b.box(sx2 - 0.16, sx2 + 0.16, -0.12, 0.2, -4.0, -0.8, steel, true)
			b.box(sx2 - 0.19, sx2 + 0.19, -0.15, 0.23, -5.6, -4.0, steel.lightened(0.03), true)
			b.box(sx2 - 0.3, sx2 + 0.3, -0.26, 0.34, -5.9, -5.6, steel.lightened(0.06), true)
			# clip-fed magazine above the breech
			b.box(sx2 - 0.22, sx2 + 0.22, 0.45, 1.05, -0.2, 0.5, Color(0.26, 0.28, 0.2), true)
			b.box(sx2 - 0.15, sx2 + 0.15, 1.05, 1.3, -0.1, 0.4, steel, true)
		b.box(-0.2, 0.2, 0.45, 0.8, 0.5, 1.2, Color(0.12, 0.12, 0.12), true)
		b.box(-1.0, 1.0, -0.4, 0.4, 1.5, 1.9, c.darkened(0.25), true)
	var m: ArrayMesh = b.commit(paint_material())
	_cache[key] = m
	return m
