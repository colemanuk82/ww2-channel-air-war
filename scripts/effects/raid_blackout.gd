class_name RaidBlackout
extends Node3D
## Civil defence while a town is raided. Driven by SkyWar, which passes its raid dictionary in each frame ({} when
## no raid is on):
##  * the raided town goes dark for a while (its windows drop out, fading back on), and every town dims further
##    for as long as the raid lasts - the shader reads raid_dim / raid_black_* (toon.gdshader);
##  * wardens' whistles at the start and at each new blackout, and distant fire-station bells now and then, all
##    scaled by how close the raid is (FX.audio.flat);
##  * a couple of fire engines and an ambulance run through the streets on the real roads, lamps flashing.
## Pure scenery. Shader globals are set every frame so a raid that ends snaps everything back to the nightly dimming.

const BLACKOUT_LEN: float = 22.0      # seconds the raided town is dark (the last few fade back on)
const BLACKOUT_FADE: float = 6.0
const BLACKOUT_EVERY: float = 70.0    # a fresh brief blackout this often while the raid lasts
const BELL_MIN: float = 25.0
const BELL_MAX: float = 45.0
const VEHICLES: int = 3               # two fire engines, one ambulance
const VEH_SPEED: float = 13.0
const VEH_SHOW_DIST: float = 6000.0
const RAID_DIM: float = 0.5           # how far every town dims while a raid is on
const HEARD_DIST: float = 22000.0     # beyond this the bells and whistles are silent

var _active: bool = false
var _city: Dictionary = {}
var _level: float = 0.0               # 0..1, how close the player is to the raided town
var _blk_t: float = 0.0               # seconds of the current blackout left
var _next_blk: float = 0.0
var _bell_t: float = 0.0
var _k_dim: float = 0.0
var _vehicles: Array = []             # {node, route, s, dir, lamp, kind, phase}
var _routes: Array = []               # RoutePath streets near the raided town
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	top_level = true
	_rng.randomize()
	_apply(0.0)


## Called every frame by SkyWar. raid = the live raid dictionary ({city, t_left, bomb_t}) or {}.
func update(delta: float, raid: Dictionary, player: Node3D) -> void:
	delta = minf(delta, 0.1)
	if not raid.is_empty() and not _active:
		_begin(raid)
	elif raid.is_empty() and _active:
		_end()
	if _active:
		if _spawn_left > 0:          # one emergency vehicle per frame: building all three at once stalled a frame
			_spawn_vehicle(VEHICLES - _spawn_left)
			_spawn_left -= 1
		_tick(delta, player)
	_apply(delta)


var _spawn_left: int = 0


func _begin(raid: Dictionary) -> void:
	_active = true
	_city = raid["city"]
	_blk_t = BLACKOUT_LEN
	_next_blk = BLACKOUT_EVERY
	_bell_t = _rng.randf_range(3.0, 8.0)
	var tr0: int = Time.get_ticks_usec()
	_routes = _find_routes()
	if Time.get_ticks_usec() - tr0 > 20000:
		print("[slow] blackout routes %d ms" % ((Time.get_ticks_usec() - tr0) / 1000))
	_spawn_left = VEHICLES
	FX.audio.flat("whistle_warden", lerpf(-32.0, -10.0, _level))


func _end() -> void:
	_active = false
	_blk_t = 0.0
	_spawn_left = 0
	for v in _vehicles:
		(v["node"] as Node3D).queue_free()
	_vehicles.clear()
	_routes.clear()


func _tick(delta: float, player: Node3D) -> void:
	var pp: Vector3 = player.global_position if player != null and is_instance_valid(player) else Vector3.ZERO
	var cp: Vector3 = _city["pos"]
	var dist: float = Vector2(cp.x - pp.x, cp.z - pp.z).length()
	_level = clampf(1.0 - dist / HEARD_DIST, 0.0, 1.0)
	# the brief blackout, repeated while the raid lasts
	_blk_t -= delta
	_next_blk -= delta
	if _next_blk <= 0.0:
		_next_blk = BLACKOUT_EVERY * _rng.randf_range(0.8, 1.2)
		_blk_t = BLACKOUT_LEN
		FX.audio.flat("whistle_warden", lerpf(-32.0, -10.0, _level))
	# fire-station bells carried over the town
	_bell_t -= delta
	if _bell_t <= 0.0:
		_bell_t = _rng.randf_range(BELL_MIN, BELL_MAX)
		if _level > 0.05:
			FX.audio.flat("fire_bell", lerpf(-34.0, -8.0, _level))
	for v in _vehicles:
		_drive(v, delta, pp)


# ------------------------------------------------------------------ shader state

func _apply(delta: float) -> void:
	var target: float = RAID_DIM if _active else 0.0
	_k_dim = move_toward(_k_dim, target, delta * 0.4)
	var k_loc: float = clampf(_blk_t / BLACKOUT_FADE, 0.0, 1.0) if _active else 0.0
	var centre: Vector3 = _city["pos"] if _active else Vector3.ZERO
	var rad: float = float(_city["r"]) if _active else 1.0
	RenderingServer.global_shader_parameter_set("raid_dim", _k_dim)
	RenderingServer.global_shader_parameter_set("raid_black_k", k_loc)
	RenderingServer.global_shader_parameter_set("raid_black_pos", centre)
	RenderingServer.global_shader_parameter_set("raid_black_r", rad)


# ------------------------------------------------------------------ vehicles

func _find_routes() -> Array:
	var out: Array = []
	if not RoadMesh.has_roads() or _city.is_empty():
		return out
	var cp: Vector3 = _city["pos"]
	var rad: float = float(_city["r"]) * 0.7
	# only the few longest streets: building a RoutePath for every street in a big town stalled a frame (~100 ms)
	var lns: Array = RoadMesh.routes_in_rect(Vector2(cp.x, cp.z), rad).filter(func(l: Dictionary) -> bool: return float(l["len"]) >= 250.0)
	lns.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["len"]) > float(y["len"]))
	for ln in lns.slice(0, 8):
		var pts3 := PackedVector3Array()
		for v in (ln["pts"] as PackedVector2Array):
			pts3.append(Vector3(v.x, 0.0, v.y))
		out.append(RoutePath.from_points(pts3))
	return out


## Fallback when no street data is loaded: a closed loop round the middle of the town.
func _ring_route() -> RoutePath:
	var cp: Vector3 = _city["pos"]
	var rad: float = float(_city["r"]) * 0.5
	var pts := PackedVector3Array()
	var a0: float = _rng.randf() * TAU
	for i in 13:
		var a: float = a0 + TAU * float(i) / 12.0
		pts.append(Vector3(cp.x + cos(a) * rad, 0.0, cp.z + sin(a) * rad))
	return RoutePath.from_points(pts)


func _spawn_vehicle(i: int) -> void:
	var kind: String = "fire" if i < 2 else "ambulance"
	var rp: RoutePath = _routes[_rng.randi() % _routes.size()] if not _routes.is_empty() else _ring_route()
	var node := Node3D.new()
	node.top_level = true
	add_child(node)
	var lamp: StandardMaterial3D = _build_vehicle(node, kind)
	_vehicles.append({"node": node, "route": rp, "s": _rng.randf() * rp.length,
		"dir": 1.0 if _rng.randf() < 0.5 else -1.0, "lamp": lamp, "kind": kind, "phase": _rng.randf() * 10.0})


func _drive(v: Dictionary, delta: float, pp: Vector3) -> void:
	var node: Node3D = v["node"]
	var rp: RoutePath = v["route"]
	var dir: float = float(v["dir"])
	if rp.length < 1.0:
		return
	var s: float = fposmod(float(v["s"]) + VEH_SPEED * dir * delta, rp.length)
	v["s"] = s
	var p: Vector3 = rp.sample(s)
	var t: Vector3 = rp.tangent(s) * dir
	node.global_position = Vector3(p.x, GroundKit.ground_y(p.x, p.z) + 0.6, p.z)
	node.rotation = Vector3(0.0, atan2(-t.x, -t.z), 0.0)
	node.visible = pp.distance_to(node.global_position) < VEH_SHOW_DIST
	# the light bar flashes: red for the fire engines, red and blue for the ambulance
	var ph: float = Time.get_ticks_msec() * 0.001 * 5.0 + float(v["phase"])
	var on_a: bool = sin(ph) > 0.0
	var lamp: StandardMaterial3D = v["lamp"]
	if str(v["kind"]) == "fire":
		lamp.albedo_color = Color(1.0, 0.12, 0.05) if on_a else Color(0.3, 0.03, 0.02)
	else:
		lamp.albedo_color = Color(1.0, 0.12, 0.05) if on_a else Color(0.1, 0.3, 1.0)


## Simple box vehicle, nose towards local -Z (the way GroundVehicle faces). Returns the light-bar material.
func _build_vehicle(root: Node3D, kind: String) -> StandardMaterial3D:
	var fire: bool = kind == "fire"
	var body: Color = Color(0.7, 0.12, 0.1) if fire else Color(0.93, 0.93, 0.9)
	var trim: Color = Color(0.85, 0.85, 0.8) if fire else Color(0.8, 0.12, 0.12)
	var wheel := Color(0.12, 0.12, 0.12)
	var lamp := StandardMaterial3D.new()
	lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp.albedo_color = Color(1.0, 0.12, 0.05)
	GroundKit.box(root, Vector3(2.4, 1.5, 5.4), Vector3(0, 1.3, 0.4), body)
	GroundKit.box(root, Vector3(2.4, 1.4, 1.9), Vector3(0, 1.2, -2.9), body)
	GroundKit.box(root, Vector3(2.46, 0.3, 4.6), Vector3(0, 1.9, 0.4), trim)
	var bar: MeshInstance3D = GroundKit.box(root, Vector3(1.3, 0.3, 0.4), Vector3(0, 2.25, -0.4), Color.WHITE)
	bar.material_override = lamp
	for sx in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(0.35, 0.9, 0.9), Vector3(sx * 1.3, 0.45, 2.0), wheel)
		GroundKit.box(root, Vector3(0.35, 0.9, 0.9), Vector3(sx * 1.3, 0.45, -1.9), wheel)
	if fire:
		GroundKit.box(root, Vector3(0.5, 0.25, 6.2), Vector3(0, 2.5, 0.6), Color(0.75, 0.75, 0.78))   # ladder
	return lamp
