class_name Campaign
extends RefCounted
## Dynamic single-pilot campaign. State lives in user://campaign.json:
##   side, aircraft, home (airfield id), date (ISO), day, pilot {rank, kills, sorties, score, lost_days},
##   strength {own, enemy} (air strength %), industry {own, enemy} (production %), damaged {target_id: days},
##   offers [today's sortie options], log [news lines], ended ("" | "victory" | "defeat").
## Every day the situation changes: bombed targets are out for a week, the enemy raids your industry in proportion to its
## remaining air strength, losses and kills move the strengths, and three new sorties are offered based on all of that.

const SAVE_PATH := "user://campaign.json"
const RANKS := {
	"Allies": ["Pilot Officer", "Flying Officer", "Flight Lieutenant", "Squadron Leader", "Wing Commander", "Group Captain"],
	"Axis": ["Leutnant", "Oberleutnant", "Hauptmann", "Major", "Oberstleutnant", "Oberst"],
}
const RANK_SCORE := [0, 1500, 4000, 8000, 14000, 22000]
const ERAS := [["Battle of Britain  (Aug 1940)", "1940-08-08"], ["Dieppe  (Aug 1942)", "1942-08-17"], ["Normandy  (Jun 1944)", "1944-06-01"], ["Rhineland  (Oct 1944)", "1944-10-01"]]
const STRIKE_TYPES := ["factory", "rail_yard", "port", "bridge", "v1_site", "radar", "battery"]
const MAX_DAYS := 90

static var state: Dictionary = {}
static var _loc: Dictionary = {}


static func loc() -> Dictionary:
	if _loc.is_empty():
		var f: FileAccess = FileAccess.open("res://data/locations.json", FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_loc = d
	return _loc


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func load_state() -> bool:
	if not has_save():
		return false
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	if d is Dictionary and (d as Dictionary).has("side"):
		state = d
		return true
	return false


static func save_state() -> void:
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(state))


static func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	state = {}


static func airfields_for(side: String, date_iso: String = "") -> Array:
	var out: Array = []
	for a in loc().get("airfields", []):
		if not bool(a.get("in_bounds", true)):
			continue
		var holder: String = "Allies" if str(a["side"]) == "RAF" else "Axis"
		var lib: String = str(a.get("liberated", ""))
		if lib != "" and date_iso != "" and date_iso >= lib:
			holder = "Allies"
		if holder == side:
			out.append(a)
	return out


static func _airfield(id: String) -> Dictionary:
	for a in loc().get("airfields", []):
		if str(a["id"]) == id:
			return a
	return {}


static func new_campaign(side: String, aircraft: String, home: String, date_iso: String) -> void:
	state = {
		"version": 1, "side": side, "aircraft": aircraft, "home": home, "date": date_iso, "day": 0,
		"pilot": {"kills": 0, "sorties": 0, "score": 0, "lost_days": 0},
		"strength": {"own": 70.0, "enemy": 75.0}, "industry": {"own": 100.0, "enemy": 100.0},
		"damaged": {}, "offers": [], "log": ["Campaign begins on %s." % date_iso], "ended": "",
	}
	generate_offers()
	save_state()


static func rank_name() -> String:
	var sc: int = int(state["pilot"]["score"])
	var r: int = 0
	for i in RANK_SCORE.size():
		if sc >= int(RANK_SCORE[i]):
			r = i
	return str((RANKS[str(state["side"])] as Array)[r])


static func _km(la1: float, lo1: float, la2: float, lo2: float) -> float:
	return sqrt(pow((lo1 - lo2) * 71.0, 2.0) + pow((la1 - la2) * 111.0, 2.0))


static func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s|%d|%d" % [state.get("date", ""), int(state["pilot"]["sorties"]), int(state.get("day", 0))])
	return r


## Targets owned by `owner_side` of the given types, nearest the home field first, skipping ones that are out of action.
static func _pool(owner_side: String, types: Array, naval: Variant = null, include_damaged: bool = false) -> Array:
	var home: Dictionary = _airfield(str(state["home"]))
	var out: Array = []
	for t in loc().get("targets", []):
		if str(t["side_owner"]) != owner_side or not bool(t.get("in_bounds", true)) or not (str(t["type"]) in types):
			continue
		if naval != null and bool(t.get("naval", false)) != bool(naval):
			continue
		if not include_damaged and (state["damaged"] as Dictionary).has(str(t["id"])):
			continue
		out.append(t)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _km(float(a["lat"]), float(a["lon"]), float(home["lat"]), float(home["lon"])) < _km(float(b["lat"]), float(b["lon"]), float(home["lat"]), float(home["lon"])))
	return out


static func generate_offers() -> void:
	var rng: RandomNumberGenerator = _rng()
	var side: String = str(state["side"])
	var enemy: String = "Axis" if side == "Allies" else "Allies"
	var es: float = float(state["strength"]["enemy"])
	var diff: float = clampf(0.2 + 0.6 * es / 100.0, 0.2, 0.9)
	var offers: Array = []
	var kinds: Array = ["strike", "ground", "ships", "escort", "sweep", "defend"]
	# the enemy raids more often the stronger it is
	var weights: Dictionary = {"strike": 3.0, "ground": 2.0, "ships": 1.2, "escort": 1.6, "sweep": 1.4, "defend": 0.6 + 2.4 * es / 100.0}
	var chosen: Array = ["strike"]
	while chosen.size() < 3:
		var total: float = 0.0
		for k in kinds:
			if not (k in chosen):
				total += float(weights[k])
		var roll: float = rng.randf() * total
		for k2 in kinds:
			if k2 in chosen:
				continue
			roll -= float(weights[k2])
			if roll <= 0.0:
				chosen.append(k2)
				break
	for kind in chosen:
		var o: Dictionary = _make_offer(kind, rng, side, enemy, diff)
		if not o.is_empty():
			offers.append(o)
	if offers.is_empty():   # nothing left to hit: fall back to a sweep
		offers.append({"kind": "sweep", "title": "Fighter sweep", "brief": "Sweep the area for enemy fighters.", "mode": "dogfight", "difficulty": diff, "reward": 400})
	state["offers"] = offers


static func _make_offer(kind: String, rng: RandomNumberGenerator, side: String, enemy: String, diff: float) -> Dictionary:
	var pool: Array = []
	match kind:
		"strike", "escort":
			pool = _pool(enemy, STRIKE_TYPES)
		"ground":
			pool = _pool(enemy, ["convoy_route", "battery", "rail_yard"], false)
		"ships":
			pool = _pool(enemy, ["convoy_route"], true)
		"defend":
			pool = _pool(side, ["factory", "rail_yard", "port", "bridge", "radar"], null, true)
		"sweep":
			return {"kind": "sweep", "title": "Fighter sweep", "mode": "dogfight", "difficulty": diff, "reward": 500,
				"brief": "Sweep the front for enemy fighters. No ground objectives: score kills and get home."}
	if pool.is_empty():
		return {}
	var t: Dictionary = pool[rng.randi() % mini(pool.size(), 5)]
	var ids: Array = [str(t["id"])]
	for t2 in pool:
		if t2 != t and ids.size() < 3 and absf(float(t2["lat"]) - float(t["lat"])) < 0.08 and absf(float(t2["lon"]) - float(t["lon"])) < 0.12:
			ids.append(str(t2["id"]))
	var nm: String = str(t["name"])
	var o: Dictionary = {"kind": kind, "difficulty": diff, "targets": ids}
	match kind:
		"strike":
			o.merge({"title": "Bomb %s" % nm, "mode": "bombing", "reward": 900, "brief": "Fly to %s and bomb it through the flak and interceptors, then return to base." % nm})
		"ground":
			o.merge({"title": "Strike %s" % nm, "mode": "ground", "reward": 700, "brief": "Hit %s: vehicles, trains and guns behind the lines. Low and fast." % nm})
		"ships":
			o.merge({"title": "Shipping strike: %s" % nm, "mode": "ground", "reward": 800, "brief": "Find and sink the ships of %s." % nm})
		"escort":
			o.merge({"title": "Escort bombers to %s" % nm, "mode": "escort", "reward": 1000, "brief": "Cover a bomber formation to %s and back. Keep them alive." % nm})
		"defend":
			o.merge({"title": "Defend %s" % nm, "mode": "defend", "reward": 800, "protect": ids, "brief": "Enemy bombers are heading for %s. Intercept before they bomb." % nm})
	return o


static func offer_config(i: int) -> Dictionary:
	var offers: Array = state["offers"]
	var o: Dictionary = offers[clampi(i, 0, offers.size() - 1)]
	var home: Dictionary = _airfield(str(state["home"]))
	var rng: RandomNumberGenerator = _rng()
	var cfg: Dictionary = {
		"side": state["side"], "aircraft": state["aircraft"], "mode": o["mode"], "difficulty": float(o["difficulty"]),
		"weather": ["clear", "scattered", "overcast"][rng.randi() % 3], "time": ["dawn", "noon", "dusk"][rng.randi() % 3],
		"ambient": false, "campaign": true, "era_date": str(state["date"]), "campaign_offer": i, "campaign_day": int(state["day"]),
		"spawn_lat": float(home["lat"]), "spawn_lon": float(home["lon"]), "spawn_airfield": str(home["id"]),
		"spawn_airborne": false, "spawn_heading": float(home.get("heading_deg", 90)), "spawn_alt": 1200.0,
	}
	cfg["wingmen"] = 2 if not AircraftCatalog.is_bomber(str(state["aircraft"])) and str(o["mode"]) != "dogfight" else 0
	if str(o["mode"]) == "escort":      # start in the air with the bombers instead of chasing them from the runway
		cfg["spawn_airborne"] = true
		cfg["spawn_alt"] = 1400.0
	if o.has("targets"):
		cfg["targets"] = o["targets"]
	if o.has("protect"):
		cfg["protect"] = o["protect"]
	return cfg


## Called by main when a campaign sortie ends. Returns extra stats lines for the results screen.
static func record_result(success: bool, stats: Dictionary, cfg: Dictionary) -> Dictionary:
	if state.is_empty() or int(cfg.get("campaign_day", -1)) != int(state["day"]):
		return {}     # replayed sortie: already counted
	var offers: Array = state["offers"]
	var o: Dictionary = offers[clampi(int(cfg.get("campaign_offer", 0)), 0, offers.size() - 1)]
	var kind: String = str(o["kind"])
	var rng: RandomNumberGenerator = _rng()
	var kills: int = int(stats.get("kills", 0)) + int(stats.get("fighters_down", 0)) + int(stats.get("bombers_down", 0))
	var pilot: Dictionary = state["pilot"]
	pilot["sorties"] = int(pilot["sorties"]) + 1
	pilot["kills"] = int(pilot["kills"]) + kills
	var gained: int = int(stats.get("score", 0)) + (int(o.get("reward", 500)) if success else 0)
	pilot["score"] = int(pilot["score"]) + gained
	var st: Dictionary = state["strength"]
	var ind: Dictionary = state["industry"]
	var log: Array = state["log"]
	var title: String = str(o["title"])
	if success:
		match kind:
			"strike", "ground", "ships", "escort":
				for id in o.get("targets", []):
					(state["damaged"] as Dictionary)[str(id)] = 6 + rng.randi() % 3
				ind["enemy"] = maxf(float(ind["enemy"]) - (6.0 if kind == "strike" or kind == "escort" else 3.0), 0.0)
				st["enemy"] = maxf(float(st["enemy"]) - 1.0 - float(kills) * 0.5, 5.0)
			"sweep":
				st["enemy"] = maxf(float(st["enemy"]) - 4.0 - float(kills) * 0.6, 5.0)
			"defend":
				ind["own"] = minf(float(ind["own"]) + 1.0, 100.0)
				st["enemy"] = maxf(float(st["enemy"]) - 2.0 - float(kills) * 0.4, 5.0)
		log.append("Day %d: %s - SUCCESS (+%d)." % [int(state["day"]) + 1, title, gained])
	else:
		st["own"] = maxf(float(st["own"]) - 3.0, 5.0)
		if kind == "defend":
			for id in o.get("protect", []):
				(state["damaged"] as Dictionary)[str(id)] = 8
			ind["own"] = maxf(float(ind["own"]) - 8.0, 0.0)
		var r: String = str(stats.get("reason", ""))
		if r.contains("killed") or r.contains("destroyed") or r.contains("lost"):
			pilot["lost_days"] = int(pilot["lost_days"]) + 2
			log.append("Day %d: %s - FAILED, aircraft lost; pilot recovers for 2 days." % [int(state["day"]) + 1, title])
			_advance_day(rng, 2)
		else:
			log.append("Day %d: %s - FAILED." % [int(state["day"]) + 1, title])
	_advance_day(rng, 1)
	var ended: String = ""
	if float(ind["enemy"]) <= 20.0:
		ended = "victory"
	elif float(ind["own"]) <= 20.0 or int(state["day"]) >= MAX_DAYS:
		ended = "victory" if float(ind["enemy"]) < float(ind["own"]) else "defeat"
	state["ended"] = ended
	if ended != "":
		log.append("CAMPAIGN OVER: %s." % ended.to_upper())
	while log.size() > 40:
		log.pop_front()
	generate_offers()
	save_state()
	return {"rank": rank_name(), "campaign_day": int(state["day"]), "enemy_industry": "%d%%" % int(ind["enemy"]), "own_industry": "%d%%" % int(ind["own"]),
		"campaign": ended.to_upper() if ended != "" else "continues"}


static func _advance_day(rng: RandomNumberGenerator, days: int) -> void:
	var log: Array = state["log"]
	for i in days:
		state["day"] = int(state["day"]) + 1
		var unix: int = Time.get_unix_time_from_datetime_string(str(state["date"]) + "T00:00:00") + 86400
		state["date"] = Time.get_date_string_from_unix_time(unix)
		var dmg: Dictionary = state["damaged"]
		for k in dmg.keys():
			dmg[k] = int(dmg[k]) - 1
			if int(dmg[k]) <= 0:
				dmg.erase(k)
		var st: Dictionary = state["strength"]
		var ind: Dictionary = state["industry"]
		st["own"] = clampf(float(st["own"]) + float(ind["own"]) / 100.0 * 3.0 - 1.5, 10.0, 100.0)
		st["enemy"] = clampf(float(st["enemy"]) + float(ind["enemy"]) / 100.0 * 3.0 - 1.5, 5.0, 100.0)
		# the enemy hits back in proportion to its remaining air strength
		if rng.randf() < 0.55 * float(st["enemy"]) / 100.0:
			var own: Array = _pool(str(state["side"]), STRIKE_TYPES)
			if not own.is_empty():
				var t: Dictionary = own[rng.randi() % own.size()]
				dmg[str(t["id"])] = 5
				ind["own"] = maxf(float(ind["own"]) - 3.0, 0.0)
				log.append("%s: enemy bombers hit %s." % [str(state["date"]), str(t["name"])])
