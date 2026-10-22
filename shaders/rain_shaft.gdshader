shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Curtain of falling rain under a rain cloud: soft vertical streaks that scroll downward, fading out
// at the cloud base, at the ground end and toward the silhouette edges.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 shaft_color : source_color = vec4(0.62, 0.66, 0.72, 1.0);

float h11(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

void fragment() {
	float col_id = floor(UV.x * 48.0);
	float s = h11(col_id);
	float streak = smoothstep(0.45, 0.95, fract(UV.y * (5.0 + s * 4.0) + TIME * (1.4 + s * 1.6) + s * 9.0));
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.4);
	float top_fade = smoothstep(1.0, 0.82, UV.y);       // UV.y = 1 at the cloud base end of the cylinder
	float bot_fade = smoothstep(0.0, 0.25, UV.y);
	float a = amount * (0.10 + 0.34 * streak) * edge * top_fade * bot_fade;
	ALBEDO = shaft_color.rgb;
	ALPHA = clamp(a, 0.0, 0.6);
}
