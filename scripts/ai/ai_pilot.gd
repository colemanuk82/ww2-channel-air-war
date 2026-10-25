class_name AIPilot
extends Node
## AI flight controller. Attach to an Aircraft (child node) with AIPilot.attach(aircraft, role, difficulty).
## Drives cmd_pitch / cmd_roll / cmd_yaw / throttle_target / cmd_boost / cmd_fire and fires bullets via AIGun.
##
## Roles:
##   FIGHTER          patrol -> intercept -> attack, evade when threatened, return home when badly hurt
##   WINGMAN          follows `leader` (usually the player) in formation and engages enemies near it
##   BOMBER_LEADER    follows `waypoints` (set_route)
##   BOMBER_FOLLOWER  holds `formation_offset` relative to `leader` (BomberFormation sets this up)
## Difficulty 0..1 scales accuracy, reaction time, aggression and bullet damage.

signal state_changed(new_state: int)
signal route_finished
signal landed_ai(aircraft: Aircraft)
signal climb_out_finished

enum Role { FIGHTER, WINGMAN, BOMBER_LEADER, BOMBER_FOLLOWER }
enum State { PATROL, INTERCEPT, ATTACK, EVADE, RETURN, FORMATION, ROUTE, TAKEOFF, LAND, CLIMB_OUT, ENERGY, STRIKE }
enum Tactic { PURSUIT, CLIMB, DIVE, ZOOM }
enum Man { NONE, HIGH_YOYO, LOW_YOYO, BOOM_ZOOM, BARREL, IMMELMANN, SPLIT_S, WINGOVER, BREAK, UNLOAD, SCISSORS, DEF_BARREL, SPIRAL }
const MAN_NAMES := ["none", "high yo-yo", "low yo-yo", "boom and zoom", "barrel roll attack", "immelmann", "split-s", "wingover", "break turn", "unloaded extension", "scissors", "defensive barrel roll", "defensive spiral"]
static var bfm_counts: Dictionary = {}    # debug: how often each basic fighter manoeuvre was flown
enum Order { FORM, ATTACK, COVER, RTB }     # radio orders from the player to wingmen (see Radio)

const FIRE_RANGE: float = 700.0
const ATTACK_RANGE: float = 1300.0
const BASE_DETECT: float = 5200.0

var ac: Aircraft
var role: int = Role.FIGHTER
var state: int = State.PATROL
var difficulty: float = 0.5
var accuracy: float = 0.6
var reaction: float = 0.25
var aggression: float = 0.6
var bullet_damage: float = 4.5
var turn_scale: float = 1.0       # scales stick deflection
var enabled: bool = true

var target: Aircraft
var leader: Node3D
var formation_offset: Vector3 = Vector3(60, 0, 80)
var formation_scale: float = 1.0    # <1 = tight formation (COVER order)
var order: int = Order.FORM
var order_target: Aircraft
var engage_radius: float = 4200.0   # wingmen only engage enemies this close to their leader
var waypoints: Array[Vector3] = []
var wp_index: int = 0
var patrol_center: Vector3 = Vector3.ZERO
var patrol_radius: float = 2200.0
var patrol_alt: float = 900.0
# Climb-out circuit after take-off (State.CLIMB_OUT): circle climb_center gaining height to climb_alt, then
# hand over to after_climb (usually ROUTE). Set by callers that want a formation to form up before it leaves.
var climb_center: Vector3 = Vector3.ZERO
var climb_alt: float = 3000.0
var climb_radius: float = 1500.0
var after_climb: int = State.ROUTE
var home: Vector3 = Vector3.ZERO
var detect_range: float = BASE_DETECT
var cruise_throttle: float = 0.7
var max_cmd: float = 1.0

var _terrain: Node
var _think_t: float = 0.0
var _mistake_t: float = 0.0      # > 0 = the pilot is mid-mistake (no ground avoidance)
var _mistake_cd: float = 0.0
# Energy fighting: some pilots prefer to fight in the vertical — they break off, climb for a height
# advantage over the target and come back down on it instead of turning with it.
var energy_fighter: bool = false
var _energy_t: float = 0.0       # > 0 = currently climbing for height
var _energy_cd: float = 0.0
var _evade_t: float = 0.0
var _evade_cd: float = 0.0
var _jink_t: float = 0.0
var _jink_sign: float = 1.0
var _jink_up: float = 0.0
var _weave: float = 0.0        # bomber formation weave: 0..0.5 lateral authority while under attack
var _weave_t: float = 0.0
var _bail_hp: float = 0.32
var _stubborn: bool = false           # presses the attack until it is nearly finished
var _decided: bool = false            # has already made the "go home or fight on" call for this damage
var _aim_err: Vector3 = Vector3.ZERO
var _aim_err_t: float = 0.0
var _seen_tp: Vector3 = Vector3.ZERO
var _seen_tv: Vector3 = Vector3.ZERO
var _seen_t: float = 0.0
var _burst_t: float = 0.0
var _pause_t: float = 0.0
var _fire_acc: float = 0.0
var _muzzle_idx: int = 0
var _muzzles: Array[Node3D] = []
var _avoid_t: float = 0.0
var _sep_dir: Vector3 = Vector3.ZERO
var _sep_t: float = 0.0
var _form_dir: Vector3 = Vector3.ZERO     # smoothed formation steering so wingmen ride the slot smoothly
var _form_thr: float = 0.0
var _dir: Vector3 = Vector3.FORWARD
var _thr: float = 0.7
var _cooling: bool = false     # engine too hot: reduced power until it cools (Options > Realism)
## Bombers cruise slower than any fighter's top speed (a Spitfire tops out at ~122 u/s), so escorts and interceptors can
## catch them. bomber_speed_k scales it (EscortMode ramps it up so the formation leaves the field slowly).
const BOMBER_CRUISE_CAP := 90.0
var bomber_speed_k: float = 1.0
var _route_alt_err: float = 0.0	# last route/slot altitude error (target y - own y); feeds the sink guard in the throttle governor
var _boost: bool = false
var _pull: float = 1.0
var _vis: float = 1.0
var _orbit_dir: float = 1.0
var _tactic: int = Tactic.PURSUIT
var _tactic_t: float = 0.0
var fire_time: float = 0.0   # debug: total seconds spent firing
var _man: int = Man.NONE         # basic fighter manoeuvre in progress
var _man_t: float = 0.0
var _man_len: float = 0.0
var _man_side: float = 1.0
var _man_cd: float = 0.0         # pause before the next manoeuvre may start
var _man_phase: int = 0
var _man_dir0: Vector3 = Vector3.FORWARD   # heading when the manoeuvre began (reversals need it)
var _threat: Aircraft            # the enemy currently on my tail
var runway_dir: Vector3 = Vector3.FORWARD   # TAKEOFF: heading to hold on the runway and climb out on
var after_takeoff: int = State.FORMATION    # state to enter once safely airborne
var land_af: Airfield                        # LAND: the field to land at
var bomb_target: Vector3 = Vector3.ZERO     # bombers release over this point
var bomb_armed: bool = false
var _bomb_cd: float = 0.0
var _strike_cd: float = 0.0      # ground / naval strike cooldown
var _salvos: int = 0             # rocket salvos fired at ground or naval targets
const GROUND_STRIKE_RANGE: float = 900.0


static func attach(aircraft: Aircraft, p_role: int = Role.FIGHTER, p_difficulty: float = 0.5) -> AIPilot:
	var p := AIPilot.new()
	p.name = "AIPilot"
	p.ac = aircraft
	p.role = p_role
	p.set_difficulty(p_difficulty)
	aircraft.add_child(p)
	aircraft.auto_level = false
	p.patrol_center = aircraft.global_position
	p.patrol_alt = aircraft.global_position.y
	p.home = aircraft.global_position
	p._muzzles = aircraft.get_muzzles()
	p._think_t = randf() * 0.3
	p._orbit_dir = 1.0 if randf() < 0.5 else -1.0
	if p_role == Role.BOMBER_LEADER or p_role == Role.BOMBER_FOLLOWER:
		p.state = State.ROUTE if p_role == Role.BOMBER_LEADER else State.FORMATION
		p.max_cmd = 0.6
		p.cruise_throttle = 0.68
	elif p_role == Role.WINGMAN:
		p.state = State.FORMATION
	aircraft.damaged.connect(p._on_damaged)
	return p


func set_difficulty(d: float) -> void:
	difficulty = clampf(d, 0.0, 1.0)
	var jitter: float = randf_range(-0.08, 0.08)
	accuracy = clampf(lerpf(0.35, 0.95, difficulty) + jitter, 0.2, 1.0)
	reaction = lerpf(0.45, 0.08, difficulty) * randf_range(0.85, 1.2)
	aggression = clampf(lerpf(0.35, 0.9, difficulty) + jitter, 0.1, 1.0)
	bullet_damage = lerpf(3.4, 6.0, difficulty)
	turn_scale = lerpf(0.75, 1.0, difficulty)
	_bail_hp = clampf(lerpf(0.35, 0.08, aggression) + randf_range(-0.07, 0.07), 0.05, 0.45)
	_stubborn = randf() < 0.28 * aggression          # some pilots press on regardless of damage
	# better pilots more often fight in the vertical rather than in the turn circle
	energy_fighter = randf() < lerpf(0.25, 0.65, difficulty)


func set_route(points: Array[Vector3]) -> void:
	waypoints = points
	wp_index = 0
	if role == Role.FIGHTER and not points.is_empty():
		state = State.ROUTE


func set_leader(n: Node3D, offset: Vector3) -> void:
	leader = n
	formation_offset = offset


## Radio order from the player. ATTACK needs the target; RTB sends the wingman to the nearest friendly airfield.
func set_order(o: int, tgt: Aircraft = null) -> void:
	order = o
	order_target = tgt
	formation_scale = 1.0
	engage_radius = 4200.0
	match o:
		Order.ATTACK:
			if tgt != null:
				target = tgt
				_set_state(State.INTERCEPT)
		Order.COVER:
			formation_scale = 0.65
			engage_radius = 2300.0
			if state == State.RETURN:
				_set_state(State.FORMATION)
		Order.RTB:
			var best: Vector3 = home
			var bd: float = INF
			for n in get_tree().get_nodes_in_group("airfield"):
				var af: Airfield = n as Airfield
				if af != null and af.team == ac.team:
					var d: float = Vector2(af.global_position.x - ac.global_position.x, af.global_position.z - ac.global_position.z).length()
					if d < bd:
						bd = d
						best = af.global_position
			home = best
			target = null
			_set_state(State.RETURN)
		_:
			if state == State.RETURN:
				_set_state(State.FORMATION)


## Does this pilot break off? Hurt past his own limit, or crippled (an engine out, a wing tip gone, on fire, the tail
## shot about). Pilots who press on only turn for home when the aircraft is nearly finished.
func _wants_home(hp_frac: float) -> bool:
	var dm: AircraftDamageModel = ac.damage_model
	var crippled: bool = ac.has_meta("on_fire") or (dm != null and (dm.engines_out_frac() > 0.0 or int(dm.wing_lost["wing_l"]) > 0 or int(dm.wing_lost["wing_r"]) > 0))
	if _stubborn:
		return hp_frac < 0.1
	return hp_frac < _bail_hp or crippled


func _nearest_friendly_field() -> Airfield:
	var best: Airfield = null
	var bd: float = INF
	for n in ac.get_tree().get_nodes_in_group("airfield"):
		var af: Airfield = n as Airfield
		if af != null and af.team == ac.team:
			var d: float = Vector2(af.global_position.x - ac.global_position.x, af.global_position.z - ac.global_position.z).length()
			if d < bd:
				bd = d
				best = af
	return best


## A wingman of the player's side says what he is going to do about it.
func _announce(going_home: bool) -> void:
	if role != Role.WINGMAN or ac.team != GameState.player_side:
		return
	var lines: Array = ["Hit, I'm breaking off. Heading for home.", "I'm in a bad way, leader. Going home.", "Engine's gone, I'm turning back."] if going_home \
		else ["Took some hits but I'm still with you.", "I can still fight. Staying on your wing.", "Scratched, not beaten. Press on."]
	Radio.say("Wingman", lines[randi() % lines.size()], Radio.Kind.FRIENDLY, 0.0)


func get_target() -> Aircraft:
	return target if is_instance_valid(target) else null


func _set_state(s: int) -> void:
	if s != state:
		if state == State.TAKEOFF and ac != null:
			ac.invulnerable = false
		state = s
		state_changed.emit(s)


func _on_damaged(_a: Aircraft, amount: float, health: float) -> void:
	if role != Role.FIGHTER and role != Role.WINGMAN:
		return
	if state == State.TAKEOFF or state == State.LAND:
		return          # a hit on the runway must not turn the take-off roll into airborne evasion
	if _evade_cd <= 0.0 and state != State.RETURN and randf() < 0.25 + 0.5 * (1.0 - aggression) + minf(amount * 0.01, 0.2):
		_begin_evade()


# ------------------------------------------------------------------ main loop

func _process(delta: float) -> void:
	if ac == null or not is_instance_valid(ac):
		queue_free()
		return
	if not enabled:
		return
	if ac.state != Aircraft.State.ALIVE:
		ac.cmd_fire = false
		return
	# Pilots make mistakes: now and then a low, fast, nose-down aircraft misjudges the pull-out. While the
	# mistake lasts the ground-avoidance is skipped, so the occasional AI flies into the deck.
	if _mistake_cd > 0.0:
		_mistake_cd -= delta
	elif ac.altitude_agl < 300.0 and ac.velocity.y < -7.0 and state != State.TAKEOFF and state != State.LAND:
		if randf() < 0.035 * delta:
			_mistake_t = 1.6
			_mistake_cd = randf_range(50.0, 180.0)
	if _mistake_t > 0.0:
		_mistake_t -= delta
	if _energy_cd > 0.0:
		_energy_cd -= delta
	delta = minf(delta, 0.05)
	if ac.auto_level:
		ac.auto_level = false
	if ac.ammo < 40:
		ac.ammo = ac.stats.ammo
	_evade_cd = maxf(_evade_cd - delta, 0.0)
	_man_cd = maxf(_man_cd - delta, 0.0)
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = 0.28 + randf() * 0.14
		_think()
	_aim_err_t -= delta
	if _aim_err_t <= 0.0:
		_aim_err_t = 0.3 + randf() * 0.3
		_aim_err = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))

	_thr = cruise_throttle
	_boost = false
	_pull = 1.0
	match state:
		State.PATROL:
			_dir = _dir_orbit(patrol_center, patrol_radius, patrol_alt)
		State.INTERCEPT:
			if _man != Man.NONE:
				_run_maneuver(delta)
			else:
				_run_pursuit(delta, false)
		State.ATTACK:
			if _man != Man.NONE:
				_run_maneuver(delta)
			else:
				_run_pursuit(delta, true)
		State.EVADE:
			if _man != Man.NONE:
				_run_maneuver(delta)
			else:
				_run_evade(delta)
		State.RETURN:
			var hp: Vector3 = home + Vector3.UP * 300.0
			if _flat_dist(hp) < 3200.0 and land_af == null and role != Role.BOMBER_LEADER and not ac.has_meta("on_fire"):
				var af: Airfield = _nearest_friendly_field()
				if af != null and ac.altitude_agl > 120.0:
					begin_landing(af)          # made it back: join the circuit and land
					return
			if _flat_dist(hp) < 700.0:
				_dir = _dir_orbit(home, 1500.0, hp.y)
			else:
				_dir = _dir_to(hp)
			_thr = 0.9
		State.STRIKE:
			_run_strike(delta)
		State.FORMATION:
			_run_formation(delta)
		State.ROUTE:
			_run_route()
		State.TAKEOFF:
			if _run_takeoff(delta):
				return                      # still rolling: the controls are already set
		State.CLIMB_OUT:
			_run_climb_out()
		State.ENERGY:
			_run_energy_climb(delta)
		State.LAND:
			_run_land(delta)

	if bomb_armed:
		_bomb_logic(delta)
	if state != State.TAKEOFF and state != State.LAND:
		_dir = _guard_ground(_dir)
		_limit_energy()
	_avoid_collisions(delta)
	if role == Role.BOMBER_LEADER and state != State.TAKEOFF:
		_dir = _bomber_weave(_dir, delta)      # weave the formation when a fighter presses an attack
	if role == Role.WINGMAN or role == Role.FIGHTER:
		var bk: float = bank_of(ac)
		_roll_rate = angle_difference(_last_bank, bk) / maxf(delta, 0.001)
		_last_bank = bk
		if state == State.FORMATION or state == State.ROUTE or state == State.PATROL:
			roll_activity += absf(_roll_rate) * delta
			roll_time += delta
	if (role == Role.BOMBER_LEADER or role == Role.BOMBER_FOLLOWER) and state != State.TAKEOFF:
		_steer_heavy(_dir)
	elif _cruise_ok():
		_steer_cruise(_dir)
	else:
		_steer(_dir)
	if role == Role.WINGMAN and state == State.FORMATION:
		# hold station smoothly: a wingman rolling to catch up looks like a barrel roll, so cap the roll
		ac.cmd_roll = clampf(ac.cmd_roll, -0.35, 0.35)
		ac.cmd_pitch = clampf(ac.cmd_pitch, -0.5, 0.6)
	if state == State.TAKEOFF:
		ac.cmd_pitch = clampf(ac.cmd_pitch, -0.3, 0.38)   # a gentle climb-out, no snap pull-ups near the stall
	if role == Role.BOMBER_LEADER or role == Role.BOMBER_FOLLOWER:
		var vmax: float = minf(ac.stats.max_speed * 0.85, BOMBER_CRUISE_CAP) * bomber_speed_k * (1.0 if role == Role.BOMBER_LEADER else 1.15)
		_thr = clampf(_thr - maxf(ac.speed - vmax, 0.0) * 0.08, 0.4, 1.0)      # never so little power that the bomber sinks      # followers may run a little faster to hold station
		if ac.velocity.y < -1.5 and _route_alt_err > -50.0:
			_thr = clampf(maxf(_thr, 0.85), 0.85, 1.0)	# altitude-hold: thin air at escort alt needs power, not the cruise floor
	# engine heat (Options > Realism): back off the power / boost before the engine cooks, resume once it has cooled
	if GameState.engine_heat_on:
		if ac.engine_heat > 0.88:
			_cooling = true
		elif ac.engine_heat < 0.6:
			_cooling = false
		if _cooling:
			_thr = minf(_thr, 0.62)
			_boost = false
		elif ac.engine_heat > 0.7:
			_boost = false
	ac.throttle_target = _thr
	ac.cmd_boost = _boost
	_ground_strike(delta)
	_fire_control(delta)


var strike_target: Node3D                 # planned strike (State.STRIKE): the ship or ground target to attack
var _strike_salvos: int = 0               # rocket salvos fired on this strike
var _strike_t: float = 0.0                # time limit on a strike, so a pilot never circles a target for ever
var _route_bomb: Vector3 = Vector3.ZERO   # a bomber's own bomb-run point, put back when a strike ends


## Give the pilot a planned strike on a ship or ground target. Fighters dive on it and fire rockets; bombers run
## in and release bombs on it. Afterwards they return to patrol (fighters) or their route (bombers).
func set_strike(t: Node3D) -> void:
	strike_target = t
	_strike_salvos = 0
	_strike_t = 90.0
	if role == Role.BOMBER_LEADER or role == Role.BOMBER_FOLLOWER:
		_route_bomb = bomb_target
	_set_state(State.STRIKE)


## The nearest enemy ship or ground target between 600 m and max_d, or null.
func _pick_strike_target(max_d: float) -> Node3D:
	if ac.stats.rockets <= 0 or _salvos >= ac.stats.rockets / 2:
		return null
	var best: Node3D = null
	var best_d: float = max_d
	for n in ac.get_tree().get_nodes_in_group("damageable"):
		var t := n as Node3D
		if t == null or not (t.is_in_group("ship") or t.is_in_group("ground_target")):
			continue
		var tt: Variant = t.get("team")
		if tt == null or tt == ac.team:
			continue
		var d: float = ac.global_position.distance_to(t.global_position)
		if d < 600.0 or d > best_d:
			continue
		best = t
		best_d = d
	return best


func _run_strike(delta: float) -> void:
	_strike_t -= delta
	var tg: Node3D = strike_target
	var dead: bool = tg == null or not is_instance_valid(tg) or (tg.has_method("is_destroyed") and tg.is_destroyed())
	if dead or _strike_t <= 0.0:
		_end_strike()
		return
	var to: Vector3 = tg.global_position - ac.global_position
	var flat: float = Vector2(to.x, to.z).length()
	_thr = 0.9
	if role == Role.BOMBER_LEADER or role == Role.BOMBER_FOLLOWER:
		if ac.bombs <= 0 or flat < 200.0:
			_end_strike()
			return
		bomb_target = tg.global_position
		_bomb_logic(delta)          # releases only when the target lies on the bomb-run line
		_dir = Vector3(to.x, 0.0, to.z).normalized()
		return
	# fighter: a shallow dive on the target, rockets once the nose is on it
	if flat < 200.0 or _strike_salvos >= 2 or _salvos >= ac.stats.rockets / 2:
		_end_strike()
		return
	_dir = to.normalized()
	if flat < 900.0 and _strike_cd <= 0.0 and ac.get_forward().angle_to(to) < 0.12:
		var mode: int = ac.weapon_mode
		ac.weapon_mode = 1
		ac.bomb_requested.emit(ac)
		ac.weapon_mode = mode
		_salvos += 1
		_strike_salvos += 1
		_strike_cd = 1.5


func _end_strike() -> void:
	strike_target = null
	_strike_salvos = 0
	if role == Role.BOMBER_LEADER or role == Role.BOMBER_FOLLOWER:
		bomb_target = _route_bomb
	_set_state(State.ROUTE if role == Role.BOMBER_LEADER else (State.FORMATION if role == Role.BOMBER_FOLLOWER else State.PATROL))


## Ground and naval attacks: an AI aircraft with rockets, or a bomber with bombs, takes an enemy ship or ground target
## that lies close ahead on its track. Fighters do not turn aside for these targets, so this is opportunistic: it
## fires at what comes up on the route, it does not plan a strike.
func _ground_strike(delta: float) -> void:
	_strike_cd = maxf(_strike_cd - delta, 0.0)
	if _strike_cd > 0.0 or ac.state != Aircraft.State.ALIVE:
		return
	if state != State.PATROL and state != State.FORMATION and state != State.ROUTE:
		return
	var fwd: Vector3 = ac.get_forward()
	var best: Node3D = null
	var best_d: float = GROUND_STRIKE_RANGE
	for n in ac.get_tree().get_nodes_in_group("damageable"):
		var t := n as Node3D
		if t == null or t == ac or not (t.is_in_group("ship") or t.is_in_group("ground_target")):
			continue
		var tt: Variant = t.get("team")
		if tt == null or tt == ac.team:
			continue
		var rel: Vector3 = t.global_position - ac.global_position
		var d: float = rel.length()
		if d < 120.0 or d > best_d:
			continue
		var rad: float = float(t.get("hit_radius"))
		if fwd.angle_to(rel) > 0.1 + rad / d:
			continue
		best = t
		best_d = d
	if best == null:
		return
	if role == Role.BOMBER_LEADER or role == Role.BOMBER_FOLLOWER:
		if ac.bombs <= 0:
			return
		var saved: Vector3 = bomb_target
		var before: int = ac.bombs
		bomb_target = best.global_position
		_bomb_logic(delta)      # releases only when the target lies on the bomb-run line
		bomb_target = saved
		if ac.bombs < before:
			_strike_cd = 6.0
		return
	if ac.stats.rockets <= 0 or _salvos >= ac.stats.rockets / 2:
		return
	var mode: int = ac.weapon_mode
	ac.weapon_mode = 1
	ac.bomb_requested.emit(ac)
	ac.weapon_mode = mode
	_salvos += 1
	_strike_cd = 4.0


# ------------------------------------------------------------------ decisions

func _think() -> void:
	_vis = _weather_visibility()
	if state == State.TAKEOFF or state == State.LAND:
		return
	if role == Role.BOMBER_LEADER or role == Role.BOMBER_FOLLOWER:
		return
	if state == State.STRIKE:
		return
	# a fighter with rockets on patrol now and then picks a ship or ground target in range and goes for it
	if role == Role.FIGHTER and state == State.PATROL and not ac.player_controlled and _strike_cd <= 0.0 and randf() < 0.12:
		var pick: Node3D = _pick_strike_target(3200.0)
		if pick != null:
			set_strike(pick)
			return
	if role == Role.WINGMAN:
		if order == Order.RTB:
			if state != State.RETURN:
				_set_state(State.RETURN)
			return
		if order == Order.ATTACK:
			if is_instance_valid(order_target) and order_target.state == Aircraft.State.ALIVE:
				target = order_target
				var dd: float = ac.global_position.distance_to(target.global_position)
				if _evade_cd <= 0.0 and _is_threatened() and randf() < 0.25:
					_begin_evade()
				elif state != State.EVADE:
					_set_state(State.ATTACK if dd < ATTACK_RANGE else State.INTERCEPT)
				return
			order = Order.FORM          # target destroyed (or gone): back to formation
			order_target = null
			engage_radius = 4200.0
	var hp_frac: float = ac.health / maxf(ac.stats.max_health, 1.0)
	if (role == Role.FIGHTER or role == Role.WINGMAN) and state != State.RETURN and _wants_home(hp_frac):
		_set_state(State.RETURN)      # badly damaged: break off and run for home
		target = null
		order = Order.RTB
		_announce(true)
		return
	if (role == Role.FIGHTER or role == Role.WINGMAN) and not _decided and hp_frac < _bail_hp + 0.18:
		_decided = true               # hurt but staying in the fight
		_announce(false)
	if state == State.RETURN:
		return
	var dr: float = detect_range * clampf(sqrt(_vis), 0.35, 1.0)
	if not _target_valid(target, dr * 1.4):
		target = _find_target(dr)
	elif randf() < 0.3:
		var alt: Aircraft = _find_target(dr)
		if alt != null and alt != target and alt.global_position.distance_to(ac.global_position) < 0.5 * target.global_position.distance_to(ac.global_position):
			target = alt
	if state == State.EVADE:
		return
	if target == null:
		if role == Role.WINGMAN and is_instance_valid(leader):
			_set_state(State.FORMATION)
		elif state == State.ROUTE:
			pass
		else:
			_set_state(State.PATROL)
		return
	if _evade_cd <= 0.0 and _is_threatened() and randf() < 0.35 + 0.5 * (1.0 - aggression):
		_begin_evade()
		return
	# Energy fighters: if they are not already above the target, break off and climb for a height
	# advantage, then come back down on it (boom and zoom) instead of turning with it.
	if energy_fighter and _energy_cd <= 0.0 and ac.global_position.y - target.global_position.y < 240.0:
		_energy_cd = randf_range(20.0, 55.0)
		_energy_t = randf_range(4.0, 8.0)
		_set_state(State.ENERGY)
		return
	var d: float = ac.global_position.distance_to(target.global_position)
	_set_state(State.ATTACK if d < ATTACK_RANGE else State.INTERCEPT)
	if _man == Man.NONE and _man_cd <= 0.0:
		_bfm_select()


## Terrain line of sight: sample the heightfield between us and `o`; if the ground
## rises to within 60m of the sight ray the target is hidden behind terrain.
func _has_los(o: Aircraft) -> bool:
	var p1: Vector3 = ac.global_position
	var p2: Vector3 = o.global_position
	for i in 3:
		var t: float = float(i + 1) / 4.0
		var p: Vector3 = p1.lerp(p2, t)
		var ray_y: float = lerpf(p1.y, p2.y, t)
		if _terrain_h(p) > ray_y - 60.0:
			return false
	return true


## The toon cloud field (WeatherManager autoload child), for cloud occlusion.
func _cloud_field() -> CloudField:
	var wm: Node = get_node_or_null("/root/WeatherManager")
	if wm == null:
		return null
	return wm.get("cloud_field") as CloudField


func _target_valid(t: Aircraft, max_range: float) -> bool:
	if t == null or not is_instance_valid(t) or t.state != Aircraft.State.ALIVE:
		return false
	if t.global_position.distance_to(ac.global_position) > max_range:
		return false
	var cf: CloudField = _cloud_field()
	if cf != null and cf.blocks_los(ac.global_position, t.global_position):
		return false
	if role == Role.WINGMAN and is_instance_valid(leader) and t != order_target and t.global_position.distance_to(leader.global_position) > engage_radius:
		return false
	return true


func _find_target(max_range: float) -> Aircraft:
	var best: Aircraft = null
	var best_score: float = INF
	var pos: Vector3 = ac.global_position
	var cf: CloudField = _cloud_field()
	for n in get_tree().get_nodes_in_group("aircraft"):
		var o: Aircraft = n as Aircraft
		if o == null or o == ac or o.state != Aircraft.State.ALIVE or o.team == ac.team or o.team == "Neutral":
			continue
		var d: float = o.global_position.distance_to(pos)
		if d > max_range:
			continue
		if not _has_los(o):
			continue
		if cf != null and cf.blocks_los(ac.global_position, o.global_position):
			continue
		if role == Role.WINGMAN and is_instance_valid(leader) and o.global_position.distance_to(leader.global_position) > engage_radius:
			continue
		var score: float = d
		if o.player_controlled:
			score *= 0.6 + 0.4 * (1.0 - aggression)
		if score < best_score:
			best_score = score
			best = o
	return best


func _is_threatened() -> bool:
	var pos: Vector3 = ac.global_position
	for n in get_tree().get_nodes_in_group("aircraft"):
		var o: Aircraft = n as Aircraft
		if o == null or o == ac or o.state != Aircraft.State.ALIVE or o.team == ac.team or o.team == "Neutral":
			continue
		var rel: Vector3 = pos - o.global_position
		var d: float = rel.length()
		if d < 650.0 and d > 1.0 and o.get_forward().dot(rel / d) > 0.93 and (o.cmd_fire or d < 220.0):
			_threat = o
			return true
	return false


func _begin_evade() -> void:
	_evade_t = randf_range(2.2, 3.8)
	_jink_t = 0.0
	_set_state(State.EVADE)
	_evade_cd = _evade_t + 3.0 + 3.0 * aggression
	_pick_defensive()


# ------------------------------------------------------------------ behaviours

func _run_pursuit(delta: float, attacking: bool) -> void:
	if target == null or not is_instance_valid(target):
		_dir = _dir_orbit(patrol_center, patrol_radius, patrol_alt)
		return
	_seen_t -= delta
	if _seen_t <= 0.0:
		_seen_t = reaction
		_seen_tp = target.global_position
		_seen_tv = target.velocity
	var pos: Vector3 = ac.global_position
	var rel: Vector3 = _seen_tp - pos
	var d: float = rel.length()
	var t: float = clampf(d / AIGun.BULLET_SPEED, 0.0, 1.5)
	var aim: Vector3 = _seen_tp + (_seen_tv - ac.velocity) * t
	if not attacking:
		# plain lead pursuit while closing in
		aim = _seen_tp + _seen_tv * clampf(d / maxf(ac.speed + 150.0, 100.0), 0.0, 2.0) * 0.8
	var err_ang: float = (1.0 - clampf(accuracy * _weather_acc(), 0.1, 1.0)) * 0.045 + 0.003
	aim += _aim_err * d * err_ang
	if attacking and d < 700.0 and (ac.velocity - target.velocity).dot(rel / maxf(d, 1.0)) > 32.0:
		aim -= _seen_tv * 0.4          # lag pursuit: fly outside the target's turn so the closure does not become an overshoot
	_dir = (aim - pos).normalized()
	# throttle: avoid overshooting
	var closing: float = (ac.velocity - target.velocity).dot(rel / maxf(d, 1.0))
	if d < 450.0 and closing > 35.0:
		_thr = clampf(0.5 + (d - 150.0) / 600.0, 0.35, 1.0)
	else:
		_thr = 1.0
	if not attacking and d > 1800.0 and ac.boost_energy > 0.5:
		_boost = true
	# overshoot / wide angle at close range: slow down so the turn radius shrinks
	var off_ang: float = ac.get_forward().angle_to(rel)
	if d < 750.0 and off_ang > 0.9:
		_thr = 0.4
	if attacking and d < 700.0 and off_ang > 0.5:
		_dir = (_seen_tp + _aim_err * d * err_ang - pos).normalized()   # pure pursuit when turning in
	# overshot / too close: break away and re-engage
	if d < 110.0 and ac.get_forward().dot(rel / maxf(d, 1.0)) < 0.2:
		_dir = (ac.get_forward() + Vector3.UP * 0.4 + ac.global_transform.basis.x * _jink_sign * 0.6).normalized()


func _run_evade(delta: float) -> void:
	_evade_t -= delta
	_jink_t -= delta
	if _jink_t <= 0.0:
		_jink_t = randf_range(0.5, 0.9)
		_jink_sign = -_jink_sign if randf() < 0.7 else _jink_sign
		_jink_up = randf_range(-0.6, 0.7)
	var b: Basis = ac.global_transform.basis
	_dir = (-b.z * 0.45 + b.x * _jink_sign * 0.9 + Vector3.UP * _jink_up).normalized()
	_thr = 1.0
	_boost = ac.boost_energy > 0.3
	if _evade_t <= 0.0:
		_set_state(State.INTERCEPT if target != null else State.PATROL)


func _run_formation(delta: float) -> void:
	if not is_instance_valid(leader):
		_dir = _dir_orbit(patrol_center, patrol_radius, patrol_alt)
		return
	var lf: Vector3 = -leader.global_transform.basis.z
	var lflat: Vector3 = Vector3(lf.x, 0.0, lf.z)
	if lflat.length() < 0.01:
		lflat = Vector3.FORWARD
	lflat = lflat.normalized()
	var yaw_basis: Basis = Basis.looking_at(lflat, Vector3.UP)
	var slot: Vector3 = leader.global_position + yaw_basis * (formation_offset * formation_scale)
	var lvel: Vector3 = Vector3.ZERO
	var lthr: float = 0.7
	if leader is Aircraft:
		lvel = (leader as Aircraft).velocity
		lthr = (leader as Aircraft).throttle
	var rel: Vector3 = slot - ac.global_position
	var d: float = rel.length()
	_form_d = d
	var want: Vector3
	if d < 70.0:
		want = (lf * 400.0 + rel * 0.6).normalized() if rel.length() > 1.0 else lf
	else:
		want = (slot + lvel * 0.5 - ac.global_position).normalized()
	# damp the commanded direction and throttle: a wingman rides the slot instead of twitching around it
	# (the aircraft's own rough-air buffeting is untouched)
	_form_dir = want if _form_dir.length_squared() < 0.01 else _form_dir.lerp(want, clampf(delta * 2.2, 0.0, 1.0)).normalized()
	_dir = _form_dir
	var ahead: float = rel.dot(lflat)
	_form_thr = (lthr + ahead * 0.003) if _form_thr <= 0.0 else lerpf(_form_thr, lthr + ahead * 0.003, clampf(delta * 1.6, 0.0, 1.0))
	_thr = clampf(_form_thr, 0.15, 1.0)
	if role == Role.BOMBER_FOLLOWER:
		_route_alt_err = rel.y
		_dir = _shallow(_dir)
		if rel.y > 40.0:
			_thr = maxf(_thr, 0.9)
	if ahead > 450.0 and ac.boost_energy > 0.4:
		_boost = true


func _run_route() -> void:
	if waypoints.is_empty():
		_dir = _dir_orbit(patrol_center, patrol_radius, patrol_alt)
		return
	var wp: Vector3 = waypoints[mini(wp_index, waypoints.size() - 1)]
	if _flat_dist(wp) < (1000.0 if role == Role.BOMBER_LEADER else 450.0):   # heavy bombers cannot turn tightly onto a waypoint
		if wp_index < waypoints.size() - 1:
			wp_index += 1
		elif wp_index == waypoints.size() - 1:
			wp_index += 1
			route_finished.emit()
		wp = waypoints[mini(wp_index, waypoints.size() - 1)]
	if wp_index >= waypoints.size():
		_dir = _dir_orbit(wp, 1800.0, wp.y)
	else:
		_dir = _dir_to(wp)
	if role == Role.BOMBER_LEADER or role == Role.BOMBER_FOLLOWER:
		_route_alt_err = wp.y - ac.global_position.y
		_dir.y += clampf(_route_alt_err * 0.0008, -0.08, 0.10)
		_dir = _dir.normalized()
	# bombers climb gently: a steep climb at bomber power bleeds the speed straight into the stall
	_dir = _shallow(_dir)
	if role == Role.BOMBER_LEADER and wp.y - ac.global_position.y > 120.0:
		_thr = 0.92


# ------------------------------------------------------------------ basic fighter manoeuvres

func _start_man(m: int, length: float, side: float = 0.0) -> void:
	_man = m
	_man_t = 0.0
	_man_phase = 0
	_man_len = length
	_man_side = side if side != 0.0 else (1.0 if randf() < 0.5 else -1.0)
	var f: Vector3 = ac.get_forward()
	var flat: Vector3 = Vector3(f.x, 0.0, f.z)
	_man_dir0 = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	var nm: String = MAN_NAMES[m]
	bfm_counts[nm] = int(bfm_counts.get(nm, 0)) + 1
	if OS.get_cmdline_user_args().has("--bfm-debug"):
		print("BFM %s flies %s (%.1fs)" % [ac.name, nm, length])


func _end_man() -> void:
	_man = Man.NONE
	_man_cd = randf_range(1.8, 3.2)


## Offence / neutral: pick a manoeuvre from the geometry (range, angle off, aspect, closure, height and energy).
func _bfm_select() -> void:
	if target == null or not is_instance_valid(target):
		return
	var rel: Vector3 = target.global_position - ac.global_position
	var d: float = maxf(rel.length(), 1.0)
	var los: Vector3 = rel / d
	var ata: float = ac.get_forward().angle_to(los)                # my nose off the target
	var aa: float = target.get_forward().angle_to(los)             # 0 = I am on its tail
	var tata: float = target.get_forward().angle_to(-los)          # its nose off me: small = it can shoot me
	var closure: float = (ac.velocity - target.velocity).dot(los)
	var dh: float = target.global_position.y - ac.global_position.y
	var spd: float = ac.speed
	var stall: float = ac.stats.stall_speed
	var agl: float = ac.altitude_agl
	# 1. defence: the target has its nose on me
	if tata < 0.5 and d < 750.0 and ata > 0.5:
		_threat = target
		_pick_defensive()
		return
	# 2. a head-on pass or overshoot left the target behind me: reverse the fight
	if ata > 2.1 and d < 1000.0:
		var r: float = randf()
		if agl > 800.0 and spd > stall * 1.9 and r < 0.35:
			_start_man(Man.WINGOVER, 4.4)
		elif dh < -150.0 and agl > 1200.0 and r < 0.6:
			_start_man(Man.SPLIT_S, 3.6)
		elif spd > stall * 1.8 and agl > 700.0 and r < 0.8:
			_start_man(Man.IMMELMANN, 5.6)
		else:
			_start_man(Man.BREAK, 2.6)
		return
	# 3. offence with the target ahead
	if ata < 1.15 and d < 1700.0:
		if dh < -220.0 and spd >= target.speed * 0.9 and d > 400.0 and aa < 2.2:
			_start_man(Man.BOOM_ZOOM, 7.0)               # high side: dive on the rear quarter, shoot, zoom away
		elif closure > 30.0 and d < 600.0 and ata > 0.25 and agl > 350.0:
			_start_man(Man.HIGH_YOYO, 2.5)               # too fast: climb out of the turn plane to stop the overshoot
		elif spd < target.speed * 0.92 and d > 500.0 and ata > 0.35 and agl > 450.0:
			_start_man(Man.LOW_YOYO, 2.1)                # too slow: trade height for speed and cut the corner
		elif ata > 0.75 and aa > 0.9 and d < 900.0 and agl > 400.0:
			_start_man(Man.BARREL, 2.7)                  # target broke away: barrel roll to keep the nose on it


## Defence against whoever is on my tail (_threat): break, barrel roll, scissors, extension or spiral.
func _pick_defensive() -> void:
	if _man != Man.NONE:
		return
	if _threat == null or not is_instance_valid(_threat):
		return
	var rel: Vector3 = _threat.global_position - ac.global_position
	var d: float = maxf(rel.length(), 1.0)
	var tata: float = _threat.get_forward().angle_to(-rel / d)
	var closure: float = (ac.velocity - _threat.velocity).dot(rel / d) * -1.0   # + = it is closing on me
	var spd: float = ac.speed
	var stall: float = ac.stats.stall_speed
	var agl: float = ac.altitude_agl
	if spd < stall * 1.55 and agl > 450.0:
		_start_man(Man.SPIRAL, 4.6)                   # no energy left: spiral down and let gravity pay
	elif d < 280.0 and tata < 0.45:
		if spd > stall * 1.9 and agl > 400.0 and randf() < 0.55:
			_start_man(Man.DEF_BARREL, 2.7)           # throttle back and barrel roll: it overshoots
		elif closure < 25.0 and spd < stall * 2.3:
			_start_man(Man.SCISSORS, 7.0)             # both slow and close: scissors
		else:
			_start_man(Man.BREAK, 2.6)
	elif d > 650.0 and closure < 0.0 and spd > stall * 1.7:
		_start_man(Man.UNLOAD, 3.6)                   # it is falling behind: unload and extend away
	else:
		var r2: float = randf()
		if d < 480.0 and tata < 0.6 and spd > stall * 1.8 and agl > 450.0 and r2 < 0.3:
			_start_man(Man.DEF_BARREL, 2.7)
		elif spd > stall * 1.8 and r2 < 0.5 and closure < 40.0:
			_start_man(Man.UNLOAD, 3.6)
		else:
			_start_man(Man.BREAK, 2.6)                # hard turn across its flight path
	_evade_t = _man_len + 0.4


func _run_maneuver(delta: float) -> void:
	_man_t += delta
	var f: Vector3 = ac.get_forward()
	var flat: Vector3 = Vector3(f.x, 0.0, f.z)
	flat = flat.normalized() if flat.length() > 0.01 else _man_dir0
	var right: Vector3 = Vector3(-flat.z, 0.0, flat.x)
	var right0: Vector3 = Vector3(-_man_dir0.z, 0.0, _man_dir0.x)
	var los: Vector3 = flat
	var tvalid: bool = target != null and is_instance_valid(target) and target.state == Aircraft.State.ALIVE
	if tvalid:
		los = (target.global_position - ac.global_position).normalized()
	_thr = cruise_throttle
	var t: float = _man_t
	var phi: float = clampf(t / maxf(_man_len, 0.1), 0.0, 1.0) * TAU
	var done: bool = t >= _man_len
	match _man:
		Man.HIGH_YOYO:
			if t < 1.3:
				_dir = (Vector3.UP * 0.8 + los * 0.5).normalized()
				_thr = 0.85
			else:
				_dir = los
				_thr = 0.95
		Man.LOW_YOYO:
			_dir = (los * 0.75 + Vector3.DOWN * 0.5).normalized()
			_thr = 1.0
		Man.BOOM_ZOOM:
			if t < _man_len and ((tvalid and ac.get_forward().angle_to(los) < 1.2 and ac.global_position.distance_to(target.global_position) > 230.0) or _man_dir0 == Vector3.ZERO) and _man_t < 5.0:
				_dir = los                              # dive onto the rear quarter
				_thr = 1.0
			else:
				_dir = (flat * 0.55 + Vector3.UP * 0.85).normalized()   # zoom climb back up
				_thr = 1.0
				if ac.speed < ac.stats.stall_speed * 1.7:
					done = true
		Man.BARREL:
			_dir = (los * 0.6 + Vector3.UP * sin(phi) * 0.8 + right * _man_side * (1.0 - cos(phi)) * 0.5).normalized()
			_thr = 0.9
		Man.IMMELMANN:
			if _man_t < 3.4 and rad_to_deg(ac._pitch_angle()) < 72.0 and _man_len > 0.0 and _man_dir0 != Vector3.ZERO and _man_phase == 0:
				_dir = Vector3(_man_dir0.x * 0.25, 1.0, _man_dir0.z * 0.25).normalized()
				_thr = 1.0
			else:
				_man_phase = 1
				_dir = (-_man_dir0 * 0.9 + Vector3.UP * 0.15).normalized()      # roll upright heading the other way
				_thr = 0.9
		Man.SPLIT_S:
			_dir = (-_man_dir0 * 0.5 + Vector3.DOWN * 0.9).normalized()
			_thr = 0.5
		Man.WINGOVER:
			if t < 1.3:
				_dir = (Vector3.UP * 0.9 + _man_dir0 * 0.3).normalized()
				_thr = 1.0
			elif t < 2.5:
				_dir = (right0 * _man_side * 0.9 + Vector3.UP * 0.15).normalized()
				_thr = 0.8
			else:
				_dir = (-_man_dir0 * 0.7 + Vector3.DOWN * 0.55).normalized()
				_thr = 0.9
		Man.BREAK:
			var base: Vector3 = right * _man_side
			if _threat != null and is_instance_valid(_threat):
				var tf: Vector3 = _threat.get_forward()
				var tflat := Vector3(tf.x, 0.0, tf.z)
				if tflat.length() > 0.01:
					tflat = tflat.normalized()
					base = Vector3(-tflat.z, 0.0, tflat.x) * _man_side   # across the attacker's flight path
				if t > 0.8 and ac.global_position.distance_to(_threat.global_position) > 1000.0:
					done = true
			_dir = (base * 0.95 + Vector3.UP * 0.1 * _man_side).normalized()
			_thr = 1.0
			_pull = 1.0
		Man.UNLOAD:
			_dir = (flat * 0.9 + Vector3.DOWN * 0.3).normalized()
			_thr = 1.0
			_pull = 0.3
			_boost = ac.boost_energy > 0.4
		Man.SCISSORS:
			var sd: float = _man_side * (1.0 if int(t / 1.5) % 2 == 0 else -1.0)
			_dir = (right * sd * 0.9 + los * 0.25 + flat * 0.1).normalized()
			_thr = 0.35
		Man.DEF_BARREL:
			_dir = (flat * 0.35 + Vector3.UP * sin(phi) * 0.8 + right * _man_side * (1.0 - cos(phi)) * 0.6).normalized()
			_thr = 0.3
		Man.SPIRAL:
			var ang: float = t * 0.9 * _man_side
			_dir = (flat.rotated(Vector3.UP, ang) * 0.8 + Vector3.DOWN * 0.6).normalized()
			_thr = 0.4
	if done or ac.altitude_agl < 140.0:
		_end_man()


# ------------------------------------------------------------------ takeoff, landing, bombing

## Limit a heavy aircraft's climb / dive angle (about +4 / -7 degrees).
func _shallow(d: Vector3) -> Vector3:
	var flat: float = Vector2(d.x, d.z).length()
	if flat < 0.001:
		return d
	var y: float = clampf(d.y / flat, -0.12, 0.07)
	return Vector3(d.x / flat, y, d.z / flat).normalized()


## Start a take-off roll from the current spot along `rdir`; `next_state` is entered once airborne and clear.
func begin_takeoff(rdir: Vector3, next_state: int) -> void:
	runway_dir = Vector3(rdir.x, 0.0, rdir.z).normalized()
	_airborne_t = 0.0
	ac.invulnerable = true
	after_takeoff = next_state
	_set_state(State.TAKEOFF)


## Fly the circuit and land at `af`; the aircraft is removed on touchdown (landed_ai is emitted first).
func begin_landing(af: Airfield) -> void:
	land_af = af
	target = null
	bomb_armed = false
	_set_state(State.LAND)


## Energy fighting: extend away and climb to gain height on the target, then re-engage from above.
func _run_energy_climb(delta: float) -> void:
	_energy_t -= delta
	_thr = 1.0
	var away: Vector3 = -ac.get_forward()
	var want_alt: float = ac.global_position.y + 400.0
	if target != null and is_instance_valid(target):
		var rel: Vector3 = target.global_position - ac.global_position
		var flat: Vector3 = Vector3(rel.x, 0.0, rel.z)
		if flat.length() > 1.0:
			away = -flat.normalized()             # extend away so we do not fly into its guns
		want_alt = maxf(target.global_position.y + 300.0, ac.global_position.y + 220.0)
	var climb: float = clampf((want_alt - ac.global_position.y) * 0.004, -0.15, 0.6)
	_dir = (Vector3(away.x, 0.0, away.z).normalized() + Vector3.UP * climb).normalized()
	if _boost_energy_ok():
		_boost = true
	if _energy_t <= 0.0:
		_set_state(State.INTERCEPT if target != null else State.PATROL)


func _boost_energy_ok() -> bool:
	return ac.boost_energy > 0.4


## Climb-out after take-off: circle the field (or the form-up point) gaining height, then hand over. This is
## what lets a bomber formation get up and together before it turns for the target.
func _run_climb_out() -> void:
	_thr = 0.95
	# aim at a point on the circuit only a little above us, so the climb stays a steady, gentle angle
	var aim_alt: float = minf(climb_alt, ac.global_position.y + 520.0)
	_dir = _dir_orbit(climb_center, climb_radius, aim_alt)
	if ac.global_position.y >= climb_alt - 90.0:
		_set_state(after_climb)
		climb_out_finished.emit()


## Start the climb-out circuit (see _run_climb_out). Callers set climb_center / climb_alt / after_climb first.
func begin_climb_out() -> void:
	_set_state(State.CLIMB_OUT)


## Returns true while the aircraft is still on the ground (controls set directly), false once airborne.
var _airborne_t: float = 0.0       # TAKEOFF: seconds since the wheels left the ground


func _run_takeoff(_delta: float) -> bool:
	var stall: float = ac.stats.stall_speed
	if ac.on_ground:
		var right: Vector3 = Vector3(ac.global_transform.basis.x.x, 0.0, ac.global_transform.basis.x.z).normalized()
		var steer: float = clampf(runway_dir.dot(right) * 5.0, -1.0, 1.0)
		ac.cmd_yaw = steer
		ac.cmd_roll = 0.0
		ac.cmd_pitch = 0.0
		ac.cmd_fire = false
		ac.throttle_target = 1.0
		ac.cmd_boost = false
		if ac.ground_airspeed() > stall * 1.12:
			ac.cmd_pitch = 0.3          # rotate with a margin over the stall, not at it
		return true
	# airborne: ALWAYS hold a positive climb angle along the runway heading, gear up, then hand over. A level
	# command while still below flying speed just lets the aircraft mush back down onto the runway, which is
	# why bombers appeared not to climb out after lifting off.
	var agl: float = ac.altitude_agl
	if ac.invulnerable and not ac.on_ground and agl > 50.0:
		ac.invulnerable = false
	_thr = 1.0
	# Just after lift-off the wings need a high angle of attack, so a nose pointed 10 degrees up does not climb at
	# all: the aircraft hovered a few metres off the runway at ~1.25x stall (heavy bombers, the Defiant, the P-38).
	# Stay nearly level in ground effect until there is speed in hand, then ease the climb angle in.
	var margin: float = clampf((ac.speed - stall * 1.25) / (stall * 0.45), 0.0, 1.0)
	var climb: float = lerpf(0.03, 0.18, margin)
	# A stall just after lift-off drops a wing into the runway: unload the wing (nose to the horizon) and keep it
	# straight until the airspeed is back, instead of holding the climb angle that caused it.
	if ac.stalled or ac.speed < stall * 1.08:
		climb = -0.04 if ac.stalled else 0.0
	_dir = (runway_dir + Vector3.UP * climb).normalized()
	# Gear up as soon as the aircraft is flying: the gear's drag is large and, left down until 35 m, it capped the
	# speed of the heavy bombers just above the stall so they never got that high.
	_airborne_t += _delta
	if ac.gear_down and (_airborne_t > 2.0 or agl > 35.0):
		ac.set_gear(false)
	if agl > 130.0 and ac.speed > stall * 1.25:
		_set_state(after_takeoff)
	return false


func _run_land(_delta: float) -> void:
	if land_af == null or not is_instance_valid(land_af):
		_set_state(State.PATROL)
		return
	var dir: Vector3 = WorldCoords.heading_to_dir(land_af.heading_deg)
	var thr: Vector3 = land_af.get_threshold_position()
	var right: Vector3 = Vector3(-dir.z, 0.0, dir.x)
	var rel: Vector3 = ac.global_position - thr
	var along: float = rel.dot(dir)
	var lat: float = rel.dot(right)
	var agl: float = ac.altitude_agl
	var stall: float = ac.stats.stall_speed
	if along < -5200.0 or (along < -1200.0 and absf(lat) > 1100.0):
		# join: fly to the initial approach fix on the extended centreline, descending to circuit height
		var fix: Vector3 = thr - dir * 5400.0 + right * clampf(lat, -1.0, 1.0) * 700.0
		fix.y = thr.y + 520.0
		_dir = _dir_to(fix)
		_thr = 0.62
		return
	# final approach: ~4 degree glide down the centreline, gear down, speed back
	if not ac.gear_down:
		ac.set_gear(true)
	var ahead: float = along + 900.0
	var aim: Vector3 = thr + dir * ahead
	aim += right * (-lat * 0.5)
	aim.y = thr.y + 8.0 + maxf(-ahead, 0.0) * 0.07
	_dir = (aim - ac.global_position).normalized()
	_thr = 0.2 if ac.speed > stall * 1.55 else 0.5
	_pull = 0.7
	if (along > -40.0 and agl < 30.0) or along > 500.0:
		landed_ai.emit(ac)
		ac.queue_free()


## Release bombs as the aircraft passes the point where they would fall onto bomb_target.
func _bomb_logic(delta: float) -> void:
	_bomb_cd -= delta
	if _bomb_cd > 0.0 or ac.bombs <= 0 or bomb_target == Vector3.ZERO:
		return
	var rel: Vector3 = bomb_target - ac.global_position
	var flat: Vector3 = Vector3(rel.x, 0.0, rel.z)
	var h: float = maxf(ac.global_position.y - bomb_target.y, 20.0)
	var lead: float = ac.speed * sqrt(2.0 * h / 30.0) * 0.92
	var fwd: Vector3 = ac.get_forward()
	var fflat: Vector3 = Vector3(fwd.x, 0.0, fwd.z).normalized()
	if flat.length() < lead + 60.0 and flat.length() > lead - 320.0 and fflat.dot(flat.normalized()) > 0.5:
		_bomb_cd = 0.22
		ac.bomb_requested.emit(ac)


# ------------------------------------------------------------------ steering

func _flat_dist(p: Vector3) -> float:
	var d: Vector3 = p - ac.global_position
	return Vector2(d.x, d.z).length()


func _dir_to(p: Vector3) -> Vector3:
	var d: Vector3 = p - ac.global_position
	if d.length() < 1.0:
		return -ac.global_transform.basis.z
	return d.normalized()


func _dir_orbit(center: Vector3, radius: float, alt: float) -> Vector3:
	var rel: Vector3 = ac.global_position - center
	rel.y = 0.0
	var aim: Vector3
	if rel.length() > radius * 2.5:
		aim = Vector3(center.x, alt, center.z)
	else:
		var ang: float = atan2(rel.z, rel.x) + 0.5 * _orbit_dir
		aim = Vector3(center.x + cos(ang) * radius, alt, center.z + sin(ang) * radius)
	return (aim - ac.global_position).normalized()


## Gentle steering for heavy bombers: banks of at most ~26 degrees, a steady climb / descent angle, no snap pulls.
func _steer_heavy(dir: Vector3) -> void:
	var f: Vector3 = ac.get_forward()
	var ff := Vector2(f.x, f.z)
	var dd := Vector2(dir.x, dir.z)
	var turn: float = 0.0
	if ff.length() > 0.01 and dd.length() > 0.01:
		ff = ff.normalized()
		dd = dd.normalized()
		turn = atan2(-(ff.y * dd.x - ff.x * dd.y), ff.dot(dd))       # + = target is to the right
	var bank_t: float = clampf(turn * 1.5, -deg_to_rad(26.0), deg_to_rad(26.0))
	var bank: float = ac._bank_angle()
	ac.cmd_roll = clampf((bank_t - bank) * 2.2, -0.6, 0.6)
	var flat: float = maxf(Vector2(dir.x, dir.z).length(), 0.001)
	# Desired flight-path angle from the route/dir, biased by the route altitude error, then the NOSE
	# attitude that achieves it: path angle PLUS the trim angle of attack. Pointing the nose straight at
	# the flight path (the old behaviour) leaves the wings at nearly zero angle of attack, so they carry
	# no weight and the bomber mushes down; auto-trim can only partly cover for it. Targeting the trim
	# attitude makes the wings carry the weight, and the altitude bias gives the path a real climb.
	var gamma: float = clampf(atan2(dir.y, flat), -deg_to_rad(9.0), deg_to_rad(9.0))
	var vs_want: float = clampf(_route_alt_err * 0.05, -12.0, 14.0)
	gamma += asin(clampf(vs_want / maxf(ac.speed, 20.0), -0.22, 0.22))
	var a_trim: float = WingModel.trim_alpha(ac.stats.stall_speed, ac.eas, ac.flap_deploy)
	var want_pitch: float = clampf(gamma + a_trim, -deg_to_rad(16.0), deg_to_rad(16.0))
	var pit_err: float = want_pitch - ac._pitch_angle()
	ac.cmd_pitch = clampf(pit_err * 3.0 + absf(sin(bank)) * 0.14, -0.4, 0.5)
	ac.cmd_yaw = 0.0


func _steer(dir: Vector3) -> void:
	var l: Vector3 = ac.global_transform.basis.inverse() * dir
	var fwd_c: float = clampf(-l.z, -1.0, 1.0)
	var err: float = acos(fwd_c)
	var fine_roll: float = clampf(l.x * 4.0, -1.0, 1.0)
	var fine_pitch: float = clampf(l.y * 5.0, -1.0, 1.0)
	var roll_err: float = 0.0
	if l.x * l.x + l.y * l.y > 0.0004:
		roll_err = atan2(l.x, l.y)
	var c_roll: float = clampf(roll_err * 2.2, -1.0, 1.0)
	var c_pitch: float = clampf(err * 3.0, 0.0, 1.0) * clampf(cos(roll_err) * 2.0, 0.0, 1.0)
	if l.y < -0.3 and fwd_c > 0.2:
		# target below and ahead: push the nose down instead of rolling over
		c_roll = clampf(l.x * 3.0, -1.0, 1.0)
		c_pitch = clampf(l.y * 3.0, -1.0, 0.0)
	var w: float = smoothstep(0.12, 0.45, err)
	var r: float = lerpf(fine_roll, c_roll, w)
	var p: float = lerpf(fine_pitch, c_pitch, w)
	var mc: float = max_cmd * turn_scale
	ac.cmd_roll = clampf(r, -mc, mc)
	ac.cmd_pitch = clampf(p * _pull, -mc, mc)
	ac.cmd_yaw = clampf(l.x * 1.5, -0.5, 0.5) * 0.5


## Steady flight for fighters that are not fighting: holding a formation slot (at any distance), flying a route,
## patrolling, climbing out or going home. Flies by bank ANGLE, not by pointing the nose: the nose-pointing
## controller (_steer) commands a roll RATE from the sideways error with nothing damping the bank it has built
## up, so straight flight wobbled +-30 degrees and a wingman catching up could end up in a slow continuous roll.
## Here the pilot wants a bank (the leader's bank near the slot, plus a correction toward where it is going,
## never more than 65 degrees) with the roll rate damped. Combat (intercept, attack, evade, manoeuvres) and
## ground-avoidance pull-ups keep _steer. --form-legacy flies the old way, for comparison.
static var FORM_LEGACY: bool = OS.get_cmdline_user_args().has("--form-legacy")
var _last_bank: float = 0.0
var _roll_rate: float = 0.0
var _form_d: float = 0.0              # distance to the formation slot (set in _run_formation)
var roll_activity: float = 0.0       # debug: accumulated |roll rate| * dt (rad) while cruising / in formation
var roll_time: float = 0.0


static func bank_of(n: Node3D) -> float:
	var b: Basis = n.global_transform.basis
	return atan2(-b.x.y, b.y.y)          # right wing down = positive


func _cruise_ok() -> bool:
	if FORM_LEGACY or _avoid_t > 0.0 or _man != Man.NONE:
		return false
	if role != Role.WINGMAN and role != Role.FIGHTER:
		return false
	return state == State.FORMATION or state == State.ROUTE or state == State.PATROL or state == State.CLIMB_OUT or state == State.RETURN


func _steer_cruise(dir: Vector3) -> void:
	# a sensible climb / dive angle: a slot or waypoint far above must not stand the fighter on its tail
	var flat_len: float = Vector2(dir.x, dir.z).length()
	if flat_len > 0.001:
		var slow: bool = ac.speed < ac.stats.stall_speed * 1.6
		var up_k: float = 0.18 if slow else 0.42
		dir = Vector3(dir.x, clampf(dir.y, -0.55 * flat_len, up_k * flat_len), dir.z).normalized()
	var b: Basis = ac.global_transform.basis
	var bank: float = _last_bank
	# sideways error, measured flat (independent of our own bank)
	var fwd: Vector3 = Vector3(-b.z.x, 0.0, -b.z.z)
	var want: Vector3 = Vector3(dir.x, 0.0, dir.z)
	var lat_ang: float = 0.0
	if fwd.length() > 0.01 and want.length() > 0.01:
		fwd = fwd.normalized()
		want = want.normalized()
		lat_ang = atan2(fwd.x * want.z - fwd.z * want.x, fwd.dot(want))   # +: wanted direction is to the right
	if state == State.FORMATION and is_instance_valid(leader) and absf(lat_ang) > deg_to_rad(100.0) and _form_d < 700.0:
		# overshot the slot (it is now behind us): never turn back across the leader; fly his heading and let
		# the throttle (already cut by _run_formation) drop us back into place
		var lf: Vector3 = -leader.global_transform.basis.z
		lf = Vector3(lf.x, 0.0, lf.z)
		if lf.length() > 0.01:
			lf = lf.normalized()
			dir = lf
			lat_ang = atan2(fwd.x * lf.z - fwd.z * lf.x, fwd.dot(lf))
	var lead_bank: float = 0.0
	var cap: float = deg_to_rad(60.0)
	if state == State.FORMATION and is_instance_valid(leader):
		# close to the slot: copy the leader's bank, with only small corrections; further out, turn harder to close
		var near: float = 1.0 - clampf((_form_d - 200.0) / 400.0, 0.0, 1.0)
		lead_bank = bank_of(leader) * 0.9 * near
		cap = deg_to_rad(lerpf(15.0, 60.0, clampf((_form_d - 150.0) / 750.0, 0.0, 1.0)))
		if absf(lead_bank) > deg_to_rad(10.0):
			cap = maxf(cap, deg_to_rad(30.0))
	# slow: a gentler turn, a steep bank at low speed just bleeds the speed away
	var bank_max: float = deg_to_rad(65.0) if ac.speed > ac.stats.stall_speed * 1.9 else deg_to_rad(42.0)
	var want_bank: float = clampf(lead_bank + clampf(lat_ang * 1.8, -cap, cap), -bank_max, bank_max)
	var r: float = clampf(angle_difference(bank, want_bank) * 1.6 - _roll_rate * 0.45, -0.5, 0.5)
	# pitch from the climb angle only: wanted elevation minus the nose's elevation, plus a little back pressure in
	# a bank. (Using the direction in our own frame mixed the sideways error into the pitch: with the nose up, a
	# slot off to one side read as "above" and the wingman pulled itself into a zoom climb and a stall.)
	var pit_err: float = asin(clampf(dir.y, -1.0, 1.0)) - ac._pitch_angle()
	var p: float = clampf(pit_err * 3.0 + absf(sin(bank)) * clampf(absf(lat_ang) * 0.6, 0.12, 0.35), -0.5, 0.6)
	var mc: float = max_cmd * turn_scale
	ac.cmd_roll = clampf(r, -mc, mc)
	ac.cmd_pitch = clampf(p * _pull, -mc, mc)
	ac.cmd_yaw = clampf(lat_ang * 0.8, -0.25, 0.25)


func _terrain_h(p: Vector3) -> float:
	if _terrain == null or not is_instance_valid(_terrain):
		_terrain = get_tree().get_first_node_in_group("terrain")
	if _terrain and _terrain.has_method("get_height_at"):
		return maxf(float(_terrain.call("get_height_at", p)), 0.0)
	return 0.0


## Overrides `dir` with a wings-level pull-up when the flight path would hit the ground.
func _guard_ground(dir: Vector3) -> Vector3:
	if _mistake_t > 0.0:
		return dir          # misjudged it: no pull-out
	var pos: Vector3 = ac.global_position
	var fwd: Vector3 = ac.get_forward()
	var look: float = clampf(ac.speed * 1.7, 160.0, 650.0)
	var need: float = 60.0 + maxf(0.0, -ac.velocity.y) * 1.8
	if _avoid_t > 0.0:
		_avoid_t -= get_process_delta_time()
	else:
		for k in [0.3, 0.65, 1.0]:
			var p: Vector3 = pos + fwd * look * k
			if p.y - _terrain_h(p) < need:
				_avoid_t = 0.9
				break
	if _avoid_t > 0.0:
		var flat: Vector3 = Vector3(fwd.x, 0.0, fwd.z)
		_thr = 1.0
		_pull = 1.0
		return (flat.normalized() * 0.35 + Vector3.UP).normalized() if flat.length() > 0.01 else Vector3.UP
	# also don't aim into the ground
	var aim_p: Vector3 = pos + dir * look
	if dir.y < 0.0 and aim_p.y - _terrain_h(aim_p) < need * 1.2:
		return Vector3(dir.x, maxf(dir.y, 0.0) + 0.1, dir.z).normalized()
	return dir


func _limit_energy() -> void:
	var stall: float = ac.stats.stall_speed
	if ac.speed < stall * 1.4:
		_thr = 1.0
		_dir = Vector3(_dir.x, _dir.y - 0.3, _dir.z).normalized()
		_pull = 0.5
		if ac.boost_energy > 0.3 and ac.speed < stall * 1.2:
			_boost = true
	elif ac.speed < stall * 1.7:
		_pull = 0.75
	var fwd_y: float = ac.get_forward().y
	if fwd_y > 0.6 and ac.speed < stall * 2.0:
		_dir = Vector3(_dir.x, minf(_dir.y, 0.1), _dir.z).normalized()


## Heavy bombers jink rather than fly straight when a fighter presses home an attack: a slow, shallow
## S-weave that stays well inside the heavy-steering limits (banks stay <= 26 deg, so no stall-inducing
## break). Applied to the leader only, so the whole formation follows the weave.
func _bomber_weave(dir: Vector3, delta: float) -> Vector3:
	if _is_threatened():
		_weave_t = maxf(_weave_t, 1.4)          # keep weaving for a moment after the run-in passes
	if _weave_t > 0.0:
		_weave_t -= delta
		_jink_t -= delta
		if _jink_t <= 0.0:
			_jink_t = randf_range(2.0, 3.6)
			_jink_sign = -_jink_sign if randf() < 0.8 else _jink_sign
			_jink_up = randf_range(-0.12, 0.16)
	_weave = move_toward(_weave, 0.5 if _weave_t > 0.0 else 0.0, delta * 0.6)
	if _weave <= 0.02:
		return dir
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.01:
		return dir
	var right: Vector3 = flat.normalized().cross(Vector3.UP).normalized()
	return (dir + right * _weave * _jink_sign + Vector3.UP * _weave * _jink_up).normalized()


func _avoid_collisions(delta: float) -> void:
	if role == Role.BOMBER_FOLLOWER or role == Role.BOMBER_LEADER:
		return          # the formation holds its line; evasive steering would throw a bomber into the stall
	_sep_t -= delta
	if _sep_t <= 0.0:
		_sep_t = 0.2
		_sep_dir = Vector3.ZERO
		var pos: Vector3 = ac.global_position
		var r: float = ac.stats.radius
		# wingmen fly close on purpose: only shove apart when really about to touch
		var span: float = 1.3 if role == Role.WINGMAN else 3.0
		for n in get_tree().get_nodes_in_group("aircraft"):
			var o: Aircraft = n as Aircraft
			if o == null or o == ac or o.state == Aircraft.State.DEAD:
				continue
			var rel: Vector3 = pos - o.global_position
			var d: float = rel.length()
			if d < (r + o.stats.radius) * span and d > 0.1:
				_sep_dir += rel / d
	if _sep_dir != Vector3.ZERO:
		var away: Vector3 = (_sep_dir.normalized() + Vector3.UP * 0.25).normalized()
		var w: float = 0.2 if role == Role.WINGMAN else 0.65
		_dir = (_dir * (1.0 - w) + away * w).normalized()


# ------------------------------------------------------------------ firing

func _fire_control(delta: float) -> void:
	var want: bool = false
	if (role == Role.FIGHTER or role == Role.WINGMAN) and (state == State.ATTACK or state == State.INTERCEPT) and is_instance_valid(target) and target.state == Aircraft.State.ALIVE:
		var rel: Vector3 = target.global_position - ac.global_position
		var d: float = rel.length()
		if d < FIRE_RANGE and d > 20.0:
			var ang: float = ac.get_forward().angle_to(rel)
			want = ang < 0.07 + target.stats.radius / d
	if want:
		if _burst_t <= 0.0 and _pause_t <= 0.0:
			_burst_t = randf_range(0.7, 1.4)
		if _burst_t > 0.0:
			_burst_t -= delta
			if _burst_t <= 0.0:
				_pause_t = randf_range(0.4, 1.0) * (1.4 - aggression)
	else:
		_burst_t = 0.0
	_pause_t = maxf(_pause_t - delta, 0.0)
	# Aircraft emits fire_requested while cmd_fire is set; its WeaponSystem spawns the bullets.
	ac.cmd_fire = want and _burst_t > 0.0
	if ac.cmd_fire:
		fire_time += delta


# ------------------------------------------------------------------ weather

func _weather_visibility() -> float:
	var wm: Node = get_node_or_null("/root/WeatherManager")
	var v: float = 1.0
	if wm and wm.has_method("get_visibility_multiplier"):
		v = float(wm.call("get_visibility_multiplier"))
	return v * night_vis()


## Dark skies hide the player's bomber from enemy fighters: 1.0 by day, down at night to ~0.18 under a new moon and
## ~0.30 under a full moon (MoonWeather.moon_light): a bright moon silhouettes a bomber against the sky.
static func night_vis() -> float:
	var tod: Node = Engine.get_main_loop().root.get_node_or_null("TimeOfDay") if Engine.get_main_loop() is SceneTree else null
	if tod == null:
		return 1.0
	var moon: float = MoonWeather.moon_light()
	return lerpf(0.18 + 0.12 * moon, 1.0, smoothstep(0.04, 0.45, float(tod.get("light_level"))))


func _weather_acc() -> float:
	return 0.55 + 0.45 * sqrt(clampf(_vis, 0.0, 1.0))
