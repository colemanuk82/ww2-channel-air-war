class_name BackupCaller
extends Node
## Enemy calls for help. When the player attacks an enemy convoy, ship, ground column or aircraft, the enemy
## sometimes radios for air support: fighters already airborne nearby are vectored onto the player, or, failing
## that, a few are scrambled from the nearest airfield of their side. Not every attack brings help, and there is
## no backup loop:
##   * each attacked convoy / flight is only ever considered once,
##   * only one backup flight is up at a time, with a long quiet spell after it before another call is answered,
##   * a sortie only gets so many calls,
##   * aircraft that came as backup never call for backup themselves.

const CALL_COOLDOWN := 150.0          # quiet seconds after a backup flight is finished (or a call was refused)
const MAX_CALLS := 3                  # per sortie
const NEARBY_RANGE := 14000.0         # airborne enemy fighters this close can be vectored in
const SCRAMBLE_RANGE := 32000.0       # an airfield this close can scramble
const BACKUP_TIME := 240.0            # a backup flight hunts for this long, then goes home
const RECONSIDER := 300.0             # the same convoy / flight may be considered again after this long

var world: Node3D
var player: Node3D
var hud: Node
var difficulty: float = 0.5
var chance: float = 0.35              # odds that an attack brings a call for help

var _cool: float = 45.0               # never in the first minute of a sortie
var _calls: int = 0
var _seen: Dictionary = {}            # incident key -> msec when it was considered
var _active: Array = []               # the backup flight now up (Aircraft)
var _active_t: float = 0.0
var _busy: bool = false               # a call is being made (radio delay)
var _debug: bool = OS.get_cmdline_user_args().has("--debug-backup")


func setup(p_world: Node3D, p_player: Node3D, p_hud: Node, p_difficulty: float) -> BackupCaller:
	world = p_world
	player = p_player
	hud = p_hud
	difficulty = p_difficulty
	chance = lerpf(0.25, 0.45, clampf(difficulty, 0.0, 1.0))
	name = "BackupCaller"
	return self


func _ready() -> void:
	Weapons.player_hit.connect(_on_player_hit)
	if _debug:
		_cool = 3.0
		chance = 1.0


func _process(delta: float) -> void:
	if not _active.is_empty():
		_active = _active.filter(func(a) -> bool: return is_instance_valid(a) and (a as Aircraft).state == Aircraft.State.ALIVE)
		_active_t -= delta
		if _active.is_empty() or _active_t <= 0.0:
			_stand_down()
		return
	if not _busy:
		_cool = maxf(_cool - delta, 0.0)


func _log(msg: String) -> void:
	if _debug:
		print("[backup] ", msg)


## The thing that was hit, as an incident: its convoy, the flight it belongs to, or itself.
func _incident_of(node: Node) -> Dictionary:
	var cur: Variant = world.get("player") if world != null else null
	if cur is Aircraft and is_instance_valid(cur):
		player = cur        # the player respawns as a new aircraft
	var pl: Aircraft = (player as Aircraft) if is_instance_valid(player) else null
	if pl == null or not is_instance_valid(pl):
		return {}
	if node is GroundTarget:
		var g := node as GroundTarget
		if g.is_dead or g.team == pl.team:
			return {}
		var cv: Node = g.get_parent()
		var key: Node = cv if cv is Convoy else g
		var kind: String = "ship" if g.is_in_group("ship") or g is GroundShip else "ground"
		return {"key": key.get_instance_id(), "team": g.team, "pos": g.global_position, "kind": kind}
	if node is Aircraft:
		var a := node as Aircraft
		if a.player_controlled or a.team == pl.team or a.state != Aircraft.State.ALIVE or a.has_meta("backup"):
			return {}
		var p: AIPilot = AIFactory.pilot_of(a)
		var key2: Node = a
		if p != null and is_instance_valid(p.leader) and p.leader is Aircraft:
			key2 = p.leader                       # one flight, one call
		var bomber: bool = AircraftCatalog.is_bomber(a.stats.id)
		return {"key": key2.get_instance_id(), "team": a.team, "pos": a.global_position, "kind": "bomber" if bomber else "fighter"}
	return {}


func _on_player_hit(node: Node, _amount: float) -> void:
	if _busy or not _active.is_empty() or _cool > 0.0 or _calls >= MAX_CALLS:
		return
	var inc: Dictionary = _incident_of(node)
	if inc.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var k: int = int(inc["key"])
	if _seen.has(k) and now - int(_seen[k]) < int(RECONSIDER * 1000.0):
		return
	_seen[k] = now
	if randf() >= chance:
		_log("no call for %s (chance %.2f)" % [inc["kind"], chance])
		return
	_busy = true
	_call(inc)


func _call(inc: Dictionary) -> void:
	await get_tree().create_timer(randf_range(2.0, 6.0)).timeout
	if not is_inside_tree() or player == null or not is_instance_valid(player):
		_busy = false
		return
	var team: String = str(inc["team"])
	var pos: Vector3 = inc["pos"]
	_say_call(team, str(inc["kind"]))
	await get_tree().create_timer(randf_range(4.0, 9.0)).timeout
	if not is_inside_tree():
		return
	var sent: Array = _vector_nearby(team, pos)
	var how: String = "nearby"
	if sent.is_empty():
		sent = _scramble(team, pos)
		how = "scramble"
	_busy = false
	if sent.is_empty():
		_log("call from %s went unanswered" % inc["kind"])
		_say_refused(team)
		_cool = CALL_COOLDOWN * 0.5
		return
	_calls += 1
	_active = sent
	_active_t = BACKUP_TIME
	_log("%s backup: %d aircraft (%s), call %d" % [how, sent.size(), (sent[0] as Aircraft).stats.id, _calls])
	_warn_player(team, how, sent.size())


## Enemy fighters already up and not busy fighting are sent to the scene.
func _vector_nearby(team: String, pos: Vector3) -> Array:
	var out: Array = []
	var want: int = randi_range(2, 4)
	for n in get_tree().get_nodes_in_group("aircraft"):
		var a: Aircraft = n as Aircraft
		if a == null or a.player_controlled or a.team != team or a.state != Aircraft.State.ALIVE or a.on_ground:
			continue
		if AircraftCatalog.is_bomber(a.stats.id) or a.has_meta("backup"):
			continue
		var p: AIPilot = AIFactory.pilot_of(a)
		if p == null or p.role != AIPilot.Role.FIGHTER:
			continue
		if not (p.state == AIPilot.State.PATROL or p.state == AIPilot.State.ROUTE):
			continue
		if a.global_position.distance_to(pos) > NEARBY_RANGE:
			continue
		_send(a, p, pos)
		out.append(a)
		if out.size() >= want:
			break
	return out


## Fighters scrambled from the nearest airfield of the side that called; they appear climbing out from the field.
func _scramble(team: String, pos: Vector3) -> Array:
	var pop: WorldPopulator = WorldPopulator.instance
	if pop == null:
		return []
	var best: Dictionary = {}
	var bd: float = SCRAMBLE_RANGE
	for f in pop.airfield_sites("Luftwaffe" if team == "Axis" else "RAF"):
		var fp: Vector3 = f["pos"]
		var d: float = Vector2(fp.x - pos.x, fp.z - pos.z).length()
		if d < bd:
			bd = d
			best = f
	if best.is_empty():
		return []
	var n: int = mini(randi_range(2, 4), AIFactory.ai_room(get_tree()))
	if n < 2:
		return []
	var fid: String = _fighter_type(team)
	var fpos: Vector3 = best["pos"]
	var to: Vector3 = Vector3(pos.x - fpos.x, 0.0, pos.z - fpos.z)
	var dir: Vector3 = to.normalized() if to.length() > 1.0 else Vector3.FORWARD
	var hd: float = WorldCoords.dir_to_heading(dir)
	var side := Vector3(-dir.z, 0.0, dir.x)
	# if the player is close enough to see the field, start them further out along the climb so nobody pops into view
	var start: Vector3 = fpos + dir * 1500.0
	var gy: float = GroundKit.ground_y(start.x, start.z)
	var out: Array = []
	for i in n:
		var p0: Vector3 = start - dir * float(i / 2) * 140.0 + side * (float(i % 2) * 2.0 - 1.0) * 70.0
		p0.y = gy + 500.0 + float(i) * 30.0
		var a: Aircraft = AIFactory.spawn(world, fid, team, p0, hd, -1.0, difficulty, AIPilot.Role.FIGHTER)
		a.set_meta("backup_scrambled", true)
		var p: AIPilot = AIFactory.pilot_of(a)
		if p != null:
			p.home = fpos
			_send(a, p, pos)
		AIFactory.add_marker(hud, a, Color(1.0, 0.25, 0.2))
		a.crashed.connect(func(x: Aircraft, _r: String) -> void:
			await x.get_tree().create_timer(2.5).timeout
			if is_instance_valid(x):
				x.queue_free())
		out.append(a)
	_log("scrambled %d %s from %s, %.0f km away" % [n, fid, str(best.get("name", "?")), bd / 1000.0])
	return out


func _send(a: Aircraft, p: AIPilot, pos: Vector3) -> void:
	a.set_meta("backup", true)
	p.patrol_center = pos
	p.patrol_radius = 3000.0
	p.patrol_alt = maxf(pos.y, GroundKit.ground_y(pos.x, pos.z)) + randf_range(700.0, 1300.0)
	p.detect_range = 9000.0
	p.set_route([Vector3(pos.x, p.patrol_alt, pos.z)] as Array[Vector3])


func _fighter_type(team: String) -> String:
	var y: int = int(GameState.era_date.substr(0, 4)) if GameState.era_date.length() >= 4 else 1940
	var pool: Array
	if team == "Axis":
		pool = ["bf109"] if y <= 1940 else (["bf109f", "fw190"] if y <= 1942 else ["bf109g", "fw190"])
	else:
		pool = ["spitfire", "hurricane"] if y <= 1941 else (["spitfire_mkix", "typhoon"] if y <= 1943 else ["spitfire_mkix", "tempest", "p51"])
	return pool[randi() % pool.size()]


## The backup flight's time is up (or it is gone): the survivors go home, and a quiet spell follows.
func _stand_down() -> void:
	for a in _active:
		if is_instance_valid(a):
			var p: AIPilot = AIFactory.pilot_of(a)
			if p == null or p.state == AIPilot.State.ATTACK or p.state == AIPilot.State.INTERCEPT:
				continue                     # still fighting: leave him to it
			if a.has_meta("backup_scrambled"):
				p.target = null
				p._set_state(AIPilot.State.RETURN)     # back to the field they came from
			else:
				p.patrol_center = a.global_position
				p.waypoints.clear()
				p._set_state(AIPilot.State.PATROL)
	_active.clear()
	_cool = CALL_COOLDOWN
	_log("backup stood down")


# ------------------------------------------------------------------ radio

func _say_call(team: String, kind: String) -> void:
	var axis: bool = team == "Axis"
	var lines: Array
	match kind:
		"ship":
			lines = [["Geleit Ost", "Convoy under air attack! Request fighter cover immediately!"], ["Vorpostenboot", "Enemy fighters over the convoy, we need help!"]] if axis \
				else [["Convoy commodore", "We're under attack! Request fighter cover, urgent!"], ["Escort leader", "Enemy aircraft over the convoy, send fighters!"]]
		"ground":
			lines = [["Flakgruppe", "Jabos attacking the column! Request fighters!"], ["Kanal Control", "Ground units under air attack. Fighters to the area."]] if axis \
				else [["Army liaison", "Column under air attack, we need fighters overhead!"], ["Sector Control", "Ground forces being strafed. Request support."]]
		"bomber":
			lines = [["Kampfgruppe", "Fighters attacking the formation! Where is our escort?"], ["Bomber leader", "Under attack! Request fighter support!"]] if axis \
				else [["Bomber leader", "Fighters on us! Request support, now!"], ["Bomber leader", "We're being hit, need some help up here!"]]
		_:
			lines = [["Rot Eins", "Enemy fighter on us, request help!"], ["Gelb Zwei", "Need assistance, Spitfires attacking!"]] if axis \
				else [["Red leader", "Bandit on our tails, any fighters in the area?"], ["Blue two", "Need help up here, 109s on us!"]]
	var l: Array = lines[randi() % lines.size()]
	Radio.say(str(l[0]), str(l[1]), Radio.Kind.CONTROL, 0.0)


func _say_refused(team: String) -> void:
	if randf() < 0.5:
		return
	var l: Array = ["Jafü 2", "No fighters available. Hold on."] if team == "Axis" else ["Sector Control", "Nothing to send you. Hold on."]
	Radio.say(str(l[0]), str(l[1]), Radio.Kind.CONTROL, 0.0)


## The player's own controller has heard it: warn him that help is on its way to the other side.
func _warn_player(team: String, how: String, n: int) -> void:
	var ctrl: String = "Sector Control" if team == "Axis" else "Kanal Control"
	var what: String = "%d bandits" % n if n > 1 else "a bandit"
	var line: String
	if how == "scramble":
		line = "Heads up, %s scrambling to intercept you. Expect company in a few minutes." % what if team == "Axis" else "Achtung, %s scrambling against you. Expect them soon." % what.replace("bandits", "Tommies").replace("a bandit", "a Tommy")
	else:
		line = "Watch out, %s nearby turning towards you." % what if team == "Axis" else "Achtung, %s close by, turning onto you." % what.replace("bandits", "Tommies").replace("a bandit", "a Tommy")
	Radio.say(ctrl, line, Radio.Kind.CONTROL, randf_range(3.0, 6.0))
