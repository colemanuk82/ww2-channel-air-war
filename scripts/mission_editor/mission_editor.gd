class_name MissionEditor
extends CanvasLayer
## Mission Editor, opened from the start menu. First a list of missions (your own and the examples) to fly, edit,
## copy or delete; then the editor: a map of the whole theatre on the left, where you place the player's start, units
## (aircraft flights, vehicle columns, ships, buildings, flak, real targets), zones and routes; and on the right tabs
## for the mission settings, units, zones, objectives and triggers. Test Fly plays the mission straight away and the
## game comes back to the editor afterwards. Files: MissionDoc. Play: CustomMissionMode.

signal closed
signal play_requested(cfg: Dictionary)

## Set before adding to the tree to open a document straight in the editor (coming back from a test flight).
var open_doc: Dictionary = {}
var open_path: String = ""

var doc: Dictionary = {}
var path: String = ""
var dirty: bool = false
var tool: String = "select"          # select | place | zone | start | route
var place_kind: String = ""
var sel: Dictionary = {"type": "", "id": ""}    # type: unit | zone | start | ""

var _root: Control
var _hub: Control
var _hub_list: ItemList
var _hub_info: Label
var _hub_entries: Array = []
var _ed: Control
var _map: EdMap
var _tabs: TabContainer
var _pages: Dictionary = {}          # tab name -> VBoxContainer (the scrolled content)
var _lists: Dictionary = {}          # group -> ItemList
var _forms: Dictionary = {}          # group -> VBoxContainer
var _status: Label
var _title: Label
var _tool_label: Label
var _dialog: AcceptDialog
var _confirm: ConfirmationDialog
var _save_prompt: ConfirmationDialog

const BLUE := Color(0.35, 0.65, 1.0)
const RED := Color(1.0, 0.38, 0.32)
const GOLD := Color(1.0, 0.85, 0.2)
const ZONE_COL := Color(1.0, 0.82, 0.3)
const GROUPS := ["units", "zones", "objectives", "triggers"]
const TAB_OF := {"units": 1, "zones": 2, "objectives": 3, "triggers": 4}


# ================================================================== map
class EdMap extends Control:
	var ed: MissionEditor
	var tex: Texture2D
	var zoom: float = 6.0
	var center: Vector2 = Vector2(0.4, 0.55)
	var _pan: bool = false
	var _drag: Dictionary = {}       # {type, id, idx} of what is being dragged
	var _press: Vector2 = Vector2.ZERO
	var _moved: float = 0.0
	var _mouse: Vector2 = Vector2.ZERO

	func _init() -> void:
		clip_contents = true
		focus_mode = Control.FOCUS_CLICK

	func _aspect() -> float:
		return float(tex.get_width()) / float(tex.get_height()) if tex != null else 2.05

	func _map_size() -> Vector2:
		var base: float = minf(size.x, size.y * _aspect())
		return Vector2(base * zoom, base * zoom / _aspect())

	func to_screen(lat: float, lon: float) -> Vector2:
		var u: float = (lon - WorldCoords.LON_MIN) / (WorldCoords.LON_MAX - WorldCoords.LON_MIN)
		var v: float = (WorldCoords.LAT_MAX - lat) / (WorldCoords.LAT_MAX - WorldCoords.LAT_MIN)
		var ms: Vector2 = _map_size()
		return size * 0.5 + Vector2((u - center.x) * ms.x, (v - center.y) * ms.y)

	func to_latlon(p: Vector2) -> Vector2:
		var ms: Vector2 = _map_size()
		var uv: Vector2 = center + (p - size * 0.5) / ms
		return Vector2(WorldCoords.LAT_MAX - uv.y * (WorldCoords.LAT_MAX - WorldCoords.LAT_MIN), WorldCoords.LON_MIN + uv.x * (WorldCoords.LON_MAX - WorldCoords.LON_MIN))

	func look_at_latlon(lat: float, lon: float) -> void:
		center = Vector2((lon - WorldCoords.LON_MIN) / (WorldCoords.LON_MAX - WorldCoords.LON_MIN), (WorldCoords.LAT_MAX - lat) / (WorldCoords.LAT_MAX - WorldCoords.LAT_MIN))
		queue_redraw()

	## Pixels per kilometre at the current zoom (north-south, which is what the zones use).
	func px_per_km() -> float:
		return absf(to_screen(51.0, 1.0).y - to_screen(51.0 + 1.0 / 111.0, 1.0).y)

	## What is under the mouse: {type: unit | zone | start | wp, id, idx}.
	func hit(p: Vector2) -> Dictionary:
		var best: Dictionary = {}
		var bd: float = 14.0
		var d: Dictionary = ed.doc
		var su: Dictionary = MissionDoc.find(d.get("units", []), str(ed.sel.get("id", ""))) if ed.sel.get("type", "") == "unit" else {}
		if not su.is_empty():
			var rt: Array = su.get("route", [])
			for i in rt.size():
				var q: float = to_screen(float(rt[i][0]), float(rt[i][1])).distance_to(p)
				if q < bd:
					bd = q
					best = {"type": "wp", "id": str(su["id"]), "idx": i}
		for u in d.get("units", []):
			var q2: float = to_screen(float(u["lat"]), float(u["lon"])).distance_to(p)
			if q2 < bd:
				bd = q2
				best = {"type": "unit", "id": str(u["id"])}
		var st: Dictionary = d.get("start", {})
		if st.has("lat"):
			var q3: float = to_screen(float(st["lat"]), float(st["lon"])).distance_to(p)
			if q3 < bd:
				bd = q3
				best = {"type": "start", "id": "start"}
		if best.is_empty():
			for z in d.get("zones", []):
				var c: Vector2 = to_screen(float(z["lat"]), float(z["lon"]))
				var r: float = maxf(float(z.get("radius", 2.0)) * px_per_km(), 10.0)
				if c.distance_to(p) < r and (best.is_empty() or c.distance_to(p) < bd):
					bd = c.distance_to(p)
					best = {"type": "zone", "id": str(z["id"])}
		return best

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if not mb.pressed:
					return
				var before: Vector2 = to_latlon(mb.position)
				zoom = clampf(zoom * (1.2 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2), 1.0, 60.0)
				var after: Vector2 = to_screen(before.x, before.y)
				center += (after - mb.position) / _map_size()
				_clamp()
				queue_redraw()
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					_pan = true
					_press = mb.position
					_moved = 0.0
				else:
					_pan = false
					if mb.button_index == MOUSE_BUTTON_RIGHT and _moved < 6.0:
						ed.map_right_click(mb.position, hit(mb.position))
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_press = mb.position
					_moved = 0.0
					_drag = {}
					if ed.tool == "select":
						var h: Dictionary = hit(mb.position)
						if not h.is_empty():
							_drag = h
							ed.select_from_map(h)
						else:
							_pan = true
				else:
					var was_pan: bool = _pan
					_pan = false
					if not _drag.is_empty():
						if _moved >= 4.0:
							ed.item_moved()
						_drag = {}
					elif _moved < 6.0:
						var ll: Vector2 = to_latlon(mb.position)
						ed.map_click(ll.x, ll.y, mb.position)
					elif was_pan:
						pass
				accept_event()
		elif event is InputEventMouseMotion:
			var mm: InputEventMouseMotion = event
			_mouse = mm.position
			_moved += mm.relative.length()
			if not _drag.is_empty() and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
				var ll2: Vector2 = to_latlon(mm.position)
				ed.drag_item(_drag, ll2.x, ll2.y)
			elif _pan:
				center -= mm.relative / _map_size()
				_clamp()
			queue_redraw()

	func _clamp() -> void:
		center = Vector2(clampf(center.x, 0.0, 1.0), clampf(center.y, 0.0, 1.0))

	func _visible(p: Vector2) -> bool:
		return p.x > -40 and p.y > -40 and p.x < size.x + 40 and p.y < size.y + 40

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.09))
		var ms: Vector2 = _map_size()
		var tl: Vector2 = size * 0.5 - Vector2(center.x * ms.x, center.y * ms.y)
		if tex != null:
			draw_texture_rect(tex, Rect2(tl, ms), false)
		var font: Font = UIKit.font()
		var bold: Font = UIKit.font(true)
		# airfields (friendly blue, enemy red), names when zoomed in
		for a in MissionDoc.airfields():
			var ap: Vector2 = to_screen(float(a["lat"]), float(a["lon"]))
			if not _visible(ap):
				continue
			var ac: Color = BLUE if str(a["side"]) == "RAF" else RED
			draw_circle(ap, 4.0, Color(0, 0, 0, 0.7))
			draw_circle(ap, 2.8, ac.darkened(0.15))
			if zoom >= 5.0:
				draw_string(font, ap + Vector2(6, 4), str(a["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(ac.lightened(0.3), 0.8))
		var d: Dictionary = ed.doc
		var me_side: String = str(d.get("side", "Allies"))
		var pk: float = px_per_km()
		# zones
		for z in d.get("zones", []):
			var zc: Vector2 = to_screen(float(z["lat"]), float(z["lon"]))
			var zr: float = maxf(float(z.get("radius", 2.0)) * pk, 6.0)
			var zsel: bool = ed.sel.get("type", "") == "zone" and ed.sel.get("id", "") == str(z["id"])
			draw_circle(zc, zr, Color(ZONE_COL, 0.12 if not zsel else 0.22))
			draw_arc(zc, zr, 0.0, TAU, 64, Color(ZONE_COL, 0.85), 2.5 if zsel else 1.5)
			draw_string(bold, zc + Vector2(-zr * 0.0 - 30, -zr - 6), str(z.get("name", z["id"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ZONE_COL)
		# routes
		for u in d.get("units", []):
			var rt: Array = u.get("route", [])
			if rt.is_empty():
				continue
			var usel: bool = ed.sel.get("type", "") == "unit" and ed.sel.get("id", "") == str(u["id"])
			var rc: Color = (BLUE if str(u["side"]) == me_side else RED)
			rc.a = 0.95 if usel else 0.45
			var prev: Vector2 = to_screen(float(u["lat"]), float(u["lon"]))
			for i in rt.size():
				var wp: Vector2 = to_screen(float(rt[i][0]), float(rt[i][1]))
				_dashed(prev, wp, rc, 2.0 if usel else 1.4)
				draw_circle(wp, 5.0 if usel else 3.5, rc)
				if usel:
					draw_string(font, wp + Vector2(7, -5), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
				prev = wp
		# units
		for u2 in d.get("units", []):
			var up: Vector2 = to_screen(float(u2["lat"]), float(u2["lon"]))
			if not _visible(up):
				continue
			var col: Color = BLUE if str(u2["side"]) == me_side else RED
			var later: bool = not bool(u2.get("active", true))
			_unit_icon(up, str(u2.get("kind", "")), float(u2.get("heading", 0.0)), col, later)
			var s2: bool = ed.sel.get("type", "") == "unit" and ed.sel.get("id", "") == str(u2["id"])
			if s2:
				draw_arc(up, 13.0, 0.0, TAU, 28, GOLD, 2.5)
			var lbl: String = "%s x%d" % [str(u2.get("name", u2["id"])), int(u2.get("count", 1))] if str(u2.get("kind", "")) != "world" else str(u2.get("name", u2["id"]))
			if later:
				lbl += "  (later)"
			draw_string(bold, up + Vector2(11, 5), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col.lightened(0.35))
		# player start
		var st: Dictionary = d.get("start", {})
		if st.has("lat"):
			var sp: Vector2 = to_screen(float(st["lat"]), float(st["lon"]))
			var dirv := Vector2(sin(deg_to_rad(float(st.get("heading", 0.0)))), -cos(deg_to_rad(float(st.get("heading", 0.0)))))
			var ssel: bool = ed.sel.get("type", "") == "start"
			draw_circle(sp, 9.0, Color(0, 0, 0, 0.6))
			draw_arc(sp, 9.0, 0.0, TAU, 24, GOLD, 3.0 if ssel else 2.0)
			draw_line(sp, sp + dirv * 34.0, GOLD, 3.0)
			draw_line(sp + dirv * 34.0, sp + dirv * 26.0 + Vector2(-dirv.y, dirv.x) * 6.0, GOLD, 3.0)
			draw_line(sp + dirv * 34.0, sp + dirv * 26.0 - Vector2(-dirv.y, dirv.x) * 6.0, GOLD, 3.0)
			var af: Dictionary = MissionDoc.airfield(str(st.get("airfield", "")))
			var stxt: String = "START" + ("  " + str(af["name"]) if not af.is_empty() else "") + ("" if bool(st.get("airborne", true)) or af.is_empty() else "  (runway)")
			draw_string(bold, sp + Vector2(12, 22), stxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GOLD)
		# tool hint and cursor position
		var hint: String = ed.tool_hint()
		draw_rect(Rect2(Vector2(8, 8), Vector2(minf(size.x - 16, 760), 26)), Color(0, 0, 0, 0.55))
		draw_string(font, Vector2(16, 27), hint, HORIZONTAL_ALIGNMENT_LEFT, size.x - 30, 15, Color(1, 1, 1, 0.9))
		var cll: Vector2 = to_latlon(_mouse)
		draw_string(font, Vector2(14, size.y - 12), "%.3f N  %.3f E      wheel: zoom   right-drag: pan" % [cll.x, cll.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.7))
		draw_string(bold, Vector2(size.x - 24, 28), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))

	func _dashed(a: Vector2, b: Vector2, c: Color, w: float) -> void:
		var L: float = a.distance_to(b)
		if L < 1.0:
			return
		var dir: Vector2 = (b - a) / L
		var t: float = 0.0
		while t < L:
			draw_line(a + dir * t, a + dir * minf(t + 9.0, L), c, w)
			t += 15.0

	func _unit_icon(p: Vector2, kind: String, hdg: float, col: Color, hollow: bool) -> void:
		var fill: Color = Color(col, 0.25) if hollow else col
		draw_circle(p, 9.5, Color(0, 0, 0, 0.55))
		match kind:
			"flight":
				var f := Vector2(sin(deg_to_rad(hdg)), -cos(deg_to_rad(hdg)))
				var r := Vector2(-f.y, f.x)
				var pts := PackedVector2Array([p + f * 9.0, p - f * 6.0 + r * 7.0, p - f * 3.0, p - f * 6.0 - r * 7.0])
				draw_colored_polygon(pts, fill)
				draw_polyline(pts + PackedVector2Array([pts[0]]), col, 1.5)
			"vehicles":
				draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), fill)
				draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), col, false, 1.5)
			"ships":
				var sp := PackedVector2Array([p + Vector2(-10, 0), p + Vector2(-4, -5), p + Vector2(10, 0), p + Vector2(-4, 5)])
				draw_colored_polygon(sp, fill)
				draw_polyline(sp + PackedVector2Array([sp[0]]), col, 1.5)
			"flak":
				draw_circle(p, 6.0, fill)
				draw_line(p + Vector2(-8, 0), p + Vector2(8, 0), col, 1.5)
				draw_line(p + Vector2(0, -8), p + Vector2(0, 8), col, 1.5)
			_:
				var hp := PackedVector2Array([p + Vector2(0, -8), p + Vector2(8, 0), p + Vector2(0, 8), p + Vector2(-8, 0)])
				draw_colored_polygon(hp, fill)
				draw_polyline(hp + PackedVector2Array([hp[0]]), col, 1.5)


# ================================================================== setup
func _ready() -> void:
	layer = 46
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var bg := ColorRect.new()          # opaque: the start menu must not show through the editor
	bg.color = Color(0.035, 0.04, 0.04, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(bg)
	_root.add_child(UIKit.dimmer(0.5))
	_dialog = AcceptDialog.new()
	_dialog.title = "Mission Editor"
	add_child(_dialog)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Mission Editor"
	add_child(_confirm)
	# leaving the editor with unsaved changes: Save / Discard / Cancel
	_save_prompt = ConfirmationDialog.new()
	_save_prompt.title = "Unsaved changes"
	_save_prompt.ok_button_text = "Save"
	_save_prompt.add_button("Discard", true, "discard")
	_save_prompt.confirmed.connect(func() -> void:
		if _save():
			_show_hub())
	_save_prompt.custom_action.connect(func(a: StringName) -> void:
		if a == &"discard":
			dirty = false
			_save_prompt.hide()
			_show_hub())
	add_child(_save_prompt)
	_build_hub()
	_build_editor()
	if not open_doc.is_empty():
		_edit(open_doc, open_path)
		dirty = open_path == ""
	else:
		_show_hub()


func _say(text: String) -> void:
	_dialog.dialog_text = text
	_dialog.popup_centered(Vector2i(640, 0))


func _ask(text: String, ok_text: String, on_ok: Callable) -> void:
	_confirm.dialog_text = text
	_confirm.ok_button_text = ok_text
	for c in _confirm.confirmed.get_connections():
		_confirm.confirmed.disconnect(c["callable"])
	_confirm.confirmed.connect(on_ok, CONNECT_ONE_SHOT)
	_confirm.popup_centered(Vector2i(560, 0))


# ================================================================== hub: the mission list
func _build_hub() -> void:
	_hub = Control.new()
	_hub.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_hub)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hub.add_child(center)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UIKit.panel_style())
	pc.custom_minimum_size = Vector2(1100, 640)
	center.add_child(pc)
	var m := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(k, 24)
	pc.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	m.add_child(vb)
	UIKit.heading(vb, "MISSION EDITOR", 32)
	var sub := UIKit.label("Build your own sorties: place the units, write the objectives, script what happens with triggers, then fly them. Your missions are saved on this computer.", 15, UIKit.TEXT_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_override("font", UIKit.body_font())
	vb.add_child(sub)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(hb)
	_hub_list = ItemList.new()
	_hub_list.custom_minimum_size = Vector2(430, 0)
	_hub_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_list(_hub_list)
	_hub_list.item_selected.connect(func(_i: int) -> void: _hub_show_info())
	_hub_list.item_activated.connect(func(_i: int) -> void: _hub_edit())
	hb.add_child(_hub_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	hb.add_child(right)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(sc)
	_hub_info = UIKit.label("", 16, UIKit.TEXT)
	_hub_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hub_info.add_theme_font_override("font", UIKit.body_font())
	_hub_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_hub_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	for b in [["FLY", _hub_fly, true], ["Edit", _hub_edit, false], ["New mission", _hub_new, false], ["Copy", _hub_copy, false], ["Delete", _hub_delete, false], ["Back", func() -> void: closed.emit(), false]]:
		var bt: Button = UIKit.button(String(b[0]), b[1], 20, bool(b[2]))
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bt)


func _style_list(il: ItemList) -> void:
	il.add_theme_font_override("font", UIKit.font())
	il.add_theme_font_size_override("font_size", 17)
	il.add_theme_color_override("font_color", UIKit.TEXT)
	il.add_theme_color_override("font_selected_color", Color(0.1, 0.08, 0.03))
	il.add_theme_stylebox_override("panel", UIKit._box(UIKit.FIELD, Color(UIKit.PANEL_EDGE, 0.35), 1))
	il.add_theme_stylebox_override("selected", UIKit._box(UIKit.ACCENT, UIKit.ACCENT, 0))
	il.add_theme_stylebox_override("selected_focus", UIKit._box(UIKit.ACCENT_HOT, UIKit.ACCENT_HOT, 0))


func _show_hub() -> void:
	_ed.visible = false
	_hub.visible = true
	_hub_entries = MissionDoc.list_all()
	_hub_list.clear()
	for e in _hub_entries:
		_hub_list.add_item(("%s   (example)" % e["name"]) if bool(e["bundled"]) else str(e["name"]))
	if not _hub_entries.is_empty():
		_hub_list.select(0)
	_hub_show_info()


func _hub_sel() -> Dictionary:
	var s: PackedInt32Array = _hub_list.get_selected_items()
	if s.is_empty() or s[0] >= _hub_entries.size():
		return {}
	return _hub_entries[s[0]]


func _hub_show_info() -> void:
	var e: Dictionary = _hub_sel()
	if e.is_empty():
		_hub_info.text = "No missions yet. Press New mission to build one."
		return
	var d: Dictionary = e["doc"]
	var lines: Array = [str(d.get("name", "")).to_upper()]
	if str(d.get("author", "")) != "":
		lines.append("by " + str(d["author"]))
	lines.append("")
	lines.append(str(d.get("briefing", "")) if str(d.get("briefing", "")) != "" else "(no briefing)")
	lines.append("")
	lines.append("%s, flying the %s.   %s, %s%s." % [str(d.get("side", "")), AircraftCatalog.display_name(str(d.get("aircraft", "spitfire"))), str(d.get("time", "noon")).capitalize(), str(d.get("weather", "clear")), (", " + str(d["date"])) if str(d.get("date", "")) != "" else ""])
	lines.append("%d units, %d objectives, %d triggers." % [(d.get("units", []) as Array).size(), (d.get("objectives", []) as Array).size(), (d.get("triggers", []) as Array).size()])
	if bool(e["bundled"]):
		lines.append("\nAn example mission: Edit opens a copy you can change.")
	_hub_info.text = "\n".join(lines)


func _hub_fly() -> void:
	var e: Dictionary = _hub_sel()
	if e.is_empty():
		return
	var v: Dictionary = MissionDoc.validate(e["doc"])
	if not (v["errors"] as PackedStringArray).is_empty():
		_say("This mission cannot be flown yet:\n\n- " + "\n- ".join(v["errors"]))
		return
	play_requested.emit(MissionDoc.start_config(e["doc"], str(e["path"]), false))


func _hub_edit() -> void:
	var e: Dictionary = _hub_sel()
	if e.is_empty():
		return
	if bool(e["bundled"]):
		var copy: Dictionary = (e["doc"] as Dictionary).duplicate(true)
		copy["name"] = str(copy.get("name", "Mission")) + " (copy)"
		_edit(copy, "")
		dirty = true
	else:
		_edit((e["doc"] as Dictionary).duplicate(true), str(e["path"]))


func _hub_new() -> void:
	_edit(MissionDoc.new_doc(GameState.player_side if GameState.player_side in MissionDoc.SIDES else "Allies"), "")
	dirty = true


func _hub_copy() -> void:
	var e: Dictionary = _hub_sel()
	if e.is_empty():
		return
	var copy: Dictionary = (e["doc"] as Dictionary).duplicate(true)
	copy["name"] = str(copy.get("name", "Mission")) + " (copy)"
	MissionDoc.save(copy)
	_show_hub()


func _hub_delete() -> void:
	var e: Dictionary = _hub_sel()
	if e.is_empty():
		return
	if bool(e["bundled"]):
		_say("The examples come with the game and cannot be deleted.")
		return
	_ask("Delete \"%s\"? This cannot be undone." % e["name"], "Delete", func() -> void:
		MissionDoc.delete(str(e["path"]))
		_show_hub())


# ================================================================== editor layout
func _build_editor() -> void:
	_ed = VBoxContainer.new()
	_ed.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ed.offset_left = 14.0
	_ed.offset_top = 12.0
	_ed.offset_right = -14.0
	_ed.offset_bottom = -12.0
	(_ed as VBoxContainer).add_theme_constant_override("separation", 8)
	_root.add_child(_ed)
	# top bar: title + map tools
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	_ed.add_child(top)
	_title = UIKit.label("", 22, UIKit.ACCENT, true)
	_title.custom_minimum_size = Vector2(320, 0)
	_title.clip_text = true
	top.add_child(_title)
	for t in [["Select / move", "select"], ["Set start", "start"], ["Add zone", "zone"], ["Draw route", "route"]]:
		var tid: String = String(t[1])
		top.add_child(UIKit.button(String(t[0]), func() -> void: set_tool(tid), 16))
	var addm := MenuButton.new()
	addm.text = "Add unit"
	addm.flat = false
	UIKit._style_button(addm, 16, false)
	var pm: PopupMenu = addm.get_popup()
	pm.add_theme_font_override("font", UIKit.font())
	pm.add_theme_font_size_override("font_size", 16)
	var kinds: Array = MissionDoc.UNIT_KINDS.keys()
	for i in kinds.size():
		pm.add_item(str(MissionDoc.UNIT_KINDS[kinds[i]]["label"]), i)
	pm.id_pressed.connect(func(i: int) -> void: set_tool("place", str(kinds[i])))
	top.add_child(addm)
	_tool_label = UIKit.label("", 15, UIKit.TEXT_DIM)
	_tool_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_tool_label)
	# map + side panel
	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 12)
	_ed.add_child(hb)
	_map = EdMap.new()
	_map.ed = self
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if ResourceLoader.exists((WorldCoords.heightmap_dir() + "/region_color.png")):
		_map.tex = load((WorldCoords.heightmap_dir() + "/region_color.png")) as Texture2D
	hb.add_child(_map)
	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", UIKit.panel_style())
	side.custom_minimum_size = Vector2(520, 0)
	hb.add_child(side)
	_tabs = TabContainer.new()
	_tabs.add_theme_font_override("font", UIKit.font(true))
	_tabs.add_theme_font_size_override("font_size", 16)
	side.add_child(_tabs)
	for tab_name in ["Mission", "Units", "Zones", "Objectives", "Triggers"]:
		var sc := ScrollContainer.new()
		sc.name = tab_name
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_tabs.add_child(sc)
		var m := MarginContainer.new()
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			m.add_theme_constant_override(k, 12)
		sc.add_child(m)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 8)
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m.add_child(vb)
		_pages[tab_name] = vb
	# bottom bar
	var bot := HBoxContainer.new()
	bot.add_theme_constant_override("separation", 10)
	_ed.add_child(bot)
	_status = UIKit.label("", 15, UIKit.TEXT_DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	bot.add_child(_status)
	for b in [["Check", _check, false], ["Save", _save, false], ["TEST FLY", _test_fly, true], ["Missions", _back_to_hub, false]]:
		bot.add_child(UIKit.button(String(b[0]), b[1], 18, bool(b[2])))


func _edit(d: Dictionary, p: String) -> void:
	doc = MissionDoc.upgrade(d)
	path = p
	dirty = false
	sel = {"type": "", "id": ""}
	tool = "select"
	_hub.visible = false
	_ed.visible = true
	var st: Dictionary = doc.get("start", {})
	_map.zoom = 6.0
	_map.look_at_latlon(float(st.get("lat", 51.1)), float(st.get("lon", 1.2)))
	_rebuild_all()


func _rebuild_all() -> void:
	_build_mission_page()
	for g in GROUPS:
		_build_group_page(g)
	_refresh_status()
	_map.queue_redraw()


func _touch(redraw: bool = true) -> void:
	dirty = true
	_refresh_status()
	if redraw:
		_map.queue_redraw()


func _refresh_status() -> void:
	_title.text = str(doc.get("name", "Mission")) + (" *" if dirty else "")
	var v: Dictionary = MissionDoc.validate(doc)
	var ne: int = (v["errors"] as PackedStringArray).size()
	var nw: int = (v["warnings"] as PackedStringArray).size()
	var where: String = path.get_file() if path != "" else "not saved yet"
	if ne > 0:
		_status.text = "%s   -   %d problem%s to fix: %s" % [where, ne, "" if ne == 1 else "s", v["errors"][0]]
		_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	elif nw > 0:
		_status.text = "%s   -   ready to fly (%d note%s: %s)" % [where, nw, "" if nw == 1 else "s", v["warnings"][0]]
		_status.add_theme_color_override("font_color", UIKit.TEXT_DIM)
	else:
		_status.text = "%s   -   ready to fly" % where
		_status.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55))
	_tool_label.text = ""


# ================================================================== map tools
func set_tool(t: String, kind: String = "") -> void:
	if t == "route" and sel.get("type", "") != "unit":
		_say("Select a unit first (Units tab or click it on the map), then draw its route.")
		return
	tool = t
	place_kind = kind
	_map.queue_redraw()


func tool_hint() -> String:
	match tool:
		"place":
			return "Click the map to place: %s   (Esc: cancel)" % str(MissionDoc.UNIT_KINDS[place_kind]["label"]).to_lower()
		"zone":
			return "Click the map to place a zone   (Esc: cancel)"
		"start":
			return "Click an airfield (runway start) or anywhere (air start) for the player   (Esc: cancel)"
		"route":
			return "Click to add waypoints to %s's route. Right-click or Esc when done." % sel.get("id", "")
	return "Click to select, drag to move. Right-click a waypoint to delete it. Delete key removes the selection."


func map_click(lat: float, lon: float, screen: Vector2) -> void:
	match tool:
		"place":
			var u: Dictionary = MissionDoc.new_unit(doc, place_kind, lat, lon)
			if place_kind == "world":
				var best: Dictionary = _nearest_target(lat, lon)
				if not best.is_empty():
					u["type"] = str(best["id"])
					u["lat"] = float(best["lat"])
					u["lon"] = float(best["lon"])
					u["name"] = str(best["name"])
					u["side"] = "Axis" if str(best.get("side_owner", "Axis")) == "Axis" else "Allies"
			(doc["units"] as Array).append(u)
			tool = "select"
			_select("unit", str(u["id"]))
			_touch()
		"zone":
			var z: Dictionary = {"id": MissionDoc.next_id(doc["zones"], "zone"), "name": "", "lat": lat, "lon": lon, "radius": 3.0}
			z["name"] = str(z["id"]).capitalize()
			(doc["zones"] as Array).append(z)
			tool = "select"
			_select("zone", str(z["id"]))
			_touch()
		"start":
			var st: Dictionary = doc["start"]
			var af: Dictionary = _airfield_near(screen)
			if not af.is_empty():
				st["lat"] = float(af["lat"])
				st["lon"] = float(af["lon"])
				st["airfield"] = str(af["id"])
				st["heading"] = float(af.get("heading_deg", 90.0))
				var friendly: bool = (str(af["side"]) == "RAF") == (str(doc["side"]) == "Allies")
				if not friendly:
					st["airborne"] = true
			else:
				st["lat"] = lat
				st["lon"] = lon
				st["airfield"] = ""
				st["airborne"] = true
			tool = "select"
			_select("start", "start")
			_build_mission_page()
			_touch()
		"route":
			var u2: Dictionary = MissionDoc.find(doc["units"], str(sel.get("id", "")))
			if not u2.is_empty():
				(u2["route"] as Array).append([snappedf(lat, 0.0001), snappedf(lon, 0.0001)])
				if str(u2.get("kind", "")) in ["flight"] and str(u2.get("behavior", "")) == "patrol":
					u2["behavior"] = "route"
				elif str(u2.get("kind", "")) in ["vehicles", "ships"] and str(u2.get("behavior", "")) == "hold":
					u2["behavior"] = "move"
				_build_group_page("units")
				_touch()
		_:
			_select("", "")


func map_right_click(_screen: Vector2, h: Dictionary) -> void:
	if tool != "select":
		tool = "select"
		_map.queue_redraw()
		return
	if h.get("type", "") == "wp":
		var u: Dictionary = MissionDoc.find(doc["units"], str(h["id"]))
		if not u.is_empty():
			(u["route"] as Array).remove_at(int(h["idx"]))
			_build_group_page("units")
			_touch()


func select_from_map(h: Dictionary) -> void:
	if h.get("type", "") == "wp":
		return
	_select(str(h["type"]), str(h["id"]))


func drag_item(h: Dictionary, lat: float, lon: float) -> void:
	lat = snappedf(lat, 0.0001)
	lon = snappedf(lon, 0.0001)
	match str(h.get("type", "")):
		"unit":
			var u: Dictionary = MissionDoc.find(doc["units"], str(h["id"]))
			if not u.is_empty() and str(u.get("kind", "")) != "world":
				u["lat"] = lat
				u["lon"] = lon
		"zone":
			var z: Dictionary = MissionDoc.find(doc["zones"], str(h["id"]))
			if not z.is_empty():
				z["lat"] = lat
				z["lon"] = lon
		"start":
			doc["start"]["lat"] = lat
			doc["start"]["lon"] = lon
			doc["start"]["airfield"] = ""
			doc["start"]["airborne"] = true
		"wp":
			var u2: Dictionary = MissionDoc.find(doc["units"], str(h["id"]))
			if not u2.is_empty():
				u2["route"][int(h["idx"])] = [lat, lon]
	dirty = true


func item_moved() -> void:
	if sel.get("type", "") == "start":
		_build_mission_page()
	_touch()


func _airfield_near(screen: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = 14.0
	for a in MissionDoc.airfields():
		var q: float = _map.to_screen(float(a["lat"]), float(a["lon"])).distance_to(screen)
		if q < bd:
			bd = q
			best = a
	return best


func _nearest_target(lat: float, lon: float) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = 1.0e9
	for t in MissionDoc.world_targets():
		var d: float = Vector2((float(t["lon"]) - lon) * 0.64, float(t["lat"]) - lat).length()
		if d < bd:
			bd = d
			best = t
	return best


func _select(type: String, id: String) -> void:
	sel = {"type": type, "id": id}
	if type in ["unit", "zone"]:
		var g: String = type + "s"
		_tabs.current_tab = TAB_OF[g]
		var il: ItemList = _lists.get(g)
		if il != null:
			var arr: Array = doc[g]
			for i in arr.size():
				if str(arr[i]["id"]) == id:
					il.select(i)
					il.ensure_current_is_visible()
		_build_form(g)
	elif type == "start":
		_tabs.current_tab = 0
	_map.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _ed.visible:
		if event.is_action_pressed("ui_cancel"):
			closed.emit()
			get_viewport().set_input_as_handled()
		return
	var fo: Control = get_viewport().gui_get_focus_owner()
	var typing: bool = fo is LineEdit or fo is TextEdit or fo is SpinBox
	if event.is_action_pressed("ui_cancel"):
		if tool != "select":
			tool = "select"
			_map.queue_redraw()
		else:
			_back_to_hub()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_DELETE and not typing:
		_delete_selected()
		get_viewport().set_input_as_handled()


func _delete_selected() -> void:
	var t: String = str(sel.get("type", ""))
	if not t in ["unit", "zone"]:
		return
	var g: String = t + "s"
	var arr: Array = doc[g]
	for i in arr.size():
		if str(arr[i]["id"]) == str(sel["id"]):
			arr.remove_at(i)
			break
	sel = {"type": "", "id": ""}
	_build_group_page(g)
	_touch()


# ================================================================== field helpers
func _row(parent: Control, caption: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	parent.add_child(hb)
	var l := UIKit.label(caption, 15, UIKit.TEXT_DIM, true)
	l.custom_minimum_size = Vector2(130, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hb.add_child(l)
	return hb


func _f_text(parent: Control, caption: String, value: String, cb: Callable) -> LineEdit:
	var le := LineEdit.new()
	le.text = value
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.add_theme_font_override("font", UIKit.body_font())
	le.add_theme_font_size_override("font_size", 16)
	le.text_changed.connect(func(t: String) -> void: cb.call(t))
	(_row(parent, caption) if caption != "" else parent).add_child(le)
	return le


func _f_long(parent: Control, caption: String, value: String, cb: Callable) -> TextEdit:
	if caption != "":
		parent.add_child(UIKit.label(caption, 15, UIKit.TEXT_DIM, true))
	var te := TextEdit.new()
	te.text = value
	te.custom_minimum_size = Vector2(0, 120)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.add_theme_font_override("font", UIKit.body_font())
	te.add_theme_font_size_override("font_size", 16)
	te.text_changed.connect(func() -> void: cb.call(te.text))
	parent.add_child(te)
	return te


func _f_num(parent: Control, caption: String, value: float, lo: float, hi: float, step: float, cb: Callable) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value = value
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.get_line_edit().add_theme_font_size_override("font_size", 16)
	sb.value_changed.connect(func(v: float) -> void: cb.call(v))
	(_row(parent, caption) if caption != "" else parent).add_child(sb)
	return sb


func _f_bool(parent: Control, caption: String, value: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = caption
	c.button_pressed = value
	c.add_theme_font_override("font", UIKit.font())
	c.add_theme_font_size_override("font_size", 16)
	c.toggled.connect(func(on: bool) -> void: cb.call(on))
	parent.add_child(c)
	return c


## Drop-down of `values` shown as `labels`; calls cb(value).
func _f_enum(parent: Control, caption: String, values: Array, labels: Array, value: Variant, cb: Callable) -> OptionButton:
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit._style_option(ob, 16)
	var idx: int = -1
	for i in values.size():
		ob.add_item(str(labels[i]) if i < labels.size() else str(values[i]))
		if str(values[i]) == str(value):
			idx = i
	if idx < 0 and not values.is_empty():
		ob.add_item("(choose)")
		idx = values.size()
	ob.select(idx)
	ob.item_selected.connect(func(i: int) -> void:
		if i < values.size():
			cb.call(values[i]))
	(_row(parent, caption) if caption != "" else parent).add_child(ob)
	return ob


func _note(parent: Control, text: String) -> void:
	var l := UIKit.label(text, 14, UIKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", UIKit.body_font())
	parent.add_child(l)


func _clear(c: Control) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()


## Ids and labels of everything in `group`, for the reference drop-downs in objectives and triggers.
func _ref_lists(group: String) -> Array:
	var ids: Array = []
	var labels: Array = []
	for e in doc.get(group, []):
		ids.append(str(e["id"]))
		var nm: String = str(e.get("name", e.get("text", "")))
		labels.append("%s  (%s)" % [nm, e["id"]] if nm != "" and nm != str(e["id"]) else str(e["id"]))
	return [ids, labels]


# ================================================================== Mission tab
func _build_mission_page() -> void:
	var p: VBoxContainer = _pages["Mission"]
	_clear(p)
	_f_text(p, "Name", str(doc.get("name", "")), func(t: String) -> void:
		doc["name"] = t
		_touch(false))
	_f_text(p, "Author", str(doc.get("author", "")), func(t: String) -> void:
		doc["author"] = t
		_touch(false))
	_f_long(p, "Briefing (shown before the sortie)", str(doc.get("briefing", "")), func(t: String) -> void:
		doc["briefing"] = t
		_touch(false))
	p.add_child(UIKit.rule(0.35))
	_f_enum(p, "Player side", MissionDoc.SIDES, ["RAF (Allies)", "Luftwaffe (Axis)"], doc["side"], func(v: Variant) -> void:
		doc["side"] = str(v)
		if not AircraftCatalog.ids_for_side(str(v)).has(str(doc["aircraft"])):
			doc["aircraft"] = AircraftCatalog.default_fighter(str(v))
		_build_mission_page()
		_touch())
	var ac_ids: Array = AircraftCatalog.ids_for_side(str(doc["side"]))
	var ac_names: Array = []
	for a in ac_ids:
		ac_names.append(AircraftCatalog.display_name(str(a)))
	_f_enum(p, "Aircraft", ac_ids, ac_names, doc["aircraft"], func(v: Variant) -> void:
		doc["aircraft"] = str(v)
		_touch(false))
	_f_num(p, "Wingmen", float(doc.get("wingmen", 2)), 0, 3, 1, func(v: float) -> void:
		doc["wingmen"] = int(v)
		_touch(false))
	_f_enum(p, "Enemy skill", [0.2, 0.5, 0.85], ["Easy", "Normal", "Hard"], _nearest_of([0.2, 0.5, 0.85], float(doc.get("difficulty", 0.5))), func(v: Variant) -> void:
		doc["difficulty"] = float(v)
		_touch(false))
	_f_enum(p, "Time of day", MissionDoc.TIMES, ["Dawn", "Noon", "Dusk", "Night"], doc.get("time", "noon"), func(v: Variant) -> void:
		doc["time"] = str(v)
		_touch(false))
	var wl: Array = []
	for w in MissionDoc.WEATHERS:
		wl.append(str(w).capitalize())
	_f_enum(p, "Weather", MissionDoc.WEATHERS, wl, doc.get("weather", "clear"), func(v: Variant) -> void:
		doc["weather"] = str(v)
		_touch(false))
	_f_text(p, "Date", str(doc.get("date", "")), func(t: String) -> void:
		doc["date"] = t.strip_edges()
		_touch(false))
	_note(p, "Date as YYYY-MM-DD between 1940-05-10 and 1945-05-08 (the ground, the airfields and the moon follow it). Leave empty for summer 1940.")
	p.add_child(UIKit.rule(0.35))
	p.add_child(UIKit.label("PLAYER START", 15, UIKit.ACCENT, true))
	var st: Dictionary = doc["start"]
	var af: Dictionary = MissionDoc.airfield(str(st.get("airfield", "")))
	_note(p, ("At %s." % af["name"]) if not af.is_empty() else ("In the air at %.3f N, %.3f E." % [float(st.get("lat", 0.0)), float(st.get("lon", 0.0))]))
	p.add_child(UIKit.button("Set start on the map", func() -> void: set_tool("start"), 16))
	if not af.is_empty():
		_f_bool(p, "Start in the air over the field (else on the runway)", bool(st.get("airborne", true)), func(on: bool) -> void:
			st["airborne"] = on
			_touch())
	_f_num(p, "Altitude (m)", float(st.get("alt", 1500.0)), 100, 8000, 50, func(v: float) -> void:
		st["alt"] = v
		_touch(false))
	_f_num(p, "Heading", float(st.get("heading", 90.0)), 0, 359, 5, func(v: float) -> void:
		st["heading"] = v
		_touch())


func _nearest_of(opts: Array, v: float) -> float:
	var best: float = float(opts[0])
	for o in opts:
		if absf(float(o) - v) < absf(best - v):
			best = float(o)
	return best


# ================================================================== list tabs (units, zones, objectives, triggers)
func _build_group_page(g: String) -> void:
	var page_name: String = {"units": "Units", "zones": "Zones", "objectives": "Objectives", "triggers": "Triggers"}[g]
	var p: VBoxContainer = _pages[page_name]
	_clear(p)
	match g:
		"units":
			_note(p, "Add a unit with the Add unit menu above the map, then click where it goes. Units not 'in at the start' are brought in by a trigger.")
		"zones":
			p.add_child(UIKit.button("Add zone (click the map)", func() -> void: set_tool("zone"), 16))
			_note(p, "Zones are circles on the map: places to reach, land in, or that triggers watch.")
		"objectives":
			p.add_child(UIKit.button("Add objective", _add_objective, 16))
			_note(p, "Required objectives must all be done for the mission to succeed; the mission fails if one fails. Hidden ones appear when a trigger shows them.")
		"triggers":
			p.add_child(UIKit.button("Add trigger", _add_trigger, 16))
			_note(p, "A trigger fires when its conditions are met, waits its delay, then runs its actions in order.")
	var il := ItemList.new()
	il.custom_minimum_size = Vector2(0, 160)
	il.auto_height = false
	_style_list(il)
	var arr: Array = doc[g]
	var sel_i: int = -1
	for i in arr.size():
		il.add_item(_entry_label(g, arr[i]))
		if (g == "units" and sel.get("type", "") == "unit" or g == "zones" and sel.get("type", "") == "zone") and str(arr[i]["id"]) == str(sel.get("id", "")):
			sel_i = i
		if (g == "objectives" or g == "triggers") and str(arr[i]["id"]) == str(_forms.get(g + "_sel", "")):
			sel_i = i
	if sel_i >= 0:
		il.select(sel_i)
	il.item_selected.connect(func(i: int) -> void:
		var id: String = str((doc[g] as Array)[i]["id"])
		if g == "units" or g == "zones":
			_select(g.trim_suffix("s"), id)
			var e: Dictionary = (doc[g] as Array)[i]
			_map.look_at_latlon(float(e["lat"]), float(e["lon"]))
		else:
			_forms[g + "_sel"] = id
			_build_form(g))
	p.add_child(il)
	_lists[g] = il
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 8)
	p.add_child(form)
	_forms[g] = form
	_build_form(g)


func _entry_label(g: String, e: Dictionary) -> String:
	match g:
		"units":
			var t: String = str(e.get("type", ""))
			return "%s   -   %s %s%s" % [str(e.get("name", e["id"])), ("%d x " % int(e.get("count", 1))) if str(e.get("kind", "")) != "world" else "", t.replace("_", " "), "" if bool(e.get("active", true)) else "  (later)"]
		"zones":
			return "%s   -   %.1f km" % [str(e.get("name", e["id"])), float(e.get("radius", 2.0))]
		"objectives":
			return "%s%s" % [str(e.get("text", e["id"])), "" if bool(e.get("required", true)) else "  (optional)"]
		"triggers":
			return "%s   -   %d if / %d then" % [str(e.get("name", e["id"])), (e.get("conditions", []) as Array).size(), (e.get("actions", []) as Array).size()]
	return str(e.get("id", ""))


func _refresh_list_labels(g: String) -> void:
	var il: ItemList = _lists.get(g)
	if il == null:
		return
	var arr: Array = doc[g]
	for i in mini(arr.size(), il.item_count):
		il.set_item_text(i, _entry_label(g, arr[i]))


func _selected_entry(g: String) -> Dictionary:
	match g:
		"units":
			return MissionDoc.find(doc["units"], str(sel.get("id", ""))) if sel.get("type", "") == "unit" else {}
		"zones":
			return MissionDoc.find(doc["zones"], str(sel.get("id", ""))) if sel.get("type", "") == "zone" else {}
	return MissionDoc.find(doc[g], str(_forms.get(g + "_sel", "")))


func _build_form(g: String) -> void:
	var form: VBoxContainer = _forms.get(g)
	if form == null:
		return
	_clear(form)
	var e: Dictionary = _selected_entry(g)
	if e.is_empty():
		return
	form.add_child(UIKit.rule(0.35))
	match g:
		"units":
			_unit_form(form, e)
		"zones":
			_zone_form(form, e)
		"objectives":
			_objective_form(form, e)
		"triggers":
			_trigger_form(form, e)
	var del := UIKit.button("Delete", func() -> void:
		(doc[g] as Array).erase(e)
		if g in ["units", "zones"]:
			sel = {"type": "", "id": ""}
		_build_group_page(g)
		_touch(), 16)
	form.add_child(del)


func _unit_form(f: VBoxContainer, u: Dictionary) -> void:
	var kind: String = str(u.get("kind", "flight"))
	f.add_child(UIKit.label(str(MissionDoc.UNIT_KINDS[kind]["label"]).to_upper() + "   (" + str(u["id"]) + ")", 15, UIKit.ACCENT, true))
	_f_text(f, "Name", str(u.get("name", "")), func(t: String) -> void:
		u["name"] = t
		_refresh_list_labels("units")
		_touch())
	if kind == "world":
		var tl: Array = MissionDoc.world_targets().duplicate()
		var la: float = float(u["lat"])
		var lo: float = float(u["lon"])
		tl.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return Vector2((float(a["lon"]) - lo) * 0.64, float(a["lat"]) - la).length() < Vector2((float(b["lon"]) - lo) * 0.64, float(b["lat"]) - la).length())
		var ids: Array = []
		var labels: Array = []
		for t in tl.slice(0, 40):
			ids.append(str(t["id"]))
			labels.append("%s (%s)" % [str(t["name"]), str(t["type"]).replace("_", " ")])
		_f_enum(f, "Target", ids, labels, u["type"], func(v: Variant) -> void:
			var t2: Dictionary = MissionDoc.world_target(str(v))
			u["type"] = str(v)
			u["lat"] = float(t2["lat"])
			u["lon"] = float(t2["lon"])
			u["name"] = str(t2["name"])
			u["side"] = "Axis" if str(t2.get("side_owner", "Axis")) == "Axis" else "Allies"
			_build_form("units")
			_refresh_list_labels("units")
			_touch())
		_note(f, "A real target already on the map (factory, port, radar, battery...). It is spawned at its real place; the 40 nearest to where you clicked are listed.")
	else:
		_f_enum(f, "Side", MissionDoc.SIDES, ["Allies", "Axis"], u["side"], func(v: Variant) -> void:
			u["side"] = str(v)
			var types: Array = MissionDoc.unit_types(kind, str(v))
			if not types.has(str(u["type"])) and not types.is_empty():
				u["type"] = str(types[0])
			_build_form("units")
			_refresh_list_labels("units")
			_touch())
		var types2: Array = MissionDoc.unit_types(kind, str(u["side"]))
		var tlabels: Array = []
		for t3 in types2:
			tlabels.append(AircraftCatalog.display_name(str(t3)) if kind == "flight" else str(t3).replace("_", " ").capitalize())
		_f_enum(f, "Type", types2, tlabels, u["type"], func(v: Variant) -> void:
			u["type"] = str(v)
			_refresh_list_labels("units")
			_touch(false))
		_f_num(f, "How many", float(u.get("count", 1)), 1, float(MissionDoc.UNIT_KINDS[kind]["max"]), 1, func(v: float) -> void:
			u["count"] = int(v)
			_refresh_list_labels("units")
			_touch())
	if kind == "flight":
		_f_num(f, "Altitude (m)", float(u.get("alt", 2500.0)), 150, 8000, 50, func(v: float) -> void:
			u["alt"] = v
			_touch(false))
	if kind != "world":
		_f_num(f, "Heading", float(u.get("heading", 0.0)), 0, 359, 5, func(v: float) -> void:
			u["heading"] = v
			_touch())
		var behs: Array = MissionDoc.UNIT_KINDS[kind]["behaviors"]
		if behs.size() > 1:
			var bl: Array = []
			for b in behs:
				bl.append(str(b).capitalize())
			_f_enum(f, "Orders", behs, bl, u.get("behavior", behs[0]), func(v: Variant) -> void:
				u["behavior"] = str(v)
				_build_form("units")
				_touch())
		_note(f, str(MissionDoc.BEHAVIOR_HELP.get(str(u.get("behavior", "")), "")))
		_f_enum(f, "Skill", [0.2, 0.5, 0.85], ["Easy", "Normal", "Hard"], _nearest_of([0.2, 0.5, 0.85], float(u.get("skill", 0.5))), func(v: Variant) -> void:
			u["skill"] = float(v)
			_touch(false))
	_f_bool(f, "In at the start (else a trigger brings it in)", bool(u.get("active", true)), func(on: bool) -> void:
		u["active"] = on
		_refresh_list_labels("units")
		_touch())
	if kind in ["flight", "vehicles", "ships"]:
		var n: int = (u.get("route", []) as Array).size()
		var rr := HBoxContainer.new()
		rr.add_theme_constant_override("separation", 8)
		f.add_child(rr)
		rr.add_child(UIKit.label("Route: %d waypoint%s" % [n, "" if n == 1 else "s"], 15, UIKit.TEXT_DIM, true))
		rr.add_child(UIKit.button("Draw route", func() -> void: set_tool("route"), 15))
		rr.add_child(UIKit.button("Clear route", func() -> void:
			u["route"] = []
			_build_form("units")
			_touch(), 15))


func _zone_form(f: VBoxContainer, z: Dictionary) -> void:
	f.add_child(UIKit.label("ZONE   (" + str(z["id"]) + ")", 15, UIKit.ACCENT, true))
	_f_text(f, "Name", str(z.get("name", "")), func(t: String) -> void:
		z["name"] = t
		_refresh_list_labels("zones")
		_touch())
	_f_num(f, "Radius (km)", float(z.get("radius", 3.0)), 0.3, 40.0, 0.1, func(v: float) -> void:
		z["radius"] = v
		_refresh_list_labels("zones")
		_touch())


func _add_objective() -> void:
	var o: Dictionary = {"id": MissionDoc.next_id(doc["objectives"], "obj"), "text": "New objective", "kind": "manual", "target": "", "required": true, "shown": true}
	(doc["objectives"] as Array).append(o)
	_forms["objectives_sel"] = str(o["id"])
	_build_group_page("objectives")
	_touch(false)


func _objective_form(f: VBoxContainer, o: Dictionary) -> void:
	f.add_child(UIKit.label("OBJECTIVE   (" + str(o["id"]) + ")", 15, UIKit.ACCENT, true))
	_f_text(f, "Text", str(o.get("text", "")), func(t: String) -> void:
		o["text"] = t
		_refresh_list_labels("objectives")
		_touch(false))
	var kinds: Array = MissionDoc.OBJECTIVE_KINDS.keys()
	var kl: Array = []
	for k in kinds:
		kl.append(str(MissionDoc.OBJECTIVE_KINDS[k]["label"]))
	_f_enum(f, "Kind", kinds, kl, o.get("kind", "manual"), func(v: Variant) -> void:
		o["kind"] = str(v)
		o["target"] = "60" if str(v) == "survive" else ""
		_build_form("objectives")
		_touch(false))
	match str(MissionDoc.OBJECTIVE_KINDS.get(str(o.get("kind", "manual")), {}).get("target", "")):
		"unit":
			var r: Array = _ref_lists("units")
			_f_enum(f, "Unit", r[0], r[1], o.get("target", ""), func(v: Variant) -> void:
				o["target"] = str(v)
				_touch(false))
		"zone":
			var r2: Array = _ref_lists("zones")
			var ids: Array = r2[0]
			var labels: Array = r2[1]
			if str(o.get("kind", "")) == "land":
				ids = [""] + ids
				labels = ["Any friendly airfield"] + labels
			_f_enum(f, "Zone", ids, labels, o.get("target", ""), func(v: Variant) -> void:
				o["target"] = str(v)
				_touch(false))
		"seconds":
			_f_num(f, "Seconds", float(o.get("target", "60")) if str(o.get("target", "")).is_valid_float() else 60.0, 5, 7200, 5, func(v: float) -> void:
				o["target"] = str(int(v))
				_touch(false))
	_f_bool(f, "Required for success", bool(o.get("required", true)), func(on: bool) -> void:
		o["required"] = on
		_refresh_list_labels("objectives")
		_touch(false))
	_f_bool(f, "Shown from the start (else a trigger shows it)", bool(o.get("shown", true)), func(on: bool) -> void:
		o["shown"] = on
		_touch(false))


func _add_trigger() -> void:
	var t: Dictionary = {"id": MissionDoc.next_id(doc["triggers"], "trigger"), "name": "", "once": true, "logic": "all", "delay": 0.0,
		"conditions": [MissionDoc.new_step(MissionDoc.CONDITIONS, "time")], "actions": [MissionDoc.new_step(MissionDoc.ACTIONS, "message")]}
	t["name"] = str(t["id"]).capitalize()
	(doc["triggers"] as Array).append(t)
	_forms["triggers_sel"] = str(t["id"])
	_build_group_page("triggers")
	_touch(false)


func _trigger_form(f: VBoxContainer, t: Dictionary) -> void:
	f.add_child(UIKit.label("TRIGGER   (" + str(t["id"]) + ")", 15, UIKit.ACCENT, true))
	_f_text(f, "Name", str(t.get("name", "")), func(s: String) -> void:
		t["name"] = s
		_refresh_list_labels("triggers")
		_touch(false))
	_f_enum(f, "Fires when", ["all", "any"], ["ALL conditions are met", "ANY condition is met"], t.get("logic", "all"), func(v: Variant) -> void:
		t["logic"] = str(v)
		_touch(false))
	_f_num(f, "Then wait (s)", float(t.get("delay", 0.0)), 0, 3600, 1, func(v: float) -> void:
		t["delay"] = v
		_touch(false))
	_f_bool(f, "Fire only once (else again each time it becomes true)", bool(t.get("once", true)), func(on: bool) -> void:
		t["once"] = on
		_touch(false))
	_step_list(f, t, "conditions", "IF", MissionDoc.CONDITIONS)
	_step_list(f, t, "actions", "THEN", MissionDoc.ACTIONS)


## The editable list of a trigger's conditions or actions: each step has a type drop-down, its parameters and buttons to
## move it up or remove it; a drop-down at the end adds a new one.
func _step_list(f: VBoxContainer, t: Dictionary, key: String, head: String, cat: Dictionary) -> void:
	f.add_child(UIKit.rule(0.3))
	f.add_child(UIKit.label(head, 17, UIKit.ACCENT, true))
	var steps: Array = t[key]
	if steps.is_empty():
		_note(f, "(none: it fires straight away)" if key == "conditions" else "(no actions yet)")
	var types: Array = cat.keys()
	var tl: Array = []
	for k in types:
		tl.append(str(cat[k]["label"]))
	for i in steps.size():
		var step: Dictionary = steps[i]
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UIKit._box(Color(0.1, 0.1, 0.09, 0.9), Color(UIKit.PANEL_EDGE, 0.3), 1))
		var mc := MarginContainer.new()
		for k2 in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			mc.add_theme_constant_override(k2, 8)
		pc.add_child(mc)
		mc.add_child(box)
		f.add_child(pc)
		var hdr := HBoxContainer.new()
		hdr.add_theme_constant_override("separation", 6)
		box.add_child(hdr)
		var idx: int = i
		_f_enum(hdr, "", types, tl, step.get("type", ""), func(v: Variant) -> void:
			steps[idx] = MissionDoc.new_step(cat, str(v))
			_build_form("triggers")
			_refresh_list_labels("triggers")
			_touch(false))
		if i > 0:
			hdr.add_child(UIKit.button("Up", func() -> void:
				var tmp: Variant = steps[idx - 1]
				steps[idx - 1] = steps[idx]
				steps[idx] = tmp
				_build_form("triggers")
				_touch(false), 14))
		hdr.add_child(UIKit.button("X", func() -> void:
			steps.remove_at(idx)
			_build_form("triggers")
			_refresh_list_labels("triggers")
			_touch(false), 14))
		for prm in (cat.get(str(step.get("type", "")), {}) as Dictionary).get("params", []):
			_param_field(box, step, prm)
	var add := OptionButton.new()
	UIKit._style_option(add, 15)
	add.add_item("+ add %s..." % ("condition" if key == "conditions" else "action"))
	for l in tl:
		add.add_item(str(l))
	add.select(0)
	add.item_selected.connect(func(i: int) -> void:
		if i <= 0:
			return
		steps.append(MissionDoc.new_step(cat, str(types[i - 1])))
		_build_form("triggers")
		_refresh_list_labels("triggers")
		_touch(false))
	f.add_child(add)


func _param_field(box: VBoxContainer, step: Dictionary, prm: Array) -> void:
	var key: String = str(prm[0])
	var kind: String = str(prm[1])
	var cap: String = key.capitalize()
	match kind:
		"float":
			_f_num(box, cap, float(step.get(key, prm[2])), 0, 100000, 1 if key != "percent" else 5, func(v: float) -> void:
				step[key] = v
				_touch(false))
		"int":
			_f_num(box, cap, float(step.get(key, prm[2])), -100000 if key == "points" else 0, 100000, 1, func(v: float) -> void:
				step[key] = int(v)
				_touch(false))
		"bool":
			_f_bool(box, cap, bool(step.get(key, prm[2])), func(on: bool) -> void:
				step[key] = on
				_touch(false))
		"text":
			_f_text(box, cap, str(step.get(key, prm[2])), func(s: String) -> void:
				step[key] = s
				_touch(false))
		"unit", "zone", "objective", "trigger":
			var r: Array = _ref_lists(kind + "s")
			_f_enum(box, cap, r[0], r[1], step.get(key, ""), func(v: Variant) -> void:
				step[key] = str(v)
				_touch(false))
		_:
			if kind.begins_with("enum:"):
				var opts: Array = Array(kind.substr(5).split("|"))
				var ol: Array = []
				for o in opts:
					ol.append(str(o).capitalize())
				_f_enum(box, cap, opts, ol, step.get(key, prm[2]), func(v: Variant) -> void:
					step[key] = str(v)
					_touch(false))


# ================================================================== save / check / fly
func _save() -> bool:
	var p: String = MissionDoc.save(doc, path)
	if p == "":
		_say("Could not save the mission.")
		return false
	path = p
	dirty = false
	_refresh_status()
	_status.text = "Saved to " + p.get_file()
	return true


func _check() -> void:
	var v: Dictionary = MissionDoc.validate(doc)
	var out: Array = []
	if not (v["errors"] as PackedStringArray).is_empty():
		out.append("To fix before flying:\n- " + "\n- ".join(v["errors"]))
	if not (v["warnings"] as PackedStringArray).is_empty():
		out.append("Worth knowing:\n- " + "\n- ".join(v["warnings"]))
	_say("\n\n".join(out) if not out.is_empty() else "All good: the mission is ready to fly.")


func _test_fly() -> void:
	var v: Dictionary = MissionDoc.validate(doc)
	if not (v["errors"] as PackedStringArray).is_empty():
		_say("Fix these first:\n\n- " + "\n- ".join(v["errors"]))
		return
	if not _save():
		return
	play_requested.emit(MissionDoc.start_config(doc, path, true))


func _back_to_hub() -> void:
	if dirty:
		_save_prompt.dialog_text = "Save the changes to \"%s\" first?" % str(doc.get("name", ""))
		_save_prompt.popup_centered(Vector2i(560, 0))
		return
	_show_hub()
