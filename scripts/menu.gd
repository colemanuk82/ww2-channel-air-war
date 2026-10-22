class_name StartMenu
extends CanvasLayer
## Start menu. Side, aircraft, mode, start point, mission and conditions sit on their own pages (SORTIE /
## START POINT / CONDITIONS / BRIEFING) switched by the visible button row, so nothing has to be scrolled to.
## Emits start_requested(config) with keys: side, aircraft, mode, difficulty (0..1), weather, time, ambient.

signal start_requested(config: Dictionary)
signal quit_requested

const DIFFICULTIES := {"Easy": 0.2, "Normal": 0.5, "Hard": 0.85}
const TIMES := ["dawn", "noon", "dusk", "night"]
const PAGES := ["SORTIE", "START POINT", "CONDITIONS", "BRIEFING"]

const DONATE_URL := "https://paypal.me/colemanuk82"

var _side: OptionButton
var _aircraft: OptionButton
var _mode: OptionButton
var _mission: OptionButton
var _mission_row: Control
var _diff: OptionButton
var _weather: OptionButton
var _time: OptionButton
var _spawn: OptionButton
var _spawn_row: Control
var _spawn_note: Label
var _desc: Label
var _info: Label
var _plan: Dictionary = {}      # result of the map planner (free flight)
var _plan_label: Label
var _plan_btn: Button
var _plan_hint: Label
var _ambient: CheckBox
var _taskings: CheckBox
var _ids: Array = []
var _mode_ids: Array = []
var _mission_ids: Array = []
var _mission_kind: String = "historical"
var _weather_names: Array = []
var _page_host: VBoxContainer
var _pages: Array = []
var _nav_btns: Array = []


func _ready() -> void:
	layer = 20
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := MenuBackground.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	add_child(MenuMusic.new())      # random menu tracks; stops when the menu closes (loading starts)
	# dark gradient on the left (behind the briefing column) and a light vignette, so the painting
	# stays visible on the right
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void fragment() {
	float left = 1.0 - smoothstep(0.30, 0.62, UV.x);
	float bottom = smoothstep(0.78, 1.0, UV.y) * 0.55;
	float top = (1.0 - smoothstep(0.0, 0.12, UV.y)) * 0.35;
	vec2 d = UV - vec2(0.62, 0.5);
	float vig = smoothstep(0.45, 0.95, length(d * vec2(1.2, 1.0))) * 0.45;
	COLOR = vec4(0.025, 0.025, 0.02, clamp(left * 0.86 + bottom + top + vig, 0.0, 0.94));
}"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	shade.material = sm
	root.add_child(shade)

	var col := MarginContainer.new()
	col.anchor_left = 0.0
	col.anchor_right = 0.0
	col.anchor_top = 0.0
	col.anchor_bottom = 1.0
	col.offset_right = 640.0
	for k in ["margin_left", "margin_right"]:
		col.add_theme_constant_override(k, 56)
	col.add_theme_constant_override("margin_top", 28)
	col.add_theme_constant_override("margin_bottom", 22)
	root.add_child(col)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	col.add_child(outer)
	var kicker := UIKit.label("1940  ·  1944", 16, UIKit.RED, true)
	outer.add_child(kicker)
	var title := UIKit.label("CHANNEL AIR WAR", 48, UIKit.TEXT, true)
	title.add_theme_constant_override("outline_size", 6)
	outer.add_child(title)
	var sub := UIKit.label("Kent, the Channel and the coast of France", 16, UIKit.ACCENT)
	outer.add_child(sub)
	outer.add_child(UIKit.rule(0.8))

	# page navigation: one button per screen, so every option is reachable without scrolling
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 8)
	outer.add_child(nav)
	for i in PAGES.size():
		var b: Button = UIKit.button(String(PAGES[i]), func() -> void: _show_page(i), 15)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav.add_child(b)
		_nav_btns.append(b)
	outer.add_child(UIKit.rule(0.35))

	_page_host = VBoxContainer.new()
	_page_host.add_theme_constant_override("separation", 8)
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_page_host)

	# --- SORTIE ---
	var sortie := _new_page()
	_page_host.add_child(sortie)
	sortie.add_child(UIKit.label("SORTIE", 14, UIKit.TEXT_DIM, true))
	_side = UIKit.option_row(sortie, "Side", ["Allies", "Axis"], 20)
	_aircraft = UIKit.option_row(sortie, "Aircraft", [], 20)
	_info = UIKit.label("", 15, UIKit.TEXT_DIM)
	sortie.add_child(_info)
	_mode_ids = ModeRegistry.get_available_ids()
	var mode_names: Array = []
	for id in _mode_ids:
		mode_names.append(ModeRegistry.display_name(id))
	_mode = UIKit.option_row(sortie, "Mode", mode_names, 20)
	var mission_names: Array = []
	for m in HistoricalMissions.list():
		_mission_ids.append(str(m.get("id", "")))
		mission_names.append(GameState.mission_label(str(m.get("id", "")), str(m.get("name", m.get("id", "")))))
	if mission_names.is_empty():
		mission_names = ["(none)"]
	_mission = UIKit.option_row(sortie, "Mission", mission_names, 20)
	_mission.get_popup().about_to_popup.connect(_open_mission_list)    # custom list so completed missions can be coloured
	_mission.item_selected.connect(func(_i: int) -> void: _tint_mission())
	_mission_row = _mission.get_parent()
	_tint_mission()

	# --- START POINT (free flight) ---
	var startpage := _new_page()
	_page_host.add_child(startpage)
	startpage.add_child(UIKit.label("START POINT", 14, UIKit.TEXT_DIM, true))
	_spawn_note = UIKit.label("The mission sets your airfield, altitude and heading.", 16, UIKit.TEXT_DIM)
	startpage.add_child(_spawn_note)
	_spawn = UIKit.option_row(startpage, "Spawn", SpawnPoints.names(), 20)
	_spawn_row = _spawn.get_parent()
	_plan_btn = UIKit.button("MAP - pick your start point / sortie", _open_planner, 20, true)
	startpage.add_child(_plan_btn)
	# Make it obvious that free flight is chosen on the map, not just from the Spawn list.
	_plan_hint = UIKit.label("Opens the theatre map: click an airfield to start on its runway or in the air over it, or click open ground to start airborne there. Pick the scenario and enemy strength on the same screen.", 13, UIKit.TEXT_DIM)
	_plan_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plan_hint.custom_minimum_size = Vector2(500, 0)
	startpage.add_child(_plan_hint)
	_plan_label = UIKit.label("", 15, UIKit.ACCENT)
	_plan_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	startpage.add_child(_plan_label)
	_ambient = CheckBox.new()
	_ambient.text = "Ambient air war (bomber raids, escorts, dogfights)"
	_ambient.button_pressed = true
	_ambient.add_theme_font_override("font", UIKit.font())
	_ambient.add_theme_font_size_override("font_size", 17)
	_ambient.add_theme_color_override("font_color", UIKit.TEXT)
	_ambient.add_theme_color_override("font_hover_color", Color.WHITE)
	_ambient.add_theme_color_override("font_focus_color", Color.WHITE)
	startpage.add_child(_ambient)
	# dynamic free flight: the Ops Room radios a new target every 10 minutes, with a waypoint (OpsRoom)
	_taskings = CheckBox.new()
	_taskings.text = "Ops Room taskings (a new target on the radio every 10 minutes)"
	_taskings.button_pressed = true
	_taskings.add_theme_font_override("font", UIKit.font())
	_taskings.add_theme_font_size_override("font_size", 17)
	_taskings.add_theme_color_override("font_color", UIKit.TEXT)
	_taskings.add_theme_color_override("font_hover_color", Color.WHITE)
	_taskings.add_theme_color_override("font_focus_color", Color.WHITE)
	startpage.add_child(_taskings)

	# --- CONDITIONS ---
	var cond := _new_page()
	_page_host.add_child(cond)
	cond.add_child(UIKit.label("CONDITIONS", 14, UIKit.TEXT_DIM, true))
	_diff = UIKit.option_row(cond, "Difficulty", DIFFICULTIES.keys(), 20)
	_diff.select(1)
	_weather_names = WeatherManager.get_weather_names()
	var wn: Array = []
	for w in _weather_names:
		wn.append(String(w).capitalize())
	_weather = UIKit.option_row(cond, "Weather", wn, 20)
	var tn: Array = []
	for t in TIMES:
		tn.append(String(t).capitalize())
	_time = UIKit.option_row(cond, "Time of day", tn, 20)
	_time.select(1)

	# --- BRIEFING ---
	var brief := _new_page()
	_page_host.add_child(brief)
	brief.add_child(UIKit.label("BRIEFING", 14, UIKit.TEXT_DIM, true))
	_desc = UIKit.label("", 15, Color(0.88, 0.86, 0.78))
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_font_override("font", UIKit.body_font())
	_desc.custom_minimum_size = Vector2(500, 0)
	brief.add_child(_desc)

	outer.add_child(UIKit.rule(0.5))
	var start := UIKit.button("TAKE OFF", _on_start, 30, true)
	start.custom_minimum_size = Vector2(0, 56)
	outer.add_child(start)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	outer.add_child(row)
	var cb := UIKit.button("Campaign", _open_campaign, 20)
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cb)
	var pl := UIKit.button("Pilot's Life", _open_career, 20)
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pl)
	var db := UIKit.button("Dam Busters", _open_dam_busters, 20)
	db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(db)
	var lb := UIKit.button("Logbook", _open_logbook, 20)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lb)
	var ob := UIKit.button("Options", func() -> void: add_child(SettingsMenu.new()), 20)
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ob)
	var crb := UIKit.button("Credits", _open_legal, 20)
	crb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(crb)
	var qb := UIKit.button("Quit", func() -> void: quit_requested.emit(), 20)
	qb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(qb)

	var hint := UIKit.label("Keyboard: W/S pitch  A/D roll  Q/E yaw  Shift/Ctrl throttle  Space fire  B weapon  Esc pause\nGamepad: left stick fly  right stick look  triggers throttle  A fire  B weapon", 14, Color(0.85, 0.83, 0.75))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_right = -36.0
	hint.offset_bottom = -26.0
	root.add_child(hint)
	# release version (project.godot application/config/version), small and quiet in the top-right corner
	var ver := UIKit.label("v%s" % str(ProjectSettings.get_setting("application/config/version", "dev")), 14, Color(0.85, 0.83, 0.75, 0.55))
	ver.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.offset_right = -22.0
	ver.offset_top = 14.0
	root.add_child(ver)
	# voluntary donation link, top-right under the version label (opens the player's browser; nothing is sent by the game)
	var sup := UIKit.button("Support me on PayPal", func() -> void: OS.shell_open(DONATE_URL), 15)
	sup.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sup.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	sup.offset_right = -22.0
	sup.offset_top = 40.0
	sup.tooltip_text = "Optional. Opens " + DONATE_URL + " in your web browser."
	root.add_child(sup)
	if FirstRun.pending():
		_welcome_when_clear(root)

	_side.item_selected.connect(func(_i: int) -> void: _refresh_aircraft())
	_side.item_selected.connect(func(_i: int) -> void: _refresh_mode())
	_aircraft.item_selected.connect(func(_i: int) -> void: _refresh_info())
	_mode.item_selected.connect(func(_i: int) -> void:
		_refresh_mode()
		_apply_mission_defaults())
	_mission.item_selected.connect(func(_i: int) -> void:
		_apply_mission_defaults()
		_refresh_mode())
	_refresh_aircraft()
	_refresh_mode()
	_show_page(_initial_page())
	start.grab_focus()
	if not NewsreelCard.shown_this_launch:
		var news: Array = NewsreelCard.headline_from_log()      # the player's own news leads the reel when there is any
		if news.is_empty():
			news = ["THE CHANNEL HOLDS", "Weekly Review, item one: the coastal fighter stations stand by through the night. Original commentary, no archive footage."]
		NewsreelCard.play_once(self, String(news[0]), String(news[1]))
	# decorations not yet presented (earned in a sortie that ended in a hurry) are shown once the card has gone
	get_tree().create_timer(5.5).timeout.connect(func() -> void:
		if is_inside_tree() and not MedalCeremony.show_pending(self, "Allies"):
			MedalCeremony.show_pending(self, "Axis"))
	if Engine.has_meta("open_campaign"):      # returning from a campaign sortie
		Engine.remove_meta("open_campaign")
		_open_campaign.call_deferred()
	if Engine.has_meta("open_career"):        # returning from a Pilot's Life sortie
		Engine.remove_meta("open_career")
		_open_career.call_deferred()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--medal-shot="):   # debug: screenshot the start-up newsreel (1.5 s) and the medal ceremony (8 s)
			var mshot: String = arg.substr(13)
			get_tree().create_timer(1.5).timeout.connect(func() -> void:
				get_viewport().get_texture().get_image().save_png(mshot.replace(".png", "_news.png")))
			get_tree().create_timer(8.0).timeout.connect(func() -> void:
				get_viewport().get_texture().get_image().save_png(mshot)
				get_tree().quit())
		if arg.begins_with("--dam-shot="):   # debug: open the Dam Busters screen from the menu, save a screenshot, quit
			var dshot: String = arg.substr(11)
			get_tree().create_timer(12.0).timeout.connect(_open_dam_busters)
			get_tree().create_timer(14.0).timeout.connect(func() -> void:
				get_viewport().get_texture().get_image().save_png(dshot)
				get_tree().quit())
		if arg.begins_with("--missions-shot="):   # debug: pretend 3 missions are done, open the Mission list, save a screenshot, quit
			var ms_path: String = arg.substr(16)
			for k in range(1, 4):
				GameState.completed_missions.append(str(_mission_ids[k]))
			_tint_mission()
			_mission.select(2)
			_tint_mission()
			get_tree().create_timer(6.0).timeout.connect(_show_mission_list)
			get_tree().create_timer(8.0).timeout.connect(func() -> void:
				get_viewport().get_window().get_viewport().get_texture().get_image().save_png(ms_path)
				get_tree().quit())
		if arg.begins_with("--logbook-shot="):   # debug: open the logbook from the menu, save a screenshot, quit
			var shot_path: String = arg.substr(15)
			get_tree().create_timer(12.0).timeout.connect(_open_logbook)
			get_tree().create_timer(14.0).timeout.connect(func() -> void:
				get_viewport().get_texture().get_image().save_png(shot_path)
				get_tree().quit())


func _new_page() -> VBoxContainer:
	var p := VBoxContainer.new()
	p.add_theme_constant_override("separation", 8)
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return p


## The first page to show: WW2_MENU_PAGE=SORTIE|START POINT|CONDITIONS|BRIEFING (for screenshots), else SORTIE.
func _initial_page() -> int:
	for i in PAGES.size():
		_pages.append(_page_host.get_child(i))
	var want: String = OS.get_environment("WW2_MENU_PAGE").to_upper()
	var idx: int = PAGES.find(want)
	return idx if idx >= 0 else 0


func _show_page(index: int) -> void:
	if index < 0 or index >= _pages.size():
		return
	for i in _pages.size():
		(_pages[i] as Control).visible = i == index
	for i in _nav_btns.size():
		(_nav_btns[i] as Button).button_pressed = i == index


func _refresh_aircraft() -> void:
	var side: String = _side.get_item_text(_side.selected)
	_ids = AircraftCatalog.ids_for_side(side)
	_aircraft.clear()
	for id in _ids:
		var st: AircraftStats = AircraftCatalog.load_stats(id)
		_aircraft.add_item(st.display_name + (" (bomber)" if AircraftCatalog.is_bomber(id) else ""))
	_aircraft.select(0)
	_refresh_info()


func _refresh_info() -> void:
	if _aircraft.selected < 0 or _aircraft.selected >= _ids.size():
		return
	var st: AircraftStats = AircraftCatalog.load_stats(_ids[_aircraft.selected])
	_info.text = "Speed %d km/h   Hull %d   Bombs %d" % [int(st.max_speed * 3.6), int(st.max_health), st.bombs]


## The Mission list holds historical missions or training lessons depending on the mode.
func _fill_missions(mode_id: String) -> void:
	var want: String = "training" if mode_id == "training" else ("dambuster" if mode_id == "dambuster" else "historical")
	if want == _mission_kind:
		return
	_mission_kind = want
	_mission.clear()
	_mission_ids.clear()
	if want == "dambuster":
		for i in DamCampaign.count():
			_mission_ids.append(str(i))
			var tag: String = "" if (DamCampaign.is_passed(i) or DamCampaign.is_open(i)) else "  (locked)"
			_mission.add_item(str(DamCampaign.DAYS[i]["title"]) + tag)
	elif want == "training":
		for l in TrainingMode.LESSONS:
			_mission_ids.append(String(l["id"]))
			_mission.add_item(String(l["name"]))
	else:
		for m in HistoricalMissions.list():
			_mission_ids.append(str(m.get("id", "")))
			_mission.add_item(GameState.mission_label(str(m.get("id", "")), str(m.get("name", m.get("id", "")))))
		if _mission_ids.is_empty():
			_mission.add_item("(none)")
	_mission.select(0)
	_tint_mission()


const DONE_GREEN := Color(0.45, 0.85, 0.45)


## True when the entry at list index i is completed: a historical mission flown, or a Dam Busters day passed.
func _mission_done_at(i: int) -> bool:
	if i < 0 or i >= _mission_ids.size():
		return false
	if _mission_kind == "dambuster":
		return DamCampaign.is_passed(int(_mission_ids[i]))
	return _mission_kind == "historical" and GameState.is_mission_done(str(_mission_ids[i]))


## Dam Busters days that are still locked are greyed out.
func _mission_locked_at(i: int) -> bool:
	return _mission_kind == "dambuster" and i >= 0 and i < _mission_ids.size() and not DamCampaign.is_open(int(_mission_ids[i]))


## The closed Mission box shows the chosen mission in green once it has been completed.
func _tint_mission() -> void:
	if _mission_done_at(_mission.selected):
		_mission.add_theme_color_override("font_color", DONE_GREEN)
		_mission.add_theme_color_override("font_hover_color", DONE_GREEN)
		_mission.add_theme_color_override("font_focus_color", DONE_GREEN)
	else:
		_mission.remove_theme_color_override("font_color")
		_mission.remove_theme_color_override("font_hover_color")
		_mission.remove_theme_color_override("font_focus_color")


## Replaces the Mission drop-down's plain popup (it cannot colour single rows) with a list that shows completed
## missions in green.
func _open_mission_list() -> void:
	_mission.get_popup().hide.call_deferred()
	_show_mission_list.call_deferred()


func _show_mission_list() -> void:
	var pp := PopupPanel.new()
	pp.add_theme_stylebox_override("panel", UIKit.panel_style())
	var il := ItemList.new()
	il.auto_height = false
	il.add_theme_font_override("font", UIKit.body_font())
	il.add_theme_font_size_override("font_size", 18)
	il.add_theme_color_override("font_color", UIKit.TEXT)
	il.add_theme_color_override("font_selected_color", UIKit.ACCENT_HOT)
	il.add_theme_color_override("font_hovered_color", UIKit.ACCENT_HOT)
	il.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(0.93, 0.74, 0.32, 0.18)
	il.add_theme_stylebox_override("selected", sel)
	il.add_theme_stylebox_override("selected_focus", sel)
	for i in _mission.item_count:
		il.add_item(_mission.get_item_text(i))
		if _mission_done_at(i):
			il.set_item_custom_fg_color(i, DONE_GREEN)
		elif _mission_locked_at(i):
			il.set_item_custom_fg_color(i, UIKit.TEXT_DIM)
	if _mission.selected >= 0:
		il.select(_mission.selected)
	il.item_selected.connect(func(i: int) -> void:
		_mission.select(i)
		_mission.item_selected.emit(i)
		pp.queue_free())
	pp.popup_hide.connect(func() -> void: pp.queue_free())
	var w: int = maxi(int(_mission.size.x), 360)
	var h: int = mini(_mission.item_count * 32 + 16, 420)
	il.custom_minimum_size = Vector2(w - 16, h - 16)
	pp.add_child(il)
	add_child(pp)
	pp.popup(Rect2i(Vector2i(_mission.get_screen_position()) + Vector2i(0, int(_mission.size.y)), Vector2i(w, h)))
	if _mission.selected >= 0:
		il.ensure_current_is_visible()


## Picking a historical mission sets the side and aircraft the mission was written for (you can still change the aircraft).
func _apply_mission_defaults() -> void:
	if _mode_ids.is_empty() or str(_mode_ids[_mode.selected]) != "historical" or _mission.selected < 0 or _mission.selected >= _mission_ids.size():
		return
	var m: Dictionary = HistoricalMissions.get_mission(str(_mission_ids[_mission.selected]))
	var sides: Array = m.get("sides", [])
	if sides.is_empty():
		return
	var cur: String = _side.get_item_text(_side.selected)
	var mine: Dictionary = {}
	for sd in sides:
		if str(sd["side"]) == cur:
			mine = sd
	if mine.is_empty():          # the mission is only playable from the other side: switch to it
		mine = sides[0]
		_side.select(0 if str(mine["side"]) == "Allies" else 1)
		_refresh_aircraft()
	for aid in mine.get("aircraft", []):
		var i: int = _ids.find(str(aid))
		if i >= 0:
			_aircraft.select(i)
			_refresh_info()
			break


func _refresh_mode() -> void:
	if _mode_ids.is_empty():
		return
	var id: String = _mode_ids[_mode.selected]
	var free: bool = id == "free"
	_ambient.visible = free
	_taskings.visible = free
	_spawn_row.visible = free
	_plan_btn.visible = free
	_plan_label.visible = free
	_plan_hint.visible = free
	_spawn_note.visible = not free
	_mission_row.visible = id == "historical" or id == "training" or id == "dambuster"
	_fill_missions(id)
	if id == "dambuster":
		_desc.text = str(DamCampaign.DAYS[clampi(maxi(_mission.selected, 0), 0, DamCampaign.count() - 1)]["brief"]) + DamCampaign.STEER_NOTE
	elif id == "training":
		_desc.text = TrainingMode.brief_for(_mission_ids[_mission.selected]) if _mission.selected >= 0 and _mission.selected < _mission_ids.size() else ""
	elif id == "historical" and not _mission_ids.is_empty():
		var side: String = _side.get_item_text(_side.selected)
		var brief: String = HistoricalMissions.briefing_for(_mission_ids[_mission.selected], side)
		_desc.text = brief if brief != "" else ModeRegistry.description(id)
	else:
		_desc.text = ModeRegistry.description(id)


func _open_campaign() -> void:
	var cm := CampaignMenu.new()
	cm.closed.connect(func() -> void: cm.queue_free())
	cm.start_requested.connect(func(cfg: Dictionary) -> void:
		cm.queue_free()
		start_requested.emit(cfg))
	add_child(cm)


func _open_career() -> void:
	var pm := CareerMenu.new()
	pm.closed.connect(func() -> void: pm.queue_free())
	pm.start_requested.connect(func(cfg: Dictionary) -> void:
		pm.queue_free()
		start_requested.emit(cfg))
	add_child(pm)


func _open_logbook() -> void:
	# Its own layer above the start menu (like Options, layer 40). It used to sit on a layer with the same number
	# as the menu and was drawn behind it, so the button seemed to do nothing.
	var layer := CanvasLayer.new()
	layer.layer = 45
	add_child(layer)
	var lm := LogbookMenu.new()
	lm.closed.connect(func() -> void: layer.queue_free())
	layer.add_child(lm)

func _open_legal() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 45
	add_child(layer)
	var lm := LegalMenu.new()
	lm.closed.connect(func() -> void: layer.queue_free())
	layer.add_child(lm)


func _open_dam_busters() -> void:
	# Its own layer above the start menu, like the logbook: added straight into the menu it was drawn behind it
	# and the button seemed to do nothing.
	var layer := CanvasLayer.new()
	layer.layer = 45
	add_child(layer)
	var dm := DamCampaignMenu.new()
	dm.closed.connect(func() -> void: layer.queue_free())
	dm.start_requested.connect(func(cfg: Dictionary) -> void:
		layer.queue_free()
		start_requested.emit(cfg))
	layer.add_child(dm)


func _open_planner() -> void:
	var fp := FlightPlanner.new()
	fp.side = _side.get_item_text(_side.selected)
	fp.cancelled.connect(func() -> void: fp.queue_free())
	fp.confirmed.connect(func(plan: Dictionary) -> void:
		_plan = plan
		fp.queue_free()
		_plan_label.text = "Planned: %s, %s" % [String(plan["scenario"]).capitalize(), "runway" if not bool(plan["spawn_airborne"]) else "airborne"]
		_on_start())
	add_child(fp)


## First launch only: offer the training flight before the player is dropped into a full mission menu.
func _welcome_when_clear(root: Control) -> void:
	# let the opening newsreel card finish first so the two do not overlap
	await get_tree().process_frame
	while is_inside_tree():
		var busy: bool = false
		for c in get_children():
			if c is NewsreelCard:
				busy = true
		if not busy:
			break
		await get_tree().create_timer(0.3).timeout
	if is_inside_tree():
		_show_welcome(root)


func _show_welcome(root: Control) -> void:
	var dim: Control = UIKit.dimmer(0.7)
	root.add_child(dim)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.panel_style())
	card.custom_minimum_size = Vector2(660, 0)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	dim.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)
	box.add_child(UIKit.label("WELCOME, PILOT", 34, UIKit.TEXT, true))
	var body := UIKit.label("New to WW2 Channel Air War? The training flight takes about five minutes and walks you through the controls: taking off, turning, firing and landing. You can run it any time from Mode > Training.\n\nPrefer to jump straight in? Pick a mission from the menu. It's completely free, so have fun.", 18, UIKit.TEXT_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	row.add_child(UIKit.button("Start the training flight", func() -> void:
		FirstRun.mark_offered()
		dim.queue_free()
		var ti: int = _mode_ids.find("training")
		if ti >= 0:
			_mode.select(ti)
			_refresh_mode()
			if _mission.item_count > 0:
				_mission.select(0)
			_on_start(), 22, true))
	row.add_child(UIKit.button("Skip, take me to the menu", func() -> void:
		FirstRun.mark_offered()
		dim.queue_free(), 20))


func _on_start() -> void:
	var mode_id: String = _mode_ids[_mode.selected] if not _mode_ids.is_empty() else "free"
	if mode_id == "dambuster":
		var di: int = clampi(maxi(_mission.selected, 0), 0, DamCampaign.count() - 1)
		if DamCampaign.is_open(di):
			start_requested.emit(DamCampaign.config_for(di))
		else:
			_desc.text = "Locked. Pass the previous day first."
		return
	if mode_id == "historical":
		_apply_mission_defaults()      # never start a mission from a side it has no briefing for
		var hid: String = str(_mission_ids[_mission.selected]) if _mission.selected >= 0 and _mission.selected < _mission_ids.size() else ""
		if hid != "" and not DatedOps.is_open(hid):
			_desc.text = "Locked. This operation opens on %s." % DatedOps.opens_text(hid)
			return
	var cfg: Dictionary = {
		"side": _side.get_item_text(_side.selected),
		"aircraft": _ids[_aircraft.selected],
		"mode": mode_id,
		"mission": _mission_ids[_mission.selected] if ((mode_id == "historical" or mode_id == "training") and not _mission_ids.is_empty()) else "",
		"difficulty": DIFFICULTIES[_diff.get_item_text(_diff.selected)],
		"weather": _weather_names[_weather.selected],
		"time": TIMES[_time.selected],
		"ambient": _ambient.button_pressed,
		"taskings": _taskings.button_pressed and mode_id == "free",
	}
	if mode_id == "free":
		cfg["spawn"] = String(SpawnPoints.LIST[_spawn.selected]["id"])
		if not _plan.is_empty():
			cfg.merge(_plan, true)      # map planner overrides spawn, scenario (mode), targets, enemy strength
	start_requested.emit(cfg)
