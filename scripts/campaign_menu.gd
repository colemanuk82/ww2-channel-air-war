class_name CampaignMenu
extends CanvasLayer
## Campaign screen opened from the start menu: new campaign form, or the current situation (date, rank, air strength and
## industry of both sides, news log) with today's three sortie offers. Emits start_requested(cfg) for the chosen sortie.

signal start_requested(config: Dictionary)
signal closed

var _root: Control
var _side: OptionButton
var _aircraft: OptionButton
var _home: OptionButton
var _era: OptionButton
var _ids: Array = []
var _homes: Array = []
var _selected: int = 0
var _offer_buttons: Array = []
var _fly: Button


func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_rebuild()


func _rebuild() -> void:
	for c in _root.get_children():
		c.queue_free()
	_offer_buttons.clear()
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.035, 0.03, 0.93)
	_root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	if Campaign.state.is_empty() and not Campaign.load_state():
		_build_new(center)
	else:
		_build_status(center)


func _build_new(parent: Control) -> void:
	var vb: VBoxContainer = UIKit.panel(parent)
	(vb.get_parent().get_parent() as Control).custom_minimum_size = Vector2(640, 0)
	UIKit.heading(vb, "NEW CAMPAIGN", 38)
	vb.add_child(UIKit.label("Fly a career. Every sortie changes the war: bombed factories stay out for a week, the enemy raids your industry, and each day offers new missions.", 16, UIKit.TEXT_DIM))
	_side = UIKit.option_row(vb, "Side", ["Allies", "Axis"], 20)
	_aircraft = UIKit.option_row(vb, "Aircraft", [], 20)
	_home = UIKit.option_row(vb, "Home base", [], 20)
	var eras: Array = []
	for e in Campaign.ERAS:
		eras.append(String(e[0]))
	_era = UIKit.option_row(vb, "Starting date", eras, 20)
	_side.item_selected.connect(func(_i: int) -> void: _refresh_new())
	_era.item_selected.connect(func(_i: int) -> void: _refresh_new())
	_refresh_new()
	vb.add_child(UIKit.button("START CAMPAIGN", _on_new, 28, true))
	vb.add_child(UIKit.button("Back", func() -> void: closed.emit(), 20))


func _refresh_new() -> void:
	var side: String = _side.get_item_text(_side.selected)
	_ids = AircraftCatalog.ids_for_side(side)
	_aircraft.clear()
	for id in _ids:
		_aircraft.add_item(AircraftCatalog.load_stats(id).display_name)
	_aircraft.select(0)
	_homes = Campaign.airfields_for(side, String(Campaign.ERAS[_era.selected][1]))
	_home.clear()
	for a in _homes:
		_home.add_item(SpawnPoints.label_for(str(a["name"]), side))
	var pref: int = 0
	for i in _homes.size():
		if str(_homes[i]["id"]) in ["biggin_hill", "manston", "calais_marck", "abbeville_drucat"]:
			pref = i
			break
	_home.select(pref)


func _on_new() -> void:
	var date: String = String(Campaign.ERAS[_era.selected][1])
	Campaign.new_campaign(_side.get_item_text(_side.selected), String(_ids[_aircraft.selected]), String(_homes[_home.selected]["id"]), date)
	_rebuild()


func _bar(parent: Control, caption: String, value: float, good_high: bool) -> void:
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var l: Label = UIKit.label(caption, 16, UIKit.TEXT_DIM)
	l.custom_minimum_size = Vector2(190, 0)
	hb.add_child(l)
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 100.0
	pb.value = value
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(240, 16)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	var t: float = value / 100.0 if good_high else 1.0 - value / 100.0
	fill.bg_color = Color(0.85, 0.3, 0.25).lerp(Color(0.4, 0.8, 0.35), clampf(t, 0.0, 1.0))
	pb.add_theme_stylebox_override("fill", fill)
	hb.add_child(pb)
	hb.add_child(UIKit.label("  %d%%" % int(value), 16))


func _build_status(parent: Control) -> void:
	var s: Dictionary = Campaign.state
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	parent.add_child(hb)
	# left: situation
	var left: VBoxContainer = UIKit.panel(hb)
	(left.get_parent().get_parent() as Control).custom_minimum_size = Vector2(560, 0)
	UIKit.heading(left, "CAMPAIGN", 36)
	left.add_child(UIKit.label("%s  -  %s" % [str(s["side"]), str(s["date"])], 20, UIKit.ACCENT))
	var p: Dictionary = s["pilot"]
	left.add_child(UIKit.label("%s   Sorties %d   Kills %d   Score %d" % [Campaign.rank_name(), int(p["sorties"]), int(p["kills"]), int(p["score"])], 17))
	left.add_child(UIKit.rule(0.4))
	_bar(left, "Your air strength", float(s["strength"]["own"]), true)
	_bar(left, "Enemy air strength", float(s["strength"]["enemy"]), false)
	_bar(left, "Your industry", float(s["industry"]["own"]), true)
	_bar(left, "Enemy industry", float(s["industry"]["enemy"]), false)
	var dmg: Dictionary = s["damaged"]
	left.add_child(UIKit.label("Targets out of action: %d" % dmg.size(), 15, UIKit.TEXT_DIM))
	left.add_child(UIKit.rule(0.4))
	left.add_child(UIKit.label("NEWS", 14, UIKit.TEXT_DIM, true))
	var log: Array = s["log"]
	var news: String = "\n".join(log.slice(maxi(log.size() - 7, 0)))
	var nl: Label = UIKit.label(news, 15, Color(0.88, 0.86, 0.78))
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.add_theme_font_override("font", UIKit.body_font())
	nl.custom_minimum_size = Vector2(500, 0)
	left.add_child(nl)
	var row := HBoxContainer.new()
	left.add_child(row)
	var back: Button = UIKit.button("Back", func() -> void: closed.emit(), 20)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(back)
	var nw: Button = UIKit.button("New campaign", func() -> void:
		Campaign.delete_save()
		_rebuild(), 20)
	nw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nw)
	# right: today's sorties
	var right: VBoxContainer = UIKit.panel(hb)
	(right.get_parent().get_parent() as Control).custom_minimum_size = Vector2(520, 0)
	if str(s["ended"]) != "":
		UIKit.heading(right, "CAMPAIGN %s" % str(s["ended"]).to_upper(), 34)
		right.add_child(UIKit.label("Start a new campaign to fly again.", 18, UIKit.TEXT_DIM))
		return
	UIKit.heading(right, "TODAY'S SORTIES", 30)
	var offers: Array = s["offers"]
	_selected = 0
	for i in offers.size():
		var o: Dictionary = offers[i]
		var b := UIKit.button(str(o["title"]), func() -> void: _select(i), 19)
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		right.add_child(b)
		_offer_buttons.append(b)
		var br: Label = UIKit.label(str(o["brief"]), 14, UIKit.TEXT_DIM)
		br.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		br.add_theme_font_override("font", UIKit.body_font())
		br.custom_minimum_size = Vector2(460, 0)
		right.add_child(br)
	_fly = UIKit.button("FLY SORTIE", func() -> void: start_requested.emit(Campaign.offer_config(_selected)), 28, true)
	right.add_child(_fly)
	_select(0)
	_fly.grab_focus()


func _select(i: int) -> void:
	_selected = i
	for j in _offer_buttons.size():
		(_offer_buttons[j] as Button).button_pressed = j == i


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()
