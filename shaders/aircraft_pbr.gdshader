shader_type spatial;
render_mode specular_schlick_ggx, cull_back, depth_draw_opaque;
global uniform float wetness;
// Realistic painted-metal aircraft skin: triplanar camouflage, panel lines, wear and grime.
// No toon ramp and no inverted-hull outline - the aircraft are painted, not cel-shaded, so the models read
// like real machines against the terrain. Textures come from tools/make_aircraft_camo.py (procedural, so
// nothing is ripped from anywhere); no UVs are needed because everything is projected in object space.
uniform sampler2D camo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float camo_scale = 0.30;                 // object-metres -> texture tiles
uniform vec4 underside_color : source_color = vec4(0.58, 0.63, 0.66, 1.0);
uniform float under_amount : hint_range(0.0, 1.0) = 0.85;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.52;
uniform float metallic : hint_range(0.0, 1.0) = 0.22;
uniform float wear : hint_range(0.0, 1.0) = 0.6;          // panel lines, paint chipping, oil
uniform float gloss : hint_range(0.0, 1.0) = 0.0;          // extra sheen on the sunward side
uniform vec4 tint : source_color = vec4(1, 1, 1, 1);       // per-aircraft paint tweak
uniform float night_amount = 0.0;

varying vec3 o_p;
varying vec3 o_n;

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

void fragment() {
	vec3 n = o_n;
	vec3 an = abs(n);
	// triplanar camo: no UV unwrap needed, and the pattern never stretches over a wing
	float s = camo_scale;
	vec3 cx = texture(camo_tex, o_p.zy * s).rgb;
	vec3 cy = texture(camo_tex, o_p.xz * s).rgb;
	vec3 cz = texture(camo_tex, o_p.xy * s).rgb;
	vec3 col = (cx * an.x + cy * an.y + cz * an.z) / max(an.x + an.y + an.z, 1e-3);
	col *= tint.rgb;

	// underside paint on everything facing down (the `under` tone used by the toon shader)
	float down = smoothstep(0.05, 0.75, -n.y);
	col = mix(col, underside_color.rgb * tint.rgb, down * under_amount);

	// panel lines and rivet rows: object space, so they stay the same size on every aircraft
	float pl = abs(fract(o_p.y * 1.45 + o_p.x * 0.06) - 0.5) * 2.0;
	float rib = abs(fract(o_p.x * 2.1 + o_p.z * 0.5) - 0.5) * 2.0;
	float line = smoothstep(0.90, 0.99, pl) + smoothstep(0.94, 1.0, rib) * 0.6;
	line = clamp(line, 0.0, 1.0);
	col *= 1.0 - line * 0.30 * wear;

	// grime: heavy under the belly and aft of the exhausts, streaked along the airflow
	float grime = vnoise2(vec2(o_p.y * 2.6, o_p.x * 9.0)) * 0.6 + vnoise2(vec2(o_p.y * 0.7, o_p.z * 7.0)) * 0.4;
	float belly = smoothstep(0.0, 1.0, -n.y) * 0.7 + smoothstep(1.0, 4.5, o_p.x) * 0.5;
	col *= 1.0 - clamp(grime * belly, 0.0, 1.0) * 0.22 * wear;

	// paint chipping to bare metal: broad worn patches (a high-frequency noise here reads as white speckle
	// all over the airframe, which looks like a corrupted texture)
	float chip = smoothstep(0.72, 0.92, vnoise2(o_p.xz * 1.7 + o_p.y * 0.9));
	chip *= smoothstep(0.15, 0.85, line) * wear;
	col = mix(col, vec3(0.52, 0.53, 0.51), clamp(chip, 0.0, 1.0) * 0.30);

	// riveted skin: a grid of rivet heads on whichever plane the surface faces (about 12 cm apart), sunk panel
	// seams between sheets of varying size, and slightly lighter sheets here and there where panels were
	// replaced or repainted. All in object metres so every aircraft gets the same scale of detail.
	vec2 rp = (an.y > an.x && an.y > an.z) ? o_p.xz : ((an.x > an.z) ? o_p.zy : o_p.xy);
	vec2 rc = fract(rp / 0.12) - 0.5;
	float rivet = 1.0 - smoothstep(0.07, 0.15, length(rc));
	vec2 sheet = floor(rp / vec2(0.9, 0.55));
	float sheet_h = hash12(sheet);
	vec2 sf = abs(fract(rp / vec2(0.9, 0.55)) - 0.5);
	float seam = smoothstep(0.485, 0.5, max(sf.x, sf.y));
	col *= 1.0 - seam * 0.20 * wear;
	col *= 1.0 + (sheet_h - 0.5) * 0.10 * wear;
	col *= 1.0 - rivet * 0.07 * wear;
	// sun-bleached upper surfaces, worn bare metal on forward-facing edges, oily streaks running aft
	float up = smoothstep(0.35, 0.95, n.y);
	col = mix(col, col * 1.16 + vec3(0.015), up * 0.35 * wear);
	float lead = smoothstep(0.55, 0.95, -n.z) * smoothstep(0.35, 0.8, vnoise2(o_p.xy * 9.0 + o_p.z));
	col = mix(col, vec3(0.55, 0.56, 0.54), lead * 0.38 * wear);
	float streak = vnoise2(vec2(o_p.x * 14.0, o_p.z * 0.9)) * smoothstep(0.3, 0.9, vnoise2(vec2(o_p.x * 3.0, o_p.z * 0.4)));
	col *= 1.0 - streak * 0.14 * wear * (1.0 - up * 0.5);

	// micro-relief: rivets, seams and dents break the specular up so the skin stops looking like painted
	// plastic under a flat light
	float micro = (vnoise2(o_p.xy * 6.0) - 0.5) + (vnoise2(o_p.zy * 6.0) - 0.5);
	NORMAL = normalize(NORMAL + vec3(micro * 0.022 * wear) + n * (rivet * 0.10 - seam * 0.16) * wear);

	// rain: a water film darkens the paint a touch and makes it glossy (wetness from WeatherManager)
	col *= 1.0 - 0.18 * wetness;
	ALBEDO = col;
	ROUGHNESS = clamp(base_roughness + grime * 0.30 - gloss * 0.15 + line * 0.10 - 0.45 * wetness, 0.05, 1.0);
	METALLIC = metallic * (1.0 - chip * 0.5);
	SPECULAR = 0.5 + gloss * 0.3;
}
