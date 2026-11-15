extends RefCounted
## Undo / redo stack for the map editor. Every change goes through do(), which applies a command to
## the document and records it; undo() and redo() replay it backwards or forwards. Issuing a new
## command after an undo drops the redo branch, which is what every editor does.
##
## The "document" is the editor's working Array of MapEdits rows (Dictionaries), edited in place:
##
##   var doc: Array = []
##   var h := EditHistory.new()
##   h.do(doc, EditHistory.cmd_add({"op": "add", "id": "a1", "asset": "barn", "lat": 51.0, "lon": 1.0}))
##   h.undo(doc)        # doc is empty again
##   h.redo(doc)        # the row is back
##
## A group operation (moving a whole multi-selection, rotating it, deleting it or pasting
## several rows) is ONE command: cmd_group() holds the per-row commands, so it is one undo step.
##
## Commands are plain Dictionaries, so they are easy to build and to test.

const ADD: String = "add"          # place an edit row (an add or a remove circle)
const DELETE: String = "delete"    # delete an edit row
const MOVE: String = "move"        # move an edit to a new lat/lon
const ROTATE: String = "rotate"    # change an add's yaw
const RADIUS: String = "radius"    # change a remove circle's radius
const GROUP: String = "group"      # several commands applied together as a single undo step

const LIMIT: int = 500             # past this many steps the oldest is forgotten

var _undo: Array = []
var _redo: Array = []


static func cmd_add(row: Dictionary) -> Dictionary:
	return {"kind": ADD, "row": row.duplicate(true)}


static func cmd_delete(row: Dictionary) -> Dictionary:
	return {"kind": DELETE, "row": row.duplicate(true)}


static func cmd_move(id: String, from_lat: float, from_lon: float, to_lat: float, to_lon: float) -> Dictionary:
	return {"kind": MOVE, "id": id, "from_lat": from_lat, "from_lon": from_lon, "to_lat": to_lat, "to_lon": to_lon}


static func cmd_rotate(id: String, from_yaw: float, to_yaw: float) -> Dictionary:
	return {"kind": ROTATE, "id": id, "from_yaw": from_yaw, "to_yaw": to_yaw}


static func cmd_radius(id: String, from_r: float, to_r: float) -> Dictionary:
	return {"kind": RADIUS, "id": id, "from_r": from_r, "to_r": to_r}


## Several commands as one undo step: a group move, a group rotate, a group delete or a paste.
## `parts` are ordinary commands (the ones above, or another group); they are applied in order
## forwards and in reverse order backwards, and a part that cannot apply rolls the whole group
## back out so a failed group leaves the document as it was.
static func cmd_group(parts: Array) -> Dictionary:
	return {"kind": GROUP, "parts": parts.duplicate(true)}


## Apply `cmd` and record it. Returns false, changing nothing, when the command cannot apply.
func do(doc: Array, cmd: Dictionary) -> bool:
	if not _apply(doc, cmd, true):
		return false
	_push(cmd)
	return true


## Record a command that the caller has already applied to `doc` (a live drag, for example).
## This is what keeps a move or a resize a single undo step instead of one per mouse event.
func record(cmd: Dictionary) -> void:
	_push(cmd)


func undo(doc: Array) -> bool:
	if _undo.is_empty():
		return false
	var cmd: Dictionary = _undo.pop_back()
	_apply(doc, cmd, false)
	_redo.append(cmd)
	return true


func redo(doc: Array) -> bool:
	if _redo.is_empty():
		return false
	var cmd: Dictionary = _redo.pop_back()
	_apply(doc, cmd, true)
	_undo.append(cmd)
	return true


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo_depth() -> int:
	return _undo.size()


func redo_depth() -> int:
	return _redo.size()


func clear() -> void:
	_undo = []
	_redo = []


## True when `id` is present anywhere in `doc`.
static func has_id(doc: Array, id: String) -> bool:
	return not row_of(doc, id).is_empty()


## The row with this id, or {}.
static func row_of(doc: Array, id: String) -> Dictionary:
	for e in doc:
		if str((e as Dictionary).get("id", "")) == id:
			return e
	return {}


static func _erase(doc: Array, id: String) -> bool:
	for i in doc.size():
		if str((doc[i] as Dictionary).get("id", "")) == id:
			doc.remove_at(i)
			return true
	return false


static func _put(doc: Array, id: String, key: String, value: float) -> bool:
	var row: Dictionary = row_of(doc, id)
	if row.is_empty():
		return false
	row[key] = value
	return true


func _push(cmd: Dictionary) -> void:
	_undo.append(cmd)
	while _undo.size() > LIMIT:
		_undo.pop_front()
	_redo.clear()


func _apply(doc: Array, cmd: Dictionary, forward: bool) -> bool:
	var id: String = str(cmd.get("id", ""))
	match str(cmd.get("kind", "")):
		ADD:
			var row: Dictionary = cmd.get("row", {}) as Dictionary
			if forward:
				if has_id(doc, str(row.get("id", ""))):
					return false
				doc.append(row.duplicate(true))
				return true
			return _erase(doc, str(row.get("id", "")))
		DELETE:
			var back: Dictionary = cmd.get("row", {}) as Dictionary
			if forward:
				return _erase(doc, str(back.get("id", "")))
			if has_id(doc, str(back.get("id", ""))):
				return false
			doc.append(back.duplicate(true))
			return true
		MOVE:
			return _put(doc, id, "lat", float(cmd["to_lat"]) if forward else float(cmd["from_lat"])) \
				and _put(doc, id, "lon", float(cmd["to_lon"]) if forward else float(cmd["from_lon"]))
		ROTATE:
			return _put(doc, id, "yaw", float(cmd["to_yaw"]) if forward else float(cmd["from_yaw"]))
		RADIUS:
			return _put(doc, id, "radius", float(cmd["to_r"]) if forward else float(cmd["from_r"]))
		GROUP:
			var parts: Array = cmd.get("parts", []) as Array
			if parts.is_empty():
				return false
			if forward:
				for i in parts.size():
					if not _apply(doc, parts[i] as Dictionary, true):
						_roll_back(doc, parts, i, false)
						return false
				return true
			for i in range(parts.size() - 1, -1, -1):
				if not _apply(doc, parts[i] as Dictionary, false):
					_roll_back(doc, parts, i, true)
					return false
			return true
	return false


## Undo a group that failed half way, so it either applies whole or changes nothing. `upto` is the
## part that failed; `forward` says which way the group was being applied. Going forward, the parts
## before `upto` are already in the document and are taken back out newest first; going backwards
## (an undo), the parts after `upto` have already been undone and are put back oldest first.
func _roll_back(doc: Array, parts: Array, upto: int, forward: bool) -> void:
	if forward:
		for j in range(upto - 1, -1, -1):
			_apply(doc, parts[j] as Dictionary, false)
		return
	for j in range(upto + 1, parts.size()):
		_apply(doc, parts[j] as Dictionary, true)
