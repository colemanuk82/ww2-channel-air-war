class_name SpitfireModel
extends RefCounted
## Procedural low-poly toon Spitfire. Real-world metres * SCALE. Faces -Z, +Y up.

const SCALE: float = 1.1

const COL_TOP := Color(0.20, 0.30, 0.15)
const COL_PATCH := Color(0.33, 0.25, 0.15)
const COL_UNDER := Color(0.66, 0.75, 0.72)
const COL_DARK := Color(0.10, 0.10, 0.11)

# Wing parameters (metres)
const WING_ROOT_X := 0.35
const WING_HALF := 5.61
const WING_Y := -0.28
const WING_DIHEDRAL := 0.4


static func _wing_section(t: float) -> Dictionary:
	var chord: float = 2.7 * sqrt(maxf(1.0 - t * t * 0.93, 0.0)) + 0.05
	var zle: float = -1.5 + 1.0 * t * t
	var yc: float = WING_Y + WING_DIHEDRAL * t
	return {"x": WING_ROOT_X + WING_HALF * t, "yc": yc, "zle": zle, "chord": chord, "t": chord * 0.13}


static func _wing_mesh(side: float) -> ArrayMesh:
	var secs: Array = []
	for t in [0.0, 0.12, 0.28, 0.45, 0.58, 0.7, 0.8, 0.88, 0.94, 1.0]:
		var s: Dictionary = _wing_section(t)
		secs.append(MeshUtil.airfoil(side * s["x"], s["yc"], s["zle"], s["chord"], s["t"]))
	return MeshUtil.loft_smooth(secs, 2, 1)


static func _tailplane_mesh(side: float) -> ArrayMesh:
	var secs: Array = []
	for t in [0.0, 0.5, 1.0]:
		var chord: float = 1.35 - 0.8 * t
		secs.append(MeshUtil.airfoil(side * (0.15 + 1.7 * t), 0.18 + 0.1 * t, 3.75 + 0.55 * t, chord, 0.1 * (1.0 - 0.5 * t)))
	return MeshUtil.loft(secs)


## Half thickness of the fin section at chord fraction f (matches the polygon in _fin_mesh).
static func _fin_half(w: float, f: float) -> float:
	if f <= 0.3:
		return w * f / 0.3
	if f <= 0.8:
		return lerpf(w, w * 0.6, (f - 0.3) / 0.5)
	return w * 0.6 * (1.0 - f) / 0.2


static func _fin_mesh() -> ArrayMesh:
	var secs: Array = []
	for t in [0.0, 0.4, 0.8, 1.0]:
		var chord: float = 1.8 - 1.0 * t
		var zle: float = 3.3 + 0.9 * t
		var y: float = 0.15 + 1.9 * t
		var w: float = 0.09 * (1.0 - 0.5 * t)
		# airfoil in the Z-Y plane with thickness along X
		secs.append(PackedVector3Array([
			Vector3(0, y, zle), Vector3(w, y, zle + chord * 0.3), Vector3(w * 0.6, y, zle + chord * 0.8),
			Vector3(0, y, zle + chord), Vector3(-w * 0.6, y, zle + chord * 0.8), Vector3(-w, y, zle + chord * 0.3)]))
	return MeshUtil.loft(secs)


## z, half width, half height, centre y (also used to lay the roundels on the skin curve)
const FUS_RINGS: Array = [
	[-3.75, 0.07, 0.07, 0.0], [-3.68, 0.20, 0.22, 0.0], [-3.5, 0.33, 0.37, 0.0], [-3.3, 0.42, 0.46, 0.0], [-2.2, 0.56, 0.62, 0.02],
	[-0.8, 0.54, 0.68, 0.10], [0.8, 0.44, 0.56, 0.10], [2.5, 0.29, 0.40, 0.11],
	[4.0, 0.15, 0.25, 0.14], [4.85, 0.06, 0.13, 0.17]]


static func _fuselage_mesh() -> ArrayMesh:
	var secs: Array = []
	for r in FUS_RINGS:
		secs.append(MeshUtil.ring_xy(r[0], r[1], r[2], r[3], 16))
	return MeshUtil.loft_smooth(secs, 5, 1)


const CANOPY_RINGS: Array = [
	[-1.15, 0.12, 0.10, 0.74], [-0.8, 0.34, 0.30, 0.78], [-0.2, 0.40, 0.40, 0.80],
	[0.5, 0.34, 0.36, 0.78], [1.2, 0.10, 0.14, 0.76]]


static func _canopy_mesh() -> ArrayMesh:
	var secs: Array = []
	for r in CANOPY_RINGS:
		secs.append(MeshUtil.ring_xy(r[0], r[1], r[2], r[3], 12))
	return MeshUtil.loft_smooth(secs, 4, 1)


static func _box(sx: float, sy: float, sz: float) -> ArrayMesh:
	var secs: Array = [MeshUtil.rect_xy(-sz * 0.5, sx * 0.5, sy * 0.5), MeshUtil.rect_xy(sz * 0.5, sx * 0.5, sy * 0.5)]
	return MeshUtil.loft(secs)


static func _decal(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, nm: String = "DecalWing") -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = ToonUtil.make_toon(color, {"outline": false, "rim": 0.0})
	mi.position = pos
	mi.name = nm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _roundel(parent: Node3D, pos: Vector3, axis: Vector3, r: float, nation: String, nm: String = "DecalWing") -> void:
	# Concentric discs, layered with tiny offsets along the axis.
	var cols: Array
	var radii: Array
	match nation:
		"Luftwaffe":
			cols = [Color(0.05, 0.05, 0.05), Color(0.95, 0.95, 0.95), Color(0.05, 0.05, 0.05)]
			radii = [1.0, 0.8, 0.6]
		_:
			cols = [Color(0.1, 0.17, 0.5), Color(0.95, 0.95, 0.95), Color(0.8, 0.1, 0.1)]
			radii = [1.0, 0.66, 0.34]
	for i in cols.size():
		var m: ArrayMesh = MeshUtil.disc(r * radii[i], 0.02, Vector3.RIGHT if absf(axis.x) > 0.5 else Vector3.UP, 20)
		var off: Vector3 = axis * 0.012 * float(i)
		_decal(parent, m, cols[i], pos + off, nm)


static func build(nation: String = "RAF") -> Node3D:
	var model := Node3D.new()
	model.name = "Model"
	var body := Node3D.new()
	body.name = "Body"
	body.scale = Vector3.ONE * SCALE
	model.add_child(body)

	var camo := ToonUtil.make_toon(COL_TOP, {"underside": COL_UNDER, "patch": COL_PATCH, "patch_scale": 0.55, "outline_thickness": 0.014, "detail": 5, "gloss": 0.7})
	var dark := ToonUtil.make_toon(COL_DARK, {"outline_thickness": 0.012})

	var fus := MeshInstance3D.new()
	fus.name = "Fuselage"
	fus.mesh = _fuselage_mesh()
	fus.material_override = camo
	body.add_child(fus)

	for side in [-1.0, 1.0]:
		var w := MeshInstance3D.new()
		w.name = "WingR" if side > 0.0 else "WingL"
		w.mesh = _wing_mesh(side)
		w.material_override = camo
		body.add_child(w)
		# inboard flap panel (pivot FlapL / FlapR, driven by the aircraft script)
		var sa: Dictionary = _wing_section(0.10)
		var sb: Dictionary = _wing_section(0.52)
		var fl := Node3D.new()
		fl.name = "FlapR" if side > 0.0 else "FlapL"
		var fchord: float = (float(sa["chord"]) + float(sb["chord"])) * 0.5
		fl.position = Vector3(side * (float(sa["x"]) + float(sb["x"])) * 0.5, (float(sa["yc"]) + float(sb["yc"])) * 0.5 - 0.06, (float(sa["zle"]) + float(sb["zle"])) * 0.5 + fchord * 0.72)
		body.add_child(fl)
		var fbm := BoxMesh.new()
		fbm.size = Vector3(absf(float(sb["x"]) - float(sa["x"])), 0.05, fchord * 0.30)
		var fmi := MeshInstance3D.new()
		fmi.mesh = fbm
		fmi.material_override = camo
		fmi.position = Vector3(0.0, 0.0, fchord * 0.15)
		fl.add_child(fmi)
		var tp := MeshInstance3D.new()
		tp.name = "TailplaneR" if side > 0.0 else "TailplaneL"
		tp.mesh = _tailplane_mesh(side)
		tp.material_override = camo
		body.add_child(tp)

	var fin := MeshInstance3D.new()
	fin.name = "Fin"
	fin.mesh = _fin_mesh()
	fin.material_override = camo
	body.add_child(fin)

	# Canopy: transparent glazing over a dark frame (grouped so it can be hidden in cockpit view)
	var canopy := Node3D.new()
	canopy.name = "Canopy"
	body.add_child(canopy)
	var gmi := MeshInstance3D.new()
	gmi.mesh = _canopy_mesh()
	gmi.material_override = ToonUtil.make_glass({"opacity": 0.2, "rim": 0.9, "tint": Color(0.58, 0.70, 0.76)})
	gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	canopy.add_child(gmi)
	PlaneBuilder.canopy_frame(canopy, CANOPY_RINGS, dark)
	PlaneBuilder.pilot(canopy, Vector3(0.0, 1.12, 0.45))
	PlaneDetails.cockpit(canopy, Vector3(0.0, 1.12, 0.45), false, CANOPY_RINGS)

	# Radiators under the wings
	for side in [-1.0, 1.0]:
		var rad := MeshInstance3D.new()
		rad.mesh = _box(0.5, 0.32, 0.9)
		rad.material_override = dark
		rad.position = Vector3(side * 2.1, -0.62, 0.0)
		body.add_child(rad)

	# Exhaust stubs
	for side in [-1.0, 1.0]:
		for k in 3:
			var ex := MeshInstance3D.new()
			ex.mesh = _box(0.1, 0.1, 0.35)
			ex.material_override = dark
			ex.position = Vector3(side * 0.5, 0.18 - 0.0 * k, -2.3 + 0.38 * k)
			body.add_child(ex)

	# Underside rack, pitot tube under the port wing, radio mast and aerial wire to the fin tip
	PlaneDetails.underside(body, "spitfire", _wing_section, -0.52, 0.0)
	var wp: Dictionary = _wing_section(0.45)
	PlaneDetails.pitot(body, Vector3(-float(wp["x"]), float(wp["yc"]) - float(wp["t"]) * 0.4, float(wp["zle"]) - 0.02))
	PlaneDetails.aerial(body, Vector3(0.0, 0.55, 1.9), 0.42, Vector3(0.0, 2.05, 4.55))

	# Navigation lights: red to port, green to starboard at the wingtips
	var wt: Dictionary = _wing_section(1.0)
	for side in [-1.0, 1.0]:
		var lc: Color = Color(0.9, 0.12, 0.12) if side < 0.0 else Color(0.15, 0.9, 0.3)
		var lm := SphereMesh.new()
		lm.radius = 0.07
		lm.height = 0.14
		lm.radial_segments = 6
		lm.rings = 3
		var lmi := MeshInstance3D.new()
		lmi.mesh = lm
		lmi.material_override = ToonUtil.make_toon(lc, {"outline": false, "rim": 0.0, "emission": lc, "emission_energy": 1.1})
		lmi.position = Vector3(side * float(wt["x"]), float(wt["yc"]), float(wt["zle"]) + float(wt["chord"]) * 0.5)
		body.add_child(lmi)

	# Markings: the fuselage roundel is laid on the skin curve so it fits the tapered rear fuselage
	var fx: float = 0.30
	if nation == "Luftwaffe":
		PlaneBuilder.skin_marking(body, FUS_RINGS, nation, 2.4, 1.0, 0.36)
		PlaneBuilder.skin_marking(body, FUS_RINGS, nation, 2.4, -1.0, 0.36)
	else:
		var sd: Array = PlaneBuilder.station_at(FUS_RINGS, 2.4)
		var r: float = minf(0.5, minf(float(sd[0]), float(sd[1])) * 0.85)
		var layers: Array = [[1.0, Color(0.1, 0.17, 0.5)], [0.66, Color(0.95, 0.95, 0.95)], [0.34, Color(0.8, 0.1, 0.1)]]
		PlaneBuilder.skin_roundel(body, FUS_RINGS, 2.4, 1.0, r, layers)
		PlaneBuilder.skin_roundel(body, FUS_RINGS, 2.4, -1.0, r, layers)
	# Wing top roundels: inboard of the aileron, tilted with the dihedral and kept inside the chord
	for side in [-1.0, 1.0]:
		var ws: Dictionary = _wing_section(0.5)
		var top_y: float = float(ws["yc"]) + float(ws["t"]) * 0.5 + 0.008
		var piv := Node3D.new()
		piv.name = "DecalWing"
		piv.position = Vector3(side * float(ws["x"]), top_y, float(ws["zle"]) + float(ws["chord"]) * 0.42)
		piv.rotation.z = side * atan(WING_DIHEDRAL / WING_HALF)
		body.add_child(piv)
		_roundel(piv, Vector3.ZERO, Vector3.UP, 0.46, nation)
	# Fin flash (RAF): bands lofted along the fin skin so they follow its sweep and thickness
	if nation != "Luftwaffe":
		var stripe_cols: Array = [Color(0.1, 0.17, 0.5), Color(0.95, 0.95, 0.95), Color(0.8, 0.1, 0.1)]
		var fr: Array = [0.34, 0.47, 0.60, 0.73]
		for i in 3:
			for sx in [-1.0, 1.0]:
				var secs: Array = []
				for t in [0.22, 0.45, 0.68, 0.85]:
					var chord: float = 1.8 - 1.0 * t
					var zle: float = 3.3 + 0.9 * t
					var y: float = 0.15 + 1.9 * t
					var w: float = 0.09 * (1.0 - 0.5 * t)
					var ring := PackedVector3Array()
					for f in [fr[i], fr[i + 1]]:
						ring.append(Vector3(sx * (_fin_half(w, f) + 0.004), y, zle + chord * f))
					for f in [fr[i + 1], fr[i]]:
						ring.append(Vector3(sx * (_fin_half(w, f) - 0.012), y, zle + chord * f))
					secs.append(ring)
				_decal(body, MeshUtil.loft(secs), stripe_cols[i], Vector3.ZERO)
	else:
		_decal(body, _box(0.2, 0.4, 0.5), Color(0.05, 0.05, 0.05), Vector3(0, 1.0, 4.3))

	# Landing gear
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "GearR" if side > 0.0 else "GearL"
		pivot.position = Vector3(side * 1.35, WING_Y + WING_DIHEDRAL * 0.17 - 0.05, -0.5)
		body.add_child(pivot)
		var leg := MeshInstance3D.new()
		leg.mesh = _box(0.12, 0.8, 0.14)
		leg.material_override = dark
		leg.position = Vector3(0, -0.4, 0)
		pivot.add_child(leg)
		var wheel := MeshInstance3D.new()
		wheel.mesh = MeshUtil.disc(0.3, 0.14, Vector3.RIGHT, 12)
		wheel.material_override = dark
		wheel.position = Vector3(0, -0.82, 0)
		pivot.add_child(wheel)
	var tail_wheel := MeshInstance3D.new()
	tail_wheel.mesh = MeshUtil.disc(0.12, 0.08, Vector3.RIGHT, 8)
	tail_wheel.material_override = dark
	tail_wheel.position = Vector3(0, -0.12, 4.5)
	tail_wheel.name = "TailWheel"
	body.add_child(tail_wheel)

	# Propeller group
	var prop := Node3D.new()
	prop.name = "Propeller"
	prop.position = Vector3(0, 0, -3.8)
	body.add_child(prop)
	var spinner := MeshInstance3D.new()
	var sp_secs: Array = []
	sp_secs.append(MeshUtil.ring_xy(-0.7, 0.02, 0.02, 0.0, 20))
	sp_secs.append(MeshUtil.ring_xy(-0.5, 0.17, 0.17, 0.0, 20))
	sp_secs.append(MeshUtil.ring_xy(-0.1, 0.30, 0.30, 0.0, 20))
	sp_secs.append(MeshUtil.ring_xy(0.1, 0.30, 0.30, 0.0, 20))
	spinner.mesh = MeshUtil.loft(sp_secs)
	spinner.material_override = ToonUtil.make_toon(Color(0.12, 0.12, 0.13), {"outline_thickness": 0.012})
	prop.add_child(spinner)
	var blade_mat := ToonUtil.make_toon(Color(0.07, 0.07, 0.07), {"outline": false})
	# The blades hang off one node so a fast-spinning prop can swap them for the PropDisc blur (see
	# AircraftModels.prop_blur): blades sampled a few times per turn strobe, which reads as the aircraft
	# shaking, worst in the cockpit view where the prop fills the screen.
	var blades := Node3D.new()
	blades.name = "Blades"
	prop.add_child(blades)
	for i in 3:
		var pivot := Node3D.new()
		pivot.rotation.z = TAU * float(i) / 3.0
		blades.add_child(pivot)
		var blade := MeshInstance3D.new()
		var bsecs: Array = [
			PackedVector3Array([Vector3(-0.09, 0.2, -0.04), Vector3(0.09, 0.2, 0.04), Vector3(0.09, 0.2, 0.0), Vector3(-0.09, 0.2, 0.0)]),
			PackedVector3Array([Vector3(-0.15, 1.1, -0.06), Vector3(0.15, 1.1, 0.06), Vector3(0.15, 1.1, 0.0), Vector3(-0.15, 1.1, 0.0)]),
			PackedVector3Array([Vector3(-0.08, 1.75, -0.03), Vector3(0.08, 1.75, 0.03), Vector3(0.08, 1.75, 0.0), Vector3(-0.08, 1.75, 0.0)])]
		blade.mesh = MeshUtil.loft(bsecs)
		blade.material_override = blade_mat
		pivot.add_child(blade)
		# yellow tip
		var tip := MeshInstance3D.new()
		tip.mesh = _box(0.17, 0.25, 0.07)
		tip.material_override = ToonUtil.make_toon(Color(0.9, 0.75, 0.15), {"outline": false})
		tip.position = Vector3(0, 1.62, 0)
		pivot.add_child(tip)
	var disc := MeshInstance3D.new()
	disc.name = "PropDisc"
	var dm := CylinderMesh.new()
	dm.top_radius = 1.75
	dm.bottom_radius = 1.75
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
	disc.visible = false
	prop.add_child(disc)

	# Markers (in Model space; Body is scaled so convert)
	for side in [-1.0, 1.0]:
		var m := Marker3D.new()
		m.name = "MuzzleR" if side > 0.0 else "MuzzleL"
		m.position = Vector3(side * 1.9, -0.22, -1.9) * SCALE
		model.add_child(m)
	var eye := Marker3D.new()
	eye.name = "CockpitEye"
	eye.position = Vector3(0.0, 1.12, 0.45) * SCALE
	model.add_child(eye)
	return model
