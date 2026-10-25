class_name WorldPopulator
extends Node3D
## Streams all ground-war + scenery content around the player (never the whole map at once).
##   var wp := WorldPopulator.populate(world_root, terrain, airfields_dict)   # call from main._ready() after the
##                                                                            # terrain exists (before first frame)
## Public API:
##   get_airfield(id) -> Airfield           (spawns + pins on demand, flattens terrain already done in populate)
##   spawn_target(id) -> Node               (force-spawns + pins a locations.json 'targets' entry, returns the
##                                           main mission_target node: GroundStructure / Convoy)
##   get_target_info(id) -> Dictionary      {id,name,type,team,pos(Vector3)}
##   targets_for_side(owner_side, types) -> Array[String]
##   pin_site(key) / free_all()
## Debug args (after `--`): --wp-demo  --wp-mode=bombing:port_calais | ground_attack | hist:dday_1944[:Allies] | bombtest
## Sites are streamed by distance (SITE_BUDGET builds per SITE_TICK); countryside tiles (farms/hedges/cattle/trees) by grid cell.

const TILE: float = 1800.0
const TILE_RADIUS: float = 12800.0
const SITE_TICK: float = 0.15
const SITE_BUDGET: int = 4
const TILE_BUDGET: int = 3
const BOOST_RADIUS: float = 8000.0   # load screen: tiles inside this are built before the game starts; the rest stream in flight
## Sites activate at act * ACT_SCALE so they are built while still outside their render
## (visibility_range) distance: no pop-in as they fade in.
const ACT_SCALE: float = 2.2

static var instance: WorldPopulator = null

var terrain: Node
var world_root: Node3D
var focus: Node3D
var existing_airfields: Dictionary = {}
## Keep-out discs [centre, radius] around every airfield's runways: no AA guns / lights / balloons inside.
var _runway_zones: Array = []
var airfields: Dictionary = {}                 # id -> Airfield
var loc: Dictionary = {}
var enable_countryside: bool = true
var enable_traffic: bool = true

var _sites: Array = []                          # Dictionary
var _site_by_key: Dictionary = {}
var _target_info: Dictionary = {}
var _target_main: Dictionary = {}               # id -> Node (live)
var _destroyed: Dictionary = {}                 # site key / target id -> true
var _tiles: Dictionary = {}                     # Vector2i -> Node3D
var _ground_zones: Array = []                   # terrain tint zones for camps (see TerrainChunkManager.add_ground_zones)
var _exclude: Array = []                        # [[Vector3, radius]]
var _timer: float = 0.0
var _tile_timer: float = 0.0
var _debug_done: bool = false
var _frames: int = 0
var _ambient_active: int = 0
var _warm_center: Vector3 = Vector3(1.0e9, 0.0, 1.0e9)


# ================================================================== setup
static func populate(p_world_root: Node3D, p_terrain: Node, p_airfields: Dictionary = {}) -> WorldPopulator:
	var wp := WorldPopulator.new()
	wp.name = "WorldPopulator"
	wp.world_root = p_world_root
	wp.terrain = p_terrain
	wp.existing_airfields = p_airfields
	p_world_root.add_child(wp)
	return wp


## Returns the live populator, creating one under `world` if main.gd did not call populate().
static func ensure(world: Node3D) -> WorldPopulator:
	if instance != null and is_instance_valid(instance):
		return instance
	var t: Node = world.get_tree().get_first_node_in_group("terrain")
	var afs: Dictionary = {}
	if "airfields" in world:
		afs = world.get("airfields")
	return populate(world, t, afs)


func _ready() -> void:
	instance = self
	add_to_group("world_populator")
	EraClock.set_date(GameState.era_date)
	_built_era = EraClock.current()
	WarDamage.refresh()
	RegionMap.load_map()
	GroundKit.lp("  populator _ready start")
	_load_locations()
	GroundKit.lp("  _load_locations")
	# The data loaders only parse their own files, so they run side by side on the worker pool. The roads and the
	# rail track both need the transport network's joined, rounded rail lines, so they run in a second stage.
	var jobs: Array = [
		func() -> void: TransportNetwork.ensure_loaded(),
		func() -> void: RiverMesh.ensure_loaded(),
		func() -> void: PylonMesh.ensure_loaded(),
		func() -> void: CanalKit.ensure_loaded(),
	]
	var gid: int = WorkerThreadPool.add_group_task(func(i: int) -> void: (jobs[i] as Callable).call(), jobs.size(), -1, true)
	WorkerThreadPool.wait_for_group_task_completion(gid)
	var jobs2: Array = [
		func() -> void: RoadMesh.ensure_loaded(),
		func() -> void: RailKit.ensure_loaded(),
	]
	var gid2: int = WorkerThreadPool.add_group_task(func(i: int) -> void: (jobs2[i] as Callable).call(), jobs2.size(), -1, true)
	WorkerThreadPool.wait_for_group_task_completion(gid2)
	if not RiverMesh.lines.is_empty():
		RenderingServer.global_shader_parameter_set("real_rivers", 1.0)
	GroundKit.lp("  data loaders (parallel)")
	_register_airfields()
	_register_cities()
	_register_features()
	_register_targets()
	_register_dams()
	_register_decoys()
	_register_industry()
	_register_rail_drama()
	_register_oil_fuel()
	_register_aircraft_industry()
	_register_v_weapons()
	_register_rural()
	_register_coastal_landmarks()
	_register_civil_defence()
	GroundKit.lp("  register airfields..civil defence")
	_register_aviation_support()
	_register_forestry()
	_register_navigation_aids()
	_register_military_depth()
	GroundKit.lp("  register aviation..military depth")
	_register_coast_defences()
	_register_ports()
	_register_sea_defences()
	_register_sweepers()
	_register_docks()
	_register_port_clutter()
	_register_camps()
	_register_pow_camps()
	_register_mulberries()
	_register_war_ground()
	_register_buildup()
	_register_kammhuber()
	add_child(BargeTraffic.new())
	for ch in WestwallKit.chunks():
		_add_site("westwall_%s_%d" % [str(ch[0]), int(ch[1])], ch[3], 9000.0, func(s: Dictionary) -> Node3D: return WestwallKit.build(str(s["lid"]), int(s["i0"]), int(s["i1"])), {"lid": str(ch[0]), "i0": int(ch[1]), "i1": int(ch[2])})
	if terrain != null and terrain.has_method("add_ground_zones"):
		terrain.call("add_ground_zones", _ground_zones)
	_push_era_zones()
	_register_osm_extras()
	GroundKit.lp("  register coast..osm extras")
	if enable_traffic:
		_register_traffic()
	GroundKit.lp("  register traffic")
	# Make sure flat zones registered above show up even if chunks already exist.
	if terrain != null and "_chunks" in terrain and not (terrain.get("_chunks") as Dictionary).is_empty() and terrain.has_method("rebuild"):
		terrain.call("rebuild")


func _exit_tree() -> void:
	if instance == self:
		instance = null
	for j in _tile_jobs:
		WorkerThreadPool.wait_for_task_completion(int((j as Dictionary)["task"]))
	_tile_jobs.clear()


func _load_locations() -> void:
	var f: FileAccess = FileAccess.open("res://data/locations.json", FileAccess.READ)
	if f == null:
		push_warning("WorldPopulator: data/locations.json missing")
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		loc = d


func _add_site(key: String, pos: Vector3, act: float, builder: Callable, extra: Dictionary = {}) -> Dictionary:
	var s: Dictionary = {"key": key, "pos": pos, "act": act * ACT_SCALE, "build": builder, "node": null, "main": null, "pin": false, "route": null, "ambient": false}
	s.merge(extra, true)
	_sites.append(s)
	_site_by_key[key] = s
	return s


func _ll(d: Dictionary) -> Vector3:
	return WorldCoords.latlon_to_world(float(d["lat"]), float(d["lon"]))


func _y(p: Vector3) -> float:
	return GroundKit.ground_y(p.x, p.z)


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, _y(p), p.z)


# ================================================================== registration
func _existing_for(id: String, pos: Vector3) -> Airfield:
	if existing_airfields.has(id) and is_instance_valid(existing_airfields[id]):
		return existing_airfields[id]
	for k in existing_airfields.keys():
		var ex: Variant = existing_airfields[k]
		if ex is Airfield and is_instance_valid(ex):
			var e3: Vector3 = (ex as Airfield).position
			if Vector2(e3.x - pos.x, e3.z - pos.z).length() < 500.0:
				return ex
	return null


func _register_airfields() -> void:
	var zones: Array = []
	for a in loc.get("airfields", []):
		var d: Dictionary = a
		if not bool(d.get("in_bounds", true)):
			continue
		var id: String = d["id"]
		var pos: Vector3 = _ll(d)
		var y: float
		var ex: Airfield = _existing_for(id, pos)
		if ex != null:
			pos = Vector3(ex.position.x, 0, ex.position.z)
			y = ex.surface_y
			airfields[id] = ex
		else:
			y = float(terrain.call("add_flat_zone", pos, 1000.0, 500.0)) if terrain else 0.0
		_exclude.append([pos, 1900.0])
		var hdir: Vector3 = WorldCoords.heading_to_dir(float(d["heading_deg"]))
		zones.append({"pos": pos, "heading": float(d["heading_deg"]), "half": Vector2(820.0, 1000.0), "feather": 200.0})
		RoadMesh.add_exclusion_box(Vector2(pos.x, pos.z), Vector2(hdir.x, hdir.z), 720.0, 780.0)
		# a large army camp beside some fields: reserve its ground now so trees and buildings keep clear of it
		var camp: Vector3 = Vector3.INF
		if ArmyCampKit.wants_camp(id):
			camp = ArmyCampKit.site_for(id, pos, float(d["heading_deg"]))
			if camp != Vector3.INF:
				_exclude.append([camp, ArmyCampKit.CAMP_RADIUS])
				if terrain:
					terrain.call("add_flat_zone", camp, 370.0, 260.0)
				RoadMesh.add_exclusion_disc(Vector2(camp.x, camp.z), ArmyCampKit.CAMP_RADIUS * 0.85)
				_ground_zones.append(ArmyCampKit.zone_for(camp, float(d["heading_deg"])))
		_add_site("af_" + id, pos, 9500.0, _build_airfield, {"id": id, "data": d, "y": y, "existing": ex, "camp": camp})
	_apply_airfield_zones(zones)


func _apply_airfield_zones(zones: Array) -> void:
	if terrain != null and terrain.has_method("set_airfield_zones"):
		terrain.call("set_airfield_zones", zones)


func _register_cities() -> void:
	var lm: Dictionary = {}
	for f in loc.get("features", []):
		if f["type"] == "landmark":
			lm[f["id"]] = f
	for c in loc.get("cities", []):
		var d: Dictionary = c
		if not bool(d.get("in_bounds", true)):
			continue
		var pos: Vector3 = _ll(d)
		var size: int = int(d["size"])
		var radius: float = 90.0 + float(size) * 85.0
		_exclude.append([pos, radius * 0.95])
		# Phase 5.3: hand the city its landmark index so _build_city can resolve cities[].landmark names to landmark
		# ids and place only those whose features[] row is absent (an existing row is streamed as `lm_<id>` instead).
		# `lm` is id -> features row; `lm_json` is id -> {name, lat, lon} from data/landmarks_1940.json.
		_add_site("city_" + d["id"], pos, 7500.0 + radius, _build_city,
			{"id": d["id"], "data": d, "size": size, "lm": lm, "lm_json": _landmark_json_index()})


func _register_features() -> void:
	for f in loc.get("features", []):
		var d: Dictionary = f
		if not bool(d.get("in_bounds", true)):
			continue
		var pos: Vector3 = _ll(d)
		match str(d["type"]):
			"landmark":
				if str(d["id"]) == "arromanches_mulberry":
					continue        # replaced by the dated MulberryKit harbours (_register_mulberries)
				_add_site("lm_" + d["id"], pos, 16000.0, _build_landmark, {"id": d["id"], "data": d})
			"beach":
				var r: float = clampf(float(d.get("radius_m", 3000.0)) / 10.0, 150.0, 900.0)
				_add_site("beach_" + d["id"], pos, 6500.0 + r, _build_beach, {"id": d["id"], "data": d, "radius": r})
			# "forest" features are no longer registered: woodland now comes from the real land
			# cover via tile streaming (Scatter._make_tile_landcover), so the shape is accurate.


## Industrial areas: clusters of factories and oil refineries on the outskirts of the big industrial towns (Thames,
## Medway, Southampton, Antwerp, Lille, Rouen, Le Havre...), with flak. Each is also a raid objective for ambient sorties.
## [id, name, lat, lon, factories, refineries]
const INDUSTRY := [
	["erith", "Erith and Dartford Works", 51.465, 0.19, 4, 0],
	["coryton", "Coryton Refinery", 51.515, 0.50, 0, 2],
	["medway", "Medway Works", 51.40, 0.55, 3, 0],
	["slough", "Slough Trading Estate", 51.515, -0.60, 3, 0],
	["reading_ind", "Reading Works", 51.46, -0.97, 2, 0],
	["portsmouth_ind", "Portsmouth Dockyard Works", 50.82, -1.07, 3, 0],
	["southampton_ind", "Southampton Works", 50.90, -1.41, 3, 0],
	["fawley", "Fawley Refinery", 50.835, -1.345, 1, 2],
	["plymouth_ind", "Devonport Works", 50.39, -4.17, 2, 0],
	["dunkirk_ind", "Dunkirk Refinery and Works", 51.03, 2.33, 2, 1],
	["calais_ind", "Calais Works", 50.94, 1.90, 2, 0],
	["boulogne_ind", "Boulogne Works", 50.72, 1.60, 2, 0],
	["lille_ind", "Lille Industrial Area", 50.64, 3.08, 4, 0],
	["amiens_ind", "Amiens Works", 49.88, 2.30, 2, 0],
	["rouen_ind", "Rouen Refineries and Works", 49.37, 1.07, 3, 2],
	["port_jerome", "Port-Jerome Refineries", 49.47, 0.55, 1, 3],
	["caen_ind", "Colombelles Steelworks", 49.21, -0.33, 3, 0],
	["cherbourg_ind", "Cherbourg Arsenal Works", 49.64, -1.62, 2, 0],
	["ghent_ind", "Ghent-Terneuzen Industry", 51.12, 3.78, 3, 1],
	["antwerp_ind", "Antwerp Refineries and Works", 51.26, 4.35, 3, 3],
	["brussels_ind", "Brussels Works", 50.88, 4.38, 3, 0],
]
var industry_sites: Array = []        # [{id, name, pos, team, kind, size, factories, refineries}] for raid planning
const INDUSTRY_JSON := "res://data/industry_1940.json"


## Phase 4.2: industry is placed from data/industry_1940.json by `kind` (mirrors data/docks_1940.json), oriented
## along the nearest rail (or river) and given a rail siding stub. Falls back to the legacy INDUSTRY clusters when
## the JSON is missing so a no-data run still populates industry. Each site stays in `industry_sites` for campaign /
## planner raid objectives.
func _register_industry() -> void:
	var sites: Array = _load_industry_1940()
	if sites.is_empty():
		_register_industry_legacy()
		return
	var placed: int = 0
	for e in sites:
		var d: Dictionary = e
		var pos: Vector3 = WorldCoords.latlon_to_world(float(d["lat"]), float(d["lon"]))
		if not WorldCoords.is_in_bounds(pos):
			continue
		var team: String = str(d.get("team", ""))
		if team == "":
			team = GroundKit.side_at(pos)
		var size: int = int(d.get("size", 2))
		var kind: String = str(d.get("kind", "mill"))
		var id: String = str(d.get("id", "industry"))
		var nm: String = str(d.get("name", id))
		_exclude.append([pos, 260.0 + 80.0 * float(size)])
		RoadMesh.add_exclusion_disc(Vector2(pos.x, pos.z), 220.0 + 80.0 * float(size))
		var extra: Dictionary = {"id": id, "name": nm, "team": team, "size": size, "kind": kind}
		var rail: Dictionary = _nearest_rail(pos)
		if not rail.is_empty():
			var rail_pt: Vector3 = rail["point"]
			extra["rail_pt"] = rail_pt
			extra["siding"] = RoutePath.from_points(PackedVector3Array([pos, rail_pt]))    # a Train can serve it later
		_add_site("ind_" + id, pos, 8500.0, _build_industry, extra)
		industry_sites.append({"id": id, "name": nm, "pos": pos, "team": team, "kind": kind, "size": size, "factories": 1, "refineries": 0})
		placed += 1
	GroundKit.lp("  _register_industry (%d sites from industry_1940.json)" % placed)


## The pre-Phase-4 clusters (still the fallback path if data/industry_1940.json is absent).
func _register_industry_legacy() -> void:
	for e in INDUSTRY:
		var pos: Vector3 = WorldCoords.latlon_to_world(float(e[2]), float(e[3]))
		var team: String = GroundKit.side_at(pos)
		var n_f: int = int(e[4])
		var n_r: int = int(e[5])
		_exclude.append([pos, 330.0 + 60.0 * float(n_f + n_r)])
		_add_site("ind_" + str(e[0]), pos, 8500.0, _build_industry_legacy, {"id": str(e[0]), "name": str(e[1]), "team": team, "nf": n_f, "nr": n_r})
		industry_sites.append({"id": str(e[0]), "name": str(e[1]), "pos": pos, "team": team, "kind": "cluster", "size": 3, "factories": n_f, "refineries": n_r})


func _load_industry_1940() -> Array:
	var f: FileAccess = FileAccess.open(INDUSTRY_JSON, FileAccess.READ)
	if f == null:
		push_warning("WorldPopulator: %s missing - using legacy INDUSTRY clusters" % INDUSTRY_JSON)
		return []
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return []
	return (d as Dictionary).get("sites", [])


## Nearest rail RoutePath to a point within `max_dist`; {} if none. {route, s, dist, point}.
var _rail_boxes: Array = []


func _nearest_rail(pos: Vector3, max_dist: float = 6000.0) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = max_dist
	if _rail_boxes.size() != TransportNetwork.rails.size():
		_rail_boxes.clear()                 # bounding box per rail, so far-away rails skip the polyline walk
		for r0 in TransportNetwork.rails:
			var pts0: PackedVector3Array = (r0 as RoutePath).points
			var lo := Vector2(1.0e12, 1.0e12)
			var hi := Vector2(-1.0e12, -1.0e12)
			for p0 in pts0:
				lo = Vector2(minf(lo.x, p0.x), minf(lo.y, p0.z))
				hi = Vector2(maxf(hi.x, p0.x), maxf(hi.y, p0.z))
			_rail_boxes.append(Rect2(lo, hi - lo))
	for ri in TransportNetwork.rails.size():
		var r: RoutePath = TransportNetwork.rails[ri]
		if not (_rail_boxes[ri] as Rect2).grow(best_d).has_point(Vector2(pos.x, pos.z)):
			continue
		var c: Vector2 = (r as RoutePath).closest(pos)
		if c.y < best_d:
			best_d = c.y
			best = {"route": r, "s": c.x, "dist": c.y, "point": (r as RoutePath).sample(c.x)}
	return best


## Direction (unit XZ) to the nearest real river centreline within `max_dist`, or ZERO. Read-only over
## RiverMesh.lines (no prepare_block / _river_block), so it is safe while tiles stream on a worker thread.
func _nearest_river_dir(pos: Vector3, max_dist: float = 1500.0) -> Vector3:
	if not RiverMesh.has_rivers():
		return Vector3.ZERO
	var p := Vector2(pos.x, pos.z)
	var best_d: float = max_dist
	var best_pt := Vector2.ZERO
	var found: bool = false
	for ln in RiverMesh.lines:
		var pts: PackedVector2Array = ln["pts"]
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var ab: Vector2 = b - a
			var l2: float = maxf(ab.length_squared(), 0.0001)
			var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
			var q: Vector2 = a + ab * t
			var dd: float = q.distance_to(p)
			if dd < best_d:
				best_d = dd
				best_pt = q
				found = true
	if not found:
		return Vector3.ZERO
	var dir := Vector3(best_pt.x - p.x, 0.0, best_pt.y - p.y)
	return dir.normalized() if dir.length() > 1.0 else Vector3.ZERO


## Site heading: face the nearest rail (local -Z = the siding direction), else the nearest river, else deterministic.
func _industry_yaw(pos: Vector3, rail_pt: Vector3, id: String) -> float:
	if rail_pt != Vector3.ZERO:
		var d: Vector3 = rail_pt - pos
		d.y = 0.0
		if d.length() > 2.0:
			return WorldCoords.dir_to_heading(d)
	var rd: Vector3 = _nearest_river_dir(pos)
	if rd != Vector3.ZERO:
		return WorldCoords.dir_to_heading(rd)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + 9
	return rng.randf() * 360.0


## Build a site from data/industry_1940.json: the typed IndustryKit works, a rail siding stub, and (for the larger
## sites) a couple of AA guns.
func _build_industry(s: Dictionary) -> Node3D:
	var container := Node3D.new()
	var pos: Vector3 = s["pos"]
	var team: String = str(s.get("team", "Allies"))
	var kind: String = str(s.get("kind", "mill"))
	var size: int = int(s.get("size", 2))
	var id: String = str(s.get("id", "industry"))
	var rail_pt: Vector3 = s.get("rail_pt", Vector3.ZERO)
	var yaw: float = _industry_yaw(pos, rail_pt, id)
	var works: Node3D = IndustryKit.build(kind, pos, yaw, size, team, hash(id))
	if works != null:
		container.add_child(works)
	if rail_pt != Vector3.ZERO:
		container.add_child(IndustryKit.build_siding(pos, rail_pt, hash(id) + 1))
	if size >= 3:
		_defences(container, pos, team, 2 if team == "Axis" else 1, 1, 0, 0, 220.0, hash(id) + 3)
	if kind != "quarry":
		_camouflage_industry(container, pos, yaw, size, hash(id) + 41)      # P15 camouflage-painted factory roof (never over an open pit)
	return container


## Legacy cluster builder: a grid of GroundStructure factories/refineries (used when the JSON is missing).
func _build_industry_legacy(s: Dictionary) -> Node3D:
	var container := Node3D.new()
	var center: Vector3 = s["pos"]
	var team: String = str(s["team"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(s["id"]))
	var n_f: int = int(s["nf"])
	var n_r: int = int(s["nr"])
	var yaw: float = float(rng.randi() % 4) * 90.0 + rng.randf_range(-12.0, 12.0)
	var fwd: Vector3 = WorldCoords.heading_to_dir(yaw)
	var side := Vector3(-fwd.z, 0, fwd.x)
	var total: int = n_f + n_r
	var placed: int = 0
	for i in total:
		var is_ref: bool = i >= n_f
		var col: int = i % 3
		var row: int = i / 3
		var p: Vector3 = center + side * ((float(col) - 1.0) * (190.0 if not is_ref else 230.0)) + fwd * (float(row) * 200.0 - 60.0)
		if GroundKit.raw_y(p.x, p.z) < 2.0:
			continue
		var st: GroundStructure = GroundStructure.create("refinery" if is_ref else "factory", team, p, yaw + (0.0 if is_ref else 90.0 * float(rng.randi() % 2)))
		st.is_mission_target = false
		st.display_name = str(s["name"])
		container.add_child(st)
		placed += 1
	if placed > 0:
		var n88: int = 2 if team == "Axis" else 1
		_defences(container, center + fwd * 80.0, team, n88 + total / 4, 2 + total / 3, 1, 0, 420.0, hash(str(s["id"])) + 21)
	return container


func _register_targets() -> void:
	for t in loc.get("targets", []):
		var d: Dictionary = t
		var id: String = d["id"]
		var pos: Vector3 = _ll(d)
		var team: String = str(d.get("side_owner", "Axis"))
		_target_info[id] = {"id": id, "name": d.get("name", id), "type": d.get("type", ""), "team": team, "pos": pos, "data": d}
		var route: RoutePath = null
		if d.has("path"):
			route = RoutePath.from_latlon(d["path"])
		var act: float = 8500.0
		if route != null:
			act = 6000.0
		else:
			_exclude.append([pos, 160.0])
		var site: Dictionary = _add_site("tgt_" + id, pos, act, _build_target, {"id": id, "data": d, "team": team})
		if route != null:
			site["route"] = route


const COAST_STRIPS := [
	# [lat1, lon1, lat2, lon2, clusters, team]
	[50.98, 1.84, 50.74, 1.57, 5, "Axis"],       # Calais - Boulogne (Atlantic Wall)
	[50.70, 1.57, 50.15, 1.55, 6, "Axis"],       # Boulogne - Somme
	[50.05, 1.45, 49.93, 1.08, 3, "Axis"],       # Somme - Dieppe
	[49.90, 1.0, 49.50, 0.2, 5, "Axis"],         # Dieppe - Le Havre
	[49.4, -0.2, 49.35, -1.1, 4, "Axis"],        # Normandy (Calvados)
	[49.60, -1.60, 49.55, -1.2, 3, "Axis"],      # Cherbourg
	[51.30, 2.9, 51.10, 2.5, 4, "Axis"],         # Belgian coast
	[51.37, 1.40, 51.12, 1.30, 4, "Allies"],     # Kent coast
	[51.05, 1.15, 50.95, 0.7, 3, "Allies"],      # Romney - Hastings
	[50.78, 0.30, 50.78, -0.9, 5, "Allies"],     # Sussex
	[50.80, -1.20, 50.62, -2.0, 3, "Allies"],    # Hampshire / Dorset
]


## Atlantic Wall + British coast defences placed every few km along the real OSM coastline (coast.json).
## OSM coastlines run with land on the LEFT, so the sea is on the right of the direction of travel.
func _register_coast_defences() -> void:
	var idx: int = 0
	var placed: int = 0
	var f: FileAccess = FileAccess.open("res://data/osm/coast.json", FileAccess.READ)
	var src_ok: bool = false
	if f != null:
		var sj: FileAccess = FileAccess.open("res://data/osm/_source.json", FileAccess.READ)
		if sj != null:
			var sd: Variant = JSON.parse_string(sj.get_as_text())
			src_ok = sd is Dictionary and str((sd as Dictionary).get("coast", "")) == "overpass"
		var d: Variant = JSON.parse_string(f.get_as_text()) if src_ok else null
		if d is Dictionary:
			for l in (d as Dictionary).get("lines", []):
				var pts: Array = l.get("pts", [])
				if pts.size() < 2:
					continue
				var rp: RoutePath = RoutePath.from_latlon(pts)
				if rp.length < 6000.0:
					continue
				var team0: String = GroundKit.side_at(rp.sample(rp.length * 0.5))
				var step0: float = 3400.0 if team0 == "Axis" else 5200.0
				var s: float = step0 * 0.5
				while s < rp.length and placed < 320:
					var p: Vector3 = rp.sample(s)
					var t: Vector3 = rp.tangent(s)
					var sea: Vector3 = Vector3(-t.z, 0.0, t.x)           # right-hand side = open water
					var team: String = GroundKit.side_at(p)
					idx += 1
					placed += 1
					var land: Vector3 = p - sea * 40.0
					_exclude.append([land, 60.0])
					var site: Dictionary = _add_site("coast_%d" % idx, land, 5200.0, _build_coast_cluster, {"team": team, "sea": sea})
					s += step0
	if placed > 0:
		return
	for s in COAST_STRIPS:
		var n: int = int(s[4]) * 3
		for i in n:
			var t: float = (float(i) + 0.5) / float(n)
			var lat: float = lerpf(float(s[0]), float(s[2]), t)
			var lon: float = lerpf(float(s[1]), float(s[3]), t)
			var pos: Vector3 = WorldCoords.latlon_to_world(lat, lon)
			idx += 1
			_add_site("coast_%d" % idx, pos, 7000.0, _build_coast_cluster, {"team": str(s[5])})


func _register_osm_extras() -> void:
	# Towns and woodland now come from the real land cover (data/heightmap/region_landcover.bin) via
	# Scatter's tile streaming, so the synthetic OSM towns/woods fallback is no longer registered.
	pass


func _register_traffic() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var n: int = 0
	var rs: Array = [] if RoadMesh.has_roads() else TransportNetwork.roads.duplicate()
	for r in rs:
		var rp: RoutePath = r
		n += 1
		var mid: Vector3 = rp.sample(rp.length * 0.5)
		var s: Dictionary = _add_site("road_%d" % n, mid, 4200.0, _build_road_traffic, {"seed": n * 31 + 7})
		s["route"] = rp
		s["ambient"] = true
	n = 0
	var rails_sorted: Array = TransportNetwork.rails.duplicate()
	rails_sorted.sort_custom(func(a: RoutePath, b: RoutePath) -> bool: return a.length > b.length)
	if rails_sorted.size() > 70:
		rails_sorted.resize(70)
	for r in rails_sorted:
		var rp2: RoutePath = r
		n += 1
		var s2: Dictionary = _add_site("rail_%d" % n, rp2.sample(rp2.length * 0.5), 4800.0, _build_rail_traffic, {"seed": n * 53 + 3})
		s2["route"] = rp2
		s2["ambient"] = true
	n = 0
	for lane in TransportNetwork.sea_lanes:
		n += 1
		var lr: RoutePath = lane["route"]
		var s3: Dictionary = _add_site("lane_%d" % n, lr.sample(lr.length * 0.5), 5200.0, _build_sea_traffic, {"lane": lane, "seed": n * 17})
		s3["route"] = lr
		s3["ambient"] = true


# ================================================================== ports, camps, fishing
## Port type routing (3.3): size-1 harbours are fishing harbours, the three dockyards get the shipyard silhouette,
## the estuary / river harbours get a river quay, everything else stays the generic commercial/ferry port.
const DOCKYARD_PORTS := ["portsmouth", "sheerness", "cherbourg"]
const RIVER_QUAY_PORTS := ["honfleur", "etaples", "rye_harbour", "newhaven"]

func _register_ports() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for p in WorldFeatures.PORTS:
		var pos: Vector3 = WorldCoords.latlon_to_world(float(p[2]), float(p[3]))
		var size: int = int(p[5])
		var team: String = str(p[4])
		_exclude.append([pos, 160.0 + 60.0 * float(size)])
		RoadMesh.add_exclusion_disc(Vector2(pos.x, pos.z), 150.0 + 60.0 * float(size))
		_add_site("port_" + str(p[0]), pos, 6500.0 + 1000.0 * float(size), _build_port, {"name": str(p[1]), "size": size, "team": team, "id": str(p[0])})
		# fishing fleet working just off every harbour
		_register_sea_lane("fish_" + str(p[0]), pos, team, "fishing", 3500.0 + float(size) * 1500.0, rng)
	# coastal convoys (British east-west coastal traffic, German coastal traffic along the French / Belgian coast)
	var legs: Array = [
		["conv_thames_dover", 51.45, 0.75, 51.18, 1.50, "Allies", "coaster"],
		["conv_dover_portsmouth", 51.00, 1.45, 50.60, 0.05, "Allies", "coaster"],
		["conv_portsmouth_poole", 50.70, -1.05, 50.58, -1.95, "Allies", "coaster"],
		["conv_boulogne_dunkirk", 50.80, 1.50, 51.10, 2.25, "Axis", "coaster"],
		["conv_havre_cherbourg", 49.55, 0.10, 49.75, -1.45, "Axis", "coaster"],
		["conv_dieppe_havre", 49.95, 1.00, 49.55, 0.05, "Axis", "coaster"],
		["conv_ostend_zeebrugge", 51.30, 2.85, 51.45, 3.35, "Axis", "coaster"],
	]
	_register_channel_convoys()
	for m in WorldFeatures.SEA_MARKS:
		var mp: Vector3 = WorldCoords.latlon_to_world(float(m[2]), float(m[3]))
		_add_site("sea_" + str(m[0]), mp, 9000.0, _build_sea_mark, {"kind": str(m[4]), "name": str(m[1])})
	for l in legs:
		var a: Vector3 = WorldCoords.latlon_to_world(float(l[1]), float(l[2]))
		var b: Vector3 = WorldCoords.latlon_to_world(float(l[3]), float(l[4]))
		var rp: RoutePath = RoutePath.from_points(PackedVector3Array([a, a.lerp(b, 0.5), b]))
		var lane: Dictionary = {"id": str(l[0]), "team": str(l[5]), "comp": str(l[6]), "route": rp}
		var s3: Dictionary = _add_site(str(l[0]), rp.sample(rp.length * 0.5), 6000.0, _build_sea_traffic, {"lane": lane, "seed": 1})
		s3["route"] = rp
		s3["ambient"] = true


## Long-haul Channel convoys (the 1940 "Kanalkampf" targets): British CW (westbound) and CE (eastbound)
## convoys of colliers in two columns with escorts and barrage balloons, and German coastal convoys from
## Cherbourg to Ostend. Lanes follow the real routes a few miles offshore (waypoints checked against the
## heightmap). Each lane carries two convoys spaced far apart so one is usually in reach.
const CHANNEL_LANES := [
	["cw", "Allies", "channel", [[51.48, 0.95], [51.44, 1.50], [51.30, 1.53], [51.13, 1.48], [51.02, 1.32], [50.88, 1.05], [50.78, 0.80], [50.68, 0.35], [50.66, -0.20], [50.65, -0.75], [50.60, -1.00], [50.53, -1.12], [50.50, -1.35], [50.52, -1.95], [50.50, -2.45]]],
	["ce", "Allies", "channel", [[50.45, -2.40], [50.47, -1.90], [50.48, -1.30], [50.58, -0.80], [50.60, -0.20], [50.62, 0.35], [50.72, 0.85], [50.86, 1.18], [50.98, 1.42], [51.10, 1.58], [51.28, 1.62], [51.42, 1.62], [51.52, 1.05]]],
	["km", "Axis", "kriegsmarine", [[49.75, -1.55], [49.72, -1.10], [49.55, -0.40], [49.55, -0.05], [49.75, 0.20], [49.95, 0.70], [50.05, 1.20], [50.25, 1.45], [50.55, 1.50], [50.78, 1.49], [50.88, 1.49], [50.97, 1.62], [51.04, 1.85], [51.10, 2.20], [51.18, 2.60], [51.28, 2.88]]],
	["ec", "Allies", "channel", [[51.55, 1.60], [51.80, 1.95], [52.20, 2.15], [52.60, 2.20], [52.95, 2.00]]],
	["nl", "Axis", "kriegsmarine", [[51.45, 3.35], [51.80, 3.60], [52.10, 4.00], [52.45, 4.35], [52.85, 4.55]]],
]

func _register_channel_convoys() -> void:
	for l in CHANNEL_LANES:
		var pts := PackedVector3Array()
		for ll in l[3]:
			pts.append(WorldCoords.latlon_to_world(float(ll[0]), float(ll[1])))
		var rp: RoutePath = RoutePath.from_points(pts)
		for k in 2:
			var lane: Dictionary = {"id": "chan_%s_%d" % [l[0], k], "team": str(l[1]), "comp": str(l[2]), "route": rp, "phase": 0.5 * float(k)}
			var s: Dictionary = _add_site(String(lane["id"]), rp.sample(rp.length * 0.5), 12000.0, _build_channel_convoy, {"lane": lane})
			s["route"] = rp
			s["ambient"] = true


## A Channel convoy: the first of each lane streams in a few km along the lane from the player's nearest
## point (out of sight, so no pop-in), the second half a lane further on.
func _build_channel_convoy(s: Dictionary) -> Node3D:
	var container := Node3D.new()
	var lane: Dictionary = s["lane"]
	var rp: RoutePath = s["route"]
	var spd: float = 7.0
	var fp: Vector3 = focus.global_position if focus else Vector3.ZERO
	var near_s: float = rp.closest(fp).x
	var start: float = fposmod(near_s + 3500.0 + float(lane["phase"]) * rp.length, rp.length)
	var cv: Convoy = Convoy.create(str(lane["team"]), rp, true, str(lane["comp"]), start, spd)
	cv.display_name = "Channel convoy" if str(lane["team"]) == "Allies" else "Coastal convoy"
	container.add_child(cv)
	s["main"] = cv
	return container


func _build_sea_mark(s: Dictionary) -> Node3D:
	var container := Node3D.new()
	var kind: String = s["kind"]
	var n: Node3D = WorldFeatures.build_lightship() if kind == "lightship" else WorldFeatures.build_sea_fort(kind)
	var pos: Vector3 = s["pos"]
	n.position = Vector3(pos.x, 0.0, pos.z)
	n.rotation.y = float(hash(str(s["name"])) % 360) * PI / 180.0
	container.add_child(n)
	return container


func _register_sea_lane(id: String, port_pos: Vector3, team: String, comp: String, reach: float, rng: RandomNumberGenerator) -> void:
	# find open water near the harbour and run a lane out to sea and back along a gentle arc
	var sea: Vector3 = GroundKit.water_dir(port_pos, 900.0)
	if sea == Vector3.ZERO:
		return
	var side := Vector3(-sea.z, 0.0, sea.x)
	var a: Vector3 = port_pos + sea * 700.0
	var b: Vector3 = port_pos + sea * (reach * 0.6) + side * rng.randf_range(-1.0, 1.0) * reach * 0.5
	var c: Vector3 = port_pos + sea * reach + side * rng.randf_range(-1.0, 1.0) * reach * 0.8
	var pts := PackedVector3Array([a, b, c])
	# only keep it if the lane is really over water
	for q in pts:
		if not GroundKit.is_water(q.x, q.z):
			return
	var rp: RoutePath = RoutePath.from_points(pts)
	var lane: Dictionary = {"id": id, "team": team, "comp": comp, "route": rp}
	var s: Dictionary = _add_site("lane_" + id, rp.sample(rp.length * 0.5), 5200.0, _build_sea_traffic, {"lane": lane, "seed": 3})
	s["route"] = rp
	s["ambient"] = true


func _register_camps() -> void:
	for c in WorldFeatures.CAMPS:
		var pos: Vector3 = WorldCoords.latlon_to_world(float(c[2]), float(c[3]))
		var size: int = int(c[6])
		_exclude.append([pos, 190.0 + 55.0 * float(size)])
		RoadMesh.add_exclusion_disc(Vector2(pos.x, pos.z), 200.0 + 60.0 * float(size))
		_add_site("camp_" + str(c[0]), pos, 7500.0, _build_camp, {"name": str(c[1]), "team": str(c[4]), "kind": str(c[5]), "size": size, "id": str(c[0])})
		if str(c[5]) == "camp":
			var cr: float = 200.0 + 60.0 * float(size)
			_ground_zones.append({"pos": pos, "heading": 0.0, "half": Vector2(cr * 0.75, cr * 0.75), "feather": cr * 0.45, "kind": 2})


## The two Mulberry harbours (June 1944 on). Always registered; the builder decides from the war date what exists.
func _register_mulberries() -> void:
	for hid in MulberryKit.HARBOURS.keys():
		_add_site("mulberry_" + str(hid), MulberryKit.centre(str(hid)), 22000.0, func(s: Dictionary) -> Node3D: return MulberryKit.build(str(s["hid"])), {"hid": str(hid)})


## Battlefields, invasion beaches and airborne landing zones. Always registered (cheap); each builder checks the date.
func _register_war_ground() -> void:
	var d: Dictionary = WarGround.data()
	for r in d.get("battlefields", []):
		var rd: Dictionary = r
		_add_site("wg_" + str(rd["id"]), WarGround._pos(rd), 6000.0 + float(rd["rx"]), func(s: Dictionary) -> Node3D: return WarGround.build(s["row"], "battlefield"), {"row": rd})
	for r in d.get("beaches", []):
		var bd: Dictionary = r
		_add_site("wg_" + str(bd["id"]), WarGround._pos(bd), 6000.0 + float(bd["length"]) * 0.5, func(s: Dictionary) -> Node3D: return WarGround.build(s["row"], "beach"), {"row": bd})
	for r in GliderKit.rows():
		var gd: Dictionary = r
		var gp: Vector3 = WorldCoords.latlon_to_world(float(gd["lat"]), float(gd["lon"]))
		_add_site("lz_" + str(gd["id"]), gp, 5500.0 + float(gd.get("rx", 400.0)), func(s: Dictionary) -> Node3D: return GliderKit.build(s["row"]), {"row": gd})


## The Kammhuber Line (C4): the belt of searchlight boxes across the Netherlands and Belgium on the night bombers'
## route to the Ruhr, 1941-42 (the "Helle Nachtjagd": searchlights lit the bombers for the night fighters inside each
## box). The lights were withdrawn to the cities in late 1942. Sources: Wikipedia - Kammhuber Line.
const KAMMHUBER := [[52.95, 6.35], [52.65, 6.30], [52.35, 6.20], [52.05, 6.05], [51.75, 5.90], [51.45, 5.75], [51.15, 5.65], [50.85, 5.60]]


func _register_kammhuber() -> void:
	for i in KAMMHUBER.size() - 1:
		var a: Vector3 = WorldCoords.latlon_to_world(float(KAMMHUBER[i][0]), float(KAMMHUBER[i][1]))
		var b: Vector3 = WorldCoords.latlon_to_world(float(KAMMHUBER[i + 1][0]), float(KAMMHUBER[i + 1][1]))
		var n: int = maxi(int(a.distance_to(b) / 9000.0), 1)
		for k in n:
			var p: Vector3 = a.lerp(b, (float(k) + 0.5) / float(n))
			_add_site("kammhuber_%d_%d" % [i, k], p, 26000.0, _build_kammhuber, {})


func _build_kammhuber(s: Dictionary) -> Node3D:
	var c := Node3D.new()
	if EraClock.is_between("1941-01-01", "1942-12-31"):
		_defences(c, s["pos"], "Axis", 0, 0, 2, 0, 1800.0, hash(str(s["key"])))
	return c


## The 1944 invasion build-up (BuildupKit): marshalling areas, anchorages, Phoenix parks, embarkation hards.
func _register_buildup() -> void:
	var d: Dictionary = BuildupKit.data()
	for spec in [["marshalling", "marshalling", 4500.0], ["anchorages", "anchorage", 6000.0], ["phoenix_parks", "phoenix_park", 9000.0], ["hards", "hard", 5000.0]]:
		for r in d.get(str(spec[0]), []):
			var rd: Dictionary = r
			var act: float = float(spec[2]) + float(rd.get("radius_m", 0.0))
			_add_site("bu_" + str(rd["id"]), BuildupKit.pos(rd), act, func(s: Dictionary) -> Node3D: return BuildupKit.build(s["row"], str(s["bkind"])), {"row": rd, "bkind": str(spec[1])})


## Prisoner-of-war and labour camps (PowCampKit.CAMPS) at their real locations.
func _register_pow_camps() -> void:
	for c in PowCampKit.CAMPS:
		var style: String = str(c[5])
		var size: int = int(c[6])
		var pos: Vector3 = PowCampKit.flattest(WorldCoords.latlon_to_world(float(c[2]), float(c[3])), style, size)
		var r: float = PowCampKit.radius(style, size)
		if terrain != null:   # level the compound (the huts stood on level ground) with a gentle ramp out to the land
			terrain.call("add_flat_zone", pos, PowCampKit.extents(style, size).length() + 15.0, 220.0)
		_exclude.append([pos, r])
		RoadMesh.add_exclusion_disc(Vector2(pos.x, pos.z), r * 0.8)
		_ground_zones.append(PowCampKit.zone_for(str(c[0]), pos, style, size))
		_add_site("pow_" + str(c[0]), pos, 8000.0, _build_pow_camp, {"name": str(c[1]), "team": str(c[4]), "style": style, "size": size, "id": str(c[0])})
		var strip_id: String = EscapeStripKit.strip_for_camp(str(c[0]))
		if strip_id != "":
			_register_escape_strip(strip_id, str(c[0]), pos)
	GroundKit.lp("  _register_pow_camps (%d)" % PowCampKit.CAMPS.size())


## The rough landing strip near a camp (see EscapeStripKit): levelled ground and a rolled strip, kept clear of scatter.
func _register_escape_strip(strip_id: String, camp_id: String, camp_pos: Vector3) -> void:
	var pl: Dictionary = EscapeStripKit.plan(camp_pos)
	var pos: Vector3 = pl["pos"]
	if terrain != null:
		pos.y = float(terrain.call("add_flat_zone", pos, EscapeStripKit.LENGTH * 0.55, 200.0))
	else:
		pos.y = GroundKit.ground_y(pos.x, pos.z)
	var name_s: String = strip_id
	for st in EscapeStripKit.STRIPS:
		if str(st[0]) == strip_id:
			name_s = str(st[2])
	EscapeStripKit.placed[strip_id] = {"pos": pos, "heading": float(pl["heading"]), "camp": camp_pos, "camp_id": camp_id, "name": name_s}
	_exclude.append([pos, EscapeStripKit.KEEP_CLEAR])
	RoadMesh.add_exclusion_disc(Vector2(pos.x, pos.z), EscapeStripKit.KEEP_CLEAR * 0.8)
	_add_site("strip_" + strip_id, pos, 6000.0, func(s: Dictionary) -> Node3D: return EscapeStripKit.build(s["pos"], float(s["heading"])), {"heading": float(pl["heading"])})


func _build_pow_camp(s: Dictionary) -> Node3D:
	var pos: Vector3 = s["pos"]
	if GroundKit.raw_y(pos.x, pos.z) < 1.5:
		return Node3D.new()
	return PowCampKit.build(pos, str(s["id"]), str(s["style"]), int(s["size"]), str(s["team"]))


## Pick the nearest shoreline point to `pos` (used by both ports and docks) - the DEM coast can sit some way off.
var _shore_cache: Dictionary = {}     # site shore searches, by query: deterministic, so a revisited site rebuilds at once
var _shore_jobs: Dictionary = {}      # query -> [task id, [result]]
var _sync_build: bool = false         # warm-up / pinned builds need the answer now


## The shoreline search for a dock / port site, on a worker thread: it samples the height field a few hundred
## times (London's inland docks took ~200 ms on the main thread). Returns the result, or null while it is running
## (the site is retried next tick). Load screen, warm-up and pinned sites compute it at once.
func _shore_for(s: Dictionary, pos: Vector3, radius: float, count: int, seed_v: int) -> Variant:
	var key: String = "%d_%d_%d_%d_%d" % [roundi(pos.x), roundi(pos.z), roundi(radius), count, seed_v]
	if _shore_cache.has(key):
		return _shore_cache[key]
	if _shore_jobs.has(key):
		var j: Array = _shore_jobs[key]
		if not WorkerThreadPool.is_task_completed(int(j[0])) and not (boost or _sync_build or bool(s.get("pin", false))):
			return null
		WorkerThreadPool.wait_for_task_completion(int(j[0]))
		_shore_jobs.erase(key)
		_shore_cache[key] = (j[1] as Array)[0]
		return _shore_cache[key]
	if boost or _sync_build or bool(s.get("pin", false)):
		_shore_cache[key] = _nearest_shore(pos, radius, count, seed_v)
		return _shore_cache[key]
	var holder: Array = [{}]
	var tid: int = WorkerThreadPool.add_task(func() -> void: holder[0] = _nearest_shore(pos, radius, count, seed_v))
	_shore_jobs[key] = [tid, holder]
	return null


func _nearest_shore(pos: Vector3, radius: float, count: int, seed_v: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var shore: Array = Scatter.find_shore(pos, radius, count, rng)
	if shore.is_empty():
		return {}
	var best: Dictionary = shore[0]
	for sd in shore:
		if (sd["pos"] as Vector3).distance_to(pos) < (best["pos"] as Vector3).distance_to(pos):
			best = sd
	return best


func _build_port(s: Dictionary) -> Node3D:
	var pos: Vector3 = s["pos"]
	var id: String = str(s["id"])
	var size: int = int(s["size"])
	var team: String = str(s["team"])
	var seed_v: int = hash(id)
	# a harbour sits on the nearest shoreline: search for it (wide, the DEM coast can be some way off)
	var bv0: Variant = _shore_for(s, pos, 1200.0, 6, seed_v)
	if bv0 == null:
		s["defer"] = true
		return null
	var best: Dictionary = bv0
	if best.is_empty():
		return Node3D.new()
	# 3.3: branch by port type / size - estuary harbours get a river quay, size-1 ports a fishing harbour,
	# the dockyards the shipyard silhouette; everything else stays the generic commercial / ferry port.
	if id in RIVER_QUAY_PORTS:
		return WorldFeatures.build_river_quay(best["pos"], Vector3(-(best["sea"] as Vector3).z, 0.0, (best["sea"] as Vector3).x), size, team, seed_v)
	if size <= 1:
		return WorldFeatures.build_fishing_harbour(best["pos"], best["sea"], size, team, seed_v)
	if id in DOCKYARD_PORTS:
		return WorldFeatures.build_drydock_shipyard(best["pos"], best["sea"], maxi(size, 2), team, seed_v)
	return WorldFeatures.build_port(best["pos"], best["sea"], size, team, seed_v)


# ---- 1940s piers & docks (data/docks_1940.json): registered from _ready() alongside _register_ports() ----
var dock_sites: int = 0                          # how many pier/dock sites were registered (for debug reports)


func _register_docks() -> void:
	var f: FileAccess = FileAccess.open("res://data/docks_1940.json", FileAccess.READ)
	if f == null:
		push_warning("WorldPopulator: data/docks_1940.json missing")
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var n: int = 0
	for group in ["piers", "docks"]:
		for e in (d as Dictionary).get(group, []):
			var dd: Dictionary = e
			var id: String = str(dd.get("id", "dock_%d" % n))
			var kind: String = str(dd.get("kind", "basin"))
			var pos: Vector3 = WorldCoords.latlon_to_world(float(dd["lat"]), float(dd["lon"]))
			var size: int = int(dd.get("size", 2))
			var team: String = str(dd.get("team", GroundKit.side_at(pos)))
			_exclude.append([pos, 220.0 + 80.0 * float(size)])
			RoadMesh.add_exclusion_disc(Vector2(pos.x, pos.z), 200.0 + 80.0 * float(size))
			_add_site("dock_" + id, pos, 6500.0 + 1000.0 * float(size), _build_dock, {"id": id, "kind": kind, "size": size, "team": team, "name": str(dd.get("name", id))})
			n += 1
	dock_sites = n
	GroundKit.lp("  _register_docks (%d sites)" % n)


## Snap the site to its nearest shoreline point, then dispatch on `kind` to the typed WorldFeatures waterfront
## builders (3.1). Kinds are the data/docks_1940.json keys: pleasure_pier|harbour_pier|basin|lock|drydock|shipyard.
func _build_dock(s: Dictionary) -> Node3D:
	var pos: Vector3 = s["pos"]
	var seed_v: int = hash(str(s["id"]))
	var bv1: Variant = _shore_for(s, pos, 1400.0, 8, seed_v)
	if bv1 == null:
		s["defer"] = true
		return null
	var best: Dictionary = bv1
	if best.is_empty():
		return Node3D.new()
	var size: int = int(s["size"])
	var team: String = str(s["team"])
	match str(s["kind"]):
		"pleasure_pier":
			return WorldFeatures.build_pleasure_pier(best["pos"], best["sea"], size, team, seed_v)
		"harbour_pier":
			return WorldFeatures.build_port(best["pos"], best["sea"], maxi(size, 2), team, seed_v)
		"basin", "lock":
			return WorldFeatures.build_dock_basin(best["pos"], best["sea"], size, team, seed_v)
		"drydock", "shipyard":
			return WorldFeatures.build_drydock_shipyard(best["pos"], best["sea"], size, team, seed_v)
	return WorldFeatures.build_port(best["pos"], best["sea"], size, team, seed_v)


func _build_camp(s: Dictionary) -> Node3D:
	var pos: Vector3 = s["pos"]
	if GroundKit.raw_y(pos.x, pos.z) < 2.0:
		return Node3D.new()
	return WorldFeatures.build_camp(pos, str(s["kind"]), int(s["size"]), str(s["team"]), hash(str(s["id"])))


# ================================================================== P1 sea defences
## Sea defences (data/sea_defences_1940.json): buoyed mine lines, anti-submarine booms and nets, blockships,
## extra Maunsell/Grain sea forts, offshore beach obstacles, marked wrecks. Ambient mine-sweeping trawlers and
## boom-gate vessels work the swept channels off the ports (see SWEEP_LANES / _register_sweepers).
const SEA_DEFENCES_JSON := "res://data/sea_defences_1940.json"
var sea_defence_sites: int = 0
var sea_defence_km: float = 0.0


func _register_sea_defences() -> void:
	var f: FileAccess = FileAccess.open(SEA_DEFENCES_JSON, FileAccess.READ)
	if f == null:
		push_warning("WorldPopulator: %s missing" % SEA_DEFENCES_JSON)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var n: int = 0
	var km: float = 0.0
	for e in (d as Dictionary).get("sites", []):
		var dd: Dictionary = e
		var id: String = str(dd.get("id", "sd_%d" % n))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(dd["lat"]), float(dd["lon"]))
		var kind: String = str(dd.get("kind", "minefield"))
		var length_m: float = float(dd.get("length_m", 0.0))
		var rows: int = int(dd.get("rows", 1))
		var style: String = str(dd.get("style", ""))
		var heading: float = float(dd.get("heading_deg", 0.0))
		var team: String = str(dd.get("team", GroundKit.side_at(pos)))
		var act: float = 9000.0 if kind == "sea_fort" else 7000.0
		_add_site("sd_" + id, pos, act, _build_sea_defence,
			{"id": id, "kind": kind, "style": style, "length_m": length_m, "rows": rows, "heading_deg": heading, "team": team,
			"from": str(dd.get("from", "")), "to": str(dd.get("to", ""))})
		if kind in ["minefield", "boom", "obstacles"]:
			km += length_m
		n += 1
	sea_defence_sites = n
	sea_defence_km = km / 1000.0
	GroundKit.lp("  _register_sea_defences (%d sites, %.0f km spanned)" % [n, sea_defence_km])


## Builder for one sea-defence site: hands the kind to SeaDefenceKit, seeded from hash(id) for determinism.
func _build_sea_defence(s: Dictionary) -> Node3D:
	if not EraClock.is_between(str(s.get("from", "")), str(s.get("to", ""))):
		return Node3D.new()      # not there on this date (e.g. the Gooseberry blockships before June 1944)
	return SeaDefenceKit.build(str(s["kind"]), str(s["style"]), s["pos"], float(s["heading_deg"]), float(s["length_m"]), int(s["rows"]), hash(str(s["id"])))


## Mine-sweeping trawlers and boom-gate vessels: short ambient lanes off the real swept channels / harbour
## booms. [id, lat0, lon0, lat1, lon1, team, ship_type]
const SWEEP_LANES := [
	["sweep_dover", 51.06, 1.38, 51.12, 1.45, "Allies", "trawler"],
	["sweep_portsmouth", 50.72, -1.08, 50.66, -0.95, "Allies", "trawler"],
	["sweep_solent", 50.72, -1.45, 50.68, -1.30, "Allies", "trawler"],
	["sweep_thames", 51.52, 1.20, 51.62, 1.35, "Allies", "trawler"],
	["sweep_harwich", 51.86, 1.32, 51.94, 1.45, "Allies", "trawler"],
	["boomgate_portsmouth", 50.79, -1.10, 50.80, -1.05, "Allies", "fishing_boat"],
	["boomgate_thames", 51.46, 0.88, 51.45, 0.92, "Allies", "fishing_boat"],
]


func _register_sweepers() -> void:
	var n: int = 0
	for l in SWEEP_LANES:
		var a: Vector3 = WorldCoords.latlon_to_world(float(l[1]), float(l[2]))
		var b: Vector3 = WorldCoords.latlon_to_world(float(l[3]), float(l[4]))
		if not GroundKit.is_water(a.x, a.z) or not GroundKit.is_water(b.x, b.z):
			continue
		var rp: RoutePath = RoutePath.from_points(PackedVector3Array([a, a.lerp(b, 0.5), b]))
		var lane: Dictionary = {"id": str(l[0]), "team": str(l[5]), "comp": str(l[6]), "route": rp}
		var s: Dictionary = _add_site("sweep_" + str(l[0]), rp.sample(rp.length * 0.5), 5200.0, _build_sweeper, {"lane": lane, "seed": n * 29 + 11})
		s["route"] = rp
		s["ambient"] = true
		n += 1
	GroundKit.lp("  _register_sweepers (%d lanes)" % n)


func _build_sweeper(s: Dictionary) -> Node3D:
	var container := Node3D.new()
	var lane: Dictionary = s["lane"]
	var rp: RoutePath = s["route"]
	var fp: Vector3 = focus.global_position if focus else Vector3.ZERO
	var c: Vector2 = rp.closest(fp)
	var sh: GroundShip = GroundShip.create(str(lane["comp"]), str(lane["team"]), rp, c.x, 5.0)
	container.add_child(sh)
	s["main"] = sh
	return container


# ================================================================== P2 city balloon barrages
## P2: barrage-balloon plan for a city, scaled by size and deterministic from hash(id) - rings of balloons
## around the town with ground winch sites. Returns [{pos: Vector3 (world), altitude: float (world units)}].
## Pure (no nodes), so the headless test and --balloon-test can call it without a scene.
static func city_balloon_plan(center: Vector3, id: String, size: int, radius: float) -> Array:
	var n: int = city_balloon_count(id, size)
	if n <= 0:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + 31
	var alt_m: float = 600.0 + float(clampi(size, 1, 5) - 1) * 220.0
	if id == "london":
		alt_m = 1500.0
	var altitude: float = alt_m * WorldCoords.VERTICAL_SCALE
	var rings: int = clampi(1 + size / 2, 1, 3)
	var out: Array = []
	for i in n:
		var ring: int = i % rings
		var r: float = radius * (0.55 + 0.45 * float(ring) / float(maxi(rings - 1, 1)))
		var a: float = TAU * float(i) / float(n) + rng.randf_range(-0.05, 0.05)
		var p: Vector3 = Vector3(center.x + cos(a) * r, 0.0, center.z + sin(a) * r)
		out.append({"pos": p, "altitude": altitude * rng.randf_range(0.85, 1.15)})
	return out


## P2: how many balloons a city's barrage flies. Scaled by size 1-5; London and the Thames/Medway estuary
## towns and the major ports get a denser apron. Pure - safe for the headless test.
static func city_balloon_count(id: String, size: int) -> int:
	var n: int = 4 + clampi(size, 1, 5) * 4
	if id == "london":
		n = 96
	elif id in ["portsmouth", "southampton", "dover", "plymouth", "chatham", "sheerness", "harwich", "gravesend"]:
		n = n * 2 + 6
	return n


## P2: lay the barrage around a city: the planned balloons on their cables plus a ground winch site each.
func _balloon_barrage(parent: Node3D, center: Vector3, id: String, size: int, radius: float, team: String) -> int:
	if team != "Allies" and size < 4:
		return 0                                       # the Luftwaffe flew only a thin local barrage in the Reich
	var plan: Array = city_balloon_plan(center, id, size, radius)
	var n: int = 0
	for e in plan:
		var d: Dictionary = e
		var p: Vector3 = d["pos"]
		if GroundKit.raw_y(p.x, p.z) < 0.6:
			continue                                   # never over water
		var bb: BarrageBalloon = BarrageBalloon.create(team, float(d["altitude"]))
		bb.position = Vector3(p.x, _y(p) + bb.altitude, p.z)
		parent.add_child(bb)
		_winch_site(parent, p, team)
		n += 1
	return n


## A ballon's ground winch site: a sandbagged emplacement with the winch and cable drum.
func _winch_site(parent: Node3D, p: Vector3, team: String) -> void:
	var gy: float = _y(p)
	var khaki: Color = Color(0.42, 0.4, 0.28) if team == "Allies" else Color(0.4, 0.4, 0.36)
	GroundKit.box(parent, Vector3(5.0, 2.2, 5.0), Vector3(p.x, gy + 1.1, p.z), khaki)
	GroundKit.cyl(parent, 0.7, 0.9, 2.4, Vector3(p.x + 3.6, gy + 1.2, p.z), GroundKit.COL_STEEL, Vector3.ZERO, 8)
	GroundKit.box(parent, Vector3(6.4, 0.8, 6.4), Vector3(p.x, gy + 0.4, p.z), GroundKit.COL_SAND, Vector3.ZERO, false)


# ================================================================== P3 dams (Dam Busters)
## Dam Busters targets (data/dams_1940.json): the Möhne, Eder, Sorpe, Ennepe, Lister and Diemel. Each is a
## destructible GroundStructure("dam") mission target with DamKit scenery (reservoir, spillway apron,
## powerhouse, anti-torpedo nets) around it. The Upkeep weapon and the Chastise mission are a separate
## follow-on phase (P3b) - this delivers the places and the targets only.
const DAMS_JSON := "res://data/dams_1940.json"
var dam_sites: int = 0


func _register_dams() -> void:
	var f: FileAccess = FileAccess.open(DAMS_JSON, FileAccess.READ)
	if f == null:
		push_warning("WorldPopulator: %s missing" % DAMS_JSON)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var n: int = 0
	for e in (d as Dictionary).get("dams", []):
		var dd: Dictionary = e
		var id: String = str(dd.get("id", "dam_%d" % n))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(dd["lat"]), float(dd["lon"]))
		var team: String = str(dd.get("team", "Axis"))
		_exclude.append([pos, 900.0])
		_target_info[id] = {"id": id, "name": str(dd.get("name", id)), "type": "dam", "team": team, "pos": pos, "data": dd}
		_add_site("dam_" + id, pos, 12000.0, _build_dam, {"id": id, "data": dd, "team": team})
		n += 1
	dam_sites = n
	GroundKit.lp("  _register_dams (%d dams)" % n)


## The live destructible wall of a dam site (null until it has been streamed in).
func dam_wall(id: String) -> Node:
	if not _site_by_key.has("dam_" + id):
		return null
	var s: Dictionary = _site_by_key["dam_" + id]
	return s["main"] if s.get("main") != null and is_instance_valid(s["main"]) else null


## Forget a dam's breached state so the next sortie starts with an intact wall.
func reset_dam(id: String) -> void:
	_destroyed.erase(id)


## Build one dam: DamKit scenery (reservoir, powerhouse, spillway apron, nets) plus the destructible wall.
func _build_dam(s: Dictionary) -> Node3D:
	var container := Node3D.new()
	var id: String = str(s["id"])
	var dd: Dictionary = s["data"]
	var team: String = str(s["team"])
	var pos: Vector3 = s["pos"]
	var heading: float = float(dd.get("heading_deg", 0.0))
	var scenery: Node3D = DamKit.build(id)
	if scenery != null:
		container.add_child(scenery)
	var wrecked: bool = _destroyed.has(id)
	var st: GroundStructure = GroundStructure.create("dam", team, pos, heading)
	st.target_id = id
	st.display_name = str(dd.get("name", id))
	st.is_mission_target = true
	st.start_wrecked = wrecked
	st.destroyed.connect(func(_n: Node, _k: Node) -> void: _destroyed[id] = true)
	container.add_child(st)
	s["main"] = st
	if not wrecked:
		_defences(container, pos, team, 2, 2, 1, 0, 260.0, hash(id) + 7)
	return container


# ================================================================== P4 decoy sites
## Starfish / QF / Q / K bombing-decoys (data/decoys_1940.json). Scenery from DecoyKit plus a destructible
## GroundStructure("decoy") target, registered in _target_info with type "decoy" and exposed by
## raid_targets() - so an Axis raid CAN be wasted on one.
const DECOYS_JSON := "res://data/decoys_1940.json"
var decoy_sites: int = 0


func _register_decoys() -> void:
	var f: FileAccess = FileAccess.open(DECOYS_JSON, FileAccess.READ)
	if f == null:
		push_warning("WorldPopulator: %s missing" % DECOYS_JSON)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var n: int = 0
	for e in (d as Dictionary).get("sites", []):
		var dd: Dictionary = e
		var id: String = str(dd.get("id", "decoy_%d" % n))
		var pos: Vector3 = _ll(dd)
		var team: String = str(dd.get("team", "Allies"))
		var kind: String = str(dd.get("kind", "q_site"))
		var size: int = int(dd.get("size", 1))
		_exclude.append([pos, 180.0 + 60.0 * float(size)])
		_target_info[id] = {"id": id, "name": str(dd.get("name", id)), "type": "decoy", "team": team, "pos": pos, "data": dd}
		_add_site("decoy_" + id, pos, 9000.0, _build_decoy,
			{"id": id, "data": dd, "team": team, "kind": kind, "size": size})
		n += 1
	decoy_sites = n
	GroundKit.lp("  _register_decoys (%d decoy sites)" % n)


## Build one decoy: DecoyKit scenery (fires/lights/dummy airfield) plus the destructible decoy "target".
func _build_decoy(s: Dictionary) -> Node3D:
	var id: String = str(s["id"])
	var dd: Dictionary = s["data"]
	var team: String = str(s["team"])
	var pos: Vector3 = s["pos"]
	var kind: String = str(s["kind"])
	var size: int = int(s["size"])
	var heading: float = float(dd.get("heading_deg", 0.0))
	var container := Node3D.new()
	container.add_child(DecoyKit.build(kind, pos, heading, size, hash(id)))
	var wrecked: bool = _destroyed.has(id)
	var st: GroundStructure = GroundStructure.create("decoy", team, pos, heading)
	st.target_id = id
	st.display_name = str(dd.get("name", id))
	st.is_mission_target = true
	st.start_wrecked = wrecked
	st.destroyed.connect(func(_n: Node, _k: Node) -> void: _destroyed[id] = true)
	container.add_child(st)
	s["main"] = st
	return container


# ================================================================== P7 railway drama
## Famous viaducts and tunnels (data/rail_drama_1940.json) at their real, cited positions. The great majority of
## the programme's viaducts and tunnels are DERIVED from the terrain per tile by RailKit.build_tile (see
## _finish_tile/_make_tile); this registers the curated catalogue as streamed scenery sites.
const RAIL_DRAMA_JSON := "res://data/rail_drama_1940.json"
var rail_drama_sites: int = 0


func _register_rail_drama() -> void:
	var f: FileAccess = FileAccess.open(RAIL_DRAMA_JSON, FileAccess.READ)
	if f == null:
		push_warning("WorldPopulator: %s missing" % RAIL_DRAMA_JSON)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var n: int = 0
	for e in (d as Dictionary).get("sites", []):
		var dd: Dictionary = e
		var id: String = str(dd.get("id", "rail_%d" % n))
		var pos: Vector3 = _ll(dd)
		_exclude.append([pos, 260.0])
		_add_site("raildrama_" + id, pos, 9500.0, _build_rail_drama, {"id": id, "data": dd})
		n += 1
	rail_drama_sites = n
	GroundKit.lp("  _register_rail_drama (%d structures)" % n)


## Build one curated rail-drama structure (a named viaduct/tunnel) via RailKit's catalogue builder.
func _build_rail_drama(s: Dictionary) -> Node3D:
	return RailKit.build_catalog(s["data"])


# ================================================================== P9 oil and fuel
## Real tank farms, refineries, petrol depots and gas holders (data/oil_fuel_1940.json). Each is a destructible
## GroundStructure (reusing the refinery / oil_depot / gasworks kinds) with OilFuelKit scenery around it,
## registered in _target_info with type "oil" so the Oil Campaign can raid it.
const OIL_FUEL_JSON := "res://data/oil_fuel_1940.json"
var oil_fuel_sites: int = 0


func _register_oil_fuel() -> void:
	var f: FileAccess = FileAccess.open(OIL_FUEL_JSON, FileAccess.READ)
	if f == null:
		push_warning("WorldPopulator: %s missing" % OIL_FUEL_JSON)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var n: int = 0
	for e in (d as Dictionary).get("sites", []):
		var dd: Dictionary = e
		var id: String = str(dd.get("id", "oil_%d" % n))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(dd["lat"]), float(dd["lon"]))
		if not WorldCoords.is_in_bounds(pos):
			continue
		var team: String = str(dd.get("team", GroundKit.side_at(pos)))
		var size: int = int(dd.get("size", 2))
		var kind: String = str(dd.get("kind", "oil_depot"))
		_exclude.append([pos, 260.0 + 90.0 * float(size)])
		RoadMesh.add_exclusion_disc(Vector2(pos.x, pos.z), 240.0 + 80.0 * float(size))
		_target_info[id] = {"id": id, "name": str(dd.get("name", id)), "type": "oil", "team": team, "pos": pos, "data": dd}
		_add_site("oil_" + id, pos, 9000.0, _build_oil_fuel, {"id": id, "data": dd, "team": team, "kind": kind, "size": size})
		n += 1
	oil_fuel_sites = n
	GroundKit.lp("  _register_oil_fuel (%d sites)" % n)


## The destructible GroundStructure kind a scenery kind reuses.
static func _oil_structure_kind(kind: String) -> String:
	match kind:
		"gasworks", "gas_holder":
			return "gasworks"
		"refinery":
			return "refinery"
		_:
			return "oil_depot"


## Build one oil/fuel site: OilFuelKit scenery plus its destructible GroundStructure.
func _build_oil_fuel(s: Dictionary) -> Node3D:
	var container := Node3D.new()
	var id: String = str(s["id"])
	var dd: Dictionary = s["data"]
	var team: String = str(s["team"])
	var kind: String = str(s["kind"])
	var size: int = int(s["size"])
	var pos: Vector3 = s["pos"]
	var heading: float = float(dd.get("heading_deg", _oil_heading(pos, id)))
	var scenery: Node3D = OilFuelKit.build(kind, pos, heading, size, team, hash(id))
	if scenery != null:
		container.add_child(scenery)
	var wrecked: bool = _destroyed.has(id)
	var st: GroundStructure = GroundStructure.create(_oil_structure_kind(kind), team, pos, heading)
	st.target_id = id
	st.display_name = str(dd.get("name", id))
	st.is_mission_target = true
	st.start_wrecked = wrecked
	st.destroyed.connect(func(_n: Node, _k: Node) -> void: _destroyed[id] = true)
	container.add_child(st)
	s["main"] = st
	if not wrecked and size >= 3:
		_defences(container, pos, team, 2 if team == "Axis" else 1, 2, 1, 0, 320.0, hash(id) + 13)
	return container


## Face the site towards the nearest open water (the refineries sat on the water) or the nearest rail; else a
## deterministic heading from the id.
func _oil_heading(pos: Vector3, id: String) -> float:
	var wd: Vector3 = GroundKit.water_dir(pos, 1200.0)
	if wd != Vector3.ZERO:
		return WorldCoords.dir_to_heading(wd)
	var rail: Dictionary = _nearest_rail(pos)
	if not rail.is_empty():
		var d: Vector3 = (rail["point"] as Vector3) - pos
		if Vector2(d.x, d.z).length() > 2.0:
			return WorldCoords.dir_to_heading(d)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + 17
	return rng.randf() * 360.0


# ================================================================== P10 aircraft industry
## The real 1940 aircraft plants and shadow factories plus dispersed production and storage sites
## (data/aircraft_industry_1940.json). Each is a destructible GroundStructure("factory") with AircraftIndustryKit
## scenery around it, registered in _target_info with type "aircraft" so a raid can be sent against the industry.
const AIRCRAFT_INDUSTRY_JSON := "res://data/aircraft_industry_1940.json"
var aircraft_industry_sites: int = 0


func _register_aircraft_industry() -> void:
	var f: FileAccess = FileAccess.open(AIRCRAFT_INDUSTRY_JSON, FileAccess.READ)
	if f == null:
		push_warning("WorldPopulator: %s missing" % AIRCRAFT_INDUSTRY_JSON)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var n: int = 0
	for e in (d as Dictionary).get("sites", []):
		var dd: Dictionary = e
		var id: String = str(dd.get("id", "air_%d" % n))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(dd["lat"]), float(dd["lon"]))
		if not WorldCoords.is_in_bounds(pos):
			continue
		var team: String = str(dd.get("team", GroundKit.side_at(pos)))
		var size: int = int(dd.get("size", 2))
		var kind: String = str(dd.get("kind", "assembly_plant"))
		_exclude.append([pos, 300.0 + 110.0 * float(size)])
		RoadMesh.add_exclusion_disc(Vector2(pos.x, pos.z), 280.0 + 100.0 * float(size))
		_target_info[id] = {"id": id, "name": str(dd.get("name", id)), "type": "aircraft", "team": team, "pos": pos, "data": dd}
		_add_site("aircraft_" + id, pos, 9000.0, _build_aircraft_industry, {"id": id, "data": dd, "team": team, "kind": kind, "size": size})
		n += 1
	aircraft_industry_sites = n
	GroundKit.lp("  _register_aircraft_industry (%d sites)" % n)


## Build one aircraft-industry site: AircraftIndustryKit scenery plus its destructible GroundStructure("factory").
func _build_aircraft_industry(s: Dictionary) -> Node3D:
	var container := Node3D.new()
	var id: String = str(s["id"])
	var dd: Dictionary = s["data"]
	var team: String = str(s["team"])
	var kind: String = str(s["kind"])
	var size: int = int(s["size"])
	var pos: Vector3 = s["pos"]
	var heading: float = float(dd.get("heading_deg", _oil_heading(pos, id)))
	var scenery: Node3D = AircraftIndustryKit.build(kind, pos, heading, size, team, hash(id))
	if scenery != null:
		container.add_child(scenery)
	var wrecked: bool = _destroyed.has(id)
	var st: GroundStructure = GroundStructure.create("factory", team, pos, heading)
	st.target_id = id
	st.display_name = str(dd.get("name", id))
	st.is_mission_target = true
	st.start_wrecked = wrecked
	st.destroyed.connect(func(_n: Node, _k: Node) -> void: _destroyed[id] = true)
	container.add_child(st)
	s["main"] = st
	if not wrecked and size >= 3:
		_defences(container, pos, team, 2 if team == "Axis" else 1, 2, 1, 0, 340.0, hash(id) + 19)
	_camouflage_industry(container, pos, heading, size, hash(id) + 43)      # P15 camouflage-painted factory roof
	return container


# ================================================================== P11 V-weapons
## The 1944 V-1 ski sites, the V-1 storage/preparation depots, and the two Pas-de-Calais "Heavy Cross" V-2
## bunkers (Wizernes / La Coupole and Eperlecques / Kraftwerk Nord West) at their cited sites in
## data/v_weapons_1940.json. Each is a destructible GroundStructure("v1_site") - the ramp branch, or the big
## dome variant for a Heavy Cross bunker - with VWeaponsKit scenery around it, registered in _target_info with
## type "v1_site" (already a raid-target type) so a Crossbow raid can be sent against them.
const V_WEAPONS_JSON := "res://data/v_weapons_1940.json"
var v_weapon_sites: int = 0


func _register_v_weapons() -> void:
	var f: FileAccess = FileAccess.open(V_WEAPONS_JSON, FileAccess.READ)
	if f == null:
		push_warning("WorldPopulator: %s missing" % V_WEAPONS_JSON)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var n: int = 0
	for e in (d as Dictionary).get("sites", []):
		var dd: Dictionary = e
		var id: String = str(dd.get("id", "vweap_%d" % n))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(dd["lat"]), float(dd["lon"]))
		if not WorldCoords.is_in_bounds(pos):
			continue
		var team: String = str(dd.get("team", "Axis"))
		var size: int = int(dd.get("size", 2))
		var kind: String = str(dd.get("kind", "ski_site"))
		_exclude.append([pos, 240.0 + 90.0 * float(size)])
		RoadMesh.add_exclusion_disc(Vector2(pos.x, pos.z), 220.0 + 80.0 * float(size))
		_target_info[id] = {"id": id, "name": str(dd.get("name", id)), "type": "v1_site", "team": team, "pos": pos, "data": dd}
		_add_site("vweap_" + id, pos, 9000.0, _build_v_weapons, {"id": id, "data": dd, "team": team, "kind": kind, "size": size})
		n += 1
	v_weapon_sites = n
	GroundKit.lp("  _register_v_weapons (%d sites)" % n)


## Build one V-weapon site: VWeaponsKit scenery plus its destructible GroundStructure("v1_site") target.
func _build_v_weapons(s: Dictionary) -> Node3D:
	var container := Node3D.new()
	var id: String = str(s["id"])
	var dd: Dictionary = s["data"]
	var team: String = str(s["team"])
	var kind: String = str(s["kind"])
	var size: int = int(s["size"])
	var pos: Vector3 = s["pos"]
	var heading: float = float(dd.get("heading_deg", _oil_heading(pos, id)))
	var scenery: Node3D = VWeaponsKit.build(kind, pos, heading, size, team, hash(id))
	if scenery != null:
		container.add_child(scenery)
	var wrecked: bool = _destroyed.has(id)
	var st: GroundStructure = GroundStructure.create("v1_site", team, pos, heading)
	if kind == "heavy_cross":
		st.variant = "dome"
	st.target_id = id
	st.display_name = str(dd.get("name", id))
	st.is_mission_target = true
	st.start_wrecked = wrecked
	st.destroyed.connect(func(_n: Node, _k: Node) -> void: _destroyed[id] = true)
	container.add_child(st)
	s["main"] = st
	if not wrecked and size >= 2:
		_defences(container, pos, team, 2, 1, 0, 0, 200.0, hash(id) + 23)
	return container


# ================================================================== P12 port clutter
## Cranes, lock gates, dredgers, hopper barges, tugs, paddle steamers and the Dover-Dunkerque train ferries at
## the real ports and dock sites (data/port_clutter_1940.json). Non-destructible scenery + moored/working
## GroundShip hulls. The two train-ferry terminals also lay a moving ferry across the Channel (see
## _register_train_ferry_lane).
const PORT_CLUTTER_JSON := "res://data/port_clutter_1940.json"
var port_clutter_sites: int = 0
var _ferry_terminals: Array = []


func _register_port_clutter() -> void:
	var f: FileAccess = FileAccess.open(PORT_CLUTTER_JSON, FileAccess.READ)
	if f == null:
		push_warning("WorldPopulator: %s missing" % PORT_CLUTTER_JSON)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var n: int = 0
	_ferry_terminals.clear()
	for e in (d as Dictionary).get("sites", []):
		var dd: Dictionary = e
		var id: String = str(dd.get("id", "pc_%d" % n))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(dd["lat"]), float(dd["lon"]))
		if not WorldCoords.is_in_bounds(pos):
			continue
		var team: String = str(dd.get("team", GroundKit.side_at(pos)))
		var size: int = int(dd.get("size", 2))
		var kind: String = str(dd.get("kind", "crane"))
		_exclude.append([pos, 170.0 + 55.0 * float(size)])
		RoadMesh.add_exclusion_disc(Vector2(pos.x, pos.z), 120.0 + 40.0 * float(size))
		_add_site("pc_" + id, pos, 7000.0, _build_port_clutter, {"id": id, "data": dd, "team": team, "kind": kind, "size": size})
		if kind == "train_ferry":
			_ferry_terminals.append(pos)
		n += 1
	port_clutter_sites = n
	_register_train_ferry_lane()
	GroundKit.lp("  _register_port_clutter (%d sites)" % n)


## The Dover-Dunkerque train-ferry crossing: a moving GroundShip("ferry") shuttling between the two terminals
## recorded in data/port_clutter_1940.json.
func _register_train_ferry_lane() -> void:
	if _ferry_terminals.size() < 2:
		return
	var a: Vector3 = _ferry_terminals[0]
	var b: Vector3 = _ferry_terminals[1]
	var mid: Vector3 = a.lerp(b, 0.5)
	if not GroundKit.is_water(mid.x, mid.z):
		return
	var rp: RoutePath = RoutePath.from_points(PackedVector3Array([a, mid, b]))
	var lane: Dictionary = {"id": "train_ferry_dover_dunkerque", "team": "Allies", "comp": "ferry", "route": rp}
	var s: Dictionary = _add_site("pc_ferry_lane", rp.sample(rp.length * 0.5), 11000.0, _build_port_ferry, {"lane": lane, "seed": 1})
	s["route"] = rp
	s["ambient"] = true


## Build one port-clutter site: snap to the nearest shore and hand the kind to PortClutterKit.
func _build_port_clutter(s: Dictionary) -> Node3D:
	var pos: Vector3 = s["pos"]
	var seed_v: int = hash(str(s["id"]))
	var bv2: Variant = _shore_for(s, pos, 1500.0, 8, seed_v)
	if bv2 == null:
		s["defer"] = true
		return null
	var best: Dictionary = bv2
	if best.is_empty():
		return Node3D.new()
	return PortClutterKit.build(str(s["kind"]), best["pos"], best["sea"], int(s["size"]), str(s["team"]), seed_v)


## Build the moving train ferry (a GroundShip("ferry") working the Dover-Dunkerque lane), as _build_sweeper.
func _build_port_ferry(s: Dictionary) -> Node3D:
	var container := Node3D.new()
	var lane: Dictionary = s["lane"]
	var rp: RoutePath = s["route"]
	var fp: Vector3 = focus.global_position if focus else Vector3.ZERO
	var c: Vector2 = rp.closest(fp)
	var sh: GroundShip = GroundShip.create(str(lane["comp"]), str(lane["team"]), rp, c.x, -1.0)
	container.add_child(sh)
	s["main"] = sh
	return container


# ================================================================== P13 rural / Kentish texture
## Oast houses and hop gardens, orchards, market gardens, drainage windpumps and sheep folds
## (data/rural_1940.json): the distinctive 1940s Kentish / Channel-coast farming look. Non-destructible scenery.
const RURAL_JSON := "res://data/rural_1940.json"
var rural_sites: int = 0


func _register_rural() -> void:
	var f: FileAccess = FileAccess.open(RURAL_JSON, FileAccess.READ)
	if f == null:
		push_warning("WorldPopulator: %s missing" % RURAL_JSON)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var n: int = 0
	for e in (d as Dictionary).get("sites", []):
		var dd: Dictionary = e
		var id: String = str(dd.get("id", "rural_%d" % n))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(dd["lat"]), float(dd["lon"]))
		if not WorldCoords.is_in_bounds(pos):
			continue
		var size: int = int(dd.get("size", 1))
		_exclude.append([pos, 140.0 + 50.0 * float(size)])
		RoadMesh.add_exclusion_disc(Vector2(pos.x, pos.z), 120.0 + 40.0 * float(size))
		_add_site("rural_" + id, pos, 6800.0, _build_rural,
			{"id": id, "kind": str(dd.get("kind", "oast_house")), "size": size, "heading_deg": float(dd.get("heading_deg", 0.0))})
		n += 1
	rural_sites = n
	GroundKit.lp("  _register_rural (%d sites)" % n)


## Build one rural site via RuralKit, seeded from hash(id) for determinism.
func _build_rural(s: Dictionary) -> Node3D:
	var id: String = str(s["id"])
	var pos: Vector3 = s["pos"]
	return RuralKit.build(str(s["kind"]), pos, float(s.get("heading_deg", 0.0)), int(s.get("size", 1)), hash(id))


# ================================================================== P14 coastal / seaside landmarks
## Martello towers, coastguard and RNLI lifeboat stations, lidos, bandstands and requisitioned holiday camps
## (data/coastal_landmarks_1940.json): real, cited seaside landmarks built by the new landmarks.gd build() ids.
## Non-destructible scenery, placed at the real position and draped on the terrain.
const COASTAL_LANDMARKS_JSON := "res://data/coastal_landmarks_1940.json"
var coastal_landmark_sites: int = 0


func _register_coastal_landmarks() -> void:
	var f: FileAccess = FileAccess.open(COASTAL_LANDMARKS_JSON, FileAccess.READ)
	if f == null:
		push_warning("WorldPopulator: %s missing" % COASTAL_LANDMARKS_JSON)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var n: int = 0
	for e in (d as Dictionary).get("sites", []):
		var dd: Dictionary = e
		var id: String = str(dd.get("id", "coast_lm_%d" % n))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(dd["lat"]), float(dd["lon"]))
		if not WorldCoords.is_in_bounds(pos):
			continue
		var size: int = int(dd.get("size", 1))
		_exclude.append([pos, 130.0 + 50.0 * float(size)])
		RoadMesh.add_exclusion_disc(Vector2(pos.x, pos.z), 110.0 + 40.0 * float(size))
		_add_site("coastlm_" + id, pos, 6600.0 + 400.0 * float(size), _build_coastal_landmark,
			{"id": id, "kind": str(dd.get("kind", "martello_tower")), "size": size})
		n += 1
	coastal_landmark_sites = n
	GroundKit.lp("  _register_coastal_landmarks (%d sites)" % n)


## Build one coastal landmark: the new landmarks.gd id, placed at the real position on the ground, with a
## deterministic heading from hash(id). Non-destructible scenery.
func _build_coastal_landmark(s: Dictionary) -> Node3D:
	var container := Node3D.new()
	var id: String = str(s["id"])
	var n: Node3D = Landmarks.build(str(s["kind"]))
	if n == null:
		return container
	var pos: Vector3 = s["pos"]
	n.position = Vector3(pos.x, _y(pos), pos.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	n.rotation.y = rng.randf() * TAU
	container.add_child(n)
	return container


# ================================================================== P15 civil defence
## Public surface shelters, Anderson garden shelters, ARP / wardens' posts and sandbagged buildings
## (data/civil_defence_1940.json), plus camouflage-painted factory roofs driven off the existing industry and
## aircraft-industry sites (see _camouflage_industry). Non-destructible scenery.
const CIVIL_DEFENCE_JSON := "res://data/civil_defence_1940.json"
var civil_defence_sites: int = 0


func _register_civil_defence() -> void:
	var f: FileAccess = FileAccess.open(CIVIL_DEFENCE_JSON, FileAccess.READ)
	if f == null:
		push_warning("WorldPopulator: %s missing" % CIVIL_DEFENCE_JSON)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var n: int = 0
	for e in (d as Dictionary).get("sites", []):
		var dd: Dictionary = e
		var id: String = str(dd.get("id", "cd_%d" % n))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(dd["lat"]), float(dd["lon"]))
		if not WorldCoords.is_in_bounds(pos):
			continue
		var size: int = int(dd.get("size", 1))
		_exclude.append([pos, 110.0 + 40.0 * float(size)])
		RoadMesh.add_exclusion_disc(Vector2(pos.x, pos.z), 90.0 + 30.0 * float(size))
		_add_site("cd_" + id, pos, 6300.0, _build_civil_defence,
			{"id": id, "kind": str(dd.get("kind", "surface_shelter")), "size": size})
		n += 1
	civil_defence_sites = n
	GroundKit.lp("  _register_civil_defence (%d sites)" % n)


## Build one civil-defence site via CivilDefenceKit, seeded from hash(id) for determinism.
func _build_civil_defence(s: Dictionary) -> Node3D:
	var id: String = str(s["id"])
	var pos: Vector3 = s["pos"]
	return CivilDefenceKit.build(str(s["kind"]), pos, float(hash(id) % 360), int(s.get("size", 1)), hash(id))


## Camouflage-painted factory roofs (P15): a disruptive CVD paint pattern laid over a works footprint, driven
## off an existing industry / aircraft-industry site (its centre, yaw, size and a seed). Added to the site node.
func _camouflage_industry(container: Node3D, pos: Vector3, heading: float, size: int, seed_v: int) -> void:
	container.add_child(CivilDefenceKit.camouflage_roof(pos, heading, size, seed_v))


# ================================================================== P16 aviation support
## Seaplane / flying-boat stations (the Sunderland bases), airship / blimp mooring stations and kite-balloon
## sites (data/aviation_support_1940.json). Non-destructible scenery from AviationSupportKit.
const AVIATION_SUPPORT_JSON := "res://data/aviation_support_1940.json"
var aviation_support_sites: int = 0


func _register_aviation_support() -> void:
	var f: FileAccess = FileAccess.open(AVIATION_SUPPORT_JSON, FileAccess.READ)
	if f == null:
		push_warning("WorldPopulator: %s missing" % AVIATION_SUPPORT_JSON)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var n: int = 0
	for e in (d as Dictionary).get("sites", []):
		var dd: Dictionary = e
		var id: String = str(dd.get("id", "aviation_%d" % n))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(dd["lat"]), float(dd["lon"]))
		if not WorldCoords.is_in_bounds(pos):
			continue
		var size: int = int(dd.get("size", 1))
		_exclude.append([pos, 190.0 + 90.0 * float(size)])
		RoadMesh.add_exclusion_disc(Vector2(pos.x, pos.z), 160.0 + 70.0 * float(size))
		_add_site("aviation_" + id, pos, 7200.0 + 300.0 * float(size), _build_aviation_support,
			{"id": id, "kind": str(dd.get("kind", "seaplane_base")), "size": size, "heading_deg": float(dd.get("heading_deg", 0.0))})
		n += 1
	aviation_support_sites = n
	GroundKit.lp("  _register_aviation_support (%d sites)" % n)


## Build one aviation-support site via AviationSupportKit, seeded from hash(id) for determinism.
func _build_aviation_support(s: Dictionary) -> Node3D:
	var id: String = str(s["id"])
	return AviationSupportKit.build(str(s["kind"]), s["pos"], float(s.get("heading_deg", 0.0)), int(s.get("size", 1)), hash(id))


# ================================================================== P17 forestry
## Forestry Commission plantations and the wartime timber camps (data/forestry_1940.json). Non-destructible
## scenery from ForestryKit.
const FORESTRY_JSON := "res://data/forestry_1940.json"
var forestry_sites: int = 0


func _register_forestry() -> void:
	var f: FileAccess = FileAccess.open(FORESTRY_JSON, FileAccess.READ)
	if f == null:
		push_warning("WorldPopulator: %s missing" % FORESTRY_JSON)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var n: int = 0
	for e in (d as Dictionary).get("sites", []):
		var dd: Dictionary = e
		var id: String = str(dd.get("id", "forest_%d" % n))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(dd["lat"]), float(dd["lon"]))
		if not WorldCoords.is_in_bounds(pos):
			continue
		var size: int = int(dd.get("size", 1))
		_exclude.append([pos, 200.0 + 100.0 * float(size)])
		RoadMesh.add_exclusion_disc(Vector2(pos.x, pos.z), 170.0 + 80.0 * float(size))
		_add_site("forest_" + id, pos, 7000.0 + 300.0 * float(size), _build_forestry,
			{"id": id, "kind": str(dd.get("kind", "plantation")), "size": size, "heading_deg": float(dd.get("heading_deg", 0.0))})
		n += 1
	forestry_sites = n
	GroundKit.lp("  _register_forestry (%d sites)" % n)


## Build one forestry site via ForestryKit, seeded from hash(id) for determinism.
func _build_forestry(s: Dictionary) -> Node3D:
	var id: String = str(s["id"])
	return ForestryKit.build(str(s["kind"]), s["pos"], float(s.get("heading_deg", 0.0)), int(s.get("size", 1)), hash(id))


# ================================================================== P18 navigation aids
## Radio-range beacons, direction-finding stations, tall beacon / broadcast masts and night-sortie approach
## lighting (data/navigation_aids_1940.json). Non-destructible scenery from NavigationAidKit.
const NAVIGATION_AIDS_JSON := "res://data/navigation_aids_1940.json"
var navigation_aid_sites: int = 0


func _register_navigation_aids() -> void:
	var f: FileAccess = FileAccess.open(NAVIGATION_AIDS_JSON, FileAccess.READ)
	if f == null:
		push_warning("WorldPopulator: %s missing" % NAVIGATION_AIDS_JSON)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var n: int = 0
	for e in (d as Dictionary).get("sites", []):
		var dd: Dictionary = e
		var id: String = str(dd.get("id", "nav_%d" % n))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(dd["lat"]), float(dd["lon"]))
		if not WorldCoords.is_in_bounds(pos):
			continue
		var size: int = int(dd.get("size", 1))
		_exclude.append([pos, 160.0 + 70.0 * float(size)])
		RoadMesh.add_exclusion_disc(Vector2(pos.x, pos.z), 140.0 + 60.0 * float(size))
		_add_site("nav_" + id, pos, 6800.0 + 300.0 * float(size), _build_navigation_aids,
			{"id": id, "kind": str(dd.get("kind", "radio_beacon")), "size": size, "heading_deg": float(dd.get("heading_deg", 0.0))})
		n += 1
	navigation_aid_sites = n
	GroundKit.lp("  _register_navigation_aids (%d sites)" % n)


## Build one navigation-aid site via NavigationAidKit, seeded from hash(id) for determinism.
func _build_navigation_aids(s: Dictionary) -> Node3D:
	var id: String = str(s["id"])
	return NavigationAidKit.build(str(s["kind"]), s["pos"], float(s.get("heading_deg", 0.0)), int(s.get("size", 1)), hash(id))


# ================================================================== P19 military depth
## Transit / embarkation camps, ammunition depots, vehicle parks, horse-drawn transport columns and tank trains
## (data/military_depth_1940.json). Non-destructible scenery from MilitaryDepthKit.
const MILITARY_DEPTH_JSON := "res://data/military_depth_1940.json"
var military_depth_sites: int = 0


func _register_military_depth() -> void:
	var f: FileAccess = FileAccess.open(MILITARY_DEPTH_JSON, FileAccess.READ)
	if f == null:
		push_warning("WorldPopulator: %s missing" % MILITARY_DEPTH_JSON)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		return
	var n: int = 0
	for e in (d as Dictionary).get("sites", []):
		var dd: Dictionary = e
		var id: String = str(dd.get("id", "mil_%d" % n))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(dd["lat"]), float(dd["lon"]))
		if not WorldCoords.is_in_bounds(pos):
			continue
		var size: int = int(dd.get("size", 1))
		_exclude.append([pos, 190.0 + 90.0 * float(size)])
		RoadMesh.add_exclusion_disc(Vector2(pos.x, pos.z), 160.0 + 70.0 * float(size))
		_add_site("mil_" + id, pos, 7200.0 + 300.0 * float(size), _build_military_depth,
			{"id": id, "kind": str(dd.get("kind", "transit_camp")), "size": size, "heading_deg": float(dd.get("heading_deg", 0.0))})
		n += 1
	military_depth_sites = n
	GroundKit.lp("  _register_military_depth (%d sites)" % n)


## Build one military-depth site via MilitaryDepthKit, seeded from hash(id) for determinism.
func _build_military_depth(s: Dictionary) -> Node3D:
	var id: String = str(s["id"])
	return MilitaryDepthKit.build(str(s["kind"]), s["pos"], float(s.get("heading_deg", 0.0)), int(s.get("size", 1)), hash(id))


# ================================================================== streaming
## Load-in: stream at full speed and report when everything near the focus has been built.
var boost: bool = false
var pending: int = 999
var _pend_sites: int = 0
var _pend_tiles: int = 0


func _process(delta: float) -> void:
	_frames += 1
	if focus == null or not is_instance_valid(focus):
		focus = GroundKit.player_node()
	if not _debug_done and _frames > 3:
		_debug_done = true
		_parse_debug_args()
	if focus == null:
		return
	if focus.global_position.distance_to(_warm_center) > 4000.0:
		_warm_center = focus.global_position
		var wu0: int = Time.get_ticks_msec()
		_warm_up(_warm_center)
		print("[slow] warm_up %d ms" % (Time.get_ticks_msec() - wu0))
	_timer -= delta
	if boost:
		_timer = 0.0
	if _timer <= 0.0:
		_timer = SITE_TICK
		var st0: int = Time.get_ticks_msec()
		_stream_sites()
		if Time.get_ticks_msec() - st0 > 100:
			print("[slow] stream_sites %d ms" % (Time.get_ticks_msec() - st0))
	if enable_countryside:
		_tile_timer -= delta
		if boost:
			_tile_timer = 0.0
		if _tile_timer <= 0.0:
			_tile_timer = 0.06
			_stream_tiles()


func _site_dist(s: Dictionary, fp: Vector3) -> float:
	var rt: Variant = s["route"]
	if rt != null:
		return (rt as RoutePath).closest(fp).y
	var p: Vector3 = s["pos"]
	return Vector2(p.x - fp.x, p.z - fp.z).length()


## Build the nearest sites/tiles synchronously when focus jumps (session start, respawn, teleport),
## so the immediate surroundings are already there instead of popping in.
func _warm_up(fp: Vector3) -> void:
	_sync_build = true
	_warm_up_inner(fp)
	_sync_build = false


func _warm_up_inner(fp: Vector3) -> void:
	var cand: Array = []
	for s in _sites:
		if s["node"] == null:
			var d: float = _site_dist(s, fp)
			if d < 3500.0:
				cand.append([d, s])
	cand.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var n: int = 0
	for e in cand:
		if n >= 8:
			break
		_build_site(e[1])
		n += 1
	var cx: int = floori(fp.x / TILE)
	var cz: int = floori(fp.z / TILE)
	var nb: int = 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if nb >= 3:
				break
			var k := Vector2i(cx + dx, cz + dz)
			if _tiles.has(k):
				continue
			var c := Vector2((float(k.x) + 0.5) * TILE, (float(k.y) + 0.5) * TILE)
			if c.distance_to(Vector2(fp.x, fp.z)) > 2600.0:
				continue
			var node: Node3D = _make_tile(k)
			add_child(node)
			_tiles[k] = node
			nb += 1


func _stream_sites() -> void:
	var fp: Vector3 = focus.global_position
	var want: Array = []
	for s in _sites:
		var d: float = _site_dist(s, fp)
		var node: Variant = s["node"]
		if node != null and not is_instance_valid(node):
			s["node"] = null
			node = null
		if node != null:
			if d > float(s["act"]) * 1.3 and not bool(s["pin"]):
				_free_site(s)
		elif d < float(s["act"]) or bool(s["pin"]):
			want.append([d, s])
	want.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var budget: int = SITE_BUDGET * (4 if boost else 1)
	var t_start: int = Time.get_ticks_usec()
	for w in want:
		if budget <= 0:
			break
		# in flight, stop after ~6 ms of building per tick (one site always goes through) to avoid stacking hitches
		if not boost and budget < SITE_BUDGET and Time.get_ticks_usec() - t_start > 6000:
			break
		var s2: Dictionary = w[1]
		if bool(s2["ambient"]) and _ambient_active >= 26 and not bool(s2["pin"]):
			continue
		_build_site(s2)
		budget -= 1
	_pend_sites = maxi(want.size() - (SITE_BUDGET * (4 if boost else 1) - budget), 0)


func _build_site(s: Dictionary) -> Node3D:
	if s["node"] != null and is_instance_valid(s["node"]):
		return s["node"]
	var b: Callable = s["build"]
	var t0: int = Time.get_ticks_msec()
	var n: Node3D = b.call(s)
	if Time.get_ticks_msec() - t0 > 40:
		print("[slow] site %s built in %d ms" % [str(s["key"]), Time.get_ticks_msec() - t0])
	if n == null and bool(s.get("defer", false)):
		s["defer"] = false
		return null          # waiting on a background search: built on a later tick
	if n == null:
		n = Node3D.new()
	n.name = str(s["key"])
	add_child(n)
	s["node"] = n
	if bool(s["ambient"]):
		_ambient_active += 1
	return n


func _free_site(s: Dictionary) -> void:
	var n: Variant = s["node"]
	if n != null and is_instance_valid(n):
		(n as Node).queue_free()
	if bool(s["ambient"]):
		_ambient_active = maxi(_ambient_active - 1, 0)
	s["node"] = null
	s["main"] = null


var _built_era: String = ""     # the date the built tiles / sites were made for
var _tile_gen: int = 0          # bumps when the era changes: tile jobs started earlier are dropped


## The sortie's date is known (main.start_game): if it differs from the one the world was built for, drop the built
## tiles and sites so they rebuild for the new date (this happens behind the load screen), and re-pick the terrain
## tint zones (many are dated).
func on_era_date(d: String) -> void:
	# tile jobs on the workers read EraClock / WarDamage: let them finish before those change under them
	for jb in _tile_jobs:
		WorkerThreadPool.wait_for_task_completion(int((jb as Dictionary)["task"]))
	_tile_jobs.clear()
	EraClock.set_date(d)
	WarDamage.refresh()
	_push_era_zones()
	if terrain != null and terrain.has_method("refresh_zones"):
		terrain.call("refresh_zones")
	if EraClock.current() == _built_era:
		return
	_built_era = EraClock.current()
	_tile_gen += 1
	free_all()
	print("[era] world rebuilt for %s (%s)" % [_built_era, EraClock.band()])


## Terrain zones that depend on the war date (bomb damage now; floods and beach churn later).
func _push_era_zones() -> void:
	if terrain != null and terrain.has_method("set_zone_group"):
		terrain.call("set_zone_group", "damage", WarDamage.zones())
		terrain.call("set_zone_group", "warground", WarGround.zones())


func free_all() -> void:
	for s in _sites:
		_free_site(s)
	for k in _tiles.keys():
		(_tiles[k] as Node).queue_free()
	_tiles.clear()


func pin_site(key: String) -> void:
	if _site_by_key.has(key):
		var s: Dictionary = _site_by_key[key]
		s["pin"] = true
		_build_site(s)


## Load-screen priority distance: tiles ahead of the aircraft (the way the sortie points, towards its target) count as
## nearer, so the scenery you fly into is ready before the load screen ends. Behind the aircraft counts as farther.
func _boost_dist(d: float, c: Vector2, fp: Vector3) -> float:
	if d < 1.0 or focus == null or not is_instance_valid(focus):
		return d
	var fwd := Vector2(-focus.global_transform.basis.z.x, -focus.global_transform.basis.z.z)
	if fwd.length() < 0.01:
		return d
	fwd = fwd.normalized()
	var to_t: Vector2 = (c - Vector2(fp.x, fp.z)) / d
	var ahead: float = to_t.dot(fwd)
	var f: float = 1.0 - 0.4 * maxf(ahead, 0.0) + 0.25 * maxf(-ahead, 0.0)
	for n in get_tree().get_nodes_in_group("mission_target"):
		var tp: Vector3 = (n as Node3D).global_position
		var dt: Vector2 = Vector2(tp.x, tp.z) - Vector2(fp.x, fp.z)
		if dt.length() > 1.0:
			f = minf(f, 1.0 - 0.4 * maxf(to_t.dot(dt.normalized()), 0.0))
	return d * f


func _stream_tiles() -> void:
	var fp: Vector3 = focus.global_position
	var cx: int = floori(fp.x / TILE)
	var cz: int = floori(fp.z / TILE)
	var rng_c: int = int(ceil(TILE_RADIUS / TILE))
	var built: int = 0
	var cand: Array = []
	for dz in range(-rng_c, rng_c + 1):
		for dx in range(-rng_c, rng_c + 1):
			var k := Vector2i(cx + dx, cz + dz)
			if _tiles.has(k):
				continue
			var c := Vector2((float(k.x) + 0.5) * TILE, (float(k.y) + 0.5) * TILE)
			var d: float = c.distance_to(Vector2(fp.x, fp.z))
			if d < TILE_RADIUS:
				cand.append([_boost_dist(d, c, fp) if boost else d, k])
	cand.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	# Finish the background tile job (the scatter maths ran on a worker; only node creation is left).
	var finish_cap: int = 4 if boost else 1
	var finished: int = 0
	var ji: int = 0
	while ji < _tile_jobs.size():
		var jb: Dictionary = _tile_jobs[ji]
		if finished >= finish_cap or not WorkerThreadPool.is_task_completed(int(jb["task"])):
			ji += 1
			continue
		WorkerThreadPool.wait_for_task_completion(int(jb["task"]))
		_tile_jobs.remove_at(ji)
		var jk: Vector2i = jb["k"]
		var res: Dictionary = jb["res"]
		var jc := Vector2((float(jk.x) + 0.5) * TILE, (float(jk.y) + 0.5) * TILE)
		if int(jb.get("gen", 0)) == _tile_gen and not _tiles.has(jk) and res.has("data") and jc.distance_to(Vector2(fp.x, fp.z)) < TILE_RADIUS + TILE:
			var ft0: int = Time.get_ticks_msec()
			var jn: Node3D = _finish_tile(jk, res["data"])
			add_child(jn)
			if Time.get_ticks_msec() - ft0 > 30 and not boost:
				print("[slow] tile %s finished in %d ms" % [str(jk), Time.get_ticks_msec() - ft0])
			_tiles[jk] = jn
			built += 1
			finished += 1
	if boost and LandCover.ready():
		# loading screen: compute the next tiles' beach defences on all cores at once
		var pre: Array = []
		for e0 in cand:
			if pre.size() >= TILE_BUDGET * 4:
				break
			pre.append(e0[1])
		var bt0: int = Time.get_ticks_msec()
		BeachKit.precompute(pre, TILE, _exclude)
		if Time.get_ticks_msec() - bt0 > 100:
			print("[slow] beach precompute %d ms" % (Time.get_ticks_msec() - bt0))
	for e in cand:
		var k2: Vector2i = e[1]
		if _job_has(k2):
			continue
		if not LandCover.ready():
			# focus just jumped (start / respawn / teleport): build synchronously so the ground is there now
			if built >= TILE_BUDGET:
				break
			var tt0: int = Time.get_ticks_msec()
			var node: Node3D = _make_tile(k2)
			add_child(node)
			_tiles[k2] = node
			built += 1
			if Time.get_ticks_msec() - tt0 > 100:
				print("[slow] tile %s built in %d ms" % [str(k2), Time.get_ticks_msec() - tt0])
		elif boost and float(e[0]) >= BOOST_RADIUS:
			break          # load screen: only the preload area; the rest waits so the terrain workers are not starved
		elif _tile_jobs.size() < _max_tile_jobs():
			_start_tile_job(k2)
		else:
			break
	var near_left: int = 0
	if boost:
		for e2 in cand:
			if float(e2[0]) < BOOST_RADIUS:
				near_left += 1
		near_left = maxi(near_left - built, 0)
	_pend_tiles = near_left if boost else maxi(cand.size() - built, 0)
	pending = _pend_sites + _pend_tiles
	for k3 in _tiles.keys():
		var c3 := Vector2((float(k3.x) + 0.5) * TILE, (float(k3.y) + 0.5) * TILE)
		if c3.distance_to(Vector2(fp.x, fp.z)) > TILE_RADIUS + TILE * 1.5:
			(_tiles[k3] as Node).queue_free()
			_tiles.erase(k3)


var _tile_jobs: Array = []   # [{"k": Vector2i, "task": int, "res": Dictionary}] tiles being scattered on workers


func _job_has(k: Vector2i) -> bool:
	for j in _tile_jobs:
		if (j as Dictionary)["k"] == k:
			return true
	return false


## Tiles scattered at once: all spare cores on the load screen, a couple while flying (keeps the frame rate steady).
func _max_tile_jobs() -> int:
	var cores: int = maxi(OS.get_processor_count() / 2, 2)
	return mini(cores, 6) if boost else 2


## Scatter one tile on a worker thread. Placing a tile's few thousand houses / trees / hedges costs 100-300 ms of
## sampling; done on the main thread that showed up as a hitch every couple of seconds in flight.
func _start_tile_job(k: Vector2i) -> void:
	var org := Vector2(float(k.x) * TILE, float(k.y) * TILE)
	var res: Dictionary = {}
	var ex: Array = _exclude
	var seed_v: int = k.x * 73856093 ^ k.y * 19349663
	GroundKit.terrain()          # resolve the cached terrain node here, not from the worker
	var task: int = WorkerThreadPool.add_task(func() -> void:
		RoadMesh.prepare_block(org, TILE)
		RiverMesh.prepare_block(org, TILE)
		res["data"] = Scatter.tile_landcover_data(org, TILE, seed_v, ex)
		RiverMesh.clear_block()
		RoadMesh.clear_block())
	_tile_jobs.append({"k": k, "task": task, "res": res, "gen": _tile_gen})


func _finish_tile(k: Vector2i, data: Dictionary) -> Node3D:
	var org := Vector2(float(k.x) * TILE, float(k.y) * TILE)
	var tt: Array = [Time.get_ticks_usec()]
	var node: Node3D = Scatter.build_tile_nodes(data)
	node.name = "tile_%d_%d" % [k.x, k.y]
	tt.append(Time.get_ticks_usec())
	if RoadMesh.has_roads():
		var rm: MeshInstance3D = RoadMesh.build_tile(org, TILE)
		if rm != null:
			node.add_child(rm)
		tt.append(Time.get_ticks_usec())
		_tile_traffic(node, k, org)
	else:
		tt.append(Time.get_ticks_usec())
	tt.append(Time.get_ticks_usec())
	if RiverMesh.has_rivers():
		var rvm: MeshInstance3D = RiverMesh.build_tile(org, TILE)
		if rvm != null:
			node.add_child(rvm)
	if PylonMesh.active():
		var pyn: Node3D = PylonMesh.build_tile(org, TILE)
		if pyn != null:
			node.add_child(pyn)
	if CanalKit.canal_count() > 0:
		var cnn: Node3D = CanalKit.build_tile(org, TILE)
		if cnn != null:
			node.add_child(GroundKit.flatten(cnn, 6000.0 * Scatter.vis_scale))
	tt.append(Time.get_ticks_usec())
	if RailKit.rail_count() > 0:
		var rln: Node3D = RailKit.build_tile(org, TILE)
		if rln != null:
			node.add_child(GroundKit.flatten(rln, 6000.0 * Scatter.vis_scale))
	tt.append(Time.get_ticks_usec())
	if int(tt[5]) - int(tt[0]) > 30000 and not boost:
		print("[slow] tile parts ms: scatter %d roads %d traffic %d rivers/pylons/canals %d rails %d" % [(int(tt[1]) - int(tt[0])) / 1000, (int(tt[2]) - int(tt[1])) / 1000, (int(tt[3]) - int(tt[2])) / 1000, (int(tt[4]) - int(tt[3])) / 1000, (int(tt[5]) - int(tt[4])) / 1000])
	return node


## One countryside tile: land-cover scatter (trees, houses, villages with churches), real road ribbons with
## lane markings, and ambient road traffic (civilian cars and buses, supply lorries, military convoys, tanks).
func _make_tile(k: Vector2i) -> Node3D:
	var org := Vector2(float(k.x) * TILE, float(k.y) * TILE)
	RoadMesh.prepare_block(org, TILE)
	RiverMesh.prepare_block(org, TILE)
	var node: Node3D = Scatter.make_tile(org, TILE, k.x * 73856093 ^ k.y * 19349663, _exclude)
	RiverMesh.clear_block()
	RoadMesh.clear_block()
	node.name = "tile_%d_%d" % [k.x, k.y]
	if RoadMesh.has_roads():
		var rm: MeshInstance3D = RoadMesh.build_tile(org, TILE)
		if rm != null:
			node.add_child(rm)
		_tile_traffic(node, k, org)
	if RiverMesh.has_rivers():
		var rvm: MeshInstance3D = RiverMesh.build_tile(org, TILE)
		if rvm != null:
			node.add_child(rvm)
	if PylonMesh.active():
		var pyn: Node3D = PylonMesh.build_tile(org, TILE)
		if pyn != null:
			node.add_child(pyn)
	if CanalKit.canal_count() > 0:
		var cnn: Node3D = CanalKit.build_tile(org, TILE)
		if cnn != null:
			node.add_child(GroundKit.flatten(cnn, 6000.0 * Scatter.vis_scale))
	if RailKit.rail_count() > 0:
		var rln: Node3D = RailKit.build_tile(org, TILE)
		if rln != null:
			node.add_child(GroundKit.flatten(rln, 6000.0 * Scatter.vis_scale))
	return node


const MAX_TILE_CONVOYS: int = 40
var _tile_convoys: int = 0


func _tile_traffic(tile: Node3D, k: Vector2i, org: Vector2) -> void:
	var centre := Vector3(org.x + TILE * 0.5, 0.0, org.y + TILE * 0.5)
	if focus == null or Vector2(centre.x - focus.global_position.x, centre.z - focus.global_position.z).length() > 8000.0:
		return
	if _tile_convoys >= MAX_TILE_CONVOYS:
		return
	var ways: Array = RoadMesh.ways_in_tile(org, TILE)
	if ways.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = k.x * 92837111 ^ k.y * 689287499
	var team: String = _team_of_pos(centre)
	for n in mini(ways.size(), 2):
		var w: Dictionary = ways[rng.randi() % ways.size()]
		var rp: RoutePath = w["route"]
		var c: Vector2 = rp.closest(centre)
		var roll: float = rng.randf()
		var comp: String
		var cteam: String = team
		var spd: float = rng.randf_range(8.0, 13.0)
		if team == "Axis":
			comp = "civil" if roll < 0.3 else ("supply" if roll < 0.55 else ("troops" if roll < 0.7 else ("tanks" if roll < 0.85 else "mixed")))
		else:
			comp = "civil" if roll < 0.55 else ("supply" if roll < 0.75 else ("troops" if roll < 0.9 else "mixed"))
		if comp == "civil":
			cteam = "Neutral"
			spd = rng.randf_range(11.0, 18.0)
			if rng.randf() < 0.5:
				comp = "civil_light"
		var cv: Convoy = Convoy.create(cteam, rp, false, comp, c.x + rng.randf_range(-500.0, 500.0), spd)
		cv.spacing = 26.0 if comp in ["civil", "civil_light"] else 22.0
		tile.add_child(cv)
		_tile_convoys += 1
		tile.tree_exited.connect(func() -> void: _tile_convoys = maxi(_tile_convoys - 1, 0))


# ================================================================== builders
func _team_of_pos(p: Vector3) -> String:
	return GroundKit.side_at(p)


func _place(n: Node3D, p: Vector3) -> void:
	n.position = Vector3(p.x, _y(p), p.z)


func _in_runway_zone(p: Vector3) -> bool:
	for z in _runway_zones:
		var c: Vector3 = z[0]
		if Vector2(p.x - c.x, p.z - c.z).length() < float(z[1]):
			return true
	return false


func _land_ring(center: Vector3, count: int, r_min: float, r_max: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var tries: int = 0
	while out.size() < count and tries < count * 12:
		tries += 1
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(r_min, r_max)
		var p: Vector3 = center + Vector3(cos(a) * r, 0, sin(a) * r)
		if _in_runway_zone(p):
			continue
		if GroundKit.raw_y(p.x, p.z) > 1.0:
			out.append(p)
	return out


## Shelled, burning buildings with black smoke around an action site (fewer where the site is intact).
func _ruins(parent: Node3D, center: Vector3, count: int, r_min: float, r_max: float, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for p in _land_ring(center, count, r_min, r_max, rng):
		var ru: BurningRuin = BurningRuin.create(rng.randi(), rng.randf_range(0.9, 1.5))
		_place(ru, p)
		parent.add_child(ru)


## AA guns, searchlights and balloons around a point.
func _defences(parent: Node3D, center: Vector3, team: String, n88: int, nbofors: int, nlights: int, nballoons: int, spread: float, seed_v: int) -> void:
	# v7.0: far more flak everywhere - every defended site gets roughly twice the heavy guns and half as many
	# again light guns and searchlights, so a raid on a defended target flies through a real barrage
	n88 = int(ceil(float(n88) * 2.0))
	nbofors = int(ceil(float(nbofors) * 1.5))
	nlights = int(ceil(float(nlights) * 1.5))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for p in _land_ring(center, n88, spread * 0.5, spread, rng):
		var g: AAGun = AAGun.create("88mm", team)
		_place(g, p)
		parent.add_child(g)
	for p in _land_ring(center, nbofors, spread * 0.3, spread * 0.9, rng):
		var g2: AAGun = AAGun.create("bofors", team)
		_place(g2, p)
		parent.add_child(g2)
	for p in _land_ring(center, nlights, spread * 0.6, spread * 1.3, rng):
		var sl: Searchlight = Searchlight.create(team)
		_place(sl, p)
		parent.add_child(sl)
	for p in _land_ring(center, nballoons, spread * 0.7, spread * 1.6, rng):
		var bb: BarrageBalloon = BarrageBalloon.create("Allies", rng.randf_range(240.0, 380.0))
		bb.position = Vector3(p.x, _y(p) + bb.altitude, p.z)
		parent.add_child(bb)


func _parked_mesh(team: String) -> ArrayMesh:
	var key: String = "parked_" + team
	if Scatter._meshes.has(key):
		return Scatter._meshes[key]
	var body: Color = Color(0.27, 0.33, 0.2) if team == "Allies" else Color(0.36, 0.4, 0.38)
	var under: Color = Color(0.55, 0.62, 0.6)
	var parts: Array = []
	parts.append(GroundKit.cyl_part(0.55, 0.95, 9.0, Vector3(0, 1.7, 0), body, Vector3(90, 0, 0), 8))
	parts.append(GroundKit.cyl_part(0.0, 0.6, 1.8, Vector3(0, 1.7, -5.3), Color(0.8, 0.7, 0.2) if team == "Axis" else body.darkened(0.2), Vector3(-90, 0, 0), 8))
	parts.append(GroundKit.box_part(Vector3(11.0, 0.22, 2.6), Vector3(0, 1.3, -0.4), body.lightened(0.06)))
	parts.append(GroundKit.box_part(Vector3(4.2, 0.18, 1.5), Vector3(0, 2.1, 4.0), body))
	parts.append(GroundKit.box_part(Vector3(0.22, 2.4, 1.7), Vector3(0, 3.0, 4.0), body))
	parts.append(GroundKit.box_part(Vector3(0.18, 3.4, 0.3), Vector3(0, 1.7, -6.2), Color(0.1, 0.1, 0.1), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.4, 1.2, 0.4), Vector3(-1.4, 0.6, -0.4), Color(0.1, 0.1, 0.1), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.4, 1.2, 0.4), Vector3(1.4, 0.6, -0.4), Color(0.1, 0.1, 0.1), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(11.0, 0.05, 2.6), Vector3(0, 1.18, -0.4), under, Vector3.ZERO, false))
	var m: ArrayMesh = GroundKit.combine(parts)
	Scatter._meshes[key] = m
	return m


func _blister_mesh(team: String) -> ArrayMesh:
	return AirfieldAssets.blister(team)

	var key: String = "blister_" + team
	if Scatter._meshes.has(key):
		return Scatter._meshes[key]
	var col: Color = Color(0.20, 0.27, 0.15) if team == "Allies" else Color(0.30, 0.31, 0.27)
	var parts: Array = []
	parts.append(GroundKit.cyl_part(5.0, 5.0, 15.0, Vector3(0, 0.0, 0), col, Vector3(90, 0, 0), 10))
	parts.append(GroundKit.box_part(Vector3(10.0, 3.0, 0.4), Vector3(0, 1.4, 7.4), Color(0.1, 0.1, 0.1), Vector3.ZERO, false))
	var m: ArrayMesh = GroundKit.combine(parts)
	Scatter._meshes[key] = m
	return m


func _truck_mesh(team: String) -> ArrayMesh:
	return AirfieldAssets.truck(team)

	var key: String = "truck_" + team
	if Scatter._meshes.has(key):
		return Scatter._meshes[key]
	var col: Color = Color(0.25, 0.30, 0.18) if team == "Allies" else Color(0.34, 0.34, 0.30)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(2.4, 2.0, 3.2), Vector3(0, 1.3, -2.4), col.lightened(0.05)))
	parts.append(GroundKit.box_part(Vector3(2.6, 2.2, 5.5), Vector3(0, 1.5, 1.8), col))
	parts.append(GroundKit.box_part(Vector3(2.2, 0.6, 9.0), Vector3(0, 0.3, 0.0), Color(0.1, 0.1, 0.1), Vector3.ZERO, false))
	var m: ArrayMesh = GroundKit.combine(parts)
	Scatter._meshes[key] = m
	return m


func _bunker_bank_mesh() -> ArrayMesh:
	return AirfieldAssets.bomb_bank()

	var key: String = "bomb_bank"
	if Scatter._meshes.has(key):
		return Scatter._meshes[key]
	var earth: Color = Color(0.34, 0.29, 0.2)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(14.0, 3.4, 3.0), Vector3(0, 1.7, -5.0), earth))
	parts.append(GroundKit.box_part(Vector3(3.0, 3.4, 10.0), Vector3(-5.5, 1.7, 0.0), earth))
	parts.append(GroundKit.box_part(Vector3(3.0, 3.4, 10.0), Vector3(5.5, 1.7, 0.0), earth))
	parts.append(GroundKit.box_part(Vector3(6.0, 1.4, 5.0), Vector3(0, 0.7, 0.0), Color(0.28, 0.3, 0.2)))
	var m: ArrayMesh = GroundKit.combine(parts)
	Scatter._meshes[key] = m
	return m


func _dress_grass_airfield(container: Node3D, dress: Node3D, af: Airfield, axf: Transform3D, y: float, team: String, rng: RandomNumberGenerator) -> void:
	# parked aircraft on the apron and a few out on the grass
	var xf: Array = []
	for pad in af.dispersal_world_points():
		if rng.randf() < 0.35:
			continue
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * 1.7), Vector3(pad.x, y + 0.4, pad.z)))
	ParkedAircraft.place(container, xf, team, af)
	# three big arched hangars in a row behind the apron
	for i in 3:
		var hp: Vector3 = axf * Vector3(-345.0, 0, -200.0 + float(i) * 95.0)
		var h: GroundStructure = GroundStructure.create("hangar", team, hp, af.heading_deg + 90.0)
		h.is_mission_target = false
		container.add_child(h)
		h.position.y = y
	var tw: GroundStructure = GroundStructure.create("control_tower", team, axf * Vector3(-70.0, 0, 60.0), af.heading_deg)
	container.add_child(tw)
	tw.position.y = y
	# fuel silos by the apron, huts and workshops in loose clusters beyond the hangars
	for i in 3:
		var fp: Vector3 = axf * Vector3(-260.0 - float(i) * 22.0, 0, 100.0)
		var ft: GroundStructure = GroundStructure.create("fuel_tank", team, fp, 0.0)
		container.add_child(ft)
		ft.position.y = y
	var huts: Array = []
	for cl in 3:
		var cx: float = -430.0 - float(cl) * 70.0
		for i in 8:
			huts.append(Transform3D(Basis(Vector3.UP, PI * 0.5 + rng.randf_range(-0.2, 0.2)), Vector3(cx + rng.randf_range(-20.0, 20.0), 0.0, -220.0 + float(cl) * 130.0 + float(i) * 18.0)))
	_props(container, "hut", AirfieldAssets.nissen(team), _to_world(axf, huts), team, 4)
	var blisters: Array = []
	for i in 6:
		var bg: Vector3 = axf * Vector3(150.0 + rng.randf_range(-6.0, 30.0), 0.0, -350.0 + float(i) * 120.0)
		blisters.append(Transform3D(Basis(Vector3.UP, af.rotation.y + PI * 0.5), Vector3(bg.x, y, bg.z)))
	_props(container, "blister", _blister_mesh(team), blisters, team, 2)
	var trucks: Array = []
	for i in 12:
		var tg: Vector3 = axf * Vector3(rng.randf_range(-300.0, -120.0), 0, rng.randf_range(-210.0, 40.0))
		trucks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(tg.x, y + 0.2, tg.z)))
	_props(container, "truck", _truck_mesh(team), trucks, team, 3)


## Destructible airfield props: greedy clusters of up to `per` instances within 30 m of the cluster's first one.
func _props(parent: Node3D, kind: String, mesh: Mesh, xforms: Array, team: String, per: int) -> void:
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


func _to_world(axf: Transform3D, local: Array) -> Array:
	var out: Array = []
	for t in local:
		out.append(axf * (t as Transform3D))
	return out


## Who holds an airfield on the current mission date: its own side, unless it has a `liberated` date (ISO) that has passed.
static func airfield_team(d: Dictionary) -> String:
	var team: String = "Allies" if str(d.get("side", "")) == "RAF" else "Axis"
	var lib: String = str(d.get("liberated", ""))
	if lib != "" and GameState.era_date != "" and GameState.era_date >= lib:
		team = "Allies"
	return team


func _build_airfield(s: Dictionary) -> Node3D:
	var id: String = s["id"]
	var d: Dictionary = s["data"]
	var container := Node3D.new()
	var team: String = airfield_team(d)
	var af: Airfield = null
	if s["existing"] != null and is_instance_valid(s["existing"]):
		af = s["existing"]
	else:
		var pos: Vector3 = s["pos"]
		af = Airfield.create(str(d["name"]), pos, float(d["heading_deg"]), float(s["y"]))
		af.style = Airfield.style_for(id)
		container.add_child(af)
		af.build_layout()      # the layout must exist now: the field is dressed below, before it enters the tree
		airfields[id] = af
	s["main"] = af
	# give every populated field its side and register it, so landing there rearms (main.gd) and the tower calls
	if af.team == "":
		af.team = team
	if not af.is_in_group("airfield"):
		af.add_to_group("airfield")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var dress := Node3D.new()
	dress.position = af.position
	dress.rotation = af.rotation
	container.add_child(dress)
	var y: float = af.surface_y
	var axf := Transform3D(Basis(Vector3.UP, af.rotation.y), af.position)
	var k: float = af.layout_scale()
	var grass_station: bool = af.style in ["raf_grass", "lw_field"]
	if grass_station:
		_dress_grass_station(container, af, axf, y, team, rng)
	elif af.style == "grass":
		_dress_grass_airfield(container, dress, af, axf, y, team, rng)
	elif af.style in ["cross", "parallel", "forward"]:
		_dress_other_airfield(container, af, axf, y, team, rng)
	else:
		# Layout (airfield local frame; -Z along the main runway, triangle corner at +X, technical site west of the track).
		var xf: Array = []
		var pads: Array = af.dispersal_world_points()
		for i in pads.size():
			if rng.randf() < 0.3:
				continue
			var pad: Vector3 = pads[i]
			xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * 1.7), Vector3(pad.x, y + 0.4, pad.z)))
		# staggered apron rows in front of the hangars
		for row in 2:
			for i in 9:
				var lp := Vector3(-165.0 - float(row) * 34.0, 0.0, -230.0 + float(i) * 52.0 + float(row) * 26.0)
				var gp: Vector3 = axf * lp
				xf.append(Transform3D(Basis(Vector3.UP, af.rotation.y - PI * 0.5 + rng.randf_range(-0.15, 0.15)) * Basis.from_scale(Vector3.ONE * 1.7), Vector3(gp.x, y + 0.4, gp.z)))
		ParkedAircraft.place(container, xf, team, af)
		# T2 hangars in a row on the technical site, control tower beside the runway, fuel tanks
		for i in 5:
			var hp: Vector3 = axf * Vector3(-265.0, 0, -210.0 + float(i) * 105.0)
			var h: GroundStructure = GroundStructure.create("hangar", team, hp, af.heading_deg + 90.0)
			h.is_mission_target = false
			container.add_child(h)
			h.position.y = y
		var tw: GroundStructure = GroundStructure.create("control_tower", team, axf * Vector3(-75.0, 0, 130.0), af.heading_deg)
		container.add_child(tw)
		tw.position.y = y
		for i in 4:
			var fp: Vector3 = axf * Vector3(-330.0 - float(i) * 22.0, 0, -560.0)
			var ft: GroundStructure = GroundStructure.create("fuel_tank", team, fp, 0.0)
			container.add_child(ft)
			ft.position.y = y
		# blister hangars along the outer track
		var blisters: Array = []
		for i in 10:
			var bl := Vector3(-150.0 - rng.randf_range(0.0, 15.0), 0.0, -560.0 + float(i) * 112.0)
			var bg: Vector3 = axf * bl
			blisters.append(Transform3D(Basis(Vector3.UP, af.rotation.y + PI * 0.5), Vector3(bg.x, y, bg.z)))
		_props(container, "blister", _blister_mesh(team), blisters, team, 2)
		# technical site: dense rows of Nissen huts beyond the hangars, plus trucks and cars
		var huts: Array = []
		for row in 5:
			for i in 12:
				huts.append(Transform3D(Basis(Vector3.UP, PI * 0.5 + (0.0 if i % 4 else 0.2)), Vector3(-350.0 - float(row) * 26.0, 0.0, -260.0 + float(i) * 44.0)))
		_props(container, "hut", AirfieldAssets.nissen(team), _to_world(axf, huts), team, 4)
		var trucks: Array = []
		for i in 14:
			var tg: Vector3 = axf * Vector3(rng.randf_range(-200.0, -130.0), 0, rng.randf_range(-260.0, 260.0))
			trucks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(tg.x, y + 0.2, tg.z)))
		_props(container, "truck", _truck_mesh(team), trucks, team, 3)
		# bomb dump: earth-banked stores in rows, well away from the buildings
		var banks: Array = []
		for row in 4:
			for i in 6:
				var bp: Vector3 = axf * Vector3(-520.0 - float(row) * 34.0, 0, 380.0 + float(i) * 36.0)
				banks.append(Transform3D(Basis(Vector3.UP, af.rotation.y + PI * 0.5), Vector3(bp.x, y, bp.z)))
		_props(container, "ammo", _bunker_bank_mesh(), banks, team, 6)
	AirfieldActivity.populate(container, af, axf, y, team, rng)     # ground crews, bowsers, tugs, bomb cart, fire tender
	# P8 airfield furniture (all layouts): blast pens/revetments, Nissen camp, T2/T1 hangars, watch office,
	# fuel + bomb dumps, flare path with Chance lights, dummy aircraft - inside the footprint, clear of the runway.
	if not grass_station:          # grass stations carry their own period dressing (pens / nets, hangar arc)
		AirfieldFurniture.dress(container, af, axf, y, team, rng)
	# defences
	var is_london: bool = id in ["northolt", "kenley", "biggin_hill", "hornchurch"]
	var n88: int = 1 if team == "Allies" else 2
	var nb: int = 3 if team == "Allies" else 2
	var zone_r: float = af.runway_length * 0.55 + 100.0
	_runway_zones.append([af.position, zone_r])
	_airfield_defences(container, af, axf, team, id, 4 if (team == "Allies" and is_london) else 0, maxf(260.0 * k, zone_r * 1.8))
	var camp_pos: Variant = s.get("camp", Vector3.INF)
	if camp_pos is Vector3 and camp_pos != Vector3.INF:
		ArmyCampKit.build(container, camp_pos, float(d["heading_deg"]), team, hash(id) + 77)
	# Blackout: at night an airfield shows its flare path / runway lamps only when it is an active (own-side)
	# field; occupied/enemy fields stay dark (see Airfield.set_lights_active).
	af.set_lights_active(team == "Allies")
	return container


## Dressing for the grass layouts. raf_grass: aircraft in E-type pens and on the apron, an arc of big hangars, the
## watch office with its landing T, Nissen huts and lorries on the technical site. lw_field: aircraft under camouflage
## nets round the field edge, tents and lorries, a fuel-drum dump - no permanent buildings.
func _dress_grass_station(container: Node3D, af: Airfield, axf: Transform3D, y: float, team: String, rng: RandomNumberGenerator) -> void:
	var L: float = af.runway_length
	var lw: bool = af.style == "lw_field"
	var xf: Array = []
	for pad in af.dispersal_world_points():
		if rng.randf() < 0.22:
			continue
		var to_c: Vector3 = af.position - (pad as Vector3)
		to_c.y = 0.0
		var b: Basis = Basis.looking_at(to_c.normalized(), Vector3.UP) if to_c.length() > 1.0 else Basis()
		b = b.rotated(Vector3.UP, rng.randf_range(-0.2, 0.2))
		xf.append(Transform3D(b, Vector3(pad.x, y + 0.4, pad.z)))
	ParkedAircraft.place(container, xf, team, af)
	if not af.pens_local.is_empty():
		container.add_child(Scatter.multi(AirfieldAssets.e_pen(), _to_world(axf, af.pens_local), 5000.0))
	if not af.nets_local.is_empty():
		container.add_child(Scatter.multi(AirfieldAssets.camo_net(team), _to_world(axf, af.nets_local), 3500.0))
	if not af.markers_local.is_empty():
		container.add_child(Scatter.multi(AirfieldAssets.boundary_marker(), _to_world(axf, af.markers_local), 2200.0))
	if lw:
		# tents and lorries in the tree line beyond each row of nets, a fuel-drum dump, an ops tent with the T
		var ex: float = L * 0.34
		var tents: Array = []
		for side in [-1.0, 1.0]:
			for i in 8:
				tents.append(Transform3D(Basis(Vector3.UP, PI * 0.5 + rng.randf_range(-0.3, 0.3)), Vector3(side * (ex + 70.0 + float(i % 2) * 14.0), 0.0, -L * 0.3 + float(i) * L * 0.08)))
		_props(container, "tent", AirfieldAssets.tent(team), _to_world(axf, tents), team, 3)
		var trucks: Array = []
		for i in 8:
			var tg: Vector3 = axf * Vector3((1.0 if i % 2 == 0 else -1.0) * (ex + rng.randf_range(40.0, 100.0)), 0, rng.randf_range(-L * 0.4, L * 0.4))
			trucks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(tg.x, y + 0.2, tg.z)))
		_props(container, "truck", _truck_mesh(team), trucks, team, 3)
		var drums: Array = []
		for i in 3:
			drums.append(Transform3D(Basis(), Vector3(-ex - 140.0 - float(i) * 22.0, 0.0, L * 0.35)))
		_props(container, "ammo", AirfieldAssets.fuel_tank(), _to_world(axf, drums), team, 3)
		var tcorner: Vector3 = axf * Vector3(-ex - 30.0, 0.0, -L * 0.2)
		container.add_child(Scatter.multi(AirfieldAssets.landing_t(), [Transform3D(Basis(Vector3.UP, af.rotation.y), Vector3(tcorner.x, y + 0.05, tcorner.z))], 3000.0))
		return
	# RAF grass station: hangar arc behind the apron, watch office + landing T, huts, fuel, lorries
	var rx: float = L * 0.38
	for i in 4:
		var hp: Vector3 = axf * Vector3(-rx - 175.0 - absf(float(i) - 1.5) * 18.0, 0, -165.0 + float(i) * 105.0)
		var h: GroundStructure = GroundStructure.create("hangar", team, hp, af.heading_deg + 90.0)
		h.is_mission_target = false
		container.add_child(h)
		h.position.y = y
	var tw_l := Vector3(-rx - 95.0, 0, 245.0)
	var tw: GroundStructure = GroundStructure.create("control_tower", team, axf * tw_l, af.heading_deg)
	container.add_child(tw)
	tw.position.y = y
	var tp: Vector3 = axf * (tw_l + Vector3(45.0, 0, 0))
	container.add_child(Scatter.multi(AirfieldAssets.landing_t(), [Transform3D(Basis(Vector3.UP, af.rotation.y), Vector3(tp.x, y + 0.05, tp.z))], 3000.0))
	var huts: Array = []
	for row in 4:
		for i in 9:
			huts.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-rx - 300.0 - float(row) * 26.0, 0.0, -230.0 + float(i) * 40.0)))
	_props(container, "hut", AirfieldAssets.nissen(team), _to_world(axf, huts), team, 4)
	for i in 4:
		var ft: GroundStructure = GroundStructure.create("fuel_tank", team, axf * Vector3(-rx - 250.0 - float(i) * 22.0, 0, 330.0), 0.0)
		container.add_child(ft)
		ft.position.y = y
	var trucks2: Array = []
	for i in 10:
		var tg2: Vector3 = axf * Vector3(rng.randf_range(-rx - 140.0, -rx - 60.0), 0, rng.randf_range(-230.0, 230.0))
		trucks2.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(tg2.x, y + 0.2, tg2.z)))
	_props(container, "truck", _truck_mesh(team), trucks2, team, 3)


## Airfield defences laid out the way the real ones were (photos and station plans): light AA - Bofors on RAF
## stations, 2 cm / 3.7 cm Flak on Luftwaffe fields - in sandbagged pits on a ring just outside the paved area,
## covering both runway approaches; machine-gun pits beside the dispersals; one heavy battery of four guns
## (3.7-inch / 88 mm) in a square with its command post 1.6-2.4 km out to the side; searchlights and (London
## sector stations) barrage balloons further out. Every spot is checked against what is already built - runways,
## taxiways, buildings, parked aircraft, dumps - and against water, so no gun sits on a taxiway or a hut.
func _airfield_defences(container: Node3D, af: Airfield, axf: Transform3D, team: String, id: String, balloons: int, spread: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + 11
	var occ: Array = _occupied(container)
	var ext: Vector2 = af.footprint_extent()
	var axis_yaw: float = af.rotation.y
	# light AA: 8 pits (Axis fields 9) on an ellipse just outside the paved footprint
	var n_light: int = 8 if team == "Allies" else 9
	for i in n_light:
		var a: float = TAU * (float(i) + rng.randf_range(-0.18, 0.18)) / float(n_light)
		for tries in 8:
			var grow: float = 60.0 + 30.0 * float(tries)
			var lp := Vector3(sin(a) * (ext.x + grow), 0.0, cos(a) * (ext.y + grow))
			var wp: Vector3 = axf * lp
			if _spot_free(wp, occ, 34.0) and GroundKit.raw_y(wp.x, wp.z) > 1.0:
				var g: AAGun = AAGun.create("bofors", team)
				_place(g, wp)
				container.add_child(g)
				occ.append(Vector3(wp.x, 12.0, wp.z))
				break
	# machine-gun pits beside the dispersal pads, on the outboard side
	var pads: Array = af.dispersal_world_points()
	var n_mg: int = mini(4, pads.size())
	for i in n_mg:
		var pad: Vector3 = pads[(i * maxi(pads.size() / maxi(n_mg, 1), 1) + rng.randi_range(0, 2)) % pads.size()]
		var out_dir: Vector3 = (pad - af.position)
		out_dir.y = 0.0
		out_dir = out_dir.normalized() if out_dir.length() > 1.0 else Vector3.RIGHT
		for tries in 6:
			var wp2: Vector3 = pad + out_dir * (40.0 + 14.0 * float(tries)) + out_dir.cross(Vector3.UP) * rng.randf_range(-20.0, 20.0)
			if _spot_free(wp2, occ, 22.0) and GroundKit.raw_y(wp2.x, wp2.z) > 1.0:
				var mg: AAGun = AAGun.create("mg", team)
				_place(mg, wp2)
				container.add_child(mg)
				occ.append(Vector3(wp2.x, 8.0, wp2.z))
				break
	# one heavy battery: four guns on a 44 m square round a sandbagged command post, out to one side of the field
	var done: bool = false
	for tries in 12:
		var side: float = 1.0 if (tries + absi(hash(id))) % 2 == 0 else -1.0
		var ang: float = axis_yaw + side * PI * 0.5 + rng.randf_range(-0.7, 0.7)
		var dist: float = rng.randf_range(1600.0, 2400.0)
		var c: Vector3 = af.position + Vector3(-sin(ang), 0.0, -cos(ang)) * dist
		var corners: Array = []
		for k in 4:
			var ca: float = ang + PI * 0.25 + PI * 0.5 * float(k)
			corners.append(c + Vector3(sin(ca), 0.0, cos(ca)) * 31.0)
		var ok: bool = GroundKit.raw_y(c.x, c.z) > 1.0 and not _in_runway_zone(c)
		for q in corners:
			ok = ok and GroundKit.raw_y((q as Vector3).x, (q as Vector3).z) > 1.0
		if not ok:
			continue
		for q2 in corners:
			var hv: AAGun = AAGun.create("88mm", team)
			_place(hv, q2)
			container.add_child(hv)
		var cp := Node3D.new()
		cp.position = Vector3(c.x, _y(c), c.z)
		cp.rotation.y = ang
		container.add_child(cp)
		GroundKit.box(cp, Vector3(7.0, 2.2, 5.0), Vector3(0.0, 1.1, 0.0), GroundKit.COL_SAND)                     # command post
		GroundKit.box(cp, Vector3(5.0, 0.6, 3.0), Vector3(0.0, 2.5, 0.0), GroundKit.COL_DARK.lightened(0.2))      # predictor roof
		GroundKit.box(cp, Vector3(3.0, 1.6, 2.0), Vector3(12.0, 0.8, 0.0), GroundKit.COL_SAND.darkened(0.1))      # ready-use ammo
		done = true
		break
	if not done:
		for p in _land_ring(af.position, 2, spread * 0.6, spread, rng):
			var hv2: AAGun = AAGun.create("88mm", team)
			_place(hv2, p)
			container.add_child(hv2)
	# searchlights and balloons further out, as before
	_defences(container, af.position, team, 0, 0, 2, balloons, spread, hash(id) + 5)


## Footprint of what is already built under `root` as [Vector3(x, radius, z)] in world space. Long strips (runways,
## taxiways, banks) are sampled along their length so they block a narrow band rather than a huge circle.
func _occupied(root: Node3D) -> Array:
	var out: Array = []
	for n in root.find_children("*", "", true, false):
		var xf: Transform3D = _rel_xf(n as Node, root)
		if n is MultiMeshInstance3D:
			var mmi := n as MultiMeshInstance3D
			var mm: MultiMesh = mmi.multimesh
			if mm == null or mm.mesh == null:
				continue
			var ab: AABB = mm.mesh.get_aabb()
			var r: float = maxf(ab.size.x, ab.size.z) * 0.5 + 2.0
			for i in mm.instance_count:
				var o: Vector3 = xf * mm.get_instance_transform(i).origin
				out.append(Vector3(o.x, r, o.z))
		elif n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var b: AABB = mi.mesh.get_aabb()
			var c: Vector3 = xf * b.get_center()
			var ax: Vector3 = xf.basis.x * b.size.x
			var az: Vector3 = xf.basis.z * b.size.z
			ax.y = 0.0
			az.y = 0.0
			var lx: float = ax.length()
			var lz: float = az.length()
			var long: Vector3 = ax if lx > lz else az
			var short: float = minf(lx, lz)
			var ll: float = long.length()
			if ll > short * 3.0 and ll > 30.0:
				var steps: int = int(ll / 15.0)
				for k in steps + 1:
					var o2: Vector3 = c + long * (float(k) / float(maxi(steps, 1)) - 0.5)
					out.append(Vector3(o2.x, short * 0.5 + 2.0, o2.z))
			else:
				out.append(Vector3(c.x, maxf(lx, lz) * 0.5 + 2.0, c.z))
	return out


static func _rel_xf(n: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


static func _spot_free(p: Vector3, occ: Array, clear: float) -> bool:
	for o in occ:
		var v: Vector3 = o
		if Vector2(p.x - v.x, p.z - v.z).length() < v.y + clear:
			return false
	return true


## Dressing for the "cross", "parallel" and "forward" layouts (airfield.gd). Local frame: -Z along the runway, west = -X.
func _dress_other_airfield(container: Node3D, af: Airfield, axf: Transform3D, y: float, team: String, rng: RandomNumberGenerator) -> void:
	var L: float = af.runway_length
	var style: String = af.style
	# parked aircraft on the pads and apron
	var xf: Array = []
	for pad in af.dispersal_world_points():
		if rng.randf() < 0.3:
			continue
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * 1.7), Vector3(pad.x, y + 0.4, pad.z)))
	ParkedAircraft.place(container, xf, team, af)
	var hx: float = -L * 0.13 - 260.0 if style == "cross" else -340.0
	var hz0: float = -150.0 if style == "cross" else -L * 0.1 - 200.0
	var n_hangars: int = 0 if style == "forward" else (4 if style == "cross" else 5)
	for i in n_hangars:
		var hp: Vector3 = axf * Vector3(hx, 0, hz0 + float(i) * 100.0)
		var h: GroundStructure = GroundStructure.create("hangar", team, hp, af.heading_deg + 90.0)
		h.is_mission_target = false
		container.add_child(h)
		h.position.y = y
	if style == "parallel":
		for i in n_hangars:
			var hp2: Vector3 = axf * Vector3(hx - 95.0, 0, hz0 + float(i) * 100.0 + 50.0)
			var h2: GroundStructure = GroundStructure.create("hangar", team, hp2, af.heading_deg + 90.0)
			h2.is_mission_target = false
			container.add_child(h2)
			h2.position.y = y
	var tw_local: Vector3 = Vector3(-L * 0.13 - 40.0, 0, 100.0) if style == "cross" else (Vector3(-120.0, 0, -L * 0.1 - 230.0) if style == "parallel" else Vector3(-60.0, 0, 60.0))
	var tw: GroundStructure = GroundStructure.create("control_tower", team, axf * tw_local, af.heading_deg)
	container.add_child(tw)
	tw.position.y = y
	var fx: float = hx - 70.0 if style != "forward" else -230.0
	for i in (4 if style != "forward" else 2):
		var ft: GroundStructure = GroundStructure.create("fuel_tank", team, axf * Vector3(fx, 0, -L * 0.3 + float(i) * 22.0), 0.0)
		container.add_child(ft)
		ft.position.y = y
	# huts (tents on forward strips): rows beyond the hangars
	var huts: Array = []
	var rows: int = 2 if style == "forward" else 4
	for row in rows:
		for i in (10 if style == "forward" else 9):
			var hxl: float = (-200.0 if style == "forward" else hx - 110.0) - float(row) * 26.0
			huts.append(Transform3D(Basis(Vector3.UP, PI * 0.5 + rng.randf_range(-0.2, 0.2)), Vector3(hxl, 0.0, -230.0 + float(i) * 36.0)))
	_props(container, "tent" if style == "forward" else "hut", AirfieldAssets.tent(team) if style == "forward" else AirfieldAssets.nissen(team), _to_world(axf, huts), team, 3)
	var trucks: Array = []
	for i in 12:
		var tg: Vector3 = axf * Vector3(rng.randf_range(hx + 40.0, hx + 160.0), 0, rng.randf_range(-260.0, 260.0))
		trucks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(tg.x, y + 0.2, tg.z)))
	_props(container, "truck", _truck_mesh(team), trucks, team, 3)
	var banks: Array = []
	for row in 3:
		for i in 5:
			var bp: Vector3 = axf * Vector3(260.0 + float(row) * 34.0, 0, 380.0 + float(i) * 36.0)
			banks.append(Transform3D(Basis(Vector3.UP, af.rotation.y + PI * 0.5), Vector3(bp.x, y, bp.z)))
	_props(container, "ammo", _bunker_bank_mesh(), banks, team, 5)


func _build_city(s: Dictionary) -> Node3D:
	var d: Dictionary = s["data"]
	var size: int = int(s["size"])
	var pos: Vector3 = s["pos"]
	# Buildings come from the land-cover tiles now (real built-up footprint), so only the site's
	# defences are built here.
	var container := Node3D.new()
	var team: String = _team_of_pos(pos)
	var id: String = d["id"]
	var radius: float = 90.0 + float(size) * 85.0
	var n88: int = 0 if size < 3 else (size - 2)
	var nb: int = size if size >= 2 else 1
	var lights: int = 0 if size < 2 else size + 2
	_defences(container, pos, team, n88, nb, lights, 0, radius * 1.1, hash(id) + 11)
	_balloon_barrage(container, pos, id, size, radius * 1.25, team)
	# Dense historic core (terraced street grid, taller blocks in the middle). The land-cover tiles
	# leave this disc empty (see _exclude in _register_cities) and fill the suburbs around it.
	container.add_child(Scatter.make_town(pos, size, hash(id) + 77, true))
	_city_skyline(container, pos, size, id, radius)
	_city_landmarks(container, d, s.get("lm", {}), s.get("lm_json", {}))
	return container


## Church spires in the larger towns and chimney stacks in the industrial cities, so they read from the air.
const INDUSTRIAL_CITIES := ["essen", "duisburg", "dortmund", "dusseldorf", "cologne", "birmingham", "coventry", "stoke", "wolverhampton",
	"liege", "charleroi", "antwerp", "rotterdam", "eindhoven_city", "nottingham", "derby", "bristol", "cardiff", "leicester"]


func _city_skyline(container: Node3D, pos: Vector3, size: int, id: String, radius: float) -> void:
	if size < 3:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + 5
	for k in (1 if size == 3 else (2 if size == 4 else 3)):
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(0.05, 0.5) * radius * 0.6
		var cp := Vector3(pos.x + cos(a) * r, 0.0, pos.z + sin(a) * r)
		var ch: Node3D = Landmarks.church(rng.randf_range(1.3, 2.0))
		ch.position = Vector3(cp.x, GroundKit.ground_y(cp.x, cp.z), cp.z)
		ch.rotation.y = rng.randf() * TAU
		container.add_child(ch)
	if id in INDUSTRIAL_CITIES:
		for k2 in (2 + size):
			var a2: float = rng.randf() * TAU
			var r2: float = rng.randf_range(0.5, 1.0) * radius * 0.7
			var sp := Vector3(pos.x + cos(a2) * r2, 0.0, pos.z + sin(a2) * r2)
			var y0: float = GroundKit.ground_y(sp.x, sp.z)
			var h: float = rng.randf_range(45.0, 85.0)
			GroundKit.cyl(container, 1.6, 2.6, h, Vector3(sp.x, y0 + h * 0.5, sp.z), Color(0.42, 0.3, 0.26), Vector3.ZERO, 8)
			GroundKit.cyl(container, 1.8, 1.8, 3.0, Vector3(sp.x, y0 + h + 1.0, sp.z), Color(0.16, 0.16, 0.17), Vector3.ZERO, 8)


## Phase 5.2: landmark `kind`s (data/landmarks_1940.json) that stand on or over water, so they are pinned to sea level
## y = 0 rather than draped on the terrain, and their long axis follows the local coastline: a pier runs out to sea,
## a breakwater / mole / dock wall runs parallel to the shore.
const LM_SEA_KINDS := ["docks", "harbour_works", "pier"]
## Open-sea marks with no terrain-drapable footing that predate the json set (kept alongside the json kinds above).
## Landmark bridges that are turned to cross their river (GroundKit.river_axis).
const RIVER_BRIDGES := ["ludendorff_bridge", "nijmegen_bridge", "arnhem_bridge"]
const LM_SEA_IDS := ["eddystone", "needles", "arromanches_mulberry"]
## Curated label -> id fallbacks for cities[].landmark wording that differs from the builder name.
const LM_ALIASES := {
	"beffroi": "lille_hotel_de_ville",
	"hotel de ville belfry": "beffroi_calais",
	"grand place": "brussels_hotel_de_ville",
	"hotel de ville": "lille_hotel_de_ville",
}
static var _lm_kind_cache: Dictionary = {}
static var _lm_json_cache: Dictionary = {}


## id -> `kind` for data/landmarks_1940.json (cached); "" if unknown.
static func _landmark_kind(id: String) -> String:
	if _lm_kind_cache.is_empty():
		var f: FileAccess = FileAccess.open("res://data/landmarks_1940.json", FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			f = null
			if d is Dictionary:
				for e in (d as Dictionary).get("landmarks", []):
					var ed: Dictionary = e
					_lm_kind_cache[str(ed.get("id", ""))] = str(ed.get("kind", ""))
	return str(_lm_kind_cache.get(id, ""))


## id -> {name, lat, lon} for data/landmarks_1940.json (cached), used by _city_landmarks for fallback placement.
static func _landmark_json_index() -> Dictionary:
	if _lm_json_cache.is_empty():
		var f: FileAccess = FileAccess.open("res://data/landmarks_1940.json", FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			f = null
			if d is Dictionary:
				for e in (d as Dictionary).get("landmarks", []):
					var ed: Dictionary = e
					var lid: String = str(ed.get("id", ""))
					_lm_json_cache[lid] = {"name": str(ed.get("name", lid)), "lat": float(ed.get("lat", 0.0)), "lon": float(ed.get("lon", 0.0))}
	return _lm_json_cache


## True when a landmark stands on/over water and is pinned to sea level (y = 0).
static func _landmark_at_sea(id: String) -> bool:
	return id in LM_SEA_IDS or _landmark_kind(id) in LM_SEA_KINDS


## Heading (degrees) for a landmark: tower_bridge/big_ben keep their fixed 90 deg, sea landmarks align to the local
## sea direction (a pier points out to sea, a breakwater/mole/dock wall runs parallel to the coast), else 0 (as built).
static func _landmark_heading(id: String, pos: Vector3) -> float:
	if id in ["tower_bridge", "big_ben"]:
		return 90.0
	if id in RIVER_BRIDGES:
		var ax: Vector3 = GroundKit.river_axis(pos, 260.0)
		if ax != Vector3.ZERO:
			var p := Vector3(-ax.z, 0.0, ax.x)      # the span runs across the river
			return rad_to_deg(atan2(-p.z, p.x))
	var kind: String = _landmark_kind(id)
	if kind in LM_SEA_KINDS:
		var sea: Vector3 = GroundKit.water_dir(pos, 900.0)
		if sea != Vector3.ZERO:
			var base: float = WorldCoords.dir_to_heading(sea)
			return base if kind == "pier" else base + 90.0
	return 0.0


## Phase 5.3: consume cities[].landmark (semicolon-separated names). Each name is resolved to a landmark id; a
## landmark that already has a features[] row is left to its streamed `lm_<id>` site (no double placement), and only
## a name whose features row is absent is placed here, at the landmark's own lat/lon from data/landmarks_1940.json,
## using the same deterministic hash(id) seeding as the rest of the city build.
func _city_landmarks(container: Node3D, d: Dictionary, lm: Dictionary, lm_json: Dictionary) -> void:
	var names: String = str(d.get("landmark", ""))
	if names.is_empty():
		return
	var index: Dictionary = _landmark_name_index(lm, lm_json)
	var placed: int = 0
	for raw in names.split(";"):
		var nm: String = _norm_landmark_name(str(raw))
		if nm.is_empty():
			continue
		var lid: String = _resolve_landmark_id(nm, index)
		if lid.is_empty():
			continue
		if lm.has(lid):
			continue                              # already streamed by _register_features -> do not double-place
		if not lm_json.has(lid):
			continue                              # no coordinates known for an un-streamed id
		var e: Dictionary = lm_json[lid]
		var lp: Vector3 = WorldCoords.latlon_to_world(float(e["lat"]), float(e["lon"]))
		var node: Node3D = Landmarks.build(lid)
		if node == null:
			continue
		node.position = Vector3(lp.x, 0.0 if _landmark_at_sea(lid) else _y(lp), lp.z)
		var heading: float = _landmark_heading(lid, lp)
		if heading != 0.0:
			node.rotation.y = deg_to_rad(heading)
		container.add_child(node)
		placed += 1
	if placed > 0:
		GroundKit.lp("  _city_landmarks(%s): %d per-city landmark(s) placed" % [str(d.get("id", "")), placed])


## normalised label / id -> landmark id, built from the features rows (id + name) and data/landmarks_1940.json.
static func _landmark_name_index(lm: Dictionary, lm_json: Dictionary) -> Dictionary:
	var idx: Dictionary = {}
	for k in lm.keys():
		var kk: String = str(k)
		idx[_norm_landmark_name(kk)] = kk
		var fn: String = _norm_landmark_name(str((lm[k] as Dictionary).get("name", "")))
		if not fn.is_empty():
			idx[fn] = kk
	for k in lm_json.keys():
		var kk: String = str(k)
		idx[_norm_landmark_name(kk)] = kk
		var jn: String = _norm_landmark_name(str((lm_json[k] as Dictionary).get("name", "")))
		if not jn.is_empty():
			idx[jn] = kk
	return idx


## Reduce a landmark label to a comparable form: drop any parenthetical, lower-case, non-alphanumeric -> spaces.
static func _norm_landmark_name(s: String) -> String:
	var t: String = s
	var op: int = t.find("(")
	if op >= 0:
		t = t.substr(0, op)
	t = t.to_lower()
	var out: String = ""
	for i in t.length():
		var c: String = t[i]
		out += c if ((c >= "a" and c <= "z") or (c >= "0" and c <= "9")) else " "
	return " ".join(out.split(" ", false))


## Resolve a normalised city landmark label to a landmark id: exact, then substring (longest key), then the curated
## alias table, then best shared-word overlap (>= 2 words, deterministic).
static func _resolve_landmark_id(nm: String, index: Dictionary) -> String:
	if nm.is_empty():
		return ""
	if index.has(nm):
		return str(index[nm])
	var best_key: String = ""
	for k in index.keys():
		var ks: String = str(k)
		if ks.is_empty():
			continue
		if (nm.contains(ks) or ks.contains(nm)) and ks.length() > best_key.length():
			best_key = ks
	if best_key != "":
		return str(index[best_key])
	var alias: String = str(LM_ALIASES.get(nm, ""))
	if alias != "":
		return alias
	var words: Dictionary = {}
	for w in nm.split(" ", false):
		if str(w).length() >= 3:
			words[str(w)] = true
	var bi: String = ""
	var bs: int = 1
	for k in index.keys():
		var ks: String = str(k)
		var sc: int = 0
		for w in words.keys():
			if ks.contains(str(w)):
				sc += 1
		var lid: String = str(index[ks])
		if sc > bs or (sc == bs and (bi == "" or lid < bi)):
			bs = sc
			bi = lid
	return bi


func _build_landmark(s: Dictionary) -> Node3D:
	var container := Node3D.new()
	var lmk: Node3D = Landmarks.build(str(s["id"]))
	if lmk == null:
		return container
	var pos: Vector3 = s["pos"]
	var lid: String = str(s["id"])
	var sea_lm: bool = _landmark_at_sea(lid)
	lmk.position = Vector3(pos.x, 0.0 if sea_lm else _y(pos), pos.z)
	var heading: float = _landmark_heading(lid, pos)
	if heading != 0.0:
		lmk.rotation.y = deg_to_rad(heading)
	container.add_child(lmk)
	return container


func _build_beach(s: Dictionary) -> Node3D:
	var pos: Vector3 = s["pos"]
	var r: float = float(s["radius"])
	var count: int = int(clampf(r / 3.5, 40.0, 220.0))
	var team_allies: bool = GroundKit.side_at(pos) == "Allies"
	var container: Node3D = Scatter.make_beach_defences(pos, r, count, hash(str(s["id"])), not team_allies)
	if not team_allies:
		_defences(container, pos, "Axis", 1, 2, 0, 0, r * 0.7, hash(str(s["id"])) + 3)
	return container


func _build_coast_cluster(s: Dictionary) -> Node3D:
	var pos: Vector3 = s["pos"]
	var team: String = str(s["team"])
	var container := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(s["key"]))
	var shore: Array = Scatter.find_shore(pos, 450.0, 8, rng)
	if shore.is_empty():
		return container
	var main_pt: Dictionary = shore[0]
	var base: Vector3 = main_pt["pos"]
	var sea_h: float = WorldCoords.dir_to_heading(main_pt["sea"])
	var bunker_team: String = team
	for i in mini(shore.size(), 6 if team == "Axis" else 3):
		var d: Dictionary = shore[i]
		var kind: String = "bunker" if (i == 0 or i == 3) else "pillbox"
		var st: GroundStructure = GroundStructure.create(kind, bunker_team, (d["pos"] as Vector3) - (d["sea"] as Vector3) * 15.0, WorldCoords.dir_to_heading(d["sea"]))
		container.add_child(st)
	if team == "Axis":
		container.add_child(Scatter.make_beach_defences(base, 520.0, 34, rng.randi(), false))
		if rng.randf() < 0.5:
			var wur: GroundStructure = GroundStructure.create("radar_wurz", "Axis", base - (main_pt["sea"] as Vector3) * 90.0, sea_h)
			container.add_child(wur)
	_defences(container, base, team, 1 if rng.randf() < 0.6 else 0, 2, 0, 0, 170.0, rng.randi())
	return container


func _target_team_defences(type: String) -> Array:
	# [n88, nbofors, nlights, nballoons, spread]
	match type:
		"port":
			return [2, 3, 2, 4, 300.0]
		"factory":
			return [1, 2, 1, 3, 220.0]
		"rail_yard":
			return [1, 2, 1, 0, 200.0]
		"bridge":
			return [1, 2, 0, 2, 180.0]
		"v1_site":
			return [2, 3, 1, 0, 240.0]
		"battery":
			return [1, 2, 0, 0, 170.0]
		"radar":
			return [0, 1, 0, 0, 120.0]
	return [0, 1, 0, 0, 120.0]


func _build_target(s: Dictionary) -> Node3D:
	var id: String = s["id"]
	var d: Dictionary = s["data"]
	var type: String = str(d["type"])
	var team: String = str(s["team"])
	var pos: Vector3 = s["pos"]
	var container := Node3D.new()
	var main: Node = null
	var wrecked: bool = _destroyed.has(id)
	match type:
		"convoy_route":
			main = _build_convoy_target(container, id, d, team)
		_:
			var skind: String = "bunker"
			var heading: float = -1.0
			match type:
				"battery":
					skind = "battery"
				"radar":
					skind = "radar_ch" if id.ends_with("_ch") else "radar_wurz"
				"port":
					skind = "port"
				"factory":
					var nm: String = str(d.get("name", "")).to_lower()
					if nm.contains("gas"):
						skind = "gasworks"
					elif nm.contains("collier"):
						skind = "colliery"
					elif nm.contains("goods") or nm.contains("marshalling"):
						skind = "goods_yard"
					elif nm.contains("refinery"):
						skind = "refinery"
					elif id.begins_with("oil_"):
						skind = "oil_depot"
					else:
						skind = "factory"
				"oil_depot":
					skind = "oil_depot"
				"rail_yard":
					var nm2: String = str(d.get("name", "")).to_lower()
					if nm2.contains("good") or nm2.contains("marshalling"):
						skind = "goods_yard"
					elif nm2.contains("shed") or nm2.contains("engine"):
						skind = "engine_shed"
					else:
						skind = "rail_yard"
				"bridge":
					skind = "bridge"
					var near: Array = TransportNetwork.routes_near("roads", pos, 120.0)
					if not near.is_empty():
						var rp: RoutePath = near[0]
						heading = WorldCoords.dir_to_heading(rp.tangent(rp.closest(pos).x)) - 90.0
				"v1_site":
					skind = "v1_site"
			var st: GroundStructure = GroundStructure.create(skind, team, pos, heading)
			st.target_id = id
			st.display_name = str(d.get("name", id))
			st.is_mission_target = true
			st.start_wrecked = wrecked
			if skind == "battery":
				st.guns = 6 if id == "battery_pointe_du_hoc" else (3 if id == "battery_lindemann" else 4)
			st.destroyed.connect(func(_n: Node, _k: Node) -> void: _destroyed[id] = true)
			container.add_child(st)
			main = st
			if type == "port":
				_moor_ships(container, pos, team, st.heading_deg)
			var df: Array = _target_team_defences(type)
			_ruins(container, pos, 5 if wrecked else (3 if type in ["port", "factory", "rail_yard"] else 2), 70.0, 260.0, hash(id) + 11)
			if not (wrecked):
				var scale_n: float = 1.0
				_defences(container, pos, team, int(df[0]), int(df[1]), int(df[2]), int(df[3]) if team == "Allies" else 0, float(df[4]) * scale_n, hash(id))
	s["main"] = main
	_target_main[id] = main
	return container


func _moor_ships(container: Node3D, pos: Vector3, team: String, heading: float) -> void:
	var fwd: Vector3 = WorldCoords.heading_to_dir(heading)
	var side := Vector3(-fwd.z, 0, fwd.x)
	for i in 2:
		var p: Vector3 = pos + fwd * 118.0 + side * (float(i) * 50.0 - 25.0)
		if GroundKit.raw_y(p.x, p.z) > 0.2:
			continue
		var route: RoutePath = RoutePath.from_points(PackedVector3Array([p, p + side * 8.0]))
		var sh: GroundShip = GroundShip.create("freighter" if i == 0 else "fishing_boat", team, route, 0.0, 0.01)
		sh.speed = 0.0
		sh.position = Vector3(p.x, 0.1, p.z)
		sh.rotation.y = -deg_to_rad(heading) + PI * 0.5
		container.add_child(sh)


func _build_convoy_target(container: Node3D, id: String, d: Dictionary, team: String) -> Node:
	var route: RoutePath = RoutePath.from_latlon(d["path"])
	var mid: Vector3 = route.sample(route.length * 0.5)
	var naval: bool = GroundKit.raw_y(mid.x, mid.z) < 0.5
	var comp: String = "mixed"
	if naval:
		match id:
			"convoy_neptune", "convoy_utah", "convoy_omaha", "convoy_gold", "convoy_sword", "convoy_mulberry":
				comp = "neptune"
			"convoy_la_panne":
				comp = "dunkirk"
			"convoy_dunkirk_evac":
				comp = "dunkirk"
			"convoy_antwerp_ostend":
				comp = "coastal"
	else:
		comp = "supply" if id == "convoy_lille_calais" else ("tanks" if id in ["convoy_21panzer", "convoy_dunkirk_perimeter"] else "mixed")
	var cv: Convoy = Convoy.create(team, route, naval, comp, 120.0, -1.0)
	cv.target_id = id
	cv.display_name = str(d.get("name", id))
	cv.is_mission_target = true
	cv.wrap = false
	cv.spacing = 50.0 if naval else 24.0
	cv.destroyed.connect(func(_n: Node, _k: Node) -> void: _destroyed[id] = true)
	container.add_child(cv)
	if not naval and team == "Axis":
		pass
	return cv


func _build_road_traffic(s: Dictionary) -> Node3D:
	var container := Node3D.new()
	var rp: RoutePath = s["route"]
	var fp: Vector3 = focus.global_position if focus else Vector3.ZERO
	var c: Vector2 = rp.closest(fp)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s["seed"]) + int(Time.get_ticks_msec() / 60000)
	var here: Vector3 = rp.sample(c.x)
	var team: String = _team_of_pos(here)
	var comps: Array = ["supply", "mixed", "troops", "tanks"] if team == "Axis" else ["supply", "mixed", "troops"]
	var cv: Convoy = Convoy.create(team, rp, false, comps[rng.randi() % comps.size()], c.x + rng.randf_range(-300.0, 300.0), rng.randf_range(7.0, 12.0))
	cv.spacing = 22.0
	container.add_child(cv)
	s["main"] = cv
	return container


func _build_rail_traffic(s: Dictionary) -> Node3D:
	var container := Node3D.new()
	var rp: RoutePath = s["route"]
	var fp: Vector3 = focus.global_position if focus else Vector3.ZERO
	var c: Vector2 = rp.closest(fp)
	var team: String = _team_of_pos(rp.sample(c.x))
	var tr: Train = Train.create(team, rp, c.x + 200.0, 14.0)
	container.add_child(tr)
	s["main"] = tr
	return container


func _build_sea_traffic(s: Dictionary) -> Node3D:
	var container := Node3D.new()
	var lane: Dictionary = s["lane"]
	var rp: RoutePath = s["route"]
	var fp: Vector3 = focus.global_position if focus else Vector3.ZERO
	var c: Vector2 = rp.closest(fp)
	var cv: Convoy = Convoy.create(str(lane["team"]), rp, true, str(lane["comp"]), c.x, -1.0)
	container.add_child(cv)
	s["main"] = cv
	return container


# ================================================================== public API
func get_target_info(id: String) -> Dictionary:
	return _target_info.get(id, {})


## Raid objectives owned by `owner_side`: mission targets (factories, refineries, ports, rail yards), the industrial
## areas and the larger towns. Each: {id, name, pos, kind}.
func raid_targets(owner_side: String) -> Array:
	var out: Array = []
	for id in _target_info.keys():
		var t: Dictionary = _target_info[id]
		if t["team"] == owner_side and str(t["type"]) in ["factory", "rail_yard", "port", "v1_site", "dam", "decoy", "oil", "aircraft"] and not _destroyed.has(id):
			out.append({"id": id, "name": t["name"], "pos": t["pos"], "kind": t["type"]})
	for ind in industry_sites:
		if ind["team"] == owner_side:
			out.append({"id": ind["id"], "name": ind["name"], "pos": ind["pos"], "kind": "industry"})
	for c in loc.get("cities", []):
		if not bool(c.get("in_bounds", true)) or int(c.get("size", 1)) < 3:
			continue
		var cp: Vector3 = _ll(c)
		if GroundKit.side_at(cp) == owner_side:
			out.append({"id": c["id"], "name": str(c.get("name", c["id"])), "pos": cp, "kind": "city"})
	return out


## Airfield data (id, name, pos, heading) for one air force ("RAF" or "Luftwaffe"), loaded or not.
func airfield_sites(air_force: String) -> Array:
	var out: Array = []
	for a in loc.get("airfields", []):
		if not bool(a.get("in_bounds", true)) or ("RAF" if airfield_team(a) == "Allies" else "Luftwaffe") != air_force:
			continue
		out.append({"id": str(a["id"]), "name": str(a.get("name", a["id"])), "pos": _ll(a), "heading": float(a.get("heading_deg", 0.0))})
	return out


func targets_for_side(owner_side: String, types: Array = []) -> Array:
	var out: Array = []
	for id in _target_info.keys():
		var t: Dictionary = _target_info[id]
		if t["team"] == owner_side and (types.is_empty() or t["type"] in types):
			out.append(id)
	return out


## Force-spawn (and pin) a target; returns its mission_target node (GroundStructure or Convoy).
func spawn_target(id: String) -> Node:
	var key: String = "tgt_" + id
	if not _site_by_key.has(key):
		return null
	var s: Dictionary = _site_by_key[key]
	s["pin"] = true
	_build_site(s)
	return s["main"]


func get_target_node(id: String) -> Node:
	var n: Variant = _target_main.get(id)
	return n if n != null and is_instance_valid(n) else null


func get_airfield(id: String) -> Airfield:
	if airfields.has(id) and is_instance_valid(airfields[id]):
		return airfields[id]
	var key: String = "af_" + id
	if not _site_by_key.has(key):
		return null
	var s: Dictionary = _site_by_key[key]
	s["pin"] = true
	_build_site(s)
	return airfields.get(id)


## Spawn a quick demo set around `center` for testing (AA nest, train, tank convoy, bunker, ship).
func spawn_demo(center: Vector3, enemy_team: String = "Axis", heading_dir: Vector3 = Vector3(0, 0, -1)) -> Node3D:
	var root := Node3D.new()
	root.name = "GroundDemo"
	add_child(root)
	var side := Vector3(-heading_dir.z, 0, heading_dir.x)
	var base: Vector3 = center + heading_dir * 1400.0
	for i in 3:
		var g: AAGun = AAGun.create("bofors", enemy_team)
		_place(g, base + side * (float(i) * 40.0 - 40.0))
		root.add_child(g)
	var g88: AAGun = AAGun.create("88mm", enemy_team)
	_place(g88, base + side * 120.0)
	root.add_child(g88)
	var sl: Searchlight = Searchlight.create(enemy_team)
	_place(sl, base - side * 90.0)
	root.add_child(sl)
	var tpts := PackedVector3Array([base + side * 300.0, base + side * 300.0 + heading_dir * 500.0, base + side * 300.0 + heading_dir * 700.0 + side * 200.0])
	var cv: Convoy = Convoy.create(enemy_team, RoutePath.from_points(tpts), false, "mixed", 60.0, 9.0)
	cv.target_id = "demo_convoy"
	root.add_child(cv)
	var rpts := PackedVector3Array([base - side * 350.0, base - side * 350.0 + heading_dir * 300.0, base - side * 380.0 + heading_dir * 900.0])
	var tr: Train = Train.create(enemy_team, RoutePath.from_points(rpts), 100.0, 16.0)
	root.add_child(tr)
	var bk: GroundStructure = GroundStructure.create("bunker", enemy_team, base + heading_dir * 120.0, 0.0)
	bk.target_id = "demo_bunker"
	bk.is_mission_target = true
	root.add_child(bk)
	for i in 3:
		var tk: GroundVehicle = GroundVehicle.create(["tiger", "panzer4", "sherman"][i], enemy_team, null, 0.0, 0.0, "fire")
		_place(tk, base + side * (float(i) * 30.0 + 200.0) + heading_dir * 200.0)
		root.add_child(tk)
	var p0: Vector3 = cv.get_center()
	var t0: Vector3 = tr.get_center()
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		print("DEMO convoy moved %.1f, train moved %.1f, AA tracers/flak shells seen: %d" % [cv.get_center().distance_to(p0), tr.get_center().distance_to(t0), GroundKit.shells_fired]))
	return root


# ================================================================== debug / automation
func _find_hud() -> Node:
	for c in world_root.get_children():
		if c is HUD:
			return c
	return null


func _parse_debug_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--wp-demo":
			var pl: Node3D = GroundKit.player_node()
			if pl:
				var f: Vector3 = -pl.global_transform.basis.z
				f.y = 0.0
				spawn_demo(pl.global_position, "Axis" if str(pl.get("team")) == "Allies" else "Allies", f.normalized())
		elif a.begins_with("--wp-mode="):
			_start_debug_mode(a.substr(10))
		elif a == "--wp-auto":
			var md: Node = world_root.get_node_or_null("Mode")
			if md is ModeBase:
				(md as ModeBase).mission_complete.connect(func(ok: bool, st: Dictionary) -> void: print("MISSION COMPLETE success=%s stats=%s" % [ok, st]))
		elif a == "--wp-peace":
			GroundKit.peace = true
		elif a == "--wp-night":
			TimeOfDay.set_preset("night")


func _start_debug_mode(spec: String) -> void:
	var parts: PackedStringArray = spec.split(":")
	var pl: Node3D = GroundKit.player_node()
	var hud: Node = _find_hud()
	if pl == null:
		push_warning("WorldPopulator: no player for --wp-mode")
		return
	var side: String = str(pl.get("team"))
	var mode: ModeBase = null
	match parts[0]:
		"bombing":
			var ids: Array = [parts[1]] if parts.size() > 1 else []
			mode = BombingMode.create(ids, side)
		"ground_attack":
			mode = GroundAttackMode.create(parts[1] if parts.size() > 1 else "normandy", side)
		"hist":
			if parts.size() > 2:
				side = parts[2]
			mode = HistoricalMissions.create(parts[1] if parts.size() > 1 else "dday_1944", side)
	if mode == null:
		return
	mode.setup(world_root, pl, hud)
	world_root.add_child(mode)
	mode.mission_complete.connect(func(ok: bool, st: Dictionary) -> void: print("MISSION COMPLETE success=%s stats=%s" % [ok, st]))
	mode.start()
	print("Started mode ", spec)



