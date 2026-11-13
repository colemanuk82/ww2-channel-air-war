#include "res://shaders/toon_common.gdshaderinc"

// Reusable toon shader: stepped light ramp, rim light, two-tone (underside) and camo patches.
uniform vec4 albedo : source_color = vec4(0.7, 0.7, 0.7, 1.0);
// Buildings (flat-shaded, detail_mode 1) are graded down a shade so the dense wartime housing stock reads
// as darker built-up mass against the fields instead of glowing pale. Applies to every flat-shaded pass,
// i.e. the buildings, and to nothing else.
const float BUILDING_DARKEN = 0.62;
uniform vec4 underside_color : source_color = vec4(0.7, 0.7, 0.7, 1.0);
uniform float underside_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 patch_color : source_color = vec4(0.4, 0.3, 0.2, 1.0);
uniform float patch_amount : hint_range(0.0, 1.0) = 0.0;
uniform float patch_scale = 0.5;
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.25;
uniform float rim_power = 3.0;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform sampler2D ramp_tex : source_color, filter_linear, repeat_disable;
uniform bool use_ramp_tex = false;
uniform float gloss : hint_range(0.0, 1.0) = 0.0;   // painted-metal sheen: a stepped highlight band on the lit side
uniform float softness : hint_range(0.0, 1.0) = 0.0; // 1 = smooth shading (foliage, like the menu paintings), 0 = hard steps
uniform float flat_shade : hint_range(0.0, 1.0) = 0.0; // 1 = solid colour: no shadow, no toon banding (buildings)

// World-space procedural detail (no texture files): 0 none, 1 building (roof tiles + windows),
// 2 asphalt (grain, cracks, stains, rubber), 3 foliage (leaf clumps), 4 mown grass.
uniform int detail_mode = 0;
uniform bool use_vcol = false;   // albedo x vertex colour (merged multi-colour meshes: one draw instead of one per part)
// 6 aged runway / taxiway (concrete bays, tar repairs, weathering, tyre rubber, crumbling grassy edges),
// 7 worn runway paint. Runway and paint boxes are unit boxes scaled to size (Airfield._add_box), so the strip's
// width and length are the model's own x / z scale (strip_wl) and obj_p * scale is the position in metres.
// (An instance uniform did the same job but every toon instance in the world then reserved a slot for it.)
global uniform float night_amount;     // 0 day .. 1 night (set by TimeOfDay): lights the windows
global uniform float raid_dim;         // 0..1 extra dimming of every town while a raid is on (RaidBlackout)
global uniform float raid_black_k;     // 0..1 full blackout over the raided town (fades back on)
global uniform vec3 raid_black_pos;    // centre of the raided town
global uniform float raid_black_r;     // radius of the raided town's built-up area
global uniform float blackout;         // 0 = windows lit as usual, 1 = wartime blackout (towns almost dark)
global uniform float wetness;          // 0..1 ground wetness (WeatherManager): wet grass/runways darken and sheen
global uniform float lamp_amount;      // 0..1 night / dusk activity: keeps active airfields and lit sites visible in blackout

varying vec3 obj_n;
varying vec3 obj_p;
varying vec2 strip_wl;
varying vec3 w_pos;
varying vec3 w_nrm;
varying vec3 inst_o;   // the instance's own origin: one id per house, so a roof or facade never splits into patches

void vertex() {
	obj_n = NORMAL;
	obj_p = VERTEX;
	strip_wl = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	inst_o = MODEL_MATRIX[3].xyz;
#ifdef NG_REAL
	// Wind sway for foliage (trees, hedges): a slow crown lean plus a quick leaf flutter, both growing with
	// height above the instance origin and phased per instance so a wood never moves in step. Faded out
	// past 1.5 km where it would only shimmer. The displacement is applied in world space and mapped back.
	if (detail_mode == 3) {
		vec3 org = MODEL_MATRIX[3].xyz;
		float cam_d = length(org - CAMERA_POSITION_WORLD);
		float fade = 1.0 - smoothstep(900.0, 1500.0, cam_d);
		if (fade > 0.0) {
			float h = clamp(w_pos.y - org.y, 0.0, 15.0);
			float hk = h / 15.0;
			vec2 cell = mod(floor(org.xz), 997.0);
			float ph = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453) * 6.2832;
			vec2 wdir = vec2(0.8, 0.6);
			float t = TIME;
			float lean = sin(t * 1.15 + ph) * 0.6 + sin(t * 0.73 + ph * 1.7) * 0.4;
			lean = (lean * 0.5 + 0.55) * 0.25 * hk * hk;
			vec3 lp = mod(w_pos, 97.0);
			float fl = sin(t * 7.3 + dot(lp, vec3(1.7, 2.3, 1.9)) + ph) * 0.04 * hk;
			vec3 off = vec3(wdir.x * lean, 0.0, wdir.y * lean) + vec3(fl * 0.6, fl * 0.5, -fl * 0.4);
			off *= fade;
			w_pos += off;
			mat3 inv_m = inverse(mat3(MODEL_MATRIX));
			VERTEX += inv_m * off;
		}
	}
#endif
	w_nrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

vec3 detail_building(vec3 col, inout float emit, float cam_dist) {
	// The fine roof-tile and window patterns alias badly on distant buildings (the shimmer seen at low
	// level over a town), so the PATTERN is faded out with range while the average tone is kept. The
	// coarse per-building tone never aliases, so it always applies (otherwise distant towns go uniform).
	float near_k = 1.0 - smoothstep(150.0, 900.0, cam_dist);
	vec3 n = normalize(w_nrm);
	col *= 0.9 + 0.2 * t_vnoise2(floor(w_pos.xz / 9.0) * 1.7);
#ifdef NG_REAL
	// Normandy and northern France (south of ~50.9 N, world z > -66 km): pale Caen limestone walls and
	// blue-grey slate roofs, against the red brick and clay tile of southern England.
	float fr = smoothstep(-70000.0, -62000.0, w_pos.z);
	// whole streets and quarters differ (older dark centres, newer pale suburbs), not just single houses
	float quarter = t_vnoise2(w_pos.xz * 0.006 + 7.0);
	col *= 0.80 + 0.40 * quarter;
	if (n.y > 0.35) {
		// Roofscape: every house its own roof - weathered terracotta, dark clay tile, Welsh slate, old brown tile
		// or lichen-stained - so a street reads as a real roofscape rather than uniform orange blocks.
		vec2 bid = floor(inst_o.xz * 0.5);
		float rh = t_hash12(bid + 5.3);
		float slate_share = mix(0.30, 0.72, fr) + (quarter - 0.5) * 0.4;
		vec3 rc = rh < slate_share ? mix(vec3(0.20, 0.21, 0.25), vec3(0.34, 0.35, 0.38), t_hash12(bid + 2.0))
			: (rh < slate_share + 0.22 ? vec3(0.52, 0.28, 0.19) : (rh < slate_share + 0.38 ? vec3(0.36, 0.20, 0.15)
			: (rh < 0.92 ? vec3(0.44, 0.35, 0.27) : vec3(0.40, 0.38, 0.29))));
		rc *= 0.70 + 0.60 * t_hash12(bid + 11.0);          // strong per-roof brightness steps, visible from the air
		col = mix(col, rc / BUILDING_DARKEN * 0.72, 0.85);
	} else {
		col = mix(col, vec3(dot(col, vec3(0.333))), 0.18);   // walls: brick and render a little less saturated
		vec3 stone = vec3(0.50, 0.46, 0.39) * (0.80 + 0.35 * t_hash12(floor(w_pos.xz / 8.0) + 31.0));   // weathered, sooty limestone
		col = mix(col, stone / BUILDING_DARKEN * 0.72, fr * 0.65);
		// Normandy facades are not all one limestone: whitewashed and ochre render, grey cement and sooty stone,
		// each house its own, so a street reads as a row of homes rather than one pale block
		float fh = t_hash12(floor(inst_o.xz * 0.5) + 53.0);
		vec3 fac = fh < 0.30 ? vec3(0.60, 0.56, 0.48) : (fh < 0.50 ? vec3(0.56, 0.47, 0.33) : (fh < 0.68 ? vec3(0.45, 0.45, 0.43) : (fh < 0.84 ? vec3(0.50, 0.44, 0.36) : vec3(0.38, 0.34, 0.29))));
		col = mix(col, fac / BUILDING_DARKEN * 0.72, fr * 0.75);
		// grounding: walls darken toward the street (the houses sit sunk into the ground, so the gradient runs the
		// whole height rather than a thin plinth band) and the eaves throw shade under the roof (unit-box houses
		// only: obj_p is the -0.5..0.5 model box)
		if (abs(obj_p.y) < 0.75 && abs(obj_p.x) < 0.75) {
			col *= mix(0.58, 1.0, smoothstep(-0.45, 0.30, obj_p.y));
			col *= 1.0 - 0.20 * smoothstep(0.34, 0.50, obj_p.y);
		}
	}
#endif
	// Distant towns are thousands of roofs only a pixel or two across: as the aircraft moves each pixel flips
	// between a dark slate roof and a red wall, which is the crawling shimmer over a town. Further out the roof
	// and wall tones are drawn together (to the street's average), so a flip between them barely shows.
	float far_k = smoothstep(500.0, 2600.0, cam_dist);
	vec3 town_avg = vec3(0.36, 0.29, 0.26);
#ifdef NG_REAL
	far_k *= 0.35;     // keep the per-roof variety further out (temporal AA / DLSS settle the shimmer)
#endif
	col = mix(col, mix(col, town_avg * (0.9 + 0.2 * t_vnoise2(floor(w_pos.xz / 9.0) * 1.7)), 0.6), far_k);
	if (near_k <= 0.001) {
		return col;
	}
	vec3 base = col;
	if (n.y > 0.35) {
		// roof: staggered tile courses + moss/stain noise. The course lines are faded out by how many of them
		// fall inside one pixel (screen-space derivative), so they vanish exactly where they would start to
		// alias - not at a fixed range, which left them crawling on oblique roofs nearer than that.
		vec2 tg = vec2(-n.z, n.x);
		float course = w_pos.y * 2.2;
		float row = floor(course);
		float u = dot(w_pos.xz, tg) * 1.1 + row * 0.5;
		float aa = 1.0 - smoothstep(0.18, 0.45, max(fwidth(course), fwidth(u)));
		float line_h = smoothstep(0.0, 0.14, fract(course));
		float line_v = smoothstep(0.0, 0.10, fract(u));
		float tiles = mix(0.85, 0.70 + 0.30 * line_h * line_v, aa);
		col *= mix(0.85, tiles, near_k);         // average roof tone preserved
		col *= mix(1.0, 0.88 + 0.24 * t_vnoise2(w_pos.xz * 0.7), near_k);
	} else if (abs(n.y) <= 0.35) {
		// walls: plain brick / render, no windows (owner's call - the window grid made towns look busy)
		vec2 tg = normalize(vec2(-n.z, n.x) + 1e-5);
		float u = dot(w_pos.xz, tg);
		// brick/render streaking and a dirty plinth
		col *= mix(1.0, 0.93 + 0.07 * t_vnoise2(vec2(u * 2.5, w_pos.y * 0.4)), near_k);
	}
	emit *= near_k;
	return mix(base, col, near_k);
}

vec3 detail_asphalt(vec3 col) {
	vec2 p = w_pos.xz;
	float grain = t_vnoise2(p * 1.9) * 0.5 + t_vnoise2(p * 6.3) * 0.5;
	col *= 0.86 + 0.28 * grain;
	col *= 0.90 + 0.20 * t_vnoise2(p * 0.045);
	float crack = abs(t_vnoise2(p * 0.33 + 4.0) - 0.5);
	col *= 1.0 - 0.28 * (1.0 - smoothstep(0.0, 0.018, crack));
	float oil = smoothstep(0.7, 0.85, t_vnoise2(p * 0.12 + 11.0));
	col = mix(col, col * 0.55, oil * 0.6);
	return col;
}

// Wartime runway, several winters old (detail_mode 6). obj_p is the strip's own box space: x across, z along.
vec3 detail_runway(vec3 col, float cam_d) {
	vec2 p = w_pos.xz;
	vec2 q = obj_p.xz * strip_wl;
	float near_k = 1.0 - smoothstep(250.0, 2200.0, cam_d);          // fine pattern fades with range (no shimmer)
	// broad weathering: bleached, dusty areas and darker damp ones, a little warm where the sun has baked it
	float blot = t_vnoise2(p * 0.028 + 7.0) * 0.6 + t_vnoise2(p * 0.085) * 0.4;
	col *= 0.78 + 0.40 * blot;
	col = mix(col, col * vec3(1.07, 1.04, 0.94), smoothstep(0.55, 0.8, blot) * 0.6);
	// concrete slabs poured at different times: each its own tone, a few patched with black tar, the edges
	// chipped, and grass growing in the joints between them
	vec2 bay = vec2(9.0, 10.8);           // bays at the world's ~1.45x scale
	vec2 bid = floor(q / bay);
	float slab_t = t_hash12(bid + 13.7);
	col *= 0.80 + 0.32 * slab_t;
	col = mix(col, col * vec3(1.03, 1.01, 0.95), step(0.7, t_hash12(bid + 2.2)) * 0.5);   // a few paler, newer slabs
	vec2 dj = (0.5 - abs(fract(q / bay) - 0.5)) * bay;          // distance to the nearest joint, each way
	float dmin = min(dj.x, dj.y);
	float wob = (t_vnoise2(p * 1.7) - 0.5) * 0.22;              // joints are not ruler-straight
	float tar = step(0.88, t_hash12(bid * 1.31 + 5.0));
	col = mix(col, vec3(0.14, 0.14, 0.15), tar * smoothstep(0.25, 0.9, dmin - t_vnoise2(p * 0.7) * 0.9) * 0.85);
	float chip = 1.0 - smoothstep(0.18, 0.55 + 0.35 * t_vnoise2(p * 0.9 + 6.0), dmin);
	col *= 1.0 - 0.16 * chip * near_k;                          // worn, darker slab edges
	float joint = 1.0 - smoothstep(0.06 + wob * 0.4, 0.20 + wob, dmin);
	// the joint itself: a dark tarred seam
	col *= 1.0 - 0.42 * joint * near_k;
	// grass in the joints: dark, dull greens and browns, in uneven runs, not in every joint
	vec3 grass = mix(vec3(0.13, 0.17, 0.07), vec3(0.22, 0.25, 0.11), t_vnoise2(p * 2.1 + 4.0));
	grass = mix(grass, vec3(0.27, 0.24, 0.14), step(0.70, t_vnoise2(p * 0.4 + 8.0)) * 0.7);   // dry, straw-coloured runs
	grass *= 0.72;                                              // the toon light lifts it: keep it a dull, dark green
	float growth = smoothstep(0.42, 0.68, t_vnoise2(p * 0.22 + 2.0) * 0.65 + t_vnoise2(p * 2.4) * 0.35);
	float gj = 1.0 - smoothstep(0.08, 0.28 + 0.25 * t_vnoise2(p * 3.3), dmin);       // ragged, wider where it is thick
	col = mix(col, grass, gj * growth * 0.9 * near_k);
	// grass spilling out of the joints in tufts here and there
	float tuft = (1.0 - smoothstep(0.2, 0.7, dmin)) * smoothstep(0.68, 0.86, t_vnoise2(p * 1.1 + 12.0));
	col = mix(col, grass, tuft * 0.8 * near_k);
	// grain and spalled pits
	float grain = t_vnoise2(p * 1.9) * 0.5 + t_vnoise2(p * 6.3) * 0.5;
	col *= 1.0 - 0.18 * near_k + 0.30 * grain * near_k;
	col *= 1.0 - 0.25 * step(0.86, t_vnoise2(p * 2.4 + 3.0)) * near_k;
	// cracks: meandering lines, mostly across the slabs
	// hairline cracks: thin, short, faint, only in some slabs
	float crack = abs(t_vnoise2(p * 1.1 + 4.0) - 0.5);
	float crack_on = step(0.55, t_hash12(bid + 41.0));
	col *= 1.0 - 0.22 * (1.0 - smoothstep(0.0, 0.006, crack)) * crack_on * near_k;
	// oil and fuel stains
	float oil = smoothstep(0.70, 0.86, t_vnoise2(p * 0.12 + 11.0));
	col = mix(col, col * 0.5, oil * 0.6);
	float half_w = strip_wl.x * 0.5;
	float len = strip_wl.y;
	if (half_w > 4.0 && len > 200.0) {
		// tyre rubber laid down in the touchdown zones, in streaks either side of the centreline
		float from_end = len * 0.5 - abs(q.y);
		float tdz = smoothstep(30.0, 90.0, from_end) * (1.0 - smoothstep(260.0, 520.0, from_end));
		float lane = 1.0 - smoothstep(half_w * 0.18, half_w * 0.48, abs(q.x));
		float streak = t_vnoise2(vec2(q.x * 1.6, q.y * 0.035) + 31.0);
		col = mix(col, vec3(0.08, 0.08, 0.085), tdz * lane * smoothstep(0.35, 0.75, streak) * 0.75);
		// crumbling edges with moss and grass growing through the cracks
		float edge = smoothstep(half_w - 3.5, half_w - 0.3, abs(q.x) + (t_vnoise2(p * 0.55) - 0.5) * 2.6);
		vec3 moss = mix(vec3(0.19, 0.22, 0.12), vec3(0.26, 0.28, 0.15), t_vnoise2(p * 1.3));
		col = mix(col, moss, edge * 0.75);
		// the joints near the edges are properly overgrown
		col = mix(col, moss * 0.95, joint * smoothstep(half_w * 0.45, half_w, abs(q.x)) * 0.8 * near_k);
	}
	return col;
}

// Worn runway paint (detail_mode 7): faded, flaked and scuffed through by tyres to the grey surface underneath.
vec3 detail_paint(vec3 col) {
	vec2 p = w_pos.xz;
	vec3 under = vec3(0.30, 0.30, 0.29) * (0.85 + 0.3 * t_vnoise2(p * 1.9));
	col = mix(col, col * vec3(0.95, 0.93, 0.84), 0.6);                      // aged off-white, a little yellowed
	col *= 0.86 + 0.18 * t_vnoise2(p * 0.6);
	float worn = t_vnoise2(p * 0.55 + 9.0) * 0.6 + t_vnoise2(p * 2.8) * 0.4;
	col = mix(col, under, smoothstep(0.50, 0.68, worn) * 0.9);            // flaked off in patches
	col = mix(col, under, 0.22);                                           // faded overall
	return col;
}

vec3 detail_foliage(vec3 col) {
	vec3 p = w_pos * 0.55;
	// layered canopy: broad masses, then twig-scale clusters, then individual leaves
	float clump = t_vnoise3(p * 1.6) * 0.5 + t_vnoise3(p * 4.1) * 0.3 + t_vnoise3(p * 9.5) * 0.2;
	col *= 0.58 + 0.66 * clump;
	// sun-side leaves lighter and warmer; the shaded interior cooler and deeper
	col = mix(col, col * vec3(1.22, 1.14, 0.76), smoothstep(0.55, 0.85, clump) * 0.55);
	col = mix(col, col * vec3(0.86, 0.98, 0.88), smoothstep(0.42, 0.18, clump) * 0.30);
	// individual leaves: fine speckle so the canopy never reads as one smooth blob
	float leaf = t_vnoise3(w_pos * 2.6);
	col *= 0.90 + 0.18 * step(0.60, leaf);
	return col;
}

// Aircraft skin (detail_mode 5): feathered camouflage edge is done in fragment(); here are panel lines, paint
// chipping to bare metal at edges and seams, oil / exhaust streaking and a little sun-fading on top surfaces.
vec3 detail_aircraft(vec3 col, inout float wear) {
	vec3 p = obj_p;
	vec3 n = normalize(obj_n);
	// panel lines: fuselage frames and longitudinal seams, thin and soft so they read without aliasing.
	// The spacing is jittered per panel so the skin never reads as a uniform grid.
	float jitter = (t_hash12(floor(vec2(p.z * 2.7, p.x * 2.4))) - 0.5) * 0.5;
	float frame = smoothstep(0.84, 0.90, abs(fract(p.z * 2.7 + jitter) - 0.5) * 2.0);
	float seam = smoothstep(0.87, 0.92, abs(fract(p.x * 2.4 - jitter) - 0.5) * 2.0);
	// rivet rows stippled along the frames and seams
	float ralong = smoothstep(0.55, 0.85, abs(fract(p.x * 22.0 + p.z * 4.0) - 0.5) * 2.0);
	float rivets = max(frame, seam) * ralong;
	float line = clamp(max(frame, seam * 0.7), 0.0, 1.0);
	col *= 1.0 - 0.20 * line - 0.08 * rivets;
	// access panels: occasional panels slightly different in tone
	vec2 pid = floor(vec2(p.z * 2.7, p.x * 2.4 + p.y * 2.4));
	col *= 0.94 + 0.10 * t_hash12(pid + 3.0);
	// chipped paint: bare aluminium showing along seams and in worn patches
	float chip_n = t_vnoise3(p * 9.0);
	float chips = smoothstep(0.82, 0.88, chip_n) * (0.25 + 0.75 * line);
	col = mix(col, vec3(0.58, 0.58, 0.56), chips * 0.45);
	wear = chips;
	// oil / exhaust streaks running back along the airflow (long thin noise), heavier below and aft
	float streak = t_vnoise3(vec3(p.x * 14.0, p.y * 14.0, p.z * 1.2));
	col *= 1.0 - 0.30 * smoothstep(0.50, 0.85, streak) * (0.5 + 0.5 * smoothstep(0.2, -0.6, n.y));
	// sun fading on upward-facing surfaces
	col = mix(col, col * 1.12 + 0.02, smoothstep(0.3, 0.9, n.y) * 0.35);
	return col;
}

// Flying kit (detail_mode 8 cloth, 9 leather, 10 skin): a handful of cheap noise taps on a few small meshes.
// Cloth: twill weave (faded with range so it never shimmers), soft folds, grime and seam darkening.
// Leather: fine grain, creases and scuffed, lighter worn edges. Skin: faint ruddy mottling.
vec3 detail_kit(vec3 col, int mode, float dist) {
	vec3 p = obj_p;
	float near_k = 1.0 - smoothstep(25.0, 70.0, dist);
	float folds = t_vnoise3(p * vec3(7.0, 16.0, 7.0));
	float fine = t_vnoise3(p * 55.0);
	if (mode == 8) {
		float twill = 0.5 + 0.5 * sin((p.x + p.y) * 210.0) * sin((p.y - p.z) * 190.0);
		col *= 1.0 - 0.10 * near_k * twill;
		col *= 0.86 + 0.28 * folds;
		col *= 1.0 - 0.18 * smoothstep(0.62, 0.9, t_vnoise3(p * 4.0 + 7.0));          // grease / grime patches
		col = mix(col, col * vec3(1.06, 1.02, 0.94), smoothstep(0.3, 0.9, obj_n.y) * 0.4);   // sun-faded shoulders
	} else if (mode == 9) {
		col *= 0.88 + 0.24 * fine * near_k + 0.10 * (1.0 - near_k);
		col *= 0.80 + 0.40 * smoothstep(0.35, 0.8, folds);                            // creases
		float scuff = smoothstep(0.70, 0.84, t_vnoise3(p * 11.0 + 3.0));
		col = mix(col, col * 1.55 + 0.04, scuff * 0.5);                               // rubbed-through, paler leather
	} else {
		col *= 0.93 + 0.14 * t_vnoise3(p * 14.0);
		col = mix(col, col * vec3(1.08, 0.92, 0.9), smoothstep(0.55, 0.85, t_vnoise3(p * 5.0)) * 0.5);
	}
	return col;
}

vec3 detail_grass(vec3 col) {
	vec2 p = w_pos.xz;
	float mow = step(0.5, fract(dot(p, vec2(0.7, 0.7)) / 38.0));
	col *= 0.93 + 0.07 * mow;
	col *= 0.84 + 0.30 * (t_vnoise2(p * 0.9) * 0.5 + t_vnoise2(p * 3.7) * 0.5);
	col *= 0.9 + 0.2 * t_vnoise2(p * 0.04);
	return col;
}

void fragment() {
	vec3 col = albedo.rgb;
	if (use_vcol) { col *= COLOR.rgb; }
	if (patch_amount > 0.0) {
		float n = t_vnoise3(obj_p * patch_scale) * 0.65 + t_vnoise3(obj_p * patch_scale * 2.3) * 0.35;
		float pe = (detail_mode == 5) ? smoothstep(0.52, 0.575, n) : step(0.55, n);   // aircraft: feathered, sprayed edge
		col = mix(col, patch_color.rgb, pe * patch_amount);
	}
	float win_emit = 0.0;
	if (detail_mode == 1) { col = detail_building(col, win_emit, length(w_pos - CAMERA_POSITION_WORLD)); }
	else if (detail_mode == 2) { col = detail_asphalt(col); }
	else if (detail_mode == 3) { col = detail_foliage(col); }
	else if (detail_mode == 4) { col = detail_grass(col); }
	else if (detail_mode == 5) { float wr = 0.0; col = detail_aircraft(col, wr); }
	else if (detail_mode == 6) { col = detail_runway(col, length(w_pos - CAMERA_POSITION_WORLD)); }
	else if (detail_mode >= 8) { col = detail_kit(col, detail_mode, length(w_pos - CAMERA_POSITION_WORLD)); }
	else if (detail_mode == 7) {
		// hand-painted and worn: ragged edges and flaked-off patches show the concrete underneath
		vec2 pq = obj_p.xz * strip_wl;
		vec2 ph = strip_wl * 0.5;
		if (ph.x > 0.01) {
			float ragged = (t_vnoise2(w_pos.xz * 2.2) - 0.5) * 0.30 + (t_vnoise2(w_pos.xz * 0.5 + 3.0) - 0.5) * 0.30;
			float to_edge = min(ph.x - abs(pq.x), ph.y - abs(pq.y));
			if (to_edge < 0.08 + ragged) { discard; }
			float flake = t_vnoise2(w_pos.xz * 0.45 + 9.0) * 0.55 + t_vnoise2(w_pos.xz * 1.6) * 0.30 + t_vnoise2(w_pos.xz * 5.0) * 0.15;
			if (flake > 0.70) { discard; }
		}
		col = detail_paint(col);
	}
	float under = smoothstep(-0.1, 0.25, -obj_n.y);
	col = mix(col, underside_color.rgb, under * underside_amount);
	if (detail_mode == 3) {
		// foliage recedes into the haze at long range only, so near and mid-range woods keep their colour
		float dcam = length(w_pos - CAMERA_POSITION_WORLD);
		col = mix(col, vec3(0.60, 0.68, 0.78), smoothstep(4000.0, 30000.0, dcam) * 0.35);
	}
	float wet_ground = 0.0;
	if (detail_mode == 2 || detail_mode == 4 || detail_mode == 6 || detail_mode == 7) {
		wet_ground = clamp(wetness, 0.0, 1.0);
		col *= mix(1.0, 0.62, wet_ground);   // wet concrete / tarmac goes much darker
	}
	ALBEDO = col * mix(1.0, BUILDING_DARKEN, flat_shade);
#ifdef NG_REAL
	if (detail_mode == 3) {
		// Leafy relief: a canopy is hundreds of leaf clusters, not a smooth ball. Bump the shading normal with
		// the same clump noise that colours it (screen-space derivative bump, no textures), so every crown
		// breaks into lit and shaded clusters under the sun. Faded with range so distant woods do not sparkle.
		float fd = length(w_pos - CAMERA_POSITION_WORLD);
		float fk = 1.0 - smoothstep(900.0, 4500.0, fd);
		if (fk > 0.001) {
			vec3 lp = w_pos * 0.55;
			float hb = (t_vnoise3(lp * 1.6) * 0.55 + t_vnoise3(lp * 4.1) * 0.30 + t_vnoise3(lp * 9.5) * 0.15 * (1.0 - smoothstep(150.0, 600.0, fd))) * 2.2 * fk;
			vec3 dpx = dFdx(VERTEX);
			vec3 dpy = dFdy(VERTEX);
			vec3 r1 = cross(dpy, NORMAL);
			vec3 r2 = cross(NORMAL, dpx);
			float det = dot(dpx, r1);
			vec3 sg = sign(det) * (dFdx(hb) * r1 + dFdy(hb) * r2);
			NORMAL = normalize(abs(det) * NORMAL - sg);
		}
		// self-occlusion: the inner, lower parts of a crown sit in their own shade
		AO = 0.55 + 0.45 * smoothstep(-0.6, 0.8, normalize(w_nrm).y);
		AO_LIGHT_AFFECT = 0.35;
	}
#endif
	ROUGHNESS = mix(1.0, 0.42, wet_ground);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	// Curved environment reflection: a soft studio-like sheen that follows the surface, so painted metal
	// reads as polished and rounded instead of flat. Bright toward grazing angles (Fresnel).
	vec3 rdir = reflect(-VIEW, normalize(NORMAL));
	float rup = clamp(rdir.y, -1.0, 1.0);
	vec3 env = mix(vec3(0.30, 0.34, 0.40), vec3(0.58, 0.68, 0.84), smoothstep(-0.4, 0.7, rup));
	env = mix(env, vec3(0.96, 0.97, 1.0), smoothstep(0.62, 1.0, rup) * 0.55);
	// the sheen is a reflection of the sky: at night there is (almost) no sky to reflect, so it fades with the
	// daylight. Without this the wet runway and taxiways glowed pale grey in the dark.
	env *= 1.0 - 0.94 * clamp(night_amount, 0.0, 1.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 refl = env * gloss * (0.10 + 0.9 * fres);
	refl += env * wet_ground * 0.22 * (0.15 + 0.85 * fres);
	// raid civil defence: windows go dark over the raided town and dim everywhere else while a raid is on
	float raid_loc = raid_black_k * (1.0 - smoothstep(raid_black_r * 0.5, raid_black_r * 1.05, length(w_pos.xz - raid_black_pos.xz)));
	float raid_out = 1.0 - clamp(max(raid_dim, raid_loc), 0.0, 1.0);
#ifdef NG_REAL
	rim *= 0.0;   // realistic: no cartoon rim light
#endif
	EMISSION = refl + rim_color.rgb * rim * rim_amount * 0.35 * (1.0 - 0.85 * clamp(night_amount, 0.0, 1.0)) + emission_color.rgb * emission_energy + vec3(1.0, 0.76, 0.38) * win_emit * night_amount * mix(1.4, 0.22, blackout) * raid_out;
}

void light() {
	// Buildings shade flat: a solid colour with no shadows and no toon banding, only a gentle top-light
	// term so roofs still read a shade brighter than walls. (ATTENUATION carries the shadow term, so
	// leaving it out is what removes the shadows.) Note: 'light' cannot 'return' early in Godot.
	if (flat_shade > 0.5) {
		// Buildings: real sun and shade. Sunlit walls and roofs take the full light, the walls facing away fall
		// to a soft shade, and cast shadows (ATTENUATION) from trees and neighbouring houses darken them, so a
		// town reads as solid blocks in the sun instead of flat colour. The floor stays high enough that the
		// dense terraces never go black.
		float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
		float lit = smoothstep(0.0, 0.75, nl) * mix(1.0, ATTENUATION, 0.85);
		// (scaled for the next-gen sun, which is 1.8x the old one: sunlit walls land about where the old flat tone was)
#ifdef NG_REAL
		// realistic: plain Lambert with the full cast shadow and a lower floor (the sky ambient fills the shade),
		// so walls turned from the sun and shadowed streets read as solid volumes rather than flat-coloured boxes
		lit = nl * ATTENUATION;
		DIFFUSE_LIGHT += (0.07 + 0.66 * lit + 0.05 * clamp(NORMAL.y, 0.0, 1.0)) * LIGHT_COLOR / PI;
#else
		DIFFUSE_LIGHT += (0.16 + 0.50 * lit + 0.04 * clamp(NORMAL.y, 0.0, 1.0)) * LIGHT_COLOR / PI;
#endif
	} else {
		float t = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
#ifdef NG_REAL
		// realistic: plain Lambert (foliage with a little wrap, as light passes round and through leaves) -
		// no toon steps and no lifted floor; the sky ambient fills the shade
		float wrap = (detail_mode == 3) ? 0.30 : 0.0;
		float shade = clamp((dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap), 0.0, 1.0) * ATTENUATION;
#else
		// foliage (and anything else with softness) shades smoothly instead of in hard toon steps
		float shade = mix(toon_band(t), 0.30 + 0.70 * smoothstep(0.05, 0.90, t), softness);
#endif
		if (detail_mode == 3) {
			// leaves glow warm when the sun is behind the canopy (translucency)
			float back = pow(clamp(dot(-VIEW, LIGHT), 0.0, 1.0), 2.0);
			DIFFUSE_LIGHT += vec3(0.52, 0.60, 0.24) * back * 0.30 * ATTENUATION;
		}
		if (gloss > 0.0) {
			vec3 hv = normalize(LIGHT + VIEW);
			float nh = clamp(dot(NORMAL, hv), 0.0, 1.0);
			shade += gloss * 1.6 * smoothstep(0.90, 0.935, nh) * ATTENUATION;      // hard-edged sun glint
		}
		if (use_ramp_tex) {
			shade = texture(ramp_tex, vec2(t, 0.5)).r;
		}
		DIFFUSE_LIGHT += shade * LIGHT_COLOR / PI;
	}
}
