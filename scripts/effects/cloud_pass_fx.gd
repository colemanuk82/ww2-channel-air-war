class_name CloudPassFX
extends Node
## Flying through cloud, in any view: tatters of cloud rush past as you meet a cloud's edge, the world goes
## grey-white inside it (as thick as the cloud is where you are), and the air gets bumpy. Added by WeatherManager.

var _veil: ColorRect
var _layer: CanvasLayer
var _in: float = 0.0          # smoothed density at the camera 0..1
var _tick: float = 0.0
var _dens: float = 0.0
var _ahead: float = 0.0
var _prev: Vector3 = Vector3.ZERO
var _vel: Vector3 = Vector3.ZERO
var _spawn_acc: float = 0.0
var _shake_t: float = 0.0


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 3
	add_child(_layer)
	_veil = ColorRect.new()
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.color = Color(0.85, 0.87, 0.9, 0.0)
	_veil.visible = false
	_layer.add_child(_veil)


func _cloud_col() -> Color:
	var cf: CloudField = WeatherManager.cloud_field
	var c: Variant = cf.mat.get_shader_parameter("cloud_color") if cf != null and cf.mat != null else null
	var col: Color = c if c is Color else Color(0.85, 0.87, 0.9)
	var lk: float = clampf(0.15 + TimeOfDay.light_level * 0.9, 0.1, 1.0)
	return Color(col.r * lk, col.g * lk, col.b * lk)


func _process(delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var cf: CloudField = WeatherManager.cloud_field
	if cam == null or cf == null or delta <= 0.0:
		return
	var cp: Vector3 = cam.global_position
	var raw: Vector3 = (cp - _prev) / delta
	if raw.length() < 600.0:
		_vel = _vel.lerp(raw, minf(delta * 4.0, 1.0))
	_prev = cp
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.1
		_dens = cf.density_at(cp)
		_ahead = cf.density_at(cp + _vel * 1.0)
	_in = move_toward(_in, _dens, delta * 1.8)
	# inside: grey-white all round, thicker toward the heart of the cloud
	var a: float = smoothstep(0.04, 0.8, _in) * 0.58
	_veil.visible = a > 0.01
	if _veil.visible:
		var c: Color = _cloud_col()
		_veil.color = Color(c.r, c.g, c.b, a)
	# at the edges (and inside): tatters of cloud streaming past
	var spd: float = _vel.length()
	var edge: float = maxf(_dens, _ahead)
	if edge > 0.0 and spd > 15.0:
		_spawn_acc += delta * (18.0 + 50.0 * clampf(edge / 0.4, 0.0, 1.0))
		var vd: Vector3 = _vel / spd
		var side: Vector3 = vd.cross(Vector3.UP).normalized()
		var c2: Color = _cloud_col()
		while _spawn_acc >= 1.0:
			_spawn_acc -= 1.0
			# a ring around the flight path, never on it: the wisps stream past the screen edges rather than
			# sitting on the aircraft in chase view
			var up2: Vector3 = side.cross(vd).normalized()
			var ang: float = randf() * TAU
			var rad: float = randf_range(16.0, 42.0)
			var pos: Vector3 = cp + vd * randf_range(25.0, 90.0) + (side * cos(ang) + up2 * sin(ang)) * rad
			FX.puffs.spawn(pos, Vector3.ZERO, randf_range(1.0, 1.8), randf_range(7.0, 12.0), randf_range(16.0, 28.0),
				Color(c2.r, c2.g, c2.b, 0.38), Color(c2.r, c2.g, c2.b, 0.0), 0.0, 0.0, 0.2)
	else:
		_spawn_acc = 0.0
	# bumps inside cumulus
	if _in > 0.15:
		_shake_t -= delta
		if _shake_t <= 0.0:
			_shake_t = randf_range(0.2, 0.7)
			var rig: Node = get_tree().get_first_node_in_group("camera_rig")
			if rig != null and rig.has_method("add_shake"):
				rig.call("add_shake", 0.06 + 0.12 * _in)
