class_name ArmyCamp
extends Node3D
## Desert army camp: a cluster of tents, lorries, armour and stores, destructible as one mission target.
## The camp itself is a cheap container (like Convoy): the child props are the damageable objects and the
## camp reports is_destroyed() once enough of them are wrecked, so OpsRoom's "destroy" goal works on it.

signal destroyed(node: Node, killer: Node)

const DesertKit = preload("res://scripts/ground/desert_airfield_kit.gd")

var team: String = "Axis"
var target_id: String = ""
var display_name: String = "Army camp"
var is_mission_target: bool = true
var radius_m: float = 220.0
var kill_fraction: float = 0.55
var start_wrecked: bool = false
var units: Array = []
var dead_count: int = 0
var is_dead: bool = false


static func create(p_team: String, p_id: String, p_name: String, pos: Vector3, p_radius: float) -> ArmyCamp:
	var c := ArmyCamp.new()
	c.team = p_team
	c.target_id = p_id
	c.display_name = p_name
	c.radius_m = p_radius
	c.position = pos
	return c


func _ready() -> void:
	add_to_group("army_camp")
	if is_mission_target:
		add_to_group("mission_target")
	_build()
	if start_wrecked:
		for u in units:
			if u != null and is_instance_valid(u) and u.has_method("set_wrecked_silently"):
				u.call("set_wrecked_silently")
		dead_count = units.size()
		is_dead = true
		remove_from_group("mission_target")
		add_to_group("destroyed_target")


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(target_id)
	var tent_mesh: Mesh = DesertKit.bell_tent()
	var marquee_mesh: Mesh = DesertKit.marquee()
	# tents and a marquee in a loose ring, off the centre so the vehicles have room
	var n_tents: int = rng.randi_range(3, 6)
	for i in n_tents:
		var a: float = TAU * float(i) / float(n_tents) + rng.randf_range(-0.22, 0.22)
		var r: float = rng.randf_range(radius_m * 0.30, radius_m * 0.62)
		var lx: float = cos(a) * r
		var lz: float = sin(a) * r
		var gy: float = GroundKit.ground_y(position.x + lx, position.z + lz) - position.y
		var mesh: Mesh = marquee_mesh if i == 0 else tent_mesh
		var pr: AirfieldProp = AirfieldProp.create("tent", team, mesh,
			[Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(lx, gy, lz))])
		pr.display_name = display_name + " tent"
		add_child(pr)
		_link(pr)
	# vehicles: mostly soft-skinned, a couple of tanks / guns
	var kinds: Array = ["truck", "truck", "truck", "kubel", "halftrack", "tank", "tank", "artillery", "bowser"]
	var n_v: int = rng.randi_range(6, 10)
	for i in n_v:
		var kind: String = str(kinds[rng.randi() % kinds.size()])
		var a2: float = rng.randf() * TAU
		var r2: float = rng.randf_range(radius_m * 0.18, radius_m * 0.72)
		var v: GroundVehicle = GroundVehicle.create(kind, team, null, 0.0, 0.0, "idle")
		v.position = Vector3(cos(a2) * r2, 0.0, sin(a2) * r2)
		v.rotation.y = rng.randf() * TAU
		v.display_name = display_name + " " + kind
		add_child(v)
		_link(v)
	# fuel dump / stores as one more target
	var fd := AirfieldProp.create("ammo", team, DesertKit.fuel_dump(),
		[Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(rng.randf_range(-40.0, 40.0), 0.0, rng.randf_range(-40.0, 40.0)))])
	fd.display_name = display_name + " stores"
	add_child(fd)
	_link(fd)


func _link(n: Node) -> void:
	units.append(n)
	if n.has_signal("destroyed"):
		n.destroyed.connect(_on_unit_destroyed)


func _on_unit_destroyed(_n: Node, killer: Node) -> void:
	dead_count += 1
	if not is_dead and dead_count >= int(ceil(float(units.size()) * kill_fraction)):
		_finish(killer)


func _finish(killer: Node) -> void:
	is_dead = true
	remove_from_group("mission_target")
	add_to_group("destroyed_target")
	destroyed.emit(self, killer)


func is_destroyed() -> bool:
	return is_dead


func alive_count() -> int:
	return units.size() - dead_count


func get_center() -> Vector3:
	return global_position
