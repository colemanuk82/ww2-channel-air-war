class_name MissionDoc
extends RefCounted
## Custom missions made in the Mission Editor: the file format, the catalogues the editor offers (unit kinds and types,
## trigger conditions and actions, objective kinds), validation, and save / load / listing.
##
## A mission is one JSON file: the player's own in user://missions/, the examples in res://data/custom_missions/.
## Format 1:
##   name, author, briefing, side ("Allies" | "Axis"), aircraft, time (dawn | noon | dusk | night), weather (a
##   WeatherManager preset), date ("YYYY-MM-DD" or "" for the default summer 1940), difficulty (0..1), wingmen (0..3)
##   start:      {lat, lon, airfield ("" = air start), airborne, alt (m), heading}
##   units:      [{id, name, kind, type, side, count, lat, lon, alt (m), heading, route: [[lat, lon], ...], behavior,
##                 active (spawned at the start, else by an "activate" action), skill (0..1)}]
##   zones:      [{id, name, lat, lon, radius (km)}]
##   objectives: [{id, text, kind, target, required, shown}]   kind: see OBJECTIVE_KINDS
##   triggers:   [{id, name, once, logic ("all" | "any"), delay (s), conditions: [{type, ...}], actions: [{type, ...}]}]
## A trigger fires when its conditions hold (all of them, or any one), waits `delay` seconds, then runs its actions in
## order. A "once" trigger fires a single time; otherwise it fires again each time its conditions become true again.
## CustomMissionMode (scripts/modes/custom_mission_mode.gd) plays the file.

const FORMAT: int = 1
const USER_DIR := "user://missions/"
const BUNDLED_DIR := "res://data/custom_missions/"
const SIDES := ["Allies", "Axis"]
const TIMES := ["dawn", "noon", "dusk", "night"]
const WEATHERS := ["clear", "scattered", "overcast", "rain", "storm", "fog"]

## Unit kinds. "types" is the list the editor offers (flights take the aircraft of the unit's side).
const UNIT_KINDS := {
	"flight": {"label": "Aircraft flight", "behaviors": ["patrol", "hunt", "route"], "max": 12},
	"vehicles": {"label": "Vehicles", "behaviors": ["move", "hold"], "max": 12,
		"types": ["sherman", "panzer4", "tiger", "truck", "halftrack", "jeep", "kubel", "artillery", "troops", "car", "bus"]},
	"ships": {"label": "Ships", "behaviors": ["move", "hold"], "max": 8,
		"types": ["freighter", "collier", "destroyer", "cruiser", "battleship", "trawler", "fishing_boat", "landing_craft", "ferry"]},
	"structure": {"label": "Building / target", "behaviors": ["hold"], "max": 6,
		"types": ["bunker", "pillbox", "battery", "radar_ch", "radar_wurz", "factory", "rail_yard", "oil_depot", "refinery", "v1_site", "hangar", "fuel_tank", "control_tower", "gasworks", "goods_yard", "engine_shed"]},
	"flak": {"label": "Flak guns", "behaviors": ["hold"], "max": 8, "types": ["88mm", "bofors", "mg"]},
	"world": {"label": "Real target on the map", "behaviors": ["hold"], "max": 1},
}

const BEHAVIOR_HELP := {
	"patrol": "Circle the spot and engage anything hostile that comes near.",
	"hunt": "Go after the player wherever he is.",
	"route": "Fly the route (bombers bomb their way along it in formation).",
	"move": "Follow the route, then loop round it.",
	"hold": "Stay where placed.",
}

## Objective kinds. target: a unit id (destroy / protect), a zone id (reach / land, "" = any friendly field for land),
## or a number of seconds (survive). "manual" objectives are only changed by trigger actions.
const OBJECTIVE_KINDS := {
	"destroy": {"label": "Destroy a unit", "target": "unit"},
	"protect": {"label": "Protect a unit", "target": "unit"},
	"reach": {"label": "Fly to a zone", "target": "zone"},
	"land": {"label": "Land (in a zone)", "target": "zone"},
	"survive": {"label": "Survive for a time", "target": "seconds"},
	"manual": {"label": "Set by triggers", "target": ""},
}

## Trigger conditions: type -> {label, params: [[key, kind, default], ...]}. Param kinds: float, int, bool, text,
## unit, zone, objective, trigger, and "enum:a|b|c".
const CONDITIONS := {
	"time": {"label": "Time since start (s) at least", "params": [["seconds", "float", 60.0]]},
	"unit_destroyed": {"label": "Unit destroyed (all of it)", "params": [["unit", "unit", ""]]},
	"unit_losses": {"label": "Unit has lost at least", "params": [["unit", "unit", ""], ["count", "int", 1]]},
	"unit_in_zone": {"label": "Unit is in zone", "params": [["unit", "unit", ""], ["zone", "zone", ""]]},
	"player_in_zone": {"label": "Player is in zone", "params": [["zone", "zone", ""]]},
	"player_alt_above": {"label": "Player above altitude (m)", "params": [["metres", "float", 1500.0]]},
	"player_alt_below": {"label": "Player below altitude (m)", "params": [["metres", "float", 300.0]]},
	"player_landed": {"label": "Player has landed", "params": []},
	"player_health_below": {"label": "Player damaged below (%)", "params": [["percent", "float", 50.0]]},
	"player_kills": {"label": "Player kills at least", "params": [["count", "int", 1]]},
	"objective": {"label": "Objective is", "params": [["objective", "objective", ""], ["state", "enum:complete|failed|active", "complete"]]},
	"flag": {"label": "Flag is", "params": [["flag", "text", "flag1"], ["value", "bool", true]]},
	"trigger_fired": {"label": "Another trigger has fired", "params": [["trigger", "trigger", ""]]},
	"chance": {"label": "Random chance (%)", "params": [["percent", "float", 50.0]]},
}

const ACTIONS := {
	"message": {"label": "Show a message", "params": [["text", "text", "Message"], ["seconds", "float", 5.0]]},
	"radio": {"label": "Radio call", "params": [["speaker", "text", "Sector Control"], ["text", "text", "Bandits approaching."], ["from", "enum:control|friendly", "control"]]},
	"activate": {"label": "Bring in a unit", "params": [["unit", "unit", ""]]},
	"objective": {"label": "Set an objective", "params": [["objective", "objective", ""], ["state", "enum:active|complete|failed", "active"]]},
	"flag": {"label": "Set a flag", "params": [["flag", "text", "flag1"], ["value", "bool", true]]},
	"hunt": {"label": "Unit attacks the player", "params": [["unit", "unit", ""]]},
	"destroy": {"label": "Destroy a unit", "params": [["unit", "unit", ""]]},
	"nav": {"label": "Point the compass at", "params": [["zone", "zone", ""]]},
	"score": {"label": "Add score", "params": [["points", "int", 100]]},
	"end": {"label": "End the mission", "params": [["result", "enum:success|failure", "success"], ["text", "text", "Mission complete"]]},
}


# ================================================================== new / defaults
static func new_doc(side: String = "Allies") -> Dictionary:
	return {
		"format": FORMAT, "name": "New mission", "author": "", "briefing": "",
		"side": side, "aircraft": AircraftCatalog.default_fighter(side), "time": "noon", "weather": "clear", "date": "",
		"difficulty": 0.5, "wingmen": 2,
		"start": {"lat": 51.115, "lon": 1.149, "airfield": "hawkinge" if side == "Allies" else "", "airborne": true, "alt": 1500.0, "heading": 135.0},
		"units": [], "zones": [], "objectives": [], "triggers": [],
	}


static func next_id(list: Array, prefix: String) -> String:
	var used: Dictionary = {}
	for e in list:
		used[str((e as Dictionary).get("id", ""))] = true
	var i: int = 1
	while used.has("%s%d" % [prefix, i]):
		i += 1
	return "%s%d" % [prefix, i]


static func new_unit(doc: Dictionary, kind: String, lat: float, lon: float) -> Dictionary:
	var enemy: String = AircraftCatalog.opposite(str(doc.get("side", "Allies")))
	var types: Array = unit_types(kind, enemy)
	var u: Dictionary = {
		"id": next_id(doc.get("units", []), {"flight": "flight", "vehicles": "column", "ships": "ships", "structure": "target", "flak": "flak", "world": "real"}.get(kind, "unit")),
		"name": "", "kind": kind, "type": str(types[0]) if not types.is_empty() else "", "side": enemy,
		"count": {"flight": 4, "vehicles": 5, "ships": 3, "structure": 1, "flak": 3, "world": 1}.get(kind, 1),
		"lat": lat, "lon": lon, "alt": 2500.0 if kind == "flight" else 0.0, "heading": 0.0,
		"route": [], "behavior": (UNIT_KINDS[kind]["behaviors"] as Array)[0], "active": true, "skill": float(doc.get("difficulty", 0.5)),
	}
	u["name"] = str(u["id"]).capitalize()
	return u


## Types the editor offers for a unit of `kind` on `side` (aircraft are per side; real targets come from locations.json).
static func unit_types(kind: String, side: String) -> Array:
	if kind == "flight":
		return AircraftCatalog.ids_for_side(side)
	if kind == "world":
		var out: Array = []
		for t in world_targets():
			out.append(str(t["id"]))
		return out
	return (UNIT_KINDS.get(kind, {}) as Dictionary).get("types", [])


static var _targets: Array = []
static var _airfields: Array = []


## Real targets (factories, ports, radar, batteries...) from data/locations.json: [{id, name, type, lat, lon, side_owner}].
static func world_targets() -> Array:
	_load_locations()
	return _targets


static func airfields() -> Array:
	_load_locations()
	return _airfields


static func _load_locations() -> void:
	if not _targets.is_empty():
		return
	var f: FileAccess = FileAccess.open("res://data/locations.json", FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return
	for t in (d as Dictionary).get("targets", []):
		if bool(t.get("in_bounds", true)) and str(t.get("type", "")) != "convoy_route":
			_targets.append(t)
	for a in (d as Dictionary).get("airfields", []):
		if bool(a.get("in_bounds", true)):
			_airfields.append(a)


static func world_target(id: String) -> Dictionary:
	for t in world_targets():
		if str(t["id"]) == id:
			return t
	return {}


static func airfield(id: String) -> Dictionary:
	for a in airfields():
		if str(a["id"]) == id:
			return a
	return {}


## Default values for a condition / action of `type` (from the catalogue): {"type": type, key: default, ...}.
static func new_step(catalogue: Dictionary, type: String) -> Dictionary:
	var d: Dictionary = {"type": type}
	for p in (catalogue.get(type, {}) as Dictionary).get("params", []):
		d[str(p[0])] = p[2]
	return d


static func find(list: Array, id: String) -> Dictionary:
	for e in list:
		if str((e as Dictionary).get("id", "")) == id:
			return e
	return {}


## Plain-English one-liner of a condition or action, for the trigger lists.
static func describe(catalogue: Dictionary, step: Dictionary) -> String:
	var spec: Dictionary = catalogue.get(str(step.get("type", "")), {})
	var parts: Array = []
	for p in spec.get("params", []):
		var v: Variant = step.get(str(p[0]), p[2])
		if v is float:
			parts.append(str(snappedf(float(v), 0.1)))
		else:
			parts.append(str(v))
	var lbl: String = str(spec.get("label", step.get("type", "?")))
	return lbl if parts.is_empty() else "%s: %s" % [lbl, ", ".join(parts)]


# ================================================================== validation
## Problems that stop the mission from being flown (errors) and ones worth knowing about (warnings).
static func validate(doc: Dictionary) -> Dictionary:
	var errors: PackedStringArray = []
	var warnings: PackedStringArray = []
	if str(doc.get("name", "")).strip_edges() == "":
		errors.append("The mission has no name.")
	var side: String = str(doc.get("side", ""))
	if not SIDES.has(side):
		errors.append("Pick a side (Allies or Axis).")
	elif not AircraftCatalog.ids_for_side(side).has(str(doc.get("aircraft", ""))):
		errors.append("The player's aircraft does not belong to the %s." % side)
	var st: Dictionary = doc.get("start", {})
	if not st.has("lat") or not st.has("lon"):
		errors.append("Set the player's start on the map.")
	var af_id: String = str(st.get("airfield", ""))
	if af_id != "" and airfield(af_id).is_empty():
		errors.append("The start airfield '%s' does not exist." % af_id)
	var ids: Dictionary = {}
	for group in ["units", "zones", "objectives", "triggers"]:
		for e in doc.get(group, []):
			var eid: String = str(e.get("id", ""))
			if eid == "":
				errors.append("Something in %s has no id." % group)
			elif ids.has(eid):
				errors.append("The id '%s' is used twice." % eid)
			ids[eid] = group
	for u in doc.get("units", []):
		var kind: String = str(u.get("kind", ""))
		if not UNIT_KINDS.has(kind):
			errors.append("Unit %s has an unknown kind '%s'." % [u.get("id", "?"), kind])
			continue
		if not unit_types(kind, str(u.get("side", "Axis"))).has(str(u.get("type", ""))):
			errors.append("Unit %s: '%s' is not a %s of the %s." % [u.get("id", "?"), u.get("type", ""), str(UNIT_KINDS[kind]["label"]).to_lower(), u.get("side", "?")])
		if str(u.get("behavior", "")) in ["route", "move"] and (u.get("route", []) as Array).is_empty():
			warnings.append("Unit %s is set to follow a route but has none: it will stay where it is." % u.get("id", "?"))
	var units: Array = doc.get("units", [])
	var zones: Array = doc.get("zones", [])
	var objs: Array = doc.get("objectives", [])
	var trigs: Array = doc.get("triggers", [])
	for o in objs:
		var ok: String = str(o.get("kind", "manual"))
		var tgt: String = str(o.get("target", ""))
		if ok in ["destroy", "protect"] and find(units, tgt).is_empty():
			errors.append("Objective '%s' needs a unit." % o.get("text", o.get("id", "?")))
		if ok == "reach" and find(zones, tgt).is_empty():
			errors.append("Objective '%s' needs a zone." % o.get("text", o.get("id", "?")))
		if ok == "land" and tgt != "" and find(zones, tgt).is_empty():
			errors.append("Objective '%s': zone '%s' does not exist." % [o.get("text", "?"), tgt])
	for t in trigs:
		for group in ["conditions", "actions"]:
			var cat: Dictionary = CONDITIONS if group == "conditions" else ACTIONS
			for step in t.get(group, []):
				var spec: Dictionary = cat.get(str(step.get("type", "")), {})
				if spec.is_empty():
					errors.append("Trigger '%s' has an unknown %s '%s'." % [t.get("name", t.get("id", "?")), group.trim_suffix("s"), step.get("type", "")])
					continue
				for p in spec.get("params", []):
					var v: String = str(step.get(str(p[0]), ""))
					var bad: bool = false
					match str(p[1]):
						"unit":
							bad = find(units, v).is_empty()
						"zone":
							bad = find(zones, v).is_empty()
						"objective":
							bad = find(objs, v).is_empty()
						"trigger":
							bad = find(trigs, v).is_empty()
					if bad:
						errors.append("Trigger '%s': pick a %s for '%s'." % [t.get("name", t.get("id", "?")), p[1], str(spec["label"]).to_lower()])
	var ends: bool = false
	for o in objs:
		if bool(o.get("required", true)):
			ends = true
	for t in trigs:
		for a in t.get("actions", []):
			if str(a.get("type", "")) == "end":
				ends = true
	if not ends:
		warnings.append("Nothing ends this mission: add a required objective or an 'End the mission' action.")
	return {"errors": errors, "warnings": warnings}


# ================================================================== files
static func slug(text: String) -> String:
	var s: String = text.strip_edges().to_lower()
	var out: String = ""
	for i in s.length():
		var c: String = s[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif not out.ends_with("_"):
			out += "_"
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out if out != "" else "mission"


static func load_file(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return {}
	return upgrade(d)


## Fill in anything an older or hand-written file leaves out, so the editor and the mode can rely on every key.
static func upgrade(d: Dictionary) -> Dictionary:
	var base: Dictionary = new_doc(str(d.get("side", "Allies")))
	for k in base.keys():
		if not d.has(k):
			d[k] = base[k]
	for k2 in (base["start"] as Dictionary).keys():
		if not (d["start"] as Dictionary).has(k2):
			d["start"][k2] = base["start"][k2]
	for u in d["units"]:
		var nu: Dictionary = new_unit(d, str(u.get("kind", "flight")) if UNIT_KINDS.has(str(u.get("kind", ""))) else "flight", float(u.get("lat", 51.0)), float(u.get("lon", 1.0)))
		for k3 in nu.keys():
			if not (u as Dictionary).has(k3):
				u[k3] = nu[k3]
	for o in d["objectives"]:
		for k4 in [["text", "Objective"], ["kind", "manual"], ["target", ""], ["required", true], ["shown", true]]:
			if not (o as Dictionary).has(k4[0]):
				o[k4[0]] = k4[1]
	for t in d["triggers"]:
		for k5 in [["name", str(t.get("id", "Trigger"))], ["once", true], ["logic", "all"], ["delay", 0.0], ["conditions", []], ["actions", []]]:
			if not (t as Dictionary).has(k5[0]):
				t[k5[0]] = k5[1]
	d["format"] = FORMAT
	return d


## Save to `path`, or to a new file in user://missions/ named after the mission. Returns the path written ("" on error).
static func save(doc: Dictionary, path: String = "") -> String:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	if path == "" or not path.begins_with(USER_DIR):
		var base: String = USER_DIR + slug(str(doc.get("name", "mission")))
		path = base + ".json"
		var n: int = 2
		while FileAccess.file_exists(path):
			path = "%s_%d.json" % [base, n]
			n += 1
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(doc, "\t"))
	return path


static func delete(path: String) -> bool:
	return path.begins_with(USER_DIR) and DirAccess.remove_absolute(path) == OK


## Every mission the player can fly: their own first (newest first), then the examples. [{path, name, bundled, doc}]
static func list_all() -> Array:
	var mine: Array = []
	for p in _json_in(USER_DIR):
		var d: Dictionary = load_file(p)
		if not d.is_empty():
			mine.append({"path": p, "name": str(d.get("name", p.get_file())), "bundled": false, "doc": d, "t": FileAccess.get_modified_time(p)})
	mine.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["t"]) > int(b["t"]))
	var out: Array = mine
	for p2 in _json_in(BUNDLED_DIR):
		var d2: Dictionary = load_file(p2)
		if not d2.is_empty():
			out.append({"path": p2, "name": str(d2.get("name", p2.get_file())), "bundled": true, "doc": d2, "t": 0})
	return out


static func _json_in(dir: String) -> Array:
	var out: Array = []
	var da: DirAccess = DirAccess.open(dir)
	if da == null:
		return out
	for fn in da.get_files():
		var f2: String = fn.trim_suffix(".remap")
		if f2.ends_with(".json"):
			out.append(dir + f2)
	out.sort()
	return out


## The start_game() config that flies `doc` (the mode reads the whole document from "custom_doc").
static func start_config(doc: Dictionary, path: String = "", from_editor: bool = false) -> Dictionary:
	var st: Dictionary = doc.get("start", {})
	var af_id: String = str(st.get("airfield", ""))
	var cfg: Dictionary = {
		"mode": "custom", "side": str(doc.get("side", "Allies")), "aircraft": str(doc.get("aircraft", "")),
		"difficulty": float(doc.get("difficulty", 0.5)), "weather": str(doc.get("weather", "clear")),
		"time": str(doc.get("time", "noon")), "wingmen": int(doc.get("wingmen", 0)),
		"spawn_lat": float(st.get("lat", 51.1)), "spawn_lon": float(st.get("lon", 1.2)), "spawn_airfield": af_id,
		"spawn_airborne": bool(st.get("airborne", true)) or af_id == "", "spawn_alt": float(st.get("alt", 1500.0)),
		"spawn_heading": float(st.get("heading", 90.0)),
		"custom_doc": doc.duplicate(true), "custom_path": path,
	}
	if str(doc.get("date", "")) != "":
		cfg["era_date"] = str(doc["date"])
		cfg["mission_date"] = str(doc["date"])
	if from_editor:
		cfg["editor_return"] = true
	return cfg
