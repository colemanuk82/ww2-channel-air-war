extends Control
## The editor's whole-map 2D view. It blits the baked base map (MapBase) and paints the live parts on
## top: town and airfield dots, the edit rows as icons, remove circles, the selection and the
## in-progress remove circle. Past OVERLAY_ZOOM the baked roads are coarser than the screen, so the
## real road segments near the viewport are drawn over the top.
##
## The view holds no edit state of its own: it reads `ed.edits`, `ed.tool` and `ed.sel_ids`, and calls
## back into `ed` for every editing action, so undo, redo and saving all live in one place. The one
## thing it does own is the rubber band: `_band_from` is where an empty-ground drag started, and
## the band is handed to the editor as a screen rectangle when the button comes up.
##
## With the Select tool a drag on empty ground draws that band (it no longer pans - pan with the
## right or middle button); a drag that starts on a selected edit moves the whole selection.

const MapTransform := preload("res://tools/map_editor/map_transform.gd")
const MapBase := preload("res://tools/map_editor/map_base.gd")
const EditSelection := preload("res://tools/map_editor/edit_selection.gd")

const SEA: Color = Color(0.05, 0.07, 0.1)
const CITY: Color = Color(0.98, 0.9, 0.66)
const RAF: Color = Color(0.45, 0.72, 1.0)
const LUFT: Color = Color(1.0, 0.5, 0.42)
const BUILDING: Color = Color(1.0, 0.78, 0.35)
const PROP: Color = Color(0.6, 0.92, 0.55)
const REMOVE: Color = Color(1.0, 0.36, 0.3)
const SELECT: Color = Color(1.0, 0.92, 0.25)

const GRID_MIN_PX: float = 60.0      # the map grid's cell is at least this wide on screen...
const GRID_MAX_PX: float = 120.0     # ...and at most this, halving the step when it would be wider
const GRID_KM_STEPS: Array = [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0]
const GRID_COL: Color = Color(1.0, 1.0, 1.0, 0.13)
const BAND_COL: Color = Color(1.0, 0.92, 0.25)

const OVERLAY_ZOOM: float = 10.0     # from here the vector roads are drawn over the baked raster
const LABEL_ZOOM: float = 5.0        # edit labels
const CITY_ZOOM: float = 4.0         # city names
const AIRFIELD_ZOOM: float = 6.0     # airfield names

## The editor shell (map_editor.gd). Deliberately untyped: the view drives it by duck typing
## (ed.tool, ed.edits, ed.select_id...), and typing it as Node would make every such call an error.
var ed = null
var t: MapTransform = MapTransform.new()
var base: MapBase = null

var _press: Vector2 = Vector2.ZERO
var _mouse: Vector2 = Vector2.ZERO
var _moved: float = 0.0
var _panning: bool = false
var _press_was_pan: bool = false
var _drag_id: String = ""
var _band_from: Vector2 = Vector2.ZERO   # the rubber band's fixed corner
var _banding: bool = false
var _mouse_seen: bool = false            # true once the mouse has been over the view
var _remove_from: Vector2 = Vector2.ZERO
var _overlay: Dictionary = {}
var _overlay_key: String = ""


func _init() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP


func resize_to(s: Vector2) -> void:
	t.size = s
	invalidate()


## Forget the cached road overlay (after a pan or a zoom).
func invalidate() -> void:
	_overlay_key = ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		t.size = size
		invalidate()


# ================================================================== input
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_button(event)
	elif event is InputEventMouseMotion:
		_motion(event)


func _button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if mb.pressed:
			t.zoom_at(mb.position, 1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.25)
			invalidate()
			queue_redraw()
			accept_event()
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		_mouse = mb.position
		_mouse_seen = true
		if mb.pressed:
			_press = mb.position
			_moved = 0.0
			_press_left(mb)
		else:
			_release_left(mb)
		accept_event()
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
		if mb.pressed:
			_panning = true
			_press = mb.position
		else:
			_panning = false
		accept_event()


func _press_left(mb: InputEventMouseButton) -> void:
	match str(ed.tool):
		"remove":
			_remove_from = mb.position
			ed.remove_begin(t.to_latlon(mb.position))
		"select":
			var id: String = hit(mb.position)
			if id.is_empty():
				# Empty ground: the press opens a rubber band (see _release_left).
				_band_from = mb.position
				_banding = true
				queue_redraw()
			elif mb.shift_pressed:
				ed.toggle_select(id)
			else:
				if not ed.is_selected(id):
					ed.select_id(id)
				_drag_id = id
				ed.begin_drag(t.to_latlon(mb.position))
		_:
			_drag_id = ""


func _release_left(mb: InputEventMouseButton) -> void:
	var panned: bool = _panning
	_panning = false
	if str(ed.tool) == "remove":
		ed.commit_remove()
		_remove_from = Vector2.ZERO
		queue_redraw()
		return
	if _banding:
		_banding = false
		if _moved < 4.0:
			# A click, not a band: an empty-ground click clears the selection.
			var ll: Vector2 = t.to_latlon(mb.position)
			ed.map_click(ll.x, ll.y, mb.shift_pressed)
		else:
			ed.select_band(band_rect())
		queue_redraw()
		return
	if not _drag_id.is_empty():
		if _moved >= 3.0:
			ed.end_drag()
		else:
			# A click on one of several selected edits narrows the selection to just that one.
			ed.select_id(_drag_id)
		_drag_id = ""
		return
	if _moved < 6.0:
		var ll: Vector2 = t.to_latlon(mb.position)
		ed.map_click(ll.x, ll.y, mb.shift_pressed)
		return
	if panned:
		queue_redraw()


func _motion(mm: InputEventMouseMotion) -> void:
	_mouse = mm.position
	_mouse_seen = true
	_moved += mm.relative.length()
	var held: bool = (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if not _drag_id.is_empty() and held:
		var ll: Vector2 = t.to_latlon(mm.position)
		ed.drag_to(ll.x, ll.y)
	elif str(ed.tool) == "remove" and held and _remove_from != Vector2.ZERO:
		ed.remove_drag(t.to_latlon(mm.position))
	elif _panning and (held or (mm.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)) != 0):
		t.pan_px(mm.relative)
		invalidate()
	queue_redraw()


## The id of the edit under `p`, or "" when there is none.
func hit(p: Vector2) -> String:
	var best: String = ""
	var best_d: float = 14.0
	for e in ed.edits:
		var row: Dictionary = e
		var c: Vector2 = t.to_screen(float(row.get("lat", 0.0)), float(row.get("lon", 0.0)))
		if absf(p.x - c.x) > 400.0 or absf(p.y - c.y) > 400.0:
			continue
		var d: float = c.distance_to(p)
		if str(row.get("op", "")) == "remove":
			var r: float = maxf(float(row.get("radius", 0.0)) * t.px_per_m(), 3.0)
			if absf(d - r) <= 8.0 and absf(d - r) < best_d:
				best_d = absf(d - r)
				best = str(row.get("id", ""))
			if d <= best_d:
				best_d = d
				best = str(row.get("id", ""))
		elif d < best_d:
			best_d = d
			best = str(row.get("id", ""))
	return best


## True when this edit is part of the selection.
func is_selected(id: String) -> bool:
	return not id.is_empty() and (ed.sel_ids as Array).has(id)


func _icon_px() -> float:
	return clampf(2.5 + t.zoom * 0.75, 4.0, 14.0)


func _on_screen(p: Vector2, pad: float = 60.0) -> bool:
	return p.x > -pad and p.y > -pad and p.x < size.x + pad and p.y < size.y + pad


func mouse_pos() -> Vector2:
	return _mouse


## False until the mouse has actually been over the map, so the editor never pastes at a stale spot.
func mouse_seen() -> bool:
	return _mouse_seen


## Lat/lon under the mouse.
func mouse_latlon() -> Vector2:
	return t.to_latlon(_mouse)


## The rubber band as it currently stands (a normalised screen rectangle).
func band_rect() -> Rect2:
	return Rect2(_band_from, _mouse - _band_from).abs()


## Point the view at a latitude and longitude, zooming in a little when it is zoomed right out.
## Used by the go-to box. `min_zoom` of 0 leaves the zoom alone.
func look_at_latlon(lat: float, lon: float, min_zoom: float = 0.0) -> void:
	if min_zoom > 0.0 and t.zoom < min_zoom:
		t.zoom = clampf(min_zoom, MapTransform.ZOOM_MIN, MapTransform.ZOOM_MAX)
	t.center = t.uv(lat, lon)
	t.clamp_center()
	invalidate()
	queue_redraw()


## The map grid's cell size in km for a given scale: the smallest step that is at least
## GRID_MIN_PX wide, halved once when it would be wider than GRID_MAX_PX. So the lines always land
## 60-120 px apart, whatever the zoom. Pure, so the tests can check the range directly.
static func grid_km(px_per_km: float) -> float:
	var p: float = maxf(px_per_km, 1.0e-6)
	for c in GRID_KM_STEPS:
		var s: float = float(c)
		if s * p >= GRID_MIN_PX:
			return s * 0.5 if s * p > GRID_MAX_PX else s
	return float(GRID_KM_STEPS[GRID_KM_STEPS.size() - 1])


## A km value as it reads on the grid caption: whole km, metres below 1 km, one decimal otherwise.
static func grid_label(km: float) -> String:
	if km < 1.0:
		return "%d m" % int(round(km * 1000.0))
	if is_equal_approx(km, roundf(km)):
		return "%d km" % int(round(km))
	return "%.1f km" % km


# ================================================================== draw
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SEA)
	if base != null and base.texture != null:
		var ms: Vector2 = t.map_size()
		draw_texture_rect(base.texture, Rect2(size * 0.5 - t.center * ms, ms), false)
	_draw_grid()
	_draw_roads()
	_draw_places()
	_draw_removes()
	_draw_adds()
	_draw_sel_box()
	_draw_pending_remove()
	_draw_band()
	_draw_overlays()


func _draw_roads() -> void:
	if t.zoom < OVERLAY_ZOOM or base == null:
		return
	var key: String = "%.5f|%.5f|%.4f|%.1f|%.1f" % [t.center.x, t.center.y, t.zoom, size.x, size.y]
	if key != _overlay_key:
		_overlay = base.visible_roads(t.view_rect(), t)
		_overlay_key = key
	for ki in MapBase.ROAD_KINDS.size():
		var pts: PackedVector2Array = _overlay.get(ki, PackedVector2Array())
		if pts.is_empty():
			continue
		var kind: String = str(MapBase.ROAD_KINDS[ki])
		var w: float = 1.0 + float(MapBase.ROAD_PX[kind]) * (0.6 + t.zoom / 24.0)
		draw_multiline(pts, Color(MapBase.ROAD_COLS[kind], 0.9), w)


func _draw_places() -> void:
	if base == null:
		return
	var font: Font = ThemeDB.fallback_font
	for c in base.cities:
		var row: Dictionary = c
		var p: Vector2 = t.to_screen(float(row["lat"]), float(row["lon"]))
		if not _on_screen(p):
			continue
		var sz: float = 2.0 + float(row.get("size", 1)) * 0.9
		draw_circle(p, sz + 1.0, Color(0, 0, 0, 0.55))
		draw_circle(p, sz, CITY)
		if t.zoom >= CITY_ZOOM:
			draw_string(font, p + Vector2(sz + 4.0, 4.0), str(row["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1,
				_font_px(), Color(CITY, 0.92))
	for a in base.airfields:
		var af: Dictionary = a
		var p: Vector2 = t.to_screen(float(af["lat"]), float(af["lon"]))
		if not _on_screen(p):
			continue
		var col: Color = RAF if str(af.get("side", "")) == "RAF" else LUFT
		var r: float = _icon_px() * 0.8
		draw_circle(p, r + 1.2, Color(0, 0, 0, 0.65))
		draw_circle(p, r, col)
		if t.zoom >= AIRFIELD_ZOOM:
			draw_string(font, p + Vector2(r + 4.0, 4.0), str(af["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1,
				_font_px(), Color(col, 0.95))


func _draw_removes() -> void:
	var font: Font = ThemeDB.fallback_font
	for e in ed.edits:
		var row: Dictionary = e
		if str(row.get("op", "")) != "remove":
			continue
		var c: Vector2 = t.to_screen(float(row["lat"]), float(row["lon"]))
		var r: float = maxf(float(row["radius"]) * t.px_per_m(), 3.0)
		if c.x + r < -20.0 or c.y + r < -20.0 or c.x - r > size.x + 20.0 or c.y - r > size.y + 20.0:
			continue
		var sel: bool = is_selected(str(row.get("id", "")))
		draw_circle(c, r, Color(REMOVE, 0.22 if sel else 0.11))
		draw_arc(c, r, 0.0, TAU, 48, Color(REMOVE, 1.0 if sel else 0.85), 2.5 if sel else 1.5, true)
		if sel:
			draw_arc(c, r + 3.0, 0.0, TAU, 48, SELECT, 1.5, true)
		if t.zoom >= LABEL_ZOOM:
			draw_string(font, c + Vector2(r + 4.0, 4.0), "%d m" % int(row["radius"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, _font_px(), Color(REMOVE, 0.9))


func _draw_adds() -> void:
	var ic: float = _icon_px()
	var font: Font = ThemeDB.fallback_font
	for e in ed.edits:
		var row: Dictionary = e
		if str(row.get("op", "")) != "add":
			continue
		var p: Vector2 = t.to_screen(float(row["lat"]), float(row["lon"]))
		if not _on_screen(p):
			continue
		var key: String = str(row.get("asset", ""))
		var building: bool = MapAssets.category(key) == "building"
		var col: Color = BUILDING if building else PROP
		var yaw: float = deg_to_rad(float(row.get("yaw", 0.0)))
		var fwd := Vector2(sin(yaw), -cos(yaw))
		var side := fwd.orthogonal()
		var sel: bool = is_selected(str(row.get("id", "")))
		if building:
			var q := PackedVector2Array([p + fwd * ic + side * ic, p + fwd * ic - side * ic,
				p - fwd * ic - side * ic, p - fwd * ic + side * ic])
			draw_colored_polygon(q, Color(col, 0.92))
			draw_polyline(PackedVector2Array([q[0], q[1], q[2], q[3], q[0]]), Color(0, 0, 0, 0.75), 1.0)
			draw_line(p, p + fwd * (ic + 2.0), Color(col.darkened(0.35), 0.9), 1.0)
		else:
			draw_circle(p, ic * 0.62, Color(0, 0, 0, 0.7))
			draw_circle(p, ic * 0.5, Color(col, 0.95))
			draw_line(p, p + fwd * (ic + 1.5), Color(col.darkened(0.3), 0.85), 1.0)
		if sel:
			draw_arc(p, ic + 4.0, 0.0, TAU, 24, SELECT, 2.0, true)
		if t.zoom >= LABEL_ZOOM:
			draw_string(font, p + Vector2(ic + 4.0, 4.0), MapAssets.label(key), HORIZONTAL_ALIGNMENT_LEFT, -1,
				_font_px(), Color(col.lightened(0.35), 0.92))


## The map grid: 1-, 2- or 5-times-a-decade km lines, drawn only where they fall on screen. The step
## is chosen by grid_km() from the current scale, so the cell stays roughly the same size on screen.
func _draw_grid() -> void:
	if not bool(ed.grid_on):
		return
	var km: float = grid_km(t.px_per_km())
	if km <= 0.0:
		return
	var rect: Rect2 = t.view_rect()
	var dlat: float = km * 1000.0 / WorldCoords.METERS_PER_DEG_LAT
	var dlon: float = km * 1000.0 / WorldCoords.units_per_deg_lon
	if dlat <= 0.0 or dlon <= 0.0:
		return
	var lat_top: float = WorldCoords.LAT_MAX - rect.position.y * (WorldCoords.LAT_MAX - WorldCoords.LAT_MIN)
	var lat_bot: float = WorldCoords.LAT_MAX - rect.end.y * (WorldCoords.LAT_MAX - WorldCoords.LAT_MIN)
	var lon_l: float = WorldCoords.LON_MIN + rect.position.x * (WorldCoords.LON_MAX - WorldCoords.LON_MIN)
	var lon_r: float = WorldCoords.LON_MIN + rect.end.x * (WorldCoords.LON_MAX - WorldCoords.LON_MIN)
	var guard: int = 0
	var lon: float = ceilf(lon_l / dlon) * dlon
	while lon <= lon_r and guard < 400:
		var x: float = t.to_screen(0.0, lon).x
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), GRID_COL, 1.0)
		lon += dlon
		guard += 1
	guard = 0
	var lat: float = ceilf(lat_bot / dlat) * dlat
	while lat <= lat_top and guard < 400:
		var y: float = t.to_screen(lat, 0.0).y
		draw_line(Vector2(0.0, y), Vector2(size.x, y), GRID_COL, 1.0)
		lat += dlat
		guard += 1


## A thin box round the selection when more than one edit is selected, so a group reads as a group
## even before you touch it.
func _draw_sel_box() -> void:
	if ed.sel_ids.size() < 2:
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for e in ed.edits:
		var row: Dictionary = e
		if not is_selected(str(row.get("id", ""))):
			continue
		var p: Vector2 = t.to_screen(float(row.get("lat", 0.0)), float(row.get("lon", 0.0)))
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	if lo.x > hi.x:
		return
	var pad: float = _icon_px() + 6.0
	var r := Rect2(lo - Vector2(pad, pad), (hi - lo) + Vector2(pad, pad) * 2.0)
	draw_rect(r, Color(SELECT, 0.55), false, 1.5)
	# Mark the group centre: it is what Q / E rotate the group about (EditSelection.centre, the same
	# maths the rotate itself uses).
	var mid: Vector2 = EditSelection.centre(ed.edits, ed.sel_ids)
	if mid.x < 0.0:
		return
	var c: Vector2 = t.to_screen(mid.x, mid.y)
	draw_line(c + Vector2(-6.0, 0.0), c + Vector2(6.0, 0.0), SELECT, 1.5)
	draw_line(c + Vector2(0.0, -6.0), c + Vector2(0.0, 6.0), SELECT, 1.5)


## The rubber band while it is being dragged out.
func _draw_band() -> void:
	if not _banding or _moved < 4.0:
		return
	var r: Rect2 = band_rect()
	draw_rect(r, Color(BAND_COL, 0.10), true)
	draw_rect(r, Color(BAND_COL, 0.9), false, 1.5)


func _draw_pending_remove() -> void:
	if str(ed.tool) != "remove" or _remove_from == Vector2.ZERO or _moved <= 2.0:
		return
	var r: float = _remove_from.distance_to(_mouse)
	draw_circle(_remove_from, r, Color(REMOVE, 0.18))
	draw_arc(_remove_from, r, 0.0, TAU, 48, REMOVE, 2.0, true)
	draw_string(ThemeDB.fallback_font, _remove_from + Vector2(0.0, -r - 6.0), "%d m" % int(ed.pixels_to_metres(r)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, REMOVE)


func _draw_overlays() -> void:
	var font: Font = ThemeDB.fallback_font
	var hint: String = str(ed.tool_hint())
	if not hint.is_empty():
		var w: float = minf(size.x - 24.0, 980.0)
		draw_rect(Rect2(Vector2(10.0, 10.0), Vector2(w, 26.0)), Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(18.0, 28.0), hint, HORIZONTAL_ALIGNMENT_LEFT, w - 16.0, 15, Color(1, 1, 1, 0.94))
	var ll: Vector2 = t.to_latlon(_mouse)
	draw_string(font, Vector2(14.0, size.y - 14.0),
		"%.4f N   %.4f E      wheel: zoom   right-drag: pan" % [ll.x, ll.y],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.72))
	_draw_scale_bar(font)
	draw_string(font, Vector2(size.x - 24.0, 30.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))


func _draw_scale_bar(font: Font) -> void:
	var from := Vector2(20.0, size.y - 36.0)
	var sb: Vector2 = t.scale_bar(from.x)
	draw_line(from, Vector2(sb.x, from.y), Color(1, 1, 1, 0.85), 2.0)
	draw_line(from + Vector2(0.0, -4.0), from + Vector2(0.0, 4.0), Color(1, 1, 1, 0.85), 2.0)
	draw_line(Vector2(sb.x, from.y - 4.0), Vector2(sb.x, from.y + 4.0), Color(1, 1, 1, 0.85), 2.0)
	draw_string(font, Vector2(from.x, from.y - 7.0), "%d km" % int(sb.y), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(1, 1, 1, 0.85))
	if bool(ed.grid_on):
		draw_string(font, Vector2(sb.x + 10.0, from.y - 7.0), "grid %s" % grid_label(grid_km(t.px_per_km())),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))


func _font_px() -> int:
	return int(clampf(12.0 * (1.0 + (t.zoom - 1.0) * 0.012), 12.0, 18.0))
