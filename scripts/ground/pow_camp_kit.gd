class_name PowCampKit
extends RefCounted
## Prisoner-of-war and labour camps at their real locations.
##
## German Stalags / Oflags / Dulag Luft (where captured Allied airmen were interrogated and held) follow the
## surviving model and plans of Stalag Luft III: a compound of long timber barrack huts in rows on beaten sandy
## ground, a cookhouse and ablution blocks, an open appel (roll-call) ground used as a sports field, a double
## 2.5 m wire fence with concertina coiled between, a warning rail inside the wire, raised "goon box" towers at the
## corners and along the fence, a gatehouse leading to the vorlager (guards' barracks, stores, water tower) and a
## cleared strip with the pine forest beyond. British camps (Kempton Park, Devizes, Hatfield Heath, Colchester,
## Island Farm) are the plainer pattern: Nissen and timber huts on grass inside a single wire fence with fewer
## towers. Organisation Todt labour camps (Alderney, and the workers' camps for the Watten and Mimoyecques bunkers)
## are rough unpainted huts behind single wire.
##
## These are not targets: they are built from static MultiMeshes with no destructible props.

## [id, name, lat, lon, team holding it, style ("stalag" / "uk" / "ot"), size 1-3]
const CAMPS := [
	# held by Germany: Allied and other prisoners
	["dulag_luft", "Dulag Luft, Oberursel", 50.2045, 8.5560, "Axis", "stalag", 1],
	["stalag_6a", "Stalag VI-A, Hemer", 51.3860, 7.7800, "Axis", "stalag", 3],   # Sauerlandpark (ex Bluecher barracks)
	["stalag_6j", "Stalag VI-J, Krefeld-Fichtenhain", 51.3080, 6.5450, "Axis", "stalag", 2],
	["stalag_6g", "Stalag VI-G, Bonn-Duisdorf", 50.7180, 7.0450, "Axis", "stalag", 2],
	["stalag_6d", "Stalag VI-D, Dortmund", 51.4960, 7.4520, "Axis", "stalag", 2],
	["stalag_326", "Stalag 326, Stukenbrock", 51.8870, 8.6500, "Axis", "stalag", 3],
	["oflag_6a", "Oflag VI-A, Soest", 51.5700, 8.1100, "Axis", "stalag", 2],
	["stalag_12a", "Stalag XII-A, Limburg", 50.3950, 8.0600, "Axis", "stalag", 3],
	["stalag_12d", "Stalag XII-D, Trier", 49.7700, 6.6600, "Axis", "stalag", 2],
	["frontstalag_194", "Frontstalag 194, Chalons-sur-Marne", 48.9600, 4.3600, "Axis", "stalag", 2],
	["frontstalag_190", "Frontstalag 190, Charleville", 49.7700, 4.7200, "Axis", "stalag", 1],
	# held by Britain: German and Italian prisoners
	["camp_7", "POW Camp 7, Kempton Park", 51.4190, -0.4030, "Allies", "uk", 2],
	["camp_23", "POW Camp 23, Le Marchant, Devizes", 51.3560, -1.9900, "Allies", "uk", 2],
	["camp_116", "POW Camp 116, Hatfield Heath", 51.8100, 0.2100, "Allies", "uk", 1],
	["camp_186", "POW Camp 186, Berechurch Hall", 51.8660, 0.9050, "Allies", "uk", 2],
	["camp_198", "POW Camp 198, Island Farm, Bridgend", 51.4950, -3.5800, "Allies", "uk", 2],
	# Organisation Todt labour camps
	["ot_norderney", "Lager Norderney, Alderney", 49.7160, -2.1850, "Axis", "ot", 1],
	["ot_helgoland", "Lager Helgoland, Alderney", 49.7120, -2.2120, "Axis", "ot", 1],
	["ot_watten", "Workers' camp, Watten bunker", 50.8180, 2.1950, "Axis", "ot", 2],
	["ot_mimoyecques", "Workers' camp, Mimoyecques", 50.8500, 1.7600, "Axis", "ot", 1],
]


static func extents(style: String, size: int) -> Vector2:
	match style:
		"stalag":
			return Vector2(110.0 + 40.0 * float(size), 85.0 + 30.0 * float(size))
		"uk":
			return Vector2(90.0 + 30.0 * float(size), 70.0 + 20.0 * float(size))
		_:
			return Vector2(60.0 + 25.0 * float(size), 45.0 + 15.0 * float(size))


## Footprint radius kept clear of scatter (includes the vorlager and the cleared strip).
static func radius(style: String, size: int) -> float:
	var e: Vector2 = extents(style, size)
	return e.length() + (110.0 if style == "stalag" else 50.0)


## The flattest spot within 300 m of the listed position (camps were built on level ground; the height data
## around some sites is coarse and hilly). Scores the height range over the footprint; the listed spot wins ties.
static func flattest(pos: Vector3, style: String, size: int) -> Vector3:
	var e: Vector2 = extents(style, size)
	var best: Vector3 = pos
	var best_s: float = INF
	for ox in range(-3, 4):
		for oz in range(-3, 4):
			var c: Vector3 = pos + Vector3(float(ox) * 100.0, 0.0, float(oz) * 100.0)
			if c.distance_to(pos) > 300.0:
				continue
			var lo: float = INF
			var hi: float = -INF
			var wet: bool = false
			for sx in [-1.0, 0.0, 1.0]:
				for sz in [-1.0, 0.0, 1.0]:
					var y: float = GroundKit.raw_y(c.x + sx * e.x, c.z + sz * e.y)
					lo = minf(lo, y)
					hi = maxf(hi, y)
					wet = wet or y < 1.5
			if wet:
				continue
			var score: float = (hi - lo) + c.distance_to(pos) * 0.01
			if score < best_s:
				best_s = score
				best = c
	return best


static func heading_for(id: String) -> float:
	return float(absi(hash(id + "powh")) % 90)


## Terrain zone: stalag / labour camps get the bare sandy compound (kind 3); British camps worn grass (kind 2).
static func zone_for(id: String, pos: Vector3, style: String, size: int) -> Dictionary:
	var e: Vector2 = extents(style, size)
	var kind: int = 2 if style == "uk" else 3
	var extra: float = 50.0 if style == "stalag" else 15.0
	return {"pos": pos, "heading": heading_for(id), "half": Vector2(e.y + extra, e.x + 15.0), "feather": 70.0, "kind": kind}


static func build(pos: Vector3, id: String, style: String, size: int, team: String) -> Node3D:
	var container := Node3D.new()
	container.name = "PowCamp_" + id
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var yaw: float = -deg_to_rad(heading_for(id))
	var axf := Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, 0.0, pos.z))
	var e: Vector2 = extents(style, size)
	var hx: float = e.x
	var hz: float = e.y
	var stalag: bool = style == "stalag"
	var hut_style: String = "ot" if style == "ot" else "stalag"
	var earth := Color(0.47, 0.41, 0.30)

	# --- wire
	container.add_child(Scatter.multi(CampAssets.fence_bay(stalag or style == "ot"), CampAssets.fence_ring(axf, yaw, hx, hz, 6.0), 3000.0))
	if stalag:
		# the second fence 2.5 m outside, concertina coiled between, the warning rail 9 m inside
		container.add_child(Scatter.multi(CampAssets.fence_bay(true), CampAssets.fence_ring(axf, yaw, hx + 2.6, hz + 2.6, 6.0), 3000.0))
		var coil: Array = CampAssets.fence_ring(axf, yaw, hx + 1.3, hz + 1.3, 6.0)
		container.add_child(Scatter.multi(CampAssets.concertina(), coil, 2200.0))
		var rail: Array = CampAssets.fence_ring(axf, yaw, hx - 9.0, hz - 9.0, 6.0)
		container.add_child(Scatter.multi(_rail_mesh(), rail, 1500.0))
	# --- towers: corners always, then along the long sides
	var towers: Array = []
	var off: float = 5.5 if stalag else 3.0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			if style == "uk" and sx * sz > 0.0:
				continue   # British camps: two diagonal towers
			towers.append(_w(axf, yaw, Vector3(sx * (hx + off), 0.0, sz * (hz + off)), PI * 0.25))
	if stalag:
		var n_side: int = 1 + size
		for i in n_side:
			var t: float = (float(i) + 1.0) / float(n_side + 1) * 2.0 - 1.0
			towers.append(_w(axf, yaw, Vector3(t * hx, 0.0, -hz - off), 0.0))
			towers.append(_w(axf, yaw, Vector3(t * hx, 0.0, hz + off), 0.0))
		towers.append(_w(axf, yaw, Vector3(-hx - off, 0.0, 0.0), PI * 0.5))
		towers.append(_w(axf, yaw, Vector3(hx + off, 0.0, 0.0), PI * 0.5))
	container.add_child(Scatter.multi(CampAssets.guard_tower("pow" if style != "uk" else "army"), towers, 5000.0))
	container.add_child(Scatter.multi(CampAssets.gate(team), [_w(axf, yaw, Vector3(0.0, 0.0, hz + (2.6 if stalag else 0.0)), 0.0)], 3000.0))

	# --- huts in rows (long axis along z), the roll-call ground left open on the -x side
	var huts: Array = []
	var nissens: Array = []
	var appel_w: float = hx * 0.38 if style != "ot" else 0.0
	var x0: float = -hx + 14.0 + appel_w
	var x1: float = hx - 14.0
	var hut_len: float = 40.0 if hut_style == "stalag" else 30.0
	var cols: int = maxi(2, int((x1 - x0) / 24.0))
	var rows: int = maxi(1, int((2.0 * hz - 30.0) / (hut_len + 14.0)))
	for c in cols:
		for r in rows:
			var lx: float = lerpf(x0, x1, (float(c) + 0.5) / float(cols))
			var lz: float = lerpf(-hz + 15.0, hz - 15.0, (float(r) + 0.5) / float(rows))
			if absf(lx) < 10.0:
				continue   # the camp street from the gate
			if style == "uk" and (c + r) % 2 == 1:
				nissens.append(_w(axf, yaw, Vector3(lx, 0.0, lz), rng.randf_range(-0.01, 0.01)))
			else:
				huts.append(_w(axf, yaw, Vector3(lx, 0.0, lz), rng.randf_range(-0.01, 0.01)))
	if not huts.is_empty():
		container.add_child(Scatter.multi(CampAssets.barrack_hut(hut_style), huts, 7000.0))
	if not nissens.is_empty():
		container.add_child(Scatter.multi(AirfieldAssets.nissen("Allies"), nissens, 6000.0))
	# cookhouse and ablutions at the head of the street, the sports pitch on the appel ground
	if style != "ot":
		container.add_child(Scatter.multi(CampAssets.cookhouse(), [_w(axf, yaw, Vector3(-hx + appel_w * 0.5 + 6.0, 0.0, hz - 26.0), PI * 0.5)], 6000.0))
		var g0: Vector3 = Vector3(-hx + 12.0 + appel_w * 0.5, 0.0, -hz * 0.45)
		var goals: Array = [_w(axf, yaw, g0 + Vector3(0, 0, -30.0), 0.0), _w(axf, yaw, g0 + Vector3(0, 0, 30.0), 0.0)]
		container.add_child(Scatter.multi(CampAssets.goalposts(), goals, 1500.0))
	else:
		container.add_child(Scatter.multi(CampAssets.cookhouse(), [_w(axf, yaw, Vector3(-hx + 20.0, 0.0, 0.0), 0.0)], 6000.0))
	# camp street and a ring path inside the wire
	var paths: Array = []
	paths.append_array(CampAssets.track_xforms(axf, Vector3(0, 0, hz + 120.0), Vector3(0, 0, -hz + 8.0), 6.0))
	paths.append_array(CampAssets.track_xforms(axf, Vector3(-hx + 5.0, 0, -hz + 5.0), Vector3(hx - 5.0, 0, -hz + 5.0), 3.0))
	paths.append_array(CampAssets.track_xforms(axf, Vector3(-hx + 5.0, 0, hz - 5.0), Vector3(hx - 5.0, 0, hz - 5.0), 3.0))
	container.add_child(Scatter.multi(Scatter.box_unit(earth.darkened(0.12)), paths, 4000.0))

	# --- vorlager outside the gate: guards' barracks, stores, the water tower, the kommandantur
	if stalag or style == "uk":
		var vz: float = hz + 45.0
		var vl: Array = []
		for i in 2 + size:
			var vx: float = (float(i) - float(1 + size) * 0.5) * 26.0
			if absf(vx) < 12.0:
				vx += 26.0 * signf(vx + 0.01)
			vl.append(_w(axf, yaw, Vector3(vx, 0.0, vz + 12.0), PI * 0.5))
		var hut_mesh: Mesh = CampAssets.barrack_hut("stalag") if stalag else AirfieldAssets.nissen("Allies")
		container.add_child(Scatter.multi(hut_mesh, vl, 6000.0))
		container.add_child(Scatter.multi(CampAssets.water_tower(), [_w(axf, yaw, Vector3(-hx * 0.6, 0.0, vz + 30.0), 0.0)], 8000.0))
		container.add_child(Scatter.multi(AirfieldAssets.truck(team), [_w(axf, yaw, Vector3(18.0, 0.0, vz - 10.0), PI * 0.5), _w(axf, yaw, Vector3(26.0, 0.0, vz - 10.0), PI * 0.5)], 2500.0))
		# vorlager wire
		var vf: Array = []
		for xf in CampAssets.fence_ring(axf * Transform3D(Basis.IDENTITY, Vector3(0, 0, vz + 14.0)), yaw, hx * 0.8, 32.0, 6.0):
			vf.append(xf)
		container.add_child(Scatter.multi(CampAssets.fence_bay(false), vf, 2600.0))

	# --- the forest round the camp (cleared strip, then pines), a few trees left inside on the British camps
	var cones: Array = []
	var rounds: Array = []
	var clear: float = 40.0 if stalag else 20.0
	var ring_n: int = 90 if stalag else 50
	for i in ring_n:
		var a: float = rng.randf() * TAU
		var rr: float = rng.randf_range(clear, clear + 70.0)
		var lp := Vector3(cos(a) * (hx + rr), 0.0, sin(a) * (hz + rr))
		if absf(lp.x) < 22.0 and lp.z > 0.0:
			continue
		if (stalag or style == "uk") and lp.z > hz and lp.z < hz + 100.0 and absf(lp.x) < hx * 0.85:
			continue   # vorlager
		var p: Vector3 = axf * lp
		if GroundKit.raw_y(p.x, p.z) < 1.0:
			continue
		var sc: float = rng.randf_range(0.9, 1.35)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sc, sc * rng.randf_range(1.0, 1.3), sc)), Vector3(p.x, GroundKit.ground_y(p.x, p.z) - 0.3, p.z))
		if stalag and rng.randf() < 0.7:
			cones.append(t)
		else:
			rounds.append(t)
	CampAssets.add_trees(container, [cones, rounds])
	if style == "uk":
		var avoid: Array = [[Vector3(0, 0, 0), Vector2(10.0, hz)]]
		for h in huts + nissens:
			var lh: Vector3 = axf.affine_inverse() * (h as Transform3D).origin
			avoid.append([lh, Vector2(7.0, 22.0)])
		CampAssets.add_trees(container, CampAssets.tree_xforms(axf, rng, hx - 10.0, hz - 10.0, 14, avoid))
	return container


static func _rail_mesh() -> ArrayMesh:
	if Scatter._meshes.has("warning_rail"):
		return Scatter._meshes["warning_rail"]
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(0.1, 0.6, 0.1), Vector3(0, 0.3, 0), CampAssets.WOOD_PALE, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(5.0, 0.08, 0.08), Vector3(2.5, 0.55, 0), CampAssets.WOOD_PALE, Vector3.ZERO, false))
	var m: ArrayMesh = AirfieldAssets._build(parts)
	Scatter._meshes["warning_rail"] = m
	return m


static func _w(axf: Transform3D, yaw: float, lp: Vector3, extra_yaw: float) -> Transform3D:
	var p: Vector3 = axf * lp
	p.y = GroundKit.ground_y(p.x, p.z)
	return Transform3D(Basis(Vector3.UP, yaw + extra_yaw), p)
