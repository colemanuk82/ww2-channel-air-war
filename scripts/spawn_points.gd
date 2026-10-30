class_name SpawnPoints
extends RefCounted
## Free-flight spawn picker entries. Airfields come from data/locations.json (all in-bounds fields for the
## chosen side), followed by the airborne sightseeing spots below. Each entry: id, name, and either
## "airfield" (id in locations.json) or lat / lon / heading (deg) / alt (m above the ground).

const LIST := [
	{"id": "dover", "name": "Dover cliffs", "lat": 51.13, "lon": 1.36, "heading": 90.0, "alt": 700.0},
	{"id": "dunkirk", "name": "Dunkirk beaches", "lat": 51.05, "lon": 2.37, "heading": 270.0, "alt": 600.0},
	{"id": "calais", "name": "Calais coast", "lat": 50.96, "lon": 1.82, "heading": 0.0, "alt": 700.0},
	{"id": "channel", "name": "Mid-Channel", "lat": 50.6, "lon": 1.0, "heading": 0.0, "alt": 1500.0},
	{"id": "beachy", "name": "Beachy Head", "lat": 50.73, "lon": 0.25, "heading": 180.0, "alt": 800.0},
	{"id": "dieppe", "name": "Dieppe", "lat": 49.93, "lon": 1.08, "heading": 0.0, "alt": 800.0},
	{"id": "lehavre", "name": "Le Havre", "lat": 49.49, "lon": 0.11, "heading": 0.0, "alt": 900.0},
	{"id": "omaha", "name": "Normandy beaches", "lat": 49.37, "lon": -0.87, "heading": 0.0, "alt": 600.0},
	{"id": "cherbourg", "name": "Cherbourg", "lat": 49.65, "lon": -1.62, "heading": 0.0, "alt": 900.0},
	{"id": "london", "name": "London", "lat": 51.5, "lon": -0.1, "heading": 90.0, "alt": 1200.0},
]

static var _locations: Dictionary = {}
static var _loaded: bool = false


static func _load_locations() -> Dictionary:
	if _loaded:
		return _locations
	_loaded = true
	var f: FileAccess = FileAccess.open("res://data/locations.json", FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if d is Dictionary:
		_locations = d
	return _locations


## The player's side is shown in the label, e.g. "RAF Hurn (Allies)" or "Calais-Marck (Axis)".
static func label_for(name: String, side: String) -> String:
	var n: String = name.strip_edges()
	var p: int = n.find("(")
	if p > 0:
		n = n.substr(0, p).strip_edges()      # drop the town qualifier already in the data: "RAF Hurn (Bournemouth)"
	if side == "Allies" and not n.to_upper().begins_with("RAF"):
		n = "RAF " + n
	return "%s (%s)" % [n, side]


static func list_for_side(side: String) -> Array:
	var out: Array = []
	var d: Dictionary = _load_locations()
	if d.has("airfields"):
		for a in (d["airfields"] as Array):
			var ad: Dictionary = a
			if not bool(ad.get("in_bounds", true)):
				continue
			var af_side: String = "Allies" if str(ad.get("side", "")) == "RAF" else "Axis"
			if af_side != side:
				continue
			var id: String = str(ad.get("id", ""))
			if id == "":
				continue
			out.append({"id": "af:" + id, "name": label_for(str(ad.get("name", id)), af_side), "airfield": id,
				"lat": float(ad.get("lat", 0.0)), "lon": float(ad.get("lon", 0.0)), "heading": float(ad.get("heading_deg", 0.0))})
		out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x["name"]) < str(y["name"]))
	for e in LIST:
		out.append(e)
	return out


static func names() -> Array:
	var out: Array = []
	for e in LIST:
		out.append(String(e["name"]))
	return out


static func find(id: String) -> Dictionary:
	for e in LIST:
		if String(e["id"]) == id:
			return e
	var d: Dictionary = _load_locations()
	if d.has("airfields"):
		for a in (d["airfields"] as Array):
			var ad: Dictionary = a
			var af_id: String = str(ad.get("id", ""))
			if af_id != "" and id == "af:" + af_id:
				var af_side: String = "Allies" if str(ad.get("side", "")) == "RAF" else "Axis"
				return {"id": id, "name": label_for(str(ad.get("name", af_id)), af_side), "airfield": af_id,
					"lat": float(ad.get("lat", 0.0)), "lon": float(ad.get("lon", 0.0)), "heading": float(ad.get("heading_deg", 0.0))}
	return {}
