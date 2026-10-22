class_name V2Rocket
extends Node3D
## A V-2 ballistic rocket. It lifts off slowly from its launch site on a roaring flame, climbs straight up, then
## leans over toward its target and drives up out of sight, leaving a tall, twisting white trail that hangs in
## the sky for minutes. Nothing can catch it. A few minutes later it falls out of the sky faster than sound -
## no warning, just a huge blast, then fires in the streets and a pillar of smoke.
##   V2Rocket.launch(parent, from, to)    signal impact(pos)

signal impact(pos: Vector3)

const BOOST_TIME: float = 62.0      # powered flight we show (it is out of sight long before burnout)
const HIDE_TIME: float = 70.0       # time "in space" before the terminal plunge (compressed from ~4 min)
const FALL_TIME: float = 5.0

var target: Vector3
var _from: Vector3
var _t: float = 0.0
var _vel: Vector3 = Vector3.ZERO
var _phase: int = 0                 # 0 boost, 1 hidden, 2 falling, 3 done
var _trail_t: float = 0.0
var _flame: MeshInstance3D
var _light: OmniLight3D
var _body: Node3D
var _fall_from: Vector3


static func launch(parent: Node, from: Vector3, to: Vector3) -> V2Rocket:
	var r := V2Rocket.new()
	parent.add_child(r)
	r._from = Vector3(from.x, maxf(GroundKit.ground_y(from.x, from.z), 0.0) + 8.0, from.z)
	r.target = Vector3(to.x, maxf(GroundKit.ground_y(to.x, to.z), 0.0), to.z)
	r.global_position = r._from
	return r


func _ready() -> void:
	top_level = true
	add_to_group("v2_rocket")
	_body = Node3D.new()
	add_child(_body)
	var white := Color(0.82, 0.8, 0.72)
	var dark := Color(0.12, 0.12, 0.11)
	var hull := ToonUtil.make_mesh(CylinderMesh.new(), white, {"outline": false})
	var cm := hull.mesh as CylinderMesh
	cm.top_radius = 0.75
	cm.bottom_radius = 0.82
	cm.height = 11.0
	hull.position = Vector3(0, 5.5, 0)
	_body.add_child(hull)
	var nose := ToonUtil.make_mesh(CylinderMesh.new(), white, {"outline": false})
	var nm := nose.mesh as CylinderMesh
	nm.top_radius = 0.02
	nm.bottom_radius = 0.75
	nm.height = 3.0
	nose.position = Vector3(0, 12.5, 0)
	_body.add_child(nose)
	for i in 4:      # the black-and-white fins
		var fin := ToonUtil.make_mesh(BoxMesh.new(), dark if i % 2 == 0 else white, {"outline": false})
		(fin.mesh as BoxMesh).size = Vector3(0.12, 3.0, 2.0)
		fin.rotation.y = TAU * 0.25 * float(i)
		fin.position = Vector3(cos(TAU * 0.25 * float(i)) * 1.1, 1.4, -sin(TAU * 0.25 * float(i)) * 1.1)
		_body.add_child(fin)
	_flame = MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.7
	fm.bottom_radius = 0.05
	fm.height = 9.0
	_flame.mesh = fm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.75, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.2)
	mat.emission_energy_multiplier = 8.0
	_flame.material_override = mat
	_flame.position = Vector3(0, -4.5, 0)
	_body.add_child(_flame)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.65, 0.3)
	_light.light_energy = 6.0
	_light.omni_range = 600.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, -8.0, 0)
	_body.add_child(_light)
	_body.scale = Vector3.ONE * 1.6
	# lift-off: a ground cloud of exhaust smoke boiling out round the pad
	for i in 26:
		var a: float = randf() * TAU
		var d := Vector3(cos(a), 0.0, sin(a))
		FX.pillars.spawn(_from + d * 6.0, d * randf_range(14.0, 30.0) + Vector3(0, randf_range(1.0, 6.0), 0), randf_range(18.0, 30.0),
			10.0, randf_range(40.0, 70.0), Color(0.92, 0.9, 0.86, 0.8), Color(0.95, 0.95, 0.95, 0.0), 1.0, 0.0, 0.6)
	FX.sfx("rocket", _from, 6.0, 0.0)


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_t += delta
	match _phase:
		0:
			_boost(delta)
		1:
			if _t >= BOOST_TIME + HIDE_TIME:
				_begin_fall()
		2:
			_fall(delta)


func _boost(delta: float) -> void:
	# slow, majestic lift-off, then hard acceleration; pitch over toward the target after ~6 s
	var acc: float = lerpf(9.0, 34.0, clampf(_t / 20.0, 0.0, 1.0))
	var to: Vector3 = target - global_position
	to.y = 0.0
	var flat: Vector3 = to.normalized() if to.length() > 1.0 else Vector3.FORWARD
	var tilt: float = clampf((_t - 6.0) / 30.0, 0.0, 1.0) * deg_to_rad(42.0)
	var dir: Vector3 = (Vector3.UP * cos(tilt) + flat * sin(tilt)).normalized()
	_vel = _vel.lerp(dir * _vel.length(), clampf(delta * 0.8, 0.0, 1.0)) + dir * acc * delta
	global_position += _vel * delta
	if _vel.length() > 0.1:
		_body.basis = Basis(Quaternion(Vector3.UP, _vel.normalized()))
	_flame.scale = Vector3.ONE * (0.9 + 0.25 * sin(_t * 47.0))
	_light.light_energy = 6.0 * (1.0 - clampf(_t / 30.0, 0.0, 1.0))
	_trail_t -= delta
	if _trail_t <= 0.0:
		_trail_t = 0.06
		# the trail: thick white puffs that hang for minutes and get blown into a zig-zag by the winds aloft
		var hi: float = clampf(global_position.y / 30000.0, 0.0, 1.0)
		var wind := Vector3(sin(global_position.y * 0.0007) * 7.0, 0.0, cos(global_position.y * 0.0005) * 5.0)
		FX.pillars.spawn(global_position - _vel.normalized() * 14.0 + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)), wind, randf_range(110.0, 170.0),
			16.0 + 22.0 * hi, 70.0 + 110.0 * hi, Color(0.97, 0.96, 0.93, 0.92), Color(0.9, 0.9, 0.92, 0.0), 0.9, 0.0, 0.05)
		# the motor: a fierce white-orange flare you can pick out from miles away
		FX._spawn_star(global_position - _vel.normalized() * 10.0, 60.0 + 40.0 * FX.night_factor(), 0.1, Color(1.0, 0.7, 0.3), Color(1.0, 0.97, 0.85), 6.0)
		if _t < 25.0:
			FX.puffs.spawn(global_position - _vel.normalized() * 8.0, -_vel * 0.05, 0.5, 4.0, 1.5,
				Color(1.0, 0.85, 0.4, 1.0), Color(1.0, 0.4, 0.1, 0.0), 0.0, 0.0, 0.0)
	if _t >= BOOST_TIME or global_position.y > 40000.0:
		_phase = 1
		visible = false


func _begin_fall() -> void:
	_phase = 2
	visible = true
	_flame.visible = false
	_light.visible = false
	var back: Vector3 = (_from - target)
	back.y = 0.0
	back = back.normalized()
	# it comes down almost vertically at ~3 500 km/h: a few seconds from 9 km up to the ground
	_fall_from = target + back * 2400.0 + Vector3(0, 18000.0, 0)
	global_position = _fall_from
	_vel = (target - _fall_from) / FALL_TIME
	_body.basis = Basis(Quaternion(Vector3.UP, _vel.normalized()))


func _fall(delta: float) -> void:
	global_position += _vel * delta
	_trail_t -= delta
	if _trail_t <= 0.0:
		_trail_t = 0.05
		FX.puffs.spawn(global_position, Vector3.ZERO, 6.0, 3.0, 10.0, Color(0.85, 0.85, 0.85, 0.35), Color(0.9, 0.9, 0.9, 0.0), 1.0, 0.0, 0.0)
	if global_position.y <= target.y + 4.0 or _t > BOOST_TIME + HIDE_TIME + FALL_TIME + 2.0:
		_detonate()


func _detonate() -> void:
	_phase = 3
	var p: Vector3 = Vector3(global_position.x, target.y, global_position.z)
	# a ton of explosive arriving faster than sound: the blast is enormous
	FX.explosion(p + Vector3(0, 4, 0), 44.0)
	FX.crater(p, 26.0)
	FX.debris(p, 24, 4.0, 110.0)
	FX.light_flash(p + Vector3(0, 30, 0), 18.0, 900.0, 1.2, Color(1.0, 0.65, 0.3))
	CityFires.ignite(p, 3.0, true)
	if Weapons != null:
		Weapons.explode_at(p, 70.0, 400.0, "Axis")
	impact.emit(p)
	queue_free()


func is_destroyed() -> bool:
	return _phase >= 3
