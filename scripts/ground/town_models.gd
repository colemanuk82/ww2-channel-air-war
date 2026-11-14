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

	## A cylinder lying along X (a wheel or roller): centre, radius, width, segments.
	func wheel(cx: float, cy: float, cz: float, r: float, w: float, segs: int, col: Color) -> void:
		var x0: float = cx - w * 0.5
		var x1: float = cx + w * 0.5
		var left: Array = []
		var right: Array = []
		for i in segs:
			var a0: float = TAU * float(i) / float(segs)
			var a1: float = TAU * float(i + 1) / float(segs)
			var p0 := Vector3(0.0, cy + sin(a0) * r, cz + cos(a0) * r)
			var p1 := Vector3(0.0, cy + sin(a1) * r, cz + cos(a1) * r)
			var am: float = (a0 + a1) * 0.5
			face([Vector3(x0, p0.y, p0.z), Vector3(x1, p0.y, p0.z), Vector3(x1, p1.y, p1.z), Vector3(x0, p1.y, p1.z)], col, Vector3(0.0, sin(am), cos(am)))
			left.append(Vector3(x0, p0.y, p0.z))
			right.append(Vector3(x1, p0.y, p0.z))
		face(left, col, Vector3.LEFT)
		face(right, col.lightened(0.05), Vector3.RIGHT)

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
		return LodCull.with_lods(m)


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


# ------------------------------------------------------------------ joined terrace rows (named towns, P4)

## True when the row's wall scheme is the warm limestone / sandstone one. terrace_row() uses the same
## rule, so the far LOD (Scatter._add_rows) always picks the matching simple unit.
static func terrace_row_warm(rng_or_hash: int) -> bool:
	return absi(rng_or_hash) % 48 % 5 != 4


## One joined party-wall terrace row of `units` (3-6) houses as a single ArrayMesh (P4.4). The whole run
## fills the placement unit box (local X -0.5..0.5 = the row's frontage, street front at -Z, ridge along X),
## so a street of N-unit rows costs one instance and one draw instead of one per house. Party walls are
## shared - the gable triangles only stand at the two ends - and the door / bay / roof rhythm and the wall
## tones vary per unit through the vertex colours (house_material is world_pbr + use_vcol), with raised
## party-wall firebreaks stepping the roof line. `rng_or_hash` seeds the scheme deterministically; the
## caller hashes town + street + slot, so rebuilds agree and the cache stays bounded (48 schemes per size).
static func terrace_row(units: int, rng_or_hash: int) -> ArrayMesh:
	var n: int = clampi(units, 3, 6)
	var hv: int = absi(rng_or_hash) % 48
	var key: String = "trow_%d_%d" % [n, hv]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hv * 7919 + n
	var b := MB.new()
	var warm: bool = terrace_row_warm(rng_or_hash)
	var wu: float = 1.0 / float(n)
	# wall tones: warm limestone / sandstone rows (with the odd sooty brick unit kept - 1940s streets were
	# dirty, just not uniformly black), or the fully sooty row for the minority of rows
	var stone_walls: Array = [Color(0.62, 0.57, 0.47), Color(0.57, 0.52, 0.43), Color(0.65, 0.60, 0.50), Color(0.53, 0.48, 0.40)]
	var door_cols: Array = [Color(0.16, 0.13, 0.11), Color(0.19, 0.25, 0.17), Color(0.24, 0.19, 0.14)]
	var step_i: int = rng.randi_range(1, n - 2)          # the one unit whose roof steps up
	var walls: Array = []                                # per-unit wall tones (the firebreaks reuse them)
	for i in n:
		var x0: float = -0.5 + float(i) * wu
		var x1: float = x0 + wu
		var uh: int = rng.randi()
		var wall: Color
		if warm:
			wall = stone_walls[uh % stone_walls.size()]
			if uh % 6 == 5:
				wall = BRICK_DK                       # the odd sooty unit even in a kept row
		else:
			wall = BRICK_DK * (0.92 + 0.16 * float(uh % 4) / 3.0)
		walls.append(wall)
		var rr: float = float(uh % 10) / 10.0
		var roof: Color
		if warm:
			roof = SLATE if rr < 0.45 else (TILE * 1.05 if rr < 0.80 else Color(0.42, 0.33, 0.26))
		else:
			roof = SLATE * 0.9
		# the unit's party-walled block (no top: the gable roof closes it), its continuous roof slice,
		# front door with doorstep and hood-side step, alternating left / right through the row
		b.box(x0, x1, -0.5, 0.5, -0.5, 0.5, wall, false)
		b.gable_x(x0, x1, -0.5, 0.5, 0.5, 0.54 if i == step_i else 0.46, 0.06, roof, wall, 0.02 if i == 0 or i == n - 1 else 0.0)
		var left: bool = uh % 2 == 0
		var dx0: float = x0 + wu * (0.12 if left else 0.58)
		var dx1: float = dx0 + wu * 0.28
		b.box(dx0, dx1, -0.5, -0.455, -0.555, -0.5, STONE * 0.9)
		b.box(dx0 + 0.008, dx1 - 0.008, -0.10, -0.075, -0.562, -0.5, door_cols[uh % door_cols.size()])
		# ground-floor bay on about one unit in three, with its own little roof
		if uh % 3 == 0:
			var bx0: float = x0 + wu * 0.30
			var bx1: float = bx0 + wu * 0.40
			b.box(bx0, bx1, -0.5, 0.0, -0.585, -0.5, wall * 0.95, false)
			b.mono(bx0, bx1, -0.585, -0.5, 0.0, 0.10, "z1", roof, wall * 0.95, 0.012)
	# raised party-wall firebreaks: always either side of the stepped unit (they close its roof step),
	# otherwise on about half the party walls - the classic broken terrace silhouette from the air
	for i2 in range(1, n):
		var xp: float = -0.5 + float(i2) * wu
		var next_to_step: bool = i2 == step_i or i2 == step_i + 1
		if next_to_step or rng.randf() < 0.45:
			var fh: float = 0.57 if next_to_step else 0.52
			var fb: Color = (walls[i2 - 1] as Color) * 0.92
			b.gable_x(xp - 0.014, xp + 0.014, -0.545, 0.545, 0.5, fh, 0.0, fb, fb)
	# shared ridge stacks on about half the party walls
	for i3 in range(1, n):
		if rng.randf() < 0.5:
			b.chimney(-0.5 + float(i3) * wu, 0.02, 0.72, 1.08, 0.10, 0.15, STACK, 2)
	var m: ArrayMesh = b.commit(house_material())
	_cache[key] = m
	return m


## Kerb + pavement strip laid in front of a named-town terrace row (P4.6): one low slab the length of the
## run (the instance scales local X), 3.6 m wide (local Z -1.8..1.8), 0.14 m proud of the ground with the
## kerb line on the street side (-Z). Built on the painted-prop material like the market square's cobbles;
## the near-house draw range and no cast shadows are set by the caller.
static func kerb_strip() -> ArrayMesh:
	if _cache.has("kerb_strip"):
		return _cache["kerb_strip"]
	var b := MB.new()
	var pave := Color(0.52, 0.51, 0.48)
	var kerb := Color(0.60, 0.58, 0.54)
	# pavement slab: 0.24 thick so it sinks 0.10 m into sloping ground, 0.14 m proud, lighter worn top
	b.box(-0.5, 0.5, -0.10, 0.14, -1.8, 1.8, pave, true, pave * 1.06)
	# kerb stones along the carriageway edge: a narrower coping standing a shade taller
	b.box(-0.5, 0.5, -0.10, 0.17, -1.8, -1.55, kerb, true, kerb * 1.04)
	var m: ArrayMesh = b.commit(paint_material())
	_cache["kerb_strip"] = m
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


# ------------------------------------------------------------------ tanks (GroundVehicle)

## Tank hull and running gear in GroundVehicle's layout: the hull deck at y = 0.75 + hull_h, nose toward -Z, the
## tracks 0.2 x width wide either side. Upper hull has a sloped glacis, fenders, engine louvres, hatches, lights and
## stowage; the road wheels show under the optional side skirts.
static func tank_hull(c: Color, length: float, width: float, hull_h: float, skirts: bool) -> ArrayMesh:
	var key: String = "tank_hull_%s_%d_%d_%s" % [c.to_html(false), int(length * 10.0), int(width * 10.0), str(skirts)]
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var dark: Color = c.darkened(0.45)
	var iron := Color(0.12, 0.12, 0.12)
	var y0: float = 0.75
	var top: float = y0 + hull_h
	var wh: float = width * 0.39
	var zf: float = -length * 0.47
	var zr: float = length * 0.46
	var zg: float = -length * 0.30
	# running gear: track runs with road wheels, sprocket, idler and return rollers
	for sx in [-1.0, 1.0]:
		var xc: float = sx * width * 0.42
		var tw: float = width * 0.2
		b.box(xc - tw * 0.5, xc + tw * 0.5, 0.12, 0.98, -length * 0.5, length * 0.5, dark, true, dark.lightened(0.05))
		var nr: int = 7
		for i in nr:
			var wz: float = lerpf(-length * 0.40, length * 0.40, float(i) / float(nr - 1))
			b.wheel(xc + sx * tw * 0.5, 0.52, wz, 0.40, 0.10, 8, dark.darkened(0.3) if i % 2 == 0 else dark.lightened(0.04))
		b.wheel(xc + sx * tw * 0.5, 0.62, zr, 0.50, 0.12, 10, dark.lightened(0.08))
		b.wheel(xc + sx * tw * 0.5, 0.62, -length * 0.5 + 0.35, 0.46, 0.12, 10, dark.lightened(0.08))
		# fender over the track
		b.box(sx * width * 0.5 - 0.05, sx * width * 0.5 + 0.05, 0.0, 0.0, 0.0, 0.0, c, false)
		b.box(minf(sx * width * 0.32, sx * width * 0.52), maxf(sx * width * 0.32, sx * width * 0.52), 0.99, 1.06, -length * 0.5, length * 0.5, c.darkened(0.08), true, c.darkened(0.04))
		if skirts:
			var segs: int = 5
			for i in segs:
				var z0: float = lerpf(-length * 0.44, length * 0.34, float(i) / float(segs)) + 0.06
				var z1: float = lerpf(-length * 0.44, length * 0.34, float(i + 1) / float(segs)) - 0.06
				var xs: float = sx * (width * 0.53)
				b.box(minf(xs, xs + sx * 0.06), maxf(xs, xs + sx * 0.06), 0.45, 1.06, z0, z1, c.darkened(0.12), true, c.darkened(0.06))
		# tow cable and a spare track link block on the hull side
		b.box(minf(sx * wh, sx * (wh + 0.05)), maxf(sx * wh, sx * (wh + 0.05)), y0 + hull_h * 0.3, y0 + hull_h * 0.42, -length * 0.25, length * 0.30, iron, false)
	# upper hull: side profile extruded across the width (deck, sloped glacis, nose, rear plate)
	var pr: Array = [Vector2(zr, y0), Vector2(zr, top), Vector2(zg, top), Vector2(zf, y0 + hull_h * 0.30), Vector2(zf, y0)]
	var np: int = pr.size()
	var rt: Array = []
	var lf: Array = []
	for p in pr:
		var pv: Vector2 = p
		rt.append(Vector3(wh, pv.y, pv.x))
		lf.append(Vector3(-wh, pv.y, pv.x))
	var rtr: Array = rt.duplicate()
	rtr.reverse()
	b.face(rt, c, Vector3.RIGHT)
	b.face(lf, c, Vector3.LEFT)
	b.face([lf[1], rt[1], rt[2], lf[2]], c.lightened(0.03), Vector3.UP)           # engine / fighting deck
	b.face([lf[2], rt[2], rt[3], lf[3]], c.lightened(0.06), Vector3(0.0, 0.6, -1.0))   # sloped glacis
	b.face([lf[3], rt[3], rt[4], lf[4]], c, Vector3.FORWARD)
	b.face([lf[0], rt[0], rt[1], lf[1]], c.darkened(0.08), Vector3.BACK)
	# engine louvres and exhaust, driver and radio-operator hatches, headlights, hull MG
	for i in 4:
		var lz: float = zr - 0.4 - float(i) * 0.38
		b.box(-wh * 0.62, wh * 0.62, top, top + 0.05, lz - 0.1, lz + 0.1, iron, false)
	for sx2 in [-1.0, 1.0]:
		b.box(minf(sx2 * wh * 0.78, sx2 * wh * 0.95), maxf(sx2 * wh * 0.78, sx2 * wh * 0.95), y0 + 0.1, y0 + hull_h * 0.55, zr, zr + 0.25, iron, false)
		b.box(sx2 * wh * 0.72 - 0.19, sx2 * wh * 0.72 + 0.19, top, top + 0.16, zg - 0.55, zg - 0.05, c.darkened(0.2), true, iron)
		b.box(sx2 * wh * 0.5 - 0.07, sx2 * wh * 0.5 + 0.07, y0 + hull_h * 0.7, y0 + hull_h * 0.7 + 0.14, zg - 0.58, zg - 0.45, Color(0.7, 0.68, 0.55), false)
	b.box(-0.05, 0.05, y0 + hull_h * 0.45, y0 + hull_h * 0.5, zf - 0.28, zf, iron, false)
	var m: ArrayMesh = b.commit(paint_material())
	_cache[key] = m
	return m


## Turret and gun, origin on the turret ring, barrel along -Z. `ts` is the turret scale of the vehicle type.
static func tank_turret(c: Color, length: float, width: float, ts: float, blen: float, brake: bool) -> ArrayMesh:
	var key: String = "tank_turret_%s_%d_%d_%d_%s" % [c.to_html(false), int(length * 10.0), int(ts * 10.0), int(blen * 10.0), str(brake)]
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var iron := Color(0.12, 0.12, 0.12)
	var rx: float = width * 0.34 * ts
	var rz: float = length * 0.23 * ts
	var h: float = 0.82 * ts
	b.prism(0.0, 0.0, 0.0, h * 0.62, rx, rz, rx * 0.97, rz * 0.97, 10, c, false)
	b.prism(0.0, 0.0, h * 0.62, h, rx * 0.97, rz * 0.97, rx * 0.72, rz * 0.7, 10, c.lightened(0.04), true)
	# mantlet, rear stowage bin, cupola with hatch, loader's hatch, aerial base
	b.box(-0.55 * ts, 0.55 * ts, 0.14 * ts, 0.70 * ts, -rz - 0.24, -rz * 0.8, c.darkened(0.1), true)
	b.box(-rx * 0.8, rx * 0.8, 0.12 * ts, 0.62 * ts, rz * 0.92, rz * 0.92 + 0.38, c.darkened(0.16), true, c.darkened(0.08))
	b.prism(rx * 0.36, rz * 0.22, h * 0.92, h * 0.92 + 0.3, 0.30 * ts, 0.30 * ts, 0.27 * ts, 0.27 * ts, 8, c.darkened(0.08), true)
	b.box(rx * 0.36 - 0.16, rx * 0.36 + 0.16, h * 0.92 + 0.3, h * 0.92 + 0.38, rz * 0.22 - 0.16, rz * 0.22 + 0.16, iron, false)
	b.box(-rx * 0.5 - 0.2, -rx * 0.5 + 0.2, h * 0.88, h * 0.88 + 0.1, rz * 0.1, rz * 0.5, c.darkened(0.2), true, iron)
	# the gun, centred at 0.45 ts: barrel, thicker at the breech end, with a muzzle brake on the Panzer IV and Tiger
	var gy: float = 0.45 * ts
	var gz0: float = -length * 0.21 * ts + 0.2
	b.box(-0.07, 0.07, gy - 0.07, gy + 0.07, gz0 - blen, gz0, iron, true)
	b.box(-0.11, 0.11, gy - 0.11, gy + 0.11, gz0 - blen * 0.35, gz0, c.darkened(0.3), true)
	if brake:
		b.box(-0.17, 0.17, gy - 0.17, gy + 0.17, gz0 - blen - 0.26, gz0 - blen + 0.04, iron.lightened(0.04), true)
	var m: ArrayMesh = b.commit(paint_material())
	_cache[key] = m
	return m


# ------------------------------------------------------------------ wheeled vehicles (GroundVehicle)

static func _tyre(b: MB, x: float, z: float, r: float, w: float) -> void:
	b.wheel(x, r, z, r, w, 10, Color(0.07, 0.07, 0.07))
	b.wheel(x + signf(x) * w * 0.5, r, z, r * 0.52, 0.04, 8, Color(0.30, 0.30, 0.28))


## One mesh per wheeled vehicle type, in GroundVehicle's layout (nose -Z, ground y = 0). kind: truck, bowser,
## kubel, jeep, halftrack, car, bus, firetender. `c` is the paint colour.
static func vehicle(kind: String, c: Color) -> ArrayMesh:
	var key: String = "veh_%s_%s" % [kind, c.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var dk: Color = c.darkened(0.45)
	var glass := Color(0.18, 0.23, 0.26)
	var chrome := Color(0.72, 0.72, 0.68)
	match kind:
		"truck", "bowser", "firetender":
			# chassis rails, bonnet and cab with a windscreen, mudguards, headlamps, then the body
			b.box(-0.8, 0.8, 0.55, 0.95, -3.2, 3.2, dk, false)
			b.box(-0.95, 0.95, 0.95, 1.65, -3.35, -2.0, c, true, c.lightened(0.05))               # bonnet
			b.box(-0.55, 0.55, 1.1, 1.6, -3.4, -3.3, chrome, false)                                 # grille
			b.box(-1.0, 1.0, 0.95, 2.1, -2.0, -0.3, c.lightened(0.03), true, c.darkened(0.05))      # cab
			b.box(-0.9, 0.9, 1.55, 2.0, -2.02, -1.98, glass, false)
			b.box(-1.02, 1.02, 1.55, 1.95, -1.6, -0.6, glass, false)
			for sx in [-1.0, 1.0]:
				b.box(minf(sx * 0.85, sx * 1.2), maxf(sx * 0.85, sx * 1.2), 0.98, 1.06, -3.4, -2.0, dk, false)
				b.box(minf(sx * 0.85, sx * 1.2), maxf(sx * 0.85, sx * 1.2), 0.98, 1.06, 0.2, 2.6, dk, false)
				b.box(sx * 0.62 - 0.13, sx * 0.62 + 0.13, 1.1, 1.35, -3.43, -3.38, Color(0.9, 0.85, 0.6), false)
			if kind == "bowser":
				var tank: Color = Color(0.62, 0.64, 0.62) if c.get_luminance() > 0.25 else Color(0.4, 0.42, 0.4)
				b.prism(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3, tank, false)
				b.box(-0.95, 0.95, 1.0, 2.6, -0.1, 4.1, tank, true, tank.lightened(0.06))
				b.box(-0.97, 0.97, 1.8, 2.05, -0.1, 4.1, Color(0.75, 0.15, 0.1), false)
				b.box(-0.28, 0.28, 2.6, 2.85, 1.5, 2.3, tank.darkened(0.2), true)
			elif kind == "firetender":
				b.box(-1.1, 1.1, 0.95, 2.0, -0.1, 3.8, c.darkened(0.1), true, c.darkened(0.04))
				b.box(-0.2, 0.2, 2.0, 2.2, -0.2, 3.8, Color(0.75, 0.7, 0.6), false)
				b.box(-0.55, 0.55, 2.0, 2.5, 3.2, 3.8, Color(0.75, 0.7, 0.2), false)
			else:
				var canvas: Color = c.lerp(Color(0.45, 0.4, 0.28), 0.5)
				b.box(-1.15, 1.15, 0.95, 1.4, 0.1, 4.2, c.darkened(0.1), true)
				for i in 6:                                                                           # tilt hoops and canvas
					var z0: float = 0.2 + float(i) * 0.65
					b.box(-1.15, 1.15, 1.4, 2.85, z0, z0 + 0.62, canvas, false)
				b.gable_z(-1.15, 1.15, 0.1, 4.2, 2.85, 0.5, 0.05, canvas.lightened(0.04), canvas.darkened(0.1), 0.05)
				b.box(-0.8, 0.8, 1.45, 2.3, 4.2, 4.26, Color(0.12, 0.12, 0.13), false)
			for z in [-2.1, 1.0, 2.5]:
				for sx in [-1.0, 1.0]:
					_tyre(b, sx * 1.0, z, 0.5, 0.35)
		"kubel", "jeep":
			var hood: float = 0.88 if kind == "jeep" else 0.95
			b.box(-0.8, 0.8, 0.45, 0.95, -1.7, 1.7, c, true, c.darkened(0.05))
			b.box(-0.6, 0.6, 0.95, 1.1, -1.65, -0.55, c.lightened(0.04), true)                       # bonnet
			b.box(-0.82, 0.82, 0.95, 1.35, 0.5, 1.7, c, true, c.darkened(0.06))                     # rear tub
			b.box(-0.68, 0.68, 1.1, 1.55, -0.62, -0.5, glass, false)                                # windscreen
			b.box(-0.6, -0.15, 0.98, 1.2, -0.3, 0.3, dk, false)                                     # seat backs
			b.box(0.15, 0.6, 0.98, 1.2, -0.3, 0.3, dk, false)
			b.wheel(0.0, 0.95, -1.4 if kind == "kubel" else 1.7, 0.36, 0.2, 8, Color(0.08, 0.08, 0.08))   # spare wheel
			for z in [-1.1, 1.1]:
				for sx in [-1.0, 1.0]:
					_tyre(b, sx * 0.85, z, 0.4, 0.25)
		"halftrack":
			b.box(-1.1, 1.1, 0.85, 1.9, -2.5, 2.5, c, true, c.darkened(0.04))
			b.box(-1.0, 1.0, 1.9, 2.3, -1.9, -0.4, c.darkened(0.1), true)                           # cab/armour top
			b.box(-0.8, 0.8, 1.2, 1.8, -2.55, -2.45, chrome.darkened(0.3), false)
			for sx in [-1.0, 1.0]:
				b.box(minf(sx * 0.75, sx * 1.25), maxf(sx * 0.75, sx * 1.25), 0.25, 1.05, -0.2, 2.5, dk, true, dk.lightened(0.05))
				for i in 4:
					b.wheel(sx * 1.0, 0.45, -0.1 + float(i) * 0.7, 0.32, 0.12, 8, dk.darkened(0.3))
				_tyre(b, sx * 1.0, -1.9, 0.45, 0.3)
		"car":
			b.box(-0.75, 0.75, 0.75, 1.35, -0.45, 1.55, c, true, c.darkened(0.03))                  # body / boot
			b.box(-0.6, 0.6, 0.75, 1.4, -1.95, -0.4, c, true, c.lightened(0.03))                    # long bonnet
			b.box(-0.66, 0.66, 1.35, 2.17, -0.1, 1.2, c.lightened(0.04), false)                     # tall upright cabin
			b.box(-0.69, 0.69, 2.17, 2.27, -0.1, 1.2, dk, false, dk)
			b.box(-0.6, 0.6, 1.4, 2.1, -0.12, -0.08, glass, false)
			b.box(-0.69, 0.69, 1.5, 2.05, 0.1, 1.0, glass, false)
			b.box(-0.35, 0.35, 0.8, 1.45, -1.99, -1.94, chrome, false)
			for sx in [-1.0, 1.0]:
				b.box(minf(sx * 0.7, sx * 1.0), maxf(sx * 0.7, sx * 1.0), 0.95, 1.05, -2.0, -0.7, dk, false)
				b.box(minf(sx * 0.7, sx * 1.0), maxf(sx * 0.7, sx * 1.0), 0.95, 1.05, 0.7, 1.6, dk, false)
				b.box(sx * 0.5 - 0.1, sx * 0.5 + 0.1, 1.2, 1.4, -2.02, -1.96, Color(0.9, 0.88, 0.7), false)
				b.box(minf(sx * 0.82, sx * 1.0), maxf(sx * 0.82, sx * 1.0), 0.5, 0.62, -1.5, 1.5, dk, false)
			for z in [-1.3, 1.15]:
				for sx in [-1.0, 1.0]:
					_tyre(b, sx * 0.82, z, 0.36, 0.22)
		"tug", "bombcart":
			# David Brown style airfield tractor: bonnet with a radiator, open seat and steering column, big rear
			# wheels under mudguards, small front wheels, a tow hitch; the bomb cart adds two loaded trolleys
			b.box(-0.45, 0.45, 0.75, 1.45, -1.2, 0.1, c.lightened(0.1), true, c.lightened(0.14))
			b.box(-0.36, 0.36, 0.85, 1.38, -1.26, -1.2, Color(0.20, 0.20, 0.20), false)
			b.box(-0.55, 0.55, 0.6, 0.95, 0.1, 1.15, c, true, c.darkened(0.1))
			b.box(-0.3, 0.3, 0.95, 1.2, 0.45, 0.95, Color(0.16, 0.13, 0.10), true)                   # seat
			b.box(-0.3, 0.3, 1.2, 1.7, 0.9, 0.98, Color(0.16, 0.13, 0.10), false)
			b.box(-0.04, 0.04, 1.2, 1.75, 0.02, 0.1, Color(0.10, 0.10, 0.10), false)                # steering column
			b.box(-0.25, 0.25, 1.72, 1.78, -0.05, 0.2, Color(0.10, 0.10, 0.10), true)
			b.box(-0.05, 0.05, 1.45, 2.3, -0.8, -0.7, Color(0.12, 0.12, 0.12), false)               # exhaust stack
			b.box(-0.08, 0.08, 0.5, 0.62, 1.15, 1.55, Color(0.12, 0.12, 0.12), true)                # hitch
			for sx in [-1.0, 1.0]:
				_tyre(b, sx * 0.85, 0.6, 0.6, 0.4)
				_tyre(b, sx * 0.7, -0.9, 0.35, 0.26)
				b.box(minf(sx * 0.6, sx * 1.1), maxf(sx * 0.6, sx * 1.1), 1.22, 1.3, 0.0, 1.2, c.darkened(0.12), true)
				b.box(minf(sx * 0.6, sx * 1.1), maxf(sx * 0.6, sx * 1.1), 0.9, 1.3, 1.14, 1.2, c.darkened(0.12), false)
			if kind == "bombcart":
				var bomb := Color(0.30, 0.33, 0.20)
				for k in 2:
					var z: float = 3.2 + float(k) * 3.4
					b.box(-0.7, 0.7, 0.55, 0.72, z - 1.4, z + 1.4, c.darkened(0.3), true)
					b.box(-0.05, 0.05, 0.55, 0.65, z - 1.9, z - 1.4, Color(0.12, 0.12, 0.12), true)      # drawbar
					for cr in [-0.8, 0.8]:
						b.box(-0.5, 0.5, 0.72, 0.9, z + cr - 0.08, z + cr + 0.08, c.darkened(0.4), true)  # cradles
					# the bomb: octagonal body, nose cone and a boxed tail fin
					var ring: Array = []
					for s in 8:
						var a: float = TAU * float(s) / 8.0
						ring.append(Vector2(cos(a) * 0.32, 1.12 + sin(a) * 0.32))
					for s in 8:
						var p0: Vector2 = ring[s]
						var p1: Vector2 = ring[(s + 1) % 8]
						var outv := Vector3(p0.x + p1.x, p0.y + p1.y - 2.24, 0.0)
						b.face([Vector3(p0.x, p0.y, z - 1.0), Vector3(p1.x, p1.y, z - 1.0), Vector3(p1.x, p1.y, z + 0.8), Vector3(p0.x, p0.y, z + 0.8)], bomb, outv)
						b.face([Vector3(p0.x, p0.y, z - 1.0), Vector3(p1.x, p1.y, z - 1.0), Vector3(0.0, 1.12, z - 1.45)], Color(0.70, 0.60, 0.20), outv + Vector3(0, 0, -0.5))
						b.face([Vector3(p0.x, p0.y, z + 0.8), Vector3(p1.x, p1.y, z + 0.8), Vector3(0.0, 1.12, z + 1.25)], bomb.darkened(0.1), outv + Vector3(0, 0, 0.5))
					b.box(-0.3, 0.3, 1.09, 1.15, z + 0.9, z + 1.35, bomb.darkened(0.25), true)
					b.box(-0.03, 0.03, 0.82, 1.42, z + 0.9, z + 1.35, bomb.darkened(0.25), true)
					for sx2 in [-1.0, 1.0]:
						_tyre(b, sx2 * 0.75, z, 0.3, 0.2)
		"bus":
			b.box(-1.05, 1.05, 0.6, 2.9, -2.0, 3.6, c, true, c.darkened(0.1))                       # body
			b.box(-1.07, 1.07, 1.75, 2.45, -1.9, 3.5, Color(0.5, 0.58, 0.62), false)               # window band
			for i in 6:
				var wz: float = -1.5 + float(i) * 0.9
				b.box(-1.08, 1.08, 1.75, 2.45, wz + 0.42, wz + 0.48, c.darkened(0.15), false)
			b.box(-0.85, 0.85, 0.6, 1.9, -3.5, -1.9, c, true, c.lightened(0.04))                    # half-cab bonnet
			b.box(-0.5, 0.5, 0.8, 1.7, -3.55, -3.5, chrome, false)
			b.box(-1.0, 1.0, 2.9, 3.05, -1.9, 3.5, c.darkened(0.2), false, c.darkened(0.25))
			for z in [-2.6, 2.3]:
				for sx in [-1.0, 1.0]:
					_tyre(b, sx * 1.0, z, 0.5, 0.3)
	var m: ArrayMesh = b.commit(paint_material())
	_cache[key] = m
	return m


## A horizontal bar between two ground-plan points (for splayed gun trails).
static func _bar_xz(b: MB, p0: Vector3, p1: Vector3, w: float, h: float, col: Color) -> void:
	var d := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z).normalized()
	var s := Vector3(-d.z, 0.0, d.x) * w * 0.5
	var up := Vector3(0.0, h, 0.0)
	b.face([p0 - s + up, p0 + s + up, p1 + s + up, p1 - s + up], col.lightened(0.05), Vector3.UP)
	b.face([p0 + s, p1 + s, p1 + s + up, p0 + s + up], col, s)
	b.face([p0 - s, p1 - s, p1 - s + up, p0 - s + up], col, -s)
	b.face([p1 - s, p1 + s, p1 + s + up, p1 - s + up], col, d)


## Field gun carriage (GroundVehicle "artillery"): spoked wheels, axle, a sloped two-plate shield with a sight port,
## split trails with spades and an ammunition limber box. The barrel is a separate mesh (it trains and recoils).
static func field_gun_carriage(c: Color) -> ArrayMesh:
	var key: String = "fgun_carriage_%s" % c.to_html(false)
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var dk: Color = c.darkened(0.45)
	b.box(-1.0, 1.0, 0.7, 1.15, -1.3, -1.12, c, true)
	b.face([Vector3(-1.0, 1.15, -1.3), Vector3(1.0, 1.15, -1.3), Vector3(1.0, 1.95, -1.05), Vector3(-1.0, 1.95, -1.05)], c.lightened(0.04), Vector3(0, 0.3, -1))
	b.face([Vector3(-1.0, 1.15, -1.3), Vector3(1.0, 1.15, -1.3), Vector3(1.0, 1.95, -1.05), Vector3(-1.0, 1.95, -1.05)], c.darkened(0.15), Vector3(0, -0.3, 1))
	b.box(-0.2, 0.2, 1.2, 1.5, -1.36, -1.3, Color(0.10, 0.10, 0.10), false)
	b.box(-1.25, 1.25, 0.62, 0.78, -0.9, -0.7, dk, true)                                          # axle
	b.box(-0.35, 0.35, 0.78, 1.3, -1.1, -0.3, c.darkened(0.2), true)                              # cradle / saddle
	for sx in [-1.0, 1.0]:
		b.wheel(sx * 1.2, 0.7, -0.8, 0.7, 0.16, 12, Color(0.08, 0.08, 0.08))
		b.wheel(sx * 1.29, 0.7, -0.8, 0.5, 0.03, 10, c.darkened(0.1))
		b.wheel(sx * 1.31, 0.7, -0.8, 0.14, 0.05, 6, dk)
		_bar_xz(b, Vector3(sx * 0.3, 0.45, -0.5), Vector3(sx * 0.95, 0.12, 2.9), 0.2, 0.2, dk)
		b.box(sx * 0.95 - 0.25, sx * 0.95 + 0.25, 0.0, 0.4, 2.85, 2.95, dk.darkened(0.2), true)   # spade
	b.box(1.6, 2.3, 0.0, 0.5, 0.6, 1.5, Color(0.26, 0.28, 0.20), true, Color(0.32, 0.34, 0.24))
	b.box(1.75, 2.15, 0.5, 0.62, 0.7, 1.4, Color(0.50, 0.42, 0.20), true)
	var m: ArrayMesh = b.commit(paint_material())
	_cache[key] = m
	return m


## The field gun's barrel, origin at the trunnion, pointing -Z: breech ring, recoil cylinder, stepped tube, muzzle brake.
static func field_gun_barrel(c: Color) -> ArrayMesh:
	var key: String = "fgun_barrel_%s" % c.to_html(false)
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var iron := Color(0.13, 0.13, 0.14)
	b.box(-0.22, 0.22, -0.12, 0.32, -0.2, 0.55, c.darkened(0.3), true)
	b.box(-0.12, 0.12, -0.22, -0.06, -1.9, 0.3, c.darkened(0.2), true)
	b.box(-0.13, 0.13, 0.0, 0.26, -2.2, -0.2, iron.lightened(0.03), true)
	b.box(-0.09, 0.09, 0.04, 0.22, -4.0, -2.2, iron, true)
	b.box(-0.15, 0.15, -0.02, 0.28, -4.3, -4.0, iron.lightened(0.05), true)
	var m: ArrayMesh = b.commit(paint_material())
	_cache[key] = m
	return m


# ------------------------------------------------------------------ airfield clutter (detailed AirfieldAssets meshes)

## Nissen hut: a half-round corrugated iron roof (radius 3.0, axis along Z, centred at y = 1.3) carried on a
## concrete base, with brick half-disc end walls, a dark door and a small window to the +Z end, a small brick
## porch and a stove pipe. Same placement footprint as the old cylinder-and-box model.
static func nissen_hut(iron: Color) -> ArrayMesh:
	var key: String = "nissen_hut_%s" % iron.to_html(false)
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var brick := Color(0.45, 0.31, 0.24)
	var concrete := Color(0.54, 0.53, 0.49)
	var dark := Color(0.08, 0.08, 0.08)
	var glass := Color(0.16, 0.20, 0.22)
	var r: float = 3.0
	var cy: float = 1.3
	var za: float = -5.5
	var zb: float = 5.5
	var arc: int = 12
	# concrete base: the low walls the iron arch sits on
	b.box(-r, r, -0.15, cy, za + 0.08, zb - 0.08, concrete, false)
	# corrugated roof: flat strips over the upper arc, alternating tone so the corrugation reads at distance
	var roof_lo: Color = iron.darkened(0.06)
	var roof_hi: Color = iron.lightened(0.05)
	for i in arc:
		var a0: float = PI * float(i) / float(arc)
		var a1: float = PI * float(i + 1) / float(arc)
		var am: float = (a0 + a1) * 0.5
		var col: Color = roof_hi if i % 2 == 0 else roof_lo
		b.face([Vector3(cos(a0) * r, cy + sin(a0) * r, za), Vector3(cos(a1) * r, cy + sin(a1) * r, za), Vector3(cos(a1) * r, cy + sin(a1) * r, zb), Vector3(cos(a0) * r, cy + sin(a0) * r, zb)], col, Vector3(cos(am), sin(am), 0.0))
	# a darker hoop rib every 1.2 m
	var ribs: int = int((zb - za) / 1.2) + 1
	var rib_col: Color = iron.darkened(0.28)
	var rr: float = r + 0.06
	for k in ribs:
		var rz: float = za + float(k) * 1.2
		for i in arc:
			var r0: float = PI * float(i) / float(arc)
			var r1: float = PI * float(i + 1) / float(arc)
			var rm: float = (r0 + r1) * 0.5
			b.face([Vector3(cos(r0) * rr, cy + sin(r0) * rr, rz - 0.06), Vector3(cos(r1) * rr, cy + sin(r1) * rr, rz - 0.06), Vector3(cos(r1) * rr, cy + sin(r1) * rr, rz + 0.06), Vector3(cos(r0) * rr, cy + sin(r0) * rr, rz + 0.06)], rib_col, Vector3(cos(rm), sin(rm), 0.0))
	# brick end walls: a half-disc fan over the arc on a short base course at each end
	for ez in [za, zb]:
		var hint: Vector3 = Vector3.FORWARD if ez < 0.0 else Vector3.BACK
		b.box(-r, r, 0.0, cy, ez - 0.08, ez + 0.08, brick, false)
		var fan: Array = [Vector3(0.0, cy, ez)]
		for i in range(arc + 1):
			var a: float = PI * float(i) / float(arc)
			fan.append(Vector3(cos(a) * r, cy + sin(a) * r, ez))
		b.face(fan, brick, hint)
	# the +Z door, window and a small brick porch round the door
	b.box(-1.5, -0.4, 0.0, 2.1, zb + 0.02, zb + 0.18, dark, false)
	b.box(0.9, 1.9, 1.4, 2.2, zb + 0.02, zb + 0.14, glass, false)
	b.box(-1.85, -1.55, 0.0, 2.3, zb, zb + 0.9, brick, false)
	b.box(-0.45, -0.15, 0.0, 2.3, zb, zb + 0.9, brick, false)
	b.box(-1.85, -0.15, 1.9, 2.3, zb, zb + 0.9, brick, true)
	b.box(-1.95, -0.05, 2.3, 2.45, zb - 0.05, zb + 1.0, brick.darkened(0.12), true)
	# stove pipe through the roof at (0.8, -1.5) with a cowl
	b.prism(0.8, -1.5, 1.5, 4.9, 0.16, 0.16, 0.16, 0.16, 6, dark, false)
	b.prism(0.8, -1.5, 4.9, 5.15, 0.34, 0.34, 0.10, 0.10, 6, dark.darkened(0.3), true)
	var m2: ArrayMesh = b.commit(paint_material())
	_cache[key] = m2
	return m2


## Ridge tent: about 4 x 6 m, ridge along Z at y = 2.42, eaves at y = 0.5 on short vertical walls, slightly
## lighter roof panels, a dark open door flap in the +Z end, a ridge pole through both ends, and four guy ropes
## per side with pegs.
static func ridge_tent(cloth: Color) -> ArrayMesh:
	var key: String = "ridge_tent_%s" % cloth.to_html(false)
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var dark := Color(0.10, 0.09, 0.07)
	var rope := Color(0.14, 0.13, 0.11)
	var wall: Color = cloth.darkened(0.10)
	var roof: Color = cloth.lightened(0.06)
	var flap: Color = cloth.darkened(0.40)
	var ridge_y: float = 2.42
	var eave_y: float = 0.5
	var hw: float = 2.0
	var za: float = -3.0
	var zb: float = 3.0
	# slightly lighter roof panels, eave to ridge
	b.face([Vector3(-hw, eave_y, za), Vector3(-hw, eave_y, zb), Vector3(0.0, ridge_y, zb), Vector3(0.0, ridge_y, za)], roof, Vector3(-0.5, 1.0, 0.0))
	b.face([Vector3(hw, eave_y, za), Vector3(hw, eave_y, zb), Vector3(0.0, ridge_y, zb), Vector3(0.0, ridge_y, za)], roof, Vector3(0.5, 1.0, 0.0))
	# short vertical walls below the eaves
	for sx in [-1.0, 1.0]:
		var wx: float = sx * hw
		b.box(wx - 0.055, wx + 0.055, 0.0, eave_y, za, zb, wall, false)
	# end walls as triangles over a short wall course
	for ez in [za, zb]:
		var hint: Vector3 = Vector3.FORWARD if ez < 0.0 else Vector3.BACK
		b.box(-hw, hw, 0.0, eave_y, ez - 0.06, ez + 0.06, wall, false)
		b.face([Vector3(-hw, eave_y, ez), Vector3(hw, eave_y, ez), Vector3(0.0, ridge_y, ez)], cloth, hint)
	# dark open door flap in the +Z end: a dark opening with two angled flap faces
	b.face([Vector3(-1.3, 0.5, zb + 0.02), Vector3(1.3, 0.5, zb + 0.02), Vector3(0.0, 2.2, zb + 0.02)], dark, Vector3.BACK)
	b.face([Vector3(0.0, 2.3, zb + 0.03), Vector3(-1.45, 0.55, zb + 0.03), Vector3(-2.2, 0.55, zb + 0.95), Vector3(-0.6, 2.3, zb + 0.95)], flap, Vector3(-0.3, 0.1, 1.0))
	b.face([Vector3(0.0, 2.3, zb + 0.03), Vector3(1.45, 0.55, zb + 0.03), Vector3(2.2, 0.55, zb + 0.95), Vector3(0.6, 2.3, zb + 0.95)], flap, Vector3(0.3, 0.1, 1.0))
	# ridge pole sticking out past both ends
	b.box(-0.05, 0.05, ridge_y - 0.05, ridge_y + 0.05, za - 0.4, zb + 0.4, dark, false)
	# four guy ropes per side, each to a peg
	for sz in [-2.4, -0.8, 0.8, 2.4]:
		for sg in [-1.0, 1.0]:
			b.beam(Vector3(sg * hw, eave_y + 0.05, sz), Vector3(sg * 3.3, 0.06, sz), 0.025, 0.025, rope)
			b.box(sg * 3.3 - 0.05, sg * 3.3 + 0.05, 0.0, 0.24, sz - 0.05, sz + 0.05, dark, true)
	var m: ArrayMesh = b.commit(paint_material())
	_cache[key] = m
	return m


## Bulk fuel tank: concrete plinth, a 16-sided banded steel drum, a low conical roof with a hatch, a caged ladder
## on the +X side, a railing ring on the roof edge, a pipe run with a valve box toward +Z, and a low earth bund
## with a gap toward +Z. Centre at origin, base y = 0 (same layout as the old fuel_tank()).
static func fuel_tank_model() -> ArrayMesh:
	var key: String = "fuel_tank_model"
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var steel := Color(0.58, 0.58, 0.55)
	var band := Color(0.34, 0.35, 0.34)
	var concrete := Color(0.55, 0.54, 0.50)
	var iron := Color(0.15, 0.15, 0.15)
	var earth := Color(0.34, 0.29, 0.20)
	var segs: int = 16
	# concrete plinth and the banded steel drum
	b.prism(0.0, 0.0, 0.0, 0.5, 5.1, 5.1, 5.1, 5.1, segs, concrete, true)
	b.prism(0.0, 0.0, 0.5, 6.1, 4.5, 4.5, 4.5, 4.5, segs, steel, true)
	for yb in [1.5, 3.3, 5.1]:
		b.prism(0.0, 0.0, yb - 0.11, yb + 0.11, 4.56, 4.56, 4.56, 4.56, segs, band, false)
	# low conical roof and its central hatch
	b.prism(0.0, 0.0, 6.1, 7.2, 4.5, 4.5, 0.8, 0.8, segs, steel.darkened(0.06), false)
	b.prism(0.0, 0.0, 7.2, 7.55, 0.8, 0.8, 0.8, 0.8, 8, band, true)
	b.prism(0.0, 0.0, 7.55, 7.68, 0.9, 0.9, 0.9, 0.9, 8, iron, true)
	# caged ladder up the +X side
	var lx: float = 4.62
	b.box(lx, lx + 0.07, 0.4, 6.3, -0.36, -0.26, iron, false)
	b.box(lx, lx + 0.07, 0.4, 6.3, 0.26, 0.36, iron, false)
	for i in 15:
		var ry: float = 0.6 + float(i) * 0.4
		b.box(lx, lx + 0.05, ry, ry + 0.04, -0.26, 0.26, iron, false)
	for i in 5:
		var cy2: float = 2.6 + float(i) * 0.9
		b.box(lx + 0.5, lx + 0.56, cy2, cy2 + 0.05, -0.55, 0.55, iron, false)
	b.box(lx + 0.5, lx + 0.56, 2.6, 6.5, -0.57, -0.51, iron, false)
	b.box(lx + 0.5, lx + 0.56, 2.6, 6.5, 0.51, 0.57, iron, false)
	# railing ring of short posts and a top rail round the roof edge
	var posts: int = 16
	var rail_r: float = 4.5
	for i in posts:
		var a: float = TAU * float(i) / float(posts)
		var rx: float = cos(a) * rail_r
		var rz: float = sin(a) * rail_r
		b.box(rx - 0.05, rx + 0.05, 6.0, 6.9, rz - 0.05, rz + 0.05, iron, false)
	for i in posts:
		var a0: float = TAU * float(i) / float(posts)
		var a1: float = TAU * float(i + 1) / float(posts)
		b.beam(Vector3(cos(a0) * rail_r, 6.85, sin(a0) * rail_r), Vector3(cos(a1) * rail_r, 6.85, sin(a1) * rail_r), 0.04, 0.04, iron)
	# pipe run toward +Z with a valve box
	var nseg: int = 8
	var pipe_y: float = 0.9
	var pipe_r: float = 0.28
	var ring: Array = []
	for s in nseg:
		var a: float = TAU * float(s) / float(nseg)
		ring.append(Vector2(cos(a) * pipe_r, pipe_y + sin(a) * pipe_r))
	for s in nseg:
		var q0: Vector2 = ring[s]
		var q1: Vector2 = ring[(s + 1) % nseg]
		var outv := Vector3(q0.x, q0.y - pipe_y, 0.0).normalized()
		b.face([Vector3(q0.x, q0.y, 4.4), Vector3(q1.x, q1.y, 4.4), Vector3(q1.x, q1.y, 7.0), Vector3(q0.x, q0.y, 7.0)], band, outv)
	var cap: Array = []
	for s in nseg:
		var a: float = TAU * float(s) / float(nseg)
		cap.append(Vector3(cos(a) * pipe_r, pipe_y + sin(a) * pipe_r, 7.0))
	b.face(cap, band.darkened(0.2), Vector3.BACK)
	b.box(-0.45, 0.45, 0.45, 1.35, 5.35, 5.95, iron, true)
	b.prism(0.0, 5.65, 1.35, 1.9, 0.12, 0.12, 0.12, 0.12, 6, iron, true)
	b.box(-0.22, 0.22, 1.9, 2.0, 5.43, 5.87, iron.darkened(0.2), true)
	# earth bund wall ring (low, radius 8.5, gap toward +Z)
	var bsegs: int = 16
	var bund_o: float = 8.5
	var bund_i: float = 7.9
	var bund_h: float = 1.3
	for i in bsegs:
		if i == 3 or i == 4:
			continue
		var a0: float = TAU * float(i) / float(bsegs)
		var a1: float = TAU * float(i + 1) / float(bsegs)
		var am: float = (a0 + a1) * 0.5
		var o0 := Vector3(cos(a0) * bund_o, 0.0, sin(a0) * bund_o)
		var o1 := Vector3(cos(a1) * bund_o, 0.0, sin(a1) * bund_o)
		var i0 := Vector3(cos(a0) * bund_i, 0.0, sin(a0) * bund_i)
		var i1 := Vector3(cos(a1) * bund_i, 0.0, sin(a1) * bund_i)
		b.face([o0, o1, Vector3(o1.x, bund_h, o1.z), Vector3(o0.x, bund_h, o0.z)], earth, Vector3(cos(am), 0.2, sin(am)))
		b.face([i0, i1, Vector3(i1.x, bund_h, i1.z), Vector3(i0.x, bund_h, i0.z)], earth.darkened(0.08), Vector3(-cos(am), 0.2, -sin(am)))
		b.face([Vector3(o0.x, bund_h, o0.z), Vector3(o1.x, bund_h, o1.z), Vector3(i1.x, bund_h, i1.z), Vector3(i0.x, bund_h, i0.z)], earth.lightened(0.08), Vector3.UP)
	for ge in [3, 5]:
		var ga: float = TAU * float(ge) / float(bsegs)
		var g0 := Vector3(cos(ga) * bund_i, 0.0, sin(ga) * bund_i)
		var g1 := Vector3(cos(ga) * bund_o, 0.0, sin(ga) * bund_o)
		var gh: Vector3 = Vector3(-sin(ga), 0.1, cos(ga)) if ge == 3 else Vector3(sin(ga), 0.1, -cos(ga))
		b.face([g0, g1, Vector3(g1.x, bund_h, g1.z), Vector3(g0.x, bund_h, g0.z)], earth.darkened(0.05), gh)
	var m: ArrayMesh = b.commit(paint_material())
	_cache[key] = m
	return m


# ------------------------------------------------------------------ windmill and lighthouse (Landmarks)

## Tower mill body: tapering tarred brick tower on a plinth with a door, a stage (gallery) on brackets, small
## windows up the tower, and a boat-shaped cap with a fantail frame at the back. The sails turn separately; the
## windshaft is at (0, 15, -3.6), as in the old model.
static func windmill_body() -> ArrayMesh:
	if _cache.has("windmill_body"):
		return _cache["windmill_body"]
	var b := MB.new()
	var tower := Color(0.66, 0.62, 0.53)
	var tar := Color(0.20, 0.18, 0.16)
	var wood := Color(0.35, 0.25, 0.18)
	var white := Color(0.80, 0.77, 0.68)
	b.prism(0.0, 0.0, 0.0, 1.2, 5.3, 5.3, 5.2, 5.2, 12, tower.darkened(0.25), false)
	b.prism(0.0, 0.0, 1.2, 16.0, 5.0, 5.0, 3.0, 3.0, 12, tower, true)
	b.prism(0.0, 0.0, 12.6, 13.0, 3.6, 3.6, 3.5, 3.5, 12, tar, true)
	# the stage: a plank gallery ring with a rail, on raking brackets
	b.prism(0.0, 0.0, 5.6, 5.85, 6.4, 6.4, 6.4, 6.4, 12, wood, true)
	for i in 12:
		var a: float = TAU * float(i) / 12.0
		var px: float = cos(a) * 6.25
		var pz: float = sin(a) * 6.25
		b.box(px - 0.08, px + 0.08, 5.85, 6.9, pz - 0.08, pz + 0.08, white, false)
		b.beam(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0), 0.1, 0.1, wood)
	b.prism(0.0, 0.0, 6.85, 6.97, 6.35, 6.35, 6.35, 6.35, 12, white, false)
	b.prism(0.0, 0.0, 6.85, 6.97, 6.15, 6.15, 6.15, 6.15, 12, white, false)
	# door and windows facing the sails, and one each side
	b.box(-0.7, 0.7, 0.0, 2.4, -5.25, -4.75, tar, false)
	for wy in [8.0, 11.0, 13.6]:
		var rr: float = lerpf(5.0, 3.0, (wy - 1.2) / 14.8)
		b.box(-0.35, 0.35, wy, wy + 0.9, -rr - 0.08, -rr + 0.3, tar, false)
		b.box(-rr - 0.08, -rr + 0.3, wy - 1.2, wy - 0.3, -0.35, 0.35, tar, false)
	# boat-shaped cap, windshaft boss, and the fantail frame behind
	b.prism(0.0, 0.0, 16.0, 16.4, 3.3, 3.3, 3.3, 3.3, 12, wood.darkened(0.2), true)
	b.gable_z(-3.1, 3.1, -3.4, 3.6, 16.4, 3.0, 0.2, white, white.darkened(0.08), 0.0)
	b.box(-0.35, 0.35, 14.65, 15.35, -3.9, -3.2, tar, true)
	b.box(-0.08, 0.08, 16.4, 20.4, 3.6, 3.76, wood, false)
	b.box(-1.6, 1.6, 18.3, 18.46, 3.6, 3.76, wood, false)
	for k in 6:
		var fa: float = TAU * float(k) / 6.0
		b.box(cos(fa) * 1.0 - 0.3, cos(fa) * 1.0 + 0.3, 19.2 + sin(fa) * 1.0 - 0.3, 19.2 + sin(fa) * 1.0 + 0.3, 3.8, 3.86, white, false)
	var m: ArrayMesh = b.commit(paint_material())
	_cache["windmill_body"] = m
	return m


## One windmill sail (arm along +Y from the shaft): the stock, a lattice of sail bars and the hemlath edge.
static func windmill_sail() -> ArrayMesh:
	if _cache.has("windmill_sail"):
		return _cache["windmill_sail"]
	var b := MB.new()
	var wood := Color(0.78, 0.74, 0.64)
	b.box(-0.14, 0.14, 0.0, 15.5, -0.12, 0.12, wood.darkened(0.25), true)
	b.box(0.14, 2.0, 3.0, 3.12, -0.06, 0.06, wood, false)
	for i in 14:
		var y: float = 3.0 + float(i) * 0.95
		b.box(0.14, 2.0, y, y + 0.1, -0.05, 0.05, wood, false)
	for xx in [0.75, 1.4, 2.0]:
		b.box(xx - 0.05, xx + 0.05, 3.0, 15.4, -0.05, 0.05, wood, false)
	b.box(-0.6, -0.14, 3.0, 15.4, -0.04, 0.04, wood.darkened(0.1), false)
	var m: ArrayMesh = b.commit(paint_material())
	_cache["windmill_sail"] = m
	return m


## Lighthouse of height h: stepped stone base, tapering white tower with a red band and window slits, gallery with
## a railing, glazed lantern room with its lamp, and a domed roof with a vent ball. (No outbuildings: most stand on rocks and pier heads.)
static func lighthouse(h: float) -> ArrayMesh:
	var key: String = "lighthouse_%d" % int(h)
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var white := Color(0.88, 0.86, 0.82)
	var red := Color(0.70, 0.15, 0.12)
	var dark := Color(0.16, 0.16, 0.18)
	b.prism(0.0, 0.0, 0.0, 1.0, 6.2, 6.2, 6.0, 6.0, 14, Color(0.50, 0.48, 0.44), true)
	b.prism(0.0, 0.0, 1.0, h * 0.30, 5.0, 5.0, 4.4, 4.4, 14, white, false)
	b.prism(0.0, 0.0, h * 0.30, h * 0.42, 4.4, 4.4, 4.15, 4.15, 14, red, false)
	b.prism(0.0, 0.0, h * 0.42, h, 4.15, 4.15, 3.0, 3.0, 14, white, true)
	b.box(-0.7, 0.7, 1.0, 3.4, -5.05, -4.6, dark, false)
	for wy in [0.2, 0.55, 0.8]:
		var rr: float = lerpf(5.0, 3.0, wy)
		b.box(-0.3, 0.3, h * wy, h * wy + 1.4, -rr - 0.06, -rr + 0.4, dark, false)
	# gallery, railing, lantern room (glazing bars over a bright lamp), dome and vent
	b.prism(0.0, 0.0, h, h + 0.4, 4.0, 4.0, 4.0, 4.0, 14, dark, true)
	for i in 14:
		var a: float = TAU * float(i) / 14.0
		b.box(cos(a) * 3.85 - 0.06, cos(a) * 3.85 + 0.06, h + 0.4, h + 1.5, sin(a) * 3.85 - 0.06, sin(a) * 3.85 + 0.06, dark, false)
	b.prism(0.0, 0.0, h + 1.42, h + 1.54, 3.92, 3.92, 3.92, 3.92, 14, dark, false)
	b.prism(0.0, 0.0, h + 0.4, h + 1.2, 2.7, 2.7, 2.7, 2.7, 10, white, false)
	b.prism(0.0, 0.0, h + 1.2, h + 4.2, 2.5, 2.5, 2.5, 2.5, 10, Color(0.92, 0.88, 0.55), false)
	for i in 10:
		var a2: float = TAU * float(i) / 10.0
		b.box(cos(a2) * 2.55 - 0.07, cos(a2) * 2.55 + 0.07, h + 1.2, h + 4.2, sin(a2) * 2.55 - 0.07, sin(a2) * 2.55 + 0.07, dark, false)
	b.prism(0.0, 0.0, h + 4.2, h + 4.5, 2.9, 2.9, 2.9, 2.9, 10, dark, true)
	b.prism(0.0, 0.0, h + 4.5, h + 5.8, 2.7, 2.7, 1.5, 1.5, 10, dark.lightened(0.06), false)
	b.prism(0.0, 0.0, h + 5.8, h + 6.6, 1.5, 1.5, 0.0, 0.0, 10, dark.lightened(0.1), false)
	b.prism(0.0, 0.0, h + 6.4, h + 7.1, 0.3, 0.3, 0.3, 0.3, 6, dark, true)
	var m: ArrayMesh = b.commit(paint_material())
	_cache[key] = m
	return m


# ------------------------------------------------------------------ cathedral (Landmarks._cathedral)

## Great church in the old generic layout (nave along Z, west towers at +Z, apse at -Z): a tall clerestoried nave
## over lean-to aisles, buttresses with pinnacles, a gabled transept, a polygonal apse with an ambulatory, a west
## front with a portal and rose window between one or two staged towers (with octagonal spires when spire_h > 0),
## and either a dome on a drum or a slender fleche over the crossing. `ruin` leaves it roofless and scorched.
static func cathedral(nave_len: float, nave_w: float, tower_h: float, towers: int, spire_h: float, col: Color, dome: bool, ruin: bool) -> ArrayMesh:
	var key: String = "cath_%d_%d_%d_%d_%d_%s_%s_%s" % [int(nave_len), int(nave_w), int(tower_h), towers, int(spire_h), col.to_html(false), str(dome), str(ruin)]
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var roof := Color(0.28, 0.29, 0.33)
	var dark := Color(0.13, 0.12, 0.12)
	var dress: Color = col.lightened(0.10)
	var wall_h: float = tower_h * 0.28
	var hl: float = nave_len * 0.5
	var hw: float = nave_w * 0.5
	var cw: float = hw * 0.52                      # half-width of the central vessel
	var aisle_h: float = wall_h * 0.58
	var rise: float = tower_h * 0.13
	var z_tw: float = hl - nave_w * 0.18           # tower centre line
	var z_w: float = hl - nave_w * 0.36            # nave stops at the tower block
	var tx: float = nave_len * 0.05                # transept centre
	var thw: float = nave_len * 0.08
	# nave, aisles and their roofs
	b.box(-cw, cw, 0.0, wall_h, -hl, z_w, col, ruin, col.darkened(0.5))
	if not ruin:
		b.gable_z(-cw, cw, -hl, z_w, wall_h, rise, cw * 0.06, roof, col, 0.0)
	for sx in [-1.0, 1.0]:
		var x0: float = minf(sx * cw, sx * hw)
		var x1: float = maxf(sx * cw, sx * hw)
		b.box(x0, x1, 0.0, aisle_h, -hl * 0.92, z_w, col.darkened(0.04), ruin, col.darkened(0.5))
		if not ruin:
			b.mono(x0, x1, -hl * 0.92, z_w, aisle_h, aisle_h + wall_h * 0.16, "x1" if sx < 0.0 else "x0", roof.lightened(0.06), col.darkened(0.04), hw * 0.03)
		# clerestory window slots and aisle buttresses with pinnacles
		var bays: int = 9
		for i in bays:
			var bz: float = lerpf(-hl * 0.86, z_w - nave_w * 0.12, float(i) / float(bays - 1))
			if absf(bz - tx) < thw * 1.2:
				continue
			var bx0: float = minf(sx * hw, sx * (hw + nave_w * 0.05))
			var bx1: float = maxf(sx * hw, sx * (hw + nave_w * 0.05))
			var bt: float = nave_w * 0.03
			b.box(bx0, bx1, 0.0, aisle_h * 0.92, bz - bt, bz + bt, dress.darkened(0.06), false)
			b.prism((bx0 + bx1) * 0.5, bz, aisle_h * 0.92, aisle_h * 0.92 + wall_h * 0.22, nave_w * 0.03, nave_w * 0.03, 0.0, 0.0, 4, dress, false, PI * 0.25)
			b.box(minf(sx * cw, sx * (cw + 0.3)), maxf(sx * cw, sx * (cw + 0.3)), aisle_h + wall_h * 0.2, wall_h * 0.92, bz + bt * 2.0, bz + bt * 2.0 + nave_w * 0.07, dark, false)
	# transept with gable ends and a big window each end
	b.box(-hw * 1.5, hw * 1.5, 0.0, wall_h, tx - thw, tx + thw, col, ruin, col.darkened(0.5))
	if not ruin:
		b.gable_x(-hw * 1.5, hw * 1.5, tx - thw, tx + thw, wall_h, rise * 0.9, thw * 0.06, roof, col, 0.0)
	for sx2 in [-1.0, 1.0]:
		b.box(minf(sx2 * hw * 1.5, sx2 * (hw * 1.5 + 0.4)), maxf(sx2 * hw * 1.5, sx2 * (hw * 1.5 + 0.4)), wall_h * 0.3, wall_h * 0.85, tx - thw * 0.4, tx + thw * 0.4, dark, false)
	# apse: a polygonal east end with a lower ambulatory and conical roofs
	b.prism(0.0, -hl, 0.0, aisle_h, hw * 0.95, hw * 0.95, hw * 0.95, hw * 0.95, 10, col.darkened(0.04), ruin)
	b.prism(0.0, -hl, aisle_h, wall_h, cw, cw, cw, cw, 10, col, ruin)
	if not ruin:
		b.prism(0.0, -hl, aisle_h, aisle_h + wall_h * 0.14, hw, hw, cw, cw, 10, roof.lightened(0.06), false)
		b.prism(0.0, -hl, wall_h, wall_h + rise, cw * 1.05, cw * 1.05, 0.0, 0.0, 10, roof, false)
	# west front: tower block, portal and rose window, gable between the towers
	var tw: float = nave_w * 0.34
	var th2: float = tw * 0.5
	b.box(-hw, hw, 0.0, wall_h, z_w, hl, col, true, roof)
	b.box(-cw * 0.45, cw * 0.45, 0.0, wall_h * 0.42, hl, hl + 0.5, dark, false)
	b.prism(0.0, hl + 0.3, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3, dark, false)
	b.box(-cw * 0.42, cw * 0.42, wall_h * 0.52, wall_h * 0.88, hl, hl + 0.4, Color(0.16, 0.18, 0.24), false)
	if not ruin:
		b.gable_z(-cw, cw, z_w, hl, wall_h, rise, 0.0, roof, dress, 0.0)
	for i in towers:
		var x: float = 0.0 if towers == 1 else (-nave_w * 0.3 if i == 0 else nave_w * 0.3)
		b.box(x - th2, x + th2, 0.0, tower_h, z_tw - th2, z_tw + th2, col, true, roof)
		for st in [0.34, 0.58, 0.80]:
			b.box(x - th2 * 1.06, x + th2 * 1.06, tower_h * st, tower_h * st + tower_h * 0.012, z_tw - th2 * 1.06, z_tw + th2 * 1.06, dress)
		# paired belfry openings on each face
		for f in 4:
			var ang: float = float(f) * PI * 0.5
			var dx: float = cos(ang)
			var dz: float = sin(ang)
			for off in [-0.22, 0.22]:
				if absf(dx) > 0.5:
					b.box(x + dx * th2 - 0.3, x + dx * th2 + 0.3, tower_h * 0.83, tower_h * 0.96, z_tw + off * tw - tw * 0.09, z_tw + off * tw + tw * 0.09, dark, false)
				else:
					b.box(x + off * tw - tw * 0.09, x + off * tw + tw * 0.09, tower_h * 0.83, tower_h * 0.96, z_tw + dz * th2 - 0.3, z_tw + dz * th2 + 0.3, dark, false)
		# parapet and corner pinnacles, then the spire
		b.box(x - th2 * 1.05, x + th2 * 1.05, tower_h, tower_h + tower_h * 0.02, z_tw - th2 * 1.05, z_tw + th2 * 1.05, dress, true, roof)
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				b.prism(x + cx * th2 * 0.9, z_tw + cz * th2 * 0.9, tower_h, tower_h + maxf(spire_h * 0.28, tower_h * 0.07), tw * 0.10, tw * 0.10, 0.0, 0.0, 6, dress, false)
		if spire_h > 0.0:
			b.prism(x, z_tw, tower_h + tower_h * 0.02, tower_h + spire_h, tw * 0.46, tw * 0.46, 0.0, 0.0, 8, col.darkened(0.14), false, PI / 8.0)
	# crossing: dome on a drum, or a fleche
	if dome:
		var dr: float = nave_w * 0.42
		var copper := Color(0.42, 0.56, 0.52)
		b.prism(0.0, tx, wall_h, wall_h + dr * 0.55, dr, dr, dr, dr, 12, dress, false)
		b.prism(0.0, tx, wall_h + dr * 0.55, wall_h + dr * 0.95, dr * 1.02, dr * 1.02, dr * 0.78, dr * 0.78, 12, copper, false)
		b.prism(0.0, tx, wall_h + dr * 0.95, wall_h + dr * 1.25, dr * 0.78, dr * 0.78, dr * 0.40, dr * 0.40, 12, copper.lightened(0.04), false)
		b.prism(0.0, tx, wall_h + dr * 1.25, wall_h + dr * 1.38, dr * 0.40, dr * 0.40, 0.0, 0.0, 12, copper.lightened(0.08), false)
		b.prism(0.0, tx, wall_h + dr * 1.36, wall_h + dr * 1.70, dr * 0.10, dr * 0.10, dr * 0.08, dr * 0.08, 8, dress, true)
		b.prism(0.0, tx, wall_h + dr * 1.70, wall_h + dr * 1.90, dr * 0.10, dr * 0.10, 0.0, 0.0, 8, Color(0.62, 0.52, 0.22), false)
	elif not ruin:
		b.prism(0.0, tx, wall_h + rise * 0.8, wall_h + rise + tower_h * 0.24, nave_w * 0.05, nave_w * 0.05, 0.0, 0.0, 8, roof.lightened(0.08), false)
	var m: ArrayMesh = b.commit(paint_material())
	_cache[key] = m
	return m


# ------------------------------------------------------------------ Calais belfry and blister hangar

## The belfry and town hall of Calais (Flemish neo-Renaissance, red brick banded with pale stone): a square
## tower with stone bands and corner turrets, a clock stage with four faces, an arcaded gallery, a slated bulbous
## cap and lantern to about 75 m, beside the long gabled hall with stepped gables and dormers.
static func calais_belfry() -> ArrayMesh:
	if _cache.has("calais_belfry"):
		return _cache["calais_belfry"]
	var b := MB.new()
	var brick := Color(0.62, 0.38, 0.30)
	var stone := Color(0.72, 0.68, 0.58)
	var slate := Color(0.26, 0.28, 0.32)
	var dark := Color(0.13, 0.12, 0.12)
	var gold := Color(0.70, 0.58, 0.24)
	# tower shaft with stone bands and corner turrets
	b.box(-7.0, 7.0, 0.0, 50.0, -7.0, 7.0, brick, false)
	for i in 9:
		var y: float = 4.0 + float(i) * 5.4
		b.box(-7.15, 7.15, y, y + 0.9, -7.15, 7.15, stone)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			b.prism(cx * 7.0, cz * 7.0, 0.0, 53.0, 1.5, 1.5, 1.4, 1.4, 8, stone.darkened(0.05), false)
			b.prism(cx * 7.0, cz * 7.0, 53.0, 58.0, 1.7, 1.7, 0.0, 0.0, 8, slate, false)
	# clock stage: wider, four gilt-rimmed faces
	b.box(-8.2, 8.2, 50.0, 59.0, -8.2, 8.2, stone, true, slate)
	b.box(-8.6, 8.6, 49.4, 50.0, -8.6, 8.6, stone.lightened(0.06))
	b.box(-8.6, 8.6, 59.0, 59.7, -8.6, 8.6, stone.lightened(0.06))
	for f in 4:
		var ang: float = float(f) * PI * 0.5
		var dx: float = cos(ang)
		var dz: float = sin(ang)
		if absf(dx) > 0.5:
			b.box(dx * 8.2 - 0.12, dx * 8.2 + 0.12, 51.6, 57.6, -3.0, 3.0, gold, false)
			b.box(dx * 8.3 - 0.12, dx * 8.3 + 0.12, 52.1, 57.1, -2.5, 2.5, Color(0.90, 0.88, 0.80), false)
		else:
			b.box(-3.0, 3.0, 51.6, 57.6, dz * 8.2 - 0.12, dz * 8.2 + 0.12, gold, false)
			b.box(-2.5, 2.5, 52.1, 57.1, dz * 8.3 - 0.12, dz * 8.3 + 0.12, Color(0.90, 0.88, 0.80), false)
	# arcaded gallery: eight columns round an open bell stage, then the bulbous cap, lantern and vane
	for k in 8:
		var ka: float = PI / 8.0 + float(k) * TAU / 8.0
		b.prism(cos(ka) * 5.6, sin(ka) * 5.6, 59.7, 65.0, 0.6, 0.6, 0.6, 0.6, 6, stone, false)
	b.prism(0.0, 0.0, 59.7, 65.0, 3.6, 3.6, 3.6, 3.6, 8, dark, false, PI / 8.0)
	b.prism(0.0, 0.0, 65.0, 65.8, 6.6, 6.6, 6.6, 6.6, 8, stone, true, PI / 8.0)
	b.prism(0.0, 0.0, 65.8, 68.5, 6.0, 6.0, 6.6, 6.6, 8, slate, false, PI / 8.0)
	b.prism(0.0, 0.0, 68.5, 71.5, 6.6, 6.6, 3.2, 3.2, 8, slate.lightened(0.04), false, PI / 8.0)
	b.prism(0.0, 0.0, 71.5, 74.5, 2.4, 2.4, 2.4, 2.4, 8, stone, true, PI / 8.0)
	b.prism(0.0, 0.0, 74.5, 79.0, 2.8, 2.8, 0.0, 0.0, 8, slate, false, PI / 8.0)
	b.prism(0.0, 0.0, 78.6, 82.0, 0.16, 0.16, 0.05, 0.05, 4, gold, false)
	# the town hall range: brick with stone bands, steep slate roof, stepped end gable, dormers, entrance
	b.box(-59.0, -9.0, 0.0, 16.0, -12.0, 12.0, brick, false)
	for hy in [5.0, 10.4, 15.2]:
		b.box(-59.2, -9.0, hy, hy + 0.8, -12.2, 12.2, stone)
	b.gable_x(-59.0, -9.0, -12.0, 12.0, 16.0, 9.0, 0.6, slate, brick, 0.0)
	for st in 5:
		var sw: float = 12.0 - float(st) * 2.4
		b.box(-60.0, -59.0, 16.0 + float(st) * 1.9, 17.9 + float(st) * 1.9, -sw, sw, stone.darkened(0.04))
	for d in 6:
		var dxx: float = -54.0 + float(d) * 8.0
		for sz in [-1.0, 1.0]:
			b.box(dxx - 1.2, dxx + 1.2, 17.0, 20.2, minf(sz * 9.0, sz * 10.4), maxf(sz * 9.0, sz * 10.4), stone, false)
			b.gable_z(dxx - 1.2, dxx + 1.2, minf(sz * 7.0, sz * 10.4), maxf(sz * 7.0, sz * 10.4), 20.2, 1.6, 0.15, slate, stone, 0.0)
	b.box(-37.0, -31.0, 0.0, 7.0, 12.0, 12.4, dark, false)
	b.box(-39.0, -29.0, 0.0, 20.0, 12.0, 13.0, stone.darkened(0.02), false)
	b.gable_z(-39.0, -29.0, 9.0, 13.0, 20.0, 5.0, 0.0, slate, stone, 0.0)
	b.box(-36.5, -31.5, 0.0, 6.5, 13.0, 13.2, dark, false)
	var m: ArrayMesh = b.commit(paint_material())
	_cache["calais_belfry"] = m
	return m


## Blister hangar (the old AirfieldAssets.blister footprint: an arch of radius 5 on the ground, 15 m long, open at
## +Z): corrugated arch in strips with raised ribs, a dark interior, a canvas door curtain drawn half across, the
## blank rear wall with a small door, and sandbags along the foot of each side.
static func blister_hangar(skin: Color) -> ArrayMesh:
	var key: String = "blister_%s" % skin.to_html(false)
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var rib: Color = skin.darkened(0.22)
	var dark := Color(0.06, 0.06, 0.06)
	var r: float = 5.0
	var n: int = 12
	var z0: float = -7.5
	var z1: float = 7.5
	for i in n:
		var a0: float = PI * float(i) / float(n)
		var a1: float = PI * float(i + 1) / float(n)
		var p0 := Vector2(cos(a0) * r, sin(a0) * r)
		var p1 := Vector2(cos(a1) * r, sin(a1) * r)
		var am: float = (a0 + a1) * 0.5
		var outv := Vector3(cos(am), sin(am), 0.0)
		var tone: Color = skin if i % 2 == 0 else skin.lightened(0.05)
		b.face([Vector3(p0.x, p0.y, z0), Vector3(p1.x, p1.y, z0), Vector3(p1.x, p1.y, z1), Vector3(p0.x, p0.y, z1)], tone, outv)
		# the inside of the shell, dark, so the open end reads as a cavern
		b.face([Vector3(p0.x * 0.97, p0.y * 0.97, z0), Vector3(p1.x * 0.97, p1.y * 0.97, z0), Vector3(p1.x * 0.97, p1.y * 0.97, z1), Vector3(p0.x * 0.97, p0.y * 0.97, z1)], dark, -outv)
		for k in 7:
			var rz: float = -6.6 + float(k) * 2.2
			b.face([Vector3(p0.x * 1.05, p0.y * 1.05, rz - 0.25), Vector3(p1.x * 1.05, p1.y * 1.05, rz - 0.25), Vector3(p1.x * 1.05, p1.y * 1.05, rz + 0.25), Vector3(p0.x * 1.05, p0.y * 1.05, rz + 0.25)], rib, outv)
		# rear wall as a fan, and the front arch frame
		b.face([Vector3(0.0, 0.0, z0), Vector3(p0.x, p0.y, z0), Vector3(p1.x, p1.y, z0)], skin.darkened(0.06), Vector3.FORWARD)
		b.face([Vector3(0.0, 0.0, z0 + 0.05), Vector3(p0.x, p0.y, z0 + 0.05), Vector3(p1.x, p1.y, z0 + 0.05)], dark, Vector3.BACK)
		b.face([Vector3(p0.x * 1.05, p0.y * 1.05, z1), Vector3(p1.x * 1.05, p1.y * 1.05, z1), Vector3(p1.x * 0.9, p1.y * 0.9, z1 + 0.05), Vector3(p0.x * 0.9, p0.y * 0.9, z1 + 0.05)], rib, Vector3.BACK)
	b.box(-4.9, 4.9, 0.0, 0.08, z0, z1 + 3.0, Color(0.30, 0.29, 0.27), true)
	b.box(-0.6, 0.6, 0.0, 2.1, z0 - 0.08, z0, dark, false)
	# canvas curtain drawn across the starboard half of the opening, hanging in folds
	var cloth: Color = skin.lerp(Color(0.42, 0.40, 0.30), 0.6)
	for c in 5:
		var cx0: float = 0.8 + float(c) * 0.78
		var top: float = sqrt(maxf(r * r * 0.9 - (cx0 + 0.39) * (cx0 + 0.39), 0.1))
		b.box(cx0, cx0 + 0.78, 0.05, top, z1 + (0.06 if c % 2 == 0 else 0.2), z1 + (0.14 if c % 2 == 0 else 0.28), cloth * (0.95 + 0.06 * float(c % 2)), false)
	for sx in [-1.0, 1.0]:
		for s in 6:
			var sz: float = -6.2 + float(s) * 2.4
			b.box(minf(sx * 5.0, sx * 5.7), maxf(sx * 5.0, sx * 5.7), 0.0, 0.5, sz - 0.9, sz + 0.9, Color(0.55, 0.49, 0.36) * (0.92 + 0.1 * float(s % 2)), true)
	var m: ArrayMesh = b.commit(paint_material())
	_cache[key] = m
	return m


# ------------------------------------------------------------------ town gasworks and goods yard (Scatter._build_civic)

## Town gas works in the old layout: two telescopic gasholders (x = -26 and +26) inside lattice guide frames with
## ring girders, one holder part-lowered; a retort house with a louvred ridge at z = +30, a tall round chimney, a
## purifier shed, coal heaps and a boundary wall.
static func gasworks() -> ArrayMesh:
	if _cache.has("gasworks"):
		return _cache["gasworks"]
	var b := MB.new()
	var drum := Color(0.42, 0.44, 0.46)
	var frame := Color(0.28, 0.28, 0.30)
	var soot := Color(0.35, 0.23, 0.18)
	var slate := Color(0.27, 0.28, 0.31)
	var coal := Color(0.09, 0.09, 0.10)
	for gi in 2:
		var gx: float = -26.0 + float(gi) * 52.0
		var lift: float = 26.0 if gi == 0 else 15.0            # the second holder is part empty
		b.prism(gx, 0.0, 0.0, 3.0, 21.0, 21.0, 21.0, 21.0, 20, soot.darkened(0.2), true)
		b.prism(gx, 0.0, 3.0, lift * 0.55, 20.0, 20.0, 20.0, 20.0, 20, drum.darkened(0.08), false)
		b.prism(gx, 0.0, lift * 0.55, lift, 19.0, 19.0, 19.0, 19.0, 20, drum, false)
		b.prism(gx, 0.0, lift, lift + 2.4, 19.0, 19.0, 4.0, 4.0, 20, drum.lightened(0.08), true)
		b.prism(gx, 0.0, lift * 0.55 - 0.4, lift * 0.55 + 0.4, 20.3, 20.3, 20.3, 20.3, 20, frame, false)
		# guide frame: columns, three ring girders and diagonal bracing between columns
		var cols: int = 10
		for fi in cols:
			var fa: float = TAU * float(fi) / float(cols)
			var fb: float = TAU * float(fi + 1) / float(cols)
			var p0 := Vector3(gx + cos(fa) * 21.6, 0.0, sin(fa) * 21.6)
			var p1 := Vector3(gx + cos(fb) * 21.6, 0.0, sin(fb) * 21.6)
			b.box(p0.x - 0.4, p0.x + 0.4, 0.0, 29.0, p0.z - 0.4, p0.z + 0.4, frame, true)
			for ry in [10.0, 19.5, 28.6]:
				_bar_xz(b, Vector3(p0.x, ry, p0.z), Vector3(p1.x, ry, p1.z), 0.35, 0.5, frame)
	# retort house with a raised louvred ridge, chimney, purifier shed, coal heaps, boundary wall
	b.box(-22.0, 22.0, 0.0, 12.0, 20.0, 40.0, soot, false)
	b.gable_x(-22.0, 22.0, 20.0, 40.0, 12.0, 4.5, 0.4, slate, soot, 0.0)
	b.box(-18.0, 18.0, 15.6, 17.4, 28.5, 31.5, soot.darkened(0.2), false)
	b.gable_x(-18.0, 18.0, 28.2, 31.8, 17.4, 0.9, 0.2, slate.lightened(0.05), soot.darkened(0.2), 0.0)
	for d in 5:
		b.box(-18.0 + float(d) * 8.0, -15.0 + float(d) * 8.0, 0.0, 5.0, 19.9, 20.0, Color(0.10, 0.09, 0.09), false)
	b.prism(-30.0, 30.0, 0.0, 5.0, 3.4, 3.4, 3.0, 3.0, 10, soot.darkened(0.1), false)
	b.prism(-30.0, 30.0, 5.0, 46.0, 2.6, 2.6, 1.7, 1.7, 10, soot.darkened(0.15), true)
	b.prism(-30.0, 30.0, 45.0, 46.6, 2.0, 2.0, 2.0, 2.0, 10, soot.darkened(0.35), true)
	b.box(28.0, 46.0, 0.0, 6.0, 24.0, 36.0, soot.lightened(0.06), false)
	b.gable_x(28.0, 46.0, 24.0, 36.0, 6.0, 2.6, 0.3, slate, soot.lightened(0.06), 0.0)
	for h in 3:
		b.prism(-8.0 + float(h) * 9.0, 47.0, 0.0, 3.2 - float(h) * 0.5, 4.5, 3.6, 0.6, 0.5, 8, coal, true)
	b.box(-50.0, 50.0, 0.0, 2.2, -24.6, -24.0, soot.lightened(0.04))
	b.box(-50.6, -50.0, 0.0, 2.2, -24.6, 52.0, soot.lightened(0.04))
	b.box(50.0, 50.6, 0.0, 2.2, -24.6, 52.0, soot.lightened(0.04))
	var m: ArrayMesh = b.commit(paint_material())
	_cache["gasworks"] = m
	return m


## Goods yard in the old layout (sidings along X): ballast bed, four sidings with rails and sleepers, covered vans,
## open coal wagons and tank wagons, a brick goods shed with a loading canopy at z = +34, a water tank on a brick
## tower, a coal stage, a yard crane and stacked sleepers.
static func goods_yard() -> ArrayMesh:
	if _cache.has("goods_yard"):
		return _cache["goods_yard"]
	var b := MB.new()
	var ballast := Color(0.34, 0.32, 0.29)
	var rail := Color(0.34, 0.30, 0.27)
	var sleeper := Color(0.20, 0.16, 0.12)
	var brick := Color(0.46, 0.28, 0.21)
	var slate := Color(0.27, 0.28, 0.31)
	var iron := Color(0.12, 0.12, 0.13)
	b.box(-105.0, 105.0, 0.0, 0.3, -22.0, 22.0, ballast, true)
	var wagon_cols: Array = [Color(0.32, 0.28, 0.22), Color(0.40, 0.22, 0.17), Color(0.30, 0.31, 0.32), Color(0.22, 0.24, 0.20)]
	for ti in 4:
		var tz: float = -15.0 + float(ti) * 10.0
		b.box(-100.0, 100.0, 0.3, 0.38, tz - 1.3, tz + 1.3, sleeper, true)
		for rz in [-0.72, 0.72]:
			b.box(-100.0, 100.0, 0.38, 0.56, tz + rz - 0.07, tz + rz + 0.07, rail, true)
		b.box(100.0, 101.2, 0.3, 1.6, tz - 1.2, tz + 1.2, sleeper.lightened(0.1), true)          # buffer stop
		for wi in 4:
			var wx: float = -72.0 + float(wi) * 44.0 + float((ti + wi) % 2) * 12.0
			var wc: Color = wagon_cols[(ti * 3 + wi) % 4]
			var kind: int = (ti + wi * 2) % 3
			b.box(wx - 4.6, wx + 4.6, 1.0, 1.3, tz - 1.25, tz + 1.25, iron, true)                 # underframe
			for ax in [-2.8, 2.8]:
				for sz in [-0.72, 0.72]:
					b.wheel(wx + ax, 0.95, tz + sz, 0.46, 0.14, 8, iron)
			if kind == 0:                                                                         # covered van
				b.box(wx - 4.4, wx + 4.4, 1.3, 3.6, tz - 1.3, tz + 1.3, wc, false)
				b.gable_x(wx - 4.4, wx + 4.4, tz - 1.3, tz + 1.3, 3.6, 0.45, 0.08, Color(0.18, 0.17, 0.16), wc, 0.1)
				b.box(wx - 0.9, wx + 0.9, 1.4, 3.4, tz + 1.3, tz + 1.36, wc.darkened(0.2), false)
			elif kind == 1:                                                                       # open coal wagon
				b.box(wx - 4.4, wx + 4.4, 1.3, 2.6, tz - 1.3, tz + 1.3, wc, false)
				b.prism(wx, tz, 2.3, 3.1, 4.0, 1.1, 1.6, 0.4, 8, Color(0.08, 0.08, 0.09), true)
			else:                                                                                 # tank wagon
				for s in 8:
					var a0: float = TAU * float(s) / 8.0
					var a1: float = TAU * float(s + 1) / 8.0
					var am: float = (a0 + a1) * 0.5
					b.face([Vector3(wx - 4.0, 2.45 + sin(a0) * 1.15, tz + cos(a0) * 1.15), Vector3(wx + 4.0, 2.45 + sin(a0) * 1.15, tz + cos(a0) * 1.15), Vector3(wx + 4.0, 2.45 + sin(a1) * 1.15, tz + cos(a1) * 1.15), Vector3(wx - 4.0, 2.45 + sin(a1) * 1.15, tz + cos(a1) * 1.15)], Color(0.14, 0.14, 0.15), Vector3(0.0, sin(am), cos(am)))
				b.wheel(wx - 4.0, 2.45, tz, 1.15, 0.05, 8, Color(0.14, 0.14, 0.15))
				b.wheel(wx + 4.0, 2.45, tz, 1.15, 0.05, 8, Color(0.14, 0.14, 0.15))
				b.box(wx - 0.4, wx + 0.4, 3.6, 4.0, tz - 0.4, tz + 0.4, iron, true)
	# goods shed with a loading canopy and platform, facing the yard
	b.box(-12.0, 52.0, 0.0, 9.0, 24.0, 44.0, brick, false)
	b.gable_x(-12.0, 52.0, 24.0, 44.0, 9.0, 5.0, 0.6, slate, brick, 0.5)
	b.box(-12.0, 52.0, 0.0, 1.3, 20.5, 24.0, Color(0.50, 0.48, 0.44), true)
	b.face([Vector3(-12.0, 6.4, 24.0), Vector3(52.0, 6.4, 24.0), Vector3(52.0, 5.6, 19.8), Vector3(-12.0, 5.6, 19.8)], slate.lightened(0.06), Vector3.UP)
	b.face([Vector3(-12.0, 6.3, 24.0), Vector3(52.0, 6.3, 24.0), Vector3(52.0, 5.5, 19.8), Vector3(-12.0, 5.5, 19.8)], Color(0.20, 0.18, 0.16), Vector3.DOWN)
	for d in 5:
		var dx: float = -6.0 + float(d) * 13.0
		b.box(dx - 2.2, dx + 2.2, 1.3, 5.2, 23.9, 24.0, Color(0.14, 0.12, 0.10), false)
		b.box(dx + 6.3, dx + 6.6, 1.3, 5.6, 20.0, 20.3, iron, false)
	# water tank on a brick tower, coal stage, yard crane, sleeper stacks
	b.box(-76.0, -64.0, 0.0, 6.0, 26.0, 34.0, brick, true)
	b.box(-76.6, -63.4, 6.0, 9.4, 25.4, 34.6, Color(0.26, 0.27, 0.29), true, Color(0.16, 0.20, 0.24))
	b.box(-58.0, -40.0, 0.0, 3.0, 25.0, 33.0, brick.darkened(0.15), true, Color(0.08, 0.08, 0.09))
	b.prism(-28.0, 30.0, 0.0, 5.5, 0.9, 0.9, 0.7, 0.7, 8, iron, true)
	b.beam(Vector3(-28.0, 5.2, 30.0), Vector3(-21.0, 9.5, 30.0), 0.3, 0.3, iron)
	for sk in 3:
		b.box(66.0 + float(sk) * 5.0, 69.6 + float(sk) * 5.0, 0.3, 1.6 + float(sk % 2) * 0.6, 27.0, 29.6, sleeper.lightened(0.05), true)
	var m: ArrayMesh = b.commit(paint_material())
	_cache["goods_yard"] = m
	return m


# ------------------------------------------------------------------ London: Big Ben and Tower Bridge

## The clock tower (at the origin) with the Houses of Parliament running off toward -X, in the old model's exaggerated
## scale: ribbed stone shaft, clock stage with four white dials, belfry, a two-stage slate spire with gilt finial;
## the palace as a long pinnacled range with a central spire and the square Victoria Tower at the far end.
static func big_ben() -> ArrayMesh:
	if _cache.has("big_ben"):
		return _cache["big_ben"]
	var b := MB.new()
	var stone := Color(0.68, 0.62, 0.48)
	var dress: Color = stone.lightened(0.10)
	var slate := Color(0.24, 0.25, 0.28)
	var dark := Color(0.13, 0.12, 0.12)
	var gold := Color(0.72, 0.60, 0.24)
	b.box(-7.0, 7.0, 0.0, 10.0, -7.0, 7.0, stone.darkened(0.06), true, slate)
	b.box(-5.5, 5.5, 10.0, 68.0, -5.5, 5.5, stone, false)
	# vertical ribs up each face and corner piers
	for f in 4:
		var ang: float = float(f) * PI * 0.5
		var dx: float = cos(ang)
		var dz: float = sin(ang)
		for off in [-3.0, -1.0, 1.0, 3.0]:
			if absf(dx) > 0.5:
				b.box(dx * 5.5 - 0.25, dx * 5.5 + 0.25, 10.0, 68.0, off - 0.3, off + 0.3, dress, false)
			else:
				b.box(off - 0.3, off + 0.3, 10.0, 68.0, dz * 5.5 - 0.25, dz * 5.5 + 0.25, dress, false)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			b.box(cx * 5.5 - 0.7, cx * 5.5 + 0.7, 0.0, 84.0, cz * 5.5 - 0.7, cz * 5.5 + 0.7, dress.darkened(0.04), false)
			b.prism(cx * 5.5, cz * 5.5, 84.0, 89.0, 0.9, 0.9, 0.0, 0.0, 4, gold.darkened(0.2), false, PI * 0.25)
	# clock stage: wider, with a dial on each face inside a dark surround
	b.box(-6.6, 6.6, 68.0, 82.0, -6.6, 6.6, stone.lightened(0.04), true, slate)
	b.box(-7.0, 7.0, 67.4, 68.0, -7.0, 7.0, dress)
	b.box(-7.0, 7.0, 82.0, 82.8, -7.0, 7.0, dress)
	for f2 in 4:
		var a2: float = float(f2) * PI * 0.5
		var ex: float = cos(a2)
		var ez: float = sin(a2)
		var ring: Array = []
		var ring2: Array = []
		for s in 12:
			var sa: float = TAU * float(s) / 12.0
			var u: float = cos(sa)
			var v: float = sin(sa)
			if absf(ex) > 0.5:
				ring.append(Vector3(ex * 6.72, 75.0 + v * 5.2, u * 5.2))
				ring2.append(Vector3(ex * 6.8, 75.0 + v * 4.5, u * 4.5))
			else:
				ring.append(Vector3(u * 5.2, 75.0 + v * 5.2, ez * 6.72))
				ring2.append(Vector3(u * 4.5, 75.0 + v * 4.5, ez * 6.8))
		b.face(ring, dark, Vector3(ex, 0.0, ez))
		b.face(ring2, Color(0.93, 0.91, 0.80), Vector3(ex, 0.0, ez))
	# belfry and the spire: lower pyramid, lantern with dormer lights, upper spire, finial
	b.box(-5.6, 5.6, 82.8, 87.0, -5.6, 5.6, stone, true, slate)
	b.hip_x(-6.0, 6.0, -6.0, 6.0, 87.0, 7.0, 3.0, 0.0, slate)
	b.box(-3.0, 3.0, 94.0, 97.5, -3.0, 3.0, slate.lightened(0.08), true)
	for f3 in 4:
		var a3: float = float(f3) * PI * 0.5
		b.box(cos(a3) * 3.0 - 0.6, cos(a3) * 3.0 + 0.6, 94.4, 96.8, sin(a3) * 3.0 - 0.6, sin(a3) * 3.0 + 0.6, gold.darkened(0.1), false)
	b.prism(0.0, 0.0, 97.5, 107.0, 3.4, 3.4, 0.0, 0.0, 4, slate, false, PI * 0.25)
	b.prism(0.0, 0.0, 106.4, 110.0, 0.22, 0.22, 0.06, 0.06, 4, gold, false)
	# the palace: river-front range with a pinnacled parapet, roof, central spire and the Victoria Tower
	b.box(-96.0, -8.0, 0.0, 16.0, -11.0, 11.0, stone, false)
	b.gable_x(-96.0, -8.0, -9.0, 9.0, 16.0, 6.0, 0.0, slate, stone, 0.0)
	b.box(-96.0, -8.0, 16.0, 17.2, -11.3, 11.3, dress, false)
	for i in 15:
		var px: float = -92.0 + float(i) * 5.9
		for sz in [-1.0, 1.0]:
			b.box(px - 0.5, px + 0.5, 0.0, 19.0, sz * 11.0 - 0.5, sz * 11.0 + 0.5, dress.darkened(0.03), false)
			b.prism(px, sz * 11.0, 19.0, 23.0, 0.7, 0.7, 0.0, 0.0, 4, slate, false, PI * 0.25)
	b.prism(-50.0, 0.0, 20.0, 34.0, 4.5, 4.5, 4.0, 4.0, 8, stone, false, PI / 8.0)
	b.prism(-50.0, 0.0, 34.0, 58.0, 4.4, 4.4, 0.0, 0.0, 8, slate, false, PI / 8.0)
	b.box(-112.0, -96.0, 0.0, 62.0, -8.0, 8.0, stone, true, slate)
	for sy in [20.0, 40.0, 58.0]:
		b.box(-112.4, -95.6, sy, sy + 0.8, -8.4, 8.4, dress)
	for cx2 in [-112.0, -96.0]:
		for cz2 in [-8.0, 8.0]:
			b.prism(cx2, cz2, 0.0, 66.0, 1.6, 1.6, 1.5, 1.5, 8, dress.darkened(0.04), false)
			b.prism(cx2, cz2, 66.0, 74.0, 1.8, 1.8, 0.0, 0.0, 8, slate, false)
	b.box(-104.1, -103.9, 62.0, 76.0, -0.1, 0.1, dark, false)
	var m: ArrayMesh = b.commit(paint_material())
	_cache["big_ben"] = m
	return m


## Tower Bridge in the old model's layout (towers at x = +/-40, deck at y = 28, river along Z): two stone towers on
## piers with corner turrets and slate roofs, twin high-level walkways, the bascule span with its two leaves a
## little raised, and suspension side spans on chains down to abutment towers.
static func tower_bridge() -> ArrayMesh:
	if _cache.has("tower_bridge"):
		return _cache["tower_bridge"]
	var b := MB.new()
	var stone := Color(0.58, 0.58, 0.56)
	var dress: Color = stone.lightened(0.10)
	var slate := Color(0.24, 0.25, 0.28)
	var steel := Color(0.30, 0.45, 0.62)
	var road := Color(0.22, 0.22, 0.24)
	var dark := Color(0.13, 0.12, 0.12)
	var deck: float = 28.0
	for sx in [-1.0, 1.0]:
		var tx: float = sx * 40.0
		# pier with cutwaters, tower shaft, bands, arch over the roadway, corner turrets and the roofs
		b.prism(tx, 0.0, -6.0, deck - 2.0, 11.0, 15.0, 10.0, 13.0, 12, stone.darkened(0.12), true)
		b.box(tx - 7.0, tx + 7.0, deck - 2.0, 60.0, -7.0, 7.0, stone, true, slate)
		for sy in [38.0, 48.0, 58.0]:
			b.box(tx - 7.3, tx + 7.3, sy, sy + 0.9, -7.3, 7.3, dress)
		b.box(tx - 7.1, tx + 7.1, deck + 0.6, deck + 9.0, -3.2, 3.2, dark, false)
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				b.prism(tx + cx * 7.0, cz * 7.0, deck - 2.0, 64.0, 2.0, 2.0, 1.9, 1.9, 8, dress.darkened(0.03), false)
				b.prism(tx + cx * 7.0, cz * 7.0, 64.0, 71.0, 2.2, 2.2, 0.0, 0.0, 8, slate, false)
		b.hip_x(tx - 6.6, tx + 6.6, -6.6, 6.6, 60.0, 11.0, 5.2, 0.0, slate)
		b.box(tx - 0.12, tx + 0.12, 71.0, 76.0, -0.12, 0.12, Color(0.72, 0.60, 0.24), false)
		# one bascule leaf, lifted a little toward mid-river, and the side span with its chain and hangers
		var x_in: float = sx * 33.0
		for sz in [-1.0, 1.0]:
			b.beam(Vector3(x_in, deck, sz * 5.6), Vector3(sx * 1.0, deck + 2.6, sz * 5.6), 0.9, 0.4, steel)
		b.face([Vector3(x_in, deck + 0.4, -5.2), Vector3(x_in, deck + 0.4, 5.2), Vector3(sx * 1.0, deck + 3.0, 5.2), Vector3(sx * 1.0, deck + 3.0, -5.2)], road, Vector3.UP)
		b.face([Vector3(x_in, deck - 0.4, -5.2), Vector3(x_in, deck - 0.4, 5.2), Vector3(sx * 1.0, deck + 2.2, 5.2), Vector3(sx * 1.0, deck + 2.2, -5.2)], steel.darkened(0.3), Vector3.DOWN)
		var x_out: float = sx * 47.0
		var x_ab: float = sx * 112.0
		b.box(minf(x_out, x_ab), maxf(x_out, x_ab), deck - 1.6, deck + 0.4, -6.0, 6.0, steel.darkened(0.2), true, road)
		var seg: int = 10
		for sz2 in [-6.0, 6.0]:
			var prev := Vector3(x_out, 56.0, sz2)
			for i in range(1, seg + 1):
				var t: float = float(i) / float(seg)
				var cur := Vector3(lerpf(x_out, x_ab, t), lerpf(56.0, deck + 9.0, t) - 9.0 * sin(PI * t), sz2)
				b.beam(prev, cur, 0.7, 0.35, steel)
				if i < seg:
					b.beam(Vector3(cur.x, deck + 0.4, sz2), cur, 0.12, 0.12, steel.darkened(0.15))
				prev = cur
		# abutment tower and its landward approach
		b.box(minf(x_ab, x_ab + sx * 10.0), maxf(x_ab, x_ab + sx * 10.0), -4.0, deck + 14.0, -8.0, 8.0, stone, true, slate)
		b.box(minf(x_ab, x_ab + sx * 10.0) - 0.2, maxf(x_ab, x_ab + sx * 10.0) + 0.2, deck + 0.6, deck + 8.0, -3.2, 3.2, dark, false)
		b.hip_x(minf(x_ab, x_ab + sx * 10.0), maxf(x_ab, x_ab + sx * 10.0), -8.0, 8.0, deck + 14.0, 5.0, 4.0, 0.0, slate)
	# the two high-level walkways
	for wz in [-4.6, 4.6]:
		b.box(-33.0, 33.0, 45.0, 49.0, wz - 1.6, wz + 1.6, steel, true, steel.darkened(0.2))
		for k in 12:
			var kx: float = -30.0 + float(k) * 5.45
			b.box(kx - 0.2, kx + 0.2, 45.0, 49.0, wz - 1.7, wz + 1.7, steel.lightened(0.15), false)
	var m: ArrayMesh = b.commit(paint_material())
	_cache["tower_bridge"] = m
	return m
