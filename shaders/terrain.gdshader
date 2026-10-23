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
uniform bool use_urban = false;
uniform sampler2D sea_tex : filter_linear, repeat_disable;   // distance to the sea (R = metres / SEA_MAX_M), same rect as map_tex
uniform bool use_sea = false;
const float SEA_MAX_M = 3000.0;
uniform vec3 tarmac_col : source_color = vec3(0.26, 0.26, 0.25);
uniform vec3 paving_col : source_color = vec3(0.37, 0.34, 0.31);

// Airfield grass: oriented, soft-edged rectangles tinted onto the terrain (no slab, no hard edge).
// af_a = (x, z, dir.x, dir.z) of the runway direction, af_b = (half along, half across, softness, active).
uniform vec4 af_a[24];
uniform vec4 af_b[24];

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
	float zrect = step(0.58, zn) * (1.0 - strip);       // regular rectangular enclosure: straight hedges and ditches
	float zrot = max(strip, step(0.42, zn));
	float sang = t_hash12(floor(xz * 0.00035) + 5.0) * 3.14159 * zrot;   // one bearing per district, no swirl
	vec2 sdir = vec2(cos(sang), sin(sang));
	vec2 wq = xz + warp * 30.0;
	float sa = dot(wq, sdir);
	float sb = dot(wq, vec2(-sdir.y, sdir.x));
	float zs = mix(zscale, 1.0, strip);
	vec2 wp = vec2(sa / (field_cell * mix(1.0, 1.7, strip) * zs), sb / (field_cell * mix(1.0, 0.72, strip) * zs));   // long fields ~2.4:1
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
	float pasture_w = clamp((1.0 - smoothstep(0.22, 0.60, cell_h)) * 0.75 + regional_pasture * 0.45, 0.0, 1.0);
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
	float hedge = 1.0 - smoothstep(0.013, 0.046, edge);   // ~same width in metres as before at the bigger cell size
	field = mix(field, hedge_col, hedge * 0.85);

	float is_crop = clamp(1.0 - pasture_w, 0.0, 1.0);   // for drill lines / tramlines below

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

	// Town ground: tarmac streets and paving instead of fields (soft, noise-broken edge).
	float urban = 0.0;
	if (use_urban && use_map) {
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
	col = mix(col, mix(col, field, 0.34), lowland * (1.0 - urban));
	// Dull farmland: the aerial imagery and the field palette are both graded a shade down and slightly
	// desaturated over the lowland, so the patchwork reads as muted wartime countryside rather than a
	// bright summer postcard. Upland, heath and towns are left alone.
	{
		float lg = lowland * (1.0 - urban);
		vec3 dull = mix(col, vec3(dot(col, vec3(0.299, 0.587, 0.114))), 0.22) * 0.87;
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
		float low_ok = (1.0 - smoothstep(25.0, 90.0, h)) * smoothstep(1.6, 3.0, h) * (1.0 - smoothstep(0.12, 0.30, slope)) * (1.0 - urban);
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
		float lok = (1.0 - smoothstep(35.0, 110.0, h)) * smoothstep(2.0, 4.0, h) * (1.0 - smoothstep(0.08, 0.2, slope)) * (1.0 - urban);
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
		col = mix(col, town, urban * 0.92);
		// Public parks inside towns (mirrored by Scatter.in_park)
		float pk = smoothstep(0.76, 0.80, t_vnoise2(xz * 0.0042 + 31.0));
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
	for (int i = 0; i < 24; i++) {
		vec4 b = af_b[i];
		if (b.w < 0.5) { continue; }
		vec4 a = af_a[i];
		vec2 d = xz - a.xy;
		float along = dot(d, a.zw);
		float across = dot(d, vec2(-a.w, a.z));
		vec2 q = abs(vec2(along, across)) - b.xy;
		float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
		if (b.w > 1.5) {
			// camps: a ragged worn edge, not a ruled rectangle
			sd += (t_vnoise2(xz * 0.018 + a.xy * 0.001) - 0.5) * b.z * 1.4;
		}
		float w = 1.0 - smoothstep(0.0, b.z, sd);
		if (b.w < 1.5) { afw = max(afw, w); }
		else if (b.w < 2.5) { cw = max(cw, w); }
		else { pw = max(pw, w); }
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
		float mow = 0.97 + 0.04 * step(0.5, fract(dot(xz, vec2(0.7, 0.7)) / 44.0));
		// a slow mottle keeps the interior from reading as one flat decal: the field LATTICE is suppressed,
		// but real aerodrome grass still varies patch to patch
		float mottle = 0.94 + 0.12 * t_vnoise2(xz * 0.006 + 17.0);
		airfield_grass *= mow * mottle;
		col = mix(col, airfield_grass, afw * 0.85);
	}
	// steep faces -> rock (roughness-broken so faces are not a flat fill), then chalk / limestone by zone
	float rockness = smoothstep(rock_slope - 0.14, rock_slope + 0.14, slope);
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
		if (use_sea && use_map) {
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
	ROUGHNESS = ground_roughness;
	METALLIC = 0.0;
}
