class_name ContrailRibbon
extends MeshInstance3D
## A soft, widening vapour plume: a world-space ribbon that starts thin and dense at the engine, then
## spreads, wanders and breaks into wisps as it ages. Vertex generation runs on the WorkerThreadPool;
## only the finished mesh upload happens on the main thread.

var life: float = 120.0     # seconds a point stays in the trail: long, high-altitude streaks
const STEP := 7.0           # metres of flight between samples
const NEAR_HALF_W := 0.8    # half-width at the aircraft: starts as a thin wisp
const FAR_HALF_W := 11.0    # half-width once the vapour has spread
const MIN_PX_W := 0.0019    # half-width per metre of camera distance: keeps a far trail ~4 px wide
const REBUILD_S := 0.066
const IDLE_REBUILD_S := 0.25   # no fresh points (out of range): fade the existing trail at a quarter of the cost
const MAX_POINTS := 4500       # hard bound per ribbon (a warp or a very fast aircraft can never grow it forever)
const SOFT_POINTS := 3900
const MAX_HALF_W := 48.0       # farthest the distance-widening may take the ribbon half-width

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

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
	ALBEDO = mix(vec3(0.66, 0.72, 0.82), vec3(1.0), profile * 0.8 + 0.2);
	ALPHA = clamp(alpha, 0.0, 0.34);
}
"""


## Worker-thread job. It owns copies of the point data, so the main thread can keep appending and
## ageing points while the geometry is generated.
class BuildJob extends RefCounted:
	var pts: PackedVector3Array
	var ages: PackedFloat32Array
	var strs: PackedFloat32Array
	var eye: Vector3
	var life: float
	var near_w: float
	var far_w: float
	var min_px: float
	var max_half: float
	var result: Dictionary = {}

	func run() -> void:
		var n: int = pts.size()
		if n < 2:
			result = {"valid": false}
			return
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var uv2s := PackedVector2Array()
		verts.resize(n * 2)
		uvs.resize(n * 2)
		uv2s.resize(n * 2)
		for i in n:
			var p: Vector3 = pts[i]
			if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
				result = {"valid": false}
				return
			var age_norm: float = clampf(ages[i] / life, 0.0, 1.0)
			var dir: Vector3 = pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
			if dir.length_squared() < 0.000001:
				dir = Vector3.FORWARD
			var dn: Vector3 = dir.normalized()
			var right: Vector3 = dn.cross(Vector3.UP)
			if right.length_squared() < 0.000001:
				right = Vector3.RIGHT
			right = right.normalized()
			# A slow, smooth wander as it ages; no per-point zig-zag or puffing.
			var spread: float = smoothstep(0.0, 0.55, age_norm)
			p += right * (sin(float(i) * 0.09 + ages[i] * 0.30) * (0.2 + 1.8 * age_norm))
			p += Vector3.UP * (cos(float(i) * 0.07 + ages[i] * 0.22) * (0.1 + 0.8 * age_norm))
			var side: Vector3 = dir.cross(eye - p)
			if side.length_squared() < 0.000001:
				side = Vector3.UP
			side = side.normalized()
			var half_w: float = lerpf(near_w, far_w, spread)
			# Very gentle edge variation; the silhouette expands smoothly rather than bulging point to point.
			var edge_var: float = 0.94 + 0.10 * sin(float(i) * 0.06 + age_norm * 1.2)
			var lw: float = half_w * edge_var
			var rw: float = half_w * (1.88 - edge_var)
			var min_w: float = eye.distance_to(p) * min_px
			lw = minf(maxf(lw, min_w), max_half)
			rw = minf(maxf(rw, min_w), max_half)
			var v: float = float(i) * 0.33
			verts[i * 2] = p - side * lw
			verts[i * 2 + 1] = p + side * rw
			uvs[i * 2] = Vector2(0.0, v)
			uvs[i * 2 + 1] = Vector2(1.0, v)
			uv2s[i * 2] = Vector2(age_norm, strs[i])
			uv2s[i * 2 + 1] = Vector2(age_norm, strs[i])
		result = {"valid": true, "verts": verts, "uvs": uvs, "uv2s": uv2s}


var _pts: PackedVector3Array = PackedVector3Array()
var _age: PackedFloat32Array = PackedFloat32Array()
var _str: PackedFloat32Array = PackedFloat32Array()
var _rb: float = 0.0
var _dirty: bool = false
var _mesh: ArrayMesh = ArrayMesh.new()
var _mat: ShaderMaterial
var _task_id: int = -1
var _job: BuildJob = null


func _ready() -> void:
	top_level = true            # points are in world space
	mesh = _mesh
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Lay down a point at world position `p`. `strength` 0..1 sets how opaque the trail is (0 at low altitude).
func add_point(p: Vector3, strength: float) -> void:
	if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
		return
	var n: int = _pts.size()
	if n == 0 or _pts[n - 1].distance_to(p) >= STEP:
		_pts.append(p)
		_age.append(0.0)
		_str.append(strength)
		_dirty = true
		if _pts.size() > MAX_POINTS:
			var cut: int = _pts.size() - SOFT_POINTS
			_pts = _pts.slice(cut)
			_age = _age.slice(cut)
			_str = _str.slice(cut)


func _process(delta: float) -> void:
	var n: int = _pts.size()
	if n == 0:
		return
	for i in n:
		_age[i] += delta
	var drop: int = 0
	while drop < n and _age[drop] > life:
		drop += 1
	if drop > 0:
		_pts = _pts.slice(drop)
		_age = _age.slice(drop)
		_str = _str.slice(drop)
	if _pts.is_empty():
		queue_free()          # world-hosted trail has faded away
		return

	# Pick up a finished worker build. Nothing here touches the rendering server from the worker.
	if _task_id >= 0 and WorkerThreadPool.is_task_completed(_task_id):
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		var res: Dictionary = _job.result if _job != null else {}
		_job = null
		_apply_result(res)

	if _pts.size() < 2:
		if _task_id < 0:
			_mesh.clear_surfaces()
		return

	_rb -= delta
	if _rb <= 0.0 and _task_id < 0:
		var far: bool = false
		var m: int = _pts.size()
		var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
		var eye: Vector3 = cam.global_position if cam != null else Vector3.ZERO
		if cam != null:
			far = minf(eye.distance_squared_to(_pts[0]), eye.distance_squared_to(_pts[m - 1])) > 14000.0 * 14000.0
		_rb = REBUILD_S if _dirty and not far else IDLE_REBUILD_S
		_dirty = false
		_start_build(eye)


func _start_build(eye: Vector3) -> void:
	var job := BuildJob.new()
	job.pts = _pts.duplicate()
	job.ages = _age.duplicate()
	job.strs = _str.duplicate()
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
	if _pts.size() < 2:
		_mesh.clear_surfaces()
		return
	if not bool(res.get("valid", false)):
		_pts.clear()
		_age.clear()
		_str.clear()
		_mesh.clear_surfaces()
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = res.get("verts", PackedVector3Array())
	arrays[Mesh.ARRAY_TEX_UV] = res.get("uvs", PackedVector2Array())
	arrays[Mesh.ARRAY_TEX_UV2] = res.get("uv2s", PackedVector2Array())
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
