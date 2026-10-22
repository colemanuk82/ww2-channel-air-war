extends Node
## Audio stub (autoload "AudioManager"). Stage 6 replaces the internals; keep this API.

# Per-category volumes live in GameState (saved with the other settings); these are the names the rest of the game uses.
var master_volume: float:
	get: return GameState.vol_master
	set(v): GameState.vol_master = clampf(v, 0.0, 1.0)
var fx_volume: float:                  # guns, explosions, flak, bombs, hits
	get: return GameState.vol_fx
	set(v): GameState.vol_fx = clampf(v, 0.0, 1.0)
var sfx_volume: float:                 # legacy name for fx_volume
	get: return GameState.vol_fx
	set(v): GameState.vol_fx = clampf(v, 0.0, 1.0)
var engine_volume: float:              # the player's engine drone
	get: return GameState.vol_engine
	set(v): GameState.vol_engine = clampf(v, 0.0, 1.0)
var radio_volume: float:               # radio calls, briefings, static and squelch
	get: return GameState.vol_radio
	set(v): GameState.vol_radio = clampf(v, 0.0, 1.0)
var music_volume: float:
	get: return GameState.vol_music
	set(v): GameState.vol_music = clampf(v, 0.0, 1.0)
var muted: bool = false


## Buses: Master <- SFX (all game sound; muted during the loading screen), Narration (briefings), Radio
## (made by the Radio autoload).
func _ready() -> void:
	for b in ["SFX", "Narration"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")


## Silence game sound (not the briefing narration), e.g. while the loading screen is up.
func set_game_sound_muted(m: bool) -> void:
	var i: int = AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_mute(i if i >= 0 else 0, m)


func play_sfx(_sfx_name: String, _position: Vector3 = Vector3.ZERO, _volume_db: float = 0.0) -> void:
	pass


func play_music(_track: String) -> void:
	pass


## Called by the aircraft each frame for the player: throttle 0..1, speed 0..1 of max.
func set_engine_state(_throttle: float, _speed_ratio: float) -> void:
	pass


func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(0, m)


## Procedural combat SFX (guns, cannon, explosion, flak, bomb_whistle, rocket, hit). Provided by FX/AudioSFX.
func play_proc_sfx(sfx_name: String, position: Vector3 = Vector3.ZERO, volume_db: float = 0.0) -> void:
	FX.sfx(sfx_name, position, volume_db)
