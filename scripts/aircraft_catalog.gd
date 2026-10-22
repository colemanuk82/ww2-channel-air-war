class_name AircraftCatalog
extends RefCounted
## Lookup of aircraft ids per side + helpers for loading AircraftStats.

const ALLIED_FIGHTERS := ["spitfire", "spitfire_mkix", "spitfire_mkxiv", "hurricane", "defiant", "typhoon", "tempest", "mosquito", "p51", "p47", "p38"]
const ALLIED_BOMBERS := ["lancaster", "b26", "blenheim", "b25", "a20", "c47"]
const AXIS_FIGHTERS := ["bf109", "bf109f", "bf109g", "bf110", "fw190", "me262"]
const AXIS_BOMBERS := ["ju87", "he111", "ju88", "do17", "ju52", "fw200"]
const BOMBER_IDS := ["lancaster", "b26", "blenheim", "b25", "a20", "c47", "ju87", "he111", "ju88", "do17", "ju52", "fw200"]


static func ids_for_side(side: String) -> Array:
	if side == "Axis":
		return AXIS_FIGHTERS + AXIS_BOMBERS
	return ALLIED_FIGHTERS + ALLIED_BOMBERS


static func fighters_for_side(side: String) -> Array:
	return AXIS_FIGHTERS if side == "Axis" else ALLIED_FIGHTERS


static func bombers_for_side(side: String) -> Array:
	return AXIS_BOMBERS if side == "Axis" else ALLIED_BOMBERS


static func default_fighter(side: String) -> String:
	return "bf109" if side == "Axis" else "spitfire"


static func opposite(side: String) -> String:
	return "Allies" if side == "Axis" else "Axis"


static func is_bomber(id: String) -> bool:
	return BOMBER_IDS.has(id)


static func load_stats(id: String) -> AircraftStats:
	var path: String = "res://data/aircraft/%s.tres" % id
	if ResourceLoader.exists(path):
		return load(path) as AircraftStats
	push_warning("AircraftCatalog: no stats for '%s'" % id)
	return load("res://data/aircraft/spitfire.tres") as AircraftStats


static func display_name(id: String) -> String:
	return load_stats(id).display_name
