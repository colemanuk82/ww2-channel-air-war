shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// Cartoon starburst billboard (explosions, muzzle flashes, flak flashes).
uniform vec4 color : source_color = vec4(1.0, 0.55, 0.1, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.95, 0.6, 1.0);
uniform float prog : hint_range(0.0, 1.0) = 0.0;
uniform float spikes = 8.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float a = atan(uv.y, uv.x);
	float e = 0.30 + 0.70 * pow(abs(cos(a * spikes * 0.5)), 5.0);
	float grow = 1.0 - pow(1.0 - clamp(prog * 2.5, 0.0, 1.0), 2.0);
	float edge = e * (0.35 + 0.65 * grow);
	float shrink = 1.0 - smoothstep(0.55, 1.0, prog);
	edge *= shrink;
	float inside = step(r, edge);
	float outline = step(r, edge + 0.04) - inside;
	float core = step(r, edge * 0.55);
	vec3 c = mix(color.rgb, core_color.rgb, core);
	c = mix(c, vec3(0.08, 0.05, 0.04), outline);
	ALBEDO = c;
	ALPHA = clamp(inside + outline, 0.0, 1.0);
	if (ALPHA < 0.5) discard;
}
