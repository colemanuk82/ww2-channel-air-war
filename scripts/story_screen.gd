class_name StoryScreen
extends CanvasLayer
## Full-screen story pages between missions. Each page is {kind, title, text, image?}:
##   "text"     - a picture (if one exists under assets/career/<image>) with a caption box, typed out
##   "letter" / "telegram" / "news" - a paper card on a dark ground
## Enter / Space / click: finish the typing, then next page. Escape: skip the rest.

signal finished

const TYPE_CPS := 42.0          # characters per second
const PAN_TIME := 14.0          # seconds for the slow zoom on picture pages
const PAPER := Color(0.93, 0.9, 0.82)
const INK := Color(0.12, 0.1, 0.08)

var _pages: Array = []
var _i: int = -1
var _root: Control
var _bg: ColorRect
var _pic: TextureRect
var _card: PanelContainer
var _title: Label
var _body: Label
var _hint: Label
var _shown: float = 0.0
var _typing: bool = false
var _tween: Tween


## Build, add to `parent` and play `pages`. Emits `finished` when the last page is passed.
static func play(parent: Node, pages: Array) -> StoryScreen:
	var s := StoryScreen.new()
	s.layer = 60
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	s._pages = pages
	parent.add_child(s)
	return s


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.color = Color(0.02, 0.025, 0.03)
	_root.add_child(_bg)
	_pic = TextureRect.new()
	_pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_pic.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	_pic.visible = false
	_root.add_child(_pic)
	_card = PanelContainer.new()
	_root.add_child(_card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	_card.add_child(vb)
	_title = UIKit.label("", 30, Color(0.9, 0.85, 0.7), true)
	vb.add_child(_title)
	_body = UIKit.label("", 22)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_override("font", UIKit.body_font())
	vb.add_child(_body)
	_hint = UIKit.label("Enter - continue     Esc - skip story", 14, UIKit.TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(_hint)
	_next()


func _process(delta: float) -> void:
	if _typing and _body != null:
		_shown += delta * TYPE_CPS
		var n: int = int(_shown)
		if n >= _body.text.length():
			_body.visible_characters = -1
			_typing = false
		else:
			_body.visible_characters = n


func _unhandled_input(event: InputEvent) -> void:
	var press: bool = event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if event.is_action_pressed("ui_cancel"):
		_done()
	elif press:
		if _typing:
			_shown = float(_body.text.length())
			_body.visible_characters = -1
			_typing = false
		else:
			_next()
	else:
		return
	get_viewport().set_input_as_handled()


func _next() -> void:
	_i += 1
	if _i >= _pages.size():
		_done()
		return
	var p: Dictionary = _pages[_i]
	var kind: String = str(p.get("kind", "text"))
	_title.text = str(p.get("title", ""))
	_body.text = str(p.get("text", ""))
	_shown = 0.0
	_body.visible_characters = 0
	_typing = true
	_hint.text = "Enter - continue     Esc - skip story" if _i < _pages.size() - 1 else "Enter - begin"
	if kind == "text":
		_show_picture(str(p.get("image", "")))
		_bg.color = Color(0.02, 0.025, 0.03)
		_card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_card.offset_left = 80.0
		_card.offset_right = -80.0
		_card.offset_top = -260.0
		_card.offset_bottom = -40.0
		_card.add_theme_stylebox_override("panel", _box(Color(0.03, 0.035, 0.04, 0.82), Color(0.5, 0.45, 0.3, 0.7)))
		_title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
		_body.add_theme_color_override("font_color", Color(0.92, 0.9, 0.84))
	else:
		_show_picture("")
		_bg.color = Color(0.05, 0.05, 0.05, 0.96)
		_card.set_anchors_preset(Control.PRESET_CENTER)
		_card.offset_left = -330.0
		_card.offset_right = 330.0
		_card.offset_top = -230.0
		_card.offset_bottom = 230.0
		_card.add_theme_stylebox_override("panel", _box(PAPER, Color(0.45, 0.4, 0.3), 2, 4))
		_title.add_theme_color_override("font_color", INK)
		_body.add_theme_color_override("font_color", INK)
		if kind == "telegram":
			_body.add_theme_font_override("font", UIKit.font(true))
		if kind == "news":
			_title.add_theme_font_override("font", UIKit.font(true))
	_title.add_theme_font_size_override("font_size", 30)


func _show_picture(path: String) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_pic.visible = false
	if path == "" or not ResourceLoader.exists("res://assets/career/" + path):
		return
	_pic.texture = load("res://assets/career/" + path) as Texture2D
	_pic.visible = true
	_pic.scale = Vector2.ONE
	_tween = create_tween()
	_tween.tween_property(_pic, "scale", Vector2(1.07, 1.07), PAN_TIME)


func _done() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	finished.emit()
	queue_free()


static func _box(bg: Color, border: Color, bw: int = 2, radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 16.0
	sb.content_margin_bottom = 16.0
	return sb
