extends RefCounted
## Ground target markers: makes enemy vehicles, guns, flak and ships easy to find (Options > Gameplay > "Ground target markers").
##   0 Off   1 Smoke only   2 Outlines + smoke (default)   3 Full
## * Outlines: a shared, cached team_outline (Realistic) / cel_ink (Cel) material overlay, red enemy / yellow friendly (blue / yellow
##   with colour-blind colours), on enemy ground units within ~8 km of the player and on friendly units of an active event (a land
##   battle, a naval skirmish, a battery: meta "gm_event"). Visible from ~500 m, thin and soft, gone by ~8 km (shader range_m).
## * HUD brackets (hud.gd) over the nearest 12 enemy units of an event: while air support is requested (2) or whenever an event is
##   within 8 km (3), plus an edge arrow for an off-screen battle. Minimap dots for the same units.
## * Marker smoke: friendly troops pop yellow smoke on the enemy position and white smoke on their own line when a battle calls for
##   support, refreshed every 60-100 s (battle_smoke, called by LandBattles).
## Built without class_name (load with preload). The scan runs at 10 Hz from the HUD (update); nothing is allocated per frame.

const OFF := 0
const SMOKE := 1
const OUTLINES := 2
const FULL := 3
const NAMES := ["Off", "Smoke only", "Outlines + smoke", "Full"]
const GROUPS := ["vehicle", "ship", "aa_gun", "coastal_gun"]
const SKIP_TYPES := ["crew", "bowser", "tug", "firetender", "bombcart", "car", "bus", "troops"]
const OUTLINE_RANGE := Vector2(500.0, 8000.0)
const APPLY_RANGE: float = 8000.0
const DROP_RANGE: float = 9000.0
const HUD_RANGE: float = 8000.0
const DOT_RANGE: float = 12000.0
const MAX_MARKS: int = 12
const MAX_DOTS: int = 48
const ENEMY_RGB := Color(1.0, 0.16, 0.1)
const FRIEND_RGB := Color(1.0, 0.85, 0.1)

static var marks: Array = []        # [node, distance, true] nearest enemy units of an event first (HUD brackets)
static var dots: Array = []         # [node, is_enemy] event units within 12 km (minimap)
static var near_event: bool = false
static var smoke_made: int = 0
static var smoke_log: Array = []    # [position, colour] of every marker smoke made
static var _mats: Dictionary = {}
static var _t: float = 0.0


static func mode() -> int:
	return clampi(GameState.ground_markers, 0, 3)


static func hud_active(support: bool) -> bool:
	var m: int = mode()
	return (m == FULL and (near_event or support)) or (m == OUTLINES and support)


static func dots_active(support: bool) -> bool:
	return mode() >= OUTLINES and (near_event or support)


static func flash_size(dist: float) -> float:
	return clampf(1.5 + dist / 350.0, 2.0, 12.0)


## One shared material per (team, box mesh, art style, colour-blind) combination.
static func mat(enemy: bool, box: bool, cel: bool) -> ShaderMaterial:
	var key: String = "%d%d%d%d" % [int(enemy), int(box), int(cel), int(GameState.colorblind)]
	var m: ShaderMaterial = _mats.get(key) as ShaderMaterial
	if m != null:
		return m
	m = ShaderMaterial.new()
	var col: Color = GameState.accessible_color(ENEMY_RGB if enemy else FRIEND_RGB)
	if cel:
		m.shader = load("res://shaders/cel/cel_ink.gdshader") as Shader
		m.set_shader_parameter("ink_color", col)
		m.set_shader_parameter("thickness", 0.05)
		m.set_shader_parameter("dist_scale", 0.0009)
		m.set_shader_parameter("soft_near", 1.0)
		m.set_shader_parameter("max_dist", OUTLINE_RANGE.y)
	else:
		m.shader = load("res://shaders/team_outline.gdshader") as Shader
		m.set_shader_parameter("outline_color", col)
		m.set_shader_parameter("thickness", 0.04)
		m.set_shader_parameter("dist_scale", 0.0011)
		m.set_shader_parameter("strength", 0.7)
		m.set_shader_parameter("far_k", 0.6)
	m.set_shader_parameter("range_m", OUTLINE_RANGE)
	m.set_shader_parameter("box_hull", box)
	m.set_meta("gm", true)
	_mats[key] = m
	return m


## Put the outline on (or take it off) every mesh of a ground unit's intact model. Cheap when nothing changed (meta key).
static func sync(n: Node3D, enemy: bool, on: bool) -> void:
	var cel: bool = GameState.art_style == 1
	var key: int = 0
	if on:
		key = 1 + int(enemy) + 2 * int(cel) + 4 * int(GameState.colorblind)
	if int(n.get_meta("gm_key", 0)) == key:
		return
	n.set_meta("gm_key", key)
	var root: Node = n.get("_intact") as Node
	if root == null:
		root = n
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c as MeshInstance3D
		if on:
			mi.material_overlay = mat(enemy, mi.mesh is BoxMesh, cel)
		elif mi.material_overlay != null and mi.material_overlay.has_meta("gm"):
			mi.material_overlay = null


static func has_outline(n: Node3D) -> bool:
	return int(n.get_meta("gm_key", 0)) != 0


## 10 Hz scan (call every frame from the HUD; it throttles itself): outlines, the HUD list and the minimap dots.
static func update(tree: SceneTree, ppos: Vector3, delta: float, force: bool = false) -> void:
	_t -= delta
	if _t > 0.0 and not force:
		return
	_t = 0.1
	marks.clear()
	dots.clear()
	near_event = false
	var m: int = mode()
	var side: String = GameState.player_side
	for g in GROUPS:
		for n in tree.get_nodes_in_group(g):
			var nd: Node3D = n as Node3D
			if nd == null:
				continue
			var team: String = str(nd.get("team"))
			if team == "" or team == "Neutral":
				continue
			if bool(nd.get("is_dead")) or str(nd.get("vtype")) in SKIP_TYPES:
				if nd.has_meta("gm_key") and int(nd.get_meta("gm_key")) != 0:
					sync(nd, team != side, false)
				continue
			var enemy: bool = team != side
			var d: float = nd.global_position.distance_to(ppos)
			var ev: Variant = nd.get_meta("gm_event") if nd.has_meta("gm_event") else null
			var in_event: bool = ev != null and (not (ev is Object) or (is_instance_valid(ev) and not bool(ev.get("ended"))))
			var had: bool = int(nd.get_meta("gm_key", 0)) != 0
			var want: bool = m >= OUTLINES and (enemy or in_event) and d < (DROP_RANGE if had else APPLY_RANGE)
			sync(nd, enemy, want)
			if not in_event or d > DOT_RANGE or m < OUTLINES:
				continue
			if dots.size() < MAX_DOTS:
				dots.append([nd, enemy])
			if d <= HUD_RANGE:
				near_event = true
				if enemy:
					_insert_mark(nd, d)


static func _insert_mark(nd: Node3D, d: float) -> void:
	var i: int = marks.size()
	while i > 0 and float((marks[i - 1] as Array)[1]) > d:
		i -= 1
	if i >= MAX_MARKS:
		return
	marks.insert(i, [nd, d, true])
	if marks.size() > MAX_MARKS:
		marks.pop_back()


## Marker smoke for a land battle: yellow on the enemy position (a little towards our own line), white on our own line.
## Returns how many columns were made.
static func battle_smoke(b: Node3D, player_side: String) -> int:
	if mode() < SMOKE or b == null or not is_instance_valid(b):
		return 0
	var e := Vector3.ZERO
	var f := Vector3.ZERO
	var ne: int = 0
	var nf: int = 0
	for u in b.units:
		if not u.alive or not is_instance_valid(u.node):
			continue
		if u.team == player_side:
			f += u.pos()
			nf += 1
		else:
			e += u.pos()
			ne += 1
	if ne == 0 or nf == 0:
		return 0
	e /= float(ne)
	f /= float(nf)
	var toward: Vector3 = (f - e)
	toward.y = 0.0
	var ep: Vector3 = e + toward.normalized() * minf(30.0, toward.length() * 0.3)
	ep.y = GroundKit.ground_y(ep.x, ep.z)
	f.y = GroundKit.ground_y(f.x, f.z)
	_smoke(ep, Color(1.0, 0.72, 0.08))
	_smoke(f, Color(0.96, 0.96, 0.94))
	return 2


static func _smoke(p: Vector3, col: Color) -> void:
	smoke_made += 1
	smoke_log.append([p, col])
	if smoke_log.size() > 32:
		smoke_log.pop_front()
	GroundKit.fx_call("marker_smoke", [p, col, 100.0])
