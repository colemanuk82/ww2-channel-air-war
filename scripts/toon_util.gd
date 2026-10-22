class_name ToonUtil
extends RefCounted
## Helpers to build toon (+ inverted-hull outline) materials in code.
## Usage:
##   var mat := ToonUtil.make_toon(Color(0.4, 0.5, 0.3))                     # toon + outline
##   var mat2 := ToonUtil.make_toon(c, {"outline": false, "rim": 0.0})
##   var mi := ToonUtil.make_mesh(BoxMesh.new(), c, {"outline_thickness": 0.05})
## Options: outline(bool) outline_thickness outline_color underside(Color) patch(Color)
##          patch_amount patch_scale detail(0-5: building/asphalt/foliage/grass/aircraft) rim emission(Color) emission_energy ramp(Texture2D)
##          flat(bool): solid colour, no shadow and no toon banding (used by buildings)
## Outlines can be toggled globally with GameState.toggle_outlines().

const TOON_SHADER_PATH := "res://shaders/toon.gdshader"
const OUTLINE_SHADER_PATH := "res://shaders/outline.gdshader"
const GLASS_SHADER_PATH := "res://shaders/canopy_glass.gdshader"

static var _toon_shader: Shader
static var _outline_shader: Shader
static var _glass_shader: Shader


static func toon_shader() -> Shader:
	if _toon_shader == null:
		_toon_shader = load(TOON_SHADER_PATH) as Shader
	return _toon_shader


static func outline_shader() -> Shader:
	if _outline_shader == null:
		_outline_shader = load(OUTLINE_SHADER_PATH) as Shader
	return _outline_shader


static func glass_shader() -> Shader:
	if _glass_shader == null:
		_glass_shader = load(GLASS_SHADER_PATH) as Shader
	return _glass_shader


## Transparent cockpit glazing (see shaders/canopy_glass.gdshader).
## Options: opacity rim tint sky glint.
static func make_glass(opts: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = glass_shader()
	if opts.has("tint"):
		m.set_shader_parameter("tint", opts["tint"])
	if opts.has("opacity"):
		m.set_shader_parameter("opacity", opts["opacity"])
	if opts.has("rim"):
		m.set_shader_parameter("rim_amount", opts["rim"])
	if opts.has("sky"):
		m.set_shader_parameter("sky_color", opts["sky"])
	if opts.has("glint"):
		m.set_shader_parameter("glint", opts["glint"])
	return m


static func make_outline(thickness: float = 0.03, color: Color = Color(0.04, 0.04, 0.06)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = outline_shader()
	m.set_shader_parameter("thickness", thickness)
	m.set_shader_parameter("outline_color", color)
	return m


static func make_toon(color: Color, opts: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = toon_shader()
	m.set_shader_parameter("albedo", color)
	if opts.has("underside"):
		m.set_shader_parameter("underside_color", opts["underside"])
		m.set_shader_parameter("underside_amount", 1.0)
	if opts.has("patch"):
		m.set_shader_parameter("patch_color", opts["patch"])
		m.set_shader_parameter("patch_amount", opts.get("patch_amount", 1.0))
		m.set_shader_parameter("patch_scale", opts.get("patch_scale", 0.5))
	if opts.has("detail"):
		m.set_shader_parameter("detail_mode", int(opts["detail"]))
	if opts.has("gloss"):
		m.set_shader_parameter("gloss", opts["gloss"])
	if opts.has("soft"):
		m.set_shader_parameter("softness", opts["soft"])
	if opts.get("flat", false):
		m.set_shader_parameter("flat_shade", 1.0)
	if opts.has("rim"):
		m.set_shader_parameter("rim_amount", opts["rim"])
	if opts.has("emission"):
		m.set_shader_parameter("emission_color", opts["emission"])
		m.set_shader_parameter("emission_energy", opts.get("emission_energy", 1.0))
	if opts.has("ramp"):
		m.set_shader_parameter("ramp_tex", opts["ramp"])
		m.set_shader_parameter("use_ramp_tex", true)
	if opts.get("outline", true):
		m.next_pass = make_outline(opts.get("outline_thickness", 0.03), opts.get("outline_color", Color(0.04, 0.04, 0.06)))
	return m


static func make_mesh(mesh: Mesh, color: Color, opts: Dictionary = {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = make_toon(color, opts)
	return mi
