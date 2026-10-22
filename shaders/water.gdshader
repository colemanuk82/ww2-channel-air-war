shader_type spatial;
// ambient_light_disabled: the engine's sky ambient + radiance reflection were stacking on top of the shader's own
// Fresnel reflection and lifting the whole sea to a pale silver; the shader supplies both itself (EMISSION).
render_mode depth_draw_never, ambient_light_disabled, cull_disabled;

#include "res://shaders/toon_common.gdshaderinc"

// Sea (v6.7). Still the stylised family (depth bands, foam, surf lines) but lit like water: a dark body colour,
// the sky reflected by a Fresnel term (pale at grazing angles toward the horizon, dark and clear looking down),
// sun and moon glitter on the wave facets (the moon lays a shimmering path across the water at night), small
// wind-streaked whitecaps instead of round blobs, fine ripples near the camera, drifting cloud shadows that match
// the terrain's, and ship wakes from the `wake_*` globals fed by GroundShip.
// The old sea read white-blue and flat: its albedo was 0.3-0.4 and lit by a 0.35 floor + toon band, so in noon
// sun it was a bright matte plane, and the fog then washed it to the horizon colour.
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 shallow_color : source_color = vec3(0.10, 0.24, 0.21);
uniform vec3 mid_color : source_color = vec3(0.055, 0.145, 0.16);
uniform vec3 deep_color : source_color = vec3(0.035, 0.095, 0.125);   // Channel grey-green, not ocean blue
uniform vec3 foam_color : source_color = vec3(0.90, 0.94, 0.95);
uniform float depth_fade = 70.0;
uniform float foam_depth = 5.0;
uniform float bands = 4.0;
uniform float wave_scale = 0.013;
uniform float scroll_speed = 0.05;
uniform float reflect_strength = 1.0;
uniform float lake_mode = 0.0;       // 1 = inland reservoir (DamKit): calm water, no depth bands / shore foam / caps

global uniform vec3 sky_top;
global uniform vec3 sky_horizon;
global uniform float cloud_shadow;
global uniform float night_amount;
global uniform float water_debug;   // 1 = show the depth difference (red) / 2 = force opaque (A/B, set by WW2_WATER_DEBUG)
global uniform vec4 wake_0;      // xz = ship position, z = heading (rad), w = length (0 = unused)
global uniform vec4 wake_1;
global uniform vec4 wake_2;
global uniform vec4 wake_3;

varying vec3 w_pos;
varying float v_shadow;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float fbm2(vec2 p) {
	return t_vnoise2(p) * 0.6 + t_vnoise2(p * 2.1 + 7.3) * 0.3 + t_vnoise2(p * 4.3 + 1.7) * 0.1;
}

float wave_h(vec2 p, float t) {
	float h = 0.0;
	// regional amplitude envelope: the swell builds and fades across the sea so the crests never form a lattice
	float env = 0.55 + 0.9 * t_vnoise2(p * 0.0021 + vec2(t * 0.01, 0.0));
	h += sin(dot(p, vec2(1.0, 0.35)) * 0.045 + t * 1.10) * 1.00;
	h += sin(dot(p, vec2(-0.40, 1.0)) * 0.072 + t * 0.75) * 0.50;
	h += sin(dot(p, vec2(0.75, -0.65)) * 0.115 + t * 1.45) * 0.22;
	h *= env;
	h += (t_vnoise2(p * 0.012 + t * 0.06) - 0.5) * 0.75;
	return h;
}

// Short crossing wave trains for chop and ripples. Analytic sines on purpose: the gradient of value noise is
// discontinuous at its lattice cells, which drew a square grid into the sun glitter (the old "dash grid").
vec2 chop_grad(vec2 p, float t, float k) {
	vec2 g = vec2(0.0);
	vec2 d0 = vec2(0.94, 0.34);
	vec2 d1 = vec2(0.17, 0.98);
	vec2 d2 = vec2(-0.71, 0.70);
	vec2 d3 = vec2(0.56, -0.83);
	vec2 d4 = vec2(-0.96, -0.28);
	g += d0 * cos(dot(p, d0) * 0.21 * k + t * 1.9) * 0.21 * k * 0.30;
	g += d1 * cos(dot(p, d1) * 0.33 * k + t * 2.3 + 1.3) * 0.33 * k * 0.20;
	g += d2 * cos(dot(p, d2) * 0.47 * k + t * 2.9 + 2.1) * 0.47 * k * 0.13;
	g += d3 * cos(dot(p, d3) * 0.71 * k + t * 3.4 + 0.7) * 0.71 * k * 0.08;
	g += d4 * cos(dot(p, d4) * 1.03 * k + t * 4.1 + 4.2) * 1.03 * k * 0.05;
	return g;
}

// V-shaped wake behind one ship: returns foam amount and a turbulence value.
float wake_one(vec2 p, vec4 w) {
	if (w.w <= 0.0) return 0.0;
	vec2 fwd = vec2(sin(w.z), -cos(w.z));
	vec2 d = p - w.xy;
	float back = -dot(d, fwd);            // distance astern
	float side = abs(d.x * fwd.y - d.y * fwd.x);
	if (back < -w.w * 0.5 || back > w.w * 14.0) return 0.0;
	float bk = max(back, 0.0);
	// turbulent centre track, widening and fading astern
	float track = (1.0 - smoothstep(w.w * 0.12 + bk * 0.035, w.w * 0.22 + bk * 0.06, side)) * (1.0 - smoothstep(w.w * 2.0, w.w * 9.0, bk));
	// Kelvin arms at ~19.5 degrees
	float arm = abs(side - bk * 0.354);
	float arms = (1.0 - smoothstep(0.0, 2.5 + bk * 0.02, arm)) * (1.0 - smoothstep(w.w * 3.0, w.w * 14.0, bk)) * step(0.0, back);
	// bow wave
	float bow = (1.0 - smoothstep(0.0, w.w * 0.18, length(d - fwd * w.w * 0.5))) * 0.8;
	float broken = t_vnoise2(p * 0.25 + TIME * 0.4);
	return clamp(track * (0.55 + 0.45 * broken) + arms * 0.55 * (0.6 + 0.4 * broken) + bow, 0.0, 1.0);
}

void fragment() {
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float scene_depth = -view.z;
	float diff = max(scene_depth + VERTEX.z, 0.0);

	diff = mix(diff, 200.0, lake_mode);      // lakes sit on their own DEM: no depth read, treat as deep water
	float ratio = clamp(diff / depth_fade, 0.0, 1.0);
	// smooth depth tint (the old 4 hard toon bands drew straight colour steps across the sea where the seabed
	// mesh changes LOD between terrain chunks)
	float banded = smoothstep(0.0, 1.0, ratio);
	vec3 col = mix(shallow_color, mid_color, smoothstep(0.0, 0.5, banded));
	col = mix(col, deep_color, smoothstep(0.4, 1.0, banded));

	vec2 wp = w_pos.xz;
	float tw = TIME * 0.5;
	float e = 1.6;
	float dist = length(w_pos - CAMERA_POSITION_WORLD);
	float wfade = 1.0 - smoothstep(500.0, 4200.0, dist);
	float rfade = 1.0 - smoothstep(60.0, 700.0, dist);
	float h0 = wave_h(wp, tw);
	float hx = wave_h(wp + vec2(e, 0.0), tw);
	float hz = wave_h(wp + vec2(0.0, e), tw);
	vec2 g = vec2(hx - h0, hz - h0) / e * 1.5 * wfade * (1.0 - 0.75 * lake_mode);
	// mid-scale chop: irregular facets so the swell never reads as a regular sine lattice
	float mfade = 1.0 - smoothstep(300.0, 2600.0, dist);
	if (mfade > 0.0) {
		// chop strength varies smoothly across the sea so it never reads as a uniform texture
		float cenv = 0.6 + 0.8 * t_vnoise2(wp * 0.004 + 17.0);
		g += chop_grad(wp, TIME, 1.0) * 0.55 * mfade * cenv;
	}
	if (rfade > 0.0) {
		g += chop_grad(wp.yx * 1.3 + 50.0, TIME * 1.6, 3.2) * 0.12 * rfade;
	}
	// far away the facets average out: a gentle residual slope keeps a soft sheen instead of a mirror line
	g += (vec2(t_vnoise2(wp * 0.004 + tw * 0.02), t_vnoise2(wp * 0.004 + 9.0 - tw * 0.02)) - 0.5) * 0.10 * (1.0 - wfade);
	vec3 wn = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(wn, 0.0)).xyz, 0.92));

	col *= 1.0 + (0.14 * clamp(h0 * 0.5 + 0.5, 0.0, 1.0) - 0.07) * wfade;

	// drifting cloud shadows (same field as terrain.gdshader so they run on across the coast)
	vec2 cp = wp * 0.0006 + vec2(TIME * 0.005, TIME * 0.003);
	float cn = t_vnoise2(cp) * 0.65 + t_vnoise2(cp * 2.3 + 5.0) * 0.35;
	float lo = 0.66 - 0.25 * cloud_shadow;
	float shade = smoothstep(lo, lo + 0.15, cn) * min(cloud_shadow * 1.7, 1.0) * step(0.01, cloud_shadow);
	v_shadow = shade;

	// --- foam ---
	float n1 = fbm2(wp * wave_scale + vec2(tw * 0.05, tw * 0.03));
	float patch = smoothstep(0.55, 0.88, t_vnoise2(wp * 0.0045 + tw * 0.012));
	// whitecaps: short streaks stretched down-wind, small and scattered, only on the higher crests
	vec2 wq = vec2(dot(wp, vec2(0.94, 0.33)), dot(wp, vec2(-0.33, 0.94)));
	float cap_n = t_vnoise2(wq * vec2(0.035, 0.11) + vec2(tw * 0.2, 0.0));
	float crest = smoothstep(0.78, 0.90, cap_n) * smoothstep(0.55, 1.15, h0) * wfade * patch;
	// foam streaks: long thin wind lanes (the old round fbm blobs read as ice floes)
	float lane = t_vnoise2(wq * vec2(0.010, 0.09) + vec2(tw * 0.05, 0.0)) * 0.7 + t_vnoise2(wq * vec2(0.03, 0.2) + 5.0) * 0.3;
	float streak = smoothstep(0.80, 0.93, lane) * smoothstep(0.40, 0.95, h0) * wfade * patch;
	float near = 1.0 - smoothstep(foam_depth * 0.3, foam_depth * 1.2, diff);
	float rings = step(0.35, sin(diff * 0.9 - TIME * 1.1 + n1 * 5.0) * 0.5 + 0.5);
	// shallows: lacy, broken foam rather than solid white (sandbanks in the DEM used to show as hard white blobs)
	float lacy = smoothstep(0.35, 0.75, t_vnoise2(wp * 0.12 + TIME * 0.05) * 0.7 + n1 * 0.3);
	float shore = near * mix(0.6, 1.0, rings) * mix(0.35, 1.0, lacy);
	float edge = (1.0 - smoothstep(0.0, foam_depth * 0.45, diff)) * mix(0.5, 1.0, lacy);
	// surf: wide bands of broken swell rolling in over the shallows, with lacy backwash between them
	float surf_zone = (1.0 - smoothstep(foam_depth * 1.6, foam_depth * 6.0, diff)) * smoothstep(foam_depth * 0.4, foam_depth * 1.0, diff);
	float surf_ph = diff * 0.38 + TIME * 0.55 + n1 * 3.2 + t_vnoise2(wp * 0.06) * 0.6;
	float surf_line = smoothstep(0.86, 0.97, sin(surf_ph) * 0.5 + 0.5) * smoothstep(0.25, 0.60, t_vnoise2(wp * 0.035 + TIME * 0.05));
	float lace = smoothstep(0.62, 0.80, t_vnoise2(wp * 0.22 + TIME * 0.08)) * (1.0 - smoothstep(foam_depth * 0.8, foam_depth * 3.0, diff)) * 0.6;
	float surf = surf_line * surf_zone + lace;
	float wake = max(max(wake_one(wp, wake_0), wake_one(wp, wake_1)), max(wake_one(wp, wake_2), wake_one(wp, wake_3)));
	float foam = clamp(shore + edge + crest * 0.9 + streak * 0.4 + surf * 0.9 + wake * 0.9, 0.0, 1.0) * (1.0 - lake_mode);
	float foam_m = smoothstep(0.30, 0.62, foam);

	// --- sky reflection (Fresnel) ---
	vec3 vw = normalize(CAMERA_POSITION_WORLD - w_pos);
	vec3 rw = reflect(-vw, wn);
	float cos_t = clamp(dot(wn, vw), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - cos_t, 5.0);
	fres = clamp(fres, 0.0, 0.55);
	// the sea never mirrors the pale horizon fully: tint the reflection with the water colour and lean on the
	// deeper sky colour, otherwise the whole sea goes silver-white at low level
	vec3 sky = mix(sky_horizon, sky_top, smoothstep(0.0, 0.22, max(rw.y, 0.0)));
	sky = mix(sky, sky * (col * 2.2 + 0.25), 0.45) * 0.8;
	vec3 refl = sky * fres * reflect_strength * (1.0 - 0.45 * shade) * (1.0 - foam_m);

	col *= 1.0 - 0.30 * shade;
	vec3 base = mix(col, foam_color, foam_m);
	ALBEDO = base;
	// own ambient: the body colour lit by the sky (dark at night), plus the reflection
	vec3 amb = mix(sky_horizon, sky_top, 0.6) * (1.0 - 0.35 * shade);
	EMISSION = base * amb * 0.85 + refl;
	ROUGHNESS = mix(0.18, 0.85, foam_m);
	SPECULAR = 0.0;
	ALPHA = clamp(0.35 + smoothstep(0.0, foam_depth * 1.5, diff) * 0.65 + foam * 0.5, 0.0, 1.0);
	if (water_debug > 0.5 && water_debug < 1.5) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(clamp(diff / 150.0, 0.0, 1.0), clamp(scene_depth / 3000.0, 0.0, 1.0), clamp(-VERTEX.z / 3000.0, 0.0, 1.0));
		ALPHA = 1.0;
	} else if (water_debug > 1.5) {
		ALPHA = 1.0;
	}
}

void light() {
	float t = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	DIFFUSE_LIGHT += (0.30 + toon_band(t) * 0.55) * LIGHT_COLOR / PI;
	vec3 hv = normalize(LIGHT + VIEW);
	float nh = clamp(dot(NORMAL, hv), 0.0, 1.0);
	float sh = 1.0 - 0.8 * v_shadow;
	// sharp glints (above 1.0 so the bloom pass makes them sparkle) and a broad soft sheen: the sheen is
	// what draws the long glitter path toward a low sun, and toward the moon at night
	float glint = smoothstep(0.25, 0.85, pow(nh, 300.0)) * 1.4;   // soft-edged: a hard step aliased into square sparkles
	float sheen = pow(nh, 48.0) * 0.28;
	float boost = 1.0 + 0.9 * night_amount;      // the moon is dim: give its path more weight
	SPECULAR_LIGHT += (glint + sheen * boost) * LIGHT_COLOR * ATTENUATION * sh;
}
