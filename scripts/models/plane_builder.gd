class_name PlaneBuilder
extends RefCounted
## Data-driven procedural toon aircraft builder. See ModelSpecs for spec dictionaries.
## Output follows the AircraftModels contract (faces -Z; nodes Propeller, PropDisc, GearL/R,
## Canopy, MuzzleL/R, CockpitEye). Units: metres * spec.scale.

# [t along fuselage 0..1 (nose->tail), width frac, height frac, centre-y offset (x hh)]
const PROFILES := {
	"inline": [[0.0, 0.10, 0.09, 0.0], [0.015, 0.34, 0.31, 0.0], [0.035, 0.56, 0.52, 0.0], [0.06, 0.74, 0.70, 0.0], [0.10, 0.90, 0.86, 0.0], [0.17, 1.0, 0.95, 0.0], [0.33, 0.96, 1.0, 0.1], [0.5, 0.78, 0.85, 0.1], [0.7, 0.5, 0.6, 0.12], [0.88, 0.26, 0.38, 0.16], [1.0, 0.1, 0.2, 0.2]],
	"radial": [[0.0, 0.8, 0.8, 0.0], [0.05, 1.0, 1.0, 0.0], [0.2, 0.98, 1.0, 0.02], [0.4, 0.8, 0.9, 0.04], [0.6, 0.6, 0.72, 0.08], [0.8, 0.36, 0.5, 0.12], [0.93, 0.2, 0.3, 0.16], [1.0, 0.1, 0.18, 0.2]],
	"bomber": [[0.0, 0.10, 0.10, 0.0], [0.012, 0.34, 0.34, 0.0], [0.03, 0.52, 0.52, 0.0], [0.06, 0.72, 0.72, 0.0], [0.10, 0.86, 0.86, 0.0], [0.16, 0.94, 0.94, 0.0], [0.3, 1.0, 1.0, 0.0], [0.55, 0.88, 0.9, 0.04], [0.75, 0.56, 0.62, 0.1], [0.9, 0.28, 0.34, 0.14], [1.0, 0.1, 0.12, 0.16]],
}

const COL_DARK := Color(0.10, 0.10, 0.11)

static var _mat_cache: Dictionary = {}


static func _flat(color: Color) -> ShaderMaterial:
	var k: String = color.to_html()
	if not _mat_cache.has(k):
		_mat_cache[k] = ToonUtil.make_toon(color, {"outline": false, "rim": 0.0})
	return _mat_cache[k]


static func _box(sx: float, sy: float, sz: float) -> ArrayMesh:
	return MeshUtil.loft([MeshUtil.rect_xy(-sz * 0.5, sx * 0.5, sy * 0.5), MeshUtil.rect_xy(sz * 0.5, sx * 0.5, sy * 0.5)])


static func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, nm: String = "") -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	if nm != "":
		m.name = nm
	parent.add_child(m)
	return m


# ---------------------------------------------------------------- fuselage

static func fus_at(f: Dictionary, z: float) -> Array:
	## returns [half_w, half_h, cy] of the fuselage at z (linear interpolation of the profile)
	var rows: Array = PROFILES[f.get("profile", "inline")]
	var t: float = clampf(inverse_lerp(float(f["z0"]), float(f["z1"]), z), 0.0, 1.0)
	for i in range(rows.size() - 1):
		var a: Array = rows[i]
		var b: Array = rows[i + 1]
		if t >= float(a[0]) and t <= float(b[0]):
			var u: float = inverse_lerp(float(a[0]), float(b[0]), t)
			var hh: float = float(f["hh"])
			return [float(f["hw"]) * lerpf(float(a[1]), float(b[1]), u), hh * lerpf(float(a[2]), float(b[2]), u), float(f.get("cy", 0.0)) + hh * lerpf(float(a[3]), float(b[3]), u)]
	return [0.1, 0.1, 0.0]


static func _fuselage_mesh(f: Dictionary) -> ArrayMesh:
	var secs: Array = []
	for r in PROFILES[f.get("profile", "inline")]:
		var z: float = lerpf(float(f["z0"]), float(f["z1"]), float(r[0]))
		var d: Array = fus_at(f, z)
		secs.append(MeshUtil.ring_xy(z, d[0], d[1], d[2], 16))
	return MeshUtil.loft_smooth(secs, 4, 1)


static func _fus_slice(f: Dictionary, za: float, zb: float, grow: float = 1.03) -> ArrayMesh:
	var da: Array = fus_at(f, za)
	var db: Array = fus_at(f, zb)
	return MeshUtil.loft([
		MeshUtil.ring_xy(za, da[0] * grow + 0.01, da[1] * grow + 0.01, da[2], 10),
		MeshUtil.ring_xy(zb, db[0] * grow + 0.01, db[1] * grow + 0.01, db[2], 10)])


# ---------------------------------------------------------------- wings

static func wing_section(w: Dictionary, t: float) -> Dictionary:
	var cr: float = w["cr"]
	var ct: float = w["ct"]
	var chord: float = lerpf(cr, ct, t)
	if w.get("round_tip", true):
		chord = maxf(chord * sqrt(maxf(1.0 - pow(t, 4.0) * 0.85, 0.0)), 0.14)
	var zle: float = float(w["le_z"]) + float(w.get("sweep", 0.0)) * t
	var yc: float = float(w["y"]) + float(w.get("dihedral", 0.3)) * t
	var gull: float = float(w.get("gull", 0.0))
	if gull > 0.0:
		yc -= gull * (t / 0.35) if t < 0.35 else gull
		yc += 0.0 if t < 0.35 else (t - 0.35) / 0.65 * (gull * 1.8)
	return {"x": float(w.get("root_x", 0.4)) + float(w["half"]) * t, "yc": yc, "zle": zle, "chord": chord, "t": chord * float(w.get("thick", 0.13))}


## Inboard flap panels (pivots FlapL / FlapR: rotation.x > 0 lowers the trailing edge). The aircraft script drives them.
static func _add_flaps(body: Node3D, w: Dictionary, mat: Material) -> void:
	var a: Dictionary = wing_section(w, 0.10)
	var b: Dictionary = wing_section(w, 0.52)
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "FlapR" if side > 0.0 else "FlapL"
		var chord: float = (float(a["chord"]) + float(b["chord"])) * 0.5
		var zle: float = (float(a["zle"]) + float(b["zle"])) * 0.5
		var yc: float = (float(a["yc"]) + float(b["yc"])) * 0.5 - (float(a["t"]) + float(b["t"])) * 0.22
		pivot.position = Vector3(side * (float(a["x"]) + float(b["x"])) * 0.5, yc, zle + chord * 0.72)
		body.add_child(pivot)
		var bm := BoxMesh.new()
		bm.size = Vector3(absf(float(b["x"]) - float(a["x"])), 0.05, chord * 0.30)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(0.0, 0.0, chord * 0.15)
		pivot.add_child(mi)


static func _wing_mesh(w: Dictionary, side: float) -> ArrayMesh:
	var secs: Array = []
	for t in [0.0, 0.12, 0.25, 0.35, 0.45, 0.55, 0.7, 0.8, 0.88, 0.94, 1.0]:
		var s: Dictionary = wing_section(w, t)
		secs.append(MeshUtil.airfoil(side * s["x"], s["yc"], s["zle"], s["chord"], s["t"]))
	if float(w.get("gull", 0.0)) > 0.0:
		# non-convex (gull) wings: loft segment by segment so the winding test uses a local centroid
		var out := ArrayMesh.new()
		for i in range(secs.size() - 1):
			var seg: ArrayMesh = MeshUtil.loft([secs[i], secs[i + 1]], i == 0, i == secs.size() - 2)
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, seg.surface_get_arrays(0))
		return out
	return MeshUtil.loft_smooth(secs, 2, 1)


static func _tailplane_mesh(tp: Dictionary, side: float) -> ArrayMesh:
	var secs: Array = []
	for t in [0.0, 0.35, 0.7, 1.0]:
		var chord: float = lerpf(float(tp["cr"]), float(tp["ct"]), t)
		secs.append(MeshUtil.airfoil(side * (0.15 + float(tp["span"]) * t), float(tp["y"]) + 0.1 * t, float(tp["z"]) + 0.5 * t, chord, 0.1 * chord * (1.0 - 0.5 * t)))
	return MeshUtil.loft_smooth(secs, 2, 1)


static func _fin_mesh(fn: Dictionary, x: float) -> ArrayMesh:
	var secs: Array = []
	for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var chord: float = lerpf(float(fn["cr"]), float(fn["ct"]), t)
		var zle: float = float(fn["z"]) + float(fn.get("sweep", 0.9)) * t
		var y: float = float(fn["y"]) + float(fn["h"]) * t
		var w: float = 0.09 * (1.0 - 0.5 * t) * maxf(1.0, float(fn["cr"]) * 0.5)
		secs.append(PackedVector3Array([
			Vector3(x, y, zle), Vector3(x + w, y, zle + chord * 0.3), Vector3(x + w * 0.6, y, zle + chord * 0.8),
			Vector3(x, y, zle + chord), Vector3(x - w * 0.6, y, zle + chord * 0.8), Vector3(x - w, y, zle + chord * 0.3)]))
	return MeshUtil.loft(secs)


# ---------------------------------------------------------------- engines / props

static func _nacelle_mesh(z0: float, z1: float, r: float, jet: bool) -> ArrayMesh:
	var prof: Array = [[0.0, 0.65], [0.07, 0.95], [0.2, 1.0], [0.6, 0.9], [0.85, 0.55], [1.0, 0.12]]
	if jet:
		prof = [[0.0, 0.8], [0.08, 1.0], [0.5, 1.0], [0.9, 0.72], [1.0, 0.5]]
	var secs: Array = []
	for p in prof:
		var z: float = lerpf(z0, z1, float(p[0]))
		secs.append(MeshUtil.ring_xy(z, r * float(p[1]), r * float(p[1]) * 0.95, 0.0, 10))
	return MeshUtil.loft_smooth(secs, 3, 1)


static func _make_prop(radius: float, blades: int, spinner_r: float, tip: Color, primary: bool, idx: int) -> Node3D:
	var prop: Node3D
	if primary:
		prop = Node3D.new()
		prop.name = "Propeller"
	else:
		var ps := PropSpinner.new()
		prop = ps
		prop.name = "Propeller%d" % idx
	var k: float = spinner_r / 0.3
	var sp_secs: Array = [
		MeshUtil.ring_xy(-0.7 * k, 0.02, 0.02, 0.0, 8), MeshUtil.ring_xy(-0.5 * k, 0.17 * k, 0.17 * k, 0.0, 8),
		MeshUtil.ring_xy(-0.1 * k, spinner_r, spinner_r, 0.0, 8), MeshUtil.ring_xy(0.1 * k, spinner_r, spinner_r, 0.0, 8)]
	_mi(prop, MeshUtil.loft(sp_secs), ToonUtil.make_toon(Color(0.12, 0.12, 0.13), {"outline_thickness": 0.012}))
	var blade_mat := ToonUtil.make_toon(Color(0.07, 0.07, 0.07), {"outline": false})
	var rs: float = radius / 1.75
	# The blades hang off one node so a fast-spinning prop can swap them for the PropDisc blur (see
	# AircraftModels.prop_blur): blades sampled a few times per turn strobe, which reads as the aircraft
	# shaking, worst in the cockpit view where the prop fills the screen.
	var blades_root := Node3D.new()
	blades_root.name = "Blades"
	prop.add_child(blades_root)
	for i in blades:
		var pivot := Node3D.new()
		pivot.rotation.z = TAU * float(i) / float(blades)
		blades_root.add_child(pivot)
		var bsecs: Array = [
			PackedVector3Array([Vector3(-0.09, 0.2, -0.04), Vector3(0.09, 0.2, 0.04), Vector3(0.09, 0.2, 0.0), Vector3(-0.09, 0.2, 0.0)]),
			PackedVector3Array([Vector3(-0.15, 1.1 * rs, -0.06), Vector3(0.15, 1.1 * rs, 0.06), Vector3(0.15, 1.1 * rs, 0.0), Vector3(-0.15, 1.1 * rs, 0.0)]),
			PackedVector3Array([Vector3(-0.08, radius, -0.03), Vector3(0.08, radius, 0.03), Vector3(0.08, radius, 0.0), Vector3(-0.08, radius, 0.0)])]
		_mi(pivot, MeshUtil.loft(bsecs), blade_mat)
		_mi(pivot, _box(0.17, 0.25, 0.07), _flat(tip), Vector3(0, radius - 0.13, 0))
	var disc := MeshInstance3D.new()
	disc.name = "PropDisc" if primary else "PropDisc%d" % idx
	var dm := CylinderMesh.new()
	dm.top_radius = radius
	dm.bottom_radius = radius
	dm.height = 0.02
	dm.radial_segments = 120
	disc.mesh = dm
	disc.rotation.x = deg_to_rad(90.0)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.15, 0.15, 0.15, 0.30)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc.material_override = dmat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.visible = not primary
	prop.add_child(disc)
	return prop


# ---------------------------------------------------------------- markings

static func _disc_z(parent: Node3D, r: float, col: Color, zoff: float) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.02
	cm.radial_segments = 20
	cm.rings = 1
	var mi := _mi(parent, cm, _flat(col), Vector3(0, 0, zoff))
	mi.rotation.x = deg_to_rad(90.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _star_mesh(r: float) -> ArrayMesh:
	var pts: Array = []
	for i in 10:
		var a: float = PI * 0.5 + TAU * float(i) / 10.0
		var rr: float = r if i % 2 == 0 else r * 0.4
		pts.append(Vector3(cos(a) * rr, sin(a) * rr, 0.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 10:
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[(i + 1) % 10]
		st.set_normal(Vector3.BACK)
		st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.BACK)
		st.add_vertex(p1)
		st.set_normal(Vector3.BACK)
		st.add_vertex(p2)
		st.set_normal(Vector3.FORWARD)
		st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.FORWARD)
		st.add_vertex(p2)
		st.set_normal(Vector3.FORWARD)
		st.add_vertex(p1)
	return st.commit()


## Flat national marking node facing `normal`. kind: "roundel" | "star" | "cross".
static func marking(parent: Node3D, nation: String, pos: Vector3, normal: Vector3, size: float, fuselage: bool, tilt: float = 0.0, pitch: float = 0.0) -> void:
	var m := Node3D.new()
	m.name = "DecalFus" if fuselage else "DecalWing"
	m.position = pos
	var up: Vector3 = Vector3.FORWARD if absf(normal.y) > 0.9 else Vector3.UP
	m.basis = Basis(Vector3(1, 0, 0), pitch) * Basis(Vector3(0, 0, 1), tilt) * Basis.looking_at(-normal, up)
	parent.add_child(m)
	match nation:
		"Luftwaffe":
			var white := Color(0.93, 0.93, 0.93)
			var black := Color(0.05, 0.05, 0.05)
			_mi(m, _box(size * 1.25, size * 0.45, 0.02), _flat(white), Vector3(0, 0, 0.0))
			_mi(m, _box(size * 0.45, size * 1.25, 0.02), _flat(white), Vector3(0, 0, 0.004))
			_mi(m, _box(size * 1.1, size * 0.3, 0.02), _flat(black), Vector3(0, 0, 0.012))
			_mi(m, _box(size * 0.3, size * 1.1, 0.02), _flat(black), Vector3(0, 0, 0.016))
		"USAAF":
			var blue := Color(0.08, 0.14, 0.45)
			var white2 := Color(0.95, 0.95, 0.95)
			_disc_z(m, size, blue, 0.0)
			var sm := _mi(m, _star_mesh(size * 0.85), _flat(white2), Vector3(0, 0, 0.02))
			sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for s in [-1.0, 1.0]:
				_mi(m, _box(size * 0.7, size * 0.36, 0.02), _flat(white2), Vector3(s * size * 1.55, 0, 0.0))
				_mi(m, _box(size * 0.7, size * 0.14, 0.02), _flat(blue), Vector3(s * size * 1.55, 0, 0.008))
		_:
			if fuselage:
				_disc_z(m, size, Color(0.95, 0.8, 0.1), 0.0)
				_disc_z(m, size * 0.8, Color(0.08, 0.14, 0.5), 0.012)
				_disc_z(m, size * 0.52, Color(0.95, 0.95, 0.95), 0.024)
				_disc_z(m, size * 0.26, Color(0.8, 0.1, 0.1), 0.036)
			else:
				_disc_z(m, size, Color(0.08, 0.14, 0.5), 0.0)
				_disc_z(m, size * 0.66, Color(0.95, 0.95, 0.95), 0.012)
				_disc_z(m, size * 0.34, Color(0.8, 0.1, 0.1), 0.024)


# ---------------------------------------------------------------- main build

static func gear_height(spec: Dictionary) -> float:
	var g: Dictionary = spec["gear"]
	return (-float(g["y"]) + float(g["len"]) + 0.02 + float(g["r"])) * float(spec.get("scale", 1.1))


## Dark cockpit framing over a glazing loft: a hoop rib at every canopy section plus a spine along the top.
## `rings` is a list of [z, half_w, half_h, cy] sections (the same ones lofted for the glass).
static func canopy_frame(parent: Node3D, rings: Array, mat: Material) -> void:
	for r in rings:
		var hw: float = float(r[1]) * 1.04 + 0.008
		var hh: float = float(r[2]) * 1.04 + 0.008
		var band: ArrayMesh = MeshUtil.loft([
			MeshUtil.ring_xy(float(r[0]) - 0.016, hw, hh, float(r[3]), 12),
			MeshUtil.ring_xy(float(r[0]) + 0.016, hw, hh, float(r[3]), 12)], false, false)
		_mi(parent, band, mat)
	var spine: Array = []
	for r2 in rings:
		spine.append(MeshUtil.rect_xy(float(r2[0]), 0.028, 0.016, float(r2[3]) + float(r2[2]) + 0.004))
	_mi(parent, MeshUtil.loft(spine), mat)


## A helmeted pilot head and shoulders just under the eye point, parented to the canopy group so the head shows
## through the glazing from outside and is hidden with the canopy in cockpit view.
static func pilot(canopy: Node3D, eye: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Pilot"
	canopy.add_child(root)
	var skin: Material = ToonUtil.make_toon(Color(0.78, 0.60, 0.48), {"outline": false, "rim": 0.0})
	var helmet: Material = ToonUtil.make_toon(Color(0.32, 0.28, 0.20), {"outline": false, "rim": 0.0})
	var kit: Material = ToonUtil.make_toon(Color(0.30, 0.32, 0.26), {"outline": false, "rim": 0.0})
	var dark: Material = ToonUtil.make_toon(Color(0.09, 0.09, 0.10), {"outline": false, "rim": 0.0, "gloss": 0.6})
	var base: Vector3 = eye - Vector3(0.0, 0.13, 0.0)
	var hs := SphereMesh.new()
	hs.radius = 0.10
	hs.height = 0.20
	hs.radial_segments = 10
	hs.rings = 5
	_mi(root, hs, skin, base)
	var hm := SphereMesh.new()
	hm.radius = 0.112
	hm.height = 0.224
	hm.radial_segments = 10
	hm.rings = 4
	var hmi := _mi(root, hm, helmet, base + Vector3(0.0, 0.015, 0.0))
	hmi.scale = Vector3(1.0, 0.9, 1.0)
	_mi(root, _box(0.17, 0.045, 0.06), dark, base + Vector3(0.0, 0.015, -0.09))
	_mi(root, _box(0.30, 0.14, 0.20), kit, base + Vector3(0.0, -0.20, 0.02))
	for c in root.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------- skin markings

## Fuselage stations [[z, half_w, half_h, cy], ...] so a marking can be laid on the actual skin curve.
static func stations(f: Dictionary, n: int = 40) -> Array:
	var out: Array = []
	for i in n:
		var z: float = lerpf(float(f["z0"]), float(f["z1"]), float(i) / float(n - 1))
		var d: Array = fus_at(f, z)
		out.append([z, float(d[0]), float(d[1]), float(d[2])])
	return out


static func station_at(st: Array, z: float) -> Array:
	var last: Array = st[st.size() - 1]
	if z <= float(st[0][0]):
		return [float(st[0][1]), float(st[0][2]), float(st[0][3])]
	if z >= float(last[0]):
		return [float(last[1]), float(last[2]), float(last[3])]
	for i in range(st.size() - 1):
		var a: Array = st[i]
		var b: Array = st[i + 1]
		if z >= float(a[0]) and z <= float(b[0]):
			var u: float = inverse_lerp(float(a[0]), float(b[0]), z)
			return [lerpf(float(a[1]), float(b[1]), u), lerpf(float(a[2]), float(b[2]), u), lerpf(float(a[3]), float(b[3]), u)]
	return [float(last[1]), float(last[2]), float(last[3])]


## Point on the elliptical fuselage skin at station z and height offset dy, pushed `off` proud of the curve.
static func skin_point(st: Array, z: float, dy: float, side: float, off: float) -> Vector3:
	var d: Array = station_at(st, z)
	var hw: float = float(d[0])
	var hh: float = maxf(float(d[1]), 0.0001)
	var cy: float = float(d[2])
	var t: float = clampf(dy / hh, -0.999, 0.999)
	return Vector3(side * (hw * sqrt(maxf(1.0 - t * t, 0.0)) + off), cy + dy, z)


## Roundel laid on the fuselage skin: each layer is a fan of triangles whose vertices follow the curve, so the
## marking hugs the skin instead of floating off the edges or sinking through the middle.
## layers: [[radius fraction, colour], ...] painted outward in order.
static func skin_roundel(parent: Node3D, st: Array, mz: float, side: float, size: float, layers: Array) -> void:
	var segs: int = 24
	for li in layers.size():
		var r: float = size * float(layers[li][0])
		var off: float = 0.012 + 0.009 * float(li)
		var stt := SurfaceTool.new()
		stt.begin(Mesh.PRIMITIVE_TRIANGLES)
		stt.set_normal(Vector3(side, 0.0, 0.0))
		var c: Vector3 = skin_point(st, mz, 0.0, side, off)
		for i in segs:
			var a0: float = TAU * float(i) / float(segs)
			var a1: float = TAU * float(i + 1) / float(segs)
			var p0: Vector3 = skin_point(st, mz + cos(a0) * r, sin(a0) * r, side, off)
			var p1: Vector3 = skin_point(st, mz + cos(a1) * r, sin(a1) * r, side, off)
			stt.add_vertex(c)
			stt.add_vertex(p0)
			stt.add_vertex(p1)
			stt.add_vertex(c)          # both windings, so the fan shows whichever way it is viewed
			stt.add_vertex(p1)
			stt.add_vertex(c)
		var mi := _mi(parent, stt.commit(), _flat(layers[li][1]), Vector3.ZERO)
		mi.name = "DecalFus"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Flat shapes (rect / disc / star, in u = along the fuselage, v = up) laid on the skin: every vertex is projected
## onto the fuselage curve so the marking hugs it. Rects are gridded so they bend with the skin.
static func skin_shapes(parent: Node3D, st: Array, mz: float, side: float, off: float, color: Color, shapes: Array, nm: String = "DecalFus") -> void:
	var stt := SurfaceTool.new()
	stt.begin(Mesh.PRIMITIVE_TRIANGLES)
	stt.set_normal(Vector3(side, 0.0, 0.0))
	for sh in shapes:
		var kind: String = sh[0]
		var tris: Array = []   # each [Vector2, Vector2, Vector2] in (u, v)
		if kind == "rect":
			var cu: float = sh[1]
			var cv: float = sh[2]
			var hu: float = sh[3]
			var hv: float = sh[4]
			var nu: int = 6
			var nv: int = 4
			for iu in nu:
				for iv in nv:
					var u0: float = cu - hu + 2.0 * hu * float(iu) / float(nu)
					var u1: float = cu - hu + 2.0 * hu * float(iu + 1) / float(nu)
					var v0: float = cv - hv + 2.0 * hv * float(iv) / float(nv)
					var v1: float = cv - hv + 2.0 * hv * float(iv + 1) / float(nv)
					tris.append([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1)])
					tris.append([Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1)])
		else:
			var pts: Array = []
			var r: float = sh[1]
			if kind == "disc":
				for i in 24:
					var a: float = TAU * float(i) / 24.0
					pts.append(Vector2(cos(a), sin(a)) * r)
			else:   # star, one point up
				for i in 10:
					var a2: float = PI * 0.5 + TAU * float(i) / 10.0
					pts.append(Vector2(cos(a2), sin(a2)) * r * (1.0 if i % 2 == 0 else 0.4))
			for i in pts.size():
				tris.append([Vector2.ZERO, pts[i], pts[(i + 1) % pts.size()]])
		for tr in tris:
			for k in 3:
				var q: Vector2 = tr[k]
				stt.add_vertex(skin_point(st, mz + q.x, q.y, side, off))
			for k in [0, 2, 1]:      # reverse winding too, so it shows from either side
				var q2: Vector2 = tr[k]
				stt.add_vertex(skin_point(st, mz + q2.x, q2.y, side, off))
	var mi := _mi(parent, stt.commit(), _flat(color), Vector3.ZERO)
	mi.name = nm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Fuselage national marking (Luftwaffe cross, USAAF star and bars) conformed to the skin.
static func skin_marking(parent: Node3D, st: Array, nation: String, mz: float, side: float, size: float) -> void:
	if nation == "Luftwaffe":
		var r: float = size
		skin_shapes(parent, st, mz, side, 0.012, Color(0.93, 0.93, 0.93), [["rect", 0.0, 0.0, r * 0.62, r * 0.225], ["rect", 0.0, 0.0, r * 0.225, r * 0.62]])
		skin_shapes(parent, st, mz, side, 0.02, Color(0.05, 0.05, 0.05), [["rect", 0.0, 0.0, r * 0.55, r * 0.15], ["rect", 0.0, 0.0, r * 0.15, r * 0.55]])
	else:
		skin_shapes(parent, st, mz, side, 0.012, Color(0.08, 0.14, 0.45), [["disc", size]])
		skin_shapes(parent, st, mz, side, 0.02, Color(0.95, 0.95, 0.95), [["star", size * 0.85], ["rect", size * 1.55, 0.0, size * 0.35, size * 0.18], ["rect", -size * 1.55, 0.0, size * 0.35, size * 0.18]])
		skin_shapes(parent, st, mz, side, 0.028, Color(0.08, 0.14, 0.45), [["rect", size * 1.55, 0.0, size * 0.35, size * 0.07], ["rect", -size * 1.55, 0.0, size * 0.35, size * 0.07]])


## RAF fin flash lofted along the real fin skin (follows sweep, taper and thickness).
static func fin_flash(parent: Node3D, fn: Dictionary, x: float) -> void:
	var cols: Array = [Color(0.1, 0.17, 0.5), Color(0.95, 0.95, 0.95), Color(0.8, 0.1, 0.1)]
	var fr: Array = [0.34, 0.47, 0.60, 0.73]
	for i in 3:
		for sx in [-1.0, 1.0]:
			var secs: Array = []
			for t in [0.25, 0.5, 0.75]:
				var chord: float = lerpf(float(fn["cr"]), float(fn["ct"]), t)
				var zle: float = float(fn["z"]) + float(fn.get("sweep", 0.9)) * t
				var y: float = float(fn["y"]) + float(fn["h"]) * t
				var w: float = 0.09 * (1.0 - 0.5 * t) * maxf(1.0, float(fn["cr"]) * 0.5)
				var ring := PackedVector3Array()
				for f in [fr[i], fr[i + 1]]:
					ring.append(Vector3(x + sx * (_fin_half(w, f) + 0.004), y, zle + chord * f))
				for f in [fr[i + 1], fr[i]]:
					ring.append(Vector3(x + sx * (_fin_half(w, f) - 0.012), y, zle + chord * f))
				secs.append(ring)
			var mi := _mi(parent, MeshUtil.loft(secs), _flat(cols[i]))
			mi.name = "DecalFin"
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Luftwaffe fin emblem: a black Hakenkreuz on a white disc, flat on both faces of the fin (twin fins: each one).
## Sits on the fin skin at mid-span, mid-chord, the same way fin_flash does for the RAF.
static func fin_swastika(parent: Node3D, fn: Dictionary, x: float) -> void:
	var t: float = 0.5
	var chord: float = lerpf(float(fn["cr"]), float(fn["ct"]), t)
	var zle: float = float(fn["z"]) + float(fn.get("sweep", 0.9)) * t
	var yc: float = float(fn["y"]) + float(fn["h"]) * t
	var zc: float = zle + chord * 0.5
	var w: float = 0.09 * (1.0 - 0.5 * t) * maxf(1.0, float(fn["cr"]) * 0.5)
	var half: float = _fin_half(w, 0.5)
	var r: float = minf(chord * 0.24, float(fn["h"]) * 0.16)
	var white := Color(0.93, 0.93, 0.93)
	var black := Color(0.05, 0.05, 0.05)
	for sx in [-1.0, 1.0]:
		_fin_plane(parent, x + sx * (half + 0.006), sx, _disc_tris(Vector2(zc, yc), r), white, "DecalFinDisc")
		_fin_plane(parent, x + sx * (half + 0.012), sx, _swastika_tris(Vector2(zc, yc), r), black, "DecalFinSwastika")


## Triangle fan for a disc (2D, in z/y).
static func _disc_tris(c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = 24
	for i in n:
		var a0: float = TAU * float(i) / float(n)
		var a1: float = TAU * float(i + 1) / float(n)
		out.append(c)
		out.append(c + Vector2(cos(a0), sin(a0)) * r)
		out.append(c + Vector2(cos(a1), sin(a1)) * r)
	return out


## Hakenkreuz as four L-shaped arms (each an arm plus a hook turning clockwise), built from rectangles.
static func _swastika_tris(c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var wd: float = 0.26 * r        # bar width
	var arm: float = 0.72 * r       # reach from the centre to the end of the arm
	var hook: float = 0.5 * r       # length of the hook
	var rects: Array = [
		[-wd * 0.5, -wd * 0.5, arm, wd * 0.5],          # the arm
		[arm - wd, -hook, arm, wd * 0.5],               # the hook turning down
	]
	for k in 4:
		for rc in rects:
			var pts: Array = [Vector2(rc[0], rc[1]), Vector2(rc[2], rc[1]), Vector2(rc[2], rc[3]), Vector2(rc[0], rc[3])]
			var q: Array = []
			for pt in pts:
				var v: Vector2 = pt as Vector2
				for _i in k:
					v = Vector2(-v.y, v.x)      # quarter turn
				q.append(c + v)
			out.append(q[0]); out.append(q[1]); out.append(q[2])
			out.append(q[0]); out.append(q[2]); out.append(q[3])
	return out


## Flat triangles on the plane x = face_x (normal sx), 2D points are (z, y). Both windings are emitted so the
## decal shows from either side of the fin without relying on culling.
static func _fin_plane(parent: Node3D, face_x: float, sx: float, tris: PackedVector2Array, col: Color, nm: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3(sx, 0.0, 0.0))
	var i: int = 0
	while i + 2 < tris.size():
		for idx in [i, i + 1, i + 2]:
			var p: Vector2 = tris[idx]
			st.add_vertex(Vector3(face_x, p.y, p.x))
		for idx in [i + 2, i + 1, i]:
			var p2: Vector2 = tris[idx]
			st.add_vertex(Vector3(face_x, p2.y, p2.x))
		i += 3
	var mi := _mi(parent, st.commit(), _flat(col), Vector3.ZERO, nm)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _fin_half(w: float, f: float) -> float:
	if f <= 0.3:
		return w * f / 0.3
	if f <= 0.8:
		return lerpf(w, w * 0.6, (f - 0.3) / 0.5)
	return w * 0.6 * (1.0 - f) / 0.2


## RAF fuselage roundel layers: yellow outer, blue, white, red centre.
static func raf_fuselage_layers() -> Array:
	return [[1.0, Color(0.95, 0.8, 0.1)], [0.8, Color(0.08, 0.14, 0.5)],
		[0.52, Color(0.95, 0.95, 0.95)], [0.26, Color(0.8, 0.1, 0.1)]]


static func build(spec: Dictionary, nation_override: String = "") -> Node3D:
	var sc: float = spec.get("scale", 1.1)
	var nation: String = nation_override if nation_override != "" else String(spec.get("nation", "RAF"))
	var model := Node3D.new()
	model.name = "Model"
	var body := Node3D.new()
	body.name = "Body"
	body.scale = Vector3.ONE * sc
	model.add_child(body)

	var col: Dictionary = spec["colors"]
	var ot: float = spec.get("outline", 0.014)
	var camo := ToonUtil.make_toon(col["top"], {"underside": col["under"], "patch": col["patch"], "patch_scale": 0.55, "outline_thickness": ot, "detail": 5, "gloss": 0.7})
	var dark := ToonUtil.make_toon(COL_DARK, {"outline_thickness": 0.012})
	var f: Dictionary = spec["fus"]
	var w: Dictionary = spec["wing"]

	_mi(body, _fuselage_mesh(f), camo, Vector3.ZERO, "Fuselage")
	for side in [-1.0, 1.0]:
		_mi(body, _wing_mesh(w, side), camo, Vector3.ZERO, "WingR" if side > 0.0 else "WingL")

	_add_flaps(body, w, camo)

	# Tail
	var tp: Dictionary = spec["tail"]
	for side in [-1.0, 1.0]:
		_mi(body, _tailplane_mesh(tp, side), camo)
	var fin: Dictionary = spec["fin"]
	if fin.get("twin", false):
		for side in [-1.0, 1.0]:
			_mi(body, _fin_mesh(fin, side * float(fin["x"])), camo)
	else:
		_mi(body, _fin_mesh(fin, 0.0), camo, Vector3.ZERO, "Fin")

	# Canopies (grouped so the aircraft script can hide them in cockpit view). Transparent glazing
	# over a dark frame of hoop ribs and a top spine so the cockpit reads as framed glass.
	var canopy := Node3D.new()
	canopy.name = "Canopy"
	body.add_child(canopy)
	var glass := ToonUtil.make_glass({"opacity": 0.2, "rim": 0.9, "tint": Color(0.58, 0.70, 0.76)})
	for c in spec.get("canopies", []):
		var secs: Array = []
		for r in c:
			secs.append(MeshUtil.ring_xy(r[0], r[1], r[2], r[3], 12))
		var gmi := _mi(canopy, MeshUtil.loft_smooth(secs, 3, 1), glass)
		gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		canopy_frame(canopy, c, dark)
	pilot(canopy, spec["eye"] as Vector3)
	PlaneDetails.cockpit(canopy, spec["eye"] as Vector3, String((spec["fus"] as Dictionary).get("profile", "")) == "bomber")

	# Engines on wings / nacelles
	var prop_idx: int = 0
	var tip: Color = spec.get("prop_tip", Color(0.9, 0.75, 0.15))
	for e in spec.get("engines", []):
		var x: float = e["x"]
		var jet: bool = e.get("jet", false)
		_mi(body, _nacelle_mesh(e["z0"], e["z1"], e["r"], jet), camo, Vector3(x, e["y"], 0.0))
		if jet:
			var intake := _mi(body, CylinderMesh.new(), dark, Vector3(x, e["y"], float(e["z0"]) + 0.03))
			(intake.mesh as CylinderMesh).top_radius = float(e["r"]) * 0.62
			(intake.mesh as CylinderMesh).bottom_radius = float(e["r"]) * 0.62
			(intake.mesh as CylinderMesh).height = 0.1
			intake.rotation.x = deg_to_rad(90.0)
		else:
			var prop: Node3D = _make_prop(e["prop_r"], int(e.get("blades", 3)), float(e["r"]) * 0.32, tip, prop_idx == 0 and not spec.has("nose_prop"), prop_idx)
			prop.position = Vector3(x, e["y"], float(e["z0"]) - 0.08)
			body.add_child(prop)
			prop_idx += 1
	if spec.has("nose_prop"):
		var n: Dictionary = spec["nose_prop"]
		var np: Node3D = _make_prop(n["r"], int(n.get("blades", 3)), float(n.get("spinner", 0.3)), tip, true, 0)
		np.position = Vector3(0, float(n.get("y", 0.0)), n["z"])
		body.add_child(np)

	# Extras
	for ex in spec.get("extras", []):
		var c2: Color = _color_of(ex.get("col", "dark"), col)
		var mat: Material = dark if ex.get("col", "dark") is String and ex.get("col", "dark") == "dark" else _flat(c2)
		if ex.get("col", "") is String and ex["col"] in ["top", "under"]:
			mat = camo
		match ex["t"]:
			"box":
				_mi(body, _box(ex["size"].x, ex["size"].y, ex["size"].z), mat, ex["pos"])
			"sphere":
				var sm := SphereMesh.new()
				sm.radius = ex["size"].x
				sm.height = ex["size"].x * 2.0
				sm.radial_segments = 8
				sm.rings = 4
				_mi(body, sm, mat, ex["pos"])
			"slice":
				_mi(body, _fus_slice(f, ex["z0"], ex["z1"]), mat)

	# Navigation lights: red to port, green to starboard at the wingtips (visible at dusk / night)
	var wtip: Dictionary = wing_section(w, 1.0)
	for side in [-1.0, 1.0]:
		var lc: Color = Color(0.9, 0.12, 0.12) if side < 0.0 else Color(0.15, 0.9, 0.3)
		var lm := SphereMesh.new()
		lm.radius = 0.07
		lm.height = 0.14
		lm.radial_segments = 6
		lm.rings = 3
		_mi(body, lm, ToonUtil.make_toon(lc, {"outline": false, "rim": 0.0, "emission": lc, "emission_energy": 1.1}), Vector3(side * float(wtip["x"]), float(wtip["yc"]), float(wtip["zle"]) + float(wtip["chord"]) * 0.5))

	# Exhaust stacks down the nose of inline (liquid-cooled) engines
	if spec.has("nose_prop") and String(f.get("profile", "inline")) == "inline":
		for side in [-1.0, 1.0]:
			for k in 4:
				var ez: float = float(f["z0"]) + 0.6 + 0.3 * float(k)
				var ed: Array = fus_at(f, ez)
				_mi(body, _box(0.09, 0.09, 0.18), dark, Vector3(side * float(ed[0]) * 0.98, float(ed[2]) + float(ed[1]) * 0.35, ez))

	# Landing gear
	var g: Dictionary = spec["gear"]
	var leg_w: float = g.get("leg_w", 0.14)
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "GearR" if side > 0.0 else "GearL"
		pivot.position = Vector3(side * float(g["x"]), g["y"], g["z"])
		body.add_child(pivot)
		_mi(pivot, _box(leg_w, g["len"], leg_w + 0.02), dark, Vector3(0, -float(g["len"]) * 0.5, 0))
		var wheel := _mi(pivot, MeshUtil.disc(g["r"], 0.14 + float(g["r"]) * 0.3, Vector3.RIGHT, 12), dark, Vector3(0, -float(g["len"]) - 0.02, 0))
		wheel.name = "Wheel"
	if spec.has("tail_wheel"):
		var tw: Array = spec["tail_wheel"]
		var twm: MeshInstance3D = _mi(body, MeshUtil.disc(0.14, 0.09, Vector3.RIGHT, 8), dark, Vector3(0, tw[0], tw[1]))
		twm.name = "TailWheel"

	_fit_details(body, spec)

	# Markings
	var mz: float = spec["mark_z"]
	var fd: Array = fus_at(f, mz)
	var msz: float = minf(float(spec.get("mark_size", 0.55)), minf(float(fd[0]), float(fd[1])) * 0.85)
	if nation == "RAF":
		var st: Array = stations(f)          # roundels follow the fuselage curve instead of floating flat
		skin_roundel(body, st, mz, 1.0, msz, raf_fuselage_layers())
		skin_roundel(body, st, mz, -1.0, msz, raf_fuselage_layers())
	else:
		var st2: Array = stations(f)
		skin_marking(body, st2, nation, mz, 1.0, msz)
		skin_marking(body, st2, nation, mz, -1.0, msz)
	var ws: Dictionary = wing_section(w, spec.get("mark_t", 0.55))
	# The airfoil (MeshUtil.airfoil) rises to 0.6 t at 25% chord then falls in a straight line to 0.35 t at 70%:
	# lay the marking on that flat slope (centre 47.5% chord, kept inside it) and pitch it to match, so it sits flush.
	var top_y: float = float(ws["yc"]) + float(ws["t"]) * 0.475 + 0.006
	var bot_y: float = float(ws["yc"]) - float(ws["t"]) * 0.36 - 0.006
	var wz: float = float(ws["zle"]) + float(ws["chord"]) * 0.475
	var wsz: float = minf(float(spec.get("wing_mark_size", 0.7)), float(ws["chord"]) * 0.21)
	var slope_top: float = atan(0.25 * float(ws["t"]) / (0.45 * float(ws["chord"])))
	var slope_bot: float = atan(0.25 * float(ws["t"]) / (0.40 * float(ws["chord"])))
	var wa: Dictionary = wing_section(w, maxf(spec.get("mark_t", 0.55) - 0.08, 0.0))
	var wb: Dictionary = wing_section(w, minf(spec.get("mark_t", 0.55) + 0.08, 1.0))
	var wtilt: float = atan2(float(wb["yc"]) - float(wa["yc"]), maxf(absf(float(wb["x"]) - float(wa["x"])), 0.001))
	for side in [-1.0, 1.0]:
		marking(body, nation, Vector3(side * float(ws["x"]), top_y, wz), Vector3.UP, wsz, false, side * wtilt, slope_top)
		if nation == "Luftwaffe":
			marking(body, nation, Vector3(side * float(ws["x"]), bot_y, wz), Vector3.DOWN, wsz, false, side * wtilt, slope_bot)
	if nation == "RAF":
		# fin flash lofted along the fin skin
		if fin.get("twin", false):
			fin_flash(body, fin, -float(fin["x"]))
			fin_flash(body, fin, float(fin["x"]))
		else:
			fin_flash(body, fin, 0.0)
	elif nation == "Luftwaffe":
		# Hakenkreuz on the fin, in the same place as the RAF flash
		if fin.get("twin", false):
			fin_swastika(body, fin, -float(fin["x"]))
			fin_swastika(body, fin, float(fin["x"]))
		else:
			fin_swastika(body, fin, 0.0)

	# D-Day invasion stripes
	if spec.get("stripes", false):
		var zs: float = float(f["z1"]) - (float(f["z1"]) - float(f["z0"])) * 0.36
		for i in 5:
			var cs: Color = Color(0.95, 0.95, 0.95) if i % 2 == 0 else Color(0.05, 0.05, 0.05)
			_mi(body, _fus_slice(f, zs + 0.34 * float(i), zs + 0.34 * float(i + 1)), _flat(cs))
		for side in [-1.0, 1.0]:
			var sa: Dictionary = wing_section(w, 0.25)
			var sb: Dictionary = wing_section(w, 0.7)
			var xs: float = (float(sa["x"]) + float(sb["x"])) * 0.5
			var chm: float = (float(sa["chord"]) + float(sb["chord"])) * 0.5
			var zm: float = (float(sa["zle"]) + float(sb["zle"])) * 0.5
			var ym: float = (float(sa["yc"]) + float(sb["yc"])) * 0.5
			var tm: float = (float(sa["t"]) + float(sb["t"])) * 0.5
			var dx: float = absf(float(sb["x"]) - float(sa["x"]))
			var bw: float = dx / 5.0
			for i in 5:
				var cs2: Color = Color(0.95, 0.95, 0.95) if i % 2 == 0 else Color(0.05, 0.05, 0.05)
				var xb: float = (float(sa["x"]) + float(sb["x"]) - dx) * 0.5 + bw * (float(i) + 0.5)
				var yb: float = lerpf(float(sa["yc"]), float(sb["yc"]), (float(i) + 0.5) / 5.0) + tm * 0.36
				var sm: MeshInstance3D = _mi(body, _box(bw, 0.024, chm * 0.74), _flat(cs2), Vector3(side * xb, yb, zm + chm * 0.5))
				sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Markers (Model space; Body is scaled)
	var gs: Array = spec["guns"]
	for side in [-1.0, 1.0]:
		var mk := Marker3D.new()
		mk.name = "MuzzleR" if side > 0.0 else "MuzzleL"
		mk.position = Vector3(side * float(gs[0]), gs[1], gs[2]) * sc
		model.add_child(mk)
	var eye := Marker3D.new()
	eye.name = "CockpitEye"
	var eye_v: Vector3 = spec["eye"] as Vector3
	# Bombers sit in a hull whose nose deck rises above a pilot's eye: lift the eye to just over the deck so the
	# view forward is clear (the glazing is hidden in the cockpit view anyway).
	var fus_d: Dictionary = spec.get("fus", {})
	if String(fus_d.get("profile", "")) == "bomber":
		eye_v.y = maxf(eye_v.y, float(fus_d.get("cy", 0.0)) + float(fus_d.get("hh", 1.0)) + 0.5)
	eye.position = eye_v * sc
	model.add_child(eye)
	return model


## Underside racks / bomb-bay seams, the pitot tube and the radio aerial (see PlaneDetails).
static func _fit_details(body: Node3D, spec: Dictionary) -> void:
	var f: Dictionary = spec["fus"]
	var w: Dictionary = spec["wing"]
	var bomber: bool = String(f.get("profile", "")) == "bomber"
	var wing_of: Callable = func(t: float) -> Dictionary: return wing_section(w, t)
	var w0: Dictionary = wing_section(w, 0.0)
	var rz: float = float(w0["zle"]) + float(w0["chord"]) * 0.45
	var fd: Array = fus_at(f, rz)
	PlaneDetails.underside(body, String(spec.get("id", "")), wing_of, float(fd[2]) - float(fd[1]), rz, f)
	if bomber:
		var nz: float = float(f["z0"]) + 1.6
		var nd: Array = fus_at(f, nz)
		PlaneDetails.pitot(body, Vector3(-float(nd[0]) * 0.97, float(nd[2]) + float(nd[1]) * 0.1, nz), 0.5)
	else:
		var wp: Dictionary = wing_section(w, 0.5)
		PlaneDetails.pitot(body, Vector3(-float(wp["x"]), float(wp["yc"]) - float(wp["t"]) * 0.4, float(wp["zle"]) - 0.02))
	var eye: Vector3 = spec["eye"] as Vector3
	var mz: float = clampf(eye.z + (3.4 if bomber else 1.3), float(f["z0"]) + 0.5, float(f["z1"]) - 1.0)
	var ad: Array = fus_at(f, mz)
	var base := Vector3(0.0, float(ad[2]) + float(ad[1]) - 0.03, mz)
	var fin: Dictionary = spec["fin"]
	var fz: float = float(fin["z"]) + float(fin.get("sweep", 0.9)) + float(fin["ct"]) * 0.4
	var fy: float = float(fin["y"]) + float(fin["h"])
	if bool(fin.get("twin", false)):
		var fx: float = float(fin["x"])
		PlaneDetails.aerial(body, base, 0.5 if bomber else 0.4, Vector3(-fx, fy, fz), Vector3(fx, fy, fz))
	else:
		PlaneDetails.aerial(body, base, 0.5 if bomber else 0.4, Vector3(0.0, fy, fz))


static func _color_of(c: Variant, cols: Dictionary) -> Color:
	if c is Color:
		return c
	match String(c):
		"top":
			return cols["top"]
		"under":
			return cols["under"]
		"yellow":
			return Color(0.9, 0.75, 0.12)
		"white":
			return Color(0.93, 0.93, 0.93)
		"olive":
			return Color(0.22, 0.26, 0.14)
		"grey":
			return Color(0.45, 0.47, 0.5)
		_:
			return COL_DARK
