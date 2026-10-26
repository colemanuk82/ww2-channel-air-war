shader_type spatial;
render_mode specular_schlick_ggx, cull_back, depth_draw_opaque;
global uniform float wetness;
// Painted-metal aircraft skin, matched to photographs of the real aircraft: matt camouflage projected in object
// space (no UVs), a hard-edged underside demarcation, structured panel seams (fuselage frames and stringer laps,
// wing ribs and spar lines) with rivet rows only along the seams, the odd access hatch, and light weathering.
// Object space: +X span (starboard), +Y up, -Z forward (nose). Textures come from tools/make_aircraft_camo.py.
uniform sampler2D camo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float camo_scale = 0.30;                 // object-metres -> texture tiles
uniform vec4 underside_color : source_color = vec4(0.58, 0.63, 0.66, 1.0);
uniform float under_amount : hint_range(0.0, 1.0) = 0.85;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.66;
uniform float metallic : hint_range(0.0, 1.0) = 0.06;
uniform float wear : hint_range(0.0, 1.0) = 0.6;          // seams, grime, chipping
uniform float gloss : hint_range(0.0, 1.0) = 0.0;          // extra sheen (bare metal)
uniform vec4 tint : source_color = vec4(1, 1, 1, 1);
uniform float night_amount = 0.0;
// 0 = camouflage over the top and sides down to a low demarcation (RAF, USAAF, Luftwaffe bombers)
// 1 = Luftwaffe fighter 1940-41: splinter on the top surfaces only, pale sides with soft dark mottling
uniform int scheme_mode = 0;
uniform vec4 mottle_a : source_color = vec4(0.43, 0.43, 0.36, 1.0);   // RLM 02
uniform vec4 mottle_b : source_color = vec4(0.25, 0.29, 0.21, 1.0);   // RLM 71

varying vec3 o_p;
varying vec3 o_n;
// Structural loss (see AircraftDamageModel): fragments past these object-space limits are cut away.
// x = starboard wing from this |x| outward, y = port wing, z = everything aft of this z (the tail); 0 = intact.
instance uniform vec4 cut = vec4(0.0);
// National markings painted into the skin (GltfModels bakes each marking group into a slot of decal_atlas and a
// planar projector here): no separate decal meshes, so nothing can sink into or float off the airframe.
const int MAX_DECALS = 8;
uniform sampler2D decal_atlas : source_color, filter_linear, repeat_disable;
uniform int decal_count = 0;
uniform vec4 decal_c[MAX_DECALS];   // projector centre (Body space), w = depth tolerance
uniform vec4 decal_u[MAX_DECALS];   // u axis / half extent, w = 1 for two-sided (fin flash)
uniform vec4 decal_v[MAX_DECALS];   // v axis / half extent
uniform vec4 decal_n[MAX_DECALS];   // plane normal, w = minimum facing
instance uniform vec3 body_off = vec3(0.0);   // this mesh's origin in Body space (skin parts are only translated)

void vertex() {
	o_p = VERTEX;
	o_n = normalize(NORMAL);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x),
	           mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

// 1 on a seam line of half-width w (metres) repeating every `spacing` along coordinate c, anti-aliased with
// the screen-space derivative so seams thin out instead of shimmering at a distance.
float seam_line(float c, float spacing, float w) {
	float d = abs(fract(c / spacing + 0.5) - 0.5) * spacing;
	float aa = max(fwidth(c), 1e-5);
	return (1.0 - smoothstep(w, w + aa * 1.2, d)) * clamp(w * 3.0 / aa, 0.0, 1.0);
}

// rivet heads along a seam: a row offset `off` from the line, one every `pitch` metres along coordinate a
float rivet_row(float a, float c, float spacing, float off, float pitch) {
	float d = abs(fract(c / spacing + 0.5) - 0.5) * spacing;
	vec2 q = vec2((fract(a / pitch) - 0.5) * pitch, d - off);
	float r = 1.0 - smoothstep(0.0035, 0.0065, length(q));
	float aa = max(fwidth(a), 1e-5);
	return r * clamp(0.004 / aa - 0.5, 0.0, 1.0);   // fade out once a rivet is smaller than a pixel
}

void fragment() {
	if ((cut.x > 0.0 && o_p.x > cut.x) || (cut.y > 0.0 && o_p.x < -cut.y) || (cut.z > 0.0 && o_p.z > cut.z)) {
		discard;
	}
	vec3 n = o_n;
	vec3 an = abs(n);
	// triplanar camouflage with sharp blend weights so patches stay crisp over curved skin
	vec3 w3 = pow(an, vec3(4.0));
	w3 /= max(w3.x + w3.y + w3.z, 1e-4);
	float s = camo_scale;
	vec3 cx = texture(camo_tex, o_p.zy * s).rgb;
	vec3 cy = texture(camo_tex, o_p.xz * s).rgb;
	vec3 cz = texture(camo_tex, o_p.xy * s).rgb;
	vec3 col = cx * w3.x + cy * w3.y + cz * w3.z;

	if (scheme_mode == 1) {
		// top surfaces carry the splinter; the sides are the pale underside blue with soft dark mottles
		float top = smoothstep(0.30, 0.48, n.y);
		// soft-edged spray mottles about 15-30 cm across, denser near the spine (photos of Bf 109 E)
		float hi = smoothstep(-0.3, 0.4, n.y);
		float m1 = smoothstep(0.60 - hi * 0.08, 0.74 - hi * 0.08, vnoise2(o_p.zy * 5.5) * 0.65 + vnoise2(o_p.zy * 13.0) * 0.35);
		float m2 = smoothstep(0.64 - hi * 0.08, 0.78 - hi * 0.08, vnoise2(o_p.zy * 4.6 + 17.0) * 0.65 + vnoise2(o_p.zy * 11.0 + 5.0) * 0.35);
		vec3 side = underside_color.rgb;
		side = mix(side, mottle_a.rgb, m1 * 0.85);
		side = mix(side, mottle_b.rgb, m2 * 0.8);
		float side_zone = smoothstep(-0.45, -0.2, n.y);
		col = mix(mix(underside_color.rgb, side, side_zone), col, top);
	} else {
		// hard-edged (sprayed) demarcation low on the fuselage side; wing undersides fully painted
		float down = 1.0 - smoothstep(-0.40, -0.30, n.y);
		col = mix(col, underside_color.rgb, down * under_amount);
	}
	col *= tint.rgb;

	// ---- structured panel seams
	float side_w = smoothstep(0.55, 0.75, an.x) * (1.0 - smoothstep(0.75, 0.9, an.y));
	float flat_w = smoothstep(0.55, 0.8, an.y);
	// fuselage / fin sides: frames every 0.48 m along the length, stringer laps every 0.36 m in height
	float s_frame = seam_line(o_p.z, 0.48, 0.0045);
	float s_lap = seam_line(o_p.y + 0.11, 0.36, 0.0035);
	// wings / tailplanes / spine: ribs every 0.6 m of span, spar and panel lines every 0.52 m of chord
	float s_rib = seam_line(o_p.x + 0.17, 0.60, 0.0045);
	float s_spar = seam_line(o_p.z + 0.21, 0.52, 0.0040);
	// nose-on surfaces (cowling front, spinner sides): rings every 0.4 m
	float s_ring = seam_line(o_p.z, 0.40, 0.004) * smoothstep(0.6, 0.85, an.z);
	float seam = max(max(s_frame, s_lap * 0.8) * side_w, max(s_rib, s_spar) * flat_w);
	seam = max(seam, s_ring);
	// access hatches: an inset rectangle in roughly one panel in six
	vec2 hp = (side_w > flat_w) ? vec2(o_p.z / 0.48, (o_p.y + 0.11) / 0.36) : vec2((o_p.x + 0.17) / 0.60, (o_p.z + 0.21) / 0.52);
	vec2 cell = floor(hp + 0.5);
	float hatch_on = step(0.83, hash12(cell + 3.7));
	vec2 hf = abs(fract(hp + 0.5) - 0.5);
	float hatch = (1.0 - smoothstep(0.0, 0.025, abs(max(hf.x, hf.y) - 0.30))) * hatch_on;
	float panel_tone = (hash12(cell) - 0.5) * 0.05;
	// rivet rows either side of each seam
	float riv = 0.0;
	riv = max(riv, rivet_row(o_p.y, o_p.z, 0.48, 0.016, 0.042) * side_w);
	riv = max(riv, rivet_row(o_p.z, o_p.y + 0.11, 0.36, 0.014, 0.05) * side_w * 0.8);
	riv = max(riv, rivet_row(o_p.z, o_p.x + 0.17, 0.60, 0.016, 0.045) * flat_w);
	riv = max(riv, rivet_row(o_p.x, o_p.z + 0.21, 0.52, 0.014, 0.05) * flat_w);
	col *= 1.0 + panel_tone * wear;
	col *= 1.0 - (seam * 0.42 + hatch * 0.30) * wear;
	col *= 1.0 + riv * 0.10 * wear;

	// ---- weathering: grime under the belly and streaked aft, light chipping on leading edges, sun fade
	float grime = vnoise2(vec2(o_p.y * 2.6, o_p.z * 0.6)) * 0.6 + vnoise2(vec2(o_p.x * 7.0, o_p.z * 0.5)) * 0.4;
	float belly = smoothstep(0.0, 1.0, -n.y) * 0.8;
	col *= 1.0 - clamp(grime * belly, 0.0, 1.0) * 0.18 * wear;
	float lead = smoothstep(0.6, 0.95, -n.z) * smoothstep(0.55, 0.85, vnoise2(o_p.xy * 11.0 + o_p.z));
	col = mix(col, vec3(0.50, 0.51, 0.50), lead * 0.30 * wear);
	float chip = smoothstep(0.80, 0.95, vnoise2(o_p.xz * 6.0 + o_p.y * 3.0)) * max(seam, hatch);
	col = mix(col, vec3(0.50, 0.51, 0.50), chip * 0.18 * wear);
	float up = smoothstep(0.5, 0.95, n.y);
	col = mix(col, col * 1.06 + vec3(0.006), up * 0.25 * wear);
	float streak = vnoise2(vec2(o_p.x * 14.0 + o_p.y * 9.0, o_p.z * 0.8)) * smoothstep(0.35, 0.9, vnoise2(vec2(o_p.x * 3.0, o_p.z * 0.35)));
	col *= 1.0 - streak * 0.08 * wear * (1.0 - up * 0.5);

	float micro = (vnoise2(o_p.xy * 6.0) - 0.5) + (vnoise2(o_p.zy * 6.0) - 0.5);
	NORMAL = normalize(NORMAL + vec3(micro * 0.015 * wear));

	// painted national markings
	vec3 bp = o_p + body_off;
	for (int i = 0; i < MAX_DECALS; i++) {
		if (i >= decal_count) { break; }
		vec3 dd = bp - decal_c[i].xyz;
		if (abs(dot(dd, decal_n[i].xyz)) > decal_c[i].w) { continue; }
		float face = dot(o_n, decal_n[i].xyz);
		if (decal_u[i].w > 0.5) { face = abs(face); }
		if (face < decal_n[i].w) { continue; }
		vec2 duv = vec2(dot(dd, decal_u[i].xyz), dot(dd, decal_v[i].xyz));
		if (abs(duv.x) > 1.0 || abs(duv.y) > 1.0) { continue; }
		vec2 suv = clamp(duv * 0.5 + 0.5, vec2(0.006), vec2(0.994));
		vec4 dc = textureLod(decal_atlas, vec2((suv.x + float(i)) / float(MAX_DECALS), suv.y), 0.0);
		// paint, but keep a trace of the panel lines and grime under it
		col = mix(col, dc.rgb * (0.9 + 0.1 * smoothstep(0.0, 0.6, dot(col, vec3(0.33)))), dc.a);
	}

	col *= 1.0 - 0.18 * wetness;
	ALBEDO = col;
	ROUGHNESS = clamp(base_roughness + grime * 0.12 + seam * 0.1 - gloss * 0.25 - 0.4 * wetness, 0.05, 1.0);
	METALLIC = clamp(metallic + chip * 0.4 * wear, 0.0, 1.0);
	SPECULAR = 0.42 + gloss * 0.3;
}
