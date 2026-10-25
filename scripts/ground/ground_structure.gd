class_name GroundStructure
extends GroundTarget
## Static destructible structures: fortifications (bunker, pillbox, battery, radar), infrastructure (bridge,
## rail_yard, port, factory, oil_depot, v1_site) and airfield buildings (hangar, fuel_tank, control_tower).
## Create with GroundStructure.create(kind, team, world_pos, heading_deg). heading < 0 = auto (face the sea).
## -Z local = "front" (gun barrels / quay face the heading). All procedural toon primitives.

const CONFIG := {
	"bunker": {"hp": 150.0, "r": 13.0, "pts": 200, "mult": 0.08, "expl": 1.4},
	"pillbox": {"hp": 100.0, "r": 7.5, "pts": 120, "mult": 0.1, "expl": 1.0},
	"battery": {"hp": 420.0, "r": 60.0, "pts": 800, "mult": 0.05, "expl": 2.5},
	"radar_ch": {"hp": 240.0, "r": 38.0, "pts": 500, "mult": 0.25, "expl": 2.0},
	"radar_wurz": {"hp": 140.0, "r": 18.0, "pts": 400, "mult": 0.25, "expl": 1.6},
	"bridge": {"hp": 300.0, "r": 70.0, "pts": 600, "mult": 0.05, "expl": 2.2},
	"rail_yard": {"hp": 320.0, "r": 80.0, "pts": 600, "mult": 0.35, "expl": 2.4},
	"port": {"hp": 450.0, "r": 95.0, "pts": 700, "mult": 0.1, "expl": 2.6},
	"factory": {"hp": 400.0, "r": 70.0, "pts": 650, "mult": 0.4, "expl": 2.6},
	"oil_depot": {"hp": 280.0, "r": 55.0, "pts": 550, "mult": 0.6, "expl": 3.4},
	"refinery": {"hp": 520.0, "r": 85.0, "pts": 800, "mult": 0.5, "expl": 3.6},
	"v1_site": {"hp": 450.0, "r": 60.0, "pts": 800, "mult": 0.05, "expl": 2.4},
	"hangar": {"hp": 200.0, "r": 26.0, "pts": 150, "mult": 0.3, "expl": 1.6},
	"fuel_tank": {"hp": 40.0, "r": 9.0, "pts": 100, "mult": 1.0, "expl": 2.4},
	"control_tower": {"hp": 80.0, "r": 12.0, "pts": 120, "mult": 0.5, "expl": 1.4},
	"dock_basin": {"hp": 420.0, "r": 90.0, "pts": 680, "mult": 0.1, "expl": 2.5},
	"drydock": {"hp": 460.0, "r": 95.0, "pts": 720, "mult": 0.1, "expl": 2.6},
	"gasworks": {"hp": 360.0, "r": 82.0, "pts": 660, "mult": 0.5, "expl": 3.2},
	"colliery": {"hp": 380.0, "r": 86.0, "pts": 680, "mult": 0.35, "expl": 2.8},
	"goods_yard": {"hp": 300.0, "r": 80.0, "pts": 560, "mult": 0.35, "expl": 2.3},
	"engine_shed": {"hp": 260.0, "r": 62.0, "pts": 480, "mult": 0.35, "expl": 2.1},
	"dam": {"hp": 1400.0, "r": 140.0, "pts": 2500, "mult": 0.03, "expl": 4.0},
	"decoy": {"hp": 260.0, "r": 62.0, "pts": 500, "mult": 0.4, "expl": 2.6},
}

var skind: String = "bunker"
var heading_deg: float = 0.0
var guns: int = 4
var variant: String = ""
var _alive_smoke: Array = []
var _barrel_tips: Array = []
var _dish: Node3D
var _fire_t: float = 6.0
var _collapse: Node3D


static func create(p_kind: String, p_team: String, world_pos: Vector3, p_heading: float = -1.0) -> GroundStructure:
	var g := GroundStructure.new()
	var cfg: Dictionary = CONFIG.get(p_kind, CONFIG["bunker"])
	g.skind = p_kind
	g.kind = p_kind
	g.team = p_team
	g.max_health = cfg["hp"]
	g.hit_radius = cfg["r"]
	g.points = cfg["pts"]
	g.small_mult = cfg["mult"]
	g.explosion_size = cfg["expl"]
	g.smoke_scale = clampf(float(cfg["expl"]) * 0.6, 0.8, 2.4)
	g.smoke_height = 4.0
	g.display_name = p_kind.replace("_", " ").capitalize()
	g.position = Vector3(world_pos.x, GroundKit.ground_y(world_pos.x, world_pos.z), world_pos.z)
	var h: float = p_heading
	if h < 0.0:
		if p_kind in ["battery", "port", "bunker", "pillbox", "v1_site"]:
			var wd: Vector3 = GroundKit.water_dir(world_pos, 320.0)
			h = WorldCoords.dir_to_heading(wd) if wd != Vector3.ZERO else (0.0 if p_team == "Axis" else 180.0)
		else:
			h = randf() * 360.0 if p_kind not in ["bridge"] else 90.0
	g.heading_deg = h
	g.rotation.y = -deg_to_rad(h)
	g._fire_t = randf_range(4.0, 14.0)
	return g


func _post_ready() -> void:
	add_to_group("structure")
	if skind in ["radar_ch", "radar_wurz"]:
		add_to_group("radar")


# ================================================================== models
func _b(root: Node3D, size: Vector3, pos: Vector3, color: Color, rot: Vector3 = Vector3.ZERO, outline: bool = true) -> MeshInstance3D:
	return GroundKit.box(root, size, pos, color, rot, outline)


func _build_intact(root: Node3D) -> void:
	match skind:
		"bunker":
			_build_bunker(root)
		"pillbox":
			_build_pillbox(root)
		"battery":
			_build_battery(root)
		"radar_ch":
			_build_chain_home(root)
		"radar_wurz":
			_build_wurzburg(root)
		"bridge":
			_build_bridge(root)
		"rail_yard":
			_build_rail_yard(root)
		"port":
			_build_port(root)
		"dock_basin":
			_rebase_world(WorldFeatures.build_dock_basin(global_position, _sea(), 2, team, hash(target_id)), root)
		"drydock":
			_rebase_world(WorldFeatures.build_drydock_shipyard(global_position, _sea(), 2, team, hash(target_id)), root)
		"gasworks":
			_rebase_world(IndustryKit.build("gasworks", Vector3(global_position.x, 0.0, global_position.z), heading_deg, 2, team, hash(target_id), false), root)
		"colliery":
			_rebase_world(IndustryKit.build("colliery", Vector3(global_position.x, 0.0, global_position.z), heading_deg, 2, team, hash(target_id), false), root)
		"goods_yard":
			_rebase_world(IndustryKit.build("goods_yard", Vector3(global_position.x, 0.0, global_position.z), heading_deg, 2, team, hash(target_id), false), root)
		"engine_shed":
			_rebase_world(IndustryKit.build("engine_shed", Vector3(global_position.x, 0.0, global_position.z), heading_deg, 2, team, hash(target_id), false), root)
		"factory":
			_build_factory(root)
		"oil_depot":
			_build_oil_depot(root)
		"refinery":
			_build_refinery(root)
		"v1_site":
			_build_v1_site(root)
		"dam":
			_build_dam(root)
		"decoy":
			_build_decoy(root)
		"hangar":
			_build_hangar(root)
		"fuel_tank":
			var ftm := MeshInstance3D.new()
			ftm.mesh = AirfieldAssets.fuel_tank()
			root.add_child(ftm)
		"control_tower":
			_build_control_tower(root)
		_:
			_b(root, Vector3(8, 4, 8), Vector3(0, 2, 0), GroundKit.COL_CONCRETE)


func _sandbags(root: Node3D, center: Vector3, count: int, radius: float, face_open: float = 0.0) -> void:
	for i in count:
		var a: float = TAU * float(i) / float(count)
		if face_open > 0.0 and absf(angle_difference(a, -PI * 0.5)) < face_open:
			continue
		_b(root, Vector3(2.4, 0.9, 1.0), center + Vector3(cos(a) * radius, 0.45, sin(a) * radius), GroundKit.COL_SAND, Vector3(0, -rad_to_deg(a) + 90.0, 0), false)


func _build_bunker(root: Node3D) -> void:
	var c: Color = GroundKit.COL_CONCRETE
	_b(root, Vector3(14, 5.0, 10), Vector3(0, 2.5, 0), c)
	_b(root, Vector3(15, 1.2, 11), Vector3(0, 5.5, 0), c.darkened(0.08))
	_b(root, Vector3(6, 1.1, 0.6), Vector3(0, 3.6, -5.1), GroundKit.COL_DARK, Vector3.ZERO, false)       # embrasure
	_b(root, Vector3(16, 1.6, 6), Vector3(0, 0.8, 7.5), Color(0.34, 0.4, 0.22), Vector3(-16, 0, 0), false)  # earth bank
	_b(root, Vector3(2.2, 3.2, 0.5), Vector3(5.0, 1.6, -5.2), GroundKit.COL_DARK, Vector3.ZERO, false)
	_sandbags(root, Vector3(0, 0, -9), 6, 3.0, 0.0)


func _build_pillbox(root: Node3D) -> void:
	var c: Color = GroundKit.COL_CONCRETE
	GroundKit.cyl(root, 4.4, 5.0, 3.2, Vector3(0, 1.6, 0), c, Vector3.ZERO, 6)
	GroundKit.cyl(root, 5.2, 5.2, 0.7, Vector3(0, 3.5, 0), c.darkened(0.1), Vector3.ZERO, 6)
	_b(root, Vector3(3.2, 0.7, 0.5), Vector3(0, 2.4, -4.4), GroundKit.COL_DARK, Vector3.ZERO, false)
	_sandbags(root, Vector3.ZERO, 8, 6.4, 0.0)


func _build_battery(root: Node3D) -> void:
	var c: Color = GroundKit.COL_CONCRETE
	var n: int = maxi(guns, 2)
	var spacing: float = 30.0
	for i in n:
		var x: float = (float(i) - float(n - 1) * 0.5) * spacing
		var z: float = sin(float(i) * 1.7) * 6.0
		_b(root, Vector3(18, 7.0, 16), Vector3(x, 3.5, z), c)
		_b(root, Vector3(20, 1.4, 18), Vector3(x, 7.6, z), c.darkened(0.1))
		_b(root, Vector3(10, 4.5, 1.0), Vector3(x, 3.4, z - 8.2), GroundKit.COL_DARK, Vector3.ZERO, false)
		# gun barrel pointing out of the casemate toward the sea (-Z)
		var gp := Node3D.new()
		gp.position = Vector3(x, 4.5, z - 5.0)
		root.add_child(gp)
		GroundKit.cyl(gp, 0.7, 0.9, 16.0, Vector3(0, 0, -7.0), Color(0.22, 0.23, 0.25), Vector3(86, 0, 0), 8)
		var tip := Node3D.new()
		tip.position = Vector3(0, 0.6, -15.5)
		gp.add_child(tip)
		_barrel_tips.append(tip)
		_b(root, Vector3(3, 2, 22), Vector3(x + 11, 1.0, z + 12), Color(0.34, 0.4, 0.22), Vector3.ZERO, false)
		GroundKit.cyl(root, 0.0, 6.0, 4.0, Vector3(x - 14, 2.0, z + 6), Color(0.34, 0.4, 0.22), Vector3.ZERO, 8, false)   # earth mounds
	# fire-control post
	_b(root, Vector3(9, 14, 9), Vector3(0, 7.0, 26), c)
	_b(root, Vector3(11, 1.3, 11), Vector3(0, 14.6, 26), c.darkened(0.1))
	_b(root, Vector3(8, 1.2, 0.5), Vector3(0, 12.0, 21.4), GroundKit.COL_DARK, Vector3.ZERO, false)
	# ammunition bunkers and trenches
	for sx in [-1.0, 1.0]:
		_b(root, Vector3(12, 4.0, 10), Vector3(sx * 30.0, 2.0, 24), c.darkened(0.05))
		_b(root, Vector3(2.0, 0.6, 28), Vector3(sx * 14.0, 0.1, 6), GroundKit.COL_DARK.lightened(0.1), Vector3.ZERO, false)


func _build_chain_home(root: Node3D) -> void:
	var steel: Color = Color(0.5, 0.2, 0.18) if team == "Allies" else Color(0.45, 0.45, 0.48)
	var h: float = 150.0
	for ox in [-26.0, 0.0, 26.0]:
		var oz: float = 0.0
		for lx in [-1.0, 1.0]:
			for lz in [-1.0, 1.0]:
				var base: Vector3 = Vector3(ox + lx * 4.0, h * 0.5, oz + lz * 4.0)
				var lean: float = rad_to_deg(atan2(3.0, h))
				GroundKit.cyl(root, 0.3, 0.55, h, base, steel, Vector3(-lz * lean, 0, lx * lean), 4, false)
		for k in 6:
			var y: float = 12.0 + float(k) * 24.0
			var w: float = lerpf(9.0, 4.5, y / h)
			_b(root, Vector3(w, 0.5, w), Vector3(ox, y, oz), steel, Vector3.ZERO, false)
		# cross-bracing look: two diagonal slats on the front face
		_b(root, Vector3(0.4, h * 0.95, 0.4), Vector3(ox, h * 0.5, -4.3), steel.darkened(0.1), Vector3(0, 0, 3), false)
	# aerial arrays between masts
	for y in [70.0, 118.0]:
		_b(root, Vector3(54, 2.0, 0.5), Vector3(0, y, 0), steel.darkened(0.2), Vector3.ZERO, false)
	_b(root, Vector3(18, 7, 12), Vector3(0, 3.5, 24), GroundKit.COL_CONCRETE)
	_b(root, Vector3(20, 1.0, 14), Vector3(0, 7.5, 24), GroundKit.COL_CONCRETE.darkened(0.15))
	_b(root, Vector3(10, 4, 8), Vector3(26, 2, 22), GroundKit.COL_BRICK)
	smoke_height = 6.0


func _build_wurzburg(root: Node3D) -> void:
	var c: Color = GroundKit.COL_CONCRETE
	_b(root, Vector3(10, 5, 10), Vector3(0, 2.5, 0), c)
	GroundKit.cyl(root, 1.0, 1.4, 8.0, Vector3(0, 9.0, 0), Color(0.3, 0.32, 0.3), Vector3.ZERO, 8)
	_dish = Node3D.new()
	_dish.position = Vector3(0, 13.0, 0)
	root.add_child(_dish)
	var d: MeshInstance3D = GroundKit.sphere(_dish, 6.5, Vector3(0, 0, -1.5), Color(0.5, 0.52, 0.5), Vector3(1.0, 1.0, 0.25))
	d.rotation_degrees = Vector3(-15, 0, 0)
	GroundKit.cyl(_dish, 0.15, 0.15, 5.0, Vector3(0, 0, -4.2), Color(0.2, 0.2, 0.2), Vector3(90, 0, 0), 4, false)
	# Freya frame
	_b(root, Vector3(18, 0.6, 0.6), Vector3(-26, 12, 0), Color(0.4, 0.4, 0.42), Vector3.ZERO, false)
	_b(root, Vector3(18, 0.6, 0.6), Vector3(-26, 18, 0), Color(0.4, 0.4, 0.42), Vector3.ZERO, false)
	_b(root, Vector3(0.6, 12, 0.6), Vector3(-35, 12, 0), Color(0.4, 0.4, 0.42), Vector3.ZERO, false)
	_b(root, Vector3(0.6, 12, 0.6), Vector3(-17, 12, 0), Color(0.4, 0.4, 0.42), Vector3.ZERO, false)
	_sandbags(root, Vector3.ZERO, 12, 9.0)


func _build_bridge(root: Node3D) -> void:
	var L: float = 150.0
	var steel: Color = Color(0.36, 0.38, 0.42)
	var concrete: Color = GroundKit.COL_CONCRETE
	_collapse = Node3D.new()
	root.add_child(_collapse)
	# deck: along local X so heading 90 = east-west... deck runs along X
	_b(root, Vector3(L, 2.4, 13.0), Vector3(0, 14.0, 0), Color(0.3, 0.3, 0.32))
	_b(root, Vector3(L, 1.0, 1.0), Vector3(0, 15.6, 6.4), steel, Vector3.ZERO, false)
	_b(root, Vector3(L, 1.0, 1.0), Vector3(0, 15.6, -6.4), steel, Vector3.ZERO, false)
	for i in 5:
		var x: float = (float(i) - 2.0) * (L / 4.0 - 4.0)
		_b(root, Vector3(5.0, 14.0, 10.0), Vector3(x, 6.0, 0), concrete)
	# arched truss on both sides
	for sz in [-6.0, 6.0]:
		var prev: Vector3 = Vector3.ZERO
		for i in 9:
			var t: float = float(i) / 8.0
			var x2: float = lerpf(-L * 0.42, L * 0.42, t)
			var y2: float = 14.0 + 22.0 * (1.0 - pow(2.0 * t - 1.0, 2.0))
			var p: Vector3 = Vector3(x2, y2, sz)
			_b(root, Vector3(0.7, y2 - 14.0, 0.7), Vector3(x2, 14.0 + (y2 - 14.0) * 0.5, sz), steel, Vector3.ZERO, false)
			if i > 0:
				var mid: Vector3 = (p + prev) * 0.5
				var ang: float = rad_to_deg(atan2(p.y - prev.y, p.x - prev.x))
				_b(root, Vector3(prev.distance_to(p) + 0.4, 1.0, 1.0), mid, steel, Vector3(0, 0, ang), false)
			prev = p
	hit_radius = 75.0


func _build_wreck_bridge(root: Node3D) -> void:
	var L: float = 150.0
	var concrete: Color = GroundKit.COL_CONCRETE.darkened(0.45)
	for i in 5:
		var x: float = (float(i) - 2.0) * (L / 4.0 - 4.0)
		if i == 2:
			continue
		_b(root, Vector3(5.0, 14.0, 10.0), Vector3(x, 6.0, 0), concrete)
	_b(root, Vector3(L * 0.42, 2.4, 13.0), Vector3(-L * 0.28, 8.0, 0), Color(0.12, 0.12, 0.13), Vector3(0, 0, 18))
	_b(root, Vector3(L * 0.42, 2.4, 13.0), Vector3(L * 0.28, 5.0, 0), Color(0.12, 0.12, 0.13), Vector3(0, 0, -28))
	_b(root, Vector3(40, 1.0, 1.0), Vector3(-8, 4.0, 5), Color(0.15, 0.15, 0.17), Vector3(0, 20, 55), false)


func _build_rail_yard(root: Node3D) -> void:
	var rail: Color = Color(0.2, 0.18, 0.16)
	var ballast: Color = Color(0.4, 0.38, 0.34)
	_b(root, Vector3(150, 0.4, 66), Vector3(0, 0.15, 0), ballast, Vector3.ZERO, false)
	for i in 6:
		var z: float = (float(i) - 2.5) * 10.0
		_b(root, Vector3(150, 0.4, 0.8), Vector3(0, 0.55, z - 0.9), rail, Vector3.ZERO, false)
		_b(root, Vector3(150, 0.4, 0.8), Vector3(0, 0.55, z + 0.9), rail, Vector3.ZERO, false)
		var x: float = -60.0 + randf() * 20.0
		var cars: int = 3 + randi() % 5
		for k in cars:
			var col: Color = Color(0.38, 0.27, 0.2) if (k + i) % 3 != 0 else Color(0.32, 0.32, 0.3)
			_b(root, Vector3(8.0, 3.2, 3.2), Vector3(x + float(k) * 9.5, 2.2, z), col)
			_b(root, Vector3(8.4, 0.3, 3.4), Vector3(x + float(k) * 9.5, 3.9, z), col.darkened(0.3), Vector3.ZERO, false)
	for lz in [-15.0, 25.0]:
		_b(root, Vector3(9, 3.4, 3.2), Vector3(40.0, 2.0, lz), Color(0.1, 0.1, 0.12))
		GroundKit.cyl(root, 0.5, 0.7, 2.0, Vector3(37.0, 4.8, lz), Color(0.1, 0.1, 0.12), Vector3.ZERO, 6)
	_b(root, Vector3(50, 9, 22), Vector3(-30, 4.5, -48), GroundKit.COL_BRICK)
	_b(root, Vector3(52, 1.8, 24), Vector3(-30, 10, -48), Color(0.3, 0.28, 0.27), Vector3.ZERO, false)
	GroundKit.cyl(root, 3.0, 3.0, 10.0, Vector3(30, 12, -45), Color(0.45, 0.42, 0.38), Vector3.ZERO, 8)
	for sx in [-1.0, 1.0]:
		GroundKit.cyl(root, 0.4, 0.5, 8.0, Vector3(30 + sx * 2.0, 4.0, -45), Color(0.3, 0.3, 0.3), Vector3.ZERO, 4, false)


## Unit direction towards open water from this structure (falls back to -Z).
func _sea() -> Vector3:
	var s: Vector3 = GroundKit.water_dir(global_position, 320.0)
	return s if s != Vector3.ZERO else Vector3(0, 0, -1)


## Delegate a world-space WorldFeatures container into this structure's local space: the waterfront builders
## position their meshes in world coordinates, so we cancel the structure's own transform (render at world
## identity). Added under the "Intact" root so it hides with the rest of the building when the target dies.
func _rebase_world(w: Node3D, root: Node3D) -> void:
	if w == null:
		return
	root.add_child(w)
	w.global_transform = Transform3D.IDENTITY


## 3.4: a 'port' target and a streamed site 'port' now look the same - both come from WorldFeatures.build_port.
func _build_port(root: Node3D) -> void:
	_rebase_world(WorldFeatures.build_port(Vector3(global_position.x, 0.0, global_position.z), _sea(), 2, team, hash(target_id)), root)


func _build_factory(root: Node3D) -> void:
	var brick: Color = GroundKit.COL_BRICK.darkened(0.1)
	_b(root, Vector3(70, 12, 40), Vector3(0, 6, 0), brick)
	for i in 5:
		var pm := MeshInstance3D.new()
		pm.mesh = GroundKit.prism_mesh(14.0, 40.0, 6.0)
		pm.material_override = GroundKit.mat(Color(0.32, 0.33, 0.35), true)
		pm.position = Vector3(-28.0 + float(i) * 14.0, 12.0, 0)
		root.add_child(pm)
	_b(root, Vector3(30, 9, 24), Vector3(-10, 4.5, 36), brick.lightened(0.05))
	_b(root, Vector3(32, 1.2, 26), Vector3(-10, 9.6, 36), Color(0.3, 0.3, 0.32), Vector3.ZERO, false)
	for x in [28.0, 40.0, 50.0]:
		GroundKit.cyl(root, 1.7, 2.4, 42.0 + float(int(x) % 5) * 2.0, Vector3(x, 21.0, -10), brick.lightened(0.1), Vector3.ZERO, 10)
		GroundKit.cyl(root, 1.9, 1.9, 1.5, Vector3(x, 41.0, -10), Color(0.8, 0.8, 0.75), Vector3.ZERO, 10, false)
	GroundKit.cyl(root, 4.0, 4.0, 12.0, Vector3(-48, 6.0, 30), Color(0.55, 0.55, 0.55), Vector3.ZERO, 10)
	_b(root, Vector3(40, 3, 6), Vector3(0, 1.5, -30), GroundKit.COL_DARK.lightened(0.12), Vector3.ZERO, false)   # loading rail


func _build_oil_depot(root: Node3D) -> void:
	var c: Color = Color(0.55, 0.56, 0.54)
	for i in 6:
		var x: float = (float(i % 3) - 1.0) * 24.0
		var z: float = (float(i / 3) - 0.5) * 26.0
		GroundKit.cyl(root, 9.0, 9.0, 10.0, Vector3(x, 5.0, z), c if i % 2 == 0 else c.darkened(0.1), Vector3.ZERO, 14)
		GroundKit.cyl(root, 9.4, 9.4, 0.6, Vector3(x, 10.2, z), c.darkened(0.25), Vector3.ZERO, 14, false)
		_b(root, Vector3(21, 1.3, 21), Vector3(x, 0.4, z), Color(0.35, 0.33, 0.3), Vector3.ZERO, false)           # bund
	_b(root, Vector3(80, 0.6, 1.0), Vector3(0, 1.5, 0), Color(0.2, 0.2, 0.22), Vector3.ZERO, false)             # pipe
	_b(root, Vector3(14, 6, 10), Vector3(0, 3, 40), GroundKit.COL_BRICK)
	smoke_scale = 3.0
	smoke_height = 8.0


## Oil refinery: tank farm, tall distillation columns, a furnace block with chimneys, pipe racks and a flare stack.
func _build_refinery(root: Node3D) -> void:
	var steel: Color = Color(0.62, 0.64, 0.64)
	var tank: Color = Color(0.58, 0.58, 0.55)
	for i in 8:
		var x: float = (float(i % 4) - 1.5) * 24.0 + 20.0
		var z: float = (float(i / 4) - 0.5) * 28.0 + 38.0
		GroundKit.cyl(root, 8.5, 8.5, 9.0, Vector3(x, 4.5, z), tank if i % 3 else tank.darkened(0.12), Vector3.ZERO, 14)
		GroundKit.cyl(root, 8.9, 8.9, 0.6, Vector3(x, 9.3, z), tank.darkened(0.25), Vector3.ZERO, 14, false)
		_b(root, Vector3(20, 1.2, 20), Vector3(x, 0.4, z), Color(0.35, 0.33, 0.3), Vector3.ZERO, false)       # bund wall
	for i in 3:
		var cx: float = -46.0 + float(i) * 14.0
		GroundKit.cyl(root, 2.6, 2.8, 36.0, Vector3(cx, 18.0, -22.0), steel, Vector3.ZERO, 10)
		for b in 3:
			GroundKit.cyl(root, 3.1, 3.1, 0.7, Vector3(cx, 8.0 + float(b) * 9.0, -22.0), steel.darkened(0.25), Vector3.ZERO, 10, false)
	GroundKit.cyl(root, 4.5, 4.5, 20.0, Vector3(-6.0, 10.0, -22.0), steel.lightened(0.05), Vector3.ZERO, 12)         # reactor drum
	_b(root, Vector3(20, 10, 14), Vector3(28.0, 5.0, -22.0), GroundKit.COL_BRICK.darkened(0.15))                    # furnace house
	GroundKit.cyl(root, 1.4, 1.8, 32.0, Vector3(22.0, 26.0, -22.0), GroundKit.COL_BRICK.lightened(0.05), Vector3.ZERO, 10)
	GroundKit.cyl(root, 1.4, 1.8, 28.0, Vector3(34.0, 24.0, -22.0), GroundKit.COL_BRICK.lightened(0.05), Vector3.ZERO, 10)
	_b(root, Vector3(110, 0.8, 1.2), Vector3(0, 6.0, -8.0), Color(0.25, 0.25, 0.27), Vector3.ZERO, false)           # pipe racks
	_b(root, Vector3(110, 0.8, 1.2), Vector3(0, 7.2, -8.0), Color(0.3, 0.2, 0.15), Vector3.ZERO, false)
	for px in [-50.0, -25.0, 0.0, 25.0, 50.0]:
		_b(root, Vector3(1.0, 7.0, 1.0), Vector3(px, 3.5, -8.0), Color(0.22, 0.22, 0.24), Vector3.ZERO, false)
	GroundKit.cyl(root, 0.7, 1.0, 46.0, Vector3(-62.0, 23.0, 14.0), Color(0.35, 0.35, 0.36), Vector3.ZERO, 8)        # flare stack
	GroundKit.cyl(root, 0.0, 1.4, 3.4, Vector3(-62.0, 48.0, 14.0), Color(1.0, 0.55, 0.12), Vector3.ZERO, 8, false)    # flare flame
	_b(root, Vector3(16, 6, 12), Vector3(-30.0, 3.0, 36.0), GroundKit.COL_BRICK)
	smoke_scale = 3.0
	smoke_height = 8.0


func _build_v1_site(root: Node3D) -> void:
	var c: Color = GroundKit.COL_CONCRETE
	var big: bool = variant == "dome" or target_id.contains("wizernes") or target_id.contains("mimoyecques") or target_id.contains("watten") or target_id.contains("eperlecques")
	if big:
		GroundKit.sphere(root, 30.0, Vector3(0, 0, 0), c, Vector3(1.0, 0.55, 1.0))
		_b(root, Vector3(24, 14, 30), Vector3(0, 7, 28), c.darkened(0.05))
		_b(root, Vector3(10, 9, 2), Vector3(0, 5.0, 43.2), GroundKit.COL_DARK, Vector3.ZERO, false)
		for sx in [-1.0, 1.0]:
			_b(root, Vector3(1.6, 6, 60), Vector3(sx * 14.0, 1.0, 55), Color(0.3, 0.3, 0.3), Vector3(0, 0, sx * 5.0), false)
	else:
		# launch ramp (inclined) with trestles and a V-1 on the rail
		_b(root, Vector3(3.0, 1.6, 70), Vector3(0, 7.0, -10), Color(0.35, 0.35, 0.37), Vector3(-12, 0, 0))
		for k in 5:
			var z: float = -38.0 + float(k) * 14.0
			_b(root, Vector3(2.4, 3.0 + float(k) * 2.2, 2.4), Vector3(0, (3.0 + float(k) * 2.2) * 0.5 - 0.0, z), Color(0.3, 0.3, 0.3), Vector3.ZERO, false)
		_b(root, Vector3(1.0, 0.8, 7.0), Vector3(0, 11.4, -28), Color(0.28, 0.3, 0.28))
		_b(root, Vector3(7.0, 0.3, 1.4), Vector3(0, 11.4, -27), Color(0.28, 0.3, 0.28), Vector3.ZERO, false)
		_b(root, Vector3(16, 6, 14), Vector3(18, 3, 18), c)
		_b(root, Vector3(18, 1.0, 16), Vector3(18, 6.5, 18), c.darkened(0.1), Vector3.ZERO, false)
		_b(root, Vector3(12, 5, 8), Vector3(-18, 2.5, 22), Color(0.4, 0.3, 0.22))
	smoke_scale = 1.8


## A decoy "target" (P4): the fake works a decoy site pretends to be, so a raid wasted on it reads as a hit
## on a real factory. A long low shadow-factory shed with chimneys, a boiler house, decoy outbuildings and a
## dummy flare stack. Local -Z = front (the decoy site's heading), matching the rest of the structures.
func _build_decoy(root: Node3D) -> void:
	var brick: Color = GroundKit.COL_BRICK.darkened(0.12)
	var roofs: Color = Color(0.34, 0.35, 0.36)
	_b(root, Vector3(72, 11, 34), Vector3(0, 5.5, 0), brick)
	for i in 5:
		var pm := MeshInstance3D.new()
		pm.mesh = GroundKit.prism_mesh(13.0, 34.0, 5.0)
		pm.material_override = GroundKit.mat(roofs, true)
		pm.position = Vector3(-28.0 + float(i) * 14.0, 11.0, 0)
		root.add_child(pm)
	_b(root, Vector3(26, 8, 20), Vector3(-14, 4, 30), brick.lightened(0.05))
	GroundKit.cyl(root, 1.6, 2.2, 40.0, Vector3(30, 20, -12), brick.lightened(0.08), Vector3.ZERO, 10)
	GroundKit.cyl(root, 1.8, 1.8, 1.4, Vector3(30, 40, -12), Color(0.8, 0.8, 0.75), Vector3.ZERO, 10, false)
	for sx in [-1.0, 1.0]:
		_b(root, Vector3(16, 6, 12), Vector3(sx * 44.0, 3, 14), brick)
	_b(root, Vector3(3, 6, 3), Vector3(-40, 3, -6), GroundKit.COL_STEEL, Vector3.ZERO, false)
	smoke_scale = 2.4
	smoke_height = 6.0


## Curved gravity/masonry dam across a valley (the Dam Busters silhouette, P3): a bowed wall, a crest roadway
## with parapets, two valve towers standing on the upstream face, a spillway chute at one end and light AA on
## the crest. Local -Z = downstream (the valley below); the reservoir (DamKit.build) lies on local +Z.
func _build_dam(root: Node3D) -> void:
	var conc: Color = Color(0.58, 0.56, 0.51)
	var stone: Color = Color(0.5, 0.49, 0.45)
	var len_x: float = 430.0
	var h: float = 84.0
	var segs: int = 16
	var seg_w: float = len_x / float(segs)
	for i in segs:
		var t: float = (float(i) + 0.5) / float(segs)
		var x: float = -len_x * 0.5 + (float(i) + 0.5) * seg_w
		var z: float = sin(t * PI) * 24.0                       # bows upstream (+Z)
		var ang: float = rad_to_deg(atan2(24.0 * PI * cos(t * PI) / len_x, 1.0))
		_b(root, Vector3(seg_w + 1.5, h, 26.0), Vector3(x, h * 0.5 - 3.0, z), conc.darkened(0.04 * float(i % 2)), Vector3(0.0, ang, 0.0))
	# crest roadway, parapets and a kerb
	_b(root, Vector3(len_x + 10.0, 2.4, 18.0), Vector3(0.0, h - 2.0, 8.0), Color(0.34, 0.33, 0.31))
	for sx in [-1.0, 1.0]:
		_b(root, Vector3(len_x, 1.4, 1.2), Vector3(0.0, h - 0.2, 8.0 + sx * 8.4), stone, Vector3.ZERO, false)
	# two valve towers standing on the upstream face
	for sx2 in [-1.0, 1.0]:
		_b(root, Vector3(9.0, 18.0, 9.0), Vector3(sx2 * 76.0, h - 4.0, 30.0), conc)
		_b(root, Vector3(11.0, 2.0, 11.0), Vector3(sx2 * 76.0, h + 6.0, 30.0), conc.darkened(0.12))
	# spillway chute at the west end of the crest
	_b(root, Vector3(64.0, 6.0, 46.0), Vector3(-len_x * 0.5 - 24.0, 4.0, -22.0), conc.darkened(0.1))
	for k in 6:
		_b(root, Vector3(64.0, 2.0, 7.0), Vector3(-len_x * 0.5 - 24.0, 8.0 - float(k) * 3.4, -6.0 - float(k) * 7.0), conc.darkened(0.2), Vector3(-20.0, 0.0, 0.0))
	# light AA on the crest (the Möhne carried light AA on and beside the wall)
	_b(root, Vector3(7.0, 1.2, 7.0), Vector3(0.0, h + 0.6, 8.0), GroundKit.COL_DARK, Vector3.ZERO, false)
	hit_radius = 140.0
	fire_on_death = false          # a breached dam pours water, not fire (see _build_wreck_dam / _on_destroyed)


## The breached wall (P3): a gap torn through the middle with the ends left standing, tumbled masonry in the
## gap and the reservoir pouring through as a pale unshaded curtain. Local -Z = downstream.
func _build_wreck_dam(root: Node3D) -> void:
	var conc: Color = Color(0.5, 0.49, 0.45)
	var len_x: float = 430.0
	var h: float = 84.0
	for sx in [-1.0, 1.0]:
		var x0: float = sx * (len_x * 0.28 + 60.0)
		_b(root, Vector3(len_x * 0.42, h, 26.0), Vector3(x0, h * 0.5 - 3.0, 0.0), conc.darkened(0.12), Vector3(0.0, 0.0, sx * -5.0))
	var blocks: Array = [Vector2(-42.0, 6.0), Vector2(-18.0, 2.0), Vector2(0.0, 9.0), Vector2(20.0, 1.0), Vector2(44.0, 5.0), Vector2(-8.0, -2.0), Vector2(30.0, -1.0)]
	for i in blocks.size():
		var bp: Vector2 = blocks[i]
		_b(root, Vector3(15.0, 8.0, 13.0), Vector3(bp.x, bp.y, -6.0 + float(i % 3) * 7.0), conc, Vector3(float(i * 23 % 40) - 20.0, float(i * 37 % 180), float(i * 17 % 30) - 15.0))
	var flood := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(len_x * 0.5, 3.0, 60.0)
	flood.mesh = fm
	flood.material_override = GroundKit.glow_mat(Color(0.62, 0.68, 0.72), 0.85, false)
	flood.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flood.position = Vector3(0.0, 3.0, -30.0)
	flood.rotation_degrees = Vector3(18.0, 0.0, 0.0)
	root.add_child(flood)


## Curved-roof hangar: side/end walls, an arched roof, big sliding doors and side pilasters.
func _build_hangar(root: Node3D) -> void:
	var L: float = 48.0
	var W: float = 36.0
	var wall_h: float = 6.5
	var rise: float = 8.5
	var wall: Color = Color(0.54, 0.50, 0.43) if team == "Allies" else Color(0.45, 0.45, 0.41)
	var roof_col: Color = wall.darkened(0.30)
	var trim: Color = wall.darkened(0.55)
	var door_col: Color = Color(0.19, 0.20, 0.21)
	# side walls
	for sx in [-1.0, 1.0]:
		_b(root, Vector3(1.0, wall_h, L), Vector3(sx * (W * 0.5 - 0.5), wall_h * 0.5, 0), wall)
	# end walls
	for sz in [-1.0, 1.0]:
		_b(root, Vector3(W, wall_h, 1.0), Vector3(0, wall_h * 0.5, sz * (L * 0.5 - 0.5)), wall)
	# arched roof
	_arch_roof(root, L, W, rise, wall_h, roof_col)
	_b(root, Vector3(1.6, 0.7, L), Vector3(0, wall_h + rise, 0), roof_col.darkened(0.12), Vector3.ZERO, false)
	# sliding doors on the front (-Z): dark panels with vertical seams and a lintel
	_b(root, Vector3(W * 0.88, wall_h * 0.9, 0.35), Vector3(0, wall_h * 0.45, -L * 0.5 + 0.15), door_col, Vector3.ZERO, false)
	for k in 6:
		var dx: float = (float(k) - 2.5) * (W * 0.88 / 7.0)
		_b(root, Vector3(0.28, wall_h * 0.9, 0.5), Vector3(dx, wall_h * 0.45, -L * 0.5), trim, Vector3.ZERO, false)
	_b(root, Vector3(W * 0.94, 1.0, 1.1), Vector3(0, wall_h * 0.96, -L * 0.5 + 0.25), trim, Vector3.ZERO, false)
	# pilasters along the side walls
	for k in 5:
		var z: float = -L * 0.5 + 4.0 + float(k) * (L - 8.0) / 4.0
		for sx2 in [-1.0, 1.0]:
			_b(root, Vector3(1.4, wall_h, 1.3), Vector3(sx2 * (W * 0.5), wall_h * 0.5, z), trim, Vector3.ZERO, false)


## Multi-storey control tower with a glazed observation room and railing.
func _build_control_tower(root: Node3D) -> void:
	var conc := Color(0.64, 0.60, 0.52)
	var glass := Color(0.24, 0.31, 0.34)
	var roof := Color(0.33, 0.33, 0.35)
	_b(root, Vector3(20, 5.5, 13), Vector3(0, 2.75, 0), conc)                       # ops block
	_b(root, Vector3(9, 13, 9), Vector3(0, 5.5 + 6.5, 0), conc)                     # shaft
	_b(root, Vector3(15, 4.5, 15), Vector3(0, 19.0, 0), conc)                       # observation room
	_b(root, Vector3(13.2, 3.0, 13.2), Vector3(0, 19.2, 0), glass, Vector3.ZERO, false)  # glazing band
	_b(root, Vector3(16.4, 0.8, 16.4), Vector3(0, 21.6, 0), roof)                    # roof slab
	_b(root, Vector3(6, 0.8, 1.0), Vector3(0, 22.4, 0), roof.darkened(0.2), Vector3.ZERO, false)
	# railing posts around the roof edge
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		_b(root, Vector3(0.4, 1.6, 0.4), Vector3(cos(a) * 7.4, 22.8, sin(a) * 7.4), roof.darkened(0.3), Vector3.ZERO, false)
	# external stair / entrance
	_b(root, Vector3(3.0, 5.5, 4.0), Vector3(0, 2.75, 8.4), conc.darkened(0.08))


## Semicircular arched roof made of angled slabs.
func _arch_roof(root: Node3D, length: float, width: float, rise: float, base_y: float, col: Color) -> void:
	var n: int = 7
	for i in n:
		var a0: float = PI * float(i) / float(n)
		var a1: float = PI * float(i + 1) / float(n)
		var x0: float = cos(a0) * width * 0.5
		var y0: float = sin(a0) * rise
		var x1: float = cos(a1) * width * 0.5
		var y1: float = sin(a1) * rise
		var mid := Vector3((x0 + x1) * 0.5, base_y + (y0 + y1) * 0.5, 0.0)
		var seg: float = Vector2(x1 - x0, y1 - y0).length()
		var ang: float = rad_to_deg(atan2(y1 - y0, x1 - x0))
		_b(root, Vector3(seg + 0.3, 0.7, length), mid, col, Vector3(0, 0, ang))


func _build_wreck(root: Node3D) -> void:
	if skind == "bridge":
		_build_wreck_bridge(root)
		return
	if skind == "dam":
		_build_wreck_dam(root)
		return
	if skind == "decoy":
		# a burned-out decoy: collapsed shed, tumbled outbuildings, scorched ground, a fallen chimney
		var dd: Color = Color(0.13, 0.12, 0.11)
		_b(root, Vector3(72, 3.0, 34), Vector3(0, 1.5, 0), dd, Vector3(0, 0, 3))
		for i in 4:
			_b(root, Vector3(16, 5.0, 12), Vector3((float(i) - 1.5) * 22.0, 2.5, 20), dd.lightened(0.04), Vector3(0, float(i * 37 % 180), 8))
		GroundKit.cyl(root, 1.6, 2.2, 18.0, Vector3(30, 6, -12), dd, Vector3(80, 0, 0), 8)
		return
	var d: Color = Color(0.11, 0.1, 0.09)
	var r: float = clampf(hit_radius * 0.5, 4.0, 40.0)
	match skind:
		"radar_ch":
			for ox in [-26.0, 0.0, 26.0]:
				_b(root, Vector3(2.0, 60.0, 2.0), Vector3(ox, 3.0, randf_range(-8, 8)), d, Vector3(randf_range(80, 90), randf_range(0, 180), 0), false)
			_b(root, Vector3(18, 3, 12), Vector3(0, 1.5, 24), d, Vector3(0, 5, 3))
		"battery":
			var n: int = maxi(guns, 2)
			for i in n:
				var x: float = (float(i) - float(n - 1) * 0.5) * 30.0
				_b(root, Vector3(18, 4.0, 16), Vector3(x, 2.0, sin(float(i) * 1.7) * 6.0), d.lightened(0.04), Vector3(0, i * 9, 4))
				_b(root, Vector3(2, 2, 14), Vector3(x + 5, 3.0, -8), d, Vector3(15, 25, 0), false)
			_b(root, Vector3(9, 6, 9), Vector3(0, 3, 26), d, Vector3(8, 0, 6))
		"port":
			_b(root, Vector3(170, 1.4, 46), Vector3(0, 0.7, -10), d.lightened(0.05), Vector3.ZERO, false)
			for i in 4:
				_b(root, Vector3(30, 3.0, 18), Vector3(-60.0 + float(i) * 38.0, 1.8, 6), d, Vector3(0, i * 7, 3))
			_b(root, Vector3(2, 14, 2), Vector3(-30, 6, -26), d, Vector3(70, 0, 20), false)
		"factory":
			_b(root, Vector3(70, 3, 40), Vector3(0, 1.5, 0), d, Vector3(0, 0, 2))
			_b(root, Vector3(20, 6, 14), Vector3(-15, 3.5, 5), d.lightened(0.05), Vector3(10, 20, 10))
			GroundKit.cyl(root, 1.7, 2.2, 20.0, Vector3(34, 2.5, -4), d, Vector3(85, 10, 0), 8)
		"rail_yard":
			for i in 7:
				_b(root, Vector3(8, 2.0, 3), Vector3(randf_range(-60, 60), 1.0, randf_range(-26, 26)), d, Vector3(randf_range(-10, 10), randf_range(0, 180), randf_range(-20, 20)), false)
			_b(root, Vector3(50, 3.0, 22), Vector3(-30, 1.5, -48), d, Vector3(0, 0, 3))
		"refinery", "oil_depot":
			for i in 6:
				GroundKit.cyl(root, 9.0, 9.5, 2.5, Vector3((float(i % 3) - 1.0) * 24.0, 1.2, (float(i / 3) - 0.5) * 26.0), d, Vector3.ZERO, 12, false)
		"hangar":
			_b(root, Vector3(34, 3, 40), Vector3(0, 1.5, 0), d, Vector3(0, 8, 3))
			_b(root, Vector3(18, 1.2, 38), Vector3(8, 4.0, 0), d.lightened(0.05), Vector3(0, 0, 40), false)
		"v1_site":
			_b(root, Vector3(30, 5, 30), Vector3(0, 2.5, 10), d, Vector3(0, 12, 4))
			_b(root, Vector3(3, 1.5, 60), Vector3(0, 2.0, -20), d, Vector3(0, 5, 14), false)
		_:
			_b(root, Vector3(r * 2.0, r * 0.4, r * 1.6), Vector3(0, r * 0.2, 0), d, Vector3(0, 12, 3))
			_b(root, Vector3(r, r * 0.35, r * 0.8), Vector3(r * 0.3, r * 0.5, 0), d.lightened(0.05), Vector3(10, 30, 15))


func _post_ready_late() -> void:
	pass


# ================================================================== behaviour
func _ready() -> void:
	super._ready()
	if skind in ["factory", "oil_depot", "refinery"] and not start_wrecked:
		# idle smoke: thin pale plumes from the chimneys
		var tops: Array = []
		match skind:
			"factory":
				tops = [Vector3(28.0, 43.5, -10.0), Vector3(40.0, 43.5, -10.0), Vector3(50.0, 43.5, -10.0)]
			"refinery":
				tops = [Vector3(22.0, 42.5, -22.0), Vector3(34.0, 38.5, -22.0)]
			"oil_depot":
				tops = [Vector3(0.0, 8.0, 40.0)]
		# not every chimney smokes: half the works are cold, and a working one has a single stack alight
		if randf() < 0.5:
			tops = []
		elif tops.size() > 1:
			tops = [tops[randi() % tops.size()]]
		for tp in tops:
			var s: Node3D = GroundKit.stack_smoke(self, tp, 1.0 if skind != "oil_depot" else 0.6)
			if s:
				_alive_smoke.append(s)


func _process(delta: float) -> void:
	if is_dead:
		return
	if _dish:
		_dish.rotation.y += delta * 0.8
	if skind == "battery" and not _barrel_tips.is_empty():
		_fire_t -= delta
		if _fire_t <= 0.0:
			_fire_t = randf_range(8.0, 20.0)
			var pl: Node3D = GroundKit.player_node()
			if pl and pl.global_position.distance_to(global_position) < 6000.0:
				var tip: Node3D = _barrel_tips[randi() % _barrel_tips.size()]
				GroundKit.explosion(tip.global_position, 0.5)


func _on_destroyed(_killer: Node) -> void:
	for s in _alive_smoke:
		if is_instance_valid(s):
			(s as Node).queue_free()
	_alive_smoke.clear()
	if is_inside_tree() and skind == "dam":
		# a breached dam pours water off the downstream face (pale spray columns, no fire)
		DamFlood.spawn(self)
		for i in 3:
			GroundKit.persistent_smoke(self, Vector3(-60.0 + float(i) * 60.0, 8.0, -34.0), 2.4, false)
		return
	if is_inside_tree() and skind == "decoy":
		# a struck decoy fires up exactly as intended (it is built to burn): black columns with fire
		for i in 3:
			GroundKit.persistent_smoke(self, Vector3(-24.0 + float(i) * 24.0, 5.0, 6.0), 2.2, false)
		return
	if is_inside_tree() and skind in INDUSTRIAL:
		# the whole works goes up: several fat black columns with fire at their base
		var cols: int = 5 if skind != "factory" else 3
		for i in cols:
			var lp := Vector3(randf_range(-0.5, 0.5) * hit_radius, 6.0, randf_range(-0.4, 0.4) * hit_radius)
			GroundKit.persistent_smoke(self, lp, 3.2 + randf() * 1.6, false)


const INDUSTRIAL := ["factory", "oil_depot", "refinery", "hangar", "fuel_tank", "gasworks", "colliery", "goods_yard", "engine_shed"]
var _hit_level: int = 0
var _tint_mat: StandardMaterial3D
var _tint_meshes: Array = []


## A damaged building turns redder the more it is hurt (a translucent red coat over every surface), instead of a
## red fire glow that read as blinking red squares from a distance.
func _damage_tint() -> void:
	var f: float = clampf(1.0 - health / maxf(max_health, 1.0), 0.0, 1.0)
	if f <= 0.02:
		return
	if _tint_mat == null:
		_tint_mat = StandardMaterial3D.new()
		_tint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_tint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tint_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_tint_mat.albedo_color = Color(1.0, 0.1, 0.06, 0.0)
		for n in find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi != null and mi.visible and _tint_meshes.size() < 240:
				mi.material_overlay = _tint_mat
				_tint_meshes.append(mi)
	_tint_mat.albedo_color = Color(1.0, 0.1, 0.06, clampf(0.18 + 0.5 * f, 0.0, 0.68))


## Industrial buildings start pouring black smoke from the first hit, and it gets worse the more damage they take.
func take_damage(amount: float, source: Node = null) -> void:
	super.take_damage(amount, source)
	_damage_tint()
	if is_dead or not (skind in INDUSTRIAL) or not is_inside_tree():
		return
	var f: float = 1.0 - health / maxf(max_health, 1.0)
	var lvl: int = 0
	if f > 0.0:
		lvl = 1
	if f >= 0.25:
		lvl = 2
	if f >= 0.5:
		lvl = 3
	if f >= 0.75:
		lvl = 4
	while _hit_level < lvl:
		_hit_level += 1
		var lp := Vector3(randf_range(-0.45, 0.45) * hit_radius, 5.0 + randf() * 5.0, randf_range(-0.35, 0.35) * hit_radius)
		GroundKit.persistent_smoke(self, lp, 1.0 + 0.9 * float(_hit_level), false)      # smoke only: no red flame glow (it flickered as red squares at range)
		GroundKit.explosion(to_global(lp), 0.7 + 0.25 * float(_hit_level))
