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
const FIRST_WAIT := Vector2(20.0, 55.0)     # cap on the silence before the first track (seconds, min..max)
const GAP_SCATTER := Vector2(0.75, 1.25)    # the Options > Music gap, varied by this much so it never feels metronomic

var _tracks: Array = []
var _last: int = -1
var _shuffle: bool = true
var _wait: float = 0.0
var _fade: float = 0.0          # 0..1 envelope
var _stopping: bool = false
var _duck: float = 1.0          # 1 = full level, lowered while a voiced radio call plays
const DUCK_LEVEL := 0.3         # music level (x) during radio chatter
const COMBAT_RANGE := 4500.0    # an enemy aircraft this close (m) puts the music in its combat state
const CALM_AFTER := 40.0        # seconds without combat before a track that combat started fades out
var combat: float = 0.0         # 0 calm .. 1 in a fight (eased): read by the HUD / tests
var _combat_raw: float = 0.0
var _scan_t: float = 0.0
var _calm_t: float = 0.0
var _combat_track: bool = false  # the playing track was brought in by combat (so calm may fade it out)
var _soft_stop: bool = false     # the current fade-out is the calm one: the player starts again after it


func _ready() -> void:
	bus = &"Master"
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("game_music")
	refresh_playlist()
	_wait = _first_wait()
	finished.connect(func() -> void: _wait = _gap_wait())


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
	return clampf(AudioManager.music_volume * AudioManager.master_volume, 0.0, 1.0) * lerpf(0.68, 0.9, combat) * _duck


## How close the fight is: 1 when an enemy aircraft is within COMBAT_RANGE of the player (or the player is
## shooting), 0 when none is. Scanned twice a second.
func _scan_combat() -> float:
	var pl: Node = GroundKit.player_node()
	if pl == null or not is_instance_valid(pl) or not (pl is Aircraft):
		return 0.0
	var pa: Aircraft = pl
	if pa.cmd_fire:
		return 1.0
	var best: float = 1.0e12
	for n in get_tree().get_nodes_in_group("aircraft"):
		var a: Aircraft = n as Aircraft
		if a == null or a == pa or a.state != Aircraft.State.ALIVE or String(a.team) == String(pa.team):
			continue
		best = minf(best, a.global_position.distance_squared_to(pa.global_position))
	return clampf(1.0 - (sqrt(best) - COMBAT_RANGE * 0.5) / (COMBAT_RANGE * 0.5), 0.0, 1.0)


func _process(delta: float) -> void:
	# duck quickly when a voiced call starts, come back up slowly afterwards
	var want: float = DUCK_LEVEL if Radio.voice_active() else 1.0
	_duck = move_toward(_duck, want, delta * (6.0 if want < _duck else 0.7))
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.5
		_combat_raw = _scan_combat()
	combat = move_toward(combat, _combat_raw, delta * (0.8 if _combat_raw > combat else 0.08))
	_calm_t = 0.0 if combat > 0.15 else _calm_t + delta
	if combat > 0.5 and not playing and not _stopping and _wait > 3.0:
		_wait = 3.0                 # a fight brings the music in soon
		_combat_track = true
	if playing and _combat_track and _calm_t > CALM_AFTER and not _stopping:
		_combat_track = false
		_stopping = true            # back to quiet once the fight is well over (a soft stop: music comes back later)
		_soft_stop = true
		_wait = _gap_wait()
	if _tracks.is_empty():
		return
	if _stopping:
		_fade = maxf(_fade - delta / 3.0, 0.0)
		volume_db = linear_to_db(maxf(_level() * _fade, 0.0001))
		if _fade <= 0.0 and playing:
			stop()
			if _soft_stop:
				_soft_stop = false
				_stopping = false
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
		_wait = _gap_wait()
		return
	stream = st
	_fade = 0.0
	volume_db = linear_to_db(0.0001)
	play()
	_wait = 1.0e9      # set again when the track finishes

## Silence before the next track comes in: Options > Music "Pause between tracks" (GameState.music_gap), with the
## first track of a sortie arriving sooner than the rest. 0 plays them back to back.
func _first_wait() -> float:
	var g: float = GameState.music_gap
	return randf_range(minf(FIRST_WAIT.x, g), minf(FIRST_WAIT.y, g))


func _gap_wait() -> float:
	var g: float = GameState.music_gap
	return randf_range(g * GAP_SCATTER.x, g * GAP_SCATTER.y)


## Shuffle bag: every track plays once, in a fresh random order, before any repeats (and the first track of a new
## bag is never the one that just played).
static var _bag: Array = []
static var _last_path: String = ""
func _bag_pick() -> int:
	if _bag.is_empty():
		for k in _tracks.size():
			_bag.append(k)
		_bag.shuffle()
		# tracks heard recently (this launch or the last ones) go to the bottom of the bag: they come round last
		var recent: Array = GameState.music_recent.get("ingame", [])
		var fresh: Array = []
		var heard: Array = []
		for k in _bag:
			if recent.has(String(_tracks[int(k)])) or String(_tracks[int(k)]) == _last_path:
				heard.append(k)
			else:
				fresh.append(k)
		_bag = heard + fresh          # pop_back takes from the end: the fresh ones first
	var idx: int = int(_bag.pop_back()) % maxi(_tracks.size(), 1)
	_last_path = String(_tracks[idx])
	GameState.note_music_played("ingame", _last_path)
	return idx
