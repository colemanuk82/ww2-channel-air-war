class_name MenuBackground
extends Control
## Full-screen menu background that cycles through the paintings in res://assets/menu/: each one slowly
## pans and zooms ("Ken Burns"), then crossfades to the next. Any .png/.jpg/.webp in that folder is used,
## sorted by filename. If the folder is empty the menu falls back to the live 3D menu camera.

const DIR := "res://assets/menu/"
const EXTS := ["png", "jpg", "jpeg", "webp"]
const HOLD := 16.0         # seconds each painting is shown (including the fade)
const FADE := 5.0
const PAN_ROOM := 0.12     # spare room around each painting, as a fraction of the screen, to pan into

var _a: TextureRect
var _b: TextureRect
var _imgs: Array = []
var _i: int = 0
var _t: float = 0.0
var _fading: bool = false
var _motion_a: Vector2 = Vector2.ZERO   # pan direction of the painting currently on screen
var _motion_b: Vector2 = Vector2.ZERO
var _age_a: float = 0.0
var _age_b: float = 0.0
var animate: bool = true   # false = a still painting (the loading screen)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_a = _mk()
	_b = _mk()
	_imgs = discover()
	if _imgs.is_empty():
		visible = false
		set_process(false)
		return
	_i = randi() % _imgs.size()
	_a.texture = load(_imgs[_i])
	_request_next()
	_a.modulate.a = 1.0
	_b.modulate.a = 0.0
	_motion_a = _rand_dir()
	resized.connect(func() -> void:
		_fit(_a)
		_fit(_b)
		_place(_a, _age_a, _motion_a)
		_place(_b, _age_b, _motion_b))
	_fit(_a)
	_fit(_b)
	_place(_a, 0.0, _motion_a)
	if not animate:
		set_process(false)


func _mk() -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)
	return tr


func _rand_dir() -> Vector2:
	var ang: float = randf() * TAU
	return Vector2(cos(ang), sin(ang) * 0.6)


## Lists the paintings. An exported build has no source images in the folder, only "<name>.png.import"
## remap files, so those are accepted too (the remapped resource loads by its original path).
static func discover() -> Array:
	var out: Array = []
	var d: DirAccess = DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			var name: String = f
			if name.ends_with(".import"):
				name = name.trim_suffix(".import")
			elif name.ends_with(".remap"):
				name = name.trim_suffix(".remap")
			if name.begins_with(".") or not EXTS.has(name.get_extension().to_lower()):
				continue
			var path: String = DIR + name
			if not out.has(path) and ResourceLoader.exists(path):
				out.append(path)
	out.sort()
	return out


## Centre a painting. The screen stays still: paintings only fade out and in. Sized once, so nothing relayouts per frame.
func _place(tr: TextureRect, _age: float, _dir: Vector2) -> void:
	tr.position = -size * PAN_ROOM * 0.5


## Decode the next painting on a background thread during the hold, so the crossfade never stalls on a disk read.
func _request_next() -> void:
	if _imgs.size() < 2:
		return
	var nxt: String = _imgs[(_i + 1) % _imgs.size()]
	if not ResourceLoader.has_cached(nxt) and ResourceLoader.load_threaded_get_status(nxt) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(nxt)


func _take(path: String) -> Texture2D:
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
		return ResourceLoader.load_threaded_get(path) as Texture2D
	return load(path) as Texture2D


func _fit(tr: TextureRect) -> void:
	tr.size = size * (1.0 + PAN_ROOM)


func _process(delta: float) -> void:
	_t += delta
	_age_a += delta
	_place(_a, _age_a, _motion_a)
	if _imgs.size() < 2:
		return
	if not _fading and _t >= HOLD - FADE:
		_fading = true
		_t = 0.0
		_i = (_i + 1) % _imgs.size()
		_b.texture = _take(_imgs[_i])
		_age_b = 0.0
		move_child(_b, get_child_count() - 1)   # once per crossfade, not every frame
		_motion_b = _rand_dir()
	if _fading:
		_age_b += delta
		_place(_b, _age_b, _motion_b)
		var k: float = clampf(_t / FADE, 0.0, 1.0)
		_a.modulate.a = 1.0 - smoothstep(0.0, 0.5, k)   # fade the old painting out...
		_b.modulate.a = smoothstep(0.5, 1.0, k)         # ...then fade the new one in
		if _t >= FADE:
			_fading = false
			_t = 0.0
			var tmp := _a
			_a = _b
			_b = tmp
			_age_a = _age_b
			_motion_a = _motion_b
			_b.modulate.a = 0.0
			_request_next()
