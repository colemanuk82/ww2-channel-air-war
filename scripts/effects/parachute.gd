class_name Parachute
extends Node3D
## Pooled parachuting pilot. FX.parachute(pos) launches one; it drifts down and hides itself after landing.

const FALL_SPEED := 9.0

var active: bool = false
var _t: float = 0.0
var _landed_t: float = -1.0
var _land_pose: float = 0.0
var _canopy: MeshInstance3D
var _sway: float = 0.0
var _drift: Vector3 = Vector3.ZERO
var team: String = ""          # the pilot's side; enemies of the player can be shot or flown into
var hit_radius: float = 2.5   # damage contract
const POINTS := 100


func _ready() -> void:
	visible = false
	_canopy = ToonUtil.make_mesh(_canopy_mesh(), Color(0.9, 0.88, 0.75), {"outline_thickness": 0.05})
	_canopy.position = Vector3(0, 7.0, 0)
	_canopy.scale = Vector3(1.0, 0.55, 1.0)
	add_child(_canopy)
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)


static func _canopy_mesh() -> Mesh:
	var sm := SphereMesh.new()
	sm.radius = 3.4
	sm.height = 6.8
	sm.radial_segments = 16
	sm.rings = 8
	return sm


# ---------------------------------------------------------------- the pilot figure

var _rig: Node3D                # suspension lines + the pilot, rebuilt when the side changes
var _look: String = ""
var _pilot: Node3D              # whole pilot, hangs from the harness and swings
var _head: Node3D
var _limbs: Array = []          # {node, ang (Vector2: x pitch / z roll), vel, base, phase, amp}


## det: toon detail mode - 8 cloth (default), 9 leather, 10 skin (see detail_kit in toon.gdshader)
func _part(parent: Node3D, mesh: Mesh, col: Color, pos: Vector3, scl: Vector3 = Vector3.ONE, det: int = 8) -> MeshInstance3D:
	var mi: MeshInstance3D = ToonUtil.make_mesh(mesh, col, {"outline_thickness": 0.025, "detail": det})
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _box_m(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


func _sph_m(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 12
	m.rings = 6
	return m


func _cap_m(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 10
	m.rings = 4
	return m


## A two-segment limb hanging from a pivot: upper part and (bent) lower part, with a hand/boot at the end.
func _limb(parent: Node3D, pivot_pos: Vector3, upper: float, lower: float, r: float, col: Color, end_col: Color, end_size: Vector3, phase: float, amp: float, base_x: float, base_z: float) -> void:
	var piv := Node3D.new()
	piv.position = pivot_pos
	parent.add_child(piv)
	_part(piv, _cap_m(r, upper + r), col, Vector3(0, -upper * 0.5, 0))
	var knee := Node3D.new()
	knee.position = Vector3(0, -upper, 0)
	piv.add_child(knee)
	_part(knee, _cap_m(r * 0.88, lower + r), col, Vector3(0, -lower * 0.5, 0))
	_part(knee, _box_m(end_size.x, end_size.y, end_size.z), end_col, Vector3(0, -lower - end_size.y * 0.3, end_size.z * 0.18), Vector3.ONE, 9)
	_limbs.append({"node": piv, "knee": knee, "ang": Vector2(base_x, base_z), "vel": Vector2.ZERO, "base": Vector2(base_x, base_z), "phase": phase, "amp": amp})


func _build_pilot(side: String) -> void:
	_look = side
	for c in _rig.get_children():
		c.queue_free()
	_limbs.clear()
	var axis: bool = side == "Axis"
	var cloth: Color = Color(0.5, 0.47, 0.36) if axis else Color(0.28, 0.33, 0.42)       # Luftwaffe tan flying suit / RAF blue-grey
	var cloth2: Color = cloth.darkened(0.12)
	var skin: Color = Color(0.86, 0.66, 0.53)
	var leather: Color = Color(0.5, 0.4, 0.27) if axis else Color(0.33, 0.22, 0.13)
	var vest: Color = Color(0.82, 0.78, 0.62) if axis else Color(0.92, 0.74, 0.1)         # Schwimmweste khaki / RAF Mae West yellow
	var boots: Color = Color(0.1, 0.09, 0.08) if axis else Color(0.16, 0.11, 0.07)
	var strap: Color = Color(0.1, 0.1, 0.08)
	# suspension lines: canopy rim -> two riser tops above the shoulders, risers -> harness
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in 10:
		var a: float = TAU * float(i) / 10.0
		var rim := Vector3(cos(a) * 3.25, 6.95, sin(a) * 3.25)
		var top := Vector3(0.26 if cos(a) > 0.0 else -0.26, 1.15, 0.0)
		lines.surface_add_vertex(rim)
		lines.surface_add_vertex(top)
	for sx in [-1.0, 1.0]:
		lines.surface_add_vertex(Vector3(sx * 0.26, 1.15, 0.0))
		lines.surface_add_vertex(Vector3(sx * 0.27, 0.62, 0.05))
	lines.surface_end()
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.14, 0.12, 0.09)
	var li := MeshInstance3D.new()
	li.mesh = lines
	li.material_override = lm
	li.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig.add_child(li)
	# the pilot, hanging in the harness (origin = middle of the body)
	_pilot = Node3D.new()
	_rig.add_child(_pilot)
	_part(_pilot, _box_m(0.52, 0.66, 0.3), cloth, Vector3(0, 0.22, 0))                    # torso
	_part(_pilot, _box_m(0.58, 0.46, 0.36), vest, Vector3(0, 0.3, 0.01))                  # life jacket over the chest
	if not axis:
		_part(_pilot, _box_m(0.2, 0.1, 0.34), vest.darkened(0.15), Vector3(0, 0.56, 0.0))  # Mae West collar bladders
	_part(_pilot, _box_m(0.5, 0.2, 0.3), cloth2, Vector3(0, -0.2, 0))                     # hips
	_part(_pilot, _box_m(0.56, 0.06, 0.34), strap, Vector3(0, -0.12, 0), Vector3.ONE, 9)                  # harness belt
	for sx in [-1.0, 1.0]:
		_part(_pilot, _box_m(0.07, 0.62, 0.34), strap, Vector3(sx * 0.2, 0.26, 0.01))     # shoulder straps
	_part(_pilot, _box_m(0.2, 0.1, 0.2), skin, Vector3(0, 0.62, 0), Vector3.ONE, 10)                     # neck
	_head = Node3D.new()
	_head.position = Vector3(0, 0.78, 0)
	_pilot.add_child(_head)
	_part(_head, _sph_m(0.17), skin, Vector3.ZERO, Vector3(0.95, 1.05, 1.0), 10)              # face
	_part(_head, _sph_m(0.19), leather, Vector3(0, 0.05, 0.015), Vector3(1.0, 0.82, 1.05), 9) # flying helmet
	for sx in [-1.0, 1.0]:
		_part(_head, _box_m(0.05, 0.14, 0.12), leather.darkened(0.1), Vector3(sx * 0.18, -0.01, 0.0), Vector3.ONE, 9)   # ear flaps / earphones
	_part(_head, _box_m(0.34, 0.06, 0.06), Color(0.08, 0.08, 0.07), Vector3(0, 0.1, -0.15), Vector3.ONE, 9)             # goggle strap + frames pushed up
	for sx in [-1.0, 1.0]:
		_part(_head, _sph_m(0.05), Color(0.25, 0.3, 0.32), Vector3(sx * 0.07, 0.1, -0.17), Vector3(1.0, 0.8, 0.6))
	_part(_head, _box_m(0.17, 0.12, 0.08), Color(0.22, 0.24, 0.2) if not axis else Color(0.45, 0.46, 0.44), Vector3(0, -0.07, -0.15), Vector3.ONE, 9)  # oxygen mask, hanging loose
	if axis:
		_part(_head, _box_m(0.04, 0.05, 0.2), leather.darkened(0.25), Vector3(0, 0.2, 0.0), Vector3.ONE, 9)             # helmet seam
	# arms: hands up on the risers; legs hanging with a slight knee bend
	for sx in [-1.0, 1.0]:
		_limb(_pilot, Vector3(sx * 0.34, 0.5, 0.0), 0.32, 0.3, 0.075, cloth, leather, Vector3(0.12, 0.12, 0.12), sx * 1.3, 0.35, 2.5, sx * 0.18)
		_limb(_pilot, Vector3(sx * 0.14, -0.28, 0.0), 0.42, 0.42, 0.095, cloth2, boots, Vector3(0.16, 0.16, 0.3), sx * 2.4 + 0.7, 0.28, 0.0, sx * 0.04)


func launch(pos: Vector3, p_team: String = "", p_look: String = "") -> void:
	team = p_team
	var look: String = p_look if p_look != "" else (p_team if p_team != "" else "Allies")
	if look != _look and _rig != null:
		_build_pilot(look)
	_canopy_col(look)
	if team != "":
		add_to_group("damageable")
	global_position = pos
	_t = 0.0
	_landed_t = -1.0
	_sway = randf() * TAU
	_drift = Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
	active = true
	visible = true
	rotation = Vector3.ZERO
	if _canopy:
		_canopy.scale = Vector3(0.2, 0.1, 0.2)
	_land_pose = 0.0
	for l in _limbs:
		l["ang"] = l["base"] + Vector2(randf_range(-0.8, 0.8), randf_range(-0.4, 0.4))
		l["vel"] = Vector2.ZERO
	if _pilot:
		_pilot.position = Vector3.ZERO
		_pilot.rotation = Vector3.ZERO


func _process(delta: float) -> void:
	if not active:
		return
	delta = minf(delta, 0.05)
	_t += delta
	if _check_ram():
		return
	if _landed_t >= 0.0:
		_landed_t += delta
		_animate(delta, 1.0, true)
		if _landed_t > 6.0:
			active = false
			visible = false
			remove_from_group("damageable")
		elif _canopy:
			_canopy.scale = _canopy.scale.lerp(Vector3(1.0, 0.1, 1.0), minf(delta * 2.0, 1.0))
		return
	var open: float = clampf((_t - 0.6) / 1.0, 0.0, 1.0)
	var fall: float = lerpf(35.0, FALL_SPEED, open)
	if _canopy:
		_canopy.scale = Vector3(lerpf(0.2, 1.0, open), lerpf(0.1, 0.55, open), lerpf(0.2, 1.0, open))
	var p: Vector3 = global_position + (Vector3.DOWN * fall + _drift * open) * delta
	global_position = p
	rotation.z = sin(_t * 1.6 + _sway) * 0.14 * open
	_animate(delta, open, false)
	var gh: float = FX.ground_height(p)
	if p.y <= gh + 0.9:
		_landed_t = 0.0
		global_position = Vector3(p.x, gh + 0.9, p.z)
		rotation = Vector3.ZERO
		if FX.is_water(p):
			FX.water_splash(p, 2.0)


## Damage contract: any hit (bullet, cannon, ram) brings the pilot down.
func take_damage(_amount: float, source: Node = null) -> void:
	if not active:
		return
	_down(source)


func _down(source: Node) -> void:
	active = false
	visible = false
	remove_from_group("damageable")
	FX.explosion(global_position + Vector3(0, 2.0, 0), 0.5)
	if WeaponWorld.is_player_source(source):
		var gm: Node = get_tree().get_first_node_in_group("game_mode")
		if gm != null and gm.has_method("add_score"):
			gm.call("add_score", POINTS)
		Weapons.player_kill.emit(self)


## Player aircraft flying into an enemy pilot brings it down.
func _check_ram() -> bool:
	if team == "":
		return false
	for n in get_tree().get_nodes_in_group("aircraft"):
		var a := n as Aircraft
		if a == null or not a.player_controlled or a.state != Aircraft.State.ALIVE or a.team == team:
			continue
		if a.global_position.distance_to(global_position + Vector3(0, 3.0, 0)) < a.hit_radius + 3.0:
			_down(a)
			return true
	return false


func _canopy_col(look: String) -> void:
	if _canopy == null:
		return
	var m: Material = _canopy.get_active_material(0)
	var c: Color = Color(0.93, 0.9, 0.78) if look != "Axis" else Color(0.84, 0.86, 0.8)
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter("albedo", c)
	elif m is BaseMaterial3D:
		(m as BaseMaterial3D).albedo_color = c


## Rag-doll motion: each limb is a damped spring chasing a swing target. In free fall (open ~ 0) the limbs
## flail; under the canopy the body hangs and swings like a pendulum and the limbs lag behind it. On the ground
## everything goes limp and the pilot slumps over.
func _animate(delta: float, open: float, landed: bool) -> void:
	if _pilot == null:
		return
	var sway_v: float = cos(_t * 1.6 + _sway) * 1.6 * 0.14 * open        # angular velocity of the swing
	var flail: float = 1.0 - open
	if landed:
		_land_pose = minf(_land_pose + delta * 1.6, 1.0)
		_pilot.rotation.x = lerpf(0.0, 1.35, _land_pose)
		_pilot.position.y = lerpf(0.0, -0.5, _land_pose)
	else:
		_pilot.rotation.z = sin(_t * 1.1 + _sway + 1.0) * 0.06 * open
		_pilot.rotation.x = sin(_t * 0.8 + _sway) * 0.05 * open - flail * 0.35
	if _head:
		_head.rotation = Vector3(sin(_t * 1.7 + _sway) * 0.12 + flail * sin(_t * 8.0) * 0.4, sin(_t * 0.9) * 0.3 * open, sin(_t * 1.3) * 0.08)
	var k: float = 38.0
	var c: float = 5.5
	for l in _limbs:
		var base: Vector2 = l["base"]
		var tgt: Vector2 = base
		if landed:
			tgt = Vector2(base.x * 0.2 + 0.2 * sign(l["phase"]) , base.y * 2.0)
		else:
			tgt = base + Vector2(-sway_v * 0.9 * (1.0 if base.x > 1.0 else -1.0), sway_v * 0.6) + Vector2(sin(_t * 2.1 + float(l["phase"])) * 0.12, sin(_t * 1.7 + float(l["phase"])) * 0.08)
			tgt += Vector2(sin(_t * 9.0 + float(l["phase"])) * 0.7, sin(_t * 7.0 + float(l["phase"]) * 1.7) * 0.5) * flail
		var ang: Vector2 = l["ang"]
		var vel: Vector2 = l["vel"]
		vel += ((tgt - ang) * k - vel * c) * delta
		ang += vel * delta
		l["ang"] = ang
		l["vel"] = vel
		var node: Node3D = l["node"]
		node.rotation = Vector3(ang.x, 0.0, ang.y)
		var kn: Node3D = l["knee"]
		var bend: float = 0.25 + 0.2 * sin(_t * 1.9 + float(l["phase"])) * open + flail * 0.5
		kn.rotation.x = -bend if base.x < 1.0 else -bend * 1.5
