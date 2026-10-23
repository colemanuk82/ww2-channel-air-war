class_name BailOut
extends Node
## Bail out of the player's aircraft (hold J for a second): the canopy goes, the pilot jumps, the aircraft is left to
## spin in, and a camera follows the parachute down. Where he lands decides what happens next:
##   "safe"     - own territory: picked up, back to the squadron
##   "sea"      - in the Channel: the dinghy and the rescue flight (DitchRescue)
##   "captured" - enemy territory
## main.gd owns one of these; `resolved(fate, pos)` fires once the pilot is down (or the player skips the descent).

signal resolved(fate: String, pos: Vector3)

const HOLD_TIME := 0.9         # seconds J must be held (no accidental bail-outs)
const MIN_AGL := 70.0          # metres: lower than this the parachute cannot open
const SKIP_AFTER := 4.0        # seconds into the descent before Enter / J skips to the landing

var active: bool = false       # the pilot is on the parachute (or just landed, before resolution)
var pending_respawn: bool = false
var _hold: float = 0.0
var _chute: Parachute
var _cam: Camera3D
var _t: float = 0.0
var _land_t: float = -1.0
var _yaw: float = 0.0
var _hud: Node
var _aircraft: Aircraft
var _done: bool = false


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
	if player == null or not is_instance_valid(player) or player.state != Aircraft.State.ALIVE or player.on_ground:
		_hold = 0.0
		return
	if not InputMap.has_action("bail_out"):
		return
	if Input.is_action_pressed("bail_out"):
		if _hold == 0.0:
			_msg("BAIL OUT - keep holding J", 1.2)
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
	if _chute == null or not is_instance_valid(_chute):
		_resolve()
		return
	var cp: Vector3 = _chute.global_position
	_yaw += delta * 0.12
	var want: Vector3 = cp + Vector3(sin(_yaw) * 26.0, 7.0, cos(_yaw) * 26.0)
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
	if _cam != null and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	active = false
	_done = true


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
