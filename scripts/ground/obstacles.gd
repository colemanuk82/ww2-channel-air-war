class_name Obstacles
extends RefCounted
## Solid scenery an aircraft can fly into: trees and woods, houses, churches, hangars, huts, pylons, parked
## aircraft, beach obstacles... There is no physics engine collision for the procedural world, so the places that
## build that scenery register their nodes here (Scatter.multi / multi_from_data, AirfieldProp, churches) and
## Aircraft asks `hit()` each frame while it is low. Each registered node is indexed lazily, only once an aircraft
## is low and near it: its instances become oriented footprints (centre, axis, half extents, base and top heights)
## in a fine grid, so the per-frame test only looks at the few objects under the aircraft.

const COARSE := 500.0        # metres per coarse cell (registered nodes)
const FINE := 30.0           # metres per fine cell (instances inside one node)
const MIN_H := 1.2           # lower than this (kerbs, strips, flat markings, rails) is never an obstacle
const MAX_TOP := 70.0        # nothing taller than this above the ground: no need to look when higher
const SHRINK := 0.85         # footprints a little inside the drawn outline (soft tree crowns, eaves)

static var _pending: Array = []          # nodes waiting to be indexed (not in the tree yet, or not looked at)
static var _cells: Dictionary = {}       # Vector2i -> Array of entries
static var _entries: Dictionary = {}     # node instance id -> entry
static var _next_resolve: int = 0


## Make a node's mesh instances solid. Safe to call before the node is in the tree.
static func register(n: Node3D) -> void:
	if n == null:
		return
	_pending.append(n)
	n.tree_exited.connect(Callable(Obstacles, "_on_exited").bind(n, n.get_instance_id()))


static func _on_exited(n: Node3D, id: int) -> void:
	# a tile that is unloaded (or moved) leaves the index; it is indexed again if it comes back
	var e: Variant = _entries.get(id)
	if e != null:
		_entries.erase(id)
		for key in (e as Dictionary)["keys"]:
			if _cells.has(key):
				(_cells[key] as Array).erase(e)
	if is_instance_valid(n) and not n.is_queued_for_deletion():
		_pending.append(n)


static func clear() -> void:
	_pending.clear()
	_cells.clear()
	_entries.clear()
	_next_resolve = 0


static func _resolve_pending() -> void:
	var now: int = Time.get_ticks_msec()
	if now < _next_resolve:
		return
	_next_resolve = now + 400
	var keep: Array = []
	for n in _pending:
		if not is_instance_valid(n):
			continue
		var node: Node3D = n
		if not node.is_inside_tree():
			keep.append(node)
			continue
		var b: AABB = _bounds(node)
		if b.size == Vector3.ZERO:
			continue
		if _entries.has(node.get_instance_id()):
			continue
		var e := {"n": node, "lo": Vector2(b.position.x, b.position.z), "hi": Vector2(b.end.x, b.end.z), "data": null, "grid": {}, "keys": []}
		_entries[node.get_instance_id()] = e
		for cx in range(int(floor(b.position.x / COARSE)), int(floor(b.end.x / COARSE)) + 1):
			for cz in range(int(floor(b.position.z / COARSE)), int(floor(b.end.z / COARSE)) + 1):
				var key := Vector2i(cx, cz)
				if not _cells.has(key):
					_cells[key] = []
				(_cells[key] as Array).append(e)
				(e["keys"] as Array).append(key)
	_pending = keep


static func _bounds(n: Node3D) -> AABB:
	if n is MultiMeshInstance3D:
		var mmi: MultiMeshInstance3D = n
		if mmi.multimesh == null or mmi.multimesh.instance_count == 0 or mmi.multimesh.mesh == null:
			return AABB()
		var a: AABB = mmi.custom_aabb if mmi.custom_aabb.size != Vector3.ZERO else mmi.multimesh.get_aabb()
		return mmi.global_transform * a
	if n is AirfieldProp:
		var ap: AirfieldProp = n
		if ap._mesh == null or ap._xf.is_empty():
			return AABB()
		var out := AABB()
		var first: bool = true
		for t in ap._xf:
			var w: AABB = ap.global_transform * (t as Transform3D) * ap._mesh.get_aabb()
			out = w if first else out.merge(w)
			first = false
		return out
	var out2 := AABB()
	var first2: bool = true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		if mi.mesh == null:
			continue
		var w2: AABB = mi.global_transform * mi.mesh.get_aabb()
		out2 = w2 if first2 else out2.merge(w2)
		first2 = false
	return out2


## Footprints of every object in a registered node: 8 doubles each (cx, cz, axis x, axis z, half x, half z, base, top).
static func _build(e: Dictionary) -> void:
	var n: Node3D = e["n"]
	var items: Array = []          # [Transform3D world, AABB local]
	if n is MultiMeshInstance3D:
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		var ab: AABB = mm.mesh.get_aabb()
		var g: Transform3D = n.global_transform
		for i in mm.instance_count:
			items.append([g * mm.get_instance_transform(i), ab])
	elif n is AirfieldProp:
		var ap: AirfieldProp = n
		for t in ap._xf:
			items.append([ap.global_transform * (t as Transform3D), ap._mesh.get_aabb()])
	else:
		for c in n.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = c
			if mi.mesh != null:
				items.append([mi.global_transform, mi.mesh.get_aabb()])
	var data := PackedFloat64Array()
	var grid: Dictionary = {}
	for it in items:
		var xf: Transform3D = it[0]
		var ab2: AABB = it[1]
		var wb: AABB = xf * ab2
		if wb.size.y < MIN_H:
			continue
		var c3: Vector3 = xf * ab2.get_center()
		var ax := Vector2(xf.basis.x.x, xf.basis.x.z)
		var az := Vector2(xf.basis.z.x, xf.basis.z.z)
		var hx: float = ab2.size.x * 0.5 * ax.length() * SHRINK
		var hz: float = ab2.size.z * 0.5 * az.length() * SHRINK
		if hx < 0.05 or hz < 0.05:
			continue
		var axn: Vector2 = ax.normalized() if ax.length() > 1e-6 else Vector2(1, 0)
		var k: int = data.size() / 8
		data.append_array([c3.x, c3.z, axn.x, axn.y, hx, hz, wb.position.y, wb.end.y])
		var rad: float = sqrt(hx * hx + hz * hz) + 8.0      # + the widest reach asked for, so no neighbour cell is needed
		for gx in range(int(floor((c3.x - rad) / FINE)), int(floor((c3.x + rad) / FINE)) + 1):
			for gz in range(int(floor((c3.z - rad) / FINE)), int(floor((c3.z + rad) / FINE)) + 1):
				var gk := Vector2i(gx, gz)
				if not grid.has(gk):
					grid[gk] = PackedInt32Array()
				var lst: PackedInt32Array = grid[gk]
				lst.append(k)
				grid[gk] = lst
	e["data"] = data
	e["grid"] = grid


## The first obstacle a body at `pos` touches: within `reach` metres sideways of its footprint and with the body's
## underside (`bottom`) below its top and its top (`top_y`) above its base. Returns {} when clear, else
## {"top": height of the obstacle, "node": the scenery node}.
static func hit(pos: Vector3, reach: float, bottom: float, top_y: float, include_parked: bool = true) -> Dictionary:
	_resolve_pending()
	var key := Vector2i(int(floor(pos.x / COARSE)), int(floor(pos.z / COARSE)))
	if not _cells.has(key):
		return {}
	var p2 := Vector2(pos.x, pos.z)
	for e in (_cells[key] as Array):
		var n: Variant = e["n"]
		if not is_instance_valid(n):
			continue
		var lo: Vector2 = e["lo"]
		var hi: Vector2 = e["hi"]
		if p2.x < lo.x - reach or p2.x > hi.x + reach or p2.y < lo.y - reach or p2.y > hi.y + reach:
			continue
		if n is AirfieldProp:
			var ap: AirfieldProp = n
			if ap.is_dead or (not include_parked and ap.pkind == "parked"):
				continue
		if e["data"] == null:
			_build(e)
		var data: PackedFloat64Array = e["data"]
		var grid: Dictionary = e["grid"]
		var gk := Vector2i(int(floor(pos.x / FINE)), int(floor(pos.z / FINE)))
		if not grid.has(gk):
			continue
		for k in (grid[gk] as PackedInt32Array):
			var o: int = k * 8
			if bottom > data[o + 7] or top_y < data[o + 6]:
				continue
			var dx: float = pos.x - data[o]
			var dz: float = pos.z - data[o + 1]
			var lx: float = dx * data[o + 2] + dz * data[o + 3]
			var lz: float = -dx * data[o + 3] + dz * data[o + 2]
			if absf(lx) < data[o + 4] + reach and absf(lz) < data[o + 5] + reach:
				return {"top": data[o + 7], "node": n}
	return {}
