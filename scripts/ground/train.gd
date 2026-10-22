class_name Train
extends Node3D
## Steam train running on a rail RoutePath. Every car is a strafe-able GroundTarget (TrainCar). Killing the
## locomotive stops the train. Mission-target aware (kill_fraction of cars). Add under a node at world origin.

signal unit_destroyed(unit: Node, killer: Node)
signal destroyed(node: Node, killer: Node)

var target_id: String = ""
var display_name: String = "Train"
var team: String = "Axis"
var is_mission_target: bool = false
var kill_fraction: float = 0.5
var route: RoutePath
var s: float = 0.0
var speed: float = 14.0
var spec: Array = ["loco", "boxcar", "boxcar", "flatcar", "tanker", "boxcar", "flak", "boxcar"]
var cars: Array = []
var dead_count: int = 0
var is_dead: bool = false
const SPACING: float = 17.0
var _frame: int = 0


static func create(p_team: String, p_route: RoutePath, start_s: float = 0.0, p_speed: float = 14.0, p_spec: Array = []) -> Train:
	var t := Train.new()
	t.team = p_team
	t.route = p_route
	t.s = start_s
	t.speed = p_speed
	if not p_spec.is_empty():
		t.spec = p_spec
	return t


func _ready() -> void:
	add_to_group("train")
	if is_mission_target:
		add_to_group("mission_target")
	if route == null or route.length < SPACING * 2.0:
		return
	for i in spec.size():
		var c: TrainCar = TrainCar.create(spec[i], team)
		c.train = self
		c.set_meta("convoy_id", target_id)
		c.destroyed.connect(_on_car_destroyed)
		add_child(c)
		cars.append(c)
	_update_cars(0.0)


func _process(delta: float) -> void:
	if cars.is_empty():
		return
	delta = minf(delta, 0.1)
	_frame += 1
	if speed > 0.0:
		s = fposmod(s + speed * delta, route.length)
	_update_cars(delta)


func _update_cars(_delta: float) -> void:
	for i in cars.size():
		var c: TrainCar = cars[i]
		if not is_instance_valid(c):
			continue
		var si: float = fposmod(s - float(i) * SPACING, route.length)
		var p: Vector3 = route.sample(si)
		var t: Vector3 = route.tangent(si)
		var yaw: float = atan2(-t.x, -t.z)
		var y0: float = GroundKit.ground_y(p.x, p.z)
		var p2: Vector3 = p + t * 4.0
		var y1: float = GroundKit.ground_y(p2.x, p2.z)
		c.global_position = Vector3(p.x, y0 + 0.4, p.z)
		c.rotation = Vector3(-atan2(y1 - y0, 4.0), yaw, 0.0)


func _on_car_destroyed(unit: Node, killer: Node) -> void:
	dead_count += 1
	unit_destroyed.emit(unit, killer)
	if unit is TrainCar and (unit as TrainCar).ctype == "loco":
		speed = 0.0
	if not is_dead and float(dead_count) >= ceilf(float(cars.size()) * kill_fraction):
		is_dead = true
		remove_from_group("mission_target")
		add_to_group("destroyed_target")
		destroyed.emit(self, killer)


func is_destroyed() -> bool:
	return is_dead


func alive_count() -> int:
	return cars.size() - dead_count


func get_center() -> Vector3:
	if cars.is_empty():
		return global_position
	var c: TrainCar = cars[0]
	return c.global_position if is_instance_valid(c) else global_position
