class_name GunShelling
extends Node
## The cross-Channel bombardment: German long-range batteries on the Pas-de-Calais coast (Cap Gris-Nez, Wimereux,
## the railway guns near Calais) shelling Dover, Folkestone and the Strait at 30-45 km.
##
## This node is the *simulation*; it lives under the world and keeps working whether or not a battery's models are
## streamed in (CoastalBattery registers its guns when built and shows the firing). Per battery it keeps the live
## state of every gun, fires them on a cycle, and holds every shell in the air for its real flight time
## (range / MEAN_SPEED, about 80 s at 34 km) before it lands: explosion in a town, water plume at sea, damage to
## whatever is there, wreckage through BattleDamage (guarded: it may not exist). Guns knocked out stay out; once
## three quarters of a battery is gone its crews abandon it (silenced) and it stops firing.
## Drive it with start()/stop(); tests call step(dt) directly.

signal gun_fired(battery_id: String, gun_index: int, aim: Vector3, flight_s: float)
signal shell_landed(pos: Vector3, target_id: String, battery_id: String, on_water: bool)
signal battery_silenced(battery_id: String)
signal bombardment_started(battery_ids: Array)

const MEAN_SPEED := 430.0          # m/s averaged over the arc: 34 km is about 80 s in the air
const MIN_FLIGHT := 20.0
const SILENCE_FRAC := 0.75
const DISPERSION := 90.0           # metres, one sigma, with the fire-control post standing
const CYCLE := {"casemate": 62.0, "railway": 150.0}   # seconds between rounds from one gun
const MAX_RANGE := {"casemate": 55000.0, "railway": 62000.0}
const Tempo := preload("res://scripts/modes/activity_tempo.gd")     # lulls hold back the ambient shelling; Busy / Quiet scale the gap
const AMBIENT_FIRST := 150.0
const AMBIENT_LENGTH := 1200.0
const AMBIENT_GAP := 1500.0

## Battery sites (real places on the Pas-de-Calais coast; the positions are plausible, not surveyed).
const SITES := {
	"battery_grosser_kurfurst": {"name": "Batterie Grosser Kurfuerst (Cap Gris-Nez)", "lat": 50.862, "lon": 1.612, "kind": "casemate", "guns": 4,
		"targets": ["dover_town", "dover_harbour", "dover_docks", "strait_convoy"]},
	"battery_friedrich_august": {"name": "Batterie Friedrich August (Wimereux)", "lat": 50.790, "lon": 1.620, "kind": "casemate", "guns": 3,
		"targets": ["dover_harbour", "dover_town", "strait_convoy"]},
	"battery_k5_coquelles": {"name": "K5 railway guns (Coquelles, Calais)", "lat": 50.929, "lon": 1.806, "kind": "railway", "guns": 2,
		"targets": ["folkestone_town", "folkestone_harbour", "dover_docks", "strait_convoy"]},
}

const TARGETS := {
	"dover_town": {"name": "Dover", "lat": 51.1279, "lon": 1.3134, "kind": "town"},
	"dover_harbour": {"name": "Dover harbour", "lat": 51.1215, "lon": 1.3225, "kind": "town"},
	"dover_docks": {"name": "Dover seafront", "lat": 51.1255, "lon": 1.3165, "kind": "town"},
	"folkestone_town": {"name": "Folkestone", "lat": 51.0814, "lon": 1.1850, "kind": "town"},
	"folkestone_harbour": {"name": "Folkestone harbour", "lat": 51.0775, "lon": 1.1945, "kind": "town"},
	"strait_convoy": {"name": "a convoy in the Strait", "lat": 51.0150, "lon": 1.4300, "kind": "sea"},
}

static var _inst: GunShelling = null
static var LOG: bool = OS.get_cmdline_user_args().has("--guns-log")

var active: bool = false
var t: float = 0.0
var time_scale: float = 1.0
var end_t: float = -1.0                 # sim time when an ambient bombardment ends (< 0: runs until stopped)
var force_target: String = ""           # debug / tests: every battery shoots at this target id
var dispersion_override: float = -1.0   # debug: fixed dispersion in metres (0 = dead on)
var stats: Dictionary = {}
var town_hits: Dictionary = {}          # target id -> shells that landed within 700 m of it on land or in the harbour

var _bat: Dictionary = {}
var _shells: Array = []
var _rng := RandomNumberGenerator.new()
var _vis: Array = []
var _ambient: bool = false
var _amb_t: float = 0.0
var _amb_gap: float = 0.0
var _amb_player: Node3D = null
var _amb_hud: Node = null
var _support_hud: Node = null           # the HUD holding the minimap "support requested" rings (see mark_support)


static func instance() -> GunShelling:
	return _inst if _inst != null and is_instance_valid(_inst) else null


static func ensure(parent: Node) -> GunShelling:
	var i: GunShelling = instance()
	if i != null:
		return i
	i = GunShelling.new()
	i.name = "GunShelling"
	_inst = i
	if parent != null and parent.is_inside_tree():
		parent.add_child(i)
	elif parent != null:
		parent.add_child(i)
	i.reset_stats()
	return i


static func site_ids() -> Array:
	return SITES.keys()


static func site_pos(id: String) -> Vector3:
	var s: Dictionary = SITES[id]
	var p: Vector3 = WorldCoords.latlon_to_world(float(s["lat"]), float(s["lon"]))
	p.y = GroundKit.ground_y(p.x, p.z)
	return p


static func target_pos(tid: String) -> Vector3:
	var s: Dictionary = TARGETS[tid]
	var p: Vector3 = WorldCoords.latlon_to_world(float(s["lat"]), float(s["lon"]))
	p.y = GroundKit.ground_y(p.x, p.z)
	return p


static func flight_time(range_m: float) -> float:
	return maxf(range_m / MEAN_SPEED, MIN_FLIGHT)


## Battery is silenced once this many of its guns are gone.
static func silence_at(n: int) -> int:
	return maxi(1, int(floor(float(n) * SILENCE_FRAC + 0.5)))


func _ready() -> void:
	_rng.seed = 1940
	_inst = self
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--guns-timescale="):
			time_scale = float(a.substr(17))


func _exit_tree() -> void:
	if _inst == self:
		_inst = null


func reset_stats() -> void:
	stats = {"fired": 0, "landed": 0, "on_town": 0, "on_sea": 0, "first_impact_s": -1.0, "guns_destroyed": 0}
	town_hits = {}


## Back to all guns standing (new mission / new test).
func reset_all() -> void:
	_bat.clear()
	_shells.clear()
	reset_stats()
	active = false
	t = 0.0
	end_t = -1.0
	force_target = ""


func _log(msg: String) -> void:
	if LOG:
		print("[guns] t=%.1f %s" % [t, msg])


# ------------------------------------------------------------------ battery records
func rec(id: String) -> Dictionary:
	if _bat.has(id):
		return _bat[id]
	if not SITES.has(id):
		return {}
	var s: Dictionary = SITES[id]
	var n: int = int(s["guns"])
	var alive: Array = []
	var nxt: Array = []
	for i in n:
		alive.append(true)
		nxt.append(1.0e9)
	var r: Dictionary = {"id": id, "pos": site_pos(id), "kind": str(s["kind"]), "n": n, "alive": alive, "next": nxt, "node": null,
		"silenced": false, "fc_alive": true, "targets": (s["targets"] as Array).duplicate(), "tgt_i": 0, "cur": "", "retarget": 0.0, "wait": []}
	for i in n:
		(r["wait"] as Array).append(0.0)
	_bat[id] = r
	return r


func register_node(id: String, node: Node) -> void:
	var r: Dictionary = rec(id)
	if not r.is_empty():
		r["node"] = node


func unregister_node(id: String, node: Node) -> void:
	if _bat.has(id) and _bat[id]["node"] == node:
		_bat[id]["node"] = null


func gun_alive(id: String, i: int) -> bool:
	var r: Dictionary = rec(id)
	return not r.is_empty() and i >= 0 and i < int(r["n"]) and bool((r["alive"] as Array)[i])


func alive_count(id: String) -> int:
	var r: Dictionary = rec(id)
	if r.is_empty():
		return 0
	var c: int = 0
	for a in (r["alive"] as Array):
		if bool(a):
			c += 1
	return c


func total_count(id: String) -> int:
	var r: Dictionary = rec(id)
	return int(r["n"]) if not r.is_empty() else 0


func is_silenced(id: String) -> bool:
	var r: Dictionary = rec(id)
	return not r.is_empty() and bool(r["silenced"])


func fc_alive(id: String) -> bool:
	var r: Dictionary = rec(id)
	return r.is_empty() or bool(r["fc_alive"])


func guns_alive_total(ids: Array = []) -> int:
	var c: int = 0
	for id in (ids if not ids.is_empty() else SITES.keys()):
		c += alive_count(str(id))
	return c


func guns_total(ids: Array = []) -> int:
	var c: int = 0
	for id in (ids if not ids.is_empty() else SITES.keys()):
		c += total_count(str(id))
	return c


func shells_in_flight() -> int:
	return _shells.size()


func in_flight_info() -> Array:
	return _shells.duplicate()


func on_gun_destroyed(id: String, i: int) -> void:
	var r: Dictionary = rec(id)
	if r.is_empty() or i < 0 or i >= int(r["n"]) or not bool((r["alive"] as Array)[i]):
		return
	(r["alive"] as Array)[i] = false
	(r["next"] as Array)[i] = 1.0e9
	stats["guns_destroyed"] = int(stats.get("guns_destroyed", 0)) + 1
	var gone: int = int(r["n"]) - alive_count(id)
	_log("gun %s #%d destroyed (%d/%d)" % [id, i, gone, int(r["n"])])
	if not bool(r["silenced"]) and gone >= silence_at(int(r["n"])):
		r["silenced"] = true
		_log("battery %s silenced" % id)
		unmark_support(id)
		battery_silenced.emit(id)
		var pop: Node = _populator()
		if pop != null and pop.get("_destroyed") is Dictionary:
			(pop.get("_destroyed") as Dictionary)[id] = true


func kill_gun(id: String, i: int) -> void:
	## Direct kill (tests / debug): through the gun node when it is built, else just the state.
	var r: Dictionary = rec(id)
	if r.is_empty():
		return
	var node: Variant = r["node"]
	if node != null and is_instance_valid(node) and node.has_method("kill_gun"):
		node.call("kill_gun", i)
	else:
		on_gun_destroyed(id, i)


func on_tower_destroyed(id: String) -> void:
	var r: Dictionary = rec(id)
	if not r.is_empty():
		r["fc_alive"] = false
		_log("fire-control post of %s destroyed: fire gets wild" % id)


var populator: Node = null          # the WorldPopulator (its _destroyed dictionary remembers silenced batteries)


func _populator() -> Node:
	return populator if populator != null and is_instance_valid(populator) else null


# ------------------------------------------------------------------ control
## Begin shelling. ids = battery ids (empty: all sites). first_delay = seconds until the first round.
func start(ids: Array = [], first_delay: float = 20.0, length: float = -1.0) -> void:
	var use: Array = ids if not ids.is_empty() else SITES.keys()
	var good: Array = []
	for id in use:
		var r: Dictionary = rec(str(id))
		if r.is_empty() or bool(r["silenced"]):
			continue
		good.append(str(id))
		var stagger: float = 9.0 if str(r["kind"]) == "casemate" else 35.0
		for i in int(r["n"]):
			if bool((r["alive"] as Array)[i]) and float((r["next"] as Array)[i]) > 1.0e8:
				(r["next"] as Array)[i] = first_delay + float(i) * stagger + _rng.randf_range(0.0, 6.0)
	if good.is_empty():
		return
	if not active:
		active = true
		end_t = t + length if length > 0.0 else -1.0
		reset_run_flag()
		_log("bombardment starts: %s" % str(good))
		bombardment_started.emit(good)


func reset_run_flag() -> void:
	stats["first_impact_s"] = -1.0
	stats["started_t"] = t


func stop() -> void:
	active = false
	unmark_all_support()
	for id in _bat:
		var r: Dictionary = _bat[id]
		for i in int(r["n"]):
			(r["next"] as Array)[i] = 1.0e9
	_log("bombardment stopped")


func any_firing() -> bool:
	if not active:
		return false
	for id in _bat:
		var r: Dictionary = _bat[id]
		if bool(r["silenced"]):
			continue
		for i in int(r["n"]):
			if bool((r["alive"] as Array)[i]) and float((r["next"] as Array)[i]) < 1.0e8:     # a gun that is on the firing list
				return true
	return false


# ------------------------------------------------------------------ simulation
func _current_target(r: Dictionary) -> String:
	if force_target != "" and TARGETS.has(force_target):
		return force_target
	if t >= float(r["retarget"]) or str(r["cur"]) == "":
		var list: Array = r["targets"]
		r["cur"] = str(list[int(r["tgt_i"]) % list.size()])
		r["tgt_i"] = int(r["tgt_i"]) + 1
		r["retarget"] = t + 330.0
		# stay inside the gun's range
		var guard: int = 0
		while Vector2(site_pos(str(r["id"])).x - target_pos(str(r["cur"])).x, site_pos(str(r["id"])).z - target_pos(str(r["cur"])).z).length() > float(MAX_RANGE[str(r["kind"])]) and guard < 6:
			r["cur"] = str(list[int(r["tgt_i"]) % list.size()])
			r["tgt_i"] = int(r["tgt_i"]) + 1
			guard += 1
	return str(r["cur"])


func step(dt: float) -> void:
	t += dt
	if active:
		if end_t > 0.0 and t >= end_t:
			stop()
		else:
			for id in _bat:
				var r: Dictionary = _bat[id]
				if bool(r["silenced"]):
					continue
				var tid: String = _current_target(r)
				var aim: Vector3 = target_pos(tid)
				for i in int(r["n"]):
					if not bool((r["alive"] as Array)[i]):
						continue
					var nx: float = float((r["next"] as Array)[i]) - dt
					(r["next"] as Array)[i] = nx
					var gun: Variant = _gun_node(r, i)
					if gun != null and nx < 40.0:
						gun.call("set_aim", aim)
					if nx <= 0.0:
						if gun != null and not bool(gun.call("is_laid", 6.0)) and float((r["wait"] as Array)[i]) < 25.0:
							(r["wait"] as Array)[i] = float((r["wait"] as Array)[i]) + dt     # still laying: wait for the barrel
							continue
						(r["wait"] as Array)[i] = 0.0
						_fire(r, i, tid)
	var k: int = _shells.size() - 1
	while k >= 0:
		var s: Dictionary = _shells[k]
		if t >= float(s["t_land"]):
			_shells.remove_at(k)
			_land(s)
		k -= 1


func _gun_node(r: Dictionary, i: int) -> Variant:
	var node: Variant = r["node"]
	if node != null and is_instance_valid(node) and node.has_method("gun_at"):
		var g: Variant = node.call("gun_at", i)
		if g != null and is_instance_valid(g):
			return g
	return null


func _fire(r: Dictionary, i: int, tid: String) -> void:
	var id: String = str(r["id"])
	var cyc: float = float(CYCLE[str(r["kind"])])
	(r["next"] as Array)[i] = cyc * _rng.randf_range(0.88, 1.12)
	var from: Vector3 = r["pos"]
	var aim: Vector3 = target_pos(tid)
	var sigma: float = dispersion_override if dispersion_override >= 0.0 else DISPERSION * (1.0 if bool(r["fc_alive"]) else 2.6)
	var off := Vector3(_rng.randfn(0.0, sigma), 0.0, _rng.randfn(0.0, sigma))
	var to: Vector3 = aim + off
	var rng_m: float = Vector2(to.x - from.x, to.z - from.z).length()
	var fl: float = flight_time(rng_m)
	var shell: Dictionary = {"from": from, "to": to, "t_fire": t, "t_land": t + fl, "flight": fl, "bid": id, "tid": tid, "range": rng_m, "whistled": false}
	_shells.append(shell)
	stats["fired"] = int(stats.get("fired", 0)) + 1
	var gun: Variant = _gun_node(r, i)
	if gun != null:
		gun.call("fire_visual")
	else:
		_far_visual(r)
	_log("%s gun %d fires at %s range %.1f km flight %.0f s" % [id, i, tid, rng_m / 1000.0, fl])
	gun_fired.emit(id, i, to, fl)


## A battery whose models are not streamed in (the player is far off): a flash, a smoke column and a long glow
## where it stands, so the guns still show from many kilometres by their muzzle flashes and smoke.
func _far_visual(r: Dictionary) -> void:
	var pl: Node3D = GroundKit.player_node()
	var fx: Node = GroundKit.fx_node()
	if pl == null or fx == null or not is_inside_tree():
		return
	var p: Vector3 = (r["pos"] as Vector3) + Vector3(_rng.randf_range(-70, 70), 8.0, _rng.randf_range(-40, 40))
	var d: float = pl.global_position.distance_to(p)
	if d > 80000.0:
		return
	fx.call("explosion", p, 6.4, true)
	fx.call("smoke_column", p, 5.0, 30.0)
	CoastalGun.distant_flash(get_tree(), p, d)
	fx.call("sfx", "thunder", p, -6.0, 0.5)


func _land(s: Dictionary) -> void:
	var p: Vector3 = s["to"]
	var wet: bool = GroundKit.is_water(p.x, p.z)
	p.y = 0.0 if wet else GroundKit.ground_y(p.x, p.z)
	var tid: String = str(s["tid"])
	stats["landed"] = int(stats.get("landed", 0)) + 1
	if float(stats.get("first_impact_s", -1.0)) < 0.0:
		stats["first_impact_s"] = t - float(stats.get("started_t", 0.0))
	var kind: String = str((TARGETS[tid] as Dictionary)["kind"]) if TARGETS.has(tid) else "sea"
	if kind == "town":
		var tp: Vector3 = target_pos(tid)
		if Vector2(p.x - tp.x, p.z - tp.z).length() < 700.0:
			stats["on_town"] = int(stats.get("on_town", 0)) + 1
			town_hits[tid] = int(town_hits.get(tid, 0)) + 1
	if wet:
		stats["on_sea"] = int(stats.get("on_sea", 0)) + 1
	_log("shell from %s lands at %s (%s) after %.0f s" % [str(s["bid"]), str(p), "water" if wet else "land", float(s["flight"])])
	_impact_fx(p, wet, kind == "town")
	shell_landed.emit(p, tid, str(s["bid"]), wet)


func _impact_fx(p: Vector3, wet: bool, in_town: bool) -> void:
	if not is_inside_tree():
		return
	if not wet:
		_damage_near(p, 48.0)
		var bd: Node = get_tree().root.get_node_or_null("BattleDamage")     # may not exist yet: stay guarded
		if bd != null:
			if bd.has_method("ruin_area"):
				bd.call("ruin_area", p, 30.0, 1.0, absi(hash(str(snappedf(p.x, 1.0)) + str(snappedf(p.z, 1.0)))) % 100000)
			if bd.has_method("crater"):
				bd.call("crater", p, 11.0)
	var fx: Node = GroundKit.fx_node()
	if fx == null:
		return
	if wet:
		fx.call("water_plume", Vector3(p.x, 0.0, p.z), 22.0)        # a 38 cm shell: a column well over a hundred feet high
		fx.call("water_splash", Vector3(p.x, 0.0, p.z), 12.0)
	else:
		fx.call("explosion", p + Vector3(0, 3, 0), 17.0, true)
		fx.call("crater", p, 10.0)
		fx.call("dust", p, 10.0)
		fx.call("debris", p + Vector3(0, 2, 0), 12, 1.8, 45.0, Color(0.3, 0.28, 0.24))
		fx.call("smoke_column", p, 9.0, 45.0)
		if in_town:
			CityFires.ignite(p, 0.9)
	fx.call("sfx", "explosion", p, 8.0, 0.0)


func _damage_near(p: Vector3, radius: float) -> void:
	for n in get_tree().get_nodes_in_group("damageable"):
		if n is Aircraft or not (n is Node3D) or not n.has_method("take_damage"):
			continue
		var hr: Variant = n.get("hit_radius")
		var d: float = Vector2((n as Node3D).global_position.x - p.x, (n as Node3D).global_position.z - p.z).length()
		var reach: float = radius + (float(hr) if hr != null else 3.0)
		if d < reach:
			n.call("take_damage", 700.0 * (1.0 - d / reach) + 60.0, self)


# ------------------------------------------------------------------ frame work: shells in the air, ambient event
func _process(delta: float) -> void:
	if active or not _shells.is_empty():
		step(delta * time_scale)
		_shell_visuals()
	if _ambient:
		_ambient_tick(delta)


## A shell in flight within a few kilometres of the player is drawn as a dark streak, and its whistle is heard.
func _shell_visuals() -> void:
	var pl: Node3D = GroundKit.player_node()
	if pl == null or not is_inside_tree():
		for v in _vis:
			(v as Node3D).visible = false
		return
	var used: int = 0
	for s in _shells:
		var u: float = clampf((t - float(s["t_fire"])) / float(s["flight"]), 0.0, 1.0)
		var a: Vector3 = s["from"]
		var b: Vector3 = s["to"]
		var apex: float = float(s["range"]) * 0.33
		var pos: Vector3 = a.lerp(b, u)
		pos.y = lerpf(a.y, b.y, u) + apex * 4.0 * u * (1.0 - u)
		var u2: float = minf(u + 0.004, 1.0)
		var nxt: Vector3 = a.lerp(b, u2)
		nxt.y = lerpf(a.y, b.y, u2) + apex * 4.0 * u2 * (1.0 - u2)
		var d: float = pl.global_position.distance_to(pos)
		if not bool(s["whistled"]) and t > float(s["t_land"]) - 3.0 and pl.global_position.distance_to(b) < 4500.0:
			s["whistled"] = true
			var fx: Node = GroundKit.fx_node()
			if fx != null:
				fx.call("sfx", "bomb_whistle", b, 8.0, 0.0)
		if d > 6000.0 or used >= 6:
			continue
		var m: Node3D = _vis_node(used)
		used += 1
		m.visible = true
		m.global_position = pos
		var dir: Vector3 = (nxt - pos)
		if dir.length() > 0.001:
			m.look_at(pos + dir, Vector3.UP)
		m.scale = Vector3.ONE * clampf(d * 0.004, 1.0, 14.0)      # a thin streak that stays visible at range
	for k in range(used, _vis.size()):
		(_vis[k] as Node3D).visible = false


func _vis_node(i: int) -> Node3D:
	while _vis.size() <= i:
		var m := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.18
		cm.height = 3.0
		cm.radial_segments = 6
		cm.rings = 1
		m.mesh = cm
		m.rotation_degrees = Vector3(90, 0, 0)
		var holder := Node3D.new()
		holder.add_child(m)
		m.material_override = GroundKit.glow_mat(Color(0.95, 0.55, 0.25), 0.9, true)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.extra_cull_margin = 500.0
		add_child(holder)
		holder.visible = false
		_vis.append(holder)
	return _vis[i]


# ------------------------------------------------------------------ ambient event (free flight)
func enable_ambient(player: Node3D, hud: Node, first_delay: float = AMBIENT_FIRST) -> void:
	_ambient = true
	_amb_player = player
	_amb_hud = hud
	_amb_t = first_delay
	_amb_gap = 0.0


func disable_ambient() -> void:
	_ambient = false


static func era_ok() -> bool:
	var d: String = str(GameState.era_date)
	if d == "":
		return true
	return d >= "1940-08-12" and d <= "1944-09-06"


func _ambient_tick(delta: float) -> void:
	if active:
		return
	_amb_t -= delta
	if _amb_t > 0.0:
		return
	if Tempo.lulling:
		_amb_t = 20.0             # a lull in the air war (activity_tempo.gd): the guns stay quiet until it is over
		return
	if _amb_player == null or not is_instance_valid(_amb_player) or not era_ok():
		_amb_t = 30.0
		return
	var dover: Vector3 = target_pos("dover_town")
	if Vector2(_amb_player.global_position.x - dover.x, _amb_player.global_position.z - dover.z).length() > 90000.0:
		_amb_t = 30.0
		return
	_begin_ambient()


func _begin_ambient() -> void:
	for id in SITES.keys():
		var r: Dictionary = rec(str(id))
		if not r.is_empty() and not bool(r["silenced"]):
			for i in int(r["n"]):
				(r["next"] as Array)[i] = 1.0e9
	start([], 25.0, AMBIENT_LENGTH)
	_amb_t = AMBIENT_LENGTH + AMBIENT_GAP * Tempo.event_scale()
	var line: String = "Dover under shellfire from Gris-Nez. Any aircraft: attack the batteries on the French coast."
	var gcl: Array = Radio.pick_line("support_guns")      # a recorded call: Allies keep the text above, Axis get their own wording
	var gsender: String = "Coastguard Dover"
	if not gcl.is_empty() and Radio.side_name() == "Axis":
		line = String(gcl[1])
		gsender = String(gcl[0])
	Radio.say(gsender, line, Radio.Kind.CONTROL, 1.0, String(gcl[2]) if not gcl.is_empty() else "")
	mark_support(_amb_hud)
	if _amb_hud != null and is_instance_valid(_amb_hud) and _amb_hud.has_method("show_message"):
		_amb_hud.call("show_message", "Dover shelled from Cap Gris-Nez - attack the batteries", 5.0)


## Minimap "ground support requested" ring on each battery still firing (same style as the land battles). Each
## ring goes when its battery is silenced, or when the bombardment stops.
func mark_support(hud: Node) -> void:
	if hud == null or not is_instance_valid(hud) or not hud.has_method("register_support_marker"):
		return
	_support_hud = hud
	for id in SITES.keys():
		var r: Dictionary = rec(str(id))
		if r.is_empty() or bool(r["silenced"]) or get_node_or_null(_support_key(str(id))) != null:
			continue
		var a := Node3D.new()
		a.name = _support_key(str(id))
		add_child(a)
		a.global_position = r["pos"]
		hud.call("register_support_marker", a)


func unmark_support(id: String) -> void:
	var a: Node = get_node_or_null(_support_key(id))
	if a == null:
		return
	if _support_hud != null and is_instance_valid(_support_hud) and _support_hud.has_method("unregister_support_marker"):
		_support_hud.call("unregister_support_marker", a)
	a.queue_free()


func unmark_all_support() -> void:
	for id in SITES.keys():
		unmark_support(str(id))


static func _support_key(id: String) -> String:
	return "SupportMark_" + id


## Nearest live (not silenced) battery to a world position, or "".
func nearest_battery(pos: Vector3) -> String:
	var best: String = ""
	var bd: float = INF
	for id in SITES.keys():
		var r: Dictionary = rec(str(id))
		if r.is_empty() or bool(r["silenced"]):
			continue
		var d: float = Vector2(pos.x - (r["pos"] as Vector3).x, pos.z - (r["pos"] as Vector3).z).length()
		if d < bd:
			bd = d
			best = str(id)
	return best
