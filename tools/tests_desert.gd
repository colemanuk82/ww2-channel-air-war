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
	_test_map_def()
	_test_world_coords()
	_test_desert_files()
	_test_desert_locations()
	_test_landcover_ids()
	_test_tracks()
	_test_map_switch()
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


func _test_map_switch() -> void:
	print("-- map switch")
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
