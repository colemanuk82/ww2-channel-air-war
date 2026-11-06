class_name MapDef
extends RefCounted
## One playable map. GameState.current_map holds its id and WorldCoords applies it (origin, bounds, scales, data folders).
## Channel is the original map: its values are exactly the ones the game used before maps existed.
## Desert ("Mediterranean / North Africa") covers Tunis to Alexandria with Malta and south Sicily; its origin is near its centre.

const DEFAULT_ID := "channel"

var id: String = DEFAULT_ID
var name: String = "Channel"
var origin_lat: float = 50.30         # the world's (0, 0) point; its latitude also sets the east-west scale (cos lat)
var origin_lon: float = 0.0
var lat_min: float = 48.9
var lat_max: float = 53.0
var lon_min: float = -4.6
var lon_max: float = 9.0
var vertical_scale: float = 2.0       # world Y per metre of elevation
var horiz_compression: float = 1.0    # real metres per horizontal game unit (1.0 = 1:1)
var heightmap_dir: String = "res://data/heightmap"   # region_height.png, region_meta.json, region_color.png, ...
var osm_dir: String = "res://data/osm"               # roads.json, rivers.json, rails.json, coast.json, ...

var locations_file: String = "res://data/locations.json"   # airfields, cities, targets, features: the map's own file


## The map with this id. Unknown ids give Channel.
static func by_id(map_id: String) -> MapDef:
	var m := MapDef.new()
	if map_id == "desert":
		m.id = "desert"
		m.name = "Desert"
		m.origin_lat = 33.75
		m.origin_lon = 19.25
		m.lat_min = 30.0
		m.lat_max = 37.5
		m.lon_min = 8.0
		m.lon_max = 30.5
		m.heightmap_dir = "res://data/desert"
		m.osm_dir = "res://data/desert/osm"
		m.locations_file = "res://data/desert/locations.json"
	return m


## Drops data cached from the previous map, so the next load reads the files of the map now chosen.
## GameState calls this when current_map changes (only the main menu changes it, before a sortie starts).
static func reset_map_caches() -> void:
	Campaign.reset_cache()
	CanalKit.reset_cache()
	SpawnPoints.reset_cache()
	TransportNetwork.reset_cache()
