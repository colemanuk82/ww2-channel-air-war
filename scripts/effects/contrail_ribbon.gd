class_name ContrailRibbon
extends MeshInstance3D
## A solid white contrail: a ribbon laid down in world space behind a high-flying aircraft. Points fade with age,
## and the ribbon is rebuilt about 15 times a second so it stays cheap for several aircraft at once.

var life: float = 44.0      # seconds a point stays in the trail (a bomber stream sets it longer)
const STEP := 7.0           # metres of flight between samples
const WIDTH := 2.6          # ribbon width in metres
const MIN_PX_W := 0.0011    # half-width per metre of camera distance: keeps a far trail at least ~2 px wide
const REBUILD_S := 0.066
const IDLE_REBUILD_S := 0.25   # no fresh points (out of range): fade the existing trail at a quarter of the cost
const MAX_POINTS := 2200       # hard bound per ribbon (a warp or a very fast aircraft can never grow it forever)
const SOFT_POINTS := 1800
const MAX_HALF_W := 48.0       # farthest the distance-widening may take the ribbon half-width

var _pts: PackedVector3Array = PackedVector3Array()
var _age: PackedFloat32Array = PackedFloat32Array()
var _str: PackedFloat32Array = PackedFloat32Array()
var _rb: float = 0.0
var _dirty: bool = false
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
	if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
		return
	var n: int = _pts.size()
	if n == 0 or _pts[n - 1].distance_to(p) >= STEP:
		_pts.append(p)
		_age.append(0.0)
		_str.append(strength)
		_dirty = true
		if _pts.size() > MAX_POINTS:
			var cut: int = _pts.size() - SOFT_POINTS
			_pts = _pts.slice(cut)
			_age = _age.slice(cut)
			_str = _str.slice(cut)


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
		var far: bool = false
		var m: int = _pts.size()
		if m > 0 and is_inside_tree():
			var cam: Camera3D = get_viewport().get_camera_3d()
			if cam != null:
				var eye: Vector3 = cam.global_position
				far = minf(eye.distance_squared_to(_pts[0]), eye.distance_squared_to(_pts[m - 1])) > 14000.0 * 14000.0
		_rb = REBUILD_S if _dirty and not far else IDLE_REBUILD_S
		_dirty = false
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
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			_pts.clear()
			_age.clear()
			_str.clear()
			_mesh.clear_surfaces()
			return
		var a: float = clampf(1.0 - _age[i] / life, 0.0, 1.0)
		a = a * a * _str[i]         # the fade stays solid for most of the trail, then thins at the end
		var dir: Vector3 = _pts[mini(i + 1, n - 1)] - _pts[maxi(i - 1, 0)]
		var side: Vector3 = dir.cross(eye - p)
		if side.length_squared() < 0.000001:
			side = Vector3.UP
		# widen with distance so the trail does not shrink below a pixel and vanish when read from far off
		var half_w: float = minf(maxf(WIDTH * 0.5, eye.distance_to(p) * MIN_PX_W), MAX_HALF_W)
		side = side.normalized() * half_w
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
