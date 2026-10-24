class_name PowEscapeCampaign
extends RefCounted
## The POW escape operations: for each prisoner-of-war camp a pair of sorties, flown in order.
##   scout   a fast photo-reconnaissance sortie by day: photograph the camp and the field strip nearby, come home.
##   pickup  the night operation: a civil DH.89 Dragon Rapide flies in low and slow under cloud, lands on the
##           strip, takes the escapers aboard and gets away quietly (see PowEscapeMode).
## A pick-up opens once its scout has been passed; the next camp opens once the previous pick-up has been passed.
## Progress is saved in user://pow_escape.json (per player, separate from the other campaigns).
##
## These are what-if operations. Real pick-ups from occupied Europe used Westland Lysanders and Lockheed Hudsons
## of 161 Squadron; the Rapide is the civil airliner the player flies instead.

const SAVE_PATH := "user://pow_escape.json"
const APPROACH_M := 38000.0         # the sortie starts this far from the camp, on the bearing back to base
const HOME_LAT := 50.85             # RAF Tangmere: the base the sorties start from and return towards
const HOME_LON := -0.71
const SCOUT_ALT_M := 450.0
const PICKUP_ALT_M := 200.0

## kind: scout | pickup. camp: id in PowCampKit.CAMPS. strip: id in EscapeStripKit.STRIPS.
const OPS: Array = [
	{"id": "p1s", "title": "Op 1a: Scout the camp at Chalons", "kind": "scout", "camp": "frontstalag_194", "strip": "strip_chalons",
		"aircraft": "mosquito", "weather": "scattered", "time": "noon", "date": "1943-10-02",
		"brief": "Frontstalag 194 at Chalons-sur-Marne. An escape line has men out of the wire and hiding in the district, and London needs to know whether a flat field near the camp could take an aircraft. Fly in at 1,500 ft or below and photograph the camp, then the field to its east. Camera runs need a steady 2 seconds over each. Guards have machine guns: keep moving and get home."},
	{"id": "p1p", "title": "Op 1b: Pick-up at Chalons", "kind": "pickup", "camp": "frontstalag_194", "strip": "strip_chalons",
		"aircraft": "dh89", "weather": "overcast", "time": "night", "date": "1943-11-01", "prisoners": 6,
		"brief": "A civil Dragon Rapide, no guns and no armour. Cross the coast low, keep under the cloud and stay away from the towns. The reception committee will show three torches in an L on the field east of the camp when they hear you. Land, stop beside the group, load the six escapers and be off again. Fly low and slow: the louder and higher you are, the sooner the camp wakes. Then home, quietly."},
	{"id": "p2s", "title": "Op 2a: Scout the camp at Charleville", "kind": "scout", "camp": "frontstalag_190", "strip": "strip_charleville",
		"aircraft": "mosquito", "weather": "scattered", "time": "noon", "date": "1943-10-09",
		"brief": "Frontstalag 190, Charleville, on the Meuse. The same job: photograph the camp, then the field west of it that the resistance say is firm and long enough. Light flak and machine guns on the camp's towers."},
	{"id": "p2p", "title": "Op 2b: Pick-up at Charleville", "kind": "pickup", "camp": "frontstalag_190", "strip": "strip_charleville",
		"aircraft": "dh89", "weather": "overcast", "time": "night", "date": "1943-11-30", "prisoners": 7,
		"brief": "Seven men this time, and a longer run: the Ardennes hills lie across the route, so plan the climb and come down under the cloud before the camp. Land on the strip west of Charleville, load and get out."},
	{"id": "p3s", "title": "Op 3a: Scout the camp at Trier", "kind": "scout", "camp": "stalag_12d", "strip": "strip_trier",
		"aircraft": "mosquito", "weather": "scattered", "time": "noon", "date": "1943-10-16",
		"brief": "Stalag XII-D, Trier, deep inside the Reich. Photograph the camp and the field north of it. Expect more guns than at the French camps and fighters on call: fly low, out and back."},
	{"id": "p3p", "title": "Op 3b: Pick-up at Trier", "kind": "pickup", "camp": "stalag_12d", "strip": "strip_trier",
		"aircraft": "dh89", "weather": "rain", "time": "night", "date": "1943-12-28", "prisoners": 8,
		"brief": "Eight men, the Rapide's full load, from the strip north of Trier. Rain and low cloud are the best cover you will get. Searchlights will be working the valley: keep out of them. Land, load, and go."},
]


static func count() -> int:
	return OPS.size()


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
	return load_progress()["passed"].has(OPS[i]["id"])


static func is_open(i: int) -> bool:
	return i == 0 or is_passed(i - 1)


static func record(i: int, success: bool) -> void:
	if not success:
		return
	var prog: Dictionary = load_progress()
	var passed: Array = prog["passed"]
	var id: String = str(OPS[i]["id"])
	if not passed.has(id):
		passed.append(id)
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"passed": passed}))


static func camp_row(camp_id: String) -> Array:
	for c in PowCampKit.CAMPS:
		if str(c[0]) == camp_id:
			return c
	return []


## Bearing (deg clockwise from north) from a point to another, on a flat approximation (fine over 100 km).
static func bearing(lat0: float, lon0: float, lat1: float, lon1: float) -> float:
	var dn: float = (lat1 - lat0) * 110540.0
	var de: float = (lon1 - lon0) * 111320.0 * cos(deg_to_rad(lat0))
	return fposmod(rad_to_deg(atan2(de, dn)), 360.0)


static func offset(lat: float, lon: float, dist: float, bearing_deg: float) -> Array:
	var b: float = deg_to_rad(bearing_deg)
	return [lat + dist * cos(b) / 110540.0, lon + dist * sin(b) / (111320.0 * cos(deg_to_rad(lat)))]


## The darkest night within a month of `date` (lowest moon illumination): pick-ups were flown in the dark of the moon
## when the weather allowed. Returns an ISO date.
static func dark_date(date: String) -> String:
	var best: String = date
	var best_i: float = 2.0
	var j0: int = MoonWeather.jdn(date)
	for k in 30:
		var d: String = MoonWeather.date_from_jdn(j0 + k)
		var ill: float = MoonWeather.illumination(d)
		if ill < best_i:
			best_i = ill
			best = d
	return best


## The game-start config for operation i (passed to main.start_game via the menu).
static func config_for(i: int) -> Dictionary:
	var d: Dictionary = OPS[clampi(i, 0, OPS.size() - 1)]
	var row: Array = camp_row(str(d["camp"]))
	var clat: float = float(row[2])
	var clon: float = float(row[3])
	var back: float = bearing(clat, clon, HOME_LAT, HOME_LON)
	var start: Array = offset(clat, clon, APPROACH_M, back)
	var pickup: bool = str(d["kind"]) == "pickup"
	var date: String = dark_date(str(d["date"])) if pickup else str(d["date"])
	var cfg: Dictionary = {
		"side": "Allies", "aircraft": str(d["aircraft"]), "mode": "pow_escape", "difficulty": 0.5,
		"weather": str(d["weather"]), "time": str(d["time"]), "ambient": false, "wingmen": 0,
		"op": i, "kind": str(d["kind"]), "title": str(d["title"]), "camp": str(d["camp"]), "strip": str(d["strip"]),
		"prisoners": int(d.get("prisoners", 0)), "era_date": date, "mission_date": date,
		"spawn_lat": float(start[0]), "spawn_lon": float(start[1]),
		"spawn_heading": fposmod(back + 180.0, 360.0),
		"spawn_alt": (PICKUP_ALT_M if pickup else SCOUT_ALT_M), "spawn_airborne": true,
	}
	return cfg
