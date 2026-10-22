class_name EscortMode
extends ModeBase
## Bomber escort: a friendly bomber formation flies to a real enemy target, bombs it and heads home. Enemy interceptor
## waves hit the formation on the way; keep at least one bomber alive until it reaches home.
## configure(cfg): side, difficulty, targets (ids from locations.json), no_fighters.

var side: String = "Allies"
var enemy_side: String = "Axis"
var difficulty: float = 0.5
var target_ids: Array = []
var no_fighters: bool = false

var formation: BomberFormation
var _populator: WorldPopulator
var _target: Node
var _target_pos: Vector3 = Vector3.ZERO
var _bombed: bool = false
var _wave_t: float = 0.0
var _waves: int = 0
var _kills: int = 0
var _tick: float = 0.0
var _home: Vector3 = Vector3.ZERO
var _count: int = 3


func configure(cfg: Dictionary) -> void:
	side = String(cfg.get("side", GameState.player_side))
	enemy_side = AircraftCatalog.opposite(side)
	difficulty = float(cfg.get("difficulty", 0.5))
	no_fighters = bool(cfg.get("no_fighters", false))
	if cfg.has("targets"):
		target_ids = (cfg["targets"] as Array).duplicate()
	_count = 3 if difficulty < 0.4 else 5


func start() -> void:
	super.start()
	_populator = WorldPopulator.ensure(world)
	var pp: Vector3 = (player as Node3D).global_position
	if target_ids.is_empty():
		var pool: Array = _populator.targets_for_side(enemy_side, ["factory", "rail_yard", "port", "bridge", "battery", "radar", "v1_site"])
		pool.sort_custom(func(a: String, b: String) -> bool:
			return (_populator.get_target_info(a)["pos"] as Vector3).distance_to(pp) < (_populator.get_target_info(b)["pos"] as Vector3).distance_to(pp))
		if not pool.is_empty():
			target_ids = [pool[0]]
	if target_ids.is_empty():
		finish(false, {"reason": "no target"})
		return
	var tid: String = str(target_ids[0])
	_target = _populator.spawn_target(tid)
	_target_pos = _populator.get_target_info(tid)["pos"]
	var to_t: Vector3 = _target_pos - pp
	to_t.y = 0.0
	var dir: Vector3 = to_t.normalized() if to_t.length() > 1.0 else Vector3(0, 0, -1)
	var alt: float = 3600.0
	_home = pp
	var start_pos: Vector3 = Vector3(pp.x, alt, pp.z) + dir * 900.0
	var route: Array[Vector3] = [Vector3(_target_pos.x, alt, _target_pos.z), Vector3(pp.x, alt, pp.z) - dir * 1500.0]
	var ids: Array = AircraftCatalog.bombers_for_side(side)
	var bid: String = ids[0] if not ids.is_empty() else "b26"
	formation = BomberFormation.spawn(world, bid, side, _count, start_pos, WorldCoords.dir_to_heading(dir), route, difficulty)
	formation.route_finished.connect(_on_route_finished)
	for m in formation.members:
		AIFactory.add_marker(hud, m, Color(0.45, 0.85, 1.0))
	objective_updated.emit("Escort the bombers to the target and home")
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "Escort %d bombers to %s" % [formation.members.size(), str(_populator.get_target_info(tid).get("name", tid))], 4.0)
	Radio.say("Bomber leader", "Little friends, this is the lead bomber. We are on our way. Stay close.", Radio.Kind.FRIENDLY, 1.5)
	# no interceptors straight away: the first wave is held back until the escort has formed up and the
	# formation is well on its way, and later waves are spaced well apart
	_wave_t = lerpf(95.0, 65.0, difficulty)


func _process(delta: float) -> void:
	super._process(delta)
	if not running or formation == null:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	if formation.alive_count() <= 0:
		finish(false, _stats("bombers lost"))
		return
	var lead: Aircraft = formation.leader
	if not is_instance_valid(lead):
		return
	var ramp: float = lerpf(0.65, 1.0, clampf(elapsed / 120.0, 0.0, 1.0))     # leave the field slowly so the escort can form up
	for m in formation.members:
		var bp: AIPilot = AIFactory.pilot_of(m) if is_instance_valid(m) else null
		if bp != null:
			bp.bomber_speed_k = ramp
	var lp: Vector3 = lead.global_position
	if GroundKit.has_arg("--escort-debug"):
		var pl: Aircraft = player as Aircraft
		print("[escort] t=%3.0f  bomber %.0f u/s (%.0f km/h) alt %.0f m  | player %.0f u/s alt %.0f m  | gap %.1f km (real)" % [elapsed, lead.speed, lead.speed * 3.6, lp.y / 2.0, pl.speed, pl.global_position.y / 2.0, Vector2(lp.x - pl.global_position.x, lp.z - pl.global_position.z).length() * WorldCoords.HORIZ_COMPRESSION / 1000.0])
	if not _bombed and Vector2(lp.x - _target_pos.x, lp.z - _target_pos.z).length() < 1800.0:
		_bombed = true
		if hud and hud.has_method("show_message"):
			hud.call("show_message", "Bombs away!", 3.0)
		Radio.say("Bomber leader", "Bombs away! Turning for home.", Radio.Kind.FRIENDLY, 0.0, "", true)
		get_tree().create_timer(5.0).timeout.connect(func() -> void:
			if _target != null and is_instance_valid(_target) and _target.has_method("take_damage"):
				_target.call("take_damage", 99999.0, lead)
			add_score(300))
	if not no_fighters:
		_wave_t -= 0.5
		if _wave_t <= 0.0 and _waves < (1 if difficulty < 0.4 else (2 if difficulty < 0.7 else 3)):
			_spawn_wave(lp)
			_wave_t = lerpf(130.0, 85.0, difficulty)


func _spawn_wave(lp: Vector3) -> void:
	_waves += 1
	var dir: Vector3 = WorldCoords.heading_to_dir(randf() * 360.0)
	var pos: Vector3 = lp + dir * 7000.0
	pos.y = lp.y + randf_range(-300.0, 400.0)
	var face: float = WorldCoords.dir_to_heading(lp - pos)
	var pool: Array = AircraftCatalog.fighters_for_side(enemy_side).filter(func(i: String) -> bool: return i != "me262")
	var n: int = clampi(1 + int(round(difficulty * 2.0)), 1, 3)
	var right := Vector3(-dir.z, 0, dir.x)
	for i in n:
		var ac: Aircraft = AIFactory.spawn(world, pool[randi() % pool.size()], enemy_side, pos + right * (float(i) - float(n) * 0.5) * 140.0, face, -1.0, difficulty)
		var pilot: AIPilot = AIFactory.pilot_of(ac)
		if pilot != null:
			pilot.detect_range = 9000.0
			pilot.patrol_center = lp
		AIFactory.add_marker(hud, ac, Color(1.0, 0.3, 0.2))
		ac.destroyed.connect(_on_enemy_down)
		ac.crashed.connect(func(a: Aircraft, _r: String) -> void: _free_later(a, 2.5))
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "BANDITS - %d fighters inbound" % n, 3.0)
	Radio.say("Bomber leader", "Bandits! Little friends, we have bandits inbound. Get them off us!", Radio.Kind.FRIENDLY, 0.0, "", true)


func nav_point() -> Variant:
	if formation != null and is_instance_valid(formation.leader):
		return formation.leader.global_position     # stay with the bombers
	return _target_pos if _target_pos != Vector3.ZERO else null


func _on_enemy_down(ac: Aircraft, killer: Node) -> void:
	if killer != null and (killer == player or (killer is Aircraft and (killer as Aircraft).player_controlled)):
		_kills += 1
		add_score(100)


func _free_later(a: Aircraft, t: float) -> void:
	if not is_instance_valid(a):
		return
	await a.get_tree().create_timer(t).timeout
	if is_instance_valid(a):
		a.queue_free()


func _on_route_finished() -> void:
	if running:
		add_score(200 * formation.alive_count())
		finish(true, _stats("bombers home"))


func _stats(reason: String = "") -> Dictionary:
	return {"bombers_alive": formation.alive_count() if formation != null else 0, "target_bombed": _bombed, "kills": _kills, "reason": reason}
