class_name BailOut
extends Node
## Bail out of the player's aircraft (hold J for a second): the canopy goes, the pilot jumps, the aircraft is left to
## spin in, and a camera follows the parachute down. Where he lands decides what happens next:
##   "safe"     - own territory: picked up, back to the squadron
##   "sea"      - in the Channel: the dinghy and the rescue flight (DitchRescue)
##   "captured" - enemy territory
## main.gd owns one of these; `resolved(fate, pos)` fires once the pilot is down (or the player skips the descent).

signal resolved(fate: String, pos: Vector3)

const HOLD_TIME := 0.6         # seconds J must be held (still deliberate, but quick under fire)
const MIN_AGL := 55.0          # metres: lower than this the parachute cannot open
const DYING_GRACE := 2.5       # after a fatal hit the pilot can still get out for a moment
const SKIP_AFTER := 1.5        # seconds into the descent before Enter / J skips to the landing

var active: bool = false       # the pilot is on the parachute (or just landed, before resolution)
var pending_respawn: bool = false
var _hold: float = 0.0
var _dying_t: float = 0.0
var _late_shown: bool = false
var _chute: Parachute
var _cam: Camera3D
var _t: float = 0.0
var _land_t: float = -1.0
var _yaw: float = 0.0
var _look_yaw: float = 0.0     # right-stick orbit around the pilot
var _look_pitch: float = 0.15
var _hint_layer: CanvasLayer
var _hint: Label
var _hud: Node
var _aircraft: Aircraft
var _done: bool = false
var _was_alive: bool = false


func setup(hud: Node) -> void:
	_hud = hud
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _msg(text: String, t: float = 3.0) -> void:
	if _hud != null and is_instance_valid(_hud) and _hud.has_method("show_message"):
		_hud.call("show_message", text, t)


## Called every frame by main with the current player aircraft.
func tick(delta: float, player: Aircraft) -> void:
	if active:
		_follow(delta)
		return
	if player == null or not is_instance_valid(player):
		_hold = 0.0
		_dying_t = 0.0
		_was_alive = false
		return
	# A hit that sets the aircraft DYING does not close the door immediately: give the pilot a
	# moment to get out, and make the hold shorter than the old one-second rule.
	if player.state == Aircraft.State.DYING:
		if _was_alive:
			_dying_t = 0.0
			_late_shown = false
			_msg("AIRCRAFT GOING DOWN - bail out now!", 2.0)
		_dying_t += delta
	else:
		_dying_t = 0.0
		_late_shown = false
	var alive: bool = player.state == Aircraft.State.ALIVE
	var can_bail: bool = alive or (player.state == Aircraft.State.DYING and _dying_t <= DYING_GRACE)
	_was_alive = alive
	if not can_bail or player.on_ground:
		_hold = 0.0
		if player.state == Aircraft.State.DYING and player.state != Aircraft.State.DEAD and not player.on_ground \
				and _dying_t > DYING_GRACE and not _late_shown:
			_late_shown = true
			_msg("TOO LATE TO BAIL OUT", 2.5)
		return
	if not InputMap.has_action("bail_out"):
		return
	if Input.is_action_pressed("bail_out") and not (GameState.sight_dials and GameState.dpad_held()):
		if _hold == 0.0:
			_msg("BAIL OUT - keep holding", 1.2)
		_hold += delta
		if _hold >= HOLD_TIME:
			_hold = 0.0
			if player.altitude_agl < MIN_AGL:
				_msg("TOO LOW TO BAIL OUT - climb or force-land", 2.5)
			else:
				_jump(player)
	else:
		_hold = 0.0


func _jump(player: Aircraft) -> void:
	_aircraft = player
	var pos: Vector3 = player.global_position + player.global_transform.basis.y * 2.0 - player.global_transform.basis.z * 1.0
	_chute = FX.parachute(pos, "", player.team)
	if _chute == null:
		_msg("Cannot bail out now", 2.0)
		return
	# the rest of the crew follow him out, one parachute each (staggered, a little behind)
	for i in range(1, player.crew_count()):
		var off: Vector3 = player.global_transform.basis.z * float(i) * 9.0 + Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
		get_tree().create_timer(0.5 * float(i)).timeout.connect(func() -> void:
			FX.parachute(pos + off, "", player.team))
	active = true
	_done = false
	_t = 0.0
	_land_t = -1.0
	_yaw = player.rotation.y + PI * 0.5
	FX.sfx("hit", pos, -4.0)
	# the abandoned aircraft: controls let go, throttle cut, and it is finished (modes count it as lost)
	player.cmd_pitch = 0.0
	player.cmd_roll = 0.35
	player.cmd_yaw = 0.0
	player.cmd_fire = false
	player.throttle_target = 0.0
	player.player_controlled = false
	player.set_meta("bailed", true)       # the pilot is already out: no second parachute from the wreck
	player.take_damage(1.0e6, null)
	_look_yaw = 0.0
	_look_pitch = 0.15
	_make_hint()
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 60000.0
	get_tree().current_scene.add_child(_cam)
	_cam.global_position = pos + Vector3(0, 6, 30)
	_cam.make_current()
	Radio.say("You", ["Bailing out!", "I'm getting out!", "Hit the silk!"][randi() % 3], Radio.Kind.FRIENDLY, 0.0)
	_msg("Bailed out. Enter or J skips the descent.", 4.0)


func _follow(delta: float) -> void:
	_t += delta
	if _chute == null or not is_instance_valid(_chute) or _t > 150.0:    # lost chute / never landed: never hang here
		_resolve()
		return
	var cp: Vector3 = _chute.global_position
	var rdt: float = delta / maxf(Engine.time_scale, 0.1)       # real-time delta: the stick must not speed up with the warp
	_yaw += delta * 0.12
	_look_yaw += Input.get_axis("look_left", "look_right") * 2.2 * rdt
	_look_pitch = clampf(_look_pitch + Input.get_axis("look_up", "look_down") * 1.4 * rdt, -0.25, 1.2)
	var ang: float = _yaw + _look_yaw
	var want: Vector3 = cp + Vector3(sin(ang) * 26.0 * cos(_look_pitch), 7.0 + sin(_look_pitch) * 26.0, cos(ang) * 26.0 * cos(_look_pitch))
	_update_hint()
	var gh: float = FX.ground_height(want)
	want.y = maxf(want.y, gh + 3.0)
	if _cam != null and is_instance_valid(_cam):
		_cam.global_position = _cam.global_position.lerp(want, clampf(delta * 3.0, 0.0, 1.0))
		_cam.look_at(cp + Vector3(0, 3.5, 0), Vector3.UP)
	var landed: bool = not _chute.active or cp.y <= FX.ground_height(cp) + 1.2
	if landed and _land_t < 0.0:
		_land_t = _t
	if _land_t >= 0.0 and _t - _land_t > 2.5:
		_resolve()
	elif _t > SKIP_AFTER and (Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("bail_out")):
		# skip: drop the pilot straight down to where he would land
		var lp := Vector3(cp.x, FX.ground_height(cp) + 0.9, cp.z)
		_chute.global_position = lp
		_resolve()


func _resolve() -> void:
	if _done:
		return
	_done = true
	_end_ui()
	var pos: Vector3 = _chute.global_position if _chute != null and is_instance_valid(_chute) else (_cam.global_position if _cam != null else Vector3.ZERO)
	var team: String = GameState.player_side
	var fate: String = "safe"
	if FX.is_water(pos) or pos.y < 1.5:
		fate = "sea"
	elif GroundKit.side_at(pos) != team:
		fate = "captured"
	if _cam != null and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	active = false
	resolved.emit(fate, pos)


## Main calls this when it respawns / rebinds the player so the chute camera never lingers.
func cancel() -> void:
	_end_ui()
	if _cam != null and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	active = false
	_done = true
	_hold = 0.0
	_dying_t = 0.0
	_late_shown = false
	_was_alive = false


static func fate_text(fate: String, side: String) -> String:
	match fate:
		"safe":
			return "Landed safely in friendly country - picked up and driven back to the squadron." if side == "Allies" \
				else "Landed safely behind our lines - a Kübelwagen takes you back to the Staffel."
		"sea":
			return "Down in the Channel - the dinghy is out. The rescue flight is on its way."
		"captured":
			return "Landed behind enemy lines - the farmer's dog found you first. You are a prisoner of war." if side == "Allies" \
				else "Landed in England - the Home Guard were waiting. You are a prisoner of war."
	return ""


# ---------------------------------------------------------------- descent hint + time warp

func _make_hint() -> void:
	_end_ui()
	_hint_layer = CanvasLayer.new()
	_hint_layer.layer = 60
	add_child(_hint_layer)
	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -86.0
	_hint.offset_bottom = -20.0
	_hint.offset_left = -520.0
	_hint.offset_right = 520.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hint.add_theme_constant_override("outline_size", 6)
	_hint_layer.add_child(_hint)


func _update_hint() -> void:
	if _hint == null or not is_instance_valid(_hint):
		return
	var warp: String = "x%d" % GameState.sim_warp
	var skip: String = "ENTER / A / J : skip to respawn" if _t > SKIP_AFTER else "(skip available in a moment)"
	_hint.text = "%s\n] [ : time warp (%s)     Right stick : look around" % [skip, warp]


func _end_ui() -> void:
	if _hint_layer != null and is_instance_valid(_hint_layer):
		_hint_layer.queue_free()
	_hint_layer = null
	_hint = null
	GameState.reset_sim_warp()
	Engine.time_scale = 1.0
