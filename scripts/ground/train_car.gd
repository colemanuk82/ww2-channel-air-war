class_name TrainCar
extends GroundTarget
## One car of a Train: loco (steaming), boxcar, flatcar (carries a tank), tanker (explodes big), flak wagon.

const TYPES := {
	"loco": {"hp": 90.0, "r": 9.0, "pts": 250, "clen": 11.0},
	"boxcar": {"hp": 45.0, "r": 8.0, "pts": 80, "clen": 9.0},
	"flatcar": {"hp": 45.0, "r": 8.0, "pts": 100, "clen": 9.0},
	"tanker": {"hp": 40.0, "r": 8.0, "pts": 120, "clen": 9.0},
	"flak": {"hp": 55.0, "r": 8.0, "pts": 150, "clen": 9.0},
}

var ctype: String = "boxcar"
var train: Node
var _steam: GPUParticles3D
var _gun: AAGun


static func create(p_type: String, p_team: String) -> TrainCar:
	var c := TrainCar.new()
	var cfg: Dictionary = TYPES.get(p_type, TYPES["boxcar"])
	c.ctype = p_type
	c.team = p_team
	c.max_health = cfg["hp"]
	c.hit_radius = cfg["r"]
	c.points = cfg["pts"]
	c.kind = "train_" + p_type
	c.display_name = "Locomotive" if p_type == "loco" else "Rail car (%s)" % p_type
	c.explosion_size = 2.4 if p_type == "tanker" else (1.6 if p_type == "loco" else 1.0)
	c.smoke_scale = 1.5 if p_type in ["tanker", "loco"] else 0.9
	c.smoke_height = 3.0
	return c


func _build_intact(root: Node3D) -> void:
	var dark := Color(0.12, 0.12, 0.13)
	var grey := Color(0.38, 0.38, 0.4)
	# chassis + wheels (shared)
	var clen: float = TYPES[ctype]["clen"]
	GroundKit.box(root, Vector3(3.0, 0.5, clen), Vector3(0, 1.0, 0), dark)
	for z in [-clen * 0.32, clen * 0.32]:
		for sx in [-1.2, 1.2]:
			GroundKit.cyl(root, 0.55, 0.55, 0.25, Vector3(sx, 0.55, z), dark, Vector3(0, 0, 90), 8, false)
	match ctype:
		"loco":
			GroundKit.cyl(root, 1.35, 1.35, 7.0, Vector3(0, 2.9, -1.5), Color(0.1, 0.1, 0.12), Vector3(90, 0, 0), 10)
			GroundKit.box(root, Vector3(3.0, 3.6, 3.0), Vector3(0, 3.1, 3.4), Color(0.18, 0.18, 0.2))        # cab
			GroundKit.box(root, Vector3(3.3, 0.3, 3.4), Vector3(0, 5.0, 3.4), Color(0.1, 0.1, 0.11))          # cab roof
			GroundKit.cyl(root, 0.5, 0.75, 2.0, Vector3(0, 5.1, -4.0), dark, Vector3.ZERO, 8)                 # chimney
			GroundKit.cyl(root, 0.55, 0.55, 0.9, Vector3(0, 4.5, -0.5), Color(0.5, 0.42, 0.15), Vector3.ZERO, 8)  # dome
			GroundKit.cyl(root, 0.7, 0.7, 0.2, Vector3(0, 2.9, -5.1), Color(0.5, 0.5, 0.5), Vector3(90, 0, 0), 8, false)
			for z in [-3.3, -1.6, 0.1]:
				for sx in [-1.35, 1.35]:
					GroundKit.cyl(root, 0.85, 0.85, 0.2, Vector3(sx, 0.85, z), Color(0.15, 0.15, 0.17), Vector3(0, 0, 90), 10, false)
		"boxcar":
			var c: Color = Color(0.4, 0.28, 0.2) if randf() > 0.4 else Color(0.35, 0.34, 0.3)
			GroundKit.box(root, Vector3(3.2, 3.0, clen * 0.95), Vector3(0, 2.8, 0), c)
			GroundKit.box(root, Vector3(3.4, 0.25, clen), Vector3(0, 4.4, 0), c.darkened(0.3))
		"flatcar":
			GroundKit.box(root, Vector3(3.2, 0.3, clen), Vector3(0, 1.35, 0), Color(0.3, 0.25, 0.2))
			var tc: Color = GroundKit.team_color(team)
			GroundKit.box(root, Vector3(2.4, 0.9, 5.0), Vector3(0, 2.0, 0), tc)
			GroundKit.box(root, Vector3(1.6, 0.8, 2.2), Vector3(0, 2.8, 0), tc.darkened(0.1))
			GroundKit.cyl(root, 0.1, 0.12, 3.0, Vector3(0, 2.9, -2.4), tc.darkened(0.4), Vector3(90, 0, 0), 5, false)
		"tanker":
			GroundKit.cyl(root, 1.5, 1.5, clen * 0.9, Vector3(0, 2.8, 0), Color(0.12, 0.12, 0.14), Vector3(90, 0, 0), 10)
			GroundKit.box(root, Vector3(0.6, 0.4, 1.0), Vector3(0, 4.4, 0), grey)
		"flak":
			GroundKit.box(root, Vector3(3.2, 0.3, clen), Vector3(0, 1.35, 0), Color(0.3, 0.25, 0.2))
			for sx in [-1.0, 1.0]:
				GroundKit.box(root, Vector3(0.3, 1.4, clen * 0.9), Vector3(sx * 1.45, 2.1, 0), Color(0.35, 0.33, 0.28))
			_gun = AAGun.create("mg", team)
			_gun.position = Vector3(0, 1.5, 0)
			_gun.scale = Vector3.ONE * 0.8
			add_child(_gun)


func _post_ready() -> void:
	add_to_group("train_car")
	if ctype == "loco":
		_make_steam()


func _make_steam() -> void:
	_steam = GPUParticles3D.new()
	_steam.amount = 18
	_steam.lifetime = 3.2
	_steam.local_coords = false
	_steam.position = Vector3(0, 6.3, -4.0)
	_steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 14.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3(0.6, 0.8, 0.0)
	pm.scale_min = 1.2
	pm.scale_max = 2.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.4))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.92, 0.92, 0.92, 0.85))
	grad.set_color(1, Color(0.8, 0.8, 0.82, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	_steam.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 6
	sm.rings = 3
	var vm := StandardMaterial3D.new()
	vm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vm.vertex_color_use_as_albedo = true
	vm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = vm
	_steam.draw_pass_1 = sm
	add_child(_steam)
	_steam.emitting = true


func _build_wreck(root: Node3D) -> void:
	var d: Color = Color(0.1, 0.09, 0.08)
	GroundKit.box(root, Vector3(3.0, 0.8, 8.5), Vector3(0, 0.9, 0), d, Vector3(0, 3, 6))
	GroundKit.box(root, Vector3(2.6, 1.6, 3.5), Vector3(0.5, 1.9, 0.5), d.lightened(0.05), Vector3(8, 15, 20))
	if ctype == "loco":
		GroundKit.cyl(root, 1.2, 1.2, 5.0, Vector3(1.8, 1.0, -2.0), d, Vector3(80, 20, 70), 8)


func _on_destroyed(_killer: Node) -> void:
	if _steam:
		_steam.emitting = false
	if _gun and is_instance_valid(_gun):
		_gun.die(_killer)
