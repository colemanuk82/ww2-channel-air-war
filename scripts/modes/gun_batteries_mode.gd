class_name GunBatteriesMode
extends BombingMode
## "Silence the guns": attack the German cross-Channel batteries (CoastalBattery, ids in GunShelling.SITES).
## The batteries start shelling Dover / Folkestone / the Strait a little after the start (GunShelling holds every
## shell in the air for its real flight time). Knock out the guns (bombs or rockets; strafing only hurts the flak
## and crews) until each battery is silenced, get out through the flak and the Bf 109s, and land back.
## Success = every listed battery silenced + back at base. Results record guns destroyed, shells fired / landed
## and whether the town was spared (at most SPARED_LIMIT shells on target before the guns were stopped).
## Runs as the inner mode of a HistoricalMissions mission with "gun_mission": true; also usable directly:
## GunBatteriesMode.create(["battery_grosser_kurfurst", "battery_friedrich_august"], "Allies").

const SPARED_LIMIT := 8
const FIRST_DELAY := 20.0

var shelling: GunShelling
var _first_delay: float = FIRST_DELAY
var _msg_cd: float = 0.0
var _landed_seen: int = 0
var _all_silenced_said: bool = false


static func create_guns(ids: Array, p_side: String = "Allies", p_difficulty: float = 0.5) -> GunBatteriesMode:
	var m := GunBatteriesMode.new()
	m.target_ids = ids.duplicate()
	m.side = p_side
	m.enemy_side = GroundKit.enemy_of(p_side)
	m.difficulty = p_difficulty
	return m


func configure(cfg: Dictionary) -> void:
	super.configure(cfg)
	if target_ids.is_empty():
		target_ids = GunShelling.site_ids()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--guns-first="):
			_first_delay = float(a.substr(13))


func start() -> void:
	shelling = GunShelling.ensure(world)
	shelling.reset_all()             # new sortie: every gun stands again (before the battery models register)
	teleport = teleport or GroundKit.has_arg("--guns-test")
	super.start()
	if _populator != null:
		shelling.populator = _populator
	var tgt: String = ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--guns-target="):
			tgt = a.substr(14)
	if tgt != "":
		shelling.force_target = tgt
	shelling.start(target_ids, _first_delay)
	shelling.shell_landed.connect(_on_shell_landed)
	shelling.battery_silenced.connect(_on_battery_silenced)
	Radio.say("Control", "%s, Control. Heavy guns on the French coast are shelling Dover. Find the batteries by their flashes and smoke and silence them." % Radio.callsign_of(player), Radio.Kind.CONTROL, 4.0)


func stop() -> void:
	super.stop()
	if shelling != null and is_instance_valid(shelling):
		if shelling.shell_landed.is_connected(_on_shell_landed):
			shelling.shell_landed.disconnect(_on_shell_landed)
		if shelling.battery_silenced.is_connected(_on_battery_silenced):
			shelling.battery_silenced.disconnect(_on_battery_silenced)
		shelling.stop()


func _update_objective() -> void:
	if phase == "ingress":
		var n: int = shelling.guns_total(target_ids) if shelling != null else 0
		objective_updated.emit("Silence the guns: %s (knock out %s)" % [_target_summary(), "three quarters of each battery" if n > 0 else "the guns"])
	else:
		super._update_objective()


func _refresh_label() -> void:
	super._refresh_label()
	if _label == null or not is_instance_valid(_label) or shelling == null:
		return
	var gt: Dictionary = gun_stats()
	_label.text += "\nGUNS DOWN %d/%d   %s   ON TOWN %d" % [gt["guns_destroyed"], gt["guns_total"], "FIRING" if shelling.any_firing() else "SILENT", gt["shells_on_town"]]


func gun_stats() -> Dictionary:
	var total: int = shelling.guns_total(target_ids)
	var alive: int = shelling.guns_alive_total(target_ids)
	var sil: int = 0
	for id in target_ids:
		if shelling.is_silenced(str(id)):
			sil += 1
	var on_town: int = int(shelling.stats.get("on_town", 0))
	return {"guns_total": total, "guns_destroyed": total - alive, "batteries_silenced": sil, "batteries": target_ids.size(),
		"shells_fired": int(shelling.stats.get("fired", 0)), "shells_landed": int(shelling.stats.get("landed", 0)),
		"shells_on_town": on_town, "town_spared": on_town <= SPARED_LIMIT}


func _stats(reason: String = "") -> Dictionary:
	var d: Dictionary = super._stats(reason)
	if shelling != null:
		d.merge(gun_stats())
		d["notes"] = _notes(d)
	return d


func _notes(d: Dictionary) -> Array:
	var out: Array = []
	out.append("Guns knocked out: %d of %d (%d of %d batteries silenced)" % [d["guns_destroyed"], d["guns_total"], d["batteries_silenced"], d["batteries"]])
	out.append("Shells fired %d, landed %d; %d fell on the town" % [d["shells_fired"], d["shells_landed"], d["shells_on_town"]])
	out.append("Dover was spared the worst of it" if bool(d["town_spared"]) else "Dover took a heavy pounding before the guns stopped")
	return out


func _on_shell_landed(_pos: Vector3, tid: String, _bid: String, wet: bool) -> void:
	_landed_seen += 1
	if _msg_cd > 0.0 or not running:
		return
	_msg_cd = 45.0
	var town: String = str((GunShelling.TARGETS.get(tid, {}) as Dictionary).get("name", "the coast"))
	var line: String = "Shell burst in the water off %s." % town if wet else "Shells falling on %s." % town
	Radio.say("Coastguard Dover", line, Radio.Kind.CONTROL, 0.5)


func _on_battery_silenced(id: String) -> void:
	if not running:
		return
	add_score(400)
	var nm: String = str((GunShelling.SITES.get(id, {}) as Dictionary).get("name", id))
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "BATTERY SILENCED: %s" % nm, 3.5)
	Radio.say("Control", "%s, Control. Guns at %s have stopped firing." % [Radio.callsign_of(player), nm], Radio.Kind.CONTROL, 1.0)


func _process(delta: float) -> void:
	super._process(delta)
	_msg_cd = maxf(_msg_cd - delta, 0.0)
	if running and shelling != null and not _all_silenced_said and not shelling.any_firing() and shelling.t > _first_delay + 5.0:
		_all_silenced_said = true
		Radio.say("Coastguard Dover", "The guns have stopped. Dover reports no more shells.", Radio.Kind.CONTROL, 2.0)
