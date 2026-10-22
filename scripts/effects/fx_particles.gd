class_name FXParticles
extends MultiMeshInstance3D
## Pooled CPU particle system rendered as ONE MultiMesh (toon puffs or debris chunks).
## Fixed capacity ring: when full the oldest-slot is overwritten. No per-spawn allocation.

const STRIDE := 20   # 12 transform + 4 colour + 4 custom

var cap: int = 768
var count: int = 0
var _rr: int = 0
var _buf: PackedFloat32Array = PackedFloat32Array()
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _axis := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _s0 := PackedFloat32Array()
var _s1 := PackedFloat32Array()
var _grav := PackedFloat32Array()
var _drag := PackedFloat32Array()
var _shade := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _ang := PackedFloat32Array()
var _c0 := PackedColorArray()
var _c1 := PackedColorArray()


func setup(mesh: Mesh, capacity: int) -> void:
	cap = capacity
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 0          # grown / shrunk with the live count (see _fit), so a quiet sky uploads nothing
	mm.visible_instance_count = 0
	multimesh = mm
	# covers the whole map: the world runs to ~600 km east of the origin (the Ruhr dams sit at x ~ 573 000), and the
	# old +-100 km box culled every puff out there - no smoke, fire, flak or spray over Germany at all
	custom_aabb = AABB(Vector3(-2.0e6, -2.0e4, -2.0e6), Vector3(4.0e6, 4.0e4, 4.0e6))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pos.resize(cap)
	_vel.resize(cap)
	_axis.resize(cap)
	_age.resize(cap)
	_life.resize(cap)
	_s0.resize(cap)
	_s1.resize(cap)
	_grav.resize(cap)
	_drag.resize(cap)
	_shade.resize(cap)
	_spin.resize(cap)
	_ang.resize(cap)
	_c0.resize(cap)
	_c1.resize(cap)


func spawn(pos: Vector3, vel: Vector3, life: float, size0: float, size1: float, col0: Color, col1: Color, shade: float = 1.0, gravity: float = 0.0, drag: float = 0.0, spin: float = 0.0) -> void:
	var i: int
	if count < cap:
		i = count
		count += 1
	else:
		i = _rr
		_rr = (_rr + 1) % cap
	_pos[i] = pos
	_vel[i] = vel
	_age[i] = 0.0
	_life[i] = maxf(life, 0.05)
	_s0[i] = size0
	_s1[i] = size1
	_c0[i] = col0
	_c1[i] = col1
	_shade[i] = shade
	_grav[i] = gravity
	_drag[i] = drag
	_spin[i] = spin
	_ang[i] = randf() * TAU
	if spin != 0.0:
		_axis[i] = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized()


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	var i: int = 0
	while i < count:
		var a: float = _age[i] + delta
		if a >= _life[i]:
			_remove(i)
			continue
		_age[i] = a
		var v: Vector3 = _vel[i]
		v.y -= _grav[i] * delta
		var d: float = _drag[i]
		if d > 0.0:
			v *= maxf(1.0 - d * delta, 0.0)
		_vel[i] = v
		_pos[i] += v * delta
		_ang[i] += _spin[i] * delta
		i += 1
	var n: int = count
	if not _fit(n):
		return
	for j in n:
		var t: float = _age[j] / _life[j]
		var te: float = 1.0 - (1.0 - t) * (1.0 - t)
		var s: float = lerpf(_s0[j], _s1[j], te)
		var p: Vector3 = _pos[j]
		var o: int = j * STRIDE
		if _spin[j] == 0.0:
			_buf[o] = s
			_buf[o + 1] = 0.0
			_buf[o + 2] = 0.0
			_buf[o + 4] = 0.0
			_buf[o + 5] = s
			_buf[o + 6] = 0.0
			_buf[o + 8] = 0.0
			_buf[o + 9] = 0.0
			_buf[o + 10] = s
		else:
			var b := Basis(_axis[j], _ang[j])
			_buf[o] = b.x.x * s
			_buf[o + 1] = b.y.x * s
			_buf[o + 2] = b.z.x * s
			_buf[o + 4] = b.x.y * s
			_buf[o + 5] = b.y.y * s
			_buf[o + 6] = b.z.y * s
			_buf[o + 8] = b.x.z * s
			_buf[o + 9] = b.y.z * s
			_buf[o + 10] = b.z.z * s
		_buf[o + 3] = p.x
		_buf[o + 7] = p.y
		_buf[o + 11] = p.z
		var c: Color = _c0[j].lerp(_c1[j], t)
		_buf[o + 12] = c.r
		_buf[o + 13] = c.g
		_buf[o + 14] = c.b
		_buf[o + 15] = c.a
		_buf[o + 16] = _shade[j]
	multimesh.buffer = _buf
	multimesh.visible_instance_count = n


var _mm_n: int = 0


## Size the MultiMesh (and its upload buffer) to the live particles in power-of-two steps: uploading the whole
## 7000-9000 slot buffer every frame cost ~1 ms even with a handful of puffs alive. False = nothing to draw.
func _fit(n: int) -> bool:
	var want: int = 0
	if n > 0:
		want = 256
		while want < n:
			want *= 2
		want = mini(want, cap)
	if want > _mm_n or (want < _mm_n / 4) or (want == 0 and _mm_n != 0):
		_mm_n = want
		multimesh.instance_count = want
		_buf.resize(want * STRIDE)
		_buf.fill(0.0)
	if _mm_n == 0:
		multimesh.visible_instance_count = 0
		return false
	return true


func _remove(i: int) -> void:
	var last: int = count - 1
	if i != last:
		_pos[i] = _pos[last]
		_vel[i] = _vel[last]
		_axis[i] = _axis[last]
		_age[i] = _age[last]
		_life[i] = _life[last]
		_s0[i] = _s0[last]
		_s1[i] = _s1[last]
		_grav[i] = _grav[last]
		_drag[i] = _drag[last]
		_shade[i] = _shade[last]
		_spin[i] = _spin[last]
		_ang[i] = _ang[last]
		_c0[i] = _c0[last]
		_c1[i] = _c1[last]
	count = last
	if _rr >= count:
		_rr = 0
