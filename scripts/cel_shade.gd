class_name CelShade
extends Node
## Cel-shaded art style (Options > Video > Art style > Cel-shaded; GameState.art_style == 1).
##
## A full-resolution screen pass in the spirit of Jet Set Radio / the Dragon Ball fighters: flat lighting
## bands, saturated colour and bold black ink lines from depth and normal jumps. It is ONE full-screen quad
## (shaders/cel/cel_post.gdshader, a spatial shader so it can read the depth and normal textures) that is
## parented to whichever Camera3D is current and hidden while the style is Realistic. The HUD is a
## CanvasLayer drawn on top and is never touched.
##
## It does not change a material, a camera or a saved setting. The cheaper render settings the look allows
## are applied by GameState.apply_graphics() / TimeOfDay.apply_post() only while the style is on.
##
##   var cel := CelShade.new(); add_child(cel)   # group "cel_shade"; GameState.apply_graphics() toggles it
##   cel.set_enabled(true)

const SHADER_PATH := "res://shaders/cel/cel_post.gdshader"

var enabled: bool = false

var _quad: MeshInstance3D = null
var _mat: ShaderMaterial = null


func _ready() -> void:
	add_to_group("cel_shade")
	_build()
	set_enabled(enabled)


func _build() -> void:
	if _quad != null:
		return
	var sh: Shader = load(SHADER_PATH) as Shader
	if sh == null:
		push_warning("CelShade: shader missing at %s" % SHADER_PATH)
		return
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.render_priority = -128                # first of the transparent pass: its screen copy has no clouds / water yet, so they must draw on top of it
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	qm.flip_faces = true
	_quad = MeshInstance3D.new()
	_quad.name = "CelQuad"
	_quad.mesh = qm
	_quad.material_override = _mat
	_quad.extra_cull_margin = 16384.0           # the vertex shader pins it to the screen; never cull it
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.visible = false
	add_child(_quad)


func set_enabled(on: bool) -> void:
	enabled = on
	if _quad == null:
		return
	_quad.visible = on
	set_process(on)
	if on:
		_follow_camera()
		_push_size()


## Park the quad under the current camera (the chase, cockpit and gunner cameras take turns).
func _follow_camera() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or _quad == null:
		return
	if _quad.get_parent() != cam:
		if _quad.get_parent() != null:
			_quad.get_parent().remove_child(_quad)
		cam.add_child(_quad)
		_quad.transform = Transform3D.IDENTITY


func _push_size() -> void:
	if _mat == null:
		return
	var vs: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	var win: Window = get_window()
	if win != null:
		vs = Vector2(win.size)            # real pixels, not the UI-scaled canvas
	_mat.set_shader_parameter("view_px", vs)


func _process(_delta: float) -> void:
	if not enabled:
		return
	_follow_camera()
	_push_size()


func is_active() -> bool:
	return enabled and _quad != null and _quad.visible


func material() -> ShaderMaterial:
	return _mat
