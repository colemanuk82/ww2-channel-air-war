class_name WaterPlane
extends MeshInstance3D
## Huge stylised sea plane at y = 0 that follows `focus` (patterns are world-space so it never swims).

@export var size: float = 1000000.0
var focus: Node3D


func _ready() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	pm.subdivide_width = 1
	pm.subdivide_depth = 1
	mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader") as Shader
	# draw the sea FIRST among transparent things: it does not write depth, and as one huge plane centred under
	# the camera it was sorted after (on top of) splashes, smoke and spray over the water and painted them out
	mat.render_priority = -100
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dbg: String = OS.get_environment("WW2_WATER_DEBUG")
	if dbg != "":
		RenderingServer.global_shader_parameter_set("water_debug", float(dbg))
		if dbg == "3":
			visible = false
		elif dbg == "4":      # plain opaque material (is the veil a transparent-pass effect?)
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.05, 0.15, 0.25)
			sm.roughness = 0.3
			material_override = sm
	extra_cull_margin = 16384.0
	position.y = 0.0


var _wake_t: float = 0.0
const WAKE_SLOTS: int = 4
const WAKE_RANGE: float = 9000.0


func _process(delta: float) -> void:
	if focus:
		var p: Vector3 = focus.global_position
		global_position = Vector3(snappedf(p.x, 100.0), 0.0, snappedf(p.z, 100.0))
	_wake_t -= delta
	if _wake_t <= 0.0:
		_wake_t = 0.2
		_update_wakes()


## Feed the four nearest moving ships to water.gdshader (globals wake_0..3) so it draws their long Kelvin
## wakes and churned tracks in the sea itself. xz = position, z = forward angle, w = hull length (0 = slot off).
func _update_wakes() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var c: Vector3 = cam.global_position if cam != null else (focus.global_position if focus != null else global_position)
	var best: Array = []
	for n in get_tree().get_nodes_in_group("ship"):
		var sh: Node3D = n as Node3D
		if sh == null or not sh.is_inside_tree() or not sh.visible:
			continue
		if float(sh.get("speed") if "speed" in sh else 0.0) < 0.5 or bool(sh.get("is_dead") if "is_dead" in sh else false):
			continue
		var dd: float = Vector2(sh.global_position.x - c.x, sh.global_position.z - c.z).length()
		if dd > WAKE_RANGE:
			continue
		best.append([dd, sh])
	best.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in WAKE_SLOTS:
		var v := Vector4.ZERO
		if i < best.size():
			var sh: Node3D = best[i][1]
			var ln: float = float(sh.get("_len") if "_len" in sh else 30.0) * sh.scale.x
			v = Vector4(sh.global_position.x, sh.global_position.z, -sh.rotation.y, ln)
		RenderingServer.global_shader_parameter_set("wake_%d" % i, v)
