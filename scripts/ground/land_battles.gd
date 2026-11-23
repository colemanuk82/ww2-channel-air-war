extends Node
## Land battle director: every few minutes a tank-and-infantry battle (LandBattle) starts at a plausible site 3.5-8.5 km
## from the player in free flight, is announced on the radio ("Panzers in the village at X, requesting air support!"),
## shows on the chart (M) as a pin, winds down after a few minutes and is tidied away once the player has left.
##
## Plausibility: the 1940-42 Channel front had no tank battles in England, so the sites follow the date and the ground:
##   before 25 June 1940, French ground ...... "arras"    Matildas counter-attack Panzers (the real 21 May 1940 fight)
##   26 June 1940 - May 1943, French ground .. "raid"     an Allied raid in force, Dieppe style (Churchills from mid-1942)
##   July 1940 - December 1941, English ground  "sealion"  WHAT-IF: a German foothold on the south coast (WHATIF_SEALION)
##   June 1943 on, French ground ............. "normandy" Shermans against Panzers in the bocage
## English ground at any other date, and anything near an airfield, gets no battle.
## Radio / HUD only use the existing Radio.say and hud.show_message. Debug: --battle-test, --battle-log,
## --battle-kind=raid|arras|sealion|normandy, --battle-dist=M, --battle-every=SECS, --no-battles, --no-whatif.
## Built without class_name (a new class_name needs an editor import first); load it with preload.

const LandBattle := preload("res://scripts/ground/land_battle.gd")
const GroundMarks := preload("res://scripts/ground/ground_marks.gd")

const Tempo := preload("res://scripts/modes/activity_tempo.gd")     # lulls hold back new battles; Busy / Quiet scale the gap
const FIRST_DELAY: float = 75.0
const GAP_MIN: float = 240.0
const GAP_MAX: float = 540.0
const RANGE_MIN: float = 3500.0
const RANGE_MAX: float = 8500.0
const AIRFIELD_CLEAR: float = 3000.0       # no battle this close to any airfield (either side)
const SITE_SPACING: float = 9000.0         # between two live battles
const MAX_ACTIVE: int = 2
const FREE_DIST: float = 16000.0           # a battle this far from the player is tidied away
const KEEP_AFTER_END: float = 150.0        # seconds a finished battle stays (if the player is still near)
const WHATIF_SEALION: bool = true          # the English-coast what-if

signal call_made(text: String)

var world: Node3D
var player: Aircraft
var hud: Node
var side: String = "Allies"                # the player's side
var difficulty: float = 0.4
var battles: Array = []
var calls: Array = []                      # every air-support call text, in order
var say_radio: bool = true                 # tests switch the radio off
var rng := RandomNumberGenerator.new()
var started_count: int = 0
var kills: int = 0                         # enemy vehicles the player destroyed in battles
var friendly_fire: int = 0                 # own-side vehicles / men the player hit
var helped: Array = []                     # battle ids the player helped (a kill while it was running)
var test_mode: bool = false
var test_kind: String = ""
var test_dist: float = 2200.0
var every_override: float = -1.0
var enabled: bool = true
var _timer: float = FIRST_DELAY
var _next_id: int = 1
var _log: bool = false
var _warn_t: float = 0.0


# ------------------------------------------------------------------ pure rules (tests)

## Which scenario fits this ground on this date? "" = none (English ground outside the what-if years, no sea lion).
static func scenario_for(date: String, ground_side: String, whatif: bool = true) -> String:
	var d: String = date if date != "" else "1940-08-08"
	if ground_side == "Axis":
		if d < "1940-06-25":
			return "arras"
		if d >= "1943-06-01":
			return "normandy"
		return "raid"
	# Allied-held ground: England, or France once liberated
	if d >= "1943-06-01":
		return "normandy"
	if whatif and WHATIF_SEALION and d >= "1940-07-01" and d < "1942-01-01":
		return "sealion"
	return ""


static func next_delay(r: float) -> float:
	return lerpf(GAP_MIN, GAP_MAX, clampf(r, 0.0, 1.0))


## Is `p` a fit site: land all round (not the sea, a beach is fine), clear of airfields and of other battles?
static func site_ok(p: Vector3, airfields: Array, active: Array) -> bool:
	if not LandBattle.drivable(p.x, p.z):
		return false
	var land: int = 0
	for i in 12:
		var a: float = TAU * float(i) / 12.0
		if LandBattle.drivable(p.x + cos(a) * 350.0, p.z + sin(a) * 350.0):
			land += 1
	if land < 8:
		return false
	for af in airfields:
		var ap: Vector3 = af if af is Vector3 else (af["pos"] as Vector3)
		if Vector2(ap.x - p.x, ap.z - p.z).length() < AIRFIELD_CLEAR:
			return false
	for q in active:
		var qp: Vector3 = q
		if Vector2(qp.x - p.x, qp.z - p.z).length() < SITE_SPACING:
			return false
	return true


## A random site ahead of / beside the player. Returns {} when none was found.
static func pick_site(from: Vector3, heading: Vector2, airfields: Array, active: Array, rng_in: RandomNumberGenerator, tries: int = 30, dmin: float = RANGE_MIN, dmax: float = RANGE_MAX, spread: float = 1.9) -> Dictionary:
	var base: float = atan2(heading.y, heading.x) if heading.length() > 0.01 else rng_in.randf() * TAU
	for i in tries:
		var ang: float = base + rng_in.randf_range(-spread, spread)
		var dist: float = rng_in.randf_range(dmin, dmax)
		var p := Vector3(from.x + cos(ang) * dist, 0.0, from.z + sin(ang) * dist)
		if site_ok(p, airfields, active):
			p.y = LandBattle.gy(p.x, p.z)
			return {"pos": p}
	return {}


## The unit vector from the site towards the direction the attackers come from: out to sea for beach scenarios
## (a landing), otherwise a random bearing with open land behind. `land_ok` is LandBattle.is_land.
static func attack_dir(p: Vector3, beach: bool, rng_in: RandomNumberGenerator) -> Vector2:
	var best := Vector2.ZERO
	var best_s: float = -1.0
	for i in 16:
		var a: float = TAU * float(i) / 16.0 + rng_in.randf() * 0.2
		var d := Vector2(cos(a), sin(a))
		var start: Vector2 = Vector2(p.x, p.z) + d * 1000.0
		if not LandBattle.drivable(start.x, start.y):
			continue
		var s: float = rng_in.randf()
		if beach and not LandBattle.is_land(p.x + d.x * 2300.0, p.z + d.y * 2300.0):
			s += 2.0            # the sea lies behind the attackers' start: they came ashore
		if LandBattle.is_land(p.x + d.x * 600.0, p.z + d.y * 600.0) and LandBattle.is_land(p.x + d.x * 850.0, p.z + d.y * 850.0):
			s += 0.5
		if s > best_s:
			best_s = s
			best = d
	if best_s < 0.0:
		return Vector2(cos(rng_in.randf() * TAU), sin(rng_in.randf() * TAU))
	return best


# ------------------------------------------------------------------ running

func setup(p_world: Node3D, p_player: Aircraft, p_hud: Node, p_side: String, p_difficulty: float) -> void:
	world = p_world
	player = p_player
	hud = p_hud
	side = p_side
	difficulty = p_difficulty
	rng.randomize()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_log = "--battle-log" in args
	LandBattle._log = _log
	enabled = not ("--no-battles" in args)
	test_mode = "--battle-test" in args
	for a in args:
		if a.begins_with("--battle-kind="):
			test_kind = a.substr(14)
		elif a.begins_with("--battle-dist="):
			test_dist = float(a.substr(14))
		elif a.begins_with("--battle-every="):
			every_override = float(a.substr(15))
	if "--battle-shots" in args:
		call_deferred("_shots_run")
	if test_mode:
		_timer = 6.0
	elif every_override > 0.0:
		_timer = minf(every_override, FIRST_DELAY)


func _airfields() -> Array:
	var out: Array = []
	var pop: WorldPopulator = WorldPopulator.instance
	if pop == null:
		return out
	for f in ["RAF", "Luftwaffe"]:
		for a in pop.airfield_sites(f):
			out.append(a["pos"])
	return out


func _active_sites() -> Array:
	var out: Array = []
	for b in battles:
		if is_instance_valid(b):
			out.append((b as Node3D).centre)
	return out


func _alive() -> bool:
	return player != null and is_instance_valid(player) and player.state == Aircraft.State.ALIVE


func _process(delta: float) -> void:
	if not enabled or world == null or not _alive():
		return
	_housekeeping(delta)
	_timer -= delta
	if _timer > 0.0:
		return
	if Tempo.lulling and every_override <= 0.0 and not test_mode:
		_timer = 15.0             # a lull in the air war (activity_tempo.gd): no new battle until it is over
		return
	var active: int = 0
	for b in battles:
		if is_instance_valid(b) and not (b as Node3D).ended:
			active += 1
	if active >= MAX_ACTIVE:
		_timer = 30.0
		return
	if start_battle():
		_timer = every_override if every_override > 0.0 else next_delay(rng.randf()) * Tempo.event_scale()
		if test_mode:
			_timer = 99999.0
	else:
		_timer = 20.0


func _housekeeping(delta: float) -> void:
	var i: int = battles.size() - 1
	while i >= 0:
		var b: Node3D = battles[i] if is_instance_valid(battles[i]) else null
		if b == null:
			battles.remove_at(i)
		else:
			var d: float = Vector2(player.global_position.x - b.centre.x, player.global_position.z - b.centre.z).length()
			if not b.ended and b.has_meta("gm_smoke_at") and b.age >= float(b.get_meta("gm_smoke_at")):
				_marker_smoke(b, d)       # refresh the marker smoke every 60-100 s while support is wanted
			if d > FREE_DIST or (b.ended and b.age - b.end_age > KEEP_AFTER_END and d > 4500.0) or b.age > 1500.0:
				b.queue_free()
				battles.remove_at(i)
		i -= 1


## Start a battle now at a site near the player. Returns false when no site was found.
func start_battle(force_kind: String = "", force_site: Variant = null) -> bool:
	var date: String = GroundKit.era_date()
	var pos := Vector3.ZERO
	var k: String = force_kind if force_kind != "" else test_kind
	if force_site != null:
		pos = force_site
	else:
		var heading := Vector2(-sin(player.rotation.y), -cos(player.rotation.y))
		var site: Dictionary
		if test_mode:
			site = pick_site(player.global_position, heading, [], _active_sites(), rng, 60, test_dist, test_dist * 1.3, 0.9)
		else:
			site = pick_site(player.global_position, heading, _airfields(), _active_sites(), rng)
		if site.is_empty():
			return false
		pos = site["pos"]
	if k == "":
		k = scenario_for(date, GroundKit.side_at(pos), not ("--no-whatif" in OS.get_cmdline_user_args()))
		if k == "" and test_mode:
			k = "raid"
	if k == "":
		return false
	var b: Node3D = spawn_battle(k, pos, date)
	if b == null:
		return false
	return true


func spawn_battle(k: String, pos: Vector3, date: String = "") -> Node3D:
	var b: Node3D = LandBattle.new()
	b.name = "LandBattle%d" % _next_id
	_next_id += 1
	var sc: Dictionary = LandBattle.scenario(k, date)
	var dir: Vector2 = attack_dir(pos, bool(sc["beach"]), rng)
	b.setup(k, pos, dir, side, rng.randi(), date)
	b.set_meta("battle_id", _next_id - 1)
	if world != null:
		world.add_child(b)
	else:
		add_child(b)
	b.losing.connect(_on_losing.bind(b))
	b.finished.connect(_on_finished.bind(b))
	b.friendly_hit.connect(_on_friendly_hit)
	battles.append(b)
	started_count += 1
	_announce_start(b)
	if _log:
		print("[battle] started #%d %s at %.0f, %.0f (%s)" % [_next_id - 1, k, pos.x, pos.z, place_name(pos)])
	return b


# ------------------------------------------------------------------ radio and chart

## The nearest named town to `p`, for the call.
static func place_name(p: Vector3) -> String:
	var pop: WorldPopulator = WorldPopulator.instance
	var best: String = ""
	var bd: float = 1.0e12
	if pop != null:
		for c in pop.loc.get("cities", []):
			var cp: Vector3 = pop._ll(c)
			var d: float = Vector2(cp.x - p.x, cp.z - p.z).length()
			if d < bd:
				bd = d
				best = str(c.get("name", c.get("id", "")))
	if best == "" or bd > 25000.0:
		return "the coast road" if best == "" else "the countryside near " + best
	return best if bd < 3500.0 else "the fields near " + best


func _callsign() -> String:
	var r: Node = get_node_or_null("/root/Radio")
	if r != null and r.has_method("callsign_of") and player != null:
		return str(r.call("callsign_of", player))
	return "Red 1"


## The text of the air-support call for battle `b`: the friendly side asks for help against the enemy's armour.
func call_text(b: Node3D, stage: int) -> String:
	var friendly: String = side
	var enemy: String = GroundKit.enemy_of(side)
	var place: String = place_name(b.centre)
	var attacking: bool = friendly == b.att_team
	var ours: String = b.who(friendly)
	var theirs: String = b.who(enemy)
	var cs: String = _callsign()
	if stage == 1:
		return "%s, Control. We are being overrun at %s - the %s are through. Anything you can spare, please, now!" % [cs, place, theirs]
	if stage == 2:
		return "%s, Control. Well done - the %s at %s have been broken." % [cs, theirs, place]
	if attacking:
		return "%s, Control. Our %s are pinned down at %s by %s and anti-tank guns, requesting air support!" % [cs, ours, place, theirs]
	return "%s, Control. %s attacking at %s, our lads are hard pressed, requesting air support!" % [cs, theirs, place]


func _say(text: String, voice_cat: String = "") -> void:
	calls.append(text)
	call_made.emit(text)
	if say_radio:
		var r: Node = get_node_or_null("/root/Radio")
		if r != null and r.has_method("say"):
			# a generic recorded call of the same kind (support_land / _losing / _thanks), if there is one
			var vclip: String = str(r.call("chatter_clip", voice_cat)) if (voice_cat != "" and r.has_method("chatter_clip")) else ""
			r.call("say", "Control", text, 1, 1.0, vclip)     # Radio.Kind.CONTROL
	if hud != null and is_instance_valid(hud) and hud.has_method("show_message") and say_radio:
		hud.call("show_message", text.get_slice("Control. ", 1), 6.0)


func _announce_start(b: Node3D) -> void:
	var d: float = Vector2(player.global_position.x - b.centre.x, player.global_position.z - b.centre.z).length() if player != null else 0.0
	if d < 14000.0:
		_say(call_text(b, 0), "support_land")
		_support_mark(b)


func _on_losing(team: String, b: Node3D) -> void:
	if team == side and is_instance_valid(b) and not b.ended:
		_say(call_text(b, 1), "support_land_losing")
		_support_mark(b)


## Minimap: a "ground support requested" ring at the battle centre (same style as the naval fights). The anchor is a
## child of the battle, so it goes with the battle; it is unregistered when the battle ends (_drop_support).
func _support_mark(b: Node3D) -> void:
	_marker_smoke(b)
	if hud == null or not is_instance_valid(hud) or not hud.has_method("register_support_marker"):
		return
	var a: Node3D = b.get_node_or_null("SupportMark") as Node3D
	if a == null:
		a = Node3D.new()
		a.name = "SupportMark"
		b.add_child(a)
	if a.is_inside_tree():
		a.global_position = b.centre
	else:
		a.position = b.centre
	hud.call("register_support_marker", a)


## Friendly troops pop marker smoke (yellow on the enemy, white on their own line) when support is requested and refresh it.
func _marker_smoke(b: Node3D, player_dist: float = -1.0) -> void:
	var pd: float = player_dist
	if pd < 0.0 and player != null and is_instance_valid(player):
		pd = Vector2(player.global_position.x - b.centre.x, player.global_position.z - b.centre.z).length()
	b.set_meta("gm_smoke_at", b.age + rng.randf_range(60.0, 100.0))
	if pd > 14000.0:
		return
	GroundMarks.battle_smoke(b, side)


func _drop_support(b: Node3D) -> void:
	var a: Node = b.get_node_or_null("SupportMark")
	if a == null:
		return
	if hud != null and is_instance_valid(hud) and hud.has_method("unregister_support_marker"):
		hud.call("unregister_support_marker", a)
	a.queue_free()


func _on_finished(winner: String, b: Node3D) -> void:
	if not is_instance_valid(b):
		return
	_drop_support(b)
	var id: int = int(b.get_meta("battle_id", 0))
	if winner == side and b.kills_by_player > 0:
		_say(call_text(b, 2), "support_land_thanks")
	if b.kills_by_player > 0 and not helped.has(id):
		helped.append(id)


func _on_friendly_hit(_what: String) -> void:
	friendly_fire += 1
	if hud != null and is_instance_valid(hud) and hud.has_method("show_message") and _warn_t <= 0.0:
		hud.call("show_message", "Friendly troops hit! Check your target.", 3.0)


## Chart pins (key M): one per live battle, gold while it rages, grey once it is over.
func map_pins() -> Array:
	var out: Array = []
	for b in battles:
		if not is_instance_valid(b):
			continue
		var bb: Node3D = b
		out.append({"pos": bb.centre, "name": ("Tank battle (over)" if bb.ended else "Tank battle: air support wanted"),
			"col": Color(0.6, 0.6, 0.6) if bb.ended else Color(1.0, 0.45, 0.2), "main": false})
	return out


## The nearest live battle (for the compass), or null.
func nav_point() -> Variant:
	var best: Variant = null
	var bd: float = 1.0e12
	if player == null or not is_instance_valid(player):
		return null
	for b in battles:
		if not is_instance_valid(b) or (b as Node3D).ended:
			continue
		var d: float = Vector2(player.global_position.x - b.centre.x, player.global_position.z - b.centre.z).length()
		if d < bd:
			bd = d
			best = b.centre
	return best


func stats() -> Dictionary:
	var k: int = 0
	var ff: int = 0
	for b in battles:
		if is_instance_valid(b):
			k += (b as Node3D).kills_by_player
			ff += (b as Node3D).friendly_fire
	return {"battles_seen": started_count, "battle_kills": maxi(kills, k), "battle_friendly_fire": maxi(friendly_fire, ff)}


# ------------------------------------------------------------------ debug: hidden-desktop pictures (--battle-shots)
## Use with `--battle-test --battle-kind=raid --battle-dist=1800 --air --freeze --at=lat,lon,alt,hdg --nohud`: waits for the
## battle, flies a camera round it (wide, low pass, close, ground level, late) and saves build/fix/battle_<name>.jpg,
## logging the frame rate. `--battle-timescale=N` runs the battle faster between pictures. Quits when done.

var _cam: Camera3D = null
var _fps: Array = []
var _shot_dir: String = "F:/ww2_dlss/build/fix"


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout


func _fps_sample(sec: float, label: String) -> void:
	var t: float = 0.0
	var vals: Array = []
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time() / maxf(Engine.time_scale, 0.01)
		vals.append(Engine.get_frames_per_second())
	var lo: float = 1.0e9
	var sum: float = 0.0
	for v in vals:
		lo = minf(lo, float(v))
		sum += float(v)
	var avg: float = sum / maxf(float(vals.size()), 1.0)
	_fps.append({"label": label, "avg": avg, "min": lo})
	print("[battle-shots] fps %s: avg %.1f min %.1f (%d samples)" % [label, avg, lo, vals.size()])


func _cam_to(pos: Vector3, look: Vector3, fov: float = 62.0) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.name = "BattleShotCam"
		_cam.far = 20000.0
		add_child(_cam)
	_cam.fov = fov
	_cam.global_transform = Transform3D(Basis.looking_at((look - pos).normalized(), Vector3.UP), pos)
	_cam.make_current()


func _save(name_s: String) -> void:
	for i in 4:
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		print("[battle-shots] empty image for ", name_s)
		return
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	var path: String = "%s/battle_%s.jpg" % [_shot_dir, name_s]
	var err: Error = img.save_jpg(path, 0.9)
	print("[battle-shots] %s -> %s (%s)" % [name_s, path, error_string(err)])


func _unit_of(b: Node3D, team: String, role: String, alive: bool) -> Variant:
	for u in b.units:
		if u.team == team and u.role == role and u.alive == alive:
			return u
	return null


func _shots_run() -> void:
	var scale_t: float = 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--battle-timescale="):
			scale_t = float(a.substr(19))
		elif a.begins_with("--battle-out="):
			_shot_dir = a.substr(13)
	var guard: int = 0
	while battles.is_empty() and guard < 600:
		guard += 1
		await _wait(0.5)
	if battles.is_empty():
		print("[battle-shots] no battle started")
		get_tree().quit(2)
		return
	player.invulnerable = true
	var b: Node3D = battles[0]
	var c: Vector3 = b.centre
	var ad: Vector2 = b.att_dir
	var ad3 := Vector3(ad.x, 0, ad.y)
	var pd3 := Vector3(-ad.y, 0, ad.x)
	print("[battle-shots] battle %s at %.0f, %.0f; attackers from %s" % [b.kind, c.x, c.z, str(ad)])
	for u in b.units:
		print("[battle-shots] unit %s %s %s at %.0f m along, %.0f m across" % [u.team, u.vtype, u.role, (u.pos() - c).dot(ad3), (u.pos() - c).dot(pd3)])
	await _wait(14.0)                         # the terrain, buildings and men stream in
	_cam_to(c + ad3 * 1900.0 + Vector3(0, 380.0, 0), c + ad3 * 300.0, 55.0)
	await _fps_sample(3.0, "wide")
	await _save("wide")
	Engine.time_scale = scale_t
	await _wait(40.0)
	Engine.time_scale = 1.0
	# behind the lead attacking tank, looking along its advance
	var lead: Variant = _unit_of(b, b.att_team, "tank", true)
	if lead != null:
		var lp: Vector3 = lead.pos()
		_cam_to(lp + ad3 * 55.0 + pd3 * 14.0 + Vector3(0, 20.0, 0), lp - ad3 * 120.0 + Vector3(0, 2.0, 0), 62.0)
		await _fps_sample(2.0, "tanks")
		await _save("tanks")
	# the infantry: a squad of the attackers
	for s in b.squads:
		if s.team == b.att_team and s.n > 0:
			var sc2: Vector2 = b.squad_centre(s)
			var sp := Vector3(sc2.x, LandBattle.gy(sc2.x, sc2.y), sc2.y)
			_cam_to(sp + ad3 * 30.0 + pd3 * 12.0 + Vector3(0, 14.0, 0), sp + Vector3(0, 0.5, 0), 55.0)
			await _fps_sample(2.0, "infantry")
			await _save("infantry")
			break
	# the defenders' side from a low pass
	var tg: Variant = _unit_of(b, b.def_team, "gun", true)
	if tg == null:
		tg = _unit_of(b, b.def_team, "tank", true)
	if tg != null:
		var gp: Vector3 = tg.pos()
		_cam_to(gp + ad3 * 130.0 + pd3 * 60.0 + Vector3(0, 40.0, 0), gp + Vector3(0, 2.0, 0), 62.0)
		await _fps_sample(2.0, "defenders")
		await _save("defenders")
	_cam_to(c + ad3 * 520.0 + pd3 * 200.0 + Vector3(0, 70.0, 0), c, 62.0)
	await _fps_sample(2.0, "pass")
	await _save("pass")
	Engine.time_scale = scale_t
	await _wait(50.0)
	Engine.time_scale = 1.0
	_cam_to(c + pd3 * 700.0 + Vector3(0, 200.0, 0), c, 55.0)
	await _fps_sample(2.0, "mid")
	await _save("mid")
	Engine.time_scale = scale_t
	var guard2: int = 0
	while not b.ended and guard2 < 400:
		guard2 += 1
		await _wait(2.0)
	Engine.time_scale = 1.0
	var wreck: Variant = _unit_of(b, b.att_team, "tank", false)
	if wreck == null:
		wreck = _unit_of(b, b.def_team, "tank", false)
	if wreck != null:
		var wp: Vector3 = wreck.pos()
		_cam_to(wp + ad3 * 60.0 + pd3 * 30.0 + Vector3(0, 22.0, 0), wp + Vector3(0, 2.0, 0), 62.0)
		await _fps_sample(2.0, "wreck")
		await _save("wreck")
	_cam_to(c + pd3 * 500.0 + Vector3(0, 160.0, 0) + ad3 * 100.0, c + Vector3(0, 4.0, 0), 58.0)
	await _fps_sample(2.0, "late")
	await _save("late")
	print("[battle-shots] status %s calls %s ruin_calls %d shells %d impacts %d craters %d" % [str(b.status()), str(calls), b.ruin_calls, b.shells_fired, b.impacts, b.craters_made])
	get_tree().quit(0)
