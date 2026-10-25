class_name FallingPart
extends Node3D
## A piece of airframe (a wing panel, the tail) that has come off an aircraft: it tumbles away on the aircraft's own
## velocity, trailing smoke, and bursts on the ground.

var vel: Vector3 = Vector3.ZERO
var spin: Vector3 = Vector3.ZERO
var _trail: Object = null
var _age: float = 0.0


static func make(world: Node, xf: Transform3D, size: Vector3, color: Color, v: Vector3, p_spin: Vector3) -> FallingPart:
	var p := FallingPart.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = ToonUtil.make_toon(color, {"outline_thickness": 0.03})
	p.add_child(mi)
	world.add_child(p)
	p.global_transform = xf
	p.vel = v
	p.spin = p_spin
	p._trail = FX.trail(p, "smoke", 1.4, Vector3.ZERO)
	return p


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_age += delta
	vel.y -= 19.6 * delta
	vel *= 1.0 - 0.12 * delta
	global_position += vel * delta
	rotate_object_local(Vector3.RIGHT, spin.x * delta)
	rotate_object_local(Vector3.UP, spin.y * delta)
	rotate_object_local(Vector3.BACK, spin.z * delta)
	var gy: float = GroundKit.ground_y(global_position.x, global_position.z)
	if global_position.y <= gy + 0.3 or _age > 25.0:
		if _age <= 25.0:
			FX.explosion(Vector3(global_position.x, gy + 0.5, global_position.z), 0.7)
		queue_free()


func _exit_tree() -> void:
	if _trail != null and is_instance_valid(_trail) and _trail.has_method("stop"):
		_trail.call("stop")
