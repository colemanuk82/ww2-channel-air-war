class_name AirborneMode
extends ModeBase
## D-Day airborne operations in a C-47 (see AirborneCampaign).
##   para  hold FIRE over the drop zone, low and slow: a stick of paratroopers leaves the door one man at a time,
##         opens its canopies and drifts down. Other C-47s of the serial drop their sticks over the zone as well.
##   tow   a glider rides behind you on a visible tow rope in a formation of tugs and gliders. Press FIRE in reach
##         of the landing zone to cast off: the rope falls away and the glider glides in and lands.

const DZ_WINDOW: float = 1.25          # the green light shows this far outside the zone's edge (times its radii)
const MAX_DROP_SPEED: float = 64.0     # m/s, about 125 mph
const MAX_DROP_AGL_M: float = 320.0    # real metres: about 1,000 ft
const EXIT_EVERY: float = 0.32         # seconds between men leaving the door
const FALL_FREE: float = 1.4           # seconds before the canopy opens
const FORM_SPEED: float = 58.0         # the other tugs fly at this
const REACH_RATIO: float = 11.0        # glide ratio used for the "in reach" indicator, with a margin
const REACH_MARGIN: float = 0.82

var start_airborne: bool = true
var manages_respawn: bool = true

var kind: String = "para"
var zone_id: String = ""
var glider_type: String = "horsa"
var title: String = "Airborne"
var op_index: int = 0
var per_stick: int = 18
var sticks_total: int = 2
var land_radius: float = 400.0

var _zone: Vector3 = Vector3.ZERO
var _rx: float = 600.0
var _rz: float = 400.0
var _have_zone: bool = false
var _ended: bool = false
var _gate: Vector3 = Vector3.ZERO
var _spawned: Array = []
var _status_t: float = 0.0
var _msg_t: float = -10.0

# para
var _sticks_done: int = 0
var _stick_left: int = 0
var _exit_t: float = 0.0
var _men: Array = []                    # {"fig", "canopy", "pos", "vel", "t", "own", "state"}
var _out: int = 0
var _in_zone: int = 0
var _landed: int = 0
var _finish_t: float = -1.0

# tow
var _rig: TowRig
var _released: bool = false
var _land_msg: bool = false
var _reach_msg: bool = false
var _form: Array = []                   # {"node", "rig", "target", "released", "t"} other tugs and their gliders
var _wait_t: float = 0.0


func configure(cfg: Dictionary) -> void:
	kind = str(cfg.get("kind", "para"))
	zone_id = str(cfg.get("zone", "tonga_dz_n"))
	glider_type = str(cfg.get("glider", "horsa"))
	if glider_type == "":
		glider_type = "horsa"
	title = str(cfg.get("title", title))
	op_index = int(cfg.get("op", 0))
	per_stick = clampi(int(cfg.get("men", 18)), 4, 24)
	sticks_total = clampi(int(cfg.get("sticks", 2)), 1, 4)
	land_radius = float(cfg.get("radius", 400.0))
	if cfg.has("era_date"):
		GameState.era_date = str(cfg["era_date"])
	TimeOfDay.set_preset(str(cfg.get("time", "night")))
	WeatherManager.set_weather(str(cfg.get("weather", "clear")), 0.1)


func start() -> void:
	super.start()
	elapsed = 0.0
	var row: Dictionary = AirborneCampaign.zone_row(zone_id)
	if not row.is_empty():
		_zone = WorldCoords.latlon_to_world(float(row["lat"]), float(row["lon"]))
		_zone.y = GroundKit.ground_y(_zone.x, _zone.z)
		_rx = float(row.get("rx", 600.0))
		_rz = float(row.get("rz", 400.0))
		_have_zone = true
	var pop: WorldPopulator = WorldPopulator.instance
	if pop != null and pop.has_method("pin_site"):
		pop.pin_site("lz_" + zone_id)
	var pl: Aircraft = player as Aircraft
	if pl != null:
		_gate = pl.global_position
		pl.set_meta("unarmed", true)
		pl.ammo = 0                     # FIRE is the door light / the tow release here, not a gun
		pl.destroyed.connect(_on_player_down)
	_build_defences()
	if kind == "tow":
		_build_tow_formation(pl)
		Radio.say("Glider pilot", "On tow and steady. Tell us when to cast off.", Radio.Kind.FRIENDLY, 2.0)
		Radio.say("Control", "Release in reach of the zone, not before. FIRE casts off the glider. Pull the camera back (numpad plus and minus) to see it on the rope.", Radio.Kind.CONTROL, 6.0)
	else:
		_build_para_formation(pl)
		Radio.say("Jumpmaster", "Stick of %d standing in the door. Low and slow, tell us when." % per_stick, Radio.Kind.FRIENDLY, 2.0)
		Radio.say("Control", "Over the zone, under 1,000 feet and 125 miles an hour. Hold FIRE for the green light.", Radio.Kind.CONTROL, 6.0)
	_update_status()


func stop() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_spawned.clear()
	if hud != null and hud.has_method("set_readout_extra"):
		hud.call("set_readout_extra", "")
	super.stop()


func nav_point() -> Variant:
	if not _have_zone:
		return null
	if kind == "tow" and _released:
		return _gate
	return _zone


func _own(n: Node) -> void:
	_spawned.append(n)


func _say(text: String, secs: float = 3.5) -> void:
	if hud != null and hud.has_method("show_message"):
		hud.call("show_message", text, secs)


func _ground_at(p: Vector3) -> Vector3:
	return Vector3(p.x, GroundKit.ground_y(p.x, p.z), p.z)


func _build_defences() -> void:
	if not _have_zone or world == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(zone_id)
	for i in 3:
		var a: float = TAU * (float(i) + rng.randf()) / 3.0
		var g: AAGun = AAGun.create("mg", "Axis")
		g.position = _ground_at(_zone + Vector3(cos(a) * _rx * 0.9, 0.0, sin(a) * _rz * 0.9))
		world.add_child(g)
		_own(g)
	var fl: AAGun = AAGun.create("bofors", "Axis") if kind == "para" else AAGun.create("mg", "Axis")
	fl.position = _ground_at(_zone + Vector3(rng.randf_range(-_rx, _rx) * 0.8, 0.0, rng.randf_range(-_rz, _rz) * 0.8))
	world.add_child(fl)
	_own(fl)


# ------------------------------------------------------------------ the rest of the serial

func _fwd_of(p: Vector3) -> Vector3:
	var d: Vector3 = _zone - p
	d.y = 0.0
	return d.normalized() if d.length() > 1.0 else Vector3.FORWARD


func _spawn_plane(pos: Vector3, fwd: Vector3) -> Node3D:
	var n := Node3D.new()
	var c47: Node3D = AircraftModels.build("c47", "USAAF")
	if c47 != null:
		n.add_child(c47)
	n.global_position = pos
	world.add_child(n)
	n.look_at(pos + fwd, Vector3.UP)
	_own(n)
	return n


## Other tugs flying with you, each with a glider on its own rope, each bound for a spot of the landing zone.
func _build_tow_formation(pl: Aircraft) -> void:
	if pl == null or not _have_zone or world == null:
		return
	var fwd: Vector3 = _fwd_of(pl.global_position)
	var right: Vector3 = fwd.cross(Vector3.UP)
	var slots: Array = [Vector3(-140.0, 10.0, 55.0), Vector3(150.0, 14.0, 110.0), Vector3(-290.0, 6.0, -20.0), Vector3(320.0, 20.0, 15.0)]
	_rig = TowRig.make(pl, glider_type, _zone)
	world.add_child(_rig)
	_own(_rig)
	for i in slots.size():
		var s: Vector3 = slots[i]
		var pos: Vector3 = pl.global_position + right * s.x + fwd * s.z + Vector3(0.0, s.y, 0.0)
		var tug: Node3D = _spawn_plane(pos, fwd)
		var tgt: Vector3 = _zone + Vector3(sin(float(i) * 2.1) * _rx * 0.5, 0.0, cos(float(i) * 2.1) * _rz * 0.5)
		var rig: TowRig = TowRig.make(tug, glider_type, tgt)
		world.add_child(rig)
		_own(rig)
		_form.append({"node": tug, "rig": rig, "fwd": fwd, "released": false, "t": 0.0, "turn": 0.0})


## Other C-47s of the serial drop on the zone as well, a stick each.
func _build_para_formation(pl: Aircraft) -> void:
	if pl == null or not _have_zone or world == null:
		return
	var fwd: Vector3 = _fwd_of(pl.global_position)
	var right: Vector3 = fwd.cross(Vector3.UP)
	var slots: Array = [Vector3(-120.0, 8.0, 35.0), Vector3(130.0, 12.0, 85.0), Vector3(-260.0, 5.0, -40.0)]
	for i in slots.size():
		var s: Vector3 = slots[i]
		var pos: Vector3 = pl.global_position + right * s.x + fwd * s.z + Vector3(0.0, s.y, 0.0)
		var tug: Node3D = _spawn_plane(pos, fwd)
		_form.append({"node": tug, "rig": null, "fwd": fwd, "released": false, "t": 0.0, "turn": 0.0, "stick": 0, "exit": 0.0})


func _tick_formation(delta: float) -> void:
	for f in _form:
		var fd: Dictionary = f
		var n: Node3D = fd["node"]
		if not is_instance_valid(n):
			continue
		var fwd: Vector3 = fd["fwd"]
		if bool(fd["released"]) or int(fd.get("stick", 0)) < 0:
			# after the drop or cast-off the aircraft turns away to port and keeps going
			fd["t"] = float(fd["t"]) + delta
			var ang: float = deg_to_rad(16.0) * delta * minf(float(fd["t"]) * 0.5, 1.0)
			fwd = fwd.rotated(Vector3.UP, ang)
			fd["fwd"] = fwd
			n.global_position += fwd * FORM_SPEED * delta + Vector3(0.0, -2.0 * delta, 0.0)
		else:
			n.global_position += fwd * FORM_SPEED * delta
		n.look_at(n.global_position + fwd, Vector3.UP)
		var d: float = Vector2(n.global_position.x - _zone.x, n.global_position.z - _zone.z).length()
		if kind == "tow":
			var rig: TowRig = fd["rig"]
			if not bool(fd["released"]):
				var agl_m: float = (n.global_position.y - GroundKit.ground_y(n.global_position.x, n.global_position.z)) / WorldCoords.VERTICAL_SCALE
				if d <= agl_m * REACH_RATIO * 0.62:
					fd["released"] = true
					rig.release()
		else:
			var st: int = int(fd.get("stick", 0))
			if st == 0 and d < _rx * 0.5:
				fd["stick"] = 1
				fd["exit"] = 0.0
				fd["left"] = 12
			elif st == 1:
				fd["exit"] = float(fd["exit"]) - delta
				if float(fd["exit"]) <= 0.0:
					fd["exit"] = EXIT_EVERY
					fd["left"] = int(fd["left"]) - 1
					_add_man(n.global_position + Vector3(0.0, -1.5, 0.0), fwd * FORM_SPEED * 0.5, false)
					if int(fd["left"]) <= 0:
						fd["stick"] = -1


# ------------------------------------------------------------------ paratroopers

func _add_man(pos: Vector3, vel: Vector3, own: bool) -> void:
	if world == null:
		return
	var fig: MeshInstance3D = CrewFigure.make("Allies", CrewFigure.Pose.STAND, 2)
	fig.position = pos
	world.add_child(fig)
	var canopy := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 4.2
	sm.height = 4.6
	sm.radial_segments = 12
	sm.rings = 5
	canopy.mesh = sm
	canopy.material_override = _canopy_mat()
	canopy.position = Vector3(0.0, 6.5, 0.0)
	canopy.scale = Vector3(1.0, 0.0, 1.0)
	canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fig.add_child(canopy)
	_men.append({"fig": fig, "canopy": canopy, "pos": pos, "vel": vel, "t": 0.0, "own": own, "state": "fall", "phase": randf() * TAU})
	_own(fig)
	if own:
		_out += 1


static var _cmat: StandardMaterial3D = null


static func _canopy_mat() -> StandardMaterial3D:
	if _cmat == null:
		_cmat = StandardMaterial3D.new()
		_cmat.albedo_color = Color(0.74, 0.72, 0.60)
		_cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _cmat


func _tick_men(delta: float) -> void:
	for m in _men:
		var md: Dictionary = m
		if md["state"] == "landed":
			continue
		var t: float = float(md["t"]) + delta
		md["t"] = t
		var v: Vector3 = md["vel"]
		var canopy: MeshInstance3D = md["canopy"]
		var open: float = clampf((t - FALL_FREE) / 0.7, 0.0, 1.0)
		if t < FALL_FREE:
			v.y -= 22.0 * delta
			v.x = lerpf(v.x, 0.0, 1.0 - exp(-0.6 * delta))
			v.z = lerpf(v.z, 0.0, 1.0 - exp(-0.6 * delta))
		else:
			v.y = lerpf(v.y, -10.0, 1.0 - exp(-2.2 * delta))                 # about 5 m/s real under a canopy
			var wind := Vector3(3.0, 0.0, 1.0)
			v.x = lerpf(v.x, wind.x, 1.0 - exp(-1.2 * delta))
			v.z = lerpf(v.z, wind.z, 1.0 - exp(-1.2 * delta))
		md["vel"] = v
		var p: Vector3 = md["pos"] + v * delta
		var gy: float = GroundKit.ground_y(p.x, p.z)
		var fig: MeshInstance3D = md["fig"]
		canopy.scale = Vector3(1.0, 0.55 * open, 1.0)
		if p.y <= gy + 0.2:
			p.y = gy
			md["state"] = "landed"
			canopy.visible = false
			fig.mesh = CrewFigure.mesh("Allies", CrewFigure.Pose.KNEEL, 2)
			if bool(md["own"]):
				_landed += 1
				var dx: float = (p.x - _zone.x) / _rx
				var dz: float = (p.z - _zone.z) / _rz
				if dx * dx + dz * dz <= 1.0:
					_in_zone += 1
					add_score(40)
		md["pos"] = p
		fig.position = p
		fig.rotation.z = sin(t * 1.3 + float(md["phase"])) * 0.12 * open


func _in_window(pl: Aircraft) -> bool:
	var dx: float = (pl.global_position.x - _zone.x) / (_rx * DZ_WINDOW)
	var dz: float = (pl.global_position.z - _zone.z) / (_rz * DZ_WINDOW)
	return dx * dx + dz * dz <= 1.0


func _agl_m(pl: Aircraft) -> float:
	return pl.altitude_agl / WorldCoords.VERTICAL_SCALE


func _drop_ok(pl: Aircraft) -> bool:
	return _in_window(pl) and _agl_m(pl) <= MAX_DROP_AGL_M and pl.speed <= MAX_DROP_SPEED and not pl.on_ground


func _tick_para(pl: Aircraft, delta: float) -> void:
	if _stick_left <= 0:
		if Input.is_action_just_pressed("fire") and _sticks_done < sticks_total:
			if _drop_ok(pl):
				_stick_left = per_stick
				_exit_t = 0.0
				_sticks_done += 1
				Radio.say("Jumpmaster", "Green light. Go, go, go!", Radio.Kind.FRIENDLY, 0.0)
			elif elapsed - _msg_t > 2.5:
				_msg_t = elapsed
				if not _in_window(pl):
					_say("NOT OVER THE DROP ZONE", 2.5)
				elif _agl_m(pl) > MAX_DROP_AGL_M:
					_say("TOO HIGH: %d ft, drop at 1,000 ft or below" % int(_agl_m(pl) * 3.28), 3.0)
				else:
					_say("TOO FAST: %d mph, drop under 125" % int(pl.speed * 2.237), 3.0)
	else:
		_exit_t -= delta
		if _exit_t <= 0.0:
			_exit_t = EXIT_EVERY
			_stick_left -= 1
			var fwd: Vector3 = -pl.global_transform.basis.z
			_add_man(pl.global_position + pl.global_transform.basis.y * -1.2 + pl.global_transform.basis.x * randf_range(-0.6, 0.6), fwd * pl.speed * 0.55, true)
			if _stick_left <= 0 and _sticks_done >= sticks_total:
				_say("ALL AWAY", 3.0)
				Radio.say("Jumpmaster", "Last man out. Stick away.", Radio.Kind.FRIENDLY, 0.5)
	if _out >= per_stick * sticks_total and _stick_left <= 0 and _landed >= _out and _finish_t < 0.0:
		_finish_t = 3.0
	if _finish_t >= 0.0:
		_finish_t -= delta
		if _finish_t <= 0.0:
			var ok: bool = float(_in_zone) >= float(_out) * 0.6
			_end(ok, "dropped" if ok else "scattered")


# ------------------------------------------------------------------ gliders

func _reach_m(pl: Aircraft) -> float:
	return _agl_m(pl) * REACH_RATIO * REACH_MARGIN


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _tick_tow(pl: Aircraft, delta: float) -> void:
	var d: float = _flat_dist(pl.global_position, _zone)
	if not _released:
		var inr: bool = d <= _reach_m(pl)
		if inr and not _reach_msg:
			_reach_msg = true
			_say("LANDING ZONE IN REACH: FIRE to cast off", 4.0)
			Radio.say("Glider pilot", "We have it in sight. Ready to cast off.", Radio.Kind.FRIENDLY, 0.5)
		if not inr:
			_reach_msg = false
		if Input.is_action_just_pressed("fire") and _rig != null:
			_released = true
			_rig.release()
			add_score(200)
			if inr:
				_say("CAST OFF. The glider is on its own.", 4.0)
				Radio.say("Glider pilot", "Cast off. Tow rope gone. Good luck, tug.", Radio.Kind.FRIENDLY, 0.5)
			else:
				_say("CAST OFF: too far out, it will not make the zone", 4.0)
				Radio.say("Glider pilot", "Too far out! We will not get there.", Radio.Kind.FRIENDLY, 0.5)
	elif _rig != null and _rig.is_stopped():
		_wait_t += delta
		if _wait_t > 2.5:
			var gd: float = _flat_dist(_rig.landed_pos, _zone)
			var ok: bool = _rig.state == "landed" and gd <= land_radius
			_end(ok, "landed" if ok else ("short" if _rig.state == "landed" else "lost"))
	elif _rig != null and _rig.state == "slide" and not _land_msg:
		_land_msg = true
		_say("THE GLIDER IS DOWN", 3.0)
	if _rig != null and _rig.state == "lost" and not _ended:
		_end(false, "lost")


func _process(delta: float) -> void:
	super._process(delta)
	if not running or _ended or not (player is Aircraft) or not _have_zone:
		return
	var pl: Aircraft = player as Aircraft
	_tick_formation(delta)
	_tick_men(delta)
	if kind == "tow":
		_tick_tow(pl, delta)
	else:
		_tick_para(pl, delta)
	_status_t += delta
	if _status_t >= 0.4:
		_status_t = 0.0
		_update_status()


func _update_status() -> void:
	if hud == null or not hud.has_method("set_readout_extra") or not _have_zone:
		return
	var pl: Aircraft = player as Aircraft
	if pl == null:
		return
	var d: float = _flat_dist(pl.global_position, _zone)
	if kind == "para":
		var light: String = "GREEN LIGHT: hold FIRE" if _drop_ok(pl) and _stick_left <= 0 and _sticks_done < sticks_total else "no light"
		hud.call("set_readout_extra", "%s   OUT %d/%d   IN ZONE %d\n%d ft  %d mph  zone %.1f km" % [light, _out, per_stick * sticks_total, _in_zone, int(_agl_m(pl) * 3.28), int(pl.speed * 2.237), d / 1000.0])
	else:
		var s: String
		if _released:
			s = "Glider: %s" % ("down" if _rig != null and _rig.is_stopped() else "gliding")
		else:
			s = "IN REACH: FIRE to cast off" if d <= _reach_m(pl) else "Out of reach: close on the zone"
		hud.call("set_readout_extra", "%s\n%d ft  zone %.1f km  reach %.1f km" % [s, int(_agl_m(pl) * 3.28), d / 1000.0, _reach_m(pl) / 1000.0])


func _stats() -> Dictionary:
	return {"men": _out, "in_zone": _in_zone}


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
		"dropped":
			msg = "%d of %d men landed on the zone." % [_in_zone, _out]
		"scattered":
			msg = "Scattered: only %d of %d men landed on the zone." % [_in_zone, _out]
		"landed":
			msg = "The glider landed on the zone."
		"short":
			msg = "The glider landed short of the zone."
		"lost":
			msg = "The glider was lost."
		"shot_down":
			msg = "Aircraft lost."
	_say(msg, 5.0)
	finish(success, {"mission": title, "kind": kind, "men": _out, "in_zone": _in_zone, "reason": reason, "score": 1000 if success else 0})
