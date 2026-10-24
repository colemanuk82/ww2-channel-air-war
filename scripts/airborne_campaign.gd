class_name AirborneCampaign
extends RefCounted
## The D-Day airborne operations, flown in order in a Douglas C-47 (see AirborneMode):
##   para   drop sticks of paratroopers onto a dropping zone: low (under 1,000 ft) and slow (under 120 mph),
##          over the zone, and the men must land inside it.
##   tow    tow an assault glider to its landing zone, cast it off in reach and watch it glide in and land.
## Progress is saved in user://airborne.json. Zones and dates are from data/airborne_landings.json.
## The first operations are the British 6th Airborne Division's (Tonga, Deadstick, Mallard), then the American 101st
## and 82nd (Chicago and the drop round Sainte-Mere-Eglise).

const SAVE_PATH := "user://airborne.json"

## kind: para | tow. zone: id in data/airborne_landings.json. from: bearing (deg) from the zone to the start point.
const OPS: Array = [
	{"id": "a1", "title": "Op 1: Tonga, paratroops onto DZ N", "kind": "para", "zone": "tonga_dz_n", "glider": "",
		"time": "night", "weather": "scattered", "date": "1944-06-06", "from": 350.0, "dist": 22000.0, "alt": 150.0, "men": 18, "sticks": 2,
		"brief": "Just after midnight, 6 June 1944. The 3rd Parachute Brigade drops east of the Orne to take the batteries and bridges that guard the left flank of the invasion. Cross the coast low, find Drop Zone N north of Ranville and, over it at 1,000 ft or less and under 120 mph, hold FIRE to send out a stick of 18 men. Two sticks. Flak and machine guns are around the zone."},
	{"id": "a2", "title": "Op 2: Deadstick, Horsa to Pegasus Bridge", "kind": "tow", "zone": "deadstick_x", "glider": "horsa",
		"time": "night", "weather": "scattered", "date": "1944-06-06", "from": 345.0, "dist": 16500.0, "alt": 1400.0, "radius": 300.0,
		"brief": "Six Horsas of the Oxfordshire and Buckinghamshire Light Infantry are going for the canal and river bridges at Benouville. You tow one. Cast off at about 6,000 ft, in reach of the landing zone beside the bridge, then the glider is on its own in the dark. FIRE casts off. The HUD shows when the landing zone is in reach."},
	{"id": "a3", "title": "Op 3: Mallard, Horsa to LZ N", "kind": "tow", "zone": "tonga_lz_n", "glider": "horsa",
		"time": "dusk", "weather": "scattered", "date": "1944-06-06", "from": 350.0, "dist": 19000.0, "alt": 1000.0, "radius": 650.0,
		"brief": "The evening lift, 6 June: 250 gliders carry the rest of the 6th Airborne Division to the landing zones by the Orne. Tow a Horsa towards Landing Zone N and cast it off in reach. Light flak on the way."},
	{"id": "a4", "title": "Op 4: Utah, paratroops onto DZ O", "kind": "para", "zone": "us_dz_o", "glider": "",
		"time": "night", "weather": "overcast", "date": "1944-06-06", "from": 285.0, "dist": 26000.0, "alt": 160.0, "men": 18, "sticks": 3,
		"brief": "The 82nd Airborne comes in from the west over the Cotentin to drop round Sainte-Mere-Eglise. Cloud and flak scattered many real sticks. Fly low, keep the speed down, and put three sticks of 18 into Drop Zone O."},
	{"id": "a5", "title": "Op 5: Chicago, Waco CG-4A to LZ E", "kind": "tow", "zone": "chicago_lz_e", "glider": "waco",
		"time": "night", "weather": "overcast", "date": "1944-06-06", "from": 80.0, "dist": 15500.0, "alt": 1100.0, "radius": 700.0,
		"brief": "Operation Chicago: the 101st Airborne's glider lift of anti-tank guns and the headquarters party, towed in the small hours to Landing Zone E near Hiesville. Tow the Waco and cast it off in reach of the zone."},
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
	var passed: Array = load_progress()["passed"]
	var id: String = str(OPS[i]["id"])
	if not passed.has(id):
		passed.append(id)
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"passed": passed}))


static func zone_row(zone_id: String) -> Dictionary:
	for z in GliderKit.rows():
		if str((z as Dictionary).get("id", "")) == zone_id:
			return z
	return {}


static func config_for(i: int) -> Dictionary:
	var d: Dictionary = OPS[clampi(i, 0, OPS.size() - 1)]
	var z: Dictionary = zone_row(str(d["zone"]))
	var lat: float = float(z.get("lat", 49.24))
	var lon: float = float(z.get("lon", -0.26))
	var b: float = float(d["from"])
	var dist: float = float(d["dist"])
	var sl: float = lat + dist * cos(deg_to_rad(b)) / 110540.0
	var sn: float = lon + dist * sin(deg_to_rad(b)) / (111320.0 * cos(deg_to_rad(lat)))
	return {
		"side": "Allies", "aircraft": "c47", "mode": "airborne", "difficulty": 0.5,
		"weather": str(d["weather"]), "time": str(d["time"]), "ambient": false, "wingmen": 0,
		"op": i, "kind": str(d["kind"]), "title": str(d["title"]), "zone": str(d["zone"]), "glider": str(d["glider"]),
		"men": int(d.get("men", 18)), "sticks": int(d.get("sticks", 2)), "radius": float(d.get("radius", 500.0)),
		"era_date": str(d["date"]), "mission_date": str(d["date"]),
		"spawn_lat": sl, "spawn_lon": sn, "spawn_heading": fposmod(b + 180.0, 360.0),
		"spawn_alt": float(d["alt"]), "spawn_airborne": true,
	}
