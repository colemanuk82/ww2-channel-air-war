class_name GVision
extends CanvasLayer
## Pilot vision under G: grey tunnel vision closing in on sustained positive G, red-out on negative G, black while
## unconscious (G-LOC), and a slow fade back in. Driven by Aircraft.g_gray / g_red / gloc_t (GameState.g_effects_on).
## One full-screen ColorRect with a small radial-vignette shader; nothing is drawn while the level is zero.

const SHADER := """
shader_type canvas_item;
uniform float gray = 0.0;
uniform float red = 0.0;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);
void fragment() {
	vec2 uv = UV - vec2(0.5);
	uv.x *= 1.7;
	float d = length(uv);
	// tunnel: the clear circle shrinks from the screen edge to a pinhole as the level rises
	float level = max(gray, red);
	float clear_r = mix(1.1, 0.0, smoothstep(0.0, 1.0, level));
	float a = smoothstep(clear_r, clear_r + 0.35, d);
	a = max(a, smoothstep(0.75, 1.0, level));
	vec3 c = mix(vec3(0.02, 0.02, 0.025), vec3(0.45, 0.0, 0.0), step(gray, red) * step(0.001, red));
	COLOR = vec4(c, clamp(a, 0.0, 1.0));
}
"""

var hud: Node
var _rect: ColorRect
var _mat: ShaderMaterial
var _lvl: float = 0.0


func _ready() -> void:
	layer = 35
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


func _process(delta: float) -> void:
	var a: Aircraft = null
	if hud != null and is_instance_valid(hud):
		a = hud.get("aircraft") as Aircraft
	var gray: float = 0.0
	var red: float = 0.0
	if a != null and is_instance_valid(a) and GameState.g_effects_on and a.state == Aircraft.State.ALIVE:
		gray = a.g_gray
		red = a.g_red
	var lvl: float = maxf(gray, red)
	_lvl = lvl
	_rect.visible = lvl > 0.003
	if _rect.visible:
		_mat.set_shader_parameter("gray", gray)
		_mat.set_shader_parameter("red", red)
