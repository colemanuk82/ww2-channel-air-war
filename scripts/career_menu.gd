class_name CareerMenu
extends CanvasLayer
## Pilot's Life: start a pilot (side, aircraft, name, ironman), see his status, and CONTINUE through the story pages
## and missions. Emits start_requested(cfg) for a mission step; the mission's result is applied by Career.record_result
## when it ends (main.gd), and the after-mission pages wait in Career.state["pending"] until this menu reopens.

signal start_requested(config: Dictionary)
signal closed

var _root: Control
var _name: LineEdit
var _side: OptionButton
var _aircraft: OptionButton
var _ids: Array = []
var _ironman: CheckBox
var _busy: bool = false


func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	if not Career.state.is_empty() or Career.load_state():
		if not (Career.state.get("pending", []) as Array).is_empty():
			_play_pending.call_deferred()
			return
	_rebuild()


func _rebuild() -> void:
	for c in _root.get_children():
		c.queue_free()
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.035, 0.03, 0.93)
	_root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	if Career.state.is_empty():
		_build_new(center)
	else:
		_build_status(center)


## After-mission pages from the last sortie, shown before the status page.
func _play_pending() -> void:
	var pages: Array = Career.state["pending"]
	Career.state["pending"] = []
	Career.save_state()
	_busy = true
	var s: StoryScreen = StoryScreen.play(get_parent(), pages)
	s.finished.connect(func() -> void:
		_busy = false
		_rebuild())


func _build_new(parent: Control) -> void:
	var vb: VBoxContainer = UIKit.panel(parent)
	(vb.get_parent().get_parent() as Control).custom_minimum_size = Vector2(640, 0)
	UIKit.heading(vb, "PILOT'S LIFE", 38)
	vb.add_child(UIKit.label("One pilot, one side, from the summer of 1940. Each sortie is part of a story: posting, patrols, scrambles, the letters home. The war keeps its own calendar.", 16, UIKit.TEXT_DIM))
	_name = LineEdit.new()
	_name.placeholder_text = "Pilot's name"
	_name.custom_minimum_size = Vector2(0, 40)
	_name.add_theme_font_size_override("font_size", 20)
	vb.add_child(_name)
	_side = UIKit.option_row(vb, "Side", ["Royal Air Force", "Luftwaffe"], 20)
	_side.item_selected.connect(func(_i: int) -> void: _refresh_aircraft())
	_aircraft = UIKit.option_row(vb, "Aircraft", [], 20)
	_ironman = CheckBox.new()
	_ironman.text = "Ironman: one life. No evacuation: a crash or capture ends the career."
	_ironman.add_theme_font_size_override("font_size", 17)
	vb.add_child(_ironman)
	_refresh_aircraft()
	vb.add_child(UIKit.button("START", _on_new, 28, true))
	vb.add_child(UIKit.button("Back", func() -> void: closed.emit(), 20))


func _side_key() -> String:
	return "Allies" if _side.selected == 0 else "Axis"


func _refresh_aircraft() -> void:
	_ids = Career.fighters_for(_side_key())
	_aircraft.clear()
	for id in _ids:
		_aircraft.add_item(AircraftCatalog.load_stats(str(id)).display_name)
	_aircraft.select(0)


func _on_new() -> void:
	var side: String = _side_key()
	var pick: String = str(_ids[maxi(_aircraft.selected, 0)])
	Career.new_pilot(_name.text, side, pick, _ironman.button_pressed)
	_rebuild()


func _build_status(parent: Control) -> void:
	var s: Dictionary = Career.state
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	parent.add_child(hb)
	var left: VBoxContainer = UIKit.panel(hb)
	(left.get_parent().get_parent() as Control).custom_minimum_size = Vector2(600, 0)
	UIKit.heading(left, str(s["name"]), 36)
	left.add_child(UIKit.label("%s  -  %s" % [Career.rank_name(), str(s["squadron"])], 20, UIKit.ACCENT))
	left.add_child(UIKit.label("%s   Sorties %d   Kills %d   Fatigue %d/10" % [Career.date_text(), int(s["sorties"]), int(s["kills"]), int(s["fatigue"])], 17))
	left.add_child(UIKit.label("Status: %s%s" % [_status_text(), "   (Ironman)" if bool(s.get("ironman", false)) else ""], 17, UIKit.TEXT_DIM))
	left.add_child(UIKit.rule(0.4))
	var mates: Array = s.get("mates", [])
	left.add_child(UIKit.label("Squadron mates: " + (", ".join(mates) if not mates.is_empty() else "none left"), 16, UIKit.TEXT_DIM))
	var lost: Array = s.get("lost_mates", [])
	if not lost.is_empty():
		left.add_child(UIKit.label("Lost: " + ", ".join(lost), 15, UIKit.TEXT_DIM))
	left.add_child(UIKit.rule(0.4))
	left.add_child(UIKit.label("LOG", 14, UIKit.TEXT_DIM, true))
	var log: Array = s.get("log", [])
	var tail: String = "\n".join(log.slice(maxi(log.size() - 7, 0)))
	var nl: Label = UIKit.label(tail, 15, Color(0.88, 0.86, 0.78))
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.add_theme_font_override("font", UIKit.body_font())
	nl.custom_minimum_size = Vector2(540, 0)
	left.add_child(nl)
	# right: what happens next
	var right: VBoxContainer = UIKit.panel(hb)
	(right.get_parent().get_parent() as Control).custom_minimum_size = Vector2(440, 0)
	if Career.is_ended():
		UIKit.heading(right, str(s["ended"]), 30)
		right.add_child(UIKit.label("The career is over. Start a new pilot to fly again.", 18, UIKit.TEXT_DIM))
		right.add_child(UIKit.button("New pilot", _new_pilot, 22, true))
		right.add_child(UIKit.button("Back", func() -> void: closed.emit(), 20))
		return
	var a: Dictionary = Career.next_action()
	var kind: String = str(a.get("kind", ""))
	var label: String = "CONTINUE"
	var note: String = ""
	match kind:
		"story":
			var sp: Array = a["step"].get("pages", [])
			note = str((sp[0] as Dictionary).get("title", "Story")) if not sp.is_empty() else "Story"
		"mission":
			note = str(a["step"].get("title", a["step"].get("id", "Next sortie"))).replace("_", " ").capitalize()
		"done":
			note = "The next chapter is not written yet. Your pilot is still on the strength of the squadron."
			label = "CONTINUE"
	UIKit.heading(right, "TODAY", 26)
	if note != "":
		right.add_child(UIKit.label(note, 18, UIKit.TEXT_DIM))
	if kind == "story" or kind == "mission" or kind == "done":
		var go := UIKit.button(label, _continue, 26, true)
		go.disabled = _busy or kind == "done"
		right.add_child(go)
	right.add_child(UIKit.button("New pilot", _new_pilot, 20))
	right.add_child(UIKit.button("Back", func() -> void: closed.emit(), 20))


func _status_text() -> String:
	match str(Career.state.get("status", "active")):
		"rest":
			return "On leave - back on duty %s" % Career.date_text(int(Career.state.get("rest_until", 0)))
		"killed":
			return "Killed"
		"pow":
			return "Prisoner of war"
		"survived":
			return "Survived the war"
	return "Fit for operations"


func _new_pilot() -> void:
	Career.delete_save()
	_rebuild()


func _continue() -> void:
	if _busy:
		return
	var a: Dictionary = Career.next_action()
	var kind: String = str(a.get("kind", ""))
	if kind == "story":
		var st: Dictionary = a["step"]
		_busy = true
		var s: StoryScreen = StoryScreen.play(get_parent(), Career.fill(st.get("pages", [])))
		s.finished.connect(func() -> void:
			_busy = false
			Career.advance_story()
			_rebuild())
	elif kind == "mission":
		var step: Dictionary = a["step"]
		_busy = true
		var before: Array = Career.fill(step.get("before", []))
		if before.is_empty():
			start_requested.emit(Career.mission_config(step))
			return
		var s2: StoryScreen = StoryScreen.play(get_parent(), before)
		s2.finished.connect(func() -> void:
			_busy = false
			start_requested.emit(Career.mission_config(step)))


func _unhandled_input(event: InputEvent) -> void:
	if not _busy and event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()
