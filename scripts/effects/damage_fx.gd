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
var _eng_fire: FXEmitter
var _leak: FXEmitter
var _burning: bool = false
var _had_fire: bool = false
var _fate: String = ""
var _fate_t: float = 0.0


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
	frac = minf(frac, 1.0 - 0.75 * aircraft.engine_wear)      # a worn-out (over-heated) engine smokes and burns too
	_update_leak()
	_fire_logic(frac, 0.25)
	if frac > 0.6 and not _burning:
		if _smoke != null or _fire != null:
			_stop_all()          # repaired / respawned: clear the damage trail
		return
	_update_trail(frac)


## Radial engines throw dark oil smoke; liquid-cooled ones lose a white plume of glycol steam first.
func _liquid_cooled() -> bool:
	var id: String = String(aircraft.stats.model_id)
	return String(PlaneParts.ENGINE_KIND.get(id, "inline")) != "radial" and not id in ["fw190", "p47"]


## A holed wing with fuel in it streams pale fuel vapour from the wound.
func _update_leak() -> void:
	var dm: AircraftDamageModel = aircraft.damage_model
	if dm == null:
		return
	var w: float = maxf(float(dm.parts["wing_l"]), float(dm.parts["wing_r"]))
	if w >= 0.4 and _leak == null:
		var sgn: float = 1.0 if float(dm.parts["wing_r"]) >= float(dm.parts["wing_l"]) else -1.0
		var half: float = dm._half_span()
		_leak = FX.trail(aircraft, "smoke", 0.9, Vector3(sgn * half * 0.4, 0.1, 0.9), 0.02)
		aircraft.set_meta("fuel_leak", true)
	elif w < 0.4 and _leak != null:
		_leak.stop()
		_leak = null
		aircraft.remove_meta("fuel_leak")


## Severely damaged aircraft can catch fire. Some fires burn out and the aircraft limps home, some burn on until
## the aircraft is lost, and some reach the fuel and the aircraft blows up in the air.
func _fire_logic(frac: float, dt: float) -> void:
	if _burning:
		var dm: AircraftDamageModel = aircraft.damage_model
		if dm != null:
			dm.parts["engine"] = minf(float(dm.parts["engine"]) + 0.02 * dt, 1.0)       # the burning engine is failing
		_fate_t -= dt
		if _fate_t > 0.0:
			return
		_burning = false
		aircraft.remove_meta("on_fire")
		match _fate:
			"out":
				if _eng_fire != null:
					_eng_fire.stop()
					_eng_fire = null
				aircraft.engine_alert.emit("FIRE OUT")
				aircraft.engine_wear = maxf(aircraft.engine_wear, 0.55)
			"die":
				aircraft.fire_kill(randf() < 0.55)
			_:
				aircraft.fire_kill(true, 0.05)
		return
	if _had_fire or frac > 0.38 or aircraft.has_meta("bailed"):
		return
	var rate: float = 0.03 + 0.18 * (0.38 - frac) / 0.38
	if aircraft.has_meta("fuel_leak"):
		rate *= 1.7
	if randf() < rate * dt:
		_ignite()


func _ignite() -> void:
	_burning = true
	_had_fire = true
	aircraft.set_meta("on_fire", true)
	var r: float = randf()
	if r < 0.4:
		_fate = "out"
		_fate_t = randf_range(5.0, 18.0)
	elif r < 0.72:
		_fate = "die"
		_fate_t = randf_range(6.0, 22.0)
	else:
		_fate = "boom"
		_fate_t = randf_range(2.0, 9.0)
	_eng_fire = FX.trail(aircraft, "fire", 2.2, Vector3(0.0, 0.5, -1.8))
	aircraft.engine_alert.emit("ENGINE FIRE!")


## Damage trail by health: grey from 60 %, thick black from 40 %, with fire under 30 %.
func _update_trail(frac: float) -> void:
	if _smoke == null:
		_smoke = FX.trail(aircraft, "smoke", 2.2, Vector3(0, 0.3, 3.5), 0.3)
	if frac >= 0.40 and _liquid_cooled() and not _burning:
		var kw: float = (0.6 - frac) / 0.2
		_smoke.size = lerpf(1.8, 2.6, kw)
		_smoke.dark = lerpf(0.0, 0.12, kw)               # white glycol steam, whitest at first
	elif frac < 0.40:
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
	if _eng_fire:
		_eng_fire.stop()
		_eng_fire = null
	if _leak:
		_leak.stop()
		_leak = null
	_burning = false
	_had_fire = false
	if aircraft != null and is_instance_valid(aircraft):
		aircraft.remove_meta("on_fire")
		aircraft.remove_meta("fuel_leak")


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
	if a.has_meta("bailed"):
		return          # abandoned by its pilot: no flash, fire or wing loss, it just flies on and goes down
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
