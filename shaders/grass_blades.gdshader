shader_type spatial;
render_mode specular_disabled, cull_disabled, depth_draw_opaque;
// Grass blade clumps on grass airfields (MultiMesh). Vertex colour: rgb = shade, a = height factor (0 root, 1 tip).
// The tips sway in the wind; normals point up so the blades light like the field they grow from.

global uniform float wetness;
uniform vec3 tint : source_color = vec3(1.0);

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = COLOR.a * COLOR.a;
	float sw = sin(TIME * 1.7 + wp.x * 0.35 + wp.z * 0.21) * 0.6 + sin(TIME * 3.1 + wp.z * 0.9) * 0.4;
	VERTEX.x += sw * 0.045 * k;
	VERTEX.z += sw * 0.025 * k;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	// vertex colours are authored like the field palette (sRGB): convert, or the blades come out pale and grey
	vec3 c = pow(COLOR.rgb, vec3(2.2)) * tint;
	c *= mix(1.0, 0.75, clamp(wetness, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = 0.95;
	BACKLIGHT = c * 0.25;
}
