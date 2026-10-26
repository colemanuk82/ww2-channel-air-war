class_name TrainingFilm
extends Control
## Animated training film: chapters on the HUD gauges and on dogfighting technique, drawn as moving diagrams with
## captions (no footage, all drawn in code). Opened from the start menu; Space pauses, Left / Right change chapter,
## Esc closes. `start_chapter` / `start_time` let a debug run jump straight to a frame.

signal closed

const FRIEND := Color(1.0, 0.85, 0.1)
const FOE := Color(1.0, 0.22, 0.14)
const GOOD := Color(0.45, 0.9, 0.5)
const WARN := Color(1.0, 0.72, 0.2)
const BAD := Color(1.0, 0.32, 0.24)
const HOT := Color(1.0, 0.04, 0.02)
const COOL := Color(0.45, 0.75, 1.0)
const INK := Color(0.95, 0.92, 0.82)
const DIM := Color(0.78, 0.75, 0.66, 0.8)
const PAPER := Color(0.06, 0.075, 0.09)
const GRID := Color(0.2, 0.26, 0.3, 0.55)

## [title, duration seconds, [[start second, caption], ...]]
const CHAPTERS := [
	["Welcome", 9.0, [[0.0, "Your flying school: how the instruments work and how to win a dogfight."], [4.5, "Use Left / Right to change chapter, Space to pause, Esc to leave."]]],
	["Flying: pitch, roll, yaw", 22.0, [[0.0, "W / S pitches the nose up and down. Pull back to climb or turn."], [7.0, "A / D rolls the wings. Roll first, then pull: that is how you turn."], [14.0, "Q / E yaws the nose left and right. Small corrections to line up a shot."], [19.0, "Let go of the stick and press R: the auto-level assist rights the aircraft."]]],
	["Throttle, boost, energy", 20.0, [[0.0, "The green arc on the left of the airspeed dial is your throttle. Shift raises it, Ctrl lowers it."], [7.0, "The orange arc on the right is boost. Hold Tab for a burst of extra power."], [13.0, "When boost runs dry the arc turns red and it is locked until it recharges."], [17.0, "Speed is energy. Keep it high: it buys you climbs, turns and escapes."]]],
	["Airspeed and stall", 18.0, [[0.0, "The airspeed dial reads in km/h. The needle sweeps round as you speed up."], [5.0, "Red zone: stall. The wings stop flying and the nose drops. Keep the needle out of it."], [10.0, "Green zone: normal flying. Amber: faster than the aircraft's top speed, a dive only."], [14.5, "Never pull hard at low speed: you will stall and spin."]]],
	["Altitude, climb, gear, flaps", 18.0, [[0.0, "The altimeter shows height above the sea in metres."], [6.0, "Climbing or diving shows on the climb readout. Height is safety and speed in the bank."], [11.0, "G raises or lowers the undercarriage. F steps the flaps. V is the wheel brake."], [15.0, "Landing: gear down, flaps down, slow, and keep the nose up at the end."]]],
	["Engine heat and wear", 20.0, [[0.0, "The outer arc on the right of the airspeed dial is engine temperature. Blue is cold, amber is warm."], [7.0, "Too long at full power or boost, and it flashes bright red: the engine is overheating."], [13.0, "Ease the throttle and stop boosting to cool it. There is no warning text, only the gauge."], [17.0, "The thin outer arc is wear: it builds up when you abuse the engine."]]],
	["G-force and blackouts", 20.0, [[0.0, "The G arc on the altimeter shows how hard you are pulling, in G."], [7.0, "Above about 6.5 G, or below -2 G, the arc turns bright red."], [11.0, "Hold it too long and your vision greys out from the edges, then you black out."], [16.0, "Ease off the stick and your sight returns. Enemy pilots black out too: make them pull hard."]]],
	["Hull and damage", 14.0, [[0.0, "The hull arc on the altimeter is your aircraft's health."], [5.0, "Pale gold is healthy. Amber is hurt. Red is critical: one more burst and you are going down."], [10.0, "If it is hopeless, hold J to bail out, with enough height for the parachute."]]],
	["Dogfight 1: lead pursuit", 24.0, [[0.0, "Never aim at the enemy. A bullet takes time to arrive, and he is moving."], [6.0, "Aim where he WILL be: put the nose in front of him along his flight path. That is lead."], [13.0, "The tighter he turns, the more lead you need. Fire when the target flies into your stream."], [19.0, "Staying inside his turning circle lets you keep him in your sight."]]],
	["Dogfight 2: boom and zoom", 22.0, [[0.0, "Start high. Height is energy you can trade for speed."], [6.0, "Dive on him from behind, fast. Fire one short burst as you close."], [13.0, "Do not stay and turn. Use your speed to zoom back up to height."], [18.0, "Repeat. He can never turn with you, and you pick when to fight."]]],
	["Dogfight 3: turns and scissors", 24.0, [[0.0, "Fighting in a turn costs speed. The slower fighter gets stuck in the circle."], [7.0, "If he gets on your tail, reverse your turn each time he is about to shoot."], [14.0, "Each reversal makes him swing wide. Crossing paths are the scissors."], [19.0, "The first to overshoot loses. Keep your speed and your nerve."]]],
	["Dogfight 4: break and overshoot", 24.0, [[0.0, "He is on your tail. Do not fly straight: that gets you shot."], [6.0, "Break hard INTO him with a tight turn. Roll and pull as hard as you can."], [13.0, "Close in fast, he overshoots and ends up in front of you."], [19.0, "Throttle back a little to make it worse for him, then take the shot."]]],
	["Dogfight 5: Immelmann and split-S", 20.0, [[0.0, "Immelmann: a half loop up, then roll upright. You gain height and turn round."], [9.0, "Split-S: roll upside down and pull through a half loop. You lose height but gain speed."], [15.0, "Use the Immelmann when you have speed to spare, the split-S to escape."]]],
	["Tips and controls", 16.0, [[0.0, "K: target view locks the camera onto the nearest aircraft."], [4.0, "M: map. [ and ]: time warp on long flights. . (full stop): next music track."], [8.0, "Space: fire. X or B: switch guns, rockets and bombs. N: bombsight. L: gunner view."], [12.0, "Options > Gameplay turns the lead marker on if you want help aiming."]]],
]

var start_chapter: int = 0
var start_time: float = 0.0

var _ch: int = 0
var _t: float = 0.0
var _paused: bool = false
var _font: Font
var _buttons: Array = []
var _stage: Rect2 = Rect2()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = UIKit.body_font()
	size = get_viewport_rect().size
	_ch = clampi(start_chapter, 0, CHAPTERS.size() - 1)
	_t = start_time
	var side := VBoxContainer.new()
	side.position = Vector2(20, 76)
	side.custom_minimum_size = Vector2(236, 0)
	side.add_theme_constant_override("separation", 4)
	add_child(side)
	for i in CHAPTERS.size():
		var idx: int = i
		var b: Button = UIKit.button("%d  %s" % [i + 1, String(CHAPTERS[i][0])], func() -> void: _goto(idx), 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(236, 30)
		side.add_child(b)
		_buttons.append(b)
	var close := UIKit.button("Close  (Esc)", func() -> void: _close(), 18, true)
	close.position = Vector2(20, 18)
	close.custom_minimum_size = Vector2(236, 40)
	add_child(close)
	_refresh_buttons()


func _goto(i: int) -> void:
	_ch = clampi(i, 0, CHAPTERS.size() - 1)
	_t = 0.0
	_paused = false
	_refresh_buttons()


func _refresh_buttons() -> void:
	for i in _buttons.size():
		(_buttons[i] as Button).modulate = Color(1, 1, 1, 1) if i == _ch else Color(0.8, 0.8, 0.8, 0.75)


func _close() -> void:
	closed.emit()
	queue_free()


func _input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k: int = (e as InputEventKey).physical_keycode
	if k == KEY_ESCAPE:
		_close()
	elif k == KEY_SPACE:
		_paused = not _paused
	elif k == KEY_RIGHT:
		_goto((_ch + 1) % CHAPTERS.size())
	elif k == KEY_LEFT:
		_goto((_ch - 1 + CHAPTERS.size()) % CHAPTERS.size())
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	size = get_viewport_rect().size    # parented to a CanvasLayer: no anchors to size it
	if not _paused:
		_t += delta
		if _t >= float(CHAPTERS[_ch][1]):
			if _ch + 1 < CHAPTERS.size():
				_goto(_ch + 1)
			else:
				_t = float(CHAPTERS[_ch][1])
	queue_redraw()


# ------------------------------------------------------------------------------------------------ drawing helpers

func _txt(p: Vector2, s: String, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0) -> void:
	draw_string(_font, p, s, align, w, size, col)


func _arc(ctr: Vector2, rad: float, a0: float, a1: float, col: Color, wd: float) -> void:
	if absf(a1 - a0) < 0.001:
		return
	draw_arc(ctr, rad, a0, a1, maxi(8, int(absf(a1 - a0) * 14.0)), col, wd, true)


## One of the arcs wrapped round a dial. `left` true: fills bottom to top up the left; false: up the right.
func _meter(ctr: Vector2, rad: float, left: bool, frac: float, col: Color, wd: float = 7.0) -> void:
	var f: float = clampf(frac, 0.0, 1.0)
	if left:
		_arc(ctr, rad, PI * 0.5, PI * 0.5 + PI * 0.98, Color(1, 1, 1, 0.1), wd)
		_arc(ctr, rad, PI * 0.5, PI * 0.5 + PI * 0.98 * f, col, wd)
	else:
		_arc(ctr, rad, PI * 0.5, PI * 0.5 - PI * 0.98, Color(1, 1, 1, 0.1), wd)
		_arc(ctr, rad, PI * 0.5, PI * 0.5 - PI * 0.98 * f, col, wd)


func _dial_face(ctr: Vector2, r: float) -> void:
	draw_circle(ctr, r + 4.0, Color(0.55, 0.5, 0.38, 0.9))
	draw_circle(ctr, r, Color(0.08, 0.09, 0.09, 1.0))
	for i in 28:
		var a: float = deg_to_rad(135.0 + 270.0 * float(i) / 27.0)
		var d := Vector2(cos(a), sin(a))
		var big: bool = i % 3 == 0
		draw_line(ctr + d * (r - (16.0 if big else 10.0)), ctr + d * (r - 4.0), Color(INK, 0.85 if big else 0.4), 2.0 if big else 1.0)


func _needle(ctr: Vector2, r: float, frac: float, col: Color = Color(1.0, 0.95, 0.8)) -> void:
	var a: float = deg_to_rad(135.0 + 270.0 * clampf(frac, 0.0, 1.0))
	var d := Vector2(cos(a), sin(a))
	draw_line(ctr - d * 14.0, ctr + d * (r - 20.0), col, 4.0, true)
	draw_circle(ctr, 7.0, Color(0.7, 0.62, 0.45))


func _callout(from: Vector2, to: Vector2, s: String, col: Color, a: float) -> void:
	if a <= 0.01:
		return
	var c := Color(col, a)
	draw_line(from, to, c, 2.0, true)
	draw_circle(from, 4.0, c)
	var w: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 24.0
	var rect := Rect2(to.x - (0.0 if to.x >= from.x else w), to.y - 18.0, w, 36.0)
	rect.position.x = clampf(rect.position.x, 8.0, size.x - w - 40.0)    # keep the label on screen
	draw_rect(rect, Color(0.04, 0.05, 0.06, 0.85 * a), true)
	draw_rect(rect, Color(c, 0.9 * a), false, 1.5)
	_txt(rect.position + Vector2(12.0, 25.0), s, 20, Color(INK, a))


func _show(t: float, t0: float, fade: float = 0.6) -> float:
	return clampf((t - t0) / fade, 0.0, 1.0)


## A top-down fighter silhouette facing `ang` (radians, 0 = right).
func _plane(p: Vector2, ang: float, sz: float, col: Color, wingspread: float = 1.0) -> void:
	var half: Array = [Vector2(1.0, 0.0), Vector2(0.4, 0.1), Vector2(0.18, 0.95 * wingspread), Vector2(-0.05, 0.95 * wingspread),
		Vector2(-0.12, 0.12), Vector2(-0.7, 0.1), Vector2(-0.8, 0.42), Vector2(-0.97, 0.42), Vector2(-1.0, 0.0)]
	var pts := PackedVector2Array()
	for v in half:
		pts.append(p + (v as Vector2).rotated(ang) * sz)
	for i in range(half.size() - 2, 0, -1):
		var v2: Vector2 = half[i]
		pts.append(p + Vector2(v2.x, -v2.y).rotated(ang) * sz)
	draw_colored_polygon(pts, col)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.6), 1.5)


## A side-on fighter silhouette; `up` = -1 draws it inverted.
func _plane_side(p: Vector2, ang: float, sz: float, col: Color, up: float = 1.0) -> void:
	var shape: Array = [Vector2(1.0, 0.0), Vector2(0.45, -0.17), Vector2(-0.4, -0.15), Vector2(-0.88, -0.55), Vector2(-1.0, -0.55),
		Vector2(-0.95, -0.02), Vector2(-0.6, 0.1), Vector2(0.4, 0.16)]
	var pts := PackedVector2Array()
	for v in shape:
		var q: Vector2 = v
		pts.append(p + Vector2(q.x, q.y * up).rotated(ang) * sz)
	draw_colored_polygon(pts, col)


func _trail(pts: Array, col: Color, w: float = 3.0) -> void:
	if pts.size() < 2:
		return
	for i in range(1, pts.size()):
		var a: float = float(i) / float(pts.size())
		draw_line(pts[i - 1], pts[i], Color(col, a * 0.8), w, true)


func _dashed(a: Vector2, b: Vector2, col: Color, w: float = 2.0) -> void:
	var n: int = maxi(2, int(a.distance_to(b) / 14.0))
	for i in range(0, n, 2):
		draw_line(a.lerp(b, float(i) / float(n)), a.lerp(b, minf(float(i + 1) / float(n), 1.0)), col, w)


func _bez(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, u: float) -> Vector2:
	var v: float = 1.0 - u
	return p0 * v * v * v + p1 * 3.0 * v * v * u + p2 * 3.0 * v * u * u + p3 * u * u * u


func _sample(fn: Callable, t0: float, t1: float, n: int = 40) -> Array:
	var out: Array = []
	for i in n + 1:
		out.append(fn.call(lerpf(t0, t1, float(i) / float(n))))
	return out


func _heading_of(fn: Callable, t: float) -> float:
	var p0: Vector2 = fn.call(t - 0.02)
	var p1: Vector2 = fn.call(t + 0.02)
	return (p1 - p0).angle()


# ------------------------------------------------------------------------------------------------ main draw

func _draw() -> void:
	var sz: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, sz), PAPER, true)
	_stage = Rect2(280.0, 70.0, sz.x - 310.0, sz.y - 190.0)
	# faint blueprint grid
	var gx: float = _stage.position.x
	while gx < _stage.end.x:
		draw_line(Vector2(gx, _stage.position.y), Vector2(gx, _stage.end.y), GRID, 1.0)
		gx += 40.0
	var gy: float = _stage.position.y
	while gy < _stage.end.y:
		draw_line(Vector2(_stage.position.x, gy), Vector2(_stage.end.x, gy), GRID, 1.0)
		gy += 40.0
	draw_rect(_stage, Color(0.5, 0.45, 0.3, 0.7), false, 2.0)
	var ch: Array = CHAPTERS[_ch]
	_txt(Vector2(_stage.position.x, 52.0), "%d / %d   %s" % [_ch + 1, CHAPTERS.size(), String(ch[0]).to_upper()], 30, UIKit.ACCENT)
	match _ch:
		0: _scene_welcome()
		1: _scene_controls()
		2: _scene_throttle()
		3: _scene_speed()
		4: _scene_altitude()
		5: _scene_heat()
		6: _scene_g()
		7: _scene_hull()
		8: _scene_lead()
		9: _scene_boom()
		10: _scene_scissors()
		11: _scene_break()
		12: _scene_loops()
		13: _scene_tips()
	_draw_caption(ch)
	_draw_progress(ch)


func _draw_caption(ch: Array) -> void:
	var caps: Array = ch[2]
	var cur: String = ""
	var t0: float = 0.0
	for c in caps:
		if _t >= float(c[0]):
			cur = String(c[1])
			t0 = float(c[0])
	if cur == "":
		return
	var a: float = _show(_t, t0, 0.5)
	var rect := Rect2(_stage.position.x, _stage.end.y + 14.0, _stage.size.x, 78.0)
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.55 * a), true)
	draw_multiline_string(_font, rect.position + Vector2(18.0, 30.0), cur, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 22, 2, Color(INK, a))


func _draw_progress(ch: Array) -> void:
	var y: float = size.y - 36.0
	var w: float = _stage.size.x
	draw_rect(Rect2(_stage.position.x, y, w, 6.0), Color(1, 1, 1, 0.12), true)
	draw_rect(Rect2(_stage.position.x, y, w * clampf(_t / float(ch[1]), 0.0, 1.0), 6.0), UIKit.ACCENT, true)
	var hint: String = "PAUSED  -  Space to resume" if _paused else "Space pause    Left / Right chapter    Esc close"
	_txt(Vector2(_stage.position.x, y + 24.0), hint, 15, DIM)


# ------------------------------------------------------------------------------------------------ chapters: basics

func _scene_welcome() -> void:
	var c: Vector2 = _stage.get_center()
	var a: float = _show(_t, 0.4, 1.0)
	_txt(Vector2(_stage.position.x, c.y - 100.0), "PILOT TRAINING FILM", 54, Color(INK, a), HORIZONTAL_ALIGNMENT_CENTER, _stage.size.x)
	_txt(Vector2(_stage.position.x, c.y - 56.0), "Instruments  -  Dogfighting  -  Controls", 26, Color(UIKit.ACCENT, a), HORIZONTAL_ALIGNMENT_CENTER, _stage.size.x)
	# a flight of three crossing the screen
	for i in 3:
		var u: float = fmod(_t * 0.09 + float(i) * 0.04, 1.2) - 0.1
		var p := Vector2(lerpf(_stage.position.x - 40.0, _stage.end.x + 40.0, u), c.y + 70.0 + float(i) * 34.0 - float(i % 2) * 20.0 + sin(_t * 1.3 + float(i)) * 6.0)
		_plane(p, 0.0, 22.0, FRIEND)
		draw_line(p - Vector2(24.0, 0), p - Vector2(24.0 + 130.0, 0), Color(1, 1, 1, 0.25), 3.0)


func _scene_controls() -> void:
	var c: Vector2 = _stage.get_center() + Vector2(-80.0, 0.0)
	# three small aircraft rotating about their three axes
	var labels: Array = ["PITCH  W / S", "ROLL  A / D", "YAW  Q / E"]
	var phase: int = clampi(int(_t / 7.0), 0, 2)
	for i in 3:
		var p := Vector2(_stage.position.x + _stage.size.x * (0.2 + 0.3 * float(i)), c.y - 10.0)
		var active: bool = i == phase or _t > 19.0
		var col: Color = FRIEND if active else Color(FRIEND, 0.3)
		var ang: float = sin(_t * 2.0) * 0.5
		var box := Rect2(p - Vector2(130.0, 120.0), Vector2(260.0, 250.0))
		draw_rect(box, Color(1, 1, 1, 0.05 if active else 0.02), true)
		draw_rect(box, Color(UIKit.ACCENT, 0.8 if active else 0.25), false, 1.5)
		if i == 0:
			_plane_side(p, -ang * 0.8, 70.0, col)
			_arc(p, 105.0, -0.6, 0.6, Color(WARN, 0.9 if active else 0.3), 4.0)
		elif i == 1:
			# front view: wings rock
			var wing := Vector2(cos(ang * 0.9), sin(ang * 0.9)) * 85.0
			draw_line(p - wing, p + wing, col, 9.0, true)
			draw_circle(p, 13.0, col)
			draw_line(p + Vector2(0, -2), p + Vector2(0, -24), col, 8.0)
			_arc(p, 105.0, PI + 0.2, PI + 1.0, Color(WARN, 0.9 if active else 0.3), 4.0)
		else:
			_plane(p, ang * 0.9, 60.0, col)
			_arc(p, 105.0, -0.6, 0.6, Color(WARN, 0.9 if active else 0.3), 4.0)
		_txt(Vector2(box.position.x, box.end.y + 30.0), String(labels[i]), 22, Color(INK, 1.0 if active else 0.4), HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	_txt(Vector2(_stage.position.x, _stage.end.y - 18.0), "Turn = roll to bank, then pull back.", 20, Color(DIM, _show(_t, 9.0)), HORIZONTAL_ALIGNMENT_CENTER, _stage.size.x)


# ------------------------------------------------------------------------------------------------ chapters: gauges

func _big_dial() -> Array:
	var r: float = minf(_stage.size.y * 0.34, 170.0)
	var ctr := Vector2(_stage.position.x + r + 330.0, _stage.get_center().y - 10.0)
	return [ctr, r]


func _scene_throttle() -> void:
	var d: Array = _big_dial()
	var ctr: Vector2 = d[0]
	var r: float = d[1]
	_dial_face(ctr, r)
	var thr: float = clampf(0.15 + _t * 0.06 if _t < 14.0 else 0.15 + 14.0 * 0.06 - (_t - 14.0) * 0.05, 0.0, 1.0)
	var boosting: bool = _t > 8.0 and _t < 13.0
	var boost: float = 1.0 if _t < 8.0 else (1.0 - (_t - 8.0) * 0.2 if _t < 13.0 else (0.0 if _t < 16.0 else (_t - 16.0) * 0.25))
	var locked: bool = _t > 13.0 and _t < 16.0
	_meter(ctr, r + 14.0, true, thr, GOOD)
	_meter(ctr, r + 14.0, false, boost, BAD if locked else (Color(1.0, 0.86, 0.4) if boosting else WARN))
	_needle(ctr, r, 0.2 + thr * 0.7)
	_txt(ctr + Vector2(-r, r + 52.0), "AIRSPEED DIAL", 18, DIM, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
	_callout(ctr + Vector2(-(r + 14.0), 0.0), ctr + Vector2(-(r + 60.0), -r - 20.0), "THROTTLE  (Shift / Ctrl)", GOOD, _show(_t, 0.5))
	_callout(ctr + Vector2(r + 14.0, 0.0), ctr + Vector2(r + 60.0, -r * 0.5), "BOOST  (hold Tab)", WARN, _show(_t, 7.0))
	_callout(ctr + Vector2(r + 10.0, 40.0), ctr + Vector2(r + 60.0, r * 0.35), "RED = locked, recharging", BAD, _show(_t, 13.0) * (1.0 if _t < 17.0 else 0.0))
	_side_panel("ENERGY", ["Speed + height = energy.", "Spend it: dive to gain speed,", "zoom to turn speed into height.", "Never waste it on slow turns."], _show(_t, 17.0))


func _scene_speed() -> void:
	var d: Array = _big_dial()
	var ctr: Vector2 = d[0]
	var r: float = d[1]
	_dial_face(ctr, r)
	var stall_f: float = 0.17
	var max_f: float = 0.78
	var a0: float = deg_to_rad(135.0)
	var sw: float = deg_to_rad(270.0)
	_arc(ctr, r - 8.0, a0, a0 + sw * stall_f, Color(BAD, 0.9), 6.0)
	_arc(ctr, r - 8.0, a0 + sw * stall_f, a0 + sw * max_f, Color(GOOD, 0.6), 6.0)
	_arc(ctr, r - 8.0, a0 + sw * max_f, a0 + sw, Color(WARN, 0.85), 6.0)
	var v: float = 0.5 + 0.45 * sin(_t * 0.5 - 1.2)
	if _t > 12.0:
		v = lerpf(v, 0.1, clampf((_t - 12.0) * 0.4, 0.0, 1.0))
	_needle(ctr, r, v)
	_txt(ctr + Vector2(-r, r + 52.0), "AIRSPEED  km/h", 18, DIM, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
	var pc := Vector2(cos(a0 + sw * 0.08), sin(a0 + sw * 0.08)) * (r - 8.0)
	_callout(ctr + pc, ctr + Vector2(r + 70.0, r * 0.65), "STALL: wings stop flying", BAD, _show(_t, 5.0))
	var gc := Vector2(cos(a0 + sw * 0.5), sin(a0 + sw * 0.5)) * (r - 8.0)
	_callout(ctr + gc, ctr + Vector2(r + 70.0, -r * 0.2), "NORMAL FLYING SPEED", GOOD, _show(_t, 9.0))
	var ac := Vector2(cos(a0 + sw * 0.9), sin(a0 + sw * 0.9)) * (r - 8.0)
	_callout(ctr + ac, ctr + Vector2(r + 70.0, -r * 0.85), "BEYOND TOP SPEED (dives)", WARN, _show(_t, 10.5))
	if _t > 12.0:
		# stalled aircraft drooping
		var p := Vector2(_stage.end.x - 150.0, _stage.position.y + 110.0)
		var drop: float = clampf((_t - 12.0) * 0.5, 0.0, 1.0)
		_plane_side(p + Vector2(0, drop * 40.0), 0.7 * drop + 0.3 * (1.0 - drop) * -0.2, 40.0, FRIEND)
		_txt(p + Vector2(-60.0, 80.0), "nose drops", 18, Color(BAD, drop), HORIZONTAL_ALIGNMENT_LEFT)


func _scene_altitude() -> void:
	var d: Array = _big_dial()
	var ctr: Vector2 = d[0]
	var r: float = d[1]
	_dial_face(ctr, r)
	var alt: float = 0.3 + 0.2 * sin(_t * 0.4)
	_needle(ctr, r, alt)
	_txt(ctr + Vector2(-r, r + 52.0), "ALTIMETER  (metres)", 18, DIM, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
	# climb readout
	var climb: float = cos(_t * 0.4) * 6.0
	_txt(ctr + Vector2(-r, 60.0), "CLIMB  %+.1f m/s" % climb, 22, GOOD if climb >= 0.0 else WARN, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
	_callout(ctr + Vector2(0, -r * 0.55), ctr + Vector2(r + 60.0, -r * 0.7), "HEIGHT ABOVE SEA", INK, _show(_t, 0.5))
	_callout(ctr + Vector2(0, 62.0), ctr + Vector2(r + 60.0, -r * 0.1), "CLIMB RATE", GOOD, _show(_t, 6.0))
	# gear and flap icons
	var ip := Vector2(_stage.end.x - 190.0, _stage.position.y + _stage.size.y * 0.72)
	var gear_down: bool = fmod(_t, 6.0) < 3.0
	var gcol: Color = WARN if gear_down else Color(DIM, 0.4)
	draw_circle(ip, 16.0, gcol)
	draw_line(ip + Vector2(0, -16), ip + Vector2(0, -50), gcol, 5.0)
	_txt(ip + Vector2(-60.0, 52.0), "GEAR  (G)", 20, Color(INK, _show(_t, 11.0)), HORIZONTAL_ALIGNMENT_CENTER, 120.0)
	var fp := ip + Vector2(120.0, 0.0)
	var flap: float = float(int(_t / 2.0) % 3) * 0.5
	draw_rect(Rect2(fp + Vector2(-34.0, -8.0), Vector2(68.0, 10.0)), WARN if flap > 0.0 else Color(DIM, 0.4), true)
	draw_line(fp + Vector2(0, 2.0), fp + Vector2(30.0, 2.0 + 30.0 * flap), WARN, 6.0)
	_txt(fp + Vector2(-70.0, 52.0), "FLAPS  (F)", 20, Color(INK, _show(_t, 11.0)), HORIZONTAL_ALIGNMENT_CENTER, 140.0)


func _scene_heat() -> void:
	var d: Array = _big_dial()
	var ctr: Vector2 = d[0]
	var r: float = d[1]
	_dial_face(ctr, r)
	var heat: float = clampf(_t / 11.0, 0.0, 1.0) if _t < 13.0 else clampf(1.0 - (_t - 13.0) * 0.12, 0.2, 1.0)
	var hot: bool = heat > 0.85
	var hc: Color = COOL.lerp(WARN, clampf(heat * 1.6, 0.0, 1.0))
	if hot:
		hc = HOT if int(_t * 4.0) % 2 == 0 else Color(1.0, 0.4, 0.3)
	_meter(ctr, r + 14.0, true, 0.6, GOOD)
	_meter(ctr, r + 24.0, false, heat, hc, 9.0)
	var wear: float = clampf(_t * 0.03, 0.0, 0.6)
	_meter(ctr, r + 36.0, false, wear, BAD if wear > 0.5 else WARN, 4.0)
	_needle(ctr, r, 0.75)
	_txt(ctr + Vector2(-r, r + 56.0), "AIRSPEED DIAL + ENGINE TEMP", 18, DIM, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
	_callout(ctr + Vector2(r + 24.0, -r * 0.2), ctr + Vector2(r + 90.0, -r * 0.75), "ENGINE TEMPERATURE", hc, _show(_t, 0.8))
	_callout(ctr + Vector2(r + 24.0, 30.0), ctr + Vector2(r + 90.0, r * 0.2), "BRIGHT RED = OVERHEATING", HOT, _show(_t, 7.0))
	_callout(ctr + Vector2(r + 36.0, 80.0), ctr + Vector2(r + 90.0, r * 0.7), "WEAR (thin outer arc)", WARN, _show(_t, 17.0))
	if _t > 13.0:
		_side_panel("COOL DOWN", ["Throttle back.", "Stop boosting.", "Fly level and wait", "for the arc to fall."], _show(_t, 13.0))


func _scene_g() -> void:
	var d: Array = _big_dial()
	var ctr: Vector2 = d[0]
	var r: float = d[1]
	_dial_face(ctr, r)
	var g: float = 1.0 + 7.0 * clampf(_t / 11.0, 0.0, 1.0) if _t < 14.0 else maxf(1.0, 8.0 - (_t - 14.0) * 2.0)
	var over: bool = g > 6.5
	_meter(ctr, r + 14.0, false, g / 8.0, HOT if over else (WARN if g > 4.5 else Color(0.6, 0.85, 1.0)))
	var tol: float = clampf((_t - 8.0) / 8.0, 0.0, 1.0) if _t < 16.0 else clampf(1.0 - (_t - 16.0) * 0.3, 0.0, 1.0)
	_meter(ctr, r + 26.0, false, tol, HOT if tol > 0.6 else WARN, 5.0)
	_meter(ctr, r + 14.0, true, 0.85, Color(0.85, 0.82, 0.66))
	_needle(ctr, r, 0.35)
	_txt(ctr + Vector2(-r, r + 56.0), "ALTIMETER DIAL + G", 18, DIM, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
	_txt(ctr + Vector2(-r, 56.0), "%.1f G" % g, 34, HOT if over else INK, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
	_callout(ctr + Vector2(r + 14.0, -20.0), ctr + Vector2(r + 80.0, -r * 0.7), "G LOAD (0 to 8 G)", INK, _show(_t, 0.6))
	_callout(ctr + Vector2(r + 14.0, 40.0), ctr + Vector2(r + 80.0, r * 0.1), "OVER 6.5 G = BRIGHT RED", HOT, _show(_t, 7.0))
	_callout(ctr + Vector2(r + 26.0, 80.0), ctr + Vector2(r + 80.0, r * 0.6), "BLACKOUT BUILD-UP", WARN, _show(_t, 11.0))
	# the sight closing in
	var vp := Rect2(_stage.end.x - 250.0, _stage.position.y + 24.0, 220.0, 140.0)
	draw_rect(vp, Color(0.35, 0.5, 0.65, 1.0), true)
	draw_rect(Rect2(vp.position.x, vp.position.y + 70.0, vp.size.x, 70.0), Color(0.25, 0.38, 0.22, 1.0), true)
	var closing: float = tol
	for k in 24:
		var f: float = float(k) / 24.0
		var shade: float = clampf(closing * 1.4 - (1.0 - f) * 0.4, 0.0, 1.0)
		draw_rect(Rect2(vp.position.x - 1.0, vp.position.y + vp.size.y * f * 0.5 - 1.0, vp.size.x + 2.0, vp.size.y * 0.5 / 24.0 + 1.0), Color(0, 0, 0, shade * 0.5), true)
		draw_rect(Rect2(vp.position.x - 1.0, vp.end.y - vp.size.y * f * 0.5 - vp.size.y * 0.5 / 24.0, vp.size.x + 2.0, vp.size.y * 0.5 / 24.0 + 1.0), Color(0, 0, 0, shade * 0.5), true)
	draw_rect(vp, Color(UIKit.ACCENT, 0.7), false, 2.0)
	_txt(vp.position + Vector2(0, vp.size.y + 24.0), "YOUR VIEW", 16, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.size.x)


func _scene_hull() -> void:
	var d: Array = _big_dial()
	var ctr: Vector2 = d[0]
	var r: float = d[1]
	_dial_face(ctr, r)
	var hull: float = clampf(1.0 - _t / 11.0 * 0.85, 0.12, 1.0)
	var col: Color = BAD if hull < 0.35 else (WARN if hull < 0.65 else Color(0.85, 0.82, 0.66))
	_meter(ctr, r + 14.0, true, hull, col, 9.0)
	_needle(ctr, r, 0.4)
	_txt(ctr + Vector2(-r, r + 56.0), "ALTIMETER DIAL + HULL", 18, DIM, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
	_callout(ctr + Vector2(-(r + 14.0), -10.0), ctr + Vector2(-(r + 70.0), -r * 0.75), "HULL (aircraft health)", col, _show(_t, 0.6))
	var bail := Vector2(_stage.end.x - 190.0, _stage.get_center().y)
	var ba: float = _show(_t, 9.5)
	if ba > 0.0:
		var py: float = bail.y + lerpf(-60.0, 80.0, clampf((_t - 10.0) / 4.0, 0.0, 1.0))
		draw_circle(Vector2(bail.x, py - 36.0), 30.0, Color(0.9, 0.9, 0.85, ba))
		draw_line(Vector2(bail.x - 30.0, py - 36.0), Vector2(bail.x, py), Color(0.9, 0.9, 0.85, ba), 2.0)
		draw_line(Vector2(bail.x + 30.0, py - 36.0), Vector2(bail.x, py), Color(0.9, 0.9, 0.85, ba), 2.0)
		draw_circle(Vector2(bail.x, py + 4.0), 6.0, Color(FRIEND, ba))
		_txt(bail + Vector2(-80.0, 130.0), "HOLD J: BAIL OUT", 20, Color(INK, ba), HORIZONTAL_ALIGNMENT_CENTER, 160.0)


func _side_panel(title: String, lines: Array, a: float) -> void:
	if a <= 0.01:
		return
	var rect := Rect2(_stage.end.x - 320.0, _stage.end.y - 170.0, 300.0, 150.0)
	draw_rect(rect, Color(0.04, 0.05, 0.06, 0.8 * a), true)
	draw_rect(rect, Color(UIKit.ACCENT, a), false, 1.5)
	_txt(rect.position + Vector2(14.0, 30.0), title, 22, Color(UIKit.ACCENT, a))
	for i in lines.size():
		_txt(rect.position + Vector2(14.0, 58.0 + 22.0 * float(i)), String(lines[i]), 17, Color(INK, a))


# ------------------------------------------------------------------------------------------------ chapters: dogfights

func _map_pt(u: float, v: float) -> Vector2:
	return _stage.position + Vector2(_stage.size.x * u, _stage.size.y * v)


func _legend() -> void:
	var p: Vector2 = _stage.position + Vector2(20.0, 30.0)
	_plane(p, 0.0, 12.0, FRIEND)
	_txt(p + Vector2(24.0, 6.0), "you", 18, INK)
	_plane(p + Vector2(90.0, 0.0), 0.0, 12.0, FOE)
	_txt(p + Vector2(114.0, 6.0), "enemy", 18, INK)


func _scene_lead() -> void:
	_legend()
	var c: Vector2 = _map_pt(0.5, 0.52)
	var big: float = _stage.size.y * 0.36
	var w: float = 0.42
	var tgt := func(t: float) -> Vector2: return c + Vector2(cos(-1.2 + t * w), sin(-1.2 + t * w)) * big
	var att := func(t: float) -> Vector2: return c + Vector2(cos(-1.2 + t * w - 0.95), sin(-1.2 + t * w - 0.95)) * big * 0.72
	var t: float = _t
	_trail(_sample(tgt, maxf(0.0, t - 3.0), t, 24), FOE)
	_trail(_sample(att, maxf(0.0, t - 3.0), t, 24), FRIEND)
	var tp: Vector2 = tgt.call(t)
	var ap: Vector2 = att.call(t)
	var th: float = _heading_of(tgt, t) + PI
	var ah: float = _heading_of(att, t) + PI
	th = (tgt.call(t + 0.05) - tgt.call(t - 0.05)).angle()
	ah = (att.call(t + 0.05) - att.call(t - 0.05)).angle()
	var lead_pt: Vector2 = tp + Vector2.from_angle(th) * (70.0 + 20.0 * sin(t))
	if _t > 2.0:
		_dashed(ap, tp, Color(1, 1, 1, 0.25 * _show(_t, 2.0)))
		_txt(ap.lerp(tp, 0.5) + Vector2(10, -6), "pure pursuit: bullets miss behind him", 16, Color(DIM, _show(_t, 2.0) * (1.0 - _show(_t, 6.0))))
	if _t > 6.0:
		var a: float = _show(_t, 6.0)
		_dashed(ap, lead_pt, Color(FRIEND, 0.9 * a), 3.0)
		draw_arc(lead_pt, 16.0, 0.0, TAU, 24, Color(FRIEND, a), 3.0)
		draw_line(lead_pt - Vector2(22, 0), lead_pt + Vector2(22, 0), Color(FRIEND, a), 2.0)
		draw_line(lead_pt - Vector2(0, 22), lead_pt + Vector2(0, 22), Color(FRIEND, a), 2.0)
		_txt(lead_pt + Vector2(20, -22), "LEAD POINT", 18, Color(FRIEND, a))
		if _t > 13.0:
			for k in 6:
				var u: float = fmod(_t * 1.6 + float(k) / 6.0, 1.0)
				draw_circle(ap.lerp(lead_pt, u), 3.0, Color(1.0, 0.95, 0.6, _show(_t, 13.0)))
	_plane(tp, th, 28.0, FOE)
	_plane(ap, ah, 28.0, FRIEND)
	if _t > 19.0:
		var a2: float = _show(_t, 19.0)
		draw_arc(c, big * 0.72, 0.0, TAU, 64, Color(FRIEND, 0.25 * a2), 2.0)
		draw_arc(c, big, 0.0, TAU, 64, Color(FOE, 0.25 * a2), 2.0)
		_txt(c + Vector2(-80.0, 6.0), "his turn circle is wider", 18, Color(DIM, a2))


func _scene_boom() -> void:
	var y0: float = _stage.position.y
	var h: float = _stage.size.y
	# sea line and altitude scale
	draw_rect(Rect2(_stage.position.x, y0 + h * 0.9, _stage.size.x, h * 0.1), Color(0.1, 0.2, 0.3, 0.8), true)
	_txt(_stage.position + Vector2(18.0, 54.0), "HIGH", 18, DIM)
	_txt(_stage.position + Vector2(18.0, h * 0.88), "LOW", 18, DIM)
	var xs: float = _stage.size.x
	var bandit_y: float = y0 + h * 0.7
	var bandit_x: float = _stage.position.x + xs * (0.15 + 0.02 * _t)
	_plane_side(Vector2(bandit_x, bandit_y), 0.0, 34.0, FOE)
	# attacker: high -> dive -> zoom
	var p0: Vector2 = _stage.position + Vector2(xs * 0.04, h * 0.1)
	var p1: Vector2 = _stage.position + Vector2(xs * 0.28, h * 0.1)
	var p2: Vector2 = _stage.position + Vector2(xs * 0.34, h * 0.86)
	var p3: Vector2 = _stage.position + Vector2(xs * 0.62, h * 0.74)
	var p4: Vector2 = _stage.position + Vector2(xs * 0.9, h * 0.62)
	var p5: Vector2 = _stage.position + Vector2(xs * 0.95, h * 0.1)
	var path := func(u: float) -> Vector2:
		if u < 0.5:
			return _bez(p0, p1, p2, p3, u * 2.0)
		return _bez(p3, p4, p5, p5 + Vector2(-xs * 0.1, 0.0), (u - 0.5) * 2.0)
	var dur: float = 18.0
	var u: float = clampf(_t / dur, 0.0, 1.0)
	var ap: Vector2 = path.call(u)
	_trail(_sample(path, maxf(0.0, u - 0.22), u, 30), FRIEND, 3.0)
	draw_polyline(PackedVector2Array(_sample(path, 0.0, 1.0, 60)), Color(FRIEND, 0.14), 2.0)
	var ang: float = (path.call(minf(u + 0.01, 1.0)) - path.call(maxf(u - 0.01, 0.0))).angle()
	_plane_side(ap, ang, 34.0, FRIEND)
	# phases
	_txt(_stage.position + Vector2(xs * 0.12, h * 0.06), "1  HIGH: wait, watch", 18, Color(INK, 1.0 if u < 0.2 else 0.4))
	_txt(_stage.position + Vector2(xs * 0.36, h * 0.5), "2  DIVE, FIRE", 18, Color(INK, 1.0 if u > 0.2 and u < 0.55 else 0.4))
	_txt(_stage.position + Vector2(xs * 0.68, h * 0.4), "3  ZOOM CLIMB", 18, Color(INK, 1.0 if u > 0.55 else 0.4))
	# firing burst
	if u > 0.34 and u < 0.46:
		for k in 8:
			var f: float = fmod(_t * 3.0 + float(k) / 8.0, 1.0)
			draw_circle(ap.lerp(Vector2(bandit_x, bandit_y), f), 3.0, Color(1.0, 0.95, 0.5))
	# energy bar
	var e: float = clampf(1.0 - absf(u - 0.5) * 1.0, 0.0, 1.0)
	var spd: float = clampf(1.0 - absf(ap.y - (y0 + h * 0.86)) / (h * 0.8), 0.15, 1.0)
	var hh: float = 1.0 - clampf((ap.y - y0) / (h * 0.9), 0.0, 1.0)
	_energy_bars(_stage.end - Vector2(210.0, 150.0), hh, spd)
	if e < -1.0:
		pass


func _energy_bars(p: Vector2, height_f: float, speed_f: float) -> void:
	_txt(p + Vector2(0, -10.0), "ENERGY", 18, DIM)
	draw_rect(Rect2(p, Vector2(160.0, 16.0)), Color(1, 1, 1, 0.1), true)
	draw_rect(Rect2(p, Vector2(160.0 * height_f, 16.0)), Color(0.5, 0.75, 1.0), true)
	_txt(p + Vector2(168.0, 14.0), "height", 16, DIM)
	draw_rect(Rect2(p + Vector2(0, 26.0), Vector2(160.0, 16.0)), Color(1, 1, 1, 0.1), true)
	draw_rect(Rect2(p + Vector2(0, 26.0), Vector2(160.0 * speed_f, 16.0)), WARN, true)
	_txt(p + Vector2(168.0, 40.0), "speed", 16, DIM)


func _scene_scissors() -> void:
	_legend()
	var cx: float = _stage.get_center().x
	var cy: float = _stage.get_center().y
	var amp: float = _stage.size.y * 0.25
	var sp: float = 40.0
	var f1 := func(t: float) -> Vector2: return Vector2(_stage.position.x + 60.0 + t * sp, cy + sin(t * 1.15) * amp)
	var f2 := func(t: float) -> Vector2: return Vector2(_stage.position.x + 60.0 + t * sp - 30.0, cy - sin(t * 1.15 + 0.3) * amp)
	var t: float = _t
	_trail(_sample(f1, maxf(0.0, t - 4.0), t, 30), FRIEND)
	_trail(_sample(f2, maxf(0.0, t - 4.0), t, 30), FOE)
	_plane(f2.call(t), (f2.call(t + 0.05) - f2.call(t - 0.05)).angle(), 28.0, FOE)
	_plane(f1.call(t), (f1.call(t + 0.05) - f1.call(t - 0.05)).angle(), 28.0, FRIEND)
	# overshoot flashes where the paths cross
	var dist: float = f1.call(t).distance_to(f2.call(t))
	if dist < 70.0 and _t > 6.0:
		var m: Vector2 = (f1.call(t) + f2.call(t)) * 0.5
		draw_arc(m, 40.0 + 6.0 * sin(t * 8.0), 0.0, TAU, 24, Color(WARN, 0.8), 3.0)
		_txt(m + Vector2(-60.0, -50.0), "CROSSING", 18, WARN)
	if _t > 14.0:
		_txt(Vector2(_stage.position.x, _stage.end.y - 14.0), "Slow, tight reversals: whoever shoots past the other loses the fight.", 18, Color(DIM, _show(_t, 14.0)), HORIZONTAL_ALIGNMENT_CENTER, _stage.size.x)


func _scene_break() -> void:
	_legend()
	var s: Vector2 = _stage.position
	var w: float = _stage.size.x
	var h: float = _stage.size.y
	var y: float = s.y + h * 0.5
	var sp: float = w * 0.045
	# defender: straight, then a hard break to the right (toward screen-down) at t=7
	var def := func(t: float) -> Vector2:
		var x: float = s.x + w * 0.38 + t * sp
		if t < 7.0:
			return Vector2(x, y)
		var tt: float = t - 7.0
		var a: float = clampf(tt * 0.55, 0.0, 2.2)
		var rr: float = 70.0
		return Vector2(s.x + w * 0.38 + 7.0 * sp + sin(a) * rr, y + (1.0 - cos(a)) * rr)
	# attacker: straight behind, keeps flying straight on (overshoots)
	var atk := func(t: float) -> Vector2:
		var x: float = s.x + w * 0.1 + t * sp * 1.18
		if t < 13.0:
			return Vector2(x, y)
		var tt: float = t - 13.0
		return Vector2(x, y) + Vector2(0.0, -tt * 5.0)
	var t: float = _t
	_trail(_sample(def, maxf(0.0, t - 5.0), t, 30), FRIEND)
	_trail(_sample(atk, maxf(0.0, t - 5.0), t, 30), FOE)
	var dp: Vector2 = def.call(t)
	var ap: Vector2 = atk.call(t)
	var dh: float = (def.call(t + 0.05) - def.call(t - 0.05)).angle()
	var ah: float = (atk.call(t + 0.05) - atk.call(t - 0.05)).angle()
	_plane(ap, ah, 28.0, FOE)
	_plane(dp, dh, 28.0, FRIEND)
	if t < 7.0:
		_dashed(ap, dp, Color(FOE, 0.5))
		_txt(ap + Vector2(0, -34.0), "ON YOUR TAIL", 18, Color(FOE, 0.9))
	if t > 7.0 and t < 13.0:
		_txt(dp + Vector2(30.0, -34.0), "BREAK INTO HIM!", 20, WARN)
	if t > 13.0:
		var a: float = _show(t, 13.0)
		draw_arc(ap, 38.0 + 5.0 * sin(t * 6.0), 0.0, TAU, 24, Color(WARN, 0.8 * a), 3.0)
		_txt(ap + Vector2(-20.0, -54.0), "OVERSHOOT", 20, Color(WARN, a))
		_dashed(dp, ap, Color(FRIEND, 0.7 * a), 3.0)
		_txt(dp + Vector2(20.0, 56.0), "NOW YOU ARE BEHIND HIM: FIRE", 18, Color(FRIEND, a))


func _scene_loops() -> void:
	var s: Vector2 = _stage.position
	var w: float = _stage.size.x
	var h: float = _stage.size.y
	var half_w: float = w * 0.5
	var r: float = minf(h * 0.26, 105.0)
	# left panel: Immelmann (half loop up, then roll upright, heading reversed)
	var lc := Vector2(s.x + half_w * 0.5, s.y + h * 0.5)
	_txt(Vector2(s.x, s.y + 28.0) + Vector2(18.0, 0.0), "IMMELMANN", 22, INK)
	var imm := func(u: float) -> Vector2:
		var base_y: float = lc.y + r * 1.2
		if u < 0.2:
			return Vector2(lc.x - r * 2.2 + u / 0.2 * r * 1.2, base_y)
		if u < 0.7:
			var a: float = (u - 0.2) / 0.5 * PI
			return Vector2(lc.x - r + sin(a) * r, base_y - (1.0 - cos(a)) * r)
		var k: float = (u - 0.7) / 0.3
		return Vector2(lc.x - r - k * r * 1.6, base_y - 2.0 * r)
	# right panel: Split-S (roll inverted, half loop down)
	var rc := Vector2(s.x + half_w * 1.5, s.y + h * 0.5)
	_txt(Vector2(s.x + half_w, s.y + 28.0) + Vector2(18.0, 0.0), "SPLIT-S", 22, INK)
	var spl := func(u: float) -> Vector2:
		var top_y: float = rc.y - r * 1.4
		if u < 0.2:
			return Vector2(rc.x - r * 2.2 + u / 0.2 * r * 1.2, top_y)
		if u < 0.7:
			var a: float = (u - 0.2) / 0.5 * PI
			return Vector2(rc.x - r + sin(a) * r, top_y + (1.0 - cos(a)) * r)
		var k: float = (u - 0.7) / 0.3
		return Vector2(rc.x - r - k * r * 1.6, top_y + 2.0 * r)
	draw_line(Vector2(s.x + half_w, s.y + 6.0), Vector2(s.x + half_w, s.y + h - 6.0), Color(GRID, 0.9), 2.0)
	var dur: float = 8.0
	var phase: float = fmod(_t, dur + 2.0) / dur
	var u: float = clampf(phase, 0.0, 1.0)
	for pair in [[imm, 1.0], [spl, 1.0]]:
		var fn: Callable = pair[0]
		draw_polyline(PackedVector2Array(_sample(fn, 0.0, 1.0, 60)), Color(FRIEND, 0.2), 2.0)
		_trail(_sample(fn, maxf(0.0, u - 0.25), u, 30), FRIEND)
		var p: Vector2 = fn.call(u)
		var ang: float = (fn.call(minf(u + 0.01, 1.0)) - fn.call(maxf(u - 0.01, 0.0))).angle()
		var inverted: float = -1.0 if (u > 0.35 and u < 0.8 and fn == imm) or (u > 0.2 and u < 0.55 and fn == spl) else 1.0
		_plane_side(p, ang, 30.0, FRIEND, inverted)
	_txt(lc + Vector2(-r * 2.2, r * 2.2), "gain height, turn round", 18, Color(DIM, _show(_t, 1.0)))
	_txt(rc + Vector2(-r * 2.2, r * 2.4), "lose height, gain speed", 18, Color(DIM, _show(_t, 9.0)))


func _scene_tips() -> void:
	var rows: Array = [["K", "target view: lock on nearest"], ["M", "tactical map"], ["[  ]", "time warp on long transits"],
		[".", "skip to the next music track"], ["Space", "fire"], ["X / B", "switch guns / rockets / bombs"], ["N", "bombsight"], ["L", "gunner view (bombers)"],
		["Tab", "boost"], ["G / F / V", "gear / flaps / wheel brake"], ["R", "auto-level"], ["Hold J", "bail out"]]
	var cols: int = 2
	var cw: float = _stage.size.x / float(cols)
	for i in rows.size():
		var a: float = _show(_t, 0.25 * float(i), 0.5)
		var p := _stage.position + Vector2(24.0 + float(i % cols) * cw, 50.0 + float(i / cols) * 62.0)
		var kw: float = 120.0
		draw_rect(Rect2(p, Vector2(kw, 42.0)), Color(0.12, 0.14, 0.15, a), true)
		draw_rect(Rect2(p, Vector2(kw, 42.0)), Color(UIKit.ACCENT, a), false, 2.0)
		_txt(p + Vector2(0, 29.0), String(rows[i][0]), 22, Color(UIKit.ACCENT_HOT, a), HORIZONTAL_ALIGNMENT_CENTER, kw)
		_txt(p + Vector2(kw + 16.0, 29.0), String(rows[i][1]), 19, Color(INK, a))
