class_name IntroCutscene
extends Node
## Opening cinematic, played once per launch before the start menu. A real-time film shot in the actual game world
## with the real aircraft models, told from both sides: Spitfires at dawn over the Dover cliffs, Bf 109s skimming the
## French hills, an Allied flight racing low through Folkestone, a Heinkel formation crossing the coast, Dover and
## Manston airfield bombed, a dogfight, a Spitfire hit, and the pilot coming down by parachute over the burning
## town as the title appears. Any key or click skips it. `await intro.finished`.

signal finished

static var shown: bool = false   # played once per launch

const DURATION := 99.0
const BAR := 0.115          # letterbox bar height as a fraction of the screen
# shot start times
const T_A := 12.0    # Spitfires along the Dover cliffs (shot 1 is the dawn take-off from Hawkinge)
const T_B := 19.0    # Luftwaffe fighters skimming the French hills
const T_C := 27.0    # Spitfires racing low through Folkestone
const T_N := 35.0    # night scramble from Manston in the rain
const T_D := 46.0    # bomber formation crosses the cliffs
const T_E := 54.0    # Dover under the bombs
const T_F := 63.0    # Manston airfield under the bombs
const T_G := 72.0    # dogfight
const T_H := 80.0    # the Spitfire is hit, the pilot bails
const T_I := 82.0    # the parachute
# time of day and weather per shot: [start, hour, weather]
const ENV := [
	[0.0, 6.35, "fog"],
	[12.0, 7.4, "scattered"],
	[19.0, 9.6, "rain"],
	[27.0, 12.3, "clear"],
	[35.0, 22.0, "rain"],
	[46.0, 19.3, "overcast"],
	[54.0, 18.85, "scattered"],
	[63.0, 22.3, "rain"],
	[72.0, 14.5, "scattered"],
	[80.0, 17.9, "scattered"],
]

var freeze: bool = false     # debug: hold the clock at the start time (screenshots)

var _cam: Camera3D
var _anchor: Node3D
var _t: float = 0.0
var _done: bool = false
var _layer: CanvasLayer
var _fade: ColorRect
var _caption: Label
var _title: Label
var _sub: Label
var _music: AudioStreamPlayer
var _sp: Array = []          # Allied flight (Spitfires)
var _ax: Array = []          # Luftwaffe skimmers (Bf 109)
var _bm: Array = []          # Heinkel formation
var _es: Array = []          # their escort
var _hero: Node3D
var _prey: Node3D
var _bullets: Array = []     # [MeshInstance3D, velocity, life]
var _bombs: Array = []       # [MeshInstance3D, velocity]
var _chute: Node3D = null
var _k: Vector3              # cliff-foot point at Dover
var _s: Vector3              # unit vector out to sea (south-east)
var _a: Vector3              # unit vector along the coast (north-east)
var _town: Vector3           # Dover town centre
var _manston: Vector3
var _cg: Vector3             # French coast point (Cap Gris Nez)
var _cgd: Vector3
var _fol: Vector3            # Folkestone
var _fold: Vector3
var _hit: bool = false
var _dead_prey: bool = false
var _hero_hit: bool = false
var _hero_vel: Vector3 = Vector3.ZERO
var _hero_boom: bool = false
var _bail: bool = false
var _time_t: float = 0.0
var _shake: float = 0.0
var _bomb_t: float = 0.0
var _start_at: float = 0.0
var _smoke_k: int = 0
var _rw_h: Dictionary = {}   # Hawkinge runway
var _rw_m: Dictionary = {}   # Manston runway
var _lamp: OmniLight3D
var _env_i: int = -1
var _terr: Node = null
var _terr_old: Array = []
var _dbg: bool = OS.get_cmdline_user_args().has("--intro-debug")
var _dbg_t: float = 0.0
var _last_boom: Vector3 = Vector3.ZERO
var _hold: float = 0.0       # after a cut to a new place: stay on black until its land has streamed in
var _warm: float = 0.0       # opening hold on black while the first location's land streams in
const PRELOAD := 4.5         # seconds before a far cut that the land starts streaming at the next location


func play(cam: Camera3D, anchor: Node3D, start_at: float = 0.0) -> void:
	_cam = cam
	_anchor = anchor
	_start_at = start_at
	_t = start_at
	process_mode = Node.PROCESS_MODE_ALWAYS
	_find_places()
	# stream terrain much faster while the film jumps around the coast (restored in _end)
	_terr = get_tree().current_scene.get("terrain") as Node
	if _terr != null and "max_inflight" in _terr:
		_terr_old = [_terr.get("max_inflight"), _terr.get("max_instantiate_per_frame")]
		_terr.set("max_inflight", 32)
		_terr.set("max_instantiate_per_frame", 16)
	_warm = 8.0 if start_at < 0.5 else 0.0
	if OS.get_cmdline_user_args().has("--intro-debug"):
		for nm in ["town", "manston", "fol", "k", "cg"]:
			var v: Vector3 = get(("_" + nm) as StringName)
			print("[introdbg] ", nm, " ", v, " water=", FX.is_water(v), " gh=", _gh(v))
		for rw in [_rw_h, _rw_m]:
			print("[introdbg] rw ", rw, " water=", FX.is_water(rw["c"]))
		for n in get_tree().get_nodes_in_group("airfield"):
			print("[introdbg] af ", n.get("airfield_name"), " ", (n as Node3D).global_position, " hdg=", n.get("heading_deg"))
		print("[introdbg] ll manston ", WorldCoords.latlon_to_world(51.3422, 1.3461), " hawk ", WorldCoords.latlon_to_world(51.115, 1.1494), " dover ", WorldCoords.latlon_to_world(51.125, 1.31))
	_build_actors()
	_build_ui()
	_build_music()
	set_process(true)


## True once the terrain chunk under `p` has streamed in at a close level of detail.
func _land_ready(p: Vector3) -> bool:
	if _terr == null or not is_instance_valid(_terr):
		return true
	var cs: float = float(_terr.get("chunk_size"))
	var ch: Dictionary = _terr.get("_chunks")
	var key := Vector2i(floori(p.x / cs), floori(p.z / cs))
	return ch.has(key) and int(ch[key]["lod"]) == 0


func _gh(p: Vector3) -> float:
	return maxf(FX.ground_height(p), 0.0)


func _find_places() -> void:
	# Dover: start on the high ground behind the cliffs and march out to sea to the first water
	var d := Vector3(0.66, 0.0, 0.75).normalized()
	_s = d
	_a = Vector3(d.z, 0.0, -d.x)
	var c: Vector3 = WorldCoords.latlon_to_world(51.135, 1.335)
	_k = c
	for i in 600:
		var p: Vector3 = c + d * float(i) * 20.0
		if FX.is_water(p):
			_k = p
			break
	_k.y = 0.0
	# town / airfield centres, taken from where the game places their buildings (WorldPopulator city_dover,
	# af_manston, city_folkestone)
	_town = Vector3(93400.0, 0.0, -91500.0)
	_manston = Vector3(95600.0, 0.0, -115300.0)
	# Cap Gris Nez: fly NW from the hills behind it out over the water
	var a0: Vector3 = WorldCoords.latlon_to_world(50.83, 1.62)
	var a1: Vector3 = WorldCoords.latlon_to_world(50.95, 1.45)
	_cgd = (a1 - a0)
	_cgd.y = 0.0
	_cgd = _cgd.normalized()
	_cg = a0
	for i in 600:
		var q: Vector3 = a0 + _cgd * float(i) * 20.0
		if FX.is_water(q):
			_cg = q
			break
	# Folkestone: fly SE through the middle of town
	_fol = Vector3(83166.0, 0.0, -86373.0)
	var f0: Vector3 = Vector3(81573.0, 0.0, -90603.0)      # Hawkinge
	_fold = (_fol - f0)
	_fold.y = 0.0
	_fold = _fold.normalized()
	_rw_h = _runway("Hawkinge", 51.115, 1.1494, 100.0, 900.0)
	_rw_m = _runway("Manston", 51.3422, 1.3461, 100.0, 2700.0)


func _runway(aname: String, lat: float, lon: float, hdg: float, ln: float) -> Dictionary:
	var c: Vector3 = WorldCoords.latlon_to_world(lat, lon)
	var h: float = hdg
	var L: float = ln
	var y: float = NAN
	for n in get_tree().get_nodes_in_group("airfield"):
		if n is Airfield and (n as Airfield).airfield_name == aname:
			var af: Airfield = n as Airfield
			c = Vector3(af.global_position.x, 0.0, af.global_position.z)
			h = af.heading_deg
			L = af.runway_length
			y = af.surface_y
	if is_nan(y):
		y = GroundKit.ground_y(c.x, c.z)
	c.y = y
	return {"c": c, "d": WorldCoords.heading_to_dir(h), "len": L, "y": y}


## Three fighters taking off in a vic: engine run-up, ground run, lift-off, climb-out. `t0` is the shot start.
func _tk_pos(i: int, t: float, t0: float, rw: Dictionary) -> Vector3:
	var d: Vector3 = rw["d"]
	var right: Vector3 = d.cross(Vector3.UP).normalized()
	var lat: float = [0.0, 20.0, -20.0][i]
	var back: float = [0.0, 30.0, 30.0][i]
	var u: float = maxf(0.0, t - t0 - 1.5)
	var s0: float = -float(rw["len"]) * 0.5 + 70.0 - back
	var ul: float = 6.5
	var s: float = 0.0
	var up: float = 0.0
	if u < ul:
		s = 5.0 * u * u
	else:
		var du: float = u - ul
		s = 5.0 * ul * ul + 65.0 * du + 2.0 * du * du
		up = 6.0 * pow(du, 1.25)
	var p: Vector3 = Vector3(rw["c"]) + d * (s0 + s) + right * lat
	p.y = float(rw["y"]) + 1.7 + up
	return p


func _tk_fly(n: Node3D, i: int, t: float, t0: float, rw: Dictionary) -> void:
	var p: Vector3 = _tk_pos(i, t, t0, rw)
	var p2: Vector3 = _tk_pos(i, t + 0.1, t0, rw)
	if p2.distance_to(p) < 0.01:
		p2 = p + Vector3(rw["d"])
	_orient(n, p, p2, 0.0)
	_spin(n)


func _tk_cam(t: float, t0: float, rw: Dictionary, cam_s: float, side: float) -> Array:
	var d: Vector3 = rw["d"]
	var right: Vector3 = d.cross(Vector3.UP).normalized()
	var lead: Vector3 = _tk_pos(0, t, t0, rw)
	var s0: float = -float(rw["len"]) * 0.5 + 70.0
	var fixed: Vector3 = Vector3(rw["c"]) + d * (s0 + cam_s) + right * side * 40.0
	fixed.y = float(rw["y"]) + 2.4
	var sw: float = t0 + 7.5
	var ch: Array = _chase(lead, d, sw, t, 55.0)
	var w: float = smoothstep(sw, sw + 2.0, t)
	return [fixed.lerp(ch[0], w), (lead + Vector3.UP).lerp(ch[1], w)]


func _env(t: float) -> void:
	var idx: int = 0
	for i in ENV.size():
		if t >= float(ENV[i][0]):
			idx = i
	var e: Array = ENV[idx]
	if idx != _env_i:
		_env_i = idx
		WeatherManager.set_weather(String(e[2]), 0.1)
		if OS.get_environment("WW2_LOW_CLOUD") == "":
			WeatherManager.low_cloud = 0.0         # the film keeps its sky clear of the very low deck
		var night: bool = float(e[1]) > 20.5
		for a in get_tree().get_nodes_in_group("airfield"):
			if "force_lights" in a:
				a.set("force_lights", night)
	TimeOfDay.set_time(float(e[1]) + (t - float(e[0])) * 0.03)


func _model(id: String, nation: String) -> Node3D:
	var m: Node3D = AircraftModels.build(id, nation)
	if m == null:
		m = Node3D.new()
	var prop: Node3D = m.find_child("Propeller", true, false) as Node3D
	var disc: Node3D = m.find_child("PropDisc", true, false) as Node3D
	if prop != null:
		var bl: Node3D = prop.find_child("Blades", true, false) as Node3D
		if bl != null and disc != null:
			bl.visible = false
			disc.visible = true
	m.visible = false
	get_tree().current_scene.add_child(m)
	return m


func _build_actors() -> void:
	for i in 3:
		_sp.append(_model("spitfire", "RAF"))
		_ax.append(_model("bf109", "Luftwaffe"))
	for i in 7:
		_bm.append(_model("he111", "Luftwaffe"))
	for i in 4:
		_es.append(_model("bf109", "Luftwaffe"))
	_prey = _model("bf109", "Luftwaffe")
	_hero = _sp[0]
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.82, 0.55)
	_lamp.light_energy = 5.0
	_lamp.omni_range = 110.0
	_lamp.shadow_enabled = false
	_lamp.visible = false
	get_tree().current_scene.add_child(_lamp)


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 90
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)
	for top in [true, false]:
		var b := ColorRect.new()
		b.color = Color.BLACK
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.anchor_left = 0.0
		b.anchor_right = 1.0
		if top:
			b.anchor_top = 0.0
			b.anchor_bottom = BAR
		else:
			b.anchor_top = 1.0 - BAR
			b.anchor_bottom = 1.0
		root.add_child(b)
	_caption = UIKit.label("", 30, Color(0.97, 0.94, 0.85), true)
	_caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.anchor_top = 1.0 - BAR - 0.09
	_caption.anchor_bottom = 1.0 - BAR - 0.02
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_caption.add_theme_constant_override("outline_size", 8)
	root.add_child(_caption)
	_title = UIKit.label("WW2  CHANNEL  AIR  WAR", 84, Color(0.97, 0.9, 0.7), true)
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_title.add_theme_constant_override("outline_size", 14)
	_title.modulate.a = 0.0
	root.add_child(_title)
	_sub = UIKit.label("FLY  THE  BATTLE  -  FROM  EITHER  SIDE", 30, Color(0.93, 0.74, 0.32), true)
	_sub.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sub.offset_top = 90.0
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_sub.add_theme_constant_override("outline_size", 10)
	_sub.modulate.a = 0.0
	root.add_child(_sub)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)



func _build_music() -> void:
	var st: AudioStream = MenuMusic.load_track("res://assets/music/cinematic_violin_tribal.mp3")
	if st == null:
		return
	_music = AudioStreamPlayer.new()
	_music.stream = st
	_music.bus = &"Master"
	_music.volume_db = linear_to_db(0.0001)
	add_child(_music)
	if _warm <= 0.0:
		_music.play(maxf(_start_at, 0.0))


func _input(e: InputEvent) -> void:
	if _done or freeze:
		return
	if (e is InputEventKey and e.pressed and not e.echo) or (e is InputEventMouseButton and e.pressed) or (e is InputEventJoypadButton and e.pressed):
		_end()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------------------------------------ paths

## Coast frame: `along` metres NE along the cliffs, `out` metres out to sea, `up` metres above sea level.
func _pt(along: float, out: float, up: float) -> Vector3:
	return _k + _a * along + _s * out + Vector3(0.0, up, 0.0)


## A low pass that follows the ground: straight line from p0 along dir at `speed`, `clear` metres above the highest
## ground in the next few hundred metres (so it skims hills and rides over towns).
func _skim(p0: Vector3, dir: Vector3, speed: float, t: float, clear: float) -> Vector3:
	var xz: Vector3 = p0 + dir * speed * t
	var h: float = 0.0
	var wsum: float = 0.0
	var acc: float = 0.0
	for k in 9:
		var hk: float = _gh(xz + dir * float(k) * 45.0)
		h = maxf(h, hk - float(k) * 3.0)
		acc += hk
		wsum += 1.0
	var y: float = lerpf(h, acc / wsum, 0.5) + clear
	return Vector3(xz.x, y, xz.z)


func _skim_flight(i: int, p0: Vector3, dir: Vector3, speed: float, t: float, clear: float) -> Vector3:
	var right: Vector3 = dir.cross(Vector3.UP).normalized()
	var lead: Vector3 = _skim(p0, dir, speed, t, clear)
	if i == 0:
		return lead
	var side: float = 1.0 if i == 1 else -1.0
	var p: Vector3 = _skim(p0 + right * side * 55.0 - dir * 60.0 * float(i), dir, speed, t, clear + 4.0 * float(i))
	return p


func _sp_a_pos(i: int, t: float) -> Vector3:
	t -= T_A
	# shot A: the flight sweeps NE along the cliffs, low over the sea
	var base: Vector3 = _pt(-3000.0 + 330.0 * t, 520.0 + 10.0 * sin(t * 0.3), 140.0 + 5.0 * sin(t * 0.9))
	if i == 0:
		return base
	var side: float = 1.0 if i == 1 else -1.0
	return base + _a * (-70.0 * float(i)) + _s * (45.0 * side) + Vector3.UP * (-5.0 * float(i))


func _ax_pos(i: int, t: float) -> Vector3:
	return _skim_flight(i, _cg - _cgd * 900.0, _cgd, 170.0, t - T_B, 34.0)


func _sp_c_pos(i: int, t: float) -> Vector3:
	return _skim_flight(i, _fol - _fold * 650.0, _fold, 150.0, t - T_C, 32.0)


## The bomber lead: over Dover town heading inland (NW), then over Manston.
func _lead(t: float) -> Vector3:
	if t < T_F - 1.0:
		var p: Vector3 = _town + _s * ((T_E + 4.5 - t) * 300.0)
		p.y = 650.0
		return p
	var q: Vector3 = _manston + _s * ((T_F + 4.0 - t) * 300.0)
	q.y = _gh(_manston) + 600.0
	return q


## Where the bombs are landing now: a bomb keeps pace with its bomber while it falls, so the ones hitting the
## ground now land just behind the lead aircraft.
func _impact(t: float) -> Vector3:
	var p: Vector3 = _lead(t) + _s * 60.0
	p.y = _gh(p)
	return p


func _bm_pos(i: int, t: float) -> Vector3:
	var lead: Vector3 = _lead(t)
	var offs: Array = [Vector2(0, 0), Vector2(-110, 95), Vector2(110, 95), Vector2(-220, 190), Vector2(220, 190), Vector2(-330, 285), Vector2(330, 285)]
	var o: Vector2 = offs[i]
	return lead + _a * o.x + _s * o.y + Vector3.UP * (-o.y * 0.03)


func _es_pos(i: int, t: float) -> Vector3:
	var lead: Vector3 = _lead(t)
	var offs: Array = [Vector3(-260, 130, 40), Vector3(260, 130, 40), Vector3(-80, 330, 70), Vector3(120, 380, 90)]
	var o: Vector3 = offs[i]
	return lead + _a * o.x + Vector3.UP * o.y + _s * o.z + _s * (60.0 * sin(t * 0.7 + float(i)))


# the dogfight (u = t - T_G): the Bf 109 jinks across the sky, the Spitfire sits behind it
func _prey_pos(t: float) -> Vector3:
	var u: float = t - T_G
	var p: Vector3 = _pt(-900.0 + 190.0 * u, 1500.0 - 55.0 * u, 520.0 + 38.0 * sin(u * 0.9) - maxf(0.0, u - 5.5) * 70.0 * (u - 5.5) * 0.4)
	p += _s * (sin(u * 0.85) * 160.0)
	return p


func _hero_pos(t: float) -> Vector3:
	var p: Vector3 = _prey_pos(t - 0.75)
	return p + Vector3(0.0, 8.0 + 4.0 * sin(t * 1.3), 0.0) + _a * (-35.0) + _s * (-14.0)


func _orient(n: Node3D, p: Vector3, ahead: Vector3, bank: float) -> void:
	n.global_position = p
	var f: Vector3 = ahead - p
	if f.length() < 0.01:
		return
	n.look_at(p + f, Vector3.UP)
	n.rotate_object_local(Vector3.FORWARD, bank)


func _fly(n: Node3D, fn: Callable, t: float, bank_k: float = 1.0) -> void:
	var p: Vector3 = fn.call(t)
	var p2: Vector3 = fn.call(t + 0.1)
	var p0: Vector3 = fn.call(t - 0.1)
	var turn: float = (p2 - p).cross(p - p0).y
	_orient(n, p, p2, clampf(turn * 0.15 * bank_k, -1.0, 1.0))
	_spin(n)


func _spin(n: Node3D) -> void:
	var prop: Node3D = n.find_child("Propeller", true, false) as Node3D
	if prop != null:
		prop.rotate_object_local(Vector3.BACK, 0.9)


# ------------------------------------------------------------------------------------------------ process

func _show_only(arr: Array, on: bool) -> void:
	for n in arr:
		(n as Node3D).visible = on


func _process(delta: float) -> void:
	if _done:
		return
	delta = minf(delta, 0.05)
	if _dbg:
		_dbg_t -= delta
		if _dbg_t <= 0.0:
			_dbg_t = 1.0
			var pend: int = (_terr.get("_pending") as Dictionary).size() if _terr != null else -1
			print("[introdbg] t=%.2f bombs=%d booms=%d boom=%s imp=%s cam=%s hold=%.1f warm=%.1f fps=%d pending=%d chunks=%d" % [_t, _bombs.size(), _smoke_k, _last_boom, _impact(_t), _cam.global_position, _hold, _warm, Engine.get_frames_per_second(), pend, (_terr.get("_chunks") as Dictionary).size() if _terr != null else -1])
	if _warm > 0.0:
		_warm -= delta
		if _warm < 7.0 and _land_ready(Vector3(_rw_h["c"])):
			_warm = 0.0
		_fade.color = Color.BLACK
		_anchor.global_position = Vector3(_rw_h["c"]) + Vector3.UP * 3.0
		_cam.global_position = _anchor.global_position
		if _warm <= 0.0:
			_env(_t)
			if _music != null:
				_music.play(0.0)
		return
	if _hold > 0.0:
		_hold -= delta
		if _land_ready(_anchor.global_position) or _hold <= 0.0:
			if _dbg:
				print("[introdbg] hold released at t=%.2f, left=%.2f ready=%s" % [_t, _hold, _land_ready(_anchor.global_position)])
			_hold = 0.0
		else:
			_fade.color = Color.BLACK
			return
	if not freeze:
		var nt: float = _t + delta
		for cut in [T_A, T_B, T_C, T_N, T_D, T_E, T_F, T_G]:
			if _t < cut and nt >= cut:
				nt = cut
				_hold = 2.5
		_t = nt
	if _t >= DURATION:
		_end()
		return
	var t: float = _t
	# --- who is on screen, and where
	var s1: bool = t < T_A
	var sa: bool = t >= T_A and t < T_B
	var sb: bool = t >= T_B and t < T_C
	var sc: bool = t >= T_C and t < T_N
	var tn: bool = t >= T_N and t < T_D
	var bombers: bool = t >= T_D - 1.0 and t < T_G
	_show_only(_sp, s1 or sa or sc or tn)
	if s1:
		for i in 3:
			_tk_fly(_sp[i], i, t, 0.0, _rw_h)
	if tn:
		for i in 3:
			_tk_fly(_sp[i], i, t, T_N, _rw_m)
	_lamp.visible = tn
	if tn:
		_lamp.global_position = _tk_pos(0, t, T_N, _rw_m) + Vector3(0.0, 12.0, 0.0) + Vector3(_rw_m["d"]) * 15.0
	_show_only(_ax, sb)
	_show_only(_bm, bombers)
	_show_only(_es, bombers)
	if t >= T_G:
		_hero.visible = not _hero_boom
	if sa:
		for i in 3:
			var ia: int = i
			_fly(_sp[i], func(tt: float) -> Vector3: return _sp_a_pos(ia, tt), t)
	if sb:
		for i in 3:
			var ib: int = i
			_fly(_ax[i], func(tt: float) -> Vector3: return _ax_pos(ib, tt), t, 0.6)
	if sc:
		for i in 3:
			var ic: int = i
			_fly(_sp[i], func(tt: float) -> Vector3: return _sp_c_pos(ic, tt), t, 0.6)
	if bombers:
		for i in _bm.size():
			var id: int = i
			_fly(_bm[i], func(tt: float) -> Vector3: return _bm_pos(id, tt), t, 0.3)
		for i in _es.size():
			var ie: int = i
			_fly(_es[i], func(tt: float) -> Vector3: return _es_pos(ie, tt), t, 0.8)
	# --- the dogfight and its aftermath
	var fight: bool = t >= T_G and t < T_H
	_prey.visible = fight and not _dead_prey
	if fight:
		_hero.visible = true
		_fly(_hero, func(tt: float) -> Vector3: return _hero_pos(tt), t, 1.4)
		_fly(_prey, func(tt: float) -> Vector3: return _prey_pos(tt), t, 1.8)
	_update_fight(t, delta)
	_update_bombs(t, delta)
	_update_bullets(delta)
	# --- time of day
	_time_t -= delta
	if _time_t <= 0.0:
		_time_t = 0.15
		_env(t)
	_camera(t, delta)
	_ui(t)


# ------------------------------------------------------------------------------------------------ bombs & fight

func _update_bombs(t: float, delta: float) -> void:
	var raining: bool = (t >= T_D + 3.0 and t < T_F - 0.5) or (t >= T_F + 0.5 and t < T_F + 6.5)
	if raining:
		_bomb_t -= delta
		if _bomb_t <= 0.0:
			_bomb_t = 0.13
			var bm: Node3D = _bm[randi() % _bm.size()]
			_spawn_bomb(bm.global_position, -_s * 280.0)
	for b in _bombs.duplicate():
		var mi: MeshInstance3D = b[0]
		var v: Vector3 = b[1]
		v.y -= 150.0 * delta
		b[1] = v
		mi.global_position += v * delta
		if v.length_squared() > 0.0001:
			mi.look_at(mi.global_position + v, Vector3.UP)
		if mi.global_position.y <= _gh(mi.global_position) + 1.0:
			var gp: Vector3 = mi.global_position
			gp.y = _gh(gp)
			FX.explosion(gp, randf_range(18.0, 30.0), true)
			_last_boom = gp
			_smoke_k += 1
			if _smoke_k % 2 == 0:
				FX.fire(gp, 9.0, 120.0)
			if _smoke_k % 4 == 1:
				FX.smoke_column(gp, 7.0, 90.0)
			_shake = maxf(_shake, 0.25)
			mi.queue_free()
			_bombs.erase(b)


func _spawn_bomb(p: Vector3, v: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = 2.2
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.08)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = p + Vector3(randf_range(-30.0, 30.0), -4.0, randf_range(-30.0, 30.0))
	_bombs.append([mi, v + Vector3(randf_range(-8.0, 8.0), 0.0, randf_range(-8.0, 8.0))])


func _update_fight(t: float, delta: float) -> void:
	if t < T_G:
		_hit = false
		_dead_prey = false
		_hero_hit = false
		_hero_boom = false
		_bail = false
		return
	var u: float = t - T_G
	# tracer bursts while closing, from the Spitfire's wings
	if u > 2.0 and u < 5.5 and _hero.visible:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_burst_t = 0.04
			for side in [-1.0, 1.0]:
				_spawn_bullet(_hero.global_position + _hero.global_transform.basis.x * side * 2.6, -_hero.global_transform.basis.z)
	if u > 4.0 and not _hit:
		_hit = true
		FX.trail(_prey, "smoke", 3.4, Vector3(0.0, 0.3, 3.0), 0.9)
		FX.fire(_prey.global_position, 5.0, 40.0)
		FX.explosion(_prey.global_position, 6.0, false)
		_shake = 1.0
	if u > 6.6 and _hit and not _dead_prey:
		_dead_prey = true
		_prey.visible = false
		FX.explosion(_prey.global_position, 14.0, false)
		FX.debris(_prey.global_position, 18, 3.0, 40.0)
		_shake = 1.6
	# the Spitfire is hit in turn, then the pilot gets out
	if t >= T_H and not _hero_hit:
		_hero_hit = true
		_hero.visible = true
		_hero_vel = -_hero.global_transform.basis.z * 150.0
		FX.trail(_hero, "smoke", 3.0, Vector3(0.0, 0.3, 3.0), 0.9)
		FX.explosion(_hero.global_position + Vector3(0, 1, 0), 5.0, false)
		_shake = 1.2
	if _hero_hit and not _hero_boom:
		_hero_vel.y -= 28.0 * delta
		_hero.global_position += _hero_vel * delta
		var ahead: Vector3 = _hero.global_position + _hero_vel
		if _hero_vel.length_squared() > 0.0001:
			_hero.look_at(ahead, Vector3.UP)
		_hero.rotate_object_local(Vector3.FORWARD, (t - T_H) * 3.2)
		_spin(_hero)
		if t >= T_H + 1.7 and not _bail:
			_bail = true
			_chute = FX.parachute(_hero.global_position + Vector3(0, 2, 0), "Allies")
		var gp: Vector3 = _hero.global_position
		if gp.y <= _gh(gp) + 2.0 or gp.y <= 2.0 or t > T_H + 6.0:
			_hero_boom = true
			_hero.visible = false
			FX.crash_explosion(Vector3(gp.x, _gh(gp), gp.z), FX.is_water(gp))
	if _chute != null and is_instance_valid(_chute) and t >= T_I and not _chute_moved:
		_chute_moved = true
		var c: Vector3 = _town + _s * 100.0
		_chute.global_position = Vector3(c.x, _gh(c) + 120.0, c.z)


var _chute_moved: bool = false
var _burst_t: float = 0.0


func _spawn_bullet(p: Vector3, dir: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 0.18, 9.0)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.2)
	mat.emission_energy_multiplier = 4.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = p
	if dir.length_squared() > 0.0001:
		mi.look_at(p + dir, Vector3.UP)
	_bullets.append([mi, dir * 520.0, 0.9])


func _update_bullets(delta: float) -> void:
	for b in _bullets.duplicate():
		var mi: MeshInstance3D = b[0]
		b[2] -= delta
		mi.global_position += (b[1] as Vector3) * delta
		if b[2] <= 0.0:
			mi.queue_free()
			_bullets.erase(b)


func _clear_fx() -> void:
	for b in _bullets:
		if is_instance_valid(b[0]):
			(b[0] as MeshInstance3D).queue_free()
	_bullets.clear()
	for b in _bombs:
		if is_instance_valid(b[0]):
			(b[0] as MeshInstance3D).queue_free()
	_bombs.clear()


# ------------------------------------------------------------------------------------------------ camera shots

func _chase(lead: Vector3, fwd: Vector3, t0: float, t: float, dist: float) -> Array:
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	var ang: float = 0.9 + (t - t0) * 0.16
	var pos: Vector3 = lead + (right * sin(ang) - fwd * cos(ang)) * dist + Vector3.UP * 7.0
	return [pos, lead + fwd * 14.0]


func _camera(t: float, delta: float) -> void:
	var pos: Vector3
	var look: Vector3
	var fov: float = 55.0
	var next_origin: Vector3 = Vector3.INF
	if t < T_A:
		# 1: dawn take-off from Hawkinge: low beside the runway, then up and away with them
		var tc: Array = _tk_cam(t, 0.0, _rw_h, 150.0, 1.0)
		pos = tc[0]
		look = tc[1]
		fov = 58.0
		if T_A - t < PRELOAD:
			next_origin = _pt(-300.0, 1500.0, 0.0)
	elif t < T_B:
		# A: low over the water, the cliffs behind; the flight roars past
		var ta: float = t - T_A
		var lead: Vector3 = _sp_a_pos(0, t)
		pos = _pt(-300.0 + 12.0 * ta, 1500.0, 26.0 + 1.5 * ta)
		look = _pt(-250.0 + 20.0 * ta, -300.0, 150.0).lerp(lead, clampf((ta - 3.5) / 3.0, 0.0, 1.0))
		fov = 60.0 - ta * 1.0
		if T_B - t < PRELOAD:
			next_origin = _cg
	elif t < T_C:
		# B: the other side - Luftwaffe fighters skimming the French hills
		var l0: Vector3 = _ax_pos(0, t)
		var ch: Array = _chase(l0, _cgd, T_B, t, 85.0)
		pos = ch[0]
		look = ch[1]
		fov = 52.0
		if T_C - t < PRELOAD:
			next_origin = _fol
	elif t < T_N:
		# C: Spitfires racing through Folkestone
		var l1: Vector3 = _sp_c_pos(0, t)
		var ch2: Array = _chase(l1, _fold, T_C, t, 70.0)
		pos = ch2[0]
		look = ch2[1]
		fov = 56.0
		if T_N - t < PRELOAD:
			next_origin = _manston
	elif t < T_D:
		# N: night scramble from Manston in the rain
		var tc2: Array = _tk_cam(t, T_N, _rw_m, 150.0, -1.0)
		pos = tc2[0]
		look = tc2[1]
		fov = 56.0
		if T_D - t < PRELOAD:
			next_origin = _town
	elif t < T_E:
		# D: the Heinkels cross the cliffs; the camera looks up from the shore
		var ld: Vector3 = _lead(t)
		var u: float = (t - T_D) / (T_E - T_D)
		pos = ld + _a * lerpf(-430.0, -300.0, u) + _s * lerpf(-260.0, 120.0, u) + Vector3.UP * lerpf(-70.0, 40.0, u)
		look = ld + _s * -120.0 + _a * 40.0
		fov = 50.0
	elif t < T_F:
		# E: high over Dover looking down at the bombs walking across the town
		var ic: Vector3 = _impact(t)
		pos = ic + _s * 520.0 + _a * (-260.0)
		pos.y = _gh(ic) + 170.0 + (t - T_E) * 3.0
		look = ic
		fov = 54.0
		if T_F - t < PRELOAD:
			next_origin = _manston
	elif t < T_G:
		# F: low over Manston as the bombs fall across the airfield
		var ic2: Vector3 = _impact(t)
		pos = ic2 + _s * 650.0 + _a * (-350.0)
		pos.y = _gh(pos) + 30.0 + (t - T_F) * 2.0
		look = ic2 + Vector3.UP * 25.0
		fov = 58.0
		if T_G - t < PRELOAD:
			next_origin = _pt(0.0, 1000.0, 400.0)
	elif t < T_H:
		# G: behind and above the Spitfire, the 109 in the sight; swing out to watch the kill
		var u: float = t - T_G
		if u < 4.5:
			var hb: Basis = _hero.global_transform.basis
			pos = _hero.global_position + hb.z * 28.0 + Vector3.UP * 9.0 + hb.x * 6.0
			look = _prey.global_position
			fov = 52.0
		else:
			var pp: Vector3 = _prey.global_position
			pos = pp + _a * -240.0 + _s * 120.0 + Vector3.UP * 25.0
			look = pp
			fov = 38.0
	elif t < T_I:
		# H: the hit Spitfire, smoking, and the pilot going over the side
		var hp: Vector3 = _hero.global_position
		pos = hp + _a * 130.0 + _s * 60.0 + Vector3.UP * 25.0
		look = hp
		fov = 44.0
	else:
		# I: orbit the pilot as he drifts down over the burning town, sunset behind
		var cp: Vector3 = _chute.global_position if _chute != null and is_instance_valid(_chute) else _town + Vector3(0, 100, 0)
		var ang: float = (t - T_I) * 0.32 + 0.4
		pos = cp + Vector3(cos(ang) * 70.0, -12.0 + 6.0 * sin(ang * 0.7), sin(ang) * 70.0)
		look = cp + Vector3(0.0, -14.0, 0.0)
		fov = 50.0
	var gh: float = _gh(pos)
	pos.y = maxf(pos.y, gh + 4.0)
	pos.y = maxf(pos.y, 8.0)
	if _shake > 0.0:
		pos += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake * 0.5
		_shake = maxf(0.0, _shake - delta * 2.5)
	# the terrain streams around the anchor: look ahead to the next shot's location before a far cut
	_anchor.global_position = next_origin if next_origin != Vector3.INF else pos
	_cam.global_position = pos
	if look.distance_to(pos) > 0.5:
		_cam.look_at(look, Vector3.UP)
	_cam.fov = fov


# ------------------------------------------------------------------------------------------------ overlays

func _ui(t: float) -> void:
	var a: float = 1.0 - clampf(t / 1.8, 0.0, 1.0)
	if t > DURATION - 2.2:
		a = clampf((t - (DURATION - 2.2)) / 2.0, 0.0, 1.0)
	# cuts: dip to black for a few frames (and a little longer for the far cuts so the land can stream in)
	for cut in [T_A, T_B, T_C, T_N, T_D, T_E, T_F, T_G, T_H, T_I]:
		var w: float = 0.3 if cut == T_A or cut == T_B or cut == T_C or cut == T_N or cut == T_E or cut == T_D else 0.18
		var d: float = absf(t - cut)
		if d < w:
			a = maxf(a, 1.0 - d / w)
	_fade.color = Color(0, 0, 0, a)
	var cap: String = ""
	var capa: float = 0.0
	var caps: Array = []    # no on-screen captions: the pictures tell the story
	for c in caps:
		if t >= float(c[0]) and t <= float(c[1]):
			cap = String(c[2])
			capa = minf(minf((t - float(c[0])) / 0.8, (float(c[1]) - t) / 0.8), 1.0)
	_caption.text = cap
	_caption.modulate.a = clampf(capa, 0.0, 1.0)
	var ta: float = clampf((t - 90.0) / 1.5, 0.0, 1.0) * clampf((DURATION - 1.0 - t) / 1.0, 0.0, 1.0)
	_title.modulate.a = ta
	_sub.modulate.a = clampf((t - 92.0) / 1.2, 0.0, 1.0) * clampf((DURATION - 1.0 - t) / 1.0, 0.0, 1.0)
	if _music != null:
		var vol: float = clampf(AudioManager.music_volume * AudioManager.master_volume, 0.0, 1.0) * 0.85
		var fin: float = clampf(t / 3.0, 0.0, 1.0) * clampf((DURATION - t) / 2.5, 0.0, 1.0)
		_music.volume_db = linear_to_db(maxf(vol * fin, 0.0001))


func _end() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	_clear_fx()
	for a in get_tree().get_nodes_in_group("airfield"):
		if "force_lights" in a:
			a.set("force_lights", false)
	if is_instance_valid(_lamp):
		_lamp.queue_free()
	if _terr != null and is_instance_valid(_terr) and _terr_old.size() == 2:
		_terr.set("max_inflight", _terr_old[0])
		_terr.set("max_instantiate_per_frame", _terr_old[1])
	for n in _sp + _ax + _bm + _es + [_prey]:
		if is_instance_valid(n):
			(n as Node3D).queue_free()
	if _layer != null:
		_layer.queue_free()
	if _music != null:
		_music.stop()
	finished.emit()
	queue_free()
