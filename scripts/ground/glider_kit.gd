class_name GliderKit
extends RefCounted
## Assault gliders left in the landing zones after the great airborne landings, and the parachutes on the dropping
## zones for the first couple of days (data/airborne_landings.json):
##  * Normandy, 6-7 June 1944: Pegasus and Horsa bridges, LZ N and LZ W round Ranville (Tonga, Mallard), the American
##    LZ E and LZ W round Hiesville and Les Forges behind Utah (Chicago, Elmira, Keokuk, Galveston, Hackensack);
##  * Market Garden, 17-19 September 1944: Wolfheze, Renkum heath and Johannahoeve (Arnhem), Groesbeek, Son;
##  * Varsity, 24 March 1945: the landing zones round Hamminkeln.
##
## From the RAF/USAAF photographs of the zones: gliders scattered in every direction across the fields, many nosed
## into the hedges, Horsa tails unbolted and lying beside the fuselage where the loads were taken out, wrecks with the
## fuselage broken in two and a wing folded. Wings and rear fuselages carry the black-and-white invasion stripes.
## They stayed for weeks (the Normandy fields were cleared through the summer; the Arnhem zones were not touched until
## after the war).
##
## Cost: one MultiMesh per glider type and state per landing zone (at most 9), 4 km fade; parachutes one MultiMesh.

const JSON_PATH := "res://data/airborne_landings.json"
const VIS := 4000.0
const STATES := ["intact", "tailoff", "wreck"]

static var _rows: Array = []


static func rows() -> Array:
	if _rows.is_empty():
		var f: FileAccess = FileAccess.open(JSON_PATH, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_rows = (d as Dictionary).get("zones", [])
	return _rows


## Build one zone for the current war date (empty node when the date is outside its window).
static func build(row: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "LZ_" + str(row["id"])
	var from: String = str(row.get("from", ""))
	var to: String = str(row.get("to", ""))
	var kind: String = str(row.get("kind", "lz"))
	var c: Vector3 = WorldCoords.latlon_to_world(float(row["lat"]), float(row["lon"]))
	var rx: float = float(row.get("rx", 400.0))
	var rz: float = float(row.get("rz", 300.0))
	var head: float = deg_to_rad(float(row.get("heading", 0.0)))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(row["id"]))
	var basis := Basis(Vector3.UP, -head)
	if kind == "dz":
		# parachutes on the dropping zone, only for two days after the drop
		if not EraClock.is_between(from, to):
			return root
		var chutes: Array = []
		for i in int(row.get("count", 200)):
			var lp := Vector3(rng.randf_range(-rx, rx), 0.0, rng.randf_range(-rz, rz))
			if (lp.x * lp.x) / (rx * rx) + (lp.z * lp.z) / (rz * rz) > 1.0:
				continue
			var p: Vector3 = c + basis * lp
			p.y = GroundKit.ground_y(p.x, p.z) + 0.12
			chutes.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * rng.randf_range(0.8, 1.15)), p))
		root.add_child(Scatter.multi(parachute_mesh(), chutes, 2500.0))
		return root
	if not EraClock.is_between(from, to):
		return root
	# gliders: scattered across the zone, roughly along the landing run, some swung round or nosed into hedges
	var buckets: Dictionary = {}
	var types: Dictionary = row.get("types", {"horsa": 10})
	var placed: Array = []
	for t in types.keys():
		var n: int = int(types[t])
		for i in n:
			var lp2 := Vector3.ZERO
			var ok: bool = false
			for tries in 12:
				lp2 = Vector3(rng.randf_range(-rx, rx), 0.0, rng.randf_range(-rz, rz))
				if (lp2.x * lp2.x) / (rx * rx) + (lp2.z * lp2.z) / (rz * rz) > 1.0:
					continue
				ok = true
				for q in placed:
					if (q as Vector3).distance_to(lp2) < 26.0:
						ok = false
						break
				if ok:
					break
			if not ok:
				continue
			placed.append(lp2)
			var p2: Vector3 = c + basis * lp2
			if GroundKit.raw_y(p2.x, p2.z) < 0.8:
				continue      # never in the sea or a flooded river
			p2.y = GroundKit.ground_y(p2.x, p2.z)
			var r: float = rng.randf()
			var st: String = "intact" if r < 0.45 else ("tailoff" if r < 0.75 and t != "waco" else "wreck")
			var yaw: float = -head + rng.randf_range(-0.5, 0.5) + (PI * rng.randf_range(-0.6, 0.6) if st == "wreck" else 0.0)
			var key: String = "%s_%s" % [t, st]
			if not buckets.has(key):
				buckets[key] = []
			(buckets[key] as Array).append(Transform3D(Basis(Vector3.UP, yaw), p2))
	for key in buckets.keys():
		var parts: PackedStringArray = str(key).split("_")
		root.add_child(Scatter.multi(glider_mesh(parts[0], parts[1]), buckets[key], VIS))
	return root


# ------------------------------------------------------------------ meshes (nose towards -Z, ground at y = 0)
static func _keep(key: String, parts: Array) -> ArrayMesh:
	var m: ArrayMesh = AirfieldAssets._build(parts)
	Scatter._meshes[key] = m
	return m


## Invasion stripes: three white and two black bands, centred at z, across a member `w` wide (x) at height y.
## along_x: bands stacked along the span (wings: each band runs fore and aft across the chord `w`).
static func _stripes(parts: Array, x: float, y: float, z: float, w: float, h: float, band: float, rot: Vector3 = Vector3.ZERO, along_x: bool = false) -> void:
	for i in 5:
		var col: Color = Color(0.86, 0.86, 0.82) if i % 2 == 0 else Color(0.08, 0.08, 0.08)
		var o: float = (float(i) - 2.0) * band
		if along_x:
			parts.append(GroundKit.box_part(Vector3(band, h, w), Vector3(x + o, y, z), col, rot, false))
		else:
			parts.append(GroundKit.box_part(Vector3(w, h, band), Vector3(x, y, z + o), col, rot, false))


## state: intact (sitting on its wheels / skid), tailoff (Horsa / Hamilcar with the rear fuselage unbolted and lying
## alongside for unloading), wreck (fuselage broken in two, one wing folded under, nose crushed).
static func glider_mesh(type: String, state: String) -> ArrayMesh:
	var key: String = "glider_%s_%s" % [type, state]
	if Scatter._meshes.has(key):
		return Scatter._meshes[key]
	var parts: Array = []
	match type:
		"hamilcar":
			_hamilcar(parts, state)
		"waco":
			_waco(parts, state)
		_:
			_horsa(parts, state)
	return _keep(key, parts)


static func _horsa(parts: Array, state: String) -> void:
	var green := Color(0.24, 0.27, 0.18)
	var earth := Color(0.34, 0.29, 0.20)
	var black := Color(0.07, 0.07, 0.07)
	var glass := Color(0.20, 0.24, 0.26)
	var wreck: bool = state == "wreck"
	var tilt: Vector3 = Vector3(0, 0, 8) if wreck else Vector3.ZERO
	var y0: float = 1.0 if wreck else 1.7
	# fuselage: a long cylinder, the cockpit glazing at the nose
	var fl: float = 10.5 if state != "intact" else 15.5
	parts.append(GroundKit.cyl_part(1.45, 1.45, fl, Vector3(0, y0, -10.2 + fl * 0.5), green, Vector3(90, 0, 0) + tilt, 10))
	parts.append(GroundKit.cyl_part(0.4, 1.45, 2.4, Vector3(0, y0, -11.4), glass if not wreck else black, Vector3(-90, 0, 0), 10))
	if state == "intact":
		parts.append(GroundKit.cyl_part(1.45, 0.5, 4.5, Vector3(0, y0 + 0.3, 7.5), green, Vector3(90, 0, 0), 10))
		parts.append(GroundKit.box_part(Vector3(0.25, 4.0, 3.4), Vector3(0, y0 + 2.3, 8.8), earth))       # fin
		parts.append(GroundKit.box_part(Vector3(9.0, 0.2, 2.6), Vector3(0, y0 + 0.6, 9.0), earth))        # tailplane
		_stripes(parts, 0.0, y0, 3.5, 3.0, 3.0, 0.55)
	elif state == "tailoff":
		# the rear fuselage lying on the grass beside the open joint
		parts.append(GroundKit.cyl_part(1.45, 0.5, 6.0, Vector3(3.6, 1.45, 4.0), green, Vector3(90, 22, 0), 10))
		parts.append(GroundKit.box_part(Vector3(0.25, 4.0, 3.4), Vector3(4.6, 3.5, 6.0), earth, Vector3(0, 22, 0)))
		parts.append(GroundKit.box_part(Vector3(9.0, 0.2, 2.6), Vector3(4.8, 2.0, 6.2), earth, Vector3(0, 22, 0)))
		parts.append(GroundKit.box_part(Vector3(0.6, 0.2, 5.0), Vector3(0.0, 0.25, 3.0), Color(0.42, 0.33, 0.22), Vector3(-10, 0, 0), false))   # unloading ramp
	else:
		parts.append(GroundKit.cyl_part(1.45, 0.5, 6.0, Vector3(1.2, 1.1, 6.6), green, Vector3(84, 0, -15), 10))
		parts.append(GroundKit.box_part(Vector3(0.25, 4.0, 3.4), Vector3(1.0, 3.0, 8.2), earth, Vector3(0, 0, -30)))
	# high wing with flaps line; the wreck has the port wing folded down into the ground
	var wy: float = y0 + 1.6
	if wreck:
		parts.append(GroundKit.box_part(Vector3(13.0, 0.4, 3.6), Vector3(7.0, wy - 0.4, -3.0), green, Vector3(0, 8, -9)))
		parts.append(GroundKit.box_part(Vector3(12.0, 0.4, 3.6), Vector3(-6.5, wy - 1.3, -2.4), green, Vector3(0, -14, 24)))
		_stripes(parts, 7.0, wy - 0.15, -3.0, 3.8, 0.42, 0.5, Vector3(0, 8, -9), true)
	else:
		parts.append(GroundKit.box_part(Vector3(26.8, 0.45, 3.8), Vector3(0, wy, -3.0), green))
		parts.append(GroundKit.box_part(Vector3(9.0, 0.47, 3.8), Vector3(-7.0, wy + 0.01, -3.0), earth, Vector3.ZERO, false))
		for sx in [-1.0, 1.0]:
			_stripes(parts, sx * 8.0, wy + 0.03, -3.0, 3.82, 0.47, 0.62, Vector3.ZERO, true)
		# undercarriage
		for sx2 in [-1.0, 1.0]:
			parts.append(GroundKit.cyl_part(0.45, 0.45, 0.3, Vector3(sx2 * 1.6, 0.45, -2.6), black, Vector3(0, 0, 90), 8, false))
		parts.append(GroundKit.cyl_part(0.35, 0.35, 0.25, Vector3(0, 0.35, -9.5), black, Vector3(0, 0, 90), 8, false))


static func _hamilcar(parts: Array, state: String) -> void:
	var green := Color(0.23, 0.26, 0.17)
	var earth := Color(0.34, 0.29, 0.20)
	var black := Color(0.07, 0.07, 0.07)
	var wreck: bool = state == "wreck"
	var y0: float = 2.2 if not wreck else 1.6
	parts.append(GroundKit.box_part(Vector3(3.6, 3.6, 13.0), Vector3(0, y0, -2.5), green))                     # box fuselage
	parts.append(GroundKit.box_part(Vector3(3.2, 3.0, 2.0), Vector3(0, y0, -9.6), green, Vector3(0, 30 if state == "tailoff" else 0, 0)))   # nose door (swung open after unloading)
	parts.append(GroundKit.box_part(Vector3(1.4, 0.9, 1.4), Vector3(0, y0 + 2.2, -6.0), Color(0.20, 0.24, 0.26)))   # cockpit on top
	if not wreck:
		parts.append(GroundKit.cyl_part(1.6, 0.4, 7.0, Vector3(0, y0 + 0.6, 7.5), green, Vector3(90, 0, 0), 8))
		parts.append(GroundKit.box_part(Vector3(0.3, 4.5, 3.6), Vector3(0, y0 + 3.0, 10.0), earth))
		parts.append(GroundKit.box_part(Vector3(11.0, 0.25, 3.0), Vector3(0, y0 + 1.0, 10.2), earth))
		parts.append(GroundKit.box_part(Vector3(33.5, 0.5, 4.6), Vector3(0, y0 + 2.2, -3.0), green))
		parts.append(GroundKit.box_part(Vector3(11.0, 0.52, 4.6), Vector3(9.0, y0 + 2.21, -3.0), earth, Vector3.ZERO, false))
		for sx in [-1.0, 1.0]:
			_stripes(parts, sx * 10.0, y0 + 2.24, -3.0, 4.62, 0.52, 0.7, Vector3.ZERO, true)
			parts.append(GroundKit.cyl_part(0.6, 0.6, 0.4, Vector3(sx * 2.4, 0.6, -2.0), black, Vector3(0, 0, 90), 8, false))
		_stripes(parts, 0.0, y0, 3.6, 3.62, 3.62, 0.6)
	else:
		parts.append(GroundKit.cyl_part(1.6, 0.4, 7.0, Vector3(2.0, 1.4, 7.0), green, Vector3(80, 0, -20), 8))
		parts.append(GroundKit.box_part(Vector3(16.0, 0.5, 4.6), Vector3(8.5, y0 + 1.6, -3.0), green, Vector3(0, 5, -7)))
		parts.append(GroundKit.box_part(Vector3(15.0, 0.5, 4.6), Vector3(-8.0, 0.8, -1.5), green, Vector3(0, -18, 12)))


static func _waco(parts: Array, state: String) -> void:
	var od := Color(0.30, 0.31, 0.21)
	var star := Color(0.86, 0.86, 0.82)
	var black := Color(0.07, 0.07, 0.07)
	var wreck: bool = state == "wreck"
	var y0: float = 1.2 if not wreck else 0.8
	parts.append(GroundKit.box_part(Vector3(1.8, 1.9, 8.0), Vector3(0, y0, -2.0), od, Vector3(0, 0, 6) if wreck else Vector3.ZERO))   # boxy fuselage
	parts.append(GroundKit.box_part(Vector3(1.7, 1.4, 1.6), Vector3(0, y0 + 0.4 if not wreck else 0.6, -6.6), Color(0.2, 0.24, 0.26), Vector3(18 if not wreck else 40, 0, 0)))   # glazed nose (hinged up for unloading)
	parts.append(GroundKit.cyl_part(0.9, 0.25, 6.0, Vector3(0, y0 + 0.4, 4.8), od, Vector3(90, 0, 0) if not wreck else Vector3(80, 0, -18), 6))
	if not wreck:
		parts.append(GroundKit.box_part(Vector3(0.2, 2.2, 2.2), Vector3(0, y0 + 1.6, 7.4), od))
		parts.append(GroundKit.box_part(Vector3(6.0, 0.15, 1.8), Vector3(0, y0 + 0.6, 7.6), od))
		parts.append(GroundKit.box_part(Vector3(25.5, 0.3, 2.6), Vector3(0, y0 + 1.25, -2.4), od))
		for sx in [-1.0, 1.0]:
			_stripes(parts, sx * 8.0, y0 + 1.42, -2.4, 2.62, 0.3, 0.45, Vector3.ZERO, true)
			parts.append(GroundKit.box_part(Vector3(0.1, 0.1, 4.4), Vector3(sx * 3.2, y0 + 0.4, -2.4), od, Vector3(0, 0, sx * 40.0), false))   # wing strut
			parts.append(GroundKit.cyl_part(0.4, 0.4, 0.2, Vector3(sx * 1.3, 0.4, -2.6), black, Vector3(0, 0, 90), 8, false))
		parts.append(GroundKit.cyl_part(0.45, 0.45, 0.04, Vector3(0.92, y0, 1.0), star, Vector3(0, 0, 90), 10, false))
		_stripes(parts, 0.0, y0 + 0.3, 2.6, 1.82, 1.3, 0.4)
	else:
		parts.append(GroundKit.box_part(Vector3(12.0, 0.3, 2.6), Vector3(6.4, y0 + 0.9, -2.0), od, Vector3(0, 10, -6)))
		parts.append(GroundKit.box_part(Vector3(11.0, 0.3, 2.6), Vector3(-6.0, 0.5, -1.0), od, Vector3(0, -22, 18)))


## A collapsed parachute canopy lying in the grass (7 m across), white / khaki / camouflage.
static func parachute_mesh() -> ArrayMesh:
	if Scatter._meshes.has("parachute_flat"):
		return Scatter._meshes["parachute_flat"]
	var parts: Array = []
	parts.append(GroundKit.cyl_part(3.2, 3.5, 0.15, Vector3(0, 0.05, 0), Color(0.82, 0.80, 0.72), Vector3.ZERO, 10, false))
	parts.append(GroundKit.cyl_part(1.4, 1.6, 0.17, Vector3(1.2, 0.07, 0.6), Color(0.48, 0.47, 0.34), Vector3.ZERO, 8, false))
	parts.append(GroundKit.box_part(Vector3(0.6, 0.2, 0.4), Vector3(-3.8, 0.1, 0.2), Color(0.30, 0.31, 0.22), Vector3.ZERO, false))   # harness / kit bag
	return _keep("parachute_flat", parts)
