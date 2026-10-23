class_name OpsRoom
extends Node
## Dynamic free flight: the Ops Room (RAF Sector Control / Luftwaffe Jafü) calls the player on the radio every
## `interval` seconds (10 minutes by default) with a new tasking against a real place on the map. A waypoint goes
## on the compass and the minimap, a panel shows the job and its progress, and the Ops Room calls again when it
## is done, failed or overtaken. Owned by FreeFlightMode (cfg "taskings").
##
## Tasking kinds (picked to suit the aircraft: bombers strike, fighters intercept, fighter-bombers do both):
##   strike    bomb / rocket a real factory, rail yard, port, radar, bridge, battery or V-1 site (WorldPopulator target)
##   airfield  shoot up an enemy airfield: destroy parked aircraft and installations
##   convoy    road convoy on the move near an enemy town
##   train     supply train on the line near an enemy town or rail yard
##   shipping  merchant convoy with escorts at sea (a real convoy route)
##   eboats    a flotilla of fast attack boats heading out of an enemy port
##   intercept an enemy bomber raid (with escort) heading for a friendly town or airfield - stop it before it bombs
##   cover     enemy dive bombers going for one of our coastal convoys
##   sweep     enemy fighters patrolling over their territory - clear the sky
##   rescue    a pilot in a dinghy - find him, circle low until the rescue launch gets a fix
##   recce     photograph an enemy site (low, wings level), then bring the pictures home
##
## Since v6.9:
##   * ONE HIT on any of a tasking's targets completes it (Weapons.player_hit), destroying it still counts too.
##   * Rendezvous: some jobs start with an RV where a friendly section waits and then joins you as wingmen;
##     "escort" jobs (fighters) meet a friendly bomber formation there and see it to its target.
##   * Intelligence: flying low past an enemy site or airfield reports it; reports become later taskings.
##   * Pressure: missed jobs raise enemy supply (more flak on later jobs), air threat (bigger escorts, bounces)
##     and, for the RAF, the V-1 threat (FlyingBomb launches toward London: "Diver, diver!").
##   * Mid-job twists (raid changes course, deadlines, reinforced flak, scrambling fighters, an E-boat going for
##     the dinghy...), night intruder jobs and searchlights, fog that scrubs a job, and scrambles when parked.
##   * Every result goes into the PilotLog (rank, decorations, logbook - key J).
## Debug: --ops-first=S (first call after S seconds), --ops-interval=S, --ops-kind=<kind>, --ops-auto (auto-complete
## each tasking a few seconds after it is issued, for soak tests), --ops-test (cycle every kind and print results).

signal tasking_started(info: Dictionary)
signal tasking_finished(info: Dictionary, success: bool)

const KINDS := ["strike", "airfield", "convoy", "train", "shipping", "eboats", "intercept", "cover", "sweep", "rescue", "recce", "escort", "intruder"]
const GROUND_KINDS := ["convoy", "train", "shipping", "eboats"]
const AIR_KINDS := ["intercept", "cover", "sweep", "escort"]
const MIN_RANGE: float = 12000.0       # world units (= metres horizontally)
const MAX_RANGE: float = 90000.0       # preferred band; beyond it the nearest candidate (up to FAR_LIMIT) is used
const FAR_LIMIT: float = 180000.0
const STALE_AFTER: float = 900.0       # at the next call, a tasking older than 15 minutes (plus the transit time to it) is replaced
const TRANSIT_SPEED: float = 70.0      # u/s, slow cruise: the transit allowance added to a far tasking's stale time

var interval: float = 600.0
var side: String = "Allies"
var enemy: String = "Axis"
var difficulty: float = 0.5
var world: Node3D
var player: Aircraft
var hud: Node
var mode: ModeBase

var active: Dictionary = {}            # the current tasking (empty = none)
var completed: int = 0
var failed: int = 0
var _pop: WorldPopulator
var _next_t: float = 60.0
var _last_kind: String = ""
var _label: Label
var _label_t: float = 0.0
var _scan_t: float = 0.0
var _counted: Dictionary = {}
var _forced: String = ""
var _auto: bool = false
var _test: bool = false
var _test_i: int = 0
var _cities: Array = []                # [{name, pos, size}]
var _rng := RandomNumberGenerator.new()
# pressure from missed jobs (see header)
var supply: int = 0
var air_threat: int = 0
var v1_threat: int = 0
var _v1_t: float = 240.0
var _v1s: Array = []
var _intel: Array = []                 # reported sites waiting to become taskings: {kind, id, name, pos}
var _reported: Dictionary = {}
var _intel_t: float = 3.0
var _intel_cd: float = 0.0
var _parked_t: float = 0.0
var _scramble_next: bool = false
var _air_t: float = 0.0
var _friends: Array = []               # the RV section / escorted bombers of the current job
var _log_ui: CanvasLayer
var _log_lbl: Label
var _weather_restore: String = ""
var _band_lo: float = MIN_RANGE         # range band for choosing targets (a follow-up job looks closer to hand)
var _band_hi: float = MAX_RANGE
var _followup: bool = false             # the next call is a "while you're up there" job near the last one
var _streak: int = 0                    # jobs done in a row without a miss
var _await_rearm: bool = false          # out of ammunition: no new jobs until the player has landed and rearmed


func setup(p_world: Node3D, p_player: Aircraft, p_hud: Node, p_mode: ModeBase, p_side: String, p_difficulty: float) -> void:
	world = p_world
	player = p_player
	hud = p_hud
	mode = p_mode
	side = p_side
	enemy = GroundKit.enemy_of(side)
	difficulty = p_difficulty
	_rng.randomize()
	_pop = WorldPopulator.ensure(world)
	_next_t = 60.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ops-first="):
			_next_t = float(a.substr(12))
		elif a.begins_with("--ops-interval="):
			interval = float(a.substr(15))
		elif a.begins_with("--ops-kind="):
			_forced = a.substr(11)
	_auto = OS.get_cmdline_user_args().has("--ops-auto")
	_test = OS.get_cmdline_user_args().has("--ops-test")
	if _test:
		_auto = true
	if _pop != null:
		for c in _pop.loc.get("cities", []):
			if bool(c.get("in_bounds", true)):
				_cities.append({"name": str(c.get("name", c["id"])), "pos": WorldCoords.latlon_to_world(float(c["lat"]), float(c["lon"])), "size": int(c.get("size", 1))})
	_build_label()
	_build_logbook_ui()
	Weapons.player_hit.connect(_on_player_hit)
	Weapons.player_kill.connect(_on_player_kill)
	var c: Dictionary = PilotLog.career(side)
	var aw: Array = PilotLog.award_names(side, c)
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "%s %s%s   (J: logbook)" % [PilotLog.rank_of(side, int(c["points"])), Radio.player_callsign,
			("  -  " + aw[-1]) if not aw.is_empty() else ""], 5.0)
	_log("[ops] Ops Room on: side %s, every %d s, first call in %d s%s" % [side, int(interval), int(_next_t), " (test cycle)" if _test else ""])


## print, and in test runs also append to res://build/ops_events.log (flushed at once: a redirected stdout is
## block-buffered on Windows and loses its tail when the process is stopped).
func _log(msg: String) -> void:
	print(msg)
	if _test or OS.get_cmdline_user_args().has("--ops-verbose"):
		var path: String = ProjectSettings.globalize_path("res://build/ops_events.log")
		var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line(msg)
			f.close()


func _exit_tree() -> void:
	_clear_active()
	if _label != null and is_instance_valid(_label):
		_label.queue_free()


# ------------------------------------------------------------------ the clock

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or player.state != Aircraft.State.ALIVE:
		return
	# scramble: sitting on the ground with nothing to do brings an urgent call
	if player.on_ground and player.speed < 3.0 and active.is_empty() and not _test:
		_parked_t += delta
		if _parked_t > 35.0 and _next_t > 8.0:
			_scramble_next = true
			_next_t = 0.0
	else:
		_parked_t = 0.0
	# (hours flown and kills are written to the logbook by ModeBase for every mode)
	_intel_scan(delta)
	_v1_tick(delta)
	_ammo_check()
	_next_t -= delta
	if _next_t <= 0.0:
		_next_t = interval
		if _await_rearm:
			_next_t = 20.0          # nothing new until they've been home for more ammunition
		elif active.is_empty():
			_issue()
		elif float(active["age"]) > float(active.get("stale_after", STALE_AFTER)):
			_say("Cancel the last tasking. Something more urgent has come up.")
			_end_active(false, true, true)      # a dispatcher cancellation is a scrub, not a miss
			_issue()
	if not active.is_empty():
		active["age"] = float(active["age"]) + delta
		_scan_t -= delta
		if _scan_t <= 0.0:
			_scan_t = 0.25
			_update_active(0.25)
	_label_t -= delta
	if _label_t <= 0.0:
		_label_t = 0.25
		_refresh_label()


## Out of ammunition on an attack job: scrub it and send the pilot home to rearm; resume once rearmed.
func _ammo_check() -> void:
	if _test or _auto:
		return
	var w: Variant = player.get("weapons")
	var rockets: int = int(w.get("rockets_left")) if w != null else 0
	var empty: bool = player.ammo <= 0 and player.bombs <= 0 and rockets <= 0
	if _await_rearm:
		if not empty:
			_await_rearm = false
			_say("Rearmed? Good. Stand by, new orders shortly." if side == "Axis" else "Rearmed? Good. Stand by, we'll have something for you shortly.", 0.0, "rearmed_1")
			_next_t = minf(_next_t, 45.0)
		return
	if not empty or active.is_empty() or str(active.get("kind", "")) in ["rescue", "recce"]:
		return
	_await_rearm = true
	_say("You are out of ammunition. Abort - go home and rearm, we will have more for you." if side == "Axis" else "You're out of ammunition. Scrub that one - go home and rearm, and we'll have more for you.", 0.0, "winchester_1")
	_end_active(false, true, true)


## Where the compass / minimap waypoint points (FreeFlightMode.nav_point forwards here).
func nav_point() -> Variant:
	if _await_rearm and active.is_empty():
		return _home_airfield()
	if active.is_empty():
		return null
	var stage: String = str(active.get("stage", ""))
	if stage == "home":
		return active.get("home", null)
	if stage == "rv":
		return active.get("rv", null)
	var lead: Variant = active.get("track")
	if lead != null and is_instance_valid(lead):
		if lead is BomberFormation:
			var f: BomberFormation = lead
			if f.leader != null and is_instance_valid(f.leader):
				return f.leader.global_position
		elif lead is Convoy:
			return (lead as Convoy).get_center()
		elif lead is Train:
			return (lead as Train).get_center()
		elif lead is Node3D:
			return (lead as Node3D).global_position
	return active.get("pos", null)


# ------------------------------------------------------------------ choosing a tasking

func _role() -> String:
	if AircraftCatalog.is_bomber(String(player.stats.id)):
		return "bomber"
	if player.stats.bombs > 0 or player.stats.rockets > 0:
		return "fighter_bomber"
	return "fighter"


func _is_night() -> bool:
	return TimeOfDay.light_level < 0.32


func _weights() -> Dictionary:
	var w: Dictionary
	match _role():
		"bomber":
			w = {"strike": 5, "shipping": 3, "airfield": 2, "train": 1, "recce": 1}
		"fighter_bomber":
			w = {"strike": 3, "airfield": 2, "convoy": 2, "train": 2, "shipping": 2, "eboats": 1, "intercept": 2, "cover": 1, "sweep": 1, "rescue": 1, "recce": 1, "escort": 1}
		_:
			w = {"intercept": 4, "cover": 2, "sweep": 3, "convoy": 2, "train": 2, "airfield": 1, "eboats": 2, "rescue": 2, "recce": 2, "escort": 3}
	if _is_night():
		# by night: no photographs, no dinghy searches, intruders over their airfields instead
		w.erase("recce")
		w.erase("rescue")
		w.erase("escort")
		if _role() != "bomber":
			w["intruder"] = 4
	return w


func _pick_kind() -> String:
	if _forced != "":
		return _forced
	if _test:
		var k: String = KINDS[_test_i % KINDS.size()]
		_test_i += 1
		return k
	var w: Dictionary = _weights()
	var total: float = 0.0
	for k in w.keys():
		if k != _last_kind:
			total += float(w[k])
	var r: float = _rng.randf() * total
	for k in w.keys():
		if k == _last_kind:
			continue
		r -= float(w[k])
		if r <= 0.0:
			return k
	return w.keys()[0]


func _issue() -> void:
	var scramble: bool = _scramble_next
	_scramble_next = false
	_parked_t = 0.0
	var followup: bool = _followup and not scramble
	_followup = false
	if followup:
		_band_lo = 4000.0
		_band_hi = 40000.0
	_issue_inner(scramble, followup)
	_band_lo = MIN_RANGE
	_band_hi = MAX_RANGE


func _issue_inner(scramble: bool, followup: bool) -> void:
	var from_intel: Dictionary = {}
	if not scramble and not _intel.is_empty() and _forced == "" and not _test and _rng.randf() < 0.6:
		from_intel = _intel.pop_front()
	for attempt in 6:
		var kind: String = _pick_kind()
		if scramble:
			kind = "intercept"
		elif not from_intel.is_empty() and attempt == 0:
			kind = str(from_intel["kind"])
		var info: Dictionary = {}
		match kind:
			"strike": info = _make_strike(str(from_intel.get("id", "")) if attempt == 0 else "")
			"airfield": info = _make_airfield(from_intel if attempt == 0 and from_intel.has("site") else {})
			"escort": info = _make_escort()
			"intruder": info = _make_intruder()
			"convoy": info = _make_convoy()
			"train": info = _make_train()
			"shipping": info = _make_shipping()
			"eboats": info = _make_eboats()
			"intercept": info = _make_raid(false)
			"cover": info = _make_raid(true)
			"sweep": info = _make_sweep()
			"rescue": info = _make_rescue()
			"recce": info = _make_recce()
		if info.is_empty():
			if _test or OS.get_cmdline_user_args().has("--ops-verbose"):
				_log("[ops] no %s tasking available (player at %s, pop %s, targets %d)" % [kind, str(_ppos()), str(_pop != null),
					(_pop.targets_for_side(enemy, []).size() if _pop != null else -1)])
			if _forced != "":
				_forced = ""          # the forced kind has nothing in range: fall back to the normal mix
			continue
		info["kind"] = kind
		info["age"] = 0.0
		# a far job is not stale before the pilot has had time to fly there (game time, so time warp cannot time it out)
		var _far: float = _dist(info["pos"]) if info.get("pos") is Vector3 else 0.0
		info["stale_after"] = STALE_AFTER + (_far / TRANSIT_SPEED) * 1.5
		if not info.has("hit"):
			info["hit"] = info.get("nodes", []).duplicate()
		if not from_intel.is_empty() and attempt == 0:
			info["from_intel"] = str(from_intel.get("name", ""))
		if scramble:
			info["scramble"] = true
			info["scramble_t"] = 0.0
		if followup:
			info["followup"] = true
		# a twist once in a while, and (by day, in fair weather) a chance of fog scrubbing the job
		info["twist_at"] = _rng.randf_range(90.0, 240.0) if (_rng.randf() < 0.5 or OS.get_cmdline_user_args().has("--ops-twist")) else -1.0
		var wx: String = str(WeatherManager.get("current")) if WeatherManager != null else "clear"
		info["fog_at"] = _rng.randf_range(200.0, 400.0) if (not _test and not _is_night() and wx in ["clear", "scattered"] and _rng.randf() < 0.08) else -1.0
		info["bounce_done"] = false
		_pressure_flak(info)
		if kind != "escort" and not scramble:
			_maybe_rv(info)
		active = info
		_last_kind = kind
		_friends = info.get("friends", [])
		_announce(info)
		_add_marker(info)
		tasking_started.emit(info)
		if _test or OS.get_cmdline_user_args().has("--ops-verbose"):
			_log("[ops] issued %s: %s at %s (%.1f km)" % [kind, str(info.get("place", "")), str(info.get("pos")), _dist_km(info["pos"])])
		return
	if not followup:
		_say("Nothing for you at the moment. Carry on with your patrol.", 0.0, "nothing_1")


# ---- helpers

func _ppos() -> Vector3:
	return player.global_position


func _dist(p: Vector3) -> float:
	return Vector2(p.x - _ppos().x, p.z - _ppos().z).length()


func _dist_km(p: Vector3) -> float:
	return _dist(p) * WorldCoords.HORIZ_COMPRESSION / 1000.0


func _bearing(p: Vector3) -> int:
	var d: Vector3 = p - _ppos()
	return int(round(WorldCoords.dir_to_heading(Vector3(d.x, 0.0, d.z)))) % 360


## A name for a place: "Saint-Omer" or "12 km north-east of Calais".
func _place_name(p: Vector3) -> String:
	var best: Dictionary = {}
	var bd: float = INF
	for c in _cities:
		var d: float = Vector2(p.x - c["pos"].x, p.z - c["pos"].z).length()
		var w: float = d / (0.8 + 0.2 * float(c["size"]))      # bigger towns win slightly further out
		if w < bd:
			bd = w
			best = c
	if best.is_empty():
		return "grid %d / %d" % [int(p.x / 1000.0), int(p.z / 1000.0)]
	var dd: float = Vector2(p.x - best["pos"].x, p.z - best["pos"].z).length()
	if dd < 3500.0:
		return "near " + str(best["name"])
	var hd: float = WorldCoords.dir_to_heading(Vector3(p.x - best["pos"].x, 0.0, p.z - best["pos"].z))
	var dirs: Array = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	if GroundKit.raw_y(p.x, p.z) < -4.0:
		return "%d km %s of %s, out at sea" % [int(round(dd / 1000.0)), dirs[int(round(hd / 45.0)) % 8], str(best["name"])]
	return "%d km %s of %s" % [int(round(dd / 1000.0)), dirs[int(round(hd / 45.0)) % 8], str(best["name"])]


func _in_range(p: Vector3, lo: float = -1.0, hi: float = -1.0) -> bool:
	if lo < 0.0:
		lo = _band_lo
	if hi < 0.0:
		hi = _band_hi
	var d: float = _dist(p)
	return d >= lo and d <= hi


## Candidates sorted so that one is chosen at random among those in range (falling back to the nearest).
func _choose(cands: Array, pos_of: Callable, lo: float = -1.0, hi: float = -1.0) -> Variant:
	if lo < 0.0:
		lo = _band_lo
	if hi < 0.0:
		hi = _band_hi
	var ok: Array = []
	for c in cands:
		if _in_range(pos_of.call(c), lo, hi):
			ok.append(c)
	if not ok.is_empty():
		return ok[_rng.randi() % ok.size()]
	var best: Variant = null
	var bd: float = INF
	for c in cands:
		var d: float = _dist(pos_of.call(c))
		if d >= lo * 0.5 and d < bd:
			bd = d
			best = c
	return best if bd < maxf(hi * 1.6, FAR_LIMIT) else null


func _container(name: String) -> Node3D:
	var n := Node3D.new()
	n.name = "Ops_" + name
	world.add_child(n)
	return n


func _ground_pt(p: Vector3) -> Vector3:
	return Vector3(p.x, GroundKit.ground_y(p.x, p.z), p.z)


## Enemy airfields that lie on the enemy's side of the front (the airfield list mixes eras: RAF fields in
## liberated Belgium must not become targets for a 1940 Luftwaffe pilot).
func _enemy_airfields() -> Array:
	if _pop == null:
		return []
	return _pop.airfield_sites(_enemy_af_force()).filter(func(a: Dictionary) -> bool: return GroundKit.side_at(a["pos"]) == enemy)


func _enemy_af_force() -> String:
	return "Luftwaffe" if enemy == "Axis" else "RAF"


func _own_af_force() -> String:
	return "RAF" if side == "Allies" else "Luftwaffe"


func _nearest_enemy_airfield(p: Vector3) -> Vector3:
	var best: Vector3 = p + Vector3(0.0, 0.0, 30000.0 if enemy == "Axis" else -30000.0)
	var bd: float = INF
	if _pop != null:
		for a in _pop.airfield_sites(_enemy_af_force()):
			var d: float = (a["pos"] as Vector3).distance_to(p)
			if d < bd:
				bd = d
				best = a["pos"]
	return best


func _home_airfield() -> Vector3:
	var best: Vector3 = _ppos()
	var bd: float = INF
	if _pop != null:
		for a in _pop.airfield_sites(_own_af_force()):
			var d: float = _dist(a["pos"])
			if d < bd:
				bd = d
				best = a["pos"]
	return best


# ---- the tasking builders. Each returns {} when nothing fits.

func _make_strike(force_id: String = "") -> Dictionary:
	if _pop == null:
		return {}
	var types: Array = ["factory", "rail_yard", "port", "radar", "bridge", "battery", "v1_site", "oil_depot", "oil"]
	var ids: Array = _pop.targets_for_side(enemy, types)
	# with the V-1 threat up, Ops wants the launch sites
	if v1_threat > 0 and side == "Allies" and _rng.randf() < 0.6:
		var v1ids: Array = _pop.targets_for_side(enemy, ["v1_site"])
		if not v1ids.is_empty():
			ids = v1ids
	var pick: Variant = force_id if force_id != "" and not _pop.get_target_info(force_id).is_empty() else _choose(ids, func(id: String) -> Vector3: return _pop.get_target_info(id)["pos"])
	if pick == null:
		return {}
	var info: Dictionary = _pop.get_target_info(pick)
	var n: Node = _pop.spawn_target(pick)
	if n == null:
		return {}
	var p: Vector3 = info["pos"]
	var root: Node3D = null
	if _is_night():
		# by night the target is ringed with searchlights
		root = _container("lights")
		_pop._defences(root, _ground_pt(p), enemy, 0, 1, 3, 0, 700.0, _rng.randi())
	return {"title": "Strike: %s" % str(info["name"]), "what": str(info["name"]), "type": str(info["type"]), "pos": p,
		"place": _place_name(p), "track": n, "goal": "destroy", "nodes": [n], "points": 1500, "root": root}


func _make_airfield(force: Dictionary = {}) -> Dictionary:
	if _pop == null:
		return {}
	var pick: Variant = force["site"] if force.has("site") else _choose(_enemy_airfields(), func(a: Dictionary) -> Vector3: return a["pos"])
	if pick == null:
		return {}
	var af: Airfield = _pop.get_airfield(str(pick["id"]))
	var p: Vector3 = pick["pos"]
	if af != null:
		p = af.global_position
	return {"title": "Airfield attack: %s" % str(pick["name"]), "what": str(pick["name"]), "pos": p, "place": _place_name(p),
		"goal": "kills", "radius": 2200.0, "need": 5, "got": 0, "points": 1200, "hit_area": true, "af": af}


func _route_near(kind: String, pos: Vector3, max_d: float) -> RoutePath:
	var list: Array = TransportNetwork.routes_near(kind, pos, max_d)
	var good: Array = []
	for r in list:
		if (r as RoutePath).length > 1500.0:
			good.append(r)
	if good.is_empty():
		return null
	return good[_rng.randi() % good.size()]


func _synthetic_route(a: Vector3, dir: Vector3, length: float) -> RoutePath:
	var pts := PackedVector3Array()
	var side_v := Vector3(-dir.z, 0, dir.x)
	for i in 8:
		var t: float = float(i) / 7.0
		pts.append(a + dir * length * t + side_v * sin(t * 5.0) * 60.0)
	return RoutePath.from_points(pts)


## Who holds a place: the side of the nearest airfield, which also has to agree with the front-line test
## (GroundKit.side_at alone puts Dover and Folkestone on the wrong side of its coastline approximation).
func _held_by(p: Vector3) -> String:
	var best: String = GroundKit.side_at(p)
	var bd: float = INF
	if _pop != null:
		for force in ["RAF", "Luftwaffe"]:
			for a in _pop.airfield_sites(force):
				var d: float = Vector2((a["pos"] as Vector3).x - p.x, (a["pos"] as Vector3).z - p.z).length()
				if d < bd:
					bd = d
					best = "Allies" if force == "RAF" else "Axis"
	return best


## An enemy-held town in range (for convoys and trains).
func _enemy_town() -> Variant:
	var towns: Array = _cities.filter(func(c: Dictionary) -> bool: return _held_by(c["pos"]) == enemy and GroundKit.side_at(c["pos"]) == enemy and GroundKit.raw_y(c["pos"].x, c["pos"].z) > 1.0)
	return _choose(towns, func(c: Dictionary) -> Vector3: return c["pos"])


func _make_convoy() -> Dictionary:
	var town: Variant = _enemy_town()
	if town == null:
		return {}
	var c: Vector3 = town["pos"]
	var rp: RoutePath = _route_near("roads", c, 9000.0)
	if rp == null:
		var ang: float = _rng.randf() * TAU
		rp = _synthetic_route(c + Vector3(cos(ang), 0, sin(ang)) * 2500.0, Vector3(cos(ang + 1.6), 0, sin(ang + 1.6)), 4000.0)
	var comps: Array = ["supply", "tanks", "troops", "mixed"]
	var comp: String = comps[_rng.randi() % comps.size()]
	var cl: Vector2 = rp.closest(c)
	var cv: Convoy = Convoy.create(enemy, rp, false, comp, cl.x, _rng.randf_range(7.0, 10.0))
	cv.spacing = 22.0
	var root: Node3D = _container("convoy")
	root.add_child(cv)
	# a light flak escort rides with the bigger columns
	if comp == "tanks" or difficulty > 0.5:
		_pop._defences(root, _ground_pt(cv.get_center()), enemy, 0, 1, 0, 0, 120.0, _rng.randi())
	var what: String = {"supply": "supply lorries", "tanks": "armoured column", "troops": "troop convoy", "mixed": "motor convoy"}[comp]
	return {"title": "Convoy: %s" % what, "what": what, "pos": cv.get_center(), "place": _place_name(cv.get_center()),
		"track": cv, "goal": "destroy", "nodes": [cv], "root": root, "points": 900}


func _make_train() -> Dictionary:
	var c: Vector3 = Vector3.ZERO
	var near_name: String = ""
	if _pop != null:
		var yards: Array = _pop.targets_for_side(enemy, ["rail_yard"])
		var y: Variant = _choose(yards, func(id: String) -> Vector3: return _pop.get_target_info(id)["pos"])
		if y != null:
			c = _pop.get_target_info(y)["pos"]
			near_name = str(_pop.get_target_info(y)["name"])
	if c == Vector3.ZERO:
		var town: Variant = _enemy_town()
		if town == null:
			return {}
		c = town["pos"]
	var rr: RoutePath = _route_near("rails", c, 12000.0)
	if rr == null:
		var ang: float = _rng.randf() * TAU
		rr = _synthetic_route(c + Vector3(cos(ang), 0, sin(ang)) * 3000.0, Vector3(cos(ang + 2.0), 0, sin(ang + 2.0)), 6000.0)
	var cl: Vector2 = rr.closest(c)
	var tr: Train = Train.create(enemy, rr, cl.x, _rng.randf_range(12.0, 17.0))
	var root: Node3D = _container("train")
	root.add_child(tr)
	var what: String = ["ammunition train", "troop train", "fuel train", "goods train"][_rng.randi() % 4]
	return {"title": "Train: %s" % what, "what": what, "pos": tr.get_center(), "place": _place_name(tr.get_center()) if near_name == "" else "out of " + near_name,
		"track": tr, "goal": "destroy", "nodes": [tr], "root": root, "points": 900}


func _make_shipping() -> Dictionary:
	if _pop == null:
		return {}
	var ids: Array = []
	for id in _pop.targets_for_side(enemy, ["convoy_route"]):
		var d: Dictionary = _pop.get_target_info(id).get("data", {})
		if bool(d.get("naval", false)):
			ids.append(id)
	var pick: Variant = _choose(ids, func(id: String) -> Vector3: return _pop.get_target_info(id)["pos"], MIN_RANGE, MAX_RANGE * 1.4)
	if pick == null:
		return {}
	var n: Node = _pop.spawn_target(pick)
	if n == null:
		return {}
	var p: Vector3 = (n as Convoy).get_center() if n is Convoy else _pop.get_target_info(pick)["pos"]
	return {"title": "Shipping strike: %s" % str(_pop.get_target_info(pick)["name"]), "what": "merchant convoy", "pos": p, "place": _place_name(p),
		"track": n, "goal": "destroy", "nodes": [n], "points": 1400}


## Open water between min_d and max_d from the player (sampled on rays), or null.
func _sea_from_player(min_d: float, max_d: float) -> Variant:
	var found: Array = []
	var a0: float = _rng.randf() * TAU
	for i in 24:
		var a: float = a0 + TAU * float(i) / 24.0
		var r: float = min_d
		while r <= max_d:
			var q: Vector3 = _ppos() + Vector3(cos(a), 0.0, sin(a)) * r
			if GroundKit.raw_y(q.x, q.z) < -6.0 and GroundKit.raw_y(q.x + 600.0, q.z) < -4.0 and GroundKit.raw_y(q.x, q.z + 600.0) < -4.0:
				found.append(Vector3(q.x, 0.0, q.z))
				break
			r += 3000.0
	if found.is_empty():
		return null
	return found[_rng.randi() % found.size()]


func _sea_point_near(p: Vector3, max_r: float) -> Variant:
	for i in 40:
		var a: float = _rng.randf() * TAU
		var r: float = _rng.randf_range(1500.0, max_r)
		var q: Vector3 = p + Vector3(cos(a), 0.0, sin(a)) * r
		if GroundKit.raw_y(q.x, q.z) < -6.0 and GroundKit.raw_y(q.x + 600.0, q.z) < -4.0 and GroundKit.raw_y(q.x, q.z + 600.0) < -4.0:
			return q
	return null


func _make_eboats() -> Dictionary:
	if _pop == null:
		return {}
	var ports: Array = _pop.targets_for_side(enemy, ["port"])
	var pick: Variant = _choose(ports, func(id: String) -> Vector3: return _pop.get_target_info(id)["pos"])
	if pick == null:
		return {}
	var port: Vector3 = _pop.get_target_info(pick)["pos"]
	var start: Variant = _sea_point_near(port, 7000.0)
	if start == null:
		return {}
	# head out to sea, away from the coast
	var out_dir: Vector3 = ((start as Vector3) - port)
	out_dir.y = 0.0
	out_dir = out_dir.normalized()
	var pts := PackedVector3Array()
	for i in 8:
		var q: Vector3 = (start as Vector3) + out_dir * 900.0 * float(i) + Vector3(-out_dir.z, 0, out_dir.x) * sin(float(i)) * 120.0
		pts.append(Vector3(q.x, 0.0, q.z))
	var route: RoutePath = RoutePath.from_points(pts)
	var root: Node3D = _container("eboats")
	var boats: Array = []
	var n: int = 3 if difficulty < 0.6 else 4
	for i in n:
		var b: GroundShip = GroundShip.create("trawler" if i == 0 else "landing_craft", enemy, route, float(i) * 70.0, 13.0)
		root.add_child(b)
		boats.append(b)
	var label: String = "E-boats" if enemy == "Axis" else "MTBs"
	return {"title": "%s leaving %s" % [label, str(_pop.get_target_info(pick)["name"])], "what": label, "pos": start, "place": _place_name(start),
		"track": boats[0], "goal": "kills_of", "nodes": boats, "need": n - 1, "root": root, "points": 1000}


func _make_raid(cover: bool) -> Dictionary:
	# the target is ours: a town or airfield (intercept) or one of our coastal convoys (cover)
	var tgt: Vector3
	var tgt_name: String
	var root: Node3D = _container("raid")
	var protect: Node = null
	if cover:
		var sea: Variant = _sea_from_player(12000.0, 70000.0)
		if sea == null:
			root.queue_free()
			return {}
		tgt = sea
		var dir: Vector3 = WorldCoords.heading_to_dir(_rng.randf() * 360.0)
		var pts := PackedVector3Array()
		for i in 10:
			var q: Vector3 = tgt + dir * 700.0 * float(i)
			if i >= 3 and GroundKit.raw_y(q.x, q.z) > -3.0:
				break                       # keep the convoy's track at sea
			pts.append(Vector3(q.x, 0.0, q.z))
		var cv: Convoy = Convoy.create(side, RoutePath.from_points(pts), true, "channel" if side == "Allies" else "kriegsmarine", 0.0, 6.0)
		root.add_child(cv)
		protect = cv
		tgt_name = "our convoy " + _place_name(tgt)
	else:
		var own: Array = _cities.filter(func(c: Dictionary) -> bool: return _held_by(c["pos"]) == side and int(c["size"]) >= 2)
		var town: Variant = _choose(own, func(c: Dictionary) -> Vector3: return c["pos"], 8000.0, 50000.0)
		if town == null:
			root.queue_free()
			return {}
		tgt = town["pos"]
		tgt_name = str(town["name"])
	# the raid comes in from the nearest enemy airfield side, 30 km out
	var from_dir: Vector3 = _nearest_enemy_airfield(tgt) - tgt
	from_dir.y = 0.0
	from_dir = from_dir.normalized() if from_dir.length() > 1.0 else Vector3(0, 0, 1)
	var start: Vector3 = tgt + from_dir * 30000.0
	var alt_y: float = (_rng.randf_range(1800.0, 3200.0) if not cover else _rng.randf_range(1400.0, 2000.0)) * WorldCoords.VERTICAL_SCALE
	start.y = alt_y
	var route: Array[Vector3] = [Vector3(tgt.x, alt_y, tgt.z), start + Vector3(from_dir.z, 0, -from_dir.x) * 8000.0]
	var pool: Array = AircraftCatalog.bombers_for_side(enemy)
	if not cover:
		pool = pool.filter(func(i: String) -> bool: return i != "ju87" and i != "ju52" and i != "c47")      # a town raid is a level-bomber job
	var bid: String = String(pool[_rng.randi() % pool.size()]) if not pool.is_empty() else ("he111" if enemy == "Axis" else "b26")
	if cover and enemy == "Axis" and AircraftCatalog.ids_for_side("Axis").has("ju87"):
		bid = "ju87"
	var nb: int = 3 if difficulty < 0.4 else (4 if difficulty < 0.75 else 5)
	var form: BomberFormation = BomberFormation.spawn(world, bid, enemy, nb, start, WorldCoords.dir_to_heading(-from_dir), route, difficulty)
	var nodes: Array = []
	for m in form.members:
		nodes.append(m)
		AIFactory.add_marker(hud, m, Color(1.0, 0.25, 0.2))
	# escort fighters weaving above the bombers
	var fpool: Array = AircraftCatalog.fighters_for_side(enemy).filter(func(i: String) -> bool: return i != "me262")
	var esc_n: int = mini((0 if difficulty < 0.3 else 2) + mini(air_threat, 3), AIFactory.ai_room(get_tree()))
	for k in esc_n:
		if fpool.is_empty() or form.leader == null:
			break
		var e: Aircraft = AIFactory.spawn(world, fpool[_rng.randi() % fpool.size()], enemy, start + Vector3(0, 300, 0) + Vector3(-from_dir.z, 0, from_dir.x) * (200.0 * (k * 2 - 1)),
			WorldCoords.dir_to_heading(-from_dir), -1.0, difficulty, AIPilot.Role.WINGMAN, form.leader)
		var pil: AIPilot = AIFactory.pilot_of(e)
		if pil != null:
			pil.set_leader(form.leader, Vector3(260.0 * (k * 2 - 1), 260.0, 300.0))
			pil.engage_radius = 2500.0
		AIFactory.add_marker(hud, e, Color(1.0, 0.45, 0.2))
		nodes.append(e)          # escorts live in the world; listed so the clean-up removes them
	var ang: int = int(round(alt_y / WorldCoords.VERTICAL_SCALE * 3.281 / 1000.0))
	return {"title": ("Convoy cover" if cover else "Intercept: raid on %s" % tgt_name), "what": AircraftCatalog.display_name(bid), "pos": tgt, "place": tgt_name,
		"track": form, "goal": "raid", "nodes": nodes, "bombers": form.members.duplicate(), "count": nb, "angels": ang,
		"root": root, "protect": protect, "points": 1300 if not cover else 1100, "raid_target": tgt}


func _make_sweep() -> Dictionary:
	var p: Variant = null
	if _pop != null:
		var afs: Array = _enemy_airfields()
		var a: Variant = _choose(afs, func(x: Dictionary) -> Vector3: return x["pos"])
		if a != null:
			p = (a["pos"] as Vector3) + WorldCoords.heading_to_dir(_rng.randf() * 360.0) * 4000.0
	if p == null:
		return {}
	var pool: Array = AircraftCatalog.fighters_for_side(enemy).filter(func(i: String) -> bool: return i != "me262")
	if pool.is_empty():
		return {}
	var n: int = mini(2 if difficulty < 0.35 else (3 if difficulty < 0.7 else 4), maxi(1, AIFactory.ai_room(get_tree())))
	var alt_y: float = _rng.randf_range(1200.0, 2600.0) * WorldCoords.VERTICAL_SCALE
	var nodes: Array = []
	var lead: Aircraft = null
	for i in n:
		var pos: Vector3 = (p as Vector3) + Vector3(float(i) * 120.0, alt_y + float(i) * 30.0, float(i) * 90.0)
		var ac: Aircraft = AIFactory.spawn(world, pool[_rng.randi() % pool.size()], enemy, pos, _rng.randf() * 360.0, -1.0, difficulty)
		var pil: AIPilot = AIFactory.pilot_of(ac)
		if pil != null:
			pil.patrol_center = Vector3((p as Vector3).x, alt_y, (p as Vector3).z)
			pil.patrol_radius = 3500.0
			pil.patrol_alt = alt_y
			pil.detect_range = 7000.0
		AIFactory.add_marker(hud, ac, Color(1.0, 0.25, 0.2))
		nodes.append(ac)
		if lead == null:
			lead = ac
	return {"title": "Fighter sweep", "what": "%d %s" % [n, AircraftCatalog.display_name(String(lead.stats.id))], "pos": p, "place": _place_name(p),
		"track": lead, "goal": "kills_of", "nodes": nodes, "need": n, "points": 1000, "angels": int(round(alt_y / WorldCoords.VERTICAL_SCALE * 3.281 / 1000.0))}


func _make_rescue() -> Dictionary:
	var sea: Variant = _sea_from_player(12000.0, 70000.0)
	if sea == null:
		return {}
	var root: Node3D = _container("rescue")
	var dinghy := Dinghy.new()
	root.add_child(dinghy)
	dinghy.global_position = Vector3((sea as Vector3).x, 0.2, (sea as Vector3).z)
	return {"title": "Air-sea rescue", "what": "pilot in a dinghy", "pos": dinghy.global_position, "place": _place_name(dinghy.global_position),
		"track": dinghy, "goal": "orbit", "need_t": 40.0, "got_t": 0.0, "root": root, "points": 800, "threat_sent": false, "nodes": [], "hit": []}


func _make_recce() -> Dictionary:
	if _pop == null:
		return {}
	var ids: Array = _pop.targets_for_side(enemy, ["radar", "v1_site", "port", "battery", "bridge"])
	var pick: Variant = _choose(ids, func(id: String) -> Vector3: return _pop.get_target_info(id)["pos"])
	if pick == null:
		return {}
	var info: Dictionary = _pop.get_target_info(pick)
	_pop.spawn_target(pick)       # so the site (and its flak) is really there
	var p: Vector3 = info["pos"]
	return {"title": "Photo recce: %s" % str(info["name"]), "what": str(info["name"]), "pos": p, "place": _place_name(p),
		"goal": "photo", "stage": "photo", "home": _home_airfield(), "points": 900, "hit": [], "type": str(info["type"])}


# ------------------------------------------------------------------ new job kinds: escort, intruder

func _make_escort() -> Dictionary:
	# friendly bombers wait at a rendezvous; take them to a real target and keep the fighters off them
	if _pop == null:
		return {}
	var ids: Array = _pop.targets_for_side(enemy, ["factory", "rail_yard", "port", "radar", "bridge", "v1_site", "oil_depot", "oil"])
	var pick: Variant = _choose(ids, func(id: String) -> Vector3: return _pop.get_target_info(id)["pos"], 25000.0, MAX_RANGE)
	if pick == null:
		return {}
	var tinfo: Dictionary = _pop.get_target_info(pick)
	var tgt_node: Node = _pop.spawn_target(pick)
	var p: Vector3 = tinfo["pos"]
	var rv: Vector3 = _rv_point(p)
	var pool: Array = AircraftCatalog.bombers_for_side(side).filter(func(i: String) -> bool: return i != "ju87" and i != "ju52" and i != "c47")
	var bid: String = String(pool[_rng.randi() % pool.size()]) if not pool.is_empty() else ("b26" if side == "Allies" else "he111")
	var info: Dictionary = {"title": "Escort: %s to %s" % [AircraftCatalog.display_name(bid), str(tinfo["name"])], "what": str(tinfo["name"]),
		"pos": p, "place": _place_name(p), "goal": "escort", "stage": "rv", "rv": rv, "bomber_id": bid,
		"target_node": tgt_node, "points": 1400, "hit": [], "type": str(tinfo["type"]), "friends": [], "section": _section_name()}
	return info


func _make_intruder() -> Dictionary:
	# night intruder: their bombers are coming home, the flare path is lit - catch them in the circuit
	if _pop == null:
		return {}
	var pick: Variant = _choose(_enemy_airfields(), func(a: Dictionary) -> Vector3: return a["pos"])
	if pick == null:
		return {}
	var af: Airfield = _pop.get_airfield(str(pick["id"]))
	var p: Vector3 = pick["pos"] if af == null else af.global_position
	if af != null and af.has_method("set_lights_active"):
		af.set_lights_active(true)
	var pool: Array = AircraftCatalog.bombers_for_side(enemy).filter(func(i: String) -> bool: return i != "ju87" and i != "ju52" and i != "c47")
	var nodes: Array = []
	for k in 2:
		if pool.is_empty():
			break
		var a: float = _rng.randf() * TAU
		var pos: Vector3 = p + Vector3(cos(a), 0.0, sin(a)) * 2500.0
		pos.y = maxf(GroundKit.ground_y(pos.x, pos.z), 0.0) + 900.0
		var ac: Aircraft = AIFactory.spawn(world, pool[_rng.randi() % pool.size()], enemy, pos, rad_to_deg(a) + 90.0, -1.0, difficulty)
		var pil: AIPilot = AIFactory.pilot_of(ac)
		if pil != null:
			pil.patrol_center = Vector3(p.x, pos.y, p.z)
			pil.patrol_radius = 2600.0
			pil.patrol_alt = pos.y
			pil.detect_range = 1500.0
		nodes.append(ac)
	var root: Node3D = _container("intruder")
	_pop._defences(root, _ground_pt(p), enemy, 0, 1, 3, 0, 900.0, _rng.randi())
	return {"title": "Intruder: %s" % str(pick["name"]), "what": str(pick["name"]), "pos": p, "place": _place_name(p),
		"goal": "kills", "radius": 3000.0, "need": 3, "got": 0, "nodes": nodes, "hit_area": true, "root": root, "points": 1300, "af": af}


# ------------------------------------------------------------------ rendezvous

func _section_name() -> String:
	if side == "Allies":
		return ["Blue Section", "Green Section", "Yellow Section", "White Section"][_rng.randi() % 4]
	return ["Schwarm Gelb", "Schwarm Blau", "Schwarm Weiss", "Schwarm Grün"][_rng.randi() % 4]


## A rendezvous a third of the way out, offset to one side, never closer than 6 km.
func _rv_point(tgt: Vector3) -> Vector3:
	var d: Vector3 = tgt - _ppos()
	d.y = 0.0
	var side_v := Vector3(-d.z, 0.0, d.x).normalized() * (_rng.randf_range(2500.0, 5000.0) * (1.0 if _rng.randf() < 0.5 else -1.0))
	var rv: Vector3 = _ppos() + d * _rng.randf_range(0.28, 0.4) + side_v
	if _dist(rv) < 6000.0:
		rv = _ppos() + d.normalized() * 6000.0 + side_v
	rv.y = 0.0
	return rv


func _maybe_rv(info: Dictionary) -> void:
	if not (str(info["kind"]) in ["strike", "shipping", "airfield", "sweep", "intercept", "intruder"]):
		return
	if _rng.randf() > 0.4 and not OS.get_cmdline_user_args().has("--ops-rv"):
		return
	if _dist(info["pos"]) < 15000.0:
		return
	info["stage"] = "rv"
	info["rv"] = _rv_point(info["pos"])
	info["section"] = _section_name()
	# the section waits at the RV, circling at the player's height
	var pool: Array = AircraftCatalog.fighters_for_side(side).filter(func(i: String) -> bool: return i != "me262")
	if pool.is_empty():
		info.erase("stage")
		return
	var fid: String = String(player.stats.id) if not AircraftCatalog.is_bomber(String(player.stats.id)) else String(pool[0])
	var alt_y: float = maxf(player.global_position.y, 900.0 * WorldCoords.VERTICAL_SCALE)
	var friends: Array = []
	var n: int = mini(2 if _rng.randf() < 0.5 else 3, maxi(1, AIFactory.ai_room(get_tree())))
	for k in n:
		var pos: Vector3 = (info["rv"] as Vector3) + Vector3(float(k) * 140.0, alt_y + float(k) * 20.0, float(k) * 90.0)
		var ac: Aircraft = AIFactory.spawn(world, fid, side, pos, _rng.randf() * 360.0, -1.0, clampf(difficulty + 0.2, 0.0, 1.0))
		var pil: AIPilot = AIFactory.pilot_of(ac)
		if pil != null:
			pil.patrol_center = Vector3((info["rv"] as Vector3).x, alt_y, (info["rv"] as Vector3).z)
			pil.patrol_radius = 1600.0
			pil.patrol_alt = alt_y
			pil.detect_range = 2500.0
		AIFactory.add_marker(hud, ac, Color(0.3, 0.85, 1.0))
		friends.append(ac)
	info["friends"] = friends


func _update_rv(dt: float) -> void:
	active["rv_t"] = float(active.get("rv_t", 0.0)) + dt
	var rv: Vector3 = active["rv"]
	if str(active["goal"]) == "escort":
		# the bombers arrive when the player is close
		if _dist(rv) < 7000.0 and not active.has("form"):
			_spawn_escorted(active)
		if active.has("form") and _dist(rv) < 3000.0:
			_join(active)
		elif float(active["rv_t"]) > 480.0 and active.has("form"):
			_say("The bombers couldn't wait any longer. They've gone on alone - catch them up!", 0.0, "rv_gone_1")
			active["stage"] = "target"
		return
	if _dist(rv) < 2500.0:
		_join(active)
	elif float(active["rv_t"]) > 420.0:
		_say("%s couldn't wait. They've gone on ahead to the target." % str(active["section"]), 0.0, "rv_gone_1")
		for f in active.get("friends", []):
			var pil: AIPilot = AIFactory.pilot_of(f) if is_instance_valid(f) else null
			if pil != null:
				pil.patrol_center = Vector3((active["pos"] as Vector3).x, pil.patrol_alt, (active["pos"] as Vector3).z)
				pil.detect_range = 7000.0
		active["stage"] = "target"


func _join(info: Dictionary) -> void:
	info["stage"] = "target"
	var friends: Array = info.get("friends", [])
	var n: int = friends.size()
	for k in n:
		var f: Variant = friends[k]
		if not is_instance_valid(f):
			continue
		var pil: AIPilot = AIFactory.pilot_of(f)
		if pil == null:
			continue
		if pil.role == AIPilot.Role.FIGHTER:
			pil.role = AIPilot.Role.WINGMAN
			pil.set_leader(player, Radio.formation_offset(k, n))
			pil.state = AIPilot.State.FORMATION
			pil.detect_range = 9000.0
	var sec: String = str(info.get("section", "The section"))
	if str(info["goal"]) == "escort":
		Radio.say(str(info.get("bomber_lead", "Bomber leader")), "Good to see you, fighters. We're turning for the target now.", Radio.Kind.FRIENDLY, 0.3, _clip("bombers_join_1"))
	else:
		var rj: int = _rng.randi() % 3
		Radio.say(sec, String(RV_JOIN[side][rj]), Radio.Kind.FRIENDLY, 0.3, _clip("rv_join_%d" % (rj + 1)))
	_record({"points": 150})
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "RENDEZVOUS  %s joined" % sec, 3.0)


func _spawn_escorted(info: Dictionary) -> void:
	var rv: Vector3 = info["rv"]
	var tgt: Vector3 = info["pos"]
	var dir: Vector3 = (tgt - rv)
	dir.y = 0.0
	dir = dir.normalized()
	var alt_y: float = _rng.randf_range(2200.0, 3200.0) * WorldCoords.VERTICAL_SCALE
	var start := Vector3(rv.x, alt_y, rv.z)
	var route: Array[Vector3] = [Vector3(tgt.x, alt_y, tgt.z), start - dir * 4000.0]
	var form: BomberFormation = BomberFormation.spawn(world, str(info["bomber_id"]), side, 3, start, WorldCoords.dir_to_heading(dir), route, difficulty)
	info["form"] = form
	info["friends"] = form.members.duplicate()
	info["bomber_lead"] = "Bomber leader" if side == "Allies" else "Kampfgruppe"
	_friends = info["friends"]
	for m in form.members:
		AIFactory.add_marker(hud, m, Color(0.45, 0.85, 1.0))
	_say("The bombers are at the rendezvous. Take station on them.", 0.0, "bombers_at_rv_1")


func _update_escort() -> void:
	if str(active["stage"]) == "rv" and not active.has("form"):
		return
	var form: Variant = active.get("form")
	if form == null or not is_instance_valid(form):
		_say("We've lost the bombers. That's a bad business.", 0.0, "escort_lost_1")
		_end_active(false, true)
		return
	var alive: int = 0
	var lead: Aircraft = null
	for m in active["friends"]:
		if is_instance_valid(m) and (m as Aircraft).state == Aircraft.State.ALIVE:
			alive += 1
			if lead == null:
				lead = m
	if alive <= 1:
		_say("We've lost the bombers. That's a bad business.", 0.0, "escort_lost_1")
		_end_active(false, true)
		return
	var tgt: Vector3 = active["pos"]
	var lp: Vector3 = lead.global_position
	var total: float = maxf(Vector2(tgt.x - (active["rv"] as Vector3).x, tgt.z - (active["rv"] as Vector3).z).length(), 1.0)
	var left: float = Vector2(tgt.x - lp.x, tgt.z - lp.z).length()
	# the enemy comes up to meet them about half way
	if not bool(active.get("intercepted", false)) and left < total * 0.55:
		active["intercepted"] = true
		var pool: Array = AircraftCatalog.fighters_for_side(enemy).filter(func(i: String) -> bool: return i != "me262")
		var n: int = 2 + mini(air_threat, 2) + (1 if difficulty > 0.6 else 0)
		var ahead: Vector3 = lp + (Vector3(tgt.x, lp.y, tgt.z) - lp).normalized() * 6000.0
		for k in n:
			if pool.is_empty():
				break
			var ac: Aircraft = AIFactory.spawn(world, pool[_rng.randi() % pool.size()], enemy, ahead + Vector3(k * 150.0, 400.0, 0.0), WorldCoords.dir_to_heading(lp - ahead), -1.0, difficulty)
			var pil: AIPilot = AIFactory.pilot_of(ac)
			if pil != null:
				pil.detect_range = 9000.0
			AIFactory.add_marker(hud, ac, Color(1.0, 0.25, 0.2))
			var en: Array = active.get("enemies", [])
			en.append(ac)
			active["enemies"] = en
		_say("Bandits ahead of the bombers! Get in among them!", 0.0, "escort_bandits_1")
	if left < 1800.0:
		for i in 7:
			var q: Vector3 = tgt + Vector3(_rng.randf_range(-350, 350), 0.0, _rng.randf_range(-350, 350))
			q.y = maxf(GroundKit.ground_y(q.x, q.z), 0.0)
			FX.explosion(q, 14.0)
		var tn: Variant = active.get("target_node")
		if tn != null and is_instance_valid(tn) and tn.has_method("take_damage"):
			tn.call("take_damage", 99999.0, null)
		Radio.say(str(active.get("bomber_lead", "Bomber leader")), "Bombs gone! Bang on target. Thanks for the company, fighters.", Radio.Kind.FRIENDLY, 0.0, _clip("bombers_bombed_1"))
		_end_active(true)


# ------------------------------------------------------------------ hits, kills and the logbook

## One hit on any of the tasking's targets completes it.
func _on_player_hit(node: Node, _amount: float) -> void:
	if node is FlyingBomb:
		return                      # V-1s are handled as kills (one hit brings them down)
	if active.is_empty() or not is_instance_valid(node):
		return
	if not _hits_target(node):
		return
	_say_take(HIT_LINES, "hit")
	_end_active(true, true)


func _hits_target(node: Node) -> bool:
	for t in active.get("hit", []):
		if t != null and is_instance_valid(t) and (t == node or (t as Node).is_ancestor_of(node)):
			return true
	if bool(active.get("hit_area", false)) and (node is GroundTarget or node is Aircraft):
		if str(node.get("team")) == enemy and node is Node3D:
			var c: Vector3 = active["pos"]
			var q: Vector3 = (node as Node3D).global_position
			return Vector2(q.x - c.x, q.z - c.z).length() <= float(active.get("radius", 2000.0))
	if str(active.get("kind", "")) in ["intercept", "cover"]:
		return (active.get("bombers", []) as Array).has(node) or (active.get("nodes", []) as Array).has(node)
	return false


func _on_player_kill(node: Node) -> void:
	if node is FlyingBomb:
		if mode != null:
			mode.add_score(150)
		_say("Good shooting! That Diver won't reach London.", 0.0, "v1_kill_1")


func _forced_run() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ops-kind=") or a in ["--ops-rv", "--ops-twist", "--ops-auto"]:
			return true
	return false


func _record(changes: Dictionary, entry: String = "") -> void:
	if _test or _forced_run():      # soak tests and forced debug runs must not touch the real logbook
		return
	var news: Dictionary = PilotLog.record(side, changes, entry)
	if str(news["promoted"]) != "":
		var rk: String = str(news["promoted"])
		_say("Congratulations, %s. You've been promoted to %s." % [Radio.player_callsign, rk], 1.5, "promoted_1")
		if hud and hud.has_method("show_message"):
			hud.call("show_message", "PROMOTED: %s" % rk.to_upper(), 6.0)
	for a in news["awards"]:
		_say("Signal from Group: you've been awarded the %s. Well done." % str(a), 2.5, "award_1")
		if hud and hud.has_method("show_message"):
			hud.call("show_message", "AWARDED: %s" % str(a).to_upper(), 6.0)


# ------------------------------------------------------------------ intelligence

## Flying low past an enemy site or airfield reports it; Ops turns reports into later taskings.
func _intel_scan(delta: float) -> void:
	_intel_cd = maxf(_intel_cd - delta, 0.0)
	_intel_t -= delta
	if _intel_t > 0.0 or _pop == null or player.on_ground:
		return
	_intel_t = 2.0
	if _intel_cd > 0.0 or _intel.size() >= 4 or player.get_altitude_m() > 2500.0:
		return
	var pp: Vector3 = _ppos()
	var cands: Array = []
	for id in _pop.targets_for_side(enemy, ["factory", "rail_yard", "port", "radar", "bridge", "battery", "v1_site", "oil_depot", "oil"]):
		var ti: Dictionary = _pop.get_target_info(id)
		cands.append({"kind": "strike", "id": id, "name": str(ti["name"]), "pos": ti["pos"], "r": 2600.0})
	for a in _enemy_airfields():
		cands.append({"kind": "airfield", "id": str(a["id"]), "name": str(a["name"]), "pos": a["pos"], "site": a, "r": 3200.0})
	for c in cands:
		if _reported.has(c["id"]):
			continue
		if not active.is_empty() and (active["pos"] as Vector3).distance_to(c["pos"]) < 500.0:
			continue
		if Vector2((c["pos"] as Vector3).x - pp.x, (c["pos"] as Vector3).z - pp.z).length() < float(c["r"]):
			_reported[c["id"]] = true
			_intel.append(c)
			_intel_cd = 60.0
			Radio.say(Radio.player_callsign, "Ops, %s. Spotted the %s %s - sending a report." % [Radio.player_callsign, str(c["name"]), _place_name(c["pos"])],
				Radio.Kind.PLAYER, 0.0, _clip("intel_report_1", true))
			var ia: int = _rng.randi() % 2
			_say(String(INTEL_ACK[side][ia]), 2.5, "intel_ack_%d" % (ia + 1))
			_record({"intel": 1, "points": 100}, "Reported %s" % str(c["name"]))
			return


# ------------------------------------------------------------------ pressure: V-1s and flak

func _pressure_flak(info: Dictionary) -> void:
	if supply <= 0 or not (str(info["kind"]) in ["strike", "airfield", "convoy", "train", "recce", "intruder"]):
		return
	var root: Node3D = _container("flak")
	_pop._defences(root, _ground_pt(info["pos"]), enemy, 1 if supply >= 3 else 0, mini(supply, 4), 0, 0, 450.0, _rng.randi())
	var extra: Array = info.get("extra_roots", [])
	extra.append(root)
	info["extra_roots"] = extra


func _v1_tick(delta: float) -> void:
	for i in range(_v1s.size() - 1, -1, -1):
		if not is_instance_valid(_v1s[i]):
			_v1s.remove_at(i)
	if v1_threat <= 0 or side != "Allies" or _pop == null:
		return
	_v1_t -= delta
	if _v1_t > 0.0:
		return
	_v1_t = maxf(320.0 - 70.0 * float(v1_threat), 90.0) * _rng.randf_range(0.8, 1.2)
	var sites: Array = _pop.targets_for_side("Axis", ["v1_site"])
	var from: Vector3 = WorldCoords.latlon_to_world(50.75, 2.0)
	if not sites.is_empty():
		from = _pop.get_target_info(sites[_rng.randi() % sites.size()])["pos"]
	var to: Vector3 = WorldCoords.latlon_to_world(51.507, -0.128)       # London
	to += Vector3(_rng.randf_range(-6000, 6000), 0.0, _rng.randf_range(-6000, 6000))
	var vb: FlyingBomb = FlyingBomb.launch(world, from, to)
	_v1s.append(vb)
	AIFactory.add_marker(hud, vb, Color(1.0, 0.15, 0.6))
	vb.impact.connect(func(_n: Node) -> void:
		_say("A Diver got through. It came down %s." % _place_name(vb.global_position), 0.0, "v1_impact_1")
		_record({}, "A V-1 hit %s" % _place_name(vb.global_position)))
	_say("Diver, diver! Flying bomb crossing the coast %s, heading for London." % _place_name(from + (to - from) * 0.25), 0.0, "v1_alert_%d" % (1 + _rng.randi() % 2))


# ------------------------------------------------------------------ progress

func _update_active(dt: float) -> void:
	if _auto and float(active["age"]) > (3.0 if _test else 6.0):
		_end_active(true)
		return
	# scramble timer: how quickly the player gets off the ground
	if bool(active.get("scramble", false)):
		active["scramble_t"] = float(active["scramble_t"]) + dt
		if not player.on_ground and player.altitude_agl > 30.0:
			active["scramble"] = false
			var st: float = float(active["scramble_t"])
			if st < 120.0:
				_say("Good scramble - airborne in %d seconds." % int(st), 0.0, "scramble_good_1")
				_record({"scrambles": 1, "points": 300}, "Scrambled in %d s" % int(st))
				if mode != null:
					mode.add_score(300)
			else:
				_say("Slow off the mark there. Get after them!", 0.0, "scramble_slow_1")
	# fog rolling in scrubs the job
	if float(active.get("fog_at", -1.0)) > 0.0 and float(active["age"]) > float(active["fog_at"]):
		active["fog_at"] = -1.0
		_weather_restore = str(WeatherManager.get("current"))
		WeatherManager.set_weather("fog", 90.0)
		_say("Met reports fog rolling in %s. Scrub the job and come home." % str(active.get("place", "")), 0.0, "scrub_fog_1")
		_end_active(false, true, true)
		_next_t = 300.0
		get_tree().create_timer(480.0).timeout.connect(func() -> void:
			if _weather_restore != "":
				WeatherManager.set_weather(_weather_restore, 120.0))
		return
	# a twist part-way through
	if float(active.get("twist_at", -1.0)) > 0.0 and float(active["age"]) > float(active["twist_at"]):
		active["twist_at"] = -1.0
		_twist()
	# enemy fighters bounce the player when the air threat is up
	if not bool(active.get("bounce_done", true)) and float(active["age"]) > 60.0 and not player.on_ground:
		active["bounce_done"] = true
		if _rng.randf() < 0.12 * float(air_threat):
			_bounce()
	if str(active.get("stage", "")) == "rv":
		_update_rv(dt)
	match str(active["goal"]):
		"destroy":
			var all_dead: bool = true
			for n in active["nodes"]:
				if is_instance_valid(n) and not bool(n.call("is_destroyed")):
					all_dead = false
			if all_dead:
				_end_active(true)
		"kills", "kills_of":
			_count_kills()
			var need: int = int(active["need"])
			var got: int = int(active.get("got", 0))
			if str(active["goal"]) == "kills_of":
				got = 0
				for n in active["nodes"]:
					if not is_instance_valid(n) or _is_down(n):
						got += 1
				active["got"] = got
			if got >= need:
				_end_active(true)
		"raid":
			_update_raid()
		"orbit":
			_update_rescue(dt)
		"photo":
			_update_recce()
		"escort":
			_update_escort()


func _bounce() -> void:
	var pool: Array = AircraftCatalog.fighters_for_side(enemy).filter(func(i: String) -> bool: return i != "me262")
	if pool.is_empty():
		return
	var back: Vector3 = -player.get_forward()
	back.y = 0.0
	back = back.normalized()
	for k in 2:
		var pos: Vector3 = _ppos() + back * 3500.0 + Vector3(k * 120.0, 500.0, 0.0)
		var ac: Aircraft = AIFactory.spawn(world, pool[_rng.randi() % pool.size()], enemy, pos, player.get_heading_deg(), -1.0, difficulty)
		var pil: AIPilot = AIFactory.pilot_of(ac)
		if pil != null:
			pil.detect_range = 9000.0
		AIFactory.add_marker(hud, ac, Color(1.0, 0.25, 0.2))
		var nd: Array = active.get("nodes", [])
		nd.append(ac)
		active["nodes"] = nd
	_say("Bandits behind you, %s! Break, break!" % Radio.player_callsign, 0.0, "bounce_1")


## One change of plan part-way through, to suit the job.
func _twist() -> void:
	var kind: String = str(active["kind"])
	match kind:
		"intercept", "cover":
			if kind == "intercept":
				var own: Array = _cities.filter(func(c: Dictionary) -> bool: return _held_by(c["pos"]) == side and int(c["size"]) >= 2 and c["name"] != active["place"])
				var form: Variant = active.get("track")
				if own.is_empty() or form == null or not is_instance_valid(form) or (form as BomberFormation).leader == null:
					return
				var lp: Vector3 = (form as BomberFormation).leader.global_position
				var best: Dictionary = {}
				var bd: float = INF
				for c in own:
					var d: float = Vector2(c["pos"].x - lp.x, c["pos"].z - lp.z).length()
					if d > 6000.0 and d < bd:
						bd = d
						best = c
				if best.is_empty():
					return
				var pil: AIPilot = AIFactory.pilot_of((form as BomberFormation).leader)
				if pil != null:
					var ny: float = lp.y
					var wps: Array[Vector3] = [Vector3(best["pos"].x, ny, best["pos"].z), lp + (lp - Vector3(best["pos"].x, ny, best["pos"].z)).normalized() * 20000.0]
					pil.waypoints = wps
					pil.wp_index = 0
				active["raid_target"] = best["pos"]
				active["pos"] = best["pos"]
				active["place"] = str(best["name"])
				active["title"] = "Intercept: raid on %s" % str(best["name"])
				_say("Change of plan - the raid has turned. They're heading for %s now." % str(best["name"]), 0.0, "twist_raid_turn_1")
			else:
				_say("The convoy's taking a real pasting down there. Hurry!", 0.0, "twist_convoy_hurry_2")
		"convoy", "train":
			_say("It's getting close to cover - once it's in there we've lost it. Get a move on!", 0.0, "twist_deadline_2")
		"shipping", "eboats":
			_say("They're making for the shore batteries. Catch them before they're under the guns.", 0.0, "twist_shore_2")
		"strike", "recce", "intruder":
			var root: Node3D = _container("reinforce")
			_pop._defences(root, _ground_pt(active["pos"]), enemy, 1, 2, 1 if _is_night() else 0, 0, 500.0, _rng.randi())
			var extra: Array = active.get("extra_roots", [])
			extra.append(root)
			active["extra_roots"] = extra
			_say("Recce says they've moved more flak in round the target. Go in fast and low.", 0.0, "twist_flak_1")
		"airfield":
			var pool: Array = AircraftCatalog.fighters_for_side(enemy).filter(func(i: String) -> bool: return i != "me262")
			for k in 2:
				if pool.is_empty():
					break
				var pos: Vector3 = (active["pos"] as Vector3) + Vector3(k * 200.0, 300.0, 0.0)
				pos.y = maxf(GroundKit.ground_y(pos.x, pos.z), 0.0) + 300.0
				var ac: Aircraft = AIFactory.spawn(world, pool[_rng.randi() % pool.size()], enemy, pos, _rng.randf() * 360.0, -1.0, difficulty)
				AIFactory.add_marker(hud, ac, Color(1.0, 0.25, 0.2))
				var nd: Array = active.get("nodes", [])
				nd.append(ac)
				active["nodes"] = nd
			_say("Heads up - they're scrambling fighters off that airfield.", 0.0, "twist_scramble_1")
		"sweep":
			var pool2: Array = AircraftCatalog.fighters_for_side(enemy).filter(func(i: String) -> bool: return i != "me262")
			for k in 2:
				if pool2.is_empty():
					break
				var pos2: Vector3 = (active["pos"] as Vector3) + Vector3(k * 150.0, 0.0, 2500.0)
				pos2.y = player.global_position.y + 300.0
				var ac2: Aircraft = AIFactory.spawn(world, pool2[_rng.randi() % pool2.size()], enemy, pos2, _rng.randf() * 360.0, -1.0, difficulty)
				var pil2: AIPilot = AIFactory.pilot_of(ac2)
				if pil2 != null:
					pil2.detect_range = 7000.0
				AIFactory.add_marker(hud, ac2, Color(1.0, 0.25, 0.2))
				(active["nodes"] as Array).append(ac2)
				(active["hit"] as Array).append(ac2)
			_say("Two more bandits joining them. Watch yourself.", 0.0, "twist_more_bandits_1")
		"rescue":
			var dinghy: Vector3 = active["pos"]
			var a: float = _rng.randf() * TAU
			var st := Vector3(dinghy.x + cos(a) * 4500.0, 0.0, dinghy.z + sin(a) * 4500.0)
			var pts := PackedVector3Array([st, Vector3(dinghy.x, 0.0, dinghy.z), Vector3(dinghy.x, 0.0, dinghy.z) - (st - dinghy).normalized() * 3000.0])
			var boat: GroundShip = GroundShip.create("trawler", enemy, RoutePath.from_points(pts), 0.0, 9.0)
			var root2: Node3D = active.get("root") if active.get("root") != null else _container("eboat")
			root2.add_child(boat)
			active["eboat"] = boat
			AIFactory.add_marker(hud, boat, Color(1.0, 0.25, 0.2))
			_say("Enemy boat heading for the dinghy! Don't let them pick him up.", 0.0, "twist_eboat_1")


func _is_down(n: Node) -> bool:
	if n is Aircraft:
		return (n as Aircraft).state != Aircraft.State.ALIVE
	if n.has_method("is_destroyed"):
		return bool(n.call("is_destroyed"))
	return false


## Enemy ground targets destroyed inside the tasking's radius since it was issued.
func _count_kills() -> void:
	if str(active["goal"]) != "kills":
		return
	var c: Vector3 = active["pos"]
	var r: float = float(active.get("radius", 2000.0))
	for n in get_tree().get_nodes_in_group("destroyed_target"):
		var id: int = n.get_instance_id()
		if _counted.has(id) or not (n is GroundTarget):
			continue
		_counted[id] = true
		var gt: GroundTarget = n
		if gt.team != enemy:
			continue
		if Vector2(gt.global_position.x - c.x, gt.global_position.z - c.z).length() <= r:
			active["got"] = int(active.get("got", 0)) + 1


func _update_raid() -> void:
	var down: int = 0
	for b in active["bombers"]:
		if not is_instance_valid(b) or (b as Aircraft).state != Aircraft.State.ALIVE:
			down += 1
	active["got"] = down
	if down >= 1:
		_end_active(true)
		return
	var form: Variant = active.get("track")
	if form == null or not is_instance_valid(form):
		return
	var f: BomberFormation = form
	if f.leader == null or not is_instance_valid(f.leader):
		return
	var tgt: Vector3 = active["raid_target"]
	var lp: Vector3 = f.leader.global_position
	if Vector2(lp.x - tgt.x, lp.z - tgt.z).length() < 1800.0:
		for i in 7:
			var q: Vector3 = tgt + Vector3(_rng.randf_range(-500, 500), 0.0, _rng.randf_range(-500, 500))
			q.y = maxf(GroundKit.ground_y(q.x, q.z), 0.0)
			if q.y <= 0.5:
				FX.water_plume(q, 10.0)
			else:
				FX.explosion(q, 14.0)
		var prot: Variant = active.get("protect")
		if prot != null and is_instance_valid(prot) and prot is Convoy:
			var cv: Convoy = prot
			for u in cv.units:
				if is_instance_valid(u) and _rng.randf() < 0.5 and u.has_method("take_damage"):
					u.call("take_damage", 9999.0, null)
		_say("They've bombed %s. We were too late on that one." % str(active["place"]), 0.0, "raid_bombed_1")
		_end_active(false)


func _update_rescue(dt: float) -> void:
	var p: Vector3 = active["pos"]
	var d: float = _dist(p)
	var alt_m: float = player.altitude_agl / WorldCoords.VERTICAL_SCALE
	var boat: Variant = active.get("eboat")
	if boat != null and is_instance_valid(boat) and not (boat as GroundShip).is_dead:
		var bp: Vector3 = (boat as Node3D).global_position
		if Vector2(bp.x - p.x, bp.z - p.z).length() < 220.0:
			_say("They've picked him up. He'll see out the war in a prison camp, poor chap.", 0.0, "rescue_lost_1")
			_end_active(false)
			return
	if d < 1400.0 and alt_m < 450.0:
		if float(active["got_t"]) == 0.0:
			_say("You've found him! Stay low and circle so the launch can get a fix on you.", 0.0, "rescue_found_1")
		active["got_t"] = float(active["got_t"]) + dt
	if float(active["got_t"]) > 12.0 and not bool(active["threat_sent"]) and _rng.randf() < 0.4 and difficulty > 0.3:
		active["threat_sent"] = true
		var pool: Array = AircraftCatalog.fighters_for_side(enemy).filter(func(i: String) -> bool: return i != "me262")
		if not pool.is_empty():
			var dir: Vector3 = WorldCoords.heading_to_dir(_rng.randf() * 360.0)
			for k in 2:
				var ac: Aircraft = AIFactory.spawn(world, pool[0], enemy, p + dir * 7000.0 + Vector3(k * 120.0, 900.0, 0.0), WorldCoords.dir_to_heading(-dir), -1.0, difficulty)
				AIFactory.add_marker(hud, ac, Color(1.0, 0.25, 0.2))
				(active["nodes"] as Array).append(ac)
			_say("Two bandits heading your way, they've seen the dinghy too. Keep them off him!", 0.0, "rescue_bandits_1")
	if float(active["got_t"]) >= float(active["need_t"]):
		_record({"rescues": 1})
		_end_active(true)


func _update_recce() -> void:
	if str(active["stage"]) == "photo":
		var p: Vector3 = active["pos"]
		var alt_m: float = player.get_altitude_m()
		var bank: float = absf(rad_to_deg(player._bank_angle()))
		if _dist(p) < 900.0 and alt_m < 1500.0 and bank < 20.0:
			active["stage"] = "home"
			active["title"] = "Bring the photos home"
			_say("Cameras running... got them! Now get those pictures home in one piece.", 0.0, "recce_photos_1")
		return
	var h: Vector3 = active["home"]
	if _dist(h) < 3500.0 and player.altitude_agl / WorldCoords.VERTICAL_SCALE < 300.0:
		_end_active(true)


## quiet: no generic success / failure call (the caller has said something more specific).
## scrub: neither done nor missed (weather, cancellation).
func _end_active(success: bool, quiet: bool = false, scrub: bool = false) -> void:
	if active.is_empty():
		return
	var info: Dictionary = active
	active = {}
	var kind: String = str(info.get("kind", ""))
	var label: String = "%s (%s)" % [str(info.get("title", kind)), str(info.get("place", ""))]
	if scrub:
		_record({}, "%s: scrubbed" % label)
	elif success:
		completed += 1
		_streak += 1
		# jobs done back to back are worth more: +25 % for each in the run, up to double
		var pts: int = int(float(info.get("points", 800)) * (1.0 + 0.25 * float(mini(_streak - 1, 4))))
		if mode != null:
			mode.add_score(pts)
		if not quiet:
			_say_take(SUCCESS_LINES, "success")
		var ax: bool = side == "Axis"
		if _streak == 3:
			_say("That is three in a row. Command is taking notice." if ax else "That's three in a row. Group are taking notice.", 2.5, "streak_1")
		elif _streak == 5:
			_say("Five in a row! The whole Geschwader is talking about you." if ax else "Five on the trot! You're the talk of the mess tonight.", 2.5, "streak_2")
		elif _streak >= 8 and _streak % 4 == 0:
			_say("Another one! There will be a decoration in this for you." if ax else "Another one! There'll be a gong in this for you.", 2.5, "streak_3")
		if hud and hud.has_method("show_message"):
			hud.call("show_message", ("TASKING COMPLETE  +%d" % pts) + ("   x%d IN A ROW" % _streak if _streak >= 2 else ""), 3.0)
		if _test:
			_next_t = 2.0
		elif _rng.randf() < 0.45 and not _await_rearm:
			# while they're out there: a second job close to hand, called in shortly
			_followup = true
			_next_t = _rng.randf_range(25.0, 45.0)
		else:
			_next_t = minf(_next_t, _rng.randf_range(90.0, 160.0))
		_record({"done": 1, "points": pts, "kind": kind}, "%s: done" % label)
		if kind in GROUND_KINDS:
			supply = maxi(supply - 1, 0)
		if kind in AIR_KINDS:
			air_threat = maxi(air_threat - 1, 0)
		if str(info.get("type", "")) == "v1_site":
			v1_threat = maxi(v1_threat - 3, 0)
	else:
		failed += 1
		_streak = 0
		if not quiet:
			_say_take(FAIL_LINES, "fail")
		if not _test:
			_next_t = minf(_next_t, _rng.randf_range(120.0, 180.0))
		if hud and hud.has_method("show_message"):
			hud.call("show_message", "TASKING FAILED", 2.5)
		if _test:
			_next_t = 2.0
		_record({"missed": 1}, "%s: missed" % label)
		# the enemy gains from what we let through
		if kind in GROUND_KINDS:
			supply += 1
			_say("That convoy got through. Their flak will be stronger for it.", 3.0, "pressure_supply_1")
		if kind in AIR_KINDS:
			air_threat += 1
		if side == "Allies" and (str(info.get("type", "")) == "v1_site" or _rng.randf() < 0.3):
			v1_threat += 2 if str(info.get("type", "")) == "v1_site" else 1
			if v1_threat <= 2:
				_v1_t = minf(_v1_t, 90.0)
	if _test or OS.get_cmdline_user_args().has("--ops-verbose"):
		_log("[ops] %s %s" % ["SCRUBBED" if scrub else ("DONE" if success else "FAILED"), kind])
	tasking_finished.emit(info, success)
	_release_friends(info)
	_cleanup(info)
	if _test and _test_i >= KINDS.size() and active.is_empty():
		_log("[ops] test cycle complete: %d done, %d failed" % [completed, failed])
		get_tree().create_timer(1.0).timeout.connect(func() -> void: get_tree().quit())


## The RV section goes home after the job (they are freed later by _cleanup's timer).
func _release_friends(info: Dictionary) -> void:
	for f in info.get("friends", []):
		if is_instance_valid(f):
			var pil: AIPilot = AIFactory.pilot_of(f)
			if pil != null and pil.role == AIPilot.Role.WINGMAN:
				pil.set_order(AIPilot.Order.RTB)
	_friends = []


func _clear_active() -> void:
	if not active.is_empty():
		_cleanup(active)
		active = {}


## Remove what the tasking spawned once the player is well away from it (wreckage stays meanwhile).
func _cleanup(info: Dictionary) -> void:
	var nodes: Array = info.get("nodes", []).duplicate()
	nodes.append_array(info.get("friends", []))
	nodes.append_array(info.get("enemies", []))
	var roots: Array = info.get("extra_roots", []).duplicate()
	if info.get("root") != null:
		roots.append(info.get("root"))
	if info.get("eboat") != null:
		roots.append(info.get("eboat"))
	var tracks: Array = [info.get("track"), info.get("form")]
	var af: Variant = info.get("af")
	if not is_inside_tree():
		return
	var tm := get_tree().create_timer(120.0)
	tm.timeout.connect(func() -> void:
		for n in nodes:
			if is_instance_valid(n) and n is Aircraft:
				(n as Aircraft).queue_free()
		for t in tracks:
			if t != null and is_instance_valid(t) and t is BomberFormation:
				(t as BomberFormation).queue_free()
		for r in roots:
			if r != null and is_instance_valid(r):
				(r as Node).queue_free()
		if af != null and is_instance_valid(af) and af.has_method("set_lights_active"):
			af.call("set_lights_active", false))
	var mk: Variant = info.get("marker")
	if mk != null and is_instance_valid(mk):
		(mk as Node).queue_free()


# ------------------------------------------------------------------ radio and HUD

func _sender() -> String:
	return "Sector Control" if side == "Allies" else "Jafü 2"


## Voice clip id for a line (assets/voice/ops/<allies|axis>/<key>.mp3), or "" when it has not been generated.
func _clip(key: String, _player: bool = false) -> String:
	var id: String = "ops/%s/%s" % ["allies" if side == "Allies" else "axis", key]
	return id if ResourceLoader.exists("res://assets/voice/" + id + ".mp3") else ""


func _say(text: String, delay: float = 0.0, key: String = "") -> void:
	Radio.say(_sender(), text, Radio.Kind.CONTROL, delay, _clip(key) if key != "" else "")


func _pick(arr: Array) -> String:
	return String(arr[_rng.randi() % arr.size()])


var _last_take: Dictionary = {}


## Says one take of a voiced set (text and recording kept together), only takes whose recording exists,
## never the same one twice running.
func _say_take(table: Dictionary, key: String, delay: float = 0.0) -> void:
	var lines: Array = table[side]
	var avail: Array = []
	for i in lines.size():
		if _clip("%s_%d" % [key, i + 1]) != "" and i != int(_last_take.get(key, -1)):
			avail.append(i)
	if avail.is_empty():
		for i in lines.size():
			if i != int(_last_take.get(key, -1)):
				avail.append(i)
	var k: int = int(avail[_rng.randi() % avail.size()]) if not avail.is_empty() else 0
	_last_take[key] = k
	_say(String(lines[k]), delay, "%s_%d" % [key, k + 1])


const SUCCESS_LINES := {
	"Allies": ["Good show! Ops confirms the job's done.", "Splendid work. That's one off the board.", "Ops here - well done, that's a confirmed result.", "Bang on. Group are delighted. Stand by for more.",
		"Lovely job. Intelligence are very pleased with you.", "That's the stuff. Chalk that one up.", "Confirmed and logged. Nicely done.", "Well done indeed. The Wingco sends his compliments.",
		"Excellent show. That'll please the Air Commodore.", "Job done. Good flying.",
		"Lovely work. That's one for the scoreboard.", "Well done. Group are delighted.", "Good show. Job confirmed.", "Nicely done. Stand by."],
	"Axis": ["Well done! The job is confirmed.", "Excellent work. Jafü is pleased.", "Confirmed - the job is done. Stand by.", "Well flown. That one is finished.",
		"Good work. The General will hear of this.", "Confirmed. A clean job, well done.", "Excellent. That one is off the list.", "Very good. Command sends its compliments.",
		"Excellent. Command will be pleased.", "Job done. Good flying.",
		"Good work. That one is on the list.", "Well done. Command is pleased.", "Good. Job confirmed.", "Nicely done. Stand by."],
}

const FAIL_LINES := {
	"Allies": ["Never mind. We'll get them next time.", "That one got away. Stand by.", "Hard luck. Can't win them all.", "Damn. Well, it's done now. Stand by.", "That's a miss, I'm afraid. Keep your chin up.",
		"Bad luck. They got away with it.", "Never mind. There'll be other days.", "That one's slipped through. Stand by."],
	"Axis": ["A pity. We will get them next time.", "That one escaped. Stand by.", "Bad luck. We cannot win them all.", "That is a failure. Stand by for new orders.", "A miss. Do better next time.",
		"Bad luck. They got away.", "Never mind. There will be other days.", "That one escaped. Stand by."],
}

const HIT_LINES := {
	"Allies": ["Direct hit! That's the job done - good shooting.", "Strike confirmed! You've hit them. Job done.", "Ops here - we have a hit reported. Well done!",
		"Observers report a hit! Lovely shooting.", "That's a hit! Job done, well flown.",
		"Bang on target! Well done.",
		"Hit! Hit! Job done.", "Good hit. That's the job finished.", "We have a hit. Well flown."],
	"Axis": ["Direct hit! The job is done. Good shooting.", "Hit confirmed! That is the job done.", "Jafü here - a hit is reported. Well done!",
		"Observers report a hit! Excellent shooting.", "A hit! The job is done. Well flown.",
		"Right on target! Well done.",
		"Hit! Hit! Job done.", "A good hit. That is the job finished.", "A hit is confirmed. Well flown."],
}

const RV_JOIN := {
	"Allies": ["Tally-ho, leader. Joining up on your wing.", "Got you visual. Forming up on you now.", "There you are! Taking station on your left."],
	"Axis": ["Leader in sight. Joining up.", "I see you. Forming up on your wing.", "There you are. Taking position on your left."],
}

const INTEL_ACK := {
	"Allies": ["Thank you. We'll pass that to Intelligence and lay something on.", "Noted. That'll make a nice target for someone - perhaps you."],
	"Axis": ["Understood. Intelligence will be informed.", "Noted. That will be a target soon - perhaps for you."],
}

const OPENERS := {
	"Allies": ["{call}, this is Sector Control.", "Hello {call}, Ops here.", "{call}, Sector. New tasking for you.", "{call}, Ops Room. Listen carefully.",
		"{call}, Sector Control. Got a job for you.", "Hello {call}. Ops again - something's come up.", "{call}, Sector here. Are you receiving?",
		"Hello {call}, Ops calling. New job for you.",
		"{call}, sector calling. Another job.", "{call}, Ops here. Something for you.", "{call}, hello, Sector. Listen in.", "{call}, Ops Room calling. New tasking."],
	"Axis": ["{call}, here is Jafü 2.", "{call}, ground control calling.", "{call}, new orders from Jafü.", "Attention {call}, Jafü here.",
		"{call}, Jafü. A job for you.", "{call}, ground control again. Something has come up.", "{call}, Jafü here. Do you hear me?",
		"{call}, Jafü calling. New job for you.",
		"{call}, Jafü calling. Another job.", "{call}, ground control here. Something for you.", "{call}, Jafü. Listen carefully.", "{call}, ground control calling. New orders."],
}

## A second job close to where the last one was finished.
const FOLLOWUPS := {
	"Allies": ["{call}, while you're up there - something else close by.", "{call}, don't go home yet. We've another one near you.", "{call}, Ops. Since you're in the area...", "{call}, stay out a little longer. One more for you.",
		"{call}, while you're out there, one more.", "{call}, don't turn for home yet. Another job nearby.", "{call}, since you're close by, another one for you.", "{call}, stay out. We've something near you."],
	"Axis": ["{call}, while you are up there - something else nearby.", "{call}, do not go home yet. Another job near you.", "{call}, Jafü. Since you are in the area...", "{call}, stay out a little longer. One more for you.",
		"{call}, while you are out there, one more.", "{call}, do not turn for home yet. Another job nearby.", "{call}, you are close by, so another one for you.", "{call}, stay out. We have something near you."],
}

## The spoken headline for each kind (voiced; "ops/<side>/brief_<kind>_N"), then the details as text.
const HEADLINES := {
	"strike": ["Priority target for you. Bombs on it, please.", "Intelligence wants a target put out of action. Go and stop it.", "We've a target that needs knocking out. Expect flak.", "Bombing job. Get in, put them on the target, and get out.", "Group want that target flattened. Off you go.", "Target for tonight's photographs. Make it a good one.", "We've a target that wants hitting. Make every bomb count.", "Intelligence have found something juicy. Go and hit it.", "Target for you. Get in under the flak and let them have it.", "Bombs on the target, please. Then straight home.", "Something needs flattening. That's your job."],
	"airfield": ["Their fighters are on the ground refuelling. Go and catch them there.", "An enemy airfield is full of aircraft. Shoot it up.", "We want an airfield put out of business. Anything you can hit.", "Catch them on the ground. Strafe the dispersals.", "Their airfield's busy. Go and make a mess of it.", "Fighters refuelling on that field. Hit them now.", "Their aircraft are lined up on the field. Shoot them up.", "An airfield needs a visit. Strafe anything you see.", "Catch their fighters before they get off the ground.", "Shoot up their airfield. Aircraft first, then anything else.", "Their field's full. Go and empty it."],
	"convoy": ["A road convoy has been seen on the move. Find it and stop it.", "The Resistance reports a convoy heading for the front. Hit it.", "There's a column on the road. Strafe the lot.", "Lorries on the move. Shoot them up.", "Transport column on the road. Stop it.", "Vehicles moving to the coast. Catch them in the open.", "A column of lorries is heading for the front. Stop it.", "Road traffic reported. Shoot up the lot.", "Convoy on the move. Go for the leading vehicle first.", "Vehicles on the road. Make a mess of them.", "Hit that column before it reaches cover."],
	"train": ["A train is leaving the yards. Stop that train.", "Railway watchers report a train running. Go for the locomotive first.", "Big train on the line. It must not get through.", "A goods train is running. Knock out the engine.", "There's a train on the line. Stop it dead.", "Train on the move. Stop the engine and you stop the lot.", "Supplies going by rail. Shoot up that train.", "A train's been seen leaving the sidings. Get after it.", "Locomotive first, then the wagons.", "There's a train that mustn't arrive. See to it."],
	"shipping": ["A convoy is steaming along their coast. Sink what you can.", "Coastal Command has shipping for you. Escorts with it, watch the flak.", "Shipping strike. Go low and go fast.", "Ships off the coast. Go and sink them.", "Coasters with escorts. Low and fast.", "Enemy ships hugging the coast. Go in low.", "There's shipping for you. Watch the escorts.", "A small convoy off their coast. Sink what you can.", "Ships for you. Go in under their guns.", "Sink what you can and get out quick."],
	"eboats": ["Fast boats putting out to sea. Catch them before they reach our convoys.", "Radar has motor boats leaving harbour. Sink them.", "Boats heading out. They're quick, so get in close.", "E-boats on the prowl. Find them and sink them.", "Fast boats heading for our convoy. Stop them.", "Fast boats out hunting. Get them before they find our ships.", "Motor boats leaving harbour. They're quick, so get in close.", "E-boats reported. Sink them.", "Fast boats making a run. Catch them.", "Boats at sea. Strafe them before they get home."],
	"intercept": ["Raid building up. Vector to intercept.", "Bandits approaching the coast with fighter escort. Get after them.", "Bombers heading inland. Intercept.", "Raid coming in. Get up there and break it up.", "Bombers on the plot. Vector to intercept.", "Raid approaching. Get after them, and don't let them through.", "Bombers crossing the coast. Get stuck in.", "Big raid on the board. Intercept, and mind the escort.", "Bandits heading for one of our towns. Stop them.", "Raiders inbound. Go and meet them.", "Bombers heading our way. Stop them short."],
	"cover": ["Our convoy is under attack by dive bombers. Get over there and break it up.", "The convoy is calling for help. Buster!", "Dive bombers going for our ships. Protect them.", "Our ships are being bombed. Get over them now.", "Dive bombers on the convoy. Buster!", "Our ships are calling for help. Get over them.", "The convoy's under attack. Break it up.", "Dive bombers on our shipping. Go!", "Our ships need you overhead. Hurry.", "The convoy's being bombed. Get there fast."],
	"sweep": ["Enemy fighters patrolling over their side. Sweep them out of the sky.", "Free hunt. Go and find their fighters.", "Their fighters are getting cocky. Teach them a lesson.", "Fighter sweep. Clear the sky over their side.", "Go and hunt their fighters.", "Their fighters are about. Go and find them.", "Free chase. Go and make a nuisance of yourself.", "Fighter sweep. See what you can stir up.", "Go and hunt over their side. Good hunting.", "Go and stir them up. Fighters only.", "Clear their fighters out of the sky."],
	"rescue": ["One of ours is down in the sea in a dinghy. Find him and circle low until the launch has a fix.", "Mayday picked up. A pilot in the drink. Circle him low so the boat can home in.", "A crew has ditched. Find the dinghy and stay with them.", "A pilot's in the water. Find him and circle.", "Dinghy reported. Go and find him.", "Pilot in the drink. Find him and stay with him.", "A dinghy's been seen. Circle low till the launch arrives.", "One of ours is in the sea. Go and find him.", "A chap's in the water. Go and find him.", "Find the dinghy and stay low over it."],
	"recce": ["We need fresh photographs. One pass, low and wings level, then bring the film home.", "Photo job for you. A steady run over the top, then straight back to base.", "Group want pictures. Get them home and you've done your bit.", "Photo run for you. Keep it steady.", "We need pictures. One clean pass, then home.", "Photographic job. Straight and level over the top.", "Intelligence want photographs. Bring them home.", "Camera job. One good run, then home.", "Pictures wanted. Steady over the target.", "One clean photo run. Don't hang about."],
	"escort": ["Bombers need an escort. Meet them at the rendezvous and see them to the target.", "Close escort job. Pick up the bombers at the rendezvous and keep the fighters off them.", "Our bombers are going in. Meet them and bring them home.", "Escort job. Look after the bombers.", "Bombers need cover. Meet them at the rendezvous.", "The bombers are counting on you. Don't leave them.", "Bomber escort. Stay with them all the way.", "Our bombers are going over. Keep the fighters off.", "Meet the bombers and see them home safe.", "Look after the bombers. They're relying on you.", "Escort job. Don't let them be picked off."],
	"intruder": ["Intruder job. Their bombers are coming home and the flare path is lit. Catch them in the circuit.", "Night intruder. Get over their airfield while they're landing.", "Their airfield is lit up for returning bombers. Go and spoil the party.", "Intruder job. Catch them landing.", "Get over their airfield in the dark.", "Night intruder. Catch them in the circuit.", "Their bombers are landing. Go and spoil it.", "Their flare path is lit. Get in among them.", "Into the dark with you. Catch them landing.", "Their circuit's busy. Go and join it."],
}

const DETAILS := {
	"strike": "Target: the {what}, {place}.",
	"airfield": "Target: {what}, {place}.",
	"convoy": "A {what} {place}.",
	"train": "An {what} {place}.",
	"shipping": "A {what} {place}.",
	"eboats": "{what} {place}.",
	"intercept": "{count} {what} at angels {angels}, target {place}.",
	"cover": "{count} {what} attacking {place}.",
	"sweep": "{what} {place}, angels {angels}.",
	"rescue": "Dinghy {place}.",
	"recce": "Photograph the {what}, {place}. Under 1500 m, wings level.",
	"escort": "Target: the {what}, {place}.",
	"intruder": "{what}, {place}.",
}


func _announce(info: Dictionary) -> void:
	var kind: String = str(info["kind"])
	var fmt: Dictionary = {"what": str(info.get("what", "target")), "place": str(info.get("place", "")),
		"count": str(info.get("count", 3)), "angels": str(info.get("angels", 10)), "call": Radio.player_callsign}
	if bool(info.get("scramble", false)):
		_say("Scramble! Scramble! Raid approaching - get airborne now!", 0.0, "scramble_1")
	elif bool(info.get("followup", false)):
		var fl: Array = FOLLOWUPS[side]
		var favail: Array = []
		for k in fl.size():
			if (k < 4 or _clip("followup_%d" % (k + 1)) != "") and k != int(_last_take.get("followup", -1)):
				favail.append(k)
		var fi: int = int(favail[_rng.randi() % favail.size()]) if not favail.is_empty() else 0
		_last_take["followup"] = fi
		_say(String(fl[fi]).format(fmt), 0.0, "followup_%d" % (fi + 1))
	else:
		var ops_open: Array = OPENERS[side]
		var oavail: Array = []
		for k in ops_open.size():
			if _clip("open_%d" % (k + 1)) != "" and k != int(_last_take.get("open", -1)):
				oavail.append(k)
		if oavail.is_empty():
			oavail = [0, 1, 2, 3]
		var oi: int = int(oavail[_rng.randi() % oavail.size()])
		_last_take["open"] = oi
		_say(String(OPENERS[side][oi]).format(fmt), 0.0, "open_%d" % (oi + 1))
	if info.has("from_intel"):
		_say("Your report on the %s checks out." % str(info["from_intel"]), 0.3, "intel_followup_1")
	var heads: Array = HEADLINES[kind]
	var havail: Array = []
	for k in heads.size():
		if (k < 3 or _clip("brief_%s_%d" % [kind, k + 1]) != "") and k != int(_last_take.get("brief_" + kind, -1)):
			havail.append(k)
	var hi: int = int(havail[_rng.randi() % havail.size()]) if not havail.is_empty() else 0
	_last_take["brief_" + kind] = hi
	_say(String(heads[hi]), 0.4, "brief_%s_%d" % [kind, hi + 1])
	var p: Vector3 = info["pos"]
	_say(String(DETAILS[kind]).format(fmt) + " Steer %03d, %d km." % [_bearing(p), int(round(_dist_km(p)))], 0.6)
	if str(info.get("stage", "")) == "rv":
		var rv: Vector3 = info["rv"]
		_say("Rendezvous first with %s %s - steer %03d, %d km. They'll go in with you." % [str(info["section"]) if kind != "escort" else "the bombers",
			_place_name(rv), _bearing(rv), int(round(_dist_km(rv)))], 0.8, "rv_set_%d" % (1 + _rng.randi() % 2))
	if supply > 0 and kind in ["strike", "airfield", "convoy", "train", "recce", "intruder"]:
		_say("Expect more flak than usual - they've been well supplied lately.", 1.0, "pressure_flak_1")
	if hud and hud.has_method("show_message"):
		hud.call("show_message", ("SCRAMBLE: " if bool(info.get("scramble", false)) else "NEW TASKING: ") + str(info["title"]).to_upper(), 5.0)


## A minimap marker node at the objective (the HUD also draws the objective diamond / edge arrow).
func _add_marker(info: Dictionary) -> void:
	var n := Node3D.new()
	world.add_child(n)
	n.global_position = info["pos"]
	info["marker"] = n


## Pins for the chart (key M): only what Ops has announced - the objective, the rendezvous, live V-1s.
func map_pins() -> Array:
	var out: Array = []
	if not active.is_empty():
		var np: Variant = nav_point()
		var obj: Variant = active.get("pos")
		var tr: Variant = active.get("track")
		if tr != null and is_instance_valid(tr) and str(active.get("stage", "")) != "rv":
			obj = nav_point()
		out.append({"pos": obj, "name": str(active["title"]), "col": Color(1.0, 0.82, 0.25), "main": true})
		if active.has("rv") and str(active.get("stage", "")) == "rv":
			out.append({"pos": active["rv"], "name": "RV: " + str(active.get("section", "bombers")), "col": Color(0.45, 0.85, 1.0), "main": false})
		if str(active.get("stage", "")) == "home" and np != null:
			out.append({"pos": np, "name": "Home - land with the photos", "col": Color(0.45, 0.95, 0.5), "main": false})
	for v in _v1s:
		if is_instance_valid(v):
			out.append({"pos": (v as Node3D).global_position, "name": "V-1", "col": Color(1.0, 0.2, 0.6), "main": false})
	return out


func _build_label() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.82))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 4)
	if hud and hud.has_method("add_widget"):
		hud.call("add_widget", _label)


func _refresh_label() -> void:
	if _label == null or not is_instance_valid(_label):
		return
	var c: Dictionary = PilotLog.career(side)
	var t: String = "OPS ROOM   done %d   missed %d   %s" % [completed, failed, PilotLog.rank_of(side, int(c["points"]))]
	if active.is_empty():
		t += "\nNext tasking in %d:%02d" % [int(_next_t) / 60, int(_next_t) % 60]
		if not _intel.is_empty():
			t += "   intel reports: %d" % _intel.size()
	else:
		var stage: String = str(active.get("stage", ""))
		t += "\n" + (("RV WITH " + str(active.get("section", "THE BOMBERS")).to_upper() + " - THEN ") if stage == "rv" else "") + str(active["title"]).to_upper()
		t += "   (P: skip)"
		if bool(active.get("scramble", false)):
			t += "\nSCRAMBLE  %d s" % int(active["scramble_t"])
		var np: Variant = nav_point()
		if np != null:
			t += "\n%03d  %.1f km" % [_bearing(np), _dist_km(np)]
		match str(active["goal"]):
			"orbit":
				t += "   fix %d%%" % int(100.0 * float(active["got_t"]) / float(active["need_t"]))
			"escort":
				if active.has("form"):
					var alive: int = 0
					for m in active["friends"]:
						if is_instance_valid(m) and (m as Aircraft).state == Aircraft.State.ALIVE:
							alive += 1
					t += "   bombers %d" % alive
			"photo":
				t += "   " + ("photos taken - land at base" if stage == "home" else "low pass, wings level")
			_:
				t += "   one hit will do"
	if supply > 0 or air_threat > 0 or v1_threat > 0:
		t += "\nFRONT  flak +%d   fighters +%d%s" % [supply, air_threat, ("   V-1 ALERTS" if v1_threat > 0 and side == "Allies" else "")]
	_label.text = t


# ------------------------------------------------------------------ logbook (key J)

func _build_logbook_ui() -> void:
	_log_ui = CanvasLayer.new()
	_log_ui.layer = 30
	_log_ui.visible = false
	add_child(_log_ui)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(760, 560)
	panel.position = Vector2(-380, -280)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.06, 0.94)
	sb.border_color = Color(0.85, 0.75, 0.45)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	_log_ui.add_child(panel)
	_log_lbl = Label.new()
	_log_lbl.add_theme_font_size_override("font_size", 16)
	_log_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	_log_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_log_lbl)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_J:
		_log_ui.visible = not _log_ui.visible
		if _log_ui.visible:
			_fill_logbook()
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_P and not active.is_empty():
		_skip_active()
		get_viewport().set_input_as_handled()


## Skip the current tasking with no penalty (no points lost, not counted as missed) and bring the next one in shortly.
func _skip_active() -> void:
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "TASKING SKIPPED - next one coming in", 2.5)
	_end_active(false, true, true)
	_next_t = minf(_next_t, 3.0) if not _test else 1.0


func _fill_logbook() -> void:
	_log_lbl.text = PilotLog.logbook_text(side) + "
(J to close)"
