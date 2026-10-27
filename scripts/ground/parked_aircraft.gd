class_name ParkedAircraft
extends RefCounted
## Parked aircraft for airfield dispersals and aprons. Instead of one generic cigar-and-wing mesh, every parked
## aircraft is the real flying model for its type (same shapes, camouflage and national markings), baked once into
## a single static mesh per type and shared. The types follow the field's side and role, so a Spitfire / Hurricane
## station looks different from a Luftwaffe Stuka field or a Lancaster bomber base.

const ALLIED_FIGHTERS := ["spitfire", "hurricane", "typhoon", "tempest", "mosquito"]
const ALLIED_US_FIGHTERS := ["p47", "p51", "p38"]
const ALLIED_BOMBERS := ["blenheim", "lancaster", "b26", "b25", "a20", "c47"]
const AXIS_FIGHTERS := ["bf109", "fw190", "bf110", "bf109"]
const AXIS_DIVE := ["ju87", "bf109", "ju87", "bf110"]
const AXIS_BOMBERS := ["he111", "ju88", "do17", "ju52", "fw200"]

static var _cache: Dictionary = {}
static var _static_shader: Shader
static var _static_mats: Dictionary = {}


## The flying skin shader carries per-instance uniforms (structural cut-aways); every mesh drawn with it reserves a
## slot in a global buffer, and a few hundred parked aircraft across the loaded airfields overflowed it. A parked
## aircraft never loses a wing in flight, so it wears the same skin with those turned into plain uniforms.
static func _static_mat(mat: Material) -> Material:
	var sm := mat as ShaderMaterial
	if sm == null or sm.shader != GltfModels.shader():
		return mat
	if _static_mats.has(sm):
		return _static_mats[sm]
	if _static_shader == null:
		_static_shader = Shader.new()
		_static_shader.code = GltfModels.shader().code.replace("instance uniform", "uniform")
	var d := ShaderMaterial.new()
	d.shader = _static_shader
	for u in sm.shader.get_shader_uniform_list():
		var nm: String = String(u["name"])
		d.set_shader_parameter(nm, sm.get_shader_parameter(nm))
	_static_mats[sm] = d
	return d


## Mesh for one aircraft type (cached). Nose at -Z, lowest point (wheels) at y = 0.
static func mesh_for(model_id: String) -> ArrayMesh:
	if _cache.has(model_id):
		return _cache[model_id]
	# the same finished model as the flying aircraft: painted livery, markings and codes
	var nation: String = "RAF"
	if model_id != "spitfire":
		var spec: Dictionary = ModelSpecs.get_spec(model_id)
		if spec.is_empty():
			return null
		nation = String(spec.get("nation", "RAF"))
	var root: Node3D = AircraftModels.build(model_id, nation)
	if root == null:
		return null
	var parts: Array = []
	_collect(root, Transform3D.IDENTITY, parts)
	# lowest vertex, so the wheels rest on the ground
	var low: float = 1.0e9
	for p in parts:
		var arrays: Array = (p[0] as Mesh).surface_get_arrays(p[1])
		var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var xf: Transform3D = p[2]
		for v in vs:
			low = minf(low, (xf * v).y)
	var lift := Transform3D(Basis(), Vector3(0.0, -low, 0.0))
	var by_mat: Dictionary = {}
	for p2 in parts:
		var mat: Material = p2[3]
		var key: int = mat.get_instance_id() if mat != null else 0
		if not by_mat.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_material(mat)
			by_mat[key] = st
		(by_mat[key] as SurfaceTool).append_from(p2[0], p2[1], lift * (p2[2] as Transform3D))
	var out := ArrayMesh.new()
	for k in by_mat:
		(by_mat[k] as SurfaceTool).commit(out)
	root.free()
	_cache[model_id] = out
	return out


static func _collect(n: Node3D, parent_xf: Transform3D, out: Array) -> void:
	if not n.visible or String(n.name).begins_with("PropDisc"):     # engines stopped: blades, not the blur disc
		return
	var t: Transform3D = parent_xf * n.transform
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var mat: Material = _static_mat(mi.material_override if mi.material_override != null else mi.get_active_material(s))
				out.append([mi.mesh, s, t, mat])
	for c in n.get_children():
		if c is Node3D:
			_collect(c as Node3D, t, out)


## Which types a field keeps: decided per airfield (stable), with the odd visitor from the same side.
static func _pick(team: String, h: int, rng: RandomNumberGenerator) -> String:
	var role: int = posmod(h, 10)
	var primary: String
	var mix: Array
	if team == "Allies":
		if role < 6:
			primary = ALLIED_FIGHTERS[posmod(h / 10, 4)]
			mix = ALLIED_FIGHTERS
		elif role < 8:
			primary = ALLIED_US_FIGHTERS[posmod(h / 10, 3)]
			mix = ALLIED_US_FIGHTERS
		else:
			primary = ALLIED_BOMBERS[posmod(h / 10, ALLIED_BOMBERS.size())]
			mix = ALLIED_BOMBERS
	else:
		if role < 5:
			primary = AXIS_FIGHTERS[posmod(h / 10, 3)]
			mix = AXIS_FIGHTERS
		elif role < 7:
			primary = AXIS_DIVE[posmod(h / 10, 2)]
			mix = AXIS_DIVE
		else:
			primary = AXIS_BOMBERS[posmod(h / 10, AXIS_BOMBERS.size())]
			mix = AXIS_BOMBERS
	if rng.randf() < 0.68:
		return primary
	return mix[rng.randi() % mix.size()]


## Places destructible parked aircraft at each transform (rotation and position are used; the old scale is ignored).
static func place(container: Node3D, xforms: Array, team: String, af: Airfield) -> void:
	var h: int = absi(hash(af.airfield_name)) if af != null else 7
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	for t in xforms:
		var id: String = _pick(team, h, rng)
		var mesh: ArrayMesh = mesh_for(id)
		if mesh == null:
			continue
		var tt: Transform3D = t
		tt.basis = tt.basis.orthonormalized()
		tt.origin.y -= 0.35
		var prop: AirfieldProp = AirfieldProp.create("parked", team, mesh, [tt])
		var bb: AABB = mesh.get_aabb()
		var span: float = maxf(bb.size.x, bb.size.z)
		prop.hit_radius = maxf(prop.hit_radius, span * 0.5 + 1.5)
		prop.max_health *= clampf(span / 12.0, 1.0, 3.0)     # a heavy bomber takes more killing than a fighter
		container.add_child(prop)
