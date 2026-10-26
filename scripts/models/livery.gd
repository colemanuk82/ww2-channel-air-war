class_name Livery
extends RefCounted
## Painted liveries: every aircraft's skin carries one texture, like a real paint job, instead of camouflage
## projected from noise plus separate marking meshes laid over the top. The procedural airframe is not changed:
## at load its skin parts get UV coordinates from a fixed, deterministic unwrap (the fuselage, nacelles and other
## long bodies are unrolled round their axis, everything else is split by facing into flat charts), all packed
## into one square atlas. assets/liveries/<model>_<nation>.png is painted into that atlas by
## tools/liveries/paint_liveries.py from the researched scheme of the real aircraft, with the roundels, crosses,
## stripes and codes painted in, and weathered. The .json beside it records the layout it was painted for.
## When the PNG is missing or its layout no longer matches the model, the aircraft keeps its old look.
##
## Repaint after changing a model: tools/hidden/livery_build.ps1 [-Only id,id]  (see tools/liveries/README.md)

const DIR := "res://assets/liveries/"
const GEO_DIR := "res://tools/liveries/geo/"
const PAD := 6                          # texels of padding round every chart (mip / filtering bleed)
const TARGET_TEXEL := 0.0095            # metres per texel needed to settle the atlas size; the atlas is then filled
const MAX_SIZE := 4096
## Markings that stay as their own meshes (so they can be switched off) rather than being painted in.
const KEEP_SEPARATE := ["Swastika", "FinDisc"]

static var _meshes: Dictionary = {}     # key -> Array of unwrapped ArrayMesh, in skin_parts order
static var _meta: Dictionary = {}       # key -> parsed json, or {} when there is no livery
static var _warned: Dictionary = {}


static func key(model_id: String, nation: String) -> String:
	return "%s_%s" % [model_id, nation.to_lower()]


static func has_livery(model_id: String, nation: String) -> bool:
	return not _load_meta(key(model_id, nation)).is_empty()


static func _load_meta(k: String) -> Dictionary:
	if _meta.has(k):
		return _meta[k]
	var d: Dictionary = {}
	var p: String = DIR + k + ".json"
	if FileAccess.file_exists(p) and ResourceLoader.exists(DIR + k + ".png"):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if v is Dictionary:
			d = v
	_meta[k] = d
	return d


## The skin parts (meshes wearing the airframe skin material), in a fixed order.
static func skin_parts(root: Node3D, skin: Material) -> Array:
	var out: Array = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.material_override == skin and mi.mesh != null:
			out.append(mi)
	return out


## Name of the nearest node at or above n whose name says it is a marking ("" when it is not one).
static func decal_group(n: Node, root: Node) -> String:
	var c: Node = n
	while c != null and c != root:
		var nm: String = String(c.name)
		if nm.contains("Decal"):
			return nm
		c = c.get_parent()
	return ""


static func painted_in(group: String) -> bool:
	if group == "":
		return false
	for s in KEEP_SEPARATE:
		if group.contains(s):
			return false
	return true


static func to_root(n: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != root:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


## Cheap fingerprint of the skin layout: part count, vertex / index counts and sizes.
static func signature(parts: Array, root: Node3D) -> int:
	var s: String = str(parts.size())
	for mi in parts:
		var m: Mesh = (mi as MeshInstance3D).mesh
		var ab: AABB = to_root(mi, root) * m.get_aabb()
		s += "|%d:%.2f,%.2f,%.2f,%.2f,%.2f,%.2f" % [m.get_surface_count(), ab.position.x, ab.position.y, ab.position.z, ab.size.x, ab.size.y, ab.size.z]
		if m is ArrayMesh:
			for si in m.get_surface_count():
				s += ",%d/%d" % [(m as ArrayMesh).surface_get_array_len(si), (m as ArrayMesh).surface_get_array_index_len(si)]
	return s.hash()


## Paint the model with its livery when one has been painted for this exact layout (else leave it as it is).
static func apply(root: Node3D, model_id: String, nation: String, skin: ShaderMaterial) -> bool:
	if skin == null:
		return false
	var k: String = key(model_id, nation)
	var meta: Dictionary = _load_meta(k)
	if meta.is_empty() or disabled:
		return false
	var parts: Array = skin_parts(root, skin)
	if signature(parts, root) != int(meta.get("sig", 0)):
		if not _warned.has(k):
			_warned[k] = true
			push_warning("Livery %s was painted for a different model layout; repaint it (tools/liveries)" % k)
		return false
	var meshes: Array = _meshes.get(k, [])
	if meshes.size() != parts.size():
		meshes = unwrap(parts, root)["meshes"]
		_meshes[k] = meshes
	for i in parts.size():
		(parts[i] as MeshInstance3D).mesh = meshes[i]
	skin.set_shader_parameter("livery_tex", load(DIR + k + ".png") as Texture2D)
	skin.set_shader_parameter("use_livery", true)
	# the markings and codes are in the paint now: drop their separate meshes / labels
	var gone: Array = []
	for n in root.find_children("*", "", true, false):
		if (n is MeshInstance3D or n is Label3D) and painted_in(decal_group(n, root)):
			gone.append(n)
	for n in gone:
		(n as Node).get_parent().remove_child(n)
		(n as Node).free()
	return true


# ---------------------------------------------------------------- unwrap

## UVs for every skin part: returns {"meshes": [ArrayMesh], "size": atlas px, "charts": n}
static func unwrap(parts: Array, root: Node3D) -> Dictionary:
	var surfs: Array = []        # per part: Array of {arr, idx, proj (per corner), tchart (per tri)}
	var charts: Array = []       # {min, max} in projection metres
	for mi in parts:
		var xf: Transform3D = to_root(mi, root)
		var m: Mesh = (mi as MeshInstance3D).mesh
		var plist: Array = []
		var pts_all := PackedVector3Array()
		var ab: AABB = xf * m.get_aabb()
		var e: Vector3 = ab.size
		var cyl: bool = e.z > 1.6 * maxf(e.x, e.y) and minf(e.x, e.y) > e.z * 0.04
		for si in m.get_surface_count():
			var arr: Array = m.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				idx.resize(vs.size())
				for i in vs.size():
					idx[i] = i
			var P := PackedVector3Array()
			P.resize(vs.size())
			for i in vs.size():
				P[i] = xf * vs[i]
			var nt: int = idx.size() / 3
			var proj := PackedVector2Array()
			proj.resize(nt * 3)
			var tchart := PackedInt32Array()
			tchart.resize(nt)
			if cyl:
				_unwrap_cyl(P, idx, proj, ab)
				var ci: int = charts.size()
				charts.append(_bounds(proj, 0, proj.size()))
				tchart.fill(ci)
			else:
				var base: Dictionary = {}
				for t in nt:
					var a: Vector3 = P[idx[t * 3]]
					var b: Vector3 = P[idx[t * 3 + 1]]
					var c: Vector3 = P[idx[t * 3 + 2]]
					var fn: Vector3 = (b - a).cross(c - a)
					var an := Vector3(absf(fn.x), absf(fn.y), absf(fn.z))
					var cls: int
					if an.y >= an.x and an.y >= an.z:
						cls = 0 if fn.y >= 0.0 else 1
					elif an.x >= an.z:
						cls = 2 if fn.x >= 0.0 else 3
					else:
						cls = 4 if fn.z >= 0.0 else 5
					for q in 3:
						var p: Vector3 = P[idx[t * 3 + q]]
						var uv: Vector2
						if cls < 2:
							uv = Vector2(p.x, p.z)
						elif cls < 4:
							uv = Vector2(p.z, p.y)
						else:
							uv = Vector2(p.x, p.y)
						proj[t * 3 + q] = uv
					if not base.has(cls):
						base[cls] = charts.size()
						charts.append({"min": Vector2(INF, INF), "max": Vector2(-INF, -INF)})
					var ch: Dictionary = charts[base[cls]]
					for q in 3:
						ch["min"] = (ch["min"] as Vector2).min(proj[t * 3 + q])
						ch["max"] = (ch["max"] as Vector2).max(proj[t * 3 + q])
					tchart[t] = base[cls]
			plist.append({"arr": arr, "idx": idx, "proj": proj, "tchart": tchart})
		surfs.append(plist)

	# ---- pack the charts (shelves, tallest first), then grow the scale to fill the atlas
	var dims: Array = []
	for ch in charts:
		var sz: Vector2 = (ch["max"] as Vector2) - (ch["min"] as Vector2)
		sz = sz.max(Vector2(0.002, 0.002))
		dims.append(sz)
	var order: Array = range(charts.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var ha: float = minf(dims[a].x, dims[a].y)
		var hb: float = minf(dims[b].x, dims[b].y)
		return ha > hb if ha != hb else a < b)
	var size: int = 512
	var k: float = 1.0 / TARGET_TEXEL
	while size < MAX_SIZE and _pack(dims, order, k, size).is_empty():
		size *= 2
	var lo: float = k * 0.25
	var hi: float = k * 2.5
	if _pack(dims, order, k, size).is_empty():
		hi = k
	else:
		lo = k
	for it in 18:
		var mid: float = (lo + hi) * 0.5
		if _pack(dims, order, mid, size).is_empty():
			hi = mid
		else:
			lo = mid
	k = lo
	var place: Dictionary = _pack(dims, order, k, size)

	# ---- build the de-indexed meshes with UVs
	var meshes: Array = []
	for pi in parts.size():
		var am := ArrayMesh.new()
		for sd in surfs[pi]:
			var arr: Array = sd["arr"]
			var idx: PackedInt32Array = sd["idx"]
			var proj: PackedVector2Array = sd["proj"]
			var tchart: PackedInt32Array = sd["tchart"]
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var n: int = idx.size()
			var ov := PackedVector3Array()
			ov.resize(n)
			var on := PackedVector3Array()
			if not ns.is_empty():
				on.resize(n)
			var oc := PackedColorArray()
			if not cs.is_empty():
				oc.resize(n)
			var ouv := PackedVector2Array()
			ouv.resize(n)
			for i in n:
				var vi: int = idx[i]
				ov[i] = vs[vi]
				if not ns.is_empty():
					on[i] = ns[vi]
				if not cs.is_empty():
					oc[i] = cs[vi]
				var ci: int = tchart[i / 3]
				var pl: Vector3 = place[ci]          # x, y = texel origin, z = 1 when turned 90 degrees
				var q: Vector2 = proj[i] - (charts[ci]["min"] as Vector2)
				if pl.z > 0.5:
					q = Vector2(q.y, q.x)
				ouv[i] = (Vector2(pl.x, pl.y) + q * k) / float(size)
			var out: Array = []
			out.resize(Mesh.ARRAY_MAX)
			out[Mesh.ARRAY_VERTEX] = ov
			if not on.is_empty():
				out[Mesh.ARRAY_NORMAL] = on
			if not oc.is_empty():
				out[Mesh.ARRAY_COLOR] = oc
			out[Mesh.ARRAY_TEX_UV] = ouv
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
		meshes.append(am)
	return {"meshes": meshes, "size": size, "charts": charts.size(), "texel": 1.0 / k}


static func _bounds(p: PackedVector2Array, a: int, b: int) -> Dictionary:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for i in range(a, b):
		mn = mn.min(p[i])
		mx = mx.max(p[i])
	return {"min": mn, "max": mx}


## A long body unrolled round its axis: u = arc length round the section (seam along the belly), v = length.
static func _unwrap_cyl(P: PackedVector3Array, idx: PackedInt32Array, proj: PackedVector2Array, ab: AABB) -> void:
	const BIN := 0.2
	var z0: float = ab.position.z
	var nb: int = int(ab.size.z / BIN) + 2
	var sx := PackedFloat64Array()
	var sy := PackedFloat64Array()
	var sn := PackedFloat64Array()
	var sr := PackedFloat64Array()
	sx.resize(nb)
	sy.resize(nb)
	sn.resize(nb)
	sr.resize(nb)
	for p in P:
		var b: int = clampi(int((p.z - z0) / BIN), 0, nb - 1)
		sx[b] += p.x
		sy[b] += p.y
		sn[b] += 1.0
	var cx := PackedFloat64Array()
	var cy := PackedFloat64Array()
	cx.resize(nb)
	cy.resize(nb)
	var lastx: float = ab.get_center().x
	var lasty: float = ab.get_center().y
	for b in nb:
		if sn[b] > 0.0:
			lastx = sx[b] / sn[b]
			lasty = sy[b] / sn[b]
		cx[b] = lastx
		cy[b] = lasty
	for p in P:
		var b: int = clampi(int((p.z - z0) / BIN), 0, nb - 1)
		sr[b] += Vector2(p.x - cx[b], p.y - cy[b]).length()
	var rr := PackedFloat64Array()
	rr.resize(nb)
	var lastr: float = maxf(ab.size.x, ab.size.y) * 0.5
	for b in nb:
		if sn[b] > 0.0:
			lastr = maxf(sr[b] / sn[b], 0.01)
		rr[b] = lastr
	var nt: int = idx.size() / 3
	for t in nt:
		var ang := [0.0, 0.0, 0.0]
		var rad := [0.0, 0.0, 0.0]
		for q in 3:
			var p: Vector3 = P[idx[t * 3 + q]]
			var fb: float = clampf((p.z - z0) / BIN - 0.5, 0.0, float(nb - 1))
			var b0: int = int(fb)
			var b1: int = mini(b0 + 1, nb - 1)
			var f: float = fb - float(b0)
			var ccx: float = lerpf(cx[b0], cx[b1], f)
			var ccy: float = lerpf(cy[b0], cy[b1], f)
			ang[q] = atan2(p.x - ccx, p.y - ccy)
			rad[q] = lerpf(rr[b0], rr[b1], f)
		if maxf(ang[0], maxf(ang[1], ang[2])) - minf(ang[0], minf(ang[1], ang[2])) > PI:
			for q in 3:
				if ang[q] < 0.0:
					ang[q] += TAU
		for q in 3:
			var p2: Vector3 = P[idx[t * 3 + q]]
			proj[t * 3 + q] = Vector2(ang[q] * rad[q], p2.z)


## Shelf-pack chart sizes (metres) at k texels per metre into size x size: chart -> Vector3(x, y, turned), or {}.
static func _pack(dims: Array, order: Array, k: float, size: int) -> Dictionary:
	var out: Dictionary = {}
	var x: int = 0
	var y: int = 0
	var shelf: int = 0
	for ci in order:
		var d: Vector2 = dims[ci]
		var turned: bool = d.y > d.x
		var w: int = int(ceil((d.y if turned else d.x) * k)) + PAD * 2
		var h: int = int(ceil((d.x if turned else d.y) * k)) + PAD * 2
		if w > size:
			return {}
		if x + w > size:
			x = 0
			y += shelf
			shelf = 0
		if y + h > size:
			return {}
		out[ci] = Vector3(x + PAD, y + PAD, 1.0 if turned else 0.0)
		x += w
		shelf = maxi(shelf, h)
	return out


# ---------------------------------------------------------------- export for the painter

static var disabled: bool = false       # set while exporting, so the model comes out unpainted


## Writes what tools/liveries/paint_liveries.py needs to paint one aircraft: the unwrapped skin triangles
## (positions, normals, UVs, which part), the marking triangles and their colours, the code labels and the
## exhaust outlets, all in model space (metres, nose towards -Z).
static func export_geo(model_id: String, nation: String, dir: String) -> String:
	disabled = true
	var root: Node3D = AircraftModels.build(model_id, nation)
	disabled = false
	if root == null:
		return "no model"
	var skin: ShaderMaterial = null
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var sm := (n as MeshInstance3D).material_override as ShaderMaterial
		if sm != null and sm.shader == GltfModels.shader():
			skin = sm
			break
	if skin == null:
		root.free()
		return "no skin"
	var parts: Array = skin_parts(root, skin)
	var sig: int = signature(parts, root)
	var t0: int = Time.get_ticks_msec()
	var uw: Dictionary = unwrap(parts, root)
	var ms: int = Time.get_ticks_msec() - t0
	var skin_f := PackedFloat32Array()
	var part_info: Array = []
	var fus_z: Vector2 = Vector2(-4, 4)
	for i in parts.size():
		var mi: MeshInstance3D = parts[i]
		if String(mi.name) == "Fuselage":
			var fab: AABB = to_root(mi, root) * mi.mesh.get_aabb()
			fus_z = Vector2(fab.position.z, fab.end.z)
	for i in parts.size():
		var mi: MeshInstance3D = parts[i]
		var xf: Transform3D = to_root(mi, root)
		var nb: Basis = xf.basis.inverse().transposed()
		var ab: AABB = xf * mi.mesh.get_aabb()
		var e: Vector3 = ab.size
		var nm: String = String(mi.name)
		var under_canopy: bool = _has_ancestor(mi, root, "Canopy")
		var cls: int = 5
		if under_canopy:
			cls = 5
		elif nm == "Fuselage":
			cls = 0
		elif nm.begins_with("Wing") and nm != "WingSpat":
			cls = 1
		elif nm.begins_with("Tailplane"):
			cls = 2
		elif nm == "Fin":
			cls = 3
		elif nm == "WheelSpat" or (e.z > 1.6 * maxf(e.x, e.y) and minf(e.x, e.y) > e.z * 0.04):
			cls = 4
		elif e.x < 0.3 * minf(e.y, e.z):
			cls = 3
		elif e.y < 0.3 * minf(e.x, e.z):
			cls = 2 if ab.get_center().z > lerpf(fus_z.x, fus_z.y, 0.6) else 1
		part_info.append({"name": nm, "class": cls, "aabb": [ab.position.x, ab.position.y, ab.position.z, ab.end.x, ab.end.y, ab.end.z]})
		var am: ArrayMesh = uw["meshes"][i]
		for si in am.get_surface_count():
			var arr: Array = am.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			for vi in vs.size():
				var p: Vector3 = xf * vs[vi]
				var nn: Vector3 = (nb * ns[vi]).normalized() if not ns.is_empty() else Vector3.UP
				skin_f.append_array([p.x, p.y, p.z, nn.x, nn.y, nn.z, uv[vi].x, uv[vi].y, float(i)])
	# markings
	var dec_f := PackedFloat32Array()
	var labels: Array = []
	var groups: Array = []
	var gi: int = 0
	for n in root.find_children("*", "", true, false):
		var grp: String = decal_group(n, root)
		if not painted_in(grp):
			continue
		var xf2: Transform3D = to_root(n, root)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi2: MeshInstance3D = n
			if not mi2.visible:
				continue
			var col := Color(0.5, 0.5, 0.5)
			var mat: Material = mi2.material_override
			if mat is ShaderMaterial:
				var a: Variant = (mat as ShaderMaterial).get_shader_parameter("albedo")
				if a != null:
					col = a
			elif mat is StandardMaterial3D:
				col = (mat as StandardMaterial3D).albedo_color
			var nb2: Basis = xf2.basis.inverse().transposed()
			var m2: Mesh = mi2.mesh
			for si in m2.get_surface_count():
				var arr2: Array = m2.surface_get_arrays(si)
				var vs2: PackedVector3Array = arr2[Mesh.ARRAY_VERTEX]
				var ns2: PackedVector3Array = arr2[Mesh.ARRAY_NORMAL] if arr2[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
				var idx2: PackedInt32Array = arr2[Mesh.ARRAY_INDEX] if arr2[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var cnt: int = idx2.size() if not idx2.is_empty() else vs2.size()
				for c in cnt:
					var vi2: int = idx2[c] if not idx2.is_empty() else c
					var p2: Vector3 = xf2 * vs2[vi2]
					var n2: Vector3 = (nb2 * ns2[vi2]).normalized() if not ns2.is_empty() else Vector3.ZERO
					dec_f.append_array([p2.x, p2.y, p2.z, n2.x, n2.y, n2.z, col.r, col.g, col.b, float(gi)])
			groups.append(grp)
			gi += 1
		elif n is Label3D:
			var lb: Label3D = n
			var b: Basis = xf2.basis
			labels.append({"text": lb.text, "font_size": lb.font_size, "pixel_size": lb.pixel_size,
				"color": [lb.modulate.r, lb.modulate.g, lb.modulate.b], "outline_size": lb.outline_size,
				"outline": [lb.outline_modulate.r, lb.outline_modulate.g, lb.outline_modulate.b],
				"origin": [xf2.origin.x, xf2.origin.y, xf2.origin.z],
				"x": [b.x.x, b.x.y, b.x.z], "y": [b.y.x, b.y.y, b.y.z], "z": [b.z.x, b.z.y, b.z.z]})
	var exh: Array = []
	for n in root.find_children("Exhaust*", "Node3D", true, false):
		var o: Vector3 = to_root(n, root).origin
		exh.append([o.x, o.y, o.z])
	var k: String = key(model_id, nation)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(dir + k + ".skin.bin", FileAccess.WRITE)
	f.store_buffer(skin_f.to_byte_array())
	f.close()
	f = FileAccess.open(dir + k + ".decal.bin", FileAccess.WRITE)
	f.store_buffer(dec_f.to_byte_array())
	f.close()
	var meta := {"model": model_id, "nation": nation, "sig": sig, "size": uw["size"], "texel": uw["texel"],
		"charts": uw["charts"], "parts": part_info, "groups": groups, "labels": labels, "exhausts": exh}
	f = FileAccess.open(dir + k + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, " "))
	f.close()
	root.free()
	return "%s: %d parts, %d tris, atlas %d (%.1f mm/texel), %d charts, unwrap %d ms, %d marking meshes, %d labels" % [
		k, parts.size(), skin_f.size() / 27, uw["size"], float(uw["texel"]) * 1000.0, uw["charts"], ms, gi, labels.size()]


static func _has_ancestor(n: Node, root: Node, nm: String) -> bool:
	var c: Node = n.get_parent()
	while c != null and c != root:
		if String(c.name) == nm:
			return true
		c = c.get_parent()
	return false
