class_name DamFlood
extends Node3D
## Water pouring out of a breached dam. A surge front runs down the valley from the gap, lapping over the ground
## and then spreading across the floodplain. One grid mesh: cells behind the front sit DEPTH above the ground
## (with a raised lip at the front); cells the front has not reached yet are sunk below the terrain.
## Spawned by GroundStructure when a dam wall is destroyed (see DamFlood.spawn).

const NX: int = 40
const NZ: int = 56
const WIDTH: float = 380.0	  # valley width at the gap (m)
const LENGTH: float = 1400.0	# how far downstream the flood is modelled (m)
const SPEED: float = 26.0	   # front speed (m/s)
const DEPTH: float = 1.6		# depth of water behind the front (m)
const LIP: float = 4.0		  # height of the surge lip at the front (m)
const SINK: float = 3.0		 # dry cells sit this far under the ground
const FILL: float = 22.0		# flood surface above the valley floor (world units): it fills the valley bottom, not the hillsides

var dir: Vector3 = Vector3(0.0, 0.0, -1.0)
var right: Vector3 = Vector3(1.0, 0.0, 0.0)
var origin: Vector3 = Vector3.ZERO
var t: float = 0.0
var _ground: PackedFloat32Array = PackedFloat32Array()
var _world: PackedVector3Array = PackedVector3Array()
var _normals: PackedVector3Array = PackedVector3Array()
var _indices: PackedInt32Array = PackedInt32Array()
var _mi: MeshInstance3D = null
var _level: PackedFloat32Array = PackedFloat32Array()   # per row: the flood surface height (flat across the valley)
var _mat: ShaderMaterial = null
var _spray_acc: float = 0.0
const SPRAY_TIME: float = 120.0   # the gap keeps throwing spray and mist for two minutes


## Start a flood at a destroyed dam wall. Downstream is the wall's local -Z.
static func spawn(wall: Node3D) -> DamFlood:
	var f := DamFlood.new()
	var fwd: Vector3 = -wall.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		fwd = Vector3(0.0, 0.0, -1.0)
	f.dir = fwd.normalized()
	f.right = Vector3.UP.cross(f.dir).normalized()
	f.origin = wall.global_position + f.dir * 10.0
	f.origin.y = 0.0
	var host: Node = wall.get_tree().current_scene
	if host == null:
		host = wall.get_parent()
	host.add_child(f)
	f.global_transform = Transform3D.IDENTITY	 # vertices are then world coordinates
	return f


func _lateral(i: int, d: float) -> float:
	var s: float = float(i) / float(NX - 1) * 2.0 - 1.0
	var flare: float = 1.0 + 0.8 * d / LENGTH
	return s * WIDTH * 0.5 * flare


func _ready() -> void:
	_mi = MeshInstance3D.new()
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# churning muddy floodwater (shaders/flood.gdshader) instead of a flat pale sheet
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/flood.gdshader") as Shader
	_mat.set_shader_parameter("origin", origin)
	_mat.set_shader_parameter("flow_dir", dir)
	_mat.set_shader_parameter("speed", SPEED)
	_mi.material_override = _mat
	add_child(_mi)
	_ground.resize(NX * NZ)
	_world.resize(NX * NZ)
	_normals.resize(NX * NZ)
	for j in NZ:
		var d: float = float(j) / float(NZ - 1) * LENGTH
		for i in NX:
			var k: int = j * NX + i
			var p: Vector3 = origin + dir * d + right * _lateral(i, d)
			_world[k] = Vector3(p.x, 0.0, p.z)
			_ground[k] = GroundKit.ground_y(p.x, p.z)
			_normals[k] = Vector3.UP
	# one flat water level per cross-section, set by that section's valley floor and never rising downstream,
	# so the water fills the bottom of the valley with a natural shoreline instead of a sheet laid over the hills
	_level.resize(NZ)
	var prev: float = INF
	for j in NZ:
		var floor_y: float = INF
		for i in NX:
			floor_y = minf(floor_y, _ground[j * NX + i])
		var lv: float = minf(prev, floor_y + FILL)
		_level[j] = lv
		prev = lv
	for j in NZ - 1:
		for i in NX - 1:
			var a: int = j * NX + i
			var c: int = a + NX
			_indices.append(a)
			_indices.append(c)
			_indices.append(a + 1)
			_indices.append(a + 1)
			_indices.append(c)
			_indices.append(c + 1)


func _process(delta: float) -> void:
	t += delta
	var front: float = SPEED * t
	if _mat != null:
		_mat.set_shader_parameter("front", minf(front, LENGTH + 60.0))
	_spray(delta, front)
	var verts := PackedVector3Array()
	verts.resize(NX * NZ)
	for j in NZ:
		var d: float = float(j) / float(NZ - 1) * LENGTH
		var wet: bool = d <= front
		var lip: float = LIP * exp(-pow((d - front) / 18.0, 2.0))
		for i in NX:
			var k: int = j * NX + i
			var w: Vector3 = _world[k]
			var lv: float = _level[j] + lip
			var y: float = lv if (wet and _ground[k] < lv - 0.2) else _ground[k] - SINK
			verts[k] = Vector3(w.x, y, w.z)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = _normals
	arr[Mesh.ARRAY_INDEX] = _indices
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mi.mesh = am


## Spray and mist: a plume of white spray thrown up where the reservoir pours through the gap (it climbs above
## the wall and drifts as mist), and spray kicked up along the surge front as it runs down the valley.
func _spray(delta: float, front: float) -> void:
	if t > SPRAY_TIME:
		return
	_spray_acc += delta
	var fade: float = 1.0 - smoothstep(SPRAY_TIME * 0.5, SPRAY_TIME, t)
	while _spray_acc >= 0.06:
		_spray_acc -= 0.06
		# the curtain at the gap
		var gp: Vector3 = origin + right * randf_range(-WIDTH * 0.22, WIDTH * 0.22) + dir * randf_range(0.0, 40.0)
		gp.y = GroundKit.ground_y(gp.x, gp.z) + randf_range(4.0, 30.0)
		FX.puffs.spawn(gp, Vector3(randf_range(-3, 3), randf_range(10.0, 22.0), randf_range(-3, 3)) + dir * 8.0, randf_range(3.0, 5.0),
			12.0, randf_range(40.0, 70.0), Color(0.93, 0.95, 0.97, 0.75 * fade), Color(0.88, 0.91, 0.94, 0.0), 0.55, 2.5, 0.35)
		# high drifting mist above the breach
		if randf() < 0.25:
			var mp: Vector3 = origin + right * randf_range(-WIDTH * 0.3, WIDTH * 0.3)
			mp.y = GroundKit.ground_y(mp.x, mp.z) + randf_range(40.0, 90.0)
			FX.puffs.spawn(mp, Vector3(randf_range(-2, 2), 3.0, randf_range(-2, 2)), randf_range(8.0, 12.0), 30.0, 90.0,
				Color(0.9, 0.92, 0.95, 0.28 * fade), Color(0.9, 0.92, 0.95, 0.0), 0.3, 0.0, 0.1)
		# spray along the surge front while it is still in the modelled valley
		if front < LENGTH:
			var d: float = front - randf_range(0.0, 20.0)
			var fp: Vector3 = origin + dir * d + right * _lateral(randi() % NX, maxf(d, 0.0))
			fp.y = _level[clampi(int(maxf(d, 0.0) / LENGTH * float(NZ - 1)), 0, NZ - 1)] + LIP
			FX.puffs.spawn(fp, dir * SPEED * 0.6 + Vector3(0, randf_range(4.0, 9.0), 0), randf_range(1.6, 2.6), 8.0, 26.0,
				Color(0.88, 0.88, 0.84, 0.75), Color(0.8, 0.8, 0.76, 0.0), 0.7, 3.0, 0.4)
