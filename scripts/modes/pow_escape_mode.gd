class_name PowEscapeMode
extends ModeBase
## POW escape operations (see PowEscapeCampaign). Two kinds of sortie:
##   "scout"   by day, in a fast aircraft: photograph the camp, then the field strip near it, then fly home.
##   "pickup"  by night, in a civil DH.89 Dragon Rapide: fly in low and slow under the cloud, land on the strip,
##             take the escapers aboard (they run out of the hedge to the aircraft one at a time), take off and
##             get away. Quiet is the point: an ALERT meter fills while the aircraft is near the camp, faster
##             when it is high, fast or lit by a searchlight, and the operation is blown if it fills before the
##             men are aboard. Reach the home gate (where the sortie began) with them to succeed.

const ZONE_R: float = 2800.0              # the camp hears and sees an aircraft inside this
const PHOTO_CAMP_R: float = 900.0
const PHOTO_CAMP_AGL_M: float = 450.0     # the camera needs 1,500 ft or less
const PHOTO_STRIP_R: float = 500.0
const PHOTO_STRIP_AGL_M: float = 300.0
const PHOTO_HOLD: float = 2.0             # steady seconds over the subject for the camera run
const HOME_R: float = 3500.0
const BOARD_R: float = 90.0               # stop within this of the group and they come
const BOARD_STOP: float = 3.0             # m/s: the aircraft must be (nearly) stopped for them to run to it
const BOARD_EVERY: float = 3.2            # seconds between men leaving the hedge
const RUN_SPEED: float = 6.5
const REVEAL_R: float = 8000.0            # the reception committee shows its torches inside this
const ALERT_BASE: float = 0.0042          # per second inside the zone, flying low and slow
const ALERT_HIGH: float = 0.040           # extra per second at 300 m or more above the ground
const ALERT_FAST: float = 0.018           # extra per second at 85 m/s or more
const ALERT_LIT: float = 0.16             # extra per second while a searchlight holds the aircraft
const ALERT_DECAY: float = 0.045          # per second outside the zone

var start_airborne: bool = true
var manages_respawn: bool = true

var kind: String = "scout"
var camp_id: String = "frontstalag_194"
var strip_id: String = "strip_chalons"
var title: String = "POW escape"
var op_index: int = 0
var n_prisoners: int = 6

var _camp: Vector3 = Vector3.ZERO
var _strip_pos: Vector3 = Vector3.ZERO
var _strip_dir: Vector3 = Vector3.FORWARD
var _gate: Vector3 = Vector3.ZERO
var _have_places: bool = false
var _ended: bool = false

# scout
var _camp_done: bool = false
var _strip_done: bool = false
var _hold_camp: float = 0.0
var _hold_strip: float = 0.0
var _warn_t: float = -10.0

# pickup
var _stage: String = "in"               # in | load | out
var alert: float = 0.0
var _aboard: int = 0
var _board_t: float = 0.0
var _torches: Array = []
var _torches_on: bool = false
var _group_pos: Vector3 = Vector3.ZERO
var _men: Array = []                    # {"node", "state" (wait/run/in), "t"}
var _lit_warned: bool = false
var _alert_msgs: int = 0
var _status_t: float = 0.0
var _spawned: Array = []
var _nav_dots: Array = []
var _hold_warned: bool = false


func configure(cfg: Dictionary) -> void:
	kind = str(cfg.get("kind", "scout"))
	camp_id = str(cfg.get("camp", camp_id))
	strip_id = str(cfg.get("strip", strip_id))
	title = str(cfg.get("title", title))
	op_index = int(cfg.get("op", 0))
	n_prisoners = clampi(int(cfg.get("prisoners", 6)), 1, 8)
	if cfg.has("era_date"):
		GameState.era_date = str(cfg["era_date"])
	TimeOfDay.set_preset(str(cfg.get("time", "noon")))
	WeatherManager.set_weather(str(cfg.get("weather", "clear")), 0.1)


func start() -> void:
	super.start()
	elapsed = 0.0
	var pop: WorldPopulator = WorldPopulator.instance
	if pop != null:
		pop.pin_site("pow_" + camp_id)
		pop.pin_site("strip_" + strip_id)
	_resolve_places()
	if player is Node3D:
		_gate = (player as Node3D).global_position
	if kind == "pickup":
		_build_group_and_torches()
	_build_defences()
	_nav_dots.append(_add_nav_dot(_camp if kind == "scout" else _strip_pos))
	var pl: Aircraft = player as Aircraft
	if pl != null:
		pl.destroyed.connect(_on_player_down)
	if kind == "pickup":
		Radio.say("Control", "Operation under way. Stay under the cloud and keep the engines throttled back. Torches in an L when they hear you.", Radio.Kind.CONTROL, 2.0)
	else:
		Radio.say("Control", "Photograph the camp, then the field to its side. Low and fast, and straight home.", Radio.Kind.CONTROL, 2.0)
	_update_status()


func stop() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_spawned.clear()
	if hud != null and hud.has_method("set_readout_extra"):
		hud.call("set_readout_extra", "")
	super.stop()


## Camp and strip positions: from what the world populator placed, or worked out here when it did not.
func _resolve_places() -> void:
	var d: Dictionary = EscapeStripKit.placed.get(strip_id, {})
	if d.is_empty():
		var row: Array = PowEscapeCampaign.camp_row(camp_id)
		if not row.is_empty():
			var camp: Vector3 = PowCampKit.flattest(WorldCoords.latlon_to_world(float(row[2]), float(row[3])), str(row[5]), int(row[6]))
			var pl: Dictionary = EscapeStripKit.plan(camp)
			var sp: Vector3 = pl["pos"]
			sp.y = GroundKit.ground_y(sp.x, sp.z)
			d = {"pos": sp, "heading": float(pl["heading"]), "camp": camp}
	if d.is_empty():
		push_warning("PowEscapeMode: no camp or strip for %s" % camp_id)
		return
	_camp = d["camp"]
	_camp.y = GroundKit.ground_y(_camp.x, _camp.z)
	_strip_pos = d["pos"]
	_strip_dir = WorldCoords.heading_to_dir(float(d["heading"]))
	_have_places = true


func nav_point() -> Variant:
	if not _have_places:
		return null
	if kind == "scout":
		if not _camp_done:
			return _camp
		if not _strip_done:
			return _strip_pos
		return _gate
	if _stage == "out":
		return _gate
	return _strip_pos


# ------------------------------------------------------------------ scenery and defences

func _ground_at(p: Vector3) -> Vector3:
	return Vector3(p.x, GroundKit.ground_y(p.x, p.z), p.z)


func _own(n: Node) -> void:
	_spawned.append(n)


## Machine guns and a light gun on the camp's towers; at night two searchlights besides. Trier has more.
func _build_defences() -> void:
	if not _have_places or world == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(camp_id + kind)
	var night: bool = kind == "pickup"
	var extra: int = 1 if camp_id == "stalag_12d" else 0
	var n_mg: int = 3 + extra
	for i in n_mg:
		var a: float = TAU * (float(i) + rng.randf()) / float(n_mg)
		var r: float = rng.randf_range(160.0, 300.0)
		var g: AAGun = AAGun.create("mg", "Axis")
		g.position = _ground_at(_camp + Vector3(cos(a) * r, 0.0, sin(a) * r))
		world.add_child(g)
		_own(g)
	var bf: AAGun = AAGun.create("bofors", "Axis")
	bf.position = _ground_at(_camp + Vector3(rng.randf_range(-200.0, 200.0), 0.0, rng.randf_range(-200.0, 200.0)))
	world.add_child(bf)
	_own(bf)
	if night:
		for i in 2 + extra:
			var a2: float = TAU * (float(i) + 0.3) / float(2 + extra)
			var sl: Searchlight = Searchlight.create("Axis")
			sl.position = _ground_at(_camp + Vector3(cos(a2) * 520.0, 0.0, sin(a2) * 520.0))
			world.add_child(sl)
			_own(sl)


func _glow(col: Color, a: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col, a)
	m.disable_fog = true
	return m


## The reception committee: three torches in an L on the strip (lit when the aircraft is near), and the escapers
## waiting in the hedge beside the strip.
func _build_group_and_torches() -> void:
	if not _have_places or world == null:
		return
	var side: Vector3 = Vector3(-_strip_dir.z, 0.0, _strip_dir.x)
	var le: Dictionary = EscapeStripKit.landing_end(strip_id, _gate)
	var thr: Vector3 = _strip_pos - _strip_dir * (EscapeStripKit.LENGTH * 0.5 - 40.0)
	var dir: Vector3 = _strip_dir
	if not le.is_empty():
		thr = le["threshold"]
		dir = le["dir"]
	var pts: Array = [thr, thr + dir * 140.0, thr + dir * 280.0, thr + dir * 140.0 + Vector3(-dir.z, 0.0, dir.x) * 55.0]
	for p in pts:
		var gp: Vector3 = _ground_at(p)
		var t := Node3D.new()
		t.position = gp
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.72, 0.35)
		lamp.light_energy = 2.2
		lamp.omni_range = 70.0
		lamp.position = Vector3(0.0, 2.0, 0.0)
		t.add_child(lamp)
		var flame := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.9
		sm.height = 1.8
		flame.mesh = sm
		flame.material_override = _glow(Color(1.0, 0.65, 0.25))
		flame.position = Vector3(0.0, 1.4, 0.0)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.add_child(flame)
		t.visible = false
		world.add_child(t)
		_torches.append(t)
		_own(t)
	# the group waits in the hedge beside the middle of the strip, away from the camp side if it can
	var away: float = 1.0 if (_strip_pos - _camp).dot(side) > 0.0 else -1.0
	_group_pos = _ground_at(_strip_pos + side * away * (EscapeStripKit.WIDTH * 0.5 + 18.0) + dir * 40.0)
	for i in n_prisoners:
		var fig: MeshInstance3D = CrewFigure.make("Allies", CrewFigure.Pose.KNEEL if i % 2 == 0 else CrewFigure.Pose.STAND, 2 + (i % 2))
		fig.position = _ground_at(_group_pos + Vector3(float(i % 3) * 2.2, 0.0, float(i / 3) * 2.2))
		fig.visible = false
		fig.scale = Vector3.ONE
		world.add_child(fig)
		_men.append({"node": fig, "state": "wait", "t": 0.0})
		_own(fig)


# ------------------------------------------------------------------ the tick

func _agl_m(pl: Aircraft) -> float:
	return pl.altitude_agl / WorldCoords.VERTICAL_SCALE


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _say(text: String, secs: float = 3.5) -> void:
	if hud != null and hud.has_method("show_message"):
		hud.call("show_message", text, secs)


func _process(delta: float) -> void:
	super._process(delta)
	if not running or _ended or not (player is Aircraft) or not _have_places:
		return
	var pl: Aircraft = player as Aircraft
	if kind == "scout":
		_tick_scout(pl, delta)
	else:
		_tick_pickup(pl, delta)
	_status_t += delta
	if _status_t >= 0.4:
		_status_t = 0.0
		_update_status()


func _photo(pl: Aircraft, subject: Vector3, radius: float, agl_max: float, hold: float, delta: float) -> float:
	## Returns the new hold time over the subject: grows while the aircraft is over it and low enough, drains otherwise.
	var d: float = _flat_dist(pl.global_position, subject)
	if d < radius:
		if _agl_m(pl) <= agl_max:
			return hold + delta
		if elapsed - _warn_t > 4.0:
			_warn_t = elapsed
			_say("TOO HIGH for the camera: %d m or below" % int(agl_max))
	return maxf(hold - delta * 2.0, 0.0)


func _tick_scout(pl: Aircraft, delta: float) -> void:
	if not _camp_done:
		_hold_camp = _photo(pl, _camp, PHOTO_CAMP_R, PHOTO_CAMP_AGL_M, _hold_camp, delta)
		if _hold_camp >= PHOTO_HOLD:
			_camp_done = true
			add_score(300)
			_say("CAMP PHOTOGRAPHED. Now the field strip.", 4.0)
			Radio.say("Photo section", "Good run over the camp. Huts, wire, towers, all on the plate.", Radio.Kind.FRIENDLY, 1.0)
			objective_updated.emit(_objective_text())
	elif not _strip_done:
		_hold_strip = _photo(pl, _strip_pos, PHOTO_STRIP_R, PHOTO_STRIP_AGL_M, _hold_strip, delta)
		if _hold_strip >= PHOTO_HOLD:
			_strip_done = true
			add_score(300)
			_say("FIELD STRIP PHOTOGRAPHED. Home now.", 4.0)
			Radio.say("Photo section", "Long, level and firm. They can land a Rapide there. Come home.", Radio.Kind.FRIENDLY, 1.0)
			objective_updated.emit(_objective_text())
	else:
		if _flat_dist(pl.global_position, _gate) < HOME_R:
			_end(true, "scouted")


func _alert_rate(pl: Aircraft) -> float:
	var r: float = ALERT_BASE
	r += ALERT_HIGH * clampf((_agl_m(pl) - 100.0) / 200.0, 0.0, 1.0)
	if not pl.on_ground:
		r += ALERT_FAST * clampf((pl.speed - 50.0) / 35.0, 0.0, 1.0)
	if pl.has_meta("lit_until") and float(pl.get_meta("lit_until")) > float(Time.get_ticks_msec()) * 0.001:
		r += ALERT_LIT
	# cloud and rain cover the noise and the silhouette
	var wm: String = str(WeatherManager.current)
	if wm == "overcast":
		r *= 0.8
	elif wm == "rain" or wm == "storm":
		r *= 0.65
	return r


func _tick_pickup(pl: Aircraft, delta: float) -> void:
	var d_camp: float = _flat_dist(pl.global_position, _camp)
	# alert
	if d_camp < ZONE_R:
		alert += _alert_rate(pl) * delta
	else:
		alert = maxf(alert - ALERT_DECAY * delta, 0.0)
	alert = clampf(alert, 0.0, 1.0)
	_alert_events(d_camp)
	if alert >= 1.0 and _stage != "out":
		_end(false, "blown")
		return
	# torches
	if not _torches_on and _flat_dist(pl.global_position, _strip_pos) < REVEAL_R:
		_torches_on = true
		for t in _torches:
			(t as Node3D).visible = true
		for m in _men:
			((m as Dictionary)["node"] as Node3D).visible = true
		_say("TORCHES IN AN L AHEAD. Land beside the group.", 5.0)
		Radio.say("Reception", "We hear you. Torches are lit. Come in over the hedge and stop by us.", Radio.Kind.FRIENDLY, 1.0)
	for t2 in _torches:
		var lamp: OmniLight3D = (t2 as Node3D).get_child(0) as OmniLight3D
		if lamp != null:
			lamp.light_energy = 2.0 + 0.5 * sin(elapsed * 17.0 + float(_torches.find(t2))) + 0.25 * sin(elapsed * 31.0)
	# stage machine
	match _stage:
		"in":
			if pl.on_ground and pl.speed < BOARD_STOP and _flat_dist(pl.global_position, _group_pos) < BOARD_R:
				_stage = "load"
				_board_t = BOARD_EVERY * 0.5
				_say("THEY ARE COMING. Hold still.", 3.0)
			elif pl.on_ground and pl.speed < BOARD_STOP and _flat_dist(pl.global_position, _strip_pos) < 500.0 and elapsed - _warn_t > 6.0:
				_warn_t = elapsed
				_say("Taxi closer to the group in the hedge", 3.0)
		"load":
			_tick_loading(pl, delta)
		"out":
			if _flat_dist(pl.global_position, _gate) < HOME_R:
				_end(true, "recovered")
	_animate_men(pl, delta)


func _tick_loading(pl: Aircraft, delta: float) -> void:
	var near: bool = pl.on_ground and _flat_dist(pl.global_position, _group_pos) < BOARD_R * 1.6
	var still: bool = pl.speed < BOARD_STOP * 1.8
	if not near:
		_stage = "in"
		_say("Group left behind: go back to them", 3.0)
		return
	if not still:
		if not _hold_warned:
			_hold_warned = true
			_say("HOLD STILL: they cannot reach a moving aircraft", 2.5)
		return
	_hold_warned = false
	_board_t += delta
	if _board_t >= BOARD_EVERY:
		_board_t = 0.0
		for m in _men:
			var md: Dictionary = m
			if md["state"] == "wait":
				md["state"] = "run"
				break


func _animate_men(pl: Aircraft, delta: float) -> void:
	var target: Vector3 = pl.global_position
	for m in _men:
		var md: Dictionary = m
		if md["state"] != "run":
			continue
		var node: Node3D = md["node"]
		var to: Vector3 = target - node.global_position
		to.y = 0.0
		var dist: float = to.length()
		if dist < 7.0 or (_stage != "load" and dist < 25.0):
			md["state"] = "in"
			node.visible = false
			_aboard += 1
			add_score(150)
			_say("%d of %d ABOARD" % [_aboard, n_prisoners], 2.5)
			if _aboard >= n_prisoners:
				_stage = "out"
				_say("ALL ABOARD. GET OUT.", 4.0)
				Radio.say("Reception", "All aboard. Go, go. Good luck.", Radio.Kind.FRIENDLY, 0.5)
				_nav_dots.append(_add_nav_dot(_gate))
				objective_updated.emit(_objective_text())
			continue
		var step: Vector3 = to / dist * minf(RUN_SPEED * delta, dist)
		node.global_position += step
		node.global_position.y = GroundKit.ground_y(node.global_position.x, node.global_position.z)
		node.look_at(node.global_position - to, Vector3.UP)
		md["t"] = float(md["t"]) + delta
		var phase: int = int(float(md["t"]) / 0.22) % 2
		(node as MeshInstance3D).mesh = CrewFigure.mesh("Allies", CrewFigure.Pose.WALK_A if phase == 0 else CrewFigure.Pose.WALK_B, 2)


func _alert_events(d_camp: float) -> void:
	if alert >= 0.35 and _alert_msgs < 1:
		_alert_msgs = 1
		_say("A dog is barking at the camp. Throttle back and stay low.", 3.5)
	elif alert >= 0.65 and _alert_msgs < 2:
		_alert_msgs = 2
		_say("GUARDS ARE STIRRING. Get the men and go.", 3.5)
	elif alert >= 0.85 and _alert_msgs < 3:
		_alert_msgs = 3
		_say("THE CAMP IS AWAKE: lights are coming on", 3.5)
	if alert < 0.2:
		_alert_msgs = 0


func _update_status() -> void:
	if hud == null or not hud.has_method("set_readout_extra"):
		return
	if kind == "scout":
		hud.call("set_readout_extra", _objective_text())
		return
	var bar: String = "ALERT %d%%" % int(round(alert * 100.0))
	hud.call("set_readout_extra", "%s   ABOARD %d/%d\n%s" % [bar, _aboard, n_prisoners, _objective_text()])


func _objective_text() -> String:
	if kind == "scout":
		if not _camp_done:
			return "Photograph the camp (%d m or below, hold steady over it)" % int(PHOTO_CAMP_AGL_M)
		if not _strip_done:
			return "Photograph the field strip nearby"
		return "Return to base"
	match _stage:
		"in":
			return "Fly in low and slow to the torches, land and stop beside the group"
		"load":
			return "Loading: hold still while they board"
		_:
			return "All aboard: fly home quietly, low and slow"


## A minimap dot at p. The HUD drops it when the node is freed.
func _add_nav_dot(p: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = p
	if hud != null:
		AIFactory.add_marker(hud, n, Color(0.55, 0.92, 1.0))
	return n


func _stats() -> Dictionary:
	return {"prisoners": _aboard, "alert": int(round(alert * 100.0))}


func _on_player_down(_a: Node, _k: Node) -> void:
	if _ended:
		return
	_end(false, "shot_down")


func _end(success: bool, reason: String) -> void:
	if _ended:
		return
	_ended = true
	var msg: String = ""
	match reason:
		"blown":
			msg = "The camp is awake: the reception committee has scattered. Operation blown."
		"shot_down":
			msg = "Aircraft lost."
		"recovered":
			msg = "%d men are out." % _aboard
		"scouted":
			msg = "Photographs delivered."
	_say(msg, 5.0)
	finish(success, {"mission": title, "kind": kind, "prisoners": _aboard, "reason": reason, "score": 1000 if success else 0})
