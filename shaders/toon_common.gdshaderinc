// Shared toon helpers: 4-band stepped light ramp + noise.
float toon_band(float t) {
	float w = 0.02;
	return 0.30
		+ 0.25 * smoothstep(0.08 - w, 0.08 + w, t)
		+ 0.25 * smoothstep(0.40 - w, 0.40 + w, t)
		+ 0.20 * smoothstep(0.72 - w, 0.72 + w, t);
}

float t_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float t_hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float t_vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(t_hash13(i), t_hash13(i + vec3(1, 0, 0)), f.x);
	float b = mix(t_hash13(i + vec3(0, 1, 0)), t_hash13(i + vec3(1, 1, 0)), f.x);
	float c = mix(t_hash13(i + vec3(0, 0, 1)), t_hash13(i + vec3(1, 0, 1)), f.x);
	float d = mix(t_hash13(i + vec3(0, 1, 1)), t_hash13(i + vec3(1, 1, 1)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

float t_vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = t_hash12(i);
	float b = t_hash12(i + vec2(1, 0));
	float c = t_hash12(i + vec2(0, 1));
	float d = t_hash12(i + vec2(1, 1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
