class_name ParkedAircraft
extends RefCounted
## Parked aircraft for airfield dispersals and aprons. Instead of one generic cigar-and-wing mesh, every parked
## aircraft is the real flying model for its type (same shapes, camouflage and national markings), baked once into
## a single static mesh per type and shared. The types follow the field's side and role, so a Spitfire / Hurricane
## station looks different from a Luftwaffe Stuka field or a Lancaster bomber base.

const ALLIED_FIGHTERS := ["spitfire", "hurricane", "typhoon", "tempest", "mosquito"]
const ALLIED_US_FIGHTERS := ["p47", "p51", "p38"]
const ALLIED_BOMBERS := ["blenheim", "lancaster", "b26", "b25", "a20", "c47"]
## The war the ground is built for shifts what sits on the ordinary fighter fields: 1940 squadrons fly
## Spitfires and Hurricanes against the 109, by 1944 Tempests and Mustangs against the 190.
const ALLIED_FIGHTERS_EARLY := ["spitfire", "hurricane"]
const ALLIED_FIGHTERS_LATE := ["tempest", "p51", "spitfire"]
const AXIS_FIGHTERS := ["bf109", "fw190", "bf110", "bf109"]
const AXIS_FIGHTERS_EARLY := ["bf109"]
const AXIS_FIGHTERS_LATE := ["fw190", "bf109"]
const AXIS_DIVE := ["ju87", "bf109", "ju87", "bf110"]
const AXIS_BOMBERS := ["he111", "ju88", "do17", "ju52", "fw200"]
## What a bomber station, a night-fighter squadron, an American ALG and a glider strip keep. Only ids that
## exist in data/aircraft/ (lancaster, blenheim, b26, b25, a20, mosquito, bf110, p47, p51, c47 all do;
## no Stirling or Halifax model exists in the project, so Lancaster stations mix in the mediums).
const RAF_BOMBER_LATE := ["lancaster", "b26", "b25", "a20"]
const RAF_BOMBER_EARLY := ["blenheim", "a20"]
const NIGHT_FIGHTER := {"Allies": ["mosquito"], "Axis": ["bf110"]}
const USAF_ALG := ["p47", "p51", "c47"]
const LW_FLIEGERHORST_EARLY := ["bf109", "ju87", "he111"]
const LW_FLIEGERHORST_LATE := ["fw190", "bf109", "ju88"]

static var _cache: Dictionary = {}
static var _far_cache: Dictionary = {}

## Distance LOD: the full baked model (itself carrying engine mesh-LODs, LodCull.with_lods) is drawn only this close;
## beyond it a ~200-triangle stand-in built from the type's ModelSpecs dimensions and colours takes over, out to
## AirfieldProp.VIS_RANGE["parked"]. A baked parked model is 24k-50k triangles, so a field of twenty in view cost
## more than the rest of the scenery around it.
const NEAR_END: float = 700.0
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


## Loading-screen jobs: every parked type's mesh, so an airfield coming into view builds none in flight.
static func warm_jobs() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for lst in [ALLIED_FIGHTERS, ALLIED_US_FIGHTERS, ALLIED_BOMBERS, AXIS_FIGHTERS, AXIS_DIVE, AXIS_BOMBERS]:
		for id in lst:
			if not seen.has(id):
				seen[id] = true
				out.append(Callable(ParkedAircraft, "far_mesh_for").bind(String(id)))    # bakes mesh_for(id) too
	return out


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
	out = LodCull.with_lods(out)
	_cache[model_id] = out
	return out


## The far stand-in for one type (cached): fuselage, wings, tailplane, fin(s), engine nacelles and gear legs from the
## type's ModelSpecs, in its camouflage top / underside colours, scaled to the baked model's span and seated on the
## same ground line (wheels at y = 0, nose at -Z), so the swap at NEAR_END does not jump. No outline pass.
static func far_mesh_for(model_id: String) -> ArrayMesh:
	if _far_cache.has(model_id):
		return _far_cache[model_id]
	var near: ArrayMesh = mesh_for(model_id)
	if near == null:
		return null
	var nb: AABB = near.get_aabb()
	var spec: Dictionary = ModelSpecs.get_spec(model_id)
	var top: Color = ModelSpecs.RAF_TOP
	var under: Color = ModelSpecs.RAF_UNDER
	var parts: Array = []
	if spec.has("fus") and spec.has("wing"):
		var cols: Dictionary = spec.get("colors", {})
		top = cols.get("top", top)
		under = cols.get("under", under)
		_spec_parts(spec, top, under, parts)
	else:
		_generic_parts(nb, top, under, parts)
	var raw: ArrayMesh = GroundKit.combine(parts)
	var rb: AABB = raw.get_aabb()
	# uniform fit on the span, centred on the baked model in x / z, fin tops level (the baked model's lowest point
	# is its wheels, which the spec shapes leave out: the legs are added below, after the fit)
	var k: float = nb.size.x / maxf(rb.size.x, 0.1)
	var c_n := Vector3(nb.position.x + nb.size.x * 0.5, 0.0, nb.position.z + nb.size.z * 0.5)
	var c_r := Vector3(rb.position.x + rb.size.x * 0.5, 0.0, rb.position.z + rb.size.z * 0.5) * k
	var dy: float = (nb.position.y + nb.size.y) - (rb.position.y + rb.size.y) * k
	if rb.position.y * k + dy < 0.0:
		dy = -rb.position.y * k            # never below the ground
	var fit := Transform3D(Basis.from_scale(Vector3.ONE * k), Vector3(c_n.x - c_r.x, dy, c_n.z - c_r.z))
	var fitted: Array = []
	for i in raw.get_surface_count():
		fitted.append([raw, i, fit, raw.surface_get_material(i)])
	# gear legs from the fitted belly down to the ground, under the wing a little ahead of the centre of mass
	var belly: float = maxf(rb.position.y * k + dy, 0.4)
	var gx: float = nb.size.x * 0.12
	var gz: float = nb.position.z + nb.size.z * 0.38
	var legs: Array = []
	for sx in [-1.0, 1.0]:
		legs.append(GroundKit.box_part(Vector3(0.35 * maxf(k, 1.0), belly, 0.35 * maxf(k, 1.0)), Vector3(c_n.x + sx * gx, belly * 0.5, gz), Color(0.12, 0.12, 0.12), Vector3.ZERO, false))
	var leg_mesh: ArrayMesh = GroundKit.combine(legs)
	for i2 in leg_mesh.get_surface_count():
		fitted.append([leg_mesh, i2, Transform3D.IDENTITY, leg_mesh.surface_get_material(i2)])
	var by_mat: Dictionary = {}
	for f in fitted:
		var mat: Material = f[3]
		var key: int = mat.get_instance_id() if mat != null else 0
		if not by_mat.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_material(mat)
			by_mat[key] = st
		(by_mat[key] as SurfaceTool).append_from(f[0], int(f[1]), f[2])
	var out := ArrayMesh.new()
	for key2 in by_mat:
		(by_mat[key2] as SurfaceTool).commit(out)
	_far_cache[model_id] = out
	return out


static func _tube(r_front: float, r_back: float, length: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_back
	c.bottom_radius = r_front
	c.height = length
	c.radial_segments = 6
	c.rings = 1
	return c


## Low-poly airframe from a PlaneBuilder spec (metres, nose -Z): one piece per feature, camouflage on top.
static func _spec_parts(spec: Dictionary, top: Color, under: Color, parts: Array) -> void:
	var fus: Dictionary = spec["fus"]
	var z0: float = float(fus.get("z0", -4.0))
	var z1: float = float(fus.get("z1", 5.0))
	var hw: float = float(fus.get("hw", 0.6))
	var hh: float = float(fus.get("hh", 0.8))
	var cy: float = float(fus.get("cy", 0.0))
	var flen: float = z1 - z0
	# a cylinder's axis is +Y: rotated +90 deg about X its bottom (front radius) faces -Z, the nose
	var along := Basis.from_euler(Vector3(deg_to_rad(90.0), 0.0, 0.0))
	var oval := Basis.from_scale(Vector3(1.0, hh / maxf(hw, 0.05), 1.0))
	var body: Material = GroundKit.mat(top, false)
	parts.append([_tube(hw, hw * 0.3, flen * 0.8), Transform3D(oval * along, Vector3(0.0, cy, z0 + flen * 0.6)), body])
	parts.append([_tube(hw * 0.5, hw, flen * 0.2), Transform3D(oval * along, Vector3(0.0, cy, z0 + flen * 0.1)), body])
	# wings: camouflage on top, a thin pale underside slab
	var w: Dictionary = spec["wing"]
	var half: float = float(w.get("half", 5.0))
	var chord: float = (float(w.get("cr", 2.0)) + float(w.get("ct", 1.0))) * 0.5
	var wy: float = float(w.get("y", 0.0))
	var wz: float = float(w.get("le_z", -1.0)) + float(w.get("cr", 2.0)) * 0.5 + float(w.get("sweep", 0.0)) * 0.5
	var th: float = maxf(float(w.get("thick", 0.14)) * chord * 0.6, 0.12)
	parts.append(GroundKit.box_part(Vector3(half * 2.0, th, chord), Vector3(0.0, wy + th * 0.5, wz), top, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(half * 2.0, 0.04, chord * 0.98), Vector3(0.0, wy - 0.02, wz), under, Vector3.ZERO, false))
	if spec.has("tail"):
		var t: Dictionary = spec["tail"]
		var tc: float = (float(t.get("cr", 1.4)) + float(t.get("ct", 0.8))) * 0.5
		parts.append(GroundKit.box_part(Vector3(float(t.get("span", 3.0)), 0.12, tc), Vector3(0.0, float(t.get("y", 0.2)), float(t.get("z", z1 - 1.0)) + tc * 0.3), top, Vector3.ZERO, false))
	if spec.has("fin"):
		var f: Dictionary = spec["fin"]
		var fc: float = (float(f.get("cr", 1.6)) + float(f.get("ct", 0.9))) * 0.5
		var fh: float = float(f.get("h", 1.8))
		var xs: Array = [0.0]
		if bool(f.get("twin", false)):
			xs = [-float(f.get("x", 1.5)), float(f.get("x", 1.5))]
		for fx in xs:
			parts.append(GroundKit.box_part(Vector3(0.14, fh, fc), Vector3(float(fx), float(f.get("y", 0.3)) + fh * 0.5, float(f.get("z", z1 - 1.0)) + fc * 0.3), top, Vector3.ZERO, false))
	var nac_mat: Material = GroundKit.mat(top.darkened(0.08), false)
	for e in spec.get("engines", []):
		var ed: Dictionary = e
		var r: float = float(ed.get("r", 0.6))
		var ez0: float = float(ed.get("z0", -2.0))
		var ez1: float = float(ed.get("z1", 1.0))
		parts.append([_tube(r, r * 0.6, ez1 - ez0), Transform3D(along, Vector3(float(ed.get("x", 0.0)), float(ed.get("y", 0.0)), (ez0 + ez1) * 0.5)), nac_mat])


## No spec (the Spitfire is a glb only): a generic single-engined fighter shape in the baked model's box.
static func _generic_parts(nb: AABB, top: Color, under: Color, parts: Array) -> void:
	var span: float = nb.size.x
	var ln: float = nb.size.z
	var zc: float = nb.position.z + ln * 0.5
	var r: float = ln * 0.055
	var along := Basis.from_euler(Vector3(deg_to_rad(90.0), 0.0, 0.0))
	parts.append([_tube(r, r * 0.3, ln * 0.95), Transform3D(along, Vector3(0.0, 0.0, zc)), GroundKit.mat(top, false)])
	parts.append(GroundKit.box_part(Vector3(span, 0.16, ln * 0.2), Vector3(0.0, -r * 0.4, zc - ln * 0.12), top, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(span, 0.04, ln * 0.19), Vector3(0.0, -r * 0.4 - 0.1, zc - ln * 0.12), under, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(span * 0.32, 0.1, ln * 0.12), Vector3(0.0, 0.0, zc + ln * 0.4), top, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.14, nb.size.y * 0.45, ln * 0.13), Vector3(0.0, nb.size.y * 0.2, zc + ln * 0.4), top, Vector3.ZERO, false))


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


## Which types a field keeps: decided per airfield (stable), with the odd visitor from the same side. The
## field's style (af.style, threaded from place()) specialises the mix - a bomber station parks bombers, an
## ALG Thunderbolts and Mustangs, a night-fighter field Mosquitos or 110s - and the era shifts the ordinary
## fighter lists. Unclassified fields use the plain hash fallback.
static func _pick(team: String, h: int, rng: RandomNumberGenerator, style: String = "") -> String:
	var role: int = posmod(h, 10)
	var primary: String
	var mix: Array
	var late: bool = EraClock.band() in ["buildup", "liberation", "1945"]
	match style:
		"raf_bomber":
			mix = RAF_BOMBER_EARLY if not late else RAF_BOMBER_LATE
			primary = mix[posmod(h / 10, mix.size())]
		"raf_satellite":
			mix = ALLIED_FIGHTERS_EARLY if not late else ["spitfire", "tempest", "p51"]
			primary = mix[posmod(h / 10, mix.size())]
		"night_fighter":
			mix = NIGHT_FIGHTER.get(team, NIGHT_FIGHTER["Allies"])
			primary = mix[posmod(h / 10, mix.size())]
		"usaf_alg":
			mix = USAF_ALG
			primary = mix[posmod(h / 10, 3)]
		"lw_fliegerhorst":
			mix = LW_FLIEGERHORST_EARLY if not late else LW_FLIEGERHORST_LATE
			primary = mix[posmod(h / 10, mix.size())]
		"glider_strip":
			mix = ["c47"]                     # the tugs wait beside the gliders
			primary = "c47"
		_:
			if team == "Allies":
				if role < 6:
					mix = ALLIED_FIGHTERS_EARLY if not late else ALLIED_FIGHTERS_LATE
					primary = mix[posmod(h / 10, mix.size())]
				elif role < 8:
					primary = ALLIED_US_FIGHTERS[posmod(h / 10, 3)]
					mix = ALLIED_US_FIGHTERS
				else:
					primary = ALLIED_BOMBERS[posmod(h / 10, ALLIED_BOMBERS.size())]
					mix = ALLIED_BOMBERS
			else:
				if role < 5:
					mix = AXIS_FIGHTERS_EARLY if not late else AXIS_FIGHTERS_LATE
					primary = mix[posmod(h / 10, mix.size())]
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
		var id: String = _pick(team, h, rng, af.style if af != null else "")
		var mesh: ArrayMesh = mesh_for(id)
		if mesh == null:
			continue
		var tt: Transform3D = t
		tt.basis = tt.basis.orthonormalized()
		tt.origin.y -= 0.35
		if af != null:
			af.parked_spots.append(Vector3(tt.origin.x, 0.0, tt.origin.z))   # the player's taxi spawn keeps clear of these
		var prop: AirfieldProp = AirfieldProp.create("parked", team, mesh, [tt])
		prop.far_mesh = far_mesh_for(id)
		prop.near_end = NEAR_END
		var bb: AABB = mesh.get_aabb()
		var span: float = maxf(bb.size.x, bb.size.z)
		prop.hit_radius = maxf(prop.hit_radius, span * 0.5 + 1.5)
		prop.max_health *= clampf(span / 12.0, 1.0, 3.0)     # a heavy bomber takes more killing than a fighter
		container.add_child(prop)
