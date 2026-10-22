class_name MenuPosters
extends Control
## Original period-style home-front posters on the start menu, drawn procedurally: flat colour, block type and
## simple shapes. Every design is invented for this game (no real posters are reproduced). Cycles slowly.

const HOLD := 12.0
const FADE := 1.0

var _i: int = 0
var _t: float = 0.0
var _b: float = 1.0          # brightness: 1 = fully shown, 0 = dark between two posters
var _phase: int = 0          # 0 = hold, 1 = fade out, 2 = fade in


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(220, 310)


func _process(delta: float) -> void:
	_t += delta
	match _phase:
		0:
			if _t >= HOLD:
				_phase = 1
				_t = 0.0
		1:
			_b = clampf(1.0 - _t / FADE, 0.0, 1.0)
			if _t >= FADE:
				_i = (_i + 1) % 4          # swap the design while the card is dark
				_phase = 2
				_t = 0.0
				_b = 0.0
		_:
			_b = clampf(_t / FADE, 0.0, 1.0)
			if _t >= FADE:
				_phase = 0
				_t = 0.0
				_b = 1.0
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	match _i:
		0:
			_poster_sortie(r)
		1:
			_poster_channel(r)
		2:
			_poster_factory(r)
		_:
			_poster_quiet(r)
	# fade overlay so the card dims between designs
	draw_rect(r, Color(0.02, 0.02, 0.02, 1.0 - _b))
	draw_rect(r, Color(0.1, 0.08, 0.05), false, 3.0)


func _text(pos: Vector2, s: String, px: int, col: Color, width: float = -1.0) -> void:
	draw_string(ThemeDB.fallback_font, pos, s, HORIZONTAL_ALIGNMENT_CENTER, width, px, col)


func _poster_sortie(r: Rect2) -> void:
	draw_rect(r, Color(0.93, 0.89, 0.78))
	draw_rect(Rect2(0, 0, r.size.x, 92), Color(0.62, 0.12, 0.10))
	_text(Vector2(0, 40), "KEEP", 34, Color(0.97, 0.93, 0.85), r.size.x)
	_text(Vector2(0, 74), "YOUR SORTIE", 20, Color(0.97, 0.93, 0.85), r.size.x)
	# a simple bomber silhouette
	var c := Vector2(r.size.x * 0.5, 175.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-80, 0), c + Vector2(-20, -14), c + Vector2(40, -14), c + Vector2(80, -4), c + Vector2(40, 2), c + Vector2(-20, 6)]), Color(0.18, 0.2, 0.22))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-10, -2), c + Vector2(-40, -48), c + Vector2(-28, -48), c + Vector2(8, -2)]), Color(0.18, 0.2, 0.22))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-10, 4), c + Vector2(-40, 50), c + Vector2(-28, 50), c + Vector2(8, 4)]), Color(0.18, 0.2, 0.22))
	_text(Vector2(0, 252), "TO YOURSELF", 22, Color(0.12, 0.1, 0.08), r.size.x)
	_text(Vector2(0, 286), "The sky has ears.", 14, Color(0.3, 0.26, 0.2), r.size.x)


func _poster_channel(r: Rect2) -> void:
	draw_rect(r, Color(0.07, 0.14, 0.24))
	for k in 5:
		var y: float = 180.0 + k * 22.0
		var pts := PackedVector2Array()
		for x in range(0, int(r.size.x) + 10, 10):
			pts.append(Vector2(x, y + sin(x * 0.06 + k) * 5.0))
		draw_polyline(pts, Color(0.35, 0.6, 0.8, 0.6), 2.0)
	_text(Vector2(0, 46), "THE CHANNEL", 26, Color(0.95, 0.82, 0.3), r.size.x)
	_text(Vector2(0, 80), "IS A WALL", 26, Color(0.95, 0.82, 0.3), r.size.x)
	_text(Vector2(0, 126), "HOLD IT.", 24, Color(0.95, 0.95, 0.9), r.size.x)
	_text(Vector2(0, 280), "Every convoy is a bet", 14, Color(0.8, 0.85, 0.9), r.size.x)


func _poster_factory(r: Rect2) -> void:
	draw_rect(r, Color(0.36, 0.38, 0.22))
	# works chimneys and sawtooth roofs
	for k in 4:
		var x: float = 22.0 + k * 48.0
		draw_rect(Rect2(x, 190, 36, 80), Color(0.2, 0.22, 0.13))
		draw_rect(Rect2(x + 26, 150, 8, 40), Color(0.2, 0.22, 0.13))
	draw_rect(Rect2(0, 268, r.size.x, 40), Color(0.18, 0.2, 0.11))
	_text(Vector2(0, 60), "PRODUCTION", 26, Color(0.96, 0.92, 0.7), r.size.x)
	_text(Vector2(0, 92), "WINS THE SKY", 22, Color(0.96, 0.92, 0.7), r.size.x)
	_text(Vector2(0, 130), "Night shifts count.", 15, Color(0.92, 0.9, 0.75), r.size.x)


func _poster_quiet(r: Rect2) -> void:
	draw_rect(r, Color(0.12, 0.3, 0.3))
	draw_circle(Vector2(r.size.x * 0.5, 170.0), 56.0, Color(0.95, 0.9, 0.75))
	draw_circle(Vector2(r.size.x * 0.5, 170.0), 56.0, Color(0.12, 0.3, 0.3, 0.0))
	_text(Vector2(0, 52), "WHO KNOWS", 24, Color(0.95, 0.92, 0.8), r.size.x)
	_text(Vector2(0, 84), "THE DAY?", 24, Color(0.95, 0.92, 0.8), r.size.x)
	_text(Vector2(0, 262), "Not the enemy.", 18, Color(0.95, 0.92, 0.8), r.size.x)
	_text(Vector2(0, 292), "Keep it that way.", 14, Color(0.8, 0.9, 0.85), r.size.x)
