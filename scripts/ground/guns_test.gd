extends Node
## Debug harness for the cross-Channel guns (hidden-desktop screenshots only). Started by main.gd for --guns-test[=shots]
## together with  --skip-menu --mode=historical --mission=gun_batteries_1940 --side=Allies --aircraft=spitfire --guns-log
## (the mission starts the player 3.5 km from the nearest battery; GunBatteriesMode teleports on --guns-test).
## Pictures go to F:\ww2_dlss\build\fix\guns_<name>.jpg (override with --guns-out=<dir>):
##   battery  (the battery just after a round: blast, smoke ring, recoil)    far  (the flashes and smoke from several km)
##   casemate (close view of one casemate and its gun)                       railway  (the K5 spur and train)
##   impact   (a shell landing in Dover)    harbour (a shell in Dover harbour, a water plume)    run  (an attack run through the flak)
## and prints [guns-test] lines with the frame rate. `--guns-shots=a,b` picks pictures.

var main: Node
var player: Aircraft
var out_dir: String = "F:/ww2_dlss/build/fix"
var shots: Array = ["far", "battery", "casemate", "impact", "harbour", "railway", "run"]
var _cam: Camera3D
var _cam_on: bool = false
var _cam_pos: Vector3
var _cam_look: Vector3
var _gs: GunShelling


static func start(main_node: Node, arg: String) -> Node:
	var n := Node.new()
	n.set_script(load("res://scripts/ground/guns_test.gd"))
	n.name = "GunsTest"
	n.set("main", main_node)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--guns-out="):
			n.set("out_dir", a.substr(11))
		elif a.begins_with("--guns-shots="):
			n.set("shots", Array(a.substr(13).split(",")))
	main_node.add_child(n)
	return n


func _ready() -> void:
	call_deferred("_run")


func _log(s: String) -> void:
	print("[guns-test] ", s)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout


func _shot(name: String) -> void:
	if not shots.has(name.split("_")[0]):
		return
	for i in 3:
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		_log("empty image for " + name)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path: String = "%s/guns_%s.jpg" % [out_dir, name]
	var err: Error = img.save_jpg(path, 0.92)
	_log("shot %s -> %s (%s) fps=%d" % [name, path, error_string(err), int(Engine.get_frames_per_second())])


func _process(_d: float) -> void:
	if _cam_on and _cam != null:
		_cam.global_transform = Transform3D(Basis.looking_at((_cam_look - _cam_pos).normalized(), Vector3.UP), _cam_pos)
		if not _cam.current:
			_cam.make_current()


func _use_cam(pos: Vector3, look: Vector3, fov: float = 62.0) -> void:
	_cam_on = true
	_cam_pos = pos
	_cam_look = look
	if _cam == null:
		_cam = Camera3D.new()
		_cam.name = "GunsTestCam"
		_cam.far = 60000.0
		add_child(_cam)
	_cam.fov = fov
	_cam.global_transform = Transform3D(Basis.looking_at((look - pos).normalized(), Vector3.UP), pos)
	_cam.make_current()


func _chase() -> void:
	_cam_on = false
	var ccam: Camera3D = main.get("camera_rig").get("chase_cam") as Camera3D
	if ccam != null:
		ccam.make_current()


func _battery(id: String) -> CoastalBattery:
	for b in get_tree().get_nodes_in_group("heavy_battery"):
		if (b as CoastalBattery).target_id == id:
			return b
	return null


func _park_player(pos: Vector3, heading: float) -> void:
	player.reset_pose(pos, heading, true)
	player.set_physics_process(false)


## Lay every gun of a battery on `tid` right away and fire one round from each (in sequence)
func _salvo(id: String, tid: String, gap: float) -> void:
	var r: Dictionary = _gs.rec(id)
	var aim: Vector3 = GunShelling.target_pos(tid)
	var b: CoastalBattery = _battery(id)
	for g in b.guns:
		(g as CoastalGun).set_aim(aim)
	var guard: int = 0
	while guard < 400:
		var all_laid: bool = true
		for g2 in b.guns:
			if not (g2 as CoastalGun).is_laid(2.0):
				all_laid = false
		if all_laid:
			break
		guard += 1
		await get_tree().create_timer(0.25, true, true).timeout
	for i in int(r["n"]):
		_gs._fire(r, i, tid)
		if gap > 0.0:
			await _wait(gap)


func _run() -> void:
	await _wait(8.0)
	player = main.get("player") as Aircraft
	if player == null:
		_log("no player")
		get_tree().quit(1)
		return
	player.invulnerable = true
	_gs = GunShelling.instance()
	var guard: int = 0
	while (_gs == null or _gs.rec("battery_grosser_kurfurst").is_empty() or _battery("battery_grosser_kurfurst") == null) and guard < 200:
		guard += 1
		await _wait(0.5)
		_gs = GunShelling.instance()
	if _gs == null:
		_log("no GunShelling")
		get_tree().quit(2)
		return
	_gs.stop()                     # the harness fires by hand
	_gs.force_target = "dover_harbour"
	_gs.active = true
	for id in GunShelling.site_ids():
		var rr: Dictionary = _gs.rec(id)
		for i in int(rr["n"]):
			(rr["next"] as Array)[i] = 1.0e9      # the scripted rounds only
	var gk: CoastalBattery = _battery("battery_grosser_kurfurst")
	_log("battery at %s heading %.0f, %d guns; player at %s" % [str(gk.global_position), gk.heading_deg, gk.guns.size(), str(player.global_position)])
	var fwd: Vector3 = WorldCoords.heading_to_dir(gk.heading_deg)
	var side: Vector3 = Vector3(-fwd.z, 0.0, fwd.x)
	var c: Vector3 = gk.global_position
	# 1. the flashes and smoke from a few km out (the player's approach); guns fire together
	_park_player(c - fwd * 5200.0 + Vector3(0, 650, 0), gk.heading_deg)
	_use_cam(c - fwd * 5200.0 + Vector3(0, 700, 0) + side * 120.0, c + Vector3(0, 8, 0), 55.0)
	await _wait(6.0)                # terrain and the battery stream in
	_salvo("battery_grosser_kurfurst", "dover_harbour", 0.4)
	await _wait(1.0)
	await _shot("far_1")
	await _wait(5.0)
	await _shot("far_2")
	# 2. close to the battery: blast, smoke ring, recoil. Re-fire one round and shoot at once
	var g0: CoastalGun = gk.guns[1]
	_use_cam(g0.global_position + side * 38.0 - fwd * 8.0 + Vector3(0, 9, 0), g0.global_position + fwd * 6.0 + Vector3(0, 7, 0), 58.0)
	await _wait(14.0)
	var rec: Dictionary = _gs.rec("battery_grosser_kurfurst")
	_gs._fire(rec, 1, "dover_harbour")
	await _wait(0.12)
	await _shot("battery_1")
	await _wait(0.5)
	await _shot("battery_2")
	await _wait(2.5)
	await _shot("battery_3")
	# 3. the whole battery from the air, a little behind and above: casemates, nets, tower, flak
	_use_cam(c - fwd * 150.0 + Vector3(0, 90.0, 0) + side * 130.0, c + fwd * 30.0 + Vector3(0, 4, 0), 62.0)
	await _wait(2.0)
	await _shot("casemate_1")
	_use_cam(c + fwd * 230.0 + Vector3(0, 60.0, 0) + side * 150.0, c + Vector3(0, 6, 0), 62.0)
	await _wait(1.0)
	await _shot("casemate_2")
	# 4. the railway guns
	var rb: CoastalBattery = _battery("battery_k5_coquelles")
	if rb != null:
		var rc: Vector3 = rb.global_position
		var rf: Vector3 = WorldCoords.heading_to_dir(rb.heading_deg)
		var rs: Vector3 = Vector3(-rf.z, 0.0, rf.x)
		_use_cam(rc - rf * 110.0 + rs * 70.0 + Vector3(0, 45.0, 0), rc + rf * 10.0 + Vector3(0, 4, 0), 62.0)
		await _wait(4.0)
		await _shot("railway_1")
	# 5. impact in Dover: player and camera go to the town so it streams in; a shell lands after its (fast-forwarded) flight
	var dp: Vector3 = GunShelling.target_pos("dover_town")
	_park_player(dp + Vector3(-700, 450, 700), 45.0)
	_use_cam(dp + Vector3(-420, 130, 420), dp + Vector3(0, 10, 0), 62.0)
	await _wait(26.0)
	_gs.time_scale = 40.0
	_gs.dispersion_override = 0.0
	_gs.force_target = "dover_town"
	_gs._fire(rec, 0, "dover_town")
	var hit: Array = []
	var want: Dictionary = {"tid": "dover_town", "bid": ""}
	_gs.shell_landed.connect(func(p: Vector3, tn: String, bn: String, _w: bool) -> void:
		if tn == str(want["tid"]) and (str(want["bid"]) == "" or bn == str(want["bid"])):
			hit.append(p))
	guard = 0
	while hit.is_empty() and guard < 200:
		guard += 1
		await get_tree().create_timer(0.1, true, true).timeout
	_gs.time_scale = 1.0
	if not hit.is_empty():
		var hp: Vector3 = hit[0]
		_log("impact at %s" % str(hp))
		_use_cam(hp + Vector3(-260, 90, 260), hp + Vector3(0, 12, 0), 60.0)
		await _wait(0.25)
		await _shot("impact_1")
		await _wait(1.2)
		await _shot("impact_2")
		await _wait(5.0)
		await _shot("impact_3")
	# 6. a shell in the harbour: the water plume
	want["tid"] = "dover_harbour"
	want["bid"] = "battery_friedrich_august"
	_gs.time_scale = 40.0
	var rec2: Dictionary = _gs.rec("battery_friedrich_august")
	hit.clear()
	_gs._fire(rec2, 0, "dover_harbour")
	guard = 0
	while hit.is_empty() and guard < 200:
		guard += 1
		await get_tree().create_timer(0.1, true, true).timeout
	_gs.time_scale = 1.0
	if not hit.is_empty():
		var wp: Vector3 = hit[0]
		_use_cam(wp + Vector3(-300, 80, 300), wp + Vector3(0, 25, 0), 60.0)
		await _wait(0.35)
		await _shot("harbour_1")
		await _wait(1.4)
		await _shot("harbour_2")
	# 7. an attack run: low over the sea and in through the flak, bombs on the casemates, camera behind the aircraft
	_chase()
	var gt: Node3D = gk.guns[0]
	var from: Vector3 = gt.global_position
	_run_f = (from - (c - fwd * 2400.0))
	_run_f.y = 0.0
	_run_f = _run_f.normalized()
	_run_p0 = Vector3(gt.global_position.x, 0.0, gt.global_position.z) - _run_f * 2300.0
	_run_v = 85.0
	_run_alt = 300.0
	player.set_physics_process(false)
	if player.get("bombs") != null:
		player.bombs = 8
	if player.get("stats") != null and player.stats.get("bombs") != null:
		player.stats.bombs = 8
	for gg in gk.guns:
		(gg as CoastalGun).set_aim(GunShelling.target_pos("dover_town"))
	_gs.force_target = "dover_town"
	_gs.active = true
	for i in int(rec["n"]):
		(rec["next"] as Array)[i] = 5.0 + 3.0 * float(i)
	_t = 0.0
	_driving = true
	_log("run starts at %s heading %s" % [str(_run_p0), str(_run_f)])
	var released: int = 0
	var last_rel: float = -9.0
	var shot_t: Array = [5.0, 14.0, 21.0, 24.5, 28.0]
	var shot_i: int = 0
	var t_end: float = 40.0
	while _t < t_end:
		await get_tree().process_frame
		var tgt_g: Node = null
		for g3 in gk.guns:
			if is_instance_valid(g3) and not (g3 as CoastalGun).is_dead:
				tgt_g = g3
				break
		if tgt_g != null and released < 4 and _t - last_rel > 0.45:
			var imp: Vector3 = Weapons.predict_bomb_impact(player.global_position, player.velocity)
			_mind = minf(_mind, Vector2(imp.x - tgt_g.global_position.x, imp.z - tgt_g.global_position.z).length())
			if Vector2(imp.x - tgt_g.global_position.x, imp.z - tgt_g.global_position.z).length() < 48.0:
				player.bomb_requested.emit(player)
				released += 1
				last_rel = _t
				_log("bomb %d released at t=%.1f, %.0f m from the gun" % [released, _t, Vector2(player.global_position.x - tgt_g.global_position.x, player.global_position.z - tgt_g.global_position.z).length()])
		if shot_i < shot_t.size() and _t > float(shot_t[shot_i]):
			await _shot("run_%d" % (shot_i + 1))
			shot_i += 1
	_driving = false
	_log("run over: min predicted miss %.0f m, bombs %d, player bombs %s;" % [_mind, released, str(player.get("bombs"))]); _log("run over: bombs released %d, guns alive %d/%d, silenced %s, aa guns left %d" % [released, _gs.alive_count("battery_grosser_kurfurst"), _gs.total_count("battery_grosser_kurfurst"), str(_gs.is_silenced("battery_grosser_kurfurst")), get_tree().get_nodes_in_group("damageable").size()])
	await _wait(1.5)
	await _shot("run_end")
	_log("done fps=%d" % int(Engine.get_frames_per_second()))
	get_tree().quit(0)


var _mind: float = 1.0e9
var _driving: bool = false
var _t: float = 0.0
var _run_f: Vector3 = Vector3.FORWARD
var _run_p0: Vector3 = Vector3.ZERO
var _run_v: float = 85.0
var _run_alt: float = 300.0


func _physics_process(delta: float) -> void:
	if not _driving or player == null or not is_instance_valid(player):
		return
	_t += delta
	var p: Vector3 = _run_p0 + _run_f * _run_v * _t
	p.y = _run_alt
	player.global_transform = Transform3D(Basis.looking_at(_run_f, Vector3.UP), p)
	player.velocity = _run_f * _run_v
	player.speed = _run_v
