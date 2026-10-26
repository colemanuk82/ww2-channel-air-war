shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Curtain of rain under a rain cloud, as it looks from a distance: a soft grey veil, not individual streaks.
// Density varies in slow vertical bands that drift, the curtain leans downwind, the bottom edge is ragged
// (some of it never reaches the ground, like virga), it is darkest just under the cloud base and fades at
// the silhouette. Dims with the global night factor.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 shaft_color : source_color = vec4(0.55, 0.58, 0.63, 1.0);
uniform float lean = 0.35;              // how far the bottom drifts downwind (unit-cylinder space)
global uniform float night_k;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return vn(p) * 0.55 + vn(p * 2.1) * 0.3 + vn(p * 4.3) * 0.15;
}

varying float v_seed;

void vertex() {
	// lean the curtain downwind: the lower it is, the further it has drifted
	VERTEX.x += (1.0 - UV.y) * lean;
	v_seed = fract(MODEL_MATRIX[3].x * 0.0013 + MODEL_MATRIX[3].z * 0.0007);
}

void fragment() {
	float u = UV.x * 9.0 + v_seed * 31.0;      // around the tube (wraps 0..1)
	float y = UV.y;                             // 1 at the cloud base, 0 at the ground
	// slow broad density bands, stretched vertically, drifting sideways a little
	float bands = fbm(vec2(u + TIME * 0.015, y * 1.4 - TIME * 0.05));
	// fine vertical texture: falling sheets, very low contrast
	float sheets = vn(vec2(UV.x * 140.0 + v_seed * 50.0, y * 6.0 + TIME * 0.9));
	// ragged bottom: each part of the curtain ends at its own height
	float reach = mix(0.0, 0.55, vn(vec2(u * 1.7, 3.0 + v_seed * 9.0)));
	float bot = smoothstep(reach, reach + 0.28, y);
	float top = smoothstep(1.0, 0.86, y);
	float darker_top = mix(0.55, 1.0, smoothstep(0.0, 0.8, y));     // heaviest right under the cloud
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	float d = smoothstep(0.25, 0.85, bands) * (0.8 + 0.2 * sheets);
	float a = amount * 0.42 * d * darker_top * top * bot * edge;
	vec3 col = shaft_color.rgb * mix(0.85, 1.05, sheets) * mix(1.0, 0.16, night_k);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 0.4);
}
