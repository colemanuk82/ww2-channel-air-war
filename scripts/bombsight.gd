class_name Bombsight
extends CanvasLayer
## Bomber bombsight (key N) and tactical map (key M) for the player's bomber.
##
## Bombsight: a bombardier's-eye view looking down through the nose. The autopilot holds wings level and the
## altitude (steer with A/D/Q/E: slight banked course changes only). The sight does not read the real aircraft
## state: the player dials the SPEED and ALTITUDE the sight assumes (arrow keys), and the sight predicts the
## bomb fall from those dialled values. Dial values that do not match the instruments and the hit marker is in
## the wrong place, so the bombs miss. The same marker is drawn live on the map.
## Map: full-screen chart with the aircraft, a faint line along the course, the live hit marker, previous
## bomb splashes, targets, airfields and towns. Wheel zooms, drag pans, Home recentres.

const KMH: float = 3.6
const BOMB_G: float = 30.0                # mirrors WeaponWorld.BOMB_GRAVITY / BOMB_DRAG
const BOMB_DRAG: float = 0.06
const GOLD := Color(0.93, 0.82, 0.5)
const INK := Color(0.9, 0.93, 0.85)
const GREEN := Color(0.45, 0.95, 0.5)
const AMBER := Color(1.0, 0.72, 0.25)
const RED := Color(1.0, 0.32, 0.25)
const PANEL := Color(0.055, 0.06, 0.05)

var aircraft: Aircraft
var rig: CameraRig
var hud: Node
var world: Node
var turrets: DefensiveTurrets

var active: bool = false
var map_open: bool = false
var chart_only: bool = false      # every aircraft gets the chart (M); only heavy bombers get the bombsight (N)
var dial_speed: float = 300.0     # km/h assumed by the sight
var dial_alt: float = 2500.0      # metres assumed by the sight
var marker: Vector3 = Vector3.ZERO   # dialled hit point (world)

var _cam: Camera3D
var _sight_ui: Control
var _map_ui: Control
var _held: Dictionary = {}
var _targets: Array = []          # {"node", "name"}
var _tgt_t: float = 0.0
var _splashes: Array = []         # {"pos": Vector3, "t": float}
var _fall_t: float = 0.0
var _near_enemy: float = 99999.0
var _near_t: float = 0.0
var _blink: float = 0.0
var _hud_was_visible: bool = true
var _wh: Array = []
var _dbg: String = ""            # debug args: --sight (synced dials) | --sight=off (default dials) | --tacmap
var _dbg_f: int = 0

# map
var _color_tex: Texture2D
var _bounds: Rect2
var _mpu: float = 45.0            # world units per screen pixel
var _mc: Vector2 = Vector2.ZERO
var _follow: bool = true
var _drag: bool = false
var _cities: Array = []
var _fields: Array = []
var _mrect: Rect2


static func attach(p_world: Node, a: Aircraft, p_rig: CameraRig, p_hud: Node) -> Bombsight:
	var b := Bombsight.new()
	b.name = "Bombsight"
	b.aircraft = a
	b.rig = p_rig
	b.hud = p_hud
	b.world = p_world
	p_world.add_child(b)
	return b


func _exit_tree() -> void:
	GameState.sight_dials = false


func _ready() -> void:
	layer = 12
	add_to_group("bombsight")
	process_mode = Node.PROCESS_MODE_INHERIT
	_bounds = WorldCoords.world_bounds()
	_color_tex = ResourceLoader.load("res://data/heightmap/region_color.png") as Texture2D
	_load_spots()
	if OS.get_cmdline_user_args().has("--chart-open"):      # debug/vis: open the chart a few seconds in
		get_tree().create_timer(5.0).timeout.connect(func() -> void: if is_instance_valid(aircraft): set_map(true))
	_sight_ui = Control.new()
	_sight_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sight_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sight_ui.visible = false
	_sight_ui.draw.connect(_draw_sight)
	add_child(_sight_ui)
	_map_ui = Control.new()
	_map_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_ui.visible = false
	_map_ui.draw.connect(_draw_map)
	_map_ui.gui_input.connect(_map_input)
	add_child(_map_ui)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sight") or arg == "--tacmap":
			_dbg = arg
	if aircraft != null:
		aircraft.bomb_requested.connect(_on_bomb)
		dial_speed = 250.0
		dial_alt = 2000.0


func _load_spots() -> void:
	var f := FileAccess.open("res://data/locations.json", FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var dd: Dictionary = d
	for a in dd.get("airfields", []):
		if a is Dictionary and bool(a.get("in_bounds", true)):
			var w: Vector3 = WorldCoords.latlon_to_world(float(a["lat"]), float(a["lon"]))
			_fields.append({"pos": Vector2(w.x, w.z), "name": str(a.get("name", "")), "side": str(a.get("side", ""))})
	for c in dd.get("cities", []):
		if c is Dictionary and bool(c.get("in_bounds", true)):
			var w2: Vector3 = WorldCoords.latlon_to_world(float(c["lat"]), float(c["lon"]))
			_cities.append({"pos": Vector2(w2.x, w2.z), "name": str(c.get("name", "")), "size": int(c.get("size", 2))})


# ------------------------------------------------------------------ input / state

func _unhandled_input(event: InputEvent) -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		return
	if chart_only:
		if event.is_action_pressed("tac_map") and not event.is_echo():
			_map_key()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("sight_cycle") and not event.is_echo():
			set_map(not map_open)
			get_viewport().set_input_as_handled()
		elif map_open and event is InputEventKey and event.pressed and event.keycode == KEY_HOME:
			_follow = true
		return
	if event.is_action_pressed("bombsight") and not event.is_echo():
		set_active(not active)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("sight_cycle") and not event.is_echo():
		# controller: one button steps flight -> bombsight -> chart -> flight
		if map_open:
			set_map(false)
			set_active(false)
		elif active:
			set_map(true)
		else:
			set_active(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("tac_map") and not event.is_echo():
		_map_key()
		get_viewport().set_input_as_handled()
	elif map_open and event is InputEventKey and event.pressed and event.keycode == KEY_HOME:
		_follow = true


## The map key steps: small minimap -> large minimap -> full-screen chart -> back to the small minimap.
func _map_key() -> void:
	var h: Node = get_tree().get_first_node_in_group("hud")
	if map_open:
		set_map(false)
		if h != null and h.has_method("set_minimap_stage"):
			h.call("set_minimap_stage", 0)
	elif h != null and h.has_method("set_minimap_stage") and int(h.get("minimap_stage")) == 0:
		h.call("set_minimap_stage", 1)
	else:
		set_map(true)


func set_active(on: bool) -> void:
	if on == active:
		return
	if on:
		if aircraft.state != Aircraft.State.ALIVE or aircraft.on_ground:
			_say("Bombsight: get airborne first")
			return
		if aircraft.bombs <= 0:
			_say("No bombs left")
			return
		if aircraft.altitude_agl < 250.0:
			_say("Too low for the bombsight")
			return
	active = on
	aircraft.sight_hold = on
	if on:
		aircraft.sight_alt_y = aircraft.global_position.y
		aircraft.weapon_mode = 2
		aircraft.weapon_bombs = true
		aircraft.weapon_changed.emit(true)
		if _cam == null:
			_cam = Camera3D.new()
			_cam.name = "SightCam"
			_cam.top_level = true
			_cam.near = 1.0
			_cam.far = 48000.0
			_cam.fov = 34.0
			aircraft.add_child(_cam)
		_cam.make_current()
		_hud_was_visible = (hud as CanvasLayer).visible if hud is CanvasLayer else true
		if hud is CanvasLayer:
			(hud as CanvasLayer).visible = false
		_wh = get_tree().root.find_children("*", "WeaponHud", true, false)
		for w in _wh:
			(w as CanvasLayer).visible = false
		_say("Bombsight: set speed and altitude to match the instruments")
	else:
		if rig != null:
			rig.current_camera().make_current()
		if hud is CanvasLayer:
			(hud as CanvasLayer).visible = _hud_was_visible
		for w in _wh:
			if is_instance_valid(w):
				(w as CanvasLayer).visible = true
		_wh.clear()
	_sight_ui.visible = on
	if map_open and on:
		pass


func set_map(on: bool) -> void:
	map_open = on
	_map_ui.visible = on
	_map_ui.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	if on:
		_follow = true
		_refresh_targets()


func _say(t: String) -> void:
	if hud != null and hud.has_method("show_message"):
		hud.call("show_message", t, 2.6)


func _on_bomb(a: Aircraft) -> void:
	if a != aircraft or a.state != Aircraft.State.ALIVE:
		return
	# remember where this stick really lands, for the splash marks on the map
	var pos: Vector3 = a.global_position - a.global_transform.basis.y * 1.8
	var vel: Vector3 = a.velocity if a.velocity.length_squared() > 1.0 else a.get_forward() * a.speed
	_splashes.append({"pos": _predict(pos, vel), "t": 0.0})
	if _splashes.size() > 40:
		_splashes.pop_front()


func _map_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(0.8, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(1.25, mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag = mb.pressed
	elif ev is InputEventMouseMotion and _drag:
		_follow = false
		_mc -= (ev as InputEventMouseMotion).relative * _mpu


func _zoom(k: float, at: Vector2) -> void:
	var before: Vector2 = _s2w(at)
	_mpu = clampf(_mpu * k, 4.0, 420.0)
	if not _follow:
		var after: Vector2 = _s2w(at)
		_mc += before - after


# ------------------------------------------------------------------ prediction

## Bomb fall (same integrator as WeaponWorld) with a long enough horizon for high-altitude drops.
func _predict(pos: Vector3, vel: Vector3) -> Vector3:
	var p: Vector3 = pos
	var v: Vector3 = vel
	var dt: float = 0.1
	_fall_t = 0.0
	for s in 480:
		v.y -= BOMB_G * dt
		var damp: float = 1.0 - BOMB_DRAG * dt
		v.x *= damp
		v.z *= damp
		var np: Vector3 = p + v * dt
		var h: float = Weapons.ground_height(np)
		if np.y <= h:
			var f: float = clampf((p.y - h) / maxf(p.y - np.y, 0.0001), 0.0, 1.0)
			var out: Vector3 = p.lerp(np, f)
			out.y = h
			_fall_t = (float(s) + f) * dt
			return out
		p = np
	_fall_t = 48.0
	return p


func _heading_h() -> Vector3:
	var v: Vector3 = Vector3(aircraft.velocity.x, 0.0, aircraft.velocity.z)
	if v.length_squared() < 4.0:
		v = aircraft.get_forward()
		v.y = 0.0
	return v.normalized() if v.length_squared() > 0.0001 else Vector3.FORWARD


func _solve() -> void:
	var h: Vector3 = _heading_h()
	var pos: Vector3 = Vector3(aircraft.global_position.x, dial_alt * WorldCoords.VERTICAL_SCALE - 1.8, aircraft.global_position.z)
	var keep: float = _fall_t
	marker = _predict(pos, h * (dial_speed / KMH))
	if _fall_t <= 0.0:
		_fall_t = keep


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		return
	_blink += delta
	if _dbg != "":
		_debug_step()
	for s in _splashes:
		s["t"] = float(s["t"]) + delta
	GameState.sight_dials = active
	if active:
		if aircraft.state != Aircraft.State.ALIVE or aircraft.on_ground or aircraft.altitude_agl < 120.0:
			if aircraft.state == Aircraft.State.ALIVE and not aircraft.on_ground:
				_say("Bombsight off: terrain")
			set_active(false)
			return
		_adjust_dials(delta)
	if active or map_open:
		_solve()
		_tgt_t -= delta
		if _tgt_t <= 0.0:
			_tgt_t = 1.0
			_refresh_targets()
		_near_t -= delta
		if _near_t <= 0.0:
			_near_t = 0.4
			_near_enemy = _nearest_enemy()
	if active:
		_update_cam()
		_sight_ui.queue_redraw()
	if map_open:
		if _follow:
			_mc = Vector2(aircraft.global_position.x, aircraft.global_position.z)
		_map_ui.queue_redraw()


func _debug_step() -> void:
	_dbg_f += 1
	if _dbg_f >= 50 and _dbg_f < 200 and _dbg_f % 10 == 0 and not active and not map_open and _dbg.begins_with("--sight"):
		print("SIGHTDBG try f=%d gnd=%s agl=%.0f bombs=%d" % [_dbg_f, aircraft.on_ground, aircraft.altitude_agl, aircraft.bombs])
		if _dbg != "--sight=off":
			dial_speed = roundf(aircraft.speed * KMH)
			dial_alt = roundf(aircraft.get_altitude_m())
		set_active(true)
	elif _dbg_f == 50 and _dbg == "--tacmap":
		set_map(true)
	elif _dbg_f == 120 and _dbg.begins_with("--sight") and OS.get_cmdline_user_args().has("--sightmap"):
		set_map(true)


func _adjust_dials(delta: float) -> void:
	var ds: float = _axis("sight_spd_down", "sight_spd_up", delta)
	var da: float = _axis("sight_alt_down", "sight_alt_up", delta)
	if ds != 0.0:
		dial_speed = clampf(dial_speed + ds * 5.0, 100.0, 700.0)
	if da != 0.0:
		dial_alt = clampf(dial_alt + da * 10.0, 100.0, 9000.0)


## +/-1 per step: one on press, then after 0.35 s repeats (accelerating the longer it is held).
func _axis(neg: String, pos: String, delta: float) -> float:
	var out: float = 0.0
	for pair in [[neg, -1.0], [pos, 1.0]]:
		var act: String = pair[0]
		var sgn: float = pair[1]
		if Input.is_action_just_pressed(act):
			_held[act] = 0.0
			out += sgn
		elif Input.is_action_pressed(act):
			var t: float = float(_held.get(act, 0.0)) + delta
			var rate: float = 0.0
			if t > 0.35:
				rate = 6.0 + minf((t - 0.35) * 14.0, 40.0)
			var carry: float = float(_held.get(act + "_c", 0.0)) + rate * delta
			var steps: float = floorf(carry)
			_held[act + "_c"] = carry - steps
			_held[act] = t
			out += sgn * steps
		else:
			_held.erase(act)
			_held.erase(act + "_c")
	return out


func _update_cam() -> void:
	if _cam == null:
		return
	var h: Vector3 = _heading_h()
	var pos: Vector3 = aircraft.global_position + h * aircraft.stats.radius * 0.45 + Vector3.DOWN * 2.2
	var look: Vector3 = marker - pos
	if look.length() < 5.0:
		look = Vector3.DOWN
	look = look.normalized()
	if absf(look.dot(h)) > 0.995:
		look = (look + Vector3.DOWN * 0.2).normalized()
	_cam.global_transform = Transform3D(Basis.looking_at(look, h), pos)


func _nearest_enemy() -> float:
	var best: float = 99999.0
	for n in get_tree().get_nodes_in_group("aircraft"):
		var e: Aircraft = n as Aircraft
		if e == null or e == aircraft or e.team == aircraft.team or e.team == "Neutral" or e.state != Aircraft.State.ALIVE:
			continue
		best = minf(best, e.global_position.distance_to(aircraft.global_position))
	return best


func _refresh_targets() -> void:
	_targets.clear()
	var m: Node = null
	if world != null:
		var mv: Variant = world.get("mode")
		m = mv as Node
	if m != null and m.has_method("map_pins"):
		return          # free flight with the Ops Room: only announced taskings are pinned (see _draw_pins)
	if m != null and m.get("inner") != null:
		m = m.get("inner") as Node
	if m != null and m.get("targets") is Array:
		var names: Dictionary = m.get("target_names") if m.get("target_names") is Dictionary else {}
		var ids: Array = m.get("target_ids") if m.get("target_ids") is Array else []
		var arr: Array = m.get("targets")
		for i in arr.size():
			var n: Variant = arr[i]
			if not is_instance_valid(n) or not (n is Node3D):
				continue
			var nm: String = str(names.get(ids[i], "")) if i < ids.size() else ""
			if nm == "":
				nm = str((n as Node).name)
			_targets.append({"node": n, "name": nm})
	if _targets.is_empty():
		for n2 in get_tree().get_nodes_in_group("mission_target"):
			if n2 is Node3D and str(n2.get("team")) != aircraft.team:
				_targets.append({"node": n2, "name": str((n2 as Node).name)})


## Pins from the game mode: the Ops Room's announced objective / rendezvous / V-1s (map_pins), or else the
## mode's current waypoint (nav_point). Off-chart pins sit on the frame edge with their distance.
func _draw_pins(c: Control, ppos: Vector3) -> void:
	var m: Node = get_tree().get_first_node_in_group("game_mode")
	if m == null:
		return
	var pins: Array = []
	if m.has_method("map_pins"):
		pins = m.call("map_pins")
	elif m.has_method("nav_point"):
		var np: Variant = m.call("nav_point")
		if np != null:
			pins.append({"pos": np, "name": "Objective", "col": Color(1.0, 0.82, 0.25), "main": true})
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
	var placed: Array = []      # label rects already drawn, so stacked edge pins don't print over each other
	var font: Font = ThemeDB.fallback_font
	for pin in pins:      # reserve every pin marker first so no label is printed across another pin
		if pin["pos"] != null:
			var q: Vector2 = _w2s(pin["pos"]).clamp(_mrect.position + Vector2(28, 28), _mrect.end - Vector2(28, 64))
			placed.append(Vector3(q.x - 16.0, q.y + 5.0, 32.0))
	for pin in pins:
		if pin["pos"] == null:
			continue
		var wp: Vector3 = pin["pos"]
		var sp: Vector2 = _w2s(wp)
		var col: Color = pin["col"]
		# off-chart pins sit on the edge, clear of the frame and of the status strip along the bottom
		var pc: Vector2 = sp.clamp(_mrect.position + Vector2(28, 28), _mrect.end - Vector2(28, 64))
		var off: bool = pc.distance_to(sp) > 1.0
		var r: float = (12.0 if bool(pin.get("main", false)) else 8.0) + 2.0 * pulse
		var dia := PackedVector2Array([pc + Vector2(0, -r), pc + Vector2(r, 0), pc + Vector2(0, r), pc + Vector2(-r, 0)])
		c.draw_colored_polygon(dia, Color(col, 0.45))
		dia.append(dia[0])
		c.draw_polyline(dia, col, 2.5)
		if bool(pin.get("main", false)):
			c.draw_arc(pc, r + 8.0 + 8.0 * pulse, 0.0, TAU, 32, Color(col, 0.6 * (1.0 - pulse)), 2.0)
			c.draw_line(_w2s(ppos), pc, Color(col, 0.35), 1.5)
		var km: float = Vector2(wp.x - ppos.x, wp.z - ppos.z).length() * WorldCoords.HORIZ_COMPRESSION / 1000.0
		if off:      # small arrow pointing on towards the real position
			var d: Vector2 = (sp - pc).normalized()
			c.draw_line(pc + d * (r + 3.0), pc + d * (r + 14.0), col, 2.5)
		var label: String = "%s  %.0f km" % [str(pin["name"]), km]
		var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var lp: Vector2 = pc + Vector2(r + 8.0, 5.0)
		if lp.x + w > _mrect.end.x - 8.0:
			lp.x = pc.x - r - 8.0 - w
		for _i in 6:
			var hit := false
			for q in placed:
				if is_equal_approx(q.x, pc.x - 16.0) and is_equal_approx(q.y, pc.y + 5.0):
					continue
				if absf(q.y - lp.y) < 18.0 and lp.x < q.x + q.z and q.x < lp.x + w:
					hit = true
			if not hit:
				break
			lp.y -= 18.0
		placed.append(Vector3(lp.x, lp.y, w))
		_txt(c, label, lp, 15, col)


func _target_dead(n: Node) -> bool:
	var v: Variant = n.get("is_dead")
	return v != null and bool(v)


# ------------------------------------------------------------------ drawing helpers

func _txt(c: Control, text: String, pos: Vector2, size: int, col: Color, align: int = 0) -> void:
	var font: Font = ThemeDB.fallback_font
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x: float = pos.x - (w * 0.5 if align == 1 else (w if align == 2 else 0.0))
	c.draw_string(font, Vector2(x + 1.0, pos.y + 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.7))
	c.draw_string(font, Vector2(x, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _night_shade() -> float:
	return 0.35 + 0.65 * clampf(TimeOfDay.light_level * 1.4, 0.0, 1.0)


func _err_col(speed_err: float, alt_err: float) -> Color:
	if speed_err < 3.0 and alt_err < 10.0:
		return GREEN
	if speed_err < 10.0 and alt_err < 30.0:
		return AMBER
	return RED


# ------------------------------------------------------------------ bombsight view

func _draw_sight() -> void:
	if aircraft == null or _cam == null:
		return
	var c: Control = _sight_ui
	var sz: Vector2 = c.size
	var win := Rect2(sz.x * 0.2, sz.y * 0.05, sz.x * 0.6, sz.y * 0.9)
	var ctr: Vector2 = sz * 0.5
	# the bombardier's panel around the glass
	c.draw_rect(Rect2(0, 0, win.position.x, sz.y), PANEL)
	c.draw_rect(Rect2(win.end.x, 0, sz.x - win.end.x, sz.y), PANEL)
	c.draw_rect(Rect2(win.position.x, 0, win.size.x, win.position.y), PANEL)
	c.draw_rect(Rect2(win.position.x, win.end.y, win.size.x, sz.y - win.end.y), PANEL)
	c.draw_rect(win, GOLD * Color(1, 1, 1, 0.55), false, 3.0)
	# nose-glazing struts at the corners
	for sx in [0.0, 1.0]:
		for sy in [0.0, 1.0]:
			var corner := Vector2(win.position.x + win.size.x * sx, win.position.y + win.size.y * sy)
			var inward := Vector2(1.0 - 2.0 * sx, 1.0 - 2.0 * sy)
			c.draw_line(corner, corner + inward * Vector2(win.size.x * 0.16, win.size.y * 0.1), Color(0.05, 0.05, 0.04, 0.8), 7.0)
	# ground scale ticks along heading
	var ground_col := Color(0.04, 0.05, 0.04, 0.85)
	c.draw_line(Vector2(ctr.x, win.position.y + 14.0), Vector2(ctr.x, ctr.y - 26.0), ground_col, 2.0)
	c.draw_line(Vector2(ctr.x, ctr.y + 26.0), Vector2(ctr.x, win.end.y - 14.0), ground_col, 2.0)
	c.draw_line(Vector2(win.position.x + 14.0, ctr.y), Vector2(ctr.x - 26.0, ctr.y), ground_col, 2.0)
	c.draw_line(Vector2(ctr.x + 26.0, ctr.y), Vector2(win.end.x - 14.0, ctr.y), ground_col, 2.0)
	for i in range(1, 6):
		var yy: float = ctr.y - float(i) * win.size.y * 0.075
		c.draw_line(Vector2(ctr.x - 7.0, yy), Vector2(ctr.x + 7.0, yy), ground_col, 2.0)
		yy = ctr.y + float(i) * win.size.y * 0.075
		c.draw_line(Vector2(ctr.x - 7.0, yy), Vector2(ctr.x + 7.0, yy), ground_col, 2.0)
	# splash radius ring (what the bomb load will cover)
	var st: AircraftStats = aircraft.stats
	var edge: Vector2 = _cam.unproject_position(marker + _cam.global_transform.basis.x * st.bomb_radius)
	var ring_r: float = clampf(edge.distance_to(ctr), 8.0, 400.0)
	var sync: Color = _err_col(absf(aircraft.speed * KMH - dial_speed), absf(aircraft.get_altitude_m() - dial_alt))
	c.draw_arc(ctr, ring_r, 0.0, TAU, 48, Color(sync, 0.9), 2.0)
	c.draw_arc(ctr, 4.0, 0.0, TAU, 12, Color(sync, 0.95), 2.0)
	# targets and previous splashes inside the glass
	var fwd: Vector3 = _heading_h()
	var nearest: float = 1.0e12
	var near_name: String = ""
	for t in _targets:
		var n: Node3D = t["node"] as Node3D
		if not is_instance_valid(n):
			continue
		var dead: bool = _target_dead(n)
		var wp: Vector3 = n.global_position
		var rel: Vector3 = wp - _cam.global_position
		var off: float = Vector2(wp.x - marker.x, wp.z - marker.z).length()
		if not dead and off < nearest:
			nearest = off
			near_name = str(t["name"])
		var col: Color = Color(0.5, 0.5, 0.5, 0.8) if dead else Color(1.0, 0.3, 0.2)
		if rel.dot(-_cam.global_transform.basis.z) <= 0.0:
			continue
		var sp: Vector2 = _cam.unproject_position(wp)
		if win.grow(-18.0).has_point(sp):
			var r: float = 11.0
			c.draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0)]), Color(col, 0.28))
			c.draw_polyline(PackedVector2Array([sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0), sp + Vector2(0, -r)]), col, 2.0)
			_txt(c, str(t["name"]).to_upper(), sp + Vector2(r + 8.0, 5.0), 14, col)
		else:
			var dir: Vector2 = (sp - ctr).normalized()
			var edge_pt: Vector2 = ctr + dir * minf(win.size.x, win.size.y) * 0.44
			var side := Vector2(-dir.y, dir.x)
			c.draw_colored_polygon(PackedVector2Array([edge_pt + dir * 12.0, edge_pt - dir * 6.0 + side * 8.0, edge_pt - dir * 6.0 - side * 8.0]), col)
	for sp_d in _splashes:
		var spl: Vector3 = sp_d["pos"]
		if float(sp_d["t"]) > 120.0 or (spl - _cam.global_position).dot(-_cam.global_transform.basis.z) <= 0.0:
			continue
		var s2: Vector2 = _cam.unproject_position(spl)
		if win.grow(-12.0).has_point(s2):
			c.draw_line(s2 + Vector2(-7, -7), s2 + Vector2(7, 7), AMBER, 2.0)
			c.draw_line(s2 + Vector2(-7, 7), s2 + Vector2(7, -7), AMBER, 2.0)
	# release cue
	var rad: float = st.bomb_radius
	if nearest < rad * 0.9:
		var on: bool = fmod(_blink, 0.5) < 0.3
		if on:
			_txt(c, "TARGET IN SIGHT: RELEASE", Vector2(ctr.x, win.position.y + 44.0), 24, GREEN, 1)
	elif nearest < 1.0e11:
		_txt(c, "%s  %.1f KM TO HIT POINT" % [near_name.to_upper(), nearest * WorldCoords.HORIZ_COMPRESSION / 1000.0], Vector2(ctr.x, win.position.y + 38.0), 18, INK, 1)
	if _near_enemy < 1100.0:
		var gun: bool = turrets != null and turrets.engaged
		_txt(c, "FIGHTERS CLOSE%s  -  N TO BREAK OFF" % ("  -  GUNNERS ENGAGING" if gun else ""), Vector2(ctr.x, win.end.y - 22.0), 20, RED if fmod(_blink, 0.6) < 0.4 else AMBER, 1)
	# left panel: settings
	var lx: float = 22.0
	var pw: float = win.position.x - 40.0
	var y: float = 56.0
	_txt(c, "BOMBSIGHT", Vector2(lx, y), 24, GOLD)
	y += 14.0
	c.draw_line(Vector2(lx, y), Vector2(lx + pw, y), Color(GOLD, 0.5), 2.0)
	y += 40.0
	var actual_spd: float = aircraft.speed * KMH
	var actual_alt: float = aircraft.get_altitude_m()
	var se: float = absf(actual_spd - dial_speed)
	var ae: float = absf(actual_alt - dial_alt)
	_txt(c, "SPEED SETTING   < >  (D-PAD)", Vector2(lx, y), 16, Color(INK, 0.75))
	y += 40.0
	_txt(c, "%d km/h" % int(round(dial_speed)), Vector2(lx, y), 36, GOLD)
	y += 28.0
	_txt(c, "airspeed now  %d km/h" % int(round(actual_spd)), Vector2(lx, y), 16, _err_col(se, 0.0))
	y += 52.0
	_txt(c, "ALTITUDE SETTING   ^ v  (D-PAD)", Vector2(lx, y), 16, Color(INK, 0.75))
	y += 40.0
	_txt(c, "%d m" % int(round(dial_alt)), Vector2(lx, y), 36, GOLD)
	y += 28.0
	_txt(c, "altitude now  %d m" % int(round(actual_alt)), Vector2(lx, y), 16, _err_col(0.0, ae))
	y += 44.0
	if se >= 3.0 or ae >= 10.0:
		_txt(c, "SETTINGS DO NOT MATCH", Vector2(lx, y), 17, sync)
		y += 22.0
		_txt(c, "THE HIT MARKER IS WRONG", Vector2(lx, y), 17, sync)
	else:
		_txt(c, "SIGHT SYNCHRONISED", Vector2(lx, y), 17, GREEN)
	y += 50.0
	_txt(c, "THROTTLE: SHIFT / CTRL  (TRIGGERS)", Vector2(lx, y), 15, Color(INK, 0.6))
	y += 20.0
	_txt(c, "STEER: A D  Q E  (LEFT STICK)", Vector2(lx, y), 15, Color(INK, 0.6))
	# right panel: status
	var rx: float = win.end.x + 22.0
	y = 56.0
	_txt(c, "RELEASE", Vector2(rx, y), 24, GOLD)
	y += 14.0
	c.draw_line(Vector2(rx, y), Vector2(sz.x - 22.0, y), Color(GOLD, 0.5), 2.0)
	y += 38.0
	_txt(c, "BOMBS  %d / %d" % [aircraft.bombs, st.bombs], Vector2(rx, y), 22, INK)
	y += 32.0
	_txt(c, "FALL TIME  %.1f s" % _fall_t, Vector2(rx, y), 18, Color(INK, 0.85))
	y += 28.0
	_txt(c, "HEADING  %03d" % int(round(aircraft.get_heading_deg())), Vector2(rx, y), 18, Color(INK, 0.85))
	y += 28.0
	var ll: Vector2 = WorldCoords.world_to_latlon(marker)
	_txt(c, "HIT POINT", Vector2(rx, y), 16, Color(INK, 0.6))
	y += 22.0
	_txt(c, "%.3f N  %.3f %s" % [ll.x, absf(ll.y), "E" if ll.y >= 0.0 else "W"], Vector2(rx, y), 16, Color(INK, 0.85))
	y += 40.0
	_txt(c, "SPACE  DROP BOMB  (PAD: A)", Vector2(rx, y), 17, GOLD)
	y += 24.0
	_txt(c, "M  CHART  (PAD: BACK)", Vector2(rx, y), 16, Color(INK, 0.7))
	y += 22.0
	_txt(c, "N  LEAVE SIGHT", Vector2(rx, y), 16, Color(INK, 0.7))
	if aircraft.bombs <= 0:
		_txt(c, "BOMBS GONE", Vector2(ctr.x, win.end.y - 60.0), 28, AMBER, 1)


# ------------------------------------------------------------------ map

func _s2w(s: Vector2) -> Vector2:
	return _mc + (s - _mrect.get_center()) * _mpu


func _w2s(p: Vector3) -> Vector2:
	return _mrect.get_center() + (Vector2(p.x, p.z) - _mc) / _mpu


func _draw_map() -> void:
	if aircraft == null:
		return
	var c: Control = _map_ui
	var sz: Vector2 = c.size
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.88))
	_mrect = Rect2(sz.x * 0.05, sz.y * 0.075, sz.x * 0.9, sz.y * 0.85)
	var shade: float = _night_shade()
	c.draw_rect(_mrect, Color(0.07, 0.1, 0.13))
	# imagery: intersect the visible world rect with the map bounds
	if _color_tex != null:
		var half: Vector2 = _mrect.size * 0.5 * _mpu
		var vis := Rect2(_mc - half, half * 2.0).intersection(_bounds)
		if vis.size.x > 0.0 and vis.size.y > 0.0:
			var tw: float = float(_color_tex.get_width())
			var th: float = float(_color_tex.get_height())
			var src := Rect2((vis.position.x - _bounds.position.x) / _bounds.size.x * tw, (vis.position.y - _bounds.position.y) / _bounds.size.y * th, vis.size.x / _bounds.size.x * tw, vis.size.y / _bounds.size.y * th)
			var dst := Rect2(_w2s(Vector3(vis.position.x, 0, vis.position.y)), vis.size / _mpu)
			c.draw_texture_rect_region(_color_tex, dst, src, Color(shade, shade, shade * 1.04, 1.0))
	# 10 km grid (real distance)
	var grid: float = 10000.0 * WorldCoords.HORIZ_COMPRESSION
	var step_px: float = grid / _mpu
	var gmul: float = 1.0
	while step_px * gmul < 70.0:
		gmul *= 2.0
	var g: float = grid * gmul
	var gx: float = ceilf((_mc.x - _mrect.size.x * 0.5 * _mpu) / g) * g
	while gx < _mc.x + _mrect.size.x * 0.5 * _mpu:
		var sx: float = _w2s(Vector3(gx, 0, _mc.y)).x
		c.draw_line(Vector2(sx, _mrect.position.y), Vector2(sx, _mrect.end.y), Color(1, 1, 1, 0.07), 1.0)
		gx += g
	var gz: float = ceilf((_mc.y - _mrect.size.y * 0.5 * _mpu) / g) * g
	while gz < _mc.y + _mrect.size.y * 0.5 * _mpu:
		var sy: float = _w2s(Vector3(_mc.x, 0, gz)).y
		c.draw_line(Vector2(_mrect.position.x, sy), Vector2(_mrect.end.x, sy), Color(1, 1, 1, 0.07), 1.0)
		gz += g
	# towns
	var font: Font = ThemeDB.fallback_font
	for ct in _cities:
		var sp: Vector2 = _w2s(Vector3(ct["pos"].x, 0, ct["pos"].y))
		if not _mrect.has_point(sp):
			continue
		var sz_i: int = int(ct["size"])
		c.draw_circle(sp, 2.0 + float(sz_i) * 0.8, Color(0.95, 0.95, 0.9, 0.85))
		if sz_i >= 3 or _mpu < 25.0:
			_txt(c, str(ct["name"]), sp + Vector2(7, 4), 13, Color(0.96, 0.96, 0.9, 0.9))
	var home_side: String = "RAF" if aircraft.team == "Allies" else "Luftwaffe"
	for af in _fields:
		var sp2: Vector2 = _w2s(Vector3(af["pos"].x, 0, af["pos"].y))
		if not _mrect.has_point(sp2):
			continue
		var fr: bool = str(af["side"]) == home_side
		var col2: Color = Color(0.5, 1.0, 0.55) if fr else Color(1.0, 0.55, 0.4)
		c.draw_rect(Rect2(sp2 - Vector2(4, 4), Vector2(8, 8)), Color(col2, 0.25))
		c.draw_rect(Rect2(sp2 - Vector2(4, 4), Vector2(8, 8)), col2, false, 1.5)
		if _mpu < 18.0:
			_txt(c, str(af["name"]), sp2 + Vector2(8, 4), 12, Color(col2, 0.9))
	# targets
	var ppos: Vector3 = aircraft.global_position
	for t in _targets:
		var n: Node3D = t["node"] as Node3D
		if not is_instance_valid(n):
			continue
		var tp: Vector2 = _w2s(n.global_position)
		var dead: bool = _target_dead(n)
		var tc: Color = Color(0.6, 0.6, 0.6) if dead else Color(1.0, 0.3, 0.22)
		var edge_clamped: Vector2 = tp.clamp(_mrect.position + Vector2(14, 14), _mrect.end - Vector2(14, 14))
		var r: float = 9.0
		c.draw_colored_polygon(PackedVector2Array([edge_clamped + Vector2(0, -r), edge_clamped + Vector2(r, 0), edge_clamped + Vector2(0, r), edge_clamped + Vector2(-r, 0)]), Color(tc, 0.35))
		c.draw_polyline(PackedVector2Array([edge_clamped + Vector2(0, -r), edge_clamped + Vector2(r, 0), edge_clamped + Vector2(0, r), edge_clamped + Vector2(-r, 0), edge_clamped + Vector2(0, -r)]), tc, 2.0)
		var dist_km: float = Vector2(n.global_position.x - ppos.x, n.global_position.z - ppos.z).length() * WorldCoords.HORIZ_COMPRESSION / 1000.0
		_txt(c, "%s  %.0f km%s" % [str(t["name"]), dist_km, "  (destroyed)" if dead else ""], edge_clamped + Vector2(r + 8.0, 5.0), 15, tc)
	# aircraft, faint course line, hit marker
	var ap: Vector2 = _w2s(ppos)
	var hd: Vector3 = _heading_h()
	var dir2 := Vector2(hd.x, hd.z)
	var segs: int = 36
	var span: float = 90000.0 * WorldCoords.HORIZ_COMPRESSION
	for i in segs:
		if i % 2 == 1:
			continue
		var a0: float = float(i) / float(segs)
		var a1: float = float(i + 1) / float(segs)
		c.draw_line(ap + dir2 * (a0 * span / _mpu), ap + dir2 * (a1 * span / _mpu), Color(1.0, 0.95, 0.5, 0.5 * (1.0 - a0)), 1.5)
	_draw_pins(c, ppos)
	var mp: Vector2 = _w2s(marker)
	if not chart_only:
		c.draw_line(ap, mp, Color(1.0, 0.45, 0.3, 0.28), 1.0)
	var st: AircraftStats = aircraft.stats
	var mr: float = maxf(st.bomb_radius / _mpu, 6.0)
	var sync: Color = _err_col(absf(aircraft.speed * KMH - dial_speed), absf(aircraft.get_altitude_m() - dial_alt))
	if not chart_only:
		c.draw_arc(mp, mr, 0.0, TAU, 32, Color(sync, 0.95), 2.0)
		c.draw_line(mp + Vector2(-mr - 5, 0), mp + Vector2(mr + 5, 0), Color(sync, 0.95), 1.5)
		c.draw_line(mp + Vector2(0, -mr - 5), mp + Vector2(0, mr + 5), Color(sync, 0.95), 1.5)
		_txt(c, "HIT POINT", mp + Vector2(mr + 8.0, -6.0), 13, Color(sync, 0.95))
	for sp_d in _splashes:
		var s3: Vector2 = _w2s(sp_d["pos"])
		c.draw_line(s3 + Vector2(-5, -5), s3 + Vector2(5, 5), AMBER, 2.0)
		c.draw_line(s3 + Vector2(-5, 5), s3 + Vector2(5, -5), AMBER, 2.0)
	var side := Vector2(-dir2.y, dir2.x)
	var ac_pt: Vector2 = ap.clamp(_mrect.position + Vector2(10, 10), _mrect.end - Vector2(10, 10))
	c.draw_colored_polygon(PackedVector2Array([ac_pt + dir2 * 15.0, ac_pt - dir2 * 10.0 + side * 9.0, ac_pt - dir2 * 5.0, ac_pt - dir2 * 10.0 - side * 9.0]), Color(0, 0, 0, 0.75))
	c.draw_colored_polygon(PackedVector2Array([ac_pt + dir2 * 12.0, ac_pt - dir2 * 8.0 + side * 7.0, ac_pt - dir2 * 4.0, ac_pt - dir2 * 8.0 - side * 7.0]), Color(1.0, 0.9, 0.3))
	# frame, scale bar, title
	c.draw_rect(_mrect, GOLD * Color(1, 1, 1, 0.6), false, 2.0)
	var bar_units: float = g
	c.draw_line(Vector2(_mrect.position.x + 18.0, _mrect.end.y - 22.0), Vector2(_mrect.position.x + 18.0 + bar_units / _mpu, _mrect.end.y - 22.0), INK, 3.0)
	_txt(c, "%d km" % int(round(bar_units * WorldCoords.HORIZ_COMPRESSION / 1000.0)), Vector2(_mrect.position.x + 18.0, _mrect.end.y - 30.0), 14, INK)
	_txt(c, "TACTICAL CHART" if not chart_only else "CHART", Vector2(_mrect.position.x, _mrect.position.y - 14.0), 22, GOLD)
	_txt(c, "WHEEL ZOOM   DRAG PAN   HOME RECENTRE   M CLOSE", Vector2(_mrect.end.x, _mrect.position.y - 14.0), 15, Color(INK, 0.75), 2)
	var info: String = "SPD %d km/h   ALT %d m   HDG %03d   BOMBS %d" % [int(round(aircraft.speed * KMH)), int(round(aircraft.get_altitude_m())), int(round(aircraft.get_heading_deg())), aircraft.bombs]
	_txt(c, info, Vector2(_mrect.end.x - 12.0, _mrect.end.y - 12.0), 16, INK, 2)
	if not active and not chart_only:
		_txt(c, "N: BOMBSIGHT (HIT POINT FOLLOWS ITS SETTINGS: %d km/h, %d m)" % [int(round(dial_speed)), int(round(dial_alt))], Vector2(_mrect.position.x + 18.0, _mrect.position.y + 24.0), 15, Color(INK, 0.7))
