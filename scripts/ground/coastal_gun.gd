class_name CoastalGun
extends GroundTarget
## One heavy long-range gun of a cross-Channel battery (see CoastalBattery / GunShelling).
##   kind "casemate": a naval-pattern gun in a concrete casemate with a wide embrasure, earth berm and camouflage net
##   kind "railway" : a railway gun (28 cm K5 pattern) on a curved spur with its girder carriage
## -Z local = firing direction. The gun slews on its own towards `aim_world` (set by GunShelling), recoils when
## fired (`fire_visual`) with a big muzzle blast, smoke ring and dust, and when destroyed tells GunShelling.
## Casemates are hard: small arms barely scratch them, it takes bombs / rockets / direct hits.

const KINDS := {
	"casemate": {"hp": 300.0, "r": 11.0, "len": 16.5, "bore": 0.58, "pts": 900, "yaw_lim": 58.0},
	"railway": {"hp": 230.0, "r": 9.5, "len": 15.0, "bore": 0.46, "pts": 900, "yaw_lim": 62.0},
}
const COL_NET := Color(0.27, 0.31, 0.19)
const COL_NET2 := Color(0.34, 0.29, 0.2)
const COL_BERM := Color(0.36, 0.38, 0.22)

var gkind: String = "casemate"
var battery_id: String = ""
var index: int = 0
var heading_deg: float = 0.0
var aim_world: Vector3 = Vector3.ZERO
var has_aim: bool = false
var fired_count: int = 0

var _yaw_node: Node3D
var _pitch_node: Node3D
var _barrel: Node3D
var _tip: Node3D
var _yaw: float = 0.0
var _elev: float = deg_to_rad(12.0)
var _recoil: float = 0.0
var _yaw_lim: float = deg_to_rad(58.0)
var _len: float = 16.5
var _flash_mat: StandardMaterial3D
static var _glow_tex: ImageTexture


static func create(p_kind: String, p_team: String, p_battery: String, p_index: int, world_pos: Vector3, p_heading: float) -> CoastalGun:
	var g := CoastalGun.new()
	var cfg: Dictionary = KINDS.get(p_kind, KINDS["casemate"])
	g.gkind = p_kind
	g.kind = "coastal_gun"
	g.team = p_team
	g.battery_id = p_battery
	g.index = p_index
	g.max_health = float(cfg["hp"])
	g.hit_radius = float(cfg["r"])
	g.points = int(cfg["pts"])
	g.small_mult = 0.03             # cannon and machine guns do next to nothing to concrete
	g.min_damage = 0.0
	g.explosion_size = 3.2
	g.smoke_scale = 2.2
	g.smoke_height = 5.0
	g._len = float(cfg["len"])
	g._yaw_lim = deg_to_rad(float(cfg["yaw_lim"]))
	g.display_name = "Heavy gun %d" % (p_index + 1)
	g.heading_deg = p_heading
	g.position = Vector3(world_pos.x, GroundKit.ground_y(world_pos.x, world_pos.z), world_pos.z)
	g.rotation.y = -deg_to_rad(p_heading)
	return g


func _post_ready() -> void:
	add_to_group("coastal_gun")
	set_process(true)


# ------------------------------------------------------------------ models
func _build_intact(root: Node3D) -> void:
	if gkind == "railway":
		_build_railway(root)
	else:
		_build_casemate(root)


func _gun_barrel(parent: Node3D, bore: float) -> void:
	# breech, cradle and barrel along -Z from the trunnion; the tip node marks the muzzle
	var steel: Color = GroundKit.COL_STEEL.darkened(0.15)
	_barrel = Node3D.new()
	_barrel.name = "Barrel"
	parent.add_child(_barrel)
	GroundKit.box(_barrel, Vector3(bore * 5.2, bore * 4.4, 3.2), Vector3(0, 0, 1.4), steel.lightened(0.05), Vector3.ZERO, true)
	GroundKit.cyl(_barrel, bore * 1.55, bore * 1.18, _len * 0.55, Vector3(0, 0, -_len * 0.27), steel, Vector3(90, 0, 0), 10)
	GroundKit.cyl(_barrel, bore * 1.18, bore * 0.92, _len * 0.5, Vector3(0, 0, -_len * 0.74), steel.darkened(0.05), Vector3(90, 0, 0), 10)
	GroundKit.cyl(_barrel, bore * 1.35, bore * 1.35, 0.9, Vector3(0, 0, -_len * 0.99), steel.darkened(0.2), Vector3(90, 0, 0), 10)   # muzzle brake
	GroundKit.cyl(_barrel, bore * 0.6, bore * 0.6, 0.12, Vector3(0, 0, -_len - 0.02), GroundKit.COL_DARK, Vector3(90, 0, 0), 8, false)
	_tip = Node3D.new()
	_tip.name = "Muzzle"
	_tip.position = Vector3(0, 0, -_len - 0.3)
	_barrel.add_child(_tip)


func _build_casemate(root: Node3D) -> void:
	var conc: Color = GroundKit.COL_CONCRETE
	# a concrete gun pit open to the front and the sky: apron, U of heavy walls, a low sloped parapet, the gun on its pedestal
	GroundKit.box(root, Vector3(34, 0.6, 42), Vector3(0, 0.25, -2), conc.darkened(0.12), Vector3.ZERO, false)
	GroundKit.box(root, Vector3(2.8, 8.0, 22), Vector3(-10.0, 4.3, 5.0), conc)
	GroundKit.box(root, Vector3(2.8, 8.0, 22), Vector3(10.0, 4.3, 5.0), conc)
	GroundKit.box(root, Vector3(22.8, 8.0, 3.2), Vector3(0, 4.3, 15.4), conc.darkened(0.03))
	GroundKit.box(root, Vector3(17.2, 1.2, 15), Vector3(0, 1.0, 6.0), conc.darkened(0.08))
	GroundKit.box(root, Vector3(22.8, 3.4, 2.6), Vector3(0, 2.3, -6.4), conc.lightened(0.03), Vector3(-16, 0, 0))
	GroundKit.cyl(root, 3.3, 3.8, 4.4, Vector3(0, 3.0, -0.5), conc.darkened(0.15), Vector3.ZERO, 14)          # pedestal
	for sx in [-1.0, 1.0]:                                  # ammunition niches in the pit walls
		GroundKit.box(root, Vector3(0.4, 2.6, 3.2), Vector3(sx * 8.5, 2.9, 8.0), GroundKit.COL_DARK, Vector3.ZERO, false)
		GroundKit.box(root, Vector3(0.4, 2.6, 3.2), Vector3(sx * 8.5, 2.9, 12.0), GroundKit.COL_DARK, Vector3.ZERO, false)
	# earth berm banked round the sides and rear
	for sx in [-1.0, 1.0]:
		GroundKit.sphere(root, 9.0, Vector3(sx * 14.5, 2.2, 4.0), COL_BERM, Vector3(1.0, 0.55, 2.0), false)
	GroundKit.sphere(root, 10.0, Vector3(0, 2.0, 21.0), COL_BERM.darkened(0.06), Vector3(1.9, 0.5, 1.0), false)
	# camouflage netting on poles above the pit, with a slot left open over the barrel; painted splinter pattern on the walls
	for px in [-10.5, 10.5]:
		for pz in [-2.0, 14.0]:
			GroundKit.box(root, Vector3(0.3, 10.5, 0.3), Vector3(px, 5.5, pz), GroundKit.COL_WOOD, Vector3.ZERO, false)
	GroundKit.box(root, Vector3(9.0, 0.18, 19.0), Vector3(-6.4, 10.8, 6.5), COL_NET, Vector3(0, 0, 2), false)
	GroundKit.box(root, Vector3(9.0, 0.18, 19.0), Vector3(6.4, 10.8, 6.5), COL_NET2, Vector3(0, 0, -2), false)
	GroundKit.box(root, Vector3(24.0, 0.18, 6.0), Vector3(0, 10.6, 13.5), COL_NET2.darkened(0.12), Vector3.ZERO, false)
	for i in 5:
		GroundKit.box(root, Vector3(4.0 + float(i % 3), 2.4, 0.15), Vector3(-7.0 + float(i) * 3.6, 5.2 + float(i % 2) * 1.4, 17.1), COL_NET if i % 2 == 0 else COL_NET2, Vector3(0, 0, float(i) * 9.0 - 18.0), false)
		GroundKit.box(root, Vector3(0.15, 2.2, 4.0 + float(i % 3)), Vector3(-11.45 if i % 2 == 0 else 11.45, 5.0 + float(i % 3), 1.5 + float(i) * 3.5), COL_NET2 if i % 2 == 0 else COL_NET, Vector3.ZERO, false)
	# the gun: yaw ring on the pedestal, pitch cradle, shield
	_yaw_node = Node3D.new()
	_yaw_node.name = "Yaw"
	_yaw_node.position = Vector3(0, 5.6, -0.5)
	root.add_child(_yaw_node)
	_pitch_node = Node3D.new()
	_pitch_node.name = "Pitch"
	_yaw_node.add_child(_pitch_node)
	GroundKit.box(_pitch_node, Vector3(6.6, 4.2, 0.8), Vector3(0, 0.3, -3.4), GroundKit.COL_STEEL.darkened(0.1))   # gun shield
	GroundKit.box(_yaw_node, Vector3(1.2, 3.4, 2.2), Vector3(-2.6, -0.6, 0.4), GroundKit.COL_STEEL.darkened(0.2), Vector3.ZERO, false)
	GroundKit.box(_yaw_node, Vector3(1.2, 3.4, 2.2), Vector3(2.6, -0.6, 0.4), GroundKit.COL_STEEL.darkened(0.2), Vector3.ZERO, false)
	_gun_barrel(_pitch_node, _bore())
	_apply_pose()


func _build_railway(root: Node3D) -> void:
	var steel: Color = GroundKit.COL_STEEL.darkened(0.2)
	var dark: Color = GroundKit.COL_DARK
	# curved spur: sleepers and two rails fanning off to the back, gravel bed
	GroundKit.box(root, Vector3(8.5, 0.35, 64), Vector3(0, 0.1, 6), GroundKit.COL_SAND.darkened(0.3), Vector3.ZERO, false)
	for i in 20:
		var z: float = -22.0 + float(i) * 2.4
		GroundKit.box(root, Vector3(3.4, 0.16, 0.5), Vector3(sin(float(i) * 0.12) * 0.4, 0.33, z), GroundKit.COL_WOOD.darkened(0.2), Vector3.ZERO, false)
	for sx in [-0.75, 0.75]:
		GroundKit.box(root, Vector3(0.14, 0.22, 64), Vector3(sx, 0.46, 6), steel, Vector3.ZERO, false)
	# the carriage rotates on the spur's curve
	_yaw_node = Node3D.new()
	_yaw_node.name = "Yaw"
	_yaw_node.position = Vector3(0, 0, 4.0)
	root.add_child(_yaw_node)
	for bz in [-9.0, -4.0, 5.0, 10.0]:    # bogies
		GroundKit.box(_yaw_node, Vector3(2.9, 0.9, 4.2), Vector3(0, 1.0, bz), steel.lightened(0.04))
		GroundKit.cyl(_yaw_node, 0.5, 0.5, 3.2, Vector3(0, 0.75, bz - 1.2), dark, Vector3(0, 0, 90), 8, false)
		GroundKit.cyl(_yaw_node, 0.5, 0.5, 3.2, Vector3(0, 0.75, bz + 1.2), dark, Vector3(0, 0, 90), 8, false)
	GroundKit.box(_yaw_node, Vector3(3.2, 1.3, 27), Vector3(0, 2.1, 0.5), steel.lightened(0.08))      # girder
	GroundKit.box(_yaw_node, Vector3(4.2, 1.5, 7), Vector3(0, 3.5, 3.0), steel)                       # breech housing
	GroundKit.box(_yaw_node, Vector3(0.5, 2.6, 3.0), Vector3(-1.9, 3.9, -1.5), steel.darkened(0.05), Vector3.ZERO, false)
	GroundKit.box(_yaw_node, Vector3(0.5, 2.6, 3.0), Vector3(1.9, 3.9, -1.5), steel.darkened(0.05), Vector3.ZERO, false)
	_pitch_node = Node3D.new()
	_pitch_node.name = "Pitch"
	_pitch_node.position = Vector3(0, 4.6, -1.5)
	_yaw_node.add_child(_pitch_node)
	_gun_barrel(_pitch_node, _bore())
	# camouflage netting slung from poles over the carriage, and the track-side apron
	GroundKit.box(_yaw_node, Vector3(7.5, 0.16, 22), Vector3(0, 7.2, 4.0), COL_NET, Vector3(0, 0, 4), false)
	GroundKit.box(_yaw_node, Vector3(6.0, 0.18, 11), Vector3(-1.0, 7.35, 8.0), COL_NET2, Vector3(0, 8, -3), false)
	for pz in [-5.0, 3.0, 11.0]:
		GroundKit.box(_yaw_node, Vector3(0.25, 6.4, 0.25), Vector3(-3.4, 4.0, pz), GroundKit.COL_WOOD, Vector3.ZERO, false)
		GroundKit.box(_yaw_node, Vector3(0.25, 6.4, 0.25), Vector3(3.4, 4.0, pz), GroundKit.COL_WOOD, Vector3.ZERO, false)
	GroundKit.box(root, Vector3(16, 0.3, 40), Vector3(0, 0.05, 2), COL_BERM.darkened(0.2), Vector3.ZERO, false)
	_apply_pose()


func _bore() -> float:
	return float((KINDS.get(gkind, KINDS["casemate"]) as Dictionary)["bore"])


func _build_wreck(root: Node3D) -> void:
	var burnt: Color = Color(0.1, 0.09, 0.08)
	GroundKit.box(root, Vector3(32, 0.1, 36), Vector3(0, 0.08, 0), Color(0.07, 0.06, 0.05), Vector3.ZERO, false)   # scorched ground
	if gkind == "railway":
		GroundKit.box(root, Vector3(3.2, 1.3, 27), Vector3(1.5, 1.6, 2), burnt.lightened(0.05), Vector3(2, 12, 14))
		GroundKit.box(root, Vector3(4.2, 1.5, 7), Vector3(-1.5, 2.6, 8), burnt, Vector3(10, -20, 22))
		GroundKit.cyl(root, 0.4, 0.5, 13.0, Vector3(-3.0, 1.2, -6.0), burnt.lightened(0.08), Vector3(80, 25, 12), 8)
		return
	GroundKit.box(root, Vector3(22, 3.4, 20), Vector3(0, 1.7, 6), GroundKit.COL_CONCRETE.darkened(0.45), Vector3(0, 0, 0))
	GroundKit.box(root, Vector3(24.5, 1.5, 22), Vector3(2.5, 4.2, 1.5), GroundKit.COL_CONCRETE.darkened(0.5), Vector3(7, 6, 14))   # roof slab slid off
	GroundKit.box(root, Vector3(8, 3.0, 8), Vector3(-8, 1.2, -4), GroundKit.COL_CONCRETE.darkened(0.4), Vector3(14, 30, 10))      # rubble
	GroundKit.cyl(root, 0.5, 0.65, _len * 0.7, Vector3(-3.0, 1.1, -10.0), burnt.lightened(0.1), Vector3(84, 18, 10), 8)             # barrel on the ground
	GroundKit.cyl(root, 0.6, 0.6, 1.0, Vector3(-5.5, 0.9, -15.5), burnt, Vector3(80, 0, 0), 8)


func _on_destroyed(_killer: Node) -> void:
	if _barrel != null and is_instance_valid(_barrel):
		_barrel.visible = false
	var m: GunShelling = GunShelling.instance()
	if m != null:
		m.on_gun_destroyed(battery_id, index)
	# ammunition cooks off: two more blasts over the next seconds
	if is_inside_tree():
		for i in 2:
			var t: SceneTreeTimer = get_tree().create_timer(0.7 + float(i) * 1.1)
			t.timeout.connect(func() -> void:
				if is_inside_tree():
					GroundKit.explosion(global_position + Vector3(randf_range(-6, 6), 5.0, randf_range(-6, 6)), 2.2))


# ------------------------------------------------------------------ aiming and firing
func set_aim(world_pos: Vector3) -> void:
	aim_world = world_pos
	has_aim = true


func _aim_angles() -> Vector2:
	## (yaw, elevation) in radians for the current aim point
	var d: Vector3 = to_local(aim_world)
	var yaw: float = clampf(atan2(-d.x, -d.z), -_yaw_lim, _yaw_lim)
	var range_m: float = Vector2(d.x, d.z).length()
	var el: float = lerpf(deg_to_rad(16.0), deg_to_rad(49.0), clampf(range_m / 52000.0, 0.0, 1.0))
	return Vector2(yaw, el)


## True when the barrel points (within a degree or two) at the aim point and the aim is inside the traverse arc.
func is_laid(tol_deg: float = 2.5) -> bool:
	if not has_aim:
		return false
	var a: Vector2 = _aim_angles()
	return absf(a.x - _yaw) < deg_to_rad(tol_deg) and absf(a.y - _elev) < deg_to_rad(tol_deg)


func _apply_pose() -> void:
	if _yaw_node != null:
		_yaw_node.rotation.y = _yaw
	if _pitch_node != null:
		_pitch_node.rotation.x = _elev
	if _barrel != null:
		_barrel.position.z = _recoil


func _process(delta: float) -> void:
	if is_dead:
		return
	if has_aim:
		var a: Vector2 = _aim_angles()
		_yaw = move_toward(_yaw, a.x, deg_to_rad(4.0) * delta)
		_elev = move_toward(_elev, a.y, deg_to_rad(2.5) * delta)
	if _recoil > 0.0:
		_recoil = maxf(_recoil - delta * 0.28, 0.0)      # runs back out slowly
	_apply_pose()


func muzzle_pos() -> Vector3:
	return _tip.global_position if _tip != null and _tip.is_inside_tree() else global_position + Vector3(0, 7.0, 0)


func muzzle_dir() -> Vector3:
	return -_tip.global_transform.basis.z.normalized() if _tip != null and _tip.is_inside_tree() else -global_transform.basis.z


## The firing picture: flash, blast, smoke ring, dust ring, light, sound, recoil.
func fire_visual() -> void:
	fired_count += 1
	_recoil = 1.7
	if not is_inside_tree():
		return
	var fx: Node = GroundKit.fx_node()
	if fx == null:
		return
	var tip: Vector3 = muzzle_pos()
	var dir: Vector3 = muzzle_dir()
	var player: Node3D = GroundKit.player_node()
	var dist: float = player.global_position.distance_to(tip) if player != null else 3000.0
	if dist > 90000.0:
		return
	fx.call("explosion", tip + dir * 3.0, 6.4, true)
	fx.call("light_flash", tip + dir * 3.0, 7.0, 110.0, 0.4, Color(1.0, 0.7, 0.35))
	# the smoke ring: a ring of puffs standing square to the barrel, thrown forward and out
	var up: Vector3 = Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var u: Vector3 = dir.cross(up).normalized()
	var v: Vector3 = dir.cross(u).normalized()
	for i in 18:
		var a: float = TAU * float(i) / 18.0
		var radial: Vector3 = u * cos(a) + v * sin(a)
		fx.puffs.spawn(tip + dir * 5.0 + radial * 1.2, dir * 15.0 + radial * 8.0, randf_range(3.0, 4.2), 1.6, 6.5,
			Color(0.82, 0.8, 0.76, 0.75), Color(0.6, 0.6, 0.6, 0.0), 0.6, 0.0, 0.9)
	# muzzle blast along the line of fire
	for i in 8:
		fx.puffs.spawn(tip + dir * float(i) * 1.5, dir * randf_range(20.0, 40.0) + Vector3(0, randf_range(0.0, 5.0), 0), randf_range(0.5, 1.0), 2.5, 7.0,
			Color(1.0, 0.82, 0.4, 0.9), Color(0.7, 0.35, 0.1, 0.0), 0.3, 0.0, 1.8)
	# dust and scorched grass flung out along the ground
	var gy: float = global_position.y
	for i in 22:
		var b: float = TAU * float(i) / 22.0 + randf() * 0.2
		var gd := Vector3(cos(b), 0.0, sin(b))
		fx.puffs.spawn(Vector3(tip.x, gy + 0.6, tip.z) + gd * 4.0, gd * randf_range(14.0, 26.0), randf_range(1.6, 2.6), 2.0, 9.0,
			Color(0.6, 0.53, 0.42, 0.6), Color(0.62, 0.56, 0.46, 0.0), 0.5, 0.0, 1.6)
	fx.call("smoke_column", tip + dir * 3.0, 4.5, 28.0)
	fx.call("sfx", "explosion", tip, 5.0, 0.1)
	fx.call("sfx", "thunder", tip, -7.0, 0.5)
	distant_flash(get_tree(), tip, dist)


## Seen from kilometres away the star is a pinprick: add a billboard flash sized to the viewing distance.
static func distant_flash(tree: SceneTree, tip: Vector3, dist: float) -> void:
	if dist < 1500.0 or tree == null or tree.current_scene == null:
		return
	if _glow_tex == null:
		var im := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for yy in 64:
			for xx in 64:
				var rr: float = clampf(Vector2(float(xx) - 31.5, float(yy) - 31.5).length() / 31.5, 0.0, 1.0)
				var aa: float = pow(1.0 - rr, 2.2)
				im.set_pixel(xx, yy, Color(1.0, lerpf(0.45, 0.95, 1.0 - rr), lerpf(0.1, 0.7, 1.0 - rr), aa))
		_glow_tex = ImageTexture.create_from_image(im)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	q.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _glow_tex
	m.albedo_color = Color(1, 1, 1, 1)
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.extra_cull_margin = 20000.0
	tree.current_scene.add_child(q)
	q.global_position = tip
	var sz: float = clampf(dist * 0.03, 30.0, 700.0)
	q.scale = Vector3.ONE * sz * 0.5
	var tw: Tween = q.create_tween()
	tw.set_parallel(true)
	tw.tween_property(q, "scale", Vector3.ONE * sz, 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color", Color(1, 1, 1, 0), 1.1)
	tw.chain().tween_callback(q.queue_free)


# ------------------------------------------------------------------ the other pieces of a battery
## Ammunition bunker: when it goes up it takes the guns beside it (damage within 55 m).
class Magazine extends GroundTarget:
	func _build_intact(root: Node3D) -> void:
		var c: Color = GroundKit.COL_CONCRETE.darkened(0.08)
		GroundKit.box(root, Vector3(14, 4.6, 20), Vector3(0, 2.3, 0), c)
		GroundKit.box(root, Vector3(15, 1.0, 21), Vector3(0, 5.0, 0), c.lightened(0.06))
		GroundKit.box(root, Vector3(4.2, 3.2, 1.0), Vector3(0, 1.8, -10.3), GroundKit.COL_DARK, Vector3.ZERO, false)
		GroundKit.sphere(root, 7.5, Vector3(-8.0, 1.5, 2), CoastalGun.COL_BERM, Vector3(1.0, 0.5, 1.6), false)
		GroundKit.sphere(root, 7.5, Vector3(8.0, 1.5, 2), CoastalGun.COL_BERM, Vector3(1.0, 0.5, 1.6), false)
		GroundKit.box(root, Vector3(15.5, 0.16, 22), Vector3(0, 5.7, 0), CoastalGun.COL_NET, Vector3.ZERO, false)

	func _build_wreck(root: Node3D) -> void:
		GroundKit.box(root, Vector3(18, 0.1, 24), Vector3(0, 0.08, 0), Color(0.07, 0.06, 0.05), Vector3.ZERO, false)
		GroundKit.box(root, Vector3(14, 2.4, 20), Vector3(0, 1.2, 0), GroundKit.COL_CONCRETE.darkened(0.5), Vector3(0, 0, 3))
		GroundKit.box(root, Vector3(15, 1.0, 21), Vector3(3, 3.0, 2), GroundKit.COL_CONCRETE.darkened(0.55), Vector3(10, 9, 18))

	func _on_destroyed(_killer: Node) -> void:
		if not is_inside_tree():
			return
		GroundKit.explosion(global_position + Vector3(0, 4, 0), 4.0)
		for n in get_tree().get_nodes_in_group("coastal_gun"):
			var d: float = (n as Node3D).global_position.distance_to(global_position)
			if d < 60.0 and n.has_method("take_damage"):
				n.call("take_damage", 160.0 * (1.0 - d / 60.0), self)


## Fire-control post: a tall concrete tower with range-finder slits. Without it the battery shoots wide.
class Tower extends GroundTarget:
	func _build_intact(root: Node3D) -> void:
		var c: Color = GroundKit.COL_CONCRETE
		GroundKit.box(root, Vector3(8, 16, 8), Vector3(0, 8, 0), c)
		GroundKit.box(root, Vector3(9.5, 1.2, 9.5), Vector3(0, 16.6, 0), c.lightened(0.06))
		GroundKit.box(root, Vector3(7.0, 1.0, 0.4), Vector3(0, 14.0, -4.1), GroundKit.COL_DARK, Vector3.ZERO, false)
		GroundKit.box(root, Vector3(0.4, 1.0, 7.0), Vector3(4.1, 14.0, 0), GroundKit.COL_DARK, Vector3.ZERO, false)
		GroundKit.cyl(root, 1.6, 1.9, 1.8, Vector3(0, 18.0, 0), GroundKit.COL_STEEL, Vector3.ZERO, 10)       # range-finder dome
		GroundKit.cyl(root, 0.06, 0.06, 4.0, Vector3(1.2, 21.0, 0), GroundKit.COL_DARK, Vector3.ZERO, 5, false)
		GroundKit.box(root, Vector3(9.0, 5.0, 0.15), Vector3(0, 11.0, 4.1), CoastalGun.COL_NET, Vector3.ZERO, false)

	func _build_wreck(root: Node3D) -> void:
		GroundKit.box(root, Vector3(8, 5, 8), Vector3(0, 2.5, 0), GroundKit.COL_CONCRETE.darkened(0.5), Vector3(0, 8, 4))
		GroundKit.box(root, Vector3(9.5, 1.2, 9.5), Vector3(4, 1.8, 3), GroundKit.COL_CONCRETE.darkened(0.55), Vector3(20, 10, 30))

	func _on_destroyed(_killer: Node) -> void:
		var m: GunShelling = GunShelling.instance()
		if m != null:
			m.on_tower_destroyed(get_meta("battery_id", ""))
