class_name LookUtil
extends RefCounted
## Safe replacement for Node3D.look_at(). Godot's look_at() decides "origin and target are the same" with a tolerance
## that grows with the coordinates, so far out on the map (tens of km from the origin) a short look (a slow aircraft's
## next step, a direction vector of a metre or two) is rejected with an error every frame. This turns the node by
## the direction itself (exact at any distance), keeps its scale, and quietly skips a zero direction or swaps the up
## vector when the direction is straight up or down.


static func look(n: Node3D, target: Vector3, up: Vector3 = Vector3.UP) -> void:
	if n == null or not n.is_inside_tree():
		return
	face(n, target - n.global_position, up)


static func face(n: Node3D, dir: Vector3, up: Vector3 = Vector3.UP) -> void:
	if n == null or not n.is_inside_tree() or dir.length_squared() < 1e-12:
		return
	var d: Vector3 = dir.normalized()
	var u: Vector3 = up.normalized() if up.length_squared() > 1e-12 else Vector3.UP
	if absf(d.dot(u)) > 0.9995:
		u = Vector3.FORWARD if absf(d.z) < 0.9 else Vector3.RIGHT
	var sc: Vector3 = n.global_basis.get_scale()
	n.global_basis = Basis.looking_at(d, u) * Basis.from_scale(sc)
