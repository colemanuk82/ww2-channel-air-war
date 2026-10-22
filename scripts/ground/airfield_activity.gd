class_name AirfieldActivity
extends RefCounted
## A living airfield: ground crews working round the parked aircraft, fuel bowsers shuttling between the fuel
## depot and the dispersals, tugs towing, a bomb cart from the dump, a fire tender by the tower. All are
## ordinary destructible GroundVehicles of the airfield's own team (bowsers burn well when strafed).
## Called from WorldPopulator._build_airfield once the static dressing is in.


static func _loop(pts: Array) -> RoutePath:
	var pv := PackedVector3Array()
	for p in pts:
		pv.append(p)
	pv.append(pts[0])
	return RoutePath.from_points(pv)


static func _crew(container: Node3D, team: String, p: Vector3, yaw: float) -> void:
	return     # ground-crew figures removed (v7.27)
	var v: GroundVehicle = GroundVehicle.create("crew", team, null, 0.0, 0.0, "idle")
	v.position = p
	v.rotation.y = yaw
	container.add_child(v)


static func _mover(container: Node3D, vt: String, team: String, pts: Array, start_s: float, spd: float) -> void:
	var r: RoutePath = _loop(pts)
	var v: GroundVehicle = GroundVehicle.create(vt, team, r, start_s, spd, "move")
	v.wrap = true
	container.add_child(v)


static func populate(container: Node3D, af: Airfield, axf: Transform3D, y: float, team: String, rng: RandomNumberGenerator) -> void:
	var pads: Array = af.dispersal_world_points()
	if pads.size() < 4:
		pads = []
		for i in 8:
			pads.append(axf * Vector3(-190.0, 0.0, -230.0 + float(i) * 62.0))
	var depot: Vector3 = axf * Vector3(-330.0, 0.0, -540.0)
	var dump: Vector3 = axf * Vector3(-520.0, 0.0, 380.0)
	var tower: Vector3 = axf * Vector3(-70.0, 0.0, 150.0)
	# crews at the aircraft
	var n: int = mini(pads.size(), 9)
	for i in n:
		var p: Vector3 = pads[(i * 2 + rng.randi() % 2) % pads.size()]
		var off := Vector3(rng.randf_range(-9.0, 9.0), 0.0, rng.randf_range(-9.0, 9.0))
		_crew(container, team, p + off, rng.randf() * TAU)
	_crew(container, team, depot + Vector3(18, 0, 10), 0.3)
	_crew(container, team, tower + Vector3(12, 0, 6), 1.2)
	_crew(container, team, dump + Vector3(-14, 0, 0), 2.0)
	# fuel bowsers: depot -> dispersals -> depot
	for b in 2:
		var stops: Array = [depot]
		for j in 3:
			var q: Vector3 = pads[(b * 3 + j * 2 + 1) % pads.size()]
			stops.append(q + Vector3(6.0, 0.0, 6.0))
		_mover(container, "bowser", team, stops, float(b) * 260.0, 3.8)
	# tugs shuffling aircraft between pads
	if pads.size() >= 4:
		_mover(container, "tug", team, [pads[0] + Vector3(5, 0, 0), pads[2] + Vector3(5, 0, 0), pads[3] + Vector3(5, 0, 0)], 40.0, 2.4)
	# bomb cart from the dump to the line
	_mover(container, "bombcart", team, [dump, pads[pads.size() / 2] + Vector3(7, 0, 0), pads[0] + Vector3(7, 0, 0)], 0.0, 2.6)
	# fire tender parked by the tower, ready
	var ft: GroundVehicle = GroundVehicle.create("firetender", team, null, 0.0, 0.0, "idle")
	ft.position = tower + Vector3(-18, 0, -4)
	ft.rotation.y = af.rotation.y
	container.add_child(ft)
