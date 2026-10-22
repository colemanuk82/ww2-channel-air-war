class_name AircraftHitProxy
extends Node3D
## Makes an Aircraft satisfy the DAMAGE CONTRACT (group "damageable", team, hit_radius, take_damage)
## without editing aircraft.gd. Added as a child; frees itself if the aircraft already exposes hit_radius.

var team: String = "Neutral"
var hit_radius: float = 8.0
var _ac: Aircraft


func _ready() -> void:
	_ac = get_parent() as Aircraft
	if _ac == null or "hit_radius" in _ac:
		queue_free()
		return
	team = _ac.team
	hit_radius = _ac.stats.radius * 1.15
	add_to_group("damageable")


func take_damage(amount: float, source: Node = null) -> void:
	if is_instance_valid(_ac):
		_ac.take_damage(amount, source)


func _process(_delta: float) -> void:
	if is_instance_valid(_ac):
		team = _ac.team
		# dead aircraft are no longer targets
		if _ac.state != Aircraft.State.ALIVE and is_in_group("damageable"):
			remove_from_group("damageable")
