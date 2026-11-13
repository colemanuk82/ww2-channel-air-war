extends CanvasLayer
## Lens finish for the post presets: a soft optical vignette and a fine, animated film grain, drawn over the
## 3D view but under every HUD / menu layer. Both are subtle (a few percent): they take the "clean render" edge
## off the image the way a camera lens and film stock do. Level 1 runs a fainter grain; level 2 the full look.

const SHADER := """
shader_type canvas_item;
render_mode blend_mix;
uniform float vignette = 0.22;
uniform float grain = 0.03;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float d = length(uv);
	float v = smoothstep(0.42, 1.05, d) * vignette;
	// grain: per-pixel hash, re-rolled ~24 times a second like film frames; quieter on bright sky so the
	// grain reads in the shadows and midtones where film grain actually lives
	vec3 sc = texture(screen_tex, SCREEN_UV).rgb;
	float luma = dot(sc, vec3(0.30, 0.59, 0.11));
	vec2 px = floor(FRAGCOORD.xy);
	float fr = floor(TIME * 24.0);
	float n = fract(sin(dot(px + fr * vec2(17.13, 41.7), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	// darkening vignette in black; grain as a tiny grey offset (alpha-blended so it never clips the HUD below)
	float g = n * grain * (1.0 - 0.55 * luma);
	vec3 c = g > 0.0 ? vec3(1.0) : vec3(0.0);
	float a = max(v, 0.0);
	vec3 col = mix(c, vec3(0.0), a / max(a + abs(g), 1e-4));
	COLOR = vec4(col, clamp(a + abs(g), 0.0, 1.0));
}
"""

var _rect: ColorRect


func _ready() -> void:
	layer = -1
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_rect.material = mat
	add_child(_rect)
	_refresh()
	GameState.settings_changed.connect(_refresh)


func _refresh() -> void:
	visible = GameState.post_fx >= 1 and OS.get_environment("WW2_NO_FILM") != "1"
	var m := _rect.material as ShaderMaterial
	m.set_shader_parameter("grain", 0.03 if GameState.post_fx >= 2 else 0.016)
	m.set_shader_parameter("vignette", 0.22 if GameState.post_fx >= 2 else 0.16)
