shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/toon_common.gdshaderinc"

// ---------------------------------------------------------------------------------------------
// Realistic countryside terrain. No toon ramp, no cel bands: a continuous, procedurally mixed
// ground palette (pasture / rough grazing / arable in several crop states / heath / chalk /
// limestone / sand / marsh / rock) blended by height, slope, a large-scale district noise and a
// finer within-field noise. All colours and the farmland lattice are computed in the shader -
// no texture files are required. World units: y = elevation_m * 2, XZ = real metres (1:1).
//
// The farmland Voronoi lattice below is intentionally IDENTICAL to the original so that
// scripts/ground/scatter.gd :: field_edge() (which mirrors it) keeps placing hedges on the
// painted boundaries.
// ---------------------------------------------------------------------------------------------

// ---- Existing palette colours (preserved: names, types and defaults unchanged) ----
uniform vec3 grass_a : source_color = vec3(0.300, 0.350, 0.180);
uniform vec3 grass_b : source_color = vec3(0.375, 0.410, 0.215);
uniform vec3 field_brown : source_color = vec3(0.370, 0.280, 0.180);
uniform vec3 field_wheat : source_color = vec3(0.545, 0.475, 0.245);
uniform vec3 forest_col : source_color = vec3(0.17, 0.30, 0.15);
uniform vec3 hedge_col : source_color = vec3(0.15, 0.25, 0.13);
uniform vec3 upland_col : source_color = vec3(0.375, 0.365, 0.250);
uniform vec3 rock_col : source_color = vec3(0.42, 0.39, 0.35);
uniform vec3 chalk_col : source_color = vec3(0.93, 0.92, 0.86);
uniform vec3 sand_col : source_color = vec3(0.80, 0.73, 0.52);
uniform vec3 seabed_col : source_color = vec3(0.55, 0.58, 0.50);
uniform vec3 heath_col : source_color = vec3(0.40, 0.33, 0.30);
uniform vec3 heather_col : source_color = vec3(0.44, 0.34, 0.38);
uniform vec3 meadow_col : source_color = vec3(0.430, 0.455, 0.240);
uniform vec3 rape_col : source_color = vec3(0.600, 0.545, 0.200);
uniform vec3 marsh_col : source_color = vec3(0.30, 0.38, 0.24);
uniform vec3 river_col : source_color = vec3(0.20, 0.32, 0.36);
uniform vec3 mud_col : source_color = vec3(0.36, 0.30, 0.22);
uniform float field_cell = 190.0;   // average field ~190 m across (~4 ha, a typical 1940s English field); scatter.gd FIELD_CELL must match
// xyz = world x, z, radius. radius 0 disables.
uniform vec4 chalk_a = vec4(0.0);
uniform vec4 chalk_b = vec4(0.0);
uniform vec4 chalk_c = vec4(0.0);
uniform vec4 chalk_d = vec4(0.0);
uniform vec4 chalk_e = vec4(0.0);
// Real imagery draped over the terrain. map_rect = (min_world_x, min_world_z, 1/size_x, 1/size_z).
uniform sampler2D map_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 map_rect = vec4(0.0, 0.0, 0.0, 0.0);
uniform bool use_map = false;
uniform float map_amount : hint_range(0.0, 1.0) = 0.72;
// Built-up land (ESA WorldCover class 50) on the same rect as map_tex: towns get paved ground.
uniform sampler2D urban_tex : filter_linear, repeat_disable;
// Farming regions (data/heightmap/region_types.png, same rect as map_tex): R bocage, G open field / downland,
// B polder / fen, A Weald. Hard 0.5 thresholds; Scatter.field_edge() (RegionMap) mirrors them for the hedges.
uniform sampler2D region_tex : filter_linear, repeat_disable;
uniform bool use_regions = false;
// Seasons (EraClock month): the crop cycle centre (-1 = off: every field at its own stage) and a tint on the farmland.
uniform float season_center = -1.0;
uniform vec3 season_tint = vec3(1.0);
uniform bool use_urban = false;
uniform sampler2D wood_tex : filter_linear, repeat_disable;   // ESA WorldCover tree cover (R), same rect as map_tex
uniform bool use_wood = false;
uniform sampler2D sea_tex : filter_linear, repeat_disable;   // distance to the sea (R = metres / SEA_MAX_M), same rect as map_tex
uniform bool use_sea = false;
// Desert map (no imagery mosaic): the shader paints sand, limestone, rock and scrub itself (desert_ground below).
uniform bool desert_look = false;
uniform float desert_origin_lat = 33.75;
uniform float desert_origin_lon = 19.25;
uniform float desert_upl_lat = 111000.0;   // metres per degree latitude / longitude (HORIZ_COMPRESSION 1)
uniform float desert_upl_lon = 90000.0;
uniform sampler2D dune_tex : filter_linear, repeat_disable;   // dune-region mask (R), same rect as map_rect; baked by build/dune_mask_gen.gd
uniform bool use_dune = false;
uniform bool desert_v2 = true;                                  // false (--desert-v1): the pre-v2 look, for perf A/B
uniform vec3 desert_sun_dir = vec3(0.3, 0.85, 0.3);           // direction TOWARDS the sun (TimeOfDay.sun_dir)
// Desert land-cover classes (data/desert/region_landcover.bin: one byte per ~300 m cell, same rect as map_rect) and the
// class id -> albedo table (128 x 1, built in TerrainChunkManager._apply_desert). Sampled with a noise-warped, dithered
// bilinear blend of the four nearest cells, so class borders are soft and ragged rather than 300 m squares.
uniform sampler2D lc_tex : filter_nearest, repeat_disable;
uniform sampler2D lc_lut : filter_nearest, repeat_disable;
uniform bool use_lc = false;
uniform vec2 lc_size = vec2(7000.0, 2770.0);
const float SEA_MAX_M = 3000.0;
uniform vec3 tarmac_col : source_color = vec3(0.26, 0.26, 0.25);
uniform vec3 paving_col : source_color = vec3(0.37, 0.34, 0.31);

// Airfield grass: oriented, soft-edged rectangles tinted onto the terrain (no slab, no hard edge).
// af_a = (x, z, dir.x, dir.z) of the runway direction, af_b = (half along, half across, softness, active).
uniform vec4 af_a[32];
uniform vec4 af_b[32];
// Which of the 32 zone slots can reach each 1 km cell (bit i = slot i, packed in RGBA8), in a 256 km window around
// the player, built by terrain_chunk_manager.gd: most of the ground touches no zone and skips the loop entirely.
uniform sampler2D zone_tex : filter_nearest, repeat_disable;
uniform vec4 zone_rect = vec4(0.0, 0.0, 0.001, 0.0);   // origin x, origin z, 1 / cell size, cells across

// ---- New palette / tuning uniforms (sensible defaults; scripts do not touch these) ----
uniform vec3 soil_col : source_color = vec3(0.300, 0.220, 0.140);       // bare ploughed earth
uniform vec3 crop_young_col : source_color = vec3(0.260, 0.400, 0.150); // young green crop
uniform vec3 stubble_col : source_color = vec3(0.560, 0.500, 0.340);    // harvested straw
uniform vec3 moor_col : source_color = vec3(0.310, 0.300, 0.180);       // rough upland grazing
uniform vec3 peat_col : source_color = vec3(0.190, 0.150, 0.120);       // peat / bare moor soil
uniform vec3 limestone_col : source_color = vec3(0.800, 0.790, 0.720);  // lime-rich rock / soil
uniform float ground_roughness : hint_range(0.0, 1.0) = 0.9;
uniform float rock_slope : hint_range(0.10, 0.95) = 0.55;     // slope where rock takes over
uniform float field_variation : hint_range(0.0, 1.0) = 1.0;   // 0 = one uniform sward, 1 = full patchwork
uniform float pasture_bias : hint_range(0.0, 0.40) = 0.12;    // more open grass / pasture among the arable fields
uniform float detail_strength : hint_range(0.0, 2.0) = 1.0;   // within-field micro texture
uniform float ao_strength : hint_range(0.0, 1.0) = 0.35;      // hollow / valley darkening
uniform float grass_translucency : hint_range(0.0, 1.0) = 0.35; // grazing-angle leaf translucency

// Cloud cover 0..1 (set by CloudField): drifting soft shadow patches on the ground.
global uniform float cloud_shadow;
// Ground wetness 0..1 (set by WeatherManager while it rains): darker, richer, slightly glossy-looking ground.
global uniform float wetness;
// Real river geometry loaded (set to 1 by RiverMesh.ensure_loaded() when data/osm/rivers.json is present):
// retires the painted rivers below so paint and geometry never fight. 0 = painted rivers remain.
global uniform float real_rivers;

varying vec3 w_pos;
varying vec3 w_normal;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

float chalk_w(vec4 z, vec2 p) {
	if (z.z <= 0.0) { return 0.0; }
	float d = length(p - z.xy);
	return 1.0 - smoothstep(z.z * 0.7, z.z, d);
}

// Continuous arable crop cycle for one field: plough -> sow -> grow -> ripen -> harvest.
vec3 arable_stage(vec3 soil, vec3 fallow, vec3 young, vec3 ripe, vec3 stub, float s) {
	if (s < 0.18) { return soil; }
	if (s < 0.34) { return mix(soil, fallow, smoothstep(0.18, 0.34, s)); }
	if (s < 0.52) { return mix(fallow, young, smoothstep(0.34, 0.52, s)); }
	if (s < 0.70) { return mix(young, ripe * 0.88, smoothstep(0.52, 0.70, s)); }
	if (s < 0.86) { return mix(ripe * 0.88, ripe, smoothstep(0.70, 0.86, s)); }
	return mix(ripe, stub, smoothstep(0.86, 1.0, s));
}

float lc_wsum(ivec4 ids, vec4 ws, int id) {
	return float(ids.x == id) * ws.x + float(ids.y == id) * ws.y + float(ids.z == id) * ws.z + float(ids.w == id) * ws.w;
}

// Class lookup for the desert ground: returns the land-weighted blend of the four nearest cells' table colours in rgb
// and the land share (class 0 = sea is excluded) in a. ids / ws let the caller ask for the share of one class.
vec4 lc_sample(vec2 xz, float cdist, out ivec4 ids, out vec4 ws) {
	float wa = 1.0 - smoothstep(7000.0, 22000.0, cdist);
	vec2 n1 = vec2(t_vnoise2(xz * 0.006 + 3.1), t_vnoise2(xz * 0.006 + 41.7)) - 0.5;
	vec2 n2 = vec2(t_vnoise2(xz * 0.03 + 9.3), t_vnoise2(xz * 0.03 + 77.1)) - 0.5;
	vec2 wxz = xz + (n1 * 300.0 + n2 * 80.0) * wa;
	vec2 uv = (wxz - map_rect.xy) * map_rect.zw;
	float st = exp2(floor(log2(max(cdist / 14000.0, 1.0))));       // far away: a coarser grid, no per-cell shimmer
	vec2 g = uv * lc_size / st - 0.5;
	vec2 i0 = floor(g);
	vec2 f = g - i0;
	vec2 dn = vec2(t_vnoise2(xz * 0.09 + 5.0), t_vnoise2(xz * 0.09 + 19.0)) - 0.5;
	f = clamp(f + dn * 0.6 * wa, 0.0, 1.0);
	f = f * f * (3.0 - 2.0 * f);
	vec2 mx = floor(lc_size / st) - 1.0;
	vec2 a0 = clamp(i0, vec2(0.0), mx);
	vec2 a1 = clamp(i0 + 1.0, vec2(0.0), mx);
	ivec2 p00 = ivec2(floor(vec2(a0.x, a0.y) * st + 0.5 * st));
	ivec2 p10 = ivec2(floor(vec2(a1.x, a0.y) * st + 0.5 * st));
	ivec2 p01 = ivec2(floor(vec2(a0.x, a1.y) * st + 0.5 * st));
	ivec2 p11 = ivec2(floor(vec2(a1.x, a1.y) * st + 0.5 * st));
	ids = ivec4(int(texelFetch(lc_tex, p00, 0).r * 255.0 + 0.5), int(texelFetch(lc_tex, p10, 0).r * 255.0 + 0.5),
		int(texelFetch(lc_tex, p01, 0).r * 255.0 + 0.5), int(texelFetch(lc_tex, p11, 0).r * 255.0 + 0.5));
	ws = vec4((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
	vec4 land = vec4(ids.x > 0 ? 1.0 : 0.0, ids.y > 0 ? 1.0 : 0.0, ids.z > 0 ? 1.0 : 0.0, ids.w > 0 ? 1.0 : 0.0) * ws;
	float lw = land.x + land.y + land.z + land.w;
	vec3 c = texelFetch(lc_lut, ivec2(clamp(ids.x, 0, 127), 0), 0).rgb * land.x
		+ texelFetch(lc_lut, ivec2(clamp(ids.y, 0, 127), 0), 0).rgb * land.y
		+ texelFetch(lc_lut, ivec2(clamp(ids.z, 0, 127), 0), 0).rgb * land.z
		+ texelFetch(lc_lut, ivec2(clamp(ids.w, 0, 127), 0), 0).rgb * land.w;
	return vec4(c / max(lw, 0.001), lw);
}

// Desert ground colour (linear albedo, lit by the sun): ochre sand on the coast, reddish-brown inland, brown-grey
// gravel (hamada) on the broad plateaus, dune streaks in the low sand seas, pale salt pans in the flats, grey rock on
// the slopes and dark wadi beds along the low flow paths. Several noise scales so the ground reads at 600 m and 3000 m.
// Green-olive only in the north (Tunisia, Jebel Akhdar, Malta). No hedges, fields or grass blades on this map.
vec3 desert_ground(float h, float slope, vec2 xz, float sea_m, float cdist, float dm) {
	float lat = desert_origin_lat - xz.y / desert_upl_lat;
	vec3 ochre = vec3(0.36, 0.26, 0.15);      // sand and ochre
	vec3 pale = vec3(0.42, 0.34, 0.24);       // coastal sand and the limestone plateau
	vec3 reddish = vec3(0.30, 0.17, 0.10);    // inland reddish-brown ground
	vec3 gravel = vec3(0.19, 0.15, 0.11);     // brown-grey gravel (hamada)
	vec3 rock = vec3(0.16, 0.14, 0.12);       // grey rock on slopes
	vec3 salt = vec3(0.40, 0.38, 0.33);       // salt pans in the flats
	vec3 wadi = vec3(0.09, 0.07, 0.05);       // dark wadi beds
	vec3 olive = vec3(0.26, 0.27, 0.15);      // dry green-olive in the north
	float n_reg = t_vnoise2(xz * 0.0009 + 7.0);
	float n_mid = t_vnoise2(xz * 0.004 + 11.0);
	float n_fine = t_vnoise2(xz * 0.03 + 23.0);
	float n_grain = t_vnoise2(xz * 0.4 + 3.0);
	float coast_k = 1.0 - smoothstep(3000.0, 15000.0, sea_m);
	float inland = 1.0 - coast_k;
	vec3 base = mix(ochre, pale, coast_k * 0.6);
	float red_k = smoothstep(0.42, 0.66, t_vnoise2(xz * 0.0011 + 23.0)) * inland;
	base = mix(base, reddish, red_k * 0.7);
	float ham = smoothstep(0.50, 0.70, n_reg) * (1.0 - 0.6 * coast_k);
	base = mix(base, gravel * (0.9 + 0.2 * n_mid), ham * 0.85);
	// dune streaks: long ridges running NW-SE, in the low sand seas and where the sand is deep
	vec2 dd = vec2(0.82, 0.57);
	vec2 dp = vec2(-0.57, 0.82);
	float streak = t_vnoise2(vec2(dot(xz, dp) * 0.02, dot(xz, dd) * 0.0018) + 5.0);
	float erg = (1.0 - smoothstep(40.0, 130.0, h)) * inland * (1.0 - smoothstep(0.05, 0.20, slope));
	base = mix(base, ochre * (0.82 + 0.36 * streak), erg * 0.7);
	base *= 1.0 + (streak - 0.5) * 0.55 * smoothstep(0.35, 0.6, n_mid) * (1.0 - smoothstep(0.05, 0.22, slope));
	// land-cover classes: the table colour of the (dithered, blended) class replaces the latitude-only guess; the class
	// then adds its own surface texture (crust, strata, scrub speckle, field patchwork, terrace walls)
	float lcw = 0.0;
	if (use_lc) {
		ivec4 lid;
		vec4 lws;
		vec4 lcs = lc_sample(xz, cdist, lid, lws);
		vec3 lcol = lcs.rgb;
		float w_salt = lc_wsum(lid, lws, 116);
		float w_sab = lc_wsum(lid, lws, 111);
		float w_rock = lc_wsum(lid, lws, 114);
		float w_wadi = lc_wsum(lid, lws, 117);
		float w_ham = lc_wsum(lid, lws, 112) + lc_wsum(lid, lws, 60) * 0.5;
		float w_reg = lc_wsum(lid, lws, 113);
		float w_veg = lc_wsum(lid, lws, 20) + lc_wsum(lid, lws, 30) + lc_wsum(lid, lws, 10) + lc_wsum(lid, lws, 90);
		float w_crop = lc_wsum(lid, lws, 40) + lc_wsum(lid, lws, 120) + lc_wsum(lid, lws, 121);
		float w_lime = lc_wsum(lid, lws, 118);
		float w_bas = lc_wsum(lid, lws, 119);
		float w_sand = lc_wsum(lid, lws, 110) + lc_wsum(lid, lws, 115);
		float nm2 = t_vnoise2(xz * 0.0035 + 71.0);
		float near_d = 1.0 - smoothstep(1200.0, 6000.0, cdist);
		lcol *= 0.90 + 0.22 * n_mid + 0.10 * (n_reg - 0.5);
		// regional hue drift at 1-30 km: warm orange-red ground in places, cooler grey-buff in others (not on green land)
		float greenk = clamp(lc_wsum(lid, lws, 20) + lc_wsum(lid, lws, 30) + lc_wsum(lid, lws, 10) + lc_wsum(lid, lws, 40) + lc_wsum(lid, lws, 120) + lc_wsum(lid, lws, 121) + lc_wsum(lid, lws, 90), 0.0, 1.0);
		float redn = smoothstep(0.42, 0.68, t_vnoise2(xz * 0.0011 + 23.0)) * (1.0 - coast_k * 0.6);
		lcol *= mix(vec3(1.0), vec3(1.20, 0.94, 0.76), redn * 0.65 * (1.0 - greenk));
		lcol *= mix(vec3(1.05, 1.0, 0.93), vec3(0.96, 0.97, 1.0), smoothstep(0.35, 0.75, t_vnoise2(xz * 0.00035 + 5.0)) * (1.0 - greenk * 0.7));
		// salt crust: bright, broken by darker damp mud patches and fine cracks
		float crack = 1.0 - smoothstep(0.02, 0.07, abs(t_vnoise2(xz * 0.07 + 13.0) - 0.5));
		lcol = mix(lcol, lcol * vec3(0.80, 0.76, 0.68), w_salt * smoothstep(0.50, 0.78, nm2) * 0.8);
		lcol *= 1.0 - w_salt * crack * 0.10 * near_d;
		// sabkha: grey-tan crust over damp, darker flats
		lcol = mix(lcol, vec3(0.26, 0.22, 0.17), w_sab * smoothstep(0.52, 0.72, nm2) * 0.65);
		lcol = mix(lcol, vec3(0.58, 0.54, 0.45), w_sab * smoothstep(0.70, 0.84, n_mid) * 0.5);
		// rock: strata bands on the slopes, darker crevices
		float band = sin(h * 0.85 + n_mid * 5.0) * 0.5 + sin(h * 2.3 + 1.7) * 0.25;
		lcol *= 1.0 + band * 0.20 * w_rock * smoothstep(0.08, 0.35, slope);
		lcol = mix(lcol, lcol * vec3(0.78, 0.74, 0.72), w_rock * smoothstep(0.55, 0.80, n_fine) * 0.5);
		// wadi bed: damp darker gravel with grey-green scrub speckle
		float spk = smoothstep(0.60, 0.74, t_vnoise2(xz * 0.30 + 3.0)) * near_d;
		lcol = mix(lcol, vec3(0.15, 0.17, 0.09), w_wadi * spk * 0.7);
		lcol *= 1.0 - 0.18 * w_wadi * smoothstep(0.35, 0.70, nm2);
		// hamada: pale plateau with dark pebble speckle; reg: dark gravel with lighter wash patches
		lcol *= 1.0 - w_ham * 0.20 * smoothstep(0.56, 0.78, t_vnoise2(xz * 0.9 + 17.0)) * near_d;
		lcol = mix(lcol, lcol * vec3(1.45, 1.40, 1.30), w_reg * smoothstep(0.62, 0.80, n_mid) * 0.5);
		// scrub / grass / wetland: dark clumps and bare gaps
		lcol *= 1.0 - w_veg * 0.20 * smoothstep(0.45, 0.75, t_vnoise2(xz * 0.22 + 29.0)) * (0.4 + 0.6 * near_d);
		lcol = mix(lcol, vec3(0.38, 0.30, 0.20), w_veg * smoothstep(0.62, 0.82, nm2) * 0.28);
		// irrigated land, oases, orchards: a patchwork of small fields (green crop, stubble, ploughed earth)
		{
			vec2 fq = vec2(dot(xz, vec2(0.94, 0.34)), dot(xz, vec2(-0.34, 0.94))) / 85.0;
			vec2 fc = floor(fq);
			float fh = t_hash12(fc + 3.7);
			vec3 fcol = mix(vec3(0.24, 0.28, 0.12), vec3(0.30, 0.32, 0.15), fract(fh * 7.3));
			fcol = mix(fcol, vec3(0.44, 0.37, 0.20), smoothstep(0.62, 0.80, fh));
			fcol = mix(fcol, vec3(0.30, 0.21, 0.13), smoothstep(0.82, 0.94, fh));
			vec2 fe = abs(fract(fq) - 0.5);
			float ditch = smoothstep(0.46, 0.495, max(fe.x, fe.y)) * near_d;
			fcol = mix(fcol, fcol * 0.6, ditch);
			float cat = lc_wsum(lid, lws, 120) + lc_wsum(lid, lws, 121);
			fcol = mix(fcol, lcol * 0.95, smoothstep(1200.0, 4500.0, cdist) * 0.85);      // the patchwork melts into one tone with range (no 85 m squares at 3 km)
			lcol = mix(lcol, mix(fcol, lcol * 0.9, cat * 0.5), w_crop * 0.75);
		}
		// limestone (Malta, the Hyblaean plateau): honey stone cut into small walled terraces
		{
			vec2 tq = vec2(dot(xz, vec2(0.80, 0.60)), dot(xz, vec2(-0.60, 0.80))) / 36.0;
			vec2 te = abs(fract(tq) - 0.5);
			float wall = smoothstep(0.455, 0.49, max(te.x, te.y)) * (1.0 - smoothstep(900.0, 3200.0, cdist));
			float th = t_hash12(floor(tq) + 11.3);
			lcol *= 1.0 + (th - 0.5) * 0.16 * w_lime;
			lcol = mix(lcol, lcol * 1.22 + vec3(0.04), wall * w_lime * 0.55);
		}
		// basalt: near-black with pale dust in the lows
		lcol = mix(lcol, vec3(0.14, 0.125, 0.11), w_bas * smoothstep(0.55, 0.80, t_vnoise2(xz * 0.015 + 8.0)) * 0.6);
		// beach / sand sea: ripples handled below; a touch of wet darkness near the surf is added by the shore code
		lcol *= 1.0 + w_sand * (n_fine - 0.5) * 0.10;
		lcw = lcs.a;
		base = mix(base, lcol, lcw * 0.92);
	}
	// salt pans: pale, flat, low basins
	float pan = smoothstep(0.66, 0.78, t_vnoise2(xz * 0.0019 + 61.0)) * (1.0 - smoothstep(25.0, 70.0, h)) * (1.0 - smoothstep(0.03, 0.12, slope)) * inland;
	base = mix(base, salt * (0.92 + 0.10 * n_fine), pan * 0.8 * (1.0 - lcw));
	// limestone plateau: paler
	base = mix(base, pale * (0.95 + 0.08 * n_fine), smoothstep(150.0, 420.0, h) * 0.4 * (1.0 - lcw));
	// wadis: dark beds along the low ridged flow paths, with lighter gravel banks either side
	vec2 ww = xz + 900.0 * (vec2(t_vnoise2(xz * 0.0005 + 2.0), t_vnoise2(xz * 0.0005 + 31.0)) - 0.5);
	float wn = abs(t_vnoise2(ww * 0.0009 + 200.0) - 0.5);
	float wbed = 1.0 - smoothstep(0.002, 0.011, wn);
	float wbank = (1.0 - smoothstep(0.004, 0.016, wn)) * (1.0 - wbed);
	// the dark contour-like lines are only real at close range: fade them out with camera distance, and keep them
	// out of the sand seas (dunes bury the drainage)
	float wfade = (1.0 - smoothstep(500.0, 2200.0, cdist)) * (1.0 - smoothstep(0.03, 0.25, dm));
	float wok = smoothstep(45.0, 110.0, h) * (1.0 - smoothstep(260.0, 420.0, h)) * (1.0 - smoothstep(0.04, 0.14, slope)) * wfade;   // dry washes on the plateau, not in the low sand flats
	base = mix(base, wadi * (1.5 + 0.4 * n_fine), wbed * wok * 0.32);
	base = mix(base, gravel * 1.25, wbank * wok * 0.18);
	// rock on steep ground
	float rk = smoothstep(0.12, 0.34, slope);
	base = mix(base, rock * (0.85 + 0.3 * n_fine), rk * 0.85);
	// fine grain and gravel speckle
	base *= 0.86 + 0.24 * n_grain;
	base *= 0.92 + 0.14 * n_fine;
	// wind ripples on the dune sand: fine crests across the dune direction, strongest in the sand seas
	float rip = sin(dot(xz, vec2(-0.57, 0.82)) * 0.9 + 6.0 * t_vnoise2(xz * 0.01));
	base *= 1.0 + 0.05 * rip * erg;
	float gn = smoothstep(34.9, 35.6, lat) * (1.0 - smoothstep(200.0, 500.0, h))
	         + smoothstep(32.2, 32.8, lat) * smoothstep(350.0, 650.0, h) * (1.0 - smoothstep(0.2, 0.5, slope));
	base = mix(base, olive * (0.80 + 0.30 * n_reg), clamp(gn, 0.0, 1.0) * 0.55 * (1.0 - lcw));
	// darker, warmer sand (the ground read washed out at 400-3000 m)
	return base * vec3(1.02, 0.94, 0.82) * 0.90;
}

// Sand-sea dune shading. Near: the real mesh normal against the sun (lit windward faces, shadowed slip faces, crest
// highlights, ripples). Far (the coarse LODs cannot hold the dunes): the same seif ridges, painted as stripes.
vec3 desert_dune_shade(vec3 col, float dm, vec3 n, vec2 xz, float cdist, float h) {
	float dk = dm * (1.0 - smoothstep(150.0, 230.0, h));
	if (dk < 0.02) { return col; }
	vec3 sun = normalize(desert_sun_dir);
	vec2 across = vec2(-0.57, 0.82);
	float near_k = 1.0 - smoothstep(4500.0, 8000.0, cdist);
	float tilt = length(n.xz);
	float sf = dot(n, sun) - sun.y;                       // > 0 faces the sun, < 0 leeward
	float lit = clamp(1.0 + sf * 3.6, 0.40, 1.55);
	vec3 shaded = col * lit;
	float slip = smoothstep(0.10, 0.26, tilt) * (1.0 - smoothstep(-0.10, 0.0, sf));
	shaded = mix(shaded, shaded * vec3(0.76, 0.63, 0.56), slip * 0.5);               // cool, deep slip-face shadow
	shaded += vec3(0.07, 0.05, 0.02) * smoothstep(0.03, 0.14, sf) * smoothstep(0.04, 0.12, tilt) * col.r * 2.0;   // lit crest edge
	float rip = sin(dot(xz, across) * 1.1 + 6.0 * t_vnoise2(xz * 0.012)) * 0.5 + 0.5;
	shaded *= 1.0 - 0.10 * rip * (1.0 - smoothstep(600.0, 2200.0, cdist)) * (0.4 + 0.6 * smoothstep(0.0, 0.1, tilt));
	vec3 outc = shaded;
	// far range: analytic stripes
	float ph = dot(xz, across) / 480.0 + (t_vnoise2(xz * 0.0007 + 3.0) - 0.5) * 1.4;
	float th = 6.2832 * ph;
	float s = sin(th + 0.8 * sin(th));
	float ds = cos(th + 0.8 * sin(th)) * (1.0 + 0.8 * cos(th));
	float sunf = dot(sun.xz, across);
	float aa = 1.0 - smoothstep(0.12, 0.45, fwidth(ph));
	vec3 far_c = col * clamp(1.0 + 0.20 * s + 0.9 * ds * sunf, 0.45, 1.5);
	far_c = mix(far_c, far_c * vec3(0.78, 0.62, 0.55), smoothstep(0.55, 0.95, -ds * sunf * 2.0) * 0.55);
	outc = mix(far_c, shaded, near_k);
	outc = mix(col, outc, mix(aa, 1.0, near_k));
	outc *= mix(vec3(1.0), vec3(1.10, 0.94, 0.78), dk * 0.5);   // warmer, redder dune sand
	return mix(col, outc, dk);
}

void fragment() {
	float h = w_pos.y;
	float slope = 1.0 - clamp(w_normal.y, 0.0, 1.0);
	vec2 xz = w_pos.xz;

	// --- farmland: domain-warped Voronoi cells (irregular field shapes) with thin hedgerows ---
	// (Lattice kept identical to the previous version so Scatter.field_edge() stays in sync.)
	// a gentle warp only: hedges run nearly straight with the odd kink, as real field boundaries do (a strong
	// warp bent every field into curved bananas)
	vec2 warp = vec2(t_vnoise2(xz * 0.004), t_vnoise2(xz * 0.004 + 53.7)) - 0.5;
	float strip = step(0.55, t_vnoise2(xz * 0.0012 + 41.0));   // hard districts: a smooth blend would swirl the lattice into rings
	float zn = t_vnoise2(xz * 0.0009 + 77.0);
	float zscale = zn < 0.22 ? 0.65 : (zn < 0.42 ? 1.0 : (zn < 0.58 ? 1.6 : 1.2));   // small old enclosures .. big arable
	float zjit = zn < 0.42 ? 0.85 : (zn < 0.58 ? 0.6 : 0.12);
	// regional farming patterns (hard flags, see RegionMap.type_weights)
	vec4 rgn = vec4(0.0);
	if (use_regions) {
		vec2 ruv = clamp(vec2((w_pos.x - map_rect.x) * map_rect.z, (w_pos.z - map_rect.y) * map_rect.w), vec2(0.0), vec2(1.0));
		rgn = texture(region_tex, ruv);
	}
	float r_boc = step(0.5, rgn.r);
	float r_open = step(0.5, rgn.g) * (1.0 - r_boc);
	float r_pold = step(0.5, rgn.b) * (1.0 - r_boc) * (1.0 - r_open);
	float r_weald = step(0.5, rgn.a) * (1.0 - r_boc) * (1.0 - r_open) * (1.0 - r_pold);
	strip = max(strip * (1.0 - r_boc), r_pold);          // bocage: no strip fields; polder: all long parcels
	zscale = mix(zscale, 0.48, r_boc);                   // bocage: small enclosures (0.5-2 ha)
	zjit = mix(zjit, 0.9, r_boc);
	zscale = mix(zscale, 2.1, r_open);                   // open field: big hedgeless arable
	zscale = mix(zscale, zscale * 0.72, r_weald);        // Weald: small fields between the shaws
	float zrect = step(0.58, zn) * (1.0 - strip) * (1.0 - r_boc);       // regular rectangular enclosure: straight hedges and ditches
	float zrot = max(strip, step(0.42, zn));
	float sang = t_hash12(floor(xz * 0.00035) + 5.0) * 3.14159 * zrot;   // one bearing per district, no swirl
	vec2 sdir = vec2(cos(sang), sin(sang));
	vec2 wq = xz + warp * 30.0;
	float sa = dot(wq, sdir);
	float sb = dot(wq, vec2(-sdir.y, sdir.x));
	float zs = mix(zscale, 1.0, strip);
	vec2 wp = vec2(sa / (field_cell * mix(1.0, 1.7, strip) * zs * mix(1.0, 1.6, r_pold)), sb / (field_cell * mix(1.0, 0.72, strip) * zs * mix(1.0, 0.62, r_pold)));   // long fields ~2.4:1 (polders ~6:1)
	vec2 cell_id = floor(wp);
	vec2 gv = fract(wp) - 0.5;
	float f1 = 8.0;
	float f2 = 8.0;
	float cell_h = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 jit = vec2(t_hash12(cell_id + o), t_hash12(cell_id + o + 19.7)) - 0.5;
			vec2 rr = gv - (o + jit * mix(zjit, 0.85, strip));
			float dc = max(abs(rr.x), abs(rr.y));
			float d = mix(dot(rr, rr), dc * dc, zrect);   // Chebyshev metric gives square-cornered rectangular fields
			if (d < f1) { f2 = f1; f1 = d; cell_h = t_hash12(cell_id + o + 7.3); }
			else if (d < f2) { f2 = d; }
		}
	}
	float edge = sqrt(f2) - sqrt(f1);

	// --- continuous land-use palette (replaces the old discrete cell_h colour bands) ---
	// Large-scale districts say where farming is arable vs pastoral; per-field hashes give every
	// enclosure its own crop stage and sward, so neighbours never look like the same field.
	float region = t_vnoise2(xz * 0.0008 + 5.0);
	float regional_pasture = smoothstep(0.38, 0.74, region);
	float fh2 = t_hash12(cell_id + 19.7);
	float fh3 = t_hash12(cell_id + 31.1);
	float stage = fract(cell_h * 1.7 + fh2 * 2.3 + fh3 * 0.9);
	if (season_center >= 0.0) {
		stage = fract(season_center + (stage - 0.5) * 0.5);   // most fields near the season's stage, a spread either side
	}

	vec3 soil = soil_col * (0.85 + 0.30 * fh2);
	vec3 young = mix(crop_young_col, grass_b, 0.40 * fh3);
	vec3 ripe = mix(field_wheat, mix(field_wheat, stubble_col, 0.55), fh3);   // wheat vs barley, per field
	vec3 fallow = mix(field_brown * 1.05, grass_b * 0.85, clamp(t_vnoise2(xz * 0.06 + fh3 * 30.0), 0.0, 1.0));
	vec3 stub = stubble_col * (0.90 + 0.20 * fh2);
	vec3 arable = arable_stage(soil, fallow, young, ripe, stub, stage);

	vec3 pasture = mix(grass_a, grass_b, fh2);
	pasture = mix(pasture, meadow_col, smoothstep(0.50, 0.95, fh3) * 0.65);   // flower-rich meadow patches
	pasture = mix(pasture, grass_a * 0.80, step(0.72, cell_h) * 0.5);         // dark improved pasture

	// How pastoral this enclosure is: low cells and pasture districts stay grass.
	float pasture_w = clamp((1.0 - smoothstep(0.22, 0.60, cell_h)) * 0.75 + regional_pasture * 0.45 + 0.35 * r_boc + 0.30 * r_pold - 0.35 * r_open + pasture_bias, 0.0, 1.0);
	vec3 field = mix(arable, pasture, pasture_w);
	// occasional whole field of oilseed rape, only where farming is arable
	float rape = step(0.92, fh3) * (1.0 - regional_pasture) * (1.0 - pasture_w);
	field = mix(field, rape_col * (0.95 + 0.10 * fh2), rape);
	// field_variation: 0 blends everything toward one regional sward, 1 keeps the full patchwork
	field = mix(mix(grass_a, grass_b, region), field, field_variation);
	// within-field texture: finer mottled canopy instead of a flat fill
	float micro = t_vnoise2(xz * 0.42 + fh2 * 40.0) * 0.5 + t_vnoise2(xz * 0.11 + 9.0) * 0.35 + t_vnoise2(xz * 1.1 + fh3 * 10.0) * 0.15;
	field *= 1.0 + (micro - 0.5) * 0.22 * detail_strength;

	// hedgerow / headland shading along the cell boundaries (subtle linear feature, not a hard step)
	float hedge = 1.0 - smoothstep(0.013, 0.046 + 0.05 * r_boc, edge);   // ~same width in metres as before at the bigger cell size; bocage hedge banks wider
	vec3 bound_col = mix(hedge_col * (1.0 - 0.25 * r_boc), vec3(0.035, 0.050, 0.060), r_pold);   // polder: water-filled ditches
	field = mix(field, bound_col, hedge * 0.85 * (1.0 - 0.85 * r_open));
	// Woodland: under real forest cover there are no fields - no patchwork colours, hedge lines or drill marks,
	// only a dark mottled canopy ground, with a noise-broken edge so the wood margin is not a ruled curve.
	float wood = 0.0;
	if (use_wood) {
		vec2 wuv = vec2((w_pos.x - map_rect.x) * map_rect.z, (w_pos.z - map_rect.y) * map_rect.w);
		if (wuv.x >= 0.0 && wuv.x <= 1.0 && wuv.y >= 0.0 && wuv.y <= 1.0) {
			float wm = texture(wood_tex, wuv).r + (t_vnoise2(xz * 0.012 + 3.0) - 0.5) * 0.45 + (t_vnoise2(xz * 0.05 + 17.0) - 0.5) * 0.18;
			wood = smoothstep(0.40, 0.58, wm);
		}
	}
	if (wood > 0.0) {
		float cm = t_vnoise2(xz * 0.07 + 5.0) * 0.55 + t_vnoise2(xz * 0.28 + 11.0) * 0.45;
		vec3 canopy = forest_col * (0.80 + 0.40 * cm);
		field = mix(field, canopy, wood * 0.92);
		hedge *= 1.0 - wood;
	}

	float is_crop = clamp(1.0 - pasture_w, 0.0, 1.0) * (1.0 - wood);   // for drill lines / tramlines below

	// --- upland rough grazing, heath and moor ---
	vec3 moor = mix(upland_col, moor_col, smoothstep(0.30, 0.90, t_vnoise2(xz * 0.02 + 5.0)));
	moor = mix(moor, peat_col, smoothstep(0.62, 0.85, t_vnoise2(xz * 0.0013 + 88.0)) * 0.7);   // bare peat hags
	moor *= 0.90 + 0.20 * t_vnoise2(xz * 0.25);                                                 // tussocks
	// chalk downs: thin pale grass over the chalk, so the uplands read lighter than the moor (blend of existing colours)
	float downs_n = smoothstep(0.45, 0.70, t_vnoise2(xz * 0.004 + 31.0));
	float downs_amt = downs_n * smoothstep(40.0, 120.0, h) * (1.0 - smoothstep(0.20, 0.40, slope)) * 0.45;
	moor = mix(moor, mix(grass_b, limestone_col, 0.35) * (0.92 + 0.12 * t_vnoise2(xz * 0.6)), downs_amt);
	float rough = smoothstep(260.0, 700.0, h);                          // climbs from managed field to moor
	rough = clamp(rough + smoothstep(0.16, 0.42, slope) * 0.45, 0.0, 1.0);   // steeper ground is rougher grazing

	float heath_n = t_vnoise2(xz * 0.0011 + 77.0) * 0.7 + t_vnoise2(xz * 0.004 + 3.0) * 0.3;
	float heath = smoothstep(0.61, 0.69, heath_n) * smoothstep(20.0, 300.0, h) * (1.0 - smoothstep(0.22, 0.45, slope));
	vec3 hc = mix(heath_col, heather_col, smoothstep(0.35, 0.8, t_vnoise2(xz * 0.05 + 5.0)));
	hc = mix(hc, vec3(0.62, 0.56, 0.16), smoothstep(0.78, 0.90, t_vnoise2(xz * 0.35 + 9.0)) * 0.7);   // gorse
	hc = mix(hc, forest_col, smoothstep(0.86, 0.96, heath_n) * 0.5);                                    // wooded patches
	hc *= 0.88 + 0.24 * t_vnoise2(xz * 0.8);

	// chalk / limestone zones (real cliff zones supplied by the chunk manager)
	float cz = max(max(max(chalk_w(chalk_a, xz), chalk_w(chalk_b, xz)), max(chalk_w(chalk_c, xz), chalk_w(chalk_d, xz))), chalk_w(chalk_e, xz));

	// --- assemble the ground: managed lowland -> rough grazing -> heath -> marsh ---
	vec3 ground = mix(field, mix(field, moor, 0.75), rough);
	ground = mix(ground, hc, heath * 0.9);

	// soil (or lime) exposed where the ground is eroding: moderate vegetation-shedding slopes
	float erode = smoothstep(0.20, 0.44, slope) * (1.0 - smoothstep(0.44, 0.64, slope));
	ground = mix(ground, mix(soil_col * (1.0 + 0.15 * t_vnoise2(xz * 0.5 + 4.0)), limestone_col, cz), erode * 0.55);

	// low wet ground near the coast: marsh with pools
	float wet_n = t_vnoise2(xz * 0.0017 + 123.0);
	float marsh = smoothstep(0.58, 0.68, wet_n) * (1.0 - smoothstep(4.0, 14.0, h)) * smoothstep(1.2, 2.4, h);
	vec3 mc2 = mix(marsh_col, marsh_col * 1.35, t_vnoise2(xz * 0.12));
	mc2 = mix(mc2, river_col, smoothstep(0.66, 0.78, t_vnoise2(xz * 0.06 + 2.0)) * 0.8);
	ground = mix(ground, mc2, marsh);

	vec3 col = ground;
	// Lowland weight (managed farmland fades out on slopes and with height).
	float lowland = (1.0 - smoothstep(180.0, 520.0, h)) * (1.0 - smoothstep(0.10, 0.34, slope));
	// Desert map: the desert ground replaces the farmland palette here, so every overlay below (airfield grass,
	// bomb damage, floods, camps, beaches) paints on top of it, as it does on the Channel map.
	if (desert_look) {
		float sea_m = 5000.0;
		if (use_sea) {
			vec2 suv0 = clamp(vec2((w_pos.x - map_rect.x) * map_rect.z, (w_pos.z - map_rect.y) * map_rect.w), vec2(0.0), vec2(1.0));
			sea_m = texture(sea_tex, suv0).r * SEA_MAX_M;
		}
		float cdist = length(w_pos - CAMERA_POSITION_WORLD);
		float dmask = 0.0;
		if (use_dune) {
			vec2 duv = clamp(vec2((w_pos.x - map_rect.x) * map_rect.z, (w_pos.z - map_rect.y) * map_rect.w), vec2(0.0), vec2(1.0));
			dmask = texture(dune_tex, duv).r;
		}
		col = desert_ground(h, slope, xz, sea_m, cdist, dmask);
		if (desert_v2) { col = desert_dune_shade(col, dmask, normalize(w_normal), xz, cdist, h); }
		lowland = 0.0;
	}

	// Town ground: tarmac streets and paving instead of fields (soft, noise-broken edge).
	float urban = 0.0;
	if (use_urban && (use_map || desert_look)) {
		vec2 uuv = vec2((w_pos.x - map_rect.x) * map_rect.z, (w_pos.z - map_rect.y) * map_rect.w);
		if (uuv.x >= 0.0 && uuv.x <= 1.0 && uuv.y >= 0.0 && uuv.y <= 1.0) {
			float um = texture(urban_tex, uuv).r + (t_vnoise2(xz * 0.004) - 0.5) * 0.55 + (t_vnoise2(xz * 0.02 + 13.0) - 0.5) * 0.25;
			urban = smoothstep(0.22, 0.66, um) * (1.0 - smoothstep(0.25, 0.45, slope));
		}
	}
	// Real satellite/imagery overlay (draped by world XZ).
	float veg = 0.5;   // how green the real imagery is here (keeps marsh/polder from turning into beach)
	if (use_map) {
		vec2 muv = vec2((w_pos.x - map_rect.x) * map_rect.z, (w_pos.z - map_rect.y) * map_rect.w);
		if (muv.x >= 0.0 && muv.x <= 1.0 && muv.y >= 0.0 && muv.y <= 1.0) {
			vec3 mc = texture(map_tex, muv).rgb;
			veg = clamp((mc.g - max(mc.r, mc.b)) * 9.0, 0.0, 1.0);
			col = mix(col, mc, map_amount);
		}
	}

	// Re-apply the field patchwork / land-use colours over the imagery so variety, hedges and heath survive.
	// (with a war date set, crop fields show their season's stage more strongly: stubble, plough, green shoots)
	col = mix(col, mix(col, field, 0.34 + (season_center >= 0.0 ? 0.28 * is_crop : 0.0)), lowland * (1.0 - urban));
	col = mix(col, field, wood * 0.7 * (1.0 - urban));      // under forest the ground is canopy, whatever the imagery says
	// Dull farmland: the aerial imagery and the field palette are both graded a shade down and slightly
	// desaturated over the lowland, so the patchwork reads as muted wartime countryside rather than a
	// bright summer postcard. Upland, heath and towns are left alone.
	{
		float lg = lowland * (1.0 - urban);
		vec3 dull = mix(col, vec3(dot(col, vec3(0.299, 0.587, 0.114))), 0.22) * 0.87;
		if (season_center >= 0.0) {
			// season grade (B6): winter farmland greyer and duller, spring greener, harvest golden, autumn brown
			float sl = dot(season_tint, vec3(0.3333));
			dull = mix(dull, vec3(dot(dull, vec3(0.299, 0.587, 0.114))), clamp((0.95 - sl) * 3.0, 0.0, 0.35));
			dull *= season_tint;
		}
		col = mix(col, dull, lg);
	}
	// Mid-range texture (visible from altitude): mottled canopy of grass/crop, drill lines per field, dappled light.
	{
		float mott = t_vnoise2(xz * 0.045) * 0.5 + t_vnoise2(xz * 0.13 + 7.0) * 0.3 + t_vnoise2(xz * 0.4 + 2.0) * 0.2;
		vec2 fd = normalize(vec2(t_hash12(cell_id + 3.1) - 0.5, t_hash12(cell_id + 8.7) - 0.5) + vec2(0.001));
		float drill = abs(fract(dot(xz, fd) / 7.0) - 0.5) * 2.0;
		float drill_k = 1.0 - smoothstep(700.0, 3000.0, length(VERTEX));   // fine lines alias into moire rings at range
		float tex = (mott - 0.5) * 0.36 + (drill - 0.5) * 0.11 * is_crop * drill_k;
		float far_k = 1.0 - smoothstep(9000.0, 20000.0, length(VERTEX));
		col *= 1.0 + tex * far_k * lowland * (1.0 - urban);
		// Tramlines: pairs of tractor-wheel tracks running the length of some crop fields (about a third of them)
		float tram_on = (is_crop > 0.5 && t_hash12(cell_id + 61.3) < 0.38) ? 1.0 : 0.0;
		float tp = dot(xz, vec2(-fd.y, fd.x)) / 22.0;            // across the drills, one set every 22 m
		float tf = abs(fract(tp) - 0.5) * 22.0;                    // metres from the centre of a set
		float track = (1.0 - smoothstep(0.55, 1.15, abs(tf - 1.9))) + (1.0 - smoothstep(0.55, 1.15, abs(tf + 1.9 - 0.0)));
		float t_fade = 1.0 - smoothstep(1500.0, 5500.0, length(VERTEX));
		vec3 tram_col = mix(col * 0.80, col * 1.18 + vec3(0.04), step(0.5, t_hash12(cell_id + 12.9)));
		col = mix(col, tram_col, clamp(track, 0.0, 1.0) * tram_on * t_fade * lowland * (1.0 - urban) * (1.0 - hedge));
	}
	// Rivers and streams: meandering ridged-noise channels in the lowlands, with mud banks and a wet floodplain.
	// Painted only as a fallback: with real river geometry (real_rivers = 1) the ribbons replace this.
	if (real_rivers < 0.5) {
		vec2 rw = xz + 260.0 * (vec2(t_vnoise2(xz * 0.0006 + 2.0), t_vnoise2(xz * 0.0006 + 31.0)) - 0.5);
		float rn = abs(t_vnoise2(rw * 0.00075 + 200.0) - 0.5);
		float sn = abs(t_vnoise2(rw * 0.0021 + 400.0) - 0.5);
		float low_ok = (1.0 - smoothstep(25.0, 90.0, h)) * smoothstep(1.6, 3.0, h) * (1.0 - smoothstep(0.12, 0.30, slope)) * (1.0 - urban) * (desert_look ? 0.0 : 1.0);
		float rw1 = 0.0035 + 0.0035 * t_vnoise2(xz * 0.0004);
		float chan = (1.0 - smoothstep(rw1, rw1 * 1.3, rn));
		float stream = (1.0 - smoothstep(0.0011, 0.0016, sn)) * 0.9;
		float bank = max(1.0 - smoothstep(rw1 * 1.3, rw1 * 2.4, rn), (1.0 - smoothstep(0.0016, 0.0034, sn)) * 0.7);
		float flood = 1.0 - smoothstep(rw1 * 2.4, rw1 * 9.0, rn);
		col = mix(col, col * vec3(0.86, 0.95, 0.82), flood * low_ok * 0.5);
		col = mix(col, mud_col, bank * low_ok * 0.7);
		vec3 wcol = mix(river_col, vec3(0.34, 0.45, 0.46), 0.5 * t_vnoise2(xz * 0.08 + TIME * 0.02));
		col = mix(col, wcol, max(chan, stream) * low_ok);
	}
	// Lakes and ponds: blobby still water in hollows of the lowlands, ringed with reed and mud
	{
		float ln = t_vnoise2(xz * 0.00085 + 300.0) * 0.62 + t_vnoise2(xz * 0.0032 + 9.0) * 0.38;
		float lok = (1.0 - smoothstep(35.0, 110.0, h)) * smoothstep(2.0, 4.0, h) * (1.0 - smoothstep(0.08, 0.2, slope)) * (1.0 - urban) * (desert_look ? 0.0 : 1.0);
		// rarer and darker than before: at dusk the old pale teal ponds glowed like snow patches across the land
		float lake = smoothstep(0.800, 0.815, ln);
		float shore = smoothstep(0.780, 0.800, ln) * (1.0 - lake);
		vec3 lcol = mix(vec3(0.07, 0.12, 0.13), vec3(0.12, 0.18, 0.19), t_vnoise2(xz * 0.04 + TIME * 0.015));
		col = mix(col, mix(marsh_col * 0.9, mud_col, 0.4), shore * lok * 0.75);
		col = mix(col, lcol, lake * lok);
	}

	if (urban > 0.0) {
		float g = t_vnoise2(xz * 0.9) * 0.5 + t_vnoise2(xz * 0.07) * 0.5;
		vec3 town = mix(tarmac_col, paving_col, smoothstep(0.35, 0.75, g));
		town *= 0.9 + 0.2 * t_vnoise2(xz * 0.02 + 3.0);
		if (desert_look) {
			// packed street earth and dusty courtyards instead of tarmac and paving: pale sand-earth with darker worn lanes
			float lane = smoothstep(0.55, 0.9, t_vnoise2(xz * 0.9 + 4.0)) * 0.5 + smoothstep(0.6, 0.85, t_vnoise2(xz * 0.07 + 8.0)) * 0.5;
			town = mix(vec3(0.38, 0.31, 0.22), vec3(0.30, 0.24, 0.17), lane);
			town *= 0.92 + 0.16 * t_vnoise2(xz * 0.02 + 3.0);
		}
		col = mix(col, town, urban * 0.92);
		// Public parks inside towns (mirrored by Scatter.in_park)
		float pk = desert_look ? 0.0 : smoothstep(0.76, 0.80, t_vnoise2(xz * 0.0042 + 31.0));
		if (pk > 0.0) {
			vec3 mown = mix(grass_a, grass_b, 0.5) * (0.95 + 0.14 * t_vnoise2(xz * 0.15));
			mown = mix(mown, grass_a * 0.8, smoothstep(0.55, 0.8, t_vnoise2(xz * 0.9)) * 0.35);
			float pa = 1.0 - smoothstep(0.012, 0.03, abs(t_vnoise2(xz * 0.012 + 5.0) - 0.5));
			mown = mix(mown, paving_col * 1.1, pa * 0.8);   // winding gravel paths
			col = mix(col, mown, urban * pk);
		}
	}
	// Close-range micro detail so the ground has texture at low altitude: grain, ploughed furrows,
	// crop rows and meadow tufts. Fades out with distance (the imagery/field colours carry the far view).
	float dist_v = length(VERTEX);
	float near_k = 1.0 - smoothstep(600.0, 4200.0, dist_v);
	if (near_k > 0.0 && h > 1.5 && urban < 0.5) {
		float g1 = t_vnoise2(xz * 0.55);
		float g2 = t_vnoise2(xz * 2.3);
		float g3 = t_vnoise2(xz * 0.11 + 9.0);
		float grain = (g1 * 0.45 + g2 * 0.35 + g3 * 0.55) - 0.67;
		vec2 fdir = normalize(vec2(t_hash12(cell_id + 3.1) - 0.5, t_hash12(cell_id + 8.7) - 0.5) + vec2(0.001));
		float rows = smoothstep(0.35, 0.65, abs(fract(dot(xz, fdir) / 2.6) - 0.5) * 2.0);
		float crop = is_crop;
		float tuft = smoothstep(0.55, 0.9, t_vnoise2(xz * 1.3 + 31.0));
		float detail = grain * 0.45 + crop * (rows - 0.5) * 0.16 * lowland + (1.0 - crop) * (tuft - 0.4) * 0.10 * lowland;
		// blade/stalk streaks and clods: stretched noise along the field direction plus fine speckle
		float streak = t_vnoise2(vec2(dot(xz, fdir) * 0.9, dot(xz, vec2(-fdir.y, fdir.x)) * 5.0)) - 0.5;
		float speck = t_hash12(floor(xz * 3.0)) - 0.5;
		detail += streak * 0.30 * lowland + speck * 0.12 + (t_vnoise2(xz * 6.0) - 0.5) * 0.14;
		col *= 1.0 + detail * near_k * 1.5 * (0.6 + 0.4 * detail_strength);
	}
	// Airfield grass: a gently lightened, mown version of the surrounding colour, fading out over `softness` metres.
	// af_b.w is the zone kind: 1 = aerodrome grass, 2 = army camp (trampled grass and mud), 3 = POW / labour
	// camp (bare sandy compound). Only the nearest 24 zones are uploaded (terrain_chunk_manager.gd).
	float afw = 0.0;
	float cw = 0.0;
	float pw = 0.0;
	float dmg = 0.0;     // kind 4: bomb damage (rubble, scorch, craters); strength in the fractional part
	float flood = 0.0;   // kind 5: flood water up to a level (fraction x 40 = world y)
	float churn = 0.0;   // kind 6: beach churned by landing craft, tracks and shells
	int zmask = 0;
	ivec2 zc = ivec2(floor((xz - zone_rect.xy) * zone_rect.z));
	if (zc.x >= 0 && zc.y >= 0 && zc.x < int(zone_rect.w) && zc.y < int(zone_rect.w)) {
		uvec4 zt = uvec4(round(texelFetch(zone_tex, zc, 0) * 255.0));
		zmask = int(zt.r | (zt.g << 8u) | (zt.b << 16u) | (zt.a << 24u));
	}
	for (int i = 0; i < 32; i++) {
		if (zmask == 0) { break; }
		bool on = (zmask & 1) != 0;
		zmask = (zmask >> 1) & 0x7fffffff;
		if (!on) { continue; }
		vec4 b = af_b[i];
		if (b.w < 0.5) { continue; }
		vec4 a = af_a[i];
		vec2 d = xz - a.xy;
		// cheap reject first: most of the 32 zones are kilometres away from any given pixel
		float reach = max(b.x, b.y) * 1.415 + b.z * 1.8;
		if (dot(d, d) > reach * reach) { continue; }
		float along = dot(d, a.zw);
		float across = dot(d, vec2(-a.w, a.z));
		vec2 q = abs(vec2(along, across)) - b.xy;
		float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
		if (sd > b.z * 1.75) { continue; }
		if (b.w > 1.5 && sd > -b.z * 0.72) {
			// camps, damage, floods: a ragged edge, not a ruled rectangle (only the noise where it can matter)
			sd += (t_vnoise2(xz * 0.018 + a.xy * 0.001) - 0.5) * b.z * 1.4;
		}
		float w = 1.0 - smoothstep(0.0, b.z, sd);
		float kind = floor(b.w + 0.001);
		if (kind < 1.5) { afw = max(afw, w); }
		else if (kind < 2.5) { cw = max(cw, w); }
		else if (kind < 3.5) { pw = max(pw, w); }
		else if (kind < 4.5) { dmg = max(dmg, w * fract(b.w)); }
		else if (kind < 5.5) {
			float lvl = fract(b.w) * 40.0;
			flood = max(flood, w * (1.0 - smoothstep(lvl - 0.8, lvl + 0.15, h)) * step(0.3, h));
		}
		else if (kind < 6.5) { churn = max(churn, w * fract(b.w)); }
	}
	if (cw > 0.0) {
		// Army camp: the field lattice and hedge lines stop; worn pasture churned to mud in patches by tracks
		// and boots, as in the 1944 marshalling-area photographs.
		vec3 worn = mix(mix(grass_a, hedge_col, 0.30), mud_col, 0.22) * 0.92;
		float churn = smoothstep(0.55, 0.80, t_vnoise2(xz * 0.022 + 5.0));
		worn = mix(worn, mud_col * 0.95, churn * 0.65);
		worn *= 0.94 + 0.12 * t_vnoise2(xz * 0.09 + 3.0);
		col = mix(col, worn, cw * 0.9);
	}
	if (dmg > 0.0) {
		// Bomb damage: the burnt-out districts of the Blitz and the bombed towns of 1942-45 seen from the air -
		// grey-brown rubble where blocks were pulled down, black scorch where whole streets burned, and crater
		// fields (one possible crater per 30 m cell, more of them the heavier the damage) with spoil rims. The
		// rubble wash follows the built-up area (urban); open ground inside the zone only gets the craters.
		// Colours are linear (sRGB rubble ~0.42/0.38/0.33, scorch ~0.12).
		vec3 rubble = vec3(0.150, 0.124, 0.094);
		vec3 scorch = vec3(0.016, 0.014, 0.012);
		vec3 g = rubble * (0.80 + 0.35 * t_vnoise2(xz * 0.21 + 2.0));
		g = mix(g, scorch, smoothstep(0.56, 0.78, t_vnoise2(xz * 0.028 + 11.0)) * 0.7);
		vec2 ccell = floor(xz / 30.0);
		vec2 cpos = (ccell + 0.2 + 0.6 * vec2(t_hash12(ccell + 3.7), t_hash12(ccell + 8.1))) * 30.0;
		float crad = 3.0 + 5.0 * t_hash12(ccell + 1.3);
		float cd = length(xz - cpos) / crad;
		float has = step(1.0 - dmg * 0.75, t_hash12(ccell + 9.9));
		float pit = (1.0 - smoothstep(0.55, 0.95, cd)) * has;
		float rim = smoothstep(0.85, 1.0, cd) * (1.0 - smoothstep(1.0, 1.4, cd)) * has;
		float wash = clamp(dmg * 1.1, 0.0, 0.9) * mix(0.15, 1.0, urban);
		col = mix(col, g, wash);
		col = mix(col, scorch * 2.0, pit * min(dmg * 1.4, 0.85));
		col = mix(col, rubble * 1.05, rim * min(dmg * 1.2, 0.6));
	}
	float water_k = 0.0;
	if (flood > 0.0) {
		// Deliberate inundation: a sheet of grey, sky-lit water over the fields, with the hedge lines and the
		// field boundaries still showing as darker stripes (the hedges stood up out of the water in the photos).
		vec3 fwater = vec3(0.075, 0.095, 0.105) * (0.88 + 0.22 * t_vnoise2(xz * 0.012 + 4.0));
		fwater = mix(fwater, col * 0.45, hedge * 0.6);
		col = mix(col, fwater, flood * 0.92);
		water_k = flood * (1.0 - hedge * 0.6);
	}
	if (churn > 0.0) {
		// Beach after the landings: sand torn up by tracks and shells - long darker track bands running up the
		// beach, wet dark patches, and small shell holes.
		float trk = smoothstep(0.62, 0.74, t_vnoise2(vec2(xz.x * 0.02, xz.y * 0.4) + 3.0)) + smoothstep(0.62, 0.74, t_vnoise2(vec2(xz.x * 0.4, xz.y * 0.02) + 9.0));
		vec2 sc = floor(xz / 14.0);
		vec2 sp = (sc + 0.25 + 0.5 * vec2(t_hash12(sc + 1.0), t_hash12(sc + 6.0))) * 14.0;
		float sh = (1.0 - smoothstep(0.4, 1.0, length(xz - sp) / (1.5 + 2.0 * t_hash12(sc + 2.0)))) * step(0.55, t_hash12(sc + 4.0));
		vec3 dark = col * 0.62;
		col = mix(col, dark, clamp(trk, 0.0, 1.0) * 0.5 * churn);
		col = mix(col, col * 0.45, sh * churn * 0.8);
		col = mix(col, col * vec3(0.78, 0.80, 0.82), smoothstep(0.55, 0.8, t_vnoise2(xz * 0.05)) * 0.4 * churn);
	}
	if (pw > 0.0) {
		// POW compound: the ground inside the wire is beaten bare - pale sandy earth with a little grass at the
		// edges (Stalag Luft III and the Rhineland Stalags stood on sandy heath).
		vec3 bare = mix(mix(sand_col, soil_col, 0.55), grass_a, 0.12) * 0.86;
		bare = mix(bare, mix(grass_a, hedge_col, 0.3), smoothstep(0.62, 0.85, t_vnoise2(xz * 0.03 + 9.0)) * 0.5);
		bare *= 0.93 + 0.14 * t_vnoise2(xz * 0.12 + 1.0);
		col = mix(col, bare, pw * 0.92);
	}
	if (afw > 0.0) {
		// Aerodrome grass. The field patchwork stops inside the perimeter - no crop colour, no drill lines,
		// no headland shading carried in from the surroundings - replaced by ONE muddy mown grass tone.
		// Derived from the palette (pasture darkened and dragged toward bare earth) so it is dark and muddy
		// but still clearly grass, and blended at 0.85 so a trace of the local ground keeps it from reading
		// as a flat decal. Deliberately not darker than this: an airfield should settle into the fields, not
		// punch a hole in them.
		// v2.2: darker, the shade of the deeper pasture fields around it (pasture pulled toward hedgerow green),
		// so from the air the field blends into the patchwork instead of showing as a pale disc
		vec3 airfield_grass = mix(mix(grass_a, hedge_col, 0.38), soil_col, 0.08) * 0.9;
		if (desert_look) {
			// desert fields: packed sand and gravel, no grass
			// pale scuffed earth with darker trampled and oil-stained patches
			airfield_grass = mix(vec3(0.55, 0.47, 0.34), vec3(0.46, 0.38, 0.27), t_vnoise2(xz * 0.05 + 31.0));
			airfield_grass *= 1.0 - 0.14 * smoothstep(0.55, 0.80, t_vnoise2(xz * 0.035 + 7.0));
			airfield_grass *= 1.0 - 0.10 * smoothstep(0.62, 0.85, t_vnoise2(xz * 0.3 + 3.0));
		}
		float mow = 0.97 + 0.04 * step(0.5, fract(dot(xz, vec2(0.7, 0.7)) / 44.0));
		// a slow mottle keeps the interior from reading as one flat decal: the field LATTICE is suppressed,
		// but real aerodrome grass still varies patch to patch
		float mottle = 0.94 + 0.12 * t_vnoise2(xz * 0.006 + 17.0);
		airfield_grass *= mow * mottle;
		col = mix(col, airfield_grass, afw * 0.85);
	}
	// steep faces -> rock (roughness-broken so faces are not a flat fill), then chalk / limestone by zone
	float rockness = desert_look ? 0.0 : smoothstep(rock_slope - 0.14, rock_slope + 0.14, slope);   // desert: its own rock above
	vec3 rockc = rock_col * (0.85 + 0.30 * t_vnoise2(xz * 0.5 + 4.0));
	rockc = mix(rockc, soil_col, smoothstep(0.30, 0.50, t_vnoise2(xz * 0.09 + 21.0)) * 0.35);   // gullies / earth
	col = mix(col, rockc, rockness);
	float chalk_amt = cz * smoothstep(0.42, 0.62, slope) * smoothstep(8.0, 40.0, h);
	// chalk face: whiter, with vertical weathering streaks (noise stretched along height) and a little flint speckle
	float streaks = t_vnoise2(vec2((xz.x + xz.y) * 0.35, h * 0.12)) * 0.6 + t_vnoise2(vec2((xz.x - xz.y) * 0.9, h * 0.35)) * 0.4;
	vec3 chalk_face = mix(chalk_col, limestone_col, 0.25) * (0.94 + 0.10 * streaks);
	chalk_face = mix(chalk_face, rock_col * 0.85, smoothstep(0.62, 0.80, t_vnoise2(xz * 1.6 + 17.0)) * 0.18);
	col = mix(col, chalk_face, chalk_amt);
	// grass cap where the cliff top levels off, and a darker rubble / talus fan where the face meets the beach
	float cap = cz * (1.0 - smoothstep(0.18, 0.34, slope)) * smoothstep(20.0, 45.0, h);
	col = mix(col, mix(grass_a, grass_b, t_vnoise2(xz * 0.4)), cap * 0.75);
	float talus = cz * (1.0 - smoothstep(10.0, 22.0, h)) * smoothstep(0.25, 0.42, slope);
	col = mix(col, rock_col * (0.75 + 0.2 * streaks), talus * 0.6);
	// beaches and shoreline: a wide pale sand strip whose back edge wanders along the coast, wet dark sand at
	// the waterline, ripples on the lower beach, a ragged tide-wrack line and a grassy dune fringe behind.
	{
		float bn = t_vnoise2(xz * 0.012 + 3.0) * 0.6 + t_vnoise2(xz * 0.06 + 9.0) * 0.4;
		float top = 4.5 + bn * 6.0;
		float flat_k = 1.0 - smoothstep(0.30, 0.55, slope);
		float sea_k = 1.0;
		if (use_sea && (use_map || desert_look)) {
			vec2 suv = vec2((w_pos.x - map_rect.x) * map_rect.z, (w_pos.z - map_rect.y) * map_rect.w);
			sea_k = 1.0 - smoothstep(900.0, 1700.0, texture(sea_tex, clamp(suv, vec2(0.0), vec2(1.0))).r * SEA_MAX_M);
		}
		// sand only on the coast: fades out beyond ~1.7 km from the sea, and not on built-up ground
		float sandm = (1.0 - smoothstep(top * 0.55, top, h)) * flat_k * (1.0 - smoothstep(0.55, 0.95, veg) * 0.8) * (1.0 - smoothstep(0.02, 0.3, urban)) * sea_k;
		float grain = t_vnoise2(xz * 1.9) * 0.5 + t_vnoise2(xz * 0.5 + 5.0) * 0.5;
		vec3 dry = mix(sand_col * 1.06, sand_col * 0.88, grain);
		float ripple = sin(dot(xz, vec2(0.62, 0.78)) * 1.9 + t_vnoise2(xz * 0.11) * 7.0) * 0.5 + 0.5;
		dry *= 1.0 - 0.07 * ripple * (1.0 - smoothstep(1.0, 3.0, h));
		float wet_k = 1.0 - smoothstep(0.45, 1.5, h + (t_vnoise2(xz * 0.18) - 0.5) * 0.7);
		vec3 sc = mix(dry, sand_col * 0.60, wet_k);
		float wrack_y = 1.7 + (bn - 0.5) * 0.9 + (t_vnoise2(xz * 0.7) - 0.5) * 0.35;
		sc = mix(sc, vec3(0.20, 0.17, 0.12), (1.0 - smoothstep(0.0, 0.22, abs(h - wrack_y))) * 0.45 * step(0.5, t_vnoise2(xz * 0.35 + 2.0)));
		// dune fringe: marram grass creeping onto the back of the beach
		float dune = smoothstep(top * 0.55, top * 0.9, h) * (0.4 + 0.6 * t_vnoise2(xz * 0.25 + 8.0));
		sc = mix(sc, vec3(0.42, 0.45, 0.25) * (0.8 + 0.4 * grain), dune * 0.55);
		col = mix(col, sc, sandm * 0.96);
	}
	// tidal flats: estuary mud just above the waterline, cut by a few drying channels, with a faint wet sheen
	{
		float estuary = smoothstep(0.55, 0.72, t_vnoise2(xz * 0.0025 + 40.0)) * (1.0 - urban);
		float flat_low = (1.0 - smoothstep(0.6, 3.0, h)) * smoothstep(-0.4, 0.2, h) * (1.0 - smoothstep(0.08, 0.2, slope));
		float chan = smoothstep(0.62, 0.70, t_vnoise2(xz * 0.05 + 12.0));
		vec3 mud = mix(mud_col * 0.95, mud_col * 1.12, t_vnoise2(xz * 0.7));
		mud = mix(mud, seabed_col * 0.9, chan * 0.5);
		mud = mix(mud, mud * 1.25, smoothstep(0.70, 0.85, t_vnoise2(xz * 0.3 + 7.0)) * 0.3);   // wet sheen patches
		col = mix(col, mud, estuary * flat_low * 0.85);
	}
	// sea floor
	col = mix(col, seabed_col, 1.0 - smoothstep(-3.0, 0.5, h));
	// Ambient occlusion in hollows: soft darkening of broad, low, gentle basins (reads as valley shading).
	{
		float basin_n = t_vnoise2(xz * 0.0011 + 61.0) * 0.6 + t_vnoise2(xz * 0.0037 + 17.0) * 0.4;
		float hollow = smoothstep(0.44, 0.62, basin_n) * (1.0 - smoothstep(0.06, 0.30, slope)) * (1.0 - urban);
		col *= 1.0 - ao_strength * hollow * 0.35;
	}
	// Grass looks slightly lighter / translucent at grazing angles (fake leaf transmission), on green ground only.
	{
		float graze = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		float greenness = clamp((col.g * 1.4 - max(col.r, col.b)) * 3.0, 0.0, 1.0);
		col += vec3(0.05, 0.08, 0.03) * graze * graze * grass_translucency * greenness * (1.0 - urban);
	}
	// Drifting cloud shadows: big soft patches that slide with the wind; more cover = more of them.
	if (cloud_shadow > 0.01 && h > -2.0) {
		vec2 cp = xz * 0.0006 + vec2(TIME * 0.005, TIME * 0.003);
		float cn = t_vnoise2(cp) * 0.65 + t_vnoise2(cp * 2.3 + 5.0) * 0.35;
		float lo = 0.66 - 0.25 * cloud_shadow;
		col *= 1.0 - 0.40 * smoothstep(lo, lo + 0.15, cn) * min(cloud_shadow * 1.7, 1.0);
	}

	col = mix(col, col * vec3(0.66, 0.70, 0.72) + vec3(0.0, 0.006, 0.012), wetness * (1.0 - urban * 0.4));
	ALBEDO = col;
	ROUGHNESS = mix(ground_roughness, 0.12, water_k);
	METALLIC = 0.0;
}
