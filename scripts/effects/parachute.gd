class_name Parachute
extends Node3D
## Pooled parachuting pilot. FX.parachute(pos) launches one; it drifts down and hides itself after landing.

const FALL_SPEED := 9.0

var active: bool = false
var _t: float = 0.0
var _landed_t: float = -1.0
var _canopy: MeshInstance3D
var _sway: float = 0.0
var _drift: Vector3 = Vector3.ZERO
var team: String = ""          # the pilot's side; enemies of the player can be shot or flown into
var hit_radius: float = 2.5   # damage contract
const POINTS := 100


func _ready() -> void:
	visible = false
	var sm := SphereMesh.new()
	sm.radius = 3.4
	sm.height = 6.8
	sm.radial_segments = 12
	sm.rings = 6
	_canopy = ToonUtil.make_mesh(sm, Color(0.9, 0.88, 0.75), {"outline_thickness": 0.05})
	_canopy.position = Vector3(0, 7.0, 0)
	_canopy.scale = Vector3(1.0, 0.55, 1.0)
	add_child(_canopy)
	var body := CapsuleMesh.new()
	body.radius = 0.45
	body.height = 1.7
	add_child(ToonUtil.make_mesh(body, Color(0.35, 0.36, 0.28), {"outline_thickness": 0.04}))
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in 6:
		var a: float = TAU * float(i) / 6.0
		lines.surface_add_vertex(Vector3(cos(a) * 3.2, 6.9, sin(a) * 3.2))
		lines.surface_add_vertex(Vector3(0, 0.7, 0))
	lines.surface_end()
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.12, 0.1, 0.08)
	var li := MeshInstance3D.new()
	li.mesh = lines
	li.material_override = lm
	li.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(li)


func launch(pos: Vector3, p_team: String = "") -> void:
	team = p_team
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


func _process(delta: float) -> void:
	if not active:
		return
	delta = minf(delta, 0.05)
	_t += delta
	if _check_ram():
		return
	if _landed_t >= 0.0:
		_landed_t += delta
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
