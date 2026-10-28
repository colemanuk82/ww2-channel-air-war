extends Node
## Time of day (autoload "TimeOfDay"): rotating sun/moon, sky, fog, ambient and light presets.
## API: set_time(hour), set_preset("dawn"|"noon"|"dusk"|"night"), cycle_preset(), time_scale (game hours per real second),
##      set_weather_modifiers(fog_mul, light_mul, desat, sky_dim) (used by WeatherManager).
## Owns the WorldEnvironment, sun and moon DirectionalLight3D as children.

signal time_changed(hour: float)
signal preset_changed(preset_name: String)

const PRESETS := {"dawn": 6.3, "noon": 12.0, "dusk": 18.4, "night": 23.0}
const PRESET_ORDER := ["dawn", "noon", "dusk", "night"]

# key: hour, top, horizon, fog, light_col, sun_energy, moon_energy, ambient_col, ambient_energy, stars, fog_density
var _keys: Array = []

var hour: float = 12.0
var time_scale: float = 0.0   # game hours per real second (0 = frozen)
var current_preset: String = "noon"

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world_env: WorldEnvironment
var environment: Environment
var sky_material: ShaderMaterial

var fog_mul: float = 1.0
var light_mul: float = 1.0
var desat: float = 0.0
var sky_dim: float = 0.0
var moon_illum: float = 1.0              # 0..1 moon brightness for this mission's date (MoonWeather); 1.0 = full moon

var sun_dir: Vector3 = Vector3.UP        # direction TOWARDS the sun
var sun_color: Color = Color.WHITE
var light_level: float = 1.0             # 0..1 overall brightness (for clouds, cockpit dimming)
var horizon_color: Color = Color.WHITE


func _ready() -> void:
	_build_keys()
	_build_nodes()
	set_time(hour)


func _k(h: float, top: Color, hor: Color, fog: Color, lc: Color, se: float, me: float, amb: Color, ae: float, stars: float, fd: float) -> Array:
	return [h, top, hor, fog, lc, se, me, amb, ae, stars, fd]


func _build_keys() -> void:
	var night := _k(0.0, Color(0.02, 0.03, 0.09), Color(0.07, 0.09, 0.17), Color(0.06, 0.08, 0.14), Color(0.6, 0.7, 1.0), 0.0, 0.4, Color(0.16, 0.20, 0.36), 0.9, 1.0, 0.00005)
	_keys = [
		night,
		_k(5.0, Color(0.02, 0.03, 0.09), Color(0.07, 0.09, 0.17), Color(0.06, 0.08, 0.14), Color(0.6, 0.7, 1.0), 0.0, 0.4, Color(0.16, 0.20, 0.36), 0.9, 1.0, 0.00005),
		_k(6.2, Color(0.34, 0.44, 0.68), Color(0.86, 0.66, 0.52), Color(0.76, 0.68, 0.63), Color(1.0, 0.66, 0.45), 1.0, 0.05, Color(0.46, 0.48, 0.62), 1.2, 0.15, 0.000060),
		_k(7.6, Color(0.30, 0.55, 0.86), Color(0.80, 0.86, 0.92), Color(0.76, 0.83, 0.89), Color(1.0, 0.92, 0.78), 1.0, 0.0, Color(0.50, 0.58, 0.72), 1.2, 0.0, 0.00005),
		_k(12.0, Color(0.20, 0.48, 0.88), Color(0.72, 0.84, 0.95), Color(0.72, 0.82, 0.92), Color(1.0, 0.97, 0.90), 1.05, 0.0, Color(0.55, 0.65, 0.80), 1.2, 0.0, 0.00005),
		_k(16.5, Color(0.26, 0.52, 0.86), Color(0.80, 0.84, 0.90), Color(0.78, 0.82, 0.88), Color(1.0, 0.93, 0.78), 1.2, 0.0, Color(0.52, 0.60, 0.74), 1.2, 0.0, 0.00005),
		_k(18.4, Color(0.26, 0.34, 0.62), Color(0.95, 0.60, 0.42), Color(0.74, 0.64, 0.58), Color(1.0, 0.58, 0.36), 1.0, 0.05, Color(0.48, 0.48, 0.62), 1.2, 0.2, 0.000060),
		_k(20.0, Color(0.05, 0.06, 0.16), Color(0.20, 0.16, 0.26), Color(0.14, 0.12, 0.20), Color(0.6, 0.7, 1.0), 0.0, 0.35, Color(0.20, 0.22, 0.38), 0.9, 0.8, 0.00005),
		_k(21.5, Color(0.02, 0.03, 0.09), Color(0.07, 0.09, 0.17), Color(0.06, 0.08, 0.14), Color(0.6, 0.7, 1.0), 0.0, 0.4, Color(0.16, 0.20, 0.36), 0.9, 1.0, 0.00005),
		_k(24.0, Color(0.02, 0.03, 0.09), Color(0.07, 0.09, 0.17), Color(0.06, 0.08, 0.14), Color(0.6, 0.7, 1.0), 0.0, 0.4, Color(0.16, 0.20, 0.36), 0.9, 1.0, 0.00005),
	]


func _build_nodes() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 1400.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 2.0
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	add_child(moon)

	var sky := Sky.new()
	sky_material = ShaderMaterial.new()
	sky_material.shader = load("res://shaders/sky.gdshader") as Shader
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_sky_affect = 0.18      # a little haze in the sky, so the horizon is not a hard cut
	# NO height fog. Godot's height fog is not distance-based: it adds 1 - exp((y - fog_height) * density) of fog
	# colour to every pixel below fog_height however close it is. With 120 / 0.006 that was a 51% veil of fog
	# colour over the whole sea (y = 0) right under the aircraft and ~25% over every airfield: the "white, flat
	# sea" and the washed-out low ground. Distance haze (exponential density + aerial perspective) remains.
	environment.fog_height = 0.0
	environment.fog_height_density = 0.0
	environment.fog_sun_scatter = 0.0
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.08
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)
	apply_post(GameState.post_fx)
	var glare := SunGlare.new()
	glare.name = "SunGlare"
	glare.tod = self
	add_child(glare)


## Post-processing level (GameState.post_fx): 0 = plain linear look, 1 = filmic tonemap + bloom + colour grade,
## 2 = also screen-space ambient occlusion and a sun-scatter glow in the fog / haze.
func apply_post(level: int) -> void:
	var on: bool = level >= 1
	var high: bool = level >= 2
	# ACES is the photographic reference response: it holds highlight detail in a bright sky and keeps
	# shadows open, which is what makes rendered daylight read as real rather than as "rendered".
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES if on else Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 5.0
	# sky reflections on glass, metal and wet surfaces (was disabled, which killed every specular)
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY if on else Environment.REFLECTION_SOURCE_DISABLED
	environment.glow_enabled = on
	environment.glow_intensity = 0.7
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.06
	environment.glow_hdr_threshold = 1.0
	environment.glow_hdr_scale = 2.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		environment.set_glow_level(i, 1.0 if i in [2, 3, 4] else 0.0)
	environment.adjustment_enabled = true
	# a real camera is not oversaturated: keep the grade subtle, the materials carry the colour now
	environment.adjustment_contrast = 1.05 if on else 1.0
	environment.adjustment_saturation = 1.05 if on else 1.0
	environment.ssao_enabled = high
	# AO can be real now: it used to fight the flat-shaded buildings, but the world is proper surfaces
	environment.ssao_radius = 2.4
	environment.ssao_intensity = 0.62
	environment.ssao_power = 1.3
	environment.fog_sun_scatter = 0.26 if high else 0.10
	environment.fog_aerial_perspective = 0.38 if high else 0.22
	# high only: one bounce of screen-space indirect light, and thin volumetric fog so the sun throws light shafts
	environment.ssil_enabled = high
	environment.ssil_intensity = 0.8
	environment.ssil_radius = 6.0
	environment.volumetric_fog_enabled = high and OS.get_environment("WW2_NO_VFOG") != "1"   # env switch: debug A/B
	environment.volumetric_fog_density = 0.0004
	environment.volumetric_fog_albedo = Color(0.92, 0.94, 1.0)
	environment.volumetric_fog_emission_energy = 0.0
	environment.volumetric_fog_anisotropy = 0.65
	environment.volumetric_fog_length = 600.0
	environment.volumetric_fog_detail_spread = 2.0
	environment.volumetric_fog_gi_inject = 0.0
	environment.volumetric_fog_sky_affect = 0.0


var _tick_acc: float = 0.0
## Industrial haze (D2): [lat, lon, radius km, strength]. The Ruhr's coking plants and steelworks and London's
## coal fires kept a brown pall over them that the bomber crews often could not see through (Wikipedia - Battle of
## the Ruhr: "industrial haze"; Great Smog / London fog).
const HAZE_AREAS := [[51.47, 7.10, 38.0, 1.0], [51.51, -0.10, 22.0, 0.7], [50.62, 5.55, 14.0, 0.5], [50.42, 4.45, 14.0, 0.5],
	[50.64, 3.07, 14.0, 0.45], [51.92, 4.48, 12.0, 0.35], [51.22, 4.40, 12.0, 0.35], [52.48, -1.90, 22.0, 0.6]]
var haze_k: float = 0.0
var _haze_acc: float = 1.0


func _update_haze(delta: float) -> void:
	_haze_acc += delta
	if _haze_acc < 1.0:
		return
	_haze_acc = 0.0
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var ll: Vector2 = WorldCoords.world_to_latlon(cam.global_position)
	var k: float = 0.0
	for a in HAZE_AREAS:
		var dlat: float = (ll.x - float(a[0])) * 111.0
		var dlon: float = (ll.y - float(a[1])) * 71.0
		var d: float = sqrt(dlat * dlat + dlon * dlon)
		k = maxf(k, float(a[3]) * (1.0 - smoothstep(float(a[2]) * 0.55, float(a[2]) * 1.35, d)))
	if absf(k - haze_k) > 0.0005:
		haze_k = lerpf(haze_k, k, 0.5) if absf(k - haze_k) > 0.02 else k
		_apply()


func _process(delta: float) -> void:
	_update_haze(delta)
	if time_scale != 0.0:
		# the sun moves slowly: re-light the sky / fog / HUD clock 5 times a second, not every frame
		_tick_acc += delta
		if _tick_acc >= 0.2:
			set_time(fposmod(hour + time_scale * _tick_acc, 24.0))
			_tick_acc = 0.0
	elif Input.is_action_just_pressed("time_cycle"):
		cycle_preset()


func _unhandled_input(event: InputEvent) -> void:
	if time_scale != 0.0 and event.is_action_pressed("time_cycle"):
		cycle_preset()


func set_preset(preset_name: String) -> void:
	if not PRESETS.has(preset_name):
		return
	current_preset = preset_name
	set_time(PRESETS[preset_name])
	preset_changed.emit(preset_name)


func cycle_preset() -> void:
	var i: int = PRESET_ORDER.find(current_preset)
	set_preset(PRESET_ORDER[(i + 1) % PRESET_ORDER.size()])


func set_weather_modifiers(p_fog_mul: float, p_light_mul: float, p_desat: float, p_sky_dim: float) -> void:
	fog_mul = p_fog_mul
	light_mul = p_light_mul
	desat = p_desat
	sky_dim = p_sky_dim
	_apply()


## Moon brightness for the mission date (MoonWeather.illumination); scales moonlight and the night-time moon glow.
func set_moon_illum(v: float) -> void:
	moon_illum = clampf(v, 0.0, 1.0)
	_apply()


func get_time_string() -> String:
	var h: int = int(floor(hour))
	var m: int = int((hour - floor(hour)) * 60.0)
	return "%02d:%02d" % [h, m]


func set_time(h: float) -> void:
	hour = fposmod(h, 24.0)
	var best: float = INF
	for p in PRESET_ORDER:
		var d: float = absf(PRESETS[p] - hour)
		if d < best:
			best = d
			current_preset = p
	_apply()
	time_changed.emit(hour)


func _sample() -> Array:
	var a: Array = _keys[0]
	var b: Array = _keys[_keys.size() - 1]
	for i in range(_keys.size() - 1):
		if hour >= _keys[i][0] and hour <= _keys[i + 1][0]:
			a = _keys[i]
			b = _keys[i + 1]
			break
	var span: float = maxf(b[0] - a[0], 0.0001)
	var t: float = clampf((hour - a[0]) / span, 0.0, 1.0)
	var out: Array = []
	for i in range(1, a.size()):
		out.append(lerp(a[i], b[i], t))
	return out  # top, hor, fog, lc, se, me, amb, ae, stars, fd


func _grey(c: Color, amount: float, dim: float) -> Color:
	var g: float = c.r * 0.3 + c.g * 0.59 + c.b * 0.11
	var out: Color = c.lerp(Color(g, g, g), amount)
	return out * (1.0 - dim)


func _apply() -> void:
	var s: Array = _sample()
	# Sun path: east at 6h, south-ish zenith at 12h, west at 18h.
	var a: float = (hour - 6.0) / 12.0 * PI
	sun_dir = Vector3(cos(a), sin(a), 0.38).normalized()
	# the moon rides lower than the sun did (about 30 degrees up at midnight) so it lays a long path on the water
	var moon_dir: Vector3 = Vector3(-sun_dir.x, -sun_dir.y * 0.4, 0.55).normalized()

	var top: Color = _grey(s[0], desat, sky_dim)
	var hor: Color = _grey(s[1], desat, sky_dim * 0.6)
	var fogc: Color = _grey(s[2], desat, sky_dim * 0.6)
	var lc: Color = s[3]
	var sun_e: float = s[4] * light_mul * clampf(sun_dir.y * 6.0, 0.0, 1.0)
	var moon_e: float = s[5] * clampf(moon_dir.y * 4.0, 0.0, 1.0) * (0.6 + 0.4 * light_mul) * lerpf(0.3, 1.0, moon_illum)
	var amb: Color = _grey(s[6], desat * 0.5, 0.0)
	var amb_e: float = s[7] * (0.55 + 0.45 * light_mul)

	sun.light_color = lc
	sun.light_energy = sun_e
	sun.visible = sun_e > 0.001
	sun.global_transform = Transform3D(Basis.looking_at(-sun_dir, Vector3.UP), Vector3.ZERO)
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_energy = moon_e
	moon.visible = moon_e > 0.001
	moon.global_transform = Transform3D(Basis.looking_at(-moon_dir, Vector3.UP), Vector3.ZERO)

	environment.ambient_light_color = amb
	environment.ambient_light_energy = amb_e
	environment.fog_light_color = fogc.lerp(Color(0.52, 0.47, 0.40), 0.3 * haze_k * clampf(sun_dir.y * 4.0, 0.0, 1.0))
	# light shafts: thicken the (high-preset) volumetric haze while the sun is low, so a dawn or dusk sun throws
	# visible rays through the gaps between clouds; thin again by day so the noon air stays clear
	if environment.volumetric_fog_enabled:
		var low: float = smoothstep(0.42, 0.06, sun_dir.y) * smoothstep(-0.06, 0.03, sun_dir.y)
		environment.volumetric_fog_density = (0.0004 + 0.0007 * low) * clampf(fog_mul, 0.6, 2.0)
		environment.volumetric_fog_albedo = Color(0.92, 0.94, 1.0).lerp(lc, 0.45 * low)
		environment.volumetric_fog_anisotropy = 0.65 + 0.2 * low
		sun.light_volumetric_fog_energy = 1.0 + 0.8 * low
	environment.fog_density = float(s[9]) * fog_mul * (1.0 + 0.4 * haze_k) * (0.0 if OS.get_environment("WW2_NO_FOG") == "1" else 1.0)
	sun_color = lc
	horizon_color = hor
	light_level = clampf(sun_e / 1.3 + moon_e * 0.3 + 0.12, 0.0, 1.0)
	var na: float = clampf((0.55 - light_level) / 0.4, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("night_amount", na)
	# Airfield lamps: full at night, and still visible through dawn / dusk while the sun is low, so a grass
	# strip has a lit edge instead of going flat dark before the sun is fully up.
	var low_sun: float = smoothstep(0.34, 0.0, sun_dir.y) * 0.6
	RenderingServer.global_shader_parameter_set("lamp_amount", clampf(maxf(na, low_sun), 0.0, 1.0))
	# Wartime blackout: at night the towns go almost fully dark, leaving only a few dim windows (toon.gdshader
	# scales the lit-window emission by `blackout`). Zero by day, so nothing changes in daylight.
	RenderingServer.global_shader_parameter_set("blackout", na)

	# the sea reflects the sky (water.gdshader Fresnel term)
	RenderingServer.global_shader_parameter_set("sky_top", Vector3(top.r, top.g, top.b))
	RenderingServer.global_shader_parameter_set("sky_horizon", Vector3(hor.r, hor.g, hor.b))
	sky_material.set_shader_parameter("top_color", top)
	sky_material.set_shader_parameter("horizon_color", hor)
	sky_material.set_shader_parameter("ground_color", hor.darkened(0.35))
	sky_material.set_shader_parameter("sun_dir", sun_dir)
	sky_material.set_shader_parameter("moon_dir", moon_dir)
	sky_material.set_shader_parameter("sun_color", lc.lightened(0.3))
	sky_material.set_shader_parameter("star_amount", float(s[8]) * (1.0 - sky_dim))
