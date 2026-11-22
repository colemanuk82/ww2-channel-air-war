shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, skip_vertex_transform;
// Cel-shaded screen pass (Options > Video > Art style > Cel-shaded). A full-screen quad parented to the
// active camera (scripts/cel_shade.gd) that reads the finished opaque frame, its depth and its normals and
//   1. flattens the lighting into 3 hard bands (lit / mid / cool shadow) per hue and saturates it,
//   2. draws black ink lines where depth or normals jump (full resolution, width scales with the window),
//   3. gives the sky and clouds a clean banded look with a soft ink edge on the clouds.
// Everything is a uniform. When the pass is hidden (Realistic) none of this runs.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D nr_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;

uniform vec2 view_px = vec2(1920.0, 1080.0);
uniform float line_px = 2.5;            // ink width in pixels at 1080p (scaled by view height)
uniform float ink_strength = 1.0;
uniform vec3 ink_col : source_color = vec3(0.015, 0.012, 0.03);
uniform float depth_thresh = 0.012;     // relative depth second-difference that counts as an edge
uniform float normal_thresh = 0.75;     // 1 - dot(n, n') that counts as a crease
uniform float line_near = 700.0;        // ink at full strength inside this range (m)
uniform float line_far = 3500.0;        // ... and gone beyond this
uniform float normal_far = 650.0;       // creases fade out much sooner (foliage normals are noisy)
uniform float band_lo = 0.15;           // luminance (sqrt space) below which a pixel is in the shadow band
uniform float band_hi = 0.34;           // ... and above which it is in the lit band
uniform float shadow_mul = 0.68;
uniform float mid_mul = 1.0;
uniform float lit_mul = 1.18;
uniform float flatten = 0.5;           // 0 = keep texture brightness inside a band, 1 = fully flat bands
uniform vec3 band_levels = vec3(0.03, 0.11, 0.24);   // luminance each band flattens to
uniform float saturation = 1.4;
uniform float saturation_green = 1.12;
uniform float water_blue = 0.9;
uniform vec3 shadow_tint = vec3(0.80, 0.84, 1.12);
uniform float sky_sat = 1.9;           // sky / cloud saturation boost
uniform float sky_bands = 0.0;          // how hard the sky / clouds are banded (0 = untouched)
uniform float cloud_ink = 0.55;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// Linear view depth from the depth texture. A perspective projection's inverse only needs the z / w rows
// (they do not depend on x / y, jitter included), so this is two multiply-adds instead of a mat4 * vec4.
float lin_depth(vec2 uv, vec4 zw) {
	float d = textureLod(depth_tex, uv, 0.0).x;
	if (d <= 0.000001) {
		return 1.0e5;          // sky
	}
	return -(zw.x * d + zw.y) / (zw.z * d + zw.w);
}
float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 cel_light(vec3 c, float l_blur) {
	// band on perceptual (sqrt) luminance of a lightly blurred sample, so grass texture does not speckle
	float g = sqrt(max(l_blur, 0.0));
	float w = 0.02;
	float s_mid = smoothstep(band_lo - w, band_lo + w, g);
	float s_hi = smoothstep(band_hi - w, band_hi + w, g);
	float mul = mix(shadow_mul, mid_mul, s_mid);
	mul = mix(mul, lit_mul, s_hi);
	vec3 tint = mix(shadow_tint, vec3(1.0), s_mid);
	float lum = max(luma(c), 0.0001);
	float lvl = mix(band_levels.x, band_levels.y, s_mid);
	lvl = mix(lvl, band_levels.z, s_hi);
	vec3 hue = c / lum;
	vec3 col = mix(c * mul, hue * lvl, flatten) * tint;
	float gl = luma(col);
	// vivid but not neon: greens are pushed far less than other hues and nudged towards teal, so fields,
	// hedges and woods keep distinct hues instead of merging into one acid green
	float greenness = clamp((col.g - col.b) / max(gl + 0.02, 0.02) * 0.9, 0.0, 1.0) * step(col.r * 0.88, col.g);   // yellow-greens (grass, pasture) count as green; gold (red > green) does not
	float warm = step(col.g, col.r) * step(col.b, col.g) * (1.0 - greenness);   // mustard / gold / brown
	float sat = mix(saturation, saturation_green, greenness);
	sat = mix(sat, sat * 0.86, warm);
	col = mix(vec3(gl), col, sat);
	col.b += 0.14 * greenness * col.g;
	col.g *= 1.0 + 0.10 * greenness;
	col.r *= (1.0 - 0.18 * greenness) * (1.0 - 0.07 * warm);
	col.g *= 1.0 + 0.05 * warm;      // olive / mustard grass leans green, not yellow
	// water and other blue-ish surfaces: clearly blue with a deeper value, not a pale grey slab
	float blueness = clamp((col.b - max(col.r, col.g * 0.92)) / max(gl + 0.02, 0.02), 0.0, 1.0);
	col = mix(col, col * vec3(0.72, 0.93, 1.3) * 0.9, blueness * water_blue);
	return max(col, vec3(0.0));
}

void fragment() {
	vec4 zw = vec4(INV_PROJECTION_MATRIX[2][2], INV_PROJECTION_MATRIX[3][2], INV_PROJECTION_MATRIX[2][3], INV_PROJECTION_MATRIX[3][3]);
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / view_px;
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;
	float dc = lin_depth(uv, zw);
	bool is_sky = dc > 5.0e4;

	float w = line_px * max(view_px.y / 1080.0, 0.5);
	vec2 o = px * (w * 0.5);
	vec2 o2 = o * 2.0;

	float dcl = min(dc, 5.0e4);
	float edge = 0.0;
	float crease = 0.0;
	// Ink only exists inside line_far, so every pixel beyond it (the sea and fields to the horizon, most of a
	// flight frame) skips all the depth and normal taps: same result, a fraction of the texture reads.
	if (dcl < line_far) {
		float dl = lin_depth(uv - vec2(o.x, 0.0), zw);
		float dr = lin_depth(uv + vec2(o.x, 0.0), zw);
		float du = lin_depth(uv - vec2(0.0, o.y), zw);
		float dd = lin_depth(uv + vec2(0.0, o.y), zw);
		float dl2 = lin_depth(uv - vec2(o2.x, 0.0), zw);
		float dr2 = lin_depth(uv + vec2(o2.x, 0.0), zw);
		float du2 = lin_depth(uv - vec2(0.0, o2.y), zw);
		float dd2 = lin_depth(uv + vec2(0.0, o2.y), zw);
		// one-sided second difference: positive only when THIS pixel is the nearer side of a step, so the ink
		// sits on the object, never on the sky behind it; zero on any flat plane however grazing
		float e1 = max(dl + dr - 2.0 * dc, du + dd - 2.0 * dc);
		float e2 = max(dl2 + dr2 - 2.0 * dc, du2 + dd2 - 2.0 * dc);
		float e = max(e1, e2 * 0.7);
		edge = step(depth_thresh * dcl + 0.03, e);
		edge *= 1.0 - smoothstep(line_near, line_far, dcl);
		if (dcl < normal_far) {      // creases are gone beyond normal_far: no normal taps there
			vec3 nc = textureLod(nr_tex, uv, 0.0).xyz * 2.0 - 1.0;
			vec3 nl = textureLod(nr_tex, uv - vec2(o2.x, 0.0), 0.0).xyz * 2.0 - 1.0;
			vec3 nr = textureLod(nr_tex, uv + vec2(o2.x, 0.0), 0.0).xyz * 2.0 - 1.0;
			vec3 nu = textureLod(nr_tex, uv - vec2(0.0, o2.y), 0.0).xyz * 2.0 - 1.0;
			vec3 nd = textureLod(nr_tex, uv + vec2(0.0, o2.y), 0.0).xyz * 2.0 - 1.0;
			float nd_max = max(max(1.0 - dot(nc, nl), 1.0 - dot(nc, nr)), max(1.0 - dot(nc, nu), 1.0 - dot(nc, nd)));
			// only where the depth is continuous: a depth step is already inked above
			float dsec = abs(dl + dr - 2.0 * dc) / max(dcl, 1.0) + abs(du + dd - 2.0 * dc) / max(dcl, 1.0);
			float cont = 1.0 - smoothstep(0.004, 0.03, dsec);
			crease = step(normal_thresh, nd_max) * cont * (1.0 - smoothstep(normal_far * 0.35, normal_far, dcl));
		}
	}
	vec3 col;
	if (is_sky) {
		float lc = luma(c);
		vec3 sr = textureLod(screen_tex, uv + vec2(o2.x, 0.0), 0.0).rgb;
		vec3 sl = textureLod(screen_tex, uv - vec2(o2.x, 0.0), 0.0).rgb;
		vec3 su = textureLod(screen_tex, uv - vec2(0.0, o2.y), 0.0).rgb;
		vec3 sd = textureLod(screen_tex, uv + vec2(0.0, o2.y), 0.0).rgb;
		float grad = max(abs(luma(sr) - luma(sl)), abs(luma(su) - luma(sd)));
		float ce = smoothstep(0.045, 0.14, grad) * cloud_ink;
		float band = floor(sqrt(max(lc, 0.0)) * 5.0 + 0.5) / 5.0;
		vec3 banded = c * ((band * band) / max(lc, 0.0001));
		col = mix(c, banded, sky_bands);
		float gl = luma(col);
		col = mix(vec3(gl), col, sky_sat);
		col = mix(col, ink_col * 2.0 + col * 0.25, ce);
	} else {
		vec2 r1 = o2 * 2.5;
		float lb = luma(c) * 2.0;
		lb += luma(textureLod(screen_tex, uv + vec2(r1.x, 0.0), 0.0).rgb);
		lb += luma(textureLod(screen_tex, uv - vec2(r1.x, 0.0), 0.0).rgb);
		lb += luma(textureLod(screen_tex, uv + vec2(0.0, r1.y), 0.0).rgb);
		lb += luma(textureLod(screen_tex, uv - vec2(0.0, r1.y), 0.0).rgb);
		lb += luma(textureLod(screen_tex, uv + r1 * 0.7, 0.0).rgb);
		lb += luma(textureLod(screen_tex, uv - r1 * 0.7, 0.0).rgb);
		lb += luma(textureLod(screen_tex, uv + vec2(r1.x, -r1.y) * 0.7, 0.0).rgb);
		lb += luma(textureLod(screen_tex, uv + vec2(-r1.x, r1.y) * 0.7, 0.0).rgb);
		lb /= 10.0;
		col = cel_light(c, lb);
		col = mix(col, ink_col, clamp(max(edge, crease), 0.0, 1.0) * ink_strength);
	}
	ALBEDO = col;
}
