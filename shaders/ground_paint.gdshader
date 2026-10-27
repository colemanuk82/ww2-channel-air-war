shader_type spatial;
render_mode specular_schlick_ggx, cull_back, depth_draw_opaque;

#include "res://shaders/toon_common.gdshaderinc"

// Built ground props (Nissen huts, blister hangars, lorries, guns, tents, sandbags, crates, huts...): the same matte
// painted look as the aircraft skins (aircraft_pbr) instead of the old cel shading, so the airfield and the aircraft
// on it read as one world. `albedo` is the paint or material colour (GroundKit.mat); weathering is procedural in
// object space: uneven paint from panel to panel, dust and bleaching on top faces, rain runs down the walls, mud
// splashed along the bottom and darker undersides. Fine detail fades with range so nothing shimmers from altitude.
uniform vec4 albedo : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform bool use_vcol = false;          // albedo x vertex colour (Scatter merges same-material parts into one draw)
uniform float roughness_v : hint_range(0.0, 1.0) = 0.82;
uniform float metallic_v : hint_range(0.0, 1.0) = 0.03;
uniform float wear : hint_range(0.0, 1.0) = 0.6;

varying vec3 obj_p;
varying vec3 obj_n;
varying vec3 w_pos;

void vertex() {
	obj_p = VERTEX;
	obj_n = normalize(NORMAL);
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = albedo.rgb;
	if (use_vcol) {
		col *= COLOR.rgb;
	}
	vec3 n = normalize(obj_n);
	float cam = length(w_pos - CAMERA_POSITION_WORLD);
	float near_k = 1.0 - smoothstep(150.0, 1200.0, cam);

	// uneven paint / material tone, coarse (never aliases)
	float tone = t_vnoise3(obj_p * 0.45 + 3.0) * 0.6 + t_vnoise3(obj_p * 1.7 + 11.0) * 0.4;
	col *= 0.90 + 0.20 * tone;

	float up = smoothstep(0.30, 0.95, n.y);
	float vert = 1.0 - smoothstep(0.30, 0.80, abs(n.y));
	// dust settled on the top faces, and the paint there bleached by the sun
	col = mix(col, col * 1.07 + vec3(0.022, 0.020, 0.014), up * 0.35 * wear);
	// rain runs down the walls
	vec2 suv = vec2(obj_p.x * 2.6 + obj_p.z * 2.6, obj_p.y * 0.12);
	float streak = smoothstep(0.45, 0.92, t_vnoise2(suv) * 0.6 + t_vnoise2(suv * 2.3 + 17.0) * 0.4) * vert * near_k;
	col *= 1.0 - streak * 0.22 * wear;
	// mud splashed up along the bottom
	float low = smoothstep(0.9, -0.1, obj_p.y) * vert;
	col = mix(col, vec3(0.20, 0.17, 0.12), low * 0.40 * wear * (0.6 + 0.4 * t_vnoise2(obj_p.xz * 3.0 + obj_p.y)));
	// undersides in shadow and grime
	col *= 1.0 - smoothstep(0.20, 0.95, -n.y) * 0.35;

	ALBEDO = col;
	ROUGHNESS = clamp(roughness_v + streak * 0.10, 0.05, 1.0);
	METALLIC = metallic_v;
	SPECULAR = 0.45;
}
