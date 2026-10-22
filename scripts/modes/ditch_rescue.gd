class_name DitchRescue
extends Node
## Rescue after a ditching in the Channel. The airman's dinghy goes onto the sea at the splash point and drifts
## (tide and wind). The normal respawn puts a fresh aircraft back in the air; that rescue flight has to find the
## dinghy and circle low over it for PICKUP_T seconds so the launch gets a fix. Not found within LOST_T: lost at sea.

const PICKUP_RANGE: float = 2200.0    # horizontal distance to the dinghy that counts as circling over him
const PICKUP_ALT: float = 450.0       # ... flown below this height above the ground
const PICKUP_T: float = 35.0          # seconds of circling needed for the fix
const LOST_T: float = 360.0           # seconds before the airman is written off

var _dinghy: Dinghy
var _hud: HUD
var _orbit_t: float = 0.0
var _life_t: float = 0.0
var _done: bool = false


## Put the dinghy on the sea at the splash point and start the rescue clock. Called when a player aircraft ditches.
static func start(parent: Node, splash: Vector3, hud: HUD) -> DitchRescue:
	var r := DitchRescue.new()
	r._hud = hud
	parent.add_child(r)
	r._dinghy = Dinghy.new()
	parent.add_child(r._dinghy)
	r._dinghy.global_position = Vector3(splash.x, 0.2, splash.z)
	var a: float = randf() * TAU
	r._dinghy.drift = Vector3(cos(a), 0.0, sin(a)) * randf_range(0.6, 1.4)
	if hud != null:
		hud.show_message("Ditched in the Channel. Rescue flight launching - find the dinghy and circle low over him for %d s." % int(PICKUP_T), 6.0)
	return r


func _process(delta: float) -> void:
	if _done:
		return
	_life_t += delta
	if _dinghy == null or not is_instance_valid(_dinghy):
		_finish(false)
		return
	var pl: Node3D = _player()
	if pl != null:
		var dp: Vector3 = _dinghy.global_position
		var d: float = Vector2(pl.global_position.x - dp.x, pl.global_position.z - dp.z).length()
		var agl: float = float(pl.get("altitude_agl"))
		if d < PICKUP_RANGE and agl < PICKUP_ALT:
			_orbit_t += delta
			if _orbit_t >= PICKUP_T:
				_finish(true)
				return
		else:
			_orbit_t = maxf(_orbit_t - delta * 0.5, 0.0)
	if _life_t >= LOST_T:
		_finish(false)


## The live player aircraft. A wreck of the one that ditched can still be in the tree for a moment, so dead ones are skipped.
func _player() -> Node3D:
	for n in get_tree().get_nodes_in_group("aircraft"):
		if "player_controlled" in n and bool(n.get("player_controlled")) and GroundKit.aircraft_alive(n):
			return n as Node3D
	return null


func _finish(picked_up: bool) -> void:
	_done = true
	if _hud != null:
		if picked_up:
			_hud.show_message("Pilot picked up by the rescue launch - back to the fight", 5.0)
		else:
			_hud.show_message("No sign of the pilot - lost at sea", 5.0)
	if _dinghy != null and is_instance_valid(_dinghy):
		_dinghy.queue_free()
	queue_free()
