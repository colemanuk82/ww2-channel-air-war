extends RefCounted
## Map data for the editor's whole-map 2D view: the imagery mosaic with the coast, rivers and major
## roads baked into it once at start, plus a coarse grid of road segments for the sharp overlay the
## view draws when zoomed in past ~10x.
##
## Baking matters: roads.json is 20 MB and 348k two-point segments, so redrawing them every frame is
## out of the question. The bake is a single ~3 s pass at start; from then on the view blits one
## texture. The grid keeps the zoomed-in overlay to the few thousand segments actually on screen.
##
##   var base := MapBase.new()
##   base.build()                      # imagery + coast + rivers + roads + segment grid
##   view.base = base                  # MapView blits base.texture

const MapTransform := preload("res://tools/map_editor/map_transform.gd")

const IMAGERY: String = "res://data/heightmap/region_color.png"
const ROADS: String = "res://data/osm/roads.json"
const RIVERS: String = "res://data/osm/rivers.json"
const COAST: String = "res://data/osm/coast.json"
const TOWNS: String = "res://data/osm/towns.json"
const LOCATIONS: String = "res://data/locations.json"

## Road kinds drawn, widest first. These are the only kinds roads.json contains.
const ROAD_KINDS: Array = ["motorway", "trunk", "primary"]
const ROAD_COLS: Dictionary = {
	"motorway": Color(0.95, 0.52, 0.32),
	"trunk": Color(0.88, 0.74, 0.46),
	"primary": Color(0.78, 0.72, 0.55),
}
const ROAD_PX: Dictionary = {"motorway": 2, "trunk": 1, "primary": 1}

const COAST_COL: Color = Color(0.96, 0.93, 0.76)
const RIVER_COL: Color = Color(0.28, 0.45, 0.68)
const GRID_KM: float = 4.0           # vector-overlay cell size

var texture: Texture2D = null
var cities: Array = []               # [{name, lat, lon, size}]
var airfields: Array = []            # [{name, lat, lon, side}]
var baked: bool = false
var bake_ms: int = 0

var _grid_w: int = 0
var _grid_h: int = 0
var _cells: Dictionary = {}                              # cell index -> PackedInt32Array of segment indices
var _segs: PackedVector2Array = PackedVector2Array()     # uv pairs, two per segment
var _seg_kind: PackedInt32Array = PackedInt32Array()     # index into ROAD_KINDS


## Load the map data and bake it. `width` sizes the bake in pixels; the imagery's own width is used
## when it is 0, which is what the editor does (so the base is drawn 1:1 and stays sharp).
func build(width: int = 0) -> void:
	var t0: int = Time.get_ticks_msec()
	var img: Image = _imagery(width)
	_bake_lines(img, _lines(COAST), COAST_COL, 2)
	# Rivers and canals are one pixel: the bake is 157 m a pixel, so anything wider reads as a fat blue
	# band across the countryside once the view is zoomed in.
	_bake_lines(img, _lines(RIVERS), RIVER_COL, 1)
	var roads: Array = _lines(ROADS)
	_bake_roads(img, roads)
	texture = ImageTexture.create_from_image(img)
	_build_grid(roads)
	_load_places()
	baked = true
	bake_ms = Time.get_ticks_msec() - t0


## The baked base map as an image (for saving or inspection). Null before build().
func image() -> Image:
	return null if texture == null else texture.get_image()


# ================================================================== places
func _load_places() -> void:
	cities = []
	airfields = []
	var loc: Variant = _json(LOCATIONS)
	if not (loc is Dictionary):
		return
	for c in (loc as Dictionary).get("cities", []):
		var cd: Dictionary = c
		if bool(cd.get("in_bounds", true)):
			cities.append({"name": str(cd.get("name", "")), "lat": float(cd.get("lat", 0.0)),
				"lon": float(cd.get("lon", 0.0)), "size": int(cd.get("size", 1))})
	for a in (loc as Dictionary).get("airfields", []):
		var ad: Dictionary = a
		if bool(ad.get("in_bounds", true)):
			airfields.append({"name": str(ad.get("name", "")), "lat": float(ad.get("lat", 0.0)),
				"lon": float(ad.get("lon", 0.0)), "side": str(ad.get("side", ""))})


# ================================================================== bake
## The imagery, or a dark sea-colour fill when it is missing. Loaded as a Texture2D and read back as
## an Image (the way hud.gd does it) rather than with Image.load(), which Godot warns will not work
## from an exported project.
func _imagery(width: int) -> Image:
	var img: Image = null
	if ResourceLoader.exists(IMAGERY):
		var tex: Texture2D = ResourceLoader.load(IMAGERY) as Texture2D
		if tex != null:
			img = tex.get_image()
	if img == null:
		var w: int = maxi(width, 1024)
		var h: int = maxi(int(round(float(w) / MapTransform.map_aspect())), 1)
		img = Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.06, 0.09, 0.12))
		return img
	img.convert(Image.FORMAT_RGBA8)
	if width > 0 and width != img.get_width():
		var hh: int = maxi(int(round(float(width) / MapTransform.map_aspect())), 1)
		img.resize(width, hh, Image.INTERPOLATE_BILINEAR)
	return img


func _bake_lines(img: Image, lines: Array, col: Color, thick: int) -> int:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var plotted: int = 0
	for ln in lines:
		var pts: Array = (ln as Dictionary).get("pts", [])
		if pts.size() < 2:
			continue
		var prev: Vector2i = _px(pts[0], w, h)
		for i in range(1, pts.size()):
			var cur: Vector2i = _px(pts[i], w, h)
			if cur == prev:
				continue
			plotted += _line(img, prev, cur, col, thick)
			prev = cur
	return plotted


func _bake_roads(img: Image, lines: Array) -> int:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var plotted: int = 0
	for ln in lines:
		var e: Dictionary = ln
		var kind: String = str(e.get("k", ""))
		if not ROAD_COLS.has(kind):
			continue
		var pts: Array = e.get("pts", [])
		if pts.size() < 2:
			continue
		var col: Color = ROAD_COLS[kind]
		var thick: int = int(ROAD_PX[kind])
		var prev: Vector2i = _px(pts[0], w, h)
		for i in range(1, pts.size()):
			var cur: Vector2i = _px(pts[i], w, h)
			if cur == prev:
				continue
			plotted += _line(img, prev, cur, col, thick)
			prev = cur
	return plotted


## Bake-space pixel of a [lat, lon] point.
static func _px(pt: Variant, w: int, h: int) -> Vector2i:
	var a: Array = pt
	var uv := MapTransform.uv_static(float(a[0]), float(a[1]))
	return Vector2i(int(round(uv.x * float(w - 1))), int(round(uv.y * float(h - 1))))


## Bresenham with a square brush, clipped to the image. Returns the pixels plotted.
static func _line(img: Image, a: Vector2i, b: Vector2i, col: Color, thick: int) -> int:
	var iw: int = img.get_width()
	var ih: int = img.get_height()
	var span: int = maxi(thick - 1, 0)
	var dx: int = absi(b.x - a.x)
	var dy: int = -absi(b.y - a.y)
	var sx: int = 1 if a.x < b.x else -1
	var sy: int = 1 if a.y < b.y else -1
	var err: int = dx + dy
	var px: int = a.x
	var py: int = a.y
	var n: int = 0
	while true:
		for oy in range(-span, span + 1):
			var yy: int = py + oy
			if yy < 0 or yy >= ih:
				continue
			for ox in range(-span, span + 1):
				var xx: int = px + ox
				if xx < 0 or xx >= iw:
					continue
				img.set_pixel(xx, yy, col)
				n += 1
		if px == b.x and py == b.y:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			px += sx
		if e2 <= dx:
			err += dx
			py += sy
	return n


# ================================================================== vector grid
func _build_grid(roads: Array) -> void:
	var km_w: float = (WorldCoords.LON_MAX - WorldCoords.LON_MIN) * WorldCoords.units_per_deg_lon / 1000.0
	var km_h: float = (WorldCoords.LAT_MAX - WorldCoords.LAT_MIN) * WorldCoords.units_per_deg_lat / 1000.0
	_grid_w = maxi(int(ceil(km_w / GRID_KM)), 1)
	_grid_h = maxi(int(ceil(km_h / GRID_KM)), 1)
	_cells = {}
	_segs = PackedVector2Array()
	_seg_kind = PackedInt32Array()
	for ln in roads:
		var e: Dictionary = ln
		var ki: int = ROAD_KINDS.find(str(e.get("k", "")))
		if ki < 0:
			continue
		var pts: Array = e.get("pts", [])
		if pts.size() < 2:
			continue
		for i in range(1, pts.size()):
			var uv0: Vector2 = MapTransform.uv_static(float((pts[i - 1] as Array)[0]), float((pts[i - 1] as Array)[1]))
			var uv1: Vector2 = MapTransform.uv_static(float((pts[i] as Array)[0]), float((pts[i] as Array)[1]))
			if uv0 == uv1:
				continue
			var idx: int = _seg_kind.size()
			_segs.append(uv0)
			_segs.append(uv1)
			_seg_kind.append(ki)
			var cell: int = _cell_of((uv0 + uv1) * 0.5)
			if _cells.has(cell):
				(_cells[cell] as PackedInt32Array).append(idx)
			else:
				_cells[cell] = PackedInt32Array([idx])


func _cell_of(uv: Vector2) -> int:
	var gx: int = clampi(int(uv.x * float(_grid_w)), 0, _grid_w - 1)
	var gy: int = clampi(int(uv.y * float(_grid_h)), 0, _grid_h - 1)
	return gy * _grid_w + gx


func segment_count() -> int:
	return _seg_kind.size()


## Screen-space vertex pairs for the road segments inside `rect` (map-space uv), grouped per kind so
## the view can draw each width and colour. `limit` caps the work; past it the baked image carries
## the rest.
func visible_roads(rect: Rect2, t: MapTransform, limit: int = 24000) -> Dictionary:
	var out: Dictionary = {}
	for ki in ROAD_KINDS.size():
		out[ki] = PackedVector2Array()
	var x0: int = clampi(int(rect.position.x * float(_grid_w)) - 1, 0, _grid_w - 1)
	var x1: int = clampi(int(rect.end.x * float(_grid_w)) + 1, 0, _grid_w - 1)
	var y0: int = clampi(int(rect.position.y * float(_grid_h)) - 1, 0, _grid_h - 1)
	var y1: int = clampi(int(rect.end.y * float(_grid_h)) + 1, 0, _grid_h - 1)
	var n: int = 0
	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			var cell: Variant = _cells.get(gy * _grid_w + gx)
			if cell == null:
				continue
			for idx in (cell as PackedInt32Array):
				if n >= limit:
					return out
				var uv0: Vector2 = _segs[idx * 2]
				var uv1: Vector2 = _segs[idx * 2 + 1]
				if not rect.intersects(Rect2(uv0.min(uv1), (uv1 - uv0).abs())):
					continue
				var arr: PackedVector2Array = out[_seg_kind[idx]]
				arr.append(t.to_screen_uv(uv0))
				arr.append(t.to_screen_uv(uv1))
				out[_seg_kind[idx]] = arr
				n += 1
	return out


# ================================================================== json
func _lines(path: String) -> Array:
	var d: Variant = _json(path)
	if not (d is Dictionary):
		return []
	return (d as Dictionary).get("lines", [])


func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
