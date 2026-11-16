class_name WarReactions
extends Node3D
## Things that react to the war (living-world phase 4). Three small systems share this one manager node:
##
##  * CRASH SCENES. When an aircraft (either side, the player or an AI) comes down on land, locals and soldiers run in
##    from the countryside, stop at a safe ring 25-40 m from the wreck and stand about talking, smoking or waving
##    people back; on the English side (and in Allied-held France) Home Guard, police and ARP wardens come first, in
##    German-held France it is German soldiers. If a road runs within ~220 m an ambulance drives up it and parks. One
##    MultiMesh per scene (AirfieldPeople.spawn), at most MAX_SCENES at once, freed after SCENE_LIFE or when the camera
##    is far away.
##  * DOWNED PILOTS. A parachuting pilot who lands on land gets 2-4 captors walking up to him; he stands with a raised
##    hand (WAVE) when the captors are of the other side ("captured"), or chats to them when they are his own.
##  * LOW PASSES. The player's aircraft below 60 m: friendly civilians and ground crew within 150 m of it stop, turn to
##    it and WAVE for a few seconds; while the player is firing, friendly people within 130 m run away from the
##    aircraft. Enemy people dive for cover through the existing AirfieldPeople.Driver. A scan at ~8 Hz over the people
##    MultiMeshes within 400 m (group "people_mm"), working on cached per-person arrays: no per-frame allocation.
##
## The figure shader walks a beat there and back from the time `TIME`; to make a runner start at his place and STOP at
## the ring, the instance's phase is chosen so that the beat begins at the moment of launch. That needs the shader's
## TIME, which scripts cannot read, so a tiny SubViewport probe samples it once (and again after 2 minutes) and the
## manager then follows it with the frame steps (see shader_time()). Without a renderer (headless tests) the engine
## tick clock stands in.

const MAN: float = AirfieldPeople.MAN
const MAX_SCENES: int = 4
const SCENE_LIFE: float = 420.0          # s a crash scene stays before it is cleared away
const FAR_REMOVE: float = 3200.0         # m from the camera at which a scene is dropped (after 20 s)
const SPAWN_RANGE: float = 6000.0        # crashes further than this from the camera are not staged
const RUN_SPEED: float = 4.6             # m/s over the ground
const RING_MIN: float = 25.0
const RING_MAX: float = 40.0
const ROAD_RANGE: float = 220.0          # an ambulance comes if a road passes this close to the wreck
const RIG_SPEED: float = 11.0
const WAVE_RANGE: float = 150.0
const WAVE_ALT: float = 60.0
const STRAFE_RANGE: float = 130.0
const SCAN_RANGE: float = 400.0
const SCAN_EVERY: float = 0.12
## figures that stand still and may be turned into a waver or a runner: TALK, WORK, SIT, SMOKER, QUEUE, CHAT
const STAY_MASK: int = (1 << 1) | (1 << 2) | (1 << 6) | (1 << 16) | (1 << 20) | (1 << 23)

static var inst: WarReactions = null
static var wave_p: float = 0.1           # chance a candidate waves in one scan (tests set 1.0)
static var _clock: float = 0.0           # sum of the frame steps seen: the shader's TIME runs at the same rate
static var _cal_clock: float = 0.0
static var _cal_time: float = 0.0
static var _cal_ok: bool = false

var scenes: Array = []                   # Gang
var test_focus: Variant = null           # tests: pretend the camera is here
var _player: Aircraft = null
var _player_t: float = 0.0
var _mms: Array = []
var _mms_t: float = 0.0
var _caches: Dictionary = {}             # MultiMeshInstance3D id -> PeopleCache
var _events: Array = []                  # [end clock, type 1 wave / 2 scatter, PeopleCache, index, local end pos, face]
var _scan_t: float = 0.0
var _probe_vp: SubViewport = null
var _probe_n: int = 0
var _probe_t1: float = -1.0
var _probe_c1: float = 0.0
var last_road_d: float = -1.0            # distance to the road the ambulance uses (debug output), -1 none


# ------------------------------------------------------------------ entry points

## Who stands about on this ground: the side that holds it, except that Axis-side ground in the liberation / 1945
## eras is Allied-held.
static func crew_team_for(side: String, band: String) -> String:
	if side == "Axis" and (band == "liberation" or band == "1945"):
		return "Allies"
	return side


static func crew_team(pos: Vector3) -> String:
	return crew_team_for(GroundKit.side_at(pos), EraClock.band())


## A downed airman is a prisoner when the people who find him are of the other side.
static func is_captured(pilot_team: String, crew: String) -> bool:
	return pilot_team != "" and pilot_team != crew


static func manager() -> WarReactions:
	if inst != null and is_instance_valid(inst):
		return inst
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return null
	var m := WarReactions.new()
	m.name = "WarReactions"
	tree.current_scene.add_child(m)
	return m


## Hook: an aircraft has just crashed on land at `pos` (Aircraft._spawn_crash_fx).
static func on_crash(pos: Vector3, team: String) -> void:
	var m: WarReactions = manager()
	if m != null:
		m.call_deferred("begin_crash", pos, team)


## Hook: a parachuting pilot of `team` has landed on land at `pos` (Parachute).
static func on_pilot_down(pos: Vector3, team: String) -> void:
	var m: WarReactions = manager()
	if m != null:
		m.call_deferred("begin_pilot", pos, team)


## The shader's TIME now (seconds, wrapped at the 3600 s rollover).
static func shader_time() -> float:
	return fmod(_cal_time + (_clock - _cal_clock), 3600.0)


func _enter_tree() -> void:
	inst = self
	if not _cal_ok:
		_cal_time = fmod(float(Time.get_ticks_msec()) / 1000.0, 3600.0)
		_cal_clock = _clock


func _exit_tree() -> void:
	for g in scenes:
		(g as Gang).free_all()
	scenes.clear()
	if inst == self:
		inst = null


# ------------------------------------------------------------------ the people of one scene

class Gang extends RefCounted:
	var mi: MultiMeshInstance3D = null
	var mm: MultiMesh = null
	var driver: Node = null
	var origin := Vector3.ZERO           # the MultiMeshInstance3D's position (y 0)
	var focus := Vector3.ZERO            # the wreck, or the pilot
	var born: float = 0.0
	var life: float = 420.0
	var is_pilot: bool = false
	var n: int = 0
	var state := PackedInt32Array()      # 0 not yet started, 1 running in, 2 arrived
	var t_start := PackedFloat32Array()
	var a_pos := PackedVector3Array()    # world start
	var b_pos := PackedVector3Array()    # world arrival
	var dress := PackedInt32Array()
	var soldier := PackedByteArray()
	var end_kind := PackedInt32Array()
	var run_t := PackedFloat32Array()
	var run_dur := PackedFloat32Array()
	var off0 := PackedFloat32Array()
	var cur_pos := PackedVector3Array()   # what each figure is doing now, mirrored on the CPU (nothing can be read
	var cur_code := PackedInt32Array()    # back from a MultiMesh under the headless renderer, so the tests use these)
	var pilot_code: int = 0
	var pilot_mi: MultiMeshInstance3D = null
	var pilot_xf := Transform3D.IDENTITY
	var pilot_t: float = 0.0
	var pilot_shown: bool = false
	var rig: MeshInstance3D = null
	var rig_pts := PackedVector2Array()
	var rig_cum := PackedFloat32Array()
	var rig_s: float = 0.0
	var rig_end: float = 0.0
	var rig_dir: float = 1.0
	var rig_t: float = 0.0
	var rig_done: bool = false

	func arrived() -> int:
		var k: int = 0
		for i in n:
			if state[i] == 2:
				k += 1
		return k

	func free_all() -> void:
		for node in [mi, pilot_mi, rig]:
			if node != null and is_instance_valid(node):
				(node as Node).queue_free()


class PeopleCache extends RefCounted:
	var mi: MultiMeshInstance3D = null
	var team: String = ""
	var driver: Node = null
	var n: int = 0
	var built: int = 0
	var pos := PackedVector3Array()      # local to the MultiMeshInstance3D
	var code := PackedInt32Array()
	var state := PackedByteArray()       # 0 idle, 1 waving, 2 running away
	var orig_xf: Dictionary = {}
	var orig_col: Dictionary = {}
	var orig_code: Dictionary = {}

	## Fill the cache from known data instead of reading the MultiMesh (the tests).
	func feed(p: PackedVector3Array, c: PackedInt32Array) -> void:
		for i in mini(n, p.size()):
			pos[i] = p[i]
			code[i] = c[i]
		built = mini(n, p.size())


# ------------------------------------------------------------------ placing people

static func _spot_ok(x: float, z: float) -> bool:
	if GroundKit.is_water(x, z):
		return false
	var gy: float = GroundKit.ground_y(x, z)
	return Obstacles.hit(Vector3(x, gy, z), 0.9, gy + 0.3, gy + 2.0).is_empty()


static func _line_ok(a: Vector3, b: Vector3) -> bool:
	var d: float = Vector2(b.x - a.x, b.z - a.z).length()
	var steps: int = int(d / 7.0) + 1
	for k in range(1, steps + 1):
		var f: float = float(k) / float(steps)
		if not _spot_ok(lerpf(a.x, b.x, f), lerpf(a.z, b.z, f)):
			return false
	return absf(GroundKit.ground_y(b.x, b.z) - GroundKit.ground_y(a.x, a.z)) < 8.0


## Outfit for the n-th person of a scene: [dress, soldier]. British ground: Home Guard and a constable first, then ARP
## wardens, soldiers and civilians; German ground: mostly soldiers with a few civilians.
static func pick_dress(side: String, rng: RandomNumberGenerator, first: bool) -> Vector2i:
	if side == "Axis":
		if rng.randf() < 0.78:
			return Vector2i(rng.randi() % 4, 1)
		return Vector2i(AirfieldPeople.CIV_SUIT + rng.randi() % 4, 0)
	var r: float = rng.randf()
	if first or r < 0.16:
		return Vector2i(AirfieldPeople.CIV_HOME_GUARD, 1) if rng.randf() < 0.5 else Vector2i(AirfieldPeople.CIV_POLICE, 0)
	if r < 0.26:
		return Vector2i(AirfieldPeople.CIV_ARP, 0)
	if r < 0.36:
		return Vector2i(rng.randi() % 4, 1)
	return Vector2i(AirfieldPeople.CIV_SUIT + rng.randi() % 5, 0)


static func pick_end_kind(rng: RandomNumberGenerator) -> int:
	var r: float = rng.randf()
	if r < 0.5:
		return AirfieldPeople.Kind.TALK
	if r < 0.7:
		return AirfieldPeople.Kind.CHAT
	if r < 0.85:
		return AirfieldPeople.Kind.WAVE
	return AirfieldPeople.Kind.SMOKER


## A start and an arrival point on the same bearing from `focus`: arrival at r_min..r_max, start s_min..s_max out,
## both on dry ground clear of buildings, the run between them clear too, and the arrival not crowding the ones
## already taken. Returns [start, arrival] or an empty array.
static func find_route(rng: RandomNumberGenerator, focus: Vector3, r_min: float, r_max: float, s_min: float, s_max: float, taken: PackedVector3Array) -> Array:
	for tries in 14:
		var ang: float = rng.randf() * TAU
		var dir := Vector3(sin(ang), 0.0, cos(ang))
		var r: float = rng.randf_range(r_min, r_max)
		var a: Vector3 = focus + dir * r
		var crowd: bool = false
		for t in taken:
			if Vector2(t.x - a.x, t.z - a.z).length() < 3.2:
				crowd = true
				break
		if crowd:
			continue
		var s: Vector3 = focus + dir * rng.randf_range(s_min, s_max)
		if not _spot_ok(a.x, a.z) or not _spot_ok(s.x, s.z) or not _line_ok(s, a):
			continue
		return [s, a]
	return []


## Put figure `i` on a run from p0 to p1 (both local to the MultiMesh) starting NOW: the beat's phase is picked so the
## stride begins at p0 at shader time `t_eff`. Returns how long the run takes in seconds.
static func launch_run(mm: MultiMesh, i: int, p0: Vector3, p1: Vector3, dress: int, soldier: bool, t_eff: float) -> float:
	var dv: Vector3 = (p1 - p0).normalized()
	var len_m: float = p0.distance_to(p1) / MAN
	var spd: float = RUN_SPEED / MAN
	var period: float = 2.0 * (len_m + 1.2 * spd) / spd          # RUN's turn-round pause is 1.2 * speed
	var ph: float = (ceilf(t_eff / period) * period - t_eff) / 61.0
	mm.set_instance_transform(i, Transform3D(Basis.looking_at(dv, Vector3.UP).scaled(Vector3.ONE * MAN), p0))
	mm.set_instance_custom_data(i, Color(len_m, spd, ph, float(AirfieldPeople.code_of(AirfieldPeople.Kind.RUN, soldier, dress))))
	return len_m / spd


## Stand figure `i` still at local `p`, facing the horizontal direction `face`.
static func place_still(mm: MultiMesh, i: int, p: Vector3, face: Vector3, kind: int, dress: int, soldier: bool, ph: float) -> void:
	var f := Vector3(face.x, 0.0, face.z)
	if f.length() < 0.01:
		f = Vector3(0.0, 0.0, -1.0)
	mm.set_instance_transform(i, Transform3D(Basis.looking_at(f.normalized(), Vector3.UP).scaled(Vector3.ONE * MAN), p))
	mm.set_instance_custom_data(i, Color(0.0, 1.4, ph, float(AirfieldPeople.code_of(kind, soldier, dress))))


func _hide(mm: MultiMesh, i: int) -> void:
	mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, -3000.0, 0.0)))


## Builds the MultiMesh and the schedule for `want` people converging on `focus`.
func _make_gang(focus: Vector3, crew: String, want: int, rng: RandomNumberGenerator, r_min: float, r_max: float, s_min: float, s_max: float, first_delay: float, gap: float, pilot: bool) -> Gang:
	var g := Gang.new()
	g.focus = focus
	g.is_pilot = pilot
	g.born = _clock
	g.life = SCENE_LIFE
	g.origin = Vector3(focus.x, 0.0, focus.z)
	var taken := PackedVector3Array()
	var men: Array = []
	for k in want:
		var rt: Array = find_route(rng, focus, r_min, r_max, s_min, s_max, taken)
		if rt.is_empty():
			continue
		var dr: Vector2i = pick_dress(crew, rng, k == 0)
		var b: Vector3 = rt[1]
		taken.append(b)
		g.a_pos.append(rt[0])
		g.b_pos.append(b)
		g.dress.append(dr.x)
		g.soldier.append(dr.y)
		g.end_kind.append(pick_end_kind(rng) if not pilot else (AirfieldPeople.Kind.TALK if rng.randf() < 0.7 else AirfieldPeople.Kind.CHAT))
		g.t_start.append(first_delay + float(k) * gap + rng.randf_range(0.0, gap))
		var gy: float = GroundKit.ground_y(b.x, b.z)
		men.append([b, focus - b, AirfieldPeople.Kind.TALK, 0.0, -1.0, 0.0, dr.y == 1, null, 0.0, gy, gy, dr.x])
	g.n = men.size()
	if g.n == 0:
		return null
	g.state.resize(g.n)
	g.run_t.resize(g.n)
	g.run_dur.resize(g.n)
	g.off0.resize(g.n)
	g.cur_pos.resize(g.n)
	g.cur_code.resize(g.n)
	var mi: MultiMeshInstance3D = AirfieldPeople.spawn(self, men, g.origin, crew, hash(Vector2(focus.x, focus.z)), "", true)
	if mi == null:
		return null
	mi.name = "CrashPeople" if not pilot else "CaptorPeople"
	mi.remove_from_group("people_mm")        # the reaction scan leaves a scene's people alone
	mi.set_meta("crew", crew)
	g.mi = mi
	g.mm = mi.multimesh
	g.driver = mi.get_node_or_null("Driver")
	g.mm.custom_aabb = AABB(Vector3(-230.0, -30.0, -230.0), Vector3(460.0, 160.0, 460.0))
	for i in g.n:
		_hide(g.mm, i)
		g.cur_pos[i] = Vector3(0.0, -3000.0, 0.0)
		g.cur_code[i] = AirfieldPeople.code_of(AirfieldPeople.Kind.TALK, g.soldier[i] == 1, g.dress[i])
	return g


func _focus_pos() -> Variant:
	if test_focus != null:
		return test_focus
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		return cam.global_position
	var p: Aircraft = _find_player()
	return p.global_position if p != null else null


func _far(pos: Vector3, d: float) -> bool:
	var f: Variant = _focus_pos()
	if f == null:
		return false
	var fv: Vector3 = f
	return Vector2(fv.x - pos.x, fv.z - pos.z).length() > d


func _trim(keep: int) -> void:
	while scenes.size() > keep:
		(scenes[0] as Gang).free_all()
		scenes.remove_at(0)


## An aircraft has come down at `pos`: stage the scene (see the class comment).
func begin_crash(pos: Vector3, _aircraft_team: String, force: bool = false) -> void:
	if not force and _far(pos, SPAWN_RANGE):
		return
	if GroundKit.is_water(pos.x, pos.z):
		return
	_trim(MAX_SCENES - 1)
	_probe_start()
	var crew: String = crew_team(pos)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2(pos.x, pos.z)) + 77
	var want: int = clampi(int(round(6.0 * AirfieldPeople.density())) + rng.randi_range(0, 2), 4, 16)
	var g: Gang = _make_gang(pos, crew, want, rng, RING_MIN, RING_MAX, 70.0, 170.0, 5.0, 3.0, false)
	if g == null:
		return
	_add_rig(g, pos, crew)
	scenes.append(g)
	print("[war-reactions] crash scene at %.0f,%.0f: %d people (%s ground)%s" % [pos.x, pos.z, g.n, crew, (", ambulance from a road %.0f m away" % last_road_d) if g.rig != null else ", no road within %.0f m" % ROAD_RANGE])


## A pilot has landed at `pos`.
func begin_pilot(pos: Vector3, pilot_team: String, force: bool = false) -> void:
	if not force and _far(pos, SPAWN_RANGE):
		return
	if GroundKit.is_water(pos.x, pos.z):
		return
	_trim(MAX_SCENES - 1)
	_probe_start()
	var crew: String = crew_team(pos)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2(pos.x, pos.z)) + 191
	var g: Gang = _make_gang(pos, crew, rng.randi_range(2, 4), rng, 5.0, 9.0, 50.0, 110.0, 4.0, 2.5, true)
	if g == null:
		return
	g.life = 240.0
	var captured: bool = is_captured(pilot_team, crew)
	var gy: float = GroundKit.ground_y(pos.x, pos.z)
	var pmen: Array = [[pos, g.a_pos[0] - pos, AirfieldPeople.Kind.WAVE if captured else AirfieldPeople.Kind.TALK, 0.0, -1.0, 0.0, false, null, 0.0, gy, gy, 0]]
	var pmi: MultiMeshInstance3D = AirfieldPeople.spawn(self, pmen, g.origin, pilot_team if pilot_team != "" else "Allies", hash(Vector2(pos.x, pos.z)) + 5, "", true)
	if pmi != null:
		pmi.name = "DownedPilot"
		pmi.remove_from_group("people_mm")
		g.pilot_mi = pmi
		g.pilot_xf = pmi.multimesh.get_instance_transform(0)
		g.pilot_t = 6.2                      # the canopy lies about 6 s before it is gone
		g.pilot_code = AirfieldPeople.code_of(AirfieldPeople.Kind.WAVE if captured else AirfieldPeople.Kind.TALK, false, 0)
		pmi.multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(0.0, -3000.0, 0.0)))
		pmi.multimesh.custom_aabb = AABB(Vector3(-20.0, -3100.0, -20.0), Vector3(40.0, 3200.0, 40.0))
	scenes.append(g)
	print("[war-reactions] downed pilot (%s) at %.0f,%.0f: %d captors (%s ground)%s" % [pilot_team, pos.x, pos.z, g.n, crew, ", captured" if captured else ""])


# ------------------------------------------------------------------ the ambulance

## Distance along a polyline's arc length `s`: position (x, 0, z) and the unit tangent.
static func path_point(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Array:
	var last: int = pts.size() - 1
	var k: int = clampi(cum.bsearch(s) - 1, 0, last - 1)
	var a: Vector2 = pts[k]
	var b: Vector2 = pts[k + 1]
	var sl: float = maxf(cum[k + 1] - cum[k], 0.001)
	var f: float = clampf((s - cum[k]) / sl, 0.0, 1.0)
	var p: Vector2 = a.lerp(b, f)
	var t: Vector2 = (b - a).normalized()
	return [Vector3(p.x, 0.0, p.y), Vector3(t.x, 0.0, t.y)]


func _add_rig(g: Gang, pos: Vector3, crew: String) -> void:
	last_road_d = -1.0
	if not RoadMesh.has_roads():
		return
	var c2 := Vector2(pos.x, pos.z)
	var best_d: float = ROAD_RANGE
	var best: Dictionary = {}
	var best_s: float = 0.0
	for r in RoadMesh.routes_in_rect(c2, ROAD_RANGE + 60.0):
		var rd: Dictionary = r
		if str(rd["k"]) == "rail":
			continue
		var pts: PackedVector2Array = rd["pts"]
		var cum: PackedFloat32Array = rd["cum"]
		for k in range(pts.size() - 1):
			var a: Vector2 = pts[k]
			var ab: Vector2 = pts[k + 1] - a
			var l2: float = ab.length_squared()
			if l2 < 0.01:
				continue
			var f: float = clampf((c2 - a).dot(ab) / l2, 0.0, 1.0)
			var d: float = (a + ab * f).distance_to(c2)
			if d < best_d:
				best_d = d
				best = rd
				best_s = cum[k] + f * sqrt(l2)
	if best.is_empty():
		return
	last_road_d = best_d
	var total: float = float(best["len"])
	var back: float = minf(best_s, 280.0)
	var fwd: float = minf(total - best_s, 280.0)
	if maxf(back, fwd) < 90.0:
		return
	g.rig_pts = best["pts"]
	g.rig_cum = best["cum"]
	g.rig_end = best_s
	if back >= fwd:
		g.rig_dir = 1.0
		g.rig_s = best_s - back
	else:
		g.rig_dir = -1.0
		g.rig_s = best_s + fwd
	var mi := MeshInstance3D.new()
	mi.name = "CrashAmbulance"
	mi.mesh = AirfieldPeople.ambulance_mesh(crew)
	mi.visibility_range_end = 1400.0
	mi.visible = false
	add_child(mi)
	g.rig = mi


func _tick_rig(g: Gang, age: float, delta: float) -> void:
	if g.rig == null or not is_instance_valid(g.rig) or g.rig_done or age < 14.0:
		return
	g.rig.visible = true
	var left: float = absf(g.rig_end - g.rig_s)
	var v: float = clampf(sqrt(2.5 * left), 1.5, RIG_SPEED)
	g.rig_s += g.rig_dir * minf(v * delta, left)
	if left < 0.6:
		g.rig_done = true
	var pt: Array = path_point(g.rig_pts, g.rig_cum, g.rig_s)
	var p: Vector3 = pt[0]
	var t: Vector3 = (pt[1] as Vector3) * g.rig_dir
	var side: Vector3 = t.cross(Vector3.UP) * (-1.6 if g.mi != null and g.mi.get_meta("crew", "Allies") != "Axis" else 1.6)
	p += side
	p.y = GroundKit.ground_y(p.x, p.z) + 0.02
	g.rig.global_transform = Transform3D(Basis.looking_at(t, Vector3.UP).scaled(Vector3.ONE * AirfieldPeople.SCALE), p)


# ------------------------------------------------------------------ the clock and the per-frame work

func _process(delta: float) -> void:
	step(delta)


## One frame of the whole manager (the tests call this directly with a chosen step).
func step(delta: float) -> void:
	_probe_tick()
	_clock += delta
	for k in range(scenes.size() - 1, -1, -1):
		var g: Gang = scenes[k]
		if not _tick_gang(g, delta):
			g.free_all()
			scenes.remove_at(k)
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_EVERY
		_scan_frame()


func _drv_off(drv: Node) -> float:
	return float(drv.get("_off")) if drv != null and is_instance_valid(drv) else 0.0


## False when the scene is over (too old, or the camera is far away).
func _tick_gang(g: Gang, delta: float) -> bool:
	if g.mi == null or not is_instance_valid(g.mi):
		return false
	var age: float = _clock - g.born
	if age > g.life or (age > 20.0 and _far(g.focus, FAR_REMOVE)):
		return false
	var off_now: float = _drv_off(g.driver)
	for i in g.n:
		if g.state[i] == 0 and age >= g.t_start[i]:
			g.off0[i] = off_now
			g.run_dur[i] = launch_run(g.mm, i, _local(g, g.a_pos[i]), _local(g, g.b_pos[i]), g.dress[i], g.soldier[i] == 1, shader_time() - off_now)
			g.run_t[i] = _clock
			g.state[i] = 1
			g.cur_pos[i] = _local(g, g.a_pos[i])
			g.cur_code[i] = AirfieldPeople.code_of(AirfieldPeople.Kind.RUN, g.soldier[i] == 1, g.dress[i])
		elif g.state[i] == 1 and (_clock - g.run_t[i]) - (off_now - g.off0[i]) >= g.run_dur[i]:
			g.state[i] = 2
			var b: Vector3 = _local(g, g.b_pos[i])
			place_still(g.mm, i, b, g.focus - g.b_pos[i], g.end_kind[i], g.dress[i], g.soldier[i] == 1, float(i) * 0.37)
			g.cur_pos[i] = b
			g.cur_code[i] = AirfieldPeople.code_of(g.end_kind[i], g.soldier[i] == 1, g.dress[i])
	if g.pilot_mi != null and is_instance_valid(g.pilot_mi) and not g.pilot_shown and age >= g.pilot_t:
		g.pilot_shown = true
		g.pilot_mi.multimesh.set_instance_transform(0, g.pilot_xf)
	_tick_rig(g, age, delta)
	return true


func _local(g: Gang, w: Vector3) -> Vector3:
	return Vector3(w.x - g.origin.x, GroundKit.ground_y(w.x, w.z) + 0.01, w.z - g.origin.z)


# ------------------------------------------------------------------ the shader-time probe

func _probe_start() -> void:
	if _probe_vp != null or DisplayServer.get_name() == "headless":
		return
	if _cal_ok and _clock - _cal_clock < 120.0:
		return
	_probe_vp = SubViewport.new()
	_probe_vp.size = Vector2i(8, 8)
	_probe_vp.disable_3d = true
	_probe_vp.transparent_bg = false
	_probe_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cr := ColorRect.new()
	cr.size = Vector2(8.0, 8.0)
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(TIME / 3600.0, fract(TIME / 16.0), fract(TIME), 1.0); }\n"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	cr.material = sm
	_probe_vp.add_child(cr)
	add_child(_probe_vp)
	_probe_n = 0
	_probe_t1 = -1.0


## The shader time a probe pixel carries: red the coarse time, green its position within 16 s, blue within 1 s.
static func decode_time(c: Color) -> float:
	var coarse: float = c.r * 3600.0
	var t16: float = c.g * 16.0
	var t: float = roundf((coarse - t16) / 16.0) * 16.0 + t16
	return roundf(t - c.b) + c.b


func _probe_tick() -> void:
	if _probe_vp == null:
		return
	_probe_n += 1
	if _probe_n < (4 if _probe_t1 < 0.0 else 40):
		return
	var img: Image = _probe_vp.get_texture().get_image()
	if img == null or img.is_empty():
		_probe_free()
		return
	var t: float = decode_time(img.get_pixel(4, 4))
	if _probe_t1 < 0.0:
		_probe_t1 = t
		_probe_c1 = _clock
		_cal_time = t
		_cal_clock = _clock
		_cal_ok = true
		_probe_n = 0
		return
	var drift: float = (t - _probe_t1) - (_clock - _probe_c1)
	if absf(drift) < 0.15:
		_cal_time = t
		_cal_clock = _clock
		_cal_ok = true
		print("[war-reactions] shader time probe ok: TIME %.2f, drift %.3f s over %.1f s" % [t, drift, _clock - _probe_c1])
	else:
		_cal_ok = false
		print("[war-reactions] shader time probe inconsistent (%.2f s drift): runners may stop early or late" % drift)
	_probe_free()


func _probe_free() -> void:
	if _probe_vp != null and is_instance_valid(_probe_vp):
		_probe_vp.queue_free()
	_probe_vp = null


# ------------------------------------------------------------------ reactions of people to the player's aircraft

func _find_player() -> Aircraft:
	if _player != null and is_instance_valid(_player) and _clock - _player_t < 2.0:
		return _player
	_player_t = _clock
	_player = null
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group("aircraft"):
			var a := n as Aircraft
			if a != null and a.player_controlled:
				_player = a
				break
	return _player


func _scan_frame() -> void:
	var p: Aircraft = _find_player()
	if p == null or p.state != Aircraft.State.ALIVE:
		_expire()
		return
	scan_at(p.global_position, p.altitude_agl, p.team, p.cmd_fire and not p.on_ground)


## One scan of the people around an aircraft at `pp` (height above the ground `agl`, side `ptm`, guns firing or not):
## those close to a low pass wave, those close to firing run away. Also finishes the waves and runs that are due.
func scan_at(pp: Vector3, agl: float, ptm: String, firing: bool) -> void:
	_expire()
	var low: bool = agl < WAVE_ALT
	if not low and not (firing and agl < 350.0):
		return
	if (_mms.is_empty() or _clock - _mms_t > 2.0) and is_inside_tree():
		_mms_t = _clock
		_mms = get_tree().get_nodes_in_group("people_mm")
	var waved: int = 0
	var ran: int = 0
	for node in _mms:
		var mi := node as MultiMeshInstance3D
		if mi == null or not is_instance_valid(mi) or not mi.is_inside_tree() or mi.multimesh == null:
			continue
		var bb: AABB = mi.multimesh.custom_aabb
		var gp: Vector3 = mi.global_position
		var c: Vector3 = gp + bb.get_center()
		if Vector2(c.x - pp.x, c.z - pp.z).length() > SCAN_RANGE + bb.size.length() * 0.5:
			continue
		var pc: PeopleCache = _cache_for(mi)
		_fill_cache(pc, 160)
		for i in pc.built:
			if pc.state[i] != 0 or ((STAY_MASK >> (pc.code[i] / 64)) & 1) == 0:
				continue
			var dx: float = gp.x + pc.pos[i].x - pp.x
			var dz: float = gp.z + pc.pos[i].z - pp.z
			var d2: float = dx * dx + dz * dz
			if d2 > WAVE_RANGE * WAVE_RANGE or not _friendly(pc, i, ptm):
				continue
			if firing and d2 < STRAFE_RANGE * STRAFE_RANGE:
				if ran < 4 and _scatter(pc, i, gp, Vector3(dx, 0.0, dz)):
					ran += 1
			elif low and waved < 3 and randf() < wave_p:
				_wave(pc, i, gp, pp)
				waved += 1


func _cache_for(mi: MultiMeshInstance3D) -> PeopleCache:
	var id: int = mi.get_instance_id()
	if _caches.has(id):
		return _caches[id]
	var pc := PeopleCache.new()
	pc.mi = mi
	pc.n = mi.multimesh.instance_count
	pc.driver = mi.get_node_or_null("Driver")
	pc.team = str(pc.driver.get("team")) if pc.driver != null else ""
	pc.pos.resize(pc.n)
	pc.code.resize(pc.n)
	pc.state.resize(pc.n)
	_caches[id] = pc
	if _caches.size() > 40:                  # forget the ones whose tiles have gone
		for k in _caches.keys():
			if not is_instance_valid((_caches[k] as PeopleCache).mi):
				_caches.erase(k)
	return pc


## Reads up to `budget` more people of a MultiMesh into the cache (the first sight of a big town spreads over scans).
func _fill_cache(pc: PeopleCache, budget: int) -> void:
	var mm: MultiMesh = pc.mi.multimesh
	while pc.built < pc.n and budget > 0:
		pc.pos[pc.built] = mm.get_instance_transform(pc.built).origin
		pc.code[pc.built] = int(mm.get_instance_custom_data(pc.built).a + 0.5)
		pc.built += 1
		budget -= 1


## Friendly to an aircraft of side `ptm`: crews and soldiers of that side; civilians everywhere for the Allies and
## in German-held places for the Axis too.
func _friendly(pc: PeopleCache, i: int, ptm: String) -> bool:
	var cd: int = pc.code[i]
	var civ: bool = AirfieldPeople.dress_of(cd) >= 8 and not AirfieldPeople.soldier_of(cd)
	if civ:
		return ptm == "Allies" or pc.team == "Axis"
	return pc.team == ptm


func _wave(pc: PeopleCache, i: int, gp: Vector3, pp: Vector3) -> void:
	var mm: MultiMesh = pc.mi.multimesh
	var xf: Transform3D = mm.get_instance_transform(i)
	xf.origin = pc.pos[i]
	var col: Color = mm.get_instance_custom_data(i)
	col.a = float(pc.code[i])
	pc.orig_xf[i] = xf
	pc.orig_col[i] = col
	pc.orig_code[i] = pc.code[i]
	var to := Vector3(pp.x - gp.x - xf.origin.x, 0.0, pp.z - gp.z - xf.origin.z)
	if to.length() > 1.0:
		mm.set_instance_transform(i, Transform3D(Basis.looking_at(to.normalized(), Vector3.UP).scaled(xf.basis.get_scale()), xf.origin))
	var cd: int = int(col.a + 0.5)
	mm.set_instance_custom_data(i, Color(col.r, col.g, col.b, float(AirfieldPeople.code_of(AirfieldPeople.Kind.WAVE, AirfieldPeople.soldier_of(cd), AirfieldPeople.dress_of(cd)))))
	pc.code[i] = AirfieldPeople.code_of(AirfieldPeople.Kind.WAVE, AirfieldPeople.soldier_of(cd), AirfieldPeople.dress_of(cd))
	pc.state[i] = 1
	_events.append([_clock + randf_range(3.5, 5.5), 1, pc, i, Vector3.ZERO, Vector3.ZERO])


## Run away from the aircraft (`away` is the horizontal vector from it to the person). False if nowhere clear to run.
func _scatter(pc: PeopleCache, i: int, gp: Vector3, away: Vector3) -> bool:
	var mm: MultiMesh = pc.mi.multimesh
	var xf: Transform3D = mm.get_instance_transform(i)
	xf.origin = pc.pos[i]
	var base: Vector3 = away.normalized() if away.length() > 0.5 else Vector3(randf() - 0.5, 0.0, randf() - 0.5).normalized()
	var w0: Vector3 = gp + xf.origin
	for attempt in 3:
		var dir: Vector3 = base.rotated(Vector3.UP, 0.0 if attempt == 0 else (0.7 if attempt == 1 else -0.7))
		var w1: Vector3 = w0 + dir * randf_range(20.0, 32.0)
		if not _line_ok(w0, w1):
			continue
		var col: Color = mm.get_instance_custom_data(i)
		col.a = float(pc.code[i])
		var cd: int = pc.code[i]
		var p1 := Vector3(xf.origin.x + (w1.x - w0.x), xf.origin.y + (GroundKit.ground_y(w1.x, w1.z) - GroundKit.ground_y(w0.x, w0.z)), xf.origin.z + (w1.z - w0.z))
		pc.orig_xf[i] = xf
		pc.orig_col[i] = col
		pc.orig_code[i] = pc.code[i]
		var off: float = _drv_off(pc.driver)
		var dur: float = launch_run(mm, i, xf.origin, p1, AirfieldPeople.dress_of(cd), AirfieldPeople.soldier_of(cd), shader_time() - off)
		pc.state[i] = 2
		pc.code[i] = AirfieldPeople.code_of(AirfieldPeople.Kind.RUN, AirfieldPeople.soldier_of(cd), AirfieldPeople.dress_of(cd))
		_events.append([_clock + dur, 2, pc, i, p1, dir])
		return true
	return false


## Finishes waves (back to what they were doing) and runs (crouched where they stopped).
func _expire() -> void:
	for k in range(_events.size() - 1, -1, -1):
		var e: Array = _events[k]
		if _clock < float(e[0]):
			continue
		_events.remove_at(k)
		var pc: PeopleCache = e[2]
		if pc == null or not is_instance_valid(pc.mi) or pc.mi.multimesh == null:
			continue
		var i: int = int(e[3])
		var mm: MultiMesh = pc.mi.multimesh
		if int(e[1]) == 1:
			mm.set_instance_transform(i, pc.orig_xf[i])
			mm.set_instance_custom_data(i, pc.orig_col[i])
			pc.code[i] = pc.orig_code[i]
			pc.state[i] = 0
		else:
			var cd: int = int(pc.orig_code[i])
			place_still(mm, i, e[4], e[5], AirfieldPeople.Kind.WORK, AirfieldPeople.dress_of(cd), AirfieldPeople.soldier_of(cd), randf())
			pc.pos[i] = e[4]
			pc.code[i] = AirfieldPeople.code_of(AirfieldPeople.Kind.WORK, AirfieldPeople.soldier_of(cd), AirfieldPeople.dress_of(cd))
			pc.state[i] = 0
		pc.orig_xf.erase(i)
		pc.orig_col.erase(i)
		pc.orig_code.erase(i)


# ------------------------------------------------------------------ debug: --crash-scene-demo

## Stages a crash at `pos` and points a camera at it. mode "close" (about 38 m, ground level) or "far" (150 m, raised).
static func demo(host: Node, pos: Vector3, mode: String) -> void:
	if mode.ends_with("+road"):               # put the wreck 45 m off the nearest road within 2.5 km (to see the ambulance)
		mode = mode.trim_suffix("+road")
		var best_d: float = 2500.0
		var c2 := Vector2(pos.x, pos.z)
		if RoadMesh.has_roads():
			for r in RoadMesh.routes_in_rect(c2, 2500.0):
				var pts: PackedVector2Array = (r as Dictionary)["pts"]
				for k in range(0, pts.size() - 1):
					var ab: Vector2 = pts[k + 1] - pts[k]
					if ab.length() < 5.0:
						continue
					var q: Vector2 = pts[k] + ab * clampf((c2 - pts[k]).dot(ab) / ab.length_squared(), 0.0, 1.0)
					var d: float = q.distance_to(c2)
					if d < best_d:
						var tg: Vector2 = ab.normalized()
						var spot := Vector3(q.x - tg.y * 45.0, 0.0, q.y + tg.x * 45.0)
						if not GroundKit.is_water(spot.x, spot.z):
							best_d = d
							pos = spot
	pos.y = GroundKit.ground_y(pos.x, pos.z)
	var m: WarReactions = manager()
	if m == null:
		return
	FX.crash_explosion(pos, false)
	m.begin_crash(pos, "Allies", true)
	var cam := CrashShot.new()
	cam.target = pos
	cam.mode = mode
	host.add_child(cam)


class CrashShot extends Camera3D:
	var target := Vector3.ZERO
	var mode: String = "close"

	func _ready() -> void:
		fov = 62.0
		process_priority = 500                 # after the game's own camera has had its say this frame
		make_current()
		RenderingServer.frame_pre_draw.connect(_retake)     # a chase camera can be made current at any point of a frame

	func _retake() -> void:
		if is_inside_tree() and not current:
			make_current()

	func _process(_delta: float) -> void:
		var back: float = 38.0 if mode == "close" else 150.0
		var up: float = 2.6 if mode == "close" else 34.0
		var ang: float = 0.9
		var cp: Vector3 = target + Vector3(sin(ang) * back, up, cos(ang) * back)
		cp.y = maxf(cp.y, GroundKit.ground_y(cp.x, cp.z) + 2.0)
		global_position = cp
		look_at(target + Vector3(0.0, 1.2 if mode == "close" else 0.0, 0.0), Vector3.UP)
		if not current:
			make_current()
