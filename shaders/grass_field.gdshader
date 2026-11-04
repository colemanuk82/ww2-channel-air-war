shader_type spatial;
render_mode specular_disabled, cull_back, depth_draw_opaque;
// One surface for a whole grass landing ground (RAF grass stations and Luftwaffe forward fields): mown bands,
// a cross-mown direction, a ragged edge where the mown area meets the longer grass, two pairs of wandering
// wheel ruts, worn patches and fine grass mottling - all procedural, so there are no stacked boxes to z-fight or
// step at their edges. The outer border fades into the terrain with hashed alpha (stays in the opaque pass).
// Coordinates are the airfield's local frame in metres: x across the strip, z along it.

global uniform float wetness;

uniform float half_w = 75.0;          // half width of the surface
uniform float half_l = 600.0;         // half length of the surface
uniform float rw = 50.0;              // the airfield's runway_width (the ruts sit at fractions of it)
uniform float seed = 0.0;
uniform vec3 col_a : source_color = vec3(0.26, 0.33, 0.17);   // mown
uniform vec3 col_b : source_color = vec3(0.20, 0.26, 0.12);   // mown the other way
uniform vec3 col_edge : source_color = vec3(0.37, 0.44, 0.24); // longer grass round the mown area
uniform vec3 col_bare : source_color = vec3(0.27, 0.23, 0.14); // worn earth and ruts
uniform float cross_on = 0.0;         // RAF stations: a second mown direction across the field
uniform float cross_angle = 1.13;

varying vec2 lp;
varying vec3 wp;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.03 + 7.1) * 0.30 + vnoise(p * 4.1 + 3.7) * 0.15;
}

void vertex() {
	lp = VERTEX.xz;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Draw a hair in front of the ground beneath it without moving it on screen: the view-space position is
	// pulled toward the camera by a fraction of its distance (millimetres close up, a metre or two from km away),
	// which beats depth-buffer fighting with the terrain at every range.
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.xyz *= 0.9993;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	float x = lp.x;
	float z = lp.y;
	float sd = seed * 0.013;
	float dist = length(wp - CAMERA_POSITION_WORLD);
	// fine detail fades with distance (and with pixel footprint) so it never shimmers
	float near_k = 1.0 - smoothstep(250.0, 1400.0, dist);

	// mown bands along the strip: irregular widths, a slight swing
	float swing = (vnoise(vec2(z * 0.004, sd)) - 0.5) * 0.7;
	float bc = x / (rw * 0.31) + swing;
	float band = smoothstep(0.42, 0.58, fract(bc * 0.5)) - smoothstep(0.92, 1.0, fract(bc * 0.5));
	vec3 c = mix(col_a, col_b, band * 0.8);
	if (cross_on > 0.5) {
		vec2 r = vec2(cos(cross_angle) * x - sin(cross_angle) * z, sin(cross_angle) * x + cos(cross_angle) * z);
		float inside = (1.0 - smoothstep(rw * 0.9, rw * 1.05, abs(r.x))) * (1.0 - smoothstep(half_l * 0.62, half_l * 0.72, abs(r.y)));
		float cb = smoothstep(0.42, 0.58, fract(r.x / (rw * 0.29) * 0.5 + 0.25));
		c = mix(c, mix(col_b, col_a, cb), inside * 0.45);
	}

	// ragged edge of the mown area, then longer, lighter grass out to the border
	float en = fbm(vec2(z * 0.035, sd * 3.1)) * 2.0 - 1.0;
	float edge_x = rw * 1.16 + en * rw * 0.10;
	float outer = smoothstep(edge_x - 2.5, edge_x + 2.5, abs(x));
	float tuft = fbm(lp * 0.22 + sd) ;
	c = mix(c, mix(col_edge, col_b, smoothstep(0.45, 0.75, tuft) * 0.6), outer * 0.85);

	// wheel ruts: two pairs wandering gently along the strip, broken up where the grass has recovered
	float ruts = 0.0;
	for (int i = 0; i < 4; i++) {
		float f = (i == 0) ? -0.30 : ((i == 1) ? 0.30 : ((i == 2) ? -0.50 : 0.50));
		float xx = f * rw + sin(z * 0.018 + f * 7.0) * 1.6 + (vnoise(vec2(z * 0.07, f * 13.0 + sd)) - 0.5) * 1.1;
		float d = abs(x - xx);
		float on = smoothstep(0.30, 0.65, vnoise(vec2(z * 0.045, f * 9.0 + sd)));
		ruts = max(ruts, (1.0 - smoothstep(0.35, 0.95, d)) * on);
	}
	ruts *= 1.0 - smoothstep(half_l * 0.86, half_l * 0.92, abs(z));
	// worn patches inside the field, more of them where aircraft turn at the ends
	float ends = smoothstep(half_l * 0.70, half_l * 0.92, abs(z)) * (1.0 - outer);
	float worn = smoothstep(0.66 - ends * 0.18, 0.80 - ends * 0.18, fbm(lp * 0.045 + sd * 2.0)) * (1.0 - outer * 0.6);
	c = mix(c, col_bare, clamp(ruts * 0.72 + worn * 0.55, 0.0, 0.85));

	// grass mottling and blade texture
	float fine = vnoise(lp * 2.3 + sd) * 0.6 + vnoise(lp * 0.55) * 0.4;
	float blades = vnoise(vec2(lp.x * 14.0, lp.y * 3.0)) ;
	c *= 1.0 + ((fine - 0.5) * 0.22 + (blades - 0.5) * 0.10 * near_k) * mix(0.4, 1.0, near_k);

	c *= mix(1.0, 0.72, clamp(wetness, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = mix(1.0, 0.6, clamp(wetness, 0.0, 1.0));

	// fade the border into the terrain (hashed alpha: opaque pass, no sorting; temporal AA smooths it)
	float bx = half_w * 0.94 + en * half_w * 0.05;
	float bz = half_l * 0.97 + (vnoise(vec2(x * 0.05, sd)) - 0.5) * 18.0;
	ALPHA = (1.0 - smoothstep(bx - 9.0, bx, abs(x))) * (1.0 - smoothstep(bz - 14.0, bz, abs(z)));
	ALPHA_HASH_SCALE = 1.0;
}
