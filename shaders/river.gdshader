shader_type spatial;
render_mode specular_disabled, cull_disabled, depth_draw_never;

#include "res://shaders/toon_common.gdshaderinc"

// River ribbon: a toon water surface that hugs the terrain. UV.x = -1..1 across the channel,
// UV.y = metres along it (arc length). Self-contained: unlike the sea it does NOT read the y=0 depth
// plane, because rivers sit in their own valleys above sea level. COLOR.r carries the waterway class
// (0 = stream, 0.5 = canal, 1 = river) so a stream reads a little narrower/hazier than a river.
// The vertex stage pulls the ribbon a hair towards the camera along the view ray (screen position is
// unchanged) so it always wins the depth test against the LOD terrain underneath (see road.gdshader).
uniform vec3 shallow_col : source_color = vec3(0.24, 0.42, 0.40);
uniform vec3 mid_col : source_color = vec3(0.16, 0.34, 0.38);
uniform vec3 deep_col : source_color = vec3(0.10, 0.23, 0.32);
uniform vec3 silt_col : source_color = vec3(0.36, 0.30, 0.20);
uniform vec3 far_col : source_color = vec3(0.31, 0.40, 0.35);
uniform float scroll_speed = 0.09;   // UV.y is arc length in metres: the flow scrolls downstream
uniform float bank_edge = 0.84;      // |UV.x| beyond which the mud / silt bank takes over

void vertex() {
	vec4 vv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = length(vv.xyz);
	vv.xyz -= normalize(vv.xyz) * (0.5 + d * 0.0016);
	POSITION = PROJECTION_MATRIX * vv;
}

global uniform vec3 sky_horizon;
global uniform vec3 sky_top;
global uniform float night_amount;

void fragment() {
	float aa = abs(UV.x);
	float along = UV.y;
	float dist = length(VERTEX);
	float cls = COLOR.r;

	// Real river water from the air: dark, peaty green-brown where you look into it, and a mirror of the sky at
	// a grazing angle (fresnel). No painted sparkle dashes - those read as road markings.
	vec3 deep = vec3(0.026, 0.036, 0.026);
	vec3 shallow = vec3(0.055, 0.062, 0.040);
	vec3 col = mix(deep, shallow, smoothstep(0.35, 0.92, aa));
	float f1 = t_vnoise2(vec2(UV.x * 3.0, along * 0.035 - TIME * scroll_speed));
	float f2 = t_vnoise2(vec2(UV.x * 9.0 + 11.0, along * 0.05 - TIME * scroll_speed * 2.1));
	col *= 0.90 + 0.20 * f1;
	// a little more silt in streams
	col = mix(col, col * vec3(1.15, 1.08, 0.9), 0.3 * (1.0 - cls));

	// fresnel sky reflection, broken up by the slow ripple pattern
	// the ribbon is drawn double-sided and its top is the BACK face (Godot flips NORMAL there), which made every
	// river a full-strength mirror: use world up instead
	// ripples: a small slope from two drifting noise layers (finite differences in channel space), faded with
	// range so distant water is a calm mirror rather than noise. The reflected ray picks sky colour from horizon
	// (grazing) to zenith (steep), so the surface shows the sky's gradient, not one flat tone.
	float rk = (1.0 - smoothstep(60.0, 650.0, dist)) * 0.22;   // ripples only near: from altitude they tiled
	vec2 rp = vec2(UV.x * 6.0, along * 0.22 - TIME * scroll_speed * 3.0);
	float r0 = t_vnoise2(rp) + 0.5 * t_vnoise2(rp * 2.7 + 4.0);
	float rx = t_vnoise2(rp + vec2(0.15, 0.0)) + 0.5 * t_vnoise2((rp + vec2(0.15, 0.0)) * 2.7 + 4.0);
	float rz = t_vnoise2(rp + vec2(0.0, 0.15)) + 0.5 * t_vnoise2((rp + vec2(0.0, 0.15)) * 2.7 + 4.0);
	vec3 wn = normalize(vec3(-(rx - r0) * rk * 6.0, 1.0, -(rz - r0) * rk * 6.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float ndv = clamp(abs(dot(NORMAL, normalize(VIEW))), 0.0, 1.0);
	float fres = 0.05 + 0.95 * pow(1.0 - ndv, 4.0);
	fres = clamp(fres, 0.0, 0.6);
	vec3 rv = reflect(-normalize(VIEW), NORMAL);
	float ry = clamp((INV_VIEW_MATRIX * vec4(rv, 0.0)).y, 0.0, 1.0);
	vec3 refl = mix(sky_horizon, sky_top, smoothstep(0.0, 0.6, ry)) * (1.0 - 0.85 * night_amount);

	// dark wet mud along both banks, then the grass verge (the terrain shows through the faded edge)
	// dark wet mud and reed margins along both banks, broken up along the channel
	float reed = t_vnoise2(vec2(along * 0.08, UV.x * 2.0 + 3.0));
	float bank = smoothstep(0.66 - 0.08 * reed, 0.95, aa);
	vec3 mud = mix(silt_col * 0.42, vec3(0.10, 0.12, 0.06), smoothstep(0.45, 0.7, reed));
	col = mix(col, mud, bank * 0.95);
	fres *= 1.0 - bank;

	// far rivers stay a quiet sheen, not graphic strips
	float far = smoothstep(2500.0, 9000.0, dist);
	col = mix(col, far_col * 0.6, far * 0.4);

	float a_water = (1.0 - smoothstep(0.94, 1.0, aa)) * mix(0.96, 0.7, smoothstep(3000.0, 9000.0, dist));
	float a_bank = (1.0 - smoothstep(0.70, 1.0, aa)) * 0.45 * (1.0 - smoothstep(2500.0, 6000.0, dist));

	ALBEDO = col;
	EMISSION = min(refl, vec3(0.8)) * fres * 0.30;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = max(a_water, a_bank);
}

void light() {
	float t = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	DIFFUSE_LIGHT += (0.25 + 0.45 * t) * LIGHT_COLOR / PI;   // water absorbs: a dark body, the sky reflection carries it
	// sun glint off the ripples (soft-edged so it never aliases into square sparkles)
	vec3 hv = normalize(LIGHT + VIEW);
	float nh = clamp(dot(NORMAL, hv), 0.0, 1.0);
	SPECULAR_LIGHT += (smoothstep(0.3, 0.9, pow(nh, 220.0)) * 0.9 + pow(nh, 40.0) * 0.08) * LIGHT_COLOR * ATTENUATION;
}
