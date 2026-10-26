class_name PadGlyph
extends Control
## Xbox-style gamepad button icon in the controller's own colours (A green, B red, X blue, Y yellow; bumpers,
## triggers, sticks, D-pad, View and Menu in grey). Use as a Control (`PadGlyph.make("A", 28)`) or draw directly
## into any CanvasItem with `PadGlyph.draw_glyph(ci, key, centre, height)`.
## Keys: A B X Y LB RB LT RT LS RS L3 R3 UP DOWN LEFT RIGHT DPAD BACK START

const COL_A := Color(0.42, 0.75, 0.22)
const COL_B := Color(0.89, 0.24, 0.20)
const COL_X := Color(0.18, 0.50, 0.89)
const COL_Y := Color(0.99, 0.77, 0.12)
const BODY := Color(0.20, 0.21, 0.23)
const EDGE := Color(0.62, 0.63, 0.66)
const INK := Color(0.96, 0.96, 0.96)

var key: String = "A"
var h: float = 28.0


static func make(k: String, height: float = 28.0) -> PadGlyph:
	var g := PadGlyph.new()
	g.key = k
	g.h = height
	g.custom_minimum_size = Vector2(width_for(k, height), height)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


## Width the glyph needs at `height`.
static func width_for(k: String, height: float) -> float:
	match k:
		"LB", "RB", "LT", "RT":
			return height * 1.55
	return height


## The glyph key for a joypad InputEvent, or "" if it is not a pad event.
static func key_for_event(ev: InputEvent) -> String:
	if ev is InputEventJoypadButton:
		match (ev as InputEventJoypadButton).button_index:
			JOY_BUTTON_A: return "A"
			JOY_BUTTON_B: return "B"
			JOY_BUTTON_X: return "X"
			JOY_BUTTON_Y: return "Y"
			JOY_BUTTON_LEFT_SHOULDER: return "LB"
			JOY_BUTTON_RIGHT_SHOULDER: return "RB"
			JOY_BUTTON_LEFT_STICK: return "L3"
			JOY_BUTTON_RIGHT_STICK: return "R3"
			JOY_BUTTON_BACK: return "BACK"
			JOY_BUTTON_START: return "START"
			JOY_BUTTON_DPAD_UP: return "UP"
			JOY_BUTTON_DPAD_DOWN: return "DOWN"
			JOY_BUTTON_DPAD_LEFT: return "LEFT"
			JOY_BUTTON_DPAD_RIGHT: return "RIGHT"
	elif ev is InputEventJoypadMotion:
		match (ev as InputEventJoypadMotion).axis:
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_TRIGGER_RIGHT: return "RT"
			JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y: return "LS"
			JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y: return "RS"
	return ""


func _draw() -> void:
	draw_glyph(self, key, size * 0.5, h)


static func _text(ci: CanvasItem, c: Vector2, s: String, px: int, col: Color) -> void:
	var f: Font = UIKit.font(true)
	var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	ci.draw_string(f, c + Vector2(-w * 0.5, px * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


static func draw_glyph(ci: CanvasItem, k: String, c: Vector2, hh: float, alpha: float = 1.0) -> void:
	if k == "":
		return
	var r: float = hh * 0.5
	var a := func(col: Color) -> Color: return Color(col, col.a * alpha)
	match k:
		"A", "B", "X", "Y":
			var col: Color = {"A": COL_A, "B": COL_B, "X": COL_X, "Y": COL_Y}[k]
			ci.draw_circle(c, r, a.call(col))
			ci.draw_arc(c, r - 1.0, 0.0, TAU, 32, a.call(col.lightened(0.35)), 1.5, true)
			_text(ci, c, k, int(hh * 0.62), a.call(Color(0.05, 0.05, 0.05) if k == "Y" else INK))
		"LB", "RB":
			var w: float = hh * 1.55
			var rc := Rect2(c - Vector2(w * 0.5, r * 0.78), Vector2(w, hh * 0.78))
			_round_rect(ci, rc, hh * 0.3, a.call(BODY), a.call(EDGE))
			_text(ci, rc.get_center(), k, int(hh * 0.5), a.call(INK))
		"LT", "RT":
			var w2: float = hh * 1.3
			var pts := PackedVector2Array([c + Vector2(-w2 * 0.5, r), c + Vector2(-w2 * 0.5, -r * 0.35),
				c + Vector2(-w2 * 0.2, -r), c + Vector2(w2 * 0.2, -r), c + Vector2(w2 * 0.5, -r * 0.35), c + Vector2(w2 * 0.5, r)])
			ci.draw_colored_polygon(pts, a.call(BODY))
			var outline := pts.duplicate()
			outline.append(pts[0])
			ci.draw_polyline(outline, a.call(EDGE), 1.5, true)
			_text(ci, c + Vector2(0, r * 0.1), k, int(hh * 0.5), a.call(INK))
		"LS", "RS", "L3", "R3":
			ci.draw_circle(c, r, a.call(BODY))
			ci.draw_arc(c, r - 1.0, 0.0, TAU, 32, a.call(EDGE), 1.5, true)
			ci.draw_arc(c, r * 0.62, 0.0, TAU, 32, a.call(EDGE.darkened(0.3)), 1.2, true)
			var lbl: String = k.substr(0, 1) if k.length() == 2 and k[1] == "S" else k
			_text(ci, c, lbl, int(hh * (0.5 if lbl.length() == 1 else 0.42)), a.call(INK))
		"UP", "DOWN", "LEFT", "RIGHT", "DPAD":
			var t: float = hh * 0.34
			var arm: float = r
			var vr := Rect2(c - Vector2(t * 0.5, arm), Vector2(t, arm * 2.0))
			var hr := Rect2(c - Vector2(arm, t * 0.5), Vector2(arm * 2.0, t))
			ci.draw_rect(vr, a.call(BODY))
			ci.draw_rect(hr, a.call(BODY))
			ci.draw_rect(vr, a.call(EDGE), false, 1.2)
			ci.draw_rect(hr, a.call(EDGE), false, 1.2)
			ci.draw_rect(Rect2(c - Vector2(t * 0.5 - 1.0, t * 0.5 - 1.0), Vector2(t - 2.0, t - 2.0)), a.call(BODY))
			var dirs := {"UP": Vector2(0, -1), "DOWN": Vector2(0, 1), "LEFT": Vector2(-1, 0), "RIGHT": Vector2(1, 0)}
			if dirs.has(k):
				var d: Vector2 = dirs[k]
				var lit := Rect2(c + d * (arm * 0.5 + t * 0.25) - Vector2(t, t) * 0.5 + Vector2(absf(d.x), absf(d.y)) * 0.0, Vector2(t, t))
				if d.x != 0.0:
					lit = Rect2(Vector2(minf(c.x + d.x * t * 0.5, c.x + d.x * arm), c.y - t * 0.5), Vector2(arm - t * 0.5, t))
				else:
					lit = Rect2(Vector2(c.x - t * 0.5, minf(c.y + d.y * t * 0.5, c.y + d.y * arm)), Vector2(t, arm - t * 0.5))
				ci.draw_rect(lit.grow(-1.0), a.call(INK))
		"BACK", "START":
			ci.draw_circle(c, r * 0.8, a.call(BODY))
			ci.draw_arc(c, r * 0.8 - 0.5, 0.0, TAU, 28, a.call(EDGE), 1.2, true)
			if k == "BACK":     # the View button: two overlapping windows
				var s: float = r * 0.42
				ci.draw_rect(Rect2(c + Vector2(-s * 0.9, -s * 0.8), Vector2(s * 1.2, s * 1.0)), a.call(INK), false, 1.2)
				ci.draw_rect(Rect2(c + Vector2(-s * 0.3, -s * 0.2), Vector2(s * 1.2, s * 1.0)), a.call(INK), true)
			else:               # the Menu button: three lines
				for i in 3:
					var y: float = (float(i) - 1.0) * r * 0.28
					ci.draw_line(c + Vector2(-r * 0.38, y), c + Vector2(r * 0.38, y), a.call(INK), 1.6, true)
		_:
			ci.draw_circle(c, r, a.call(BODY))
			_text(ci, c, k, int(hh * 0.4), a.call(INK))


static func _round_rect(ci: CanvasItem, rc: Rect2, rad: float, fill: Color, edge: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	sb.draw(ci.get_canvas_item(), rc)
