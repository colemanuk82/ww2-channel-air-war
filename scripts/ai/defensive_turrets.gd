class_name DefensiveTurrets
extends Node3D
## Defensive gun turrets for a bomber (used on the player's aircraft; AI formations have their own gunners).
## Each turret is a small dome + twin barrels on the airframe that tracks the nearest enemy fighter inside its
## firing arc and range and fires tracer bursts at it. Range shrinks in fog / rain and at night (the gunners
## see less too). Static API: DefensiveTurrets.attach(aircraft, hud) -> DefensiveTurrets.

const BASE_RANGE: float = 680.0
const TICK: float = 0.1
const MSG_COOLDOWN: float = 14.0

## Mounts, positioned against the fuselage box (not the wing span, which is far larger):
## pos.x = fraction of the fuselage half-width (+right), pos.y = fraction of the half-height added to cy,
## pos.z = fraction along the fuselage from the nose (z0) to the tail (z1). axis = rest/centre direction,
## arc = half cone (deg). Values follow the real fits: the dorsal cannot bear below the horizon, the ventral
## cannot bear above it, the tail cannot bear forward through the fuselage, the waist guns cannot cross over.
const MOUNTS := {
	"nose": {"pos": Vector3(0.0, 0.25, 0.02), "axis": Vector3(0, 0.15, -1), "arc": 50.0},
	"dorsal": {"pos": Vector3(0.0, 1.0, 0.5), "axis": Vector3(0, 1, 0.35), "arc": 80.0},
	"ventral": {"pos": Vector3(0.0, -1.0, 0.55), "axis": Vector3(0, -1, 0.3), "arc": 78.0},
	"tail": {"pos": Vector3(0.0, 0.1, 0.99), "axis": Vector3(0, 0.05, 1), "arc": 58.0},
	"waist_l": {"pos": Vector3(-0.95, -0.05, 0.65), "axis": Vector3(-1, 0, 0), "arc": 62.0},
	"waist_r": {"pos": Vector3(0.95, -0.05, 0.65), "axis": Vector3(1, 0, 0), "arc": 62.0},
}

## Real defensive fits. Nose / dorsal / ventral / tail / waist as the type actually carried them.
const LAYOUTS := {
	"lancaster": ["nose", "dorsal", "tail"],                       # FN5 nose, FN50 dorsal, FN20 four-gun tail
	"he111": ["nose", "dorsal", "ventral"],                        # A/B/C-Stand
	"ju88": ["dorsal", "ventral", "nose"],                         # B and C-Stand, later a nose gun
	"do17": ["nose", "dorsal", "ventral"],                         # A/B/C-Stand (eight forward MGs)
	"b25": ["nose", "dorsal", "tail", "waist_l", "waist_r"],       # two in the nose, Bendix, tail, two waist
	"b26": ["nose", "dorsal", "tail", "waist_l", "waist_r"],
	"blenheim": ["dorsal", "ventral"],                             # twin dorsal turret + ventral gun
	"a20": ["dorsal", "ventral"],
	"fw200": ["nose", "dorsal", "ventral", "waist_l", "waist_r"],
	"ju87": ["tail"],                                              # single rear-firing gun
}

## Aircraft-local position of a turret mount (metres), taken from the model's fuselage box so the turret
## sits on the airframe. Falls back to a radius-scaled generic box for models without a spec.
static func mount_local(model_id: String, key: String, fallback_radius: float = 10.0) -> Vector3:
	var u: Vector3 = MOUNTS[key]["pos"]
	var spec: Dictionary = ModelSpecs.get_spec(model_id)
	if spec.is_empty() or not spec.has("fus"):
		return Vector3(u.x * fallback_radius * 0.12, u.y * fallback_radius * 0.09, lerpf(-fallback_radius * 0.5, fallback_radius * 0.5, u.z))
	var fus: Dictionary = spec["fus"]
	var sc: float = float(spec.get("scale", 1.1))
	return Vector3(u.x * float(fus["hw"]), float(fus.get("cy", 0.0)) + u.y * float(fus["hh"]), lerpf(float(fus["z0"]), float(fus["z1"]), u.z)) * sc


var aircraft: Aircraft
var hud: Node
var damage: float = 2.0
var skill: float = 0.4
var engaged: bool = false         # true while any turret has a target (read by HUDs)
var _turrets: Array = []          # {name, pivot, axis, arc_cos, burst_t}
var _t: float = 0.0
var _msg_cd: float = 0.0
var _snd_cd: float = 0.0
var _flip: bool = false

# --- gunner view: the player mans one turret at a time (the aircraft flies on autopilot) ---
var rig: CameraRig
var view_index: int = -1          # -1 = flying, otherwise the index of the manned turret
var _cam: Camera3D
var _ui: CanvasLayer
var _ui_c: Control
var _hud_was: bool = true
var _aim: Vector2 = Vector2.ZERO  # manual aim offset (yaw, pitch) off the turret axis, radians
var _any_in_arc: bool = false     # an enemy is close to where the manned gun is pointing
var _cam_clear: float = 2.2       # how far the gunner camera sits outside the mount


# ------------------------------------------------------------------ gunner view

func turret_count() -> int:
	return _turrets.size()


func turret_name(i: int) -> String:
	return String(_turrets[i]["name"]) if i >= 0 and i < _turrets.size() else ""


## Step to the next turret; after the last one, back to flying. Bound to the gunner-view key.
func cycle_view() -> void:
	if _turrets.is_empty():
		return
	if view_index + 1 >= _turrets.size():
		leave_view()
		return
	view_index += 1
	_enter_view()


func leave_view() -> void:
	view_index = -1
	_aim = Vector2.ZERO
	_any_in_arc = false
	if _cam != null and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	if _ui != null and is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null
	_ui_c = null
	if aircraft != null and is_instance_valid(aircraft):
		aircraft.sight_hold = false             # release the autopilot
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = _hud_was
	if rig != null and is_instance_valid(rig) and rig.current_camera() != null:
		rig.current_camera().make_current()


func _enter_view() -> void:
	if view_index < 0 or view_index >= _turrets.size() or aircraft == null:
		return
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.near = 0.2
		_cam.far = 48000.0
		_cam.fov = 55.0
		add_child(_cam)          # in the AIRFRAME frame, not the turret: a turret swings to track and would
	elif _cam.get_parent() != self:   # carry the camera into the fuselage
		_cam.reparent(self, false)
	_cam_clear = maxf(2.2, aircraft.stats.radius * 0.22)
	_update_view_cam()
	_cam.current = true
	# the aircraft flies itself while the player mans the gun (the airframe stays visible: the wings give
	# useful context and the camera sits outside the guns, so the view of the world is clear)
	aircraft.sight_hold = true
	aircraft.sight_alt_y = aircraft.global_position.y
	if hud is CanvasLayer:
		_hud_was = (hud as CanvasLayer).visible
		(hud as CanvasLayer).visible = false
	if _ui == null or not is_instance_valid(_ui):
		_ui = CanvasLayer.new()
		_ui.layer = 3
		_ui_c = Control.new()
		_ui_c.set_anchors_preset(Control.PRESET_FULL_RECT)
		_ui_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui_c.draw.connect(_draw_sight)
		_ui.add_child(_ui_c)
		add_child(_ui)
	elif _ui_c != null and is_instance_valid(_ui_c):
		_ui_c.queue_redraw()
	if hud != null and hud.has_method("show_message"):
		hud.call("show_message", "%s gun - press the gunner key to change position" % turret_name(view_index).replace("_", " ").capitalize(), 2.5)


## Place the gunner camera: fixed just outside the mount (along the mount's own direction, so it never ends
## up inside the fuselage however the turret swings) but looking along the current aim.
func _update_view_cam() -> void:
	if _cam == null or not is_instance_valid(_cam) or view_index < 0 or view_index >= _turrets.size():
		return
	var t: Dictionary = _turrets[view_index]
	var pivot: Node3D = t["pivot"]
	var rest_world: Vector3 = (aircraft.global_transform.basis * (t["axis"] as Vector3)).normalized()
	_cam.global_position = pivot.global_position + rest_world * _cam_clear
	var aim_world: Vector3 = -pivot.global_transform.basis.z
	var up: Vector3 = Vector3.UP
	if absf(aim_world.dot(up)) > 0.98:
		up = aircraft.global_transform.basis.y
	_cam.look_at(_cam.global_position + aim_world, up)


## Aim the manned gun with the mouse, or the right stick on a pad. Offsets are clamped to the turret arc.
func _unhandled_input(event: InputEvent) -> void:
	if view_index < 0 or aircraft == null or not is_instance_valid(aircraft):
		return
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		_aim.x -= mm.relative.x * 0.0018
		_aim.y -= mm.relative.y * 0.0018
		_clamp_aim()
		get_viewport().set_input_as_handled()


func _clamp_aim() -> void:
	if view_index < 0 or view_index >= _turrets.size():
		return
	var arc: float = deg_to_rad(float(MOUNTS[String(_turrets[view_index]["name"])]["arc"]))
	var lim: float = maxf(arc * 0.92, 0.05)
	if _aim.length() > lim:
		_aim = _aim.normalized() * lim


## Local-space aim direction of the manned turret (axis turned by the player's aim offsets).
func _view_aim_local(t: Dictionary) -> Vector3:
	var axis: Vector3 = t["axis"]
	var up: Vector3 = Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var b: Basis = Basis.looking_at(axis, up)
	var d: Vector3 = (b * Vector3(0, 0, -1)).rotated(b.y, _aim.x).rotated(b.x, _aim.y)
	return d.normalized()


func _draw_sight() -> void:
	if _ui_c == null or view_index < 0 or view_index >= _turrets.size():
		return
	var c: Vector2 = _ui_c.size * 0.5
	var col: Color = Color(1.0, 0.82, 0.28, 0.95) if _any_in_arc else Color(0.85, 0.98, 0.85, 0.85)
	_ui_c.draw_arc(c, 26.0, 0.0, TAU, 40, col, 1.6)
	_ui_c.draw_line(c + Vector2(-44, 0), c + Vector2(-9, 0), col, 1.6)
	_ui_c.draw_line(c + Vector2(9, 0), c + Vector2(44, 0), col, 1.6)
	_ui_c.draw_line(c + Vector2(0, -44), c + Vector2(0, -9), col, 1.6)
	_ui_c.draw_line(c + Vector2(0, 9), c + Vector2(0, 44), col, 1.6)
	_ui_c.draw_circle(c, 2.0, col)
	var lbl: String = "%s GUN  %d/%d" % [turret_name(view_index).replace("_", " ").to_upper(), view_index + 1, _turrets.size()]
	_ui_c.draw_string(ThemeDB.fallback_font, c + Vector2(-40, 74), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)


## Turret fit for a model: the named layout, or the generic dorsal + tail pair for any other armed bomber.
static func layout_for(model_id: String, bombs: int) -> Array:
	var layout: Array = LAYOUTS.get(model_id, [])
	if not layout.is_empty():
		return layout
	if bombs < 8 or model_id in ["mosquito", "ju52", "c47"]:
		return []
	return ["dorsal", "tail"]


static func attach(a: Aircraft, p_hud: Node = null, p_skill: float = 0.6) -> DefensiveTurrets:
	var layout: Array = layout_for(a.stats.id, a.stats.bombs)
	if layout.is_empty():
		return null
	var d := DefensiveTurrets.new()
	d.name = "DefensiveTurrets"
	d.aircraft = a
	d.hud = p_hud
	d.skill = p_skill
	a.add_child(d)
	d._build(layout)
	return d


func _build(layout: Array) -> void:
	var r: float = aircraft.stats.radius
	var dome_r: float = clampf(r * 0.04, 0.35, 0.72)
	var skin: ShaderMaterial = ToonUtil.make_toon(Color(0.2, 0.22, 0.2))
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.45, 0.6, 0.65, 0.5)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	var steel: ShaderMaterial = ToonUtil.make_toon(Color(0.08, 0.08, 0.09))
	for key in layout:
		var m: Dictionary = MOUNTS[key]
		var axis: Vector3 = (m["axis"] as Vector3).normalized()
		var pivot := Node3D.new()
		pivot.name = "Turret_" + String(key)
		pivot.position = mount_local(aircraft.stats.id, key, r)
		add_child(pivot)
		var dome := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = dome_r
		sm.height = dome_r * 2.0
		sm.radial_segments = 20
		sm.rings = 10
		dome.mesh = sm
		dome.material_override = glass if key in ["nose", "tail"] else skin
		dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(dome)
		for sx in [-1.0, 1.0]:
			var b := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.025
			cm.bottom_radius = 0.035
			cm.height = dome_r * 1.5
			cm.radial_segments = 5
			b.mesh = cm
			b.material_override = steel
			b.rotation_degrees = Vector3(90, 0, 0)
			b.position = Vector3(sx * dome_r * 0.28, 0.0, -dome_r * 0.95)
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pivot.add_child(b)
		_rest_pose(pivot, axis)
		_turrets.append({"name": String(key), "pivot": pivot, "axis": axis, "arc_cos": cos(deg_to_rad(float(m["arc"]))), "burst": 0.0})


func _rest_pose(pivot: Node3D, axis: Vector3) -> void:
	var up: Vector3 = Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	pivot.basis = Basis.looking_at(axis, up)


func _process(delta: float) -> void:
	if aircraft == null or not is_instance_valid(aircraft) or aircraft.state != Aircraft.State.ALIVE:
		if view_index >= 0:
			leave_view()
		return
	_msg_cd -= delta
	_snd_cd -= delta
	_t -= delta
	if view_index >= 0:
		_update_view_cam()
		# right stick aims the manned gun (the mouse is handled in _unhandled_input)
		_aim.x -= Input.get_axis("look_left", "look_right") * 0.9 * delta
		_aim.y -= Input.get_axis("look_up", "look_down") * 0.9 * delta
		_clamp_aim()
		if _ui_c != null and is_instance_valid(_ui_c):
			_ui_c.queue_redraw()
	# visual tracking every frame (cheap): ease each barrel to its aim or back to rest
	for t in _turrets:
		var pivot: Node3D = t["pivot"]
		var want: Basis = t.get("want_basis", Basis.IDENTITY) if t.get("has_aim", false) else Basis.looking_at(t["axis"], Vector3.UP if absf((t["axis"] as Vector3).y) < 0.9 else Vector3.RIGHT)
		var q: Quaternion = Quaternion(pivot.basis.orthonormalized()).slerp(Quaternion(want.orthonormalized()), clampf(delta * 9.0, 0.0, 1.0))
		pivot.basis = Basis(q)
	if _t > 0.0:
		return
	_t = TICK
	_think()


## Share of this turret's fire the gunner can still deliver, from the crew intercom (1.0 when there is no crew model).
func _crew_factor(mount: String) -> float:
	var ci: Node = aircraft.get_node_or_null("CrewIntercom")
	if ci == null or not ci.has_method("gun_factor"):
		return 1.0
	return float(ci.call("gun_factor", mount))


func _range_factor() -> float:
	var f: float = 1.0
	var wm: Node = get_node_or_null("/root/WeatherManager")
	if wm and wm.has_method("get_visibility_multiplier"):
		f *= clampf(sqrt(float(wm.call("get_visibility_multiplier"))), 0.45, 1.0)
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	if tod:
		f *= lerpf(0.6, 1.0, smoothstep(0.05, 0.5, float(tod.get("light_level"))))
	return f


func _think() -> void:
	var enemies: Array[Aircraft] = []
	for n in get_tree().get_nodes_in_group("aircraft"):
		var e: Aircraft = n as Aircraft
		if e != null and e != aircraft and e.team != aircraft.team and e.team != "Neutral" and e.state == Aircraft.State.ALIVE:
			enemies.append(e)
	var rng: float = BASE_RANGE * _range_factor()
	var any: bool = false
	var xf: Transform3D = aircraft.global_transform
	var inv: Transform3D = xf.affine_inverse()
	for ti in _turrets.size():
		var t: Dictionary = _turrets[ti]
		t["has_aim"] = false
		var pivot: Node3D = t["pivot"]
		if ti == view_index:
			# the player is manning this one: aim it by hand, fire on the trigger
			var dl: Vector3 = _view_aim_local(t)
			t["want_basis"] = Basis.looking_at(dl, Vector3.UP if absf(dl.y) < 0.9 else Vector3.RIGHT)
			t["has_aim"] = true
			any = true
			var wdir: Vector3 = (-pivot.global_transform.basis.z).normalized()
			_any_in_arc = false
			for e in enemies:
				var ev: Vector3 = e.global_position - pivot.global_position
				if ev.length() < rng and wdir.dot(ev.normalized()) > 0.995:
					_any_in_arc = true
					break
			if Input.is_action_pressed("fire"):
				var o: Vector3 = pivot.global_position + wdir * 1.5
				for k in 2:
					AIGun.fire(self, aircraft, o, AIGun.spread_dir(wdir, 0.012), aircraft.velocity, aircraft.team, damage, k == 0)
				if _snd_cd <= 0.0:
					_snd_cd = 0.12
					FX.sfx("mg_defensive", aircraft.global_position, -7.0, 0.1)
			continue
		var crew_f: float = _crew_factor(String(t["name"]))     # a dead gunner's turret is silent, a wounded one fires half the time
		if crew_f <= 0.0:
			continue
		var best: Aircraft = null
		var bd: float = rng
		for e in enemies:
			var d: float = e.global_position.distance_to(pivot.global_position)
			if d >= bd:
				continue
			var local_dir: Vector3 = (inv * e.global_position - pivot.position).normalized()
			if local_dir.dot(t["axis"]) < float(t["arc_cos"]):
				continue
			bd = d
			best = e
		if best == null:
			continue
		any = true
		if crew_f < 1.0 and randf() > crew_f:
			continue
		var tt: float = bd / AIGun.BULLET_SPEED
		var aim: Vector3 = best.global_position + (best.velocity - aircraft.velocity) * tt
		var dir: Vector3 = (aim - pivot.global_position).normalized()
		# the pivot is a child of the aircraft: aim basis is expressed in aircraft-local space
		var ldir: Vector3 = (xf.basis.inverse() * dir).normalized()
		t["want_basis"] = Basis.looking_at(ldir, Vector3.UP if absf(ldir.y) < 0.9 else Vector3.RIGHT)
		t["has_aim"] = true
		var spread: float = (1.0 - skill) * 0.10 + 0.035 + bd / rng * 0.030
		# the burst is thrown at the target rather than aimed dead on: mostly misses, with the odd hit
		var jitter: Vector3 = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * spread * 1.5
		var fire_dir: Vector3 = (aim + jitter - pivot.global_position).normalized()
		_flip = not _flip
		var origin: Vector3 = pivot.global_position + fire_dir * 1.5
		for k in 2:
			AIGun.fire(self, aircraft, origin, AIGun.spread_dir(fire_dir, spread), aircraft.velocity, aircraft.team, damage, _flip or k == 0)
	engaged = any
	if any:
		if _snd_cd <= 0.0:
			_snd_cd = 0.18
			FX.sfx("mg_defensive", aircraft.global_position, -7.0, 0.1)
		if _msg_cd <= 0.0 and aircraft.player_controlled and hud != null and hud.has_method("show_message"):
			_msg_cd = MSG_COOLDOWN
			hud.call("show_message", "Gunners engaging", 2.0)
