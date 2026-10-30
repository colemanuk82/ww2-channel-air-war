shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform vec4 beam_color : source_color = vec4(0.55, 0.60, 0.70, 0.10);

void fragment() {
	// Fade around the circumference and up the cone: a soft shaft rather than a hard cylinder edge.
	float around = smoothstep(0.0, 0.32, UV.x) * (1.0 - smoothstep(0.68, 1.0, UV.x));
	float vertical = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.72, 1.0, UV.y));
	ALBEDO = beam_color.rgb;
	ALPHA = beam_color.a * around * (0.35 + 0.65 * vertical);
}
