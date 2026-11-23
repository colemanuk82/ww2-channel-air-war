class_name WarPeriod
extends RefCounted
## War period selector for free flight / dogfight sorties: Early (1939-41), Mid (1942-43), Late (1944-45) or Any.
##
## A period gives (a) a date range the sortie date is drawn from, (b) the aircraft that were in service then, per
## side. `active` is the period of the sortie being flown ("any" = today's free choice, nothing is filtered):
## AircraftCatalog.fighters_for_side / bombers_for_side narrow their pools to it, so the AI, the ambient world and
## the passing flights all use period-appropriate types without each system knowing about it. main.gd sets it at
## sortie start (and back to "any" for every mission that fixes its own date).
## The ground (airfields, damage, build-up, land battles) already follows the date through EraClock.

const ANY := "any"
const IDS := ["any", "early", "mid", "late"]

## id -> [label, short label, first day, last day]. The war in the game's theatre starts in the Battle of France.
const PERIODS := {
	"early": ["Early war (1939-41)", "Early war", "1940-05-10", "1941-12-31"],
	"mid": ["Mid war (1942-43)", "Mid war", "1942-01-01", "1943-12-31"],
	"late": ["Late war (1944-45)", "Late war", "1944-01-01", "1945-04-30"],
}

## id -> side -> aircraft ids in service in that period (only types that exist in data/aircraft).
const IN_SERVICE := {
	"early": {
		"Allies": ["spitfire", "hurricane", "defiant", "blenheim", "beaufort"],
		"Axis": ["bf109", "bf109f", "fw190", "bf110", "ju87", "ju88", "he111", "do17", "ju52", "fw200"],      # the Fw 190 A joins JG 26 in autumn 1941
	},
	"mid": {
		"Allies": ["spitfire", "spitfire_mkix", "hurricane", "typhoon", "mosquito", "p38", "p47", "beaufort", "blenheim", "a20", "b26", "lancaster", "c47"],
		"Axis": ["bf109f", "bf109g", "fw190", "bf110", "ju87", "ju88", "he111", "do17", "ju52", "fw200"],
	},
	"late": {
		"Allies": ["spitfire_mkix", "spitfire_mkxiv", "typhoon", "tempest", "mosquito", "p51", "p47", "p38", "lancaster", "b26", "b25", "a20", "c47"],
		"Axis": ["bf109g", "fw190", "me262", "bf110", "ju87", "ju88", "he111", "ju52", "fw200"],
	},
}

static var active: String = ANY


static func valid(id: String) -> bool:
	return IDS.has(id)


## Menu entries in order: "Any / custom" first, then the three periods.
static func menu_labels() -> Array:
	var out: Array = ["Any / custom"]
	for id in IDS.slice(1):
		out.append(String(PERIODS[id][0]))
	return out


static func label(id: String) -> String:
	return String(PERIODS[id][0]) if PERIODS.has(id) else "Any / custom"


static func first_day(id: String) -> String:
	return String(PERIODS[id][2]) if PERIODS.has(id) else ""


static func last_day(id: String) -> String:
	return String(PERIODS[id][3]) if PERIODS.has(id) else ""


## The period a date falls in ("any" when it is outside all three).
static func of_date(d: String) -> String:
	for id in IDS.slice(1):
		if d >= first_day(id) and d <= last_day(id):
			return id
	return ANY


## True when the date lies inside the period (always true for "any").
static func date_in(id: String, d: String) -> bool:
	return id == ANY or not PERIODS.has(id) or (d >= first_day(id) and d <= last_day(id))


## A random day in the period, optionally only in the given months (a season). "" for "any".
static func random_date(id: String, months: Array = []) -> String:
	if not PERIODS.has(id):
		return ""
	var t0: int = int(Time.get_unix_time_from_datetime_string(first_day(id)))
	var t1: int = int(Time.get_unix_time_from_datetime_string(last_day(id)))
	var d: Dictionary = {}
	for tries in 400:
		d = Time.get_datetime_dict_from_unix_time(randi_range(t0, t1))
		if months.is_empty() or months.has(int(d["month"])):
			break
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


## Aircraft of the side that were in service in the period (all of `ids` for "any").
static func filter(ids: Array, side: String, id: String = "") -> Array:
	var p: String = active if id == "" else id
	if p == ANY or not IN_SERVICE.has(p):
		return ids
	var ok: Array = IN_SERVICE[p].get(side, [])
	return ids.filter(func(a: String) -> bool: return ok.has(a))


## Same as filter(), but never returns an empty list (falls back to the unfiltered one).
static func filter_or_all(ids: Array, side: String, id: String = "") -> Array:
	var f: Array = filter(ids, side, id)
	return f if not f.is_empty() else ids


## A hand-written pool of types with the out-of-period ones swapped for their closest in-period fit (no duplicates);
## unchanged for "any". Used where a pool is built from explicit ids rather than the catalog lists.
static func substitute(pool: Array, side: String) -> Array:
	if active == ANY or not IN_SERVICE.has(active):
		return pool
	var full: Array = AircraftCatalog.ids_for_side(side)
	var out: Array = []
	for a in pool:
		var b: String = closest_fit(str(a), full, side, active)
		if not out.has(b):
			out.append(b)
	return out


## The in-period aircraft closest to `aircraft_id` (the same one when it fits; else the same role, then the same
## type family, then the first in the list). `pool` is the side's full list.
static func closest_fit(aircraft_id: String, pool: Array, side: String, id: String) -> String:
	var fit: Array = filter(pool, side, id)
	if fit.is_empty() or fit.has(aircraft_id):
		return aircraft_id
	var bomber: bool = AircraftCatalog.is_bomber(aircraft_id)
	var best: String = ""
	var best_score: int = -1
	var base: String = aircraft_id.rstrip("0123456789fgxiv").substr(0, 4)
	for a in fit:
		var s: int = 0
		if AircraftCatalog.is_bomber(a) == bomber:
			s += 10
		if String(a).begins_with(base):
			s += 5
		# later / earlier marks of the same family beat unrelated types
		if s > best_score:
			best_score = s
			best = a
	return best if best != "" else String(fit[0])


const FLAVOUR := {
	"early": "The Battle of France, the Battle of Britain and the Channel Dash: Spitfire I/II/V and Hurricanes against Bf 109 E/F, Bf 110 and the Ju 87 / Ju 88 / He 111 / Do 17 bomber fleets.",
	"mid": "Dieppe, the Circus and Rhubarb operations: Spitfire V/IX and Typhoons against Bf 109 F/G and Fw 190 A.",
	"late": "D-Day to the Rhine: Spitfire IX/XIV, Tempests, rocket-firing Typhoons, Mustangs, Thunderbolts and Lightnings against Fw 190 A/D, Bf 109 G/K, V-1 raids and the Me 262.",
}


## One line for the briefing and results.
static func brief_line(id: String, date: String = "") -> String:
	if not PERIODS.has(id):
		return ""
	var s: String = "War period: %s" % label(id)
	if date != "":
		s += " (sortie date %s)" % date
	return s + "\n" + String(FLAVOUR.get(id, "")) + "\nThe sortie date is drawn from this period (your Season choice still applies) and only aircraft in service then are offered and flown by the AI."
