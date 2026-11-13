class_name HistoricalMissions
extends ModeBase
## Historical missions loader. Turns data/missions.json into a configured inner mode:
##   role "strike"  -> BombingMode (objectives = mission targets, flak + interception + RTB)
##   role "strafe"  -> GroundAttackMode (destroy the listed convoy / targets)
##   role "defend"  -> DefendMode (protect objectives from bomber raids)
## Register in ModeRegistry as "historical" (script = this file); main passes cfg {"mission": id, "side": ...}.
## Sets start airfield, time of day, weather, and exposes briefing text via get_briefing().
## Static API: HistoricalMissions.list() -> Array[Dictionary], get_mission(id), create(id, side) -> ModeBase,
##             HistoricalMissions.briefing_for(id, side) -> String.
## Mission ids: bob_kent, dieppe_1942, dday_1944, dunkirk_1940, antwerp_raid, lille_raid, lehavre_raid,
##              v1_sites, seine_bridges.

const MISSIONS_PATH := "res://data/missions.json"

var start_airborne: bool = true
var manages_respawn: bool = true

var mission_id: String = "bob_kent"
var side: String = "Allies"
var mission: Dictionary = {}
var side_cfg: Dictionary = {}
var inner: ModeBase
var role: String = "strike"
var teleport: bool = false

static var _cache: Array = []


static func list() -> Array:
	if _cache.is_empty():
		var f: FileAccess = FileAccess.open(MISSIONS_PATH, FileAccess.READ)
		if f == null:
			f = FileAccess.open("res://data/missions_seed.json", FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_cache = (d as Dictionary).get("missions", [])
	return _cache


static func get_mission(id: String) -> Dictionary:
	for m in list():
		if m["id"] == id:
			return m
	return {}


static func sides_of(id: String) -> Array:
	var out: Array = []
	for s in get_mission(id).get("sides", []):
		out.append(s["side"])
	return out


static func briefing_for(id: String, p_side: String) -> String:
	return MissionBrief.briefing(get_mission(id), p_side)


static func create(id: String, p_side: String = "Allies") -> HistoricalMissions:
	var h := HistoricalMissions.new()
	h.mission_id = id
	h.side = p_side
	h._load()
	return h


func nav_point() -> Variant:
	return inner.nav_point() if inner != null and is_instance_valid(inner) else null


func live_stats() -> Dictionary:
	var d: Dictionary = inner.live_stats() if inner != null else super.live_stats()
	if _ev_kills > 0:
		d["air_kills"] = _ev_kills
	d["mission"] = str(mission.get("name", mission_id))
	var f: Dictionary = _facts(d)
	for i in _bonuses.size():
		var b: Dictionary = _bonuses[i]
		var note: String = MissionBrief.bonus_progress(b, f)
		d["bonus_%d" % (i + 1)] = "%s%s" % [str(b["short"]), (" (%s)" % note) if note != "" else ""]
	return d


func get_briefing() -> String:
	return briefing_for(mission_id, side)


func _load() -> void:
	mission = get_mission(mission_id)
	for s in mission.get("sides", []):
		if s["side"] == side:
			side_cfg = s
	role = str((mission.get("roles", {}) as Dictionary).get(side, "strike"))


func configure(cfg: Dictionary) -> void:
	if cfg.has("mission"):
		mission_id = str(cfg["mission"])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mission="):
			mission_id = a.substr(10)
	side = str(cfg.get("side", GameState.player_side))
	_load()
	if mission.is_empty():
		push_warning("HistoricalMissions: unknown mission '%s'" % mission_id)
		return
	start_airborne = bool(mission.get("airborne", true))   # false = start on the runway (take-off)
	GameState.era_date = str(mission.get("date", ""))   # decides which airfields are liberated on this date
	# environment + start airfield
	TimeOfDay.set_time(float(mission.get("time_of_day", 12.0)))
	WeatherManager.set_weather(str(mission.get("weather", "clear")), 0.1)
	if side_cfg.has("spawn"):      # the mission starts in the air at a fixed point (start_airfield is then just "home")
		var sp: Dictionary = side_cfg["spawn"]
		GameState.spawn_point = {"name": str(mission.get("name", "")), "lat": float(sp["lat"]), "lon": float(sp["lon"]),
			"heading": float(sp.get("heading", 90.0)), "alt": float(sp.get("alt", 1500.0))}
	if side_cfg.has("start_airfield"):
		GameState.start_airfield = str(side_cfg["start_airfield"])
		var pop: WorldPopulator = WorldPopulator.ensure(world)
		if "airfields" in world:
			var afs: Dictionary = world.get("airfields")
			var af: Airfield = pop.get_airfield(GameState.start_airfield)
			if af != null:
				afs[GameState.start_airfield] = af
	teleport = teleport or GroundKit.has_arg("--wp-teleport")
	# flight size from the mission (importers: the player's own flight); older missions: two wingmen for fighter pilots
	wingmen_wanted = int(mission.get("wingmen", 2))
	if role == "sweep":
		wingmen_wanted = 0          # the dogfight mode brings its own
	var objs: Array = (mission.get("objectives", {}) as Dictionary).get(side, [])
	var icfg: Dictionary = cfg.duplicate()
	icfg["side"] = side
	match role:
		"defend":
			var d := DefendMode.new()
			icfg["protect"] = (mission.get("protect", {}) as Dictionary).get(side, objs)
			icfg["waves"] = int(mission.get("waves", 3))
			d.teleport = teleport
			inner = d
		"escort":
			var e := EscortMode.new()
			icfg["targets"] = objs
			inner = e
		"sweep":
			inner = DogfightMode.new()
		"strafe":
			var g := GroundAttackMode.new()
			icfg["targets"] = objs
			g.teleport = teleport
			inner = g
		_:
			var b := BombingMode.new()
			icfg["targets"] = objs
			icfg["no_fighters"] = bool(mission.get("no_fighters", false))
			b.teleport = teleport
			inner = b
	inner.name = "Inner_" + role
	inner.radio_quiet = true
	inner.setup(world, player, hud)
	inner.call("configure", icfg)
	_bonuses = MissionBrief.bonuses(mission, side)
	inner.mission_complete.connect(func(ok: bool, st: Dictionary) -> void:
		_line("win" if ok else "lose")
		var stats: Dictionary = st.duplicate()
		stats["mission"] = str(mission.get("name", mission_id))
		stats["success"] = ok
		var db: Dictionary = MissionBrief.debrief(mission, side, _facts(stats))
		stats["debrief"] = db
		stats["grade"] = str(db["grade_name"])
		if ok:
			GameState.record_mission_grade(mission_id, int(db["grade"]))
		finish(ok, stats))
	inner.objective_updated.connect(func(t: String) -> void:
		_objective_text = t
		_card_show_t = CARD_SHOW_S
		objective_updated.emit(t))
	inner.score_changed.connect(func(sc: int) -> void:
		score = sc
		score_changed.emit(sc))


func setup(p_world: Node3D, p_player: Node3D, p_hud: Node) -> void:
	super.setup(p_world, p_player, p_hud)


func start() -> void:
	bomber_support = true     # a bomber player gets the squadron + escort (ModeBase); fighter pilots get wingmen
	super.start()
	if inner == null:
		_load()
		if mission.is_empty():
			finish(false, {"reason": "unknown mission"})
			return
		configure({"side": side, "mission": mission_id})
	add_child(inner)
	inner.start()
	_events_pending = (mission.get("events", []) as Array).duplicate(true)
	_spawn_scene()
	_spawn_wing()
	if _wing != null:
		_support_skip_bombers = true   # this mission already flies its own bomber stream; add the escort only
	_build_objective_card()
	_line("start_1", 1.0)
	_line("start_2", 2.0)
	if hud and hud.has_method("show_message"):
		hud.call("show_message", str(mission.get("name", "")), 3.5)


# ------------------------------------------------------------------ battle scene (D-Day / Dunkirk) and friendly bomber stream
var _wing: BomberFormation
var _wing_targets: Array = []
var _wing_bombed: Dictionary = {}
var _wing_home: Vector3 = Vector3.ZERO


func _spawn_scene() -> void:
	var sc: Variant = mission.get("scene", null)
	if sc is Dictionary and world != null:
		world.add_child(BattleScene.create(sc as Dictionary))


## Mission field "wing": {count, aircraft, alt_m}: a stream of friendly AI bombers flying the target chain ahead of the player.
func _spawn_wing() -> void:
	var w: Variant = (mission.get("wing_by_side", {}) as Dictionary).get(side, null)
	if not (w is Dictionary) or player == null:
		return
	var objs: Array = (mission.get("objectives", {}) as Dictionary).get(side, [])
	var pop: WorldPopulator = WorldPopulator.ensure(world)
	var pts: Array[Vector3] = []
	var pp: Vector3 = (player as Node3D).global_position
	var alt: float = float((w as Dictionary).get("alt_m", 1800.0)) * 2.0
	for id in objs:
		var info: Dictionary = pop.get_target_info(str(id))
		if info.has("pos"):
			var p: Vector3 = info["pos"]
			pts.append(Vector3(p.x, alt, p.z))
			_wing_targets.append({"id": str(id), "pos": p})
	if pts.is_empty():
		return
	var to_t: Vector3 = pts[0] - pp
	to_t.y = 0.0
	var dir: Vector3 = to_t.normalized() if to_t.length() > 1.0 else Vector3(0, 0, -1)
	_wing_home = Vector3(pp.x, 0.0, pp.z)
	var af: Airfield = pop.get_airfield(GameState.start_airfield)
	if af != null:
		_wing_home = Vector3(af.position.x, af.surface_y, af.position.z)
	# home leg: fly back to the base airfield, losing height on the way in
	var back: Vector3 = _wing_home - pts[pts.size() - 1]
	back.y = 0.0
	var back_dir: Vector3 = back.normalized() if back.length() > 1.0 else dir
	pts.append(Vector3(_wing_home.x, alt, _wing_home.z) - back_dir * 9000.0)
	pts.append(Vector3(_wing_home.x, maxf(alt * 0.3, 500.0), _wing_home.z) - back_dir * 2500.0)
	pts.append(Vector3(_wing_home.x, _wing_home.y + 300.0, _wing_home.z))
	var bid: String = str((w as Dictionary).get("aircraft", ""))
	if bid == "":
		var ids: Array = AircraftCatalog.bombers_for_side(side)
		bid = ids[0] if not ids.is_empty() else "he111"
	var n: int = int((w as Dictionary).get("count", 5))
	var start_pos: Vector3 = Vector3(pp.x, alt, pp.z) + dir * 1400.0
	_wing = BomberFormation.spawn(world, bid, side, n, start_pos, WorldCoords.dir_to_heading(dir), pts, float(mission.get("difficulty_hint", 0.5)))
	for m in _wing.members:
		AIFactory.add_marker(hud, m, Color(0.45, 0.85, 1.0))
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "%d bombers of your wing are ahead: join the stream" % n, 4.0)


func _wing_update() -> void:
	if _wing == null or not is_instance_valid(_wing):
		return
	for t in _wing_targets:
		var id: String = str(t["id"])
		var tp: Vector3 = t["pos"]
		var done: Dictionary = _wing_bombed.get(id, {})
		for m in _wing.members:
			if not is_instance_valid(m) or m.state != Aircraft.State.ALIVE:
				continue
			var mid: int = m.get_instance_id()
			if done.has(mid):
				continue
			var vel: Vector3 = m.velocity if m.velocity.length() > 1.0 else m.get_forward() * 100.0
			var h: float = maxf(m.global_position.y - GroundKit.ground_y(tp.x, tp.z), 50.0)
			var fall: float = sqrt(2.0 * h / 30.0)
			var vh: float = Vector2(vel.x, vel.z).length()
			var travel: float = vh / 0.06 * (1.0 - exp(-0.06 * fall))   # bombs shed horizontal speed to drag
			var to_t := Vector2(tp.x - m.global_position.x, tp.z - m.global_position.z)
			if to_t.length() <= travel and to_t.normalized().dot(Vector2(vel.x, vel.z).normalized()) > 0.5:
				done[mid] = true
				_wing_drop_stick(m, vel)
		_wing_bombed[id] = done
	# bombers that have dropped everything and reached the home airfield land out of sight and are removed
	if _wing_home != Vector3.ZERO:
		for m in _wing.members:
			if not is_instance_valid(m) or m.state != Aircraft.State.ALIVE:
				continue
			var dropped_all: bool = true
			for t2 in _wing_targets:
				if not (_wing_bombed.get(str(t2["id"]), {}) as Dictionary).has(m.get_instance_id()):
					dropped_all = false
			if dropped_all and Vector2(m.global_position.x - _wing_home.x, m.global_position.z - _wing_home.z).length() < 1500.0:
				m.queue_free()


## One stick of bombs from a wing bomber (same bomb physics as the player's; they blast, burn and smoke like any other).
func _wing_drop_stick(m: Aircraft, vel: Vector3) -> void:
	var w: Node = get_tree().root.get_node_or_null("Weapons")
	if w == null:
		return
	var dir: Vector3 = vel.normalized()
	for k in 5:
		w.call("drop_bomb", m.global_position + dir * float(k) * 36.0 - Vector3(0, 3, 0), vel, m.team, m, 200.0, 30.0)


# ------------------------------------------------------------------ scripted radio dialogue
var _dlg_t: float = 2.0
var _dlg_done: Dictionary = {}


func _line(key: String, delay: float = 0.0) -> void:
	if _dlg_done.has(key):
		return
	_dlg_done[key] = true
	var sd: String = "axis" if side == "Axis" else "allies"
	var id: String = "mission/%s/%s/%s" % [mission_id, sd, key]
	if not Radio.has_story(id):   # no mission-specific clip: use the generic line for this role (assets/voice/generic/)
		id = "generic/%s/%s/%s" % [{"escort": "strike", "sweep": "defend"}.get(role, role), sd, key]
	Radio.story(id, delay)


## Objectives destroyed so far (strike / strafe) or protected sites lost (defend), from the target groups.
func _count_destroyed(ids: Array) -> int:
	var n: int = 0
	for node in get_tree().get_nodes_in_group("destroyed_target"):
		if str(node.get("target_id")) in ids:
			n += 1
	return n


func _process(delta: float) -> void:
	super._process(delta)
	if not running or mission.is_empty():
		return
	_ev_t -= delta
	if _wing != null and int(Engine.get_process_frames()) % 30 == 0:
		_wing_update()
	if _ev_t <= 0.0 and not _events_pending.is_empty():
		_ev_t = 1.0
		_check_events()
	_dlg_t -= delta
	if _dlg_t > 0.0:
		return
	_dlg_t = 1.0
	_goals_tick()
	_beats_tick()
	if role == "defend":
		var lost: int = _count_destroyed((mission.get("protect", {}) as Dictionary).get(side, []))
		if lost >= 1:
			_line("loss_1")
		if lost >= 2:
			_line("loss_2")
	else:
		var objs: Array = (mission.get("objectives", {}) as Dictionary).get(side, [])
		var done: int = _count_destroyed(objs)
		if done >= 1:
			_line("first")
		if objs.size() >= 3 and done * 2 >= objs.size() and done < objs.size():
			_line("half")
		if done >= objs.size() and objs.size() > 0:
			_line("all")


# ------------------------------------------------------------------ scripted air events (the original scripted-event missions)
## Each event: {kind: ambush|raid|flyby|escort, hostile, aircraft, count, lat, lon, alt_m, trigger_km (real km), label}.
## It fires once, when the player comes within trigger_km of its position.
var _events_pending: Array = []
var _ev_t: float = 3.0
var _ev_kills: int = 0
# Scripted air events are paced: nothing before the player has been flying for a while, and never two at once.
const EVENT_MIN_AIR_S := 45.0     # seconds airborne before the first air event may fire
const EVENT_GAP_S := 75.0         # minimum seconds between air events
var _air_s: float = 0.0
var _gap_s: float = EVENT_GAP_S


func _check_events() -> void:
	if player == null or not is_instance_valid(player):
		return
	var pp: Vector3 = (player as Node3D).global_position
	var done: int = _count_destroyed((mission.get("objectives", {}) as Dictionary).get(side, []))
	if not (player as Aircraft).on_ground:
		_air_s += 1.0              # this runs about once a second
	_gap_s += 1.0
	var paced: bool = _air_s < EVENT_MIN_AIR_S or _gap_s < EVENT_GAP_S
	for e in _events_pending.duplicate():
		if int(e.get("after_done", 0)) > done:
			continue        # return-leg events wait until the targets are hit
		if paced and not (str(e.get("kind", "")) in ["weather", "message"]):
			continue        # too soon after take-off / after the last air event
		var wp: Vector3 = WorldCoords.latlon_to_world(float(e["lat"]), float(e["lon"]))
		var reach: float = float(e.get("trigger_km", 20.0)) * 1000.0 / WorldCoords.HORIZ_COMPRESSION
		if Vector2(pp.x - wp.x, pp.z - wp.z).length() < reach:
			_events_pending.erase(e)
			if not (str(e.get("kind", "")) in ["weather", "message"]):
				_gap_s = 0.0
			_fire_event(e, wp, pp)
			if not (str(e.get("kind", "")) in ["weather", "message"]):
				break           # one air event per pass


func _event_target_pos(pp: Vector3) -> Vector3:
	var objs: Array = (mission.get("objectives", {}) as Dictionary).get(side, [])
	for oid in objs:
		for t in get_tree().get_nodes_in_group("mission_target"):
			if str(t.get("target_id")) == str(oid) and t is Node3D:
				return (t as Node3D).global_position
	var fwd: Vector3 = -(player as Node3D).global_transform.basis.z
	fwd.y = 0.0
	return pp + fwd.normalized() * 8000.0


func _fire_event(e: Dictionary, wp: Vector3, pp: Vector3) -> void:
	var kind0: String = str(e.get("kind", ""))
	if kind0 == "weather" or kind0 == "message":
		# unexpected conditions: the weather turns, or the crew spots something ahead
		var ops0: String = "Operations Room" if side == "Allies" else "Ground Control"
		if kind0 == "weather":
			WeatherManager.set_weather(str(e.get("weather", "overcast")), 25.0)
		if e.has("text"):
			Radio.say(str(e.get("speaker", "Crew")), str(e["text"]), Radio.Kind.CONTROL, 0.0, "", true)
		if hud and hud.has_method("show_message") and e.has("label"):
			hud.call("show_message", str(e["label"]), 3.5)
		return
	var id: String = str(e.get("aircraft", "spitfire"))
	# The aircraft's own side decides who flies it (two-sided missions share one event list); hostile = not the player's side.
	var hostile: bool = bool(e.get("hostile", false))
	var team: String = AircraftCatalog.opposite(side) if hostile else side
	if AircraftCatalog.ids_for_side("Axis").has(id) != AircraftCatalog.ids_for_side("Allies").has(id):
		team = "Axis" if AircraftCatalog.ids_for_side("Axis").has(id) else "Allies"
		hostile = team != side
	var count: int = clampi(int(e.get("count", 4)), 1, 8)
	var y: float = maxf(float(e.get("alt_m", 2500)) * WorldCoords.VERTICAL_SCALE, GroundKit.ground_y(wp.x, wp.z) + 700.0)
	# The original group's start point may be behind the player or right on top of them: bring such a group in ahead.
	var fwd0: Vector3 = -(player as Node3D).global_transform.basis.z
	fwd0.y = 0.0
	fwd0 = fwd0.normalized() if fwd0.length() > 0.1 else Vector3(0, 0, -1)
	var rel0: Vector3 = wp - pp
	rel0.y = 0.0
	if rel0.length() < 3500.0 or fwd0.dot(rel0.normalized()) < 0.2:
		var right0 := Vector3(-fwd0.z, 0.0, fwd0.x)
		wp = pp + fwd0 * (8000.0 if hostile else 5000.0) + right0 * randf_range(-2500.0, 2500.0)
		y = maxf(pp.y + randf_range(-150.0, 250.0), GroundKit.ground_y(wp.x, wp.z) + 500.0)
	var start := Vector3(wp.x, y, wp.z)
	var goal: Vector3 = pp if hostile else _event_target_pos(pp)
	var dir: Vector3 = goal - start
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 1.0 else Vector3(0, 0, -1)
	var hdg: float = WorldCoords.dir_to_heading(dir)
	var right := Vector3(-dir.z, 0, dir.x)
	var made: Array = []
	if AircraftCatalog.is_bomber(id):
		var route: Array[Vector3] = [start + dir * 9000.0, start + dir * 30000.0]
		var f: BomberFormation = BomberFormation.spawn(world, id, team, count, start, hdg, route, 0.5)
		for m in f.members:
			made.append(m)
	else:
		for i in count:
			var off: Vector3 = right * (float(i % 4) - 1.5) * 160.0 - dir * float(i / 4) * 170.0
			var ac: Aircraft = AIFactory.spawn(world, id, team, start + off, hdg, -1.0, 0.5, AIPilot.Role.FIGHTER)
			made.append(ac)
			if hostile:
				var pilot: AIPilot = AIFactory.pilot_of(ac)
				if pilot != null:
					pilot.detect_range = 6500.0
					pilot.patrol_center = pp
	for ac2 in made:
		AIFactory.add_marker(hud, ac2, Color(1.0, 0.3, 0.2) if hostile else Color(0.4, 0.8, 1.0))
		if hostile:
			(ac2 as Aircraft).destroyed.connect(_on_event_enemy_down)
	var what: String = "%d x %s" % [made.size(), id.to_upper()]
	var ops: String = "Operations Room" if side == "Allies" else "Ground Control"
	match str(e.get("kind", "")):
		"ambush":
			Radio.say(ops, "Bandits! %s coming for you. Break and engage." % what, Radio.Kind.CONTROL, 0.0, "", true)
		"raid":
			Radio.say(ops, "Enemy bombers ahead: %s. Take them down." % what, Radio.Kind.CONTROL, 0.0, "", true)
		"escort":
			Radio.say(ops, "Friendly bombers in the area: %s. Keep the sky clear." % what, Radio.Kind.CONTROL)
		_:
			Radio.say(ops, "Friendly fighters joining: %s." % what, Radio.Kind.CONTROL)
	if hud and hud.has_method("show_message") and hostile:
		hud.call("show_message", "ENEMY AIRCRAFT: " + what, 3.0)


func _on_event_enemy_down(ac: Aircraft, killer: Node) -> void:
	var by_player: bool = killer != null and (killer == player or (killer is Aircraft and (killer as Aircraft).player_controlled))
	if not by_player:
		return
	_ev_kills += 1
	if inner != null and is_instance_valid(inner):
		inner.add_score(150 if ac.is_in_group("bomber") else 100)


func stop() -> void:
	super.stop()
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	if inner != null and is_instance_valid(inner):
		inner.stop()


# ------------------------------------------------------------------ objectives: the primary task and two bonuses
## The bonus objectives (MissionBrief.bonuses) are tracked from facts gathered once a second; the objective card
## shows at the start and for a while whenever something changes, then gets out of the way.
const CARD_SHOW_S := 30.0
var _bonuses: Array = []
var _bonus_state: Dictionary = {}       # bonus id -> "done" | "lost" (told to the pilot once)
var _objective_text: String = ""
var _card: Label
var _card_show_t: float = CARD_SHOW_S
var _lives_lost: int = 0


## The facts MissionBrief scores the sortie from. `st` is the inner mode's stats (live or final).
func _facts(st: Dictionary) -> Dictionary:
	var f: Dictionary = st.duplicate()
	f["time"] = elapsed
	var air: int = int(player_kills["air"]) + int(player_kills["v1"])
	if inner != null and is_instance_valid(inner):
		air = maxi(air, int(inner.player_kills["air"]) + int(inner.player_kills["v1"]))
	f["air_kills"] = air
	f["ground_kills"] = int(player_kills["ground"]) + int(player_kills["ships"])
	var pl: Aircraft = (player as Aircraft) if player != null and is_instance_valid(player) else null
	var hf: float = 0.0
	if pl != null and pl.stats != null and pl.state == Aircraft.State.ALIVE:
		hf = clampf(pl.health / maxf(pl.stats.max_health, 1.0), 0.0, 1.0)
	f["health_frac"] = hf
	var lost: int = _lives_lost
	if inner != null and is_instance_valid(inner):
		var dv: Variant = inner.get("deaths")
		if dv != null:
			lost = maxi(lost, int(dv))
		var pd: Variant = inner.get("_player_dead")
		if pd != null and bool(pd):
			lost = maxi(lost, 1)
		if inner is BombingMode:
			var dropped: int = 0
			var hit: int = 0
			for e in (inner as BombingMode)._bda:
				for mk in (e["marks"] as Array):
					dropped += 1
					if bool(mk["hit"]):
						hit += 1
			f["bombs_dropped"] = dropped
			f["bombs_hit"] = hit
			f["targets_destroyed"] = (inner as BombingMode)._destroyed_count
			f["targets"] = (inner as BombingMode).targets.size()
		elif inner is DefendMode:
			f["protected_alive"] = (inner as DefendMode)._alive_protected().size()
			f["protected"] = (inner as DefendMode).protected_nodes.size()
		elif inner is EscortMode:
			var fm: BomberFormation = (inner as EscortMode).formation
			f["bombers_alive"] = fm.alive_count() if fm != null and is_instance_valid(fm) else 0
			f["bombers"] = (inner as EscortMode)._count
	f["lives_lost"] = lost
	return f


func _build_objective_card() -> void:
	_card = Label.new()
	_card.add_theme_color_override("font_color", Color(0.95, 0.93, 0.82))
	if hud and hud.has_method("add_widget"):
		hud.call("add_widget", _card)
	if _objective_text == "":
		_objective_text = MissionBrief.task_line(mission, side)


## Text of the objective card: heading, the task, then one line per bonus with its state.
func objective_card_text(f: Dictionary) -> String:
	var lines: Array = ["OBJECTIVES", _objective_text]
	for b in _bonuses:
		var st: String = str(_bonus_state.get(str(b["id"]), ""))
		var note: String = MissionBrief.bonus_progress(b, f)
		var tag: String = "BONUS"
		if st == "done":
			tag = "DONE"
			note = ""
		elif st == "lost":
			tag = "MISSED"
		lines.append("%s  %s%s" % [tag, str(b["short"]), ("   (%s)" % note) if note != "" else ""])
	return "\n".join(PackedStringArray(lines))


func _goals_tick() -> void:
	if _card == null or not is_instance_valid(_card) or inner == null or not is_instance_valid(inner):
		return
	var f: Dictionary = _facts(inner.live_stats())
	f["success"] = true          # "would this bonus stand if the mission ended well now?"
	for b in _bonuses:
		var id: String = str(b["id"])
		if _bonus_state.has(id) and _bonus_state[id] == "lost":
			continue
		if MissionBrief.bonus_lost(b, f):
			_bonus_state[id] = "lost"
			_card_show_t = 12.0
			if hud and hud.has_method("show_message"):
				hud.call("show_message", "Bonus missed: %s" % str(b["short"]), 3.0)
			continue
		# counted bonuses are settled as soon as the count is reached; the rest are judged when the mission ends
		if id in ["air_kill", "air_kills", "bomber_kills", "ground_kills"] and not _bonus_state.has(id) and MissionBrief.bonus_done(b, f):
			_bonus_state[id] = "done"
			_card_show_t = 12.0
			if hud and hud.has_method("show_message"):
				hud.call("show_message", "Bonus achieved: %s" % str(b["short"]), 3.0)
		if id == "par" and not _par_warned and float(b["need"]) - elapsed < 300.0 and elapsed > 60.0:
			_par_warned = true
			_card_show_t = 12.0
			if hud and hud.has_method("show_message"):
				hud.call("show_message", "Five minutes left for the commendation", 3.5)
	_card_show_t -= 1.0
	var want: String = objective_card_text(f) if _card_show_t > 0.0 else ""
	if _card.text != want:
		_card.text = want


# ------------------------------------------------------------------ pacing: calls that mark the stages of the sortie
## Strike and strafe sorties get a call on reaching the target area, a pair of fighters sent after the player on
## the way out of a defended target, and a call with the home field in sight.
const TARGET_AREA_KM := 12.0
const HOME_SIGHT_KM := 9.0
const PURSUIT_DELAY_S := 18.0
var _par_warned: bool = false
var _beat_area: bool = false
var _beat_home: bool = false
var _beat_pursuit: bool = false
var _rtb_s: float = 0.0


func _ops_name() -> String:
	return "Operations Room" if side == "Allies" else "Ground Control"


func _beats_tick() -> void:
	if not (role in ["strike", "strafe"]) or inner == null or not is_instance_valid(inner):
		return
	var pl: Aircraft = (player as Aircraft) if player != null and is_instance_valid(player) else null
	if pl == null or pl.state != Aircraft.State.ALIVE:
		return
	var rtb: bool = inner is BombingMode and (inner as BombingMode).phase == "rtb"
	var np: Variant = inner.nav_point()
	if np == null:
		return
	var km: float = Vector2((np as Vector3).x - pl.global_position.x, (np as Vector3).z - pl.global_position.z).length() * WorldCoords.HORIZ_COMPRESSION / 1000.0
	if not rtb:
		if not _beat_area and km < TARGET_AREA_KM and elapsed > 20.0 and not pl.on_ground:
			_beat_area = true
			var txt: String = "Target area coming up, ten kilometres. The flak will be waiting: make the first run count."
			if role == "strafe":
				txt = "You are nearly on them. Come in low and fast, and do not fly the same line twice."
			Radio.say(_ops_name(), txt, Radio.Kind.CONTROL)
			if hud and hud.has_method("show_message"):
				hud.call("show_message", "Target area ahead", 3.0)
		return
	_rtb_s += 1.0
	if not _beat_pursuit and _rtb_s >= PURSUIT_DELAY_S:
		_beat_pursuit = true
		if not bool(mission.get("no_fighters", false)) and float(mission.get("difficulty_hint", 0.5)) >= 0.4 and km > HOME_SIGHT_KM:
			_spawn_pursuit(pl)
	if not _beat_home and km < HOME_SIGHT_KM:
		_beat_home = true
		Radio.say(_ops_name(), "We have you in sight. The circuit is clear: bring her in.", Radio.Kind.CONTROL)
		if hud and hud.has_method("show_message"):
			hud.call("show_message", "Home field ahead: land, or pass low over the runway", 4.5)


## A fighter type the other side flies in this mission (its own list, else a scripted hostile fighter, else the default).
func pursuit_type() -> String:
	var enemy: String = AircraftCatalog.opposite(side)
	for s in mission.get("sides", []):
		if str(s.get("side", "")) == enemy:
			for id in s.get("aircraft", []):
				if not AircraftCatalog.is_bomber(str(id)) and AircraftCatalog.ids_for_side(enemy).has(str(id)):
					return str(id)
	for e in mission.get("events", []):
		if e is Dictionary and (e as Dictionary).has("aircraft"):
			var eid: String = str(e["aircraft"])
			if AircraftCatalog.ids_for_side(enemy).has(eid) and not AircraftCatalog.ids_for_side(side).has(eid) and not AircraftCatalog.is_bomber(eid):
				return eid
	return AircraftCatalog.default_fighter(enemy)


## Two enemy fighters come up from the target and chase the player on the way home.
func _spawn_pursuit(pl: Aircraft) -> void:
	var id: String = pursuit_type()
	var enemy: String = AircraftCatalog.opposite(side)
	var fwd: Vector3 = Vector3(pl.get_forward().x, 0.0, pl.get_forward().z)
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3(0, 0, -1)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var pp: Vector3 = pl.global_position
	var skill: float = clampf(float(mission.get("difficulty_hint", 0.5)), 0.2, 0.9)
	for i in 2:
		var pos: Vector3 = pp - fwd * 5200.0 + right * (float(i) - 0.5) * 320.0
		pos.y = maxf(pp.y + 250.0, GroundKit.ground_y(pos.x, pos.z) + 500.0)
		var ac: Aircraft = AIFactory.spawn(world, id, enemy, pos, WorldCoords.dir_to_heading(fwd), -1.0, skill, AIPilot.Role.FIGHTER)
		var pilot: AIPilot = AIFactory.pilot_of(ac)
		if pilot != null:
			pilot.detect_range = 8000.0
			pilot.patrol_center = pp
		AIFactory.add_marker(hud, ac, Color(1.0, 0.3, 0.2))
		ac.destroyed.connect(_on_event_enemy_down)
	Radio.say(_ops_name(), "Fighters are up from the target and coming after you. Do not hang about.", Radio.Kind.CONTROL, 0.0, "", true)
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "Enemy fighters in pursuit", 3.0)
