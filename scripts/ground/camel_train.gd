class_name CamelTrain
extends Node3D
## A camel caravan walking a piste: 6-18 camels with handlers implied by gaps, small bob, dust at their feet.
## Cheap: one merged camel mesh reused by a handful of MeshInstance3D nodes that only move when near the camera.

const DesertScatter = preload("res://scripts/ground/desert_scatter.gd")

static var _mesh: ArrayMesh

var route: RoutePath
var s: float = 0.0
var speed: float = 1.25
var count: int = 10
var spacing: float = 3.4
var _camels: Array = []
var _dust_t: float = 0.0


static func create(p_route: RoutePath, p_start: float, p_count: int = 10, p_speed: float = 1.25) -> CamelTrain:
	var c := CamelTrain.new()
	c.route = p_route
	c.s = p_start
	c.count = clampi(p_count, 3, 18)
	c.speed = p_speed
	return c


func _ready() -> void:
	if _mesh == null:
		_mesh = _build_mesh()
	for i in count:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_camels.append(mi)
	_step(0.0)


func _process(delta: float) -> void:
	if route == null or route.length < 2.0:
		return
	s = fposmod(s + speed * delta, route.length)
	# far away the caravan is a few pixels: only move it every other frame and skip the bob
	var cam: Camera3D = get_viewport().get_camera_3d()
	var far: bool = cam != null and cam.global_position.distance_to(global_position) > 4500.0
	if far and (Engine.get_process_frames() % 3) != 0:
		return
	_step(delta)
	if far:
		return
	_dust_t -= delta
	if _dust_t <= 0.0:
		_dust_t = 0.55
		GroundKit.fx_call("dust", [global_position, 1.1])


func _step(_delta: float) -> void:
	if route == null or route.length < 2.0:
		return
	var head: Vector3 = route.sample(s)
	var hy: float = GroundKit.ground_y(head.x, head.z)
	global_position = Vector3(head.x, hy, head.z)
	for i in _camels.size():
		var ss: float = fposmod(s - float(i) * spacing, route.length)
		var p: Vector3 = route.sample(ss)
		var t: Vector3 = route.tangent(ss)
		var gy: float = GroundKit.ground_y(p.x, p.z)
		var bob: float = sin(Time.get_ticks_msec() * 0.006 + float(i) * 1.7) * 0.05
		var mi: MeshInstance3D = _camels[i]
		mi.position = Vector3(p.x - global_position.x, gy - global_position.y + bob, p.z - global_position.z)
		mi.rotation.y = atan2(-t.x, -t.z)


func _build_mesh() -> ArrayMesh:
	var parts: Array = []
	var hide := Color(0.74, 0.64, 0.47)
	var dark := Color(0.56, 0.46, 0.33)
	var body := BoxMesh.new()
	body.size = Vector3(1.9, 0.85, 0.75)
	parts.append(DesertScatter._part(body, Vector3(0, 1.75, 0), hide, false))
	var hump := SphereMesh.new()
	hump.radius = 0.46
	hump.height = 0.92
	parts.append(DesertScatter._part(hump, Vector3(0, 2.24, 0), hide, false))
	var neck := BoxMesh.new()
	neck.size = Vector3(0.34, 0.95, 0.34)
	parts.append(DesertScatter._part(neck, Vector3(0, 2.36, -0.92), hide, false))
	var head := BoxMesh.new()
	head.size = Vector3(0.4, 0.32, 0.62)
	parts.append(DesertScatter._part(head, Vector3(0, 2.80, -1.30), dark, false))
	for sx in [-0.6, 0.6]:
		for sz in [-0.55, 0.55]:
			var leg := BoxMesh.new()
			leg.size = Vector3(0.17, 1.35, 0.17)
			parts.append(DesertScatter._part(leg, Vector3(sx, 0.68, sz), dark, false))
	var tail := BoxMesh.new()
	tail.size = Vector3(0.1, 0.7, 0.1)
	parts.append(DesertScatter._part(tail, Vector3(0, 1.6, 0.85), dark, false))
	return Scatter._merge(parts)
