class_name DatedOps
extends RefCounted
## Dated operations: some missions open on a real calendar date, the anniversary of the event they recreate
## (the Blitz night, the start of the V-1 campaign). The first time the game runs on or after that date it
## records the operation as open in user://dated_ops.cfg, and it stays open from then on.
## WW2_TODAY=YYYY-MM-DD overrides today's date (for testing).

const PATH := "user://dated_ops.cfg"

## mission id -> the anniversary (month, day) and the label shown in the mission list.
const OPS := {
	"blitz_black_saturday": {"month": 9, "day": 7, "label": "Black Saturday, 7 Sep 1940"},
	"bmb_london_docks_night": {"month": 9, "day": 7, "label": "London docks by night, 7 Sep 1940"},
	"v1_sites": {"month": 6, "day": 13, "label": "V-1 campaign opens, 13 Jun 1944"},
}


static func is_dated(id: String) -> bool:
	return OPS.has(id)


static func opens_text(id: String) -> String:
	return str(OPS[id]["label"]) if OPS.has(id) else ""


static func today() -> Dictionary:
	var env: String = OS.get_environment("WW2_TODAY")
	var parts: PackedStringArray = env.split("-")
	if parts.size() == 3 and env.length() == 10:
		return {"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2])}
	return Time.get_date_dict_from_system()


## True when the operation is open: its anniversary has been reached at any point (recorded in user://dated_ops.cfg).
static func is_open(id: String) -> bool:
	if not OPS.has(id):
		return true
	var cf := ConfigFile.new()
	cf.load(PATH)
	if bool(cf.get_value("opened", id, false)):
		return true
	var op: Dictionary = OPS[id]
	var t: Dictionary = today()
	if int(t["month"]) * 100 + int(t["day"]) >= int(op["month"]) * 100 + int(op["day"]):
		cf.set_value("opened", id, true)
		cf.save(PATH)
		return true
	return false
