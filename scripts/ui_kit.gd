class_name UIKit
extends RefCounted
## Helpers and the shared look for code-built menus (start menu, pause, options, results) and the HUD.
## Art direction follows the painted menu artwork: smoke-dark panels, brass trim, cream text.

const TEXT := Color(0.95, 0.92, 0.82)
const TEXT_DIM := Color(0.78, 0.75, 0.66)
const ACCENT := Color(0.93, 0.74, 0.32)          # brass
const ACCENT_HOT := Color(1.0, 0.86, 0.5)
const RED := Color(0.78, 0.2, 0.16)              # roundel red
const PANEL := Color(0.055, 0.06, 0.055, 0.86)
const PANEL_EDGE := Color(0.62, 0.5, 0.27, 0.9)
const FIELD := Color(0.1, 0.105, 0.095, 0.95)

static var _font: Font
static var _font_bold: Font
static var _font_display: Font
static var _font_body: Font

const FONT_DIR := "res://assets/fonts/"


static func _bundled(file: String) -> Font:
	var p: String = FONT_DIR + file
	if ResourceLoader.exists(p):
		var f: Resource = load(p)
		if f is Font:
			return f as Font
	return null


## Heading / banner face: Barlow Condensed Bold with a little letter spacing (military stencil-ish signage feel).
static func display_font() -> Font:
	if _font_display == null:
		var base: Font = _bundled("BarlowCondensed-Bold.ttf")
		if base == null:
			_font_display = font(true)
		else:
			var fv := FontVariation.new()
			fv.base_font = base
			fv.spacing_glyph = 2
			_font_display = fv
	return _font_display


## Paragraph face for briefings and descriptions: Barlow Medium (slightly wider than the HUD face, easier to read in blocks).
static func body_font() -> Font:
	if _font_body == null:
		_font_body = _bundled("Barlow-Medium.ttf")
		if _font_body == null:
			_font_body = font(false)
	return _font_body


## UI / HUD font: bundled Barlow Condensed (SIL OFL, see assets/fonts), else Bahnschrift / Segoe UI / Arial.
static func font(bold: bool = false) -> Font:
	if bold and _font_bold != null:
		return _font_bold
	if not bold and _font != null:
		return _font
	var bundled: Font = _bundled("BarlowCondensed-Bold.ttf" if bold else "BarlowCondensed-SemiBold.ttf")
	if bundled != null:
		if bold:
			_font_bold = bundled
		else:
			_font = bundled
		return bundled
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Bahnschrift", "DIN Alternate", "Segoe UI", "Arial"])
	sf.font_weight = 700 if bold else 500
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	sf.hinting = TextServer.HINTING_LIGHT
	sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	sf.multichannel_signed_distance_field = false
	if bold:
		_font_bold = sf
	else:
		_font = sf
	return sf


static func label(text: String, size: int = 18, col: Color = TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 3)
	return l


## Big spaced-out heading with a brass rule under it.
static func heading(parent: Control, text: String, size: int = 30) -> Label:
	var l := label(text, size, ACCENT, true)
	l.add_theme_font_override("font", display_font())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	parent.add_child(rule())
	return l


## Thin brass divider.
static func rule(alpha: float = 0.55) -> Control:
	var c := ColorRect.new()
	c.color = Color(PANEL_EDGE, alpha)
	c.custom_minimum_size = Vector2(0, 2)
	return c


static func _box(bg: Color, border: Color, bw: int = 2, radius: int = 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func panel_style() -> StyleBoxFlat:
	var sb := _box(PANEL, PANEL_EDGE, 1, 2)
	sb.border_width_top = 3
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 18
	return sb


static func panel(parent: Control) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", panel_style())
	parent.add_child(pc)
	var m := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(k, 22)
	pc.add_child(m)
	# a tall panel scrolls instead of running off the screen (focus and the mouse wheel both scroll it)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	m.add_child(sc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	var fit := func() -> void:
		if not is_instance_valid(sc) or not sc.is_inside_tree():
			return
		var avail: float = sc.get_viewport().get_visible_rect().size.y - 90.0
		sc.custom_minimum_size.y = minf(vb.get_combined_minimum_size().y, maxf(avail, 160.0))
	vb.minimum_size_changed.connect(fit)
	fit.call_deferred()
	return vb


static func _style_button(b: Button, size: int, primary: bool) -> void:
	b.add_theme_font_override("font", font(true))
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT if not primary else Color(0.12, 0.09, 0.04))
	b.add_theme_color_override("font_hover_color", Color.WHITE if not primary else Color(0.05, 0.04, 0.02))
	b.add_theme_color_override("font_focus_color", Color.WHITE if not primary else Color(0.05, 0.04, 0.02))
	b.add_theme_color_override("font_pressed_color", ACCENT_HOT)
	var base_bg: Color = Color(0.13, 0.135, 0.12, 0.92) if not primary else ACCENT
	var hot_bg: Color = Color(0.22, 0.2, 0.15, 1.0) if not primary else ACCENT_HOT
	var n := _box(base_bg, Color(PANEL_EDGE, 0.55), 1)
	n.border_width_left = 4
	n.border_color = Color(PANEL_EDGE, 0.7)
	var h := _box(hot_bg, ACCENT, 1)
	h.border_width_left = 6
	var f := _box(hot_bg, ACCENT_HOT, 2)
	f.border_width_left = 6
	var p := _box(Color(0.3, 0.24, 0.1, 1.0), ACCENT, 1)
	p.border_width_left = 6
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("focus", f)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT if not primary else HORIZONTAL_ALIGNMENT_CENTER
	b.mouse_entered.connect(func() -> void:
		if b.focus_mode != Control.FOCUS_NONE:
			b.grab_focus())


static func button(text: String, on_press: Callable, size: int = 22, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	_style_button(b, size, primary)
	b.pressed.connect(on_press)
	return b


static func _style_option(ob: OptionButton, size: int) -> void:
	ob.add_theme_font_override("font", font())
	ob.add_theme_font_size_override("font_size", size)
	ob.add_theme_color_override("font_color", TEXT)
	ob.add_theme_color_override("font_hover_color", Color.WHITE)
	ob.add_theme_color_override("font_focus_color", Color.WHITE)
	ob.add_theme_stylebox_override("normal", _box(FIELD, Color(PANEL_EDGE, 0.35), 1))
	ob.add_theme_stylebox_override("hover", _box(Color(0.18, 0.17, 0.13, 1.0), ACCENT, 1))
	ob.add_theme_stylebox_override("focus", _box(Color(0.18, 0.17, 0.13, 1.0), ACCENT_HOT, 2))
	ob.add_theme_stylebox_override("pressed", _box(Color(0.25, 0.21, 0.12, 1.0), ACCENT, 1))
	var pm: PopupMenu = ob.get_popup()
	pm.add_theme_font_override("font", font())
	pm.add_theme_font_size_override("font_size", size)
	pm.add_theme_color_override("font_color", TEXT)
	pm.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.03))
	pm.add_theme_stylebox_override("panel", _box(Color(0.07, 0.075, 0.07, 0.98), PANEL_EDGE, 1))
	var hv := _box(ACCENT, ACCENT, 0)
	pm.add_theme_stylebox_override("hover", hv)
	ob.mouse_entered.connect(func() -> void: ob.grab_focus())


## Row with a left caption and an OptionButton; returns the OptionButton.
static func option_row(parent: Control, caption: String, items: Array, size: int = 18) -> OptionButton:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	parent.add_child(hb)
	var l := label(caption.to_upper(), size - 3, TEXT_DIM, true)
	l.custom_minimum_size = Vector2(150, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(l)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_option(ob, size)
	for it in items:
		ob.add_item(String(it))
	hb.add_child(ob)
	return ob


## Full-screen dimmer with a soft vignette (used behind pause / options / results).
static func dimmer(alpha: float = 0.55) -> Control:
	var c := ColorRect.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform float a = 0.55;\nvoid fragment(){ vec2 d = UV - 0.5; float v = smoothstep(0.25, 0.85, length(d * vec2(1.3, 1.0))); COLOR = vec4(0.02, 0.02, 0.015, a + v * 0.35); }"
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("a", alpha)
	c.material = m
	return c
