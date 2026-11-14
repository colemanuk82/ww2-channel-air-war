class_name TaxiController
extends Node
## Taxi to the runway (PROMPT-taxi-to-runway.md). Attached to a spawned aircraft with a world-space
## route from Airfield.taxi_route(). Two modes:
##  * the PLAYER flies the taxi themselves - the controller only guides: the compass chevron rides on
##    the next waypoint (hud.taxi_wp), the tower calls the taxi, and holding the assist key for 2 s
##    while stopped skips to the line-up point;
##  * AI (wingmen, or --taxi-test) is DRIVEN: pure-pursuit nose-wheel steering along the route, a
##    crawl through corners, a full stop at hold-short until cleared, then line up.
## `lined_up` fires once the aircraft is on the centreline pointing down the runway.

signal lined_up

const TAXI_SPEED := 9.0          # m/s aim on the straights (a gentle wartime taxi)
const TURN_SPEED := 4.0          # m/s through a corner
const WP_RANGE := 14.0           # waypoint reached
const HOLD_RANGE := 9.0          # stop short of the hold-short point
const SKIP_HOLD := 2.0           # seconds the assist key must be held to skip

var route: PackedVector3Array = PackedVector3Array()
var wp_i: int = 1
var active: bool = false
var ai: bool = false             # true: drive the aircraft; false: guide the player
var holding: bool = false        # standing at hold-short, waiting to be cleared
var cleared: bool = false        # the hold is released (the runway is free)
var line_yaw: float = 0.0        # world heading of the line-up (the runway heading)
var ahead_ac: Aircraft = null    # the aircraft taxiing ahead (the player leads, wingmen trail)
var hold_i: int = -1             # the route index of the hold-short point (the 4th from the end)
var _plane: Aircraft = null
var _hud: Node = null
var _skip_t: float = 0.0
var _log_t: float = 0.0
var _was_player: bool = false     # an AI-driven PLAYER gets the controls back when the taxi ends


func setup(plane: Aircraft, p_route: PackedVector3Array, p_line_yaw: float, p_hud: Node, p_ai: bool) -> void:
	_plane = plane
	route = p_route
	line_yaw = p_line_yaw
	_hud = p_hud
	ai = p_ai
	wp_i = 1
	holding = false
	cleared = false
	_skip_t = 0.0
	active = plane != null and is_instance_valid(plane) and route.size() >= 3
	hold_i = route.size() - 4 if active and route.size() >= 4 else -1
	# the route tail is [... hold-short, runway entry, centreline, line-up] (Airfield.taxi_route)
	if active and ai and plane.player_controlled:
		plane.player_controlled = false   # the aircraft's own input path would override the AI drive
		_was_player = true
	if not active and _hud != null and _hud.has_method("show_message"):
		_hud.call("show_message", "Taxi: no route - line up by hand", 3.0)


func waypoint() -> Vector3:
	if route.is_empty():
		return Vector3.ZERO
	return route[mini(wp_i, route.size() - 1)]


func stop() -> void:
	active = false
	if _hud != null and is_instance_valid(_hud):
		_hud.set("taxi_wp", Vector3.INF)


func tick(delta: float) -> void:
	if not active or _plane == null or not is_instance_valid(_plane) or _plane.state != Aircraft.State.ALIVE:
		return
	if _plane.process_mode == Node.PROCESS_MODE_DISABLED:
		return     # the loading screen holds the aircraft disabled: the taxi starts when it is released
	var pp: Vector3 = _plane.global_position
	# the route never advances past the hold-short until it is cleared (the aircraft ahead is on the runway)
	var adv_limit: int = route.size() - 1
	if hold_i >= 0 and not cleared:
		adv_limit = mini(adv_limit, hold_i)
	while wp_i < adv_limit and Vector2(pp.x, pp.z).distance_to(Vector2(route[wp_i].x, route[wp_i].z)) < WP_RANGE:
		wp_i += 1
	var at_end: bool = wp_i >= route.size() - 1
	var tgt: Vector3 = route[wp_i]
	var d: float = Vector2(pp.x, pp.z).distance_to(Vector2(tgt.x, tgt.z))
	# hold-short discipline: stand at the hold point until cleared (the aircraft ahead is on the runway)
	holding = hold_i >= 0 and wp_i == hold_i and d < HOLD_RANGE and not cleared
	if ai:
		_drive(tgt, d, at_end)
	else:
		_guide(delta, d, at_end)
	if _log_t > 0.0:
		_log_t -= delta
		if _log_t <= 0.0:
			_log_t = 2.0
			print("TAXI leg=%d/%d spd=%.1f thr=%.2f d=%.0f hold=%s" % [wp_i, route.size() - 1, _plane.speed, _plane.throttle_target, d, holding])


## Player mode: guidance only - the chevron on the compass, the skip, and the done transitions.
func _guide(delta: float, d: float, at_end: bool) -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.set("taxi_wp", waypoint())
	# skip: hold the assist key while stopped to be moved to the line-up point (the toggle itself is
	# suppressed while GameState.taxi_active, so holding R does not switch the flight assist off)
	if _plane.on_ground and _plane.speed < 2.0 and Input.is_action_pressed("assist_toggle"):
		_skip_t += delta
		if _skip_t >= SKIP_HOLD:
			_finish(true)
			return
	else:
		_skip_t = 0.0
	if at_end and d < 12.0:
		_finish(false)


## AI mode: drive - pure pursuit on the route, crawl through corners, stop at the hold, and keep a
## respectful gap to the aircraft ahead: if it stops (the player taking his time), we stop and wait.
func _drive(tgt: Vector3, d: float, at_end: bool) -> void:
	var to_t := tgt - _plane.global_position
	to_t.y = 0.0
	# compass heading convention (north = -Z), matching Aircraft.get_heading_deg
	var want: float = rad_to_deg(atan2(to_t.x, -to_t.z))
	var err: float = wrapf(want - _plane.get_heading_deg(), -180.0, 180.0)
	_plane.cmd_yaw = clampf(err * 0.06, -0.45, 0.45)
	var sp_target: float = TAXI_SPEED
	if absf(err) > 30.0:
		sp_target = TURN_SPEED
	if ahead_ac != null and is_instance_valid(ahead_ac) and ahead_ac.state == Aircraft.State.ALIVE:
		var da: float = _plane.global_position.distance_to(ahead_ac.global_position)
		var gap: float = maxf(_plane.stats.radius + ahead_ac.stats.radius, 12.0) * 2.2
		if da < gap * 0.62:
			sp_target = 0.0                              # too close: stop and wait for it to move off
		elif da < gap:
			sp_target = minf(sp_target, ahead_ac.speed)  # match its speed, never overtake
	if at_end:
		# creep into the line-up slot and stop in it: without this the pursuit circles the point
		sp_target = minf(sp_target, lerpf(0.0, 5.0, clampf((d - 6.0) / 20.0, 0.0, 1.0)))
	var stopped: bool = (holding and d < HOLD_RANGE * 0.6) or (at_end and d < 7.0)
	if stopped:
		sp_target = 0.0
	if sp_target > 0.0:
		_plane.throttle_target = clampf(0.1 + (sp_target - _plane.speed) * 0.06, 0.0, 0.4)
		_plane.brake_on = false
	else:
		_plane.throttle_target = 0.0
		_plane.brake_on = _plane.speed > 0.5
	if at_end and d < 9.0 and _plane.speed < 1.5:
		_finish(false)


## Done: clear the HUD, stop driving; a skipped taxi is moved to the line-up point directly.
func _finish(teleport: bool) -> void:
	var end: Vector3 = route[route.size() - 1]
	active = false
	if _hud != null and is_instance_valid(_hud):
		_hud.set("taxi_wp", Vector3.INF)
	if _plane != null and is_instance_valid(_plane):
		_plane.cmd_yaw = 0.0
		_plane.throttle_target = 0.0
		_plane.brake_on = false
		if teleport:
			var wp: Vector3 = Vector3(end.x, _plane.global_position.y, end.z)
			_plane.reset_pose(wp, line_yaw, false)
		if _was_player:
			_plane.player_controlled = true     # the AI-driven player flies again
	lined_up.emit()
