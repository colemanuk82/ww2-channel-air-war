shader_type spatial;
render_mode specular_schlick_ggx, cull_back, depth_draw_opaque;
// National markings (roundels, crosses, fin flash) on the glTF airframes: flat painted meshes that sit on a curved
// skin, so parts of them dipped under the wing surface (cut roundels). The vertex is pulled a little towards the
// camera, more with distance (depth precision drops), so the paint always wins over the skin it lies on.
uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform float roughness_v = 0.62;
uniform float lift = 0.035;          // metres towards the camera at close range
uniform float lift_per_m = 0.0006;   // extra per metre of distance (capped at 0.25 m)

void vertex() {
	vec3 vp = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = length(vp);
	vp -= (vp / max(d, 0.001)) * min(min(lift + d * lift_per_m, 0.25), d * 0.5);
	POSITION = PROJECTION_MATRIX * vec4(vp, 1.0);
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness_v;
	METALLIC = 0.0;
}
