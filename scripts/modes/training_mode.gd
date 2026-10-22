class_name TrainingMode
extends ModeBase
## Training missions: short guided lessons with an instructor and on-screen objectives.
##   t_first_sortie  the whole first experience in one lesson: take off, shoot four drones, land
##   t_basic      level flight, climbing, turning: fly through rings
##   t_takeoff    full throttle, rotate, gear up, climb out
##   t_landing    join the approach, gear down, land on the runway
##   t_gunnery    shoot down target drones
##   t_rockets    rockets / bombs against ground targets
##   t_formation  hold station on a lead aircraft
##   t_stall      stall and recover
##   t_dogfight   one-on-one against an easy fighter
## configure(cfg): side, aircraft, mission (lesson id). A lesson can also be forced from the command
##   line with --mission=<id>, e.g. --skip-menu --mode=training --mission=t_first_sortie.
##   The first-sortie chain can be entered part-way for testing with --lesson-phase=1|2.

const LESSONS := [
	{"id": "t_first_sortie", "name": "First Sortie (start here)", "brief": "Start here. Take off, shoot down four drones at the practice range, then fly back and land gently."},
	{"id": "t_basic", "name": "1. Basic flying", "brief": "Level flight, climbs and turns. Fly through the glowing rings."},
	{"id": "t_takeoff", "name": "2. Take-off", "brief": "Line up on the runway, full throttle, rotate and climb away."},
	{"id": "t_landing", "name": "3. Landing", "brief": "Join the approach, lower the gear and flaps and put it down on the runway."},
	{"id": "t_gunnery", "name": "4. Gunnery", "brief": "Shoot down four target drones with your guns."},
	{"id": "t_rockets", "name": "5. Rockets and bombs", "brief": "Destroy the bunkers and fuel tanks with rockets, bombs or guns. B selects the weapon."},
	{"id": "t_formation", "name": "6. Formation flying", "brief": "Hold your place beside the leader through a series of turns."},
	{"id": "t_stall", "name": "7. Stalls and recovery", "brief": "Stall the aircraft on purpose, then recover without losing too much height."},
	{"id": "t_dogfight", "name": "8. Dogfighting", "brief": "Shoot down two training opponents."},
]

## The first-sortie lesson runs the take-off, gunnery and landing phases in one chain.
const PHASE_TAKEOFF := 0
const PHASE_GUNNERY := 1
const PHASE_LANDING := 2

var start_airborne: bool = true
var manages_respawn: bool = true

var lesson: String = "t_first_sortie"
var side: String = "Allies"
var enemy_side: String = "Axis"
var _label: Label
var _phase: int = PHASE_TAKEOFF
var _phase_t: float = 0.0
var _step: int = 0
var _obj: String = ""
var _detail: String = ""
var _t: float = 0.0
var _rings: Array[Node3D] = []
var _targets: Array[Node] = []
var _kills: int = 0
var _drones_total: int = 0
var _leader: Aircraft
var _station_time: float = 0.0
var _pose_pos: Vector3 = Vector3.ZERO
var _pose_heading: float = 0.0
var _pose_air: bool = true
var _pose_speed: float = -1.0
var _dead_t: float = -1.0
var _stall_alt: float = 0.0
var _done: bool = false
var _landed_t: float = -1.0


static func lesson_ids() -> Array:
	var out: Array = []
	for l in LESSONS:
		out.append(String(l["id"]))
	return out


static func lesson_names() -> Array:
	var out: Array = []
	for l in LESSONS:
		out.append(String(l["name"]))
	return out


static func brief_for(id: String) -> String:
	for l in LESSONS:
		if String(l["id"]) == id:
			return String(l["brief"])
	return ""


func configure(cfg: Dictionary) -> void:
	side = String(cfg.get("side", GameState.player_side))
	enemy_side = AircraftCatalog.opposite(side)
	lesson = String(cfg.get("mission", lesson))
	for a in OS.get_cmdline_user_args():     # debug: force a lesson (the menu passes it in cfg instead)
		if a.begins_with("--mission="):
			lesson = a.substr(10)
	if not (lesson in lesson_ids()):
		lesson = String(LESSONS[0]["id"])    # unknown / empty: fall back to the lesson listed first
	start_airborne = not (lesson == "t_takeoff" or lesson == "t_first_sortie")
	print("[training] lesson: %s (%s)" % [lesson, "airborne" if start_airborne else "on the ground"])


func start() -> void:
	super.start()
	_build_label()
	if player and is_instance_valid(player):
		var p: Aircraft = player as Aircraft
		p.crashed.connect(func(_a: Aircraft, _r: String) -> void: _dead_t = 2.5)
		p.destroyed.connect(func(_a: Aircraft, _k: Node) -> void: _dead_t = 2.5)
		p.took_off.connect(func(_a: Aircraft) -> void: _on_took_off())
		p.landed.connect(func(_a: Aircraft) -> void: _on_landed())
	_setup_lesson()


func stop() -> void:
	super.stop()
	for r in _rings:
		if is_instance_valid(r):
			r.queue_free()
	_rings.clear()
	if _label and is_instance_valid(_label):
		_label.queue_free()


# ------------------------------------------------------------------ helpers

func _af() -> Airfield:
	var afs: Variant = world.get("airfields") if world != null else null
	if afs is Dictionary and (afs as Dictionary).has(GameState.start_airfield):
		return (afs as Dictionary)[GameState.start_airfield]
	return null


func _build_label() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.82))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 4)
	if hud and hud.has_method("add_widget"):
		hud.call("add_widget", _label)


## Recorded instructor lines (assets/voice/training/<allies|axis>/<key>), matched by the start of the text.
const VOICE_KEYS := {
	"Welcome to flying school": "basic_welcome", "Full throttle. Keep her straight": "takeoff_start",
	"You are on the downwind": "landing_start", "Four target drones": "gunnery_start", "Ground targets ahead": "rockets_start",
	"Stay on the leader's wing": "formation_start", "We are going to stall": "stall_start", "Two practice opponents": "dogfight_start",
	"Now a gentle climb": "basic_climb", "Bank left": "basic_left", "Now roll right": "basic_right", "Throttle back a little": "basic_descend",
	"Good.": "good", "Let's try that again": "again", "Good shooting": "gunnery_done", "Well flown": "all_done",
	"All targets destroyed": "targets_done", "Airborne": "airborne", "Nice landing": "nice_landing", "That was off the runway": "off_runway",
	"Rolling": "rolling", "Gear up": "gear_up_climb", "Clean take-off": "clean_takeoff", "Gear down": "gear_down_line_up",
	"Smooth landing": "smooth_landing", "Excellent formation": "formation_done", "She has stalled": "stalled",
	"Recovered": "recovered", "Too low": "too_low",
}


func _say(text: String, secs: float = 4.5) -> void:
	if hud and hud.has_method("show_message"):
		hud.call("show_message", "Instructor: " + text, secs)
	for k in VOICE_KEYS:
		if text.begins_with(String(k)):
			_voice(String(VOICE_KEYS[k]), text)
			break


func _voice(key: String, text: String) -> void:
	var side: String = "axis" if GameState.player_side == "Axis" else "allies"
	Radio.say("Instructor", text, Radio.Kind.CONTROL, 0.0, "training/%s/%s" % [side, key], true)


func _set_obj(text: String) -> void:
	_obj = text
	objective_updated.emit(text)


func _refresh_label() -> void:
	if _label == null or not is_instance_valid(_label):
		return
	var name_s: String = ""
	for l in LESSONS:
		if String(l["id"]) == lesson:
			name_s = String(l["name"])
	_label.text = "TRAINING  %s\n%s%s" % [name_s, _obj, ("\n" + _detail) if _detail != "" else ""]


## Remember the pose crash recovery should put the player back at (without moving them now).
func _store_pose(pos: Vector3, heading: float, airborne: bool, speed: float = -1.0) -> void:
	_pose_pos = pos
	_pose_heading = heading
	_pose_air = airborne
	_pose_speed = speed


func _pose(pos: Vector3, heading: float, airborne: bool, speed: float = -1.0) -> void:
	_store_pose(pos, heading, airborne, speed)
	_reset_player()


func _reset_player() -> void:
	var p: Aircraft = player as Aircraft
	if p == null:
		return
	p.reset_pose(_pose_pos, _pose_heading, _pose_air, _pose_speed)
	p.process_mode = Node.PROCESS_MODE_INHERIT
	if world != null and world.get("camera_rig") != null:
		(world.get("camera_rig") as CameraRig).bind(p)
	var terr: Node = world.get_tree().get_first_node_in_group("terrain") if world != null else null
	if terr != null and terr.has_method("set_focus"):
		terr.call("set_focus", p)


func _ground(p: Vector3) -> float:
	return GroundKit.ground_y(p.x, p.z)


## A glowing ring (plus a tall beam so it can be seen from far away) that the player flies through.
func _make_ring(pos: Vector3, dir: Vector3, radius: float, col: Color) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	var d: Vector3 = dir.normalized()
	var x: Vector3 = d.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z: Vector3 = x.cross(d)
	root.basis = Basis(x, d, z)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(col, 0.95)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true       # haze used to wash the rings out at a distance
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.88
	tm.outer_radius = radius * 1.04
	tm.rings = 48
	tm.ring_segments = 12
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.5
	cm.bottom_radius = 2.5
	cm.height = 2400.0
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(col, 0.35)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bmat.disable_fog = true
	beam.mesh = cm
	beam.material_override = bmat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = pos + Vector3(0, 1100, 0)
	world.add_child(beam)
	world.add_child(root)
	_rings.append(beam)
	_rings.append(root)
	return root


func _clear_rings() -> void:
	for r in _rings:
		if is_instance_valid(r):
			r.queue_free()
	_rings.clear()


func _fwd_flat(heading: float) -> Vector3:
	return WorldCoords.heading_to_dir(heading)


func _dist_label(p: Vector3) -> String:
	var pl: Vector3 = (player as Node3D).global_position
	var d: Vector3 = p - pl
	var flat: float = Vector2(d.x, d.z).length()
	var brg: float = WorldCoords.dir_to_heading(Vector3(d.x, 0.0, d.z))
	return "%.1f km   bearing %03d   %+d m height" % [flat * WorldCoords.HORIZ_COMPRESSION / 1000.0, int(round(brg)) % 360, int(round(d.y * 0.5))]


# ------------------------------------------------------------------ lessons

func _setup_lesson() -> void:
	var af: Airfield = _af()
	if af == null:
		_set_obj("No airfield available")
		return
	var dir: Vector3 = _fwd_flat(af.heading_deg)
	var thr: Vector3 = af.get_threshold_position()
	_step = 0
	_voice(lesson + "_intro", brief_for(lesson))
	match lesson:
		"t_first_sortie":
			# ground start at the home field: full throttle, rotate, gear up, climb out (take-off phase)
			_phase = _debug_phase()          # --lesson-phase=1|2 jumps into the range / landing phase
			_phase_t = 0.0
			if _phase == PHASE_GUNNERY:
				_first_sortie_gunnery(true)
			elif _phase == PHASE_LANDING:
				_first_sortie_landing(true)
			else:
				_phase = PHASE_TAKEOFF
				_pose(thr + Vector3(0, 1.5, 0), af.heading_deg, false)
				_set_obj("Full throttle (Shift) and roll down the runway")
				_say("Welcome to flying school. This is your first sortie: take off, shoot down four drones at the range, then fly back and land.")
		"t_basic":
			var p0 := Vector3(thr.x, af.surface_y + 900.0, thr.z)
			_pose(p0, af.heading_deg, true, 90.0)
			_say("Welcome to flying school. Keep the nose level and fly through the first ring.")
			_basic_step()
		"t_takeoff":
			_pose(thr + Vector3(0, 1.5, 0), af.heading_deg, false)
			_set_obj("Throttle up (Shift) and roll down the runway")
			_say("Full throttle. Keep her straight with the rudder (Q / E).")
		"t_landing":
			var start: Vector3 = thr - dir * 6500.0
			start.y = af.surface_y + 420.0
			var st: AircraftStats = (player as Aircraft).stats
			_pose(start, af.heading_deg, true, st.stall_speed * 1.9)
			(player as Aircraft).throttle_target = 0.45
			_set_obj("Lower the gear (G) and flaps (F)")
			_say("You are on the downwind-to-final leg. Gear down, flaps down, line up with the runway.")
		"t_gunnery":
			_pose(Vector3(thr.x, af.surface_y + 1100.0, thr.z), af.heading_deg, true, 90.0)
			_spawn_drones(af, 4)
			_say("Four target drones ahead. Get behind one and use the guns (Space).")
		"t_rockets":
			_pose(Vector3(thr.x, af.surface_y + 900.0, thr.z), af.heading_deg, true, 90.0)
			_spawn_ground_targets(af, dir)
			_say("Ground targets ahead. B switches between guns, rockets and bombs; Space fires.")
		"t_formation":
			_pose(Vector3(thr.x, af.surface_y + 1000.0, thr.z), af.heading_deg, true, 90.0)
			_spawn_leader(af, dir)
			_say("Stay on the leader's wing. Keep close but do not collide.")
		"t_stall":
			_pose(Vector3(thr.x, af.surface_y + 1800.0, thr.z), af.heading_deg, true, 100.0)
			_set_obj("Throttle back (Ctrl) and pull the nose up (S) until she stalls")
			_say("We are going to stall her on purpose. Throttle back and hold the stick back.")
		"t_dogfight":
			_pose(Vector3(thr.x, af.surface_y + 1300.0, thr.z), af.heading_deg, true, 100.0)
			_spawn_opponents(af, dir, 2)
			_say("Two practice opponents. Get on their tail and shoot them down.")
	_refresh_label()


func _basic_step() -> void:
	_clear_rings()
	var p: Vector3 = (player as Node3D).global_position
	var f: Vector3 = (player as Aircraft).get_forward()
	var flat := Vector3(f.x, 0.0, f.z).normalized()
	var left := Vector3(flat.z, 0.0, -flat.x)
	match _step:
		0:
			_set_obj("Fly straight and level through the ring")
			_ring_pos(p + flat * 2200.0)
		1:
			_set_obj("Climb through the next ring")
			_say("Now a gentle climb. Pull back a little and open the throttle.")
			_ring_pos(p + flat * 1800.0 + Vector3(0, 500.0, 0))
		2:
			_set_obj("Turn left through the ring")
			_say("Bank left (A) and ease back on the stick to turn.")
			_ring_pos(p + flat * 900.0 + left * 1700.0)
		3:
			_set_obj("Turn right through the ring")
			_say("Now roll right (D) and turn the other way.")
			_ring_pos(p + flat * 800.0 - left * 2100.0)
		4:
			_set_obj("Descend through the ring")
			_say("Throttle back a little and let the nose drop to descend.")
			_ring_pos(p + flat * 2000.0 - Vector3(0, 450.0, 0))
		_:
			_set_obj("Lesson complete")
			_finish_lesson(true)


var _ring_target: Vector3 = Vector3.ZERO


func _ring_pos(pos: Vector3) -> void:
	_ring_target = pos
	var f: Vector3 = ((player as Aircraft).get_forward())
	_make_ring(pos, Vector3(f.x, 0.0, f.z), 85.0, Color(0.3, 1.0, 0.45))


func _spawn_drones(af: Airfield, n: int) -> void:
	var dir: Vector3 = _fwd_flat(af.heading_deg)
	var thr: Vector3 = af.get_threshold_position()
	_drones_total = n
	_kills = 0
	for i in n:
		var pos: Vector3 = thr + dir * (2400.0 + float(i) * 380.0) + Vector3(sin(float(i) * 2.1) * 500.0, af.surface_y + 1100.0 + float(i % 2) * 150.0 - thr.y, 0)
		pos.y = af.surface_y + 1100.0 + float(i % 2) * 160.0
		var d: Aircraft = AIFactory.spawn(world, "bf109" if side == "Allies" else "spitfire", enemy_side, pos, af.heading_deg, 62.0, 0.0)
		var pil: AIPilot = AIFactory.pilot_of(d)
		if pil != null:
			pil.enabled = false
		d.auto_level = true
		d.throttle_target = 0.4
		d.cmd_fire = false
		d.destroyed.connect(func(_a: Aircraft, _k: Node) -> void: _on_drone_down())
		d.crashed.connect(func(x: Aircraft, _r: String) -> void:
			_on_drone_lost()
			await x.get_tree().create_timer(2.0).timeout
			if is_instance_valid(x):
				x.queue_free())
		_targets.append(d)
	_set_obj(_drone_obj())


## Objective line for the drone phases, shared by the gunnery lesson and the first-sortie range phase.
func _drone_obj() -> String:
	var s: String = "Practice range ahead - shoot down the drones: %d / %d" if lesson == "t_first_sortie" else "Shoot down the target drones: %d / %d"
	return s % [_kills, _drones_total]


func _live_drones() -> int:
	var n: int = 0
	for t in _targets:
		if is_instance_valid(t) and t is Aircraft and (t as Aircraft).state == Aircraft.State.ALIVE:
			n += 1
	return n


## A drone that flew into the ground is gone: the first-sortie range phase counts it so the chain can
## never stall after the player (or the AI) loses one out of the count.
func _on_drone_lost() -> void:
	if lesson == "t_first_sortie":
		_on_drone_down()


func _on_drone_down() -> void:
	_kills += 1
	if lesson == "t_gunnery":
		_set_obj(_drone_obj())
		if _kills >= _drones_total:
			_say("Good shooting. That is the gunnery lesson done.")
			_finish_lesson(true)
	elif lesson == "t_dogfight":
		_set_obj("Shoot down the practice opponents: %d / %d" % [_kills, _drones_total])
		if _kills >= _drones_total:
			_say("Well flown. Training complete.")
			_finish_lesson(true)
	elif lesson == "t_first_sortie":
		_set_obj(_drone_obj())
		if _kills >= _drones_total:
			_say("Good shooting. Now turn back to the field and land.")
			_first_sortie_landing()
	_refresh_label()


func _spawn_ground_targets(af: Airfield, dir: Vector3) -> void:
	var thr: Vector3 = af.get_threshold_position()
	var left := Vector3(dir.z, 0.0, -dir.x)
	var found: int = 0
	var tries: int = 0
	_targets.clear()
	while found < 6 and tries < 80:
		tries += 1
		var p: Vector3 = thr + dir * randf_range(2800.0, 4200.0) + left * randf_range(-900.0, 900.0)
		if GroundKit.raw_y(p.x, p.z) < 3.0:
			continue
		var kind: String = "bunker" if found < 4 else "fuel_tank"
		var st: GroundStructure = GroundStructure.create(kind, enemy_side, p, randf() * 360.0)
		st.is_mission_target = false
		world.add_child(st)
		st.destroyed.connect(func(_n: Node, _k: Node) -> void: _on_target_down())
		_targets.append(st)
		found += 1
	_drones_total = found
	_kills = 0
	_set_obj("Destroy the ground targets: 0 / %d" % found)
	if found == 0:
		_set_obj("No land for targets here - choose another airfield")


func _on_target_down() -> void:
	_kills += 1
	_set_obj("Destroy the ground targets: %d / %d" % [_kills, _drones_total])
	if _kills >= _drones_total:
		_say("All targets destroyed. Good work.")
		_finish_lesson(true)
	_refresh_label()


func _spawn_leader(af: Airfield, dir: Vector3) -> void:
	var thr: Vector3 = af.get_threshold_position()
	var pos: Vector3 = thr + dir * 500.0
	pos.y = af.surface_y + 1000.0
	_leader = AIFactory.spawn(world, AircraftCatalog.default_fighter(side), side, pos, af.heading_deg, 95.0, 0.4)
	var pil: AIPilot = AIFactory.pilot_of(_leader)
	var pts: Array[Vector3] = []
	var cur: Vector3 = pos
	var hd: float = af.heading_deg
	for i in 8:
		hd += (26.0 if i % 2 == 0 else -26.0) * (1.0 if i < 6 else 0.5)
		cur += WorldCoords.heading_to_dir(hd) * 2800.0
		pts.append(Vector3(cur.x, pos.y, cur.z))
	pil.set_route(pts)
	pil.state = AIPilot.State.ROUTE
	pil.cruise_throttle = 0.62
	_station_time = 0.0
	_set_obj("Hold station on the leader: 0 / 45 s")


func _spawn_opponents(af: Airfield, dir: Vector3, n: int) -> void:
	var thr: Vector3 = af.get_threshold_position()
	_drones_total = n
	_kills = 0
	for i in n:
		var pos: Vector3 = thr + dir * (2600.0 + float(i) * 500.0)
		pos.y = af.surface_y + 1300.0 + float(i) * 120.0
		var e: Aircraft = AIFactory.spawn(world, "bf109" if side == "Allies" else "spitfire", enemy_side, pos, af.heading_deg + 180.0, -1.0, 0.18)
		var pil: AIPilot = AIFactory.pilot_of(e)
		pil.detect_range = 7000.0
		e.destroyed.connect(func(_a: Aircraft, _k: Node) -> void: _on_drone_down())
		e.crashed.connect(func(x: Aircraft, _r: String) -> void:
			await x.get_tree().create_timer(2.0).timeout
			if is_instance_valid(x):
				x.queue_free())
		_targets.append(e)
	_set_obj("Shoot down the practice opponents: 0 / %d" % n)


## Airborne after the take-off roll: shared by the take-off lesson and the first-sortie take-off phase.
func _takeoff_airborne() -> void:
	if _step < 2:
		_step = 2
		_set_obj("Gear up (G)")
		_say("Airborne. Raise the undercarriage and keep climbing.")


func _on_took_off() -> void:
	if lesson == "t_takeoff":
		_takeoff_airborne()
	elif lesson == "t_first_sortie" and _phase == PHASE_TAKEOFF:
		_takeoff_airborne()


## Touchdown: shared by the landing lesson and the first-sortie landing phase. Sets _step 3 (brake to a
## stop) on the runway, 9 (go round again) anywhere else.
func _landing_touchdown() -> void:
	_landed_t = 0.0
	var af: Airfield = _af()
	var on_rw: bool = false
	if af != null:
		var pl: Vector3 = (player as Node3D).global_position
		var loc: Vector3 = af.to_local(pl)
		on_rw = absf(loc.x) < af.runway_width * 1.1 and absf(loc.z) < af.runway_length * 0.55
	if on_rw:
		_step = 3
		_set_obj("Touchdown! Brake (V) to a stop")
		_say("Nice landing. Use the brakes to stop.")
	else:
		_step = 9
		_set_obj("You landed off the runway - try again")
		_say("That was off the runway. Take off and go round again, or restart the lesson.")


func _on_landed() -> void:
	if lesson == "t_landing":
		if _step < 3:
			_landing_touchdown()
	elif lesson == "t_first_sortie" and _phase == PHASE_LANDING:
		_landing_touchdown()
	_refresh_label()


func _finish_lesson(ok: bool) -> void:
	if _done:
		return
	_done = true
	add_score(1000 if ok else 0)
	get_tree().create_timer(2.5).timeout.connect(func() -> void: finish(ok, {"lesson": lesson}))


# ------------------------------------------------------------------ loop

func _process(delta: float) -> void:
	super._process(delta)
	if not running or player == null or not is_instance_valid(player) or _done:
		return
	var p: Aircraft = player as Aircraft
	if _dead_t >= 0.0:
		_dead_t -= delta
		if _dead_t < 0.0:
			_dead_t = -1.0
			_say("Let's try that again.")
			_reset_player()
			if lesson == "t_basic":
				_basic_step()
			elif lesson == "t_first_sortie":
				_first_sortie_respawn()
		return
	_t += delta
	match lesson:
		"t_first_sortie":
			_step_first_sortie(p)
		"t_basic":
			if _ring_target != Vector3.ZERO and p.global_position.distance_to(_ring_target) < 90.0:
				_step += 1
				_ring_target = Vector3.ZERO
				_say("Good.", 1.5)
				_basic_step()
			elif _ring_target != Vector3.ZERO:
				_detail = _dist_label(_ring_target)
		"t_takeoff":
			_step_takeoff(p)
		"t_landing":
			_step_landing(p)
		"t_formation":
			_step_formation(p, delta)
		"t_stall":
			_step_stall(p)
		"t_gunnery", "t_dogfight":
			_detail_nearest_target(p)
		"t_rockets":
			var nearest2: float = INF
			var tp: Vector3 = Vector3.ZERO
			for t in _targets:
				if is_instance_valid(t) and not (t as GroundTarget).is_dead:
					var d2: float = p.global_position.distance_to((t as Node3D).global_position)
					if d2 < nearest2:
						nearest2 = d2
						tp = (t as Node3D).global_position
			if nearest2 < INF:
				_detail = "Nearest: " + _dist_label(tp)
	_refresh_label()


## Nearest live drone readout, shared by the gunnery, dogfight and first-sortie range phases.
func _detail_nearest_target(p: Aircraft) -> void:
	var nearest: float = INF
	var np: Vector3 = Vector3.ZERO
	for t in _targets:
		if is_instance_valid(t) and t is Aircraft and (t as Aircraft).state == Aircraft.State.ALIVE:
			var dd: float = p.global_position.distance_to((t as Node3D).global_position)
			if dd < nearest:
				nearest = dd
				np = (t as Node3D).global_position
	_detail = ("Nearest: " + _dist_label(np)) if nearest < INF else ""


# ------------------------------------------------- first sortie: take off, range, land

## The first sortie chains the take-off, gunnery and landing lessons: each phase runs the step
## function the standalone lesson uses, then hands over to the next one.
func _step_first_sortie(p: Aircraft) -> void:
	_phase_t += get_process_delta_time()
	match _phase:
		PHASE_TAKEOFF:
			_step_takeoff(p)
		PHASE_GUNNERY:
			_detail_nearest_target(p)
			if _phase_t > 4.0 and _live_drones() == 0 and _kills < _drones_total:
				# no drones left in the world to shoot: move the chain on instead of hanging here
				_say("No drones left. Turn back to the field and land.")
				_first_sortie_landing()
		PHASE_LANDING:
			_step_landing(p)


## Phase 2: the practice range, reusing the gunnery lesson's drone spawn and kill count.
## `from_debug` is set by --lesson-phase=1: the player is dropped into the phase instead of flying into it.
func _first_sortie_gunnery(from_debug: bool = false) -> void:
	_phase = PHASE_GUNNERY
	_phase_t = 0.0
	_step = 0
	_detail = ""
	var af: Airfield = _af()
	if af == null:                        # no field to work from: skip the phase rather than error
		_first_sortie_landing()
		return
	var thr: Vector3 = af.get_threshold_position()
	# crash recovery puts the player back level over the range, not on the runway
	_store_pose(Vector3(thr.x, af.surface_y + 1100.0, thr.z), af.heading_deg, true, 90.0)
	_spawn_drones(af, 4)
	if from_debug:
		_reset_player()
	_say("Four target drones ahead. Get behind one and use the guns (Space).")


## Phase 3: back to the field, reusing the landing lesson's gear / approach / touchdown / brake steps.
## `from_debug` is set by --lesson-phase=2: the player is dropped on the approach instead of flying back.
func _first_sortie_landing(from_debug: bool = false) -> void:
	_phase = PHASE_LANDING
	_phase_t = 0.0
	_step = 0
	_detail = ""
	var af: Airfield = _af()
	if af == null or player == null or not is_instance_valid(player):     # nothing to land on: end cleanly
		_finish_lesson(true)
		return
	var dir: Vector3 = _fwd_flat(af.heading_deg)
	var thr: Vector3 = af.get_threshold_position()
	var start: Vector3 = thr - dir * 6500.0
	start.y = af.surface_y + 420.0
	var st: AircraftStats = (player as Aircraft).stats
	_store_pose(start, af.heading_deg, true, st.stall_speed * 1.9)
	if from_debug:
		_reset_player()
	_set_obj("Turn back to the field and lower the gear (G) and flaps (F)")
	_say("You are on the downwind-to-final leg. Gear down, flaps down, line up with the runway.")


## Debug (--lesson-phase=1|2): start the first-sortie chain part-way through to check one phase on its own.
func _debug_phase() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lesson-phase="):
			return clampi(int(a.substr(15)), PHASE_TAKEOFF, PHASE_LANDING)
	return PHASE_TAKEOFF


## The chain is a single lesson: after a crash, re-arm the phase the player was in instead of
## restarting. _reset_player() has already put the aircraft back at the pose stored for that phase.
func _first_sortie_respawn() -> void:
	_phase_t = 0.0
	_step = 0
	_detail = ""
	match _phase:
		PHASE_TAKEOFF:
			_set_obj("Full throttle (Shift) and roll down the runway")
			_say("Full throttle. Keep her straight with the rudder (Q / E).")
		PHASE_GUNNERY:
			var af: Airfield = _af()
			if af != null and _live_drones() == 0 and _kills < _drones_total:
				_spawn_drones(af, 4)      # every drone was lost without being shot down: send fresh ones
			_set_obj(_drone_obj())
			_say("Four target drones ahead. Get behind one and use the guns (Space).")
		PHASE_LANDING:
			_set_obj("Lower the gear (G) and flaps (F)")
			_say("You are on the downwind-to-final leg. Gear down, flaps down, line up with the runway.")
	_refresh_label()


func _step_takeoff(p: Aircraft) -> void:
	match _step:
		0:
			if p.speed > 8.0:
				_step = 1
				_set_obj("Hold her straight, then pull back (S) at %d km/h" % int(p.stats.stall_speed * 3.6 * 1.15))
				_say("Rolling. Rotate gently when the airspeed reads about %d km/h." % int(p.stats.stall_speed * 3.6 * 1.15))
		1:
			_detail = "Speed %d km/h" % int(p.speed * 3.6)
			if lesson == "t_first_sortie" and not p.on_ground:    # took_off never fired: carry on anyway
				_takeoff_airborne()
		2:
			if not p.gear_down:
				_step = 3
				_set_obj("Climb to 300 m")
				_say("Gear up. Now climb away, keep the speed above %d km/h." % int(p.stats.stall_speed * 3.6 * 1.3))
			elif lesson == "t_first_sortie" and p.get_altitude_m() > 200.0:
				# the gear was left down: carry on rather than dead-ending the whole chain
				_step = 3
				_set_obj("Climb to 300 m (gear still down - G to raise)")
				_say("Gear up. Now climb away, keep the speed above %d km/h." % int(p.stats.stall_speed * 3.6 * 1.3))
		3:
			_detail = "Altitude %d m" % int(p.get_altitude_m())
			if p.get_altitude_m() > 300.0:
				if lesson == "t_first_sortie":
					_say("Clean take-off. Now head for the practice range.")
					_first_sortie_gunnery()
				else:
					_set_obj("Take-off complete")
					_say("Clean take-off. Well done.")
					_finish_lesson(true)


func _step_landing(p: Aircraft) -> void:
	var af: Airfield = _af()
	if af == null:
		return
	var dir: Vector3 = _fwd_flat(af.heading_deg)
	var thr: Vector3 = af.get_threshold_position()
	var rel: Vector3 = p.global_position - thr
	var along: float = rel.dot(dir)
	var lat: float = rel.dot(Vector3(-dir.z, 0.0, dir.x))
	match _step:
		0:
			if p.gear_down:
				_step = 1
				_set_obj("Line up with the runway and descend, keep your speed low")
				_say("Gear down. Line up on the runway centreline and aim to touch down just past the threshold.")
		1:
			_detail = "%.1f km to run   %s %d m off centre   %d m above the runway   speed %d km/h" % [maxf(-along, 0.0) * WorldCoords.HORIZ_COMPRESSION / 1000.0, "left" if lat < 0.0 else "right", int(absf(lat) * 2.0), int((p.global_position.y - af.surface_y) * 0.5), int(p.speed * 3.6)]
			if p.on_ground:
				_landing_touchdown()        # touched down without the aircraft's landed signal
		3:
			_detail = "Speed %d km/h" % int(p.speed * 3.6)
			if _landed_t >= 0.0:
				_landed_t += get_process_delta_time()
			if p.speed < 6.0 and _landed_t > 2.0:
				_set_obj("Landing complete")
				_say("Smooth landing. Well done.")
				_finish_lesson(true)
		9:
			_detail = ""
			if lesson == "t_first_sortie" and not p.on_ground and p.gear_down:
				_step = 1                # off the runway: let them fly round and try the approach again


func _step_formation(p: Aircraft, delta: float) -> void:
	if _leader == null or not is_instance_valid(_leader) or _leader.state != Aircraft.State.ALIVE:
		_finish_lesson(true)
		return
	var lf: Vector3 = _leader.get_forward()
	var lflat: Vector3 = Vector3(lf.x, 0.0, lf.z).normalized()
	var slot: Vector3 = _leader.global_position + Basis.looking_at(lflat, Vector3.UP) * Vector3(95.0, 5.0, 95.0)
	var d: float = p.global_position.distance_to(slot)
	var inside: bool = d < 130.0
	if inside:
		_station_time += delta
	_set_obj("Hold station on the leader: %d / 45 s" % int(_station_time))
	_detail = "%s - %d m from your slot" % ["IN POSITION" if inside else "move closer", int(d * 2.0)]
	if _station_time >= 45.0:
		_say("Excellent formation flying.")
		_finish_lesson(true)


func _step_stall(p: Aircraft) -> void:
	match _step:
		0:
			if p.stalled:
				_step = 1
				_stall_alt = p.get_altitude_m()
				_set_obj("Recover: stick forward (W), full throttle, wings level")
				_say("She has stalled. Nose down, full throttle, keep the wings level.")
		1:
			var lost: float = _stall_alt - p.get_altitude_m()
			_detail = "Height lost %d m   speed %d km/h" % [int(lost), int(p.speed * 3.6)]
			if not p.stalled and p.speed > p.stats.stall_speed * 1.35 and absf(rad_to_deg(p._bank_angle())) < 25.0:
				_set_obj("Recovered")
				_say("Recovered after losing %d m. Well done." % int(lost))
				_finish_lesson(true)
			elif p.get_altitude_m() < 120.0:
				_say("Too low - starting again.")
				_reset_player()
				_step = 0
				_set_obj("Throttle back (Ctrl) and pull the nose up (S) until she stalls")
