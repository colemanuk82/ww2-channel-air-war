extends RefCounted
## Selection and group-edit maths for the map editor: what a rubber band catches, Shift+click toggling,
## the one-undo-step command for a group move / rotate / delete / paste, and the go-to search matcher.
##
## Everything here is pure and headless-testable. The selection itself lives in the editor
## (map_editor.gd's `sel_ids`); each function takes it as an argument and returns a new Array, or a
## plain command Dictionary for EditHistory. The view passes its MapTransform in for the screen maths.
##
##   var ids: Array = EditSelection.inside(doc, Rect2(a, b), t)       # a rubber band
##   var cmd: Dictionary = EditSelection.rotate_cmd(doc, ids, 15.0)   # the whole group, one undo step
##   history.do(doc, cmd)

const EditHistory := preload("res://tools/map_editor/edit_history.gd")

## How far a plain Ctrl+V (with no mouse over the map) drops the paste from where it was copied, in
## degrees: about 440 m south and 430 m east, so the copy is visible and never sits on the original.
const PASTE_D_LAT: float = 0.004
const PASTE_D_LON: float = 0.006
## Pasted positions are snapped to this grid, the same one the editor snaps a place and a drag to,
## so the recorded command and the document always agree to the last digit.
const SNAP_DEG: float = 0.00001

## The go-to matcher's order: a whole-name match beats a prefix, which beats a substring.
const RANK_EXACT: int = 0
const RANK_PREFIX: int = 1
const RANK_PART: int = 2
## How the go-to matches are titled in the status line.
const KIND_TITLE: Dictionary = {"city": "City", "airfield": "Airfield", "edit": "Edit"}


# ================================================================== the selection set
## `ids` + `id`, or `ids` - `id` when it is already there. Adding puts the id last, so it becomes the
## primary selection (the one the yaw / radius readout shows).
static func toggle(ids: Array, id: String) -> Array:
	var out: Array = []
	for v in ids:
		var s: String = str(v)
		if s.is_empty() or s == id or out.has(s):
			continue
		out.append(s)
	if not ids.has(id):
		out.append(id)
	return out


## The ids that still have a row in `doc`, in the order given, with duplicates dropped. This is what
## cleans a selection up after an undo, a redo or a delete.
static func prune(doc: Array, ids: Array) -> Array:
	var out: Array = []
	for v in ids:
		var s: String = str(v)
		if s.is_empty() or out.has(s):
			continue
		if row_of(doc, s).is_empty():
			continue
		out.append(s)
	return out


## The rows for `ids`, in that order. The rows themselves, not copies.
static func rows_of(doc: Array, ids: Array) -> Array:
	var out: Array = []
	for v in ids:
		var row: Dictionary = row_of(doc, str(v))
		if not row.is_empty():
			out.append(row)
	return out


## The row with this id, or {}.
static func row_of(doc: Array, id: String) -> Dictionary:
	if id.is_empty():
		return {}
	for e in doc:
		var row: Dictionary = e
		if str(row.get("id", "")) == id:
			return row
	return {}


## Every edit whose centre lies inside the screen rectangle `rect`, in document order. This is the
## rubber band: a remove circle is picked up by its centre point, like an icon is by its dot.
static func inside(doc: Array, rect: Rect2, t) -> Array:
	var out: Array = []
	var r: Rect2 = rect.abs()
	if r.size.x < 2.0 and r.size.y < 2.0:
		return out
	for e in doc:
		var row: Dictionary = e
		var p: Vector2 = t.to_screen(float(row.get("lat", 0.0)), float(row.get("lon", 0.0)))
		if r.has_point(p):
			out.append(str(row.get("id", "")))
	return out


# ================================================================== group commands
## Several commands as a single undo step ({} when there is nothing to do).
static func group_cmd(parts: Array) -> Dictionary:
	if parts.is_empty():
		return {}
	return EditHistory.cmd_group(parts)


## One step that moves every selected row by the same lat/lon offset.
static func move_cmd(doc: Array, ids: Array, d_lat: float, d_lon: float) -> Dictionary:
	var parts: Array = []
	for v in ids:
		var row: Dictionary = row_of(doc, str(v))
		if row.is_empty():
			continue
		var flat: float = float(row.get("lat", 0.0))
		var flon: float = float(row.get("lon", 0.0))
		parts.append(EditHistory.cmd_move(str(row["id"]), flat, flon, flat + d_lat, flon + d_lon))
	return group_cmd(parts)


## The step that puts a finished live drag where it ended, from the positions captured when the drag
## started (`from_pos`: id -> Vector2(lat, lon)). Rows that did not move are left out.
static func drag_cmd(doc: Array, from_pos: Dictionary) -> Dictionary:
	var parts: Array = []
	for k in from_pos:
		var id: String = str(k)
		var row: Dictionary = row_of(doc, id)
		if row.is_empty():
			continue
		var from: Vector2 = from_pos[k]
		var to := Vector2(float(row.get("lat", 0.0)), float(row.get("lon", 0.0)))
		if to.is_equal_approx(from):
			continue
		parts.append(EditHistory.cmd_move(id, from.x, from.y, to.x, to.y))
	return group_cmd(parts)


## One step that rotates every selected `add` row about the selection's centre: the rows orbit the
## centre and their yaw turns by the same angle, clockwise for a positive `delta_deg` (so it matches
## what Q / E do to one row). Remove circles are never rotated, not even moved.
static func rotate_cmd(doc: Array, ids: Array, delta_deg: float) -> Dictionary:
	var adds: Array = []
	for v in ids:
		var row: Dictionary = row_of(doc, str(v))
		if row.is_empty() or str(row.get("op", "")) != "add":
			continue
		adds.append(row)
	if adds.is_empty():
		return {}
	var c: Vector2 = centre_of(adds)
	var cw: Vector3 = WorldCoords.latlon_to_world(c.x, c.y)
	var a: float = deg_to_rad(delta_deg)
	var ca: float = cos(a)
	var sa: float = sin(a)
	var parts: Array = []
	for e in adds:
		var row: Dictionary = e
		var id: String = str(row["id"])
		var lat: float = float(row.get("lat", 0.0))
		var lon: float = float(row.get("lon", 0.0))
		var w: Vector3 = WorldCoords.latlon_to_world(lat, lon)
		# Compass maths in the XZ plane: +x is east, -z is north, and clockwise is a positive angle.
		var dx: float = w.x - cw.x
		var dn: float = -(w.z - cw.z)
		var ex: float = dx * ca + dn * sa
		var nn: float = -dx * sa + dn * ca
		var ll: Vector2 = WorldCoords.world_to_latlon(Vector3(cw.x + ex, 0.0, cw.z - nn))
		if Vector2(lat, lon).distance_to(ll) > 1.0e-9:
			parts.append(EditHistory.cmd_move(id, lat, lon, ll.x, ll.y))
		var from_yaw: float = float(row.get("yaw", 0.0))
		parts.append(EditHistory.cmd_rotate(id, from_yaw, fposmod(from_yaw + delta_deg, 360.0)))
	return group_cmd(parts)


## One step that deletes every selected row, remove circles included.
static func delete_cmd(doc: Array, ids: Array) -> Dictionary:
	var parts: Array = []
	for v in ids:
		var row: Dictionary = row_of(doc, str(v))
		if row.is_empty():
			continue
		parts.append(EditHistory.cmd_delete(row))
	return group_cmd(parts)


## The centre of some rows (a selection or a clipboard) as Vector2(lat, lon), averaged in world
## metres. When any of the rows is an `add` only `add` rows count, so a remove circle beside them
## never drags the centre off the group that rotates. Vector2(-1, -1) when there is no row.
static func centre_of(rows: Array) -> Vector2:
	var any_add: bool = false
	for e in rows:
		if str((e as Dictionary).get("op", "")) == "add":
			any_add = true
			break
	var sum := Vector3.ZERO
	var n: int = 0
	for e in rows:
		var row: Dictionary = e
		if any_add and str(row.get("op", "")) != "add":
			continue
		var w: Vector3 = WorldCoords.latlon_to_world(float(row.get("lat", 0.0)), float(row.get("lon", 0.0)))
		sum.x += w.x
		sum.z += w.z
		n += 1
	if n == 0:
		return Vector2(-1.0, -1.0)
	return WorldCoords.world_to_latlon(Vector3(sum.x / float(n), 0.0, sum.z / float(n)))


## The selection's centre, for the group rotate.
static func centre(doc: Array, ids: Array) -> Vector2:
	return centre_of(rows_of(doc, ids))


# ================================================================== copy / paste
## The `add` rows among `ids`, deep-copied, in document order. Remove circles never copy.
static func copy_rows(doc: Array, ids: Array) -> Array:
	var out: Array = []
	for e in doc:
		var row: Dictionary = e
		if not ids.has(str(row.get("id", ""))) or str(row.get("op", "")) != "add":
			continue
		out.append(row.duplicate(true))
	return out


## Paste `clip` (rows taken with copy_rows) as one undo step. `at` is a lat/lon to centre the pasted
## group on (the editor passes the mouse); a negative latitude means "offset from where it was
## copied" (PASTE_D_LAT / PASTE_D_LON). Every pasted row gets a fresh id from MapEdits.next_id, taken
## against the document plus what this paste has already used, so a paste never collides.
static func paste_cmd(doc: Array, clip: Array, at: Vector2 = Vector2(-1.0, -1.0)) -> Dictionary:
	if clip.is_empty():
		return {}
	var shift := Vector2(PASTE_D_LAT, PASTE_D_LON)
	if at.x >= 0.0:
		shift = at - centre_of(clip)
	var known: Array = doc.duplicate()
	var parts: Array = []
	for e in clip:
		var src: Dictionary = e
		var row: Dictionary = src.duplicate(true)
		row["id"] = MapEdits.next_id("a", known)
		row["lat"] = snappedf(float(src.get("lat", 0.0)) + shift.x, SNAP_DEG)
		row["lon"] = snappedf(float(src.get("lon", 0.0)) + shift.y, SNAP_DEG)
		known.append(row)
		parts.append(EditHistory.cmd_add(row))
	return group_cmd(parts)


## The ids an all-ADD group command (a paste) created, in order.
static func add_ids(cmd: Dictionary) -> Array:
	var out: Array = []
	for e in cmd.get("parts", []):
		var part: Dictionary = e
		if str(part.get("kind", "")) != EditHistory.ADD:
			continue
		var row: Dictionary = part.get("row", {}) as Dictionary
		out.append(str(row.get("id", "")))
	return out


# ================================================================== go to
## Every city, airfield and edit whose name, label or id contains `needle` (case-insensitive), best
## match first: a whole-name match, then a prefix, then anywhere in the name. Ties keep the order
## cities, airfields, edits, which is the order they are offered in. Each match is
## {kind, title, name, id, lat, lon, rank}.
static func goto_matches(needle: String, cities: Array, airfields: Array, doc: Array) -> Array:
	var n: String = needle.strip_edges().to_lower()
	var out: Array = []
	if n.is_empty():
		return out
	for c in cities:
		var row: Dictionary = c
		_note(out, n, "city", str(row.get("name", "")), "", float(row.get("lat", 0.0)), float(row.get("lon", 0.0)))
	for a in airfields:
		var row: Dictionary = a
		_note(out, n, "airfield", str(row.get("name", "")), "", float(row.get("lat", 0.0)), float(row.get("lon", 0.0)))
	for e in doc:
		var row: Dictionary = e
		var id: String = str(row.get("id", ""))
		var what: String = MapAssets.label(str(row.get("asset", ""))) if str(row.get("op", "")) == "add" else "removal"
		_note(out, n, "edit", what, id, float(row.get("lat", 0.0)), float(row.get("lon", 0.0)))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["rank"]) != int(b["rank"]):
			return int(a["rank"]) < int(b["rank"])
		return int(a["order"]) < int(b["order"]))
	return out


## Rank one candidate and append it to `out` when it matches. A name and an id are both searched, and
## the better of the two ranks wins, so "a2" finds an edit by its id and "barn" by its label.
static func _note(out: Array, needle: String, kind: String, name: String, id: String, lat: float, lon: float) -> void:
	var rank: int = _rank(name, needle)
	var id_rank: int = _rank(id, needle)
	if id_rank >= 0 and (rank < 0 or id_rank < rank):
		rank = id_rank
	if rank < 0:
		return
	var display: String = name if id.is_empty() else "%s %s" % [name, id]
	out.append({"kind": kind, "title": "%s %s" % [str(KIND_TITLE.get(kind, kind)), display],
		"name": display, "id": id, "lat": lat, "lon": lon, "rank": rank, "order": out.size()})


## 0 for a whole-name match, 1 for a prefix, 2 for anywhere in the name, -1 for no match.
static func _rank(text: String, needle: String) -> int:
	var s: String = text.to_lower().strip_edges()
	if s.is_empty() or needle.is_empty():
		return -1
	if s == needle:
		return RANK_EXACT
	if s.begins_with(needle):
		return RANK_PREFIX
	if s.contains(needle):
		return RANK_PART
	return -1
