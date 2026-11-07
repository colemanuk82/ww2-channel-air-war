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
var radius_m: float = 260.0
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
	var tent_mesh: Mesh = DesertKit.ridge_tent()
	var marquee_mesh: Mesh = DesertKit.marquee()
	var hut_mesh: Mesh = DesertKit.control_hut()
	var yaw: float = rng.randf() * TAU
	var c: float = cos(yaw)
	var s: float = sin(yaw)
	var local := func(lx: float, lz: float) -> Vector2:
		return Vector2(lx * c - lz * s, lx * s + lz * c)
	# packed-earth parade square at the centre
	var ring := MeshInstance3D.new()
	ring.mesh = DesertKit.parade_ring()
	ring.position = Vector3(0, 0.02, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	# rows of large white ridge tents, in neat lines with lanes between them (the reference layout)
	var rows: int = 4
	var cols: int = 7
	for r in rows:
		for i in cols:
			var off: Vector2 = local.call((float(i) - 3.0) * 9.5, (float(r) - 1.5) * 12.5 + 8.0)
			var gy: float = GroundKit.ground_y(position.x + off.x, position.z + off.y) - position.y
			var pr: AirfieldProp = AirfieldProp.create("tent", team, tent_mesh,
				[Transform3D(Basis(Vector3.UP, yaw), Vector3(off.x, gy, off.y))])
			pr.display_name = display_name + " tent"
			add_child(pr)
			_link(pr)
	# two big marquees and a couple of timber huts on the far side
	for i in 2:
		var offm: Vector2 = local.call((float(i) - 0.5) * 20.0, -22.0)
		var gym: float = GroundKit.ground_y(position.x + offm.x, position.z + offm.y) - position.y
		var pm: AirfieldProp = AirfieldProp.create("tent", team, marquee_mesh,
			[Transform3D(Basis(Vector3.UP, yaw), Vector3(offm.x, gym, offm.y))])
		pm.display_name = display_name + " marquee"
		add_child(pm)
		_link(pm)
	for i in 2:
		var offh: Vector2 = local.call(-52.0 + float(i) * 14.0, 6.0)
		var gyh: float = GroundKit.ground_y(position.x + offh.x, position.z + offh.y) - position.y
		var ph: AirfieldProp = AirfieldProp.create("hut", team, hut_mesh,
			[Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), Vector3(offh.x, gyh, offh.y))])
		ph.display_name = display_name + " hut"
		add_child(ph)
		_link(ph)
	# radio mast at the edge of the camp
	var offmast: Vector2 = local.call(62.0, 34.0)
	var gym2: float = GroundKit.ground_y(position.x + offmast.x, position.z + offmast.y) - position.y
	var mast: AirfieldProp = AirfieldProp.create("hut", team, DesertKit.radio_mast(),
		[Transform3D(Basis(Vector3.UP, yaw), Vector3(offmast.x, gym2, offmast.y))])
	mast.display_name = display_name + " radio mast"
	add_child(mast)
	_link(mast)
	# vehicles parked in lines at the back of the camp, plus a few armour pieces
	var kinds: Array = ["truck", "truck", "truck", "kubel", "kubel", "halftrack", "bowser", "artillery", "tank"]
	for r in 2:
		for i in 6:
			var offv: Vector2 = local.call((float(i) - 2.5) * 8.5, (float(r) - 0.5) * 9.0 - 40.0)
			var v: GroundVehicle = GroundVehicle.create(str(kinds[(r * 6 + i) % kinds.size()]), team, null, 0.0, 0.0, "idle")
			v.position = Vector3(offv.x, 0.0, offv.y)
			v.rotation.y = yaw + rng.randf_range(-0.08, 0.08)
			v.display_name = display_name + " vehicle"
			add_child(v)
			_link(v)
	for i in 3:
		var offt: Vector2 = local.call((float(i) - 1.0) * 12.0, -50.0)
		var tank: GroundVehicle = GroundVehicle.create("tank", team, null, 0.0, 0.0, "idle")
		tank.position = Vector3(offt.x, 0.0, offt.y)
		tank.rotation.y = yaw
		tank.display_name = display_name + " tank"
		add_child(tank)
		_link(tank)
	# stores: fuel dumps and ammunition stacks
	for i in 3:
		var offs: Vector2 = local.call(48.0 + float(i) * 6.0, -34.0 + float(i) * 12.0)
		var fd := AirfieldProp.create("ammo", team, DesertKit.fuel_dump(),
			[Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.2, 0.2)), Vector3(offs.x, 0.0, offs.y))])
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
