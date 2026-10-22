class_name WeaponProjectile
extends RefCounted
## Pooled bomb / rocket state (the visual node is created once and reused).

var node: Node3D
var pos: Vector3
var vel: Vector3
var team: int = 2
var source: Node
var damage: float = 100.0
var radius: float = 20.0
var age: float = 0.0
var max_age: float = 40.0
var acc: float = 0.0
var whistled: bool = false
# bouncing (Upkeep) bomb state: skips off the water, then sinks and is fused underwater
var skipping: bool = false
var skips: int = 0
var sunk: bool = false
var fuse: float = 0.0


func reset(p: Vector3, v: Vector3, t: int, src: Node, dmg: float, rad: float, life: float) -> void:
	pos = p
	vel = v
	team = t
	source = src
	damage = dmg
	radius = rad
	age = 0.0
	max_age = life
	acc = 0.0
	whistled = false
