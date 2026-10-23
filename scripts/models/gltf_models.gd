class_name GltfModels
extends RefCounted
## High-poly Blender-authored aircraft: tools/models/build_all.py writes assets/models/<id>.glb and this file
## loads it and rewires it onto realistic (non-toon) materials + the AircraftModels node contract.
##
## The .glb carries geometry and node names only (authored in metres by tools/models/kit.py); the finish lives
## here, so one Blender asset serves every nation's paint scheme.
##
## Materials: shaders/aircraft_pbr.gdshader with a procedural camouflage texture from
## tools/make_aircraft_camo.py (triplanar, so no UV unwrap is needed) and **no inverted-hull outline pass** -
## the aircraft are painted machines, not cel-shaded. Metal, glass, tyres and national markings use
## StandardMaterial3D so they answer the world lighting like real materials.
##
## A missing .glb returns null and AircraftModels falls back to the procedural builders, so an unfinished
## aircraft can never break a sortie.
##
## Blender builds with the nose toward +Y; the glTF export maps that onto Godot's -Z, which is what
## Aircraft.get_forward() assumes. Node contract (see scripts/aircraft_models.gd):
##   Body, Fuselage, WingL/WingR, Tailplane, Fin, Canopy (node toggled by cockpit view), CanopyFrame,
##   Pilot, Propeller > Blades + Spinner + PropDisc, GearL/GearR, MuzzleL/MuzzleR, CockpitEye,
##   DecalFus* (fuselage markings) and other Decal* (wing / fin markings).

const DIR := "res://assets/models/"
const CAMO_DIR := "res://assets/models/camo/"
const PBR_SHADER := "res://shaders/aircraft_pbr.gdshader"

## Model -> camouflage scheme (tools/make_aircraft_camo.py writes these). A missing entry falls back to the
## nation's default, so a new aircraft never renders untextured.
const CAMO := {
	"spitfire": "raf_day", "hurricane": "raf_day", "typhoon": "raf_day", "tempest": "raf_day",
	"defiant": "raf_night", "mosquito": "raf_day", "blenheim": "raf_day", "lancaster": "raf_night",
	"p51": "usaaf_od", "p47": "usaaf_od", "p38": "bare_metal", "b25": "usaaf_od", "b26": "usaaf_od",
	"a20": "usaaf_od", "c47": "usaaf_od",
	"bf109": "lw_fighter", "bf110": "lw_fighter", "fw190": "lw_fighter", "me262": "lw_fighter",
	"he111": "lw_splinter", "ju88": "lw_splinter", "ju87": "lw_splinter", "do17": "lw_splinter",
	"ju52": "lw_splinter", "fw200": "lw_splinter",
}
const CAMO_BY_NATION := {"Luftwaffe": "lw_splinter", "USAAF": "usaaf_od", "USN": "usaaf_od", "RAF": "raf_day"}

## Paint tweaks per scheme: [underside tone, roughness, metallic, sheen]. Wartime camouflage paint is matt, so the
## painted schemes are rough and barely metallic (photos show almost no sheen); bare metal is the exception.
const FINISH := {
	"raf_day": [Color(0.55, 0.58, 0.60), 0.70, 0.05, 0.0],       # Medium Sea Grey under
	"raf_night": [Color(0.12, 0.13, 0.14), 0.78, 0.03, 0.0],     # night black
	"lw_splinter": [Color(0.53, 0.62, 0.70), 0.68, 0.05, 0.0],   # RLM 65 Hellblau under
	"lw_fighter": [Color(0.56, 0.64, 0.71), 0.66, 0.05, 0.0],    # RLM 65 sides and under, mottled
	"lw_desert": [Color(0.62, 0.66, 0.70), 0.70, 0.04, 0.0],
	"usaaf_od": [Color(0.50, 0.52, 0.52), 0.70, 0.05, 0.0],      # Neutral Grey under
	"bare_metal": [Color(0.62, 0.63, 0.62), 0.30, 0.75, 0.35],
}
## Schemes that reuse another scheme's texture with a different paint layout (see scheme_mode in the shader).
const TEXTURE_OF := {}

const COL_METAL := Color(0.10, 0.10, 0.11)
const COL_TIP := Color(0.86, 0.72, 0.16)
const COL_PILOT := Color(0.36, 0.28, 0.21)
const COL_TYRE := Color(0.07, 0.07, 0.08)

static var _pbr_shader: Shader


static func path_for(model_id: String) -> String:
	return DIR + model_id + ".glb"


static func has_model(model_id: String) -> bool:
	return ResourceLoader.exists(path_for(model_id))


## Instantiate + paint the model, or null when the asset is missing / broken (caller falls back).
static func build(model_id: String, nation: String = "RAF") -> Node3D:
	var ps: PackedScene = load(path_for(model_id)) as PackedScene
	if ps == null:
		return null
	var root: Node3D = ps.instantiate() as Node3D
	if root == null:
		push_warning("GltfModels: %s did not instantiate a Node3D" % model_id)
		return null
	root.name = "Model"
	_rewire(root, model_id, nation)
	print("[models] %s from %s.glb (%s)" % [model_id, model_id, camo_for(model_id, nation)])
	return root


static func camo_for(model_id: String, nation: String) -> String:
	var c: String = String(CAMO.get(model_id, ""))
	if c != "":
		return c
	return String(CAMO_BY_NATION.get(nation, "raf_day"))


static func shader() -> Shader:
	if _pbr_shader == null:
		_pbr_shader = load(PBR_SHADER) as Shader
	return _pbr_shader


## The airframe skin: triplanar camouflage, painted underside, panel lines and grime. No outline pass.
static func make_skin(scheme: String, tint: Color = Color(1, 1, 1)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader()
	var fin: Array = FINISH.get(scheme, FINISH["raf_day"])
	m.set_shader_parameter("camo_tex", load(CAMO_DIR + String(TEXTURE_OF.get(scheme, scheme)) + ".png") as Texture2D)
	m.set_shader_parameter("scheme_mode", 1 if scheme == "lw_fighter" else 0)
	m.set_shader_parameter("underside_color", fin[0])
	m.set_shader_parameter("base_roughness", fin[1])
	m.set_shader_parameter("metallic", fin[2])
	m.set_shader_parameter("gloss", fin[3])
	m.set_shader_parameter("wear", 0.6)
	m.set_shader_parameter("under_amount", 0.85 if scheme != "raf_night" else 0.3)
	m.set_shader_parameter("tint", tint)
	return m


static func _metal(col: Color, rough: float = 0.45, met: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = met
	m.metallic_specular = 0.6
	return m


static func _paint(col: Color, rough: float = 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = 0.0
	return m


static func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.80, 0.86, 0.24)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.metallic_specular = 0.9
	return m


static func _rewire(root: Node3D, model_id: String, nation: String) -> void:
	var skin: ShaderMaterial = make_skin(camo_for(model_id, nation))
	var metal: StandardMaterial3D = _metal(COL_METAL, 0.42, 0.9)
	var dark: StandardMaterial3D = _paint(COL_METAL, 0.55)
	var glass: StandardMaterial3D = _glass()
	var blade: StandardMaterial3D = _paint(Color(0.06, 0.06, 0.07), 0.4)
	var tip: StandardMaterial3D = _paint(COL_TIP, 0.5)
	var tyre: StandardMaterial3D = _paint(COL_TYRE, 0.85)
	var pilot: StandardMaterial3D = _paint(COL_PILOT, 0.75)
	var discs: Array[Node3D] = []

	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		var nm: String = String(mi.name)
		mi.material_override = _material_for(nm, skin, metal, dark, glass, blade, tip, tyre, pilot)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if nm.begins_with("PropDisc"):
			discs.append(mi)
	# the prop blur discs are unshaded translucent plates, hidden until the blades spin too fast to draw as
	# blades (AircraftModels.prop_blur swaps them in) - so a freshly built model shows its propeller
	for d in discs:
		var mi := d as MeshInstance3D
		mi.material_override = _disc_material()
		mi.visible = false
		_add_prop_tip_ring(mi)   # the blade-tip colour on the swirl: kept at the owner's request

	if root.find_child("Pilot", true, false) == null:
		_add_pilot(root, pilot)


static func _disc_material() -> StandardMaterial3D:
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.15, 0.15, 0.15, 0.30)   # v5 value
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	return dm


## A thin translucent ring at the rim of the prop blur disc, in the blade-tip colour: the tips of the
## blades trace a faint bright circle as they spin, so the swirl is not a uniform grey plate. Parented to
## the disc, so it appears and disappears with it.
static func _add_prop_tip_ring(disc: MeshInstance3D) -> void:
	if disc.mesh == null:
		return
	var sz: Vector3 = disc.mesh.get_aabb().size
	var radius: float = maxf(maxf(sz.x, sz.y), sz.z) * 0.5
	if radius <= 0.05:
		return
	var tor := TorusMesh.new()
	tor.inner_radius = radius * 0.93
	tor.outer_radius = radius
	tor.rings = 28
	tor.ring_segments = 6
	var ring := MeshInstance3D.new()
	ring.name = "TipRing"
	ring.mesh = tor
	ring.material_override = _tip_ring_material()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the disc is thin along its own axis: put the ring in the disc's own plane
	if sz.x <= sz.y and sz.x <= sz.z:
		ring.rotation = Vector3(0.0, 0.0, PI * 0.5)
	elif sz.z <= sz.x and sz.z <= sz.y:
		ring.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	disc.add_child(ring)


static func _tip_ring_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(COL_TIP.r, COL_TIP.g, COL_TIP.b, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _material_for(nm: String, skin: ShaderMaterial, metal: StandardMaterial3D, dark: StandardMaterial3D,
		glass: StandardMaterial3D, blade: StandardMaterial3D, tip: StandardMaterial3D,
		tyre: StandardMaterial3D, pilot: StandardMaterial3D) -> Material:
	if nm.begins_with("PropDisc"):
		return dark
	if nm.begins_with("BladeTip"):
		return tip
	if nm.begins_with("Blade") or nm.begins_with("PropBlade"):
		return blade
	if nm.begins_with("CanopyGlass"):
		return glass
	if nm.begins_with("Canopy") and nm.findn("frame") >= 0:
		return dark
	if nm.begins_with("Canopy"):
		return glass
	if nm.begins_with("Pilot"):
		return pilot
	if nm.begins_with("Wheel") or nm.begins_with("Tyre"):
		return tyre
	if nm.begins_with("Decal"):
		return _decal_material(nm)
	if nm.begins_with("Gun") or nm.begins_with("Turret") or nm.begins_with("Exhaust") \
			or nm.begins_with("Muzzle") or nm.begins_with("Spinner") or nm.begins_with("Intake") \
			or nm.begins_with("Mouth") or nm.begins_with("Jet"):
		return metal
	if nm.begins_with("Strut") or nm.begins_with("Gear") or nm.begins_with("Leg"):
		return metal
	if nm.begins_with("Frame") or nm.begins_with("Windscreen") or nm.begins_with("Antenna"):
		return dark
	return skin


## National markings are flat meshes named by colour, e.g. DecalFusBlue_1 / DecalWingRed_L. Painted with a
## touch of roughness, so they sit in the lighting like the rest of the airframe.
static func _decal_material(nm: String) -> Material:
	var n: String = nm.to_lower()
	var c := Color(0.80, 0.80, 0.80)
	if n.findn("red") >= 0:
		c = Color(0.62, 0.11, 0.10)
	elif n.findn("blue") >= 0:
		c = Color(0.10, 0.16, 0.40)
	elif n.findn("yellow") >= 0:
		c = Color(0.78, 0.62, 0.14)
	elif n.findn("black") >= 0:
		c = Color(0.06, 0.06, 0.07)
	elif n.findn("green") >= 0:
		c = Color(0.12, 0.20, 0.12)
	return _paint(c, 0.62)


## Fallback head + shoulders, placed at the CockpitEye so _test_markings always finds a pilot.
static func _add_pilot(root: Node3D, mat: Material) -> void:
	var eye: Node3D = root.find_child("CockpitEye", true, false) as Node3D
	if eye == null:
		return
	var grp := Node3D.new()
	grp.name = "Pilot"
	eye.add_child(grp)
	var head := MeshInstance3D.new()
	head.name = "PilotHead"
	var sm := SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.24
	sm.radial_segments = 12
	sm.rings = 6
	head.mesh = sm
	head.material_override = mat
	head.position = Vector3(0, -0.06, 0)
	grp.add_child(head)
	var torso := MeshInstance3D.new()
	torso.name = "PilotTorso"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.42, 0.34, 0.32)
	torso.mesh = bm
	torso.material_override = mat
	torso.position = Vector3(0, -0.34, -0.06)
	grp.add_child(torso)
