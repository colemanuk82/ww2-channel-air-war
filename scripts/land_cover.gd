class_name LandCover
extends RefCounted
## Reads the ESA WorldCover class grid (data/heightmap/region_landcover.bin) so 3D content
## (trees, buildings, hedgerows) can be placed where the real land cover says they belong.
## Classes: 10 tree, 20 shrub, 30 grass, 40 crop, 50 built, 60 bare, 70 snow, 80 water,
## 90 wetland, 95 mangrove, 100 moss, 0 = no data (open sea). Returns -1 if the grid is missing.

static var _data: PackedByteArray = PackedByteArray()
static var _w: int = 0
static var _h: int = 0
static var _lat_min: float = 0.0
static var _lat_max: float = 0.0
static var _lon_min: float = 0.0
static var _lon_max: float = 0.0
static var _loaded: bool = false


static func _load() -> bool:
	if _loaded:
		return _w > 0 and _h > 0
	_loaded = true
	var jf: FileAccess = FileAccess.open((WorldCoords.heightmap_dir() + "/region_landcover.json"), FileAccess.READ)
	if jf == null:
		return false
	var d: Variant = JSON.parse_string(jf.get_as_text())
	jf = null
	if not (d is Dictionary):
		return false
	var dd: Dictionary = d
	_w = int(dd.get("width", 0))
	_h = int(dd.get("height", 0))
	_lat_min = float(dd.get("lat_min", 0.0))
	_lat_max = float(dd.get("lat_max", 0.0))
	_lon_min = float(dd.get("lon_min", 0.0))
	_lon_max = float(dd.get("lon_max", 0.0))
	var bf: FileAccess = FileAccess.open((WorldCoords.heightmap_dir() + "/region_landcover.bin"), FileAccess.READ)
	if bf == null:
		_w = 0
		return false
	_data = bf.get_buffer(bf.get_length())
	bf = null
	return _w > 0 and _h > 0 and _data.size() == _w * _h


static func ready() -> bool:
	return _load()


## Grid accessors so the desert terrain shader can build lc_tex from the same single copy of the
## 19.4 MB class grid instead of reading region_landcover.bin a second time.
static func width() -> int:
	_load()
	return _w


static func height() -> int:
	_load()
	return _h


static func data() -> PackedByteArray:
	_load()
	return _data


## WorldCover class at a world XZ position, or -1 if the grid is unavailable.
static func class_at(x: float, z: float) -> int:
	if not _load():
		return -1
	if _lon_max <= _lon_min or _lat_max <= _lat_min:
		return -1
	# Inlined world -> lat/lon: this is called tens of thousands of times per tile, so no Vector3/Vector2
	# allocations and no second division round-trip.
	var lat: float = WorldCoords.ORIGIN_LAT - z / WorldCoords.units_per_deg_lat
	var lon: float = WorldCoords.ORIGIN_LON + x / WorldCoords.units_per_deg_lon
	var u: float = (lon - _lon_min) / (_lon_max - _lon_min)
	var v: float = (_lat_max - lat) / (_lat_max - _lat_min)
	var col: int = clampi(int(u * float(_w)), 0, _w - 1)
	var row: int = clampi(int(v * float(_h)), 0, _h - 1)
	return int(_data[row * _w + col])


## Built-up mask (class 50) as an 8-bit image over the land-cover grid, upsampled 2x with a cubic filter
## so the terrain shader can threshold it into smooth town outlines. Null if the grid is missing.
static func urban_mask() -> Image:
	if not _load():
		return null
	var raw := PackedByteArray()
	raw.resize(_w * _h)
	for i in _w * _h:
		raw[i] = 255 if _data[i] == 50 else 0
	var img := Image.create_from_data(_w, _h, false, Image.FORMAT_L8, raw)
	img.resize(_w * 2, _h * 2, Image.INTERPOLATE_CUBIC)
	return img
