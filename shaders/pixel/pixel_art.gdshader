shader_type canvas_item;
// Pixel-art screen pass (PROMPT-pixel-art.md, phase 1). Sits on a full-screen ColorRect above the 3D
// frame and below the HUD (layer 5), and does, in this order:
//
//   1. crush the frame onto a coarse pixel grid (NATIVE pixels, nearest — no filtering);
//   2. an optional 1-px ink edge where neighbouring cells differ enough (outlines, the Slotbound look);
//   3. ordered (Bayer 8x8) dithering, applied to the same grid cell so it reads as texture, not grain;
//   4. quantise to the fixed 32-colour palette (assets/textures/pixel/palette.png, tools/make_pixel_palette.py).
//
// Everything is a uniform so the look can be tuned without a rebuild. When `enabled` is 0 the pass is
// a straight copy: the same scene renders exactly as before.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;

uniform bool enabled = true;
uniform vec2 native_size = vec2(480.0, 270.0);  // the pixel grid the frame is crushed onto
uniform vec2 out_size = vec2(1920.0, 1080.0);   // the viewport, in pixels

uniform float dither = 1.0;          // 0 = off, 1 = full Bayer
uniform float edge = 1.0;            // ink outline strength, 0 = none
uniform vec3 ink = vec3(0.047, 0.043, 0.063);   // palette entry 0, the outline colour
uniform float edge_threshold = 0.16;  // how different two cells must be to get ink between them
uniform float colour_k = 1.0;         // blend towards the palette (1 = fully quantised)
uniform float vignette = 0.0;         // optional darkening at the corners

// 8x8 Bayer, normalised to -0.5..0.5, exactly the classic ordered-dither matrix.
const float BAYER8[64] = float[64](
	0.0, 32.0, 8.0, 40.0, 2.0, 34.0, 10.0, 42.0,
	48.0, 16.0, 56.0, 24.0, 50.0, 18.0, 58.0, 26.0,
	12.0, 44.0, 4.0, 36.0, 14.0, 46.0, 6.0, 38.0,
	60.0, 28.0, 52.0, 20.0, 62.0, 30.0, 54.0, 22.0,
	3.0, 35.0, 11.0, 43.0, 1.0, 33.0, 9.0, 41.0,
	51.0, 19.0, 59.0, 27.0, 49.0, 17.0, 57.0, 25.0,
	15.0, 47.0, 7.0, 39.0, 13.0, 45.0, 5.0, 37.0,
	63.0, 31.0, 55.0, 23.0, 61.0, 29.0, 53.0, 21.0
);

// The centre of a native cell for a screen pixel: everything snaps to these, so the whole frame has
// exactly `native_size` distinct sample positions and no half-pixel shimmer.
vec2 cell_uv(vec2 frag, vec2 grid) {
	vec2 cell = floor(frag / (out_size / grid));
	return (cell + 0.5) / grid;
}

float bayer(vec2 cell) {
	ivec2 p = ivec2(mod(cell, 8.0));
	return (BAYER8[p.y * 8 + p.x] + 0.5) / 64.0 - 0.5;
}

// Nearest palette entry, compared in gamma space (what the eye sees in a 32-colour image).
vec3 quantise(vec3 c) {
	float best = 1e9;
	vec3 pick = c;
	for (int i = 0; i < 32; i++) {
		vec3 p = texelFetch(palette_tex, ivec2(i, 0), 0).rgb;
		vec3 d = (c - p) * vec3(0.9, 1.0, 0.8);   // slightly favour the greens this game is full of
		float dist = dot(d, d);
		if (dist < best) {
			best = dist;
			pick = p;
		}
	}
	return pick;
}

// A cell's colour snapped to the palette, and a per-palette-entry test that is stable enough to
// compare two cells with (see the edge pass in fragment()).
vec3 quantise_cell(vec3 c) {
	return quantise(c);
}

void fragment() {
	// No early return: Godot 4 requires a single exit from fragment().
	if (!enabled) {
		COLOR = vec4(texture(screen_tex, SCREEN_UV).rgb, 1.0);
	} else {
		vec2 grid = max(native_size, vec2(1.0));
		vec2 pix = SCREEN_UV * out_size;
		vec2 uv = cell_uv(pix, grid);
		vec2 cell = floor(pix / (out_size / grid));
		vec2 step_uv = vec2(1.0) / grid;

		// Sample the crushed grid ONCE per cell and quantise each sample, so the edge test below
		// compares palette entries with palette entries. Comparing a dithered colour against a raw one
		// (the first version of this shader did) marks every dither dot as an edge and the frame fills
		// with black speckle.
		vec3 c = quantise_cell(texture(screen_tex, uv).rgb);
		vec3 r = quantise_cell(texture(screen_tex, uv + vec2(step_uv.x, 0.0)).rgb);
		vec3 u = quantise_cell(texture(screen_tex, uv + vec2(0.0, step_uv.y)).rgb);

		// Ordered dither, applied before the palette search: this is what turns a smooth sky gradient
		// into the two-tone band Slotbound has instead of a hard mach band. Kept small - a strong
		// dither on a 32-colour palette reads as noise, not shading.
		vec3 cc = texture(screen_tex, uv).rgb + bayer(cell) * (dither * 0.030);
		c = quantise(cc);

		// Ink edges: one native pixel wide, from palette-to-palette differences only.
		if (edge > 0.001) {
			float dr = distance(c, r);
			float du = distance(c, u);
			float e = max(step(edge_threshold, dr), step(edge_threshold, du)) * edge;
			c = mix(c, ink, e);
		}

		if (vignette > 0.001) {
			vec2 v = uv - 0.5;
			c *= 1.0 - vignette * dot(v, v) * 2.0;
		}

		COLOR = vec4(c, 1.0);
	}
}
