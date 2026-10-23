class_name DogfightMode
extends ModeBase
## Waves of enemy fighters (plus the occasional bomber formation) over the Channel.
## Player keeps the chosen side; enemies are the opposite side. Allied/own-side wingmen follow the player.
## configure(cfg): side, aircraft, difficulty (0..1).

var start_airborne: bool = true
var manages_respawn: bool = true

var side: String = "Allies"
var enemy_side: String = "Axis"
var difficulty: float = 0.5
var player_aircraft_id: String = "spitfire"
var planes_left: int = 3
var wave: int = 0
var _low_wait: float = 0.0     # extra seconds the next wave has been held back while the player is low
var total_waves: int = 5
var kills: int = 0
var deaths: int = 0
var combo: int = 0
var combo_time: float = 0.0
var enemies: Array[Aircraft] = []
var wingmen: Array[Aircraft] = []
var wingmen_max: int = 3      # grows every time a life is used, so you come back with more support
var formations: Array[BomberFormation] = []

enum Phase { PREP, ACTIVE, BREAK, OVER }
var phase: int = Phase.PREP
var _phase_t: float = 3.0
var _player_dead: bool = false
var _respawn_t: float = 0.0
var _label: Label
var _check_t: float = 0.0
var _won: bool = false
var _debug: bool = OS.get_cmdline_user_args().has("--ai-debug")
var _dbg_t: float = 0.0


func configure(cfg: Dictionary) -> void:
	side = String(cfg.get("side", GameState.player_side))
	enemy_side = AircraftCatalog.opposite(side)
	difficulty = float(cfg.get("difficulty", 0.5))
	player_aircraft_id = String(cfg.get("aircraft", AircraftCatalog.default_fighter(side)))
	planes_left = 5 if difficulty < 0.35 else (3 if difficulty < 0.7 else 2)
	total_waves = 3 if difficulty < 0.35 else (5 if difficulty < 0.7 else 7)
	planes_left = int(cfg.get("planes", planes_left))
	wave = maxi(int(cfg.get("start_wave", 1)) - 1, 0)
	total_waves = maxi(total_waves, wave + 1)


func start() -> void:
	super.start()
	enemy_side = AircraftCatalog.opposite(side)
	_build_label()
	if player and is_instance_valid(player):
		(player as Aircraft).destroyed.connect(_on_player_destroyed)
	_top_up_wingmen()
	_set_phase(Phase.PREP, 45.0)      # a long run-in before the first contact: take off, climb, get set, spot them
	_announce("DOGFIGHT - %d waves" % total_waves, "Destroy all enemy aircraft.")
	_refresh_label()


func stop() -> void:
	super.stop()
	if _label and is_instance_valid(_label):
		_label.queue_free()


func _build_label() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.82))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 4)
	if hud and hud.has_method("add_widget"):
		hud.call("add_widget", _label)


func _announce(msg: String, objective: String = "") -> void:
	if hud and hud.has_method("show_message"):
		hud.call("show_message", msg, 3.0)
	if objective != "":
		objective_updated.emit(objective)


func _refresh_label() -> void:
	if _label == null or not is_instance_valid(_label):
		return
	var mult: float = _combo_mult()
	_label.text = "DOGFIGHT  WAVE %d/%d\nENEMIES %d   KILLS %d\nSCORE %d%s\nAIRCRAFT %d" % [maxi(wave, 1), total_waves, _alive_enemies(), kills, score, ("   COMBO x%.1f" % mult) if combo > 1 else "", planes_left]


func _set_phase(p: int, t: float) -> void:
	phase = p
	_phase_t = t


func _combo_mult() -> float:
	return minf(1.0 + 0.5 * float(maxi(combo - 1, 0)), 4.0)


# ------------------------------------------------------------------ loop

func _process(delta: float) -> void:
	super._process(delta)
	if not running:
		return
	if _debug:
		_dbg_t -= delta
		if _dbg_t <= 0.0:
			_dbg_t = 5.0
			_debug_dump()
	if combo_time > 0.0:
		combo_time -= delta
		if combo_time <= 0.0:
			combo = 0
			_refresh_label()
	if _player_dead:
		_respawn_t -= delta
		if _respawn_t <= 0.0:
			_respawn_player()
	match phase:
		Phase.PREP, Phase.BREAK:
			_phase_t -= delta
			if _phase_t <= 0.0:
				# never launch a wave at a player still on the airfield or hugging the ground: wait (up to 90 s) until he is up
				var pl: Aircraft = player as Aircraft
				if pl != null and is_instance_valid(pl) and (pl.on_ground or pl.altitude_agl < 450.0) and _low_wait < 90.0:
					_low_wait += delta
				else:
					_low_wait = 0.0
					_next_wave()
		Phase.ACTIVE:
			_check_t -= delta
			if _check_t <= 0.0:
				_check_t = 0.5
				if _alive_enemies() == 0:
					_wave_cleared()
				_refresh_label()


func _alive_enemies() -> int:
	var n: int = 0
	for e in enemies:
		if is_instance_valid(e) and e.state == Aircraft.State.ALIVE:
			n += 1
	return n


func _wave_cleared() -> void:
	var bonus: int = 250 * wave
	add_score(bonus)
	if wave >= total_waves:
		_won = true
		phase = Phase.OVER
		_announce("ALL WAVES CLEARED!", "Victory")
		finish(true, _stats())
		return
	_announce("WAVE %d CLEARED  +%d" % [wave, bonus], "Wave %d cleared - prepare for the next" % wave)
	radio_call_any("dog_clear", 2, 1.0)
	_set_phase(Phase.BREAK, 20.0)     # a longer breather between waves: rearm, climb back up, get set
	enemies = enemies.filter(func(e: Aircraft) -> bool: return is_instance_valid(e))
	_top_up_wingmen()


func nav_point() -> Variant:
	return _nearest_pos(enemies)


func _stats() -> Dictionary:
	return {"kills": kills, "waves": wave, "deaths": deaths, "difficulty": "%d%%" % int(difficulty * 100.0)}


# ------------------------------------------------------------------ waves

func _next_wave() -> void:
	wave += 1
	_set_phase(Phase.ACTIVE, 0.0)
	var n: int = clampi(roundi((2.0 + float(wave) * 1.2) * (0.6 + 0.4 * difficulty)), 2, 10)
	var pool: Array = _enemy_pool(wave)
	var base_heading: float = 300.0 if side == "Axis" else 115.0
	var center: Vector3 = _player_pos()
	var jets: int = 0
	# not every wave comes straight at you: some are patrols loitering well away from the airfield that have not seen
	# you yet - find them on the radar and sneak up (from above, out of the sun, from behind) for the first strike.
	var sneak: bool = randf() < (0.3 if wave == 1 else 0.45)
	var patrol_c: Vector3 = center + WorldCoords.heading_to_dir(randf() * 360.0) * randf_range(8000.0, 12000.0)
	for i in n:
		var id: String = pool[randi() % pool.size()]
		if id == "me262":
			jets += 1
			if jets > 1:
				id = "fw190"
		var h: float = base_heading + randf_range(-40.0, 40.0)
		var dist: float = randf_range(9000.0, 12500.0) if wave == 1 else randf_range(6000.0, 8500.0)     # the first wave starts well out, far from the airfield
		var pos: Vector3 = center + WorldCoords.heading_to_dir(h) * dist + Vector3(randf_range(-250, 250), 0, randf_range(-250, 250))
		pos.y = _safe_alt(pos, center.y + randf_range(-150.0, 350.0))
		var face: float = WorldCoords.dir_to_heading(center - pos)
		if sneak:
			pos = patrol_c + Vector3(randf_range(-400, 400), 0, randf_range(-400, 400))
			pos.y = _safe_alt(pos, center.y + randf_range(300.0, 900.0))
			face = WorldCoords.dir_to_heading(patrol_c - center) + 90.0 + randf_range(-30.0, 30.0)
		var ac: Aircraft = AIFactory.spawn(world, id, enemy_side, pos, face, -1.0, clampf(difficulty * 0.6 + randf_range(-0.08, 0.08), 0.0, 1.0))
		_register_enemy(ac, Color(1.0, 0.25, 0.2), patrol_c if sneak else Vector3.ZERO)
	var wave_bombers: bool = wave in [3, 5, 7]
	if wave_bombers:
		_spawn_bombers(center, base_heading, 3 + (1 if difficulty > 0.7 else 0))
	var msg: String = "WAVE %d  -  %d enemy aircraft" % [wave, n]
	if wave_bombers:
		msg += " + bombers"
	if sneak:
		msg += " - a patrol that has not seen you"
	_announce(msg, "Wave %d of %d: destroy all enemy aircraft" % [wave, total_waves])
	if wave >= total_waves:
		radio_call("dog_final")
	else:
		radio_call_any("dog_wave", 3)
	_top_up_wingmen()
	_refresh_label()


func _enemy_pool(w: int) -> Array:
	if enemy_side == "Axis":
		var p: Array = ["bf109"]
		if w >= 2:
			p.append("fw190")
		if w >= 4:
			p.append("me262")
		return p
	var q: Array = ["spitfire", "hurricane"]
	if w >= 2:
		q.append("p51")
	if w >= 3:
		q.append("typhoon")
	if w >= 4:
		q.append("p47")
	return q


func _spawn_bombers(center: Vector3, base_heading: float, count: int) -> void:
	var bomber_ids: Array = AircraftCatalog.bombers_for_side(enemy_side)
	var id: String = bomber_ids[randi() % bomber_ids.size()]
	var h: float = base_heading + randf_range(-25.0, 25.0)
	var pos: Vector3 = center + WorldCoords.heading_to_dir(h) * 9000.0
	pos.y = _safe_alt(pos, 1300.0)
	var face: float = WorldCoords.dir_to_heading(center - pos)
	var dir: Vector3 = (center - pos)
	dir.y = 0.0
	dir = dir.normalized()
	var route: Array[Vector3] = [Vector3(center.x, pos.y, center.z) + dir * 1200.0, Vector3(center.x, pos.y, center.z) + dir * 10000.0]
	var f: BomberFormation = BomberFormation.spawn(world, id, enemy_side, count, pos, face, route, difficulty)
	formations.append(f)
	for m in f.members:
		_register_enemy(m, Color(1.0, 0.6, 0.15))


func _register_enemy(ac: Aircraft, col: Color, loiter: Vector3 = Vector3.ZERO) -> void:
	enemies.append(ac)
	ac.destroyed.connect(_on_enemy_destroyed)
	ac.crashed.connect(func(a: Aircraft, _r: String) -> void: _free_later(a, 2.5))
	AIFactory.add_marker(hud, ac, col)
	var pilot: AIPilot = AIFactory.pilot_of(ac)
	if pilot and pilot.role == AIPilot.Role.FIGHTER:
		if loiter != Vector3.ZERO:
			pilot.detect_range = 2600.0          # a patrol that has not noticed you: it only reacts when you get close
			pilot.patrol_center = loiter
		else:
			pilot.detect_range = 4500.0
			pilot.patrol_center = _player_pos()


func _free_later(a: Aircraft, t: float) -> void:
	if not is_instance_valid(a):
		return
	await a.get_tree().create_timer(t).timeout
	if is_instance_valid(a):
		a.queue_free()


func _safe_alt(pos: Vector3, desired: float) -> float:
	var ground: float = 0.0
	var t: Node = world.get_tree().get_first_node_in_group("terrain") if world else null
	if t and t.has_method("get_height_at"):
		ground = maxf(float(t.call("get_height_at", pos)), 0.0)
	return maxf(desired, ground + 350.0)


func _player_pos() -> Vector3:
	if player and is_instance_valid(player):
		return player.global_position
	return Vector3.ZERO


# ------------------------------------------------------------------ wingmen

func _top_up_wingmen() -> void:
	if not (player and is_instance_valid(player)) or _player_dead:
		return
	wingmen = wingmen.filter(func(w: Aircraft) -> bool: return is_instance_valid(w) and w.state == Aircraft.State.ALIVE)
	var id: String = player_aircraft_id
	if AircraftCatalog.is_bomber(id):
		id = AircraftCatalog.default_fighter(side)
	var pl: Aircraft = player as Aircraft
	var yaw: Basis = Basis.looking_at(Vector3(pl.get_forward().x, 0.0, pl.get_forward().z).normalized() if absf(pl.get_forward().y) < 0.99 else Vector3.FORWARD, Vector3.UP)
	while wingmen.size() < wingmen_max:
		var k: int = wingmen.size()
		var off: Vector3 = Radio.formation_offset(k, wingmen_max)
		var pos: Vector3 = pl.global_position + yaw * off
		var w: Aircraft = AIFactory.spawn(world, id, side, pos, pl.get_heading_deg(), maxf(pl.speed, pl.stats.stall_speed * 1.6), 0.75, AIPilot.Role.WINGMAN, player)
		var pilot: AIPilot = AIFactory.pilot_of(w)
		pilot.set_leader(player, off)
		pilot.detect_range = 9000.0
		wingmen.append(w)
		w.crashed.connect(func(a: Aircraft, _r: String) -> void: _free_later(a, 2.5))
		AIFactory.add_marker(hud, w, Color(0.3, 0.75, 1.0))


# ------------------------------------------------------------------ events

func _on_enemy_destroyed(ac: Aircraft, killer: Node) -> void:
	var by_player: bool = killer != null and (killer == player or (killer is Aircraft and (killer as Aircraft).player_controlled))
	if by_player:
		kills += 1
		combo += 1
		combo_time = 7.0
		var base: int = 100
		if ac.is_in_group("bomber"):
			base = 150
		elif ac.stats.id == "me262":
			base = 200
		var pts: int = int(round(float(base) * _combo_mult()))
		add_score(pts)
		var text: String = "KILL +%d" % pts
		if combo >= 2:
			text += "   COMBO x%.1f" % _combo_mult()
		if hud and hud.has_method("show_message"):
			hud.call("show_message", text, 2.0)
	elif killer != null and killer is Aircraft:
		add_score(25)
	_free_later(ac, 14.0)
	_refresh_label()


func _on_player_destroyed(_a: Aircraft, _killer: Node) -> void:
	if _player_dead or not running:
		return
	_player_dead = true
	deaths += 1
	planes_left -= 1
	combo = 0
	if planes_left <= 0:
		_announce("SHOT DOWN - no aircraft left", "Mission failed")
		await get_tree().create_timer(3.5).timeout
		if running:
			finish(false, _stats())
		return
	_announce("SHOT DOWN - %d aircraft left" % planes_left)
	_respawn_t = 4.5
	_refresh_label()


func _respawn_player() -> void:
	_player_dead = false
	# a life was used: come back with more wingmen on the wing
	wingmen_max = clampi(wingmen_max + 2, 3, ModeBase.WINGMEN_MAX)
	if world and world.has_method("respawn_player"):
		world.call("respawn_player")
	_top_up_wingmen()
	if not wingmen.is_empty():
		Radio.say("Wingmen", "Replacements up. %d on your wing." % wingmen_max, Radio.Kind.FRIENDLY, 1.0)
	_refresh_label()


func _debug_dump() -> void:
	var states: Array = []
	for e in enemies:
		if is_instance_valid(e):
			var p: AIPilot = AIFactory.pilot_of(e)
			var tg: Aircraft = p.get_target() if p else null
			var angd: float = rad_to_deg(e.get_forward().angle_to(tg.global_position - e.global_position)) if tg else -1.0
			states.append("%s:%s hp%d ft%.1f ang%d spd%d tgt%s d%d" % [e.stats.id, AIPilot.State.keys()[p.state] if p else "-", int(e.health), p.fire_time if p else 0.0, int(angd), int(e.speed), tg.stats.id if tg else "-", int(e.global_position.distance_to(tg.global_position)) if tg else -1])
	var wm: Array = []
	for w in wingmen:
		if is_instance_valid(w):
			var wp: AIPilot = AIFactory.pilot_of(w)
			wm.append("%s hp%d ft%.1f" % [AIPilot.State.keys()[wp.state] if wp else "-", int(w.health), wp.fire_time if wp else 0.0])
	print("[dogfight] wingmen: ", wm)
	print("[dogfight] t=%.0f wave=%d kills=%d score=%d planes=%d phase=%d fps=%d hp=%d | %s" % [elapsed, wave, kills, score, planes_left, phase, Engine.get_frames_per_second(), int((player as Aircraft).health), ", ".join(states)])
