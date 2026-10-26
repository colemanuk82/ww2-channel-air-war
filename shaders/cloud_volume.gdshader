shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_front, shadows_disabled;

#include "res://shaders/toon_common.gdshaderinc"

// Raymarched volumetric clouds, physically-flavoured lighting in the spirit of Blackrack's KSP clouds
// (Beer-powder extinction, dual-lobe Henyey-Greenstein phase with a silver lining, multi-scatter
// approximation, sky ambient with interior occlusion). Four cloud types: see cloud_density().
// Raymarched volumetric cumulus. Each cloud is a box proxy (mesh spans -1..1) scaled to the cloud's
// radii; the fragment shader marches the camera ray through a noise-eroded ellipsoid, lights each
// sample with a short march toward the sun (self-shadowing) plus forward-scatter "silver lining", and
// stops at the scene depth so terrain and aircraft occlude correctly. cull_front means the back faces
// draw, so it also works when the camera is inside the cloud.
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 shade_color : source_color = vec4(0.62, 0.7, 0.82, 1.0);
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.2);
uniform float light_level = 1.0;
uniform float density_scale = 1.0;     // extinction multiplier (weather: heavier = darker, denser)
uniform float fade_near = 30000.0;
uniform float fade_far = 45000.0;
// detail setting (GameState.cloud_detail): march step multiplier, step cap, sun-light sample every Nth step
uniform float step_k = 1.0;
uniform int max_steps = 60;
uniform int light_every = 2;
instance uniform float seed = 0.0;
instance uniform float ctype = 0.0;   // 0 cumulus, 1 towering cumulus / anvil, 2 stratocumulus deck, 3 cirrus, 4 altocumulus,
                                      // 5 lenticular, 6 castellanus, 7 cirrocumulus, 8 congestus, 9 stratus
instance uniform float nfreq = 2.1;   // noise frequency (bigger clouds get finer lumps)

varying vec3 l_cam;
varying vec3 l_pos;
varying vec3 l_sun;
varying vec3 w_pos;
varying float v_ry;
varying vec3 v_sc;
varying vec3 l_up;

void vertex() {
	mat4 inv_m = inverse(MODEL_MATRIX);
	l_pos = VERTEX;
	l_cam = (inv_m * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	l_sun = (inv_m * vec4(normalize(sun_dir), 0.0)).xyz;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_ry = length(MODEL_MATRIX[1].xyz);
	v_sc = vec3(length(MODEL_MATRIX[0].xyz), v_ry, length(MODEL_MATRIX[2].xyz));
	l_up = (inv_m * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

float hg(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * c, 1.5);
}

float fbm3(vec3 p) {
	return t_vnoise3(p) * 0.55 + t_vnoise3(p * 2.2) * 0.30 + t_vnoise3(p * 4.7) * 0.15;
}

// Density at a point in unit-ellipsoid space (|p| <= 1 inside the proxy), shaped per cloud type.
// Noise is sampled in world metres (p * sc) so lump size is the same on a small puff and a huge massif.
float cloud_density(vec3 p, float sd, float ty, vec3 sc) {
	vec3 off = vec3(sd * 13.1, sd * 3.7, sd * 7.9);
	if (ty < 0.5) {
		// cumulus humilis/mediocris: flat base, domed lumpy top
		float flat_k = mix(1.0, 1.55, fract(sd * 0.173));      // per cloud: rounder mediocris .. flat humilis
		// low-frequency warp so the outline is never a clean ellipse
		vec3 wp = p + (vec3(t_vnoise3(p * 1.6 + off), 0.0, t_vnoise3(p * 1.6 + off + 4.1)) - 0.5) * 0.3;
		vec3 q = vec3(wp.x, wp.y < 0.0 ? wp.y * 1.55 : wp.y * 1.05 * flat_k, wp.z);   // softer, rounder underside
		float shape = 1.0 - length(q) * 1.12;
		// two extra lumps, placed and sized per cloud: a heap of billows rather than one dome
		for (int li = 0; li < 2; li++) {
			float fi = float(li);
			vec2 h = vec2(fract(sin(sd * 12.9 + fi * 78.2) * 43758.5), fract(sin(sd * 39.3 + fi * 11.7) * 24634.6));
			vec3 lc = vec3((h.x - 0.5) * 0.7, 0.05 + h.y * 0.25, (h.y - 0.5) * 0.6 * (fi < 0.5 ? 1.0 : -1.0));
			float lr = 0.36 + 0.2 * h.x;
			vec3 lq = (q - lc * vec3(1.0, flat_k, 1.0)) / lr;
			shape = max(shape, (1.0 - length(lq)) * lr * 1.25);
		}
		if (shape <= -0.35) { return 0.0; }
		float n = fbm3(p * sc / 300.0 + off);
		float d0 = shape * 1.45 - 0.30 + (n - 0.5) * 1.15;
		d0 -= 0.24 * (1.0 - clamp(d0, 0.0, 1.0)) * t_vnoise3(p * sc / 95.0 + off);   // fine billow erosion at the edges
		return clamp(d0, 0.0, 1.0);
	} else if (ty < 1.5) {
		// cumulonimbus: narrower base, tall billowing tower, anvil flare at the top
		float fl = 1.0 + 0.85 * smoothstep(0.40, 0.95, p.y);
		float wd = mix(0.62, 1.0, smoothstep(-0.9, 0.3, p.y)) * fl;
		vec3 q = vec3(p.x / wd, p.y < -0.15 ? (p.y + 0.15) * 2.4 : p.y * 0.92, p.z / wd);
		float shape = 1.0 - length(q);
		if (shape <= -0.35) { return 0.0; }
		vec3 np = p * sc / vec3(340.0, 420.0, 340.0) + off;
		float n = fbm3(np);
		float d1 = shape * 1.35 - 0.24 + (n - 0.5) * 1.05;
		d1 -= 0.22 * (1.0 - clamp(d1, 0.0, 1.0)) * t_vnoise3(np * 2.9);
		return clamp(d1, 0.0, 1.0);
	} else if (ty < 2.5) {
		// stratocumulus: broad low deck broken into lumpy rolls with gaps
		vec2 ws = p.xz + (vec2(t_vnoise3(p * 1.3 + off), t_vnoise3(p * 1.3 + off + 3.3)) - 0.5) * 0.4;
		float shape = min(1.0 - length(ws) * 1.08, 1.0 - abs(p.y) * 1.15);
		if (shape <= -0.35) { return 0.0; }
		vec3 np = p * sc / vec3(480.0, 260.0, 480.0) + off;
		float n = fbm3(np);
		float rolls = t_vnoise3(p * sc / vec3(1300.0, 400.0, 1300.0) + off * 1.3);   // broken into rolls with gaps
		return clamp(shape * 1.1 - 0.2 + (n - 0.5) * 1.5 + (rolls - 0.5) * 1.1, 0.0, 1.0);
	}
	if (ty > 4.5) {
		if (ty < 5.5) {
			// lenticular: a smooth lens, thick in the middle, razor thin at the rim; some are stacked plates
			float r2 = dot(p.xz, p.xz);
			float half_t = 0.85 * (1.0 - r2);
			if (half_t <= 0.0) { return 0.0; }
			vec3 npl = p * sc / vec3(900.0, 160.0, 900.0) + off;
			float nl = t_vnoise3(npl) * 0.7 + t_vnoise3(npl * 2.3) * 0.3;
			float lens = (half_t - abs(p.y)) / max(half_t, 0.05);
			float dl = smoothstep(0.0, 0.35, lens) * (0.75 + 0.35 * nl) - 0.08;
			if (fract(sd * 0.37) > 0.45) {
				float plate = 0.5 + 0.5 * cos(p.y * 3.14159 * 3.0);     // three plates with clear gaps
				dl *= smoothstep(0.30, 0.75, plate);
			}
			return clamp(dl * 1.2, 0.0, 1.0);
		} else if (ty < 6.5) {
			// castellanus: a thin flat base with turrets climbing out of it
			float foot = 1.0 - length(p.xz);
			if (foot <= -0.1) { return 0.0; }
			vec2 g = p.xz * sc.xz / 380.0 + off.xz;
			vec2 id = floor(g);
			vec2 f = fract(g) - 0.5;
			float hc = t_hash12(id + vec2(sd, sd * 1.7));
			float top = hc > 0.45 ? mix(0.0, 1.0, (hc - 0.45) / 0.55) : -0.6;   // fewer, taller turrets
			top *= smoothstep(-0.1, 0.5, foot);                        // shorter turrets toward the edge
			float rise = clamp((p.y + 0.55) / 1.5, 0.0, 1.0);
			float rad = 0.30 * (1.0 - 0.3 * rise) + 0.06 * sin(p.y * 9.0 + hc * 20.0);   // narrow, knobbly columns
			float col = rad - length(f);
			float tower = min(col * 6.0, (top - p.y) * 4.0);
			float base_slab = 0.5 - abs(p.y + 0.65) * 4.0;
			vec3 npc = p * sc / 110.0 + off;
			float nc = fbm3(npc);
			float dc = max(tower, base_slab) + (nc - 0.5) * 0.6;
			return clamp(dc * smoothstep(-0.1, 0.25, foot), 0.0, 1.0);
		} else if (ty < 7.5) {
			// cirrocumulus: a thin sheet of tiny cells in ripples, with holes
			float shc = min(1.0 - length(p.xz) * 0.97, 1.0 - abs(p.y) * 1.4);
			if (shc <= -0.1) { return 0.0; }
			vec2 w = p.xz * sc.xz;
			vec2 warp = vec2(t_vnoise3(vec3(w / 900.0, sd)), t_vnoise3(vec3(w / 900.0 + 7.3, sd))) * 70.0;
			vec2 g2 = (w + warp * 1.6) / vec2(150.0, 190.0) + off.xz;
			vec2 id2 = floor(g2);
			float h1 = t_hash12(id2 + sd);
			float h2 = t_hash12(id2 * 1.37 + sd + 5.1);
			vec2 f2 = fract(g2) - 0.5 - (vec2(h1, h2) - 0.5) * 0.35;      // jittered cell centres
			float cell = mix(0.16, 0.44, h2) - length(f2 * vec2(1.0, 1.3));  // uneven cell sizes
			cell += (t_vnoise3(vec3(w / 70.0, sd)) - 0.5) * 0.18;            // ragged cell edges
			float rows = 0.55 + 0.45 * sin((w.x + warp.y * 3.0) / 420.0);   // ripple rows
			float holes = t_vnoise3(vec3(w / 1400.0, sd * 2.0));
			float dcc = smoothstep(0.0, 0.2, cell) * rows * smoothstep(0.30, 0.55, holes) * smoothstep(-0.1, 0.4, shc);
			return clamp(dcc * 0.75, 0.0, 1.0);
		} else if (ty < 8.5) {
			// congestus: tall cauliflower, narrowing to a rounded crown, hard-edged billows
			float wd2 = mix(0.78, 1.0, smoothstep(-0.8, -0.1, p.y)) * mix(1.0, 0.72, smoothstep(0.15, 1.0, p.y));
			vec3 q2 = vec3(p.x / wd2, p.y < -0.2 ? (p.y + 0.2) * 2.6 : p.y * 0.86, p.z / wd2);
			float shg = 1.0 - length(q2);
			if (shg <= -0.4) { return 0.0; }
			vec3 npg = p * sc / 280.0 + off;
			float ng = fbm3(npg);
			float bulge = t_vnoise3(npg * 0.45);
			float dg = shg * 1.45 - 0.26 + (ng - 0.5) * 1.25 + (bulge - 0.5) * 0.55;
			dg -= 0.26 * (1.0 - clamp(dg, 0.0, 1.0)) * t_vnoise3(npg * 3.1);
			return clamp(dg * 1.3, 0.0, 1.0);
		}
		// stratus: a low featureless grey sheet with a soft ragged underside
		float shs = min(1.0 - length(p.xz) * 0.98, 1.0 - abs(p.y) * 1.2);
		if (shs <= -0.2) { return 0.0; }
		vec3 nps = p * sc / vec3(1600.0, 220.0, 1600.0) + off;
		float ns = fbm3(nps);
		float under = p.y < 0.0 ? t_vnoise3(p * sc / 140.0 + off) * 0.35 * (-p.y) : 0.0;
		return clamp((shs * 1.7 + (ns - 0.5) * 0.7 - under) * 0.8, 0.0, 1.0);
	}
	if (ty > 3.5) {
		// altocumulus: flat mid-level cloudlets in small cells
		vec2 wa = p.xz + (vec2(t_vnoise3(p * 1.4 + off), t_vnoise3(p * 1.4 + off + 2.7)) - 0.5) * 0.4;
		float sh = min(1.0 - length(wa) * 1.1, 1.0 - abs(p.y) * 1.2);
		if (sh <= -0.35) { return 0.0; }
		vec3 npa = p * sc / vec3(260.0, 120.0, 260.0) + off;
		float na = fbm3(npa);
		float lumps = t_vnoise3(p * sc / vec3(520.0, 200.0, 520.0) + off * 1.7);
		return clamp(sh * 1.05 - 0.2 + (na - 0.5) * 1.8 + (lumps - 0.5) * 0.9, 0.0, 1.0);
	}
	// cirrus: thin wispy streaks stretched along the cloud's long axis
	float shape = 1.0 - length(vec3(p.x * 0.85, p.y * 1.3, p.z));
	if (shape <= -0.2) { return 0.0; }
	vec3 np = p * sc / vec3(2600.0, 230.0, 320.0) + off;
	float n = fbm3(np);
	return clamp((shape * 1.1 + (n - 0.58) * 1.7 - 0.22) * 0.5, 0.0, 1.0);
}

void fragment() {
	vec3 ro = l_cam;
	vec3 rd = normalize(l_pos - l_cam);
	float b = dot(ro, rd);
	float c = dot(ro, ro) - 1.0;
	float h = b * b - c;
	if (h <= 0.0) { discard; }
	h = sqrt(h);
	float t0 = max(-b - h, 0.0);
	float t1 = -b + h;
	// world metres per local unit along this ray
	float wl = length((MODEL_MATRIX * vec4(rd, 0.0)).xyz);

	// Clip the march at the opaque scene (terrain, aircraft).
	float depth = texture(depth_tex, SCREEN_UV).x;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_dist = length(vp.xyz / vp.w);
	t1 = min(t1, scene_dist / wl);
	if (t1 <= t0) { discard; }

	float dist_cam = length(w_pos - CAMERA_POSITION_WORLD);
	// fewer steps for far clouds (they cover few pixels)
	float span_m = (t1 - t0) * wl;
	float step_m = dist_cam < 4000.0 ? 55.0 : (dist_cam < 12000.0 ? 90.0 : 150.0);
	int steps = int(clamp(span_m / (step_m * step_k), 8.0, float(max_steps)));
	float dt = (t1 - t0) / float(steps);
	float jitter = t_hash12(FRAGCOORD.xy);
	float t = t0 + dt * jitter;

	vec3 wdir = normalize(w_pos - CAMERA_POSITION_WORLD);
	vec3 sdir = normalize(sun_dir);
	float cs = dot(wdir, sdir);
	// dual-lobe phase: broad back-scatter plus a strong forward lobe for the silver lining
	float phase = mix(hg(cs * -1.0 * -1.0, -0.25), hg(cs, 0.66), 0.16) * 0.95;
	float ty = ctype;
	float tm = ty < 0.5 ? 1.0 : (ty < 1.5 ? 1.3 : (ty < 2.5 ? 0.75 : (ty < 3.5 ? 0.32 : (ty < 4.5 ? 0.55 :
		(ty < 5.5 ? 0.8 : (ty < 6.5 ? 0.9 : (ty < 7.5 ? 0.35 : (ty < 8.5 ? 1.15 : 0.7))))))));
	bool thin_hi = (ty > 2.5 && ty < 3.5) || (ty > 6.5 && ty < 7.5);     // cirrus, cirrocumulus
	float sigma_m = 0.014 * density_scale * tm;     // extinction per world metre at density 1
	float sd = seed;
	float sh1 = clamp(v_ry * 0.30, 60.0, 360.0);
	float sh2 = sh1 * 2.3;

	float T = 1.0;
	vec3 acc = vec3(0.0);
	float od = 0.0;        // sun optical depth and sky occlusion are refreshed every other step (cost)
	float up_occ = 1.0;
	for (int i = 0; i < 60; i++) {
		if (i >= steps) { break; }
		vec3 p = ro + rd * t;
		float d = cloud_density(p, sd, ty, v_sc);
		if (d > 0.005) {
			float sig = d * sigma_m * dt * wl;
			// optical depth toward the sun: three samples with growing spacing (integrated by segment length)
			if ((i % light_every) == 0 && !thin_hi) {
				float da = cloud_density(p + l_sun * sh1 * 0.4, sd, ty, v_sc);
				float db = cloud_density(p + l_sun * sh1, sd, ty, v_sc);
				float dc = cloud_density(p + l_sun * sh1 * 2.2, sd, ty, v_sc);
				od = sigma_m * sh1 * (da * 0.4 + db * 0.6 + dc * 1.2);
				// sky light reaching this sample from above
				up_occ = exp(-cloud_density(p + l_up * sh1 * 0.9, sd, ty, v_sc) * sigma_m * sh1 * 0.9);
			}
			float beer = exp(-od);
			float powder = 1.0 - exp(-od * 2.0 - 0.15);
			float sun_t = beer * mix(1.0, powder * 2.0, 0.55) + 0.34 * exp(-od * 0.10);   // + multi-scatter floor
			float height_k = clamp(p.y * 0.5 + 0.55, 0.0, 1.0);
			vec3 sun_e = cloud_color.rgb * 1.05 * sun_t * phase;
			vec3 amb = mix(shade_color.rgb * 0.76, shade_color.rgb * 0.64 + cloud_color.rgb * 0.40, height_k) * (0.42 + 0.58 * up_occ);
			vec3 col = sun_e + amb * (thin_hi ? 1.4 : 1.0);
			if (thin_hi) { col = mix(col, cloud_color.rgb, 0.55); }   // cirrus / cirrocumulus: bright, high, thin
			if (ty > 8.5) { col *= 0.86; }                          // stratus: flat grey
			float a = 1.0 - exp(-sig);
			acc += T * a * col;
			T *= 1.0 - a;
			if (T < 0.03) { break; }
		}
		t += dt;
	}
	float alpha = 1.0 - T;
	float fade = 1.0 - smoothstep(fade_near, fade_far, dist_cam);
	ALBEDO = min(acc / max(alpha, 0.001) * light_level, vec3(1.15));
	ALPHA = clamp(alpha, 0.0, 1.0) * fade;
}
