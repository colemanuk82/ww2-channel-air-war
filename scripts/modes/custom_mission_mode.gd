class_name CustomMissionMode
extends ModeBase
## Plays a mission made in the Mission Editor (see MissionDoc for the file format).
## main.gd passes the whole document as cfg["custom_doc"]. The mode spawns the units that start active, keeps the
## objectives (some complete or fail by themselves: destroy / protect / reach / land / survive), and runs the triggers
## four times a second: when a trigger's conditions hold it waits its delay and runs its actions (messages, radio calls,
## bringing in units, setting objectives and flags, ending the mission...). The mission succeeds once every required
## objective is done, fails when one fails, or ends when an "End the mission" action says so.

var start_airborne: bool = true

var doc: Dictionary = {}
var side: String = "Allies"
var difficulty: float = 0.5

var _populator: WorldPopulator
var _units: Dictionary = {}       # id -> {def, members: Array, dead: Dictionary(instance id -> true), spawned, formation, wp}
var _zones: Dictionary = {}       # id -> {pos: Vector3, r: float (world units), name}
var _objs: Array = []             # [{def, state: "inactive" | "active" | "complete" | "failed"}] in file order
var _flags: Dictionary = {}
var _trig: Array = []             # [{def, fired: int, was_true: bool, chance: {}}]
var _queue: Array = []            # [{t: due time, actions: Array}]
var _nav: Variant = null          # zone id the compass points at (set by an action)
var _label: Label
var _tick: float = 0.0
var _ending: bool = false


func configure(cfg: Dictionary) -> void:
	doc = MissionDoc.upgrade((cfg.get("custom_doc", {}) as Dictionary).duplicate(true))
	side = str(doc.get("side", cfg.get("side", "Allies")))
	difficulty = float(doc.get("difficulty", cfg.get("difficulty", 0.5)))
	var st: Dictionary = doc.get("start", {})
	start_airborne = bool(st.get("airborne", true)) or str(st.get("airfield", "")) == ""


func start() -> void:
	super.start()
	_populator = WorldPopulator.ensure(world)
	_init_state()
	for uid in _units.keys():
		if bool((_units[uid]["def"] as Dictionary).get("active", true)):
			_spawn_unit(uid)
	_build_label()
	_refresh_label()
	if hud and hud.has_method("show_message"):
		hud.call("show_message", str(doc.get("name", "Mission")), 4.0)
	var spawned: int = 0
	for uid2 in _units.keys():
		spawned += (_units[uid2]["members"] as Array).size()
	_log("start '%s': %d units (%d in the world), %d objectives, %d triggers" % [doc.get("name", ""), _units.size(), spawned, _objs.size(), _trig.size()])


## Zones, units (not spawned yet), objectives and triggers from the document.
func _init_state() -> void:
	_zones.clear()
	_units.clear()
	_objs.clear()
	_trig.clear()
	for z in doc.get("zones", []):
		var p: Vector3 = WorldCoords.latlon_to_world(float(z["lat"]), float(z["lon"]))
		_zones[str(z["id"])] = {"pos": p, "r": float(z.get("radius", 2.0)) * 1000.0 / WorldCoords.HORIZ_COMPRESSION, "name": str(z.get("name", z["id"]))}
	for u in doc.get("units", []):
		_units[str(u["id"])] = {"def": u, "members": [], "dead": {}, "spawned": false, "formation": null, "wp": 0}
	for o in doc.get("objectives", []):
		_objs.append({"def": o, "state": "active" if bool(o.get("shown", true)) else "inactive"})
	for t in doc.get("triggers", []):
		_trig.append({"def": t, "fired": 0, "was_true": false, "chance": {}})


## Mission events in the log (debug builds): what spawned, which triggers fired, objective changes, the end.
func _log(text: String) -> void:
	if OS.is_debug_build():
		print("[custom] t=%.0f  %s" % [elapsed, text])


# ================================================================== spawning
func _ground_pos(lat: float, lon: float, want_water: bool) -> Vector3:
	var p: Vector3 = WorldCoords.latlon_to_world(lat, lon)
	return _snap(p, want_water)


## Move a point onto land (vehicles, buildings, guns) or water (ships) when it was placed a little off: searches
## outward in rings up to ~4 km, and gives up (keeps the point) if nothing fits.
func _snap(p: Vector3, want_water: bool) -> Vector3:
	if (GroundKit.raw_y(p.x, p.z) < 0.6) == want_water:
		return p
	for ring in range(1, 21):
		var r: float = float(ring) * 200.0
		for k in 16:
			var a: float = TAU * float(k) / 16.0
			var q: Vector3 = p + Vector3(cos(a), 0.0, sin(a)) * r
			if (GroundKit.raw_y(q.x, q.z) < 0.6) == want_water:
				return q
	return p


func _route_world(u: Dictionary, want_water: bool, y: float = -1.0) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for ll in u.get("route", []):
		var q: Vector3 = WorldCoords.latlon_to_world(float(ll[0]), float(ll[1]))
		if y < 0.0:
			q = _snap(q, want_water)
		else:
			q.y = y
		out.append(q)
	return out


func _spawn_unit(uid: String) -> void:
	var rec: Dictionary = _units.get(uid, {})
	if rec.is_empty() or bool(rec["spawned"]):
		return
	rec["spawned"] = true
	var u: Dictionary = rec["def"]
	var kind: String = str(u.get("kind", "flight"))
	var team: String = str(u.get("side", "Axis"))
	var count: int = clampi(int(u.get("count", 1)), 1, int((MissionDoc.UNIT_KINDS.get(kind, {}) as Dictionary).get("max", 12)))
	var skill: float = float(u.get("skill", difficulty))
	var lat: float = float(u.get("lat", 51.0))
	var lon: float = float(u.get("lon", 1.0))
	var typ: String = str(u.get("type", ""))
	var beh: String = str(u.get("behavior", "hold"))
	var hdg: float = float(u.get("heading", 0.0))
	var members: Array = []
	match kind:
		"flight":
			var p: Vector3 = WorldCoords.latlon_to_world(lat, lon)
			var alt_y: float = maxf(GroundKit.ground_y(p.x, p.z), 0.0) + float(u.get("alt", 2500.0)) * WorldCoords.VERTICAL_SCALE
			p.y = alt_y
			var route: Array[Vector3] = _route_world(u, false, alt_y)
			if not route.is_empty():
				hdg = WorldCoords.dir_to_heading(route[0] - p)
			if AircraftCatalog.is_bomber(typ) and beh == "route" and not route.is_empty():
				# the editor's count is the count: no random big raid, no size multiplier
				var keep: float = BomberFormation.big_raid_chance
				var keep_mult: float = BomberFormation.size_mult
				BomberFormation.big_raid_chance = 0.0
				BomberFormation.size_mult = 1.0
				var f: BomberFormation = BomberFormation.spawn(world, typ, team, count, p, hdg, route, skill)
				BomberFormation.big_raid_chance = keep
				BomberFormation.size_mult = keep_mult
				rec["formation"] = f
				members = f.members.duplicate()
			else:
				var dir: Vector3 = WorldCoords.heading_to_dir(hdg)
				var right := Vector3(-dir.z, 0.0, dir.x)
				for i in count:
					var off: Vector3 = right * (float(i % 4) - 1.5) * 120.0 - dir * float(i / 4) * 160.0
					var ac: Aircraft = AIFactory.spawn(world, typ, team, p + off, hdg, -1.0, skill)
					var pilot: AIPilot = AIFactory.pilot_of(ac)
					if pilot != null:
						pilot.patrol_center = route[0] if (beh == "route" and not route.is_empty()) else p
						if beh == "hunt":
							pilot.detect_range = 60000.0
					members.append(ac)
					ac.crashed.connect(func(a: Aircraft, _r: String) -> void: _free_later(a, 3.0))
			for m in members:
				AIFactory.add_marker(hud, m, Color(0.45, 0.85, 1.0) if team == side else Color(1.0, 0.3, 0.2))
		"vehicles":
			var route2: Array[Vector3] = _route_world(u, false)
			var base: Vector3 = _ground_pos(lat, lon, false)
			if beh == "move" and not route2.is_empty():
				var pts := PackedVector3Array([base])
				for q in route2:
					pts.append(q)
				var rp: RoutePath = RoutePath.from_points(pts)
				for i in count:
					var v: GroundVehicle = GroundVehicle.create(typ, team, rp, float(count - 1 - i) * 30.0, 7.0, "move")
					world.add_child(v)
					members.append(v)
			else:
				var dir2: Vector3 = WorldCoords.heading_to_dir(hdg)
				for i in count:
					var v2: GroundVehicle = GroundVehicle.create(typ, team, null, 0.0, 0.0, "idle")
					v2.position = _snap(base - dir2 * float(i) * 28.0, false)
					v2.rotation.y = -deg_to_rad(hdg)
					world.add_child(v2)
					members.append(v2)
		"ships":
			var base3: Vector3 = _ground_pos(lat, lon, true)
			var route3: Array[Vector3] = _route_world(u, true)
			var fwd3: Vector3 = WorldCoords.heading_to_dir(hdg)
			if beh == "move" and not route3.is_empty():
				var pts3 := PackedVector3Array([base3])
				for q3 in route3:
					pts3.append(q3)
				var rp3: RoutePath = RoutePath.from_points(pts3)
				# sailing in company: columns a few hundred metres apart, the odd column staggered half a station
				var small3: bool = typ in ["fishing_boat", "landing_craft", "trawler"]
				var station3: float = 150.0 if small3 else 260.0
				var gap3: float = 170.0 if small3 else 300.0
				var cols3: int = 1 if count <= 2 else (2 if count <= 6 else 3)
				var rows3: int = int(ceil(float(count) / float(cols3)))
				for i in count:
					var col3: int = i % cols3
					var row3: int = i / cols3
					var along3: float = float(rows3 - 1 - row3) * station3 - (station3 * 0.5 if col3 % 2 == 1 else 0.0) + randf_range(-0.12, 0.12) * station3
					var sh: GroundShip = GroundShip.create(typ, team, rp3, maxf(along3 + station3 * 0.5, 0.0))
					sh.lateral = (float(col3) - float(cols3 - 1) * 0.5) * gap3 + randf_range(-0.1, 0.1) * gap3
					sh.wander = 14.0 if small3 else 22.0
					sh.wander_phase = randf() * TAU
					world.add_child(sh)
					members.append(sh)
			else:
				# anchored: each ship on its own short line, barely moving
				var side3 := Vector3(-fwd3.z, 0.0, fwd3.x)
				for i in count:
					var at: Vector3 = _snap(base3 + side3 * float(i) * 110.0, true)
					var sh2: GroundShip = GroundShip.create(typ, team, RoutePath.from_points(PackedVector3Array([at, at + fwd3 * 60.0])), 0.0, 0.01)
					world.add_child(sh2)
					members.append(sh2)
		"structure":
			var base4: Vector3 = _ground_pos(lat, lon, false)
			var dir4: Vector3 = WorldCoords.heading_to_dir(hdg + 90.0)
			for i in count:
				var g: GroundStructure = GroundStructure.create(typ, team, _snap(base4 + dir4 * float(i) * 180.0, false), hdg if hdg > 0.0 else -1.0)
				g.is_mission_target = true
				world.add_child(g)
				members.append(g)
		"flak":
			var base5: Vector3 = _ground_pos(lat, lon, false)
			for i in count:
				var gun: AAGun = AAGun.create(typ, team)
				var a: float = TAU * float(i) / float(count)
				var gp: Vector3 = _snap(base5 + (Vector3(cos(a), 0.0, sin(a)) * 70.0 if count > 1 else Vector3.ZERO), false)
				gun.position = Vector3(gp.x, GroundKit.ground_y(gp.x, gp.z), gp.z)
				world.add_child(gun)
				members.append(gun)
		"world":
			var node: Node = _populator.spawn_target(typ) if _populator != null else null
			if node != null:
				members.append(node)
	rec["members"] = members
	_log("unit %s in: %d x %s %s" % [uid, members.size(), typ, kind])
	for m2 in members:
		if m2 != null and m2.has_signal("destroyed"):
			m2.connect("destroyed", _on_member_destroyed.bind(uid))


func _on_member_destroyed(node: Node, _killer: Node, uid: String) -> void:
	var rec: Dictionary = _units.get(uid, {})
	if not rec.is_empty():
		(rec["dead"] as Dictionary)[node.get_instance_id()] = true


func _free_later(a: Aircraft, t: float) -> void:
	if not is_instance_valid(a):
		return
	await a.get_tree().create_timer(t).timeout
	if is_instance_valid(a):
		a.queue_free()


## Members of a unit still in the fight.
func _alive(uid: String) -> Array:
	var out: Array = []
	var rec: Dictionary = _units.get(uid, {})
	if rec.is_empty():
		return out
	for m in rec["members"]:
		if m == null or not is_instance_valid(m) or (rec["dead"] as Dictionary).has(m.get_instance_id()):
			continue
		if m is Aircraft and (m as Aircraft).state != Aircraft.State.ALIVE:
			continue
		if m is GroundTarget and (m as GroundTarget).is_dead:
			continue
		out.append(m)
	return out


func _losses(uid: String) -> int:
	var rec: Dictionary = _units.get(uid, {})
	if rec.is_empty() or not bool(rec["spawned"]):
		return 0
	return (rec["members"] as Array).size() - _alive(uid).size()


func _destroyed(uid: String) -> bool:
	var rec: Dictionary = _units.get(uid, {})
	return not rec.is_empty() and bool(rec["spawned"]) and _alive(uid).is_empty()


# ================================================================== the loop
func _process(delta: float) -> void:
	super._process(delta)
	if not running:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.25
	_steer_flights()
	_update_objectives()
	_run_triggers()
	_run_queue()
	_check_end()


## Fighters set to "route" move their patrol point along the route; "hunt" fighters always patrol round the player.
func _steer_flights() -> void:
	var pl: Node3D = player as Node3D
	for uid in _units.keys():
		var rec: Dictionary = _units[uid]
		if not bool(rec["spawned"]) or rec["formation"] != null:
			continue
		var u: Dictionary = rec["def"]
		if str(u.get("kind", "")) != "flight":
			continue
		var beh: String = str(u.get("behavior", "patrol"))
		var alive: Array = _alive(uid)
		if alive.is_empty():
			continue
		if beh == "hunt" and pl != null and is_instance_valid(pl):
			for m in alive:
				var p: AIPilot = AIFactory.pilot_of(m)
				if p != null:
					p.patrol_center = pl.global_position
					p.detect_range = 60000.0
		elif beh == "route":
			var route: Array = u.get("route", [])
			if route.is_empty():
				continue
			var wp: int = int(rec["wp"])
			var lead: Node3D = alive[0]
			var ll: Array = route[mini(wp, route.size() - 1)]
			var tgt: Vector3 = WorldCoords.latlon_to_world(float(ll[0]), float(ll[1]))
			if Vector2(lead.global_position.x - tgt.x, lead.global_position.z - tgt.z).length() < 1500.0 and wp < route.size() - 1:
				rec["wp"] = wp + 1
				ll = route[wp + 1]
				tgt = WorldCoords.latlon_to_world(float(ll[0]), float(ll[1]))
			for m2 in alive:
				var p2: AIPilot = AIFactory.pilot_of(m2)
				if p2 != null:
					p2.patrol_center = Vector3(tgt.x, m2.global_position.y, tgt.z)


func _player_ok() -> bool:
	return player != null and is_instance_valid(player)


func _in_zone(p: Vector3, zid: String) -> bool:
	var z: Dictionary = _zones.get(zid, {})
	if z.is_empty():
		return false
	return Vector2(p.x - (z["pos"] as Vector3).x, p.z - (z["pos"] as Vector3).z).length() <= float(z["r"])


func _landed() -> bool:
	var pl: Aircraft = (player as Aircraft) if is_instance_valid(player) else null
	return pl != null and is_instance_valid(pl) and pl.on_ground and pl.speed < 8.0 and pl.state == Aircraft.State.ALIVE


func _update_objectives() -> void:
	var changed: bool = false
	for o in _objs:
		if o["state"] != "active":
			continue
		var d: Dictionary = o["def"]
		var tgt: String = str(d.get("target", ""))
		var ns: String = ""
		match str(d.get("kind", "manual")):
			"destroy":
				if _destroyed(tgt):
					ns = "complete"
			"protect":
				if _destroyed(tgt):
					ns = "failed"
			"reach":
				if _player_ok() and _in_zone((player as Node3D).global_position, tgt):
					ns = "complete"
			"land":
				if _landed() and (tgt == "" or _in_zone((player as Node3D).global_position, tgt)):
					ns = "complete"
			"survive":
				if tgt.is_valid_float() and elapsed >= float(tgt):
					ns = "complete"
		if ns != "":
			_set_objective(o, ns)
			changed = true
	if changed:
		_refresh_label()


func _set_objective(o: Dictionary, state: String) -> void:
	if o["state"] == state:
		return
	var was: String = o["state"]
	o["state"] = state
	_log("objective '%s': %s -> %s" % [str((o["def"] as Dictionary).get("text", "")), was, state])
	var text: String = str((o["def"] as Dictionary).get("text", "Objective"))
	if hud and hud.has_method("show_message"):
		match state:
			"complete":
				hud.call("show_message", "Objective complete: " + text, 3.5)
				add_score(250)
			"failed":
				hud.call("show_message", "Objective failed: " + text, 3.5)
			"active":
				if was == "inactive":
					hud.call("show_message", "New objective: " + text, 3.5)
	_refresh_label()


func _obj(id: String) -> Dictionary:
	for o in _objs:
		if str((o["def"] as Dictionary).get("id", "")) == id:
			return o
	return {}


func _cond(c: Dictionary, tr: Dictionary) -> bool:
	var pl: Aircraft = (player as Aircraft) if is_instance_valid(player) else null
	match str(c.get("type", "")):
		"time":
			return elapsed >= float(c.get("seconds", 0.0))
		"unit_destroyed":
			return _destroyed(str(c.get("unit", "")))
		"unit_losses":
			return _losses(str(c.get("unit", ""))) >= int(c.get("count", 1))
		"unit_in_zone":
			for m in _alive(str(c.get("unit", ""))):
				if _in_zone((m as Node3D).global_position, str(c.get("zone", ""))):
					return true
			return false
		"player_in_zone":
			return _player_ok() and _in_zone(pl.global_position, str(c.get("zone", "")))
		"player_alt_above":
			return _player_ok() and pl.global_position.y / WorldCoords.VERTICAL_SCALE > float(c.get("metres", 0.0))
		"player_alt_below":
			return _player_ok() and pl.global_position.y / WorldCoords.VERTICAL_SCALE < float(c.get("metres", 0.0))
		"player_landed":
			return _landed()
		"player_health_below":
			return _player_ok() and pl.health / maxf(pl.stats.max_health, 1.0) * 100.0 < float(c.get("percent", 50.0))
		"player_kills":
			return _kill_total() >= int(c.get("count", 1))
		"objective":
			var o: Dictionary = _obj(str(c.get("objective", "")))
			return not o.is_empty() and str(o["state"]) == str(c.get("state", "complete"))
		"flag":
			return bool(_flags.get(str(c.get("flag", "")), false)) == bool(c.get("value", true))
		"trigger_fired":
			for t in _trig:
				if str((t["def"] as Dictionary).get("id", "")) == str(c.get("trigger", "")):
					return int(t["fired"]) > 0
			return false
		"chance":
			# rolled once per trigger, so the trigger does not fire just because it is checked many times
			var key: String = str(c.hash())
			if not (tr["chance"] as Dictionary).has(key):
				tr["chance"][key] = randf() * 100.0 < float(c.get("percent", 50.0))
			return bool(tr["chance"][key])
	return false


func _run_triggers() -> void:
	for tr in _trig:
		var d: Dictionary = tr["def"]
		var once: bool = bool(d.get("once", true))
		if once and int(tr["fired"]) > 0:
			continue
		var conds: Array = d.get("conditions", [])
		var ok: bool = true
		if not conds.is_empty():
			var any: bool = str(d.get("logic", "all")) == "any"
			ok = not any
			for c in conds:
				var r: bool = _cond(c, tr)
				if any and r:
					ok = true
					break
				if not any and not r:
					ok = false
					break
		var rising: bool = ok and not bool(tr["was_true"])
		tr["was_true"] = ok
		if not rising:
			continue
		tr["fired"] = int(tr["fired"]) + 1
		_log("trigger '%s' fired" % str(d.get("name", d.get("id", ""))))
		_queue.append({"t": elapsed + maxf(float(d.get("delay", 0.0)), 0.0), "actions": d.get("actions", [])})


func _run_queue() -> void:
	var i: int = 0
	while i < _queue.size():
		var q: Dictionary = _queue[i]
		if elapsed >= float(q["t"]):
			_queue.remove_at(i)
			for a in q["actions"]:
				_act(a)
				if not running:
					return
		else:
			i += 1


func _act(a: Dictionary) -> void:
	match str(a.get("type", "")):
		"message":
			if hud and hud.has_method("show_message"):
				hud.call("show_message", str(a.get("text", "")), float(a.get("seconds", 5.0)))
		"radio":
			Radio.say(str(a.get("speaker", "Control")), str(a.get("text", "")), Radio.Kind.CONTROL if str(a.get("from", "control")) == "control" else Radio.Kind.FRIENDLY)
		"activate":
			_spawn_unit(str(a.get("unit", "")))
		"objective":
			var o: Dictionary = _obj(str(a.get("objective", "")))
			if not o.is_empty():
				_set_objective(o, str(a.get("state", "active")))
		"flag":
			_flags[str(a.get("flag", ""))] = bool(a.get("value", true))
		"hunt":
			var rec: Dictionary = _units.get(str(a.get("unit", "")), {})
			if not rec.is_empty():
				(rec["def"] as Dictionary)["behavior"] = "hunt"
				rec["formation"] = null
		"destroy":
			for m in _alive(str(a.get("unit", ""))):
				if m.has_method("take_damage"):
					m.call("take_damage", 1.0e6, null)
		"nav":
			_nav = str(a.get("zone", ""))
		"score":
			add_score(int(a.get("points", 0)))
		"end":
			_end(str(a.get("result", "success")) == "success", str(a.get("text", "")))


func _check_end() -> void:
	if _ending:
		return
	var required: int = 0
	var done: int = 0
	for o in _objs:
		var d: Dictionary = o["def"]
		if not bool(d.get("required", true)):
			continue
		if o["state"] == "failed":
			_end(false, "Objective failed: " + str(d.get("text", "")))
			return
		required += 1
		# a protect objective counts as done while what it protects is still afloat / standing
		if o["state"] == "complete" or (o["state"] == "active" and str(d.get("kind", "")) == "protect" and _units.has(str(d.get("target", "")))):
			done += 1
	var only_protect: bool = true
	for o2 in _objs:
		if bool((o2["def"] as Dictionary).get("required", true)) and str((o2["def"] as Dictionary).get("kind", "")) != "protect":
			only_protect = false
	if required > 0 and done == required and not only_protect:
		_end(true, "All objectives complete")


func _end(success: bool, text: String) -> void:
	if _ending or not running:
		return
	_ending = true
	_log("end: %s (%s)" % ["success" if success else "failure", text])
	if hud and hud.has_method("show_message"):
		hud.call("show_message", text if text != "" else ("Mission complete" if success else "Mission failed"), 3.0)
	var reason: String = text
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if running:
			finish(success, _stats(reason)))


func _stats(reason: String = "") -> Dictionary:
	var done: int = 0
	for o in _objs:
		if o["state"] == "complete":
			done += 1
	return {"reason": reason, "objectives_done": done, "objectives": _objs.size(), "mission": str(doc.get("name", ""))}


# ================================================================== HUD
func _build_label() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	if hud and hud.has_method("add_widget"):
		hud.call("add_widget", _label)


func _refresh_label() -> void:
	if _label == null:
		return
	var lines: PackedStringArray = [str(doc.get("name", "Mission")).to_upper()]
	for o in _objs:
		var st: String = o["state"]
		if st == "inactive":
			continue
		var tag: String = {"active": "", "complete": "   done", "failed": "   FAILED"}.get(st, "")
		lines.append(str((o["def"] as Dictionary).get("text", "Objective")) + tag)
	_label.text = "\n".join(lines)


func nav_point() -> Variant:
	if _nav != null and _zones.has(str(_nav)):
		return _zones[str(_nav)]["pos"]
	for o in _objs:
		if o["state"] != "active":
			continue
		var d: Dictionary = o["def"]
		var tgt: String = str(d.get("target", ""))
		match str(d.get("kind", "")):
			"destroy", "protect":
				var p: Variant = _nearest_pos(_alive(tgt))
				if p != null:
					return p
			"reach", "land":
				if _zones.has(tgt):
					return _zones[tgt]["pos"]
	return null

