shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled, depth_draw_never, fog_disabled;   // no fog: a far team-coloured outline must stay red / yellow

// Cel-shaded aircraft ink: a thick (2-3 px) silhouette outline, Jet Set Radio style. A `material_overlay`
// on every aircraft in the cel style, the player included (the team outline skips the player).
//
// The hull is expanded in view space and its front faces are culled, so only the ring outside the
// aircraft's own silhouette survives; the normal depth test keeps it behind the airframe. `thickness`
// and `dist_scale` are clamped so the outline stays about one NATIVE pixel wide at any range instead
// of ballooning at 5 km like an unclamped inverted hull would.

uniform vec4 ink_color : source_color = vec4(0.05, 0.05, 0.07, 1.0);
uniform float thickness = 0.06;      // world units, roughly the width of the wingtip paint line
uniform float dist_scale = 0.0011;   // grows with distance so it stays ~1 pixel on screen
uniform float max_dist = 24000.0;     // clamp: past this the sprite is a few pixels anyway
uniform bool box_hull = false;      // far stand-in boxes: inflate along sign(VERTEX) (per-face normals leave no ring)
uniform float soft_near = 0.0;       // 1 = team-coloured AI ink: thinner under ~6 km, ramping up with distance (the player's black ink keeps its full weight)
uniform float pixel_k = 1.0;         // 0 = off (same as the game's normal look)

varying float v_px;

void vertex() {
	float d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	v_px = 1.0;
	// Cap the distance term so far aircraft do not grow a slab-like outline.
	float grow = thickness + min(d, max_dist) * dist_scale;
	grow *= mix(1.0, mix(0.4, 1.0, smoothstep(1500.0, 6000.0, d)), soft_near);   // v4.31: team-coloured (AI) ink is thin up close, full size from ~6 km
	VERTEX += (box_hull ? sign(VERTEX) : NORMAL) * grow * pixel_k;
}

void fragment() {
	if (pixel_k < 0.5) {
		discard;
	}
	ALBEDO = ink_color.rgb;
}
