class_name PlaneParts
extends RefCounted
## Higher-fidelity shared parts for every aircraft (procedural PlaneBuilder types and the hero SpitfireModel):
## ogive spinner, twisted paddle propeller blades, tyres with hubs, oleo gear legs with doors, exhaust stacks,
## cannon barrels, radiators / intakes and rounded tail surfaces. Body space: nose toward -Z, +Y up, metres.

const RUBBER := Color(0.045, 0.045, 0.05)
const ALLOY := Color(0.55, 0.57, 0.58)
const CHROME := Color(0.72, 0.74, 0.75)
const DARKMETAL := Color(0.13, 0.13, 0.14)
const SOOT := Color(0.12, 0.085, 0.06)
const RUST := Color(0.28, 0.15, 0.08)

## Engine type per aircraft for the nacelle fittings (radial: cowl ring, gills and cylinder heads; annular: Ju 88 style
## ring radiator; inline: ejector exhausts and a chin radiator).
const ENGINE_KIND := {
	"b25": "radial", "b26": "radial", "a20": "radial", "c47": "radial", "do17": "radial", "ju52": "radial",
	"fw200": "radial", "blenheim": "radial", "ju88": "annular",
	"lancaster": "inline", "he111": "inline", "bf110": "inline", "mosquito": "inline", "p38": "inline",
}

static var _cache: Dictionary = {}


static func mat(c: Color, gloss: float = 0.5) -> Material:
	var k: String = "%s_%.2f" % [c.to_html(), gloss]
	if not _cache.has(k):
		_cache[k] = ToonUtil.make_toon(c, {"outline": false, "rim": 0.0, "gloss": gloss})
	return _cache[k]


static func _mi(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, nm: String = "", shadow: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if nm != "":
		mi.name = nm
	parent.add_child(mi)
	return mi


static func cyl(parent: Node3D, r0: float, r1: float, h: float, pos: Vector3, m: Material, rot: Vector3 = Vector3.ZERO, segs: int = 8, nm: String = "") -> MeshInstance3D:
	## Cylinder along local Y (rot in degrees to point it elsewhere).
	var cm := CylinderMesh.new()
	cm.top_radius = r1
	cm.bottom_radius = r0
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	var mi := _mi(parent, cm, m, pos, nm)
	mi.rotation_degrees = rot
	return mi


# ---------------------------------------------------------------- propeller

static func spinner_mesh(spinner_r: float) -> ArrayMesh:
	## Smooth ogive nose cone, base plane at z = +0.1k. k = spinner_r / 0.3 (matches the old spinner proportions).
	var k: float = spinner_r / 0.3
	var secs: Array = []
	var n: int = 9
	for i in range(n + 1):
		var u: float = float(i) / float(n)
		var z: float = lerpf(-0.72 * k, -0.02 * k, u)
		var r: float = spinner_r * pow(sin(u * PI * 0.5), 0.72)
		secs.append(MeshUtil.ring_xy(z, maxf(r, 0.012), maxf(r, 0.012), 0.0, 16))
	secs.append(MeshUtil.ring_xy(0.1 * k, spinner_r * 1.0, spinner_r * 1.0, 0.0, 16))
	return MeshUtil.loft_smooth(secs, 2, 1)


static func blade_mesh(radius: float, spinner_r: float) -> ArrayMesh:
	## Paddle blade along +Y with pitch twist (steep at the root, flat at the tip), chord widening to ~65% radius.
	var rs: float = radius / 1.75
	var stations: Array = [
		# [y/R, chord (rs units), thickness, twist deg]
		[0.0, 0.11, 0.050, 40.0], [0.16, 0.14, 0.046, 38.0], [0.30, 0.22, 0.042, 33.0], [0.48, 0.30, 0.036, 26.0],
		[0.66, 0.32, 0.030, 20.0], [0.82, 0.28, 0.024, 15.0], [0.93, 0.21, 0.018, 12.0], [1.0, 0.10, 0.012, 10.0]]
	var y0: float = spinner_r * 0.85
	var secs: Array = []
	for s in stations:
		var y: float = lerpf(y0, radius, float(s[0]))
		var c: float = float(s[1]) * rs
		var th: float = float(s[2]) * rs * 1.6
		var ph: float = deg_to_rad(float(s[3]))
		var pts: Array = [Vector2(-c * 0.5, 0.0), Vector2(-c * 0.22, th), Vector2(c * 0.2, th * 0.8), Vector2(c * 0.5, 0.0), Vector2(c * 0.2, -th * 0.25), Vector2(-c * 0.22, -th * 0.3)]
		var ring := PackedVector3Array()
		for p in pts:
			var q: Vector2 = p
			ring.append(Vector3(q.x * cos(ph) - q.y * sin(ph), y, q.x * sin(ph) + q.y * cos(ph)))
		secs.append(ring)
	return MeshUtil.loft_smooth(secs, 2, 0)


static func hub_plate(prop: Node3D, spinner_r: float) -> void:
	var k: float = spinner_r / 0.3
	var p := cyl(prop, spinner_r * 1.02, spinner_r * 1.02, 0.05 * k, Vector3(0, 0, 0.1 * k), mat(DARKMETAL), Vector3(90, 0, 0), 16, "Backplate")
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# ---------------------------------------------------------------- wheels and legs

static func wheel(pivot: Node3D, r: float, width: float, pos: Vector3, nm: String = "Wheel") -> MeshInstance3D:
	## Tyre (named Wheel so the aircraft script can find it) with alloy hub, hub cap and a sidewall ring.
	var tyre := _mi(pivot, MeshUtil.disc(r, width, Vector3.RIGHT, 20), mat(RUBBER, 0.2), pos, nm, true)
	var hub := cyl(tyre, r * 0.58, r * 0.58, width * 1.04, Vector3.ZERO, mat(ALLOY, 0.7), Vector3(0, 0, 90), 14)
	hub.name = "Hub"
	cyl(tyre, r * 0.22, r * 0.22, width * 1.18, Vector3.ZERO, mat(CHROME, 0.9), Vector3(0, 0, 90), 8, "Cap")
	return tyre


static func gear_leg(pivot: Node3D, side: float, length: float, leg_w: float, wheel_r: float, wheel_w: float, with_door: bool = true) -> void:
	## Oleo leg (fat dark upper, chrome lower), scissor link, axle fork, and an outer gear door.
	var dm := mat(DARKMETAL, 0.4)
	var up: float = length * 0.55
	cyl(pivot, leg_w * 0.62, leg_w * 0.52, up, Vector3(0, -up * 0.5, 0), dm, Vector3.ZERO, 10, "OleoUpper")
	var lo: float = length * 0.5
	cyl(pivot, leg_w * 0.32, leg_w * 0.32, lo, Vector3(0, -up - lo * 0.5 + length * 0.05, 0), mat(CHROME, 0.9), Vector3.ZERO, 8, "OleoLower")
	# torque scissor
	var sc := BoxMesh.new()
	sc.size = Vector3(leg_w * 0.18, length * 0.22, leg_w * 0.18)
	var s1 := _mi(pivot, sc, dm, Vector3(0, -length * 0.5, -leg_w * 0.7))
	s1.rotation_degrees = Vector3(18, 0, 0)
	# axle fork: two cheeks either side of the wheel
	for fs in [-1.0, 1.0]:
		var fk := BoxMesh.new()
		fk.size = Vector3(leg_w * 0.2, wheel_r * 0.5, leg_w * 0.5)
		_mi(pivot, fk, dm, Vector3(fs * (wheel_w * 0.5 + leg_w * 0.14), -length - wheel_r * 0.1, 0))
	if with_door:
		var door := BoxMesh.new()
		door.size = Vector3(0.03, length * 0.8, maxf(wheel_r * 1.1, 0.26))
		var dmi := _mi(pivot, door, mat(Color(0.2, 0.22, 0.17), 0.3), Vector3(side * (wheel_w * 0.5 + leg_w * 0.6), -length * 0.46, 0.0), "GearDoor")
		dmi.rotation_degrees = Vector3(0, 0, side * 4.0)


static func tail_wheel(body: Node3D, y: float, z: float, r: float = 0.14) -> void:
	var tw := wheel(body, r, 0.09, Vector3(0, y, z), "TailWheel")
	var fk := BoxMesh.new()
	fk.size = Vector3(0.025, r * 1.6, 0.05)
	_mi(body, fk, mat(DARKMETAL), Vector3(0, y + r * 0.9, z - 0.02)).rotation_degrees = Vector3(-8, 0, 0)
	tw.rotation_degrees = Vector3.ZERO


# ---------------------------------------------------------------- engine fittings

static func exhaust_stacks(body: Node3D, f: Dictionary, z_from: float, count: int, spacing: float, y_frac: float = 0.35, fishtail: bool = true) -> void:
	## Ejector exhaust stubs along each side of an inline-engine cowling: round pipes, flared and swept aft, soot streaked.
	for side in [-1.0, 1.0]:
		for k in count:
			var ez: float = z_from + spacing * float(k)
			var ed: Array = PlaneBuilder.fus_at(f, ez)
			var hw: float = float(ed[0])
			var py: float = float(ed[2]) + float(ed[1]) * y_frac
			var stub := cyl(body, 0.034, 0.048, 0.2, Vector3(side * (hw * 0.97 + 0.02), py, ez), mat(RUST if k % 2 == 0 else Color(0.2, 0.12, 0.08), 0.3), Vector3(90, 0, side * -80.0), 8, "Exhaust")
			stub.rotation_degrees = Vector3(90, 0, -side * 14.0)
			if fishtail:
				var ft := BoxMesh.new()
				ft.size = Vector3(0.018, 0.075, 0.1)
				_mi(body, ft, mat(SOOT, 0.2), Vector3(side * (hw * 1.0 + 0.1), py, ez + 0.1))
			# scorch streak on the cowling behind each stub
			var st := BoxMesh.new()
			st.size = Vector3(0.006, 0.05, spacing * 0.8)
			_mi(body, st, mat(SOOT, 0.1), Vector3(side * (hw * 0.995 + 0.004), py, ez + spacing * 0.55))


static func radial_cowl(body: Node3D, f: Dictionary, color: Color) -> void:
	## Cowling lip ring and cooling-gill band for radial engines, plus the dark inlet behind the propeller.
	var z0: float = float(f["z0"])
	var d: Array = PlaneBuilder.fus_at(f, z0 + 0.35)
	var r: float = maxf(float(d[0]), float(d[1]))
	var lip: Array = [
		MeshUtil.ring_xy(z0 - 0.02, r * 0.72, r * 0.72, float(d[2]), 20),
		MeshUtil.ring_xy(z0 + 0.04, r * 1.0, r * 1.0, float(d[2]), 20),
		MeshUtil.ring_xy(z0 + 0.2, r * 1.04, r * 1.04, float(d[2]), 20),
		MeshUtil.ring_xy(z0 + 0.34, r * 1.0, r * 1.0, float(d[2]), 20)]
	_mi(body, MeshUtil.loft_smooth(lip, 2, 0), mat(Color(0.5, 0.52, 0.53), 0.8), Vector3.ZERO, "CowlLip", true)
	var gills: Array = [
		MeshUtil.ring_xy(z0 + 0.62, r * 1.0, r * 1.0, float(d[2]), 20),
		MeshUtil.ring_xy(z0 + 0.7, r * 1.03, r * 1.03, float(d[2]), 20),
		MeshUtil.ring_xy(z0 + 0.86, r * 1.03, r * 1.03, float(d[2]), 20),
		MeshUtil.ring_xy(z0 + 0.94, r * 1.0, r * 1.0, float(d[2]), 20)]
	_mi(body, MeshUtil.loft_smooth(gills, 2, 0), mat(color.darkened(0.35), 0.3), Vector3.ZERO, "CowlGills")
	cyl(body, r * 0.62, r * 0.62, 0.04, Vector3(0, float(d[2]), z0 - 0.0), mat(Color(0.03, 0.03, 0.035), 0.2), Vector3(90, 0, 0), 20, "Inlet")
	# cylinder-head bumps ringing the cowl
	for i in 9:
		var a: float = TAU * float(i) / 9.0
		var b := BoxMesh.new()
		b.size = Vector3(0.12, 0.1, 0.34)
		var bm := _mi(body, b, mat(color, 0.5), Vector3(cos(a) * r * 1.0, float(d[2]) + sin(a) * r * 1.0, z0 + 0.52))
		bm.rotation_degrees = Vector3(0, 0, rad_to_deg(a) - 90.0)


static func intake_scoop(body: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	## Radiator / intake fairing (chin radiators, belly scoops, underwing coolers): a rounded duct that is full size at
	## the mouth and tapers into the skin at the back, with a dark mouth, a polished lip and a cooling-flap line.
	var hw: float = size.x * 0.5
	var hh: float = size.y * 0.5
	var zf: float = pos.z - size.z * 0.5
	var zb: float = pos.z + size.z * 0.5
	var top: float = pos.y + hh
	var rings: Array = []
	for st in [[0.0, 0.92, 0.92], [0.06, 1.0, 1.0], [0.45, 1.0, 1.0], [0.75, 0.9, 0.7], [1.0, 0.7, 0.18]]:
		var z: float = lerpf(zf, zb, float(st[0]))
		var h2: float = hh * float(st[2])
		rings.append(MeshUtil.ring_xy(z, hw * float(st[1]), h2, top - h2, 14))
	_mi(body, MeshUtil.loft_smooth(rings, 2, 1), mat(color, 0.5), Vector3.ZERO, "Scoop", true)
	var mouth: Array = [
		MeshUtil.ring_xy(zf - 0.004, hw * 0.8, hh * 0.72, top - hh * 0.92, 14),
		MeshUtil.ring_xy(zf + 0.02, hw * 0.8, hh * 0.72, top - hh * 0.92, 14)]
	_mi(body, MeshUtil.loft(mouth), mat(Color(0.025, 0.025, 0.03), 0.2), Vector3.ZERO, "ScoopMouth")
	var lip: Array = [
		MeshUtil.ring_xy(zf - 0.01, hw * 0.95, hh * 0.9, top - hh * 0.92, 14),
		MeshUtil.ring_xy(zf + 0.03, hw * 0.95, hh * 0.9, top - hh * 0.92, 14)]
	_mi(body, MeshUtil.loft(lip, false, false), mat(ALLOY, 0.7), Vector3.ZERO, "ScoopLip")
	# cooling flap line at the back of the duct
	var fl := BoxMesh.new()
	fl.size = Vector3(size.x * 0.8, 0.012, 0.02)
	_mi(body, fl, mat(Color(0.05, 0.05, 0.05), 0.2), Vector3(pos.x, top - hh * 1.55 * 0.9, lerpf(zf, zb, 0.72)))


static func cannons(body: Node3D, side_x: float, y: float, z_muzzle: float, count: int, barrel_len: float, r: float) -> void:
	## Cannon / MG barrels poking forward from the leading edge on both wings.
	for side in [-1.0, 1.0]:
		for k in count:
			var x: float = side * (side_x - 0.22 * float(k))
			var c := cyl(body, r * (1.0 - 0.15 * float(k)), r * (1.0 - 0.15 * float(k)) * 0.9, barrel_len, Vector3(x, y - 0.03 * float(k), z_muzzle + barrel_len * 0.5), mat(DARKMETAL, 0.5), Vector3(90, 0, 0), 8, "Barrel")
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			cyl(body, r * 1.7, r * 1.7, 0.06, Vector3(x, y - 0.03 * float(k), z_muzzle + 0.03), mat(Color(0.05, 0.05, 0.055), 0.3), Vector3(90, 0, 0), 8, "MuzzleBrake")


static func underwing_radiators(body: Node3D, wing_of: Callable, t: float, size: Vector3, color: Color, left_only: bool = false) -> void:
	## Boxed radiator / oil-cooler housings hung beneath each wing (Spitfire, Bf 109, Hurricane).
	for side in [-1.0, 1.0]:
		if left_only and side > 0.0:
			continue
		var s: Dictionary = wing_of.call(t)
		var sz := Vector3(size.x, size.y, size.z)
		var pos := Vector3(side * float(s["x"]), float(s["yc"]) - float(s["t"]) * 0.5 - size.y * 0.42, float(s["zle"]) + float(s["chord"]) * 0.42)
		intake_scoop(body, pos, sz, color)


# ---------------------------------------------------------------- rounded tail surfaces

static func tailplane_mesh(tp: Dictionary, side: float, base_x: float = 0.15) -> ArrayMesh:
	## Rounded-tip tailplane: chord tapers with an elliptical planform, thickness falls to the tip.
	var secs: Array = []
	for t in [0.0, 0.2, 0.4, 0.6, 0.78, 0.9, 0.96, 1.0]:
		var chord: float = lerpf(float(tp["cr"]), float(tp["ct"]), t)
		chord = maxf(chord * sqrt(maxf(1.0 - pow(t, 3.0) * 0.82, 0.0)), 0.1)
		var th: float = 0.11 * chord * (1.0 - 0.45 * t)
		secs.append(MeshUtil.airfoil(side * (base_x + float(tp["span"]) * t), float(tp["y"]) + 0.1 * t, float(tp["z"]) + 0.5 * t, chord, th))
	return MeshUtil.loft_smooth(secs, 2, 1)


static func fin_mesh(fn: Dictionary, x: float) -> ArrayMesh:
	## Fin + rudder lofted through PlaneBuilder.fin_sec (curved leading edge, rounded top, optional dorsal fillet).
	var secs: Array = []
	for t in [0.0, 0.08, 0.18, 0.3, 0.45, 0.6, 0.72, 0.82, 0.9, 0.95, 0.985, 1.0]:
		var d: Dictionary = PlaneBuilder.fin_sec(fn, t)
		var chord: float = d["chord"]
		var zle: float = d["zle"]
		var y: float = d["y"]
		var w: float = d["w"]
		secs.append(PackedVector3Array([
			Vector3(x, y, zle), Vector3(x + w, y, zle + chord * 0.3), Vector3(x + w * 0.6, y, zle + chord * 0.8),
			Vector3(x, y, zle + chord), Vector3(x - w * 0.6, y, zle + chord * 0.8), Vector3(x - w, y, zle + chord * 0.3)]))
	return MeshUtil.loft(secs)


# ---------------------------------------------------------------- nacelles (multi-engine types)

static func cowl_ring(body: Node3D, c: Vector3, r: float, color: Color, bumps: int, gills: bool = true) -> void:
	## Radial / annular cowling at centre c (front face z = c.z): polished lip, dark inlet, optional cylinder heads and gills.
	var lip: Array = [
		MeshUtil.ring_xy(c.z - 0.02, r * 0.7, r * 0.7, c.y, 20),
		MeshUtil.ring_xy(c.z + 0.04, r * 0.97, r * 0.97, c.y, 20),
		MeshUtil.ring_xy(c.z + 0.18, r * 1.03, r * 1.03, c.y, 20),
		MeshUtil.ring_xy(c.z + 0.3, r * 1.0, r * 1.0, c.y, 20)]
	var lm := _mi(body, MeshUtil.loft_smooth(lip, 2, 0), mat(Color(0.5, 0.52, 0.53), 0.8), Vector3(c.x, 0, 0), "CowlLip", true)
	lm.position.x = c.x
	cyl(body, r * 0.66, r * 0.66, 0.04, Vector3(c.x, c.y, c.z + 0.02), mat(Color(0.03, 0.03, 0.035), 0.2), Vector3(90, 0, 0), 20, "Inlet")
	for i in bumps:
		var a: float = TAU * float(i) / float(bumps)
		var b := BoxMesh.new()
		b.size = Vector3(r * 0.2, r * 0.16, r * 0.5)
		var bm := _mi(body, b, mat(Color(0.2, 0.2, 0.21), 0.5), Vector3(c.x + cos(a) * r * 0.5, c.y + sin(a) * r * 0.5, c.z + 0.08))
		bm.rotation_degrees = Vector3(0, 0, rad_to_deg(a) - 90.0)
	if gills:
		var gz: float = c.z + r * 1.1
		var g: Array = [
			MeshUtil.ring_xy(gz, r * 0.98, r * 0.98, c.y, 20),
			MeshUtil.ring_xy(gz + 0.06, r * 1.04, r * 1.04, c.y, 20),
			MeshUtil.ring_xy(gz + 0.22, r * 1.04, r * 1.04, c.y, 20),
			MeshUtil.ring_xy(gz + 0.3, r * 0.98, r * 0.98, c.y, 20)]
		var gm := _mi(body, MeshUtil.loft_smooth(g, 2, 0), mat(color.darkened(0.35), 0.3), Vector3.ZERO, "CowlGills")
		gm.position.x = c.x


static func nacelle_fittings(body: Node3D, id: String, e: Dictionary, color: Color, under: Color) -> void:
	var kind: String = String(ENGINE_KIND.get(id, "inline"))
	var x: float = float(e["x"])
	var y: float = float(e["y"])
	var z0: float = float(e["z0"])
	var z1: float = float(e["z1"])
	var r: float = float(e["r"])
	match kind:
		"radial":
			cowl_ring(body, Vector3(x, y, z0), r * 0.95, color, 9)
		"annular":
			cowl_ring(body, Vector3(x, y, z0), r * 0.95, color, 0, false)
		_:
			# ejector exhaust stubs down both sides of the nacelle and a chin radiator
			var n: int = 6
			var sp: float = minf((z1 - z0) * 0.35 / float(n), 0.26)
			for side in [-1.0, 1.0]:
				for k in n:
					var ez: float = z0 + r * 0.55 + sp * float(k)
					var stub := cyl(body, 0.03, 0.045, 0.18, Vector3(x + side * r * 0.93, y + r * 0.25, ez), mat(RUST if k % 2 == 0 else Color(0.2, 0.12, 0.08), 0.3), Vector3.ZERO, 8, "Exhaust")
					stub.rotation_degrees = Vector3(90, 0, -side * 14.0)
				var st := BoxMesh.new()
				st.size = Vector3(0.006, 0.07, sp * float(n) + 0.6)
				_mi(body, st, mat(SOOT, 0.1), Vector3(x + side * r * 0.955, y + r * 0.25, z0 + r * 0.55 + sp * float(n) * 0.5 + 0.3))
			intake_scoop(body, Vector3(x, y - r * 0.9, z0 + r * 0.9), Vector3(r * 0.9, r * 0.45, r * 1.4), under.darkened(0.3))


static func gun_turret(body: Node3D, pos: Vector3, r: float, glass: Material, skin: Material) -> void:
	## Boulton Paul style power turret: metal base ring, faired collar, glazed dome and four guns trained aft.
	cyl(body, r * 1.05, r * 1.1, 0.12, pos + Vector3(0, -0.02, 0), mat(DARKMETAL, 0.5), Vector3.ZERO, 20, "TurretRing")
	var dm := SphereMesh.new()
	dm.radius = r
	dm.height = r * 1.6
	dm.radial_segments = 20
	dm.rings = 8
	dm.is_hemisphere = true
	var dome := _mi(body, dm, glass, pos + Vector3(0, 0.04, 0), "TurretDome")
	dome.scale = Vector3(1.0, 1.0, 1.15)
	# dome framing: two hoops
	for k in 2:
		var tm := TorusMesh.new()
		tm.inner_radius = r * (0.98 - 0.3 * float(k))
		tm.outer_radius = r * (1.02 - 0.3 * float(k))
		tm.rings = 20
		var t := _mi(body, tm, mat(DARKMETAL, 0.5), pos + Vector3(0, 0.06 + r * 0.55 * float(k), 0))
		t.scale = Vector3(1.0, 1.0, 1.15)
	for gx in [-0.17, -0.06, 0.06, 0.17]:
		var b := cyl(body, 0.022, 0.02, 0.9, pos + Vector3(gx, r * 0.45, 0.55), mat(DARKMETAL, 0.5), Vector3(80, 0, 0), 6, "TurretGun")
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# ---------------------------------------------------------------- control-surface gaps

static func _strip(pts: Array, half_h: float, half_w: float) -> ArrayMesh:
	## Thin dark strip through the points (Body space), each cross-section a small rect normal to the run.
	var secs: Array = []
	for i in pts.size():
		var p: Vector3 = pts[i]
		var dir: Vector3 = ((pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var side: Vector3 = dir.cross(Vector3.UP).normalized() * half_w
		if side.length() < 0.0001:
			side = Vector3(0, 0, half_w)
		var up := Vector3(0, half_h, 0)
		secs.append(PackedVector3Array([p + up - side, p + up + side, p - up + side, p - up - side]))
	return MeshUtil.loft(secs)


static func aileron_lines(body: Node3D, wing_of: Callable, side: float, t0: float = 0.6, t1: float = 0.95, hinge: float = 0.74) -> void:
	## Aileron hinge line and its two chordwise ends, on the top and bottom skin (the airfoil of MeshUtil.airfoil).
	var m := mat(Color(0.04, 0.04, 0.045), 0.15)
	for surf in [1.0, -1.0]:
		var run: Array = []
		for k in 7:
			var t: float = lerpf(t0, t1, float(k) / 6.0)
			run.append(_skin_pt(wing_of.call(t), side, hinge, surf))
		_mi(body, _strip(run, 0.006, 0.011), m, Vector3.ZERO, "HingeLine")
		for t in [t0, t1]:
			var ends: Array = []
			for f in [hinge, lerpf(hinge, 1.0, 0.5), 0.985]:
				ends.append(_skin_pt(wing_of.call(t), side, f, surf))
			_mi(body, _strip(ends, 0.006, 0.009), m, Vector3.ZERO, "HingeLine")


static func _skin_pt(s: Dictionary, side: float, f: float, surf: float) -> Vector3:
	## Point on the wing skin at chord fraction f (top surf = 1, bottom = -1). Follows the exact surface the wing is
	## lofted through: MeshUtil.airfoil refined once by MeshUtil.refine_ring (loft_smooth ring_passes = 1).
	var ring: PackedVector3Array = MeshUtil.refine_ring(MeshUtil.airfoil(0.0, float(s["yc"]), float(s["zle"]), float(s["chord"]), float(s["t"])))
	# refined order: 0 LE, upper 1..5, 6 TE, lower 7..11 back to the LE
	var idx: Array = [0, 1, 2, 3, 4, 5, 6] if surf > 0.0 else [6, 7, 8, 9, 10, 11, 0]
	var z: float = float(s["zle"]) + float(s["chord"]) * clampf(f, 0.0, 1.0)
	var y: float = ring[idx[0]].y
	for k in idx.size() - 1:
		var pa: Vector3 = ring[idx[k]]
		var pb: Vector3 = ring[idx[k + 1]]
		var lo: float = minf(pa.z, pb.z)
		var hi: float = maxf(pa.z, pb.z)
		if z >= lo and z <= hi and hi > lo:
			y = lerpf(pa.y, pb.y, (z - pa.z) / (pb.z - pa.z))
			break
	return Vector3(side * float(s["x"]), y + surf * 0.004, z)


static func skin_patch(body: Node3D, wing_of: Callable, side: float, t0: float, t1: float, f0: float, f1: float, surf: float, color: Color, nm: String = "DecalStripe") -> void:
	## A paint patch laid on the wing skin between span fractions t0..t1 and chord fractions f0..f1 (top surf = 1,
	## bottom = -1). Used for D-Day stripes, which wrap the real wing chord rather than float above it.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nt: int = 3
	var nf: int = 10
	var grid: Array = []
	for i in nt + 1:
		var row: Array = []
		var s: Dictionary = wing_of.call(lerpf(t0, t1, float(i) / float(nt)))
		for j in nf + 1:
			var p: Vector3 = _skin_pt(s, side, lerpf(f0, f1, float(j) / float(nf)), surf)
			p.y += surf * 0.002
			row.append(p)
		grid.append(row)
	st.set_normal(Vector3(0, surf, 0))
	for i in nt:
		for j in nf:
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i + 1][j]
			var c: Vector3 = grid[i + 1][j + 1]
			var d: Vector3 = grid[i][j + 1]
			for tri in [[a, b, c], [a, c, d]]:
				st.add_vertex(tri[0])
				st.add_vertex(tri[1])
				st.add_vertex(tri[2])
				st.add_vertex(tri[2])
				st.add_vertex(tri[1])
				st.add_vertex(tri[0])
	var mi := _mi(body, st.commit(), mat(color, 0.3), Vector3.ZERO, nm)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func jet_fittings(body: Node3D, front: Vector3, z1: float, r: float) -> void:
	## Axial-flow jet details: the starter-housing bullet in the intake and the exhaust cone in the tailpipe.
	var bullet: Array = [
		MeshUtil.ring_xy(front.z - 0.08, 0.02, 0.02, front.y, 12),
		MeshUtil.ring_xy(front.z + 0.02, r * 0.3, r * 0.3, front.y, 12),
		MeshUtil.ring_xy(front.z + 0.2, r * 0.38, r * 0.38, front.y, 12)]
	var b := _mi(body, MeshUtil.loft_smooth(bullet, 2, 0), mat(Color(0.45, 0.46, 0.47), 0.7), Vector3.ZERO, "IntakeBullet")
	b.position.x = front.x
	var tail_r: float = r * 0.56
	var cone: Array = [
		MeshUtil.ring_xy(z1 - 0.25, tail_r * 0.7, tail_r * 0.7, front.y, 12),
		MeshUtil.ring_xy(z1 + 0.05, tail_r * 0.45, tail_r * 0.45, front.y, 12),
		MeshUtil.ring_xy(z1 + 0.3, 0.02, 0.02, front.y, 12)]
	var c := _mi(body, MeshUtil.loft_smooth(cone, 2, 0), mat(Color(0.2, 0.17, 0.14), 0.5), Vector3.ZERO, "ExhaustCone")
	c.position.x = front.x
	cyl(body, tail_r * 0.98, tail_r * 0.98, 0.03, Vector3(front.x, front.y, z1 - 0.005), mat(Color(0.03, 0.03, 0.03), 0.2), Vector3(90, 0, 0), 14, "Tailpipe")


static func bomber_turret(body: Node3D, pos: Vector3, r: float, glass: Material, forward: bool, hemi: bool) -> void:
	## Glazed gun turret (nose / tail / dorsal): perspex dome or ball over a dark frame, with twin barrels.
	var dm := SphereMesh.new()
	dm.radius = r
	dm.height = r * (1.0 if hemi else 2.0)
	dm.radial_segments = 18
	dm.rings = 8
	dm.is_hemisphere = hemi
	_mi(body, dm, glass, pos, "TurretGlass")
	# frame: base ring and one meridian hoop, so the dome reads as framed perspex not a ball
	var ring := TorusMesh.new()
	ring.inner_radius = r * 0.96
	ring.outer_radius = r * 1.04
	ring.rings = 18
	_mi(body, ring, mat(DARKMETAL, 0.5), pos + Vector3(0, 0.01 if hemi else 0.0, 0), "TurretRing")
	var hoop := TorusMesh.new()
	hoop.inner_radius = r * 0.97
	hoop.outer_radius = r * 1.02
	hoop.rings = 18
	var hm := _mi(body, hoop, mat(DARKMETAL, 0.5), pos)
	hm.rotation_degrees = Vector3(0, 0, 90)
	# gunner silhouette inside and the guns
	var gd := SphereMesh.new()
	gd.radius = r * 0.28
	gd.height = r * 0.56
	_mi(body, gd, mat(Color(0.3, 0.27, 0.2), 0.3), pos + Vector3(0, r * (0.25 if hemi else 0.0), 0))
	var dz: float = -1.0 if forward else 1.0
	for gx in [-r * 0.28, r * 0.28]:
		var gl: float = r * 1.9
		var b := cyl(body, 0.025, 0.022, gl, pos + Vector3(gx, r * (0.3 if hemi else 0.0), dz * (r * 0.5 + gl * 0.5)), mat(DARKMETAL, 0.5), Vector3(90, 0, 0), 6, "TurretGun")
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


static func gondola(body: Node3D, pos: Vector3, size: Vector3, skin: Color, glass: Material) -> void:
	## Ventral gondola (He 111 / Ju 88 / Fw 200 "Bola"): a rounded fairing with glazed front and rear gun windows.
	var hw: float = size.x * 0.5
	var hh: float = size.y * 0.5
	var zf: float = pos.z - size.z * 0.5
	var zb: float = pos.z + size.z * 0.5
	var top: float = pos.y + hh
	var rings: Array = []
	for st in [[0.0, 0.5, 0.35], [0.12, 0.92, 0.9], [0.3, 1.0, 1.0], [0.75, 0.95, 0.9], [0.92, 0.7, 0.55], [1.0, 0.4, 0.25]]:
		var h2: float = hh * float(st[2])
		rings.append(MeshUtil.ring_xy(lerpf(zf, zb, float(st[0])), hw * float(st[1]), h2, top - h2, 14))
	_mi(body, MeshUtil.loft_smooth(rings, 2, 1), mat(skin, 0.5), Vector3.ZERO, "Gondola", true)
	for z in [zf + size.z * 0.1, zb - size.z * 0.08]:
		var win := SphereMesh.new()
		win.radius = hw * 0.75
		win.height = hh * 1.3
		win.radial_segments = 12
		win.rings = 6
		_mi(body, win, glass, Vector3(pos.x, top - hh * 1.0, z), "GondolaGlass")
	cyl(body, 0.022, 0.02, 0.7, Vector3(pos.x, top - hh, zb + 0.2), mat(DARKMETAL, 0.5), Vector3(90, 0, 0), 6, "GondolaGun")
