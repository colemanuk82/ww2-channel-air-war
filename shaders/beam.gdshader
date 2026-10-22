shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Soft light shaft for a searchlight beam. The mesh is a camera-facing quad stretched along the beam axis,
// so the beam reads as a volumetric shaft instead of the faceted polygon cone it used to be (whose facets
// showed as square patches marching up the beam). The alpha fades to nothing across the width and along the
// whole length, so the quad never brightens a visible rectangle around the beam.
uniform vec3 beam_color : source_color = vec3(0.82, 0.90, 1.0);
uniform float strength : hint_range(0.0, 2.0) = 0.45;

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;                                  // 0 at the axis, 1 at the edge
	float side = pow(1.0 - clamp(across, 0.0, 1.0), 3.0);
	float along = smoothstep(0.0, 0.03, UV.y) * (1.0 - smoothstep(0.0, 0.95, UV.y));
	ALBEDO = beam_color;
	ALPHA = side * along * strength;
}
