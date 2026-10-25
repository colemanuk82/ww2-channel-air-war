class_name MenuMusic
extends AudioStreamPlayer
## Start-menu music. Plays the MENU MUSIC manager's playlist - the tracks that ship in res://assets/music/
## plus any copies the player imported into user://music/menu/ - in random order (never the same one twice in a
## row), or in playlist order when Shuffle is off. The playlist, the shuffle flag and the chosen track live in
## GameState (settings.cfg [music]) and are edited on Options > Music.
## It is a child of the start menu, so it stops when the menu closes and loading starts.

const DIR := "res://assets/music/"
const USER_DIR := "user://music/menu/"
const EXTS := ["mp3", "ogg", "wav"]

var _tracks: Array = []
var _last: int = -1
var _shuffle: bool = true


func _ready() -> void:
	bus = &"Master"
	add_to_group("menu_music")
	refresh_playlist()
	finished.connect(_next)
	var want: String = GameState.music_current("menu")
	if not _shuffle and want != "" and _tracks.has(want):     # Options > Music picked a specific opener
		play_path(want)
	else:
		_next()


## Re-read the playlist + shuffle flag from GameState (called at start and whenever Options changes them).
func refresh_playlist() -> void:
	_tracks = GameState.music_playlist("menu")
	_shuffle = GameState.music_shuffle("menu")


func _process(_delta: float) -> void:
	if playing:     # follow the Music slider while a track plays
		volume_db = linear_to_db(clampf(AudioManager.music_volume * AudioManager.master_volume, 0.01, 1.0))


func current_track() -> String:
	if _last >= 0 and _last < _tracks.size():
		return String(_tracks[_last])
	return ""


func set_shuffle(on: bool) -> void:
	_shuffle = on


## Play a specific track now (Options > Music "Play").
func play_path(path: String) -> void:
	var i: int = _tracks.find(path)
	if i < 0:
		return
	_last = i
	_start(i)


## Step to the next (dir = 1) or previous (dir = -1) track; Next respects shuffle.
func next_track(dir: int = 1) -> void:
	if _tracks.is_empty():
		return
	if _shuffle and dir > 0:
		_next()
		return
	var i: int = (maxi(_last, 0) + dir) % _tracks.size()
	if i < 0:
		i += _tracks.size()
	_last = i
	_start(i)


func _next() -> void:
	if _tracks.is_empty() or AudioManager.muted:
		return
	if _shuffle:
		var i: int = _bag_pick()
		_last = i
	else:
		_last = (_last + 1) % _tracks.size()
	_start(_last)


func _start(i: int) -> void:
	var st: AudioStream = load_track(String(_tracks[i]))
	if st == null:
		return
	stream = st
	volume_db = linear_to_db(clampf(AudioManager.music_volume * AudioManager.master_volume, 0.01, 1.0))
	play()


## Audio files in a folder (exported builds only list "<name>.import" remaps, which load by the original path).
static func discover_in(dir: String) -> Array:
	var out: Array = []
	var d: DirAccess = DirAccess.open(dir)
	if d:
		for f in d.get_files():
			var n: String = f.trim_suffix(".import").trim_suffix(".remap")
			var path: String = dir + n
			if EXTS.has(n.get_extension().to_lower()) and not out.has(path) and ResourceLoader.exists(path):
				out.append(path)
	out.sort()
	return out


## Same as discover_in but for user:// folders, whose files have no imported resource to test.
static func discover_user(dir: String) -> Array:
	var out: Array = []
	var d: DirAccess = DirAccess.open(dir)
	if d:
		for f in d.get_files():
			var n: String = f.trim_suffix(".import").trim_suffix(".remap")
			var path: String = dir + n
			if EXTS.has(n.get_extension().to_lower()) and not out.has(path) and FileAccess.file_exists(path):
				out.append(path)
	out.sort()
	return out


## Load a track from anywhere: shipped res:// tracks go through the resource system; imported user:// files
## are decoded straight from their bytes (they have no imported resource).
static func load_track(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	match path.get_extension().to_lower():
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			return mp3
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"wav":
			return AudioStreamWAV.load_from_buffer(bytes)
	return null


## Folder an imported track for a manager is copied into ("menu" or "ingame").
static func user_dir(which: String) -> String:
	return "user://music/ingame/" if which == "ingame" else "user://music/menu/"


## Copy an audio file the player picked into user://music/<manager>/ and return its resource path ("" on failure).
static func import_track(which: String, src: String) -> String:
	var ext: String = src.get_extension().to_lower()
	if not EXTS.has(ext):
		return ""
	var dir: String = user_dir(which)
	DirAccess.make_dir_recursive_absolute(dir)
	var base: String = src.get_file()
	var dst: String = dir + base
	var n: int = 1
	while FileAccess.file_exists(dst):
		dst = "%s%s_%d.%s" % [dir, base.get_basename(), n, ext]
		n += 1
	if DirAccess.copy_absolute(src, dst) != OK:
		return ""
	return dst


## True for a track the player imported (lives under user://), i.e. safe to delete from disk.
static func is_imported(path: String) -> bool:
	return path.begins_with("user://")


## Delete an imported copy from disk. Shipped tracks are never touched (returns false).
static func delete_track(path: String) -> bool:
	if not is_imported(path) or not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK

## Shuffle bag: every track plays once, in a fresh random order, before any repeats (and the first track of a new
## bag is never the one that just played).
var _bag: Array = []
func _bag_pick() -> int:
	if _bag.is_empty():
		for k in _tracks.size():
			_bag.append(k)
		_bag.shuffle()
		if _bag.size() > 1 and int(_bag[_bag.size() - 1]) == _last:
			var t: Variant = _bag[0]
			_bag[0] = _bag[_bag.size() - 1]
			_bag[_bag.size() - 1] = t
	return int(_bag.pop_back()) % maxi(_tracks.size(), 1)
