shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Firelight thrown on the ground round a fire: a soft, round, flickering pool of orange draped over the terrain.
// Replaces the huge omni lights that lit a hard-edged square of ground and trees. UV.x = 0 centre .. 1 rim.
uniform vec3 glow_color = vec3(1.0, 0.42, 0.12);
uniform float intensity = 1.0;
uniform float seed = 0.0;

void fragment() {
	float r = clamp(UV.x, 0.0, 1.0);
	// a ragged rim that flickers, so the pool never reads as a perfect disc
	float wob = 0.06 * sin(TIME * 7.3 + seed + UV.y * 37.699) + 0.04 * sin(TIME * 13.1 + seed * 2.0 + UV.y * 87.965);
	float k = 1.0 - smoothstep(0.0, 1.0, r + wob * r);
	k = k * k * (0.85 + 0.15 * sin(TIME * 9.0 + seed));
	ALBEDO = glow_color * k * intensity;
	ALPHA = 1.0;
}
