shader_type canvas_item;
render_mode blend_add, unshaded;

// Screen-space light shafts (crepuscular rays): each pixel marches toward the sun's screen position and gathers
// the bright sky it passes; clouds and terrain in between are darker and so cut the light into rays.
// Driven by SunGlare: sun_uv, amount (0 = off), tint.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec2 sun_uv = vec2(0.5);
uniform float amount = 0.0;
uniform vec3 tint = vec3(1.0, 0.85, 0.6);
uniform float threshold = 0.84;
const int STEPS = 40;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 delta = (uv - sun_uv) / float(STEPS) * 0.9;
	vec2 p = uv;
	float decay = 1.0;
	float acc = 0.0;
	for (int i = 0; i < STEPS; i++) {
		p -= delta;
		if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) break;
		vec3 c = textureLod(screen_tex, p, 1.5).rgb;
		float l = dot(c, vec3(0.299, 0.587, 0.114));
		acc += max(l - threshold, 0.0) * decay;
		decay *= 0.93;
	}
	float d = length((uv - sun_uv) * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0));
	float fall = 1.0 / (1.0 + d * 4.0);
	COLOR = vec4(tint * min(acc * 0.06, 0.35) * amount * fall, 1.0);
}
