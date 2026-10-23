class_name CameraRig
extends Node3D
## Chase camera (smooth follow, speed FOV, shake) + cockpit camera. Toggle with the "camera" action.
## bind(aircraft) to attach. Public: add_shake(amount), toggle_view(), is_cockpit, current_camera().

signal view_changed(cockpit: bool)
signal view_distance_changed(message: String, seconds: float)

@export var distance: float = 16.0
@export var height: float = 4.4
@export var base_fov: float = 66.0
@export var cockpit_fov: float = 80.0
@export var follow_rate: float = 5.5
@export var up_rate: float = 2.5
@export var view_dist_step: float = 1.12     # numpad +/-: chase camera distance scale per press (multiplicative)
@export var cockpit_zoom_step: float = 5.0   # numpad +/-: cockpit camera zoom, in FOV degrees per press

var target: Aircraft
var chase_cam: Camera3D
var cockpit_cam: Camera3D
var is_cockpit: bool = false
var overhead: bool = false
var overhead_alt: float = 2000.0

var _fwd: Vector3 = Vector3.FORWARD
var _up: Vector3 = Vector3.UP
var _fov: float = 66.0
var _shake: float = 0.0
var _terrain: Node
var _t: float = 0.0
var _look_yaw: float = 0.0     # free-look offset (gamepad right stick), radians
var _look_pitch: float = 0.0
var bomb_cam_on: bool = false       # follows a released bouncing bomb (see _process)
var _bomb_serial: int = 0
var _bomb_cam_linger: float = 0.0
var _bomb_cam_pos: Vector3 = Vector3.ZERO
var _bomb_cam_vel: Vector3 = Vector3.ZERO
const COCKPIT_STEADY_RATE: float = 6.0   # cockpit view: how fast it follows the airframe attitude (per second)
var _cock_basis: Basis = Basis.IDENTITY   # smoothed airframe attitude used by the cockpit camera
var _cock_ready: bool = false
var padlock: bool = false      # target view: aim the chase camera at the nearest aircraft
var _padlock_was: bool = false # last frame's padlock state, to snap back to centre on release

# Numpad view distance / zoom (numpad +, -, Enter). Per-session only: never written to settings.
var _dist_scale: float = 1.0        # smoothed chase distance multiplier (1.0 = the rig's own framing)
var _dist_scale_t: float = 1.0      # target the numpad steps toward
var _cockpit_fov: float = 80.0      # smoothed cockpit FOV
var _cockpit_fov_t: float = 80.0    # target the numpad steps toward
const ZOOM_SAVE_PATH := "user://chase_zoom.cfg"   # chase distance per plane, kept between sessions
var _zoom_plane: String = ""                       # stats id of the plane the chase zoom belongs to

const LOOK_RATE: float = 3.2        # rad/s while the stick is held
const LOOK_DEAD: float = 0.18       # stick deadzone
const LOOK_MAX_PITCH: float = 1.35  # ~77 deg
const ORBIT_MIN_EL: float = -1.15   # lowest the orbit camera may sit below the aircraft
const ORBIT_MAX_EL: float = 1.30    # highest it may rise above (keeps looking_at well defined)
const DIST_SCALE_MIN: float = 0.35  # numpad minus floor: how close the chase camera may pull in
const DIST_SCALE_MAX: float = 3.0   # numpad plus ceiling: how far it may back off
const COCKPIT_FOV_MIN: float = 35.0 # cockpit zoom-in floor (FOV degrees)
const COCKPIT_FOV_MAX: float = 95.0 # cockpit zoom-out ceiling (FOV degrees)
const VIEW_SMOOTH_RATE: float = 8.0 # per-second ease for the distance / zoom changes


func _ready() -> void:
	process_priority = 100
	add_to_group("camera_rig")
	_ensure_input_actions()
	_cockpit_fov = cockpit_fov
	_cockpit_fov_t = cockpit_fov
	_dist_scale = 1.0
	_dist_scale_t = 1.0
	chase_cam = Camera3D.new()
	chase_cam.name = "ChaseCam"
	chase_cam.near = 2.0
	chase_cam.far = 48000.0
	chase_cam.fov = base_fov
	add_child(chase_cam)
	chase_cam.make_current()


func bind(a: Aircraft) -> void:
	target = a
	_zoom_plane = str(a.stats.id) if a.stats else ""
	_dist_scale_t = _read_zoom(_zoom_plane)
	_dist_scale = _dist_scale_t
	if cockpit_cam and is_instance_valid(cockpit_cam):
		cockpit_cam.queue_free()
	cockpit_cam = Camera3D.new()
	cockpit_cam.name = "CockpitCam"
	cockpit_cam.near = 0.3
	cockpit_cam.far = 48000.0
	cockpit_cam.fov = cockpit_fov
	var mount: Node3D = a.get_cockpit_mount()
	(mount if mount else a).add_child(cockpit_cam)
	cockpit_cam.top_level = true   # placed each frame from the steadied attitude (see _steady_cockpit)
	_cock_ready = false
	_fwd = a.get_forward()
	_up = a.global_transform.basis.y
	_snap()
	set_cockpit(is_cockpit)


func current_camera() -> Camera3D:
	return cockpit_cam if is_cockpit else chase_cam


func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.5)


func toggle_view() -> void:
	set_cockpit(not is_cockpit)


## When true the cockpit view is held. Set by --cockpit.
##
## An earlier attempt enforced this every frame; that version failed to parse, which broke the whole rig
## (nothing rendered - Movie Maker recorded flat blue). It is set once instead, and the phantom toggle
## below is what actually needed suppressing.
var force_cockpit := false


func set_cockpit(on: bool) -> void:
	is_cockpit = on
	_cock_ready = false
	bomb_cam_on = false
	if target:
		target.set_cockpit_view(on)
	if on and cockpit_cam:
		cockpit_cam.make_current()
	else:
		chase_cam.make_current()
	view_changed.emit(on)


## Hold an orbit offset around the aircraft (degrees). Used by the screenshot tour so a
## shot can be framed from the side / front; cleared by set_orbit(0, 0).
func set_orbit(yaw_deg: float, pitch_deg: float) -> void:
	_look_yaw = deg_to_rad(yaw_deg)
	_look_pitch = deg_to_rad(clampf(pitch_deg, -77.0, 77.0))


## Chase distance for one plane, from its own file (settings.cfg is rewritten by GameState, so it stays separate).
static func _read_zoom(plane: String) -> float:
	var cf := ConfigFile.new()
	if plane == "" or cf.load(ZOOM_SAVE_PATH) != OK:
		return 1.0
	return clampf(float(cf.get_value("chase", plane, 1.0)), DIST_SCALE_MIN, DIST_SCALE_MAX)


## Saves the chase distance for the plane being flown; other planes' values are kept.
func _store_zoom() -> void:
	if _zoom_plane == "":
		return
	var cf := ConfigFile.new()
	cf.load(ZOOM_SAVE_PATH)
	cf.set_value("chase", _zoom_plane, _dist_scale_t)
	cf.save(ZOOM_SAVE_PATH)


## Numpad +/- : move the chase camera closer (+) / further (-), or zoom the cockpit camera in (+) / out (-).
## dir is +1 for the plus key and -1 for minus; the live value eases over a few frames (see _process).
func adjust_view_distance(dir: float) -> void:
	if is_cockpit:
		_cockpit_fov_t = clampf(_cockpit_fov_t - dir * cockpit_zoom_step, COCKPIT_FOV_MIN, COCKPIT_FOV_MAX)
		_notify_view_distance("Cockpit zoom FOV %.0f" % _cockpit_fov_t)
	else:
		_dist_scale_t = clampf(_dist_scale_t * (1.0 / view_dist_step if dir > 0.0 else view_dist_step), DIST_SCALE_MIN, DIST_SCALE_MAX)
		_store_zoom()
		_notify_view_distance("View distance %.0f%%" % (_dist_scale_t * 100.0))


## Numpad Enter: back to the current view's default (chase distance 1.0x, cockpit FOV = the rig's default).
func reset_view_distance() -> void:
	if is_cockpit:
		_cockpit_fov_t = cockpit_fov
		_notify_view_distance("Cockpit zoom reset (FOV %.0f)" % _cockpit_fov_t)
	else:
		_dist_scale_t = 1.0
		_store_zoom()
		_notify_view_distance("View distance reset (100%)")


## Console line + HUD toast (main wires view_distance_changed to hud.show_message).
func _notify_view_distance(msg: String) -> void:
	print("[camera] %s" % msg)
	view_distance_changed.emit(msg, 1.4)


## The view-distance actions are declared in project.godot [input]; register them here too if a build is
## missing them (mirrors GameState's runtime InputMap registration).
func _ensure_input_actions() -> void:
	_ensure_view_action("view_dist_increase", KEY_KP_ADD, KEY_EQUAL)
	_ensure_view_action("view_dist_decrease", KEY_KP_SUBTRACT, KEY_MINUS)
	_ensure_view_action("view_dist_reset", KEY_KP_ENTER, KEY_ENTER)


func _ensure_view_action(action: String, primary: Key, secondary: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.5)
	if not InputMap.action_get_events(action).is_empty():
		return
	var e1 := InputEventKey.new()
	e1.physical_keycode = primary
	InputMap.action_add_event(action, e1)
	var e2 := InputEventKey.new()
	e2.physical_keycode = secondary
	InputMap.action_add_event(action, e2)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera"):
		# --cockpit: a headless capture run delivers a phantom press of this action (the X button) during
		# startup, which flipped the view to chase and made every recording come out third-person. When the
		# view has been explicitly requested, ignore the toggle.
		if force_cockpit:
			return
		toggle_view()
	elif event.is_action_pressed("center_view"):
		_look_yaw = 0.0          # snap the free-look back ahead
		_look_pitch = 0.0
	elif event.is_action_pressed("view_dist_increase", true):   # echo: holding the key keeps it moving
		adjust_view_distance(1.0)
	elif event.is_action_pressed("view_dist_decrease", true):
		adjust_view_distance(-1.0)
	elif event.is_action_pressed("view_dist_reset"):
		reset_view_distance()


func _snap() -> void:
	if target == null:
		return
	var p: Vector3 = target.global_position
	if overhead:
		chase_cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), p + Vector3.UP * overhead_alt)
		return
	chase_cam.global_position = p - _fwd * distance + _up * height
	chase_cam.look_at(p + _fwd * 30.0, Vector3.UP)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	delta = minf(delta, 0.05)
	_t += delta
	# Target view is held, not toggled: while the key/button is down the view points at the nearest
	# aircraft, and letting go returns to the normal view.
	padlock = Input.is_action_pressed("padlock")
	# Letting go of target view snaps the camera straight back to forward-centre (free-look offset cleared).
	if _padlock_was and not padlock:
		_look_yaw = 0.0
		_look_pitch = 0.0
		_fwd = target.get_forward()
		_up = target.global_transform.basis.y
		_cock_ready = false
	_padlock_was = padlock
	var tf: Vector3 = target.get_forward()
	var tu: Vector3 = target.global_transform.basis.y
	_fwd = _nlerp(_fwd, tf, 1.0 - exp(-follow_rate * delta))
	_up = _nlerp(_up, tu, 1.0 - exp(-up_rate * delta))
	var up_v: Vector3 = Vector3.UP.lerp(_up, 0.55).normalized()

	var speed_ratio: float = clampf(target.speed / target.stats.max_speed, 0.0, 1.4)
	var want_fov: float = base_fov + speed_ratio * 14.0 + (8.0 if target.boosting else 0.0)
	_fov = lerpf(_fov, want_fov, 1.0 - exp(-4.0 * delta))
	# Numpad view distance / zoom: ease the live value toward its target so a press never snaps the camera.
	_dist_scale = lerpf(_dist_scale, _dist_scale_t, 1.0 - exp(-VIEW_SMOOTH_RATE * delta))
	_cockpit_fov = lerpf(_cockpit_fov, _cockpit_fov_t, 1.0 - exp(-VIEW_SMOOTH_RATE * delta))

	_shake = move_toward(_shake, 0.0, delta * 2.0)
	var sh: float = clampf(target.shake_intensity + _shake, 0.0, 1.5) * (0.25 if GameState.reduce_shake else 1.0)

	# Gamepad right-stick free look: integrates while held and holds its offset when released.
	var rx: float = _look_axis("look_left", "look_right")
	var ry: float = _look_axis("look_up", "look_down")
	_look_yaw = wrapf(_look_yaw - rx * LOOK_RATE * delta, -PI, PI)
	_look_pitch = clampf(_look_pitch - ry * LOOK_RATE * delta, -LOOK_MAX_PITCH, LOOK_MAX_PITCH)

	# Bouncing bomb: on release the chase camera follows the bomb from the side so the skips are visible.
	var sv: Dictionary = Weapons.skip_bomb_view()
	if int(sv["serial"]) != _bomb_serial:
		_bomb_serial = int(sv["serial"])
		if bool(sv["live"]):
			set_cockpit(false)
			bomb_cam_on = true
			_bomb_cam_linger = 2.5
	if bomb_cam_on:
		if bool(sv["live"]):
			_bomb_cam_linger = 2.5
			_bomb_cam_pos = sv["pos"]
			_bomb_cam_vel = sv["vel"]
		else:
			_bomb_cam_linger -= delta
			if _bomb_cam_linger <= 0.0:
				bomb_cam_on = false
				chase_cam.make_current()
		if bomb_cam_on:
			var hv: Vector3 = Vector3(_bomb_cam_vel.x, 0.0, _bomb_cam_vel.z)
			if hv.length() < 0.5:
				hv = Vector3(tf.x, 0.0, tf.z)
			hv = hv.normalized()
			var side: Vector3 = hv.cross(Vector3.UP).normalized()
			var cam_p: Vector3 = _bomb_cam_pos + side * 18.0 + Vector3.UP * 3.5 - hv * 6.0
			chase_cam.global_transform = Transform3D(Basis.looking_at(_bomb_cam_pos + Vector3.UP * 0.5 - cam_p, Vector3.UP), cam_p)
			chase_cam.fov = 60.0
			return
	var p: Vector3 = target.global_position
	if overhead:
		var up_dir: Vector3 = tf
		if up_dir.length() < 0.001:
			up_dir = Vector3.FORWARD
		chase_cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, up_dir), p + Vector3.UP * overhead_alt)
		chase_cam.fov = _fov
		return
	if not is_cockpit:
		var cam_dist: float = distance * _dist_scale
		var cam_up: float = height
		var pos: Vector3
		var cam_basis: Basis
		# Bombsight view: with the bombs weapon selected, pitch the chase camera
		# down at the predicted impact point so the terrain marker stays on screen.
		var bomb_view: bool = target.weapon_bombs and target.bombs > 0 and not target.on_ground and not target.bombsight_only
		var pt: Aircraft = _padlock_target() if padlock else null
		if pt != null:
			# Target view: sit behind the player and aim at the nearest aircraft so both stay framed.
			var tp: Vector3 = pt.global_position
			var flat: Vector3 = Vector3(tp.x - p.x, 0.0, tp.z - p.z)
			if flat.length_squared() < 0.01:
				flat = Vector3(_fwd.x, 0.0, _fwd.z)
			flat = flat.normalized()
			cam_dist = maxf(distance, 26.0) * _dist_scale
			pos = p - flat * cam_dist + up_v * (height + 3.0)
			pos.y = maxf(pos.y, _ground(pos) + 3.0)
			cam_basis = Basis.looking_at((tp - pos).normalized(), up_v)
		elif bomb_view:
			var vel: Vector3 = target.velocity
			if vel.length_squared() < 1.0:
				vel = tf * target.speed
			var imp: Vector3 = Weapons.predict_bomb_impact(p - target.global_transform.basis.y * 1.8, vel)
			var look_dir: Vector3 = (imp - p).normalized()
			var base_dist: float = p.distance_to(imp)
			# Zoom out in bombsight view so the airframe doesn't obscure the marker
			cam_dist = distance * 2.4 * _dist_scale
			cam_up = height * 2.0
			pos = p - _fwd * cam_dist + up_v * cam_up
			pos.y = maxf(pos.y, _ground(pos) + 3.0)
			var look_yaw: Vector3 = look_dir.rotated(Vector3.UP, _look_yaw)
			var right: Vector3 = look_yaw.cross(Vector3.UP).normalized()
			look_yaw = look_yaw.rotated(right, _look_pitch)
			cam_basis = Basis.looking_at((p + look_yaw * base_dist - pos).normalized(), up_v)
		else:
			# Orbit the camera around the aircraft with the right stick while always looking
			# back at it, so the aircraft stays centred and you can see all around it.
			var fwd_h: Vector3 = Vector3(_fwd.x, 0.0, _fwd.z)
			if fwd_h.length_squared() < 0.000001:
				fwd_h = Vector3.FORWARD
			fwd_h = fwd_h.normalized()
			var el: float = clampf(atan2(height, distance) + _look_pitch, ORBIT_MIN_EL, ORBIT_MAX_EL)
			var dir_h: Vector3 = (-fwd_h).rotated(Vector3.UP, _look_yaw)
			pos = p + dir_h * (cam_dist * cos(el)) + Vector3.UP * (cam_dist * sin(el))
			pos.y = maxf(pos.y, _ground(pos) + 3.0)
			cam_basis = Basis.looking_at((p - pos).normalized(), up_v)
		chase_cam.global_transform = Transform3D(cam_basis, pos)
		chase_cam.fov = _fov
		chase_cam.h_offset = sin(_t * 47.0) * clampf(_shake, 0.0, 1.5) * 0.25 * (0.25 if GameState.reduce_shake else 1.0)
		chase_cam.v_offset = cos(_t * 39.0) * clampf(_shake, 0.0, 1.5) * 0.25 * (0.25 if GameState.reduce_shake else 1.0)
	elif cockpit_cam:
		cockpit_cam.fov = clampf(_cockpit_fov + speed_ratio * 6.0, COCKPIT_FOV_MIN, COCKPIT_FOV_MAX)
		var look: Vector3 = Vector3(_look_pitch, _look_yaw, 0.0)
		var ptd: Aircraft = _padlock_target() if padlock else null
		if ptd != null:
			# aim the cockpit view at the target (look is relative to the airframe)
			var local: Vector3 = target.global_transform.basis.inverse() * (ptd.global_position - target.global_position)
			var hd: float = Vector2(local.x, local.z).length()
			look = Vector3(atan2(local.y, maxf(hd, 0.001)), atan2(-local.x, -local.z), 0.0)
		else:
			look = Vector3(_look_pitch, _look_yaw, 0.0)
		_steady_cockpit(delta, look)
		cockpit_cam.h_offset = sin(_t * 47.0) * clampf(_shake, 0.0, 1.5) * 0.05
		cockpit_cam.v_offset = cos(_t * 39.0) * clampf(_shake, 0.0, 1.5) * 0.05


## Cockpit view: the camera takes the airframe's attitude through a slow filter, so gust roll and pitch
## (turbulence) do not shake the view, while a turn still turns it within a fraction of a second.
## The free-look / padlock offset (look) is applied on top, unfiltered.
func _steady_cockpit(delta: float, look: Vector3) -> void:
	var ab: Basis = target.global_transform.basis.orthonormalized()
	if not _cock_ready:
		_cock_basis = ab
		_cock_ready = true
	_cock_basis = _cock_basis.slerp(ab, 1.0 - exp(-COCKPIT_STEADY_RATE * delta)).orthonormalized()
	var mount: Node3D = target.get_cockpit_mount()
	var origin: Vector3 = mount.global_position if mount else target.global_position
	var mount_basis: Basis = Basis.IDENTITY
	if mount:
		mount_basis = (target.global_transform.basis.inverse() * mount.global_transform.basis).orthonormalized()
	cockpit_cam.global_transform = Transform3D(_cock_basis * mount_basis * Basis.from_euler(look), origin)


## Normalised lerp: same as slerp for the small per-frame steps used here, but never trips Godot's
## "axis must be normalized" check (slerp of nearly parallel / opposite vectors did, every frame).
func _nlerp(a: Vector3, b: Vector3, t: float) -> Vector3:
	var v: Vector3 = a.lerp(b, t)
	if v.length_squared() < 1.0e-6:
		return b.normalized() if b.length_squared() > 1.0e-6 else a
	return v.normalized()


func _ground(pos: Vector3) -> float:
	if _terrain == null or not is_instance_valid(_terrain):
		_terrain = get_tree().get_first_node_in_group("terrain")
	if _terrain:
		return _terrain.call("get_height_at", pos)
	return 0.0


## Nearest ENEMY aircraft still flying, within padlock range (for the held target view), or null.
const PADLOCK_RANGE: float = 8000.0

func _padlock_target() -> Aircraft:
	if target == null or not is_instance_valid(target):
		return null
	var best: Aircraft = null
	var bd: float = PADLOCK_RANGE * PADLOCK_RANGE
	for n in get_tree().get_nodes_in_group("aircraft"):
		var a: Aircraft = n as Aircraft
		if a == null or a == target or not is_instance_valid(a) or a.state != Aircraft.State.ALIVE:
			continue
		if str(a.team) == GameState.player_side or str(a.team) == "Neutral":
			continue                       # only lock onto the enemy
		var d: float = a.global_position.distance_squared_to(target.global_position)
		if d < bd:
			bd = d
			best = a
	return best


## Right-stick axis value with deadzone (0 when centred).
func _look_axis(neg: String, pos: String) -> float:
	var v: float = Input.get_axis(neg, pos)
	if absf(v) < LOOK_DEAD:
		return 0.0
	return (v - signf(v) * LOOK_DEAD) / (1.0 - LOOK_DEAD)
