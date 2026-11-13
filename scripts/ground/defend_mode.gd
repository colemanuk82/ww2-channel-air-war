class_name DefendMode
extends ModeBase
## Defend mission: protect ground objectives (radar, factory, port, convoy...) from waves of enemy bombers with
## fighter escorts (AIFactory / BomberFormation). Bombers drop real bombs (Weapons) when overhead a protected target.
## Success = all waves finished with at least half of the objectives alive; fail = all lost or player destroyed.
## The raids differ (raid_plan): a massed raid first, then low-level raids and fighter sweeps, and the heaviest
## raid last. A raid that is broken up early brings the next one forward, so there is no long wait in an empty sky.

var start_airborne: bool = true
var manages_respawn: bool = true

var side: String = "Allies"
var enemy_side: String = "Axis"
var difficulty: float = 0.5
var protect_ids: Array = []
var waves: int = 3
var teleport: bool = false
var briefing: String = ""

var wave: int = 0
var protected_nodes: Array = []
var names: Dictionary = {}
var bombers_down: int = 0
var fighters_down: int = 0

var _populator: WorldPopulator
var _label: Label
var _label_t: float = 0.0
var _wave_t: float = 20.0
var _formations: Array = []
var _escorts: Array = []
var _dropped: Dictionary = {}
var _finish_t: float = -1.0
var _player_dead: bool = false
var _hurried: int = 0               # the wave whose early end already brought the next raid forward

const RAID_ALT := 700.0
const RAID_ALT_LOW := 600.0
const RAID_DIST := 7000.0           # how far out a raid starts
const RAID_DIST_LOW := 5200.0       # a low raid is picked up late
const NEXT_RAID_S := 22.0           # a raid broken up early: the next one comes this soon


## What raid number `wave` (1-based) of `waves` looks like. `mix` varies the middle raids between missions.
## Returns {kind: mass|low|sweep|big, alt, dist (how far out it starts), bombers (change to the count),
## fighters (change), ahead (how far the escort flies in front of the bombers), label}.
static func raid_plan(wave: int, waves: int, mix: int = 0) -> Dictionary:
	if wave <= 1 or waves <= 1:
		return {"kind": "mass", "alt": RAID_ALT, "dist": RAID_DIST, "bombers": 0, "fighters": 0, "ahead": 0.0, "label": "Raid"}
	if wave >= waves and waves >= 3:
		return {"kind": "big", "alt": RAID_ALT, "dist": RAID_DIST, "bombers": 2, "fighters": 1, "ahead": 0.0, "label": "The big raid"}
	if (wave + mix) % 2 == 0:
		return {"kind": "low", "alt": RAID_ALT_LOW, "dist": RAID_DIST_LOW, "bombers": -1, "fighters": -1, "ahead": 0.0, "label": "Low, fast raid"}
	return {"kind": "sweep", "alt": RAID_ALT, "dist": RAID_DIST, "bombers": -1, "fighters": 2, "ahead": 1500.0, "label": "Fighter sweep ahead of the bombers"}


func _raid_mix() -> int:
	var h: int = 0
	for id in protect_ids:
		h += str(id).length()
	return h


func configure(cfg: Dictionary) -> void:
	side = str(cfg.get("side", GameState.player_side))
	enemy_side = GroundKit.enemy_of(side)
	difficulty = float(cfg.get("difficulty", 0.5))
	if cfg.has("protect"):
		protect_ids = (cfg["protect"] as Array).duplicate()
	waves = 2 if difficulty < 0.35 else (3 if difficulty < 0.7 else 4)
	if cfg.has("waves"):
		waves = int(cfg["waves"])
	if world != null:
		_populator = WorldPopulator.ensure(world)


func start() -> void:
	super.start()
	teleport = teleport or GroundKit.has_arg("--wp-teleport")
	if _populator == null:
		_populator = WorldPopulator.ensure(world)
	for id in protect_ids:
		var info: Dictionary = _populator.get_target_info(id)
		names[id] = str(info.get("name", id))
		var n: Node = _populator.spawn_target(id)
		if n != null:
			protected_nodes.append(n)
	_build_label()
	if player and is_instance_valid(player):
		var p: Aircraft = (player as Aircraft) if is_instance_valid(player) else null
		p.destroyed.connect(_on_player_destroyed)
		p.crashed.connect(func(_a: Aircraft, _r: String) -> void: _on_player_destroyed(p, null))
		if teleport and not protected_nodes.is_empty():
			var tp: Vector3 = _node_pos(protected_nodes[0])
			var pos: Vector3 = tp + Vector3(0, 0, 1800.0)
			pos.y = 600.0
			p.reset_pose(pos, 0.0, true)
	objective_updated.emit("Protect: %s" % ", ".join(PackedStringArray(names.values())))
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "DEFEND - intercept the %d raids" % waves, 4.0)


func stop() -> void:
	super.stop()
	if _label != null and is_instance_valid(_label):
		_label.queue_free()


func _build_label() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.82))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 4)
	if hud and hud.has_method("add_widget"):
		hud.call("add_widget", _label)


func _node_pos(n: Node) -> Vector3:
	if n is Convoy:
		return (n as Convoy).get_center()
	return (n as Node3D).global_position


func _alive_protected() -> Array:
	var out: Array = []
	for n in protected_nodes:
		if is_instance_valid(n) and not bool(n.call("is_destroyed")):
			out.append(n)
	return out


func _enemy_airfield_pos() -> Vector3:
	var want: String = "Luftwaffe" if enemy_side == "Axis" else "RAF"
	var pool: Array = []
	for a in _populator.loc.get("airfields", []):
		if str(a["side"]) == want:
			pool.append(a)
	if pool.is_empty():
		return _node_pos(protected_nodes[0]) + Vector3(6000, 0, 6000)
	var tp: Vector3 = _node_pos(protected_nodes[0])
	var best: Array = []
	for a in pool:
		var p: Vector3 = WorldCoords.latlon_to_world(float(a["lat"]), float(a["lon"]))
		if p.distance_to(tp) > 3500.0:
			best.append([p.distance_to(tp), p])
	if best.is_empty():
		return _node_pos(protected_nodes[0]) + Vector3(6000, 0, 6000)
	best.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	return best[randi() % mini(best.size(), 3)][1]


func _spawn_wave() -> void:
	var alive: Array = _alive_protected()
	if alive.is_empty() or world == null:
		return
	wave += 1
	var plan: Dictionary = raid_plan(wave, waves, _raid_mix())
	var tgt: Node = alive[randi() % alive.size()]
	var tp: Vector3 = _node_pos(tgt)
	var alt: float = maxf(float(plan["alt"]), GroundKit.ground_y(tp.x, tp.z) + 330.0)
	var home: Vector3 = _enemy_airfield_pos()
	var start_pos: Vector3 = home
	var dir: Vector3 = (tp - home)
	dir.y = 0.0
	if dir.length() > float(plan["dist"]):
		start_pos = tp - dir.normalized() * float(plan["dist"])
	start_pos.y = alt
	var hdg: float = WorldCoords.dir_to_heading(Vector3(tp.x - start_pos.x, 0, tp.z - start_pos.z))
	var ids: Array = AircraftCatalog.bombers_for_side(enemy_side)
	var fids: Array = AircraftCatalog.fighters_for_side(enemy_side)
	if not ids.is_empty():
		var wps: Array[Vector3] = []
		wps.append(Vector3(tp.x, alt, tp.z))
		var out: Vector3 = tp + Vector3(tp.x - start_pos.x, 0.0, tp.z - start_pos.z).normalized() * 2500.0
		wps.append(Vector3(out.x, alt, out.z))
		wps.append(Vector3(home.x, RAID_ALT, home.z))
		var count: int = maxi(3 + wave + int(difficulty * 2.0) + int(plan["bombers"]), 2)
		var f: BomberFormation = BomberFormation.spawn(world, ids[randi() % ids.size()], enemy_side, count, start_pos, hdg, wps, difficulty)
		_formations.append(f)
		f.bomber_destroyed.connect(func(_b: Aircraft, killer: Node) -> void:
			bombers_down += 1
			if killer == player:
				add_score(200))
	if not fids.is_empty():
		var lead_off: Vector3 = Vector3(tp.x - start_pos.x, 0.0, tp.z - start_pos.z).normalized() * float(plan["ahead"])
		for i in maxi(2 + wave + int(plan["fighters"]), 1):
			var off := Vector3(randf_range(-250, 250), randf_range(-30, 120), randf_range(-250, 250))
			var ac: Aircraft = AIFactory.spawn(world, fids[randi() % fids.size()], enemy_side, start_pos + lead_off + off, hdg, -1.0, clampf(difficulty + randf_range(-0.1, 0.1), 0.0, 1.0))
			_escorts.append(ac)
			ac.destroyed.connect(func(_a: Aircraft, killer: Node) -> void:
				fighters_down += 1
				if killer == player:
					add_score(150))
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "%s %d/%d inbound toward %s" % [str(plan["label"]), wave, waves, str(names.get(str(tgt.get("target_id")), "target"))], 4.0)
	if str(plan["kind"]) == "mass" and not radio_quiet:
		radio_call_any("defend_raid", 3)
	else:
		Radio.say("Operations Room" if side == "Allies" else "Ground Control", raid_call(plan, wave, waves, str(names.get(str(tgt.get("target_id")), "the target"))), Radio.Kind.CONTROL, 0.0, "", true)


## The controller's words for a raid.
static func raid_call(plan: Dictionary, p_wave: int, p_waves: int, where: String) -> String:
	match str(plan.get("kind", "mass")):
		"low":
			return "Raid %d of %d is a small one, low and fast, making for %s. It is close already: catch it before it gets there." % [p_wave, p_waves, where]
		"sweep":
			return "Raid %d of %d: their fighters are out in front of the bombers. Deal with the escort, then the bombers making for %s." % [p_wave, p_waves, where]
		"big":
			return "This is the big one: raid %d of %d, the heaviest yet, making for %s. Everything you have." % [p_wave, p_waves, where]
	return "Raid %d of %d building, heading for %s." % [p_wave, p_waves, where]


func _bomber_drops() -> void:
	var alive: Array = _alive_protected()
	if alive.is_empty():
		return
	var has_weapons: bool = get_tree().root.has_node("Weapons")
	for f in _formations:
		if not is_instance_valid(f):
			continue
		for m in (f as BomberFormation).members:
			if not is_instance_valid(m) or m.state != Aircraft.State.ALIVE:
				continue
			var mid: int = m.get_instance_id()
			if _dropped.has(mid):
				continue
			for t in alive:
				var tp: Vector3 = _node_pos(t)
				if Vector2(m.global_position.x - tp.x, m.global_position.z - tp.z).length() < 130.0:
					_dropped[mid] = true
					var vel: Vector3 = m.velocity if m.velocity.length() > 1.0 else m.get_forward() * 100.0
					if has_weapons:
						var w: Node = get_tree().root.get_node("Weapons")
						for k in 3:
							w.call("drop_bomb", m.global_position + vel.normalized() * float(k) * 14.0 - Vector3(0, 2, 0), vel, enemy_side, m, 140.0, 28.0)
					else:
						t.call("take_damage", 120.0, m)
					break


func _formations_done() -> bool:
	for f in _formations:
		if is_instance_valid(f) and (f as BomberFormation).alive_count() > 0 and not bool(f.get("_finished")):
			return false
	return true


func nav_point() -> Variant:
	var leaders: Array = []
	for f in _formations:
		if is_instance_valid(f) and is_instance_valid((f as BomberFormation).leader):
			leaders.append((f as BomberFormation).leader)
	var p: Variant = _nearest_pos(leaders)
	return p if p != null else _nearest_pos(protected_nodes)


func _stats() -> Dictionary:
	return {"bombers_down": bombers_down, "fighters_down": fighters_down, "protected_alive": _alive_protected().size(), "protected": protected_nodes.size(), "waves": wave}


func _on_player_destroyed(_a: Node, _k: Node) -> void:
	if _player_dead or not running:
		return
	_player_dead = true
	finish(false, _stats())


func _process(delta: float) -> void:
	super._process(delta)
	if not running:
		return
	_bomber_drops()
	var alive: Array = _alive_protected()
	if alive.is_empty() and not protected_nodes.is_empty():
		finish(false, _stats())
		return
	if wave < waves:
		_wave_t -= delta
		if _wave_t <= 0.0:
			_spawn_wave()
			_wave_t = 80.0
		elif wave >= 1 and _hurried < wave and _wave_t > NEXT_RAID_S and _wave_t < 62.0 and _formations_done():
			# the raid is finished with (shot down or gone home): bring the next plot forward
			_hurried = wave
			_wave_t = NEXT_RAID_S
			if hud and hud.has_method("show_message"):
				hud.call("show_message", "Raid dealt with - the next is already building", 3.5)
	elif _finish_t < 0.0 and _formations_done():
		_finish_t = 6.0
	if _finish_t >= 0.0:
		_finish_t -= delta
		if _finish_t <= 0.0:
			var ok: bool = float(alive.size()) >= float(protected_nodes.size()) * 0.5 and bombers_down >= 1     # at least one raider must be shot down
			add_score(alive.size() * 600)
			finish(ok, _stats())
			return
	_label_t -= delta
	if _label_t <= 0.0 and _label != null and is_instance_valid(_label):
		_label_t = 0.3
		var n_b: int = 0
		for f in _formations:
			if is_instance_valid(f):
				n_b += (f as BomberFormation).alive_count()
		_label.text = "DEFEND  RAID %d/%d\nPROTECTED %d/%d   BOMBERS %d\nKILLS B%d F%d   SCORE %d" % [wave, waves, alive.size(), protected_nodes.size(), n_b, bombers_down, fighters_down, score]
