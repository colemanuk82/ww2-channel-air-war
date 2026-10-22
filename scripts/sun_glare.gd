class_name SunGlare
extends CanvasLayer
## Screen-space sun glare: a soft warm bloom around the sun plus a few lens ghosts while the sun is in front of
## the camera. Drawn with additive blending above the 3D view and below the HUD. Off when GameState.post_fx is 0.

var tod: Node
var _ctl: Control
var _amt: float = 0.0
var _pos: Vector2 = Vector2.ZERO
var _rays: ColorRect
var _rays_mat: ShaderMaterial
var _rays_amt: float = 0.0


func _ready() -> void:
	layer = 2
	_ctl = Control.new()
	_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_ctl.material = m
	_ctl.draw.connect(_draw_glare)
	# light shafts through the gaps in the clouds (shaders/god_rays.gdshader); strongest with a low sun
	_rays = ColorRect.new()
	_rays.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rays_mat = ShaderMaterial.new()
	_rays_mat.shader = load("res://shaders/god_rays.gdshader") as Shader
	_rays.material = _rays_mat
	_rays.visible = false
	add_child(_rays)
	add_child(_ctl)


func _process(delta: float) -> void:
	var target: float = 0.0
	var cam: Camera3D = get_viewport().get_camera_3d()
	if tod != null and cam != null and GameState.post_fx >= 1:
		var sd: Vector3 = tod.get("sun_dir")
		var far_pt: Vector3 = cam.global_position + sd * 1000.0
		if sd.y > -0.02 and not cam.is_position_behind(far_pt):
			var fwd: Vector3 = -cam.global_transform.basis.z
			var facing: float = clampf(fwd.dot(sd), 0.0, 1.0)
			_pos = cam.unproject_position(far_pt)
			target = pow(facing, 3.0) * clampf(sd.y * 5.0 + 0.45, 0.0, 1.0) * (1.0 - float(tod.get("sky_dim")))
	_amt = move_toward(_amt, target, delta * 2.5)
	# rays: need the sun roughly in view (it may sit just off-screen), more with a low sun
	var rays_target: float = 0.0
	if tod != null and cam != null and GameState.post_fx >= 1:
		var sd2: Vector3 = tod.get("sun_dir")
		var fp2: Vector3 = cam.global_position + sd2 * 1000.0
		if sd2.y > -0.03 and not cam.is_position_behind(fp2):
			var f2: float = clampf((-cam.global_transform.basis.z).dot(sd2), 0.0, 1.0)
			var low: float = 0.45 + 0.55 * smoothstep(0.55, 0.08, sd2.y)
			rays_target = smoothstep(0.55, 0.95, f2) * low * (1.0 - 0.6 * float(tod.get("sky_dim")))
			var vs: Vector2 = get_viewport().get_visible_rect().size
			_rays_mat.set_shader_parameter("sun_uv", cam.unproject_position(fp2) / vs)
			var sc: Color = tod.get("sun_color") if "sun_color" in tod else Color(1.0, 0.85, 0.6)
			_rays_mat.set_shader_parameter("tint", Vector3(sc.r, sc.g * 0.92, sc.b * 0.8))
	_rays_amt = move_toward(_rays_amt, rays_target, delta * 1.5)
	_rays.visible = _rays_amt > 0.01
	if _rays.visible:
		_rays_mat.set_shader_parameter("amount", _rays_amt)
	_ctl.visible = _amt > 0.01
	if _ctl.visible:
		_ctl.queue_redraw()


func _draw_glare() -> void:
	var size: Vector2 = _ctl.size
	var c: Vector2 = size * 0.5
	var r0: float = size.y * 0.5
	var warm := Color(1.0, 0.86, 0.6)
	for i in 14:
		var t: float = float(i) / 13.0
		var a: float = (1.0 - t) * (1.0 - t) * 0.045 * _amt
		_ctl.draw_circle(_pos, lerpf(r0 * 0.04, r0 * 0.9, t), Color(warm.r, warm.g, warm.b, a))
	var axis: Vector2 = c - _pos
	# [position along the sun-to-centre line, radius as a fraction of half the screen height, colour, filled]
	var ghosts: Array = [
		[0.35, 0.05, Color(1.0, 0.8, 0.45, 0.10), true],
		[0.7, 0.09, Color(0.6, 0.85, 1.0, 0.07), false],
		[1.15, 0.035, Color(1.0, 0.7, 0.4, 0.10), true],
		[1.6, 0.13, Color(0.7, 1.0, 0.8, 0.05), false],
	]
	for g in ghosts:
		var gp: Vector2 = _pos + axis * float(g[0])
		var col: Color = g[2]
		col.a *= _amt
		if bool(g[3]):
			_ctl.draw_circle(gp, r0 * float(g[1]), col)
		else:
			_ctl.draw_arc(gp, r0 * float(g[1]), 0.0, TAU, 40, col, 3.0, true)
