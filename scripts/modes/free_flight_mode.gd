class_name FreeFlightMode
extends ModeBase
## Free flight: no objectives. Optional ambient dogfights (small AI skirmishes near the player), and optional
## Ops Room taskings (cfg "taskings"): every 10 minutes the radio sends the player after a new target with a
## waypoint on the compass and minimap (see OpsRoom).
## configure(cfg): side, ambient (bool), taskings (bool), tasking_interval (s), difficulty.

var ambient_dogfights: bool = false
var side: String = "Allies"
var difficulty: float = 0.4
var taskings: bool = false
var tasking_interval: float = 600.0
var ops: OpsRoom
var passing_on: bool = true       # friendly flights you come across and can join (PassingFlights)
var passing: PassingFlights
var naval: NavalSkirmish          # occasional sea fights near convoys (scripts/ground/naval_skirmish.gd)
var flights: EnemyFlights         # the other side's flights, each with a mission (ambient flights on)
const LandBattles := preload("res://scripts/ground/land_battles.gd")
var land_battles: Node            # occasional tank / infantry battles with a radio call (scripts/ground/land_battles.gd)


func configure(cfg: Dictionary) -> void:
	side = String(cfg.get("side", GameState.player_side))
	ambient_dogfights = bool(cfg.get("ambient", false)) and not bool(cfg.get("no_fighters", false))
	difficulty = float(cfg.get("difficulty", 0.4))
	taskings = bool(cfg.get("taskings", false)) or OS.get_cmdline_user_args().has("--taskings")
	tasking_interval = float(cfg.get("tasking_interval", 600.0))
	passing_on = bool(cfg.get("passing_flights", true)) and not OS.get_cmdline_user_args().has("--no-passing")
	# Free flight had no wingman count of its own, so the base default stayed at zero unless the map
	# planner supplied one. Give fighter starts the normal pair; bomber crews still fly alone.
	var want: int = int(cfg.get("wingmen", 2))
	if player is Aircraft and (player as Aircraft).stats != null and AircraftCatalog.is_bomber((player as Aircraft).stats.id):
		want = 0
	wingmen_wanted = clampi(want, 0, WINGMEN_MAX)


## Most AI aircraft alive at once in free flight (all dynamic traffic shares it; wingmen count too).
const AI_CAP: int = 40


func start() -> void:
	super.start()
	AIFactory.ai_cap = AI_CAP
	objective_updated.emit("Free flight")
	if ambient_dogfights:
		var sm := SortieManager.new()
		sm.name = "SortieManager"
		world.add_child(sm)
		sm.setup(world, player, hud, difficulty, 4.0 if OS.get_cmdline_user_args().has("--sortie-test") else SortieManager.FIRST_DELAY)
	if ambient_dogfights and player is Aircraft:
		flights = EnemyFlights.new()
		flights.name = "EnemyFlights"
		add_child(flights)
		flights.setup(world, player as Aircraft, hud, side, difficulty)
	if (ambient_dogfights or OS.get_cmdline_user_args().has("--naval-test")) and player is Aircraft:
		# occasional sea fights near the convoys (E-boats, MTBs, destroyers) with a radio call for air support
		naval = NavalSkirmish.new()
		naval.name = "NavalSkirmish"
		add_child(naval)
		naval.setup(world, player as Aircraft, hud, side, difficulty)
	if (ambient_dogfights or OS.get_cmdline_user_args().has("--battle-test")) and player is Aircraft:
		# occasional land battles (tanks and infantry) at plausible sites, announced on the radio
		land_battles = LandBattles.new()
		land_battles.name = "LandBattles"
		add_child(land_battles)
		land_battles.setup(world, player as Aircraft, hud, side, difficulty)
	if (ambient_dogfights or OS.get_cmdline_user_args().has("--guns-event")) and side == "Allies" and player is Aircraft and not OS.get_cmdline_user_args().has("--no-guns"):
		# the cross-Channel guns shell Dover now and then (scripts/ground/gun_shelling.gd): radio call, then attack the batteries
		GunShelling.ensure(world).enable_ambient(player, hud, 6.0 if OS.get_cmdline_user_args().has("--guns-event") else GunShelling.AMBIENT_FIRST)
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
	var gs_stop: GunShelling = GunShelling.instance()
	if gs_stop != null:
		gs_stop.disable_ambient()
		gs_stop.stop()
	if ops != null and is_instance_valid(ops):
		ops.queue_free()
	ops = null
	if flights != null and is_instance_valid(flights):
		flights.queue_free()
	flights = null
	if naval != null and is_instance_valid(naval):
		naval.cleanup()
		naval.queue_free()
	naval = null
	if land_battles != null and is_instance_valid(land_battles):
		land_battles.queue_free()
	land_battles = null
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
	if land_battles != null and is_instance_valid(land_battles):
		return land_battles.nav_point()       # the nearest battle that wants air support
	var gs_nav: GunShelling = GunShelling.instance()
	if gs_nav != null and gs_nav.active and player != null and is_instance_valid(player):
		var nb: String = gs_nav.nearest_battery(player.global_position)
		if nb != "":
			return gs_nav.rec(nb)["pos"]       # the shelling batteries
	return null


## Chart pins (key M): what the Ops Room has announced, and the tank battles.
func map_pins() -> Array:
	var out: Array = []
	if ops != null and is_instance_valid(ops):
		out = ops.map_pins()
	if land_battles != null and is_instance_valid(land_battles):
		out.append_array(land_battles.map_pins())
	return out


## The ops room's current strike tasking (a factory, a radar station...).
func strike_targets() -> Array:
	if ops != null and is_instance_valid(ops):
		return ops.strike_targets()
	return []


func _stats() -> Dictionary:
	var d: Dictionary = {}
	if ops != null and is_instance_valid(ops):
		d = {"taskings_done": ops.completed, "taskings_missed": ops.failed}
	if passing != null and is_instance_valid(passing) and passing.joined_count > 0:
		d["flights_joined"] = passing.joined_count
	if land_battles != null and is_instance_valid(land_battles):
		var bs: Dictionary = land_battles.stats()
		if int(bs.get("battles_seen", 0)) > 0:
			d["battle_kills"] = bs["battle_kills"]
			d["battle_friendly_fire"] = bs["battle_friendly_fire"]
	return d


func _process(delta: float) -> void:
	super._process(delta)
	if ops != null and is_instance_valid(ops):
		ops.set_process(running)
	if flights != null and is_instance_valid(flights):
		flights.set_process(running)
	if naval != null and is_instance_valid(naval):
		naval.set_process(running)
	if land_battles != null and is_instance_valid(land_battles):
		land_battles.set_process(running)
