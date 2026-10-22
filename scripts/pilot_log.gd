class_name PilotLog
extends RefCounted
## The player's flying record, one career per air force (RAF / Luftwaffe), kept in user://pilot_log.cfg:
## points, taskings done / missed (by kind), missions flown / failed, air and ground kills, ships sunk, V-1s,
## scrambles, rescues, hours flown, the rank those earn and the decorations awarded, plus the last 40 logbook
## entries. Kills, hours and mission results are recorded by ModeBase for every mode; taskings by the Ops Room.
## Shown on the logbook overlay (key J in free flight, Logbook on the main menu).

const PATH := "user://pilot_log.cfg"

const RANKS := {
	"Allies": [[0, "Pilot Officer"], [1500, "Flying Officer"], [5000, "Flight Lieutenant"], [12000, "Squadron Leader"],
		[25000, "Wing Commander"], [45000, "Group Captain"]],
	"Axis": [[0, "Leutnant"], [1500, "Oberleutnant"], [5000, "Hauptmann"], [12000, "Major"],
		[25000, "Oberstleutnant"], [45000, "Oberst"]],
}

## [id, name, test] - test is evaluated against the career dictionary; awards are permanent once earned.
const AWARDS := {
	"Allies": [
		["mid", "Mentioned in Despatches", "done + missions >= 3 or air >= 2 or ships >= 2"],
		["dfc", "Distinguished Flying Cross", "done + missions >= 10 or air >= 5"],
		["dfc_bar", "Bar to the DFC", "done + missions >= 25 or air >= 12"],
		["dso", "Distinguished Service Order", "done + missions >= 45 or air >= 20"],
		["dso_bar", "Bar to the DSO", "done + missions >= 80 or air >= 35"],
		["asr", "Air-Sea Rescue commendation", "rescues >= 3"],
		["diver", "Anti-Diver commendation", "v1 >= 5"],
		["coastal", "Coastal Command commendation", "ships >= 5"],
		["ground", "Army Co-operation commendation", "ground >= 25"],
	],
	"Axis": [
		["ek2", "Iron Cross 2nd Class", "done + missions >= 3 or air >= 2 or ships >= 2"],
		["ek1", "Iron Cross 1st Class", "done + missions >= 10 or air >= 5"],
		["ffs", "Front Flying Clasp in Gold", "done + missions >= 25"],
		["dkg", "German Cross in Gold", "done + missions >= 45 or air >= 20"],
		["rk", "Knight's Cross of the Iron Cross", "done + missions >= 80 or air >= 40"],
		["seenot", "Sea Rescue commendation", "rescues >= 3"],
		["anti_ship", "Anti-Shipping commendation", "ships >= 5"],
		["ground", "Ground Assault Badge", "ground >= 25"],
	],
}

static var _cf: ConfigFile = null


static func _load() -> void:
	if _cf != null:
		return
	_cf = ConfigFile.new()
	_cf.load(PATH)


static func career(side: String) -> Dictionary:
	_load()
	var d: Dictionary = _cf.get_value(side, "career", {})
	for k in ["points", "done", "missed", "air", "ground", "ships", "v1", "scrambles", "rescues", "intel", "seconds", "missions", "missions_failed"]:
		if not d.has(k):
			d[k] = 0
	if not d.has("kinds"):
		d["kinds"] = {}
	if not d.has("awards"):
		d["awards"] = []
	if not d.has("unseen_awards"):
		d["unseen_awards"] = (d["awards"] as Array).duplicate()     # decorations earned before ceremonies existed
	if not d.has("entries"):
		d["entries"] = []
	return d


static func save_career(side: String, d: Dictionary) -> void:
	_load()
	_cf.set_value(side, "career", d)
	_cf.save(PATH)


static func rank_of(side: String, points: int) -> String:
	var r: String = String(RANKS[side][0][1])
	for step in RANKS[side]:
		if points >= int(step[0]):
			r = String(step[1])
	return r


static func next_rank(side: String, points: int) -> Array:
	for step in RANKS[side]:
		if points < int(step[0]):
			return step
	return []


static func _test(expr_s: String, d: Dictionary) -> bool:
	var e := Expression.new()
	var names: PackedStringArray = ["done", "missed", "air", "ground", "ships", "v1", "scrambles", "rescues", "intel", "missions"]
	if e.parse(expr_s, names) != OK:
		return false
	var vals: Array = []
	for n in names:
		vals.append(int(d.get(n, 0)))
	var r: Variant = e.execute(vals)
	return bool(r) if not e.has_execute_failed() else false


## Apply a change; returns the news it produced: {"promoted": "<new rank>" or "", "awards": [names]}.
static func record(side: String, changes: Dictionary, entry: String = "") -> Dictionary:
	var d: Dictionary = career(side)
	var before: String = rank_of(side, int(d["points"]))
	for k in changes.keys():
		if k == "kind":
			var kinds: Dictionary = d["kinds"]
			kinds[changes[k]] = int(kinds.get(changes[k], 0)) + 1
		else:
			d[k] = int(d.get(k, 0)) + int(changes[k])
	if entry != "":
		var ents: Array = d["entries"]
		ents.push_front("%s  %s" % [Time.get_date_string_from_system(), entry])
		while ents.size() > 40:
			ents.pop_back()
	var news: Dictionary = {"promoted": "", "awards": []}
	var after: String = rank_of(side, int(d["points"]))
	if after != before:
		news["promoted"] = after
	var have: Array = d["awards"]
	var unseen: Array = d.get("unseen_awards", [])
	for a in AWARDS[side]:
		if not have.has(a[0]) and _test(String(a[2]), d):
			have.append(a[0])
			unseen.append(a[0])          # presented by MedalCeremony when it is safe to stop and look
			(news["awards"] as Array).append(String(a[1]))
	d["unseen_awards"] = unseen
	save_career(side, d)
	return news


static func award_names(side: String, d: Dictionary) -> Array:
	var out: Array = []
	for a in AWARDS[side]:
		if (d["awards"] as Array).has(a[0]):
			out.append(String(a[1]))
	return out


## The logbook text for one side: rank, decorations, totals and recent entries. Used by the Ops Room (J) and the main menu.
static func logbook_text(side: String) -> String:
	var c: Dictionary = career(side)
	var pts: int = int(c["points"])
	var nx: Array = next_rank(side, pts)
	var t: String = "PILOT'S FLYING LOG BOOK  -  %s\n\n" % ("Royal Air Force" if side == "Allies" else "Luftwaffe")
	t += "%s %s     %d points%s\n" % [rank_of(side, pts), Radio.player_callsign, pts, ("   (next: %s at %d)" % [nx[1], nx[0]]) if not nx.is_empty() else ""]
	var aw: Array = award_names(side, c)
	t += "Decorations: %s\n\n" % (", ".join(aw) if not aw.is_empty() else "none yet")
	t += "Missions %d flown, %d failed     Taskings %d done, %d missed\n" % [int(c["missions"]), int(c["missions_failed"]), int(c["done"]), int(c["missed"])]
	t += "Aircraft destroyed %d     Ships sunk %d     Ground targets %d\n" % [int(c["air"]), int(c["ships"]), int(c["ground"])]
	t += "V-1s shot down %d     Scrambles %d     Rescues %d     Intelligence reports %d\n" % [int(c["v1"]), int(c["scrambles"]), int(c["rescues"]), int(c["intel"])]
	t += "Hours flown %.1f\n\nRECENT ENTRIES\n" % (float(c["seconds"]) / 3600.0)
	var ents: Array = c["entries"]
	for i in mini(ents.size(), 14):
		t += "  " + str(ents[i]) + "\n"
	t += PeriodText.section_text(side)
	return t


## True for automated / debug runs (screenshots, soak tests, forced taskings): they must not touch the real logbook.
static func debug_run() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot=") or a.begins_with("--logbook-shot=") or a.begins_with("--dam-shot=") or a.begins_with("--medal-shot=") or a.begins_with("--ops-kind=") or a.begins_with("--quit-after") or a.begins_with("--fire-test") \
				or a in ["--ops-test", "--ops-auto", "--ops-rv", "--ops-twist", "--autopilot", "--crew-test", "--plume-test"] or a.begins_with("--damage-test"):
			return true
	return false


## Record, then announce any promotion or decoration on the HUD and the radio. Returns the news.
static func record_and_announce(side: String, changes: Dictionary, entry: String, hud: Node) -> Dictionary:
	if debug_run():
		return {"promoted": "", "awards": []}
	var news: Dictionary = record(side, changes, entry)
	var sd: String = "axis" if side == "Axis" else "allies"
	var ctl: String = "Jafü 2" if side == "Axis" else "Sector Control"
	if str(news["promoted"]) != "":
		var rk: String = str(news["promoted"])
		Radio.say(ctl, "Congratulations, %s. You've been promoted to %s." % [Radio.player_callsign, rk], Radio.Kind.CONTROL, 1.5, "ops/%s/promoted_1" % sd)
		if hud != null and is_instance_valid(hud) and hud.has_method("show_message"):
			hud.call("show_message", "PROMOTED: %s" % rk.to_upper(), 6.0)
	for a in news["awards"]:
		Radio.say(ctl, "Signal from Group: you've been awarded the %s. Well done." % str(a), Radio.Kind.CONTROL, 2.5, "ops/%s/award_1" % sd)
		if hud != null and is_instance_valid(hud) and hud.has_method("show_message"):
			hud.call("show_message", "AWARDED: %s" % str(a).to_upper(), 6.0)
	return news
