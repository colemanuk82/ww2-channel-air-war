shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

#include "res://shaders/toon_common.gdshaderinc"

// Dam-breach flood water (DamFlood). Muddy grey-brown water racing downstream, churned white over the first few
// hundred metres below the gap and along the surge front, with flow streaks that scroll down the valley.
// Vertices are in world space (DamFlood keeps an identity transform).
uniform vec3 origin = vec3(0.0);
uniform vec3 flow_dir = vec3(0.0, 0.0, -1.0);
uniform float front = 0.0;           // distance of the surge front from the gap (world units)
uniform float speed = 26.0;
uniform vec3 water_col : source_color = vec3(0.30, 0.29, 0.24);
uniform vec3 foam_col : source_color = vec3(0.86, 0.88, 0.86);

varying vec3 w_pos;

void vertex() {
	w_pos = VERTEX;
}

void fragment() {
	vec2 fd = normalize(flow_dir.xz);
	vec2 rel = w_pos.xz - origin.xz;
	float along = dot(rel, fd);
	float across = rel.x * fd.y - rel.y * fd.x;
	// flow streaks: noise stretched along the flow and scrolled downstream at the flood's speed
	vec2 fp = vec2(across * 0.08, along * 0.012 - TIME * speed * 0.012);
	float n1 = t_vnoise2(fp) * 0.6 + t_vnoise2(fp * 2.7 + 4.0) * 0.4;
	float n2 = t_vnoise2(vec2(across * 0.3, along * 0.05 - TIME * speed * 0.05));
	// whitewater: just below the gap, and a band of breaking surge at the front
	float gap = 1.0 - smoothstep(60.0, 420.0, along);
	float surge = exp(-pow((along - front) / 40.0, 2.0));
	float churn = clamp(gap * (0.55 + 0.6 * n2) + surge * (0.7 + 0.5 * n1) + smoothstep(0.72, 0.9, n1) * 0.45, 0.0, 1.0);
	vec3 col = water_col * (0.85 + 0.3 * n1);
	col = mix(col, foam_col, smoothstep(0.35, 0.8, churn));
	ALBEDO = col;
	ROUGHNESS = mix(0.25, 0.9, churn);
	SPECULAR = 0.4;
	// a ragged leading edge instead of a straight cut-off
	float edge = smoothstep(front + 6.0, front - 18.0, along + (n1 - 0.5) * 30.0);
	ALPHA = clamp(edge, 0.0, 1.0) * 0.96;
	ALPHA_SCISSOR_THRESHOLD = 0.35;
}
