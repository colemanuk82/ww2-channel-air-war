class_name SpawnPoints
extends RefCounted
## Free-flight spawn picker entries: the four airfields (start on the runway, or airborne over it if "start airborne" is
## on) plus airborne spots around the map. Each: id, name, and either "airfield" (id in Main.AIRFIELDS) or
## lat / lon / heading (deg) / alt (m above the ground).

const LIST := [
	{"id": "af:manston", "name": "RAF Manston (runway)", "airfield": "manston"},
	{"id": "af:hawkinge", "name": "RAF Hawkinge (runway)", "airfield": "hawkinge"},
	{"id": "af:marck", "name": "Calais-Marck (runway)", "airfield": "marck"},
	{"id": "af:st_omer", "name": "Saint-Omer (runway)", "airfield": "st_omer"},
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


static func names() -> Array:
	var out: Array = []
	for e in LIST:
		out.append(String(e["name"]))
	return out


static func find(id: String) -> Dictionary:
	for e in LIST:
		if String(e["id"]) == id:
			return e
	return {}
