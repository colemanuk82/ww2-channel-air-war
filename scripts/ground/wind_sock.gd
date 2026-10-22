class_name WindSock
extends Node3D
## Airfield wind sock that actually shows the wind: it swings round to stream downwind, fills out and lifts
## toward horizontal as the wind rises, hangs limp in a calm, and flutters. Origin = top of the pole.

const COLOR := Color(0.95, 0.45, 0.12)
const STRIPE := Color(0.95, 0.93, 0.88)
var _pivot: Node3D
var _segs: Array = []
var _t: float = 0.0
var _yaw: float = 0.0
var _lift: float = 0.0
var _acc: float = 0.0


func _ready() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	# five tapering segments, alternating orange / white like the real thing
	for i in 5:
		var cm := CylinderMesh.new()
		var r0: float = 1.0 - float(i) * 0.15
		cm.top_radius = r0 - 0.15
		cm.bottom_radius = r0
		cm.height = 1.1
		cm.radial_segments = 10
		var mi := ToonUtil.make_mesh(cm, STRIPE if i % 2 == 1 else COLOR, {"outline": false})
		var holder := Node3D.new()
		holder.add_child(mi)
		mi.rotation.z = deg_to_rad(-90.0)      # cylinder axis along +X (downwind)
		mi.position = Vector3(0.55, 0.0, 0.0)
		if _segs.is_empty():
			_pivot.add_child(holder)
		else:
			(_segs[-1] as Node3D).add_child(holder)
			holder.position = Vector3(1.1, 0.0, 0.0)
		_segs.append(holder)
	var ring := ToonUtil.make_mesh(TorusMesh.new(), Color(0.3, 0.3, 0.3), {"outline": false})
	(ring.mesh as TorusMesh).inner_radius = 0.95
	(ring.mesh as TorusMesh).outer_radius = 1.08
	ring.rotation.z = deg_to_rad(90.0)
	_pivot.add_child(ring)


func _process(delta: float) -> void:
	_t += delta
	_acc += delta
	if _acc > 0.2:
		_acc = 0.0
		var w: Vector3 = WeatherManager.get_wind(global_position) if WeatherManager.has_method("get_wind") else Vector3.ZERO
		w.y = 0.0
		var spd: float = w.length()
		if spd > 0.05:
			# world yaw that points local +X downwind
			_yaw = lerp_angle(_yaw, atan2(-w.z, w.x) - get_parent_node_3d().global_rotation.y, 0.25)
		# limp below ~2, full out by ~10 world units/s (a ~20 kt wind)
		_lift = lerpf(_lift, clampf((spd - 1.0) / 9.0, 0.0, 1.0), 0.3)
	_pivot.rotation.y = _yaw + sin(_t * 0.7) * 0.06 * _lift
	# droop: hang down in a calm, stream level in a strong wind; each segment sags a little more, and flutters
	var droop: float = lerpf(deg_to_rad(-75.0), deg_to_rad(-4.0), _lift)
	_pivot.rotation.z = droop
	for i in range(1, _segs.size()):
		var seg: Node3D = _segs[i]
		var sag: float = (1.0 - _lift) * deg_to_rad(4.0) + _lift * deg_to_rad(1.5)
		seg.rotation.z = -sag + sin(_t * (6.0 + float(i)) + float(i) * 1.3) * deg_to_rad(4.0) * (0.3 + _lift)
		seg.rotation.y = sin(_t * (4.0 + float(i) * 0.7) + float(i)) * deg_to_rad(3.0) * (0.3 + _lift)
