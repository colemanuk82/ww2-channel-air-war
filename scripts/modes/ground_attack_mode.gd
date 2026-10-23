class_name GroundAttackMode
extends ModeBase
## Strafing / ground attack: hunt enemy trains, road convoys, tank groups (and ships) in a region, with kill
## counters. Success = kill quota reached (or all given target_ids destroyed); fail = player destroyed / time out.
## configure(cfg): side, difficulty, region (key of REGIONS), quota, targets (mission_target ids to destroy).
## Direct use: GroundAttackMode.create("normandy", "Allies", 20).

const REGIONS := {
	"pas_de_calais": {"lat": 50.78, "lon": 2.15, "team": "Axis", "name": "Pas-de-Calais"},
	"normandy": {"lat": 49.25, "lon": 0.25, "team": "Axis", "name": "Normandy"},
	"flanders": {"lat": 51.02, "lon": 3.2, "team": "Axis", "name": "Flanders"},
	"seine": {"lat": 49.35, "lon": 1.2, "team": "Axis", "name": "Seine valley"},
	"kent": {"lat": 51.22, "lon": 0.85, "team": "Allies", "name": "Kent"},
	"sussex": {"lat": 50.95, "lon": -0.25, "team": "Allies", "name": "Sussex"},
}

var start_airborne: bool = true
var manages_respawn: bool = true

var side: String = "Allies"
var enemy_side: String = "Axis"
var difficulty: float = 0.5
var region: String = ""
var quota: int = 20
var target_ids: Array = []          # optional explicit mission_target ids (convoys, structures)
var teleport: bool = false
var debug_auto: bool = false
var briefing: String = ""

var kills: Dictionary = {"tanks": 0, "vehicles": 0, "trains": 0, "ships": 0, "aa": 0}
var total_kills: int = 0

var _populator: WorldPopulator
var _container: Node3D
var _center: Vector3 = Vector3.ZERO
var _label: Label
var _label_t: float = 0.0
var _scan_t: float = 0.0
var _counted: Dictionary = {}
var _target_nodes: Array = []
var _player_dead: bool = false
var _death_note: String = ""
var _debug_t: float = 8.0
var _spawned: Array = []


static func create(p_region: String, p_side: String = "Allies", p_quota: int = 20) -> GroundAttackMode:
	var m := GroundAttackMode.new()
	m.region = p_region
	m.side = p_side
	m.enemy_side = GroundKit.enemy_of(p_side)
	m.quota = p_quota
	return m


func configure(cfg: Dictionary) -> void:
	side = str(cfg.get("side", GameState.player_side))
	enemy_side = GroundKit.enemy_of(side)
	difficulty = float(cfg.get("difficulty", 0.5))
	if cfg.has("region"):
		region = str(cfg["region"])
	if cfg.has("quota"):
		quota = int(cfg["quota"])
	else:
		quota = 14 if difficulty < 0.35 else (20 if difficulty < 0.7 else 28)
	if cfg.has("targets"):
		target_ids = (cfg["targets"] as Array).duplicate()
	if world != null:
		_populator = WorldPopulator.ensure(world)
		if "airfields" in world:
			var afs: Dictionary = world.get("airfields")
			if not afs.has(GameState.start_airfield):
				var af: Airfield = _populator.get_airfield(GameState.start_airfield)
				if af != null:
					afs[GameState.start_airfield] = af


func start() -> void:
	super.start()
	teleport = teleport or GroundKit.has_arg("--wp-teleport")
	debug_auto = debug_auto or GroundKit.has_arg("--wp-auto")
	if _populator == null:
		_populator = WorldPopulator.ensure(world)
	enemy_side = GroundKit.enemy_of(side)
	if region == "" or not REGIONS.has(region):
		region = "pas_de_calais" if side == "Allies" else "kent"
	var r: Dictionary = REGIONS[region]
	_center = WorldCoords.latlon_to_world(float(r["lat"]), float(r["lon"]))
	_container = Node3D.new()
	_container.name = "GroundAttackTargets"
	world.add_child(_container)
	if target_ids.is_empty():
		_spawn_region()
	for id in target_ids:
		var n: Node = _populator.spawn_target(id)
		if n != null:
			_target_nodes.append(n)
			if n is Convoy:
				_center = (n as Convoy).get_center()
	_build_label()
	if player and is_instance_valid(player):
		var p: Aircraft = player as Aircraft
		p.destroyed.connect(_on_player_destroyed)
		p.crashed.connect(func(_a: Aircraft, r: String) -> void:
			_death_note = "killed - crashed (%s)" % r
			_on_player_destroyed(p, null))
		if teleport:
			var dir: Vector3 = Vector3(0, 0, 1) if enemy_side == "Axis" else Vector3(0, 0, -1)
			var pos: Vector3 = _center - dir * 2200.0
			pos.y = 500.0
			p.reset_pose(pos, WorldCoords.dir_to_heading(dir), true)
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "GROUND ATTACK - %s: destroy %d targets" % [str(r["name"]), quota], 4.0)
	objective_updated.emit("Strafe trains, convoys and tanks over %s (%d)" % [str(r["name"]), quota])
	radio_call("ground_start", 2.0)


func stop() -> void:
	super.stop()
	if _label != null and is_instance_valid(_label):
		_label.queue_free()


func _route_near(kind: String, pos: Vector3, max_d: float) -> RoutePath:
	var list: Array = TransportNetwork.routes_near(kind, pos, max_d)
	if list.is_empty():
		return null
	return list[randi() % list.size()]


func _synthetic_route(a: Vector3, dir: Vector3, length: float) -> RoutePath:
	var pts := PackedVector3Array()
	var side_v := Vector3(-dir.z, 0, dir.x)
	for i in 6:
		var t: float = float(i) / 5.0
		pts.append(a + dir * length * t + side_v * sin(t * 4.0) * 40.0)
	return RoutePath.from_points(pts)


func _spawn_region() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(region) + 7
	# road convoys
	var comps: Array = ["mixed", "supply", "tanks", "troops"]
	for i in 3:
		var rp: RoutePath = _route_near("roads", _center, 6000.0)
		if rp == null or rp.length < 400.0:
			var ang: float = rng.randf() * TAU
			rp = _synthetic_route(_center + Vector3(cos(ang), 0, sin(ang)) * 600.0, Vector3(cos(ang + 1.2), 0, sin(ang + 1.2)), 1600.0)
		var c: Vector2 = rp.closest(_center)
		var cv: Convoy = Convoy.create(enemy_side, rp, false, comps[i % comps.size()], c.x, rng.randf_range(7.0, 11.0))
		cv.spacing = 22.0
		_container.add_child(cv)
		_spawned.append(cv)
	# trains
	for i in 2:
		var rr: RoutePath = _route_near("rails", _center, 7000.0)
		if rr == null or rr.length < 500.0:
			var ang2: float = rng.randf() * TAU
			rr = _synthetic_route(_center + Vector3(cos(ang2), 0, sin(ang2)) * 900.0, Vector3(cos(ang2 + 2.0), 0, sin(ang2 + 2.0)), 2400.0)
		var c2: Vector2 = rr.closest(_center)
		var tr: Train = Train.create(enemy_side, rr, c2.x, 14.0)
		_container.add_child(tr)
		_spawned.append(tr)
	# tank groups (idle / firing) with AA cover
	for g in 3:
		var base: Vector3 = _center + Vector3(rng.randf_range(-1800, 1800), 0, rng.randf_range(-1800, 1800))
		if GroundKit.raw_y(base.x, base.z) < 2.0:
			base = _center
		var tank_types: Array = ["panzer4", "tiger", "panzer4"] if enemy_side == "Axis" else ["sherman", "sherman", "sherman"]
		for k in 3:
			var v: GroundVehicle = GroundVehicle.create(tank_types[k], enemy_side, null, 0.0, 0.0, "fire" if k != 1 else "idle")
			var p: Vector3 = base + Vector3(rng.randf_range(-60, 60), 0, rng.randf_range(-60, 60))
			v.position = Vector3(p.x, GroundKit.ground_y(p.x, p.z), p.z)
			v.rotation.y = rng.randf() * TAU
			_container.add_child(v)
		var art: GroundVehicle = GroundVehicle.create("artillery", enemy_side, null, 0.0, 0.0, "fire")
		art.position = Vector3(base.x + 40.0, GroundKit.ground_y(base.x + 40.0, base.z), base.z)
		_container.add_child(art)
		_populator._defences(_container, base, enemy_side, 1 if g == 0 else 0, 2, 0, 0, 160.0, rng.randi())
	# troop column on foot
	var tcol: GroundVehicle = GroundVehicle.create("troops", enemy_side, _synthetic_route(_center + Vector3(300, 0, 0), Vector3(1, 0, 0.4).normalized(), 900.0), 0.0, 3.0, "move")
	_container.add_child(tcol)


func _build_label() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.82))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 4)
	if hud and hud.has_method("add_widget"):
		hud.call("add_widget", _label)


func _classify(n: Node) -> String:
	if n is GroundVehicle:
		return "tanks" if (n as GroundVehicle).vtype in ["sherman", "panzer4", "tiger"] else "vehicles"
	if n is TrainCar:
		return "trains"
	if n is GroundShip:
		return "ships"
	if n is AAGun:
		return "aa"
	return ""


func _scan_kills() -> void:
	for n in get_tree().get_nodes_in_group("destroyed_target"):
		var id: int = n.get_instance_id()
		if _counted.has(id) or not (n is GroundTarget):
			continue
		var gt: GroundTarget = n as GroundTarget
		if gt.team != enemy_side:
			continue
		var cls: String = _classify(gt)
		if cls == "":
			continue
		_counted[id] = true
		kills[cls] = int(kills[cls]) + 1
		total_kills += 1
		add_score(gt.points)
		if hud and hud.has_method("show_message") and total_kills % 5 == 0:
			hud.call("show_message", "%d kills" % total_kills, 1.5)
			radio_call_any("ground_kills", 3)
	var done_targets: bool = not _target_nodes.is_empty()
	for t in _target_nodes:
		if is_instance_valid(t) and not bool(t.call("is_destroyed")):
			done_targets = false
	if (target_ids.is_empty() and total_kills >= quota) or (not target_ids.is_empty() and done_targets):
		add_score(1000)
		finish(true, _stats())


func nav_point() -> Variant:
	var p: Variant = _nearest_pos(_target_nodes)
	return p if p != null else (_center if _center != Vector3.ZERO else null)


func _stats() -> Dictionary:
	return {"kills": total_kills, "tanks": kills["tanks"], "vehicles": kills["vehicles"], "trains": kills["trains"], "ships": kills["ships"], "aa": kills["aa"]}


func _on_player_destroyed(_a: Node, _k: Node) -> void:
	if _player_dead or not running:
		return
	_player_dead = true
	var st: Dictionary = _stats()
	st["reason"] = _death_note if _death_note != "" else "killed - shot down"
	finish(false, st)


func _process(delta: float) -> void:
	super._process(delta)
	if not running:
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.4
		_scan_kills()
	_label_t -= delta
	if _label_t <= 0.0 and _label != null and is_instance_valid(_label):
		_label_t = 0.25
		var t: String = "GROUND ATTACK  %s\nTANKS %d  VEHICLES %d  TRAINS %d  SHIPS %d  AA %d\nKILLS %d / %d   SCORE %d" % [
			str(REGIONS[region]["name"]).to_upper(), kills["tanks"], kills["vehicles"], kills["trains"], kills["ships"], kills["aa"], total_kills, quota, score]
		if player != null:
			var to: Vector3 = _center - player.global_position
			t += "\nAREA %.1f km  BRG %03d" % [Vector2(to.x, to.z).length() * WorldCoords.HORIZ_COMPRESSION / 1000.0, int(WorldCoords.dir_to_heading(Vector3(to.x, 0, to.z)))]
		_label.text = t
	if debug_auto:
		_debug_t -= delta
		if _debug_t <= 0.0:
			_debug_t = 0.4
			var n: int = 0
			for s in _spawned:
				for u in (s as Node).get_children():
					if u is GroundTarget and not (u as GroundTarget).is_dead and n < 3:
						(u as GroundTarget).take_damage(99999.0, player)
						n += 1
