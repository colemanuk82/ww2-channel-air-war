shader_type spatial;
render_mode specular_disabled, cull_back;

#include "res://shaders/toon_common.gdshaderinc"

// Toon cloud puffs for a MultiMesh. Instances are wrapped around wrap_center so the field is endless.
uniform vec4 cloud_color : source_color = vec4(1.0, 0.99, 0.96, 1.0);
uniform vec4 shade_color : source_color = vec4(0.46, 0.55, 0.72, 1.0);
uniform vec3 wrap_center = vec3(0.0);
uniform float wrap_size = 26000.0;
uniform float light_level = 1.0;

varying float v_under;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec2 rel = origin.xz - wrap_center.xz;
	vec2 wrapped = mod(rel + wrap_size * 0.5, vec2(wrap_size)) - wrap_size * 0.5;
	vec2 delta = wrapped - rel;
	float edge = 1.0 - smoothstep(0.38, 0.5, max(abs(wrapped.x), abs(wrapped.y)) / wrap_size);
	VERTEX = VERTEX * edge + vec3(delta.x, 0.0, delta.y) / max(s, 0.001);
	v_under = NORMAL.y;
}

void fragment() {
	ALBEDO = mix(shade_color.rgb, cloud_color.rgb, smoothstep(-0.35, 0.55, v_under)) * light_level;
	ROUGHNESS = 1.0;
}

void light() {
	float t = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	DIFFUSE_LIGHT += (0.45 + 0.55 * smoothstep(0.25, 0.55, t)) * LIGHT_COLOR / PI * 0.75;
}
