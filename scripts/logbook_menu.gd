class_name LogbookMenu
extends Control
## Pilot's logbook from the main menu: rank, decorations and totals for each side. Emits closed().

signal closed

var _text: Label
var _tabs: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.05, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# centred, and scrolls on a short window so it never runs off the screen
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 40)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(720, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	box.add_child(UIKit.label("PILOT'S LOGBOOK", 34, UIKit.TEXT, true))
	box.add_child(UIKit.label("Your rank, decorations and totals, kept for each side.", 16, UIKit.TEXT_DIM))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	for side in ["Allies", "Axis"]:
		var b := UIKit.button("RAF (Allies)" if side == "Allies" else "Luftwaffe (Axis)", func() -> void: _show(side), 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		_tabs[side] = b
	_text = UIKit.label("", 16, UIKit.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_text)
	box.add_child(UIKit.button("Back", func() -> void: closed.emit(), 18))
	_show("Allies")


func _show(side: String) -> void:
	_text.text = PilotLog.logbook_text(side)



func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()
