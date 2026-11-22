extends Node3D
## Air-dropped torpedo (Beaufort 18 in Mk XII, He 111 LT F5b). One node per torpedo, created by Weapons.drop_torpedo and
## ticked by its own _physics_process; WeaponWorld only keeps the registry (`Weapons.torpedoes`).
##
## Phases: AIR (falls with the air tail's slight nose-down pitch and a small wobble) -> water entry (splash column and
## ring, then a dive that is deeper the higher / faster / steeper it was dropped, and a recovery to the set depth) ->
## RUN (underwater at the set depth, straight, with a bubble wake on the surface behind it) -> end (hit / aground /
## ran out / dud).
## Release limits (Torpedo.evaluate_release): within them it runs; a little outside it porpoises (deep dive, late
## recovery, and a dud if the sea is too shallow for the dive); far outside it breaks up on entry.
## Units: x / z in metres, y is world units (VERTICAL_SCALE 2), so heights are converted with WorldCoords.

const WorldCoordsRef := preload("res://scripts/world_coords.gd")

enum Phase { AIR, RUN, DONE }

## speeds m/s, distances m. max_alt / min_alt are metres above the sea at release.
const TYPES := {
	"mk12": {"name": "18 in Mk XII", "min_alt": 8.0, "max_alt": 30.0, "min_speed": 45.0, "max_speed": 82.0, "max_angle": 18.0,
		"run_speed": 20.0, "range": 2600.0, "arm": 250.0, "depth": 4.5, "damage": 330.0, "length": 5.3, "col": Color(0.22, 0.24, 0.26)},
	"ltf5b": {"name": "LT F5b", "min_alt": 10.0, "max_alt": 45.0, "min_speed": 50.0, "max_speed": 92.0, "max_angle": 20.0,
		"run_speed": 18.5, "range": 2200.0, "arm": 220.0, "depth": 5.0, "damage": 310.0, "length": 5.5, "col": Color(0.2, 0.22, 0.2)},
}
## Which torpedo a model carries (the stats resource also needs `torpedoes` > 0).
const FOR_MODEL := {"beaufort": "mk12", "he111": "ltf5b"}
const SEA_MIN_DEPTH := 6.0        # the seabed counts as at least this deep wherever there is water (the game's shelf is shallow)
const WAKE_LIFE := 45.0
const WAKE_MAX_PTS := 420
const WAKE_STEP := 6.0
## Hull draught by ship type (metres, before the ship scale). A torpedo running deeper than this passes under.
const DRAUGHT := {"destroyer": 3.8, "freighter": 6.0, "landing_craft": 1.5, "fishing_boat": 2.0, "collier": 6.5, "trawler": 3.0,
	"cruiser": 5.5, "battleship": 8.0, "ferry": 4.0}

var tid: String = "mk12"
var cfg: Dictionary
var team: String = "Allies"
var source: Node
var phase: int = Phase.AIR
var vel: Vector3 = Vector3.ZERO            # world units / s
var fate: String = "runs"                  # runs / porpoise / dud / breaks_up (from the release check)
var verdict: Dictionary = {}
var run_dist: float = 0.0                  # metres run underwater
var depth: float = 0.0                     # current depth below the surface (positive down)
var set_depth: float = 4.5
var dive_depth: float = 4.5
var heading: Vector3 = Vector3.FORWARD     # horizontal unit vector of the run
var entry_pos: Vector3 = Vector3.ZERO
var outcome: String = ""                   # hit / dud_hit / aground / ran_out / seabed / broke_up / ""
var hit_target: Node
var wake_active: bool = false
var age: float = 0.0
var _body: Node3D
var _wake: MeshInstance3D
var _wp := PackedVector3Array()
var _wt := PackedFloat32Array()
var _wj := PackedFloat32Array()
var _last_wp: Vector3 = Vector3(1.0e9, 0.0, 0.0)
var _wake_dirty: float = 0.0
var _bubble_t: float = 0.0
var _ships: Array = []
var _ship_t: float = 0.0
var _fall_t: float = -1.0
var _fall_pos: Vector3 = Vector3.ZERO
var _done_t: float = 0.0
var _wobble: float = randf() * TAU
var _terrain: Node
var _clock: float = 0.0

static var _shader: Shader
static var _body_mats: Dictionary = {}


# ------------------------------------------------------------------ release limits

static func type_for_model(model_id: String) -> String:
	return String(FOR_MODEL.get(model_id, ""))


## Judge a release. alt_m = metres above the sea, speed = airspeed m/s, path_deg = flight path angle (negative = diving),
## roll_deg = bank. water_depth = metres of sea under the drop. Returns {ok, status, fate, dive, heading_err_deg, problems}.
static func evaluate_release(torp_id: String, alt_m: float, speed: float, path_deg: float, roll_deg: float = 0.0, water_depth: float = 40.0) -> Dictionary:
	var t: Dictionary = TYPES.get(torp_id, TYPES["mk12"])
	var ex_alt: float = maxf(alt_m - float(t["max_alt"]), 0.0) / float(t["max_alt"])
	var ex_spd: float = maxf(speed - float(t["max_speed"]), 0.0) / float(t["max_speed"])
	var steep: float = maxf(-path_deg - float(t["max_angle"]), 0.0)
	var problems: Array = []
	if ex_alt > 0.0:
		problems.append("TOO HIGH")
	if ex_spd > 0.0:
		problems.append("TOO FAST")
	if steep > 0.0:
		problems.append("TOO STEEP")
	if alt_m < float(t["min_alt"]):
		problems.append("TOO LOW")
	if speed < float(t["min_speed"]):
		problems.append("TOO SLOW")
	var dive: float = float(t["depth"]) + 16.0 * ex_alt + 14.0 * ex_spd + 0.6 * steep
	if speed < float(t["min_speed"]):
		dive += (float(t["min_speed"]) - speed) * 0.12
	var f: String = "runs"
	if ex_alt > 0.7 or ex_spd > 0.28 or steep > 35.0:
		f = "breaks_up"
	elif dive > maxf(water_depth, SEA_MIN_DEPTH) - 1.0:
		f = "dud"
	elif dive > float(t["depth"]) + 2.5:
		f = "porpoise"
	return {"ok": problems.is_empty() or problems == ["TOO LOW"], "status": ("OK" if problems.is_empty() else String(problems[0])),
		"fate": f, "dive": dive, "heading_err_deg": clampf(absf(roll_deg) - 8.0, 0.0, 30.0) * 0.25, "problems": problems}


static func limits_text(torp_id: String) -> String:
	var t: Dictionary = TYPES.get(torp_id, TYPES["mk12"])
	return "%s: drop under %d m and %d km/h" % [t["name"], int(t["max_alt"]), int(float(t["max_speed"]) * 3.6)]


## Where a torpedo released now would enter the water, and its horizontal heading. Used by the sight.
static func predict_entry(pos: Vector3, vel_v: Vector3) -> Dictionary:
	var g: float = 9.8 * WorldCoordsRef.VERTICAL_SCALE
	var h: float = maxf(pos.y, 0.0)
	var vy: float = vel_v.y
	# solve pos.y + vy t - g t^2 / 2 = 0
	var tt: float = (vy + sqrt(vy * vy + 2.0 * g * h)) / g
	var hv := Vector3(vel_v.x, 0.0, vel_v.z) * (1.0 - 0.06 * tt)
	return {"pos": Vector3(pos.x + hv.x * tt, 0.0, pos.z + hv.z * tt), "t": tt}


## Aim point: where to point at on a ship moving with `ship_vel` so the run intercepts it. Returns Vector3.ZERO when no
## intercept inside the torpedo's range exists. `from` is the water entry point.
static func lead_point(torp_id: String, from: Vector3, ship_pos: Vector3, ship_vel: Vector3, entry_t: float = 0.0) -> Vector3:
	var t: Dictionary = TYPES.get(torp_id, TYPES["mk12"])
	var v: float = float(t["run_speed"])
	var p0: Vector3 = ship_pos + ship_vel * entry_t - from
	p0.y = 0.0
	var sv := Vector3(ship_vel.x, 0.0, ship_vel.z)
	# |p0 + sv t| = v t
	var a: float = sv.dot(sv) - v * v
	var b: float = 2.0 * p0.dot(sv)
	var c: float = p0.dot(p0)
	var tt: float = -1.0
	if absf(a) < 1.0e-5:
		if absf(b) > 1.0e-5:
			tt = -c / b
	else:
		var disc: float = b * b - 4.0 * a * c
		if disc >= 0.0:
			var s: float = sqrt(disc)
			var t1: float = (-b - s) / (2.0 * a)
			var t2: float = (-b + s) / (2.0 * a)
			tt = minf(t1, t2) if minf(t1, t2) > 0.0 else maxf(t1, t2)
	if tt <= 0.0 or tt * v > float(t["range"]):
		return Vector3.ZERO
	return ship_pos + ship_vel * (entry_t + tt)


# ------------------------------------------------------------------ setup

func setup(torp_id: String, p: Vector3, v: Vector3, t_team: String, src: Node, release_alt_m: float, roll_deg: float = 0.0) -> void:
	tid = torp_id if TYPES.has(torp_id) else "mk12"
	cfg = TYPES[tid]
	team = t_team
	source = src
	set_depth = float(cfg["depth"])
	vel = v
	global_position = p
	var hv := Vector3(v.x, 0.0, v.z)
	var hs: float = hv.length()
	var path_deg: float = rad_to_deg(atan2(v.y / WorldCoordsRef.VERTICAL_SCALE, maxf(hs, 0.1)))
	var wd: float = _sea_depth(p + hv.normalized() * 60.0)
	verdict = evaluate_release(tid, release_alt_m, hs, path_deg, roll_deg, wd)
	fate = String(verdict["fate"])
	dive_depth = float(verdict["dive"])
	heading = hv.normalized() if hs > 0.5 else Vector3.FORWARD
	var err: float = float(verdict["heading_err_deg"])
	if err > 0.0:
		heading = heading.rotated(Vector3.UP, deg_to_rad(randf_range(-err, err)))
	_build_visual()
	_orient()


func _ready() -> void:
	set_physics_process(true)


func _build_visual() -> void:
	_body = make_visual(tid, 1.3)
	add_child(_body)


## The torpedo's shape (nose toward -Z). len_k scales it up so it reads from the air; also used for the one slung under
## the aircraft (fit_to_body).
static func make_visual(torp_id: String, len_k: float) -> Node3D:
	var tcfg: Dictionary = TYPES[torp_id]
	var root := Node3D.new()
	var col: Color = tcfg["col"]
	var mat: StandardMaterial3D = _body_mats.get(torp_id) as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = col
		mat.roughness = 0.5
		mat.metallic = 0.4
		_body_mats[torp_id] = mat
	var L: float = float(tcfg["length"]) * len_k
	var body := CylinderMesh.new()
	body.top_radius = 0.3
	body.bottom_radius = 0.3
	body.height = L * 0.78
	body.radial_segments = 10
	body.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = body
	mi.material_override = mat
	mi.rotation.x = deg_to_rad(90.0)
	mi.position = Vector3(0, 0, L * 0.04)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var nose := CylinderMesh.new()
	nose.top_radius = 0.0
	nose.bottom_radius = 0.3
	nose.height = L * 0.2
	nose.radial_segments = 10
	nose.rings = 1
	var ni := MeshInstance3D.new()
	ni.mesh = nose
	ni.material_override = mat
	ni.rotation.x = deg_to_rad(90.0)
	ni.position = Vector3(0, 0, -L * 0.35 - L * 0.1)
	ni.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ni)
	var fin := BoxMesh.new()
	fin.size = Vector3(1.1, 0.06, 0.55)
	for k in 2:
		var fi := MeshInstance3D.new()
		fi.mesh = fin
		fi.material_override = mat
		fi.position = Vector3(0, 0, L * 0.4)
		fi.rotation.z = deg_to_rad(90.0 * k)
		fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fi)
	# red warhead band so it reads against the sea
	var band := CylinderMesh.new()
	band.top_radius = 0.31
	band.bottom_radius = 0.31
	band.height = L * 0.1
	band.radial_segments = 10
	band.rings = 1
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.75, 0.55, 0.12)
	var bi := MeshInstance3D.new()
	bi.mesh = band
	bi.material_override = bm
	bi.rotation.x = deg_to_rad(90.0)
	bi.position = Vector3(0, 0, -L * 0.25)
	bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bi)
	return root


## Slings torpedoes under a procedural model's fuselage (Body space, metres): one on the centreline (Beaufort) or a pair
## side by side (He 111). Nodes are named Torp0 / Torp1 so the aircraft can hide one as it is dropped.
static func fit_to_body(body: Node3D, spec: Dictionary, torp_id: String, count: int) -> void:
	var f: Dictionary = spec["fus"]
	var w0: Dictionary = PlaneBuilder.wing_section(spec["wing"], 0.0)
	var rz: float = float(w0["zle"]) + float(w0["chord"]) * 0.45
	var fd: Array = PlaneBuilder.fus_at(f, rz)
	var bottom: float = float(fd[2]) - float(fd[1])
	for i in count:
		var tn: Node3D = make_visual(torp_id, 1.15)
		tn.name = "Torp%d" % i
		var x: float = 0.0 if count < 2 else (-0.5 if i == 0 else 0.5) * minf(float(fd[0]) * 0.9, 0.62)
		tn.position = Vector3(x, bottom - (0.12 if count < 2 else 0.2), rz + 0.2)
		tn.rotation.x = deg_to_rad(-1.5)
		body.add_child(tn, true)


func _orient() -> void:
	var d: Vector3 = vel if phase == Phase.AIR else Vector3(heading.x, 0.0, heading.z)
	if phase == Phase.RUN:
		d = Vector3(heading.x, _depth_rate(), heading.z)
	if d.length_squared() < 0.0001:
		return
	d = d.normalized()
	var up: Vector3 = Vector3.UP if absf(d.y) < 0.98 else Vector3.BACK
	var b := Basis.looking_at(d, up)
	if phase == Phase.AIR:
		# the air tail holds the nose a few degrees low, with a small wobble
		b = b * Basis(Vector3.RIGHT, deg_to_rad(-6.0 + 2.2 * sin(_clock * 8.0 + _wobble)))
		b = b * Basis(Vector3.UP, deg_to_rad(1.5 * sin(_clock * 5.3 + _wobble)))
	global_transform = Transform3D(b, global_position)


# ------------------------------------------------------------------ helpers

func _terrain_node() -> Node:
	if _terrain == null or not is_instance_valid(_terrain):
		_terrain = get_tree().get_first_node_in_group("terrain") if is_inside_tree() else null
	return _terrain


func _ground(p: Vector3) -> float:
	var t: Node = _terrain_node()
	if t != null and t.has_method("get_height_at"):
		return float(t.call("get_height_at", p))
	return -60.0


## Metres of sea under p: the game's seabed is flat at 0 over most of the sea (no bathymetry), which counts as deep (40 m);
## where the terrain does dip below the sea it is used, never less than SEA_MIN_DEPTH.
func _sea_depth(p: Vector3) -> float:
	var h: float = _ground(p)
	if h > -0.5:
		return 40.0
	return maxf(-h, SEA_MIN_DEPTH)


func _is_water(p: Vector3) -> bool:
	var t: Node = _terrain_node()
	if t != null and t.has_method("is_water_at"):
		return bool(t.call("is_water_at", p))
	return true


## Planned depth at `run` metres into the run: dive, then recovery to the set depth (a porpoise swings round it).
func depth_at(run: float) -> float:
	var dive_len: float = 30.0 + (dive_depth - set_depth) * 2.0
	var rec_len: float = 55.0 + (dive_depth - set_depth) * 7.0
	if run < dive_len:
		var k: float = run / dive_len
		return lerpf(0.0, dive_depth, k * k * (3.0 - 2.0 * k))
	var r: float = clampf((run - dive_len) / rec_len, 0.0, 1.0)
	var d: float = lerpf(dive_depth, set_depth, r * r * (3.0 - 2.0 * r))
	if fate == "porpoise" and r < 1.0:
		d += sin(r * PI * 2.0) * (dive_depth - set_depth) * 0.25 * (1.0 - r)
	return maxf(d, 0.0)


func _depth_rate() -> float:
	return (depth_at(run_dist + 4.0) - depth_at(run_dist)) / 4.0 * -1.0


func ship_draught(sh: Node) -> float:
	var st: String = String(sh.get("stype")) if "stype" in sh else ""
	var dr: float = float(DRAUGHT.get(st, 3.0))
	return dr * (sh.scale.x if sh is Node3D else 1.0)


# ------------------------------------------------------------------ simulation

func _physics_process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_clock += delta
	age += delta
	if phase == Phase.AIR:
		_step_air(delta)
	elif phase == Phase.RUN:
		_step_run(delta)
	_tick_fx(delta)
	if phase == Phase.DONE:
		_done_t += delta
		if _wake != null:
			_wake_dirty -= delta
			if _wake_dirty <= 0.0:
				_wake_dirty = 0.5
				_rebuild_wake()
		if _done_t > WAKE_LIFE + 1.0 and _fall_t < 0.0:
			_finish()


func _step_air(delta: float) -> void:
	vel.y -= 9.8 * WorldCoordsRef.VERTICAL_SCALE * delta
	var damp: float = maxf(1.0 - 0.06 * delta, 0.0)
	vel.x *= damp
	vel.z *= damp
	var p1: Vector3 = global_position + vel * delta
	if p1.y <= 0.0:
		var f: float = clampf(global_position.y / maxf(global_position.y - p1.y, 0.0001), 0.0, 1.0)
		var ep: Vector3 = global_position.lerp(p1, f)
		ep.y = 0.0
		global_position = ep
		_enter_water()
		return
	var h: float = _ground(p1)
	if p1.y <= h and not _is_water(p1):
		# fell on land: a thud and a puff of dirt, nothing more
		global_position = Vector3(p1.x, h, p1.z)
		FX.dust(global_position, 2.5)
		FX.sfx("hit", global_position, -4.0, 0.1)
		_end("land")
		return
	global_position = p1
	_orient()


func _enter_water() -> void:
	entry_pos = global_position
	var hs: float = Vector2(vel.x, vel.z).length()
	var angle: float = absf(rad_to_deg(atan2(-vel.y / WorldCoordsRef.VERTICAL_SCALE, maxf(hs, 0.1))))
	var spd: float = Vector3(vel.x / 1.0, vel.y / WorldCoordsRef.VERTICAL_SCALE, vel.z).length()
	if not _is_water(entry_pos):
		FX.dust(entry_pos, 2.5)
		_end("land")
		return
	entry_splash(entry_pos, spd, angle)
	FX.sfx("bomb_whistle", entry_pos, -12.0, 0.3)
	if fate == "breaks_up":
		# the torpedo breaks its back on the water: spray, debris and a foam slick, no run
		FX.debris(entry_pos + Vector3(0, 0.5, 0), 8, 0.6, 9.0, Color(0.25, 0.25, 0.26))
		FX.water_splash(entry_pos, 5.0)
		_end("broke_up")
		return
	phase = Phase.RUN
	run_dist = 0.0
	depth = 0.0
	_ship_t = 0.0
	wake_active = true
	_start_wake()
	_orient()


## The entry splash: a spray column and a ring sized to the speed and angle of the entry.
static func entry_splash(pos: Vector3, speed: float, angle_deg: float) -> void:
	var size: float = clampf(2.0 + speed * 0.03 + angle_deg * 0.08, 2.5, 8.0)
	FX.water_splash(pos, size)
	# column of spray thrown up and forward by the entry
	var n: int = clampi(int(6.0 + size * 1.5), 7, 18)
	for i in n:
		var up: float = size * randf_range(2.2, 4.4)
		var d := Vector3(randf_range(-0.25, 0.25), 1.0, randf_range(-0.25, 0.25))
		FX.puffs.spawn(pos + Vector3(randf_range(-1.0, 1.0), 0.3, randf_range(-1.0, 1.0)) * size * 0.2, d * up, randf_range(1.0, 1.7), size * 0.3, size * randf_range(0.7, 1.0),
			Color(0.96, 0.98, 1.0, 0.92), Color(0.85, 0.92, 0.96, 0.0), 0.9, size * 3.0, 0.2)
	# ring
	var nr: int = clampi(int(10.0 + size * 2.0), 12, 22)
	for i in nr:
		var a: float = TAU * float(i) / float(nr)
		var dir := Vector3(cos(a), 0.05, sin(a))
		FX.puffs.spawn(pos + dir * size * 0.3, dir * size * randf_range(1.4, 2.2), randf_range(1.3, 2.0), size * 0.28, size * 0.85,
			Color(0.93, 0.97, 1.0, 0.7), Color(0.85, 0.9, 0.95, 0.0), 0.6, 0.0, 1.1)


func _step_run(delta: float) -> void:
	var v: float = float(cfg["run_speed"])
	var step: float = v * delta
	run_dist += step
	depth = depth_at(run_dist)
	var p: Vector3 = global_position + heading * step
	p.y = -depth
	global_position = p
	# seabed / shore
	var water: bool = _is_water(p)
	if not water:
		_hit_shore()
		return
	if depth >= _sea_depth(p) - 0.4:
		_bury()
		return
	# ship test
	_ship_t -= delta
	if _ship_t <= 0.0:
		_ship_t = 0.4
		_ships = get_tree().get_nodes_in_group("ship")
	for n in _ships:
		var sh := n as Node3D
		if sh == null or not is_instance_valid(sh) or not sh.is_inside_tree():
			continue
		if bool(sh.get("is_dead")) or String(sh.get("team")) == team:
			continue
		if _hits_ship(sh, p):
			_strike(sh, p)
			return
	if run_dist >= float(cfg["range"]):
		_run_out()
		return
	_orient()


func _hits_ship(sh: Node3D, p: Vector3) -> bool:
	if depth > ship_draught(sh) + 0.4:
		return false                                  # running too deep: passes under the keel
	var lp: Vector3 = sh.global_transform.affine_inverse() * Vector3(p.x, sh.global_position.y, p.z)
	var half_l: float = 0.5 * float(sh.get("_len")) + 0.6 if "_len" in sh else float(sh.get("hit_radius"))
	var half_b: float = 0.5 * float(sh.get("_beam")) + 0.6 if "_beam" in sh else float(sh.get("hit_radius"))
	return absf(lp.x) <= half_b and absf(lp.z) <= half_l


func _strike(sh: Node3D, p: Vector3) -> void:
	hit_target = sh
	if run_dist < float(cfg["arm"]):
		# not yet armed: it strikes the hull with a clang and sinks (a dud)
		FX.sfx("hit_metal:1", p, -2.0, 0.1)
		FX.water_splash(Vector3(p.x, 0.0, p.z), 3.5)
		if sh.has_method("take_damage"):
			sh.call("take_damage", 6.0, source)
		_end("dud_hit")
		return
	_detonate(p, sh)
	var dmg: float = float(cfg["damage"])
	if sh.has_method("torpedo_hit"):
		sh.call("torpedo_hit", dmg, p, source)
	elif sh.has_method("take_damage"):
		sh.call("take_damage", dmg, source)
	_end("hit")


## The explosion alongside the hull: flash, a tall white water column with spray and debris, and the column falling back
## a moment later.
func _detonate(p: Vector3, sh: Node3D) -> void:
	var surf := Vector3(p.x, 0.0, p.z)
	FX.explosion(surf + Vector3(0, 2.0, 0), 5.0)
	FX.water_plume(surf, 14.0)
	FX.debris(surf + Vector3(0, 3.0, 0), 14, 1.3, 22.0, Color(0.16, 0.15, 0.14))
	FX.light_flash(surf + Vector3(0, 6.0, 0), 4.0, 90.0, 0.3, Color(1.0, 0.75, 0.45))
	FX.sfx("explosion", surf, 2.0, 0.0)
	_fall_t = 1.5
	_fall_pos = surf
	Weapons.explosion_occurred.emit(surf, 22.0)


func _tick_fx(delta: float) -> void:
	# falling water after the column: a curtain of spray coming back down, and a boil on the surface
	if _fall_t >= 0.0:
		_fall_t -= delta
		if _fall_t < 0.0:
			for i in 16:
				var a: float = randf() * TAU
				var r: float = randf_range(2.0, 14.0)
				var top := _fall_pos + Vector3(cos(a) * r, randf_range(26.0, 48.0), sin(a) * r)
				FX.puffs.spawn(top, Vector3(0, -randf_range(14.0, 26.0), 0), randf_range(1.4, 2.0), 3.0, 5.0,
					Color(0.93, 0.96, 0.99, 0.6), Color(0.85, 0.9, 0.95, 0.0), 0.5, 0.0, 0.4)
			FX.water_splash(_fall_pos, 9.0)
			FX.sfx("explosion", _fall_pos, -16.0, 0.2)
	# compressed-air exhaust bubbles at the tail while running
	if wake_active and phase == Phase.RUN:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			_bubble_t = 0.12
			var tail: Vector3 = global_position - heading * 2.2
			FX.puffs.spawn(Vector3(tail.x, 0.3, tail.z), Vector3(randf_range(-0.4, 0.4), randf_range(0.2, 0.6), randf_range(-0.4, 0.4)), randf_range(2.0, 3.0), 0.7, 2.2,
				Color(1, 1, 1, 0.55), Color(0.95, 0.98, 1.0, 0.0), 0.0, 0.0, 0.8)
		var tp := Vector3(global_position.x, 0.0, global_position.z)
		if tp.distance_to(_last_wp) >= WAKE_STEP or _last_wp.x > 1.0e8:
			_add_wake_point(tp)
		_wake_dirty -= delta
		if _wake_dirty <= 0.0:
			_wake_dirty = 0.25
			_rebuild_wake()
	# the shape under the water: dark, shallow enough to read through the surface
	if _body != null and phase == Phase.RUN:
		_body.visible = true


func _hit_shore() -> void:
	# ran onto the shore or a sandbank: armed torpedoes go off in the surf, otherwise it just lies there
	var p := global_position
	if run_dist >= float(cfg["arm"]):
		FX.water_plume(Vector3(p.x, 0.0, p.z), 7.0)
		FX.sfx("explosion", p, -2.0, 0.1)
		Weapons.explosion_occurred.emit(p, 12.0)
	else:
		FX.water_splash(Vector3(p.x, 0.0, p.z), 2.5)
	_end("aground")


func _bury() -> void:
	# deep dive into shallow water: it buries itself in the seabed (a dud): a boil of mud and a few bubbles
	var p := global_position
	for i in 6:
		FX.puffs.spawn(Vector3(p.x, 0.3, p.z) + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)), randf_range(2.0, 3.5), 1.4, 3.6,
			Color(0.55, 0.55, 0.45, 0.45), Color(0.6, 0.6, 0.5, 0.0), 0.3, 0.0, 0.6)
	_end("seabed")


func _run_out() -> void:
	# end of the run: the torpedo sinks (a boil of bubbles); the practice head does not explode
	var p := global_position
	for i in 5:
		FX.puffs.spawn(Vector3(p.x, 0.3, p.z) + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)), Vector3(0, 0.6, 0), randf_range(2.5, 4.0), 1.0, 3.2,
			Color(1, 1, 1, 0.5), Color(0.95, 0.98, 1.0, 0.0), 0.0, 0.0, 0.7)
	_end("ran_out")


func _end(what: String) -> void:
	outcome = what
	if OS.get_cmdline_user_args().has("--torp-log") or str(OS.get_cmdline_user_args()).contains("--torp-test"):
		print("[torpedo] end %s after %.0f m, depth %.1f, ground %.1f, water %s, fate %s" % [what, run_dist, depth, _ground(global_position), str(_is_water(global_position)), fate])
	phase = Phase.DONE
	wake_active = false
	_done_t = 0.0
	if _body != null:
		_body.visible = false
	if _wake == null or _wp.size() < 2:
		if _fall_t < 0.0:
			_finish()
	else:
		_rebuild_wake()


func _finish() -> void:
	if get_parent() != null and Weapons != null:
		Weapons.torpedoes.erase(self)
	queue_free()


# ------------------------------------------------------------------ bubble wake ribbon

func _start_wake() -> void:
	_wake = MeshInstance3D.new()
	_wake.top_level = true
	_wake.global_transform = Transform3D.IDENTITY
	_wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wake.extra_cull_margin = 4000.0
	var m := ShaderMaterial.new()
	if _shader == null:
		_shader = Shader.new()
		_shader.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, depth_draw_never, blend_mix;\nvarying vec3 wp;\n" \
			+ "float h21(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }\n" \
			+ "float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);\n" \
			+ "  return mix(mix(h21(i), h21(i+vec2(1,0)), f.x), mix(h21(i+vec2(0,1)), h21(i+vec2(1,1)), f.x), f.y); }\n" \
			+ "void vertex(){ wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }\n" \
			+ "void fragment(){\n  float edge = 1.0 - abs(UV.x * 2.0 - 1.0);\n  float n = vn(wp.xz * 1.1) * 0.6 + vn(wp.xz * 3.1) * 0.4;\n" \
			+ "  float a = COLOR.a * smoothstep(0.0, 0.45, edge) * clamp(0.35 + n * 1.05, 0.0, 1.0);\n" \
			+ "  ALBEDO = mix(vec3(0.82, 0.9, 0.93), vec3(1.0), n);\n  ALPHA = clamp(a, 0.0, 1.0);\n}\n"
	m.shader = _shader
	_wake.material_override = m
	add_child(_wake)


func _add_wake_point(p: Vector3) -> void:
	_last_wp = p
	_wp.append(p)
	_wt.append(_clock)
	_wj.append(randf())
	if _wp.size() > WAKE_MAX_PTS:
		_wp = _wp.slice(1)
		_wt = _wt.slice(1)
		_wj = _wj.slice(1)


func wake_points() -> int:
	return _wp.size()


func _rebuild_wake() -> void:
	if _wake == null:
		return
	var n: int = _wp.size()
	if n < 2:
		_wake.mesh = null
		return
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.resize(n * 2)
	cols.resize(n * 2)
	uvs.resize(n * 2)
	var any: bool = false
	for i in n:
		var a: float = _clock - _wt[i]
		var fade: float = clampf(1.0 - a / WAKE_LIFE, 0.0, 1.0)
		var w: float = lerpf(0.9, 3.6, clampf(a / 40.0, 0.0, 1.0)) * (0.85 + 0.3 * _wj[i])
		var tang: Vector3
		if i < n - 1:
			tang = _wp[i + 1] - _wp[i]
		else:
			tang = _wp[i] - _wp[i - 1]
		tang.y = 0.0
		tang = tang.normalized() if tang.length_squared() > 0.0001 else Vector3.FORWARD
		var side := Vector3(-tang.z, 0.0, tang.x) * w
		var al: float = 0.9 * pow(fade, 1.3)
		if al > 0.01:
			any = true
		verts[i * 2] = _wp[i] + side + Vector3(0, 0.35, 0)
		verts[i * 2 + 1] = _wp[i] - side + Vector3(0, 0.35, 0)
		cols[i * 2] = Color(1, 1, 1, al)
		cols[i * 2 + 1] = Color(1, 1, 1, al)
		uvs[i * 2] = Vector2(0.0, float(i))
		uvs[i * 2 + 1] = Vector2(1.0, float(i))
		if i < n - 1:
			idx.append_array(PackedInt32Array([i * 2, i * 2 + 1, i * 2 + 2, i * 2 + 1, i * 2 + 3, i * 2 + 2]))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_wake.mesh = am
	if not any and phase == Phase.DONE:
		_wake.visible = false


## For the camera (Weapons.skip_bomb_view): true while the torpedo is flying, running, or its column is still up.
func view_live() -> bool:
	return phase != Phase.DONE or _done_t < 3.0


## Fully faded or gone: the sim can drop it.
func is_finished() -> bool:
	return phase == Phase.DONE and (_wake == null or not _wake.visible or _done_t > WAKE_LIFE)
