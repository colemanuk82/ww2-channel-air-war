shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Dim airfield lamp: a soft round glow billboard that only shows at night (global night_amount, set by TimeOfDay).
// It grows with distance so a lamp is still a faint dot from a few kilometres out.
global uniform float night_amount;
varying vec4 vcol;

void vertex() {
	vcol = COLOR;
	vec4 origin_view = VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0);
	float d = length(origin_view.xyz);
	float s = 1.8 + d * 0.012;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= s;
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float g = pow(clamp(1.0 - r, 0.0, 1.0), 2.4);
	ALBEDO = vcol.rgb * 1.6;
	ALPHA = g * night_amount * vcol.a;
}
