class_name BuildupKit
extends RefCounted
## Southern England in the spring of 1944 (data/buildup_1944.json), as the reconnaissance photographs and the
## histories of Operation Overlord describe it:
##  * marshalling areas - the "sausages": vehicles parked nose to tail along the verges of the country lanes for
##    miles inland of the embarkation points, under the hedgerow trees where they could;
##  * landing craft (LCT, LCI(L), LST) moored in rows in the Solent, Spithead, Southampton Water, Portsmouth, Poole,
##    Portland, Dartmouth, Torbay, Plymouth and the Sussex harbours;
##  * the Phoenix caissons of the Mulberry harbours, sunk in rows in the shallows off Selsey / Pagham and Dungeness to
##    hide them until they were refloated in the days after D-Day;
##  * embarkation hards: concrete "chocolate-block" slipways built down the beaches from 1942-43.
##
## Cost: per site one MultiMesh per mesh. Lane vehicles are capped per area; craft per anchorage. All fade by 4 km
## (caissons and hards 9 km).

const JSON_PATH := "res://data/buildup_1944.json"
const VIS := 4000.0

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f: FileAccess = FileAccess.open(JSON_PATH, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
	return _data


static func pos(r: Dictionary) -> Vector3:
	return WorldCoords.latlon_to_world(float(r["lat"]), float(r["lon"]))


static func build(r: Dictionary, kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Buildup_" + str(r["id"])
	if not EraClock.is_between(str(r.get("from", "")), str(r.get("to", ""))):
		return root
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(r["id"]))
	match kind:
		"marshalling":
			_marshalling(root, r, rng)
		"anchorage":
			_anchorage(root, r, rng)
		"phoenix_park":
			_phoenix_park(root, r, rng)
		"hard":
			_hard(root, r)
	return root


## Vehicles along the roads: walk the real roads (the data holds the main A-road network) within the radius and park on the verge every ~12 m, in runs
## (a convoy's length) with gaps, both sides on the wider roads. Towns are skipped (no parking in the high street).
static func _marshalling(root: Node3D, r: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = pos(r)
	var radius: float = float(r.get("radius_m", 5000.0))
	var cap: int = int(r.get("vehicles", 300))
	var routes: Array = RoadMesh.routes_in_rect(Vector2(c.x, c.z), radius)
	routes.sort_custom(func(a, b): return int(a["idx"]) < int(b["idx"]))
	var lists: Dictionary = {"truck": [], "tank": [], "halftrack": []}
	var n: int = 0
	for rt in routes:
		if n >= cap:
			break
		var k: String = str(rt["k"])
		if k == "motorway":
			continue          # the road data is the modern major network; the 1944 convoys used the A-roads
		var pts: PackedVector2Array = rt["pts"]
		var run_left: int = 0
		var gap: float = 0.0
		for i in range(pts.size() - 1):
			if n >= cap:
				break
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var seg: float = a.distance_to(b)
			if seg < 1.0:
				continue
			var dir: Vector2 = (b - a) / seg
			var nrm := Vector2(-dir.y, dir.x)
			var t: float = gap
			while t < seg and n < cap:
				var p: Vector2 = a + dir * t
				if p.distance_to(Vector2(c.x, c.z)) > radius:
					t += 12.0
					continue
				if run_left <= 0:
					if rng.randf() < 0.45:
						t += rng.randf_range(80.0, 300.0)       # a gap between convoys
						run_left = 0
						continue
					run_left = rng.randi_range(6, 24)
				var side: float = 1.0 if (int(t / 300.0) + i) % 2 == 0 else -1.0
				var vp: Vector2 = p + nrm * side * 5.5
				if LandCover.class_at(vp.x, vp.y) == 50 or GroundKit.raw_y(vp.x, vp.y) < 1.0:
					t += 12.0
					run_left = 0
					continue
				var yaw: float = atan2(-dir.x, -dir.y)
				var roll: float = rng.randf()
				var kk: String = "truck" if roll < 0.62 else ("tank" if roll < 0.82 else "halftrack")
				(lists[kk] as Array).append(Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.04, 0.04)), Vector3(vp.x, GroundKit.ground_y(vp.x, vp.y), vp.y)))
				n += 1
				run_left -= 1
				t += rng.randf_range(10.0, 13.0)
			gap = maxf(t - seg, 0.0)
	var team: String = "Allies"
	if not (lists["truck"] as Array).is_empty():
		root.add_child(Scatter.multi(AirfieldAssets.truck(team), lists["truck"], VIS))
	if not (lists["tank"] as Array).is_empty():
		root.add_child(Scatter.multi(AirfieldAssets.tank(team), lists["tank"], VIS))
	if not (lists["halftrack"] as Array).is_empty():
		root.add_child(Scatter.multi(AirfieldAssets.halftrack(team), lists["halftrack"], VIS))


## Landing craft moored in rows (trots) on open water round the anchorage centre.
static func _anchorage(root: Node3D, r: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = pos(r)
	var radius: float = float(r.get("radius_m", 1500.0))
	var heading: float = deg_to_rad(float(r.get("heading", 0.0)))
	var basis := Basis(Vector3.UP, -heading)
	var mix: Dictionary = r.get("craft", {"lct": 20})
	var lists: Dictionary = {}
	for t in mix.keys():
		lists[t] = []
		var want: int = int(mix[t])
		var spacing: Vector2 = {"lct": Vector2(16.0, 70.0), "lci": Vector2(14.0, 80.0), "lst": Vector2(28.0, 140.0)}.get(str(t), Vector2(20.0, 80.0))
		var placed: int = 0
		var tries: int = 0
		while placed < want and tries < want * 8:
			tries += 1
			var row: int = rng.randi_range(-8, 8)
			var col_i: int = rng.randi_range(-10, 10)
			var lp := Vector3(float(col_i) * spacing.x * 2.2 + (rng.randf_range(-3, 3)), 0.0, float(row) * spacing.y + {"lct": 0.0, "lci": 30.0, "lst": -45.0}.get(str(t), 0.0))
			if lp.length() > radius:
				continue
			var p: Vector3 = c + basis * lp
			if GroundKit.raw_y(p.x, p.z) > -1.5:
				continue      # needs water under it
			(lists[t] as Array).append(Transform3D(basis * Basis(Vector3.UP, rng.randf_range(-0.06, 0.06)), Vector3(p.x, 0.0, p.z)))
			placed += 1
	for t2 in lists.keys():
		if not (lists[t2] as Array).is_empty():
			root.add_child(Scatter.multi(craft_mesh(str(t2)), lists[t2], VIS))


static func _phoenix_park(root: Node3D, r: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = pos(r)
	var basis := Basis(Vector3.UP, -deg_to_rad(float(r.get("heading", 0.0))))
	var rows: int = int(r.get("rows", 4))
	var cols: int = int(r.get("cols", 8))
	var list: Array = []
	for i in rows:
		for j in cols:
			var lp := Vector3((float(j) - float(cols - 1) * 0.5) * 75.0, 0.0, (float(i) - float(rows - 1) * 0.5) * 40.0)
			var p: Vector3 = c + basis * lp
			if GroundKit.raw_y(p.x, p.z) > -0.3:
				continue
			# sunk on the bottom: only the top couple of metres showing at this state of tide
			list.append(Transform3D(basis * Basis(Vector3.UP, rng.randf_range(-0.05, 0.05)), Vector3(p.x, -2.5, p.z)))
	if not list.is_empty():
		root.add_child(Scatter.multi(MulberryKit.phoenix_mesh(), list, 9000.0))


static func _hard(root: Node3D, r: Dictionary) -> void:
	var c: Vector3 = pos(r)
	var sea: Vector3 = GroundKit.water_dir(c, 600.0)
	if sea == Vector3.ZERO:
		sea = WorldCoords.heading_to_dir(float(r.get("heading", 180.0)))
	var yaw: float = atan2(sea.x, sea.z)
	var list: Array = []
	var w: int = int(r.get("width", 3))
	for k in w:
		var side := Vector3(sea.z, 0.0, -sea.x)
		var p: Vector3 = c + side * ((float(k) - float(w - 1) * 0.5) * 34.0)
		p.y = maxf(GroundKit.ground_y(p.x, p.z), 0.0)
		list.append(Transform3D(Basis(Vector3.UP, yaw), p))
	root.add_child(Scatter.multi(hard_mesh(), list, 9000.0))


# ------------------------------------------------------------------ meshes (bow towards -Z, waterline y = 0)
static func _keep(key: String, parts: Array) -> ArrayMesh:
	var m: ArrayMesh = AirfieldAssets._build(parts)
	Scatter._meshes[key] = m
	return m


static func craft_mesh(t: String) -> ArrayMesh:
	var key: String = "craft_" + t
	if Scatter._meshes.has(key):
		return Scatter._meshes[key]
	var grey := Color(0.40, 0.42, 0.43)
	var dark := Color(0.20, 0.21, 0.22)
	var deck := Color(0.30, 0.31, 0.30)
	var parts: Array = []
	match t:
		"lst":
			# LST: 100 m, high-sided with the bow doors forward, the bridge and funnel aft, deck cargo
			parts.append(GroundKit.box_part(Vector3(15.0, 7.0, 100.0), Vector3(0, 2.5, 0), grey))
			parts.append(GroundKit.box_part(Vector3(13.0, 0.3, 70.0), Vector3(0, 6.1, -8.0), deck, Vector3.ZERO, false))
			parts.append(GroundKit.box_part(Vector3(11.0, 7.0, 12.0), Vector3(0, 9.0, 40.0), grey))
			parts.append(GroundKit.cyl_part(1.0, 1.0, 5.0, Vector3(2.5, 14.0, 38.0), dark, Vector3.ZERO, 6, false))
			parts.append(GroundKit.box_part(Vector3(12.0, 6.5, 6.0), Vector3(0, 2.6, -51.0), grey.darkened(0.1)))
			for i in 5:
				parts.append(GroundKit.box_part(Vector3(3.0, 2.4, 6.0), Vector3(-3.0 + float(i % 2) * 6.0, 7.4, -30.0 + float(i) * 9.0), Color(0.30, 0.33, 0.22), Vector3.ZERO, false))
		"lci":
			# LCI(L): 48 m, ship-shaped bow with gangways each side, a round conning tower
			parts.append(GroundKit.box_part(Vector3(7.0, 3.6, 46.0), Vector3(0, 1.2, 0), grey))
			parts.append(GroundKit.box_part(Vector3(5.0, 3.0, 6.0), Vector3(0, 1.0, -25.0), grey, Vector3(0, 45, 0)))
			parts.append(GroundKit.cyl_part(2.2, 2.4, 3.6, Vector3(0, 4.6, 4.0), grey))
			for sx in [-1.0, 1.0]:
				parts.append(GroundKit.box_part(Vector3(1.0, 0.3, 9.0), Vector3(sx * 4.2, 3.2, -16.0), dark, Vector3(28, 0, 0), false))   # gangway ramps
		_:
			# LCT Mk 4/5: 57 m long open tank deck, wheelhouse aft, the ramp up at the bow; a couple of tanks embarked
			parts.append(GroundKit.box_part(Vector3(9.5, 2.6, 57.0), Vector3(0, 0.9, 0), grey))
			parts.append(GroundKit.box_part(Vector3(8.0, 0.3, 46.0), Vector3(0, 1.6, -4.0), deck, Vector3.ZERO, false))
			parts.append(GroundKit.box_part(Vector3(8.5, 3.4, 0.6), Vector3(0, 2.4, -28.4), grey.darkened(0.1)))
			parts.append(GroundKit.box_part(Vector3(5.5, 4.0, 5.0), Vector3(0, 4.0, 24.5), grey))
			for i in 3:
				parts.append(GroundKit.box_part(Vector3(2.7, 2.2, 5.8), Vector3(0, 2.9, -18.0 + float(i) * 9.0), Color(0.27, 0.29, 0.19)))
	return _keep(key, parts)


## Embarkation hard: the concrete apron down the beach with its interlocking "chocolate-block" mats into the water.
static func hard_mesh() -> ArrayMesh:
	if Scatter._meshes.has("embark_hard"):
		return Scatter._meshes["embark_hard"]
	var conc := Color(0.62, 0.60, 0.55)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(30.0, 0.5, 40.0), Vector3(0, 0.1, -10.0), conc, Vector3.ZERO, false))
	for i in 6:
		parts.append(GroundKit.box_part(Vector3(30.0, 0.35, 6.2), Vector3(0, -0.4 - float(i) * 0.35, 13.0 + float(i) * 6.4), conc.darkened(0.06 * float(i % 2)), Vector3(4, 0, 0), false))
	for sx in [-1.0, 1.0]:
		parts.append(GroundKit.box_part(Vector3(0.5, 0.9, 40.0), Vector3(sx * 15.2, 0.4, -10.0), conc.darkened(0.12), Vector3.ZERO, false))
	return _keep("embark_hard", parts)
