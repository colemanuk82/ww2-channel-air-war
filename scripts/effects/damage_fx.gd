class_name AircraftDamageFX
extends Node
## Visual damage for an Aircraft (added as a child by Aircraft._ready):
##  < 60% health: grey smoke trail; < 30%: black smoke + flames; death: fire trail, possible wing loss,
##  possible parachuting pilot. The crash explosion itself is spawned by Aircraft._spawn_crash_fx().

const WING_COL_ALLIES := Color(0.33, 0.36, 0.22)
const WING_COL_AXIS := Color(0.34, 0.37, 0.4)

var aircraft: Aircraft
var _smoke: FXEmitter
var _fire: FXEmitter
var _poll: float = 0.0


func attach(a: Aircraft) -> void:
	aircraft = a
	a.damaged.connect(_on_damaged)
	a.destroyed.connect(_on_destroyed)
	a.crashed.connect(_on_crashed)


func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0 or aircraft == null:
		return
	_poll = 0.25
	if aircraft.state != Aircraft.State.ALIVE:
		return
	var frac: float = aircraft.health / maxf(aircraft.stats.max_health, 1.0)
	if frac > 0.6:
		_stop_all()          # repaired / respawned: clear the damage trail
		return
	_update_trail(frac)


## Damage trail by health: grey from 60 %, thick black from 40 %, with fire under 30 %.
func _update_trail(frac: float) -> void:
	if _smoke == null:
		_smoke = FX.trail(aircraft, "smoke", 2.2, Vector3(0, 0.3, 3.5), 0.3)
	if frac < 0.40:
		var k: float = clampf((0.40 - frac) / 0.15, 0.0, 1.0)
		_smoke.size = lerpf(2.9, 4.0, k)
		_smoke.dark = lerpf(0.78, 0.96, k)
	elif _smoke != null:
		var k2: float = (0.6 - frac) / 0.2
		_smoke.size = lerpf(2.2, 2.9, k2)
		_smoke.dark = lerpf(0.3, 0.7, k2)
	if frac < 0.3 and _fire == null:
		_fire = FX.trail(aircraft, "fire", 2.4, Vector3(0, 0.5, 2.5))


func _stop_all() -> void:
	if _smoke:
		_smoke.stop()
		_smoke = null
	if _fire:
		_fire.stop()
		_fire = null


func _on_damaged(_a: Aircraft, _amount: float, _health: float) -> void:
	_poll = 0.0          # refresh the trail on the next frame


func _on_destroyed(a: Aircraft, _killer: Node) -> void:
	if a.state != Aircraft.State.DYING:
		return   # crashed directly; the crash fx handles it
	if _smoke == null:
		_smoke = FX.trail(a, "smoke", 3.0, Vector3(0, 0.3, 3.5), 0.9)
	else:
		_smoke.dark = 0.95
		_smoke.size = 3.4
	if _fire == null:
		_fire = FX.trail(a, "fire", 3.0, Vector3(0, 0.5, 2.5))
	FX.explosion(a.global_position, 4.0)   # in-air hit flash
	if randf() < 0.45:
		_lose_wing(a)
	# a kill that blows up in mid-air leaves nobody alive; otherwise each man aboard may get out
	if a.altitude_agl > 50.0 and not a.on_ground and not a.has_meta("bailed") and a._explode_t <= 0.0:
		var pos: Vector3 = a.global_position
		var side: String = a.team
		var fwd: Vector3 = -a.global_transform.basis.z
		var out: int = 0
		for i in a.crew_count():
			if randf() < (0.7 if i == 0 else 0.65):
				var off: Vector3 = Vector3(randf_range(-3.0, 3.0), -2.0, randf_range(-3.0, 3.0)) + fwd * float(i) * -9.0
				get_tree().create_timer(0.7 + 0.45 * float(out)).timeout.connect(func() -> void:
					FX.parachute(pos + off, side))
				out += 1


func _lose_wing(a: Aircraft) -> void:
	var side: float = 1.0 if randf() < 0.5 else -1.0
	var col: Color = WING_COL_AXIS if a.team == "Axis" else WING_COL_ALLIES
	var origin: Vector3 = a.global_position + a.global_transform.basis.x * side * 4.0
	var out: Vector3 = a.global_transform.basis.x * side
	for i in 5:
		FX.chunks.spawn(origin + out * float(i) * 0.8, a.velocity * 0.8 + out * randf_range(6.0, 16.0) + Vector3(0, randf_range(2.0, 10.0), 0),
			randf_range(2.5, 4.0), 3.2, 2.2, col, Color(col.r, col.g, col.b, 0.0), 1.0, 30.0, 0.05, randf_range(2.0, 6.0))
	FX.sparks(origin, out, 8)
	# the stump makes it roll harder
	a.set("_dying_spin", side * 3.2)


func _on_crashed(_a: Aircraft, _reason: String) -> void:
	_stop_all()
