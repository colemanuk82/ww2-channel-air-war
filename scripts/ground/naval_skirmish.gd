class_name NavalSkirmish
extends Node3D
## Occasional sea fights in view of the player: E-boats (S-boote) rushing a British coastal convoy, MTBs / MGBs and
## destroyers hitting a German coastal convoy, destroyer duels. The manager watches the ships near the player;
## when opposing ships come within gun range (or, now and then, when an opposing patrol is spawned off a convoy in
## view) it starts an ENGAGEMENT: ships manoeuvre (GroundShip._process hands them to drive() while engaged), fire
## shells that straddle then bracket (spread() shrinks with every salvo), light fires, list, slow and sink through
## the existing GroundShip damage / sinking, and the side friendly to the player calls for air support on the radio
## (text only, once per engagement). Fast boats make torpedo runs, break away and come round again.
## Everything is cheap when nothing is happening (a scan every 2 s) and FX are skipped beyond view range.
## Debug: --naval-test (a convoy and an attack in front of the player), --naval-log, --naval-every=SECS (cooldown),
## --naval-kind=eboat|mtb|destroyer, --naval-team=Allies|Axis (the convoy's side in --naval-test).
## Shared helper (tiny): NavalSkirmish.request_air_support(hud, sender, text, world_pos, player_pos) sends a radio call
## + HUD message with bearing and range; other systems may use it.

## Gun fits: range (m), reload (s), shells per salvo, damage per hit, shell speed (m/s), splash size, dispersion (fraction
## of range, 1 sigma), muzzle blast scale. Light craft fire cannon bursts, destroyers 4.7 inch salvos.
const GUNS: Dictionary = {
	"destroyer": {"range": 3200.0, "cd": 5.0, "n": 4, "dmg": 34.0, "spd": 430.0, "plume": 6.0, "sig": 0.040, "blast": 1.0},
	"cruiser": {"range": 4800.0, "cd": 5.5, "n": 6, "dmg": 46.0, "spd": 480.0, "plume": 8.0, "sig": 0.038, "blast": 1.4},
	"trawler": {"range": 2300.0, "cd": 4.0, "n": 1, "dmg": 20.0, "spd": 380.0, "plume": 3.5, "sig": 0.050, "blast": 0.5},
	"eboat": {"range": 1100.0, "cd": 2.2, "n": 5, "dmg": 6.0, "spd": 520.0, "plume": 1.6, "sig": 0.034, "blast": 0.3},
	"mtb": {"range": 1000.0, "cd": 2.0, "n": 5, "dmg": 6.0, "spd": 520.0, "plume": 1.6, "sig": 0.034, "blast": 0.3},
}
const TURN: Dictionary = {"destroyer": 0.30, "cruiser": 0.22, "trawler": 0.36, "eboat": 0.9, "mtb": 0.9}
const TORP_SPEED: float = 18.0
const TORP_RANGE: float = 1100.0
const TORP_ARM: float = 90.0
const TORP_DAMAGE: float = 240.0
const FIRST_DELAY: Vector2 = Vector2(150.0, 260.0)
const COOLDOWN: Vector2 = Vector2(330.0, 660.0)
const Tempo := preload("res://scripts/modes/activity_tempo.gd")     # lulls hold back new sea fights; Busy / Quiet scale the gap
const MAX_ENGAGE_AGE: float = 150.0
const VIEW_FX: float = 6500.0           # no effects beyond this distance from the camera
const CULL_DIST: float = 14000.0        # an engagement this far from the player is simply dropped
const ALLIED_CONVOY_NAMES: Array = ["Peewit", "Booty", "Agent", "Bacon", "Arena", "Bosom", "Pilot", "Hyson"]
const PLACES: Array = [
	["Dungeness", 50.91, 0.98], ["Dover", 51.13, 1.31], ["Folkestone", 51.08, 1.19], ["Beachy Head", 50.73, 0.25],
	["Calais", 50.96, 1.85], ["Cap Gris-Nez", 50.87, 1.58], ["Boulogne", 50.73, 1.58], ["Dunkirk", 51.05, 2.37],
	["Ostend", 51.23, 2.92], ["North Foreland", 51.38, 1.44], ["Brighton", 50.82, -0.14], ["Harwich", 51.95, 1.29],
	["Flushing", 51.45, 3.60], ["Cherbourg", 49.65, -1.62], ["Portland Bill", 50.52, -2.46], ["Selsey Bill", 50.72, -0.79],
]

var world: Node
var player: Node3D
var hud: Node
var side: String = "Allies"            # the player's side
var engagements: Array = []            # Dictionaries, see start_engagement()
var cooldown: float = 200.0
var log_on: bool = false
var test_mode: bool = false
var radio_enabled: bool = true
var self_drive: bool = false           # unit tests: step() also drives the ships (no frames run)
var started: int = 0
var forced_kind: String = ""
var forced_team: String = ""
var cooldown_every: float = -1.0

var _tick: float = 1.0
var _ctl: Dictionary = {}              # ship instance id -> control Dictionary
var _shells: Array = []
var _torps: Array = []
var _after: Array = []                 # ships still driven after their engagement ended (rejoining the convoy / leaving)
var _tracers: Array = []
var _tr_next: int = 0
var _tr_mat: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
var _next_id: int = 1
var _test_done: bool = false
var _args: PackedStringArray = OS.get_cmdline_user_args()
# debug pictures: --naval-shots=<dir> [--naval-tag=day|night] with --naval-test (hidden desktop only)
var shots_dir: String = ""
var shot_tag: String = "day"
var _shot_times: Array = [10.0, 24.0, 40.0, 58.0, 80.0]
var _shot_i: int = 0
var _shot_cam: Camera3D
var _fps_sum: float = 0.0
var _fps_n: int = 0
var _fps_min: float = 1000.0


# ------------------------------------------------------------------ pure helpers (unit-tested)

static func is_armed(stype: String) -> bool:
	return GUNS.has(stype)


## True when two ships of opposing sides are in gun range (at least one of them armed with range >= dist).
static func can_engage(type_a: String, team_a: String, type_b: String, team_b: String, dist: float) -> bool:
	if team_a == team_b or team_a == "Neutral" or team_b == "Neutral":
		return false
	var reach: float = 0.0
	for t in [type_a, type_b]:
		if GUNS.has(t):
			reach = maxf(reach, float(GUNS[t]["range"]))
	return reach > 0.0 and dist <= reach


## Chance per scan (every 2 s) that opposing ships in range open fire. Zero during the cooldown; closer and darker is likelier.
static func engage_chance(dist: float, reach: float, cooldown_left: float, night: bool) -> float:
	if cooldown_left > 0.0 or reach <= 0.0 or dist > reach:
		return 0.0
	var c: float = 0.12 * (1.0 - 0.5 * clampf(dist / reach, 0.0, 1.0))
	return c * (1.5 if night else 1.0)


## One-sigma shell dispersion (m) at range_m after k salvos on the same target: the first salvos straddle widely, then the
## fire creeps onto the target (bracketing).
static func spread(stype: String, range_m: float, k: int) -> float:
	var g: Dictionary = GUNS.get(stype, GUNS["trawler"])
	return float(g["sig"]) * range_m * maxf(0.4, 1.6 * pow(0.72, float(k)))


## Probability that one shell with 1-sigma dispersion `sigma` lands within `radius` of the aim point (circular normal).
static func hit_probability(sigma: float, radius: float) -> float:
	if sigma <= 0.001:
		return 1.0
	return 1.0 - exp(-(radius * radius) / (2.0 * sigma * sigma))


## What attacks a convoy of `convoy_team`: {types, label, att_team}. r in 0..1 (rolled by the caller).
static func pick_scenario(convoy_team: String, night: bool, has_destroyer: bool, r: float, rn: float = 0.5) -> Dictionary:
	var n: int = 2 + int(rn * 2.99)          # 2..4 boats
	if convoy_team == "Allies":
		var duel: float = 0.10 if night else (0.30 if has_destroyer else 0.18)
		if r < duel:
			return {"types": ["destroyer"], "label": "a German destroyer", "att_team": "Axis"}
		var t: Array = []
		for i in n:
			t.append("eboat")
		return {"types": t, "label": "E-boats", "att_team": "Axis"}
	var duel2: float = 0.14 if night else 0.28
	if r < duel2:
		return {"types": ["destroyer"] if rn < 0.6 else ["destroyer", "destroyer"], "label": "destroyers", "att_team": "Allies"}
	var t2: Array = []
	for i in n:
		t2.append("mtb")
	return {"types": t2, "label": "MTBs" if rn < 0.5 else "MGBs", "att_team": "Allies"}


static func place_name(p: Vector3) -> String:
	var best: String = ""
	var bd: float = 32000.0
	for pl in PLACES:
		var q: Vector3 = WorldCoords.latlon_to_world(float(pl[1]), float(pl[2]))
		var d: float = Vector2(q.x - p.x, q.z - p.z).length()
		if d < bd:
			bd = d
			best = str(pl[0])
	return best


static func bearing_deg(from: Vector3, to: Vector3) -> int:
	var h: float = WorldCoords.dir_to_heading(Vector3(to.x - from.x, 0.0, to.z - from.z))
	return int(round(fposmod(h, 360.0))) % 360


## The request: friendly convoy under attack (own = true) or friendly boats attacking an enemy convoy (own = false).
static func call_text(own: bool, convoy_name: String, attackers: String, place: String, bearing: int, miles: int, player_side: String) -> String:
	var where: String = ("off %s" % place) if place != "" else "in mid-Channel"
	if own:
		if player_side == "Allies":
			return "Convoy %s under attack by %s %s, any aircraft in the area, request immediate support! Bearing %03d, %d miles." % [convoy_name, attackers, where, bearing, miles]
		return "%s under attack by %s %s. Any aircraft in the area, request immediate air support! Bearing %03d, %d miles." % [convoy_name, attackers, where, bearing, miles]
	return "All aircraft, this is %s. We are engaging an enemy convoy %s and need air support. Bearing %03d, %d miles." % [convoy_name, where, bearing, miles]


## Small shared helper: radio call + HUD message. Nothing is queued twice here; the caller decides when to call it.
static func request_air_support(p_hud: Node, sender: String, text: String, world_pos: Vector3, player_pos: Vector3, voice_cat: String = "") -> void:
	var miles: int = int(round(Vector2(world_pos.x - player_pos.x, world_pos.z - player_pos.z).length() / 1609.0))
	var tail: String = " (bearing %03d, %d miles)" % [bearing_deg(player_pos, world_pos), miles]
	Radio.say(sender, text, Radio.Kind.FRIENDLY, 0.5, Radio.chatter_clip(voice_cat) if voice_cat != "" else "", true)
	if p_hud != null and is_instance_valid(p_hud) and p_hud.has_method("show_message"):
		p_hud.call("show_message", "Air support requested" + tail, 6.0)


static func yaw_of(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


static func forward_of(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static var all_water: bool = false      # unit tests (their terrain is dry land everywhere)


static func is_water_at(x: float, z: float) -> bool:
	return all_water or GroundKit.raw_y(x, z) <= 0.3


# ------------------------------------------------------------------ setup and scanning

func setup(p_world: Node, p_player: Node3D, p_hud: Node, p_side: String, _difficulty: float = 0.5) -> void:
	world = p_world
	player = p_player
	hud = p_hud
	side = p_side
	_rng.randomize()
	cooldown = _rng.randf_range(FIRST_DELAY.x, FIRST_DELAY.y)
	log_on = _args.has("--naval-log") or _args.has("--naval-test")
	for a in _args:
		if a == "--naval-test":
			test_mode = true
			cooldown = 4.0
		elif a.begins_with("--naval-every="):
			cooldown_every = float(a.substr(14))
			cooldown = maxf(cooldown_every, 5.0)
		elif a.begins_with("--naval-kind="):
			forced_kind = a.substr(13)
		elif a.begins_with("--naval-team="):
			forced_team = a.substr(13)
		elif a.begins_with("--naval-shots="):
			shots_dir = a.substr(14)
		elif a.begins_with("--naval-tag="):
			shot_tag = a.substr(12)
	if Weapons != null and Weapons.has_signal("player_hit") and not Weapons.player_hit.is_connected(_on_player_hit):
		Weapons.player_hit.connect(_on_player_hit)


func _log(msg: String) -> void:
	if log_on:
		print("[naval] ", msg)


func _cam() -> Camera3D:
	if not is_inside_tree():
		return null
	return get_viewport().get_camera_3d()


func _near(p: Vector3, r: float = VIEW_FX) -> bool:
	var cam: Camera3D = _cam()
	return cam != null and cam.global_position.distance_to(p) < r


func _night() -> bool:
	return FX != null and FX.night_factor() > 0.55


func _process(delta: float) -> void:
	step(minf(delta, 0.1))


## One simulation step (also called directly by the unit tests).
func step(dt: float) -> void:
	if Tempo.lulling and cooldown < 6.0:
		cooldown = 6.0            # a lull in the air war (activity_tempo.gd): no new sea fight until it is over
	if cooldown > 0.0:
		cooldown -= dt
	_tick -= dt
	if _tick <= 0.0:
		_tick = 2.0
		_scan()
	if not _after.is_empty():
		_step_after(dt)
	if engagements.is_empty() and _shells.is_empty() and _torps.is_empty():
		return
	for e in engagements.duplicate():
		_step_engagement(e as Dictionary, dt)
	_step_shells(dt)
	_step_torps(dt)
	if shots_dir != "":
		_shot_tick(dt)
	var i: int = engagements.size() - 1
	while i >= 0:
		if bool((engagements[i] as Dictionary).get("done", false)):
			engagements.remove_at(i)
		i -= 1


func _ships_near_player(r: float) -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group("ship"):
		var sh := n as GroundShip
		if sh == null or not is_instance_valid(sh) or sh.is_dead or not sh.is_inside_tree():
			continue
		if sh.team != "Allies" and sh.team != "Axis":
			continue
		if player != null and is_instance_valid(player) and Vector2(sh.global_position.x - player.global_position.x, sh.global_position.z - player.global_position.z).length() > r:
			continue
		out.append(sh)
	return out


func _engaged(sh: Node) -> bool:
	return _ctl.has(sh.get_instance_id()) or (sh is GroundShip and (sh as GroundShip).skirmish != null)


func _scan() -> void:
	if player == null or not is_instance_valid(player) or not is_inside_tree():
		return
	if test_mode and not _test_done and cooldown <= 0.0:
		_test_done = true
		_spawn_test_scene()
		return
	if not engagements.is_empty():
		return
	if cooldown > 0.0:
		return
	var night: bool = _night()
	var ships: Array = _ships_near_player(9000.0)
	# 1. opposing ships already in gun range of each other
	var pair: Array = []
	var best_p: float = 0.0
	for i in ships.size():
		var a: GroundShip = ships[i]
		if _engaged(a):
			continue
		for j in range(i + 1, ships.size()):
			var b: GroundShip = ships[j]
			if _engaged(b) or a.team == b.team:
				continue
			var d: float = Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()
			if not can_engage(a.stype, a.team, b.stype, b.team, d):
				continue
			var reach: float = 0.0
			for t in [a.stype, b.stype]:
				if GUNS.has(t):
					reach = maxf(reach, float(GUNS[t]["range"]))
			var p: float = engage_chance(d, reach, cooldown, night)
			if p > best_p and _rng.randf() < p:
				best_p = p
				pair = [a, b]
	if pair.size() == 2:
		_start_natural(pair[0], pair[1], ships)
		return
	# 2. an opposing patrol turns up off a convoy that is in view
	if _rng.randf() > 0.22:
		return
	var cands: Array = []
	for n in get_tree().get_nodes_in_group("convoy"):
		var cv := n as Convoy
		if cv == null or not cv.naval or cv.is_dead or cv.alive_count() < 2 or cv.team == "Neutral":
			continue
		if cv.composition in ["neptune", "fishing", "dunkirk"]:
			continue
		var c: Vector3 = cv.get_center()
		var dist: float = Vector2(c.x - player.global_position.x, c.z - player.global_position.z).length()
		if dist < 1500.0 or dist > 8000.0:
			continue
		var busy: bool = false
		for u in cv.units:
			if is_instance_valid(u) and _engaged(u):
				busy = true
				break
		if not busy:
			cands.append(cv)
	if cands.is_empty():
		return
	_spawn_attack(cands[_rng.randi() % cands.size()] as Convoy)


func _start_natural(a: GroundShip, b: GroundShip, ships: Array) -> void:
	var att: Array = [a] if is_armed(a.stype) else [b]
	var tgt: GroundShip = b if att[0] == a else a
	var defs: Array = [tgt]
	for s2 in ships:
		var o: GroundShip = s2
		if o != tgt and o.team == tgt.team and not _engaged(o) and Vector2(o.global_position.x - tgt.global_position.x, o.global_position.z - tgt.global_position.z).length() < 1600.0:
			defs.append(o)
	var friend_att: Array = [att[0]]
	for s3 in ships:
		var o2: GroundShip = s3
		if o2 != att[0] and o2.team == att[0].team and not _engaged(o2) and is_armed(o2.stype) and Vector2(o2.global_position.x - att[0].global_position.x, o2.global_position.z - att[0].global_position.z).length() < 1200.0:
			friend_att.append(o2)
	start_engagement(friend_att, defs, "enemy ships", false, _convoy_name(tgt))


func _convoy_name(sh: GroundShip) -> String:
	var cid: String = str(sh.get_meta("convoy_id", ""))
	var h: int = absi(hash(cid + sh.team))
	if sh.team == "Allies":
		return ALLIED_CONVOY_NAMES[h % ALLIED_CONVOY_NAMES.size()]
	return "Geleit Nordsee %d" % (1 + h % 9)


# ------------------------------------------------------------------ spawning an attack off a convoy

func _spawn_attack(cv: Convoy) -> void:
	var night: bool = _night()
	var has_dd: bool = false
	for u in cv.units:
		if is_instance_valid(u) and (u as GroundShip).stype == "destroyer" and not (u as GroundShip).is_dead:
			has_dd = true
	var sc: Dictionary = pick_scenario(cv.team, night, has_dd, _rng.randf(), _rng.randf())
	if forced_kind != "":
		var t: Array = []
		for i in (1 if forced_kind == "destroyer" else 3):
			t.append(forced_kind)
		sc = {"types": t, "label": {"eboat": "E-boats", "mtb": "MTBs", "destroyer": "a destroyer"}.get(forced_kind, "enemy ships"), "att_team": "Axis" if forced_kind == "eboat" else ("Allies" if forced_kind == "mtb" else cv.team)}
		if forced_kind == "destroyer":
			sc["att_team"] = "Axis" if cv.team == "Allies" else "Allies"
	var center: Vector3 = cv.get_center()
	var lead: GroundShip = null
	for u2 in cv.units:
		if is_instance_valid(u2) and not (u2 as GroundShip).is_dead:
			lead = u2 as GroundShip
			break
	if lead == null:
		return
	var fwd: Vector3 = forward_of(lead.rotation.y)
	var perp: Vector3 = Vector3(-fwd.z, 0.0, fwd.x)
	var pos: Variant = _find_water_spot(center, perp, fwd, 2600.0 if sc["types"][0] != "destroyer" else 3000.0)
	if pos == null:
		_log("no open water for an attack off %s" % cv.display_name)
		return
	var att: Array = _make_attackers(sc["types"], str(sc["att_team"]), pos as Vector3, center)
	if att.is_empty():
		return
	var defs: Array = []
	for u3 in cv.units:
		if is_instance_valid(u3) and not (u3 as GroundShip).is_dead:
			defs.append(u3)
	start_engagement(att, defs, str(sc["label"]), true, _convoy_name(lead))


## Open water about `dist` off `center` to either side (and a little ahead or astern), with a clear sea lane in between.
func _find_water_spot(center: Vector3, perp: Vector3, fwd: Vector3, dist: float) -> Variant:
	var sgn0: float = 1.0 if _rng.randf() < 0.5 else -1.0
	for scale_k in [1.0, 0.8, 1.3, 0.6]:
		for sgn in [sgn0, -sgn0]:
			var p: Vector3 = center + perp * sgn * dist * scale_k + fwd * _rng.randf_range(-500.0, 300.0)
			p.y = 0.0
			var ok: bool = true
			for k in 7:
				var q: Vector3 = center.lerp(p, float(k) / 6.0)
				if not is_water_at(q.x, q.z):
					ok = false
					break
			if ok:
				return p
	return null


func _make_attackers(types: Array, team: String, at: Vector3, toward: Vector3) -> Array:
	var out: Array = []
	var dirv: Vector3 = (toward - at)
	dirv.y = 0.0
	dirv = dirv.normalized()
	var perp: Vector3 = Vector3(-dirv.z, 0.0, dirv.x)
	for i in types.size():
		var t: String = str(types[i])
		var sh: GroundShip = GroundShip.create(t, team, null, 0.0, float(GroundShip.TYPES[t]["speed"]))
		sh.display_name = {"eboat": "S-boot", "mtb": "MTB", "destroyer": "Destroyer"}.get(t, t.capitalize())
		sh.set_meta("skirmish_spawn", true)
		sh.set_meta("gm_event", self)       # ground target markers (ground_marks.gd)
		var off: float = (float(i) - float(types.size() - 1) * 0.5) * 110.0
		sh.position = at + perp * off - dirv * absf(off) * 0.3
		sh.rotation.y = yaw_of(dirv)
		add_child(sh)
		out.append(sh)
	return out


## --naval-test: a convoy crossing in front of the player and an attack on it, whatever is (not) on the map there.
func _spawn_test_scene() -> void:
	var team: String = forced_team if forced_team != "" else side
	var fwd: Vector3 = -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right: Vector3 = Vector3(-fwd.z, 0.0, fwd.x) * -1.0
	var mid: Vector3 = player.global_position + fwd * 3000.0
	mid.y = 0.0
	var pts: PackedVector3Array = PackedVector3Array([mid - right * 5000.0, mid + right * 7000.0])
	var rp: RoutePath = RoutePath.from_points(pts)
	var comp: String = "channel" if team == "Allies" else "kriegsmarine"
	var cv: Convoy = Convoy.create(team, rp, true, comp, 5000.0, 7.0)
	cv.display_name = "Test convoy"
	cv.target_id = "naval_test"
	add_child(cv)
	await get_tree().process_frame
	_log("test convoy %s (%s) with %d ships" % [comp, team, cv.units.size()])
	_spawn_attack(cv)


# ------------------------------------------------------------------ engagements

## Begin an engagement: `att` ships open the action against `defs`. Armed ships on both sides get a control record and are
## driven by drive(); unarmed merchants scatter (faster, weaving) along their route. The radio call is made once, here.
func start_engagement(att: Array, defs: Array, label: String, spawned: bool, p_name: String = "Convoy") -> Dictionary:
	var e: Dictionary = {"id": _next_id, "att": att.duplicate(), "def": defs.duplicate(), "label": label, "spawned": spawned,
		"age": 0.0, "calls": 0, "name": p_name, "done": false, "outcome": "", "assist": false, "merch": {}, "check": 0.0,
		"star": _rng.randf_range(4.0, 12.0), "att_n": att.size(), "def_n": defs.size(), "marked": [], "gone_t": 0.0}
	_next_id += 1
	var center: Vector3 = _center(defs)
	e["center"] = center
	for sh in att:
		_take(sh as GroundShip, e, "att", center)
	for sh2 in defs:
		var d: GroundShip = sh2 as GroundShip
		if is_armed(d.stype) and _min_dist(d, att) < 3600.0:
			_take(d, e, "def", center)
		elif not is_armed(d.stype):
			# merchants scatter: a burst of speed and a weaving course
			e["merch"][d.get_instance_id()] = [d.speed, d.wander, d.wander_phase]
			d.speed = minf(d.speed * 1.35, float(GroundShip.TYPES.get(d.stype, {"speed": 9.0})["speed"]) * 1.2)
			d.wander = 55.0
	engagements.append(e)
	started += 1
	cooldown = cooldown_every if cooldown_every >= 0.0 else _rng.randf_range(COOLDOWN.x, COOLDOWN.y) * Tempo.event_scale()
	_log("engagement %d: %s (%d) vs %d ships near %s" % [int(e["id"]), label, att.size(), defs.size(), place_name(center)])
	_announce(e)
	return e


func _center(ships: Array) -> Vector3:
	var c: Vector3 = Vector3.ZERO
	var n: int = 0
	for s in ships:
		if is_instance_valid(s):
			c += (s as Node3D).global_position
			n += 1
	return c / float(maxi(n, 1))


func _min_dist(sh: Node3D, others: Array) -> float:
	var m: float = 1.0e9
	for o in others:
		if is_instance_valid(o):
			m = minf(m, sh.global_position.distance_to((o as Node3D).global_position))
	return m


func _take(sh: GroundShip, e: Dictionary, role: String, center: Vector3) -> void:
	var cfg: Dictionary = GroundShip.TYPES.get(sh.stype, GroundShip.TYPES["trawler"])
	var fast: bool = sh.stype == "eboat" or sh.stype == "mtb"
	var c: Dictionary = {"eid": int(e["id"]), "role": role, "mode": "approach", "tgt": null, "v": maxf(sh.speed, 4.0), "vwant": float(cfg["speed"]),
		"vmax": float(cfg["speed"]), "hwant": sh.rotation.y, "turn": float(TURN.get(sh.stype, 0.3)), "t": 0.0, "gun_cd": _rng.randf_range(0.5, 2.5),
		"salvo": {}, "torps": 2 if sh.stype == "eboat" else (2 if sh.stype == "mtb" else 0), "passes": 0, "spd0": maxf(sh.speed, 0.1),
		"fast": fast, "home": sh.global_position, "side": 1.0 if _rng.randf() < 0.5 else -1.0, "avoid_t": 0.0, "avoid_sign": 1.0,
		"land_t": 0.0, "roll": 0.0, "burn": false, "burn_t": 0.0, "spray_t": 0.0, "bob": 0.0, "gone": false, "dead_t": 0.0}
	if role == "def" and sh.route != null:
		c["mode"] = "intercept"
	_ctl[sh.get_instance_id()] = c
	sh.skirmish = self


func _release(sh: GroundShip) -> void:
	if is_instance_valid(sh):
		sh.skirmish = null
	_ctl.erase(sh.get_instance_id())


func _announce(e: Dictionary) -> void:
	if int(e["calls"]) > 0:
		return
	e["calls"] = 1
	var att: Array = e["att"]
	var defs: Array = e["def"]
	if att.is_empty() or defs.is_empty():
		return
	var attackers_friendly: bool = (att[0] as GroundShip).team == side
	var spot: Vector3 = _center(defs)
	var ppos: Vector3 = player.global_position if (player != null and is_instance_valid(player)) else spot
	var place: String = place_name(spot)
	var miles: int = int(round(Vector2(spot.x - ppos.x, spot.z - ppos.z).length() / 1609.0))
	var bearing: int = bearing_deg(ppos, spot)
	var label: String = str(e["label"])
	var text: String
	var sender: String
	if attackers_friendly:
		sender = "MTB 102" if (att[0] as GroundShip).stype == "mtb" else ("S-boot 24" if (att[0] as GroundShip).stype == "eboat" else "Destroyer Control")
		text = call_text(false, sender, "", place, bearing, miles, side)
	else:
		sender = ("Convoy " + str(e["name"])) if side == "Allies" else str(e["name"])
		text = call_text(true, str(e["name"]), label, place, bearing, miles, side)
	e["call_text"] = text
	if radio_enabled and Radio != null:
		request_air_support(hud, sender, text, spot, ppos, "support_naval_attack" if attackers_friendly else "support_naval")
	_log("RADIO %s: %s" % [sender, text])
	# minimap markers: the attackers (enemy red) or, when our own boats attack, the convoy's escorts
	if hud != null and is_instance_valid(hud) and hud.has_method("register_minimap_marker"):
		for sh in att:
			var mk_col: Color = Color(0.3, 0.75, 1.0) if attackers_friendly else Color(1.0, 0.25, 0.2)
			AIFactory.add_marker(hud, sh as Node3D, mk_col)
			(e["marked"] as Array).append(sh)
		if not attackers_friendly:
			var lead: Node3D = defs[0] as Node3D
			AIFactory.add_marker(hud, lead, Color(0.3, 0.75, 1.0))
			(e["marked"] as Array).append(lead)
	_support_mark(e, spot)


## The same "support requested" ring as the land battles, at the fight; removed when the engagement is over.
func _support_mark(e: Dictionary, spot: Vector3) -> void:
	if hud == null or not is_instance_valid(hud) or not hud.has_method("register_support_marker"):
		return
	var a := Node3D.new()
	a.name = "SupportMark%d" % int(e["id"])
	add_child(a)
	if a.is_inside_tree():
		a.global_position = spot
	else:
		a.position = spot
	hud.call("register_support_marker", a)
	e["support"] = a


func _unsupport(e: Dictionary) -> void:
	var a: Variant = e.get("support")
	if a is Node3D and is_instance_valid(a):
		if hud != null and is_instance_valid(hud) and hud.has_method("unregister_support_marker"):
			hud.call("unregister_support_marker", a)
		(a as Node3D).queue_free()
	e.erase("support")


func _unmark(n: Node) -> void:
	if hud == null or not is_instance_valid(hud):
		return
	var arr: Variant = hud.get("_markers")
	if arr is Array:
		for i in range((arr as Array).size() - 1, -1, -1):
			if (arr as Array)[i][0] == n:
				(arr as Array).remove_at(i)


func _on_player_hit(node: Node, _amount: float) -> void:
	for e in engagements:
		if (e["att"] as Array).has(node) or (e["def"] as Array).has(node):
			e["assist"] = true


# ------------------------------------------------------------------ per-ship movement (called from GroundShip._process)

func drive(sh: GroundShip, delta: float) -> void:
	var c: Variant = _ctl.get(sh.get_instance_id())
	if c == null:
		sh.skirmish = null
		return
	var cc: Dictionary = c
	# speed: hull type limit, slowed by damage (health) and by torpedo flooding (GroundShip halves .speed)
	var hf: float = clampf(sh.health / maxf(sh.max_health, 1.0), 0.0, 1.0)
	var flood: float = clampf(sh.speed / float(cc["spd0"]), 0.0, 1.0) if sh._torp_hit else 1.0
	var vmax: float = float(cc["vmax"]) * (0.45 + 0.55 * hf) * flood
	cc["v"] = move_toward(float(cc["v"]), minf(float(cc["vwant"]), vmax), 4.5 * delta)
	var v: float = float(cc["v"])
	# turn
	var cur: float = sh.rotation.y
	var diff: float = wrapf(float(cc["hwant"]) - cur, -PI, PI)
	var rate: float = float(cc["turn"]) * (0.4 + 0.6 * clampf(v / maxf(vmax, 1.0), 0.0, 1.0))
	var yaw: float = cur + clampf(diff, -rate * delta, rate * delta)
	sh.rotation.y = yaw
	sh._yaw = yaw
	var fwd: Vector3 = forward_of(yaw)
	var pos: Vector3 = sh.global_position + fwd * v * delta
	# land ahead: swing away
	cc["land_t"] = float(cc["land_t"]) - delta
	cc["avoid_t"] = maxf(float(cc["avoid_t"]) - delta, 0.0)
	if float(cc["land_t"]) <= 0.0:
		cc["land_t"] = 0.5
		var ah: Vector3 = pos + fwd * (v * 7.0 + 90.0)
		if not is_water_at(ah.x, ah.z):
			cc["avoid_t"] = 3.5
			cc["avoid_sign"] = 1.0 if is_water_at(pos.x - fwd.z * 200.0, pos.z + fwd.x * 200.0) else -1.0
		if float(cc["avoid_t"]) > 0.0:
			cc["hwant"] = yaw + 1.6 * float(cc["avoid_sign"])
	# a ship still tied to a route keeps its station moving (so it can rejoin the convoy)
	if sh.route != null and sh.route.length > 1.0:
		sh.s += float(cc["spd0"]) * sh.dir * delta
		sh.s = fposmod(sh.s, sh.route.length) if sh.wrap else clampf(sh.s, 0.0, sh.route.length)
	cc["bob"] = float(cc["bob"]) + delta
	var bob: float = sh._bob_t
	sh.global_position = Vector3(pos.x, 0.1 + sin(bob * 1.4) * 0.12, pos.z)
	var k: float = clampf(v / maxf(float(cc["vmax"]), 1.0), 0.0, 1.0)
	cc["roll"] = lerpf(float(cc["roll"]), clampf(-diff * 0.45, -0.2, 0.2) * k, clampf(delta * 2.0, 0.0, 1.0))
	sh._list_cur = move_toward(sh._list_cur, sh._list_target * sh._list_sign, delta * 0.04)
	sh.rotation.z = sin(bob * 0.9) * 0.012 + sh._list_cur + float(cc["roll"])
	sh.rotation.x = -0.06 * k if bool(cc["fast"]) else 0.0
	# bow spray and a rooster-tail of white water behind a fast boat (near the camera only)
	if bool(cc["fast"]) and k > 0.5:
		cc["spray_t"] = float(cc["spray_t"]) - delta
		if float(cc["spray_t"]) <= 0.0 and _near(pos, 3500.0):
			cc["spray_t"] = 0.11
			var back: Vector3 = pos - fwd * 14.0
			FX.puffs.spawn(Vector3(back.x, 0.6, back.z), -fwd * 3.0 + Vector3(randf_range(-1.5, 1.5), 3.5, randf_range(-1.5, 1.5)), 1.3, 1.2, 3.6,
				Color(0.95, 0.98, 1.0, 0.6), Color(0.85, 0.92, 0.96, 0.0), 0.4, 3.0, 0.6)


# ------------------------------------------------------------------ the fight

func _alive(list: Array) -> Array:
	var out: Array = []
	for s in list:
		if is_instance_valid(s) and not (s as GroundShip).is_dead and not bool(_ctl.get((s as GroundShip).get_instance_id(), {}).get("gone", false)):
			out.append(s)
	return out


func _velocity(sh: GroundShip) -> Vector3:
	var c: Variant = _ctl.get(sh.get_instance_id())
	if c != null:
		return forward_of(sh.rotation.y) * float((c as Dictionary)["v"])
	if sh.route != null and sh.speed > 0.0:
		return forward_of(sh.rotation.y) * sh.speed
	return Vector3.ZERO


func _nearest(sh: GroundShip, list: Array, prefer_soft: bool = false) -> GroundShip:
	var best: GroundShip = null
	var bd: float = 1.0e9
	for o in list:
		var t: GroundShip = o as GroundShip
		var d: float = sh.global_position.distance_to(t.global_position)
		if prefer_soft and not is_armed(t.stype):
			d *= 0.6
		if d < bd:
			bd = d
			best = t
	return best


func _step_engagement(e: Dictionary, dt: float) -> void:
	e["age"] = float(e["age"]) + dt
	var att: Array = _alive(e["att"])
	var defs: Array = _alive(e["def"])
	var ppos: Vector3 = player.global_position if (player != null and is_instance_valid(player)) else Vector3.ZERO
	if player != null and is_instance_valid(player):
		var cdist: float = Vector2(ppos.x - float((e["center"] as Vector3).x), ppos.z - float((e["center"] as Vector3).z)).length()
		if cdist > CULL_DIST:
			_finish(e, "culled")
			return
	var age: float = float(e["age"])
	# the sides' ships think and shoot
	for sh in att:
		_think(sh as GroundShip, e, att, defs, dt)
	for sh2 in defs:
		if _ctl.has((sh2 as GroundShip).get_instance_id()):
			_think(sh2 as GroundShip, e, defs, att, dt)
	if self_drive:
		for sh3 in att + defs:
			if _ctl.has((sh3 as GroundShip).get_instance_id()):
				drive(sh3 as GroundShip, dt)
	# dead ships leave the picture
	for lst in [e["att"], e["def"]]:
		for s in lst:
			if is_instance_valid(s) and (s as GroundShip).is_dead and _ctl.has((s as GroundShip).get_instance_id()):
				_release(s as GroundShip)
	# attackers that have run off the scene are removed
	for sh4 in att:
		var c4: Dictionary = _ctl.get((sh4 as GroundShip).get_instance_id(), {})
		if not c4.is_empty() and str(c4["mode"]) == "flee":
			var gd: float = (sh4 as GroundShip).global_position.distance_to(e["center"] as Vector3)
			var far_player: bool = player != null and is_instance_valid(player) and (sh4 as GroundShip).global_position.distance_to(ppos) > 9000.0
			if gd > 4800.0 or far_player or float(c4["t"]) > 60.0:
				c4["gone"] = true
				_remove_ship(sh4 as GroundShip)
	# night: starshells over the convoy
	e["star"] = float(e["star"]) - dt
	if float(e["star"]) <= 0.0:
		e["star"] = _rng.randf_range(16.0, 28.0)
		if _night() and _near(e["center"] as Vector3):
			_starshell((e["center"] as Vector3) + Vector3(_rng.randf_range(-250.0, 250.0), 0.0, _rng.randf_range(-250.0, 250.0)))
	# end of the engagement
	e["check"] = float(e["check"]) + dt
	if float(e["check"]) >= 0.5:
		e["check"] = 0.0
		e["center"] = _center(defs) if not defs.is_empty() else e["center"]
		var armed_def: int = 0
		for d in defs:
			if is_armed((d as GroundShip).stype):
				armed_def += 1
		if att.is_empty():
			_finish(e, "repelled")
		elif defs.is_empty():
			_finish(e, "destroyed")
		elif age > MAX_ENGAGE_AGE:
			# time: the attackers break off
			for sh5 in att:
				var c5: Dictionary = _ctl.get((sh5 as GroundShip).get_instance_id(), {})
				if not c5.is_empty() and str(c5["mode"]) != "flee":
					c5["mode"] = "flee"
					c5["t"] = 0.0
			if _all_fled(att):
				_finish(e, "broke_off")
		elif att.size() * 2 <= int(e["att_n"]) and age > 60.0 and _rng.randf() < 0.5:
			for sh6 in att:
				var c6: Dictionary = _ctl.get((sh6 as GroundShip).get_instance_id(), {})
				if not c6.is_empty() and str(c6["mode"]) != "flee":
					c6["mode"] = "flee"
					c6["t"] = 0.0


func _step_after(dt: float) -> void:
	var i: int = _after.size() - 1
	while i >= 0:
		var sh: GroundShip = _after[i] as GroundShip if is_instance_valid(_after[i]) else null
		if sh == null:
			_after.remove_at(i)
			i -= 1
			continue
		var c: Dictionary = _ctl.get(sh.get_instance_id(), {})
		if c.is_empty() or sh.is_dead:
			_release(sh)
			_after.remove_at(i)
			i -= 1
			continue
		var ctr: Vector3 = c.get("center", sh.global_position)
		_think(sh, {"center": ctr, "age": 999.0}, [], [], dt)
		if self_drive and _ctl.has(sh.get_instance_id()):
			drive(sh, dt)
		if str(c["mode"]) == "flee":
			var far_p: bool = player != null and is_instance_valid(player) and sh.global_position.distance_to(player.global_position) > 9000.0
			if sh.global_position.distance_to(ctr) > 4800.0 or far_p or float(c["t"]) > 70.0:
				_after.remove_at(i)
				_remove_ship(sh)
		elif not _ctl.has(sh.get_instance_id()):
			_after.remove_at(i)
		i -= 1


func _all_fled(att: Array) -> bool:
	for s in att:
		var c: Dictionary = _ctl.get((s as GroundShip).get_instance_id(), {})
		if not c.is_empty() and not bool(c["gone"]):
			return false
	return true


func _remove_ship(sh: GroundShip) -> void:
	_release(sh)
	_unmark(sh)
	if is_instance_valid(sh) and sh.has_meta("skirmish_spawn"):
		sh.queue_free()


func _finish(e: Dictionary, outcome: String) -> void:
	if bool(e["done"]):
		return
	e["done"] = true
	e["outcome"] = outcome
	_unsupport(e)
	for lst in [e["att"], e["def"]]:
		for s in lst:
			if not is_instance_valid(s):
				continue
			var sh: GroundShip = s as GroundShip
			if sh.has_meta("skirmish_spawn") and outcome in ["culled", "broke_off", "repelled"] and not sh.is_dead:
				_remove_ship(sh)
				continue
			var cf: Dictionary = _ctl.get(sh.get_instance_id(), {})
			if not sh.is_dead and not cf.is_empty() and outcome != "culled":
				# ships still afloat keep being driven: back to station along the route, or (spawned boats) away
				if sh.route != null and sh.route.length > 1.0:
					cf["mode"] = "rejoin"
				elif sh.has_meta("skirmish_spawn"):
					cf["mode"] = "flee"
					cf["t"] = 0.0
				else:
					cf["mode"] = ""
				if str(cf["mode"]) != "":
					cf["tgt"] = null
					cf["center"] = e["center"]
					_after.append(sh)
					_unmark(sh)
					continue
			_release(sh)
			_unmark(sh)
	# merchants go back to station-keeping
	for id in (e["merch"] as Dictionary):
		var m: Object = instance_from_id(int(id))
		if m != null and is_instance_valid(m):
			var arr: Array = e["merch"][id]
			(m as GroundShip).speed = float(arr[0])
			(m as GroundShip).wander = float(arr[1])
	# dead spawned boats are cleared away after a while
	for s2 in e["att"]:
		if is_instance_valid(s2) and (s2 as GroundShip).has_meta("skirmish_spawn") and (s2 as GroundShip).is_dead:
			(s2 as GroundShip).get_tree().create_timer(60.0).timeout.connect((s2 as GroundShip).queue_free)
	_log("engagement %d over: %s after %.0f s (%d of %d attackers left, %d of %d convoy ships)" % [int(e["id"]), outcome, float(e["age"]),
		_alive(e["att"]).size(), int(e["att_n"]), _alive(e["def"]).size(), int(e["def_n"])])
	if outcome == "culled":
		return
	if radio_enabled and Radio != null and player != null and is_instance_valid(player) and not (e["att"] as Array).is_empty():
		var attackers_friendly: bool = is_instance_valid((e["att"] as Array)[0]) and ((e["att"] as Array)[0] as GroundShip).team == side
		var line: String = ""
		var vcat: String = ""       # a generic recorded call of the same meaning (assets/voice, scripts/radio_chatter.gd)
		if outcome == "repelled" or outcome == "broke_off":
			if attackers_friendly:
				line = "Breaking off the attack. Thank you, aircraft." if bool(e["assist"]) else "We are breaking off the attack."
			else:
				line = ("%s: attackers driven off. Thank you for the help, aircraft!" % str(e["name"])) if bool(e["assist"]) else ("%s: the attackers have broken off." % str(e["name"]))
			if bool(e["assist"]):
				vcat = "support_naval_end"
		elif outcome == "destroyed" and not attackers_friendly:
			line = "%s is lost." % str(e["name"])
			vcat = "support_naval_lost"
		if line != "":
			Radio.say(("MTB 102" if attackers_friendly else str(e["name"])), line, Radio.Kind.FRIENDLY, 1.0, Radio.chatter_clip(vcat) if vcat != "" else "")


## One ship's decisions: pick a target, steer, shoot, burn.
func _think(sh: GroundShip, e: Dictionary, own: Array, foes: Array, dt: float) -> void:
	var c: Dictionary = _ctl.get(sh.get_instance_id(), {})
	if c.is_empty():
		return
	c["t"] = float(c["t"]) + dt
	var mode: String = str(c["mode"])
	var role: String = str(c["role"])
	var hp: float = sh.health / maxf(sh.max_health, 1.0)
	var pos: Vector3 = sh.global_position
	# damaged beyond a point: attackers run for home under smoke
	if role == "att" and mode != "flee" and hp < 0.35:
		c["mode"] = "flee"
		c["t"] = 0.0
		mode = "flee"
	var tgt: GroundShip = c["tgt"] as GroundShip if (c["tgt"] != null and is_instance_valid(c["tgt"])) else null
	if tgt != null and tgt.is_dead:
		tgt = null
	if tgt == null and mode != "flee" and mode != "rejoin":
		tgt = _nearest(sh, foes, bool(c["fast"]) and int(c["torps"]) > 0)
		c["tgt"] = tgt
	if tgt == null and role == "def" and mode != "rejoin":
		c["mode"] = "rejoin"
		mode = "rejoin"
	var to_t: Vector3 = Vector3.ZERO
	var dist: float = 0.0
	if tgt != null:
		to_t = tgt.global_position - pos
		to_t.y = 0.0
		dist = to_t.length()
	var vmax: float = float(c["vmax"])
	var avoiding: bool = float(c["avoid_t"]) > 0.0
	match mode:
		"approach":
			if tgt != null:
				if bool(c["fast"]):
					# attack run at full speed, aimed at where the target will be
					var lead: Vector3 = tgt.global_position + _velocity(tgt) * (dist / maxf(vmax, 1.0)) * 0.8
					if not avoiding:
						c["hwant"] = yaw_of(lead - pos)
					c["vwant"] = vmax
					var aligned: bool = absf(wrapf(yaw_of(lead - pos) - sh.rotation.y, -PI, PI)) < 0.3
					var soft: bool = not is_armed(tgt.stype)
					if int(c["torps"]) > 0 and aligned and dist > 200.0 and ((soft and dist < 1000.0) or (dist < 800.0 and float(c["t"]) > 3.0)):
						_launch_torpedo(sh, lead)
						c["torps"] = int(c["torps"]) - 1
					if dist < 230.0 or float(c["t"]) > 45.0:
						c["mode"] = "break"
						c["t"] = 0.0
						c["passes"] = int(c["passes"]) + 1
						c["side"] = 1.0 if _rng.randf() < 0.5 else -1.0
				elif role == "def" and dist > 3500.0:
					c["mode"] = "rejoin"          # the attackers have run off: back to the convoy
					c["tgt"] = null
				else:
					# big ship: close to a standoff range, then turn broadside to bring every gun to bear
					var stand: float = 1900.0 if role == "att" else (1350.0 if sh.stype == "destroyer" else 900.0)
					var line_dir: Vector3 = to_t.normalized()
					var perp: Vector3 = Vector3(-line_dir.z, 0.0, line_dir.x) * float(c["side"])
					var want_dir: Vector3 = line_dir
					if dist < stand * 1.25:
						want_dir = (perp * 0.9 + line_dir * clampf((dist - stand) / stand, -0.7, 0.4)).normalized()
					if not avoiding:
						c["hwant"] = yaw_of(want_dir)
					c["vwant"] = vmax * (0.7 if dist < stand * 1.25 else 1.0)
					if role == "att" and (float(e["age"]) > 105.0):
						c["mode"] = "flee"
						c["t"] = 0.0
		"intercept":
			# an escort goes for the nearest attacker, turning broadside at its standoff range
			c["mode"] = "approach"
		"break":
			# turn away across the convoy's bows laying smoke, come round again after a pause
			if tgt != null and not avoiding:
				c["hwant"] = yaw_of(-to_t) + 1.1 * float(c["side"])
			c["vwant"] = vmax
			_smoke_trail(sh, 0.7)
			if float(c["t"]) > 15.0:
				c["tgt"] = null
				if int(c["passes"]) >= 3 or hp < 0.55:
					c["mode"] = "flee"
				else:
					c["mode"] = "approach"
				c["t"] = 0.0
		"flee":
			var away: Vector3 = pos - (e["center"] as Vector3)
			away.y = 0.0
			if away.length() < 1.0:
				away = -forward_of(sh.rotation.y)
			var home_dir: Vector3 = ((c["home"] as Vector3) - pos)
			home_dir.y = 0.0
			if not avoiding:
				c["hwant"] = yaw_of(away.normalized() * 0.7 + home_dir.normalized() * 0.5)
			c["vwant"] = vmax
			_smoke_trail(sh, 0.9 if bool(c["fast"]) else 0.5)
		"rejoin":
			if sh.route != null and sh.route.length > 1.0:
				var rp: Vector3 = sh.route.sample(sh.s)
				var tf: Vector3 = sh.route.tangent(sh.s)
				var sd: Vector3 = Vector3(-tf.z, 0.0, tf.x).normalized()
				var station: Vector3 = rp + sd * sh.lateral
				var gap: Vector3 = station - pos
				gap.y = 0.0
				if gap.length() < 45.0:
					sh._lat_k = 1.0
					_release(sh)
					return
				if not avoiding:
					c["hwant"] = yaw_of(gap)
				c["vwant"] = vmax
			else:
				_release(sh)
				return
	# guns
	_tick_guns(sh, c, tgt, dt)
	# fire aboard
	if hp < 0.5 and not bool(c["burn"]):
		c["burn"] = true
	if bool(c["burn"]):
		_burn(sh, c, dt)


func _tick_guns(sh: GroundShip, c: Dictionary, tgt: GroundShip, dt: float) -> void:
	c["gun_cd"] = float(c["gun_cd"]) - dt
	if tgt == null or not GUNS.has(sh.stype) or float(c["gun_cd"]) > 0.0:
		return
	var g: Dictionary = GUNS[sh.stype]
	var d: Vector3 = tgt.global_position - sh.global_position
	d.y = 0.0
	var dist: float = d.length()
	if dist > float(g["range"]) or dist < 60.0:
		return
	# damaged ships shoot slower
	c["gun_cd"] = float(g["cd"]) * _rng.randf_range(0.85, 1.2) * (1.0 + (1.0 - sh.health / maxf(sh.max_health, 1.0)))
	_fire(sh, c, tgt, dist)


## A salvo: dispersion from spread(), the first two salvos straddle short and over, then it closes in.
func _fire(sh: GroundShip, c: Dictionary, tgt: GroundShip, dist: float) -> void:
	var g: Dictionary = GUNS[sh.stype]
	var tid: int = tgt.get_instance_id()
	var k: int = int((c["salvo"] as Dictionary).get(tid, 0))
	(c["salvo"] as Dictionary)[tid] = k + 1
	var sig: float = spread(sh.stype, dist, k) * (1.0 + _velocity(tgt).length() / 18.0)     # a fast boat is hard to hit
	var flight: float = dist / float(g["spd"])
	var aim: Vector3 = tgt.global_position + _velocity(tgt) * flight
	aim.y = 0.0
	var dirv: Vector3 = (aim - sh.global_position)
	dirv.y = 0.0
	dirv = dirv.normalized()
	var perp: Vector3 = Vector3(-dirv.z, 0.0, dirv.x)
	var n: int = int(g["n"])
	var muzzle: Vector3 = sh.global_position + dirv * float(sh._len) * 0.25 * sh.scale.x + Vector3(0.0, 4.0 * sh.scale.x, 0.0)
	var show: bool = _near(sh.global_position)
	for i in n:
		var along: float
		if k == 0:
			along = -1.7 * sig            # first salvo falls short
		elif k == 1:
			along = 1.3 * sig             # second goes over: the target is bracketed
		else:
			along = _rng.randfn(0.0, 0.5 * sig)
		var lat: float = _rng.randfn(0.0, 0.5 * sig)
		var to: Vector3 = aim + dirv * (along + _rng.randfn(0.0, 0.25 * sig)) + perp * lat
		to.y = 0.0
		_shells.append({"from": muzzle + perp * _rng.randf_range(-1.5, 1.5), "to": to, "t": -float(i) * (0.10 if n > 3 else 0.2), "dur": maxf(flight, 0.4),
			"dmg": float(g["dmg"]), "plume": float(g["plume"]), "src": sh, "team": sh.team, "big": sh.stype == "destroyer" or sh.stype == "cruiser",
			"vis": show, "tr": -1})
	if show:
		var bl: float = float(g["blast"])
		FX.puffs.spawn(muzzle + dirv * 3.0, dirv * 4.0 + Vector3(0, 1.5, 0), 2.6, 1.4 * bl + 0.5, 4.5 * bl + 1.0,
			Color(0.8, 0.76, 0.7, 0.6), Color(0.6, 0.6, 0.6, 0.0), 0.6, 0.0, 0.7)
		FX.puffs.spawn(muzzle + dirv * 2.0, dirv * 1.0, 0.18, 1.0 * bl + 0.4, 2.6 * bl + 0.6, Color(1.0, 0.85, 0.45, 0.95), Color(1.0, 0.5, 0.1, 0.0), 0.0, 0.0, 0.0)
		FX.light_flash(muzzle, 2.2 * bl + 0.6, 70.0, 0.12, Color(1.0, 0.72, 0.38))
		FX.sfx("explosion", muzzle, linear_to_db(clampf(0.12 + 0.18 * bl, 0.05, 0.4)), 0.25)


# ------------------------------------------------------------------ shells, torpedoes, effects

func _tracer_mesh() -> MeshInstance3D:
	if _tracers.is_empty():
		_tr_mat = StandardMaterial3D.new()
		_tr_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tr_mat.albedo_color = Color(1.0, 0.72, 0.28)
		_tr_mat.emission_enabled = true
		_tr_mat.emission = Color(1.0, 0.6, 0.2)
		_tr_mat.emission_energy_multiplier = 2.5
		for i in 40:
			var m := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.7, 0.7, 12.0)
			m.mesh = bm
			m.material_override = _tr_mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m.visible = false
			add_child(m)
			_tracers.append(m)
	_tr_next = (_tr_next + 1) % _tracers.size()
	return _tracers[_tr_next] as MeshInstance3D


func _step_shells(dt: float) -> void:
	var i: int = _shells.size() - 1
	while i >= 0:
		var s: Dictionary = _shells[i]
		s["t"] = float(s["t"]) + dt
		var t: float = float(s["t"])
		var tr: int = int(s["tr"])
		if t >= 0.0 and bool(s["vis"]) and tr == -1 and is_inside_tree():
			var mi: MeshInstance3D = _tracer_mesh()
			mi.visible = true
			s["tr"] = _tracers.find(mi)
			tr = int(s["tr"])
		if t >= float(s["dur"]):
			if tr >= 0:
				(_tracers[tr] as MeshInstance3D).visible = false
			_impact(s)
			_shells.remove_at(i)
		elif t >= 0.0 and tr >= 0:
			var u: float = t / float(s["dur"])
			var a: Vector3 = s["from"]
			var b: Vector3 = s["to"]
			var arc: float = minf(a.distance_to(b) * 0.12, 90.0) if bool(s["big"]) else minf(a.distance_to(b) * 0.03, 14.0)
			var p: Vector3 = a.lerp(b, u) + Vector3(0.0, 4.0 * arc * u * (1.0 - u), 0.0)
			var p2: Vector3 = a.lerp(b, minf(u + 0.03, 1.0)) + Vector3(0.0, 4.0 * arc * minf(u + 0.03, 1.0) * (1.0 - minf(u + 0.03, 1.0)), 0.0)
			var mi2: MeshInstance3D = _tracers[tr]
			if p.distance_to(p2) > 0.01:
				mi2.look_at_from_position(p, p2, Vector3.UP)
		i -= 1


func _enemy_ships(team: String) -> Array:
	var out: Array = []
	for e in engagements:
		for lst in [e["att"], e["def"]]:
			for s in lst:
				if is_instance_valid(s) and (s as GroundShip).team != team and not (s as GroundShip).is_dead and not out.has(s):
					out.append(s)
	return out


func _impact(s: Dictionary) -> void:
	var p: Vector3 = s["to"]
	var near: bool = _near(p)
	var src: Node = s["src"] if is_instance_valid(s["src"]) else null
	var hit: GroundShip = null
	for o in _enemy_ships(str(s["team"])):
		var sh: GroundShip = o
		if Vector2(p.x - sh.global_position.x, p.z - sh.global_position.z).length() < sh.hit_radius * 0.95:
			hit = sh
			break
	if hit != null:
		var dmg: float = float(s["dmg"])
		var hp0: float = hit.health
		hit.take_damage(dmg, src)
		var wp: Vector3 = hit.global_position + Vector3(randf_range(-0.3, 0.3) * hit._beam, 3.5 * hit.scale.x, randf_range(-0.4, 0.4) * hit._len) * hit.scale.x
		if not hit.is_dead and not hit._torp_hit:
			hit._list_sign = -1.0 if hit.to_local(p).x >= 0.0 else 1.0
			hit._list_target = deg_to_rad(clampf(2.0 + (1.0 - hit.health / maxf(hit.max_health, 1.0)) * 10.0, 2.0, 12.0))
		if near:
			var big: bool = bool(s["big"])
			FX.explosion(wp, 4.5 if big else 1.8, big)
			FX.light_flash(wp, 3.0 if big else 1.4, 80.0, 0.2, Color(1.0, 0.7, 0.35))
			FX.sfx("hit_metal:1", wp, -4.0 if big else -9.0, 0.08)
			FX.puffs.spawn(wp, Vector3(0, 5.0, 0), 4.0, 2.0, 9.0 if big else 5.0, Color(0.12, 0.12, 0.12, 0.8), Color(0.2, 0.2, 0.2, 0.0), 0.6, 0.0, 0.3)
		_log("hit: %s -> %s (%.0f -> %.0f hp)" % [(src as Node).name if src != null else "?", hit.stype, hp0, hit.health])
		return
	var pl: float = float(s["plume"])
	if not is_water_at(p.x, p.z):
		# shells that land ashore (a beach, a cliff, a harbour): a burst, and scars if the ruins system is there
		if near:
			FX.explosion(Vector3(p.x, maxf(GroundKit.raw_y(p.x, p.z), 0.0) + 1.0, p.z), pl * 0.7, false)
		var bd: Node = get_node_or_null("/root/BattleDamage")
		if bd != null and bd.has_method("crater") and pl >= 5.0:
			bd.call("crater", p, pl * 0.9)
			if bd.has_method("ruin_area") and _rng.randf() < 0.25:
				bd.call("ruin_area", p, 25.0, 0.5)
		return
	if near:
		var wpos: Vector3 = Vector3(p.x, 0.0, p.z)
		if pl >= 3.0:
			FX.water_plume(wpos, pl)
		else:
			FX.water_splash(wpos, pl)


func _launch_torpedo(sh: GroundShip, aim: Vector3) -> void:
	var d: Vector3 = aim - sh.global_position
	d.y = 0.0
	d = d.normalized()
	var p: Vector3 = sh.global_position + d * 22.0
	p.y = 0.0
	_torps.append({"pos": p, "dir": d, "run": 0.0, "src": sh, "team": sh.team, "fx": 0.0})
	_log("%s launches a torpedo" % sh.stype)
	if _near(p):
		FX.water_splash(p, 2.5)
		FX.puffs.spawn(p + Vector3(0, 1.5, 0), d * 6.0, 2.0, 1.5, 5.0, Color(0.9, 0.92, 0.95, 0.5), Color(0.8, 0.85, 0.9, 0.0), 0.6, 0.0, 0.8)


func _step_torps(dt: float) -> void:
	var i: int = _torps.size() - 1
	while i >= 0:
		var t: Dictionary = _torps[i]
		var p: Vector3 = t["pos"]
		var step_d: float = TORP_SPEED * dt
		p += (t["dir"] as Vector3) * step_d
		t["pos"] = p
		t["run"] = float(t["run"]) + step_d
		var gone: bool = float(t["run"]) > TORP_RANGE or not is_water_at(p.x, p.z)
		if not gone:
			t["fx"] = float(t["fx"]) - dt
			if float(t["fx"]) <= 0.0 and _near(p):
				t["fx"] = 0.12
				FX.puffs.spawn(Vector3(p.x, 0.25, p.z), Vector3(randf_range(-0.3, 0.3), 0.5, randf_range(-0.3, 0.3)), 7.0, 0.9, 2.4,
					Color(0.95, 0.98, 1.0, 0.7), Color(0.85, 0.92, 0.96, 0.0), 0.3, 0.0, 0.4)
			for o in _enemy_ships(str(t["team"])):
				var sh: GroundShip = o
				if Vector2(p.x - sh.global_position.x, p.z - sh.global_position.z).length() < sh.hit_radius * 0.8:
					var src: Node = t["src"] if is_instance_valid(t["src"]) else null
					if float(t["run"]) >= TORP_ARM:
						if _near(p):
							FX.water_plume(Vector3(p.x, 0.0, p.z), 11.0)
							FX.explosion(Vector3(p.x, 3.0, p.z), 7.0, true)
						sh.torpedo_hit(TORP_DAMAGE, p, src)
						_log("torpedo hit %s (%.0f hp left)" % [sh.stype, sh.health])
					elif _near(p):
						FX.water_splash(Vector3(p.x, 0.0, p.z), 3.0)
					gone = true
					break
		if gone:
			_torps.remove_at(i)
		i -= 1


func _smoke_trail(sh: GroundShip, amount: float) -> void:
	var c: Dictionary = _ctl.get(sh.get_instance_id(), {})
	if c.is_empty():
		return
	c["smk_t"] = float(c.get("smk_t", 0.0)) - get_process_delta_time()
	if float(c["smk_t"]) > 0.0 or not _near(sh.global_position, 5000.0):
		return
	c["smk_t"] = 0.25
	var back: Vector3 = sh.global_position - forward_of(sh.rotation.y) * (sh._len * 0.5 * sh.scale.x)
	FX.puffs.spawn(Vector3(back.x, 3.0, back.z), Vector3(randf_range(-0.6, 0.6), 1.0, randf_range(-0.6, 0.6)), 10.0, 3.0 * amount + 2.0, 16.0 * amount + 6.0,
		Color(0.9, 0.9, 0.9, 0.6), Color(0.85, 0.85, 0.85, 0.0), 0.8, 0.0, 0.3)


func _burn(sh: GroundShip, c: Dictionary, dt: float) -> void:
	c["burn_t"] = float(c["burn_t"]) - dt
	if float(c["burn_t"]) > 0.0 or not _near(sh.global_position, 5500.0):
		return
	c["burn_t"] = 0.18
	var off: Vector3 = Vector3(0.0, 5.0 * sh.scale.x, randf_range(-0.3, 0.3) * sh._len * sh.scale.x)
	var p: Vector3 = sh.global_position + sh.global_transform.basis * Vector3(0, 0, off.z / sh.scale.x) + Vector3(0, off.y, 0)
	FX.puffs.spawn(p, Vector3(randf_range(-0.5, 0.5), 4.0, randf_range(-0.5, 0.5)), 6.0, 2.0, 11.0, Color(0.1, 0.1, 0.1, 0.8), Color(0.2, 0.2, 0.2, 0.0), 0.6, 0.0, 0.3)
	if _rng.randf() < 0.6:
		FX.puffs.spawn(p, Vector3(0, 2.5, 0), 0.7, 1.4, 3.0, Color(1.0, 0.6, 0.15, 0.9), Color(0.5, 0.1, 0.0, 0.0), 0.0, 0.0, 0.0)


func _starshell(pos: Vector3) -> void:
	var p: Vector3 = Vector3(pos.x, 260.0, pos.z)
	FX.light_flash(p, 2.4, 110.0, 8.0, Color(1.0, 0.95, 0.82))
	FX.puffs.spawn(p, Vector3(0, -6.0, 0), 8.0, 10.0, 16.0, Color(1.0, 0.96, 0.8, 0.95), Color(1.0, 0.8, 0.5, 0.0), 0.0, 0.0, 0.0)
	_log("starshell")


## The engagement a ship is in, for others to query.
func engagement_of(sh: Node) -> Dictionary:
	for e in engagements:
		if (e["att"] as Array).has(sh) or (e["def"] as Array).has(sh):
			return e
	return {}


func cleanup() -> void:
	for e in engagements.duplicate():
		_finish(e as Dictionary, "culled")
	engagements.clear()
	for a in _after.duplicate():
		if is_instance_valid(a):
			_release(a as GroundShip)
	_after.clear()
	_shells.clear()
	_torps.clear()


# ------------------------------------------------------------------ debug pictures (--naval-test --naval-shots=<dir>)

func _shot_tick(dt: float) -> void:
	if engagements.is_empty():
		return
	var e: Dictionary = engagements[0]
	var att: Array = _alive(e["att"])
	var defs: Array = _alive(e["def"])
	if att.is_empty() and defs.is_empty():
		return
	var ac: Vector3 = _center(att) if not att.is_empty() else _center(defs)
	var dc: Vector3 = _center(defs) if not defs.is_empty() else ac
	var mid: Vector3 = ac.lerp(dc, 0.5)
	var axis: Vector3 = dc - ac
	axis.y = 0.0
	if axis.length() < 1.0:
		axis = Vector3(1, 0, 0)
	var perp: Vector3 = Vector3(-axis.z, 0.0, axis.x).normalized()
	# the game's own (active) camera is flown over the action, after the player's controller has placed it
	process_priority = 1000
	# behind the attackers (or the convoy once they are gone), looking across them at the convoy
	var adir: Vector3 = axis.normalized()
	var base: Vector3 = ac if not att.is_empty() else dc
	var want: Vector3 = base - adir * 420.0 + perp * 180.0 + Vector3(0.0, 70.0, 0.0)
	var focus: Vector3 = base + adir * 380.0 + Vector3(0.0, 4.0, 0.0)
	if _shot_cam == null:
		_shot_cam = Camera3D.new()
		_shot_cam.name = "NavalShotCam"
		_shot_cam.far = 20000.0
		_shot_cam.fov = 48.0
		add_child(_shot_cam)
		_shot_cam.global_position = want
	var cp: Vector3 = _shot_cam.global_position.lerp(want, clampf(dt * 1.2, 0.0, 1.0))
	_shot_cam.global_transform = Transform3D(Basis.looking_at((focus - cp).normalized(), Vector3.UP), cp)
	if not _shot_cam.current:
		_shot_cam.make_current()
	var f: float = Engine.get_frames_per_second()
	if float(e["age"]) > 3.0 and f > 1.0:
		_fps_sum += f
		_fps_n += 1
		_fps_min = minf(_fps_min, f)
	if _shot_i < _shot_times.size() and float(e["age"]) >= float(_shot_times[_shot_i]):
		var path: String = "%s/naval_%s_%d.jpg" % [shots_dir, shot_tag, _shot_i + 1]
		_shot_i += 1
		_take_shot(path)
		if _shot_i >= _shot_times.size():
			get_tree().create_timer(2.5).timeout.connect(_shots_done)


func _take_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		img.save_jpg(path, 0.88)
	print("[naval] shot %s fps=%.0f ships=%d shells=%d" % [path, Engine.get_frames_per_second(), get_tree().get_nodes_in_group("ship").size(), _shells.size()])


func _shots_done() -> void:
	print("[naval] fps over the fight: avg %.1f, min %.1f (%d samples)" % [_fps_sum / maxf(float(_fps_n), 1.0), _fps_min, _fps_n])
	get_tree().quit()