class_name WarGround
extends RefCounted
## The ground after the fighting, by date (data/war_ground.json):
##  * floods: the German inundations behind the Normandy beaches (Merderet, Douve, Dives, spring 1944), the Allied
##    breaching of the Walcheren dykes (October 1944), the Betuwe ("the Island") flooded in December 1944 and the
##    Wieringermeer in April 1945 - a terrain zone (kind 5) that turns all ground below the flood level to water,
##    with the hedge tops and trees still standing out of it;
##  * battlefields: crater fields (terrain zone kind 4, the same as bomb damage - in open country only the craters
##    show) with knocked-out tanks and burnt lorries left where they were hit (Goodwood, Hill 112, Villers-Bocage,
##    Totalize, the Huertgen, the Reichswald, Oosterbeek...);
##  * beaches: the invasion beaches after the landings, churned by tracks (terrain zone kind 6), with wrecked landing
##    craft at the waterline and drowned tanks; and the Dunkirk beaches of June 1940, lined with the BEF's
##    abandoned lorries.
##
## Cost: the floods and churn are terrain-shader zones (no geometry). Wrecks are one MultiMesh per mesh per site,
## capped by the data (a few dozen per site) with 3 km fades.

const JSON_PATH := "res://data/war_ground.json"
const VIS := 3200.0

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f: FileAccess = FileAccess.open(JSON_PATH, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
	return _data


static func _pos(r: Dictionary) -> Vector3:
	return WorldCoords.latlon_to_world(float(r["lat"]), float(r["lon"]))


## Terrain zones live on the current date: floods (kind 5, level in metres / 40 in the fraction), battlefield crater
## fields (kind 4), churned beaches (kind 6).
static func zones() -> Array:
	var out: Array = []
	var d: Dictionary = data()
	for r in d.get("floods", []):
		var rd: Dictionary = r
		if not EraClock.is_between(str(rd["from"]), str(rd["to"])):
			continue
		var lvl_y: float = float(rd.get("level_m", 3.0)) * WorldCoords.VERTICAL_SCALE
		out.append({"pos": _pos(rd), "heading": float(rd.get("heading", 0.0)), "half": Vector2(float(rd["rz"]), float(rd["rx"])), "feather": float(rd.get("feather", 400.0)), "kind": 5.0 + clampf(lvl_y / 40.0, 0.0, 0.99)})
	for r in d.get("battlefields", []):
		var bd: Dictionary = r
		if not EraClock.is_between(str(bd["from"]), str(bd["to"])):
			continue
		var lv: float = float(bd.get("craters", 0.5)) * lerpf(0.5, 1.0, EraClock.ramp(str(bd["from"]), str(bd.get("full", bd["from"]))))
		out.append({"pos": _pos(bd), "heading": float(bd.get("heading", 0.0)), "half": Vector2(float(bd["rz"]), float(bd["rx"])), "feather": float(bd["rx"]) * 0.4, "kind": 4.0 + clampf(lv, 0.0, 0.99)})
	for r in d.get("beaches", []):
		var sd: Dictionary = r
		if not EraClock.is_between(str(sd["from"]), str(sd.get("churn_to", sd["to"]))):
			continue
		out.append({"pos": _pos(sd), "heading": float(sd.get("heading", 0.0)), "half": Vector2(float(sd["length"]) * 0.5, 120.0), "feather": 120.0, "kind": 6.0 + clampf(float(sd.get("churn", 0.7)), 0.0, 0.99)})
	return out


## Build the wreckage of one battlefield or beach row (empty outside its date window).
static func build(r: Dictionary, kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "WarGround_" + str(r["id"])
	if not EraClock.is_between(str(r["from"]), str(r["to"])):
		return root
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(r["id"]))
	var c: Vector3 = _pos(r)
	var team: String = str(r.get("team", "Allies"))
	var buckets: Dictionary = {}
	if kind == "battlefield":
		var rx: float = float(r["rx"])
		var rz: float = float(r["rz"])
		var hb := Basis(Vector3.UP, -deg_to_rad(float(r.get("heading", 0.0))))
		for spec in [["tank", int(r.get("tanks", 0))], ["enemy_tank", int(r.get("enemy_tanks", 0))], ["lorry", int(r.get("lorries", 0))]]:
			for i in int(spec[1]):
				var lp := Vector3(rng.randf_range(-rx, rx), 0.0, rng.randf_range(-rz, rz))
				if (lp.x * lp.x) / (rx * rx) + (lp.z * lp.z) / (rz * rz) > 1.0:
					continue
				var p: Vector3 = c + hb * lp
				if GroundKit.raw_y(p.x, p.z) < 1.0:
					continue
				p.y = GroundKit.ground_y(p.x, p.z)
				_put(buckets, str(spec[0]), Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.FORWARD, rng.randf_range(-0.08, 0.08)), p))
	else:
		# beach: wrecks strung along the shore, landing craft at and below the waterline, vehicles on the sand
		var L: float = float(r["length"])
		var along := WorldCoords.heading_to_dir(float(r.get("heading", 90.0)))
		var across := Vector3(-along.z, 0.0, along.x)
		var sea_dir: Vector3 = GroundKit.water_dir(c, 900.0)      # once per beach: the shore faces one way
		if sea_dir == Vector3.ZERO:
			sea_dir = across
		var sq: Vector3 = sea_dir - along * sea_dir.dot(along)        # square to the shoreline
		sea_dir = sq.normalized() if sq.length() > 0.2 else across
		for spec2 in [["landing_craft", int(r.get("landing_craft", 0))], ["tank", int(r.get("tanks", 0))], ["lorry", int(r.get("lorries", 0))]]:
			for i in int(spec2[1]):
				var base: Vector3 = c + along * rng.randf_range(-L * 0.5, L * 0.5)
				# walk in from the sea to the waterline
				var best: Vector3 = Vector3.INF
				for k in 31:
					var q: Vector3 = base + sea_dir * (300.0 - float(k) * 20.0)
					if GroundKit.raw_y(q.x, q.z) > 0.2:
						best = q
						break
				if best == Vector3.INF:
					continue
				var t: String = str(spec2[0])
				var off: float = rng.randf_range(-30.0, 5.0) if t == "landing_craft" else rng.randf_range(8.0, 80.0)
				var p2: Vector3 = best - sea_dir * off
				p2.y = maxf(GroundKit.ground_y(p2.x, p2.z), -1.4 if t == "landing_craft" else -0.8)
				var yaw: float = atan2(sea_dir.x, sea_dir.z) + rng.randf_range(-0.5, 0.5) + (PI if t == "landing_craft" else rng.randf_range(-1.2, 1.2))
				_put(buckets, t, Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, rng.randf_range(-0.12, 0.12)), p2))
	for key in buckets.keys():
		root.add_child(Scatter.multi(_mesh(str(key), team), buckets[key], VIS))
	return root


static func _put(b: Dictionary, k: String, t: Transform3D) -> void:
	if not b.has(k):
		b[k] = []
	(b[k] as Array).append(t)


static func _mesh(k: String, team: String) -> ArrayMesh:
	match k:
		"tank":
			return burnt_tank_mesh(team, false)
		"enemy_tank":
			return burnt_tank_mesh(GroundKit.enemy_of(team), true)
		"landing_craft":
			return wrecked_lct_mesh()
	return burnt_lorry_mesh()


# ------------------------------------------------------------------ meshes (nose -Z, ground y = 0)
static func _keep(key: String, parts: Array) -> ArrayMesh:
	var m: ArrayMesh = AirfieldAssets._build(parts)
	Scatter._meshes[key] = m
	return m


## A knocked-out tank: hull and turret burnt out (rust-brown and black), the turret traversed and slewed off its
## ring on some, a track thrown. Allied = Sherman / Cromwell outline, Axis = Panzer IV / Panther outline.
static func burnt_tank_mesh(team: String, alt: bool) -> ArrayMesh:
	var key: String = "burnt_tank_%s_%s" % [team, str(alt)]
	if Scatter._meshes.has(key):
		return Scatter._meshes[key]
	var allied: bool = team == "Allies"
	var paint: Color = Color(0.25, 0.26, 0.18) if allied else Color(0.44, 0.39, 0.26)
	var burnt := Color(0.28, 0.17, 0.11)
	var black := Color(0.07, 0.06, 0.06)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(2.7, 1.2, 5.9), Vector3(0, 1.3, 0), burnt))
	parts.append(GroundKit.box_part(Vector3(2.4, 0.5, 4.2), Vector3(0.1, 1.95, 0.6), paint.darkened(0.25), Vector3.ZERO, false))   # paint left on the deck
	for sx in [-1.0, 1.0]:
		var thrown: bool = sx > 0.0 and alt
		parts.append(GroundKit.box_part(Vector3(0.62, 1.0, 6.2), Vector3(sx * 1.45 + (0.9 if thrown else 0.0), 0.55 if not thrown else 0.15, 0.4 if thrown else 0.0), black, Vector3(0, 6 if thrown else 0, 70 if thrown else 0)))
	if allied:
		parts.append(GroundKit.cyl_part(1.0, 1.15, 1.0, Vector3(0.2, 2.35, 0.5), burnt.darkened(0.15), Vector3(0, 0, 9), 10))
		parts.append(GroundKit.cyl_part(0.11, 0.13, 2.8, Vector3(1.6, 2.3, -0.2), black, Vector3(90, -55, 0), 6, false))
	else:
		parts.append(GroundKit.box_part(Vector3(2.1, 0.9, 2.7), Vector3(-0.3, 2.3, 0.4), burnt.darkened(0.1), Vector3(0, 35, -6)))
		parts.append(GroundKit.cyl_part(0.1, 0.12, 4.2, Vector3(-1.8, 2.3, -0.9), black, Vector3(90, 35, 0), 6, false))
	parts.append(GroundKit.cyl_part(2.6, 3.4, 0.05, Vector3(0, 0.03, 0), Color(0.09, 0.08, 0.07), Vector3.ZERO, 10, false))   # scorched ground
	return _keep(key, parts)


## A burnt-out lorry: blackened cab and chassis, the canvas tilt burnt away to the hoops.
static func burnt_lorry_mesh() -> ArrayMesh:
	if Scatter._meshes.has("burnt_lorry"):
		return Scatter._meshes["burnt_lorry"]
	var burnt := Color(0.25, 0.16, 0.11)
	var black := Color(0.07, 0.06, 0.06)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(2.2, 0.4, 6.6), Vector3(0, 0.9, 0), black))
	parts.append(GroundKit.box_part(Vector3(2.1, 1.6, 1.8), Vector3(0, 1.8, -2.3), burnt))
	parts.append(GroundKit.box_part(Vector3(2.2, 0.6, 4.0), Vector3(0, 1.4, 1.2), burnt.darkened(0.2)))
	for i in 4:
		parts.append(GroundKit.box_part(Vector3(2.2, 0.08, 0.08), Vector3(0, 2.7, -0.4 + float(i) * 1.1), black, Vector3.ZERO, false))
		for sx in [-1.0, 1.0]:
			parts.append(GroundKit.box_part(Vector3(0.08, 1.1, 0.08), Vector3(sx * 1.05, 2.15, -0.4 + float(i) * 1.1), black, Vector3.ZERO, false))
	for z in [-2.3, 1.0, 2.4]:
		for sx2 in [-1.0, 1.0]:
			parts.append(GroundKit.cyl_part(0.48, 0.48, 0.32, Vector3(sx2 * 1.05, 0.48, z), black, Vector3(0, 0, 90), 8, false))
	return _keep("burnt_lorry", parts)


## A wrecked LCT / LCA: a flat-bottomed landing craft stranded broadside or bow-in, ramp down, holed and listing.
static func wrecked_lct_mesh() -> ArrayMesh:
	if Scatter._meshes.has("wrecked_lct"):
		return Scatter._meshes["wrecked_lct"]
	var grey := Color(0.36, 0.38, 0.38)
	var dark := Color(0.16, 0.17, 0.17)
	var rust := Color(0.36, 0.22, 0.14)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(9.0, 2.6, 34.0), Vector3(0, 1.0, 0), grey))                 # hull
	parts.append(GroundKit.box_part(Vector3(9.2, 0.8, 34.2), Vector3(0, 0.1, 0), rust, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(7.6, 0.3, 30.0), Vector3(0, 0.9, -1.0), dark, Vector3.ZERO, false))   # tank deck
	parts.append(GroundKit.box_part(Vector3(8.0, 0.4, 5.0), Vector3(0, 0.2, -18.6), grey.darkened(0.15), Vector3(-22, 0, 0)))  # ramp down
	parts.append(GroundKit.box_part(Vector3(5.0, 3.6, 4.5), Vector3(0, 3.6, 14.0), grey))                # wheelhouse aft
	parts.append(GroundKit.box_part(Vector3(1.6, 1.6, 1.6), Vector3(2.8, 1.8, 2.0), Color(0.05, 0.05, 0.05), Vector3.ZERO, false))   # shell hole
	return _keep("wrecked_lct", parts)
