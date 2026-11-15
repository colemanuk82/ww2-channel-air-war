extends RefCounted
## Lat/lon <-> screen maths for the map editor's whole-map 2D view. Pure and stateless apart from the
## four view fields, so the view and the unit tests share one transform.
##
## The map is drawn as a rectangle in "map space": u runs 0 -> 1 west to east, v runs 0 -> 1 north to
## south, and `center` is the map-space point under the middle of the viewport. Zoom 1 fits the whole
## map in the viewport; 80 is street level.
##
##   var t := MapTransform.new()
##   t.size = Vector2(1280.0, 720.0); t.zoom = 4.0
##   var p: Vector2 = t.to_screen(51.2, 1.4)
##   var ll: Vector2 = t.to_latlon(p)      # == Vector2(51.2, 1.4)

const ZOOM_MIN: float = 1.0
const ZOOM_MAX: float = 80.0

var size: Vector2 = Vector2(1280.0, 720.0)      # viewport size in pixels
var center: Vector2 = Vector2(0.5, 0.5)         # map-space point at the viewport middle
var zoom: float = 1.0                           # 1.0 = the whole map fitted to the viewport


## Map width / height in world metres, from the game's own projection constants.
static func map_aspect() -> float:
	var w: float = (WorldCoords.LON_MAX - WorldCoords.LON_MIN) * WorldCoords.units_per_deg_lon
	var h: float = (WorldCoords.LAT_MAX - WorldCoords.LAT_MIN) * WorldCoords.units_per_deg_lat
	return w / h


## The drawn map size in pixels: fitted to the viewport, then scaled by `zoom`.
func map_size() -> Vector2:
	var base: float = minf(size.x, size.y * map_aspect())
	return Vector2(base * zoom, base * zoom / map_aspect())


## Latitude and longitude of a screen point. Returns Vector2(lat, lon).
func to_latlon(p: Vector2) -> Vector2:
	var uv: Vector2 = center + (p - size * 0.5) / map_size()
	return Vector2(WorldCoords.LAT_MAX - uv.y * (WorldCoords.LAT_MAX - WorldCoords.LAT_MIN),
		WorldCoords.LON_MIN + uv.x * (WorldCoords.LON_MAX - WorldCoords.LON_MIN))


## Screen position of a latitude and longitude.
func to_screen(lat: float, lon: float) -> Vector2:
	return to_screen_uv(uv(lat, lon))


## Map-space (u, v) of a latitude and longitude.
func uv(lat: float, lon: float) -> Vector2:
	return uv_static(lat, lon)


## The same mapping without a view, for the bake and the tests: u east, v south, both 0 -> 1.
static func uv_static(lat: float, lon: float) -> Vector2:
	return Vector2((lon - WorldCoords.LON_MIN) / (WorldCoords.LON_MAX - WorldCoords.LON_MIN),
		(WorldCoords.LAT_MAX - lat) / (WorldCoords.LAT_MAX - WorldCoords.LAT_MIN))


## Screen position of a map-space point.
func to_screen_uv(p: Vector2) -> Vector2:
	return size * 0.5 + (p - center) * map_size()


## The map-space rectangle the viewport currently shows.
func view_rect() -> Rect2:
	var half: Vector2 = (size * 0.5) / map_size()
	return Rect2(center - half, half * 2.0)


## Pixels per kilometre north-south (sweep radii and the scale bar use this).
func px_per_km() -> float:
	var km: float = (WorldCoords.LAT_MAX - WorldCoords.LAT_MIN) * WorldCoords.METERS_PER_DEG_LAT / 1000.0
	return map_size().y / km


## Pixels per world metre. The world is 1:1 horizontally, so radii in metres scale directly.
func px_per_m() -> float:
	var m: float = (WorldCoords.LAT_MAX - WorldCoords.LAT_MIN) * WorldCoords.METERS_PER_DEG_LAT
	return map_size().y / m


## A rounded scale-bar length that is at least ~60 px here: Vector2(end_x, km).
func scale_bar(from_x: float) -> Vector2:
	var pkm: float = maxf(px_per_km(), 1.0e-6)
	var km: float = 500.0
	for cand in [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0]:
		km = cand
		if cand * pkm >= 60.0:
			break
	return Vector2(from_x + km * pkm, km)


## Zoom by `factor` while keeping the lat/lon under `at` (a screen point) fixed.
func zoom_at(at: Vector2, factor: float) -> void:
	var before: Vector2 = to_latlon(at)
	zoom = clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	center += (to_screen(before.x, before.y) - at) / map_size()
	clamp_center()


## Pan by a screen-pixel delta (drag).
func pan_px(delta: Vector2) -> void:
	center -= delta / map_size()
	clamp_center()


## Keep the viewport from wandering off the map. Small viewports may see past an edge, so the
## centre is only clamped when the map is at least as large as the viewport on that axis.
func clamp_center() -> void:
	var ms: Vector2 = map_size()
	var hx: float = 0.0 if ms.x < size.x else (size.x * 0.5) / ms.x
	var hy: float = 0.0 if ms.y < size.y else (size.y * 0.5) / ms.y
	center = Vector2(clampf(center.x, hx, 1.0 - hx), clampf(center.y, hy, 1.0 - hy))
