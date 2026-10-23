class_name BombingMode
extends ModeBase
## Bombing run against real targets from data/locations.json (side_owner = the enemy of the player).
## Flow: fly to the objective (HUD distance + beacon), bomb it through flak and fighter interception, then
## return to base (RTB). Success = all objectives destroyed + RTB; fail = player destroyed (or time out).
## configure(cfg): side, difficulty (0..1), target / targets (ids), tuned from main.gd's start config.
## Direct use: BombingMode.create(["port_calais"], "Allies") then setup(world, player, hud), add_child, start().

var start_airborne: bool = true
var manages_respawn: bool = true

var side: String = "Allies"
var enemy_side: String = "Axis"
var difficulty: float = 0.5
var target_ids: Array = []
var targets: Array = []             # live nodes (GroundStructure / Convoy)
var target_names: Dictionary = {}
var phase: String = "ingress"       # ingress -> rtb -> done
var interceptor_waves: int = 2
var rtb_radius: float = 650.0
var teleport: bool = false          # debug: place the player near the target
var debug_auto: bool = false        # debug: destroy targets after a few seconds
var briefing: String = ""

var _populator: WorldPopulator
var _label: Label
var _beacon: MeshInstance3D
var _label_t: float = 0.0
var _home: Vector3 = Vector3.ZERO
var _have_home: bool = false
var _wave_t: float = 30.0
var _waves_spawned: int = 0
var _destroyed_count: int = 0
var _player_dead: bool = false
var _death_note: String = ""        # how the player was lost, shown on the results screen
var _near_msg: bool = false
var _debug_t: float = 5.0
var _kills: int = 0
var _enemy_fighters: Array = []
var _bda: Array = []                # bomb damage assessment: one entry per target {node, name, r, marks}


static func create(ids: Array, p_side: String = "Allies", p_difficulty: float = 0.5) -> BombingMode:
	var m := BombingMode.new()
	m.target_ids = ids.duplicate()
	m.side = p_side
	m.enemy_side = GroundKit.enemy_of(p_side)
	m.difficulty = p_difficulty
	return m


func configure(cfg: Dictionary) -> void:
	side = str(cfg.get("side", GameState.player_side))
	enemy_side = GroundKit.enemy_of(side)
	difficulty = float(cfg.get("difficulty", 0.5))
	if cfg.has("targets"):
		target_ids = (cfg["targets"] as Array).duplicate()
	elif cfg.has("target"):
		target_ids = [str(cfg["target"])]
	interceptor_waves = 1 if difficulty < 0.35 else (2 if difficulty < 0.7 else 3)
	if bool(cfg.get("no_fighters", false)):
		interceptor_waves = 0
	if world != null:
		_populator = WorldPopulator.ensure(world)
		_ensure_airfield()


## Make sure main's airfields dict can resolve the current start airfield (populator airfields) and that the
## default start airfield is on the player's side.
func _ensure_airfield() -> void:
	if _populator == null or world == null or not ("airfields" in world):
		return
	var afs: Dictionary = world.get("airfields")
	if not afs.has(GameState.start_airfield):
		var af: Airfield = _populator.get_airfield(GameState.start_airfield)
		if af != null:
			afs[GameState.start_airfield] = af


func _pick_targets() -> void:
	if not target_ids.is_empty():
		return
	var types: Array = ["port", "factory", "rail_yard", "bridge", "v1_site", "battery", "radar"]
	var pool: Array = _populator.targets_for_side(enemy_side, types)
	var home: Vector3 = _home if _have_home else Vector3.ZERO
	pool.sort_custom(func(a: String, b: String) -> bool:
		return (_populator.get_target_info(a)["pos"] as Vector3).distance_to(home) < (_populator.get_target_info(b)["pos"] as Vector3).distance_to(home))
	if pool.is_empty():
		return
	var first: String = pool[randi() % mini(pool.size(), 5)]
	target_ids = [first]
	var p0: Vector3 = _populator.get_target_info(first)["pos"]
	for id in pool:
		if id != first and (_populator.get_target_info(id)["pos"] as Vector3).distance_to(p0) < 1800.0 and target_ids.size() < 3:
			target_ids.append(id)


func start() -> void:
	# the player's bomber squadron + escort join once airborne. When this mode runs as the inner mode of a
	# historical mission, the parent mode already provides that, so only the top-level instance does it.
	bomber_support = not (get_parent() is ModeBase)
	super.start()
	teleport = teleport or GroundKit.has_arg("--wp-teleport")
	debug_auto = debug_auto or GroundKit.has_arg("--wp-auto")
	if _populator == null:
		_populator = WorldPopulator.ensure(world)
	_ensure_airfield()
	_find_home()
	_pick_targets()
	if target_ids.is_empty():
		push_warning("BombingMode: no targets available")
		finish(false, {"reason": "no targets"})
		return
	for id in target_ids:
		var info: Dictionary = _populator.get_target_info(id)
		target_names[id] = str(info.get("name", id))
		var n: Node = _populator.spawn_target(id)
		if n == null:
			continue
		targets.append(n)
		n.connect("destroyed", _on_target_destroyed.bind(id))
		var hr: Variant = n.get("hit_radius")
		_bda.append({"node": n, "name": str(target_names[id]), "r": float(hr) if hr != null else 30.0, "marks": []})
	print("BombingMode: targets=%s nodes=%d home=%s" % [str(target_ids), targets.size(), str(_home)])
	if not Weapons.player_bomb_impact.is_connected(_on_bomb_impact):
		Weapons.player_bomb_impact.connect(_on_bomb_impact)
	_make_beacon()
	_build_label()
	if player and is_instance_valid(player):
		var p: Aircraft = player as Aircraft
		p.destroyed.connect(_on_player_destroyed)
		p.crashed.connect(func(_a: Aircraft, r: String) -> void:
			_death_note = "killed - crashed (%s)" % r
			_on_player_destroyed(p, null))
		if p.bombs <= 0:
			p.bombs = 2
		if teleport:
			_teleport_near()
	_update_objective()
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "BOMBING RUN: %s" % _target_summary(), 4.0)
	if hud and hud.has_method("register_minimap_marker"):
		for t in targets:
			if t is GroundStructure:
				hud.call("register_minimap_marker", t, Color(1.0, 0.3, 0.2))
	_wave_t = 25.0


func stop() -> void:
	super.stop()
	if Weapons.player_bomb_impact.is_connected(_on_bomb_impact):
		Weapons.player_bomb_impact.disconnect(_on_bomb_impact)
	for n in [_label, _beacon]:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()


func _find_home() -> void:
	var id: String = GameState.start_airfield
	var af: Airfield = null
	if world != null and "airfields" in world:
		var afs: Dictionary = world.get("airfields")
		if afs.has(id):
			af = afs[id]
	if af == null and _populator != null:
		af = _populator.get_airfield(id)
	if af != null:
		_home = Vector3(af.position.x, af.surface_y, af.position.z)
		_have_home = true


func _target_summary() -> String:
	var names: Array = []
	for id in target_ids:
		names.append(str(target_names.get(id, id)))
	return ", ".join(names)


func _target_pos(n: Node) -> Vector3:
	if n is Convoy:
		return (n as Convoy).get_center()
	return (n as Node3D).global_position


func nav_point() -> Variant:
	var alive: Array = _alive_targets()
	if not alive.is_empty():
		return _nearest_pos(alive)
	return _home if _have_home else null     # all targets down: back to base


func _alive_targets() -> Array:
	var out: Array = []
	for t in targets:
		if is_instance_valid(t) and not bool(t.call("is_destroyed")):
			out.append(t)
	return out


func _nearest_target() -> Node:
	if player == null:
		return null
	var best: Node = null
	var bd: float = INF
	for t in _alive_targets():
		var d: float = _target_pos(t).distance_to(player.global_position)
		if d < bd:
			bd = d
			best = t
	return best


# ------------------------------------------------------------------ objective marker / HUD
func _make_beacon() -> void:
	_beacon = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 6.0
	cm.bottom_radius = 9.0
	cm.height = 1400.0
	cm.radial_segments = 8
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	_beacon.mesh = cm
	_beacon.material_override = GroundKit.glow_mat(Color(1.0, 0.35, 0.15), 0.28, true)
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_beacon)


func _build_label() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.82))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 4)
	if hud and hud.has_method("add_widget"):
		hud.call("add_widget", _label)


func _update_objective() -> void:
	match phase:
		"ingress":
			objective_updated.emit("Destroy: %s" % _target_summary())
		"rtb":
			objective_updated.emit("Return to base")


func _refresh_label() -> void:
	if _label == null or not is_instance_valid(_label) or player == null:
		return
	var txt: String = "BOMBING RUN  %s\n" % phase.to_upper()
	if phase == "ingress":
		var t: Node = _nearest_target()
		if t != null:
			var tp: Vector3 = _target_pos(t)
			var to: Vector3 = tp - player.global_position
			var hdg: float = WorldCoords.dir_to_heading(Vector3(to.x, 0, to.z))
			var dist_km: float = Vector2(to.x, to.z).length() * WorldCoords.HORIZ_COMPRESSION / 1000.0
			txt += "TARGET %s\n%.1f km  BRG %03d  (%d/%d down)\n" % [str(target_names.get(str(t.get("target_id")), "target")), dist_km, int(hdg), _destroyed_count, targets.size()]
			if Vector2(to.x, to.z).length() < 220.0 and player.global_position.y > 60.0:
				txt += ">> RELEASE BOMBS <<\n"
	elif phase == "rtb" and _have_home:
		var tb: Vector3 = _home - player.global_position
		txt += "BASE  %.1f km  BRG %03d\n" % [Vector2(tb.x, tb.z).length() * WorldCoords.HORIZ_COMPRESSION / 1000.0, int(WorldCoords.dir_to_heading(Vector3(tb.x, 0, tb.z)))]
	var p: Aircraft = player as Aircraft
	if p:
		txt += "BOMBS %d  SCORE %d" % [p.bombs, score]
	_label.text = txt


# ------------------------------------------------------------------ events
func _on_target_destroyed(_node: Node, _killer: Node, id: String) -> void:
	_destroyed_count += 1
	add_score(500)
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "TARGET DESTROYED: %s" % str(target_names.get(id, id)), 3.0)
	radio_call_any("bomb_target", 3, 0.8)
	if _alive_targets().is_empty():
		_all_targets_down()


func _all_targets_down() -> void:
	if phase != "ingress":
		return
	phase = "rtb"
	_debug_t = 4.0
	add_score(1000)
	if _beacon:
		_beacon.visible = false
	_update_objective()
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "All targets destroyed - return to base!", 4.0)
	radio_call_any("bomb_all", 2, 2.0)
	if not _have_home:
		finish(true, _stats())


func _on_player_destroyed(_a: Node, _k: Node) -> void:
	if _player_dead or not running:
		return
	_player_dead = true
	print("BombingMode: player destroyed t=%.1f" % elapsed)
	finish(false, _stats(_death_note if _death_note != "" else "killed - shot down"))


func _stats(reason: String = "") -> Dictionary:
	return {"targets_destroyed": _destroyed_count, "targets": targets.size(), "reason": reason, "kills": _kills, "bda": _bda_report()}


## A player bomb went off. It counts against the nearest objective within 260 m of it, as a hit when it lands
## inside that target's hit radius, otherwise a miss. Marks are stored relative to the target centre.
func _on_bomb_impact(pos: Vector3, _radius: float) -> void:
	if not running or _bda.is_empty():
		return
	var best: Dictionary = {}
	var bd: float = 260.0
	for e in _bda:
		var n: Node = e["node"]
		if not is_instance_valid(n):
			continue
		var c: Vector3 = _target_pos(n)
		var d: float = Vector2(pos.x - c.x, pos.z - c.z).length()
		if d < bd:
			bd = d
			best = e
	if best.is_empty():
		return
	var c2: Vector3 = _target_pos(best["node"])
	(best["marks"] as Array).append({"x": pos.x - c2.x, "z": pos.z - c2.z, "hit": bd <= float(best["r"])})


## Per-target damage assessment for the results screen: the target name, its hit radius, whether it is down and
## every bomb mark (metres from the target centre, world X/Z).
func _bda_report() -> Dictionary:
	var out: Array = []
	for e in _bda:
		var n: Node = e["node"]
		var down: bool = is_instance_valid(n) and bool(n.call("is_destroyed"))
		out.append({"name": e["name"], "r": e["r"], "destroyed": down, "marks": (e["marks"] as Array).duplicate()})
	return {"targets": out}


func _teleport_near() -> void:
	var t: Node = _nearest_target()
	if t == null:
		return
	var tp: Vector3 = _target_pos(t)
	var dir: Vector3 = Vector3(0, 0, 1) if enemy_side == "Axis" else Vector3(0, 0, -1)
	var pos: Vector3 = tp - dir * 3500.0
	pos.y = 650.0
	var hdg: float = WorldCoords.dir_to_heading(dir)
	(player as Aircraft).reset_pose(pos, hdg, true)


# ------------------------------------------------------------------ interception
func _spawn_interceptors() -> void:
	if world == null or player == null:
		return
	var ids: Array = AircraftCatalog.fighters_for_side(enemy_side)
	if ids.is_empty():
		return
	var n: int = 2 + int(difficulty * 3.0) + _waves_spawned
	var tp: Vector3 = player.global_position
	var t: Node = _nearest_target()
	var base: Vector3 = _target_pos(t) if t != null else tp
	for i in n:
		var a: float = randf() * TAU
		var pos: Vector3 = base + Vector3(cos(a), 0, sin(a)) * randf_range(2500.0, 4200.0)
		pos.y = maxf(tp.y, 450.0) + randf_range(-60.0, 200.0)
		var hdg: float = WorldCoords.dir_to_heading(Vector3(tp.x - pos.x, 0, tp.z - pos.z))
		var ac: Aircraft = AIFactory.spawn(world, ids[randi() % ids.size()], enemy_side, pos, hdg, -1.0, clampf(difficulty + randf_range(-0.1, 0.1), 0.0, 1.0))
		_enemy_fighters.append(ac)
		ac.destroyed.connect(func(_a: Aircraft, killer: Node) -> void:
			if killer == player:
				_kills += 1
				add_score(150))
	_waves_spawned += 1
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "Enemy fighters inbound!", 2.5)
	radio_call_any("bomb_fighters", 2)


# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	super._process(delta)
	if not running or player == null or not is_instance_valid(player):
		return
	if _beacon and _beacon.visible:
		var t: Node = _nearest_target()
		if t != null:
			var tp: Vector3 = _target_pos(t)
			_beacon.global_position = Vector3(tp.x, 600.0, tp.z)
	_label_t -= delta
	if _label_t <= 0.0:
		_label_t = 0.2
		_refresh_label()
	if phase == "ingress":
		var nt: Node = _nearest_target()
		if nt != null:
			var d: float = _target_pos(nt).distance_to(player.global_position)
			_wave_t -= delta
			if _waves_spawned < interceptor_waves and (d < 7500.0 and _wave_t <= 0.0):
				_spawn_interceptors()
				_wave_t = 70.0
		if debug_auto:
			_debug_t -= delta
			if _debug_t <= 0.0:
				_debug_t = 99999.0
				for t2 in _alive_targets():
					t2.call("take_damage", 99999.0, player)
	elif phase == "rtb":
		if debug_auto:
			_debug_t -= delta
			if _debug_t <= 0.0:
				_debug_t = 99999.0
				finish(true, _stats("debug rtb"))
				return
		if _have_home:
			var p: Aircraft = player as Aircraft
			var dh: float = Vector2(player.global_position.x - _home.x, player.global_position.z - _home.z).length()
			if dh < rtb_radius and (p.on_ground or p.altitude_agl < 220.0):
				add_score(500)
				if hud and hud.has_method("show_message"):
					hud.call("show_message", "MISSION COMPLETE - back at base", 3.0)
				radio_call("bomb_complete")
				phase = "done"
				finish(true, _stats())
