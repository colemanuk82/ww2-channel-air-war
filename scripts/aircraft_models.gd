class_name AircraftModels
extends RefCounted
## Factory for procedural aircraft models. Add new models by extending `build`
## (or add a spec to ModelSpecs for the data-driven PlaneBuilder).
## Every model must return a Node3D "Model" (faces -Z) and ideally provide these child nodes:
##   "Propeller" (spins around Z), "GearL"/"GearR" (retractable pivots), "Canopy",
##   "MuzzleL"/"MuzzleR" (Node3D marker positions for guns), "CockpitEye" (pilot eye point).


static func build(model_id: String, nation: String = "RAF") -> Node3D:
	# Building a procedural airframe costs 70-250 ms of main-thread time, which was the hitch every time an
	# aircraft appeared (worst in dogfights, where a wave spawns at once). Each type is built once into a
	# prototype and every aircraft after that is a copy of it (a few ms: meshes and materials are shared).
	var proto: Node3D = prototype(model_id, nation)
	if proto == null:
		return null
	var m: Node3D = proto.duplicate() as Node3D
	apply_historical_markings(m, GameState.historical_markings)
	return m


static var _protos: Dictionary = {}


## The finished model for a type (built on first use, then kept). Never add it to the tree: build() copies it.
static func prototype(model_id: String, nation: String) -> Node3D:
	var key: String = model_id + "|" + nation
	if _protos.has(key) and is_instance_valid(_protos[key]):
		return _protos[key]
	var model: Node3D = _build_raw(model_id, nation)
	if model == null:
		return null
	_make_realistic(model, model_id, nation)
	_protos[key] = model
	return model


## Frees the kept prototypes (at quit, so nothing is reported as leaked).
static func free_prototypes() -> void:
	for k in _protos:
		if is_instance_valid(_protos[k]):
			(_protos[k] as Node).free()
	_protos.clear()


static func has_prototype(model_id: String, nation: String) -> bool:
	return _protos.has(model_id + "|" + nation)


## Every flyable type's (model, nation), the player's own and their enemies' first: what the loading screen
## builds ahead of time so no aircraft has to be built in flight.
static func warm_list(player_id: String, player_side: String) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var later: Array = []
	for f in DirAccess.get_files_at("res://data/aircraft/"):
		var fn: String = f.trim_suffix(".remap")
		if not fn.ends_with(".tres"):
			continue
		var st: AircraftStats = load("res://data/aircraft/" + fn) as AircraftStats
		if st == null:
			continue
		var k: String = st.model_id + "|" + st.nation
		if seen.has(k):
			continue
		seen[k] = true
		var item: Array = [st.model_id, st.nation]
		if fn.get_basename() == player_id:
			out.push_front(item)
		elif not AircraftCatalog.ids_for_side(player_side).has(fn.get_basename()):
			out.append(item)
		else:
			later.append(item)
	out.append_array(later)
	return out


## Replaces the cel-shaded (toon + inverted-hull outline) materials with painted-metal ones, without
## touching any shape: the airframe gets the triplanar camouflage skin (shaders/aircraft_pbr.gdshader),
## every other toon part (dark metal, blades, lights) a plain lit material, and the outline pass is
## dropped. The prop-blur disc gets a thin ring in the blade-tip colour so the swirl shows the tips.
static func _make_realistic(root: Node3D, model_id: String, nation: String) -> void:
	var toon: Shader = ToonUtil.toon_shader()
	var skin: ShaderMaterial = null
	var plain: Dictionary = {}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		var m: ShaderMaterial = mi.material_override as ShaderMaterial
		if m == null or m.shader != toon:
			if String(mi.name).begins_with("PropDisc"):
				_add_tip_ring(mi)
			continue
		var dmode: Variant = m.get_shader_parameter("detail_mode")
		if dmode != null and int(dmode) == 5:
			if skin == null:
				skin = GltfModels.make_skin(GltfModels.camo_for(model_id, nation))
			mi.material_override = skin
			continue
		var alb: Variant = m.get_shader_parameter("albedo")
		var col: Color = alb if alb != null else Color(0.5, 0.5, 0.5)
		var em: Variant = m.get_shader_parameter("emission_color")
		# markings are matt paint like the camouflage under them, not shiny plastic
		var dpar: Node = mi.get_parent()
		var decal: bool = String(mi.name).contains("Decal") or (dpar != null and String(dpar.name).contains("Decal"))
		var key: String = "%s|%s|%s" % [col.to_html(), str(em), str(decal)]
		if decal and (em == null or Color(em) == Color(0, 0, 0, 1) or Color(em) == Color(0, 0, 0, 0)):
			# markings: matt paint drawn a hair towards the camera, so the curved wing / fuselage skin can never
			# cut through a roundel, cross or code (shaders/decal_paint.gdshader)
			if not plain.has(key):
				var dm := ShaderMaterial.new()
				dm.shader = load("res://shaders/decal_paint.gdshader") as Shader
				dm.set_shader_parameter("albedo", col)
				dm.set_shader_parameter("roughness_v", 0.78)
				plain[key] = dm
			mi.material_override = plain[key]
			continue
		if not plain.has(key):
			var sm := StandardMaterial3D.new()
			sm.albedo_color = col
			sm.roughness = 0.78 if decal else 0.5
			sm.metallic = 0.02 if decal else 0.25
			if em != null and Color(em) != Color(0, 0, 0, 1) and Color(em) != Color(0, 0, 0, 0):
				sm.emission_enabled = true
				sm.emission = Color(em)
				var ee: Variant = m.get_shader_parameter("emission_energy")
				sm.emission_energy_multiplier = float(ee) if ee != null else 1.0
			plain[key] = sm
		mi.material_override = plain[key]
	# the painted livery texture (assets/liveries), with the markings and codes painted in, when there is one
	Livery.apply(root, model_id, nation, skin)
	apply_historical_markings(root, GameState.historical_markings)


## Show or hide the swastika on Luftwaffe fins (and the white disc it sits on) under `root`, following the
## "Historical markings" setting. These stay separate meshes, never painted into the livery, so they can be
## switched off; with them off the fin is left in its camouflage.
static func apply_historical_markings(root: Node, on: bool) -> void:
	if root == null:
		return
	for n in root.find_children("DecalFin*", "Node3D", true, false):
		var nm: String = String(n.name)
		if nm.contains("Swastika") or nm.contains("FinDisc"):
			(n as Node3D).visible = on


const TIP_COL := Color(0.86, 0.72, 0.16)


static func _add_tip_ring(disc: MeshInstance3D) -> void:
	var cm := disc.mesh as CylinderMesh
	if cm == null:
		return
	# Flat soft-edged annulus (alpha fades to nothing inward): no overlapping faces, so nothing to shimmer
	var r1: float = cm.top_radius
	var r0: float = r1 * 0.78
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = 120
	for k in n:
		var a0: float = TAU * float(k) / float(n)
		var a1: float = TAU * float(k + 1) / float(n)
		var p0i := Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var p0o := Vector3(cos(a0) * r1, 0, sin(a0) * r1)
		var p1i := Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		var p1o := Vector3(cos(a1) * r1, 0, sin(a1) * r1)
		for tri in [[p0i, p0o, p1o, 0.0, 1.0, 1.0], [p0i, p1o, p1i, 0.0, 1.0, 0.0]]:
			for q in 3:
				st.set_color(Color(1, 1, 1, float(tri[3 + q])))
				st.add_vertex(tri[q])
	var ring := MeshInstance3D.new()
	ring.name = "TipRing"
	ring.mesh = st.commit()
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(TIP_COL.r, TIP_COL.g, TIP_COL.b, 0.07)
	rm.vertex_color_use_as_albedo = true
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.add_child(ring)          # same axis as the disc cylinder, so it lies in the disc plane


static func _build_raw(model_id: String, nation: String = "RAF") -> Node3D:
	if model_id == "spitfire":
		return SpitfireModel.build(nation)
	var spec: Dictionary = ModelSpecs.get_spec(model_id)
	if not spec.is_empty():
		return PlaneBuilder.build(spec, nation)
	push_warning("AircraftModels: unknown model '%s', using spitfire" % model_id)
	return SpitfireModel.build(nation)


## Propeller stroboscope guard. A propeller turning fast enough to advance more than this much in one frame
## cannot be drawn as blades at all: the three blades land on an unrelated angle every frame, so the prop
## stroboscopes and reads as the whole nose shaking (worst in the cockpit view, where it fills the screen).
## Past the limit the discrete blades are swapped for the translucent PropDisc blur, which is what a real
## fast prop looks like from the front. Frame-rate aware, so a prop still shows blades at high frame rates.
const PROP_STEP_LIMIT: float = 0.5236     # radians of spin per frame (30 deg) beyond which the blades strobe


static func prop_blur(rate: float, delta: float, was_blurred: bool = false) -> bool:
	# Hysteresis: once blurred, stay blurred until the spin drops well below the limit, so frame-time
	# jitter near the threshold cannot flip blades/disc (and the tip ring) on and off like a light.
	var step: float = rate * delta
	if was_blurred:
		return step > PROP_STEP_LIMIT * 0.6
	return step > PROP_STEP_LIMIT
