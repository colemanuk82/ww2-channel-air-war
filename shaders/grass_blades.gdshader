shader_type spatial;
render_mode specular_disabled, cull_disabled, depth_draw_opaque;
// Grass blade clumps on grass airfields (MultiMesh). Vertex colour: rgb = shade, a = height factor (0 root, 1 tip).
// The tips sway in the wind. The blades are lit as if they faced straight up (like the field they grow from):
// the normal is set in the fragment from the view matrix, never from an inverted model matrix - that produced
// invalid (NaN) pixels which the bloom blew up into big white glowing discs over the field (v3.13).

global uniform float wetness;
uniform vec3 tint : source_color = vec3(1.0);

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = COLOR.a * COLOR.a;
	float sw = sin(TIME * 1.7 + wp.x * 0.35 + wp.z * 0.21) * 0.6 + sin(TIME * 3.1 + wp.z * 0.9) * 0.4;
	VERTEX.x += sw * 0.045 * k;
	VERTEX.z += sw * 0.025 * k;
}

void fragment() {
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	// vertex colours are authored like the field palette (sRGB): convert, or the blades come out pale and grey
	vec3 c = pow(clamp(COLOR.rgb, vec3(0.0), vec3(1.0)), vec3(2.2)) * tint;
	c *= mix(1.0, 0.75, clamp(wetness, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
