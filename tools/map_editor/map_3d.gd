extends Control
## PHASE 3 - the map editor's close-up 3D world window.
##
## A top-down view of the game's REAL streamed world (terrain + scenery tiles) around a lat/lon,
## built out of the game's own streamers so that what Craig sees here is exactly what the game
## generates at that spot:
##
##   TerrainChunkManager (scripts/terrain_chunk_manager.gd) - the LOD terrain chunks, group "terrain".
##   WorldPopulator      (scripts/world_populator.gd)       - the countryside scenery tiles (houses,
##       gardens, hedges, trees, roads, rivers, railways), the airfields, the towns and the hand-made
##       map edits from data/map_edits.json. Created exactly the way WorldPopulator.populate() creates
##       it, only with the ambient road / rail / sea traffic switched off: this is a tool, not the game,
##       and a convoy driving past is not scenery to place by.
##   WaterPlane          (scripts/water_plane.gd)           - the sea.
##
## Both streamers follow a plain Node3D (the "focus"), so no aircraft, camera rig, HUD, audio or mode
## is involved: the view just moves that node. Lighting and the sky come from the TimeOfDay autoload's
## own sun and WorldEnvironment, because this view shares the root viewport's World3D (set
## `use_game_lighting = false` to get a private sun + flat sky instead).
##
## The whole world lives inside a SubViewport, so the window can be swapped in place of the 2D view
## (MapView) in the editor's layout, sits inside the panel it is given and is clipped by it.
##
## ---- API the integrator calls ---------------------------------------------------------------
##   const Map3D := preload("res://tools/map_editor/map_3d.gd")   # no class_name in tools/: preload it like the other editor scripts
##   var view := Map3D.new()
##   view.open(host, lat, lon, metres_per_px) -> void   # build (or reuse) the world, stream it there
##   view.set_focus(lat: float, lon: float) -> void     # look somewhere else (host driven: NO signal)
##   view.get_focus() -> Vector2                        # Vector2(lat, lon) at the middle of the view
##   view.close() -> void                               # stop streaming, leave the tree, keep the instance
##   view.focus_moved(lat, lon)                         # SIGNAL: the user panned / zoomed / resized
##   view.set_zoom(metres_per_px) / view.get_zoom() -> float
##   view.is_open() -> bool
##   view.refresh_edits(rows) -> Dictionary  # show the editor's (unsaved) document now; no-op when closed
##   view.is_settled() -> bool      # terrain chunks and scenery tiles have stopped arriving
##   view.stats() -> Dictionary     # counters for the tests and the shot log
##   view.latlon_at(px) -> Vector2 / view.screen_of(lat, lon) -> Vector2
##
## open() adds the view to `host` (any Node, normally the editor's map container), makes it visible and
## builds the world on the first call; later calls only move the camera. close() tears the world down
## (the game's own _exit_tree code joins its worker threads), removes the view from its parent and
## hides it - the instance stays alive, so open() can be called again.
##
## Mouse: the wheel zooms about the cursor, right-drag or middle-drag pans. The view is never rotated:
## north is up and east is right, exactly like the 2D map. Nothing else is intercepted, so the editor's
## own keyboard handling keeps working.
##
## Lat/lon <-> world is WorldCoords.latlon_to_world / world_to_latlon only (scripts/world_coords.gd);
## this file never re-implements the projection. The camera is orthographic, so `metres_per_px` is an
## exact scale from the middle to the edge of the view (no perspective foreshortening).

const TerrainScript := preload("res://scripts/terrain_chunk_manager.gd")
const PopulatorScript := preload("res://scripts/world_populator.gd")
const SeaScript := preload("res://scripts/water_plane.gd")

signal focus_moved(lat: float, lon: float)
## A plain left click that was not a drag, in the lat/lon under it. The editor routes tool clicks
## through this while the 3D window is open (its 2D view is hidden then); drags are left alone.
signal clicked(lat: float, lon: float, shift: bool)

# Orthographic, so the camera height does NOT set the scale (metres_per_px does). It must still stay
# close to the ground: the game's fog and aerial perspective are distance fog built for a camera a few
# hundred metres up, and 8 km up painted a pale veil over the whole picture. 1.2 km is clear.
const CAM_HEIGHT: float = 1200.0
const CAM_NEAR: float = 1.0
const CAM_FAR: float = 2400.0       # the ground sits CAM_HEIGHT below the camera, plus the highest hills
const MPP_MIN: float = 0.15             # metres per control pixel, closest / furthest
const MPP_MAX: float = 60.0
const MPP_DEFAULT: float = 1.5
const ZOOM_STEP: float = 1.25
const EAGER_SECONDS: float = 3.0        # WorldPopulator.boost for at least this long (the load-screen path)
const EAGER_MAX: float = 40.0           # ... and no longer than this, however slow the machine
const VIEW_MARGIN_TILES: float = 1.0    # a tile is "in view" when it comes this close to the visible rectangle
const MIN_RENDER_PX: int = 64           # the render target never shrinks below this
const OVERLAY_REFRESH: float = 0.25
const REFRESH_EAGER_SECONDS: float = 0.5   # after an edit: eager until settled, at least this long

var metres_per_px: float = MPP_DEFAULT
var show_overlay: bool = false          # crosshair, scale bar and a readout (the shot scene uses it)
var eager_seconds: float = EAGER_SECONDS
var use_game_lighting: bool = true      # share the root World3D, i.e. TimeOfDay's sun, sky and fog
var msaa_level: Viewport.MSAA = Viewport.MSAA_2X

var _lat: float = 49.18
var _lon: float = -0.36
var _open: bool = false
var _frame: SubViewportContainer = null
var _vp: SubViewport = null
var _world: Node3D = null
var _terrain: Node = null
var _wp: Node = null
var _sea: Node = null
var _focus: Node3D = null
var _cam: Camera3D = null
var _overlay: Control = null
var _eager_t: float = 0.0               # how long the eager (boost) fill has been on
var _eager_on: bool = false
var _eager_need: float = EAGER_SECONDS  # the least time the current eager spell lasts
var _refreshes: int = 0                 # refresh_edits calls since the world was built (stats)
var _overlay_t: float = 0.0
var _panning: bool = false
var _pan_press: Vector2 = Vector2.ZERO
var _click_press: Vector2 = Vector2.ZERO   # where the current left press started (tool clicks)
var _build_ms: int = 0
var _terrain_ms: int = 0
var _populator_ms: int = 0


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	visible = false


# ================================================================== open / close
## Build (or reuse) the world and look at lat/lon. `metres_per_px` is metres of ground per pixel of
## this control; open() adds the view to `host` and makes it visible.
func open(host: Node, lat: float, lon: float, metres_per_px_value: float) -> void:
	metres_per_px = clampf(metres_per_px_value, MPP_MIN, MPP_MAX)
	_lat = clampf(lat, WorldCoords.LAT_MIN, WorldCoords.LAT_MAX)
	_lon = clampf(lon, WorldCoords.LON_MIN, WorldCoords.LON_MAX)
	if host != null and get_parent() != host:
		if get_parent() != null:
			get_parent().remove_child(self)
		host.add_child(self)
	_fill_host()
	visible = true
	if _vp == null:
		_build_widget()
	if _world == null:
		_build_world()
	_apply_camera()
	_open = true
	print("[map3d] open %.5f,%.5f  %.2f m/px  world build %d ms (terrain %d, populator %d)" % [
		_lat, _lon, metres_per_px, _build_ms, _terrain_ms, _populator_ms])


## Stop streaming and leave the tree (the world is freed, this instance is kept for a later open()).
func close() -> void:
	_open = false
	_teardown_world()
	visible = false
	if get_parent() != null:
		get_parent().remove_child(self)
	print("[map3d] closed")


## Fill a plain Control host (a Container sizes its children itself, so it is left alone).
func _fill_host() -> void:
	var p: Node = get_parent()
	if p == null or p is Container:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func is_open() -> bool:
	return _open


## The editor's document changed: show `rows` (MapEdits rows, saved or not) in the live world at once.
## Only the touched hand-made sites and the scenery tiles under changed remove circles are rebuilt (see
## WorldPopulator.refresh_map_edits), and streaming goes eager again until the view has settled. No-op
## while the window is closed. Returns the populator's counts ({} when closed).
func refresh_edits(rows: Array) -> Dictionary:
	if not _open or _wp == null or not _wp.has_method("refresh_map_edits"):
		return {}
	var t0: int = Time.get_ticks_usec()
	var r: Dictionary = _wp.call("refresh_map_edits", rows)
	_refreshes += 1
	if int(r.get("added", 0)) + int(r.get("moved", 0)) + int(r.get("dropped", 0)) + int(r.get("tiles", 0)) > 0:
		print("[map3d] edits refreshed in %.1f ms: +%d moved %d -%d, %d tiles to rebuild" % [
			float(Time.get_ticks_usec() - t0) / 1000.0, int(r.get("added", 0)), int(r.get("moved", 0)),
			int(r.get("dropped", 0)), int(r.get("tiles", 0))])
		_go_eager(REFRESH_EAGER_SECONDS)
	return r


## Turn the populator's load-screen budget on until the view has settled (and at least `min_s` seconds).
func _go_eager(min_s: float) -> void:
	if eager_seconds <= 0.0 or _wp == null:
		return
	_eager_t = 0.0
	_eager_need = min_s
	_eager_on = true
	_wp.set("boost", true)


## Look somewhere else. Host driven, so no focus_moved is emitted (the view is being told, not asked).
func set_focus(lat: float, lon: float) -> void:
	_lat = clampf(lat, WorldCoords.LAT_MIN, WorldCoords.LAT_MAX)
	_lon = clampf(lon, WorldCoords.LON_MIN, WorldCoords.LON_MAX)
	_apply_camera()


## Vector2(lat, lon) at the middle of the view.
func get_focus() -> Vector2:
	return Vector2(_lat, _lon)


func set_zoom(metres_per_px_value: float) -> void:
	metres_per_px = clampf(metres_per_px_value, MPP_MIN, MPP_MAX)
	_apply_camera()


func get_zoom() -> float:
	return metres_per_px


## True once the ground under the view has arrived: every terrain chunk overlapping the visible
## rectangle has been built AND every scenery tile overlapping it is in the scene.
##
## Deliberately NOT TerrainChunkManager.is_settled() / WorldPopulator.pending: the game streams out to
## its 48 km far ring and 12.8 km scenery radius, which a close-up editor window would wait a minute for
## and never needs. The two streamers still do all their own work; this only asks whether what the user
## can see is there yet.
func is_settled() -> bool:
	return _view_chunks_present() and _view_tiles_present()


## True when every terrain chunk overlapping the view exists and carries a mesh.
func _view_chunks_present() -> bool:
	if _terrain == null:
		return false
	var cv: Variant = _terrain.get("_chunks")
	if not (cv is Dictionary):
		return true
	var have: Dictionary = cv
	var cs: float = float(_terrain.get("chunk_size"))
	if cs <= 0.0:
		return true
	var c: Vector3 = WorldCoords.latlon_to_world(_lat, _lon)
	var half: Vector2 = size * 0.5 * metres_per_px
	for kz in range(floori((c.z - half.y) / cs), floori((c.z + half.y) / cs) + 1):
		for kx in range(floori((c.x - half.x) / cs), floori((c.x + half.x) / cs) + 1):
			var key := Vector2i(kx, kz)
			if not have.has(key):
				return false
			var rec: Variant = have[key]
			if not (rec is Dictionary):
				return false
			var node: Variant = (rec as Dictionary).get("node")
			if node == null or not is_instance_valid(node):
				return false
	return true


## How many terrain chunks overlapping the view have been built: Vector2i(present, wanted).
func _view_chunk_count() -> Vector2i:
	var cs: float = float(_terrain.get("chunk_size")) if _terrain != null else 2000.0
	if cs <= 0.0:
		return Vector2i(0, 0)
	var c: Vector3 = WorldCoords.latlon_to_world(_lat, _lon)
	var half: Vector2 = size * 0.5 * metres_per_px
	var have: Variant = _terrain.get("_chunks") if _terrain != null else null
	var n: int = 0
	var want: int = 0
	for kz in range(floori((c.z - half.y) / cs), floori((c.z + half.y) / cs) + 1):
		for kx in range(floori((c.x - half.x) / cs), floori((c.x + half.x) / cs) + 1):
			want += 1
			if have is Dictionary and (have as Dictionary).has(Vector2i(kx, kz)):
				n += 1
	return Vector2i(n, want)


## The scenery tile keys overlapping the visible rectangle, grown by VIEW_MARGIN_TILES.
func _tile_keys_in_view() -> Array:
	var keys: Array = []
	if _wp == null:
		return keys
	var tile: float = _tile_size()
	if tile <= 0.0:
		return keys
	var c: Vector3 = WorldCoords.latlon_to_world(_lat, _lon)
	var half: Vector2 = size * 0.5 * metres_per_px
	var x0: int = floori((c.x - half.x) / tile) - int(ceil(VIEW_MARGIN_TILES))
	var x1: int = floori((c.x + half.x) / tile) + int(ceil(VIEW_MARGIN_TILES))
	var z0: int = floori((c.z - half.y) / tile) - int(ceil(VIEW_MARGIN_TILES))
	var z1: int = floori((c.z + half.y) / tile) + int(ceil(VIEW_MARGIN_TILES))
	for kz in range(z0, z1 + 1):
		for kx in range(x0, x1 + 1):
			keys.append(Vector2i(kx, kz))
	return keys


## True when every tile overlapping the view has been built (the populator keeps them in `_tiles`).
func _view_tiles_present() -> bool:
	if _wp == null:
		return false
	var tv: Variant = _wp.get("_tiles")
	if not (tv is Dictionary):
		return true
	var have: Dictionary = tv
	for k in _tile_keys_in_view():
		if not have.has(k):
			return false
	return true


## How many of the tiles overlapping the view have arrived: Vector2i(present, wanted).
func _view_tile_count() -> Vector2i:
	var keys: Array = _tile_keys_in_view()
	if _wp == null:
		return Vector2i(0, keys.size())
	var tv: Variant = _wp.get("_tiles")
	if not (tv is Dictionary):
		return Vector2i(keys.size(), keys.size())
	var have: Dictionary = tv
	var n: int = 0
	for k in keys:
		if have.has(k):
			n += 1
	return Vector2i(n, keys.size())


## The populator's own countryside tile size in world units (public const on the game's script).
func _tile_size() -> float:
	var v: float = float(PopulatorScript.TILE)
	return v if v > 0.0 else 1800.0


## Counters for the tests and the shot log.
func stats() -> Dictionary:
	var tiles: int = 0
	var chunks: int = 0
	var pending: int = -1
	var sites: int = 0
	if _wp != null:
		var tv: Variant = _wp.get("_tiles")
		if tv is Dictionary:
			tiles = (tv as Dictionary).size()
		sites = _wp.get_child_count()
		var pv: Variant = _wp.get("pending")
		if pv is int:
			pending = int(pv)
	if _terrain != null:
		var cv: Variant = _terrain.get("_chunks")
		if cv is Dictionary:
			chunks = (cv as Dictionary).size()
	var vc: Vector2i = _view_tile_count()
	var cc: Vector2i = _view_chunk_count()
	return {"lat": _lat, "lon": _lon, "metres_per_px": metres_per_px, "build_ms": _build_ms,
		"terrain_ms": _terrain_ms, "populator_ms": _populator_ms, "chunks": chunks,
		"tiles": tiles, "nodes": sites, "pending": pending,
		"view_tiles": vc.y, "view_tiles_have": vc.x, "covered": _view_tiles_present(),
		"view_chunks": cc.y, "view_chunks_have": cc.x, "ground": _view_chunks_present(),
		"settled": is_settled(), "refreshes": _refreshes, "eager": _eager_on}


# ================================================================== widget
func _build_widget() -> void:
	# The container keeps the render target the same size as this control. It is given a real size
	# (MIN_RENDER_PX at the very least) before the viewport exists, because a 0-sized render target
	# makes the renderer fail on its intermediate buffers.
	_frame = SubViewportContainer.new()
	_frame.name = "World"
	_frame.stretch = true
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.custom_minimum_size = Vector2(MIN_RENDER_PX, MIN_RENDER_PX)
	add_child(_frame)
	_vp = SubViewport.new()
	_vp.name = "Viewport"
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = msaa_level
	_vp.use_occlusion_culling = false
	_vp.audio_listener_enable_3d = false
	_vp.handle_input_locally = false
	_frame.add_child(_vp)
	_resize_viewport()
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = show_overlay
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_resize_viewport()
		_apply_camera()


## The container sizes the render target; this only keeps a sensible floor on it (and copes with the
## first frame, when the control has not been laid out yet).
func _resize_viewport() -> void:
	if _frame == null or _vp == null:
		return
	if _frame.size.x < float(MIN_RENDER_PX) or _frame.size.y < float(MIN_RENDER_PX):
		_frame.size = Vector2(maxf(_frame.size.x, float(MIN_RENDER_PX)),
			maxf(_frame.size.y, float(MIN_RENDER_PX)))


# ================================================================== world
func _build_world() -> void:
	var t0: int = Time.get_ticks_msec()
	_teardown_world()
	_world = Node3D.new()
	_world.name = "Map3DWorld"
	_vp.add_child(_world)
	if not (use_game_lighting and _share_game_world()):
		_own_lighting()
	_terrain = TerrainScript.new()
	_terrain.name = "Terrain"
	_world.add_child(_terrain)
	_terrain_ms = Time.get_ticks_msec() - t0
	_focus = Node3D.new()
	_focus.name = "Focus"
	_world.add_child(_focus)
	_terrain.call("set_focus", _focus)
	_sea = SeaScript.new()
	_sea.name = "Sea"
	_world.add_child(_sea)
	_sea.set("focus", _focus)
	var t1: int = Time.get_ticks_msec()
	# Made the way WorldPopulator.populate() makes it (same fields, same add_child), then the ambient
	# traffic is dropped: no convoys, no trains, no shipping in a tool that is meant to show scenery.
	var wp: Node3D = PopulatorScript.new()
	wp.name = "WorldPopulator"
	wp.set("world_root", _world)
	wp.set("terrain", _terrain)
	wp.set("existing_airfields", {})
	wp.set("enable_traffic", false)
	wp.set("enable_countryside", true)
	_world.add_child(wp)
	_wp = wp
	wp.set("focus", _focus)
	_populator_ms = Time.get_ticks_msec() - t1
	_cam = Camera3D.new()
	_cam.name = "Cam"
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = CAM_NEAR
	_cam.far = CAM_FAR
	_cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)     # straight down, north (-Z) up on screen
	_world.add_child(_cam)
	_cam.current = true
	_eager_t = 0.0
	_eager_need = eager_seconds
	_eager_on = eager_seconds > 0.0
	if _eager_on:
		wp.set("boost", true)                             # the load-screen path: fill the area now
	_build_ms = Time.get_ticks_msec() - t0
	print("[map3d] terrain+heightfield %d ms, populator registration %d ms, world %d ms" % [
		_terrain_ms, _populator_ms, _build_ms])


## Share the root viewport's World3D so the TimeOfDay autoload's sun, sky and fog light this view too.
func _share_game_world() -> bool:
	if not is_inside_tree():
		return false
	var root_vp: Viewport = get_tree().root
	if root_vp == null or root_vp.world_3d == null:
		return false
	_vp.world_3d = root_vp.world_3d
	return _vp.world_3d == root_vp.world_3d


## Private fallback lighting for a run with no TimeOfDay (or with use_game_lighting = false).
func _own_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, 140.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = false
	_world.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.68, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.56, 0.63, 0.72)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	_world.add_child(we)


func _teardown_world() -> void:
	if _world != null:
		if _vp != null and _world.is_inside_tree():
			_vp.remove_child(_world)     # -> _exit_tree joins the terrain / populator worker threads
		_world.queue_free()
	_world = null
	_terrain = null
	_wp = null
	_sea = null
	_focus = null
	_cam = null
	_eager_t = 0.0
	_eager_on = false
	_refreshes = 0
	_build_ms = 0
	_terrain_ms = 0
	_populator_ms = 0


func _apply_camera() -> void:
	if _cam == null or _focus == null:
		return
	var w: Vector3 = WorldCoords.latlon_to_world(_lat, _lon)
	var gy: float = 0.0
	if _terrain != null and _terrain.has_method("get_height_at"):
		gy = float(_terrain.call("get_height_at", w))
	_focus.position = Vector3(w.x, gy, w.z)
	_cam.position = Vector3(w.x, gy + CAM_HEIGHT, w.z)
	var vh: float = float(_vp.size.y) if _vp != null and _vp.size.y > 0 else maxf(size.y, 1.0)
	_cam.size = metres_per_px * maxf(vh, 1.0)
	if _overlay != null:
		_overlay.queue_redraw()


# ================================================================== world <-> screen
## World position (XZ, y = 0) under a control-space pixel.
func world_at(px: Vector2) -> Vector3:
	var w: Vector3 = WorldCoords.latlon_to_world(_lat, _lon)
	return Vector3(w.x + (px.x - size.x * 0.5) * metres_per_px, 0.0,
		w.z + (px.y - size.y * 0.5) * metres_per_px)


## Vector2(lat, lon) under a control-space pixel.
func latlon_at(px: Vector2) -> Vector2:
	return WorldCoords.world_to_latlon(world_at(px))


## Control-space position of a lat/lon (the inverse of latlon_at()).
func screen_of(lat: float, lon: float) -> Vector2:
	var w: Vector3 = WorldCoords.latlon_to_world(lat, lon)
	var c: Vector3 = WorldCoords.latlon_to_world(_lat, _lon)
	return Vector2(size.x * 0.5 + (w.x - c.x) / metres_per_px, size.y * 0.5 + (w.z - c.z) / metres_per_px)


# ================================================================== input
func _gui_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var f: float = ZOOM_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP
				_zoom_at(mb.position, f)
				accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			_pan_press = mb.position
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_click_press = mb.position
			else:
				if _click_press.distance_to(mb.position) < 6.0:
					var ll: Vector2 = latlon_at(mb.position)
					clicked.emit(ll.x, ll.y, mb.shift_pressed)
				accept_event()
			return
		return
	if event is InputEventMouseMotion and _panning:
		var mm: InputEventMouseMotion = event
		_move_world(-mm.relative.x * metres_per_px, -mm.relative.y * metres_per_px, true)
		accept_event()


## Zoom by `factor` about a control-space point, keeping the ground under it in place.
func _zoom_at(at: Vector2, factor: float) -> void:
	var before: Vector3 = world_at(at)
	metres_per_px = clampf(metres_per_px * factor, MPP_MIN, MPP_MAX)
	var after: Vector3 = world_at(at)
	_move_world(before.x - after.x, before.z - after.z, true)


## Pan by a world-space XZ delta. `notify` is false for host-driven moves (no focus_moved).
func _move_world(dx: float, dz: float, notify: bool) -> void:
	var c: Vector3 = WorldCoords.latlon_to_world(_lat, _lon)
	var ll: Vector2 = WorldCoords.world_to_latlon(Vector3(c.x + dx, 0.0, c.z + dz))
	_lat = clampf(ll.x, WorldCoords.LAT_MIN, WorldCoords.LAT_MAX)
	_lon = clampf(ll.y, WorldCoords.LON_MIN, WorldCoords.LON_MAX)
	_apply_camera()
	if notify:
		focus_moved.emit(_lat, _lon)


# ================================================================== frame
func _process(delta: float) -> void:
	if not _open:
		return
	if _eager_on:
		_eager_t += delta
		# Keep the populator's eager budget while the visible rectangle is still filling: the close-up is
		# what the editor is waiting for, so it must not queue behind the tiles out at the 12.8 km edge.
		var done: bool = _eager_t >= _eager_need and is_settled()
		if (done or _eager_t >= EAGER_MAX) and _wp != null:
			_eager_on = false
			_wp.set("boost", false)      # back to the ordinary in-flight streaming budget
			print("[map3d] eager fill done after %.1f s (view tiles %d/%d)" % [
				_eager_t, _view_tile_count().x, _view_tile_count().y])
	_resize_viewport()
	if _vp != null and _cam != null and not is_equal_approx(_cam.size, metres_per_px * float(_vp.size.y)):
		_apply_camera()
	if _overlay != null and _overlay.visible != show_overlay:
		_overlay.visible = show_overlay
	if show_overlay and _overlay != null:
		_overlay_t -= delta
		if _overlay_t <= 0.0:
			_overlay_t = OVERLAY_REFRESH
			_overlay.queue_redraw()


# ================================================================== overlay (optional)
func _draw_overlay() -> void:
	if _overlay == null:
		return
	var w: float = _overlay.size.x
	var h: float = _overlay.size.y
	if w < 8.0 or h < 8.0:
		return
	var font: Font = ThemeDB.fallback_font
	var col := Color(1.0, 0.92, 0.25, 0.9)
	var c := Vector2(w * 0.5, h * 0.5)
	_overlay.draw_line(c - Vector2(16.0, 0.0), c + Vector2(16.0, 0.0), col, 2.0)
	_overlay.draw_line(c - Vector2(0.0, 16.0), c + Vector2(0.0, 16.0), col, 2.0)
	var bar_m: float = _nice_metres(150.0 * metres_per_px)
	var bar_px: float = bar_m / maxf(metres_per_px, 0.0001)
	var x0: float = 16.0
	var y0: float = h - 24.0
	var white := Color(1.0, 1.0, 1.0, 0.92)
	_overlay.draw_line(Vector2(x0, y0), Vector2(x0 + bar_px, y0), white, 3.0)
	_overlay.draw_line(Vector2(x0, y0 - 6.0), Vector2(x0, y0 + 6.0), white, 2.0)
	_overlay.draw_line(Vector2(x0 + bar_px, y0 - 6.0), Vector2(x0 + bar_px, y0 + 6.0), white, 2.0)
	_overlay.draw_string(font, Vector2(x0, y0 - 10.0), _metres_label(bar_m),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, white)
	var st: Dictionary = stats()
	var lines: Array = [
		"3D WORLD  lat %.5f  lon %.5f" % [float(st["lat"]), float(st["lon"])],
		"%.2f m/px   view %.2f x %.2f km" % [metres_per_px, w * metres_per_px / 1000.0, h * metres_per_px / 1000.0],
		"terrain chunks %d   scenery tiles %d   nodes %d" % [int(st["chunks"]), int(st["tiles"]), int(st["nodes"])],
		"view chunks %d/%d   view tiles %d/%d   %s" % [int(st["view_chunks_have"]), int(st["view_chunks"]),
			int(st["view_tiles_have"]), int(st["view_tiles"]),
			"ready" if bool(st["settled"]) else "streaming"],
	]
	var y: float = 22.0
	for ln in lines:
		_overlay.draw_string(font, Vector2(12.0, y), str(ln), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, white)
		y += 18.0


## 1 / 2 / 5 x 10^n just under `m`, so a scale bar is a round number of metres.
static func _nice_metres(m: float) -> float:
	if m <= 0.0:
		return 1.0
	var p: float = pow(10.0, floor(log(m) / log(10.0)))
	var best: float = p
	for k in [1.0, 2.0, 5.0, 10.0]:
		if p * float(k) <= m:
			best = p * float(k)
	return best


static func _metres_label(m: float) -> String:
	if m >= 1000.0:
		var km: float = m / 1000.0
		if is_equal_approx(km, round(km)):
			return "%d km" % int(round(km))
		return "%.1f km" % km
	return "%d m" % int(round(m))
