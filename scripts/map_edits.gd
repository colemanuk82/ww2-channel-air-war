class_name MapEdits
extends RefCounted
## Hand-made map edits (res://data/map_edits.json, version 1) applied on top of the procedural world.
## The map-editor app (built separately) reuses save(). Format:
##   {"version":1,"edits":[
##     {"op":"add","id":"a1","asset":"<asset key>","lat":51.2,"lon":0.5,"yaw":90.0,"scale":1.0},
##     {"op":"remove","id":"r1","lat":49.18,"lon":-0.36,"radius":25.0,"what":"all"}]}
## "move" / "replace" are just a remove plus an add, so there are no extra ops. Positions are lat/lon
## (WorldCoords.latlon_to_world); an added object's height is taken from the terrain when it is spawned.
## yaw is degrees; scale defaults to 1. Bad rows are skipped with a warning - a broken file never crashes.

const PATH: String = "res://data/map_edits.json"
const VERSION: int = 1
const OPS: Array = ["add", "remove"]
const WHICH: Array = ["all", "houses", "trees", "hedges", "sites"]
const DEFAULT_RADIUS: float = 25.0

static var _edits: Array = []      # validated rows, in file order
static var _removes: Array = []    # [{pos: Vector3, r2: float, what: String}] precomputed for is_removed


## (Re)load the edits from `path` (PATH when omitted). A missing or malformed file simply leaves no edits.
static func load(path: String = "") -> void:
	if path.is_empty():
		path = PATH
	_edits = []
	_removes = []
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f = null
	var d: Variant = JSON.parse_string(txt)
	if not (d is Dictionary):
		push_warning("MapEdits: %s is not a JSON object" % path)
		return
	var rows: Variant = (d as Dictionary).get("edits", [])
	if not (rows is Array):
		push_warning("MapEdits: %s has no edits array" % path)
		return
	for row in (rows as Array):
		var e: Dictionary = _validate(row)
		if e.is_empty():
			continue
		_edits.append(e)
		if str(e["op"]) == "remove":
			var c: Vector3 = WorldCoords.latlon_to_world(float(e["lat"]), float(e["lon"]))
			var r: float = float(e["radius"])
			_removes.append({"pos": c, "r2": r * r, "what": str(e["what"])})

## A finite float for a JSON number, or null (used by the validators below).
static func _num(v: Variant) -> Variant:
	if v is float or v is int:
		var x: float = float(v)
		if is_finite(x):
			return x
	return null


## Normalise one row, or return {} (after a warning) when it is not a usable edit.
static func _validate(row: Variant) -> Dictionary:
	if not (row is Dictionary):
		push_warning("MapEdits: skipping a row that is not an object")
		return {}
	var d: Dictionary = row
	var op: String = str(d.get("op", ""))
	if not OPS.has(op):
		push_warning("MapEdits: skipping row with unknown op '%s'" % op)
		return {}
	var id: String = str(d.get("id", ""))
	if id.is_empty():
		push_warning("MapEdits: skipping a %s row with no id" % op)
		return {}
	var lat: Variant = _num(d.get("lat"))
	var lon: Variant = _num(d.get("lon"))
	if lat == null or lon == null:
		push_warning("MapEdits: skipping '%s' with a missing or non-numeric position" % id)
		return {}
	if op == "add":
		var asset: String = str(d.get("asset", ""))
		if asset.is_empty():
			push_warning("MapEdits: skipping add '%s' with no asset" % id)
			return {}
		var yaw: Variant = _num(d.get("yaw"))
		var scale: Variant = _num(d.get("scale"))
		var sc: float = float(scale) if scale != null else 1.0
		if sc <= 0.0:
			push_warning("MapEdits: skipping add '%s' with scale <= 0" % id)
			return {}
		return {"op": "add", "id": id, "asset": asset, "lat": lat, "lon": lon, "yaw": (float(yaw) if yaw != null else 0.0), "scale": sc}
	var what: String = str(d.get("what", "all"))
	if not WHICH.has(what):
		push_warning("MapEdits: skipping remove '%s' with unknown what '%s'" % [id, what])
		return {}
	var radius: Variant = _num(d.get("radius"))
	var r: float = float(radius) if radius != null else DEFAULT_RADIUS
	if r <= 0.0:
		push_warning("MapEdits: skipping remove '%s' with radius <= 0" % id)
		return {}
	return {"op": "remove", "id": id, "lat": lat, "lon": lon, "radius": r, "what": what}

## The valid `add` rows, in file order (copies, so callers cannot mutate the loaded set).
static func adds() -> Array:
	var out: Array = []
	for e in _edits:
		if str((e as Dictionary)["op"]) == "add":
			out.append((e as Dictionary).duplicate())
	return out


## The valid `remove` rows, in file order (copies).
static func removes() -> Array:
	var out: Array = []
	for e in _edits:
		if str((e as Dictionary)["op"]) == "remove":
			out.append((e as Dictionary).duplicate())
	return out


static func has_edits() -> bool:
	return not _edits.is_empty()


static func has_removes() -> bool:
	return not _removes.is_empty()


## True when `pos` (world XZ) lies inside a remove circle that applies to `what`. A remove with what "all"
## applies to everything; an empty `what` matches any remove. Used by the tile scatters (houses / trees /
## hedges) and world populator keep-outs. Pure and read-only: safe on a worker thread once loaded.
static func is_removed(pos: Vector3, what: String = "") -> bool:
	if _removes.is_empty():
		return false
	var w: String = what if not what.is_empty() else "all"
	for e in _removes:
		var rw: String = str((e as Dictionary)["what"])
		if rw != "all" and rw != w:
			continue
		var c: Vector3 = (e as Dictionary)["pos"]
		var dx: float = pos.x - c.x
		var dz: float = pos.z - c.z
		if dx * dx + dz * dz <= float((e as Dictionary)["r2"]):
			return true
	return false

## Write the loaded edits back as stable, sorted, pretty JSON (so the editor and the game agree byte for byte).
static func save(path: String = "") -> bool:
	if path.is_empty():
		path = PATH
	var rows: Array = []
	for e in _edits:
		rows.append(_sorted_row(e as Dictionary))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _row_key(a) < _row_key(b))
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("MapEdits: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify({"version": VERSION, "edits": rows}, "\t"))
	f = null
	return true


static func _row_key(e: Dictionary) -> String:
	return "%s|%s" % [str(e.get("op", "")), str(e.get("id", ""))]


## The row with its keys in sorted order, so the written file is stable.
static func _sorted_row(e: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var ks: Array = e.keys()
	ks.sort()
	for k in ks:
		out[k] = e[k]
	return out