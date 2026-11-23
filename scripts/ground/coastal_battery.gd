class_name CoastalBattery
extends Node3D
## A cross-Channel heavy battery site, a mission target (WorldPopulator type "heavy_battery", ids in GunShelling.SITES):
## casemated guns (or railway guns on a spur with their train), ammunition bunkers, a fire-control tower, camouflage
## nets, huts, trenches, and a ring of flak (88 mm, 37-40 mm and MGs). Procedural, in the project's toon style.
## It is the *model* of the site; GunShelling holds the state and does the firing. The battery counts as destroyed
## (signal `destroyed`) when GunShelling silences it: three quarters of its guns knocked out.
## Mission-target contract (BombingMode / DefendMode): team, hit_radius, target_id, display_name, is_destroyed(),
## signal destroyed(node, killer), group "mission_target".

signal destroyed(node: Node, killer: Node)

var team: String = "Axis"
var target_id: String = ""
var display_name: String = ""
var is_mission_target: bool = true
var start_wrecked: bool = false
var hit_radius: float = 95.0
var heading_deg: float = 0.0
var skind: String = "heavy_battery"
var guns: Array = []
var magazines: Array = []
var tower: Node = null
var is_dead: bool = false
var populator: Node = null

var _kind: String = "casemate"
var _n: int = 3
var _mgr: GunShelling = null


static func create(p_id: String, p_team: String = "Axis") -> CoastalBattery:
	var b := CoastalBattery.new()
	b.target_id = p_id
	b.team = p_team
	var s: Dictionary = GunShelling.SITES.get(p_id, GunShelling.SITES["battery_grosser_kurfurst"])
	b.display_name = str(s["name"])
	b._kind = str(s["kind"])
	b._n = int(s["guns"])
	var p: Vector3 = GunShelling.site_pos(p_id) if GunShelling.SITES.has(p_id) else Vector3.ZERO
	b.position = p
	var first: String = str((s["targets"] as Array)[0])
	var to: Vector3 = GunShelling.target_pos(first) - p
	b.heading_deg = WorldCoords.dir_to_heading(Vector3(to.x, 0, to.z))
	return b


func is_destroyed() -> bool:
	return is_dead


func gun_at(i: int) -> Node:
	return guns[i] if i >= 0 and i < guns.size() and is_instance_valid(guns[i]) else null


func kill_gun(i: int) -> void:
	var g: Node = gun_at(i)
	if g != null:
		(g as CoastalGun).die(null)
	elif _mgr != null:
		_mgr.on_gun_destroyed(target_id, i)


func _ready() -> void:
	add_to_group("heavy_battery")
	add_to_group("structure")
	if is_mission_target:
		add_to_group("mission_target")
	_mgr = GunShelling.ensure(get_tree().current_scene if get_tree().current_scene != null else get_tree().root)
	if populator != null:
		_mgr.populator = populator
	_mgr.register_node(target_id, self)
	_mgr.battery_silenced.connect(_on_silenced)
	var rec: Dictionary = _mgr.rec(target_id)
	is_dead = bool(rec.get("silenced", false)) or start_wrecked
	_build_guns()
	_build_static()
	_build_defences()
	if is_dead:
		add_to_group("destroyed_target")


func _exit_tree() -> void:
	if _mgr != null and is_instance_valid(_mgr):
		_mgr.unregister_node(target_id, self)


func _on_silenced(id: String) -> void:
	if id != target_id or is_dead:
		return
	is_dead = true
	add_to_group("destroyed_target")
	destroyed.emit(self, null)


# ------------------------------------------------------------------ placement helpers
func _off(x: float, z: float) -> Vector3:
	return Basis(Vector3.UP, -deg_to_rad(heading_deg)) * Vector3(x, 0.0, z)


func _put(n: Node3D, x: float, z: float, extra_yaw_deg: float = 0.0) -> void:
	var o: Vector3 = _off(x, z)
	var wx: float = position.x + o.x
	var wz: float = position.z + o.z
	n.position = Vector3(o.x, GroundKit.ground_y(wx, wz) - position.y, o.z)
	n.rotation.y = -deg_to_rad(heading_deg + extra_yaw_deg)


func _build_guns() -> void:
	var rec: Dictionary = _mgr.rec(target_id)
	for i in _n:
		var g: CoastalGun = CoastalGun.create(_kind, team, target_id, i, global_position, heading_deg)
		g.is_mission_target = false
		g.start_wrecked = not bool((rec["alive"] as Array)[i]) if not rec.is_empty() else false
		if _kind == "railway":
			_put(g, (float(i) - float(_n - 1) * 0.5) * 46.0, 0.0)
		else:
			_put(g, (float(i) - float(_n - 1) * 0.5) * 64.0 + sin(float(i) * 2.3) * 4.0, sin(float(i) * 1.7) * 7.0)
		add_child(g)
		guns.append(g)
	if _kind == "casemate":
		for sx in [-1.0, 1.0]:
			var m := CoastalGun.Magazine.new()
			m.team = team
			m.hit_radius = 10.0
			m.max_health = 190.0
			m.small_mult = 0.05
			m.points = 300
			m.explosion_size = 3.6
			m.display_name = "Ammunition bunker"
			m.kind = "ammo_bunker"
			_put(m, sx * 46.0, 64.0, 180.0)
			add_child(m)
			magazines.append(m)
		var tw := CoastalGun.Tower.new()
		tw.team = team
		tw.hit_radius = 8.0
		tw.max_health = 150.0
		tw.small_mult = 0.06
		tw.points = 350
		tw.explosion_size = 2.6
		tw.display_name = "Fire-control post"
		tw.kind = "fire_control"
		tw.set_meta("battery_id", target_id)
		_put(tw, -(float(_n) * 32.0 + 40.0), 30.0)
		add_child(tw)
		tower = tw
	else:
		var tw2 := CoastalGun.Tower.new()
		tw2.team = team
		tw2.hit_radius = 8.0
		tw2.max_health = 150.0
		tw2.small_mult = 0.06
		tw2.points = 350
		tw2.explosion_size = 2.6
		tw2.display_name = "Fire-control post"
		tw2.kind = "fire_control"
		tw2.set_meta("battery_id", target_id)
		_put(tw2, 80.0, 40.0)
		add_child(tw2)
		tower = tw2
	if not bool(rec.get("fc_alive", true)) and tower != null:
		(tower as GroundTarget).start_wrecked = true


func _build_static() -> void:
	var deco := Node3D.new()
	deco.name = "Deco"
	add_child(deco)
	deco.rotation.y = -deg_to_rad(heading_deg)
	var olive: Color = CoastalGun.COL_NET
	var brown: Color = CoastalGun.COL_NET2
	# service road and a turning loop behind the guns
	GroundKit.box(deco, Vector3(5.0, 0.12, 120.0), Vector3(0, 0.1, 100.0), Color(0.3, 0.27, 0.22), Vector3.ZERO, false)
	GroundKit.box(deco, Vector3(150.0, 0.12, 4.0), Vector3(0, 0.1, 50.0), Color(0.3, 0.27, 0.22), Vector3.ZERO, false)
	# camouflaged huts (barracks, stores) with netting, trenches and sandbag rings
	for i in 4:
		var hx: float = -70.0 + float(i) * 46.0
		GroundKit.box(deco, Vector3(7.0, 3.0, 15.0), Vector3(hx, 1.5, 92.0 + float(i % 2) * 14.0), GroundKit.COL_WOOD.darkened(0.2))
		GroundKit.box(deco, Vector3(8.2, 0.9, 16.0), Vector3(hx, 3.5, 92.0 + float(i % 2) * 14.0), olive.darkened(0.1), Vector3(0, 0, 0))
		GroundKit.box(deco, Vector3(14.0, 0.15, 24.0), Vector3(hx, 4.4, 92.0 + float(i % 2) * 14.0), olive if i % 2 == 0 else brown, Vector3(0, float(i) * 7.0, 2.0), false)
	for i in 6:
		GroundKit.box(deco, Vector3(2.0, 0.4, 20.0 + float(i) * 3.0), Vector3(-90.0 + float(i) * 36.0, 0.1, 22.0), Color(0.12, 0.11, 0.09), Vector3(0, float(i) * 20.0 - 40.0, 0), false)
	# a great net slung across the yard between the guns on poles
	for k in 2:
		var nx: float = (float(k) - 0.5) * 78.0
		GroundKit.box(deco, Vector3(30.0, 0.16, 30.0), Vector3(nx, 7.2, 38.0), olive if k == 0 else brown, Vector3(2, 0, 3), false)
		for px in [-13.0, 13.0]:
			GroundKit.box(deco, Vector3(0.3, 7.0, 0.3), Vector3(nx + px, 3.5, 38.0 - 13.0), GroundKit.COL_WOOD, Vector3.ZERO, false)
			GroundKit.box(deco, Vector3(0.3, 7.0, 0.3), Vector3(nx + px, 3.5, 38.0 + 13.0), GroundKit.COL_WOOD, Vector3.ZERO, false)
	# barbed-wire belt (a thin dark band) round the whole site
	var rw: float = float(_n) * 36.0 + 90.0
	GroundKit.box(deco, Vector3(rw * 2.0, 0.9, 0.2), Vector3(0, 0.45, -60.0), Color(0.15, 0.14, 0.13), Vector3.ZERO, false)
	GroundKit.box(deco, Vector3(rw * 2.0, 0.9, 0.2), Vector3(0, 0.45, 150.0), Color(0.15, 0.14, 0.13), Vector3.ZERO, false)
	GroundKit.box(deco, Vector3(0.2, 0.9, 210.0), Vector3(-rw, 0.45, 45.0), Color(0.15, 0.14, 0.13), Vector3.ZERO, false)
	GroundKit.box(deco, Vector3(0.2, 0.9, 210.0), Vector3(rw, 0.45, 45.0), Color(0.15, 0.14, 0.13), Vector3.ZERO, false)
	if _kind == "railway":
		_build_train(deco)


## The railway guns' train on its siding, a locomotive and ammunition wagons under nets, and a camouflaged tunnel mouth.
func _build_train(deco: Node3D) -> void:
	var steel: Color = GroundKit.COL_STEEL.darkened(0.25)
	var tx: float = -34.0
	for sx in [-0.75, 0.75]:
		GroundKit.box(deco, Vector3(0.14, 0.22, 120.0), Vector3(tx + sx, 0.4, 100.0), steel, Vector3.ZERO, false)
	for i in 48:
		GroundKit.box(deco, Vector3(3.2, 0.16, 0.5), Vector3(tx, 0.3, 40.0 + float(i) * 2.4), GroundKit.COL_WOOD.darkened(0.2), Vector3.ZERO, false)
	# locomotive
	GroundKit.box(deco, Vector3(3.2, 3.2, 11.0), Vector3(tx, 2.4, 52.0), Color(0.12, 0.12, 0.13))
	GroundKit.cyl(deco, 1.45, 1.45, 8.0, Vector3(tx, 3.6, 49.0), Color(0.14, 0.14, 0.15), Vector3(90, 0, 0), 10)
	GroundKit.cyl(deco, 0.4, 0.55, 1.6, Vector3(tx, 5.6, 45.5), Color(0.1, 0.1, 0.1), Vector3.ZERO, 8, false)
	GroundKit.box(deco, Vector3(3.4, 0.2, 26.0), Vector3(tx, 5.3, 66.0), CoastalGun.COL_NET, Vector3.ZERO, false)
	for i in 3:
		var wz: float = 65.0 + float(i) * 15.0
		GroundKit.box(deco, Vector3(3.0, 3.2, 13.0), Vector3(tx, 2.3, wz), GroundKit.COL_OLIVE.darkened(0.15 + float(i) * 0.05))
		GroundKit.box(deco, Vector3(3.2, 0.3, 13.4), Vector3(tx, 4.1, wz), GroundKit.COL_OLIVE.darkened(0.3), Vector3.ZERO, false)
	# tunnel mouth at the end of the spur
	var c: Color = GroundKit.COL_CONCRETE
	GroundKit.box(deco, Vector3(2.2, 7.0, 4.0), Vector3(tx - 3.8, 3.5, 128.0), c, Vector3.ZERO, true)
	GroundKit.box(deco, Vector3(2.2, 7.0, 4.0), Vector3(tx + 3.8, 3.5, 128.0), c, Vector3.ZERO, true)
	GroundKit.box(deco, Vector3(10.0, 2.0, 4.0), Vector3(tx, 7.8, 128.0), c.lightened(0.05))
	GroundKit.box(deco, Vector3(5.4, 6.2, 0.6), Vector3(tx, 3.1, 129.6), GroundKit.COL_DARK, Vector3.ZERO, false)
	GroundKit.sphere(deco, 14.0, Vector3(tx, 0.5, 138.0), CoastalGun.COL_BERM, Vector3(1.0, 0.55, 1.2), false)


func _build_defences() -> void:
	# [type, x, z] in the battery frame: heavy flak on the flanks, light flak and MGs all round the guns
	var spots: Array = []
	var span: float = float(_n) * 34.0 + 70.0
	spots.append(["88mm", -span, -10.0])
	spots.append(["88mm", span, -10.0])
	spots.append(["bofors", -span * 0.55, -70.0])
	spots.append(["bofors", span * 0.55, -70.0])
	spots.append(["bofors", -span * 0.4, 118.0])
	spots.append(["bofors", span * 0.4, 118.0])
	spots.append(["mg", 0.0, -62.0])
	spots.append(["mg", -span - 25.0, 60.0])
	spots.append(["mg", span + 25.0, 60.0])
	if _kind == "casemate":
		spots.append(["88mm", 0.0, 140.0])
	for sp in spots:
		var a: AAGun = AAGun.create(str(sp[0]), team)
		_put(a, float(sp[1]), float(sp[2]))
		a.is_mission_target = false
		add_child(a)
		# sandbag ring
		GroundKit.cyl(a, 3.6, 4.0, 1.1, Vector3(0, 0.5, 0), GroundKit.COL_SAND.darkened(0.15), Vector3.ZERO, 10, false)
