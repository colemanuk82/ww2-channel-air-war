class_name AudioSFX
extends Node
## Procedural SFX (no assets): guns, cannon, explosion, flak, bomb whistle, rocket, hit ping, engine drone.
## Streams are generated lazily as AudioStreamWAV and played through a small AudioStreamPlayer3D pool.
## Owned by the FX autoload: FX.sfx("gun", pos).

const RATE := 22050
const POOL := 28
## Sounds nearer the listener than this skip the per-name rate gate: a close flak burst or hit must never be dropped
## because a far one played a moment earlier.
const NEAR_BYPASS := 450.0

## Engine voices. base/pulse_hz must be even whole numbers (the loop is 0.5 s, so cycles stay whole and it loops
## cleanly). harm = number of harmonics, roll = harmonic roll-off, rasp = high mechanical hash, pulse = firing-order
## throb depth, whine = turbine tone (jets), db = loudness trim, plo/phi = pitch range from idle to full throttle.
const ENGINES := {
	"merlin": {"base": 84, "harm": 8, "roll": 1.0, "rasp": 0.02, "pulse": 0.15, "pulse_hz": 42, "db": 0.0, "plo": 0.65, "phi": 1.7},
	"griffon": {"base": 80, "harm": 12, "roll": 0.9, "rasp": 0.05, "pulse": 0.13, "pulse_hz": 40, "db": 1.5, "plo": 0.62, "phi": 1.58},
	"napier": {"base": 96, "harm": 12, "roll": 0.6, "rasp": 0.12, "pulse": 0.3, "pulse_hz": 48, "db": 3.0, "plo": 0.7, "phi": 1.8},
	"db601": {"base": 76, "harm": 10, "roll": 0.9, "rasp": 0.06, "pulse": 0.1, "pulse_hz": 38, "db": 0.0, "plo": 0.65, "phi": 1.65},
	"db605": {"base": 72, "harm": 11, "roll": 0.85, "rasp": 0.07, "pulse": 0.12, "pulse_hz": 36, "db": 1.0, "plo": 0.62, "phi": 1.62},
	"jumo211": {"base": 70, "harm": 9, "roll": 1.0, "rasp": 0.04, "pulse": 0.2, "pulse_hz": 35 * 2, "db": 0.0, "plo": 0.6, "phi": 1.5},
	"allison": {"base": 90, "harm": 7, "roll": 1.1, "rasp": 0.03, "pulse": 0.1, "pulse_hz": 30, "db": -1.0, "plo": 0.7, "phi": 1.75},
	"radial_bmw": {"base": 54, "harm": 6, "roll": 0.7, "rasp": 0.08, "pulse": 0.5, "pulse_hz": 26, "db": 1.0, "plo": 0.6, "phi": 1.45},
	"radial_pw": {"base": 46, "harm": 6, "roll": 0.6, "rasp": 0.06, "pulse": 0.55, "pulse_hz": 22, "db": 2.0, "plo": 0.6, "phi": 1.4},
	"radial_mercury": {"base": 58, "harm": 6, "roll": 0.7, "rasp": 0.07, "pulse": 0.45, "pulse_hz": 28, "db": 1.0, "plo": 0.6, "phi": 1.5},
	"gipsy": {"base": 104, "harm": 7, "roll": 0.8, "rasp": 0.05, "pulse": 0.22, "pulse_hz": 34, "db": -4.0, "plo": 0.7, "phi": 1.55},   # DH Gipsy Six: a quiet inverted in-line
	"jet": {"base": 30, "harm": 3, "roll": 1.0, "rasp": 0.7, "pulse": 0.05, "pulse_hz": 12, "whine": 0.18, "db": 2.0, "plo": 0.5, "phi": 1.6},
}

## Gun voices, one shot each: dur / lp / decay / thump_hz / thump_amt feed _noise_burst, db trims loudness.
const GUNS := {
	"browning303": {"dur": 0.07, "lp": 0.5, "decay": 60.0, "hz": 150.0, "amt": 0.35, "db": -2.0},
	"hispano20": {"dur": 0.16, "lp": 0.22, "decay": 20.0, "hz": 75.0, "amt": 0.85, "db": 1.0},
	"browning50": {"dur": 0.11, "lp": 0.3, "decay": 38.0, "hz": 95.0, "amt": 0.7, "db": 0.0},
	"mg17": {"dur": 0.06, "lp": 0.65, "decay": 70.0, "hz": 200.0, "amt": 0.25, "db": -3.0},
	"mg151": {"dur": 0.14, "lp": 0.24, "decay": 24.0, "hz": 85.0, "amt": 0.75, "db": 0.0},
	"mk108": {"dur": 0.2, "lp": 0.16, "decay": 14.0, "hz": 55.0, "amt": 1.0, "db": 3.0},
	"mg_defensive": {"dur": 0.07, "lp": 0.55, "decay": 65.0, "hz": 170.0, "amt": 0.3, "db": -4.0},
}

var enabled: bool = true
var engine_enabled: bool = true
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer3D] = []
var _next: int = 0
var _last_play: Dictionary = {}
var _slot_loud: PackedFloat32Array = PackedFloat32Array()   # estimated loudness (dB at the listener) of what each pool slot is playing
var _engine: AudioStreamPlayer
var _engine_key: String = ""
var _wind_lo: AudioStreamPlayer
var _wind_hi: AudioStreamPlayer
var _wind_gust: float = 0.0
var _siren: AudioStreamPlayer = null
var _flat: Array[AudioStreamPlayer] = []
var _flat_next: int = 0


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 2500.0
		p.unit_size = 90.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.bus = _bus()
		add_child(p)
		_players.append(p)


func _bus() -> StringName:
	return &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"


func _vol_db(engine_bus: bool = false) -> float:
	var v: float = 1.0
	var am: Node = get_node_or_null("/root/AudioManager")
	if am:
		v = float(am.get("engine_volume" if engine_bus else "fx_volume")) * float(am.get("master_volume"))
		if am.get("muted"):
			v = 0.0
	return linear_to_db(maxf(v, 0.0001))


func play(sfx_name: String, pos: Vector3, volume_db: float = 0.0, min_interval: float = 0.0) -> void:
	if not enabled or _players.is_empty():
		return
	var now: float = Time.get_ticks_msec() * 0.001
	var dist: float = _listener_dist(pos)
	if min_interval > 0.0 and dist > NEAR_BYPASS and now - float(_last_play.get(sfx_name, -10.0)) < min_interval:
		return
	var s: AudioStream = _stream(sfx_name)
	if s == null:
		return
	var vol: float = volume_db + _vol_db() + _sfx_trim(sfx_name)
	# how loud it will actually be at the listener (inverse-distance falloff past the unit size)
	var loud: float = vol - 20.0 * log(maxf(dist / 90.0, 1.0)) / log(10.0)
	var slot: int = _pick_slot(loud)
	if slot < 0:
		return           # every voice is busy with something louder
	_last_play[sfx_name] = now
	var p: AudioStreamPlayer3D = _players[slot]
	p.stream = s
	p.global_position = pos
	p.volume_db = vol
	p.pitch_scale = randf_range(0.92, 1.08)
	p.play()
	_slot_loud[slot] = loud


## Distance from the listening camera (0 when there is none, so headless runs treat every sound as near).
func _listener_dist(pos: Vector3) -> float:
	var vp: Viewport = get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp != null else null
	if cam == null:
		return 0.0
	return cam.global_position.distance_to(pos)


## A free voice if there is one, else steal the quietest playing voice - but only if the new sound is louder.
## Plain round-robin let a barrage of far flak or a dogfight's gunfire cut off the one burst right beside you.
func _pick_slot(loud: float) -> int:
	if _slot_loud.size() != _players.size():
		_slot_loud.resize(_players.size())
		_slot_loud.fill(-200.0)
	var quiet_i: int = -1
	var quiet_v: float = 1.0e9
	for k in _players.size():
		var i: int = (_next + k) % _players.size()
		if not _players[i].playing:
			_next = (i + 1) % _players.size()
			return i
		if _slot_loud[i] < quiet_v:
			quiet_v = _slot_loud[i]
			quiet_i = i
	if loud >= quiet_v:
		return quiet_i
	return -1


## Engine drone for the player aircraft. throttle 0..1, speed_ratio 0..1, profile = key of ENGINES,
## count = number of engines (extra engines add detuned voices, so twins and heavies beat and throb).
func engine(throttle: float, speed_ratio: float, profile: String = "merlin", count: int = 1) -> void:
	if not engine_enabled:
		return
	var e: Dictionary = ENGINES.get(profile, ENGINES["merlin"])
	var key: String = _engine_stream_key(profile, count)
	if _engine == null:
		_engine = AudioStreamPlayer.new()
		_engine.bus = _bus()
		add_child(_engine)
	if key != _engine_key:
		_engine_key = key
		_engine.stream = _stream("engine:" + key)
		_engine.play()
	_engine.pitch_scale = lerpf(float(e["plo"]), float(e["phi"]), clampf(throttle * 0.8 + speed_ratio * 0.2, 0.0, 1.0))
	_engine.volume_db = lerpf(-24.0, -13.0, throttle) + float(e["db"]) + _vol_db(true)
	if not _engine.playing:
		_engine.play()


func _engine_stream_key(profile: String, count: int) -> String:
	var voices: int = 1 if count <= 1 else (2 if count <= 3 else 3)
	return "%s:%d" % [profile if ENGINES.has(profile) else "merlin", voices]


## Positional engine for other aircraft (AI planes, wingmen). Add the result as a child of the aircraft.
func make_engine_player(profile: String, count: int) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _stream("engine:" + _engine_stream_key(profile, count))
	p.bus = _bus()
	p.max_distance = 3200.0
	p.unit_size = 70.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	return p


func update_engine_player(p: AudioStreamPlayer3D, throttle: float, speed_ratio: float, profile: String) -> void:
	var e: Dictionary = ENGINES.get(profile, ENGINES["merlin"])
	p.pitch_scale = lerpf(float(e["plo"]), float(e["phi"]), clampf(throttle * 0.8 + speed_ratio * 0.2, 0.0, 1.0))
	p.volume_db = lerpf(-20.0, -9.0, throttle) + float(e["db"]) + _vol_db() if enabled and engine_enabled else -80.0


func _sfx_trim(sfx_name: String) -> float:
	if sfx_name.begins_with("gun:"):
		var g: Dictionary = GUNS.get(sfx_name.substr(4), {})
		return float(g.get("db", 0.0))
	return 0.0


## Wind / slipstream for the player. speed_ratio 0..1 of top speed, wind_mps = local wind, turb 0..1.
## Two looped noise layers: a low rush and a high hiss/whistle that only builds at speed. Gusts modulate both.
## Air-raid warning siren: looped under the sky war while a raid is on or expected nearby. level 0..1 sets how loud
## it is (0 stops it); the caller scales it with how close the raid is.
func siren(level: float) -> void:
	if level <= 0.001:
		if _siren != null and _siren.playing:
			_siren.stop()
		return
	if _siren == null:
		_siren = AudioStreamPlayer.new()
		_siren.stream = _stream("siren")
		_siren.bus = _bus()
		add_child(_siren)
	_siren.volume_db = lerpf(-30.0, -10.0, sqrt(clampf(level, 0.0, 1.0))) + _vol_db()
	if not _siren.playing:
		_siren.play()


func wind(speed_ratio: float, wind_mps: float, turb: float, cockpit: bool, on_ground: bool) -> void:
	if not enabled:
		return
	if _wind_lo == null:
		_wind_lo = AudioStreamPlayer.new()
		_wind_lo.stream = _stream("wind_lo")
		_wind_lo.bus = _bus()
		add_child(_wind_lo)
		_wind_lo.play()
		_wind_hi = AudioStreamPlayer.new()
		_wind_hi.stream = _stream("wind_hi")
		_wind_hi.bus = _bus()
		add_child(_wind_hi)
		_wind_hi.play()
	# airflow felt = airspeed, plus a little ambient rustle from the real wind (matters on the ground)
	var sr: float = maxf(clampf(speed_ratio, 0.0, 1.4), clampf(wind_mps / 70.0, 0.0, 0.5) if on_ground else 0.0)
	var t: float = Time.get_ticks_msec() * 0.001
	var gust: float = (sin(t * 1.3) * 0.5 + sin(t * 3.1 + 1.0) * 0.3 + sin(t * 7.3) * 0.2) * turb
	_wind_gust = lerpf(_wind_gust, gust, 0.2)
	var cab: float = -4.0 if cockpit else 0.0     # canopy muffles it a little
	var lo_db: float = lerpf(-66.0, -34.0, pow(clampf(sr, 0.0, 1.0), 1.25)) + _wind_gust * 3.0 + cab
	var hi_db: float = lerpf(-88.0, -43.0, pow(clampf(sr, 0.0, 1.2), 2.4)) + _wind_gust * 3.0 + cab
	_wind_lo.volume_db = lo_db + _vol_db()
	_wind_lo.pitch_scale = lerpf(0.62, 1.35, clampf(sr, 0.0, 1.0)) + _wind_gust * 0.05
	_wind_hi.volume_db = hi_db + _vol_db()
	_wind_hi.pitch_scale = lerpf(0.85, 1.55, clampf(sr, 0.0, 1.0))
	if not _wind_lo.playing:
		_wind_lo.play()
	if not _wind_hi.playing:
		_wind_hi.play()


## Non-positional one-shot for sounds heard from across a town (wardens' whistles, distant fire bells). The caller
## sets the loudness, so there is no distance falloff.
func flat(sfx_name: String, volume_db: float, pitch_jitter: float = 0.03) -> void:
	if not enabled:
		return
	var s: AudioStream = _stream(sfx_name)
	if s == null:
		return
	if _flat.is_empty():
		for i in 5:
			var fp := AudioStreamPlayer.new()
			fp.bus = _bus()
			add_child(fp)
			_flat.append(fp)
	var p: AudioStreamPlayer = _flat[_flat_next]
	_flat_next = (_flat_next + 1) % _flat.size()
	p.stream = s
	p.volume_db = volume_db + _vol_db()
	p.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.play()


## Something hit the player's own aircraft, heard through the airframe (no distance falloff). kind "bullet" is a
## machine-gun / cannon strike (clang and ring of metal), "blast" is flak bursting alongside (a hard thump and a
## patter of fragments). share is the hit as a fraction of the aircraft's health and sets how loud it is.
func player_hit(kind: String, share: float) -> void:
	if not enabled:
		return
	var now: float = Time.get_ticks_msec() * 0.001
	var key: String = "ph_" + kind
	if now - float(_last_play.get(key, -10.0)) < 0.045:
		return
	_last_play[key] = now
	var k: float = clampf(share * 12.0, 0.0, 1.0)
	if kind == "blast":
		flat("hit_frag:%d" % randi_range(0, 2), lerpf(-3.0, 6.0, k), 0.05)
	else:
		flat("hit_metal:%d" % randi_range(0, 2), lerpf(-5.0, 4.0, k), 0.06)


func stop_engine() -> void:
	if _engine:
		_engine.stop()


const PREWARM_NAMES := ["gun", "cannon", "hit", "flak", "flak_close", "hit_metal:0", "hit_metal:1", "hit_metal:2",
	"hit_frag:0", "hit_frag:1", "hit_frag:2", "siren", "whistle_warden", "fire_bell", "thunder", "explosion",
	"crash", "bomb_whistle", "rocket", "engine", "wind_lo", "wind_hi"]
var _pre_queue: Array = []


## Synthesise every sound ahead of use, one per frame from start-up (menu / load screen). Each one is computed
## sample by sample in GDScript - a 1.5-3 s explosion / crash / thunder took 50-120 ms - so a first explosion,
## raid bell or new aircraft engine no longer stalls the frame it plays in. (Main thread on purpose: building the
## AudioStreamWAV resources on worker threads crashed the exported build.)
func prewarm() -> void:
	if not _pre_queue.is_empty():
		return
	for n in PREWARM_NAMES:
		_pre_queue.append(n)
	for g in GUNS:
		_pre_queue.append("gun:" + g)
	for e in ENGINES:
		for v in [1, 2, 3]:
			_pre_queue.append("engine:%s:%d" % [e, v])
	set_process(true)


func _process(_delta: float) -> void:
	if _pre_queue.is_empty():
		set_process(false)
		return
	_stream(String(_pre_queue.pop_front()))


func _stream(n: String) -> AudioStream:
	if _streams.has(n):
		return _streams[n]
	var s: AudioStreamWAV = _synth(n)
	_streams[n] = s
	return s


## Builds one named stream (pure: safe on a worker thread; it touches no shared state).
func _synth(n: String) -> AudioStreamWAV:
	var s: AudioStreamWAV = null
	if n.begins_with("gun:"):
		var g: Dictionary = GUNS.get(n.substr(4), GUNS["browning50"])
		return _noise_burst(float(g["dur"]), float(g["lp"]), float(g["decay"]), float(g["hz"]), float(g["amt"]))
	if n.begins_with("hit_metal:"):
		return _hit_metal(int(n.substr(10)))
	if n.begins_with("hit_frag:"):
		return _hit_frag(int(n.substr(9)))
	if n.begins_with("engine:"):
		var parts: PackedStringArray = n.substr(7).split(":")
		return _engine_loop_p(parts[0], int(parts[1]))
	match n:
		"gun":
			s = _noise_burst(0.09, 0.35, 45.0, 120.0, 0.5)
		"cannon":
			s = _noise_burst(0.15, 0.2, 22.0, 70.0, 0.8)
		"hit":
			s = _noise_burst(0.06, 0.8, 60.0, 1700.0, 0.25)
		"flak":
			s = _noise_burst(0.6, 0.12, 8.0, 90.0, 0.8)
		"flak_close":
			s = _flak_close()
		"siren":
			s = _siren_loop()
		"whistle_warden":
			s = _warden_whistle()
		"fire_bell":
			s = _fire_bell()
		"thunder":
			s = _noise_burst(3.2, 0.05, 1.1, 48.0, 0.7)
		"explosion":
			s = _explosion(1.5)
		"crash":
			s = _crash_boom(3.0)
		"bomb_whistle":
			s = _whistle(1.6)
		"rocket":
			s = _noise_burst(1.0, 0.3, 2.5, 140.0, 0.25)
		"engine":
			s = _engine_loop()
		"wind_lo":
			s = _wind_loop(3.0, 0.045, 0.9)
		"wind_hi":
			s = _wind_loop(3.0, 0.35, 0.55)
	return s


func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _noise_burst(dur: float, lp: float, decay: float, thump_hz: float, thump_amt: float) -> AudioStreamWAV:
	var n: int = int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		var env: float = exp(-decay * t)
		f += (randf_range(-1.0, 1.0) - f) * lp
		var th: float = sin(TAU * thump_hz * t) * exp(-decay * 0.7 * t) * thump_amt
		out[i] = (f * 1.4 + th) * env * 0.8
	return _wav(out)


## A shell bursting close by: a hard crack on the front, a chest-thump underneath, then fragments whirring past.
## The distant "flak" voice is mostly low rumble, which vanishes on small speakers; this has real top end.
func _flak_close() -> AudioStreamWAV:
	var dur: float = 1.5
	var n: int = int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f: float = 0.0
	var hp: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		var w: float = randf_range(-1.0, 1.0)
		f += (w - f) * 0.14
		hp = w - f                                          # high-passed noise: the sharp crack
		var crack: float = hp * exp(-70.0 * t) * 1.6
		var body: float = f * exp(-7.0 * t) * 2.2
		var thump: float = sin(TAU * (78.0 - 30.0 * minf(t, 0.4)) * t) * exp(-9.0 * t) * 0.9
		out[i] = (crack + body + thump) * minf(t * 900.0, 1.0)
	# fragments whizzing and pattering past, a few hundredths of a second apart
	for k in 14:
		var t0: float = randf_range(0.04, 0.7)
		var hz: float = randf_range(1400.0, 3600.0)
		var amp: float = randf_range(0.12, 0.3) * (1.0 - t0 / 1.1)
		var i0: int = int(t0 * RATE)
		for j in int(0.09 * RATE):
			var idx: int = i0 + j
			if idx >= n:
				break
			var tj: float = float(j) / RATE
			out[idx] += (sin(TAU * hz * (1.0 - 4.0 * tj) * tj) * 0.7 + randf_range(-0.3, 0.3)) * exp(-45.0 * tj) * amp
	for i in n:
		out[i] = clampf(out[i], -1.0, 1.0) * 0.95
	return _wav(out)


## A bullet or cannon shell striking the player's own airframe: a sharp clang with a short metallic ring and a dull
## thud behind it. The variant picks a different set of ring frequencies so a burst of hits does not sound looped.
func _hit_metal(variant: int) -> AudioStreamWAV:
	var rings: Array = [[820.0, 1330.0, 2150.0], [690.0, 1180.0, 1890.0], [960.0, 1570.0, 2480.0]]
	var r: Array = rings[variant % 3]
	var dur: float = 0.45
	var n: int = int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		var w: float = randf_range(-1.0, 1.0)
		f += (w - f) * 0.5
		var tick: float = (w - f) * exp(-220.0 * t) * 1.5
		var ring: float = 0.0
		for q in 3:
			ring += sin(TAU * float(r[q]) * t) * exp(-(16.0 + 9.0 * q) * t) * (0.5 - 0.1 * q)
		var thud: float = sin(TAU * (130.0 - 40.0 * minf(t * 6.0, 1.0)) * t) * exp(-30.0 * t) * 0.7
		out[i] = clampf(tick + ring + thud, -1.0, 1.0) * minf(t * 2500.0, 1.0) * 0.95
	return _wav(out)


## Flak fragments tearing into the player's aircraft: a heavy thump, a crunch, and a rattle of small metal strikes.
func _hit_frag(variant: int) -> AudioStreamWAV:
	var dur: float = 1.0
	var n: int = int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		f += (randf_range(-1.0, 1.0) - f) * 0.2
		var thump: float = sin(TAU * (88.0 - 36.0 * minf(t * 3.0, 1.0)) * t) * exp(-10.0 * t) * 1.0
		var crunch: float = f * exp(-16.0 * t) * 2.0
		out[i] = (thump + crunch) * minf(t * 1500.0, 1.0)
	for k in 9 + variant * 2:
		var t0: float = randf_range(0.02, 0.55)
		var hz: float = randf_range(900.0, 2600.0)
		var amp: float = randf_range(0.18, 0.45) * (1.0 - t0 * 0.9)
		var i0: int = int(t0 * RATE)
		for j in int(0.12 * RATE):
			var idx: int = i0 + j
			if idx >= n:
				break
			var tj: float = float(j) / RATE
			out[idx] += (sin(TAU * hz * tj) * 0.8 + randf_range(-0.4, 0.4) * exp(-120.0 * tj)) * exp(-38.0 * tj) * amp
	for i in n:
		out[i] = clampf(out[i], -1.0, 1.0) * 0.95
	return _wav(out)


func _explosion(dur: float) -> AudioStreamWAV:
	var n: int = int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		var lp: float = lerpf(0.22, 0.03, clampf(t / 0.8, 0.0, 1.0))
		f += (randf_range(-1.0, 1.0) - f) * lp
		var sub: float = sin(TAU * (60.0 - 25.0 * t) * t) * 0.6
		out[i] = (f * 2.2 + sub) * exp(-2.6 * t) * minf(t * 200.0, 1.0) * 0.8
	return _wav(out)


## Aircraft hitting the ground: a bigger, deeper boom than a shell burst — a low thump under a long rumble.
func _crash_boom(dur: float) -> AudioStreamWAV:
	var n: int = int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f: float = 0.0
	var lo: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		var lp: float = lerpf(0.10, 0.02, clampf(t / 1.6, 0.0, 1.0))
		f += (randf_range(-1.0, 1.0) - f) * lp
		lo += (f - lo) * 0.02                                   # extra-low rumble rolling on under the blast
		var sub: float = sin(TAU * (42.0 - 16.0 * t) * t) * 0.9
		out[i] = clampf(f * 2.0 + lo * 3.0 + sub, -1.0, 1.0) * exp(-1.5 * t) * minf(t * 120.0, 1.0) * 0.95
	return _wav(out)


func _whistle(dur: float) -> AudioStreamWAV:
	var n: int = int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		var k: float = t / dur
		var hz: float = lerpf(2000.0, 650.0, k)
		ph += TAU * hz / RATE
		var env: float = minf(k * 6.0, 1.0) * (0.35 + 0.65 * k)
		out[i] = (sin(ph) * 0.5 + sin(ph * 2.01) * 0.12 + randf_range(-0.06, 0.06)) * env * 0.5
	return _wav(out)


## Seamless looped filtered noise: lp = one-pole low-pass coefficient (small = rumble, large = hiss).
func _wind_loop(dur: float, lp: float, gain: float) -> AudioStreamWAV:
	var n: int = int(dur * RATE)
	var fade: int = int(0.25 * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var f: float = 0.0
	var f2: float = 0.0
	for i in n + fade:
		f += (randf_range(-1.0, 1.0) - f) * lp
		f2 += (f - f2) * minf(lp * 2.0, 1.0)
		# slow breathing so the loop is not static
		var breathe: float = 0.8 + 0.2 * sin(TAU * float(i) / float(n) * 3.0)
		raw[i] = f2 * 3.2 * gain * breathe
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = raw[i]
	# cross-fade the tail into the head so the loop point is click-free
	for i in fade:
		var w: float = float(i) / float(fade)
		out[i] = raw[n + i] * (1.0 - w) + raw[i] * w
	return _wav(out, true)


## Air-raid siren: a 10 s rising and falling wail (650 Hz +/-150 Hz, whole cycles over the loop) with a second harmonic.
func _siren_loop() -> AudioStreamWAV:
	var dur: float = 10.0
	var n: int = int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		var f: float = 650.0 + 150.0 * sin(TAU * t / dur)
		ph += TAU * f / RATE
		out[i] = (sin(ph) + 0.3 * sin(2.0 * ph)) * 0.3
	return _wav(out, true)


## Air-raid wardens' whistle: a two-note trill on a breathy tone, about 1.6 s.
func _warden_whistle() -> AudioStreamWAV:
	var dur: float = 1.6
	var n: int = int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		var k: float = t / dur
		var hi: float = 1.0 if sin(TAU * 11.0 * t) > 0.0 else 0.0
		var hz: float = lerpf(2350.0, 2650.0, hi) * (1.0 + 0.02 * sin(TAU * 4.0 * k))
		ph += TAU * hz / RATE
		var env: float = minf(t * 25.0, 1.0) * minf((dur - t) * 25.0, 1.0)
		out[i] = (sin(ph) * 0.8 + sin(ph * 2.0) * 0.1 + randf_range(-0.08, 0.08)) * env * 0.45
	return _wav(out)


## Distant fire-station bell: an inharmonic strike, a few decaying partials and a short clapper transient.
func _fire_bell() -> AudioStreamWAV:
	var dur: float = 2.6
	var n: int = int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var partials: Array = [[1.0, 1.0, 1.4], [2.02, 0.5, 2.2], [2.76, 0.35, 3.0], [4.07, 0.2, 4.5], [5.4, 0.12, 6.0]]
	for i in n:
		var t: float = float(i) / RATE
		var v: float = 0.0
		for pa in partials:
			v += sin(TAU * 520.0 * float(pa[0]) * t) * float(pa[1]) * exp(-float(pa[2]) * t)
		v += randf_range(-1.0, 1.0) * exp(-60.0 * t) * 0.5
		out[i] = v * 0.35 * minf(t * 400.0, 1.0)
	return _wav(out)


func _engine_loop() -> AudioStreamWAV:
	var n: int = RATE / 2
	var out := PackedFloat32Array()
	out.resize(n)
	var base: float = 80.0   # 40 cycles in 0.5 s, so the loop is seamless
	for i in n:
		var t: float = float(i) / RATE
		var v: float = 0.0
		for h in range(1, 8):
			v += sin(TAU * base * float(h) * t + float(h) * 0.7) / float(h) * (1.0 if h % 2 == 1 else 0.6)
		var pulse: float = 0.75 + 0.25 * sin(TAU * base * 0.5 * t)
		out[i] = v * 0.22 * pulse
	return _wav(out, true)


## Engine loop for an ENGINES profile; voices > 1 adds detuned copies (+2 Hz each) so multi-engine aircraft beat.
## Two sub-octave sines and a heavily low-passed noise bed add the deep combustion rumble; the loop is
## tail-to-head cross-faded so the noise stays click-free, then normalised so no profile clips.
func _engine_loop_p(profile: String, voices: int) -> AudioStreamWAV:
	var e: Dictionary = ENGINES.get(profile, ENGINES["merlin"])
	var n: int = RATE / 2
	var fade: int = int(0.05 * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var base: float = float(e["base"])
	var harm: int = int(e["harm"])
	var roll: float = float(e["roll"])
	var rasp: float = float(e["rasp"])
	var pulse: float = float(e["pulse"])
	var pulse_hz: float = float(e["pulse_hz"])
	var whine: float = float(e.get("whine", 0.0))
	var sub_hz: float = base * 0.5             # one octave down: the engine's body
	var sub2_hz: float = floor(base * 0.25)    # two octaves down: the deep rumble
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(profile)
	var rf: Array = []
	var rp: Array = []
	for k in 14:
		rf.append(float(rng.randi_range(100, 1400)) * 2.0)   # whole cycles in 0.5 s, so it loops cleanly
		rp.append(rng.randf() * TAU)
	var nf: float = 0.0                        # one-pole low-pass state for the combustion roar
	var peak: float = 0.0001
	for i in n + fade:
		var t: float = float(i) / RATE
		var v: float = 0.0
		for vi in voices:
			var b: float = base + float(vi) * 2.0
			for h in range(1, harm + 1):
				v += sin(TAU * b * float(h) * t + float(h) * 0.7 + float(vi) * 1.3) * pow(1.0 / float(h), roll) * (1.0 if h % 2 == 1 else 0.6)
		v = v / float(voices) * 0.16
		v *= (1.0 - pulse) + pulse * sin(TAU * pulse_hz * t)
		v += sin(TAU * sub_hz * t) * 0.13 + sin(TAU * sub2_hz * t) * 0.06
		nf += (randf_range(-1.0, 1.0) - nf) * 0.022
		v += nf * 0.7
		var r: float = 0.0
		for k in 14:
			r += sin(TAU * float(rf[k]) * t + float(rp[k]))
		v += r * rasp * 0.05
		if whine > 0.0:
			v += whine * (sin(TAU * 1800.0 * t) + 0.5 * sin(TAU * 3200.0 * t + 0.4) + 0.3 * sin(TAU * 4600.0 * t))
		raw[i] = v
		peak = maxf(peak, absf(v))
	var norm: float = 0.78 / peak
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = raw[i] * norm
	for i in fade:
		var w: float = float(i) / float(fade)
		out[i] = (raw[n + i] * (1.0 - w) + raw[i] * w) * norm
	return _wav(out, true)
