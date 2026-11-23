extends Node3D
## One land battle (tanks, anti-tank guns, lorries and infantry squads of two sides), run by LandBattles (the director).
## Units are GroundVehicle nodes (GroundTarget: they join the "damageable" group, so the player's bombs, rockets and guns
## destroy them and the normal wreck / fire / score paths run). Infantry are one MultiMesh per squad (the airfield men's
## figure and shader); a squad runs a bound (the shader's RUN beat started at the right clock phase), goes to ground
## (the shader's `alarm` = lying flat) and fires, then runs the next bound behind its tanks.
## Cheap at distance: the logic ticks at 4 / 2 / 1 Hz by distance to the player, effects and tracers only within 6.5 km.
## Scenario data are the era-correct forces (see SCENARIOS). Debug: --battle-log.
## Built without class_name (a new class_name needs an editor import first); load it with preload.

signal losing(team: String)
signal finished(winner: String)
signal friendly_hit(what: String)

const MAN: float = 1.036                # AirfieldPeople.MAN (SCALE * HEIGHT_M / FIG_H)
const RUN_SPD: float = 3.6              # mesh metres a second of a rifle squad's bound (about 3.7 m/s)
const TRACER_MAX: int = 56
const CORPSE_MAX: int = 160
const FX_RANGE: float = 6500.0
const SQUAD_VIEW: float = 2600.0

## kind -> forces. Tanks / guns / trucks are GroundVehicle types; "squads" the men per side.
const SCENARIOS := {
	"arras": {
		"title": "Arras counter-attack",
		"att": "Allies", "def": "Axis", "beach": false,
		"a_tanks": ["matilda", "matilda", "matilda", "matilda"], "a_guns": [], "a_trucks": ["jeep"], "a_squads": 2,
		"d_tanks": ["pz38t", "pz38t", "pz38t", "panzer3", "panzer3"], "d_guns": ["pak", "pak"], "d_trucks": ["truck", "kubel"], "d_squads": 3,
		"who": {"Allies": "Matildas", "Axis": "Panzers"},
	},
	"raid": {
		"title": "Allied raid in force (Dieppe style)",
		"att": "Allies", "def": "Axis", "beach": true,
		"a_tanks": ["churchill", "churchill", "churchill", "churchill"], "a_guns": [], "a_trucks": ["jeep"], "a_squads": 4,
		"d_tanks": ["panzer3", "panzer3"], "d_guns": ["pak", "pak", "pak"], "d_trucks": ["truck", "kubel"], "d_squads": 3,
		"who": {"Allies": "Churchills", "Axis": "Panzers"},
	},
	"sealion": {
		"title": "Sea Lion what-if: a German foothold",
		"att": "Axis", "def": "Allies", "beach": true,
		"a_tanks": ["panzer3", "panzer3", "panzer3", "pz38t", "pz38t", "panzer4"], "a_guns": [], "a_trucks": ["truck", "truck"], "a_squads": 4,
		"d_tanks": ["matilda", "matilda", "valentine", "valentine"], "d_guns": ["pak", "pak"], "d_trucks": ["jeep"], "d_squads": 3,
		"who": {"Allies": "Matildas", "Axis": "Panzers"},
	},
	"normandy": {
		"title": "Armoured fight in the bocage",
		"att": "Allies", "def": "Axis", "beach": false,
		"a_tanks": ["sherman", "sherman", "sherman", "sherman"], "a_guns": [], "a_trucks": ["halftrack", "halftrack"], "a_squads": 4,
		"d_tanks": ["panzer4", "panzer4", "tiger"], "d_guns": ["pak", "pak"], "d_trucks": ["truck"], "d_squads": 3,
		"who": {"Allies": "Shermans", "Axis": "Panzers"},
	},
}

# Per vehicle type: main gun reload (s), effective range (m), top speed (m/s), armour-piercing damage range.
const GUNS := {
	"churchill": {"reload": 7.5, "range": 850.0, "speed": 4.0, "dmg": [28.0, 48.0]},
	"matilda": {"reload": 8.0, "range": 800.0, "speed": 3.6, "dmg": [28.0, 46.0]},
	"valentine": {"reload": 7.0, "range": 800.0, "speed": 4.6, "dmg": [28.0, 46.0]},
	"sherman": {"reload": 6.5, "range": 900.0, "speed": 5.2, "dmg": [30.0, 52.0]},
	"panzer3": {"reload": 6.5, "range": 850.0, "speed": 5.0, "dmg": [28.0, 48.0]},
	"pz38t": {"reload": 6.0, "range": 750.0, "speed": 5.4, "dmg": [26.0, 42.0]},
	"panzer4": {"reload": 7.0, "range": 900.0, "speed": 4.8, "dmg": [30.0, 52.0]},
	"tiger": {"reload": 8.0, "range": 1100.0, "speed": 3.8, "dmg": [45.0, 80.0]},
	"pak": {"reload": 5.5, "range": 1000.0, "speed": 0.0, "dmg": [30.0, 55.0]},
}

## Test hook: land test used when placing units (default: the terrain). func(x: float, z: float) -> bool.
static var land_fn: Callable = Callable()
static var _fig_mesh: ArrayMesh = null
static var _log: bool = false

class Unit extends RefCounted:
	var node: GroundVehicle
	var team: String = ""
	var vtype: String = ""
	var role: String = "tank"          # tank | gun | truck
	var alive: bool = true
	var reload: float = 7.0
	var fire_t: float = 3.0
	var mg_t: float = 2.0
	var range_m: float = 800.0
	var dmg_lo: float = 28.0
	var dmg_hi: float = 48.0
	var phase: String = "hold"         # bound | halt | hold
	var phase_t: float = 0.0
	var goal: Vector2 = Vector2.ZERO
	var top_speed: float = 4.0
	var brew_t: float = -1.0
	var yaw: float = 0.0
	var chk_t: float = 0.0             # next check that it does not stand in a house

	func pos() -> Vector3:
		return node.global_position

class Squad extends RefCounted:
	var team: String = ""
	var mi: MultiMeshInstance3D
	var mm: MultiMesh
	var n: int = 0
	var start_n: int = 0
	var mp: PackedVector2Array = PackedVector2Array()      # each man: his position (the start of the bound while running)
	var xf: Array = []
	var cd: Array = []
	var state: String = "prone"        # run | prone
	var t: float = 3.0                 # seconds left in this state
	var run_total: float = 1.0
	var dir: Vector2 = Vector2(0, -1)
	var run_len: float = 0.0
	var fire_t: float = 1.0
	var alarm: float = 1.0
	var want_alarm: float = 1.0
	var pin_t: float = 0.0
	var routed: bool = false

var kind: String = "raid"
var sc: Dictionary = {}
var centre: Vector3 = Vector3.ZERO
var att_dir: Vector2 = Vector2(0, -1)      # unit vector from the centre towards where the attackers come from
var att_team: String = "Allies"
var def_team: String = "Axis"
var player_team: String = "Allies"
var seed_v: int = 1
var manual: bool = false                    # tests step it themselves (tick)
var rng := RandomNumberGenerator.new()

var units: Array = []
var squads: Array = []
var age: float = 0.0
var max_dur: float = 600.0
var ended: bool = false
var winner: String = ""
var end_age: float = 0.0
var armour0: Dictionary = {}
var men0: Dictionary = {}
var losing_said: Dictionary = {}
var kills_by_player: int = 0
var friendly_fire: int = 0
var men_killed_by_player: int = 0
var shells_fired: int = 0
var impacts: int = 0
var craters_made: int = 0
var ruin_calls: int = 0
var near: bool = false                       # a player aircraft is within FX_RANGE
var edge: float = 1.0                         # defenders' hit-chance factor (0.75-1.3: some battles turn the attackers' way)

var _acc: float = 0.0
var _budget: float = 10.0
var _shells: Array = []
var _ruin_t: float = 0.0
var _ruin_level: float = 0.5
var _player_t: float = 0.0
var _player: Node3D = null
var _pdist: float = 99999.0
var _alarm_t: float = 0.0
var _tr_mm: MultiMesh
var _tr_mi: MultiMeshInstance3D
var _tr_p: Array = []
var _tr_v: Array = []
var _tr_life: Array = []
var _tr_n: int = 0
var _co_mm: MultiMesh
var _co_mi: MultiMeshInstance3D
var _co_n: int = 0
var _built: bool = false


# ------------------------------------------------------------------ pure helpers (tests)

static func is_land(x: float, z: float) -> bool:
	if land_fn.is_valid():
		return bool(land_fn.call(x, z))
	return not GroundKit.is_water(x, z)


## Open ground a vehicle can drive on: land that is not woodland (ESA class 10), water or mangrove.
static func drivable(x: float, z: float) -> bool:
	if land_fn.is_valid():
		return bool(land_fn.call(x, z))
	if GroundKit.is_water(x, z):
		return false
	var c: int = LandCover.class_at(x, z)
	return c != 10 and c != 80 and c != 95


static func gy(x: float, z: float) -> float:
	return GroundKit.ground_y(x, z)


static func yaw_of(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


## The forces of a scenario for a date (Churchills only from mid-1942, Matildas / Valentines before).
static func scenario(k: String, date: String) -> Dictionary:
	var d: Dictionary = (SCENARIOS.get(k, SCENARIOS["raid"]) as Dictionary).duplicate(true)
	if k == "raid" and date != "" and date < "1942-06":
		d["a_tanks"] = ["matilda", "matilda", "matilda", "valentine"]
	return d


static func squad_size() -> int:
	return clampi(int(round(4.0 + AirfieldPeople.density() * 1.5)), 5, 8)


func setup(p_kind: String, p_centre: Vector3, p_att_dir: Vector2, p_player_team: String, p_seed: int, p_date: String = "") -> void:
	kind = p_kind
	sc = scenario(p_kind, p_date)
	centre = p_centre
	att_dir = p_att_dir.normalized() if p_att_dir.length() > 0.01 else Vector2(0, -1)
	att_team = str(sc["att"])
	def_team = str(sc["def"])
	player_team = p_player_team
	seed_v = p_seed
	rng.seed = p_seed
	_log = _log or ("--battle-log" in OS.get_cmdline_user_args())


func _ready() -> void:
	if not _built:
		build()


func team_friendly(team: String) -> bool:
	return team == player_team


func who(team: String) -> String:
	return str((sc["who"] as Dictionary).get(team, "troops"))


# ------------------------------------------------------------------ building

func _valid_spot(c: Vector2, spread: float) -> Vector2:
	for i in 8:
		var p := c + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * (spread * (0.4 + 0.2 * float(i)) if i > 0 else 0.0)
		if drivable(p.x, p.y):
			return p
	return c


func _add_vehicle(vtype: String, team: String, p: Vector2, face: Vector2, role: String) -> Unit:
	var v: GroundVehicle = GroundVehicle.create(vtype, team, null, 0.0, 0.0, "idle")
	var u := Unit.new()
	u.node = v
	u.team = team
	u.vtype = vtype
	u.role = role
	v.position = Vector3(p.x, gy(p.x, p.y) + 0.2, p.y)
	v.rotation.y = yaw_of(face)
	u.yaw = v.rotation.y
	var g: Dictionary = GUNS.get(vtype, {})
	if not g.is_empty():
		u.reload = float(g["reload"])
		u.range_m = float(g["range"])
		u.top_speed = float(g["speed"])
		u.dmg_lo = float((g["dmg"] as Array)[0])
		u.dmg_hi = float((g["dmg"] as Array)[1])
	u.fire_t = rng.randf_range(1.5, 6.0)
	u.mg_t = rng.randf_range(1.0, 4.0)
	add_child(v)
	v.destroyed.connect(_on_destroyed.bind(u))
	units.append(u)
	return u


func _make_squad(team: String, p: Vector2, face: Vector2, n: int, prone: bool) -> Squad:
	var s := Squad.new()
	s.team = team
	s.n = n
	s.start_n = n
	s.dir = face.normalized()
	var perp := Vector2(-s.dir.y, s.dir.x)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	if _fig_mesh == null:
		_fig_mesh = AirfieldPeople.figure_mesh()
	mm.mesh = _fig_mesh
	mm.instance_count = n
	mm.custom_aabb = AABB(Vector3(-420, -30, -420), Vector3(840, 120, 840))
	s.mm = mm
	var mi := MultiMeshInstance3D.new()
	mi.name = "Squad_" + team
	mi.multimesh = mm
	mi.material_override = AirfieldPeople._material(team, true)
	mi.position = Vector3(centre.x, 0.0, centre.z)
	mi.visibility_range_end = SQUAD_VIEW
	mi.visibility_range_end_margin = 100.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.mi = mi
	add_child(mi)
	for i in n:
		var q: Vector2 = p + perp * (float(i) - float(n - 1) * 0.5) * 3.2 - s.dir * rng.randf_range(0.0, 4.0)
		q = _valid_spot(q, 6.0)
		s.mp.append(q)
		s.xf.append(Transform3D.IDENTITY)
		s.cd.append(Color(1, 1, 0, 0))
	_pose_all(s)
	s.alarm = 1.0 if prone else 0.0
	s.want_alarm = s.alarm
	_push_alarm(s)
	squads.append(s)
	men0[team] = int(men0.get(team, 0)) + n
	return s


func build() -> void:
	if _built:
		return
	_built = true
	MilitaryPeople._ensure_probe()
	max_dur = rng.randf_range(540.0, 780.0)
	edge = rng.randf_range(0.75, 1.3)
	var perp := Vector2(-att_dir.y, att_dir.x)
	var c2 := Vector2(centre.x, centre.z)
	var start: Vector2 = c2 + att_dir * rng.randf_range(850.0, 1150.0)
	var face_in: Vector2 = -att_dir
	# attackers: tanks in a rough line abreast with bounds, squads between and behind, soft vehicles at the back
	var at: Array = sc["a_tanks"]
	for i in at.size():
		var lat: float = (float(i) - float(at.size() - 1) * 0.5) * rng.randf_range(34.0, 52.0)
		var p: Vector2 = _valid_spot(start + perp * lat + att_dir * rng.randf_range(0.0, 90.0), 30.0)
		var u: Unit = _add_vehicle(str(at[i]), att_team, p, face_in, "tank")
		var hold: float = rng.randf_range(190.0, 300.0)
		u.goal = c2 + (p - c2).normalized() * hold
		u.phase = "halt"
		u.phase_t = rng.randf_range(0.5, 6.0)
		u.node.mode = "idle"
	for i in (sc["a_trucks"] as Array).size():
		var p2: Vector2 = _valid_spot(start + att_dir * rng.randf_range(160.0, 260.0) + perp * (float(i) - 0.5) * 60.0, 30.0)
		var ut: Unit = _add_vehicle(str((sc["a_trucks"] as Array)[i]), att_team, p2, face_in, "truck")
		ut.goal = c2 + (p2 - c2).normalized() * rng.randf_range(520.0, 700.0)
		ut.phase = "halt"
		ut.phase_t = rng.randf_range(10.0, 25.0)
		ut.top_speed = 5.0
	var sn: int = squad_size()
	var a_sq: int = int(sc["a_squads"])
	for i in a_sq:
		var lat2: float = (float(i) - float(a_sq - 1) * 0.5) * 55.0
		_make_squad(att_team, start + att_dir * rng.randf_range(40.0, 120.0) + perp * lat2, face_in, sn, true)
	# defenders: guns at the edges of the objective, tanks behind cover, squads in the houses and hedges
	var dg: Array = sc["d_guns"]
	for i in dg.size():
		var a: float = rng.randf_range(-0.8, 0.8) + float(i) * 0.7 - float(dg.size() - 1) * 0.35
		var dirv := Vector2(att_dir.x, att_dir.y).rotated(a)
		var p3: Vector2 = _valid_spot(c2 + dirv * rng.randf_range(110.0, 260.0), 40.0)
		var ug: Unit = _add_vehicle(str(dg[i]), def_team, p3, att_dir, "gun")
		ug.phase = "hold"
	var dt: Array = sc["d_tanks"]
	for i in dt.size():
		var a2: float = rng.randf_range(-1.1, 1.1)
		var p4: Vector2 = _valid_spot(c2 - att_dir.rotated(a2) * rng.randf_range(10.0, 190.0), 40.0)
		var ud: Unit = _add_vehicle(str(dt[i]), def_team, p4, att_dir, "tank")
		ud.phase = "hold"
		ud.phase_t = rng.randf_range(20.0, 60.0)
		ud.goal = p4
	for i in (sc["d_trucks"] as Array).size():
		var p5: Vector2 = _valid_spot(c2 - att_dir * rng.randf_range(120.0, 220.0) + perp * rng.randf_range(-50.0, 50.0), 30.0)
		var ut2: Unit = _add_vehicle(str((sc["d_trucks"] as Array)[i]), def_team, p5, perp, "truck")
		ut2.phase = "hold"
	var d_sq: int = int(sc["d_squads"])
	for i in d_sq:
		var p6: Vector2 = _valid_spot(c2 + att_dir.rotated(rng.randf_range(-1.3, 1.3)) * rng.randf_range(30.0, 150.0), 30.0)
		_make_squad(def_team, p6, att_dir, sn, true)
	for u in units:
		var uu: Unit = u
		if uu.role != "truck":
			armour0[uu.team] = int(armour0.get(uu.team, 0)) + 1
	_setup_pools()
	_ruin(0.5, 170.0)
	if _log:
		print("[battle] %s at %.0f, %.0f: %s %d tanks + %d men vs %s %d tanks/guns + %d men" % [kind, centre.x, centre.z, att_team, int(armour0.get(att_team, 0)), int(men0.get(att_team, 0)), def_team, int(armour0.get(def_team, 0)), int(men0.get(def_team, 0))])


func _setup_pools() -> void:
	var tm := MultiMesh.new()
	tm.transform_format = MultiMesh.TRANSFORM_3D
	tm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, 0.09, 7.0)
	tm.mesh = bm
	tm.instance_count = TRACER_MAX
	tm.custom_aabb = AABB(Vector3(-1500, -50, -1500), Vector3(3000, 400, 3000))
	_tr_mm = tm
	_tr_mi = MultiMeshInstance3D.new()
	_tr_mi.multimesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	m.emission_enabled = true
	m.emission = Color(1.0, 0.7, 0.3)
	m.emission_energy_multiplier = 2.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tr_mi.material_override = m
	_tr_mi.position = Vector3(centre.x, 0.0, centre.z)
	_tr_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tr_mi)
	for i in TRACER_MAX:
		_tr_p.append(Vector3.ZERO)
		_tr_v.append(Vector3.ZERO)
		_tr_life.append(0.0)
		tm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		tm.set_instance_color(i, Color.WHITE)
	var cm := MultiMesh.new()
	cm.transform_format = MultiMesh.TRANSFORM_3D
	cm.use_colors = true
	var cb := BoxMesh.new()
	cb.size = Vector3(0.55, 0.22, 1.75)
	cm.mesh = cb
	cm.instance_count = CORPSE_MAX
	cm.visible_instance_count = 0
	cm.custom_aabb = AABB(Vector3(-1500, -50, -1500), Vector3(3000, 100, 3000))
	_co_mm = cm
	_co_mi = MultiMeshInstance3D.new()
	_co_mi.multimesh = cm
	var m2 := StandardMaterial3D.new()
	m2.vertex_color_use_as_albedo = true
	m2.roughness = 1.0
	_co_mi.material_override = m2
	_co_mi.position = Vector3(centre.x, 0.0, centre.z)
	_co_mi.visibility_range_end = 1500.0
	_co_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_co_mi)


# ------------------------------------------------------------------ squads (the men)

func _local(p: Vector3) -> Vector3:
	return Vector3(p.x - centre.x, p.y, p.z - centre.z)


func _man_xf(p: Vector2, p1: Vector2, d: Vector2) -> Transform3D:
	var y0: float = gy(p.x, p.y) + 0.01
	var y1: float = gy(p1.x, p1.y) + 0.01
	var dir3 := Vector3(d.x, 0.0, d.y)
	if p.distance_to(p1) > 1.0:
		dir3 = Vector3(p1.x - p.x, y1 - y0, p1.y - p.y).normalized()
	var bas: Basis = Basis.looking_at(dir3, Vector3.UP).scaled(Vector3.ONE * MAN)
	return Transform3D(bas, _local(Vector3(p.x, y0, p.y)))


func _code(kind_id: int, team: String, dress: int) -> float:
	return float(AirfieldPeople.code_of(kind_id, true, dress))


## Every man standing / lying where mp says, facing the squad's direction (the prone pose: the squad's alarm is up).
func _pose_all(s: Squad) -> void:
	for i in s.n:
		_pose_man(s, i)
	s.mm.visible_instance_count = s.n


func _pose_man(s: Squad, i: int) -> void:
	var p: Vector2 = s.mp[i]
	s.xf[i] = _man_xf(p, p, s.dir)
	s.cd[i] = Color(1.0, 1.0, rng.randf(), _code(AirfieldPeople.Kind.TALK, s.team, rng.randi() % 4))
	_push(s, i)


func _push(s: Squad, i: int) -> void:
	s.mm.set_instance_transform(i, s.xf[i])
	s.mm.set_instance_custom_data(i, s.cd[i])


func _push_alarm(s: Squad) -> void:
	s.mi.set_instance_shader_parameter("alarm", s.alarm)


func man_pos(s: Squad, i: int) -> Vector2:
	if s.state == "run":
		var f: float = clampf(1.0 - s.t / maxf(s.run_total, 0.1), 0.0, 1.0)
		return s.mp[i] + s.dir * (s.run_len * f)
	return s.mp[i]


func squad_centre(s: Squad) -> Vector2:
	if s.n <= 0:
		return Vector2(centre.x, centre.z)
	var c := Vector2.ZERO
	for i in s.n:
		c += man_pos(s, i)
	return c / float(s.n)


## Start a bound of `length` metres along `d`: each man's RUN beat begins now.
func _squad_run(s: Squad, d: Vector2, length: float) -> void:
	s.dir = d.normalized()
	s.run_len = length
	s.state = "run"
	var secs: float = length / (RUN_SPD * MAN)
	s.run_total = secs
	s.t = secs
	s.want_alarm = 0.0
	var now: float = MilitaryPeople.shader_time()
	var len_mesh: float = length / MAN
	for i in s.n:
		var p: Vector2 = s.mp[i]
		var p1: Vector2 = p + s.dir * length
		s.xf[i] = _man_xf(p, p1, s.dir)
		var ph: float = MilitaryPeople.beat_phase(len_mesh, RUN_SPD, 1.2, now + rng.randf_range(0.0, 0.5))
		s.cd[i] = Color(len_mesh, RUN_SPD, ph, _code(AirfieldPeople.Kind.RUN, s.team, rng.randi() % 4))
		_push(s, i)


func _squad_arrive(s: Squad) -> void:
	for i in s.n:
		s.mp[i] = s.mp[i] + s.dir * s.run_len
	s.state = "prone"
	s.run_len = 0.0
	s.want_alarm = 1.0
	_pose_all(s)
	s.t = rng.randf_range(4.0, 8.0)


func _kill_man(s: Squad, i: int, by_player: bool) -> void:
	if s.n <= 0 or i < 0 or i >= s.n:
		return
	var p: Vector2 = man_pos(s, i)
	_corpse(p, s.team)
	var last: int = s.n - 1
	s.mp[i] = s.mp[last]
	s.xf[i] = s.xf[last]
	s.cd[i] = s.cd[last]
	if i != last:
		_push(s, i)
	s.n -= 1
	s.mm.visible_instance_count = s.n
	if by_player:
		men_killed_by_player += 1
		if team_friendly(s.team):
			friendly_fire += 1
			friendly_hit.emit("men")
	if s.n > 0 and float(s.n) <= float(s.start_n) * 0.4 and not s.routed:
		s.routed = true
		_squad_rout(s)


func _squad_rout(s: Squad) -> void:
	var c: Vector2 = squad_centre(s)
	var away: Vector2 = (c - Vector2(centre.x, centre.z)).normalized()
	if s.team == att_team:
		away = att_dir
	if s.state == "run":
		_squad_arrive(s)
	_squad_run(s, away, rng.randf_range(60.0, 120.0))


func _corpse(p: Vector2, team: String) -> void:
	if _co_n >= CORPSE_MAX:
		return
	var y: float = gy(p.x, p.y) + 0.12
	var yaw: float = rng.randf() * TAU
	_co_mm.set_instance_transform(_co_n, Transform3D(Basis(Vector3.UP, yaw), _local(Vector3(p.x, y, p.y))))
	_co_mm.set_instance_color(_co_n, Color(0.22, 0.21, 0.14) if team == "Allies" else Color(0.26, 0.28, 0.27))
	_co_n += 1
	_co_mm.visible_instance_count = _co_n


## Men within `radius` of `p` fall with probability `chance` each. Returns how many.
func casualties_near(p: Vector3, radius: float, chance: float, by_player: bool = false, only_team: String = "") -> int:
	var killed: int = 0
	var p2 := Vector2(p.x, p.z)
	for s in squads:
		var sq: Squad = s
		if only_team != "" and sq.team != only_team:
			continue
		var i: int = sq.n - 1
		while i >= 0:
			if man_pos(sq, i).distance_to(p2) < radius and rng.randf() < chance:
				_kill_man(sq, i, by_player)
				killed += 1
			i -= 1
	return killed


func men_alive(team: String) -> int:
	var n: int = 0
	for s in squads:
		if (s as Squad).team == team:
			n += (s as Squad).n
	return n


func armour_alive(team: String) -> int:
	var n: int = 0
	for u in units:
		var uu: Unit = u
		if uu.team == team and uu.role != "truck" and uu.alive:
			n += 1
	return n


func vehicles_alive(team: String) -> int:
	var n: int = 0
	for u in units:
		var uu: Unit = u
		if uu.team == team and uu.alive:
			n += 1
	return n


# ------------------------------------------------------------------ effects

func _fx_cost(c: float) -> bool:
	if not near or _budget < c:
		return false
	_budget -= c
	return true


func _tracer(from: Vector3, to: Vector3, speed: float, team: String) -> void:
	if not near:
		return
	var slot: int = -1
	for i in TRACER_MAX:
		if float(_tr_life[i]) <= 0.0:
			slot = i
			break
	if slot < 0:
		return
	var d: Vector3 = to - from
	var ln: float = d.length()
	if ln < 1.0:
		return
	_tr_p[slot] = from
	_tr_v[slot] = d / ln * speed
	_tr_life[slot] = minf(ln / speed, 2.0)
	_tr_mm.set_instance_color(slot, Color(1.0, 0.3, 0.18) if team == "Allies" else Color(1.0, 0.92, 0.55))
	_tr_n += 1


func _update_tracers(dt: float) -> void:
	if _tr_n <= 0:
		return
	var left: int = 0
	for i in TRACER_MAX:
		var l: float = float(_tr_life[i])
		if l <= 0.0:
			continue
		l -= dt
		_tr_life[i] = l
		if l <= 0.0:
			_tr_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
			continue
		left += 1
		var p: Vector3 = (_tr_p[i] as Vector3) + (_tr_v[i] as Vector3) * dt
		_tr_p[i] = p
		var v: Vector3 = _tr_v[i]
		_tr_mm.set_instance_transform(i, Transform3D(Basis.looking_at(v.normalized(), Vector3.UP), _local(p)))
	_tr_n = left


func _sfx(name_s: String, p: Vector3, db: float, gap: float) -> void:
	if near:
		GroundKit.fx_call("sfx", [name_s, p, db, gap])


func _muzzle(u: Unit, aim: Vector3) -> void:
	var tip: Node3D = u.node._tip
	var turret: Node3D = u.node._turret
	if turret != null:
		var to: Vector3 = aim - u.pos()
		turret.global_rotation.y = atan2(-to.x, -to.z)
	if tip != null and _fx_cost(1.0):
		GroundKit.explosion(tip.global_position, 0.2)
		GroundKit.sparks(tip.global_position)
	_sfx("cannon", u.pos(), -2.0, 0.1)


func _dirt(p: Vector3, size: float) -> void:
	if _fx_cost(0.6):
		GroundKit.fx_call("dust", [p + Vector3(0, 0.5, 0), size])
		GroundKit.explosion(p, size * 0.12)


# ------------------------------------------------------------------ the shells in flight

func _fire_shell(u: Unit, tp: Vector3, tu: Unit) -> void:
	shells_fired += 1
	var d: float = u.pos().distance_to(tp)
	var moving: bool = tu != null and tu.phase == "bound"
	var p_hit: float = lerpf(0.62, 0.12, clampf(d / maxf(u.range_m, 1.0), 0.0, 1.0)) * (0.65 if moving else 1.0)
	p_hit *= edge if u.team == def_team else 1.0 / edge          # one side has the better of this battle
	if tu == null:
		p_hit = 0.0
	var hit: bool = rng.randf() < p_hit
	var dest: Vector3 = tp
	if not hit:
		var ang: float = rng.randf() * TAU
		var off: float = rng.randf_range(5.0, 28.0)
		dest = tp + Vector3(cos(ang) * off, 0.0, sin(ang) * off)
		dest.y = gy(dest.x, dest.z)
	var muzzle: Vector3 = u.pos() + Vector3(0, 2.4, 0)
	if u.node._tip != null:
		muzzle = u.node._tip.global_position
	_muzzle(u, tp)
	_tracer(muzzle, dest + Vector3(0, 1.0, 0), 520.0, u.team)
	_shells.append({"t": d / 520.0 + 0.05, "pos": dest, "unit": tu, "hit": hit, "team": u.team, "dmg": rng.randf_range(u.dmg_lo, u.dmg_hi)})


func _resolve_shells(dt: float) -> void:
	var i: int = _shells.size() - 1
	while i >= 0:
		var sh: Dictionary = _shells[i]
		sh["t"] = float(sh["t"]) - dt
		if float(sh["t"]) <= 0.0:
			_shells.remove_at(i)
			_impact(sh)
		i -= 1


func _impact(sh: Dictionary) -> void:
	impacts += 1
	var p: Vector3 = sh["pos"]
	var tu: Unit = sh["unit"]
	if bool(sh["hit"]) and tu != null and tu.alive and is_instance_valid(tu.node):
		GroundKit.sparks(tu.pos() + Vector3(0, 1.8, 0))
		_sfx("hit_metal:1", tu.pos(), -3.0, 0.1)
		tu.node.take_damage(float(sh["dmg"]), null)
		if tu.alive and tu.node.health <= tu.node.max_health * 0.38 and tu.brew_t < 0.0 and tu.role != "truck":
			tu.brew_t = rng.randf_range(2.5, 6.5)            # the crew bale out, it burns, then the ammunition goes up
			tu.phase = "hold"
			GroundKit.stack_smoke(tu.node, Vector3(0, 2.6, 0), 1.3)
	else:
		_dirt(p, rng.randf_range(2.5, 4.5))
		_sfx("hit", p, -6.0, 0.1)
		_maybe_crater(p)
	# a shell (or the bursting tank) also hurts the men round it
	casualties_near(p, 6.0, 0.35)


func _maybe_crater(p: Vector3) -> void:
	if craters_made >= 28 or rng.randf() > 0.3:
		return
	craters_made += 1
	var bd: Node = _battle_damage()
	if bd != null and bd.has_method("crater"):
		bd.call("crater", p, rng.randf_range(3.0, 6.0))
	else:
		GroundKit.fx_call("crater", [p, rng.randf_range(2.0, 3.5)])


func _battle_damage() -> Node:
	var t: SceneTree = GroundKit.tree()
	if t == null:
		return null
	return t.root.get_node_or_null("BattleDamage")


func _ruin(intensity: float, radius: float) -> void:
	var bd: Node = _battle_damage()
	ruin_calls += 1
	if bd != null and bd.has_method("ruin_area"):
		bd.call("ruin_area", centre, radius, intensity, seed_v)
	if _log:
		print("[battle] ruin_area r=%.0f i=%.2f (%s)" % [radius, intensity, "BattleDamage" if bd != null else "no BattleDamage"])


# ------------------------------------------------------------------ thinking

func _on_destroyed(node: Node, killer: Node, u: Unit) -> void:
	if not u.alive:
		return
	u.alive = false
	u.brew_t = -1.0
	u.phase = "hold"
	if WeaponWorld.is_player_source(killer):
		if team_friendly(u.team):
			friendly_fire += 1
			friendly_hit.emit(u.vtype)
		else:
			kills_by_player += 1
		# bombs and rockets that kill a vehicle also catch the men beside it
		casualties_near(u.pos(), 11.0, 0.5, true)
	elif u.role != "truck":
		casualties_near(u.pos(), 7.0, 0.3)
	if is_instance_valid(node):
		_ruin_level = minf(_ruin_level + 0.06, 1.0)
	_check_losing()


func _check_losing() -> void:
	for team in [att_team, def_team]:
		var a0: int = int(armour0.get(team, 0))
		if a0 > 0 and not losing_said.has(team) and float(armour_alive(team)) <= float(a0) / 3.0 + 0.01:
			losing_said[team] = true
			losing.emit(team)


func _enemy_of(team: String) -> String:
	return def_team if team == att_team else att_team


func _best_target(u: Unit) -> Dictionary:
	var p2 := Vector2(u.pos().x, u.pos().z)
	var best: Dictionary = {}
	var best_s: float = 1.0e9
	for e in units:
		var eu: Unit = e
		if eu.team == u.team or not eu.alive:
			continue
		var d: float = p2.distance_to(Vector2(eu.pos().x, eu.pos().z))
		if d > u.range_m:
			continue
		var sc_d: float = d - (260.0 if eu.role != "truck" else 0.0)
		if sc_d < best_s:
			best_s = sc_d
			best = {"unit": eu, "pos": eu.pos() + Vector3(0, 1.5, 0), "dist": d}
	if best.is_empty():
		for s in squads:
			var sq: Squad = s
			if sq.team == u.team or sq.n <= 0:
				continue
			var c: Vector2 = squad_centre(sq)
			var d2: float = p2.distance_to(c)
			if d2 <= minf(u.range_m, 650.0) and d2 < best_s:
				best_s = d2
				best = {"squad": sq, "pos": Vector3(c.x, gy(c.x, c.y) + 0.5, c.y), "dist": d2}
	return best


## Vehicles placed before the village streamed in may stand in a house: once the scenery's obstacle index knows the
## spot (the player is near, so it has been built) a vehicle in a building is moved to the nearest open ground.
func _unstick(u: Unit, dt: float) -> void:
	u.chk_t -= dt
	if u.chk_t > 0.0 or not near or u.phase == "bound" or age > 150.0:
		return
	u.chk_t = 2.0
	var p: Vector3 = u.pos()
	if Obstacles.hit(p, 3.5, p.y, p.y + 3.0, true).is_empty():
		return
	for ring in [14.0, 26.0, 42.0, 60.0]:
		for k in 8:
			var a: float = TAU * float(k) / 8.0 + u.yaw
			var q := Vector2(p.x + cos(a) * ring, p.z + sin(a) * ring)
			if not drivable(q.x, q.y):
				continue
			var y: float = gy(q.x, q.y)
			if Obstacles.hit(Vector3(q.x, y, q.y), 3.5, y, y + 3.0, true).is_empty():
				u.node.global_position = Vector3(q.x, y + 0.2, q.y)
				if u.role == "tank" and u.team == def_team:
					u.goal = q
				return


func _think_unit(u: Unit, dt: float) -> void:
	u.fire_t -= dt
	u.mg_t -= dt
	_unstick(u, dt)
	if u.role != "gun":
		_phase(u, dt)
	if u.role == "truck":
		return
	if u.phase == "bound":
		return
	var tg: Dictionary = _best_target(u)
	if tg.is_empty():
		return
	if u.fire_t <= 0.0:
		u.fire_t = u.reload * rng.randf_range(0.8, 1.35)
		if tg.has("unit"):
			_fire_shell(u, tg["pos"], tg["unit"])
		else:
			_fire_shell(u, tg["pos"], null)        # HE on infantry: bursts and a plume
	if u.mg_t <= 0.0 and u.role == "tank" and tg.has("squad") or (u.mg_t <= 0.0 and u.role == "tank" and tg.has("unit") and float(tg["dist"]) < 300.0):
		u.mg_t = rng.randf_range(1.4, 3.0)
		_mg_burst(u.pos() + Vector3(0, 2.2, 0), tg, u.team, 0.1)


func _mg_burst(from: Vector3, tg: Dictionary, team: String, kill_p: float) -> void:
	var tp: Vector3 = tg["pos"]
	for k in 3:
		_tracer(from, tp + Vector3(rng.randf_range(-6, 6), rng.randf_range(0.2, 2.0), rng.randf_range(-6, 6)), 420.0, team)
	_sfx("gun", from, -8.0, 0.25)
	if tg.has("squad"):
		var sq: Squad = tg["squad"]
		if sq.n > 0:
			var f: float = (0.5 if sq.state == "prone" else 1.0) * (1.0 - clampf(float(tg["dist"]) / 520.0, 0.0, 0.9))
			if rng.randf() < kill_p * 3.0 * f:
				_kill_man(sq, rng.randi() % sq.n, false)
			sq.pin_t = 3.0


func _phase(u: Unit, dt: float) -> void:
	var p: Vector2 = Vector2(u.pos().x, u.pos().z)
	u.phase_t -= dt
	match u.phase:
		"bound":
			if u.phase_t <= 0.0 or p.distance_to(u.goal) < 6.0:
				u.phase = "halt"
				u.phase_t = rng.randf_range(5.0, 9.0)
		"halt":
			if u.phase_t <= 0.0:
				if p.distance_to(u.goal) > 8.0 and u.team == att_team:
					u.phase = "bound"
					u.phase_t = rng.randf_range(8.0, 13.0)
				else:
					u.phase = "hold"
					u.phase_t = rng.randf_range(25.0, 60.0)
		"hold":
			# a defending tank shifts position now and then
			if u.phase_t <= 0.0:
				u.phase_t = rng.randf_range(30.0, 70.0)
				if u.team == def_team and u.role == "tank" and rng.randf() < 0.4:
					var np: Vector2 = p + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(25.0, 60.0)
					if drivable(np.x, np.y):
						u.goal = np
						u.phase = "bound"
						u.phase_t = 14.0


func _integrate(dt: float) -> void:
	for e in units:
		var u: Unit = e
		if not u.alive or u.phase != "bound" or not is_instance_valid(u.node):
			continue
		var pos: Vector3 = u.node.global_position
		var to: Vector2 = u.goal - Vector2(pos.x, pos.z)
		var d: float = to.length()
		if d < 1.0:
			continue
		var step: float = minf(u.top_speed * dt, d)
		var dv: Vector2 = to / d
		var np := Vector2(pos.x, pos.z) + dv * step
		u.yaw = lerp_angle(u.yaw, yaw_of(dv), clampf(dt * 1.2, 0.0, 1.0))
		u.node.global_position = Vector3(np.x, gy(np.x, np.y) + 0.2, np.y)
		u.node.rotation.y = u.yaw


func _think_squad(s: Squad, dt: float) -> void:
	s.t -= dt
	s.pin_t = maxf(s.pin_t - dt, 0.0)
	var c: Vector2 = squad_centre(s)
	if s.state == "run":
		if s.t <= 0.0:
			_squad_arrive(s)
		return
	# prone: fire at the nearest enemy squad, then maybe move up behind the tanks
	s.fire_t -= dt
	if s.fire_t <= 0.0 and not ended:
		s.fire_t = rng.randf_range(1.2, 2.8)
		var best: Squad = null
		var bd: float = 340.0
		for o in squads:
			var os: Squad = o
			if os.team == s.team or os.n <= 0:
				continue
			var d: float = c.distance_to(squad_centre(os))
			if d < bd:
				bd = d
				best = os
		if best != null:
			var oc: Vector2 = squad_centre(best)
			var from_i: int = rng.randi() % s.n
			var fp: Vector2 = man_pos(s, from_i)
			var tg: Dictionary = {"squad": best, "pos": Vector3(oc.x, gy(oc.x, oc.y) + 1.0, oc.y), "dist": bd}
			_mg_burst(Vector3(fp.x, gy(fp.x, fp.y) + 0.7, fp.y), tg, s.team, 0.05)
			best.pin_t = 2.5
			s.dir = (oc - c).normalized()
	if ended or s.routed or s.t > 0.0 or s.pin_t > 0.0:
		return
	if s.team == att_team:
		var cobj: Vector2 = Vector2(centre.x, centre.z)
		var dobj: float = c.distance_to(cobj)
		var front: float = 1.0e9          # how close to the objective the nearest friendly tank is
		for e in units:
			var eu: Unit = e
			if eu.team == s.team and eu.alive and eu.role == "tank":
				front = minf(front, Vector2(eu.pos().x, eu.pos().z).distance_to(cobj))
		var hold_off: float = 80.0
		if dobj > hold_off and (front > 5000.0 or dobj > front - 25.0 or rng.randf() < 0.1):
			_squad_run(s, (cobj - c).normalized().rotated(rng.randf_range(-0.25, 0.25)), rng.randf_range(35.0, 60.0))
			return
	s.t = rng.randf_range(4.0, 8.0)


func _update_player(dt: float) -> void:
	_player_t -= dt
	if _player_t > 0.0:
		return
	_player_t = 1.0
	_player = GroundKit.player_node()
	if _player != null and is_instance_valid(_player):
		_pdist = Vector2(_player.global_position.x - centre.x, _player.global_position.z - centre.z).length()
	else:
		_pdist = 99999.0
	near = _pdist < FX_RANGE


## Low enemy aircraft over a squad pins it (the men dive flat).
func _scan_aircraft(dt: float) -> void:
	_alarm_t -= dt
	if _alarm_t > 0.0 or _player == null or not is_instance_valid(_player):
		return
	_alarm_t = 0.5
	var ac: Aircraft = _player as Aircraft
	if ac == null or ac.team == "" or ac.on_ground:
		return
	for s in squads:
		var sq: Squad = s
		if sq.team == ac.team or sq.n <= 0:
			continue
		var c: Vector2 = squad_centre(sq)
		var d := Vector2(ac.global_position.x - c.x, ac.global_position.z - c.y).length()
		if d < 320.0 and ac.global_position.y - gy(c.x, c.y) < 260.0:
			sq.pin_t = 4.0


func tick(dt: float) -> void:
	age += dt
	_budget = minf(_budget + dt * 10.0, 16.0)
	if not near or _pdist > 3500.0:
		_integrate(dt)                       # far away the tanks move in whole ticks, not every frame
	for e in units:
		var u: Unit = e
		if not u.alive or not is_instance_valid(u.node):
			continue
		if u.brew_t > 0.0:
			u.brew_t -= dt
			if u.brew_t <= 0.0:
				u.brew_t = -1.0
				u.node.die(null)
			continue
		if not ended:
			_think_unit(u, dt)
	for s in squads:
		if (s as Squad).n > 0:
			_think_squad(s, dt)
	_resolve_shells(dt)
	_ruin_t += dt
	if _ruin_t > 80.0 and not ended:
		_ruin_t = 0.0
		_ruin(_ruin_level, 200.0 + 80.0 * _ruin_level)
	_check_end()


func _check_end() -> void:
	if ended:
		return
	var done: Dictionary = {}
	for team in [att_team, def_team]:
		var m0: int = maxi(int(men0.get(team, 1)), 1)
		done[team] = armour_alive(team) == 0 and float(men_alive(team)) <= float(m0) * 0.4
	if bool(done[att_team]) or bool(done[def_team]) or age > max_dur:
		ended = true
		end_age = age
		if bool(done[att_team]) and not bool(done[def_team]):
			winner = def_team
		elif bool(done[def_team]) and not bool(done[att_team]):
			winner = att_team
		else:
			var sa: float = float(armour_alive(att_team)) * 6.0 + float(men_alive(att_team))
			var sd: float = float(armour_alive(def_team)) * 6.0 + float(men_alive(def_team))
			winner = att_team if sa > sd else def_team
		for s in squads:
			var sq: Squad = s
			if sq.state == "run":
				_squad_arrive(sq)
			sq.want_alarm = 0.0 if sq.team == winner and sq.n > 0 else 1.0
		finished.emit(winner)
		if _log:
			print("[battle] over after %.0f s: %s holds the field (%s %d/%d armour, %d men; %s %d/%d armour, %d men)" % [age, winner, att_team, armour_alive(att_team), int(armour0.get(att_team, 0)), men_alive(att_team), def_team, armour_alive(def_team), int(armour0.get(def_team, 0)), men_alive(def_team)])


func strength(team: String) -> float:
	return float(armour_alive(team)) * 6.0 + float(men_alive(team))


func status() -> Dictionary:
	return {"kind": kind, "age": age, "ended": ended, "winner": winner,
		"att": att_team, "def": def_team,
		"att_armour": armour_alive(att_team), "def_armour": armour_alive(def_team),
		"att_men": men_alive(att_team), "def_men": men_alive(def_team),
		"kills_by_player": kills_by_player, "friendly_fire": friendly_fire}


func _process(delta: float) -> void:
	if not _built:
		return
	_update_player(delta)
	for s in squads:
		var sq: Squad = s
		if sq.alarm != sq.want_alarm:
			sq.alarm = move_toward(sq.alarm, sq.want_alarm, delta * (2.0 if sq.want_alarm > sq.alarm else 1.5))
			_push_alarm(sq)
	if near:
		_update_tracers(delta)
	if near and _pdist <= 3500.0:
		_integrate(delta)
	if manual:
		return
	_scan_aircraft(delta)
	_acc += delta
	var step: float = 0.25 if _pdist < 3500.0 else (0.5 if _pdist < 7000.0 else 1.0)
	if _acc >= step:
		var dt: float = _acc
		_acc = 0.0
		tick(minf(dt, 2.0))
