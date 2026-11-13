shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// Propeller blur disc: a faint, mostly clear swirl rather than a solid grey plate. Nearly clear at the hub, a
// thin smoky band through the blade span with soft blade streaks, and fading out just inside the tip circle,
// so from behind the aircraft it reads as a spinning prop, not as a translucent sphere around the nose.
// The radius is measured in the plane across the disc's thin local axis (`axis`).
uniform float radius = 1.5;
uniform int axis = 1;   // the disc's thin (spin) axis in local space: 0 x, 1 y, 2 z
uniform vec4 tint : source_color = vec4(0.13, 0.13, 0.13, 1.0);
uniform float strength = 0.08;
varying vec3 loc;

void vertex() {
	loc = VERTEX;
}

void fragment() {
	vec2 q = axis == 0 ? loc.yz : (axis == 1 ? loc.xz : loc.xy);
	float r = length(q) / max(radius, 0.01);
	float a = atan(q.y, q.x);
	float band = smoothstep(0.12, 0.35, r) * (1.0 - smoothstep(0.86, 1.0, r));
	// soft streaks (the blades smeared by the shutter), slowly turning so they never sit still
	float streak = 0.75 + 0.25 * sin(a * 3.0 + TIME * 1.7 + r * 4.0);
	ALBEDO = tint.rgb;
	ALPHA = clamp(strength * band * streak, 0.0, 1.0);
}
