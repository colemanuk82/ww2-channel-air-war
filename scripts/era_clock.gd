class_name EraClock
extends RefCounted
## The war date the world is built for. Everything on the ground that changes with the war (bomb damage, the 1944
## build-up, Normandy after D-Day, the floods, the gliders) asks here.
##
## GameState.era_date is "" for quick missions and free flight that have no date; the ground then shows
## DEFAULT (high summer 1940, the Battle of Britain), which is what the 1940 data describes.
##
## The date is cached in a static so worker threads (tile scatter) can read it without touching the scene tree.
## WorldPopulator calls set_date() when it registers and again from main.start_game(); when the date changes,
## the populator drops its built tiles and sites so they rebuild for the new date (on the load screen).

const DEFAULT := "1940-08-15"

## Era bands, in order: [id, first day]. A band runs until the next one starts.
const BANDS := [
	["1940", "1900-01-01"],        # Phoney war, Dunkirk, Battle of Britain
	["blitz", "1940-09-07"],       # Black Saturday: the night Blitz on London begins
	["midwar", "1941-06-01"],      # after the Blitz; the bomber offensive grows
	["buildup", "1944-04-01"],     # the invasion build-up across southern England
	["liberation", "1944-06-06"],  # D-Day and the advance
	["1945", "1945-01-01"],        # the last winter, the Rhine
]

static var _date: String = ""
static var revision: int = 0       # bumps whenever the date changes (lets caches notice)


## Set the date ("" = no date: DEFAULT). Returns true when it changed.
static func set_date(d: String) -> bool:
	var nd: String = d if _valid(d) else ""
	if nd == _date:
		return false
	_date = nd
	revision += 1
	return true


## The effective ISO date (never empty).
static func current() -> String:
	return _date if _date != "" else DEFAULT


## True when the effective date lies in [from, to] (either end may be "" = open).
static func is_between(from: String, to: String) -> bool:
	var d: String = current()
	return (from == "" or d >= from) and (to == "" or d <= to)


## Same test for an explicit date.
static func in_window(d: String, from: String, to: String) -> bool:
	return (from == "" or d >= from) and (to == "" or d <= to)


static func band() -> String:
	return band_of(current())


static func band_of(d: String) -> String:
	var out: String = str(BANDS[0][0])
	for b in BANDS:
		if d >= str(b[1]):
			out = str(b[0])
	return out


## Days from `from` to the effective date (negative before). Used to grow damage over a raid period.
static func days_since(from: String) -> int:
	return int((_unix(current()) - _unix(from)) / 86400)


## 0..1 ramp: 0 on/before `from`, 1 on/after `full` (linear in days between).
static func ramp(from: String, full: String) -> float:
	var a: float = float(_unix(from))
	var b: float = float(_unix(full))
	var t: float = float(_unix(current()))
	if b <= a:
		return 1.0 if t >= a else 0.0
	return clampf((t - a) / (b - a), 0.0, 1.0)


## Month 1..12 of the effective date (seasons).
static func month() -> int:
	return int(current().substr(5, 2))


static func _unix(d: String) -> int:
	if not _valid(d):
		return 0
	return Time.get_unix_time_from_datetime_string(d + "T12:00:00")


static func _valid(d: String) -> bool:
	return d.length() == 10 and d[4] == "-" and d[7] == "-" and d.substr(0, 4).is_valid_int()
