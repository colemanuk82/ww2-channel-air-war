class_name PassingFlights
extends Node
## Free flight: friendly flights out on their own business. Every few minutes a formation appears in the player's
## sector already on its way to a real target on the other side: a bomber raid with a close escort, or a fighter
## sweep. When the player comes within a few kilometres the leader calls him up and asks if he wants to tag
## along; key 5 accepts. Joined, the compass points at the flight (then at the target), the enemy come up to
## meet it near the target, and seeing it through goes in the logbook. Ignore the offer and the flight carries on
## without you. Owned by FreeFlightMode (cfg "passing_flights", on by default; --no-passing turns it off).
## Debug: --passing-test (first flight after 4 s, close by), --passing-kind=raid|sweep, --passing-auto (accept).

const OFFER_RANGE: float = 3600.0      # world units: how close the player must come before the leader calls
const OFFER_TIME: float = 25.0         # seconds the offer stays open
const LOSE_RANGE: float = 22000.0      # a joined player this far from the flight for LOSE_TIME has left it
const LOSE_TIME: float = 60.0
const DESPAWN_RANGE: float = 30000.0   # an unjoined flight this far away is quietly removed
const ALLY_CALLS := ["Tiger", "Gannic", "Sapper", "Bearskin", "Mitor", "Kenway", "Yorker", "Wagon"]
const AXIS_CALLS := ["Adler", "Falke", "Rabe", "Wiesel", "Kurfürst", "Stieglitz", "Hummel", "Elster"]

var world: Node3D
var player: Aircraft
var hud: Node
var mode: ModeBase
var side: String = "Allies"
var enemy: String = "Axis"
var difficulty: float = 0.5
var ops: Node                          # the Ops Room, if running: no offers while one of its taskings is active

var flight: Dictionary = {}            # the current flight (empty = none), see _spawn_flight
var joined_count: int = 0
var _next_t: float = 200.0
var _scan_t: float = 0.0
var _args: PackedStringArray = OS.get_cmdline_user_args()
var _test: bool = false
var _auto: bool = false
var _forced: String = ""


func setup(p_world: Node3D, p_player: Aircraft, p_hud: Node, p_mode: ModeBase, p_side: String, p_difficulty: float) -> void:
	world = p_world
	player = p_player
	hud = p_hud
	mode = p_mode
	side = p_side
	enemy = AircraftCatalog.opposite(side)
	difficulty = p_difficulty
	_test = _args.has("--passing-test")
	_auto = _args.has("--passing-auto")
	for a in _args:
		if a.begins_with("--passing-kind="):
			_forced = a.substr(15)
	_next_t = 4.0 if _test else randf_range(150.0, 260.0)


func _process(delta: float) -> void:
	if world == null or player == null or not is_instance_valid(player):
		return
	if flight.is_empty():
		_next_t -= delta
		if _next_t <= 0.0:
			_next_t = 20.0          # retried soon if nothing could be placed (on the ground, no target...)
			if _can_spawn():
				_spawn_flight()
		return
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = 0.5
	_update_flight(0.5)


func _can_spawn() -> bool:
	if player.state != Aircraft.State.ALIVE or player.on_ground or player.altitude_agl < 150.0:
		return false
	if AIFactory.ai_room(get_tree()) < 8:     # room for the flight and the fighters that come up to meet it
		return false
	return WorldPopulator.instance != null and is_instance_valid(WorldPopulator.instance)


func _ops_busy() -> bool:
	if ops == null or not is_instance_valid(ops):
		return false
	var a: Variant = ops.get("active")
	return a is Dictionary and not (a as Dictionary).is_empty()


# ------------------------------------------------------------------ spawning

func _spawn_flight() -> void:
	var pp: Vector3 = player.global_position
	# a real target on the other side, a decent run away
	var cands: Array = []
	for t in WorldPopulator.instance.raid_targets(enemy):
		var tp: Vector3 = t["pos"]
		var d: float = Vector2(tp.x - pp.x, tp.z - pp.z).length()
		if d > 16000.0 and d < 160000.0:      # (the Channel is ~100 km wide off Sussex)
			cands.append(t)
	if cands.is_empty():
		if _test:
			print("PASSING no target in range")
		return
	# prefer the nearer half, so the run is not always the longest one on the map
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return Vector2((x["pos"] as Vector3).x - pp.x, (x["pos"] as Vector3).z - pp.z).length() < Vector2((y["pos"] as Vector3).x - pp.x, (y["pos"] as Vector3).z - pp.z).length())
	cands = cands.slice(0, maxi(cands.size() / 2, mini(cands.size(), 8)))
	var tgt: Dictionary = cands[randi() % cands.size()]
	var tpos: Vector3 = tgt["pos"]
	var kind: String = _forced
	if kind == "":
		kind = "raid" if AircraftCatalog.is_bomber(player.stats.id) or randf() < 0.55 else "sweep"
	# start a few kilometres ahead and off to one side of the player, already heading for the target, so
	# that flying on he comes across it (the minimap shows it as a friendly blip)
	var pf: Vector3 = Vector3(player.get_forward().x, 0.0, player.get_forward().z)
	pf = pf.normalized() if pf.length() > 0.1 else Vector3(0, 0, -1)
	var perp := Vector3(-pf.z, 0.0, pf.x) * (1.0 if randf() < 0.5 else -1.0)
	var start: Vector3 = pp + pf * (2600.0 if _test else randf_range(6500.0, 9000.0)) + perp * (900.0 if _test else randf_range(1800.0, 3200.0))
	var alt: float = clampf(pp.y + randf_range(-150.0, 450.0), 900.0, 3600.0)
	start.y = maxf(alt, GroundKit.ground_y(start.x, start.z) + 500.0)
	var to_t: Vector3 = Vector3(tpos.x - start.x, 0.0, tpos.z - start.z).normalized()
	var hdg: float = WorldCoords.dir_to_heading(to_t)
	var pool: Array = ALLY_CALLS if side == "Allies" else AXIS_CALLS
	var call: String = pool[randi() % pool.size()]
	if call == str(Radio.get("squadron")):
		call = pool[(pool.find(call) + 1) % pool.size()]
	flight = {"kind": kind, "target": tgt, "tpos": tpos, "alt": start.y, "call": call, "members": [], "enemies": [],
		"leader": null, "form": null, "offered": false, "offer_t": 0.0, "joined": false, "declined": false,
		"phase": "outbound", "lost_t": 0.0, "far_t": 0.0, "patrol_t": 0.0, "scrambled": false, "dropped": false,
		"done": false, "age": 0.0, "what": ""}
	if kind == "raid":
		_spawn_raid(start, hdg, to_t)
	else:
		_spawn_sweep(start, hdg, to_t)
	print("PASSING spawned %s '%s' -> %s (%.0f km away)" % [kind, call, str(tgt["name"]), Vector2(tpos.x - pp.x, tpos.z - pp.z).length() / 1000.0])


func _route_to(start: Vector3, tpos: Vector3, alt: float, home_dir: Vector3) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var to_t: Vector3 = Vector3(tpos.x - start.x, 0.0, tpos.z - start.z)
	var leg: float = to_t.length()
	var n: int = maxi(int(leg / 9000.0), 1)
	for i in range(1, n):
		var f: float = float(i) / float(n)
		pts.append(Vector3(lerpf(start.x, tpos.x, f), alt, lerpf(start.z, tpos.z, f)))
	pts.append(Vector3(tpos.x, alt, tpos.z))
	var out: Vector3 = tpos + home_dir * 5000.0
	pts.append(Vector3(out.x, alt, out.z))
	return pts


func _spawn_raid(start: Vector3, hdg: float, to_t: Vector3) -> void:
	var bids: Array = AircraftCatalog.bombers_for_side(side)
	var bid: String = bids[randi() % bids.size()] if not bids.is_empty() else "blenheim"
	var tpos: Vector3 = flight["tpos"]
	var alt: float = flight["alt"]
	# bomb run, then a turn back toward our side
	var home_dir: Vector3 = (-to_t).rotated(Vector3.UP, deg_to_rad(randf_range(-35.0, 35.0)))
	var route: Array[Vector3] = _route_to(start, tpos, alt, home_dir)
	var back: Vector3 = tpos + home_dir * 30000.0
	route.append(Vector3(back.x, alt * 0.8, back.z))
	var form: BomberFormation = BomberFormation.spawn(world, bid, side, 2, start, hdg, route, difficulty)
	flight["form"] = form
	flight["leader"] = form.leader
	var ground_t := Vector3(tpos.x, GroundKit.ground_y(tpos.x, tpos.z), tpos.z)
	for m in form.members:
		var p: AIPilot = AIFactory.pilot_of(m)
		if p != null:
			p.bomb_target = ground_t
			p.bomb_armed = true
			p.bomber_speed_k = 0.92
		(flight["members"] as Array).append(m)
		_track(m, true)
	# close escort: a pair (or two) of fighters riding high on the bombers' flanks
	var fits: Array = AircraftCatalog.fighters_for_side(side).filter(func(i: String) -> bool: return i != "me262")
	var fid: String = fits[randi() % fits.size()] if not fits.is_empty() else "spitfire"
	var yaw: Basis = Basis.looking_at(WorldCoords.heading_to_dir(hdg), Vector3.UP)
	for j in mini(randi_range(2, 4), maxi(0, AIFactory.ai_room(get_tree()) - 3)):
		var off := Vector3((240.0 + float(j / 2) * 90.0) * (1.0 if j % 2 == 0 else -1.0), 110.0 + float(j / 2) * 40.0, 40.0 + float(j / 2) * 120.0)
		var esc: Aircraft = AIFactory.spawn(world, fid, side, start + yaw * off, hdg, -1.0, clampf(difficulty + 0.15, 0.0, 1.0), AIPilot.Role.WINGMAN, form.leader)
		var ep: AIPilot = AIFactory.pilot_of(esc)
		if ep != null:
			ep.set_leader(form.leader, off)
			ep.engage_radius = 3600.0
			ep.detect_range = 7500.0
		(flight["members"] as Array).append(esc)
		_track(esc, true)
	flight["what"] = "%d %ss for %s" % [form.members.size(), AircraftCatalog.display_name(bid), str(flight["target"]["name"])]
	flight["job"] = "escort"


func _spawn_sweep(start: Vector3, hdg: float, to_t: Vector3) -> void:
	var fits: Array = AircraftCatalog.fighters_for_side(side).filter(func(i: String) -> bool: return i != "me262")
	var fid: String = fits[randi() % fits.size()] if not fits.is_empty() else "spitfire"
	var tpos: Vector3 = flight["tpos"]
	var alt: float = flight["alt"]
	var yaw: Basis = Basis.looking_at(WorldCoords.heading_to_dir(hdg), Vector3.UP)
	var n: int = 4
	var lead: Aircraft = null
	for i in n:
		var off := Vector3(0, 0, 0) if i == 0 else Vector3(70.0 * float(i) * (1.0 if i % 2 == 1 else -1.0), -4.0 * float(i), 85.0 * float(i))
		var role: int = AIPilot.Role.FIGHTER if i == 0 else AIPilot.Role.WINGMAN
		var a: Aircraft = AIFactory.spawn(world, fid, side, start + yaw * off, hdg, -1.0, clampf(difficulty + 0.1, 0.0, 1.0), role, lead)
		var p: AIPilot = AIFactory.pilot_of(a)
		if i == 0:
			lead = a
			p.patrol_center = Vector3(tpos.x, alt, tpos.z)        # after any fight, it carries on to the target area
			p.patrol_alt = alt
			p.patrol_radius = 3000.0
			p.detect_range = 7000.0
			p.set_route(_route_to(start, tpos, alt, -to_t))
			p.route_finished.connect(func() -> void:
				if not flight.is_empty() and flight.get("leader") == a:
					flight["phase"] = "patrol")
		else:
			p.set_leader(lead, off)
			p.engage_radius = 3600.0
			p.detect_range = 7000.0
		(flight["members"] as Array).append(a)
		_track(a, true)
	flight["leader"] = lead
	flight["what"] = "a sweep of %d %ss over %s" % [n, AircraftCatalog.display_name(fid), str(flight["target"]["name"])]
	flight["job"] = "sweep"


func _track(a: Aircraft, friendly: bool) -> void:
	AIFactory.add_marker(hud, a, Color(0.3, 0.75, 1.0) if friendly else Color(1.0, 0.25, 0.2))
	a.crashed.connect(func(x: Aircraft, _r: String) -> void:
		await x.get_tree().create_timer(2.5).timeout
		if is_instance_valid(x):
			x.queue_free())


# ------------------------------------------------------------------ the flight on its way

func _alive(arr: Array) -> Array:
	return arr.filter(func(m) -> bool: return is_instance_valid(m) and (m as Aircraft).state == Aircraft.State.ALIVE)


func _lead() -> Aircraft:
	var l: Variant = flight.get("leader")
	if l != null and is_instance_valid(l) and (l as Aircraft).state == Aircraft.State.ALIVE:
		return l
	var alive: Array = _alive(flight["members"])
	if alive.is_empty():
		return null
	var form: Variant = flight.get("form")
	if form != null and is_instance_valid(form) and is_instance_valid((form as BomberFormation).leader):
		flight["leader"] = (form as BomberFormation).leader
		return flight["leader"]
	flight["leader"] = alive[0]
	return alive[0]


func _update_flight(dt: float) -> void:
	flight["age"] = float(flight["age"]) + dt
	var lead: Aircraft = _lead()
	if lead == null:
		_end_flight(false, "lost")
		return
	var pp: Vector3 = player.global_position
	var d: float = pp.distance_to(lead.global_position)
	var player_ok: bool = player.state == Aircraft.State.ALIVE
	var tpos: Vector3 = flight["tpos"]
	var to_target: float = Vector2(lead.global_position.x - tpos.x, lead.global_position.z - tpos.z).length()
	if _test and fmod(float(flight["age"]), 4.0) < dt * 0.5:
		var lp: AIPilot = AIFactory.pilot_of(lead)
		print("PASSING t=%.0f %s phase=%s d=%.0f to_tgt=%.0f lead_st=%d alt=%.0f spd=%.0f alive=%d foes=%d offered=%s joined=%s" % [float(flight["age"]), str(flight["kind"]), str(flight["phase"]), d, to_target, lp.state if lp else -1, lead.global_position.y, lead.speed, _alive(flight["members"]).size(), _alive(flight["enemies"]).size(), str(flight["offered"]), str(flight["joined"])])
	# the offer, once, when the player comes within sight
	if not bool(flight["offered"]) and player_ok and not player.on_ground and d < OFFER_RANGE and not _ops_busy() and flight["phase"] == "outbound":
		_offer(lead)
	if bool(flight["offered"]) and not bool(flight["joined"]) and not bool(flight["declined"]):
		flight["offer_t"] = float(flight["offer_t"]) - dt
		if _auto and float(flight["offer_t"]) < OFFER_TIME - 2.0:
			accept()
		elif float(flight["offer_t"]) <= 0.0:
			flight["declined"] = true
			Radio.say(_leader_call(), ["No matter. Good hunting.", "Understood. We'll press on.", "Fair enough. Cheerio."][randi() % 3], Radio.Kind.FRIENDLY, 0.2)
			_set_label("")
	# the other side comes up to meet the flight near the target (only worth the aircraft if the player is with it)
	if bool(flight["joined"]) and not bool(flight["scrambled"]) and to_target < 14000.0:
		flight["scrambled"] = true
		_scramble(lead)
	match str(flight["kind"]):
		"raid":
			# over the target and out the far side counts as the raid done even if a straggler kept its bombs
			if to_target < 1500.0:
				flight["over"] = true
			var past: bool = bool(flight.get("over", false)) and to_target > 4500.0
			if not bool(flight["dropped"]) and (_bombs_gone() or past):
				flight["dropped"] = true
				flight["phase"] = "home"
				Radio.say(_leader_call(), ["Bombs gone! Turning for home.", "Bombs away. Let's go home.", "That's the lot. Turning for home."][randi() % 3], Radio.Kind.FRIENDLY, 0.5)
				if bool(flight["joined"]):
					_end_flight(true, "the raid on %s" % str(flight["target"]["name"]))
					return
		"sweep":
			if str(flight["phase"]) == "outbound" and to_target < 3500.0:
				flight["phase"] = "patrol"
			if str(flight["phase"]) == "patrol":
				flight["patrol_t"] = float(flight["patrol_t"]) + dt
				var foes: Array = _alive(flight["enemies"])
				var cleared: bool = bool(flight["scrambled"]) and foes.is_empty() and float(flight["patrol_t"]) > 30.0
				if cleared or float(flight["patrol_t"]) > 150.0:
					flight["phase"] = "home"
					Radio.say(_leader_call(), ["Sky's clear. That'll do for today, heading home.", "Nothing more up here. Home, chaps.", "Right, that's our patrol done. Turning for home."][randi() % 3], Radio.Kind.FRIENDLY, 0.5)
					_send_home()
					if bool(flight["joined"]):
						_end_flight(true, "the sweep over %s" % str(flight["target"]["name"]))
						return
	# a joined player who wanders far away has left the flight
	if bool(flight["joined"]):
		if d > LOSE_RANGE:
			flight["lost_t"] = float(flight["lost_t"]) + dt
			if float(flight["lost_t"]) > LOSE_TIME:
				Radio.say(_leader_call(), "Lost sight of you. We'll carry on.", Radio.Kind.FRIENDLY, 0.2)
				_end_flight(false, "left")
				return
		else:
			flight["lost_t"] = 0.0
		if not player_ok:
			_end_flight(false, "shot down")
			return
	else:
		# nobody is watching: tidy it away once it is well out of the player's sector
		if d > DESPAWN_RANGE:
			flight["far_t"] = float(flight["far_t"]) + dt
			if float(flight["far_t"]) > 20.0:
				_end_flight(false, "gone", true)
				return
		else:
			flight["far_t"] = 0.0
		if str(flight["phase"]) == "home" and d > 12000.0:
			_end_flight(false, "gone", true)
			return
	if bool(flight["joined"]):
		var verb: String = "escort to" if str(flight["kind"]) == "raid" else "sweep over"
		_set_label("With %s: %s %s%s" % [str(flight["call"]), verb, str(flight["target"]["name"]), "" if str(flight["phase"]) != "patrol" else " (patrolling)"])


func _bombs_gone() -> bool:
	var form: Variant = flight.get("form")
	if form == null or not is_instance_valid(form):
		return false
	var any: bool = false
	for m in (form as BomberFormation).members:
		if is_instance_valid(m) and (m as Aircraft).state == Aircraft.State.ALIVE:
			any = true
			if (m as Aircraft).bombs > 0:
				return false
	return any


func _send_home() -> void:
	var lead: Aircraft = _lead()
	if lead == null:
		return
	var p: AIPilot = AIFactory.pilot_of(lead)
	if p == null:
		return
	var home: Vector3 = player.global_position
	for n in get_tree().get_nodes_in_group("airfield"):
		var af: Airfield = n as Airfield
		if af != null and af.team == side:
			home = af.global_position
			break
	p.patrol_center = Vector3(home.x, lead.global_position.y, home.z)
	p.home = home
	p.set_route([Vector3(home.x, lead.global_position.y, home.z)] as Array[Vector3])


## Enemy fighters scramble against the flight as it nears the target.
func _scramble(lead: Aircraft) -> void:
	var pool: Array = AircraftCatalog.fighters_for_side(enemy).filter(func(i: String) -> bool: return i != "me262" and i != "mosquito")
	if pool.is_empty():
		return
	var fid: String = pool[randi() % pool.size()]
	var tpos: Vector3 = flight["tpos"]
	var to_us: Vector3 = Vector3(lead.global_position.x - tpos.x, 0.0, lead.global_position.z - tpos.z).normalized()
	var c: Vector3 = tpos + to_us * 3000.0
	var n: int = mini(randi_range(3, 5) + (1 if str(flight["kind"]) == "sweep" else 0), AIFactory.ai_room(get_tree()))
	if n < 2:
		return
	var hdg: float = WorldCoords.dir_to_heading(to_us)
	for i in n:
		var pos := Vector3(c.x + float(i) * 110.0, maxf(float(flight["alt"]) + randf_range(-150.0, 350.0), GroundKit.ground_y(c.x, c.z) + 400.0), c.z + float(i % 2) * 120.0)
		var e: Aircraft = AIFactory.spawn(world, fid, enemy, pos, hdg, -1.0, difficulty, AIPilot.Role.FIGHTER)
		var p: AIPilot = AIFactory.pilot_of(e)
		if p != null:
			p.patrol_center = lead.global_position
			p.patrol_alt = float(flight["alt"])
			p.patrol_radius = 2500.0
			p.detect_range = 9000.0
		(flight["enemies"] as Array).append(e)
		_track(e, false)
	Radio.say(_leader_call(), ["Bandits, twelve o'clock, coming up to meet us!", "Here they come - bandits ahead!", "Look out, enemy fighters climbing up ahead!"][randi() % 3], Radio.Kind.FRIENDLY, 0.3)


# ------------------------------------------------------------------ the offer

func _leader_call() -> String:
	return "%s leader" % str(flight.get("call", "Flight"))


func _offer(lead: Aircraft) -> void:
	flight["offered"] = true
	flight["offer_t"] = OFFER_TIME
	var me: String = Radio.callsign_of(player)
	var line: String
	if str(flight["job"]) == "escort":
		line = "%s, this is %s. %s. Could do with another escort - care to join us?" % [me, _leader_call(), str(flight["what"]).capitalize()]
	else:
		line = "%s, %s here. We're off on %s. Fancy coming along?" % [me, _leader_call(), str(flight["what"])]
	Radio.say(_leader_call(), line, Radio.Kind.FRIENDLY, 0.2)
	_set_label("Press 5 to join %s flight" % str(flight["call"]))
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "Press 5 to join %s" % _leader_call(), 5.0)


func _unhandled_input(event: InputEvent) -> void:
	if GameState.paused or flight.is_empty():
		return
	if event.is_action_pressed("radio_join"):
		if bool(flight["offered"]) and not bool(flight["joined"]) and not bool(flight["declined"]):
			accept()
			get_viewport().set_input_as_handled()


func accept() -> void:
	if flight.is_empty() or bool(flight["joined"]):
		return
	flight["joined"] = true
	joined_count += 1
	var me: String = Radio.callsign_of(player)
	Radio.say(me, ["Count me in. Joining you now.", "Wilco, I'll tag along.", "Love to. Coming up on your flank."][randi() % 3], Radio.Kind.PLAYER, 0.0)
	var reply: String = "Good show. Take the high cover, we'll lead." if str(flight["job"]) == "escort" else "Splendid. Form on us, we'll lead."
	Radio.say(_leader_call(), reply, Radio.Kind.FRIENDLY, 1.6)
	if mode != null and is_instance_valid(mode):
		mode.objective_updated.emit("With %s: %s" % [str(flight["call"]), str(flight["what"])])
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "Joined %s - follow the flight (compass)" % _leader_call(), 4.0)


func _end_flight(success: bool, what: String, quiet: bool = false) -> void:
	var was_joined: bool = bool(flight.get("joined", false))
	if was_joined and success:
		PilotLog.record_and_announce(side, {"missions": 1, "points": 250}, "Joined %s on %s" % [_leader_call(), what], hud)
		Radio.say(_leader_call(), ["Thanks for the company. Drinks are on us.", "Much obliged for the help. Cheerio.", "Good work up there. Thanks for coming along."][randi() % 3], Radio.Kind.FRIENDLY, 3.0)
	if was_joined and mode != null and is_instance_valid(mode):
		mode.objective_updated.emit("Free flight")
	_set_label("")
	if quiet:
		for m in (flight["members"] as Array) + (flight["enemies"] as Array):
			if is_instance_valid(m):
				(m as Node).queue_free()
		var form: Variant = flight.get("form")
		if form != null and is_instance_valid(form):
			(form as Node).queue_free()
	else:
		# whatever is still flying goes home in its own time; tidy it away later
		var left: Array = (flight["members"] as Array) + (flight["enemies"] as Array)
		var form2: Variant = flight.get("form")
		get_tree().create_timer(150.0).timeout.connect(func() -> void:
			for m in left:
				if is_instance_valid(m) and is_instance_valid(player) and (m as Node3D).global_position.distance_to(player.global_position) > 9000.0:
					(m as Node).queue_free()
			if form2 != null and is_instance_valid(form2) and (form2 as BomberFormation).alive_count() == 0:
				(form2 as Node).queue_free())
	print("PASSING ended: %s joined=%s success=%s" % [what, str(was_joined), str(success)])
	flight = {}
	_next_t = 4.0 if _test else randf_range(240.0, 420.0)


# ------------------------------------------------------------------ compass and panel

## Compass target while flying with the flight: the leader on the way out, the target once close to it.
func nav_point() -> Variant:
	if flight.is_empty() or not bool(flight["joined"]):
		return null
	var lead: Aircraft = _lead()
	if lead == null:
		return null
	if player.global_position.distance_to(lead.global_position) > 2500.0:
		return lead.global_position
	return flight["tpos"]


var _label: Label


func _set_label(text: String) -> void:
	if _label == null:
		if hud == null or not hud.has_method("add_widget"):
			return
		_label = Label.new()
		_label.add_theme_font_size_override("font_size", 15)
		_label.add_theme_color_override("font_color", Color(0.7, 0.88, 1.0))
		_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		_label.add_theme_constant_override("outline_size", 4)
		hud.call("add_widget", _label)
	_label.text = text
	_label.visible = text != ""


func _exit_tree() -> void:
	if _label != null and is_instance_valid(_label):
		_label.queue_free()
