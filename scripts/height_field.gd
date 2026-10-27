class_name HeightField
extends RefCounted
## Terrain height source. Thread-safe for reads once set up.
## Uses data/heightmap/region_height.png + region_meta.json if present (see DATA CONTRACT),
## otherwise a procedural fallback: hand-authored Kent / Channel / France coast polygons + noise.
## Land/sea comes from data/heightmap/region_coast.png (an exact anti-aliased mask rasterised from
## the OSM land polygons) when present — it overrides the DEM's own land mask so inlets/islands are
## exact; the DEM only supplies the elevation. Falls back to the DEM cubic B-spline path if absent.
## All coordinates in/out are world units (see WorldCoords). Heights are world Y (elev_m * 2).

const HEIGHTMAP_PATH := "res://data/heightmap/region_height.png"
const META_PATH := "res://data/heightmap/region_meta.json"
const COAST_PATH := "res://data/heightmap/region_coast.png"
const COAST_META_PATH := "res://data/heightmap/region_coast_meta.json"
const SEA_FLOOR_Y := -4.0
# Coastal rise tuning (metres of inland distance over which land reaches its DEM height).
const COAST_RAMP_M := 110.0       # gentle coast / beach
const CLIFF_RAMP_M := 25.0        # chalk cliff face: reaches the cliff top within ~1 mask pixel
const MASK_EDGE_M := 160.0        # approx horizontal span of the mask's 0.5..1.0 edge gradient
const CLIFF_DEM_LO := 20.0        # steepen only where the DEM land is already this high ...
const CLIFF_DEM_HI := 55.0        # ... fading in up to this height
const CLIFF_SAMPLE_PX := 2        # DEM pixels sampled around a cliff cell for the cliff-top height
static var force_procedural: bool = false  # debug: ignore the heightmap file

var from_file: bool = false
var _image: Image
var _raw16: PackedByteArray   # big-endian 16-bit samples, row-major (when PNG is 16-bit grayscale)
var _w: int = 0
var _h: int = 0
var _lat_min: float = 0.0
var _lat_max: float = 0.0
var _lon_min: float = 0.0
var _lon_max: float = 0.0
var _max_elev: float = 1000.0
var _sea_val: float = 0.0
# coast distance grid (file mode), metres to nearest land for sea cells
var _cd: PackedFloat32Array
var _cd_w: int = 0
var _cd_h: int = 0
# exact OSM land/sea mask (file mode), L8 grey 0..255
var use_coast_mask: bool = false
var _mask_raw: PackedByteArray
var _mask_w: int = 0
var _mask_h: int = 0
var _mask_lat_min: float = 0.0
var _mask_lat_max: float = 0.0
var _mask_lon_min: float = 0.0
var _mask_lon_max: float = 0.0

var _noise_h: FastNoiseLite
var _noise_big: FastNoiseLite
var _noise_coast: FastNoiseLite
var _england: Poly
var _france: Poly
var _m_lon: float = 71110.0
var _m_lat: float = 110540.0

# [lat, lon, radius_m] chalk-cliff areas (used for procedural cliffs and chalk shading)
var cliff_zones: Array = [
	[51.11, 1.24, 10000.0],   # Folkestone - Dover (White Cliffs)
	[51.14, 1.35, 7000.0],    # South Foreland
	[50.745, 0.18, 9000.0],   # Seven Sisters
	[50.93, 1.72, 6500.0],    # Cap Blanc-Nez
	[49.71, 0.20, 10000.0],   # Etretat
]

# Flat zones (airfields): Vector4(x, z, flat_radius, blend) + height array
var _zones: Array = []
const ZONE_CELL := 4000.0
var _zone_grid: Dictionary = {}      # Vector2i cell -> PackedInt32Array of _zones indices touching it
var _zone_h: PackedFloat32Array = PackedFloat32Array()


func setup() -> void:
	_m_lon = WorldCoords.units_per_deg_lon * WorldCoords.HORIZ_COMPRESSION
	_m_lat = WorldCoords.units_per_deg_lat * WorldCoords.HORIZ_COMPRESSION
	_noise_h = FastNoiseLite.new()
	_noise_h.seed = 1940
	_noise_h.frequency = 1.0
	_noise_h.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_h.fractal_octaves = 4
	_noise_big = FastNoiseLite.new()
	_noise_big.seed = 44
	_noise_big.frequency = 1.0
	_noise_big.fractal_octaves = 3
	_noise_coast = FastNoiseLite.new()
	_noise_coast.seed = 6
	_noise_coast.frequency = 1.0
	if force_procedural or not _try_load_file():
		_build_procedural()


func _try_load_file() -> bool:
	if not FileAccess.file_exists(HEIGHTMAP_PATH) or not FileAccess.file_exists(META_PATH):
		# exported builds need the raw PNG packed (export include filter "data/heightmap/*.png")
		push_error("HeightField: %s not found - using the PROCEDURAL coastline (wrong land/sea)" % HEIGHTMAP_PATH)
		return false
	var mf := FileAccess.open(META_PATH, FileAccess.READ)
	if mf == null:
		return false
	var meta: Variant = JSON.parse_string(mf.get_as_text())
	if not (meta is Dictionary):
		return false
	var img: Image = null
	GroundKit.lp("    hf: start")
	var dims: Vector2i = _load_png16(HEIGHTMAP_PATH)
	GroundKit.lp("    hf: heightmap png16")
	if dims.x > 0:
		_w = dims.x
		_h = dims.y
	else:
		img = Image.new()
		if img.load(HEIGHTMAP_PATH) != OK:
			push_warning("HeightField: failed to load heightmap, using procedural terrain")
			return false
		_image = img
		_w = img.get_width()
		_h = img.get_height()
	_lat_min = float(meta.get("lat_min", WorldCoords.LAT_MIN))
	_lat_max = float(meta.get("lat_max", WorldCoords.LAT_MAX))
	_lon_min = float(meta.get("lon_min", WorldCoords.LON_MIN))
	_lon_max = float(meta.get("lon_max", WorldCoords.LON_MAX))
	_max_elev = float(meta.get("max_elev_m", 1000.0))
	_sea_val = float(meta.get("sea_level_value", 0.0)) / 65535.0
	from_file = true
	_load_coast_mask()
	GroundKit.lp("    hf: coast mask png")
	_build_coast_distance()
	GroundKit.lp("    hf: coast distance")
	print("HeightField: loaded heightmap %dx%d (%s)%s" % [_w, _h, "16-bit" if _raw16.size() > 0 else "image fallback, 8-bit precision", " + coast mask %dx%d" % [_mask_w, _mask_h] if use_coast_mask else " (no coast mask: DEM land mask + B-spline)"])
	return true


## Loads the exact OSM-derived land/sea mask. Returns silently (use_coast_mask stays false) when
## absent so exported builds without the mask keep the old B-spline coastline.
func _load_coast_mask() -> void:
	if not FileAccess.file_exists(COAST_PATH) or not FileAccess.file_exists(COAST_META_PATH):
		push_warning("HeightField: %s not found - coastline falls back to the DEM B-spline path" % COAST_PATH)
		return
	var mf := FileAccess.open(COAST_META_PATH, FileAccess.READ)
	if mf == null:
		return
	var meta: Variant = JSON.parse_string(mf.get_as_text())
	if not (meta is Dictionary):
		return
	var cf := FileAccess.open(COAST_PATH, FileAccess.READ)
	if cf == null:
		push_warning("HeightField: failed to load coast mask, using the DEM B-spline path")
		return
	var img := Image.new()
	if img.load_png_from_buffer(cf.get_buffer(cf.get_length())) != OK:
		push_warning("HeightField: failed to decode coast mask, using the DEM B-spline path")
		return
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_L8:
		img.convert(Image.FORMAT_L8)
	_mask_w = img.get_width()
	_mask_h = img.get_height()
	_mask_raw = img.get_data()
	if _mask_w < 2 or _mask_h < 2 or _mask_raw.size() < _mask_w * _mask_h:
		push_warning("HeightField: coast mask is malformed, using the DEM B-spline path")
		_mask_w = 0
		_mask_h = 0
		_mask_raw = PackedByteArray()
		return
	_mask_lat_min = float(meta.get("lat_min", _lat_min))
	_mask_lat_max = float(meta.get("lat_max", _lat_max))
	_mask_lon_min = float(meta.get("lon_min", _lon_min))
	_mask_lon_max = float(meta.get("lon_max", _lon_max))
	use_coast_mask = true


## Anti-aliased land fraction 0..1 at lat/lon from the exact OSM mask (0 = sea, 1 = land, 0.5 = coast).
func _mask_at(lat: float, lon: float) -> float:
	var u: float = clampf((lon - _mask_lon_min) / (_mask_lon_max - _mask_lon_min) * float(_mask_w - 1), 0.0, float(_mask_w - 1))
	var v: float = clampf((_mask_lat_max - lat) / (_mask_lat_max - _mask_lat_min) * float(_mask_h - 1), 0.0, float(_mask_h - 1))
	var x0: int = mini(int(u), _mask_w - 2)
	var y0: int = mini(int(v), _mask_h - 2)
	var fx: float = u - float(x0)
	var fy: float = v - float(y0)
	var row: int = y0 * _mask_w
	var a: float = float(_mask_raw[row + x0])
	var b: float = float(_mask_raw[row + x0 + 1])
	var c: float = float(_mask_raw[row + _mask_w + x0])
	var d: float = float(_mask_raw[row + _mask_w + x0 + 1])
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy) * 0.00392156862


## Normalised sample 0..1 at integer pixel.
func _px(x: int, y: int) -> float:
	if _raw16.size() > 0:
		var i: int = (y * _w + x) * 2
		return float((_raw16[i] << 8) | _raw16[i + 1]) / 65535.0
	return _image.get_pixel(x, y).r


## Decodes a 16-bit grayscale PNG into _raw16 (Godot's own loader truncates to 8 bit).
## Result is cached in user:// so the (slow, GDScript) unfilter only runs once per file version.
func _load_png16(path: String) -> Vector2i:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return Vector2i.ZERO
	var data: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	if data.size() < 33:
		return Vector2i.ZERO
	var w: int = (data[16] << 24) | (data[17] << 16) | (data[18] << 8) | data[19]
	var h: int = (data[20] << 24) | (data[21] << 16) | (data[22] << 8) | data[23]
	var depth: int = data[24]
	var ctype: int = data[25]
	var interlace: int = data[28]
	if depth != 16 or ctype != 0 or interlace != 0:
		return Vector2i.ZERO
	var cache_path: String = "user://height16_%d_%d_%d.bin" % [data.size(), w, h]
	if FileAccess.file_exists(cache_path):
		var cf := FileAccess.open(cache_path, FileAccess.READ)
		if cf and cf.get_length() == w * h * 2:
			_raw16 = cf.get_buffer(cf.get_length())
			return Vector2i(w, h)
	# collect IDAT
	var idat := PackedByteArray()
	var pos: int = 8
	while pos + 8 <= data.size():
		var clen: int = (data[pos] << 24) | (data[pos + 1] << 16) | (data[pos + 2] << 8) | data[pos + 3]
		var ctag: String = data.slice(pos + 4, pos + 8).get_string_from_ascii()
		if ctag == "IDAT":
			idat.append_array(data.slice(pos + 8, pos + 8 + clen))
		elif ctag == "IEND":
			break
		pos += 12 + clen
	var stride: int = w * 2
	var raw: PackedByteArray = idat.decompress((stride + 1) * h, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() < (stride + 1) * h:
		push_warning("HeightField: PNG16 decompress failed")
		return Vector2i.ZERO
	var out := PackedByteArray()
	out.resize(stride * h)
	for y in h:
		var ro: int = y * (stride + 1)
		var ft: int = raw[ro]
		var o: int = y * stride
		var po: int = o - stride
		ro += 1
		match ft:
			0:
				for x in stride:
					out[o + x] = raw[ro + x]
			1:
				for x in range(0, 2):
					out[o + x] = raw[ro + x]
				for x in range(2, stride):
					out[o + x] = (raw[ro + x] + out[o + x - 2]) & 255
			2:
				if y == 0:
					for x in stride:
						out[o + x] = raw[ro + x]
				else:
					for x in stride:
						out[o + x] = (raw[ro + x] + out[po + x]) & 255
			3:
				for x in stride:
					var a: int = out[o + x - 2] if x >= 2 else 0
					var b: int = out[po + x] if y > 0 else 0
					out[o + x] = (raw[ro + x] + ((a + b) >> 1)) & 255
			4:
				for x in stride:
					var a2: int = out[o + x - 2] if x >= 2 else 0
					var b2: int = out[po + x] if y > 0 else 0
					var c2: int = out[po + x - 2] if (x >= 2 and y > 0) else 0
					var pp: int = a2 + b2 - c2
					var pa: int = absi(pp - a2)
					var pb: int = absi(pp - b2)
					var pc: int = absi(pp - c2)
					var pred: int = a2 if (pa <= pb and pa <= pc) else (b2 if pb <= pc else c2)
					out[o + x] = (raw[ro + x] + pred) & 255
			_:
				return Vector2i.ZERO
	_raw16 = out
	var wf := FileAccess.open(cache_path, FileAccess.WRITE)
	if wf:
		wf.store_buffer(out)
	return Vector2i(w, h)


func _build_coast_distance() -> void:
	# Coarse distance-to-land grid for sea depth shading (chamfer transform).
	# In mask mode the land set comes from the exact OSM mask, not the DEM.
	_cd_w = mini(_w, 700)
	_cd_h = mini(_h, 340)
	_cd = PackedFloat32Array()
	_cd.resize(_cd_w * _cd_h)
	var big: float = 1.0e9
	var inv_w1: float = 1.0 / float(maxi(_w - 1, 1))
	var inv_h1: float = 1.0 / float(maxi(_h - 1, 1))
	for j in _cd_h:
		var py: int = mini(int(float(j) / float(_cd_h) * float(_h)), _h - 1)
		var lat: float = _lat_max - float(py) * inv_h1 * (_lat_max - _lat_min)
		for i in _cd_w:
			var px: int = mini(int(float(i) / float(_cd_w) * float(_w)), _w - 1)
			var is_land: bool
			if use_coast_mask:
				var lon: float = _lon_min + float(px) * inv_w1 * (_lon_max - _lon_min)
				is_land = _mask_at(lat, lon) >= 0.5
			else:
				is_land = _px(px, py) > _sea_val + 0.0001
			_cd[j * _cd_w + i] = 0.0 if is_land else big
	var cx: float = (_lon_max - _lon_min) / float(_cd_w) * _m_lon
	var cy: float = (_lat_max - _lat_min) / float(_cd_h) * _m_lat
	var cd: float = sqrt(cx * cx + cy * cy)
	for j in _cd_h:
		for i in _cd_w:
			var idx: int = j * _cd_w + i
			var v2: float = _cd[idx]
			if i > 0:
				v2 = minf(v2, _cd[idx - 1] + cx)
			if j > 0:
				v2 = minf(v2, _cd[idx - _cd_w] + cy)
				if i > 0:
					v2 = minf(v2, _cd[idx - _cd_w - 1] + cd)
				if i < _cd_w - 1:
					v2 = minf(v2, _cd[idx - _cd_w + 1] + cd)
			_cd[idx] = v2
	for j in range(_cd_h - 1, -1, -1):
		for i in range(_cd_w - 1, -1, -1):
			var idx2: int = j * _cd_w + i
			var v3: float = _cd[idx2]
			if i < _cd_w - 1:
				v3 = minf(v3, _cd[idx2 + 1] + cx)
			if j < _cd_h - 1:
				v3 = minf(v3, _cd[idx2 + _cd_w] + cy)
				if i < _cd_w - 1:
					v3 = minf(v3, _cd[idx2 + _cd_w + 1] + cd)
				if i > 0:
					v3 = minf(v3, _cd[idx2 + _cd_w - 1] + cd)
			_cd[idx2] = v3


# ---------------------------------------------------------------- public

## Make the ground flat around (x, z). Returns the flattened height (world Y).
func add_flat_zone(x: float, z: float, flat_radius: float, blend: float, min_height: float = 3.0) -> float:
	var h: float = maxf(height_y(x, z), min_height)
	_zones.append(Vector4(x, z, flat_radius, blend))
	_zone_h.append(h)
	# index the zone in every grid cell its outer edge touches, so height_y only tests the few zones near a point
	# (it used to test all of them for every height sample: ~120 airfields, and more with the camps)
	var idx: int = _zones.size() - 1
	var r: float = flat_radius + blend
	var c0 := Vector2i(floori((x - r) / ZONE_CELL), floori((z - r) / ZONE_CELL))
	var c1 := Vector2i(floori((x + r) / ZONE_CELL), floori((z + r) / ZONE_CELL))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var key := Vector2i(cx, cz)
			var lst: PackedInt32Array = _zone_grid.get(key, PackedInt32Array())
			lst.append(idx)
			_zone_grid[key] = lst
	return h


## Terrain surface height in world Y (negative = sea floor).
func height_y(wx: float, wz: float) -> float:
	var ll: Vector2 = WorldCoords.world_to_latlon(Vector3(wx, 0.0, wz))
	var e: float = elev_m(ll.x, ll.y)
	var y: float
	if e > 0.0:
		y = e * WorldCoords.VERTICAL_SCALE
	else:
		y = minf(e * WorldCoords.VERTICAL_SCALE, SEA_FLOOR_Y)
	var cell := Vector2i(floori(wx / ZONE_CELL), floori(wz / ZONE_CELL))
	if not _zone_grid.has(cell):
		return y
	for i in (_zone_grid[cell] as PackedInt32Array):
		var z: Vector4 = _zones[i]
		var d: float = Vector2(wx - z.x, wz - z.y).length()
		var w: float = 1.0 - smoothstep(z.z, z.z + z.w, d)
		if w > 0.0:
			y = lerpf(y, _zone_h[i], w)
	return y


## Elevation in metres (<= 0 is sea; negative values are depth below sea level in procedural mode).
func elev_m(lat: float, lon: float) -> float:
	if from_file:
		return _file_elev(lat, lon)
	return _proc_elev(lat, lon)


func get_cliff_world_zones() -> Array:
	var out: Array = []
	for c in cliff_zones:
		var p: Vector3 = WorldCoords.latlon_to_world(c[0], c[1])
		out.append(Vector3(p.x, p.z, c[2] / WorldCoords.HORIZ_COMPRESSION))
	return out


## Mask land fraction 0..1 at a world XZ position (1.0 when no coast mask is loaded).
## Used by CliffSkirt to trace the coastline; thread-safe (reads only).
func coast_land_w(wx: float, wz: float) -> float:
	if not use_coast_mask:
		return 1.0
	var ll: Vector2 = WorldCoords.world_to_latlon(Vector3(wx, 0.0, wz))
	return _mask_at(ll.x, ll.y)


## Cliff-top elevation in metres at a world XZ position: the highest DEM sample in a small ring
## around the cell (so the coarse DEM's own coast being offset from the exact mask edge cannot hide a
## high cliff top). Returns 0 when there is no DEM file.
func cliff_top_m_w(wx: float, wz: float) -> float:
	if not from_file:
		return 0.0
	var ll: Vector2 = WorldCoords.world_to_latlon(Vector3(wx, 0.0, wz))
	var u: float = (ll.y - _lon_min) / (_lon_max - _lon_min) * float(_w - 1)
	var v: float = (_lat_max - ll.x) / (_lat_max - _lat_min) * float(_h - 1)
	return _dem_coast_top(u, v)


## Chalk-cliff membership 0..1 at a world XZ position (0 outside every cliff zone).
func cliff_zone_weight_w(wx: float, wz: float) -> float:
	var ll: Vector2 = WorldCoords.world_to_latlon(Vector3(wx, 0.0, wz))
	return _cliff_weight(ll.y * _m_lon, ll.x * _m_lat)


# ---------------------------------------------------------------- file mode

func _file_elev(lat: float, lon: float) -> float:
	var u: float = (lon - _lon_min) / (_lon_max - _lon_min) * float(_w - 1)
	var v: float = (_lat_max - lat) / (_lat_max - _lat_min) * float(_h - 1)
	if u < 0.0 or v < 0.0 or u > float(_w - 1) or v > float(_h - 1):
		return -40.0
	if use_coast_mask:
		return _mask_elev(lat, lon, u, v)
	var x0: int = mini(int(u), _w - 2)
	var y0: int = mini(int(v), _h - 2)
	var fx: float = u - float(x0)
	var fy: float = v - float(y0)
	var a: float = _px(x0, y0)
	var b: float = _px(x0 + 1, y0)
	var c: float = _px(x0, y0 + 1)
	var d: float = _px(x0 + 1, y0 + 1)
	var sv: float = _sea_val + 0.00001
	var n_land: int = int(a > sv) + int(b > sv) + int(c > sv) + int(d > sv)
	if n_land == 4:
		var val: float = lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)
		return maxf((val - _sea_val) * _max_elev, 0.1)
	if n_land == 0:
		return _sea_depth(u, v, 0.0)
	# Coastal cell: the source DEM is ~450 m per pixel, so a plain bilinear land/sea threshold
	# draws a staircase coastline. Use a cubic B-spline of the land mask (smooth contour at 0.5)
	# and of the elevation instead.
	var land_k: float = 0.0
	var elev_k: float = 0.0
	for j in 4:
		var py: int = clampi(y0 - 1 + j, 0, _h - 1)
		var wy: float = _bspline_w(fy, j)
		for i in 4:
			var px: int = clampi(x0 - 1 + i, 0, _w - 1)
			var wgt: float = wy * _bspline_w(fx, i)
			var s: float = _px(px, py)
			if s > sv:
				land_k += wgt
				elev_k += wgt * (s - _sea_val)
	if land_k >= 0.5:
		var e_land: float = elev_k / maxf(land_k, 0.001) * _max_elev
		# rises off the waterline over a short band (keeps cliffs steep, no vertical step)
		return maxf(0.15, e_land * smoothstep(0.5, 0.6, land_k))
	return _sea_depth(u, v, land_k)


## Land/sea is decided by the exact OSM mask; the DEM only supplies the elevation. The land side
## ramps from the waterline to its DEM height over COAST_RAMP_M (narrowed to CLIFF_RAMP_M inside a
## chalk cliff zone where the DEM land is already high), so cliffs read as near-vertical faces.
func _mask_elev(lat: float, lon: float, u: float, v: float) -> float:
	var m: float = _mask_at(lat, lon)
	if m < 0.5:
		return _sea_depth(u, v, clampf(m, 0.0, 0.5))
	var base: float = maxf(_dem_m(u, v), 1.0)
	var ramp: float = COAST_RAMP_M
	var cw: float = _cliff_weight(lon * _m_lon, lat * _m_lat)
	if cw > 0.0:
		var top: float = _dem_coast_top(u, v)
		var k: float = cw * smoothstep(CLIFF_DEM_LO, CLIFF_DEM_HI, top)
		if k > 0.0:
			base = lerpf(base, maxf(top, base), k)
			ramp = lerpf(COAST_RAMP_M, CLIFF_RAMP_M, k)
	var d_land: float = clampf((m - 0.5) * 2.0, 0.0, 1.0) * MASK_EDGE_M
	return maxf(0.2, base * smoothstep(0.0, ramp, d_land))


## Bilinear DEM elevation in metres at a fractional pixel (0 outside sea).
func _dem_m(u: float, v: float) -> float:
	u = clampf(u, 0.0, float(_w - 1))
	v = clampf(v, 0.0, float(_h - 1))
	var x0: int = mini(int(u), _w - 2)
	var y0: int = mini(int(v), _h - 2)
	var fx: float = u - float(x0)
	var fy: float = v - float(y0)
	var a: float = _px(x0, y0)
	var b: float = _px(x0 + 1, y0)
	var c: float = _px(x0, y0 + 1)
	var d: float = _px(x0 + 1, y0 + 1)
	return maxf((lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy) - _sea_val) * _max_elev, 0.0)


## Highest DEM sample in a small ring around a cliff cell — gives the cliff-top height even when
## the coarse DEM's own coast is offset from the exact OSM coastline.
func _dem_coast_top(u: float, v: float) -> float:
	var d: float = float(CLIFF_SAMPLE_PX)
	var h: float = _dem_m(u, v)
	h = maxf(h, _dem_m(u - d, v - d))
	h = maxf(h, _dem_m(u, v - d))
	h = maxf(h, _dem_m(u + d, v - d))
	h = maxf(h, _dem_m(u - d, v))
	h = maxf(h, _dem_m(u + d, v))
	h = maxf(h, _dem_m(u - d, v + d))
	h = maxf(h, _dem_m(u, v + d))
	h = maxf(h, _dem_m(u + d, v + d))
	return h


## Cubic B-spline basis weight for tap i (0..3) at fraction t.
func _bspline_w(t: float, i: int) -> float:
	match i:
		0:
			return (1.0 - t) * (1.0 - t) * (1.0 - t) / 6.0
		1:
			return (3.0 * t * t * t - 6.0 * t * t + 4.0) / 6.0
		2:
			return (-3.0 * t * t * t + 3.0 * t * t + 3.0 * t + 1.0) / 6.0
	return t * t * t / 6.0


## Sea depth (negative metres) from the bilinear distance-to-coast grid. land_k (0..0.5) shelves
## the bed up towards the shoreline.
func _sea_depth(u: float, v: float, land_k: float) -> float:
	var gx: float = clampf(u / float(_w) * float(_cd_w) - 0.5, 0.0, float(_cd_w - 1))
	var gy: float = clampf(v / float(_h) * float(_cd_h) - 0.5, 0.0, float(_cd_h - 1))
	var i0: int = mini(int(gx), _cd_w - 2)
	var j0: int = mini(int(gy), _cd_h - 2)
	var tx: float = gx - float(i0)
	var ty: float = gy - float(j0)
	var r0: int = j0 * _cd_w + i0
	var dist: float = lerpf(lerpf(_cd[r0], _cd[r0 + 1], tx), lerpf(_cd[r0 + _cd_w], _cd[r0 + _cd_w + 1], tx), ty)
	var deep: float = -(2.0 + 40.0 * smoothstep(0.0, 12000.0, dist))
	return lerpf(deep, -0.3, smoothstep(0.15, 0.5, land_k))


# ---------------------------------------------------------------- procedural mode

func _proc_elev(lat: float, lon: float) -> float:
	var x: float = lon * _m_lon
	var y: float = lat * _m_lat
	var sd: float = maxf(_england.signed_dist(x, y), _france.signed_dist(x, y))
	sd += _noise_coast.get_noise_2d(x / 2500.0, y / 2500.0) * 350.0
	if sd <= 0.0:
		return -(2.0 + minf(-sd, 40000.0) / 40000.0 * 40.0)
	var cw: float = _cliff_weight(x, y)
	var low: float = _noise_h.get_noise_2d(x / 9000.0, y / 9000.0) * 0.5 + 0.5
	var big: float = _noise_big.get_noise_2d(x / 60000.0, y / 60000.0) * 0.5 + 0.5
	var base: float = 6.0 + low * 40.0
	var inland: float = smoothstep(0.0, 40000.0, sd)
	base += inland * (30.0 + 80.0 * big)
	var cliff_h: float = 100.0 + _noise_h.get_noise_2d(x / 3000.0, y / 3000.0) * 14.0
	var wcl: float = cw * (1.0 - smoothstep(0.0, 25000.0, sd))
	base = lerpf(base, cliff_h, wcl)
	var ramp_len: float = lerpf(5000.0, 220.0, cw)
	var r: float = smoothstep(0.0, 1.0, sd / ramp_len)
	var beach: float = 0.7 * minf(sd / 70.0, 1.0)
	return maxf(base * r, beach)


func _cliff_weight(x: float, y: float) -> float:
	var best: float = 0.0
	for c in cliff_zones:
		var d: float = Vector2(x - c[1] * _m_lon, y - c[0] * _m_lat).length()
		var r: float = c[2]
		best = maxf(best, 1.0 - smoothstep(r * 0.4, r, d))
	return best


func _build_procedural() -> void:
	var eng: Array = [
		[-6.0, 50.40], [-4.6, 50.33], [-4.14, 50.35], [-3.85, 50.28], [-3.65, 50.22], [-3.5, 50.44],
		[-3.4, 50.60], [-3.0, 50.70], [-2.6, 50.62], [-2.45, 50.54], [-2.2, 50.60], [-1.95, 50.60],
		[-1.85, 50.72], [-1.55, 50.72], [-1.3, 50.78], [-1.08, 50.78], [-0.79, 50.72], [-0.67, 50.78],
		[-0.37, 50.81], [-0.14, 50.82], [0.06, 50.79], [0.25, 50.73], [0.40, 50.78], [0.58, 50.85],
		[0.77, 50.92], [0.98, 50.91], [1.08, 51.07], [1.18, 51.08], [1.32, 51.12], [1.37, 51.14],
		[1.41, 51.22], [1.40, 51.28], [1.42, 51.33], [1.39, 51.39], [1.45, 51.38], [1.13, 51.38],
		[1.03, 51.36], [0.90, 51.36], [0.70, 51.43], [0.55, 51.46], [0.72, 51.53], [0.95, 51.62],
		[1.15, 51.79], [1.15, 52.5], [-6.0, 52.5]]
	var fra: Array = [
		[-4.7, 48.0], [-4.7, 48.72], [-4.0, 48.72], [-3.5, 48.84], [-3.0, 48.75], [-2.5, 48.60],
		[-2.0, 48.70], [-1.5, 48.64], [-1.58, 48.84], [-1.6, 49.1], [-1.72, 49.2], [-1.80, 49.40],
		[-1.88, 49.65], [-1.95, 49.72], [-1.62, 49.66], [-1.25, 49.70], [-1.27, 49.50], [-1.20, 49.42],
		[-1.15, 49.35], [-0.95, 49.36], [-0.85, 49.37], [-0.62, 49.35], [-0.45, 49.34], [-0.25, 49.29],
		[-0.10, 49.29], [0.15, 49.40], [0.08, 49.48], [0.15, 49.69], [0.37, 49.76], [0.80, 49.87],
		[1.08, 49.93], [1.37, 50.06], [1.55, 50.20], [1.57, 50.40], [1.59, 50.52], [1.58, 50.73],
		[1.60, 50.86], [1.70, 50.93], [1.85, 50.97], [2.20, 51.03], [2.37, 51.06], [2.60, 51.10],
		[2.90, 51.23], [3.20, 51.34], [3.40, 51.40], [3.55, 51.45], [3.65, 51.60], [3.85, 51.80],
		[3.85, 52.0], [6.0, 52.0], [6.0, 48.0]]
	_england = Poly.new(eng, _m_lon, _m_lat)
	_france = Poly.new(fra, _m_lon, _m_lat)


# Polygon with bucketed nearest-edge signed distance (metres, positive inside).
class Poly:
	const B: float = 20000.0
	const R: float = 35000.0
	const FAR: float = 60000.0
	var pts := PackedVector2Array()
	var ccw: bool = true
	var buckets: Dictionary = {}
	var inside_center: Dictionary = {}

	func _init(lonlat: Array, m_lon: float, m_lat: float) -> void:
		for p in lonlat:
			pts.append(Vector2(p[0] * m_lon, p[1] * m_lat))
		var area: float = 0.0
		var n: int = pts.size()
		for i in n:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % n]
			area += a.x * b.y - b.x * a.y
		ccw = area > 0.0
		var x0: int = floori(-6.0 * m_lon / B)
		var x1: int = floori(6.0 * m_lon / B)
		var y0: int = floori(48.0 * m_lat / B)
		var y1: int = floori(53.0 * m_lat / B)
		for by in range(y0, y1 + 1):
			for bx in range(x0, x1 + 1):
				var c := Vector2((bx + 0.5) * B, (by + 0.5) * B)
				var lst := PackedInt32Array()
				for i in n:
					var a2: Vector2 = pts[i]
					var b2: Vector2 = pts[(i + 1) % n]
					if _seg_dist(c, a2, b2) <= B * 0.7072 + R:
						lst.append(i)
				var key := Vector2i(bx, by)
				buckets[key] = lst
				if lst.is_empty():
					inside_center[key] = _inside_full(c)

	static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
		var ab: Vector2 = b - a
		var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		return (p - (a + ab * t)).length()

	func _inside_full(p: Vector2) -> bool:
		var inside: bool = false
		var n: int = pts.size()
		var j: int = n - 1
		for i in n:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[j]
			if (a.y > p.y) != (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
				inside = not inside
			j = i
		return inside

	func signed_dist(x: float, y: float) -> float:
		var key := Vector2i(floori(x / B), floori(y / B))
		if not buckets.has(key):
			return FAR if _inside_full(Vector2(x, y)) else -FAR
		var lst: PackedInt32Array = buckets[key]
		if lst.is_empty():
			return FAR if inside_center[key] else -FAR
		var p := Vector2(x, y)
		var best: float = INF
		var side: float = 1.0
		var n: int = pts.size()
		for idx in lst:
			var a: Vector2 = pts[idx]
			var b: Vector2 = pts[(idx + 1) % n]
			var ab: Vector2 = b - a
			var ap: Vector2 = p - a
			var t: float = clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var d2: float = (ap - ab * t).length_squared()
			if d2 < best:
				best = d2
				side = ab.cross(ap)
		var d: float = minf(sqrt(best), FAR)
		var inside: bool = (side > 0.0) == ccw
		return d if inside else -d
