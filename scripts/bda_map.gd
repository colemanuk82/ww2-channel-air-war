class_name BDAMap
extends Control
## Bomb damage assessment map for the results screen: one target seen from above, with its hit radius, range
## rings and every bomb the player dropped on it. Red = inside the hit radius, grey cross = a miss.
## Build a row of them with BDAMap.panel(targets), where targets is the "bda" list from BombingMode's stats.

const SPAN := 150.0      # metres from the target centre to the edge of the map

var _entry: Dictionary = {}


static func panel(targets: Array) -> Control:
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 18)
	flow.add_theme_constant_override("v_separation", 10)
	for e in targets:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		var m := BDAMap.new()
		m._entry = e
		m.custom_minimum_size = Vector2(220, 220)
		col.add_child(m)
		var hits: int = 0
		var total: int = 0
		for mk in e.get("marks", []):
			total += 1
			if bool(mk.get("hit", false)):
				hits += 1
		var status: String = "DOWN" if bool(e.get("destroyed", false)) else "STANDING"
		var cap := UIKit.label("%s - %s\n%d of %d bombs on target" % [str(e.get("name", "Target")), status, hits, total], 14, UIKit.TEXT_DIM)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.custom_minimum_size = Vector2(220, 0)
		cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(cap)
		flow.add_child(col)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(UIKit.label("BOMB DAMAGE ASSESSMENT", 16, UIKit.ACCENT, true))
	box.add_child(flow)
	return box


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var k: float = minf(size.x, size.y) * 0.5 / SPAN       # pixels per metre
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.17, 0.21, 0.13))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.85, 0.80, 0.65, 0.5), false, 1.0)
	for ring in [50.0, 100.0]:
		draw_arc(c, ring * k, 0.0, TAU, 72, Color(1.0, 1.0, 1.0, 0.22), 1.0)
	draw_line(Vector2(c.x, 0.0), Vector2(c.x, size.y), Color(1.0, 1.0, 1.0, 0.12), 1.0)
	draw_line(Vector2(0.0, c.y), Vector2(size.x, c.y), Color(1.0, 1.0, 1.0, 0.12), 1.0)
	var r: float = float(_entry.get("r", 30.0))
	draw_circle(c, r * k, Color(0.42, 0.35, 0.26, 0.9))
	draw_arc(c, r * k, 0.0, TAU, 48, Color(0.95, 0.90, 0.70), 2.0)
	if bool(_entry.get("destroyed", false)):
		draw_arc(c, r * k + 5.0, 0.0, TAU, 48, Color(1.0, 0.35, 0.2, 0.8), 2.0)
	var edge: Vector2 = size * 0.5 - Vector2(4.0, 4.0)
	for mk in _entry.get("marks", []):
		var p: Vector2 = c + Vector2(float(mk.get("x", 0.0)), float(mk.get("z", 0.0))) * k
		if absf(p.x - c.x) > edge.x or absf(p.y - c.y) > edge.y:
			continue
		if bool(mk.get("hit", false)):
			draw_circle(p, 4.0, Color(1.0, 0.35, 0.15))
		else:
			draw_line(p + Vector2(-3.0, -3.0), p + Vector2(3.0, 3.0), Color(0.8, 0.8, 0.8, 0.8), 1.5)
			draw_line(p + Vector2(-3.0, 3.0), p + Vector2(3.0, -3.0), Color(0.8, 0.8, 0.8, 0.8), 1.5)
	draw_string(ThemeDB.fallback_font, Vector2(6.0, 16.0), "50 m / 100 m rings", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(1, 1, 1, 0.5))
