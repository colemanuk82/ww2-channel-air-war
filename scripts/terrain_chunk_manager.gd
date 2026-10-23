class_name TerrainChunkManager
extends Node3D
## Chunked, LOD-streamed toon terrain.
## Heights come from HeightField (heightmap file per DATA CONTRACT, or procedural fallback).
## Chunks are built on worker threads and streamed around `focus`.
## Public API: get_height_at(pos), get_terrain_y(x,z), is_water_at(pos), add_flat_zone(...),
##             set_focus(node), field (HeightField), signal initial_chunks_ready.
## Extending to the full map: it already covers the whole playable bounds; just raise lod_distances.

signal initial_chunks_ready

@export var chunk_size: float = 2000.0
# The last ring must reach the camera far plane (see camera_rig.gd) so the terrain edge is never visible.
@export var lod_resolutions: Array[int] = [64, 32, 16, 8, 4]
@export var lod_distances: Array[float] = [4200.0, 8000.0, 14000.0, 24000.0, 48000.0]
@export var max_inflight: int = 6
@export var max_instantiate_per_frame: int = 4
@export var shadows_on_terrain: bool = false

var field: HeightField
var focus: Node3D
var material: ShaderMaterial

var _chunks: Dictionary = {}    # Vector2i -> {"node": MeshInstance3D, "lod": int}
var _pending: Dictionary = {}   # Vector2i -> lod being built
var _results: Array = []
var _mutex := Mutex.new()
var _inflight: int = 0
var _timer: float = 0.0
var _bounds: Rect2
var _initial_done: bool = false
var _task_ids: Array = []
var _generation: int = 0        # bumps on rebuild so stale results are dropped
var _base_lod: Array = []

# Kept for the whole session: a replay / next mission reuses the imagery and urban-mask textures instead of decoding
# and uploading them again (about 75 MB of video memory stays resident).
static var _imagery_tex: Texture2D
static var _urban_tex: Texture2D
static var _sea_tex: Texture2D


func _ready() -> void:
	add_to_group("terrain")
	field = HeightField.new()
	field.setup()
	GroundKit.lp("  HeightField.setup")
	_bounds = WorldCoords.world_bounds().grow(chunk_size)
	_make_material()
	_timer = 0.0


func _make_material() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader") as Shader
	var zones: Array = field.get_cliff_world_zones()
	var names: Array = ["chalk_a", "chalk_b", "chalk_c", "chalk_d", "chalk_e"]
	for i in names.size():
		if i < zones.size():
			var z: Vector3 = zones[i]
			material.set_shader_parameter(names[i], Vector4(z.x, z.y, z.z, 0.0))
		else:
			material.set_shader_parameter(names[i], Vector4(0, 0, 0, 0))
	_apply_imagery()


## Ground tint zones (airfield grass, army-camp mud, POW-compound sand). zones: Array of {"pos": Vector3,
## "heading": float (deg), optional "half": Vector2 half-extents, "feather": float, "kind": 1/2/3}. The shader has 24
## slots, so all zones are kept here and the 24 nearest the focus are uploaded (refreshed as the player flies).
var _zones_all: Array = []
var _zone_at: Vector3 = Vector3(INF, 0, INF)


func set_airfield_zones(zones: Array) -> void:
	_zones_all = _zones_all.filter(func(z): return int(z.get("kind", 1)) != 1)
	_zones_all.append_array(zones)
	_upload_zones(true)


## Extra non-airfield zones (camps); appended to the airfield ones.
func add_ground_zones(zones: Array) -> void:
	_zones_all.append_array(zones)
	_upload_zones(true)


func _upload_zones(force: bool = false) -> void:
	if material == null:
		return
	var fp: Vector3 = focus.global_position if focus else Vector3.ZERO
	fp.y = 0.0
	if not force and fp.distance_to(_zone_at) < 3000.0:
		return
	_zone_at = fp
	var order: Array = _zones_all.duplicate()
	if order.size() > 24:
		order.sort_custom(func(p, q): return (p["pos"] as Vector3).distance_squared_to(fp) < (q["pos"] as Vector3).distance_squared_to(fp))
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	for i in 24:
		if i < order.size():
			var z: Dictionary = order[i]
			var p: Vector3 = z["pos"]
			var dir: Vector3 = WorldCoords.heading_to_dir(float(z.get("heading", 0.0)))
			a.append(Vector4(p.x, p.z, dir.x, dir.z))
			# airfields: 650x700 m half-extents with a 330 m feather, so the edge fades into the surrounding
			# fields rather than ending on a line the player can see from the air
			var half: Vector2 = z.get("half", Vector2(650.0, 700.0))
			b.append(Vector4(half.x, half.y, float(z.get("feather", 330.0)), float(z.get("kind", 1))))
		else:
			a.append(Vector4(0, 0, 1, 0))
			b.append(Vector4(0, 0, 1, 0))
	material.set_shader_parameter("af_a", a)
	material.set_shader_parameter("af_b", b)


## Drape the real imagery mosaic (data/heightmap/region_color.png) if it has been generated.
func _apply_imagery() -> void:
	var color_path: String = "res://data/heightmap/region_color.png"
	if not ResourceLoader.exists(color_path):
		material.set_shader_parameter("use_map", false)
		return
	var b: Rect2 = WorldCoords.world_bounds()
	if _imagery_tex == null:
		_imagery_tex = load(color_path) as Texture2D
	material.set_shader_parameter("map_tex", _imagery_tex)
	GroundKit.lp("  imagery texture")
	material.set_shader_parameter("map_rect", Vector4(b.position.x, b.position.y, 1.0 / b.size.x, 1.0 / b.size.y))
	material.set_shader_parameter("use_map", true)
	# towns: paved ground instead of the field patchwork where the real land cover is built-up
	if _urban_tex == null:
		if ResourceLoader.exists("res://data/heightmap/region_urban.png"):      # precomputed by tools/make_urban_mask.py
			_urban_tex = load("res://data/heightmap/region_urban.png") as Texture2D
		else:
			var um: Image = LandCover.urban_mask()
			if um != null:
				_urban_tex = ImageTexture.create_from_image(um)
	_apply_sea(b)
	GroundKit.lp("  urban mask")
	if _urban_tex != null:
		material.set_shader_parameter("urban_tex", _urban_tex)
		material.set_shader_parameter("use_urban", true)


## Sea-distance texture over the imagery rect, so the sand strip can be kept to the coast (see terrain.gdshader).
func _apply_sea(b: Rect2) -> void:
	if not field.use_coast_mask:
		return
	if _sea_tex == null:
		_sea_tex = ImageTexture.create_from_image(_sea_distance_image(b))
	material.set_shader_parameter("sea_tex", _sea_tex)
	material.set_shader_parameter("use_sea", true)


## Two-pass chamfer distance from every land cell to the nearest sea cell, on a 1536 x 768 grid over b.
## Written as R8: value = metres / 3000 (clamped). Built once per run.
func _sea_distance_image(b: Rect2) -> Image:
	var w: int = 1536
	var h: int = 768
	var sx: float = b.size.x / float(w)
	var sz: float = b.size.y / float(h)
	var big: float = 1.0e9
	var d := PackedFloat32Array()
	d.resize(w * h)
	for j in h:
		var wz: float = b.position.y + (float(j) + 0.5) * sz
		for i in w:
			var wx: float = b.position.x + (float(i) + 0.5) * sx
			d[j * w + i] = 0.0 if field.coast_land_w(wx, wz) < 0.5 else big
	var dg: float = sqrt(sx * sx + sz * sz)
	for j in h:
		for i in w:
			var idx: int = j * w + i
			var v: float = d[idx]
			if i > 0:
				v = minf(v, d[idx - 1] + sx)
			if j > 0:
				v = minf(v, d[idx - w] + sz)
				if i > 0:
					v = minf(v, d[idx - w - 1] + dg)
				if i < w - 1:
					v = minf(v, d[idx - w + 1] + dg)
			d[idx] = v
	for j in range(h - 1, -1, -1):
		for i in range(w - 1, -1, -1):
			var idx2: int = j * w + i
			var v2: float = d[idx2]
			if i < w - 1:
				v2 = minf(v2, d[idx2 + 1] + sx)
			if j < h - 1:
				v2 = minf(v2, d[idx2 + w] + sz)
				if i < w - 1:
					v2 = minf(v2, d[idx2 + w + 1] + dg)
				if i > 0:
					v2 = minf(v2, d[idx2 + w - 1] + dg)
			d[idx2] = v2
	var img := Image.create_empty(w, h, false, Image.FORMAT_R8)
	for j in h:
		for i in w:
			img.set_pixel(i, j, Color(clampf(d[j * w + i] / 3000.0, 0.0, 1.0), 0.0, 0.0))
	return img


func _exit_tree() -> void:
	for id in _task_ids:
		WorkerThreadPool.wait_for_task_completion(id)
	_task_ids.clear()


func set_focus(n: Node3D) -> void:
	focus = n


## Scale the terrain streaming/LOD distances (graphics "view distance" setting).
func set_view_scale(s: float) -> void:
	if _base_lod.is_empty():
		_base_lod = lod_distances.duplicate()
	var d: Array[float] = []
	for v in _base_lod:
		d.append(float(v) * s)
	lod_distances = d
	if has_method("rebuild"):
		call("rebuild")


## Flatten terrain around an airfield. Call BEFORE the first chunks are generated if possible
## (otherwise call rebuild()). Returns the flattened height (world Y).
func add_flat_zone(world_pos: Vector3, flat_radius: float, blend: float) -> float:
	return field.add_flat_zone(world_pos.x, world_pos.z, flat_radius, blend)


func get_terrain_y(x: float, z: float) -> float:
	return field.height_y(x, z)


## Ground height for gameplay: never below sea level (0).
func get_height_at(pos: Vector3) -> float:
	return maxf(field.height_y(pos.x, pos.z), 0.0)


func is_water_at(pos: Vector3) -> bool:
	return field.height_y(pos.x, pos.z) < 0.6


## Drop all chunks and regenerate (e.g. after adding flat zones).
func rebuild() -> void:
	_generation += 1
	for k in _chunks.keys():
		(_chunks[k]["node"] as Node).queue_free()
	_chunks.clear()
	_pending.clear()
	_timer = 0.0


func _process(delta: float) -> void:
	_drain_results()
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.1
		_update_streaming()
		if _zones_all.size() > 24:
			_upload_zones()


## True once every chunk wanted around the focus has been built (used by the load screen).
func is_settled() -> bool:
	return _pending.is_empty() and _inflight == 0 and not _chunks.is_empty()


func _lod_for(d: float) -> int:
	for i in lod_distances.size():
		if d < lod_distances[i]:
			return i
	return -1


func _desired_lod(d: float, current: int) -> int:
	var base: int = _lod_for(d)
	if current >= 0 and base >= 0 and base != current:
		var lo: int = _lod_for(d * 0.85)
		var hi: int = _lod_for(d * 1.15)
		if hi == -1:
			hi = lod_distances.size()
		if current >= lo and current <= hi:
			return current
	return base


func _update_streaming() -> void:
	var fp: Vector3 = focus.global_position if focus else Vector3(0, 0, 0)
	var rmax: float = lod_distances[lod_distances.size() - 1]
	var cr: int = int(ceil(rmax / chunk_size)) + 1
	var cx0: int = floori(fp.x / chunk_size)
	var cz0: int = floori(fp.z / chunk_size)
	var wanted: Dictionary = {}
	var requests: Array = []
	for dz in range(-cr, cr + 1):
		for dx in range(-cr, cr + 1):
			var key := Vector2i(cx0 + dx, cz0 + dz)
			var center := Vector2((key.x + 0.5) * chunk_size, (key.y + 0.5) * chunk_size)
			if not _bounds.has_point(center):
				continue
			var d: float = Vector2(center.x - fp.x, center.y - fp.z).length() - chunk_size * 0.5
			d = maxf(d, 0.0)
			var current: int = _chunks[key]["lod"] if _chunks.has(key) else -1
			var lod: int = _desired_lod(d, current)
			if lod < 0:
				continue
			wanted[key] = lod
			if lod != current and _pending.get(key, -2) != lod:
				requests.append([d, key, lod])
	# unload far chunks
	for key in _chunks.keys():
		if not wanted.has(key):
			(_chunks[key]["node"] as Node).queue_free()
			_chunks.erase(key)
	requests.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for r in requests:
		if _inflight >= max_inflight:
			break
		_dispatch(r[1], r[2])


func _dispatch(key: Vector2i, lod: int) -> void:
	for i in range(_task_ids.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_task_ids[i]):
			WorkerThreadPool.wait_for_task_completion(_task_ids[i])
			_task_ids.remove_at(i)
	_pending[key] = lod
	_inflight += 1
	var gen: int = _generation
	_task_ids.append(WorkerThreadPool.add_task(func() -> void: _build_task(key, lod, gen)))


func _build_task(key: Vector2i, lod: int, gen: int) -> void:
	var arrays: Array = _build_arrays(key, lod)
	_mutex.lock()
	_results.append({"key": key, "lod": lod, "arrays": arrays, "gen": gen})
	_mutex.unlock()


func _drain_results() -> void:
	_mutex.lock()
	var batch: Array = _results
	_results = []
	_mutex.unlock()
	var keep: Array = []
	var made: int = 0
	for r in batch:
		if made >= max_instantiate_per_frame:
			keep.append(r)
			continue
		_inflight -= 1
		made += 1
		var key: Vector2i = r["key"]
		if r["gen"] != _generation:
			continue
		if _pending.get(key, -2) == r["lod"]:
			_pending.erase(key)
		_install(key, r["lod"], r["arrays"])
	if not keep.is_empty():
		_mutex.lock()
		_results.append_array(keep)
		_mutex.unlock()
	if not _initial_done and _inflight == 0 and not _chunks.is_empty() and _pending.is_empty():
		_initial_done = true
		initial_chunks_ready.emit()


func _install(key: Vector2i, lod: int, arrays: Array) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node: MeshInstance3D
	if _chunks.has(key):
		node = _chunks[key]["node"]
	else:
		node = MeshInstance3D.new()
		node.position = Vector3(key.x * chunk_size, 0.0, key.y * chunk_size)
		node.material_override = material
		if not shadows_on_terrain:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	node.mesh = mesh
	_chunks[key] = {"node": node, "lod": lod}


## Runs on a worker thread. Builds mesh arrays for a chunk at a given LOD (with edge skirts).
func _build_arrays(key: Vector2i, lod: int) -> Array:
	var res: int = lod_resolutions[lod]
	var step: float = chunk_size / float(res)
	var ox: float = key.x * chunk_size
	var oz: float = key.y * chunk_size
	var n: int = res + 1
	var gn: int = res + 3
	var hs := PackedFloat32Array()
	hs.resize(gn * gn)
	for j in gn:
		for i in gn:
			hs[j * gn + i] = field.height_y(ox + float(i - 1) * step, oz + float(j - 1) * step)
	var skirt: float = maxf(30.0, step * 1.3)
	var vcount: int = n * n + 4 * n
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(vcount)
	norms.resize(vcount)
	for j in n:
		for i in n:
			var gi: int = (j + 1) * gn + (i + 1)
			var h: float = hs[gi]
			var dhdx: float = (hs[gi + 1] - hs[gi - 1]) / (2.0 * step)
			var dhdz: float = (hs[gi + gn] - hs[gi - gn]) / (2.0 * step)
			var idx: int = j * n + i
			verts[idx] = Vector3(float(i) * step, h, float(j) * step)
			norms[idx] = Vector3(-dhdx, 1.0, -dhdz).normalized()
	var indices := PackedInt32Array()
	indices.resize(res * res * 6 + 4 * res * 6)
	var w: int = 0
	for j in res:
		for i in res:
			var a: int = j * n + i
			var b: int = a + 1
			var c: int = a + n
			var d: int = c + 1
			indices[w] = a
			indices[w + 1] = b
			indices[w + 2] = c
			indices[w + 3] = b
			indices[w + 4] = d
			indices[w + 5] = c
			w += 6
	# skirts: 4 edges, vertices appended after the grid
	var base: int = n * n
	var edges: Array = []
	var top := PackedInt32Array()
	var bottom := PackedInt32Array()
	var left := PackedInt32Array()
	var right := PackedInt32Array()
	for i in n:
		top.append(i)
		bottom.append(res * n + i)
		left.append(i * n)
		right.append(i * n + res)
	edges = [top, bottom, left, right]
	for e in 4:
		var src: PackedInt32Array = edges[e]
		var start: int = base + e * n
		for i in n:
			var v: Vector3 = verts[src[i]]
			verts[start + i] = Vector3(v.x, v.y - skirt, v.z)
			norms[start + i] = norms[src[i]]
		for i in res:
			var a2: int = src[i]
			var b2: int = src[i + 1]
			var c2: int = start + i
			var d2: int = start + i + 1
			indices[w] = a2
			indices[w + 1] = b2
			indices[w + 2] = c2
			indices[w + 3] = b2
			indices[w + 4] = d2
			indices[w + 5] = c2
			w += 6
	# Near-vertical chalk cliff faces along the coastline (the coarse DEM/mask cannot hold one).
	var cliff: Dictionary = CliffSkirt.build_chunk(field, ox, oz, chunk_size)
	var sv: PackedVector3Array = cliff["verts"]
	if not sv.is_empty():
		var sn: PackedVector3Array = cliff["norms"]
		var si: PackedInt32Array = cliff["indices"]
		var off: int = verts.size()
		verts.append_array(sv)
		norms.append_array(sn)
		for k in si.size():
			indices.append(si[k] + off)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
