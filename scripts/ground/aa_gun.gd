class_name AAGun
extends GroundTarget
## Anti-aircraft gun (88mm flak / Bofors / light MG). Tracks and shoots enemy-team aircraft.
## Accuracy falls with distance and bad weather (GroundKit.visibility()), rises with difficulty; at night a
## target must be lit by a Searchlight (meta "lit_until") or be very close. 88mm fires fused flak bursts,
## Bofors/MG fire visible tracers through the shared AAShells pool.
##
## DRAW CALLS: the static geometry (sandbag loop + base plate) is merged into a single ArrayMesh and the
## moving groups (yaw ring, pitch cradle, muzzle flash) each use one merged mesh. All meshes are built
## ONCE per (type, team) and cached statically, so every AAGun of a type shares the same mesh resources
## and Godot can instance-batch them. A gun is 4 MeshInstance3D nodes (was ~16-17).

const TYPES := {
	"88mm": {"range": 3600.0, "rate": 1.7, "burst": 3, "speed": 650.0, "dmg": 3.4, "radius": 19.0, "base_err": 0.010, "k_err": 0.000012, "hp": 90.0, "r": 9.0, "pts": 220, "turn": 0.8, "vis": 1.7, "night_sight": 900.0},
	"bofors": {"range": 1700.0, "rate": 1.25, "burst": 8, "speed": 520.0, "dmg": 1.2, "radius": 0.0, "base_err": 0.012, "k_err": 0.000012, "hp": 55.0, "r": 7.0, "pts": 140, "turn": 1.5, "vis": 1.5, "night_sight": 800.0},
	"mg": {"range": 1000.0, "rate": 0.8, "burst": 8, "speed": 480.0, "dmg": 0.9, "radius": 0.0, "base_err": 0.02, "k_err": 0.000025, "hp": 30.0, "r": 5.0, "pts": 80, "turn": 1.8, "vis": 1.2, "night_sight": 600.0},
}

var gtype: String = "88mm"
var cfg: Dictionary = {}
var active: bool = true
var _vis: Node3D
var _yaw_node: Node3D
var _pitch_node: Node3D
var _tip: Node3D
var _flash: MeshInstance3D
var _flash_t: float = 0.0
var _target: Node3D
var _scan_t: float = 0.0
var _cool: float = 1.0
var _burst_left: int = 0
var _burst_gap: float = 0.0
var _yaw: float = 0.0
var _pitch: float = 0.0
var _attentive: bool = true       # is the crew at the gun and watching the sky? Crews wander off, doze, or look the wrong way
var _attn_t: float = 0.0
var _barrage: bool = false      # night: firing a predicted barrage at an aircraft it can hear but not see

## Shared geometry cache: merged ArrayMeshes keyed by type/team, built once and reused by every gun.
static var _merged: Dictionary = {}
static var _flash_mesh_ref: SphereMesh


static func create(p_type: String, p_team: String) -> AAGun:
	var g := AAGun.new()
	g.gtype = p_type
	g.team = p_team
	g.cfg = TYPES.get(p_type, TYPES["bofors"])
	g.max_health = g.cfg["hp"]
	g.hit_radius = g.cfg["r"]
	g.points = g.cfg["pts"]
	g.kind = "aa_" + p_type
	g.display_name = "AA gun (%s)" % p_type
	g.explosion_size = 0.9
	g.smoke_scale = 0.8
	g.small_mult = 0.6
	g._scan_t = randf() * 0.3
	g._yaw = randf() * TAU
	return g


## Merge parts [[Mesh, Transform3D, Material], ...] into ONE ArrayMesh, one surface per distinct
## material (so a gun costs a handful of draw calls instead of one per part). Mirrors the merge used
## by AirfieldAssets so multi-part props share the fewest possible surfaces.
static func _merge(parts: Array) -> ArrayMesh:
	var src: ArrayMesh = GroundKit.combine(parts)
	var by_mat: Dictionary = {}
	for i in src.get_surface_count():
		var mat: Material = src.surface_get_material(i)
		var key: int = mat.get_instance_id() if mat != null else 0
		if not by_mat.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_material(mat)
			by_mat[key] = st
		(by_mat[key] as SurfaceTool).append_from(src, i, Transform3D.IDENTITY)
	var out := ArrayMesh.new()
	for k in by_mat:
		(by_mat[k] as SurfaceTool).commit(out)
	return out


## Sandbag loop + base plate (static, non-moving). Identical for every gun of a type.
static func _static_mesh(t: String) -> ArrayMesh:
	var key: String = "stat_" + t
	if _merged.has(key):
		return _merged[key]
	var big: bool = t == "88mm"
	var ring_r: float = 6.5 if big else 5.0
	var parts: Array = []
	for i in 10:
		var a: float = TAU * float(i) / 10.0
		parts.append(GroundKit.box_part(Vector3(3.2, 1.3, 1.1), Vector3(cos(a) * ring_r, 0.65, sin(a) * ring_r), GroundKit.COL_SAND, Vector3(0, -rad_to_deg(a) + 90.0, 0), false))
	parts.append(GroundKit.cyl_part(ring_r - 0.8, ring_r - 0.8, 0.3, Vector3(0, 0.15, 0), GroundKit.COL_DARK.lightened(0.15), Vector3.ZERO, 12, false))
	var m: ArrayMesh = _merge(parts)
	_merged[key] = m
	return m


## Rotating yaw ring (+ the Bofors gunner seat, which turns with the mount but never pitches).
static func _yaw_mesh(t: String, team: String) -> ArrayMesh:
	var key: String = "yaw_%s_%s" % [t, team]
	if _merged.has(key):
		return _merged[key]
	var c: Color = GroundKit.team_color(team)
	var parts: Array = []
	parts.append(GroundKit.cyl_part(1.4, 1.7, 1.4, Vector3(0, 0.7, 0), c.darkened(0.15), Vector3.ZERO, 8))
	if t != "88mm":
		parts.append(GroundKit.box_part(Vector3(0.8, 0.2, 0.8), Vector3(1.6, 1.4, 1.2), c.darkened(0.3)))   # seat
	var m: ArrayMesh = _merge(parts)
	_merged[key] = m
	return m


## Pitching cradle: shield, barrel(s) and breech — all raise/lower together.
static func _pitch_mesh(t: String, team: String) -> ArrayMesh:
	var key: String = "pitch_%s_%s" % [t, team]
	if _merged.has(key):
		return _merged[key]
	var c: Color = GroundKit.team_color(team)
	var parts: Array = []
	if t == "88mm":
		parts.append(GroundKit.box_part(Vector3(3.0, 2.0, 0.3), Vector3(0, 0.4, -1.0), c))                                   # shield
		parts.append(GroundKit.cyl_part(0.28, 0.4, 9.0, Vector3(0, 0.2, -4.8), c.darkened(0.3), Vector3(90, 0, 0), 8))      # barrel
		parts.append(GroundKit.box_part(Vector3(1.2, 1.0, 2.0), Vector3(0, 0.0, 0.6), c.darkened(0.2)))                     # breech
	else:
		for sx in [-0.7, 0.7]:
			parts.append(GroundKit.cyl_part(0.14, 0.2, 5.0, Vector3(sx, 0.2, -2.8), c.darkened(0.3), Vector3(90, 0, 0), 6))  # twin barrels
		parts.append(GroundKit.box_part(Vector3(2.0, 1.0, 1.6), Vector3(0, 0.0, 0.2), c))                                    # cradle
	var m: ArrayMesh = _merge(parts)
	_merged[key] = m
	return m


## Wreck debris (3 boxes/cylinders) merged into one shared mesh.
static func _wreck_mesh() -> ArrayMesh:
	var key: String = "wreck"
	if _merged.has(key):
		return _merged[key]
	var d: Color = Color(0.1, 0.09, 0.08)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(5.0, 0.9, 5.0), Vector3(0, 0.4, 0), d, Vector3(0, 15, 3)))
	parts.append(GroundKit.cyl_part(0.25, 0.3, 6.0, Vector3(1.5, 0.9, -1.0), d, Vector3(75, 40, 0), 6))
	parts.append(GroundKit.box_part(Vector3(2.0, 1.2, 2.0), Vector3(-1.0, 0.9, 1.0), d.lightened(0.05), Vector3(20, 10, 25)))
	var m: ArrayMesh = _merge(parts)
	_merged[key] = m
	return m


static func _flash_mesh() -> SphereMesh:
	if _flash_mesh_ref == null:
		var fm := SphereMesh.new()
		fm.radius = 1.1
		fm.height = 2.2
		fm.radial_segments = 6
		fm.rings = 3
		_flash_mesh_ref = fm
	return _flash_mesh_ref


func _post_ready() -> void:
	add_to_group("aa_gun")
	_attentive = randf() < 0.55
	_attn_t = randf_range(15.0, 80.0)


func _build_intact(root: Node3D) -> void:
	_vis = Node3D.new()
	root.add_child(_vis)
	var big: bool = gtype == "88mm"
	# Static geometry (sandbag loop + base plate): one shared, cached mesh.
	var stat := MeshInstance3D.new()
	stat.mesh = _static_mesh(gtype)
	_vis.add_child(stat)
	_yaw_node = Node3D.new()
	_yaw_node.position = Vector3(0, 0.4, 0)
	_vis.add_child(_yaw_node)
	# Yaw ring (+ seat) as one shared mesh on the yaw node.
	var yaw := MeshInstance3D.new()
	yaw.mesh = _yaw_mesh(gtype, team)
	_yaw_node.add_child(yaw)
	_pitch_node = Node3D.new()
	_pitch_node.position = Vector3(0, 2.0 if big else 1.8, 0)
	_yaw_node.add_child(_pitch_node)
	# Shield + barrel(s) + breech as one shared mesh on the pitch node.
	var pitch := MeshInstance3D.new()
	pitch.mesh = _pitch_mesh(gtype, team)
	_pitch_node.add_child(pitch)
	_tip = Node3D.new()
	_tip.position = Vector3(0, 0.2, -9.4) if big else Vector3(0, 0.2, -5.4)
	_pitch_node.add_child(_tip)
	_flash = MeshInstance3D.new()
	_flash.mesh = _flash_mesh()
	_flash.material_override = GroundKit.glow_mat(Color(1.0, 0.85, 0.4), 1.0)
	_flash.visible = false
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tip.add_child(_flash)
	_vis.scale = Vector3.ONE * 1.4
	hit_radius = hit_radius * 1.0
	# the gun and its pit fade out with distance (a light gun is a speck beyond ~3 km); the muzzle flash and the
	# tracers are not range-limited, so a firing gun still shows where it is
	var vr: float = 4500.0 if big else (3500.0 if gtype == "bofors" else 2500.0)
	for mi in [stat, yaw, pitch]:
		(mi as MeshInstance3D).visibility_range_end = vr
		(mi as MeshInstance3D).visibility_range_end_margin = vr * 0.12
		(mi as MeshInstance3D).visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _build_wreck(root: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _wreck_mesh()
	root.add_child(mi)


func _process(delta: float) -> void:
	if is_dead or not active:
		return
	delta = minf(delta, 0.1)
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.visible = false
	# Not every gun is manned or watching: each crew spends long spells away from the gun or looking elsewhere, and
	# even an alert one is slow to pick an aircraft out of the sky.
	_attn_t -= delta
	if _attn_t <= 0.0:
		_attentive = randf() < 0.55
		_attn_t = randf_range(20.0, 90.0)
		if _attentive:
			_cool = maxf(_cool, randf_range(2.0, 6.0))        # running back to the gun
	if not _attentive:
		_target = null
		_burst_left = 0
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.3
		if randf() < 0.45:
			_acquire()
	if _target != null and (not GroundKit.aircraft_alive(_target) or _target.global_position.distance_to(global_position) > _eff_range() * 1.05):
		_target = null
	var aim: Vector3 = Vector3.ZERO
	var has_aim: bool = false
	if _target != null:
		aim = _predict(_target)
		has_aim = true
	_track(aim, has_aim, delta)
	_cool -= delta
	if has_aim and _cool <= 0.0:
		var err: float = _angle_error(aim)
		if err < (0.3 if _barrage else 0.12):
			if _burst_left <= 0:
				_burst_left = int(cfg["burst"])
			_burst_gap -= delta
			if _burst_gap <= 0.0:
				_burst_gap = (0.32 if gtype == "88mm" else 0.11) if int(cfg["burst"]) > 1 else 0.0
				_shoot(aim)
				_burst_left -= 1
				if _burst_left <= 0:
					_cool = float(cfg["rate"]) * randf_range(0.85, 1.25)


func _eff_range() -> float:
	return float(cfg["range"]) * (0.55 + 0.45 * GroundKit.visibility())


func _acquire() -> void:
	if _target != null or GroundKit.peace:
		return
	var rng: float = _eff_range()
	var best: Node3D = null
	var best_d: float = INF
	var best_barrage: bool = false
	var night: bool = GroundKit.is_night()
	var now: float = Time.get_ticks_msec() / 1000.0
	for a in GroundKit.enemy_aircraft(team, global_position, rng):
		var n3: Node3D = a as Node3D
		if _at_friendly_field(n3):
			continue
		var d: float = n3.global_position.distance_to(global_position)
		var barrage: bool = false
		if night:
			var lit: bool = n3.has_meta("lit_until") and float(n3.get_meta("lit_until")) > now
			if not lit and d > float(cfg["night_sight"]):
				if gtype != "88mm":
					continue
				barrage = true        # heavy guns put up a sound-located barrage: lots of shells, few hits
				d += 1500.0           # prefer a target the searchlights hold
		if n3.global_position.y < global_position.y - 5.0 and d > 300.0:
			pass
		if d < best_d:
			best_d = d
			best = n3
			best_barrage = barrage
	if best != null and _target == null:
		_cool = maxf(_cool, randf_range(1.3, 3.5))        # reaction time before the first shot
	_target = best
	_barrage = best_barrage


## Aircraft within 700u of an airfield of their own team are safe (no flak over friendly fields).
func _at_friendly_field(n3: Node3D) -> bool:
	var ac_team: Variant = n3.get("team")
	if ac_team == null:
		return false
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	for af in tree.get_nodes_in_group("airfield"):
		if str(af.get("team")) != str(ac_team):
			continue
		if af.global_position.distance_to(n3.global_position) < 700.0:
			return true
	return false


func _predict(t: Node3D) -> Vector3:
	var from: Vector3 = _tip.global_position if _tip else global_position
	var tv: Vector3 = Vector3.ZERO
	if "velocity" in t:
		tv = t.get("velocity")
	var p: Vector3 = t.global_position
	var spd: float = cfg["speed"]
	for i in 3:
		p = t.global_position + tv * (from.distance_to(p) / spd)
	return p


func _angle_error(aim: Vector3) -> float:
	var f: Vector3 = -_pitch_node.global_transform.basis.z
	var d: Vector3 = (aim - _pitch_node.global_position).normalized()
	return f.angle_to(d)


func _track(aim: Vector3, has_aim: bool, delta: float) -> void:
	var turn: float = cfg["turn"]
	var ty: float
	var tp: float
	if has_aim:
		var d: Vector3 = aim - _pitch_node.global_position
		ty = atan2(-d.x, -d.z) - global_rotation.y
		tp = atan2(d.y, Vector2(d.x, d.z).length())
	else:
		ty = _yaw + delta * 0.2
		tp = deg_to_rad(35.0)
	_yaw = lerp_angle(_yaw, ty, clampf(turn * delta / maxf(absf(angle_difference(_yaw, ty)), 0.01), 0.0, 1.0))
	_pitch = move_toward(_pitch, clampf(tp, deg_to_rad(-5.0), deg_to_rad(88.0)), turn * delta)
	_yaw_node.rotation.y = _yaw
	_pitch_node.rotation.x = _pitch


func _shoot(aim: Vector3) -> void:
	var shells: AAShells = AAShells.get_instance()
	if shells == null:
		return
	var from: Vector3 = _tip.global_position
	var dist: float = from.distance_to(aim)
	var acc: float = GroundKit.visibility() * (0.6 + 0.4 * GroundKit.difficulty())
	var err: float = (float(cfg["base_err"]) + float(cfg["k_err"]) * dist) / maxf(acc, 0.2)
	# a searchlight holding a target makes the battery far more accurate: the glow of the beam lets the
	# layers follow the aircraft, so flak lands much closer (stronger at night, when the beam is on)
	if _target and _target.has_meta("lit_until") and float(_target.get_meta("lit_until")) > Time.get_ticks_msec() / 1000.0:
		err *= 0.55 if GroundKit.is_night() else 0.8
	if _barrage:
		err *= 5.0
	var dir: Vector3 = (aim - from).normalized()
	var axis: Vector3 = dir.cross(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))).normalized()
	if axis.length() < 0.1:
		axis = Vector3.UP
	dir = dir.rotated(axis, err * sqrt(randf()))
	var spd: float = cfg["speed"]
	if gtype == "88mm":
		var fuse: float = dist / spd
		shells.fire_flak(from, dir * spd, fuse, float(cfg["dmg"]), float(cfg["radius"]), team)
	else:
		shells.fire_tracer(from, dir * spd, float(cfg["dmg"]), team, 2.4)
	GroundKit.shells_fired += 1
	_flash.visible = true
	_flash_t = 0.05
	var pl: Node3D = GroundKit.player_node()
	if pl and pl.global_position.distance_to(global_position) < 2500.0 and gtype == "88mm":
		GroundKit.sparks(from, dir)


func _on_destroyed(_killer: Node) -> void:
	active = false
	_target = null
