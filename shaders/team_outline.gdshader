shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled, blend_mix, depth_draw_never;

// Team outline for AI aircraft (used as a material overlay): red = enemy, yellow = friendly. Faint, and it fades out
// beyond a few kilometres, and it also fades out when the aircraft is close enough to be recognised by eye.
uniform vec4 outline_color : source_color = vec4(1.0, 0.15, 0.1, 1.0);
uniform float thickness = 0.05;
uniform float dist_scale = 0.0009;
uniform float strength = 0.5;
global uniform float outline_near_start;
global uniform float outline_fade_end;
global uniform float outline_enabled;
global uniform float night_k;          // 0 day .. 1 night (FX): outlines show up closer in the dark

varying float v_dist;
varying vec3 o_p;
instance uniform vec4 cut = vec4(0.0);     // the same structural cut as the aircraft skin

void vertex() {
	float d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	v_dist = d;
	o_p = VERTEX;
	VERTEX += NORMAL * (thickness + min(d, outline_fade_end) * dist_scale);
}

void fragment() {
	if ((cut.x > 0.0 && o_p.x > cut.x) || (cut.y > 0.0 && o_p.x < -cut.y) || (cut.z > 0.0 && o_p.z > cut.z)) {
		discard;
	}
	float near_start = outline_near_start;
	float near_end = outline_near_start + 250.0;   // show the colour quickly past the chosen low range
	float fade_end = max(outline_fade_end, near_end + 500.0);
	float fade_start = max(near_end, fade_end - 2500.0);
	ALBEDO = outline_color.rgb;
	ALPHA = strength * outline_enabled * (1.0 - smoothstep(fade_start, fade_end, v_dist)) * mix(smoothstep(near_start, near_end, v_dist), 1.0, night_k);
}
