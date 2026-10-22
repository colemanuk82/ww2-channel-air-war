class_name SettingsMenu
extends CanvasLayer
## Options panel, opened from the start menu or the pause menu. Every option lives on its own page so that
## nothing has to be scrolled to: a visible tab row swaps between Video / Render / Audio / Music / Gameplay /
## Controls, and the Controls section has its own sub-row. Applies live and persists. Apply and Back are always
## on screen at the bottom.

signal closed

static var start_on_controls: bool = false      # debug / shortcut: open straight on the Controls page

const PAGES := ["video", "render", "audio", "music", "gameplay", "controls"]
const PAGE_LABELS := {"video": "VIDEO", "render": "RENDER", "audio": "AUDIO", "music": "MUSIC", "gameplay": "GAMEPLAY", "controls": "CONTROLS"}

## Controls pages are slices of BINDINGS (header row included). Keep these in step with the table below:
##   FLIGHT 0-11   WEAPONS+BOMBERS 12-21   CAMERA 22-28   RADIO+WORLD 29-37   SYSTEM 38-43
const CONTROL_PAGES := [
	["flight", "FLIGHT", 0, 12],
	["weapons", "WEAPONS", 12, 22],
	["camera", "CAMERA", 22, 29],
	["radio", "RADIO", 29, 38],
	["system", "SYSTEM", 38, 44],
]

const MUSIC_PER_PAGE := 12

var _root: Control
var _pages: Dictionary = {}
var _tab_btns: Dictionary = {}
var _page_host: VBoxContainer
var _status: Label
var _hint: Label

# Settings widgets that _refresh() re-reads after a quality preset changes several at once.
var _quality: OptionButton
var _outlines: OptionButton
var _shadows: OptionButton
var _msaa: OptionButton
var _post: OptionButton
var _view: OptionButton
var _clouds: OptionButton
var _fullscreen: OptionButton
var _ui_scale: OptionButton

# Controls page
var _ctl_pages: Dictionary = {}
var _ctl_btns: Dictionary = {}
var _binding_buttons: Dictionary = {}
var _listening_action: String = ""
var _diagram: ControllerDiagram
var _current_page: String = "video"
var _footer_hint: Label

# Music page
var _music_which: String = "menu"
var _music_which_btns: Dictionary = {}
var _music_names: GridContainer
var _music_now: Label
var _music_note: Label
var _music_page_label: Label
var _music_shuffle_btn: Button
var _music_tile_buttons: Dictionary = {}
var _music_selected: int = -1
var _music_page: int = 0
var _file_dialog: FileDialog


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_root = root
	root.add_child(UIKit.dimmer(0.82))
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 22)
	root.add_child(margin)
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 14)
	margin.add_child(panel)
	UIKit.heading(panel, "OPTIONS", 30)

	# Tab row, with LB / RB bumper chips at the ends (as on the console-style controls screen).
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 10)
	panel.add_child(tabs)
	tabs.add_child(_chip("LB"))
	for key in PAGES:
		var b: Button = UIKit.button(String(PAGE_LABELS[key]), func() -> void: _show_page(key), 16)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
		_tab_btns[key] = b
	tabs.add_child(_chip("RB"))
	panel.add_child(UIKit.rule())

	# Page area: each page sits on its own card and scrolls if it is taller than the screen.
	# HBox (not CenterContainer) so the page area fills the height left under the tabs.
	var centre := HBoxContainer.new()
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(centre)
	_page_host = VBoxContainer.new()
	_page_host.custom_minimum_size = Vector2(1000, 300)
	_page_host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre.add_child(_page_host)

	var builders := {
		"video": _build_video_page, "render": _build_render_page, "audio": _build_audio_page,
		"music": _build_music_page, "gameplay": _build_gameplay_page, "controls": _build_controls_page,
	}
	for key in PAGES:
		var content: VBoxContainer = builders[key].call()
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UIKit.panel_style())
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.visible = false
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.add_child(scroll)
		scroll.add_child(content)
		_page_host.add_child(card)
		_pages[key] = card

	_status = UIKit.label("", 14, UIKit.ACCENT)
	panel.add_child(_status)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	panel.add_child(bottom)
	_footer_hint = UIKit.label("LB / RB  switch page      B / Esc  back", 14, UIKit.TEXT_DIM)
	_footer_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(_footer_hint)
	var apply: Button = UIKit.button("Apply", _apply, 20, true)
	apply.custom_minimum_size = Vector2(170, 0)
	bottom.add_child(apply)
	var back: Button = UIKit.button("Back", _back, 20)
	back.custom_minimum_size = Vector2(170, 0)
	bottom.add_child(back)

	_music_select_manager("menu")

	var want: String = OS.get_environment("WW2_SETTINGS_PAGE")
	if start_on_controls:
		want = "controls"
	if not PAGES.has(want):
		want = "video"
	_show_page(want)


## Small rounded bumper chip (LB / RB) for the tab row.
func _chip(text: String) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.93, 0.9)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l: Label = UIKit.label(text, 13, Color(0.08, 0.08, 0.07), true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _apply() -> void:
	GameState.save_settings()
	GameState.settings_changed.emit()
	_status.text = "Settings applied and saved."


func _back() -> void:
	GameState.save_settings()
	closed.emit()
	queue_free()


func _show_page(key: String) -> void:
	if not _pages.has(key):
		return
	_current_page = key
	for k in _pages.keys():
		(_pages[k] as Control).visible = k == key
	for k in _tab_btns.keys():
		(_tab_btns[k] as Button).button_pressed = k == key
	_status.text = ""


func _new_page() -> VBoxContainer:
	var p := VBoxContainer.new()
	p.add_theme_constant_override("separation", 9)
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return p


# ---------------------------------------------------------------- Video

func _build_video_page() -> VBoxContainer:
	var page := _new_page()
	_quality = _row(page, "Quality", ["Low", "Medium", "High"], GameState.quality, func(i: int) -> void:
		GameState.apply_quality(i)
		_refresh())
	_outlines = _row(page, "Outlines", ["Off", "On"], 1 if GameState.outlines_enabled else 0, func(i: int) -> void:
		GameState.set_graphic("outlines", i == 1))
	_shadows = _row(page, "Shadows", ["Off", "On"], 1 if GameState.shadows_enabled else 0, func(i: int) -> void:
		GameState.set_graphic("shadows", i == 1))
	_msaa = _row(page, "Anti-aliasing", ["Off", "2x", "4x"], [0, 2, 4].find(GameState.msaa_level), func(i: int) -> void:
		GameState.set_graphic("msaa", [0, 2, 4][i]))
	_post = _row(page, "Post effects", ["Off", "Medium", "High"], GameState.post_fx, func(i: int) -> void:
		GameState.set_graphic("post_fx", i))
	_view = _row(page, "View distance", ["Near", "Normal", "Far"], GameState.view_distance, func(i: int) -> void:
		GameState.set_graphic("view_distance", i))
	_clouds = _row(page, "Cloud detail", ["Low", "Medium", "High"], GameState.cloud_detail, func(i: int) -> void:
		GameState.set_graphic("cloud_detail", i))
	_fullscreen = _row(page, "Fullscreen", ["Off", "On"], 1 if GameState.fullscreen else 0, func(i: int) -> void:
		GameState.set_graphic("fullscreen", i == 1))
	return page


# ---------------------------------------------------------------- Render / upscaling

func _build_render_page() -> VBoxContainer:
	var page := _new_page()
	var dlss_ok: bool = GameState.dlss_supported()
	var up_items: Array = ["Off", "FSR 2", "DLSS" if dlss_ok else "DLSS (not available)"]
	var cur_up: int = GameState.upscaler if GameState.upscaler >= 0 else (2 if dlss_ok else 0)
	_row(page, "Upscaling", up_items, cur_up, func(i: int) -> void:
		GameState.set_graphic("upscaler", i))
	_row(page, "Upscale quality", GameState.UPSCALE_NAMES, GameState.upscale_quality, func(i: int) -> void:
		GameState.set_graphic("upscale_quality", i))
	_row(page, "Frame generation", ["Off", "On" if GameState.framegen_supported() else "On (needs RTX 40+)"], 1 if GameState.frame_gen else 0, func(i: int) -> void:
		GameState.set_graphic("frame_gen", i == 1))
	_ui_scale = _row(page, "UI scale", ["85%", "100%", "125%", "150%"], _ui_index(), func(i: int) -> void:
		GameState.set_graphic("ui_scale", float(GameState.UI_SCALES[i])))
	return page


# ---------------------------------------------------------------- Audio

func _build_audio_page() -> VBoxContainer:
	var page := _new_page()
	_slider_row(page, "Master", AudioManager.master_volume, func(v: float) -> void: AudioManager.master_volume = v)
	_slider_row(page, "Effects", AudioManager.fx_volume, func(v: float) -> void: AudioManager.fx_volume = v)
	_slider_row(page, "Engine", AudioManager.engine_volume, func(v: float) -> void: AudioManager.engine_volume = v)
	_slider_row(page, "Radio", AudioManager.radio_volume, func(v: float) -> void: AudioManager.radio_volume = v)
	_slider_row(page, "Music", AudioManager.music_volume, func(v: float) -> void: AudioManager.music_volume = v)
	var note: Label = UIKit.label("Effects: guns, explosions, flak, bombs.  Radio: calls, briefings and static.  Music tracks: see the Music page.", 14, UIKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(note)
	return page


# ---------------------------------------------------------------- Gameplay

func _build_gameplay_page() -> VBoxContainer:
	var page := _new_page()
	_row(page, "Time passes", GameState.TIME_SPEED_NAMES, GameState.time_speed, func(i: int) -> void:
		GameState.set_graphic("time_speed", i))
	_row(page, "Player repairs", ["Off", "On"], 1 if GameState.player_heal else 0, func(i: int) -> void:
		GameState.set_graphic("player_heal", i == 1))
	_row(page, "Pitch ladder", ["Off", "On"], 1 if GameState.show_pitch_ladder else 0, func(i: int) -> void:
		GameState.set_graphic("pitch_ladder", i == 1))
	_row(page, "Control hints", ["Off", "On"], 1 if GameState.show_hints else 0, func(i: int) -> void:
		GameState.set_graphic("show_hints", i == 1))
	_row(page, "Radio subtitles", ["Off", "On"], 1 if GameState.radio_subtitles else 0, func(i: int) -> void:
		GameState.set_graphic("radio_subtitles", i == 1))
	_row(page, "Radio static", ["Off", "On"], 1 if GameState.radio_static else 0, func(i: int) -> void:
		GameState.set_graphic("radio_static", i == 1))
	_row(page, "Radio voice", ["Off", "On"], 1 if GameState.radio_voice else 0, func(i: int) -> void:
		GameState.radio_voice = i == 1)
	return page


# ---------------------------------------------------------------- Controls

func _build_controls_page() -> VBoxContainer:
	var page := _new_page()
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	_diagram = ControllerDiagram.new()
	_diagram.set_bindings(_diagram_map())
	page.add_child(_diagram)
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 8)
	page.add_child(nav)
	for spec in CONTROL_PAGES:
		var b: Button = UIKit.button(String(spec[1]), func() -> void: _show_ctl(String(spec[0])), 15)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav.add_child(b)
		_ctl_btns[String(spec[0])] = b
	_hint = UIKit.label("Gamepad: click a binding, then press a button. Esc cancels, Delete unbinds.", 13, UIKit.TEXT_DIM)
	page.add_child(_hint)
	var host := VBoxContainer.new()
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(host)
	for spec in CONTROL_PAGES:
		var sub: VBoxContainer = _build_controls_sub(int(spec[2]), int(spec[3]))
		sub.visible = false
		host.add_child(sub)
		_ctl_pages[String(spec[0])] = sub
	page.add_child(UIKit.button("Reset gamepad bindings", func() -> void: _reset_bindings(), 15))
	_show_ctl("flight")
	return page


## Which actions sit on each pad input, for the diagram. Keys match ControllerDiagram.ANCHORS.
func _diagram_map() -> Dictionary:
	var out: Dictionary = {}
	for row in BINDINGS:
		var name_s := String(row[0])
		var action := String(row[2])
		if action != "":
			for ev in InputMap.action_get_events(action):
				_add_pad_key(out, _event_key(ev), name_s)
		else:
			var txt := String(row[3]).to_lower()
			for pair in [["left stick", "LS"], ["right stick", "RS"], ["right trigger", "RT"], ["left trigger", "LT"], ["left shoulder", "LB"], ["right shoulder", "RB"], ["d-pad", "DPAD"]]:
				if txt.find(String(pair[0])) >= 0:
					_add_pad_key(out, String(pair[1]), name_s)
	return out


func _add_pad_key(out: Dictionary, key: String, name_s: String) -> void:
	if key == "":
		return
	if not out.has(key):
		out[key] = []
	var names: Array = out[key]
	if not names.has(name_s):
		names.append(name_s)


func _event_key(ev: InputEvent) -> String:
	if ev is InputEventJoypadButton:
		var bi: int = (ev as InputEventJoypadButton).button_index
		var btn_keys := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
			JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_BACK: "BACK",
			JOY_BUTTON_START: "START", JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS"}
		if btn_keys.has(bi):
			return String(btn_keys[bi])
		if bi >= JOY_BUTTON_DPAD_UP and bi <= JOY_BUTTON_DPAD_RIGHT:
			return "DPAD"
		return ""
	if ev is InputEventJoypadMotion:
		var ax: int = (ev as InputEventJoypadMotion).axis
		var ax_keys := {JOY_AXIS_LEFT_X: "LS", JOY_AXIS_LEFT_Y: "LS", JOY_AXIS_RIGHT_X: "RS", JOY_AXIS_RIGHT_Y: "RS",
			JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT"}
		return String(ax_keys.get(ax, ""))
	return ""


func _show_ctl(key: String) -> void:
	for k in _ctl_pages.keys():
		(_ctl_pages[k] as Control).visible = k == key
	for k in _ctl_btns.keys():
		(_ctl_btns[k] as Button).button_pressed = k == key


## One controls page: rows from_i..to_i of BINDINGS (the header row of the first section included).
func _build_controls_sub(from_i: int, to_i: int) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var gr := GridContainer.new()
	gr.columns = 3
	gr.add_theme_constant_override("h_separation", 20)
	gr.add_theme_constant_override("v_separation", 2)
	gr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(gr)
	gr.add_child(UIKit.label("Action", 14, UIKit.ACCENT))
	gr.add_child(UIKit.label("Keyboard", 14, UIKit.ACCENT))
	gr.add_child(UIKit.label("Gamepad", 14, UIKit.ACCENT))
	for i in range(from_i, mini(to_i, BINDINGS.size())):
		var row: Array = BINDINGS[i]
		var head: bool = String(row[1]) == "" and String(row[2]) == "" and String(row[3]) == ""
		var col: Color = UIKit.ACCENT if head else UIKit.TEXT
		var sz: int = 13 if head else 15
		var name_l: Label = UIKit.label(String(row[0]), sz, col)
		name_l.custom_minimum_size = Vector2(250, 0)
		gr.add_child(name_l)
		gr.add_child(UIKit.label(String(row[1]), sz, col if head else Color(0.8, 0.9, 1.0)))
		var action: String = String(row[2])
		if action != "":
			var b: Button = UIKit.button(_pad_label(action), func() -> void: _start_listening(action, _binding_buttons[action]), 14)
			b.custom_minimum_size = Vector2(150, 0)
			_binding_buttons[action] = b
			gr.add_child(b)
		else:
			gr.add_child(UIKit.label(String(row[3]), sz, col if head else Color(0.8, 0.9, 1.0)))
	return vb


# ---------------------------------------------------------------- Music managers

## Two independent managers (MENU MUSIC / IN-GAME MUSIC) wired to the real MenuMusic / GameMusic players.
## The track list is paged so it never needs scrolling; Import copies a file into user://music/, Delete removes
## it from the playlist (and from disk for imported copies only).
func _build_music_page() -> VBoxContainer:
	var page := _new_page()
	var which_row := HBoxContainer.new()
	which_row.alignment = BoxContainer.ALIGNMENT_CENTER
	which_row.add_theme_constant_override("separation", 10)
	page.add_child(which_row)
	for w in [["menu", "MENU MUSIC"], ["ingame", "IN-GAME MUSIC"]]:
		var b: Button = UIKit.button(String(w[1]), func() -> void: _music_select_manager(String(w[0])), 18)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		which_row.add_child(b)
		_music_which_btns[String(w[0])] = b

	_music_now = UIKit.label("", 16, UIKit.ACCENT)
	_music_now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_music_now)

	_music_names = GridContainer.new()
	_music_names.columns = 2
	_music_names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_music_names.add_theme_constant_override("h_separation", 8)
	_music_names.add_theme_constant_override("v_separation", 4)
	page.add_child(_music_names)

	var page_row := HBoxContainer.new()
	page_row.alignment = BoxContainer.ALIGNMENT_CENTER
	page_row.add_theme_constant_override("separation", 8)
	page.add_child(page_row)
	page_row.add_child(UIKit.button("<  Earlier", func() -> void: _music_flip_page(-1), 15))
	_music_page_label = UIKit.label("", 15, UIKit.TEXT_DIM)
	_music_page_label.custom_minimum_size = Vector2(150, 0)
	_music_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_row.add_child(_music_page_label)
	page_row.add_child(UIKit.button("Later  >", func() -> void: _music_flip_page(1), 15))

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	page.add_child(row1)
	for spec in [["Import...", _music_import], ["Delete", _music_delete], ["Play", _music_play]]:
		var b: Button = UIKit.button(String(spec[0]), spec[1], 17)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row1.add_child(b)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	page.add_child(row2)
	var prev: Button = UIKit.button("Previous", func() -> void: _music_step(-1), 17)
	prev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(prev)
	var nxt: Button = UIKit.button("Next", func() -> void: _music_step(1), 17)
	nxt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(nxt)
	_music_shuffle_btn = UIKit.button("Shuffle: On", func() -> void: _music_toggle_shuffle(), 17)
	_music_shuffle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_music_shuffle_btn)

	_music_note = UIKit.label("", 13, UIKit.TEXT_DIM)
	_music_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_music_note)

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.title = "Import a music track"
	_file_dialog.add_filter("*.mp3, *.ogg, *.wav", "Audio files")
	_file_dialog.use_native_dialog = false
	_file_dialog.size = Vector2i(760, 480)
	_file_dialog.file_selected.connect(_on_music_file_selected)
	_root.add_child(_file_dialog)
	return page


func _music_live() -> Node:
	return get_tree().get_first_node_in_group("menu_music" if _music_which == "menu" else "game_music")


func _track_title(path: String) -> String:
	return path.get_file().get_basename() if path != "" else ""


func _music_select_manager(which: String) -> void:
	_music_which = which
	_music_selected = -1
	_music_page = 0
	for k in _music_which_btns.keys():
		(_music_which_btns[k] as Button).button_pressed = k == which
	if _music_shuffle_btn != null:
		_music_shuffle_btn.text = "Shuffle: %s" % ("On" if GameState.music_shuffle(which) else "Off")
	if _music_note != null:
		_music_note.text = "Imports are copied into user://music/. Shipped tracks are never deleted from disk."
	_music_refresh()


func _music_refresh() -> void:
	var list: Array = GameState.music_playlist(_music_which)
	var pages: int = maxi(1, int(ceil(float(list.size()) / float(MUSIC_PER_PAGE))))
	_music_page = clampi(_music_page, 0, pages - 1)
	_music_selected = clampi(_music_selected, -1, list.size() - 1)
	_music_page_label.text = "Page %d / %d  -  %d track%s" % [_music_page + 1, pages, list.size(), "" if list.size() == 1 else "s"]
	var now_path: String = _music_now_path()
	_music_now.text = "Now playing: %s" % (_track_title(now_path) if now_path != "" else "(silent)")
	for c in _music_names.get_children():
		_music_names.remove_child(c)
		c.queue_free()
	_music_tile_buttons.clear()
	var start_i: int = _music_page * MUSIC_PER_PAGE
	for k in range(start_i, mini(start_i + MUSIC_PER_PAGE, list.size())):
		var path: String = String(list[k])
		var tag: String = "  [imported]" if MenuMusic.is_imported(path) else ""
		var b: Button = UIKit.button(_track_title(path) + tag, func() -> void: _music_select(k), 15)
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = k == _music_selected
		_music_names.add_child(b)
		_music_tile_buttons[k] = b


func _music_now_path() -> String:
	var p: Node = _music_live()
	if p != null and p.has_method("current_track"):
		var cur: String = String(p.call("current_track"))
		if cur != "":
			return cur
	return GameState.music_current(_music_which)


func _music_select(index: int) -> void:
	var list: Array = GameState.music_playlist(_music_which)
	if index < 0 or index >= list.size():
		return
	_music_selected = index
	for k in _music_tile_buttons.keys():
		(_music_tile_buttons[k] as Button).button_pressed = int(k) == index
	var path: String = String(list[index])
	if MenuMusic.is_imported(path):
		_music_note.text = "Selected %s (imported). Delete removes it from the playlist and the disk." % _track_title(path)
	else:
		_music_note.text = "Selected %s (ships with the game). Delete removes it from this playlist only." % _track_title(path)


func _music_flip_page(dir: int) -> void:
	_music_page += dir
	_music_refresh()


func _music_import() -> void:
	_file_dialog.popup_centered()


func _on_music_file_selected(path: String) -> void:
	var dst: String = MenuMusic.import_track(_music_which, path)
	if dst == "":
		_music_note.text = "Could not import that file (only mp3 / ogg / wav)."
		return
	GameState.add_music_track(_music_which, dst)
	var list: Array = GameState.music_playlist(_music_which)
	_music_selected = list.find(dst)
	_music_page = int(floor(float(maxi(_music_selected, 0)) / float(MUSIC_PER_PAGE)))
	_music_note.text = "Imported %s into %s." % [dst.get_file(), MenuMusic.user_dir(_music_which)]
	_music_sync_player(false)
	_music_refresh()


func _music_delete() -> void:
	var list: Array = GameState.music_playlist(_music_which)
	if _music_selected < 0 or _music_selected >= list.size():
		_music_note.text = "Select a track first."
		return
	var path: String = String(list[_music_selected])
	if MenuMusic.is_imported(path):
		MenuMusic.delete_track(path)
		_music_note.text = "Deleted %s." % path.get_file()
	else:
		_music_note.text = "%s ships with the game - removed from this playlist (file kept)." % path.get_file()
	GameState.remove_music_track(_music_which, path)
	_music_selected = -1
	_music_sync_player(false)
	_music_refresh()


func _music_play() -> void:
	var list: Array = GameState.music_playlist(_music_which)
	if _music_selected < 0 or _music_selected >= list.size():
		_music_note.text = "Select a track first."
		return
	var path: String = String(list[_music_selected])
	GameState.set_music_current(_music_which, path)
	_music_note.text = "Playing %s." % path.get_file()
	_music_sync_player(true)
	_music_refresh()


func _music_step(dir: int) -> void:
	var p: Node = _music_live()
	if p != null and p.has_method("next_track"):
		p.call("next_track", dir)
		_music_note.text = "Skipped %s." % ("forward" if dir > 0 else "back")
	else:
		_music_note.text = "No player running right now - the choice is saved for next time."
	_music_refresh()


func _music_toggle_shuffle() -> void:
	var on: bool = not GameState.music_shuffle(_music_which)
	GameState.set_music_shuffle(_music_which, on)
	_music_shuffle_btn.text = "Shuffle: %s" % ("On" if on else "Off")
	_music_sync_player(false)


## Push the current playlist / shuffle / selection at the live player. force_play restarts on the chosen track.
func _music_sync_player(force_play: bool) -> void:
	var p: Node = _music_live()
	if p == null:
		return
	if p.has_method("refresh_playlist"):
		p.call("refresh_playlist")
	if p.has_method("set_shuffle"):
		p.call("set_shuffle", GameState.music_shuffle(_music_which))
	if force_play and p.has_method("play_path"):
		var path: String = GameState.music_current(_music_which)
		if path != "":
			p.call("play_path", path)


# ---------------------------------------------------------------- shared widgets

func _ui_index() -> int:
	var best: int = 1
	var bd: float = 1e9
	for i in GameState.UI_SCALES.size():
		var d: float = absf(float(GameState.UI_SCALES[i]) - GameState.ui_scale)
		if d < bd:
			bd = d
			best = i
	return best


## Volume sliders (0-100 %), applied live and saved when the handle is released.
func _slider_row(page: VBoxContainer, caption: String, value: float, cb: Callable) -> HSlider:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	page.add_child(hb)
	var l: Label = UIKit.label(caption.to_upper(), 17, UIKit.TEXT_DIM, true)
	l.custom_minimum_size = Vector2(150, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 100.0
	sl.step = 5.0
	sl.value = roundf(value * 100.0)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size = Vector2(280, 28)
	hb.add_child(sl)
	var pct: Label = UIKit.label("%d%%" % int(sl.value), 17)
	pct.custom_minimum_size = Vector2(60, 0)
	hb.add_child(pct)
	sl.value_changed.connect(func(v: float) -> void:
		pct.text = "%d%%" % int(v)
		cb.call(v / 100.0))
	sl.drag_ended.connect(func(_changed: bool) -> void: GameState.save_settings())
	return sl


func _row(vb: VBoxContainer, caption: String, items: Array, sel: int, cb: Callable) -> OptionButton:
	var ob: OptionButton = UIKit.option_row(vb, caption, items)
	ob.select(clampi(sel, 0, items.size() - 1))
	ob.item_selected.connect(func(i: int) -> void: cb.call(i))
	return ob


## Re-read the values (used after a quality preset changes several at once).
func _refresh() -> void:
	_outlines.select(1 if GameState.outlines_enabled else 0)
	_shadows.select(1 if GameState.shadows_enabled else 0)
	_msaa.select(maxi([0, 2, 4].find(GameState.msaa_level), 0))
	_post.select(clampi(GameState.post_fx, 0, 2))
	_view.select(clampi(GameState.view_distance, 0, 2))
	_clouds.select(clampi(GameState.cloud_detail, 0, 2))
	_fullscreen.select(1 if GameState.fullscreen else 0)
	_ui_scale.select(_ui_index())


## Controls reference. Columns: label, keyboard text, action id ("" = not remappable), gamepad text
## (used only when the action is empty). Rows with an action id get a click-to-rebind gamepad button.
const BINDINGS := [
	["FLIGHT", "", "", ""],
	["Pitch", "S / W", "", "Left stick up / down"],
	["Roll", "A / D", "", "Left stick left / right"],
	["Yaw (rudder)", "Q / E", "", "-"],
	["Throttle", "Shift / Ctrl", "", "Right trigger up, left trigger down"],
	["Boost", "Tab", "boost", ""],
	["Target view (hold)", "K", "padlock", "Left shoulder"],
	["Auto-level assist", "R", "assist_toggle", ""],
	["Landing gear", "G", "gear", ""],
	["Wheel brake (landing)", "V", "brake", "Left trigger"],
	["Flaps (up / 15 / 35)", "F", "flaps", ""],
	["Bail out (hold)", "J", "bail_out", ""],
	["WEAPONS", "", "", ""],
	["Fire / drop bomb", "Space", "fire", ""],
	["Switch guns / bombs", "X or B", "weapon_toggle", ""],
	["BOMBERS", "", "", ""],
	["Bombsight / chart", "N / M", "sight_cycle", ""],
	["Gunner position (cycle)", "L", "gunner_view", ""],
	["Sight speed +", "Right arrow", "sight_spd_up", ""],
	["Sight speed -", "Left arrow", "sight_spd_down", ""],
	["Sight altitude +", "Up arrow", "sight_alt_up", ""],
	["Sight altitude -", "Down arrow", "sight_alt_down", ""],
	["CAMERA", "", "", ""],
	["Chase / cockpit view", "C", "camera", ""],
	["Free-look", "-", "", "Right stick"],
	["Centre view", "Right mouse", "center_view", ""],
	["Target view (nearest aircraft)", "K", "padlock", ""],
	["Hide HUD", "H", "", "-"],
	["Hide controls hint", "F1", "", "-"],
	["RADIO ORDERS (friendly aircraft)", "", "", ""],
	["Form on me", "1", "", "-"],
	["Attack my target", "2", "", "-"],
	["Cover me / break and defend", "3", "", "-"],
	["Return to base", "4", "", "-"],
	["WORLD", "", "", ""],
	["Time of day", "T", "", "-"],
	["Weather", "Y", "", "-"],
	["Outlines", "O", "", "-"],
	["SYSTEM", "", "", ""],
	["Pause / back", "Esc", "ui_cancel", ""],
	["Respawn", "Backspace", "", "-"],
	["Time warp up (x1 / x2 / x4)", "] or F5", "warp_up", ""],
	["Time warp down (x2 / x1)", "[", "warp_down", ""],
	["Start airborne toggle / swap airfield", "F2 / F3", "", "-"],
]

const JOY_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}
const JOY_AXIS_NAMES := {
	JOY_AXIS_LEFT_X: "L stick X", JOY_AXIS_LEFT_Y: "L stick Y",
	JOY_AXIS_RIGHT_X: "R stick X", JOY_AXIS_RIGHT_Y: "R stick Y",
	JOY_AXIS_TRIGGER_LEFT: "L trigger", JOY_AXIS_TRIGGER_RIGHT: "R trigger",
}


func _start_listening(action: String, btn: Button) -> void:
	_listening_action = action
	btn.text = "Press a button..."
	_hint.text = "Listening for %s - press a gamepad button or move a stick/trigger (Esc cancels, Delete unbinds)." % action


func _stop_listening() -> void:
	_listening_action = ""
	_hint.text = "Gamepad: click a binding, then press a button. Esc cancels, Delete unbinds."
	_refresh_bindings()


func _refresh_bindings() -> void:
	for action in _binding_buttons.keys():
		(_binding_buttons[action] as Button).text = _pad_label(action)
	if _diagram != null:
		_diagram.set_bindings(_diagram_map())


func _reset_bindings() -> void:
	GameState.reset_pad_bindings()
	_refresh_bindings()


func _pad_label(action: String) -> String:
	var e: InputEvent = GameState.pad_event_for(action)
	if e == null:
		return "Unbound"
	if e is InputEventJoypadButton:
		var b: InputEventJoypadButton = e
		return String(JOY_BUTTON_NAMES.get(b.button_index, "Btn %d" % b.button_index))
	var m: InputEventJoypadMotion = e
	var base: String = String(JOY_AXIS_NAMES.get(m.axis, "Axis %d" % m.axis))
	return base + (" +" if m.axis_value > 0.0 else " -")


func _input(event: InputEvent) -> void:
	if _listening_action == "":
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
			var bi: int = (event as InputEventJoypadButton).button_index
			if bi == JOY_BUTTON_LEFT_SHOULDER or bi == JOY_BUTTON_RIGHT_SHOULDER:
				var i: int = PAGES.find(_current_page)
				_show_page(PAGES[posmod(i + (-1 if bi == JOY_BUTTON_LEFT_SHOULDER else 1), PAGES.size())])
				get_viewport().set_input_as_handled()
			elif bi == JOY_BUTTON_B:
				_back()
				get_viewport().set_input_as_handled()
		if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
			_back()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_stop_listening()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_DELETE:
		GameState.clear_pad(_listening_action)     # leave the action with no gamepad button
		_stop_listening()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		GameState.rebind_pad(_listening_action, event)
		_stop_listening()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.6:
		GameState.rebind_pad(_listening_action, event)
		_stop_listening()
		get_viewport().set_input_as_handled()
