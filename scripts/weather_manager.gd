extends Node
## Weather (autoload "WeatherManager"). set_weather(name, blend_time); signal weather_changed.
## Stage 1: clear / scattered / overcast with toon cloud puffs; rain/storm/fog map to heavier
## fog + darkening for now (particles and lightning come in Stage 5).

signal weather_changed(weather_name: String)

const PRESETS := {
	# cover: cloud puff fraction, fog: fog density multiplier, light: sun strength, desat, dim: sky dimming, cloud_dark
	"clear": {"precip": 0.0, "cover": 0.30, "fog": 1.0, "light": 1.0, "desat": 0.0, "dim": 0.0, "cloud_dark": 0.0, "wind_lo": 2.0, "wind_hi": 7.0},
	"scattered": {"precip": 0.0, "cover": 0.62, "fog": 1.2, "light": 0.95, "desat": 0.08, "dim": 0.03, "cloud_dark": 0.05, "wind_lo": 5.0, "wind_hi": 11.0},
	"overcast": {"precip": 0.04, "cover": 1.0, "fog": 2.2, "light": 0.55, "desat": 0.55, "dim": 0.18, "cloud_dark": 0.35, "wind_lo": 8.0, "wind_hi": 14.0},
	"rain": {"precip": 0.7, "cover": 1.0, "fog": 3.5, "light": 0.42, "desat": 0.65, "dim": 0.28, "cloud_dark": 0.5, "wind_lo": 10.0, "wind_hi": 17.0},
	"storm": {"precip": 1.0, "cover": 1.0, "fog": 4.5, "light": 0.3, "desat": 0.7, "dim": 0.42, "cloud_dark": 0.7, "wind_lo": 16.0, "wind_hi": 27.0},
	"fog": {"precip": 0.0, "cover": 0.6, "fog": 12.0, "light": 0.6, "desat": 0.5, "dim": 0.1, "cloud_dark": 0.2, "wind_lo": 0.0, "wind_hi": 3.0},
}
const ORDER := ["clear", "scattered", "overcast", "rain", "storm", "fog"]

var current: String = "clear"
var cloud_field: CloudField
var rain_fx: RainFX
var rain: float = 0.0            # rain at the camera right now (0..1): weather precip plus any rain cloud overhead
var wetness: float = 0.0         # ground wetness 0..1 (lags the rain: soaks in, dries slowly)

# ---- weather fronts. A front is a long line moving across the map with the wind. The weather where you are
# depends on which side of it you are: ahead of it the base weather, then thickening cloud as it nears, a band of
# rain (a cold front brings storms and towering cloud) along the line itself, broken showery cloud behind it, then
# clearing. The clouds themselves follow the same profile (CloudField asks cover_at() for each cloud), so the
# front is visible coming in as a wall of cloud. Sector Control / Jafü warn of it. A new front forms upwind once
# the last has passed. set_weather() sets the base weather; fronts_enabled = false keeps the weather fixed.
const FRONT_LADDER := ["clear", "scattered", "overcast", "rain"]
var fronts_enabled: bool = true
var _front_timer: float = 420.0
var _front_dir: int = 1
var _rain_tick: int = 0
var _force_rain: bool = OS.get_cmdline_user_args().has("--rain-now")     # debug: steady rain at the camera
var base_weather: String = "clear"
var front_active: bool = false
var front_cold: bool = true          # cold front: sharp, stormy band; warm front: wide rain belt ahead of the line
var front_normal: Vector2 = Vector2(1, 0)   # direction the front moves (blow-to of the wind)
var front_offset: float = 0.0        # signed distance of the line along front_normal from the world origin
var front_speed: float = 14.0        # units/s
var _front_zone: String = ""
var _front_warned: int = 0
var _front_check: float = 0.0
const FRONT_AHEAD_FAR: float = 42000.0     # cloud starts thickening this far ahead of the line
const FRONT_AHEAD_NEAR: float = 9000.0     # rain belt starts (warm fronts start it further out)
const FRONT_BEHIND: float = -7000.0        # back edge of the rain band
const FRONT_CLEAR: float = -26000.0        # showers end behind the line

# ---- wind (units/s, i.e. m/s-equivalent). wind_dir_deg is where the wind blows FROM (meteorological).
var wind_dir_deg: float = 240.0
var wind_speed: float = 5.0            # mean surface wind
var _wind_target_dir: float = 240.0
var _wind_target_speed: float = 5.0
var _wind_timer: float = 0.0
var _wind_t: float = 0.0
var cloud_drift: Vector2 = Vector2.ZERO    # accumulated cloud movement with the wind

var _from: Dictionary = {}
var _to: Dictionary = {}
var _cur: Dictionary = {}
var _t: float = 1.0
var _dur: float = 1.0


func _ready() -> void:
	randomize()
	# Prevailing south-westerlies over the Channel most of the time, otherwise any direction.
	wind_dir_deg = fposmod(randfn(240.0, 35.0), 360.0) if randf() < 0.65 else randf() * 360.0
	_wind_target_dir = wind_dir_deg
	cloud_field = CloudField.new()
	cloud_field.name = "Clouds"
	add_child(cloud_field)
	_cur = (PRESETS["clear"] as Dictionary).duplicate()
	_from = _cur.duplicate()
	_to = _cur.duplicate()
	_retarget_wind(false)
	wind_speed = _wind_target_speed
	rain_fx = RainFX.new()
	rain_fx.name = "RainFX"
	add_child(rain_fx)
	var cpf := CloudPassFX.new()
	cpf.name = "CloudPassFX"
	add_child(cpf)
	_front_timer = randf_range(300.0, 600.0)
	_apply()
	TimeOfDay.time_changed.connect(func(_h: float) -> void: _apply())


func get_weather_names() -> Array:
	return ORDER


## Re-roll the wind target inside the current weather's band (called on weather change and every ~2 min).
func _retarget_wind(shift_dir: bool) -> void:
	var lo: float = float(_to.get("wind_lo", 2.0)) if not _to.is_empty() else 3.0
	var hi: float = float(_to.get("wind_hi", 8.0)) if not _to.is_empty() else 8.0
	_wind_target_speed = randf_range(lo, hi)
	var shift: float = randf_range(-25.0, 25.0)
	if shift_dir:
		shift = randf_range(35.0, 80.0) * (1.0 if randf() < 0.6 else -1.0)   # a front passing veers the wind
	_wind_target_dir = fposmod(_wind_target_dir + shift, 360.0)
	_wind_timer = randf_range(90.0, 180.0)


## Wind vector (blow-TO direction) at a world position, in units/s, with altitude shear and gusts.
func get_wind(pos: Vector3) -> Vector3:
	var alt_m: float = maxf(pos.y / WorldCoords.VERTICAL_SCALE, 0.0)
	var shear: float = 1.0 + clampf(alt_m / 3000.0, 0.0, 1.0) * 0.8      # stronger aloft
	var veer: float = clampf(alt_m / 2000.0, 0.0, 1.0) * 22.0            # backs/veers with height
	var g: float = 0.5 * sin(_wind_t * 0.7 + pos.x * 0.0009) + 0.3 * sin(_wind_t * 1.9 + pos.z * 0.0013 + 1.3) + 0.2 * sin(_wind_t * 4.3 + (pos.x + pos.z) * 0.002)
	var spd: float = maxf(wind_speed * shear + g * wind_speed * 0.2, 0.0)
	return WorldCoords.heading_to_dir(wind_dir_deg + veer + 180.0) * spd


## 0..1 low-level turbulence (rough air): grows with wind strength, worst near the ground and in storms.
func get_turbulence(agl: float) -> float:
	var base: float = clampf((wind_speed - 4.0) / 22.0, 0.0, 1.0)
	var low: float = 1.0 + clampf((400.0 - agl) / 400.0, 0.0, 1.0) * 0.8
	var stormy: float = clampf(float(_cur.get("cloud_dark", 0.0)) * 0.6, 0.0, 0.4)
	return clampf(base * low + stormy, 0.0, 1.0)


func get_visibility_multiplier() -> float:
	return 1.0 / maxf(float(_cur["fog"]), 0.5)


func set_weather(weather_name: String, blend_time: float = 4.0) -> void:
	if not PRESETS.has(weather_name):
		push_warning("WeatherManager: unknown weather '%s'" % weather_name)
		return
	base_weather = weather_name
	if front_active and weather_name in ["fog", "storm"]:
		cancel_front()
	if front_active:
		_front_zone = ""           # an active front keeps going; the weather here is re-read on the next tick
		_front_check = 0.0
		return
	_blend_to(weather_name, blend_time)


func cancel_front() -> void:
	front_active = false
	_front_zone = ""
	_front_warned = 0


func _blend_to(weather_name: String, blend_time: float) -> void:
	current = weather_name
	_from = _cur.duplicate()
	_to = (PRESETS[weather_name] as Dictionary).duplicate()
	_dur = maxf(blend_time, 0.01)
	_t = 0.0
	_retarget_wind(true)
	_front_timer = randf_range(420.0, 780.0)
	weather_changed.emit(weather_name)


## A front moves through: step one rung up or down the ladder (slow 70 s blend, wind veers).
func advance_front() -> void:
	var i: int = FRONT_LADDER.find(current)
	if i < 0:
		return                       # fog / storm presets are left alone
	if i == FRONT_LADDER.size() - 1:
		_front_dir = -1
	elif i == 0:
		_front_dir = 1
	elif randf() < 0.2:
		_front_dir = -_front_dir      # sometimes the front stalls and the system retreats
	set_weather(FRONT_LADDER[clampi(i + _front_dir, 0, FRONT_LADDER.size() - 1)], 70.0)


func cycle_weather() -> void:
	var i: int = ORDER.find(current)
	set_weather(ORDER[(i + 1) % ORDER.size()])


func _process(delta: float) -> void:
	_wind_t += delta
	_wind_timer -= delta
	if _wind_timer <= 0.0:
		_retarget_wind(false)
	wind_speed = move_toward(wind_speed, _wind_target_speed, delta * 0.15)
	var dd: float = rad_to_deg(angle_difference(deg_to_rad(wind_dir_deg), deg_to_rad(_wind_target_dir)))
	wind_dir_deg = fposmod(wind_dir_deg + clampf(dd, -0.5 * delta, 0.5 * delta), 360.0)
	cloud_drift += Vector2(get_wind(Vector3(0, 1500, 0)).x, get_wind(Vector3(0, 1500, 0)).z) * delta
	if fronts_enabled:
		_front_tick(delta)
	_update_rain(delta)
	if Input.is_action_just_pressed("weather_cycle"):
		cycle_weather()
	if _t < 1.0:
		_t = minf(_t + delta / _dur, 1.0)
		var k: float = smoothstep(0.0, 1.0, _t)
		for key in _to.keys():
			_cur[key] = lerpf(float(_from[key]), float(_to[key]), k)
		_apply()
	# keep cloud tint in sync while time of day animates
	elif Engine.get_process_frames() % 30 == 0:
		_apply()


## Rain at the camera: the weather's own precipitation, plus showers falling from a rain cloud overhead.
func _update_rain(delta: float) -> void:
	_rain_tick += 1
	var cam: Camera3D = get_viewport().get_camera_3d()
	# Rain falls only where a rain cloud is overhead, so the clear gaps between cells stay dry.
	var target: float = 0.0
	if cam != null and cloud_field != null:
		if _rain_tick % 6 == 0:
			cloud_field.sample_rain(cam.global_position)
		target = clampf(cloud_field.rain_here, 0.0, 1.0)
	if _force_rain:
		target = 1.0
	rain = move_toward(rain, target, delta * 0.5)
	wetness = move_toward(wetness, 1.0 if rain > 0.15 else 0.0, delta * (0.08 if rain > 0.15 else 0.012))
	RenderingServer.global_shader_parameter_set("wetness", wetness)
	if rain_fx:
		rain_fx.intensity = rain
		rain_fx.storm = clampf((float(_cur.get("cloud_dark", 0.0)) - 0.45) / 0.25, 0.0, 1.0)
	if cloud_field:
		cloud_field.set_rain_level(maxf(float(_cur.get("precip", 0.0)), rain))
	if _rain_tick % 10 == 0:
		_apply()


func _apply() -> void:
	TimeOfDay.set_weather_modifiers(float(_cur["fog"]) * (1.0 + rain * 1.1), _cur["light"], _cur["desat"] + rain * 0.1, _cur["dim"])
	if cloud_field:
		cloud_field.cover = _cur["cover"]
		var ll: float = TimeOfDay.light_level
		var dark: float = float(_cur["cloud_dark"])
		var base: Color = TimeOfDay.sun_color.lerp(Color.WHITE, 0.6)
		var shade: Color = TimeOfDay.horizon_color.lerp(Color(0.5, 0.58, 0.72), 0.5)
		cloud_field.mat.set_shader_parameter("cloud_color", base.lerp(Color(0.72, 0.74, 0.78), dark))
		cloud_field.mat.set_shader_parameter("shade_color", shade.lerp(Color(0.45, 0.47, 0.53), dark))
		cloud_field.mat.set_shader_parameter("light_level", lerpf(0.18, 1.0, ll))
		cloud_field.mat.set_shader_parameter("density_scale", 1.0 + dark * 1.2)


# ------------------------------------------------------------------ moving fronts

func _cam_pos() -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d()
	return cam.global_position if cam != null else Vector3.ZERO


## Signed distance of a world point ahead of the front line (+ = the front has not reached it yet).
func front_distance(p: Vector3) -> float:
	return front_offset - Vector2(p.x, p.z).dot(front_normal)


## Spawn a front upwind of the camera, arriving in roughly `eta` seconds.
func spawn_front(eta: float = -1.0) -> void:
	if base_weather in ["fog", "storm"]:
		return
	var blow_to: Vector3 = WorldCoords.heading_to_dir(wind_dir_deg + 180.0)
	front_normal = Vector2(blow_to.x, blow_to.z).normalized()
	front_speed = randf_range(12.0, 20.0)
	front_cold = randf() < 0.55
	if eta < 0.0:
		eta = randf_range(900.0, 2100.0)      # 15-35 minutes away
	# placed relative to the camera on the first tick it exists (at sortie start it is not there yet)
	_front_place_eta = eta
	_front_age = 0.0
	front_active = true
	_front_zone = ""
	_front_warned = 0


var _front_place_eta: float = -1.0


func _place_front() -> bool:
	# relative to the player's aircraft once the sortie is under way (not during loading, before the start point
	# is set, or the front would be measured from the wrong place)
	var pl: Node3D = null
	for n in get_tree().get_nodes_in_group("aircraft"):
		if bool(n.get("player_controlled")):
			pl = n as Node3D
			break
	if pl == null or not pl.is_inside_tree() or pl.process_mode == Node.PROCESS_MODE_DISABLED:
		return false
	var c: Vector3 = pl.global_position
	front_offset = Vector2(c.x, c.z).dot(front_normal) - (FRONT_AHEAD_NEAR + front_speed * _front_place_eta)
	_front_place_eta = -1.0
	return true


## Cloud cover (0..1) the front gives at a world point; the base weather's cover away from it.
func cover_at(p: Vector3) -> float:
	var base_c: float = float((PRESETS[base_weather] as Dictionary)["cover"]) if PRESETS.has(base_weather) else 0.3
	if not front_active or _front_place_eta >= 0.0:
		return -1.0
	var d: float = front_distance(p)
	var near: float = FRONT_AHEAD_NEAR * (1.0 if front_cold else 2.4)
	if d > FRONT_AHEAD_FAR:
		return base_c
	if d > near:
		return lerpf(maxf(base_c, 0.85 if not front_cold else 0.6), base_c, (d - near) / (FRONT_AHEAD_FAR - near))
	if d > FRONT_BEHIND:
		return 1.0
	if d > FRONT_CLEAR:
		return lerpf(base_c, 0.66, (d - FRONT_CLEAR) / (FRONT_BEHIND - FRONT_CLEAR))
	return base_c


## The named weather at a distance from the line.
func _zone_weather(d: float) -> String:
	var near: float = FRONT_AHEAD_NEAR * (1.0 if front_cold else 2.4)
	if d > FRONT_AHEAD_FAR:
		return base_weather
	if d > near:
		return "overcast" if d < FRONT_AHEAD_FAR * 0.6 or not front_cold else ("scattered" if base_weather == "clear" else base_weather)
	if d > FRONT_BEHIND:
		return "storm" if front_cold and d < FRONT_AHEAD_NEAR * 0.45 and d > FRONT_BEHIND * 0.5 else "rain"
	if d > FRONT_CLEAR:
		return "scattered"
	return base_weather


func _front_tick(delta: float) -> void:
	if not front_active:
		_front_timer -= delta
		if _front_timer <= 0.0:
			_front_timer = randf_range(600.0, 1200.0)
			spawn_front()
		return
	if _front_place_eta >= 0.0 and not _place_front():
		return
	front_offset += front_speed * delta
	_front_check -= delta
	if _front_check > 0.0:
		return
	_front_check = 1.0
	var d: float = front_distance(_cam_pos())
	var zone: String = _zone_weather(d)
	if zone != _front_zone:
		var first: bool = _front_zone == ""
		_front_zone = zone
		if zone != current:
			_blend_to(zone, 2.0 if first else 75.0)
			_retarget_wind(true)
	_front_warn(d)
	if d < FRONT_CLEAR - 25000.0:
		front_active = false                    # long gone: the next one forms upwind in a while
		_front_timer = randf_range(600.0, 1500.0)
		_blend_to(base_weather, 90.0)


var _front_age: float = 0.0


func _front_warn(d: float) -> void:
	var c: Vector3 = _cam_pos()
	if c == Vector3.ZERO:
		return
	_front_age += 1.0
	if _front_age < 5.0:
		return          # not during loading: the radio channel is cleared when the sortie starts
	var side: String = GameState.player_side
	var who: String = "Jafü 2" if side == "Axis" else "Sector Control"
	var mins: int = int(round(maxf(d - FRONT_AHEAD_NEAR, 0.0) / maxf(front_speed, 1.0) / 60.0))
	var from_dir: String = _compass_word(-front_normal)
	if _front_warned == 0 and d < FRONT_AHEAD_FAR + 15000.0 and d > FRONT_AHEAD_NEAR:
		_front_warned = 1
		Radio.say(who, "Met reports a %s front coming in from the %s. Rain and low cloud in about %d minutes." % ["cold" if front_cold else "warm", from_dir, maxi(mins, 1)], Radio.Kind.CONTROL, 2.0)
	elif _front_warned == 1 and d < FRONT_AHEAD_NEAR:
		_front_warned = 2
		Radio.say(who, "The front is on top of you. %s" % ("Thunderstorms in the band - keep out of the big cumulonimbus." if front_cold else "Rain and low cloud for a good while yet."), Radio.Kind.CONTROL, 1.0)
	elif _front_warned == 2 and d < FRONT_CLEAR:
		_front_warned = 3
		Radio.say(who, "The front has gone through. It's clearing from the %s." % from_dir, Radio.Kind.CONTROL, 1.0)


static func _compass_word(v: Vector2) -> String:
	var h: float = fposmod(rad_to_deg(atan2(v.x, -v.y)), 360.0)
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return names[int(round(h / 45.0)) % 8]


## For the minimap / chart: the front line as {active, normal (Vector2, direction of travel), offset, cold}.
func front_info() -> Dictionary:
	return {"active": front_active and _front_place_eta < 0.0, "normal": front_normal, "offset": front_offset, "cold": front_cold}
