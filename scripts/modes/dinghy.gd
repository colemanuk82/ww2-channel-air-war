class_name Dinghy
extends Node3D
## A ditched airman in a yellow rubber dinghy: bobbing on the swell, a patch of green sea-marker dye spreading
## round him, and a drifting orange smoke flare so he can be spotted from the air (OpsRoom "rescue" tasking).

var _t: float = 0.0
var _smoke_t: float = 0.0
var drift: Vector3 = Vector3.ZERO   # set by DitchRescue: the tide and wind carry the dinghy along the sea
var _boat: Node3D


func _ready() -> void:
	var dye := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 22.0
	dm.bottom_radius = 22.0
	dm.height = 0.05
	dm.radial_segments = 24
	dye.mesh = dm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.25, 0.85, 0.45, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = -50          # over the sea (which draws first), under spray
	dye.material_override = mat
	dye.position = Vector3(0, 0.15, 0)
	dye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dye)
	_boat = Node3D.new()
	add_child(_boat)
	var ring := ToonUtil.make_mesh(TorusMesh.new(), Color(0.98, 0.78, 0.10), {"outline": false})
	var tm := ring.mesh as TorusMesh
	tm.inner_radius = 0.75
	tm.outer_radius = 1.35
	ring.scale = Vector3(1.0, 1.4, 1.3)
	_boat.add_child(ring)
	var floor_m := ToonUtil.make_mesh(CylinderMesh.new(), Color(0.85, 0.65, 0.08), {"outline": false})
	(floor_m.mesh as CylinderMesh).top_radius = 0.9
	(floor_m.mesh as CylinderMesh).bottom_radius = 0.9
	(floor_m.mesh as CylinderMesh).height = 0.1
	floor_m.position = Vector3(0, -0.15, 0)
	_boat.add_child(floor_m)
	# the airman: Mae West life jacket, flying helmet
	var body := ToonUtil.make_mesh(BoxMesh.new(), Color(0.95, 0.75, 0.15), {"outline": false})
	(body.mesh as BoxMesh).size = Vector3(0.45, 0.55, 0.3)
	body.position = Vector3(0, 0.35, 0)
	_boat.add_child(body)
	var head := ToonUtil.make_mesh(SphereMesh.new(), Color(0.35, 0.25, 0.18), {"outline": false})
	(head.mesh as SphereMesh).radius = 0.13
	(head.mesh as SphereMesh).height = 0.26
	head.position = Vector3(0, 0.75, 0)
	_boat.add_child(head)
	_boat.scale = Vector3.ONE * 1.6       # a touch larger than life so it can be found from the air


func _process(delta: float) -> void:
	_t += delta
	global_position += drift * delta
	_boat.position.y = 0.25 + sin(_t * 1.3) * 0.25
	_boat.rotation.z = sin(_t * 0.9) * 0.12
	_boat.rotation.x = sin(_t * 1.1 + 1.0) * 0.1
	_smoke_t -= delta
	if _smoke_t <= 0.0:
		_smoke_t = 0.12
		var p: Vector3 = global_position + Vector3(1.5, 1.2, 0.0)
		FX.puffs.spawn(p, Vector3(randf_range(2.0, 4.0), randf_range(3.0, 5.0), randf_range(-1.0, 1.0)), randf_range(6.0, 9.0),
			1.5, 14.0, Color(1.0, 0.45, 0.08, 0.85), Color(1.0, 0.62, 0.3, 0.0), 0.5, 0.0, 0.25)
