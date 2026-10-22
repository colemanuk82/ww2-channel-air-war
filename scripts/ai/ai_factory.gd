class_name AIFactory
extends RefCounted
## Spawns AI-controlled aircraft.
##   var ac := AIFactory.spawn(world, "bf109", "Axis", pos, heading_deg, speed, 0.5)            # fighter AI
##   var wm := AIFactory.spawn(world, "spitfire", "Allies", pos, hdg, -1.0, 0.7, AIPilot.Role.WINGMAN, player)
## Underlying recipe: instantiate aircraft_base.tscn, set stats, player_controlled=false, team, add_child, reset_pose.

const AIRCRAFT_SCENE := "res://scenes/aircraft/aircraft_base.tscn"

## Budget for AI aircraft alive at once (0 = unlimited). Free flight sets it (FreeFlightMode.AI_CAP) so the
## dynamic traffic - passing flights, ambient raids and skirmishes, Ops Room taskings - never piles up.
static var ai_cap: int = 0


## Live AI aircraft in the world (the player and wrecks are not counted).
static func ai_live(tree: SceneTree) -> int:
	var n: int = 0
	for a in tree.get_nodes_in_group("aircraft"):
		var ac: Aircraft = a as Aircraft
		if ac != null and not ac.player_controlled and ac.state != Aircraft.State.DEAD:
			n += 1
	return n


## How many more AI aircraft the budget allows (a large number when there is no cap).
static func ai_room(tree: SceneTree) -> int:
	return 1000 if ai_cap <= 0 else maxi(0, ai_cap - ai_live(tree))


static func spawn(parent: Node, stats_id: String, team: String, pos: Vector3, heading_deg: float, speed: float = -1.0, difficulty: float = 0.5, role: int = AIPilot.Role.FIGHTER, leader: Node3D = null, on_ground: bool = false) -> Aircraft:
	var packed: PackedScene = load(AIRCRAFT_SCENE)
	var ac: Aircraft = packed.instantiate() as Aircraft
	ac.stats = AircraftCatalog.load_stats(stats_id)
	if role == AIPilot.Role.BOMBER_LEADER or role == AIPilot.Role.BOMBER_FOLLOWER:
		# AI bombers (every spawn route: formations, sorties, events) get a lower top speed than the flyable version so
		# fighters can always catch and escort them; the catalog bombers are as fast as the fighters.
		ac.stats = ac.stats.duplicate() as AircraftStats
		ac.stats.max_speed = minf(ac.stats.max_speed * 0.78, AIPilot.BOMBER_CRUISE_CAP * 1.15)
	ac.player_controlled = false
	ac.team = team
	ac.start_gear_down = on_ground
	parent.add_child(ac)
	ac.reset_pose(pos, heading_deg, not on_ground, speed)
	var pilot: AIPilot = AIPilot.attach(ac, role, difficulty)
	if leader != null:
		pilot.set_leader(leader, Vector3(70, -5, 90))
	return ac


static func pilot_of(ac: Aircraft) -> AIPilot:
	return ac.get_node_or_null("AIPilot") as AIPilot


## Registers a minimap marker and unregisters it the moment `n` leaves the tree
## (the HUD would otherwise assign a freed instance while drawing).
static func add_marker(hud: Node, n: Node3D, color: Color) -> void:
	if hud == null or not hud.has_method("register_minimap_marker"):
		return
	hud.call("register_minimap_marker", n, color)
	n.tree_exiting.connect(func() -> void:
		var arr: Variant = hud.get("_markers")
		if arr is Array and is_instance_valid(hud):
			for i in range((arr as Array).size() - 1, -1, -1):
				if (arr as Array)[i][0] == n:
					(arr as Array).remove_at(i), CONNECT_ONE_SHOT)
