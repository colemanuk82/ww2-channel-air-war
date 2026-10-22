extends Node
## WORLD COORDINATE CONTRACT (autoload "WorldCoords").
## The map is 1:1 horizontally (1 unit = 1 m of real map distance, like a flight simulator), so real distances take their
## real flying time. Aircraft speeds and object sizes are in game units (the HUD shows units/s as m/s). Heights stay doubled
## (world_y = elevation_m * 2.0: relief and altitude tuning are unchanged). Origin = lat 50.30, lon 0.00.
## +X east, -Z north, +Y up.
## NOTE: world_to_latlon returns Vector2(x = lat, y = lon).

const ORIGIN_LAT: float = 50.30
const ORIGIN_LON: float = 0.0
const HORIZ_COMPRESSION: float = 1.0      # real metres per horizontal game unit (1.0 = 1:1; it was 2.0 until v1.9)
const VERTICAL_SCALE: float = 2.0
const METERS_PER_DEG_LON_EQ: float = 111320.0
const METERS_PER_DEG_LAT: float = 110540.0

const LAT_MIN: float = 48.9
const LAT_MAX: float = 53.0
const LON_MIN: float = -4.6
const LON_MAX: float = 9.0

## World units per degree of longitude / latitude (derived, set in _init).
var units_per_deg_lon: float = 0.0
var units_per_deg_lat: float = 0.0


func _init() -> void:
	units_per_deg_lon = METERS_PER_DEG_LON_EQ * cos(deg_to_rad(50.3)) / HORIZ_COMPRESSION
	units_per_deg_lat = METERS_PER_DEG_LAT / HORIZ_COMPRESSION


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
