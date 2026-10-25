class_name GameMusic
extends AudioStreamPlayer
## Occasional in-flight music: after a few minutes of silence a random track from the IN-GAME MUSIC manager's
## playlist (res://assets/music/ingame/ plus any copies imported into user://music/ingame/) fades in gently,
## plays through, fades out at the end, then silence again before the next one (never the same track twice in a
## row, or in order when Shuffle is off). Waits while a briefing is being narrated. Added by main.gd for each
## sortie. The playlist and shuffle flag live in GameState (settings.cfg [music]); Options > Music edits them.

const DIR := "res://assets/music/ingame/"
const FADE_IN := 9.0
const FADE_OUT := 6.0
const FIRST_WAIT := Vector2(20.0, 55.0)     # silence before the first track (seconds, min..max)
const GAP := Vector2(35.0, 90.0)            # silence between tracks

var _tracks: Array = []
var _last: int = -1
var _shuffle: bool = true
var _wait: float = 0.0
var _fade: float = 0.0          # 0..1 envelope
var _stopping: bool = false
var _duck: float = 1.0          # 1 = full level, lowered while a voiced radio call plays
const DUCK_LEVEL := 0.3         # music level (x) during radio chatter


func _ready() -> void:
	bus = &"Master"
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("game_music")
	refresh_playlist()
	_wait = randf_range(FIRST_WAIT.x, FIRST_WAIT.y)
	finished.connect(func() -> void: _wait = randf_range(GAP.x, GAP.y))


## Re-read the playlist + shuffle flag from GameState (called at start and whenever Options changes them).
func refresh_playlist() -> void:
	_tracks = GameState.music_playlist("ingame")
	_shuffle = GameState.music_shuffle("ingame")


func current_track() -> String:
	if _last >= 0 and _last < _tracks.size():
		return String(_tracks[_last])
	return ""


func set_shuffle(on: bool) -> void:
	_shuffle = on


## Play a specific track now with a gentle fade-in (Options > Music "Play").
func play_path(path: String) -> void:
	var i: int = _tracks.find(path)
	if i < 0:
		return
	_stopping = false
	if playing:
		stop()
	stream = MenuMusic.load_track(String(_tracks[i]))
	if stream == null:
		return
	_last = i
	_fade = 0.0
	volume_db = linear_to_db(0.0001)
	play()
	_wait = 1.0e9      # set again when the track finishes


## Skip immediately (Options > Music "Next") - in-game music only ever picks the next track, so this just
## ends the current one and re-arms the pick.
func next_track(_dir: int = 1) -> void:
	if _tracks.is_empty():
		return
	_stopping = false
	if playing:
		stop()
	_wait = 0.0


## Fade the current track out and stay quiet (results screen, quit).
func fade_out_and_stop() -> void:
	_stopping = true


func _level() -> float:
	return clampf(AudioManager.music_volume * AudioManager.master_volume, 0.0, 1.0) * 0.75 * _duck


func _process(delta: float) -> void:
	# duck quickly when a voiced call starts, come back up slowly afterwards
	var want: float = DUCK_LEVEL if Radio.voice_active() else 1.0
	_duck = move_toward(_duck, want, delta * (6.0 if want < _duck else 0.7))
	if _tracks.is_empty():
		return
	if _stopping:
		_fade = maxf(_fade - delta / 3.0, 0.0)
		volume_db = linear_to_db(maxf(_level() * _fade, 0.0001))
		if _fade <= 0.0 and playing:
			stop()
		return
	if playing:
		var left: float = stream.get_length() - get_playback_position() if stream != null else 99.0
		var target: float = 0.0 if left < FADE_OUT else 1.0
		var rate: float = 1.0 / (FADE_OUT if target < _fade else FADE_IN)
		_fade = move_toward(_fade, target, delta * rate)
		volume_db = linear_to_db(maxf(_level() * _fade * _fade, 0.0001))   # squared: a gentle start
		return
	if GameState.paused or Radio.narrating() or AudioManager.muted:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	if _shuffle:
		var i: int = _bag_pick()
		_last = i
	else:
		_last = (_last + 1) % _tracks.size()
	var st: AudioStream = MenuMusic.load_track(String(_tracks[_last]))
	if st == null:
		_wait = randf_range(GAP.x, GAP.y)
		return
	stream = st
	_fade = 0.0
	volume_db = linear_to_db(0.0001)
	play()
	_wait = 1.0e9      # set again when the track finishes

## Shuffle bag: every track plays once, in a fresh random order, before any repeats (and the first track of a new
## bag is never the one that just played).
static var _bag: Array = []
static var _last_path: String = ""
func _bag_pick() -> int:
	if _bag.is_empty():
		for k in _tracks.size():
			_bag.append(k)
		_bag.shuffle()
		if _bag.size() > 1 and String(_tracks[int(_bag[_bag.size() - 1])]) == _last_path:
			var t: Variant = _bag[0]
			_bag[0] = _bag[_bag.size() - 1]
			_bag[_bag.size() - 1] = t
	var idx: int = int(_bag.pop_back()) % maxi(_tracks.size(), 1)
	_last_path = String(_tracks[idx])
	return idx
