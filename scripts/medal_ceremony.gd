class_name MedalCeremony
extends CanvasLayer
## The presentation of a decoration: the medal drawn on its ribbon, its name and a citation written from the
## pilot's own record. Awards are queued by PilotLog (career "unseen_awards") and shown when it is safe to stop and
## look: on the ground and stopped, after a mission (over the results) or back at the start menu.
##   MedalCeremony.show_pending(parent, side) -> true if one is showing (the rest follow, one per click)

signal finished

const STYLE := {
	# ribbon: stripes (colour, width share) or "diag" for diagonal; shape: cross_flory / cross_pattee / iron /
	# star / leaf / disc / clasp; metal colour; bar: a silver bar on the ribbon
	"mid": {"ribbon": [[Color(0.75, 0.12, 0.12), 1], [Color(0.95, 0.95, 0.95), 1], [Color(0.1, 0.18, 0.5), 2], [Color(0.95, 0.95, 0.95), 1], [Color(0.75, 0.12, 0.12), 1]], "shape": "leaf", "metal": Color(0.72, 0.52, 0.26)},
	"dfc": {"ribbon": "diag", "diag": [Color(0.42, 0.18, 0.55), Color(0.95, 0.95, 0.95)], "shape": "cross_flory", "metal": Color(0.82, 0.83, 0.85)},
	"dfc_bar": {"ribbon": "diag", "diag": [Color(0.42, 0.18, 0.55), Color(0.95, 0.95, 0.95)], "shape": "cross_flory", "metal": Color(0.82, 0.83, 0.85), "bar": true},
	"dso": {"ribbon": [[Color(0.1, 0.15, 0.45), 1], [Color(0.72, 0.08, 0.1), 6], [Color(0.1, 0.15, 0.45), 1]], "shape": "cross_pattee", "metal": Color(0.85, 0.7, 0.3), "enamel": Color(0.96, 0.96, 0.94)},
	"dso_bar": {"ribbon": [[Color(0.1, 0.15, 0.45), 1], [Color(0.72, 0.08, 0.1), 6], [Color(0.1, 0.15, 0.45), 1]], "shape": "cross_pattee", "metal": Color(0.85, 0.7, 0.3), "enamel": Color(0.96, 0.96, 0.94), "bar": true},
	"asr": {"ribbon": [[Color(0.1, 0.25, 0.55), 2], [Color(0.9, 0.75, 0.2), 1], [Color(0.1, 0.25, 0.55), 2]], "shape": "disc", "metal": Color(0.72, 0.52, 0.26), "mark": "anchor"},
	"diver": {"ribbon": [[Color(0.15, 0.15, 0.2), 2], [Color(0.8, 0.2, 0.1), 1], [Color(0.15, 0.15, 0.2), 2]], "shape": "disc", "metal": Color(0.82, 0.83, 0.85), "mark": "wings"},
	"coastal": {"ribbon": [[Color(0.05, 0.25, 0.3), 2], [Color(0.9, 0.9, 0.9), 1], [Color(0.05, 0.25, 0.3), 2]], "shape": "disc", "metal": Color(0.72, 0.52, 0.26), "mark": "anchor"},
	"ground": {"ribbon": [[Color(0.35, 0.3, 0.15), 2], [Color(0.75, 0.12, 0.12), 1], [Color(0.35, 0.3, 0.15), 2]], "shape": "disc", "metal": Color(0.72, 0.52, 0.26), "mark": "swords"},
	"ek2": {"ribbon": [[Color(0.05, 0.05, 0.05), 1], [Color(0.95, 0.95, 0.95), 1], [Color(0.75, 0.1, 0.1), 3], [Color(0.95, 0.95, 0.95), 1], [Color(0.05, 0.05, 0.05), 1]], "shape": "iron", "metal": Color(0.8, 0.8, 0.82)},
	"ek1": {"ribbon": [], "shape": "iron", "metal": Color(0.8, 0.8, 0.82)},
	"ffs": {"ribbon": [], "shape": "clasp", "metal": Color(0.85, 0.7, 0.3)},
	"dkg": {"ribbon": [], "shape": "star", "metal": Color(0.82, 0.83, 0.85), "wreath": Color(0.85, 0.7, 0.3)},
	"rk": {"ribbon": [[Color(0.05, 0.05, 0.05), 1], [Color(0.95, 0.95, 0.95), 1], [Color(0.75, 0.1, 0.1), 3], [Color(0.95, 0.95, 0.95), 1], [Color(0.05, 0.05, 0.05), 1]], "shape": "iron", "metal": Color(0.85, 0.85, 0.88), "big": true},
	"seenot": {"ribbon": [[Color(0.85, 0.75, 0.2), 1], [Color(0.1, 0.25, 0.55), 3], [Color(0.85, 0.75, 0.2), 1]], "shape": "disc", "metal": Color(0.82, 0.83, 0.85), "mark": "anchor"},
	"anti_ship": {"ribbon": [[Color(0.1, 0.2, 0.4), 2], [Color(0.95, 0.95, 0.95), 1], [Color(0.1, 0.2, 0.4), 2]], "shape": "disc", "metal": Color(0.72, 0.52, 0.26), "mark": "anchor"},
}

var side: String = "Allies"
var award_id: String = ""
var award_name: String = ""
var _art: Control
var _t: float = 0.0
var _queue: Array = []


static func pending(side_: String) -> Array:
	var c: Dictionary = PilotLog.career(side_)
	return (c.get("unseen_awards", []) as Array).duplicate()


static func show_pending(parent: Node, side_: String) -> bool:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return false
	if not parent.get_tree().get_nodes_in_group("medal_ceremony").is_empty():
		return true
	var q: Array = pending(side_)
	if q.is_empty():
		return false
	var m := MedalCeremony.new()
	m.side = side_
	m._queue = q
	parent.add_child(m)
	return true


static func _mark_seen(side_: String, id: String) -> void:
	if PilotLog.debug_run():
		return
	var c: Dictionary = PilotLog.career(side_)
	var u: Array = c.get("unseen_awards", [])
	u.erase(id)
	c["unseen_awards"] = u
	PilotLog.save_career(side_, c)


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("medal_ceremony")
	_next()


func _next() -> void:
	for ch in get_children():
		ch.queue_free()
	if _queue.is_empty():
		finished.emit()
		queue_free()
		return
	award_id = str(_queue.pop_front())
	award_name = award_id
	for a in PilotLog.AWARDS[side]:
		if String(a[0]) == award_id:
			award_name = String(a[1])
	_t = 0.0
	_build()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.025, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(760, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	box.add_child(UIKit.label("AIR MINISTRY BULLETIN" if side == "Allies" else "VERLEIHUNGSURKUNDE", 16, UIKit.TEXT_DIM))
	_art = Control.new()
	_art.custom_minimum_size = Vector2(760, 300)
	_art.draw.connect(_draw_medal)
	box.add_child(_art)
	var title := UIKit.label(award_name.to_upper(), 30, UIKit.TEXT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var cit := UIKit.label(_citation(), 17, UIKit.TEXT)
	cit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cit)
	var b := UIKit.button("Carry on" if not _queue.is_empty() else "Dismissed", func() -> void:
		_mark_seen(side, award_id)
		_next(), 18)
	box.add_child(b)
	b.grab_focus.call_deferred()


func _citation() -> String:
	var c: Dictionary = PilotLog.career(side)
	var rank: String = PilotLog.rank_of(side, int(c["points"]))
	var who: String = "%s %s" % [rank, Radio.player_callsign]
	var ops: int = int(c["done"]) + int(c["missions"])
	var air: int = int(c["air"])
	var ships: int = int(c["ships"])
	var ground: int = int(c["ground"])
	var deeds: Array = []
	if ops > 0:
		deeds.append(_n(ops, "operational sortie"))
	if air > 0:
		deeds.append("%d enemy aircraft destroyed" % air)
	if ships > 0:
		deeds.append(_n(ships, "vessel") + " sunk")
	if ground > 0:
		deeds.append(_n(ground, "ground target") + " destroyed")
	if int(c["rescues"]) > 0:
		deeds.append(_n(int(c["rescues"]), "air-sea rescue"))
	if int(c["v1"]) > 0:
		deeds.append(_n(int(c["v1"]), "flying bomb") + " brought down")
	var record: String = ", ".join(deeds) if not deeds.is_empty() else "many hours over the Channel"
	if side == "Allies":
		match award_id:
			"mid":
				return "%s is mentioned in despatches for distinguished service. His record: %s." % [who, record]
			"asr", "coastal", "diver", "ground":
				return "%s is commended for valuable service in the air. His record: %s." % [who, record]
			_:
				return "%s has completed %s. He has shown the greatest skill, courage and determination, often in the face of heavy opposition, and his example has been an inspiration to his squadron." % [who, record]
	else:
		match award_id:
			"ek2", "ek1":
				return "In recognition of bravery before the enemy, %s is awarded the %s. Record: %s." % [who, award_name, record]
			_:
				return "%s is honoured for outstanding achievement in the air war over the Channel. Record: %s." % [who, record]


static func _n(n: int, noun: String) -> String:
	return "%d %s%s" % [n, noun, "" if n == 1 else "s"]


func _process(delta: float) -> void:
	_t += delta
	if _art != null and _t < 2.0:
		_art.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_mark_seen(side, award_id)
		_next()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ the medal

func _draw_medal() -> void:
	var st: Dictionary = STYLE.get(award_id, STYLE["mid"])
	var w: float = _art.size.x
	var k: float = clampf(_t / 0.8, 0.0, 1.0)
	var drop: float = (1.0 - k * k * (3.0 - 2.0 * k)) * -40.0
	var a: float = k
	var cx: float = w * 0.5
	var top: float = 10.0 + drop
	var ribbon = st.get("ribbon", [])
	var big: bool = bool(st.get("big", false))
	var rw: float = 78.0
	var rh: float = 110.0
	var medal_y: float = top + 40.0
	if typeof(ribbon) == TYPE_STRING or (ribbon is Array and not (ribbon as Array).is_empty()):
		# ribbon, folded to a point-down at its base
		var r0 := Vector2(cx - rw * 0.5, top)
		if typeof(ribbon) == TYPE_STRING:
			var cols: Array = st["diag"]
			_art.draw_rect(Rect2(r0, Vector2(rw, rh)), Color(cols[0], a))
			var stripe: float = 9.0
			var rect_poly := PackedVector2Array([r0, r0 + Vector2(rw, 0), r0 + Vector2(rw, rh), r0 + Vector2(0, rh)])
			var x: float = -rh
			var n: int = 0
			while x < rw:
				if n % 2 == 1:
					var p := PackedVector2Array([r0 + Vector2(x, rh), r0 + Vector2(x + stripe, rh), r0 + Vector2(x + stripe + rh, 0.0), r0 + Vector2(x + rh, 0.0)])
					for piece in Geometry2D.intersect_polygons(p, rect_poly):
						_art.draw_colored_polygon(piece, Color(cols[1], a))
				x += stripe
				n += 1
		else:
			var total: float = 0.0
			for s in ribbon:
				total += float(s[1])
			var x2: float = r0.x
			for s in ribbon:
				var sw: float = rw * float(s[1]) / total
				_art.draw_rect(Rect2(Vector2(x2, r0.y), Vector2(sw + 0.5, rh)), Color(s[0], a))
				x2 += sw
		_art.draw_rect(Rect2(r0, Vector2(rw, rh)), Color(0, 0, 0, 0.35 * a), false, 1.5)
		if bool(st.get("bar", false)):
			_art.draw_rect(Rect2(r0 + Vector2(-4, rh * 0.42), Vector2(rw + 8, 12)), Color(0.85, 0.86, 0.88, a))
			_art.draw_rect(Rect2(r0 + Vector2(-4, rh * 0.42), Vector2(rw + 8, 12)), Color(0.4, 0.4, 0.42, a), false, 1.0)
		# suspender ring
		_art.draw_arc(Vector2(cx, top + rh + 6.0), 7.0, 0.0, TAU, 16, Color(st["metal"], a), 3.0)
		medal_y = top + rh + 14.0
	var c := Vector2(cx, medal_y + (70.0 if not big else 85.0))
	var R: float = 64.0 if not big else 80.0
	var metal: Color = Color(st["metal"], a)
	var dark := Color(metal.darkened(0.45), a)
	match str(st["shape"]):
		"cross_flory", "cross_pattee", "iron":
			_cross(c, R, str(st["shape"]), metal, dark, st, a)
		"star":
			_star(c, R, metal, dark, st, a)
		"leaf":
			_leaf(c, R, metal, dark, a)
		"clasp":
			_clasp(c, R, metal, dark, a)
		_:
			_art.draw_circle(c, R * 0.82, dark)
			_art.draw_circle(c, R * 0.76, metal)
			_art.draw_arc(c, R * 0.62, 0.0, TAU, 40, dark, 2.0)
			_mark(c, R * 0.5, str(st.get("mark", "")), dark)


## A four-armed cross: flory (DFC, flared tips with a central roundel), pattée (DSO, enamelled), iron (black with
## a silver border; the centre carries only the year of institution).
func _cross(c: Vector2, R: float, kind: String, metal: Color, dark: Color, st: Dictionary, a: float) -> void:
	for arm in 4:
		var ang: float = arm * PI * 0.5 - PI * 0.5
		var d := Vector2(cos(ang), sin(ang))
		var s := Vector2(-d.y, d.x)
		var inner: float = R * 0.16
		var outer: float = R
		var wi: float = R * (0.14 if kind != "cross_flory" else 0.12)
		var wo: float = R * (0.42 if kind != "cross_flory" else 0.3)
		var poly := PackedVector2Array([c + d * inner + s * wi, c + d * outer + s * wo, c + d * (outer - (R * 0.08 if kind == "iron" else 0.0)), c + d * outer - s * wo, c + d * inner - s * wi])
		if kind == "iron":
			_art.draw_colored_polygon(poly, metal)
			var shrink := PackedVector2Array()
			for q in poly:
				shrink.append(c + (q - c) * 0.84)
			_art.draw_colored_polygon(shrink, Color(0.06, 0.06, 0.07, a))
		else:
			_art.draw_colored_polygon(poly, metal)
			_art.draw_polyline(poly + PackedVector2Array([poly[0]]), dark, 1.5)
			if st.has("enamel"):
				var en := PackedVector2Array()
				for q in poly:
					en.append(c + (q - c) * 0.8)
				_art.draw_colored_polygon(en, Color(st["enamel"], a))
			if kind == "cross_flory":
				_art.draw_circle(c + d * outer, R * 0.09, metal)       # the fleur tips
	if kind == "iron":
		_txt_center(c, "1939", 14, Color(0.85, 0.85, 0.88, a))
	elif kind == "cross_flory":
		_art.draw_circle(c, R * 0.24, dark)
		_art.draw_circle(c, R * 0.2, metal)
		_txt_center(c, "RAF", 12, dark)
	else:
		_art.draw_circle(c, R * 0.24, Color(0.75, 0.1, 0.12, a))
		_art.draw_arc(c, R * 0.24, 0.0, TAU, 24, metal, 2.0)


func _star(c: Vector2, R: float, metal: Color, dark: Color, st: Dictionary, a: float) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var ang: float = i * PI / 8.0 - PI * 0.5
		var r: float = R if i % 2 == 0 else R * 0.62
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	_art.draw_colored_polygon(pts, metal)
	_art.draw_polyline(pts + PackedVector2Array([pts[0]]), dark, 1.5)
	_art.draw_circle(c, R * 0.42, Color(st["wreath"], a))
	for i in 18:
		var ang2: float = i * TAU / 18.0
		_art.draw_circle(c + Vector2(cos(ang2), sin(ang2)) * R * 0.36, R * 0.07, Color(Color(st["wreath"]).darkened(0.3), a))
	_art.draw_circle(c, R * 0.27, Color(0.9, 0.9, 0.9, a))
	_txt_center(c, "1941", 13, Color(0.1, 0.1, 0.1, a))


func _leaf(c: Vector2, R: float, metal: Color, dark: Color, a: float) -> void:
	# a bronze oak leaf
	var pts := PackedVector2Array()
	for i in 25:
		var t: float = float(i) / 24.0
		var y: float = lerpf(-R, R * 0.8, t)
		var w: float = sin(t * PI) * R * 0.42 * (0.85 + 0.15 * sin(t * PI * 7.0))
		pts.append(c + Vector2(w, y))
	for i in range(24, -1, -1):
		var t2: float = float(i) / 24.0
		var y2: float = lerpf(-R, R * 0.8, t2)
		var w2: float = sin(t2 * PI) * R * 0.42 * (0.85 + 0.15 * sin(t2 * PI * 7.0 + 0.6))
		pts.append(c + Vector2(-w2, y2))
	_art.draw_colored_polygon(pts, metal)
	_art.draw_polyline(pts, dark, 1.5)
	_art.draw_line(c + Vector2(0, -R * 0.9), c + Vector2(0, R * 1.05), dark, 2.0)


func _clasp(c: Vector2, R: float, metal: Color, dark: Color, a: float) -> void:
	var r := Rect2(c - Vector2(R * 1.4, R * 0.18), Vector2(R * 2.8, R * 0.36))
	_art.draw_rect(r, metal)
	_art.draw_rect(r, dark, false, 1.5)
	for i in 12:
		var x: float = r.position.x + R * 0.2 + i * R * 0.2
		_art.draw_circle(Vector2(x, c.y), R * 0.06, dark)
	_art.draw_circle(c, R * 0.42, metal)
	_art.draw_arc(c, R * 0.42, 0.0, TAU, 32, dark, 2.0)
	_mark(c, R * 0.3, "wings", dark)


func _mark(c: Vector2, r: float, mark: String, col: Color) -> void:
	match mark:
		"anchor":
			_art.draw_line(c + Vector2(0, -r), c + Vector2(0, r * 0.9), col, 3.0)
			_art.draw_line(c + Vector2(-r * 0.45, -r * 0.55), c + Vector2(r * 0.45, -r * 0.55), col, 3.0)
			_art.draw_arc(c + Vector2(0, r * 0.2), r * 0.7, 0.3, PI - 0.3, 16, col, 3.0)
		"swords":
			_art.draw_line(c + Vector2(-r, -r), c + Vector2(r, r), col, 3.0)
			_art.draw_line(c + Vector2(r, -r), c + Vector2(-r, r), col, 3.0)
		_:
			_art.draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), col, 3.0)
			_art.draw_arc(c + Vector2(-r * 0.5, r * 0.1), r * 0.5, PI, TAU, 10, col, 2.0)
			_art.draw_arc(c + Vector2(r * 0.5, r * 0.1), r * 0.5, PI, TAU, 10, col, 2.0)
			_art.draw_circle(c, r * 0.22, col)


func _txt_center(c: Vector2, t: String, size: int, col: Color) -> void:
	var f: Font = UIKit.font()
	var w: float = f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_art.draw_string(f, c + Vector2(-w * 0.5, size * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
