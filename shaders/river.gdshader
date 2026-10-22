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

void fragment() {
	float aa = abs(UV.x);
	float along = UV.y;
	float dist = length(VERTEX);
	float cls = COLOR.r;

	// Banded depth across the channel: deeper in the middle, shelving to the banks.
	vec3 col = mix(deep_col, mid_col, smoothstep(0.0, 0.45, aa));
	col = mix(col, shallow_col, smoothstep(0.45, 0.85, aa));

	// Flow: two scrolling noise bands down the arc length. Streams are hazier, rivers greener.
	float f1 = t_vnoise2(vec2(UV.x * 3.0, along * 0.035 - TIME * scroll_speed));
	float f2 = t_vnoise2(vec2(UV.x * 7.0 + 11.0, along * 0.09 - TIME * scroll_speed * 2.1));
	col *= 0.92 + 0.16 * (f1 * 0.6 + f2 * 0.4);
	col = mix(col, col * vec3(0.90, 1.02, 0.96), 0.12 * (1.0 - cls));
	// sunward sparkle on the moving ripples
	col += vec3(0.10, 0.12, 0.09) * smoothstep(0.80, 0.97, f2);

	// Mud / silt bank tint at the ribbon edges (the terrain shows through if the DEM is un-carved).
	float bank = smoothstep(bank_edge, 1.0, aa);
	col = mix(col, silt_col, bank * 0.85);

	// Distance fade toward the field colour so far rivers stay faint, not graphic strips.
	col = mix(col, far_col, smoothstep(2500.0, 9000.0, dist) * 0.7);

	float a_water = (1.0 - smoothstep(0.94, 1.0, aa)) * mix(0.94, 0.6, smoothstep(3000.0, 9000.0, dist));
	float a_bank = (1.0 - smoothstep(0.70, 1.0, aa)) * 0.35 * (1.0 - smoothstep(2500.0, 6000.0, dist));

	ALBEDO = col;
	ROUGHNESS = 1.0;
	ALPHA = max(a_water, a_bank);
}

void light() {
	float t = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	DIFFUSE_LIGHT += (0.40 + toon_band(t) * 0.60) * LIGHT_COLOR / PI;
}
