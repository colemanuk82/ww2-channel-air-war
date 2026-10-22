class_name TransportNetwork
extends RefCounted
## Road / rail / sea-lane polylines (RoutePath) for ground traffic. Uses data/osm/{roads,rails}.json when present
## ({"lines":[{"k":..,"pts":[[lat,lon],..]}]}), otherwise falls back to straight-ish lines between cities from
## data/locations.json. Call TransportNetwork.ensure_loaded() once (needs the terrain for the water check).

static var loaded: bool = false
static var roads: Array = []        # RoutePath
static var rails: Array = []        # RoutePath
static var rail_chains: Array = []  # every railway line joined and rounded (PackedVector2Array x,z), before the length cut (RailKit uses these)
static var sea_lanes: Array = []    # {"id": String, "team": String, "comp": String, "route": RoutePath}
static var roads_from_osm: bool = false
static var rails_from_osm: bool = false
static var _cities: Dictionary = {}

const ROAD_PAIRS := [
	["calais", "boulogne"], ["calais", "dunkirk"], ["calais", "saint_omer_town"], ["saint_omer_town", "lille"],
	["lille", "arras"], ["arras", "amiens"], ["amiens", "abbeville"], ["boulogne", "abbeville"], ["dieppe", "rouen"],
	["rouen", "le_havre"], ["rouen", "lisieux"], ["lisieux", "caen"], ["caen", "bayeux"], ["bayeux", "saint_lo"],
	["saint_lo", "valognes"], ["valognes", "cherbourg"], ["amiens", "rouen"], ["abbeville", "le_treport"],
	["le_treport", "dieppe"], ["lille", "brussels"], ["brussels", "ghent"], ["ghent", "bruges"], ["bruges", "ostend"],
	["brussels", "antwerp"], ["dunkirk", "ostend"], ["lille", "ghent"], ["arras", "lille"], ["caen", "rouen"],
	["london", "canterbury"], ["canterbury", "dover"], ["dover", "folkestone"], ["canterbury", "maidstone"],
	["london", "maidstone"], ["london", "brighton"], ["london", "guildford"], ["guildford", "portsmouth"],
	["portsmouth", "southampton"], ["southampton", "poole"], ["london", "reading"], ["london", "chatham"],
	["chatham", "canterbury"], ["brighton", "eastbourne"], ["eastbourne", "hastings"], ["brighton", "chichester"],
	["chichester", "portsmouth"], ["southampton", "reading"], ["ramsgate", "canterbury"], ["hastings", "maidstone"],
]
const RAIL_PAIRS := [
	["calais", "saint_omer_town"], ["saint_omer_town", "lille"], ["lille", "arras"], ["arras", "amiens"],
	["amiens", "rouen"], ["rouen", "le_havre"], ["rouen", "lisieux"], ["lisieux", "caen"], ["caen", "bayeux"],
	["bayeux", "saint_lo"], ["saint_lo", "valognes"], ["valognes", "cherbourg"], ["lille", "brussels"],
	["brussels", "antwerp"], ["brussels", "ghent"], ["ghent", "bruges"], ["bruges", "ostend"], ["calais", "boulogne"],
	["boulogne", "abbeville"], ["abbeville", "amiens"], ["dunkirk", "calais"],
	["london", "canterbury"], ["canterbury", "dover"], ["london", "maidstone"], ["maidstone", "folkestone"],
	["london", "brighton"], ["london", "guildford"], ["guildford", "portsmouth"], ["portsmouth", "southampton"],
	["london", "reading"], ["london", "chatham"], ["brighton", "eastbourne"], ["eastbourne", "hastings"],
]
const EXTRA_SEA_LANES := [
	{"id": "lane_dover_calais", "team": "Allies", "comp": "coastal", "pts": [[51.11, 1.40], [51.03, 1.62], [50.99, 1.80]]},
	{"id": "lane_portsmouth_havre", "team": "Allies", "comp": "mixed", "pts": [[50.74, -1.10], [50.30, -0.70], [49.60, 0.05]]},
	{"id": "lane_kent_fishing", "team": "Allies", "comp": "coastal", "pts": [[51.34, 1.55], [51.30, 1.85], [51.40, 2.10]]},
	{"id": "lane_sussex_fishing", "team": "Allies", "comp": "coastal", "pts": [[50.68, 0.20], [50.62, 0.65], [50.70, 1.0]]},
	{"id": "lane_normandy_fishing", "team": "Axis", "comp": "coastal", "pts": [[49.80, 0.20], [49.90, 0.65], [50.05, 1.0]]},
	{"id": "lane_flanders", "team": "Axis", "comp": "coastal", "pts": [[51.35, 2.95], [51.45, 3.30], [51.40, 3.60]]},
	{"id": "lane_cherbourg", "team": "Axis", "comp": "coastal", "pts": [[49.70, -1.40], [49.65, -0.90], [49.50, -0.60]]},
]


static func ensure_loaded() -> void:
	if loaded:
		return
	loaded = true
	_load_cities()
	# The real (large) road network is drawn and trafficked tile by tile by RoadMesh / WorldPopulator, so only the
	# small synthetic fallback file is turned into RoutePath routes here.
	if _file_size("res://data/osm/roads.json") > 300000:
		roads = []
		roads_from_osm = true
	else:
		roads = _load_osm("res://data/osm/roads.json", 350.0, RoutePath.curve_radius("secondary"))
		roads_from_osm = not roads.is_empty()
		if roads.is_empty():
			roads = _fallback(ROAD_PAIRS, 11)
	rails = _load_osm("res://data/osm/rails.json", 450.0, RoutePath.curve_radius("rail"))
	rails_from_osm = not rails.is_empty()
	if rails.is_empty():
		rails = _fallback(RAIL_PAIRS, 23)
	for l in EXTRA_SEA_LANES:
		sea_lanes.append({"id": l["id"], "team": l["team"], "comp": l["comp"], "route": RoutePath.from_latlon(l["pts"])})


static func _file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else 0


static func _load_cities() -> void:
	var f: FileAccess = FileAccess.open("res://data/locations.json", FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		for c in (d as Dictionary).get("cities", []):
			_cities[c["id"]] = Vector2(float(c["lat"]), float(c["lon"]))


## Lines are read with their bends rounded into curves (RoutePath.fillet_2d) when fillet_r > 0.
static func _load_osm(path: String, min_len: float, fillet_r: float = 0.0) -> Array:
	var out: Array = []
	if not FileAccess.file_exists(path):
		return out
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return out
	var lines: Array = (d as Dictionary).get("lines", [])
	if fillet_r <= 0.0:
		for l in lines:
			var pts: Array = l.get("pts", [])
			if pts.size() < 2:
				continue
			var rp: RoutePath = RoutePath.from_latlon(pts)
			if rp.length >= min_len:
				out.append(rp)
		return out
	# the exports are mostly two-point segments: join them into whole lines, then round the bends
	var kinds := PackedStringArray()
	var segs: Array = []
	for l in lines:
		var pts2: Array = l.get("pts", [])
		if pts2.size() < 2:
			continue
		var p2 := PackedVector2Array()
		for p in pts2:
			var w: Vector3 = WorldCoords.latlon_to_world(float(p[0]), float(p[1]))
			p2.append(Vector2(w.x, w.z))
		kinds.append("x")
		segs.append(p2)
	for ch in RoutePath.chain_2d(kinds, segs):
		var c2: PackedVector2Array = RoutePath.fillet_2d(ch[1], fillet_r)
		if path.ends_with("rails.json"):
			rail_chains.append(c2)
		var p3 := PackedVector3Array()
		for q in c2:
			p3.append(Vector3(q.x, 0.0, q.y))
		var rp2: RoutePath = RoutePath.from_points(p3)
		if rp2.length >= min_len:
			out.append(rp2)
	return out


static func _fallback(pairs: Array, seed_v: int) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for pr in pairs:
		if not _cities.has(pr[0]) or not _cities.has(pr[1]):
			continue
		var a: Vector2 = _cities[pr[0]]
		var b: Vector2 = _cities[pr[1]]
		var pa: Vector3 = WorldCoords.latlon_to_world(a.x, a.y)
		var pb: Vector3 = WorldCoords.latlon_to_world(b.x, b.y)
		var d: float = Vector2(pa.x - pb.x, pa.z - pb.z).length()
		var n: int = maxi(int(d / 350.0), 2)
		var perp: Vector3 = Vector3(-(pb.z - pa.z), 0, pb.x - pa.x).normalized()
		var pts := PackedVector3Array()
		var bad: bool = false
		for i in n + 1:
			var t: float = float(i) / float(n)
			var p: Vector3 = pa.lerp(pb, t)
			if i > 0 and i < n:
				p += perp * rng.randf_range(-1.0, 1.0) * minf(d * 0.04, 60.0)
			if GroundKit.terrain() != null and GroundKit.raw_y(p.x, p.z) < 0.0 and i > 0 and i < n:
				bad = true
				break
			pts.append(p)
		if bad:
			continue
		out.append(RoutePath.from_points(pts))
	return out


## Pick up to `count` routes (longest first, shuffled among the top) near a point; returns Array of RoutePath.
static func routes_near(kind: String, pos: Vector3, max_dist: float) -> Array:
	var src: Array = roads if kind == "roads" else rails
	var out: Array = []
	for r in src:
		var c: Vector2 = (r as RoutePath).closest(pos)
		if c.y <= max_dist:
			out.append(r)
	return out
