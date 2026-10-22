shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix, fog_disabled;
// Toon puff/debris for pooled MultiMesh effects. Instance COLOR = rgba, INSTANCE_CUSTOM.x = shade amount.
// Soft billows: the silhouette fades out (fresnel) and a per-puff lumpy noise erodes the alpha, so smoke and dust read as
// airy clouds instead of hard-edged low-poly blobs. Debris (shade = 1 with an opaque colour) keeps its crisp look.
// 1 by day, lower at night: smoke and dust (shade >= 0.5) dim with the light; flames and tracers stay bright
uniform float light_k = 1.0;
// soft particles: fade where a puff cuts into the ground (or a building), so flames and smoke sitting on the
// terrain don't end in a hard, flat-bottomed edge
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float soft_dist = 4.0;
// Own distance haze instead of the engine fog: the engine's aerial perspective mixes distant objects toward the
// SKY colour, which at night is blue, so dark smoke columns turned into strings of blue beads. Smoke now fades
// into a haze colour that darkens with the night (FX sets both every half second).
uniform vec3 haze_color = vec3(0.7, 0.75, 0.82);
uniform float haze_density = 0.00005;
varying vec4 v_col;
varying float v_shade;
varying vec3 v_loc;
varying float v_id;
const mat3 ROT_M = mat3(vec3(0.36, 0.80, -0.48), vec3(-0.80, 0.28, 0.53), vec3(0.48, -0.53, -0.70));

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
	v_shade = INSTANCE_CUSTOM.x;
	v_loc = VERTEX;
	v_id = float(INSTANCE_ID);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float l = dot(n, normalize(vec3(-0.35, 0.75, 0.55)));
	float band = l > 0.3 ? 1.0 : (l > -0.2 ? 0.8 : 0.62);
	float ndv = clamp(dot(n, normalize(VIEW)), 0.0, 1.0);
	vec3 c = v_col.rgb * mix(1.0, band, v_shade);
	c *= mix(1.0, light_k, step(0.5, v_shade));
	// puffs are translucent; opaque chunks (debris) skip the softening.
	// Flames, embers and fireballs spawn at alpha 1.0, so an alpha-only test left every one of them a
	// hard-edged opaque low-poly blob - which from the air reads as a red square sitting on the ground
	// rather than as fire. Only debris (shade = 1 with an opaque colour) keeps its crisp look.
	float soft_amt = max(1.0 - step(0.5, v_shade), 1.0 - smoothstep(0.85, 0.99, v_col.a));
	float edge = smoothstep(0.0, 0.6, ndv);
	vec3 q = ROT_M * v_loc;
	float lump = vnoise(q * 3.0 + vec3(v_id * 7.31, v_id * 3.17, v_id * 1.93)) * 0.5
		+ vnoise(q * 7.0 + vec3(v_id * 2.13)) * 0.3
		+ vnoise(q * 15.0 + vec3(v_id * 5.7)) * 0.2;
	float erode = smoothstep(0.18, 0.72, lump + edge * 0.45);
	float a = v_col.a * mix(1.0, edge * erode, soft_amt * 0.9);
	float dz = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, dz, 1.0);
	float scene_d = -sv.z / sv.w;
	float soft = clamp((scene_d - (-VERTEX.z)) / soft_dist, 0.0, 1.0);
	a *= mix(1.0, soft, soft_amt);
	float dist = length(VERTEX);
	float haze = 1.0 - exp(-dist * haze_density);
	float smoke = step(0.5, v_shade);
	c = mix(c, haze_color, haze * mix(0.35, 1.0, smoke));
	a *= 1.0 - 0.45 * haze * smoke;        // far smoke thins out rather than reading as solid balls
	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 1.0);
}
