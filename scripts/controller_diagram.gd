class_name ControllerDiagram
extends Control
## Gamepad diagram for the Controls page. Draws the controller outline (assets/ui/controller_outline.png) with the
## face buttons in their Xbox colours, a leader line to each input, and beside it the button icon, its name and
## what is bound to it (wrapping onto a second line rather than being cut off).
## Call set_bindings() whenever bindings change.

const TEX_PATH := "res://assets/ui/controller_outline.png"
const PAD_SCALE := 0.35                 # outline is 1470 px wide in the asset; drawn at 35 %
const PAD_SIZE := Vector2(1470, 1040) * PAD_SCALE
const W := 1120.0
const H := 390.0
const PAD_POS := Vector2((W - PAD_SIZE.x) * 0.5, 12.0)
const LABEL_W := 290.0

## Input keys -> point on the outline image (asset pixels), where the leader line ends.
const ANCHORS := {
	"LT": Vector2(330, 40), "LB": Vector2(423, 76), "BACK": Vector2(626, 293),
	"LS": Vector2(365, 293), "DPAD": Vector2(538, 524),
	"RT": Vector2(1130, 40), "RB": Vector2(1037, 76), "START": Vector2(834, 293),
	"RS": Vector2(918, 510), "Y": Vector2(1101, 197), "B": Vector2(1199, 299),
	"A": Vector2(1101, 395), "X": Vector2(1001, 299),
}
const LEFT_KEYS: Array = ["LT", "LB", "LS", "BACK", "DPAD"]
const RIGHT_KEYS: Array = ["RT", "RB", "Y", "B", "X", "A", "RS", "START"]
const NAMES := {
	"LT": "Left trigger", "LB": "Left bumper", "BACK": "View", "LS": "Left stick  (click L3)", "DPAD": "D-pad",
	"RT": "Right trigger", "RB": "Right bumper", "START": "Menu", "RS": "Right stick  (click R3)",
	"Y": "Y", "B": "B", "A": "A", "X": "X",
}
const GLYPH := {"LS": "LS", "RS": "RS", "DPAD": "DPAD"}

var _actions: Dictionary = {}     # input key -> Array of action names
var _text: Dictionary = {}        # input key -> Label showing the actions
var _tex: Texture2D


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_tex = load(TEX_PATH)


func _ready() -> void:
	_build_labels(LEFT_KEYS, true)
	_build_labels(RIGHT_KEYS, false)


func _row_y(keys: Array, key: String) -> float:
	var step: float = (H - 64.0) / float(maxi(keys.size() - 1, 1))    # room under the last row for a 2nd line
	return 16.0 + float(keys.find(key)) * step


func _build_labels(keys: Array, left: bool) -> void:
	for key in keys:
		var k: String = String(key)
		var y: float = _row_y(keys, k)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 1)
		vb.position = Vector2(0.0 if left else W - LABEL_W, y - 14.0)
		vb.custom_minimum_size = Vector2(LABEL_W, 0)
		vb.size = Vector2(LABEL_W, 40)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(vb)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.alignment = BoxContainer.ALIGNMENT_END if left else BoxContainer.ALIGNMENT_BEGIN
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(head)
		var name_l: Label = UIKit.label(String(NAMES.get(k, k)).to_upper(), 12, UIKit.ACCENT, true)
		var g: PadGlyph = PadGlyph.make(String(GLYPH.get(k, k)), 24.0)
		if left:
			head.add_child(name_l)
			head.add_child(g)
		else:
			head.add_child(g)
			head.add_child(name_l)
		var act_l: Label = UIKit.label("", 13, UIKit.TEXT)
		act_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if left else HORIZONTAL_ALIGNMENT_LEFT
		act_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		act_l.custom_minimum_size = Vector2(LABEL_W, 0)
		vb.add_child(act_l)
		_text[k] = act_l
	_refresh_text()


## actions: input key -> Array of action display names.
func set_bindings(actions: Dictionary) -> void:
	_actions = actions
	_refresh_text()
	queue_redraw()


func _refresh_text() -> void:
	for key in _text.keys():
		var names: Array = _actions.get(key, [])
		var l: Label = _text[key]
		l.text = ",  ".join(PackedStringArray(names)) if names.size() > 0 else "-"
		l.add_theme_color_override("font_color", UIKit.TEXT if names.size() > 0 else UIKit.TEXT_DIM)


func _anchor(key: String) -> Vector2:
	return PAD_POS + ANCHORS[key] * PAD_SCALE


func _draw() -> void:
	if _tex != null:
		draw_texture_rect(_tex, Rect2(PAD_POS, PAD_SIZE), false, Color(1, 1, 1, 0.95))
	var lead := Color(UIKit.ACCENT, 0.55)
	for key in LEFT_KEYS:
		var from := Vector2(LABEL_W + 10.0, _row_y(LEFT_KEYS, key))
		draw_line(from, _anchor(key), lead, 1.5, true)
		draw_circle(_anchor(key), 4.0, UIKit.ACCENT)
	for key in RIGHT_KEYS:
		var from2 := Vector2(W - LABEL_W - 10.0, _row_y(RIGHT_KEYS, key))
		draw_line(from2, _anchor(key), lead, 1.5, true)
		draw_circle(_anchor(key), 4.0, UIKit.ACCENT)
	# the face buttons in their own colours, over the outline
	for fk in ["A", "B", "X", "Y"]:
		PadGlyph.draw_glyph(self, fk, _anchor(fk), 28.0)
