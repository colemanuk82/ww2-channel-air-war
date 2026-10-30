class_name ContrailRibbon
extends MeshInstance3D
## A soft, widening vapour plume: up to two world-space ribbons (one per engine) batched into a single
## mesh and a single worker task. Vertex generation runs on the WorkerThreadPool; only the finished mesh
## upload happens on the main thread.

var life: float = 120.0     # seconds a point stays in the trail: long, high-altitude streaks
const STEP := 7.0           # metres of flight between samples
const NEAR_HALF_W := 0.8    # half-width at the aircraft: starts as a thin wisp
const FAR_HALF_W := 11.0    # half-width once the vapour has spread
const MIN_PX_W := 0.0019    # half-width per metre of camera distance: keeps a far trail ~4 px wide
const REBUILD_S := 0.066
const IDLE_REBUILD_S := 0.25   # no fresh points (out of range): fade the existing trail at a quarter of the cost
const MAX_POINTS := 4500       # hard bound per stream (a warp or a very fast aircraft can never grow it forever)
const SOFT_POINTS := 3900
const MAX_HALF_W := 48.0       # farthest the distance-widening may take the ribbon half-width

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec3 contrail_tint = vec3(1.0);

varying vec2 v_uv2;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_uv2 = UV2;
}

void fragment() {
	float u = clamp(UV.x, 0.0, 1.0);
	float age = clamp(v_uv2.x, 0.0, 1.0);
	float str = clamp(v_uv2.y, 0.0, 1.0);

	// Soft, rounded cross-section instead of a hard-edged rectangle.
	float profile = exp(-pow((u - 0.5) * 3.6, 2.0));

	// Gentle, static density variation: a smooth plume, not a string of puffs.
	vec2 q = vec2(u * 2.4, UV.y * 0.7);
	float n1 = noise(q);
	float n2 = noise(q * 2.2 + 1.7);
	float wisp = n1 * 0.70 + n2 * 0.30;
	float density = mix(0.94, 1.03, wisp);

	// Weak right at the aircraft, thickening behind it, then dissipating far back.
	float fresh = smoothstep(0.0, 0.020, age);
	float old = 1.0 - smoothstep(0.62, 1.0, age);
	float fade = fresh * old;
	float core = exp(-pow((u - 0.5) * 7.0, 2.0));

	float alpha = (profile * 0.55 + core * 0.08) * fade * density * str * 0.5;
	ALBEDO = mix(vec3(0.66, 0.72, 0.82), vec3(1.0), profile * 0.8 + 0.2) * contrail_tint;
	ALPHA = clamp(alpha, 0.0, 0.34);
}
"""


## Worker-thread job. It owns copies of both streams, so the main thread can keep appending and
## ageing points while the geometry is generated.
class BuildJob extends RefCounted:
	var pts: PackedVector3Array
	var ages: PackedFloat32Array
	var strs: PackedFloat32Array
	var pts2: PackedVector3Array
	var ages2: PackedFloat32Array
	var strs2: PackedFloat32Array
	var eye: Vector3
	var life: float
	var near_w: float
	var far_w: float
	var min_px: float
	var max_half: float
	var result: Dictionary = {}

	func _lane(p: PackedVector3Array, a: PackedFloat32Array, s: PackedFloat32Array) -> Dictionary:
		var n: int = p.size()
		if n < 2:
			return {"ok": false}
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var uv2s := PackedVector2Array()
		var idx := PackedInt32Array()
		verts.resize(n * 2)
		uvs.resize(n * 2)
		uv2s.resize(n * 2)
		for i in n:
			var pos: Vector3 = p[i]
			if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
				return {"ok": false}
			var age_norm: float = clampf(a[i] / life, 0.0, 1.0)
			var dir: Vector3 = p[mini(i + 1, n - 1)] - p[maxi(i - 1, 0)]
			if dir.length_squared() < 0.000001:
				dir = Vector3.FORWARD
			var dn: Vector3 = dir.normalized()
			var right: Vector3 = dn.cross(Vector3.UP)
			if right.length_squared() < 0.000001:
				right = Vector3.RIGHT
			right = right.normalized()
			var spread: float = smoothstep(0.0, 0.55, age_norm)
			pos += right * (sin(float(i) * 0.09 + a[i] * 0.30) * (0.2 + 1.8 * age_norm))
			pos += Vector3.UP * (cos(float(i) * 0.07 + a[i] * 0.22) * (0.1 + 0.8 * age_norm))
			var side: Vector3 = dir.cross(eye - pos)
			if side.length_squared() < 0.000001:
				side = Vector3.UP
			side = side.normalized()
			var half_w: float = lerpf(near_w, far_w, spread)
			var edge_var: float = 0.94 + 0.10 * sin(float(i) * 0.06 + age_norm * 1.2)
			var lw: float = half_w * edge_var
			var rw: float = half_w * (1.88 - edge_var)
			var min_w: float = eye.distance_to(pos) * min_px
			lw = minf(maxf(lw, min_w), max_half)
			rw = minf(maxf(rw, min_w), max_half)
			var v: float = float(i) * 0.33
			verts[i * 2] = pos - side * lw
			verts[i * 2 + 1] = pos + side * rw
			uvs[i * 2] = Vector2(0.0, v)
			uvs[i * 2 + 1] = Vector2(1.0, v)
			uv2s[i * 2] = Vector2(age_norm, s[i])
			uv2s[i * 2 + 1] = Vector2(age_norm, s[i])
		for i in n - 1:
			var a0: int = i * 2
			var b0: int = (i + 1) * 2
			idx.append_array([a0, b0, a0 + 1, a0 + 1, b0, b0 + 1])
		return {"ok": true, "verts": verts, "uvs": uvs, "uv2s": uv2s, "idx": idx}

	func run() -> void:
		var lanes: Array = [_lane(pts, ages, strs)]
		if pts2.size() >= 2:
			lanes.append(_lane(pts2, ages2, strs2))
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var uv2s := PackedVector2Array()
		var idx := PackedInt32Array()
		var any: bool = false
		for d in lanes:
			if not bool(d.get("ok", false)):
				continue
			any = true
			var base: int = verts.size()
			var lv: PackedVector3Array = d["verts"]
			var lu: PackedVector2Array = d["uvs"]
			var l2: PackedVector2Array = d["uv2s"]
			var li: PackedInt32Array = d["idx"]
			verts.append_array(lv)
			uvs.append_array(lu)
			uv2s.append_array(l2)
			for k in li:
				idx.append(int(k) + base)
		if not any:
			result = {"valid": false}
			return
		result = {"valid": true, "verts": verts, "uvs": uvs, "uv2s": uv2s, "idx": idx}


var _pts: PackedVector3Array = PackedVector3Array()
var _age: PackedFloat32Array = PackedFloat32Array()
var _str: PackedFloat32Array = PackedFloat32Array()
var _pts2: PackedVector3Array = PackedVector3Array()
var _age2: PackedFloat32Array = PackedFloat32Array()
var _str2: PackedFloat32Array = PackedFloat32Array()
var _rb: float = 0.0
var _dirty: bool = false
var _mesh: ArrayMesh = ArrayMesh.new()
var _mat: ShaderMaterial
var _task_id: int = -1
var _job: BuildJob = null
var _tint_t: float = 0.0


func _ready() -> void:
	top_level = true            # points are in world space
	mesh = _mesh
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat.set_shader_parameter("contrail_tint", _cloud_tint())


## The same lit colour the cloud layer uses, so high contrails sit in the sky instead of glowing white.
static func _cloud_tint() -> Color:
	var cc := Color(0.85, 0.87, 0.9)
	var cf: CloudField = WeatherManager.cloud_field
	if cf != null and cf.mat != null:
		var cv: Variant = cf.mat.get_shader_parameter("cloud_color")
		if cv is Color:
			cc = cv
	var lk: float = clampf(0.15 + TimeOfDay.light_level * 0.9, 0.1, 1.0)
	return Color(cc.r * lk, cc.g * lk, cc.b * lk)


## Lay down a point on stream 0 or 1. `strength` 0..1 sets how opaque the trail is (0 at low altitude).
func add_point(p: Vector3, strength: float, lane: int = 0) -> void:
	if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
		return
	var n: int = _pts.size() if lane == 0 else _pts2.size()
	var last: Vector3 = _pts[n - 1] if lane == 0 and n > 0 else (_pts2[n - 1] if n > 0 else Vector3.INF)
	if n == 0 or last.distance_to(p) >= STEP:
		if lane == 0:
			_pts.append(p)
			_age.append(0.0)
			_str.append(strength)
			if _pts.size() > MAX_POINTS:
				var cut: int = _pts.size() - SOFT_POINTS
				_pts = _pts.slice(cut)
				_age = _age.slice(cut)
				_str = _str.slice(cut)
		else:
			_pts2.append(p)
			_age2.append(0.0)
			_str2.append(strength)
			if _pts2.size() > MAX_POINTS:
				var cut2: int = _pts2.size() - SOFT_POINTS
				_pts2 = _pts2.slice(cut2)
				_age2 = _age2.slice(cut2)
				_str2 = _str2.slice(cut2)
		_dirty = true


func _process(delta: float) -> void:
	var n: int = _pts.size()
	var n2: int = _pts2.size()
	if n == 0 and n2 == 0:
		return
	_tint_t -= delta
	if _tint_t <= 0.0:
		_tint_t = 0.5
		if _mat != null:
			_mat.set_shader_parameter("contrail_tint", _cloud_tint())
	for i in n:
		_age[i] += delta
	for i in n2:
		_age2[i] += delta
	var drop: int = 0
	while drop < n and _age[drop] > life:
		drop += 1
	if drop > 0:
		_pts = _pts.slice(drop)
		_age = _age.slice(drop)
		_str = _str.slice(drop)
	var drop2: int = 0
	while drop2 < n2 and _age2[drop2] > life:
		drop2 += 1
	if drop2 > 0:
		_pts2 = _pts2.slice(drop2)
		_age2 = _age2.slice(drop2)
		_str2 = _str2.slice(drop2)
	if _pts.is_empty() and _pts2.is_empty():
		queue_free()          # world-hosted trail has faded away
		return

	# Pick up a finished worker build. Nothing here touches the rendering server from the worker.
	if _task_id >= 0 and WorkerThreadPool.is_task_completed(_task_id):
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		var res: Dictionary = _job.result if _job != null else {}
		_job = null
		_apply_result(res)

	if _pts.size() < 2 and _pts2.size() < 2:
		if _task_id < 0:
			_mesh.clear_surfaces()
		return

	_rb -= delta
	if _rb <= 0.0 and _task_id < 0:
		var far: bool = false
		var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
		var eye: Vector3 = cam.global_position if cam != null else Vector3.ZERO
		if cam != null:
			var best: float = INF
			if _pts.size() > 0:
				best = minf(best, eye.distance_squared_to(_pts[0]))
				best = minf(best, eye.distance_squared_to(_pts[_pts.size() - 1]))
			if _pts2.size() > 0:
				best = minf(best, eye.distance_squared_to(_pts2[0]))
				best = minf(best, eye.distance_squared_to(_pts2[_pts2.size() - 1]))
			far = best > 14000.0 * 14000.0
		_rb = REBUILD_S if _dirty and not far else IDLE_REBUILD_S
		_dirty = false
		_start_build(eye)


func _start_build(eye: Vector3) -> void:
	var job := BuildJob.new()
	job.pts = _pts.duplicate()
	job.ages = _age.duplicate()
	job.strs = _str.duplicate()
	job.pts2 = _pts2.duplicate()
	job.ages2 = _age2.duplicate()
	job.strs2 = _str2.duplicate()
	job.eye = eye
	job.life = life
	job.near_w = NEAR_HALF_W
	job.far_w = FAR_HALF_W
	job.min_px = MIN_PX_W
	job.max_half = MAX_HALF_W
	_job = job
	var id: int = WorkerThreadPool.add_task(job.run, false, "contrail")
	if id < 0:
		job.run()               # pool unavailable: build once on the main thread
		_job = null
		_task_id = -1
		_apply_result(job.result)
	else:
		_task_id = id


func _apply_result(res: Dictionary) -> void:
	if _pts.size() < 2 and _pts2.size() < 2:
		_mesh.clear_surfaces()
		return
	if not bool(res.get("valid", false)):
		_pts.clear()
		_age.clear()
		_str.clear()
		_pts2.clear()
		_age2.clear()
		_str2.clear()
		_mesh.clear_surfaces()
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = res.get("verts", PackedVector3Array())
	arrays[Mesh.ARRAY_TEX_UV] = res.get("uvs", PackedVector2Array())
	arrays[Mesh.ARRAY_TEX_UV2] = res.get("uv2s", PackedVector2Array())
	arrays[Mesh.ARRAY_INDEX] = res.get("idx", PackedInt32Array())
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
