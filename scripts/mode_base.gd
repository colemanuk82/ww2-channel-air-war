class_name ModeBase
extends Node
## Base class for game modes (dogfight, bombing, ground attack, historical missions, free flight).
## A mode is added as a child of the world root by main.gd. Modes never edit each other's files.
##
## DAMAGE CONTRACT (shared by weapons, AI, ground units, aircraft):
##   Anything that can be hit joins group "damageable" and exposes:
##     var team: String            # "Allies" or "Axis" (or "Neutral")
##     var hit_radius: float       # world units (1 unit = 10 m); used for sphere hit tests
##     func take_damage(amount: float, source: Node) -> void
##   Optional: signal destroyed(node, killer)   (Aircraft already has this)
##   Objects that count as mission targets also join group "mission_target".

signal mission_complete(success: bool, stats: Dictionary)
signal objective_updated(text: String)
signal score_changed(score: int)

var world: Node3D
var player: Node3D   # the player's Aircraft
var hud: Node        # HUD
var score: int = 0
var elapsed: float = 0.0
var running: bool = false


var radio_quiet: bool = false   # set by HistoricalMissions: its own scripted dialogue replaces the generic calls

## Everything the player destroys, in every mode (Weapons.player_kill): shown in the kill count and written to the
## pilot's logbook along with time in the air and the mission result.
var player_kills: Dictionary = {"air": 0, "ground": 0, "ships": 0, "v1": 0}
var _air_log_t: float = 0.0
const KILL_POINTS := {"air": 50, "ground": 10, "ships": 40, "v1": 150}


## Generic voiced mode call: assets/voice/mode/<allies|axis>/<key> (see tools/make_voice_story.py).
func radio_call(key: String, delay: float = 0.0) -> void:
	if radio_quiet:
		return
	var side: String = "axis" if GameState.player_side == "Axis" else "allies"
	Radio.story("mode/%s/%s" % [side, key], delay)


## One of the numbered variants key_1 .. key_n.
func radio_call_any(key: String, n: int, delay: float = 0.0) -> void:
	radio_call("%s_%d" % [key, randi_range(1, n)], delay)


## Wingmen: friendly fighters that join the player once airborne and follow / fight with them.
## Set wingmen_wanted (0-3) in configure(); main.gd also applies cfg["wingmen"]. Losing a life only
## replaces losses up to that number (see reinforce_wingmen); the flight never grows.
const WINGMEN_MAX: int = 9
var wingmen_wanted: int = 0
var wingmen_list: Array = []
var _wingmen_done: bool = false


func _wingmen_tick() -> void:
	if taxi_af != null:
		_taxi_wingmen_tick()
		return              # the taxi flight IS the flight: no airborne top-up while it forms
	if _wingmen_done or not running or player == null or not is_instance_valid(player):
		return
	var pl: Aircraft = (player as Aircraft) if is_instance_valid(player) else null
	if pl == null or pl.state != Aircraft.State.ALIVE:
		return
	var id: String = pl.stats.id
	if AircraftCatalog.is_bomber(id):
		return          # bomber crews fly on their own
	var want: int = clampi(wingmen_wanted, 0, WINGMEN_MAX)
	if want <= 0:
		return
	# a runway start: the flight lines up on the same runway and takes off with the player (see _rw_spawn)
	if pl.on_ground and pl.speed < 1.0 and not _rw_active:
		var af: Airfield = _runway_under(pl)
		if af != null and _rw_spawn(pl, af, want):
			_wingmen_done = true
			return
	if pl.on_ground or pl.global_position.y < 60.0:
		return          # wait until the player is in the air (take-off)
	_wingmen_done = true
	wingmen_list = wingmen_list.filter(func(w) -> bool:
		return is_instance_valid(w) and (w as Aircraft).state == Aircraft.State.ALIVE)
	if wingmen_list.size() >= want:
		return
	var first: bool = wingmen_list.is_empty()
	var side: String = GameState.player_side
	var fwd: Vector3 = Vector3(pl.get_forward().x, 0.0, pl.get_forward().z)
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3(0, 0, -1)
	var yaw: Basis = Basis.looking_at(fwd, Vector3.UP)
	while wingmen_list.size() < want:
		var k: int = wingmen_list.size()
		var off: Vector3 = Radio.formation_offset(k, want)
		var w: Aircraft = AIFactory.spawn(world, id, side, pl.global_position + yaw * off, pl.get_heading_deg(), maxf(pl.speed, pl.stats.stall_speed * 1.6), 0.7, AIPilot.Role.WINGMAN, player)
		var pilot: AIPilot = AIFactory.pilot_of(w)
		if pilot != null:
			pilot.set_leader(player, off)
			pilot.detect_range = 9000.0
		wingmen_list.append(w)
		w.crashed.connect(func(a: Aircraft, _r: String) -> void:
			if is_instance_valid(a):
				a.get_tree().create_timer(2.5).timeout.connect(func() -> void:
					if is_instance_valid(a):
						a.queue_free()))
		AIFactory.add_marker(hud, w, Color(0.3, 0.75, 1.0))
	if first:
		Radio.say("Wingmen", "%d on your wing, ready." % want, Radio.Kind.FRIENDLY, 0.5)


# ------------------------------------------------------------------ runway take-off with the flight
## On a runway start the wingmen are parked on the same runway. One or two sit ahead in the starboard lane and roll
## first, then circle the field until the player is up; the rest wait behind and roll one after another once the
## player is on the move. Everyone forms on the player once he is airborne. The ground crew stand on the port
## side, so the queue uses the starboard lane and the centreline behind. main.gd moves a ground start up the
## runway by runway_queue_length() so the ones behind have tarmac to sit on.
const RUNWAY_WINGMEN_MAX: int = 5
var _rw_active: bool = false
var _rw_before: Array = []        # [{"ac", "t" (release time), "rolled"}]
var _rw_after: Array = []         # [{"ac", "start", "rolled", "t"}]
var _rw_t: float = 0.0
var _rw_fwd: Vector3 = Vector3.FORWARD
var _rw_start: Vector3 = Vector3.ZERO
var _rw_af: Airfield
var _rw_want: int = 0
var _rw_joined: bool = false
var _rw_timer: Timer
var _rw_old: Array = []       # queue entries from before a respawn: airborne or rolling, kept so they can rejoin


## How many of n wingmen roll before the player and how many after.
static func runway_split(n: int) -> Vector2i:
	n = clampi(n, 0, RUNWAY_WINGMEN_MAX)
	var before: int = 0 if n <= 1 else (1 if n <= 3 else 2)
	return Vector2i(before, n - before)


## Nose-to-tail spacing of the queue on the runway for an aircraft of this radius.
static func runway_slot_gap(radius: float) -> float:
	return radius * 2.6 + 12.0


func _runs_own_wingmen() -> bool:
	return has_method("_top_up_wingmen")


## How far up the runway a ground start is moved so the wingmen rolling after the player have room behind him.
func runway_queue_length() -> float:
	var pl: Aircraft = (player as Aircraft) if is_instance_valid(player) else null
	if pl == null or pl.stats == null or _runs_own_wingmen() or AircraftCatalog.is_bomber(pl.stats.id):
		return 0.0
	var alive: int = 0
	for w in wingmen_list:
		if is_instance_valid(w) and (w as Aircraft).state == Aircraft.State.ALIVE:
			alive += 1
	var sp: Vector2i = runway_split(clampi(wingmen_wanted, 0, WINGMEN_MAX) - alive)
	return float(sp.y) * runway_slot_gap(pl.stats.radius)


## The friendly airfield whose runway the aircraft is standing on (null if none).
func _runway_under(pl: Aircraft) -> Airfield:
	for n in get_tree().get_nodes_in_group("airfield"):
		var af: Airfield = n as Airfield
		if af == null or not is_instance_valid(af) or af.team != pl.team:
			continue
		var loc: Vector3 = af.global_transform.affine_inverse() * pl.global_position
		if absf(loc.x) <= af.runway_width * 0.5 + 6.0 and absf(loc.z) <= af.runway_length * 0.5 + 10.0:
			return af
	return null


func _rw_spawn(pl: Aircraft, af: Airfield, want: int) -> bool:
	wingmen_list = wingmen_list.filter(func(w) -> bool:
		return is_instance_valid(w) and (w as Aircraft).state == Aircraft.State.ALIVE)
	var sp: Vector2i = runway_split(want - wingmen_list.size())
	if sp.x + sp.y <= 0:
		return false
	# a respawn: the earlier queue entries (already rolling or released) must not hold up the new queue, whose
	# timers and "aircraft ahead is clear" checks start from scratch. They are kept only so they can rejoin.
	for e in _rw_before + _rw_after:
		if bool(e["rolled"]) and is_instance_valid(e["ac"]):
			_rw_old.append(e)
	_rw_before.clear()
	_rw_after.clear()
	var id: String = pl.stats.id
	var fwd: Vector3 = Vector3(pl.get_forward().x, 0.0, pl.get_forward().z)
	fwd = fwd.normalized() if fwd.length() > 0.1 else WorldCoords.heading_to_dir(af.heading_deg)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var r: float = pl.stats.radius
	var gap: float = runway_slot_gap(r)
	var lane: float = minf(r * 2.0 + 2.0, af.runway_width * 0.5 + r * 0.45)   # clear of the player's starboard wingtip
	var base: Vector3 = pl.global_position
	var hdg: float = pl.get_heading_deg()
	var k: int = wingmen_list.size()
	for i in sp.x:
		var w: Aircraft = _rw_park(id, base + fwd * gap * (1.3 + float(i) * 1.2) + right * lane, hdg, k, want)
		_rw_before.append({"ac": w, "t": 5.0 + float(i) * 8.0, "rolled": false})
		k += 1
	for j in sp.y:
		var p: Vector3 = base - fwd * gap * float(j + 1) + right * (lane if j % 2 == 0 else 0.0)
		var w2: Aircraft = _rw_park(id, p, hdg, k, want)
		_rw_after.append({"ac": w2, "start": p, "rolled": false, "t": 0.0})
		k += 1
	_rw_af = af
	_rw_fwd = fwd
	_rw_start = base
	_rw_want = want
	_rw_t = 0.0
	_rw_joined = false
	_rw_active = true
	if _rw_timer == null:
		_rw_timer = Timer.new()
		_rw_timer.wait_time = 0.25
		_rw_timer.autostart = true
		_rw_timer.timeout.connect(_rw_tick)
		add_child(_rw_timer)
	return true


## One wingman parked on the runway, engine idling, waiting for its turn (the pilot is switched off until then).
func _rw_park(id: String, pos: Vector3, hdg: float, k: int, want: int) -> Aircraft:
	var w: Aircraft = AIFactory.spawn(world, id, GameState.player_side, pos, hdg, 0.0, 0.7, AIPilot.Role.WINGMAN, null, true)
	var pilot: AIPilot = AIFactory.pilot_of(w)
	if pilot != null:
		pilot.leader = null
		pilot.enabled = false
		pilot.detect_range = 9000.0
		pilot.set_meta("rw_off", Radio.formation_offset(k, want))
	w.throttle_target = 0.0
	w.set_meta("radio_idx", k + 2)          # callsigns follow the order on the runway
	wingmen_list.append(w)
	w.crashed.connect(func(a: Aircraft, _r: String) -> void:
		if is_instance_valid(a):
			a.get_tree().create_timer(2.5).timeout.connect(func() -> void:
				if is_instance_valid(a):
					a.queue_free()))
	AIFactory.add_marker(hud, w, Color(0.3, 0.75, 1.0))
	return w


func _rw_tick() -> void:
	if not _rw_active or not running:
		return
	var pl: Aircraft = (player as Aircraft) if is_instance_valid(player) else null
	if pl == null or not is_instance_valid(pl) or pl.state != Aircraft.State.ALIVE:
		_rw_active = false
		for e in _rw_before + _rw_after:          # the player is gone: anyone still parked goes up anyway
			if not bool(e["rolled"]):
				e["rolled"] = true
				_rw_release(e["ac"], AIPilot.State.PATROL)
		return
	_rw_t += 0.25
	var pl_up: bool = not pl.on_ground and pl.altitude_agl > 25.0
	var pl_along: float = (pl.global_position - _rw_start).dot(_rw_fwd)
	if _rw_debug:
		_rw_debug_tick(pl, pl_along)
	# the ones ahead roll on a timer, then hold over the field
	for e in _rw_before:
		if not bool(e["rolled"]) and _rw_t >= float(e["t"]):
			e["rolled"] = true
			_rw_release(e["ac"], AIPilot.State.PATROL)
			if is_instance_valid(e["ac"]):
				Radio.say(Radio.callsign_of(e["ac"]), ["Rolling.", "Off we go.", "Rolling now. See you upstairs."][randi() % 3], Radio.Kind.FRIENDLY, 0.3)
	# the ones behind follow the player down the runway, each once the aircraft ahead of it is well clear
	var gap: float = runway_slot_gap(pl.stats.radius)
	for j in _rw_after.size():
		var e: Dictionary = _rw_after[j]
		if bool(e["rolled"]):
			continue
		var ahead_clear: bool
		if j == 0:
			ahead_clear = pl_up or (pl_along > gap + 45.0 and pl.speed > 8.0)
		else:
			var prev: Dictionary = _rw_after[j - 1]
			if not bool(prev["rolled"]):
				break
			var pa: Variant = prev["ac"]
			var moved: float = 9999.0
			if is_instance_valid(pa):
				moved = ((pa as Aircraft).global_position - (prev["start"] as Vector3)).dot(_rw_fwd)
			ahead_clear = moved > gap + 45.0 and _rw_t - float(prev["t"]) > 3.0
		if ahead_clear:
			e["rolled"] = true
			e["t"] = _rw_t
			_rw_release(e["ac"], AIPilot.State.FORMATION if pl_up or pl.speed > 20.0 else AIPilot.State.PATROL)
		break
	# once the player is up, everyone already airborne joins on him; anyone circling while he is still
	# on the ground keeps circling the field
	_rw_old = _rw_old.filter(func(e) -> bool: return is_instance_valid(e["ac"]))
	for e in _rw_before + _rw_after + _rw_old:
		var a: Variant = e["ac"]
		if not bool(e["rolled"]) or not is_instance_valid(a):
			continue
		var p: AIPilot = AIFactory.pilot_of(a)
		if p == null:
			continue
		if pl_up:
			if p.leader != pl:
				p.set_leader(pl, p.get_meta("rw_off", Vector3(70, -5, 90)))
				if p.state == AIPilot.State.TAKEOFF:
					p.after_takeoff = AIPilot.State.FORMATION
				elif p.state == AIPilot.State.PATROL:
					p._set_state(AIPilot.State.FORMATION)
		elif p.leader == pl and p.state != AIPilot.State.TAKEOFF:
			p.leader = null
			p._set_state(AIPilot.State.PATROL)
	if pl_up and not _rw_joined:
		_rw_joined = true
		var any: Variant = null
		for e in _rw_before:
			if is_instance_valid(e["ac"]):
				any = e["ac"]
		if any != null:
			Radio.say(Radio.callsign_of(any), "Got you. Joining up.", Radio.Kind.FRIENDLY, 2.0)
	var all_rolled: bool = true
	for e in _rw_after:
		if not bool(e["rolled"]):
			all_rolled = false
	if all_rolled and pl_up and pl.altitude_agl > 300.0 and not _rw_debug:
		_rw_active = false
		_rw_before.clear()
		_rw_after.clear()


# ------------------------------------------------------------------ taxi-out flight (P: taxi to runway)
## The player starts at a dispersal: the flight taxis with him. One wingman per clear dispersal spot is
## parked and given a TaxiController; each holds short until the aircraft ahead of it is on the runway,
## keeps a gap behind it (and stops to wait if the player stops), and joins the runway take-off queue
## as it lines up.
var taxi_af: Airfield = null       # set by main._dispersal_start
var _taxi_wing: Array = []         # [{"ac", "ctrl"}] in trail order behind the player
var _taxi_want: int = 0
var _taxi_i: int = 0               # wingmen spawned so far
var _taxi_scan: int = 0            # dispersal candidates scanned


## main._dispersal_start: the player taxis out of `af` with `want` wingmen trailing.
func begin_taxi_flight(af: Airfield, want: int) -> void:
	taxi_af = af
	_taxi_want = clampi(want, 0, 3)
	_taxi_i = 0
	_taxi_scan = 0
	_taxi_wing.clear()


## main._on_taxi_done: the player is lined up - open the hold for the first wingman and arm the runway
## take-off queue behind him.
func player_lined_up(lineup: Vector3) -> void:
	if taxi_af == null:
		return
	_rw_af = taxi_af
	_rw_fwd = WorldCoords.heading_to_dir(taxi_af.heading_deg)
	_rw_start = lineup
	_rw_active = true
	if _rw_timer == null:
		_rw_timer = Timer.new()
		_rw_timer.wait_time = 0.25
		_rw_timer.autostart = true
		_rw_timer.timeout.connect(_rw_tick)
		add_child(_rw_timer)
	if not _taxi_wing.is_empty():
		(_taxi_wing[0]["ctrl"] as TaxiController).cleared = true


func _taxi_wingmen_tick() -> void:
	if taxi_af == null or _taxi_i >= _taxi_want or player == null or not is_instance_valid(player):
		return
	var pl: Aircraft = (player as Aircraft) if is_instance_valid(player) else null
	if pl == null or pl.state != Aircraft.State.ALIVE or not pl.on_ground:
		return
	var spots: Array = taxi_af._dispersal_local
	var n: int = spots.size()
	for _try in 6:
		if _taxi_i >= _taxi_want or _taxi_scan >= n:
			taxi_af = null          # the flight is formed (or nothing clear is left): done
			return
		var ki: int = taxi_af.keep_clear_i
		var k: int = (ki + 1 + _taxi_scan) % n if ki >= 0 else _taxi_scan % n
		_taxi_scan += 1
		if k == ki:
			continue
		var route: PackedVector3Array = taxi_af.taxi_route(spots[k])
		if route.size() < 3:
			continue
		var wp: Vector3 = taxi_af.global_transform * (spots[k] as Vector3)
		var blocked: bool = false
		for ps in taxi_af.parked_spots:
			if Vector2(wp.x, wp.z).distance_to(Vector2((ps as Vector3).x, (ps as Vector3).z)) < 15.0:
				blocked = true
				break
		if blocked:
			continue
		var wd: Vector3 = taxi_af.global_transform.basis * ((route[1] as Vector3) - (route[0] as Vector3))
		wd.y = 0.0
		var yaw: float = rad_to_deg(atan2(wd.x, -wd.z))
		var w: Aircraft = _rw_park(pl.stats.id, Vector3(wp.x, taxi_af.surface_y + pl.stats.gear_height + 0.35, wp.z), yaw, _taxi_i, _taxi_want)
		var ctrl := TaxiController.new()
		add_child(ctrl)
		var world := PackedVector3Array()
		for lp in route:
			var t: Vector3 = taxi_af.global_transform * (lp as Vector3)
			t.y = taxi_af.surface_y + w.stats.gear_height + 0.35
			world.append(t)
		ctrl.setup(w, world, taxi_af.heading_deg, hud, true)
		ctrl.ahead_ac = pl if _taxi_wing.is_empty() else (_taxi_wing[_taxi_wing.size() - 1]["ac"] as Aircraft)
		if _taxi_debug:
			ctrl.set("_log_t", 0.01)
		var j: int = _taxi_wing.size()
		var w_ref: Aircraft = w
		ctrl.lined_up.connect(func() -> void:
			_taxi_wing_lined_up(w_ref, j))
		_taxi_wing.append({"ac": w, "ctrl": ctrl})
		_taxi_i += 1
		print("[taxi] wingman %d taxiing from dispersal %d" % [_taxi_i, k])
		return     # one parked spawn per tick (each build is a noticeable hitch)


func _taxi_wing_lined_up(w: Aircraft, j: int) -> void:
	if not is_instance_valid(w):
		return
	_rw_after.append({"ac": w, "start": w.global_position, "rolled": false, "t": _rw_t})
	_rw_active = true
	if _rw_timer == null:
		_rw_timer = Timer.new()
		_rw_timer.wait_time = 0.25
		_rw_timer.autostart = true
		_rw_timer.timeout.connect(_rw_tick)
		add_child(_rw_timer)
	if j + 1 < _taxi_wing.size():
		(_taxi_wing[j + 1]["ctrl"] as TaxiController).cleared = true
		Radio.say(Radio.callsign_of(w), "Holding short. Waiting for you to get clear.", Radio.Kind.FRIENDLY, 0.4)


## Debug (--rw-test): the player's aircraft takes off by itself after 12 s; positions are logged every 2 s.
var _rw_debug: bool = OS.get_cmdline_user_args().has("--rw-test")
## Debug (--taxi-test): the taxiing wingmen log their legs every 2 s as well.
var _taxi_debug: bool = OS.get_cmdline_user_args().has("--taxi-test")


func _rw_debug_tick(pl: Aircraft, pl_along: float) -> void:
	if _rw_t >= 12.0 and AIFactory.pilot_of(pl) == null:
		pl.player_controlled = false
		var ap: AIPilot = AIPilot.attach(pl, AIPilot.Role.FIGHTER, 0.9)
		ap.detect_range = 0.0                # a calm leader: no fighting, a climbing square circuit with gentle turns
		var rgt := Vector3(-_rw_fwd.z, 0.0, _rw_fwd.x)
		var y0: float = pl.global_position.y
		var pts: Array[Vector3] = []
		var c: Vector3 = pl.global_position + _rw_fwd * 9000.0
		for q in [Vector3(0, 900, 0), rgt * 7000.0 + Vector3(0, 1300, 0), rgt * 7000.0 + _rw_fwd * 7000.0 + Vector3(0, 1500, 0), _rw_fwd * 7000.0 + Vector3(0, 1500, 0), Vector3(0, 1500, 0), rgt * 7000.0 + Vector3(0, 1500, 0)]:
			pts.append(Vector3(c.x + q.x, y0 + q.y, c.z + q.z))
		ap.waypoints = pts
		ap.wp_index = 0
		ap.begin_takeoff(_rw_fwd, AIPilot.State.ROUTE)
		print("RWTEST player rolling")
	if fmod(_rw_t, 1.0) > 0.01:
		return
	var right := Vector3(-_rw_fwd.z, 0.0, _rw_fwd.x)
	var line: String = "RWTEST t=%.0f player along=%.0f spd=%.0f agl=%.0f gnd=%s bank=%.0f" % [_rw_t, pl_along, pl.speed, pl.altitude_agl, str(pl.on_ground), rad_to_deg(AIPilot.bank_of(pl))]
	for e in _rw_before + _rw_after:
		var a: Variant = e["ac"]
		if not is_instance_valid(a):
			line += " | dead"
			continue
		var w: Aircraft = a
		var rel: Vector3 = w.global_position - _rw_start
		var p: AIPilot = AIFactory.pilot_of(w)
		line += " | %s st=%d spd=%.0f d=%.0f slot=%.0f bank=%.0f pit=%.0f thr=%.2f r=%.2f p=%.2f%s" % ["B" if e in _rw_before else "A", p.state if p else -1, w.speed, w.global_position.distance_to(pl.global_position), p._form_d if p else -1.0, rad_to_deg(AIPilot.bank_of(w)), rad_to_deg(w._pitch_angle()), w.throttle, w.cmd_roll, w.cmd_pitch, (" L c=%d m=%d av=%.1f" % [int(p._cruise_ok()), p._man, p._avoid_t]) if p and p.leader == pl else ""]
	print(line)
	if fmod(_rw_t, 10.0) < 0.01:
		var rr: String = "RWROLL t=%.0f" % _rw_t
		for e in _rw_before + _rw_after:
			var p2: AIPilot = AIFactory.pilot_of(e["ac"]) if is_instance_valid(e["ac"]) else null
			if p2 != null and p2.roll_time > 1.0:
				rr += " %.1f deg/s (%.0f s, bank %.0f)" % [rad_to_deg(p2.roll_activity / p2.roll_time), p2.roll_time, rad_to_deg(AIPilot.bank_of(e["ac"]))]
		print(rr)


## Hand a parked wingman to its pilot: take-off roll along the runway, then `next` (PATROL circles the field).
func _rw_release(a: Variant, next: int) -> void:
	if not is_instance_valid(a):
		return
	var p: AIPilot = AIFactory.pilot_of(a)
	if p == null:
		return
	p.enabled = true
	if next == AIPilot.State.FORMATION and is_instance_valid(player):
		p.set_leader(player, p.get_meta("rw_off", Vector3(70, -5, 90)))
	else:
		p.leader = null
		var c: Vector3 = _rw_af.global_position if is_instance_valid(_rw_af) else (a as Aircraft).global_position
		p.patrol_center = c
		p.patrol_alt = c.y + 700.0
		p.patrol_radius = 1700.0
	p.begin_takeoff(_rw_fwd, next)


## Losing a life brings in replacements up to the configured flight size: the flight never grows beyond
## what the mode asked for, however many times the player goes down.
func reinforce_wingmen() -> void:
	if wingmen_wanted <= 0:
		return
	wingmen_list = wingmen_list.filter(func(w) -> bool:
		return is_instance_valid(w) and (w as Aircraft).state == Aircraft.State.ALIVE)
	# wingmen still alive stay as they are: only a flight with losses gets replacements
	if wingmen_list.size() >= wingmen_wanted:
		return
	_wingmen_done = false


## Bomber sortie support: when the player flies a bomber, a squadron forms up behind him and a pair of fighter
## escorts waits at a rendezvous point ahead, then joins his wing. Opt in with `bomber_support = true`
## (bombing + historical missions) so bomber crews are not flying on their own.
## Set `_support_skip_bombers` when the mission already provides its own bomber stream (then only escorts join).
var bomber_support: bool = false
var _support_done: bool = false
var _support_skip_bombers: bool = false
var _support_nodes: Array = []
var _squadron_spawned: bool = false
var _escorts_spawned: bool = false
var _rv_pos: Vector3 = Vector3.ZERO
var _rv_marker: Node3D = null
var _rv_t: float = 0.0
const RV_AHEAD: float = 5200.0       # the escort rendezvous, this far along the player's heading
const RV_RADIUS: float = 2400.0      # arrive this close and the fighters join up
const RV_FALLBACK: float = 120.0     # ... or this long after forming up, if the point was missed


func _support_tick() -> void:
	if _support_done or not running or player == null or not is_instance_valid(player):
		return
	var pl: Aircraft = (player as Aircraft) if is_instance_valid(player) else null
	if pl == null or pl.state != Aircraft.State.ALIVE or pl.on_ground or pl.global_position.y < 60.0:
		return          # wait until the player is airborne (take-off)
	if not AircraftCatalog.is_bomber(String(pl.stats.id)):
		_support_done = true
		return          # fighter pilots get wingmen instead (see _wingmen_tick)
	if not _squadron_spawned:
		_squadron_spawned = true
		spawn_bomber_support(pl)
		return
	if _escorts_spawned:
		return
	_rv_t += 1.0
	var near: bool = Vector2(pl.global_position.x - _rv_pos.x, pl.global_position.z - _rv_pos.z).length() <= RV_RADIUS
	if near or _rv_t >= RV_FALLBACK:
		_escorts_spawned = true
		_support_done = true
		_spawn_fighter_escort(pl)


## Spawn the player's bomber squadron (flying on his wing) and set the escort rendezvous ahead.
func spawn_bomber_support(pl: Aircraft) -> void:
	var side: String = GameState.player_side
	var fwd: Vector3 = Vector3(pl.get_forward().x, 0.0, pl.get_forward().z)
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3(0, 0, -1)
	var hdg: float = WorldCoords.dir_to_heading(fwd)
	var diff: float = 0.5
	var dv: Variant = get("difficulty")
	if dv != null:
		diff = float(dv)
	# the rest of the squadron, formed up behind the player
	if not _support_skip_bombers:
		var bid: String = String(pl.stats.id)
		if not AircraftCatalog.is_bomber(bid):
			var bids: Array = AircraftCatalog.bombers_for_side(side)
			bid = String(bids[0]) if not bids.is_empty() else "b26"
		var np: Variant = nav_point()
		var tgt: Vector3 = (np as Vector3) if np != null else pl.global_position + fwd * 6000.0
		var alt: float = maxf(pl.global_position.y, 200.0)
		var route: Array[Vector3] = [Vector3(tgt.x, alt, tgt.z), pl.global_position - fwd * 1500.0]
		var start_pos: Vector3 = pl.global_position - fwd * 220.0
		var form: BomberFormation = BomberFormation.spawn(world, bid, side, 3, start_pos, hdg, route, diff, 62.0)
		_support_nodes.append(form)
		var speed_k: float = clampf(pl.stats.max_speed / AIPilot.BOMBER_CRUISE_CAP, 1.0, 1.6)
		for m in form.members:
			if not is_instance_valid(m):
				continue
			# Match the player's bomber: the AI-only speed cut (made so fighters can catch a raid) would leave the
			# squadron trailing behind its own leader.
			m.stats.max_speed = maxf(m.stats.max_speed, pl.stats.max_speed)
			var mp: AIPilot = AIFactory.pilot_of(m)
			if mp != null:
				mp.bomber_speed_k = speed_k
			AIFactory.add_marker(hud, m, Color(0.45, 0.85, 1.0))
		# The box flies on the player's wing: the AI leader follows the player and the rest keep station on him.
		var lead: AIPilot = AIFactory.pilot_of(form.leader)
		if lead != null:
			lead.set_leader(pl, Vector3(0.0, -25.0, 220.0))
			lead.role = AIPilot.Role.BOMBER_FOLLOWER
			lead._set_state(AIPilot.State.FORMATION)
		Radio.say("Bomber leader", "Squadron formed up behind you. Escort rendezvous ahead.", Radio.Kind.FRIENDLY, 1.0)
	# the escort rendezvous: a marker on the minimap and a call to fly to it
	_rv_pos = pl.global_position + fwd * RV_AHEAD
	_rv_t = 0.0
	_rv_marker = Node3D.new()
	_rv_marker.name = "EscortRV"
	_rv_marker.global_position = _rv_pos
	world.add_child(_rv_marker)
	_support_nodes.append(_rv_marker)
	AIFactory.add_marker(hud, _rv_marker, Color(0.35, 0.9, 1.0))
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "Squadron with you - fly on to meet your fighter escort", 5.0)


## The fighter escort arrives at the rendezvous and takes station on the player's wing, staying close.
func _spawn_fighter_escort(pl: Aircraft) -> void:
	var side: String = GameState.player_side
	var fits: Array = AircraftCatalog.fighters_for_side(side)
	if fits.is_empty():
		return
	var fid: String = String(fits[0])
	var fwd: Vector3 = Vector3(pl.get_forward().x, 0.0, pl.get_forward().z)
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3(0, 0, -1)
	var hdg: float = WorldCoords.dir_to_heading(fwd)
	var yaw: Basis = Basis.looking_at(fwd, Vector3.UP)
	var diff: float = 0.5
	var dv: Variant = get("difficulty")
	if dv != null:
		diff = float(dv)
	for k in 2:
		var off: Vector3 = Radio.formation_offset(k, 2)
		var esc: Aircraft = AIFactory.spawn(world, fid, side, _rv_pos + yaw * off, hdg,
			maxf(pl.speed, pl.stats.stall_speed * 1.8), clampf(diff + 0.2, 0.0, 1.0), AIPilot.Role.WINGMAN, player)
		var pilot: AIPilot = AIFactory.pilot_of(esc)
		if pilot != null:
			pilot.set_leader(player, off)
			pilot.set_order(AIPilot.Order.COVER)      # tight formation, stay with the leader
			pilot.engage_radius = 1600.0              # only break for enemies close to the player
			pilot.detect_range = 3000.0
		_support_nodes.append(esc)
		AIFactory.add_marker(hud, esc, Color(0.3, 0.85, 1.0))
	if _rv_marker != null and is_instance_valid(_rv_marker):
		_rv_marker.queue_free()
		_rv_marker = null
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "Fighter escort joined - on your wing", 5.0)
	Radio.say("Escort", "Escort flight joining up. We'll stay on your wing.", Radio.Kind.FRIENDLY, 1.0)


## World position the compass should point at (next objective / waypoint), or null for none. Modes override it.
func nav_point() -> Variant:
	return null


## The buildings the player has been sent to destroy right now (TargetSpotter calls them out and marks them when
## they come into view). Modes with a specific target override it.
func strike_targets() -> Array:
	return []


## Helper for nav_point(): position of the node in `nodes` nearest the player (skipping destroyed ones).
func _nearest_pos(nodes: Array) -> Variant:
	if player == null or not is_instance_valid(player):
		return null
	var pp: Vector3 = (player as Node3D).global_position
	var best: Variant = null
	var bd: float = INF
	for n in nodes:
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		if n.has_method("is_destroyed") and bool(n.call("is_destroyed")):
			continue
		var d: float = Vector2(n.global_position.x - pp.x, n.global_position.z - pp.z).length()
		if d < bd:
			bd = d
			best = (n as Node3D).global_position
	return best


func setup(p_world: Node3D, p_player: Node3D, p_hud: Node) -> void:
	add_to_group("game_mode")
	world = p_world
	player = p_player
	hud = p_hud


func start() -> void:
	running = true
	if not Weapons.player_kill.is_connected(_on_any_player_kill):
		Weapons.player_kill.connect(_on_any_player_kill)
	if not has_method("_top_up_wingmen"):     # (the dogfight mode runs its own wingmen; the tick no-ops at 0)
		var tm := Timer.new()
		tm.wait_time = 1.0
		tm.autostart = true
		tm.timeout.connect(_wingmen_tick)
		add_child(tm)
	if bomber_support:
		var stm := Timer.new()
		stm.wait_time = 1.0
		stm.autostart = true
		stm.timeout.connect(_support_tick)
		add_child(stm)


func stop() -> void:
	running = false
	for n in _support_nodes:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	_support_nodes.clear()


## Live stats for the pause-menu score sheet: score + time, merged with the mode's own _stats() (kills, targets...).
func live_stats() -> Dictionary:
	var d: Dictionary = {"score": score, "time": elapsed}
	if has_method("_stats"):
		d.merge(call("_stats"), true)
	_merge_kills(d)
	return d


func _kill_total() -> int:
	return int(player_kills["air"]) + int(player_kills["ground"]) + int(player_kills["ships"]) + int(player_kills["v1"])


## Kills include everything the player destroyed (aircraft, vehicles, guns, ships, V-1s), not only what a mode counts.
func _merge_kills(d: Dictionary) -> void:
	d["kills"] = maxi(int(d.get("kills", 0)), _kill_total())
	if int(player_kills["ships"]) > 0 and not d.has("ships"):
		d["ships"] = int(player_kills["ships"])
	if int(player_kills["air"]) > 0 and not d.has("aircraft"):
		d["aircraft"] = int(player_kills["air"])


func _on_any_player_kill(node: Node) -> void:
	if not running or node == null or not is_instance_valid(node):
		return
	var pl_team: String = GameState.player_side
	var t: Variant = node.get("team")
	if t != null and str(t) == pl_team:
		return                      # own side: no credit
	var cls: String = ""
	if node is FlyingBomb:
		cls = "v1"
	elif node is Parachute:
		return
	elif node is Aircraft:
		cls = "air"
	elif node is GroundShip:
		cls = "ships"
	else:
		cls = "ground"
	player_kills[cls] = int(player_kills[cls]) + 1
	var what: String = {"air": "aircraft destroyed", "ships": "ship sunk", "v1": "V-1 shot down", "ground": "ground target destroyed"}[cls]
	var entry: String = ""
	if cls != "ground":
		var nm: Variant = node.get("display_name")
		entry = "%s%s" % [what.capitalize(), (" (%s)" % str(nm)) if nm != null and str(nm) != "" else ""]
	PilotLog.record_and_announce(pl_team, {cls: 1, "points": int(KILL_POINTS[cls])}, entry, hud)


func add_score(points: int) -> void:
	score += points
	score_changed.emit(score)


func finish(success: bool, extra: Dictionary = {}) -> void:
	if not running:
		return
	running = false
	var stats := {"score": score, "time": elapsed, "success": success}
	stats.merge(extra, true)
	print("[mission] finish success=%s reason='%s' t=%.0f score=%d mode=%s" % [success, str(extra.get("reason", "")), elapsed, score, str(get_meta("mode_id", name))])
	_merge_kills(stats)
	var mid: String = str(get_meta("mode_id", ""))
	var label: String = ModeRegistry.display_name(mid) if mid != "" and ModeRegistry.MODES.has(mid) else "Sortie"
	PilotLog.record_and_announce(GameState.player_side, {"missions": 1 if success else 0, "missions_failed": 0 if success else 1,
		"points": 300 if success else 0}, "%s: %s, %d destroyed" % [label, "success" if success else "failed", _kill_total()], hud)
	mission_complete.emit(success, stats)


var _spotter: TargetSpotter = null


func _process(delta: float) -> void:
	if running:
		elapsed += delta
		# drive the taxiing wingmen (the player's own controller is ticked from main)
		for e in _taxi_wing:
			var c: TaxiController = e["ctrl"]
			if c == null or not is_instance_valid(c):
				continue
			if c.active:
				c.tick(delta)
			else:
				e["ctrl"] = null
				c.queue_free()
		if _spotter == null:
			_spotter = TargetSpotter.new()
			_spotter.mode = self
			add_child(_spotter)
		# hours flown go into the logbook a minute at a time
		var pl: Aircraft = (player as Aircraft) if is_instance_valid(player) else null
		if pl != null and is_instance_valid(pl) and pl.state == Aircraft.State.ALIVE and not pl.on_ground:
			_air_log_t += delta
			if _air_log_t >= 60.0:
				_air_log_t -= 60.0
				PilotLog.record_and_announce(GameState.player_side, {"seconds": 60}, "", hud)
