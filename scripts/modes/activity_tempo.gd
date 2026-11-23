extends RefCounted
## Free-flight "tempo": the enemy activity drifts between busy spells and natural lulls (a few minutes, now and then
## 5-10), so a sortie does not feel like a conveyor belt. Pure rules (static, unit-tested) plus a tiny state machine
## (one instance, owned by EnemyFlights). Built without class_name (a new class_name needs an editor import first):
## load it with preload("res://scripts/modes/activity_tempo.gd").
##
## "Enemy activity" option (sortie page, free flight): Quiet / Normal / Busy.
##   Quiet   long lulls, sparse contacts      Normal  varied tempo with the odd quiet spell (default)
##   Busy    rare, short lulls, more action
## A lull holds back NEW enemy flights, airfield sorties, land battles, naval fights and the cross-Channel guns
## (flights already in the air are never removed). Night and bad weather make a lull more likely, never permanent.
## A big raid can still break a lull now and then; the end of a lull is announced as a light radio cue.

const IDS: Array = ["quiet", "normal", "busy"]
const LABELS: Array = ["Quiet", "Normal", "Busy"]
const DEFAULT: String = "normal"

## lull_p: chance that a busy spell is followed by a lull; lull_*: normal lull length (s); long_*: the occasional long
## lull; act_*: length of a busy spell; launch_k / event_k: multiplier on the gap between flights / ground-sea events
## (below 1 = more often); break_p: chance per 10 s inside a lull that a big raid breaks it; max_flights: flights up.
const PARAMS := {
	"quiet": {"lull_p": 0.75, "lull_min": 240.0, "lull_max": 420.0, "long_p": 0.35, "long_min": 420.0, "long_max": 660.0,
		"act_min": 90.0, "act_max": 200.0, "launch_k": 1.5, "event_k": 1.6, "break_p": 0.006, "max_flights": 2},
	"normal": {"lull_p": 0.55, "lull_min": 120.0, "lull_max": 300.0, "long_p": 0.2, "long_min": 300.0, "long_max": 600.0,
		"act_min": 240.0, "act_max": 480.0, "launch_k": 1.0, "event_k": 1.0, "break_p": 0.010, "max_flights": 3},
	"busy": {"lull_p": 0.2, "lull_min": 40.0, "lull_max": 100.0, "long_p": 0.0, "long_min": 100.0, "long_max": 100.0,
		"act_min": 360.0, "act_max": 720.0, "launch_k": 0.6, "event_k": 0.65, "break_p": 0.020, "max_flights": 4},
}
## Group size odds [small, medium, large] per level (Normal is EnemyFlights.SIZE_ODDS).
const SIZE_ODDS := {"quiet": [0.72, 0.22, 0.06], "normal": [0.62, 0.28, 0.10], "busy": [0.45, 0.38, 0.17]}
const FIRST_SPELL: Vector2 = Vector2(150.0, 260.0)      # the first busy spell once airborne (before any lull)

# Shared state read by the other ambient systems (set by FreeFlightMode.configure / EnemyFlights).
static var level: String = DEFAULT
static var lulling: bool = false
static var night: bool = false
static var bad_weather: bool = false

var lull: bool = false
var t_left: float = 0.0           # seconds left in the current spell
var elapsed: float = 0.0
var lull_len: float = 0.0         # length of the current / last lull
var lulls: int = 0                # lulls begun so far
var broken: int = 0               # lulls cut short by a big raid
var history: Array = []           # {"t", "what" (lull / busy / broken), "len"}
var _rng := RandomNumberGenerator.new()
var _break_t: float = 10.0
var _lull_start: float = 0.0


static func sanitize(id: String) -> String:
	return id if IDS.has(id) else DEFAULT


static func index_of(id: String) -> int:
	return maxi(IDS.find(sanitize(id)), 0)


static func param(lvl: String, key: String) -> Variant:
	return (PARAMS[sanitize(lvl)] as Dictionary)[key]


static func is_bad_weather(w: String) -> bool:
	return w in ["rain", "storm", "fog", "overcast"]


## Chance that a busy spell ends in a lull: more at night and in bad weather, capped so a spell can always follow.
static func lull_chance(lvl: String, is_night: bool, bad_wx: bool) -> float:
	var p: float = float(param(lvl, "lull_p"))
	if is_night:
		p *= 1.25
	if bad_wx:
		p *= 1.2
	return clampf(p, 0.0, 0.95)


## Length of a lull: r_long picks the occasional long one, r_len places it inside its range.
static func lull_length(lvl: String, r_long: float, r_len: float) -> float:
	if r_long < float(param(lvl, "long_p")):
		return lerpf(float(param(lvl, "long_min")), float(param(lvl, "long_max")), r_len)
	return lerpf(float(param(lvl, "lull_min")), float(param(lvl, "lull_max")), r_len)


## Length of a busy spell (a little shorter at night and in bad weather).
static func spell_length(lvl: String, is_night: bool, bad_wx: bool, r: float) -> float:
	var s: float = lerpf(float(param(lvl, "act_min")), float(param(lvl, "act_max")), r)
	if is_night:
		s *= 0.85
	if bad_wx:
		s *= 0.9
	return s


## Gap multiplier for flights / sorties and for land, sea and gun events at the current level.
static func launch_scale() -> float:
	return float(param(level, "launch_k"))


static func event_scale() -> float:
	return float(param(level, "event_k"))


static func size_odds(lvl: String) -> Array:
	return SIZE_ODDS[sanitize(lvl)]


func begin(seed_val: int = 0) -> void:
	if seed_val != 0:
		_rng.seed = seed_val
	else:
		_rng.randomize()
	lull = false
	elapsed = 0.0
	lulls = 0
	broken = 0
	history.clear()
	_break_t = 10.0
	t_left = _rng.randf_range(FIRST_SPELL.x, FIRST_SPELL.y)
	_publish()


func _publish() -> void:
	lulling = lull


## Advance by dt seconds. Returns "" or what just began: "lull", "busy" (a natural end of a lull) or "broken".
func advance(dt: float) -> String:
	elapsed += dt
	if lull:
		_break_t -= dt
		if _break_t <= 0.0:
			_break_t = 10.0
			if t_left > 45.0 and _rng.randf() < float(param(level, "break_p")):
				return _end_lull("broken")
	t_left -= dt
	if t_left > 0.0:
		return ""
	if lull:
		return _end_lull("busy")
	if _rng.randf() < lull_chance(level, night, bad_weather):
		lull = true
		lulls += 1
		_lull_start = elapsed
		lull_len = lull_length(level, _rng.randf(), _rng.randf())
		t_left = lull_len
		history.append({"t": elapsed, "what": "lull", "len": lull_len})
		_publish()
		return "lull"
	t_left = spell_length(level, night, bad_weather, _rng.randf())      # another busy spell
	return ""


func _end_lull(what: String) -> String:
	lull = false
	if what == "broken":
		broken += 1
	t_left = spell_length(level, night, bad_weather, _rng.randf())
	history.append({"t": elapsed, "what": what, "len": elapsed - _lull_start})
	_publish()
	return what
