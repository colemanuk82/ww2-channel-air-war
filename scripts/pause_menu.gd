class_name PauseMenu
extends CanvasLayer
## Esc pause overlay: resume / restart / quit to menu / quit game. Works while the tree is paused.

signal resume_requested
signal restart_requested
signal menu_requested
signal quit_requested
signal warp_requested(mult: int)      # simulation time warp picked from the menu row (x1 / x2 / x4)
signal end_sortie_requested           # Pilot's Life: land, then end the sortie (the result is recorded)

var _root: Control
var _resume_btn: Button
var _warp_btn: Button
var enabled: bool = true
var stats_provider: Callable = Callable()   # returns the live mode stats Dictionary (set by main)
var warp_reset: Callable = Callable()       # main resets the warp to 1x when this menu opens (set by main)
var _score_panel: Control
var show_end_sortie: bool = false       # set by main for career sorties
var _end_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim: Control = UIKit.dimmer(0.5)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var vb: VBoxContainer = UIKit.panel(center)
	vb.custom_minimum_size = Vector2(320, 0)
	UIKit.heading(vb, "PAUSED", 36)
	_resume_btn = UIKit.button("Resume", func() -> void: set_open(false))
	vb.add_child(_resume_btn)
	# Time warp row: the game is paused while this menu is up (which forces 1x), so picking a speed here also
	# resumes the flight with it applied - that is the "warp to the action" entry point outside the ] / [ keys.
	_warp_btn = UIKit.button(_warp_text(), func() -> void: _cycle_warp())
	vb.add_child(_warp_btn)
	vb.add_child(UIKit.button("Score", _show_score))
	vb.add_child(UIKit.button("Options", func() -> void: add_child(SettingsMenu.new())))
	_end_btn = UIKit.button("End sortie (land first)", func() -> void:
		set_open(false)
		end_sortie_requested.emit())
	_end_btn.visible = false
	vb.add_child(_end_btn)
	vb.add_child(UIKit.button("Restart", func() -> void: restart_requested.emit()))
	vb.add_child(UIKit.button("Quit to menu", func() -> void: menu_requested.emit()))


## Live score sheet for the current sortie (score, kills, time and whatever the mode tracks).
func _show_score() -> void:
	if _score_panel != null and is_instance_valid(_score_panel):
		_score_panel.queue_free()
	var stats: Dictionary = stats_provider.call() if stats_provider.is_valid() else {}
	_score_panel = Control.new()
	_score_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_score_panel)
	_score_panel.add_child(UIKit.dimmer(0.65))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_score_panel.add_child(center)
	var vb: VBoxContainer = UIKit.panel(center)
	vb.custom_minimum_size = Vector2(420, 0)
	UIKit.heading(vb, "SCORE", 36)
	var secs: int = int(float(stats.get("time", 0.0)))
	var rows: Array = [["Score", str(int(stats.get("score", 0)))], ["Kills", str(int(stats.get("kills", 0)))], ["Time", "%d:%02d" % [secs / 60, secs % 60]]]
	var first: Array = ["score", "kills", "time", "success", "reason"]
	for k in stats.keys():
		if k in first:
			continue
		var v: Variant = stats[k]
		if v is int or v is float or v is String:
			rows.append([String(k).capitalize().replace("_", " "), str(v)])
	for r in rows:
		var hb := HBoxContainer.new()
		vb.add_child(hb)
		var a := UIKit.label(r[0], 20, UIKit.ACCENT)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(a)
		hb.add_child(UIKit.label(r[1], 20))
	var back := UIKit.button("Back", func() -> void: _score_panel.queue_free())
	vb.add_child(back)
	back.grab_focus()


func is_open() -> bool:
	return _root.visible


## Current warp as it would read on the row ("Time warp: x1 ->").
func _warp_text() -> String:
	return "Time warp: %s  >" % GameState.SIM_WARP_NAMES[GameState.sim_warp_index()]


## Step the warp up the ladder and resume: the warp is only meaningful while flying.
func _cycle_warp() -> void:
	var next_i: int = (GameState.sim_warp_index() + 1) % GameState.SIM_WARPS.size()
	set_open(false)
	warp_requested.emit(int(GameState.SIM_WARPS[next_i]))


func set_open(open: bool) -> void:
	_root.visible = open
	if _end_btn != null:
		_end_btn.visible = open and show_end_sortie
	get_tree().paused = open
	GameState.paused = open
	if open:
		if warp_reset.is_valid():
			warp_reset.call()          # 1x while paused; the row above re-arms it
		if _warp_btn:
			_warp_btn.text = _warp_text()
		_resume_btn.grab_focus()
	else:
		resume_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if enabled and event.is_action_pressed("ui_cancel"):
		set_open(not _root.visible)
		get_viewport().set_input_as_handled()
