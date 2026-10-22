class_name ChimneySmokes
extends Node3D
## Thin white chimney smoke over a few houses of a village / farm tile. Emitters only run while the camera is
## within ~3 km (and a global budget isn't spent): each live emitter keeps puffs in the shared FX pool.

const RANGE: float = 1500.0       # world units (2 m each)
const BUDGET: int = 40

static var _active_total: int = 0

var points: PackedVector3Array = PackedVector3Array()
var size: float = 1.1
var _holders: Array = []
var _emitters: Array = []
var _t: float = randf() * 1.5


func _ready() -> void:
	for p in points:
		var holder := Node3D.new()
		holder.position = p
		add_child(holder)
		_holders.append(holder)
		_emitters.append(null)


func _exit_tree() -> void:
	for e in _emitters:
		if e != null:
			_active_total = maxi(_active_total - 1, 0)
	_emitters.clear()


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 1.5
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp: Vector3 = cam.global_position
	for i in _holders.size():
		var h: Node3D = _holders[i]
		var d: float = Vector2(h.global_position.x - cp.x, h.global_position.z - cp.z).length()
		var e: Variant = _emitters[i]
		if e == null and d < RANGE and _active_total < BUDGET:
			var r: Array = GroundKit.fx_call("chimney_smoke", [h.global_position, size, h])
			if r[0]:
				_emitters[i] = r[1]
				_active_total += 1
		elif e != null and d > RANGE * 1.3:
			if is_instance_valid(e):
				(e as FXEmitter).stop()
			_emitters[i] = null
			_active_total = maxi(_active_total - 1, 0)
