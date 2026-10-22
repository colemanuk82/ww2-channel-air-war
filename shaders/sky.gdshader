shader_type sky;

// Realistic sky. A continuous, elevation-driven vertical gradient (hazy horizon -> deeper zenith),
// aerial-perspective haze, a soft forward-scatter glow with a smooth sun disc, and a night sky of
// stars, a faint Milky Way band and a moon with a soft halo. No banding, no quantised steps.
//
// The palette and the sun/moon paths are supplied each frame by TimeOfDay (scripts/time_of_day.gd);
// this shader only shapes them by the sun's ELEVATION and adds the scattering a static palette cannot:
//  * high sun  -> blue zenith, pale warm horizon
//  * low sun   -> warm orange/red band near the horizon with a deep blue above
//  * below the horizon -> night, dark blue-black zenith
// It is drawn over the whole screen every frame, so it stays a handful of cheap maths ops.

uniform vec3 top_color : source_color = vec3(0.22, 0.5, 0.88);       // zenith
uniform vec3 horizon_color : source_color = vec3(0.72, 0.84, 0.95); // horizon (== the world fog colour)
uniform vec3 ground_color : source_color = vec3(0.35, 0.4, 0.45);    // below the horizon
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);                          // towards the sun
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);                        // towards the moon
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.8);        // sun-light colour (warm when low)
uniform float star_amount = 0.0;                                     // 0 day .. 1 night

// 0 = full day, 1 = full night. Registered in project.godot [shader_globals] and set by TimeOfDay.
global uniform float night_amount;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 sdir = normalize(sun_dir);
	float elev = sdir.y;                     // sun elevation, -1..1: the master control for the sky

	// --- lighting and warmth, both read straight off the sun's elevation ---
	float day = smoothstep(-0.18, 0.10, elev);   // 1 with the sun up, 0 once it is well below
	float upward = clamp(h, 0.0, 1.0);

	vec3 col;
	if (h >= 0.0) {
		// Rayleigh-like vertical profile: compress toward the horizon so the hazy band is thin and
		// open into the zenith. Continuous everywhere - no steps.
		float zenith_t = smoothstep(0.0, 1.0, pow(upward, 0.55));
		col = mix(horizon_color, top_color, zenith_t);
		// aerial perspective: a slightly whiter wash in the lowest ~10 degrees, so the horizon is
		// hazier than the zenith and agrees with the fog colour the world uses.
		float haze = exp(-h * 9.0);
		col = mix(col, mix(horizon_color, vec3(1.0), 0.18), haze * 0.35 * (0.4 + 0.6 * day));
	} else {
		// below the horizon the sky fades from the horizon colour into the ground colour
		col = mix(horizon_color, ground_color, smoothstep(0.0, -0.30, h));
	}

	// --- azimuth: how far this ray points toward (1) or away from (0) the sun ---
	vec2 dh = normalize(vec2(d.x, d.z) + vec2(1e-5));
	vec2 sh = normalize(vec2(sdir.x, sdir.z) + vec2(1e-5));
	float az = dot(dh, sh) * 0.5 + 0.5;
	float sunw = az * az * (3.0 - 2.0 * az);   // smooth, sharpened toward the sun

	// warmth that peaks at the horizon crossing (dawn/dusk) and fades toward noon and night
	float warm = exp(-abs(elev) * 4.5);
	vec3 warm_col = mix(sun_color, vec3(1.0, 0.60, 0.34), 0.5 * warm);

	// --- forward-scatter glow: wide and soft at low sun, tight near noon ---
	float sd = dot(d, sdir);
	float core = pow(max(sd, 0.0), mix(5.0, 40.0, smoothstep(-0.05, 0.45, elev)));  // low exponent = wide bloom
	float halo = pow(max(sd, 0.0), 1.7) * 0.10;                                     // very broad, subtle
	col += warm_col * (core + halo) * day * (0.35 + 0.9 * warm);
	// a horizon-hugging bloom toward the sun, strongest when the sun sits low
	col += warm_col * exp(-max(h, 0.0) * 6.0) * sunw * day * (0.25 + 0.9 * warm);

	// --- sun disc: small, smooth-edged, driven above 1.0 so the bloom pass catches it ---
	float disc = smoothstep(0.99955, 0.99985, sd) * smoothstep(-0.03, 0.03, elev);
	col = mix(col, mix(vec3(1.0, 0.97, 0.92), sun_color, 0.6) * 8.0, disc);

	// --- moon: a cool soft halo plus a disc, only at night and above the horizon ---
	vec3 mdir = normalize(moon_dir);
	float md = dot(d, mdir);
	float moon_vis = smoothstep(-0.03, 0.05, mdir.y) * night_amount;
	if (moon_vis > 0.001) {
		float mdisc = smoothstep(0.9990, 0.9996, md);
		float mhalo = pow(max(md, 0.0), 200.0);
		col += vec3(0.86, 0.89, 1.0) * (mdisc * 1.4 + mhalo * 0.35) * moon_vis;
	}

	// --- night sky: stars fading in as the sun drops, over a faint Milky Way band ---
	float night = clamp(max(star_amount, night_amount), 0.0, 1.0);
	if (night > 0.002 && h > -0.02) {
		float above = smoothstep(0.0, 0.16, h);   // dimmer down in the thicker air near the horizon
		// Milky Way: a diffuse band of unresolved stars along a fixed great circle, with dust lanes
		vec3 mw_n = normalize(vec3(0.30, 0.22, 0.93));
		float mt = dot(d, mw_n);
		// smooth band (no per-cell noise, which read as blocky squares) and kept faint
		float mw = exp(-mt * mt * 30.0);
		col += vec3(0.50, 0.55, 0.72) * mw * night * above * 0.03;
		// stars: one candidate per cell, gently coloured, brightest overhead
		vec3 p = d * 190.0;
		vec3 c = floor(p);
		float rnd = hash13(c);
		float cell = hash12(c.xy + c.z * 1.7);
		vec3 fr = fract(p) - 0.5;
		float s = smoothstep(0.5, 0.02, length(fr)) * step(0.990, rnd);
		vec3 st_col = mix(vec3(0.82, 0.88, 1.0), vec3(1.0, 0.90, 0.76), cell);
		col += st_col * s * (0.45 + 0.5 * cell) * night * above * 0.75;
	}

	// Sub-LSB dither so the smooth gradient does not show 8-bit banding rings.
	col += (hash13(floor(d * 2048.0)) - 0.5) * (1.5 / 255.0);

	COLOR = col;
}
