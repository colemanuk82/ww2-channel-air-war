class_name RainFX
extends Node3D
## Rain around the camera.
##  * World rain: streaks simulated in the camera's frame, moving at the rain's velocity RELATIVE to you (falling
##    drops + wind - your own speed). Standing still it falls and slants with the wind; at 300 mph it streams
##    straight at you, and the streaks stretch with speed like a camera shutter would draw them.
##  * Cockpit glass (cockpit view only): drops land on the canopy and the airflow drives them across it. Each drop
##    runs away from the point where your direction of flight meets the glass - looking forward they burst
##    outward from the middle, looking left they run off to the left, looking back they converge - and when slow
##    or parked they trickle down with gravity instead. Stick-slip motion and wet trails behind each drop.
##  * Sound: a soft hiss outside, drumming on the canopy in the cockpit. Lightning flashes and thunder in storms.
## `intensity` 0..1 and `storm` 0..1 are set by WeatherManager.

var intensity: float = 0.0
var storm: float = 0.0
var _parts: GPUParticles3D
var _pm: ParticleProcessMaterial
var _quad: QuadMesh
var _mat: StandardMaterial3D
var _over: RainOverlay
var _cam_prev: Vector3 = Vector3.ZERO
var _vel: Vector3 = Vector3.ZERO
var _thunder_t: float = -1.0
var _flash_t: float = 12.0
var _snd: AudioStreamPlayer
var _snd_level: float = 0.0

const FALL_SPEED: float = 18.0      # units/s straight down (terminal velocity of a raindrop, in world units)


func _ready() -> void:
	top_level = true
	_pm = ParticleProcessMaterial.new()
	_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_pm.emission_box_extents = Vector3(40.0, 30.0, 40.0)
	_pm.direction = Vector3(0, -1, 0)
	_pm.spread = 2.0
	_pm.initial_velocity_min = 40.0
	_pm.initial_velocity_max = 50.0
	_pm.gravity = Vector3.ZERO
	_pm.particle_flag_align_y = true
	_pm.scale_min = 0.7
	_pm.scale_max = 1.3
	_quad = QuadMesh.new()
	_quad.size = Vector2(0.025, 1.0)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mat.billboard_keep_scale = true
	_mat.albedo_texture = _streak_tex()
	_mat.albedo_color = Color(0.8, 0.85, 0.92, 0.3)
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.disable_receive_shadows = true
	_quad.material = _mat
	_parts = GPUParticles3D.new()
	_parts.amount = 6000
	_parts.lifetime = 1.0
	_parts.local_coords = true          # simulated in the camera's (translating) frame: velocity = relative velocity
	_parts.visibility_aabb = AABB(Vector3(-120, -90, -120), Vector3(240, 180, 240))
	_parts.process_material = _pm
	_parts.draw_pass_1 = _quad
	_parts.emitting = false
	_parts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_parts)
	var cl := CanvasLayer.new()
	cl.layer = 4
	add_child(cl)
	_over = RainOverlay.new()
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(_over)
	_snd = AudioStreamPlayer.new()
	_snd.stream = _rain_loop()
	_snd.volume_db = -60.0
	add_child(_snd)


## A soft streak: bright in the middle, fading to both ends and the sides.
static func _streak_tex() -> Texture2D:
	var img := Image.create(8, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 8:
			var u: float = (float(x) + 0.5) / 8.0 * 2.0 - 1.0
			var v: float = (float(y) + 0.5) / 64.0
			var a: float = (1.0 - u * u) * sin(v * PI) * (0.6 + 0.4 * v)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## Two seconds of looping rain: band-limited noise (the hiss) with soft random drop ticks (the drumming).
static func _rain_loop() -> AudioStreamWAV:
	var rate: int = 22050
	var n: int = rate * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var lp: float = 0.0
	var lp2: float = 0.0
	var tick: float = 0.0
	for i in n:
		var w: float = rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.35
		lp2 += (lp - lp2) * 0.6
		if rng.randf() < 0.004:
			tick = rng.randf_range(0.3, 1.0)
		tick *= 0.93
		var s: float = (lp2 * 0.5 + (lp - lp2) * 0.6 + tick * rng.randf_range(-1.0, 1.0)) * 0.6
		# cross-fade the ends so the loop has no click
		var e: float = minf(float(i), float(n - 1 - i)) / 400.0
		s *= clampf(e, 0.0, 1.0) if e < 1.0 else 1.0
		var v: int = int(clampf(s, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = n
	return st


func _player() -> Aircraft:
	for n in get_tree().get_nodes_in_group("aircraft"):
		var a: Aircraft = n as Aircraft
		if a != null and a.player_controlled:
			return a
	return null


func _process(delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp: Vector3 = cam.global_position
	if delta > 0.0:
		var raw: Vector3 = (cp - _cam_prev) / delta
		if raw.length() < 600.0:                 # ignore camera cuts / teleports
			_vel = _vel.lerp(raw, minf(delta * 4.0, 1.0))
	_cam_prev = cp
	var on: bool = intensity > 0.03
	_parts.emitting = on
	var pl: Aircraft = _player()
	var cockpit: bool = pl != null and pl._cockpit_view and pl.state == Aircraft.State.ALIVE
	if on:
		_parts.amount_ratio = clampf(intensity, 0.05, 1.0)
		# the rain's velocity relative to us: falling, blown by the wind, minus our own motion
		var w: Vector3 = WeatherManager.get_wind(cp)
		var rel: Vector3 = Vector3(w.x, -FALL_SPEED * (1.0 + 0.3 * storm), w.z) - _vel
		var rs: float = maxf(rel.length(), 1.0)
		var rd: Vector3 = rel / rs
		_pm.direction = rd
		_pm.initial_velocity_min = rs * 0.92
		_pm.initial_velocity_max = rs * 1.08
		# drops are born upstream so the box ahead of us is always full; they live long enough to sweep past
		_parts.lifetime = clampf(110.0 / rs, 0.35, 2.4)
		global_position = cp - rd * 45.0
		# motion blur: the faster they pass, the longer and fainter the streak
		_quad.size = Vector2(0.022 + 0.01 * storm, clampf(rs * 0.016, 0.7, 4.5))
		var light: float = clampf(0.25 + TimeOfDay.light_level * 0.85, 0.2, 1.0)
		_mat.albedo_color = Color(0.8 * light, 0.85 * light, 0.92 * light, clampf(0.34 - rs * 0.0006, 0.16, 0.34))
	# overlay
	_over.intensity = intensity
	_over.cockpit = cockpit
	_over.cam = cam
	_over.aircraft = pl
	_over.air_vel = _vel
	# sound: louder drumming on the canopy than the hiss outside
	var want: float = intensity * (1.0 if cockpit else 0.45)
	_snd_level = move_toward(_snd_level, want, delta * 0.5)
	if _snd_level > 0.02:
		if not _snd.playing:
			_snd.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
			_snd.play()
		_snd.volume_db = linear_to_db(maxf(_snd_level * 0.55, 0.0001)) + (2.0 if cockpit else -4.0)
		_snd.pitch_scale = 0.85 + 0.35 * clampf(_vel.length() / 200.0, 0.0, 1.0)
	elif _snd.playing:
		_snd.stop()
	# lightning
	if storm > 0.6 and intensity > 0.5:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash_t = randf_range(6.0, 18.0)
			_over.flash(randf_range(0.5, 1.0))
			_thunder_t = randf_range(0.4, 3.5)
	if _thunder_t > 0.0:
		_thunder_t -= delta
		if _thunder_t <= 0.0:
			FX.sfx("thunder", cp + Vector3(randf_range(-1, 1), 0.2, randf_range(-1, 1)).normalized() * 600.0, -2.0)


## Screen-space rain: drops on the canopy glass (cockpit only), a wet tint and lightning flashes.
class RainOverlay extends Control:
	var intensity: float = 0.0
	var cockpit: bool = false
	var cam: Camera3D
	var aircraft: Aircraft
	var air_vel: Vector3 = Vector3.ZERO
	var _drops: Array = []        # {p, r, vs, stick, life, trail: PackedVector2Array, moved}
	var _flash: float = 0.0
	var _focus: Vector2 = Vector2.ZERO     # where the airflow comes from (screen)
	var _toward: bool = false              # true: drops converge on _focus (looking backwards)
	var _flow_k: float = 0.0               # 0 parked .. 1 flying: airflow vs gravity
	var _grav: Vector2 = Vector2(0, 1)
	var _light: float = 1.0

	func flash(k: float) -> void:
		_flash = k

	func _process(delta: float) -> void:
		_flash = maxf(_flash - delta * 2.4, 0.0)
		var wet: bool = intensity > 0.04
		if not wet and _drops.is_empty() and _flash <= 0.0:
			if visible:
				visible = false
			return
		visible = true
		_light = clampf(0.3 + TimeOfDay.light_level * 0.8, 0.25, 1.0)
		if not cockpit:
			_drops.clear()         # no glass outside the cockpit
		else:
			_update_flow()
			_update_drops(delta, wet)
		queue_redraw()

	## Airflow over the glass for this view: from the point where the flight path meets the screen.
	func _update_flow() -> void:
		if cam == null:
			return
		var cp: Vector3 = cam.global_position
		var dir: Vector3 = air_vel.normalized() if air_vel.length() > 8.0 else (aircraft.get_forward() if aircraft != null else -cam.global_transform.basis.z)
		var ahead: Vector3 = cp + dir * 2000.0
		if not cam.is_position_behind(ahead):
			_focus = cam.unproject_position(ahead)
			_toward = false
		else:
			_focus = cam.unproject_position(cp - dir * 2000.0)
			_toward = true
		var c: Vector3 = cp - cam.global_transform.basis.z * 10.0
		_grav = (cam.unproject_position(c + Vector3.DOWN) - cam.unproject_position(c)).normalized()
		var spd: float = air_vel.length()
		_flow_k = clampf((spd - 6.0) / 50.0, 0.0, 1.0)

	func _flow_at(p: Vector2) -> Vector2:
		var d: Vector2 = (_focus - p) if _toward else (p - _focus)
		var L: float = d.length()
		if L < 0.001:
			return _grav
		var diag: float = size.length()
		# slow near the stagnation point, quick further out
		var near: float = clampf(L / (0.35 * diag), 0.15, 1.0)
		return d / L * near

	func _update_drops(delta: float, wet: bool) -> void:
		var sz: Vector2 = size
		var spd: float = air_vel.length()
		if wet:
			# more drops strike the glass the faster we fly into the rain
			var rate: float = intensity * (14.0 + 70.0 * _flow_k)
			var n_new: int = int(rate * delta) + (1 if randf() < fmod(rate * delta, 1.0) else 0)
			for k in n_new:
				if _drops.size() >= 150:
					break
				var p := Vector2(randf() * sz.x, randf() * sz.y)
				var big: bool = randf() < 0.3
				_drops.append({"p": p, "r": randf_range(3.5, 7.5) if big else randf_range(1.2, 3.2), "vs": randf_range(0.6, 1.4),
					"stick": randf_range(0.0, 0.5), "life": randf_range(4.0, 9.0), "trail": PackedVector2Array([p]), "moved": 0.0})
		var air_px: float = (120.0 + 520.0 * clampf(spd / 180.0, 0.0, 1.0)) * _flow_k
		for i in range(_drops.size() - 1, -1, -1):
			var d: Dictionary = _drops[i]
			d["life"] = float(d["life"]) - delta
			var r: float = float(d["r"])
			var p: Vector2 = d["p"]
			if float(d["stick"]) > 0.0:
				d["stick"] = float(d["stick"]) - delta
			else:
				# big drops get dragged off first; small ones cling. Stick-slip: now and then a drop catches again
				var size_k: float = clampf(r / 6.0, 0.25, 1.2)
				var v: Vector2 = _flow_at(p) * air_px * size_k * float(d["vs"]) + _grav * (35.0 + 25.0 * size_k) * (1.0 - 0.75 * _flow_k)
				var step: Vector2 = v * delta
				p += step
				d["p"] = p
				d["moved"] = float(d["moved"]) + step.length()
				if float(d["moved"]) > 5.0:
					d["moved"] = 0.0
					var tr: PackedVector2Array = d["trail"]
					tr.append(p)
					if tr.size() > 9:     # short trail: the film behind a running drop is blown thin at once
						tr.remove_at(0)
					d["trail"] = tr
				if randf() < delta * (0.6 if _flow_k > 0.3 else 1.5):
					d["stick"] = randf_range(0.05, 0.35)
				# a running drop sheds water and shrinks
				d["r"] = maxf(r - step.length() * 0.004, 1.0)
			if float(d["life"]) <= 0.0 or p.x < -40.0 or p.y < -40.0 or p.x > sz.x + 40.0 or p.y > sz.y + 40.0:
				_drops.remove_at(i)

	func _draw() -> void:
		var sz: Vector2 = size
		if intensity > 0.04:
			# a grey wet veil: stronger in the cockpit (water film on the glass)
			draw_rect(Rect2(Vector2.ZERO, sz), Color(0.10, 0.13, 0.18, (0.13 if cockpit else 0.07) * intensity))
		var L: float = _light
		for d in _drops:
			var p: Vector2 = d["p"]
			var r: float = d["r"]
			var fade: float = clampf(float(d["life"]) * 0.8, 0.0, 1.0)
			var tr: PackedVector2Array = d["trail"]
			# the wet trail it leaves behind, thinning and fading toward its start
			if tr.size() >= 2:
				var n: int = tr.size()
				for k in range(n - 1):
					var t: float = float(k + 1) / float(n)
					var w: float = maxf(r * 0.75 * t, 0.9)
					draw_line(tr[k], tr[k + 1], Color(0.05, 0.07, 0.1, 0.06 * t * fade), w + 1.0, true)       # refracted dark edge
					draw_line(tr[k], tr[k + 1], Color(0.8 * L, 0.86 * L, 0.94 * L, 0.15 * t * fade), w * 0.8, true)
				draw_line(tr[n - 1], p, Color(0.8 * L, 0.86 * L, 0.94 * L, 0.2 * fade), maxf(r * 0.7, 0.9), true)
				# a running drop is drawn out into a teardrop, its tail toward where it came from
				var back: Vector2 = (tr[n - 1] - p)
				if back.length() > 0.5:
					back = back.normalized()
					draw_line(p, p + back * r * 2.2, Color(0.72 * L, 0.78 * L, 0.88 * L, 0.22 * fade), r * 1.3, true)
			# the bead: darker refracting rim, lighter body, a pin of highlight
			draw_circle(p, r, Color(0.05, 0.07, 0.1, 0.16 * fade))
			draw_circle(p, r * 0.78, Color(0.72 * L, 0.78 * L, 0.88 * L, 0.16 * fade))
			draw_arc(p, r, 2.2, 4.0, 8, Color(L, L, L, 0.28 * fade), 1.0, true)
			draw_circle(p + Vector2(-r * 0.32, -r * 0.36), maxf(r * 0.22, 0.6), Color(1, 1, 1, 0.55 * fade * L))
		if _flash > 0.0:
			draw_rect(Rect2(Vector2.ZERO, sz), Color(0.92, 0.95, 1.0, clampf(_flash, 0.0, 1.0) * 0.55))
