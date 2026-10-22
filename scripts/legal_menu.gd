class_name LegalMenu
extends Control
## Credits and licences, the end user licence agreement, the privacy policy and the engine's own licence list.
## Text lives in data/legal.json (built by tools/build_legal.py from docs/legal/*.txt). Emits closed().

signal closed

const LEGAL_PATH := "res://data/legal.json"
const TABS := [["credits", "Credits & Licences"], ["eula", "Licence Agreement"], ["privacy", "Privacy Policy"], ["engine", "Engine Licences"]]

static var _cache: Dictionary = {}

var _body: RichTextLabel
var _buttons: Dictionary = {}


## The bundled legal text by key (credits / eula / privacy / epilepsy); empty when the file is missing.
static func text_for(key: String) -> String:
	if _cache.is_empty():
		var f := FileAccess.open(LEGAL_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_cache = parsed
	return String(_cache.get(key, ""))


## Godot's own licence, its component licences and copyright list (built into the engine binary).
static func engine_text() -> String:
	var out: String = "GODOT ENGINE\n\n" + Engine.get_license_text() + "\n\n"
	out += "---------------------------------------------\nENGINE COMPONENT COPYRIGHTS\n\n"
	for comp in Engine.get_copyright_info():
		out += "* %s\n" % String(comp.get("name", ""))
		for part in comp.get("parts", []):
			out += "    %s\n    Copyright: %s\n    Licence: %s\n" % [", ".join(PackedStringArray(part.get("files", []))), ", ".join(PackedStringArray(part.get("copyright", []))), String(part.get("license", ""))]
		out += "\n"
	out += "---------------------------------------------\nLICENCE TEXTS\n\n"
	var info: Dictionary = Engine.get_license_info()
	for k in info.keys():
		out += "===== %s =====\n%s\n\n" % [String(k), String(info[k])]
	return out


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.05, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 36)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	box.add_child(UIKit.label("CREDITS & LEGAL", 32, UIKit.TEXT, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	for t in TABS:
		var key: String = t[0]
		var b := UIKit.button(String(t[1]), func() -> void: _show(key), 17)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		_buttons[key] = b
	_body = RichTextLabel.new()
	_body.bbcode_enabled = false
	_body.scroll_active = true
	_body.selection_enabled = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(0, 360)
	_body.add_theme_font_override("normal_font", UIKit.body_font())
	_body.add_theme_font_size_override("normal_font_size", 16)
	_body.add_theme_color_override("default_color", UIKit.TEXT)
	box.add_child(_body)
	box.add_child(UIKit.button("Back", func() -> void: closed.emit(), 18, true))
	_show("credits")


func _show(key: String) -> void:
	_body.text = engine_text() if key == "engine" else text_for(key)
	_body.scroll_to_line(0)
	for k in _buttons.keys():
		(_buttons[k] as Button).disabled = (k == key)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()
