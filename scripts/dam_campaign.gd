class_name DamCampaign
extends RefCounted
## The Dam Busters course: one mission per day, in order. Each day unlocks when the one before it is passed.
## Progress is saved in user://dambusters.json (per player, separate from the career campaign).

const SAVE_PATH := "user://dambusters.json"
const APPROACH_M := 12000.0     # the aircraft starts this far out, on the approach bearing
const START_ALT_M := 60.0
## Appended to every day's brief: the HUD steering marker.
const STEER_NOTE := "\n\nSteer by the blue marker on the compass. It points to the next ring or target, then home."

## kind: low | skip | range | dam (see DamRunMode). target: [lat, lon] the run is aimed at.
## approach: bearing (deg, clockwise from north) from the target to the start point.
const DAYS: Array = [
	{"id": "d1", "title": "Day 1: Low flying", "kind": "low",
		"brief": "Learn to fly low over the Channel. Pass through the three glowing rings at 60 ft or less, then get back to the airfield with the gear down. Let go of the stick and the aircraft holds its speed: tap the throttle until the climb gauge reads LEVEL, or press R for altitude hold.",
		"target": [50.66, 0.95], "approach": 270.0,
		"rings": [[50.66, 0.95], [50.665, 1.00], [50.67, 1.06]]},
	{"id": "d2", "title": "Day 2: Skipping", "kind": "skip",
		"brief": "Drop the bouncing bomb on the flat water range. Watch the camera follow it skip. It must bounce at least 4 times before it sinks.",
		"target": [50.62, 0.90], "approach": 270.0, "marker": [50.62, 0.90]},
	{"id": "d3", "title": "Day 3: Release timing", "kind": "range",
		"brief": "Release the bomb at the right moment so it sinks within 120 m of the ring on the water.",
		"target": [50.62, 0.90], "approach": 270.0, "marker": [50.62, 0.97]},
	{"id": "d4", "title": "Day 4: Dam wall practice", "kind": "dam", "dam": "moehne", "practice": true,
		"brief": "Practice on the Möhne wall. The wall is weakened for training. Fly low over the reservoir and breach it.",
		"target": [51.4893, 8.0588], "approach": 160.0},
	{"id": "d5", "time": "night", "title": "Day 5: Operation Chastise - Möhne", "kind": "dam", "dam": "moehne",
		"brief": "Attack the Möhne dam. Fly low over the reservoir, drop the bomb against the wall and breach it. Then get home.",
		"target": [51.4893, 8.0588], "approach": 160.0},
	{"id": "d6", "time": "night", "title": "Day 6: Operation Chastise - Eder", "kind": "dam", "dam": "eder",
		"brief": "Attack the Eder dam. The same low run as at the Möhne. Breach the wall, then get home.",
		"target": [51.1833, 8.9667], "approach": 240.0},
	{"id": "d7", "time": "night", "title": "Day 7: Operation Chastise - Sorpe", "kind": "dam", "dam": "sorpe", "must_breach": false,
		"brief": "The Sorpe is a diversion. Bomb the wall so the bomb detonates close to it. The earth dam will not breach. Then get home.",
		"target": [51.3503, 7.9675], "approach": 120.0},
]


static func count() -> int:
	return DAYS.size()


static func load_progress() -> Dictionary:
	var out: Dictionary = {"passed": []}
	if not FileAccess.file_exists(SAVE_PATH):
		return out
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return out
	var d: Variant = JSON.parse_string(f.get_as_text())
	if d is Dictionary and (d as Dictionary).get("passed") is Array:
		out["passed"] = (d as Dictionary)["passed"]
	return out


static func is_passed(i: int) -> bool:
	return load_progress()["passed"].has(DAYS[i]["id"])


## Day i is open when it is the first day, or the day before it has been passed.
static func is_open(i: int) -> bool:
	return i == 0 or is_passed(i - 1)


static func record(i: int, success: bool) -> void:
	if not success:
		return
	var prog: Dictionary = load_progress()
	var passed: Array = prog["passed"]
	var id: String = str(DAYS[i]["id"])
	if not passed.has(id):
		passed.append(id)
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"passed": passed}))


## Offset a lat/lon by `dist` metres along `bearing` (deg clockwise from north). Returns [lat, lon].
static func _offset(lat: float, lon: float, dist: float, bearing: float) -> Array:
	var b: float = deg_to_rad(bearing)
	var dlat: float = dist * cos(b) / 110540.0
	var dlon: float = dist * sin(b) / (111320.0 * cos(deg_to_rad(lat)))
	return [lat + dlat, lon + dlon]


## The game-start config for day i (passed to main.start_game via the menu).
static func config_for(i: int) -> Dictionary:
	var d: Dictionary = DAYS[clampi(i, 0, DAYS.size() - 1)]
	var t: Array = d["target"]
	var approach: float = float(d.get("approach", 270.0))
	var dist: float = 2500.0 if OS.get_cmdline_user_args().has("--dam-near") else APPROACH_M   # debug: short approach for recordings
	var start: Array = _offset(float(t[0]), float(t[1]), dist, approach)
	var cfg: Dictionary = {
		"side": "Allies", "aircraft": "lancaster", "mode": "dambuster", "difficulty": 0.5,
		"weather": "clear", "time": str(d.get("time", "dusk")), "ambient": false, "wingmen": 0,
		"kind": d["kind"], "title": d["title"], "day": i,
		"spawn_lat": float(start[0]), "spawn_lon": float(start[1]),
		"spawn_heading": fmod(approach + 180.0, 360.0), "spawn_alt": START_ALT_M, "spawn_airborne": true,
	}
	if d.has("dam"):
		cfg["dam"] = d["dam"]
	if d.has("practice"):
		cfg["practice"] = d["practice"]
	if d.has("must_breach"):
		cfg["must_breach"] = d["must_breach"]
	if d.has("marker"):
		cfg["marker"] = d["marker"]
	if OS.get_cmdline_user_args().has("--dam-near"):
		cfg["spawn_alt"] = 250.0	  # debug: clear the hills on the short approach
	if d.has("rings"):
		cfg["rings"] = d["rings"]
	return cfg
