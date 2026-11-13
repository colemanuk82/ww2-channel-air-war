shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// Cartoon starburst billboard (explosions, muzzle flashes, flak flashes).
uniform vec4 color : source_color = vec4(1.0, 0.55, 0.1, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.95, 0.6, 1.0);
uniform float prog : hint_range(0.0, 1.0) = 0.0;
uniform float spikes = 8.0;
// realistic scenery: a soft, hot flash (bright core fading into an orange glow, a faint ragged rim, no ink
// outline and no cartoon spikes) instead of the comic starburst
uniform bool soft_flash = false;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float a = atan(uv.y, uv.x);
	if (soft_flash) {
		float grow_s = 1.0 - pow(1.0 - clamp(prog * 3.0, 0.0, 1.0), 2.0);
		float fade = 1.0 - smoothstep(0.25, 1.0, prog);
		float rag = 0.85 + 0.15 * sin(a * 7.0 + prog * 6.0) * sin(a * 3.0 - 1.3);
		float rr = r / max(0.25 + 0.75 * grow_s, 0.01) / rag;
		float glow = exp(-rr * rr * 3.2);
		float hot = exp(-rr * rr * 14.0);
		vec3 cs = mix(color.rgb * 0.9, core_color.rgb * 1.6, hot);
		ALBEDO = cs * (1.0 + 2.0 * hot * (1.0 - prog));
		ALPHA = clamp(glow * fade * 0.9, 0.0, 1.0);
	} else {
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
}
