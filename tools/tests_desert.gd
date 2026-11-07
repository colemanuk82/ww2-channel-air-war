extends Node
## Desert map checks (headless). Its own scene, so tools/tests.gd stays as it is:
##   godot --headless --path . scenes/tests_desert.tscn
## Covers MapDef and WorldCoords for the desert and channel maps, the desert data files, the land-cover class ids,
## the desert tracks, and that switching GameState.current_map back to channel restores the Channel values exactly.

const DESERT_DIR := "res://data/desert"
const LANDCOVER_IDS: Array = [0, 10, 20, 30, 40, 50, 60, 80, 90, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121]

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var date_before: String = str(GameState.era_date)
	_test_map_def()
	_test_world_coords()
	_test_desert_files()
	_test_desert_locations()
	_test_landcover_ids()
	_test_tracks()
	_test_ground_ownership()
	_test_life_data()
	_test_campaign_targets()
	_test_dune_shape()
	_test_rescue_text()
	_test_map_switch()
	GameState.era_date = date_before
	GameState.current_map = "channel"   # always leave the game on Channel
	print("\nTESTS %s  (%d passed, %d failed)" % ["FAILED" if _failed > 0 else "OK", _passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", what)
	return ok


func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


func _read_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if d is Dictionary:
		return d
	return {}


func _test_map_def() -> void:
	print("-- map definitions")
	var d: MapDef = MapDef.by_id("desert")
	_check(d.id == "desert" and d.name == "Desert", "desert map id and name")
	_check(d.origin_lat == 33.75 and d.origin_lon == 19.25, "desert origin is 33.75, 19.25")
	_check(d.lat_min == 30.0 and d.lat_max == 37.5 and d.lon_min == 8.0 and d.lon_max == 30.5, "desert bounds 30..37.5 N, 8..30.5 E")
	_check(d.heightmap_dir == "res://data/desert" and d.osm_dir == "res://data/desert/osm", "desert data folders")
	_check(d.locations_file == "res://data/desert/locations.json", "desert locations file")
	_check(d.lat_min < d.origin_lat and d.origin_lat < d.lat_max and d.lon_min < d.origin_lon and d.origin_lon < d.lon_max, "desert origin lies inside its bounds")
	var c: MapDef = MapDef.by_id("channel")
	_check(c.id == "channel" and c.origin_lat == 50.30 and c.origin_lon == 0.0, "channel origin 50.30, 0.00")
	_check(c.lat_min == 48.9 and c.lat_max == 53.0 and c.lon_min == -4.6 and c.lon_max == 9.0, "channel bounds 48.9..53.0 N, -4.6..9.0 E")
	_check(c.heightmap_dir == "res://data/heightmap" and c.osm_dir == "res://data/osm" and c.locations_file == "res://data/locations.json", "channel data folders")
	_check(MapDef.by_id("bogus").id == MapDef.DEFAULT_ID, "unknown map id gives channel")


func _test_world_coords() -> void:
	print("-- world coordinates")
	GameState.current_map = "desert"
	_check(WorldCoords.heightmap_dir() == "res://data/desert", "WorldCoords heightmap folder on desert")
	_check(WorldCoords.osm_dir() == "res://data/desert/osm", "WorldCoords osm folder on desert")
	_check(WorldCoords.locations_path() == "res://data/desert/locations.json", "WorldCoords locations path on desert")
	var origin: Vector3 = WorldCoords.latlon_to_world(33.75, 19.25)
	_check(origin.length() < 1e-3, "desert origin maps to world (0, 0, 0)")
	var p: Vector3 = WorldCoords.latlon_to_world(36.8483, 10.227)
	var back: Vector2 = WorldCoords.world_to_latlon(p)
	_check(absf(back.x - 36.8483) < 1e-6 and absf(back.y - 10.227) < 1e-6, "desert lat/lon round trip (Tunis)")
	_check(WorldCoords.is_in_bounds(origin), "desert origin is in bounds")
	_check(not WorldCoords.is_in_bounds(WorldCoords.latlon_to_world(50.3, 0.0)), "London is outside desert bounds")
	var wb: Rect2 = WorldCoords.world_bounds()
	_check(wb.size.x > 0.0 and wb.size.y > 0.0, "desert world bounds have a size")
	GameState.current_map = "channel"
	_check(WorldCoords.heightmap_dir() == "res://data/heightmap", "WorldCoords heightmap folder on channel")
	_check(WorldCoords.osm_dir() == "res://data/osm", "WorldCoords osm folder on channel")
	_check(WorldCoords.locations_path() == "res://data/locations.json", "WorldCoords locations path on channel")


func _test_desert_files() -> void:
	print("-- desert data files")
	for fn in ["region_height.png", "region_meta.json", "region_landcover.json", "region_landcover.bin", "tracks.json", "locations.json"]:
		_check(FileAccess.file_exists(DESERT_DIR + "/" + fn), "desert file %s exists" % fn)
	var meta: Dictionary = _read_json(DESERT_DIR + "/region_meta.json")
	_check(not meta.is_empty(), "region_meta.json parses")
	var w: int = int(meta.get("width", 0))
	var h: int = int(meta.get("height", 0))
	var d: MapDef = MapDef.by_id("desert")
	_check(w > 0 and h > 0, "region_meta.json has a grid size (%dx%d)" % [w, h])
	_check(float(meta.get("lat_min", 0.0)) == d.lat_min and float(meta.get("lat_max", 0.0)) == d.lat_max and float(meta.get("lon_min", 0.0)) == d.lon_min and float(meta.get("lon_max", 0.0)) == d.lon_max, "region_meta.json bounds match the desert map")
	var img: Image = Image.load_from_file(DESERT_DIR + "/region_height.png")
	_check(img != null and img.get_width() == w and img.get_height() == h, "region_height.png is %dx%d" % [w, h])


func _test_desert_locations() -> void:
	print("-- desert locations")
	var loc: Dictionary = _read_json(DESERT_DIR + "/locations.json")
	var afs: Array = loc.get("airfields", [])
	_check(afs.size() > 0, "desert locations has airfields (%d)" % afs.size())
	var d: MapDef = MapDef.by_id("desert")
	for a in afs:
		var ad: Dictionary = a
		var id: String = str(ad.get("id", "?"))
		var lat: Variant = ad.get("lat")
		var lon: Variant = ad.get("lon")
		var nums: bool = _is_num(lat) and _is_num(lon)
		_check(nums, "airfield %s has numeric lat and lon" % id)
		if nums:
			var la: float = float(lat)
			var lo: float = float(lon)
			_check(la >= d.lat_min and la <= d.lat_max and lo >= d.lon_min and lo <= d.lon_max, "airfield %s is inside the desert bounds" % id)
		_check(_is_num(ad.get("heading_deg")), "airfield %s has a numeric heading" % id)


func _test_landcover_ids() -> void:
	print("-- land cover classes")
	var lc: Dictionary = _read_json(DESERT_DIR + "/region_landcover.json")
	var w: int = int(lc.get("width", 0))
	var h: int = int(lc.get("height", 0))
	var classes: Dictionary = lc.get("classes", {})
	_check(not classes.is_empty(), "region_landcover.json lists its classes")
	for k in classes.keys():
		_check(LANDCOVER_IDS.has(int(str(k))), "class %s is in the known set" % str(k))
	var grid: PackedByteArray = FileAccess.get_file_as_bytes(DESERT_DIR + "/region_landcover.bin")
	_check(grid.size() == w * h, "region_landcover.bin has %d cells (got %d)" % [w * h, grid.size()])
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(256)
	seen.fill(0)
	for b in grid:
		seen[b] = 1
	var bad: Array = []
	for v in 256:
		if seen[v] == 1 and not LANDCOVER_IDS.has(v):
			bad.append(v)
	_check(bad.is_empty(), "every land cover cell is a known class (unknown: %s)" % str(bad))


func _test_tracks() -> void:
	print("-- desert tracks")
	var tr: Dictionary = _read_json(DESERT_DIR + "/tracks.json")
	_check(not tr.is_empty(), "tracks.json parses")
	var lines: Array = tr.get("lines", [])
	_check(lines.size() > 0, "tracks.json has lines (%d)" % lines.size())
	var ok_lines: bool = true
	for ln in lines:
		var ld: Dictionary = ln
		var pts: Array = ld.get("pts", [])
		if ld.get("k") != "track" or pts.size() < 2:
			ok_lines = false
	_check(ok_lines, "every track line is kind track with at least two points")


## Desert ownership moves with the campaign: Alamein, Malta and Sicily on the right dates, Channel unchanged.
func _test_ground_ownership() -> void:
	print("-- ground ownership")
	GameState.current_map = "desert"
	GameState.era_date = "1942-07-05"
	_check(GroundKit.side_at_latlon(30.90, 28.95) == "Axis", "Alamein is Axis in July 1942")
	GameState.era_date = "1942-11-20"
	_check(GroundKit.side_at_latlon(30.90, 28.95) == "Allies", "Alamein is Allied after Second Alamein")
	GameState.era_date = "1942-07-05"
	_check(GroundKit.side_at_latlon(35.90, 14.50) == "Allies", "Malta is Allied")
	_check(GroundKit.side_at_latlon(37.50, 14.00) == "Axis", "Sicily is Axis before the invasion")
	GameState.era_date = "1943-08-01"
	_check(GroundKit.side_at_latlon(37.50, 14.00) == "Allies", "Sicily is Allied after the invasion")
	GameState.era_date = "1944-06-10"
	_check(GroundKit.side_at_latlon(50.00, 5.00) == "Axis", "Channel front still says the occupied coast is Axis")
	_check(GroundKit.side_at_latlon(51.40, 0.50) == "Allies", "Channel front still says Kent is Allied")


func _test_life_data() -> void:
	print("-- desert life data")
	var life: Dictionary = _read_json(DESERT_DIR + "/life.json")
	_check(not life.is_empty(), "life.json parses")
	var d: MapDef = MapDef.by_id("desert")
	var places: Array = life.get("settlements", [])
	_check(places.size() >= 10, "life.json has extra places (%d)" % places.size())
	var places_ok: bool = true
	for p in places:
		var pd: Dictionary = p
		var la: float = float(pd.get("lat", 0.0))
		var lo: float = float(pd.get("lon", 0.0))
		if la < d.lat_min or la > d.lat_max or lo < d.lon_min or lo > d.lon_max:
			places_ok = false
		if str(pd.get("kind", "")) not in ["hamlet", "oasis"] or int(pd.get("size", 0)) < 1:
			places_ok = false
	_check(places_ok, "every extra place is a hamlet/oasis inside the map")
	var caravans: Array = life.get("caravans", [])
	_check(caravans.size() >= 3, "life.json has camel caravans (%d)" % caravans.size())
	var car_ok: bool = true
	for c in caravans:
		var cd: Dictionary = c
		var pts: Array = cd.get("pts", [])
		if pts.size() < 2 or int(cd.get("count", 0)) < 3 or int(cd.get("count", 0)) > 18:
			car_ok = false
		for q in pts:
			var qa: Array = q
			if qa.size() < 2 or float(qa[0]) < d.lat_min or float(qa[0]) > d.lat_max or float(qa[1]) < d.lon_min or float(qa[1]) > d.lon_max:
				car_ok = false
	_check(car_ok, "every caravan walks a valid route with 3-18 camels")
	var groups: Array = life.get("battle_groups", [])
	_check(groups.size() >= 3, "life.json has moving battle groups (%d)" % groups.size())
	var grp_ok: bool = true
	for g in groups:
		var gd: Dictionary = g
		if str(gd.get("team", "")) not in ["Allies", "Axis"]:
			grp_ok = false
		if str(gd.get("comp", "")) not in ["tanks", "mixed", "supply", "troops"]:
			grp_ok = false
		if (gd.get("pts", []) as Array).size() < 2:
			grp_ok = false
	_check(grp_ok, "every battle group has a team, a composition and a route")


func _test_campaign_targets() -> void:
	print("-- desert campaign targets")
	var loc: Dictionary = _read_json(DESERT_DIR + "/locations.json")
	var camps: int = 0
	var routes: int = 0
	var bad: bool = false
	var d: MapDef = MapDef.by_id("desert")
	for t in loc.get("targets", []):
		var td: Dictionary = t
		var typ: String = str(td.get("type", ""))
		var la: float = float(td.get("lat", 0.0))
		var lo: float = float(td.get("lon", 0.0))
		if la < d.lat_min or la > d.lat_max or lo < d.lon_min or lo > d.lon_max:
			bad = true
		if typ == "camp":
			camps += 1
			if float(td.get("radius_m", 0.0)) <= 0.0:
				bad = true
		elif typ == "convoy_route":
			routes += 1
			if (td.get("path", []) as Array).size() < 2:
				bad = true
	_check(camps >= 10, "desert has plenty of army camps (%d)" % camps)
	_check(routes >= 5, "desert has mapped convoy routes (%d)" % routes)
	_check(not bad, "every camp and convoy route is complete and inside the map")
	var gen_fields: int = 0
	for a in loc.get("airfields", []):
		if bool((a as Dictionary).get("generated", false)):
			gen_fields += 1
	_check(gen_fields >= 10, "extra sporadic airfields were added (%d)" % gen_fields)
	_check(load("res://scripts/ground/army_camp.gd") != null, "ArmyCamp script loads")
	_check(load("res://scripts/ground/camel_train.gd") != null, "CamelTrain script loads")


## Dunes: the mask stays in range, the offset is a pure function, it is feathered to zero at the field
## edge and a trough can never be dug below the water plane.
func _test_dune_shape() -> void:
	print("-- dune shape")
	GameState.current_map = "desert"
	var hf := HeightField.new()
	hf.setup()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var in_range: bool = true
	var pure: bool = true
	var floored: bool = true
	var positives: int = 0
	for i in 400:
		var lat: float = rng.randf_range(30.2, 32.9)
		var lon: float = rng.randf_range(15.0, 25.0)
		var wx: float = (lon - WorldCoords.ORIGIN_LON) * WorldCoords.units_per_deg_lon
		var wz: float = -(lat - WorldCoords.ORIGIN_LAT) * WorldCoords.units_per_deg_lat
		var e: float = hf.elev_m(lat, lon)
		var m: float = hf.dune_region_mask(wx, wz, e)
		if m < 0.0 or m > 1.0:
			in_range = false
		if m > 0.05:
			positives += 1
		var off: float = hf._dune_offset(wx, wz, e)
		if off != hf._dune_offset(wx, wz, e):
			pure = false
		if e > 0.0 and off < -e * WorldCoords.VERTICAL_SCALE * 0.8 - 0.01:
			floored = false
	_check(in_range, "dune region mask stays in 0..1")
	_check(pure, "dune offset is a pure function of position")
	_check(floored, "dune troughs never dig below the water plane")
	_check(positives > 0, "there are real dune fields in the southern desert (%d of 400 samples)" % positives)


func _test_rescue_text() -> void:
	print("-- desert rescue text")
	GameState.current_map = "desert"
	_check(BailOut.fate_text("safe", "Allies").to_lower().contains("desert"), "a desert landing is a desert fate, not a Channel one")
	_check(BailOut.fate_text("sea", "Allies").to_lower().contains("mediterranean"), "a desert ditching is a Mediterranean rescue")
	GameState.current_map = "channel"
	_check(BailOut.fate_text("sea", "Allies").contains("Channel"), "the Channel sea rescue text is unchanged")


func _test_map_switch() -> void:
	var settings_path: String = "user://settings.cfg"
	var settings_before: PackedByteArray = FileAccess.get_file_as_bytes(settings_path)
	var debug_before: bool = GameState.map_debug_override
	GameState.current_map = "channel"
	var ch_lon: float = WorldCoords.units_per_deg_lon
	var ch_lat: float = WorldCoords.units_per_deg_lat
	var ch_bounds: Rect2 = WorldCoords.world_bounds()
	var ch_probe: Vector3 = WorldCoords.latlon_to_world(51.0, 1.0)
	var ch_file_af: int = _read_json("res://data/locations.json").get("airfields", []).size()
	var ch_af: int = Campaign.loc().get("airfields", []).size()
	_check(ch_af == ch_file_af and ch_af > 0, "Channel locations count from Campaign.loc() is %d" % ch_af)
	GameState.current_map = "desert"
	_check(WorldCoords.ORIGIN_LAT == 33.75 and WorldCoords.ORIGIN_LON == 19.25 and WorldCoords.LAT_MIN == 30.0 and WorldCoords.LON_MAX == 30.5, "desert values applied to WorldCoords")
	_check(WorldCoords.units_per_deg_lon != ch_lon, "desert east-west scale differs from Channel (cos of origin latitude)")
	var de_file_af: int = _read_json(DESERT_DIR + "/locations.json").get("airfields", []).size()
	_check(Campaign.loc().get("airfields", []).size() == de_file_af, "Campaign.loc() reads the desert locations file after the switch")
	GameState.current_map = "channel"
	_check(WorldCoords.units_per_deg_lon == ch_lon and WorldCoords.units_per_deg_lat == ch_lat, "Channel scales restored exactly")
	_check(WorldCoords.world_bounds() == ch_bounds, "Channel world bounds restored exactly")
	_check(WorldCoords.latlon_to_world(51.0, 1.0) == ch_probe, "Channel projection restored exactly")
	_check(WorldCoords.ORIGIN_LAT == 50.30 and WorldCoords.ORIGIN_LON == 0.0 and WorldCoords.VERTICAL_SCALE == 2.0 and WorldCoords.HORIZ_COMPRESSION == 1.0, "Channel origin and scales restored")
	_check(WorldCoords.LAT_MIN == 48.9 and WorldCoords.LAT_MAX == 53.0 and WorldCoords.LON_MIN == -4.6 and WorldCoords.LON_MAX == 9.0, "Channel bounds restored")
	_check(WorldCoords.heightmap_dir() == "res://data/heightmap" and WorldCoords.osm_dir() == "res://data/osm" and WorldCoords.locations_path() == "res://data/locations.json", "Channel data folders restored")
	_check(GameState.current_map == "channel", "current_map is back to channel")
	_check(Campaign.loc().get("airfields", []).size() == ch_af, "Channel locations count unchanged (%d)" % ch_af)
	_check(FileAccess.get_file_as_bytes(settings_path) == settings_before, "settings.cfg is unchanged by the map switch")
	_check(GameState.map_debug_override == debug_before, "map_debug_override is unchanged by the map switch")
