shader_type spatial;
render_mode specular_schlick_ggx, cull_back, depth_draw_opaque;

#include "res://shaders/toon_common.gdshaderinc"

// Realistic world-surface shader: the single replacement for the toon factory on every procedural
// building, road, tree, prop and vehicle. Triplanar in OBJECT space (the procedural meshes have no
// usable UVs, so a wall, roof and floor all read correctly), a real PBR response, and weathering
// built from settled dust, rain runs down vertical faces and texture-derived surface relief.
//
// There is NO cel ramp, NO banded toon step, NO rim light and NO inverted-hull outline here: the
// outline is a separate next_pass the caller adds and is expected to stop adding.
//
// The uniform block below is a CONTRACT with scripts/toon_util.gd - every name is set from code, so
// keep them in sync. surface_tex is assigned by the caller (assets/textures/world/*.png).

// ---- surfaces (the toon_util contract) -----------------------------------------------------------
uniform vec4 albedo : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform sampler2D surface_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float tex_scale = 0.5;                         // triplanar tiles per metre
uniform float roughness_v : hint_range(0.0, 1.0) = 0.8;
uniform float metallic_v : hint_range(0.0, 1.0) = 0.0;
uniform float wear : hint_range(0.0, 1.0) = 0.35;      // grime, streaks, edge wear
uniform float flat_shade : hint_range(0.0, 1.0) = 0.0; // >0.5 = ignore textures, use a plain lit colour
uniform float underside_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 underside_color : source_color = vec4(0.4, 0.4, 0.42, 1.0);
uniform float patch_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 patch_color : source_color = vec4(0.3, 0.3, 0.3, 1.0);
uniform float patch_scale = 0.5;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 1.0;
uniform float detail_mode = 0.0;                       // 0 building, 1 asphalt, 2 foliage, 3 grass, 4 vehicle, 5 metal
uniform float gloss : hint_range(0.0, 1.0) = 0.0;      // painted sheen

varying vec3 obj_p;      // object-space position (triplanar source)
varying vec3 obj_n;      // object-space normal
varying vec3 w_pos;      // world position (camera-distance fade for fine detail)

void vertex() {
	obj_p = VERTEX;
	obj_n = normalize(NORMAL);
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Triplanar sample of surface_tex: the three axis pairs weighted by the (sharpened) normal axes.
vec3 triplanar(vec3 p, vec3 w, float s) {
	vec3 x = texture(surface_tex, p.zy * s).rgb;
	vec3 y = texture(surface_tex, p.xz * s).rgb;
	vec3 z = texture(surface_tex, p.xy * s).rgb;
	return x * w.x + y * w.y + z * w.z;
}

void fragment() {
	vec3 n = normalize(obj_n);
	vec3 an = abs(n);
	// Sharpened triplanar weights: a wall reads as a wall and a roof as a roof, with no soft
	// cross-fade smearing rounded corners.
	vec3 bw = pow(an, vec3(4.0));
	bw /= max(bw.x + bw.y + bw.z, 1e-4);

	float s = max(tex_scale, 1e-4);
	// Static world geometry (buildings, roads, grass) is batched into huge meshes, so object space would tile
	// the texture hundreds of times across one mesh and mip-blur it to flat grey - a 12 m terrace would show
	// brick only if the projection is anchored to the world. Moving props keep object space so their
	// texture travels with them instead of swimming through it.
	vec3 tp = (detail_mode > 3.5) ? obj_p : w_pos;
	vec3 tex = triplanar(tp, bw, s);
	float tex_lum = dot(tex, vec3(0.299, 0.587, 0.114));

	bool untextured = flat_shade > 0.5;
	float m = detail_mode;

	// ---- base surface -----------------------------------------------------------------------
	vec3 col = untextured ? albedo.rgb : tex * albedo.rgb;
	float rough = roughness_v;
	float metal = metallic_v;
	float spec = 0.5;
	float relief_k = 1.0;      // how much texture-luminance relief this surface gets

	if (!untextured) {
		// ---- weathering --------------------------------------------------------------------
		// Fine weathering fades out with camera range (the project has a history of distant
		// shimmer); the coarse terms - settled dust, blotches, ground splash - stay at range.
		float cam_dist = length(w_pos - CAMERA_POSITION_WORLD);
		float near_k = 1.0 - smoothstep(120.0, 900.0, cam_dist);

		float up = smoothstep(0.10, 0.90, n.y);              // dust settles on upward faces
		float vert = 1.0 - smoothstep(0.30, 0.80, abs(n.y)); // rain runs down vertical faces

		// Streaks: very low frequency along Y and moderate across, so the pattern forms long
		// vertical runs rather than the fine speckle the previous attempt produced.
		vec2 suv = vec2(obj_p.x * 2.6 + obj_p.z * 2.6, obj_p.y * 0.09);
		float streak = t_vnoise2(suv) * 0.6 + t_vnoise2(suv * 2.3 + 17.0) * 0.4;
		streak = smoothstep(0.42, 0.92, streak) * near_k;

		// Broad dirt blotches (low frequency, never aliases).
		float blotch = smoothstep(0.40, 0.88, t_vnoise3(obj_p * 0.55 + 5.0));

		// Recesses / mortar: the dark parts of the texture are dirt traps. Mip-filtered, so it
		// needs no range fade.
		float cavity = 1.0 - smoothstep(0.10, 0.55, tex_lum);

		float dirt = clamp(up * 0.50 + vert * streak * 0.65 + blotch * 0.30, 0.0, 1.0) * wear;
		col *= 1.0 - dirt * 0.45;
		col = mix(col, col * vec3(0.82, 0.80, 0.76), cavity * wear * 0.35);

		// Soot / shadow in the undersides.
		col = mix(col, col * 0.55, smoothstep(0.25, 0.95, -n.y) * wear * 0.45);

		// Ground splash: the bottom of a wall is dirtier (a plinth, as the old shader had).
		float low = smoothstep(1.1, -0.4, obj_p.y);
		col = mix(col, col * vec3(0.80, 0.78, 0.72), low * wear * 0.35);

		// A dirty surface is a rougher surface.
		rough += dirt * 0.30;

		// ---- detail modes ------------------------------------------------------------------
		if (m == 1.0) {
			// Asphalt / tarmac: matte and a shade darker than the tint, with aggregate grain.
			col *= 0.80 * (0.90 + 0.20 * tex_lum);
			rough = clamp(rough + 0.15, 0.0, 1.0);
			metal = 0.0;
			spec = 0.35;
			relief_k = 0.45;
		} else if (m == 2.0) {
			// Foliage: a leafy mass, clumped and shaded into depth, not a smooth blob.
			float clump = t_vnoise3(obj_p * 2.1) * 0.6 + t_vnoise3(obj_p * 5.3 + 3.0) * 0.4;
			col *= 0.60 + 0.72 * clump;
			col = mix(col, col * vec3(1.20, 1.10, 0.78), smoothstep(0.55, 0.90, clump) * 0.40); // sun-side leaves warmer
			col = mix(col, col * vec3(0.84, 0.94, 0.86), smoothstep(0.40, 0.15, clump) * 0.35); // shaded interior cooler
			rough = clamp(rough * 0.90, 0.0, 1.0);
			metal = 0.0;
			spec = 0.35;
			relief_k = 0.55;
		} else if (m == 3.0) {
			// Grass: matte, mottled.
			float g = t_vnoise2(obj_p.xz * 0.9) * 0.5 + t_vnoise2(obj_p.xz * 3.7 + 9.0) * 0.5;
			col *= 0.84 + 0.30 * g;
			rough = clamp(rough + 0.10, 0.0, 1.0);
			metal = 0.0;
			relief_k = 0.45;
		} else if (m == 4.0) {
			// Vehicle: painted metal with light panel wear and a touch more sheen.
			float panel = smoothstep(0.86, 0.98, abs(fract(obj_p.y * 1.6 + obj_p.x * 0.05 + obj_p.z * 0.03) - 0.5) * 2.0);
			col *= 1.0 - panel * 0.10 * wear * near_k;
			rough = clamp(rough - 0.06, 0.05, 1.0);
			spec = 0.60;
			relief_k = 0.85;
		} else if (m == 5.0) {
			// Metal: smoother and more specular.
			rough = mix(rough, 0.24, 0.65);
			metal = clamp(max(metal, 0.75), 0.0, 1.0);
			spec = 0.80;
			relief_k = 0.70;
		} else {
			// 0 building: brick / render / stone / plank / tile - joints read slightly deeper.
			col = mix(col, col * vec3(0.88, 0.87, 0.86), cavity * wear * 0.25);
			rough = clamp(rough + cavity * 0.08, 0.0, 1.0);
		}
	}

	// ---- compatibility: camo patches and the darker underside tone ---------------------------------
	if (patch_amount > 0.0) {
		float pn = t_vnoise3(obj_p * patch_scale) * 0.65 + t_vnoise3(obj_p * patch_scale * 2.3) * 0.35;
		float pe = smoothstep(0.48, 0.60, pn);
		col = mix(col, patch_color.rgb, pe * patch_amount);
	}
	float under = smoothstep(-0.1, 0.25, -n.y);
	col = mix(col, underside_color.rgb, under * underside_amount);

	// ---- painted sheen -----------------------------------------------------------------------------
	rough = clamp(rough - gloss * 0.45, 0.04, 1.0);
	spec = clamp(spec + gloss * 0.30, 0.0, 1.0);

	// ---- surface relief ----------------------------------------------------------------------------
	// Small-amplitude bump derived from the texture's own luminance, so brick mortar, plank gaps and
	// stone joints catch the light and the surface stops reading as flat paint. Screen-space
	// derivative bump (Mikkelsen): no UVs or exported tangents needed. The height is mip-filtered and
	// the gradient is clamped, keeping the amplitude modest so it never breaks into speckle.
	if (!untextured) {
		float hgt = tex_lum;
		vec3 dpx = dFdx(VERTEX);
		vec3 dpy = dFdy(VERTEX);
		vec3 r1 = cross(dpy, NORMAL);
		vec3 r2 = cross(NORMAL, dpx);
		float det = dot(dpx, r1);
		float hx = clamp(dFdx(hgt), -0.05, 0.05);
		float hy = clamp(dFdy(hgt), -0.05, 0.05);
		vec3 grad = sign(det) * (hx * r1 + hy * r2);
		NORMAL = normalize(abs(det) * NORMAL - grad * (0.9 * relief_k));
	}

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = clamp(metal, 0.0, 1.0);
	SPECULAR = spec;
	EMISSION = emission_color.rgb * emission_energy;

	if (m == 2.0 && !untextured) {
		// Leaves scatter transmitted light: a little translucency so a backlit canopy glows.
		BACKLIGHT = vec3(0.42, 0.52, 0.20) * 0.6;
	}
}
