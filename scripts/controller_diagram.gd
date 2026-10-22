class_name ControllerDiagram
extends Control
## Gamepad diagram for the Controls page. Draws the controller outline (assets/ui/controller_outline.png) with a
## leader line to each input, and a label on the left or right listing what is bound to that input.
## Call set_bindings() whenever bindings change.

const TEX_PATH := "res://assets/ui/controller_outline.png"
const PAD_SCALE := 0.42                 # outline is 1470 px wide in the asset; drawn at 42 %
const PAD_SIZE := Vector2(1470, 1040) * PAD_SCALE
const W := 1100.0
const H := 440.0
const PAD_POS := Vector2((W - PAD_SIZE.x) * 0.5, 0.0)
const LABEL_W := 240.0

## Input keys -> point on the outline image (asset pixels), where the leader line ends.
const ANCHORS := {
	"LT": Vector2(330, 40), "LB": Vector2(423, 76), "BACK": Vector2(626, 293),
	"LS": Vector2(365, 293), "DPAD": Vector2(538, 524),
	"RT": Vector2(1130, 40), "RB": Vector2(1037, 76), "START": Vector2(834, 293),
	"RS": Vector2(918, 510), "Y": Vector2(1101, 197), "B": Vector2(1199, 299),
	"A": Vector2(1101, 395), "X": Vector2(1001, 299),
}
const LEFT_KEYS: Array = ["LT", "LB", "LS", "BACK", "DPAD"]
const RIGHT_KEYS: Array = ["RT", "RB", "Y", "B", "X", "START", "A", "RS"]
const NAMES := {
	"LT": "Left trigger", "LB": "Left bumper", "BACK": "Back", "LS": "Left stick (L3)", "DPAD": "D-pad",
	"RT": "Right trigger", "RB": "Right bumper", "START": "Start", "RS": "Right stick (R3)",
	"Y": "Y", "B": "B", "A": "A", "X": "X",
}

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
	var step: float = (H - 40.0) / float(maxi(keys.size() - 1, 1))
	return 20.0 + float(keys.find(key)) * step


func _build_labels(keys: Array, left: bool) -> void:
	for key in keys:
		var k: String = String(key)
		var y: float = _row_y(keys, k)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		vb.position = Vector2(0.0 if left else W - LABEL_W, y - 18.0)
		vb.size = Vector2(LABEL_W, 40)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(vb)
		var name_l: Label = UIKit.label(String(NAMES.get(k, k)).to_upper(), 12, UIKit.ACCENT, true)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if left else HORIZONTAL_ALIGNMENT_LEFT
		vb.add_child(name_l)
		var act_l: Label = UIKit.label("", 15, UIKit.TEXT)
		act_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if left else HORIZONTAL_ALIGNMENT_LEFT
		act_l.clip_text = true
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
		l.text = ", ".join(PackedStringArray(names)) if names.size() > 0 else "-"
		l.add_theme_color_override("font_color", UIKit.TEXT if names.size() > 0 else UIKit.TEXT_DIM)


func _anchor(key: String) -> Vector2:
	return PAD_POS + ANCHORS[key] * PAD_SCALE


func _draw() -> void:
	if _tex != null:
		draw_texture_rect(_tex, Rect2(PAD_POS, PAD_SIZE), false, Color(1, 1, 1, 0.95))
	var lead := Color(UIKit.ACCENT, 0.6)
	for key in LEFT_KEYS:
		var from := Vector2(LABEL_W + 8.0, _row_y(LEFT_KEYS, key))
		draw_line(from, _anchor(key), lead, 1.5, true)
		draw_circle(_anchor(key), 4.0, UIKit.ACCENT)
	for key in RIGHT_KEYS:
		var from2 := Vector2(W - LABEL_W - 8.0, _row_y(RIGHT_KEYS, key))
		draw_line(from2, _anchor(key), lead, 1.5, true)
		draw_circle(_anchor(key), 4.0, UIKit.ACCENT)
