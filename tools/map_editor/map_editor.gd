extends Control
## Map Editor: a separate app (its own scene) over the game's real map and data, for hand-placing
## buildings and props and cutting removal circles. It reads and writes the game's own
## data/map_edits.json (MapEdits), so what is done here is what WorldPopulator and Scatter apply.
##
## Run it from the repo root:
##   godot --path . tools/map_editor/map_editor.tscn
## See README.md beside this file. It is never part of an exported game: export_presets.cfg
## excludes tools/.
##
## Every change to `edits` goes through the EditHistory stack, so undo / redo cover placing,
## deleting, moving, rotating, resizing, group operations and pastes; a whole group operation is a
## single step.
##
## The selection lives here, not in the view: `sel_ids` holds the selected edit ids in the order
## they were picked, and the last one is the primary (`sel_id`) whose yaw / radius the toolbar
## reads. EditSelection (edit_selection.gd) does the group maths, so it is unit tested.

const EditHistory := preload("res://tools/map_editor/edit_history.gd")
const EditSelection := preload("res://tools/map_editor/edit_selection.gd")
const MapBase := preload("res://tools/map_editor/map_base.gd")
const MapView := preload("res://tools/map_editor/map_view.gd")
const Map3D := preload("res://tools/map_editor/map_3d.gd")   # top-down 3D world window

const SAVE_PATH: String = "res://data/map_edits.json"
const AUTOSAVE_PATH: String = "user://map_edits_autosave.json"
const AUTOSAVE_SECS: float = 60.0
const BASE_WIDTH: int = 6144        # the imagery's own width, so the base map is drawn 1:1
const ROT_STEP: float = 15.0
const ROT_STEP_FINE: float = 1.0
const RADIUS_STEP: float = 5.0
const GOTO_ZOOM: float = 6.0        # the go-to box zooms in to at least this, if it is further out

const CATEGORIES: Array = [["building", "Buildings"], ["prop", "Props"]]

var edits: Array = []               # the working document: MapEdits row dictionaries
var history := EditHistory.new()
var tool: String = "select"         # select | place | remove
var place_asset: String = ""
var place_yaw: float = 0.0
## The selection, in the order the edits were picked; the last one is the primary.
var sel_ids: Array = []
## The primary selection (the last id picked), or "". Assigning one id replaces the selection,
## which keeps the Phase 2 single-selection calls working unchanged.
var sel_id: String:
	get:
		return "" if sel_ids.is_empty() else str(sel_ids[sel_ids.size() - 1])
	set(value):
		sel_ids = [] if str(value).is_empty() else [str(value)]
var dirty: bool = false
var grid_on: bool = true            # the map grid (G); a visual aid only, nothing snaps to it
var clipboard: Array = []           # copied `add` rows, waiting for Ctrl+V

var _view: MapView = null
var _base: MapBase = null
var _title: Label = null
var _status: Label = null
var _stats: Label = null
var _rot_label: Label = null
var _tool_buttons: Dictionary = {}
var _lists: Dictionary = {}
var _keys: Dictionary = {}
var _searches: Dictionary = {}
var _quit_confirm: ConfirmationDialog = null
var _autosave: Timer = null
var _drag_from: Vector2 = Vector2.ZERO       # the primary row's position when a drag started
var _drag_from_ll: Vector2 = Vector2.ZERO    # the mouse lat/lon when a drag started
var _drag_from_pos: Dictionary = {}          # id -> Vector2(lat, lon) at the start of a drag
var _goto: LineEdit = null
var _grid_button: Button = null
var _map3d_button: Button = null
var _map3d: Map3D = null             # the top-down 3D world window (map_3d.gd)
var _goto_matches: Array = []
var _goto_pos: int = -1
var _goto_needle: String = ""
var _shot_select: Array = []                 # --editor-select=a1,a2, for the self-test shots
var _remove_center: Vector2 = Vector2.ZERO
var _remove_have: bool = false

# --editor-shot: render a few real frames, save a picture and quit. This is how the drawing code is
# checked without a window on the developer's desktop; see README.md.
var _shot_path: String = ""
var _shot_frames: int = 0
var _shot_after: int = 90
var _shot_done: bool = false
var _shot_3d: bool = false          # --editor-3d: open the world window before the shot
var _shot_at: Vector2 = Vector2(-1.0, -1.0)   # the --editor-at lat/lon, for the 3D open


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	MapEdits.load()
	edits = MapEdits.all()
	history.clear()
	_build_ui()
	_build_base()
	_build_autosave()
	_tool_flags()
	_set_status("Editing %s" % MapEdits.last_path())
	_refresh()
	_parse_shot_args()


# ================================================================== ui
func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)
	_build_toolbar(root)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	root.add_child(body)
	_build_palette(body)
	_view = MapView.new()
	_view.ed = self
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_view)
	# The 3D world window replaces the 2D view in the same slot when it is open, so the layout does not
	# jump around. It is hidden until the first toggle.
	_map3d = Map3D.new()
	_map3d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map3d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map3d.visible = false
	_map3d.focus_moved.connect(_on_3d_focus_moved)
	_map3d.clicked.connect(_on_3d_clicked)
	body.add_child(_map3d)


func _build_toolbar(root: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	root.add_child(bar)
	_title = Label.new()
	_title.text = "MAP EDITOR"
	_title.custom_minimum_size = Vector2(116.0, 0.0)
	_title.clip_text = true
	bar.add_child(_title)
	for entry in [["Place", "place"], ["Select", "select"], ["Remove", "remove"]]:
		var b := Button.new()
		b.text = str(entry[0])
		b.toggle_mode = true
		var id: String = str(entry[1])
		b.pressed.connect(func() -> void: set_tool(id))
		bar.add_child(b)
		_tool_buttons[id] = b
	bar.add_child(VSeparator.new())
	bar.add_child(_button("Undo", undo))
	bar.add_child(_button("Redo", redo))
	bar.add_child(_button("Delete", delete_selection))
	bar.add_child(_button("Copy", func() -> void: copy_selection()))
	bar.add_child(_button("Paste", func() -> void: paste_clipboard()))
	bar.add_child(_button("Save", func() -> void: save_now()))
	bar.add_child(VSeparator.new())
	_grid_button = _button("Grid", toggle_grid)
	_grid_button.toggle_mode = true
	_grid_button.button_pressed = grid_on
	_grid_button.tooltip_text = "Map grid on / off (G)"
	bar.add_child(_grid_button)
	_map3d_button = _button("3D", toggle_3d)
	_map3d_button.toggle_mode = true
	_map3d_button.tooltip_text = "Top-down 3D view of the real streamed world at the map centre (V)"
	bar.add_child(_map3d_button)
	bar.add_child(VSeparator.new())
	_rot_label = Label.new()
	_rot_label.custom_minimum_size = Vector2(86.0, 0.0)
	bar.add_child(_rot_label)
	# The tool hint is drawn as a banner over the map itself, and the status, the go-to box and the
	# counts get their own line so nothing is squeezed out of the button row.
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	root.add_child(row2)
	_status = Label.new()
	_status.clip_text = true
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_status)
	_goto = LineEdit.new()
	_goto.placeholder_text = "go to city / airfield / edit"
	_goto.custom_minimum_size = Vector2(210.0, 0.0)
	_goto.clear_button_enabled = true
	_goto.tooltip_text = "Type part of a name or id and press Enter; Enter again cycles the matches."
	_goto.text_submitted.connect(func(txt: String) -> void: goto_go(txt))
	row2.add_child(_goto)
	_stats = Label.new()
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row2.add_child(_stats)
	_quit_confirm = ConfirmationDialog.new()
	_quit_confirm.title = "Unsaved changes"
	_quit_confirm.dialog_text = "You have unsaved map edits. Quit and lose them?"
	# Quitting while the 3D window is streaming leaves the game's worker threads with queued tiles, so
	# the world is torn down properly first (close() joins them).
	_quit_confirm.confirmed.connect(_quit_now)
	add_child(_quit_confirm)


func _quit_now() -> void:
	if _map3d != null and _map3d.is_open():
		_map3d.close()
	get_tree().quit()


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _build_palette(body: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300.0, 0.0)
	body.add_child(panel)
	var tabs := TabContainer.new()
	panel.add_child(tabs)
	for entry in CATEGORIES:
		var cat: String = str(entry[0])
		var box := VBoxContainer.new()
		box.name = str(entry[1])
		box.add_theme_constant_override("separation", 4)
		tabs.add_child(box)
		var search := LineEdit.new()
		search.placeholder_text = "search..."
		search.text_changed.connect(func(_t: String) -> void: _fill_list(cat))
		box.add_child(search)
		_searches[cat] = search
		var list := ItemList.new()
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.item_selected.connect(func(i: int) -> void: _palette_pick(cat, i))
		box.add_child(list)
		_lists[cat] = list
	_fill_list("building")
	_fill_list("prop")


func _palette_pick(cat: String, index: int) -> void:
	var keys: Array = _keys.get(cat, [])
	if index < 0 or index >= keys.size():
		return
	place_asset = str(keys[index])
	set_tool("place")


func _fill_list(cat: String) -> void:
	var list: ItemList = _lists.get(cat)
	if list == null:
		return
	var needle: String = str((_searches[cat] as LineEdit).text).strip_edges().to_lower()
	var entries: Array = []
	for k in MapAssets.keys():
		var key: String = str(k)
		if MapAssets.category(key) != cat:
			continue
		var label: String = MapAssets.label(key)
		if needle.is_empty() or label.to_lower().contains(needle) or key.contains(needle):
			entries.append([key, label])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return str(a[1]) < str(b[1]))
	var keys: Array = []
	list.clear()
	for e in entries:
		list.add_item(str(e[1]))
		keys.append(str(e[0]))
	_keys[cat] = keys
	if not place_asset.is_empty() and keys.has(place_asset):
		list.select(keys.find(place_asset))


func _build_base() -> void:
	_base = MapBase.new()
	_base.build(BASE_WIDTH)
	_view.base = _base
	_view.queue_redraw()


func _build_autosave() -> void:
	_autosave = Timer.new()
	_autosave.wait_time = AUTOSAVE_SECS
	_autosave.timeout.connect(_autosave_tick)
	add_child(_autosave)
	_autosave.start()


# ================================================================== tools
func set_tool(t: String) -> void:
	if t == "place" and place_asset.is_empty():
		return
	tool = t
	if t != "remove":
		_remove_have = false
	_tool_flags()
	_refresh()


func _tool_flags() -> void:
	for k in _tool_buttons:
		(_tool_buttons[k] as Button).button_pressed = str(k) == tool


func tool_hint() -> String:
	match tool:
		"place":
			if place_asset.is_empty():
				return "Pick an asset in the palette, then click the map to place it."
			return "Click to place %s.  Q/E rotate %d deg (shift: fine).  Shift+click keeps placing." % [
				MapAssets.label(place_asset), int(ROT_STEP)]
		"select":
			return "Click to select, Shift+click to add, drag empty ground to rubber-band; drag a selection to " \
				+ "move it all; Q/E rotate the group; [ ] radius; Del deletes; Ctrl+C/V copy; G grid."
		"remove":
			return "Press on the map and drag out a circle; release to cut houses, trees and hedges inside it."
	return ""


## A click on the map that was not a drag.
func map_click(lat: float, lon: float, shift: bool) -> void:
	if tool == "place":
		_place(lat, lon, shift)
	elif tool == "select":
		# Empty ground: a plain click clears the selection, a Shift+click keeps it.
		if not shift:
			clear_selection()


# ================================================================== selection
## Replace the selection with `ids` (ids with no row are dropped).
func set_selection(ids: Array) -> void:
	sel_ids = EditSelection.prune(edits, ids)
	_drag_from_pos = {}
	_refresh()


func clear_selection() -> void:
	set_selection([])


func is_selected(id: String) -> bool:
	return not id.is_empty() and sel_ids.has(id)


## Shift+click: add the edit to the selection, or drop it when it is already in.
func toggle_select(id: String) -> void:
	set_selection(EditSelection.toggle(sel_ids, id))


## The rubber band came out: select everything whose centre is inside `rect` (a screen rectangle).
func select_band(rect: Rect2) -> void:
	if _view == null:
		return
	set_selection(EditSelection.inside(edits, rect, _view.t))
	var n: int = sel_ids.size()
	_set_status("Rubber band: %d edit%s selected" % [n, "" if n == 1 else "s"])


func _snap(lat: float, lon: float) -> Vector2:
	return Vector2(snappedf(lat, 0.00001), snappedf(lon, 0.00001))


func _place(lat: float, lon: float, keep: bool) -> void:
	var ll: Vector2 = _snap(lat, lon)
	var row: Dictionary = {"op": "add", "id": MapEdits.next_id("a", edits), "asset": place_asset,
		"lat": ll.x, "lon": ll.y, "yaw": place_yaw, "scale": 1.0}
	if not history.do(edits, EditHistory.cmd_add(row)):
		return
	sel_id = str(row["id"])
	dirty = true
	if not keep:
		tool = "select"
		_remove_have = false
		_tool_flags()
	_refresh()


## Select exactly one edit (a plain click), or clear the selection with "".
func select_id(id: String) -> void:
	sel_id = id
	_drag_from_pos = {}
	var row: Dictionary = EditHistory.row_of(edits, id)
	if not row.is_empty():
		_drag_from = Vector2(float(row["lat"]), float(row["lon"]))
	_refresh()


## A drag started on the selection: remember where every selected row was, so the whole drag is one
## undo step (and so the rows keep their relative positions).
func begin_drag(latlon: Vector2) -> void:
	_drag_from_ll = _snap(latlon.x, latlon.y)
	_drag_from_pos = {}
	for row in EditSelection.rows_of(edits, sel_ids):
		_drag_from_pos[str(row["id"])] = Vector2(float(row["lat"]), float(row["lon"]))
	var row0: Dictionary = EditSelection.row_of(edits, sel_id)
	if not row0.is_empty():
		_drag_from = Vector2(float(row0["lat"]), float(row0["lon"]))


## Live drag: move every selected row by the same offset, in place. The offset is the snapped
## mouse delta, so the group's shape is untouched.
func drag_to(lat: float, lon: float) -> void:
	if _drag_from_pos.is_empty():
		return
	var ll: Vector2 = _snap(lat, lon)
	var d_lat: float = ll.x - _drag_from_ll.x
	var d_lon: float = ll.y - _drag_from_ll.y
	for k in _drag_from_pos:
		var row: Dictionary = EditHistory.row_of(edits, str(k))
		if row.is_empty():
			continue
		var from: Vector2 = _drag_from_pos[k]
		row["lat"] = from.x + d_lat
		row["lon"] = from.y + d_lon
	if _view != null:
		_view.queue_redraw()


## The drag ended: record the whole group move as one undo step.
func end_drag() -> void:
	var cmd: Dictionary = EditSelection.drag_cmd(edits, _drag_from_pos)
	_drag_from_pos = {}
	if cmd.is_empty():
		_refresh()
		return
	history.record(cmd)
	dirty = true
	_refresh()


## Live drag of one row by id (the Phase 2 entry point; the view now drags the selection).
func drag_edit(id: String, lat: float, lon: float) -> void:
	var row: Dictionary = EditHistory.row_of(edits, id)
	if row.is_empty():
		return
	var ll: Vector2 = _snap(lat, lon)
	row["lat"] = ll.x
	row["lon"] = ll.y
	_view.queue_redraw()


func end_move(id: String) -> void:
	var row: Dictionary = EditHistory.row_of(edits, id)
	if row.is_empty():
		return
	var to := Vector2(float(row["lat"]), float(row["lon"]))
	if to.is_equal_approx(_drag_from):
		return
	history.record(EditHistory.cmd_move(id, _drag_from.x, _drag_from.y, to.x, to.y))
	_drag_from = to
	dirty = true
	_refresh()


func remove_begin(latlon: Vector2) -> void:
	_remove_center = latlon
	_remove_have = true


func remove_drag(latlon: Vector2) -> void:
	if not _remove_have:
		_remove_center = latlon
		_remove_have = true
	_view.queue_redraw()


func commit_remove() -> void:
	if not _remove_have:
		return
	_remove_have = false
	var cur: Vector2 = _view.t.to_latlon(_view.mouse_pos())
	var metres: float = metres_between(_remove_center, cur)
	if metres < 5.0:
		_view.queue_redraw()
		return
	var c: Vector2 = _snap(_remove_center.x, _remove_center.y)
	var row: Dictionary = {"op": "remove", "id": MapEdits.next_id("r", edits), "lat": c.x, "lon": c.y,
		"radius": roundf(metres), "what": "all"}
	if history.do(edits, EditHistory.cmd_add(row)):
		sel_id = str(row["id"])
		dirty = true
	_refresh()


## Q / E: with nothing selected this turns the next placement; with a selection it rotates every
## selected `add` row about the selection's centre as ONE undo step. Remove circles never rotate.
func rotate_selection(delta: float) -> void:
	if sel_ids.is_empty():
		place_yaw = fposmod(place_yaw + delta, 360.0)
		_refresh()
		return
	rotate_group(delta)


## Rotate the whole selection about its centre; true when a step was recorded.
func rotate_group(delta: float) -> bool:
	var cmd: Dictionary = EditSelection.rotate_cmd(edits, sel_ids, delta)
	if cmd.is_empty():
		return false
	if not history.do(edits, cmd):
		return false
	dirty = true
	_refresh()
	_set_status("Rotated %d edit%s by %d deg about the selection centre" % [sel_ids.size(),
		"" if sel_ids.size() == 1 else "s", int(round(delta))])
	return true


## `[` / `]`: every selected remove circle changes radius, as one undo step.
func resize_selection(delta: float) -> void:
	var parts: Array = []
	for row in EditSelection.rows_of(edits, sel_ids):
		if str(row["op"]) != "remove":
			continue
		var from: float = float(row.get("radius", MapEdits.DEFAULT_RADIUS))
		parts.append(EditHistory.cmd_radius(str(row["id"]), from, maxf(from + delta, 5.0)))
	if parts.is_empty():
		return
	history.do(edits, EditHistory.cmd_group(parts))
	dirty = true
	_refresh()


## Delete every selected edit as ONE undo step.
func delete_selection() -> void:
	var cmd: Dictionary = EditSelection.delete_cmd(edits, sel_ids)
	if cmd.is_empty():
		return
	var n: int = sel_ids.size()
	if history.do(edits, cmd):
		clear_selection()
		dirty = true
		_refresh()
		_set_status("Deleted %d edit%s" % [n, "" if n == 1 else "s"])


# ================================================================== copy / paste
## Ctrl+C: copy the selected `add` rows (remove circles never copy). Returns how many were copied.
func copy_selection() -> int:
	clipboard = EditSelection.copy_rows(edits, sel_ids)
	var n: int = clipboard.size()
	if n == 0:
		_set_status("Nothing to copy: select a placed edit first (remove circles do not copy)")
	else:
		_set_status("Copied %d edit%s" % [n, "" if n == 1 else "s"])
	return n


## Ctrl+V: paste the clipboard as ONE undo step, with fresh ids. `at` is a lat/lon to centre the
## pasted group on; a negative latitude means "offset from where it was copied" (the mouse is used
## instead when it has been over the map). Returns the ids of the pasted rows.
func paste_clipboard(at: Vector2 = Vector2(-1.0, -1.0)) -> Array:
	if clipboard.is_empty():
		_set_status("Nothing to paste: copy a selection first (Ctrl+C)")
		return []
	var where: Vector2 = at
	if where.x < 0.0 and _view != null and _view.mouse_seen():
		where = _view.mouse_latlon()
	var cmd: Dictionary = EditSelection.paste_cmd(edits, clipboard, where)
	if cmd.is_empty():
		return []
	if not history.do(edits, cmd):
		return []
	var ids: Array = EditSelection.add_ids(cmd)
	set_selection(ids)
	dirty = true
	_refresh()
	_set_status("Pasted %d edit%s (%s)" % [ids.size(), "" if ids.size() == 1 else "s",
		", ".join(ids.slice(0, 4)) + ("..." if ids.size() > 4 else "")])
	return ids


# ================================================================== go to
## Every city, airfield and edit matching `needle`, best match first (see EditSelection).
func goto_find_matches(needle: String) -> Array:
	var cities: Array = []
	var airfields: Array = []
	if _base != null:
		cities = _base.cities
		airfields = _base.airfields
	return EditSelection.goto_matches(needle, cities, airfields, edits)


## The go-to box: Enter jumps to the first match and reports it; Enter again cycles the matches.
func goto_go(text: String) -> void:
	var needle: String = text.strip_edges()
	if needle.is_empty():
		_goto_matches = []
		_goto_pos = -1
		_goto_needle = ""
		_set_status("Go to: type part of a city, airfield, edit label or id, then Enter")
		return
	if needle != _goto_needle:
		_goto_needle = needle
		_goto_matches = goto_find_matches(needle)
		_goto_pos = -1
	if _goto_matches.is_empty():
		_set_status("Go to: nothing matches \"%s\"" % needle)
		return
	_goto_pos = (_goto_pos + 1) % _goto_matches.size()
	_goto_show(_goto_matches[_goto_pos])


## Jump to the next match for what is in the go-to box (the same as pressing Enter again).
func goto_next() -> void:
	if _goto == null:
		return
	goto_go(_goto.text)


func _goto_show(m: Dictionary) -> void:
	var ll := Vector2(float(m["lat"]), float(m["lon"]))
	if _view != null:
		_view.look_at_latlon(ll.x, ll.y, GOTO_ZOOM)
	# set_focus is editor-driven, so it does not bounce a focus_moved back at us.
	if _map3d != null and _map3d.is_open():
		_map3d.set_focus(ll.x, ll.y)
	if str(m["kind"]) == "edit" and not str(m["id"]).is_empty():
		sel_id = str(m["id"])
	_refresh()
	_set_status("Go to %d/%d:  %s   %.4f N  %.4f E" % [_goto_pos + 1, _goto_matches.size(),
		str(m["title"]), ll.x, ll.y])


# ================================================================== grid
## G / the Grid button: the map grid on or off. It is drawn by map_view and snaps nothing.
func toggle_grid() -> void:
	set_grid(not grid_on)


func set_grid(on: bool) -> void:
	grid_on = on
	if _grid_button != null:
		_grid_button.button_pressed = on
	if _view != null:
		_view.queue_redraw()
	_set_status("Grid %s" % ("on" if on else "off"))


# ================================================================== 3D world window
## The "3D" button / V: swap the 2D map for the top-down view of the real streamed world. Opening it
## centres on wherever the 2D map is looking, so the two views agree about where you are.
func toggle_3d() -> void:
	set_3d(not _map3d.is_open())


func set_3d(on: bool, focus: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if _map3d == null:
		return
	_map3d_button.button_pressed = on
	if on:
		# Default to wherever the 2D map is looking, so the two views agree; a caller may pass an exact
		# lat/lon instead (the self-test does, because at _ready the 2D view has no size yet).
		var c: Vector2 = focus
		if c.x < 0.0:
			c = _view.t.to_latlon(_view.size * 0.5)
		# 1.5 m of ground per pixel: close enough to read individual houses, which is the point.
		_map3d.open(_map3d.get_parent(), c.x, c.y, 1.5)
		_map3d.visible = true
		_view.visible = false
	else:
		_map3d.close()
		_map3d.visible = false
		_view.visible = true
	_refresh()


## The user panned or zoomed the 3D window: keep the 2D map (and so the next open) on the same spot.
func _on_3d_focus_moved(lat: float, lon: float) -> void:
	if _view != null and _view.visible:
		_view.look_at_latlon(lat, lon, 0.0)


## A plain click in the 3D window places the current palette asset there. Everything else (select,
## drag, remove circles) stays in the 2D view on purpose: this window exists to look at the world.
func _on_3d_clicked(lat: float, lon: float, shift: bool) -> void:
	if tool != "place" or place_asset.is_empty():
		return
	_place(lat, lon, shift)


func undo() -> void:
	if history.undo(edits):
		_clean_selection()
		dirty = true
		_refresh()


func redo() -> void:
	if history.redo(edits):
		_clean_selection()
		dirty = true
		_refresh()


## Drop selection ids that no longer have a row (after an undo, a redo or a delete).
func _clean_selection() -> void:
	sel_ids = EditSelection.prune(edits, sel_ids)
	_drag_from_pos = {}


# ================================================================== save
## Write the working set to data/map_edits.json. Returns true on success.
func save_now() -> bool:
	MapEdits.set_rows(edits)
	if not MapEdits.save(SAVE_PATH):
		_set_status("SAVE FAILED: %s" % SAVE_PATH)
		return false
	dirty = false
	_set_status("Saved %s at %s" % [SAVE_PATH, Time.get_time_string_from_system()])
	_refresh()
	return true


func _autosave_tick() -> void:
	MapEdits.set_rows(edits)
	if MapEdits.save(AUTOSAVE_PATH):
		_set_status("Autosaved to %s (Ctrl+S writes the real file)" % AUTOSAVE_PATH)


func _set_status(s: String) -> void:
	if _status == null:
		return
	_status.text = s
	if not _shot_path.is_empty():
		return
	# Save / autosave messages clear themselves; the self-test run keeps its line for the log.
	get_tree().create_timer(8.0).timeout.connect(func() -> void:
		if _status != null and _status.text == s:
			_status.text = "")


func _update_title() -> void:
	var mark: String = " *" if dirty else ""
	if _title != null:
		_title.text = "MAP EDITOR" + mark
	var win: Window = get_window()
	if win != null:
		win.title = "Map Editor" + mark


func _refresh() -> void:
	if _view != null:
		_view.queue_redraw()
	_update_title()
	var adds: int = 0
	var removes: int = 0
	for e in edits:
		if str((e as Dictionary).get("op", "")) == "add":
			adds += 1
		else:
			removes += 1
	if _stats != null:
		var sel: String = ""
		if sel_ids.size() == 1:
			sel = "  1 selected"
		elif sel_ids.size() > 1:
			sel = "  %d selected" % sel_ids.size()
		_stats.text = "%d placed  %d cuts%s  " % [adds, removes, sel]
	if _grid_button != null:
		_grid_button.button_pressed = grid_on
	if _rot_label != null:
		var row: Dictionary = EditHistory.row_of(edits, sel_id)
		if sel_ids.size() > 1:
			_rot_label.text = "%d sel" % sel_ids.size()
		elif row.is_empty():
			_rot_label.text = "yaw %d" % int(place_yaw)
		elif str(row["op"]) == "add":
			_rot_label.text = "yaw %d" % int(round(float(row.get("yaw", 0.0))))
		else:
			_rot_label.text = "radius %d m" % int(round(float(row.get("radius", 0.0))))


# ================================================================== helpers
func metres_between(a: Vector2, b: Vector2) -> float:
	var wa: Vector3 = WorldCoords.latlon_to_world(a.x, a.y)
	var wb: Vector3 = WorldCoords.latlon_to_world(b.x, b.y)
	return Vector2(wa.x, wa.z).distance_to(Vector2(wb.x, wb.z))


## Metres for a pixel distance on screen, for the remove-circle readout.
func pixels_to_metres(px: float) -> float:
	return px / maxf(_view.t.px_per_m(), 1.0e-9)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: InputEventKey = event
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		if k.keycode == KEY_ESCAPE:
			focus.release_focus()
			get_viewport().set_input_as_handled()
		return
	if k.ctrl_pressed and k.keycode == KEY_Z:
		undo()
	elif k.ctrl_pressed and k.keycode == KEY_Y:
		redo()
	elif k.ctrl_pressed and k.keycode == KEY_S:
		save_now()
	elif k.ctrl_pressed and k.keycode == KEY_C:
		copy_selection()
	elif k.ctrl_pressed and k.keycode == KEY_V:
		paste_clipboard()
	elif k.keycode == KEY_G:
		toggle_grid()
	elif k.keycode == KEY_V:
		toggle_3d()
	elif k.keycode == KEY_Q:
		rotate_selection(-ROT_STEP_FINE if k.shift_pressed else -ROT_STEP)
	elif k.keycode == KEY_E:
		rotate_selection(ROT_STEP_FINE if k.shift_pressed else ROT_STEP)
	elif k.keycode == KEY_BRACKETLEFT:
		resize_selection(-RADIUS_STEP)
	elif k.keycode == KEY_BRACKETRIGHT:
		resize_selection(RADIUS_STEP)
	elif k.keycode == KEY_DELETE:
		delete_selection()
	elif k.keycode == KEY_1:
		set_tool("select")
	elif k.keycode == KEY_2:
		set_tool("place")
	elif k.keycode == KEY_3:
		set_tool("remove")
	elif k.keycode == KEY_ESCAPE:
		if not sel_ids.is_empty():
			clear_selection()
		set_tool("select")
	else:
		return
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and dirty and not _quitting():
		get_tree().set_auto_accept_quit(false)
		_quit_confirm.popup_centered(Vector2i(440, 0))


func _quitting() -> bool:
	return _quit_confirm != null and _quit_confirm.visible


## --editor-shot=<path> [--editor-zoom=N] [--editor-frames=N]: draw real frames, save, quit.
func _parse_shot_args() -> void:
	var zoom: float = 1.0
	var about: Vector2 = Vector2(-1.0, -1.0)
	for a in OS.get_cmdline_user_args():
		var arg: String = str(a)
		if arg.begins_with("--editor-shot="):
			_shot_path = ProjectSettings.globalize_path(arg.substr("--editor-shot=".length()))
		elif arg.begins_with("--editor-zoom="):
			zoom = float(arg.substr("--editor-zoom=".length()))
		elif arg.begins_with("--editor-frames="):
			_shot_after = maxi(int(arg.substr("--editor-frames=".length())), 2)
		elif arg.begins_with("--editor-at="):
			var parts: PackedStringArray = arg.substr("--editor-at=".length()).split(",")
			if parts.size() == 2:
				about = Vector2(float(parts[0]), float(parts[1]))
		elif arg.begins_with("--editor-grid="):
			grid_on = arg.substr("--editor-grid=".length()).to_int() != 0
		elif arg.begins_with("--editor-select="):
			_shot_select = Array(arg.substr("--editor-select=".length()).split(",", false))
		elif arg == "--editor-3d":
			_shot_3d = true
	if _shot_path.is_empty():
		return
	if zoom > 0.0:
		_view.t.zoom = clampf(zoom, 1.0, 80.0)
		_view.invalidate()
	if about.x >= 0.0:
		_view.t.center = _view.t.uv(about.x, about.y)
		_view.t.clamp_center()
		_shot_at = about
	if not _shot_select.is_empty():
		sel_ids = EditSelection.prune(edits, _shot_select)
		_refresh()
	_set_status("SELF TEST: %d frames, then %s" % [_shot_after, _shot_path])


func _shot_tick() -> void:
	if _shot_path.is_empty() or _shot_done:
		return
	_shot_frames += 1
	if _shot_frames < _shot_after:
		return
	if _shot_frames == _shot_after:
		RenderingServer.frame_post_draw.connect(_on_shot_drawn, CONNECT_ONE_SHOT)
		_view.queue_redraw()
		return
	_shot_done = true
	# A headless run has a dummy renderer and no texture to grab, so there is nothing to save; the
	# picture is only wanted from the hidden-desktop runs.
	if DisplayServer.get_name() == "headless":
		print("EDITOR SHOT skipped (headless has no renderer): %s" % _shot_path)
		get_tree().quit()
		return
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		var err: Error = img.save_png(_shot_path)
		print("EDITOR SHOT %s (%dx%d) err=%d" % [_shot_path, img.get_width(), img.get_height(), err])
	get_tree().quit()


func _on_shot_drawn() -> void:
	_shot_tick()


func _process(_delta: float) -> void:
	if _shot_3d and _view != null and _view.size.x > 0.0:
		_shot_3d = false
		# The 2D view has no size at _ready, so its centre is meaningless; use the requested spot.
		set_3d(true, _shot_at)
	_shot_tick()
	if _view == null:
		return
	if _view.t.size != _view.size:
		_view.resize_to(_view.size)
