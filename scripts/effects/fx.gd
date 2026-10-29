extends Node
## Autoload "FX": pooled toon effects. All sizes are world units (1 unit = 10 m horizontally;
## an aircraft is ~16 units wide, a bomb blast is ~26, a bullet impact ~0.6).
##   FX.explosion(pos, size)            starburst + fireball + smoke + debris
##   FX.crash_explosion(pos, on_water)  big aircraft/vehicle crash (fire, smoke column, crater)
##   FX.smoke_column(pos, size, secs)   -> FXEmitter (dark rising smoke)
##   FX.fire(pos, size, secs=45)        -> FXEmitter (flames + smoke)
##   FX.trail(node, "smoke"|"fire", size, offset) -> FXEmitter following a node; call .stop() when done
##   FX.flak_burst(pos)                 black puff + orange flash
##   FX.sparks(pos, normal)             bullet hit sparks
##   FX.dust(pos, size)   FX.water_splash(pos, size)   FX.water_plume(pos, size)  (bomb in water)
##   FX.muzzle_flash(node)              pooled flash parented to a muzzle marker
##   FX.crater(pos, radius)             scorched disc decal on terrain
##   FX.parachute(pos)                  falling pilot with canopy
##   FX.debris(pos, count, size, speed, colour)
##   FX.sfx("gun"|"cannon"|"explosion"|"flak"|"bomb_whistle"|"rocket"|"hit", pos, volume_db, min_interval)
##   FX.engine(throttle, speed_ratio)   procedural engine drone (player)

signal big_explosion(pos: Vector3, size: float)   # for camera shake etc.

const SHADER_PUFF := "res://shaders/fx_puff.gdshader"
const SHADER_STAR := "res://shaders/fx_star.gdshader"
const SHADER_CRATER := "res://shaders/fx_crater.gdshader"
const STAR_POOL := 96
const CRATER_POOL := 28
const CHUNK_COL := Color(0.22, 0.2, 0.17)

var puffs: FXParticles
var pillars: FXParticles     # tall smoke pillars (battle scenes): own big pool so they never starve ordinary effects
var chunks: FXParticles
var audio: AudioSFX

var _star_nodes: Array[MeshInstance3D] = []
var _star_mats: Array[ShaderMaterial] = []
var _star_age := PackedFloat32Array()
var _star_life := PackedFloat32Array()
var _star_size := PackedFloat32Array()
var _star_on := PackedByteArray()
var _star_next: int = 0

var _flash_list: Array[MeshInstance3D] = []
var _star_shader: Shader

var _craters: Array[MeshInstance3D] = []
var _crater_next: int = 0
var _crater_mat: ShaderMaterial

var _lights: Array[OmniLight3D] = []
var _light_age := PackedFloat32Array()
var _light_life := PackedFloat32Array()
var _light_peak := PackedFloat32Array()
var _light_next: int = 0
const LIGHT_POOL := 4

var _emitters: Array[FXEmitter] = []
var _puff_mat: ShaderMaterial
var _light_k_t: float = 0.0
var _chutes: Array[Parachute] = []
var _terrain: Node


func _ready() -> void:
	process_priority = 10
	var puff_mat := ShaderMaterial.new()
	puff_mat.shader = load(SHADER_PUFF) as Shader
	_puff_mat = puff_mat
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 10
	sm.rings = 5
	sm.material = puff_mat
	puffs = FXParticles.new()
	puffs.name = "Puffs"
	add_child(puffs)
	puffs.setup(sm, 7000)
	var pm2 := SphereMesh.new()
	pm2.radius = 0.5
	pm2.height = 1.0
	pm2.radial_segments = 8
	pm2.rings = 4
	pm2.material = puff_mat
	pillars = FXParticles.new()
	pillars.name = "Pillars"
	add_child(pillars)
	pillars.setup(pm2, 9000)

	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.35, 1.0)
	bm.material = puff_mat
	chunks = FXParticles.new()
	chunks.name = "Chunks"
	add_child(chunks)
	chunks.setup(bm, 160)

	_star_shader = load(SHADER_STAR) as Shader
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for i in STAR_POOL:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		var m := ShaderMaterial.new()
		m.shader = _star_shader
		mi.material_override = m
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_star_nodes.append(mi)
		_star_mats.append(m)
	_star_age.resize(STAR_POOL)
	_star_life.resize(STAR_POOL)
	_star_size.resize(STAR_POOL)
	_star_on.resize(STAR_POOL)

	_crater_mat = ShaderMaterial.new()
	_crater_mat.shader = load(SHADER_CRATER) as Shader
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE
	for i in CRATER_POOL:
		var c := MeshInstance3D.new()
		c.mesh = pm
		c.material_override = _crater_mat
		c.visible = false
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(c)
		_craters.append(c)

	# Pooled omni lights: explosions briefly light up the ground, aircraft and smoke around them.
	for i in LIGHT_POOL:
		var l := OmniLight3D.new()
		l.shadow_enabled = false
		l.visible = false
		l.light_energy = 0.0
		l.omni_attenuation = 1.8
		l.distance_fade_enabled = true
		l.distance_fade_begin = 3000.0
		l.distance_fade_length = 800.0
		add_child(l)
		_lights.append(l)
	_light_age.resize(LIGHT_POOL)
	_light_life.resize(LIGHT_POOL)
	_light_peak.resize(LIGHT_POOL)

	audio = AudioSFX.new()
	audio.name = "AudioSFX"
	add_child(audio)
	if not OS.get_cmdline_user_args().has("--no-sfx-prewarm"):
		audio.prewarm()          # every procedural sound, one per frame while the menu / load screen runs
	# lazily-built effect assets whose first use stalled a frame mid-flight (~100 ms on the first big bomb burst:
	# the blast column's shader + procedural mesh); build them now, on the menu / load screen
	BattleScene._pillar_mat()
	BattleScene._pillar_mesh(2)
	if GroundGlow._shader == null:
		GroundGlow._shader = load(GroundGlow.SHADER) as Shader


# ------------------------------------------------------------------ helpers

func _terrain_node() -> Node:
	if _terrain == null or not is_instance_valid(_terrain):
		_terrain = get_tree().get_first_node_in_group("terrain")
	return _terrain


func ground_height(pos: Vector3) -> float:
	var t: Node = _terrain_node()
	if t and t.has_method("get_height_at"):
		return t.call("get_height_at", pos)
	return 0.0


func is_water(pos: Vector3) -> bool:
	var t: Node = _terrain_node()
	if t and t.has_method("is_water_at"):
		return t.call("is_water_at", pos)
	return false


func _rv(s: float) -> Vector3:
	return Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))


func _spawn_star(pos: Vector3, size: float, life: float, col: Color, core: Color, spikes: float = 8.0) -> void:
	var i: int = _star_next
	_star_next = (_star_next + 1) % STAR_POOL
	var mi: MeshInstance3D = _star_nodes[i]
	var m: ShaderMaterial = _star_mats[i]
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("core_color", core)
	m.set_shader_parameter("spikes", spikes)
	m.set_shader_parameter("prog", 0.0)
	mi.global_position = pos
	mi.scale = Vector3.ONE * size
	mi.rotation.z = randf() * TAU
	mi.visible = true
	_star_age[i] = 0.0
	_star_life[i] = life
	_star_size[i] = size
	_star_on[i] = 1


# ------------------------------------------------------------------ public effects

func explosion(pos: Vector3, size: float = 10.0, star: bool = true) -> void:
	var s: float = maxf(size, 0.5)
	if star:
		_spawn_star(pos + Vector3(0, s * 0.3, 0), s * 3.4, 0.38, Color(1.0, 0.5, 0.08), Color(1.0, 0.95, 0.55), 9.0)
	# fireball
	var n_fire: int = clampi(int(4.0 + s * 0.4), 4, 10)
	for i in n_fire:
		var off: Vector3 = _rv(s * 0.35)
		off.y = absf(off.y)
		puffs.spawn(pos + off, off.normalized() * s * randf_range(0.6, 1.8), randf_range(0.45, 0.8),
			s * 0.35, s * randf_range(1.0, 1.5), Color(1.0, 0.85, 0.3, 1.0), Color(0.9, 0.22, 0.05, 0.0), 0.35, 0.0, 1.5)
	# smoke
	var n_smoke: int = clampi(int(3.0 + s * 0.5), 3, 12)
	for i in n_smoke:
		var off2: Vector3 = _rv(s * 0.5)
		off2.y = absf(off2.y) + s * 0.2
		puffs.spawn(pos + off2, Vector3(off2.x, s * randf_range(0.6, 1.2), off2.z) * 0.5, randf_range(14.0, 24.0),
			s * 0.5, s * randf_range(2.6, 4.2), Color(0.16, 0.15, 0.15, 0.9), Color(0.34, 0.33, 0.32, 0.0), 1.0, -s * 0.03, 0.55)
	# a slow, dirty pall that hangs where the blast was for half a minute or more (in the air or over the ground)
	for i in clampi(int(2.0 + s * 0.2), 2, 6):
		var off3: Vector3 = _rv(s * 0.6)
		off3.y = absf(off3.y) + s * 0.5
		puffs.spawn(pos + off3, Vector3(off3.x * 0.1, s * 0.12, off3.z * 0.1), randf_range(28.0, 42.0),
			s * 1.2, s * randf_range(4.0, 5.5), Color(0.2, 0.19, 0.18, 0.6), Color(0.4, 0.39, 0.38, 0.0), 1.0, 0.0, 0.3)
	# sparks / embers
	for i in clampi(int(s), 4, 14):
		var d: Vector3 = (_rv(1.0) + Vector3(0, 0.8, 0)).normalized()
		puffs.spawn(pos, d * s * randf_range(2.0, 4.5), randf_range(0.5, 1.0), s * 0.07, s * 0.02,
			Color(1.0, 0.85, 0.35, 1.0), Color(1.0, 0.3, 0.05, 0.0), 0.0, s * 2.0, 0.4)
	if s >= 6.0:
		debris(pos, clampi(int(s * 0.4), 3, 10), s * 0.14, s * 2.6, CHUNK_COL)
	if s >= 4.0:
		# shock ring: dust (or spray over water) racing outwards along the ground, plus a short light flash
		var wet: bool = is_water(pos)
		var rc: Color = Color(0.88, 0.95, 0.98, 0.7) if wet else Color(0.62, 0.55, 0.45, 0.65)
		var n_ring: int = clampi(int(8.0 + s * 0.8), 8, 22)
		for i in n_ring:
			var a: float = TAU * float(i) / float(n_ring) + randf() * 0.2
			var dir := Vector3(cos(a), 0.0, sin(a))
			puffs.spawn(pos + dir * s * 0.2 + Vector3(0, 0.3, 0), dir * s * randf_range(2.2, 3.2), randf_range(0.55, 0.9),
				s * 0.22, s * 0.7, rc, Color(rc.r, rc.g, rc.b, 0.0), 0.5, 0.0, 2.2)
		light_flash(pos + Vector3(0, s * 0.6, 0), clampf(s * 0.35, 1.5, 9.0), s * 9.0, 0.45, Color(1.0, 0.62, 0.25))
	if s >= 7.0 and not is_water(pos):
		_blast_column(pos, s)
	sfx("explosion", pos, linear_to_db(clampf(s / 18.0, 0.25, 1.6)), 0.05)
	big_explosion.emit(pos, s)


var _blast_cols: Array = []


## Big blasts (bombs, ammo dumps, fuel) leave a tall near-black column that shoots up, stands for a while, then thins away.
func _blast_column(pos: Vector3, s: float) -> void:
	while _blast_cols.size() >= 16:
		var old: Variant = _blast_cols.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	var mi := MeshInstance3D.new()
	mi.mesh = BattleScene._pillar_mesh(randi() % 3)
	mi.material_override = BattleScene._pillar_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2000.0
	var w: float = clampf(0.45 + s * 0.02, 0.5, 1.2)
	var h: float = clampf(0.3 + s * 0.02, 0.35, 0.9)
	mi.rotation.y = randf() * TAU
	mi.position = pos - Vector3(0, 1.0, 0)
	mi.scale = Vector3(w * 0.3, 0.02, w * 0.3)
	add_child(mi)
	_blast_cols.append(mi)
	var tw: Tween = create_tween()
	tw.tween_property(mi, "scale", Vector3(w, h, w), 6.0).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_interval(60.0 + s)
	tw.tween_property(mi, "scale", Vector3(w * 0.15, h * 1.15, w * 0.15), 40.0)
	tw.tween_callback(mi.queue_free)


func crash_explosion(pos: Vector3, on_water: bool = false) -> void:
	if on_water:
		water_splash(pos, 14.0)
		explosion(pos + Vector3(0, 2, 0), 9.0, false)
		return
	# An aircraft hitting the ground: a quick, fuel-fed fireball (no cartoon starburst), a throw of earth and dust,
	# wreckage scattered along the line of impact, a scar in the ground, and a wreck that burns and smokes for a
	# minute or more.
	explosion(pos + Vector3(0, 1.5, 0), 15.0, false)
	for i in 12:        # soil and dust thrown up and out
		var d: Vector3 = (_rv(1.0) + Vector3(0, 1.1, 0)).normalized()
		puffs.spawn(pos + Vector3(0, 0.5, 0), d * randf_range(6.0, 18.0), randf_range(1.2, 2.6), 1.2, randf_range(4.0, 7.0),
			Color(0.36, 0.28, 0.2, 0.8), Color(0.42, 0.36, 0.3, 0.0), 0.9, 9.0, 0.6)
	debris(pos, 26, 0.9, 55.0, Color(0.3, 0.32, 0.25))
	debris(pos, 8, 2.2, 30.0, Color(0.34, 0.35, 0.3))
	fire(pos, 5.0, 90.0)
	smoke_column(pos, 8.0, 70.0)
	crater(pos, 6.0)
	light_flash(pos + Vector3(0, 5.0, 0), 8.0, 60.0, 0.35, Color(1.0, 0.6, 0.24))
	sfx("crash", pos, 12.0, 0.02)


func smoke_column(pos: Vector3, size: float = 6.0, duration: float = 20.0) -> FXEmitter:
	return _add_emitter(FXEmitter.Kind.COLUMN, pos, null, Vector3.ZERO, size, duration)


## Subtle chimney smoke that lives as long as `holder` does (not subject to the finite-emitter cap).
func stack_smoke(pos: Vector3, size: float, holder: Node3D) -> FXEmitter:
	var e: FXEmitter = _add_emitter(FXEmitter.Kind.STACK, pos, holder, Vector3.ZERO, size, -1.0)
	var w: Vector3 = Vector3.ZERO
	var wm: Node = get_node_or_null("/root/WeatherManager")
	if wm != null and wm.has_method("get_wind"):
		w = wm.call("get_wind", pos)
	e.drift = Vector3(w.x, 0.0, w.z).limit_length(7.0) * 0.55
	return e


## Burning building: flames plus a tall black smoke plume, both bound to `holder` (stopped when it leaves the tree).
## Returns the emitters so the caller can stop() them.
func blaze(holder: Node3D, size: float = 1.0, plume: float = 1.0, smoke_on: bool = true) -> Array:
	var w: Vector3 = Vector3.ZERO
	var wm: Node = get_node_or_null("/root/WeatherManager")
	if wm != null and wm.has_method("get_wind"):
		w = wm.call("get_wind", holder.global_position)
	var lean: Vector3 = Vector3(w.x, 0.0, w.z).limit_length(9.0) * 0.8 + Vector3(2.0, 0.0, 0.8)
	var fire_e: FXEmitter = _add_emitter(FXEmitter.Kind.BLAZE, holder.global_position, holder, Vector3(0, 1.0, 0), 2.2 * size, -1.0)
	fire_e.drift = lean
	fire_e.smoke_on = smoke_on
	var out: Array = [fire_e]
	if smoke_on:
		var plume_e: FXEmitter = _add_emitter(FXEmitter.Kind.PLUME, holder.global_position, holder, Vector3(0, 4.0 * size, 0), 3.2 * size * plume, -1.0)
		plume_e.drift = lean
		out.append(plume_e)
	return out


## Permanent tall black smoke pillar with fire at its foot, bound to `holder` (stops when it leaves the tree).
func pillar(holder: Node3D, size: float = 7.0) -> FXEmitter:
	var w: Vector3 = Vector3.ZERO
	var wm: Node = get_node_or_null("/root/WeatherManager")
	if wm != null and wm.has_method("get_wind"):
		w = wm.call("get_wind", holder.global_position)
	var e: FXEmitter = _add_emitter(FXEmitter.Kind.PILLAR, holder.global_position, holder, Vector3.ZERO, size, -1.0)
	e.drift = Vector3(w.x, 0.0, w.z).limit_length(9.0) * 0.8 + Vector3(2.0, 0.0, 0.8)
	e.aux = puffs
	return e


## Domestic chimney smoke: thin white wisp that drifts with the wind.
func chimney_smoke(pos: Vector3, size: float, holder: Node3D) -> FXEmitter:
	var e: FXEmitter = stack_smoke(pos, size, holder)
	e.dark = -1.0
	return e


func fire(pos: Vector3, size: float = 4.0, duration: float = 45.0) -> FXEmitter:
	return _add_emitter(FXEmitter.Kind.FIRE, pos, null, Vector3.ZERO, size, duration)


## Smoke/fire trail following a node (e.g. a damaged aircraft). offset is in the node's local space.
func trail(node: Node3D, kind: String = "smoke", size: float = 2.0, offset: Vector3 = Vector3(0, 0.3, 3.0), dark: float = 0.5) -> FXEmitter:
	var k: int = FXEmitter.Kind.TRAIL_FIRE if kind == "fire" else FXEmitter.Kind.TRAIL_SMOKE
	var e: FXEmitter = _add_emitter(k, node.global_transform * offset, node, offset, size, -1.0)
	e.dark = dark
	return e


func _add_emitter(kind: int, pos: Vector3, follow: Node3D, offset: Vector3, size: float, duration: float) -> FXEmitter:
	var e := FXEmitter.new()
	e.kind = kind
	e.pos = pos
	e.last_pos = pos
	e.follow = follow
	e.offset = offset
	e.size = size
	e.remain = duration
	e.total = duration
	if _emitters.size() >= 48:
		# drop the oldest finite emitter
		for i in _emitters.size():
			if _emitters[i].follow == null:
				_emitters.remove_at(i)
				break
	_emitters.append(e)
	return e


## 0 by day .. 1 in full darkness (dusk is in between).
func night_factor() -> float:
	return clampf((0.55 - TimeOfDay.light_level) / 0.4, 0.0, 1.0)


func flak_burst(pos: Vector3, scale_v: float = 1.0, quiet: bool = false) -> void:
	var night: float = night_factor()
	var k: float = maxf(scale_v, 0.3)
	# the flash: a sharp orange star, bigger and slower to die after dark so a barrage reads like fireworks
	_spawn_star(pos, 22.0 * k * (1.0 + 0.6 * night), 0.25 + 0.3 * night, Color(1.0, 0.55, 0.1), Color(1.0, 0.92, 0.5), 7.0)
	if night > 0.3:
		# glowing shell fragments that spray out and fade - only really visible at night
		for i in 6:
			var d: Vector3 = _rv(1.0).normalized()
			puffs.spawn(pos, d * randf_range(25.0, 60.0) * k, randf_range(0.5, 1.1), 1.6 * k, 0.4 * k,
				Color(1.0, 0.8, 0.35, 1.0), Color(1.0, 0.35, 0.05, 0.0), 0.0, 9.0, 0.8)
	# Black powder puffs hang in the air long after the flash: the burst swells into a dirty blot that drifts with the
	# wind and stays visible for half a minute, so a battery's work leaves a whole field of smudges in the sky.
	var wind: Vector3 = Vector3.ZERO
	var wm: Node = get_node_or_null("/root/WeatherManager")
	if wm != null and wm.has_method("get_wind"):
		wind = wm.call("get_wind", pos)
	wind = Vector3(wind.x, 0.0, wind.z).limit_length(8.0)
	for i in 8:
		var off: Vector3 = _rv(2.5 * k)
		puffs.spawn(pos + off, off * 0.5 + Vector3(0.0, 0.4, 0.0) + wind * 0.6, randf_range(18.0, 30.0), 3.0 * k, randf_range(14.0, 24.0) * k,
			Color(0.06, 0.06, 0.07, 0.95), Color(0.26, 0.26, 0.28, 0.0), 0.8, -0.12, 0.35)
	if not quiet:
		# Close bursts get the cracking voice and extra level (the distant one is mostly low rumble and falls to nothing
		# beside you); both bypass the rate gate when near, so a barrage never swallows the one right on top of you.
		var cam: Camera3D = get_viewport().get_camera_3d()
		var near: float = cam.global_position.distance_to(pos) if cam != null else 1.0e9
		if near < 700.0:
			sfx("flak_close", pos, lerpf(9.0, 3.0, clampf(near / 700.0, 0.0, 1.0)), 0.05)
		else:
			sfx("flak", pos, 0.0, 0.05)


func sparks(pos: Vector3, normal: Vector3 = Vector3.UP, count: int = 4) -> void:
	_spawn_star(pos, 1.3, 0.12, Color(1.0, 0.8, 0.25), Color(1.0, 1.0, 0.8), 6.0)
	for i in count:
		var d: Vector3 = (normal + _rv(0.9)).normalized()
		puffs.spawn(pos, d * randf_range(10.0, 30.0), randf_range(0.2, 0.4), 0.28, 0.08,
			Color(1.0, 0.9, 0.4, 1.0), Color(1.0, 0.4, 0.1, 0.0), 0.0, 25.0, 0.0)


func dust(pos: Vector3, size: float = 1.5) -> void:
	for i in 2:
		puffs.spawn(pos + _rv(size * 0.2), Vector3(randf_range(-1, 1), randf_range(2.0, 5.0), randf_range(-1, 1)) * size * 0.5,
			randf_range(0.7, 1.2), size * 0.4, size * 1.2, Color(0.48, 0.4, 0.3, 0.8), Color(0.55, 0.48, 0.4, 0.0), 1.0, 0.0, 1.0)


## Rubber smoke from a wheel touching down.
func tyre_smoke(pos: Vector3, size: float = 1.6) -> void:
	for i in 3:
		puffs.spawn(pos + _rv(size * 0.2), Vector3(randf_range(-1, 1), randf_range(0.4, 1.2), randf_range(-1, 1)) * size * 0.6,
			randf_range(0.9, 1.5), size * 0.4, size * 1.6, Color(0.88, 0.88, 0.86, 0.7), Color(0.9, 0.9, 0.9, 0.0), 0.0, 0.0, 0.6)


## Dark cough of exhaust smoke from a cold engine starting.
func engine_start_puff(pos: Vector3, size: float = 1.4) -> void:
	puffs.spawn(pos + _rv(size * 0.2), Vector3(randf_range(-0.6, 0.6), randf_range(0.5, 1.4), randf_range(-0.6, 0.6)),
		randf_range(1.4, 2.2), size * 0.4, size * 1.8, Color(0.16, 0.16, 0.16, 0.6), Color(0.5, 0.5, 0.5, 0.0), 0.0, 0.0, 0.6)


## Brief omni light (pooled, oldest is reused). peak = light energy, reach = range in world units.
func light_flash(pos: Vector3, peak: float, reach: float, life: float, col: Color) -> void:
	var i: int = _light_next
	_light_next = (_light_next + 1) % LIGHT_POOL
	var l: OmniLight3D = _lights[i]
	l.global_position = pos
	l.omni_range = minf(reach, 110.0)    # very large ranges lit a blocky square of ground (clustered light edges)
	l.light_color = col
	l.light_energy = peak
	l.visible = true
	_light_age[i] = 0.0
	_light_life[i] = maxf(life, 0.05)
	_light_peak[i] = peak


## One puff of wingtip condensation: white, flat-shaded, thins out quickly.
func vapor_puff(pos: Vector3, vel: Vector3, size: float, alpha: float) -> void:
	puffs.spawn(pos, vel, 1.3, size * 0.4, size * 1.7, Color(1.0, 1.0, 1.0, alpha), Color(0.92, 0.96, 1.0, 0.0), 0.0, 0.0, 0.6)


func water_splash(pos: Vector3, size: float = 3.0) -> void:
	# expanding foam ring on the surface
	for i in clampi(int(size * 1.5), 6, 14):
		var a: float = randf() * TAU
		var dir2 := Vector3(cos(a), 0.0, sin(a))
		puffs.spawn(pos + Vector3(0, 0.2, 0), dir2 * size * randf_range(0.8, 1.6), randf_range(0.6, 1.0), size * 0.2, size * 0.5,
			Color(0.95, 0.98, 1.0, 0.8), Color(0.8, 0.9, 0.95, 0.0), 0.2, 0.0, 1.8)
	for i in clampi(int(size), 3, 9):
		var d := Vector3(randf_range(-0.5, 0.5), 1.0, randf_range(-0.5, 0.5))
		puffs.spawn(pos, d * size * randf_range(1.2, 2.6), randf_range(0.7, 1.1), size * 0.3, size * 0.55,
			Color(0.9, 0.96, 1.0, 0.95), Color(0.7, 0.86, 0.95, 0.0), 1.0, size * 4.0, 0.3)


## A bomb (or a depth-charge / Upkeep detonation) in water: a tall white column that climbs and falls back,
## a crown of spray thrown outwards, a base surge racing across the surface, a drifting mist, and a pale foam
## slick that lingers on the water for a while. size ~ blast radius (world units); 8 = 500 lb bomb.
func water_plume(pos: Vector3, size: float = 8.0) -> void:
	var s: float = maxf(size, 2.0)
	var surf := Vector3(pos.x, pos.y + 0.3, pos.z)
	var white := Color(0.96, 0.98, 1.0, 0.95)
	var fade := Color(0.82, 0.90, 0.95, 0.0)
	# the column: fast-rising puffs, stacked, pulled back down by gravity
	var n_col: int = clampi(int(10.0 + s), 10, 26)
	for i in n_col:
		var up: float = s * randf_range(3.5, 7.5)
		var d := Vector3(randf_range(-0.12, 0.12), 1.0, randf_range(-0.12, 0.12))
		puffs.spawn(surf + _rv(s * 0.25) * Vector3(1, 0, 1), d * up, randf_range(2.2, 3.4), s * 0.45, s * randf_range(1.1, 1.6),
			white, fade, 0.85, s * 1.8, 0.25)
	# crown: spray thrown outwards and up from the top of the column
	for i in clampi(int(s * 1.2), 8, 20):
		var a: float = TAU * float(i) / 12.0 + randf() * 0.4
		var dir := Vector3(cos(a), randf_range(0.9, 1.6), sin(a))
		puffs.spawn(surf + Vector3(0, s * 0.8, 0), dir * s * randf_range(2.0, 3.4), randf_range(1.6, 2.6), s * 0.25, s * 0.8,
			white, fade, 0.7, s * 2.2, 0.3)
	# base surge: a ring of spray rolling outwards across the water
	var n_ring: int = clampi(int(14.0 + s), 14, 30)
	for i in n_ring:
		var a2: float = TAU * float(i) / float(n_ring) + randf() * 0.2
		var dir2 := Vector3(cos(a2), 0.05, sin(a2))
		puffs.spawn(surf + dir2 * s * 0.4, dir2 * s * randf_range(2.6, 3.8), randf_range(2.5, 3.8), s * 0.4, s * 1.6,
			Color(0.92, 0.96, 0.98, 0.75), Color(0.85, 0.9, 0.95, 0.0), 0.6, 0.0, 0.9)
	# drifting mist after the column falls
	for i in 5:
		puffs.spawn(surf + Vector3(0, s * randf_range(0.5, 2.5), 0) + _rv(s), Vector3(randf_range(-1, 1), 0.6, randf_range(-1, 1)) * s * 0.15,
			randf_range(7.0, 10.0), s * 1.2, s * 3.2, Color(0.9, 0.93, 0.96, 0.35), Color(0.9, 0.93, 0.96, 0.0), 0.3, 0.0, 0.2)
	# foam slick on the surface (flattened, slow to fade)
	for i in 6:
		var o: Vector3 = _rv(s * 0.9)
		o.y = 0.0
		puffs.spawn(Vector3(pos.x, pos.y - s * 0.12, pos.z) + o, Vector3.ZERO, randf_range(14.0, 20.0), s * 0.8, s * 2.4,
			Color(0.95, 0.97, 0.98, 0.55), Color(0.9, 0.95, 0.96, 0.0), 0.15, 0.0, 0.0)
	light_flash(surf + Vector3(0, s * 0.4, 0), clampf(s * 0.15, 0.8, 4.0), s * 6.0, 0.25, Color(1.0, 0.75, 0.45))
	sfx("explosion", pos, linear_to_db(clampf(s / 18.0, 0.25, 1.6)), 0.05)


func muzzle_flash(muzzle: Node3D) -> void:
	return      # no starburst at the gun mounts: the tracers and the gun sound carry the fire
	if muzzle == null or not is_instance_valid(muzzle):
		return
	var f: MeshInstance3D = null
	if muzzle.has_meta("fx_flash"):
		f = muzzle.get_meta("fx_flash") as MeshInstance3D
	if f == null or not is_instance_valid(f):
		f = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		f.mesh = q
		var m := ShaderMaterial.new()
		m.shader = _star_shader
		m.set_shader_parameter("color", Color(1.0, 0.7, 0.15))
		m.set_shader_parameter("core_color", Color(1.0, 1.0, 0.8))
		m.set_shader_parameter("prog", 0.35)
		m.set_shader_parameter("spikes", 6.0)
		f.material_override = m
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.position = Vector3(0, 0, -0.6)
		muzzle.add_child(f)
		muzzle.set_meta("fx_flash", f)
	f.scale = Vector3.ONE * randf_range(1.6, 2.6)
	f.rotation.z = randf() * TAU
	f.visible = true
	f.set_meta("t", 0.05)
	if not _flash_list.has(f):
		_flash_list.append(f)


func crater(pos: Vector3, radius: float = 6.0) -> void:
	if is_water(pos):
		return
	var c: MeshInstance3D = _craters[_crater_next]
	_crater_next = (_crater_next + 1) % CRATER_POOL
	var h: float = ground_height(pos)
	var e: float = maxf(radius * 0.6, 1.0)
	var hx: float = ground_height(pos + Vector3(e, 0, 0)) - ground_height(pos - Vector3(e, 0, 0))
	var hz: float = ground_height(pos + Vector3(0, 0, e)) - ground_height(pos - Vector3(0, 0, e))
	var n := Vector3(-hx, 2.0 * e, -hz).normalized()
	var basis := Basis(Quaternion(Vector3.UP, n)) * Basis(Vector3.UP, randf() * TAU)
	basis = basis.scaled(Vector3(radius * 2.0, 1.0, radius * 2.0))
	c.global_transform = Transform3D(basis, Vector3(pos.x, h + 0.25 + radius * 0.02, pos.z))
	c.visible = true


func parachute(pos: Vector3, team: String = "", look: String = "") -> Parachute:
	var p: Parachute = null
	for c in _chutes:
		if not c.active:
			p = c
			break
	if p == null:
		if _chutes.size() >= 24:
			p = _chutes[0]      # pool full: recycle the oldest so a bail-out can never fail
			_chutes.remove_at(0)
			_chutes.append(p)
		else:
			p = Parachute.new()
			add_child(p)
			_chutes.append(p)
	p.launch(pos, team, look)
	return p


func debris(pos: Vector3, count: int, size: float, speed: float, col: Color = CHUNK_COL) -> void:
	for i in count:
		var d: Vector3 = (_rv(1.0) + Vector3(0, 0.9, 0)).normalized()
		chunks.spawn(pos, d * speed * randf_range(0.4, 1.0), randf_range(1.6, 3.0), size * randf_range(0.6, 1.4), size * randf_range(0.3, 0.8),
			col * randf_range(0.8, 1.2), Color(col.r, col.g, col.b, 0.0), 1.0, 28.0, 0.1, randf_range(4.0, 12.0))


func sfx(sfx_name: String, pos: Vector3, volume_db: float = 0.0, min_interval: float = 0.0) -> void:
	audio.play(sfx_name, pos, volume_db, min_interval)


func engine(throttle: float, speed_ratio: float, profile: String = "merlin", count: int = 1) -> void:
	audio.engine(throttle, speed_ratio, profile, count)


# ------------------------------------------------------------------ update

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_light_k_t -= delta
	if _light_k_t <= 0.0 and _puff_mat != null:
		_light_k_t = 0.5
		# smoke is drawn unshaded, so dim it with the light or it glows grey against a night sky
		_puff_mat.set_shader_parameter("light_k", lerpf(1.0, 0.22, night_factor()))
		RenderingServer.global_shader_parameter_set("night_k", night_factor())
		var env: Environment = TimeOfDay.environment
		if env != null:
			var hc: Color = env.fog_light_color.darkened(0.94 * night_factor())
			_puff_mat.set_shader_parameter("haze_color", Vector3(hc.r, hc.g, hc.b))
			_puff_mat.set_shader_parameter("haze_density", env.fog_density if env.fog_enabled else 0.0)
			var pm: ShaderMaterial = BattleScene._pillar_mat()
			pm.set_shader_parameter("light_k", lerpf(1.0, 0.22, night_factor()))
			pm.set_shader_parameter("haze_color", Vector3(hc.r, hc.g, hc.b))
			pm.set_shader_parameter("haze_density", env.fog_density if env.fog_enabled else 0.0)
	for i in STAR_POOL:
		if _star_on[i] == 0:
			continue
		var a: float = _star_age[i] + delta
		if a >= _star_life[i]:
			_star_on[i] = 0
			_star_nodes[i].visible = false
			continue
		_star_age[i] = a
		_star_mats[i].set_shader_parameter("prog", a / _star_life[i])
	var k: int = _flash_list.size() - 1
	while k >= 0:
		var f: MeshInstance3D = _flash_list[k]
		if not is_instance_valid(f):
			_flash_list.remove_at(k)
		else:
			var t: float = float(f.get_meta("t")) - delta
			f.set_meta("t", t)
			if t <= 0.0:
				f.visible = false
				_flash_list.remove_at(k)
		k -= 1
	for li in LIGHT_POOL:
		if not _lights[li].visible:
			continue
		var la: float = _light_age[li] + delta
		if la >= _light_life[li]:
			_lights[li].visible = false
			_lights[li].light_energy = 0.0
			continue
		_light_age[li] = la
		var lk: float = 1.0 - la / _light_life[li]
		_lights[li].light_energy = _light_peak[li] * lk * lk
	var e_i: int = _emitters.size() - 1
	while e_i >= 0:
		var e: FXEmitter = _emitters[e_i]
		if not e.update(delta, pillars if e.kind == FXEmitter.Kind.PILLAR else puffs):
			_emitters.remove_at(e_i)
		e_i -= 1
