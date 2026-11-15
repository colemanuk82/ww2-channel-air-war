class_name TaxiController
extends Node
## Taxi to the runway (PROMPT-taxi-to-runway.md). Attached to a spawned aircraft with a world-space
## route from Airfield.taxi_route(). Two modes:
##  * the PLAYER flies the taxi themselves - the controller only guides: the compass chevron rides on
##    the next waypoint (hud.taxi_wp), the tower calls the taxi, and holding the assist key for 2 s
##    while stopped skips to the line-up point;
##  * AI (wingmen, or --taxi-test) is DRIVEN: pure-pursuit nose-wheel steering along the route, a
##    crawl through corners, then onto the runway behind the aircraft ahead (the hold-short opens as soon as
##    that aircraft has gone through its own) and into the line-up slot behind it.
## `lined_up` fires once the aircraft is on the centreline pointing down the runway.

signal lined_up

const TAXI_SPEED := 11.0         # m/s aim on the straights
const CATCH_SPEED := 15.0        # m/s on a long straight when the aircraft ahead has drawn away
const TURN_SPEED := 4.0          # m/s through a corner
const WP_RANGE := 14.0           # waypoint reached
const HOLD_RANGE := 9.0          # stop short of the hold-short point
const SKIP_HOLD := 2.0           # seconds the assist key must be held to skip
const LOOK := 10.0               # m: pure-pursuit look-ahead along the route

var route: PackedVector3Array = PackedVector3Array()
var wp_i: int = 1
var active: bool = false
var ai: bool = false             # true: drive the aircraft; false: guide the player
var holding: bool = false        # standing at hold-short, waiting to be cleared
var cleared: bool = false        # the hold is released (the runway is free)
var auto_clear: bool = false     # nobody ahead (the player): the tower clears the hold as the aircraft reaches it
var line_yaw: float = 0.0        # world heading of the line-up (the runway heading)
var ahead_ac: Aircraft = null    # the aircraft taxiing ahead (the player leads, wingmen trail)
var ahead_ctrl: TaxiController = null   # its controller (where it is along its own route)
var start_after: int = -1        # stay parked until ahead_ctrl has passed this index of ITS route (where ours joins it)
var waiting: bool = false        # parked on the spot, waiting for the aircraft ahead to go past
var queued: bool = false         # stopped behind the aircraft ahead
var hold_i: int = -1             # the route index of the hold-short point (the 4th from the end)
var _plane: Aircraft = null
var _hud: Node = null
var _skip_t: float = 0.0
var _log_t: float = 0.0
var _started: bool = false
var _sp_dbg: float = 0.0
var _was_player: bool = false     # an AI-driven PLAYER gets the controls back when the taxi ends
var _had_ahead_ctrl: bool = false # follow() gave us a controller to trail: its progress opens our hold


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
	_started = false
	active = plane != null and is_instance_valid(plane) and route.size() >= 3
	hold_i = route.size() - 4 if active and route.size() >= 4 else -1
	# the route tail is [... hold-short, runway entry, centreline, line-up] (Airfield.taxi_route)
	if active and ai and plane.player_controlled:
		plane.player_controlled = false   # the aircraft's own input path would override the AI drive
		_was_player = true
	if not active and _hud != null and _hud.has_method("show_message"):
		_hud.call("show_message", "Taxi: no route - line up by hand", 3.0)


## Trail `ac` (driven by `ctrl`): stay parked until it has gone past the point where our route joins its route.
func follow(ac: Aircraft, ctrl: TaxiController) -> void:
	ahead_ac = ac
	ahead_ctrl = ctrl
	_had_ahead_ctrl = ctrl != null
	start_after = merge_index(route, ctrl.route) if ctrl != null else -1


## The index in `ahead_route` of the first point of `p_route` (after its park spot) that the two routes share: our
## aircraft joins the other's path there. The routes are built on the same taxi graph, so shared nodes coincide.
static func merge_index(p_route: PackedVector3Array, ahead_route: PackedVector3Array) -> int:
	for j in range(1, p_route.size()):
		for m in range(1, ahead_route.size()):
			if Vector2(p_route[j].x - ahead_route[m].x, p_route[j].z - ahead_route[m].z).length() < 1.0:
				return m
	return maxi(ahead_route.size() - 4, 1)


func waypoint() -> Vector3:
	if route.is_empty():
		return Vector3.ZERO
	return route[mini(wp_i, route.size() - 1)]


## On the runway centreline, past the hold and pointing down the runway (within `max_err` degrees), moving slowly.
func on_runway(max_err: float) -> bool:
	if not active or _plane == null or not is_instance_valid(_plane) or hold_i < 0 or wp_i < route.size() - 1:
		return false
	return _plane.speed < 8.0 and absf(wrapf(_plane.get_heading_deg() - line_yaw, -180.0, 180.0)) < max_err


## End the taxi where the aircraft stands (the leader has started his take-off roll: go from here).
func finish_here() -> void:
	if active:
		_finish(false)


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
	# the flight follows its leader onto the runway: our hold opens as soon as the aircraft ahead has gone through
	# its own hold (or its taxi is over), not when it has finished lining up
	if ai and not cleared and _had_ahead_ctrl:
		if not is_instance_valid(ahead_ctrl) or not ahead_ctrl.active or (ahead_ctrl.hold_i >= 0 and ahead_ctrl.wp_i > ahead_ctrl.hold_i):
			cleared = true
	# the route never advances past the hold-short until it is cleared (the aircraft ahead is on the runway)
	var adv_limit: int = route.size() - 1
	if hold_i >= 0 and not cleared:
		adv_limit = mini(adv_limit, hold_i)
	while wp_i < adv_limit and (_xz_dist(pp, route[wp_i]) < WP_RANGE or _seg_t(pp, wp_i) >= 1.0):
		wp_i += 1
	var at_end: bool = wp_i >= route.size() - 1
	var tgt: Vector3 = route[wp_i]
	var d: float = _xz_dist(pp, tgt)
	# the tower clears an aircraft with nobody ahead of it as it reaches the hold
	if auto_clear and not cleared and hold_i >= 0 and wp_i == hold_i and d < 30.0:
		cleared = true
		Radio.say("Tower", "Cleared to line up runway %03d." % int(wrapf(line_yaw, 0.0, 360.0)), Radio.Kind.CONTROL, 0.3)
	# hold-short discipline: stand at the hold point until cleared (the aircraft ahead is on the runway)
	holding = hold_i >= 0 and wp_i == hold_i and d < HOLD_RANGE and not cleared
	if ai:
		_drive(d, at_end)
	else:
		_guide(delta, d, at_end)
	if _log_t > 0.0:
		_log_t -= delta
		if _log_t <= 0.0:
			_log_t = 2.0
			print("TAXI %s leg=%d/%d spd=%.1f want=%.1f thr=%.2f d=%.0f hold=%s clr=%s wait=%s q=%s ahead=%.0f" % [_plane.name, wp_i, route.size() - 1, _plane.speed, _sp_dbg, _plane.throttle_target, d, holding, cleared, waiting, queued, _plane.global_position.distance_to(ahead_ac.global_position) if ahead_ac != null and is_instance_valid(ahead_ac) else -1.0])


static func _xz_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## How far along leg i (route[i-1] -> route[i]) the point p projects: 0 at its start, 1 at its end.
func _seg_t(p: Vector3, i: int) -> float:
	var a: Vector3 = route[i - 1]
	var ab := Vector2(route[i].x - a.x, route[i].z - a.z)
	var l2: float = ab.length_squared()
	if l2 < 0.01:
		return 1.0
	return Vector2(p.x - a.x, p.z - a.z).dot(ab) / l2


## Pure-pursuit carrot: LOOK m ahead of our projection on the current leg, spilling onto the next leg round a corner;
## on the last leg it runs on past the line-up point, so the aircraft stops squarely on the centreline.
func _carrot(p: Vector3, limit: int) -> Vector3:
	var a: Vector3 = route[wp_i - 1]
	var b: Vector3 = route[wp_i]
	var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var ln: float = ab.length()
	if ln < 0.5:
		return b
	var dir: Vector3 = ab / ln
	var s: float = clampf(Vector3(p.x - a.x, 0.0, p.z - a.z).dot(dir), 0.0, ln) + LOOK
	if s <= ln or wp_i >= route.size() - 1:
		return a + dir * s
	if wp_i >= limit:
		return b
	var c: Vector3 = route[wp_i + 1]
	var bc := Vector3(c.x - b.x, 0.0, c.z - b.z)
	if bc.length() < 0.5:
		return b
	return b + bc.normalized() * minf(s - ln, bc.length())


## How far along our route (from `p`, looking `look` m ahead) the aircraft at `q` stands in our way: the path
## distance to the route point nearest it, or -1 if it is more than `clear` m to the side of the path (or further on).
func _path_block(p: Vector3, q: Vector3, look: float, clear: float) -> float:
	var q2 := Vector2(q.x, q.z)
	var prev := Vector2(p.x, p.z)
	var run: float = 0.0
	var best: float = -1.0
	var best_lat: float = clear
	if prev.distance_to(q2) < clear:
		return 0.0
	for i in range(wp_i, route.size()):
		var nxt := Vector2(route[i].x, route[i].z)
		var seg: float = prev.distance_to(nxt)
		if seg > 0.01:
			var c: Vector2 = Geometry2D.get_closest_point_to_segment(q2, prev, nxt)
			var lat: float = c.distance_to(q2)
			if lat < best_lat:
				best_lat = lat
				best = run + prev.distance_to(c)
		run += seg
		prev = nxt
		if run > look:
			break
	return best if best >= 0.0 and best <= look else -1.0


## Player mode: guidance only - the chevron on the compass, the skip, and the done transitions.
func _guide(delta: float, d: float, at_end: bool) -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.set("taxi_wp", waypoint())
	# rolling for take-off (or airborne) without stopping in the line-up slot still ends the taxi: the wingmen
	# waiting for him to line up are released
	if _plane.speed > 25.0 or (not _plane.on_ground and _plane.altitude_agl > 8.0):
		_finish(false)
		return
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
func _drive(d: float, at_end: bool) -> void:
	var pp: Vector3 = _plane.global_position
	# parked until the aircraft ahead has gone past the point where we join its route
	if not _started:
		var go: bool = ahead_ctrl == null or not is_instance_valid(ahead_ctrl) or not ahead_ctrl.active or start_after < 0
		if not go and ahead_ctrl.wp_i > start_after:
			var mp: Vector3 = ahead_ctrl.route[start_after]
			go = ahead_ac == null or not is_instance_valid(ahead_ac) or _xz_dist(ahead_ac.global_position, mp) > 14.0
		if ahead_ac != null and is_instance_valid(ahead_ac) and (ahead_ac.state != Aircraft.State.ALIVE or not ahead_ac.on_ground):
			go = true
		_started = go
		waiting = not go
		if waiting:
			_plane.cmd_yaw = 0.0
			_plane.throttle_target = 0.0
			_plane.brake_on = true
			return
	var limit: int = route.size() - 1
	if hold_i >= 0 and not cleared:
		limit = mini(limit, hold_i)
	var tgt: Vector3 = _carrot(pp, limit)
	var to_t := tgt - pp
	to_t.y = 0.0
	# compass heading convention (north = -Z), matching Aircraft.get_heading_deg
	var want: float = rad_to_deg(atan2(to_t.x, -to_t.z))
	var err: float = wrapf(want - _plane.get_heading_deg(), -180.0, 180.0)
	_plane.cmd_yaw = clampf(err * 0.06, -0.45, 0.45)
	var sp_target: float = TAXI_SPEED
	if absf(err) > 30.0:
		sp_target = TURN_SPEED
	# slow for the corner coming up
	if wp_i < limit and d < 25.0:
		var a: Vector3 = route[wp_i] - route[wp_i - 1]
		var b: Vector3 = route[wp_i + 1] - route[wp_i]
		if absf(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z))) > deg_to_rad(50.0):
			sp_target = minf(sp_target, lerpf(TURN_SPEED, TAXI_SPEED, clampf((d - 8.0) / 17.0, 0.0, 1.0)))
	queued = false
	if ahead_ac != null and is_instance_valid(ahead_ac) and ahead_ac.state == Aircraft.State.ALIVE and ahead_ac.on_ground:
		# the aircraft ahead has drawn away: close up on a long straight
		if sp_target >= TAXI_SPEED and absf(err) < 12.0 and d > 60.0 and _xz_dist(pp, ahead_ac.global_position) > 75.0:
			sp_target = CATCH_SPEED
		# keep a gap to the aircraft ahead - but only where it actually stands on the path we are about to taxi (a
		# lined-up aircraft beside a taxiway that crosses behind it is no reason to stop)
		var gap: float = maxf(_plane.stats.radius + ahead_ac.stats.radius, 12.0) * 2.6
		var stop_d: float = gap * 0.7
		if hold_i >= 0 and wp_i > hold_i:
			# on the runway the line-up slots are runway_slot_gap apart: close up to them
			stop_d = _plane.stats.radius + ahead_ac.stats.radius + 6.0
			gap = stop_d + 15.0
		var da: float = _path_block(pp, ahead_ac.global_position, gap + 10.0, (_plane.stats.radius + ahead_ac.stats.radius) * 0.9 + 2.0)
		if da >= 0.0:
			if da < stop_d:
				sp_target = 0.0
				queued = true
			elif da < gap:
				sp_target = minf(sp_target, maxf(ahead_ac.speed, lerpf(0.0, TAXI_SPEED, (da - stop_d) / (gap - stop_d))))
				queued = sp_target < 0.5
	if at_end:
		# creep into the line-up slot and stop in it
		sp_target = minf(sp_target, lerpf(0.0, 5.0, clampf((d - 6.0) / 20.0, 0.0, 1.0)))
	if hold_i >= 0 and wp_i == hold_i and not cleared and d < 40.0:
		# ease down to the hold while it is still closed
		sp_target = minf(sp_target, lerpf(3.0, TAXI_SPEED, clampf((d - HOLD_RANGE) / 31.0, 0.0, 1.0)))
		if d < HOLD_RANGE:
			sp_target = minf(sp_target, lerpf(0.0, 3.0, clampf((d - 3.0) / 6.0, 0.0, 1.0)))
	var stopped: bool = (holding and d < HOLD_RANGE * 0.6) or (at_end and d < 7.0)
	if stopped:
		sp_target = 0.0
	_sp_dbg = sp_target
	if sp_target > 0.05:
		_plane.throttle_target = clampf(0.1 + (sp_target - _plane.speed) * 0.08, 0.0, 0.55)
		_plane.brake_on = _plane.speed > sp_target + 2.0
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
