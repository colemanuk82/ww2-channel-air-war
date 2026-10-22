class_name AIGun
extends RefCounted
## Gunnery helper for AI pilots and bomber gunners.
## Uses the `Weapons` autoload (WeaponWorld.fire_bullet) when present; otherwise falls back to a crude
## hitscan so AI is still dangerous before the weapon system exists.

const BULLET_SPEED: float = 520.0
const FALLBACK_RANGE: float = 900.0
const FALLBACK_HIT_CHANCE: float = 0.55


static func weapons(tree_node: Node) -> Node:
	return tree_node.get_node_or_null("/root/Weapons")


## Fire a single bullet. `inherit_vel` is added to the muzzle velocity (shooter velocity).
static func fire(tree_node: Node, shooter: Node3D, origin: Vector3, dir: Vector3, inherit_vel: Vector3, team: String, damage: float, tracer: bool = true) -> void:
	var w: Node = weapons(tree_node)
	if w != null and w.has_method("fire_bullet"):
		w.call("fire_bullet", origin, dir * BULLET_SPEED + inherit_vel, team, shooter, damage, tracer, 1.7)
		return
	_hitscan(tree_node, shooter, origin, dir, team, damage)


static func _hitscan(tree_node: Node, shooter: Node3D, origin: Vector3, dir: Vector3, team: String, damage: float) -> void:
	if randf() > FALLBACK_HIT_CHANCE:
		return
	var best: Node = null
	var best_d: float = FALLBACK_RANGE
	for n in tree_node.get_tree().get_nodes_in_group("aircraft"):
		var a: Aircraft = n as Aircraft
		if a == null or a == shooter or a.team == team or a.state != Aircraft.State.ALIVE:
			continue
		var rel: Vector3 = a.global_position - origin
		var t: float = rel.dot(dir)
		if t < 0.0 or t > best_d:
			continue
		var miss: float = (rel - dir * t).length()
		if miss < a.stats.radius * 1.2:
			best = a
			best_d = t
	if best != null:
		(best as Aircraft).take_damage(damage, shooter)


## Random direction within a cone of `spread` radians around dir.
static func spread_dir(dir: Vector3, spread: float) -> Vector3:
	var up: Vector3 = Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var right: Vector3 = dir.cross(up).normalized()
	var up2: Vector3 = right.cross(dir).normalized()
	var a: float = randf() * TAU
	var r: float = sqrt(randf()) * spread
	return (dir + (right * cos(a) + up2 * sin(a)) * r).normalized()
