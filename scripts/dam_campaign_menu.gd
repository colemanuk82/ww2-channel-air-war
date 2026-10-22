class_name DamCampaignMenu
extends Control
## Dam Busters course: one day per mission, in order. Pick an open day and fly it.
## Emits start_requested(cfg) (DamCampaign.config_for) and closed().

signal start_requested(config: Dictionary)
signal closed

var _selected: int = 0
var _brief: Label
var _fly: Button
var _list: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.05, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Centre the column on screen and let it scroll when the window is short, so it never runs off the edge.
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
	box.custom_minimum_size = Vector2(620, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	box.add_child(UIKit.label("DAM BUSTERS", 34, UIKit.TEXT, true))
	box.add_child(UIKit.label("Training, then Operation Chastise. One mission a day.", 16, UIKit.TEXT_DIM))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	box.add_child(_list)
	_brief = UIKit.label("", 16, UIKit.TEXT_DIM)
	_brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_brief)
	_fly = UIKit.button("FLY THIS DAY", func() -> void: start_requested.emit(DamCampaign.config_for(_selected)), 24, true)
	box.add_child(_fly)
	box.add_child(UIKit.button("Back", func() -> void: closed.emit(), 18))
	_rebuild()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	for i in DamCampaign.count():
		var d: Dictionary = DamCampaign.DAYS[i]
		var tag: String = "  (passed)" if DamCampaign.is_passed(i) else ("" if DamCampaign.is_open(i) else "  (locked)")
		var b := UIKit.button(str(d["title"]) + tag, func() -> void: _select(i), 17)
		b.disabled = not DamCampaign.is_open(i)
		_list.add_child(b)
	_select(_first_open())


func _first_open() -> int:
	for i in DamCampaign.count():
		if DamCampaign.is_open(i) and not DamCampaign.is_passed(i):
			return i
	return DamCampaign.count() - 1


func _select(i: int) -> void:
	_selected = i
	_brief.text = str(DamCampaign.DAYS[i]["brief"]) + DamCampaign.STEER_NOTE
	_fly.disabled = not DamCampaign.is_open(i)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()
