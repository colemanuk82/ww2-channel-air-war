class_name TowRig
extends Node3D
## An assault glider on a tow rope behind a tug, and what happens when the rope is cast off.
##   towed   the glider rides high behind the tug on a sagging rope that is drawn between the tug's tail and its nose
##   free    cast off: the rope drops away, the glider glides to its landing zone (turning on to it, circling to lose
##           height if it arrives high) and lands
##   landed  rolled to a stop; `landed_pos` is where
##   lost    could not reach the ground at the zone (the tug went down while towing)
## Heights are in world units (VERTICAL_SCALE 2 over real metres): a Horsa's 12:1 glide is a 6.7 u/s sink at 40 m/s.

const HORIZ_SPEED: float = 40.0
const SINK: float = 6.7                 # world units / second (3.3 m/s real)
const TURN_RATE: float = 22.0           # degrees per second
const ROPE_LEN: float = 36.0
const TUG_HOOK: Vector3 = Vector3(0.0, -0.4, 11.0)      # tail of a C-47, tug-local
const GLIDER_UP: float = 2.6            # towed a little above the tug's slipstream
const NOSE: float = 11.4                # glider nose forward of its origin

var tug: Node3D
var glider_type: String = "horsa"
var state: String = "towed"
var target: Vector3 = Vector3.ZERO
var landed_pos: Vector3 = Vector3.ZERO
var glider: MeshInstance3D
var _rope: Array = []                   # two cylinder segments
var _drop_rope: Node3D
var _drop_t: float = 0.0
var _drop_v: Vector3 = Vector3.ZERO
var _speed: float = HORIZ_SPEED
var _yaw: float = 0.0
var _bank: float = 0.0
var _t: float = 0.0


static func make(p_tug: Node3D, type: String, p_target: Vector3) -> TowRig:
	var r := TowRig.new()
	r.tug = p_tug
	r.glider_type = type
	r.target = p_target
	return r


func _ready() -> void:
	glider = MeshInstance3D.new()
	glider.mesh = GliderKit.glider_mesh(glider_type, "intact")
	add_child(glider)
	for i in 2:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.07
		cm.bottom_radius = 0.07
		cm.height = 1.0
		cm.radial_segments = 5
		mi.mesh = cm
		mi.material_override = _rope_mat()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_rope.append(mi)
	if tug != null:
		var tb: Basis = tug.global_transform.basis
		glider.global_position = tug.global_transform * Vector3(0.0, GLIDER_UP, TUG_HOOK.z + ROPE_LEN + NOSE)
		glider.global_basis = tb
		_yaw = _yaw_of(tb)


static func _rope_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.50, 0.32)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _yaw_of(b: Basis) -> float:
	var f: Vector3 = -b.z
	return atan2(-f.x, -f.z)


## Draw a taut-ish rope of two segments from a to b (a little sag in the middle).
func _draw_rope(rope: Array, a: Vector3, b: Vector3, sag: float) -> void:
	var m: Vector3 = (a + b) * 0.5 + Vector3(0.0, -sag, 0.0)
	_seg(rope[0], a, m)
	_seg(rope[1], m, b)


static func _seg(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d: Vector3 = b - a
	var l: float = maxf(d.length(), 0.01)
	var y: Vector3 = d / l
	var x: Vector3 = y.cross(Vector3.RIGHT)
	if x.length() < 0.05:
		x = y.cross(Vector3.FORWARD)
	x = x.normalized()
	var z: Vector3 = x.cross(y)
	mi.global_transform = Transform3D(Basis(x, y * l, z), (a + b) * 0.5)


## Cast off. The rope falls away behind the tug; the glider glides.
func release() -> void:
	if state != "towed":
		return
	state = "free"
	_speed = HORIZ_SPEED
	_yaw = _yaw_of(glider.global_basis)
	# the rope: the same two segments, now falling free
	_drop_rope = Node3D.new()
	get_parent().add_child(_drop_rope)
	var tail: Vector3 = tug.global_transform * TUG_HOOK
	var nose: Vector3 = glider.global_transform * Vector3(0.0, 0.0, -NOSE)
	_drop_rope.set_meta("a", tail)
	_drop_rope.set_meta("b", nose)
	_drop_v = Vector3.ZERO
	_drop_t = 0.0


func _physics_process(delta: float) -> void:
	_t += delta
	match state:
		"towed":
			_tick_towed(delta)
		"free":
			_tick_free(delta)
	_tick_rope_fall(delta)


func _tick_towed(delta: float) -> void:
	if tug == null or not is_instance_valid(tug):
		state = "lost"
		return
	var want_p: Vector3 = tug.global_transform * Vector3(0.0, GLIDER_UP, TUG_HOOK.z + ROPE_LEN + NOSE)
	var k: float = 1.0 - exp(-5.0 * delta)
	glider.global_position = glider.global_position.lerp(want_p, k)
	var gb: Basis = glider.global_basis.orthonormalized().slerp(tug.global_transform.basis.orthonormalized(), 1.0 - exp(-3.0 * delta))
	glider.global_basis = gb
	var a: Vector3 = tug.global_transform * TUG_HOOK
	var b: Vector3 = glider.global_transform * Vector3(0.0, 0.1, -NOSE)
	_draw_rope(_rope, a, b, 1.2 + 0.4 * sin(_t * 1.7))


func _tick_free(delta: float) -> void:
	var p: Vector3 = glider.global_position
	var to: Vector3 = target - p
	to.y = 0.0
	var dist: float = to.length()
	var agl: float = p.y - GroundKit.ground_y(p.x, p.z)
	# heading: turn on to the zone, or circle round it when still high above it
	var want: float = atan2(-to.x, -to.z)
	var turn: float = 0.0
	if dist < 260.0 and agl > 70.0:
		turn = deg_to_rad(TURN_RATE) * delta        # circle to lose height
	else:
		var diff: float = wrapf(want - _yaw, -PI, PI)
		turn = clampf(diff, -deg_to_rad(TURN_RATE) * delta, deg_to_rad(TURN_RATE) * delta)
	_yaw += turn
	_bank = lerpf(_bank, clampf(turn / maxf(delta, 0.001) * 0.9, -0.5, 0.5), 1.0 - exp(-3.0 * delta))
	var flare: bool = agl < 24.0
	var sink: float = SINK * (0.35 if flare else 1.0)
	_speed = lerpf(_speed, HORIZ_SPEED * (0.8 if flare else 1.0), 1.0 - exp(-1.0 * delta))
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	p += fwd * _speed * delta
	p.y -= sink * delta
	var gy: float = GroundKit.ground_y(p.x, p.z)
	var pitch: float = -atan2(sink, _speed) * (0.4 if not flare else -1.0)
	var b := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.FORWARD, -_bank)
	glider.global_basis = b
	if p.y <= gy + 0.1:
		p.y = gy
		state = "slide"
		landed_pos = p
	glider.global_position = p


func _tick_rope_fall(delta: float) -> void:
	if state == "slide":
		# roll out along the ground, slowing
		_speed = maxf(_speed - 14.0 * delta, 0.0)
		var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		var p: Vector3 = glider.global_position + fwd * _speed * delta
		p.y = GroundKit.ground_y(p.x, p.z)
		glider.global_position = p
		glider.global_basis = Basis(Vector3.UP, _yaw)
		if _speed <= 0.05:
			state = "landed"
			landed_pos = p
	if _drop_rope == null:
		return
	_drop_t += delta
	_drop_v.y -= 24.0 * delta
	var a: Vector3 = _drop_rope.get_meta("a") + _drop_v * delta
	var b: Vector3 = _drop_rope.get_meta("b") + _drop_v * delta * 0.8
	a.y += 0.0
	_drop_rope.set_meta("a", a)
	_drop_rope.set_meta("b", b + Vector3(0.0, 0.0, 0.0))
	if _drop_rope.get_child_count() == 0:
		for i in 2:
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.07
			cm.bottom_radius = 0.07
			cm.height = 1.0
			cm.radial_segments = 5
			mi.mesh = cm
			mi.material_override = _rope_mat()
			_drop_rope.add_child(mi)
		# the live rope segments are hidden: the dropping copy takes over
		for r in _rope:
			(r as MeshInstance3D).visible = false
	var kids: Array = _drop_rope.get_children()
	_draw_rope(kids, a, b, 3.0 + _drop_t)
	if _drop_t > 7.0:
		_drop_rope.queue_free()
		_drop_rope = null


func is_down() -> bool:
	return state == "landed" or state == "slide" or state == "lost"


func is_stopped() -> bool:
	return state == "landed" or state == "lost"
