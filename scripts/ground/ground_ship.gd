class_name GroundShip
extends GroundTarget
## Naval vessels: destroyer, freighter, landing_craft, fishing_boat. Move along a sea RoutePath with a wake;
## sink slowly (tilt + descend) when destroyed. Lofted toon hulls via MeshUtil.loft.

const TYPES := {
	"destroyer": {"hp": 260.0, "r": 20.0, "pts": 400, "len": 34.0, "beam": 4.4, "speed": 16.0},
	"freighter": {"hp": 200.0, "r": 22.0, "pts": 300, "len": 40.0, "beam": 6.5, "speed": 9.0},
	"landing_craft": {"hp": 70.0, "r": 10.0, "pts": 120, "len": 15.0, "beam": 3.6, "speed": 12.0},
	"fishing_boat": {"hp": 35.0, "r": 7.0, "pts": 60, "len": 10.0, "beam": 2.8, "speed": 6.0},
	"collier": {"hp": 240.0, "r": 26.0, "pts": 320, "len": 52.0, "beam": 8.0, "speed": 8.0},
	"trawler": {"hp": 90.0, "r": 11.0, "pts": 150, "len": 20.0, "beam": 4.2, "speed": 10.0},
	"cruiser": {"hp": 520.0, "r": 28.0, "pts": 600, "len": 52.0, "beam": 6.2, "speed": 13.0},
	"battleship": {"hp": 900.0, "r": 34.0, "pts": 1000, "len": 70.0, "beam": 9.0, "speed": 11.0},
	"ferry": {"hp": 150.0, "r": 18.0, "pts": 250, "len": 40.0, "beam": 7.0, "speed": 9.0},
}

## Ships under way are drawn larger than their nominal size so they read from the air at the game's
## compressed map scale (moored harbour craft keep their size to fit the quays).
const SHIP_SCALE: float = 1.8

var stype: String = "destroyer"
var route: RoutePath
var s: float = 0.0
var dir: float = 1.0
var speed: float = 10.0
var wrap: bool = false
var lateral: float = 0.0          # sideways offset from the route (convoy columns), + = starboard
var balloon_alt: float = 0.0      # > 0: flies a barrage balloon from the deck (1940 Channel convoys)
var _yaw: float = 0.0
var _sink: float = 0.0
var _wake: MeshInstance3D
var _bob_t: float = randf() * 10.0
var _len: float = 30.0
var _beam: float = 4.0
var _aa_cd: float = 0.0

## Warships carry light anti-aircraft guns only (pom-poms and Oerlikons). Rounds per second by hull type. The rounds
## are weak: a single flyby does little, but a fighter that stays in range for a while gets hurt.
const AA_RATE: Dictionary = {"destroyer": 1.2, "cruiser": 1.6, "battleship": 1.1, "trawler": 0.7}
const AA_RANGE: float = 900.0
const AA_DAMAGE: float = 0.6


static func create(p_type: String, p_team: String, p_route: RoutePath, start_s: float = 0.0, p_speed: float = -1.0) -> GroundShip:
	var sh := GroundShip.new()
	var cfg: Dictionary = TYPES.get(p_type, TYPES["freighter"])
	sh.stype = p_type
	sh.team = p_team
	sh.route = p_route
	sh.s = start_s
	sh.speed = p_speed if p_speed > 0.0 else float(cfg["speed"])
	sh.max_health = cfg["hp"]
	sh.hit_radius = cfg["r"]
	sh.points = cfg["pts"]
	sh._len = cfg["len"]
	sh._beam = cfg["beam"]
	sh.kind = p_type
	sh.display_name = p_type.replace("_", " ").capitalize()
	sh.swap_on_death = false
	sh.explosion_size = 2.0 if p_type in ["destroyer", "freighter"] else 1.2
	sh.smoke_scale = 1.6
	sh.smoke_height = 8.0
	return sh


func _hull_mesh(length: float, beam: float, depth: float, fb: float, bow_sharp: float) -> ArrayMesh:
	var n: int = 12
	var secs: Array = []
	for i in n + 1:
		var t: float = float(i) / float(n)       # 0 = bow (-Z) .. 1 = stern
		var wfac: float
		if t < 0.3:
			wfac = lerpf(bow_sharp, 1.0, sin(t / 0.3 * PI * 0.5))
		elif t > 0.88:
			wfac = lerpf(1.0, 0.72, (t - 0.88) / 0.12)
		else:
			wfac = 1.0
		var w: float = beam * 0.5 * wfac
		var top: float = fb * (1.0 + 0.5 * pow(1.0 - t, 3.0))
		var z: float = -length * 0.5 + length * t
		secs.append(PackedVector3Array([
			Vector3(-w, top, z), Vector3(w, top, z), Vector3(w * 0.96, 0.0, z),
			Vector3(w * 0.55, -depth, z), Vector3(-w * 0.55, -depth, z), Vector3(-w * 0.96, 0.0, z)]))
	return MeshUtil.loft(secs)


func _hull(color: Color, depth: float, fb: float, sharp: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _hull_mesh(_len, _beam, depth, fb, sharp)
	mi.material_override = GroundKit.mat(color, true, 0.12)
	_intact.add_child(mi)


func _build_intact(root: Node3D) -> void:
	var grey: Color = Color(0.45, 0.5, 0.55) if team == "Allies" else Color(0.38, 0.4, 0.42)
	match stype:
		"destroyer":
			_hull(grey, 2.0, 2.0, 0.08)
			GroundKit.box(root, Vector3(2.8, 2.4, 6.0), Vector3(0, 3.4, -2.0), grey.lightened(0.1))
			GroundKit.box(root, Vector3(2.0, 1.6, 3.0), Vector3(0, 5.4, -2.0), grey.lightened(0.15))
			for z in [3.0, 8.0]:
				GroundKit.cyl(root, 0.9, 1.2, 4.0, Vector3(0, 4.4, z - 2.0), grey.darkened(0.3), Vector3.ZERO, 8)
			GroundKit.cyl(root, 0.15, 0.2, 9.0, Vector3(0, 8.0, -1.0), grey.darkened(0.4), Vector3.ZERO, 5)
			for z in [-11.0, -7.0, 12.0]:
				GroundKit.cyl(root, 1.2, 1.3, 0.9, Vector3(0, 2.5, z), grey.darkened(0.15), Vector3.ZERO, 8)
				GroundKit.cyl(root, 0.18, 0.18, 4.0, Vector3(0, 2.9, z - 2.0), GroundKit.COL_DARK, Vector3(90, 0, 0), 5, false)
		"freighter":
			var hull_c: Color = Color(0.18, 0.2, 0.22) if team == "Axis" else Color(0.28, 0.24, 0.2)
			_hull(hull_c, 3.0, 2.6, 0.1)
			GroundKit.box(root, Vector3(5.0, 5.0, 7.0), Vector3(0, 5.0, 12.0), Color(0.78, 0.76, 0.68))
			GroundKit.box(root, Vector3(4.0, 1.6, 4.0), Vector3(0, 8.4, 12.0), Color(0.8, 0.78, 0.7))
			GroundKit.cyl(root, 1.1, 1.3, 5.0, Vector3(0, 10.5, 14.0), Color(0.55, 0.15, 0.12), Vector3.ZERO, 8)
			for z in [-12.0, -4.0, 4.0]:
				GroundKit.box(root, Vector3(3.8, 0.8, 5.5), Vector3(0, 3.0, z), Color(0.3, 0.27, 0.2))
			for z in [-8.0, 0.0]:
				GroundKit.cyl(root, 0.15, 0.2, 9.0, Vector3(0, 7.0, z), GroundKit.COL_DARK, Vector3.ZERO, 5)
				GroundKit.cyl(root, 0.1, 0.12, 8.0, Vector3(0, 11.0, z + 3.5), GroundKit.COL_DARK, Vector3(-40, 0, 0), 5, false)
		"collier":
			# raised bow, bridge amidships, engines + funnel aft, dark hull with rust-red boot-top
			var hc: Color = Color(0.2, 0.2, 0.21) if team == "Axis" else Color(0.24, 0.22, 0.2)
			_hull(hc, 3.6, 3.0, 0.12)
			var house: Color = Color(0.72, 0.7, 0.62) if team == "Allies" else Color(0.55, 0.56, 0.55)
			GroundKit.box(root, Vector3(_beam * 0.85, 2.0, 7.0), Vector3(0, 4.4, -_len * 0.5 + 4.5), hc.lightened(0.08))
			GroundKit.box(root, Vector3(6.0, 3.2, 6.0), Vector3(0, 5.2, -1.0), house)
			GroundKit.box(root, Vector3(5.0, 1.6, 3.6), Vector3(0, 7.6, -1.6), house.lightened(0.06))
			GroundKit.box(root, Vector3(6.4, 2.6, 9.0), Vector3(0, 4.6, _len * 0.5 - 7.0), house.darkened(0.08))
			GroundKit.cyl(root, 1.3, 1.5, 6.5, Vector3(0, 8.8, _len * 0.5 - 8.0), Color(0.12, 0.12, 0.12), Vector3.ZERO, 8)
			for z in [-14.0, -8.0, 6.0, 12.0]:
				GroundKit.box(root, Vector3(_beam * 0.62, 0.9, 4.2), Vector3(0, 3.4, z), Color(0.26, 0.22, 0.17))
			for z in [-11.0, 9.0]:
				GroundKit.cyl(root, 0.18, 0.22, 11.0, Vector3(0, 8.6, z), GroundKit.COL_DARK, Vector3.ZERO, 5)
				GroundKit.cyl(root, 0.1, 0.12, 9.0, Vector3(0, 6.2, z + 3.0), GroundKit.COL_DARK, Vector3(-55, 0, 0), 5, false)
		"trawler":
			# requisitioned armed trawler (escort): high bow, wheelhouse, tall funnel, gun on the foredeck
			var tc: Color = Color(0.42, 0.46, 0.5) if team == "Allies" else Color(0.36, 0.38, 0.4)
			_hull(tc, 1.8, 1.8, 0.14)
			GroundKit.box(root, Vector3(2.6, 2.2, 3.6), Vector3(0, 3.0, 1.0), tc.lightened(0.12))
			GroundKit.cyl(root, 0.7, 0.8, 3.6, Vector3(0, 4.4, 3.6), Color(0.14, 0.14, 0.15), Vector3.ZERO, 8)
			GroundKit.cyl(root, 0.12, 0.15, 7.0, Vector3(0, 5.5, -1.5), GroundKit.COL_DARK, Vector3.ZERO, 5)
			GroundKit.cyl(root, 0.8, 0.9, 0.7, Vector3(0, 2.4, -6.0), tc.darkened(0.2), Vector3.ZERO, 8)
			GroundKit.cyl(root, 0.12, 0.12, 2.6, Vector3(0, 2.7, -7.2), GroundKit.COL_DARK, Vector3(90, 0, 0), 5, false)
		"cruiser", "battleship":
			var big: bool = stype == "battleship"
			_hull(grey, 2.6 if big else 2.2, 2.4, 0.07)
			GroundKit.box(root, Vector3(_beam * 0.45, 3.0, 7.0), Vector3(0, 4.6, -_len * 0.04), grey.lightened(0.1))
			GroundKit.box(root, Vector3(_beam * 0.32, 2.2, 4.0), Vector3(0, 7.2, -_len * 0.04), grey.lightened(0.16))
			for fz in ([-0.02, 0.18] if big else [0.0, 0.17]):
				GroundKit.cyl(root, 0.9, 1.2, 4.5, Vector3(0, 6.0, _len * fz + 1.0), grey.darkened(0.32), Vector3.ZERO, 8)
			GroundKit.cyl(root, 0.15, 0.2, 11.0, Vector3(0, 10.0, -_len * 0.04 + 2.0), grey.darkened(0.4), Vector3.ZERO, 5)
			var tz: Array = [-0.36, -0.26, 0.3, 0.4] if big else [-0.33, -0.23, 0.33]
			for fz in tz:
				GroundKit.cyl(root, 1.7, 1.8, 1.3, Vector3(0, 3.2, _len * fz), grey.darkened(0.15), Vector3.ZERO, 10)
				for bx in [-0.5, 0.0, 0.5]:
					GroundKit.cyl(root, 0.2, 0.22, 6.0 if big else 4.5, Vector3(bx, 3.5, _len * fz - 3.4), GroundKit.COL_DARK, Vector3(90, 0, 0), 5, false)
		"ferry":
			_hull(Color(0.16, 0.17, 0.2), 2.4, 2.4, 0.12)
			var wh: Color = Color(0.86, 0.85, 0.8)
			GroundKit.box(root, Vector3(_beam * 0.8, 2.8, _len * 0.62), Vector3(0, 4.2, 1.0), wh)
			GroundKit.box(root, Vector3(_beam * 0.62, 2.4, _len * 0.4), Vector3(0, 6.8, 0.0), wh.darkened(0.04))
			GroundKit.box(root, Vector3(_beam * 0.5, 1.6, 3.0), Vector3(0, 8.8, -4.0), wh.darkened(0.08))
			GroundKit.cyl(root, 1.3, 1.5, 5.0, Vector3(0, 10.0, 4.0), Color(0.75, 0.55, 0.2), Vector3.ZERO, 8)
		"landing_craft":
			_hull(Color(0.34, 0.37, 0.3), 0.9, 1.4, 0.35)
			GroundKit.box(root, Vector3(_beam * 0.8, 0.2, _len * 0.55), Vector3(0, 1.45, -1.0), Color(0.3, 0.32, 0.26))
			GroundKit.box(root, Vector3(1.8, 1.6, 2.0), Vector3(0, 2.2, 5.0), Color(0.4, 0.42, 0.34))
			GroundKit.box(root, Vector3(_beam * 0.9, 1.6, 0.2), Vector3(0, 1.6, -_len * 0.5 + 0.6), Color(0.28, 0.3, 0.24), Vector3(-20, 0, 0))
		_:
			_hull(Color(0.3, 0.32, 0.38) if team == "Allies" else Color(0.22, 0.25, 0.3), 1.0, 1.1, 0.12)
			GroundKit.box(root, Vector3(1.8, 1.5, 2.6), Vector3(0, 2.0, 1.5), Color(0.62, 0.55, 0.42))
			GroundKit.cyl(root, 0.08, 0.1, 6.0, Vector3(0, 4.0, -1.0), GroundKit.COL_WOOD, Vector3.ZERO, 5, false)
	_make_wake(root)


func _make_wake(root: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L: float = _len * 2.4
	var w0: float = _beam * 0.5
	var w1: float = _beam * 1.7
	var zs: float = _len * 0.5 - 1.0
	# V-shaped wedge trailing behind the stern (+Z)
	var pts: Array = [
		[Vector3(-w0, 0.12, zs), Color(1, 1, 1, 0.75)], [Vector3(w0, 0.12, zs), Color(1, 1, 1, 0.75)],
		[Vector3(-w1, 0.12, zs + L), Color(1, 1, 1, 0.0)], [Vector3(w1, 0.12, zs + L), Color(1, 1, 1, 0.0)]]
	for idx in [0, 2, 1, 1, 2, 3]:
		st.set_color(pts[idx][1])
		st.set_normal(Vector3.UP)
		st.add_vertex(pts[idx][0])
	# bow wave
	var bw: float = _beam * 0.8
	var bz: float = -_len * 0.5
	var bp: Array = [
		[Vector3(0, 0.12, bz - 1.0), Color(1, 1, 1, 0.8)], [Vector3(-bw, 0.12, bz + _len * 0.25), Color(1, 1, 1, 0.0)],
		[Vector3(bw, 0.12, bz + _len * 0.25), Color(1, 1, 1, 0.0)]]
	for idx in [0, 1, 2]:
		st.set_color(bp[idx][1])
		st.set_normal(Vector3.UP)
		st.add_vertex(bp[idx][0])
	_wake = MeshInstance3D.new()
	_wake.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_wake.material_override = m
	_wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wake)


func _build_wreck(_root: Node3D) -> void:
	pass


func _post_ready() -> void:
	add_to_group("ship")
	if speed > 0.5:
		scale = Vector3.ONE * SHIP_SCALE
		hit_radius *= SHIP_SCALE
	_apply_team_outline()
	if balloon_alt > 0.0:
		var bb: BarrageBalloon = BarrageBalloon.create(team, balloon_alt / scale.x)
		bb.position = Vector3(0.0, balloon_alt / scale.x + 2.0, _len * 0.15)
		add_child(bb)


## Same red (enemy) / yellow (friendly) outline the AI aircraft get, but it carries further because
## ships are usually seen from altitude.
func _apply_team_outline() -> void:
	if team == "Neutral" or not is_instance_valid(_intact):
		return
	var friendly: bool = team == GameState.player_side
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/team_outline.gdshader") as Shader
	m.set_shader_parameter("outline_color", Color(1.0, 0.85, 0.1) if friendly else Color(1.0, 0.16, 0.1))
	m.set_shader_parameter("thickness", 0.12)
	m.set_shader_parameter("dist_scale", 0.0011)
	m.set_shader_parameter("fade_start", 2500.0)
	m.set_shader_parameter("fade_end", 9000.0)
	m.set_shader_parameter("strength", 0.6)
	for n in _intact.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).material_overlay = m
	if route != null and route.length > 1.0:
		_step(0.0, true)


var _lod_f: int = 0
var _lod_skip: int = 1
var _lod_acc: float = 0.0


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_bob_t += delta
	if is_dead:
		_sink = minf(_sink + delta / 20.0, 1.0)
		global_position.y = lerpf(0.0, -_len * 0.22 * scale.y, _sink)
		rotation.z = lerpf(0.0, deg_to_rad(22.0), _sink)
		rotation.x = lerpf(0.0, deg_to_rad(-6.0), _sink)
		if _wake:
			_wake.visible = false
		if _sink >= 1.0 and is_instance_valid(_intact) and _intact.visible:
			# stays as a half-submerged wreck, but hide it after a while to save draw calls
			set_process(false)
		return
	# far ships (beyond their guns' reach) update every few frames with the time they missed
	_lod_f += 1
	if _lod_f % 30 == 1:
		var cam: Camera3D = get_viewport().get_camera_3d()
		var dc: float = cam.global_position.distance_to(global_position) if cam != null else 0.0
		_lod_skip = 1 if dc < 4000.0 else (3 if dc < 9000.0 else 8)
	_lod_acc += delta
	if _lod_skip > 1 and (_lod_f + get_instance_id()) % _lod_skip != 0:
		return
	delta = minf(_lod_acc, 0.1 * float(_lod_skip))
	_lod_acc = 0.0
	_tick_aa(delta)
	if route != null and route.length > 1.0 and speed > 0.0:
		_step(delta, false)
	else:
		global_position.y = 0.1 + sin(_bob_t * 1.4) * 0.12


func _step(delta: float, snap: bool) -> void:
	s += speed * dir * delta
	if wrap:
		s = fposmod(s, route.length)
	elif s > route.length:
		s = route.length
		dir = -1.0
	elif s < 0.0:
		s = 0.0
		dir = 1.0
	var p: Vector3 = route.sample(s)
	var t: Vector3 = route.tangent(s) * dir
	var ty: float = atan2(-t.x, -t.z)
	_yaw = ty if snap else lerp_angle(_yaw, ty, clampf(delta * 1.2, 0.0, 1.0))
	if lateral != 0.0:
		var tf: Vector3 = route.tangent(s)
		p += Vector3(-tf.z, 0.0, tf.x).normalized() * lateral
	global_position = Vector3(p.x, 0.1 + sin(_bob_t * 1.4) * 0.12, p.z)
	rotation.y = _yaw
	rotation.z = sin(_bob_t * 0.9) * 0.012


## Light anti-aircraft fire at the nearest enemy aircraft in range: tracer rounds with a wide spread, the cooldown set
## by hull type (AA_RATE). Weak on purpose; the rounds mostly miss.
func _tick_aa(delta: float) -> void:
	_aa_cd = maxf(_aa_cd - delta, 0.0)
	if _aa_cd > 0.0 or not AA_RATE.has(stype):
		return
	var best: Aircraft = null
	var best_d: float = AA_RANGE
	for n in get_tree().get_nodes_in_group("damageable"):
		var a := n as Aircraft
		if a == null or a.team == team or a.state != Aircraft.State.ALIVE:
			continue
		var d: float = a.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = a
	if best == null:
		return
	_aa_cd = 1.0 / float(AA_RATE[stype])
	var from: Vector3 = global_position + Vector3(0.0, 6.0 * SHIP_SCALE, 0.0)
	var aim: Vector3 = best.global_position + best.velocity * (best_d / 420.0)
	var dir: Vector3 = (aim - from).normalized()
	dir = (dir + Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.1).normalized()
	Weapons.fire_bullet(from + dir * 2.0, dir * 420.0, team, self, AA_DAMAGE, true, 2.2)


func _on_destroyed(_killer: Node) -> void:
	speed = 0.0
	if is_instance_valid(_intact):
		for n in _intact.find_children("*", "MeshInstance3D", true, false):
			(n as MeshInstance3D).material_overlay = null
	if _wake:
		_wake.visible = false
