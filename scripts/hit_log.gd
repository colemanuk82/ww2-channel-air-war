class_name HitLog
extends RefCounted
## Debug log of every hit on the player's aircraft: what fired, its team and whether that is a FRIEND or FOE of the
## player, how far away it was, and the damage. Each hit prints a "[hit]" line to the game log; when the player is
## shot down a "[shot down]" summary (damage per shooter, friendly total) goes to the log and the black box.
##
## Sources: anything that passes itself to take_damage() (aircraft guns, ships, balloons) is named directly. Shooters
## that cannot pass a node without changing kill credit (flak shells and searchlight-directed 88s, which call
## take_damage with no source) announce themselves first through HitLog.shooter(), read by the very next hit.

static var _pending: Node = null
static var _pending_kind: String = ""
static var _tally: Dictionary = {}       # label -> {dmg, hits, friendly}
static var _friendly_total: float = 0.0
static var _total: float = 0.0


## Call just before take_damage(..., null) so the hit can still be attributed (kind: "flak 88mm", "tracer mg", ...).
static func shooter(node: Node, kind: String) -> void:
	_pending = node
	_pending_kind = kind


## Aircraft.take_damage on the player: describe and record one hit.
static func on_player_hit(victim: Aircraft, amount: float, source: Node) -> void:
	var src: Node = source
	var kind: String = ""
	if src == null and _pending != null and is_instance_valid(_pending):
		src = _pending
		kind = _pending_kind
	_pending = null
	_pending_kind = ""
	var label: String = _label(src, kind)
	var team: String = _team_of(src)
	var rel: String = "UNKNOWN"
	if team != "":
		rel = "FRIENDLY" if team == victim.team else ("NEUTRAL" if team == "Neutral" else "FOE")
	var dist: String = ""
	if src is Node3D and is_instance_valid(src):
		dist = " at %.0f m" % (src as Node3D).global_position.distance_to(victim.global_position)
	var key: String = "%s [%s %s]" % [label, team if team != "" else "?", rel]
	var e: Dictionary = _tally.get(key, {"dmg": 0.0, "hits": 0})
	e["dmg"] = float(e["dmg"]) + amount
	e["hits"] = int(e["hits"]) + 1
	_tally[key] = e
	_total += amount
	if rel == "FRIENDLY":
		_friendly_total += amount
	var line: String = "[hit] %.1f dmg (health %.0f/%.0f) from %s, team %s -> %s%s" % [
		amount, maxf(victim.health, 0.0), victim.stats.max_health, label, team if team != "" else "?", rel, dist]
	if src == null:
		line += " | " + _caller()
	print(line)
	if rel == "FRIENDLY":
		BlackBox.note(line)       # friendly fire is always worth a breadcrumb


## The player went down: summary of who did the damage this life, then start a fresh tally.
static func on_player_down(victim: Aircraft, killer: Node) -> void:
	var lines: Array = []
	lines.append("[shot down] %s (%s) - final blow: %s, team %s. Damage this life %.0f, of it FRIENDLY %.0f" % [
		victim.stats.display_name if "display_name" in victim.stats else "player", victim.team,
		_label(killer, ""), _team_of(killer) if _team_of(killer) != "" else "?", _total, _friendly_total])
	var keys: Array = _tally.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return float(_tally[a]["dmg"]) > float(_tally[b]["dmg"]))
	for k in keys:
		lines.append("    %6.1f dmg in %3d hits  %s" % [float(_tally[k]["dmg"]), int(_tally[k]["hits"]), k])
	for l in lines:
		print(l)
		BlackBox.note(l)
	reset()


static func reset() -> void:
	_tally.clear()
	_friendly_total = 0.0
	_total = 0.0
	_pending = null
	_pending_kind = ""


static func _label(n: Node, kind: String) -> String:
	if n == null or not is_instance_valid(n):
		return "no source (collision / crash / environment?)" if kind == "" else kind
	var what: String = ""
	if true:
		if n is Aircraft:
			var st: Variant = (n as Aircraft).stats
			what = "aircraft " + (str(st.get("display_name")) if st != null and "display_name" in st else str(n.name))
			if (n as Aircraft).player_controlled:
				what += " (you)"
		elif n is AAGun:
			what = "AA gun " + str(n.get("gtype"))
		elif n is GroundShip:
			what = "ship " + str(n.get("stype"))
		elif n is BarrageBalloon:
			what = "barrage balloon"
		elif n is Searchlight:
			what = "searchlight battery"
		else:
			what = n.get_class()
	if kind != "":
		what = "%s from %s" % [kind, what]
	var ll: Vector2 = WorldCoords.world_to_latlon((n as Node3D).global_position) if n is Node3D else Vector2.ZERO
	return "%s \"%s\" @ %.3f,%.3f" % [what, n.name, ll.x, ll.y] if n is Node3D else "%s \"%s\"" % [what, n.name]


static func _team_of(n: Node) -> String:
	if n == null or not is_instance_valid(n) or not ("team" in n):
		return ""
	return str(n.get("team"))


## Where an unattributed hit came from (debug builds give a script backtrace; release builds give none).
static func _caller() -> String:
	var out: Array = []
	for f in get_stack():
		var d: Dictionary = f
		out.append("%s:%d %s" % [str(d.get("source", "")).get_file(), int(d.get("line", 0)), str(d.get("function", ""))])
	return "caller: " + (" <- ".join(out.slice(2, 7)) if out.size() > 2 else "n/a (release build)")
