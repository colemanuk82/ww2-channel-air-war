class_name Scatter
extends RefCounted
## MultiMesh scatter builders: towns, forests, countryside tiles (farms, hedgerows, cattle, windmills),
## beach obstacles and defensive lines. All results are Node3D containers added at world origin.

## Draw distances (world units). Tiles are streamed in beyond these (see WorldPopulator.TILE_RADIUS) so
## content fades in while still invisible instead of popping.
const VIS_TREE: float = 10500.0
const VIS_HOUSE: float = 10500.0
const VIS_HEDGE: float = 3600.0
const VIS_COW: float = 3500.0

## Scales every instanced-detail draw distance (set from the View distance setting).
static var vis_scale: float = 1.0
static var _meshes: Dictionary = {}
static var _vmats: Dictionary = {}
const _MKEYS: Array = ["underside_color", "underside_amount", "patch_color", "patch_amount", "patch_scale", "rim_amount",
	"gloss", "softness", "flat_shade", "detail_mode", "emission_color", "emission_energy", "use_ramp_tex"]


## Like GroundKit.combine, but parts whose toon materials differ only in colour share ONE surface: the colour
## goes into the vertex colours (toon use_vcol). A tree drops from ~9 draws (+9 outline passes) to 2 (+2).
static func _merge(parts: Array) -> ArrayMesh:
	var groups: Dictionary = {}
	var order: Array = []
	for p in parts:
		var m: Mesh = p[0]
		var t: Transform3D = p[1]
		var mat: Material = p[2]
		var key: String = "id%d" % mat.get_instance_id()
		var col := Color.WHITE
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader == ToonUtil.toon_shader():
			var sm: ShaderMaterial = mat
			var parts_k: Array = []
			for k in _MKEYS:
				parts_k.append(str(sm.get_shader_parameter(k)))
			var np: ShaderMaterial = sm.next_pass as ShaderMaterial
			parts_k.append("none" if np == null else "%s_%s" % [str(np.get_shader_parameter("thickness")), str(np.get_shader_parameter("outline_color"))])
			key = "|".join(parts_k)
			col = sm.get_shader_parameter("albedo")
			if not _vmats.has(key):
				var vm: ShaderMaterial = sm.duplicate()
				vm.set_shader_parameter("albedo", Color.WHITE)
				vm.set_shader_parameter("use_vcol", true)
				_vmats[key] = vm
		elif mat is ShaderMaterial and (mat as ShaderMaterial).shader == GroundKit.paint_shader():
			var pm: ShaderMaterial = mat
			key = "paint|%s" % str(pm.get_shader_parameter("roughness_v"))
			col = pm.get_shader_parameter("albedo")
			if not _vmats.has(key):
				var pv: ShaderMaterial = pm.duplicate()
				pv.set_shader_parameter("albedo", Color.WHITE)
				pv.set_shader_parameter("use_vcol", true)
				_vmats[key] = pv
		if not groups.has(key):
			groups[key] = {"mat": _vmats.get(key, mat), "v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
			order.append(key)
		var g: Dictionary = groups[key]
		var arrays: Array = m.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var nrms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		var idx = arrays[Mesh.ARRAY_INDEX]
		var gv: PackedVector3Array = g["v"]
		var gn: PackedVector3Array = g["n"]
		var guv: PackedVector2Array = g["uv"]
		var gc: PackedColorArray = g["c"]
		var gi: PackedInt32Array = g["i"]
		var base: int = gv.size()
		var lin: Color = col.srgb_to_linear()
		var has_uv: bool = uvs != null and (uvs as PackedVector2Array).size() == verts.size()
		for i in verts.size():
			gv.append(t * verts[i])
			gn.append((t.basis * nrms[i]).normalized())
			guv.append(uvs[i] if has_uv else Vector2.ZERO)
			gc.append(lin)
		if idx != null and (idx as PackedInt32Array).size() > 0:
			for ii in (idx as PackedInt32Array):
				gi.append(base + ii)
		else:
			for ii2 in verts.size():
				gi.append(base + ii2)
		g["v"] = gv
		g["n"] = gn
		g["uv"] = guv
		g["c"] = gc
		g["i"] = gi
	var out := ArrayMesh.new()
	for key2 in order:
		var g2: Dictionary = groups[key2]
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g2["v"]
		arr[Mesh.ARRAY_NORMAL] = g2["n"]
		arr[Mesh.ARRAY_TEX_UV] = g2["uv"]
		arr[Mesh.ARRAY_COLOR] = g2["c"]
		arr[Mesh.ARRAY_INDEX] = g2["i"]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, g2["mat"])
	return out
static var _mats_d: Dictionary = {}


# ------------------------------------------------------------------ shared meshes
static func _dmat(color: Color, detail: int, thickness: float, outline: bool = true) -> ShaderMaterial:
	var key: String = "d%d_%s_%.3f_%s" % [detail, color.to_html(false), thickness, str(outline)]
	if _mats_d.has(key):
		return _mats_d[key]
	var opts: Dictionary = {"outline": outline, "outline_thickness": thickness, "rim": 0.0, "detail": detail}
	if detail == 1:
		opts["flat"] = true     # buildings shade flat: solid colour, no cast/self shadow, no toon banding
	if detail == 3:
		opts["soft"] = 0.6      # foliage shades softly and hazes with distance, like the menu paintings
	var m: ShaderMaterial = ToonUtil.make_toon(color, opts)
	_mats_d[key] = m
	return m


static func _boxm(w: float, h: float, d: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return b


## 1940s building stock, each filling the unit box that the placement transforms scale:
## 0/1 brick and rendered terrace units (the classic UK street), 2 semi-detached pair, 3 cottage,
## 4 corner shop, 5 Victorian villa, 6 warehouse, 7 works / factory, 8 cinema / picture palace,
## 9 railway station front (all share the unit box; 0-7 are unchanged - MultiMeshes index by variant).
static func house_mesh(variant: int) -> ArrayMesh:
	var key: String = "house%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var brick: Color = Color(0.46, 0.28, 0.21)        # red brick: the common UK stock
	var brick_dk: Color = Color(0.35, 0.23, 0.18)     # soot-darkened brick (industrial, older terraces)
	var stone: Color = Color(0.52, 0.47, 0.40)        # pale render / stone: villages and cottages
	var slate: Color = Color(0.29, 0.30, 0.33)
	var chimney: Color = Color(0.34, 0.22, 0.17)
	if variant == 8:
		# cinema / picture palace: a rendered front with a lit marquee band over the entrance
		var cparts: Array = []
		cparts.append([_boxm(0.86, 0.86, 1.0), Transform3D(Basis.IDENTITY, Vector3.ZERO), _dmat(Color(0.56, 0.51, 0.46), 1, 0.0, false)])
		cparts.append([_boxm(0.94, 0.66, 0.14), Transform3D(Basis.IDENTITY, Vector3(0.0, -0.08, -0.52)), _dmat(Color(0.63, 0.60, 0.55), 1, 0.0, false)])
		cparts.append([_boxm(0.90, 0.13, 0.06), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.17, -0.58)), _dmat(Color(0.98, 0.86, 0.42), 1, 0.0, false)])
		cparts.append([_boxm(0.30, 0.36, 0.06), Transform3D(Basis.IDENTITY, Vector3(0.0, -0.17, -0.58)), _dmat(Color(0.12, 0.11, 0.10), 1, 0.0, false)])
		var m8: ArrayMesh = GroundKit.combine(cparts)
		_meshes[key] = m8
		return m8
	if variant == 9:
		# station front: low, long frontage with a platform canopy over the track side and a clock block
		var sparts: Array = []
		sparts.append([_boxm(1.0, 0.66, 1.0), Transform3D(Basis.IDENTITY, Vector3(0.0, -0.17, 0.0)), _dmat(brick, 1, 0.0, false)])
		sparts.append([GroundKit.prism_mesh(1.04, 1.0, 0.22), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.33, 0.0)), _dmat(slate, 1, 0.0, false)])
		sparts.append([_boxm(1.02, 0.05, 0.30), Transform3D(Basis.IDENTITY, Vector3(0.0, -0.06, -0.62)), _dmat(Color(0.34, 0.34, 0.33), 1, 0.0, false)])
		sparts.append([_boxm(0.10, 0.24, 0.10), Transform3D(Basis.IDENTITY, Vector3(0.34, 0.58, 0.0)), _dmat(stone, 1, 0.0, false)])
		var m9: ArrayMesh = GroundKit.combine(sparts)
		_meshes[key] = m9
		return m9
	var parts: Array = []
	match variant % 8:
		0, 1:   # terrace unit: narrow, two storeys, gable roof, bay to the street; a slim stack on the brick variant only
			var wall: Color = brick if variant == 0 else brick_dk
			parts.append([_boxm(1.0, 1.0, 1.0), Transform3D.IDENTITY, _dmat(wall, 1, 0.0, false)])
			parts.append([GroundKit.prism_mesh(1.05, 1.0, 0.40), Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), _dmat(slate, 1, 0.0, false)])
			if variant == 0:
				parts.append([_boxm(0.12, 0.26, 0.15), Transform3D(Basis.IDENTITY, Vector3(-0.38, 0.80, 0)), _dmat(chimney, 1, 0.0, false)])
			parts.append([_boxm(0.40, 0.40, 0.10), Transform3D(Basis.IDENTITY, Vector3(0.02, -0.30, -0.54)), _dmat(wall * 0.9, 1, 0.0, false)])
		2:   # semi-detached pair: wider, one roof over two homes (no stack: chimneys kept to a few house types so streets read less busy)
			parts.append([_boxm(1.0, 1.0, 1.0), Transform3D.IDENTITY, _dmat(brick, 1, 0.0, false)])
			parts.append([GroundKit.prism_mesh(1.08, 1.0, 0.34), Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), _dmat(slate, 1, 0.0, false)])
		3:   # cottage: low, deep thatch/tile roof
			parts.append([_boxm(1.0, 0.78, 1.0), Transform3D(Basis.IDENTITY, Vector3(0, -0.11, 0)), _dmat(stone, 1, 0.0, false)])
			parts.append([GroundKit.prism_mesh(1.12, 1.06, 0.55), Transform3D(Basis.IDENTITY, Vector3(0, 0.28, 0)), _dmat(Color(0.50, 0.42, 0.26), 1, 0.0, false)])
		4:   # corner shop: taller, parapet front, shopfront band at street level
			parts.append([_boxm(1.0, 1.0, 1.0), Transform3D.IDENTITY, _dmat(brick * 1.06, 1, 0.0, false)])
			parts.append([_boxm(1.04, 0.10, 1.04), Transform3D(Basis.IDENTITY, Vector3(0, 0.52, 0)), _dmat(Color(0.34, 0.33, 0.31), 1, 0.0, false)])
			parts.append([_boxm(0.92, 0.22, 0.06), Transform3D(Basis.IDENTITY, Vector3(0, -0.24, -0.52)), _dmat(Color(0.20, 0.24, 0.26), 1, 0.0, false)])
		5:   # Victorian villa: taller, big bay, steep gable, tall stack
			parts.append([_boxm(1.0, 1.0, 1.0), Transform3D.IDENTITY, _dmat(brick * 0.95, 1, 0.0, false)])
			parts.append([GroundKit.prism_mesh(1.06, 1.0, 0.50), Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), _dmat(slate * 1.05, 1, 0.0, false)])
			parts.append([_boxm(0.44, 0.60, 0.14), Transform3D(Basis.IDENTITY, Vector3(0.0, -0.20, -0.55)), _dmat(brick * 0.88, 1, 0.0, false)])
			parts.append([_boxm(0.13, 0.32, 0.16), Transform3D(Basis.IDENTITY, Vector3(-0.38, 0.86, 0)), _dmat(chimney, 1, 0.0, false)])
		6:   # warehouse: tall brick block, shallow roof, small windows
			parts.append([_boxm(1.0, 1.0, 1.0), Transform3D.IDENTITY, _dmat(brick_dk, 1, 0.0, false)])
			parts.append([GroundKit.prism_mesh(1.04, 1.0, 0.18), Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), _dmat(slate * 0.9, 1, 0.0, false)])
		7:   # works / factory: long, low, flat roof with a works chimney
			parts.append([_boxm(1.0, 0.82, 1.0), Transform3D(Basis.IDENTITY, Vector3(0, -0.09, 0)), _dmat(brick_dk * 1.1, 1, 0.0, false)])
			parts.append([_boxm(1.02, 0.08, 1.02), Transform3D(Basis.IDENTITY, Vector3(0, 0.33, 0)), _dmat(Color(0.30, 0.29, 0.28), 1, 0.0, false)])
			parts.append([_boxm(0.16, 0.70, 0.16), Transform3D(Basis.IDENTITY, Vector3(0.34, 0.70, 0.30)), _dmat(chimney, 1, 0.0, false)])
	var m: ArrayMesh = _merge(parts)
	_meshes[key] = m
	return m


static func tree_mesh(round_tree: bool) -> ArrayMesh:
	var key: String = "tree_round" if round_tree else "tree_cone"
	if _meshes.has(key):
		return _meshes[key]
	var parts: Array = []
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.4
	trunk.bottom_radius = 0.6
	trunk.height = 4.0
	trunk.radial_segments = 5
	trunk.rings = 1
	parts.append([trunk, Transform3D(Basis.IDENTITY, Vector3(0, 2.0, 0)), GroundKit.mat(Color(0.28, 0.2, 0.13), false)])
	if round_tree:
		var sm := SphereMesh.new()
		sm.radius = 3.4
		sm.height = 6.2
		sm.radial_segments = 7
		sm.rings = 4
		parts.append([sm, Transform3D(Basis.IDENTITY, Vector3(0, 6.6, 0)), _dmat(Color(0.24, 0.36, 0.15), 3, 0.1)])
		# side lobes: the crown reads as foliage rather than one ball
		var lobe := SphereMesh.new()
		lobe.radius = 2.1
		lobe.height = 3.4
		lobe.radial_segments = 6
		lobe.rings = 3
		parts.append([lobe, Transform3D(Basis.IDENTITY, Vector3(1.8, 5.6, 0.8)), _dmat(Color(0.20, 0.33, 0.13), 3, 0.1)])
		parts.append([lobe, Transform3D(Basis.IDENTITY, Vector3(-1.6, 7.5, -0.7)), _dmat(Color(0.28, 0.41, 0.17), 3, 0.1)])
		var br := CylinderMesh.new()
		br.top_radius = 0.16
		br.bottom_radius = 0.24
		br.height = 2.6
		br.radial_segments = 4
		br.rings = 1
		parts.append([br, Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-48.0)), Vector3(1.1, 4.6, 0.4)), GroundKit.mat(Color(0.26, 0.19, 0.12), false)])
	else:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 3.3
		cm.height = 10.0
		cm.radial_segments = 7
		cm.rings = 1
		parts.append([cm, Transform3D(Basis.IDENTITY, Vector3(0, 8.0, 0)), _dmat(Color(0.14, 0.3, 0.17), 3, 0.1)])
		# a second, lower skirt gives the conifer a fuller, layered silhouette
		var skirt := CylinderMesh.new()
		skirt.top_radius = 1.5
		skirt.bottom_radius = 3.9
		skirt.height = 4.6
		skirt.radial_segments = 7
		skirt.rings = 1
		parts.append([skirt, Transform3D(Basis.IDENTITY, Vector3(0, 4.6, 0)), _dmat(Color(0.12, 0.27, 0.15), 3, 0.1)])
	# ragged bushy silhouette: a ring of small leafy lobes round the crown
	if round_tree:
		_bushy(parts, Vector3(0, 6.6, 0), 3.0, 5, Color(0.24, 0.36, 0.15), 11)
	else:
		_bushy(parts, Vector3(0, 6.4, 0), 2.8, 5, Color(0.15, 0.31, 0.18), 12)
	var m: ArrayMesh = _merge(parts)
	_meshes[key] = m
	return m


const TREE_CONES: Array = [0, 0, 2, 6]
const TREE_ROUNDS: Array = [1, 1, 3, 4, 5, 7]
const TREE_VARIANTS: int = 8


## Assign each tree a species. Woods are stands: most trees in a ~110 m patch share one species, with a
## scattering of others, so woodland reads as mixed forest with coherent patches of colour. Pure function of position.
static func _split_trees(cones: Array, rounds: Array) -> Array:
	var out: Array = []
	for i in TREE_VARIANTS:
		out.append([])
	for t in cones:
		var o: Vector3 = (t as Transform3D).origin
		var stand: int = absi(hash(Vector2i(floori(o.x / 110.0), floori(o.z / 110.0))))
		var own: int = absi(hash(Vector2i(floori(o.x * 3.0), floori(o.z * 3.0))))
		var k: int = stand if own % 10 < 7 else own
		(out[TREE_CONES[k % TREE_CONES.size()]] as Array).append(t)
	for t2 in rounds:
		var o2: Vector3 = (t2 as Transform3D).origin
		var stand2: int = absi(hash(Vector2i(floori(o2.x / 90.0) + 7, floori(o2.z / 90.0) - 3)))
		var own2: int = absi(hash(Vector2i(floori(o2.x * 3.0), floori(o2.z * 3.0))))
		var k2: int = stand2 if own2 % 10 < 7 else own2
		(out[TREE_ROUNDS[k2 % TREE_ROUNDS.size()]] as Array).append(t2)
	return out


## Tree species meshes: 0 spruce, 1 oak, 2 poplar, 3 birch, 4 broad oak, 5 beech, 6 scots pine, 7 lime / willow.
## Every crown stays a shade of green / olive: no copper-red species, so no tree ever reads as a red blob
## against the fields from the air. Birch and lime / willow (which turn early) carry only a faint autumn khaki.
## Tree crowns keep close to one green whatever the species (birch yellows and poplar limes pulled most of the way in),
## so woods and tree lines read as one consistent colour, near and far.
const TREE_GREEN: Color = Color(0.19, 0.31, 0.15)


static func _calm(c: Color) -> Color:
	return c.lerp(TREE_GREEN, 0.65)


static func tree_variant(v: int) -> ArrayMesh:
	var key: String = "tree_v%d" % v
	if _meshes.has(key):
		return _meshes[key]
	if v == 0:
		_meshes[key] = tree_mesh(false)
		return _meshes[key]
	if v == 1:
		_meshes[key] = tree_mesh(true)
		return _meshes[key]
	var trunk_col := Color(0.28, 0.2, 0.13)
	var trunk_h: float = 4.0
	var parts: Array = []
	var crown: Array = []     # [mesh, offset, colour]
	match v:
		2:   # poplar: tall, narrow flame
			trunk_h = 3.0
			var pc := CylinderMesh.new()
			pc.top_radius = 0.0
			pc.bottom_radius = 1.9
			pc.height = 15.0
			pc.radial_segments = 6
			pc.rings = 1
			crown.append([pc, Vector3(0, 10.5, 0), Color(0.20, 0.34, 0.13)])
			var pc2 := CylinderMesh.new()
			pc2.top_radius = 1.1
			pc2.bottom_radius = 2.3
			pc2.height = 5.0
			pc2.radial_segments = 6
			pc2.rings = 1
			crown.append([pc2, Vector3(0, 5.6, 0), Color(0.17, 0.30, 0.12)])
		3:   # silver birch: small airy crown on a pale trunk
			trunk_col = Color(0.84, 0.83, 0.77)
			trunk_h = 5.0
			var bs := SphereMesh.new()
			bs.radius = 2.5
			bs.height = 5.4
			bs.radial_segments = 6
			bs.rings = 3
			crown.append([bs, Vector3(0, 6.6, 0), Color(0.36, 0.44, 0.20)])
			crown.append([bs, Vector3(1.1, 8.3, 0.4), Color(0.41, 0.48, 0.22)])
		4:   # broad oak: heavy mid-green crown
			var ao := SphereMesh.new()
			ao.radius = 3.7
			ao.height = 6.2
			ao.radial_segments = 7
			ao.rings = 4
			crown.append([ao, Vector3(0, 6.6, 0), Color(0.26, 0.38, 0.16)])
			crown.append([ao, Vector3(-1.8, 7.8, 1.0), Color(0.20, 0.32, 0.13)])
		5:   # beech: heavy, dark green crown
			var cb := SphereMesh.new()
			cb.radius = 3.9
			cb.height = 6.8
			cb.radial_segments = 7
			cb.rings = 4
			crown.append([cb, Vector3(0, 6.9, 0), Color(0.18, 0.30, 0.16)])
			var cbl := SphereMesh.new()
			cbl.radius = 2.4
			cbl.height = 3.8
			cbl.radial_segments = 6
			cbl.rings = 3
			crown.append([cbl, Vector3(2.0, 5.9, 0.9), Color(0.15, 0.26, 0.14)])
			crown.append([cbl, Vector3(-1.9, 8.0, -0.8), Color(0.21, 0.34, 0.18)])
		6:   # scots pine: bare trunk, flat blue-green canopy plates
			trunk_col = Color(0.46, 0.27, 0.16)
			trunk_h = 8.0
			var pl := SphereMesh.new()
			pl.radius = 3.4
			pl.height = 2.6
			pl.radial_segments = 7
			pl.rings = 2
			crown.append([pl, Vector3(0, 9.0, 0), Color(0.15, 0.31, 0.20)])
			crown.append([pl, Vector3(1.6, 11.0, -0.8), Color(0.18, 0.34, 0.22)])
			var pl2 := SphereMesh.new()
			pl2.radius = 2.4
			pl2.height = 1.9
			pl2.radial_segments = 6
			pl2.rings = 2
			crown.append([pl2, Vector3(-1.7, 7.4, 0.9), Color(0.13, 0.27, 0.18)])
		_:   # lime / willow: wide, soft, yellow-green, with a faint autumn khaki (these turn early)
			var li := SphereMesh.new()
			li.radius = 4.1
			li.height = 5.4
			li.radial_segments = 7
			li.rings = 3
			crown.append([li, Vector3(0, 6.2, 0), Color(0.42, 0.46, 0.20)])
			crown.append([li, Vector3(2.0, 5.4, 1.2), Color(0.38, 0.42, 0.17)])
			var li2 := SphereMesh.new()
			li2.radius = 2.6
			li2.height = 3.6
			li2.radial_segments = 6
			li2.rings = 3
			crown.append([li2, Vector3(-2.1, 7.0, -1.0), Color(0.45, 0.49, 0.22)])
	var trk := CylinderMesh.new()
	trk.top_radius = 0.35
	trk.bottom_radius = 0.6
	trk.height = trunk_h
	trk.radial_segments = 5
	trk.rings = 1
	parts.append([trk, Transform3D(Basis.IDENTITY, Vector3(0, trunk_h * 0.5, 0)), GroundKit.mat(trunk_col, false)])
	for c in crown:
		parts.append([c[0], Transform3D(Basis.IDENTITY, c[1]), _dmat(_calm(c[2]), 3, 0.1)])
	# ragged bushy silhouette: a ring of small leafy lobes round the main crown mass
	if not crown.is_empty():
		var main_mesh: Mesh = crown[0][0]
		var ctr: Vector3 = crown[0][1]
		var rad: float = 2.6
		if main_mesh is SphereMesh:
			rad = (main_mesh as SphereMesh).radius
		elif main_mesh is CylinderMesh:
			rad = (main_mesh as CylinderMesh).bottom_radius * 0.8
		_bushy(parts, ctr, rad, 5, _calm(crown[0][2]), 31 + v)
	var m: ArrayMesh = _merge(parts)
	_meshes[key] = m
	return m


static func cow_mesh() -> ArrayMesh:
	if _meshes.has("cow"):
		return _meshes["cow"]
	var bm := BoxMesh.new()
	bm.size = Vector3(1.4, 1.5, 3.0)
	var hd := BoxMesh.new()
	hd.size = Vector3(0.9, 0.9, 1.0)
	var lg := BoxMesh.new()
	lg.size = Vector3(0.3, 1.0, 0.3)
	var white: ShaderMaterial = GroundKit.mat(Color(0.88, 0.85, 0.8), false)
	var dark: ShaderMaterial = GroundKit.mat(Color(0.25, 0.18, 0.14), false)
	var parts: Array = [[bm, Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0)), white], [hd, Transform3D(Basis.IDENTITY, Vector3(0, 1.8, -1.9)), dark]]
	for sx in [-0.45, 0.45]:
		for sz in [-1.0, 1.0]:
			parts.append([lg, Transform3D(Basis.IDENTITY, Vector3(sx, 0.5, sz)), dark])
	var m: ArrayMesh = _merge(parts)
	_meshes["cow"] = m
	return m


static func hedgehog_mesh() -> ArrayMesh:
	if _meshes.has("hedgehog"):
		return _meshes["hedgehog"]
	var bm := BoxMesh.new()
	bm.size = Vector3(0.45, 0.45, 5.0)
	var mt: ShaderMaterial = GroundKit.mat(Color(0.2, 0.2, 0.22), false)
	var parts: Array = []
	for r in [Vector3(0, 0, 0), Vector3(90, 0, 0), Vector3(0, 90, 45)]:
		var rv: Vector3 = r
		parts.append([bm, Transform3D(Basis.from_euler(Vector3(deg_to_rad(rv.x), deg_to_rad(rv.y), deg_to_rad(rv.z))), Vector3(0, 2.0, 0)), mt])
	var m: ArrayMesh = _merge(parts)
	_meshes["hedgehog"] = m
	return m


## Concrete "dragon's teeth" anti-tank pyramid.
static func tooth_mesh() -> ArrayMesh:
	if _meshes.has("tooth"):
		return _meshes["tooth"]
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 1.5
	cm.height = 1.7
	cm.radial_segments = 4
	cm.rings = 1
	var m: ArrayMesh = GroundKit.combine([[cm, Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 0.85, 0)), GroundKit.mat(Color(0.56, 0.56, 0.53), true, 0.04)]])
	_meshes["tooth"] = m
	return m


## Czech-hedgehog / beach-pole obstacle strip helper (Rommel's asparagus: tall poles).
static func pole_mesh() -> ArrayMesh:
	if _meshes.has("pole"):
		return _meshes["pole"]
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.18
	cm.height = 5.0
	cm.radial_segments = 5
	cm.rings = 1
	var m: ArrayMesh = GroundKit.combine([[cm, Transform3D(Basis.IDENTITY, Vector3(0, 2.5, 0)), GroundKit.mat(Color(0.32, 0.23, 0.14), false)]])
	_meshes["pole"] = m
	return m


static func nissen_mesh() -> ArrayMesh:
	if _meshes.has("nissen"):
		return _meshes["nissen"]
	var cm := CylinderMesh.new()
	cm.top_radius = 3.0
	cm.bottom_radius = 3.0
	cm.height = 11.0
	cm.radial_segments = 12
	cm.rings = 1
	var t := Transform3D(Basis.from_euler(Vector3(deg_to_rad(90.0), 0, 0)), Vector3(0, 1.3, 0))
	var m: ArrayMesh = GroundKit.combine([[cm, t, GroundKit.mat(Color(0.43, 0.45, 0.34), true, 0.05)]])
	_meshes["nissen"] = m
	return m


static func box_unit(color: Color, outline: bool = false) -> ArrayMesh:
	var key: String = "unit_%s_%s" % [color.to_html(false), str(outline)]
	if _meshes.has(key):
		return _meshes[key]
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	var m: ArrayMesh = GroundKit.combine([[bm, Transform3D.IDENTITY, GroundKit.mat(color, outline, 0.05)]])
	_meshes[key] = m
	return m


## Bushy hedge segment: a row of overlapping leafy clumps filling the unit box, so a hedge reads as a
## ragged leafy mass instead of a flat slab. The tile builder scales this along the hedge line.
static func hedge_mesh() -> ArrayMesh:
	if _meshes.has("hedge"):
		return _meshes["hedge"]
	var parts: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260508
	var base: Color = Color(0.25, 0.34, 0.18)
	var n: int = 9
	for i in n:
		var t: float = (float(i) + 0.5) / float(n)
		var r: float = rng.randf_range(0.34, 0.50)
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 1.9
		sm.radial_segments = 6
		sm.rings = 3
		var off: Vector3 = Vector3(t - 0.5, rng.randf_range(-0.06, 0.06), rng.randf_range(-0.16, 0.16))
		parts.append([sm, Transform3D(Basis.IDENTITY, off), _dmat(base * rng.randf_range(0.84, 1.16), 3, 0.0, false)])
	var m: ArrayMesh = _merge(parts)
	_meshes["hedge"] = m
	return m


## Adds a ring of small leafy lobes around a crown mass, so a tree has a ragged bushy silhouette.
static func _bushy(parts: Array, center: Vector3, radius: float, count: int, col: Color, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for i in count:
		var a: float = TAU * float(i) / float(count) + rng.randf_range(-0.35, 0.35)
		var r: float = radius * rng.randf_range(0.42, 0.70)
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 1.8
		sm.radial_segments = 5
		sm.rings = 3
		var off: Vector3 = center + Vector3(cos(a) * radius * 0.78, rng.randf_range(-0.45, 0.45) * radius, sin(a) * radius * 0.78)
		parts.append([sm, Transform3D(Basis.IDENTITY, off), _dmat(col * rng.randf_range(0.84, 1.14), 3, 0.1)])


static func multi(mesh: Mesh, xforms: Array, vis_end: float = 0.0) -> MultiMeshInstance3D:
	# The node is re-centred on its instances with a tight AABB, so the engine can frustum-cull it per
	# tile/site and distance-fade it (visibility_range uses the AABB centre, hence the re-centring).
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var lo := Vector3(1.0e9, 1.0e9, 1.0e9)
	var hi := Vector3(-1.0e9, -1.0e9, -1.0e9)
	for t in xforms:
		var o: Vector3 = (t as Transform3D).origin
		lo = lo.min(o)
		hi = hi.max(o)
	var c: Vector3 = (lo + hi) * 0.5 if not xforms.is_empty() else Vector3.ZERO
	mm.instance_count = xforms.size()
	mm.visible_instance_count = mm.instance_count
	for i in xforms.size():
		var t2: Transform3D = xforms[i]
		t2.origin -= c
		mm.set_instance_transform(i, t2)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.position = c
	var pad := Vector3(60.0, 60.0, 60.0)
	mi.custom_aabb = AABB(lo - c - pad, (hi - lo) + pad * 2.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Obstacles.register(mi)
	if vis_end > 0.0:
		vis_end *= vis_scale
		mi.visibility_range_end = vis_end
		mi.visibility_range_end_margin = minf(vis_end * 0.12, 900.0)
		# no FADE_SELF: a fading object is drawn in the transparent pass, after the clouds, so woods and houses
		# showed through cloud decks. Plain range cut-off instead (the margin keeps it from flickering).
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	return mi


static func _xf(pos: Vector3, yaw: float, scale_v: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(scale_v), pos)


static func _land(x: float, z: float, min_h: float = 1.5) -> bool:
	return GroundKit.raw_y(x, z) >= min_h and not RoadMesh.near_rail(Vector2(x, z)) and not RoadMesh.near_road(Vector2(x, z), 6.0) and not RiverMesh.near_river(Vector2(x, z))


# ------------------------------------------------------------------ towns
## Layout data for one town (reads RoadMesh/RiverMesh/GroundKit, builds no nodes). Returns:
##   "houses": Array of 10 transform arrays (one per house_mesh variant),
##   "civic": Array of {"kind","pos","yaw","scale"} for market square / town hall / station / quay,
##   "church": Dictionary or null, "smokes": Array[Vector3], "stats": Dictionary.
## Terraces follow the real street network (RoadMesh.routes_in_rect) when road data covers the town; in
## synthetic-fallback areas it falls back to the legacy jittered grid. Districts by distance from centre (2.2).
static func town_layout(center: Vector3, size: int, seed_v: int, church: bool = true) -> Dictionary:
	# the town's own road index for the exact keep-off-the-roads test (unless a tile job already made one)
	var own_block: bool = not RoadMesh.has_block()
	if own_block:
		var rr: float = 90.0 + float(size) * 85.0 + 120.0
		RoadMesh.prepare_block(Vector2(center.x - rr, center.z - rr), rr * 2.0)
	var out: Dictionary = _town_layout(center, size, seed_v, church)
	if own_block:
		RoadMesh.clear_block()
	return out


static func _town_layout(center: Vector3, size: int, seed_v: int, church: bool = true) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var radius: float = 90.0 + float(size) * 85.0
	var cen := Vector2(center.x, center.z)
	var lists: Array = []
	for i in 10:
		lists.append([])
	var civic: Array = []
	var ct: Dictionary = {"houses": 0, "longest": 0, "core": 0, "suburban": 0, "industrial": 0}
	# Waterfront: nearest river/coast within the town disc (2.3 - face the water, thin to a quay edge).
	var water: Dictionary = _town_water(center, radius)
	var rblk: Dictionary = _river_block(water["river_pts"] as Array)
	var wdir: Vector2 = water["dir"]
	var wedge: float = float(water["edge"])
	# Streets inside the town radius (real road polylines; empty in synthetic-fallback areas).
	var streets: Array = RoadMesh.routes_in_rect(cen, radius)
	var pitch: float = clampf(11.0 + rng.randf_range(-1.0, 1.0), 9.0, 13.5)
	if not streets.is_empty():
		# 2.1 street-driven: terraces run ALONG each street away from junctions / street ends.
		var jhash: Dictionary = {}
		for si in range(streets.size()):
			var jpts: PackedVector2Array = streets[si]["pts"]
			for jp in jpts:
				var key := Vector2i(floori(jp.x / 36.0), floori(jp.y / 36.0))
				var arr: Array = jhash.get(key, [])
				if not arr.has(si):
					arr.append(si)
					jhash[key] = arr
		var ctx: Dictionary = {"lists": lists, "rng": rng, "size": size, "radius": radius, "cen": cen,
			"wdir": wdir, "wedge": wedge, "rblk": rblk, "ct": ct, "pitch": pitch}
		var step: float = pitch
		for si2 in range(streets.size()):
			var pts: PackedVector2Array = streets[si2]["pts"]
			ctx["half"] = float(RoadMesh.WIDTHS.get(String(streets[si2]["k"]), 8.0)) * 0.75
			var run_p: int = 0
			var run_m: int = 0
			for i in range(pts.size() - 1):
				var aa: Vector2 = pts[i]
				var bb: Vector2 = pts[i + 1]
				var seg_len: float = aa.distance_to(bb)
				if seg_len < 0.5 or (aa.distance_to(cen) > radius * 1.25 + 40.0 and bb.distance_to(cen) > radius * 1.25 + 40.0):
					ct["longest"] = maxi(int(ct["longest"]), maxi(run_p, run_m))
					run_p = 0
					run_m = 0
					continue
				var dv: Vector2 = (bb - aa) / seg_len
				var nseg: int = maxi(int(round(seg_len / step)), 1)
				for k in range(nseg):
					var p: Vector2 = aa.lerp(bb, float(k) / float(nseg))
					if p.distance_to(cen) <= radius * _edge_k(p.x, p.y) and not _near_junction(p, si2, jhash):
						run_p = _lay_side(ctx, p, dv, 1.0, run_p)
						run_m = _lay_side(ctx, p, dv, -1.0, run_m)
					else:
						ct["longest"] = maxi(int(ct["longest"]), maxi(run_p, run_m))
						run_p = 0
						run_m = 0
			ct["longest"] = maxi(int(ct["longest"]), maxi(run_p, run_m))
	else:
		# Fallback (synthetic-fallback areas): the legacy jittered rectilinear grid, one yaw for the town.
		var grid_yaw: float = rng.randf() * PI
		var ca: float = cos(grid_yaw)
		var sa: float = sin(grid_yaw)
		var row_gap: float = pitch * rng.randf_range(1.05, 1.25)
		var block: int = rng.randi_range(3, 5)
		var rows: int = int(ceil(radius * 1.25 / row_gap))
		var cols: int = int(ceil(radius * 1.25 / pitch))
		for iz in range(-rows, rows + 1):
			if posmod(iz, block + 1) == 0:
				continue
			var z: float = float(iz) * row_gap
			var run: int = 0
			for ix in range(-cols, cols + 1):
				if posmod(ix, block + 1) == 0:
					run = 0
					continue
				var x: float = float(ix) * pitch
				var lx: float = x + rng.randf_range(-0.9, 0.9)
				var lz: float = z + rng.randf_range(-0.9, 0.9)
				var wx0: float = center.x + lx * ca - lz * sa
				var wz0: float = center.z + lx * sa + lz * ca
				var r_eff: float = radius * _edge_k(wx0, wz0)
				if lx * lx + lz * lz > r_eff * r_eff:
					run = 0
					continue
				var wp: Vector3 = center + Vector3(lx * ca - lz * sa, 0.0, lx * sa + lz * ca)
				if not _land(wp.x, wp.z, 1.2) or in_park(wp.x, wp.z) or _on_block_lc(wp.x, wp.z, rblk):
					run = 0
					continue
				var d: float = Vector2(wp.x - center.x, wp.z - center.z).length()
				var core: float = clampf(1.0 - d / radius, 0.0, 1.0)
				var p: float = 0.95 if run > 0 else 0.18 + 0.70 * core
				if rng.randf() > p:
					run = 0
					continue
				run += 1
				ct["longest"] = maxi(int(ct["longest"]), run)
				var band: int = _band_for(d, radius, size)
				var w: float = pitch
				var dep: float = rng.randf_range(6.5, 9.5)
				var h: float = 5.4 + rng.randf_range(0.0, 2.4) + core * float(size) * rng.randf_range(0.4, 1.6)
				var y: float = GroundKit.ground_y(wp.x, wp.z) + h * 0.5 - 0.4
				var vi: int
				if posmod(ix + 1, block + 1) == 0 and rng.randf() < 0.5:
					vi = 4
				elif rng.randf() < 0.10:
					vi = rng.randi_range(2, 3)
				else:
					vi = rng.randi() % 2
				(lists[vi % 8] as Array).append(_xf(Vector3(wp.x, y, wp.z), grid_yaw, Vector3(w, h, dep)))
				ct["houses"] = int(ct["houses"]) + 1
				if band == 0:
					ct["core"] = int(ct["core"]) + 1
				elif band == 2:
					ct["suburban"] = int(ct["suburban"]) + 1
				elif band == 3:
					ct["industrial"] = int(ct["industrial"]) + 1
	# 2.1c Ribbon plots just beyond the built-up edge: cottages along the lanes outside the town radius,
	# so the centre frays into the countryside instead of stopping on a clean circle.
	if not streets.is_empty():
		var fringe_n: int = 12 + size * 6
		for f in range(fringe_n):
			var rd: Dictionary = streets[rng.randi_range(0, streets.size() - 1)]
			var rpts: PackedVector2Array = rd["pts"]
			if rpts.size() < 2:
				continue
			var ri: int = rng.randi_range(0, rpts.size() - 2)
			var ra: Vector2 = rpts[ri]
			var rb: Vector2 = rpts[ri + 1]
			var rv: Vector2 = rb - ra
			var rl: float = rv.length()
			if rl < 1.0:
				continue
			var rdir: Vector2 = rv / rl
			var rp: Vector2 = ra.lerp(rb, rng.randf_range(0.35, 1.0))
			var rdst: float = rp.distance_to(cen)
			if rdst < radius * 0.90 or rdst > radius * 1.60:
				continue
			var rside: float = 1.0 if rng.randf() < 0.5 else -1.0
			var hp: Vector2 = rp + Vector2(-rdir.y, rdir.x) * rside * rng.randf_range(11.0, 20.0)
			if not _land(hp.x, hp.y, 1.4) or in_park(hp.x, hp.y) or _on_block_lc(hp.x, hp.y, rblk) or RoadMesh.near_road(hp, 4.0):
				continue
			var hv: int = 2 if rng.randf() < 0.55 else (3 if rng.randf() < 0.70 else 5)
			var hh: float = 5.2 + rng.randf_range(0.0, 1.8)
			var hy: float = GroundKit.ground_y(hp.x, hp.y) + hh * 0.5 - 0.4
			var hyaw: float = atan2(-rdir.y, rdir.x) + (0.0 if rside > 0.0 else PI) + rng.randf_range(-0.18, 0.18)
			(lists[hv] as Array).append(_xf(Vector3(hp.x, hy, hp.y), hyaw, Vector3(pitch * 1.1, hh, rng.randf_range(6.0, 8.0))))
			ct["houses"] = int(ct["houses"]) + 1
			ct["suburban"] = int(ct["suburban"]) + 1
	else:
		# No road data (synthetic-fallback towns): a ragged ring of outlying cottages and smallholdings
		# beyond the grid, so the built-up edge does not end on a clean circle.
		var fringe_n: int = 10 + size * 4
		for f in range(fringe_n):
			var fa: float = rng.randf() * TAU
			var fr: float = radius * rng.randf_range(0.98, 1.55)
			var hp := Vector2(cen.x + cos(fa) * fr, cen.y + sin(fa) * fr)
			if not _land(hp.x, hp.y, 1.4) or in_park(hp.x, hp.y) or _on_block_lc(hp.x, hp.y, rblk) or RoadMesh.near_road(hp, 4.0):
				continue
			var hv: int = 2 if rng.randf() < 0.55 else (3 if rng.randf() < 0.70 else 5)
			var hh: float = 5.2 + rng.randf_range(0.0, 1.8)
			var hy: float = GroundKit.ground_y(hp.x, hp.y) + hh * 0.5 - 0.4
			var hyaw: float = fa + PI * 0.5 + rng.randf_range(-0.8, 0.8)
			(lists[hv] as Array).append(_xf(Vector3(hp.x, hy, hp.y), hyaw, Vector3(pitch * 1.1, hh, rng.randf_range(6.0, 8.0))))
			ct["houses"] = int(ct["houses"]) + 1
			ct["suburban"] = int(ct["suburban"]) + 1
	# 2.1b The nearest rail to the town: used by the station, the goods yard and the gasworks (any size).
	var rails: Array = TransportNetwork.routes_near("rails", center, radius * 1.8)
	var best_r: RoutePath = null
	var best_s: float = 0.0
	var best_d: float = 1.0e12
	for r in rails:
		var cl: Vector2 = (r as RoutePath).closest(center)
		if cl.y < best_d:
			best_d = cl.y
			best_r = r
			best_s = cl.x
	# 2.2 civic core for the larger towns (size >= 3): market square, town hall, railway station.
	if size >= 3:
		var ma: float = rng.randf() * TAU
		var mr: float = rng.randf_range(0.08, 0.20) * radius
		var mp := Vector3(center.x + cos(ma) * mr, 0.0, center.z + sin(ma) * mr)
		if _land(mp.x, mp.z, 1.5) and not _on_block_lc(mp.x, mp.z, rblk):
			mp.y = GroundKit.ground_y(mp.x, mp.z)
			civic.append({"kind": "market", "pos": mp, "yaw": rng.randf() * TAU, "scale": 1.0})
		var ta: float = ma + rng.randf_range(1.6, 2.6)
		var tr: float = rng.randf_range(0.10, 0.24) * radius
		var tp := Vector3(center.x + cos(ta) * tr, 0.0, center.z + sin(ta) * tr)
		if _land(tp.x, tp.z, 1.5) and not _on_block_lc(tp.x, tp.z, rblk):
			tp.y = GroundKit.ground_y(tp.x, tp.z)
			var tyaw: float = rng.randf() * TAU
			if wdir != Vector2.ZERO:
				tyaw = atan2(-wdir.x, -wdir.y)          # face the water when the town is on it
			civic.append({"kind": "townhall", "pos": tp, "yaw": tyaw, "scale": rng.randf_range(0.9, 1.15)})
		# railway station snapped to the nearest rail (TransportNetwork.routes_near("rails", ...))
		if best_r != null:
			var sp: Vector3 = best_r.sample(best_s)
			var sdir: Vector3 = best_r.tangent(best_s)
			var perp := Vector2(-sdir.z, sdir.x)
			var so: float = 24.0
			var bp := Vector2(sp.x + perp.x * so, sp.z + perp.y * so)
			if GroundKit.raw_y(bp.x, bp.y) >= 1.2 and _land(bp.x, bp.y, 1.5):
				civic.append({"kind": "station", "pos": Vector3(bp.x, GroundKit.ground_y(bp.x, bp.y), bp.y), "yaw": atan2(-sdir.z, sdir.x), "scale": 1.0})
	# 2.2b Rail-linked town texture (all sizes): a goods yard and a town gasworks where a line meets the town.
	if best_r != null:
		var rsp: Vector3 = best_r.sample(best_s)
		var rdir: Vector3 = best_r.tangent(best_s)
		var rperp := Vector2(-rdir.z, rdir.x)
		var ryaw: float = atan2(-rdir.z, rdir.x)          # local -Z along the rail (the station convention)
		var yq := Vector2(rsp.x - rperp.x * 48.0, rsp.z - rperp.y * 48.0)
		if GroundKit.raw_y(yq.x, yq.y) >= 1.2 and _land(yq.x, yq.y, 1.5) and not _on_block_lc(yq.x, yq.y, rblk):
			civic.append({"kind": "railyard", "pos": Vector3(yq.x, GroundKit.ground_y(yq.x, yq.y), yq.y), "yaw": ryaw, "scale": 1.0})
		var gsp: Vector3 = best_r.sample(best_s + 240.0)
		var gq := Vector2(gsp.x + rperp.x * 30.0, gsp.z + rperp.y * 30.0)
		if GroundKit.raw_y(gq.x, gq.y) >= 1.2 and _land(gq.x, gq.y, 1.5) and gq.distance_to(cen) < radius * 1.25 and not _on_block_lc(gq.x, gq.y, rblk):
			civic.append({"kind": "gasworks", "pos": Vector3(gq.x, GroundKit.ground_y(gq.x, gq.y), gq.y), "yaw": ryaw, "scale": 1.0})
	# 2.2c a church tower / spire in the civic core of the larger towns, so the skyline reads from the air.
	if size >= 3:
		var cha: float = rng.randf() * TAU
		var chr: float = rng.randf_range(0.04, 0.12) * radius
		var chp := Vector2(center.x + cos(cha) * chr, center.z + sin(cha) * chr)
		if GroundKit.raw_y(chp.x, chp.y) >= 1.2 and _land(chp.x, chp.y, 1.5) and not _on_block_lc(chp.x, chp.y, rblk):
			civic.append({"kind": "spire", "pos": Vector3(chp.x, GroundKit.ground_y(chp.x, chp.y), chp.y), "yaw": rng.randf() * TAU, "scale": rng.randf_range(1.0, 1.4)})
	# 2.3 waterfront: a quay edge along the water side (the nearest rows are thinned/fronted in _lay_side).
	if wdir != Vector2.ZERO and wedge > 0.0:
		var wside := Vector2(-wdir.y, wdir.x)
		var qbase := Vector2(center.x + wdir.x * (wedge - 18.0), center.z + wdir.y * (wedge - 18.0))
		for qi in range(-1, 2):
			var qp: Vector2 = qbase + wside * (float(qi) * 46.0)
			if GroundKit.raw_y(qp.x, qp.y) >= 1.0:
				civic.append({"kind": "quay", "pos": Vector3(qp.x, GroundKit.ground_y(qp.x, qp.y), qp.y), "yaw": atan2(-wside.y, wside.x), "scale": 1.0})
	# white chimney smoke over a scattering of the town's houses
	var smokes: Array = []
	for i in range(10):
		for t3 in (lists[i] as Array):
			if smokes.size() >= 16:
				break
			if rng.randf() < 0.045:
				var tb: Transform3D = t3
				smokes.append(tb.origin + Vector3(0.0, tb.basis.get_scale().y * 0.5 + 1.2, 0.0))
	var church_d: Variant = null
	if church:
		var cp2: Vector3 = center + Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20))
		if _land(cp2.x, cp2.z, 1.2):
			church_d = {"pos": Vector3(cp2.x, GroundKit.ground_y(cp2.x, cp2.z), cp2.z), "yaw": rng.randf() * TAU, "scale": rng.randf_range(0.9, 1.4)}
	var stats: Dictionary = {"streets": streets.size(), "houses": int(ct["houses"]), "longest_run": int(ct["longest"]),
		"core": int(ct["core"]), "suburban": int(ct["suburban"]), "industrial": int(ct["industrial"]),
		"civic": civic.size(), "waterfront": wdir != Vector2.ZERO}
	return {"houses": lists, "civic": civic, "church": church_d, "smokes": smokes, "stats": stats}


## Stats for --city-test without building any nodes.
static func town_stats(center: Vector3, size: int, seed_v: int) -> Dictionary:
	return town_layout(center, size, seed_v, true)["stats"]


## Build one town: terraces from town_layout(), plus the civic core (2.2) and the church.
static func make_town(center: Vector3, size: int, seed_v: int, church: bool = true) -> Node3D:
	return make_town_from(center, town_layout(center, size, seed_v, church))


## The town's nodes from a town_layout() (which can be worked out on a worker thread).
static func make_town_from(center: Vector3, d: Dictionary) -> Node3D:
	var root := Node3D.new()
	var lists: Array = (d["houses"] as Array).duplicate(true)
	var town_ruins: Array = [[], []]
	var t_areas: Array = WarDamage.areas_near(Vector2(center.x, center.z) - Vector2(3000.0, 3000.0), 6000.0)
	WarDamage.apply_to_houses(lists, town_ruins, t_areas)
	for rv in 2:
		if not (town_ruins[rv] as Array).is_empty():
			root.add_child(multi(WarDamage.ruin_mesh(rv), town_ruins[rv], 11000.0))
	var smokes: Array = d["smokes"]
	if not smokes.is_empty():
		var cs := ChimneySmokes.new()
		for sp in smokes:
			cs.points.append(sp)
		cs.size = 1.5
		root.add_child(cs)
	for i in range(lists.size()):
		if (lists[i] as Array).is_empty():
			continue
		root.add_child(multi(house_mesh(i), lists[i], 11000.0))
	for c in d["civic"]:
		_build_civic(root, c as Dictionary)
	var ch_d: Variant = d["church"]
	if ch_d != null and WarDamage.level_in(t_areas, (ch_d as Dictionary)["pos"].x, (ch_d as Dictionary)["pos"].z) < 0.6:
		var cd: Dictionary = ch_d
		var ch: Node3D = Landmarks.church(float(cd["scale"]))
		ch.position = cd["pos"]
		ch.rotation.y = float(cd["yaw"])
		root.add_child(ch)
	return root


## Lay one terrace unit on the side (sgn) of a street point p with unit direction dir. Returns the new run length.
static func _lay_side(ctx: Dictionary, p: Vector2, dir: Vector2, sgn: float, run: int) -> int:
	var rng: RandomNumberGenerator = ctx["rng"]
	var size: int = int(ctx["size"])
	var radius: float = float(ctx["radius"])
	var cen: Vector2 = ctx["cen"]
	var lists: Array = ctx["lists"]
	var rblk: Dictionary = ctx["rblk"]
	var ct: Dictionary = ctx["ct"]
	var depth: float = rng.randf_range(6.6, 9.0)
	# set back behind this street's drawn width (carriageway and verge / pavement), not onto it
	var off: float = depth * 0.5 + float(ctx.get("half", 4.5)) + rng.randf_range(0.6, 1.8)
	var nrm := Vector2(-dir.y, dir.x) * sgn
	var hp: Vector2 = p + nrm * off + dir * rng.randf_range(-0.45, 0.45)
	if not _land(hp.x, hp.y, 1.2) or in_park(hp.x, hp.y) or _on_block_lc(hp.x, hp.y, rblk) or RoadMesh.near_road(hp, depth * 0.5):
		ct["longest"] = maxi(int(ct["longest"]), run)
		return 0
	var dcen: float = hp.distance_to(cen)
	var band: int = _band_for(dcen, radius, size)
	var wdir: Vector2 = ctx["wdir"]
	var waterside: bool = false
	if wdir != Vector2.ZERO:
		var front: float = (hp - cen).dot(wdir)
		var dw: float = float(ctx["wedge"]) - front
		if dw < 5.0:                              # in the water / the quay cut - never build here
			ct["longest"] = maxi(int(ct["longest"]), run)
			return 0
		if dw < 55.0:
			waterside = true
			if rng.randf() > 0.45:               # thin the nearest rows to a broken quay edge
				ct["longest"] = maxi(int(ct["longest"]), run)
				return 0
	var core: float = clampf(1.0 - dcen / radius, 0.0, 1.0)
	var pkeep: float = 0.95 if run > 0 else 0.42 + 0.55 * core
	if rng.randf() > pkeep:
		ct["longest"] = maxi(int(ct["longest"]), run)
		return 0
	var vi: int = _pick_variant(band, run == 0, rng, size)
	var h: float = 5.4 + rng.randf_range(0.0, 2.2)
	if band == 0:
		h += 2.4 + float(size) * 0.5
	elif band == 3:
		h += 0.6
	h += core * float(size) * rng.randf_range(0.3, 1.2)
	var yaw: float = atan2(-dir.y, dir.x) + (0.0 if sgn > 0.0 else PI) + rng.randf_range(-0.03, 0.03)
	if waterside:
		yaw = atan2(-wdir.x, -wdir.y)            # the nearest rows face the water
	var y: float = GroundKit.ground_y(hp.x, hp.y) + h * 0.5 - 0.4
	var w: float = float(ctx["pitch"]) * 1.16
	(lists[vi] as Array).append(_xf(Vector3(hp.x, y, hp.y), yaw, Vector3(w, h, depth)))
	ct["houses"] = int(ct["houses"]) + 1
	if band == 0:
		ct["core"] = int(ct["core"]) + 1
	elif band == 2:
		ct["suburban"] = int(ct["suburban"]) + 1
	elif band == 3:
		ct["industrial"] = int(ct["industrial"]) + 1
	run += 1
	if run > int(ct["longest"]):
		ct["longest"] = run
	return run


## District band by distance from the town centre and its size (2.2).
static func _band_for(d: float, radius: float, size: int) -> int:
	var f: float = d / maxf(radius, 1.0)
	if size >= 3 and f < 0.30:
		return 0                     # central commercial core
	if f < 0.62:
		return 1                     # inner terraces
	if f < 0.90:
		return 2                     # suburban semis / cottages
	return 3                         # industrial fringe


## Pick a house_mesh variant for a district band (0 core, 1 inner, 2 suburban, 3 industrial).
static func _pick_variant(band: int, at_junction: bool, rng: RandomNumberGenerator, size: int) -> int:
	match band:
		0:
			if at_junction and rng.randf() < 0.12 + 0.03 * float(size):
				return 8                                     # the odd cinema at a street corner
			var r0: float = rng.randf()
			if r0 < 0.34:
				return 4                                     # shopfront / corner block
			if r0 < 0.62:
				return 5                                     # taller villa block
			if r0 < 0.80:
				return 6                                     # warehouse / commercial
			return 0
		1:
			if at_junction and rng.randf() < 0.14:
				return 4
			return 0 if rng.randf() < 0.58 else 1
		2:
			var r2: float = rng.randf()
			if r2 < 0.42:
				return 2
			if r2 < 0.78:
				return 3
			return 5
		_:
			return 7 if rng.randf() < 0.55 else 6


## True when p sits within a street-vertex cluster of a *different* street (a junction / cross-street).
static func _near_junction(p: Vector2, si: int, jhash: Dictionary) -> bool:
	var cx: int = floori(p.x / 36.0)
	var cz: int = floori(p.y / 36.0)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var arr: Variant = jhash.get(Vector2i(cx + dx, cz + dz))
			if arr == null:
				continue
			for s in (arr as Array):
				if int(s) != si:
					return true
	return false


## Nearest water (river/canal or coast) around a town: {"dir": Vector2 toward it, "edge": distance, "river_pts": Array}.
static func _town_water(center: Vector3, radius: float) -> Dictionary:
	var cen := Vector2(center.x, center.z)
	var res: Dictionary = {"dir": Vector2.ZERO, "edge": -1.0, "river_pts": []}
	var best_d: float = radius * 1.4
	var best_dir := Vector2.ZERO
	for i in 32:
		var a: float = TAU * float(i) / 32.0
		var dd := Vector2(cos(a), sin(a))
		var rr: float = 20.0
		while rr <= radius * 1.4:
			if GroundKit.is_water(cen.x + dd.x * rr, cen.y + dd.y * rr):
				if rr < best_d:
					best_d = rr
					best_dir = dd
				break
			rr += 24.0
	if best_dir != Vector2.ZERO:
		res["dir"] = best_dir
		res["edge"] = best_d
	var rv: Array = []
	if RiverMesh.has_rivers():
		var lim: float = radius + 120.0
		var lim2: float = lim * lim
		for ln in RiverMesh.lines:
			var pts: PackedVector2Array = (ln as Dictionary)["pts"]
			for p in pts:
				if p.distance_squared_to(cen) <= lim2:
					rv.append(p)
	if not rv.is_empty():
		var rd: float = 1.0e12
		var rp: Vector2 = cen
		for p2 in rv:
			var d2: float = (p2 as Vector2).distance_squared_to(cen)
			if d2 < rd:
				rd = d2
				rp = p2 as Vector2
		rd = sqrt(rd)
		if rd < radius * 1.05 and (float(res["edge"]) < 0.0 or rd < float(res["edge"])):
			res["dir"] = (rp - cen).normalized()
			res["edge"] = rd
	res["river_pts"] = rv
	return res


## Coarse blocked-cell map (24 m) marking the river/canal corridor so no house is built in the channel.
static func _river_block(river_pts: Array) -> Dictionary:
	var blk: Dictionary = {}
	for p in river_pts:
		var q: Vector2 = p
		var cx: int = floori(q.x / 24.0)
		var cz: int = floori(q.y / 24.0)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				blk[Vector2i(cx + dx, cz + dz)] = true
	return blk


static func _on_block_lc(x: float, z: float, blk: Dictionary) -> bool:
	if blk.is_empty():
		return false
	return blk.has(Vector2i(floori(x / 24.0), floori(z / 24.0)))


## Civic buildings of the town core (2.2): market square, town hall, railway station, river quay.
static func _build_civic(root: Node3D, c: Dictionary) -> void:
	var kind: String = str(c["kind"])
	var sc: float = float(c.get("scale", 1.0))
	var holder := Node3D.new()
	holder.position = c["pos"]
	holder.rotation.y = float(c["yaw"])
	root.add_child(holder)
	match kind:
		"townhall":
			GroundKit.box(holder, Vector3(24, 13, 16) * sc, Vector3(0.0, 6.5 * sc, 0.0), Color(0.56, 0.52, 0.46))
			var rf := MeshInstance3D.new()
			rf.mesh = GroundKit.prism_mesh(25.0 * sc, 17.0 * sc, 4.0 * sc)
			rf.material_override = GroundKit.mat(Color(0.32, 0.30, 0.32))
			rf.position = Vector3(0.0, 13.0 * sc, 0.0)
			holder.add_child(rf)
			GroundKit.cyl(holder, 0.0, 3.2 * sc, 16.0 * sc, Vector3(0.0, 21.0 * sc, 0.0), Color(0.5, 0.48, 0.44), Vector3.ZERO, 4)
			GroundKit.box(holder, Vector3(3.4, 3.4, 3.4) * sc, Vector3(0.0, 29.0 * sc, 0.0), Color(0.30, 0.30, 0.34))
		"market":
			GroundKit.box(holder, Vector3(46, 0.5, 38) * sc, Vector3(0.0, 0.25 * sc, 0.0), Color(0.56, 0.54, 0.5), Vector3.ZERO, false)
			GroundKit.cyl(holder, 0.7, 1.0, 7.0 * sc, Vector3(0.0, 3.5 * sc, 0.0), Color(0.62, 0.58, 0.5), Vector3.ZERO, 6)
			for sx in [-1.0, 1.0]:
				GroundKit.box(holder, Vector3(12, 3.0, 5.0) * sc, Vector3(sx * 14.0 * sc, 1.5 * sc, 11.0 * sc), Color(0.7, 0.66, 0.58))
		"station":
			var mask := MeshInstance3D.new()
			mask.mesh = house_mesh(9)
			mask.scale = Vector3(42.0, 9.0, 13.0) * sc
			mask.position = Vector3(0.0, 4.5 * sc, 0.0)
			holder.add_child(mask)
			GroundKit.box(holder, Vector3(96.0, 0.6, 9.0) * sc, Vector3(0.0, 0.3 * sc, -16.0 * sc), Color(0.6, 0.58, 0.55), Vector3.ZERO, false)
		"quay":
			GroundKit.box(holder, Vector3(60.0, 2.2, 8.0), Vector3(0.0, 1.1, 0.0), Color(0.5, 0.5, 0.47), Vector3.ZERO, false)
		"gasworks":
			# A town gas works on the railway: a pair of gasholder drums in their guide frames, a retort house
			# and a tall works chimney (existing greys / soot brick and slate only).
			var drum: Color = Color(0.42, 0.44, 0.46)
			var gframe: Color = Color(0.30, 0.30, 0.32)
			var soot: Color = Color(0.35, 0.23, 0.18)
			for gi in 2:
				var gx: float = -26.0 + float(gi) * 52.0
				GroundKit.cyl(holder, 20.0, 20.0, 26.0, Vector3(gx, 13.0 * sc, 0.0), drum, Vector3.ZERO, 18)
				GroundKit.cyl(holder, 20.6, 20.6, 1.6, Vector3(gx, 26.4 * sc, 0.0), drum.darkened(0.12), Vector3.ZERO, 18, false)
				GroundKit.cyl(holder, 17.6, 17.6, 1.2, Vector3(gx, 27.6 * sc, 0.0), drum.lightened(0.08), Vector3.ZERO, 18, false)
				for fi in 8:
					var fa: float = TAU * float(fi) / 8.0
					GroundKit.box(holder, Vector3(0.8, 28.0, 0.8) * sc, Vector3(gx + sin(fa) * 20.6, 14.0 * sc, cos(fa) * 20.6), gframe, Vector3.ZERO, false)
			GroundKit.box(holder, Vector3(44.0, 12.0, 20.0) * sc, Vector3(0.0, 6.0 * sc, 30.0), soot)
			var grf := MeshInstance3D.new()
			grf.mesh = GroundKit.prism_mesh(21.0, 45.0, 4.0)
			grf.material_override = GroundKit.mat(Color(0.29, 0.30, 0.33), true)
			grf.position = Vector3(0.0, 12.0 * sc, 30.0)
			grf.rotation_degrees = Vector3(0.0, 90.0, 0.0)
			holder.add_child(grf)
			GroundKit.cyl(holder, 1.8, 2.6, 46.0, Vector3(-30.0, 23.0, 30.0), soot.darkened(0.15), Vector3.ZERO, 10)
		"railyard":
			# A goods yard: rail sidings on a ballast bed with covered and open wagons, a goods shed and a
			# coaling stage / water tank - the yard that sat where a line met the town.
			var railt: Color = Color(0.40, 0.38, 0.34)
			var ballast: Color = Color(0.34, 0.32, 0.29)
			var wagon: Color = Color(0.32, 0.28, 0.22)
			GroundKit.box(holder, Vector3(210.0, 0.3, 44.0), Vector3(0.0, 0.15, 0.0), ballast, Vector3.ZERO, false)
			for ti in 4:
				var tz: float = -15.0 + float(ti) * 10.0
				GroundKit.box(holder, Vector3(200.0, 0.3, 1.6), Vector3(0.0, 0.35, tz), railt, Vector3.ZERO, false)
				for wi in 3:
					var wx: float = -60.0 + float(wi) * 55.0 + float((ti + wi) % 2) * 14.0
					GroundKit.box(holder, Vector3(9.0, 3.0, 2.6), Vector3(wx, 2.2, tz), wagon, Vector3.ZERO, false)
					GroundKit.box(holder, Vector3(9.4, 0.4, 2.9), Vector3(wx, 3.9, tz), Color(0.20, 0.18, 0.16), Vector3.ZERO, false)
			var gshed := MeshInstance3D.new()
			gshed.mesh = house_mesh(6)
			gshed.scale = Vector3(64.0, 12.0, 22.0)
			gshed.position = Vector3(20.0, 6.0, 34.0)
			holder.add_child(gshed)
			GroundKit.box(holder, Vector3(12.0, 3.0, 8.0), Vector3(-70.0, 4.5, 30.0), Color(0.46, 0.28, 0.21))
			GroundKit.cyl(holder, 3.0, 3.0, 5.0, Vector3(-70.0, 9.0, 30.0), Color(0.30, 0.30, 0.32), Vector3.ZERO, 10, false)
		"spire":
			# A church tower and spire in the civic core (Landmarks.church), so the town centre reads from the air.
			holder.add_child(Landmarks.church(sc))


# ------------------------------------------------------------------ forests
static func make_forest(center: Vector3, radius: float, count: int, seed_v: int, poly: PackedVector2Array = PackedVector2Array()) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var cones: Array = []
	var rounds: Array = []
	var tries: int = 0
	while (cones.size() + rounds.size()) < count and tries < count * 3:
		tries += 1
		var a: float = rng.randf() * TAU
		var r: float = radius * sqrt(rng.randf())
		var p: Vector3 = center + Vector3(cos(a) * r, 0, sin(a) * r)
		if poly.size() > 2 and not Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), poly):
			continue
		if not _land(p.x, p.z, 1.5) or in_lake(p.x, p.z):
			continue
		var sc: float = rng.randf_range(1.8, 3.0)
		var t: Transform3D = _xf(Vector3(p.x, GroundKit.ground_y(p.x, p.z) - 0.3, p.z), rng.randf() * TAU, Vector3(sc, sc * rng.randf_range(0.9, 1.3), sc))
		if rng.randf() < 0.6:
			cones.append(t)
		else:
			rounds.append(t)
	var tsp0: Array = _split_trees(cones, rounds)
	for tv in tsp0.size():
		if not (tsp0[tv] as Array).is_empty():
			root.add_child(multi(tree_variant(tv), tsp0[tv], 11000.0))
	return root


# ------------------------------------------------------------------ countryside tile
## Farms, barns, windmills, hedgerows, cattle and tree clumps for one grid cell. exclude: [[Vector3, radius], ...]
static func make_tile(origin: Vector2, cell: float, seed_v: int, exclude: Array) -> Node3D:
	if LandCover.ready():
		return _make_tile_landcover(origin, cell, seed_v, exclude)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var root := Node3D.new()
	var probe: int = 0
	for k in 5:
		var q := Vector2(origin.x + cell * rng.randf(), origin.y + cell * rng.randf())
		if _land(q.x, q.y, 1.5):
			probe += 1
	if probe == 0:
		return root
	var houses: Array = [[], [], [], []]
	var hedges: Array = []
	var cows: Array = []
	var trees_c: Array = []
	var trees_r: Array = []
	var side: String = GroundKit.side_at(Vector3(origin.x + cell * 0.5, 0, origin.y + cell * 0.5))
	var farms: int = rng.randi_range(1, 3)
	for f in farms:
		var p := Vector2(origin.x + cell * rng.randf(), origin.y + cell * rng.randf())
		if not _ok(p, exclude, 1.8):
			continue
		var y: float = GroundKit.ground_y(p.x, p.y)
		var yaw: float = rng.randf() * TAU
		var hv: int = rng.randi() % 4
		(houses[hv] as Array).append(_xf(Vector3(p.x, y + 3.0, p.y), yaw, Vector3(12, 6.5, 16)))
		var bp: Vector2 = p + Vector2(cos(yaw) * 24.0, sin(yaw) * 24.0)
		if _ok(bp, exclude, 1.8):
			(houses[(hv + 1) % 4] as Array).append(_xf(Vector3(bp.x, GroundKit.ground_y(bp.x, bp.y) + 4.5, bp.y), yaw + PI * 0.5, Vector3(16, 9.0, 28)))
		for t in rng.randi_range(2, 5):
			var tp: Vector2 = p + Vector2(rng.randf_range(-34, 34), rng.randf_range(-34, 34))
			if _ok(tp, exclude, 1.5):
				var sc: float = rng.randf_range(1.4, 2.2)
				trees_r.append(_xf(Vector3(tp.x, GroundKit.ground_y(tp.x, tp.y) - 0.3, tp.y), rng.randf() * TAU, Vector3(sc, sc, sc)))
		if rng.randf() < 0.18:
			var wp: Vector2 = p + Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60))
			if _ok(wp, exclude, 1.8):
				var wm: Node3D = Landmarks.windmill()
				wm.position = Vector3(wp.x, GroundKit.ground_y(wp.x, wp.y), wp.y)
				wm.rotation.y = rng.randf() * TAU
				root.add_child(wm)
		var cp: Vector2 = p + Vector2(rng.randf_range(-90, 90), rng.randf_range(-90, 90))
		for c in rng.randi_range(5, 12):
			var q: Vector2 = cp + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
			if _ok(q, exclude, 1.8):
				cows.append(_xf(Vector3(q.x, GroundKit.ground_y(q.x, q.y), q.y), rng.randf() * TAU, Vector3.ONE * 1.8))
	for h in rng.randi_range(5, 10):
		var a := Vector2(origin.x + cell * rng.randf(), origin.y + cell * rng.randf())
		var ang: float = (0.0 if rng.randf() > 0.5 else PI * 0.5) + rng.randf_range(-0.15, 0.15)
		var ln: float = rng.randf_range(90.0, 220.0)
		var c: Vector2 = a + Vector2(cos(ang), sin(ang)) * ln * 0.5
		if _ok(a, exclude, 1.8) and _ok(c, exclude, 1.8):
			hedges.append(_xf(Vector3(c.x, GroundKit.ground_y(c.x, c.y) + 1.4, c.y), -ang, Vector3(ln, 2.8, 2.6)))
	for k in rng.randi_range(2, 5):
		var cc := Vector2(origin.x + cell * rng.randf(), origin.y + cell * rng.randf())
		for t in rng.randi_range(3, 8):
			var tp2: Vector2 = cc + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
			if _ok(tp2, exclude, 1.5):
				var sc2: float = rng.randf_range(1.3, 2.4)
				var tr: Transform3D = _xf(Vector3(tp2.x, GroundKit.ground_y(tp2.x, tp2.y) - 0.3, tp2.y), rng.randf() * TAU, Vector3(sc2, sc2, sc2))
				if rng.randf() < 0.5:
					trees_c.append(tr)
				else:
					trees_r.append(tr)
	for i in 4:
		if not (houses[i] as Array).is_empty():
			root.add_child(multi(house_mesh(i), houses[i], 6500.0))
	if not hedges.is_empty():
		root.add_child(multi(box_unit(Color(0.18, 0.29, 0.13), false), hedges, 7000.0))
	if LIVESTOCK and not cows.is_empty():
		root.add_child(multi(cow_mesh(), cows, 3500.0))
	var tsplit: Array = _split_trees(trees_c, trees_r)
	for tv2 in tsplit.size():
		if not (tsplit[tv2] as Array).is_empty():
			root.add_child(multi(tree_variant(tv2), tsplit[tv2], 7000.0))
	return root


## Land-cover driven tile: sample the ESA WorldCover grid and place trees on woodland, houses on
## built-up, hedgerows and the odd tree on farmland, cattle on pasture. Everything sits on terrain.
static func _make_tile_landcover(origin: Vector2, cell: float, seed_v: int, exclude: Array) -> Node3D:
	return build_tile_nodes(tile_landcover_data(origin, cell, seed_v, exclude))


## The expensive half of a land-cover tile: samples land cover / terrain / roads and computes every instance
## transform, packed into ready-to-upload MultiMesh buffers. Pure data (no nodes, no shared caches), so it can
## run on a worker thread (see WorldPopulator tile jobs). Call RoadMesh.prepare_block() on the same thread first.
static func tile_landcover_data(origin: Vector2, cell: float, seed_v: int, exclude: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var houses: Array = [[], [], [], []]
	var cows: Array = []
	var trees_c: Array = []
	var trees_r: Array = []
	# forest INTERIOR (not near the wood's margin): individual trees only close up, with whole-wood clump blobs
	# standing in at range; the margin keeps the full trees (and their long-range low-poly crowns)
	var wtrees_c: Array = []
	var wtrees_r: Array = []
	var blobs: Array = [[], []]
	var hedges: Array = []
	var ricks: Array = []
	var stooks: Array = []
	var mon: int = EraClock.month()
	var harvest_season: bool = mon >= 7 or mon <= 3       # ricks stood from the harvest until threshing in the winter
	var stook_season: bool = mon == 8 or mon == 9
	var wrecks: Array = []
	var obstacles: Array = []
	var house_yaw: float = rng.randf() * PI
	var farms_n: int = 0
	var step: float = 22.0
	var n: int = int(ceil(cell / step)) + 1
	for j in n:
		for i in n:
			var p := Vector2(origin.x + (float(i) + rng.randf()) * step, origin.y + (float(j) + rng.randf()) * step)
			var cls: int = LandCover.class_at(p.x, p.y)
			match cls:
				10:                                   # tree cover
					if _wood_interior(p):
						var br: float = rng.randf_range(34.0, 52.0)
						if i % 3 == 0 and j % 3 == 0 and _ok_tree(p, exclude) and not RoadMesh.near_road(p, br * 0.5):
							(blobs[rng.randi() % 2] as Array).append(_xf(Vector3(p.x, GroundKit.ground_y(p.x, p.y) - 1.0, p.y), rng.randf() * TAU,
								Vector3(br, rng.randf_range(15.0, 21.0), br * rng.randf_range(0.85, 1.1))))
						if wtrees_c.size() + wtrees_r.size() < 8000 and rng.randf() < 0.70 and _ok_tree(p, exclude):
							_add_tree(wtrees_c, wtrees_r, p, rng, 1.25, 1.8)
					elif trees_c.size() + trees_r.size() < 8000 and rng.randf() < 0.70 and _ok_tree(p, exclude):
						_add_tree(trees_c, trees_r, p, rng, 1.25, 1.8)     # fewer, bigger trees: the same canopy
				20:                                   # shrub
					if trees_c.size() + trees_r.size() < 6000 and rng.randf() < 0.2 and _ok_tree(p, exclude):
						_add_tree(trees_c, trees_r, p, rng, 0.85, 1.25)
				40:                                   # cropland: hedges and trees follow the field boundaries
					_field_edge_props(p, exclude, hedges, trees_c, trees_r, rng, 0.9)
					if farms_n < 3 and rng.randf() < 0.0007 and _add_farmstead(p, exclude, houses, trees_c, trees_r, rng):
						farms_n += 1
					if trees_c.size() + trees_r.size() < 9000 and rng.randf() < 0.008 and _ok_tree(p, exclude):
						_add_tree(trees_c, trees_r, p, rng, 0.9, 1.3)
					# harvest: a group of corn ricks, or rows of stooks drying in the field
					var rick_roll: float = rng.randf()     # drawn every time, so the season never shifts the rest of the tile
					if ricks.size() < 24 and harvest_season and rick_roll < 0.0011 and _ok(p, exclude, 1.5):
						var ry: float = rng.randf() * TAU
						var rdir := Vector2(cos(ry), sin(ry))
						if rng.randf() < 0.5 or not stook_season:
							for k in rng.randi_range(2, 5):
								var q: Vector2 = p + rdir * (float(k) * 9.0) + Vector2(-rdir.y, rdir.x) * rng.randf_range(-1.5, 1.5)
								ricks.append(_xf(Vector3(q.x, GroundKit.ground_y(q.x, q.y) - 0.2, q.y), rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.85, 1.1)))
						else:
							for k in rng.randi_range(4, 8):
								var q2: Vector2 = p + Vector2(-rdir.y, rdir.x) * (float(k) * 7.0)
								stooks.append(_xf(Vector3(q2.x, GroundKit.ground_y(q2.x, q2.y), q2.y), ry, Vector3.ONE))
					if wrecks.size() < 1 and rng.randf() < 0.00005 and _ok(p, exclude, 1.5):
						wrecks.append(_xf(Vector3(p.x, GroundKit.ground_y(p.x, p.y), p.y), rng.randf() * TAU, Vector3.ONE))
					if obstacles.size() < 6 and rng.randf() < 0.004 and RuralProps.wants_obstacles(p) and _ok(p, exclude, 1.5):
						obstacles.append(_xf(Vector3(p.x, GroundKit.ground_y(p.x, p.y), p.y), rng.randf() * PI, Vector3.ONE))
					# an outlying cottage / ribbon plot just beyond the built-up mask frays the town edge into the fields
					if rng.randf() < 0.075 and _built_near(p, 80.0) and _ok(p, exclude, 1.4):
						_add_house(houses, p, rng, house_yaw + rng.randf_range(-0.9, 0.9))
				30:                                   # grassland
					_field_edge_props(p, exclude, hedges, trees_c, trees_r, rng, 0.45)
					if farms_n < 3 and rng.randf() < 0.0004 and _add_farmstead(p, exclude, houses, trees_c, trees_r, rng):
						farms_n += 1
					if trees_c.size() + trees_r.size() < 9000 and rng.randf() < 0.022 and _ok_tree(p, exclude):
						_add_tree(trees_c, trees_r, p, rng, 0.85, 1.25)
					if wrecks.size() < 1 and rng.randf() < 0.00004 and _ok(p, exclude, 1.5):
						wrecks.append(_xf(Vector3(p.x, GroundKit.ground_y(p.x, p.y), p.y), rng.randf() * TAU, Vector3.ONE))
					if obstacles.size() < 6 and rng.randf() < 0.003 and RuralProps.wants_obstacles(p) and _ok(p, exclude, 1.5):
						obstacles.append(_xf(Vector3(p.x, GroundKit.ground_y(p.x, p.y), p.y), rng.randf() * PI, Vector3.ONE))
					if rng.randf() < 0.012 and _ok(p, exclude, 1.5):
						cows.append(_xf(Vector3(p.x, GroundKit.ground_y(p.x, p.y), p.y), rng.randf() * TAU, Vector3.ONE * 1.8))
					# an outlying cottage / ribbon plot just beyond the built-up mask frays the town edge into the fields
					if rng.randf() < 0.075 and _built_near(p, 80.0) and _ok(p, exclude, 1.4):
						_add_house(houses, p, rng, house_yaw + rng.randf_range(-0.9, 0.9))
				50:                                   # built-up: terraced rows along the local street grid
					if in_park(p.x, p.y):
						# parkland: scattered trees
						if rng.randf() < 0.012 and _ok_tree(p, exclude):
							_add_tree(trees_c, trees_r, p, rng, 1.0, 1.5)
					else:
						var edge_f: float = _built_frac(p)
						if rng.randf() < 0.88 * (0.45 + 0.55 * edge_f) and _ok(p, exclude, 1.2):
							# the town's rows bend and merge with the next block instead of running dead straight
							var yaw_j: float = house_yaw + (_vn(p.x * 0.0035 + 71.0, p.y * 0.0035 + 71.0) - 0.5) * 1.1 + rng.randf_range(-0.05, 0.05)
							_add_terrace(houses, p, rng, yaw_j)
	# bomb damage on the war date: gutted shells and cleared plots (same transforms, two shared shell meshes)
	var dmg_areas: Array = WarDamage.areas_near(origin, cell)
	var ruins: Array = [[], []]
	WarDamage.apply_to_houses(houses, ruins, dmg_areas)
	var out: Dictionary = {"multis": [], "church": null}
	# A church at the heart of each village (a cluster of houses in this tile)
	var n_houses: int = 0
	var hc := Vector3.ZERO
	for k in 4:
		for t in (houses[k] as Array):
			hc += (t as Transform3D).origin
			n_houses += 1
	if n_houses >= 12:
		hc /= float(n_houses)
		# snap to the nearest house so the church sits inside the built-up area
		var best_d: float = 1.0e12
		var best_p: Vector3 = hc
		for k2 in 4:
			for t2 in (houses[k2] as Array):
				var d2: float = ((t2 as Transform3D).origin - hc).length_squared()
				if d2 < best_d:
					best_d = d2
					best_p = (t2 as Transform3D).origin
		var cp := Vector3(best_p.x + 14.0, GroundKit.ground_y(best_p.x + 14.0, best_p.z), best_p.z)
		var ch_scale: float = rng.randf_range(0.9, 1.3)
		if WarDamage.level_in(dmg_areas, cp.x, cp.z) < 0.6:
			out["church"] = [cp, house_yaw, ch_scale]
	# thin white chimney smoke over a handful of the houses (capped per tile: each one is a live emitter)
	var smokes: Array = []
	for k in 4:
		for t3 in (houses[k] as Array):
			if smokes.size() >= 2:
				break
			if rng.randf() < 0.015:          # only the odd house has a fire lit
				var tb: Transform3D = t3
				smokes.append(tb.origin + Vector3(tb.basis.x.normalized().x * 2.0, tb.basis.get_scale().y * 0.5 + 1.2, tb.basis.x.normalized().z * 2.0))
	out["smokes"] = smokes
	for k in 4:
		if not (houses[k] as Array).is_empty():
			out["multis"].append(["house%d" % k, multi_data(houses[k]), VIS_HOUSE])
	if not hedges.is_empty():
		out["multis"].append(["hedge", multi_data(hedges), VIS_HEDGE])
	for rv in 2:
		if not (ruins[rv] as Array).is_empty():
			out["multis"].append(["ruin%d" % rv, multi_data(ruins[rv]), VIS_HOUSE])
	if LIVESTOCK and not cows.is_empty():
		out["multis"].append(["cow", multi_data(cows), VIS_COW])
	if not ricks.is_empty():
		out["multis"].append(["rick", multi_data(ricks), RuralProps.VIS_RICK])
	if not stooks.is_empty():
		out["multis"].append(["stooks", multi_data(stooks), RuralProps.VIS_RICK * 0.6])
	if not wrecks.is_empty():
		out["multis"].append(["field_wreck", multi_data(wrecks), RuralProps.VIS_WRECK])
	if not obstacles.is_empty():
		out["multis"].append(["landing_obstacles", multi_data(obstacles), RuralProps.VIS_RICK])
	var tsp: Array = _split_trees(trees_c, trees_r)
	for tv3 in tsp.size():
		if not (tsp[tv3] as Array).is_empty():
			out["multis"].append(["tree_v%d" % tv3, multi_data(tsp[tv3]), VIS_TREE])
	var wsp: Array = _split_trees(wtrees_c, wtrees_r)
	for wv in wsp.size():
		if not (wsp[wv] as Array).is_empty():
			out["multis"].append(["wtree_v%d" % wv, multi_data(wsp[wv]), WOOD_TREE_VIS])
	for bv in 2:
		if not (blobs[bv] as Array).is_empty():
			out["multis"].append(["wblob%d" % bv, multi_data(blobs[bv]), VIS_TREE])
	for bm in BeachKit.tile_multis(origin, cell, seed_v, exclude):
		out["multis"].append(bm)
	return out


## The cheap half (main thread): creates the nodes from tile_landcover_data().
static func build_tile_nodes(d: Dictionary) -> Node3D:
	var root := Node3D.new()
	var ch_d: Variant = d.get("church")
	if ch_d != null:
		var ch: Node3D = Landmarks.church(float(ch_d[2]))
		Obstacles.register(ch)
		ch.position = ch_d[0]
		ch.rotation.y = float(ch_d[1])
		root.add_child(ch)
	var sm_d: Array = d.get("smokes", [])
	if not sm_d.is_empty():
		var cs := ChimneySmokes.new()
		for sp in sm_d:
			cs.points.append(sp)
		root.add_child(cs)
	for m in d.get("multis", []):
		var kind: String = m[0]
		var mesh: Mesh
		match kind:
			"hedge":
				mesh = hedge_mesh()
			"cow":
				mesh = cow_mesh()
			"rick":
				mesh = RuralProps.rick_mesh()
			"stooks":
				mesh = RuralProps.stook_mesh()
			"field_wreck":
				mesh = RuralProps.wreck_mesh()
			"landing_obstacles":
				mesh = RuralProps.obstacle_mesh()
			"tree_c":
				mesh = tree_mesh(false)
			"tree_r":
				mesh = tree_mesh(true)
			_:
				if kind.begins_with("bk_"):
					mesh = BeachKit.mesh(kind)
				elif kind.begins_with("ruin"):
					mesh = WarDamage.ruin_mesh(int(kind.substr(4)))
				elif kind.begins_with("tree_v"):
					mesh = tree_variant(int(kind.substr(6)))
				elif kind.begins_with("wtree_v"):
					mesh = tree_variant(int(kind.substr(7)))
				elif kind.begins_with("wblob"):
					mesh = wood_blob_mesh(int(kind.substr(5)))
				else:
					mesh = house_mesh(int(kind.substr(5)))
		if kind.begins_with("tree_v") or kind == "hedge":
			_add_lod_pair(root, mesh, far_mesh(kind), m[1], float(m[2]), TREE_NEAR if kind != "hedge" else HEDGE_NEAR)
		elif kind.begins_with("wtree_v"):
			_add_lod_pair(root, mesh, far_mesh("tree_v" + kind.substr(7)), m[1], float(m[2]), WOOD_TREE_NEAR)
		elif kind.begins_with("wblob"):
			var bi: MultiMeshInstance3D = multi_from_data(mesh, m[1], float(m[2]))
			bi.visibility_range_begin = WOOD_BLOB_BEGIN * vis_scale
			bi.visibility_range_begin_margin = 250.0
			root.add_child(bi)
		else:
			root.add_child(multi_from_data(mesh, m[1], float(m[2])))
	return root


## Near / far pair over the same instances: the full model up close, a one-piece low-poly stand-in
## (no outline pass) further out. The switch is per multimesh (tile), on its AABB centre distance.
static func _add_lod_pair(root: Node, near_mesh: Mesh, far: Mesh, d: Dictionary, vis_end: float, near_end: float) -> void:
	var ne: float = near_end * vis_scale
	if vis_end <= ne:
		root.add_child(multi_from_data(near_mesh, d, vis_end))
		return
	var a: MultiMeshInstance3D = multi_from_data(near_mesh, d, ne)
	a.visibility_range_end_margin = 150.0
	a.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	root.add_child(a)
	var b: MultiMeshInstance3D = multi_from_data(far, d, vis_end, false)     # same instances as `a`: solid once
	b.visibility_range_begin = ne
	b.visibility_range_begin_margin = 150.0
	root.add_child(b)


const TREE_NEAR: float = 2200.0
const WOOD_TREE_NEAR: float = 700.0      # forest interior: full trees only this close ...
const WOOD_TREE_VIS: float = 2400.0      # ... low-poly crowns out to here, then the clump blobs take over
const WOOD_BLOB_BEGIN: float = 0.0    # blobs show at every range (fill between the crowns up close, the whole canopy far off)
const WOOD_EDGE_PROBE: float = 110.0     # a wood sample within this of non-wood land counts as the margin


## True when p is well inside woodland: all four probes WOOD_EDGE_PROBE m away are tree cover too.
static func _wood_interior(p: Vector2) -> bool:
	return LandCover.class_at(p.x + WOOD_EDGE_PROBE, p.y) == 10 and LandCover.class_at(p.x - WOOD_EDGE_PROBE, p.y) == 10 \
		and LandCover.class_at(p.x, p.y + WOOD_EDGE_PROBE) == 10 and LandCover.class_at(p.x, p.y - WOOD_EDGE_PROBE) == 10


## A clump of canopy for far-off forest: a few overlapping squashed domes in one cheap surface (unit size: the
## instance scale sets radius and height). Variant 0 is darker conifer, 1 mixed woodland.
static func wood_blob_mesh(variant: int) -> ArrayMesh:
	var key: String = "wood_blob_%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var base: Color = TREE_GREEN * (0.93 if variant == 0 else 1.06)
	var lumps: Array = [
		[Vector3(0.0, 0.5, 0.0), 0.72, 1.0, 1.00],
		[Vector3(0.55, 0.36, 0.15), 0.5, 0.8, 1.12],
		[Vector3(-0.5, 0.34, -0.3), 0.5, 0.75, 0.92],
		[Vector3(0.1, 0.3, -0.65), 0.45, 0.7, 1.06],
		[Vector3(-0.25, 0.32, 0.6), 0.42, 0.66, 0.96],
	]
	var parts: Array = []
	for l in lumps:
		var sm := SphereMesh.new()
		sm.radius = float(l[1])
		sm.height = float(l[2])
		sm.radial_segments = 7
		sm.rings = 3
		var c: Color = Color(base.r * float(l[3]), base.g * float(l[3]), base.b * float(l[3]))
		parts.append([sm, Transform3D(Basis.IDENTITY, l[0]), _dmat(c, 3, 0.1, false)])
	var m: ArrayMesh = _merge(parts)
	_meshes[key] = m
	return m
const HEDGE_NEAR: float = 1500.0
# far crowns per species: [cone?, centre, radius, height, colour] (radius a little wider: the near model's bushy lobes)
const TREE_FAR: Array = [
	[true, Vector3(0, 7.5, 0), 4.0, 11.5, Color(0.14, 0.3, 0.17)],
	[false, Vector3(0, 6.6, 0), 4.3, 7.4, Color(0.24, 0.36, 0.15)],
	[true, Vector3(0, 10.0, 0), 2.4, 15.5, Color(0.20, 0.34, 0.13)],
	[false, Vector3(0.5, 7.4, 0.2), 3.1, 6.4, Color(0.36, 0.44, 0.20)],
	[false, Vector3(-0.6, 7.0, 0.4), 4.8, 7.6, Color(0.26, 0.38, 0.16)],
	[false, Vector3(0, 6.9, 0), 4.8, 7.8, Color(0.18, 0.30, 0.16)],
	[false, Vector3(0.2, 9.6, 0), 4.0, 4.0, Color(0.15, 0.31, 0.20)],
	[false, Vector3(0.3, 6.3, 0.2), 5.0, 6.2, Color(0.42, 0.46, 0.20)],
]


## One-surface distance stand-in for "tree_vN" / "hedge" (about a tenth of the triangles, one draw, no outline).
static func far_mesh(kind: String) -> ArrayMesh:
	var key: String = "far_" + kind
	if _meshes.has(key):
		return _meshes[key]
	var parts: Array = []
	if kind == "hedge":
		var hb := BoxMesh.new()
		hb.size = Vector3(1.0, 0.82, 0.62)
		parts.append([hb, Transform3D.IDENTITY, _dmat(Color(0.23, 0.32, 0.17), 3, 0.0, false)])
	else:
		var spec: Array = TREE_FAR[clampi(int(kind.substr(6)), 0, TREE_FAR.size() - 1)]
		var shape: PrimitiveMesh
		if bool(spec[0]):
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = float(spec[2])
			cm.height = float(spec[3])
			cm.radial_segments = 6
			cm.rings = 1
			cm.cap_top = false
			shape = cm
		else:
			var sm := SphereMesh.new()
			sm.radius = float(spec[2])
			sm.height = float(spec[3])
			sm.radial_segments = 6
			sm.rings = 3
			shape = sm
		parts.append([shape, Transform3D(Basis.IDENTITY, spec[1]), _dmat(_calm(spec[4]), 3, 0.1, false)])
	var m: ArrayMesh = _merge(parts)
	_meshes[key] = m
	return m


## multi() split in two: the transform packing (any thread) ...
static func multi_data(xforms: Array) -> Dictionary:
	var lo := Vector3(1.0e9, 1.0e9, 1.0e9)
	var hi := Vector3(-1.0e9, -1.0e9, -1.0e9)
	for t in xforms:
		var o: Vector3 = (t as Transform3D).origin
		lo = lo.min(o)
		hi = hi.max(o)
	var c: Vector3 = (lo + hi) * 0.5 if not xforms.is_empty() else Vector3.ZERO
	var buf := PackedFloat32Array()
	buf.resize(xforms.size() * 12)
	var i: int = 0
	for t2 in xforms:
		var b: Basis = (t2 as Transform3D).basis
		var o2: Vector3 = (t2 as Transform3D).origin - c
		buf[i] = b.x.x
		buf[i + 1] = b.y.x
		buf[i + 2] = b.z.x
		buf[i + 3] = o2.x
		buf[i + 4] = b.x.y
		buf[i + 5] = b.y.y
		buf[i + 6] = b.z.y
		buf[i + 7] = o2.y
		buf[i + 8] = b.x.z
		buf[i + 9] = b.y.z
		buf[i + 10] = b.z.z
		buf[i + 11] = o2.z
		i += 12
	return {"buf": buf, "count": xforms.size(), "c": c, "lo": lo, "hi": hi}


## ... and the node (main thread): one buffer upload instead of a set_instance_transform() per instance.
static func multi_from_data(mesh: Mesh, d: Dictionary, vis_end: float = 0.0, solid: bool = true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = int(d["count"])
	if mm.instance_count > 0:
		mm.buffer = d["buf"]
	mm.visible_instance_count = mm.instance_count
	var c: Vector3 = d["c"]
	var lo: Vector3 = d["lo"]
	var hi: Vector3 = d["hi"]
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.position = c
	var pad := Vector3(60.0, 60.0, 60.0)
	mi.custom_aabb = AABB(lo - c - pad, (hi - lo) + pad * 2.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if solid:
		Obstacles.register(mi)
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
		mi.visibility_range_end_margin = minf(vis_end * 0.12, 900.0)
		# no FADE_SELF: a fading object is drawn in the transparent pass, after the clouds, so woods and houses
		# showed through cloud decks. Plain range cut-off instead (the margin keeps it from flickering).
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	return mi


static func _add_tree(cones: Array, rounds: Array, p: Vector2, rng: RandomNumberGenerator, s0: float, s1: float) -> void:
	var sc: float = rng.randf_range(s0, s1)
	var t: Transform3D = _xf(Vector3(p.x, GroundKit.ground_y(p.x, p.y) - 0.3, p.y), rng.randf() * TAU, Vector3(sc, sc * rng.randf_range(0.9, 1.3), sc))
	if rng.randf() < 0.6:
		cones.append(t)
	else:
		rounds.append(t)


static func _add_house(lists: Array, p: Vector2, rng: RandomNumberGenerator, yaw: float) -> void:
	var h: float = rng.randf_range(5.0, 9.0)
	var w: float = rng.randf_range(8.0, 13.0)
	var l: float = rng.randf_range(7.0, 11.0)
	if RoadMesh.near_road(p, maxf(w, l) * 0.6):       # the whole house clear of the road, not just its centre
		return
	var y: float = GroundKit.ground_y(p.x, p.y) + h * 0.5 - 0.4
	(lists[rng.randi() % 4] as Array).append(_xf(Vector3(p.x, y, p.y), yaw + rng.randf_range(-0.12, 0.12), Vector3(w, h, l)))


## A short terrace of 2-4 attached houses (typical English / Flemish street frontage), filling most of
## a 22 m sample cell, so built-up land reads as dense streets rather than scattered boxes.
static func _add_terrace(lists: Array, p: Vector2, rng: RandomNumberGenerator, yaw: float) -> void:
	var n: int = rng.randi_range(2, 4)
	var unit_w: float = rng.randf_range(6.2, 7.6)
	var depth: float = rng.randf_range(6.6, 9.0)
	var a: float = yaw + rng.randf_range(-0.06, 0.06)
	var along := Vector2(cos(a), -sin(a))
	var start: Vector2 = p - along * unit_w * float(n - 1) * 0.5
	var base_h: float = rng.randf_range(6.0, 9.5)
	var lst: Array = lists[rng.randi() % 4]
	for i in n:
		var q: Vector2 = start + along * unit_w * float(i)
		if not _land(q.x, q.y, 1.2) or RoadMesh.near_road(q, maxf(unit_w, depth) * 0.6):
			continue
		var h: float = base_h + rng.randf_range(-0.4, 0.4)
		var y: float = GroundKit.ground_y(q.x, q.y) + h * 0.5 - 0.4
		lst.append(_xf(Vector3(q.x, y, q.y), a, Vector3(unit_w * 1.02, h, depth)))


# ------------------------------------------------------------------ field boundaries (mirrors shaders/terrain.gdshader)
const FIELD_CELL: float = 190.0      # = terrain.gdshader field_cell (it was 62 vs the shader's 124: the hedges missed the painted boundaries)


static func _fh(px: float, py: float) -> float:        # t_hash12
	var ax: float = fposmod(px * 0.1031, 1.0)
	var ay: float = fposmod(py * 0.1031, 1.0)
	var bx: float = ax
	var by: float = ay
	var bz: float = ax
	var dd: float = bx * (by + 33.33) + by * (bz + 33.33) + bz * (bx + 33.33)
	bx += dd
	by += dd
	bz += dd
	return fposmod((bx + by) * bz, 1.0)


# Mirrors the terrain shader's town-park mask (smoothstep(0.76,0.80, vnoise(xz*0.0042+31)))
static func in_park(x: float, z: float) -> bool:
	return _vn(x * 0.0042 + 31.0, z * 0.0042 + 31.0) > 0.775


# Mirrors the terrain shader's lake mask (blobs of vnoise in lowland hollows). Lakes are painted colour on the
# terrain, not real water, so nothing may be scattered on them: trees, hedges, forests, farms and cattle.
static func lake_noise(x: float, z: float) -> float:
	return _vn(x * 0.00085 + 300.0, z * 0.00085 + 300.0) * 0.62 + _vn(x * 0.0032 + 9.0, z * 0.0032 + 9.0) * 0.38


static func in_lake(x: float, z: float) -> bool:
	if lake_noise(x, z) <= 0.780:      # keep in step with terrain.gdshader (shore band starts at 0.78)
		return false
	var h: float = GroundKit.raw_y(x, z)
	return h > 1.5 and h < 108.0        # same lowland band the shader allows lakes in


static func _vn(px: float, py: float) -> float:        # t_vnoise2
	var ix: float = floorf(px)
	var iy: float = floorf(py)
	var fx: float = px - ix
	var fy: float = py - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a: float = _fh(ix, iy)
	var b: float = _fh(ix + 1.0, iy)
	var c: float = _fh(ix, iy + 1.0)
	var d: float = _fh(ix + 1.0, iy + 1.0)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


## Low-frequency wobble for town edges (0.78..1.22). World-space, so neighbouring town tiles agree
## on where the built-up area frays out instead of ending on a hard circle or tile boundary.
static func _edge_k(x: float, z: float) -> float:
	var n: float = _vn(x * 0.0065 + 17.0, z * 0.0065 + 17.0) * 0.65 \
		+ _vn(x * 0.019 + 5.0, z * 0.019 + 5.0) * 0.35
	return 0.78 + 0.44 * n


## Cheap probe: is there built-up land cover within `r` of p? Used to fray the town edge into
## the fields with the odd outlying cottage instead of stopping dead at the mask boundary.
static func _built_near(p: Vector2, r: float) -> bool:
	for k in 4:
		var a: float = TAU * float(k) / 4.0 + 0.4
		if LandCover.class_at(p.x + cos(a) * r, p.y + sin(a) * r) == 50:
			return true
	return false


## How much of the ring around p is built-up (0..1). Frays the town fringe instead of ending it
## on the land-cover cell boundary.
static func _built_frac(p: Vector2, r: float = 34.0) -> float:
	var n: int = 0
	for k in 8:
		var a: float = TAU * float(k) / 8.0
		if LandCover.class_at(p.x + cos(a) * r, p.y + sin(a) * r) == 50:
			n += 1
	return float(n) / 8.0


## Nearest field boundary to world point p (the same domain-warped Voronoi cells the terrain shader paints, including its
## strip-field districts, field-size zones and rectangular-enclosure districts - keep in sync with shaders/terrain.gdshader).
## Returns {"q": Vector2 point on the boundary, "tan": Vector2 unit tangent, "dist": metres} .
static func field_edge(p: Vector2) -> Dictionary:
	var wx: float = _vn(p.x * 0.004, p.y * 0.004) - 0.5
	var wy: float = _vn(p.x * 0.004 + 53.7, p.y * 0.004 + 53.7) - 0.5
	var strip: float = 1.0 if _vn(p.x * 0.0012 + 41.0, p.y * 0.0012 + 41.0) >= 0.55 else 0.0
	var zn: float = _vn(p.x * 0.0009 + 77.0, p.y * 0.0009 + 77.0)
	var zscale: float = 0.65 if zn < 0.22 else (1.0 if zn < 0.42 else (1.6 if zn < 0.58 else 1.2))
	var zjit: float = 0.85 if zn < 0.42 else (0.6 if zn < 0.58 else 0.12)
	var rg: Vector4 = RegionMap.type_weights(p.x, p.y)       # [bocage, open, polder, weald] - as terrain.gdshader
	strip = maxf(strip * (1.0 - rg.x), rg.z)
	zscale = lerpf(zscale, 0.48, rg.x)
	zjit = lerpf(zjit, 0.9, rg.x)
	zscale = lerpf(zscale, 2.1, rg.y)
	zscale = lerpf(zscale, zscale * 0.72, rg.w)
	var zrect: float = (1.0 if zn >= 0.58 else 0.0) * (1.0 - strip) * (1.0 - rg.x)
	var zrot: float = maxf(strip, 1.0 if zn >= 0.42 else 0.0)
	var sang: float = _fh(floorf(p.x * 0.00035) + 5.0, floorf(p.y * 0.00035) + 5.0) * 3.14159 * zrot
	var sdir := Vector2(cos(sang), sin(sang))
	var perp := Vector2(-sdir.y, sdir.x)
	var wq := Vector2(p.x + wx * 30.0, p.y + wy * 30.0)
	var zs: float = lerpf(zscale, 1.0, strip)
	var cell_x: float = FIELD_CELL * lerpf(1.0, 1.7, strip) * zs * lerpf(1.0, 1.6, rg.z)
	var cell_y: float = FIELD_CELL * lerpf(1.0, 0.72, strip) * zs * lerpf(1.0, 0.62, rg.z)
	var u := Vector2(wq.dot(sdir) / cell_x, wq.dot(perp) / cell_y)
	var cid := Vector2(floorf(u.x), floorf(u.y))
	var gv: Vector2 = u - cid - Vector2(0.5, 0.5)
	var jit_k: float = lerpf(zjit, 0.85, strip)
	var d1: float = 8.0
	var d2: float = 8.0
	var f1 := Vector2.ZERO
	var f2 := Vector2.ZERO
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var jx: float = _fh(cid.x + ox, cid.y + oy) - 0.5
			var jy: float = _fh(cid.x + ox + 19.7, cid.y + oy + 19.7) - 0.5
			var f := Vector2(ox + jx * jit_k, oy + jy * jit_k)
			var rr: Vector2 = gv - f
			var dc: float = maxf(absf(rr.x), absf(rr.y))
			var d: float = lerpf(rr.dot(rr), dc * dc, zrect)
			if d < d1:
				d2 = d1
				f2 = f1
				d1 = d
				f1 = f
			elif d < d2:
				d2 = d
				f2 = f
	var diff: Vector2 = f2 - f1
	if diff.length() < 0.0001:
		return {}
	var n: Vector2
	var m: Vector2 = (f1 + f2) * 0.5
	if zrect > 0.5:        # Chebyshev metric: the boundary is an axis-aligned line through the midpoint
		n = Vector2(signf(diff.x), 0.0) if absf(diff.x) >= absf(diff.y) else Vector2(0.0, signf(diff.y))
	else:
		n = diff.normalized()
	var off: float = (gv - m).dot(n)
	var q_gv: Vector2 = gv - n * off
	var qp: Vector2 = (cid + Vector2(0.5, 0.5) + q_gv)
	var qw: Vector2 = sdir * (qp.x * cell_x) + perp * (qp.y * cell_y) - Vector2(wx, wy) * 30.0
	var tg_gv := Vector2(-n.y, n.x)
	var tg: Vector2 = sdir * (tg_gv.x * cell_x) + perp * (tg_gv.y * cell_y)
	var dist_vec: Vector2 = sdir * (n.x * off * cell_x) + perp * (n.y * off * cell_y)
	var c1: Vector2 = cid + f1.round()
	var c2: Vector2 = cid + f2.round()
	var eid: int = hash(Vector4(c1.x + c2.x, c1.y + c2.y, absf(c1.x - c2.x), absf(c1.y - c2.y)))
	return {"q": qw, "tan": tg.normalized(), "dist": dist_vec.length(), "eid": eid, "region": rg}


## Hedge segments and the odd tree along the field boundary that passes near sample point p.
const HEDGE_OPEN_PCT: int = 40     # share of field boundaries without a hedge row
const LIVESTOCK: bool = false       # cattle in the fields (removed: read as white blobs from the air)


static func _field_edge_props(p: Vector2, exclude: Array, hedges: Array, trees_c: Array, trees_r: Array, rng: RandomNumberGenerator, density: float) -> void:
	if rng.randf() > density:
		return
	var e: Dictionary = field_edge(p)
	if e.is_empty() or float(e["dist"]) > 11.0:
		return
	var rgw: Vector4 = e.get("region", Vector4.ZERO)
	# share of open boundaries by region: bocage almost all hedged, open-field country almost none, polders are
	# ditches (a line of poplars or willows along some of them), the Weald well hedged
	var open_pct: int = HEDGE_OPEN_PCT
	if rgw.x > 0.5:
		open_pct = 4
	elif rgw.y > 0.5:
		open_pct = 93
	elif rgw.z > 0.5:
		open_pct = 100
	elif rgw.w > 0.5:
		open_pct = 22
	if absi(int(e["eid"])) % 100 < open_pct:
		if rgw.z > 0.5 and absi(int(e["eid"])) % 7 == 0 and trees_c.size() + trees_r.size() < 9000:
			var qq: Vector2 = e["q"]
			if _ok_tree(qq, exclude):
				_add_tree(trees_c, trees_r, qq, rng, 0.9, 1.25)     # poplar / willow line along a polder ditch
		return     # an open boundary (post-and-wire, ditch or grubbed out): no hedge row, no hedgerow trees
	var q: Vector2 = e["q"]
	if q.distance_to(p) > 15.0 or not _ok(q, exclude, 1.6) or GroundKit.ground_y(q.x, q.y) > 350.0:
		return
	var tg: Vector2 = e["tan"]
	# The bisector between two field centres is an infinite line, but the real boundary stops at the field corners.
	# Only keep a segment whose ends and middle all still lie on a boundary, so hedges never cut across a field.
	var half: float = 0.0
	for cand in [11.0, 7.0, 3.5]:
		var ok_seg: bool = true
		for t in [-1.0, -0.5, 0.5, 1.0]:
			var pe: Dictionary = field_edge(q + tg * (cand * t))
			# the same boundary all the way along (same pair of fields), within 1.6 m of the straight line
			if pe.is_empty() or float(pe["dist"]) > 1.6 or int(pe["eid"]) != int(e["eid"]):
				ok_seg = false
				break
		if ok_seg:
			half = cand
			break
	if half <= 0.0:
		return
	var ang: float = atan2(tg.y, tg.x)
	var boc: bool = rgw.x > 0.5
	# bocage: the hedge stands on a bank, taller and thicker, with more trees in it
	hedges.append(_xf(Vector3(q.x, GroundKit.ground_y(q.x, q.y) + (1.6 if boc else 1.15), q.y), -ang, Vector3(half * 2.0 + 1.0, 3.2 if boc else 2.3, 2.6 if boc else 1.9)))
	if trees_c.size() + trees_r.size() < 9000 and rng.randf() < (0.8 if boc else (0.6 if rgw.w > 0.5 else 0.45)):
		var tp: Vector2 = q + tg * rng.randf_range(-half, half) + Vector2(-tg.y, tg.x) * rng.randf_range(-2.5, 2.5)
		if _ok_tree(tp, exclude):
			_add_tree(trees_c, trees_r, tp, rng, 0.9, 1.3)


## A farmstead on the edge of a field: farmhouse and a big barn round a yard, a shed, and a windbreak of trees on the
## exposed side, all aligned to the field boundary. Sparse by design (about one per km2 of farmland). Returns true if placed.
static func _add_farmstead(p: Vector2, exclude: Array, houses: Array, trees_c: Array, trees_r: Array, rng: RandomNumberGenerator) -> bool:
	var e: Dictionary = field_edge(p)
	if e.is_empty() or float(e["dist"]) > 14.0:
		return false
	var q: Vector2 = e["q"]
	var tg: Vector2 = e["tan"]
	var nrm := Vector2(-tg.y, tg.x)
	if rng.randf() < 0.5:
		nrm = -nrm
	var base: Vector2 = q + nrm * 12.0       # yard sits just inside the field next to the boundary
	if GroundKit.ground_y(base.x, base.y) > 300.0:
		return false
	var yaw: float = atan2(tg.y, tg.x)
	var spots: Array = []
	var house_p: Vector2 = base - tg * 14.0
	var barn_p: Vector2 = base + tg * 16.0 + nrm * 6.0
	var shed_p: Vector2 = base + nrm * 20.0 - tg * 4.0
	for sp in [house_p, barn_p, shed_p]:
		if not _ok(sp, exclude, 1.8):
			return false
	var hv: int = rng.randi() % 4
	(houses[hv] as Array).append(_xf(Vector3(house_p.x, GroundKit.ground_y(house_p.x, house_p.y) + 3.0, house_p.y), -yaw + PI * 0.5, Vector3(11, 6.5, 15)))
	(houses[(hv + 1) % 4] as Array).append(_xf(Vector3(barn_p.x, GroundKit.ground_y(barn_p.x, barn_p.y) + 4.5, barn_p.y), -yaw, Vector3(26, 9.0, 15)))
	(houses[(hv + 2) % 4] as Array).append(_xf(Vector3(shed_p.x, GroundKit.ground_y(shed_p.x, shed_p.y) + 2.0, shed_p.y), -yaw, Vector3(10, 4.0, 7)))
	# windbreak on the far side of the yard, plus a couple of orchard trees by the house
	for i in rng.randi_range(4, 7):
		var tp: Vector2 = base + nrm * 32.0 + tg * (float(i) * 9.0 - 30.0) + Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
		if _ok_tree(tp, exclude):
			_add_tree(trees_c, trees_r, tp, rng, 1.2, 1.8)
	for i in 2:
		var op: Vector2 = house_p - nrm * 10.0 + tg * rng.randf_range(-10.0, 4.0)
		if _ok_tree(op, exclude):
			_add_tree(trees_c, trees_r, op, rng, 0.9, 1.2)
	return true


static func _add_hedge(list: Array, p: Vector2, rng: RandomNumberGenerator) -> void:
	var ang: float = (0.0 if rng.randf() > 0.5 else PI * 0.5) + rng.randf_range(-0.15, 0.15)
	var ln: float = rng.randf_range(60.0, 150.0)
	var c: Vector2 = p + Vector2(cos(ang), sin(ang)) * ln * 0.5
	if _land(c.x, c.y, 1.5) and not in_lake(c.x, c.y):
		list.append(_xf(Vector3(c.x, GroundKit.ground_y(c.x, c.y) + 0.9, c.y), -ang, Vector3(ln, 1.8, 1.6)))


## True on or near the beach / shoreline (no trees there): low ground with open water within ~220 m.
static func _beach(p: Vector2) -> bool:
	var h: float = GroundKit.raw_y(p.x, p.y)
	if h > 50.0:
		return false
	# open water within ~150 units (300 m) in any of 8 directions: beach and the low cliff top above it
	var reach: float = 260.0 if h < 6.0 else 150.0
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(0.7, 0.7), Vector2(-0.7, 0.7), Vector2(0.7, -0.7), Vector2(-0.7, -0.7)]:
		if GroundKit.raw_y(p.x + d.x * reach, p.y + d.y * reach) < 0.6 or GroundKit.raw_y(p.x + d.x * reach * 0.5, p.y + d.y * reach * 0.5) < 0.6:
			return true
	return false


static func _ok_tree(p: Vector2, exclude: Array, min_h: float = 1.5) -> bool:
	return _ok(p, exclude, min_h) and not _beach(p)


static func _ok(p: Vector2, exclude: Array, min_h: float) -> bool:
	if not _land(p.x, p.y, min_h):
		return false
	if RiverMesh.near_river(p):        # nor in a river channel (near_river is worker-thread owned, see RiverMesh)
		return false
	if _beach(p):                      # no trees, houses or farms on the beach (defences use their own placement)
		return false
	if in_lake(p.x, p.y):              # nor on the painted lakes
		return false
	for e in exclude:
		var c: Vector3 = e[0]
		var r: float = e[1]
		if Vector2(c.x, c.z).distance_squared_to(p) < r * r:
			return false
	return true


# ------------------------------------------------------------------ shore + obstacles
## Random shoreline points (land cells next to sea) inside a circle. Each: {"pos": Vector3, "sea": Vector3 dir}
static func find_shore(center: Vector3, radius: float, count: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var tries: int = 0
	while out.size() < count and tries < count * 40:
		tries += 1
		var a: float = rng.randf() * TAU
		var r: float = radius * sqrt(rng.randf())
		var p := Vector3(center.x + cos(a) * r, 0, center.z + sin(a) * r)
		var h: float = GroundKit.raw_y(p.x, p.z)
		if h < 0.8 or h > 12.0:
			continue
		var wd: Vector3 = GroundKit.water_dir(p, 60.0)
		if wd == Vector3.ZERO:
			continue
		out.append({"pos": Vector3(p.x, GroundKit.ground_y(p.x, p.z), p.z), "sea": wd})
	return out


## Beach defences along the shore: hedgehogs (in the surf), wire, sandbag/trench strips, optional bunkers.
static func make_beach_defences(center: Vector3, radius: float, count: int, seed_v: int, with_bunkers: bool = true) -> Node3D:
	return beach_defences_from(beach_defence_data(center, radius, count, seed_v), with_bunkers)


## The placement half of make_beach_defences: the shore search and every transform. Pure maths on the height field,
## so the site streamer runs it on a worker thread; beach_defences_from() then builds the nodes.
static func beach_defence_data(center: Vector3, radius: float, count: int, seed_v: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var pts: Array = find_shore(center, radius, count, rng)
	var hh: Array = []
	var wire: Array = []
	var bags: Array = []
	var teeth: Array = []
	var poles: Array = []
	var seawall: Array = []
	var steel: Array = []       # Belgian-gate frames (thin rusty girders)
	var trench: Array = []
	var parapet: Array = []
	var mines: Array = []
	var ruin_pts: Array = []
	for pi in pts.size():
		var d: Dictionary = pts[pi]
		var p: Vector3 = d["pos"]
		var sea: Vector3 = d["sea"]
		var perp := Vector3(-sea.z, 0, sea.x)
		var yaw_along: float = atan2(-perp.x, -perp.z)
		# concrete seawall on the back of the beach (as at Utah, Dieppe and the Normandy resorts)
		if pi % 3 == 0:
			var sp: Vector3 = p - sea * 4.0
			if GroundKit.raw_y(sp.x, sp.z) > 0.8:
				seawall.append(_xf(Vector3(sp.x, GroundKit.ground_y(sp.x, sp.z) + 0.9, sp.z), yaw_along, Vector3(36, 2.2, 1.4)))
		# Belgian gates (Cointet elements): rusty girder frames standing in the surf
		if pi % 2 == 0:
			for gk in 3:
				var gp: Vector3 = p + sea * rng.randf_range(35.0, 80.0) + perp * (float(gk) - 1.0) * rng.randf_range(9.0, 15.0)
				var gy2: float = maxf(GroundKit.raw_y(gp.x, gp.z), 0.0)
				var gyaw: float = yaw_along + rng.randf_range(-0.3, 0.3)
				var gb := Vector3(gp.x, gy2 + 1.6, gp.z)
				steel.append(_xf(gb, gyaw, Vector3(3.4, 0.22, 0.22)))
				steel.append(_xf(gb + perp * 1.7 + Vector3(0, -0.2, 0), gyaw, Vector3(0.22, 3.0, 0.22)))
				steel.append(_xf(gb - perp * 1.7 + Vector3(0, -0.2, 0), gyaw, Vector3(0.22, 3.0, 0.22)))
		# zig-zag trench with a sandbag parapet and a Tobruk pit, behind the wire
		if pi % 2 == 1:
			var tb: Vector3 = p - sea * rng.randf_range(55.0, 85.0)
			for zk in 6:
				var zp: Vector3 = tb + perp * (float(zk) - 2.5) * 5.0
				var zyaw: float = yaw_along + (0.6 if zk % 2 == 0 else -0.6)
				if GroundKit.raw_y(zp.x, zp.z) > 1.5:
					var zy: float = GroundKit.ground_y(zp.x, zp.z)
					trench.append(_xf(Vector3(zp.x, zy + 0.02, zp.z), zyaw, Vector3(6.4, 0.18, 1.5)))
					parapet.append(_xf(Vector3(zp.x + sea.x * 1.1, zy + 0.4, zp.z + sea.z * 1.1), zyaw, Vector3(6.2, 0.8, 0.7)))
		# minefield: grid of stakes behind the wire, fenced by wire
		if pi % 4 == 2:
			var mb: Vector3 = p - sea * rng.randf_range(35.0, 60.0)
			for mi in 20:
				var mp: Vector3 = mb + perp * (float(mi % 5) - 2.0) * 5.0 - sea * float(mi / 5) * 5.0
				if GroundKit.raw_y(mp.x, mp.z) > 1.0:
					mines.append(_xf(Vector3(mp.x, GroundKit.ground_y(mp.x, mp.z) + 0.45, mp.z), 0.0, Vector3(0.12, 0.9, 0.12)))
		# shell-burst ruins inland: burning buildings behind the defences
		if pi % 7 == 3:
			ruin_pts.append(p - sea * rng.randf_range(90.0, 170.0) + perp * rng.randf_range(-40.0, 40.0))
		# hedgehogs just seaward, in a loose line
		for k in 6:
			var hp: Vector3 = p + sea * rng.randf_range(12.0, 55.0) + perp * rng.randf_range(-22, 22)
			var gy: float = maxf(GroundKit.raw_y(hp.x, hp.z), 0.0)
			hh.append(_xf(Vector3(hp.x, gy, hp.z), rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.9, 1.4)))
		# barbed wire line landward
		var wp: Vector3 = p - sea * rng.randf_range(10.0, 25.0)
		wire.append(_xf(Vector3(wp.x, GroundKit.ground_y(wp.x, wp.z) + 0.9, wp.z), atan2(-perp.x, -perp.z), Vector3(42, 1.8, 0.4)))
		# a second and third wire fence, offset along the beach and further inland
		for wk in 2:
			var wp2: Vector3 = p - sea * (28.0 + float(wk) * 12.0 + rng.randf_range(0.0, 6.0)) + perp * rng.randf_range(-20.0, 20.0)
			if GroundKit.raw_y(wp2.x, wp2.z) > 1.0:
				wire.append(_xf(Vector3(wp2.x, GroundKit.ground_y(wp2.x, wp2.z) + 0.9, wp2.z), atan2(-perp.x, -perp.z) + rng.randf_range(-0.12, 0.12), Vector3(rng.randf_range(24.0, 40.0), 1.8, 0.4)))
		# a row of concrete dragon's teeth just above the tide line, and rows of tall obstacle poles behind
		var tooth_off: float = rng.randf_range(6.0, 16.0)
		for tk in 13:
			var tp: Vector3 = p + sea * tooth_off + perp * (float(tk) - 6.0) * 4.2 + sea * sin(float(tk) * 1.7) * 1.2
			if GroundKit.raw_y(tp.x, tp.z) > 0.5:
				teeth.append(_xf(Vector3(tp.x, GroundKit.ground_y(tp.x, tp.z) - 0.2, tp.z), rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.9, 1.25)))
		for tk2 in 9:
			var tp2: Vector3 = p + sea * (tooth_off + 7.0) + perp * (float(tk2) - 4.0) * 4.6 + sea * sin(float(tk2) * 2.3) * 1.4
			if GroundKit.raw_y(tp2.x, tp2.z) > 0.5:
				teeth.append(_xf(Vector3(tp2.x, GroundKit.ground_y(tp2.x, tp2.z) - 0.2, tp2.z), rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.9, 1.25)))
		for pk in 4:
			var pp: Vector3 = p - sea * (60.0 + float(pk % 2) * 14.0) + perp * (float(pk) - 1.5) * 22.0 + perp * rng.randf_range(-6.0, 6.0)
			if GroundKit.raw_y(pp.x, pp.z) > 1.5:
				poles.append(_xf(Vector3(pp.x, GroundKit.ground_y(pp.x, pp.z) - 0.3, pp.z), 0.0, Vector3.ONE * rng.randf_range(0.9, 1.2)))
		var bp: Vector3 = p - sea * rng.randf_range(30.0, 50.0)
		bags.append(_xf(Vector3(bp.x, GroundKit.ground_y(bp.x, bp.z) + 0.6, bp.z), atan2(-perp.x, -perp.z), Vector3(18, 1.2, 2.2)))
	# burning ruins inland (at most two, only where the war date shows a recent raid): [position, scale]
	var ruins: Array = []
	for rp in ruin_pts:
		if ruins.size() >= 2 or GroundKit.raw_y((rp as Vector3).x, (rp as Vector3).z) < 2.0:
			continue
		if WarDamage.level_at((rp as Vector3).x, (rp as Vector3).z) < 0.3:
			continue
		ruins.append([Vector3((rp as Vector3).x, GroundKit.ground_y((rp as Vector3).x, (rp as Vector3).z), (rp as Vector3).z), rng.randf_range(0.9, 1.4)])
	return {"pts": pts, "hh": hh, "wire": wire, "bags": bags, "teeth": teeth, "poles": poles, "seawall": seawall,
		"steel": steel, "trench": trench, "parapet": parapet, "mines": mines, "ruins": ruins}


## Build the beach defences laid out by beach_defence_data() (main thread).
static func beach_defences_from(d: Dictionary, with_bunkers: bool = true) -> Node3D:
	var root := Node3D.new()
	var pts: Array = d["pts"]
	var hh: Array = d["hh"]
	var wire: Array = d["wire"]
	var bags: Array = d["bags"]
	var teeth: Array = d["teeth"]
	var poles: Array = d["poles"]
	var seawall: Array = d["seawall"]
	var steel: Array = d["steel"]
	var trench: Array = d["trench"]
	var parapet: Array = d["parapet"]
	var mines: Array = d["mines"]
	if not hh.is_empty():
		root.add_child(multi(hedgehog_mesh(), hh, 6000.0))
	if not wire.is_empty():
		root.add_child(multi(box_unit(Color(0.12, 0.1, 0.1), false), wire, 4500.0))
	if not bags.is_empty():
		root.add_child(multi(box_unit(GroundKit.COL_SAND, false), bags, 4500.0))
	if not teeth.is_empty():
		root.add_child(multi(tooth_mesh(), teeth, 7000.0))
	if not poles.is_empty():
		root.add_child(multi(pole_mesh(), poles, 6000.0))
	if not seawall.is_empty():
		root.add_child(multi(box_unit(Color(0.62, 0.6, 0.56), true), seawall, 5500.0))
	if not steel.is_empty():
		root.add_child(multi(box_unit(Color(0.30, 0.18, 0.12), false), steel, 4500.0))
	if not trench.is_empty():
		root.add_child(multi(box_unit(Color(0.08, 0.07, 0.06), false), trench, 3500.0))
	if not parapet.is_empty():
		root.add_child(multi(box_unit(GroundKit.COL_SAND.darkened(0.15), false), parapet, 3500.0))
	if not mines.is_empty():
		root.add_child(multi(box_unit(Color(0.7, 0.12, 0.1), false), mines, 2500.0))
	for r in d["ruins"]:
		var rp: Vector3 = r[0]
		var ru: BurningRuin = BurningRuin.create(int(absf(rp.x * 7.0 + rp.z)), float(r[1]))
		ru.position = rp
		root.add_child(ru)
	if with_bunkers:
		var nb: int = mini(pts.size() / 6, 4)
		for i in nb:
			var d2: Dictionary = pts[i * 5]
			var kind: String = "bunker" if i % 2 == 0 else "pillbox"
			var s: GroundStructure = GroundStructure.create(kind, "Axis", (d2["pos"] as Vector3) - (d2["sea"] as Vector3) * 22.0, WorldCoords.dir_to_heading(d2["sea"]))
			root.add_child(s)
	return root
