extends Node
## Debug harness for the air-dropped torpedo (hidden-desktop screenshots only). Started by main.gd for
##   --torp-test[=alt_m,speed_kmh,drop_dist_m,ship_type,ship_speed_ms]   (defaults 25,290,650,destroyer,6)
## together with the usual `--skip-menu --mode=free --side=Allies --aircraft=beaufort --air --at=lat,lon,alt,hdg --torpedoes`.
## The player's aircraft is flown on a scripted straight and level line (kinematic) to a drop point, a destroyer moves
## across the track, and the aim is solved with Torpedo.lead_point so a correct run hits. Pictures go to
##   --torp-out=<dir> (default F:\ww2_dlss\build\fix) as torp_*.jpg: aircraft, entry, wake, hit, hit2, sinking, weapon cam.
## `--torp-miss` aims 180 m behind the ship (a clean miss), `--torp-shots=a,b,c` picks the pictures.

const TorpedoScript := preload("res://scripts/weapons/torpedo.gd")

var main: Node
var player: Aircraft
var alt_m: float = 25.0
var speed_kmh: float = 290.0
var drop_dist: float = 650.0
var ship_type: String = "destroyer"
var ship_speed: float = 6.0
var out_dir: String = "F:/ww2_dlss/build/fix"
var miss: bool = false
var _last_tor_pos: Vector3 = Vector3.ZERO
var shots: Array = ["aircraft", "hud", "entry", "wake", "hit", "hit2", "sink", "cam"]
var _driving: bool = false
var _t: float = 0.0
var _p0: Vector3
var _f: Vector3
var _v: float
var _ship: GroundShip
var _cam: Camera3D
var _result: Dictionary = {}


static func start(main_node: Node, arg: String) -> Node:
	var n := Node.new()
	n.set_script(load("res://scripts/weapons/torp_test.gd"))
	n.name = "TorpTest"
	n.set("main", main_node)
	if arg.contains("="):
		var f: PackedStringArray = arg.split("=")[1].split(",")
		if f.size() > 0 and f[0] != "":
			n.set("alt_m", float(f[0]))
		if f.size() > 1:
			n.set("speed_kmh", float(f[1]))
		if f.size() > 2:
			n.set("drop_dist", float(f[2]))
		if f.size() > 3:
			n.set("ship_type", f[3])
		if f.size() > 4:
			n.set("ship_speed", float(f[4]))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--torp-out="):
			n.set("out_dir", a.substr(11))
		elif a == "--torp-miss":
			n.set("miss", true)
		elif a.begins_with("--torp-shots="):
			n.set("shots", Array(a.substr(13).split(",")))
	main_node.add_child(n)
	return n


func _ready() -> void:
	call_deferred("_run")


func _log(s: String) -> void:
	print("[torp-test] ", s)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	if not shots.has(name):
		return
	await _wait_frames(3)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		_log("empty image for " + name)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path: String = "%s/torp_%s.jpg" % [out_dir, name]
	var err: Error = img.save_jpg(path, 0.92)
	_log("shot %s -> %s (%s) t=%.1f" % [name, path, error_string(err), _t])


var _cam_on: bool = false
var _cam_pos: Vector3
var _cam_look: Vector3


func _process(_d: float) -> void:
	if _cam_on and _cam != null:
		_cam.global_transform = Transform3D(Basis.looking_at((_cam_look - _cam_pos).normalized(), Vector3.UP), _cam_pos)
		if not _cam.current:
			_cam.make_current()


func _use_cam(pos: Vector3, look: Vector3) -> void:
	_cam_on = true
	_cam_pos = pos
	_cam_look = look
	if _cam == null:
		_cam = Camera3D.new()
		_cam.name = "TorpTestCam"
		_cam.far = 20000.0
		_cam.fov = 62.0
		add_child(_cam)
	_cam.global_transform = Transform3D(Basis.looking_at((look - pos).normalized(), Vector3.UP), pos)
	_cam.make_current()


func _run() -> void:
	await _wait(6.0)                       # the world and the player finish building
	player = main.get("player") as Aircraft
	if player == null:
		_log("no player")
		get_tree().quit(1)
		return
	player.invulnerable = true
	player.torpedo_load = true if player.stats.torpedoes > 0 else false
	if not player.torpedo_load:
		_log("aircraft carries no torpedoes: " + String(player.stats.id))
		get_tree().quit(2)
		return
	if player.weapons != null:
		player.bombs = player.max_bombs()
		player.weapons.sync_torpedo_visuals()
	player.weapon_mode = 2
	player.weapon_bombs = true
	_v = speed_kmh / 3.6
	var tid: String = TorpedoScript.type_for_model(player.stats.model_id)
	var f0: Vector3 = player.get_forward()
	f0.y = 0.0
	f0 = f0.normalized()
	var side: Vector3 = Vector3(-f0.z, 0.0, f0.x)
	var drop_pos: Vector3 = Vector3(player.global_position.x, alt_m * WorldCoords.VERTICAL_SCALE, player.global_position.z) + f0 * (_v * 4.0)
	var ship_dir: Vector3 = side
	var ship_at_drop: Vector3 = Vector3(drop_pos.x, 0.0, drop_pos.z) + f0 * drop_dist
	var f: Vector3 = f0
	var ent_t: float = 0.0
	for it in 4:
		var vel: Vector3 = f * _v
		var ent: Dictionary = TorpedoScript.predict_entry(drop_pos + Vector3(0, -1.5, 0), vel)
		ent_t = float(ent["t"])
		var lead: Vector3 = TorpedoScript.lead_point(tid, ent["pos"], ship_at_drop, ship_dir * ship_speed, ent_t)
		if lead == Vector3.ZERO:
			_log("no intercept at this range")
			break
		if miss:
			lead += ship_dir * -1.0 * 180.0
		var d: Vector3 = lead - Vector3(ent["pos"])
		d.y = 0.0
		f = d.normalized()
	_f = f
	_p0 = drop_pos - f * (_v * 4.0)
	# the ship: moving across the track, placed so it is at ship_at_drop when the drop happens (t = 4 s)
	var start: Vector3 = ship_at_drop - ship_dir * ship_speed * 4.0
	var rp: RoutePath = RoutePath.from_points(PackedVector3Array([start, start + ship_dir * 6000.0]))
	_ship = GroundShip.create(ship_type, "Axis", rp, 0.0, ship_speed)
	main.add_child(_ship)
	_log("ship %s speed %.1f at %s, aircraft alt %.0f m %.0f km/h, drop %.0f m from the ship, torpedo %s" % [ship_type, ship_speed, str(start), alt_m, speed_kmh, drop_dist, tid])
	_driving = true
	_t = 0.0
	player.set_physics_process(false)
	_apply_pose(0.0)
	await _wait(1.6)
	# picture 1: the aircraft with the torpedo under the fuselage (from the right-front, slightly below)
	_use_cam(player.global_position + _f * 15.0 + Vector3(_f.z, 0, -_f.x) * 17.0 + Vector3(0, -3.0, 0), player.global_position + Vector3(0, -0.5, 0))
	await _shot("aircraft")
	# picture 2: the HUD with the torpedo sight (the normal chase camera)
	player.get_viewport().get_camera_3d()
	_cam_on = false
	var ccam: Camera3D = main.get("camera_rig").get("chase_cam") as Camera3D
	if ccam != null:
		ccam.make_current()
	await _wait(0.4)
	await _shot("hud")
	# the drop
	while _t < 4.0:
		await get_tree().physics_frame
	player.bomb_requested.emit(player)
	var tor: Node3D = Weapons.last_torpedo
	_last_tor_pos = tor.global_position
	_log("drop at t=%.2f alt=%.1f m: verdict %s" % [_t, player.get_altitude_m(), str(tor.get("verdict"))])
	# the weapon cam (follows the torpedo from the side) a moment after the release
	_cam_on = false
	await _wait(1.3)
	await _shot("cam")
	if not is_instance_valid(tor):
		# a torpedo that broke up on release is already gone: picture the place and finish
		_log("torpedo already gone (broke up / dud) -> %s" % str(Weapons.last_torpedo))
		_use_cam(_last_tor_pos + side * 45.0 + Vector3(0, 18.0, 0), _last_tor_pos)
		await _wait(0.5)
		await _shot("hit")
		_result = {"outcome": "gone", "ship_health": _ship.health, "ship_dead": _ship.is_dead, "run": 0.0}
		_log("RESULT " + str(_result))
		get_tree().quit(0)
		return
	# entry
	var guard: int = 0
	while int(tor.get("phase")) == 0 and guard < 600:
		guard += 1
		await get_tree().physics_frame
	var ep: Vector3 = tor.get("entry_pos")
	_use_cam(ep + side * 26.0 + _f * -34.0 + Vector3(0, 10.0, 0), ep + Vector3(0, 3.0, 0))
	await _wait(0.35)
	_use_cam(ep + side * 26.0 + _f * -34.0 + Vector3(0, 10.0, 0), ep + Vector3(0, 3.0, 0))
	await _shot("entry")
	# the run: the bubble wake from behind and above
	while int(tor.get("phase")) == 1 and float(tor.get("run_dist")) < 260.0:
		await get_tree().physics_frame
	if int(tor.get("phase")) == 1:
		var tp: Vector3 = tor.global_position
		var hd: Vector3 = tor.get("heading")
		_use_cam(tp - hd * 75.0 + Vector3(0, 32.0, 0) + Vector3(-hd.z, 0, hd.x) * 10.0, tp - hd * 20.0)
		await _wait(0.2)
		_use_cam(tor.global_position - hd * 75.0 + Vector3(0, 32.0, 0) + Vector3(-hd.z, 0, hd.x) * 10.0, tor.global_position - hd * 20.0)
		await _shot("wake")
	# wait for the end of the run
	guard = 0
	while int(tor.get("phase")) != 2 and guard < 60 * 90:
		guard += 1
		await get_tree().physics_frame
	var outcome: String = String(tor.get("outcome"))
	_log("outcome %s after %.0f m (fate %s)" % [outcome, float(tor.get("run_dist")), String(tor.get("fate"))])
	var hp: Vector3 = tor.global_position
	var shp: Vector3 = _ship.global_position
	if outcome == "hit":
		_use_cam(shp - _f * 170.0 + side * 40.0 + Vector3(0, 26.0, 0), shp + Vector3(0, 24.0, 0))
		await _wait(0.8)
		_use_cam(shp - _f * 170.0 + side * 40.0 + Vector3(0, 26.0, 0), shp + Vector3(0, 24.0, 0))
		await _shot("hit")
		await _wait(2.0)
		_use_cam(shp - _f * 170.0 + side * 40.0 + Vector3(0, 26.0, 0), shp + Vector3(0, 24.0, 0))
		await _shot("hit2")
		await _wait(16.0)
		_use_cam(_ship.global_position + side * 120.0 + Vector3(0, 22.0, 0), _ship.global_position + Vector3(0, 4.0, 0))
		await _shot("sink")
		await _wait(12.0)
		_use_cam(_ship.global_position + side * 120.0 + Vector3(0, 22.0, 0), _ship.global_position + Vector3(0, 0.0, 0))
		await _shot("sunk")
	else:
		_use_cam(hp + side * 60.0 + Vector3(0, 20.0, 0), hp)
		await _wait(0.5)
		await _shot("hit")
	_result = {"outcome": outcome, "ship_health": _ship.health, "ship_dead": _ship.is_dead, "run": float(tor.get("run_dist"))}
	_log("RESULT " + str(_result))
	await _wait(1.0)
	get_tree().quit(0)


func _physics_process(delta: float) -> void:
	if not _driving or player == null or not is_instance_valid(player):
		return
	_t += delta
	_apply_pose(_t)


func _apply_pose(t: float) -> void:
	var p: Vector3 = _p0 + _f * _v * t
	p.y = alt_m * WorldCoords.VERTICAL_SCALE
	player.global_transform = Transform3D(Basis.looking_at(_f, Vector3.UP), p)
	player.velocity = _f * _v
	player.speed = _v
