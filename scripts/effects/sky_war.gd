class_name SkyWar
extends Node3D
## The war going on around you. Pure scenery (it never damages anything except where a V-weapon lands):
##  * distant flak barrages - salvos of bursts hanging over defended places kilometres away, now and then by day,
##    almost constantly at night, when the flashes, glowing fragments and streams of coloured light-flak tracer
##    climbing out of the dark make it look like fireworks night;
##  * searchlight cones swinging over whatever is being attacked after dark;
##  * raids on towns: bomb flashes walking across a town, fires taking hold (CityFires), flak and searchlights over it;
##  * the V-weapons blitz (free flight): V-1 flying bombs droning in toward London, and V-2 rockets climbing out of
##    the Pas-de-Calais on a white trail, arriving minutes later out of nowhere.
## main.gd creates one for every air session: SkyWar.new().setup(world, player, hud, mode_id).

const BEAMS: int = 3
const TRACER_COLS := [Color(1.0, 0.25, 0.12), Color(1.0, 0.62, 0.15), Color(1.0, 0.9, 0.35), Color(0.45, 1.0, 0.4)]

# searchlight alert: seconds left in which the lights are up. Set by a raid (15 min after it starts) and by a raid
# that is about to come (2 min before). Peaceful towns stay dark.
static var alert_t: float = 0.0
static func lights_up() -> bool:
	return alert_t > 0.0

var intensity: float = 1.0
var vweapons: bool = false
var raids: bool = false

var _world: Node
var _player: Node3D
var _hud: Node
var _side: String = "Allies"
var _bursts: Array = []        # pending {t, pos, k}
var _streams: Array = []       # active light-flak hoses {pos, dir, t, col, k, sweep}
var _barrage_t: float = 4.0
var _stream_t: float = 6.0
var _raid_t: float = 90.0
var _raid: Dictionary = {}     # {city, t_left, bomb_t}
var _v1_t: float = 150.0
var _v2_t: float = 240.0
var _beams: Array = []         # {mi, base, yaw, pitch, sp, ph}
var _beam_mat: StandardMaterial3D
var _beam_zone: Vector3 = Vector3.INF
var _rng := RandomNumberGenerator.new()
var _force_city: String = ""
var _civil: RaidBlackout = null


func setup(world: Node, player: Node3D, hud: Node, mode_id: String) -> SkyWar:
	_world = world
	_player = player
	_hud = hud
	_side = str(player.get("team")) if player and "team" in player else "Allies"
	vweapons = mode_id == "free"
	raids = mode_id == "free"
	name = "SkyWar"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--skywar="):
			intensity = float(a.substr(9))
		elif a == "--raid-now":
			_raid_t = 3.0
		elif a.begins_with("--raid-city="):      # debug: the raid falls on this town (by name), at once
			_force_city = a.substr(12).to_lower()
			_raid_t = 3.0
		elif a == "--v2-now":
			_v2_t = 2.0
		elif a == "--v1-now":
			_v1_t = 2.0
	return self


func _ready() -> void:
	top_level = true
	_rng.randomize()
	_civil = RaidBlackout.new()
	add_child(_civil)
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(0.55, 0.6, 0.7, 0.10)
	_beam_mat.disable_receive_shadows = true
	var cm := CylinderMesh.new()
	cm.top_radius = 55.0
	cm.bottom_radius = 3.0
	cm.height = 9000.0
	cm.radial_segments = 10
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	for i in BEAMS:
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = _beam_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 9000.0
		mi.visible = false
		add_child(mi)
		_beams.append({"mi": mi, "base": Vector3.ZERO, "yaw": 0.0, "pitch": 0.6, "sp": 0.2, "ph": 0.0, "lit": false, "placed": false, "timer": randf() * 60.0})


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	if _player == null or not is_instance_valid(_player):
		_player = GroundKit.player_node()
		if _player == null:
			return
	var night: float = FX.night_factor()
	alert_t = maxf(alert_t - delta, 0.0)
	var tq: int = Time.get_ticks_usec()
	_tick_siren()
	_tick_barrages(delta, night)
	_tick_bursts(delta)
	_tick_streams(delta, night)
	_tick_beams(delta, night)
	if Time.get_ticks_usec() - tq > 20000:
		print("[slow] sky_war flak/beams %d ms" % ((Time.get_ticks_usec() - tq) / 1000))
	var t0: int = Time.get_ticks_usec()
	if raids:
		_tick_raid(delta, night)
	var t1: int = Time.get_ticks_usec()
	_civil.update(delta, _raid, _player)
	var t2: int = Time.get_ticks_usec()
	if t2 - t0 > 20000:
		print("[slow] sky_war raid %d ms, blackout %d ms" % [(t1 - t0) / 1000, (t2 - t1) / 1000])
	if vweapons:
		_tick_vweapons(delta)


# ------------------------------------------------------------------ distant flak

## A point on land some way off: biased ahead of the player, preferring enemy territory and towns.
func _zone(min_d: float, max_d: float) -> Vector3:
	var p: Vector3 = _player.global_position
	var fwd: Vector3 = -_player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var best := Vector3.INF
	var best_s: float = -1.0
	for i in 8:
		var a: float = atan2(fwd.x, fwd.z) + _rng.randf_range(-1.9, 1.9)
		var d: float = _rng.randf_range(min_d, max_d)
		var q := p + Vector3(sin(a), 0.0, cos(a)) * d
		q.y = GroundKit.ground_y(q.x, q.z)
		if q.y < 1.0 and FX.is_water(q):
			continue
		var sc: float = _rng.randf()
		if GroundKit.side_at(q) != _side:
			sc += 1.0
		if not CityFires.city_at(q).is_empty():
			sc += 0.8
		if sc > best_s:
			best_s = sc
			best = q
	return best


func _tick_barrages(delta: float, night: float) -> void:
	_barrage_t -= delta
	if _barrage_t > 0.0:
		return
	# by day an occasional far-off salvo; at night the sky is full of it
	var per_min: float = (2.5 + 13.0 * night) * intensity
	_barrage_t = 60.0 / maxf(per_min, 0.1) * _rng.randf_range(0.5, 1.5)
	var c: Vector3 = _raid_centre() if not _raid.is_empty() and _rng.randf() < 0.6 else _zone(3500.0, 16000.0)
	if c == Vector3.INF:
		return
	_salvo(c, _rng.randi_range(4, 10 + int(6.0 * night)))
	if night > 0.3:
		_beam_zone = c


## A salvo: several bursts spread through a box of sky over the guns, a second or two apart.
func _salvo(ground: Vector3, n: int) -> void:
	var alt: float = ground.y + _rng.randf_range(1800.0, 7600.0)
	var centre := Vector3(ground.x + _rng.randf_range(-600, 600), alt, ground.z + _rng.randf_range(-600, 600))
	var t0: float = 0.0
	for i in n:
		t0 += _rng.randf_range(0.08, 0.6)
		var p: Vector3 = centre + Vector3(_rng.randf_range(-380, 380), _rng.randf_range(-260, 260), _rng.randf_range(-380, 380))
		_bursts.append({"t": t0, "pos": p})


func _tick_bursts(delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else _player.global_position
	for i in range(_bursts.size() - 1, -1, -1):
		var b: Dictionary = _bursts[i]
		b["t"] = float(b["t"]) - delta
		if float(b["t"]) > 0.0:
			continue
		var p: Vector3 = b["pos"]
		var d: float = eye.distance_to(p)
		if _player.global_position.distance_to(p) < 1500.0:
			_bursts.remove_at(i)        # scenery flak never bursts right beside you (that is the real guns' job)
			continue
		# far bursts are drawn larger so they still read as more than a pixel (and stay silent)
		FX.flak_burst(p, clampf(d / 2600.0, 1.0, 4.0), d > 4500.0)
		_bursts.remove_at(i)


## Streams of light-flak tracer hosing up out of the dark: strings of glowing beads that arc over and burn out.
func _tick_streams(delta: float, night: float) -> void:
	if night > 0.25:
		_stream_t -= delta
		if _stream_t <= 0.0:
			_stream_t = 60.0 / maxf((3.0 + 16.0 * night) * intensity, 0.1) * _rng.randf_range(0.5, 1.5)
			var g: Vector3 = _raid_centre() if not _raid.is_empty() and _rng.randf() < 0.5 else _zone(2500.0, 13000.0)
			if g != Vector3.INF:
				var cam: Camera3D = get_viewport().get_camera_3d()
				var eye: Vector3 = cam.global_position if cam else _player.global_position
				var k: float = clampf(eye.distance_to(g) / 1800.0, 1.0, 5.0)
				var col: Color = TRACER_COLS[_rng.randi() % TRACER_COLS.size()]
				for j in _rng.randi_range(2, 5):
					var a: float = _rng.randf() * TAU
					var el: float = _rng.randf_range(0.75, 1.35)
					var dir := Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el))
					var base: Vector3 = g + Vector3(_rng.randf_range(-250, 250), 2.0, _rng.randf_range(-250, 250))
					base.y = GroundKit.ground_y(base.x, base.z) + 2.0
					_streams.append({"pos": base, "dir": dir, "t": _rng.randf_range(2.0, 4.5), "gap": 0.0, "col": col, "k": k,
						"sweep": Vector3(_rng.randf_range(-0.25, 0.25), 0.0, _rng.randf_range(-0.25, 0.25))})
	for i in range(_streams.size() - 1, -1, -1):
		var s: Dictionary = _streams[i]
		s["t"] = float(s["t"]) - delta
		if float(s["t"]) <= 0.0:
			_streams.remove_at(i)
			continue
		s["dir"] = ((s["dir"] as Vector3) + (s["sweep"] as Vector3) * delta).normalized()
		s["gap"] = float(s["gap"]) - delta
		if float(s["gap"]) <= 0.0:
			s["gap"] = 0.09
			var col: Color = s["col"]
			var k: float = s["k"]
			FX.puffs.spawn(s["pos"], (s["dir"] as Vector3) * 520.0, _rng.randf_range(3.2, 4.2), 2.6 * k, 1.6 * k,
				Color(col.r, col.g, col.b, 1.0), Color(col.r, col.g * 0.6, col.b * 0.4, 0.0), 0.0, 55.0, 0.05)


# ------------------------------------------------------------------ searchlights

## Air-raid siren: heard only low down (under 400 m above the ground) and within about 15 km of the city under
## alert, while a raid is on or expected. It swells as the player closes on the city.
const SIREN_MAX_AGL_M: float = 400.0
const SIREN_RANGE_M: float = 15000.0

func _tick_siren() -> void:
	var lvl: float = 0.0
	if lights_up() and _player != null and is_instance_valid(_player):
		var zone: Vector3 = _raid_centre() if not _raid.is_empty() else _beam_zone
		var agl_v: Variant = _player.get("altitude_agl")
		var agl_m: float = INF if agl_v == null else float(agl_v) / WorldCoords.VERTICAL_SCALE
		if zone != Vector3.INF and agl_m < SIREN_MAX_AGL_M:
			var d: float = Vector2(zone.x - _player.global_position.x, zone.z - _player.global_position.z).length()
			lvl = clampf(1.0 - d / SIREN_RANGE_M, 0.0, 1.0)
	FX.audio.siren(lvl)


func _tick_beams(delta: float, night: float) -> void:
	var on: bool = lights_up() and night > 0.45 and _beam_zone != Vector3.INF and _beam_zone.distance_to(_player.global_position) < 26000.0
	var zone: Vector3 = _raid_centre() if not _raid.is_empty() else _beam_zone
	for i in BEAMS:
		var b: Dictionary = _beams[i]
		var mi: MeshInstance3D = b["mi"]
		# every beam keeps its own clock: it lights and goes out at its own moment, never in step with the others
		b["timer"] = float(b["timer"]) - delta
		if float(b["timer"]) <= 0.0:
			if not on:
				b["lit"] = false
				b["timer"] = _rng.randf_range(0.5, 12.0)
			elif not bool(b["lit"]):
				b["lit"] = true
				b["placed"] = false
				b["timer"] = _rng.randf_range(25.0, 60.0)
			else:
				b["lit"] = false
				b["timer"] = _rng.randf_range(8.0, 25.0)
		mi.visible = bool(b["lit"])
		if not bool(b["lit"]):
			continue
		if not bool(b["placed"]) or (b["base"] as Vector3).distance_to(zone) > 3500.0:
			var q: Vector3 = zone + Vector3(_rng.randf_range(-2200, 2200), 0.0, _rng.randf_range(-2200, 2200))
			q.y = GroundKit.ground_y(q.x, q.z) + 1.0
			b["base"] = q
			b["yaw"] = _rng.randf() * TAU
			b["pitch"] = _rng.randf_range(0.5, 1.1)
			b["sp"] = _rng.randf_range(0.08, 0.22) * (1.0 if _rng.randf() < 0.5 else -1.0)
			b["ph"] = _rng.randf() * TAU
			b["placed"] = true
		b["yaw"] = float(b["yaw"]) + float(b["sp"]) * delta
		b["ph"] = float(b["ph"]) + delta * 0.3
		var pitch: float = clampf(float(b["pitch"]) + 0.25 * sin(float(b["ph"])), 0.35, 1.45)
		var dir := Vector3(cos(float(b["yaw"])) * cos(pitch), sin(pitch), sin(float(b["yaw"])) * cos(pitch))
		var bs: Basis = Basis(Quaternion(Vector3.UP, dir))
		mi.global_transform = Transform3D(bs, (b["base"] as Vector3) + dir * 4500.0)
	# the beams fade in with the dark
	_beam_mat.albedo_color.a = 0.10 * clampf((night - 0.45) / 0.3, 0.0, 1.0)


# ------------------------------------------------------------------ raids on towns

func _raid_centre() -> Vector3:
	if _raid.is_empty():
		return Vector3.INF
	return (_raid["city"] as Dictionary)["pos"]


func _tick_raid(delta: float, night: float) -> void:
	if _raid.is_empty():
		_raid_t -= delta
		if _raid_t < 120.0:
			alert_t = maxf(alert_t, 120.0)   # a raid is expected: the searchlights come up
		if _raid_t > 0.0:
			return
		_raid_t = _rng.randf_range(240.0, 420.0) * (0.6 if night > 0.5 else 1.0) / maxf(intensity, 0.2)
		var tc0: int = Time.get_ticks_usec()
		var cl: Array = CityFires.cities()
		var tc1: int = Time.get_ticks_usec()
		var cands: Array = []
		for c in cl:
			var d: float = Vector2((c["pos"] as Vector3).x - _player.global_position.x, (c["pos"] as Vector3).z - _player.global_position.z).length()
			if _force_city != "":
				if str(c["name"]).to_lower() == _force_city:
					cands = [c]
					break
			elif d > 5000.0 and d < 32000.0:
				cands.append(c)
		if cands.is_empty():
			return
		var city: Dictionary = cands[_rng.randi() % cands.size()]
		_raid = {"city": city, "t_left": _rng.randf_range(150.0, 260.0), "bomb_t": 2.0}
		_beam_zone = city["pos"]
		alert_t = maxf(alert_t, 900.0)   # raid under way: the lights stay up for a while after it
		var own: bool = GroundKit.side_at(city["pos"]) == _side
		var who: String = "Sector Control" if _side == "Allies" else "Jafü 2"
		var msg: String = ("Heavy raid developing on %s. Fires are being reported." if own else "Our bombers are over %s now.") % str(city["name"])
		var tc2: int = Time.get_ticks_usec()
		Radio.say(who, msg, Radio.Kind.CONTROL, 0.5)
		if Time.get_ticks_usec() - tc0 > 20000:
			print("[slow] raid start: cities %d ms, pick %d ms, radio %d ms" % [(tc1 - tc0) / 1000, (tc2 - tc1) / 1000, (Time.get_ticks_usec() - tc2) / 1000])
		return
	_raid["t_left"] = float(_raid["t_left"]) - delta
	if float(_raid["t_left"]) <= 0.0:
		_raid = {}
		return
	_raid["bomb_t"] = float(_raid["bomb_t"]) - delta
	if float(_raid["bomb_t"]) <= 0.0:
		_raid["bomb_t"] = _rng.randf_range(0.4, 1.8)
		var city: Dictionary = _raid["city"]
		var r: float = float(city["r"]) * 0.8
		# a stick of bombs walking across the town
		var p0: Vector3 = (city["pos"] as Vector3) + Vector3(_rng.randf_range(-r, r), 0.0, _rng.randf_range(-r, r))
		var step := Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)).normalized() * 70.0
		for j in _rng.randi_range(2, 5):
			var p: Vector3 = p0 + step * float(j)
			p.y = GroundKit.ground_y(p.x, p.z)
			if FX.is_water(p):
				continue
			var te0: int = Time.get_ticks_usec()
			FX.explosion(p + Vector3(0, 2, 0), _rng.randf_range(12.0, 20.0))
			var te1: int = Time.get_ticks_usec()
			if _rng.randf() < 0.45:
				CityFires.ignite(p, _rng.randf_range(0.8, 1.6))
			if Time.get_ticks_usec() - te0 > 15000:
				print("[slow] raid bomb: explosion %d ms, fire %d ms" % [(te1 - te0) / 1000, (Time.get_ticks_usec() - te1) / 1000])


# ------------------------------------------------------------------ V-weapons

var _v1_warn: float = -1.0       # > 0: a V-1 is on its ramp, counting down to take-off
var _v1_site: Vector3 = Vector3.ZERO


func _tick_vweapons(delta: float) -> void:
	if _v1_warn > 0.0:
		_v1_warn -= delta
		if _v1_warn <= 0.0:
			_v1_warn = -1.0
			_launch_v1()
	_v1_t -= delta
	if _v1_t <= 0.0 and _v1_warn < 0.0:
		_v1_t = _rng.randf_range(200.0, 380.0) / maxf(intensity, 0.2)
		_begin_v1()
	_v2_t -= delta
	if _v2_t <= 0.0:
		_v2_t = _rng.randf_range(300.0, 560.0) / maxf(intensity, 0.2)
		_launch_v2()


func _launch_sites() -> Array:
	var out: Array = []
	var pop: Node = get_tree().get_first_node_in_group("world_populator")
	if pop != null and pop.has_method("targets_for_side"):
		for id in pop.call("targets_for_side", "Axis", ["v1_site"]):
			out.append((pop.call("get_target_info", id) as Dictionary)["pos"])
	if out.is_empty():
		out = [WorldCoords.latlon_to_world(50.75, 2.0), WorldCoords.latlon_to_world(50.71, 2.24), WorldCoords.latlon_to_world(50.83, 2.18)]
	return out


func _london() -> Vector3:
	return WorldCoords.latlon_to_world(51.507, -0.128) + Vector3(_rng.randf_range(-7000, 7000), 0.0, _rng.randf_range(-7000, 7000))


## A V-1 is readied on one of the launch sites. Allied listeners sometimes get a sector warning first; the bomb
## then takes off from the ramp after a short wait (8 to 12 s), and can be shot down during the climb.
func _begin_v1() -> void:
	var sites: Array = _launch_sites()
	_v1_site = sites[_rng.randi() % sites.size()]
	if _side == "Allies" and _rng.randf() < 0.6:
		Radio.say("Sector Control", "V-1 rocket about to launch from the Pas-de-Calais. Watch the coast.", Radio.Kind.CONTROL, 0.3)
		_v1_warn = _rng.randf_range(8.0, 12.0)
	else:
		_v1_warn = 0.05


func _launch_v1() -> void:
	var vb: FlyingBomb = FlyingBomb.launch_from_ramp(_world, _v1_site, _london())
	AIFactory.add_marker(_hud, vb, Color(1.0, 0.15, 0.6))
	if _side == "Allies":
		Radio.say("Sector Control", "Diver, diver! Flying bomb over the coast, heading for London.", Radio.Kind.CONTROL, 0.3)


func _launch_v2() -> void:
	# the Heavy Cross sites in the Pas-de-Calais, or a mobile battery somewhere behind them
	var froms: Array = [WorldCoords.latlon_to_world(50.71, 2.24), WorldCoords.latlon_to_world(50.83, 2.18),
		WorldCoords.latlon_to_world(_rng.randf_range(50.4, 50.9), _rng.randf_range(2.0, 2.9))]
	var from: Vector3 = froms[_rng.randi() % froms.size()]
	var r: V2Rocket = V2Rocket.launch(_world, from, _london())
	if _side == "Allies":
		Radio.say("Sector Control", "Big Ben, Big Ben. Rocket launch reported in the Pas-de-Calais.", Radio.Kind.CONTROL, 2.0)
		r.impact.connect(func(_p: Vector3) -> void:
			Radio.say("Sector Control", "Big Ben has landed in London. Fires are burning.", Radio.Kind.CONTROL, 2.0))
	else:
		Radio.say("Jafü 2", "Vergeltung: a V-2 has gone up from the Pas-de-Calais.", Radio.Kind.CONTROL, 2.0)
