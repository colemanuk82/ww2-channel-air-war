shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;

// Inverted-hull outline. Use as `next_pass` of a toon material (see ToonUtil).
// Needs smooth normals on the mesh. Toggled globally via GameState.outlines_enabled.
global uniform float outline_enabled;
uniform vec4 outline_color : source_color = vec4(0.04, 0.04, 0.06, 1.0);
uniform float thickness = 0.035;
uniform float dist_scale = 0.00035;

void vertex() {
	if (outline_enabled < 0.5) {
		VERTEX = vec3(0.0);
	} else {
		float d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
		VERTEX += NORMAL * (thickness + d * dist_scale);
	}
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
