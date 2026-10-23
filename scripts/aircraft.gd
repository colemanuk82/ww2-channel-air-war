class_name Aircraft
extends Node3D
## Arcade aircraft. Node3D root; flight is integrated manually (no physics bodies).
## Control sources: set `player_controlled = true` to read the InputMap, otherwise an AI/other
## script writes the cmd_* variables each frame:
##   cmd_pitch (+1 nose up), cmd_roll (+1 roll right), cmd_yaw (+1 yaw right) in -1..1,
##   throttle_target 0..1, cmd_boost (bool), cmd_fire (bool).
## Assumes its parent has an identity transform (world root).

signal fire_requested(aircraft: Aircraft)      # emitted every frame while cmd_fire is true and alive
signal bomb_requested(aircraft: Aircraft)      # emitted on bomb press
signal weapon_changed(bombs: bool)             # player switched the selected weapon
signal damaged(aircraft: Aircraft, amount: float, health: float)
signal destroyed(aircraft: Aircraft, killer: Node)   # health reached 0 (starts dying) or crashed
signal crashed(aircraft: Aircraft, reason: String)   # hit ground/water hard (explosion spawned)
signal took_off(aircraft: Aircraft)
signal landed(aircraft: Aircraft)
signal stall_changed(aircraft: Aircraft, stalled: bool)
signal boost_changed(aircraft: Aircraft, active: bool)
signal gear_changed(aircraft: Aircraft, down: bool)
signal flaps_changed(aircraft: Aircraft, message: String)   # flap setting changed / refused / damaged

enum State { ALIVE, DYING, DEAD }

@export var stats: AircraftStats
@export var player_controlled: bool = false
@export var team: String = "Allies"
@export var start_gear_down: bool = true

# Control inputs (written by player input or AI)
var cmd_pitch: float = 0.0
var cmd_roll: float = 0.0
var cmd_yaw: float = 0.0
var throttle_target: float = 0.0
var cmd_boost: bool = false
var cmd_fire: bool = false
var weapon_bombs: bool = false   # true while the BOMBS weapon is selected (bombsight, bomb camera)
var weapon_mode: int = 0         # selected weapon: 0 guns, 1 rockets, 2 bombs
var brake_on: bool = false       # wheel brake held (ground only)
var wind: Vector3 = Vector3.ZERO # local wind (blow-to), refreshed every frame
const WIND_MAX := 3.0             # strongest wind that acts on the aircraft (units/s, about 2% of cruise speed)
const WIND_EFFECT := 0.25         # share of the real wind that acts on the aircraft
var headwind: float = 0.0        # component of wind opposing the nose (negative = tailwind)
var crosswind: float = 0.0       # component from the right (positive = wind blowing toward the right wing)
var turbulence: float = 0.0      # 0..1 rough air
var air_density: float = 1.0     # sigma: 1 at sea level, thinner with altitude
var eas: float = 0.0             # equivalent airspeed: true airspeed * sqrt(sigma), what the wings feel
var g_load: float = 1.0          # lift along the wing normal in weights (1 = level upright flight)
var lift_fraction: float = 1.0   # share of the weight the wings carry vertically (negative = pushing the aircraft down)
var wing: WingModel              # strip-theory wing (see wing_model.gd)
var flap_setting: int = 0        # 0 up, 1 take-off (15 deg), 2 landing (35 deg)
var flap_deploy: float = 0.0     # animated 0..1
const FLAP_TARGETS := [0.0, 0.43, 1.0]
const FLAP_NAMES := ["UP", "15", "35"]
const ENGINE_POWER: float = 0.6        # share of stats.accel available as thrust in the air
const INDUCED_DRAG: float = 1.5        # speed lost per second per g above 1 (scaled by speed)
const ROLL_COUPLING: float = 0.9       # rad/s of roll rate per unit of wing rolling moment
const GROUND_RUN_K: float = 0.30       # fraction of the normal acceleration available while rolling on the ground
var _flap_l: Node3D
var _flap_r: Node3D

# State (read-only for outside code)
var state: int = State.ALIVE
var speed: float = 0.0
var throttle: float = 0.0
var health: float = 100.0
## Set for AI aircraft from the start of the take-off roll until they have climbed to 50 m: no damage, no crash.
var invulnerable: bool = false
var _dmg_side: float = 0.0          # which way a damaged aircraft pulls (fixed per aircraft once it is hit)
var boost_energy: float = 1.0
var boosting: bool = false
var boost_locked: bool = false
var on_ground: bool = false
var stalled: bool = false
var gear_down: bool = true
var auto_level: bool = true
var velocity: Vector3 = Vector3.ZERO
var altitude_agl: float = 0.0
var over_water: bool = false
var shake_intensity: float = 0.0
var ammo: int = 0
var bombs: int = 0
var hit_radius: float = 8.0   # damage contract: sphere radius for hit tests (world units)
var weapons: WeaponSystem
var bombsight_only: bool = false   # bomber with a bombsight: no free impact-point aid in the chase view (set the sight instead)
var sight_hold: bool = false     # bombsight engaged: autopilot keeps wings level and holds sight_alt_y; steering = slight banked turns
var sight_alt_y: float = 0.0
var _explode_t: float = -1.0     # > 0 while a destroyed aircraft is about to detonate in the air
var damage_fx: AircraftDamageFX
var damage_model: AircraftDamageModel
var _pending_hit: Vector3 = Vector3.ZERO      # set by WeaponWorld just before take_damage: where the round struck
var _pending_dir: Vector3 = Vector3.ZERO

var _pitch_rate: float = 0.0
var _roll_rate: float = 0.0
# Pitch trim (see _update_trim). trim_speed: the equivalent airspeed the aircraft is trimmed for; with the stick
# released it settles back to this speed and the THROTTLE then sets the climb or sink rate, so there is always a
# throttle setting that holds a fixed altitude. With the assist on (auto_level) it holds the altitude instead.
var trim_speed: float = 0.0
var alt_hold_active: bool = false     # assist altitude hold engaged (stick released, wings near level)
var _hold_y: float = 0.0
var _trim_corr: float = 0.01          # learned offset: the strip wing (washout etc.) needs a little more AoA than the ideal formula
var _thr_held: float = 0.0            # seconds the throttle key has been held (tap = 1% step)
var _n_target: float = 1.0            # lift the trim aims for, in weights along the wing normal
var _path_dir: Vector3 = Vector3.FORWARD   # world velocity direction (lags the nose)
var _aoa: float = 0.0                      # angle of attack (radians)
var _wing_drop: float = 0.0                # stall wing-drop direction (-1..1)
var _yaw_rate: float = 0.0
var _stall_amount: float = 0.0
var _impact_shake: float = 0.0
var _gear_amount: float = 1.0
var _terrain: Node = null
var _model: Node3D
var _prop: Node3D
var _prop_disc: Node3D
var _prop_blades: Node3D
var _gear_l: Node3D
var _gear_r: Node3D
var _canopy: Node3D
var _eye: Node3D
var _dying_spin: float = 0.0
var _cockpit_view: bool = false


func _ready() -> void:
	add_to_group("aircraft")
	if stats == null:
		stats = load("res://data/aircraft/spitfire.tres") as AircraftStats
	health = stats.max_health
	ammo = stats.ammo
	bombs = stats.bombs
	gear_down = start_gear_down
	_gear_amount = 1.0 if gear_down else 0.0
	auto_level = GameState.auto_level
	_build_model()
	_apply_gear_visual()
	add_to_group("damageable")
	hit_radius = stats.radius
	weapons = WeaponSystem.new()
	weapons.name = "Weapons"
	add_child(weapons)
	weapons.attach(self)
	weapon_mode = 2 if (stats != null and stats.bombs > 0 and stats.ammo <= 0) else 0   # bombers default to bombs
	weapon_bombs = weapon_mode == 2
	damage_fx = AircraftDamageFX.new()
	damage_fx.name = "DamageFX"
	add_child(damage_fx)
	damage_fx.attach(self)
	damage_model = AircraftDamageModel.new()
	damage_model.name = "DamageModel"
	add_child(damage_model)
	damage_model.attach(self)


## AI aircraft get a coloured outline so they are easy to see: red for the enemy, yellow for friendlies.
func _apply_team_outline() -> void:
	if player_controlled or _model == null:
		return
	var friendly: bool = team == GameState.player_side
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/team_outline.gdshader") as Shader
	m.set_shader_parameter("outline_color", Color(1.0, 0.85, 0.1) if friendly else Color(1.0, 0.16, 0.1))
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi == null or String(mi.name).findn("disc") >= 0:
			continue
		mi.material_overlay = m


func _build_model() -> void:
	var old: Node = get_node_or_null("Model")
	if old:
		old.queue_free()
	_model = AircraftModels.build(stats.model_id, stats.nation)
	_contrail_ready = false
	add_child(_model)
	_apply_team_outline()
	_prop = _model.find_child("Propeller", true, false) as Node3D
	_prop_disc = _model.find_child("PropDisc", true, false) as Node3D
	_prop_blades = _prop.find_child("Blades", true, false) as Node3D if _prop else null
	_gear_l = _model.find_child("GearL", true, false) as Node3D
	_gear_r = _model.find_child("GearR", true, false) as Node3D
	_scan_ground_geometry()
	_canopy = _model.find_child("Canopy", true, false) as Node3D
	_eye = _model.find_child("CockpitEye", true, false) as Node3D
	_flap_l = _model.find_child("FlapL", true, false) as Node3D
	_flap_r = _model.find_child("FlapR", true, false) as Node3D
	# wing half-span (metres * model scale) for the strip-theory wing
	var half: float = 5.4 * 1.1
	var spec: Dictionary = ModelSpecs.get_spec(stats.model_id)
	if not spec.is_empty():
		half = float(spec["wing"]["half"]) * float(spec.get("scale", 1.1))
	wing = WingModel.new()
	wing.setup(half, int(get_instance_id()))
	var mount: Node3D = get_node_or_null("CockpitMount") as Node3D
	if mount and _eye:
		mount.position = _eye.position


# ---------------------------------------------------------------- ground stance
## Where the wheels and the propeller sit on the airframe (aircraft-local metres), read from the built model, so a
## tail-dragger rests tail-down on its two main wheels and tail wheel, the tail comes up as it gathers speed, and
## the propeller disc always clears the runway.
var _gg_ok: bool = false
var _gg_ym: float = 0.0       # lowest point of the main wheels
var _gg_zm: float = 0.0       # ... and where along the fuselage they are (+z = aft)
var _gg_tail: bool = false
var _gg_yt: float = 0.0       # lowest point of the tail wheel
var _gg_zt: float = 0.0
var _gg_py: float = 0.0       # propeller centre height / station / radius
var _gg_pz: float = 0.0
var _gg_pr: float = 0.0
var _gg_rest: float = 0.0     # nose-up attitude at rest (radians); 0 for nose-wheel types


func _aabb_local(n: Node3D) -> AABB:
	var out := AABB()
	var first: bool = true
	if n == null:
		return out
	var inv: Transform3D = global_transform.affine_inverse()
	var nodes: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		nodes.append(n)
	for m in nodes:
		var mi: MeshInstance3D = m as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf: Transform3D = inv * mi.global_transform
		var bb: AABB = mi.mesh.get_aabb()
		for i in 8:
			var p: Vector3 = xf * bb.get_endpoint(i)
			if first:
				out = AABB(p, Vector3.ZERO)
				first = false
			else:
				out = out.expand(p)
	return out


func _scan_ground_geometry() -> void:
	if not is_inside_tree():
		return
	_gg_ok = false
	_gg_tail = false
	_gg_rest = 0.0
	_gg_pr = 0.0
	if _gear_l == null or _gear_r == null:
		return
	var gb: AABB = _aabb_local(_gear_l).merge(_aabb_local(_gear_r))
	if gb.size.y <= 0.01:
		return
	_gg_ym = gb.position.y
	_gg_zm = gb.position.z + gb.size.z * 0.5
	var tw: Node3D = _model.find_child("TailWheel", true, false) as Node3D
	if tw != null:
		var tb: AABB = _aabb_local(tw)
		if tb.size.y > 0.01:
			_gg_tail = true
			_gg_yt = tb.position.y
			_gg_zt = tb.position.z + tb.size.z * 0.5
			if absf(_gg_zt - _gg_zm) > 0.5:
				_gg_rest = clampf(atan((_gg_ym - _gg_yt) / (_gg_zm - _gg_zt)), 0.0, deg_to_rad(22.0))
			else:
				_gg_tail = false
	if _prop != null:
		var pb: AABB = _aabb_local(_prop)
		if pb.size.x > 0.5:
			_gg_pr = maxf(pb.size.x, pb.size.y) * 0.5
			_gg_py = pb.position.y + pb.size.y * 0.5
			_gg_pz = (global_transform.affine_inverse() * _prop.global_transform).origin.z
	_gg_ok = true


## Height of the aircraft origin above the ground for the given pitch (nose up positive): the lowest of the main
## wheels, the tail wheel and the propeller tips (with a little clearance) rests on the surface.
func ground_offset(pit: float) -> float:
	if not _gg_ok:
		return stats.gear_height
	var c: float = cos(pit)
	var s: float = sin(pit)
	var h: float = -(_gg_ym * c - _gg_zm * s)
	if _gg_tail:
		h = maxf(h, -(_gg_yt * c - _gg_zt * s))
	if _gg_pr > 0.0:
		h = maxf(h, (_gg_pr - _gg_py) * c + _gg_pz * s + 0.45)
	return h


## Nose-up angle (radians) the aircraft rests at on its wheels.
func ground_rest_pitch() -> float:
	return _gg_rest


# ---------------------------------------------------------------- public API

func get_forward() -> Vector3:
	return -global_transform.basis.z


func get_heading_deg() -> float:
	return WorldCoords.dir_to_heading(get_forward())


func get_altitude_m() -> float:
	return global_position.y / WorldCoords.VERTICAL_SCALE


func get_muzzles() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in ["MuzzleL", "MuzzleR"]:
		var m: Node3D = _model.get_node_or_null(n) as Node3D
		if m:
			out.append(m)
	return out


func get_cockpit_mount() -> Node3D:
	return get_node_or_null("CockpitMount") as Node3D


func set_cockpit_view(on: bool) -> void:
	_cockpit_view = on
	if _canopy:
		_canopy.visible = not on
	if on:
		_ensure_blackout()
	for b in _blackout:
		if is_instance_valid(b):
			b.visible = on


## The airframe is a set of single-sided shells, so from the pilot's eye the hull's inside faces are culled
## and the world shows straight through the fuselage. Each body mesh gets a twin that draws only its INSIDE
## faces, solid black, and is shown only in the cockpit view: the interior reads as a dark, solid cockpit
## and the world is seen only through the open canopy/windscreen area. Built once, for every aircraft type.
var _blackout: Array[MeshInstance3D] = []
var _blackout_mat: StandardMaterial3D


func _ensure_blackout() -> void:
	if not _blackout.is_empty() or _model == null:
		return
	# Heavy bombers: the pilot sits above the nose deck, so the hull's black inside faces would only fill the view.
	var bspec: Dictionary = ModelSpecs.get_spec(stats.model_id)
	if not bspec.is_empty() and String((bspec.get("fus", {}) as Dictionary).get("profile", "")) == "bomber":
		return
	if _blackout_mat == null:
		_blackout_mat = StandardMaterial3D.new()
		_blackout_mat.albedo_color = Color(0.0, 0.0, 0.0)
		_blackout_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blackout_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var nm: String = String(mi.name).to_lower()
		var skip: bool = false
		for key in ["prop", "blade", "spinner", "disc", "canopy", "glass", "pilot", "wheel", "tyre", "gear", "leg", "muzzle", "outline", "blackout", "gun", "tracer"]:
			if nm.contains(key):
				skip = true
				break
		if skip:
			continue
		var twin := MeshInstance3D.new()
		twin.name = "Blackout"
		twin.mesh = mi.mesh
		twin.material_override = _blackout_mat
		twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		twin.visible = false
		mi.add_child(twin)
		_blackout.append(twin)
	# a solid black cockpit floor under the pilot's eye, reaching well forward: glazed noses and open
	# floors then read as a dark cockpit instead of showing the ground straight through the aircraft
	var mount: Node3D = get_cockpit_mount()
	if mount != null and AircraftCatalog.BOMBER_IDS.has(stats.model_id):   # fighters have a closed nose; bombers have glazing
		var fb := BoxMesh.new()
		fb.size = Vector3(1.5, 0.04, 4.0)
		var floor_mi := MeshInstance3D.new()
		floor_mi.name = "BlackoutFloor"
		floor_mi.mesh = fb
		var floor_mat := StandardMaterial3D.new()
		floor_mat.albedo_color = Color(0.0, 0.0, 0.0)
		floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		floor_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		floor_mi.material_override = floor_mat
		floor_mi.position = Vector3(0.0, -0.55, -1.2)
		floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		floor_mi.visible = false
		mount.add_child(floor_mi)
		_blackout.append(floor_mi)


func set_gear(down: bool) -> void:
	if down == gear_down:
		return
	gear_down = down
	gear_changed.emit(self, down)


## Place on the ground or in the air. heading_deg: 0 = north.
func reset_pose(pos: Vector3, heading_deg: float, airborne: bool, start_speed: float = -1.0) -> void:
	if damage_model != null:
		damage_model.repair()
	state = State.ALIVE
	add_to_group("damageable")
	if weapons:
		weapons.rockets_left = stats.rockets
	health = stats.max_health
	ammo = stats.ammo
	bombs = stats.bombs
	boost_energy = 1.0
	boost_locked = false
	boosting = false
	stalled = false
	_stall_amount = 0.0
	_pitch_rate = 0.0
	_roll_rate = 0.0
	_yaw_rate = 0.0
	_impact_shake = 0.0
	_aoa = 0.0
	_wing_drop = 0.0
	if _model:
		_model.visible = true
	var dir: Vector3 = WorldCoords.heading_to_dir(heading_deg)
	global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), pos)
	_path_dir = dir
	flap_setting = 0
	flap_deploy = 0.0
	on_ground = not airborne
	trim_speed = 0.0
	alt_hold_active = false
	_n_target = 1.0
	if airborne:
		speed = start_speed if start_speed > 0.0 else stats.max_speed * 0.7
		throttle = 0.7
		throttle_target = 0.7
		set_gear(false)
	else:
		speed = 0.0
		throttle = 0.0
		throttle_target = 0.0
		set_gear(true)
	_apply_gear_visual()


var _collide_cd: float = 0.0   # seconds until this aircraft can be part of another collision


## Aircraft hit each other: airborne aircraft whose spheres overlap take damage scaled by closing speed.
## Ramming credits the kill to whoever struck (the player gets the kill if they hit an enemy).
func _check_collisions(delta: float) -> void:
	_collide_cd = maxf(_collide_cd - delta, 0.0)
	if state != State.ALIVE or on_ground or _collide_cd > 0.0:
		return
	var iid: int = get_instance_id()
	for n in get_tree().get_nodes_in_group("aircraft"):
		var o := n as Aircraft
		# each pair is checked once, from the lower instance id
		if o == null or o.get_instance_id() <= iid or o.state != State.ALIVE or o.on_ground or o._collide_cd > 0.0:
			continue
		var d: Vector3 = o.global_position - global_position
		if d.length() > (hit_radius + o.hit_radius) * 0.85:
			continue
		var closing: float = (velocity - o.velocity).length()
		var dmg: float = clampf(25.0 + closing * 0.6, 35.0, 200.0)
		_collide_cd = 1.0
		o._collide_cd = 1.0
		FX.explosion(global_position + d * 0.5, 2.0)
		take_damage(dmg, o)
		o.take_damage(dmg, self)
		return


## Number of men aboard (one parachute each when they bail out or the aircraft is shot down intact).
func crew_count() -> int:
	var key: String = String(stats.id) if stats != null else ""
	var table: Dictionary = {"defiant": 2, "bf110": 2, "ju87": 2, "mosquito": 2, "blenheim": 3, "a20": 3, "ju52": 3,
		"c47": 4, "do17": 4, "ju88": 4, "he111": 5, "b25": 6, "b26": 6, "fw200": 6, "lancaster": 7}
	for k in table:
		if key.begins_with(k):
			return int(table[k])
	return 1


func take_damage(amount: float, source: Node = null) -> void:
	if state != State.ALIVE or invulnerable:
		return
	health = maxf(health - amount, 0.0)
	_regen_cd = 8.0        # pause the player's slow self-repair while under fire
	if _dmg_side == 0.0:
		_dmg_side = 1.0 if randf() < 0.5 else -1.0
	_impact_shake = minf(_impact_shake + amount * 0.02, 1.0)
	if damage_model != null:
		damage_model.on_hit(amount, source, _pending_hit, _pending_dir)
	_pending_hit = Vector3.ZERO
	_pending_dir = Vector3.ZERO
	damaged.emit(self, amount, health)
	if not player_controlled and WeaponWorld.is_player_source(source):
		Weapons.player_hit.emit(self, amount)
	if health <= 0.0:
		state = State.DYING
		_dying_spin = randf_range(-1.5, 1.5)
		# sometimes a kill detonates in the air rather than gliding down (fuel / ammo going up)
		if randf() < 0.35 and not has_meta("bailed"):     # an abandoned aircraft flies on and crashes, it never airbursts
			_explode_t = randf_range(0.4, 2.2)
		destroyed.emit(self, source)
		if not player_controlled and WeaponWorld.is_player_source(source):
			Weapons.player_kill.emit(self)


# ---------------------------------------------------------------- process

func _process(delta: float) -> void:
	_check_collisions(delta)
	delta = minf(delta, 0.05)
	if state == State.DEAD:
		return
	_update_wind(delta)
	_update_air_data()
	_update_flaps(delta)
	if state == State.ALIVE and player_controlled:
		_read_input()
	elif state == State.DYING:
		cmd_pitch = -0.45   # nose drops: death spiral
		cmd_roll = _dying_spin
		cmd_yaw = 0.0
		cmd_boost = false
		cmd_fire = false
		throttle_target = 0.0
		if _explode_t > 0.0:
			_explode_t -= delta
			if _explode_t <= 0.0:
				_explode_in_air()
	if not player_controlled and cmd_fire and state == State.ALIVE:
		fire_requested.emit(self)   # AI fire (player emits from _read_input)
	_update_throttle_boost(delta)
	_update_rotation(delta)
	_update_speed(delta)
	_update_flight_path(delta)
	_move_and_ground(delta)
	_update_visuals(delta)
	_update_shake(delta)
	_regen_health(delta)
	_update_engine_sound()
	_update_vapor(delta)
	_ground_dust(delta)
	_contrails(delta)
	if player_controlled:
		AudioManager.set_engine_state(throttle, speed / stats.max_speed)
		FX.audio.wind(speed / stats.max_speed, wind.length(), turbulence, _cockpit_view, on_ground)


## Optional very slow self-repair for the player (Options > Player repairs). Paused for a few seconds after a hit.
const REPAIR_RATE: float = 0.5      # hit points per second
var _regen_cd: float = 0.0


func _regen_health(delta: float) -> void:
	if not player_controlled or not GameState.player_heal or state != State.ALIVE:
		return
	if _regen_cd > 0.0:
		_regen_cd -= delta
		return
	if health < stats.max_health:
		health = minf(health + REPAIR_RATE * delta, stats.max_health)
		if health >= stats.max_health and damage_model != null:
			damage_model.repair()      # fully patched up: holes and part damage go too


## Vapour contrails above 1000 m: a drifting white trail emitted just behind the tail so it streams
## out behind the aircraft (not from the nose / propellers). Only aircraft near the camera trail, so the
## shared puff pool is never starved.
const CONTRAIL_ALT_M := 1000.0
var _contrail_acc: float = 0.0
var _contrail_local: Vector3 = Vector3.ZERO
var _contrail_ready: bool = false
var _contrail_node: ContrailRibbon = null


## Emission point in the aircraft's local space: just aft of the tail, cached from the model's bounds.
func _contrail_anchor() -> Vector3:
	if _contrail_ready or _model == null:
		return _contrail_local
	var box := AABB()
	var have: bool = false
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != self:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b: AABB = mi.mesh.get_aabb()
		for k in 8:
			var c: Vector3 = b.position + Vector3(
				b.size.x * float(k & 1), b.size.y * float((k >> 1) & 1), b.size.z * float((k >> 2) & 1))
			var w: Vector3 = xf * c
			if have:
				box = box.expand(w)
			else:
				box = AABB(w, Vector3.ZERO)
				have = true
	if have:
		_contrail_local = Vector3(box.get_center().x, box.get_center().y, box.end.z + 0.6)
		_contrail_ready = true
	return _contrail_local


func _contrails(delta: float) -> void:
	if stats == null or state != Aircraft.State.ALIVE or on_ground or _model == null:
		return
	var alt: float = get_altitude_m()
	if alt < CONTRAIL_ALT_M:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_squared_to(global_position) > 5000.0 * 5000.0:
		return
	if _contrail_node == null:
		_contrail_node = ContrailRibbon.new()
		add_child(_contrail_node)
	var f: float = clampf((alt - CONTRAIL_ALT_M) / 250.0, 0.0, 1.0)
	_contrail_node.add_point(global_transform * _contrail_anchor(), f)


## Positional engine sound for every aircraft except the player's (the player has the cockpit drone).
## Only aircraft within ~3 km of the camera make sound, so a big formation costs nothing at range.
var _engine3d: AudioStreamPlayer3D = null


func _update_engine_sound() -> void:
	if player_controlled or stats == null:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	var near: bool = state == State.ALIVE and cam != null and cam.global_position.distance_squared_to(global_position) < 3200.0 * 3200.0
	if not near:
		if _engine3d != null and _engine3d.playing:
			_engine3d.stop()
		return
	if _engine3d == null:
		_engine3d = FX.audio.make_engine_player(stats.engine_sound, stats.engine_count)
		add_child(_engine3d)
	if not _engine3d.playing:
		_engine3d.play()
	FX.audio.update_engine_player(_engine3d, throttle, speed / maxf(stats.max_speed, 1.0), stats.engine_sound)


## Wingtip condensation: hard pulls (high g) leave white vapour trails off both wingtips. Only drawn near the camera.
var _vapor_k: float = 0.0
var _vapor_last: Array = []
var _tip: Vector3 = Vector3.ZERO     # right wingtip in aircraft space (x = half span)
var _tip_ready: bool = false


func _update_vapor(delta: float) -> void:
	if stats == null or state != State.ALIVE:
		_vapor_last.clear()
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_squared_to(global_position) > 2600.0 * 2600.0:
		_vapor_k = 0.0
		_vapor_last.clear()
		return
	if not _tip_ready:
		_tip_ready = true
		var spec: Dictionary = ModelSpecs.get_spec(stats.model_id)
		var sc: float = float(spec.get("scale", 1.1))
		if spec.has("wing"):
			var w: Dictionary = spec["wing"]
			_tip = Vector3(float(w["half"]), float(w["y"]) + float(w.get("dihedral", 0.0)), float(w["le_z"]) + float(w["ct"]) * 0.5) * sc
		else:
			_tip = Vector3(hit_radius * 0.9, -0.2, 0.4)
	var want: float = clampf((absf(g_load) - 2.6) / 2.2, 0.0, 1.0) if speed > stats.stall_speed * 1.25 else 0.0
	_vapor_k = move_toward(_vapor_k, want, delta * 1.5)
	var tips: Array = [global_transform * Vector3(-_tip.x, _tip.y, _tip.z), global_transform * _tip]
	if _vapor_k > 0.04 and _vapor_last.size() == 2:
		for i in 2:
			var a: Vector3 = _vapor_last[i]
			var b: Vector3 = tips[i]
			var n: int = clampi(int(ceil(a.distance_to(b) / 3.5)), 1, 4)
			for j in n:
				FX.vapor_puff(a.lerp(b, (float(j) + 1.0) / float(n)), Vector3(randf_range(-0.3, 0.3), randf_range(0.1, 0.5), randf_range(-0.3, 0.3)),
					0.6 + _vapor_k * 0.7, 0.2 + _vapor_k * 0.4)
	_vapor_last = tips


## Sample the wind at the aircraft. Called every frame.
func _update_wind(delta: float) -> void:
	var wm: Node = get_node_or_null("/root/WeatherManager")
	if wm == null:
		return
	# Wind only nudges the aircraft: scaled down and capped so it can never stop or throw a flying aircraft around.
	wind = (wm.call("get_wind", global_position) as Vector3 * WIND_EFFECT).limit_length(WIND_MAX)
	var fwd: Vector3 = get_forward()
	var right: Vector3 = global_transform.basis.x
	headwind = -wind.dot(Vector3(fwd.x, 0.0, fwd.z).normalized()) if (fwd.x != 0.0 or fwd.z != 0.0) else 0.0
	crosswind = wind.dot(Vector3(right.x, 0.0, right.z).normalized())
	turbulence = float(wm.call("get_turbulence", altitude_agl)) if state != State.DEAD else 0.0


## Air density from altitude (ISA-like, 8.5 km scale height) and the equivalent airspeed the wings feel.
func _update_air_data() -> void:
	var alt_m: float = maxf(get_altitude_m(), 0.0)
	air_density = exp(-alt_m / 8500.0)
	eas = speed * sqrt(air_density)


## Angle of attack in the aircraft's vertical plane: positive when the nose is above the flight path (relative
## wind from below the wing), negative when it is below (wind from above the wing).
func _alpha_signed() -> float:
	var pl: Vector3 = global_transform.basis.inverse() * _path_dir     # flight path in aircraft axes (-Z fwd, +Y up)
	return atan2(-pl.y, -pl.z)


## Cycle the flaps UP -> 15 -> 35 -> UP. Extending is refused above the flap speed limit.
func cycle_flaps() -> void:
	var nxt: int = (flap_setting + 1) % 3
	if nxt > flap_setting and speed > stats.stall_speed * 2.0:
		flaps_changed.emit(self, "FLAPS: TOO FAST")
		return
	flap_setting = nxt
	flaps_changed.emit(self, "FLAPS %s" % FLAP_NAMES[nxt])


func _update_flaps(delta: float) -> void:
	flap_deploy = move_toward(flap_deploy, float(FLAP_TARGETS[flap_setting]), 0.3 * delta)
	if flap_setting > 0 and speed > stats.stall_speed * 2.6 and state == State.ALIVE:
		flap_setting = 0
		take_damage(6.0)
		flaps_changed.emit(self, "FLAPS DAMAGED: OVERSPEED")
	var deg: float = flap_deploy * 35.0
	if _flap_l:
		_flap_l.rotation.x = deg_to_rad(deg)
	if _flap_r:
		_flap_r.rotation.x = deg_to_rad(deg)


## Airspeed the wings actually feel while rolling on the ground: ground speed plus the headwind.
func ground_airspeed() -> float:
	return maxf(speed + headwind, 0.0)


func _read_input() -> void:
	var inv: float = -1.0 if GameState.invert_pitch else 1.0
	var dt: float = get_process_delta_time()
	cmd_pitch = _stick(cmd_pitch, Input.get_axis("pitch_down", "pitch_up") * inv, dt)
	cmd_roll = _stick(cmd_roll, Input.get_axis("roll_left", "roll_right"), dt)
	cmd_yaw = _stick(cmd_yaw, Input.get_axis("yaw_left", "yaw_right"), dt)
	# Throttle: a tap moves it 1% (fine setting, e.g. to find the level-flight throttle); held, it starts to run
	# after a quarter second, slowly at first, then at the full 0.6 per second.
	var td: float = Input.get_axis("throttle_down", "throttle_up")
	if Input.is_action_just_pressed("throttle_up"):
		throttle_target = minf(throttle_target + 0.01, 1.0)
		_thr_held = 0.0
	elif Input.is_action_just_pressed("throttle_down"):
		throttle_target = maxf(throttle_target - 0.01, 0.0)
		_thr_held = 0.0
	if absf(td) > 0.01:
		_thr_held += dt
		var run: float = 0.0 if _thr_held < 0.25 else (0.2 if _thr_held < 0.8 else 0.6)
		throttle_target = clampf(throttle_target + td * run * dt, 0.0, 1.0)
	else:
		_thr_held = 0.0
	cmd_boost = Input.is_action_pressed("boost")
	if Input.is_action_just_pressed("weapon_toggle"):
		var modes: Array = [0]
		if stats.rockets > 0:
			modes.append(1)
		if stats.bombs > 0:
			modes.append(2)
		weapon_mode = modes[(modes.find(weapon_mode) + 1) % modes.size()]
		weapon_bombs = weapon_mode == 2
		weapon_changed.emit(weapon_bombs)
	cmd_fire = Input.is_action_pressed("fire") and weapon_mode == 0
	if weapon_mode != 0:
		if Input.is_action_just_pressed("fire") and state == State.ALIVE:
			bomb_requested.emit(self)
	elif cmd_fire and state == State.ALIVE:
		fire_requested.emit(self)
	brake_on = Input.is_action_pressed("brake")
	if Input.is_action_just_pressed("flaps") and state == State.ALIVE:
		cycle_flaps()
	if Input.is_action_just_pressed("gear"):
		set_gear(not gear_down)
	if Input.is_action_just_pressed("assist_toggle"):
		auto_level = not auto_level
		GameState.auto_level = auto_level
	if sight_hold and not on_ground:
		_sight_autopilot()


## Bombing run autopilot: wings level, altitude held, and a gentle bank (max ~10 degrees) from the steering keys
## so the bomber can be nudged onto the target line without ever leaving level flight.
func _sight_autopilot() -> void:
	var steer: float = clampf(Input.get_axis("roll_left", "roll_right") + Input.get_axis("yaw_left", "yaw_right"), -1.0, 1.0)
	cmd_roll = clampf((steer * deg_to_rad(10.0) - _bank_angle()) * 2.5, -0.6, 0.6)
	cmd_yaw = 0.0
	var spd: float = maxf(velocity.length(), 1.0)
	var path: float = asin(clampf(velocity.y / spd, -1.0, 1.0))
	var want: float = clampf((sight_alt_y - global_position.y) * 0.004, -0.07, 0.07)
	cmd_pitch = clampf((want - path) * 6.0, -0.5, 0.5)


## Stick travel: keys are on/off, so a key press is eased in over ~0.18 s and released over ~0.12 s
## (a real stick takes a moment to move) instead of stepping the control rate in one frame. Analog
## gamepad input is already smooth and only gets the same short travel limit.
func _stick(cur: float, want: float, dt: float) -> float:
	var pushing: bool = absf(want) > absf(cur) and (cur == 0.0 or signf(want) == signf(cur))
	return move_toward(cur, want, (5.5 if pushing else 8.5) * dt)


func _update_throttle_boost(delta: float) -> void:
	throttle = move_toward(throttle, throttle_target, 0.7 * delta)
	var want: bool = cmd_boost and not boost_locked and boost_energy > 0.0 and state == State.ALIVE and not on_ground
	if want:
		boost_energy = maxf(boost_energy - delta / stats.boost_duration, 0.0)
		if boost_energy <= 0.0:
			boost_locked = true
	else:
		boost_energy = minf(boost_energy + delta / stats.boost_cooldown, 1.0)
		if boost_locked and boost_energy >= 0.5:
			boost_locked = false
	if want != boosting:
		boosting = want
		boost_changed.emit(self, boosting)


func _bank_angle() -> float:
	var b: Basis = global_transform.basis
	return atan2(-b.x.y, b.y.y)


func _pitch_angle() -> float:
	return asin(clampf(-global_transform.basis.z.y, -1.0, 1.0))


## 0 = undamaged .. 1 = about to fall out of the sky. Drives engine power, control authority and the pull to one side.
func damage_level() -> float:
	return clampf(1.0 - health / maxf(stats.max_health, 1.0), 0.0, 1.0)


## Pitch trim. Works out what lift the stick-free aircraft should ask its wing for (_n_target) and learns the
## small angle-of-attack correction the strip wing needs to really deliver it (without it the wings carried only
## ~92% of the weight at "trim", so every hands-off aircraft sagged into a dive).
##  - Stick held: the trim follows the current speed (1 g).
##  - Stick released, assist on: altitude hold - the height when the stick was let go (plus a short projection of
##    the climb/sink rate) is held with gentle lift changes; banked turns get the extra lift a level turn needs.
##  - Stick released, assist off (player): speed stability as on a real trimmed aircraft - faster than trim speed
##    gives more lift (climb), slower gives less (sink). Speed therefore stays near trim_speed, and the throttle
##    sets the climb rate: find the throttle at which the VSI reads zero and the aircraft stays at that height.
func _update_trim(delta: float) -> void:
	var vs_scale: float = WorldCoords.VERTICAL_SCALE
	var upright: float = global_transform.basis.y.y
	var bank: float = _bank_angle()
	var stick_free: bool = absf(cmd_pitch) < 0.05
	var steady: bool = state == State.ALIVE and not on_ground and _stall_amount < 0.05 and upright > 0.5 \
		and absf(_roll_rate) < 0.7 and eas > stats.stall_speed * 1.05
	# learn the wing's real lift slope offset (only in calm, unstalled, mostly upright flight)
	if steady and wing != null and absf(_alpha_signed()) < WingModel.CRIT * 0.7:
		var dn_da: float = _lift_slope()
		var a_1g: float = _alpha_signed() + (1.0 - g_load) / dn_da
		var raw: float = WingModel.trim_alpha(stats.stall_speed, eas, flap_deploy)
		var want: float = clampf(a_1g - raw, -0.08, 0.08)
		_trim_corr = lerpf(_trim_corr, want, 1.0 - exp(-0.8 * delta))
	var was_hold: bool = alt_hold_active
	alt_hold_active = auto_level and stick_free and steady and absf(bank) < deg_to_rad(50.0) and not sight_hold
	if alt_hold_active:
		if not was_hold:
			_hold_y = global_position.y + velocity.y * 1.2     # capture, with a short projection of the climb/sink
		var dy_m: float = (_hold_y - global_position.y) / vs_scale
		var vz_m: float = velocity.y / vs_scale
		var n_lvl: float = 1.0 / maxf(cos(bank), 0.65)            # a level turn needs more lift
		_n_target = clampf(n_lvl + 0.010 * clampf(dy_m, -60.0, 60.0) - 0.055 * vz_m, 0.75, 1.45)
		trim_speed = eas
	elif player_controlled and stick_free and steady:
		if trim_speed <= 0.0:
			trim_speed = eas
		var r: float = eas / trim_speed
		var vz2: float = velocity.y / vs_scale
		_n_target = clampf(r * r - 0.04 * vz2, 0.7, 1.4)       # small sink-rate damping tames the phugoid
	else:
		_n_target = 1.0
		if not stick_free or on_ground or state != State.ALIVE or _stall_amount > 0.05:
			trim_speed = maxf(eas, stats.stall_speed * 1.15)


## dn/d(alpha) of the wing at the current equivalent airspeed (weights per radian), from the strip model's scaling.
func _lift_slope() -> float:
	var ss: float = maxf(stats.stall_speed, 1.0)
	return maxf(WingModel.CL_ALPHA * eas * eas / (ss * ss * WingModel.CL_MAX_REF), 0.5)


## The angle of attack the trim aims for: the ideal-wing 1 g angle + the learned wing correction + whatever extra
## (or less) lift _update_trim asks for.
func _trim_alpha_cmd() -> float:
	var a: float = WingModel.trim_alpha(stats.stall_speed, eas, flap_deploy) + _trim_corr
	if not on_ground:
		a += (_n_target - 1.0) / _lift_slope()
	return clampf(a, -0.12, WingModel.CRIT * 0.85)


func _update_rotation(delta: float) -> void:
	_update_trim(delta)
	var air_auth: float = clampf(eas / (stats.stall_speed * 1.1), 0.0, 1.0)
	# Stalled wings keep ~55% authority so the pilot can always push through and recover.
	var ctrl: float = air_auth * (1.0 - 0.45 * _stall_amount)
	# Stiffer controls near top speed (dynamic pressure), so fast dives need a firm hand.
	var fast: float = clampf((eas - stats.max_speed * 0.85) / (stats.max_speed * 0.5), 0.0, 1.0)
	# Heavier elevator near stall speed: no snap-rotation off the runway or flick stalls when slow.
	var slow_k: float = clampf((eas - stats.stall_speed) / (stats.stall_speed * 0.8), 0.0, 1.0)
	var pitch_auth: float = ctrl * (1.0 - 0.4 * fast) * (0.55 + 0.45 * slow_k)
	var roll_auth: float = ctrl * (1.0 - 0.25 * fast)
	# battle damage: below ~half health the controls get heavy and sluggish
	var dmg: float = damage_level()
	var ctl_loss: float = 1.0 - 0.4 * smoothstep(0.4, 1.0, dmg)
	pitch_auth *= ctl_loss
	roll_auth *= ctl_loss
	var dm: AircraftDamageModel = damage_model
	var parts_hit: bool = dm != null and dm.any_damage()
	if parts_hit:
		pitch_auth *= dm.pitch_auth_k()
		roll_auth *= dm.roll_auth_k()
	if on_ground:
		pitch_auth = clampf((ground_airspeed() - stats.stall_speed * 0.65) / (stats.stall_speed * 0.3), 0.0, 1.0)
		roll_auth = 0.0

	# Pulling harder into a stall does nothing useful; pushing forward is always fully effective.
	var pull_limit: float = 1.0 - 0.6 * _stall_amount if cmd_pitch > 0.0 else 1.0
	# Soft angle-of-attack limiter: pulling harder as the wing nears its critical angle fades out, so hard turns ride
	# the edge of the stall instead of tipping over it. Slow-speed stalls still happen (trim AoA itself runs out).
	if cmd_pitch != 0.0 and not on_ground:
		var al: float = _alpha_signed()
		if cmd_pitch * al > 0.0:
			pull_limit *= 1.0 - smoothstep(0.17, 0.25, absf(al))
	var t_pitch: float = cmd_pitch * pull_limit * deg_to_rad(stats.pitch_rate_deg) * pitch_auth
	var t_roll: float = cmd_roll * deg_to_rad(stats.roll_rate_deg) * roll_auth
	var t_yaw: float = cmd_yaw * deg_to_rad(stats.yaw_rate_deg) * (0.4 + 0.6 * ctrl)
	# a shot-up aircraft wants to roll off to one side; the pilot has to hold it against the stick
	if dmg > 0.35 and not on_ground and state == State.ALIVE:
		t_roll += _dmg_side * deg_to_rad(9.0) * smoothstep(0.35, 0.9, dmg) * air_auth * (0.4 if parts_hit else 1.0)
	# where it was hit matters: a holed / aileron-less wing drops, a shot-up tail makes the nose wander
	if parts_hit and not on_ground and state == State.ALIVE:
		t_roll += dm.roll_bias() * air_auth
		t_yaw += dm.yaw_wander(delta) * air_auth

	# Auto-level assist
	if auto_level and state == State.ALIVE and not on_ground:
		var bank: float = _bank_angle()
		var roll_free: float = 1.0 - minf(absf(cmd_roll) * 3.0, 1.0)
		t_roll += clampf(-bank * stats.assist_strength, -deg_to_rad(stats.roll_rate_deg), deg_to_rad(stats.roll_rate_deg)) * roll_free * air_auth
		var pit: float = _pitch_angle()
		var pitch_free: float = 1.0 - minf(absf(cmd_pitch) * 3.0, 1.0)
		var level_w: float = 1.0 - smoothstep(deg_to_rad(55.0), deg_to_rad(80.0), absf(bank))
		if alt_hold_active:
			level_w = 0.0       # the altitude hold (via the trim) flies the pitch; levelling the NOSE made it sink
		t_pitch += clampf(-pit * stats.assist_strength * 0.25, -0.35, 0.35) * pitch_free * air_auth * level_w

	# Stall: nose drops and a wing drops (incipient spin)
	if _stall_amount > 0.0 and not on_ground:
		var pit2: float = _pitch_angle()
		t_pitch -= _stall_amount * deg_to_rad(36.0) * smoothstep(deg_to_rad(-80.0), deg_to_rad(-60.0), pit2)
		t_roll += _stall_amount * _wing_drop * deg_to_rad(6.0)      # tie-breaker; the real wing drop comes from the strip model
		t_yaw += _stall_amount * _wing_drop * deg_to_rad(8.0)

	# Wing rolling moment from the strip model: roll damping, dihedral stability, stall wing drop. More lift on the
	# right wing rolls the aircraft LEFT, hence the minus sign (roll rate + = right).
	if not on_ground and wing != null:
		t_roll -= wing.roll_moment * ROLL_COUPLING
		t_pitch -= flap_deploy * deg_to_rad(6.0) * air_auth       # flaps put the nose down a little
	# Auto-trim: a trimmed aircraft holds the angle of attack that carries its weight when flown upright. With the
	# stick free the nose therefore follows the flight path; upside down that same angle points the lift DOWN, so
	# the aircraft pushes over into a dive until the pilot pushes the stick forward.
	if not on_ground and state == State.ALIVE and _stall_amount < 0.25:
		var a_trim: float = _roll_trim(_trim_alpha_cmd())
		var trim_free: float = 1.0 - minf(absf(cmd_pitch) * 3.0, 1.0)
		var trim_w: float = 1.0 - smoothstep(0.08, 0.25, _stall_amount)
		t_pitch += clampf((a_trim - _alpha_signed()) * 5.0, -deg_to_rad(25.0), deg_to_rad(25.0)) * trim_free * air_auth * trim_w
	# Static stability: the tail keeps the nose pointing into the relative wind, so a stalled aircraft whose nose is
	# far from its flight path swings back toward it (this is what lets it fall out of a stall). Acts with or without
	# the stick, but never beyond what the elevator can answer.
	if not on_ground and state != State.DEAD:
		var a_ref: float = _roll_trim(_trim_alpha_cmd())
		t_pitch -= clampf(_alpha_signed() - a_ref, -2.0, 2.0) * (0.8 + 1.6 * _stall_amount) * clampf(eas / stats.stall_speed, 0.3, 1.0)
	# Rough air: gusty roll/pitch kicks that scale with turbulence, stronger when slow and in the lower air.
	if turbulence > 0.01 and not on_ground:
		var ph: float = float(get_instance_id() % 97)
		var tt: float = Time.get_ticks_msec() * 0.001
		var kick: float = turbulence * (0.6 + 0.4 * (1.0 - clampf(speed / stats.max_speed, 0.0, 1.0)))
		kick *= clampf((altitude_agl - 4.0) / 40.0, 0.0, 1.0)     # no gust can roll a wingtip into the runway just after lift-off
		t_roll += kick * deg_to_rad(26.0) * (sin(tt * 1.7 + ph) * 0.6 + sin(tt * 3.9 + ph * 2.0) * 0.4)
		t_pitch += kick * deg_to_rad(9.0) * (sin(tt * 2.3 + ph * 0.7) * 0.6 + sin(tt * 5.1 + ph) * 0.4)
		t_yaw += kick * deg_to_rad(4.0) * sin(tt * 1.3 + ph * 1.3)
		shake_intensity = maxf(shake_intensity, kick * 0.18)
	var k: float = 1.0 - exp(-stats.rate_response * delta)
	_pitch_rate = lerpf(_pitch_rate, t_pitch, k)
	_roll_rate = lerpf(_roll_rate, t_roll, k)
	_yaw_rate = lerpf(_yaw_rate, t_yaw, k)

	rotate_object_local(Vector3.RIGHT, _pitch_rate * delta)
	rotate_object_local(Vector3.BACK, -_roll_rate * delta)
	rotate_object_local(Vector3.UP, -_yaw_rate * delta)

	# Bank turns: heading change proportional to bank.
	# Faded out (not switched off) as the aircraft rolls past the vertical, otherwise hovering near ~100 degrees
	# of bank toggles ~1 rad/s of yaw on and off from one frame to the next (a visible kick in steep turns).
	var turn_w: float = smoothstep(-0.4, 0.05, global_transform.basis.y.y)
	# ...and while rolling fast: at knife-edge it would swing the nose around and wobble the roll
	turn_w *= 1.0 - smoothstep(0.7, 1.6, absf(_roll_rate))
	if not on_ground and turn_w > 0.0:
		# Turn rate falls with speed (w = g*tan(bank)/v): tight at slow speed, wide when fast.
		var turn_k: float = clampf(stats.max_speed * 0.55 / maxf(speed, 20.0), 0.7, 1.45)
		rotate(Vector3.UP, global_transform.basis.x.y * stats.bank_turn_rate * turn_k * air_auth * turn_w * delta)

	orthonormalize()


## During a fast aileron roll (stick not pulled or pushed) the trimmed angle of attack follows the wing's
## attitude: lift up when upright, none at knife-edge, a push when inverted, so the aircraft rolls round its
## flight path instead of the nose falling away (what a pilot does with the stick). Otherwise: plain trim.
func _roll_trim(a_trim: float) -> float:
	var k: float = smoothstep(0.7, 1.6, absf(_roll_rate)) * (1.0 - minf(absf(cmd_pitch) * 3.0, 1.0))
	if k <= 0.0 or on_ground:
		return a_trim
	var up: float = global_transform.basis.y.y
	var a_roll: float = a_trim * up if up >= 0.0 else a_trim * up * 1.6   # cambered wing: push harder inverted
	return lerpf(a_trim, a_roll, k)


func _update_speed(delta: float) -> void:
	var max_s: float = stats.max_speed
	var target: float
	if on_ground:
		target = lerpf(0.0, max_s, throttle)
	else:
		target = lerpf(stats.stall_speed * 1.15 / sqrt(air_density), max_s, throttle)
	var dmg_s: float = damage_level()
	var boost_on: bool = boosting and dmg_s < 0.6          # a badly hit engine can't take emergency power
	if boost_on:
		target += stats.boost_bonus
	var thrust_k: float = clampf(pow(air_density, 0.7), 0.35, 1.0)      # engine power falls with altitude
	var rate: float = stats.accel * thrust_k if target > speed else stats.decel
	if boost_on:
		rate = stats.accel * 3.0 * thrust_k
	if on_ground and target > speed:
		rate *= GROUND_RUN_K      # wheels and prop wash: it takes longer to build take-off speed on the runway
	if on_ground and throttle < 0.05:
		rate = 9.0
	if on_ground and brake_on:
		target = 0.0
		rate = 18.0          # wheel brakes: much stronger than rolling resistance
	if on_ground:
		speed = move_toward(speed, target, rate * delta)
	else:
		# In the air: thrust against drag instead of easing toward a throttle setpoint. Parasite drag rises with
		# speed squared and exactly balances full throttle at max_speed (max_speed + boost_bonus when boosting), so
		# top speeds are unchanged, but the engine is weaker (ENGINE_POWER) and turns cost far more energy:
		# lost speed takes a while to win back.
		var d0: float = stats.accel * ENGINE_POWER
		var vr: float = speed / max_s
		var engine_k: float = 1.0 - 0.5 * smoothstep(0.3, 1.0, dmg_s)     # lost power: top speed and climb fall away
		if damage_model != null:
			engine_k *= damage_model.engine_k()
		var thrust: float = d0 * throttle * (1.3 - 0.3 * clampf(vr, 0.0, 1.0)) * thrust_k * engine_k
		if boost_on:
			var bb: float = (max_s + stats.boost_bonus) / max_s
			thrust = maxf(thrust, d0 * bb * bb * 1.4 * thrust_k)
		var drag: float = d0 * vr * vr * thrust_k * (damage_model.drag_k() if damage_model != null else 1.0)
		speed += (thrust - drag) * delta
		speed -= _path_dir.y * stats.gravity_accel * delta                    # climbing along the path costs speed, diving gains it
		speed -= INDUCED_DRAG * maxf(absf(g_load) - 1.0, 0.0) * clampf(vr + 0.3, 0.5, 1.3) * delta   # hard turns bleed energy
		speed -= flap_deploy * (2.5 + 8.0 * speed / max_s) * delta             # flap drag
	if gear_down and not on_ground:
		speed -= 6.0 * delta * (speed / max_s)
	if state == State.DYING:
		speed = maxf(speed, stats.stall_speed * 0.9)
	# Stall buffet adds drag, but never more than a dive can win back, and the airspeed never decays to
	# zero in the air: a stalled aircraft mushes down at roughly 55% of stall speed and can fly out of it.
	speed -= _stall_amount * 12.0 * delta
	var min_air: float = 0.0 if on_ground else stats.stall_speed * 0.55 / sqrt(air_density)
	speed = clampf(speed, min_air, (max_s + stats.boost_bonus) * 1.25)


## Flight path from wing lift. The strip-theory wing (wing_model.gd) gives the lift along the wing normal at the
## current angle of attack, speed, air density and wing attitude; that lift plus gravity bends the flight path.
## Flown upright at trim the wings carry exactly the weight; rolled over they push the aircraft DOWN. Thin air or
## low speed means less lift (sinking, then the stall). Stall comes from the stalled share of the wing area.
func _update_flight_path(delta: float) -> void:
	var fwd: Vector3 = get_forward()
	if on_ground:
		_path_dir = fwd
		_aoa = 0.0
		_stall_amount = 0.0
		g_load = 1.0
		lift_fraction = 1.0
		if stalled:
			stalled = false
			stall_changed.emit(self, false)
		return
	var alpha_s: float = _alpha_signed()
	wing.evaluate(global_position, global_transform.basis, _path_dir, speed, alpha_s, _roll_rate, _yaw_rate, stats.stall_speed, flap_deploy)
	var n: float = clampf(wing.n_total, -3.5, 9.0)                # structural limits (g)
	g_load = n
	var nrm: Vector3 = global_transform.basis.y
	lift_fraction = n * nrm.y
	var g_w: float = stats.gravity_accel
	var a_total: Vector3 = nrm * (n * g_w) + Vector3.DOWN * g_w
	var perp: Vector3 = a_total - _path_dir * a_total.dot(_path_dir)    # only the sideways part bends the path
	_path_dir = (_path_dir + perp * (delta / maxf(speed, 12.0))).normalized()
	# The fin and rudder kill sideslip: the flight path may not slide sideways relative to the wing plane for long,
	# otherwise the aircraft crabs across the map pointing one way and travelling another.
	var side: Vector3 = global_transform.basis.x
	_path_dir = (_path_dir - side * _path_dir.dot(side) * clampf(6.0 * delta, 0.0, 1.0)).normalized()
	_aoa = acos(clampf(fwd.dot(_path_dir), -1.0, 1.0))

	# Stall: part of the wing past its critical angle, or simply too slow to fly. (It used to also stall whenever
	# the wing could not hold the aircraft up against gravity at its current attitude, which is wrong in vertical
	# or inverted flight: every loop "stalled" going up the vertical and every roll stalled at knife-edge.)
	var spd_stall: float = clampf((stats.stall_speed * 0.85 - eas) / (stats.stall_speed * 0.25), 0.0, 1.0)
	var target_stall: float = maxf(wing.stall_amount, spd_stall)
	# The stall builds and clears progressively (about 0.3 s / 0.25 s) instead of snapping.
	_stall_amount = move_toward(_stall_amount, target_stall, (3.2 if target_stall > _stall_amount else 4.0) * delta)
	# Pre-stall buffet warning a little before the wing lets go.
	var warn: float = clampf((absf(alpha_s) - WingModel.CRIT * 0.8) / (WingModel.CRIT * 0.2), 0.0, 1.0)
	warn = maxf(warn, clampf((stats.stall_speed * 1.05 - eas) / (stats.stall_speed * 0.2), 0.0, 1.0))
	if warn > 0.0 and _stall_amount < 0.2:
		shake_intensity = maxf(shake_intensity, warn * 0.18)
	var is_stalled: bool = _stall_amount > (0.1 if stalled else 0.25)
	if is_stalled != stalled:
		stalled = is_stalled
		stall_changed.emit(self, stalled)
		if stalled:
			# the wing that is further into the stall drops
			_wing_drop = signf(wing.stall_asym) if absf(wing.stall_asym) > 0.05 else (1.0 if randf() > 0.5 else -1.0)
	if _stall_amount > 0.05:
		shake_intensity = maxf(shake_intensity, _stall_amount * 0.45)


func _ground_height(pos: Vector3) -> float:
	if _terrain == null or not is_instance_valid(_terrain):
		_terrain = get_tree().get_first_node_in_group("terrain")
	if _terrain and _terrain.has_method("get_height_at"):
		return _terrain.call("get_height_at", pos)
	return 0.0


func _is_water(pos: Vector3) -> bool:
	if _terrain and _terrain.has_method("is_water_at"):
		return _terrain.call("is_water_at", pos)
	return true


func _move_and_ground(delta: float) -> void:
	var fwd: Vector3 = get_forward()
	if on_ground:
		_path_dir = fwd
		velocity = fwd * speed
	else:
		var sink: Vector3 = Vector3.DOWN * (_stall_amount * 18.0)
		velocity = _path_dir * speed + sink
	position += velocity * delta
	if not on_ground:
		position += wind * delta        # the whole air mass carries the aircraft
	elif speed > 3.0:
		# weathervaning: a crosswind turns the nose into the wind, the pilot counters with rudder/brake
		rotate(Vector3.UP, crosswind * 0.0045 * clampf(speed / 40.0, 0.0, 1.0) * delta * 3.0)

	var gh: float = _ground_height(position)
	over_water = _is_water(position)
	var floor_y: float = gh + stats.gear_height
	altitude_agl = position.y - gh
	var clearance: float = position.y - floor_y

	if on_ground:
		# Ground steering
		var steer: float = clampf(cmd_yaw + cmd_roll * 0.8, -1.0, 1.0)
		rotate(Vector3.UP, -steer * deg_to_rad(stats.ground_turn_rate_deg) * clampf(speed / 18.0, 0.0, 1.0) * delta)
		# keep wings level, drop the nose back down unless we are flying fast enough to rotate
		rotate_object_local(Vector3.BACK, _bank_angle() * clampf(8.0 * delta, 0.0, 1.0))
		var pit: float = _pitch_angle()
		var rotate_speed: float = stats.stall_speed * 0.65
		if pit < 0.0 or ground_airspeed() < rotate_speed:
			# a tail-dragger sits tail-down on its mains and tail wheel, and the tail lifts as the speed builds
			var tail_down: float = 1.0 - smoothstep(stats.stall_speed * 0.12, stats.stall_speed * 0.5, ground_airspeed())
			var goal: float = _gg_rest * tail_down if ground_airspeed() < rotate_speed else 0.0
			rotate_object_local(Vector3.RIGHT, (goal - pit) * clampf(5.0 * delta, 0.0, 1.0))
		if fwd.y > 0.04 and ground_airspeed() > stats.stall_speed * (0.95 - 0.10 * flap_deploy):
			on_ground = false
			_path_dir = fwd.rotated(global_transform.basis.x, -WingModel.trim_alpha(stats.stall_speed, maxf(ground_airspeed(), 20.0), flap_deploy))
			position.y += 0.6
			took_off.emit(self)
		else:
			position.y = lerpf(position.y, gh + ground_offset(_pitch_angle()), clampf(12.0 * delta, 0.0, 1.0)) if _gg_ok else floor_y
			if over_water and state == State.ALIVE:
				_crash("ditched")
			elif state == State.DYING:
				_crash("crash")
	elif clearance <= 0.0:
		_ground_contact(floor_y)


func _ground_contact(floor_y: float) -> void:
	var vy: float = velocity.y
	if invulnerable and state == State.ALIVE:
		position.y = floor_y
		velocity.y = maxf(vy, 0.0)
		on_ground = true
		return
	var bank: float = absf(_bank_angle())
	var pit: float = _pitch_angle()
	if state == State.DYING:
		_crash("crash")
		return
	if over_water:
		# Skimming a shallow, level touch is forgiven once; otherwise ditch.
		if vy > -10.0 and absf(pit) < deg_to_rad(8.0) and bank < deg_to_rad(25.0) and speed > stats.stall_speed:
			position.y = floor_y + 0.8
			_impact_shake = 0.6
			take_damage(12.0)
			rotate_object_local(Vector3.RIGHT, deg_to_rad(6.0))
		else:
			_crash("ditched")
		return
	var gentle: bool = vy > -stats.crash_vspeed and bank < deg_to_rad(45.0) and pit > deg_to_rad(-22.0) and pit < deg_to_rad(28.0)
	if gentle:
		position.y = floor_y
		on_ground = true
		speed = maxf(speed - headwind, 4.0)    # ground speed on touchdown = airspeed minus headwind
		_impact_shake = clampf(-vy / 40.0, 0.1, 0.6)
		if vy < -14.0:
			take_damage((-vy - 14.0) * 1.2)
		if not gear_down:
			take_damage(12.0)
		landed.emit(self)
	elif vy > -stats.crash_vspeed * 1.8 and health > 35.0 and pit > deg_to_rad(-45.0):
		# hard hit: bounce and take damage rather than instantly dying
		position.y = floor_y + 1.0
		take_damage(35.0)
		_impact_shake = 1.0
		rotate_object_local(Vector3.RIGHT, deg_to_rad(18.0))
		speed *= 0.7
	else:
		_crash("crash")


func _crash(reason: String) -> void:
	if state == State.DEAD or (invulnerable and state == State.ALIVE):
		return
	var was_dying: bool = state == State.DYING
	state = State.DEAD
	remove_from_group("damageable")
	health = 0.0
	velocity = Vector3.ZERO
	speed = 0.0
	cmd_fire = false
	if reason != "exploded":
		_spawn_crash_fx()          # a mid-air detonation has already spawned its own fireball
	if _model:
		_model.visible = false
	crashed.emit(self, reason)
	if not was_dying:
		destroyed.emit(self, null)


func _spawn_crash_fx() -> void:
	FX.crash_explosion(global_position, over_water)


## A kill that goes up in the air: fireball and debris where the aircraft was, then it is gone.
func _explode_in_air() -> void:
	_explode_t = -1.0
	FX.explosion(global_position, 13.0)
	FX.debris(global_position, 10, 1.8, 32.0, Color(0.3, 0.31, 0.29))
	FX.light_flash(global_position, 8.0, 70.0, 0.4, Color(1.0, 0.62, 0.25))
	FX.sfx("crash", global_position, 6.0, 0.05)
	_crash("exploded")


var _prop_blurred: bool = false


func _update_visuals(delta: float) -> void:
	if _prop:
		var rate: float = lerpf(9.0, 70.0, throttle) if state != State.DEAD else 0.0
		_prop.rotate_object_local(Vector3.BACK, rate * delta)
		# A propeller turning this fast cannot be drawn as blades: they land on an unrelated angle every
		# frame and strobe, which reads as the whole aircraft shaking (loudest in the cockpit view, where
		# the prop fills the screen). Past the limit the translucent PropDisc carries the prop instead.
		var blur: bool = AircraftModels.prop_blur(rate, minf(delta, 1.0 / 30.0), _prop_blurred)
		_prop_blurred = blur
		if _prop_blades:
			_prop_blades.visible = not blur
		if _prop_disc:
			_prop_disc.visible = blur
	var target_gear: float = 1.0 if gear_down else 0.0
	if not is_equal_approx(_gear_amount, target_gear):
		_gear_amount = move_toward(_gear_amount, target_gear, delta * 1.2)
		_apply_gear_visual()


func _apply_gear_visual() -> void:
	var fold: float = (1.0 - _gear_amount) * 1.45
	if _gear_l:
		_gear_l.rotation.z = -fold
		_gear_l.visible = _gear_amount > 0.05
	if _gear_r:
		_gear_r.rotation.z = fold
		_gear_r.visible = _gear_amount > 0.05


func _update_shake(delta: float) -> void:
	_impact_shake = move_toward(_impact_shake, 0.0, delta * 1.6)
	var s: float = _impact_shake
	if boosting:
		s += 0.22
	s += _stall_amount * 0.45
	if on_ground and speed > 5.0:
		s += 0.05 * clampf(speed / 50.0, 0.0, 1.0)
	shake_intensity = clampf(s, 0.0, 1.0)


var _dust_t: float = 0.0


## Dust and grass kicked up behind the wheels and propeller wash on take-off and landing rolls (nearby aircraft only).
func _ground_dust(delta: float) -> void:
	_touchdown_and_wash(delta)
	if not on_ground or state != State.ALIVE or speed < 7.0:
		return
	_dust_t -= delta
	if _dust_t > 0.0:
		return
	_dust_t = 0.09
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null and not player_controlled and cam.global_position.distance_to(global_position) > 700.0:
		return
	var tail: Vector3 = global_position + global_transform.basis.z * 4.0
	tail.y = FX.ground_height(tail) + 0.4
	if FX.is_water(tail):
		return
	FX.dust(tail, clampf(speed / stats.max_speed, 0.2, 1.0) * 1.9)


var _was_ground: bool = true
var _wash_t: float = 0.0


## Tyre smoke on touchdown, and spray off the water under a low-flying aircraft.
func _touchdown_and_wash(delta: float) -> void:
	if state != State.ALIVE:
		return
	if on_ground and not _was_ground and speed > 22.0:
		for sx in [-1.8, 1.8]:
			var w: Vector3 = global_position + global_transform.basis.x * sx + global_transform.basis.z * 0.4
			w.y = FX.ground_height(w) + 0.2
			FX.tyre_smoke(w, 1.6)
	_was_ground = on_ground
	if on_ground or speed < 20.0:
		return
	_wash_t -= delta
	if _wash_t > 0.0:
		return
	_wash_t = 0.3
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null and not player_controlled and cam.global_position.distance_to(global_position) > 700.0:
		return
	var p: Vector3 = global_position
	if p.y - FX.ground_height(p) < 22.0 and FX.is_water(p):
		FX.water_splash(Vector3(p.x, 0.0, p.z), 1.2)
