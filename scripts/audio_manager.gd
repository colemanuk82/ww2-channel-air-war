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
	# cockpit view: the canopy and airframe cut the highs of everything outside (guns, flak, other engines)
	var si: int = AudioServer.get_bus_index("SFX")
	_cockpit_lp = AudioEffectLowPassFilter.new()
	_cockpit_lp.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(si, _cockpit_lp)
	_cockpit_fx = AudioServer.get_bus_effect_count(si) - 1
	AudioServer.set_bus_effect_enabled(si, _cockpit_fx, false)


var _cockpit_lp: AudioEffectLowPassFilter
var _cockpit_fx: int = -1
var _cockpit_k: float = 0.0


## Called every frame for the player with the current view: eases a low-pass over the game sound in the cockpit
## (about 3.2 kHz) and opens it again outside.
func set_cockpit(on: bool, delta: float) -> void:
	_cockpit_k = move_toward(_cockpit_k, 1.0 if on else 0.0, delta * 4.0)
	if _cockpit_lp == null or _cockpit_fx < 0:
		return
	var si: int = AudioServer.get_bus_index("SFX")
	var active: bool = _cockpit_k > 0.01
	if AudioServer.is_bus_effect_enabled(si, _cockpit_fx) != active:
		AudioServer.set_bus_effect_enabled(si, _cockpit_fx, active)
	_cockpit_lp.cutoff_hz = lerpf(16000.0, 3200.0, _cockpit_k)


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
