class_name RoutePath
extends RefCounted
## Polyline in the XZ plane with arc-length sampling. Used by vehicles, trains and ships.

var points: PackedVector3Array = PackedVector3Array()
var cum: PackedFloat32Array = PackedFloat32Array()
var length: float = 0.0


static func from_points(pts: PackedVector3Array) -> RoutePath:
	var r := RoutePath.new()
	r.points = pts
	r.cum.resize(pts.size())
	var acc: float = 0.0
	for i in pts.size():
		if i > 0:
			acc += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		r.cum[i] = acc
	r.length = acc
	return r


## Rounds the corners of a polyline: each bend becomes a circular arc of `radius` (smaller where the legs are too
## short for it: an arc never uses more than 48% of either leg, so neighbouring arcs never overlap), sampled every
## `step_deg` degrees of turn. Straight stretches are untouched. Hairpins (over 150 degrees) are left alone.
## Deterministic, so every loader that rounds the same line gets the same curve (rails: TransportNetwork, RailKit).
static func fillet_2d(pts: PackedVector2Array, radius: float, step_deg: float = 5.0) -> PackedVector2Array:
	var n: int = pts.size()
	if n < 3 or radius <= 0.0:
		return pts
	var out := PackedVector2Array()
	out.append(pts[0])
	var min_turn: float = deg_to_rad(3.0)
	var max_turn: float = deg_to_rad(150.0)
	for i in range(1, n - 1):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var c: Vector2 = pts[i + 1]
		var d1: Vector2 = b - a
		var d2: Vector2 = c - b
		var l1: float = d1.length()
		var l2: float = d2.length()
		if l1 < 0.5 or l2 < 0.5:
			out.append(b)
			continue
		var u1: Vector2 = d1 / l1
		var u2: Vector2 = d2 / l2
		var turn: float = acos(clampf(u1.dot(u2), -1.0, 1.0))
		if turn < min_turn or turn > max_turn:
			out.append(b)
			continue
		var th: float = tan(turn * 0.5)
		var t: float = minf(radius * th, 0.48 * minf(l1, l2))
		var r: float = t / th
		var p1: Vector2 = b - u1 * t
		var p2: Vector2 = b + u2 * t
		var side: float = 1.0 if u1.cross(u2) > 0.0 else -1.0
		var ctr: Vector2 = p1 + Vector2(-u1.y, u1.x) * side * r
		var a0: float = (p1 - ctr).angle()
		var da: float = wrapf((p2 - ctr).angle() - a0, -PI, PI)
		var steps: int = maxi(int(ceil(absf(rad_to_deg(da)) / step_deg)), 1)
		for k in steps + 1:
			var ang: float = a0 + da * float(k) / float(steps)
			out.append(ctr + Vector2(cos(ang), sin(ang)) * r)
	out.append(pts[n - 1])
	return out


## Joins line pieces into continuous polylines. The OSM exports are almost all two-point segments, so the bends sit
## where one segment meets the next: wherever exactly two pieces of the same kind share an end point (0.5 m), they
## are joined; junctions (3+ pieces) and dead ends stay as ends. Returns [[kind, PackedVector2Array], ...] in a
## deterministic order (the same input always gives the same chains).
static func chain_2d(kinds: PackedStringArray, segs: Array) -> Array:
	var n: int = segs.size()
	var nodes: Dictionary = {}      # Vector2i -> Array of (line index * 2 + end)
	for i in n:
		var pts: PackedVector2Array = segs[i]
		for e in 2:
			var p: Vector2 = pts[0] if e == 0 else pts[pts.size() - 1]
			var key := Vector2i(roundi(p.x * 2.0), roundi(p.y * 2.0))
			if not nodes.has(key):
				nodes[key] = []
			(nodes[key] as Array).append(i * 2 + e)
	var used := PackedByteArray()
	used.resize(n)
	var out: Array = []
	for i in n:
		if used[i] == 1:
			continue
		used[i] = 1
		var kind: String = kinds[i]
		var chain: PackedVector2Array = (segs[i] as PackedVector2Array).duplicate()
		# extend from the tail, then from the head
		for dir in 2:
			while true:
				var tip: Vector2 = chain[chain.size() - 1] if dir == 0 else chain[0]
				var at: Array = nodes.get(Vector2i(roundi(tip.x * 2.0), roundi(tip.y * 2.0)), [])
				if at.size() != 2:
					break
				var other: int = -1
				for code in at:
					var li: int = int(code) >> 1
					if used[li] == 0 and kinds[li] == kind:
						other = int(code)
				if other < 0:
					break
				var oi: int = other >> 1
				used[oi] = 1
				var op: PackedVector2Array = segs[oi]
				var forward: bool = (other & 1) == 0          # joined at its start: walk it start -> end
				var m: int = op.size()
				if dir == 0:
					for k in range(1, m):
						chain.append(op[k] if forward else op[m - 1 - k])
				else:
					var pre := PackedVector2Array()
					for k in range(m - 1, 0, -1):
						pre.append(op[k] if forward else op[m - 1 - k])
					pre.append_array(chain)
					chain = pre
		out.append([kind, chain])
	return out


## Arc lengths along a 2D polyline (cum[0] = 0).
static func cum_2d(pts: PackedVector2Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	var acc: float = 0.0
	for i in pts.size():
		if i > 0:
			acc += pts[i - 1].distance_to(pts[i])
		cum[i] = acc
	return cum


## Curve radius (world units, ~metres) for a road or rail class.
static func curve_radius(kind: String) -> float:
	match kind:
		"rail":
			return 900.0
		"motorway":
			return 600.0
		"trunk":
			return 450.0
		"primary":
			return 320.0
		"secondary":
			return 220.0
		"tertiary":
			return 160.0
	return 140.0


static func from_latlon(ll: Array) -> RoutePath:
	var pts := PackedVector3Array()
	for p in ll:
		pts.append(WorldCoords.latlon_to_world(float(p[0]), float(p[1])))
	return from_points(pts)


func _seg(s: float) -> int:
	var lo: int = 0
	var hi: int = points.size() - 1
	while hi - lo > 1:
		var mid: int = (lo + hi) >> 1
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	return lo


## Position (y = 0) at arc length s (clamped).
func sample(s: float) -> Vector3:
	if points.size() < 2:
		return points[0] if points.size() == 1 else Vector3.ZERO
	s = clampf(s, 0.0, length)
	var i: int = _seg(s)
	var seg_len: float = maxf(cum[i + 1] - cum[i], 0.0001)
	var f: float = (s - cum[i]) / seg_len
	var a: Vector3 = points[i]
	var b: Vector3 = points[i + 1]
	return Vector3(lerpf(a.x, b.x, f), 0.0, lerpf(a.z, b.z, f))


func tangent(s: float) -> Vector3:
	if points.size() < 2:
		return Vector3(0, 0, -1)
	s = clampf(s, 0.0, length)
	var i: int = _seg(s)
	var d: Vector3 = points[i + 1] - points[i]
	d.y = 0.0
	return d.normalized() if d.length() > 0.0001 else Vector3(0, 0, -1)


## Closest arc-length to world point p, and the distance to the polyline.
func closest(p: Vector3) -> Vector2:
	var best_d: float = INF
	var best_s: float = 0.0
	for i in range(points.size() - 1):
		var a: Vector2 = Vector2(points[i].x, points[i].z)
		var b: Vector2 = Vector2(points[i + 1].x, points[i + 1].z)
		var ab: Vector2 = b - a
		var l2: float = maxf(ab.length_squared(), 0.0001)
		var t: float = clampf((Vector2(p.x, p.z) - a).dot(ab) / l2, 0.0, 1.0)
		var q: Vector2 = a + ab * t
		var d: float = q.distance_to(Vector2(p.x, p.z))
		if d < best_d:
			best_d = d
			best_s = cum[i] + sqrt(l2) * t
	return Vector2(best_s, best_d)
