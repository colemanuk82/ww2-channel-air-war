shader_type spatial;
render_mode specular_disabled, cull_disabled, depth_draw_never;

#include "res://shaders/toon_common.gdshaderinc"

// Road ribbon: a subtle, slightly translucent worn-asphalt mark with soft (anti-aliased) edges and NO paint.
// It fades toward the ground colour with distance so roads read as faint lines, not graphic strips.
// UV.x = -1..1 across the road, UV.y = metres along it.
// The vertex shader pulls the ribbon slightly towards the camera along the view ray (screen position is
// unchanged) so it always wins the depth test against the LOD terrain mesh under it.
uniform vec3 asphalt : source_color = vec3(0.30, 0.31, 0.30);
uniform vec3 far_color : source_color = vec3(0.36, 0.39, 0.31);

void vertex() {
	vec4 vv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = length(vv.xyz);
	vv.xyz -= normalize(vv.xyz) * (0.6 + d * 0.0018);
	POSITION = PROJECTION_MATRIX * vv;
}

void fragment() {
	float aa = abs(UV.x);
	float along = UV.y;
	float dist = length(VERTEX);
	if (COLOR.g > 0.5) {
		// Railway, kept subtle: a stone verge (gravel shoulder) that blends into the fields on either side, a darker
		// ballast bed in the middle with faint sleepers, and two muted steel rails. Rails widen and the whole thing
		// fades toward the field colour with distance so it never reads as a graphic strip.
		float w = 0.035 + dist * 0.000028;
		float rail_l = 1.0 - smoothstep(w * 0.6, w, abs(aa - 0.17));
		float sl = smoothstep(0.35, 0.5, abs(fract(along / 2.2) - 0.5) * 2.0);
		float gn = t_vnoise2(vec2(along * 0.9, UV.x * 7.0));
		vec3 verge = vec3(0.45, 0.43, 0.38) * (0.88 + 0.24 * gn);
		vec3 bed = vec3(0.27, 0.25, 0.22) * (0.9 + 0.2 * gn);
		vec3 tie = vec3(0.34, 0.29, 0.24);
		vec3 steel = vec3(0.50, 0.52, 0.54);
		float in_bed = 1.0 - smoothstep(0.26, 0.34, aa);
		vec3 rc = mix(verge, bed, in_bed);
		rc = mix(rc, tie, (1.0 - sl) * in_bed * (1.0 - smoothstep(700.0, 1800.0, dist)) * step(aa, 0.24));
		rc = mix(rc, steel, rail_l * (1.0 - smoothstep(1500.0, 4000.0, dist) * 0.6));
		rc = mix(rc, far_color, smoothstep(600.0, 4500.0, dist) * 0.75);
		float rail_edge = 1.0 - smoothstep(0.55, 1.0, aa);
		ALBEDO = rc;
		ROUGHNESS = 1.0;
		ALPHA = rail_edge * mix(0.95, 0.55, smoothstep(1200.0, 6000.0, dist));
	} else {
		// Road: worn tarmac with darker wheel tracks, a pale gravelly edge and NO painted lines (1940s roads were unmarked). Detail fades out with distance so far roads stay faint.
		float ra = aa * 1.5;
		float sgn = UV.x * 1.5;
		float near = 1.0 - smoothstep(350.0, 2200.0, dist);
		float grain = t_vnoise2(vec2(along * 0.35, UV.x * 4.0));
		float patch = t_vnoise2(vec2(along * 0.045, UV.x * 1.3));
		vec3 col = asphalt * (0.88 + 0.22 * grain) * (0.93 + 0.14 * patch);
		float tracks = smoothstep(0.17, 0.0, abs(abs(sgn) - 0.5)) * 0.14 * near;
		col *= 1.0 - tracks;
		float gravel = smoothstep(0.80, 0.90, ra) * (1.0 - smoothstep(0.93, 1.0, ra));
		col = mix(col, vec3(0.50, 0.47, 0.40) * (0.9 + 0.2 * grain), gravel * 0.7);
		col = mix(col, far_color, smoothstep(500.0, 4500.0, dist));
		float a_road = (1.0 - smoothstep(0.88, 1.0, ra)) * mix(0.93, 0.5, smoothstep(1200.0, 6500.0, dist));
		vec3 grass = vec3(0.30, 0.40, 0.22) * (0.9 + 0.2 * t_vnoise2(vec2(along * 0.12, UV.x * 3.0)));
		grass = mix(grass, far_color, smoothstep(500.0, 4500.0, dist));
		float a_verge = (1.0 - smoothstep(0.6, 1.0, aa)) * 0.30 * (1.0 - smoothstep(2500.0, 6000.0, dist));
		float alpha = max(a_road, a_verge);
		ALBEDO = mix(grass, col, clamp(a_road / max(alpha, 0.001), 0.0, 1.0));
		ROUGHNESS = 1.0;
		ALPHA = alpha;
	}
}

void light() {
	float t = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	DIFFUSE_LIGHT += toon_band(t) * LIGHT_COLOR / PI;
}
