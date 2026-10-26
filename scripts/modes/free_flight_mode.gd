class_name FreeFlightMode
extends ModeBase
## Free flight: no objectives. Optional ambient dogfights (small AI skirmishes near the player), and optional
## Ops Room taskings (cfg "taskings"): every 10 minutes the radio sends the player after a new target with a
## waypoint on the compass and minimap (see OpsRoom).
## configure(cfg): side, ambient (bool), taskings (bool), tasking_interval (s), difficulty.

var ambient_dogfights: bool = false
var side: String = "Allies"
var difficulty: float = 0.4
var _t: float = 10.0            # set in start(): first skirmish after a few quiet minutes
var _ambient: Array[Aircraft] = []
var taskings: bool = false
var tasking_interval: float = 600.0
var ops: OpsRoom
var passing_on: bool = true       # friendly flights you come across and can join (PassingFlights)
var passing: PassingFlights


func configure(cfg: Dictionary) -> void:
	side = String(cfg.get("side", GameState.player_side))
	ambient_dogfights = bool(cfg.get("ambient", false)) and not bool(cfg.get("no_fighters", false))
	difficulty = float(cfg.get("difficulty", 0.4))
	taskings = bool(cfg.get("taskings", false)) or OS.get_cmdline_user_args().has("--taskings")
	tasking_interval = float(cfg.get("tasking_interval", 600.0))
	passing_on = bool(cfg.get("passing_flights", true)) and not OS.get_cmdline_user_args().has("--no-passing")


## Most AI aircraft alive at once in free flight (all dynamic traffic shares it; wingmen count too).
const AI_CAP: int = 30


func start() -> void:
	super.start()
	AIFactory.ai_cap = AI_CAP
	objective_updated.emit("Free flight")
	_t = randf_range(90.0, 150.0)
	if ambient_dogfights:
		var sm := SortieManager.new()
		sm.name = "SortieManager"
		world.add_child(sm)
		sm.setup(world, player, hud, difficulty, 4.0 if OS.get_cmdline_user_args().has("--sortie-test") else SortieManager.FIRST_DELAY)
	if taskings and player is Aircraft:
		ops = OpsRoom.new()
		ops.name = "OpsRoom"
		ops.interval = tasking_interval
		add_child(ops)
		ops.setup(world, player as Aircraft, hud, self, side, difficulty)
		objective_updated.emit("Free flight - the Ops Room will call with taskings")
	if passing_on and player is Aircraft:
		passing = PassingFlights.new()
		passing.name = "PassingFlights"
		add_child(passing)
		passing.setup(world, player as Aircraft, hud, self, side, difficulty)
		passing.ops = ops
	if hud and hud.has_method("show_message"):
		var msg: String = "Free flight - Ops Room taskings every %d min" % int(tasking_interval / 60.0) if taskings else "Free flight - no objectives"
		hud.call("show_message", msg + ("  (ambient dogfights on)" if ambient_dogfights else ""), 4.0)


func stop() -> void:
	AIFactory.ai_cap = 0
	if ops != null and is_instance_valid(ops):
		ops.queue_free()
	ops = null
	if passing != null and is_instance_valid(passing):
		passing.queue_free()
	passing = null
	super.stop()


func nav_point() -> Variant:
	if passing != null and is_instance_valid(passing):
		var pn: Variant = passing.nav_point()
		if pn != null:
			return pn             # flying with a flight you joined
	if ops != null and is_instance_valid(ops):
		return ops.nav_point()
	return null


## Chart pins (key M): only what the Ops Room has announced.
func map_pins() -> Array:
	if ops != null and is_instance_valid(ops):
		return ops.map_pins()
	return []


func _stats() -> Dictionary:
	var d: Dictionary = {}
	if ops != null and is_instance_valid(ops):
		d = {"taskings_done": ops.completed, "taskings_missed": ops.failed}
	if passing != null and is_instance_valid(passing) and passing.joined_count > 0:
		d["flights_joined"] = passing.joined_count
	return d


func _process(delta: float) -> void:
	super._process(delta)
	if ops != null and is_instance_valid(ops):
		ops.set_process(running)
	if not running or not ambient_dogfights or player == null or not is_instance_valid(player):
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = randf_range(120.0, 210.0)
	var alive: Array[Aircraft] = []
	for a in _ambient:
		if is_instance_valid(a) and a.state == Aircraft.State.ALIVE:
			alive.append(a)
	_ambient = alive
	if _ambient.size() > 6 or AIFactory.ai_room(get_tree()) < 4:
		return
	_spawn_skirmish()


func _spawn_skirmish() -> void:
	var other: String = AircraftCatalog.opposite(side)
	var center: Vector3 = player.global_position + WorldCoords.heading_to_dir(randf() * 360.0) * randf_range(9000.0, 14000.0)
	center.y = maxf(player.global_position.y + randf_range(-100.0, 300.0), 700.0)
	var friend_pool: Array = AircraftCatalog.fighters_for_side(side).filter(func(i: String) -> bool: return i != "me262")
	var foe_pool: Array = AircraftCatalog.fighters_for_side(other).filter(func(i: String) -> bool: return i != "me262")
	for i in 2:
		var off: Vector3 = Vector3(-500.0 + 150.0 * i, 0, 0)
		var f: Aircraft = AIFactory.spawn(world, friend_pool[randi() % friend_pool.size()], side, center + off, 90.0, -1.0, difficulty)
		var e: Aircraft = AIFactory.spawn(world, foe_pool[randi() % foe_pool.size()], other, center - off, 270.0, -1.0, difficulty)
		for a in [f, e]:
			var p: AIPilot = AIFactory.pilot_of(a)
			p.detect_range = 4500.0      # normal visual range: they fight each other unless the player joins in
			(a as Aircraft).crashed.connect(func(x: Aircraft, _r: String) -> void: _free_later(x, 2.5))
			_ambient.append(a)
			AIFactory.add_marker(hud, a, Color(0.3, 0.75, 1.0) if a == f else Color(1.0, 0.25, 0.2))


func _free_later(a: Aircraft, t: float) -> void:
	if not is_instance_valid(a):
		return
	await a.get_tree().create_timer(t).timeout
	if is_instance_valid(a):
		a.queue_free()
