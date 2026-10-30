class_name FlightPlanner
extends CanvasLayer
## Sortie planner opened from the start menu: a zoomable map of the whole theatre (airfields, cities). Click an airfield to
## start there (on the runway or airborne over it) or click anywhere else to start in the air at that spot. Pick the
## scenario (free flight, bombing run, ground strike, boat strike, bomber escort, fighter sweep) and the enemy strength.
## Emits confirmed(plan) with the keys main.gd / the modes understand:
##   spawn_lat, spawn_lon, spawn_airfield ("" = free air spawn), spawn_airborne, spawn_alt (m), spawn_heading,
##   mode, targets (ids), ambient, difficulty, no_fighters, scenario

signal confirmed(plan: Dictionary)
signal cancelled

const LAT_MIN := 48.9
const LAT_MAX := 53.0
const LON_MIN := -4.6
const LON_MAX := 9.0
const SCENARIOS := [
	["free", "Free flight (no objectives)"],
	["bombing", "Bombing run"],
	["ground", "Ground strike (convoys, trains, guns)"],
	["ships", "Boat / convoy strike"],
	["escort", "Bomber escort"],
	["sweep", "Fighter sweep (waves of fighters)"],
]
const ENEMY := [["None", 0.2], ["Light", 0.25], ["Normal", 0.5], ["Heavy", 0.85]]
const BOMB_TYPES := ["factory", "rail_yard", "port", "bridge", "battery", "radar", "v1_site"]

var side: String = "Allies"
var _airfields: Array = []
var _cities: Array = []
var _targets: Array = []
var _map: MapView
var _sel: Dictionary = {}
var _info: Label
var _target_info: Label
var _start_type: OptionButton
var _alt: HSlider
var _alt_label: Label
var _hdg: HSlider
var _hdg_label: Label
var _scenario: OptionButton
var _enemy: OptionButton
var _wingmen: OptionButton
var _fly: Button
var _date_slider: HSlider
var _date_label: Label
var _env_label: Label
var _forecast: String = "clear"
## Weather picked in the menu's Conditions (a preset, not Random): it overrides the day's forecast. "" = random day.
var weather_choice: String = ""


class MapView extends Control:
	signal picked(lat: float, lon: float, airfield_id: String)
	var tex: Texture2D
	var zoom: float = 1.0
	var center: Vector2 = Vector2(0.4, 0.55)
	var airfields: Array = []
	var cities: Array = []
	var sel: Dictionary = {}
	var heading: float = 0.0
	var _drag: bool = false
	var _moved: float = 0.0
	var _hover: String = ""

	func _init() -> void:
		clip_contents = true
		focus_mode = Control.FOCUS_NONE

	func _aspect() -> float:
		return float(tex.get_width()) / float(tex.get_height()) if tex != null else 2.05

	func _map_size() -> Vector2:
		var base: float = minf(size.x, size.y * _aspect())
		return Vector2(base * zoom, base * zoom / _aspect())

	func to_screen(lat: float, lon: float) -> Vector2:
		var u: float = (lon - FlightPlanner.LON_MIN) / (FlightPlanner.LON_MAX - FlightPlanner.LON_MIN)
		var v: float = (FlightPlanner.LAT_MAX - lat) / (FlightPlanner.LAT_MAX - FlightPlanner.LAT_MIN)
		var ms: Vector2 = _map_size()
		return size * 0.5 + Vector2((u - center.x) * ms.x, (v - center.y) * ms.y)

	func to_latlon(p: Vector2) -> Vector2:
		var ms: Vector2 = _map_size()
		var uv: Vector2 = center + (p - size * 0.5) / ms
		return Vector2(FlightPlanner.LAT_MAX - uv.y * (FlightPlanner.LAT_MAX - FlightPlanner.LAT_MIN), FlightPlanner.LON_MIN + uv.x * (FlightPlanner.LON_MAX - FlightPlanner.LON_MIN))

	func _nearest_airfield(p: Vector2, max_px: float) -> Dictionary:
		var best: Dictionary = {}
		var bd: float = max_px
		for a in airfields:
			var d: float = to_screen(float(a["lat"]), float(a["lon"])).distance_to(p)
			if d < bd:
				bd = d
				best = a
		return best

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				var before: Vector2 = to_latlon(mb.position)
				zoom = clampf(zoom * (1.2 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2), 1.0, 24.0)
				var after: Vector2 = to_screen(before.x, before.y)
				var ms: Vector2 = _map_size()
				center += (after - mb.position) / ms
				_clamp()
				queue_redraw()
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_drag = true
					_moved = 0.0
				else:
					_drag = false
					if _moved < 6.0:
						var af: Dictionary = _nearest_airfield(mb.position, 14.0)
						if not af.is_empty():
							picked.emit(float(af["lat"]), float(af["lon"]), str(af["id"]))
						else:
							var ll: Vector2 = to_latlon(mb.position)
							picked.emit(ll.x, ll.y, "")
		elif event is InputEventMouseMotion:
			var mm: InputEventMouseMotion = event
			if _drag:
				_moved += mm.relative.length()
				center -= mm.relative / _map_size()
				_clamp()
			var h: Dictionary = _nearest_airfield(mm.position, 12.0)
			var hid: String = str(h.get("id", ""))
			if hid != _hover:
				_hover = hid
			queue_redraw()

	func _clamp() -> void:
		center = Vector2(clampf(center.x, 0.0, 1.0), clampf(center.y, 0.0, 1.0))

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.09))
		var ms: Vector2 = _map_size()
		var tl: Vector2 = size * 0.5 - Vector2(center.x * ms.x, center.y * ms.y)
		if tex != null:
			draw_texture_rect(tex, Rect2(tl, ms), false)
		else:
			draw_rect(Rect2(tl, ms), Color(0.18, 0.26, 0.17))
		var font: Font = UIKit.font()
		for c in cities:
			if int(c["size"]) < 3 and zoom < 3.0:
				continue
			var p: Vector2 = to_screen(float(c["lat"]), float(c["lon"]))
			if p.x < -20 or p.y < -20 or p.x > size.x + 20 or p.y > size.y + 20:
				continue
			draw_circle(p, 2.5 + float(c["size"]) * 0.5, Color(0.95, 0.9, 0.7, 0.9))
			if zoom >= 2.0 or int(c["size"]) >= 4:
				draw_string(font, p + Vector2(6, -4), str(c["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85))
		for a in airfields:
			var p2: Vector2 = to_screen(float(a["lat"]), float(a["lon"]))
			if p2.x < -20 or p2.y < -20 or p2.x > size.x + 20 or p2.y > size.y + 20:
				continue
			var col: Color = Color(0.35, 0.65, 1.0) if str(a["side"]) == "RAF" else Color(1.0, 0.38, 0.32)
			draw_circle(p2, 5.5, Color(0, 0, 0, 0.8))
			draw_circle(p2, 4.0, col)
			var show_name: bool = zoom >= 2.0 or str(a["id"]) == _hover or str(a["id"]) == str(sel.get("airfield", ""))
			if show_name:
				draw_string(font, p2 + Vector2(8, 5), str(a["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col.lightened(0.35))
		if not sel.is_empty():
			var sp: Vector2 = to_screen(float(sel["lat"]), float(sel["lon"]))
			draw_arc(sp, 12.0, 0.0, TAU, 28, Color(1.0, 0.85, 0.2), 2.5)
			var dirv := Vector2(sin(deg_to_rad(heading)), -cos(deg_to_rad(heading)))
			draw_line(sp, sp + dirv * 46.0, Color(1.0, 0.85, 0.2), 3.0)
			draw_line(sp + dirv * 46.0, sp + dirv * 38.0 + Vector2(-dirv.y, dirv.x) * 6.0, Color(1.0, 0.85, 0.2), 3.0)
			draw_line(sp + dirv * 46.0, sp + dirv * 38.0 - Vector2(-dirv.y, dirv.x) * 6.0, Color(1.0, 0.85, 0.2), 3.0)
		draw_string(font, Vector2(12, 24), "Wheel: zoom   Drag: pan   Click: choose start", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
		draw_string(font, Vector2(size.x - 28, 24), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))


func _ready() -> void:
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_data()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(UIKit.dimmer(0.8))
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 24.0
	hb.offset_right = -24.0
	hb.offset_top = 24.0
	hb.offset_bottom = -24.0
	hb.add_theme_constant_override("separation", 16)
	root.add_child(hb)
	_map = MapView.new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.airfields = _airfields
	_map.cities = _cities
	if ResourceLoader.exists("res://data/heightmap/region_color.png"):
		_map.tex = load("res://data/heightmap/region_color.png") as Texture2D
	_map.picked.connect(_on_picked)
	hb.add_child(_map)

	var vb: VBoxContainer = UIKit.panel(hb)
	(vb.get_parent().get_parent() as Control).custom_minimum_size = Vector2(400, 0)
	UIKit.heading(vb, "PLAN SORTIE", 30)
	_info = UIKit.label("Click an airfield or any point on the map.", 16, UIKit.ACCENT)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_override("font", UIKit.body_font())
	vb.add_child(_info)
	_start_type = UIKit.option_row(vb, "Start", ["On the runway", "Airborne"], 18)
	_start_type.item_selected.connect(func(_i: int) -> void: _refresh())
	_alt_label = UIKit.label("", 16)
	vb.add_child(_alt_label)
	_alt = HSlider.new()
	_alt.min_value = 150.0
	_alt.max_value = 7000.0
	_alt.step = 50.0
	_alt.value = 1200.0
	_alt.value_changed.connect(func(_v: float) -> void: _refresh())
	vb.add_child(_alt)
	_hdg_label = UIKit.label("", 16)
	vb.add_child(_hdg_label)
	_hdg = HSlider.new()
	_hdg.min_value = 0.0
	_hdg.max_value = 359.0
	_hdg.step = 5.0
	_hdg.value = 90.0
	_hdg.value_changed.connect(func(_v: float) -> void: _refresh())
	vb.add_child(_hdg)
	vb.add_child(UIKit.rule(0.4))
	var names: Array = []
	for s in SCENARIOS:
		names.append(String(s[1]))
	_scenario = UIKit.option_row(vb, "Scenario", names, 18)
	_scenario.item_selected.connect(func(_i: int) -> void: _refresh())
	var en: Array = []
	for e in ENEMY:
		en.append(String(e[0]))
	_enemy = UIKit.option_row(vb, "Enemy", en, 18)
	_enemy.select(2)
	_wingmen = UIKit.option_row(vb, "Wingmen", ["None", "1", "2", "3"], 18)
	_wingmen.select(2)
	_date_label = UIKit.label("", 16)
	vb.add_child(_date_label)
	_date_slider = HSlider.new()
	_date_slider.min_value = 0.0
	_date_slider.max_value = float(MoonWeather.DATE_SPAN_DAYS)
	_date_slider.step = 1.0
	# no date / weather slider any more: the sortie is flown on a random day with that day's forecast
	# (a fixed weather is chosen in the menu's Conditions instead of Random)
	_date_slider.value = float(randi_range(0, MoonWeather.DATE_SPAN_DAYS))
	_date_slider.visible = false
	vb.add_child(_date_slider)
	_env_label = UIKit.label("", 15, UIKit.TEXT_DIM)
	_env_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_env_label.add_theme_font_override("font", UIKit.body_font())
	vb.add_child(_env_label)
	_target_info = UIKit.label("", 15, UIKit.TEXT_DIM)
	_target_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_target_info.add_theme_font_override("font", UIKit.body_font())
	vb.add_child(_target_info)
	_fly = UIKit.button("FLY", _on_fly, 28, true)
	vb.add_child(_fly)
	vb.add_child(UIKit.button("Back", func() -> void: cancelled.emit(), 20))
	_fly.disabled = true
	_refresh()


func _load_data() -> void:
	var f: FileAccess = FileAccess.open("res://data/locations.json", FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return
	for a in (d as Dictionary).get("airfields", []):
		if bool(a.get("in_bounds", true)):
			_airfields.append(a)
	for c in (d as Dictionary).get("cities", []):
		if bool(c.get("in_bounds", true)):
			_cities.append(c)
	for t in (d as Dictionary).get("targets", []):
		if bool(t.get("in_bounds", true)):
			_targets.append(t)


func _is_friendly_field(af_id: String) -> bool:
	var want: String = "RAF" if side == "Allies" else "Luftwaffe"
	for a in _airfields:
		if str(a["id"]) == af_id:
			return str(a.get("side", "")) == want
	return false


func _on_picked(lat: float, lon: float, airfield_id: String) -> void:
	# You cannot start a sortie from an enemy airfield: fall back to an air start over that point.
	var friendly: bool = airfield_id == "" or _is_friendly_field(airfield_id)
	if not friendly:
		airfield_id = ""
	_sel = {"lat": lat, "lon": lon, "airfield": airfield_id}
	var rw: bool = airfield_id != ""
	_start_type.set_item_disabled(0, not rw)
	if rw:
		for a in _airfields:
			if str(a["id"]) == airfield_id:
				_hdg.value = float(a.get("heading_deg", 90))
	else:
		_start_type.select(1)
	_fly.disabled = false
	_refresh()
	if not friendly:
		_info.text = "Enemy airfield - you cannot take off from here. Airborne start instead."


func _date() -> String:
	return MoonWeather.date_at_offset(int(_date_slider.value))


## Moon for the chosen date and the forecast for this route (same date + route = same weather every time).
func _refresh_env() -> void:
	var date: String = _date()
	var lat: float = float(_sel["lat"]) if not _sel.is_empty() else 51.1
	var lon: float = float(_sel["lon"]) if not _sel.is_empty() else 1.3
	var illum: float = MoonWeather.illumination(date)
	_date_label.text = "Date: %s   Moon: %s, %d%% lit" % [date, MoonWeather.moon_name(date), int(round(illum * 100.0))]
	_forecast = MoonWeather.forecast(date, lat, lon) if weather_choice == "" else weather_choice
	var pen: float = MoonWeather.nav_penalty(_forecast)
	var nav_note: String = "Clear: full map detail."
	if pen >= 0.5:
		nav_note = "Navigation very hard: map detail cut back. Hold the coast and rivers, allow for drift."
	elif pen >= 0.25:
		nav_note = "Navigation harder: map detail reduced. Allow for drift."
	elif pen > 0.0:
		nav_note = "Haze: map detail slightly reduced."
	var moon_note: String = "Moon partly lit."
	if illum >= 0.6:
		moon_note = "Bright moon: bombers easier to spot for searchlights and night fighters."
	elif illum < 0.25:
		moon_note = "Dark moon: bombers harder to spot at night."
	_env_label.text = "%s: %s. %s\n%s" % ["Forecast for the day" if weather_choice == "" else "Weather (set in Conditions)", _forecast.capitalize(), nav_note, moon_note]


func _is_runway() -> bool:
	return str(_sel.get("airfield", "")) != "" and _start_type.selected == 0


func _refresh() -> void:
	_refresh_env()
	if _sel.is_empty():
		return
	var af_id: String = str(_sel.get("airfield", ""))
	var label: String = "Air spawn at %.2f N, %.2f E" % [float(_sel["lat"]), float(_sel["lon"])]
	for a in _airfields:
		if str(a["id"]) == af_id:
			label = SpawnPoints.label_for(str(a["name"]), "Allies" if str(a["side"]) == "RAF" else "Axis")
	_info.text = label
	var rw: bool = _is_runway()
	_alt.editable = not rw
	_hdg.editable = not rw
	_alt_label.text = "Altitude: %d m" % int(_alt.value) + ("  (runway start)" if rw else "")
	_hdg_label.text = "Heading: %03d" % int(_hdg.value) + ("  (runway)" if rw else "")
	_map.sel = _sel
	_map.heading = float(_hdg.value)
	_map.queue_redraw()
	var plan: Dictionary = _targets_for(SCENARIOS[_scenario.selected][0])
	var ids: Array = plan.get("targets", [])
	if ids.is_empty():
		_target_info.text = ""
	else:
		var names: Array = []
		for t in _targets:
			if str(t["id"]) in ids:
				names.append("%s (%d km)" % [str(t["name"]), int(_km(float(t["lat"]), float(t["lon"])))])
		_target_info.text = "Objective: " + ", ".join(names)


func _km(lat: float, lon: float) -> float:
	var dx: float = (lon - float(_sel["lon"])) * 71.0
	var dy: float = (lat - float(_sel["lat"])) * 111.0
	return sqrt(dx * dx + dy * dy)


## Nearest enemy targets of a fitting kind for the chosen scenario.
func _targets_for(scn: String) -> Dictionary:
	var out: Dictionary = {"targets": []}
	if _sel.is_empty() or scn in ["free", "sweep"]:
		return out
	var enemy_owner: String = "Axis" if side == "Allies" else "Allies"
	var pool: Array = []
	for t in _targets:
		if str(t["side_owner"]) != enemy_owner:
			continue
		var typ: String = str(t["type"])
		match scn:
			"bombing", "escort":
				if typ in BOMB_TYPES:
					pool.append(t)
			"ground":
				if typ in ["convoy_route", "battery", "rail_yard"] and not bool(t.get("naval", false)):
					pool.append(t)
			"ships":
				if typ == "convoy_route" and bool(t.get("naval", false)):
					pool.append(t)
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _km(float(a["lat"]), float(a["lon"])) < _km(float(b["lat"]), float(b["lon"])))
	if pool.is_empty():
		return out
	var first: Dictionary = pool[0]
	var ids: Array = [str(first["id"])]
	for t2 in pool:
		if t2 != first and ids.size() < 3 and absf(float(t2["lat"]) - float(first["lat"])) < 0.08 and absf(float(t2["lon"]) - float(first["lon"])) < 0.12:
			ids.append(str(t2["id"]))
	out["targets"] = ids
	return out


func _on_fly() -> void:
	if _sel.is_empty():
		return
	var scn: String = SCENARIOS[_scenario.selected][0]
	var level: float = float(ENEMY[_enemy.selected][1])
	var none: bool = _enemy.selected == 0
	var plan: Dictionary = {
		"spawn_lat": float(_sel["lat"]), "spawn_lon": float(_sel["lon"]), "spawn_airfield": str(_sel.get("airfield", "")),
		"spawn_airborne": not _is_runway(), "spawn_alt": float(_alt.value), "spawn_heading": float(_hdg.value),
		"scenario": scn, "wingmen": _wingmen.selected, "difficulty": level, "no_fighters": none and scn != "sweep", "ambient": not none and scn == "free",
		"mode": {"free": "free", "bombing": "bombing", "ground": "ground", "ships": "ground", "escort": "escort", "sweep": "dogfight"}[scn],
	}
	plan["weather"] = _forecast
	plan["mission_date"] = _date()
	var t: Dictionary = _targets_for(scn)
	if not (t["targets"] as Array).is_empty():
		plan["targets"] = t["targets"]
	confirmed.emit(plan)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		cancelled.emit()
		get_viewport().set_input_as_handled()
