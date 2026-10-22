class_name ContrailRibbon
extends MeshInstance3D
## A solid white contrail: a ribbon laid down in world space behind a high-flying aircraft. Points fade with age,
## and the ribbon is rebuilt about 15 times a second so it stays cheap for several aircraft at once.

var life: float = 22.0      # seconds a point stays in the trail (a bomber stream sets it longer)
const STEP := 7.0           # metres of flight between samples
const WIDTH := 2.6          # ribbon width in metres
const REBUILD_S := 0.066

var _pts: PackedVector3Array = PackedVector3Array()
var _age: PackedFloat32Array = PackedFloat32Array()
var _str: PackedFloat32Array = PackedFloat32Array()
var _rb: float = 0.0
var _mesh: ArrayMesh = ArrayMesh.new()
var _mat: StandardMaterial3D


func _ready() -> void:
	top_level = true            # points are in world space
	mesh = _mesh
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.disable_receive_shadows = true
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Lay down a point at world position `p`. `strength` 0..1 sets how opaque the trail is (0 at low altitude).
func add_point(p: Vector3, strength: float) -> void:
	var n: int = _pts.size()
	if n == 0 or _pts[n - 1].distance_to(p) >= STEP:
		_pts.append(p)
		_age.append(0.0)
		_str.append(strength)


func _process(delta: float) -> void:
	var n: int = _pts.size()
	if n == 0:
		return
	for i in n:
		_age[i] += delta
	var drop: int = 0
	while drop < n and _age[drop] > life:
		drop += 1
	if drop > 0:
		_pts = _pts.slice(drop)
		_age = _age.slice(drop)
		_str = _str.slice(drop)
	_rb -= delta
	if _rb <= 0.0:
		_rb = REBUILD_S
		_rebuild()


func _rebuild() -> void:
	var n: int = _pts.size()
	if n < 2:
		_mesh.clear_surfaces()
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam != null else Vector3.ZERO
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(n * 2)
	cols.resize(n * 2)
	for i in n:
		var p: Vector3 = _pts[i]
		var a: float = clampf(1.0 - _age[i] / life, 0.0, 1.0)
		a = a * a * _str[i]         # the fade stays solid for most of the trail, then thins at the end
		var dir: Vector3 = _pts[mini(i + 1, n - 1)] - _pts[maxi(i - 1, 0)]
		var side: Vector3 = dir.cross(eye - p)
		if side.length_squared() < 0.000001:
			side = Vector3.UP
		side = side.normalized() * (WIDTH * 0.5)
		var c := Color(0.97, 0.98, 1.0, 0.85 * a)
		verts[i * 2] = p - side
		verts[i * 2 + 1] = p + side
		cols[i * 2] = c
		cols[i * 2 + 1] = c
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
