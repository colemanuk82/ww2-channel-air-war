class_name FlyingBomb
extends Node3D
## A V-1 flying bomb ("Diver"): straight and level at ~600 m and ~600 km/h from its launch site toward a city,
## pulse-jet flame and a smoke trail. Shoot it (any hit brings it down) before it gets there; if it does, it
## dives in and explodes. Damage contract: group "damageable", team, hit_radius, take_damage, signal destroyed.
## Spawned by the Ops Room when the V-1 threat is up (missed strikes on the V-1 sites).

signal destroyed(node: Node, killer: Node)
signal impact(node: Node)

var team: String = "Axis"
var hit_radius: float = 9.0
var target: Vector3 = Vector3.ZERO
var speed: float = 165.0                 # world units / s (~600 km/h)
var is_dead: bool = false
var _dir: Vector3 = Vector3.FORWARD
var _diving: bool = false
var _trail_t: float = 0.0
var _flame: MeshInstance3D


var _ramping: bool = false
var _ramp_v: float = 0.0          # climb rate during the ramp take-off (units/s)


## A V-1 taking off from its ramp: it starts on the ground and climbs out under its own pulse-jet before it levels
## off at cruise height. Anyone near the site can watch it go up, and it can be shot down during the climb.
static func launch_from_ramp(parent: Node, from: Vector3, to: Vector3) -> FlyingBomb:
	var b := FlyingBomb.new()
	parent.add_child(b)
	b.target = to
	var g: float = maxf(GroundKit.ground_y(from.x, from.z), 0.0)
	b.global_position = Vector3(from.x, g + 2.0, from.z)
	var d: Vector3 = to - from
	d.y = 0.0
	b._dir = d.normalized()
	b._ramping = true
	b.look_at(b.global_position + b._dir, Vector3.UP)
	return b


static func launch(parent: Node, from: Vector3, to: Vector3) -> FlyingBomb:
	var b := FlyingBomb.new()
	parent.add_child(b)
	b.target = to
	b.global_position = Vector3(from.x, maxf(GroundKit.ground_y(from.x, from.z), 0.0) + 1200.0, from.z)
	var d: Vector3 = to - from
	d.y = 0.0
	b._dir = d.normalized()
	b.look_at(b.global_position + b._dir, Vector3.UP)
	return b


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("flying_bomb")
	var grey := Color(0.36, 0.38, 0.33)
	var body := ToonUtil.make_mesh(CylinderMesh.new(), grey, {"outline": false})
	var cm := body.mesh as CylinderMesh
	cm.top_radius = 0.42
	cm.bottom_radius = 0.42
	cm.height = 7.6
	body.rotation.x = deg_to_rad(90.0)
	add_child(body)
	var nose := ToonUtil.make_mesh(SphereMesh.new(), grey, {"outline": false})
	(nose.mesh as SphereMesh).radius = 0.42
	(nose.mesh as SphereMesh).height = 1.4
	nose.position = Vector3(0, 0, -3.8)
	add_child(nose)
	var wing := ToonUtil.make_mesh(BoxMesh.new(), grey, {"outline": false})
	(wing.mesh as BoxMesh).size = Vector3(5.3, 0.12, 1.1)
	wing.position = Vector3(0, 0, -0.3)
	add_child(wing)
	var tail := ToonUtil.make_mesh(BoxMesh.new(), grey, {"outline": false})
	(tail.mesh as BoxMesh).size = Vector3(2.0, 0.1, 0.7)
	tail.position = Vector3(0, 0.15, 3.3)
	add_child(tail)
	var jet := ToonUtil.make_mesh(CylinderMesh.new(), grey.darkened(0.3), {"outline": false})
	var jm := jet.mesh as CylinderMesh
	jm.top_radius = 0.28
	jm.bottom_radius = 0.22
	jm.height = 3.6
	jet.rotation.x = deg_to_rad(90.0)
	jet.position = Vector3(0, 0.75, 2.6)
	add_child(jet)
	_flame = MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.35
	fm.height = 2.2
	_flame.mesh = fm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.6, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.1)
	mat.emission_energy_multiplier = 4.0
	_flame.material_override = mat
	_flame.position = Vector3(0, 0.75, 4.8)
	_flame.rotation.x = deg_to_rad(90.0)
	add_child(_flame)
	scale = Vector3.ONE * 1.6     # a little larger than life so it can be found


func _process(delta: float) -> void:
	if is_dead:
		return
	if _ramping:
		_ramp(delta)
		return
	var p: Vector3 = global_position
	var flat: float = Vector2(target.x - p.x, target.z - p.z).length()
	if not _diving and flat < 1500.0:
		_diving = true        # engine cuts, it noses over (the silence Londoners dreaded)
		_flame.visible = false
	if _diving:
		var to: Vector3 = (target - p).normalized()
		_dir = _dir.lerp(to, clampf(delta * 1.5, 0.0, 1.0)).normalized()
	global_position = p + _dir * speed * delta
	look_at(global_position + _dir, Vector3.UP if absf(_dir.y) < 0.95 else Vector3.FORWARD)
	if not _diving:
		_flame.scale = Vector3.ONE * (0.7 + 0.6 * absf(sin(Time.get_ticks_msec() * 0.06)))
		_trail_t -= delta
		if _trail_t <= 0.0:
			_trail_t = 0.08
			FX.puffs.spawn(global_position - _dir * 9.0 + Vector3(0, 1.2, 0), Vector3.ZERO, 3.0, 0.8, 4.0,
				Color(0.55, 0.55, 0.52, 0.5), Color(0.6, 0.6, 0.58, 0.0), 0.8, 0.0, 0.3)
	if global_position.y <= maxf(GroundKit.ground_y(global_position.x, global_position.z), 0.0) + 2.0:
		is_dead = true
		FX.explosion(global_position, 26.0)
		CityFires.ignite(global_position, 2.0, true)
		impact.emit(self)
		queue_free()


## Climb-out from the ramp: the bomb gains height at a steady rate while the pulse-jet pushes it forward, then levels
## off at cruise height (about 600 m above the ground) and carries on as an ordinary flying bomb.
func _ramp(delta: float) -> void:
	_ramp_v = minf(_ramp_v + 60.0 * delta, 95.0)
	var p: Vector3 = global_position
	var g: float = maxf(GroundKit.ground_y(p.x, p.z), 0.0)
	var fwd: float = minf(40.0 + _ramp_v * 1.2, speed)
	var ny: float = minf(p.y + _ramp_v * delta, g + 1200.0)
	global_position = Vector3(p.x, ny, p.z) + _dir * fwd * delta
	look_at(global_position + (_dir + Vector3.UP * 0.7).normalized(), Vector3.UP)
	if ny >= g + 1199.0:
		_ramping = false
	_trail_t -= delta
	if _trail_t <= 0.0:
		_trail_t = 0.08
		FX.puffs.spawn(global_position - _dir * 9.0 + Vector3(0, 1.2, 0), Vector3.ZERO, 3.0, 0.8, 4.0,
			Color(0.55, 0.55, 0.52, 0.5), Color(0.6, 0.58, 0.58, 0.0), 0.8, 0.0, 0.3)


func take_damage(_amount: float, source: Node = null) -> void:
	if is_dead:
		return
	if WeaponWorld.is_player_source(source):
		Weapons.player_hit.emit(self, _amount)
	is_dead = true
	remove_from_group("damageable")
	FX.explosion(global_position, 14.0)
	destroyed.emit(self, source)
	if WeaponWorld.is_player_source(source):
		Weapons.player_kill.emit(self)
	queue_free()


func is_destroyed() -> bool:
	return is_dead
