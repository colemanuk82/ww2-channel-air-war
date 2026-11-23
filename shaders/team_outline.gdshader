shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled, blend_mix, depth_draw_never, fog_disabled;   // no fog: a far outline must stay red / yellow

// Team outline for AI aircraft (used as a material overlay): red = enemy, yellow = friendly. Faint, and it fades out
// beyond a few kilometres, and it also fades out when the aircraft is close enough to be recognised by eye.
const float OUTLINE_MIN_END = 16000.0;
uniform bool box_hull = false;      // far stand-in boxes: inflate along sign(VERTEX); a box's per-face normals would move the faces apart and leave no ring
uniform vec4 outline_color : source_color = vec4(1.0, 0.15, 0.1, 1.0);
uniform float thickness = 0.05;
uniform float dist_scale = 0.0009;
uniform float strength = 0.5;
uniform vec2 range_m = vec2(0.0);   // ground units (GroundMarks): (fade-in start, fade-out end) in metres; (0, 0) = the aircraft's global range
uniform float far_k = 1.0;          // weight of the heavy far styling (opaque, grown ring): ground units use less of it
global uniform float outline_near_start;
global uniform float outline_fade_end;
global uniform float outline_enabled;
global uniform float night_k;          // 0 day .. 1 night (FX): outlines show up closer in the dark

varying float v_dist;
varying float v_far;
varying vec3 o_p;
instance uniform vec4 cut = vec4(0.0);     // the same structural cut as the aircraft skin

void vertex() {
	float d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	v_dist = d;
	// beyond the detailed-model range the far stand-in boxes are tiny dark specks: grow the ring a little and make it opaque
	v_far = smoothstep(3000.0, 6000.0, d) * far_k;   // v4.31: the heavy far styling builds up only past ~3 km (was 1.2-3.5 km); full far weight by 6 km, so 8-20 km is unchanged
	float ramp = mix(0.35, 1.0, smoothstep(1500.0, 6000.0, d));   // close range: thin ring that grows with distance
	o_p = VERTEX;
	VERTEX += (box_hull ? sign(VERTEX) : NORMAL) * (thickness + min(d, (range_m.y > 0.0 ? range_m.y : max(outline_fade_end, OUTLINE_MIN_END))) * dist_scale * (1.0 + 0.5 * v_far) * ramp);
}

void fragment() {
	if ((cut.x > 0.0 && o_p.x > cut.x) || (cut.y > 0.0 && o_p.x < -cut.y) || (cut.z > 0.0 && o_p.z > cut.z)) {
		discard;
	}
	bool ground = range_m.y > 0.0;
	float near_start = ground ? range_m.x : outline_near_start;
	float near_end = near_start + 250.0;   // show the colour quickly past the chosen low range
	float fade_end = ground ? range_m.y : max(max(outline_fade_end, OUTLINE_MIN_END), near_end + 500.0);   // aircraft: never shorter than 16 km, the far aircraft stay marked
	float fade_start = max(near_end, fade_end - (ground ? 2500.0 : 6000.0));                               // long soft fade, no pop
	ALBEDO = outline_color.rgb;
	ALPHA = mix(mix(strength * 0.45, strength, smoothstep(300.0, 3000.0, v_dist)), 0.95, v_far) * outline_enabled * (1.0 - smoothstep(fade_start, fade_end, v_dist)) * mix(smoothstep(near_start, near_end, v_dist), 1.0, night_k);
}
