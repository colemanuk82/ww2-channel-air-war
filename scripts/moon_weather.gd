class_name MoonWeather
extends RefCounted
## Moon phase and weather as mission conditions. Pure data helpers, no nodes:
##   illumination(date) -> 0..1 lit fraction of the moon that night; moon_name(date)
##   forecast(date, lat, lon) -> a WeatherManager preset, deterministic for the date and route (the planner's seed)
##   nav_penalty(weather) -> 0..1 navigation difficulty (the minimap loses ground detail, the planner warns)
##   moon_light() / nav_penalty_now() read the live TimeOfDay / WeatherManager autoloads.
## Dates are ISO "YYYY-MM-DD" strings. The planner's date slider runs DATE_START .. DATE_START + DATE_SPAN_DAYS.

const SYNODIC: float = 29.530588853
const NEW_MOON_EPOCH_JDN: float = 2451550.26     # new moon of 2000-01-06 18:14 UTC
const DATE_START: String = "1940-06-01"
const DATE_SPAN_DAYS: int = 213                  # to 1940-12-31
const DEFAULT_DATE: String = "1940-09-15"

## Forecast weights for a planned sortie (sum 1.0). Names are WeatherManager presets.
const FORECAST_WEIGHTS := [["clear", 0.30], ["scattered", 0.25], ["overcast", 0.20], ["rain", 0.10], ["fog", 0.10], ["storm", 0.05]]
## Navigation difficulty per preset: cuts map detail back and makes the planner warn.
const NAV_PENALTY := {"clear": 0.0, "scattered": 0.05, "overcast": 0.25, "rain": 0.35, "storm": 0.5, "fog": 0.6}


## Julian day number (noon) of an ISO date.
@warning_ignore("integer_division")
static func jdn(date: String) -> int:
	var p: PackedStringArray = date.split("-")
	var y: int = int(p[0])
	var m: int = int(p[1])
	var d: int = int(p[2])
	var a: int = (14 - m) / 12
	var yy: int = y + 4800 - a
	var mm: int = m + 12 * a - 3
	return d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045


## ISO date of a Julian day number (inverse of jdn).
@warning_ignore("integer_division")
static func date_from_jdn(j: int) -> String:
	var a: int = j + 32044
	var b: int = (4 * a + 3) / 146097
	var c: int = a - 146097 * b / 4
	var d: int = (4 * c + 3) / 1461
	var e: int = c - 1461 * d / 4
	var m: int = (5 * e + 2) / 153
	var day: int = e - (153 * m + 2) / 5 + 1
	var month: int = m + 3 - 12 * (m / 10)
	var year: int = 100 * b + d - 4800 + m / 10
	return "%04d-%02d-%02d" % [year, month, day]


## Planner date slider: days after DATE_START and back.
static func date_at_offset(offset: int) -> String:
	return date_from_jdn(jdn(DATE_START) + clampi(offset, 0, DATE_SPAN_DAYS))


static func offset_of(date: String) -> int:
	return jdn(date) - jdn(DATE_START)


## Days since the last new moon (0 = new, ~14.8 = full).
static func moon_age(date: String) -> float:
	return fposmod(float(jdn(date)) - NEW_MOON_EPOCH_JDN, SYNODIC)


## Lit fraction of the moon's disc, 0 (new) .. 1 (full).
static func illumination(date: String) -> float:
	return (1.0 - cos(TAU * moon_age(date) / SYNODIC)) * 0.5


static func moon_name(date: String) -> String:
	var age: float = moon_age(date)
	if age < 1.85 or age >= 27.7:
		return "New moon"
	if age < 7.4:
		return "Waxing crescent"
	if age < 9.2:
		return "First quarter"
	if age < 13.8:
		return "Waxing gibbous"
	if age < 15.7:
		return "Full moon"
	if age < 21.0:
		return "Waning gibbous"
	if age < 22.9:
		return "Last quarter"
	return "Waning crescent"


## Weather preset for a sortie: the same date and route always roll the same forecast.
static func forecast(date: String, lat: float, lon: float) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s|%.2f|%.2f" % [date, lat, lon]).hash()
	var roll: float = rng.randf()
	var acc: float = 0.0
	for w in FORECAST_WEIGHTS:
		acc += float(w[1])
		if roll < acc:
			return String(w[0])
	return "clear"


static func nav_penalty(weather: String) -> float:
	return float(NAV_PENALTY.get(weather, 0.0))


static func _autoload(node_name: String) -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null(node_name)
	return null


## Live moon brightness (TimeOfDay.moon_illum, set per mission); 1.0 when there is no TimeOfDay.
static func moon_light() -> float:
	var tod: Node = _autoload("TimeOfDay")
	return clampf(float(tod.get("moon_illum")), 0.0, 1.0) if tod != null else 1.0


## Live navigation penalty from the current weather.
static func nav_penalty_now() -> float:
	var wm: Node = _autoload("WeatherManager")
	return nav_penalty(str(wm.get("current"))) if wm != null else 0.0
