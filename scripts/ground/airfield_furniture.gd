class_name AirfieldFurniture
extends RefCounted
## P8 airfield furniture on the real 85 airfields: dispersal and blast pens with earth revetments, Nissen-hut
## camps, T2 and T1 hangars, a watch office (control tower), fuel and bomb dumps, a flare path with Chance
## lights, and a few dummy aircraft. Everything is placed inside the airfield footprint and clear of the runway
## (the runway runs along the airfield's local Z at x = 0, so all furniture sits at |x| well outside the paved
## width). Deterministic from the airfield's own rng (seeded from hash(id) in WorldPopulator._build_airfield).
##
##   AirfieldFurniture.dress(container, af, axf, y, team, rng)   # called once per airfield
##
## All procedural low-poly toon: meshes from AirfieldAssets, props clustered into destructible AirfieldProp
## nodes, revetments and the flare path as MultiMeshes. No photo textures.

const COL_EARTH := Color(0.34, 0.29, 0.2)
const COL_TRACK := Color(0.36, 0.32, 0.26)
const COL_DARK := Color(0.1, 0.1, 0.1)


## Place the whole furniture set for one airfield. `axf` is the airfield frame (Basis = af.rotation, origin =
## af.position); y is the flat surface height; rng is the airfield's own generator.
static func dress(container: Node3D, af: Airfield, axf: Transform3D, y: float, team: String, rng: RandomNumberGenerator) -> void:
	var L: float = af.runway_length
	_pens(container, af, y, team, rng)
	_revetments(container, af, axf, y, team, rng, L)
	_nissen_camp(container, axf, y, team, rng)
	_hangars(container, axf, y, team, rng, L)
	_dumps(container, axf, y, team, rng, L)
	_watch_office(container, axf, y, L)
	_flare_path(container, axf, y, L)
	_dummies(container, axf, y, team, rng, L)


static func _world(axf: Transform3D, local: Vector3, yaw: float) -> Transform3D:
	return axf * Transform3D(Basis(Vector3.UP, yaw), local)


## Dispersal / blast pens: an earth revetment arc round each dispersal pad (a MultiMesh of bank segments).
static func _pens(container: Node3D, af: Airfield, y: float, team: String, rng: RandomNumberGenerator) -> void:
	var banks: Array = []
	for p in af.dispersal_world_points():
		if rng.randf() < 0.35:
			continue
		var pad: Vector3 = p
		for j in 3:
			var a: float = TAU * float(j) / 3.0 + 0.7
			var bp := Vector3(pad.x + cos(a) * 25.0, y, pad.z + sin(a) * 25.0)
			var tang := Vector3(-sin(a), 0.0, cos(a)) * 11.0
			if af.near_paved(bp, 4.0) or af.near_paved(bp + tang, 4.0) or af.near_paved(bp - tang, 4.0):
				continue      # never across a taxiway stem or a neighbouring pad
			banks.append(Transform3D(Basis(Vector3.UP, -a), bp))
	if not banks.is_empty():
		container.add_child(Scatter.multi(AirfieldAssets.revetment(team), banks, 5000.0))


## A low revetment line screening the paved area from the grass, on the east flank.
static func _revetments(container: Node3D, af: Airfield, axf: Transform3D, y: float, team: String, rng: RandomNumberGenerator, L: float) -> void:
	var banks: Array = []
	var n: int = int(L / 60.0)
	for i in n:
		var z: float = -L * 0.5 + 40.0 + float(i) * 60.0
		if rng.randf() < 0.4:
			continue
		var bt: Transform3D = _world(axf, Vector3(150.0 + rng.randf_range(-8.0, 8.0), 0.0, z), 0.0)
		var ax: Vector3 = axf.basis * Vector3(0, 0, 11.0)
		if af.near_paved(bt.origin, 4.0) or af.near_paved(bt.origin + ax, 4.0) or af.near_paved(bt.origin - ax, 4.0):
			continue
		banks.append(bt)
	if not banks.is_empty():
		container.add_child(Scatter.multi(AirfieldAssets.revetment(team), banks, 5000.0))


## A Nissen-hut camp (communal site) in the grass east of the track: rows of huts plus a water tower.
static func _nissen_camp(container: Node3D, axf: Transform3D, y: float, team: String, rng: RandomNumberGenerator) -> void:
	var huts: Array = []
	for row in 5:
		for i in 9:
			huts.append(_world(axf, Vector3(280.0 + float(row) * 30.0, 0.0, -150.0 + float(i) * 34.0 + float(row) * 6.0), PI * 0.5 + rng.randf_range(-0.05, 0.05)))
	_prop_cluster(container, "hut", AirfieldAssets.nissen(team), huts, team, 4)
	var wt: Vector3 = axf * Vector3(470.0, 0.0, -40.0)
	GroundKit.cyl(container, 3.4, 3.4, 6.0, Vector3(wt.x, y + 6.0, wt.z), GroundKit.COL_BRICK.lightened(0.05), Vector3.ZERO, 12)
	for i in 4:
		GroundKit.cyl(container, 0.3, 0.3, 4.0, Vector3(wt.x - 2.0 + float(i) * 1.4, y + 2.0, wt.z + 2.0), GroundKit.COL_STEEL, Vector3.ZERO, 4, false)


## A row of T2 (large) and T1 (smaller) hangars out on the far west of the technical site.
static func _hangars(container: Node3D, axf: Transform3D, y: float, team: String, rng: RandomNumberGenerator, L: float) -> void:
	var t2: Array = []
	for i in 2:
		t2.append(_world(axf, Vector3(-620.0, 0.0, -260.0 + float(i) * 130.0), PI * 0.5))
	_prop_cluster(container, "blister", AirfieldAssets.t2_hangar(team), t2, team, 2)
	var t1: Array = []
	for i in 3:
		t1.append(_world(axf, Vector3(-740.0, 0.0, -150.0 + float(i) * 110.0), PI * 0.5))
	_prop_cluster(container, "blister", AirfieldAssets.t1_hangar(team), t1, team, 2)


## Fuel dump (tanks) and bomb dump (earth-banked bomb stacks), well clear of the buildings.
static func _dumps(container: Node3D, axf: Transform3D, y: float, team: String, rng: RandomNumberGenerator, L: float) -> void:
	var fuel: Array = []
	for i in 4:
		for r in 2:
			fuel.append(_world(axf, Vector3(-820.0 - float(r) * 30.0, 0.0, -200.0 + float(i) * 34.0), 0.0))
	_prop_cluster(container, "ammo", AirfieldAssets.fuel_tank(), fuel, team, 4)
	var bombs: Array = []
	for i in 3:
		for r in 2:
			bombs.append(_world(axf, Vector3(480.0 + float(r) * 34.0, 0.0, 240.0 + float(i) * 40.0), PI * 0.5))
	_prop_cluster(container, "ammo", AirfieldAssets.bomb_bank(), bombs, team, 3)


## The watch office / control tower: a two-storey operations block with a glazed control room and balcony.
static func _watch_office(container: Node3D, axf: Transform3D, y: float, L: float) -> void:
	var p: Vector3 = axf * Vector3(-200.0, 0.0, -L * 0.18)
	var yaw: float = axf.basis.get_euler().y
	var h := Node3D.new()
	h.position = Vector3(p.x, y, p.z)
	h.rotation.y = yaw
	container.add_child(h)
	GroundKit.box(h, Vector3(15.0, 3.6, 11.0), Vector3(0.0, 1.8, 0.0), GroundKit.COL_BRICK.darkened(0.06))
	GroundKit.box(h, Vector3(11.0, 3.0, 8.0), Vector3(0.0, 5.1, 0.0), GroundKit.COL_BRICK)
	GroundKit.box(h, Vector3(12.2, 0.5, 9.2), Vector3(0.0, 3.75, 0.0), Color(0.5, 0.48, 0.44))                     # balcony slab
	GroundKit.box(h, Vector3(10.6, 1.5, 7.6), Vector3(0.0, 5.4, 0.0), Color(0.16, 0.2, 0.22), Vector3.ZERO, false)  # glazed gallery
	var roof := MeshInstance3D.new()
	roof.mesh = GroundKit.prism_mesh(8.4, 11.4, 1.8)
	roof.material_override = GroundKit.mat(Color(0.3, 0.3, 0.32), true)
	roof.position = Vector3(0.0, 6.6, 0.0)
	h.add_child(roof)
	GroundKit.cyl(h, 0.1, 0.12, 7.0, Vector3(6.6, 10.0, 0.0), GroundKit.COL_STEEL, Vector3.ZERO, 4, false)          # signal mast


## The flare path: a row of Chance lights parallel to (and clear of) the runway, with a dark lamp-light strip.
static func _flare_path(container: Node3D, axf: Transform3D, y: float, L: float) -> void:
	var yaw_deg: float = rad_to_deg(axf.basis.get_euler().y)
	GroundKit.box(container, Vector3(2.4, 0.2, L * 0.9), axf * Vector3(112.0, 0.12, 0.0), COL_TRACK, Vector3(0.0, yaw_deg, 0.0), false)
	var n: int = int(L / 75.0)
	var lights: Array = []
	for i in n + 1:
		var z: float = -L * 0.45 + float(i) * (L * 0.9 / float(maxi(n, 1)))
		lights.append(_world(axf, Vector3(112.0, 0.0, z), 0.0))
	if not lights.is_empty():
		container.add_child(Scatter.multi(AirfieldAssets.chance_light(), lights, 2500.0))


## A few dummy aircraft on the far grass (the plywood silhouettes that drew strafing runs).
static func _dummies(container: Node3D, axf: Transform3D, y: float, team: String, rng: RandomNumberGenerator, L: float) -> void:
	var xf: Array = []
	for i in 4:
		var z: float = -60.0 + float(i) * 40.0 + rng.randf_range(-6.0, 6.0)
		xf.append(_world(axf, Vector3(210.0 + rng.randf_range(-10.0, 10.0), 0.0, z), rng.randf_range(-0.4, 0.4)))
	if not xf.is_empty():
		container.add_child(Scatter.multi(AirfieldAssets.dummy_aircraft(team), xf, 4200.0))


## Greedy clusters of up to `per` props within 30 m of the cluster's first one into one destructible AirfieldProp.
static func _prop_cluster(parent: Node3D, kind: String, mesh: Mesh, xforms: Array, team: String, per: int) -> void:
	var left: Array = xforms.duplicate()
	while not left.is_empty():
		var first: Transform3D = left.pop_front()
		var chunk: Array = [first]
		var rest: Array = []
		for t in left:
			if chunk.size() < per and (t as Transform3D).origin.distance_to(first.origin) < 30.0:
				chunk.append(t)
			else:
				rest.append(t)
		left = rest
		parent.add_child(AirfieldProp.create(kind, team, mesh, chunk))
