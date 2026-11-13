class_name MissionBrief
extends RefCounted
## What a historical mission asks of the pilot, in words: the structured briefing (task, route, opposition,
## conditions), the bonus objectives picked for it, and the graded debrief once it is over.
## Everything here is static and reads only data/missions.json entries and data/locations.json, so the menu can
## call it without a world and the tests can check every mission.
##
## Bonus objectives: two per mission and side, chosen from the pool for the side's role (see POOLS). Each is
## {id, text, short, need}. The grade is 0 for a failed mission, otherwise 1 + the number of bonuses achieved.

const LOCATIONS_PATH := "res://data/locations.json"
const GRADE_NAMES := ["Mission failed", "Satisfactory", "Commended", "Outstanding"]
const BONUS_COUNT: int = 2

## Bonus pools by role. The order is rotated by the mission id, so two missions of the same role differ.
const POOLS := {
	"strike": ["accuracy", "par", "air_kill", "clean"],
	"strike_quiet": ["accuracy", "par", "clean"],          # no enemy fighters on this run
	"strafe": ["par", "air_kill", "clean", "ground_kills"],
	"defend": ["intact", "bomber_kills", "clean", "air_kill"],
	"escort": ["all_home", "air_kills", "clean"],
	"sweep": ["air_kills", "no_loss", "par"],
}

static var _loc: Dictionary = {}       # id -> {name, lat, lon, kind}


static func _index() -> Dictionary:
	if not _loc.is_empty():
		return _loc
	var f: FileAccess = FileAccess.open(LOCATIONS_PATH, FileAccess.READ)
	if f == null:
		return _loc
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return _loc
	for kind in ["targets", "airfields", "cities", "features"]:
		for e in (d as Dictionary).get(kind, []):
			var id: String = str(e.get("id", ""))
			if id != "" and not _loc.has(id):
				_loc[id] = {"name": str(e.get("name", id)), "lat": float(e.get("lat", 0.0)), "lon": float(e.get("lon", 0.0)), "kind": kind}
	return _loc


## The proper name of a target / airfield id ("Chain Home Dover"), or a tidied id when it is not in the data.
static func place_name(id: String) -> String:
	var e: Dictionary = _index().get(id, {})
	if not e.is_empty():
		return str(e["name"])
	return id.replace("_", " ").capitalize()


static func has_place(id: String) -> bool:
	return _index().has(id)


## Great-circle distance in km between two places (ids from locations.json); -1 when either is unknown.
static func distance_km(a: String, b: String) -> float:
	var ea: Dictionary = _index().get(a, {})
	var eb: Dictionary = _index().get(b, {})
	if ea.is_empty() or eb.is_empty():
		return -1.0
	return latlon_km(float(ea["lat"]), float(ea["lon"]), float(eb["lat"]), float(eb["lon"]))


static func latlon_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var p1: float = deg_to_rad(lat1)
	var p2: float = deg_to_rad(lat2)
	var dp: float = p2 - p1
	var dl: float = deg_to_rad(lon2 - lon1)
	var h: float = sin(dp * 0.5) * sin(dp * 0.5) + cos(p1) * cos(p2) * sin(dl * 0.5) * sin(dl * 0.5)
	return 6371.0 * 2.0 * atan2(sqrt(h), sqrt(maxf(1.0 - h, 0.0)))


## Initial true bearing in degrees (0 = north, 90 = east) from a to b; -1 when either is unknown.
static func bearing_deg(a: String, b: String) -> float:
	var ea: Dictionary = _index().get(a, {})
	var eb: Dictionary = _index().get(b, {})
	if ea.is_empty() or eb.is_empty():
		return -1.0
	var p1: float = deg_to_rad(float(ea["lat"]))
	var p2: float = deg_to_rad(float(eb["lat"]))
	var dl: float = deg_to_rad(float(eb["lon"]) - float(ea["lon"]))
	var y: float = sin(dl) * cos(p2)
	var x: float = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
	return fposmod(rad_to_deg(atan2(y, x)), 360.0)


static func compass(deg: float) -> String:
	var names: Array = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return names[int(round(fposmod(deg, 360.0) / 45.0)) % 8]


static func _side_cfg(m: Dictionary, side: String) -> Dictionary:
	for s in m.get("sides", []):
		if str(s.get("side", "")) == side:
			return s
	return {}


static func role_of(m: Dictionary, side: String) -> String:
	return str((m.get("roles", {}) as Dictionary).get(side, "strike"))


## The ids the side's task is about: the sites to protect on a defend mission, otherwise its objectives.
static func task_ids(m: Dictionary, side: String) -> Array:
	var objs: Array = (m.get("objectives", {}) as Dictionary).get(side, [])
	if role_of(m, side) == "defend":
		return (m.get("protect", {}) as Dictionary).get(side, objs)
	return objs


static func _join(names: Array) -> String:
	if names.size() <= 1:
		return "" if names.is_empty() else str(names[0])
	var head: Array = names.slice(0, names.size() - 1)
	return "%s and %s" % [", ".join(PackedStringArray(head)), str(names[names.size() - 1])]


## One sentence saying what the side has to do, with the real place names.
static func task_line(m: Dictionary, side: String) -> String:
	var role: String = role_of(m, side)
	var names: Array = []
	for id in task_ids(m, side):
		names.append(place_name(str(id)))
	var what: String = _join(names)
	match role:
		"sweep":
			return "Sweep the area and clear the sky of enemy fighters."
		"defend":
			return "Break up the raids on %s. At least half must still stand when the last raid turns for home." % what
		"escort":
			return "Stay with the bombers to %s and bring them home." % what
		"strafe":
			return "Find and destroy %s." % what
		_:
			return "Destroy %s, then return to base." % what


## Distance and bearing from the start airfield to the first task site, or "" when the data does not allow it.
static func route_line(m: Dictionary, side: String) -> String:
	var sc: Dictionary = _side_cfg(m, side)
	var home: String = str(sc.get("start_airfield", ""))
	var ids: Array = task_ids(m, side)
	if home == "" or ids.is_empty() or not has_place(home):
		return ""
	var first: String = str(ids[0])
	var hn: String = place_name(home)
	if sc.has("spawn"):         # the sortie starts in the air at a fixed point: the airfield is only "home"
		var sp: Dictionary = sc["spawn"]
		var e: Dictionary = _index().get(first, {})
		if e.is_empty():
			return "Home field: %s." % hn
		return "You join the mission in the air, %d km from %s. Home field: %s." % [
			int(round(latlon_km(float(sp["lat"]), float(sp["lon"]), float(e["lat"]), float(e["lon"])))), place_name(first), hn]
	var km: float = distance_km(home, first)
	if km < 0.0:
		return "From %s." % hn
	if km < 3.0:
		return "From %s, right over the field." % hn
	var brg: float = bearing_deg(home, first)
	var leg: String = "%s lies %d km to the %s (steer %03d)" % [place_name(first), int(round(km)), compass(brg), int(round(brg)) % 360]
	if role_of(m, side) == "defend":
		return "From %s. %s." % [hn, leg]
	return "From %s. %s. %s." % [hn, leg, "Take off from the runway" if not bool(m.get("airborne", true)) else "You start airborne over the field"]


## Which side flies an aircraft type when only one side has it; "" when both or neither do.
static func _owner_of(aircraft_id: String) -> String:
	var ax: bool = AircraftCatalog.ids_for_side("Axis").has(aircraft_id)
	var al: bool = AircraftCatalog.ids_for_side("Allies").has(aircraft_id)
	if ax == al:
		return ""
	return "Axis" if ax else "Allies"


## Enemy aircraft types the scripted events will bring against this side (display names, no repeats).
static func opposition(m: Dictionary, side: String) -> Array:
	var out: Array = []
	for e in m.get("events", []):
		if not (e is Dictionary) or not (e as Dictionary).has("aircraft"):
			continue
		var id: String = str(e["aircraft"])
		var owner: String = _owner_of(id)
		var hostile: bool = (owner != side) if owner != "" else bool(e.get("hostile", false))
		if not hostile:
			continue
		var nm: String = AircraftCatalog.display_name(id) if ResourceLoader.exists("res://data/aircraft/%s.tres" % id) else id.to_upper()
		if not out.has(nm):
			out.append(nm)
	return out


static func opposition_line(m: Dictionary, side: String) -> String:
	var role: String = role_of(m, side)
	var types: Array = opposition(m, side)
	var parts: Array = []
	if not types.is_empty():
		parts.append("Intelligence reports %s on the route" % _join(types))
	match role:
		"defend":
			parts.append("%d raids are plotted, each bombers with a fighter escort" % int(m.get("waves", 3)))
		"escort":
			parts.append("expect interceptors to go for the bombers, not for you")
		"sweep":
			parts.append("enemy fighters will come up in waves")
		"strafe":
			parts.append("light flak covers the target")
		_:
			if bool(m.get("no_fighters", false)):
				parts.append("no enemy fighters are expected")
			else:
				parts.append("flak at the target, and fighters will come up once you are near it")
	var out: Array = []
	for p in parts:
		out.append(_cap(str(p)))
	return ". ".join(PackedStringArray(out)) + "."


static func _cap(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1)


static func _clock(hour: float) -> String:
	var h: int = int(floor(fposmod(hour, 24.0)))
	var mn: int = int(round((fposmod(hour, 24.0) - float(h)) * 60.0)) % 60
	var part: String = "night"
	if hour >= 5.0 and hour < 8.0:
		part = "dawn"
	elif hour >= 8.0 and hour < 12.0:
		part = "morning"
	elif hour >= 12.0 and hour < 17.0:
		part = "afternoon"
	elif hour >= 17.0 and hour < 20.5:
		part = "dusk" if hour >= 19.0 else "evening"
	return "%02d:%02d, %s" % [h, mn, part]


const WEATHER_WORDS := {
	"clear": "clear skies", "scattered": "scattered cloud", "overcast": "overcast", "rain": "rain and low cloud",
	"storm": "storms", "fog": "fog", "mist": "mist", "snow": "snow showers",
}


static func conditions_line(m: Dictionary) -> String:
	var w: String = str(m.get("weather", "clear"))
	return "%s. %s." % [_clock(float(m.get("time_of_day", 12.0))), _cap(str(WEATHER_WORDS.get(w, w.replace("_", " "))))]


static func date_text(iso: String) -> String:
	var p: PackedStringArray = iso.split("-")
	if p.size() != 3:
		return iso
	var months: Array = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
	var mi: int = clampi(int(p[1]) - 1, 0, 11)
	return "%d %s %s" % [int(p[2]), months[mi], p[0]]


## Par time in seconds for the "home in time" bonus: the mission's time_limit (a route-based estimate).
static func par_seconds(m: Dictionary) -> float:
	return maxf(float(m.get("time_limit", 1800)), 600.0)


static func _bonus(kind: String, m: Dictionary) -> Dictionary:
	match kind:
		"par":
			var mins: int = int(ceil(par_seconds(m) / 60.0))
			return {"id": kind, "text": "Finish the job inside %d minutes" % mins, "short": "Inside %d min" % mins, "need": par_seconds(m)}
		"accuracy":
			return {"id": kind, "text": "Put at least half your bombs on target", "short": "Half your bombs on target", "need": 0.5}
		"air_kill":
			return {"id": kind, "text": "Shoot down an enemy aircraft yourself", "short": "Shoot down an enemy aircraft", "need": 1}
		"air_kills":
			return {"id": kind, "text": "Shoot down three enemy aircraft yourself", "short": "Shoot down 3 aircraft", "need": 3}
		"bomber_kills":
			return {"id": kind, "text": "Shoot down three aircraft of the raids yourself", "short": "Shoot down 3 raiders", "need": 3}
		"ground_kills":
			return {"id": kind, "text": "Destroy eight vehicles, guns or wagons", "short": "Destroy 8 ground targets", "need": 8}
		"clean":
			return {"id": kind, "text": "Bring your aircraft home with no more than light damage", "short": "No more than light damage", "need": 0.6}
		"intact":
			return {"id": kind, "text": "Let none of the protected sites be destroyed", "short": "Lose none of the sites", "need": 0}
		"all_home":
			return {"id": kind, "text": "Bring every bomber home", "short": "Every bomber home", "need": 0}
		"no_loss":
			return {"id": kind, "text": "Do not lose an aircraft", "short": "Lose no aircraft", "need": 0}
	return {"id": kind, "text": kind, "short": kind, "need": 0}


## The two bonus objectives for a mission and side (stable: the same mission always gets the same pair).
static func bonuses(m: Dictionary, side: String) -> Array:
	var role: String = role_of(m, side)
	var key: String = role
	if role == "strike" and bool(m.get("no_fighters", false)):
		key = "strike_quiet"
	var pool: Array = (POOLS.get(key, POOLS["strike"]) as Array).duplicate()
	if role == "defend" and task_ids(m, side).size() < 2:
		pool.erase("intact")         # one site: losing it already fails the mission
	var mid: String = str(m.get("id", ""))
	var h: int = 0
	for i in mid.length():
		h = (h * 31 + mid.unicode_at(i)) % 9973
	var out: Array = []
	for k in mini(BONUS_COUNT, pool.size()):
		out.append(_bonus(str(pool[(h + k) % pool.size()]), m))
	return out


## The full briefing shown in the menu: name and date, the written brief, then task, route, opposition,
## conditions and the bonus objectives.
static func briefing(m: Dictionary, side: String) -> String:
	if m.is_empty():
		return ""
	var lines: Array = ["%s  (%s)" % [str(m.get("name", "")), date_text(str(m.get("date", "")))], "", str(m.get("brief", "")), ""]
	lines.append("TASK  %s" % task_line(m, side))
	var rt: String = route_line(m, side)
	if rt != "":
		lines.append("ROUTE  %s" % rt)
	lines.append("OPPOSITION  %s" % opposition_line(m, side))
	lines.append("CONDITIONS  %s" % conditions_line(m))
	var bl: Array = []
	for b in bonuses(m, side):
		bl.append(str(b["text"]))
	if not bl.is_empty():
		lines.append("FOR A COMMENDATION  %s." % "; ".join(PackedStringArray(bl)))
	return "\n".join(PackedStringArray(lines))


# ------------------------------------------------------------------ scoring the sortie

## Whether one bonus was achieved, from the end-of-mission facts:
##   success, time (s), air_kills, ground_kills, bombs_dropped, bombs_hit, health_frac (0..1, -1 unknown),
##   lives_lost, protected_alive, protected, bombers_alive, bombers.
static func bonus_done(b: Dictionary, f: Dictionary) -> bool:
	if not bool(f.get("success", false)):
		return false
	match str(b.get("id", "")):
		"par":
			return float(f.get("time", INF)) <= float(b["need"])
		"accuracy":
			var dropped: int = int(f.get("bombs_dropped", 0))
			return dropped > 0 and float(f.get("bombs_hit", 0)) / float(dropped) >= float(b["need"])
		"air_kill", "air_kills", "bomber_kills":
			return int(f.get("air_kills", 0)) >= int(b["need"])
		"ground_kills":
			return int(f.get("ground_kills", 0)) >= int(b["need"])
		"clean":
			return int(f.get("lives_lost", 0)) == 0 and float(f.get("health_frac", 1.0)) >= float(b["need"])
		"intact":
			return int(f.get("protected", 0)) > 0 and int(f.get("protected_alive", 0)) >= int(f.get("protected", 0))
		"all_home":
			return int(f.get("bombers", 0)) > 0 and int(f.get("bombers_alive", 0)) >= int(f.get("bombers", 0))
		"no_loss":
			return int(f.get("lives_lost", 0)) == 0
	return false


## Progress text for the in-flight objective card ("2/3", "41:10 of 76:00"), or "" when there is nothing to count.
static func bonus_progress(b: Dictionary, f: Dictionary) -> String:
	match str(b.get("id", "")):
		"par":
			var left: float = float(b["need"]) - float(f.get("time", 0.0))
			if left < 0.0:
				return "over time"
			return "%d:%02d left" % [int(left) / 60, int(left) % 60]
		"accuracy":
			var dropped: int = int(f.get("bombs_dropped", 0))
			return "%d of %d on target" % [int(f.get("bombs_hit", 0)), dropped] if dropped > 0 else ""
		"air_kill", "air_kills", "bomber_kills":
			return "%d/%d" % [mini(int(f.get("air_kills", 0)), int(b["need"])), int(b["need"])]
		"ground_kills":
			return "%d/%d" % [mini(int(f.get("ground_kills", 0)), int(b["need"])), int(b["need"])]
		"clean":
			var hf: float = float(f.get("health_frac", 1.0))
			return "airframe %d%%" % int(round(clampf(hf, 0.0, 1.0) * 100.0))
		"intact":
			return "%d/%d standing" % [int(f.get("protected_alive", 0)), int(f.get("protected", 0))] if int(f.get("protected", 0)) > 0 else ""
		"all_home":
			return "%d/%d flying" % [int(f.get("bombers_alive", 0)), int(f.get("bombers", 0))] if int(f.get("bombers", 0)) > 0 else ""
		"no_loss":
			return "%d lost" % int(f.get("lives_lost", 0)) if int(f.get("lives_lost", 0)) > 0 else ""
	return ""


## True once a bonus can no longer be earned on this sortie (shown struck out; the pilot is told once).
static func bonus_lost(b: Dictionary, f: Dictionary) -> bool:
	match str(b.get("id", "")):
		"par":
			return float(f.get("time", 0.0)) > float(b["need"])
		"clean", "no_loss":
			return int(f.get("lives_lost", 0)) > 0
		"intact":
			return int(f.get("protected", 0)) > 0 and int(f.get("protected_alive", 0)) < int(f.get("protected", 0))
		"all_home":
			return int(f.get("bombers", 0)) > 0 and int(f.get("bombers_alive", 0)) < int(f.get("bombers", 0))
	return false


static func grade(success: bool, bonuses_done: int) -> int:
	if not success:
		return 0
	return clampi(1 + bonuses_done, 1, GRADE_NAMES.size() - 1)


static func grade_name(g: int) -> String:
	return GRADE_NAMES[clampi(g, 0, GRADE_NAMES.size() - 1)]


static func _fail_cause(reason: String) -> String:
	var r: String = reason.to_lower()
	if r.contains("crash"):
		return "Your aircraft was lost in a crash"
	if r.contains("shot down") or r.contains("killed"):
		return "You were shot down"
	if r.contains("bombers lost"):
		return "Every bomber in the formation was lost"
	if r.contains("time"):
		return "Time ran out"
	return ""


## A short written account of the sortie for the results screen.
static func summary(m: Dictionary, side: String, f: Dictionary) -> String:
	var role: String = role_of(m, side)
	var ok: bool = bool(f.get("success", false))
	var names: Array = []
	for id in task_ids(m, side):
		names.append(place_name(str(id)))
	var where: String = _join(names)
	var s: Array = []
	var ak: int = int(f.get("air_kills", 0))
	match role:
		"defend":
			var alive: int = int(f.get("protected_alive", 0))
			var total: int = int(f.get("protected", 0))
			if ok:
				s.append("The raids on %s were broken up." % where if alive >= total else "The raids got through to %s, but enough still stands." % where)
			else:
				var cause: String = _fail_cause(str(f.get("reason", "")))
				if cause != "" and alive > 0:
					s.append("%s with the raids still coming in." % cause)
				elif alive <= 0 and total > 0:
					s.append("The bombers got through and %s was destroyed." % where)
				else:
					s.append("The raiders reached %s untouched: not one was shot down." % where)
			if total > 1:
				s.append("%d of %d sites are still standing." % [alive, total])
		"escort":
			var ba: int = int(f.get("bombers_alive", 0))
			var bt: int = int(f.get("bombers", 0))
			if ok:
				s.append("The bombers hit %s and %s came home." % [where, "all of them" if ba >= bt else "%d of %d" % [ba, bt]])
			else:
				var cause2: String = _fail_cause(str(f.get("reason", "")))
				s.append("%s before the formation was home." % (cause2 if cause2 != "" else "The escort failed"))
		"sweep":
			s.append("The sweep cleared the sky." if ok else "The sweep was driven off.")
		_:
			var done: int = int(f.get("targets_destroyed", 0))
			var tot: int = int(f.get("targets", names.size()))
			if ok:
				s.append("%s destroyed, and you brought the aircraft home." % where)
			else:
				var cause3: String = _fail_cause(str(f.get("reason", "")))
				var tail: String = "with the job unfinished." if done < tot or tot == 0 else "on the way home, with the targets already down."
				s.append("%s %s" % [cause3 if cause3 != "" else "The sortie was abandoned", tail])
			if tot > 1 and not ok:
				s.append("%d of %d targets were destroyed." % [done, tot])
			var dropped: int = int(f.get("bombs_dropped", 0))
			if dropped > 0:
				s.append("%d of your %d bombs fell on target." % [int(f.get("bombs_hit", 0)), dropped])
	if ak > 0:
		s.append("You shot down %d enemy aircraft." % ak)
	var gk: int = int(f.get("ground_kills", 0))
	if gk > 0 and role in ["strafe", "strike"]:
		s.append("%d vehicles, guns and wagons were knocked out on the ground." % gk)
	return " ".join(PackedStringArray(s))


## Everything the results screen needs: {title, grade, grade_name, summary, objectives: [{text, done, primary, note}]}.
static func debrief(m: Dictionary, side: String, f: Dictionary) -> Dictionary:
	var ok: bool = bool(f.get("success", false))
	var objs: Array = [{"text": task_line(m, side), "done": ok, "primary": true, "note": ""}]
	var n_done: int = 0
	for b in bonuses(m, side):
		var d: bool = bonus_done(b, f)
		if d:
			n_done += 1
		objs.append({"text": str(b["text"]), "done": d, "primary": false, "note": bonus_progress(b, f)})
	var g: int = grade(ok, n_done)
	return {"title": str(m.get("name", "")), "grade": g, "grade_name": grade_name(g), "summary": summary(m, side, f), "objectives": objs}
