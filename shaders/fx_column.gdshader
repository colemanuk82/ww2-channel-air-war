shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, fog_disabled;
// Tall smoke columns (bomb blasts, battle pillars): a mesh of many overlapping puffs (vertex colour = density).
// Soft, translucent edges and a lumpy outline instead of hard lit spheres, a fake top-light, darkened at night
// (light_k) and faded into its own haze - lit spheres caught the blue night sky and read as strings of beads.
uniform float light_k = 1.0;
uniform vec3 haze_color = vec3(0.7, 0.75, 0.82);
uniform float haze_density = 0.00005;
varying vec4 v_col;
varying vec3 v_loc;
varying float v_up;

float h31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	v_col = COLOR;
	v_loc = VERTEX;
	v_up = (MODEL_MATRIX * vec4(NORMAL, 0.0)).y;
}

void fragment() {
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float edge = smoothstep(0.0, 0.65, ndv);
	float lump = vnoise(v_loc * 0.09) * 0.6 + vnoise(v_loc * 0.27) * 0.4;
	float erode = smoothstep(0.2, 0.7, lump + edge * 0.5);
	float top = 0.78 + 0.22 * clamp(v_up * 0.5 + 0.5, 0.0, 1.0);    // a little lighter where it faces the sky
	vec3 c = v_col.rgb * top * light_k;
	float dist = length(VERTEX);
	float haze = 1.0 - exp(-dist * haze_density);
	c = mix(c, haze_color, haze);
	ALBEDO = c;
	ALPHA = clamp(0.93 * edge * erode * (1.0 - 0.4 * haze), 0.0, 1.0);
}
