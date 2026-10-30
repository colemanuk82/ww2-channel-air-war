class_name DonationPrompt
extends CanvasLayer
## One-time-per-launch support panel shown over the start menu. Optional: the game never sends anything
## unless the player opens one of the links.

signal done

const DONATE_URL := "https://paypal.me/colemanuk82"
const ISSUES_URL := "https://github.com/colemanuk82/ww2-channel-air-war/issues"

static var shown: bool = false


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.02, 0.025, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.045, 0.05, 0.97)
	sb.border_color = Color(0.78, 0.69, 0.43, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(UIKit.label("SUPPORT CHANNEL AIR WAR", 29, UIKit.TEXT, true))
	box.add_child(UIKit.rule(0.8))
	var body := UIKit.label(
		"Thank you for playing. If you are enjoying the game, please consider donating to me — it helps cover the AI development costs and lets me keep updating it.\n\nI would also love to hear any suggestions you have for what to add next.",
		18, UIKit.TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(700, 0)
	box.add_child(body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var donate := UIKit.button("Donate via PayPal", func() -> void: OS.shell_open(DONATE_URL), 19, true)
	donate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	donate.tooltip_text = "Optional. Opens " + DONATE_URL + " in your browser."
	row.add_child(donate)
	var ideas := UIKit.button("Suggest an idea", func() -> void: OS.shell_open(ISSUES_URL), 19)
	ideas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ideas.tooltip_text = "Optional. Opens the GitHub issues page in your browser."
	row.add_child(ideas)
	var cont := UIKit.button("Continue to menu", _close, 19, true)
	cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cont)
	cont.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	done.emit()
