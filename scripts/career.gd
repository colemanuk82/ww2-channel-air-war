class_name Career
extends RefCounted
## Pilot's Life: one pilot, one side, one chapter at a time. State lives in user://career.json; the story and the
## missions come from data/career.json. Story steps advance when shown; a mission step advances when it is flown.
## A sortie is an ordinary mode configured with cfg "career": true; main.gd reports the fate (safe, sea, captured,
## crashed) and record_result() applies it.

const SAVE_PATH := "user://career.json"
const DATA_PATH := "res://data/career.json"
const RANKS := {
	"Allies": ["Pilot Officer", "Flying Officer", "Flight Lieutenant", "Squadron Leader"],
	"Axis": ["Leutnant", "Oberleutnant", "Hauptmann", "Major"],
}
const RANK_AT_SORTIES := [0, 4, 9, 16]      # sorties needed for each rank
const SQUADRON := {"Allies": "No. 921 Squadron", "Axis": "I./JG 901"}   # invented units
const HOME := {"Allies": ["biggin_hill", "manston", "hornchurch"], "Axis": ["calais_marck", "abbeville_drucat"]}
const MATES := {
	"Allies": ["Tom Ashby", "Ginger Mallory", "Dickie Hale", "Bunny Wren", "Sandy Croft"],
	"Axis": ["Rudi Falkner", "Paul Adler", "Fritz Hagen", "Egon Rapp", "Kurt Lenz"],
}
const START_DAY_NAME := "10 July 1940"
const MONTH_NAMES := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

static var state: Dictionary = {}
static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_data = parsed
	return _data


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func load_state() -> bool:
	if not has_save():
		return false
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		state = parsed
	return not state.is_empty()


static func save_state() -> void:
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(state, "\t"))


static func delete_save() -> void:
	state = {}
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## A new pilot. `aircraft` is one of the fighters for the side; `ironman` = one life, no evacuation.
static func new_pilot(pilot_name: String, side: String, aircraft: String, ironman: bool) -> void:
	var mates: Array = MATES[side].duplicate()
	mates.shuffle()
	state = {
		"name": pilot_name.strip_edges() if pilot_name.strip_edges() != "" else "Pilot",
		"side": side, "aircraft": aircraft, "ironman": ironman,
		"squadron": SQUADRON[side], "home": HOME[side][0], "chapter": 0, "step": 0,
		"day": 0, "sorties": 0, "kills": 0, "fatigue": 0, "status": "active", "rest_until": 0,
		"ended": "", "mates": mates.slice(0, 2), "lost_mates": [], "pending": [],
		"log": ["Posted to %s on %s." % [SQUADRON[side], START_DAY_NAME]],
	}
	save_state()


static func rank_index() -> int:
	var n: int = int(state.get("sorties", 0))
	var r: int = 0
	for i in RANK_AT_SORTIES.size():
		if n >= RANK_AT_SORTIES[i]:
			r = i
	return mini(r, RANKS[state["side"]].size() - 1)


static func rank_name() -> String:
	return str(RANKS[state["side"]][rank_index()])


## "14 July 1940" from the day offset since START_DAY_NAME (real calendar, so it runs on through 1945).
static func date_text(day: int = -1) -> String:
	var d: int = int(state.get("day", 0)) if day < 0 else day
	var base: int = Time.get_unix_time_from_datetime_dict({"year": 1940, "month": 7, "day": 10, "hour": 12, "minute": 0, "second": 0})
	var dd: Dictionary = Time.get_date_dict_from_unix_time(base + d * 86400)
	return "%d %s %d" % [int(dd["day"]), MONTH_NAMES[int(dd["month"]) - 1], int(dd["year"])]


## Day offset (from START_DAY_NAME) of an ISO date like "1941-01-01".
static func _day_of(iso: String) -> int:
	var parts: PackedStringArray = iso.split("-")
	if parts.size() < 3:
		return 0
	var base: int = Time.get_unix_time_from_datetime_dict({"year": 1940, "month": 7, "day": 10, "hour": 12, "minute": 0, "second": 0})
	var u: int = Time.get_unix_time_from_datetime_dict({"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]), "hour": 12, "minute": 0, "second": 0})
	return int(round(float(u - base) / 86400.0))


static func chapter() -> Dictionary:
	var chs: Array = data().get("chapters", [])
	var idx: int = int(state.get("chapter", 0))
	return chs[idx] if idx < chs.size() else {}


static func steps() -> Array:
	return chapter().get(str(state.get("side", "Allies")), [])


## What the menu should do next: {"kind": "story" | "mission" | "done", ...}. Empty when the career is over.
static func next_action() -> Dictionary:
	if is_ended():
		return {"kind": "ended"}
	var list: Array = steps()
	var i: int = int(state.get("step", 0))
	if i >= list.size():
		return {"kind": "done"}
	var st: Dictionary = list[i]
	return {"kind": str(st.get("kind", "story")), "step": st, "index": i}


static func is_ended() -> bool:
	return str(state.get("ended", "")) != ""


## Pages with the pilot's name, rank, squadron and mates filled in.
static func fill(pages: Array) -> Array:
	var out: Array = []
	var rep: Dictionary = {
		"{name}": str(state.get("name", "")), "{rank}": rank_name(), "{squadron}": str(state.get("squadron", "")),
		"{mate1}": str(state.get("mates", ["", ""])[0]) if state.get("mates", []).size() > 0 else "",
		"{mate2}": str(state.get("mates", ["", ""])[1]) if state.get("mates", []).size() > 1 else "",
	}
	for p in pages:
		var q: Dictionary = (p as Dictionary).duplicate()
		for k in ["title", "text"]:
			var s: String = str(q.get(k, ""))
			for key in rep.keys():
				s = s.replace(key, str(rep[key]))
			q[k] = s
		out.append(q)
	return out


## A story step has been shown: move past it.
static func advance_story() -> void:
	state["step"] = int(state.get("step", 0)) + 1
	_next_chapter_if_done()
	save_state()


static func _next_chapter_if_done() -> void:
	if int(state.get("step", 0)) >= steps().size() and not steps().is_empty():
		state["chapter"] = int(state.get("chapter", 0)) + 1
		state["step"] = 0
		if int(state["chapter"]) >= (data().get("chapters", []) as Array).size() and not is_ended():
			state["ended"] = "THE WAR IS OVER"
			state["status"] = "survived"
		else:
			# the calendar jumps to the start of the next chapter (it never goes backwards)
			var sd: String = str(chapter().get("start", ""))
			if sd != "":
				state["day"] = maxi(int(state.get("day", 0)), _day_of(sd))


## Flight configuration for the current mission step. Mirrors Campaign.offer_config so the usual pipeline runs.
static func mission_config(step: Dictionary) -> Dictionary:
	var side: String = str(state["side"])
	var home: Dictionary = Campaign._airfield(str(state["home"]))
	var cfg: Dictionary = {
		"side": side, "aircraft": str(state["aircraft"]), "mode": str(step.get("mode", "free")),
		"difficulty": float(step.get("difficulty", 0.4)), "weather": str(step.get("weather", "clear")),
		"time": str(step.get("time", "dawn")), "ambient": false, "campaign": false, "career": true,
		"career_step": int(state.get("step", 0)), "era_date": "1940-07-10",
		"spawn_lat": float(home.get("lat", 51.3)), "spawn_lon": float(home.get("lon", 0.0)),
		"spawn_airfield": str(state["home"]), "spawn_airborne": false,
		"spawn_heading": float(home.get("heading_deg", 90.0)), "spawn_alt": 1200.0,
	}
	if step.has("mission"):
		cfg["mission"] = str(step["mission"])
	cfg["wingmen"] = 2 if not AircraftCatalog.is_bomber(str(state["aircraft"])) and str(cfg["mode"]) != "dogfight" else 0
	return cfg


## Aircraft the pilot may choose for the side (fighters only in this chapter).
static func fighters_for(side: String) -> Array:
	var out: Array = []
	for id in AircraftCatalog.ids_for_side(side):
		if not AircraftCatalog.is_bomber(str(id)):
			out.append(id)
	return out


## A sortie is over. `stats["fate"]` says what happened to the pilot: "safe", "sea", "captured", "crashed" or
## "returned" (no bail-out). Applies the consequences, queues the after-mission pages and returns a summary.
static func record_result(success: bool, stats: Dictionary, cfg: Dictionary) -> Dictionary:
	if state.is_empty() or not bool(cfg.get("career", false)):
		return {}
	var step_i: int = int(cfg.get("career_step", int(state.get("step", 0))))
	var list: Array = steps()
	var step: Dictionary = list[clampi(step_i, 0, maxi(list.size() - 1, 0))] if not list.is_empty() else {}
	var fate: String = str(stats.get("fate", "returned"))
	var kills: int = int(stats.get("kills", 0)) + int(stats.get("fighters_down", 0)) + int(stats.get("bombers_down", 0))
	state["sorties"] = int(state.get("sorties", 0)) + 1
	state["kills"] = int(state.get("kills", 0)) + kills
	state["fatigue"] = mini(int(state.get("fatigue", 0)) + 2, 10)
	var rest_days: int = 0
	var status: String = "active"
	var ironman: bool = bool(state.get("ironman", false))
	match fate:
		"sea":
			rest_days = 3
		"captured":
			if ironman:
				status = "pow"
			else:
				rest_days = 14
		"crashed":
			if ironman:
				status = "killed"
			else:
				rest_days = 21
	if int(state.get("fatigue", 0)) >= 8 and rest_days == 0:
		rest_days = 2      # stood down for flying fatigue
	var lost_mate: String = ""
	if fate in ["captured", "crashed"] and not state.get("mates", []).is_empty():
		lost_mate = str(state["mates"][0])
		state["mates"] = (state["mates"] as Array).slice(1)
		(state["lost_mates"] as Array).append(lost_mate)
	state["day"] = int(state.get("day", 0)) + 1 + rest_days
	if rest_days > 0:
		state["fatigue"] = 0
	state["rest_until"] = int(state["day"])
	if status != "active":
		state["status"] = status
		state["ended"] = "KILLED IN ACTION" if status == "killed" else "PRISONER OF WAR"
	else:
		state["status"] = "rest" if rest_days > 0 else "active"
	# the mission step is done once flown
	if not list.is_empty():
		state["step"] = int(state.get("step", 0)) + 1
		_next_chapter_if_done()
	var pages: Array = []
	pages.append_array(step.get("after", []))
	pages.append_array(_fate_pages(fate, ironman, rest_days, lost_mate))
	state["pending"] = fill(pages)
	var line: String = "%s - %s. %d kill%s. %s" % [date_text(), _fate_word(fate), kills, "" if kills == 1 else "s",
		("Back to flying in %d days." % rest_days) if rest_days > 0 and status == "rest" else ""]
	(state["log"] as Array).append(line.strip_edges())
	save_state()
	return {"fate": fate, "status": str(state["status"]), "ended": str(state["ended"]), "rest_days": rest_days,
		"lost_mate": lost_mate}


static func _fate_word(fate: String) -> String:
	match fate:
		"safe": return "Bailed out over friendly ground and walked home"
		"sea": return "Picked up from the Channel"
		"captured": return "Down behind enemy lines"
		"crashed": return "Crashed"
	return "Returned to base"


static func _fate_pages(fate: String, ironman: bool, rest_days: int, lost_mate: String) -> Array:
	var out: Array = []
	match fate:
		"sea":
			out.append({"kind": "telegram", "title": "Rescue", "text": "{name} PICKED UP FROM THE CHANNEL. ALIVE. REST FOR %d DAYS." % rest_days})
		"captured":
			if ironman:
				out.append({"kind": "letter", "title": "Red Cross notice", "text": "{rank} {name} is reported prisoner of war. His personal effects are held at the camp. The squadron sends its regrets."})
			else:
				out.append({"kind": "text", "title": "Evaded", "text": "You spent %d days behind the lines before a route home opened. Nobody at the squadron expected to see you again." % rest_days})
		"crashed":
			if ironman:
				out.append({"kind": "letter", "title": "Telegram home", "text": "The Air Ministry regrets to inform you that {name} was killed on operations."})
			else:
				var txt: String = "Weeks in a bed at the station hospital. The doctors say you were lucky."
				if lost_mate != "":
					txt += " %s did not make it." % lost_mate
				out.append({"kind": "text", "title": "Hospital", "text": txt})
	return out
