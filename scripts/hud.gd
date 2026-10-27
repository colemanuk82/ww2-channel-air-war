class_name HUD
extends CanvasLayer
## Flight HUD built in code. Extend via:
##   hud.bind_aircraft(a) / hud.bind_camera(cam)
##   hud.show_message("text", seconds)
##   hud.add_widget(control)                       # added to the extra container (top-left column)
##   hud.register_minimap_marker(node3d, color)    # dots on the minimap (auto-removed when freed)
##   hud.set_readout_extra("AMMO 600")             # extra line in the bottom-left panel

const BOMBER_MERGE_DIST: float = 1500.0     # bombers closer than this (world units) share one minimap icon
const MAP_RANGE: float = 22000.0     # world units from centre to edge of the minimap
const MAP_RES: int = 256             # internal map texture resolution
const MAP_MOVE: float = 1500.0       # world units of travel before the map re-centres
const PANEL_BG := Color(0.05, 0.055, 0.05, 0.72)
const TEXT_COL := Color(0.95, 0.92, 0.82)
const ACCENT := Color(0.93, 0.74, 0.32)
const BRASS := Color(0.72, 0.58, 0.32)
const DIAL_FACE := Color(0.06, 0.06, 0.055, 0.92)
const GOOD := Color(0.6, 0.86, 0.48)
const WARN := Color(1.0, 0.68, 0.28)
const BAD := Color(1.0, 0.32, 0.24)
const FRIEND_COL := Color(1.0, 0.85, 0.1)
const ENEMY_COL := Color(1.0, 0.22, 0.14)
const CABLE_COL := Color(1.0, 0.5, 0.12)   # barrage balloon cable hazard marks
## Gauges, compass and readouts sit back a little so they frame the view instead of competing with it.
## The minimap, the message banner and the warnings stay at full strength.
const HUD_FADE: float = 0.62

var aircraft: Aircraft
var camera: Camera3D
var terrain: Node

var _root: Control
var _speed_lbl: Label
var _alt_lbl: Label
var _hdg_lbl: Label
var _inst: Control
var _radio: Control
var _radio_msgs: Array = []     # {"sender", "text", "kind", "t"}
var _hints: Control
var _tr_box: Control
var _vsi: float = 0.0
var _last_alt: float = 0.0
var _extra_lbl: Label
var _warp_lbl: Label          # "TIME x2" readout, only up while the simulation is warped
var _info_lbl: Label
var _msg_lbl: Label
var _stall_lbl: Label
var _thr_bar: ProgressBar
var _boost_bar: ProgressBar
var _hp_bar: ProgressBar
var _gear_lbl: Label
var _compass: Control
var _minimap: Control
var _aim: Control
var _hit_t: float = 0.0     # hit-confirm marker timers
var _kill_t: float = 0.0
var _weapon_prev: bool = false
var _weapon_mode_prev: int = 0
var _extra_box: VBoxContainer
var _msg_timer: float = 0.0
var _msg_alpha: float = 0.0
var _msg_bar: Control
var _markers: Array = []   # [Node3D, Color]
var _map_img: Image
var _map_tex: ImageTexture
var _map_row: int = 0
var _map_center: Vector2 = Vector2.ZERO
var _map_dirty: bool = true
var _color_img: Image
var _af_spots: Array = []   # {"pos": Vector2, "hdg": float, "len": float}
var _city_spots: Array = []  # {"pos": Vector2, "size": int, "name": String}


func _ready() -> void:
	layer = 10
	add_to_group("hud")          # lets world objects (searchlights) post a message without a direct reference
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build()
	Radio.message.connect(_on_radio)
	Weapons.player_hit.connect(func(_n: Node, _a: float) -> void: _hit_t = 0.25)
	Weapons.player_kill.connect(_on_player_kill)
	_load_color_map()
	_load_spots()
	_map_img = Image.create(MAP_RES, MAP_RES, false, Image.FORMAT_RGBA8)
	_map_img.fill(Color(0.1, 0.2, 0.3))
	_map_tex = ImageTexture.create_from_image(_map_img)
	TimeOfDay.time_changed.connect(func(_h: float) -> void: _update_info())
	WeatherManager.weather_changed.connect(func(_w: String) -> void: _update_info())
	_update_info()
	if OS.get_cmdline_user_args().has("--tally-test"):     # debug: one of every tally mark (screenshots)
		get_tree().create_timer(6.0).timeout.connect(func() -> void:
			for k in ["fighter", "fighter", "bomber", "v1", "parked", "tank", "vehicle", "ship", "train", "flak", "balloon", "building"]:
				_tally.append({"kind": k, "t": -10.0})
			_layout_tally())


func _on_flaps(_a: Aircraft, message: String) -> void:
	# no on-screen text for flap changes (the flap icon shows the setting)
	pass


func _on_radio(sender: String, text: String, kind: int) -> void:
	_radio_msgs.append({"sender": sender, "text": text, "kind": kind, "t": Time.get_ticks_msec() * 0.001})
	while _radio_msgs.size() > 5:
		_radio_msgs.pop_front()


func _draw_radio() -> void:
	if not GameState.radio_subtitles:
		return
	var now: float = Time.get_ticks_msec() * 0.001
	var font: Font = UIKit.font(true)
	# Long call-outs ("bombers taking off from RAF Manston, their target in Calais") are wrapped to at
	# most two lines so they always stay on screen.
	var max_w: float = 500.0
	var fs: int = 17
	var lh: float = 21.0
	var y: float = 0.0
	for m in _radio_msgs:
		var age: float = now - float(m["t"])
		if age > 11.0:
			continue
		var a: float = clampf((11.0 - age) / 2.0, 0.0, 1.0) * clampf(age / 0.12, 0.0, 1.0)
		var kind: int = int(m["kind"])
		var who_col: Color = Color(0.55, 0.85, 1.0) if kind == 0 else (ACCENT if kind == 1 else Color(0.85, 1.0, 0.7))
		var lines: PackedStringArray = _wrap_text(String(m["sender"]) + ": " + String(m["text"]), font, fs, max_w, 2)
		var wmax: float = 0.0
		for ln in lines:
			wmax = maxf(wmax, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		var h: float = lh * float(lines.size()) + 8.0
		var w: float = wmax + 22.0
		_radio.draw_rect(Rect2(0, y, w, h), Color(0.035, 0.04, 0.035, 0.66 * a))
		_radio.draw_rect(Rect2(0, y, 3, h), Color(who_col, a))
		for i in lines.size():
			var col: Color = Color(who_col, a) if i == 0 else Color(0.95, 0.95, 0.9, a)
			_radio.draw_string(font, Vector2(11, y + 17.0 + lh * float(i) + 1.0), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.8 * a))
			_radio.draw_string(font, Vector2(10, y + 17.0 + lh * float(i)), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		y += h + 4.0


## Greedy word wrap, capped at max_lines: the remainder is joined onto the last line rather than dropped.
func _wrap_text(text: String, font: Font, size: int, max_w: float, max_lines: int) -> PackedStringArray:
	var words: PackedStringArray = text.split(" ", false)
	var lines: PackedStringArray = PackedStringArray()
	var cur: String = ""
	for w in words:
		var cand: String = w if cur == "" else cur + " " + w
		if cur != "" and lines.size() < max_lines - 1 and font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
			lines.append(cur)
			cur = w
		else:
			cur = cand
	if cur != "":
		lines.append(cur)
	return lines


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		GameState.set_graphic("show_hints", not GameState.show_hints)
	# without a chart (Bombsight) in this mode, the map key just switches the minimap between small and large
	if event.is_action_pressed("tac_map") and not event.is_echo() and get_tree().get_nodes_in_group("bombsight").is_empty():
		set_minimap_stage(1 - minimap_stage)
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ minimap size
## The map key (M) steps: small minimap -> large minimap -> full-screen chart -> small again (bombsight.gd).
const MINIMAP_SIZES := [150.0, 240.0]
var minimap_stage: int = 0


func set_minimap_stage(st: int) -> void:
	minimap_stage = clampi(st, 0, MINIMAP_SIZES.size() - 1)
	_apply_minimap_size()


func _apply_minimap_size() -> void:
	if _minimap == null:
		return
	var s: float = float(MINIMAP_SIZES[minimap_stage])
	_minimap.custom_minimum_size = Vector2(s, s)
	_layout_tally()
	_minimap.offset_left = -s - 16.0
	_minimap.offset_top = -s - 16.0
	_minimap.offset_right = -16.0
	_minimap.offset_bottom = -16.0
	_minimap.queue_redraw()


func bind_aircraft(a: Aircraft) -> void:
	if a != aircraft and aircraft != null:
		_tally.clear()
		_layout_tally()
	aircraft = a
	if a != null and not a.flaps_changed.is_connected(_on_flaps):
		a.flaps_changed.connect(_on_flaps)
	if a != null and not a.engine_alert.is_connected(_on_engine_alert):
		a.engine_alert.connect(_on_engine_alert)
		a.blackout_alert.connect(_on_engine_alert)


func _on_engine_alert(text: String) -> void:
	# engine overheat / high-G messages are shown by the bright red gauges instead of text
	pass


func bind_camera(c: Camera3D) -> void:
	camera = c


func show_message(text: String, seconds: float = 2.5) -> void:
	_msg_lbl.text = text.to_upper()
	_msg_timer = seconds


func add_widget(c: Control) -> void:
	# A mode readout (a Label the mode keeps writing its text to) is shown as a mission card: a dark glass plate
	# with a brass edge, the first line as a heading, the rest wrapped in the body face (see _draw_card). The Label
	# itself stays hidden inside the card as the text source, so every mode works unchanged.
	if c is Label:
		var l := c as Label
		var card := Control.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.set_meta("src", l)
		l.visible = false
		card.add_child(l)
		card.draw.connect(_draw_card.bind(card))
		_cards.append(card)
		_extra_box.add_child(card)
		return
	_extra_box.add_child(c)


# ---------------------------------------------------------------- mission cards (top-left readouts)

const CARD_W: float = 540.0          # widest a card grows before its lines wrap
const CARD_HEAD: int = 20
const CARD_BODY: int = 18
const CARD_LINE: float = 23.0
const CARD_PAD := Vector2(14.0, 9.0)
const SEG_GAP: float = 18.0
var _cards: Array = []


## Text of a card split into rows of segments: [[text, kind]...] per row. Segments are the parts of a line the
## modes separate with three spaces ("done 0   missed 0"); kind 0 normal, 1 heading title, 2 hint "(P: skip)",
## 3 warning (SCRAMBLE, ALERT, V-1).
func _card_rows(text: String, head_font: Font, body_font: Font) -> Array:
	var rows: Array = []
	var lines: PackedStringArray = text.strip_edges().split("\n")
	for li in lines.size():
		var segs: PackedStringArray = lines[li].strip_edges().split("   ", false)
		var row: Array = []
		var w: float = 0.0
		for si in segs.size():
			var t: String = segs[si].strip_edges()
			if t == "":
				continue
			var kind: int = 0
			if li == 0 and si == 0:
				kind = 1
			elif t.begins_with("(") and t.ends_with(")"):
				kind = 2
			elif t.contains("SCRAMBLE") or t.contains("ALERT") or t.contains("OUT OF"):
				kind = 3
			var f: Font = head_font if kind == 1 else body_font
			var fs: int = CARD_HEAD if kind == 1 else (CARD_BODY - 3 if kind == 2 else CARD_BODY)
			var sw: float = f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if not row.is_empty() and w + SEG_GAP + sw > CARD_W:
				rows.append(row)
				row = []
				w = 0.0
			if sw > CARD_W:
				# one very long segment (a mission title): wrap it by words
				for wl in _wrap_text(t, f, fs, CARD_W, 3):
					if not row.is_empty():
						rows.append(row)
					row = [[wl, kind, f, fs]]
				w = f.get_string_size(String(row[0][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				continue
			row.append([t, kind, f, fs])
			w += (SEG_GAP if row.size() > 1 else 0.0) + sw
		if not row.is_empty():
			rows.append(row)
	return rows


func _layout_card(card: Control) -> void:
	var l: Label = card.get_meta("src")
	var text: String = l.text if is_instance_valid(l) else ""
	if card.has_meta("last") and String(card.get_meta("last")) == text:
		return
	card.set_meta("last", text)
	var rows: Array = _card_rows(text, UIKit.display_font(), UIKit.font(true))
	card.set_meta("rows", rows)
	var w: float = 0.0
	for row in rows:
		var rw: float = 0.0
		for sg in row:
			rw += (SEG_GAP if rw > 0.0 else 0.0) + (sg[2] as Font).get_string_size(String(sg[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(sg[3])).x
		w = maxf(w, rw)
	var h: float = CARD_LINE * float(rows.size()) + (6.0 if rows.size() > 1 else 0.0)
	card.custom_minimum_size = Vector2(w + CARD_PAD.x * 2.0 + 4.0, h + CARD_PAD.y * 2.0) if not rows.is_empty() else Vector2.ZERO
	card.queue_redraw()


func _draw_card(card: Control) -> void:
	var rows: Array = card.get_meta("rows", [])
	if rows.is_empty():
		return
	var l: Label = card.get_meta("src")
	var body_col: Color = l.get_theme_color("font_color") if is_instance_valid(l) and l.has_theme_color_override("font_color") else TEXT_COL
	var r := Rect2(Vector2.ZERO, card.size)
	card.draw_rect(r, Color(0.035, 0.04, 0.035, 0.80))
	card.draw_rect(Rect2(0, 0, 4.0, r.size.y), Color(ACCENT, 0.95))            # brass edge, like the menu cards
	card.draw_rect(r, Color(BRASS, 0.30), false, 1.0)
	var y: float = CARD_PAD.y
	for ri in rows.size():
		var x: float = CARD_PAD.x + 4.0
		var base: float = y + CARD_LINE * 0.5 + 7.0
		for sg in rows[ri]:
			var t: String = sg[0]
			var kind: int = sg[1]
			var f: Font = sg[2]
			var fs: int = sg[3]
			var col: Color = body_col
			match kind:
				1:
					col = ACCENT
				2:
					col = Color(body_col, 0.55)
				3:
					col = WARN
			card.draw_string(f, Vector2(x + 1.0, base + 1.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.85))
			card.draw_string(f, Vector2(x, base), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			x += f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + SEG_GAP
		y += CARD_LINE
		if ri == 0 and rows.size() > 1:
			card.draw_line(Vector2(CARD_PAD.x + 4.0, y + 1.0), Vector2(r.size.x - CARD_PAD.x, y + 1.0), Color(BRASS, 0.45), 1.0)
			y += 6.0


# ---------------------------------------------------------------- kill tally (this life)

const TALLY_PER_ROW: int = 10
const TALLY_CELL := Vector2(30.0, 24.0)
## Tally mark colours by what was destroyed.
const TALLY_COLS := {
	"fighter": Color(1.0, 0.36, 0.30), "bomber": Color(1.0, 0.58, 0.24), "v1": Color(1.0, 0.34, 0.72),
	"parked": Color(0.92, 0.66, 0.52), "tank": Color(0.72, 0.86, 0.36), "vehicle": Color(0.98, 0.86, 0.36),
	"ship": Color(0.45, 0.76, 1.0), "train": Color(0.80, 0.68, 1.0), "flak": Color(1.0, 0.74, 0.30),
	"balloon": Color(0.86, 0.92, 0.98), "building": Color(0.92, 0.82, 0.62),
}
var _tally: Array = []          # {"kind": String, "t": seconds when scored}
var _tally_c: Control
var _was_alive: bool = true


## What a kill was, for its tally mark: fighter, bomber, v1, parked, tank, vehicle, ship, train, flak, balloon, building.
func _kill_kind(n: Node) -> String:
	if n is Aircraft:
		var ac: Aircraft = n
		if ac.stats != null and AircraftCatalog.is_bomber(ac.stats.id):
			return "bomber"
		return "fighter"
	if n is FlyingBomb:
		return "v1"
	if n is Parachute:
		return ""
	if n is GroundShip:
		return "ship"
	if n is BarrageBalloon:
		return "balloon"
	if n is AAGun or n is Searchlight:
		return "flak"
	var k: String = String(n.get("kind")) if n.get("kind") != null else ""
	if k.begins_with("train"):
		return "train"
	if k.begins_with("aa_"):
		return "flak"
	if n is GroundVehicle:
		return "tank" if k in ["sherman", "panzer4", "tiger"] else "vehicle"
	if n is AirfieldProp:
		match (n as AirfieldProp).pkind:
			"parked":
				return "parked"
			"tank":
				return "tank"
			"truck":
				return "vehicle"
			"gun":
				return "flak"
		return "building"
	if k.contains("ship") or k.contains("boat") or k.contains("barge"):
		return "ship"
	return "building"


func _on_player_kill(n: Node) -> void:
	_kill_t = 0.8
	if n == null or not is_instance_valid(n):
		return
	var kind: String = _kill_kind(n)
	if kind == "":
		return
	_tally.append({"kind": kind, "t": Time.get_ticks_msec() * 0.001})
	_layout_tally()


func _layout_tally() -> void:
	if _tally_c == null:
		return
	# top right, just under the time / weather panel; the control hints move down below it
	var n: int = _tally.size()
	var rows: int = int(ceil(float(mini(n, TALLY_PER_ROW * 3)) / float(TALLY_PER_ROW)))
	var h: float = float(rows) * TALLY_CELL.y
	_tally_c.offset_right = -16.0
	_tally_c.offset_left = -16.0 - float(TALLY_PER_ROW) * TALLY_CELL.x
	_tally_c.offset_top = 66.0
	_tally_c.offset_bottom = 66.0 + h
	_tally_c.visible = n > 0
	if _hints != null:
		var hy: float = 70.0 + (h + 6.0 if n > 0 else 0.0)
		_hints.offset_top = hy
		_hints.offset_bottom = hy + HINT_ROW * float(HINTS.size()) + 16.0
	_tally_c.queue_redraw()


func _draw_tally() -> void:
	var n: int = _tally.size()
	if n == 0:
		return
	var c: Control = _tally_c
	var now: float = Time.get_ticks_msec() * 0.001
	# newest marks first in reading order would shuffle them; marks are painted in the order scored, like the
	# kill markings under a cockpit. Past three rows the earliest ones scroll off (the count stays exact).
	var first: int = maxi(0, n - TALLY_PER_ROW * 3)
	for i in range(first, n):
		# right-aligned rows: the newest mark at the right-hand end of the last row
		var k: int = i - first
		var row: int = k / TALLY_PER_ROW
		var in_row: int = mini(n - first - row * TALLY_PER_ROW, TALLY_PER_ROW)
		var slot: int = TALLY_PER_ROW - in_row + (k % TALLY_PER_ROW)
		var ctr := Vector2(TALLY_CELL.x * (float(slot) + 0.5), TALLY_CELL.y * (float(row) + 0.5))
		var age: float = now - float(_tally[i]["t"])
		var pop: float = 1.0 + 0.9 * (1.0 - smoothstep(0.0, 0.35, age))
		var kind: String = String(_tally[i]["kind"])
		var col: Color = TALLY_COLS.get(kind, TEXT_COL)
		col = col.lerp(Color.WHITE, 1.0 - smoothstep(0.2, 1.2, age))       # flashes white as it is scored
		_tally_icon(c, kind, ctr, pop, col)


## Small stencil silhouettes, about 24 x 16 px at k = 1: a dark drop shadow, then the paint colour.
func _tally_icon(c: Control, kind: String, p: Vector2, k: float, col: Color) -> void:
	var polys: Array = []
	match kind:
		"fighter", "parked", "v1":
			# plan view, nose up: fuselage, wings, tailplane
			polys.append([Vector2(-1.4, -8), Vector2(1.4, -8), Vector2(1.6, 7), Vector2(-1.6, 7)])
			polys.append([Vector2(-11, -1), Vector2(11, -1), Vector2(10, 2.5), Vector2(-10, 2.5)])
			polys.append([Vector2(-5, 5.5), Vector2(5, 5.5), Vector2(4.5, 7.5), Vector2(-4.5, 7.5)])
			if kind == "v1":
				polys.append([Vector2(-1.2, 3), Vector2(1.2, 3), Vector2(1.2, 9), Vector2(-1.2, 9)])
		"bomber":
			polys.append([Vector2(-1.8, -8), Vector2(1.8, -8), Vector2(1.6, 7.5), Vector2(-1.6, 7.5)])
			polys.append([Vector2(-12, -1.5), Vector2(12, -1.5), Vector2(11, 2.5), Vector2(-11, 2.5)])
			polys.append([Vector2(-6.5, -5), Vector2(-3.5, -5), Vector2(-3.5, 2), Vector2(-6.5, 2)])
			polys.append([Vector2(3.5, -5), Vector2(6.5, -5), Vector2(6.5, 2), Vector2(3.5, 2)])
			polys.append([Vector2(-5.5, 6), Vector2(5.5, 6), Vector2(5, 8), Vector2(-5, 8)])
		"tank":
			# side view: tracks, hull, turret, gun
			polys.append([Vector2(-10, 3), Vector2(10, 3), Vector2(8, 7), Vector2(-8, 7)])
			polys.append([Vector2(-9, -1), Vector2(9, -1), Vector2(10, 3), Vector2(-10, 3)])
			polys.append([Vector2(-5, -5.5), Vector2(3, -5.5), Vector2(4, -1), Vector2(-6, -1)])
			polys.append([Vector2(3, -4.2), Vector2(12, -4.2), Vector2(12, -2.8), Vector2(3, -2.8)])
		"vehicle":
			# lorry: cab and canvas tilt, wheels
			polys.append([Vector2(-10, -5), Vector2(3, -5), Vector2(3, 3), Vector2(-10, 3)])
			polys.append([Vector2(4, -2), Vector2(8, -2), Vector2(10, 1), Vector2(10, 3), Vector2(4, 3)])
			polys.append(_disc_pts(Vector2(-6, 5), 2.4))
			polys.append(_disc_pts(Vector2(6, 5), 2.4))
		"ship":
			polys.append([Vector2(-12, 1), Vector2(12, 1), Vector2(8, 6), Vector2(-9, 6)])
			polys.append([Vector2(-5, -3), Vector2(4, -3), Vector2(4, 1), Vector2(-5, 1)])
			polys.append([Vector2(-1.5, -8), Vector2(1, -8), Vector2(1, -3), Vector2(-1.5, -3)])
		"train":
			polys.append([Vector2(-11, -3), Vector2(4, -3), Vector2(4, 4), Vector2(-11, 4)])
			polys.append([Vector2(4, -7), Vector2(10, -7), Vector2(10, 4), Vector2(4, 4)])
			polys.append([Vector2(-8, -8), Vector2(-5, -8), Vector2(-5, -3), Vector2(-8, -3)])
			polys.append(_disc_pts(Vector2(-7, 5.5), 2.2))
			polys.append(_disc_pts(Vector2(-1, 5.5), 2.2))
			polys.append(_disc_pts(Vector2(6, 5.5), 2.2))
		"flak":
			# gun on a cruciform mount, barrel raised
			polys.append([Vector2(-9, 5), Vector2(9, 5), Vector2(9, 7.5), Vector2(-9, 7.5)])
			polys.append([Vector2(-4, 0), Vector2(4, 0), Vector2(5, 5), Vector2(-5, 5)])
			polys.append([Vector2(-1, 1), Vector2(1.5, -0.5), Vector2(9, -9), Vector2(7, -10)])
		"balloon":
			# barrage balloon: fat envelope with three tail fins
			polys.append(_disc_pts(Vector2(-2, 0), 7.5, 0.6))
			polys.append([Vector2(3, -2), Vector2(10, -8), Vector2(11, -6), Vector2(6, -1)])
			polys.append([Vector2(3, 2), Vector2(10, 8), Vector2(11, 6), Vector2(6, 1)])
			polys.append([Vector2(4, -1), Vector2(11, -1), Vector2(11, 1), Vector2(4, 1)])
		_:
			# building: walls and a pitched roof
			polys.append([Vector2(-9, -1), Vector2(9, -1), Vector2(9, 7), Vector2(-9, 7)])
			polys.append([Vector2(-11, -1), Vector2(0, -8), Vector2(11, -1)])
	# no backing plate: a dark outline all round (and a drop shadow) keeps the marks readable on sky or ground
	var shadow := Color(0, 0, 0, 0.8)
	var offs: Array = [Vector2(1.6, 1.6), Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2.ZERO]
	for pass_i in offs.size():
		var off: Vector2 = offs[pass_i]
		var last: bool = pass_i == offs.size() - 1
		var pc: Color = col if last else shadow
		if kind == "parked" and last:
			pc = col
		for poly in polys:
			var pts := PackedVector2Array()
			for v in poly:
				pts.append(p + (v as Vector2) * k + off)
			c.draw_colored_polygon(pts, pc)
	if kind == "parked":
		# parked: a ground bar under the plan view
		c.draw_rect(Rect2(p + Vector2(-11, 9.5) * k, Vector2(22, 1.6) * k), col)


func _disc_pts(ctr: Vector2, r: float, squash: float = 1.0) -> Array:
	var out: Array = []
	for i in 12:
		var a: float = TAU * float(i) / 12.0
		out.append(ctr + Vector2(cos(a) * r, sin(a) * r * squash))
	return out


func set_readout_extra(text: String) -> void:
	_extra_lbl.text = text


func register_minimap_marker(n: Node3D, color: Color) -> void:
	_markers.append([n, color])


func _label(text: String, size: int = 18, col: Color = TEXT_COL) -> Label:
	var l := UIKit.label(text, size, col)
	l.add_theme_constant_override("outline_size", 4)
	return l


func _panel(parent: Control) -> VBoxContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.border_color = Color(BRASS, 0.8)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	pc.add_theme_stylebox_override("panel", sb)
	parent.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	return vb


func _bar(title: String, parent: Control, col: Color) -> ProgressBar:
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var l := _label(title, 14)
	l.custom_minimum_size = Vector2(52, 0)
	hb.add_child(l)
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.step = 0.001
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(130, 12)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	pb.add_theme_stylebox_override("background", bg)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	pb.add_theme_stylebox_override("fill", fg)
	hb.add_child(pb)
	return pb


func _build() -> void:
	# Bottom-left instrument cluster (custom drawn)
	_inst = Control.new()
	_inst.anchor_left = 0.0
	_inst.anchor_right = 0.0
	_inst.anchor_top = 1.0
	_inst.anchor_bottom = 1.0
	_inst.offset_left = 16.0
	_inst.offset_right = 400.0
	_inst.offset_top = -226.0
	_inst.offset_bottom = -8.0
	_inst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inst.draw.connect(_draw_inst)
	_root.add_child(_inst)
	_extra_lbl = _label("", 15, ACCENT)
	_extra_lbl.anchor_top = 1.0
	_extra_lbl.anchor_bottom = 1.0
	_extra_lbl.offset_left = 20.0
	_extra_lbl.offset_top = -250.0
	_extra_lbl.offset_bottom = -226.0
	_root.add_child(_extra_lbl)

	# Radio log (left side, under the weapon readout column)
	_radio = Control.new()
	_radio.anchor_left = 0.0
	_radio.anchor_right = 0.0
	_radio.anchor_top = 0.0
	_radio.anchor_bottom = 0.0
	_radio.offset_left = 16.0
	_radio.offset_top = 262.0
	_radio.offset_right = 520.0
	_radio.offset_bottom = 440.0
	_radio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radio.draw.connect(_draw_radio)
	_root.add_child(_radio)

	# Top-left extension column
	var tl := MarginContainer.new()
	tl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tl.add_theme_constant_override("margin_left", 16)
	tl.add_theme_constant_override("margin_top", 16)
	_root.add_child(tl)
	_extra_box = VBoxContainer.new()
	_extra_box.add_theme_constant_override("separation", 6)
	tl.add_child(_extra_box)
	# Simulation time warp (] / [ in flight): a quiet line in the same column as the mode readouts,
	# hidden at 1x so the HUD is unchanged in normal play.
	_warp_lbl = _label("", 15, ACCENT)
	_warp_lbl.visible = false
	add_widget(_warp_lbl)

	# Top-right time / weather
	var tr := MarginContainer.new()
	_tr_box = tr
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.add_theme_constant_override("margin_right", 16)
	tr.add_theme_constant_override("margin_top", 16)
	_root.add_child(tr)
	var tvb := _panel(tr)
	_info_lbl = _label("12:00  CLEAR", 20)
	tvb.add_child(_info_lbl)
	_hints = Control.new()
	_hints.anchor_left = 1.0
	_hints.anchor_right = 1.0
	_hints.anchor_top = 0.0
	_hints.anchor_bottom = 0.0
	_hints.offset_left = -176.0
	_hints.offset_right = -16.0
	_hints.offset_top = 70.0
	_hints.offset_bottom = 70.0 + HINT_ROW * float(HINTS.size()) + 16.0
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.draw.connect(_draw_hints)
	_root.add_child(_hints)

	# Compass strip
	_compass = Control.new()
	_compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_compass.position = Vector2(-230, 10)
	_compass.size = Vector2(460, 84)
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass.draw.connect(_draw_compass)
	_root.add_child(_compass)
	_hdg_lbl = Label.new()

	# Messages
	# A dark strip with brass hairlines that fades in and out behind the text, just under the compass.
	_msg_bar = Control.new()
	_msg_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_msg_bar.position = Vector2(-450, 92)
	_msg_bar.size = Vector2(900, 62)
	_msg_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg_bar.draw.connect(_draw_msg_bar)
	_root.add_child(_msg_bar)
	# Smaller and allowed to run to two lines: long call-outs ("bombers taking off from RAF Manston,
	# their target in Calais") used to run off the edge of the screen.
	_msg_lbl = _label("", 19, UIKit.TEXT)
	_msg_lbl.add_theme_font_override("font", UIKit.display_font())
	_msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_msg_lbl.position = Vector2(-450, 92)
	_msg_lbl.size = Vector2(900, 62)
	_root.add_child(_msg_lbl)
	_stall_lbl = _label("STALL", 36, Color(1.0, 0.3, 0.2))
	_stall_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stall_lbl.size = Vector2(300, 48)
	_stall_lbl.set_anchors_preset(Control.PRESET_CENTER)
	_stall_lbl.position = Vector2(-150, 110)
	_stall_lbl.visible = false
	_root.add_child(_stall_lbl)

	# Aim marker
	_aim = Control.new()
	_aim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_aim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim.draw.connect(_draw_aim)
	_root.add_child(_aim)

	# Minimap
	_minimap = Control.new()
	_minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_minimap_size()
	_minimap.draw.connect(_draw_minimap)
	_root.add_child(_minimap)

	# Kill tally for this life, top right under the time / weather: one coloured mark per kill (plane, bomber, tank, lorry, ship...)
	_tally_c = Control.new()
	_tally_c.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_tally_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tally_c.draw.connect(_draw_tally)
	_tally_c.visible = false
	_root.add_child(_tally_c)
	_layout_tally()

	# Ease the instruments, compass and readouts back so the view leads. The minimap, the message
	# banner, the aim markers and the warnings are deliberately left at full strength.
	for c in [_inst, _extra_lbl, _compass, _tr_box, _hints]:     # the radio log and mission cards stay at full strength to be readable
		if c is CanvasItem:
			(c as CanvasItem).modulate.a = HUD_FADE


## Real imagery mosaic (data/heightmap/region_color.png) as the map base.
func _load_color_map() -> void:
	var tex := ResourceLoader.load("res://data/heightmap/region_color.png") as Texture2D
	if tex == null:
		return
	_color_img = tex.get_image()
	if _color_img != null:
		_color_img.convert(Image.FORMAT_RGBA8)


## Airfield runway symbols + town dots from the real location data.
func _load_spots() -> void:
	var f := FileAccess.open("res://data/locations.json", FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var dd: Dictionary = d
	for a in dd.get("airfields", []):
		if not (a is Dictionary) or not bool(a.get("in_bounds", true)):
			continue
		var w: Vector3 = WorldCoords.latlon_to_world(float(a.get("lat", 0.0)), float(a.get("lon", 0.0)))
		_af_spots.append({
			"pos": Vector3(w.x, 0.0, w.z),
			"hdg": deg_to_rad(float(a.get("heading_deg", 0.0))),
			"len": 1000.0,
		})
	for c in dd.get("cities", []):
		if not (c is Dictionary) or not bool(c.get("in_bounds", true)):
			continue
		var w2: Vector3 = WorldCoords.latlon_to_world(float(c.get("lat", 0.0)), float(c.get("lon", 0.0)))
		_city_spots.append({
			"pos": Vector3(w2.x, 0.0, w2.z),
			"size": int(c.get("size", 2)),
			"name": String(c.get("name", "")),
		})


func _update_info() -> void:
	if _info_lbl:
		_info_lbl.text = "%s  %s" % [TimeOfDay.get_time_string(), WeatherManager.current.to_upper()]


var _dmg_stage: int = 0


## One-off call-outs as battle damage takes hold (matches the flight-model penalties in Aircraft).
func _damage_callouts() -> void:
	var frac: float = aircraft.health / maxf(aircraft.stats.max_health, 1.0)
	var stage: int = 0
	if frac <= 0.2:
		stage = 3
	elif frac <= 0.4:
		stage = 2
	elif frac <= 0.65:
		stage = 1
	if stage > _dmg_stage and aircraft.state == Aircraft.State.ALIVE:
		var msg: Array = ["", "ENGINE HIT: losing power", "BADLY DAMAGED: heavy controls, no emergency power", "ENGINE FAILING: get her home"]
		show_message(msg[stage], 3.5)
	_dmg_stage = stage


func _process(delta: float) -> void:
	_hit_t = maxf(_hit_t - delta, 0.0)
	_kill_t = maxf(_kill_t - delta, 0.0)
	# "Hide HUD" only hides the clutter: gauges, compass, map, ammo, aim and target markers always stay
	var show: bool = GameState.show_hud
	_radio.visible = show
	if _tr_box:
		_tr_box.visible = show
	for card in _cards:
		if is_instance_valid(card):
			var src: Label = (card as Control).get_meta("src")
			_layout_card(card)
			(card as Control).visible = show and is_instance_valid(src) and src.text.strip_edges() != ""
	# the radio log sits just under the top-left column, however tall the mission card has grown
	var col_bottom: float = _extra_box.get_global_rect().end.y if _extra_box.get_child_count() > 0 else 16.0
	_radio.offset_top = maxf(col_bottom + 12.0, 120.0)
	_radio.offset_bottom = _radio.offset_top + 200.0
	# kill tally: cleared when a new life starts
	if aircraft != null and is_instance_valid(aircraft):
		var alive: bool = aircraft.state == Aircraft.State.ALIVE
		if alive and not _was_alive and not _tally.is_empty():
			_tally.clear()
			_layout_tally()
		_was_alive = alive
	if _tally_c != null and not _tally.is_empty():
		_tally_c.queue_redraw()
	# simulation time warp readout: hidden at 1x (and with the HUD hidden), so normal play looks unchanged
	_warp_lbl.text = ("TIME %s" % GameState.SIM_WARP_NAMES[GameState.sim_warp_index()]) if GameState.sim_warp > 1 else ""
	if Input.is_action_just_pressed("hud_toggle"):
		GameState.show_hud = not GameState.show_hud
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			_msg_timer = 0.0
	_msg_alpha = move_toward(_msg_alpha, 1.0 if _msg_timer > 0.0 else 0.0, delta * 5.0)
	if _msg_alpha <= 0.0 and _msg_timer <= 0.0:
		_msg_lbl.text = ""
	_msg_lbl.modulate.a = _msg_alpha
	_msg_bar.queue_redraw()
	if aircraft == null or not is_instance_valid(aircraft):
		return
	if (aircraft.weapon_mode == 2) != _weapon_prev or aircraft.weapon_mode != _weapon_mode_prev:
		_weapon_prev = aircraft.weapon_mode == 2
		_weapon_mode_prev = aircraft.weapon_mode
		show_message("WEAPON: " + ["GUNS", "ROCKETS", "BOMBS"][aircraft.weapon_mode], 1.2)
	if terrain == null:
		terrain = get_tree().get_first_node_in_group("terrain")
	var alt_m: float = aircraft.get_altitude_m()
	_vsi = lerpf(_vsi, (alt_m - _last_alt) / maxf(delta, 0.0001), 1.0 - exp(-4.0 * delta))
	_last_alt = alt_m
	var low_fall: bool = not aircraft.on_ground and aircraft.altitude_agl < 260.0 and aircraft.velocity.y < -28.0
	# only the low-altitude "PULL UP" warning remains; the old STALL text is gone (the airspeed needle still shows a stall)
	_stall_lbl.text = "PULL UP"
	_stall_lbl.visible = false   # no on-screen PULL UP text
	_damage_callouts()
	_hints.visible = GameState.show_hints and GameState.show_hud
	_inst.queue_redraw()
	_radio.queue_redraw()
	_compass.queue_redraw()
	_aim.queue_redraw()
	_update_map(delta)
	_minimap.queue_redraw()


func _draw_msg_bar() -> void:
	if _msg_alpha <= 0.01 or _msg_lbl.text == "":
		return
	var sz: Vector2 = _msg_bar.size
	# width from the unwrapped text (the label itself wraps, so its minimum size is no use here)
	var font: Font = _msg_lbl.get_theme_font("font")
	var fs: int = _msg_lbl.get_theme_font_size("font_size")
	var tw: float = font.get_string_size(_msg_lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 90.0
	var w: float = minf(tw, sz.x)
	var x0: float = (sz.x - w) * 0.5
	var n: int = 24
	for i in n:
		var prof: float = pow(sin(PI * (float(i) + 0.5) / float(n)), 0.7) * _msg_alpha
		var sx: float = x0 + w * float(i) / float(n)
		var sw: float = w / float(n) + 1.0
		_msg_bar.draw_rect(Rect2(sx, 0.0, sw, sz.y), Color(0.03, 0.04, 0.035, 0.6 * prof))
		_msg_bar.draw_rect(Rect2(sx, 0.0, sw, 1.5), Color(BRASS, 0.85 * prof))
		_msg_bar.draw_rect(Rect2(sx, sz.y - 1.5, sw, 1.5), Color(BRASS, 0.85 * prof))


func _txt(c: Control, text: String, pos: Vector2, size: int, col: Color, align: int = 0) -> void:
	# align: 0 left, 1 centre, 2 right (pos is the anchor point; pos.y is the baseline)
	var font: Font = ThemeDB.fallback_font
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x: float = pos.x - (w * 0.5 if align == 1 else (w if align == 2 else 0.0))
	c.draw_string(font, Vector2(x + 1.0, pos.y + 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.7))
	c.draw_string(font, Vector2(x, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _glass(c: Control, r: Rect2) -> void:
	c.draw_rect(r, PANEL_BG)
	c.draw_rect(r, Color(BRASS, 0.35), false, 1.0)
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, 3.0)), Color(BRASS, 0.85))


func _corner_brackets(c: Control, r: Rect2) -> void:
	var arm: float = 12.0
	var corners: Array = [[r.position, 1.0, 1.0], [Vector2(r.end.x, r.position.y), -1.0, 1.0], [r.end, -1.0, -1.0], [Vector2(r.position.x, r.end.y), 1.0, -1.0]]
	for cn in corners:
		var p: Vector2 = cn[0]
		c.draw_line(p, p + Vector2(float(cn[1]) * arm, 0.0), BRASS, 2.0)
		c.draw_line(p, p + Vector2(0.0, float(cn[2]) * arm), BRASS, 2.0)


func _seg_bar(c: Control, r: Rect2, frac: float, col: Color) -> void:
	var n: int = 14
	var gap: float = 2.0
	var w: float = (r.size.x - gap * float(n - 1)) / float(n)
	for i in n:
		var x: float = r.position.x + float(i) * (w + gap)
		var on: bool = (float(i) + 0.5) / float(n) <= frac
		c.draw_rect(Rect2(x, r.position.y, w, r.size.y), col if on else Color(1, 1, 1, 0.10))


func _draw_inst() -> void:
	var c: Control = _inst
	var a: Aircraft = aircraft
	if a == null or not is_instance_valid(a):
		return
	var r: float = 72.0
	var actr := Vector2(92.0, 98.0)
	var lctr := Vector2(274.0, 98.0)
	var hull: float = clampf(a.health / a.stats.max_health, 0.0, 1.0)
	# ---- meters wrapped round the dials (no box): throttle + boost on the airspeed dial, hull + g on the altimeter.
	# Each is an arc just outside the bezel; the left arcs fill bottom -> top, the right arcs fill bottom -> top too.
	_arc_meter(c, actr, r + 12.0, true, a.throttle, GOOD, "thr")
	_arc_meter(c, actr, r + 12.0, false, a.boost_energy, BAD if a.boost_locked else (Color(1.0, 0.86, 0.4) if a.boosting else WARN), "boost")
	_arc_meter(c, lctr, r + 12.0, true, hull, BAD if hull < 0.35 else (WARN if hull < 0.65 else Color(0.85, 0.82, 0.66)), "hull")
	if GameState.engine_heat_on:
		# engine temperature: outer arc on the airspeed dial (blue cold -> amber -> red), flashing when overheating
		var hc: Color = Color(0.45, 0.75, 1.0).lerp(Color(1.0, 0.72, 0.2), clampf(a.engine_heat * 1.6, 0.0, 1.0))
		if a.overheated or a.engine_heat > 0.85:
			hc = Color(1.0, 0.04, 0.02)
		_arc_meter(c, actr, r + 22.0, false, a.engine_heat, hc, "heat")
		if a.engine_wear > 0.02:
			_arc_meter(c, actr, r + 31.0, false, a.engine_wear, BAD if a.engine_wear > 0.6 else WARN, "wear")
	if GameState.g_effects_on and maxf(a.g_gray, a.g_red) > 0.02:
		_arc_meter(c, lctr, r + 22.0, false, maxf(a.g_gray, a.g_red), Color(1.0, 0.04, 0.02) if a.g_gray > 0.6 or a.g_red > 0.6 else WARN, "tol")
	var gf: float = clampf(absf(a.g_load) / 8.0, 0.0, 1.0) if not a.on_ground else 0.0
	_arc_meter(c, lctr, r + 12.0, false, gf, Color(1.0, 0.04, 0.02) if a.g_load > 6.5 or a.g_load < -2.0 else (WARN if a.g_load > 4.5 else Color(0.6, 0.85, 1.0)), "g")
	# ---- airspeed indicator
	var vmax: float = ceilf((a.stats.max_speed + a.stats.boost_bonus) * 3.6 * 1.08 / 100.0) * 100.0
	var kmh: float = a.speed * 3.6
	_dial_face(c, actr, r)
	var a0: float = deg_to_rad(135.0)
	var sweep: float = deg_to_rad(270.0)
	var stall_f: float = clampf(a.stats.stall_speed * 3.6 / vmax, 0.0, 1.0)
	var maxn_f: float = clampf(a.stats.max_speed * 3.6 / vmax, 0.0, 1.0)
	c.draw_arc(actr, r - 8.0, a0, a0 + sweep * stall_f, 32, Color(BAD, 0.85), 4.0)
	c.draw_arc(actr, r - 8.0, a0 + sweep * stall_f, a0 + sweep * maxn_f, 48, Color(GOOD, 0.5), 4.0)
	c.draw_arc(actr, r - 8.0, a0 + sweep * maxn_f, a0 + sweep, 24, Color(WARN, 0.8), 4.0)
	var v: float = 0.0
	while v <= vmax + 0.5:
		var ang: float = a0 + sweep * (v / vmax)
		var d := Vector2(cos(ang), sin(ang))
		var major: bool = int(round(v)) % 100 == 0
		c.draw_line(actr + d * (r - (18.0 if major else 14.0)), actr + d * (r - 10.0), Color(TEXT_COL, 0.9 if major else 0.5), 2.0 if major else 1.0)
		if major and int(round(v)) % 200 == 0:
			_txt(c, "%d" % int(round(v / 10.0)), actr + d * (r - 29.0) + Vector2(0, 5), 12, TEXT_COL, 1)
		v += 50.0
	_txt(c, "km/h x10", actr + Vector2(0, -20.0), 9, Color(TEXT_COL, 0.5), 1)
	_needle(c, actr, a0 + sweep * clampf(kmh / vmax, 0.0, 1.0), r - 13.0, 3.0, BAD if a.stalled else Color(1.0, 0.97, 0.88))
	_value_box(c, actr + Vector2(0, 26.0), "%d" % int(kmh), 17, BAD if a.stalled else (WARN if a.boosting else TEXT_COL))
	# ---- altimeter: long hand hundreds (1000 m a turn), short hand thousands
	_dial_face(c, lctr, r)
	for i in 50:
		var ang2: float = -PI * 0.5 + TAU * float(i) / 50.0
		var d2 := Vector2(cos(ang2), sin(ang2))
		var big: bool = i % 5 == 0
		c.draw_line(lctr + d2 * (r - (17.0 if big else 13.0)), lctr + d2 * (r - 10.0), Color(TEXT_COL, 0.9 if big else 0.45), 2.0 if big else 1.0)
		if big:
			_txt(c, "%d" % (i / 5), lctr + d2 * (r - 27.0) + Vector2(0, 5), 13, TEXT_COL, 1)
	var alt_m: float = maxf(a.get_altitude_m(), 0.0)
	_needle(c, lctr, -PI * 0.5 + TAU * fposmod(alt_m / 10000.0, 1.0), r * 0.48, 5.0, Color(0.9, 0.86, 0.72))
	_needle(c, lctr, -PI * 0.5 + TAU * fposmod(alt_m / 1000.0, 1.0), r - 13.0, 2.5, Color(1.0, 0.97, 0.88))
	_value_box(c, lctr + Vector2(0, 26.0), "%d m" % int(alt_m), 15, ACCENT)
	# vertical speed to a tenth of a m/s, so the throttle can be set for level flight (the trim holds the speed
	# and the throttle sets the climb rate); LEVEL when it is within 0.3 m/s, ALT HOLD while the assist holds height
	var up: bool = _vsi >= 0.0
	var level: bool = absf(_vsi) < 0.3 and not a.on_ground
	# below the dials (inside they collided with the needles and the "km/h x10" label)
	var vs_tag: String = ""
	if not a.on_ground:
		vs_tag = "   ALT HOLD" if a.alt_hold_active else ("   LEVEL" if level else "")
	_txt(c, "%s%.1f m/s%s" % ["+" if up else "-", absf(_vsi), vs_tag], lctr + Vector2(0, r + 17.0), 11, GOOD if level else (Color(0.6, 0.85, 1.0) if up else WARN), 1)
	_txt(c, "THR %d%%" % int(round(a.throttle_target * 100.0)), actr + Vector2(0, r + 17.0), 11, Color(TEXT_COL, 0.85), 1)
	# g readout at the end of the g arc, lift warning when the wing can't carry the weight
	if not a.on_ground:
		_txt(c, "%.1fg" % a.g_load, lctr + Vector2(r + 22.0, -r * 0.62), 11, Color(TEXT_COL, 0.85), 1)
		if a.lift_fraction < 0.3:
			_txt(c, "LOW LIFT", lctr + Vector2(0, r + 31.0), 11, BAD, 1)
	# ---- status icons in a row under the dials: gear, flaps, assist, brake, wind
	var off_c := Color(TEXT_COL, 0.28)
	var y: float = 196.0
	_icon_gear(c, Vector2(40.0, y), GOOD if a.gear_down else off_c)
	_icon_flaps(c, Vector2(80.0, y), a.flap_setting, WARN if a.flap_setting > 0 else off_c)
	_icon_assist(c, Vector2(120.0, y), Color(0.6, 0.85, 1.0) if a.auto_level else off_c)
	if a.on_ground:
		_icon_brake(c, Vector2(160.0, y), BAD if a.brake_on else off_c)
	# wind: arrow (nose up) + head/tail component
	var wv: Vector3 = a.wind
	var fwd3: Vector3 = a.get_forward()
	var rgt3: Vector3 = a.global_transform.basis.x
	var wspd: float = Vector2(wv.x, wv.z).length()
	var wctr := Vector2(232.0, y)
	c.draw_arc(wctr, 10.0, 0.0, TAU, 24, Color(0, 0, 0, 0.45), 3.0)
	c.draw_arc(wctr, 10.0, 0.0, TAU, 24, Color(TEXT_COL, 0.4), 1.2)
	if wspd > 0.3:
		var wd := Vector2(wv.x * rgt3.x + wv.z * rgt3.z, -(wv.x * fwd3.x + wv.z * fwd3.z)).normalized()
		var wn := Vector2(-wd.y, wd.x)
		var tip: Vector2 = wctr + wd * 8.0
		c.draw_line(wctr - wd * 8.0, tip, Color(0.6, 0.85, 1.0), 2.0)
		c.draw_colored_polygon(PackedVector2Array([tip + wd * 3.0, tip - wd * 3.0 + wn * 3.0, tip - wd * 3.0 - wn * 3.0]), Color(0.6, 0.85, 1.0))
	var hw: float = a.headwind
	_txt(c, "%d" % int(round(absf(hw))), wctr + Vector2(16.0, 4.0), 11, Color(0.65, 0.88, 1.0) if hw >= 0.0 else WARN)


## Meter drawn as an arc just outside a dial: left side (left=true) or right side, 100 degrees long,
## filling from the bottom up, with a small icon at the bottom end.
func _arc_meter(c: Control, ctr: Vector2, rad: float, left: bool, frac: float, col: Color, icon: String) -> void:
	var span: float = deg_to_rad(100.0)
	var a_bot: float = deg_to_rad(140.0) if left else deg_to_rad(40.0)
	var dir: float = 1.0 if left else -1.0
	var a_top: float = a_bot + span * dir
	c.draw_arc(ctr, rad, minf(a_bot, a_top), maxf(a_bot, a_top), 28, Color(0, 0, 0, 0.5), 7.0)
	c.draw_arc(ctr, rad, minf(a_bot, a_top), maxf(a_bot, a_top), 28, Color(1, 1, 1, 0.12), 4.0)
	var f: float = clampf(frac, 0.0, 1.0)
	if f > 0.005:
		var a_f: float = a_bot + span * f * dir
		c.draw_arc(ctr, rad, minf(a_bot, a_f), maxf(a_bot, a_f), 28, col, 4.0)
	var ip: Vector2 = ctr + Vector2(cos(a_bot), sin(a_bot)) * (rad + 3.0) + Vector2(-8.0 if left else 8.0, 8.0)
	match icon:
		"thr":
			# throttle lever
			c.draw_line(ip + Vector2(-4, 5), ip + Vector2(4, 5), col, 2.0)
			c.draw_line(ip + Vector2(0, 5), ip + Vector2(3, -3), col, 2.0)
			c.draw_circle(ip + Vector2(3.5, -4), 2.6, col)
		"boost":
			# lightning bolt
			c.draw_colored_polygon(PackedVector2Array([ip + Vector2(1, -7), ip + Vector2(-4, 1), ip + Vector2(0, 1), ip + Vector2(-1, 7), ip + Vector2(4, -1), ip + Vector2(0, -1)]), col)
		"hull":
			# shield
			c.draw_colored_polygon(PackedVector2Array([ip + Vector2(-5, -6), ip + Vector2(5, -6), ip + Vector2(5, 0), ip + Vector2(0, 7), ip + Vector2(-5, 0)]), col)
			c.draw_line(ip + Vector2(0, -4), ip + Vector2(0, 4), Color(0, 0, 0, 0.6), 1.5)
		"g":
			_txt(c, "G", ip + Vector2(0, 5), 13, col, 1)
		"heat":
			# thermometer
			c.draw_line(ip + Vector2(0, -6), ip + Vector2(0, 3), col, 2.5)
			c.draw_circle(ip + Vector2(0, 5), 3.2, col)
		"wear":
			# little cog = engine wear
			c.draw_arc(ip, 4.5, 0.0, TAU, 12, col, 2.0)
			c.draw_circle(ip, 1.5, col)


func _icon_gear(c: Control, p: Vector2, col: Color) -> void:
	c.draw_line(p + Vector2(0, -9), p + Vector2(0, -1), col, 2.0)
	c.draw_arc(p + Vector2(0, 3), 5.0, 0.0, TAU, 16, Color(0, 0, 0, 0.5), 4.0)
	c.draw_arc(p + Vector2(0, 3), 5.0, 0.0, TAU, 16, col, 2.5)
	c.draw_circle(p + Vector2(0, 3), 1.5, col)


func _icon_flaps(c: Control, p: Vector2, setting: int, col: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(-11, -2), p + Vector2(2, -4), p + Vector2(4, -1), p + Vector2(-11, 1)]), col)
	var dn: float = [0.0, 15.0, 35.0][clampi(setting, 0, 2)]
	var fd := Vector2(cos(deg_to_rad(dn)), sin(deg_to_rad(dn)))
	c.draw_line(p + Vector2(5, -2), p + Vector2(5, -2) + fd * 8.0, col, 3.0)


func _icon_assist(c: Control, p: Vector2, col: Color) -> void:
	# horizon / attitude symbol
	c.draw_arc(p, 8.0, 0.0, TAU, 24, Color(0, 0, 0, 0.5), 3.5)
	c.draw_arc(p, 8.0, 0.0, TAU, 24, col, 1.8)
	c.draw_line(p + Vector2(-8, 0), p + Vector2(8, 0), col, 1.8)
	c.draw_line(p + Vector2(-4, 3), p + Vector2(4, 3), col, 1.8)


func _icon_brake(c: Control, p: Vector2, col: Color) -> void:
	c.draw_arc(p, 8.0, 0.0, TAU, 24, col, 2.0)
	_txt(c, "!", p + Vector2(0, 5), 13, col, 1)


## Round instrument face: brass bezel, matt black face, faint inner ring.
func _night_amt() -> float:
	return clampf(1.0 - TimeOfDay.light_level * 1.6, 0.0, 1.0)


func _dial_face(c: Control, ctr: Vector2, r: float) -> void:
	var night: float = _night_amt()
	# night: each gauge is back-lit, a warm bulb halo bleeding out round the bezel
	if night > 0.02:
		for gi in 12:
			var gf: float = float(gi) / 12.0
			c.draw_circle(ctr, r + 4.0 + 34.0 * (1.0 - gf), Color(1.0, 0.78, 0.42, 0.075 * night * (gf + 0.15)))
	c.draw_circle(ctr + Vector2(2, 3), r + 4.0, Color(0, 0, 0, 0.35))
	c.draw_circle(ctr, r + 3.0, BRASS.darkened(0.4))
	c.draw_arc(ctr, r + 1.5, 0.0, TAU, 64, BRASS, 2.0)
	c.draw_circle(ctr, r - 0.5, DIAL_FACE)
	if night > 0.02:
		for bi in 6:
			c.draw_circle(ctr, (r - 0.5) * (1.0 - float(bi) / 6.0), Color(1.0, 0.82, 0.5, 0.04 * night))
	c.draw_arc(ctr, r - 22.0, 0.0, TAU, 48, Color(1, 1, 1, 0.05), 1.0)


func _needle(c: Control, ctr: Vector2, ang: float, ln: float, w: float, col: Color) -> void:
	var d := Vector2(cos(ang), sin(ang))
	var n := Vector2(-d.y, d.x)
	c.draw_colored_polygon(PackedVector2Array([ctr - d * 10.0 + n * w * 0.6 + Vector2(1.5, 2.0), ctr + d * ln + Vector2(1.5, 2.0), ctr - d * 10.0 - n * w * 0.6 + Vector2(1.5, 2.0)]), Color(0, 0, 0, 0.45))
	c.draw_colored_polygon(PackedVector2Array([ctr - d * 9.0 + n * w, ctr + d * (ln - 3.0) + n * 0.7, ctr + d * ln, ctr + d * (ln - 3.0) - n * 0.7, ctr - d * 9.0 - n * w]), col)
	c.draw_circle(ctr, 5.0, BRASS)
	c.draw_circle(ctr, 2.0, Color(0.1, 0.1, 0.1))


## Small boxed digital readout centred on pos.
func _value_box(c: Control, pos: Vector2, text: String, size: int, col: Color) -> void:
	var w: float = ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 12.0
	var rr := Rect2(pos.x - w * 0.5, pos.y - float(size) * 0.5 - 4.0, w, float(size) + 6.0)
	c.draw_rect(rr, Color(0, 0, 0, 0.7))
	c.draw_rect(rr, Color(BRASS, 0.5), false, 1.0)
	_txt(c, text, Vector2(pos.x, pos.y + float(size) * 0.38), size, col, 1)


## Control hints (right side): Xbox controller glyph + action (controller only). Shown when GameState.show_hints (Options >
## Control hints, F1 toggles it).
const HINTS := [
	["LS", "Fly"],
	["RS", "Look around"],
	["RT", "Throttle up"],
	["LT", "Throttle down"],
	["A", "Fire / drop"],
	["B", "Switch weapon"],
	["RB", "Boost"],
	["LB", "Level assist"],
	["Y", "Gear"],
	["L3", "Flaps"],
	["R3", "Wheel brake"],
	["X", "Camera"],
	["MENU", "Pause"],
]
const HINT_ROW: float = 25.0


func _draw_hints() -> void:
	var c: Control = _hints
	var w: float = c.size.x
	var h: float = HINT_ROW * float(HINTS.size()) + 16.0
	c.draw_rect(Rect2(0, 0, w, h), Color(0.04, 0.045, 0.04, 0.42))
	c.draw_rect(Rect2(0, 0, 2.0, h), Color(BRASS, 0.7))
	for i in HINTS.size():
		var row: Array = HINTS[i]
		var y: float = 8.0 + float(i) * HINT_ROW + HINT_ROW * 0.5
		_pad_glyph(c, Vector2(22.0, y), String(row[0]))
		_txt(c, String(row[1]), Vector2(44.0, y + 5.0), 13, Color(TEXT_COL, 0.88))


## Xbox controller glyphs: coloured face buttons, bumper / trigger pills, stick rings, menu button.
func _pad_glyph(c: Control, p: Vector2, g: String) -> void:
	var font: Font = ThemeDB.fallback_font
	var face := {"A": Color(0.38, 0.75, 0.2), "B": Color(0.86, 0.22, 0.18), "X": Color(0.2, 0.5, 0.92), "Y": Color(0.95, 0.75, 0.1)}
	if face.has(g):
		c.draw_circle(p, 9.5, Color(0, 0, 0, 0.6))
		c.draw_circle(p, 8.5, Color(0.12, 0.12, 0.12))
		var tw: float = font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		c.draw_string(UIKit.font(true), Vector2(p.x - tw * 0.5, p.y + 4.5), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, face[g])
		return
	var dark := Color(0.12, 0.12, 0.12)
	var lite := Color(0.92, 0.9, 0.84)
	match g:
		"LB", "RB":
			var r := Rect2(p.x - 13.0, p.y - 6.0, 26.0, 12.0)
			c.draw_rect(r.grow(1.0), Color(0, 0, 0, 0.6))
			c.draw_rect(r, dark)
		"LT", "RT":
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-10, -9), p + Vector2(10, -9), p + Vector2(10, 5), p + Vector2(0, 9), p + Vector2(-10, 5)]), dark)
		"LS", "RS", "L3", "R3":
			c.draw_circle(p, 10.0, Color(0, 0, 0, 0.6))
			c.draw_circle(p, 9.0, dark)
			c.draw_arc(p, 6.0, 0.0, TAU, 20, Color(lite, 0.5), 1.2)
			if g == "L3" or g == "R3":
				c.draw_circle(p, 2.0, lite)
		"MENU":
			c.draw_circle(p, 9.5, Color(0, 0, 0, 0.6))
			c.draw_circle(p, 8.5, dark)
			for k in 3:
				c.draw_line(p + Vector2(-4.0, -3.0 + 3.0 * float(k)), p + Vector2(4.0, -3.0 + 3.0 * float(k)), lite, 1.4)
			return
	var lbl: String = g.substr(0, 1) if g in ["LS", "RS", "L3", "R3"] else g
	var fs: int = 10 if lbl.length() > 1 else 11
	var tw2: float = font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	c.draw_string(UIKit.font(true), Vector2(p.x - tw2 * 0.5, p.y + 3.8), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lite)


func _draw_compass() -> void:
	if aircraft == null:
		return
	var hdg: float = aircraft.get_heading_deg()
	var w: float = _compass.size.x
	var px_per_deg: float = 4.0
	var base_y: float = 30.0
	var night: float = _night_amt()
	if night > 0.02:
		var strip := Rect2(10.0, base_y - 28.0, w - 20.0, 66.0)
		for gi in 12:
			var gf: float = float(gi) / 12.0
			_compass.draw_rect(strip.grow(26.0 * (1.0 - gf)), Color(1.0, 0.78, 0.42, 0.07 * night * (gf + 0.15)), true)
		_compass.draw_rect(strip, Color(0.12, 0.08, 0.03, 0.55 * night), true)
		_compass.draw_rect(strip, Color(1.0, 0.82, 0.5, 0.06 * night), true)
	_compass.draw_line(Vector2(12, base_y), Vector2(w - 12, base_y), Color(1, 1, 1, 0.28), 1.0)
	for d in range(-60, 61):
		var deg: float = floorf(hdg) + float(d)
		var m: int = int(fposmod(deg, 360.0))
		var x: float = w * 0.5 + (deg - hdg) * px_per_deg
		if x < 14.0 or x > w - 14.0:
			continue
		var fade: float = 1.0 - pow(absf(x - w * 0.5) / (w * 0.5), 2.0)
		if m % 5 == 0:
			var big: bool = m % 10 == 0
			_compass.draw_line(Vector2(x, base_y), Vector2(x, base_y - (13.0 if big else 6.0)), Color(TEXT_COL, 0.85 * fade), 1.5 if big else 1.0)
		if m % 30 == 0:
			var lbl: String = {0: "N", 90: "E", 180: "S", 270: "W"}.get(m, "%03d" % m)
			var lc: Color = ACCENT if m % 90 == 0 else TEXT_COL
			_txt(_compass, lbl, Vector2(x, base_y - 18.0), 16 if m % 90 == 0 else 12, Color(lc, fade), 1)
	_draw_nav_marker(hdg, w, base_y, px_per_deg)
	_compass.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, base_y + 2.0), Vector2(w * 0.5 - 6, base_y + 10.0), Vector2(w * 0.5 + 6, base_y + 10.0)]), ACCENT)
	var box := Rect2(w * 0.5 - 28.0, base_y + 12.0, 56.0, 22.0)
	_compass.draw_rect(box, PANEL_BG)
	_compass.draw_rect(box, Color(ACCENT, 0.7), false, 1.0)
	_txt(_compass, "%03d" % (int(round(hdg)) % 360), Vector2(w * 0.5, base_y + 28.0), 17, ACCENT, 1)


func _out_of_ammo() -> bool:
	if aircraft == null or aircraft.has_meta("unarmed") or (aircraft.stats != null and aircraft.stats.ammo <= 0):
		return false          # civil / transport sorties carry no weapons: nothing to run out of
	var rk: int = aircraft.weapons.rockets_left if aircraft.weapons != null else 0
	return aircraft.ammo <= 0 and aircraft.bombs <= 0 and rk <= 0


## Nearest airfield on the player's own side (the "head home" point once the guns are dry).
func _nearest_friendly_airfield() -> Variant:
	if aircraft == null:
		return null
	var best: Variant = null
	var bd: float = INF
	for n in get_tree().get_nodes_in_group("airfield"):
		var a := n as Node3D
		if a == null or str(a.get("team")) != GameState.player_side:
			continue
		var d: float = Vector2(a.global_position.x - aircraft.global_position.x, a.global_position.z - aircraft.global_position.z).length()
		if d < bd:
			bd = d
			best = a.global_position
	return best


## Subtle line on the compass tape toward the mode's next objective (target, bombers, home...), with the
## distance. Off the tape it becomes a small chevron at the nearer edge.
func _draw_nav_marker(hdg: float, w: float, base_y: float, px_per_deg: float) -> void:
	if aircraft == null:
		return
	# Out of ammunition: the marker switches to a green line home to the nearest friendly airfield.
	var np: Variant = null
	var col := Color(0.55, 0.92, 1.0)
	if _out_of_ammo():
		np = _nearest_friendly_airfield()
		if np != null:
			col = Color(0.42, 0.95, 0.42)
	else:
		var mode_node: Node = get_tree().get_first_node_in_group("game_mode")
		if mode_node != null and mode_node.has_method("nav_point"):
			np = mode_node.call("nav_point")
	if np == null:
		return
	var d: Vector3 = (np as Vector3) - aircraft.global_position
	d.y = 0.0
	if d.length() < 80.0:
		return
	var rel: float = wrapf(WorldCoords.dir_to_heading(d) - hdg, -180.0, 180.0)
	var km: float = d.length() * WorldCoords.HORIZ_COMPRESSION / 1000.0
	var x: float = w * 0.5 + rel * px_per_deg
	var edge: float = w * 0.5 - 16.0
	var dist_txt: String = "%d km" % int(round(km)) if km >= 10.0 else "%.1f km" % km
	if absf(x - w * 0.5) <= edge:
		var fade: float = 1.0 - 0.5 * pow(absf(x - w * 0.5) / (w * 0.5), 2.0)
		_compass.draw_line(Vector2(x, base_y - 22.0), Vector2(x, base_y + 6.0), Color(col, 0.7 * fade), 2.0)
		_compass.draw_colored_polygon(PackedVector2Array([Vector2(x, base_y - 26.0), Vector2(x - 3.5, base_y - 21.0), Vector2(x + 3.5, base_y - 21.0)]), Color(col, 0.85 * fade))
		# below the heading readout box (which ends at base_y + 34), so the compass direction never covers it
		_txt(_compass, dist_txt, Vector2(x, base_y + 44.0), 11, Color(col, 0.65 * fade), 1)
	else:
		var s: float = signf(rel)
		var ex: float = w * 0.5 + s * edge
		_compass.draw_colored_polygon(PackedVector2Array([Vector2(ex + s * 6.0, base_y - 8.0), Vector2(ex - s * 2.0, base_y - 15.0), Vector2(ex - s * 2.0, base_y - 1.0)]), Color(col, 0.7))
		_txt(_compass, dist_txt, Vector2(ex - s * 22.0, base_y + 44.0), 11, Color(col, 0.55), 1)


func _draw_aim() -> void:
	if camera == null or aircraft == null or aircraft.state == Aircraft.State.DEAD:
		return
	if GameState.show_pitch_ladder:
		_draw_ladder()
	# (no hit-confirm cross: _draw_hit_marker is kept but no longer drawn)


## White cross when your rounds land, a larger red one when you destroy the target.
func _draw_hit_marker() -> void:
	if _hit_t <= 0.0 and _kill_t <= 0.0:
		return
	var c: Vector2 = _aim.size * 0.5
	var killed: bool = _kill_t > 0.0
	var a: float = clampf((_kill_t / 0.8) if killed else (_hit_t / 0.25), 0.0, 1.0)
	var col: Color = GameState.accessible_color(Color(1.0, 0.25, 0.2, a)) if killed else Color(1, 1, 1, a)
	var r0: float = 10.0 if killed else 7.0
	var r1: float = 22.0 if killed else 15.0
	for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		_aim.draw_line(c + d * r0, c + d * r1, col, 2.5, true)


## Horizon line + pitch ladder, projected from the aircraft's heading so it follows the camera exactly.
func _draw_ladder() -> void:
	if aircraft.on_ground or aircraft.speed < 5.0:
		return
	var f: Vector3 = aircraft.get_forward()
	var flat := Vector3(f.x, 0.0, f.z)
	if flat.length() < 0.05:
		return
	flat = flat.normalized()
	var right: Vector3 = flat.cross(Vector3.UP).normalized()
	var cp: Vector3 = camera.global_position
	for pd in range(-30, 21, 10):
		var pr: float = deg_to_rad(float(pd))
		var wp: Vector3 = cp + (flat * cos(pr) + Vector3.UP * sin(pr)) * 4000.0
		if camera.is_position_behind(wp):
			continue
		var sp: Vector2 = camera.unproject_position(wp)
		if sp.y < 120.0 or sp.y > get_viewport().get_visible_rect().size.y - 230.0:
			continue
		var sr: Vector2 = camera.unproject_position(wp + right * 200.0) - sp
		if sr.length() < 0.01:
			continue
		var rd: Vector2 = sr.normalized()
		var alpha: float = 0.55 if pd == 0 else 0.30
		var col := Color(0.9, 0.95, 0.85, alpha)
		var gap: float = 70.0 if pd == 0 else 24.0
		var ln: float = 150.0 if pd == 0 else 52.0
		for sgn in [-1.0, 1.0]:
			var a1: Vector2 = sp + rd * float(sgn) * gap
			var a2: Vector2 = sp + rd * float(sgn) * (gap + ln)
			_aim.draw_line(a1, a2, col, 1.4)
			if pd != 0:
				var tick: Vector2 = Vector2(rd.y, -rd.x) * (7.0 if pd > 0 else -7.0)
				_aim.draw_line(a2, a2 + tick, col, 1.4)
		if pd != 0:
			_txt(_aim, "%d" % absi(pd), sp + rd * (gap + ln + 16.0) + Vector2(0, 4), 11, Color(col, alpha + 0.15), 1)


func _update_map(_delta: float) -> void:
	if terrain == null or aircraft == null:
		return
	# The window is clamped inside the world bounds so the map never runs off
	# the edge of the playable region (no blank "cut off" area on the minimap).
	var b := WorldCoords.world_bounds()
	var nc := Vector2(
		clampf(aircraft.global_position.x, b.position.x + MAP_RANGE, b.position.x + b.size.x - MAP_RANGE),
		clampf(aircraft.global_position.z, b.position.y + MAP_RANGE, b.position.y + b.size.y - MAP_RANGE)
	)
	var moved: bool = _map_center.distance_squared_to(nc) > MAP_MOVE * MAP_MOVE
	if not (moved or _map_dirty):
		return
	_map_dirty = false
	_map_center = nc
	if _color_img != null:
		_blit_map(b)
		return
	# Fallback (no imagery): progressive height grid at map resolution.
	for r in 32:
		var j: int = _map_row
		for i in MAP_RES:
			var wx: float = _map_center.x + (float(i) / float(MAP_RES - 1) - 0.5) * 2.0 * MAP_RANGE
			var wz: float = _map_center.y + (float(j) / float(MAP_RES - 1) - 0.5) * 2.0 * MAP_RANGE
			var h: float = terrain.call("get_terrain_y", wx, wz)
			var c: Color
			if h < 0.6:
				c = Color(0.12, 0.28, 0.40).lerp(Color(0.2, 0.42, 0.52), clampf(1.0 + h / 60.0, 0.0, 1.0))
			elif h > 150.0:
				c = Color(0.62, 0.6, 0.5)
			else:
				c = Color(0.38, 0.48, 0.26).lerp(Color(0.6, 0.58, 0.4), clampf(h / 300.0, 0.0, 1.0))
			_map_img.set_pixel(i, j, c)
		_map_row += 1
		if _map_row >= MAP_RES:
			_map_row = 0
			_map_tex.update(_map_img)
			break


## Re-blit the imagery window around the map centre into the map texture.
func _blit_map(b: Rect2) -> void:
	var cw: int = _color_img.get_width()
	var ch: int = _color_img.get_height()
	var w: int = maxi(int(ceil(2.0 * MAP_RANGE * float(cw) / b.size.x)), 8)
	var h: int = maxi(int(ceil(2.0 * MAP_RANGE * float(ch) / b.size.y)), 8)
	var x0: int = clampi(int(round((_map_center.x - MAP_RANGE - b.position.x) * float(cw) / b.size.x)), 0, maxi(cw - w, 0))
	var y0: int = clampi(int(round((_map_center.y - MAP_RANGE - b.position.y) * float(ch) / b.size.y)), 0, maxi(ch - h, 0))
	var crop := Image.create(w, h, false, Image.FORMAT_RGBA8)
	crop.blit_rect(_color_img, Rect2i(x0, y0, w, h), Vector2i(0, 0))
	crop.resize(MAP_RES, MAP_RES, Image.INTERPOLATE_BILINEAR)
	_map_img = crop
	_map_tex.update(_map_img)


## Plane silhouette (top view) for the minimap: fuselage, swept wings and tailplane, drawn with a dark outline first.
## `dir` = unit heading on the map, `k` = size multiplier, `bomber` = longer fuselage and wider wings.
func _plane_icon(c: Control, p: Vector2, dir: Vector2, k: float, col: Color, bomber: bool = false) -> void:
	if dir.length() < 0.01:
		dir = Vector2(0, -1)
	var d: Vector2 = dir * k
	var s: Vector2 = Vector2(-dir.y, dir.x) * k
	var span: float = 10.0 if bomber else 7.5
	var len: float = 9.0 if bomber else 7.5
	var parts: Array = []
	parts.append(PackedVector2Array([p + d * len, p + d * (len * 0.4) + s * 1.5, p - d * (len * 0.7) + s * 1.1, p - d * len, p - d * (len * 0.7) - s * 1.1, p + d * (len * 0.4) - s * 1.5]))
	parts.append(PackedVector2Array([p + d * 2.5 + s * 1.2, p - d * 0.5 + s * span, p - d * 3.2 + s * span, p - d * 2.0 + s * 1.0]))
	parts.append(PackedVector2Array([p + d * 2.5 - s * 1.2, p - d * 2.0 - s * 1.0, p - d * 3.2 - s * span, p - d * 0.5 - s * span]))
	var tw: float = span * 0.42
	parts.append(PackedVector2Array([p - d * (len * 0.6) + s * 0.9, p - d * (len * 0.85) + s * tw, p - d * (len + 0.5) + s * tw, p - d * (len * 0.8) + s * 0.9]))
	parts.append(PackedVector2Array([p - d * (len * 0.6) - s * 0.9, p - d * (len * 0.8) - s * 0.9, p - d * (len + 0.5) - s * tw, p - d * (len * 0.85) - s * tw]))
	for poly in parts:       # dark outline: the same shapes grown about the centre
		var big := PackedVector2Array()
		for q in (poly as PackedVector2Array):
			big.append(p + (q - p) * 1.35)
		c.draw_colored_polygon(big, Color(0, 0, 0, 0.75))
	for poly2 in parts:
		c.draw_colored_polygon(poly2 as PackedVector2Array, col)


## A moving weather front on the minimap, in weather-map style: blue triangles (cold) or red half-discs (warm)
## along the line, on the side it is moving towards.
func _draw_front(rect: Rect2, to_map: Callable) -> void:
	var fi: Dictionary = WeatherManager.front_info()
	if not bool(fi["active"]):
		return
	var n: Vector2 = fi["normal"]
	var off: float = float(fi["offset"])
	var m: Vector2 = _map_center
	var p0: Vector2 = m + n * (off - m.dot(n))
	var t := Vector2(-n.y, n.x)
	var a: Vector2 = to_map.call(Vector3(p0.x - t.x * MAP_RANGE * 2.0, 0.0, p0.y - t.y * MAP_RANGE * 2.0))
	var b: Vector2 = to_map.call(Vector3(p0.x + t.x * MAP_RANGE * 2.0, 0.0, p0.y + t.y * MAP_RANGE * 2.0))
	# clip the segment to the chart (Liang-Barsky)
	var d: Vector2 = b - a
	var t0: float = 0.0
	var t1: float = 1.0
	var pq: Array = [[-d.x, a.x - rect.position.x], [d.x, rect.end.x - a.x], [-d.y, a.y - rect.position.y], [d.y, rect.end.y - a.y]]
	for e in pq:
		var pp: float = float(e[0])
		var qq: float = float(e[1])
		if absf(pp) < 0.0001:
			if qq < 0.0:
				return
			continue
		var r: float = qq / pp
		if pp < 0.0:
			t0 = maxf(t0, r)
		else:
			t1 = minf(t1, r)
		if t0 > t1:
			return
	var c0: Vector2 = a + d * t0
	var c1: Vector2 = a + d * t1
	var cold: bool = bool(fi["cold"])
	var col: Color = Color(0.25, 0.5, 1.0, 0.95) if cold else Color(0.95, 0.25, 0.2, 0.95)
	_minimap.draw_line(c0, c1, Color(0, 0, 0, 0.6), 4.0)
	_minimap.draw_line(c0, c1, col, 2.0)
	var nm: Vector2 = (to_map.call(Vector3(p0.x + n.x * 1000.0, 0.0, p0.y + n.y * 1000.0)) - to_map.call(Vector3(p0.x, 0.0, p0.y))).normalized()
	var along: Vector2 = (c1 - c0)
	var L: float = along.length()
	if L < 10.0:
		return
	var u: Vector2 = along / L
	var step: float = 18.0
	var k: float = step * 0.5
	while k < L - 4.0:
		var q: Vector2 = c0 + u * k
		if cold:
			_minimap.draw_colored_polygon(PackedVector2Array([q - u * 4.5, q + u * 4.5, q + nm * 6.5]), col)
		else:
			_minimap.draw_arc(q, 4.5, nm.angle() - PI * 0.5, nm.angle() + PI * 0.5, 8, col, 2.5)
		k += step


func _draw_minimap() -> void:
	var sz: Vector2 = _minimap.size
	var night: float = clampf(1.0 - TimeOfDay.light_level * 1.6, 0.0, 1.0)
	# at night the chart is lit from behind like a lamp-box: a warm halo bleeding out past the frame
	if night > 0.02:
		for gi in 12:
			var gf: float = float(gi) / 12.0
			_minimap.draw_rect(Rect2(Vector2.ZERO, sz).grow(46.0 * (1.0 - gf)), Color(1.0, 0.78, 0.42, 0.085 * night * (gf + 0.15)), true)
	_minimap.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.08, 0.06, 0.03, 0.55) if night > 0.02 else Color(0, 0, 0, 0.5))
	if aircraft == null:
		return
	var rect := Rect2(3, 3, sz.x - 6, sz.y - 6)
	# dim the map at night like a real chart light
	# cloud and fog strip the chart's ground detail: the imagery fades into the dark base as the weather closes in
	var nav_pen: float = MoonWeather.nav_penalty_now()
	var shade := Color(1.0, 0.99 - 0.06 * night, 0.96 - 0.2 * night, 1.0 - 0.6 * nav_pen)
	_minimap.draw_texture_rect(_map_tex, rect, false, shade)
	# brightness lift (day) plus a lamp-like warm bloom (night), strongest in the middle
	_minimap.draw_rect(rect, Color(1.0, 0.96, 0.86, 0.13 + 0.07 * night))
	if night > 0.02:
		for bi in 8:
			var bf: float = float(bi) / 8.0
			_minimap.draw_circle(rect.get_center(), rect.size.x * 0.62 * (1.0 - bf), Color(1.0, 0.82, 0.5, 0.035 * night))
	_minimap.draw_rect(rect, Color(0.9, 0.85, 0.6, 0.35), false, 1.0)
	_corner_brackets(_minimap, Rect2(Vector2.ZERO, sz))
	_txt(_minimap, "%d KM" % int(MAP_RANGE * 2.0 * WorldCoords.HORIZ_COMPRESSION / 1000.0), Vector2(rect.position.x + 8, rect.end.y - 8), 11, Color(TEXT_COL, 0.85))
	var to_map := func(p: Vector3) -> Vector2:
		var u: float = (p.x - _map_center.x) / (2.0 * MAP_RANGE) + 0.5
		var v: float = (p.z - _map_center.y) / (2.0 * MAP_RANGE) + 0.5
		return rect.position + Vector2(u, v) * rect.size
	# half-range ring
	_minimap.draw_arc(rect.get_center(), rect.size.x * 0.25, 0.0, TAU, 48, Color(0.9, 0.85, 0.6, 0.22), 1.0)
	_draw_front(rect, to_map)
	# airfields: runway stripe rotated to heading
	var px_per_u: float = rect.size.x / (2.0 * MAP_RANGE)
	for af in _af_spots:
		var mp: Vector2 = to_map.call(af["pos"])
		if not rect.has_point(mp):
			continue
		var d: Vector2 = Vector2(sin(float(af["hdg"])), -cos(float(af["hdg"]))) * float(af["len"]) * 0.5 * px_per_u
		_minimap.draw_line(mp - d, mp + d, Color(0.98, 0.98, 0.92, 0.95), 3.0)
		_minimap.draw_circle(mp, 2.0, Color(0.98, 0.98, 0.92, 0.95))
	# towns: dot sized by population, names for the bigger ones
	for c in _city_spots:
		var mp2: Vector2 = to_map.call(c["pos"])
		if not rect.has_point(mp2):
			continue
		if nav_pen >= 0.4 and int(c["size"]) < 3:
			continue                 # small towns drop off the chart in fog and storm
		var cr: float = 1.5 + float(c["size"]) * 0.8
		_minimap.draw_circle(mp2, cr, Color(0.92, 0.92, 0.88, 0.9))
		if int(c["size"]) >= 3 and nav_pen < 0.25 and rect.get_center().distance_to(mp2) < rect.size.x * 0.34:
			var name := String(c["name"])
			var font := ThemeDB.fallback_font
			var tw := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var lx := mp2.x + cr + 3.0
			if lx + tw > rect.end.x:
				lx = mp2.x - cr - 3.0 - tw
			var ly := mp2.y + 4.0
			if lx >= rect.position.x and lx + tw <= rect.end.x and ly - 11.0 >= rect.position.y and ly + 3.0 <= rect.end.y:
				_minimap.draw_string(font, Vector2(lx, ly), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.95, 0.9, 0.9))
	# taskings against moving enemy aircraft / ships (intercepts) give only a general area: enemy contacts show on
	# the minimap once they are close (mode.minimap_fog_range), and bombers flying together share ONE icon
	var gm0: Node = get_tree().get_first_node_in_group("game_mode")
	var fog_r: float = float(gm0.call("minimap_fog_range")) if gm0 != null and gm0.has_method("minimap_fog_range") else 0.0
	var apos: Vector3 = aircraft.global_position
	var bomber_spots: Array = []
	for m in _markers:
		var n = m[0]  # untyped: a typed Node3D assignment errors when the node was freed
		if is_instance_valid(n):
			var wpos: Vector3 = (n as Node3D).global_position
			if fog_r > 0.0 and (n is Aircraft or n.is_in_group("ship")) and str(n.get("team")) != GameState.player_side \
					and Vector2(wpos.x - apos.x, wpos.z - apos.z).length() > fog_r:
				continue
			if n is Aircraft and (n as Node3D).is_in_group("bomber"):
				var close: bool = false
				for bp in bomber_spots:
					if Vector2(wpos.x - (bp as Vector3).x, wpos.z - (bp as Vector3).z).length() < BOMBER_MERGE_DIST:
						close = true
						break
				if close:
					continue
				bomber_spots.append(wpos)
			var mpp: Vector2 = to_map.call(wpos)
			if rect.has_point(mpp):
				if n is Aircraft:
					# little plane silhouette in the aircraft's colour, pointing the way it flies (bombers: bigger wings)
					var af3: Vector3 = (n as Aircraft).get_forward()
					_plane_icon(_minimap, mpp, Vector2(af3.x, af3.z).normalized(), 1.0, GameState.accessible_color(m[1]), (n as Node3D).is_in_group("bomber"))
				else:
					_minimap.draw_circle(mpp, 3.0, GameState.accessible_color(m[1]))
	# the current objective (mode nav_point): a pulsing diamond, or an arrow on the frame edge with the
	# distance when it lies off the chart (Ops Room taskings are often 20-50 km out)
	var gm: Node = get_tree().get_first_node_in_group("game_mode")
	if gm != null and gm.has_method("nav_point"):
		var onp: Variant = gm.call("nav_point")
		if onp != null:
			var op: Vector2 = to_map.call(onp as Vector3)
			var oc := Color(1.0, 0.82, 0.25)
			var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
			var fog_area: float = float(gm.call("minimap_fog_area")) if gm.has_method("minimap_fog_area") else 0.0
			if fog_area > 0.0 and rect.grow(-6.0).has_point(op):
				# a general area, not a fix: a soft search circle
				var ar: float = maxf((to_map.call((onp as Vector3) + Vector3(fog_area, 0.0, 0.0)) as Vector2).distance_to(op), 8.0)
				_minimap.draw_circle(op, ar, Color(oc, 0.10))
				_minimap.draw_arc(op, ar, 0.0, TAU, 48, Color(0, 0, 0, 0.55), 3.0)
				_minimap.draw_arc(op, ar, 0.0, TAU, 48, Color(oc, 0.55 + 0.25 * pulse), 1.5)
			elif rect.grow(-6.0).has_point(op):
				var r0: float = 5.0 + 2.0 * pulse
				var dia := PackedVector2Array([op + Vector2(0, -r0), op + Vector2(r0, 0), op + Vector2(0, r0), op + Vector2(-r0, 0)])
				_minimap.draw_colored_polygon(dia, Color(oc, 0.85))
				dia.append(dia[0])
				_minimap.draw_polyline(dia, Color(0, 0, 0, 0.8), 1.5)
				_minimap.draw_arc(op, r0 + 5.0 + 4.0 * pulse, 0.0, TAU, 24, Color(oc, 0.5 * (1.0 - pulse)), 1.5)
			else:
				var ctr: Vector2 = rect.get_center()
				var dv: Vector2 = (op - ctr).normalized()
				var half: Vector2 = rect.size * 0.5 - Vector2(10, 10)
				var k: float = minf(half.x / maxf(absf(dv.x), 0.001), half.y / maxf(absf(dv.y), 0.001))
				var ep: Vector2 = ctr + dv * k
				var sv := Vector2(-dv.y, dv.x)
				_minimap.draw_colored_polygon(PackedVector2Array([ep + dv * 7.0, ep - dv * 4.0 + sv * 5.5, ep - dv * 4.0 - sv * 5.5]), Color(oc, 0.7 + 0.3 * pulse))
				var okm: float = Vector2((onp as Vector3).x - aircraft.global_position.x, (onp as Vector3).z - aircraft.global_position.z).length() * WorldCoords.HORIZ_COMPRESSION / 1000.0
				var tp: Vector2 = ep - dv * 22.0 + Vector2(0, 4)
				_txt(_minimap, "%d km" % int(round(okm)), tp, 11, Color(oc, 0.95), 1)
	# barrage balloon cables: a short hazard cross where each live wire runs up from its winch (the wire is
	# vertical, so on the chart it is a point; the cross marks the reach a wing can strike within)
	for cn in get_tree().get_nodes_in_group("balloon_cable"):
		if not is_instance_valid(cn) or bool(cn.get("is_dead")):
			continue
		var cmp: Vector2 = to_map.call((cn as Node3D).global_position)
		if not rect.grow(-4.0).has_point(cmp):
			continue
		var cx := Vector2(3.5, 3.5)
		var cy := Vector2(3.5, -3.5)
		_minimap.draw_line(cmp - cx, cmp + cx, Color(0, 0, 0, 0.7), 3.0)
		_minimap.draw_line(cmp - cy, cmp + cy, Color(0, 0, 0, 0.7), 3.0)
		_minimap.draw_line(cmp - cx, cmp + cx, CABLE_COL, 1.5)
		_minimap.draw_line(cmp - cy, cmp + cy, CABLE_COL, 1.5)
	# ships under way: small hulls along their heading, yellow friendly / red enemy
	for sh in get_tree().get_nodes_in_group("ship"):
		var sn := sh as Node3D
		if sn == null or bool(sh.get("is_dead")) or float(sh.get("speed")) < 0.5:
			continue
		if fog_r > 0.0 and str(sh.get("team")) != GameState.player_side \
				and Vector2(sn.global_position.x - apos.x, sn.global_position.z - apos.z).length() > fog_r:
			continue
		var smp: Vector2 = to_map.call(sn.global_position)
		if not rect.grow(-3.0).has_point(smp):
			continue
		var sf: Vector3 = -sn.global_transform.basis.z
		var sd := Vector2(sf.x, sf.z).normalized()
		var sp := Vector2(-sd.y, sd.x)
		var scol: Color = GameState.accessible_color(FRIEND_COL if str(sh.get("team")) == GameState.player_side else ENEMY_COL)
		var hullp := PackedVector2Array([smp + sd * 5.0, smp + sd * 1.0 + sp * 1.8, smp - sd * 4.0 + sp * 1.6, smp - sd * 4.0 - sp * 1.6, smp + sd * 1.0 - sp * 1.8])
		var outline := PackedVector2Array()
		for q in hullp:
			outline.append(smp + (q - smp) * 1.45)
		_minimap.draw_colored_polygon(outline, Color(0, 0, 0, 0.7))
		_minimap.draw_colored_polygon(hullp, scol)
	var pp: Vector2 = to_map.call(aircraft.global_position)
	pp = pp.clamp(rect.position, rect.end)
	var f: Vector3 = aircraft.get_forward()
	_plane_icon(_minimap, pp, Vector2(f.x, f.z).normalized(), 1.4, Color(1, 0.9, 0.3), AircraftCatalog.is_bomber(aircraft.stats.id) if "id" in aircraft.stats else false)
	_minimap.draw_string(ThemeDB.fallback_font, Vector2(sz.x * 0.5 - 4, 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ACCENT)
