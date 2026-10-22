class_name GroundVehicle
extends GroundTarget
## Tanks (sherman / panzer4 / tiger), trucks, halftracks, jeeps, artillery and troop columns.
## Follows a RoutePath (road polyline) or sits idle / fires. Visuals are exaggerated by VIS for visibility.
## Create with GroundVehicle.create(type, team, route, start_s, speed, mode). Add under a node at the world origin.

const VIS: float = 2.2
const TYPES := {
	"sherman": {"hp": 90.0, "r": 7.5, "pts": 150, "armor": 0.6},
	"panzer4": {"hp": 90.0, "r": 7.5, "pts": 150, "armor": 0.6},
	"tiger": {"hp": 200.0, "r": 9.0, "pts": 300, "armor": 0.4},
	"truck": {"hp": 40.0, "r": 6.0, "pts": 60, "armor": 1.0},
	"halftrack": {"hp": 55.0, "r": 6.5, "pts": 80, "armor": 0.9},
	"jeep": {"hp": 25.0, "r": 4.0, "pts": 40, "armor": 1.0},
	"artillery": {"hp": 60.0, "r": 6.0, "pts": 100, "armor": 0.8},
	"troops": {"hp": 40.0, "r": 10.0, "pts": 50, "armor": 1.0},
	"kubel": {"hp": 25.0, "r": 4.0, "pts": 40, "armor": 1.0},      # VW Kubelwagen (German light car)
	"car": {"hp": 12.0, "r": 3.2, "pts": 5, "armor": 1.0},
	"bus": {"hp": 25.0, "r": 5.0, "pts": 10, "armor": 1.0},
	"crew": {"hp": 15.0, "r": 4.0, "pts": 10, "armor": 1.0},         # airfield ground crew (small working group)
	"bowser": {"hp": 45.0, "r": 6.0, "pts": 90, "armor": 1.0},       # refuelling bowser: burns well
	"tug": {"hp": 30.0, "r": 4.0, "pts": 40, "armor": 1.0},          # aircraft tractor
	"firetender": {"hp": 40.0, "r": 6.0, "pts": 50, "armor": 1.0},
	"bombcart": {"hp": 30.0, "r": 5.0, "pts": 70, "armor": 1.0},     # tractor with two bomb trolleys
}

var vtype: String = "sherman"
var route: RoutePath
var s: float = 0.0
var dir: float = 1.0
var speed: float = 8.0
var mode: String = "move"        # move | idle | fire
var wrap: bool = true
var _vis: Node3D
var _turret: Node3D
var _tip: Node3D
var _fire_t: float = 2.0
var _yaw: float = 0.0
var _frame: int = 0
var _troops: MultiMeshInstance3D
var _troop_n: int = 12
var _troop_t: float = 0.0
var _pitch: float = 0.0


static func create(p_type: String, p_team: String, p_route: RoutePath, start_s: float = 0.0, p_speed: float = 8.0, p_mode: String = "move") -> GroundVehicle:
	var v := GroundVehicle.new()
	v.vtype = p_type
	v.team = p_team
	v.route = p_route
	v.s = start_s
	v.speed = p_speed
	v.mode = p_mode
	var cfg: Dictionary = TYPES.get(p_type, TYPES["truck"])
	v.max_health = cfg["hp"]
	v.hit_radius = cfg["r"]
	v.points = cfg["pts"]
	v.small_mult = cfg["armor"]
	v.kind = p_type
	v.display_name = p_type.capitalize()
	v.explosion_size = 1.0 if p_type != "tiger" else 1.4
	v.smoke_scale = 0.8
	v.smoke_height = 2.5
	v._fire_t = randf_range(1.0, 5.0)
	if p_type == "crew":
		v._troop_n = 5
	if p_type == "bowser":
		v.explosion_size = 1.8
		v.smoke_scale = 1.2
	return v


func _post_ready() -> void:
	_frame = randi() % 4
	add_to_group("vehicle")
	if mode == "move" and route != null and route.length > 1.0:
		_place(0.0, true)
	else:
		_ground(true)


# ------------------------------------------------------------------ models
func _build_intact(root: Node3D) -> void:
	_vis = Node3D.new()
	_vis.scale = Vector3.ONE * VIS
	root.add_child(_vis)
	var c: Color = GroundKit.team_color(team)
	match vtype:
		"sherman":
			_build_tank(c, 5.8, 2.6, 0.9, 1.0, 0.0, false)
		"panzer4":
			_build_tank(c, 5.9, 2.8, 0.9, 1.0, 1.0, true)
		"tiger":
			_build_tank(c, 7.0, 3.6, 1.1, 1.1, 1.8, true)
		"truck":
			_build_truck(c if team != "Neutral" else Color(0.25, 0.3, 0.42))     # civilian lorries are not army green
		"kubel":
			_build_kubel(c)
		"halftrack":
			_build_halftrack(c)
		"jeep":
			_build_jeep(c)
		"artillery":
			_build_gun(c)
		"troops", "crew":
			_build_troops()
		"bowser":
			_build_bowser(c)
		"tug":
			_build_tug(c)
		"firetender":
			_build_firetender()
		"bombcart":
			_build_bombcart(c)
		"car":
			_build_car()
		"bus":
			_build_bus()
		_:
			_build_truck(c)


func _build_tank(c: Color, length: float, width: float, hull_h: float, turret_s: float, barrel_extra: float, skirts: bool) -> void:
	var dark: Color = c.darkened(0.45)
	GroundKit.box(_vis, Vector3(width * 0.78, hull_h, length * 0.92), Vector3(0, 0.75 + hull_h * 0.5, 0), c)
	GroundKit.box(_vis, Vector3(width * 0.9, 0.35, length * 0.2), Vector3(0, 0.95, -length * 0.47), c, Vector3(-28, 0, 0))    # glacis
	for sx in [-1.0, 1.0]:
		GroundKit.box(_vis, Vector3(width * 0.2, 0.85, length), Vector3(sx * width * 0.42, 0.55, 0), dark)                  # track
		if skirts:
			GroundKit.box(_vis, Vector3(0.12, 0.7, length * 0.7), Vector3(sx * (width * 0.52), 0.95, 0.2), c.darkened(0.15))
	_turret = Node3D.new()
	_turret.position = Vector3(0, 0.75 + hull_h, -0.2)
	_vis.add_child(_turret)
	GroundKit.box(_turret, Vector3(width * 0.62 * turret_s, 0.8 * turret_s, length * 0.42 * turret_s), Vector3(0, 0.4 * turret_s, 0), c)
	GroundKit.box(_turret, Vector3(0.7, 0.6, 0.7), Vector3(0.45, 0.95 * turret_s, 0.25), c.darkened(0.1))                     # cupola
	var blen: float = 3.2 + barrel_extra
	GroundKit.cyl(_turret, 0.11, 0.14, blen, Vector3(0, 0.45 * turret_s, -length * 0.21 * turret_s - blen * 0.5 + 0.2), dark, Vector3(90, 0, 0), 6)
	_tip = Node3D.new()
	_tip.position = Vector3(0, 0.45 * turret_s, -length * 0.21 * turret_s - blen + 0.2)
	_turret.add_child(_tip)


func _build_truck(c: Color) -> void:
	var dark: Color = c.darkened(0.5)
	GroundKit.box(_vis, Vector3(2.0, 1.5, 1.7), Vector3(0, 1.4, -2.0), c)                       # cab
	GroundKit.box(_vis, Vector3(2.2, 0.3, 4.2), Vector3(0, 0.8, 1.0), dark)                      # bed base
	GroundKit.box(_vis, Vector3(2.2, 1.6, 3.8), Vector3(0, 1.8, 1.1), c.lerp(Color(0.45, 0.4, 0.28), 0.5), Vector3.ZERO)  # canvas
	for z in [-2.0, 1.0, 2.4]:
		for sx in [-1.0, 1.0]:
			GroundKit.cyl(_vis, 0.5, 0.5, 0.35, Vector3(sx * 1.1, 0.5, z), GroundKit.COL_DARK, Vector3(0, 0, 90), 8, false)


func _build_bowser(c: Color) -> void:
	var dark: Color = c.darkened(0.5)
	GroundKit.box(_vis, Vector3(2.0, 1.5, 1.7), Vector3(0, 1.4, -2.2), c)
	GroundKit.box(_vis, Vector3(2.2, 0.3, 4.6), Vector3(0, 0.8, 1.0), dark)
	GroundKit.cyl(_vis, 1.0, 1.0, 4.4, Vector3(0, 1.9, 1.0), Color(0.62, 0.64, 0.62) if team == "Allies" else Color(0.4, 0.42, 0.4), Vector3(90, 0, 0), 12)
	GroundKit.box(_vis, Vector3(2.1, 0.25, 0.5), Vector3(0, 2.0, 1.0), Color(0.75, 0.15, 0.1))    # red band: AVGAS
	GroundKit.cyl(_vis, 0.12, 0.12, 1.2, Vector3(0.9, 1.0, 3.1), GroundKit.COL_DARK, Vector3(0, 0, 90), 5, false)
	for z in [-2.2, 0.4, 2.0]:
		for sx in [-1.0, 1.0]:
			GroundKit.cyl(_vis, 0.5, 0.5, 0.35, Vector3(sx * 1.1, 0.5, z), GroundKit.COL_DARK, Vector3(0, 0, 90), 8, false)


func _build_tug(c: Color) -> void:
	GroundKit.box(_vis, Vector3(1.4, 0.9, 2.2), Vector3(0, 1.0, 0), c.lightened(0.1))
	GroundKit.box(_vis, Vector3(1.0, 0.8, 0.9), Vector3(0, 1.8, 0.4), c.darkened(0.1))
	GroundKit.cyl(_vis, 0.08, 0.08, 1.0, Vector3(0, 2.6, -0.7), GroundKit.COL_DARK, Vector3.ZERO, 5, false)
	for sx in [-1.0, 1.0]:
		GroundKit.cyl(_vis, 0.6, 0.6, 0.4, Vector3(sx * 0.85, 0.6, 0.6), GroundKit.COL_DARK, Vector3(0, 0, 90), 8, false)
		GroundKit.cyl(_vis, 0.35, 0.35, 0.3, Vector3(sx * 0.85, 0.4, -0.8), GroundKit.COL_DARK, Vector3(0, 0, 90), 8, false)


func _build_firetender() -> void:
	var red: Color = Color(0.72, 0.12, 0.1)
	GroundKit.box(_vis, Vector3(2.0, 1.6, 1.8), Vector3(0, 1.4, -2.0), red)
	GroundKit.box(_vis, Vector3(2.2, 1.4, 3.6), Vector3(0, 1.4, 1.2), red.darkened(0.1))
	GroundKit.box(_vis, Vector3(0.35, 0.2, 4.4), Vector3(0, 2.4, 0.8), Color(0.75, 0.7, 0.6))
	GroundKit.cyl(_vis, 0.5, 0.5, 1.6, Vector3(0, 2.4, 2.6), Color(0.75, 0.7, 0.2), Vector3(0, 0, 90), 8, false)
	for z in [-2.0, 0.6, 2.4]:
		for sx in [-1.0, 1.0]:
			GroundKit.cyl(_vis, 0.5, 0.5, 0.35, Vector3(sx * 1.1, 0.5, z), GroundKit.COL_DARK, Vector3(0, 0, 90), 8, false)


func _build_bombcart(c: Color) -> void:
	_build_tug(c)
	for k in 2:
		var z: float = 3.2 + float(k) * 3.4
		GroundKit.box(_vis, Vector3(1.4, 0.2, 2.8), Vector3(0, 0.7, z), c.darkened(0.3))
		GroundKit.cyl(_vis, 0.32, 0.32, 2.6, Vector3(0, 1.1, z), Color(0.42, 0.4, 0.2), Vector3(90, 0, 0), 8)
		for sx in [-1.0, 1.0]:
			GroundKit.cyl(_vis, 0.3, 0.3, 0.2, Vector3(sx * 0.75, 0.3, z), GroundKit.COL_DARK, Vector3(0, 0, 90), 6, false)


func _build_halftrack(c: Color) -> void:
	var dark: Color = c.darkened(0.5)
	GroundKit.box(_vis, Vector3(2.2, 1.3, 5.0), Vector3(0, 1.3, 0), c)
	GroundKit.box(_vis, Vector3(2.0, 0.6, 1.8), Vector3(0, 2.0, -1.2), c.darkened(0.1))
	for sx in [-1.0, 1.0]:
		GroundKit.box(_vis, Vector3(0.5, 0.8, 2.6), Vector3(sx * 1.0, 0.5, 1.2), dark)
		GroundKit.cyl(_vis, 0.45, 0.45, 0.3, Vector3(sx * 1.0, 0.45, -1.9), GroundKit.COL_DARK, Vector3(0, 0, 90), 8, false)


## Civilian saloon in a random 1940s paint colour (black, grey, maroon, green, cream, blue).
func _build_car() -> void:
	var cols: Array = [Color(0.08, 0.08, 0.09), Color(0.32, 0.33, 0.35), Color(0.38, 0.1, 0.1), Color(0.14, 0.26, 0.17), Color(0.75, 0.7, 0.55), Color(0.15, 0.2, 0.36)]
	var c: Color = cols[randi() % cols.size()]
	var dark: Color = c.darkened(0.45)
	GroundKit.box(_vis, Vector3(1.5, 0.62, 2.0), Vector3(0, 1.05, 0.55), c)                     # body / boot
	GroundKit.box(_vis, Vector3(1.2, 0.7, 1.3), Vector3(0, 1.1, -1.25), c)                      # long bonnet
	GroundKit.box(_vis, Vector3(1.32, 0.85, 1.45), Vector3(0, 1.72, 0.45), c.lightened(0.04))   # tall upright cabin
	GroundKit.box(_vis, Vector3(1.38, 0.1, 1.55), Vector3(0, 2.17, 0.45), dark)                 # roof
	GroundKit.box(_vis, Vector3(1.12, 0.55, 0.06), Vector3(0, 1.8, -0.3), Color(0.5, 0.58, 0.64), Vector3(-8, 0, 0), false)   # upright windscreen
	GroundKit.box(_vis, Vector3(0.7, 0.75, 0.1), Vector3(0, 1.1, -1.95), Color(0.75, 0.75, 0.72))   # upright chrome radiator grille
	for sx in [-1.0, 1.0]:
		GroundKit.box(_vis, Vector3(0.28, 0.12, 3.0), Vector3(sx * 0.82, 0.62, 0.0), dark, Vector3.ZERO, false)      # running boards
		GroundKit.box(_vis, Vector3(0.34, 0.12, 0.95), Vector3(sx * 0.82, 1.0, -1.35), dark, Vector3.ZERO, false)    # front wings
		GroundKit.box(_vis, Vector3(0.34, 0.12, 0.95), Vector3(sx * 0.82, 1.0, 1.15), dark, Vector3.ZERO, false)     # rear wings
		GroundKit.cyl(_vis, 0.12, 0.12, 0.1, Vector3(sx * 0.5, 1.2, -2.0), Color(0.9, 0.88, 0.7), Vector3(90, 0, 0), 6, false)   # headlamps
	for z in [-1.3, 1.15]:
		for sx in [-1.0, 1.0]:
			GroundKit.cyl(_vis, 0.36, 0.36, 0.22, Vector3(sx * 0.82, 0.4, z), GroundKit.COL_DARK, Vector3(0, 0, 90), 8, false)


func _build_bus() -> void:
	var c: Color = Color(0.55, 0.12, 0.1) if randf() < 0.6 else Color(0.2, 0.3, 0.2)
	GroundKit.box(_vis, Vector3(2.1, 2.3, 5.6), Vector3(0, 1.75, 0.8), c)                       # upright body
	GroundKit.box(_vis, Vector3(1.8, 0.35, 5.4), Vector3(0, 3.0, 0.8), c.darkened(0.15))         # roof
	GroundKit.box(_vis, Vector3(2.14, 0.65, 5.0), Vector3(0, 2.25, 0.8), Color(0.55, 0.62, 0.66), Vector3.ZERO, false)   # window band
	GroundKit.box(_vis, Vector3(1.7, 1.3, 1.6), Vector3(0, 1.2, -2.8), c)                       # engine bonnet ("half-cab")
	GroundKit.box(_vis, Vector3(1.0, 0.9, 0.1), Vector3(0, 1.2, -3.65), Color(0.75, 0.75, 0.72))  # radiator
	for z in [-2.6, 2.3]:
		for sx in [-1.0, 1.0]:
			GroundKit.cyl(_vis, 0.5, 0.5, 0.3, Vector3(sx * 1.0, 0.5, z), GroundKit.COL_DARK, Vector3(0, 0, 90), 8, false)


## Volkswagen Kubelwagen: flat-sided open German army car with a spare wheel on the bonnet.
func _build_kubel(c: Color) -> void:
	GroundKit.box(_vis, Vector3(1.55, 0.7, 3.3), Vector3(0, 0.95, 0), c)
	GroundKit.box(_vis, Vector3(1.4, 0.55, 0.12), Vector3(0, 1.55, -0.55), c.darkened(0.15))     # upright windscreen
	GroundKit.box(_vis, Vector3(1.45, 0.08, 1.4), Vector3(0, 1.88, 0.45), Color(0.3, 0.28, 0.2), Vector3.ZERO, false)  # folded canvas hood
	GroundKit.cyl(_vis, 0.38, 0.38, 0.22, Vector3(0, 1.45, -1.3), GroundKit.COL_DARK, Vector3(80, 0, 0), 8, false)     # spare wheel
	for z in [-1.1, 1.1]:
		for sx in [-1.0, 1.0]:
			GroundKit.cyl(_vis, 0.4, 0.4, 0.25, Vector3(sx * 0.85, 0.42, z), GroundKit.COL_DARK, Vector3(0, 0, 90), 8, false)


func _build_jeep(c: Color) -> void:
	GroundKit.box(_vis, Vector3(1.6, 0.7, 3.2), Vector3(0, 0.9, 0), c)
	GroundKit.box(_vis, Vector3(1.4, 0.8, 0.15), Vector3(0, 1.5, -0.8), c.darkened(0.2))
	for z in [-1.1, 1.1]:
		for sx in [-1.0, 1.0]:
			GroundKit.cyl(_vis, 0.4, 0.4, 0.25, Vector3(sx * 0.85, 0.4, z), GroundKit.COL_DARK, Vector3(0, 0, 90), 8, false)


func _build_gun(c: Color) -> void:
	var dark: Color = c.darkened(0.45)
	GroundKit.box(_vis, Vector3(2.0, 1.2, 0.2), Vector3(0, 1.3, -1.2), c)                        # shield
	_turret = Node3D.new()
	_turret.position = Vector3(0, 1.3, -0.8)
	_vis.add_child(_turret)
	GroundKit.cyl(_turret, 0.15, 0.2, 4.4, Vector3(0, 0.1, -2.0), dark, Vector3(88, 0, 0), 6)
	_tip = Node3D.new()
	_tip.position = Vector3(0, 0.1, -4.2)
	_turret.add_child(_tip)
	for sx in [-1.0, 1.0]:
		GroundKit.cyl(_vis, 0.7, 0.7, 0.25, Vector3(sx * 1.2, 0.7, -0.8), GroundKit.COL_DARK, Vector3(0, 0, 90), 10, false)
		GroundKit.box(_vis, Vector3(0.15, 0.15, 3.0), Vector3(sx * 0.5, 0.55, 1.4), dark, Vector3(0, sx * 12.0, 0))


## Airfield ground crew at work: proper CrewFigure people (life-size x1.45, like the aircraft) - one bent over a
## job, one kneeling, one supervising, one fetching a box round the dispersal - with crates, cans and a drum.
var _crew_figs: Array = []          # [{node, team, dress, pose, set:Array, next}]
var _crew_walker: Dictionary = {}

func _build_crew_group() -> void:
	var k: float = 1.45 / VIS               # figures are built in real metres; _vis is scaled by VIS
	var grp := Node3D.new()
	grp.scale = Vector3.ONE * k
	_vis.add_child(grp)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(global_position.x * 13.0 + global_position.z * 7.0)) + get_instance_id()
	var d0: int = rng.randi() % CrewFigure.DRESSES
	# (pose set it cycles through, position in metres, facing)
	var spots: Array = [
		[[CrewFigure.Pose.BEND, CrewFigure.Pose.KNEEL, CrewFigure.Pose.BEND], Vector3(0.0, 0, 0.0), 0.0],
		[[CrewFigure.Pose.KNEEL, CrewFigure.Pose.BEND], Vector3(1.4, 0, -0.6), -0.9],
		[[CrewFigure.Pose.HIPS, CrewFigure.Pose.STAND, CrewFigure.Pose.POINT], Vector3(-1.6, 0, 1.3), 2.4],
		[[CrewFigure.Pose.STAND, CrewFigure.Pose.HIPS], Vector3(-0.6, 0, 2.2), 3.0],
	]
	for i in spots.size():
		var sp: Array = spots[i]
		var pset: Array = sp[0]
		var pose: int = int(pset[rng.randi() % pset.size()])
		var fig: MeshInstance3D = CrewFigure.make(team, pose, (d0 + i) % CrewFigure.DRESSES)
		fig.position = (sp[1] as Vector3) + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		fig.rotation.y = float(sp[2]) + rng.randf_range(-0.4, 0.4)
		grp.add_child(fig)
		_crew_figs.append({"node": fig, "dress": (d0 + i) % CrewFigure.DRESSES, "pose": pose, "set": pset, "next": rng.randf_range(4.0, 12.0)})
	# one man walks a slow round of the dispersal carrying a box
	var wf: MeshInstance3D = CrewFigure.make(team, CrewFigure.Pose.WALK_A, (d0 + 4) % CrewFigure.DRESSES)
	grp.add_child(wf)
	_crew_walker = {"node": wf, "dress": (d0 + 4) % CrewFigure.DRESSES, "pose": CrewFigure.Pose.WALK_A, "a": rng.randf() * TAU, "r": rng.randf_range(4.5, 7.0), "dir": 1.0 if rng.randf() < 0.5 else -1.0}
	# kit on the ground: an ammunition box, a toolbox, jerricans and an oil drum
	var olive: Color = Color(0.30, 0.33, 0.21) if team != "Axis" else Color(0.34, 0.35, 0.32)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(0.9, 0.42, 0.5), Vector3(0.9, 0.21, 0.9), Color(0.40, 0.31, 0.19)))                    # wooden crate
	parts.append(GroundKit.box_part(Vector3(0.92, 0.05, 0.52), Vector3(0.9, 0.44, 0.9), Color(0.33, 0.25, 0.15), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.55, 0.22, 0.24), Vector3(-0.7, 0.11, -0.8), Color(0.45, 0.10, 0.08)))                 # toolbox
	for j in 3:
		parts.append(GroundKit.box_part(Vector3(0.17, 0.47, 0.34), Vector3(-1.9 + float(j) * 0.2, 0.235, -0.2), olive))            # cans
	parts.append(GroundKit.cyl_part(0.29, 0.29, 0.88, Vector3(2.3, 0.44, 0.4), Color(0.22, 0.24, 0.20) if team != "Axis" else Color(0.30, 0.30, 0.28), Vector3.ZERO, 12))   # drum
	parts.append(GroundKit.cyl_part(0.30, 0.30, 0.04, Vector3(2.3, 0.62, 0.4), Color(0.6, 0.55, 0.2), Vector3.ZERO, 12, false))   # drum band
	var kit := MeshInstance3D.new()
	kit.mesh = AirfieldAssets._build(parts)
	kit.visibility_range_end = 1600.0
	grp.add_child(kit)
	_place_walker(0.0)


func _place_walker(t: float) -> void:
	if _crew_walker.is_empty():
		return
	var a: float = float(_crew_walker["a"]) + t * 0.16 * float(_crew_walker["dir"])
	var r: float = float(_crew_walker["r"])
	var n: MeshInstance3D = _crew_walker["node"]
	n.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
	# tangent of the circle; the figure faces -Z
	var tg: Vector3 = Vector3(-sin(a), 0.0, cos(a)) * float(_crew_walker["dir"])
	n.rotation.y = atan2(-tg.x, -tg.z)
	var stride: int = CrewFigure.Pose.WALK_A if fmod(t * 2.4, 2.0) < 1.0 else CrewFigure.Pose.WALK_B
	if int(_crew_walker["pose"]) != stride:
		_crew_walker["pose"] = stride
		n.mesh = CrewFigure.mesh(team, stride, int(_crew_walker["dress"]))


func _update_crew(t: float, dt: float) -> void:
	_place_walker(t)
	for c in _crew_figs:
		c["next"] = float(c["next"]) - dt
		if float(c["next"]) <= 0.0:
			c["next"] = randf_range(5.0, 14.0)
			var pset: Array = c["set"]
			var pose: int = int(pset[randi() % pset.size()])
			if pose != int(c["pose"]):
				c["pose"] = pose
				(c["node"] as MeshInstance3D).mesh = CrewFigure.mesh(team, pose, int(c["dress"]))


func _build_troops() -> void:
	if vtype == "crew":
		_build_crew_group()
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var cm := CapsuleMesh.new()
	cm.radius = 0.28
	cm.height = 1.7
	cm.radial_segments = 6
	cm.rings = 2
	mm.mesh = cm
	mm.instance_count = _troop_n
	_troops = MultiMeshInstance3D.new()
	_troops.multimesh = mm
	var col: Color = Color(0.3, 0.35, 0.25) if team == "Allies" else Color(0.38, 0.4, 0.36)
	_troops.material_override = GroundKit.mat(col, true, 0.03)
	_vis.add_child(_troops)
	_update_troops(0.0)


func _update_troops(t: float) -> void:
	if _troops == null:
		return
	var mm: MultiMesh = _troops.multimesh
	for i in _troop_n:
		var row: int = i / 2
		var side: float = -1.0 if i % 2 == 0 else 1.0
		if vtype == "crew":
			var a: float = float(i) * 1.26
			var cp := Vector3(cos(a) * 2.0 + sin(t * 0.7 + float(i)) * 0.5, 0.95 + absf(sin(t * 2.2 + float(i) * 1.7)) * 0.08, sin(a) * 2.0 + cos(t * 0.6 + float(i)) * 0.5)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, a + t * 0.2), cp))
			continue
		var bob: float = absf(sin(t * 6.0 + float(i))) * 0.12 if mode == "move" else 0.0
		var p := Vector3(side * 1.1 + sin(float(i) * 3.1) * 0.25, 0.95 + bob, float(row) * 1.9 - 5.0)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))


func _build_wreck(root: Node3D) -> void:
	var w := Node3D.new()
	w.scale = Vector3.ONE * VIS
	root.add_child(w)
	var d: Color = Color(0.1, 0.09, 0.08)
	match vtype:
		"troops", "crew":
			for i in 5:
				GroundKit.box(w, Vector3(0.5, 0.25, 1.3), Vector3(randf_range(-2, 2), 0.15, randf_range(-3, 3)), Color(0.18, 0.15, 0.12), Vector3(0, randf_range(0, 180), 0), false)
		"truck", "halftrack", "jeep", "bowser", "tug", "firetender", "bombcart":
			GroundKit.box(w, Vector3(2.2, 0.9, 4.2), Vector3(0, 0.55, 0), d, Vector3(0, 8, 5))
			GroundKit.box(w, Vector3(1.8, 0.7, 1.4), Vector3(0.2, 1.2, -1.5), d.lightened(0.05), Vector3(10, -12, 20))
		_:
			GroundKit.box(w, Vector3(2.6, 0.9, 5.4), Vector3(0, 0.75, 0), d, Vector3(0, 4, 3))
			GroundKit.box(w, Vector3(1.8, 0.7, 2.2), Vector3(1.3, 1.1, 1.0), d.lightened(0.06), Vector3(14, 25, 30))  # blown turret
			GroundKit.cyl(w, 0.1, 0.12, 3.0, Vector3(2.0, 0.4, -1.5), d, Vector3(80, 30, 0), 6)


# ------------------------------------------------------------------ behaviour
var _lod_skip: int = 1        # update every Nth frame by distance from the camera (far vehicles need no 60 Hz)
var _lod_acc: float = 0.0


func _process(delta: float) -> void:
	if is_dead:
		return
	_frame += 1
	if _frame % 30 == 1:
		var cam: Camera3D = get_viewport().get_camera_3d()
		var dc: float = cam.global_position.distance_to(global_position) if cam != null else 0.0
		_lod_skip = 1 if dc < 2500.0 else (3 if dc < 6000.0 else 8)
		if mode == "idle" and vtype != "troops" and vtype != "crew":
			_lod_skip *= 4         # parked: only re-seat on the ground now and then
	_lod_acc += delta
	if _lod_skip > 1 and (_frame + get_instance_id()) % _lod_skip != 0:
		return
	delta = minf(_lod_acc, 0.1 * float(_lod_skip))
	_lod_acc = 0.0
	if mode == "move" and route != null and route.length > 1.0:
		_place(delta, false)
	elif _frame % 4 == 0:
		_ground(false)
	if vtype == "troops" or vtype == "crew":
		_troop_t += delta
		if _frame % 6 == 0 and _troops:
			_update_troops(_troop_t)
		elif vtype == "crew" and _frame % 3 == 0 and not _crew_figs.is_empty():
			_update_crew(_troop_t, delta * 3.0)
	if mode == "fire" and _tip != null:
		_fire_t -= delta
		if _fire_t <= 0.0:
			_fire_t = randf_range(2.5, 6.0)
			_fire_flash()


func _place(delta: float, snap: bool) -> void:
	s += speed * dir * delta
	if wrap:
		s = fposmod(s, route.length)
	else:
		if s > route.length:
			s = route.length
			dir = -1.0
		elif s < 0.0:
			s = 0.0
			dir = 1.0
	var p: Vector3 = route.sample(s)
	var t: Vector3 = route.tangent(s) * dir
	var target_yaw: float = atan2(-t.x, -t.z)
	_yaw = target_yaw if snap else lerp_angle(_yaw, target_yaw, clampf(delta * 4.0, 0.0, 1.0))
	global_position = Vector3(p.x, global_position.y, p.z)
	rotation.y = _yaw
	if snap or _frame % 2 == 0:
		_ground(snap)


func _ground(_snap: bool) -> void:
	var p: Vector3 = global_position
	var y0: float = GroundKit.ground_y(p.x, p.z)
	var f: Vector3 = Vector3(-sin(rotation.y), 0, -cos(rotation.y)) * 3.0
	var y1: float = GroundKit.ground_y(p.x + f.x, p.z + f.z)
	global_position.y = y0 + 0.2
	_pitch = lerpf(_pitch, atan2(y1 - y0, 3.0), 0.25)
	rotation.x = -_pitch


func _fire_flash() -> void:
	var pl: Node3D = GroundKit.player_node()
	if pl and pl.global_position.distance_to(global_position) > 5000.0:
		return
	if _turret and pl:
		var to_p: Vector3 = pl.global_position - global_position
		_turret.global_rotation.y = atan2(-to_p.x, -to_p.z)
	GroundKit.explosion(_tip.global_position, 0.18)
	GroundKit.sparks(_tip.global_position)


func _on_destroyed(_killer: Node) -> void:
	speed = 0.0
	mode = "idle"


func take_damage(amount: float, source: Node = null) -> void:
	super.take_damage(amount, source)
	if vtype == "troops" and not is_dead and _troops:
		var alive: int = int(ceil(float(_troop_n) * clampf(health / max_health, 0.0, 1.0)))
		_troops.multimesh.visible_instance_count = alive
