class_name PeriodText
extends RefCounted
## Intelligence summaries and press extracts for the logbook. Items live in data/period_text.json and unlock as
## the career progresses. Each item's "when" block holds conditions that must all hold:
##   done / air: taskings completed / aircraft destroyed (pilot log)
##   day: campaign day reached (campaign save)     mission: that mission id has been completed
## An empty "when" unlocks from the start.

const PATH := "res://data/period_text.json"
static var _items: Array = []


static func items() -> Array:
	if _items.is_empty():
		var f: FileAccess = FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_items = (d as Dictionary).get("items", [])
	return _items


static func _campaign_day() -> int:
	if Campaign.state.is_empty() and Campaign.has_save():
		Campaign.load_state()
	return int(Campaign.state.get("day", 0))


static func _met(when: Dictionary, career: Dictionary, day: int) -> bool:
	for k in when.keys():
		var want: Variant = when[k]
		match str(k):
			"done", "air":
				if int(career.get(k, 0)) < int(want):
					return false
			"day":
				if day < int(want):
					return false
			"mission":
				if not GameState.completed_missions.has(str(want)):
					return false
			_:
				return false
	return true


## The items for one side that the career has unlocked so far.
static func unlocked(side: String) -> Array:
	var career: Dictionary = PilotLog.career(side)
	var day: int = _campaign_day()
	var out: Array = []
	for it in items():
		if str(it["side"]) == side and _met(it.get("when", {}), career, day):
			out.append(it)
	return out


## The logbook section: how many have been unlocked, then each one.
static func section_text(side: String) -> String:
	var total: int = 0
	for it in items():
		if str(it["side"]) == side:
			total += 1
	var got: Array = unlocked(side)
	var t: String = "\nINTELLIGENCE AND PRESS EXTRACTS  (%d of %d)\n" % [got.size(), total]
	if got.is_empty():
		return t + "  Nothing yet. Fly more sorties.\n"
	for it in got:
		var kind: String = "INTEL" if str(it["kind"]) == "intel" else "PRESS"
		t += "\n  [%s] %s\n  %s\n" % [kind, str(it["title"]), str(it["body"])]
	return t
