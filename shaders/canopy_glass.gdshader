shader_type spatial;
render_mode specular_disabled, blend_mix, depth_draw_never;

// Stylised cockpit glazing: mostly clear head-on so the airframe shows through, with a bright
// fresnel rim at grazing angles and a hard sun glint band, so the canopy reads as glass from outside.

uniform vec4 tint : source_color = vec4(0.60, 0.72, 0.78, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.22;
uniform float rim_amount : hint_range(0.0, 2.0) = 0.5;
uniform vec3 rim_color : source_color = vec3(0.85, 0.93, 1.0);
uniform vec3 sky_color : source_color = vec3(0.58, 0.70, 0.86);
uniform float glint : hint_range(0.0, 3.0) = 0.35;
// Cel-shaded style only (Aircraft sets it 1.0, 0.0 in Realistic): a light sky-tinted haze over the glass and
// two crisp white anime glint bands that slide with the view and the sun. 0 = the original glass exactly.
uniform float cel_k = 0.0;
global uniform vec3 sun_dir_world;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = tint.rgb;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	ALPHA = clamp(opacity + fres * rim_amount, 0.04, 0.9);
	EMISSION = sky_color * fres * 0.28 + rim_color * fres * 0.08;
	if (cel_k > 0.5) {
		// veil: the interior reads slightly hazy, tinted by the sky
		ALBEDO = mix(tint.rgb, sky_color, 0.55);
		ALPHA = clamp(ALPHA + 0.26, 0.0, 0.92);
		EMISSION += sky_color * 0.16;
		// hard glints: a wide and a thin diagonal band in view space, offset by where the sun is, plus a
		// sun-facing facet highlight; small and crisp, never a mirror
		vec3 sv = normalize((VIEW_MATRIX * vec4(normalize(sun_dir_world), 0.0)).xyz);
		vec3 loc = VERTEX - NODE_POSITION_VIEW;
		float d = dot(loc.xy, vec2(0.82, 0.57)) + sv.x * 0.12;
		float b1 = 1.0 - smoothstep(0.035, 0.045, abs(d - 0.07));
		float b2 = 1.0 - smoothstep(0.010, 0.016, abs(d + 0.05));
		float nh = dot(normalize(NORMAL), normalize(sv + VIEW));
		float facet = smoothstep(0.965, 0.972, nh);
		float streak = clamp(max(max(b1, b2) * 0.9, facet), 0.0, 1.0);
		EMISSION += vec3(1.0) * streak * 1.6;
		ALBEDO = mix(ALBEDO, vec3(1.0), streak);
		ALPHA = max(ALPHA, streak * 0.95);
	}
}

void light() {
	vec3 hv = normalize(LIGHT + VIEW);
	float nh = clamp(dot(NORMAL, hv), 0.0, 1.0);
	DIFFUSE_LIGHT += smoothstep(0.93, 0.98, nh) * glint * LIGHT_COLOR;   // hard-edged sun glint
}
