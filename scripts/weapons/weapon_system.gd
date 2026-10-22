class_name WeaponSystem
extends Node
## Per-aircraft weapons controller. Aircraft._ready creates one and calls attach(self); it works for
## player and AI aircraft alike (AI just sets cmd_fire / emits bomb_requested).
## Guns: fire_requested (every frame while firing) -> rate limited volleys, one bullet per muzzle.
## Bombs / rockets: bomb_requested -> drops a bomb if bombs remain, otherwise a rocket pair.

var aircraft: Aircraft
var rockets_left: int = 0
var hud_overlay: WeaponHud

var _gun_cd: float = 0.0
var _warned_low: bool = false
var _warned_out: bool = false
var _tracer_i: int = 0
var _bomb_side: float = 1.0
var _muzzles: Array[Node3D] = []

## Player gunnery help. Both values were tuned by ear: `spread *= 0.5` with a 9 deg assist cone was far
## too easy, going all the way to 1.0 / 2.5 deg overshot the other way, so the middle ground is the small
## player cone discount below with an assist that only catches aiming errors worth a few degrees.
const PLAYER_SPREAD_K: float = 0.75
const AIM_ASSIST_DEG: float = 3.0


func attach(a: Aircraft) -> void:
	aircraft = a
	rockets_left = a.stats.rockets
	a.fire_requested.connect(_on_fire)
	a.bomb_requested.connect(_on_bomb)
	_muzzles = a.get_muzzles()
	if a.player_controlled:
		hud_overlay = WeaponHud.new()
		hud_overlay.name = "WeaponHud"
		add_child(hud_overlay)
		hud_overlay.bind(self)


func _process(delta: float) -> void:
	if _gun_cd > 0.0:
		_gun_cd -= delta
	if aircraft == null or not is_instance_valid(aircraft):
		return
	if aircraft.player_controlled:
		if aircraft.ammo > _low_threshold():      # restocked (rearm / respawn): arm the warnings again
			_warned_low = false
		if aircraft.ammo > 0:
			_warned_out = false
		var alive: bool = aircraft.state != Aircraft.State.DEAD
		FX.engine(aircraft.throttle if alive else 0.0, aircraft.speed / maxf(aircraft.stats.max_speed, 1.0), aircraft.stats.engine_sound, aircraft.stats.engine_count)


func _low_threshold() -> int:
	return int(float(aircraft.stats.ammo) * 0.25)


## Player only: one spoken + on-screen warning when the guns drop to a quarter, and another when they run dry.
func _check_ammo(a: Aircraft) -> void:
	var side: String = "axis" if a.team == "Axis" else "allies"
	if a.ammo <= 0 and not _warned_out:
		_warned_out = true
		_warned_low = true
		_ammo_call(side, "ammo_out", ["Out of ammo! Guns empty.", "Guns are dry, I'm out of ammo!"], "OUT OF AMMO")
	elif a.ammo <= _low_threshold() and not _warned_low:
		_warned_low = true
		_ammo_call(side, "ammo_low", ["Low on ammo.", "Running low on ammunition."], "LOW AMMO")


func _ammo_call(side: String, key: String, texts: Array, banner: String) -> void:
	var n: int = randi() % texts.size()
	Radio.say(Radio.player_callsign, str(texts[n]), Radio.Kind.PLAYER, 0.0, "mode/%s/%s_%d" % [side, key, n + 1], true)
	if hud_overlay != null:
		hud_overlay.flash(banner)


func rearm() -> void:
	rockets_left = aircraft.stats.rockets
	aircraft.ammo = aircraft.stats.ammo
	aircraft.bombs = aircraft.stats.bombs
	_warned_low = false
	_warned_out = false


func _on_fire(a: Aircraft) -> void:
	if _gun_cd > 0.0 or a.ammo <= 0 or a.state != Aircraft.State.ALIVE:
		return
	var st: AircraftStats = a.stats
	if _muzzles.is_empty() or not is_instance_valid(_muzzles[0]):
		_muzzles = a.get_muzzles()
		if _muzzles.is_empty():
			return
	_gun_cd = 1.0 / maxf(st.fire_rate, 0.5)
	var fwd: Vector3 = a.get_forward()
	var aim: Vector3 = a.global_position + fwd * st.gun_convergence
	var spread: float = st.gun_spread
	if a.player_controlled:
		aim = _assisted_aim(a, fwd, aim)
		spread *= PLAYER_SPREAD_K
	var per_bullet: float = st.gun_damage * float(maxi(st.gun_count, 1)) / float(_muzzles.size())
	var life: float = st.gun_range / st.gun_speed
	var base_vel: Vector3 = a.velocity
	for m in _muzzles:
		if a.ammo <= 0:
			break
		var mp: Vector3 = m.global_position
		var d: Vector3 = (aim - mp).normalized()
		d += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * spread
		d = d.normalized()
		_tracer_i += 1
		var tracer: bool = st.tracer_every <= 1 or _tracer_i % st.tracer_every == 0
		Weapons.fire_bullet(mp + d * 1.5, base_vel + d * st.gun_speed, a.team, a, per_bullet, tracer, life)
		a.ammo -= 1
		FX.muzzle_flash(m)
	if a.player_controlled:
		_check_ammo(a)
	var shot_sfx: String = ("gun:" + st.gun_sound) if st.gun_sound != "" else ("cannon" if st.gun_damage >= 2.0 else "gun")
	FX.sfx(shot_sfx, a.global_position, -6.0 if not a.player_controlled else -3.0, 0.06)


func _on_bomb(a: Aircraft) -> void:
	if a.state != Aircraft.State.ALIVE:
		return
	var st: AircraftStats = a.stats
	var basis: Basis = a.global_transform.basis
	var want_rockets: bool = a.weapon_mode == 1 or (a.weapon_mode == 0 and a.bombs <= 0)   # AI bombers leave the mode at guns
	if not want_rockets and a.bombs > 0:
		a.bombs -= 1
		_bomb_side = -_bomb_side
		var pos: Vector3 = a.global_position - basis.y * 1.8 + basis.x * _bomb_side * 1.2
		var vel: Vector3 = a.velocity
		if vel.length_squared() < 1.0:
			vel = a.get_forward() * a.speed
		Weapons.drop_bomb(pos, vel, a.team, a, st.bomb_damage, st.bomb_radius)
	elif rockets_left > 0:
		var n: int = mini(2, rockets_left)
		rockets_left -= n
		var fwd: Vector3 = a.get_forward()
		for i in n:
			var side: float = -1.0 if i == 0 else 1.0
			var pos2: Vector3 = a.global_position + basis.x * side * 3.0 - basis.y * 0.6 + fwd * 2.0
			Weapons.fire_rocket(pos2, a.velocity + fwd * st.rocket_speed, a.team, a, st.rocket_damage, st.rocket_radius)


## Dogfight aim assist for the player: when an enemy sits close to the gun line, the guns converge on where it will be
## when the bullets arrive (lead), pulled in only as far as a small cone so deliberate misses still miss.
func _assisted_aim(a: Aircraft, fwd: Vector3, default_aim: Vector3) -> Vector3:
	var best: Node3D = null
	var best_ang: float = deg_to_rad(AIM_ASSIST_DEG)
	for n in a.get_tree().get_nodes_in_group("damageable"):
		var t := n as Node3D
		if t == null or t == a or not is_instance_valid(t):
			continue
		var tt: Variant = t.get("team")
		if tt == null or tt == a.team:
			continue
		var to: Vector3 = t.global_position - a.global_position
		var dist: float = to.length()
		if dist < 40.0 or dist > a.stats.gun_range * 0.9:
			continue
		var ang: float = fwd.angle_to(to)
		if ang < best_ang:
			best_ang = ang
			best = t
	if best == null:
		return default_aim
	var tv: Variant = best.get("velocity")
	var vel: Vector3 = tv if tv is Vector3 else Vector3.ZERO
	var dist2: float = a.global_position.distance_to(best.global_position)
	var tof: float = dist2 / maxf(a.stats.gun_speed, 1.0)
	var lead: Vector3 = best.global_position + (vel - a.velocity) * tof
	return lead
