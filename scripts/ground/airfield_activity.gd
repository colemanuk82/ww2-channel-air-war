class_name AirfieldActivity
extends RefCounted
## A living airfield: ground crews working round the parked aircraft, fuel bowsers shuttling between the fuel
## depot and the dispersals, tugs towing, a bomb cart from the dump, a fire tender by the tower. All are
## ordinary destructible GroundVehicles of the airfield's own team (bowsers burn well when strafed).
## Called from WorldPopulator._build_airfield once the static dressing is in.
##
## Service vehicles never drive across a runway: every leg of their loop is planned in the field's local frame
## round the runways' ends (route_around_runways), and a stop that cannot be reached that way is dropped.

## Clearance kept from a runway edge by vehicles (m), and the extra step out to the corner waypoints.
const RUNWAY_MARGIN: float = 14.0
const CORNER_STEP: float = 18.0


static func _crew(container: Node3D, team: String, p: Vector3, yaw: float) -> void:
	return     # ground-crew figures removed (v7.27)
	var v: GroundVehicle = GroundVehicle.create("crew", team, null, 0.0, 0.0, "idle")
	v.position = p
	v.rotation.y = yaw
	container.add_child(v)


## A looping vehicle over world-space stops; each leg (the closing one too) is routed round the runways.
static func _mover(container: Node3D, af: Airfield, axf: Transform3D, vt: String, team: String, pts: Array, start_s: float, spd: float) -> void:
	var path: PackedVector3Array = loop_around_runways(af, axf, pts)
	if path.size() < 3:
		return
	var v: GroundVehicle = GroundVehicle.create(vt, team, RoutePath.from_points(path), start_s, spd, "move")
	v.wrap = true
	container.add_child(v)


static func populate(container: Node3D, af: Airfield, axf: Transform3D, y: float, team: String, rng: RandomNumberGenerator) -> void:
	var pads: Array = af.dispersal_world_points()
	if pads.size() < 4:
		pads = []
		for i in 8:
			pads.append(axf * Vector3(-190.0, 0.0, -230.0 + float(i) * 62.0))
	var rws: Array = runways(af)
	var depot: Vector3 = axf * off_runway(rws, Vector3(-330.0, 0.0, -540.0))
	var dump: Vector3 = axf * off_runway(rws, Vector3(-520.0, 0.0, 380.0))
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
	# the men: walking between the pads, depot, dump and tower, working at the aircraft, standing talking, lining the
	# take-off run. Placed at the end of the airfield build (WorldPopulator._build_airfield), once every hangar, hut,
	# pen and parked aircraft is in, so none of them stands inside one.
	container.set_meta("people_args", [af, axf, y, team, rws, pads, depot, dump, tower])
	# fuel bowsers: depot -> dispersals -> depot
	for b in 2:
		var stops: Array = [depot]
		for j in 3:
			var q: Vector3 = pads[(b * 3 + j * 2 + 1) % pads.size()]
			stops.append(q + Vector3(6.0, 0.0, 6.0))
		_mover(container, af, axf, "bowser", team, stops, float(b) * 260.0, 3.8)
	# tugs shuffling aircraft between pads
	if pads.size() >= 4:
		_mover(container, af, axf, "tug", team, [pads[0] + Vector3(5, 0, 0), pads[2] + Vector3(5, 0, 0), pads[3] + Vector3(5, 0, 0)], 40.0, 2.4)
	# bomb cart from the dump to the line
	_mover(container, af, axf, "bombcart", team, [dump, pads[pads.size() / 2] + Vector3(7, 0, 0), pads[0] + Vector3(7, 0, 0)], 0.0, 2.6)
	# fire tender parked by the tower, ready (never left standing on a runway)
	var ft: GroundVehicle = GroundVehicle.create("firetender", team, null, 0.0, 0.0, "idle")
	var inv: Transform3D = axf.affine_inverse()
	var ftp: Vector3 = axf * off_runway(rws, inv * (tower + Vector3(-18, 0, -4)))
	ft.position = Vector3(ftp.x, tower.y, ftp.z)
	ft.rotation.y = af.rotation.y
	container.add_child(ft)
	# ammunition crate and fuel-drum stacks by the dispersals, the dumps and the hangars (placed once the rest of
	# the dressing is in, so they keep clear of it)
	AirfieldStores.attach(container, af, axf, y, team, depot, dump, rng.randi())


# --- runway avoidance (all in the airfield's LOCAL frame: x across, z along the main runway) ----------------

## The field's runways as [from, to, half_width] local segments: the main runway always, plus every paved strip
## wide and long enough to be one (the triangle / cross / parallel layouts' other runways).
static func runways(af: Airfield) -> Array:
	var hw: float = af.runway_width * 0.5
	var out: Array = [[Vector3(0.0, 0.0, -af.runway_length * 0.5), Vector3(0.0, 0.0, af.runway_length * 0.5), hw]]
	for seg in af._paved:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var w: float = float(seg[2])
		if w >= maxf(hw * 0.6, 14.0) and Vector2(b.x - a.x, b.z - a.z).length() > 300.0:
			out.append([Vector3(a.x, 0.0, a.z), Vector3(b.x, 0.0, b.z), w])
	return out


static func _seg_dist(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(p1, p2, q1, q2) != null:
		return 0.0
	return minf(minf(Geometry2D.get_closest_point_to_segment(p1, q1, q2).distance_to(p1),
			Geometry2D.get_closest_point_to_segment(p2, q1, q2).distance_to(p2)),
			minf(Geometry2D.get_closest_point_to_segment(q1, p1, p2).distance_to(q1),
			Geometry2D.get_closest_point_to_segment(q2, p1, p2).distance_to(q2)))


## True when the local leg a-b keeps `margin` m clear of every runway.
static func leg_clear(rws: Array, a: Vector3, b: Vector3, margin: float = RUNWAY_MARGIN) -> bool:
	var p1 := Vector2(a.x, a.z)
	var p2 := Vector2(b.x, b.z)
	for r in rws:
		var q1 := Vector2((r[0] as Vector3).x, (r[0] as Vector3).z)
		var q2 := Vector2((r[1] as Vector3).x, (r[1] as Vector3).z)
		if _seg_dist(p1, p2, q1, q2) < float(r[2]) + margin:
			return false
	return true


## A local point pushed straight out from any runway it stands on (or within `margin` of), to just beyond it.
static func off_runway(rws: Array, p: Vector3, margin: float = RUNWAY_MARGIN) -> Vector3:
	var q: Vector3 = p
	for _pass in 3:
		var moved: bool = false
		for r in rws:
			var a := Vector2((r[0] as Vector3).x, (r[0] as Vector3).z)
			var b := Vector2((r[1] as Vector3).x, (r[1] as Vector3).z)
			var v := Vector2(q.x, q.z)
			var c: Vector2 = Geometry2D.get_closest_point_to_segment(v, a, b)
			var lim: float = float(r[2]) + margin
			if c.distance_to(v) < lim:
				var d: Vector2 = v - c
				if d.length() < 0.5:
					d = (b - a).orthogonal()
				var np: Vector2 = c + d.normalized() * (lim + 6.0)
				q = Vector3(np.x, q.y, np.y)
				moved = true
		if not moved:
			break
	return q


## Detour waypoints: just beyond each corner of every runway, dropped where they fall on another runway.
static func _corners(rws: Array) -> Array:
	var out: Array = []
	for r in rws:
		var a: Vector3 = r[0]
		var b: Vector3 = r[1]
		var ax: Vector3 = b - a
		ax.y = 0.0
		if ax.length() < 1.0:
			continue
		var u: Vector3 = ax.normalized()
		var side := Vector3(-u.z, 0.0, u.x)
		var off: float = float(r[2]) + RUNWAY_MARGIN + CORNER_STEP
		for e in [[a, -1.0], [b, 1.0]]:
			for sd in [-1.0, 1.0]:
				var c: Vector3 = (e[0] as Vector3) + u * float(e[1]) * off + side * sd * off
				if leg_clear(rws, c, c, RUNWAY_MARGIN + 2.0):
					out.append(c)
	return out


## Shortest runway-free path (local points, a first, b last) via the runway-corner waypoints; empty if none.
static func route_around_runways(rws: Array, a: Vector3, b: Vector3) -> PackedVector3Array:
	if leg_clear(rws, a, b):
		return PackedVector3Array([a, b])
	var pts: Array = [a, b]
	pts.append_array(_corners(rws))
	var n: int = pts.size()
	var dist: PackedFloat32Array = PackedFloat32Array()
	dist.resize(n)
	dist.fill(1.0e30)
	var prev: PackedInt32Array = PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var done: PackedByteArray = PackedByteArray()
	done.resize(n)
	done.fill(0)
	dist[0] = 0.0
	for _i in n:
		var u: int = -1
		var ud: float = 1.0e30
		for j in n:
			if done[j] == 0 and dist[j] < ud:
				ud = dist[j]
				u = j
		if u < 0 or u == 1:
			break
		done[u] = 1
		for v in n:
			if done[v] != 0 or v == u:
				continue
			var w: float = (pts[u] as Vector3).distance_to(pts[v])
			if ud + w < dist[v] and leg_clear(rws, pts[u], pts[v]):
				dist[v] = ud + w
				prev[v] = u
	if prev[1] < 0:
		return PackedVector3Array()
	var out := PackedVector3Array()
	var cur: int = 1
	while cur >= 0:
		out.insert(0, pts[cur])
		cur = prev[cur]
	return out


## World-space closed loop through the stops (back to the first), every leg routed round the runways. Stops that
## stand on a runway are pushed off it first; a stop the planner cannot reach from the loop so far is left out.
static func loop_around_runways(af: Airfield, axf: Transform3D, stops: Array) -> PackedVector3Array:
	var rws: Array = runways(af)
	var inv: Transform3D = axf.affine_inverse()
	var local: Array = []
	for s in stops:
		var lp: Vector3 = inv * (s as Vector3)
		local.append(off_runway(rws, Vector3(lp.x, 0.0, lp.z)))
	var kept: Array = [local[0]]
	for i in range(1, local.size()):
		if not route_around_runways(rws, kept[kept.size() - 1], local[i]).is_empty():
			kept.append(local[i])
	if kept.size() < 2:
		return PackedVector3Array()
	var lpath := PackedVector3Array()
	for i in kept.size():
		var leg: PackedVector3Array = route_around_runways(rws, kept[i], kept[(i + 1) % kept.size()])
		if leg.is_empty():
			return PackedVector3Array()     # the way back is cut: no loop at all rather than one across a runway
		for j in leg.size():
			if j == 0 and not lpath.is_empty():
				continue
			lpath.append(leg[j])
	var y0: float = (stops[0] as Vector3).y
	var out := PackedVector3Array()
	for p in lpath:
		var w: Vector3 = axf * p
		out.append(Vector3(w.x, y0, w.z))
	return out
