class_name SortieManager
extends Node
## Ambient air war for free flight: every couple of minutes a bomber raid takes off from an airfield near the player
## (Allied raids from the English fields, Luftwaffe raids from the French and Belgian ones), forms up over the field,
## climbs out on a realistic route (departure circuit, outbound leg, initial point, bomb run, egress, a different
## way home), drops on a factory / refinery / port / rail yard / city on the other side of the Channel, then returns
## and lands. Escort fighters take off after them and fly in formation with the lead bomber; the other side
## scrambles interceptors from the airfield nearest the target.

const DELAY := 12.0               # seconds between aircraft rolling
const MAX_RAIDS := 2
const FIRST_DELAY := 90.0

var world: Node3D
var player: Node3D
var hud: Node
var difficulty: float = 0.5
var _t: float = FIRST_DELAY
var _raids: Array = []            # {"members": Array[Aircraft], "defenders": Array, "home": Airfield, "done": bool}
var _debug: bool = OS.get_cmdline_user_args().has("--sortie-test")
var _dbg_t: float = 3.0
var _land_test_t: float = 3.0 if OS.get_cmdline_user_args().has("--land-test") else -1.0
var _lt_ac: Aircraft
var _busy: Dictionary = {}        # airfield instance id -> true while a raid is rolling from it


func setup(p_world: Node3D, p_player: Node3D, p_hud: Node, p_difficulty: float, first_delay: float = FIRST_DELAY) -> void:
	world = p_world
	player = p_player
	hud = p_hud
	difficulty = p_difficulty
	_t = first_delay


func _process(delta: float) -> void:
	if world == null or player == null or not is_instance_valid(player):
		return
	if _land_test_t >= 0.0:
		_land_test_t -= delta
		if _land_test_t < 0.0:
			_land_test_t = -1.0
			_land_test()
	if _debug:
		_dbg_t -= delta
		if _dbg_t <= 0.0:
			_dbg_t = 3.0
			for r in _raids:
				var ms: Array = r["members"]
				var line: String = "SORTIE"
				var k: int = 0
				for m in ms:
					if is_instance_valid(m) and k < 4:
						var pp: AIPilot = AIFactory.pilot_of(m)
						line += " | %s st=%d spd=%.0f alt=%.0f gnd=%s thr=%.2f/%.2f yaw=%.2f pit=%.1f ga=%.1f hw=%.1f" % [(m as Aircraft).stats.display_name.substr(0, 6), pp.state if pp else -1, (m as Aircraft).speed, (m as Aircraft).global_position.y, str((m as Aircraft).on_ground), (m as Aircraft).throttle, (m as Aircraft).throttle_target, (m as Aircraft).cmd_yaw, rad_to_deg((m as Aircraft)._pitch_angle()), (m as Aircraft).ground_airspeed(), (m as Aircraft).headwind]
					k += 1
				var ldr: Variant = ms[0] if ms.size() > 0 else null
				if ldr != null and is_instance_valid(ldr):
					var lp2: AIPilot = AIFactory.pilot_of(ldr)
					if lp2 != null:
						line += " || LEADER wp=%d/%d bombs=%d x=%.0f z=%.0f hdg=%.0f" % [lp2.wp_index, lp2.waypoints.size(), (ldr as Aircraft).bombs, (ldr as Aircraft).global_position.x, (ldr as Aircraft).global_position.z, WorldCoords.dir_to_heading((ldr as Aircraft).get_forward())]
				print(line, " n=", ms.size())
	_raids = _raids.filter(func(r: Dictionary) -> bool: return _raid_alive(r))
	_t -= delta
	if _t > 0.0:
		return
	_t = randf_range(140.0, 220.0)
	if _raids.size() >= MAX_RAIDS:
		return
	_try_launch()


func _raid_alive(r: Dictionary) -> bool:
	for m in r["members"]:
		if is_instance_valid(m) and (m as Aircraft).state != Aircraft.State.DEAD:
			return true
	return false


# ------------------------------------------------------------------ planning

func _loaded_airfields() -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	var srcs: Array = []
	if "airfields" in world:
		srcs.append(world.get("airfields"))
	if WorldPopulator.instance != null and is_instance_valid(WorldPopulator.instance):
		srcs.append(WorldPopulator.instance.airfields)
	for src in srcs:
		for k in (src as Dictionary).keys():
			var af: Variant = (src as Dictionary)[k]
			if af != null and is_instance_valid(af) and not seen.has(af.get_instance_id()):
				seen[af.get_instance_id()] = true
				out.append(af)
	return out


func _try_launch() -> void:
	var pop: WorldPopulator = WorldPopulator.instance
	if pop == null or AIFactory.ai_room(get_tree()) < 10:
		return
	var sides: Array = ["Allies", "Axis"]
	sides.shuffle()
	for side in sides:
		var fields: Array = []
		for af in _loaded_airfields():
			var a: Airfield = af
			if GroundKit.side_at(a.global_position) != side or _busy.has(a.get_instance_id()):
				continue
			var d: float = Vector2(a.global_position.x - player.global_position.x, a.global_position.z - player.global_position.z).length()
			if d > 1500.0 and d < 11000.0:
				fields.append(a)
		if fields.is_empty():
			continue
		var origin: Airfield = fields[randi() % fields.size()]
		var enemy: String = AircraftCatalog.opposite(side)
		var cands: Array = []
		for t in pop.raid_targets(enemy):
			var tp: Vector3 = t["pos"]
			var dd: float = Vector2(tp.x - origin.global_position.x, tp.z - origin.global_position.z).length()
			if dd > 12000.0 and dd < 70000.0:
				cands.append([dd, t])
		if cands.is_empty():
			continue
		cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		var pick: Dictionary = cands[randi() % mini(cands.size(), 6)][1]
		_launch(origin, side, pick)
		return


func _pt(x: float, z: float, y: float) -> Vector3:
	return Vector3(x, y, z)


## Waypoints for the whole sortie: departure circuit, outbound leg, IP, bomb run, egress, return leg.
func _build_route(af: Airfield, tpos: Vector3, cruise_y: float) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var dir: Vector3 = WorldCoords.heading_to_dir(af.heading_deg)
	var left := Vector3(dir.z, 0.0, -dir.x)
	var thr: Vector3 = af.get_threshold_position()
	var home := Vector3(af.global_position.x, 0.0, af.global_position.z)
	# climb-out straight ahead, then a left-hand departure circuit while the formation forms up
	pts.append(_pt(thr.x + dir.x * 2600.0, thr.z + dir.z * 2600.0, 700.0))
	var radius: float = 2800.0
	var center: Vector3 = home + left * radius + dir * 1400.0
	var v0 := Vector2(thr.x + dir.x * 2600.0 - center.x, thr.z + dir.z * 2600.0 - center.z)
	var th0: float = v0.angle()
	var tang := Vector2(-sin(th0), cos(th0))
	var sgn_c: float = 1.0 if tang.dot(Vector2(dir.x, dir.z)) > 0.0 else -1.0
	for k in range(1, 19):
		var th: float = th0 + sgn_c * deg_to_rad(20.0) * float(k)
		pts.append(_pt(center.x + cos(th) * radius, center.z + sin(th) * radius, lerpf(800.0, cruise_y * 0.55, minf(float(k) / 14.0, 1.0))))
	# outbound: leave the circuit toward the initial point, climbing to cruise
	var tdir: Vector3 = Vector3(tpos.x - home.x, 0.0, tpos.z - home.z).normalized()
	var tperp := Vector3(-tdir.z, 0.0, tdir.x)
	var sgn: float = 1.0 if randf() < 0.5 else -1.0
	var ip: Vector3 = tpos - tdir * 13000.0 + tperp * sgn * 5000.0
	var last: Vector3 = pts[pts.size() - 1]
	var leg: float = Vector2(ip.x - last.x, ip.z - last.z).length()
	var n: int = maxi(int(leg / 9000.0), 1)
	for i in range(1, n + 1):
		var f: float = float(i) / float(n + 1)
		pts.append(_pt(lerpf(last.x, ip.x, f), lerpf(last.z, ip.z, f), lerpf(cruise_y * 0.55, cruise_y, minf(f * 2.0, 1.0))))
	pts.append(_pt(ip.x, ip.z, cruise_y))
	pts.append(_pt(tpos.x - tdir.x * 6000.0, tpos.z - tdir.z * 6000.0, cruise_y))      # run-in, straight and level
	pts.append(_pt(tpos.x, tpos.z, cruise_y))                                          # over the target
	pts.append(_pt(tpos.x + tdir.x * 4500.0, tpos.z + tdir.z * 4500.0, cruise_y))
	# egress: turn away across the other side, then a different way home, descending
	var eg1: Vector3 = tpos + tdir * 7500.0 - tperp * sgn * 6500.0
	pts.append(_pt(eg1.x, eg1.z, cruise_y - 200.0))
	var mid: Vector3 = (eg1 + home) * 0.5 - tperp * sgn * 4500.0
	pts.append(_pt(mid.x, mid.z, cruise_y * 0.6))
	var iaf: Vector3 = thr - dir * 9000.0 + left * 1800.0
	pts.append(_pt(iaf.x, iaf.z, 1000.0))
	return pts


# ------------------------------------------------------------------ launching

func _spawn_on_runway(af: Airfield, id: String, team: String, role: int, slot: int) -> Aircraft:
	var dir: Vector3 = WorldCoords.heading_to_dir(af.heading_deg)
	var right := Vector3(-dir.z, 0.0, dir.x)
	var pos: Vector3 = af.get_threshold_position() + right * (float(slot % 3) - 1.0) * 9.0
	var st: AircraftStats = AircraftCatalog.load_stats(id)
	pos.y = af.surface_y + st.gear_height + 0.35
	return AIFactory.spawn(world, id, team, pos, af.heading_deg, 0.0, difficulty, role, null, true)


func _launch(af: Airfield, side: String, tgt: Dictionary) -> void:
	var enemy: String = AircraftCatalog.opposite(side)
	var bomber_id: String = AircraftCatalog.bombers_for_side(side)[randi() % AircraftCatalog.bombers_for_side(side).size()]
	var fighter_pool: Array = AircraftCatalog.fighters_for_side(side).filter(func(i: String) -> bool: return i != "me262" and i != "mosquito")
	var fighter_id: String = fighter_pool[randi() % fighter_pool.size()]
	var n_b: int = mini(BomberFormation.scaled(randi_range(4, 6)), 12)      # bigger raids (one takes off at a time)
	var n_f: int = randi_range(4, 6)
	var room: int = AIFactory.ai_room(get_tree())                         # free flight: share the AI budget
	if room < 1000:
		n_b = mini(n_b, maxi(3, room / 2))
		n_f = mini(n_f, maxi(0, room - n_b - 4))                           # leave room for the interceptors
	var cruise_y: float = randf_range(3800.0, 4600.0)
	var tpos: Vector3 = tgt["pos"]
	var route: Array[Vector3] = _build_route(af, tpos, cruise_y)
	var dir: Vector3 = WorldCoords.heading_to_dir(af.heading_deg)
	var raid: Dictionary = {"members": [], "defenders": [], "home": af, "done": false}
	_raids.append(raid)
	_busy[af.get_instance_id()] = true
	_say("%s %s taking off from %s - target: %s" % [side, "bombers", af.airfield_name, str(tgt["name"])])
	var form := BomberFormation.new()
	form.name = "BomberFormation"
	form.team = side
	form.difficulty = difficulty
	form.gunner_damage = lerpf(2.5, 4.5, difficulty)
	world.add_child(form)
	var ground_t := Vector3(tpos.x, GroundKit.ground_y(tpos.x, tpos.z), tpos.z)
	# bombers, one every DELAY seconds
	for i in n_b:
		if not is_instance_valid(af) or not is_instance_valid(world):
			break
		var role: int = AIPilot.Role.BOMBER_LEADER if i == 0 else AIPilot.Role.BOMBER_FOLLOWER
		var ac: Aircraft = _spawn_on_runway(af, bomber_id, side, role, i)
		ac.add_to_group("bomber")
		form.members.append(ac)
		(raid["members"] as Array).append(ac)
		var p: AIPilot = AIFactory.pilot_of(ac)
		p.bomb_target = ground_t
		p.bomb_armed = true
		if i == 0:
			form.leader = ac
			p.waypoints = route
			p.wp_index = 0
			# climb out over the field so the formation can get up and together, then route to the target
			p.climb_center = Vector3(af.position.x, af.surface_y, af.position.z)
			p.climb_alt = cruise_y
			p.climb_radius = 1700.0
			p.after_climb = AIPilot.State.ROUTE
			p.climb_out_finished.connect(func() -> void:
				Radio.say("Bomber leader", "Formed up. Proceeding to the target.", Radio.Kind.FRIENDLY, 0.5))
			p.begin_takeoff(dir, AIPilot.State.CLIMB_OUT)
			Radio.say("Bomber leader", "Squadron, form up on me. Climbing out over the field.", Radio.Kind.FRIENDLY, 1.5)
			p.route_finished.connect(func() -> void: _on_route_end(raid))
		else:
			var off: Vector3 = BomberFormation.slot_offset(i, 110.0)
			p.set_leader(form.members[0], off)
			p.begin_takeoff(dir, AIPilot.State.FORMATION)
		ac.destroyed.connect(form._on_member_destroyed)
		_track(ac, side)
		await get_tree().create_timer(DELAY).timeout
	# escorts take off behind them and fly with the lead bomber
	for j in n_f:
		if not is_instance_valid(af) or not is_instance_valid(form.leader):
			break
		var fa: Aircraft = _spawn_on_runway(af, fighter_id, side, AIPilot.Role.WINGMAN, j)
		(raid["members"] as Array).append(fa)
		var fp: AIPilot = AIFactory.pilot_of(fa)
		fp.set_leader(form.leader, Vector3((220.0 + float(j / 2) * 80.0) * (1.0 if j % 2 == 0 else -1.0), 90.0 + float(j / 2) * 40.0, 60.0 + float(j / 2) * 110.0))
		fp.engage_radius = 3600.0
		fp.detect_range = 7500.0
		fp.begin_takeoff(dir, AIPilot.State.FORMATION)
		_track(fa, side)
		await get_tree().create_timer(DELAY * 0.5).timeout
	_busy.erase(af.get_instance_id())
	# the other side scrambles interceptors against the raid
	await get_tree().create_timer(25.0).timeout
	_scramble(raid, enemy, tpos, cruise_y)


func _scramble(raid: Dictionary, enemy: String, tpos: Vector3, cruise_y: float) -> void:
	var pop: WorldPopulator = WorldPopulator.instance
	if pop == null:
		return
	var fields: Array = pop.airfield_sites("Luftwaffe" if enemy == "Axis" else "RAF")
	var best: Dictionary = {}
	var bd: float = INF
	for f in fields:
		var fp: Vector3 = f["pos"]
		var d: float = Vector2(fp.x - tpos.x, fp.z - tpos.z).length()
		if d < bd and d < 40000.0:
			bd = d
			best = f
	if best.is_empty():
		return
	var pool: Array = AircraftCatalog.fighters_for_side(enemy).filter(func(i: String) -> bool: return i != "me262" and i != "mosquito")
	var fid: String = pool[randi() % pool.size()]
	var n: int = mini(randi_range(4, 6), AIFactory.ai_room(get_tree()))
	if n <= 0:
		return
	var loaded: Airfield = null
	for af in _loaded_airfields():
		if (af as Airfield).airfield_name == str(best.get("name", "")) or str(best["id"]) in WorldPopulator.instance.airfields and WorldPopulator.instance.airfields[best["id"]] == af:
			loaded = af
	_say("%s interceptors scrambling" % enemy)
	for i in n:
		var ac: Aircraft
		var fpos: Vector3 = best["pos"]
		if loaded != null and is_instance_valid(loaded):
			ac = _spawn_on_runway(loaded, fid, enemy, AIPilot.Role.FIGHTER, i)
			var pl: AIPilot = AIFactory.pilot_of(ac)
			pl.patrol_center = tpos
			pl.patrol_alt = cruise_y
			pl.patrol_radius = 3500.0
			pl.detect_range = 9000.0
			pl.begin_takeoff(WorldCoords.heading_to_dir(loaded.heading_deg), AIPilot.State.PATROL)
			await get_tree().create_timer(DELAY * 0.6).timeout
		else:
			var hd: float = WorldCoords.dir_to_heading(Vector3(tpos.x - fpos.x, 0.0, tpos.z - fpos.z))
			ac = AIFactory.spawn(world, fid, enemy, Vector3(fpos.x + float(i) * 120.0, 1400.0, fpos.z), hd, -1.0, difficulty, AIPilot.Role.FIGHTER)
			var pa: AIPilot = AIFactory.pilot_of(ac)
			pa.patrol_center = tpos
			pa.patrol_alt = cruise_y
			pa.patrol_radius = 3500.0
			pa.detect_range = 9000.0
		(raid["defenders"] as Array).append(ac)
		(raid["members"] as Array).append(ac)
		_track(ac, enemy)


# ------------------------------------------------------------------ bookkeeping

func _track(ac: Aircraft, team: String) -> void:
	var friendly: bool = team == GameState.player_side
	AIFactory.add_marker(hud, ac, Color(0.3, 0.75, 1.0) if friendly else Color(1.0, 0.25, 0.2))
	ac.crashed.connect(func(x: Aircraft, _r: String) -> void:
		await x.get_tree().create_timer(2.5).timeout
		if is_instance_valid(x):
			x.queue_free())


func _say(msg: String) -> void:
	if hud != null and hud.has_method("show_message"):
		hud.call("show_message", msg, 4.0)


func _on_route_end(raid: Dictionary) -> void:
	if raid["done"]:
		return
	raid["done"] = true
	var home: Airfield = raid["home"]
	var k: int = 0
	for m in raid["members"]:
		if not is_instance_valid(m):
			continue
		var p: AIPilot = AIFactory.pilot_of(m)
		if p == null or p.state == AIPilot.State.LAND:
			continue
		var af: Airfield = home if is_instance_valid(home) else null
		if af == null or GroundKit.side_at(af.global_position) != m.team:
			continue
		# defenders are not coming home with the bombers; the rest line up for the circuit one after another
		if m in raid["defenders"]:
			continue
		var delay: float = float(k) * 3.5
		k += 1
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if is_instance_valid(p) and is_instance_valid(af):
				p.begin_landing(af))
	for d in raid["defenders"]:
		if is_instance_valid(d):
			get_tree().create_timer(randf_range(40.0, 90.0)).timeout.connect(func() -> void:
				if is_instance_valid(d):
					(d as Node).queue_free())


func _land_test() -> void:
	var af: Airfield = null
	for a in _loaded_airfields():
		af = a
		break
	if af == null:
		print("LANDTEST no airfield")
		return
	var dir: Vector3 = WorldCoords.heading_to_dir(af.heading_deg)
	var left := Vector3(dir.z, 0.0, -dir.x)
	var thr: Vector3 = af.get_threshold_position()
	var pos: Vector3 = thr - dir * 9000.0 + left * 2200.0
	pos.y = af.surface_y + 900.0
	var ac: Aircraft = AIFactory.spawn(world, "lancaster", "Allies", pos, af.heading_deg, 95.0, 0.5, AIPilot.Role.BOMBER_LEADER)
	var p: AIPilot = AIFactory.pilot_of(ac)
	p.landed_ai.connect(func(_a: Aircraft) -> void: print("LANDTEST LANDED at t=", Time.get_ticks_msec() / 1000.0))
	p.begin_landing(af)
	_lt_ac = ac
	print("LANDTEST start")


func _physics_process(_d: float) -> void:
	if _lt_ac != null and is_instance_valid(_lt_ac) and Engine.get_physics_frames() % 30 == 0:
		var af: Airfield = null
		for a in _loaded_airfields():
			af = a
			break
		if af != null:
			var dir: Vector3 = WorldCoords.heading_to_dir(af.heading_deg)
			var thr: Vector3 = af.get_threshold_position()
			var rel: Vector3 = _lt_ac.global_position - thr
			var pp: AIPilot = AIFactory.pilot_of(_lt_ac)
			print("LANDTEST along=%.0f lat=%.0f alt=%.0f agl=%.0f spd=%.0f st=%d gear=%s" % [rel.dot(dir), rel.dot(Vector3(-dir.z, 0.0, dir.x)), _lt_ac.global_position.y, _lt_ac.altitude_agl, _lt_ac.speed, pp.state, str(_lt_ac.gear_down)])
