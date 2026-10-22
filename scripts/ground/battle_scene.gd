class_name BattleScene
extends Node3D
## Scripted amphibious battle dressing for the D-Day and Dunkirk missions. Add under the world root (origin).
## cfg: {kind: "dday"|"dunkirk", beaches: [names], phase: "predawn"|"assault"|"buildup"|"counter", intensity: 0..2}
## D-Day: landing-craft waves running in on each beach, battleship / cruiser / destroyer bombardment, rocket
## ripples, shells and bombs walking the beach, burning wrecks, Shermans at the waterline, German bunkers,
## panzers and flak behind the dunes. Dunkirk: the Mole with ferries alongside, burning oil tanks, troop queues
## on the sand and wading into the sea, little ships shuttling, destroyers offshore, stukas' bombs, wrecks.
## Positions are real lat/lon; the shoreline is found on the actual terrain at run time.

# name -> {lat, lon (a point on the beach), out (seaward direction in world XZ), half (half width in world units)}
const DDAY := {
	"utah": {"lat": 49.425, "lon": -1.172, "out": Vector2(0.95, -0.3), "half": 900.0},
	"omaha": {"lat": 49.371, "lon": -0.870, "out": Vector2(0.0, -1.0), "half": 1300.0},
	"gold": {"lat": 49.338, "lon": -0.590, "out": Vector2(0.0, -1.0), "half": 1100.0},
	"juno": {"lat": 49.333, "lon": -0.455, "out": Vector2(0.0, -1.0), "half": 800.0},
	"sword": {"lat": 49.291, "lon": -0.285, "out": Vector2(0.0, -1.0), "half": 1000.0},
}
const DUNKIRK := {
	"malo": {"lat": 51.057, "lon": 2.395, "out": Vector2(-0.3, -1.0), "half": 1200.0},
	"bray": {"lat": 51.078, "lon": 2.520, "out": Vector2(-0.3, -1.0), "half": 1400.0},
	"lapanne": {"lat": 51.093, "lon": 2.585, "out": Vector2(-0.3, -1.0), "half": 1200.0},
	"mole": {"lat": 51.041, "lon": 2.362, "out": Vector2(0.0, -1.0), "half": 500.0},
}

var cfg: Dictionary = {}
var kind: String = "dday"
var phase: String = "assault"
var intensity: float = 1.0
var _t: float = 0.0
var _tick: float = 0.0
var _beaches: Array = []
var _craft: Array = []
var _warships: Array = []
var _built: bool = false
var _rng := RandomNumberGenerator.new()


static func create(p_cfg: Dictionary) -> BattleScene:
	var b := BattleScene.new()
	b.cfg = p_cfg
	b.name = "BattleScene"
	return b


func _ready() -> void:
	_rng.seed = hash(str(cfg))
	kind = str(cfg.get("kind", "dday"))
	phase = str(cfg.get("phase", "assault"))
	intensity = float(cfg.get("intensity", 1.0))
	call_deferred("_build")


# ------------------------------------------------------------------ geometry helpers
func _w(lat: float, lon: float) -> Vector3:
	return WorldCoords.latlon_to_world(lat, lon)


## Find the waterline for a beach spec by walking from its point seaward.
func _make_beach(name_: String, spec: Dictionary) -> Dictionary:
	var c: Vector3 = _w(float(spec["lat"]), float(spec["lon"]))
	var o2: Vector2 = (spec["out"] as Vector2).normalized()
	var out := Vector3(o2.x, 0.0, o2.y)
	var p: Vector3 = c
	var guard: int = 0
	while GroundKit.is_water(p.x, p.z) and guard < 300:      # started in the sea: come ashore first
		p -= out * 20.0
		guard += 1
	guard = 0
	while not GroundKit.is_water(p.x, p.z) and guard < 400:  # walk out to the surf line
		p += out * 20.0
		guard += 1
	var shore: Vector3 = p - out * 20.0
	shore.y = 0.0
	return {"name": name_, "shore": shore, "out": out, "lat": Vector3(-out.z, 0.0, out.x), "half": float(spec["half"]), "cache": {}}


## Seaward offset of the local waterline at this lateral position, relative to the beach's base shore point.
## Coasts curve, so everything is placed against the shoreline found at its own lateral position.
func _shore_off(b: Dictionary, lateral: float) -> float:
	var key: int = int(roundf(lateral / 30.0))
	var cache: Dictionary = b["cache"]
	if cache.has(key):
		return float(cache[key])
	var out: Vector3 = b["out"]
	var base: Vector3 = (b["shore"] as Vector3) + (b["lat"] as Vector3) * (float(key) * 30.0)
	var off: float = 0.0
	var guard: int = 0
	var p: Vector3 = base
	if GroundKit.is_water(p.x, p.z):
		while GroundKit.is_water(p.x, p.z) and guard < 120:
			p -= out * 20.0
			off -= 20.0
			guard += 1
		off += 20.0
	else:
		while not GroundKit.is_water(p.x, p.z) and guard < 120:
			p += out * 20.0
			off += 20.0
			guard += 1
		off -= 20.0
	cache[key] = off
	return off


func _pt(b: Dictionary, along: float, lateral: float) -> Vector3:
	var p: Vector3 = (b["shore"] as Vector3) + (b["out"] as Vector3) * (along + _shore_off(b, lateral)) + (b["lat"] as Vector3) * lateral
	p.y = 0.0
	return p


func _land(b: Dictionary, along: float, lateral: float) -> Vector3:
	var p: Vector3 = _pt(b, along, lateral)
	p.y = GroundKit.ground_y(p.x, p.z)
	return p


func _add_vehicle(vt: String, team: String, p: Vector3, yaw: float, mode: String, wrecked: bool = false) -> GroundVehicle:
	var v: GroundVehicle = GroundVehicle.create(vt, team, null, 0.0, 0.0, mode)
	v.position = p
	v.rotation.y = yaw
	v.start_wrecked = wrecked
	add_child(v)
	if wrecked:
		GroundKit.persistent_smoke(v, Vector3(0, 2.0, 0), _rng.randf_range(0.7, 1.3), true)
	return v


## A tall, thick column of black smoke with fire at its foot (FX blaze), bound to a holder node.
func _pillar(p: Vector3, size: float, plume: float) -> void:
	# a tall, tight, near-black column: a pre-built chain of lumpy spheres (one mesh, no per-frame cost)
	var mi := MeshInstance3D.new()
	mi.mesh = _pillar_mesh(_rng.randi() % 3)
	mi.material_override = _pillar_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var s: float = clampf(size * 0.22 + plume * 0.03, 0.8, 1.5)
	mi.position = Vector3(p.x, GroundKit.ground_y(p.x, p.z) - 2.0, p.z)
	mi.rotation.y = _rng.randf() * TAU
	mi.scale = Vector3(s * _rng.randf_range(0.8, 1.15), _rng.randf_range(0.8, 1.25), s * _rng.randf_range(0.8, 1.15))
	mi.extra_cull_margin = 2000.0
	add_child(mi)


static var _pillar_meshes: Array = []
static var _pillar_material: ShaderMaterial


## Soft translucent smoke (shaders/fx_column.gdshader); FX keeps its night darkening and haze up to date.
static func _pillar_mat() -> ShaderMaterial:
	if _pillar_material == null:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/fx_column.gdshader") as Shader
		_pillar_material = m
	return _pillar_material


static func _pillar_mesh(variant: int) -> ArrayMesh:
	while _pillar_meshes.size() <= variant:
		var rng := RandomNumberGenerator.new()
		rng.seed = 9100 + _pillar_meshes.size() * 17
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 10
		sm.rings = 6
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n: int = 64          # many overlapping puffs: a continuous column, not a string of beads
		var height: float = 520.0   # world units (~1 km)
		var lean := Vector3(0.45, 0.0, 0.18)
		for k in n:
			var t: float = float(k) / float(n - 1)
			var c: Vector3 = Vector3(0.0, t * height, 0.0) + lean * (t * t * height * 0.5)
			c += Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * (3.0 + t * 12.0)
			var r: float = lerpf(7.5, 21.0, pow(t, 0.8)) * rng.randf_range(0.85, 1.2)
			var d: float = lerpf(0.035, 0.30, pow(t, 1.2))
			var col := Color(d, d * 0.97, d * 0.95, 1.0)
			# a few extra lumps at the foot make a thick boiling base
			var tr := Transform3D(Basis().scaled(Vector3(r, r * 1.1, r)), c)
			var mesh_arr: Array = sm.get_mesh_arrays()
			var cols := PackedColorArray()
			cols.resize((mesh_arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			cols.fill(col)
			mesh_arr[Mesh.ARRAY_COLOR] = cols
			var tmp := ArrayMesh.new()
			tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arr)
			st.append_from(tmp, 0, tr)
		st.generate_normals()
		_pillar_meshes.append(st.commit())
	return _pillar_meshes[variant]


## Smoke pillars littering a stretch of coast: along the beach, in the dunes and well inland.
func _coast_smoke(b: Dictionary, count: int, depth_lo: float, depth_hi: float, big: float) -> void:
	var half: float = float(b["half"])
	for i in count:
		var lat: float = lerpf(-half * 1.15, half * 1.15, (float(i) + _rng.randf()) / float(count))
		var p: Vector3 = _land(b, _rng.randf_range(depth_lo, depth_hi), lat)
		if GroundKit.is_water(p.x, p.z):
			continue
		_pillar(p, _rng.randf_range(3.0, 5.0) * big, _rng.randf_range(9.0, 16.0))


func _yaw_facing(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


func _add_ship(st: String, team: String, a: Vector3, b: Vector3, start_s: float, spd: float, wrecked: bool = false) -> GroundShip:
	var r: RoutePath = RoutePath.from_points(PackedVector3Array([a, b]))
	var sh: GroundShip = GroundShip.create(st, team, r, start_s, spd)
	sh.position = Vector3(a.x, 0.1, a.z)
	sh.start_wrecked = wrecked
	add_child(sh)
	if not wrecked:
		var big: float = {"landing_craft": 4.2, "fishing_boat": 3.6, "trawler": 3.2, "destroyer": 2.6, "cruiser": 2.8, "battleship": 3.0,
			"freighter": 2.6, "collier": 2.6, "ferry": 2.8}.get(st, 2.4)
		sh.scale = Vector3.ONE * big      # exaggerated so fleets and waves read from altitude
		sh.hit_radius *= big / 1.8
	if wrecked:
		sh.set_process(false)
		sh.rotation.z = deg_to_rad(_rng.randf_range(10.0, 20.0))
		sh.position.y = -2.0
		GroundKit.persistent_smoke(sh, Vector3(0, 8.0, 0), _rng.randf_range(1.0, 1.8), true)
	return sh


# ------------------------------------------------------------------ build
func _build() -> void:
	if _built:
		return
	_built = true
	var names: Array = cfg.get("beaches", DDAY.keys() if kind == "dday" else DUNKIRK.keys())
	var table: Dictionary = DDAY if kind == "dday" else DUNKIRK
	for n in names:
		if table.has(n):
			_beaches.append(_make_beach(str(n), table[n]))
	for b in _beaches:
		if kind == "dday":
			_build_dday_beach(b)
		else:
			_build_dunkirk_beach(b)
	print("[battle] built ", kind, " beaches=", _beaches.size(), " nodes=", get_child_count(), " craft=", _craft.size())


func _hedgehog_mesh() -> ArrayMesh:
	var parts: Array = []
	var c: Color = Color(0.18, 0.17, 0.16)
	for r in [Vector3(0, 0, 0), Vector3(0, 0, 90), Vector3(90, 0, 0)]:
		parts.append(GroundKit.box_part(Vector3(0.9, 0.9, 5.0), Vector3(0, 1.6, 0), c, r + Vector3(35, 25, 0), false))
	return GroundKit.combine(parts)


func _obstacles(b: Dictionary, along: float, step: float, jitter: float) -> void:
	var half: float = float(b["half"])
	var n: int = int(half * 2.0 / step)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _hedgehog_mesh()
	mm.instance_count = n
	for i in n:
		var p: Vector3 = _pt(b, along + _rng.randf_range(-jitter, jitter), -half + step * i + _rng.randf_range(-6.0, 6.0))
		p.y = maxf(GroundKit.raw_y(p.x, p.z), 0.0) - 0.5
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_dday_beach(b: Dictionary) -> void:
	var out: Vector3 = b["out"]
	var half: float = float(b["half"])
	var yaw_sea: float = _yaw_facing(out)           # facing the water
	var yaw_land: float = _yaw_facing(-out)
	var k: float = clampf(intensity, 0.4, 2.0)
	_obstacles(b, 40.0, 38.0, 25.0)
	# --- German strongpoints in the dunes and bluffs
	for i in int(5 * k):
		var lat: float = lerpf(-half, half, (i + 0.5) / (5.0 * k)) + _rng.randf_range(-60.0, 60.0)
		var s: GroundStructure = GroundStructure.create("bunker" if i % 2 == 0 else "pillbox", "Axis", _land(b, -90.0 - _rng.randf_range(0.0, 60.0), lat), -1.0)
		add_child(s)
	for i in int(2 * k):
		var a: AAGun = AAGun.create("mg" if i % 2 == 0 else "bofors", "Axis")
		a.position = _land(b, -170.0, _rng.randf_range(-half, half) * 0.8)
		add_child(a)
	# panzers and guns dug in behind the beach
	for i in int(3 * k):
		_add_vehicle("panzer4", "Axis", _land(b, -420.0 - _rng.randf_range(0, 380.0), _rng.randf_range(-half, half) * 0.9), yaw_sea + _rng.randf_range(-0.4, 0.4), "fire")
	for i in 2:
		_add_vehicle("artillery", "Axis", _land(b, -600.0, _rng.randf_range(-half, half) * 0.7), yaw_sea, "fire")
	if phase == "counter":
		for i in 3:
			_add_vehicle("tiger", "Axis", _land(b, -520.0 - i * 120.0, -half * 0.5 + i * half * 0.5), yaw_sea, "fire")
	# --- Allied armour and troops at the waterline (more of it once the beachhead is established)
	var ntank: int = 3 if phase in ["predawn"] else 6
	if phase in ["buildup", "counter"]:
		ntank = 9
	for i in int(ntank * (k * 0.6 + 0.4)):
		var lat2: float = lerpf(-half, half, (i + 0.5) / float(ntank)) + _rng.randf_range(-40.0, 40.0)
		var dd: bool = phase in ["assault", "predawn"] and i % 2 == 0
		var p: Vector3 = _land(b, -8.0 + (22.0 if dd else 0.0) - _rng.randf_range(0.0, 30.0), lat2)
		if dd:
			p = _pt(b, 18.0 + _rng.randf_range(0.0, 40.0), lat2)     # DD tanks swimming in the surf
			p.y = 0.15
		var tk: GroundVehicle = _add_vehicle("sherman", "Allies", p, yaw_land + _rng.randf_range(-0.3, 0.3), "idle" if dd else "fire")
		if dd:
			tk.scale = Vector3.ONE * 0.9
	for i in int(6 * k):
		_add_vehicle("troops", "Allies", _land(b, -2.0 - _rng.randf_range(0, 60.0), _rng.randf_range(-half, half) * 0.9), yaw_land, "idle")
	for i in 3:
		_add_vehicle("jeep" if i < 2 else "halftrack", "Allies", _land(b, -40.0 - i * 20.0, _rng.randf_range(-half, half) * 0.7), yaw_land, "idle")
	if phase in ["assault", "counter", "buildup"]:
		for i in int(4 * k):
			_add_vehicle(["truck", "sherman", "halftrack"][_rng.randi() % 3], "Allies", _land(b, _rng.randf_range(-30.0, -5.0), _rng.randf_range(-half, half)), _rng.randf() * TAU, "idle", true)
	# --- burning beach: smoke columns, the haze of the bombardment
	_coast_smoke(b, int(14 * k), -380.0, 10.0, 1.0)         # the beach itself
	_coast_smoke(b, int(7 * k), -1100.0, -380.0, 1.3)       # burning villages and batteries behind it
	# --- landing craft waves
	var route_len: float = 2600.0 if phase != "buildup" else 1500.0
	var rows: int = 6 if phase != "predawn" else 4
	var per_row: int = int(7 * (k * 0.5 + 0.5))
	var lo: float = 0.0
	var hi: float = 1.0
	match phase:
		"predawn":
			lo = 0.0
			hi = 0.3
		"buildup":
			lo = 0.55
			hi = 1.0
		"counter":
			lo = 0.3
			hi = 0.9
	for r in rows:
		var f: float = lerpf(lo, hi, float(r) / float(maxi(rows - 1, 1)))
		for j in per_row:
			var lat3: float = lerpf(-half * 0.85, half * 0.85, (j + 0.5) / float(per_row)) + _rng.randf_range(-25.0, 25.0)
			var st: String = "landing_craft"
			var from: Vector3 = _pt(b, route_len, lat3)
			var to: Vector3 = _pt(b, 12.0, lat3 + _rng.randf_range(-20.0, 20.0))
			var sh: GroundShip = _add_ship(st, "Allies", from, to, f * route_len + _rng.randf_range(-40.0, 40.0), _rng.randf_range(10.0, 13.0))
			_craft.append(sh)
	# a couple of hulks burning in the shallows
	for i in int(9 * k):
		var wp: Vector3 = _pt(b, _rng.randf_range(30.0, 500.0), _rng.randf_range(-half, half) * 0.9)
		_add_ship("landing_craft", "Allies", wp, wp + Vector3(6, 0, 0), 0.0, 0.01, true)
	# --- the fleet standing off: transports, bombardment squadron
	var fl_a: float = 4200.0 + _rng.randf_range(0.0, 400.0)
	for i in 9:
		var lat4: float = lerpf(-half * 1.3, half * 1.3, i / 8.0)
		var a1: Vector3 = _pt(b, fl_a + 1500.0 + (i % 3) * 420.0, lat4)
		_add_ship(["freighter", "collier", "freighter"][i % 3], "Allies", a1, a1 + Vector3(300, 0, 0), 0.0, 0.6)
	var heavies: Array = ["battleship", "cruiser", "destroyer", "destroyer", "cruiser", "destroyer", "destroyer", "battleship"]
	for i in heavies.size():
		var lat5: float = lerpf(-half * 1.3, half * 1.3, float(i) / 7.0)
		var a2: Vector3 = _pt(b, fl_a - 300.0 + (i % 3) * 420.0, lat5)
		var s2: GroundShip = _add_ship(heavies[i], "Allies", a2, a2 + Vector3((b["lat"] as Vector3).x, 0, (b["lat"] as Vector3).z) * 500.0, 0.0, 1.2)
		_warships.append(s2)
	# German E-boats / mines are not modelled; the sea belongs to the Allies here


func _build_dunkirk_beach(b: Dictionary) -> void:
	var out: Vector3 = b["out"]
	var half: float = float(b["half"])
	var yaw_sea: float = _yaw_facing(out)
	var k: float = clampf(intensity, 0.4, 2.0)
	if str(b["name"]) == "mole":
		_build_mole(b)
		return
	# --- the long queues: files of men on the sand and wading out into the shallows
	var nq: int = int(9 * (k * 0.5 + 0.5))
	for i in nq:
		var lat: float = lerpf(-half * 0.8, half * 0.8, (i + 0.5) / float(nq)) + _rng.randf_range(-40.0, 40.0)
		for j in 5:
			var along: float = -30.0 + j * 30.0                 # from the dunes down into the water
			var p: Vector3 = _pt(b, along, lat)
			p.y = maxf(GroundKit.raw_y(p.x, p.z), 0.0) + 0.1 if along < 8.0 else 0.1
			_add_vehicle("troops", "Allies", p, yaw_sea, "idle")
	for i in int(3 * k):
		_add_vehicle(["truck", "halftrack"][i % 2], "Allies", _land(b, -80.0 - _rng.randf_range(0, 90.0), _rng.randf_range(-half, half)), _rng.randf() * TAU, "idle", true)
	for i in int(6 * k):
		_add_vehicle(["truck", "car", "bus", "artillery"][_rng.randi() % 4], "Allies", _land(b, -20.0 - _rng.randf_range(0, 200.0), _rng.randf_range(-half, half)), _rng.randf() * TAU, "idle", true)
	# --- little ships shuttling to the shallows and out to the transports
	var small: Array = ["fishing_boat", "fishing_boat", "trawler", "landing_craft", "fishing_boat", "trawler"]
	for i in int(18 * k):
		var lat2: float = lerpf(-half, half, (i + 0.5) / (18.0 * k)) + _rng.randf_range(-30.0, 30.0)
		var from: Vector3 = _pt(b, 2300.0 + _rng.randf_range(0.0, 600.0), lat2)
		var to: Vector3 = _pt(b, 25.0, lat2)
		_craft.append(_add_ship(small[i % small.size()], "Allies", from, to, _rng.randf_range(0.0, 1900.0), _rng.randf_range(6.0, 10.0)))
	# --- waiting off the beach: destroyers, a paddle-less ferry or two, colliers
	for i in 8:
		var lat3: float = lerpf(-half * 1.2, half * 1.2, i / 7.0)
		var a: Vector3 = _pt(b, 2900.0 + (i % 3) * 420.0, lat3)
		var st: String = ["destroyer", "ferry", "collier", "ferry", "destroyer", "freighter", "ferry", "trawler"][i]
		var sh: GroundShip = _add_ship(st, "Allies", a, a + (b["lat"] as Vector3) * 400.0, 0.0, 1.0)
		if st == "destroyer":
			_warships.append(sh)
	for i in int(6 * k):
		var wp: Vector3 = _pt(b, _rng.randf_range(100.0, 900.0), _rng.randf_range(-half, half))
		_add_ship(["trawler", "freighter", "fishing_boat"][i % 3], "Allies", wp, wp + Vector3(5, 0, 0), 0.0, 0.01, true)
	# --- the perimeter: German guns and panzers inland (they shell the beaches)
	for i in int(3 * k):
		_add_vehicle("artillery", "Axis", _land(b, -2600.0 - _rng.randf_range(0, 500.0), _rng.randf_range(-half, half)), yaw_sea, "fire")
	for i in int(2 * k):
		_add_vehicle("panzer4", "Axis", _land(b, -2300.0 - _rng.randf_range(0, 400.0), _rng.randf_range(-half, half)), yaw_sea, "fire")
	_coast_smoke(b, int(12 * k), -500.0, 0.0, 1.0)
	_coast_smoke(b, int(6 * k), -1800.0, -500.0, 1.4)
	for i in 2:
		var a3: AAGun = AAGun.create("bofors" if i == 0 else "mg", "Allies")
		a3.position = _land(b, -60.0, _rng.randf_range(-half, half) * 0.6)
		add_child(a3)


func _build_mole(b: Dictionary) -> void:
	var out: Vector3 = b["out"]
	var lat: Vector3 = b["lat"]
	var yaw: float = _yaw_facing(out)
	# the East Mole: a narrow timber-and-concrete jetty running ~800 units out into the harbour mouth
	var length: float = 800.0
	var parts: Array = []
	var deck_c: Color = Color(0.4, 0.38, 0.34)
	parts.append(GroundKit.box_part(Vector3(9.0, 3.0, length), Vector3(0, 1.5, 0), deck_c, Vector3.ZERO, true))
	for i in 20:
		var z: float = -length * 0.5 + length * float(i) / 19.0
		parts.append(GroundKit.box_part(Vector3(12.0, 5.5, 2.0), Vector3(0, 2.8, z), Color(0.3, 0.28, 0.25), Vector3.ZERO, false))
	var mi := MeshInstance3D.new()
	mi.mesh = GroundKit.combine(parts)
	var centre: Vector3 = _pt(b, length * 0.5 - 20.0, 0.0)
	mi.position = centre
	mi.rotation.y = yaw
	add_child(mi)
	# destroyers and ferries alongside, men queued along the deck
	for i in 4:
		var side: float = 22.0 if i % 2 == 0 else -22.0
		var base: Vector3 = _pt(b, 120.0 + i * 170.0, side)
		var st: String = ["destroyer", "ferry", "ferry", "destroyer"][i]
		var p2: Vector3 = base + out * 40.0
		var sh: GroundShip = _add_ship(st, "Allies", base, p2, 0.0, 0.6)
		sh.rotation.y = yaw + PI * 0.5
		if st == "destroyer":
			_warships.append(sh)
	for i in 12:
		_add_vehicle("troops", "Allies", _pt(b, 40.0 + i * 55.0, _rng.randf_range(-2.0, 2.0)) + Vector3(0, 3.2, 0), yaw, "idle")
	# the burning oil tanks and warehouses of the port, black columns lying over the town
	var tanks: Array = [_w(51.034, 2.340), _w(51.028, 2.356), _w(51.040, 2.330), _w(51.031, 2.372)]
	for tp in tanks:
		var s: GroundStructure = GroundStructure.create("fuel_tank", "Axis", tp, 0.0)
		s.start_wrecked = true
		add_child(s)
		var holder := Node3D.new()
		holder.position = Vector3(tp.x, GroundKit.ground_y(tp.x, tp.z), tp.z)
		add_child(holder)
		_pillar(tp, 5.0, 16.0)
		_pillar(tp + Vector3(30, 0, 20), 4.0, 12.0)
		_pillar(tp + Vector3(-25, 0, 35), 3.5, 10.0)


# ------------------------------------------------------------------ the bombardment and raids, running
func _process(delta: float) -> void:
	if not _built:
		return
	_t += delta
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.3
	var pl: Node3D = GroundKit.player_node()
	var ppos: Vector3 = pl.global_position if pl != null else Vector3.ZERO
	var ramp: float = 0.45 + 0.55 * smoothstep(0.0, 240.0, _t)
	if phase == "predawn":
		ramp *= 0.75
	for b in _beaches:
		var centre: Vector3 = _pt(b, 0.0, 0.0)
		if pl != null and Vector2(centre.x - ppos.x, centre.z - ppos.z).length() > 14000.0:
			continue
		var rate: float = intensity * ramp * (1.7 if kind == "dday" else 1.0)
		for rep in 2:
			if _rng.randf() < rate * 0.7:
				_shell_on_beach(b)
			if _rng.randf() < rate * 0.5:
				_shell_in_sea(b)
		if kind == "dday" and _rng.randf() < rate * 0.1:
			_rocket_ripple(b)
		if _rng.randf() < rate * 0.35 and not _warships.is_empty():
			_naval_salvo()
		if _rng.randf() < rate * 0.05:
			_hit_a_craft()
		if kind == "dunkirk" and _rng.randf() < rate * 0.25:
			_stuka_stick(b)


func _shell_on_beach(b: Dictionary) -> void:
	var half: float = float(b["half"])
	var p: Vector3 = _land(b, _rng.randf_range(-320.0, 30.0), _rng.randf_range(-half, half))
	GroundKit.explosion(p + Vector3(0, 2.0, 0), _rng.randf_range(2.5, 5.0))
	GroundKit.fx_call("dust", [p, 5.0])
	if _rng.randf() < 0.18:
		GroundKit.fx_call("smoke_column", [p, _rng.randf_range(6.0, 10.0), 40.0])
	if _rng.randf() < 0.25:
		GroundKit.fx_call("debris", [p, 6, 2.0, 28.0])
	if _rng.randf() < 0.12:
		GroundKit.fx_call("crater", [p, 5.0])


func _shell_in_sea(b: Dictionary) -> void:
	var half: float = float(b["half"])
	var p: Vector3 = _pt(b, _rng.randf_range(30.0, 1500.0), _rng.randf_range(-half, half))
	GroundKit.fx_call("water_splash", [p, _rng.randf_range(5.0, 11.0)])


func _rocket_ripple(b: Dictionary) -> void:
	var half: float = float(b["half"])
	var lat0: float = _rng.randf_range(-half, half * 0.4)
	for i in 14:
		var p: Vector3 = _land(b, _rng.randf_range(-140.0, 10.0), lat0 + i * 45.0)
		var tw: SceneTreeTimer = get_tree().create_timer(i * 0.1)
		tw.timeout.connect(func() -> void:
			GroundKit.explosion(p + Vector3(0, 1.5, 0), 2.0)
			GroundKit.fx_call("dust", [p, 4.0]))


func _naval_salvo() -> void:
	var sh: GroundShip = _warships[_rng.randi() % _warships.size()] as GroundShip
	if sh == null or not is_instance_valid(sh) or sh.is_dead:
		return
	var f: float = 0.9 if sh.stype in ["battleship", "cruiser"] else 0.5
	var p: Vector3 = sh.global_position + Vector3(0, 7.0 * sh.scale.y, 0)
	GroundKit.explosion(p, f)
	GroundKit.fx_call("light_flash", [p, 6.0, 500.0, 0.25, Color(1.0, 0.8, 0.5)])


func _hit_a_craft() -> void:
	if _craft.is_empty():
		return
	var c: GroundShip = _craft[_rng.randi() % _craft.size()] as GroundShip
	if c != null and is_instance_valid(c) and not c.is_dead:
		c.die(null)


func _stuka_stick(b: Dictionary) -> void:
	var half: float = float(b["half"])
	var a: Vector3 = _pt(b, _rng.randf_range(-60.0, 600.0), _rng.randf_range(-half, half))
	var d: Vector3 = (b["lat"] as Vector3)
	for i in 4:
		var p: Vector3 = a + d * i * 28.0
		var wet: bool = GroundKit.is_water(p.x, p.z)
		var tw: SceneTreeTimer = get_tree().create_timer(i * 0.16)
		tw.timeout.connect(func() -> void:
			if wet:
				GroundKit.fx_call("water_splash", [p, 9.0])
			else:
				GroundKit.explosion(p + Vector3(0, 2.0, 0), 1.6))
