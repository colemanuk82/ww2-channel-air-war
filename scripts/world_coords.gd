extends Node
## WORLD COORDINATE CONTRACT (autoload "WorldCoords").
## The map is 1:1 horizontally (1 unit = 1 m of real map distance, like a flight simulator), so real distances take their
## real flying time. Aircraft speeds and object sizes are in game units (the HUD shows units/s as m/s). Heights stay doubled
## (world_y = elevation_m * 2.0: relief and altitude tuning are unchanged). +X east, -Z north, +Y up.
## Origin, bounds, scales and data folders come from the active map (MapDef, chosen by GameState.current_map).
## Channel (the default) has origin lat 50.30, lon 0.00.
## NOTE: world_to_latlon returns Vector2(x = lat, y = lon).

const METERS_PER_DEG_LON_EQ: float = 111320.0
const METERS_PER_DEG_LAT: float = 110540.0

## The active map. Change it only through set_map().
var active_map: MapDef

## Values of the active map, copied by set_map(). Callers read them as WorldCoords.NAME.
var ORIGIN_LAT: float = 0.0
var ORIGIN_LON: float = 0.0
var HORIZ_COMPRESSION: float = 1.0      # real metres per horizontal game unit (1.0 = 1:1; it was 2.0 until v1.9)
var VERTICAL_SCALE: float = 2.0
var LAT_MIN: float = 0.0
var LAT_MAX: float = 0.0
var LON_MIN: float = 0.0
var LON_MAX: float = 0.0

## World units per degree of longitude / latitude (derived, set by set_map).
var units_per_deg_lon: float = 0.0
var units_per_deg_lat: float = 0.0


func _init() -> void:
	set_map(MapDef.DEFAULT_ID)


func _ready() -> void:
	# GameState may have loaded a saved map before this autoload was ready (autoload order is not guaranteed).
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		set_map(str(gs.get("current_map")))


## Switch the playable map (unknown ids give Channel). Copies origin, bounds and scales from MapDef.
func set_map(map_id: String) -> void:
	active_map = MapDef.by_id(map_id)
	ORIGIN_LAT = active_map.origin_lat
	ORIGIN_LON = active_map.origin_lon
	HORIZ_COMPRESSION = active_map.horiz_compression
	VERTICAL_SCALE = active_map.vertical_scale
	LAT_MIN = active_map.lat_min
	LAT_MAX = active_map.lat_max
	LON_MIN = active_map.lon_min
	LON_MAX = active_map.lon_max
	units_per_deg_lon = METERS_PER_DEG_LON_EQ * cos(deg_to_rad(ORIGIN_LAT)) / HORIZ_COMPRESSION
	units_per_deg_lat = METERS_PER_DEG_LAT / HORIZ_COMPRESSION


## Folder of the active map's heightmap files (res://data/heightmap for Channel).
func heightmap_dir() -> String:
	return active_map.heightmap_dir


## Folder of the active map's OSM files (res://data/osm for Channel).
func osm_dir() -> String:
	return active_map.osm_dir


## The active map's locations file (airfields, cities, targets, features). Channel keeps res://data/locations.json.
func locations_path() -> String:
	return active_map.locations_file


func latlon_to_world(lat: float, lon: float) -> Vector3:
	return Vector3((lon - ORIGIN_LON) * units_per_deg_lon, 0.0, -(lat - ORIGIN_LAT) * units_per_deg_lat)


## Returns Vector2(lat, lon).
func world_to_latlon(p: Vector3) -> Vector2:
	return Vector2(ORIGIN_LAT - p.z / units_per_deg_lat, ORIGIN_LON + p.x / units_per_deg_lon)


func elevation_to_world_y(elev_m: float) -> float:
	return elev_m * VERTICAL_SCALE


func world_y_to_elevation(y: float) -> float:
	return y / VERTICAL_SCALE


## Playable bounds as a Rect2 in the XZ plane (position = min x, min z).
func world_bounds() -> Rect2:
	var a: Vector3 = latlon_to_world(LAT_MAX, LON_MIN)  # north-west
	var b: Vector3 = latlon_to_world(LAT_MIN, LON_MAX)  # south-east
	return Rect2(Vector2(a.x, a.z), Vector2(b.x - a.x, b.z - a.z))


func is_in_bounds(p: Vector3) -> bool:
	return world_bounds().has_point(Vector2(p.x, p.z))


## Compass heading in degrees (0 = north, 90 = east) -> unit forward vector in the XZ plane.
func heading_to_dir(heading_deg: float) -> Vector3:
	var h: float = deg_to_rad(heading_deg)
	return Vector3(sin(h), 0.0, -cos(h))


func dir_to_heading(d: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)
