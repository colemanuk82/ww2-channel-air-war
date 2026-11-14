extends Node
## Debug scenario runner: a headless, terrain-less taxi simulation that writes a compact JSON state log.
##   godot --headless --fixed-fps 60 --path . scenes/dbg.tscn -- --style=raf_bomber --wingmen=3 --secs=150 --out=build/dbg/run.json
## Builds ONE Airfield (any style), parks real Aircraft on its dispersals and steps the real TaxiController
## exactly as ModeBase / Main do (the wingman scheduling below mirrors ModeBase._taxi_wingmen_tick - keep in sync).
## All coordinates in the log are in the airfield's LOCAL frame: x right, z along the runway, take-off toward -Z;
## yaw is degrees clockwise from the take-off direction.
## Args: --style= --wingmen= --secs= --out= --heading= --aircraft= --hz= --spot= (player dispersal index, default
## the field's keep_clear_i) --player-hold (the player holds short until --release-after seconds) --props=0/1

var _a: Dictionary = {}
var _af: Airfield = null
var _inv: Transform3D
var _agents: Array = []       # [{"id","role","ac","ctrl","spot","route","done","t_done"}]
var _frames: Array = []
var _events: Array = []
var _t: float = 0.0
var _tick: int = 0
var _secs: float = 150.0
var _hz: float = 10.0
var _want: int = 0
var _scan: int = 0
var _spawned: int = 0
var _player_spot: Vector3 = Vector3.INF
var _stopped_after: float = -1.0
var _aircraft_id: String = "spitfire"
var _hold_player: bool = false
var _release_after: float = 20.0
var _finished: bool = false


class DbgTerrain:
	extends Node
	func get_terrain_y(_x: float, _z: float) -> float:
		return 0.0
	func get_height_at(_pos: Vector3) -> float:
		return 0.0
	func is_water_at(_pos: Vector3) -> bool:
		return false


func _ready() -> void:
	for s in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(s).trim_prefix("--").split("=", true, 1)
		_a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var t := DbgTerrain.new()
	t.name = "DbgTerrain"
	add_child(t)
	t.add_to_group("terrain")
	_secs = float(_a.get("secs", 150.0))
	_hz = float(_a.get("hz", 10.0))
	_want = clampi(int(_a.get("wingmen", 2)), 0, 7)
	_aircraft_id = String(_a.get("aircraft", "spitfire"))
	_hold_player = _a.has("player-hold")
	_release_after = float(_a.get("release-after", 20.0))
	_af = Airfield.create(String(_a.get("name", "Dbg " + String(_a.get("style", "triangle")))), Vector3.ZERO, float(_a.get("heading", 90.0)), 0.0)
	_af.style = String(_a.get("style", "triangle"))
	add_child(_af)
	_af.build_layout()
	_inv = _af.global_transform.affine_inverse()
	var spots: Array = _af._dispersal_local
	if spots.is_empty():
		_finish("no dispersal spots on this style")
		return
	var pk: int = int(_a.get("spot", _af.keep_clear_i if _af.keep_clear_i >= 0 else 0)) % spots.size()
	var route: PackedVector3Array = _af.taxi_route(spots[pk])
	if route.size() < 3:
		_finish("no taxi route from dispersal %d" % pk)
		return
	_player_spot = _af.global_transform * (spots[pk] as Vector3)
	_spawn("player", pk, route)
	(_agents[0]["ctrl"] as TaxiController).cleared = not _hold_player
	_log_event("start", "player taxis from dispersal %d, %d legs" % [pk, route.size()])


func _spawn(role: String, k: int, route: PackedVector3Array) -> void:
	var spots: Array = _af._dispersal_local
	var wp: Vector3 = _af.global_transform * (spots[k] as Vector3)
	var wd: Vector3 = _af.global_transform.basis * ((route[1] as Vector3) - (route[0] as Vector3))
	wd.y = 0.0
	var yaw: float = rad_to_deg(atan2(wd.x, -wd.z))
	var st: AircraftStats = AircraftCatalog.load_stats(_aircraft_id)
	var ac: Aircraft = AIFactory.spawn(self, _aircraft_id, "Allies", Vector3(wp.x, st.gear_height + 0.35, wp.z), yaw, 0.0, 0.7, AIPilot.Role.WINGMAN, null, true)
	var pilot: AIPilot = AIFactory.pilot_of(ac)
	if pilot != null:
		pilot.leader = null
		pilot.enabled = false
	ac.throttle_target = 0.0
	ac.name = role
	var world := PackedVector3Array()
	for lp in route:
		var tv: Vector3 = _af.global_transform * (lp as Vector3)
		tv.y = st.gear_height + 0.35
		world.append(tv)
	var ctrl := TaxiController.new()
	add_child(ctrl)
	ctrl.setup(ac, world, _af.heading_deg, null, true)
	if not _agents.is_empty():
		ctrl.ahead_ac = _agents[_agents.size() - 1]["ac"]
	var rl: Array = []
	for lp in route:
		rl.append([snappedf((lp as Vector3).x, 0.01), snappedf((lp as Vector3).z, 0.01)])
	var ag: Dictionary = {"id": role, "role": role, "ac": ac, "ctrl": ctrl, "spot": k, "route": rl, "done": false, "t_done": -1.0,
		"radius": ac.stats.radius, "model": _aircraft_id, "spawn_t": _t}
	var idx: int = _agents.size()
	ctrl.lined_up.connect(func() -> void: _on_lined_up(idx))
	_agents.append(ag)
	_log_event("spawn", "%s parked on dispersal %d" % [role, k])


func _on_lined_up(i: int) -> void:
	_agents[i]["done"] = true
	_agents[i]["t_done"] = _t
	_log_event("lined_up", "%s lined up" % _agents[i]["id"])
	if i + 1 < _agents.size():
		(_agents[i + 1]["ctrl"] as TaxiController).cleared = true


## Mirrors ModeBase._taxi_wingmen_tick: one wingman per tick, on the dispersals after the reserved one.
func _wingmen_tick() -> void:
	if _spawned >= _want:
		return
	var spots: Array = _af._dispersal_local
	var n: int = spots.size()
	for _try in 6:
		if _spawned >= _want or _scan >= n:
			return
		var ki: int = _af.keep_clear_i
		var k: int = (ki + 1 + _scan) % n if ki >= 0 else _scan % n
		_scan += 1
		if k == ki:
			continue
		var route: PackedVector3Array = _af.taxi_route(spots[k])
		if route.size() < 3:
			continue
		var wp: Vector3 = _af.global_transform * (spots[k] as Vector3)
		if Vector2(wp.x, wp.z).distance_to(Vector2(_player_spot.x, _player_spot.z)) < 30.0:
			continue
		_spawn("wing%d" % (_spawned + 1), k, route)
		_spawned += 1
		return


func _physics_process(delta: float) -> void:
	if _agents.is_empty() or _finished:
		return
	_t += delta
	_tick += 1
	if _hold_player and _t >= _release_after:
		(_agents[0]["ctrl"] as TaxiController).cleared = true
	_wingmen_tick()
	for ag in _agents:
		(ag["ctrl"] as TaxiController).tick(delta)
	var every: int = maxi(1, int(round(60.0 / _hz)))
	if _tick % every == 0:
		_frames.append(_frame())
	var all_done: bool = _spawned >= _want or _scan >= _af._dispersal_local.size()
	for ag in _agents:
		all_done = all_done and bool(ag["done"])
	if all_done and _stopped_after < 0.0:
		_stopped_after = _t + 3.0
	if (_stopped_after >= 0.0 and _t >= _stopped_after) or _t >= _secs:
		_finish("done" if _stopped_after >= 0.0 else "timeout: not every aircraft lined up in %.0fs" % _secs)


func _state_of(ag: Dictionary) -> String:
	var ctrl: TaxiController = ag["ctrl"]
	var ac: Aircraft = ag["ac"]
	if bool(ag["done"]):
		return "lined_up"
	if ctrl.holding:
		return "holding"
	if ac.speed < 0.3:
		return "stopped" if ctrl.wp_i > 1 or _t - float(ag["spawn_t"]) > 2.0 else "parked"
	return "taxiing"


func _frame() -> Array:
	var rows: Array = []
	for ag in _agents:
		var ac: Aircraft = ag["ac"]
		var ctrl: TaxiController = ag["ctrl"]
		var lp: Vector3 = _inv * ac.global_position
		var fwd: Vector3 = _inv.basis * (-ac.global_transform.basis.z)
		var yaw: float = rad_to_deg(atan2(fwd.x, -fwd.z))
		rows.append([ag["id"], snappedf(lp.x, 0.01), snappedf(lp.z, 0.01), snappedf(yaw, 0.1), snappedf(ac.speed, 0.01),
			_state_of(ag), ctrl.wp_i, snappedf(ac.throttle_target, 0.01), ac.brake_on])
	return [snappedf(_t, 0.001), rows]


func _log_event(kind: String, msg: String) -> void:
	_events.append({"t": snappedf(_t, 0.001), "kind": kind, "msg": msg})


func _v2(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.z, 0.01)]


func _layout() -> Dictionary:
	var af: Airfield = _af
	var nodes: Array = []
	for p in af.taxi_nodes:
		nodes.append(_v2(p))
	var paved: Array = []
	for pv in af._paved:
		var row: Array = []
		for e in (pv as Array):
			row.append(_v2(e) if e is Vector3 else snappedf(float(e), 0.01))
		paved.append(row)
	var disp: Array = []
	for d in af._dispersal_local:
		disp.append(_v2(d))
	var props: Array = []
	if int(_a.get("props", 1)) != 0:
		_collect_props(af, props)
	return {
		"style": af.style, "name": af.airfield_name, "heading_deg": af.heading_deg,
		"runway": {"length": af.runway_length, "width": af.runway_width},
		"taxi_nodes": nodes, "taxi_edges": af.taxi_edges,
		"hold": _v2(af.taxi_hold), "entry": _v2(af.taxi_entry),
		"paved": paved, "dispersals": disp, "keep_clear": af.keep_clear_i, "props": props,
	}


## Footprints of the tall scenery (hangars, huts, tower, pens, trees...) in the airfield's local XZ:
## [cx, cz, half_x, half_z, yaw_deg, height, name].
func _collect_props(root: Node, out: Array) -> void:
	for c in root.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var mi: MeshInstance3D = c
			var box: AABB = mi.mesh.get_aabb()
			var tr: Transform3D = _inv * mi.global_transform
			var ctr: Vector3 = tr * (box.position + box.size * 0.5)
			var sc: Vector3 = tr.basis.get_scale()
			var h: float = box.size.y * sc.y
			if h >= 2.0 and box.size.x * sc.x < 400.0 and box.size.z * sc.z < 400.0:
				var yaw: float = rad_to_deg(tr.basis.orthonormalized().get_euler().y)
				out.append([snappedf(ctr.x, 0.1), snappedf(ctr.z, 0.1), snappedf(box.size.x * sc.x * 0.5, 0.1), snappedf(box.size.z * sc.z * 0.5, 0.1), snappedf(-yaw, 0.1), snappedf(h, 0.1), String(mi.name)])
		_collect_props(c, out)


func _finish(reason: String) -> void:
	if _finished:
		return
	_finished = true
	_log_event("end", reason)
	var out: String = String(_a.get("out", "build/dbg/run.json"))
	var path: String = out if out.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var data: Dictionary = {
		"version": 1, "args": _a, "hz": _hz, "reason": reason, "sim_secs": snappedf(_t, 0.001),
		"layout": _layout() if _af != null else {}, "agents": [], "events": _events, "frames": _frames,
	}
	for ag in _agents:
		data["agents"].append({"id": ag["id"], "role": ag["role"], "spot": ag["spot"], "route": ag["route"], "radius": ag["radius"],
			"model": ag["model"], "t_done": ag["t_done"], "spawn_t": ag["spawn_t"]})
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("DBG cannot write ", path)
	else:
		f.store_string(JSON.stringify(data))
		f.close()
	print("DBG_DONE %s t=%.1f frames=%d %s" % [path, _t, _frames.size(), reason])
	get_tree().quit()
