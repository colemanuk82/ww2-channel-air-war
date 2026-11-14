class_name AirfieldStores
extends Node3D
## Ammunition crate stacks and fuel / oil drum stacks round an airfield: one beside most dispersal pads (on the
## outboard side, away from the runway), a cluster at the fuel depot (drums) and at the bomb dump (crates), and a
## few against the hangars. Every stack is destructible (AirfieldProp kinds "crates" and "drums").
##
## Placement waits until the whole field is dressed (this node's _ready runs when the finished site enters the
## tree), so the stacks can keep clear of everything else: runways (plus a wide margin), taxiways and pads
## (Airfield.near_paved), the taxi-out flight's routes and its reserved dispersals (Airfield.taxi_flight /
## taxi_flight_routes), parked aircraft (Airfield.parked_spots) and every building and prop already placed.
##
##   AirfieldStores.attach(container, af, axf, y, team, depot, dump, seed)   # from AirfieldActivity.populate

const PAVED_CLEAR: float = 10.0     # m from any taxiway, pad or runway pavement
const RUNWAY_CLEAR: float = 30.0    # m from a runway edge (paved or grass strip)
const ROUTE_CLEAR: float = 18.0     # m from a taxi-out route
const FLIGHT_PAD_CLEAR: float = 40.0   # m from a reserved taxi-flight dispersal
const PARKED_CLEAR: float = 20.0    # m from a parked aircraft
const STACK_R: float = 3.0          # a stack's own radius
const PAD_RING: float = 40.0        # stacks beside a pad stand this far from its centre (pens are at ~25-29 m)

var af: Airfield
var axf: Transform3D
var y: float = 0.0
var team: String = "Allies"
var depot: Vector3
var dump: Vector3
var seed_v: int = 0

var _rws: Array = []
var _routes: Array = []
var _flight_pads: Array = []      # local Vector3
var _blockers: Array = []         # [world Vector3, radius]
var _crates: Array = []           # world Transform3D
var _drums: Array = []


static func attach(container: Node3D, p_af: Airfield, p_axf: Transform3D, p_y: float, p_team: String, p_depot: Vector3, p_dump: Vector3, p_seed: int) -> AirfieldStores:
	var s := AirfieldStores.new()
	s.name = "AirfieldStores"
	s.af = p_af
	s.axf = p_axf
	s.y = p_y
	s.team = p_team
	s.depot = p_depot
	s.dump = p_dump
	s.seed_v = p_seed
	container.add_child(s)
	return s


func _ready() -> void:
	if af == null or not is_instance_valid(af):
		return
	# the container sits at the world origin; this node must too, so its props' world transforms hold
	transform = Transform3D.IDENTITY
	plan()
	if not _crates.is_empty():
		_cluster("crates", AirfieldAssets.crate_stack(team), _crates)
	if not _drums.is_empty():
		_cluster("drums", AirfieldAssets.drum_stack(team), _drums)


## Work out every stack's transform (fills _crates and _drums). Separate from _ready so the debug check can run it.
func plan() -> void:
	_crates.clear()
	_drums.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	_rws = AirfieldActivity.runways(af)
	_routes = flight_routes(af)
	var flight: Array = flight_pads(af)
	_flight_pads.clear()
	for i in flight:
		if i >= 0 and i < af._dispersal_local.size():
			_flight_pads.append(af._dispersal_local[i])
	_collect_blockers(get_parent())
	# beside the dispersal pads, on the side away from the runway
	for i in af._dispersal_local.size():
		if i in flight or rng.randf() < 0.4:
			continue
		var lp: Vector3 = af._dispersal_local[i]
		var out_dir := Vector2(signf(lp.x) if absf(lp.x) > 1.0 else 1.0, 0.0)
		if Vector2(lp.x, lp.z).length() > 1.0:
			out_dir = (out_dir * 0.6 + Vector2(lp.x, lp.z).normalized() * 0.4).normalized()
		var base: float = out_dir.angle() + rng.randf_range(-0.5, 0.5)
		for da in [0.0, 0.55, -0.55, 1.1, -1.1, 1.65, -1.65]:
			var a: float = base + float(da)
			var cand := Vector3(lp.x + cos(a) * PAD_RING, 0.0, lp.z + sin(a) * PAD_RING)
			if _try(axf * cand, rng, rng.randf() < 0.55):
				break
	# drums at the fuel depot, crates at the bomb dump
	for c in [[depot, false, 4], [dump, true, 4]]:
		var centre: Vector3 = c[0]
		var placed: int = 0
		for k in 24:
			if placed >= int(c[2]):
				break
			var a2: float = rng.randf() * TAU
			var r2: float = rng.randf_range(22.0, 55.0)
			if _try(centre + Vector3(cos(a2) * r2, 0.0, sin(a2) * r2), rng, bool(c[1])):
				placed += 1
	# a few against the hangars (and the blister / T1 / T2 sheds)
	var sheds: Array = []
	for n in get_parent().get_children():
		if n is GroundStructure and String((n as GroundStructure).kind).find("hangar") >= 0:
			sheds.append([(n as Node3D).position, (n as GroundTarget).hit_radius])
		elif n is AirfieldProp and (n as AirfieldProp).pkind == "blister":
			sheds.append([(n as Node3D).position, (n as GroundTarget).hit_radius])
	for sh in sheds:
		if rng.randf() < 0.45:
			continue
		var hp: Vector3 = sh[0]
		var a3: float = rng.randf() * TAU
		for tr2 in 4:
			var aa: float = a3 + float(tr2) * PI * 0.5
			var rr: float = float(sh[1]) + 6.0
			if _try(Vector3(hp.x + cos(aa) * rr, 0.0, hp.z + sin(aa) * rr), rng, rng.randf() < 0.5):
				break


## The dispersal indices the taxi-out flight leaves from (Airfield.taxi_flight; on a layout without a flight plan,
## the player's kept-clear spot).
static func flight_pads(p_af: Airfield) -> Array:
	var tf: Variant = p_af.get("taxi_flight")
	if tf != null:
		return Array(tf)
	var k: int = int(p_af.get("keep_clear_i")) if p_af.get("keep_clear_i") != null else -1
	return [k] if k >= 0 else []


## The taxi-out routes (local polylines) stacks must keep off: the flight's (Airfield.taxi_flight_routes), or,
## without a flight plan, every dispersal's route to the runway.
static func flight_routes(p_af: Airfield) -> Array:
	var fr: Variant = p_af.get("taxi_flight_routes")
	if fr != null:
		return fr
	var out: Array = []
	for sp in p_af._dispersal_local:
		var rt: PackedVector3Array = p_af.taxi_route(sp)
		if rt.size() >= 3:
			out.append(rt)
	return out


## Places one stack at world point p if it is clear of everything; returns whether it went down.
func _try(p: Vector3, rng: RandomNumberGenerator, crates: bool) -> bool:
	if not is_clear(p):
		return false
	var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, y, p.z))
	(_crates if crates else _drums).append(t)
	_blockers.append([Vector3(p.x, 0.0, p.z), STACK_R + 3.0])
	return true


## True when a world point is a fair place for a stack (see the class notes for what it keeps clear of).
func is_clear(p: Vector3) -> bool:
	var inv: Transform3D = axf.affine_inverse()
	var lp: Vector3 = inv * p
	lp.y = 0.0
	if not AirfieldActivity.leg_clear(_rws, lp, lp, RUNWAY_CLEAR + STACK_R):
		return false
	if af.near_paved(p, PAVED_CLEAR + STACK_R):
		return false
	var q := Vector2(lp.x, lp.z)
	for rt in _routes:
		var pr: PackedVector3Array = rt
		for i in range(1, pr.size()):
			var c: Vector2 = Geometry2D.get_closest_point_to_segment(q, Vector2(pr[i - 1].x, pr[i - 1].z), Vector2(pr[i].x, pr[i].z))
			if c.distance_to(q) < ROUTE_CLEAR + STACK_R:
				return false
	for fp in _flight_pads:
		if Vector2((fp as Vector3).x, (fp as Vector3).z).distance_to(q) < FLIGHT_PAD_CLEAR:
			return false
	for ps in af.parked_spots:
		if Vector2((ps as Vector3).x - p.x, (ps as Vector3).z - p.z).length() < PARKED_CLEAR:
			return false
	for b in _blockers:
		var bp: Vector3 = b[0]
		if Vector2(bp.x - p.x, bp.z - p.z).length() < float(b[1]) + STACK_R:
			return false
	return true


## Buildings and props already on the field (world XZ + radius). Moving vehicles are left out.
func _collect_blockers(root: Node) -> void:
	_blockers.clear()
	if root == null:
		return
	for n in root.find_children("*", "GroundTarget", true, false):
		if n is GroundVehicle or n == self:
			continue
		var g: GroundTarget = n
		var wp: Vector3 = _world_of(g)
		_blockers.append([wp, g.hit_radius])
	for n2 in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi: MultiMeshInstance3D = n2
		if mmi.multimesh == null or mmi.multimesh.instance_count > 400:
			continue      # big scatter (grass, flare-path lamps) is not a blocker
		var mm: MultiMesh = mmi.multimesh
		var r: float = 4.0
		if mm.mesh != null:
			var ab: AABB = mm.mesh.get_aabb()
			r = maxf(ab.size.x, ab.size.z) * 0.5 + 1.0
		for i in mm.instance_count:
			var o: Vector3 = _world_of(mmi) + mm.get_instance_transform(i).origin
			_blockers.append([o, r])


## World position of a node under the (not yet in-tree) container: the sum of local positions up to it.
func _world_of(n: Node3D) -> Vector3:
	if n.is_inside_tree():
		return n.global_position
	var p: Vector3 = n.position
	var c: Node = n.get_parent()
	while c != null and c is Node3D and c != get_parent():
		p = (c as Node3D).transform * p
		c = c.get_parent()
	return p


## Destructible clusters of up to three stacks within 30 m of each other.
func _cluster(kind: String, mesh: Mesh, xforms: Array) -> void:
	var left: Array = xforms.duplicate()
	while not left.is_empty():
		var first: Transform3D = left.pop_front()
		var chunk: Array = [first]
		var rest: Array = []
		for t in left:
			if chunk.size() < 3 and (t as Transform3D).origin.distance_to(first.origin) < 30.0:
				chunk.append(t)
			else:
				rest.append(t)
		left = rest
		add_child(AirfieldProp.create(kind, team, mesh, chunk))


## The planned stacks (world transforms) for the debug check: [crates, drums].
func planned() -> Array:
	return [_crates, _drums]
