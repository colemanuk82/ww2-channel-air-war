class_name Searchlight
extends GroundTarget
## Searchlight: sweeps the sky at night (TimeOfDay), locks onto enemy aircraft that cross the beam, and marks
## them as "lit" (meta lit_until) so AA guns can see/hit them in the dark. Inactive (beam hidden) by day.

const BEAM_LEN: float = 4000.0
const BEAM_MAX: float = 12000.0
const LOCK_CLOSE: float = 2600.0     # enemy aircraft closer than this are picked up even off the beam
# Catch: a locked player aircraft held inside the beam for CATCH_HOLD seconds is "caught" and flak comes up at it.
# The beam slews at a limited rate while it holds the player, so a fast crossing or a sharp break at close range
# takes him out of the beam (off by more than BREAK_CONE for BREAK_T seconds). Tuning values, to be tested in play.
const CATCH_CONE: float = 0.105      # ~6 deg: inside this, the hold timer runs
const CATCH_HOLD: float = 3.0        # seconds held in the beam before the catch
const BREAK_CONE: float = 0.14       # ~8 deg: beyond this the player is trying to break out
const BREAK_T: float = 0.5           # seconds beyond BREAK_CONE that lose the lock
const CATCH_SLEW: float = 0.12       # rad/s the beam can turn to follow the player
const CATCH_FLAK_T: float = 1.3      # seconds between flak bursts at a caught aircraft
const ESCAPE_COOL: float = 10.0      # after breaking out, the light cannot re-catch him for this long

var active: bool = false
var _pending: bool = false   # a switch is waiting for this light's own moment
var _gap: float = 0.0
var _pivot: Node3D
var _beam: MeshInstance3D
var _light: SpotLight3D
var _sweep_yaw: float = 0.0
var _sweep_pitch: float = 0.0
var _sweep_speed: float = 0.25
var _sweep_phase: float = 0.0
var _locked: Node3D
var _check_t: float = 0.0
var _scan_t: float = 0.0
var _beam_len: float = BEAM_LEN
var _dir: Vector3 = Vector3.UP
var _caught: bool = false        # the locked player is in the catch: flak is coming up at him
var _hold_t: float = 0.0         # seconds the player has been held inside CATCH_CONE
var _out_t: float = 0.0          # seconds the player has been outside BREAK_CONE
var _flak_t: float = 0.0         # countdown to the next flak burst at a caught player
var _escape_cool: float = 0.0    # while above zero, the player cannot be picked up again


static func create(p_team: String) -> Searchlight:
	var s := Searchlight.new()
	s.team = p_team
	s.max_health = 35.0
	s.hit_radius = 5.0
	s.points = 90
	s.kind = "searchlight"
	s.display_name = "Searchlight"
	s.explosion_size = 0.7
	s.smoke_scale = 0.6
	s._sweep_phase = randf() * TAU
	s._sweep_speed = randf_range(0.18, 0.32) * (1.0 if randf() > 0.5 else -1.0)
	s._sweep_yaw = randf() * TAU
	s._check_t = randf()
	return s


func _post_ready() -> void:
	add_to_group("searchlight")
	_apply_active(GroundKit.is_night())


func _build_intact(root: Node3D) -> void:
	var c: Color = GroundKit.team_color(team)
	# round concrete emplacement ringed with sandbags (a bare square slab read as a stray block on the ground)
	GroundKit.cyl(root, 2.4, 2.7, 0.5, Vector3(0, 0.25, 0), c.darkened(0.2), Vector3.ZERO, 14)
	for i in 10:
		var sa: float = TAU * float(i) / 10.0
		GroundKit.box(root, Vector3(0.75, 0.42, 0.46), Vector3(sin(sa) * 2.35, 0.45, cos(sa) * 2.35), c.darkened(0.05), Vector3(0, rad_to_deg(sa), 0))
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 2.4, 0)
	root.add_child(_pivot)
	var housing := GroundKit.cyl(_pivot, 1.5, 1.5, 2.2, Vector3(0, 0, -0.4), c.darkened(0.1), Vector3(90, 0, 0), 10)
	housing.name = "Housing"
	GroundKit.cyl(_pivot, 1.25, 1.25, 0.1, Vector3(0, 0, -1.55), Color(1.0, 0.95, 0.7), Vector3(90, 0, 0), 10, false)
	# beam: a camera-facing soft light shaft (a quad), oriented along the beam each frame. The old cylinder
	# cone showed its polygon facets as square patches marching up the beam.
	_beam = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	_beam.mesh = qm
	var bm := ShaderMaterial.new()
	bm.shader = load("res://shaders/beam.gdshader") as Shader
	_beam.material_override = bm
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.extra_cull_margin = 2000.0
	_beam.top_level = true                     # placed in world space each frame, aligned to the beam
	_beam.visible = false
	add_child(_beam)
	_light = SpotLight3D.new()
	_light.spot_range = BEAM_LEN
	_light.spot_angle = 6.0
	_light.light_energy = 0.0        # the shaft is drawn as a mesh: it must not light the ground/fog around it
	_light.light_color = Color(0.85, 0.92, 1.0)
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0, -1.6)
	_light.visible = false
	_pivot.add_child(_light)
	_apply_dir(Vector3.UP)


## Stretch the beam (and its spotlight) to a given length so it always reaches the target
## instead of being cut off at a fixed altitude.
func _set_beam_length(l: float) -> void:
	l = clampf(l, 200.0, BEAM_MAX)
	_beam_len = l
	if _light:
		_light.spot_range = l


## Place and aim the beam quad: along the beam axis, turned to face the camera, widening with range.
func _update_beam() -> void:
	if _beam == null or _model_ready_check():
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	var start: Vector3 = _pivot.global_position
	var yax: Vector3 = _dir
	var eye: Vector3 = (cam.global_position - start) if cam != null else Vector3.UP
	var xax: Vector3 = eye.cross(yax)
	if xax.length() < 0.0001:
		xax = Vector3.RIGHT
	xax = xax.normalized()
	var zax: Vector3 = xax.cross(yax).normalized()
	var w: float = 4.0 + _beam_len * 0.004
	_beam.global_transform = Transform3D(Basis(xax * w, yax * _beam_len, zax), start + yax * _beam_len * 0.5)


func _model_ready_check() -> bool:
	return _beam == null or _pivot == null or not _pivot.is_inside_tree()


func _build_wreck(root: Node3D) -> void:
	GroundKit.box(root, Vector3(3.6, 1.0, 3.6), Vector3(0, 0.5, 0), wreck_color, Vector3(0, 10, 5))
	GroundKit.cyl(root, 1.4, 1.4, 2.0, Vector3(1.5, 0.8, 1.0), wreck_color, Vector3(10, 0, 70), 8)


func _apply_active(on: bool) -> void:
	active = on
	if not on:
		_caught = false
		_hold_t = 0.0
		_out_t = 0.0
	if _beam:
		_beam.visible = on and not is_dead
	if _light:
		_light.visible = on and not is_dead


func _apply_dir(d: Vector3) -> void:
	_dir = d.normalized()
	if _pivot and _pivot.is_inside_tree():
		var up: Vector3 = Vector3.UP if absf(_dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		_pivot.global_transform.basis = Basis.looking_at(_dir, up)
	elif _pivot:
		_pivot.rotation = Vector3(deg_to_rad(80.0), 0, 0)


func _process(delta: float) -> void:
	if is_dead:
		return
	delta = minf(delta, 0.1)
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 1.5
		var night: bool = GroundKit.is_night()
		var pl: Node3D = GroundKit.player_node()
		var near: bool = pl == null or pl.global_position.distance_to(global_position) < 9000.0
		var want: bool = night and near and SkyWar.lights_up()
		if want != active:
			# this light switches at its own moment, not with the rest of the group
			if not _pending:
				_pending = true
				_gap = randf_range(0.0, 45.0)
			_gap -= 1.5
			if _gap <= 0.0:
				_pending = false
				_apply_active(want)
		else:
			_pending = false
	if not active:
		return
	_escape_cool = maxf(_escape_cool - delta, 0.0)
	var now: float = Time.get_ticks_msec() / 1000.0
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.2
		_scan_for_lock()
	var want_dir: Vector3
	if _locked != null and GroundKit.aircraft_alive(_locked) and _locked.global_position.distance_to(global_position) < BEAM_MAX:
		var tgt: Vector3 = _locked.global_position
		want_dir = (tgt - _pivot.global_position).normalized()
		_set_beam_length(_pivot.global_position.distance_to(tgt) + 120.0)
		_locked.set_meta("lit_until", now + 1.2)
		if _is_player(_locked):
			_player_track(delta, want_dir)
		else:
			_dir = _dir.lerp(want_dir, clampf(delta * 3.5, 0.0, 1.0)).normalized()
	else:
		_locked = null
		_set_beam_length(BEAM_LEN)
		_sweep_phase += delta
		_sweep_yaw += _sweep_speed * delta
		_sweep_pitch = deg_to_rad(62.0) + sin(_sweep_phase * 0.35) * deg_to_rad(18.0)
		want_dir = Vector3(sin(_sweep_yaw) * cos(_sweep_pitch), sin(_sweep_pitch), -cos(_sweep_yaw) * cos(_sweep_pitch))
		_dir = _dir.lerp(want_dir, clampf(delta * 2.0, 0.0, 1.0)).normalized()
	_apply_dir(_dir)
	_update_beam()


func _scan_for_lock() -> void:
	if _locked != null:
		return
	# Prefer an aircraft flying through the beam; failing that, grab an enemy that has come in close over the
	# battery. A held aircraft is marked "lit" so the AA layers can follow it (much better flak accuracy).
	var closest: Node3D = null
	# moonlight: a bright moon lets a light pick a bomber up from further off and across a wider cone
	var moon: float = MoonWeather.moon_light()
	var cone: float = deg_to_rad(9.0) * lerpf(0.8, 1.2, moon)
	var closest_d: float = LOCK_CLOSE * lerpf(0.7, 1.2, moon)
	for a in GroundKit.enemy_aircraft(team, global_position, BEAM_MAX):
		var n3: Node3D = a as Node3D
		var to: Vector3 = (n3.global_position - _pivot.global_position)
		var dist: float = to.length()
		if dist < 60.0:
			continue
		if _escape_cool > 0.0 and _is_player(n3):
			continue          # he has just broken out of this beam
		if _dir.angle_to(to.normalized()) < cone:
			_locked = n3
			return
		if dist < closest_d:
			closest_d = dist
			closest = n3
	_locked = closest


func _is_player(n: Node) -> bool:
	return "player_controlled" in n and bool(n.get("player_controlled"))


## Beam motion while it holds the player: a slew-limited tracker plus the catch timers. A player who stays
## out past BREAK_CONE for BREAK_T seconds is lost; one held inside CATCH_CONE for CATCH_HOLD seconds is caught.
func _player_track(delta: float, want_dir: Vector3) -> void:
	var off: float = _dir.angle_to(want_dir)
	if off > BREAK_CONE:
		_out_t += delta
		if _out_t >= BREAK_T:
			_lose_player()
			return
	else:
		_out_t = maxf(_out_t - delta, 0.0)
	if off > CATCH_CONE:
		_hold_t = 0.0
	elif not _caught and _escape_cool <= 0.0:
		_hold_t += delta
		if _hold_t >= CATCH_HOLD:
			_caught = true
			_flak_t = 0.5
			_say("Caught in the searchlight - break out of the beam!")
	if _caught:
		_flak_t -= delta
		if _flak_t <= 0.0:
			_flak_t = CATCH_FLAK_T
			_fire_at(_locked)
	if off > 0.0001:
		_dir = _dir.slerp(want_dir, clampf(CATCH_SLEW * delta / off, 0.0, 1.0)).normalized()


func _lose_player() -> void:
	var was_caught: bool = _caught
	_locked = null
	_caught = false
	_hold_t = 0.0
	_out_t = 0.0
	_escape_cool = ESCAPE_COOL
	if was_caught:
		_say("Broke out of the searchlight")


## One flak burst at a caught aircraft: 88mm fused shell, aimed at its predicted position with some error.
func _fire_at(t: Node3D) -> void:
	var shells: AAShells = AAShells.get_instance()
	if shells == null or t == null or not is_instance_valid(t):
		return
	var from: Vector3 = _pivot.global_position
	var tv: Vector3 = Vector3.ZERO
	if "velocity" in t:
		tv = t.get("velocity")
	var spd: float = 650.0
	var aim: Vector3 = t.global_position
	for i in 2:
		aim = t.global_position + tv * (from.distance_to(aim) / spd)
	var dir: Vector3 = (aim - from).normalized()
	var axis: Vector3 = dir.cross(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))).normalized()
	if axis.length() < 0.1:
		axis = Vector3.UP
	dir = dir.rotated(axis, 0.03 * sqrt(randf()))
	shells.fire_flak(from, dir * spd, from.distance_to(aim) / spd, 3.4, 19.0, team)
	if _is_player(t):
		t.set("_impact_shake", 0.3)     # the flak bursts shake the aircraft a little each time


func _say(text: String) -> void:
	var tree: SceneTree = GroundKit.tree()
	if tree == null:
		return
	var h: Node = tree.get_first_node_in_group("hud")
	if h != null and h.has_method("show_message"):
		h.call("show_message", text, 3.0)


func _on_destroyed(_killer: Node) -> void:
	_apply_active(false)
	_locked = null
