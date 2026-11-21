class_name PixelArt
extends CanvasLayer
## Pixel-art mode (PROMPT-pixel-art.md, phase 1): the screen pass that turns the finished 3D frame
## into a 32-colour, dithered, ink-outlined image on a coarse pixel grid.
##
## How it works: a full-screen ColorRect on layer 5 - above the 3D frame, below the HUD (layer 10) -
## reads `hint_screen_texture` and runs shaders/pixel/pixel_art.gdshader. The 3D frame is crushed onto
## `native_size` cells by sampling each cell's centre, so the whole scene resolves to that many hard
## pixels; the HUD keeps its own resolution on top, which is how Slotbound's chunky UI reads.
##
## Why it is cheap and safe: it does not touch the world, the materials or the cameras, so it cannot
## regress the flight game. Turning it off is one uniform, and `enabled = 0` makes the pass a straight
## copy. The render-state changes it needs (no upscaler, no MSAA, no SSAO) live in
## GameState.apply_graphics() so there is one source of truth for graphics settings.
##
##   var px := PixelArt.new()
##   add_child(px)                       # layers itself, hidden until set_enabled(true)
##   px.set_enabled(true)                # or GameState.art_style == 1
##   px.set_native(Vector2i(480, 270))   # 0.1 in the program file
##
## Debug: main.gd parses --pixel (turn on) and --pixel-native=WxH (grid size).

const SHADER_PATH := "res://shaders/pixel/pixel_art.gdshader"
const PALETTE_PATH := "res://assets/textures/pixel/palette.png"

## The render grid. 480x270 is Slotbound's own resolution; the others are there for taste.
const NATIVE_PRESETS: Array = [Vector2i(320, 180), Vector2i(400, 225), Vector2i(480, 270), Vector2i(640, 360)]
const NATIVE_DEFAULT: int = 2                    # 480x270

const DITHER_DEFAULT: float = 0.6      # subtle: a strong dither on 32 colours reads as noise
const EDGE_DEFAULT: float = 0.85       # ink outlines (Slotbound's defining trait), slightly soft
const EDGE_THRESHOLD: float = 0.22     # palette distance before a boundary gets ink; higher = less speckle

var enabled: bool = false

var _rect: ColorRect = null
var _mat: ShaderMaterial = null
var _native: Vector2i = NATIVE_PRESETS[NATIVE_DEFAULT]
var _palette: Texture2D = null
var _palette_from: Array = []        # the sRGB 0-1 colours, for the tests


func _init() -> void:
	layer = 5                        # above the 3D frame, below the HUD (which is 10)
	follow_viewport_enabled = false


func _ready() -> void:
	_build()
	set_enabled(enabled)


func _build() -> void:
	if _rect != null:
		return
	var sh: Shader = load(SHADER_PATH) as Shader
	if sh == null:
		push_warning("PixelArt: shader missing at %s" % SHADER_PATH)
		return
	_palette = _load_palette()
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	if _palette != null:
		_mat.set_shader_parameter("palette_tex", _palette)
	else:
		push_warning("PixelArt: palette missing at %s - run tools/make_pixel_palette.py" % PALETTE_PATH)
	_rect = ColorRect.new()
	_rect.name = "PixelPass"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)
	_apply()


## The palette image, or null when it has not been generated (the pass still works, it just quantises
## towards whatever the fallback palette is).
func _load_palette() -> Texture2D:
	if not ResourceLoader.exists(PALETTE_PATH):
		return null
	var tex: Texture2D = ResourceLoader.load(PALETTE_PATH) as Texture2D
	_palette_from = []
	if tex != null:
		var img: Image = tex.get_image()
		if img != null:
			img.convert(Image.FORMAT_RGB8)
			for x in img.get_width():
				_palette_from.append(img.get_pixel(x, 0))
	return tex


func set_enabled(on: bool) -> void:
	enabled = on
	if _rect == null:
		return
	_rect.visible = on
	_apply()


func set_native(size: Vector2i) -> void:
	_native = Vector2i(maxi(size.x, 64), maxi(size.y, 36))
	_apply()


func set_native_preset(index: int) -> void:
	set_native(NATIVE_PRESETS[clampi(index, 0, NATIVE_PRESETS.size() - 1)])


func native_size() -> Vector2i:
	return _native


func native_preset_index() -> int:
	return NATIVE_PRESETS.find(_native)


func set_dither(v: float) -> void:
	_mat.set_shader_parameter("dither", clampf(v, 0.0, 1.0))


func set_edge(v: float) -> void:
	_mat.set_shader_parameter("edge", clampf(v, 0.0, 1.0))


## Push the grid size and the viewport size the shader needs into the material.
func _apply() -> void:
	if _mat == null:
		return
	var win: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	if win.x < 1.0:
		win = Vector2(1920.0, 1080.0)
	_mat.set_shader_parameter("enabled", enabled)
	_mat.set_shader_parameter("native_size", Vector2(_native))
	_mat.set_shader_parameter("out_size", win)
	_mat.set_shader_parameter("dither", DITHER_DEFAULT)
	_mat.set_shader_parameter("edge", EDGE_DEFAULT)
	_mat.set_shader_parameter("edge_threshold", EDGE_THRESHOLD)


func _process(_delta: float) -> void:
	# A window resize changes out_size; only re-push when it actually moved.
	if _mat == null or not enabled:
		return
	var win: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	if win.distance_to(_mat.get_shader_parameter("out_size")) > 0.5:
		_mat.set_shader_parameter("out_size", win)


## The palette as sRGB colours (the tests check the count and that every entry is a valid colour).
func palette_colours() -> Array:
	return _palette_from.duplicate()


## Render the current frame to `path` at an integer nearest upscale (debug / shots).
## `scale` is the pixel multiple; 4 gives a 1920x1080 image from a 480x270 grid.
func save_upscaled(path: String, scale: int = 4) -> bool:
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		return false
	img.resize(_native.x * scale, _native.y * scale, Image.INTERPOLATE_NEAREST)
	var err: Error = img.save_png(path)
	print("PIXEL SHOT %s (%dx%d from %dx%d, scale %d) err=%d" % [path, img.get_width(), img.get_height(),
		_native.x, _native.y, scale, err])
	return err == OK
