shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled, depth_draw_never;

// Pixel-art aircraft ink (PROMPT-pixel-art.md): a hard 1-2 px silhouette outline, the way a pixel-art
// sprite is drawn. Used as a `material_overlay` on every aircraft in pixel mode, INCLUDING the player
// (the game's team_outline skips the player, which is why the player's aircraft read as a dark blob
// against the sea once the frame is crushed to 480x270).
//
// The hull is expanded in view space and its front faces are culled, so only the ring outside the
// aircraft's own silhouette survives; the normal depth test keeps it behind the airframe. `thickness`
// and `dist_scale` are clamped so the outline stays about one NATIVE pixel wide at any range instead
// of ballooning at 5 km like an unclamped inverted hull would.

uniform vec4 ink_color : source_color = vec4(0.05, 0.05, 0.07, 1.0);
uniform float thickness = 0.06;      // world units, roughly the width of the wingtip paint line
uniform float dist_scale = 0.0011;   // grows with distance so it stays ~1 pixel on screen
uniform float max_dist = 4000.0;     // clamp: past this the sprite is a few pixels anyway
uniform float pixel_k = 1.0;         // 0 = off (same as the game's normal look)

varying float v_px;

void vertex() {
	float d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	v_px = 1.0;
	// Cap the distance term so far aircraft do not grow a slab-like outline.
	float grow = thickness + min(d, max_dist) * dist_scale;
	VERTEX += NORMAL * grow * pixel_k;
}

void fragment() {
	if (pixel_k < 0.5) {
		discard;
	}
	ALBEDO = ink_color.rgb;
}
