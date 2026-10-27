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

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = tint.rgb;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	ALPHA = clamp(opacity + fres * rim_amount, 0.04, 0.9);
	EMISSION = sky_color * fres * 0.28 + rim_color * fres * 0.08;
}

void light() {
	vec3 hv = normalize(LIGHT + VIEW);
	float nh = clamp(dot(NORMAL, hv), 0.0, 1.0);
	DIFFUSE_LIGHT += smoothstep(0.93, 0.98, nh) * glint * LIGHT_COLOR;   // hard-edged sun glint
}
