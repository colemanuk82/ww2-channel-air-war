shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// Flat scorched-earth disc with banded rings. UV is a unit quad.
uniform float strength : hint_range(0.0, 1.0) = 1.0;
varying vec3 wp;

void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float wob = 0.06 * sin(atan(uv.y, uv.x) * 5.0 + wp.x * 0.3) + 0.04 * sin(atan(uv.y, uv.x) * 9.0);
	r += wob;
	vec3 col = vec3(0.30, 0.22, 0.14);
	col = mix(col, vec3(0.16, 0.12, 0.09), step(r, 0.72));
	col = mix(col, vec3(0.06, 0.05, 0.05), step(r, 0.42));
	ALBEDO = col;
	ALPHA = step(r, 1.0) * strength * (r < 0.85 ? 0.9 : 0.6);
	if (ALPHA < 0.05) discard;
}
